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

  after_each(function() _G.time, _G.C_AuctionHouse = os.time, nil end)

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
    local ready = false
    local GC = load(now, sent, cache, function() return { isCommodity = false } end)
    local advance = upvalue(GC.Sell.OnThrottleReady, "advanceQuote")
    local driver = upvalue(advance, "driver")
    driver.isReady = function() return ready end
    set(GC.Sell.Refresh, "setStatus", function(text) status[#status + 1] = text end)
    GC.Sell.Refresh(); GC.Sell.OnOwnedAuctions()
    assert.same({}, sent.keys)
    ready = true; GC.Sell.OnThrottleReady()
    assert.same({ 42 }, sent.keys)
    GC.Sell.OnItemSearchResults(42)
    GC.Sniper.IsAHOpen = function() return false end
    GC.Sell.Refresh()
    assert.equal("Auction House is not open", status[#status])
  end)
end)
