local helper = require("spec.spec_helper")

-- Followed groups (plan 2026-10-22, task 8): the selling rules of the groups the player follows
-- on goldcap.gg, read from the Companion's GoldCap_AppRuns. The first cap of an item decides its
-- rule, exactly as it decides the item's price cap (Core/Caps.lua), and a variant under the
-- cap's item level keeps the rule's shape but none of the prices the site worked out at that level.
describe("GroupRules", function()
  local GC

  local FLIP = { n = "Transmog: Plate", p = "flip", d = 48, q = 1, fp = 70, s = 5 }
  local GATHER = { n = "Herbs", p = "gather", d = 24, fp = 80 }

  local function adopt(caps, rules, groups)
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = groups or { "G" },
      caps = caps, rules = rules }
    return GC.GroupRules.Adopt()
  end

  before_each(function()
    GC = helper.loadModule("Core/GroupRules.lua")
    _G.GoldCap_AppRuns = nil
  end)
  after_each(function() _G.GoldCap_AppRuns = nil end)

  it("reads a flip rule", function()
    assert.is_true(adopt({ { i = 10, c = 700, l = 610, g = 1, u = 1000, r = 1, k = true } }, { FLIP }))
    assert.same({ name = "Transmog: Plate", play = "flip", durationIndex = 3, perItem = 1, stepPct = 5,
      floorPct = 70, floorUnit = 700, usualUnit = 1000 }, GC.GroupRules.RuleFor(10, 610))
    assert.equal(3, GC.GroupRules.durationByItem[10])
    assert.equal(3, GC.GroupRules.HOURS_TO_INDEX[48])
  end)

  it("hands out a fresh table every time", function()
    adopt({ { i = 10, c = 700, u = 1000, r = 1 } }, { GATHER })
    local a = GC.GroupRules.RuleFor(10, 0)
    a.floorUnit = 1
    assert.equal(800, GC.GroupRules.RuleFor(10, 0).floorUnit)
  end)

  it("a craft rule floors at f", function()
    adopt({ { i = 20, c = 900, u = 1200, r = 1, f = 950 } }, { { n = "Potions", p = "craft", d = 24 } })
    local rule = GC.GroupRules.RuleFor(20, 0)
    assert.equal(950, rule.floorUnit)
    assert.is_true(rule.craftFloor)
    assert.is_nil(rule.floorPct)
    adopt({ { i = 20, c = 900, u = 1200, r = 1 } }, { { n = "Potions", p = "craft", d = 24 } })
    assert.is_nil(GC.GroupRules.RuleFor(20, 0).floorUnit)
    assert.is_nil(GC.GroupRules.RuleFor(20, 0).craftFloor)
  end)

  it("a lower level keeps the rule but none of its prices", function()
    adopt({ { i = 10, c = 700, l = 610, g = 1, u = 1000, r = 1, k = true } }, { FLIP })
    for _, level in ipairs({ 600, false }) do
      local rule = GC.GroupRules.RuleFor(10, level or nil)
      assert.is_nil(rule.floorUnit)
      assert.is_nil(rule.usualUnit)
      assert.is_nil(rule.stepPct)
      assert.equal("Transmog: Plate", rule.name)
      assert.equal("flip", rule.play)
      assert.equal(3, rule.durationIndex)
      assert.equal(1, rule.perItem)
    end
    assert.equal(700, GC.GroupRules.RuleFor(10, 640).floorUnit)
    -- The cost to craft does not depend on the item's level.
    adopt({ { i = 11, c = 700, l = 610, u = 1000, r = 1, f = 650 } }, { { n = "Potions", p = "craft", d = 24 } })
    assert.equal(650, GC.GroupRules.RuleFor(11, 600).floorUnit)
  end)

  it("an alert cap without u has no floor", function()
    adopt({ { i = 30, c = 500, r = 1 } }, { GATHER })
    local rule = GC.GroupRules.RuleFor(30, 0)
    assert.equal("Herbs", rule.name)
    assert.is_nil(rule.floorUnit)
    assert.is_nil(rule.stepPct)
  end)

  it("the first cap of an item decides its rule", function()
    adopt({ { i = 5, c = 700, u = 1000, r = 1 }, { i = 5, c = 800, u = 1000, r = 2 } }, { FLIP, GATHER })
    assert.equal(FLIP.n, GC.GroupRules.RuleFor(5).name)
    -- An unreadable first cap is not the item's first cap: Core/Caps.lua drops it too.
    adopt({ { i = 6, c = 0, r = 1 }, { i = 6, c = 800, u = 1000, r = 2 } }, { FLIP, GATHER })
    assert.equal(GATHER.n, GC.GroupRules.RuleFor(6).name)
    -- A first cap without a rule leaves the item without one, as its cap has none.
    adopt({ { i = 7, c = 700 }, { i = 7, c = 800, u = 1000, r = 2 } }, { FLIP, GATHER })
    assert.is_nil(GC.GroupRules.RuleFor(7))
  end)

  it("an old file gives no rule to any item", function()
    assert.is_false(adopt({ { i = 5, c = 800, g = 1 }, { i = 7, c = 600, l = 610, m = true } }, nil))
    assert.is_nil(GC.GroupRules.RuleFor(5))
    assert.is_nil(next(GC.GroupRules.durationByItem))
    assert.is_false(GC.GroupRules.Adopt())
  end)

  it("reports a change only when a rule moves, and empties when the file goes", function()
    assert.is_true(adopt({ { i = 10, c = 700, u = 1000, r = 1 } }, { GATHER }))
    assert.is_false(GC.GroupRules.Adopt())
    _G.GoldCap_AppRuns.rules[1] = { n = "Herbs", p = "gather", d = 48, fp = 80 }
    assert.is_true(GC.GroupRules.Adopt())
    assert.equal(3, GC.GroupRules.durationByItem[10])
    local held = GC.GroupRules.durationByItem
    _G.GoldCap_AppRuns = nil
    assert.is_true(GC.GroupRules.Adopt())
    assert.is_nil(GC.GroupRules.RuleFor(10))
    -- Refreshed in place: a click path that holds the table reads the new contents.
    assert.is_nil(held[10])
    assert.equal(held, GC.GroupRules.durationByItem)
  end)

  it("takes the file it is handed", function()
    assert.is_true(GC.GroupRules.Adopt({ v = 3, caps = { { i = 10, c = 700, u = 1000, r = 1 } }, rules = { GATHER } }))
    assert.equal("Herbs", GC.GroupRules.RuleFor(10).name)
  end)

  -- The bank card's groups (UI/BankGroupsCard.lua): an item's group is its rule's name, by the same
  -- first cap that decides the rule.
  it("names the group of an item, and says whether any group came at all", function()
    assert.is_false(GC.GroupRules.HasGroups())
    assert.is_nil(GC.GroupRules.GroupOf(10))
    adopt({ { i = 10, c = 700, u = 1000, r = 1 }, { i = 10, c = 700, u = 1000, r = 2 }, { i = 11, c = 500 } },
      { GATHER, FLIP })
    assert.is_true(GC.GroupRules.HasGroups())
    assert.equal("Herbs", GC.GroupRules.GroupOf(10))
    assert.is_nil(GC.GroupRules.GroupOf(11))
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    assert.is_false(GC.GroupRules.HasGroups())
    assert.is_nil(GC.GroupRules.GroupOf(10))
  end)

  -- The name is the group's in the language of the newest follow, so it changes; the id (the
  -- group's slug on goldcap.gg) does not. The bank card keeps counts by the key GroupOf answers.
  it("answers a group's key and name: its id when the rule has one, else its name", function()
    adopt({ { i = 10, c = 700, u = 1000, r = 1 }, { i = 11, c = 700, u = 1000, r = 2 } },
      { { n = "Kräuter", id = "herbs-tww", p = "gather", d = 24 }, GATHER })
    assert.same({ "herbs-tww", "Kräuter" }, { GC.GroupRules.GroupOf(10) })
    -- An older Companion's file has no id: the name is the key.
    assert.same({ "Herbs", "Herbs" }, { GC.GroupRules.GroupOf(11) })
    -- A player's own list from a TSM import has a slug of its own.
    adopt({ { i = 10, c = 700, u = 1000, r = 1 } }, { { n = "My Herbs", id = "u_a1b2c3d4e5f6", p = "gather", d = 24 } })
    assert.same({ "u_a1b2c3d4e5f6", "My Herbs" }, { GC.GroupRules.GroupOf(10) })
  end)

  it("reads an id only in the site's shape, and a rule with a broken id keeps its name as the key", function()
    local long = string.rep("a", 80)
    for id, want in pairs({ [long] = long, ["ore_1-x"] = "ore_1-x", [long .. "a"] = "Herbs", ["Herbs"] = "Herbs",
        ["herbs tww"] = "Herbs", [""] = "Herbs", ["herbs\n"] = "Herbs", ["травы"] = "Herbs" }) do
      adopt({ { i = 10, c = 700, u = 1000, r = 1 } }, { { n = "Herbs", id = id, p = "gather", d = 24 } })
      assert.equal(want, (GC.GroupRules.GroupOf(10)), id)
      assert.equal("Herbs", GC.GroupRules.RuleFor(10).name, id)
    end
    adopt({ { i = 10, c = 700, u = 1000, r = 1 } }, { { n = "Herbs", id = 42, p = "gather", d = 24 } })
    assert.equal("Herbs", (GC.GroupRules.GroupOf(10)))
  end)

  it("reports a new id as a change, and the same id under a new name too", function()
    assert.is_true(adopt({ { i = 10, c = 700, u = 1000, r = 1 } }, { { n = "Herbs", id = "herbs", p = "gather", d = 24 } }))
    _G.GoldCap_AppRuns.rules[1].id = "herbs-tww"
    assert.is_true(GC.GroupRules.Adopt())
    assert.equal("herbs-tww", (GC.GroupRules.GroupOf(10)))
    _G.GoldCap_AppRuns.rules[1].n = "Kräuter"
    assert.is_true(GC.GroupRules.Adopt())
    assert.same({ "herbs-tww", "Kräuter" }, { GC.GroupRules.GroupOf(10) })
    assert.is_false(GC.GroupRules.Adopt())
  end)

  it("unreadable rules give nothing", function()
    for _, bad in ipairs({
      { rules = { { n = "X", p = "gather", d = 36 } }, r = 1 },
      { rules = { { n = "X", p = "farm", d = 24 } }, r = 1 },
      { rules = { { n = "", p = "gather", d = 24 } }, r = 1 },
      { rules = { false, GATHER }, r = 1 },
      { rules = { GATHER }, r = 2 },
      { rules = { GATHER }, r = 0 },
      { rules = { GATHER }, r = 1.5 },
      { rules = "x", r = 1 },
    }) do
      adopt({ { i = 10, c = 700, u = 1000, r = bad.r } }, bad.rules)
      assert.is_nil(GC.GroupRules.RuleFor(10))
      assert.is_nil(next(GC.GroupRules.durationByItem))
    end
    -- Odd optional fields cost only themselves.
    adopt({ { i = 10, c = 700, u = "x", r = 1, f = -5 } }, { { n = "X", p = "flip", d = 12, q = 2, fp = 300, s = 0 } })
    assert.same({ name = "X", play = "flip", durationIndex = 1 }, GC.GroupRules.RuleFor(10, 0))
  end)

  describe("Describe", function()
    local function described(cap, rule)
      adopt({ cap }, { rule })
      return GC.GroupRules.Describe(GC.GroupRules.RuleFor(cap.i, cap.l or 0))
    end

    it("says the rule in words", function()
      assert.equal("1 at a time, 48 h, not under 70% of usual, 5% cheaper each time it comes back",
        described({ i = 10, c = 700, l = 610, u = 1000, r = 1 }, FLIP))
      assert.equal("all you have, 24 h, not under 80% of usual",
        described({ i = 11, c = 700, u = 1000, r = 1 }, GATHER))
      assert.equal("all you have, 24 h, not under the cost to craft",
        described({ i = 12, c = 700, u = 1000, r = 1, f = 900 }, { n = "Potions", p = "craft", d = 24 }))
      assert.equal("all you have, 24 h",
        described({ i = 13, c = 700, u = 1000, r = 1 }, { n = "Potions", p = "craft", d = 24 }))
      assert.is_nil(GC.GroupRules.Describe(nil))
    end)

    it("names no floor that does not apply", function()
      adopt({ { i = 10, c = 700, l = 610, u = 1000, r = 1 } }, { FLIP })
      assert.equal("1 at a time, 48 h", GC.GroupRules.Describe(GC.GroupRules.RuleFor(10, 600)))
    end)
  end)
end)
