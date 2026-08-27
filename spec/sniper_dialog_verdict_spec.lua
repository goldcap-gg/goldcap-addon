local helper = require("spec.spec_helper")

-- The buy dialog used to read as a debug dump: a 12-row label/value grid and a literal
-- `item=... reasons=...` line, one click from spending real gold. These specs cover the
-- restructure -- a verdict block above the grid, the grid itself behind a collapsed-by-default
-- Details toggle, and the diagnostic line hidden unless GC.db.settings.sniper.debug is on.
describe("Sniper buy dialog verdict block", function()
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

  local function fakeVerdictHead()
    local w = { text = "", colors = {} }
    function w:SetText(t) self.text = t end
    function w:SetTextColor(r, g, b) self.colors[#self.colors + 1] = { r, g, b } end
    return w
  end

  local function fakeVerdictSub()
    local w = { text = "", shown = nil }
    function w:SetText(t) self.text = t end
    function w:SetTextColor() end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
  end

  local function fakeDiagnostic()
    local d = { text = "", shown = nil, heightCalls = 0 }
    function d:SetText(t) self.text = t end
    function d:GetStringHeight() return 24 end
    function d:SetHeight() self.heightCalls = self.heightCalls + 1 end
    function d:ClearAllPoints() end
    function d:SetPoint() end
    function d:Show() self.shown = true end
    function d:Hide() self.shown = false end
    return d
  end

  -- Task 2 restyle: distinct-color widget doubles for the new verdictLabel/verdictAmount
  -- fields, same "record every SetTextColor call" shape as fakeVerdictHead above -- so the
  -- SAFE/REFUSED tint assertions below compare against real, different color tables (green vs
  -- red) rather than two stubs that happen to look alike.
  local function fakeVerdictLabel()
    local w = { text = "", colors = {} }
    function w:SetText(t) self.text = t end
    function w:SetTextColor(r, g, b) self.colors[#self.colors + 1] = { r, g, b } end
    return w
  end

  local function fakeVerdictAmount()
    local w = { text = "", colors = {}, shown = nil }
    function w:SetText(t) self.text = t end
    function w:SetTextColor(r, g, b) self.colors[#self.colors + 1] = { r, g, b } end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
  end

  -- Fix round 1: state-tracking double for the caption, same "shown" shape as fakeVerdictSub
  -- above -- textSink()'s Show/Hide are no-ops, which would make the "orphaned caption on
  -- refusal" assertion below vacuous.
  local function fakeVerdictAmountNote()
    local w = { shown = nil }
    function w:SetText() end
    function w:SetTextColor() end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
  end

  -- Check panel v2: state-tracking double shared by the new entryCard/exitCard/suspectNote
  -- fields below -- Show()/Hide() record which one last ran (nil until either does, same
  -- "starts nil" shape as fakeVerdictAmount/fakeVerdictSub above), so the cards-vs-note
  -- assertions are non-vacuous.
  local function fakeShowHide()
    local w = { shown = nil }
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
  end

  local function fakeDialog(overrides)
    local d = {
      fixedHeight = 400, diagnosticGaps = 4, diagnosticMinimumHeight = 108,
      detailsOpen = false, evidenceTopOpen = -200, evidenceTopClosed = -100,
      SetHeight = function() end,
      banner = { IsShown = function() return false end },
      diagnosticText = fakeDiagnostic(),
      status = { ClearAllPoints = function() end, SetPoint = function() end },
      decisionStatusText = textSink(), unitPriceText = textSink(), totalCostText = textSink(),
      exitUnitText = textSink(), profitText = textSink(), mvText = textSink(),
      soldText = textSink(), sellThroughText = textSink(), sourceAgeText = textSink(),
      reasonText = textSink(), verdictHead = fakeVerdictHead(), verdictSub = fakeVerdictSub(),
      mvNote = { Hide = function() end, ClearAllPoints = function() end, SetPoint = function() end },
    }
    for k, v in pairs(overrides or {}) do d[k] = v end
    return d
  end

  local function load(dbOverrides)
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
        tier = { WATCH = { 1, 1, 1 } },
        -- Task 2 restyle: green/red added (additive -- every existing test in this file only
        -- ever reads fg/fgDim off this table) for stampDialogFromDecision's new guarded
        -- verdictLabel/verdictAmount tint calls.
        color = { fg = { 0.9, 0.9, 0.9 }, fgDim = { 0.5, 0.5, 0.5 },
          green = { 0.25, 0.85, 0.25 }, red = { 0.898, 0.283, 0.302 } } },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
      end },
      Data = { GetItemValue = function() return {} end },
      db = { settings = { sniper = dbOverrides or {} } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local stamp = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "stampDialogFromDecision")
    setUpvalue(stamp, "marketForDecision", function() return {} end)
    return GC, stamp
  end

  it("names the action and its cost when the decision is buyable, with a quiet stress-profit sub-line", function()
    local GC, stamp = load()
    local d = fakeDialog()
    setUpvalue(stamp, "dialog", d)

    -- Both amounts stay >= formatColumnAmount's 100g compaction threshold so the expected
    -- strings are exact without also having to stub GetCoinTextureString.
    stamp({ itemID = 42 }, {
      status = "SAFE", buyable = true, quantity = 3, entryTotal = 4530000,
      stressProfit = 1200000, reasons = {},
    })

    assert.equal("Buy 3 × item 42 for 453g", d.verdictHead.text)
    assert.equal("you should clear about 120g", d.verdictSub.text)
    assert.is_true(d.verdictSub.shown)
    assert.same({ GC.Theme.color.fg[1], GC.Theme.color.fg[2], GC.Theme.color.fg[3] },
      d.verdictHead.colors[#d.verdictHead.colors])
  end)

  it("uses the item name/icon cache setRowDeal populates, not a fresh Item lookup", function()
    local _, stamp = load()
    local d = fakeDialog()
    setUpvalue(stamp, "dialog", d)
    local nameIconCache = getUpvalue(stamp, "nameIconCache")
    nameIconCache[42] = { icon = "icon", named = "|cffffffffArgentleaf|r" }

    stamp({ itemID = 42 }, {
      status = "SAFE", buyable = true, quantity = 1, entryTotal = 2000000, stressProfit = 1000000, reasons = {},
    })

    assert.equal("Buy 1 × |cffffffffArgentleaf|r for 200g", d.verdictHead.text)
  end)

  it("shows the refusal sentence in refusal red and hides the sub-line when not buyable", function()
    local GC, stamp = load()
    local d = fakeDialog()
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, {
      status = "WATCH", buyable = false, quantity = 0,
      reasons = { "stress_profit_below_buffer" },
    })

    assert.equal(GC.SniperDecision.ReasonText("stress_profit_below_buffer"), d.verdictHead.text)
    assert.not_equal("stress_profit_below_buffer", d.verdictHead.text)
    assert.same({ 1, 0.3, 0.3 }, d.verdictHead.colors[#d.verdictHead.colors])
    assert.is_false(d.verdictSub.shown)
  end)

  it("stamps the live-verdict kicker and big signed profit figure when both widgets exist, buyable then refusal", function()
    -- Task 2 restyle. A fakeDialog WITHOUT verdictLabel/verdictAmount/verdictAmountNote is
    -- exactly what every other test in this file already builds (fakeDialog()'s own base
    -- shape, unmodified) -- those must keep stamping fine (they do, elsewhere in this file);
    -- this test is the additive counterpart with a fakeDialog that HAS them.
    local GC, stamp = load()
    local d = fakeDialog({
      verdictLabel = fakeVerdictLabel(),
      verdictAmount = fakeVerdictAmount(),
      verdictAmountNote = fakeVerdictAmountNote(),
    })
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, {
      status = "SAFE", buyable = true, quantity = 3, entryTotal = 4530000,
      stressProfit = 1200000, reasons = {},
    })
    assert.equal("LIVE VERDICT · SAFE", d.verdictLabel.text)
    assert.same({ GC.Theme.color.green[1], GC.Theme.color.green[2], GC.Theme.color.green[3] },
      d.verdictLabel.colors[#d.verdictLabel.colors])
    assert.equal("+120g", d.verdictAmount.text) -- same 1200000-copper figure verdictSub's own sentence uses
    assert.same({ GC.Theme.color.green[1], GC.Theme.color.green[2], GC.Theme.color.green[3] },
      d.verdictAmount.colors[#d.verdictAmount.colors])
    assert.is_true(d.verdictAmount.shown)
    assert.is_true(d.verdictAmountNote.shown) -- Fix round 1: the caption goes with the amount

    stamp({ itemID = 42 }, {
      status = "WATCH", buyable = false, quantity = 0,
      reasons = { "stress_profit_below_buffer" },
    })
    assert.equal("LIVE VERDICT · REFUSED", d.verdictLabel.text)
    assert.same({ GC.Theme.color.red[1], GC.Theme.color.red[2], GC.Theme.color.red[3] },
      d.verdictLabel.colors[#d.verdictLabel.colors])
    assert.is_false(d.verdictAmount.shown)
    assert.is_false(d.verdictAmountNote.shown) -- Fix round 1: not orphaned when the amount hides
  end)

  -- Item 3 (addon polish batch): the dialog is a session-long singleton, and the refusal branch
  -- above only Hides verdictAmount (never resets its color -- there is nothing to clear on a
  -- real refusal, the amount is gone). openDialog's own CHECKING placeholder re-Shows it with a
  -- neutral "--" but, before this fix, never re-tinted it, so a dash left over from an earlier
  -- buyable (green) check rendered as a green "checking..." verdict -- reading as a live
  -- positive verdict before the requote even lands.
  it("keeps the CHECKING verdict amount dim, not leftover green from an earlier buyable check", function()
    _G.GetTime = function() return 100 end
    local GC, stamp = load()
    local d = fakeDialog({
      verdictLabel = fakeVerdictLabel(),
      verdictAmount = fakeVerdictAmount(),
      verdictAmountNote = fakeVerdictAmountNote(),
      cancelBtn = { SetLabel = function() end, Enable = function() end },
      primaryBtn = { Disable = function() end },
      Show = function() end,
    })
    setUpvalue(stamp, "dialog", d)

    -- First dialog resolves buyable -- the real stamp path, same as the test above.
    stamp({ itemID = 42 }, {
      status = "SAFE", buyable = true, quantity = 1, entryTotal = 2000000,
      stressProfit = 1000000, reasons = {},
    })
    assert.same({ GC.Theme.color.green[1], GC.Theme.color.green[2], GC.Theme.color.green[3] },
      d.verdictAmount.colors[#d.verdictAmount.colors])

    -- Second dialog, a different deal, opened fresh (no .stale/.prewarm -- takes openDialog's
    -- CHECKING branch). `dialog` is a shared upvalue across the whole file, so this is the
    -- SAME fake `d` stamp just painted green.
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    setUpvalue(openDialog, "hideRequoteBanner", function() end)
    setUpvalue(openDialog, "setDialogHeader", function() end)
    setUpvalue(openDialog, "setPrimaryLabel", function() end)
    setUpvalue(openDialog, "setDialogStatus", function() end)
    setUpvalue(openDialog, "startRequery", function() end)

    openDialog({}, { itemID = 43 })

    assert.equal("—", d.verdictAmount.text)
    assert.is_true(d.verdictAmount.shown)
    assert.same({ GC.Theme.color.fgDim[1], GC.Theme.color.fgDim[2], GC.Theme.color.fgDim[3] },
      d.verdictAmount.colors[#d.verdictAmount.colors])
    _G.GetTime = nil
  end)

  it("stamps the ENTRY AVG / STRESS EXIT cards from the same two values as the evidence grid, and swaps them for the suspect note on a SUSPECT tier", function()
    -- Check panel v2. The two amounts are owned by stampDialogFromDecision (same as
    -- unitPriceText/exitUnitText); which of the cards-vs-note pair is shown is owned by
    -- setDialogHeader instead -- both guarded on the same new dialog.* fields, exercised
    -- together here the way openDialog/armReady/armCheck actually call them in sequence.
    local GC, stamp = load()
    local d = fakeDialog({
      entryValue = textSink(), exitValue = textSink(),
      entryCard = fakeShowHide(), exitCard = fakeShowHide(),
      tierChip = { SetLabel = function() end },
      suspectNote = fakeShowHide(),
      nameText = textSink(), icon = { SetTexture = function() end },
    })
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, {
      status = "SAFE", buyable = true, quantity = 3, entryTotal = 4530000,
      stressProfit = 1200000, exitUnit = 1600000, reasons = {},
    })
    assert.equal(d.unitPriceText.text, d.entryValue.text)
    assert.equal(d.exitUnitText.text, d.exitValue.text)

    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local setDialogHeader = getUpvalue(openDialog, "setDialogHeader")

    setDialogHeader({ itemID = 42, tier = "WATCH" }, {})
    assert.is_true(d.entryCard.shown)
    assert.is_true(d.exitCard.shown)
    assert.is_false(d.suspectNote.shown)

    setDialogHeader({ itemID = 42, tier = "SUSPECT" }, {})
    assert.is_false(d.entryCard.shown)
    assert.is_false(d.exitCard.shown)
    assert.is_true(d.suspectNote.shown)
  end)

  it("hides the diagnostic line and contributes no height to it by default", function()
    local _, stamp = load() -- no debug key set -> off
    local d = fakeDialog()
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, { status = "SAFE", buyable = true, quantity = 1, entryTotal = 2000000, reasons = {} })

    assert.is_false(d.diagnosticText.shown)
    assert.equal(0, d.diagnosticText.heightCalls)
    assert.equal(400, d.baseHeight) -- fixedHeight(400) + 0 gap + 0 diagnostic height
  end)

  it("shows the diagnostic line, unchanged text, once debug is turned on", function()
    local _, stamp = load({ debug = true })
    local d = fakeDialog()
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, {
      computedStatus = "SAFE", status = "WATCH", buyable = false, quantity = 1,
      reasons = { "brief" },
    })

    assert.is_true(d.diagnosticText.shown)
    assert.equal(1, d.diagnosticText.heightCalls)
    assert.equal("item=42 computed=SAFE public=WATCH buyable=no reasons=brief", d.diagnosticText.text)
  end)

  it("shows the exact same diagnostic text regardless of the debug setting", function()
    local decision = {
      computedStatus = "WATCH", status = "WATCH", buyable = false, quantity = 1,
      reasons = { "listings_too_low" },
    }
    local _, stampOff = load()
    local dOff = fakeDialog()
    setUpvalue(stampOff, "dialog", dOff)
    stampOff({ itemID = 7 }, decision)

    local _, stampOn = load({ debug = true })
    local dOn = fakeDialog()
    setUpvalue(stampOn, "dialog", dOn)
    stampOn({ itemID = 7 }, decision)

    assert.equal(dOn.diagnosticText.text, dOff.diagnosticText.text)
  end)

  -- createDialog builds real widget trees (Theme.Panel/CreateFrame etc), which this suite
  -- does not stand up -- see the other specs in this file for the reachable behaviour
  -- (stampDialogFromDecision, resizeDialogDiagnostics). These assert the toggle's own wiring
  -- the same way the wiring suite asserts protected-call placement: against the source.
  describe("Details toggle wiring (source)", function()
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

    it("keeps Quantity and its quick-fill row above the Details toggle, not behind it", function()
      local text = source()
      local qtyPos = assert(text:find("local qtyBox = makeQtyEditBox(d,", 1, true))
      local quickFillPos = assert(text:find("local quickFillBtns = {}", 1, true))
      local togglePos = assert(text:find("local detailsToggle = Theme.Button(d,", 1, true))
      local evidenceRowsPos = assert(text:find("d.evidenceRows = {}", 1, true))
      assert.is_true(qtyPos < togglePos)
      assert.is_true(quickFillPos < togglePos)
      assert.is_true(togglePos < evidenceRowsPos) -- the toggle exists before the rows it hides
    end)

    it("shows/hides every evidence row pair and flips the toggle's own label together", function()
      local text = source()
      local body = section(text, "local function applyDetailsState(open)", "detailsToggle:SetScript(\"OnClick\"")
      assert.is_truthy(body:find("d.detailsToggle:SetLabel(", 1, true))
      assert.is_truthy(body:find("for _, pair in ipairs(d.evidenceRows) do", 1, true))
      assert.is_truthy(body:find("pair.label:Show()", 1, true))
      assert.is_truthy(body:find("pair.value:Show()", 1, true))
      assert.is_truthy(body:find("pair.label:Hide()", 1, true))
      assert.is_truthy(body:find("pair.value:Hide()", 1, true))
    end)

    it("switches between the two precomputed fixed-height budgets, never recomputing DG live", function()
      local text = source()
      local body = section(text, "local function applyDetailsState(open)", "detailsToggle:SetScript(\"OnClick\"")
      assert.is_truthy(body:find(
        "d.fixedHeight = d.detailsOpen and DG.FIXED_HEIGHT_OPEN or DG.FIXED_HEIGHT_CLOSED", 1, true))
    end)

    it("persists the open/closed choice under GC.db.settings.sniper.dialogDetailsOpen", function()
      local text = source()
      local body = section(text, "local function applyDetailsState(open)", "detailsToggle:SetScript(\"OnClick\"")
      assert.is_truthy(body:find("cfg.dialogDetailsOpen = d.detailsOpen", 1, true))
    end)

    it("restores the persisted choice on the dialog's own first construction", function()
      local text = source()
      assert.is_truthy(text:find(
        "applyDetailsState(savedCfg and savedCfg.dialogDetailsOpen)", 1, true))
    end)

    it("routes the toggle's click through the same apply function that seeds the initial state", function()
      local text = source()
      assert.is_truthy(text:find(
        "detailsToggle:SetScript(\"OnClick\", function() applyDetailsState(not d.detailsOpen) end)",
        1, true))
    end)

    -- Fix wave (check panel v2 review): createFrame's OnSizeChanged re-applies the saved
    -- preference on every resize (see the OnSizeChanged section below), including a downsize
    -- that trips this very guard -- without this, every drag-resize past the fit floor would
    -- spam "Enlarge the window to see details" the whole way down.
    it("does not announce the F5 refusal while a resize's own re-apply is in flight (detailsQuiet)", function()
      local text = source()
      local body = section(text, "local function applyDetailsState(open)", "detailsToggle:SetScript(\"OnClick\"")
      -- Pinned through the string layer: the sentence is now a GC.L key, so the source reads
      -- setDialogStatus(GC.L[...]) while the words themselves are unchanged.
      assert.is_truthy(body:find(
        "if dialog and not d.detailsQuiet then setDialogStatus(GC.L[\"Enlarge the window to see details\"]) end",
        1, true))
    end)

    -- The dialog exposes applyDetailsState so createFrame's OnSizeChanged can drive it directly
    -- (the only handle the rest of the file gets on this closure), same idiom as f.applyPanelInset.
    it("exposes applyDetailsState on the dialog table for the resize hook to call", function()
      local text = source()
      assert.is_truthy(text:find("d.applyDetailsState = applyDetailsState", 1, true))
    end)
  end)

  it("DG's open/closed height budgets differ by exactly one evidence grid, with no overlap or negative geometry", function()
    -- A behavioural sanity check on the actual production constants (not a stand-in), reached
    -- as a direct upvalue of createDialog -- DG's own fields are referenced right in its body.
    local Theme = { RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 } }
    local GC = { Theme = Theme,
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
      end },
      Data = { GetItemValue = function() return {} end },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    -- Same debug.getupvalue chain the wiring suite documents and uses throughout:
    -- clearDeals -> refreshRows -> createRow -> buildRowCell -> onBuyClick -> openDialog.
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local DG = getUpvalue(createDialog, "DG")

    assert.equal(DG.GRID_ROWS * DG.GRID_ROW_H, DG.FIXED_HEIGHT_OPEN - DG.FIXED_HEIGHT_CLOSED)
    assert.is_true(DG.FIXED_HEIGHT_CLOSED > 0)
    -- Stacked top-to-bottom without overlap: verdict, then Quantity, then the toggle, each
    -- strictly below the one before it.
    assert.is_true(DG.VERDICT_TOP > DG.QTY_TOP)
    assert.is_true(DG.QTY_TOP > DG.CARDS_TOP)
    assert.is_true(DG.CARDS_TOP > DG.TOGGLE_TOP)
    assert.is_true(DG.TOGGLE_TOP > DG.GRID_TOP)
    assert.is_true(DG.GRID_TOP > DG.EVIDENCE_BOTTOM_OPEN)
    assert.is_true(DG.TOGGLE_TOP > DG.EVIDENCE_BOTTOM_CLOSED)
  end)
end)
