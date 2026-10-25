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

  -- `before(GC)` (optional) runs just before UI/SniperFrame.lua loads: a module the window
  -- subscribes to at load (Core/Collection.lua's OnChange) has to be there first, as in the TOC.
  local function loadSniper(before)
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
    if before then before(GC) end
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
    _G.C_AuctionHouse, _G.Enum, _G.C_Item = nil, nil, nil
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

    -- One item id, many item levels, one reference for all of them: armor or a weapon far under it
    -- is a lower level, not a find (owner, 2026-10-15: the board opened on an ilvl 19 bracer at
    -- 100% off). A recipe at the same discount is one item, and stays.
    it("leaves armor and weapons more than 80% under the reference off the board and the drills", function()
      local class = { [42] = 4, [43] = 9, [44] = 4 } -- bracers, a recipe, a tabard
      local slot = { [42] = "INVTYPE_WRIST", [43] = "", [44] = "INVTYPE_TABARD" }
      _G.C_Item = { GetItemInfoInstant = function(itemID)
        return itemID, "", "", slot[itemID], 1, class[itemID], itemID == 44 and 0 or 2
      end }
      local GC = loadSniper()
      helper.loadModule("Core/ItemsBoard.lua", GC)
      values[42], values[43], values[44] = realmValue(), realmValue(), realmValue()
      targetIds = { 42, 43, 44 }
      GC.Sniper._RebuildKeyTargets()

      GC.Sniper._keyPoll:Fold({ browseRow(42, 30000, 2), browseRow(43, 30000, 2), browseRow(44, 30000, 2) })

      assert.is_false(GC.Sniper._drillQueue:Has(42)) -- 85% under
      assert.is_nil(GC.Sniper._realmDeals[42])
      assert.is_true(GC.Sniper._drillQueue:Has(43))
      assert.is_table(GC.Sniper._realmDeals[43])
      assert.is_table(GC.Sniper._realmDeals[44])
    end)

    -- ClickUp 869fjdhnk: a flip priced at a level (the payload's L) is boarded and drilled at its
    -- cheapest lot at or above that level, never at a lower level's price.
    it("boards and drills a flip priced at a level at its cheapest lot at or above it", function()
      local GC = loadSniper()
      values[42] = realmValue() -- reference 200000 at item level 623
      targetIds = { 42 }
      GC.Sniper._RebuildKeyTargets()
      local function at(itemLevel, minPrice)
        return { itemKey = { itemID = 42, itemLevel = itemLevel, itemSuffix = 0, battlePetSpeciesID = 0 },
          minPrice = minPrice, totalQuantity = 1 }
      end

      GC.Sniper._keyPoll:Fold({ at(590, 30000), at(625, 120000) })

      assert.equal(120000, GC.Sniper._drillQueue:Peek().floor)
      assert.equal(120000, GC.Sniper._realmDeals[42].unitPrice)
    end)

    it("leaves a flip off the board while no lot reaches its level", function()
      local GC = loadSniper()
      values[42] = realmValue()
      targetIds = { 42 }
      GC.Sniper._RebuildKeyTargets()
      GC.Sniper._keyPoll:Fold({ { itemKey = { itemID = 42, itemLevel = 590, itemSuffix = 0, battlePetSpeciesID = 0 },
        minPrice = 30000, totalQuantity = 1 } })
      assert.is_false(GC.Sniper._drillQueue:Has(42))
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
  -- The Items board split (Core/ItemsBoard.lua): the rare finds the region payload names are asked
  -- about after everything else, admitted by being rare finds rather than by a realm value; what
  -- this realm asks for one is only ever a Rare finds row -- never a hit, a drill or a flip row.
  describe("rare finds", function()
    -- A rare find as GC.Data.RareFacts hands it out: six realms, cheapest 3,150g.
    local function rareFacts()
      return { sales30d = 2, lastSaleCopper = 25000000, lastSoldAgeHours = 31, realms = 6,
        floorMin = 31500000, floorP10 = 900000000, floorP25 = 1389993400 }
    end

    -- The data layer's split, as Core/Data.lua answers it (spec/data_spec.lua pins that side):
    -- `rares` itemID -> facts, `rank` the ids in the site's order, `flips` itemID -> F facts.
    local function split(GC, rares, rank, flips)
      flips = flips or {}
      GC.Data.IsRareFind = function(id) return rares[id] ~= nil end
      GC.Data.RareFacts = function(id) return rares[id] end
      GC.Data.HasRareFinds = function() return next(rares) ~= nil end
      GC.Data.RareIds = function() return rank end
      GC.Data.RareBefore = function(a, b)
        local at, bt = 0, 0
        for i, id in ipairs(rank) do
          if id == a then at = i end
          if id == b then bt = i end
        end
        return at < bt
      end
      GC.Data.FlipFacts = function(id) return flips[id] end
    end

    local function load(before)
      local GC = loadSniper(before)
      if not GC.Util then helper.loadModule("Core/Util.lua", GC) end
      helper.loadModule("Core/ItemsBoard.lua", GC)
      return GC
    end

    -- A flip row as the board keeps it.
    local function deal(itemID) return { itemID = itemID, unitPrice = 100, qty = 1, profit = 10 } end

    local function shape(list)
      local out = {}
      for i, e in ipairs(list) do
        if e.kind == "header" then out[i] = e.section .. ":" .. e.count
        elseif e.kind == "empty" then out[i] = e.text
        else out[i] = e.itemID end
      end
      return out
    end

    describe("the poll set", function()
      it("asks about them after the rest, with no realm value of their own", function()
        local GC = load()
        values[10] = realmValue()
        targetIds = { 10 }
        split(GC, { [7935] = rareFacts(), [8350] = rareFacts() }, { 8350, 7935 })

        GC.Sniper._RebuildKeyTargets()
        assert.equal(3, GC.Sniper._keyPoll:Count())
        assert.same({ 10, 7935, 8350 }, GC.Sniper._keyPoll:NextBatch())

        local none = function() return false end
        assert.same({ 20, 30, 50, 40 }, GC.Sniper._KeyTargetIds({ 20 }, {}, { 30 }, none,
          function(id) return id == 20 or id == 30 end, { 50, 40 }))
      end)

      it("asks about the best-ranked RARE_POLL_CAP of them, commodities left out", function()
        local GC = load()
        local rank = {}
        for i = 1, 250 do rank[i] = 1000 + i end
        local commodity = function(id) return id == 1001 end
        local ids = GC.Sniper._KeyTargetIds({}, {}, {}, commodity, function() return false end, rank)
        assert.equal(200, #ids)
        assert.equal(1002, ids[1])
        assert.equal(1201, ids[200])
        -- One already asked about as a T target counts among the 200, and is asked once.
        ids = GC.Sniper._KeyTargetIds({}, {}, { 1002 }, commodity, function(id) return id == 1002 end, rank)
        assert.equal(200, #ids)
        assert.equal(1002, ids[1])
        assert.equal(1201, ids[200])
      end)

      it("leaves a round half way where it was when a rebuild changes nothing", function()
        local GC = load()
        local rares, rank = {}, {}
        for i = 1, 150 do rares[2000 + i] = rareFacts(); rank[i] = 2000 + i end
        split(GC, rares, rank)
        GC.Sniper._RebuildKeyTargets()
        assert.equal(100, #GC.Sniper._keyPoll:NextBatch())
        GC.Sniper._RebuildKeyTargets()
        assert.equal(50, #GC.Sniper._keyPoll:NextBatch())
        assert.is_false(GC.Sniper._keyPoll:HasPending())
      end)
    end)

    describe("an answer", function()
      it("never makes a hit, a drill or a flip row of one, even with a T ask still loaded", function()
        local GC = load()
        values[7935] = realmValue({ ref = 2000000000 }) -- an old import's ask, outlived by the payload
        split(GC, { [7935] = rareFacts() }, { 7935 })
        GC.Sniper._RebuildKeyTargets()
        GC.Sniper._keysBatch = { 7935 }

        GC.Sniper._keyPoll:Fold({ browseRow(7935, 31500000, 1) })

        assert.is_false(GC.Sniper._drillQueue:Has(7935))
        assert.is_nil(GC.Sniper._realmDeals[7935])
        assert.same({ unit = 31500000, qty = 1 }, GC.Sniper._rareSeen[7935])
      end)

      it("lets go of one the batch asked about and the answer did not name", function()
        local GC = load()
        split(GC, { [7935] = rareFacts() }, { 7935 })
        GC.Sniper._rareSeen[7935] = { unit = 1, qty = 1 }
        GC.Sniper._keysBatch = { 7935 }
        GC.Sniper._keyPoll:Fold({})
        assert.is_nil(GC.Sniper._rareSeen[7935])
      end)

      it("still puts a flip on the board and in the drill queue, as before", function()
        local GC = load()
        values[42] = realmValue()
        targetIds = { 42 }
        split(GC, { [7935] = rareFacts() }, { 7935 })
        GC.Sniper._RebuildKeyTargets()
        GC.Sniper._keyPoll:Fold({ browseRow(42, 120000, 2), browseRow(7935, 31500000, 1) })
        assert.is_true(GC.Sniper._drillQueue:Has(42))
        assert.is_table(GC.Sniper._realmDeals[42])
        assert.is_nil(GC.Sniper._rareSeen[42])
      end)
    end)

    describe("the board", function()
      it("draws Flips and Rare finds, a rare find at or under p25 only", function()
        local GC = load()
        split(GC, { [7935] = rareFacts(), [8350] = rareFacts() }, { 7935, 8350 })
        GC.Sniper._rareSeen[7935] = { unit = 31500000, qty = 1 }
        GC.Sniper._rareSeen[8350] = { unit = 1389993401, qty = 1 } -- above a quarter of the realms
        assert.same({ "flips:1", 10, "rares:1", 7935 }, shape(GC.Sniper._ItemsDisplay({ deal(10) })))
        assert.equal("min", GC.Sniper._ItemsDisplay({})[4].standing)
      end)

      it("looks as it did before the site switched, apart from the Flips header", function()
        local GC = load()
        split(GC, {}, {})
        assert.same({ "flips:1", 10 }, shape(GC.Sniper._ItemsDisplay({ deal(10) })))
        local empty = {}
        assert.equal(empty, GC.Sniper._ItemsDisplay(empty)) -- the board's own empty state explains it
      end)

      it("leaves the Commodities board alone", function()
        local GC = load()
        split(GC, { [7935] = rareFacts() }, { 7935 })
        GC.Sniper._rareSeen[7935] = { unit = 31500000, qty = 1 }
        GC.db.settings.sniper.board = "commodities"
        local list = { deal(10) }
        assert.equal(list, GC.Sniper._ItemsDisplay(list))
        assert.equal("", GC.Sniper._RowNotes(deal(10)))
      end)

      -- A row is two lines at most (owner, 2026-10-25: "more than two lines is not needed"): the
      -- name, and one line under it. Everything else is the row's tooltip (GC.Sniper._RowDetails).
      local function texts(details)
        local out = {}
        for _, detail in ipairs(details) do out[#out + 1] = detail.text end
        return table.concat(out, "\n")
      end

      it("says how often a flip sold this week under its name, and on how many realms in its tooltip", function()
        local GC = load()
        split(GC, {}, {}, { [10] = { ref = 300000, sales7d = 6, realms = 3 } })
        local notes = GC.Sniper._RowNotes(deal(10))
        assert.equal("Sold 6 times in 7 days", helper.plain(notes):match("^\n(.*)$"))
        assert.equal("Sold 6 times in 7 days on 3 realms", texts(GC.Sniper._RowDetails(deal(10))))
        assert.equal("", GC.Sniper._RowNotes(deal(11)))
        assert.same({}, GC.Sniper._RowDetails(deal(11)))
        GC.db.settings.sniper.board = "commodities"
        assert.same({}, GC.Sniper._RowDetails(deal(10)))
      end)

      -- Where a flip sells (the payload's C, S and K): this realm is Tarren Mill, the account has a
      -- character on Kazzak, and Silvermoon is a realm it has none on.
      describe("where a flip sells", function()
        local G = 10000
        local function loadRouted(spots, cheap)
          _G.GetRealmName = function() return "Tarren Mill" end
          local GC = load()
          helper.loadModule("Core/SellRoute.lua", GC)
          split(GC, {}, {}, { [10] = { ref = 300000, sales7d = 6, realms = 3 } })
          local keys = { tarrenmill = 1084, kazzak = 1305, silvermoon = 3391 }
          local names = { [1084] = "Tarren Mill", [1305] = "Kazzak", [3391] = "Silvermoon" }
          GC.Data.RealmIdByKey = function(key) return keys[key] end
          GC.Data.RealmName = function(id) return names[id] end
          GC.Data.ClientRegion = function() return "eu" end
          GC.Data.SellSpots = function(id) return id == 10 and spots or nil end
          GC.Data.CheapRealms = function(id) return id == 10 and cheap or nil end
          GC.Ledger = { GetGold = function() return { { char = "Alt-Kazzak", region = "eu", copper = 1 } } end }
          return GC
        end

        local function under(GC)
          return helper.plain(GC.Sniper._RowNotes(deal(10))):match("^\n(.*)$")
        end

        after_each(function() _G.GetRealmName = nil end)

        it("names the player's realm it sells best on and how soon, the list price in the tooltip", function()
          local GC = loadRouted({ { realmId = 1305, list = 2200 * G, days = 2.4, own = true },
            { realmId = 1084, list = 1900 * G, days = 0.6, own = true } })
          assert.equal("Sells on Kazzak in about 2 days", under(GC))
          local details = texts(GC.Sniper._RowDetails(deal(10)))
          assert.truthy(details:find("Sell on Kazzak for " .. GC.Util.FormatMoney(2200 * G) .. ", sells in about 2 days", 1, true))
          assert.truthy(details:find("Sold 6 times in 7 days on 3 realms", 1, true))
        end)

        it("calls one of the player's realms by their character's realm, not the payload's name for its market", function()
          local GC = loadRouted({ { realmId = 1305, list = 2200 * G, days = 2.4, own = true },
            { realmId = 1084, list = 1900 * G, days = 0.6, own = true } })
          GC.Data.RealmName = function(id) return ({ [1084] = "Tarren Mill", [1305] = "Kazzak-Market" })[id] end
          assert.equal("Sells on Kazzak in about 2 days", under(GC))
          assert.truthy(texts(GC.Sniper._RowDetails(deal(10))):find("Sell on Kazzak for ", 1, true))
        end)

        it("says how soon it sells here, and in the tooltip that this realm's lot is among the five cheapest", function()
          local GC = loadRouted({ { realmId = 1084, list = 1900 * G, days = 0.6, own = true } }, { floor5th = 100, realms = 24 })
          assert.equal("Sells here within a day", under(GC)) -- the lot asks 100 copper
          local details = GC.Sniper._RowDetails(deal(10))
          assert.equal("Among the 5 cheapest of 24 realms", details[2].text)
          assert.equal(GC.Theme.color.gold, details[2].color)
          assert.truthy(texts(details):find("Sell here for " .. GC.Util.FormatMoney(1900 * G), 1, true))
          GC = loadRouted(nil, { floor5th = 99, realms = 24 })
          assert.falsy(texts(GC.Sniper._RowDetails(deal(10))):find("cheapest", 1, true))
          assert.equal("Sold 6 times in 7 days", under(GC)) -- no realm to sell on: how often it sold
        end)

        it("rounds how soon as the tooltip does", function()
          local GC = loadRouted({ { realmId = 1084, list = 1900 * G, days = 1.4, own = true } })
          assert.equal("Sells here in about 1 day", under(GC))
          GC = loadRouted({ { realmId = 1084, list = 1900 * G, days = 2.5, own = true } })
          assert.equal("Sells here in about 3 days", under(GC))
        end)

        it("names a realm with no character on it only in the tooltip, when it pays notably more", function()
          local GC = loadRouted({ { realmId = 3391, list = 4000 * G, days = 3, own = false },
            { realmId = 1084, list = 1900 * G, days = 0.6, own = true } })
          assert.equal("Sells here within a day", under(GC))
          assert.truthy(texts(GC.Sniper._RowDetails(deal(10))):find("Pays more on Silvermoon, where you have no character", 1, true))
        end)

        it("says nothing about where to sell on a realm the payload does not know", function()
          local GC = loadRouted({ { realmId = 1084, list = 1900 * G, days = 0.6, own = true } })
          _G.GetRealmName = function() return "Nowhere" end
          GC.SellRoute._here = nil
          assert.equal("Sold 6 times in 7 days", under(GC))
          assert.falsy(texts(GC.Sniper._RowDetails(deal(10))):find("Sell", 1, true))
        end)

        it("hands the tooltip what the row leaves out", function()
          local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
          local text = f:read("*a")
          f:close()
          local enterAt = assert(text:find('row:SetScript("OnEnter", function(self)', 1, true))
          local enter = text:sub(enterAt)
          local at = assert(enter:find("local details = GC.Sniper._RowDetails(self.deal)", 1, true))
          assert.truthy(enter:find("GameTooltip:AddLine(GC.Util.ClientText(detail.text)", at, true))
          assert.truthy(at < assert(enter:find("GameTooltip:Show()", 1, true)))
        end)
      end)

      -- The item cell, as GC.Sniper._FitRowName writes it: the line under the name goes when the
      -- name alone takes both lines, and comes back when the row widens. The name is never cut.
      describe("the item cell's two lines", function()
        local function cell(linesFor)
          local text = {}
          function text:SetText(t) self.text = t end
          function text:GetNumLines() return linesFor(self.text) end
          return { nameText = text }
        end

        it("keeps the line under a name that fits on one line", function()
          local GC = load()
          local row = cell(function(t) return select(2, t:gsub("\n", "")) + 1 end)
          row._nameParts = { "Glaive Tosser x1 of 2", "", "", "\nSells here in about 2 days" }
          GC.Sniper._FitRowName(row)
          assert.equal("Glaive Tosser x1 of 2\nSells here in about 2 days", row.nameText.text)
        end)

        it("leaves the line to the tooltip when the name wraps, and puts it back when the row widens", function()
          local GC = load()
          local wide = false
          local row = cell(function(t)
            local lines = select(2, t:gsub("\n", "")) + 1
            return wide and lines or lines + 1 -- narrow: the name takes two lines
          end)
          row._nameParts = { "Teebu's Scorching Straight Sword x1 of 2", "", "", "\nSold 39 times in 7 days" }
          GC.Sniper._FitRowName(row)
          assert.equal("Teebu's Scorching Straight Sword x1 of 2", row.nameText.text)
          wide = true
          GC.Sniper._FitRowName(row)
          assert.equal("Teebu's Scorching Straight Sword x1 of 2\nSold 39 times in 7 days", row.nameText.text)
        end)

        it("writes a row with no line under its name as it was", function()
          local GC = load()
          local row = cell(function() return 9 end)
          row._nameParts = { "Section", "", "" }
          GC.Sniper._FitRowName(row)
          assert.equal("Section", row.nameText.text)
        end)
      end)

      -- A Rare finds row, two lines like a flip's: the name, and where this realm's listing stands.
      -- The sales seen are its tooltip's (GC.Sniper._RareTooltip).
      it("draws a Rare finds row with its standing under the name and its sales in the tooltip", function()
        local GC = load()
        local function widget()
          local w = {}
          for _, name in ipairs({ "Hide", "Disable", "SetTexture", "SetTextColor" }) do w[name] = function() end end
          function w:SetText(t) self.text = t end
          function w:SetLabel(t) self.label = t end
          return w
        end
        local row = { buy = widget(), tierChip = widget(), icon = widget(), nameText = widget(), pinBg = widget(),
          rail = widget(), discountText = widget(), unitText = widget(), priceText = widget(), profitText = widget(),
          trendText = widget() }
        function row:Show() self.shown = true end
        function row:IsShown() return self.shown end
        function row:SetAlpha() end
        GC.Sniper._PaintBoardEntry(row, { kind = "rare", itemID = 7935, unitPrice = 31500000, qty = 1,
          standing = "min", facts = rareFacts() })
        local standing, sales = GC.ItemsBoard.RareLines({ standing = "min", facts = rareFacts() })
        local text = helper.plain(row.nameText.text)
        assert.equal("item 7935\n" .. standing, text)
        assert.is_nil(text:find(sales, 1, true))
      end)

      -- Hovering a board row shows one window (owner, 2026-10-25: three at once, the item and two
      -- comparisons with what the character wears). Blizzard's own switch goes on after the owner
      -- is set and before the item, as ItemUtil.DisplayEquipSlotTooltip does it, and
      -- GameTooltip_OnTooltipCleared turns it off with the next tooltip. Shift still compares.
      it("shows a row's item tooltip without the comparison windows", function()
        local GC = load()
        local calls = {}
        local tip = {}
        function tip:SetItemByID(id) calls[#calls + 1] = "item " .. id end
        local saved = { _G.GameTooltip, _G.GameTooltip_SuppressAutomaticCompareItem, GC.Theme.ItemTooltipOutside }
        finally(function()
          _G.GameTooltip, _G.GameTooltip_SuppressAutomaticCompareItem, GC.Theme.ItemTooltipOutside =
            saved[1], saved[2], saved[3]
        end)
        _G.GameTooltip = tip
        _G.GameTooltip_SuppressAutomaticCompareItem = function(t)
          assert.equal(tip, t)
          calls[#calls + 1] = "suppress"
        end
        GC.Theme.ItemTooltipOutside = function() calls[#calls + 1] = "owner" end

        GC.Sniper._ShowItemTooltip({}, 7935)
        assert.same({ "owner", "suppress", "item 7935" }, calls)

        -- Every item tooltip the Deals board and its Check draw goes through it.
        local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
        local text = f:read("*a")
        f:close()
        assert.equal(1, select(2, text:gsub("GameTooltip:SetItemByID%(", "")))
        assert.equal(3, select(2, text:gsub("\n%s*GC%.Sniper%._ShowItemTooltip%(", "")))
      end)

      -- GoldCap's own price block under the item (UI/Tooltip.lua: Vendor, Auction, region price,
      -- data age) stands aside on the Items board, whose cells already say it, and keeps its place
      -- on the commodity board.
      it("keeps GoldCap's price block off an Items board row's tooltip", function()
        local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
        local text = f:read("*a")
        f:close()
        local enterAt = assert(text:find('row:SetScript("OnEnter", function(self)', 1, true))
        local enter = text:sub(enterAt)
        local own = assert(enter:find(
          'self.goldcapOwnLines = (self.deal and (self.deal.kind == "rare" or GC.Sniper._RealmBoard())) or nil', 1, true))
        assert.is_true(own < assert(enter:find("GC.Sniper._ShowItemTooltip(self, self.deal.itemID)", 1, true)))
        -- And the second realm line under the verdict is gone: the Check names the region's price.
        assert.is_nil(text:find("local realmValue = GC.Sniper._RealmValue(self.deal.itemID)", 1, true))
      end)

      it("pins nothing and opens nothing from a header or a Rare finds row", function()
        local GC = load()
        GC.Sniper._RowPinEvent({ deal = { kind = "rare", itemID = 7935 } }, "down", "RightButton")
        GC.Sniper._RowPinEvent({ deal = { kind = "header", section = "rares", count = 1 } }, "up", "RightButton")
        assert.same({}, GC.db.settings.sniper.watchPins)
      end)
    end)

    describe("collection marks and Only what I lack", function()
      local Client = require("spec.support.collection_client")
      local client

      -- 7935 a plate chest nobody has; 7936 a plate chest sharing its look, which the account has
      -- through 7935's twin; 2553 a recipe this character does not know; 2589 a trade good; 1973
      -- a toy the account owns.
      local function world()
        return {
          items = {
            [7935] = { classID = 4, subclassID = 4, equipLoc = "INVTYPE_CHEST", appearanceID = 100, sourceID = 1001 },
            [7936] = { classID = 4, subclassID = 4, equipLoc = "INVTYPE_CHEST", appearanceID = 200, sourceID = 2001 },
            [7937] = { classID = 4, subclassID = 4, equipLoc = "INVTYPE_CHEST", appearanceID = 200, sourceID = 2002 },
            [2553] = { classID = 9, subclassID = 6, tooltip = { "Recipe: Elixir of Minor Agility" } },
            [2589] = { classID = 7, subclassID = 5, equipLoc = "" },
            [1973] = { classID = 15, subclassID = 4, toy = true },
          },
          sources = { [1001] = 7935, [2001] = 7936, [2002] = 7937 },
          appearances = { [100] = { 1001 }, [200] = { 2001, 2002 } },
          owned = { sources = { [2002] = true }, tabards = {}, toys = { [1973] = true } },
        }
      end

      local function loadMarked()
        return load(function(GC)
          helper.loadModule("Core/Collection.lua", GC)
          client = Client.new(world())
          GC.Collection.SetClient(client)
        end)
      end

      it("marks what the account lacks, an appearance it has elsewhere, and nothing else", function()
        local GC = loadMarked()
        split(GC, {}, {})
        assert.equal("\nNot collected", helper.plain(GC.Sniper._RowNotes(deal(7935)))) -- the line under the name
        assert.truthy(GC.Sniper._RowNotes(deal(2553)):find("Not known by this character", 1, true))
        assert.truthy(GC.Sniper._RowNotes(deal(7936)):find("Appearance known", 1, true))
        assert.equal("", GC.Sniper._RowNotes(deal(2589)))
        assert.equal("", GC.Sniper._RowNotes(deal(1973)))
      end)

      it("keeps only what the account lacks while the toggle is on, in both sections", function()
        local GC = loadMarked()
        split(GC, { [2553] = rareFacts(), [1973] = rareFacts() }, { 2553, 1973 })
        GC.Sniper._rareSeen[2553] = { unit = 31500000, qty = 1 }
        GC.Sniper._rareSeen[1973] = { unit = 31500000, qty = 1 }
        local flips = { deal(7935), deal(7936), deal(2589) }
        assert.same({ "flips:3", 7935, 7936, 2589, "rares:2", 2553, 1973 }, shape(GC.Sniper._ItemsDisplay(flips)))

        assert.is_false(GC.db.settings.sniper.onlyLack == true) -- off until the player turns it on
        GC.Sniper._ToggleOnlyLack()
        assert.is_true(GC.db.settings.sniper.onlyLack)
        assert.same({ "flips:1", 7935, "rares:1", 2553 }, shape(GC.Sniper._ItemsDisplay(flips)))
        GC.Sniper._ToggleOnlyLack()
        assert.equal(7, #GC.Sniper._ItemsDisplay(flips))
      end)

      it("renders once for a burst of collection changes, not once per event", function()
        local GC = loadMarked()
        local queued = 0
        _G.C_Timer.After = function() queued = queued + 1 end
        for _ = 1, 25 do GC.Collection.Reset() end
        assert.equal(1, queued)
        assert.is_true(GC.Sniper._rowFitQueued)
      end)
    end)
  end)
end)
