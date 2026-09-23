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

  -- Check panel v3: one fact row is a label, a value, and EITHER a meter or a leader line --
  -- never both. Recording `shown` on each is what lets a test assert the choice rather than
  -- the pixels.
  local function fakeFactRows()
    local rows = {}
    for i = 1, 4 do
      local function region()
        local w = { text = "", shown = nil, colors = {} }
        function w:SetText(t) self.text = t end
        function w:SetTextColor(r, g, b) self.colors[#self.colors + 1] = { r, g, b } end
        function w:SetWidth(n) self.width = n end
        function w:SetColorTexture() end
        function w:ClearAllPoints() end
        function w:SetPoint() end
        function w:Show() self.shown = true end
        function w:Hide() self.shown = false end
        return w
      end
      rows[i] = { label = region(), value = region(), meter = region(),
        leader = region(), fill = region(), tick = region() }
    end
    return rows
  end

  local function fakeHeroText()
    local w = { text = "", shown = nil }
    function w:SetText(t) self.text = t end
    function w:SetTextColor() end
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
        color = { fg = { 0.9, 0.9, 0.9 }, fgDim = { 0.5, 0.5, 0.5 }, fgMuted = { 0.72, 0.71, 0.69 },
          green = { 0.25, 0.85, 0.25 }, red = { 0.898, 0.283, 0.302 },
          gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
      end },
      Data = { GetItemValue = function() return {} end },
      db = { settings = { sniper = dbOverrides or {} } },
    }
    -- Core/Util.lua: the facts block formats counts through GC.Util.FormatCount (see its own
    -- comment there for why "856k" beats "856146.0" in a 90px column).
    helper.loadModule("Core/Util.lua", GC)
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
    local stamp = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "stampDialogFromDecision")
    setUpvalue(stamp, "marketForDecision", function() return {} end)
    return GC, stamp
  end

  -- Check panel v3. The verdict block stopped narrating the click ("Buy 3 × Argentleaf for
  -- 453g" said what the header and the primary button already said, twice) and stopped
  -- printing the same profit figure a third time in a sub-line. What is left is the sentence
  -- that says why the answer is what it is.
  it("states why the trade is clear, and never repeats the figure in a sub-line", function()
    local GC, stamp = load()
    local d = fakeDialog()
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, {
      status = "SAFE", buyable = true, quantity = 3, entryTotal = 4530000,
      stressProfit = 1200000, reasons = {},
    })

    assert.equal("Checked against the live order book a moment ago.", d.verdictHead.text)
    assert.is_false(d.verdictSub.shown)
    assert.same({ GC.Theme.color.fg[1], GC.Theme.color.fg[2], GC.Theme.color.fg[3] },
      d.verdictHead.colors[#d.verdictHead.colors])
  end)

  -- The item's own name belongs to the header, which resolves it asynchronously and colours it
  -- by quality. Repeating it inside the verdict meant the one line with room for a REASON was
  -- spending most of its width on an identity the player was already looking at.
  it("leaves the item's identity to the header rather than restating it in the verdict", function()
    local _, stamp = load()
    local d = fakeDialog()
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, {
      status = "SAFE", buyable = true, quantity = 1, entryTotal = 2000000,
      stressProfit = 1000000, reasons = {},
    })

    assert.is_nil(d.verdictHead.text:find("42", 1, true))
    assert.is_nil(d.verdictHead.text:find("item", 1, true))
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

  -- Check panel v3. The kicker names the ANSWER ("Won't buy"), not the machine's state
  -- ("LIVE VERDICT · REFUSED"), and the figure below it changes UNIT rather than disappearing:
  -- a refusal about the price still has a loss to show, and only a refusal about the VALUE has
  -- no honest number at all. The old panel hid the figure on every refusal and left a 94px hole.
  it("names the answer and keeps a figure on a refusal that still has one", function()
    local GC, stamp = load()
    local d = fakeDialog({
      verdictLabel = fakeVerdictLabel(),
      verdictAmount = fakeVerdictAmount(),
      verdictAmountNote = fakeVerdictAmountNote(),
      heroText = fakeHeroText(),
    })
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, {
      status = "SAFE", buyable = true, quantity = 3, entryTotal = 4530000,
      stressProfit = 1200000, reasons = {},
    })
    assert.equal("Clear to buy", d.verdictLabel.text)
    assert.same({ GC.Theme.color.green[1], GC.Theme.color.green[2], GC.Theme.color.green[3] },
      d.verdictLabel.colors[#d.verdictLabel.colors])
    assert.equal("+120g", d.verdictAmount.text)
    assert.is_true(d.verdictAmount.shown)
    assert.is_false(d.heroText.shown)
    assert.is_true(d.verdictAmountNote.shown)

    stamp({ itemID = 42 }, {
      status = "WATCH", buyable = false, quantity = 200, entryTotal = 6220000,
      stressProfit = -960000, reasons = { "stress_profit_below_buffer" },
    })
    assert.equal("Won't buy", d.verdictLabel.text)
    assert.same({ GC.Theme.color.red[1], GC.Theme.color.red[2], GC.Theme.color.red[3] },
      d.verdictLabel.colors[#d.verdictLabel.colors])
    -- The loss IS the answer here, in the same slot the profit used.
    assert.equal("-96g", d.verdictAmount.text)
    assert.is_true(d.verdictAmount.shown)
    assert.is_true(d.verdictAmountNote.shown) -- the caption goes with whatever the figure is
  end)

  -- The owner's own screenshot: a HOT lot at -81%, refused because the value cannot be trusted.
  -- Printing "-1,240g" there would invent precision out of the very number being refused, and a
  -- bare "—" would read as a value that failed to load. The words go in the figure's slot, at
  -- the figure's weight.
  it("says it cannot price the lot instead of inventing a figure it has just refused", function()
    local _, stamp = load()
    local d = fakeDialog({
      verdictLabel = fakeVerdictLabel(),
      verdictAmount = fakeVerdictAmount(),
      verdictAmountNote = fakeVerdictAmountNote(),
      heroText = fakeHeroText(),
    })
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, {
      status = "WATCH", buyable = false, quantity = 200, entryTotal = 6220000,
      stressProfit = -1240000, reasons = { "price_history_sparse" },
    })

    assert.is_false(d.verdictAmount.shown)
    assert.is_true(d.heroText.shown)
    assert.equal("Can't price this", d.heroText.text)
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

  -- Caps fixes 2b. A cap decision reached this panel with no entryTotal, so UNIT and TOTAL
  -- read "—" on a buy about to spend real gold; a commodity cap then led with its saving under
  -- the cap as a green "+" over the "worst case, selling all back" caption, and a realm cap said
  -- "Can't price this" over a lot priced to the copper. The panel now says what the player
  -- pays, per unit and in total, beside the price they set -- and invents no profit.
  local function recorder()
    local w = { text = "", shown = nil }
    function w:SetText(t) self.text = t end
    function w:SetTextColor() end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    return w
  end

  local function factLabels(d)
    local labels = {}
    for i = 1, #d.factRows do labels[#labels + 1] = d.factRows[i].label.text end
    return labels
  end

  local function capDialog()
    return fakeDialog({
      verdictLabel = fakeVerdictLabel(), verdictAmount = fakeVerdictAmount(),
      verdictAmountNote = recorder(), heroText = fakeHeroText(),
      factRows = fakeFactRows(), unitPriceText = recorder(), totalCostText = recorder(),
      profitText = recorder(),
    })
  end

  it("prices a commodity cap buy in the player's own terms", function()
    local GC, stamp = load()
    local d = capDialog()
    setUpvalue(stamp, "dialog", d)

    -- 10 x 100g + 10 x 190g under a 200g cap: 2900g for 20.
    stamp({ itemID = 42, isCommodity = true, cap = 2000000 }, {
      status = "SAFE", buyable = true, cap = true, quantity = 20, entryTotal = 29000000,
      entryUnitDisplay = 1450000, unit = 1000000, capUnit = 2000000,
    })

    assert.equal(GC.Util.FormatMoney(1450000), d.unitPriceText.text)
    assert.equal(GC.Util.FormatMoney(29000000), d.totalCostText.text)
    assert.equal("At your price", d.verdictLabel.text)
    assert.equal(GC.Util.FormatMoney(1450000), d.verdictAmount.text) -- no "+", no saving-as-profit
    assert.is_true(d.verdictAmount.shown)
    assert.is_false(d.heroText.shown)
    assert.equal("—", d.profitText.text)
    local labels = factLabels(d)
    assert.equal("You pay", labels[1])
    assert.equal("Your price", labels[2])
    assert.equal(GC.Util.FormatMoney(2000000), d.factRows[2].value.text)
    -- The caption names the player's price; it says nothing about selling anything back.
    assert.is_truthy(d.verdictAmountNote.text:find(GC.Util.FormatMoney(2000000), 1, true))
    assert.is_nil(d.verdictAmountNote.text:find("sell", 1, true))
  end)

  it("prices a realm cap lot instead of saying it cannot", function()
    local GC, stamp = load()
    local d = capDialog()
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42, isCommodity = false, cap = 1000000 }, {
      status = "WATCH", cap = true, quantity = 1, entryTotal = 800000, entryUnitDisplay = 800000,
      unit = 800000, capUnit = 1000000,
      candidate = { auctionID = 9, buyout = 800000, quantity = 1, itemLevel = 615 },
    })

    assert.equal(GC.Util.FormatMoney(800000), d.unitPriceText.text)
    assert.equal(GC.Util.FormatMoney(800000), d.totalCostText.text)
    assert.equal("At your price", d.verdictLabel.text)
    assert.is_false(d.heroText.shown)
    assert.equal(GC.Util.FormatMoney(800000), d.verdictAmount.text)
    assert.equal("Your price", factLabels(d)[2])
  end)

  -- A Check only the wallet limit refused (owner report 2026-09-24): the pane says the buy needs
  -- gold and how much, not "Won't buy", and never "can't price this" over a buy it priced.
  it("says how much gold a buy only the wallet limit refused needs", function()
    local GC, stamp = load()
    local d = capDialog()
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42, isCommodity = true }, {
      status = "AVOID", buyable = false, reasons = { "capital_limit" }, needsGold = 200000000,
      quantity = 200, entryTotal = 200000000, entryUnitDisplay = 1000000, stressProfit = 370000000,
    })

    assert.equal("Needs gold", d.verdictLabel.text)
    assert.equal(GC.Util.FormatMoney(200000000), d.verdictAmount.text)
    assert.is_true(d.verdictAmount.shown)
    assert.is_false(d.heroText.shown)
    assert.equal(GC.CheckVerdict.TONE_SENTENCE.gold, d.verdictHead.text)
    assert.equal("You would pay", factLabels(d)[1])
  end)

  -- Check panel v3 replaced the ENTRY AVG / STRESS EXIT plaques (two numbers the evidence grid
  -- already carried, in a slot that went blank on every SUSPECT deal) with four facts chosen to
  -- explain THIS verdict. A meter is drawn only where CheckVerdict handed one out -- a bar with
  -- no honest ceiling is decoration competing with the figure above it.
  it("backs the verdict with four facts, metering only where a real scale exists", function()
    local _, stamp = load()
    setUpvalue(stamp, "marketForDecision", function()
      return { marketValue = 3040000, soldPerDay = 412, sellThroughBps = 8800,
        liquidityConfidence = 90, listings = 17 }
    end)
    local d = fakeDialog({ factRows = fakeFactRows() })
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, {
      status = "WATCH", buyable = false, quantity = 200, entryTotal = 6220000,
      stressProfit = -960000, reasons = { "stress_profit_below_buffer" },
    })

    -- What you pay against what you get back, on one shared ceiling: the comparison is the
    -- whole point of a profit refusal, so both carry a bar.
    assert.equal("You would pay", d.factRows[1].label.text)
    assert.equal("622g", d.factRows[1].value.text)
    assert.is_true(d.factRows[1].meter.shown)
    assert.is_false(d.factRows[1].leader.shown)
    assert.equal("You would get", d.factRows[2].label.text)
    assert.equal("526g", d.factRows[2].value.text)
    assert.is_true(d.factRows[2].meter.shown)
    -- Sell-through is already a percentage, so it meters against the engine's own 70% gate.
    assert.equal("Sell-through", d.factRows[3].label.text)
    assert.equal("88%", d.factRows[3].value.text)
    assert.is_true(d.factRows[3].meter.shown)
  end)

  -- A liquidity refusal is about TIME, and a seller count has no ceiling of its own -- so the
  -- gold tied up gets the leader line, not a bar drawn against a number nobody chose.
  it("gives a figure with no natural ceiling a leader line instead of a bar", function()
    local _, stamp = load()
    setUpvalue(stamp, "marketForDecision", function()
      return { marketValue = 3040000, soldPerDay = 3, sellThroughBps = 4100,
        liquidityConfidence = 90, listings = 17 }
    end)
    local d = fakeDialog({ factRows = fakeFactRows() })
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42 }, {
      status = "WATCH", buyable = false, quantity = 200, entryTotal = 6220000,
      stressProfit = 184000, reasons = { "velocity_too_low" },
    })

    assert.equal("Gold tied up", d.factRows[3].label.text)
    assert.is_false(d.factRows[3].meter.shown)
    assert.is_true(d.factRows[3].leader.shown)
    -- The sign is the point on this one, unlike what you PAY.
    assert.equal("If it clears", d.factRows[4].label.text)
    assert.equal("+18g40s", d.factRows[4].value.text)
  end)

  -- A refusal under a HOT board tier is the window arguing with itself: the tier came from the
  -- imported snapshot, the verdict from the live book. The reconciliation block is stacked only
  -- when the two actually disagree -- a WATCH tier next to "won't buy" is them agreeing.
  it("stacks the reconciliation block only when the board's tier contradicts the verdict", function()
    local _, stamp = load()
    local shapes = {}
    local d = fakeDialog({
      reconcileText = textSink(),
      layoutBlocks = function(shape) shapes[#shapes + 1] = shape end,
    })
    setUpvalue(stamp, "dialog", d)

    stamp({ itemID = 42, tier = "HOT" }, {
      status = "WATCH", buyable = false, quantity = 0, reasons = { "price_history_sparse" },
    })
    assert.is_true(shapes[#shapes].reconcile)
    assert.is_false(shapes[#shapes].actionable) -- and nothing to buy, so no quantity block

    stamp({ itemID = 42, tier = "WATCH" }, {
      status = "WATCH", buyable = false, quantity = 0, reasons = { "price_history_sparse" },
    })
    assert.is_false(shapes[#shapes].reconcile)

    stamp({ itemID = 42, tier = "HOT" }, {
      status = "SAFE", buyable = true, quantity = 3, entryTotal = 4530000,
      stressProfit = 1200000, reasons = {},
    })
    assert.is_false(shapes[#shapes].reconcile) -- the board and the verdict agree
    assert.is_true(shapes[#shapes].actionable)
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

    -- Check panel v3: the quantity control moved into its own block frame (qtyBlock), which is
    -- what lets layoutBlocks drop it entirely on a refusal. It still has to be built -- and
    -- therefore stacked -- above the toggle and the rows the toggle hides.
    it("keeps Quantity and its quick-fill row above the Details toggle, not behind it", function()
      local text = source()
      local qtyPos = assert(text:find("local qtyBox = makeQtyEditBox(qtyBlock,", 1, true))
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

    -- Check panel v3: the budgets are no longer two constants. layoutBlocks writes
    -- d.fixedHeightClosed/Open from the blocks THIS verdict actually shows, and the DG pair is
    -- only the construction-time seed -- a refusal with no quantity block is 50px shorter than
    -- the old single worst case, which is what let the toggle open inside the docked drawer at
    -- all. What must not come back is recomputing geometry here: this still only picks.
    it("picks between the two measured budgets rather than recomputing geometry", function()
      local text = source()
      local body = section(text, "local function applyDetailsState(open)", "detailsToggle:SetScript(\"OnClick\"")
      assert.is_truthy(body:find(
        "d.fixedHeight = d.detailsOpen and (d.fixedHeightOpen or DG.FIXED_HEIGHT_OPEN)", 1, true))
      assert.is_truthy(body:find("(d.fixedHeightClosed or DG.FIXED_HEIGHT_CLOSED)", 1, true))
      -- The fit guard measures the same layout it is about to draw, not a worst case.
      assert.is_truthy(body:find("local openHeight = d.fixedHeightOpen or DG.FIXED_HEIGHT_OPEN", 1, true))
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
    -- In game 2026-09-23: "The profit does not clear your...", "Needs a live price check
    -- befor..." -- the Reason row was one line wide and the sentence ended in dots. It wraps
    -- now, and the rulebook's text trap applies: a wrapping FontString held to a fixed height
    -- draws nothing, so it is anchored on its top edge only and never given a height, and the
    -- transcript grows by what it measures -- the fit guard included.
    it("wraps the Reason under itself and grows the transcript to fit it", function()
      local text = source()
      local build = section(text, "local reasonLabel = Theme.Label(gridBlock", "local function layoutBlocks(shape)")
      assert.is_truthy(build:find("reasonText:SetWordWrap(true)", 1, true))
      assert.is_nil(build:find("reasonText:SetMaxLines(1)", 1, true))
      assert.is_nil(build:find("reasonText:SetHeight(", 1, true))
      assert.is_truthy(build:find('reasonText:SetPoint("TOPLEFT", reasonLabel, "TOPRIGHT"', 1, true))
      assert.is_truthy(build:find('reasonText:SetPoint("TOPRIGHT"', 1, true))
      local layout = section(text, "local function layoutBlocks(shape)", "d.layoutBlocks = layoutBlocks")
      assert.is_truthy(layout:find("d.reasonText:GetStringHeight()", 1, true))
      assert.is_truthy(layout:find("place(gridBlock, gridH,", 1, true))
      assert.is_truthy(layout:find("d.fixedHeightOpen = above + gridH", 1, true))
    end)

    it("exposes applyDetailsState on the dialog table for the resize hook to call", function()
      local text = source()
      assert.is_truthy(text:find("d.applyDetailsState = applyDetailsState", 1, true))
    end)
  end)

  it("swaps the four facts for the ten-row transcript rather than stacking both", function()
    -- A behavioural sanity check on the actual production constants (not a stand-in), reached
    -- as a direct upvalue of createDialog -- DG's own fields are referenced right in its body.
    -- The REAL pad scale (UI/Theme.lua's own T.pad), not the shrunken double the behavioural
    -- tests above use: every number in this test is a pixel budget measured against the drawer
    -- the docked auction-house tab actually gives this panel, and a 4/8/12 -> 2/4/8 substitution
    -- would quietly make each of those assertions pass on geometry nobody ships.
    local Theme = { RAIL_W = 76, pad = { xs = 4, s = 8, m = 12, l = 16 } }
    local GC = { Theme = Theme,
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
      end },
      Data = { GetItemValue = function() return {} end },
    }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
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

    -- Check panel v3: opening Details costs the DIFFERENCE between the transcript and the four
    -- facts it replaces, not the whole transcript on top of them. Reserving both at once is
    -- what made the toggle refuse to open in the docked AH drawer and then tell the player to
    -- enlarge a window with no resize handle.
    assert.equal(DG.GRID_H - DG.FACTS_H, DG.FIXED_HEIGHT_OPEN - DG.FIXED_HEIGHT_CLOSED)
    assert.is_true(DG.FIXED_HEIGHT_CLOSED > 0)
    assert.is_true(DG.GRID_H > DG.FACTS_H) -- the transcript is the longer of the two

    -- Both shapes fit the drawer the docked auction-house tab actually gives this panel. The
    -- old pair was 548 closed / 728 open against the same ceiling.
    local DOCKED_CEILING = 565
    assert.equal(446, DG.FIXED_HEIGHT_CLOSED)
    assert.equal(550, DG.FIXED_HEIGHT_OPEN)
    assert.is_true(DG.FIXED_HEIGHT_OPEN <= DOCKED_CEILING,
      ("a purchase with Details open needs %d of %d"):format(DG.FIXED_HEIGHT_OPEN, DOCKED_CEILING))
    -- A refusal drops the quantity block and gains the reconciliation line: 536.
    assert.is_true(DG.FIXED_HEIGHT_OPEN - DG.QTY_BLOCK_H + DG.RECONCILE_H <= DOCKED_CEILING)

    -- Every block is a positive height, so nothing can stack backwards over its neighbour.
    for _, field in ipairs({ "HEADER_H", "HERO_H", "RECONCILE_H", "QTY_BLOCK_H", "FACTS_H",
        "TOGGLE_BLOCK_H", "GRID_H", "STATUS_H", "CONTROLS_H" }) do
      assert.is_true(DG[field] > 0, field .. " is not a positive height")
    end
    -- The hero's own slots add up to the band that has to hold them.
    assert.equal(DG.HERO_H, Theme.pad.s + DG.HERO_KICKER_H + Theme.pad.xs + DG.HERO_FIGURE_H
      + Theme.pad.xs + DG.HERO_CAPTION_H + Theme.pad.xs + DG.HERO_SENTENCE_H + Theme.pad.s)
    -- Three columns and two gaps fill the content width exactly -- no fact row can overhang.
    assert.equal(DG.WIDTH - 2 * Theme.pad.m,
      DG.FACT_LABEL_W + Theme.pad.s + DG.FACT_METER_W + Theme.pad.s + DG.FACT_VALUE_W)
  end)
end)
