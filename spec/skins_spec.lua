local helper = require("spec.spec_helper")

-- UI/Kit/Skins.lua: the skins as data, applied in place over UI/Kit/Tokens.lua.
describe("skins", function()
  local GC, Tokens, Skins

  before_each(function()
    GC = helper.loadModule("UI/Theme.lua")
    Tokens, Skins = GC.Kit.Tokens, GC.Kit.Skins
  end)

  local function same(a, b, what)
    for i = 1, math.min(#a, #b) do
      assert.is_true(math.abs(a[i] - b[i]) < 1e-9, ("%s channel %d: %s vs %s"):format(what, i, a[i], b[i]))
    end
  end

  -- WCAG relative luminance (sRGB transfer), alpha dropped.
  local function luminance(c)
    local v = {}
    for i = 1, 3 do
      v[i] = c[i] <= 0.03928 and c[i] / 12.92 or ((c[i] + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * v[1] + 0.7152 * v[2] + 0.0722 * v[3]
  end
  local function contrast(a, b)
    local la, lb = luminance(a), luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
  end

  it("lists the nine skins in order", function()
    assert.same({ "goldcap", "forever", "pixel", "parchment", "horde", "alliance", "midnight", "classic", "leather" },
      Skins.ORDER)
  end)

  it("every skin defines every colour key goldcap defines", function()
    for _, id in ipairs(Skins.ORDER) do
      for key in pairs(Skins.defs.goldcap.color) do
        local c = Skins.defs[id].color[key]
        assert.is_table(c, id .. "." .. key)
        assert.is_true(#c == 3 or #c == 4, id .. "." .. key)
        for i = 1, #c do
          assert.is_true(type(c[i]) == "number" and c[i] >= 0 and c[i] <= 1, id .. "." .. key .. "[" .. i .. "]")
        end
      end
    end
  end)

  it("gives every skin its shape, frame and flags", function()
    for _, id in ipairs(Skins.ORDER) do
      local d = Skins.defs[id]
      assert.equal(4, #d.radius, id)
      assert.is_true(({ hairline = 1, bevel = 1, pixel = 1, classic = 1 })[d.frame] ~= nil, id)
      assert.is_number(d.frameWidth, id)
      assert.is_boolean(d.plates, id)
      assert.is_boolean(d.glow, id)
      assert.is_table(d.fonts, id)
    end
    assert.equal("rivets", Skins.defs.horde.ornament)
    assert.equal("stitch", Skins.defs.leather.ornament)
    assert.is_nil(Skins.defs.goldcap.ornament)
  end)

  it("goldcap is today's palette", function()
    Skins.Apply("goldcap")
    local c = Tokens.color
    same(c.gold, Tokens.hex("E8B04B"), "gold")
    same(c.windowTop, Tokens.hex("151921", 0.93), "windowTop")
    same(c.text4, Tokens.hex("6F7885"), "text4")
    same(c.text5, Tokens.hex("4F5763"), "text5")
    same(c.raised, Tokens.hex("1B2029"), "raised")
    same(c.hoverWash, { c.gold[1], c.gold[2], c.gold[3], 0.18 }, "hoverWash")
  end)

  it("defines the six skin-only keys as tables right after load, and aliases of them follow Apply", function()
    local keys = { "railIdle", "railActive", "primaryTop", "primaryBottom", "primaryText", "frameTint" }
    for _, key in ipairs(keys) do assert.is_table(Tokens.color[key], key) end
    local alias = Tokens.color.primaryTop
    Skins.Apply("horde")
    assert.equal(alias, Tokens.color.primaryTop)
    same(alias, Tokens.hex("CF3B2D"), "primaryTop")
  end)

  it("apply writes in place", function()
    local g = Tokens.color.gold
    Skins.Apply("horde")
    assert.equal(g, Tokens.color.gold)
    same(g, Tokens.hex("CB3A2C"), "gold")
    assert.equal("horde", Skins.Current() == Skins.defs.horde and "horde")
  end)

  it("derived colours follow", function()
    local f = Tokens.alpha("gold", 0.12)
    Skins.Apply("alliance")
    local gold = Skins.defs.alliance.color.gold
    for i = 1, 3 do assert.is_true(math.abs(f[i] - gold[i]) < 1e-9) end
    assert.equal(0.12, f[4])
    same(GC.Theme.color.bg, Tokens.hex("080C16"), "bg")
    assert.equal(0.12, Tokens.alpha("gold", 0.12)[4])
  end)

  it("an alpha derived without a number follows the token's own", function()
    local w = Tokens.alpha("windowTop")
    Skins.Apply("forever")
    assert.equal(0.92, w[4])
    Skins.Apply("goldcap")
    assert.equal(0.93, w[4])
  end)

  it("unknown ids fall back to goldcap", function()
    for _, id in ipairs({ "Horde", "next" }) do
      Skins.Apply("horde")
      assert.equal("goldcap", Skins.Apply(id))
      same(Tokens.color.gold, Tokens.hex("E8B04B"), id)
    end
    assert.equal("goldcap", Skins.Apply(nil))
    assert.equal("goldcap", Skins.Apply(42))
    assert.equal(Skins.defs.goldcap, Skins.Current())
  end)

  it("Blizzard surfaces keep today's colours", function()
    Skins.Apply("parchment")
    same(Tokens.blizzard.text1, Tokens.hex("F3F1EC"), "blizzard text1")
  end)

  it("text is readable in every skin", function()
    for _, id in ipairs(Skins.ORDER) do
      local c = Skins.defs[id].color
      for _, ground in ipairs({ "windowTop", "windowBottom" }) do
        for _, key in ipairs({ "text1", "text2" }) do
          local r = contrast(c[key], c[ground])
          assert.is_true(r >= 4.5, ("%s: %s on %s is %.2f"):format(id, key, ground, r))
        end
        for _, key in ipairs({ "text3", "text4", "profit", "loss", "goldText", "yours", "warn", "tierHot", "tierGood", "tierWatch", "tierSuspect" }) do
          local r = contrast(c[key], c[ground])
          assert.is_true(r >= 3, ("%s: %s on %s is %.2f"):format(id, key, ground, r))
        end
      end
    end
  end)
end)
