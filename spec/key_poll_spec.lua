local helper = require("spec.spec_helper")

describe("KeyPoll", function()
  local GC
  local now, triggers, hits, rowsEmitted

  local function row(itemID, minPrice, totalQuantity)
    return { itemKey = { itemID = itemID }, minPrice = minPrice, totalQuantity = totalQuantity }
  end

  -- The other shape the client is allowed to answer with: one row per item-level variant, each
  -- carrying the full item key that variant answers to.
  local function variantRow(itemID, itemLevel, minPrice, totalQuantity)
    return {
      itemKey = { itemID = itemID, itemLevel = itemLevel, itemSuffix = 0, battlePetSpeciesID = 0 },
      minPrice = minPrice,
      totalQuantity = totalQuantity,
    }
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

    -- Caps fixes 4b: the ratchet's one way back for a hit that was reported and then lost
    -- before anybody drilled it (Core/DrillQueue.lua's onLost). The next fold of the same floor
    -- is news again -- once.
    it("reports an unchanged floor again after Rearm, and only once", function()
      local poll = newPoll()
      triggers[7] = 1000
      poll:Fold({ row(7, 900, 3) })
      poll:Fold({ row(7, 900, 3) })
      assert.equal(1, #hits)
      poll:Rearm(7)
      poll:Fold({ row(7, 900, 3) })
      assert.equal(2, #hits)
      assert.equal(900, hits[2].floor)
      poll:Fold({ row(7, 900, 3) })
      assert.equal(2, #hits)
    end)

    it("does nothing on Rearm for an item it has never seen", function()
      local poll = newPoll()
      triggers[7] = 1000
      poll:Rearm(7)
      assert.is_nil(poll:Book()[7])
      poll:Fold({ row(7, 900, 3) })
      assert.equal(1, #hits)
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

    -- Final review: SearchForItemKeys may answer with one row per item-level variant of the
    -- same item, and it may answer with one row for the whole item group -- both shapes are
    -- legal and the client is contractually neither. Folded row by row, the variant shape made
    -- the book flip between variants on every batch, so the ratchet above read noise as news,
    -- the arbiter's own `booked.floor == hit.floor` re-check then dropped the drill it had just
    -- queued, and the caller's floor-per-item map took whichever variant came last. Collapsing
    -- first makes all three right whichever way the client answers.
    it("collapses several rows for one item into the cheapest floor and the whole stack", function()
      local poll = newPoll()
      triggers[7] = 1000
      poll:Fold({ row(7, 950, 2), row(7, 900, 3), row(7, 980, 1) })

      assert.equal(1, #hits)
      assert.equal(900, hits[1].floor)
      assert.equal(6, hits[1].qty)
      assert.equal(900, poll:Book()[7].floor)
      assert.equal(6, poll:Book()[7].qty)
      -- The caller sees the same one row per item the book does.
      assert.equal(1, #rowsEmitted[1])
      assert.equal(900, rowsEmitted[1][1].minPrice)
      assert.equal(6, rowsEmitted[1][1].totalQuantity)
    end)

    it("never writes the collapsed figures back into the client's own result rows", function()
      local poll = newPoll()
      triggers[7] = 1000
      local first, second = row(7, 950, 2), row(7, 900, 3)
      poll:Fold({ first, second })
      assert.equal(950, first.minPrice)
      assert.equal(2, first.totalQuantity)
      assert.equal(3, second.totalQuantity)
    end)

    -- The variant drill (Teebu's Scorching Straight Sword, 159840, 2026-09-22). Collapsing to
    -- one floor is right for the ratchet and not enough for the DRILL, which has to name a key
    -- to search with: a bare key resolves to ONE variant server-side, so the board priced the
    -- 250,000 (19) lot and never saw the 211,111 (66) one sitting beside it in Blizzard's own
    -- browse. The rows the fold throws away are the only place the addon ever sees both, so
    -- they are kept on the book entry for UI/SniperFrame.lua to aim at.
    it("keeps every variant's own row on the book entry, cheapest first", function()
      local poll = newPoll()
      triggers[159840] = 300000
      poll:Fold({ variantRow(159840, 19, 250000, 2), variantRow(159840, 66, 211111, 1) })

      local entry = poll:Book()[159840]
      assert.equal(159840, entry.itemID)
      assert.equal(211111, entry.floor) -- the collapsed floor is still the cheapest on offer
      assert.equal(3, entry.qty)
      assert.equal(2, #entry.variants)
      assert.same({ itemLevel = 66, itemSuffix = 0, battlePetSpeciesID = 0, floor = 211111, qty = 1 },
        entry.variants[1])
      assert.same({ itemLevel = 19, itemSuffix = 0, battlePetSpeciesID = 0, floor = 250000, qty = 2 },
        entry.variants[2])
    end)

    -- The group shape: one row for the whole item, no item level in the key. There is exactly
    -- one variant to name and its key IS the bare key, which is what keeps the drill on its
    -- old behaviour for every item the client answers about this way.
    it("records the group row as the one variant it is", function()
      local poll = newPoll()
      triggers[7] = 1000
      poll:Fold({ row(7, 900, 3) })
      assert.same({ { itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0, floor = 900, qty = 3 } },
        poll:Book()[7].variants)
    end)

    it("keeps two different items apart while collapsing", function()
      local poll = newPoll()
      triggers[7], triggers[8] = 1000, 1000
      poll:Fold({ row(7, 950, 2), row(8, 300, 1), row(7, 900, 3) })
      assert.equal(2, #hits)
      assert.equal(900, poll:Book()[7].floor)
      assert.equal(5, poll:Book()[7].qty)
      assert.equal(300, poll:Book()[8].floor)
      assert.equal(1, poll:Book()[8].qty)
    end)
  end)

  -- Which key the drill sends. Pure, and deliberately not a method on a poll: the arbiter reads
  -- a book entry (Book()[itemID]) and needs the key for it, nothing more.
  describe("VariantKeyFor", function()
    local function teebus()
      local poll = newPoll()
      poll:Fold({ variantRow(159840, 19, 250000, 2), variantRow(159840, 66, 211111, 1) })
      return poll:Book()[159840]
    end

    it("names the cheapest variant when any item level will do", function()
      assert.same({ itemID = 159840, itemLevel = 66, itemSuffix = 0, battlePetSpeciesID = 0 },
        GC.KeyPoll.VariantKeyFor(teebus(), 0))
    end)

    -- The floor is what the decision about to be made compares against -- a cap's own `l`
    -- (Core/Caps.lua's DecideRealm) or the realm reference's refIlvl
    -- (GC.SniperDecision.EvaluateRealm). Drilling under it buys facts about lots neither one
    -- can approve.
    it("names the cheapest variant at or above the item-level floor", function()
      -- A ladder whose CHEAPEST variant is also its junk one, which is the case the floor
      -- exists for: bought on price alone it is a bargain on an item nobody asked for.
      local poll = newPoll()
      poll:Fold({ variantRow(300, 19, 100000, 1), variantRow(300, 66, 211111, 1),
        variantRow(300, 610, 900000, 1) })
      local entry = poll:Book()[300]

      assert.equal(19, GC.KeyPoll.VariantKeyFor(entry, 0).itemLevel)
      assert.equal(66, GC.KeyPoll.VariantKeyFor(entry, 20).itemLevel)
      assert.equal(610, GC.KeyPoll.VariantKeyFor(entry, 610).itemLevel)
      assert.is_nil(GC.KeyPoll.VariantKeyFor(entry, 611))
    end)

    it("has no answer when no variant reaches the floor", function()
      assert.is_nil(GC.KeyPoll.VariantKeyFor(teebus(), 610))
    end)

    it("has no answer for an entry that carries no variants at all", function()
      assert.is_nil(GC.KeyPoll.VariantKeyFor(nil, 0))
      assert.is_nil(GC.KeyPoll.VariantKeyFor({ itemID = 7, floor = 900 }, 0))
      assert.is_nil(GC.KeyPoll.VariantKeyFor({ itemID = 7, variants = {} }, 0))
    end)
  end)

  -- Caps fixes 3d: what an item costs at or above an item-level floor, off the same book entry.
  -- The entry's own `floor` is the cheapest variant of ANY level, so a cap with a level floor
  -- judged by it was kept alive by the junk variant after the one it wanted had sold.
  describe("FloorFor", function()
    local function ladder()
      local poll = newPoll()
      poll:Fold({ variantRow(300, 19, 100000, 1), variantRow(300, 66, 211111, 1),
        variantRow(300, 610, 900000, 1), variantRow(300, 615, 950000, 1) })
      return poll:Book()[300]
    end

    it("is the entry's own floor when any item level will do", function()
      assert.equal(100000, GC.KeyPoll.FloorFor(ladder(), 0))
      assert.equal(100000, GC.KeyPoll.FloorFor(ladder(), nil))
    end)

    it("is the cheapest variant at or above the item-level floor", function()
      assert.equal(211111, GC.KeyPoll.FloorFor(ladder(), 20))
      assert.equal(900000, GC.KeyPoll.FloorFor(ladder(), 610))
      assert.equal(950000, GC.KeyPoll.FloorFor(ladder(), 611))
    end)

    it("has no answer when no variant reaches the floor, or there is no entry", function()
      assert.is_nil(GC.KeyPoll.FloorFor(ladder(), 616))
      assert.is_nil(GC.KeyPoll.FloorFor(nil, 0))
      assert.is_nil(GC.KeyPoll.FloorFor({ itemID = 7, floor = 900 }, 610))
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
