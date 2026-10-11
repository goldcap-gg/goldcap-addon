local helper = require("spec.spec_helper")

-- UI/Kit/Tokens.lua holds the new palette; UI/Theme.lua maps its long-standing colour names onto
-- it, so Sniper, Buy, Sold and Settings draw in the new colours without being edited.
describe("kit tokens", function()
  local GC

  before_each(function()
    GC = helper.loadModule("UI/Theme.lua")
  end)

  local function near(hexString, actual, what)
    local expected = GC.Kit.Tokens.hex(hexString)
    for i = 1, 3 do
      assert.is_true(math.abs(expected[i] - actual[i]) < 0.002, ("%s channel %d: %s vs %s"):format(what, i, expected[i], actual[i]))
    end
  end

  it("draws the old colour names in the new palette", function()
    local c = GC.Theme.color
    near("F3F1EC", c.fg, "fg")
    near("C3C8D0", c.fgMuted, "fgMuted")
    near("8B93A0", c.fgDim, "fgDim")
    near("E8B04B", c.gold, "gold")
    near("F7CF5A", c.goldHi, "goldHi")
    near("6EE7A0", c.green, "green")
    near("FF8A8A", c.red, "red")
    near("7CC0FF", c.watch, "watch")
    near("151921", c.panel, "panel")
    near("0C0E13", c.bg, "bg")
  end)

  it("keeps every colour name a window reads", function()
    for _, key in ipairs({ "bg", "panel", "panelHi", "border", "gold", "goldHi", "fg", "fgMuted", "fgDim",
      "red", "redFill", "green", "cost", "zebra", "hover", "watch" }) do
      assert.is_table(GC.Theme.color[key], key)
    end
  end)

  it("leaves the Sniper's tier colours meaning what they mean today", function()
    assert.same({ 1, 0.35, 0.15 }, GC.Theme.tier.HOT)
    assert.same({ 1, 0.85, 0.1 }, GC.Theme.tier.SUSPECT)
  end)

  it("names the media folder once", function()
    assert.equal("Interface\\AddOns\\GoldCap\\Media\\", GC.Kit.MEDIA)
    assert.equal(GC.Kit.MEDIA, GC.Theme.MEDIA)
  end)
end)
