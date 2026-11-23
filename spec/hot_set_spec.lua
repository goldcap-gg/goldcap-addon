local helper = require("spec.spec_helper")

describe("HotSet", function()
  local GC, now, set
  before_each(function()
    GC = helper.loadModule("Core/HotSet.lua")
    now = 1000
    set = GC.HotSet.New(function() return now end, 600)
  end)

  it("holds a marked item until its time is up, by the table", function()
    local cases = { { 0, true }, { 1, true }, { 599, true }, { 600, false }, { 5000, false } }
    for _, c in ipairs(cases) do
      local s = GC.HotSet.New(function() return now end, 600)
      s:Mark(7)
      now = 1000 + c[1]
      assert.equal(c[2], s:Has(7), "after " .. c[1] .. " s")
      now = 1000
    end
    assert.is_false(set:Has(8))
  end)

  it("starts the time again on a new mark", function()
    set:Mark(7)
    now = 1500
    set:Mark(7)
    now = 2050
    assert.is_true(set:Has(7))
    now = 2100
    assert.is_false(set:Has(7))
  end)

  it("counts only the items still in the set, and ignores what is not an item id", function()
    set:Mark(1)
    now = 1300
    set:Mark(2)
    set:Mark("x")
    set:Mark(nil)
    assert.equal(2, set:Count())
    now = 1650
    assert.equal(1, set:Count())
    now = 1900
    assert.equal(0, set:Count())
  end)
end)
