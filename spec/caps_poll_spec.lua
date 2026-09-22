local helper = require("spec.spec_helper")

-- Caps fixes, task 4: how the player's caps are polled, drilled and kept, wired through
-- UI/SniperFrame.lua. The pure halves have their own specs (Core/KeyPoll.lua, Core/DrillQueue.lua,
-- Core/Caps.lua); this is what the sniper does with them.
describe("Caps polling", function()
  local values, clock, now

  local function browseRow(itemID, minPrice, totalQuantity)
    return { itemKey = { itemID = itemID }, minPrice = minPrice, totalQuantity = totalQuantity or 3 }
  end

  local function loadSniper()
    clock, now = 1000, 100
    _G.GetTime = function() return now end
    _G.time = function() return clock end
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

    values = {}
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
      GetWatchlist = function() return {} end,
      TargetIds = function() return {} end,
    }
    GC.Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end }
    GC.Print = function() end
    GC.AuctionHouseTab = { PlayerIsBusy = function() return false end }
    helper.loadModule("UI/SniperFrame.lua", GC)
    return GC
  end

  local function adoptCaps(GC, caps)
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, groups = {}, caps = caps }
    GC.Caps.Adopt()
    GC.Sniper._RebuildKeyTargets()
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.C_AuctionHouse, _G.Enum, _G.GoldCap_AppRuns = nil, nil, nil
  end)

  -- Caps fixes 4b. Both cap ratchets -- the poll's (Core/KeyPoll.lua's Fold) and the book pass's
  -- (GC.Caps.BookHits) -- report a floor once and stay quiet while it stands. A hit the drill queue
  -- then let go of without drilling it (ninety seconds in the queue on another tab, or pushed out
  -- by a few hundred other caps) was therefore never looked at again, however long the lot sat
  -- there at the player's price.
  describe("a cap hit the drill queue lets go of un-drilled", function()
    it("is reported again by the next poll of the same floor", function()
      local GC = loadSniper()
      adoptCaps(GC, { { i = 42, c = 100 } })
      local poll = GC.Sniper._keyPoll
      poll:Fold({ browseRow(42, 90) })
      assert.is_true(GC.Sniper._drillQueue:Has(42))

      clock = clock + 91 -- aged out, never drilled
      assert.is_false(GC.Sniper._drillQueue:Has(42))

      poll:Fold({ browseRow(42, 90) })
      assert.is_true(GC.Sniper._drillQueue:Has(42))
      local head = GC.Sniper._drillQueue:Peek()
      assert.equal(90, head.floor)
      assert.is_true(head.cap)
    end)

    it("is reported again by the next book pass of the same floor", function()
      local GC = loadSniper()
      GC.db.commodityByItem[77] = true
      adoptCaps(GC, { { i = 77, c = 100 } })
      local book = { [77] = { floor = 90, qty = 5 } }
      assert.equal(1, #GC.Caps.BookHits(book, GC.Sniper._IsCommodityId))
      GC.Sniper._drillQueue:Push({ itemID = 77, floor = 90, estProfit = 10, priority = 1, cap = true })
      assert.same({}, GC.Caps.BookHits(book, GC.Sniper._IsCommodityId))

      clock = clock + 91
      assert.is_false(GC.Sniper._drillQueue:Has(77))
      assert.equal(1, #GC.Caps.BookHits(book, GC.Sniper._IsCommodityId))
    end)

    it("does not re-arm an ordinary hit that ages out", function()
      local GC = loadSniper()
      values[42] = { kind = "realm_item", source = "import", mv = 250000, ref = 200000, refIlvl = 0 }
      GC.Data.TargetIds = function() return { 42 } end
      GC.Sniper._RebuildKeyTargets()
      local poll = GC.Sniper._keyPoll
      poll:Fold({ browseRow(42, 120000) })
      assert.is_true(GC.Sniper._drillQueue:Has(42))
      clock = clock + 91
      assert.is_false(GC.Sniper._drillQueue:Has(42))
      poll:Fold({ browseRow(42, 120000) })
      assert.is_false(GC.Sniper._drillQueue:Has(42))
    end)
  end)
end)
