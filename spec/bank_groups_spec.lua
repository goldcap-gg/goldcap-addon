local helper = require("spec.spec_helper")

-- Bank by group (Core/BankGroups.lua, retail only): which stack of a followed group one press
-- moves between the bags and the Warband Bank, and how many of each item the player keeps in the
-- bags. The stacks are what UI/BankRoute.lua's reader hands over; the group of an item is
-- Core/GroupRules.lua's, faked here as a table.
describe("bank by group", function()
  local GC, M

  -- Herbs: 1 and 2 (two qualities of one herb); Ore: 3. Item 9 is in no followed group.
  local GROUP = { [1] = "Herbs", [2] = "Herbs", [3] = "Ore" }
  local NAMES = { [1] = "Bloom", [2] = "Bloom", [3] = "Bismuth", [9] = "Linen Cloth" }

  local function stack(itemID, bag, slot, count, over)
    local s = { itemID = itemID, bag = bag, slot = slot, count = count, name = NAMES[itemID] }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
  end

  local function plan(bags, bank, keep, moving)
    return M.Plan(bags, bank, {
      groupOf = function(id) return GROUP[id] end,
      keepFor = function(name) return (keep or {})[name] or 0 end,
      moving = moving or {},
    })
  end

  local function where(stacks)
    local out = {}
    for _, s in ipairs(stacks) do out[#out + 1] = s.bag .. ":" .. s.slot end
    return out
  end

  before_each(function()
    GC = helper.loadModule("Core/BankGroups.lua")
    M = GC.BankGroups
  end)

  describe("Plan", function()
    it("lists each followed group with items in the bags or the bank, by name, with both counts", function()
      local groups = plan(
        { stack(1, 0, 1, 200), stack(9, 0, 2, 20), stack(3, 5, 1, 50) },
        { stack(2, 12, 4, 600) })
      assert.equal(2, #groups)
      assert.equal("Herbs", groups[1].name)
      assert.equal(200, groups[1].inBags)
      assert.equal(600, groups[1].inBank)
      assert.equal("Ore", groups[2].name)
      assert.equal(50, groups[2].inBags)
      assert.equal(0, groups[2].inBank)
    end)

    it("leaves out a group with nothing here, and items in no followed group", function()
      assert.same({}, plan({ stack(9, 0, 1, 20) }, {}))
      local groups = plan({}, { stack(3, 12, 1, 10) })
      assert.equal(1, #groups)
      assert.equal("Ore", groups[1].name)
      assert.same({}, groups[1].toBank)
      assert.same({ "12:1" }, where(groups[1].toBags))
    end)

    it("puts every stack in the bank with no keep count, the biggest of an item first", function()
      local herbs = plan({ stack(1, 0, 1, 20), stack(1, 0, 2, 200), stack(2, 1, 3, 5) }, {})[1]
      assert.same({ "0:2", "0:1", "1:3" }, where(herbs.toBank))
    end)

    it("takes every stack of the group out of the bank, whatever the keep count", function()
      local herbs = plan({}, { stack(1, 12, 1, 50), stack(2, 13, 7, 900) }, { Herbs = 100 })[1]
      assert.same({ "12:1", "13:7" }, where(herbs.toBags))
    end)

    -- A stack is moved whole: the game cannot split one in a single call. So To bank moves a stack
    -- only while the bags keep at least the count of that item without it.
    it("keeps at least the keep count of each item in the bags", function()
      local herbs = plan({ stack(1, 0, 1, 200), stack(1, 0, 2, 5), stack(2, 1, 1, 30) }, {}, { Herbs = 10 })[1]
      -- Bloom (1): 205 in the bags. The 200 would leave 5, under 10: it stays; the 5 leaves 200.
      -- Bloom (2) is another item: its 30 alone would leave nothing, so it stays.
      assert.same({ "0:2" }, where(herbs.toBank))
      assert.equal(10, herbs.keep)
      assert.equal(235, herbs.inBags)
    end)

    it("moves down to exactly the keep count when the stacks allow it", function()
      local ore = plan({ stack(3, 0, 1, 200), stack(3, 0, 2, 10) }, {}, { Ore = 10 })[1]
      assert.same({ "0:1" }, where(ore.toBank))
    end)

    it("moves nothing to the bank when the bags hold no more than the keep count", function()
      local ore = plan({ stack(3, 0, 1, 20), stack(3, 0, 2, 20) }, {}, { Ore = 40 })[1]
      assert.same({}, ore.toBank)
      assert.equal(40, ore.inBags)
    end)

    -- What a press has sent is on its way: the next press moves the next stack, at once.
    it("skips a stack a press has sent and one the game has locked, and counts a sent one as gone", function()
      local bags = { stack(3, 0, 1, 100), stack(3, 0, 2, 50), stack(3, 0, 3, 20, { locked = true }) }
      local ore = plan(bags, { stack(3, 12, 1, 5) }, nil, { ["0:1"] = true, ["12:1"] = true })[1]
      assert.same({ "0:2" }, where(ore.toBank))
      assert.same({}, ore.toBags)
      -- The counts are what the bags show until they show the move.
      assert.equal(170, ore.inBags)
      assert.equal(5, ore.inBank)
      -- Keep 20: the sent 100 has left, so the 50 may go and leave the locked 20.
      ore = plan(bags, {}, { Ore = 20 }, { ["0:1"] = true })[1]
      assert.same({ "0:2" }, where(ore.toBank))
      ore = plan(bags, {}, { Ore = 21 }, { ["0:1"] = true })[1]
      assert.same({}, ore.toBank)
    end)

    -- A stack the Warband Bank must not take (still refundable, or refused) stays in the bags: it is
    -- counted, it counts toward the keep, and To bank never offers it.
    it("never offers a stack the Warband Bank must not take, and counts it as kept", function()
      local ore = plan({ stack(3, 0, 1, 30, { noDeposit = true }), stack(3, 0, 2, 10) }, {}, { Ore = 30 })[1]
      assert.same({ "0:2" }, where(ore.toBank))
      assert.equal(40, ore.inBags)
    end)

    it("orders a group's items by name, then by item", function()
      GROUP[4] = "Herbs"
      NAMES[4] = "Aethril"
      local herbs = plan({ stack(2, 0, 1, 10), stack(4, 0, 2, 10), stack(1, 0, 3, 10) }, {})[1]
      assert.same({ "0:2", "0:3", "0:1" }, where(herbs.toBank))
      GROUP[4], NAMES[4] = nil, nil
    end)
  end)

  describe("keep counts", function()
    it("is 0 for every group until the player sets one, and creates nothing to read it", function()
      local db = {}
      assert.equal(0, M.KeepFor(db, "Herbs"))
      assert.is_nil(db.bankKeep)
      assert.is_true(M.SetKeep(db, "Herbs", 0))
      assert.is_nil(db.bankKeep)
    end)

    it("remembers a count per group in a versioned table made on the first one", function()
      local db = {}
      assert.is_true(M.SetKeep(db, "Herbs", 40))
      assert.same({ v = M.VERSION, groups = { Herbs = 40 } }, db.bankKeep)
      assert.equal(40, M.KeepFor(db, "Herbs"))
      assert.equal(0, M.KeepFor(db, "Ore"))
      assert.is_true(M.SetKeep(db, "Herbs", 0))
      assert.same({ v = M.VERSION, groups = {} }, db.bankKeep)
    end)

    it("refuses what is not a whole count from 0 to 9999, and a group with no name", function()
      local db = {}
      for _, bad in ipairs({ -1, 1.5, 10000, 0 / 0, math.huge, "5" }) do
        assert.is_false(M.SetKeep(db, "Herbs", bad), tostring(bad))
      end
      assert.is_false(M.SetKeep(db, "", 5))
      assert.is_false(M.SetKeep(db, nil, 5))
      assert.is_nil(db.bankKeep)
    end)

    it("reads a damaged count as 0 and starts a damaged table afresh", function()
      local db = { bankKeep = { v = M.VERSION, groups = { Herbs = "x", Ore = -3 } } }
      assert.equal(0, M.KeepFor(db, "Herbs"))
      assert.equal(0, M.KeepFor(db, "Ore"))
      db.bankKeep = "x"
      assert.is_true(M.SetKeep(db, "Ore", 5))
      assert.same({ v = M.VERSION, groups = { Ore = 5 } }, db.bankKeep)
    end)

    -- A newer GoldCap's table is a shape this one does not know: it is left as it is.
    it("neither reads nor writes a table a newer GoldCap saved", function()
      local newer = { v = M.VERSION + 1, groups = { Herbs = 40 } }
      local db = { bankKeep = newer }
      assert.is_false(M.Writable(db))
      assert.equal(0, M.KeepFor(db, "Herbs"))
      assert.is_false(M.SetKeep(db, "Herbs", 5))
      assert.same({ v = M.VERSION + 1, groups = { Herbs = 40 } }, db.bankKeep)
      assert.is_true(M.Writable({}))
    end)
  end)
end)
