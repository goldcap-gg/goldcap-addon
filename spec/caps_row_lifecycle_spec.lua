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

  local function getUpvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end
  local function setUpvalue(fn, wanted, value)
    for i = 1, math.huge do
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

  -- Caps fixes 2a: GC.Data.GetItemValue answers a realm item the import lists only in `T:`
  -- with its region reference and NO mv (Core/Data.lua's target-only branch). buildCapDeal
  -- multiplied that nil inside the drill-result handler -- for exactly the gear a cap exists
  -- for -- so the drill threw instead of building the row.
  it("builds a cap row for gear the import knows only by its region reference", function()
    local GC = loadSniper()
    adoptCap(GC, 42, 1000000, 0)
    values[42] = { ts = 1, source = "import", kind = "realm_item", ref = 5000000, refIlvl = 610 }
    local evaluateLiveItemDeal = getUpvalue(GC.Sniper.OnItemSearchResults, "evaluateLiveItemDeal")
    setUpvalue(evaluateLiveItemDeal, "driver", {
      itemResult = function() return {} end,
      itemLots = function() return { { auctionID = 9, buyout = 800000, itemLevel = 615, quantity = 1 } } end,
    })

    local live = evaluateLiveItemDeal(42)

    assert.is_true(live.decision.cap)
    local deal = GC.Sniper._realmDeals[42]
    assert.equal(1000000, deal.cap)
    assert.is_nil(deal.mv)
    assert.equal(-800000, deal.estProfit) -- "no reference", exactly as buildCapDeal promises
  end)

  -- Caps fixes 3e: finding a lot is not telling the player about it. The drill used to commit
  -- the lot's announcement (GC.Caps.Announce) the moment it built the row -- here with no
  -- window at all, so nothing could ring -- and the lot then never rang for the rest of the
  -- visit, whatever the player did next.
  it("does not spend a lot's announcement on a hit nobody could see", function()
    local GC = loadSniper()
    adoptCap(GC, 42, 1000000, 0)
    local evaluateLiveItemDeal = getUpvalue(GC.Sniper.OnItemSearchResults, "evaluateLiveItemDeal")
    setUpvalue(evaluateLiveItemDeal, "driver", {
      itemResult = function() return {} end,
      itemLots = function() return { { auctionID = 9, buyout = 800000, itemLevel = 615, quantity = 1 } } end,
    })

    evaluateLiveItemDeal(42)

    assert.is_table(GC.Sniper._realmDeals[42])
    assert.is_true(GC.Caps.Announce({ itemID = 42, isCommodity = false, auctionID = 9 }))
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

  -- Caps fixes 3c: an item with a region reference qualifies as an ORDINARY deal off the same
  -- batch -- the aggregate floor under the reference -- and that deal used to be written over
  -- the cap row: the "group · your price" label, the CAP bucket and the lot the drill resolved
  -- all went, replaced by an unverified aggregate at the floor.
  it("keeps the cap row when the same batch also qualifies the item as an ordinary deal", function()
    local GC = loadSniper()
    adoptCap(GC, 42, 100, 0)
    values[42] = { ts = 1, source = "import", kind = "realm_item", ref = 150 }
    local held = capDeal(42, 80, 100)
    GC.Sniper._realmDeals[42] = held
    GC.Sniper._keysBatch = { 42 }

    GC.Sniper._keyPoll:Fold({ browseRow(42, 90, 3) }) -- under the cap, and 40% under the reference

    assert.equal(held, GC.Sniper._realmDeals[42])
  end)

  it("hands the item to the ordinary deal once the cap no longer holds", function()
    local GC = loadSniper()
    adoptCap(GC, 42, 100, 0)
    values[42] = { ts = 1, source = "import", kind = "realm_item", ref = 150 }
    GC.Sniper._realmDeals[42] = capDeal(42, 80, 100)
    GC.Sniper._keysBatch = { 42 }

    GC.Sniper._keyPoll:Fold({ browseRow(42, 120, 3) }) -- above the cap, still 20% under the reference

    local deal = GC.Sniper._realmDeals[42]
    assert.is_table(deal)
    assert.is_nil(deal.cap)
    assert.equal(120, deal.unitPrice)
  end)

  -- Caps fixes 3d: the keep-alive judged the item by its aggregate floor -- the cheapest variant
  -- of ANY level. A cap with a level floor ("610 or better at 100") was then kept alive by a 590
  -- selling at 50 after the 615 it had found was gone. It reads the poll's own book entry now,
  -- at the cap's own level.
  local function variantRow(itemID, itemLevel, minPrice)
    return { itemKey = { itemID = itemID, itemLevel = itemLevel }, minPrice = minPrice, totalQuantity = 1 }
  end

  it("lets an item-level cap row go once only a variant below its level is under the cap", function()
    local GC = loadSniper()
    adoptCap(GC, 42, 100, 610)
    GC.Sniper._realmDeals[42] = capDeal(42, 80, 100)
    GC.Sniper._keysBatch = { 42 }

    GC.Sniper._keyPoll:Fold({ variantRow(42, 590, 50), variantRow(42, 615, 150) })

    assert.is_nil(GC.Sniper._realmDeals[42])
  end)

  it("keeps an item-level cap row while a variant at its level is still under the cap", function()
    local GC = loadSniper()
    adoptCap(GC, 42, 100, 610)
    local held = capDeal(42, 80, 100)
    GC.Sniper._realmDeals[42] = held
    GC.Sniper._keysBatch = { 42 }

    GC.Sniper._keyPoll:Fold({ variantRow(42, 590, 50), variantRow(42, 615, 90) })

    assert.equal(held, GC.Sniper._realmDeals[42])
  end)

  -- The other half of 3d: the keep-alive may not depend on which rows the ordinary path turned
  -- into realm rows. A capped item the import knows no region reference for is still answered
  -- for by the batch, and its own floor keeps its row.
  it("keeps the cap row of an item the import has no region reference for", function()
    local GC = loadSniper()
    adoptCap(GC, 42, 100, 0)
    values[42] = { ts = 1, source = "import", kind = "realm_item", mv = 500 } -- a median, no ref
    local held = capDeal(42, 80, 100)
    GC.Sniper._realmDeals[42] = held
    GC.Sniper._keysBatch = { 42 }

    GC.Sniper._keyPoll:Fold({ browseRow(42, 90, 3) })

    assert.equal(held, GC.Sniper._realmDeals[42])
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
        ReasonText = function(t) return "reason:" .. tostring(t) end,
        -- The player's own per-buy limits a cap decision is made within; roomy, so they bind
        -- nothing in this block -- what a cap may spend is spec/caps_purchase_spec.lua's subject.
        BuyLimits = function() return { maxQuantity = 5000, budget = 1000000000000 } end },
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
    -- The real store operations: the board a cap row lands on is this suite's subject, and a
    -- stubbed ApplyLiveObservation that returns its list untouched is how an assertion on the
    -- wrong store (`deals` in full-scan mode) once passed.
    helper.loadModule("Core/FullScan.lua", GC)
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
      -- The window this board lives in is on screen (see `frame` below), so a shown row is a
      -- visible one -- the question the cap ring asks before it spends anything (caps fixes 3e).
      function row:IsVisible() return self.shown end
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

  -- Caps fixes 3b: the board the player sees. A cap row used to be written into the watchlist
  -- map (`deals`) whenever the watch loop had not yet taken over the full-scan list
  -- (_liveTracksScanDeals false -- the start of every visit, until three distinct prices have
  -- churned), while the Commodities board in full-scan mode reads scanDeals alone. The hit was
  -- announced, rang for nothing on screen, and the ratchet then kept it off the board for the
  -- rest of the visit. These assertions used to read `deals[42]` in full-scan mode -- pinning
  -- exactly that. They now read what the board renders.
  local function board(GC)
    local refreshRows = upvalue(GC.Sniper.OnAuctionHouseShow, "refreshRows")
    return upvalue(upvalue(refreshRows, "renderList"), "sortedDeals")()
  end
  local function onBoard(GC, itemID)
    for _, deal in ipairs(board(GC)) do
      if deal.itemID == itemID then return deal end
    end
    return nil
  end
  -- And the pooled row the render stamped it on, shown.
  local function renderedRow(GC, itemID)
    local rowsList = upvalue(upvalue(GC.Sniper.OnAuctionHouseShow, "refreshRows"), "rows")
    for _, row in ipairs(rowsList) do
      if row.deal and row.deal.itemID == itemID and row:IsShown() then return row end
    end
    return nil
  end

  it("keeps/creates a cap row from an observation with no plain (market) deal at all", function()
    local GC = load()
    adoptCap(GC, 42, 100, 0)
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    driverTbl.commodityBook = function() return { { unitPrice = 80, quantity = 3 } } end -- under cap

    -- The watch loop found nothing against the market (nil deal, exactly what a pure-cap item
    -- with no GC.Data.GetItemValue entry produces every cycle) -- but the book is under cap.
    driverTbl.onObservation(42, nil)

    local capDeal = onBoard(GC, 42)
    assert.is_table(capDeal)
    assert.equal(100, capDeal.cap)
    assert.equal(80, capDeal.unitPrice)
    assert.equal(capDeal, renderedRow(GC, 42).deal)
  end)

  it("removes a cap row once the book's floor is back above the cap", function()
    local GC = load()
    adoptCap(GC, 42, 100, 0)
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")

    driverTbl.commodityBook = function() return { { unitPrice = 80, quantity = 3 } } end
    driverTbl.onObservation(42, nil)
    assert.is_table(onBoard(GC, 42))

    driverTbl.commodityBook = function() return { { unitPrice = 150, quantity = 3 } } end -- over cap now
    driverTbl.onObservation(42, nil)
    assert.is_nil(onBoard(GC, 42))
  end)

  -- The first hit of a visit comes from a drill, not the watch loop: the book pass's hit is
  -- queued and its answer lands in OnCommoditySearchResults, long before the watch set exists.
  it("puts a drilled cap hit on the Commodities board before the watch loop has started", function()
    local GC = load()
    adoptCap(GC, 42, 100, 0)
    assert.is_false(GC.Sniper._liveTracksScanDeals)
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    local evaluateLiveCommodityDeal = upvalue(driverTbl.onObservation, "evaluateLiveCommodityDeal")

    evaluateLiveCommodityDeal(42, { { unitPrice = 80, quantity = 3 } })

    assert.equal(100, onBoard(GC, 42).cap)
    assert.is_table(renderedRow(GC, 42))
  end)

  it("puts it on the watchlist board when that is the board on screen", function()
    local GC = load()
    adoptCap(GC, 42, 100, 0)
    set(GC.Sniper.OnAuctionHouseShow, "mode", "watchlist")
    GC.Sniper._liveTracksScanDeals = true -- a pinned item's watch loop, before any scan
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")

    driverTbl.commodityBook = function() return { { unitPrice = 80, quantity = 3 } } end
    driverTbl.onObservation(42, nil)
    assert.equal(100, onBoard(GC, 42).cap)

    driverTbl.commodityBook = function() return { { unitPrice = 150, quantity = 3 } } end
    driverTbl.onObservation(42, nil)
    assert.is_nil(onBoard(GC, 42))
  end)

  -- Final review I1: the background drill is handed { itemID, unitPrice = hit.floor } -- the
  -- BROWSE floor -- so the verdict it recorded was filed under a price no row on the board was
  -- showing. verdictFor matches item AND asking price, so it answered nil for the very row the
  -- cap decision had just built: no CAP bucket, no label, no rank, until the player ran a
  -- manual Check on it. The verdict is now stamped off the deal the cap decision built, at the
  -- price that row is actually asking.
  it("files the verdict under the cap row's own price, so the board can label it", function()
    local GC = load()
    adoptCap(GC, 42, 100, 0)
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    -- The drill was queued at the browse floor (90) and the cap decision buys at the book's
    -- own cheapest qualifying level (80) -- the two prices that used to disagree.
    driverTbl.commodityBook = function() return { { unitPrice = 80, quantity = 3 } } end

    driverTbl.onObservation(42, nil)

    local capDeal = onBoard(GC, 42)
    assert.is_table(capDeal)
    assert.equal(80, capDeal.unitPrice)

    local show = GC.Sniper.OnAuctionHouseShow
    local verdictFor = upvalue(upvalue(upvalue(show, "refreshRows"), "renderList"), "verdictFor")
    local verdict = verdictFor(capDeal)
    assert.is_table(verdict)
    assert.is_true(verdict.cap)
    assert.equal(80, verdict.unitPrice)
    -- And nothing is filed at the browse floor the drill was queued at.
    assert.is_nil(verdictFor({ itemID = 42, unitPrice = 90 }))
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

-- Caps fixes 3a: a capped commodity's "your price" row lives on the commodity board's own
-- store (scanDeals), and every completed book pass used to replace that store wholesale with
-- what FullScan.Evaluate built from the pass's rows -- market deals only. A capped commodity
-- with no market deal of its own simply vanished at the end of the next pass, and the book-pass
-- ratchet (GC.Caps.BookHits) never re-drilled it while its floor stood still. The row now
-- stands for as long as the pass says the cap still holds.
describe("Caps row lifecycle -- commodity board across a book pass", function()
  local values, browseResults

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

  local function browseRow(itemID, minPrice, totalQuantity)
    return { itemKey = { itemID = itemID }, minPrice = minPrice, totalQuantity = totalQuantity or 3 }
  end

  local function loadSniper(capCopper)
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
    browseResults = {}
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return true end,
      GetBrowseResults = function() return browseResults end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      SearchForItemKeys = function() end,
    }

    values = {}
    local GC = { db = { commodityByItem = { [42] = true }, settings = { sniper = { sound = true,
      showRefused = false, board = "commodities",
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
    helper.loadModule("Core/BoardRows.lua", GC)
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
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, groups = {},
      caps = { { i = 42, c = capCopper or 100, l = 0 } } }
    GC.Caps.Adopt()
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.C_AuctionHouse, _G.Enum, _G.GoldCap_AppRuns = nil, nil, nil
  end)

  -- The commodity board the player is looking at: what sortedDeals hands the renderer.
  local function sortedDeals(GC)
    local refreshRows = upvalue(GC.Sniper.OnAuctionHouseShow, "refreshRows")
    return upvalue(upvalue(refreshRows, "renderList"), "sortedDeals")
  end
  local function onBoard(GC, itemID)
    for _, deal in ipairs(sortedDeals(GC)()) do
      if deal.itemID == itemID then return deal end
    end
    return nil
  end

  -- A cap row as the drill builds it, on the full-scan board.
  local function seedCapRow(GC, unitPrice, capCopper)
    unitPrice = unitPrice or 80
    local capRow = { itemID = 42, isCommodity = true, unitPrice = unitPrice, qty = 3,
      capTotal = unitPrice * 3, mv = nil, discount = 0, profit = -unitPrice,
      estProfit = -unitPrice, tier = "WATCH", cap = capCopper or 100, stale = true }
    set(sortedDeals(GC), "mode", "fullscan")
    set(sortedDeals(GC), "scanDeals", { capRow })
    return capRow
  end

  -- One book pass of `kind`, from arming to the completion reconcile, answering `rows`.
  local function runPass(GC, kind, rows)
    browseResults = rows
    GC.Sniper._bookPass:Start(kind)
    GC.Sniper._bookPass:OnThrottleReady()
    GC.Sniper.OnBrowseResults()
    assert.is_false(GC.Sniper._bookPass:IsPaging())
  end

  it("keeps the row through a pass that shows the item still at or under the cap", function()
    local GC = loadSniper()
    local capRow = seedCapRow(GC)

    runPass(GC, "wide", { browseRow(42, 90) })

    assert.equal(capRow, onBoard(GC, 42))
  end)

  it("keeps the row through a classes pass that never looked at the item", function()
    local GC = loadSniper()
    local capRow = seedCapRow(GC)

    runPass(GC, "classes", { browseRow(7, 500) })

    assert.equal(capRow, onBoard(GC, 42))
  end)

  it("lets the row go once the pass prices the item above the cap", function()
    local GC = loadSniper()
    seedCapRow(GC)

    runPass(GC, "wide", { browseRow(42, 150) })

    assert.is_nil(onBoard(GC, 42))
  end)

  it("lets the row go once a pass that looked for the item no longer finds it", function()
    local GC = loadSniper()
    seedCapRow(GC)

    runPass(GC, "wide", { browseRow(7, 500) })

    assert.is_nil(onBoard(GC, 42))
  end)

  -- The same item can be a market deal as well: its own browse row, under the region value,
  -- merged in page by page and rebuilt at the end. Neither may replace the row the player's
  -- own price built while that price still holds.
  local MARKET = { kind = "commodity", source = "import", mv = 250000, stressUnit = 200000,
    sold = 12, sellThroughBps = 9000, liquidityConfidence = 90, listings = 20,
    currentQty = 400, trend = 0 }

  it("keeps the row over the pass's own market row for the item while the cap holds", function()
    local GC = loadSniper(200000)
    values[42] = MARKET
    local capRow = seedCapRow(GC, 140000, 200000)

    runPass(GC, "wide", { browseRow(42, 150000, 50) })

    assert.equal(capRow, onBoard(GC, 42))
  end)

  it("(the pass above does build a market row for the item of its own)", function()
    local GC = loadSniper(200000)
    values[42] = MARKET
    set(sortedDeals(GC), "mode", "fullscan")

    runPass(GC, "wide", { browseRow(42, 150000, 50) })

    local deal = onBoard(GC, 42)
    assert.is_table(deal)
    assert.is_nil(deal.cap)
    assert.equal(150000, deal.unitPrice)
  end)
end)
