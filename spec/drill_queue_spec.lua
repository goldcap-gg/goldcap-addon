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

  it("keeps the entry queued when the budget refuses a Pop", function()
    local q = GC.DrillQueue.New(fakeDriver(), { perMinute = 1 })
    q:Push({ itemID = 1, floor = 1, estProfit = 1 })
    q:Push({ itemID = 2, floor = 1, estProfit = 9 })
    assert.equal(2, q:Pop().itemID)
    assert.is_nil(q:Pop())   -- budget spent
    assert.equal(1, q:Depth()) -- the refused entry is still queued, not dropped
  end)

  describe("Peek", function()
    it("returns the highest estProfit without removing it", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 500 })
      q:Push({ itemID = 2, floor = 200, estProfit = 900 })
      assert.equal(2, q:Peek().itemID)
      assert.equal(2, q:Peek().itemID)
      assert.equal(2, q:Depth())
    end)

    it("does not charge the per-minute budget", function()
      local q = GC.DrillQueue.New(fakeDriver(), { perMinute = 1 })
      q:Push({ itemID = 1, floor = 100, estProfit = 500 })
      q:Peek()
      q:Peek()
      assert.equal(1, q:Pop().itemID) -- the peeks spent nothing, so the one send is still there
    end)

    it("returns nil on an empty queue", function()
      assert.is_nil(GC.DrillQueue.New(fakeDriver()):Peek())
    end)
  end)

  describe("Drop", function()
    it("removes the entry without charging the budget", function()
      local q = GC.DrillQueue.New(fakeDriver(), { perMinute = 1 })
      q:Push({ itemID = 1, floor = 100, estProfit = 900 })
      q:Push({ itemID = 2, floor = 200, estProfit = 500 })
      assert.is_true(q:Drop({ itemID = 1, floor = 100 }))
      assert.equal(1, q:Depth())
      assert.equal(2, q:Pop().itemID) -- the budget was never touched by the drop
    end)

    it("frees the itemID+floor key so the same hit can be pushed again", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 900 })
      q:Drop({ itemID = 1, floor = 100 })
      assert.is_true(q:Push({ itemID = 1, floor = 100, estProfit = 900 }))
    end)

    it("reports false for an entry it does not hold", function()
      local q = GC.DrillQueue.New(fakeDriver())
      assert.is_false(q:Drop({ itemID = 1, floor = 100 }))
      assert.is_false(q:Drop(nil))
    end)
  end)

  describe("Has", function()
    it("answers for an itemID at any floor", function()
      local q = GC.DrillQueue.New(fakeDriver())
      assert.is_false(q:Has(1))
      q:Push({ itemID = 1, floor = 100, estProfit = 1 })
      assert.is_true(q:Has(1))
      q:Pop()
      assert.is_false(q:Has(1))
    end)

    it("stops answering once the entry has expired", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 1 })
      now = now + 91
      assert.is_false(q:Has(1))
    end)
  end)

  describe("the 200-entry cap", function()
    local function fill(q, count, profitFor)
      for i = 1, count do
        q:Push({ itemID = i, floor = 1, estProfit = profitFor(i) })
      end
    end

    it("evicts the lowest-estProfit entry for a better one", function()
      local q = GC.DrillQueue.New(fakeDriver())
      fill(q, 200, function(i) return i * 10 end) -- item 1 is the cheapest at 10
      assert.equal(200, q:Depth())
      assert.is_true(q:Push({ itemID = 9001, floor = 1, estProfit = 15 }))
      assert.equal(200, q:Depth())
      assert.is_false(q:Has(1))    -- the worst entry made room
      assert.is_true(q:Has(9001))
    end)

    it("refuses a new entry that is worth less than the worst one queued", function()
      local q = GC.DrillQueue.New(fakeDriver())
      fill(q, 200, function(i) return i * 10 end)
      assert.is_false(q:Push({ itemID = 9001, floor = 1, estProfit = 5 }))
      assert.equal(200, q:Depth())
      assert.is_true(q:Has(1))
    end)
  end)

  describe("the 90-second expiry", function()
    it("drops an expired entry instead of popping it", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 900 })
      now = now + 90
      assert.is_nil(q:Peek())
      assert.is_nil(q:Pop())
      assert.equal(0, q:Depth())
    end)

    it("keeps an entry that is still inside the window", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 900 })
      now = now + 89
      assert.equal(1, q:Peek().itemID)
    end)

    it("expires only the entries that are actually old", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 900 })
      now = now + 60
      q:Push({ itemID = 2, floor = 100, estProfit = 100 })
      now = now + 31 -- item 1 is 91s old, item 2 is 31s old
      assert.equal(1, q:Depth())
      assert.equal(2, q:Peek().itemID)
    end)
  end)

  describe("Clear", function()
    it("empties the queue", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 900 })
      q:Push({ itemID = 2, floor = 100, estProfit = 100 })
      q:Clear()
      assert.equal(0, q:Depth())
      assert.is_nil(q:Peek())
      assert.is_false(q:Has(1))
      assert.is_true(q:Push({ itemID = 1, floor = 100, estProfit = 900 })) -- the key is free again
    end)
  end)
end)
