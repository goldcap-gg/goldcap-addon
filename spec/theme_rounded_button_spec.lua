local helper = require("spec.spec_helper")

-- Rounded T.Button mode (3rd arg "plaque" | "badge") and T.TierMark, against the real
-- widgets, same option-(a) approach as theme_card_spec.lua / theme_button_contract_spec.lua.
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

describe("Theme.Button rounded mode / Theme.TierMark", function()
  local GC

  before_each(function()
    GC = {}
    _G.CreateFrame = function() return stubFrame() end
    helper.loadModule("UI/Theme.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame = nil
  end)

  it("plaque mode slices bg/highlight off plaque.png and gets a plaque_ring.png ring", function()
    local T = GC.Theme
    local btn = T.Button(stubFrame(), "ghost", "plaque")
    assert.equal(T.MEDIA .. "plaque.png", btn.bg.textureFile)
    assert.same({ 12, 12, 12, 12 }, btn.bg.slice)
    assert.equal(T.MEDIA .. "plaque.png", btn.highlightTexture.textureFile)
    assert.equal(T.MEDIA .. "plaque_ring.png", btn.ring.textureFile)
    assert.same({ 12, 12, 12, 12 }, btn.ring.slice)
  end)

  it("badge mode slices bg/highlight off badge.png at BADGE_SLICE margins and has no ring", function()
    local T = GC.Theme
    local btn = T.Button(stubFrame(), "ghost", "badge")
    assert.equal(T.MEDIA .. "badge.png", btn.bg.textureFile)
    assert.same({ 6, 6, 6, 6 }, btn.bg.slice)
    assert.equal(T.MEDIA .. "badge.png", btn.highlightTexture.textureFile)
    -- too small for the ring art
    assert.is_nil(btn.ring)
  end)

  -- The Sell row's Post: a thin gold outline on the one control the row exists for. The ring
  -- art is its own 1px badge_ring.png -- plaque_ring.png's radius and 12px margins notch an
  -- 18px button -- and only a button that asks for it wears one.
  describe("badge SetRing", function()
    it("draws a ring off badge_ring.png at the badge margins, tinted as asked", function()
      local T = GC.Theme
      local btn = T.Button(stubFrame(), "ghost", "badge")
      btn:SetRing({ 0.8, 0.6, 0.2, 0.45 })
      assert.equal(T.MEDIA .. "badge_ring.png", btn.ring.textureFile)
      assert.same({ 6, 6, 6, 6 }, btn.ring.slice)
      assert.same({ 0.8, 0.6, 0.2, 0.45 }, btn.ring.vertex)
      assert.is_true(btn.ring.shown)
    end)

    it("takes the ring off again, and keeps one texture across calls for a pooled row", function()
      local btn = GC.Theme.Button(stubFrame(), "ghost", "badge")
      btn:SetRing(nil) -- never had one: nothing to do, nothing built
      assert.is_nil(btn.ring)
      btn:SetRing({ 1, 1, 1, 1 })
      local ring = btn.ring
      btn:SetRing(nil)
      assert.is_false(ring.shown)
      btn:SetRing({ 1, 0, 0, 1 })
      assert.equal(ring, btn.ring)
      assert.is_true(ring.shown)
      assert.same({ 1, 0, 0, 1 }, ring.vertex)
    end)

    it("dims with the button while it is disabled", function()
      local btn = GC.Theme.Button(stubFrame(), "ghost", "badge")
      btn:SetRing({ 1, 1, 1, 1 })
      btn:Disable()
      assert.equal(0.45, btn.ring.alpha)
      btn:Enable()
      assert.equal(1, btn.ring.alpha)
    end)
  end)

  it("SetVariant recolors a rounded button's bg via SetVertexColor, not SetColorTexture", function()
    local T = GC.Theme
    local btn = T.Button(stubFrame(), "ghost", "plaque")
    btn.bg.colorTexture, btn.bg.vertex = nil, nil
    btn:SetVariant("active")
    assert.is_nil(btn.bg.colorTexture)
    assert.is_truthy(btn.bg.vertex)
    local spec = T.color.gold
    assert.same({ spec[1], spec[2], spec[3], 0.16 }, btn.bg.vertex)
  end)

  it("leaves square mode (nil 3rd arg) exactly as before: solid bg, no ring", function()
    local T = GC.Theme
    local btn = T.Button(stubFrame(), "ghost")
    assert.is_truthy(btn.bg.colorTexture)
    assert.is_nil(btn.bg.textureFile)
    assert.is_nil(btn.ring)
  end)

  it("TierMark: SetLabel colors the dot and text and sets the label text", function()
    local T = GC.Theme
    local mark = T.TierMark(stubFrame())
    assert.is_truthy(mark.dot)
    assert.is_truthy(mark.text)
    local color = T.tier.HOT
    mark:SetLabel("HOT", color)
    assert.equal("HOT", mark.text.rawText)
    assert.same({ color[1], color[2], color[3], 1 }, mark.dot.colorTexture)
    assert.same({ color[1], color[2], color[3], 1 }, mark.text.color)
  end)
end)
