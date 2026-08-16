local helper = require("spec.spec_helper")

describe("Watch loop", function()
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

  -- Harness state, reset by load(): every test reads these instead of spying by hand.
  local now, sent, searched, started, decision

  local function widget()
    local w = {}
    function w:SetText() end
    function w:SetTextColor() end
    function w:SetTexture() end
    function w:SetLabel(label) self.label = label end
    function w:SetVariant(name) self.variant = name end
    function w:Enable() self.enabled = true end
    function w:Disable() self.enabled = false end
    return w
  end

  local function fakeRow()
    local row = {
      buy = widget(), tierChip = widget(), icon = widget(), nameText = widget(),
      discountText = widget(), unitText = widget(), priceText = widget(),
      profitText = widget(), trendText = widget(), highlight = widget(), shown = false,
    }
    function row:Show() self.shown = true end
    function row:Hide() self.shown = false end
    function row:IsShown() return self.shown end
    function row:SetAlpha(a) self.alpha = a end
    return row
  end

  local function deal(itemID, unitPrice)
    return { itemID = itemID, unitPrice = unitPrice, qty = 1, avail = 10, profit = 1000,
      discount = 0.5, tier = "GOOD", stale = true, action = "Check", status = "WATCH",
      reason = "live_verification_required" }
  end

  local function load()
    now, sent, searched, started = 100, {}, {}, {}
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
      Theme = { ROW_H = 20, pad = { m = 8, s = 4, xs = 2 },
        tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 } } },
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
      db = { settings = { sniper = { sound = false, showRefused = false, watchPins = {} } } },
    }
    helper.loadModule("Core/WatchSet.lua", GC)          -- the REAL selector, not a stub
    helper.loadModule("UI/SniperFrame.lua", GC)

    -- A fake poll scanner: records the target list it was started on, and every granted slot.
    GC.Scanner = { New = function() end }
    local watch = { hungry = true, scanned = 0 }
    function watch:Wants() return self.hungry end
    function watch:Start(list)
      local copy = {}
      for i = 1, #list do copy[i] = list[i] end
      started[#started + 1] = copy
    end
    function watch:Stop() self.stopped = (self.stopped or 0) + 1 end
    function watch:OnSystemReady() sent[#sent + 1] = "watch" end
    GC.Sniper.scanner = watch

    local show = GC.Sniper.OnAuctionHouseShow
    local refreshRows = upvalue(show, "refreshRows")
    set(refreshRows, "content", { SetHeight = function() end })
    set(refreshRows, "createRow", function() return fakeRow() end)
    set(GC.Sniper.OnItemKeyInfo, "driver", {
      isReady = function() return true end,
      mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan,
      -- The real callback, not a stub: this is the implementation under test for the
      -- "stamps a watched item's verdict" case below, and it reaches back into the shared
      -- `driver` upvalue (via evaluateLiveCommodityDeal) for the commodityBook/commodityResult
      -- stubs set on THIS same table, same as every other closure in this chunk does.
      onObservation = upvalue(GC.Sniper.OnItemKeyInfo, "driver").onObservation,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function(itemID) searched[#searched + 1] = itemID end,
      commodityBook = function() return { { unitPrice = 100, quantity = 50 } } end,
      commodityResult = function() return { unitPrice = 100, qty = 50, avail = 50 } end,
      itemResult = function() return nil end,
      getValue = function() return { mv = 200, soldPerDay = 50 } end,
      onStatus = function() end,
    })
    set(show, "ahOpen", true)
    set(show, "mode", "fullscan")
    set(show, "frame", { IsShown = function() return true end, Hide = function() end,
      status = { SetText = function() end } })
    return GC, started
  end

  -- renderList is a chunk-level local; reach it the way every other test in this repo does.
  local function renderList(GC)
    return upvalue(upvalue(GC.Sniper.OnAuctionHouseShow, "refreshRows"), "renderList")()
  end

  local function tickAt(GC, seconds)
    now = seconds
    upvalue(GC.Sniper.OnAuctionHouseShow, "tickAutoVerify")()
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
  end)

  it("starts the loop once an item has churned enough", function()
    local GC, started = load()
    GC.Sniper._churn = {}
    GC.WatchSet.Observe(GC.Sniper._churn, { { itemID = 7, unitPrice = 100 } }, 1)
    GC.WatchSet.Observe(GC.Sniper._churn, { { itemID = 7, unitPrice = 90 } }, 2)
    GC.Sniper._RefreshWatchSet()
    assert.same({}, started)                       -- two prices is not churn

    GC.WatchSet.Observe(GC.Sniper._churn, { { itemID = 7, unitPrice = 80 } }, 3)
    GC.Sniper._RefreshWatchSet()
    assert.same({ { 7 } }, started)
  end)

  it("does not restart the loop when the set is unchanged", function()
    local GC, started = load()
    GC.Sniper._churn = {}
    for price = 1, 3 do GC.WatchSet.Observe(GC.Sniper._churn, { { itemID = 7, unitPrice = price } }, price) end
    GC.Sniper._RefreshWatchSet()
    GC.Sniper._RefreshWatchSet()
    assert.equal(1, #started)                      -- restarting resets alert state; do it only on a real change
  end)

  it("watches a pin with no churn at all", function()
    local GC, started = load()
    GC.db.settings.sniper.watchPins = { 42 }
    GC.Sniper._churn = {}
    GC.Sniper._RefreshWatchSet()
    assert.same({ { 42 } }, started)
  end)

  it("forgets what it learned when the auction house closes, but not the pins", function()
    local GC = load()
    GC.db.settings.sniper.watchPins = { 42 }
    GC.Sniper._churn = {}
    for price = 1, 3 do GC.WatchSet.Observe(GC.Sniper._churn, { { itemID = 7, unitPrice = price } }, price) end
    GC.Sniper.OnAuctionHouseClosed()
    assert.same({}, GC.Sniper._churn)
    assert.same({ 42 }, GC.db.settings.sniper.watchPins)
  end)

  it("does not restart the loop when a re-rank leaves membership unchanged", function()
    local GC, started = load()
    GC.Sniper._churn = {}
    -- Two items both clear MIN_CHURN and tie on count (3); Select's tiebreak after count is
    -- `at` (recency) descending, so seeding item 20 with the later seq range ranks it first.
    for price = 1, 3 do GC.WatchSet.Observe(GC.Sniper._churn, { { itemID = 10, unitPrice = price } }, price) end
    for price = 4, 6 do GC.WatchSet.Observe(GC.Sniper._churn, { { itemID = 20, unitPrice = price } }, price) end
    GC.Sniper._RefreshWatchSet()
    assert.same({ { 20, 10 } }, started)             -- sanity: confirms the order this test depends on

    -- A fresh, distinct price for item 10 (currently ranked second) bumps its count past
    -- item 20's, so Select now ranks 10 first -- same two members, different order.
    GC.WatchSet.Observe(GC.Sniper._churn, { { itemID = 10, unitPrice = 99 } }, 7)
    GC.Sniper._RefreshWatchSet()
    assert.equal(1, #started)                        -- membership unchanged; reordering must not restart
  end)

  it("stops the loop when the set goes empty, rather than starting on an empty list", function()
    local GC, started = load()
    local scanner = GC.Sniper.scanner
    GC.db.settings.sniper.watchPins = { 42 }
    GC.Sniper._churn = {}
    GC.Sniper._RefreshWatchSet()
    assert.same({ { 42 } }, started)                 -- loop started on the pin

    GC.db.settings.sniper.watchPins = {}
    GC.Sniper._RefreshWatchSet()
    assert.equal(1, #started)                        -- Start was not called again with an empty list
    assert.equal(1, scanner.stopped)                  -- the scanner was told to stop instead
  end)

  it("stamps a watched item's verdict from the poll, with no extra query", function()
    local GC = load()
    GC.db.settings.sniper.watchPins = { 42 }
    GC.Sniper._RefreshWatchSet()
    local observe = upvalue(GC.Sniper.OnItemKeyInfo, "driver").onObservation
    -- A live commodity book is already fetched by the poll; the decision engine says SAFE.
    decision = { status = "SAFE", buyable = true, quantity = 5, reasons = {} }
    observe(42, { itemID = 42, unitPrice = 100, qty = 5, isCommodity = true })
    local verdicts = upvalue(upvalue(GC.Sniper.OnAuctionHouseShow, "tickAutoVerify"), "verdicts")
    assert.is_true(verdicts[42].buyable)
    assert.same({}, searched)          -- not one additional SendSearchQuery
  end)

  it("does not spend verification budget on an item the loop is already watching", function()
    local GC = load()
    GC.db.settings.sniper.watchPins = { 42 }
    GC.Sniper._RefreshWatchSet()
    set(GC.Sniper.OnAuctionHouseShow, "scanDeals", { deal(42, 100), deal(43, 200) })
    tickAt(GC, 101)
    assert.same({ 43 }, searched)      -- 42 is watched; the walk skips straight past it
  end)
end)
