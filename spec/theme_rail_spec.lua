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
  function f:CreateTexture(_, layer) local t = stubFrame(); t.layer = layer; return t end
  function f:CreateFontString() return stubFrame() end
  return f
end

describe("Theme.Rail navigation widgets", function()
  local GC

  before_each(function()
    GC = {}
    _G.CreateFrame = function() return stubFrame() end
    helper.loadModule("UI/Theme.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame = nil
  end)

  it("RailButton: active disables the button and paints gold; inactive re-enables and dims", function()
    local b = GC.Theme.RailButton(stubFrame(), GC.Theme.MEDIA .. "icon_deals.png", "DEALS")
    b:SetActive(true)
    assert.is_false(b.enabled)          -- active view's button must not be clickable
    assert.is_true(b.bg.shown)
    assert.is_true(b.glow.shown)
    assert.equal(0, b.highlightTexture.alpha)
    local hi = GC.Theme.color.goldHi
    assert.same({ hi[1], hi[2], hi[3], 1 }, b.icon.vertex)
    b:SetActive(false)
    assert.is_true(b.enabled)
    assert.is_false(b.bg.shown)
    assert.is_false(b.glow.shown)
    assert.equal(1, b.highlightTexture.alpha)
  end)

  it("RailButton: badge shows a count and hides on nil", function()
    local b = GC.Theme.RailButton(stubFrame(), GC.Theme.MEDIA .. "icon_sell.png", "SELL")
    assert.is_false(b.badge.shown)
    b:SetBadge(3)
    assert.is_true(b.badge.shown)
    assert.equal("3", b.badge.text.rawText)
    b:SetBadge(nil)
    assert.is_false(b.badge.shown)
  end)

  it("RailButton: badge bg is its own badge texture (14px tall -- even plaque.png's margins would notch it)", function()
    local b = GC.Theme.RailButton(stubFrame(), GC.Theme.MEDIA .. "icon_sell.png", "SELL")
    assert.equal(GC.Theme.MEDIA .. "badge.png", b.badge.bg.textureFile)
    assert.same({ 6, 6, 6, 6 }, b.badge.bg.slice)
  end)

  -- Item 7 (addon polish batch): SetBadge already scales the badge's WIDTH by T.Scale() (the
  -- digit-count-dependent part), but its height stayed a fixed 14 -- at the 0.9x-1.3x
  -- font-scale slider extremes the pill's aspect ratio no longer matched its own width.
  it("RailButton: badge height scales with T.Scale() the same way its width already does", function()
    GC.Theme.SetScale(1.3)
    local b = GC.Theme.RailButton(stubFrame(), GC.Theme.MEDIA .. "icon_sell.png", "SELL")
    b:SetBadge(3)
    assert.equal(14 * 1.3, b.badge.height)
    GC.Theme.SetScale(1.0)
  end)

  it("RailButton: hover is the engine HIGHLIGHT layer on a mouse-enabled button", function()
    local b = GC.Theme.RailButton(stubFrame(), GC.Theme.MEDIA .. "icon_sold.png", "SOLD")
    assert.is_true(b.mouseEnabled)
    assert.equal("HIGHLIGHT", b.highlightTexture.layer)
    assert.equal("ADD", b.highlightTexture.blend)
  end)

  it("Rail: returns the three nav buttons and the gear", function()
    local rail = GC.Theme.Rail(stubFrame())
    assert.equal(GC.Theme.RAIL_W, rail.frame.width)
    assert.is_truthy(rail.buttons.deals)
    assert.is_truthy(rail.buttons.sell)
    assert.is_truthy(rail.buttons.sold)
    assert.is_truthy(rail.gear)
    -- T6: rounded "badge" (margin 6, same size class as RailButton's own badge -- see
    -- ROUNDED_BUTTON's comment in Theme.lua) so SetVariant("active")/"ghost" (SettingsFrame.lua's
    -- OnShow/OnHide) has a rounded fill to repaint, not the square edgeBorder look.
    assert.equal(6, rail.gear.roundedMargin)
    -- labels are what the player reads; assert them so a refactor can't shuffle order
    assert.equal("DEALS", rail.buttons.deals.text.rawText)
    assert.equal("SELL", rail.buttons.sell.text.rawText)
    assert.equal("SOLD", rail.buttons.sold.text.rawText)
  end)

  it("Rail: SetTopInset re-points the logo below the docked host's portrait", function()
    local rail = GC.Theme.Rail(stubFrame())
    assert.is_truthy(rail.logo)
    rail.SetTopInset(28)
    local point = rail.logo.points[#rail.logo.points]
    assert.same({ "TOP", 0, -44 }, point)
  end)
end)
