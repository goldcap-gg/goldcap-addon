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
    -- The real WidgetAPI fires OnEditFocusLost synchronously from ClearFocus, and this whole
    -- screen is built on that ordering: Enter and Escape both clear focus, and the commit lives
    -- in the focus-lost script (SettingsFrame.lua's bindNumberField). A fake that just dropped
    -- a flag would let Escape look like it abandoned an edit that production would have saved.
    function r:ClearFocus()
      self.focused = false
      if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
    end
    function r:SetFocus()
      self.focused = true
      if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end
    end
    function r:HasFocus() return self.focused == true end
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
      -- Every numeric field/toggle wires a hover explanation through this -- the double just
      -- has to hand back something SOMETHING can call, not pick a real side (that geometry is
      -- theme_tooltip_anchor_spec.lua's job against the real Theme.lua).
      TooltipAnchor = function() return "ANCHOR_RIGHT" end,
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

  -- The card frame itself, found via its own title FontString's parent -- both left cards now
  -- carry a same-labeled DEFAULTS button, so a test that means ONE card's button needs the
  -- card handle to scope the lookup rather than buttonLabeled's whole-panel walk.
  local function cardByTitle(panel, titleText)
    local found
    walk(panel, function(node)
      if node.kind == "FontString" and node.textValue == titleText then found = node.parent end
    end)
    assert.is_not_nil(found, "no card titled " .. tostring(titleText))
    return found
  end

  local function buttonIn(cardFrame, text)
    for _, child in ipairs(cardFrame.children) do
      if child.kind == "Button" and child.label == text then return child end
    end
    return nil
  end

  -- A numeric field's editbox: fieldRow builds the box immediately before its own label (same
  -- construction order toggleOf's own comment describes for toggleRow), so the label's
  -- immediately-preceding sibling is its field box, carrying `.editBox` per makeEditBox.
  local function fieldOf(panel, rowLabelText)
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
    local box = siblings[labelIndex - 1]
    assert.is_not_nil(box and box.editBox, "no field box immediately before row label " .. tostring(rowLabelText))
    return box
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
    -- Any-method-is-a-no-op stub: the hover explanation wiring (attachExplanation) calls
    -- GameTooltip:SetOwner/AddLine/Show, none of which any test here asserts on -- the content
    -- those calls build is Theme.TooltipAnchor's/GC.DEFAULTS' concern, already covered where
    -- it lives (theme_tooltip_anchor_spec.lua, this file's DEFAULTS-button tests below).
    _G.GameTooltip = setmetatable({}, { __index = function() return function() end end })
    GC = { db = { settings = { sniper = {
      maxCapitalShare = 0.1, minimumProfitCopper = 10000, minimumRoi = 0.15,
      dumpTrendPct = 40, spikeTrendPct = 30, wallAbsorbHours = 2, sound = true, auto = false,
      postDuration = 2,
    } } } }
    -- Read by defaultLine/boolDefaultLine (the tooltip's line 3) and by each left card's own
    -- DEFAULTS button -- deliberately different from the "current value" fixture above so a
    -- test can tell a freshly-reset field apart from one that merely never changed.
    GC.DEFAULTS = { settings = { sniper = {
      maxCapitalShare = 0.05, minimumProfitCopper = 50000, minimumRoi = 0.10,
      dumpTrendPct = 10, spikeTrendPct = 30, wallAbsorbHours = 2, sound = true, auto = false,
      overcut = true, postDuration = 2,
    } } }
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
    _G.GameTooltip = nil
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
    local t = toggleOf(_G.GoldCapSniperFrame, "Sound on SAFE deal")
    assert.equal("RIGHT", t.knob.points[1][1])

    t.checkButton.scripts.OnClick(t.checkButton)

    assert.is_false(GC.db.settings.sniper.sound)
    assert.equal("LEFT", t.knob.points[1][1])
  end)

  it("gives the toggle's checkbutton an engine-driven HIGHLIGHT hover wash (M10)", function()
    GC.db.settings.sniper.sound = true
    GC.SettingsUI.Toggle()
    local t = toggleOf(_G.GoldCapSniperFrame, "Sound on SAFE deal")
    local hover
    for _, child in ipairs(t.checkButton.children) do
      if child.layer == "HIGHLIGHT" then hover = child end
    end
    assert.is_not_nil(hover, "no HIGHLIGHT texture on the toggle's checkButton")
    assert.equal("badge.png", hover.texture)
    assert.equal("ADD", hover.blendMode)
    assert.same({ GC.Theme.color.gold[1], GC.Theme.color.gold[2], GC.Theme.color.gold[3], 0.18 }, hover.vertexColor)
  end)

  it("builds the five kit cards (WHAT COUNTS AS A DEAL/BRAKES replacing DEAL THRESHOLDS/SAFETY) and a rounded DONE button", function()
    GC.SettingsUI.Toggle()
    local titles = cardTitles(_G.GoldCapSniperFrame)
    assert.is_true(titles["WHAT COUNTS AS A DEAL"])
    assert.is_true(titles["BRAKES"])
    assert.is_true(titles["POSTING"])
    assert.is_true(titles["AUTOMATION & ALERTS"])
    assert.is_true(titles["DISPLAY"])
    assert.is_nil(titles["DEAL THRESHOLDS"])
    assert.is_nil(titles["SAFETY"])

    local done = buttonLabeled(_G.GoldCapSniperFrame, "DONE")
    assert.is_not_nil(done)
    assert.equal("plaque", done.rounded)
  end)

  it("drops the HOT/GOOD tier fields from the UI entirely", function()
    GC.SettingsUI.Toggle()
    local labels = {}
    walk(_G.GoldCapSniperFrame, function(node)
      if node.kind == "FontString" and node.textValue then labels[node.textValue] = true end
    end)
    assert.is_nil(labels["HOT — min discount %"])
    assert.is_nil(labels["HOT — min sold/day"])
    assert.is_nil(labels["GOOD — min discount %"])
    assert.is_nil(labels["GOOD — min sold/day"])
  end)

  it("Min profit/Min return/Max wallet live on WHAT COUNTS AS A DEAL, and the brakes on BRAKES", function()
    GC.SettingsUI.Toggle()
    local whatCounts = cardByTitle(_G.GoldCapSniperFrame, "WHAT COUNTS AS A DEAL")
    local brakes = cardByTitle(_G.GoldCapSniperFrame, "BRAKES")
    assert.is_not_nil(fieldOf(whatCounts, "Min profit per buy (gold)"))
    assert.is_not_nil(fieldOf(whatCounts, "Min return per buy %"))
    assert.is_not_nil(fieldOf(whatCounts, "Max wallet per buy %"))
    assert.is_not_nil(fieldOf(brakes, "Dump-trend cap %"))
    assert.is_not_nil(fieldOf(brakes, "Spike-trend threshold %"))
    assert.is_not_nil(fieldOf(brakes, "Wall absorb window (hours)"))
  end)

  it("minimumRoi field round-trips UI percent 10..200 to a stored fraction 0.10..2.00, clamped at both ends", function()
    GC.db.settings.sniper.minimumRoi = 0.15
    GC.SettingsUI.Toggle()
    local box = fieldOf(_G.GoldCapSniperFrame, "Min return per buy %")
    assert.equal("15", box.editBox:GetText())

    box.editBox:SetText("55")
    box.editBox.scripts.OnEditFocusLost(box.editBox)
    assert.equal(0.55, GC.db.settings.sniper.minimumRoi)
    assert.equal("55", box.editBox:GetText())

    -- Below Core/SniperDecision.lua's normalizeConfig floor of 0.10 (10%) -- the box must not
    -- accept anything that floor would just silently re-clamp back up.
    box.editBox:SetText("1")
    box.editBox.scripts.OnEditFocusLost(box.editBox)
    assert.equal(0.10, GC.db.settings.sniper.minimumRoi)

    box.editBox:SetText("500")
    box.editBox.scripts.OnEditFocusLost(box.editBox)
    assert.equal(2.00, GC.db.settings.sniper.minimumRoi)
  end)

  -- Escape is how a player backs out of a field -- and it committed instead. Its handler clears
  -- focus, clearing focus is what fires the commit, so a number typed and then abandoned was
  -- saved anyway (clamped to the field's range, which is how "999" became a real 200% setting).
  it("Escape abandons a half-typed number instead of saving it", function()
    GC.db.settings.sniper.minimumRoi = 0.15
    GC.SettingsUI.Toggle()
    local box = fieldOf(_G.GoldCapSniperFrame, "Min return per buy %")
    box.editBox:SetFocus()
    box.editBox:SetText("999")

    box.editBox.scripts.OnEscapePressed(box.editBox)

    assert.equal(0.15, GC.db.settings.sniper.minimumRoi)
    assert.equal("15", box.editBox:GetText()) -- and the box shows what is actually stored
    assert.is_false(box.editBox:HasFocus())
  end)

  -- The gold wash that marks the focused field was left painted on every box the player had
  -- ever typed in: makeEditBox wires the tint off on focus loss, and bindNumberField's own
  -- focus-lost script replaces that handler wholesale.
  it("drops the focus tint when the field loses focus", function()
    GC.SettingsUI.Toggle()
    local box = fieldOf(_G.GoldCapSniperFrame, "Min return per buy %")
    -- The rounded fill editBoxBg recolors -- the box's first child, built before its editbox.
    local fill = box.children[1]
    box.editBox:SetFocus()
    assert.same({ 0.83, 0.64, 0.22, 0.25 }, fill.vertexColor) -- gold wash, fakeTheme's palette

    box.editBox:ClearFocus()

    assert.same({ 0.05, 0.05, 0.07, 1 }, fill.vertexColor)
  end)

  it("a card's DEFAULTS button resets only that card's own fields to GC.DEFAULTS", function()
    GC.db.settings.sniper.minimumProfitCopper = 999999
    GC.db.settings.sniper.minimumRoi = 1.5
    GC.db.settings.sniper.maxCapitalShare = 0.19
    GC.db.settings.sniper.dumpTrendPct = 77 -- BRAKES field -- must NOT move
    GC.SettingsUI.Toggle()

    local whatCounts = cardByTitle(_G.GoldCapSniperFrame, "WHAT COUNTS AS A DEAL")
    local resetBtn = buttonIn(whatCounts, "DEFAULTS")
    assert.is_not_nil(resetBtn)
    resetBtn.scripts.OnClick(resetBtn)

    assert.equal(GC.DEFAULTS.settings.sniper.minimumProfitCopper, GC.db.settings.sniper.minimumProfitCopper)
    assert.equal(GC.DEFAULTS.settings.sniper.minimumRoi, GC.db.settings.sniper.minimumRoi)
    assert.equal(GC.DEFAULTS.settings.sniper.maxCapitalShare, GC.db.settings.sniper.maxCapitalShare)
    assert.equal(77, GC.db.settings.sniper.dumpTrendPct) -- untouched -- BRAKES owns its own button

    local box = fieldOf(_G.GoldCapSniperFrame, "Max wallet per buy %")
    assert.equal("5", box.editBox:GetText()) -- GC.DEFAULTS.maxCapitalShare 0.05 -> 5%
  end)

  -- The same reset RESET WINDOW performs, published so `/goldcap reset` can reach it (see
  -- Core/Init.lua): the button is inside the window, which is no use when the window is what
  -- has gone missing. It must work whether or not this screen was ever opened.
  it("publishes the window reset without needing the settings screen to be built", function()
    GC.db.settings.sniper.window = { point = "TOPLEFT", x = 9000, y = -9000, width = 1400, height = 1200 }

    GC.SettingsUI.ResetWindow()

    assert.is_nil(GC.db.settings.sniper.window)
    assert.same({ 720, 600 }, { _G.GoldCapSniperFrame.width, _G.GoldCapSniperFrame.height })
    assert.same({ { "CENTER" } }, _G.GoldCapSniperFrame.points)
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
