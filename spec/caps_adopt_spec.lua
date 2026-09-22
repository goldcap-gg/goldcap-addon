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
