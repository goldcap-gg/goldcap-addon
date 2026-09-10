local helper = require("spec.spec_helper")

-- This protects the UI boundary around the pure SniperDecision engine. The static checks make
-- the protected WoW calls auditable; the fixture below also runs the real price-update handler
-- with a failed 4% requote, so the safety branch is not merely a source-text convention.
describe("Sniper purchase wiring", function()
  local function source()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  local function section(text, first, last)
    local from = assert(text:find(first, 1, true), first)
    local to = assert(text:find(last, from + #first, true), last)
    return text:sub(from, to - 1)
  end

  it("keeps purchase calls in the hardware-click handler and starts exact decision quantity", function()
    local text = source()
    local click = section(text, "local function onDialogPrimaryClick()", "-- ---------------------------------------------------------------------------\n-- Sniper v3 dialog layout constants")

    assert.is_truthy(click:find("C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, decision.quantity)", 1, true))
    assert.is_truthy(click:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_truthy(click:find("C_AuctionHouse.PlaceBid", 1, true))
    local nonCommodityGate = assert(click:find("if not deal.isCommodity", 1, true))
    local placeBid = assert(click:find("C_AuctionHouse.PlaceBid", 1, true))
    assert.is_true(nonCommodityGate < placeBid)
    assert.is_truthy(click:find("quoteSnapshot", 1, true))
    assert.is_truthy(click:find("quoteSnapshot.decision.status ~= \"SAFE\"", 1, true))
    assert.is_truthy(click:find("commodityDraining", 1, true))

    local before = text:sub(1, assert(text:find("local function onDialogPrimaryClick()", 1, true)) - 1)
    local after = text:sub(assert(text:find("-- Sniper v3 dialog layout constants", 1, true)))
    assert.is_nil(before:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_nil(before:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_nil(before:find("C_AuctionHouse.PlaceBid", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.PlaceBid", 1, true))
  end)

  it("keeps a shadowed SAFE decision on the Check path", function()
    local text = source()
    local arm = section(text, "local function armReady", "local function armCheck")
    local click = section(text, "local function onDialogPrimaryClick()", "-- ---------------------------------------------------------------------------\n-- Sniper v3 dialog layout constants")

    -- A shadow result is public WATCH/buyable=false; only that public contract can arm or
    -- reach a protected WoW call. `computedStatus` is display evidence, never an arm key.
    assert.is_truthy(arm:find("not decision.buyable or decision.status ~= \"SAFE\"", 1, true))
    assert.is_nil(arm:find("computedStatus", 1, true))
    assert.is_truthy(click:find("decision.status ~= \"SAFE\" or not decision.buyable", 1, true))
    assert.is_nil(click:find("computedStatus", 1, true))
  end)

  it("renders complete non-actionable shadow diagnostics", function()
    local text = source()
    local diagnostic = section(text, "local function stampDialogFromDecision", "local function copyReasons")

    assert.is_truthy(diagnostic:find("dialog.diagnosticText:SetText", 1, true))
    assert.is_truthy(diagnostic:find("computed=%s public=%s buyable=%s reasons=%s", 1, true))
    assert.is_truthy(diagnostic:find("table.concat(decision.reasons or {}, \", \")", 1, true))

    -- The item ID leads the diagnostic. The dialog's own header cannot carry it: setDialogHeader
    -- writes "item <id>" only until Item:ContinueOnItemLoad overwrites it with the localized
    -- name. A name is not an identity -- tiered reagents share one name across several IDs
    -- (Argentleaf is both 236776 and 236777), so a shadow observation recorded from the name
    -- alone cannot be attributed to an item after the fact.
    assert.is_truthy(diagnostic:find("item=%d computed=%s public=%s buyable=%s reasons=%s", 1, true))
  end)

  it("sizes, banners, and shrinks a stateful full-reasons diagnostic", function()
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return {} end },
      -- The diagnostic line only measures/shows with debug on (fix round N) -- this spec is
      -- specifically about that auto-sizing behaviour, which stays byte-identical to before
      -- once it is on, so it turns debug on rather than asserting the (separately covered)
      -- default-off/no-measurement case.
      db = { settings = { sniper = { debug = true } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

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
    local priceUpdated = GC.Sniper.OnCommodityPriceUpdated
    local stamp = getUpvalue(priceUpdated, "stampDialogFromDecision")
    local showBanner = getUpvalue(priceUpdated, "showRequoteBanner")
    local hideBanner = getUpvalue(priceUpdated, "hideRequoteBanner")
    local diagnosticHeight, dialogHeight, statusAnchors = nil, nil, {}
    local function textSink()
      return { SetText = function() end, SetTextColor = function() end, Show = function() end, Hide = function() end }
    end
    local diagnosticText = { text = "" }
    function diagnosticText:SetText(text) self.text = text end
    function diagnosticText:GetStringHeight()
      return #self.text > 200 and 260 or 24 -- simulates wrapped 1.3x-font reason evidence
    end
    function diagnosticText:SetHeight(height) diagnosticHeight = height end
    function diagnosticText:ClearAllPoints() end
    function diagnosticText:SetPoint() end
    function diagnosticText:Show() end
    function diagnosticText:Hide() end
    local banner = {
      shown = false,
      head = textSink(),
      detail = textSink(),
    }
    function banner:IsShown() return self.shown end
    function banner:Show() self.shown = true end
    function banner:Hide() self.shown = false end
    local fakeDialog = {
      fixedHeight = 400, diagnosticGaps = 4, diagnosticMinimumHeight = 108,
      detailsOpen = false, evidenceTopOpen = -200, evidenceTopClosed = -100,
      SetHeight = function(_, height) dialogHeight = height end,
      banner = banner,
      diagnosticText = diagnosticText,
      status = {
        ClearAllPoints = function() end,
        SetPoint = function(_, ...) statusAnchors[#statusAnchors + 1] = { ... } end,
      },
      decisionStatusText = textSink(), quantityText = textSink(), unitPriceText = textSink(),
      totalCostText = textSink(), exitUnitText = textSink(), profitText = textSink(),
      mvText = textSink(), soldText = textSink(), sellThroughText = textSink(),
      sourceAgeText = textSink(), reasonText = textSink(),
      verdictHead = textSink(), verdictSub = textSink(),
      mvNote = { Hide = function() end, ClearAllPoints = function() end, SetPoint = function() end },
    }
    setUpvalue(stamp, "dialog", fakeDialog)
    setUpvalue(stamp, "marketForDecision", function() return {} end)

    local maximalReasons = {}
    for i = 1, 32 do maximalReasons[i] = ("maximum_length_reason_%02d"):format(i) end
    stamp({ itemID = 42 }, {
      computedStatus = "SAFE", status = "WATCH", buyable = false, quantity = 1,
      reasons = maximalReasons,
    })

    assert.equal(260, diagnosticHeight)
    assert.equal(664, dialogHeight) -- fixed + diagnostic + grid→diagnostic/status gaps
    assert.same({ "TOPLEFT", fakeDialog.diagnosticText, "BOTTOMLEFT", 0, -2 }, statusAnchors[1])

    showBanner("PRICE ROSE", "still safe")
    assert.equal(710, dialogHeight) -- banner height stays additive to the measured base

    stamp({ itemID = 42 }, {
      computedStatus = "WATCH", status = "WATCH", buyable = false, quantity = 1,
      reasons = { "brief" },
    })
    hideBanner()
    assert.equal(108, diagnosticHeight)
    assert.equal(512, dialogHeight) -- reused dialog resets to its short diagnostic base

    -- Behavioural counterpart to the source-text check above: the ID actually reaches the
    -- rendered evidence line, for the exact deal the dialog was stamped from.
    assert.equal("item=42 computed=WATCH public=WATCH buyable=no reasons=brief", diagnosticText.text)
  end)

  it("requires a newly evaluated safe quote, cancels a broken requote, and records one purchase fact", function()
    local text = source()
    local quote = section(text, "function GC.Sniper.OnCommodityPriceUpdated", "function GC.Sniper.OnCommodityPriceUnavailable")
    local accounting = section(text, "local function recordPurchaseFacts", "local function reportDetachedCommodity")

    assert.is_truthy(quote:find("evaluateLive", 1, true))
    assert.is_truthy(quote:find("C_AuctionHouse.CancelCommoditiesPurchase()", 1, true))
    assert.is_truthy(quote:find("requote_broke_safety", 1, true))
    assert.is_truthy(quote:find("drainCommodityPurchase(row)", 1, true))
    assert.is_truthy(accounting:find("purchase.total", 1, true))
    assert.is_truthy(accounting:find("GC.Data.RecordFlip(deal, purchase", 1, true))
    assert.is_truthy(accounting:find("GC.Ledger.RecordSniperBuy(deal, purchase", 1, true))
    assert.is_truthy(accounting:find("GC.Acquisitions.RecordGoldCap(deal, purchase", 1, true))
  end)

  it("cancels a sub-five-percent failed requote before any confirm can run", function()
    -- The integration fixture intentionally supplies a final server total that is only 4%
    -- higher, but whose stress math fails. This must cancel on economics, not rely on the old
    -- 5% visual-warning threshold; no event is permitted to confirm a protected purchase.
    local cancelCalls, confirmCalls = 0, 0
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() confirmCalls = confirmCalls + 1 end,
    }
    _G.C_Timer = { After = function() end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local row = {
      purchaseStage = "buying", purchaseToken = 7,
      purchaseDeal = { itemID = 42, isCommodity = true },
      decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1 },
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)

    -- The fresh book still begins at 100g; a 104g server quote makes the 100g stress-profit
    -- boundary fail. The real handler must cancel before any button can be a Confirm path.
    _G.C_AuctionHouse.GetNumCommoditySearchResults = function() return 2 end
    _G.C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index)
      if index == 1 then return { unitPrice = 1000000, quantity = 1 } end
      return { unitPrice = 2105265, quantity = 1 }
    end
    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000)

    assert.equal(1, cancelCalls)
    assert.equal(0, confirmCalls)
    assert.equal("check", row.purchaseStage)
    assert.is_nil(row.decisionSnapshot)
    assert.is_nil(row.quoteSnapshot)

    -- The cancellation remains owned until a terminal event. A second late price must be
    -- drained too; otherwise its terminal event could be misattributed to a later Start.
    local draining = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining")
    assert.is_table(draining)
    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000)
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == draining)
    GC.Sniper.OnCommodityPurchaseFailed()
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
  end)

  -- CancelCommoditiesPurchase produces none of the three terminal events that consume a
  -- tombstone, so before this an unconfirmed cancellation blocked every later commodity buy
  -- with "waiting for previous commodity purchase to settle" until the player happened to close
  -- the Auction House. An unconfirmed attempt never called ConfirmCommoditiesPurchase, so no
  -- gold can have moved and no late event can credit a purchase to the wrong row -- retiring it
  -- on a timer is safe. A CONFIRMED tombstone still waits forever: its late success must land.
  it("retires an unconfirmed drain tombstone on its own timer, but never a confirmed one", function()
    local cancelCalls, timers = 0, {}
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() end,
      GetNumCommoditySearchResults = function() return 2 end,
      GetCommoditySearchResultInfo = function(_, index)
        if index == 1 then return { unitPrice = 1000000, quantity = 1 } end
        return { unitPrice = 2105265, quantity = 1 }
      end,
    }
    _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local row = {
      purchaseStage = "buying", purchaseToken = 7,
      purchaseDeal = { itemID = 42, isCommodity = true },
      decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1 },
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)

    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000) -- breaks safety -> cancel + drain
    assert.equal(1, cancelCalls)
    local draining = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining")
    assert.is_table(draining)
    assert.is_falsy(draining.confirmed)

    -- Other timers (arm timeouts and the like) are scheduled along the same path; each is run
    -- under pcall so an unrelated one cannot decide this example's outcome either way.
    local function runTimers()
      for _, timer in ipairs(timers) do pcall(timer.fn) end
    end
    runTimers()
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))

    -- The retirement must be bound to the exact tombstone it was scheduled for: replaying those
    -- same callbacks against a later CONFIRMED tombstone must leave it completely alone.
    local confirmedTombstone = { row = {}, itemID = 42, token = 11, confirmed = true }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", confirmedTombstone)
    runTimers()
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == confirmedTombstone)

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
  end)

  it("freezes a commodity success without a matching final quote instead of estimating a purchase", function()
    local flipCalls, ledgerCalls = 0, 0
    _G.C_AuctionHouse = {}
    _G.GetTime = function() return 0 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return {} end, RecordFlip = function() flipCalls = flipCalls + 1 end },
      Ledger = { RecordSniperBuy = function() ledgerCalls = ledgerCalls + 1 end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    local deal = { itemID = 42, isCommodity = true }
    local row = { purchaseStage = "confirming", purchaseToken = 3, deal = deal, purchaseDeal = deal }
    setUpvalue(GC.Sniper.OnCommodityPurchaseSucceeded, "commodityPurchase", {
      row = row, itemID = 42, token = 3, confirmed = true, deal = row.purchaseDeal,
    })
    GC.Sniper.OnCommodityPurchaseSucceeded()

    assert.equal("frozen", row.purchaseStage)
    assert.equal(0, flipCalls)
    assert.equal(0, ledgerCalls)
    _G.C_AuctionHouse, _G.GetTime = nil, nil
  end)

  it("retains a commodity tombstone through late prices until its terminal event", function()
    local cancelCalls = 0
    _G.C_AuctionHouse = { CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local old = { row = { purchaseToken = 1 }, itemID = 42, token = 1 }
    local newerRow = { purchaseToken = 2, purchaseStage = "buying", purchaseDeal = { itemID = 42, isCommodity = true } }
    local newer = { row = newerRow, itemID = 42, token = 2 }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", old)
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", newer)

    GC.Sniper.OnCommodityPriceUpdated(1000000, 1000000) -- late price for the drained old attempt

    assert.equal(1, cancelCalls)
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == old)
    assert.equal("buying", newerRow.purchaseStage)

    GC.Sniper.OnCommodityPurchaseFailed() -- terminal failure belonging to the drained old attempt
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPurchaseFailed, "commodityDraining"))
    assert.equal("buying", newerRow.purchaseStage)
    _G.C_AuctionHouse = nil
  end)

  it("keeps a delayed price tombstone until a terminal event", function()
    _G.C_AuctionHouse = { CancelCommoditiesPurchase = function() end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", { row = {}, itemID = 42, token = 1 })
    GC.Sniper.OnCommodityPriceUpdated(1000000, 1000000)
    assert.is_table(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))
    _G.C_AuctionHouse = nil
  end)

  it("records the confirmed final quote exactly once after an AH-close tombstone", function()
    local flipPurchase, ledgerPurchase, confirmCalls, cancelDisabled = nil, nil, 0, false
    _G.time = function() return 100000 end
    _G.GetTime = function() return 0 end
    _G.C_AuctionHouse = { ConfirmCommoditiesPurchase = function() confirmCalls = confirmCalls + 1 end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = {
        GetItemValue = function() return {} end,
        RecordFlip = function(_, purchase) flipPurchase = purchase end,
      },
      Ledger = {
        Context = function() return {} end,
        RecordSniperBuy = function(_, purchase) ledgerPurchase = purchase; return { key = "snipe:42" } end,
      },
      Acquisitions = { RecordGoldCap = function(_, purchase, _, _, key)
        assert.equal("snipe:42", key)
        assert.is_true(purchase == ledgerPurchase)
      end },
      Sell = { Reset = function() end, SellableCount = function() return 0 end },
      Print = function() end,
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local row = {
      purchaseStage = "confirm", purchaseToken = 9,
      purchaseDeal = { itemID = 42, isCommodity = true },
      quoteSnapshot = {
        token = 9, itemID = 42, quantity = 3, total = 123456,
        decision = { version = 1, status = "SAFE", buyable = true, quantity = 3,
          reasons = { "safe" }, exitUnit = 60000, stressProfit = 42000 },
        market = { sourceAt = 99999 },
      },
    }
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end
    -- Follow the real row-click closure chain to the hardware-only Confirm handler and the
    -- exact OnHide abort helper; this is intentionally not a hand-written state transition.
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local confirm = getUpvalue(createDialog, "onDialogPrimaryClick")
    local abortOnHide = getUpvalue(createDialog, "abortRowPurchase")
    local fakeDialog = {
      row = row,
      primaryBtn = { Disable = function() end },
      cancelBtn = { Disable = function() cancelDisabled = true end },
      status = { SetText = function() end, SetTextColor = function() end },
      banner = { Hide = function() end },
      SetHeight = function() end,
      Hide = function() end,
      baseHeight = 1,
    }
    setUpvalue(confirm, "dialog", fakeDialog)
    setUpvalue(confirm, "commodityPurchase", { row = row, itemID = 42, token = 9 })

    confirm() -- exact protected click path
    assert.equal(1, confirmCalls)
    assert.is_true(cancelDisabled)
    assert.equal("confirming", row.purchaseStage)
    fakeDialog.row = nil -- exact OnHide ordering before it invokes abortRowPurchase
    abortOnHide(row, "purchase canceled")
    assert.equal("confirming", row.purchaseStage)

    GC.Sniper.OnAuctionHouseClosed()

    -- The pool can be reused in the next AH session before the old, untagged terminal event
    -- arrives. A late success must settle frozen facts only, never clear this new Check.
    local newDeal = { itemID = 99, isCommodity = true }
    local newAttempt = { row = row, itemID = 99, token = 22, deal = newDeal, sent = true }
    local awaiting = { [99] = newAttempt }
    local active = { [99] = true }
    row.deal = newDeal
    row.purchaseStage = "requerying"
    row.purchaseToken = 22
    row.purchaseDeal = nil
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", awaiting)
    local resolve = getUpvalue(GC.Sniper.OnCommodityPurchaseSucceeded, "resolvePurchase")
    setUpvalue(resolve, "activeItemID", active)

    GC.Sniper.OnCommodityPurchaseSucceeded()
    GC.Sniper.OnCommodityPurchaseSucceeded() -- duplicate terminal is a no-op

    assert.is_table(flipPurchase)
    assert.is_true(flipPurchase == ledgerPurchase)
    assert.equal(123456, flipPurchase.total)
    assert.equal(1, GC.Sniper.session.buys)
    assert.equal(123456, GC.Sniper.session.spent)
    assert.equal("requerying", row.purchaseStage)
    assert.is_true(row.deal == newDeal)
    assert.equal(22, row.purchaseToken)
    assert.is_true(awaiting[99] == newAttempt)
    assert.is_true(active[99])
    _G.time, _G.GetTime, _G.C_AuctionHouse = nil, nil, nil
  end)

  it("ignores a stale requery result after its row token advances", function()
    _G.C_AuctionHouse = {}
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    local row = { purchaseStage = "requerying", purchaseToken = 2, deal = { itemID = 42, isCommodity = true } }
    local old = { row = row, itemID = 42, token = 1, deal = row.deal }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", { [42] = old })
    GC.Sniper.OnCommoditySearchResults(42)

    assert.equal("requerying", row.purchaseStage)
    _G.C_AuctionHouse = nil
  end)

  it("settles detached confirmed unavailable and failure without freezing a repooled Check", function()
    local flipCalls, ledgerCalls = 0, 0
    _G.C_AuctionHouse = {}
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = {
        GetItemValue = function() return {} end,
        RecordFlip = function() flipCalls = flipCalls + 1 end,
      },
      Ledger = {
        Context = function() return {} end,
        RecordSniperBuy = function() ledgerCalls = ledgerCalls + 1 end,
      },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local newDeal = { itemID = 99, isCommodity = true }
    local row = { deal = newDeal, purchaseStage = "requerying", purchaseToken = 22 }
    local newAttempt = { row = row, itemID = 99, token = 22, deal = newDeal, sent = true }
    local awaiting = { [99] = newAttempt }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", awaiting)
    local oldDeal = { itemID = 42, isCommodity = true }
    local old = { row = row, itemID = 42, token = 9, confirmed = true, deal = oldDeal }
    setUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "commodityDraining", old)

    GC.Sniper.OnCommodityPriceUnavailable()

    assert.equal("requerying", row.purchaseStage)
    assert.is_true(row.deal == newDeal)
    assert.equal(22, row.purchaseToken)
    assert.is_true(awaiting[99] == newAttempt)
    assert.equal(0, flipCalls)
    assert.equal(0, ledgerCalls)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUnavailable, "commodityDraining"))
    assert.equal("purchase total unavailable — inspect mailbox", GC.Sniper.detachedCommodityStatus[42].note)

    setUpvalue(GC.Sniper.OnCommodityPurchaseFailed, "commodityDraining", old)
    GC.Sniper.OnCommodityPurchaseFailed()

    assert.equal("requerying", row.purchaseStage)
    assert.is_true(row.deal == newDeal)
    assert.equal(22, row.purchaseToken)
    assert.is_true(awaiting[99] == newAttempt)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPurchaseFailed, "commodityDraining"))
    assert.equal("confirmed commodity purchase failed after AH close", GC.Sniper.detachedCommodityStatus[42].note)
    _G.C_AuctionHouse = nil
  end)

  it("token-fences an old Check timeout from a newer Check attempt", function()
    local timers = {}
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
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

    -- Reach the same private Check function the row click ultimately uses, through real
    -- closures rather than duplicating its logic in the fixture.
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local abortRowPurchase = getUpvalue(createDialog, "abortRowPurchase")
    setUpvalue(startRequery, "driver", {
      isReady = function() return false end,
      getKeyInfo = function() return { isCommodity = true } end,
    })

    local deal = { itemID = 42, isCommodity = true }
    local row = { deal = deal }
    startRequery(row, deal)
    abortRowPurchase(row, nil) -- unsent Check is cancelled locally; no drain is needed
    startRequery(row, deal)

    assert.equal(2, row.purchaseToken)
    assert.equal(2, #timers)
    timers[1]() -- timer for token 1 must not alter the live token-2 Check
    assert.equal("requerying", row.purchaseStage)
    local awaiting = getUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery")
    assert.equal(2, awaiting[42].token)
    _G.C_Timer = nil
  end)

  it("drains an old search result before it can resolve a newer prewarm attempt", function()
    _G.C_AuctionHouse = {}
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local old = { itemID = 42, token = 1, sent = true }
    local warm = { itemID = 42, token = 2, sent = true, deal = { itemID = 42 } }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining", { [42] = old })
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "prewarmAttempt", warm)

    GC.Sniper.OnCommoditySearchResults(42)

    assert.is_nil(getUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining")[42])
    assert.is_true(getUpvalue(GC.Sniper.OnCommoditySearchResults, "prewarmAttempt") == warm)
    _G.C_AuctionHouse = nil
  end)

  it("does not Start while a cancelled requote tombstone still owns commodity events", function()
    local starts = 0
    _G.C_AuctionHouse = { StartCommoditiesPurchase = function() starts = starts + 1 end }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local primary = getUpvalue(createDialog, "onDialogPrimaryClick")
    local deal = { itemID = 42, isCommodity = true }
    local row = {
      deal = deal, purchaseStage = "ready", purchaseToken = 5,
      decisionSnapshot = { status = "SAFE", buyable = true, quantity = 3 },
    }
    setUpvalue(primary, "dialog", {
      row = row,
      primaryBtn = { Disable = function() end },
      status = { SetText = function() end, SetTextColor = function() end },
    })
    setUpvalue(primary, "commodityDraining", { itemID = 42, token = 4 })

    primary()

    assert.equal(0, starts)
    assert.equal("ready", row.purchaseStage)
    _G.C_AuctionHouse = nil
  end)

  it("flushes a throttled watchlist Check exactly once before its timeout can show Gone", function()
    -- Regression target: a Live scanner used to receive the throttle-ready event first while
    -- SniperFrame returned early for `mode == "watchlist"`. The dialog's parked Check then
    -- never sent and its timeout rendered the listing falsely Gone.
    local timers, sends, ready = {}, 0, false
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_AuctionHouse = {}
    _G.GetMoney = function() return 1000000 end
    _G.time = function() return 100 end
    _G.GetTime = function() return 100 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
      db = { settings = { sniper = {} } },
      SniperDecision = {
        Evaluate = function()
          return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } }
        end,
      },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local driver = {
      isReady = function() return ready end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() sends = sends + 1 end,
      commodityBook = function() return { { unitPrice = 100, quantity = 1 } } end,
      commodityResult = function() return { avail = 1 } end,
    }
    setUpvalue(startRequery, "driver", driver)

    local deal = { itemID = 42, isCommodity = true }
    local row = { deal = deal }
    startRequery(row, deal)
    assert.equal(0, sends)

    ready = true
    GC.Sniper.OnThrottleReady()
    GC.Sniper.OnThrottleReady()
    assert.equal(1, sends)

    GC.Sniper.OnCommoditySearchResults(42)
    timers[1]()
    assert.equal("check", row.purchaseStage)
    _G.C_Timer, _G.C_AuctionHouse, _G.GetMoney, _G.GetTime = nil, nil, nil, nil
    _G.time = os.time
  end)

  it("switches Check rows without an intervening Live search or ambiguous replacement result", function()
    -- Regression target: onBuyClick used abortRowPurchase(old) as a standalone Cancel. That
    -- synchronously restarted Live before openDialog(new) could register its new Check, so a
    -- Scanner:Start implementation that sends immediately could inject an untagged search.
    local timers, authoritativeSends, liveSends = {}, 0, 0
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_AuctionHouse = {}
    _G.GetMoney = function() return 1000000 end
    _G.time = function() return 100 end
    _G.GetTime = function() return 100 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return { 7 } end },
      db = { settings = { sniper = {} } },
      SniperDecision = {
        Evaluate = function()
          return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } }
        end,
      },
    }
    helper.loadModule("Core/Scanner.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local driver = {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() authoritativeSends = authoritativeSends + 1 end,
      commodityBook = function() return { { unitPrice = 100, quantity = 1 } } end,
      commodityResult = function() return { avail = 1 } end,
    }
    setUpvalue(startRequery, "driver", driver)
    setUpvalue(GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    GC.Sniper.scanner = GC.Scanner.New({
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      now = function() return 100 end,
      sendSearch = function() liveSends = liveSends + 1 end,
      onStatus = function() end,
    }, {})
    GC.Sniper.scanner:Start({ 7 })
    GC.Sniper.scanner:Stop()
    GC.Sniper._liveTargets = { 7 }
    liveSends = 0

    local oldDeal = { itemID = 42, isCommodity = true }
    local oldRow = { deal = oldDeal, purchaseStage = "requerying", purchaseToken = 1 }
    local oldAttempt = { row = oldRow, itemID = 42, token = 1, deal = oldDeal, sent = false }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", { [42] = oldAttempt })
    GC.Sniper._pausedLiveRequery = oldAttempt
    setUpvalue(onBuyClick, "dialog", { row = oldRow, Hide = function() end })
    setUpvalue(onBuyClick, "openDialog", function(row, deal) startRequery(row, deal) end)

    local newDeal = { itemID = 43, isCommodity = true }
    local newRow = { deal = newDeal }
    onBuyClick(newRow)

    assert.equal(0, liveSends)
    assert.equal(1, authoritativeSends)
    -- The harness bypasses visual openDialog construction; result ownership itself has no UI
    -- dependency, so remove the old-row shell before dispatching the real event handler.
    setUpvalue(onBuyClick, "dialog", nil)
    GC.Sniper.OnCommoditySearchResults(43)
    assert.equal("check", newRow.purchaseStage)
    assert.is_nil(oldRow.purchaseStage)
    assert.equal(1, liveSends) -- only after the replacement result resolves ownership
    _G.C_Timer, _G.C_AuctionHouse, _G.GetMoney, _G.GetTime = nil, nil, nil, nil
    _G.time = os.time
  end)

  it("releases a transferred Live pause exactly once when B's drain fence clears", function()
    -- Regression target: A→B keeps A's pause owner, but B can be blocked behind a previous
    -- sent B result. The drain handler used to clear only the fence, leaving Live stranded.
    local timers, liveSends = {}, 0
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_AuctionHouse = {}
    _G.GetMoney = function() return 1000000 end
    _G.time = function() return 100 end
    _G.GetTime = function() return 100 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return { 7 } end },
      db = { settings = { sniper = {} } },
      SniperDecision = { Evaluate = function() return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } } end },
    }
    helper.loadModule("Core/Scanner.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    setUpvalue(startRequery, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() error("B must not send before its old result drains") end,
    })
    setUpvalue(GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    GC.Sniper.scanner = GC.Scanner.New({
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      now = function() return 100 end,
      sendSearch = function() liveSends = liveSends + 1 end,
      onStatus = function() end,
    }, {})
    GC.Sniper.scanner:Start({ 7 })
    GC.Sniper.scanner:Stop()
    GC.Sniper._liveTargets = { 7 }
    liveSends = 0

    local aDeal = { itemID = 42, isCommodity = true }
    local aRow = { deal = aDeal, purchaseStage = "requerying", purchaseToken = 1 }
    local aAttempt = { row = aRow, itemID = 42, token = 1, deal = aDeal, sent = false }
    local oldB = { itemID = 43, token = 7, sent = true }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", { [42] = aAttempt })
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining", { [43] = oldB })
    GC.Sniper._pausedLiveRequery = aAttempt
    setUpvalue(onBuyClick, "dialog", { row = aRow, Hide = function() end })
    setUpvalue(onBuyClick, "openDialog", function(row, deal)
      setUpvalue(onBuyClick, "dialog", nil) -- bypass visual construction; exercise ownership only
      startRequery(row, deal)
    end)

    local bRow = { deal = { itemID = 43, isCommodity = true } }
    onBuyClick(bRow)
    assert.equal("check", bRow.purchaseStage)
    assert.equal(0, liveSends)

    GC.Sniper.OnCommoditySearchResults(43)
    assert.equal(1, liveSends)
    GC.Sniper.OnCommoditySearchResults(43)
    assert.equal(1, liveSends)
    assert.equal("check", bRow.purchaseStage)

    -- A late B drain cannot resume a newer Check's owner or treat it as B's result.
    local newerOwner = { itemID = 99 }
    local staleDrain = { itemID = 43, token = 8, sent = true }
    GC.Sniper._pausedLiveRequery = newerOwner
    GC.Sniper._drainWaitRequery[43] = {
      row = bRow, itemID = 43, token = 2, deal = bRow.deal, draining = staleDrain,
    }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining", { [43] = staleDrain })
    GC.Sniper.OnCommoditySearchResults(43)
    assert.is_true(GC.Sniper._pausedLiveRequery == newerOwner)
    assert.equal(1, liveSends)
    assert.equal("check", bRow.purchaseStage)
    _G.C_Timer, _G.C_AuctionHouse, _G.GetMoney, _G.GetTime = nil, nil, nil, nil
    _G.time = os.time
  end)

  it("releases a transferred drain-wait owner when B is cancelled before its old result", function()
    local timers, liveSends = {}, 0
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_AuctionHouse = {}
    _G.GetMoney = function() return 1000000 end
    _G.time = function() return 100 end
    _G.GetTime = function() return 100 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return { 7 } end },
      db = { settings = { sniper = {} } },
      SniperDecision = { Evaluate = function() return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } } end },
    }
    helper.loadModule("Core/Scanner.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local abortRowPurchase = getUpvalue(createDialog, "abortRowPurchase")
    setUpvalue(startRequery, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() error("drain fence must still block B") end,
    })
    setUpvalue(GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    GC.Sniper.scanner = GC.Scanner.New({
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      now = function() return 100 end,
      sendSearch = function() liveSends = liveSends + 1 end,
      onStatus = function() end,
    }, {})
    GC.Sniper.scanner:Start({ 7 })
    GC.Sniper.scanner:Stop()
    GC.Sniper._liveTargets = { 7 }
    liveSends = 0

    local aDeal = { itemID = 42, isCommodity = true }
    local aRow = { deal = aDeal, purchaseStage = "requerying", purchaseToken = 1 }
    local aAttempt = { row = aRow, itemID = 42, token = 1, deal = aDeal, sent = false }
    local oldB = { itemID = 43, token = 7, sent = true }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", { [42] = aAttempt })
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining", { [43] = oldB })
    GC.Sniper._pausedLiveRequery = aAttempt
    setUpvalue(onBuyClick, "dialog", { row = aRow, Hide = function() end })
    setUpvalue(onBuyClick, "openDialog", function(row, deal)
      setUpvalue(onBuyClick, "dialog", nil)
      startRequery(row, deal)
    end)

    local bRow = { deal = { itemID = 43, isCommodity = true } }
    onBuyClick(bRow)
    abortRowPurchase(bRow, nil)
    assert.equal(1, liveSends)
    GC.Sniper.OnCommoditySearchResults(43)
    assert.equal(1, liveSends)
    _G.C_Timer, _G.C_AuctionHouse, _G.GetMoney, _G.GetTime = nil, nil, nil, nil
    _G.time = os.time
  end)
  -- Replaces two tests that pinned the Live pause/resume dance around a Check.
  -- Live is gone (Auto is strictly broader and the two fought each other with
  -- nothing in the interface saying so), so the scanner loop never runs and a
  -- Check has no contention to yield to. What still has to hold is that the Check
  -- sends its own search exactly once and touches the scanner not at all.
  it("checks a listing without starting or resuming the retired Live loop", function()
    local timers, sends, ready = {}, 0, false
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.C_AuctionHouse = {}
    _G.GetMoney = function() return 1000000 end
    _G.time = function() return 100 end
    _G.GetTime = function() return 100 end
    local scanner = { starts = 0, resumes = 0, stops = 0, scanned = 0 }
    function scanner:Start() self.starts = self.starts + 1 end
    function scanner:Resume() self.resumes = self.resumes + 1 end
    function scanner:Stop() self.stops = self.stops + 1 end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return { 42 } end },
      db = { settings = { sniper = {} } },
      SniperDecision = {
        Evaluate = function()
          return { status = "WATCH", buyable = false, reasons = { "shadow_mode" } }
        end,
      },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

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
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local driver = {
      isReady = function() return ready end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() sends = sends + 1 end,
      commodityBook = function() return { { unitPrice = 100, quantity = 1 } } end,
      commodityResult = function() return { avail = 1 } end,
    }
    setUpvalue(startRequery, "driver", driver)
    setUpvalue(GC.Sniper.OnAuctionHouseClosed, "ahOpen", true)
    GC.Sniper.scanner = scanner

    local deal = { itemID = 42, isCommodity = true }
    startRequery({ deal = deal }, deal)
    ready = true
    GC.Sniper.OnThrottleReady()
    GC.Sniper.OnCommoditySearchResults(42)

    assert.equal(1, sends)
    assert.equal(0, scanner.starts)
    assert.equal(0, scanner.stops)
    assert.equal(0, scanner.resumes)
    _G.C_Timer, _G.C_AuctionHouse, _G.GetMoney, _G.GetTime = nil, nil, nil, nil
    _G.time = os.time
  end)
  -- Blizzard's own buy dialog keeps listening for COMMODITY_PRICE_UPDATED after
  -- ConfirmCommoditiesPurchase: when the price moved between the quote and the Confirm click
  -- the server re-quotes instead of buying, and the player has to confirm again. The Sniper
  -- used to drop that event in "confirming" -- and a re-quote is never followed by a terminal
  -- event, so the confirmed attempt sat forever as an owned pending, then (after an AH close)
  -- as a confirmed tombstone that refused every later commodity Buy with "waiting for previous
  -- commodity purchase to settle" until /reload.
  it("re-quotes a confirmed attempt when the server updates the price after Confirm", function()
    local cancelCalls, timers = 0, {}
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() end,
      GetNumCommoditySearchResults = function() return 2 end,
      GetCommoditySearchResultInfo = function(_, index)
        if index == 1 then return { unitPrice = 1000000, quantity = 1 } end
        return { unitPrice = 2105265, quantity = 1 }
      end,
    }
    _G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    local deal = { itemID = 42, isCommodity = true }
    local quote = { token = 7, itemID = 42, quantity = 1, total = 1000000, decision = { status = "SAFE", buyable = true } }
    local row = {
      purchaseStage = "confirming", purchaseToken = 7, deal = deal, purchaseDeal = deal,
      decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1 },
      quoteSnapshot = quote,
    }
    local pending = { row = row, itemID = 42, token = 7, confirmed = true, deal = deal, quote = quote }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", pending)
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)

    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000) -- server re-quote, 4% above the confirmed quote

    -- No gold moved: the server is waiting for a fresh Confirm, so the attempt is unconfirmed
    -- again and its old immutable quote is gone with it.
    assert.is_falsy(pending.confirmed)
    assert.is_nil(pending.quote)
    assert.are_not.equal("confirming", row.purchaseStage)
    -- ...and the ordinary requote path judged the new price: it broke safety, so the attempt
    -- was cancelled and drained into a tombstone that retires on its own timer.
    assert.equal(1, cancelCalls)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase"))
    local draining = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining")
    assert.is_table(draining)
    assert.is_falsy(draining.confirmed)

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
  end)

  -- A confirmed attempt whose terminal event never comes (dropped event, disconnect, a server
  -- that answered with nothing) must not hold the single commodity slot until /reload. Its
  -- bookkeeping is released after a generous window and the player is told to check the
  -- mailbox -- the honest statement, since the buy may or may not have gone through.
  it("releases a confirmed attempt that never hears back from the server", function()
    _G.C_AuctionHouse = { CancelCommoditiesPurchase = function() end }
    _G.GetTime = function() return 0 end
    _G.time = function() return 100000 end
    local printed = {}
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    GC.Print = function(text) printed[#printed + 1] = text end
    local stranded = { row = {}, itemID = 42, token = 5, confirmed = true, deal = { itemID = 42, isCommodity = true } }

    -- The AH-close tombstone slot...
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", stranded)
    GC.Sniper._ReleaseStrandedConfirmed(stranded)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))
    assert.equal(1, #printed)
    assert.is_truthy(printed[1]:find("inspect mailbox", 1, true))

    -- ...and the live owned slot alike.
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", stranded)
    GC.Sniper._ReleaseStrandedConfirmed(stranded)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase"))

    -- Bound to the exact attempt it was armed for: a later attempt in either slot is untouched.
    local other = { row = {}, itemID = 43, token = 6, confirmed = true }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", other)
    GC.Sniper._ReleaseStrandedConfirmed(stranded)
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == other)
    assert.equal(2, #printed)

    -- Armed by the hardware Confirm click itself, right where the attempt becomes confirmed.
    local click = section(source(), "local function onDialogPrimaryClick()", "-- ---------------------------------------------------------------------------\n-- Sniper v3 dialog layout constants")
    local confirmAt = assert(click:find("pending.confirmed = true", 1, true))
    local releaseAt = assert(click:find("_ReleaseStrandedConfirmed", 1, true))
    assert.is_true(confirmAt < releaseAt)

    _G.C_AuctionHouse, _G.GetTime, _G.time = nil, nil, nil
  end)
end)
