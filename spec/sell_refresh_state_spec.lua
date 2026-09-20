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

  -- A throttle flag that has stopped changing puts the whole addon on one forced send per
  -- window per consumer (Core/Util.lua). The permit used to be a single global one handed out
  -- by the mere act of ASKING whether the system was ready -- and the Sniper's arbiter asks
  -- immediately before this tab does, on every ready event, so this walk never once got one:
  -- "PRICING… 0/20" through a hundred and twenty ready events on a live client.
  it("holds its place when the throttle pacing gives the turn to somebody else", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local retries = 0
    _G.C_Timer = { After = function() retries = retries + 1 end }
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    local mayClaim = false
    upvalue(advance, "driver").claimSend = function() return mayClaim end

    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({}, sent.keys)   -- nothing sent...
    assert.is_true(retries > 0)  -- ...and it is coming back for its own turn
    assert.equal(0, refreshState(GC).index) -- the queue position is untouched

    mayClaim = true
    GC.Sell.OnThrottleReady()
    assert.same({ 42 }, sent.keys)
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

  -- Reported from the game: "PRICING…" with two rows priced and the other 38 blank for as
  -- long as the tab stayed open. A yield to a purchase had no way back except the phase
  -- watchdog, which restarted the pass from item 1 -- straight into the same yield.
  it("a yield to a purchase asks again by itself, from the same place in the queue", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local timers = {}
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    local critical = true
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.Sniper.IsSearchCritical = function() return critical end

    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({}, sent.keys) -- yielded to the purchase
    local armed = #timers
    assert.is_true(armed >= 1)

    -- The purchase ends with no event of its own; the retry is what notices.
    critical = false
    for i = 1, armed do timers[i]() end
    assert.same({ 42 }, sent.keys)
  end)

  it("a retry armed by a walk that was since restarted does nothing", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local timers = {}
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    local critical = true
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.Sniper.IsSearchCritical = function() return critical end

    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    local stale = timers[#timers]
    GC.Sell.Refresh() -- a new generation: the old retry must not drive it
    critical = false
    stale()
    assert.same({}, sent.keys)
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

  -- Starving on a busy search slot is the walk working correctly, not stalling: the 15s
  -- PHASE_WATCHDOG_SECONDS must not misreport "Auction House did not answer" while nothing
  -- was ever sent. advanceQuote now calls markProgress() on that path (same as the
  -- purchase-yield branch) and says why, once per walk rather than on every tick.
  it("reports a busy search slot once per walk instead of tripping the watchdog", function()
    local now, sent, cache, status = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    local ready = true
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    local driver = upvalue(advance, "driver")
    driver.isReady = function() return ready end
    set(GC.Sell.Refresh, "setStatus", function(text) status[#status + 1] = text end)

    GC.Sell.Refresh()
    ready = false
    GC.Sell.OnOwnedAuctions() -- enters pricing and immediately starves on the busy slot
    assert.equal("Waiting for the Auction House…", status[#status])
    assert.equal(100, refreshState(GC).progressAt) -- markProgress ran: the watchdog will not fire
    assert.same({}, sent.keys)

    local noticedAt = #status
    now.value = 105
    GC.Sell.OnThrottleReady() -- still not ready: progress advances again, notice does not repeat
    assert.equal(noticedAt, #status)
    assert.equal(105, refreshState(GC).progressAt)

    ready = true
    GC.Sell.OnThrottleReady() -- the slot frees up: the walk proceeds
    assert.same({ 42 }, sent.keys)
  end)

  it("beginQuoteWalk resets the waiting-noted flag so the next walk can report again", function()
    local now, sent, cache, status = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    local ready = true
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    local driver = upvalue(advance, "driver")
    driver.isReady = function() return ready end
    set(GC.Sell.Refresh, "setStatus", function(text) status[#status + 1] = text end)

    GC.Sell.Refresh()
    ready = false
    GC.Sell.OnOwnedAuctions()
    assert.equal("Waiting for the Auction House…", status[#status])
    assert.is_true(refreshState(GC).waitingNoted)

    ready = true
    GC.Sell.OnThrottleReady()
    assert.same({ 42 }, sent.keys)
    GC.Sell.OnCommoditySearchResults(42)
    assert.equal("done", refreshState(GC).phase)

    -- A fresh walk clears the flag: starving again on the next round reports again.
    GC.Sell.Refresh()
    ready = false
    GC.Sell.OnOwnedAuctions()
    local notices = 0
    for _, text in ipairs(status) do
      if text == "Waiting for the Auction House…" then
        notices = notices + 1
      end
    end
    assert.equal(2, notices)
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
    -- The walk's OWN repeat, which is what the age gate is for.
    GC.Sell.Refresh(true)
    -- Never-priced first, then the aged one; the 3-second-old quote is not asked about at all.
    assert.same({ 42, 44 }, refreshState(GC).queue)
  end)

  -- Unresolved positions were excluded from pricing wholesale, which left every tiered
  -- reagent caught in identity repair (Progenium Ore, Bismuth...) at "—" forever -- reading
  -- as the walk being broken. Identity questions are about COST; a commodity's market price
  -- is exact for its itemID no matter whose stock it is. Variant ITEMS stay excluded: a
  -- basic-key quote can be a different variant's price, and a wrong number is worse than none.
  it("prices an unresolved commodity holding stock, never an unresolved variant item", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.SellPositions.Build = function()
      return {
        { itemID = 51, positionKey = "commodity:51", bagQty = 3, unresolved = true },
        { itemID = 52, positionKey = "item:52:100:0:0", bagQty = 1, unresolved = true },
        { itemID = 53, positionKey = "commodity:53", unresolved = true }, -- stockless ghost
      }
    end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 51 }, refreshState(GC).queue)
  end)

  -- A quote restored after a reload is a number with no book under it. While it was still
  -- "fresh" the walk left it alone, so for half a minute after every reload the rows had prices
  -- and no queue standing, and their panels no book.
  it("still asks about a fresh quote that was restored without its book", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.SellPositions.Build = function()
      return { { itemID = 43, positionKey = "commodity:43", bagQty = 5, displayMarketUnit = 100, quoteAge = 3 } }
    end
    upvalue(GC.Sell.FoldBulk, "quotes")[43] = { unit = 100, at = 97, bookless = true }
    GC.Sell.Refresh(true)
    assert.same({ 43 }, refreshState(GC).queue)
  end)

  -- The queue covers both decks. Asked in order of need alone, a walk of twenty-seven spent its
  -- first seconds on live lots while the ten rows of bag stock on screen waited for theirs.
  it("asks about the deck on screen before the other one, in the order it is drawn", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.SellPositions.Build = function()
      return {
        { itemID = 50, positionKey = "commodity:50", listedQty = 9 },                 -- never priced, other deck
        { itemID = 42, positionKey = "commodity:42", bagQty = 5, displayMarketUnit = 100, quoteAge = 40 },
        { itemID = 43, positionKey = "commodity:43", bagQty = 5 },
      }
    end
    local places = upvalue(GC.Sell.Refresh, "rowPlaces")
    places["commodity:42"], places["commodity:43"] = 1, 2
    GC.Sell.Refresh(true)
    assert.same({ 42, 43, 50 }, refreshState(GC).queue)
  end)

  it("finishes an all-fresh pass immediately instead of re-pricing the whole tab", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.SellPositions.Build = function()
      return { { itemID = 43, positionKey = "commodity:43", bagQty = 5, displayMarketUnit = 100, quoteAge = 3 } }
    end
    GC.Sell.Refresh(true)
    assert.equal("done", refreshState(GC).phase)
    assert.same({}, sent.keys)
  end)

  -- The 5-second repeat used to re-run the whole manual path, including a throttled
  -- QueryOwnedAuctions round trip and its wait, before a single price was asked -- per tick.
  -- Owned lots change through OWNED_AUCTIONS_UPDATED/AUCTION_CANCELED events anyway, so the
  -- repeat now prices immediately; only a manual press re-queries the listings.
  it("an automatic pass skips the owned-auctions round trip and prices immediately", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.equal(1, sent.owned)
    GC.Sell.OnCommoditySearchResults(42)
    assert.equal("done", refreshState(GC).phase)
    now.value = 140
    GC.Sell.Refresh(true)
    assert.equal(1, sent.owned) -- no second owned query
    assert.equal("waiting_result", refreshState(GC).phase) -- already asking prices
    assert.same({ 42, 42 }, sent.keys)
  end)

  -- An item the auction house answered "nothing listed" about used to be indistinguishable
  -- from one never asked: its cache entry was wiped, so EVERY pass re-asked it (or worse,
  -- burned the full request timeout on it), which is what ground a tab full of niche items
  -- to a crawl. The empty answer is now remembered for a while and skipped like a fresh
  -- quote.
  it("does not re-ask an item that answered 'nothing listed' until that answer ages", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    upvalue(advance, "driver").commodity = function() return nil end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    GC.Sell.OnCommoditySearchResults(42) -- the answer: nothing on sale
    assert.equal("done", refreshState(GC).phase)
    GC.Sell.Refresh(true)
    assert.equal("done", refreshState(GC).phase) -- nothing due: the pass finishes instantly
    assert.same({ 42 }, sent.keys)
    now.value = 170 -- past the remembered-answer window
    GC.Sell.Refresh(true)
    assert.same({ 42, 42 }, sent.keys)
  end)

  -- The drain fence exists so a LATE answer cannot be credited to a new request for the same
  -- item -- but it was permanent, cleared only by the very event that never comes for a
  -- request that timed out silently. One such item wedged EVERY later pass: the walk reached
  -- it, parked in "draining" waiting for the ghost event, and the watchdog shot the pass --
  -- which is exactly "pressed Refresh several times, it stopped going anywhere, half the tab
  -- has no market price". Past a plausibility window the lost answer is not coming; lift the
  -- fence and ask again.
  it("lifts a drain fence whose lost answer is too old to still arrive", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    now.value = 111
    GC.Sell.OnThrottleReady() -- times out the request, leaves the drain tombstone
    assert.equal("done", refreshState(GC).phase)
    now.value = 140 -- well past any plausible late delivery
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42, 42 }, sent.keys)
    assert.equal("waiting_result", refreshState(GC).phase)
  end)

  it("a manual Refresh wipes remembered empty answers and re-asks for real", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    upvalue(advance, "driver").commodity = function() return nil end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    GC.Sell.OnCommoditySearchResults(42)
    assert.same({ 42 }, sent.keys)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42, 42 }, sent.keys) -- the player asked; the remembered answer must not gag it
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
  -- The fence branch used to be a dead end: it parked the machine in "draining" with no
  -- progress stamp and no way back -- advanceQuote refused the phase outright, so its own retry
  -- and OnThrottleReady's tail both bounced off it -- and the only exit was the 15s watchdog
  -- declaring the whole pass dead over one item.
  it("[S1] re-checks a drain fence on its own timer instead of wedging the pass", function()
    local now, sent, cache, timers = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    _G.C_Timer = { After = function(seconds, callback)
      timers[#timers + 1] = { seconds = seconds, callback = callback }
    end }
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    now.value = 111
    GC.Sell.OnThrottleReady() -- the request times out and leaves its drain tombstone
    now.value = 112
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    local state = refreshState(GC)
    assert.equal("draining", state.phase)
    -- Waiting behind a fence is the walk working, so the watchdog must not read it as an
    -- unanswered request.
    assert.equal(112, state.progressAt)
    local retry
    for _, timer in ipairs(timers) do if timer.seconds == 2 then retry = timer.callback end end
    assert.is_function(retry)
    now.value = 140 -- past the window in which the lost answer could still arrive
    retry()
    assert.same({ 42, 42 }, sent.keys)
    assert.equal("waiting_result", refreshState(GC).phase)
  end)

  -- A click on Post whose quote had aged out spliced its item INTO refresh.queue. The owned
  -- phase ends in a full rebuild of that array, so the item the player was standing on was the
  -- one thing the pass threw away.
  it("[S3] keeps a click's price request through the queue rebuild the owned phase ends in", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.SellPositions.Build = function()
      return { { itemID = 42, positionKey = "commodity:42", bagQty = 5 } }
    end
    local render = upvalue(GC.Sell.Attach, "renderRows")
    local startFor = upvalue(upvalue(render, "onPostClick"), "startQuoteRefreshFor")
    GC.Sell.Refresh() -- the owned phase: there is no queue to splice into yet
    startFor({ itemID = 77 })
    GC.Sell.OnOwnedAuctions()
    assert.same({ 77 }, sent.keys) -- the clicked item goes first, and is not lost
    GC.Sell.OnCommoditySearchResults(77)
    assert.same({ 77, 42 }, sent.keys)
  end)

  -- The same click, taken while the walk was waiting on an item key: the insert landed on the
  -- awaited item's own slot, so when that key arrived the walk stepped straight over the
  -- spliced item and re-asked the awaited one.
  it("[S3] answers a click's item next while the walk is waiting on an item key", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local keyed = {}
    local GC = load(now, sent, cache, function(itemID) return keyed[itemID] and { isCommodity = true } or nil end)
    GC.SellPositions.Build = function()
      return { { itemID = 42, positionKey = "commodity:42", bagQty = 5 } }
    end
    local render = upvalue(GC.Sell.Attach, "renderRows")
    local startFor = upvalue(upvalue(render, "onPostClick"), "startQuoteRefreshFor")
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.equal("waiting_key", refreshState(GC).phase)
    startFor({ itemID = 77 })
    keyed[42], keyed[77] = true, true
    GC.Sell.OnItemKeyInfo(42)
    assert.same({ 42 }, sent.keys) -- the awaited key is still the one that was waiting
    GC.Sell.OnCommoditySearchResults(42)
    assert.same({ 42, 77 }, sent.keys) -- and the click's item is next, not skipped
  end)

  -- startQuoteRefreshFor armed no watchdog at all, so an item whose key never arrived left the
  -- machine in waiting_key for the rest of the session: "PRICING…" with no automatic
  -- re-pricing, because Refresh(automatic) will not leave a set phase.
  it("[S2] a click's one-item price check arms the phase watchdog", function()
    local now, sent, cache, timers = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    _G.C_Timer = { After = function(seconds, callback)
      timers[#timers + 1] = { seconds = seconds, callback = callback }
    end }
    local GC = load(now, sent, cache, function() return nil end)
    local render = upvalue(GC.Sell.Attach, "renderRows")
    local startFor = upvalue(upvalue(render, "onPostClick"), "startQuoteRefreshFor")
    startFor({ itemID = 42 })
    assert.equal("waiting_key", refreshState(GC).phase)
    local watchdog
    for _, timer in ipairs(timers) do if timer.seconds == 15 then watchdog = timer.callback end end
    assert.is_function(watchdog)
    now.value = 200
    watchdog()
    assert.equal("error", refreshState(GC).phase)
  end)

  it("[S2] skips an item whose key never arrives instead of holding the whole pass", function()
    local now, sent, cache, timers = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    _G.C_Timer = { After = function(seconds, callback)
      timers[#timers + 1] = { seconds = seconds, callback = callback }
    end }
    local GC = load(now, sent, cache, function(itemID) return itemID == 43 and { isCommodity = true } or nil end)
    GC.SellPositions.Build = function()
      return { { itemID = 42, positionKey = "commodity:42", bagQty = 5 },
        { itemID = 43, positionKey = "commodity:43", bagQty = 5 } }
    end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.equal("waiting_key", refreshState(GC).phase)
    assert.same({}, sent.keys)
    local keyTimeout
    for _, timer in ipairs(timers) do if timer.seconds == 10 then keyTimeout = timer.callback end end
    assert.is_function(keyTimeout)
    now.value = 111
    keyTimeout()
    assert.same({ 43 }, sent.keys)
  end)

  -- Opening the auction house priced the whole Sell tab whether or not the player was looking
  -- at it -- up to forty throttled round trips on the same slot the Sniper's scans and the
  -- player's own searches use.
  it("[S8] does not price while the Sell tab is not the tab on screen", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    local parked = upvalue(advance, "walkParked")
    set(GC.Sell.Attach, "renderRows", function() end)
    set(parked, "container", { IsShown = function() return false end })
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    -- The owned-auctions read and the composition still happen: the tab badge depends on them
    -- and they cost no price query.
    assert.equal(1, sent.owned)
    assert.same({}, sent.keys)
    assert.equal("idle", refreshState(GC).phase)
    set(parked, "container", { IsShown = function() return true end })
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
  end)

  -- OWNED_AUCTIONS_UPDATED and AUCTION_CANCELED fire on their own schedule -- a lot expiring, a
  -- cancel from the Blizzard panel -- and every one of them used to stamp the walk's progress,
  -- which kept the watchdog quiet over a pricing request that was never coming back.
  it("[S13] an owned-auctions update does not feed a wedged pricing phase's watchdog", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.equal("waiting_result", refreshState(GC).phase)
    local stamped = refreshState(GC).progressAt
    now.value = 108
    GC.Sell.OnOwnedAuctions()
    assert.equal(stamped, refreshState(GC).progressAt)
  end)

  -- A zero read is not the same fact as a zero ANSWER: GetNum*SearchResults reports whatever
  -- result set the client holds for the key right now, and these events are raised by the
  -- Sniper's searches too. Gagging the item on that basis told the player the auction house had
  -- answered when it had not.
  it("[S6] will not call a zero read an answer the client cannot prove is complete", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local render = upvalue(GC.Sell.Attach, "renderRows")
    local driver = upvalue(upvalue(GC.Sell.OnThrottleReady, "advanceQuote"), "driver")
    driver.commodity = function() return nil end
    driver.hasFullResults = function() return false end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    GC.Sell.OnCommoditySearchResults(42)
    local rest = upvalue(render, "emptyAnswers")[42]
    assert.is_false(rest.answered)
    -- Fenced rather than gagged: our own reply may still be on the way.
    assert.is_table(refreshState(GC).drain["commodity:42"])
  end)

  it("[S6] does treat a zero read the client proves complete as a real 'nothing listed'", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local render = upvalue(GC.Sell.Attach, "renderRows")
    local driver = upvalue(upvalue(GC.Sell.OnThrottleReady, "advanceQuote"), "driver")
    driver.commodity = function() return nil end
    driver.hasFullResults = function() return true end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    GC.Sell.OnCommoditySearchResults(42)
    assert.is_true(upvalue(render, "emptyAnswers")[42].answered)
    assert.is_nil(refreshState(GC).drain["commodity:42"])
  end)

  -- A request that never came back was recorded exactly like a reply carrying no listings, so
  -- the tab told the player "Nothing listed on the AH right now" about an item the auction
  -- house had said nothing about at all.
  it("[S7] records a timeout as silence, not as an empty answer", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local render = upvalue(GC.Sell.Attach, "renderRows")
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    now.value = 111
    GC.Sell.OnThrottleReady()
    assert.is_false(upvalue(render, "emptyAnswers")[42].answered)
  end)

  it("[S10] dates a quote from the request, not from when its answer was handled", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local stamped
    GC.QuoteCache.Set = function(_, itemID, unit, at) cache[itemID] = unit; stamped = at end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    now.value = 106
    GC.Sell.OnCommoditySearchResults(42)
    assert.equal(222, cache[42])
    assert.equal(100, stamped)
  end)

  -- GetOwnedAuctions never reports whether an auction is a commodity, and GetItemKeyInfo
  -- answers nil until the client has cached that key -- so a lot filed itself under an
  -- `item:...` key while the same item's BAG stock, classified from the remembered answer, filed
  -- under `commodity:...`: two rows for one item, the listing holding no stock and the stock
  -- reading "not on hand".
  it("[S5] keys an owned lot from the remembered answer, and remembers a fresh one", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    GC.db = { commodityByItem = { [42] = true } }
    _G.C_AuctionHouse.GetItemKeyInfo = function(key)
      return key.itemID == 43 and { isCommodity = true } or nil
    end
    local classify = upvalue(GC.Sell.OnOwnedAuctions, "classifyOwnedAuctions")
    local auctions = { { itemKey = { itemID = 42 } }, { itemKey = { itemID = 43 } },
      { itemKey = { itemID = 44 } } }
    classify(auctions)
    assert.is_true(auctions[1].isCommodity) -- remembered, where GetItemKeyInfo had no answer
    assert.is_true(auctions[2].isCommodity)
    assert.is_true(GC.db.commodityByItem[43]) -- and the fresh answer is written back
    assert.is_nil(auctions[3].isCommodity) -- nobody can key it yet: left alone, never guessed
  end)

  it("[S18] Reset forgets the rested items, the skip count and a click's pending request", function()
    local now, sent, cache = { value = 100 }, { owned = 0, keys = {} }, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    local render = upvalue(GC.Sell.Attach, "renderRows")
    upvalue(upvalue(GC.Sell.OnThrottleReady, "advanceQuote"), "driver").commodity = function() return nil end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    GC.Sell.OnCommoditySearchResults(42)
    local state = refreshState(GC)
    state.priority[#state.priority + 1] = 99
    assert.is_table(upvalue(render, "emptyAnswers")[42])
    assert.equal(1, state.skipped)
    GC.Sell.Reset()
    assert.is_nil(upvalue(render, "emptyAnswers")[42])
    assert.same({}, state.priority)
    assert.equal(0, state.skipped)
  end)
end)
