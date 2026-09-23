local helper = require("spec.spec_helper")

describe("Book pass wiring", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  -- Unused by Task 4's own single test below (it only reads GC.Sniper._bookPass, never pokes
  -- an upvalue), but Task 5 extends this same describe block with a test that calls it --
  -- kept here rather than reintroduced there, per this batch's plan.
  -- luacheck: ignore set
  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local browseSent, browseQueries, browseResults

  -- One browse row in the shape C_AuctionHouse.GetBrowseResults() returns.
  local function browseRow(itemID, minPrice, totalQuantity)
    return { itemKey = { itemID = itemID }, minPrice = minPrice, totalQuantity = totalQuantity or 50 }
  end

  -- An import value rich enough to survive GC.SniperDecision.PreScreen AND to evaluate to a
  -- deal: mv well above the asking prices below, a real stress exit, and liquidity facts past
  -- every hard gate. Overrides let a test fail exactly one of them.
  local function dealValue(overrides)
    local value = { kind = "commodity", source = "import", mv = 250000, stressUnit = 200000,
      sold = 12, sellThroughBps = 9000, liquidityConfidence = 90, listings = 20,
      currentQty = 400, trend = 0 }
    for k, v in pairs(overrides or {}) do value[k] = v end
    return value
  end

  local function loadSniper(enum)
    browseSent, browseQueries, browseResults = 0, {}, {}
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.GetMoney = function() return 10 * 1000 * 10000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.PlaySound = function() end
    _G.SOUNDKIT = { READY_CHECK = 8960, MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Enum = enum or { ItemClass = { Tradegoods = 7, Consumable = 0, Gem = 3, ItemEnhancement = 8,
      Miscellaneous = 15 } }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function(query)
        browseSent = browseSent + 1
        browseQueries[#browseQueries + 1] = query
      end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return true end,
      GetBrowseResults = function() return browseResults end,
    }

    -- The real Core/Init.lua sniper defaults for everything Core/DealMath.lua and
    -- Core/SniperDecision.lua actually read -- a partial table here would make a missing
    -- threshold look like a scan that found nothing.
    local GC = { db = { settings = { sniper = { sound = true, showRefused = false,
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
    GC.Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end }
    GC.Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end }
    GC.Print = function() end
    GC.AuctionHouseTab = { PlayerIsBusy = function() return false end }
    helper.loadModule("UI/SniperFrame.lua", GC)
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.C_AuctionHouse, _G.Enum = nil, nil
  end)

  it("sends a class-filtered query, not an empty one, when Auto starts a fresh pass", function()
    local GC = loadSniper()
    -- Reach the real Core/AutoScan.lua machine the way autoscan_wiring_spec.lua does --
    -- feedAuto is a direct upvalue of OnAuctionHouseShow, autoScan a direct upvalue of
    -- feedAuto -- and drive it without ever building the real frame (Tick's own startScan
    -- action calls the real startFullScan(), whose own refreshRows()/etc. all no-op safely
    -- with `frame` still nil).
    local feedAuto = upvalue(GC.Sniper.OnAuctionHouseShow, "feedAuto")
    local autoScan = upvalue(feedAuto, "autoScan")

    autoScan:Input("toggleOn", 1000)
    autoScan:Tick(1000)
    assert.equal(1, browseSent)
    local classes = {}
    for i, filter in ipairs(browseQueries[1].itemClassFilters) do classes[i] = filter.classID end
    assert.same({ 7, 0, 3, 8, 15 }, classes)
  end)

  it("grants a drill-down before a page even while a book pass is mid-paging", function()
    local GC = loadSniper()
    local searched = {}
    -- Reach the same `driver` the search/purchase path uses (installed at file scope, a
    -- direct upvalue of GC.Sniper.OnItemKeyInfo -- see watch_loop_spec.lua's own use of this
    -- exact upvalue) and swap its sendSearch so a drill-down is observable without a real
    -- item key.
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    driverTbl.getKeyInfo = function() return { isCommodity = true } end
    driverTbl.sendSearch = function(itemID) searched[#searched + 1] = itemID end

    set(GC.Sniper.OnAuctionHouseShow, "ahOpen", true)
    -- The book has to agree that this is still the price the hit was flagged at, or the
    -- arbiter (rightly) drops it as stale instead of spending a send on it.
    GC.Sniper._bookPass:Book()[777] = { floor = 100 }
    GC.Sniper._drillQueue:Push({ itemID = 777, floor = 100, estProfit = 5000 })
    GC.Sniper.OnThrottleReady()
    assert.same({ 777 }, searched)
    assert.equal(0, browseSent) -- the book pass never even got asked this turn
  end)

  it("sends the book pass's deferred start after a queued drill-down is served", function()
    local GC = loadSniper()
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    driverTbl.getKeyInfo = function() return { isCommodity = true } end
    driverTbl.sendSearch = function() end

    set(GC.Sniper.OnAuctionHouseShow, "ahOpen", true)

    -- Throttle busy at Start() time: the book pass's own send is deferred rather than sent.
    _G.C_AuctionHouse.IsThrottledMessageSystemReady = function() return false end
    GC.Sniper._bookPass:Start("classes")
    assert.equal(0, browseSent)

    -- A slot cycle: throttle is ready again, and a drill-down is queued ahead of the pass.
    _G.C_AuctionHouse.IsThrottledMessageSystemReady = function() return true end
    GC.Sniper._bookPass:Book()[777] = { floor = 100 }
    GC.Sniper._drillQueue:Push({ itemID = 777, floor = 100, estProfit = 5000 })
    GC.Sniper.OnThrottleReady()
    assert.equal(0, browseSent) -- drill-down outranked the page this cycle

    -- Next cycle: the deferred start goes out.
    GC.Sniper.OnThrottleReady()
    assert.equal(1, browseSent)
  end)

  -- A drill-down that CANNOT be sent must not cost a send. Before this, the arbiter popped
  -- (charging the 60/min budget) and only then asked whether a query could go out, so one
  -- rich hit nothing could ever drill parked at the head of the queue and burned the whole
  -- budget, tick after tick, for every other item on the board.
  it("charges nothing for a drill-down the pre-warm slot refuses", function()
    local GC = loadSniper()
    local searched = {}
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    driverTbl.getKeyInfo = function() return { isCommodity = true } end
    driverTbl.sendSearch = function(itemID) searched[#searched + 1] = itemID end

    set(GC.Sniper.OnAuctionHouseShow, "ahOpen", true)
    -- A one-send budget, so a charge is impossible to miss.
    GC.Sniper._drillQueue = GC.DrillQueue.New({ now = _G.time }, { perMinute = 1 })
    GC.Sniper._bookPass:Book()[777] = { floor = 100 }
    GC.Sniper._drillQueue:Push({ itemID = 777, floor = 100, estProfit = 5000 })

    -- One pre-warm in flight globally: this drill-down cannot send this turn.
    set(GC.Sniper.OnItemSearchResults, "prewarmAttempt", { itemID = 42, token = 1, deal = {} })
    GC.Sniper.OnThrottleReady()
    assert.same({}, searched)
    assert.equal(1, GC.Sniper._drillQueue:Depth()) -- still queued

    -- The slot frees up, and the one send in the budget is still there to spend.
    set(GC.Sniper.OnItemSearchResults, "prewarmAttempt", nil)
    GC.Sniper.OnThrottleReady()
    assert.same({ 777 }, searched)
  end)

  it("drops a hit the book has already moved past, and serves the next one in the same turn", function()
    local GC = loadSniper()
    local searched = {}
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    driverTbl.getKeyInfo = function() return { isCommodity = true } end
    driverTbl.sendSearch = function(itemID) searched[#searched + 1] = itemID end

    set(GC.Sniper.OnAuctionHouseShow, "ahOpen", true)
    GC.Sniper._drillQueue = GC.DrillQueue.New({ now = _G.time }, { perMinute = 1 })
    -- 777 is the richest hit queued, but the book has since read a different floor for it:
    -- the price it was flagged at is gone, so there is nothing to drill.
    GC.Sniper._bookPass:Book()[777] = { floor = 90 }
    GC.Sniper._bookPass:Book()[888] = { floor = 200 }
    GC.Sniper._drillQueue:Push({ itemID = 777, floor = 100, estProfit = 9000 })
    GC.Sniper._drillQueue:Push({ itemID = 888, floor = 200, estProfit = 100 })

    GC.Sniper.OnThrottleReady()
    assert.same({ 888 }, searched)                 -- the stale head cost nothing, not even a turn
    assert.equal(0, GC.Sniper._drillQueue:Depth()) -- and it is gone, not parked at the head again
  end)

  it("empties the book and the drill queue when the auction house closes", function()
    local GC = loadSniper()
    GC.Sniper._bookPass:Book()[777] = { floor = 100 }
    GC.Sniper._drillQueue:Push({ itemID = 777, floor = 100, estProfit = 5000 })

    GC.Sniper.OnAuctionHouseClosed()

    assert.is_nil(next(GC.Sniper._bookPass:Book()))
    assert.equal(0, GC.Sniper._drillQueue:Depth())
  end)

  it("never queues a hit the discovery pre-screen would refuse", function()
    local GC = loadSniper()
    -- Below its trigger (140000 for this value at the default floors), so the book pass hits.
    browseResults = { browseRow(500, 100000) }

    GC.Data.GetItemValue = function() return dealValue({ sold = 0 }) end -- velocity_too_low
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper._bookPass:OnResultsUpdated()
    assert.equal(0, GC.Sniper._drillQueue:Depth())

    -- Same hit, same price, a market the pre-screen accepts: now it queues.
    GC.Data.GetItemValue = function() return dealValue() end
    GC.Sniper._bookPass:Reset()
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper._bookPass:OnResultsUpdated()
    assert.equal(1, GC.Sniper._drillQueue:Depth())
  end)

  it("keeps the wide pass's out-of-class finds through a classes pass", function()
    local GC = loadSniper()
    GC.Data.GetItemValue = function() return dealValue() end

    local function boardHas(itemID)
      for _, deal in ipairs(upvalue(GC.Sniper.OnAuctionHouseShow, "scanDeals")) do
        if deal.itemID == itemID then return true end
      end
      return false
    end

    -- A wide pass sees both: 100 is a reagent the classes filter covers, 500 is not.
    browseResults = { browseRow(100, 100000), browseRow(500, 100000) }
    GC.Sniper._bookPass:Start("wide")
    GC.Sniper._bookPass:OnResultsUpdated()
    assert.is_true(boardHas(100))
    assert.is_true(boardHas(500))

    -- A classes pass cannot see 500 at all. Erasing it would mean the board forgot a deal
    -- nothing has disproved, every few seconds, for as long as Auto runs.
    browseResults = { browseRow(100, 100000) }
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper._bookPass:OnResultsUpdated()
    assert.is_true(boardHas(100))
    assert.is_true(boardHas(500))

    -- The next wide pass DID look and did not find it: now it goes.
    GC.Sniper._bookPass:Start("wide")
    GC.Sniper._bookPass:OnResultsUpdated()
    assert.is_true(boardHas(100))
    assert.is_false(boardHas(500))
  end)

  -- The re-review's reproduction: "did not see" used to mean only "no browse row in THIS
  -- classes pass", which cannot tell an out-of-class item from an in-class one that genuinely
  -- sold out between passes -- the sold-out one got resurrected from _wideExtras for up to
  -- widePassSeconds. SeenByClasses fixes it: an item a classes pass has EVER folded is known
  -- in-class, and a later classes pass's silence about it means gone, not unseen.
  it("does not resurrect an in-class item that sold out, even though a wide pass saw it too", function()
    local GC = loadSniper()
    GC.Data.GetItemValue = function() return dealValue() end

    local function boardHas(itemID)
      for _, deal in ipairs(upvalue(GC.Sniper.OnAuctionHouseShow, "scanDeals")) do
        if deal.itemID == itemID then return true end
      end
      return false
    end

    -- 100 is in-class: an earlier classes pass has already folded it.
    browseResults = { browseRow(100, 100000) }
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper._bookPass:OnResultsUpdated()
    assert.is_true(boardHas(100))

    -- A wide pass finds both 100 (still there) and 500, the genuine out-of-class find.
    browseResults = { browseRow(100, 100000), browseRow(500, 100000) }
    GC.Sniper._bookPass:Start("wide")
    GC.Sniper._bookPass:OnResultsUpdated()
    assert.is_true(boardHas(100))
    assert.is_true(boardHas(500))

    -- 100 sells out: the next classes pass returns zero rows. Its silence about 100 is
    -- authoritative (100 is in-class, the pass looked and found nothing), unlike its silence
    -- about 500 (out-of-class, the pass never asked).
    browseResults = {}
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper._bookPass:OnResultsUpdated()
    assert.is_false(boardHas(100))
    assert.is_true(boardHas(500))
  end)

  -- Owner-reported gap: a SAFE verdict must not outlive the price it was computed at.
  -- verdictFor already refuses one whose unitPrice no longer matches the row -- the piece this
  -- proves is that the row's OWN price actually moves on the very next fold, in-class, with no
  -- wait for anything else. FullScan.MergeDeals' "incoming wins unconditionally" contract is
  -- what does it: a fold hands scanDeals a brand-new deal table for the item, never a mutation
  -- of the old one, so the stale table a stored verdict was keyed against simply stops being
  -- what's on the board.
  it("refreshes an in-class item's price on the very next classes-pass fold", function()
    local GC = loadSniper()
    -- A higher mv than dealValue()'s default: both 19.23g and 27.61g need to stay a real
    -- discount off it, or the repriced pass screens the row out as no longer a deal at all
    -- instead of exercising the refresh this test is about.
    GC.Data.GetItemValue = function() return dealValue({ mv = 500000, stressUnit = 400000 }) end

    local function dealFor(itemID)
      for _, deal in ipairs(upvalue(GC.Sniper.OnAuctionHouseShow, "scanDeals")) do
        if deal.itemID == itemID then return deal end
      end
    end

    browseResults = { browseRow(100, 192300) } -- 19.23g
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper._bookPass:OnResultsUpdated()
    local first = dealFor(100)
    assert.is_not_nil(first)
    assert.equal(192300, first.unitPrice)

    -- A previous live Check stamped SAFE at exactly this price.
    local clearDeals = upvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = upvalue(clearDeals, "refreshRows")
    local setRowDeal = upvalue(refreshRows, "setRowDeal")
    local verdictFor = upvalue(setRowDeal, "verdictFor")
    local verdicts = upvalue(verdictFor, "verdicts")
    verdicts[100] = { unitPrice = first.unitPrice, at = 100, buyable = true, status = "SAFE" }
    assert.is_not_nil(verdictFor(dealFor(100)))

    -- The next classes pass folds 100 again and reports a different floor.
    browseResults = { browseRow(100, 276100) } -- 27.61g
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper._bookPass:OnResultsUpdated()

    local refolded = dealFor(100)
    assert.equal(276100, refolded.unitPrice)  -- the board carries the new floor
    assert.is_nil(verdictFor(refolded))       -- and the old SAFE verdict no longer applies to it
  end)

  it("scans Miscellaneous even on a client whose Enum does not name it", function()
    local GC = loadSniper({ ItemClass = { Tradegoods = 7, Consumable = 0, Gem = 3, ItemEnhancement = 8 } })
    local feedAuto = upvalue(GC.Sniper.OnAuctionHouseShow, "feedAuto")
    local autoScan = upvalue(feedAuto, "autoScan")
    autoScan:Input("toggleOn", 1000)
    autoScan:Tick(1000)
    local classes = {}
    for i, filter in ipairs(browseQueries[1].itemClassFilters) do classes[i] = filter.classID end
    assert.same({ 7, 0, 3, 8, 15 }, classes)
  end)

  it("queues a hit with how likely it is to sell", function()
    local GC = loadSniper()
    browseResults = { browseRow(500, 100000) }
    GC.Data.GetItemValue = function() return dealValue({ sellThroughBps = 8000, liquidityConfidence = 90 }) end
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper._bookPass:OnResultsUpdated()
    local head = GC.Sniper._drillQueue:Peek()
    assert.equal(500, head.itemID)
    assert.equal(0.8, head.confidence)
  end)

  it("hands an ordinary hit the drill queue lost back to the book pass, and a cap's to the caps", function()
    local GC = loadSniper()
    local lostToPass, rearmed = {}, {}
    GC.Sniper._bookPass = { Lost = function(_, itemID, floor) lostToPass[#lostToPass + 1] = { itemID, floor } end }
    GC.Caps = { Rearm = function(itemID) rearmed[#rearmed + 1] = itemID end }
    GC.Sniper._OnDrillLost({ itemID = 5, floor = 100, priority = 0, cap = false })
    GC.Sniper._OnDrillLost({ itemID = 6, floor = 100, priority = 1, cap = true })
    assert.same({ { 5, 100 } }, lostToPass)
    assert.same({ 6 }, rearmed)
  end)

  -- Fix round 1 (m3): a realm item's hit comes from the key poll, whose ratchet never repeats an
  -- unchanged floor. Lost, it is re-armed there too -- under the same hold as the book pass's
  -- re-hit, and only while the poll still shows the floor that was lost.
  it("re-arms the realm poll for an ordinary hit it lost, at the floor the poll still shows", function()
    local GC = loadSniper()
    local rearmedPoll = {}
    GC.Sniper._bookPass = { Lost = function() end }
    GC.Sniper._keyPoll = {
      Book = function() return { [5] = { judged = 100 }, [6] = { judged = 90 } } end,
      Rearm = function(_, itemID, holdSeconds) rearmedPoll[#rearmedPoll + 1] = { itemID, holdSeconds } end,
    }
    GC.Sniper._OnDrillLost({ itemID = 5, floor = 100, priority = 0, cap = false })
    GC.Sniper._OnDrillLost({ itemID = 6, floor = 100, priority = 0, cap = false }) -- the poll moved on
    GC.Sniper._OnDrillLost({ itemID = 7, floor = 100, priority = 0, cap = false }) -- never polled
    assert.same({ { 5, 120 } }, rearmedPoll)
  end)

  it("prints the sniper's supply counters on /gc board", function()
    local GC = loadSniper()
    GC.Data.FactItemIds = function() return { 1, 2, 3 } end
    GC.Sniper._drillQueue:Push({ itemID = 9, floor = 100, estProfit = 1 })
    GC.Sniper._drillShare.drills, GC.Sniper._drillShare.pages = 4, 2
    GC.Sniper._lastPass = { kind = "classes", seconds = 12, pages = 9, items = 900 }
    local printed = {}
    GC.Print = function(line) printed[#printed + 1] = line end
    GC.Sniper.DebugBoard()
    local line
    for _, text in ipairs(printed) do
      if text:find("^sniper:") then line = text end
    end
    assert.is_truthy(line)
    assert.equal("sniper: facts=3 queue=1 lost=0 rehits=0 lastPass=classes 12s/9 pages drillShare=4/6", line)
  end)
end)
