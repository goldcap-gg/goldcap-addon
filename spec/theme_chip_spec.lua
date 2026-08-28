local helper = require("spec.spec_helper")

-- Task 2 restyle (check panel v2): T.Chip went from a solid dark plaque + colored underline to
-- a tinted pill built on the same sliced-texture kit as T.Card/T.Button's rounded variants.
-- Real Theme.lua against stubbed frames, same option-(a) approach as theme_button_contract_spec
-- and theme_card_spec: exercise the ACTUAL widget, no fakes-of-fakes.
local function stubFrame()
  local f = { points = {}, scripts = {} }
  function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function f:ClearAllPoints() self.points = {} end
  function f:SetSize(w, h) self.width, self.height = w, h end
  function f:SetWidth(w) self.width = w end
  function f:SetHeight(h) self.height = h end
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:RegisterForClicks(kind) self.clicks = kind end
  function f:EnableMouse(enabled) self.mouseEnabled = enabled end
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
  return f
end

describe("Theme.Chip (tier pill)", function()
  local GC

  before_each(function()
    GC = {}
    _G.CreateFrame = function() return stubFrame() end
    helper.loadModule("UI/Theme.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame = nil
  end)

  it("builds a 20px-tall pill from badge.png (BADGE_SLICE margins, no ring)", function()
    local chip = GC.Theme.Chip(stubFrame())
    assert.equal(20, chip.height)
    assert.equal(GC.Theme.MEDIA .. "badge.png", chip.bg.textureFile)
    assert.same({ 6, 6, 6, 6 }, chip.bg.slice)
    assert.is_nil(chip.ring) -- badge.png has no ring texture, unlike T.Card's card.png/plaque.png
  end)

  it("no longer builds an underline -- nothing in the addon reads .underline off a chip", function()
    local chip = GC.Theme.Chip(stubFrame())
    assert.is_nil(chip.underline)
  end)

  it("SetLabel tints the text with the given color and keeps the .label call signature", function()
    local chip = GC.Theme.Chip(stubFrame())
    local hot = { 1, 0.35, 0.15 }
    chip:SetLabel("HOT", hot)
    assert.equal("HOT", chip.text.rawText)
    assert.same({ hot[1], hot[2], hot[3], 1 }, chip.text.color)
  end)

  it("SetLabel tints the pill's fill at alpha 0.12 via SetVertexColor, not SetColorTexture", function()
    local chip = GC.Theme.Chip(stubFrame())
    local hot = { 1, 0.35, 0.15 }
    chip:SetLabel("HOT", hot)
    assert.same({ hot[1], hot[2], hot[3], 0.12 }, chip.bg.vertex)
    assert.is_nil(chip.bg.colorTexture) -- recolored via vertex color only, the file art intact
  end)

  it("SetLabel with no colorTable falls back to Theme.color.fg", function()
    local chip = GC.Theme.Chip(stubFrame())
    chip:SetLabel("WATCH")
    local fg = GC.Theme.color.fg
    assert.same({ fg[1], fg[2], fg[3], 1 }, chip.text.color)
    assert.same({ fg[1], fg[2], fg[3], 0.12 }, chip.bg.vertex)
  end)
end)
