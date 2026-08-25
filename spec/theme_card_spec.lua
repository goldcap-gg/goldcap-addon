local helper = require("spec.spec_helper")

-- Real Theme.lua against stubbed frames, same option-(a) approach as
-- theme_button_contract_spec.lua: exercise the ACTUAL widget, no fakes-of-fakes.
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
  function f:Enable() self.enabled = true; if self.scripts.OnEnable then self.scripts.OnEnable(self) end end
  function f:Disable() self.enabled = false; if self.scripts.OnDisable then self.scripts.OnDisable(self) end end
  function f:SetJustifyH(v) self.justify = v end
  function f:SetWordWrap(v) self.wordWrap = v end
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

describe("Theme.Card / Theme.Glow", function()
  local GC

  before_each(function()
    GC = {}
    _G.CreateFrame = function() return stubFrame() end
    helper.loadModule("UI/Theme.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame = nil
  end)

  it("builds a card from the sliced rounded textures, panel-tinted by default", function()
    local card = GC.Theme.Card(stubFrame())
    assert.equal(GC.Theme.MEDIA .. "card.png", card.bg.textureFile)
    assert.equal(GC.Theme.MEDIA .. "ring.png", card.ring.textureFile)
    assert.same({ 24, 24, 24, 24 }, card.bg.slice)
    assert.same({ 24, 24, 24, 24 }, card.ring.slice)
    -- default tints: panel fill, border ring (alpha carried through)
    local p, b = GC.Theme.color.panel, GC.Theme.color.border
    assert.same({ p[1], p[2], p[3], 1 }, card.bg.vertex)
    assert.same({ b[1], b[2], b[3], b[4] }, card.ring.vertex)
  end)

  it("builds a small card from the plaque textures with PLAQUE_SLICE margins", function()
    local card = GC.Theme.Card(stubFrame(), nil, nil, true)
    assert.equal(GC.Theme.MEDIA .. "plaque.png", card.bg.textureFile)
    assert.equal(GC.Theme.MEDIA .. "plaque_ring.png", card.ring.textureFile)
    assert.same({ 12, 12, 12, 12 }, card.bg.slice)
    assert.same({ 12, 12, 12, 12 }, card.ring.slice)
  end)

  it("SetTint recolors fill and ring independently", function()
    local card = GC.Theme.Card(stubFrame())
    local gold = GC.Theme.color.gold
    card:SetTint({ gold[1], gold[2], gold[3], 0.13 }, nil)
    assert.same({ gold[1], gold[2], gold[3], 0.13 }, card.bg.vertex)
    -- ring untouched by a nil arg
    local b = GC.Theme.color.border
    assert.same({ b[1], b[2], b[3], b[4] }, card.ring.vertex)
  end)

  it("Glow is an additive halo hung outside the parent's rect", function()
    local parent = stubFrame()
    local glow = GC.Theme.Glow(parent, { 1, 1, 1, 0.14 })
    assert.equal(GC.Theme.MEDIA .. "glow.png", glow.textureFile)
    assert.equal("ADD", glow.blend)
    assert.same({ 1, 1, 1, 0.14 }, glow.vertex)
    -- two SetPoint calls: TOPLEFT -inset,+inset and BOTTOMRIGHT +inset,-inset
    assert.equal(2, #glow.points)
    assert.same({ "TOPLEFT", -14, 14 }, glow.points[1])
    assert.same({ "BOTTOMRIGHT", 14, -14 }, glow.points[2])
  end)

  it("SlicedTexture creates a texture with the given file and margins", function()
    local parent = stubFrame()
    local tx = GC.Theme.SlicedTexture(parent, "BACKGROUND", GC.Theme.MEDIA .. "card_right.png", {1, 1, 1, 0.5}, 24)
    assert.equal(GC.Theme.MEDIA .. "card_right.png", tx.textureFile)
    assert.same({ 24, 24, 24, 24 }, tx.slice)
    assert.same({ 1, 1, 1, 0.5 }, tx.vertex)
  end)
end)
