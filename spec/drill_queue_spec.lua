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

  -- The arbiter re-queues a hit whose send was declined (an uncached item key, the drain
  -- fence). Stamping that with a fresh clock made the entry immortal: highest estProfit keeps
  -- it at the head, nothing can ever age it out, and it goes on describing a price nobody has
  -- seen for minutes while every ready tick tries it again.
  it("keeps a re-queued hit's original age, so an undrillable one still ages out", function()
    local q = GC.DrillQueue.New(fakeDriver())
    q:Push({ itemID = 1, floor = 100, estProfit = 500 })

    for _ = 1, 5 do
      now = now + 15
      local hit = q:Pop()          -- charged, handed out
      assert.equal(1, hit.itemID)
      assert.is_true(q:Push(hit))  -- declined, straight back in
    end

    now = now + 20 -- 95s after the FIRST push, past the 90s time to live
    assert.is_nil(q:Peek())
    assert.equal(0, q:Depth())
  end)

  it("refuses a pushedAt from the future, which would outlive the queue itself", function()
    local q = GC.DrillQueue.New(fakeDriver())
    q:Push({ itemID = 1, floor = 100, estProfit = 500, pushedAt = now + 10000 })
    now = now + 91
    assert.is_nil(q:Peek())
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

  describe("priority", function()
    it("pops a priority hit before a higher-estProfit priority-less one", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 9999 })
      q:Push({ itemID = 2, floor = 200, estProfit = 5, priority = 1 })
      assert.equal(2, q:Pop().itemID)
      assert.equal(1, q:Pop().itemID)
    end)

    it("breaks a priority tie by estProfit desc", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 50, priority = 1 })
      q:Push({ itemID = 2, floor = 200, estProfit = 90, priority = 1 })
      assert.equal(2, q:Pop().itemID)
      assert.equal(1, q:Pop().itemID)
    end)

    it("keeps priority and cap on the stored entry", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 5, priority = 1, cap = true })
      local peeked = q:Peek()
      assert.equal(1, peeked.priority)
      assert.is_true(peeked.cap)
      local popped = q:Pop()
      assert.equal(1, popped.priority)
      assert.is_true(popped.cap)
    end)

    it("defaults priority to 0 and cap to false when absent", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 5 })
      local popped = q:Pop()
      assert.equal(0, popped.priority)
      assert.is_false(popped.cap)
    end)

    it("does not change the dedup key", function()
      local q = GC.DrillQueue.New(fakeDriver())
      assert.is_true(q:Push({ itemID = 1, floor = 100, estProfit = 5, priority = 1 }))
      assert.is_false(q:Push({ itemID = 1, floor = 100, estProfit = 999, priority = 5 }))
      assert.equal(1, q:Depth())
    end)

    it("displaces a low-priority entry before a high-priority one when full", function()
      local q = GC.DrillQueue.New(fakeDriver())
      -- item 1 is priority 1 (protected), the rest are priority 0 with rising estProfit
      q:Push({ itemID = 1, floor = 1, estProfit = 1, priority = 1 })
      for i = 2, 200 do
        q:Push({ itemID = i, floor = 1, estProfit = i * 10 })
      end
      assert.equal(200, q:Depth())
      -- worth more than item 2's estProfit (20) but less than item 1's own estProfit (1) is
      -- not the point here -- the point is it is priority-0, same as item 2, so it competes
      -- with item 2, not with the protected item 1.
      assert.is_true(q:Push({ itemID = 9001, floor = 1, estProfit = 25 }))
      assert.is_true(q:Has(1))     -- the priority hit survives despite the lowest estProfit
      assert.is_false(q:Has(2))    -- the lowest priority-0 estProfit is displaced instead
    end)
  end)

  -- Caps fixes 4b. Strict priority with nothing else meant a steady stream of cap hits (the
  -- player's own prices, priority 1) held every ordinary drill back for as long as it lasted --
  -- the first round after opening the auction house with a few hundred caps is exactly such a
  -- stream. Bounded now: after four priority pops in a row that an ordinary hit waited through,
  -- the next pop is the best ordinary hit.
  describe("fairness under a stream of priority hits", function()
    local function pushCaps(q, first, last)
      for id = first, last do
        q:Push({ itemID = id, floor = 1, estProfit = 1, priority = 1, cap = true })
      end
    end

    it("drills one ordinary hit after four priority pops in a row", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 1, estProfit = 9999 })
      pushCaps(q, 101, 110)
      local order = {}
      for _ = 1, 6 do order[#order + 1] = q:Pop().itemID end
      assert.equal(1, order[5])
      for i = 1, 4 do assert.is_true(order[i] > 100) end
      assert.is_true(order[6] > 100) -- and the stream resumes behind it
    end)

    it("names the same entry at Peek that Pop is about to take", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 1, estProfit = 9999 })
      pushCaps(q, 101, 110)
      for _ = 1, 4 do q:Pop() end
      assert.equal(1, q:Peek().itemID)
      assert.equal(1, q:Pop().itemID)
    end)

    it("counts only the priority pops an ordinary hit actually waited through", function()
      local q = GC.DrillQueue.New(fakeDriver())
      pushCaps(q, 101, 106)
      for _ = 1, 6 do q:Pop() end -- nobody was waiting: nothing is owed
      q:Push({ itemID = 1, floor = 1, estProfit = 9999 })
      pushCaps(q, 201, 210)
      local order = {}
      for _ = 1, 5 do order[#order + 1] = q:Pop().itemID end
      assert.same({ true, true, true, true }, {
        order[1] > 200, order[2] > 200, order[3] > 200, order[4] > 200 })
      assert.equal(1, order[5])
    end)

    it("keeps strict priority for the pops in between", function()
      local q = GC.DrillQueue.New(fakeDriver())
      q:Push({ itemID = 1, floor = 1, estProfit = 9999 })
      q:Push({ itemID = 2, floor = 1, estProfit = 5000 })
      pushCaps(q, 101, 104)
      assert.is_true(q:Pop().itemID > 100)
      assert.is_true(q:Pop().itemID > 100)
    end)
  end)

  -- Caps fixes 4b, the other half. A cap hit is reported by a ratchet (Core/KeyPoll.lua's Fold,
  -- GC.Caps.BookHits) that never repeats an unchanged floor, so a cap hit the queue let go of
  -- without drilling it was gone for good -- until the floor happened to move. The queue now says
  -- so (driver.onLost) and the caller re-arms the ratchet; ordinary hits are not reported.
  describe("a cap hit lost un-drilled", function()
    local lost

    local function losingDriver()
      lost = {}
      return { now = function() return now end,
        onLost = function(entry) lost[#lost + 1] = entry end }
    end

    it("is reported when it expires", function()
      local q = GC.DrillQueue.New(losingDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 5, priority = 1, cap = true })
      q:Push({ itemID = 2, floor = 200, estProfit = 5 })
      now = now + 91
      assert.equal(0, q:Depth())
      assert.equal(1, #lost)
      assert.equal(1, lost[1].itemID)
      assert.equal(100, lost[1].floor)
      assert.is_true(lost[1].cap)
    end)

    it("is reported when a better hit evicts it from a full queue", function()
      local q = GC.DrillQueue.New(losingDriver())
      for i = 1, 200 do
        q:Push({ itemID = i, floor = 1, estProfit = i, priority = 1, cap = true })
      end
      assert.is_true(q:Push({ itemID = 9001, floor = 1, estProfit = 500, priority = 1, cap = true }))
      assert.equal(1, #lost)
      assert.equal(1, lost[1].itemID)
    end)

    it("is reported when a full queue refuses it", function()
      local q = GC.DrillQueue.New(losingDriver())
      for i = 1, 200 do
        q:Push({ itemID = i, floor = 1, estProfit = 1000 + i, priority = 1, cap = true })
      end
      assert.is_false(q:Push({ itemID = 9001, floor = 7, estProfit = 1, priority = 1, cap = true }))
      assert.equal(1, #lost)
      assert.equal(9001, lost[1].itemID)
      assert.equal(7, lost[1].floor)
    end)

    it("is not reported when it is drilled, dropped, cleared or already queued", function()
      local q = GC.DrillQueue.New(losingDriver())
      q:Push({ itemID = 1, floor = 100, estProfit = 5, priority = 1, cap = true })
      q:Push({ itemID = 2, floor = 100, estProfit = 5, priority = 1, cap = true })
      q:Push({ itemID = 3, floor = 100, estProfit = 5, priority = 1, cap = true })
      assert.is_false(q:Push({ itemID = 3, floor = 100, estProfit = 5, priority = 1, cap = true }))
      q:Pop()
      q:Drop({ itemID = 2, floor = 100 })
      q:Clear()
      now = now + 91
      q:Depth()
      assert.same({}, lost)
    end)

    it("is not reported for an ordinary hit", function()
      local q = GC.DrillQueue.New(losingDriver())
      for i = 1, 200 do q:Push({ itemID = i, floor = 1, estProfit = 1000 + i }) end
      q:Push({ itemID = 9001, floor = 1, estProfit = 1 })    -- refused
      q:Push({ itemID = 9002, floor = 1, estProfit = 5000 }) -- evicts item 1
      now = now + 91                                          -- the rest expire
      q:Depth()
      assert.same({}, lost)
    end)
  end)

  -- The same item at the same floor can be reported by two sources -- the realm poll as an
  -- ordinary hit, the player's own cap as a priority one. The key is the same, so the second push
  -- is a duplicate; it may not leave the hit queued at the lower of the two priorities.
  it("upgrades a queued hit when the same item and floor come back as a cap hit", function()
    local q = GC.DrillQueue.New(fakeDriver())
    q:Push({ itemID = 1, floor = 100, estProfit = 5 })
    q:Push({ itemID = 2, floor = 100, estProfit = 9999 })
    assert.is_false(q:Push({ itemID = 1, floor = 100, estProfit = 5, priority = 1, cap = true }))
    assert.equal(2, q:Depth())
    local head = q:Pop()
    assert.equal(1, head.itemID)
    assert.equal(1, head.priority)
    assert.is_true(head.cap)
  end)

  -- Round 1: and once upgraded it is ordered among the caps by the caps' own measure -- the
  -- saving under the cap -- not by the market estimate it was first queued with.
  it("orders an upgraded hit among the caps by the cap's own measure", function()
    local q = GC.DrillQueue.New(fakeDriver())
    q:Push({ itemID = 1, floor = 100, estProfit = 9999 })
    q:Push({ itemID = 2, floor = 50, estProfit = 10, priority = 1, cap = true })
    q:Push({ itemID = 1, floor = 100, estProfit = 5, priority = 1, cap = true })
    assert.equal(2, q:Pop().itemID)
    assert.equal(1, q:Pop().itemID)
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
