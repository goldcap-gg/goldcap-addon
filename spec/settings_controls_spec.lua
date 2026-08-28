local helper = require("spec.spec_helper")

-- Loads UI/SettingsFrame.lua standalone (like sell_widget_behavior_spec.lua loads
-- UI/SellFrame.lua) against a minimal fake Theme -- this spec is about the controls
-- (pill toggle / segmented duration / slider thumb), not the panel layout Task 4 already
-- covers via loadorder_spec.lua's real-Theme construction pass.
describe("Settings controls", function()
  local GC
  local refreshRailActiveCalls

  -- Same recording double shape as soldframe_spec.lua/sell_widget_behavior_spec.lua's own
  -- region() -- `.points`/`.scripts`/`.variant`/`.label` are bookkeeping the double alone
  -- defines; production code never reads them back (ui_widget_field_spec.lua's DOUBLE_ONLY
  -- guard covers the same rule for SoldFrame/SellFrame).
  local function region(kind, parent)
    local r = { __frame = true, kind = kind, parent = parent, shown = true, points = {},
                scripts = {}, children = {} }
    if parent then parent.children[#parent.children + 1] = r end
    function r:SetPoint(point, relative, relativePoint, x, y)
      self.points[#self.points + 1] = { point, relative, relativePoint, x, y }
    end
    function r:ClearAllPoints() self.points = {} end
    function r:SetAllPoints(rel) self.points[#self.points + 1] = { "ALL", rel } end
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width or 0 end
    function r:GetHeight() return self.height or 0 end
    function r:SetJustifyH(j) self.justify = j end
    function r:SetWordWrap(v) self.wordWrap = v end
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue or "" end
    function r:SetLabel(t) self.label = t end
    function r:SetVariant(v) self.variant = v end
    function r:SetTextColor(...) self.colorValue = { ... } end
    function r:SetColorTexture(...) self.colorTexture = { ... } end
    function r:SetTexture(f) self.texture = f end
    function r:SetTexCoord() end
    function r:SetTextureSliceMargins(...) self.sliceMargins = { ... } end
    function r:SetVertexColor(...) self.vertexColor = { ... } end
    -- M10: the pill toggle's hover wash is a HIGHLIGHT-layer texture with an additive blend
    -- (Theme.Button's own hover precedent), built synchronously in makeToggle.
    function r:SetBlendMode(m) self.blendMode = m end
    function r:SetFont(...) self.font = { ... } end
    function r:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function r:SetSpacing(s) self.spacing = s end
    -- T6: mirrors the real WidgetAPI (Show/Hide dispatch OnShow/OnHide) -- SettingsFrame.lua's
    -- rail-gear wiring only runs off those events, not off build()'s own state, so a fake that
    -- flipped `.shown` without firing them would leave that wiring untestable here.
    function r:Show()
      self.shown = true
      if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function r:Hide()
      self.shown = false
      if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function r:IsShown() return self.shown end
    function r:Enable() self.enabled = true end
    function r:Disable() self.enabled = false end
    function r:EnableMouse() end
    function r:EnableKeyboard() end
    function r:SetPropagateKeyboardInput() end
    function r:SetFrameStrata(s) self.strata = s end
    -- The overlay derives its own frame LEVEL off the Sniper window's rather than pinning a
    -- strata (see UI/SettingsFrame.lua's raiseLevel), so the double has to answer both.
    function r:GetFrameLevel() return self.level or 1 end
    function r:SetFrameLevel(level) self.level = level end
    function r:SetScript(name, fn)
      -- Real CheckButtons flip their own checked state BEFORE OnClick fires (documented
      -- WidgetAPI behavior) -- production's bindCheckbox reads self:GetChecked() inside its
      -- OnClick to decide the new stored value, so the double has to replicate that ordering
      -- or a simulated click here would read the state from before the click.
      if name == "OnClick" and self.kind == "CheckButton" then
        self.scripts[name] = function(...)
          self.checked = not self.checked
          return fn(...)
        end
      else
        self.scripts[name] = fn
      end
    end
    -- M9: HookScript must CHAIN with whatever script is already stored, not replace it -- the
    -- real WidgetAPI runs every hook after the frame's own SetScript handler, so a fake that
    -- overwrote here would silently discard SettingsFrame.lua's OnShow refresh loop the moment
    -- the gear-tint HookScript (T6, below) got wired onto the same event.
    function r:HookScript(name, fn)
      local prev = self.scripts[name]
      self.scripts[name] = function(...)
        if prev then prev(...) end
        return fn(...)
      end
    end
    function r:CreateTexture(_, layer) local t = region("Texture", self); t.layer = layer; return t end
    function r:CreateFontString(_, layer) local t = region("FontString", self); t.layer = layer; return t end
    function r:RegisterForClicks() end
    function r:SetAutoFocus() end
    function r:SetMaxLetters(n) self.maxLetters = n end
    function r:ClearFocus() end
    function r:SetChecked(v) self.checked = v and true or false end
    function r:GetChecked() return self.checked end
    function r:SetCheckedTexture() end
    function r:SetOrientation(o) self.orientation = o end
    function r:SetMinMaxValues(a, b) self.min, self.max = a, b end
    function r:SetValueStep(s) self.step = s end
    function r:SetObeyStepOnDrag() end
    function r:SetThumbTexture(t) self.thumb = t end
    function r:SetValue(v) self.value = v end
    function r:GetValue() return self.value or 0 end
    return r
  end

  local function fakeTheme()
    return {
      MEDIA = "",
      FONT_MONO = "mono",
      RAIL_W = 76,
      color = { bg = { 0.05, 0.05, 0.07 }, panel = { 0.08, 0.09, 0.11 }, panelHi = { 0.10, 0.11, 0.14 },
                border = { 1, 1, 1, 0.06 }, gold = { 0.83, 0.64, 0.22 }, goldHi = { 0.91, 0.76, 0.35 },
                fg = { 0.92, 0.91, 0.89 }, fgDim = { 0.55, 0.54, 0.52 } },
      pad = { xs = 4, s = 8, m = 12, l = 16 },
      Scale = function() return 1 end,
      SetScale = function() end,
      OnRescale = function() end,
      Panel = function(parent) return region("Frame", parent) end,
      Card = function(parent) return region("Frame", parent) end,
      Label = function(parent) return region("FontString", parent) end,
      Num = function(parent) return region("FontString", parent) end,
      Button = function(parent, _, rounded) local b = region("Button", parent); b.rounded = rounded; return b end,
      SlicedTexture = function(parent, layer) local t = region("Texture", parent); t.layer = layer; return t end,
    }
  end

  -- Depth-first walk of the recording double's children, for the two lookup helpers below --
  -- production code never reads `.children`, only this spec does (same as soldframe_spec.lua's
  -- own traversal helpers).
  local function walk(node, visit)
    visit(node)
    for _, child in ipairs(node.children or {}) do walk(child, visit) end
  end

  local function segmentsOf(panel)
    local found = {}
    walk(panel, function(node)
      if node.kind == "Button" and (node.label == "12H" or node.label == "24H" or node.label == "48H") then
        found[node.label] = node
      end
    end)
    return found
  end

  -- A row's toggle is built (and appended to the card's children) immediately before its own
  -- label -- toggleRow in SettingsFrame.lua calls makeToggle() then Theme.Label() in that
  -- order -- so the label's immediately-preceding sibling is its own toggle, not the other
  -- toggle row sharing the same card parent.
  local function toggleOf(panel, rowLabelText)
    local labelNode
    walk(panel, function(node)
      if node.kind == "FontString" and node.textValue == rowLabelText then labelNode = node end
    end)
    assert.is_not_nil(labelNode, "no row label " .. tostring(rowLabelText))
    local siblings = labelNode.parent.children
    local labelIndex
    for i, child in ipairs(siblings) do
      if child == labelNode then labelIndex = i end
    end
    local toggle = siblings[labelIndex - 1]
    assert.is_not_nil(toggle and toggle.knob and toggle.checkButton,
      "no toggle immediately before row label " .. tostring(rowLabelText))
    return toggle
  end

  local function cardTitles(panel)
    local titles = {}
    walk(panel, function(node)
      if node.kind == "FontString" and node.textValue then titles[node.textValue] = true end
    end)
    return titles
  end

  local function buttonLabeled(panel, text)
    local found
    walk(panel, function(node)
      if node.kind == "Button" and node.label == text then found = node end
    end)
    return found
  end

  -- The overlay panel itself. Module-level `panel` inside SettingsFrame.lua isn't reachable
  -- from a spec any other way, and it can no longer be picked out of the window's children by
  -- its strata: it deliberately pins none now (it wins on frame LEVEL inside its parent's
  -- strata -- see raiseLevel there, and spec/sniper_window_layering_spec.lua for why). The
  -- upvalue is exact where a shape match was only ever a guess.
  local function settingsPanel()
    for i = 1, math.huge do
      local name, value = debug.getupvalue(GC.SettingsUI.Toggle, i)
      if not name then break end
      if name == "panel" then return value end
    end
    error("missing upvalue panel")
  end

  before_each(function()
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    GC = { db = { settings = { sniper = {
      hotDiscount = 0.1, hotMinSold = 5, goodDiscount = 0.05, goodMinSold = 2,
      maxCapitalShare = 0.1, minimumProfitCopper = 10000, dumpTrendPct = 40,
      spikeTrendPct = 30, wallAbsorbHours = 2, sound = true, auto = false,
      postDuration = 2,
    } } } }
    GC.Theme = fakeTheme()
    -- T7: RefreshRailActive is GC.Sniper's own export (SniperFrame.lua, right after setView) --
    -- SettingsFrame.lua's OnHide calls it to re-apply the active tab's Disable() on close. The
    -- fake just counts calls; which tab it would restore is SniperFrame.lua's own concern,
    -- covered by SniperFrame's specs, not this one.
    refreshRailActiveCalls = 0
    GC.Sniper = {
      DefaultWindowSize = function() return 720, 600 end,
      RefreshRailActive = function() refreshRailActiveCalls = refreshRailActiveCalls + 1 end,
    }
    _G.GoldCapSniperFrame = region("Frame")
    -- T6: SettingsFrame.lua reads the gear off sniperFrame.rail.gear (SniperFrame.lua's own
    -- `f.rail = rail`, ~:5153) -- a plain region("Button") already records SetVariant calls
    -- into `.variant`, same as every other fake button in this file.
    -- T7: `.buttons` mirrors Theme.Rail's own shape (rail.buttons.deals/sell/sold) -- region's
    -- Enable/Disable already record `.enabled`, same double every other fake button in this
    -- file uses.
    _G.GoldCapSniperFrame.rail = {
      gear = region("Button"),
      buttons = { deals = region("Button"), sell = region("Button"), sold = region("Button") },
    }
    helper.loadModule("UI/SettingsFrame.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame = nil
    _G.GoldCapSniperFrame = nil
  end)

  it("paints the current auction duration as the active segment and switches on click", function()
    GC.db.settings.sniper.postDuration = 2 -- 24h, see SettingsFrame.lua's storedDurationIndex
    GC.SettingsUI.Toggle()
    local seg = segmentsOf(_G.GoldCapSniperFrame)
    assert.equal("active", seg["24H"].variant)
    assert.equal("ghost", seg["12H"].variant)
    assert.equal("ghost", seg["48H"].variant)

    seg["48H"].scripts.OnClick(seg["48H"])

    assert.equal(3, GC.db.settings.sniper.postDuration) -- postDuration 3 == 48h
    assert.equal("active", seg["48H"].variant)
    assert.equal("ghost", seg["24H"].variant)
  end)

  it("toggle knob follows the checked state and a click flips the setting", function()
    GC.db.settings.sniper.sound = true
    GC.SettingsUI.Toggle()
    local t = toggleOf(_G.GoldCapSniperFrame, "Sound on HOT deal")
    assert.equal("RIGHT", t.knob.points[1][1])

    t.checkButton.scripts.OnClick(t.checkButton)

    assert.is_false(GC.db.settings.sniper.sound)
    assert.equal("LEFT", t.knob.points[1][1])
  end)

  it("gives the toggle's checkbutton an engine-driven HIGHLIGHT hover wash (M10)", function()
    GC.db.settings.sniper.sound = true
    GC.SettingsUI.Toggle()
    local t = toggleOf(_G.GoldCapSniperFrame, "Sound on HOT deal")
    local hover
    for _, child in ipairs(t.checkButton.children) do
      if child.layer == "HIGHLIGHT" then hover = child end
    end
    assert.is_not_nil(hover, "no HIGHLIGHT texture on the toggle's checkButton")
    assert.equal("badge.png", hover.texture)
    assert.equal("ADD", hover.blendMode)
    assert.same({ GC.Theme.color.gold[1], GC.Theme.color.gold[2], GC.Theme.color.gold[3], 0.18 }, hover.vertexColor)
  end)

  it("builds the five kit cards and a rounded DONE button", function()
    GC.SettingsUI.Toggle()
    local titles = cardTitles(_G.GoldCapSniperFrame)
    assert.is_true(titles["DEAL THRESHOLDS"])
    assert.is_true(titles["SAFETY"])
    assert.is_true(titles["POSTING"])
    assert.is_true(titles["AUTOMATION & ALERTS"])
    assert.is_true(titles["DISPLAY"])

    local done = buttonLabeled(_G.GoldCapSniperFrame, "DONE")
    assert.is_not_nil(done)
    assert.equal("plaque", done.rounded)
  end)

  it("offers a language picker that writes the setting and re-applies it", function()
    GC.SettingsUI.Toggle()
    local button = buttonLabeled(_G.GoldCapSniperFrame, "Game language")
    assert.is_not_nil(button)

    -- MenuUtil is the engine's own menu framework (Patch 11.0, replacing the deprecated
    -- UIDropDownMenu). Stubbed here to capture what the picker hands it.
    local captured
    _G.MenuUtil = {
      CreateRadioContextMenu = function(owner, isSelected, setSelected, ...)
        captured = { owner = owner, isSelected = isSelected, setSelected = setSelected,
                     entries = { ... } }
      end,
    }
    button.scripts.OnClick(button)

    assert.equal(13, #captured.entries) -- auto + 11 client locales + ukUA
    assert.is_true(captured.isSelected("auto"))
    captured.setSelected("ukUA")
    assert.equal("ukUA", GC.db.settings.locale)
    assert.is_true(captured.isSelected("ukUA"))
    assert.is_false(captured.isSelected("auto"))
    assert.equal("Українська", button.label)

    _G.MenuUtil = nil
  end)

  it("rail gear lights up while the overlay is open (T6)", function()
    local gear = _G.GoldCapSniperFrame.rail.gear
    GC.SettingsUI.Toggle() -- opens: build() then Show()
    assert.equal("active", gear.variant)

    GC.SettingsUI.Toggle() -- closes
    assert.equal("ghost", gear.variant)
  end)

  it("tints the gear icon along with the plate (M8)", function()
    local gear = _G.GoldCapSniperFrame.rail.gear
    gear.icon = region("Texture", gear)
    GC.SettingsUI.Toggle() -- opens
    assert.same(GC.Theme.color.goldHi, { gear.icon.vertexColor[1], gear.icon.vertexColor[2], gear.icon.vertexColor[3] })

    GC.SettingsUI.Toggle() -- closes
    assert.same(GC.Theme.color.fgDim, { gear.icon.vertexColor[1], gear.icon.vertexColor[2], gear.icon.vertexColor[3] })
  end)

  it("still runs the OnShow refresh loop after the gear-tint hook is chained onto it (M9)", function()
    -- Regression for the fake HookScript bug: it used to REPLACE the production OnShow refresh
    -- loop (SetScript) with the T6 gear-tint hook (HookScript on the same event), so a value
    -- changed while the panel was closed would never repaint on re-open. The segment control is
    -- the easiest observable: its variant only updates inside bindDurationSegments' display(),
    -- one of the refreshers that loop calls.
    GC.SettingsUI.Toggle() -- opens
    GC.SettingsUI.Toggle() -- closes
    GC.db.settings.sniper.postDuration = 1 -- 12h, changed while the panel was closed
    GC.SettingsUI.Toggle() -- re-opens: OnShow must still run the refresh loop
    local seg = segmentsOf(_G.GoldCapSniperFrame)
    assert.equal("active", seg["12H"].variant)
    assert.equal("ghost", seg["24H"].variant)
    assert.equal("ghost", seg["48H"].variant)
  end)

  it("Hide() before the panel is ever built is a no-op (T7)", function()
    assert.has_no.errors(function() GC.SettingsUI.Hide() end)
  end)

  it("enables all three rail tab buttons while open, so a rail click can still land (T7)", function()
    local buttons = _G.GoldCapSniperFrame.rail.buttons
    GC.SettingsUI.Toggle() -- opens
    assert.is_true(buttons.deals.enabled)
    assert.is_true(buttons.sell.enabled)
    assert.is_true(buttons.sold.enabled)
  end)

  it("Hide() hides the panel, un-tints the gear, and restores the active rail tab (T7)", function()
    local gear = _G.GoldCapSniperFrame.rail.gear
    GC.SettingsUI.Toggle() -- opens
    assert.equal("active", gear.variant)
    -- build()'s own initial panel:Hide() (SettingsFrame.lua's C2 fix) already fired OnHide once
    -- before the panel was ever shown -- reset the counter so this only measures the explicit
    -- Hide() call below.
    refreshRailActiveCalls = 0

    GC.SettingsUI.Hide()

    assert.is_false(settingsPanel():IsShown())
    assert.equal("ghost", gear.variant)
    assert.equal(1, refreshRailActiveCalls)
  end)
end)
