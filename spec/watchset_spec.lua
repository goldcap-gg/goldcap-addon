local helper = require("spec.spec_helper")

describe("WatchSet", function()
  local GC
  before_each(function() GC = helper.loadModule("Core/WatchSet.lua") end)

  local function deal(itemID, unitPrice) return { itemID = itemID, unitPrice = unitPrice } end

  it("counts a distinct asking price once, however often it is seen", function()
    local churn = {}
    GC.WatchSet.Observe(churn, { deal(1, 100) }, 1)
    GC.WatchSet.Observe(churn, { deal(1, 100) }, 2)
    GC.WatchSet.Observe(churn, { deal(1, 100) }, 3)
    assert.equal(1, churn[1].count)
  end)

  it("counts each new floor the item is reposted at", function()
    local churn = {}
    GC.WatchSet.Observe(churn, { deal(1, 100) }, 1)
    GC.WatchSet.Observe(churn, { deal(1, 90) }, 2)
    GC.WatchSet.Observe(churn, { deal(1, 95) }, 3)
    assert.equal(3, churn[1].count)
    assert.equal(3, churn[1].at)
  end)

  it("promotes only items that have moved often enough", function()
    local churn = {}
    GC.WatchSet.Observe(churn, { deal(1, 100), deal(2, 500) }, 1)
    GC.WatchSet.Observe(churn, { deal(1, 90) }, 2)
    GC.WatchSet.Observe(churn, { deal(1, 80) }, 3)
    assert.same({ 1 }, GC.WatchSet.Select(churn, {}, 10))
  end)

  it("puts pins first and never drops one for a recidivist", function()
    local churn = {}
    for price = 1, 5 do GC.WatchSet.Observe(churn, { deal(7, price) }, price) end
    assert.same({ 42, 7 }, GC.WatchSet.Select(churn, { 42 }, 10))
  end)

  it("never truncates pins even when they outnumber capacity", function()
    local churn = {}
    -- A standing instruction outranks anything the addon worked out for itself: capacity
    -- bounds only the churn-derived portion of the set, never the pins.
    assert.same({ 42, 43 }, GC.WatchSet.Select(churn, { 42, 43 }, 1))
  end)

  it("still bounds the churn-derived portion by capacity once pins are included", function()
    local churn = {
      [1] = { count = 5, seen = {}, at = 10 },
      [2] = { count = 4, seen = {}, at = 9 },
    }
    assert.same({ 42, 1 }, GC.WatchSet.Select(churn, { 42 }, 1))
  end)

  it("never lists a pinned item twice", function()
    local churn = {}
    for price = 1, 5 do GC.WatchSet.Observe(churn, { deal(7, price) }, price) end
    assert.same({ 7 }, GC.WatchSet.Select(churn, { 7 }, 10))
  end)

  it("orders recidivists deterministically: score, then recency, then id", function()
    local churn = {
      [1] = { count = 3, seen = {}, at = 10 },
      [2] = { count = 5, seen = {}, at = 1 },
      [3] = { count = 3, seen = {}, at = 10 },
      [4] = { count = 3, seen = {}, at = 20 },
    }
    assert.same({ 2, 4, 1, 3 }, GC.WatchSet.Select(churn, {}, 10))
  end)

  it("ignores deals with no price and tolerates an empty world", function()
    local churn = {}
    GC.WatchSet.Observe(churn, { { itemID = 1 }, deal(2, 0) }, 1)
    assert.is_nil(churn[1])
    assert.is_nil(churn[2])
    assert.same({}, GC.WatchSet.Select({}, {}, 10))
    assert.same({}, GC.WatchSet.Select({}, {}, 0))
  end)
end)
