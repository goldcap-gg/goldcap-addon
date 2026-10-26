local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/HoardRow.lua's item icon, shared by the Hoard, Send to alts, Disenchant and the craft panel.
describe("shared item icon", function()
  local GC, restore, HF, row

  before_each(function()
    restore = W.install()
    _G.C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function(id) return id == 7 and 3 or nil end }
    _G.C_TooltipInfo = { GetItemByID = function() return { lines = { { leftText = "|A:Professions-Icon-Quality-Tier3-Small:20:20|a" } } } end }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("UI/HoardFrame.lua", GC)
    helper.loadModule("UI/HoardRow.lua", GC)
    HF = GC.HoardFrame
    row = W.CreateFrame("Frame")
  end)

  after_each(function()
    _G.C_TradeSkillUI, _G.C_TooltipInfo = nil, nil
    restore()
  end)

  local function shown(w) return W.state(w).shown end

  it("paints as before without options: no pip, no dimming", function()
    local slot = HF.Row.NewIcon(row, 30, true)
    HF.Row.PaintIcon(slot, 7, 555, 4, nil)
    assert.is_false(shown(slot.pip))
    assert.is_false(W.state(slot.icon).desaturated)
    assert.same({ 1, 1, 1, 1 }, W.state(slot.icon).vertex)
    assert.is_false(shown(slot.shade))
  end)

  it("draws the crafting quality top left, a third of the icon, when asked", function()
    local slot = HF.Row.NewIcon(row, 30)
    HF.Row.PaintIcon(slot, 7, 555, nil, nil, { pip = true })
    assert.is_true(shown(slot.pip))
    assert.equal("Professions-Icon-Quality-Tier3-Small", W.state(slot.pip).atlas)
    assert.same({ 10, 10 }, { W.state(slot.pip).width, W.state(slot.pip).height })
    assert.same({ "TOPLEFT", slot.edge, "TOPLEFT", 0, 0 }, W.state(slot.pip).points[1])
  end)

  it("hides the pip for an item without a quality, and again on the next paint", function()
    local slot = HF.Row.NewIcon(row, 30)
    HF.Row.PaintIcon(slot, 7, 555, nil, nil, { pip = true })
    HF.Row.PaintIcon(slot, 8, 556, nil, nil, { pip = true })
    assert.is_false(shown(slot.pip))
    HF.Row.PaintIcon(slot, 7, 555, nil, nil, { pip = true })
    HF.Row.PaintIcon(slot, 7, 555)
    assert.is_false(shown(slot.pip))
  end)

  it("shades a dim icon as a disabled one, apart from the moved shade", function()
    local slot = HF.Row.NewIcon(row, 30)
    HF.Row.PaintIcon(slot, 7, 555, nil, nil, { dim = true })
    assert.is_true(W.state(slot.icon).desaturated)
    assert.same({ 0.5, 0.5, 0.5, 1 }, W.state(slot.icon).vertex)
    assert.is_false(shown(slot.shade))
    HF.Row.PaintIcon(slot, 7, 555)
    assert.is_false(W.state(slot.icon).desaturated)
    assert.same({ 1, 1, 1, 1 }, W.state(slot.icon).vertex)
  end)

  it("hides the pip with the icon", function()
    local slot = HF.Row.NewIcon(row, 30)
    HF.Row.PaintIcon(slot, 7, 555, nil, nil, { pip = true })
    HF.Row.HideIcon(slot)
    assert.is_false(shown(slot.pip))
  end)
end)
