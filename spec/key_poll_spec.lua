local helper = require("spec.spec_helper")

describe("KeyPoll", function()
  local GC
  local now, triggers, hits, rowsEmitted

  local function row(itemID, minPrice, totalQuantity)
    return { itemKey = { itemID = itemID }, minPrice = minPrice, totalQuantity = totalQuantity }
  end

  local function fakeDriver()
    return {
      now = function() return now end,
      triggerFor = function(itemID) return triggers[itemID] end,
      onHit = function(hit) hits[#hits + 1] = hit end,
      onRows = function(rows) rowsEmitted[#rowsEmitted + 1] = rows end,
    }
  end

  before_each(function()
    GC = helper.loadModule("Core/KeyPoll.lua")
    now = 1000
    triggers, hits, rowsEmitted = {}, {}, {}
  end)

  local function newPoll(opts)
    return GC.KeyPoll.New(fakeDriver(), opts)
  end

  local function ids(first, last)
    local list = {}
    for id = first, last do list[#list + 1] = id end
    return list
  end

  describe("batching", function()
    it("has nothing pending with no targets", function()
      local poll = newPoll()
      assert.is_false(poll:HasPending())
      assert.is_nil(poll:NextBatch())
    end)

    it("never hands out more than 100 keys in one batch", function()
      local poll = newPoll()
      poll:SetTargets(ids(1, 250))
      assert.equal(100, #poll:NextBatch())
      assert.equal(100, #poll:NextBatch())
      assert.equal(50, #poll:NextBatch())
      assert.is_false(poll:HasPending())
    end)

    it("refuses to raise the 100-key cap through opts", function()
      local poll = newPoll({ maxBatch = 500 })
      poll:SetTargets(ids(1, 250))
      assert.equal(100, #poll:NextBatch())
    end)

    it("walks the set round-robin, one visit each per cycle", function()
      local poll = newPoll({ maxBatch = 2 })
      poll:SetTargets({ 5, 1, 3, 2 })
      assert.same({ 1, 2 }, poll:NextBatch())
      assert.same({ 3, 5 }, poll:NextBatch())
      assert.is_false(poll:HasPending())
      assert.is_nil(poll:NextBatch())
      -- The next cycle resumes where the cursor stopped rather than restarting at the top,
      -- so an odd-sized set does not starve its tail.
      poll:BeginCycle()
      assert.is_true(poll:HasPending())
      assert.same({ 1, 2 }, poll:NextBatch())
    end)

    it("wraps the cursor mid-batch when the set does not divide evenly", function()
      local poll = newPoll({ maxBatch = 2 })
      poll:SetTargets({ 1, 2, 3 })
      assert.same({ 1, 2 }, poll:NextBatch())
      assert.same({ 3 }, poll:NextBatch())     -- the cycle's remainder, not a wrapped pair
      poll:BeginCycle()
      assert.same({ 1, 2 }, poll:NextBatch())  -- cursor wrapped back to the top for the new cycle
    end)

    it("deduplicates and sorts the target set", function()
      local poll = newPoll({ maxBatch = 10 })
      poll:SetTargets({ 9, 3, 9, 3, 1, "x", -4 })
      assert.same({ 1, 3, 9 }, poll:NextBatch())
      assert.equal(3, poll:Count())
    end)

    it("leaves an unchanged set alone, and restarts a changed one", function()
      local poll = newPoll({ maxBatch = 2 })
      poll:SetTargets({ 1, 2, 3, 4 })
      assert.same({ 1, 2 }, poll:NextBatch())
      assert.is_false(poll:SetTargets({ 4, 3, 2, 1 })) -- same set, different order
      assert.same({ 3, 4 }, poll:NextBatch())          -- cursor untouched
      assert.is_true(poll:SetTargets({ 1, 2, 3, 4, 5 }))
      assert.is_true(poll:HasPending())                -- a new set is a new cycle
      assert.same({ 1, 2 }, poll:NextBatch())
    end)
  end)

  describe("folding results", function()
    it("fires a hit for a floor under the trigger, the first time it is seen", function()
      local poll = newPoll()
      triggers[7] = 1000
      poll:Fold({ row(7, 900, 3) })
      assert.equal(1, #hits)
      assert.equal(7, hits[1].itemID)
      assert.equal(900, hits[1].floor)
      assert.equal(3, hits[1].qty)
      assert.is_nil(hits[1].prev)
      assert.equal(900, poll:Book()[7].floor)
      assert.equal(1000, poll:Book()[7].seenAt)
    end)

    it("says nothing about a floor at or above the trigger", function()
      local poll = newPoll()
      triggers[7] = 1000
      poll:Fold({ row(7, 1000, 3), row(8, 10, 1) }) -- 8 has no trigger at all
      assert.same({}, hits)
    end)

    it("does not re-report the same listing on the next cycle", function()
      local poll = newPoll()
      triggers[7] = 1000
      poll:Fold({ row(7, 900, 3) })
      poll:Fold({ row(7, 900, 3) })
      assert.equal(1, #hits)
    end)

    it("reports the same item again when the floor moves or the stack grows", function()
      local poll = newPoll()
      triggers[7] = 1000
      poll:Fold({ row(7, 900, 3) })
      poll:Fold({ row(7, 850, 3) })   -- price moved
      poll:Fold({ row(7, 850, 4) })   -- more of it listed at the same price
      poll:Fold({ row(7, 850, 2) })   -- fewer: somebody bought some, not news
      assert.equal(3, #hits)
      assert.equal(900, hits[2].prev.floor)
    end)

    it("ignores rows with no item id or no price", function()
      local poll = newPoll()
      triggers[7] = 1000
      poll:Fold({ { minPrice = 900 }, row(7, 0, 1), row(7, nil, 1) })
      assert.same({}, hits)
      assert.is_nil(poll:Book()[7])
    end)

    it("hands every row to the caller, hit or not", function()
      local poll = newPoll()
      local rows = { row(7, 900, 3), row(8, 5, 1) }
      poll:Fold(rows)
      assert.same({ rows }, rowsEmitted)
    end)
  end)

  it("forgets the book on reset but keeps the targets", function()
    local poll = newPoll({ maxBatch = 2 })
    triggers[7] = 1000
    poll:SetTargets({ 7, 8 })
    poll:Fold({ row(7, 900, 3) })
    assert.equal(1, #hits)

    poll:Reset()
    assert.is_nil(poll:Book()[7])
    assert.equal(2, poll:Count())
    assert.is_true(poll:HasPending())
    assert.same({ 7, 8 }, poll:NextBatch())
    -- With the book gone the same listing is news again -- the point of forgetting it.
    poll:Fold({ row(7, 900, 3) })
    assert.equal(2, #hits)
  end)
end)
