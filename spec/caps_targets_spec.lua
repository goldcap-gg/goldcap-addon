local helper = require("spec.spec_helper")

-- Live price caps, addon task 2: which realm item ids the key poll watches, and in what
-- order. GC.Sniper._KeyTargetIds is the pure helper _RebuildKeyTargets folds through
-- GC.Caps.Targets(), the player's pins, the site watchlist and the region's target list --
-- caps first (a capped item is the player's own price, so it needs no realm reference to be
-- watched), everything else needs one.
describe("Key target ids", function()
  local GC

  before_each(function()
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return false end,
      GetBrowseResults = function() return {} end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      SearchForItemKeys = function() end,
    }
    GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 }, fgMuted = { 0.72, 0.71, 0.69 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end },
      Scanner = { New = function() return {} end },
      Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end },
      SniperDecision = { Evaluate = function() return {} end, MarketFromValue = function() return {} end,
        ReasonText = function(t) return tostring(t) end },
      FullScan = {
        RowsFromBrowse = function() return {} end,
        EvaluateDelta = function() return {}, 0, 0 end,
        CollectNewHot = function() return {} end,
        MergeDeals = function(existing) return existing end,
        CapDeals = function(deals) return deals end,
      },
      WatchSet = { Observe = function() end, Select = function() return {} end },
      Print = function() end,
      db = { settings = { sniper = { sound = false, board = "items" } } },
    }
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
  end)

  after_each(function()
    _G.GetTime, _G.time, _G.C_Timer, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.C_AuctionHouse = nil
  end)

  local function noValueFn(missing)
    missing = missing or {}
    local set = {}
    for _, id in ipairs(missing) do set[id] = true end
    return function(itemID) return not set[itemID] end
  end

  local function commodityFn(ids)
    local set = {}
    for _, id in ipairs(ids or {}) do set[id] = true end
    return function(itemID) return set[itemID] == true end
  end

  it("puts caps first, ahead of pins, watchlist and targets", function()
    local ids = GC.Sniper._KeyTargetIds({ 10 }, { 20 }, { 30 }, { 40 },
      commodityFn({}), noValueFn({}))
    assert.same({ 10, 20, 30, 40 }, ids)
  end)

  it("excludes a commodity cap", function()
    local ids = GC.Sniper._KeyTargetIds({ 10, 11 }, {}, {}, {},
      commodityFn({ 11 }), noValueFn({}))
    assert.same({ 10 }, ids)
  end)

  it("keeps a cap that has no realm value", function()
    local ids = GC.Sniper._KeyTargetIds({ 10 }, {}, {}, {},
      commodityFn({}), noValueFn({ 10 }))
    assert.same({ 10 }, ids)
  end)

  it("drops a pin that has no realm value", function()
    local ids = GC.Sniper._KeyTargetIds({}, { 20 }, {}, {},
      commodityFn({}), noValueFn({ 20 }))
    assert.same({}, ids)
  end)

  it("lists a duplicate only once, at its first (highest-priority) slot", function()
    local ids = GC.Sniper._KeyTargetIds({ 10 }, { 10, 20 }, { 20 }, { 10, 30 },
      commodityFn({}), noValueFn({}))
    assert.same({ 10, 20, 30 }, ids)
  end)
end)
