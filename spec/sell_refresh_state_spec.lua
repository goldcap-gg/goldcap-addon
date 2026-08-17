local helper = require("spec.spec_helper")

describe("Sell refresh state fence", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local function refreshState(GC) return upvalue(GC.Sell.OnThrottleReady, "refresh") end

  local function load(now, sent, cache, keyInfo)
    _G.time = function() return now.value end
    _G.C_AuctionHouse = {
      QueryOwnedAuctions = function() sent.owned = sent.owned + 1 end,
      GetOwnedAuctions = function() return {} end,
    }
    local GC = {
      Sell = {}, Sniper = { IsAHOpen = function() return true end, IsBusy = function() return false end },
      QuoteCache = {
        MAX_AGE_SECONDS = 10,
        Set = function(_, itemID, unit) cache[itemID] = unit end,
        Clear = function() for key in pairs(cache) do cache[key] = nil end end,
      },
      SellPositions = {
        NormalizeOwnedLots = function() return {} end,
        -- bagQty matters: the pricing walk only asks the server about positions
        -- there is something to do with -- stock in the bags, or a live listing
        -- that could be reposted. A full inventory is easily sixty sellable
        -- stacks and the walk repeats, so pricing rows nobody will act on would
        -- crowd out the Sniper's own scans.
        Build = function() return { { itemID = 42, positionKey = "commodity:42", bagQty = 5 } } end,
      },
    }
    helper.loadModule("UI/SellFrame.lua", GC)
    local driver = {
      isReady = function() return true end,
      keyInfo = keyInfo,
      send = function(itemID) sent.keys[#sent.keys + 1] = itemID end,
      item = function() return 111 end, itemLevels = function() return nil end,
      commodity = function() return 222 end, commodityLevels = function() return nil end,
    }
    set(upvalue(GC.Sell.OnThrottleReady, "advanceQuote"), "driver", driver)
    return GC
  end

  after_each(function() _G.time, _G.C_AuctionHouse, _G.C_Timer = os.time, nil, nil end)

  it("waits for item key info and then sends that same key once", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local keyed = false
    local GC = load(now, sent, cache, function() return keyed and { isCommodity = false } or nil end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.equal("waiting_key", refreshState(GC).phase)
    assert.same({}, sent.keys)
    keyed = true
    GC.Sell.OnItemKeyInfo(42)
    assert.same({ 42 }, sent.keys)
    assert.equal("waiting_result", refreshState(GC).phase)
  end)

  it("drains a timed-out untagged result before allowing the same key again", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    now.value = 111
    GC.Sell.OnThrottleReady()
    -- One item failing is not the pass failing. It used to park the machine in
    -- "error" and stop, so with a tab full of bag stock the items further down
    -- the queue were never reached. The pass carries on; with nothing else
    -- queued here it simply finishes. The drain fence below is unchanged.
    assert.equal("done", refreshState(GC).phase)
    GC.Sell.Refresh()
    assert.same({ 42 }, sent.keys)
    GC.Sell.OnItemSearchResults(42)
    assert.is_nil(cache[42])
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42, 42 }, sent.keys)
  end)

  it("prices one commodity request and reports exact progress", function()
    local now, sent, cache, status = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    set(GC.Sell.Refresh, "setStatus", function(text) status[#status + 1] = text end)
    GC.Sell.Refresh()
    assert.equal(1, sent.owned)
    GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    assert.equal("Pricing 1/1…", status[#status])
    GC.Sell.OnCommoditySearchResults(42)
    assert.equal(222, cache[42])
    assert.equal("done", refreshState(GC).phase)
    assert.equal("Prices up to date", status[#status])
  end)

  -- Pressing the button means "do it now". It used to refuse while any phase
  -- other than idle/done/error was set, and three of those phases wait on an
  -- event that can simply never arrive -- an owned-auctions query, an item-key
  -- lookup, a drain -- so one unanswered call made Refresh dead for the session.
  it("a second press restarts the run instead of being swallowed", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.Sell.Refresh()
    assert.equal("owned", refreshState(GC).phase)
    GC.Sell.Refresh()
    assert.equal(2, sent.owned)
    assert.equal("owned", refreshState(GC).phase)
  end)

  it("the automatic repeat stands aside for a run already in flight", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.Sell.Refresh()
    GC.Sell.Refresh(true)
    assert.equal(1, sent.owned)
  end)

  -- Reported from the game: "refresh hangs, works after a reload, and it happens
  -- when auto scan is on". Under Auto the full browse scan runs back to back
  -- with a two-second breather forever, and the walk stood aside for IsBusy --
  -- which counts that scan. So the Sell tab priced nothing at all while Auto was
  -- on, and Refresh only ever worked when a reload happened to catch a gap.
  it("prices through a background scan, and only yields to a purchase", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local critical = false
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.Sniper.IsBusy = function() return true end -- a full scan is always running
    GC.Sniper.IsSearchCritical = function() return critical end

    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    assert.equal("waiting_result", refreshState(GC).phase)

    -- A purchase does own the slot, and is short.
    critical = true
    GC.Sell.OnCommoditySearchResults(42)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)

    critical = false
    GC.Sell.OnThrottleReady()
    assert.same({ 42, 42 }, sent.keys)
  end)

  it("waits for throttle and fails closed when the auction house is unavailable", function()
    local now, sent, cache, status = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    local ready = true
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    local driver = upvalue(advance, "driver")
    driver.isReady = function() return ready end
    set(GC.Sell.Refresh, "setStatus", function(text) status[#status + 1] = text end)
    GC.Sell.Refresh()
    ready = false
    GC.Sell.OnOwnedAuctions()
    assert.same({}, sent.keys)
    ready = true; GC.Sell.OnThrottleReady()
    assert.same({ 42 }, sent.keys)
    GC.Sell.OnItemSearchResults(42)
    GC.Sniper.IsAHOpen = function() return false end
    GC.Sell.Refresh()
    assert.equal("Auction House is not open", status[#status])
  end)

  it("parks the cold-start owned-auction refresh until throttle-ready and sends it once", function()
    local now, sent, cache, status = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    local ready = false
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    local driver = upvalue(advance, "driver")
    driver.isReady = function() return ready end
    set(GC.Sell.Refresh, "setStatus", function(text) status[#status + 1] = text end)

    GC.Sell.Refresh()
    assert.equal(0, sent.owned)
    assert.equal("waiting_owned", refreshState(GC).phase)
    assert.equal("Waiting for Auction House…", status[#status])

    ready = true
    GC.Sell.OnThrottleReady()
    assert.equal(1, sent.owned)
    assert.equal("owned", refreshState(GC).phase)

    GC.Sell.OnThrottleReady()
    assert.equal(1, sent.owned)
  end)

  it("cancels a parked cold-start refresh before a later throttle-ready event", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local ready = false
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    local driver = upvalue(advance, "driver")
    driver.isReady = function() return ready end

    GC.Sell.Refresh()
    assert.equal(0, sent.owned)
    GC.Sell.Reset()

    ready = true
    GC.Sell.OnThrottleReady()
    assert.equal(0, sent.owned)
    assert.equal("idle", refreshState(GC).phase)
  end)

  it("uses a real request timer to tombstone a sent quote without throttle activity", function()
    local now, sent, cache, timers, status = { value = 100 }, { owned = 0, keys = {} }, {}, {}, {}
    -- Delay-keyed, not index-keyed: Refresh also arms a phase watchdog now (a
    -- phase that answers no event used to wedge the button for good), so "the
    -- request timer" has to be identified by the window it waits, not by being
    -- the only timer anyone registered.
    _G.C_Timer = { After = function(seconds, callback)
      timers[#timers + 1] = { seconds = seconds, callback = callback }
    end }
    local function fire(seconds)
      for index = #timers, 1, -1 do
        if timers[index].seconds == seconds then return timers[index].callback() end
      end
      error("no timer waiting " .. tostring(seconds) .. "s")
    end
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    set(GC.Sell.Refresh, "setStatus", function(text) status[#status + 1] = text end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    fire(10)
    assert.equal("done", refreshState(GC).phase)
    assert.equal("Prices up to date · 1 did not answer", status[#status])
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    GC.Sell.OnItemSearchResults(42)
    assert.is_nil(cache[42])
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42, 42 }, sent.keys)
  end)

  it("fails closed for an empty search result and clears only that key", function()
    local now, sent, cache, status = { value = 100 }, { owned = 0, keys = {} }, { [7] = 999 }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    local driver = upvalue(advance, "driver")
    driver.item = function() return nil end
    set(GC.Sell.Refresh, "setStatus", function(text) status[#status + 1] = text end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions(); GC.Sell.OnItemSearchResults(42)
    -- An answer that came back empty means there is genuinely nothing on sale,
    -- so this key's stale quote goes -- unlike a timeout, which teaches nothing
    -- and leaves any quote already on hand to age visibly.
    assert.equal("done", refreshState(GC).phase)
    assert.is_nil(cache[42])
    assert.equal(999, cache[7])
    assert.equal("Prices up to date · 1 did not answer", status[#status])
  end)

  it("makes an old request timer and result inert after Reset", function()
    local now, sent, cache, timers = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    _G.C_Timer = { After = function(seconds, callback)
      timers[#timers + 1] = { seconds = seconds, callback = callback }
    end }
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    GC.Sell.Reset()
    for _, timer in ipairs(timers) do timer.callback() end
    GC.Sell.OnItemSearchResults(42)
    assert.equal("idle", refreshState(GC).phase)
    assert.is_nil(cache[42])
  end)

  it("[I1] drains pre-Reset request A before same-key request B can proceed", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)

    GC.Sell.Reset()
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    assert.equal("draining", refreshState(GC).phase)

    GC.Sell.OnItemSearchResults(42)
    assert.is_nil(cache[42])
    assert.same({ 42, 42 }, sent.keys)
    assert.equal("waiting_result", refreshState(GC).phase)

    GC.Sell.OnItemSearchResults(42)
    assert.equal(111, cache[42])
    assert.equal("done", refreshState(GC).phase)
  end)

  it("[I1] lets the next same-key run send after an invalid terminal was consumed", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    local driver = upvalue(advance, "driver")
    driver.item = function() return nil end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions(); GC.Sell.OnItemSearchResults(42)
    assert.equal("done", refreshState(GC).phase)
    assert.same({ 42 }, sent.keys)

    driver.item = function() return 111 end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42, 42 }, sent.keys)
    assert.equal("waiting_result", refreshState(GC).phase)
  end)

  -- The walk used to re-ask the server about EVERY actionable position on every 5-second
  -- pass -- freshness only decided the ORDER, never the membership -- so a tab of two dozen
  -- items ground through "Pricing N/24" continuously even when every price on screen was
  -- seconds old. A pass now contains only what actually needs asking: never-priced rows and
  -- rows whose quote has aged past the re-walk threshold. Steady state is an empty pass.
  it("prices only never-priced and aged rows, never a quote that is still fresh", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.SellPositions.Build = function()
      return {
        { itemID = 43, positionKey = "commodity:43", bagQty = 5, displayMarketUnit = 100, quoteAge = 3 },
        { itemID = 42, positionKey = "commodity:42", bagQty = 5 },
        { itemID = 44, positionKey = "commodity:44", bagQty = 5, displayMarketUnit = 100, quoteAge = 31 },
      }
    end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    -- Never-priced first, then the aged one; the 3-second-old quote is not asked about at all.
    assert.same({ 42, 44 }, refreshState(GC).queue)
  end)

  it("finishes an all-fresh pass immediately instead of re-pricing the whole tab", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.SellPositions.Build = function()
      return { { itemID = 43, positionKey = "commodity:43", bagQty = 5, displayMarketUnit = 100, quoteAge = 3 } }
    end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.equal("done", refreshState(GC).phase)
    assert.same({}, sent.keys)
  end)

  it("observes commodity and variant owned lots with the exact active scope", function()
    local now, sent, cache, observed = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.SellPositions.NormalizeOwnedLots = function()
      return { { itemID = 42, positionKey = "commodity:42" }, { itemID = 7, positionKey = "item:7:100:3:0" } }
    end
    GC.Acquisitions = { ObserveOwnedPosition = function(...) observed[#observed + 1] = { ... } end }
    GC.Ledger = { Context = function() return { char = "A-R", region = "eu" } end }
    GC.Sell.OnOwnedAuctions()
    assert.same({
      { "commodity:42", 42, "Item 42", "A-R", "eu", 100 },
      { "item:7:100:3:0", 7, "Item 7", "A-R", "eu", 100 },
    }, observed)
  end)
end)
