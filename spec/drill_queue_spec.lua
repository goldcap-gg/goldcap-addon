local helper = require("spec.spec_helper")

describe("DrillQueue", function()
  local GC, now

  local function fakeDriver() return { now = function() return now end } end

  before_each(function()
    GC = helper.loadModule("Core/DrillQueue.lua")
    now = 1000
  end)

  it("returns nil when empty", function()
    local q = GC.DrillQueue.New(fakeDriver())
    assert.is_nil(q:Pop())
  end)

  it("pops the highest estProfit first", function()
    local q = GC.DrillQueue.New(fakeDriver())
    q:Push({ itemID = 1, floor = 100, estProfit = 500 })
    q:Push({ itemID = 2, floor = 200, estProfit = 900 })
    q:Push({ itemID = 3, floor = 300, estProfit = 100 })
    assert.equal(2, q:Pop().itemID)
    assert.equal(1, q:Pop().itemID)
    assert.equal(3, q:Pop().itemID)
    assert.is_nil(q:Pop())
  end)

  it("drops a duplicate push of the same itemID+floor while the first is still queued", function()
    local q = GC.DrillQueue.New(fakeDriver())
    assert.is_true(q:Push({ itemID = 1, floor = 100, estProfit = 500 }))
    assert.is_false(q:Push({ itemID = 1, floor = 100, estProfit = 999 }))
    assert.equal(1, q:Depth())
  end)

  it("allows re-pushing the same itemID+floor once it has been popped", function()
    local q = GC.DrillQueue.New(fakeDriver())
    q:Push({ itemID = 1, floor = 100, estProfit = 500 })
    q:Pop()
    assert.is_true(q:Push({ itemID = 1, floor = 100, estProfit = 500 }))
    assert.equal(1, q:Depth())
  end)

  it("treats a different floor for the same item as a separate entry", function()
    local q = GC.DrillQueue.New(fakeDriver())
    q:Push({ itemID = 1, floor = 100, estProfit = 500 })
    q:Push({ itemID = 1, floor = 90, estProfit = 500 })
    assert.equal(2, q:Depth())
  end)

  it("enforces the per-minute budget with a sliding window", function()
    local q = GC.DrillQueue.New(fakeDriver(), { perMinute = 2 })
    q:Push({ itemID = 1, floor = 1, estProfit = 1 })
    q:Push({ itemID = 2, floor = 1, estProfit = 1 })
    q:Push({ itemID = 3, floor = 1, estProfit = 1 })
    assert.is_not_nil(q:Pop())
    assert.is_not_nil(q:Pop())
    assert.is_nil(q:Pop()) -- budget spent
    now = now + 61
    assert.is_not_nil(q:Pop()) -- the window slid past the first two sends
  end)

  it("reports queue depth", function()
    local q = GC.DrillQueue.New(fakeDriver())
    assert.equal(0, q:Depth())
    q:Push({ itemID = 1, floor = 1, estProfit = 1 })
    assert.equal(1, q:Depth())
  end)
end)
