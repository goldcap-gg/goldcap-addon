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
        Build = function() return { { itemID = 42, positionKey = "commodity:42" } } end,
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
    assert.equal("error", refreshState(GC).phase)
    GC.Sell.Refresh()
    assert.same({ 42 }, sent.keys)
    GC.Sell.OnItemSearchResults(42)
    assert.is_nil(cache[42])
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42, 42 }, sent.keys)
  end)

  it("prices one commodity request, rejects overlap, and reports exact progress", function()
    local now, sent, cache, status = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    local GC = load(now, sent, cache, function() return { isCommodity = true } end)
    set(GC.Sell.Refresh, "setStatus", function(text) status[#status + 1] = text end)
    GC.Sell.Refresh(); GC.Sell.Refresh()
    assert.equal(1, sent.owned)
    GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    assert.equal("Pricing 1/1…", status[#status])
    GC.Sell.OnCommoditySearchResults(42)
    assert.equal(222, cache[42])
    assert.equal("done", refreshState(GC).phase)
    assert.equal("Updated just now", status[#status])
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
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    set(GC.Sell.Refresh, "setStatus", function(text) status[#status + 1] = text end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42 }, sent.keys)
    assert.equal(1, #timers)
    timers[1]()
    assert.equal("error", refreshState(GC).phase)
    assert.equal("Refresh failed", status[#status])
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
    assert.equal("error", refreshState(GC).phase)
    assert.is_nil(cache[42])
    assert.equal(999, cache[7])
    assert.equal("Refresh failed", status[#status])
  end)

  it("makes an old request timer and result inert after Reset", function()
    local now, sent, cache, timers = { value = 100 }, { owned = 0, keys = {} }, {}, {}
    _G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.equal(1, #timers)
    GC.Sell.Reset()
    timers[1]()
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
    assert.equal("error", refreshState(GC).phase)
    assert.same({ 42 }, sent.keys)

    driver.item = function() return 111 end
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({ 42, 42 }, sent.keys)
    assert.equal("waiting_result", refreshState(GC).phase)
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
