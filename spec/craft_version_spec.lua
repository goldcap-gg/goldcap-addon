local helper = require("spec.spec_helper")

-- Core/CraftVersion.lua: from what each version of an item sold per piece sold for this week (the
-- region payload's X) and the version a character makes, the price a craft has and what it rests
-- on. Pure. The rods' week, 2026-11-24, EU.
describe("craft version", function()
  local V

  before_each(function()
    local GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/CraftVersion.lua", GC)
    V = GC.CraftVersion
  end)

  local silver = { [2] = { ilvl = 212, sales = 8, realms = 5, median = 5160000 },
    [3] = { ilvl = 218, sales = 17, realms = 9, median = 3000000 },
    [4] = { ilvl = 225, sales = 17, realms = 10, median = 5500000 },
    [5] = { ilvl = 232, sales = 1208, realms = 89, median = 11100000 } }
  local plain = { [0] = { ilvl = 0, sales = 91, realms = 35, median = 880000 } }

  local function ranks(others)
    local out = {}
    for i, o in ipairs(others) do out[i] = o.rank end
    return out
  end

  it("proves a version from 5 sales on 3 realms", function()
    assert.equal(5, V.MIN_SALES)
    assert.equal(3, V.MIN_REALMS)
    assert.is_true(V.Proven({ ilvl = 1, sales = 5, realms = 3, median = 1 }))
    assert.is_false(V.Proven({ ilvl = 1, sales = 4, realms = 3, median = 1 }))
    assert.is_false(V.Proven({ ilvl = 1, sales = 5, realms = 2, median = 1 }))
    assert.is_false(V.Proven({ ilvl = 1, sales = 5, realms = 3 }))
    assert.is_false(V.Proven(nil))
  end)

  local cases = {
    { "a rank nobody sold", silver, 1, "unsold" },
    { "a proven rank", silver, 5, "proven", 11100000 },
    { "no ranks: no rank needed", plain, nil, "proven", 880000 },
    { "no ranks, rank 0", plain, 0, "proven", 880000 },
    { "four sales", { [1] = { ilvl = 180, sales = 4, realms = 4, median = 2110000 } }, 1, "thin", 2110000 },
    { "two realms", { [1] = { ilvl = 180, sales = 6, realms = 2, median = 2110000 } }, 1, "thin", 2110000 },
    { "named with no sale", {}, 1, "nosales" },
    { "not named", nil, 1, "nodata" },
    { "rank not known", silver, nil, "unknown" },
  }
  for _, c in ipairs(cases) do
    it("picks " .. c[4] .. " for " .. c[1], function()
      local b = V.Pick(c[2], c[3])
      assert.equal(c[4], b.kind)
      assert.equal(c[5], b.median)
      assert.is_table(b.others)
    end)
  end

  it("names the other proven versions, best rank first", function()
    local b = V.Pick(silver, 1)
    assert.same({ 5, 4, 3, 2 }, ranks(b.others))
    assert.same({ rank = 5, ilvl = 232, median = 11100000, sales = 1208 }, b.others[1])
    b = V.Pick(silver, 5)
    assert.same({ 5, 232, 1208, 89 }, { b.rank, b.ilvl, b.sales, b.realms })
    assert.same({ 4, 3, 2 }, ranks(b.others))
    assert.same({ 5, 4, 3, 2 }, ranks(V.Pick(silver, nil).others))
    -- A thin version is never among the others.
    local mixed = { [1] = { ilvl = 180, sales = 2, realms = 2, median = 1 }, [2] = silver[2] }
    assert.same({ 2 }, ranks(V.Pick(mixed, 3).others))
  end)

  it("finds the cheapest proven version", function()
    assert.same({ 3000000, 3 }, { V.Cheapest(silver) })
    assert.same({ 880000, 0 }, { V.Cheapest(plain) })
    assert.same({}, { V.Cheapest({ [1] = { ilvl = 180, sales = 4, realms = 4, median = 1 } }) })
    assert.same({}, { V.Cheapest({}) })
    assert.same({}, { V.Cheapest(nil) })
  end)

  it("finds a version by its item level", function()
    assert.equal(4, (V.ByLevel(silver, 225)))
    assert.equal(silver[4], select(2, V.ByLevel(silver, 225)))
    assert.is_nil(V.ByLevel(silver, 206))
    assert.is_nil(V.ByLevel(silver, 0))
    assert.is_nil(V.ByLevel(plain, 0))
    assert.is_nil(V.ByLevel(nil, 225))
  end)
end)
