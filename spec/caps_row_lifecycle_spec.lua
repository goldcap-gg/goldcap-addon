local helper = require("spec.spec_helper")

-- Live price caps, addon task 5 fix round 1: a cap row must survive the SAME polls that judge
-- an ordinary deal by market value, because a cap needs no market/realm reference at all
-- (Core/Caps.lua's own contract -- the cap IS the player's own price). Two regressions found in
-- review of the original task-5 commit:
--
--   1. The key poll's own `onRows` (UI/SniperFrame.lua) nulled out every asked id that did not
--      qualify via GC.DealMath.Evaluate -- which a pure cap item, with no realm value, never
--      does -- deleting the cap row the drill had just built on the very next cycle.
--   2. The watch loop's `onObservation` wrote the plain (market-only) deal straight into the
--      board, unconditionally -- nil for exactly the item a cap exists to rescue -- before the
--      cap-aware evaluation ever ran.
describe("Caps row lifecycle -- realm key poll (onRows)", function()
  local values, watchlist, targetIds

  local function browseRow(itemID, minPrice, totalQuantity)
    return { itemKey = { itemID = itemID }, minPrice = minPrice, totalQuantity = totalQuantity or 3 }
  end

  local function loadSniper()
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.GetMoney = function() return 10 * 1000 * 10000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.PlaySound = function() end
    _G.SOUNDKIT = { READY_CHECK = 8960, MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Enum = { ItemClass = { Tradegoods = 7, Consumable = 0, Gem = 3, ItemEnhancement = 8 } }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return true end,
      GetBrowseResults = function() return {} end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      SearchForItemKeys = function() end,
    }

    values, watchlist, targetIds = {}, {}, {}
    local GC = { db = { commodityByItem = {}, settings = { sniper = { sound = true, showRefused = false,
      board = "items",
      minimumProfitCopper = 50000, minimumRoi = 0.10, watchDiscount = 0.10,
      suspectDiscount = 0.90, hotDiscount = 0.40, hotProfit = 500000,
      goodDiscount = 0.25, goodProfit = 100000, hotMinSold = 3, goodMinSold = 1,
      dumpTrendPct = 10, watchPins = {} } } } }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/WatchSet.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    GC.Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
      tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
      color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
        fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 },
        gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } } }
    GC.Data = {
      GetItemValue = function(itemID) return values[itemID] end,
      GetWatchlist = function() return watchlist end,
      TargetIds = function() return targetIds end,
    }
    GC.Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end }
    GC.Print = function() end
    GC.AuctionHouseTab = { PlayerIsBusy = function() return false end }
    helper.loadModule("UI/SniperFrame.lua", GC)
    GC.Sniper._liveTracksScanDeals = true -- so _CurrentLiveDeal reads the scanned board
    return GC
  end

  local function adoptCap(GC, itemID, c, l)
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, groups = {},
      caps = { { i = itemID, c = c, l = l or 0 } } }
    GC.Caps.Adopt()
  end

  -- What Task 5's drill wiring itself would have built into GC.Sniper._realmDeals: a
  -- `.cap`-carrying, `.stale` row with no realm/market value at all.
  local function capDeal(itemID, unitPrice, cap)
    return {
      itemID = itemID, isCommodity = false, unitPrice = unitPrice, qty = 1, auctionID = 999,
      mv = nil, discount = 0, profit = 20, estProfit = 20, tier = "WATCH",
      cap = cap, capGroup = nil, capManual = nil, stale = true,
    }
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.C_AuctionHouse, _G.Enum, _G.GoldCap_AppRuns = nil, nil, nil
  end)

  it("survives a batch where the item has no realm value, as long as the floor stays under the cap", function()
    local GC = loadSniper()
    adoptCap(GC, 42, 100, 0)
    -- values[42] is nil -- there is no site data for this item at all, exactly the headline
    -- case a cap exists to cover. GC.Sniper._RealmValue(42) answers nil, so the ordinary
    -- GC.DealMath.Evaluate path in onRows can never qualify it.
    GC.Sniper._realmDeals[42] = capDeal(42, 80, 100)
    GC.Sniper._keysBatch = { 42 }

    GC.Sniper._keyPoll:Fold({ browseRow(42, 90, 3) }) -- floor 90 <= cap 100

    assert.is_table(GC.Sniper._CurrentLiveDeal(42))
    assert.equal(100, GC.Sniper._CurrentLiveDeal(42).cap)
  end)

  it("removes a cap row once the batch's own floor climbs back above the cap", function()
    local GC = loadSniper()
    adoptCap(GC, 42, 100, 0)
    GC.Sniper._realmDeals[42] = capDeal(42, 80, 100)
    GC.Sniper._keysBatch = { 42 }

    GC.Sniper._keyPoll:Fold({ browseRow(42, 150, 3) }) -- floor 150 > cap 100

    assert.is_nil(GC.Sniper._CurrentLiveDeal(42))
  end)

  it("removes a cap row when the batch it asked in comes back with no row for it at all", function()
    local GC = loadSniper()
    adoptCap(GC, 42, 100, 0)
    GC.Sniper._realmDeals[42] = capDeal(42, 80, 100)
    GC.Sniper._keysBatch = { 42 }

    GC.Sniper._keyPoll:Fold({}) -- sold out: nothing came back for it

    assert.is_nil(GC.Sniper._CurrentLiveDeal(42))
  end)

  it("does not resurrect an ordinary (non-cap) row that fails to qualify", function()
    -- Guards the fix itself: only an EXISTING cap-flagged deal gets the survival check: an
    -- ordinary unqualified row (no `.cap` field) is removed exactly as before.
    local GC = loadSniper()
    values[42] = nil
    GC.Sniper._realmDeals[42] = { itemID = 42, isCommodity = false, unitPrice = 80, qty = 1, stale = true }
    GC.Sniper._keysBatch = { 42 }

    GC.Sniper._keyPoll:Fold({ browseRow(42, 90, 3) })

    assert.is_nil(GC.Sniper._CurrentLiveDeal(42))
  end)
end)

describe("Caps row lifecycle -- commodity watch loop (onObservation)", function()
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

  local now, decision

  local function load()
    now = 100
    decision = { status = "SAFE", buyable = true, quantity = 5, reasons = {} }
    _G.GetTime = function() return now end
    _G.time = function() return 1000 end
    _G.GetMoney = function() return 10 * 1000 * 10000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.PlaySound = function() end
    _G.SOUNDKIT = { READY_CHECK = 8960, MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
        tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 }, fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 },
          gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = { GetItemValue = function() return { mv = 200, soldPerDay = 50 } end,
        GetWatchlist = function() return {} end },
      Sell = { Refresh = function() end, Reset = function() end,
        Hide = function() end, Show = function() end },
      SniperDecision = { Evaluate = function() return decision end,
        MarketFromValue = function() return {} end,
        ReasonText = function(t) return "reason:" .. tostring(t) end },
      FullScan = { ApplyLiveObservation = function(list) return list end },
      Print = function() end,
      db = { settings = { sniper = { sound = false, showRefused = false, watchPins = {},
        minimumProfitCopper = 0 } } },
    }
    helper.loadModule("Core/WatchSet.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/BoardRows.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    GC.Scanner = { New = function() end }
    local watch = { hungry = true, scanned = 0 }
    function watch:Wants() return self.hungry end
    function watch:Start() end
    function watch:Stop() end
    function watch:OnSystemReady() end
    GC.Sniper.scanner = watch

    local show = GC.Sniper.OnAuctionHouseShow
    local refreshRows = upvalue(show, "refreshRows")
    set(refreshRows, "content", { SetHeight = function() end })
    set(refreshRows, "createRow", function()
      local w = {}
      function w:SetText() end
      function w:SetTextColor() end
      function w:SetTexture() end
      function w:SetLabel() end
      function w:SetVariant() end
      function w:Show() end
      function w:Hide() end
      function w:SetColorTexture() end
      function w:Enable() end
      function w:Disable() end
      local row = { buy = w, tierChip = w, icon = w, nameText = w, discountText = w, unitText = w,
        priceText = w, profitText = w, trendText = w, highlight = w, rail = w, pinBg = w, shown = false }
      function row:Show() self.shown = true end
      function row:Hide() self.shown = false end
      function row:IsShown() return self.shown end
      function row:SetAlpha() end
      return row
    end)
    set(GC.Sniper.OnItemKeyInfo, "driver", {
      isReady = function() return true end,
      mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan,
      onObservation = upvalue(GC.Sniper.OnItemKeyInfo, "driver").onObservation,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() end,
      commodityBook = function() return {} end,
      commodityResult = function() return nil end,
      itemResult = function() return nil end,
      getValue = function() return { mv = 200, soldPerDay = 50 } end,
      onStatus = function() end,
    })
    set(show, "ahOpen", true)
    set(show, "mode", "fullscan")
    set(show, "frame", { IsShown = function() return true end, Hide = function() end,
      status = { SetText = function() end } })
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.GoldCap_AppRuns = nil
  end)

  local function adoptCap(GC, itemID, c, l)
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, groups = {},
      caps = { { i = itemID, c = c, l = l or 0 } } }
    GC.Caps.Adopt()
  end

  it("keeps/creates a cap row from an observation with no plain (market) deal at all", function()
    local GC = load()
    adoptCap(GC, 42, 100, 0)
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    driverTbl.commodityBook = function() return { { unitPrice = 80, quantity = 3 } } end -- under cap

    -- The watch loop found nothing against the market (nil deal, exactly what a pure-cap item
    -- with no GC.Data.GetItemValue entry produces every cycle) -- but the book is under cap.
    driverTbl.onObservation(42, nil)

    local dealsMap = upvalue(driverTbl.onObservation, "deals")
    assert.is_table(dealsMap[42])
    assert.equal(100, dealsMap[42].cap)
    assert.equal(80, dealsMap[42].unitPrice)
  end)

  it("removes a cap row once the book's floor is back above the cap", function()
    local GC = load()
    adoptCap(GC, 42, 100, 0)
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    local dealsMap = upvalue(driverTbl.onObservation, "deals")

    driverTbl.commodityBook = function() return { { unitPrice = 80, quantity = 3 } } end
    driverTbl.onObservation(42, nil)
    assert.is_table(dealsMap[42])

    driverTbl.commodityBook = function() return { { unitPrice = 150, quantity = 3 } } end -- over cap now
    driverTbl.onObservation(42, nil)
    assert.is_nil(dealsMap[42])
  end)

  it("does not touch the board for an item with no cap at all when the plain deal is nil", function()
    local GC = load()
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    local dealsMap = upvalue(driverTbl.onObservation, "deals")
    dealsMap[7] = { itemID = 7, unitPrice = 1 } -- pre-seeded, so a wrongful write is visible either way

    driverTbl.commodityBook = function() return {} end
    driverTbl.onObservation(7, nil)

    assert.is_nil(dealsMap[7]) -- the plain (nil-deal) write/removal path still runs, unchanged
  end)
end)
