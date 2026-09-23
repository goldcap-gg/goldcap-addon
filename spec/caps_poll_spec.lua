local helper = require("spec.spec_helper")

-- Caps fixes, task 4: how the player's caps are polled, drilled and kept, wired through
-- UI/SniperFrame.lua. The pure halves have their own specs (Core/KeyPoll.lua, Core/DrillQueue.lua,
-- Core/Caps.lua); this is what the sniper does with them.
describe("Caps polling", function()
  local values, clock, now

  local function upvalue(fn, wanted)
    for i = 1, 200 do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end
  local function setUpvalue(fn, wanted, value)
    for i = 1, 200 do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

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

  local keysSent
  -- The auction house open, the window up and the client's throttle ready: the one state the cap
  -- poll runs in. Every SearchForItemKeys is recorded, by the ids it asked about.
  local function openAH(GC)
    keysSent = {}
    GC.Sniper.IsAHOpen = function() return true end
    GC.Sniper.IsWindowShown = function() return true end
    _G.C_AuctionHouse.SearchForItemKeys = function(keys)
      local ids = {}
      for i = 1, #keys do ids[i] = keys[i].itemID end
      keysSent[#keysSent + 1] = ids
    end
  end

  -- The answer to the batch that is out, as the client delivers it: a browse event.
  local function answer(GC, rows)
    _G.C_AuctionHouse.GetBrowseResults = function() return rows or {} end
    GC.Sniper.OnBrowseResults()
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

  -- Round 1. A search sent on top of an unanswered SearchForItemKeys takes its answer with it and
  -- comes back empty itself (UI/SellFrame.lua's advanceQuote, seen in game). With the caps polling
  -- on the Deals boards, a keys batch is out there most of the time -- so no background search of
  -- ours goes out over one, whoever sent it, and no keys batch goes out over a search of ours.
  describe("never one search over another", function()
    local function batchOut(GC, owner)
      GC.Sniper._keysAwaiting, GC.Sniper._keysOwner, GC.Sniper._keysBatch = clock, owner, { 1 }
    end

    for _, owner in ipairs({ "caps", "sniper" }) do
      it("holds a drill back while a " .. owner .. " batch is unanswered", function()
        local GC = loadSniper()
        adoptCaps(GC, { { i = 42, c = 100 } })
        GC.Sniper._capPoll:Fold({ browseRow(42, 90) })
        setUpvalue(upvalue(GC.Sniper.OnThrottleReady, "canDrillNow"), "ahOpen", true)
        local drilled = {}
        setUpvalue(GC.Sniper.OnThrottleReady, "maybeStartPrewarm", function(deal)
          drilled[#drilled + 1] = deal.itemID
          return true
        end)
        batchOut(GC, owner)
        GC.Sniper.OnThrottleReady()
        assert.same({}, drilled)
        GC.Sniper._keysAwaiting, GC.Sniper._keysOwner, GC.Sniper._keysBatch = nil, nil, nil
        GC.Sniper.OnThrottleReady()
        assert.same({ 42 }, drilled)
      end)
    end

    it("stands the verify walk down while a keys batch is unanswered", function()
      local GC = loadSniper()
      local standsDown = upvalue(upvalue(GC.Sniper.OnThrottleReady, "stepVerifyWalk"), "verifyWalkStandsDown")
      setUpvalue(standsDown, "ahOpen", true)
      setUpvalue(standsDown, "frame", { IsShown = function() return true end })
      assert.is_false(standsDown())
      batchOut(GC, "caps")
      assert.is_true(standsDown())
    end)

    it("keeps the watch loop from sending while a keys batch is unanswered", function()
      local GC = loadSniper()
      local mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan
      setUpvalue(mayScan, "watchGrant", true)
      assert.is_true(mayScan())
      batchOut(GC, "caps")
      assert.is_false(mayScan())
    end)

    it("sends no hover pre-warm while a keys batch is unanswered", function()
      local GC = loadSniper()
      local searched = 0
      _G.C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = true } end
      _G.C_AuctionHouse.SendSearchQuery = function() searched = searched + 1 end
      local prewarm = upvalue(GC.Sniper.OnThrottleReady, "maybeStartPrewarm")
      setUpvalue(prewarm, "ahOpen", true)
      batchOut(GC, "caps")
      assert.is_nil(prewarm({ itemID = 42, unitPrice = 90, stale = true }))
      assert.equal(0, searched)
      GC.Sniper._keysAwaiting, GC.Sniper._keysOwner, GC.Sniper._keysBatch = nil, nil, nil
      assert.is_true(prewarm({ itemID = 42, unitPrice = 90, stale = true }))
      assert.equal(1, searched)
    end)

    -- The other direction, and on every path to a batch -- the arbiter, the ticker's nudges, a
    -- board switch, BUY's and the Sell tab's own calls all go through _TrySendKeysBatchFor.
    it("sends no keys batch, on any path, over a search of ours, a purchase or a parked Check", function()
      local GC = loadSniper()
      openAH(GC)
      adoptCaps(GC, { { i = 42, c = 100 } })
      GC.Sniper._keyPoll:SetTargets({ 5 })
      local buyPoll = { HasPending = function() return true end, NextBatch = function() return { 9 } end }
      local function anyPath()
        return GC.Sniper._TrySendCapBatch() or GC.Sniper._TrySendKeysBatch()
          or GC.Sniper._TrySendKeysBatchFor(buyPoll, "buy", function() return true end)
      end
      local prewarm = upvalue(GC.Sniper.OnThrottleReady, "maybeStartPrewarm")
      setUpvalue(prewarm, "prewarmAttempt", { itemID = 7 })
      assert.is_false(anyPath())
      setUpvalue(prewarm, "prewarmAttempt", nil)
      local parked = upvalue(GC.Sniper.OnThrottleReady, "pendingRequerySend")
      parked[7] = { itemID = 7 }
      assert.is_false(anyPath())
      parked[7] = nil
      local row = { purchaseStage = "confirming" }
      setUpvalue(GC.Sniper._QuietZoneOpen, "rows", { row })
      assert.is_false(anyPath())
      row.purchaseStage = nil
      assert.same({}, keysSent)
      assert.is_true(anyPath())
    end)

    -- Whatever still sends over a batch takes its answer with it, so the batch is written off at
    -- once instead of holding every keys consumer for the rest of its thirty seconds.
    it("writes a batch off when a search goes out over it anyway", function()
      local GC = loadSniper()
      _G.C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = true } end
      _G.C_AuctionHouse.SendSearchQuery = function() end
      batchOut(GC, "caps")
      upvalue(GC.Sniper.OnItemKeyInfo, "driver").sendSearch(42)
      assert.is_false(GC.Sniper._KeysOutstanding())
    end)

    it("sends no keys batch, on any path, while the watch loop's search is unanswered", function()
      local GC = loadSniper()
      openAH(GC)
      adoptCaps(GC, { { i = 42, c = 100 } })
      GC.Sniper._keyPoll:SetTargets({ 5 })
      local awaiting = true
      GC.Sniper.scanner = { Awaiting = function() return awaiting end, Wants = function() return false end }
      local buyPoll = { HasPending = function() return true end, NextBatch = function() return { 9 } end }
      assert.is_false(GC.Sniper._TrySendCapBatch())
      assert.is_false(GC.Sniper._TrySendKeysBatch())
      assert.is_false(GC.Sniper._TrySendKeysBatchFor(buyPoll, "buy", function() return true end))
      assert.same({}, keysSent)
      awaiting = false
      assert.is_true(GC.Sniper._TrySendCapBatch())
    end)
  end)

  -- Round 2. The player's own Check is the player, but sent over an unanswered keys batch it
  -- comes back empty -- "listing gone", the row deleted -- and a YOUR PRICE row did not come back
  -- while the lot sat there at the same price. It is held for the batch's answer instead, which
  -- normally lands in well under a second, and never for longer than LIM.CHECK_HOLD_SECONDS.
  describe("a player's Check while a keys batch is out", function()
    local searched

    local function setup()
      local GC = loadSniper()
      openAH(GC)
      searched = {}
      _G.C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = true } end
      _G.C_AuctionHouse.SendSearchQuery = function(key) searched[#searched + 1] = key.itemID end
      setUpvalue(GC.Sniper.OnThrottleReady, "isCurrentRequeryAttempt", function() return true end)
      adoptCaps(GC, { { i = 42, c = 100 } })
      local attempt = { itemID = 7, token = 1, row = {}, deal = { itemID = 7 } }
      return GC, attempt, upvalue(GC.Sniper.OnItemKeyInfo, "issueRequerySearch")
    end

    it("goes at once when no batch is out", function()
      local GC, attempt, issue = setup()
      issue(attempt)
      assert.same({ 7 }, searched)
      assert.is_nil(next(upvalue(GC.Sniper.OnThrottleReady, "pendingRequerySend")))
    end)

    it("waits for the batch's answer, and goes on the turn it brings", function()
      local GC, attempt, issue = setup()
      assert.is_true(GC.Sniper._TrySendCapBatch())
      issue(attempt)
      assert.same({}, searched)
      GC.Sniper.OnThrottleReady()
      assert.same({}, searched) -- nothing else sends meanwhile either
      answer(GC, {})
      GC.Sniper.OnThrottleReady()
      assert.same({ 7 }, searched)
      assert.is_true(attempt.sent)
    end)

    it("never waits longer than the hold, and then gives the batch up", function()
      local GC, attempt, issue = setup()
      local timers = {}
      _G.C_Timer.After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end
      assert.is_true(GC.Sniper._TrySendCapBatch())
      issue(attempt)
      assert.same({}, searched)
      assert.equal(1, #timers)
      assert.is_true(timers[1].seconds < 8) -- well inside the Check's own timeout
      now = now + timers[1].seconds
      timers[1].fn()
      assert.same({ 7 }, searched)
      assert.is_false(GC.Sniper._KeysOutstanding())
    end)
  end)

  -- Round 2, the safety net: a Check that came back empty for any reason ("listing gone") on a
  -- capped item re-arms the cap ratchets, so a false gone heals within the next round.
  describe("a gone on a capped item", function()
    local function gone(GC, itemID)
      local apply = upvalue(upvalue(GC.Sniper.OnItemKeyInfo, "finishRequery"), "applyRequeryResult")
      apply({ deal = { itemID = itemID, isCommodity = false, unitPrice = 90, cap = 100, auctionID = 9 } },
        itemID, nil)
    end

    it("is looked at again by the next cap round at the same price", function()
      local GC = loadSniper()
      adoptCaps(GC, { { i = 42, c = 100 } })
      GC.Sniper._capPoll:Fold({ browseRow(42, 90) })
      GC.Sniper._drillQueue:Clear()
      GC.Sniper._capPoll:Fold({ browseRow(42, 90) })
      assert.is_false(GC.Sniper._drillQueue:Has(42))
      gone(GC, 42)
      GC.Sniper._capPoll:Fold({ browseRow(42, 90) })
      assert.is_true(GC.Sniper._drillQueue:Has(42))
    end)

    it("is reported again by the next book pass at the same price", function()
      local GC = loadSniper()
      GC.db.commodityByItem[77] = true
      adoptCaps(GC, { { i = 77, c = 100 } })
      local book = { [77] = { floor = 90, qty = 5 } }
      assert.equal(1, #GC.Caps.BookHits(book, GC.Sniper._IsCommodityId))
      gone(GC, 77)
      assert.equal(1, #GC.Caps.BookHits(book, GC.Sniper._IsCommodityId))
    end)
  end)

  -- Round 2: a hover pre-warm refused because a keys batch was out is asked again once the batch
  -- is gone -- if the pointer is still on that row. OnEnter fires once; nothing else would.
  describe("a hover refused while a keys batch is out", function()
    local function hoverSetup()
      local GC = loadSniper()
      local warmed = {}
      local prewarm = upvalue(GC.Sniper.OnThrottleReady, "maybeStartPrewarm")
      setUpvalue(prewarm, "ahOpen", true)
      _G.C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = true } end
      _G.C_AuctionHouse.SendSearchQuery = function(key) warmed[#warmed + 1] = key.itemID end
      local row = { deal = { itemID = 42, unitPrice = 90, stale = true },
        IsVisible = function() return true end }
      setUpvalue(GC.Sniper._HoverPrewarm, "hoveredRow", row)
      GC.Sniper._keysAwaiting, GC.Sniper._keysOwner, GC.Sniper._keysBatch = clock, "caps", { 1 }
      GC.Sniper._HoverPrewarm(row)
      return GC, row, warmed
    end

    it("is warmed on the first turn after the batch is gone", function()
      local GC, _, warmed = hoverSetup()
      assert.same({}, warmed)
      GC.Sniper._keysAwaiting, GC.Sniper._keysOwner, GC.Sniper._keysBatch = nil, nil, nil
      GC.Sniper.OnThrottleReady()
      assert.same({ 42 }, warmed)
    end)

    it("is not, once the pointer has moved on", function()
      local GC, _, warmed = hoverSetup()
      setUpvalue(GC.Sniper._HoverPrewarm, "hoveredRow", nil)
      GC.Sniper._keysAwaiting, GC.Sniper._keysOwner, GC.Sniper._keysBatch = nil, nil, nil
      GC.Sniper.OnThrottleReady()
      assert.same({}, warmed)
    end)
  end)

  -- Round 1 (4a): a batch given up on is not proven gone -- the client's events carry no identity
  -- -- and before the caps' poll no keys batch was ever out on a board where Auto pages. A late
  -- answer read as the next pass's first page rebuilt the Commodities board from a hundred capped
  -- items.
  describe("a written-off batch that answers after all", function()
    local function arm(GC)
      openAH(GC)
      GC.db.settings.sniper.board = "commodities"
      adoptCaps(GC, { { i = 42, c = 100 } })
      assert.is_true(GC.Sniper._TrySendCapBatch())
      GC.Sniper.OnThrottledMessageDropped()
      assert.is_false(GC.Sniper._KeysOutstanding())
    end

    it("is not taken for the next pass's first page", function()
      local GC = loadSniper()
      _G.C_AuctionHouse.HasFullBrowseResults = function() return true end
      arm(GC)
      GC.Sniper._bookPass:Start("classes")
      GC.Sniper._bookPass:OnThrottleReady()
      answer(GC, { browseRow(42, 90) })   -- the cap batch's answer, late
      assert.is_true(GC.Sniper._bookPass:IsPaging())
      assert.is_nil(GC.Sniper._bookPass:Book()[42])
      answer(GC, { browseRow(7, 500) })   -- the pass's own page
      assert.is_false(GC.Sniper._bookPass:IsPaging())
      assert.equal(500, GC.Sniper._bookPass:Book()[7].floor)
    end)

    it("is not taken for the answer of the batch sent after it", function()
      local GC = loadSniper()
      arm(GC)
      GC.Sniper._keyPoll:SetTargets({ 5 })
      GC.db.settings.sniper.board = "items"
      now = now + 2
      assert.is_true(GC.Sniper._TrySendKeysBatch())
      answer(GC, { browseRow(42, 90) })   -- late: not the realm poll's
      assert.is_true(GC.Sniper._KeysOutstanding())
      assert.equal("sniper", GC.Sniper._keysOwner)
      answer(GC, { browseRow(5, 120) })   -- the realm poll's own
      assert.is_false(GC.Sniper._KeysOutstanding())
      assert.equal(120, GC.Sniper._keyPoll:Book()[5].floor)
    end)
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
      local poll = GC.Sniper._capPoll
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

    -- Round 1: only the ratchets that report cap hits. The realm poll reports none any more, and
    -- re-arming it queued an ordinary drill nobody had lost.
    it("does not re-arm the realm poll", function()
      local GC = loadSniper()
      values[42] = { kind = "realm_item", source = "import", mv = 250000, ref = 200000, refIlvl = 0 }
      GC.Data.TargetIds = function() return { 42 } end
      GC.Sniper._RebuildKeyTargets()
      GC.Sniper._keyPoll:Fold({ browseRow(42, 120000) })
      GC.Sniper._drillQueue:Clear()
      GC.Sniper._drillQueue:Push({ itemID = 42, floor = 90, estProfit = 10, priority = 1, cap = true })
      clock = clock + 91
      assert.is_false(GC.Sniper._drillQueue:Has(42))
      GC.Sniper._keyPoll:Fold({ browseRow(42, 120000) })
      assert.is_false(GC.Sniper._drillQueue:Has(42))
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

  -- Caps fixes 4a. Realm-item caps rode the Items board's keys batch, which only runs on that
  -- board, and commodity caps were seen only by Auto's book pass, which stands paused on it: half
  -- the caps slept at any moment, and on the Sell, Sold and BUY tabs all of them did. The caps
  -- have a poll of their own now, realm and commodity alike (a commodity's item key answers with
  -- its cheapest unit too -- the Sell tab's bulk fill and the BUY refresh already rely on it), and
  -- it runs whatever is on screen.
  describe("the cap poll", function()
    describe("what it asks about", function()
      it("is every cap: realm items and commodities, with or without a price of their own", function()
        local GC = loadSniper()
        GC.db.commodityByItem[77] = true
        adoptCaps(GC, { { i = 42, c = 100 }, { i = 77, c = 50 }, { i = 43, c = 100, l = 610 } })
        assert.equal(3, GC.Sniper._capPoll:Count())
        assert.same({ 42, 43, 77 }, GC.Sniper._capPoll:NextBatch())
      end)

      it("leaves the realm poll to its own lists", function()
        local GC = loadSniper()
        values[44] = { kind = "realm_item", source = "import", mv = 250000, ref = 200000, refIlvl = 0 }
        GC.Data.TargetIds = function() return { 44 } end
        adoptCaps(GC, { { i = 42, c = 100 }, { i = 44, c = 100 } })
        -- 42 is only a cap: the realm poll has nothing to price it by. 44 is a region target as
        -- well, and the realm poll keeps it for that.
        assert.same({ 44 }, GC.Sniper._keyPoll:NextBatch())
        assert.same({ 42, 44 }, GC.Sniper._capPoll:NextBatch())
      end)
    end)

    describe("when it asks", function()
      local function onView(GC, v, board)
        setUpvalue(GC.Sniper.OnThrottleReady, "view", v)
        GC.db.settings.sniper.board = board or "commodities"
      end

      for _, where in ipairs({ { "deals", "commodities" }, { "deals", "items" }, { "sold" } }) do
        it("asks on " .. where[1] .. (where[2] and (" / " .. where[2]) or ""), function()
          local GC = loadSniper()
          openAH(GC)
          adoptCaps(GC, { { i = 42, c = 100 }, { i = 77, c = 50 } })
          onView(GC, where[1], where[2])
          GC.Sniper.OnThrottleReady()
          assert.same({ { 42, 77 } }, keysSent)
          assert.equal("caps", GC.Sniper._keysOwner)
        end)
      end

      -- Round 1: the Sell and BUY tabs run searches of their own (the pricing walk, BUY's quotes),
      -- and a search sent on top of an unanswered keys batch takes its answer and comes back empty
      -- itself (UI/SellFrame.lua's advanceQuote, seen in game). The player's own tab wins.
      for _, v in ipairs({ "sell", "buy" }) do
        it("stays quiet on the " .. v .. " tab, and asks again back on Deals", function()
          local GC = loadSniper()
          openAH(GC)
          adoptCaps(GC, { { i = 42, c = 100 } })
          onView(GC, v)
          GC.Sniper.OnThrottleReady()
          assert.is_false(GC.Sniper._TrySendCapBatch())
          assert.same({}, keysSent)
          onView(GC, "deals")
          assert.is_true(GC.Sniper._TrySendCapBatch())
        end)
      end

      it("does not ask while the window is closed or the auction house is", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        GC.Sniper.IsWindowShown = function() return false end
        GC.Sniper.OnThrottleReady()
        GC.Sniper.IsWindowShown = function() return true end
        GC.Sniper.IsAHOpen = function() return false end
        GC.Sniper.OnThrottleReady()
        assert.same({}, keysSent)
      end)

      it("does not ask while the player is using the auction house themselves", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        GC.AuctionHouseTab.PlayerIsBusy = function() return true end
        GC.Sniper.OnThrottleReady()
        assert.is_false(GC.Sniper._TrySendCapBatch())
        assert.same({}, keysSent)
      end)

      it("does not ask while a purchase is in flight", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        local row = { purchaseStage = "confirming" }
        setUpvalue(GC.Sniper._QuietZoneOpen, "rows", { row })
        GC.Sniper.OnThrottleReady()
        assert.is_false(GC.Sniper._TrySendCapBatch())
        assert.same({}, keysSent)
        row.purchaseStage = nil
        assert.is_true(GC.Sniper._TrySendCapBatch())
      end)

      -- The auction-house ticker asks this directly, off the arbiter's own order, so the
      -- arbiter's first rule has to hold here too: the player's own Check goes first.
      it("does not ask ahead of a parked Check", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        local parked = upvalue(GC.Sniper.OnThrottleReady, "pendingRequerySend")
        parked[42] = { itemID = 42 }
        assert.is_false(GC.Sniper._TrySendCapBatch())
        parked[42] = nil
        assert.is_true(GC.Sniper._TrySendCapBatch())
      end)

      -- With Auto paging back to back, the end of a pass is the one settled buffer there is.
      it("asks the moment a pass completes", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        GC.Sniper._bookPass:Start("classes")
        GC.Sniper._bookPass:OnThrottleReady() -- the pass's query goes out...
        GC.Sniper.OnBrowseResults()           -- ...and its one page completes it
        assert.is_false(GC.Sniper._bookPass:IsPaging())
        assert.same({ { 42 } }, keysSent)
      end)

      it("never replaces a browse buffer a pass owns", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        GC.Sniper._bookPass:Start("classes") -- armed: the next page is the pass's
        assert.is_false(GC.Sniper._TrySendCapBatch())
        assert.same({}, keysSent)
      end)

      it("sends one batch at a time, a hundred keys at most", function()
        local GC = loadSniper()
        openAH(GC)
        local caps = {}
        for i = 1, 150 do caps[i] = { i = 1000 + i, c = 100 } end
        adoptCaps(GC, caps)
        assert.is_true(GC.Sniper._TrySendCapBatch())
        assert.is_false(GC.Sniper._TrySendCapBatch()) -- the first is still out
        assert.equal(1, #keysSent)
        assert.equal(100, #keysSent[1])
      end)
    end)

    -- Fairness. A cap batch holds the one keys interlock until it answers, and every other
    -- consumer of it -- the Items board's poll, the BUY refresh, the Sell tab's bulk fill, and
    -- Auto's next pass (which may not start over an outstanding batch) -- asks again at least
    -- once every 1.25 seconds. So after each answer the cap poll stands aside for a breath longer
    -- than that, and whoever was waiting goes first; between two rounds it rests longer still.
    describe("how it shares the slot", function()
      it("stands aside for a breath after each answer, and the realm poll goes in between", function()
        local GC = loadSniper()
        openAH(GC)
        values[5] = { kind = "realm_item", source = "import", mv = 250000, ref = 200000, refIlvl = 0 }
        GC.Data.TargetIds = function() return { 5 } end
        local caps = {}
        for i = 1, 150 do caps[i] = { i = 1000 + i, c = 100 } end
        adoptCaps(GC, caps)
        GC.db.settings.sniper.board = "items"

        GC.Sniper.OnThrottleReady()
        assert.equal(100, #keysSent[1]) -- the caps went first
        answer(GC, {})
        GC.Sniper.OnThrottleReady()
        assert.same({ 5 }, keysSent[2]) -- the realm poll, while the caps stand aside
        answer(GC, {})
        GC.Sniper.OnThrottleReady()
        assert.equal(2, #keysSent)       -- still inside the breath

        now = now + 2
        GC.Sniper.OnThrottleReady()
        assert.equal(50, #keysSent[3])   -- the rest of the round
      end)

      it("lets an armed pass take the buffer before its next batch", function()
        local GC = loadSniper()
        openAH(GC)
        local sentBrowse = 0
        _G.C_AuctionHouse.SendBrowseQuery = function() sentBrowse = sentBrowse + 1 end
        local caps = {}
        for i = 1, 150 do caps[i] = { i = 1000 + i, c = 100 } end
        adoptCaps(GC, caps)

        GC.Sniper.OnThrottleReady()
        answer(GC, {})
        GC.Sniper._bookPass:Start("classes")
        now = now + 2
        GC.Sniper.OnThrottleReady()
        assert.equal(1, sentBrowse)
        assert.equal(1, #keysSent)
      end)

      it("rests between two rounds", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        assert.is_true(GC.Sniper._TrySendCapBatch())
        answer(GC, {})
        now = now + 2
        assert.is_false(GC.Sniper._TrySendCapBatch())
        now = now + 3
        assert.is_true(GC.Sniper._TrySendCapBatch())
        assert.same({ { 42 }, { 42 } }, keysSent)
      end)

      it("takes a breath after a batch the client dropped", function()
        local GC = loadSniper()
        openAH(GC)
        local caps = {}
        for i = 1, 150 do caps[i] = { i = 1000 + i, c = 100 } end
        adoptCaps(GC, caps)
        assert.is_true(GC.Sniper._TrySendCapBatch())
        GC.Sniper.OnThrottledMessageDropped()
        assert.is_false(GC.Sniper._KeysOutstanding())
        assert.is_false(GC.Sniper._TrySendCapBatch())
        now = now + 2
        assert.is_true(GC.Sniper._TrySendCapBatch())
      end)

      it("rests between rounds after a last batch the client dropped", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        assert.is_true(GC.Sniper._TrySendCapBatch())
        GC.Sniper.OnThrottledMessageDropped()
        now = now + 2
        assert.is_false(GC.Sniper._TrySendCapBatch())
        now = now + 3
        assert.is_true(GC.Sniper._TrySendCapBatch())
      end)

      -- Round 1: a batch still out when the player opens the Sell or BUY tab is one their searches
      -- may take the answer of -- and the Sell walk now waits for it. It gets the Sell tab's own
      -- eight seconds there, not thirty.
      it("gets eight seconds, not thirty, while the Sell or BUY tab is on screen", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        assert.is_true(GC.Sniper._TrySendCapBatch())
        clock = clock + 8
        assert.is_true(GC.Sniper._KeysOutstanding()) -- on Deals: the full thirty
        setUpvalue(GC.Sniper.OnThrottleReady, "view", "sell")
        assert.is_false(GC.Sniper._KeysOutstanding())
      end)

      -- Round 1: while a batch is out no background search of ours goes (drills, the verify walk,
      -- the watch loop), so the breath after it is what they get. It is at least as long as the
      -- batch held the interlock -- they get half the time or better however slowly the auction
      -- house answers -- up to the eight seconds the Sell tab waits.
      it("stands aside at least as long as its last batch took to answer", function()
        local GC = loadSniper()
        openAH(GC)
        local caps = {}
        for i = 1, 150 do caps[i] = { i = 1000 + i, c = 100 } end
        adoptCaps(GC, caps)
        assert.is_true(GC.Sniper._TrySendCapBatch())
        clock, now = clock + 6, now + 6
        answer(GC, {})
        now = now + 5
        assert.is_false(GC.Sniper._TrySendCapBatch())
        now = now + 1
        assert.is_true(GC.Sniper._TrySendCapBatch())
      end)

      it("takes a breath after a batch that never answered, too", function()
        local GC = loadSniper()
        openAH(GC)
        local caps = {}
        for i = 1, 150 do caps[i] = { i = 1000 + i, c = 100 } end
        adoptCaps(GC, caps)
        assert.is_true(GC.Sniper._TrySendCapBatch())
        clock = clock + 31 -- written off (LIM.KEYS_TIMEOUT_SECONDS)
        now = now + 31
        assert.is_false(GC.Sniper._KeysOutstanding())
        assert.is_false(GC.Sniper._TrySendCapBatch())
        now = now + 7
        assert.is_false(GC.Sniper._TrySendCapBatch())
        now = now + 1 -- the breath tops out at the Sell tab's eight seconds
        assert.is_true(GC.Sniper._TrySendCapBatch())
      end)
    end)

    describe("what an answer does", function()
      it("folds into the cap poll and queues your-price drills, realm and commodity alike", function()
        local GC = loadSniper()
        openAH(GC)
        GC.db.commodityByItem[77] = true
        adoptCaps(GC, { { i = 42, c = 100 }, { i = 77, c = 50 } })
        GC.Sniper.OnThrottleReady()
        answer(GC, { browseRow(42, 90), browseRow(77, 40) })

        assert.equal(90, GC.Sniper._capPoll:Book()[42].floor)
        assert.is_nil(GC.Sniper._keyPoll:Book()[42])
        for _, itemID in ipairs({ 42, 77 }) do
          assert.is_true(GC.Sniper._drillQueue:Has(itemID))
        end
        local head = GC.Sniper._drillQueue:Peek()
        assert.equal(1, head.priority)
        assert.is_true(head.cap)
        assert.is_nil(GC.Sniper._keysAwaiting) -- and the interlock is free again
      end)

      it("says nothing about a floor above the cap", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        GC.Sniper.OnThrottleReady()
        answer(GC, { browseRow(42, 150) })
        assert.is_false(GC.Sniper._drillQueue:Has(42))
      end)

      -- The arbiter re-reads the book before it spends a send on a queued hit and drops one whose
      -- floor has moved. It asked the book pass and the realm poll -- neither of which ever sees a
      -- cap-only item now -- so without the cap poll's book every one of these hits was dropped.
      it("is drilled, not dropped as a floor nobody has seen", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        GC.Sniper.OnThrottleReady()
        answer(GC, { browseRow(42, 90) })

        local drilled = {}
        setUpvalue(GC.Sniper.OnThrottleReady, "canDrillNow", function() return true end)
        setUpvalue(GC.Sniper.OnThrottleReady, "maybeStartPrewarm", function(deal)
          drilled[#drilled + 1] = deal.itemID
          return true
        end)
        GC.Sniper.OnThrottleReady()
        assert.same({ 42 }, drilled)
      end)

      it("drills a realm cap on the variant key the cap poll saw", function()
        local GC = loadSniper()
        adoptCaps(GC, { { i = 42, c = 100 } })
        GC.Sniper._capPoll:Fold({
          { itemKey = { itemID = 42, itemLevel = 19, itemSuffix = 0, battlePetSpeciesID = 0 },
            minPrice = 120, totalQuantity = 1 },
          { itemKey = { itemID = 42, itemLevel = 66, itemSuffix = 0, battlePetSpeciesID = 0 },
            minPrice = 90, totalQuantity = 1 },
        })
        _G.C_AuctionHouse.MakeItemKey = function(itemID, itemLevel)
          return { itemID = itemID, itemLevel = itemLevel or 0 }
        end
        local driver = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
        assert.equal(66, driver.variantKey(42).itemLevel)
      end)
    end)

    -- The cap poll is also what now keeps a "your price" row honest between drills, wherever it
    -- lives: it asked about the item by name, so a floor above the cap -- or no answer at all --
    -- says the row is over.
    describe("the rows it keeps", function()
      local function capDeal(itemID, isCommodity, unitPrice, cap)
        return { itemID = itemID, isCommodity = isCommodity, unitPrice = unitPrice, qty = 1,
          auctionID = (not isCommodity) and 999 or nil, discount = 0, profit = 1, estProfit = 1,
          tier = "WATCH", cap = cap, stale = true }
      end

      local function polled(GC, rows)
        GC.Sniper.OnThrottleReady()
        answer(GC, rows)
      end

      it("keeps a realm row while the floor stays at or under the cap", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        local held = capDeal(42, false, 80, 100)
        GC.Sniper._realmDeals[42] = held
        polled(GC, { browseRow(42, 90) })
        assert.equal(held, GC.Sniper._realmDeals[42])
      end)

      it("takes a realm row down once the floor climbs above the cap, or the item is gone", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 }, { i = 43, c = 100 } })
        GC.Sniper._realmDeals[42] = capDeal(42, false, 80, 100)
        GC.Sniper._realmDeals[43] = capDeal(43, false, 80, 100)
        polled(GC, { browseRow(42, 150) })
        assert.is_nil(GC.Sniper._realmDeals[42])
        assert.is_nil(GC.Sniper._realmDeals[43])
      end)

      it("leaves an ordinary realm row to the realm poll", function()
        local GC = loadSniper()
        openAH(GC)
        adoptCaps(GC, { { i = 42, c = 100 } })
        local ordinary = { itemID = 42, isCommodity = false, unitPrice = 130000, qty = 1, stale = true }
        GC.Sniper._realmDeals[42] = ordinary
        polled(GC, { browseRow(42, 150) })
        assert.equal(ordinary, GC.Sniper._realmDeals[42])
      end)

      it("takes a commodity row down once the floor climbs above the cap", function()
        local GC = loadSniper()
        openAH(GC)
        GC.db.commodityByItem[77] = true
        adoptCaps(GC, { { i = 77, c = 50 } })
        GC.Sniper._PutCapRow(77, capDeal(77, true, 40, 50))
        assert.is_table(GC.Sniper._BoardCapRow({ itemID = 77, isCommodity = true }))
        polled(GC, { browseRow(77, 60) })
        assert.is_nil(GC.Sniper._BoardCapRow({ itemID = 77, isCommodity = true }))
      end)

      it("keeps a commodity row while the floor holds", function()
        local GC = loadSniper()
        openAH(GC)
        GC.db.commodityByItem[77] = true
        adoptCaps(GC, { { i = 77, c = 50 } })
        GC.Sniper._PutCapRow(77, capDeal(77, true, 40, 50))
        polled(GC, { browseRow(77, 45) })
        assert.is_table(GC.Sniper._BoardCapRow({ itemID = 77, isCommodity = true }))
      end)

      -- The same rule as the book pass's (caps fixes 3f): a price that went above the cap and
      -- comes back down to where it was is a new opportunity, and rings as one.
      it("forgets what it announced once the floor is above the cap", function()
        local GC = loadSniper()
        openAH(GC)
        GC.db.commodityByItem[77] = true
        adoptCaps(GC, { { i = 77, c = 50 } })
        GC.Caps.Announce({ itemID = 77, isCommodity = true, unitPrice = 40 })
        polled(GC, { browseRow(77, 60) })
        assert.is_true(GC.Caps.IsNews({ itemID = 77, isCommodity = true, unitPrice = 40 }))
      end)
    end)

    -- Caps fixes 4c. "610 or better, at 100": the poll's aggregate floor is the cheapest variant
    -- of ANY level, so the cap woke for every move of a 590 -- a priority drill each time, which
    -- the cap then refused -- and never for a drop on the 615 it was actually waiting for, as
    -- long as the 590 sat under it.
    describe("with an item-level floor", function()
      local function variantRow(itemID, itemLevel, minPrice)
        return { itemKey = { itemID = itemID, itemLevel = itemLevel, itemSuffix = 0, battlePetSpeciesID = 0 },
          minPrice = minPrice, totalQuantity = 1 }
      end

      it("does not spend a drill on a variant below its level", function()
        local GC = loadSniper()
        adoptCaps(GC, { { i = 42, c = 100, l = 610 } })
        GC.Sniper._capPoll:Fold({ variantRow(42, 590, 50), variantRow(42, 615, 150) })
        GC.Sniper._capPoll:Fold({ variantRow(42, 590, 40), variantRow(42, 615, 150) })
        assert.is_false(GC.Sniper._drillQueue:Has(42))
      end)

      it("drills a drop on the variant at its level while a cheaper one sits under it", function()
        local GC = loadSniper()
        adoptCaps(GC, { { i = 42, c = 100, l = 610 } })
        GC.Sniper._capPoll:Fold({ variantRow(42, 590, 40), variantRow(42, 615, 150) })
        GC.Sniper._capPoll:Fold({ variantRow(42, 590, 40), variantRow(42, 615, 90) })
        local head = GC.Sniper._drillQueue:Peek()
        assert.equal(42, head.itemID)
        assert.equal(90, head.floor)
        assert.is_true(head.cap)

        -- ...and the arbiter does not throw it away for failing to match the aggregate floor (40):
        -- the book it re-reads is judged at the cap's level too.
        local drilled = {}
        setUpvalue(GC.Sniper.OnThrottleReady, "canDrillNow", function() return true end)
        setUpvalue(GC.Sniper.OnThrottleReady, "maybeStartPrewarm", function(deal)
          drilled[#drilled + 1] = deal.itemID .. "@" .. deal.unitPrice
          return true
        end)
        GC.Sniper.OnThrottleReady()
        assert.same({ "42@90" }, drilled)
      end)

      -- An item level means nothing to a commodity -- GC.Caps.DecideCommodity never reads one --
      -- and its browse row states none. Held to one anyway, the cap could never fire.
      it("means nothing to a commodity", function()
        local GC = loadSniper()
        openAH(GC)
        GC.db.commodityByItem[77] = true
        adoptCaps(GC, { { i = 77, c = 50, l = 610 } })
        GC.Sniper._PutCapRow(77, { itemID = 77, isCommodity = true, unitPrice = 40, qty = 1,
          discount = 0, profit = 1, estProfit = 1, tier = "WATCH", cap = 50, stale = true })
        GC.Sniper.OnThrottleReady()
        answer(GC, { browseRow(77, 40) })
        assert.is_true(GC.Sniper._drillQueue:Has(77))
        assert.is_table(GC.Sniper._BoardCapRow({ itemID = 77, isCommodity = true }))
      end)
    end)

    -- Round 1 (4a): an item a batch asked about and got no row for has no listing left. The row
    -- goes (above) -- and the poll's own ratchet has to let go of it too, or the same price listed
    -- again is not news: the book still says 90, and 90 is not a change.
    it("reports a relisting at the same price after the item was gone", function()
      local GC = loadSniper()
      openAH(GC)
      adoptCaps(GC, { { i = 42, c = 100 } })
      local function round(rows)
        GC.Sniper._TrySendCapBatch()
        answer(GC, rows)
        GC.Sniper._drillQueue:Clear()
        now = now + 5
      end
      round({ browseRow(42, 90) })
      round({})                      -- sold
      GC.Sniper._TrySendCapBatch()
      answer(GC, { browseRow(42, 90) }) -- listed again, at the same price
      assert.is_true(GC.Sniper._drillQueue:Has(42))
    end)

    -- Round 1 (4c): a client that answers gear with one collapsed row (itemLevel 0) states no
    -- level at all. Held to a level nothing states, every item-level cap stopped firing silently.
    it("falls back to the item's own floor when no row states an item level", function()
      local GC = loadSniper()
      adoptCaps(GC, { { i = 42, c = 100, l = 610 } })
      GC.Sniper._capPoll:Fold({ browseRow(42, 90) })
      assert.is_true(GC.Sniper._drillQueue:Has(42))
    end)

    it("forgets its book when the auction house closes", function()
      local GC = loadSniper()
      adoptCaps(GC, { { i = 42, c = 100 } })
      GC.Sniper._capPoll:Fold({ browseRow(42, 90) })
      GC.Sniper.OnAuctionHouseClosed()
      assert.is_nil(GC.Sniper._capPoll:Book()[42])
      assert.equal(1, GC.Sniper._capPoll:Count()) -- the caps themselves are not session state
    end)
  end)
end)
