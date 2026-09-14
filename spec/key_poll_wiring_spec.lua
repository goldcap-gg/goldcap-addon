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
    -- board = "items": this whole file is about the board the key poll fills, and since 0.9.2
    -- that is a board of its own -- the poll only spends a throttle slot while it is the one
    -- on screen. The refusal on the other board is its own test at the end of this file.
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
    end)

    -- An import from before the T section existed, or an item the region has no figure for:
    -- the realm's own median is not a reference and does not stand in for one.
    it("refuses a realm median with no region reference behind it", function()
      local GC = loadSniper()
      values[42] = { kind = "realm_item", source = "import", mv = 250000 }
      assert.is_nil(GC.Sniper._RealmValue(42))
      assert.is_true(GC.Sniper._RealmNeedsReference(42))
      -- A commodity is not affected: its market value is measured across the region already.
      values[43] = { kind = "region_commodity", source = "import", mv = 250000 }
      assert.is_false(GC.Sniper._RealmNeedsReference(43))
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

    -- A completed pass replaces the COMMODITY board wholesale, and since 0.9.2 the realm row
    -- is not on that board at all -- it is the Items store's, which no pass writes to. (Before
    -- the split the same guarantee was bought by merging the poll's copy back over the pass's
    -- result on every completion; before THAT, every realm row vanished seconds after the poll
    -- found it.)
    it("stays in the Items store across a completed pass", function()
      local GC = loadSniper()
      values[42] = realmValue()
      targetIds = { 42 }
      GC.Sniper._RebuildKeyTargets()
      GC.Sniper._keyPoll:Fold({ browseRow(42, 120000, 2) })
      assert.is_table(GC.Sniper._CurrentLiveDeal(42))

      -- A real pass, run to completion: HasFullBrowseResults() is true in this harness, so the
      -- first results event finishes it and the board is rebuilt from the pass's own rows.
      GC.Sniper._bookPass:Start("classes")
      GC.Sniper._bookPass:OnResultsUpdated()
      assert.is_false(GC.Sniper._bookPass:IsPaging())
      assert.is_table(GC.Sniper._CurrentLiveDeal(42))
      assert.is_table(GC.Sniper._realmDeals[42])
    end)

    -- The batch asked about the item by name, so silence about it is an answer.
    it("takes the row off the board when the batch it asked in comes back without it", function()
      local GC = loadSniper()
      values[42] = realmValue()
      targetIds = { 42 }
      GC.Sniper._RebuildKeyTargets()
      GC.Sniper._keysBatch = { 42 }
      GC.Sniper._keyPoll:Fold({ browseRow(42, 120000, 2) })
      assert.is_table(GC.Sniper._CurrentLiveDeal(42))

      GC.Sniper._keysBatch = { 42 }
      GC.Sniper._keyPoll:Fold({}) -- sold out: nothing came back for it
      assert.is_nil(GC.Sniper._CurrentLiveDeal(42))
      assert.is_nil(GC.Sniper._realmDeals[42])
    end)

    -- The board defect this rule exists for: with only a realm median to go on, the fold used
    -- to publish a row claiming 97% off. There is no row now -- not a quieter one, none.
    it("produces no row and no drill for a realm item with no region reference", function()
      local GC = loadSniper()
      values[42] = { kind = "realm_item", source = "import", mv = 2746440 }
      targetIds = { 42 }
      GC.Sniper._RebuildKeyTargets()
      assert.equal(0, GC.Sniper._keyPoll:Count()) -- never even polled

      GC.Sniper._keyPoll:Fold({ browseRow(42, 89999, 2) })
      assert.is_false(GC.Sniper._drillQueue:Has(42))
      assert.is_nil(GC.Sniper._CurrentLiveDeal(42))
      assert.is_nil(GC.Sniper._realmDeals[42])
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

  -- Live client, 2026-09-14: "PRICING…" at 0/20 with 121 ready events behind it. The keys
  -- batch is pending again the moment it lands, so with the Sell tab on screen it took every
  -- ready tick ahead of the pricing walk, which runs after this handler.
  -- Measured in game: 362 targets pending and not one batch sent in thirteen Auto passes --
  -- the only ready tick after a pass's last page arrives before that page lands, and the
  -- breather between passes brings no tick at all. The switch to the Items board, and the end
  -- of a pass, are where a batch can actually go.
  it("switching to the Items board between passes sends a keys batch on its own", function()
    local GC = loadSniper()
    values[42] = realmValue()
    targetIds = { 42 }
    GC.Sniper._RebuildKeyTargets()
    local sent = 0
    _G.C_AuctionHouse.SearchForItemKeys = function() sent = sent + 1 end
    GC.Sniper._SetBoard("items")
    assert.equal(1, sent)
    -- A batch is out: nothing more until it answers, and the pass may not start over it.
    assert.is_false(GC.Sniper._TrySendKeysBatch(false))
    assert.is_true(GC.Sniper._KeysOutstanding())
  end)

  it("does not spend a ready tick on a keys batch while the Sell tab is on screen", function()
    local GC = loadSniper()
    values[42] = realmValue()
    targetIds = { 42 }
    GC.Sniper._RebuildKeyTargets()
    assert.is_true(GC.Sniper._keyPoll:HasPending())
    local sent = 0
    _G.C_AuctionHouse.SearchForItemKeys = function() sent = sent + 1 end
    local function setView(v)
      local fn = GC.Sniper.OnThrottleReady
      for i = 1, 200 do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == "view" then debug.setupvalue(fn, i, v); return end
      end
      error("no `view` upvalue on OnThrottleReady")
    end

    setView("sell")
    GC.Sniper.OnThrottleReady()
    assert.equal(0, sent)

    setView("deals")
    GC.Sniper.OnThrottleReady()
    assert.equal(1, sent)
  end)

  -- 0.9.2, the two boards: this poll fills the ITEMS board and nothing else, so on the
  -- Commodities board it was refreshing rows the player cannot see -- at the cost of the one
  -- throttled slot the commodity scan and the Sell tab's pricing walk are also asking for.
  -- The Deals view is not enough on its own any more; the board has to be the poll's own.
  it("does not spend a ready tick on a keys batch while the Commodities board is up", function()
    local GC = loadSniper()
    values[42] = realmValue()
    targetIds = { 42 }
    GC.Sniper._RebuildKeyTargets()
    local sent = 0
    _G.C_AuctionHouse.SearchForItemKeys = function() sent = sent + 1 end

    GC.db.settings.sniper.board = "commodities"
    GC.Sniper.OnThrottleReady()
    assert.equal(0, sent)
    -- Still pending, not consumed: switching boards is all it takes to resume.
    assert.is_true(GC.Sniper._keyPoll:HasPending())

    GC.db.settings.sniper.board = "items"
    GC.Sniper.OnThrottleReady()
    assert.equal(1, sent)
  end)

  -- A save from an older build (or a hand-edited one) carries no `board` at all, and a garbage
  -- value must not strand the player on a board that does not exist.
  it("treats an absent or unknown board setting as Commodities", function()
    local GC = loadSniper()
    GC.db.settings.sniper.board = nil
    assert.equal("commodities", GC.Sniper._Board())
    GC.db.settings.sniper.board = "gear"
    assert.equal("commodities", GC.Sniper._Board())
    GC.db.settings.sniper.board = "items"
    assert.equal("items", GC.Sniper._Board())
  end)
end)
