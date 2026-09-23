local helper = require("spec.spec_helper")
describe("Caps.Adopt", function()
  local GC
  before_each(function()
    GC = helper.loadModule("Core/Caps.lua")
    _G.GoldCap_AppRuns = nil
  end)
  after_each(function() _G.GoldCap_AppRuns = nil end)

  it("reads caps and groups with type guards and keeps delivery order", function()
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1700000000, runs = {},
      groups = { "Transmog", "Ore" },
      caps = { { i = 212345, c = 1500000, l = 610, g = 1, m = true }, { i = 190311, c = 4200, g = 2 } } }
    assert.is_true(GC.Caps.Adopt())
    assert.equals(2, GC.Caps.Count())
    assert.same({ 212345, 190311 }, GC.Caps.Targets())
    assert.same({ c = 1500000, l = 610, group = "Transmog", manual = true }, GC.Caps.For(212345))
    assert.same({ c = 4200, l = 0, group = "Ore", manual = false }, GC.Caps.For(190311))
    assert.equals(1500001, GC.Caps.TriggerFor(212345))
    assert.is_nil(GC.Caps.TriggerFor(1))
    assert.equals(1700000000, GC.Caps.GeneratedAt())
  end)

  it("drops junk entries alone and a group index off the end", function()
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = { "G" },
      caps = { "x", { i = "a" }, { i = 5 }, { i = 6, c = 0 }, { i = 7, c = 10, g = 9 }, { i = 7, c = 20 } } }
    assert.is_true(GC.Caps.Adopt())
    assert.same({ 7 }, GC.Caps.Targets())
    assert.same({ c = 10, l = 0, group = nil, manual = false }, GC.Caps.For(7))  -- first wins
  end)

  -- Final review M9: the type guard let infinity through. `v == v` catches a NaN and nothing
  -- else, so a `c` of math.huge became a cap no price on earth could break -- every lot
  -- qualifies, every server quote passes GC.Caps.QuoteOk. Neither is a number the site can have
  -- meant. An unusable `l` drops the entry rather than falling back to "no floor": widening the
  -- player's own "this much for ilvl >= 610" into "this much for anything" is how a junk
  -- variant gets bought at the good variant's price.
  it("drops a cap whose numbers are infinite", function()
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = {},
      caps = { { i = 1, c = math.huge }, { i = 2, c = -math.huge }, { i = 3, c = 100, l = math.huge },
        { i = 4, c = 100, l = 10 } } }
    GC.Caps.Adopt()
    assert.same({ 4 }, GC.Caps.Targets())
    assert.is_nil(GC.Caps.For(1))
    assert.is_nil(GC.Caps.For(2))
    assert.is_nil(GC.Caps.For(3))
  end)

  -- Caps fixes 4a + 4c. Spec §5 held the poll to 200 ilvl-gated caps because each of them cost a
  -- drill to judge: the poll's aggregate floor says nothing about item level. The poll now judges
  -- a gated cap on the cheapest variant at its own level (Core/KeyPoll.lua's minIlvlFor), which
  -- costs no more than any other cap -- and every cap is polled, whatever board is on screen.
  describe("ilvl-gated caps", function()
    it("are all polled, in delivery order, however many there are", function()
      local caps = {}
      for i = 1, 210 do caps[#caps + 1] = { i = 2000 + i, c = 100, l = 610 } end
      for i = 1, 30 do caps[#caps + 1] = { i = 3000 + i, c = 100, l = 0 } end
      _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = {}, caps = caps }
      GC.Caps.Adopt()
      local targets = GC.Caps.Targets()
      assert.equal(240, #targets)
      assert.equal(2001, targets[1])
      assert.equal(2210, targets[210])
      assert.equal(3030, targets[240])
      assert.equal(101, GC.Caps.TriggerFor(2210))
    end)
  end)

  -- Caps fixes 5d: every drop above is silent by design -- a partly broken write must not block
  -- the parts that are fine -- which left a player whose price never fired nothing to go on.
  -- Counted instead, for `/gc board` to print; never a popup.
  it("counts the prices it dropped as unreadable and the ones it dropped as repeats", function()
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = {},
      caps = { "x", { i = "a" }, { i = 5 }, { i = 6, c = 0 }, { i = 8, c = 10, l = "610" },
        { i = 7, c = 10 }, { i = 7, c = 20 } } }
    GC.Caps.Adopt()
    local malformed, duplicate = GC.Caps.Dropped()
    assert.equals(5, malformed)
    assert.equals(1, duplicate)

    _G.GoldCap_AppRuns = { v = 3, generatedAt = 2, runs = {}, groups = {}, caps = { { i = 7, c = 10 } } }
    GC.Caps.Adopt()
    assert.same({ 0, 0 }, { GC.Caps.Dropped() })
    _G.GoldCap_AppRuns = nil
    GC.Caps.Adopt()
    assert.same({ 0, 0 }, { GC.Caps.Dropped() })
  end)

  it("an absent or unsupported file clears the set", function()
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, caps = { { i = 1, c = 1 } } }
    GC.Caps.Adopt()
    _G.GoldCap_AppRuns = { v = 9, generatedAt = 2, runs = {}, caps = { { i = 1, c = 1 } } }
    assert.is_true(GC.Caps.Adopt())
    assert.equals(0, GC.Caps.Count())
    _G.GoldCap_AppRuns = nil
    GC.Caps.Adopt()
    assert.equals(0, GC.Caps.Count())
  end)
end)
