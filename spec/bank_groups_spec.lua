local helper = require("spec.spec_helper")

-- Bank by group (Core/BankGroups.lua, retail only): which stacks of a followed group a press moves
-- between the bags and the Warband Bank, in which order, and how many of each item the player
-- keeps in the bags. The stacks are what UI/BankRoute.lua's reader hands over; the group of an
-- item is Core/GroupRules.lua's, faked here as a table: its key and its name, the name being the
-- key for a rule without an id (an older Companion's file).
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

  local function plan(bags, bank, keep, moving, keyed)
    return M.Plan(bags, bank, {
      groupOf = function(id)
        if keyed then
          local g = keyed[id]
          if g then return g[1], g[2], g[3], g[4], g[5] end
          return nil
        end
        return GROUP[id], GROUP[id]
      end,
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

    it("carries a group's parent and short name onto the group, nil for a top group", function()
      local groups = M.Plan({ stack(1, 0, 1, 200), stack(3, 5, 1, 50) }, {}, {
        groupOf = function(id)
          if id == 1 then return "herbs-classic", "Herbs: Classic", "herbs", "Herbs", "Classic" end
          return "Ore", "Ore"
        end,
        keepFor = function() return 0 end,
      })
      assert.equal("herbs-classic", groups[1].key)
      assert.equal("herbs", groups[1].parentKey)
      assert.equal("Herbs", groups[1].parentName)
      assert.equal("Classic", groups[1].shortName)
      assert.equal("Ore", groups[2].key)
      assert.is_nil(groups[2].parentKey)
      assert.is_nil(groups[2].parentName)
      assert.is_nil(groups[2].shortName)
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

    -- Whole stacks go while the bags keep at least the count of that item without them; what is
    -- still above the count comes out of the smallest stack left, as a split.
    it("leaves exactly the keep count of each item in the bags", function()
      local herbs = plan({ stack(1, 0, 1, 200), stack(1, 0, 2, 5), stack(2, 1, 1, 30) }, {}, { Herbs = 10 })[1]
      -- Bloom (1): 205 in the bags. The 200 would leave 5, under 10: the 5 leaves 200, then 190 of
      -- the 200 split off. Bloom (2) is another item: 20 of its 30 split off.
      assert.same({ "0:2", "0:1", "1:1" }, where(herbs.toBank))
      assert.same({ 5, 190, 20 }, { herbs.toBank[1].count, herbs.toBank[2].count, herbs.toBank[3].count })
      assert.same({ nil, 200, 30 }, { herbs.toBank[1].split, herbs.toBank[2].split, herbs.toBank[3].split })
      assert.equal(10, herbs.keep)
      assert.equal(235, herbs.inBags)
    end)

    describe("a split", function()
      local function counts(stacks)
        local out = {}
        for _, s in ipairs(stacks) do out[#out + 1] = s.count .. (s.split and ("/" .. s.split) or "") end
        return out
      end

      it("sends whole stacks and splits nothing when they add up to the surplus", function()
        local herbs = plan({ stack(1, 0, 1, 2), stack(1, 0, 2, 2), stack(1, 0, 3, 2) }, {}, { Herbs = 2 })[1]
        assert.same({ "2", "2" }, counts(herbs.toBank))
      end)

      it("lists a whole stack and a split of 1 for two stacks of 2 with a keep of 1", function()
        local herbs = plan({ stack(1, 0, 1, 2), stack(1, 0, 2, 2) }, {}, { Herbs = 1 })[1]
        -- 4 in the bags, 1 kept: 3 leave, 2 whole and 1 split off the other 2.
        assert.same({ "2", "1/2" }, counts(herbs.toBank))
        assert.same({ "0:1", "0:2" }, where(herbs.toBank))
      end)

      it("sends 20, 3 whole and 15 of the other 20 for 20, 20, 3 with a keep of 5", function()
        local herbs = plan({ stack(1, 0, 1, 20), stack(1, 0, 2, 20), stack(1, 0, 3, 3) }, {}, { Herbs = 5 })[1]
        assert.same({ "20", "3", "15/20" }, counts(herbs.toBank))
        assert.same({ "0:1", "0:3", "0:2" }, where(herbs.toBank))
        local total = 0
        for _, s in ipairs(herbs.toBank) do total = total + s.count end
        assert.equal(38, total)
      end)

      it("splits 150 off one stack of 200 with a keep of 50, as a copy of the source", function()
        local herbs = plan({ stack(1, 0, 4, 200, { link = "item:1" }) }, {}, { Herbs = 50 })[1]
        assert.same({ "150/200" }, counts(herbs.toBank))
        local part = herbs.toBank[1]
        assert.equal(1, part.itemID)
        assert.equal(0, part.bag)
        assert.equal(4, part.slot)
        assert.equal("Bloom", part.name)
        assert.equal("item:1", part.link)
      end)

      it("never splits with a keep of 0", function()
        local herbs = plan({ stack(1, 0, 1, 200), stack(1, 0, 2, 5) }, {}, {})[1]
        assert.same({ "200", "5" }, counts(herbs.toBank))
      end)

      it("never takes a locked or sent stack as the source of a split", function()
        local bags = { stack(1, 0, 1, 20, { locked = true }), stack(1, 0, 2, 30) }
        local herbs = plan(bags, {}, { Herbs = 25 })[1]
        -- 50 in the bags, 25 kept: the 30 is the only free stack, and 25 of it can go.
        assert.same({ "25/30" }, counts(herbs.toBank))
        assert.equal(2, herbs.toBank[1].slot)
        herbs = plan({ stack(1, 0, 1, 20) }, {}, { Herbs = 10 }, { ["0:1"] = true })[1]
        assert.same({}, herbs.toBank)
        -- The source of a split in flight still holds what it keeps, and is not offered again.
        herbs = plan({ stack(1, 0, 1, 10), stack(1, 0, 2, 5) }, {}, { Herbs = 10 },
          { ["0:1"] = { split = "0:2" }, ["0:2"] = true })[1]
        assert.same({}, herbs.toBank)
      end)

      it("leaves Take out whole", function()
        local herbs = plan({}, { stack(1, 12, 1, 200) }, { Herbs = 50 })[1]
        assert.same({ "200" }, counts(herbs.toBags))
      end)
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
      -- Keep 21: the sent 100 has left; 49 of the 50 split off, leaving the 1 and the locked 20.
      ore = plan(bags, {}, { Ore = 21 }, { ["0:1"] = true })[1]
      assert.same({ "0:2" }, where(ore.toBank))
      assert.equal(49, ore.toBank[1].count)
      assert.equal(50, ore.toBank[1].split)
    end)

    -- A stack the Warband Bank must not take (still refundable, or refused) stays in the bags: it is
    -- counted, it counts toward the keep, and To bank never offers it.
    it("never offers a stack the Warband Bank must not take, and counts it as kept", function()
      for _, why in ipairs({ "refund", "refused" }) do
        local ore = plan({ stack(3, 0, 1, 30, { stays = why }), stack(3, 0, 2, 10) }, {}, { Ore = 30 })[1]
        assert.same({ "0:2" }, where(ore.toBank), why)
        assert.equal(40, ore.inBags, why)
      end
    end)

    -- And the card says so: which item stays, how many, and why, one line per item and reason.
    it("names what stays in the bags and why, summed per item and reason", function()
      local herbs = plan({
        stack(1, 0, 1, 20, { stays = "refund" }), stack(1, 0, 2, 5, { stays = "refund" }),
        stack(2, 0, 3, 7, { stays = "refused" }), stack(1, 0, 4, 3, { stays = "refused" }),
        stack(1, 0, 5, 100),
      }, {})[1]
      assert.same({
        { itemID = 1, name = "Bloom", count = 25, why = "refund" },
        { itemID = 1, name = "Bloom", count = 3, why = "refused" },
        { itemID = 2, name = "Bloom", count = 7, why = "refused" },
      }, herbs.stays)
      assert.same({ "0:5" }, where(herbs.toBank))
      assert.equal(135, herbs.inBags)
      assert.same({}, plan({ stack(3, 0, 1, 10) }, {})[1].stays)
    end)

    -- What a press can never raise: an item's total in the bags and the bank together, and the
    -- group's number of stacks (a stack moves whole; landing on another only merges the two).
    -- The card sizes itself for the widest label these allow, so it does not change between presses.
    it("names every item of the group with its total here, and counts the group's stacks", function()
      local herbs = plan({ stack(1, 0, 1, 200), stack(1, 0, 2, 20, { stays = "refund" }), stack(2, 0, 3, 5) },
        { stack(1, 12, 1, 600) }, nil, { ["0:3"] = true })[1]
      assert.same({ { itemID = 1, name = "Bloom", count = 820 }, { itemID = 2, name = "Bloom", count = 5 } }, herbs.items)
      assert.equal(4, herbs.stackCount)
    end)

    -- A group is its id on goldcap.gg, not its name: two follows that read alike (a catalog group and
    -- a player's own list, or two languages that spell a group the same) share nothing.
    it("keeps two groups named alike apart, each with its own keep count, sorted by name then key", function()
      local keyed = { [1] = { "u_a1b2c3d4e5f6", "Herbs" }, [3] = { "herbs-tww", "Herbs" }, [9] = { "cloth", "Cloth" } }
      local groups = plan({ stack(1, 0, 1, 30), stack(3, 0, 2, 30), stack(9, 0, 3, 5) }, {},
        { ["herbs-tww"] = 30, Herbs = 99 }, nil, keyed)
      assert.equal(3, #groups)
      assert.same({ "Cloth", "Herbs", "Herbs" }, { groups[1].name, groups[2].name, groups[3].name })
      assert.same({ "cloth", "herbs-tww", "u_a1b2c3d4e5f6" }, { groups[1].key, groups[2].key, groups[3].key })
      -- The catalog group keeps its 30; the list (no count of its own) moves its stack.
      assert.equal(30, groups[2].keep)
      assert.same({}, groups[2].toBank)
      assert.equal(0, groups[3].keep)
      assert.same({ "0:1" }, where(groups[3].toBank))
      assert.equal(30, groups[3].inBags)
    end)

    it("names a group the key when no name comes with it", function()
      local groups = plan({ stack(3, 0, 1, 30) }, {}, nil, nil, { [3] = { "ore" } })
      assert.same({ "ore", "ore" }, { groups[1].key, groups[1].name })
    end)

    it("orders a group's items by name, then by item", function()
      GROUP[4] = "Herbs"
      NAMES[4] = "Aethril"
      local herbs = plan({ stack(2, 0, 1, 10), stack(4, 0, 2, 10), stack(1, 0, 3, 10) }, {})[1]
      assert.same({ "0:2", "0:3", "0:1" }, where(herbs.toBank))
      GROUP[4], NAMES[4] = nil, nil
    end)
  end)

  -- Shared with Core/Hoard.lua, whose plans move stacks in the same order and skip the same sent ones.
  describe("SlotKey and StackOrder", function()
    it("names a stack by where it sits", function()
      assert.equal("5:12", M.SlotKey(stack(1, 5, 12, 20)))
    end)

    it("orders stacks the biggest first, then by bag, then by slot", function()
      local stacks = { stack(1, 1, 1, 20), stack(1, 0, 4, 200), stack(1, 0, 2, 20), stack(1, 0, 9, 200) }
      table.sort(stacks, M.StackOrder)
      assert.same({ "0:4", "0:9", "0:2", "1:1" }, where(stacks))
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

    -- A follow from the site in another language, or a renamed list, keeps the group's id: the
    -- count saved under the id is still there under the new name. A rule without an id (an older
    -- Companion's file) is keyed by its name, as Core/GroupRules.lua's GroupOf answers it.
    it("keeps a count under the group's key, whatever the group is called now", function()
      local db = {}
      assert.is_true(M.SetKeep(db, "herbs-tww", 40))
      for _, name in ipairs({ "Herbs", "Kräuter", "Травы" }) do
        local group = M.Plan({ stack(1, 0, 1, 30) }, {}, {
          groupOf = function() return "herbs-tww", name end,
          keepFor = function(key) return M.KeepFor(db, key) end,
        })[1]
        assert.equal(name, group.name)
        assert.equal(40, group.keep, name)
      end
      -- A rule without an id is keyed by its name: a count of its own.
      assert.equal(0, M.KeepFor(db, "Herbs"))
      assert.is_true(M.SetKeep(db, "Herbs", 7))
      assert.same({ v = M.VERSION, groups = { ["herbs-tww"] = 40, Herbs = 7 } }, db.bankKeep)
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
