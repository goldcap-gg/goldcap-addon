local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/DealCard.lua: the GoldCap card under a DEALS row's tooltip. It is GameTooltip's own child, so
-- it hides with it; it is as wide as the tooltip and never under 300; it hangs under the tooltip,
-- over it at the screen's foot; and it goes the moment the tooltip is cleared or changes owner.
describe("deal card", function()
  local GC, restore, tip, hooks, owner, savedTip, savedParent

  local function fakeTooltip(geometry)
    local t = W.CreateFrame("GameTooltip")
    local s = W.state(t)
    function t:GetOwner() return s.owner end
    function t:SetOwner(o) s.owner = o end
    function t:GetBottom() return geometry.bottom end
    function t:GetTop() return geometry.top end
    function t:GetLeft() return geometry.left end
    function t:GetEffectiveScale() return 1 end
    function t:HookScript(name, fn) hooks[name] = fn end
    t:SetWidth(geometry.width)
    return t
  end

  local function model()
    return {
      deal = { itemID = 7, forever = "market", ceiling = 850, refUnit = 1700, unitPrice = 500, avail = 2731 },
      big = { label = "You make about", text = "~+1s 13c", tone = "profit" },
      scale = GC.DealCard.Scale(500, 850, 1700, "market"),
      chips = GC.DealCard.Chips({ avail = 2731, forever = "market" }),
      notes = { { text = "Listed at or under the deal price of a group you follow (Herbs)" } },
      facts = { { left = "Source", right = "your scan, 3m ago" } },
      hints = GC.DealCard.Hints({}, false, false),
      now = function() return 104 end,
      verdict = { buyable = true, at = 100 },
    }
  end

  before_each(function()
    restore = W.install()
    hooks = {}
    GC = helper.loadModule("Core/Util.lua")
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("Core/DealCard.lua", GC)
    helper.loadModule("UI/DealCard.lua", GC)
    savedTip, savedParent = _G.GameTooltip, _G.UIParent
    owner = {}
    tip = fakeTooltip({ bottom = 400, top = 700, left = 900, width = 240 })
    tip:SetOwner(owner)
    _G.GameTooltip = tip
    _G.UIParent = { GetTop = function() return 1000 end, GetEffectiveScale = function() return 1 end }
  end)

  after_each(function()
    _G.GameTooltip, _G.UIParent, _G.GetCoinTextureString = savedTip, savedParent, nil
    restore()
  end)

  local function window(left)
    return { GetLeft = function() return left end, GetEffectiveScale = function() return 1 end }
  end

  it("is the tooltip's own child, never under 300 wide, docked flush under it", function()
    GC.DealCardUI.Show(owner, model(), window(100))
    local card = GC.DealCardUI._Frame()
    assert.equal(tip, card:GetParent())
    assert.is_true(card:IsShown())
    assert.equal(300, card:GetWidth())
    local point, rel, relPoint, x, y = card:GetPoint(1)
    assert.same({ "TOPLEFT", tip, "BOTTOMLEFT", 0, 0 }, { point, rel, relPoint, x, y })
    assert.is_true(card:GetHeight() > 100)
  end)

  it("takes the tooltip's width when it is wider", function()
    tip:SetWidth(360)
    GC.DealCardUI.Show(owner, model(), window(100))
    assert.equal(360, GC.DealCardUI._Frame():GetWidth())
  end)

  it("grows away from the window when the tooltip sits left of it, and hangs above at the screen's foot", function()
    tip = fakeTooltip({ bottom = 40, top = 300, left = 10, width = 240 })
    tip:SetOwner(owner)
    _G.GameTooltip = tip
    GC.DealCardUI.Show(owner, model(), window(500))
    local point, rel, relPoint = GC.DealCardUI._Frame():GetPoint(1)
    assert.same({ "BOTTOMRIGHT", tip, "TOPRIGHT" }, { point, rel, relPoint })
  end)

  it("leaves with the tooltip: cleared, or drawn for another owner", function()
    GC.DealCardUI.Show(owner, model(), window(100))
    local card = GC.DealCardUI._Frame()
    hooks.OnTooltipCleared()
    assert.is_false(card:IsShown())

    GC.DealCardUI.Show(owner, model(), window(100))
    tip:SetOwner({})
    W.state(card).scripts.OnUpdate(card, 1)
    assert.is_false(card:IsShown())
  end)

  it("draws the verdict, the big number, the scale and the hints", function()
    GC.DealCardUI.Show(owner, model(), window(100))
    local card = GC.DealCardUI._Frame()
    assert.equal("SAFE · LIVE 4s AGO", card.pill.text:GetText())
    assert.equal("~+1s 13c", card.bigValue:GetText())
    assert.is_true(card.bar:IsShown())
    assert.equal("2,731 listed", card.chips[1].text:GetText())
    assert.equal("watch it", card.hints[1].text:GetText())
  end)

  -- A language whose words run wider (CHAR_W stands in for one): the card grows to hold the pill
  -- beside the brand rather than cut it, and a key hint that does not fit starts a new row.
  it("widens for a wide pill and wraps its key hints", function()
    local wide = W.CHAR_W
    finally(function() W.CHAR_W = wide end)
    W.CHAR_W = 9
    local m = model()
    m.verdict = { needsGold = 53224680, at = 100 }
    m.hints = GC.DealCard.Hints({}, false, true)
    GC.DealCardUI.Show(owner, m, window(100))
    local card = GC.DealCardUI._Frame()
    assert.is_true(card:GetWidth() > 300)
    local first, third = W.state(card.hints[1]).points[1][5], W.state(card.hints[3]).points[1][5]
    assert.is_true(third < first)
  end)

  it("draws no scale and no number when the model has none", function()
    local m = model()
    m.scale, m.big = nil, nil
    GC.DealCardUI.Show(owner, m, window(100))
    local card = GC.DealCardUI._Frame()
    assert.is_false(card.bar:IsShown())
    assert.is_false(card.bigValue:IsShown())
  end)
end)
