local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/Kit/Button.lua's Theme.BoardTab: DEALS' boards as tabs, the game's icon for the board, its
-- name, a line saying what is on it and its count on the icon (owner, 2026-11-23: variant B of the
-- toolbar board on the Blackwater canvas). The real kit against the frame fakes.
describe("Theme.BoardTab", function()
  local GC, T, restore
  local BAG = "Interface\\Icons\\INV_Misc_Bag_10"

  local function plain(text) return helper.plain(text) end
  local function st(region) return W.state(region) end

  before_each(function()
    restore = W.install()
    GC = helper.loadModule("UI/Theme.lua", {})
    helper.loadModule("Core/Util.lua", GC)
    T = GC.Theme
  end)

  after_each(function()
    W.missingTextures = {}
    restore()
  end)

  it("keeps the name as its label, with the line under it and no count until one is given", function()
    local tab = T.BoardTab(CreateFrame("Frame"), BAG, "bag")
    tab:SetLabel("COMMODITIES")
    tab:SetSub("herbs, ore, potions")
    assert.equal("COMMODITIES", tab.label)
    assert.equal("herbs, ore, potions", plain(st(tab.sub).text))
    assert.is_true(st(tab.sub).shown)
    assert.equal(T.BOARD_TAB.H, st(tab).height)
    assert.equal(BAG, st(tab.icon).file)
    assert.is_nil(tab.countValue)
    assert.is_false(st(tab.count).shown and true or false)
  end)

  it("puts a count on the icon, and none at zero", function()
    local tab = T.BoardTab(CreateFrame("Frame"), BAG, "bag")
    tab:SetCount(44)
    assert.equal(44, tab.countValue)
    assert.is_true(st(tab.count).shown)
    tab:SetCount(0)
    assert.is_nil(tab.countValue)
    assert.is_false(st(tab.count).shown and true or false)
  end)

  it("shows the board that is up in colour with a gold edge, the others greyed", function()
    local tab = T.BoardTab(CreateFrame("Frame"), BAG, "bag")
    assert.is_true(st(tab.icon).desaturated)
    tab:SetVariant("active")
    assert.is_false(st(tab.icon).desaturated)
    local gold = T.color.gold
    assert.same({ gold[1], gold[2], gold[3], 0.9 }, st(tab.iconEdge).color)
    tab:SetVariant("ghost")
    assert.is_true(st(tab.icon).desaturated)
  end)

  -- Never cut: where the row is short of room the line goes whole and the name stands alone.
  it("drops its line whole and is narrower without it", function()
    local tab = T.BoardTab(CreateFrame("Frame"), BAG, "bag")
    tab:SetLabel("ITEMS")
    tab:SetSub("gear, pets, recipes")
    tab:Fit()
    local wide = st(tab).width
    tab:ShowSub(false)
    tab:Fit()
    assert.is_false(st(tab.sub).shown and true or false)
    assert.is_true(st(tab).width < wide)
    tab:ShowSub(true)
    assert.is_true(st(tab.sub).shown)
  end)

  it("stands the kit's glyph in where the client has no such icon", function()
    W.missingTextures = { [BAG] = true }
    local tab = T.BoardTab(CreateFrame("Frame"), BAG, "bag")
    assert.equal(GC.Kit.Icons.file, st(tab.icon).file)
  end)

  -- Retail's every other button: the tab is opt-in, a plain one carries none of it.
  it("leaves a plain kit button as it was", function()
    local b = T.Button(CreateFrame("Frame"), "ghost", "plaque")
    assert.is_nil(b.icon)
    assert.is_nil(b.sub)
    assert.is_nil(b.SetCount)
  end)
end)
