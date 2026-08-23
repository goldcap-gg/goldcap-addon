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
        color = { fg = { 0.9, 0.9, 0.9 }, fgDim = { 0.5, 0.5, 0.5 } } },
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
    assert.is_true(DG.QTY_TOP > DG.TOGGLE_TOP)
    assert.is_true(DG.TOGGLE_TOP > DG.GRID_TOP)
    assert.is_true(DG.GRID_TOP > DG.EVIDENCE_BOTTOM_OPEN)
    assert.is_true(DG.TOGGLE_TOP > DG.EVIDENCE_BOTTOM_CLOSED)
  end)
end)
