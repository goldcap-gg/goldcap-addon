local helper = require("spec.spec_helper")

-- Sniper phase 2, the UI side: which items the realm poll asks about, what a returned row is
-- measured against, and what a row under its trigger actually does to the board and the drill
-- queue. Core/KeyPoll.lua's own spec covers the batching and the ratchet; this covers the
-- wiring around it in UI/SniperFrame.lua.
describe("Key poll wiring", function()
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

  -- A realm item as the import describes one: a median from the I section, and (optionally)
  -- the region reference and its item level from the T section. No verification facts -- that
  -- is what makes it a realm item rather than a commodity.
  local function realmValue(overrides)
    local value = { kind = "realm_item", source = "import", mv = 250000, ref = 200000, refIlvl = 623 }
    for k, v in pairs(overrides or {}) do value[k] = v end
    return value
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.C_AuctionHouse, _G.Enum = nil, nil
  end)

  describe("what a realm item is worth", function()
    it("takes the lower of this realm's median and the region reference", function()
      local GC = loadSniper()
      values[42] = realmValue()
      assert.equal(200000, GC.Sniper._RealmValue(42).mv)
      values[42] = realmValue({ mv = 150000 })
      assert.equal(150000, GC.Sniper._RealmValue(42).mv)
      -- An import from before the T section existed: the realm median is all there is.
      values[42] = { kind = "realm_item", source = "import", mv = 250000 }
      assert.equal(250000, GC.Sniper._RealmValue(42).mv)
    end)

    it("carries the reference item level through", function()
      local GC = loadSniper()
      values[42] = realmValue()
      assert.equal(623, GC.Sniper._RealmValue(42).refIlvl)
    end)

    it("answers for a target the import has no median for at all", function()
      local GC = loadSniper()
      values[42] = { kind = "realm_item", source = "import", ref = 200000, refIlvl = 0 }
      assert.equal(200000, GC.Sniper._RealmValue(42).mv)
    end)

    it("refuses a commodity and refuses bundled data", function()
      local GC = loadSniper()
      values[42] = realmValue({ kind = "region_commodity" })
      assert.is_nil(GC.Sniper._RealmValue(42))
      -- Bundled sample data is not this realm's median and must never be treated as one.
      values[42] = realmValue({ source = "bundled" })
      assert.is_nil(GC.Sniper._RealmValue(42))
      values[43] = nil
      assert.is_nil(GC.Sniper._RealmValue(43))
    end)
  end)

  describe("the poll set", function()
    it("is the pins, the site watchlist and the region's targets, realm items only", function()
      local GC = loadSniper()
      values[10] = realmValue()  -- pinned
      values[20] = realmValue()  -- on the site watchlist
      values[30] = realmValue()  -- a region target
      values[40] = realmValue({ kind = "region_commodity" }) -- a commodity: the book pass's job
      values[50] = nil           -- nothing known about it at all
      GC.db.settings.sniper.watchPins = { 10, 40 }
      watchlist = { 20, 50 }
      targetIds = { 30, 10 } -- also pinned: it must appear once, not twice

      GC.Sniper._RebuildKeyTargets()
      assert.equal(3, GC.Sniper._keyPoll:Count())
      assert.same({ 10, 20, 30 }, GC.Sniper._keyPoll:NextBatch())
    end)

    it("leaves out an item the Sell tab has already classified as a commodity", function()
      local GC = loadSniper()
      values[10] = realmValue()
      values[11] = realmValue()
      GC.db.commodityByItem[11] = true
      targetIds = { 10, 11 }

      GC.Sniper._RebuildKeyTargets()
      assert.same({ 10 }, GC.Sniper._keyPoll:NextBatch())
    end)
  end)

  describe("folding a batch", function()
    -- reference 200000 -> trigger 140000 (the profit floor, stricter here than the 25% one)
    it("queues a drill-down and puts the row on the board, priced against the reference", function()
      local GC = loadSniper()
      values[42] = realmValue()
      targetIds = { 42 }
      GC.Sniper._RebuildKeyTargets()

      GC.Sniper._keyPoll:Fold({ browseRow(42, 120000, 2) })

      assert.is_true(GC.Sniper._drillQueue:Has(42))
      local queued = GC.Sniper._drillQueue:Peek()
      assert.equal(120000, queued.floor)
      -- 0.95 x 200000 - 120000
      assert.equal(70000, queued.estProfit)

      local deal = GC.Sniper._CurrentLiveDeal(42)
      assert.is_table(deal)
      -- Measured against the REFERENCE (200000), not this realm's own median (250000): 40%
      -- under, not 52%.
      assert.equal(200000, deal.mv)
      assert.equal(0.4, deal.discount)
      assert.equal("WATCH", deal.status)
      assert.equal("realm_item_unverified", deal.reason)
      assert.is_false(deal.buyable)
      -- A keys row is an aggregate across sellers, exactly like a browse row: nothing may be
      -- bought off it until a live drill resolves one actual lot.
      assert.is_true(deal.stale)
      assert.is_nil(deal.auctionID)
    end)

    it("says nothing about a floor that does not clear the trigger", function()
      local GC = loadSniper()
      values[42] = realmValue()
      targetIds = { 42 }
      GC.Sniper._RebuildKeyTargets()

      GC.Sniper._keyPoll:Fold({ browseRow(42, 190000, 2) })
      assert.is_false(GC.Sniper._drillQueue:Has(42))
      assert.is_nil(GC.Sniper._CurrentLiveDeal(42)) -- 5% under the reference is not a deal
    end)

    it("ignores an item with no reference at all", function()
      local GC = loadSniper()
      values[42] = nil
      GC.Sniper._keyPoll:Fold({ browseRow(42, 1, 2) })
      assert.is_false(GC.Sniper._drillQueue:Has(42))
      assert.is_nil(GC.Sniper._CurrentLiveDeal(42))
    end)
  end)

  it("folds a keys answer into the poll rather than into the paging book pass", function()
    local GC = loadSniper()
    values[42] = realmValue()
    targetIds = { 42 }
    GC.Sniper._RebuildKeyTargets()
    _G.C_AuctionHouse.GetBrowseResults = function() return { browseRow(42, 120000, 2) } end

    -- No batch outstanding: the event belongs to whatever the book pass is doing.
    assert.is_false(GC.Sniper._FoldKeysBatch())
    assert.is_nil(GC.Sniper._keyPoll:Book()[42])

    GC.Sniper._keysAwaiting = 1000
    GC.Sniper.OnBrowseResults()
    assert.equal(120000, GC.Sniper._keyPoll:Book()[42].floor)
    assert.is_nil(GC.Sniper._keysAwaiting) -- and the slot is free for the next batch
  end)
end)
