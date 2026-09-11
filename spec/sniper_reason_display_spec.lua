local helper = require("spec.spec_helper")

-- The dialog and status line are the last thing a player reads before spending real gold.
-- GC.SniperDecision.ReasonText is the one place that turns an engine token ("stress_profit_-
-- below_buffer") into a sentence a player can act on. Every player-facing reason string in
-- SniperFrame.lua must be routed through it -- the diagnostic line (`item=... reasons=...`)
-- is the one deliberate exception, kept exact for bug reports, and is not asserted here.
describe("Sniper dialog reason humanization", function()
  local function baseGC()
    return {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        -- Check panel v3 tints the verdict band, the headline figure and every fact from
        -- these, so the palette is no longer optional in a Theme double.
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
      end },
      Data = { GetItemValue = function() return {} end },
      db = { settings = { sniper = {} } },
    }
  end

  local function loadSniper(GC)
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
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
  end

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

  local function textSink()
    return { SetText = function() end, SetTextColor = function() end, Show = function() end, Hide = function() end }
  end

  local function fakeDialog(reasonText, diagnosticText)
    return {
      fixedHeight = 400, diagnosticGaps = 4, diagnosticMinimumHeight = 108,
      detailsOpen = false, evidenceTopOpen = -200, evidenceTopClosed = -100,
      SetHeight = function() end,
      banner = { IsShown = function() return false end },
      diagnosticText = diagnosticText,
      status = { ClearAllPoints = function() end, SetPoint = function() end },
      decisionStatusText = textSink(), quantityText = textSink(), unitPriceText = textSink(),
      totalCostText = textSink(), exitUnitText = textSink(), profitText = textSink(),
      mvText = textSink(), soldText = textSink(), sellThroughText = textSink(),
      sourceAgeText = textSink(), reasonText = reasonText,
      verdictHead = textSink(), verdictSub = textSink(),
      mvNote = { Hide = function() end, ClearAllPoints = function() end, SetPoint = function() end },
    }
  end

  local function fakeTextRegion()
    local region = { text = "" }
    function region:SetText(text) self.text = text end
    return region
  end

  local function fakeDiagnostic()
    local d = fakeTextRegion()
    function d:GetStringHeight() return 24 end
    function d:SetHeight() end
    function d:ClearAllPoints() end
    function d:SetPoint() end
    function d:Show() end
    function d:Hide() end
    return d
  end

  it("shows a sentence, not a bare token, on the buy dialog's Reason line", function()
    local GC = baseGC()
    loadSniper(GC)

    local reasonText = fakeTextRegion()
    local dialog = fakeDialog(reasonText, fakeDiagnostic())
    local stamp = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "stampDialogFromDecision")
    setUpvalue(stamp, "dialog", dialog)
    setUpvalue(stamp, "marketForDecision", function() return {} end)

    stamp({ itemID = 42 }, {
      computedStatus = "WATCH", status = "WATCH", buyable = false, quantity = 1,
      reasons = { "stress_profit_below_buffer" },
    })

    assert.not_equal("stress_profit_below_buffer", reasonText.text)
    assert.equal(GC.SniperDecision.ReasonText("stress_profit_below_buffer"), reasonText.text)
  end)

  it("shows the sentence for the reason that actually refused, not an informational one", function()
    -- `demand_limit` is informational (added whenever the chosen qty is capped, which is
    -- ordinary) and sorts ahead of the gate that actually refused. The headline must skip it
    -- exactly like the raw firstReason search already does, and still humanize what it lands on.
    local GC = baseGC()
    loadSniper(GC)

    local reasonText = fakeTextRegion()
    local dialog = fakeDialog(reasonText, fakeDiagnostic())
    local stamp = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "stampDialogFromDecision")
    setUpvalue(stamp, "dialog", dialog)
    setUpvalue(stamp, "marketForDecision", function() return {} end)

    stamp({ itemID = 42 }, {
      computedStatus = "WATCH", status = "WATCH", buyable = false, quantity = 1,
      reasons = { "demand_limit", "stress_profit_below_buffer" },
      informational = { demand_limit = true },
    })

    assert.equal(GC.SniperDecision.ReasonText("stress_profit_below_buffer"), reasonText.text)
  end)

  it("humanizes the requote-broke-safety status note instead of concatenating the raw token", function()
    local cancelCalls = 0
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() end,
    }
    _G.C_Timer = { After = function() end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end

    local GC = baseGC()
    GC.Data = { GetItemValue = function()
      return {
        mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
        stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
        liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
        madBps = 0, trend = -9,
      }
    end }
    GC.db = { settings = { sniper = {
      maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
      minimumProfitCopper = 1000000, minimumRoi = 0.10,
    } } }
    loadSniper(GC)

    local row = {
      purchaseStage = "buying", purchaseToken = 7,
      purchaseDeal = { itemID = 42, isCommodity = true },
      decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1 },
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)

    -- A broken requote no longer drops the row to Check: it cancels and re-runs the live
    -- requery itself. The sentence the player reads is the dialog status, so capture that,
    -- and stub the requery -- this example is about the wording, not the search.
    local capturedNote
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "setDialogStatus", function(text) capturedNote = text end)
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery", function() end)

    -- Same fixture the purchase-wiring suite uses: a 4% higher server total that still fails
    -- the fixed stress-profit math, so the handler cancels through requote_broke_safety.
    _G.C_AuctionHouse.GetNumCommoditySearchResults = function() return 2 end
    _G.C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index)
      if index == 1 then return { unitPrice = 1000000, quantity = 1 } end
      return { unitPrice = 2105265, quantity = 1 }
    end
    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000)

    assert.equal(1, cancelCalls)
    assert.is_string(capturedNote)
    assert.is_nil(capturedNote:find("requote_broke_safety", 1, true))
    assert.is_truthy(capturedNote:find(GC.SniperDecision.ReasonText("requote_broke_safety"), 1, true))

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
  end)

  it("routes a failed player-chosen-quantity re-evaluation through ReasonText, not a bare token", function()
    -- applyChosenQty has no reachable behavioural seam (its armCheck call sits inside a nested
    -- qtyBox.onCommit closure that only exists once createDialog has built real widgets), so
    -- this asserts the fix at the source, the same way the wiring suite asserts protected-call
    -- placement: the literal reasons[1] fallback must be wrapped in GC.SniperDecision.ReasonText.
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = f:read("*a")
    f:close()

    local from = assert(text:find("local function applyChosenQty(row, n)", 1, true))
    local to = assert(text:find("local function applyQuickFillQty(pct)", 1, true))
    local body = text:sub(from, to - 1)

    assert.is_truthy(body:find(
      "GC.SniperDecision.ReasonText((decision and decision.reasons and decision.reasons[1])",
      1, true))
  end)
end)
