local helper = require("spec.spec_helper")

-- Loads UI/SettingsFrame.lua standalone (like sell_widget_behavior_spec.lua loads
-- UI/SellFrame.lua) against a minimal fake Theme -- this spec is about the controls
-- (pill toggle / segmented duration / slider thumb), not the panel layout Task 4 already
-- covers via loadorder_spec.lua's real-Theme construction pass.
describe("Settings controls", function()
  local GC

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
    function r:SetFont(...) self.font = { ... } end
    function r:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function r:SetSpacing(s) self.spacing = s end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:Enable() self.enabled = true end
    function r:Disable() self.enabled = false end
    function r:EnableMouse() end
    function r:EnableKeyboard() end
    function r:SetPropagateKeyboardInput() end
    function r:SetFrameStrata(s) self.strata = s end
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
    function r:HookScript(name, fn) self.scripts[name] = fn end
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

  before_each(function()
    _G.CreateFrame = function(kind, _, parent) return region(kind, parent) end
    GC = { db = { settings = { sniper = {
      hotDiscount = 0.1, hotMinSold = 5, goodDiscount = 0.05, goodMinSold = 2,
      maxCapitalShare = 0.1, minimumProfitCopper = 10000, dumpTrendPct = 40,
      spikeTrendPct = 30, wallAbsorbHours = 2, sound = true, auto = false,
      postDuration = 2,
    } } } }
    GC.Theme = fakeTheme()
    GC.Sniper = { DefaultWindowSize = function() return 720, 520 end }
    _G.GoldCapSniperFrame = region("Frame")
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
end)
