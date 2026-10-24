local helper = require("spec.spec_helper")

-- GoldCap Hoard's model (Core/Hoard.lua, retail only): what each of the window's presses moves,
-- the groups and folders it lists, and what it remembers. The groups are Core/BankGroups.lua's
-- real Plan, made from stacks shaped as UI/BankRoute.lua's reader hands them over, with the group
-- of an item faked as a table of what Core/GroupRules.lua's GroupOf answers. Prices are tables too:
-- the market value of an item and its group's usual price.
describe("Hoard", function()
  local GC, H

  -- itemID -> { key, name, parent key, parent name, short name }, as GroupOf answers. Gathering
  -- has three subgroups and Crafting two, so each is a folder; Transmog has one, so its Plate stays
  -- a group row with its whole name; Gems is a top group.
  local GROUP_OF = {
    [1] = { "herbs", "Gathering: Herbs", "gathering", "Gathering", "Herbs" },
    [2] = { "herbs", "Gathering: Herbs", "gathering", "Gathering", "Herbs" },
    [3] = { "herbs", "Gathering: Herbs", "gathering", "Gathering", "Herbs" },
    [4] = { "herbs", "Gathering: Herbs", "gathering", "Gathering", "Herbs" },
    [5] = { "herbs", "Gathering: Herbs", "gathering", "Gathering", "Herbs" },
    [6] = { "herbs", "Gathering: Herbs", "gathering", "Gathering", "Herbs" },
    [10] = { "ore", "Gathering: Ore", "gathering", "Gathering", "Ore" },
    [11] = { "ore", "Gathering: Ore", "gathering", "Gathering", "Ore" },
    [20] = { "cloth", "Gathering: Cloth", "gathering", "Gathering", "Cloth" },
    [30] = { "potions", "Crafting: Potions", "crafting", "Crafting", "Potions" },
    [31] = { "potions", "Crafting: Potions", "crafting", "Crafting", "Potions" },
    [40] = { "flasks", "Crafting: Flasks", "crafting", "Crafting", "Flasks" },
    [50] = { "plate", "Transmog: Plate", "transmog", "Transmog", "Plate" },
    [60] = { "gems", "Gems" },
  }
  local NAMES = {
    [1] = "Tranquility Bloom", [2] = "Argentleaf", [3] = "Azeroot", [4] = "Sanguithorn", [5] = "Mana Lily",
    [6] = "Luredrop", [10] = "Copper Ore", [11] = "Tin Ore", [20] = "Bright Linen",
    [30] = "Enlightenment Tonic", [31] = "Mana Potion", [40] = "Flask of the Magisters",
    [50] = "Velvet Cinch", [60] = "Ruby", [99] = "Linen Cloth",
  }
  -- The market value of each item, in copper. Luredrop (6) has none yet.
  local VALUE = {
    [1] = 50, [2] = 30, [3] = 20, [4] = 10, [5] = 10, [10] = 5, [11] = 8, [20] = 1, [30] = 400,
    [31] = 300, [40] = 2000, [50] = 9000, [60] = 700,
  }
  local function valueOf(id) return VALUE[id] end
  local function iconOf(id) return 100000 + id end
  local function groupOf(id)
    local g = GROUP_OF[id]
    if g then return g[1], g[2], g[3], g[4], g[5] end
    return nil
  end

  local function stack(itemID, bag, slot, count, over)
    local s = { itemID = itemID, bag = bag, slot = slot, count = count, name = NAMES[itemID], icon = 100000 + itemID }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
  end

  local function where(stacks)
    local out = {}
    for _, s in ipairs(stacks) do out[#out + 1] = s.bag .. ":" .. s.slot end
    return out
  end

  local function plan(bags, bank, keep, groupOfFn)
    return GC.BankGroups.Plan(bags, bank, {
      groupOf = groupOfFn or groupOf,
      keepFor = function(key) return (keep or {})[key] or 0 end,
    })
  end

  -- Every group with something in the bags and the bank. Worth here: Herbs 5,500 (Luredrop has
  -- no value), Ore 1,400, Cloth 1,000, so Gathering 7,900; Potions 5,200, Flasks 6,000, so
  -- Crafting 11,200; Plate 9,000; Gems 700.
  local function world()
    return plan({
      stack(1, 0, 1, 20), stack(2, 0, 2, 10), stack(3, 0, 3, 5), stack(4, 0, 4, 5), stack(5, 0, 5, 5),
      stack(6, 0, 6, 100), stack(10, 1, 1, 200), stack(30, 2, 1, 10), stack(60, 2, 2, 1),
      stack(99, 2, 3, 20),
    }, {
      stack(1, 6, 1, 80), stack(11, 6, 2, 50), stack(20, 6, 3, 1000), stack(31, 6, 4, 4),
      stack(40, 6, 5, 3), stack(50, 6, 6, 1),
    })
  end

  local function rows(groups, opts)
    local o = { valueOf = valueOf, iconOf = iconOf, filter = "all", sort = "value" }
    for k, v in pairs(opts or {}) do o[k] = v end
    return H.Rows(groups, o)
  end

  -- The rows (or, with `which`, another list of the answer, such as foldedRows) as "name" (depth 0)
  -- or "  name" (depth 1, under a folder).
  local function names(result, which)
    local out = {}
    for _, row in ipairs(result[which or "rows"]) do out[#out + 1] = (row.depth == 1 and "  " or "") .. row.name end
    return out
  end

  local function rowNamed(result, name, which)
    for _, row in ipairs(result[which or "rows"]) do
      if row.name == name then return row end
    end
    return nil
  end

  local function allOpen() return true end

  local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepCopy(v) end
    return out
  end

  before_each(function()
    GC = helper.loadModule("Core/NameMatch.lua")
    helper.loadModule("Core/BankGroups.lua", GC)
    helper.loadModule("Core/Hoard.lua", GC)
    H = GC.Hoard
  end)

  it("has the window's numbers", function()
    assert.equal(110, H.PRICE_UP_PCT)
    assert.equal(8, H.SEARCH_MIN_GROUPS)
    assert.equal(5, H.ICONS)
    assert.equal(1, H.VERSION)
  end)

  describe("IsPriceUp", function()
    local cases = {
      { "exactly 110% of the usual price", 110, 100, true },
      { "just under it", 109, 100, false },
      { "far above it", 500, 100, true },
      { "an odd usual price met exactly", 1111, 1010, true },
      { "an item with no market value", nil, 100, false },
      { "an item with no usual price", 500, nil, false },
      { "a usual price of 0", 500, 0, false },
      { "a market value of 0", 0, 100, false },
      { "a price that is not a number", "500", 100, false },
      { "a price that is not a number at all", 0 / 0, 100, false },
    }
    for _, case in ipairs(cases) do
      it(case[1], function()
        assert.equal(case[4], H.IsPriceUp(7, function() return case[2] end, function() return case[3] end))
      end)
    end

    it("asks both prices about the item it is asked about", function()
      local asked = {}
      H.IsPriceUp(7, function(id) asked[#asked + 1] = "now " .. id; return 200 end,
        function(id) asked[#asked + 1] = "usual " .. id; return 100 end)
      assert.same({ "now 7", "usual 7" }, asked)
    end)
  end)

  describe("PricesUp", function()
    -- Argentleaf (2) has a usual price and no market value yet, Azeroot (3) the other way round.
    local USUAL = { [40] = 1500, [31] = 300, [30] = 400, [60] = 100, [99] = 1, [1] = 10, [2] = 10 }
    local NOW = { [40] = 2000, [31] = 330, [30] = 400, [60] = 1000, [99] = 999, [1] = 50, [3] = 500 }
    local function up(bank, moving)
      return H.PricesUp(bank, {
        groupOf = groupOf,
        valueOf = function(id) return NOW[id] end,
        usualOf = function(id) return USUAL[id] end,
        moving = moving,
      })
    end

    it("takes out each followed item at 110% of its usual price or more, the most worth first", function()
      local out = up({
        stack(40, 6, 1, 3), stack(30, 6, 2, 10), stack(31, 6, 3, 4), stack(40, 6, 4, 5), stack(99, 6, 5, 10),
      })
      -- Flasks 8 at 2,000 (133% of 1,500) and Mana Potion 4 at 330 (110%); the Tonic sells at its
      -- usual price; Linen Cloth (99) is in no followed group, however high its price.
      assert.same({
        { itemID = 40, name = "Flask of the Magisters", count = 8, now = 2000, usual = 1500 },
        { itemID = 31, name = "Mana Potion", count = 4, now = 330, usual = 300 },
      }, out.items)
      assert.same({ "6:4", "6:1", "6:3" }, where(out.stacks))
      assert.equal(8 * 2000 + 4 * 330, out.worth)
    end)

    it("never lists an item missing either price", function()
      local out = up({ stack(2, 6, 1, 10), stack(3, 6, 2, 10), stack(6, 6, 3, 10) })
      assert.same({ stacks = {}, items = {}, worth = 0 }, out)
    end)

    it("leaves a stack the game holds or a press has sent", function()
      local out = up({ stack(60, 6, 1, 1, { locked = true }), stack(1, 6, 2, 20), stack(1, 6, 3, 30) }, { ["6:3"] = true })
      assert.same({ "6:2" }, where(out.stacks))
      assert.same({ { itemID = 1, name = "Tranquility Bloom", count = 20, now = 50, usual = 10 } }, out.items)
    end)

    it("has nothing to take out of an empty bank", function()
      assert.same({ stacks = {}, items = {}, worth = 0 }, up({}))
    end)

    it("asks each item's group and prices once, however many stacks it has", function()
      local asked = {}
      local function count(what) return function(id)
        asked[what .. " " .. id] = (asked[what .. " " .. id] or 0) + 1
        if what == "group" then return groupOf(id) end
        return (what == "now" and NOW or USUAL)[id]
      end end
      local out = H.PricesUp({ stack(40, 6, 1, 3), stack(40, 6, 2, 5), stack(40, 6, 3, 1), stack(30, 6, 4, 10),
        stack(30, 6, 5, 10) }, { groupOf = count("group"), valueOf = count("now"), usualOf = count("usual") })
      assert.equal(9, out.items[1].count)
      assert.same({ ["group 40"] = 1, ["now 40"] = 1, ["usual 40"] = 1, ["group 30"] = 1, ["now 30"] = 1,
        ["usual 30"] = 1 }, asked)
    end)

    it("takes out nothing when asked with no prices at all", function()
      assert.same({ stacks = {}, items = {}, worth = 0 }, H.PricesUp({ stack(40, 6, 1, 3) }))
      assert.same({ stacks = {}, items = {}, worth = 0 }, H.PricesUp({ stack(40, 6, 1, 3) }, {}))
    end)
  end)

  describe("ForCrafts", function()
    it("takes the fewest whole stacks of any quality that cover what the bags lack, the biggest first", function()
      local out = H.ForCrafts({ { ids = { 1, 2 }, need = 100, have = 20, missing = 80 } },
        { stack(1, 6, 1, 60), stack(2, 6, 2, 30), stack(1, 6, 3, 10), stack(2, 6, 4, 40) })
      -- 60 leaves 20 to find; the 30 and the 40 each cover it, and the 30 brings the least extra.
      assert.same({ "6:1", "6:2" }, where(out.stacks))
      assert.same({ { itemID = 1, name = "Tranquility Bloom", need = 100, inBags = 20, taken = 90 } }, out.items)
    end)

    local cases = {
      { "one stack that covers it all, the smallest that does", 10, { 200, 10, 5 }, { "6:2" } },
      { "the smallest covering stack after the biggest", 215, { 200, 20, 10 }, { "6:1", "6:2" } },
      { "every stack when the bank holds less than is missing", 50, { 20, 10 }, { "6:1", "6:2" } },
      { "the first of two alike when either covers", 10, { 30, 30 }, { "6:1" } },
      { "nothing when the bank holds none", 10, {}, {} },
    }
    for _, case in ipairs(cases) do
      it("takes " .. case[1], function()
        local bank = {}
        for i, count in ipairs(case[3]) do bank[i] = stack(1, 6, i, count) end
        local out = H.ForCrafts({ { ids = { 1 }, need = case[2], have = 0, missing = case[2] } }, bank)
        assert.same(case[4], where(out.stacks))
      end)
    end

    it("lists only the reagents it takes, in the queue's order, and skips a currency", function()
      local out = H.ForCrafts({
        { currency = 3008, need = 100, have = 0, missing = 100 },
        { ids = { 40 }, need = 10, have = 5, missing = 5 },
        { ids = { 3 }, need = 4, have = 0, missing = 4 },
        { ids = { 30, 31 }, need = 12, have = 2, missing = 10 },
      }, { stack(40, 6, 1, 3), stack(40, 6, 2, 1), stack(31, 6, 3, 20) })
      assert.same({
        { itemID = 40, name = "Flask of the Magisters", need = 10, inBags = 5, taken = 4 },
        { itemID = 31, name = "Mana Potion", need = 12, inBags = 2, taken = 20 },
      }, out.items)
      assert.same({ "6:1", "6:2", "6:3" }, where(out.stacks))
    end)

    it("never takes one stack twice, nor one the game holds or a press has sent", function()
      local out = H.ForCrafts({
        { ids = { 1 }, need = 30, have = 0, missing = 30 },
        { ids = { 1, 2 }, need = 30, have = 0, missing = 30 },
      }, { stack(1, 6, 1, 30), stack(1, 6, 2, 40, { locked = true }), stack(2, 6, 3, 50), stack(2, 6, 4, 60) },
        { ["6:4"] = true })
      assert.same({ "6:1", "6:3" }, where(out.stacks))
    end)

    it("has nothing to take with nothing missing", function()
      assert.same({ stacks = {}, items = {} }, H.ForCrafts({}, { stack(1, 6, 1, 30) }))
      assert.same({ stacks = {}, items = {} }, H.ForCrafts(nil, nil))
    end)
  end)

  describe("PutAway", function()
    it("stores every group's To bank stack but the items left out, summed per item", function()
      local groups = plan({ stack(2, 0, 1, 10), stack(2, 0, 2, 15), stack(1, 0, 3, 20), stack(30, 1, 1, 10),
        stack(60, 1, 2, 1) }, {}, { gems = 5 })
      local out = H.PutAway(groups, { [1] = true, [30] = true })
      assert.same({ "0:2", "0:1" }, where(out.stacks))
      assert.same({ { itemID = 2, name = "Argentleaf", count = 25 } }, out.items)
    end)

    it("stores the whole To bank of every group with nothing left out", function()
      local groups = world()
      local out = H.PutAway(groups)
      local want = {}
      for _, group in ipairs(groups) do
        for _, s in ipairs(group.toBank) do want[#want + 1] = s.bag .. ":" .. s.slot end
      end
      assert.same(want, where(out.stacks))
      assert.equal(9, #out.stacks)
    end)
  end)

  describe("Rows", function()
    it("folds two or more subgroups of one parent into a folder, and a lone subgroup stays a group", function()
      local result = rows(world(), { sort = "name" })
      assert.same({ "Crafting", "Gathering", "Gems", "Transmog: Plate" }, names(result))
      local gathering = result.rows[2]
      assert.equal("folder", gathering.kind)
      assert.equal("gathering", gathering.key)
      assert.equal(0, gathering.depth)
      assert.equal(3, gathering.childCount)
      assert.is_false(gathering.open)
      assert.is_nil(gathering.group)
      local plate = result.rows[4]
      assert.equal("group", plate.kind)
      assert.equal("plate", plate.key)
      assert.equal(0, plate.depth)
      assert.equal("plate", plate.group.key)
      assert.equal(7, result.total)
    end)

    it("lists an open folder's groups under it by their short names", function()
      local result = rows(world(), { sort = "name", folderOpen = function(key) return key == "gathering" end })
      assert.same({ "Crafting", "Gathering", "  Cloth", "  Herbs", "  Ore", "Gems", "Transmog: Plate" }, names(result))
      assert.same({ "cloth", "herbs", "ore" }, result.rows[2].children)
      assert.is_true(result.rows[2].open)
      assert.equal(1, result.rows[4].depth)
      assert.equal("herbs", result.rows[4].key)
      assert.equal("Gathering: Herbs", result.rows[4].group.name)
    end)

    it("shows a group's five most valuable items, then by name, with their totals and the rest as more", function()
      local herbs = rowNamed(rows(world(), { folderOpen = allOpen }), "Herbs")
      -- Mana Lily and Sanguithorn are worth the same; Luredrop has no value and is the sixth.
      assert.same({
        { itemID = 1, icon = 100001, count = 100 }, { itemID = 2, icon = 100002, count = 10 },
        { itemID = 3, icon = 100003, count = 5 }, { itemID = 5, icon = 100005, count = 5 },
        { itemID = 4, icon = 100004, count = 5 },
      }, herbs.icons)
      assert.equal(1, herbs.more)
      assert.equal(0, rowNamed(rows(world(), { folderOpen = allOpen }), "Ore").more)
    end)

    it("shows a folder's first icon of each group in its order, and its other items as more", function()
      local gathering = rowNamed(rows(world()), "Gathering")
      assert.same({ { itemID = 1, icon = 100001, count = 100 }, { itemID = 10, icon = 100010, count = 200 },
        { itemID = 20, icon = 100020, count = 1000 } }, gathering.icons)
      -- Herbs has 6 items, Ore 2 and Cloth 1.
      assert.equal(6, gathering.more)
    end)

    it("stops a folder's icons at five", function()
      local five = {}
      for i = 1, 7 do
        GROUP_OF[200 + i] = { "sub" .. i, "Many: " .. i, "many", "Many", tostring(i) }
        five[i] = stack(200 + i, 0, i, 1)
      end
      local many = rows(plan(five, {}))
      assert.equal(1, #many.rows)
      assert.equal(5, #many.rows[1].icons)
      assert.equal(2, many.rows[1].more)
      for i = 1, 7 do GROUP_OF[200 + i] = nil end
    end)

    it("is worth each item's count at its market value, in whole copper, and nothing without one", function()
      local result = rows(world(), { folderOpen = allOpen })
      assert.equal(5500, rowNamed(result, "Herbs").worth)
      assert.equal(7900, rowNamed(result, "Gathering").worth)
      assert.equal(11200, rowNamed(result, "Crafting").worth)
      assert.equal(9000, rowNamed(result, "Transmog: Plate").worth)
      local odd = rows(plan({ stack(1, 0, 1, 3) }, {}), { valueOf = function() return 2.5 end })
      assert.equal(7, odd.rows[1].worth)
      assert.equal(0, rows(plan({ stack(1, 0, 1, 3) }, {}), { valueOf = false }).rows[1].worth)
    end)

    it("carries a group's counts and moves, and a folder's over the groups it lists", function()
      local result = rows(world(), { folderOpen = allOpen })
      local herbs, gathering = rowNamed(result, "Herbs"), rowNamed(result, "Gathering")
      assert.equal(145, herbs.inBags)
      assert.equal(80, herbs.inBank)
      -- The row's lists are its own: the window may change them without touching the plan.
      assert.same(herbs.group.toBank, herbs.toBank)
      assert.are_not.equal(herbs.group.toBank, herbs.toBank)
      assert.same(herbs.group.toBags, herbs.toBags)
      assert.are_not.equal(herbs.group.toBags, herbs.toBags)
      assert.equal(345, gathering.inBags)
      assert.equal(1130, gathering.inBank)
      -- Children by worth: Herbs, Ore, Cloth.
      assert.same({ "herbs", "ore", "cloth" }, gathering.children)
      -- Each group's To bank as Plan orders it: its items by name, then Ore's.
      assert.same({ "0:2", "0:3", "0:6", "0:5", "0:4", "0:1", "1:1" }, where(gathering.toBank))
      assert.same({ "6:1", "6:2", "6:3" }, where(gathering.toBags))
    end)

    it("names the play of a group's rule, asked with its first item, and none for a folder", function()
      local result = rows(world(), { folderOpen = allOpen, playOf = function(id)
        if id == 60 then return "stock" end
        if id == 2 then return "gather" end
        return nil
      end })
      assert.equal("stock", rowNamed(result, "Gems").play)
      assert.equal("gather", rowNamed(result, "Herbs").play)
      assert.is_nil(rowNamed(result, "Gathering").play)
      assert.is_nil(rowNamed(rows(world()), "Gems").play)
    end)

    -- Rows only reads the plan: the window paints from it again after every move.
    it("leaves the Plan groups as they were, but for the groups it remembers as shown", function()
      local groups = world()
      local before = deepCopy(groups)
      local shown = {}
      rows(groups, { filter = "move", shown = shown, query = "o", sort = "name", folderOpen = allOpen })
      rows(groups, { filter = "all", shown = shown, playOf = function() return "gather" end })
      assert.same(before, groups)
      assert.is_true(shown.herbs)
    end)

    -- A followed top group can have the key of another group's parent (both "Gathering" and
    -- "Gathering: Herbs" followed): two rows, the folder first, whatever the sort.
    it("lists a top group and a folder of the same key as two rows in a fixed order", function()
      local groups = plan({ stack(1, 0, 1, 20), stack(10, 0, 2, 200), stack(70, 0, 3, 1) }, {}, nil, function(id)
        if id == 70 then return "gathering", "Gathering" end
        return groupOf(id)
      end)
      for _, sort in ipairs({ "name", "value" }) do
        local result = rows(groups, { sort = sort, valueOf = function() return nil end })
        assert.same({ "Gathering", "Gathering" }, names(result), sort)
        assert.same({ "folder", "group" }, { result.rows[1].kind, result.rows[2].kind }, sort)
        assert.same({ "gathering", "gathering" }, { result.rows[1].key, result.rows[2].key }, sort)
      end
    end)

    describe("the filter", function()
      -- Bags only. Herbs and Potions have stacks to store; Ore, Cloth, Gems and Flasks keep all
      -- they have in the bags.
      local function bagsOnly(keep)
        return plan({ stack(1, 0, 1, 20), stack(10, 0, 2, 200), stack(20, 0, 3, 30), stack(60, 0, 4, 1),
          stack(30, 0, 5, 10), stack(40, 0, 6, 3) }, {},
          keep or { ore = 1000, cloth = 1000, gems = 5, flasks = 10 })
      end

      it("lists under To move here only the groups with something to move, and counts the rest", function()
        local result = rows(bagsOnly(), { filter = "move", folderOpen = allOpen })
        assert.same({ "Crafting", "  Potions", "Gathering", "  Herbs" }, names(result))
        assert.equal(4, result.folded)
        assert.equal(6, result.total)
        assert.equal(2, result.toMove)
      end)

      -- A folder is made from all its groups, so it neither comes nor goes as their moves finish.
      it("keeps a folder with one group left to show, still counting all of its groups", function()
        local gathering = rowNamed(rows(bagsOnly(), { filter = "move" }), "Gathering")
        assert.equal("folder", gathering.kind)
        assert.same({ "herbs" }, gathering.children)
        assert.equal(3, gathering.childCount)
        assert.same({ "0:1" }, where(gathering.toBank))
        assert.equal(20, gathering.inBags)
      end)

      it("leaves out a folder none of whose groups shows", function()
        local result = rows(bagsOnly({ herbs = 1000, ore = 1000, cloth = 1000, gems = 5, flasks = 10 }), { filter = "move" })
        assert.same({ "Crafting" }, names(result))
        assert.equal(5, result.folded)
      end)

      it("lists everything under All and folds nothing", function()
        local result = rows(bagsOnly(), { filter = "all" })
        assert.same({ "Crafting", "Gathering", "Gems" }, names(result))
        assert.equal(0, result.folded)
        assert.equal(2, result.toMove)
      end)

      it("lists a group whose only line is a stack that stays in the bags", function()
        local groups = plan({ stack(60, 0, 1, 1, { stays = "refund" }) }, {})
        assert.same({ "Gems" }, names(rows(groups, { filter = "move" })))
      end)

      -- As the bank card did: a group shown in this visit stays listed after its last move, so a
      -- press never takes the row from under the cursor.
      it("keeps listing a group shown earlier in the visit, and remembers each group it lists to move", function()
        local shown = { ore = true }
        local result = rows(bagsOnly(), { filter = "move", shown = shown, folderOpen = allOpen })
        assert.same({ "Crafting", "  Potions", "Gathering", "  Herbs", "  Ore" }, names(result))
        assert.equal(3, result.toMove)
        assert.equal(3, result.folded)
        assert.same({ ore = true, herbs = true, potions = true }, shown)
        -- Herbs' moves are done: it stays.
        result = rows(bagsOnly({ herbs = 1000, ore = 1000, cloth = 1000, gems = 5, flasks = 10 }),
          { filter = "move", shown = shown, folderOpen = allOpen })
        assert.same({ "Crafting", "  Potions", "Gathering", "  Herbs", "  Ore" }, names(result))
      end)

      -- The fold line opens onto the groups it counts, as rows like the others. A folder whose
      -- groups fall on both sides of the line is on both, each time over its groups on that side.
      it("hands the folded groups to the fold line as rows, a folder on both sides with its own groups", function()
        local result = rows(bagsOnly(), { filter = "move", folderOpen = allOpen })
        assert.same({ "Crafting", "  Flasks", "Gathering", "  Ore", "  Cloth", "Gems" }, names(result, "foldedRows"))
        local listed, folded = rowNamed(result, "Gathering"), rowNamed(result, "Gathering", "foldedRows")
        assert.same({ "herbs" }, listed.children)
        assert.same({ "ore", "cloth" }, folded.children)
        assert.equal(3, listed.childCount)
        assert.equal(3, folded.childCount)
        assert.equal(1000, listed.worth)
        assert.equal(1030, folded.worth)
        assert.same({ { itemID = 1, icon = 100001, count = 20 } }, listed.icons)
        assert.same({ { itemID = 10, icon = 100010, count = 200 }, { itemID = 20, icon = 100020, count = 30 } },
          folded.icons)
        assert.equal(0, folded.more)
        assert.equal("group", rowNamed(result, "Gems", "foldedRows").kind)
      end)

      it("folds nothing under All, and closed folders under the line show no groups", function()
        assert.same({}, rows(bagsOnly(), { filter = "all" }).foldedRows)
        assert.same({ "Crafting", "Gathering", "Gems" }, names(rows(bagsOnly(), { filter = "move" }), "foldedRows"))
      end)
    end)

    describe("the search", function()
      it("finds a group by an item's name and shows its folder with that group alone", function()
        local result = rows(world(), { query = "bloom", folderOpen = allOpen })
        assert.same({ "Gathering", "  Herbs" }, names(result))
        assert.same({ "herbs" }, result.rows[1].children)
        assert.equal(3, result.rows[1].childCount)
        assert.equal(7, result.total)
      end)

      local cases = {
        { "a group's name, whatever its case", "GEMS", { "Gems" } },
        { "a subgroup's short name", "flasks", { "Crafting", "  Flasks" } },
        { "a folder's name, with all its groups", "crafting", { "Crafting", "  Flasks", "  Potions" } },
        { "words inside a name", "plate", { "Transmog: Plate" } },
        { "nothing for a dot, which is no pattern", ".", {} },
        { "nothing for a percent sign", "%a", {} },
        { "everything for a blank query", "  ", { "Crafting", "  Flasks", "  Potions", "Transmog: Plate",
          "Gathering", "  Herbs", "  Ore", "  Cloth", "Gems" } },
      }
      for _, case in ipairs(cases) do
        it("finds " .. case[1], function()
          assert.same(case[3], names(rows(world(), { query = case[2], folderOpen = allOpen })))
        end)
      end

      it("finds a name in the player's language, case-blind", function()
        NAMES[60] = "Рубин"
        local result = rows(world(), { query = "РУБ" })
        NAMES[60] = "Ruby"
        assert.same({ "Gems" }, names(result))
      end)

      it("counts as folded only the groups the search finds", function()
        local groups = plan({ stack(1, 0, 1, 20), stack(10, 0, 2, 200), stack(60, 0, 3, 1) }, {}, { ore = 1000, gems = 5 })
        local result = rows(groups, { filter = "move", query = "ore" })
        assert.same({}, names(result))
        assert.equal(1, result.folded)
        assert.same({ "Gathering", "  Ore" }, names(result, "foldedRows"))
        assert.equal(3, result.total)
        assert.equal(1, result.toMove)
      end)

      -- What the search found is on the screen, inside a closed folder too; the folder is not
      -- opened for good, so clearing the search closes it again.
      it("shows the groups it finds inside a closed folder, without opening the folder for good", function()
        local db = {}
        local result = rows(world(), { query = "bloom", folderOpen = function(key) return H.FolderOpen(db, key) end })
        assert.same({ "Gathering", "  Herbs" }, names(result))
        assert.is_false(result.rows[1].open)
        assert.is_true(result.rows[1].forcedOpen)
        assert.same({}, db)
        local open = rows(world(), { query = "bloom", folderOpen = allOpen })
        assert.is_true(open.rows[1].open)
        assert.is_false(open.rows[1].forcedOpen)
        local cleared = rows(world(), { query = "" })
        assert.same({ "Crafting", "Transmog: Plate", "Gathering", "Gems" }, names(cleared))
        assert.is_false(cleared.rows[1].forcedOpen)
      end)
    end)

    describe("the sort", function()
      it("puts the most worth first, a folder by its own worth and its groups by theirs", function()
        assert.same({ "Crafting", "  Flasks", "  Potions", "Transmog: Plate", "Gathering", "  Herbs", "  Ore",
          "  Cloth", "Gems" }, names(rows(world(), { folderOpen = allOpen })))
      end)

      it("sorts by name, a folder's groups too", function()
        assert.same({ "Crafting", "  Flasks", "  Potions", "Gathering", "  Cloth", "  Herbs", "  Ore", "Gems",
          "Transmog: Plate" }, names(rows(world(), { sort = "name", folderOpen = allOpen })))
      end)

      it("sorts the same worth by name, and the same name by key", function()
        local keyed = { [1] = { "b-key", "Alike" }, [2] = { "a-key", "Alike" }, [3] = { "c", "Zed" } }
        local groups = plan({ stack(1, 0, 1, 1), stack(2, 0, 2, 1), stack(3, 0, 3, 1) }, {}, nil, function(id)
          local g = keyed[id]
          if g then return g[1], g[2] end
          return nil
        end)
        local same = rows(groups, { valueOf = function() return 10 end })
        local keys = {}
        for _, row in ipairs(same.rows) do keys[#keys + 1] = row.key end
        assert.same({ "a-key", "b-key", "c" }, keys)
        same = rows(groups, { sort = "name" })
        keys = {}
        for _, row in ipairs(same.rows) do keys[#keys + 1] = row.key end
        assert.same({ "a-key", "b-key", "c" }, keys)
      end)

      -- As the player reads them: case-blind and accent-blind (Core/NameMatch.lua), where the bytes
      -- would put every lowercase and accented name after Z. Two names that read alike keep an order.
      it("sorts names as the player reads them, whatever their case or accents", function()
        local named = { [301] = { "z-lower", "zinc" }, [302] = { "eclat", "Éclat" }, [303] = { "z-upper", "Zinc" },
          [304] = { "mithril", "mithril" } }
        local groups = plan({ stack(301, 0, 1, 1), stack(302, 0, 2, 1), stack(303, 0, 3, 1), stack(304, 0, 4, 1) }, {},
          nil, function(id)
            local g = named[id]
            if g then return g[1], g[2] end
            return nil
          end)
        assert.same({ "Éclat", "mithril", "Zinc", "zinc" }, names(rows(groups, { sort = "name" })))
        assert.same({ "Éclat", "mithril", "Zinc", "zinc" }, names(rows(groups, { valueOf = function() return nil end })))
      end)

      it("shows icons of the same worth by name as the player reads them", function()
        NAMES[2], NAMES[3] = "Zinc Ore", "éclat Dust"
        local herbs = rows(plan({ stack(2, 0, 1, 1), stack(3, 0, 2, 1) }, {}), { valueOf = function() return 10 end }).rows[1]
        NAMES[2], NAMES[3] = "Argentleaf", "Azeroot"
        assert.same({ 3, 2 }, { herbs.icons[1].itemID, herbs.icons[2].itemID })
      end)
    end)

    -- The Review Focus: 40 followed groups, half of them subgroups of 6 parents.
    describe("with 40 groups", function()
      local PARENT = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6 }
      local function forty()
        local bags, keep, of = {}, {}, {}
        for i = 1, 40 do
          local id = 1000 + i
          local key, name = ("g%02d"):format(i), ("Group %02d"):format(i)
          if i > 20 then
            local p = PARENT[i - 20]
            of[id] = { key, "Parent " .. p .. ": " .. name, "p" .. p, "Parent " .. p, name }
          else
            of[id] = { key, name }
          end
          bags[i] = { itemID = id, bag = 0, slot = i, count = i, name = "Item " .. i }
          -- The odd ones have a stack to store; the even ones keep all they have.
          if i % 2 == 0 then keep[key] = 1000 end
        end
        return plan(bags, {}, keep, function(id)
          local g = of[id]
          if g then return g[1], g[2], g[3], g[4], g[5] end
          return nil
        end)
      end

      it("shows 20 groups and 6 folders under All, every folder closed", function()
        local result = rows(forty(), { sort = "name" })
        assert.equal(26, #result.rows)
        assert.equal(40, result.total)
        local counts = {}
        for _, row in ipairs(result.rows) do
          if row.kind == "folder" then counts[#counts + 1] = row.childCount end
        end
        assert.same({ 5, 4, 3, 3, 3, 2 }, counts)
      end)

      it("shows 10 groups and the 6 folders to move here, and folds the other 20 groups", function()
        local result = rows(forty(), { filter = "move", sort = "name" })
        assert.equal(16, #result.rows)
        assert.equal(20, result.toMove)
        assert.equal(20, result.folded)
        local listed = {}
        for _, row in ipairs(result.rows) do
          if row.kind == "folder" then listed[#listed + 1] = #row.children end
        end
        assert.same({ 3, 2, 1, 2, 1, 1 }, listed)
      end)

      it("lists every group once with every folder open", function()
        local result = rows(forty(), { folderOpen = allOpen })
        local seen = 0
        for _, row in ipairs(result.rows) do
          if row.kind == "group" then seen = seen + 1 end
        end
        assert.equal(40, seen)
        assert.equal(46, #result.rows)
      end)
    end)

    it("lists nothing with no group", function()
      assert.same({ rows = {}, foldedRows = {}, folded = 0, total = 0, toMove = 0 }, H.Rows({}, {}))
    end)
  end)

  describe("CheckState", function()
    local folder = { kind = "folder", children = { "herbs", "ore", "cloth" } }
    local cases = {
      { "off with none of its groups selected", {}, "off" },
      { "mixed with some", { ore = true }, "mixed" },
      { "on with all", { herbs = true, ore = true, cloth = true }, "on" },
      { "off with only groups of another folder", { potions = true }, "off" },
    }
    for _, case in ipairs(cases) do
      it("is " .. case[1], function() assert.equal(case[3], H.CheckState(folder, case[2])) end)
    end

    it("is off for a folder with no group listed, and with no selection", function()
      assert.equal("off", H.CheckState({ kind = "folder", children = {} }, { herbs = true }))
      assert.equal("off", H.CheckState(folder, nil))
    end)
  end)

  describe("Check", function()
    local folder = { kind = "folder", key = "trade", children = { "herbs", "ore", "cloth" } }

    it("selects every group of a folder that is off, and keeps the others", function()
      local selected = { potions = true }
      H.Check(folder, selected)
      assert.same({ potions = true, herbs = true, ore = true, cloth = true }, selected)
    end)

    it("clears every group of a folder that is on or mixed, and keeps the others", function()
      for _, start in ipairs({ { herbs = true, ore = true, cloth = true }, { ore = true } }) do
        start.potions = true
        H.Check(folder, start)
        assert.same({ potions = true }, start)
      end
    end)

    it("checks a group that is off and clears one that is on", function()
      local selected = {}
      H.Check({ kind = "group", key = "herbs" }, selected)
      assert.same({ herbs = true }, selected)
      H.Check({ kind = "group", key = "herbs" }, selected)
      assert.same({}, selected)
    end)
  end)

  describe("Selection", function()
    it("totals the selected groups, a closed folder's included, each once", function()
      local groups = world()
      local sel = H.Selection(groups, { herbs = true, flasks = true, plate = true, gone = true }, valueOf)
      assert.equal(3, sel.groups)
      assert.same({ "0:2", "0:3", "0:6", "0:5", "0:4", "0:1" }, where(sel.toBank))
      assert.same({ "6:5", "6:1", "6:6" }, where(sel.toBags))
      assert.equal(5500 + 6000 + 9000, sel.worth)
    end)

    it("is empty with nothing selected", function()
      assert.same({ groups = 0, toBank = {}, toBags = {}, worth = 0 }, H.Selection(world(), {}, valueOf))
      assert.same({ groups = 0, toBank = {}, toBags = {}, worth = 0 }, H.Selection(world(), nil, valueOf))
    end)
  end)

  describe("MakeRoom", function()
    -- What stays was decided by the reader: a refundable stack toward the Warband Bank, or one the
    -- bank refuses, comes marked `stays`, and a soulbound one is not read for the Warband Bank.
    it("moves every stack the bank takes, the biggest first, then by bag and slot", function()
      local stacks = H.MakeRoom({
        stack(1, 0, 1, 20), stack(2, 1, 3, 200), stack(3, 0, 5, 200, { stays = "refund" }),
        stack(4, 0, 7, 50, { stays = "refused" }), stack(5, 0, 8, 50, { locked = true }), stack(6, 0, 2, 200),
        stack(10, 4, 1, 1),
      }, { ["4:1"] = true })
      assert.same({ "0:2", "1:3", "0:1" }, where(stacks))
    end)

    it("has nothing to move from empty bags", function()
      assert.same({}, H.MakeRoom({}))
      assert.same({}, H.MakeRoom(nil))
    end)
  end)

  describe("Remember", function()
    it("remembers the bank, the time and how many of each item went", function()
      assert.same({ bankType = 2, at = 1000, items = { [1] = 50, [2] = 5 } },
        H.Remember(2, 1000, { stack(1, 0, 1, 20), stack(1, 0, 2, 30), stack(2, 0, 3, 5) }))
      assert.same({ bankType = 0, at = 5, items = {} }, H.Remember(0, 5, {}))
    end)
  end)

  describe("PutBack", function()
    local room = { bankType = 2, at = 1000, items = { [1] = 70, [2] = 5, [3] = 10 } }

    it("takes back each item's remembered count in the fewest stacks, the biggest first", function()
      local stacks = H.PutBack(room, {
        stack(1, 6, 1, 30), stack(1, 6, 2, 20), stack(1, 6, 3, 40), stack(2, 6, 4, 200), stack(3, 6, 5, 4),
        stack(4, 6, 6, 99), stack(1, 6, 7, 5, { locked = true }), stack(3, 6, 8, 2),
      }, { ["6:8"] = true })
      -- Bloom: 40 and 30 make the 70. Argentleaf: the 5 that went merged into a stack the bank
      -- held, and a stack moves whole, so the 200 comes back. Azeroot: another character took
      -- some, so the 4 that are there.
      assert.same({ "6:3", "6:1", "6:4", "6:5" }, where(stacks))
    end)

    -- Deposits merge into the stacks the bank already held: what went in may now be part of a
    -- bigger stack. The biggest stacks while they fit, then the smallest that covers the rest.
    local cases = {
      { "the smallest stack that covers what is left", 70, { 50, 30, 25 }, { "6:1", "6:3" } },
      { "the remembered count exactly when the stacks make it", 70, { 40, 30, 20 }, { "6:1", "6:2" } },
      { "one merged stack for a few that went", 5, { 200 }, { "6:1" } },
      { "all there is when there is less", 100, { 30, 20 }, { "6:1", "6:2" } },
    }
    for _, case in ipairs(cases) do
      it("takes " .. case[1], function()
        local bank = {}
        for i, count in ipairs(case[3]) do bank[i] = stack(1, 6, i, count) end
        assert.same(case[4], where(H.PutBack({ bankType = 2, at = 1, items = { [1] = case[2] } }, bank)))
      end)
    end

    it("takes nothing with nothing remembered", function()
      assert.same({}, H.PutBack(nil, { stack(1, 6, 1, 30) }))
      assert.same({}, H.PutBack({ bankType = 2, at = 1, items = {} }, { stack(1, 6, 1, 30) }))
    end)
  end)

  describe("the store", function()
    local ROOM = { bankType = 2, at = 1000, items = { [1] = 50, [2] = 5 } }

    it("reads the defaults from nothing saved and writes nothing to read them", function()
      local db = {}
      assert.is_true(H.Writable(db))
      assert.is_false(H.Closed(db))
      assert.is_false(H.FolderOpen(db, "gathering"))
      assert.is_nil(H.Room(db, "Kael-Draenor"))
      assert.is_nil(db.hoard)
      -- Setting a default keeps nothing, so it makes nothing.
      assert.is_true(H.SetClosed(db, false))
      assert.is_true(H.SetFolderOpen(db, "gathering", false))
      assert.is_true(H.SetRoom(db, "Kael-Draenor", nil))
      assert.is_nil(db.hoard)
    end)

    it("remembers the window closed in a versioned table made on the first write", function()
      local db = {}
      assert.is_true(H.SetClosed(db, true))
      assert.same({ v = H.VERSION, closed = true, open = {}, room = {} }, db.hoard)
      assert.is_true(H.Closed(db))
      assert.is_true(H.SetClosed(db, false))
      assert.is_false(H.Closed(db))
      assert.same({ v = H.VERSION, open = {}, room = {} }, db.hoard)
    end)

    it("remembers each open folder by its parent's key, and forgets a closed one", function()
      local db = {}
      assert.is_true(H.SetFolderOpen(db, "gathering", true))
      assert.is_true(H.SetFolderOpen(db, "crafting", true))
      assert.is_true(H.FolderOpen(db, "gathering"))
      assert.is_false(H.FolderOpen(db, "transmog"))
      assert.is_true(H.SetFolderOpen(db, "gathering", false))
      assert.same({ crafting = true }, db.hoard.open)
    end)

    it("remembers what Make room put away for each character, as a copy, and forgets it", function()
      local db = {}
      local room = { bankType = 2, at = 1000, items = { [1] = 50, [2] = 5 } }
      assert.is_true(H.SetRoom(db, "Kael-Draenor", room))
      room.items[1] = 1
      assert.same(ROOM, H.Room(db, "Kael-Draenor"))
      H.Room(db, "Kael-Draenor").items[2] = 99
      assert.same(ROOM, H.Room(db, "Kael-Draenor"))
      assert.is_nil(H.Room(db, "Alt-Draenor"))
      assert.is_true(H.SetRoom(db, "Kael-Draenor", nil))
      assert.same({}, db.hoard.room)
      -- A room with nothing in it is nothing to put back.
      assert.is_true(H.SetRoom(db, "Kael-Draenor", ROOM))
      assert.is_true(H.SetRoom(db, "Kael-Draenor", { bankType = 2, at = 1, items = {} }))
      assert.is_nil(H.Room(db, "Kael-Draenor"))
    end)

    local refused = {
      { "a closed state that is not true or false", function(db) return H.SetClosed(db, "yes") end },
      { "a folder with no key", function(db) return H.SetFolderOpen(db, "", true) end },
      { "a folder key that is not a string", function(db) return H.SetFolderOpen(db, 5, true) end },
      { "an open state that is not true or false", function(db) return H.SetFolderOpen(db, "gathering", 1) end },
      { "a room for no character", function(db) return H.SetRoom(db, "", ROOM) end },
      { "a room with no bank", function(db) return H.SetRoom(db, "Kael", { at = 1, items = { [1] = 5 } }) end },
      { "a room with no time", function(db) return H.SetRoom(db, "Kael", { bankType = 2, items = { [1] = 5 } }) end },
      { "a room with no items", function(db) return H.SetRoom(db, "Kael", { bankType = 2, at = 1 }) end },
      { "a room with a count of 0", function(db) return H.SetRoom(db, "Kael", { bankType = 2, at = 1, items = { [1] = 0 } }) end },
      { "a room with half an item", function(db) return H.SetRoom(db, "Kael", { bankType = 2, at = 1, items = { [1] = 1.5 } }) end },
      { "a room with an item that is no item", function(db) return H.SetRoom(db, "Kael", { bankType = 2, at = 1, items = { x = 5 } }) end },
      { "a room that is no table", function(db) return H.SetRoom(db, "Kael", "room") end },
    }
    for _, case in ipairs(refused) do
      it("refuses " .. case[1] .. " and writes nothing", function()
        local db = {}
        assert.is_false(case[2](db))
        assert.is_nil(db.hoard)
      end)
    end

    it("reads a damaged table as nothing saved and starts it afresh", function()
      local db = { hoard = "x" }
      assert.is_false(H.Closed(db))
      assert.is_nil(H.Room(db, "Kael"))
      assert.is_true(H.SetFolderOpen(db, "gathering", true))
      assert.same({ v = H.VERSION, open = { gathering = true }, room = {} }, db.hoard)
      db.hoard = { v = H.VERSION, closed = "yes", open = "x", room = 5 }
      assert.is_false(H.Closed(db))
      assert.is_false(H.FolderOpen(db, "gathering"))
      assert.is_nil(H.Room(db, "Kael"))
      assert.is_true(H.SetRoom(db, "Kael", ROOM))
      assert.is_true(H.SetFolderOpen(db, "gathering", true))
      assert.same({ v = H.VERSION, closed = "yes", open = { gathering = true }, room = { Kael = ROOM } }, db.hoard)
    end)

    it("reads only the sound part of a damaged room", function()
      local db = { hoard = { v = H.VERSION, room = {
        Kael = { bankType = 2, at = 1000, items = { [1] = 50, [2] = "x", [3] = -1, [4] = 2.5 } },
        Alt = { bankType = 2, at = 1000, items = { [2] = "x" } },
        Bare = { at = 1000, items = { [1] = 5 } },
      } } }
      assert.same({ bankType = 2, at = 1000, items = { [1] = 50 } }, H.Room(db, "Kael"))
      assert.is_nil(H.Room(db, "Alt"))
      assert.is_nil(H.Room(db, "Bare"))
    end)

    -- A newer GoldCap's table is a shape this one does not know: it is left as it is.
    it("neither reads nor writes a table a newer GoldCap saved", function()
      local newer = { v = H.VERSION + 1, closed = true, open = { gathering = true }, room = { Kael = ROOM } }
      local db = { hoard = newer }
      assert.is_false(H.Writable(db))
      assert.is_false(H.Closed(db))
      assert.is_false(H.FolderOpen(db, "gathering"))
      assert.is_nil(H.Room(db, "Kael"))
      assert.is_false(H.SetClosed(db, false))
      assert.is_false(H.SetFolderOpen(db, "crafting", true))
      assert.is_false(H.SetRoom(db, "Kael", nil))
      assert.same({ v = H.VERSION + 1, closed = true, open = { gathering = true }, room = { Kael = ROOM } }, db.hoard)
      assert.is_false(H.Writable(nil))
    end)
  end)
end)
