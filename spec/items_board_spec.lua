local helper = require("spec.spec_helper")

-- Core/ItemsBoard.lua through its public functions: the Items board split into Flips and Rare
-- finds. A rare find has no price, so everything here about one is a fact -- where this realm's
-- cheapest listing stands among the other realms', and what sold -- and never a discount, a profit
-- or a reference.
describe("ItemsBoard", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ItemsBoard.lua", GC)
  end)

  -- The Ornate Mithril Breastplate of the brief: six realms list it, the cheapest at 3,150g, a
  -- tenth of them at 90,000g and a quarter at 138,999g.
  local function facts(overrides)
    local f = { sales30d = 2, lastSaleCopper = 25000000, lastSoldAgeHours = 26, realms = 6,
      floorMin = 31500000, floorP10 = 900000000, floorP25 = 1389993400 }
    for k, v in pairs(overrides or {}) do f[k] = v end
    return f
  end

  describe("Standing", function()
    it("puts a price at or under each floor in that floor's place, and one above p25 nowhere", function()
      local f = facts()
      assert.equal("min", GC.ItemsBoard.Standing(31500000, f))
      assert.equal("min", GC.ItemsBoard.Standing(1, f))
      assert.equal("p10", GC.ItemsBoard.Standing(31500001, f))
      assert.equal("p10", GC.ItemsBoard.Standing(900000000, f))
      assert.equal("p25", GC.ItemsBoard.Standing(900000001, f))
      assert.equal("p25", GC.ItemsBoard.Standing(1389993400, f))
      assert.is_nil(GC.ItemsBoard.Standing(1389993401, f))
    end)

    it("has no standing without a price or without facts", function()
      assert.is_nil(GC.ItemsBoard.Standing(nil, facts()))
      assert.is_nil(GC.ItemsBoard.Standing(0, facts()))
      assert.is_nil(GC.ItemsBoard.Standing(100, nil))
    end)

    it("says where it stands in words", function()
      assert.equal("Cheapest of 6 realms", GC.ItemsBoard.StandingText("min", 6))
      assert.equal("Among the cheapest 10% of 34 realms", GC.ItemsBoard.StandingText("p10", 34))
      assert.equal("Cheaper than 3 in 4 of 12 realms", GC.ItemsBoard.StandingText("p25", 12))
      assert.is_nil(GC.ItemsBoard.StandingText(nil, 12))
    end)
  end)

  describe("SalesText", function()
    it("says what sold, the last price and how long ago, in days from a day on", function()
      assert.equal("Sold 2 times in 30 days, last for 2500g 1 day ago",
        GC.ItemsBoard.SalesText(facts({ lastSoldAgeHours = 26 })))
      assert.equal("Sold 2 times in 30 days, last for 2500g 3 days ago",
        GC.ItemsBoard.SalesText(facts({ lastSoldAgeHours = 3 * 24 + 23 })))
    end)

    it("counts hours under a day", function()
      assert.equal("Sold 2 times in 30 days, last for 2500g 23 hours ago",
        GC.ItemsBoard.SalesText(facts({ lastSoldAgeHours = 23 })))
      assert.equal("Sold 2 times in 30 days, last for 2500g 1 hour ago",
        GC.ItemsBoard.SalesText(facts({ lastSoldAgeHours = 1 })))
      assert.equal("Sold 2 times in 30 days, last for 2500g less than an hour ago",
        GC.ItemsBoard.SalesText(facts({ lastSoldAgeHours = 0 })))
    end)

    it("says once for one sale", function()
      assert.equal("Sold once in 30 days, last for 2500g 1 day ago",
        GC.ItemsBoard.SalesText(facts({ sales30d = 1 })))
    end)

    it("says no sale was seen when none was", function()
      local f = facts({ sales30d = 0 })
      f.lastSaleCopper, f.lastSoldAgeHours = nil, nil
      assert.equal("No sale seen in 30 days", GC.ItemsBoard.SalesText(f))
    end)

    it("leaves the last sale out when its price is not known", function()
      local f = facts({ sales30d = 3 })
      f.lastSaleCopper, f.lastSoldAgeHours = nil, nil -- GC.Data.RareFacts' shape for a sale with no price
      assert.equal("Sold 3 times in 30 days", GC.ItemsBoard.SalesText(f))
    end)
  end)

  it("says how often a flip sells", function()
    assert.equal("Sold 6 times in 7 days on 3 realms",
      GC.ItemsBoard.FlipText({ ref = 300000, sales7d = 6, realms = 3 }))
    assert.is_nil(GC.ItemsBoard.FlipText(nil))
  end)

  describe("MarkText", function()
    it("marks what the account lacks, by what kind of collectible it is", function()
      for _, kind in ipairs({ "appearance", "pet", "toy", "mount" }) do
        assert.equal("Not collected", GC.ItemsBoard.MarkText("missing", kind), kind)
      end
      assert.equal("Not known by this character", GC.ItemsBoard.MarkText("missing", "recipe"))
    end)

    it("marks an appearance known through another item", function()
      assert.equal("Appearance known", GC.ItemsBoard.MarkText("elsewhere", "appearance"))
    end)

    it("marks nothing collected, unknown or not a collectible", function()
      assert.is_nil(GC.ItemsBoard.MarkText("collected", "appearance"))
      assert.is_nil(GC.ItemsBoard.MarkText("unknown", "pet"))
      assert.is_nil(GC.ItemsBoard.MarkText("unknown", nil))
      assert.is_nil(GC.ItemsBoard.MarkText(nil, nil))
      assert.is_nil(GC.ItemsBoard.MarkText("missing", nil))
    end)
  end)

  describe("FoldSeen", function()
    local function row(itemID, minPrice, qty)
      return { itemKey = { itemID = itemID }, minPrice = minPrice, totalQuantity = qty or 1 }
    end
    local function rare(ids)
      local set = {}
      for _, id in ipairs(ids) do set[id] = true end
      return function(itemID) return set[itemID] == true end
    end

    it("keeps each rare find's cheapest listing and nothing else", function()
      local seen = {}
      GC.ItemsBoard.FoldSeen(seen, { row(7935, 31500000, 2), row(42, 100) }, nil, rare({ 7935 }))
      assert.same({ [7935] = { unit = 31500000, qty = 2 } }, seen)
    end)

    it("lets go of an asked rare find the answer is silent about, and keeps an unasked one", function()
      local seen = { [7935] = { unit = 1, qty = 1 }, [8350] = { unit = 2, qty = 1 } }
      GC.ItemsBoard.FoldSeen(seen, {}, { 7935 }, rare({ 7935, 8350 }))
      assert.is_nil(seen[7935])
      assert.same({ unit = 2, qty = 1 }, seen[8350])
    end)
  end)

  describe("RareRows", function()
    local FACTS = {
      [1] = facts({ floorMin = 100, floorP10 = 200, floorP25 = 300 }),
      [2] = facts({ floorMin = 100, floorP10 = 200, floorP25 = 300 }),
      [3] = facts({ floorMin = 100, floorP10 = 200, floorP25 = 300 }),
      [4] = facts({ floorMin = 100, floorP10 = 200, floorP25 = 300 }),
    }
    local function factsFor(itemID) return FACTS[itemID] end
    -- The site's rank, reversed by id here so the test can tell it from id order.
    local function before(a, b) return a > b end
    local function ids(list)
      local out = {}
      for i, r in ipairs(list) do out[i] = r.itemID end
      return out
    end

    it("lists a rare find at or under p25 and leaves one above it out", function()
      local rows = GC.ItemsBoard.RareRows({ [1] = { unit = 300, qty = 1 }, [2] = { unit = 301, qty = 1 } },
        factsFor, { before = before })
      assert.same({ 1 }, ids(rows))
      assert.equal("rare", rows[1].kind)
      assert.equal("p25", rows[1].standing)
      assert.equal(300, rows[1].unitPrice)
      -- No price of its own: nothing a row could call a discount, a profit or a reference.
      assert.is_nil(rows[1].profit)
      assert.is_nil(rows[1].discount)
      assert.is_nil(rows[1].mv)
    end)

    it("leaves out an item that is not a rare find", function()
      assert.same({}, GC.ItemsBoard.RareRows({ [9] = { unit = 1, qty = 1 } }, factsFor, {}))
    end)

    it("ranks the cheapest of all first, then by standing, then by the site's rank", function()
      local seen = { [1] = { unit = 250 }, [2] = { unit = 50 }, [3] = { unit = 150 }, [4] = { unit = 90 } }
      assert.same({ 4, 2, 3, 1 }, ids(GC.ItemsBoard.RareRows(seen, factsFor, { before = before })))
    end)

    it("sorts by price within the section when the header asks, and ignores keys a rare find has not", function()
      local seen = { [1] = { unit = 250 }, [2] = { unit = 50 }, [3] = { unit = 150 }, [4] = { unit = 90 } }
      assert.same({ 2, 4, 3, 1 }, ids(GC.ItemsBoard.RareRows(seen, factsFor,
        { before = before, sort = { key = "unit", desc = false } })))
      assert.same({ 1, 3, 4, 2 }, ids(GC.ItemsBoard.RareRows(seen, factsFor,
        { before = before, sort = { key = "price", desc = true } })))
      assert.same({ 4, 2, 3, 1 }, ids(GC.ItemsBoard.RareRows(seen, factsFor,
        { before = before, sort = { key = "profit", desc = true } })))
    end)

    it("leaves out a row held on screen", function()
      local seen = { [1] = { unit = 250 }, [2] = { unit = 50 } }
      assert.same({ 1 }, ids(GC.ItemsBoard.RareRows(seen, factsFor, { before = before, skip = { [2] = true } })))
    end)

    it("hands its two lines to the row", function()
      local rows = GC.ItemsBoard.RareRows({ [1] = { unit = 50 } }, factsFor, {})
      local standing, sales = GC.ItemsBoard.RareLines(rows[1])
      assert.equal("Cheapest of 6 realms", standing)
      assert.equal("Sold 2 times in 30 days, last for 2500g 1 day ago", sales)
    end)
  end)

  -- Enum.ItemClass: 2 weapon, 4 armor (subclass 5 cosmetic), 9 recipe, 15 miscellaneous, 17 battle pet.
  describe("GearPastReach", function()
    local REF = 1000000
    it("is armor or a weapon listed more than 80% under the price it is measured against", function()
      assert.is_true(GC.ItemsBoard.GearPastReach(199999, REF, 4, 2))  -- leather bracers, 80.0001% off
      assert.is_true(GC.ItemsBoard.GearPastReach(1, REF, 2, 7))       -- a sword at 100% off
      assert.is_true(GC.ItemsBoard.GearPastReach(50000, REF, 4, 0, "INVTYPE_FINGER")) -- a ring has levels
      assert.is_false(GC.ItemsBoard.GearPastReach(200000, REF, 4, 2)) -- 80% exactly is still shown
      assert.is_false(GC.ItemsBoard.GearPastReach(600000, REF, 2, 7))
    end)

    it("leaves alone what comes at one item level: cosmetics, recipes, pets, toys and mounts", function()
      assert.is_false(GC.ItemsBoard.GearPastReach(10000, REF, 4, 5))
      assert.is_false(GC.ItemsBoard.GearPastReach(10000, REF, 4, 0, "INVTYPE_TABARD"))
      assert.is_false(GC.ItemsBoard.GearPastReach(10000, REF, 4, 0, "INVTYPE_BODY")) -- a shirt
      assert.is_true(GC.ItemsBoard.GearPastReach(10000, REF, 4, 0, "INVTYPE_FINGER"))
      assert.is_false(GC.ItemsBoard.GearPastReach(10000, REF, 9, 1))
      assert.is_false(GC.ItemsBoard.GearPastReach(10000, REF, 17, 0))
      assert.is_false(GC.ItemsBoard.GearPastReach(10000, REF, 15, 5))
    end)

    it("says nothing about an item whose class it was not told, or a price that is not one", function()
      assert.is_false(GC.ItemsBoard.GearPastReach(10000, REF, nil, nil))
      assert.is_false(GC.ItemsBoard.GearPastReach(nil, REF, 4, 2))
      assert.is_false(GC.ItemsBoard.GearPastReach(10000, 0, 4, 2))
    end)
  end)

  describe("Sections", function()
    local function deal(itemID) return { itemID = itemID, unitPrice = 100, profit = 10 } end
    local function rareRow(itemID) return { kind = "rare", itemID = itemID, unitPrice = 5, standing = "min" } end
    local function shape(list)
      local out = {}
      for i, e in ipairs(list) do
        if e.kind == "header" then out[i] = e.section .. ":" .. e.count
        elseif e.kind == "empty" then out[i] = e.text
        else out[i] = e.itemID end
      end
      return out
    end

    it("hands an empty board back as it came while there are no rare finds", function()
      local flips = {}
      assert.equal(flips, GC.ItemsBoard.Sections(flips, {}, { rares = false }))
    end)

    it("heads the flips and shows no Rare finds section before the site has any", function()
      assert.same({ "flips:2", 10, 11 },
        shape(GC.ItemsBoard.Sections({ deal(10), deal(11) }, {}, { rares = false })))
    end)

    it("heads both sections with their counts", function()
      assert.same({ "flips:1", 10, "rares:2", 7935, 8350 },
        shape(GC.ItemsBoard.Sections({ deal(10) }, { rareRow(7935), rareRow(8350) }, { rares = true })))
    end)

    it("gives an empty section its header and one line", function()
      assert.same({ "flips:0", "No flips on this realm right now", "rares:0", "No rare finds on this realm right now" },
        shape(GC.ItemsBoard.Sections({}, {}, { rares = true })))
      assert.same({ "flips:1", 10, "rares:0", "No rare finds on this realm right now" },
        shape(GC.ItemsBoard.Sections({ deal(10) }, {}, { rares = true })))
    end)

    it("keeps only what the filter keeps, in both sections, and says so when it emptied one", function()
      local keep = function(entry) return entry.itemID == 11 or entry.itemID == 8350 end
      assert.same({ "flips:1", 11, "rares:1", 8350 },
        shape(GC.ItemsBoard.Sections({ deal(10), deal(11) }, { rareRow(7935), rareRow(8350) },
          { rares = true, keep = keep })))
      assert.same({ "flips:0", "Nothing here you lack", "rares:0", "No rare finds on this realm right now" },
        shape(GC.ItemsBoard.Sections({ deal(10) }, {}, { rares = true, keep = function() return false end })))
    end)

    it("holds each section to the cap", function()
      assert.same({ "flips:2", 10, 11, "rares:2", 7935, 8350 },
        shape(GC.ItemsBoard.Sections({ deal(10), deal(11), deal(12) },
          { rareRow(7935), rareRow(8350), rareRow(9) }, { rares = true, cap = 2 })))
    end)

    it("counts a row held on screen in its section, and says nothing of emptiness beside it", function()
      assert.same({ "flips:1", "rares:2", 8350 },
        shape(GC.ItemsBoard.Sections({}, { rareRow(8350) }, { rares = true, held = { flips = 1, rares = 1 } })))
    end)

    it("does not draw an item twice when a flip row already has it", function()
      assert.same({ "flips:1", 7935, "rares:1", 8350 },
        shape(GC.ItemsBoard.Sections({ deal(7935) }, { rareRow(7935), rareRow(8350) }, { rares = true })))
    end)
  end)
end)
