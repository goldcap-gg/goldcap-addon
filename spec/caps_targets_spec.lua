local helper = require("spec.spec_helper")

-- Live price caps, addon task 2: which realm item ids the key poll watches. GC.Sniper._KeyTargetIds
-- is the pure helper _RebuildKeyTargets folds through the player's pins, the site watchlist and the
-- region's target list -- realm items with a realm reference only. Caps fixes 4a took the caps out
-- of it: they have a poll of their own that runs on every board (spec/caps_poll_spec.lua).
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

  it("lists pins, the watchlist and the targets", function()
    local ids = GC.Sniper._KeyTargetIds({ 20 }, { 30 }, { 40 },
      commodityFn({}), noValueFn({}))
    assert.same({ 20, 30, 40 }, ids)
  end)

  it("excludes a commodity", function()
    local ids = GC.Sniper._KeyTargetIds({ 10, 11 }, {}, {},
      commodityFn({ 11 }), noValueFn({}))
    assert.same({ 10 }, ids)
  end)

  it("drops anything with no realm value, a pin included", function()
    local ids = GC.Sniper._KeyTargetIds({ 20 }, { 21 }, { 22, 23 },
      commodityFn({}), noValueFn({ 20, 21, 22 }))
    assert.same({ 23 }, ids)
  end)

  it("lists a duplicate only once", function()
    local ids = GC.Sniper._KeyTargetIds({ 10, 20 }, { 20 }, { 10, 30 },
      commodityFn({}), noValueFn({}))
    assert.same({ 10, 20, 30 }, ids)
  end)

  -- Final review I3 + M6: ONE answer to "is this a commodity", shared by the poll's own target
  -- set and the book pass's cap hits. Two different answers used to live in this file: the poll
  -- asked GC.db.commodityByItem alone -- a cache the Sell tab fills, so an item nobody has
  -- priced is simply absent from it, and a capped commodity therefore went into
  -- SearchForItemKeys, which answers about item keys and never about a commodity book. The book
  -- pass asked the client's GetItemKeyInfo instead, once per cap per pass, which on an uncached
  -- key is a server request: a cap list of a few hundred was a request storm every pass.
  describe("_IsCommodityId", function()
    it("takes the Sell tab's own classification first", function()
      GC.db.commodityByItem = { [10] = true }
      assert.is_true(GC.Sniper._IsCommodityId(10))
      assert.is_false(GC.Sniper._IsCommodityId(11))
    end)

    it("reads the import's classification, which knows items nobody has priced", function()
      GC.Data.GetItemValue = function(id) return id == 12 and { kind = "region_commodity" } or nil end
      assert.is_true(GC.Sniper._IsCommodityId(12))
      assert.is_false(GC.Sniper._IsCommodityId(13))
    end)

    it("does not read a realm item as a commodity", function()
      GC.Data.GetItemValue = function() return { kind = "realm_item", ref = 5 } end
      assert.is_false(GC.Sniper._IsCommodityId(14))
    end)

    it("falls back to client key info only where the client has ALREADY answered", function()
      -- The memo is filled by whichever path already had to ask the client (driver.getKeyInfo);
      -- nothing here ever asks on its own, which is the whole point.
      GC.Sniper._keyInfoCommodity[15] = true
      GC.Sniper._keyInfoCommodity[16] = false
      assert.is_true(GC.Sniper._IsCommodityId(15))
      assert.is_false(GC.Sniper._IsCommodityId(16))
      assert.is_false(GC.Sniper._IsCommodityId(17)) -- never asked about: not a commodity yet
    end)
  end)
end)
