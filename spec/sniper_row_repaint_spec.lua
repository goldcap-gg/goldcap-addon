local helper = require("spec.spec_helper")

-- setRowDeal ends by building a fresh Item object, a fresh ContinueOnItemLoad closure and a
-- Theme.QualityMarkup tooltip scan for every row, on every render -- and refreshRows (which
-- calls it) runs on every browse page while a full scan streams, on every watch-loop
-- observation, on every verdict stamp, and off the 0.25s ticker. With up to WIN.ROW_CAP rows
-- that is a lot of allocation for rows whose content never actually moved. These specs prove
-- the fix skips a genuinely identical re-render while still repainting whenever anything the
-- player can see -- item, price, qty, tier, profit, verdict, pinned state, placeholder state --
-- actually changed, and that the itemID name/icon cache does not stop a real repaint.
describe("Sniper row repaint skip", function()
  local function getUpvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end
  -- A widget that counts every mutating call it receives, so a skip can be proven by the
  -- counter staying flat rather than by re-reading text that a bug could leave stale anyway.
  local function widget(calls)
    local w = {}
    function w:SetText(t) self.text = t; calls.n = calls.n + 1 end
    function w:SetTextColor() calls.n = calls.n + 1 end
    function w:SetTexture(t) self.texture = t; calls.n = calls.n + 1 end
    function w:SetLabel(label) self.label = label; calls.n = calls.n + 1 end
    -- Task 2 restyle: buildRowCell calls this once at row construction (not on every render),
    -- so it does not count toward the repaint-skip tally this suite exists to prove.
    function w:SetUppercase(on) self.uppercase = on end
    function w:SetVariant(name) self.variant = name; calls.n = calls.n + 1 end
    function w:SetColorTexture(r, g, b) self.rgb = { r, g, b }; calls.n = calls.n + 1 end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:Enable() self.enabled = true end
    function w:Disable() self.enabled = false end
    -- Fix 1 repaint spec (below): layoutRow/anchorColumns touch these on every column cell and
    -- on nameText -- no-ops, since this suite only cares whether Show/Hide/Enable/Disable ran.
    function w:SetPoint() end
    function w:ClearAllPoints() end
    function w:SetWidth() end
    return w
  end

  local function fakeRow(calls)
    local row = {
      buy = widget(calls), tierChip = widget(calls), icon = widget(calls), nameText = widget(calls),
      discountText = widget(calls), unitText = widget(calls), priceText = widget(calls),
      profitText = widget(calls), trendText = widget(calls), highlight = widget(calls),
      rail = widget(calls), pinBg = widget(calls), shown = false,
    }
    function row:Show() self.shown = true end
    function row:Hide() self.shown = false end
    function row:IsShown() return self.shown end
    function row:SetAlpha(a) self.alpha = a end
    return row
  end

  local function deal(itemID, overrides)
    local d = {
      itemID = itemID, unitPrice = 1000, qty = 5, profit = 2000, discount = 0.4,
      tier = "GOOD", action = "Check",
    }
    for k, v in pairs(overrides or {}) do d[k] = v end
    return d
  end

  local function load()
    local itemLoads = 0
    local trendValue = nil
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function(_, itemID)
      itemLoads = itemLoads + 1
      return {
        ContinueOnItemLoad = function(_, cb) cb() end, -- resolves synchronously, like a cached lookup
        GetItemIcon = function() return "icon:" .. itemID end,
        GetItemQuality = function() return nil end,
        GetItemName = function() return "Item " .. itemID end,
      }
    end }

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
        tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
          fg = { 0.92, 0.91, 0.89 }, gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } },
      },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
      end },
      Data = { GetItemValue = function() return trendValue and { trend = trendValue } or nil end },
      db = { settings = { sniper = { watchPins = {} } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local setRowDeal = getUpvalue(refreshRows, "setRowDeal")
    local verdictFor = getUpvalue(setRowDeal, "verdictFor")
    local verdicts = getUpvalue(verdictFor, "verdicts")
    -- flashRow is not reachable from clearDeals/refreshRows -- it's an upvalue of
    -- repaintToggledRow, which is itself an upvalue of the public GC.Sniper._TogglePin.
    local repaintToggledRow = getUpvalue(GC.Sniper._TogglePin, "repaintToggledRow")
    local flashRow = getUpvalue(repaintToggledRow, "flashRow")
    -- Fix 1: layoutRow is createRow's own upvalue (createRow calls it directly at the end of
    -- construction) -- reached the same "one more link in the chain" way every other upvalue
    -- above is, off createRow which is itself an upvalue of refreshRows.
    local createRow = getUpvalue(refreshRows, "createRow")
    local layoutRow = getUpvalue(createRow, "layoutRow")

    return {
      GC = GC,
      setRowDeal = setRowDeal,
      flashRow = flashRow,
      layoutRow = layoutRow,
      verdicts = verdicts,
      itemLoads = function() return itemLoads end,
      setTrend = function(v) trendValue = v end,
    }
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetCoinTextureString = nil, os.time, nil
    _G.ITEM_QUALITY_COLORS, _G.Item = nil, nil
  end)

  it("does not repaint an identical re-render, even from a different deal table", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)

    ctx.setRowDeal(row, deal(7))
    local afterFirst = calls.n
    assert.is_true(afterFirst > 0)

    -- A brand-new table with the exact same values -- streaming/MergeDeals hands refreshRows a
    -- fresh table every pass, so the skip must be a value comparison, never `deal1 == deal2`.
    ctx.setRowDeal(row, deal(7))

    assert.equal(afterFirst, calls.n)
  end)

  it("repaints when the profit changes", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)

    ctx.setRowDeal(row, deal(7, { profit = 2000 }))
    local afterFirst = calls.n
    ctx.setRowDeal(row, deal(7, { profit = 9999 }))

    assert.is_true(calls.n > afterFirst)
    assert.equal("+9999c", row.profitText.text)
  end)

  it("repaints when the unit price, quantity, or tier changes", function()
    local ctx = load()
    for _, field in ipairs({ "unitPrice", "qty", "tier" }) do
      local calls = { n = 0 }
      local row = fakeRow(calls)
      local base = deal(7)
      ctx.setRowDeal(row, base)
      local afterFirst = calls.n
      local changed = deal(7)
      changed[field] = field == "tier" and "HOT" or (changed[field] + 1)
      ctx.setRowDeal(row, changed)
      assert.is_true(calls.n > afterFirst, "expected a repaint when " .. field .. " changes")
    end
  end)

  it("repaints when a background Check's verdict changes, even though the deal itself did not", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local d = deal(7)

    ctx.setRowDeal(row, d)
    assert.equal("Check", row.buy.label) -- no verdict yet
    local afterFirst = calls.n

    -- stampVerdict's own shape: unitPrice-keyed, buyable, status, at.
    ctx.verdicts[7] = { unitPrice = d.unitPrice, at = 100, buyable = true, status = "SAFE" }
    ctx.setRowDeal(row, d) -- same deal object, same fields -- only the verdict moved

    assert.is_true(calls.n > afterFirst)
    assert.equal("Buy", row.buy.label)
  end)

  it("repaints when the item is pinned or unpinned, even though the deal itself did not change", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local d = deal(7)

    ctx.setRowDeal(row, d)
    local afterFirst = calls.n
    assert.is_nil(row.rail.rgb and row.rail.rgb[1] == ctx.GC.Theme.color.watch[1] or nil)

    ctx.GC.db.settings.sniper.watchPins = { 7 }
    ctx.setRowDeal(row, d)

    assert.is_true(calls.n > afterFirst)
    assert.same(ctx.GC.Theme.color.watch, row.rail.rgb)
  end)

  it("repaints when it becomes (or stops being) a pin placeholder", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local live = deal(7)
    ctx.setRowDeal(row, live)
    local afterFirst = calls.n

    local placeholder = deal(7, { pinPlaceholder = true })
    ctx.setRowDeal(row, placeholder)

    assert.is_true(calls.n > afterFirst)
    -- A watched-not-a-deal row has no Buy button at all (it read as a broken control when it
    -- was a disabled "Watching" ghost button) -- the double records Hide having actually been
    -- called, not just the widget's untouched default (nil).
    assert.is_false(row.buy.shown)
    local watchingSuffix = "· watching|r"
    assert.equal(watchingSuffix, row.nameText.text:sub(-#watchingSuffix))

    -- A pooled row that was a placeholder must come back with a working button once it is
    -- reassigned (or reverts) to an actual deal -- setRowDeal's non-placeholder branch re-Shows
    -- row.buy before its label logic runs.
    local afterPlaceholder = calls.n
    ctx.setRowDeal(row, deal(7))

    assert.is_true(calls.n > afterPlaceholder)
    assert.is_true(row.buy.shown)
  end)

  it("repaints when the trend read against the SAME deal object changes", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local d = deal(7)

    ctx.setRowDeal(row, d)
    assert.equal("—", row.trendText.text)
    local afterFirst = calls.n

    ctx.setTrend(-12)
    ctx.setRowDeal(row, d) -- same deal object -- only GC.Data.GetItemValue's answer moved

    assert.is_true(calls.n > afterFirst)
    assert.equal("▼12%", row.trendText.text)
  end)

  it("still shows a row that goes hidden and comes back with the exact same deal", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local d = deal(7)

    ctx.setRowDeal(row, d)
    assert.is_true(row:IsShown())

    row:Hide() -- refreshRows does this to a pooled slot that has no deal this pass
    ctx.setRowDeal(row, deal(7)) -- reassigned later, content-identical to before

    assert.is_true(row:IsShown(), "a reused row must never stay hidden just because its content repeats")
  end)

  -- Fix 1 (check-panel-deals-list, task 4): a watching row's Buy button must stay inert across
  -- ANY column re-layout, not just survive the setRowDeal call that first hid it. Opening the
  -- check panel at >= WIN.PANEL_SHIFT_MIN drives applyColumnVisibility, which re-runs layoutRow
  -- (and therefore anchorColumns) over every pooled row -- and anchorColumns unconditionally
  -- cell:Show()s every VISIBLE fixed column, "buy" included, since "buy" is a fixed column, never
  -- one of the responsive optional ones computeHidden ever drops. Before this fix that re-Show
  -- brought back an ENABLED button carrying the slot's last construction label, clickable
  -- through both its own OnClick and the row's whole-row click guard (onBuyClick has no
  -- pinPlaceholder check of its own). Needs row.cells wired up (anchorColumns reads
  -- row.cells[col.key]) -- added additively here since fakeRow above only builds named fields.
  it("keeps a watching row's Buy button hidden and disabled across a column re-layout", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    row.cells = {
      tier = row.tierChip, disc = row.discountText, unit = row.unitText,
      total = row.priceText, profit = row.profitText, trend = row.trendText, buy = row.buy,
    }

    ctx.setRowDeal(row, deal(7, {
      pinPlaceholder = true, unitPrice = 500, qty = 1, profit = 0, discount = 0,
      tier = "WATCH", action = "Check", priceUnknown = false,
    }))
    assert.is_false(row.buy.shown)

    -- Simulates applyColumnVisibility's re-layout pass over every pooled row (e.g. triggered by
    -- the check panel opening/closing at WIN.PANEL_SHIFT_MIN).
    ctx.layoutRow(row)

    assert.is_false(row.buy.shown,
      "a watching row's Buy button must stay hidden across a column re-layout")
    assert.is_false(row.buy.enabled,
      "a watching row's Buy button must stay disabled across a column re-layout")
  end)

  -- Fix 3: a pin placeholder (renderList's fabricated row for a pin that fell out of the deals
  -- list) is not a deal -- its discount/profit/qty fields are sentinel zeros kept only so
  -- callers that expect a number get one. Rendering those sentinels used to print "0%", a
  -- 0-copper profit coin, and (when a price WAS observed) the same unit price twice as a fake
  -- "unit/total" pair, since qty is always 1. Every one of those cells must say nothing instead.
  it("renders a priceUnknown pin placeholder's discount, profit and price as dashes, not zeros", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)

    ctx.setRowDeal(row, deal(7, {
      pinPlaceholder = true, unitPrice = 0, qty = 1, profit = 0, discount = 0,
      tier = "WATCH", action = "Check", priceUnknown = true,
    }))

    assert.equal("—", row.discountText.text)
    assert.equal("—", row.profitText.text)
    assert.equal("—", row.unitText.text)
    assert.equal("—", row.priceText.text)
    assert.is_false(row.buy.shown)
    local watchingSuffix = "· watching|r"
    assert.equal(watchingSuffix, row.nameText.text:sub(-#watchingSuffix))
  end)

  it("shows a pin placeholder's last-seen unit price without duplicating it as a fake total", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)

    ctx.setRowDeal(row, deal(7, {
      pinPlaceholder = true, unitPrice = 500, qty = 1, profit = 0, discount = 0,
      tier = "WATCH", action = "Check", priceUnknown = false,
    }))

    assert.equal("—", row.discountText.text)
    assert.equal("—", row.profitText.text)
    assert.equal("500c", row.unitText.text)   -- the one real number: what it costs right now
    assert.equal("—", row.priceText.text)     -- never unitPrice * qty duplicated as a fake total
  end)

  it("resolves an itemID's name/icon once and reuses it across a genuine repaint", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)

    ctx.setRowDeal(row, deal(7, { profit = 100 }))
    assert.equal(1, ctx.itemLoads())

    ctx.setRowDeal(row, deal(7, { profit = 200 })) -- genuine change -> repaints, but same itemID
    assert.equal(1, ctx.itemLoads())
  end)

  -- Task 2: the HOT-deal ping used to animate row.highlight's alpha directly, so the hover
  -- wash inherited whatever alpha the fade animation had last written to it. It now owns a
  -- dedicated row.flash texture; row.highlight is touched only by OnEnter/OnLeave.
  it("flashes the ping on the row's own flash texture, never the hover highlight", function()
    local ctx = load()
    local flashCalls, highlightCalls = {}, {}
    local row = {
      flash = {
        SetAlpha = function() table.insert(flashCalls, "SetAlpha") end,
        Show = function() table.insert(flashCalls, "Show") end,
        Hide = function() table.insert(flashCalls, "Hide") end,
      },
      highlight = {
        SetAlpha = function() table.insert(highlightCalls, "SetAlpha") end,
        Show = function() table.insert(highlightCalls, "Show") end,
        Hide = function() table.insert(highlightCalls, "Hide") end,
      },
      flashAnim = { Stop = function() end, Play = function() end },
    }

    ctx.flashRow(row)

    assert.same({ "SetAlpha", "Show" }, flashCalls)
    assert.same({}, highlightCalls)
  end)

  it("resets only the flash texture, not the hover highlight, when a pooled row's itemID changes mid-flash", function()
    local ctx = load()
    local calls = { n = 0 }
    local row = fakeRow(calls)
    local flashResets = {}
    row.flash = {
      SetAlpha = function() table.insert(flashResets, "SetAlpha") end,
      Hide = function() table.insert(flashResets, "Hide") end,
      Show = function() end,
    }
    row.flashAnim = { Stop = function() table.insert(flashResets, "Stop") end, Play = function() end }
    local highlightHideCalls = 0
    local realHighlightHide = row.highlight.Hide
    function row.highlight:Hide()
      highlightHideCalls = highlightHideCalls + 1
      realHighlightHide(self)
    end

    ctx.setRowDeal(row, deal(7))
    -- A DIFFERENT itemID lands in this same pooled slot mid-flash -- the reuse guard stops/
    -- hides/resets row.flash, and never touches row.highlight (OnEnter/OnLeave own that alone).
    ctx.setRowDeal(row, deal(9))

    assert.same({ "Stop", "Hide", "SetAlpha" }, flashResets)
    assert.equal(0, highlightHideCalls)
  end)
end)

-- Task 2 review finding: nothing above drives the REAL OnMouseDown/OnMouseUp/OnLeave closures
-- createRow wires onto a row -- the repaint tests above hand-build fake rows, and
-- watch_loop_spec.lua's "[wiring] dispatches both mouse phases..." only proves the SOURCE TEXT
-- calls the right functions by name, not that the leftPressed latch/buy gate actually behave.
-- This builds a REAL row against a REAL Theme.Button/TierMark/Num/Label (same option-(a)
-- approach as theme_button_contract_spec.lua/theme_rounded_button_spec.lua) off a recording
-- CreateFrame stub, the way loadorder_spec.lua's stubFrame records SetScript into a table, and
-- fires the actual closures captured off the result.
describe("Row click wiring (whole-row left-click acts)", function()
  -- Nearly the theme_rounded_button_spec.lua / theme_button_contract_spec.lua stub, extended
  -- with CreateAnimationGroup (createRow builds one directly on the row -- see flashAnim) and
  -- IsEnabled (the new OnMouseUp gate reads it off row.buy). shown/enabled default to true,
  -- matching a real Blizzard widget's default state -- createRow never calls Show()/Enable()
  -- on construction, it relies on that default, and a stub defaulting to false/nil would pass
  -- these tests for the wrong reason (an accidentally-hidden button "explains" a click that
  -- never fires).
  local function stubFrame()
    local f = { points = {}, scripts = {}, shown = true, enabled = true }
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() self.points = {} end
    function f:SetSize(w, h) self.width, self.height = w, h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:HookScript(name, fn) self.scripts[name] = fn end
    function f:RegisterForClicks(kind) self.clicks = kind end
    function f:EnableMouse(enabled) self.mouseEnabled = enabled end
    function f:Enable() self.enabled = true; if self.scripts.OnEnable then self.scripts.OnEnable(self) end end
    function f:Disable() self.enabled = false; if self.scripts.OnDisable then self.scripts.OnDisable(self) end end
    function f:IsEnabled() return self.enabled end
    function f:SetJustifyH(v) self.justify = v end
    function f:SetWordWrap(v) self.wordWrap = v end
    function f:SetMaxLines(n) self.maxLines = n end
    function f:SetText(text) self.rawText = text end
    function f:GetText() return self.rawText or "" end
    function f:SetTextColor(...) self.color = { ... } end
    function f:SetFont(path, size, flags) self.font = { path, size, flags } end
    function f:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function f:SetColorTexture(...) self.colorTexture = { ... } end
    function f:SetTexture(file) self.textureFile = file end
    function f:SetTextureSliceMargins(l, t, r, b) self.slice = { l, t, r, b } end
    function f:SetVertexColor(...) self.vertex = { ... } end
    function f:SetBlendMode(mode) self.blend = mode end
    function f:SetAllPoints(rel) self.allPoints = rel end
    function f:SetAlpha(a) self.alpha = a end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:CreateTexture() return stubFrame() end
    function f:CreateFontString() return stubFrame() end
    function f:CreateAnimationGroup()
      return {
        CreateAnimation = function()
          return {
            SetFromAlpha = function() end, SetToAlpha = function() end,
            SetDuration = function() end, SetSmoothing = function() end,
            SetOrder = function() end, SetTarget = function() end,
          }
        end,
        SetLooping = function() end, SetScript = function() end,
        Play = function() end, Stop = function() end, IsPlaying = function() return false end,
      }
    end
    return f
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

  local function load()
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.CreateFrame = function() return stubFrame() end
    -- Only OnLeave (GameTooltip:Hide()) is exercised below, never OnEnter's fuller GameTooltip
    -- use -- an any-method-is-a-no-op stub covers whichever of GameTooltip's methods any given
    -- scenario happens to reach, the same trick sniper_pin_feedback_spec.lua's row stubs use.
    _G.GameTooltip = setmetatable({}, { __index = function() return function() end end })

    local GC = {}
    helper.loadModule("UI/Theme.lua", GC)
    GC.AutoScan = { New = function()
      return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end }
    end }
    GC.Data = { GetItemValue = function() return nil end }
    GC.db = { settings = { sniper = { watchPins = {} } } }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/WatchSet.lua", GC) -- _TogglePin -> _RefreshWatchSet -> GC.WatchSet.Select
    helper.loadModule("UI/SniperFrame.lua", GC)

    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")

    return { GC = GC, createRow = createRow }
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetCoinTextureString = nil, os.time, nil
    _G.ITEM_QUALITY_COLORS, _G.Item = nil, nil
    _G.CreateFrame, _G.GameTooltip = nil, nil
  end)

  -- itemID 99 satisfies GC.Sniper._RowPinEvent's `not row.deal` guard for the right-click test
  -- below -- setRowDeal is never called here, so this is set directly, the way
  -- sniper_pin_feedback_spec.lua's own row stubs do.
  local function buildRow(ctx)
    local row = ctx.createRow({}, 1)
    row.deal = { itemID = 99 }
    return row
  end

  it("builds row.flash as its own texture, distinct from row.highlight", function()
    local ctx = load()
    local row = buildRow(ctx)
    assert.is_not_nil(row.flash)
    assert.is_not_nil(row.highlight)
    assert.are_not.equal(row.highlight, row.flash)
  end)

  it("fires the row action once for a left down+up that both land on the row", function()
    local ctx = load()
    local row = buildRow(ctx)
    local calls = {}
    setUpvalue(ctx.createRow, "onBuyClick", function(r) calls[#calls + 1] = r end)

    row.scripts.OnMouseDown(row, "LeftButton")
    row.scripts.OnMouseUp(row, "LeftButton")

    assert.same({ row }, calls)
  end)

  it("never fires the row action on a right-click, and still dispatches both phases to the pin handler", function()
    local ctx = load()
    local row = buildRow(ctx)
    local calls = {}
    setUpvalue(ctx.createRow, "onBuyClick", function(r) calls[#calls + 1] = r end)

    row.scripts.OnMouseDown(row, "RightButton")
    row.scripts.OnMouseUp(row, "RightButton")

    assert.same({}, calls)
    -- Proves _RowPinEvent actually received BOTH phases (down armed+toggled the latch, up saw
    -- the latch and did NOT toggle again) -- a single stray toggle would also leave one entry
    -- here, so this alone wouldn't prove two calls, but combined with the down-only/up-only
    -- latch behaviour already covered in sniper_pin_feedback_spec.lua, this is the wiring proof.
    assert.same({ 99 }, ctx.GC.db.settings.sniper.watchPins)
  end)

  it("does not fire when the left press started on the row but the cursor left before releasing", function()
    local ctx = load()
    local row = buildRow(ctx)
    local calls = {}
    setUpvalue(ctx.createRow, "onBuyClick", function(r) calls[#calls + 1] = r end)

    row.scripts.OnMouseDown(row, "LeftButton")
    row.scripts.OnLeave(row)
    row.scripts.OnMouseUp(row, "LeftButton")

    assert.same({}, calls)
  end)

  it("does not fire on a left-up with no prior left-down on this row", function()
    local ctx = load()
    local row = buildRow(ctx)
    local calls = {}
    setUpvalue(ctx.createRow, "onBuyClick", function(r) calls[#calls + 1] = r end)

    row.scripts.OnMouseUp(row, "LeftButton")

    assert.same({}, calls)
  end)

  it("does not fire when the Buy button is disabled", function()
    local ctx = load()
    local row = buildRow(ctx)
    local calls = {}
    setUpvalue(ctx.createRow, "onBuyClick", function(r) calls[#calls + 1] = r end)
    row.buy:Disable()

    row.scripts.OnMouseDown(row, "LeftButton")
    row.scripts.OnMouseUp(row, "LeftButton")

    assert.same({}, calls)
  end)

  it("does not fire when the Buy button is hidden", function()
    local ctx = load()
    local row = buildRow(ctx)
    local calls = {}
    setUpvalue(ctx.createRow, "onBuyClick", function(r) calls[#calls + 1] = r end)
    row.buy:Hide()

    row.scripts.OnMouseDown(row, "LeftButton")
    row.scripts.OnMouseUp(row, "LeftButton")

    assert.same({}, calls)
  end)
end)

-- Item 1 (addon polish batch): OnEnter pins the hovered row into `hoveredRow` so refreshRows()
-- leaves its content alone while the cursor sits over it (see sortedDeals()'s hoveredItemID
-- exclusion) -- correct while the window stays open, but the window's own OnHide never released
-- that pin. Escaping or clicking the title-bar X while a row was hovered left that pooled row
-- excluded from every future refreshRows() forever after (OnLeave, which normally clears the
-- pin, is not reliably delivered when a frame hides under a stationary cursor -- see
-- addon/AGENTS.md). Driven against a REAL createFrame()-built window via the same full-toc-load
-- recipe spec/sniper_panel_inset_spec.lua uses (`buildFrame()`), so this proves the actual
-- registered OnHide script, not a synthetic stand-in for it.
describe("Sniper window OnHide clears the hover pin", function()
  -- Same exhaustive per-spec double as spec/sniper_panel_inset_spec.lua's own stubFrame():
  -- every widget method createFrame's (and, here, createRow's) real construction path touches.
  local function stubFrame()
    local f
    f = {
      RegisterEvent = function() end,
      UnregisterEvent = function() end,
      scripts = {},
      SetScript = function(self, name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end,
      SetSize = function() end,
      SetPoint = function() end,
      SetMovable = function() end,
      EnableMouse = function() end,
      RegisterForDrag = function() end,
      Show = function() end,
      Hide = function() end,
      IsShown = function() return false end,
      SetText = function() end,
      SetTexture = function() end,
      SetTextColor = function() end,
      SetJustifyH = function() end,
      SetWidth = function() end,
      SetScrollChild = function() end,
      StartMoving = function() end,
      StopMovingOrSizing = function() end,
      CreateFontString = function() return stubFrame() end,
      CreateTexture = function() return stubFrame() end,
      TitleText = { SetText = function() end },
      EnableMouseWheel = function() end,
      SetVerticalScroll = function() end,
      GetVerticalScroll = function() return 0 end,
      GetVerticalScrollRange = function() return 0 end,
      SetWordWrap = function() end,
      SetMaxLines = function() end,
      SetSpacing = function() end,
      Enable = function() end,
      Disable = function() end,
      GetFontString = function() return nil end,
      SetResizable = function() end,
      SetResizeBounds = function() end,
      StartSizing = function() end,
      ClearAllPoints = function() end,
      GetPoint = function() return nil end,
      GetHeight = function() return 0 end,
      GetFrameLevel = function() return 1 end,
      SetFrameLevel = function() end,
      SetColorTexture = function() end,
      SetBlendMode = function() end,
      SetTextureSliceMargins = function() end,
      SetVertexColor = function() end,
      SetAllPoints = function() end,
      SetHeight = function() end,
      SetFont = function() end,
      GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
      RegisterForClicks = function() end,
      SetFrameStrata = function() end,
      GetWidth = function() return 0 end,
      HookScript = function() end,
      IsEnabled = function() return true end,
      SetAlpha = function() end,
      CreateAnimationGroup = function()
        return {
          CreateAnimation = function()
            return {
              SetFromAlpha = function() end,
              SetToAlpha = function() end,
              SetDuration = function() end,
              SetSmoothing = function() end,
              SetOrder = function() end,
              SetTarget = function() end,
            }
          end,
          SetLooping = function() end,
          SetScript = function() end,
          Play = function() end,
          Stop = function() end,
          IsPlaying = function() return false end,
        }
      end,
      EnableKeyboard = function() end,
      SetPropagateKeyboardInput = function() end,
      SetAutoFocus = function() end,
      SetMaxLetters = function() end,
      GetText = function() return "" end,
      ClearFocus = function() end,
      SetChecked = function() end,
      GetChecked = function() return false end,
      SetCheckedTexture = function() end,
      SetOrientation = function() end,
      SetMinMaxValues = function() end,
      SetValueStep = function() end,
      SetObeyStepOnDrag = function() end,
      SetThumbTexture = function() end,
      SetValue = function() end,
      GetValue = function() return 0 end,
    }
    return f
  end

  local function getUpvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  -- Builds a real GoldCap addon table via the exact same load-order recipe
  -- spec/sniper_panel_inset_spec.lua uses, then constructs the real Sniper window through
  -- GC.Sniper.Toggle() (which does `frame = frame or createFrame()`), and hands back that real
  -- frame plus GC so a spec can reach the real OnHide script off `frame.scripts.OnHide`.
  local function buildFrame()
    _G.CreateFrame = function(_, name)
      local f = stubFrame()
      if name and name ~= "" then
        _G[name] = f
      end
      return f
    end
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    _G.SlashCmdList = {}
    _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    _G.hooksecurefunc = _G.hooksecurefunc or function() end
    _G.GetTime = _G.GetTime or function() return 0 end
    _G.PlaySound = _G.PlaySound or function() end
    _G.SOUNDKIT = _G.SOUNDKIT or { MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = _G.C_Timer or { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.time = os.time
    -- Needed for setRowDeal (runs inside refreshRows) to resolve an item's name/icon, the same
    -- fake as this file's own describe("Sniper row repaint skip") load().
    _G.Item = { CreateFromItemID = function(_, itemID)
      return {
        ContinueOnItemLoad = function(_, cb) cb() end,
        GetItemIcon = function() return "icon:" .. itemID end,
        GetItemQuality = function() return nil end,
        GetItemName = function() return "Item " .. itemID end,
      }
    end }
    -- setRowDeal/OnEnter don't check anything on it in this scenario -- any-method-is-a-no-op
    -- covers whichever of GameTooltip's methods either happens to reach.
    _G.GameTooltip = setmetatable({}, { __index = function() return function() end end })

    local GC = {}
    local toc = assert(io.open("GoldCap/GoldCap.toc", "r"))
    local files = {}
    for rawLine in toc:lines() do
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^##") then
        files[#files + 1] = line
      end
    end
    toc:close()
    for _, rel in ipairs(files) do
      local chunk, err = loadfile("GoldCap/" .. rel:gsub("\\", "/"))
      assert(chunk, err)
      chunk("GoldCap", GC)
    end

    GC.Sniper.Toggle() -- constructs and shows the real window; frame = frame or createFrame()
    local frame = _G.GoldCapSniperFrame
    assert(frame, "GC.Sniper.Toggle() did not publish _G.GoldCapSniperFrame")
    assert.is_function(frame.scripts.OnHide)

    return frame, GC
  end

  local function teardown()
    _G.CreateFrame = nil
    _G.GoldCapSniperFrame = nil
    _G.UISpecialFrames = nil
    _G.SlashCmdList = nil
    _G.C_AddOns = nil
    _G.GoldCap_MarketData = nil
    _G.SLASH_GOLDCAP1 = nil
    _G.SLASH_GOLDCAP2 = nil
    _G.hooksecurefunc = nil
    _G.GetTime = nil
    _G.PlaySound = nil
    _G.SOUNDKIT = nil
    _G.C_Timer = nil
    _G.GetCoinTextureString = nil
    _G.ITEM_QUALITY_COLORS = nil
    _G.time = nil
    _G.Item = nil
    _G.GameTooltip = nil
  end

  after_each(teardown)

  it("repaints a pooled row that was hovered when the window was hidden", function()
    local frame, GC = buildFrame()
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local renderList = getUpvalue(refreshRows, "renderList")
    local sortedDeals = getUpvalue(renderList, "sortedDeals")
    local deals = getUpvalue(sortedDeals, "deals")
    local rows = getUpvalue(refreshRows, "rows")

    deals[1234] = { itemID = 1234, unitPrice = 1000, qty = 1, profit = 100, discount = 0.1, tier = "GOOD" }
    refreshRows()
    local row = rows[1]
    assert.is_not_nil(row)
    assert.are.equal(1234, row.deal.itemID)

    row.scripts.OnEnter(row) -- pins hoveredRow to this row, same as a real mouse hover

    -- The item moves on (price no longer qualifies) and a different deal takes its place --
    -- exactly the situation refreshRows() must be free to repaint this pooled row into.
    deals[1234] = nil
    deals[5678] = { itemID = 5678, unitPrice = 2000, qty = 1, profit = 200, discount = 0.2, tier = "GOOD" }

    frame.scripts.OnHide(frame) -- window closes (Escape / title-bar X) while still "hovering"

    refreshRows()

    assert.are.equal(5678, row.deal.itemID)
  end)

  it("is a no-op when no row is hovered", function()
    local frame = buildFrame()

    assert.has_no.errors(function() frame.scripts.OnHide(frame) end)
  end)
end)
