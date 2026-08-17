local helper = require("spec.spec_helper")

describe("Flips row model (Sniper v3 §5)", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Flips.lua")
  end)

  local function flip(overrides)
    local f = { itemID = 42, qty = 2, paidUnit = 100, paidTotal = 200, boughtAt = 0, targetUnit = 190 }
    for k, v in pairs(overrides or {}) do f[k] = v end
    return f
  end

  local function lots(...)
    return { ... }
  end

  describe("BuildRow", function()
    it("carries itemID/qty/boughtUnit straight from the flip", function()
      local row = GC.Flips.BuildRow(flip(), {}, nil, {})
      assert.equal(42, row.itemID)
      assert.equal(2, row.qty)
      assert.equal(100, row.boughtUnit)
    end)

    it("UNLISTED: no owned lot, no quote -- profit nil, listed/market nil", function()
      local row = GC.Flips.BuildRow(flip(), {}, nil, {})
      assert.equal("UNLISTED", row.status)
      assert.is_nil(row.listedUnit)
      assert.is_nil(row.marketUnit)
      assert.is_nil(row.profit)
    end)

    it("UNLISTED even with a fresh quote, as long as there's no owned lot", function()
      -- marketUnit alone still feeds the profit projection (both terms of
      -- the min() collapse to marketUnit when listedUnit is nil).
      local row = GC.Flips.BuildRow(flip({ paidUnit = 100, paidTotal = 300, qty = 3 }), {}, { unit = 1000, at = 0 }, {})
      assert.equal("UNLISTED", row.status)
      assert.is_nil(row.listedUnit)
      assert.equal(1000, row.marketUnit)
      -- floor(1000 * 3 * 95 / 100) - 300 = 2550
      assert.equal(2550, row.profit)
    end)

    it("projects from the supplied live quote, never the flip target", function()
      local row = GC.Flips.BuildRow(flip({ targetUnit = 999999 }), {}, { unit = 1000 }, {})
      assert.equal(1000, row.marketUnit)
      assert.equal(1700, row.profit)
    end)

    it("LISTED: owned lot exists and no fresh quote to compare against", function()
      local row = GC.Flips.BuildRow(flip({ paidUnit = 100, paidTotal = 300, qty = 3 }),
        lots({ itemID = 42, unitPrice = 333 }), nil, {})
      assert.equal("LISTED", row.status)
      assert.equal(333, row.listedUnit)
      assert.is_nil(row.marketUnit)
      -- floor(333 * 3 * 95 / 100) - 300 = 649
      assert.equal(649, row.profit)
    end)

    it("LISTED: owned lot priced AT (not above) the current lowest ask", function()
      local row = GC.Flips.BuildRow(flip(), lots({ itemID = 42, unitPrice = 500 }),
        { unit = 500, at = 0 }, {})
      assert.equal("LISTED", row.status)
    end)

    it("picks the LOWEST of several owned lots for the same item", function()
      local row = GC.Flips.BuildRow(flip(),
        lots({ itemID = 42, unitPrice = 900 }, { itemID = 42, unitPrice = 400 }, { itemID = 42, unitPrice = 700 }),
        nil, {})
      assert.equal(400, row.listedUnit)
    end)

    it("ignores owned lots belonging to a different item", function()
      local row = GC.Flips.BuildRow(flip(), lots({ itemID = 999, unitPrice = 1 }), nil, {})
      assert.is_nil(row.listedUnit)
      assert.equal("UNLISTED", row.status)
    end)

    it("UNDERCUT: owned lot priced above the current lowest ask", function()
      local row = GC.Flips.BuildRow(flip({ paidUnit = 100, qty = 2 }),
        lots({ itemID = 42, unitPrice = 150 }), { unit = 100, at = 0 }, {})
      assert.equal("UNDERCUT", row.status)
      assert.equal(150, row.listedUnit)
      assert.equal(100, row.marketUnit)
      -- floor(100 * 2 * 95 / 100) - 200 = -10
      assert.equal(-10, row.profit)
    end)

    it("SOLD_PENDING outranks UNDERCUT even when the lot is clearly undercut", function()
      local row = GC.Flips.BuildRow(flip({ paidUnit = 100, qty = 2 }),
        lots({ itemID = 42, unitPrice = 150 }), { unit = 100, at = 0 },
        { { itemID = 42, kind = "sale", pending = true } })
      assert.equal("SOLD_PENDING", row.status)
      -- profit is still computed against listed/market -- SOLD_PENDING only
      -- changes the status chip, not the projection.
      assert.equal(-10, row.profit)
    end)

    it("SOLD_PENDING outranks LISTED", function()
      local row = GC.Flips.BuildRow(flip(), lots({ itemID = 42, unitPrice = 333 }), nil,
        { { itemID = 42, kind = "sale", pending = true } })
      assert.equal("SOLD_PENDING", row.status)
    end)

    it("a non-pending sale entry does not trigger SOLD_PENDING", function()
      local row = GC.Flips.BuildRow(flip(), lots({ itemID = 42, unitPrice = 333 }), nil,
        { { itemID = 42, kind = "sale", pending = false } })
      assert.equal("LISTED", row.status)
    end)

    describe("SOLD (F1: posted flips keep their cost basis)", function()
      it("SOLD when a non-pending sale landed at/after postedAt and no owned lot remains", function()
        local row = GC.Flips.BuildRow(flip({ posted = true, postedAt = 500 }), {}, nil,
          { { itemID = 42, kind = "sale", pending = false, at = 500 } })
        assert.equal("SOLD", row.status)
      end)

      it("SOLD falls back to boughtAt when the flip was never posted (postedAt nil)", function()
        local row = GC.Flips.BuildRow(flip({ boughtAt = 100 }), {}, nil,
          { { itemID = 42, kind = "sale", pending = false, at = 100 } })
        assert.equal("SOLD", row.status)
      end)

      it("a sale landing BEFORE postedAt does not count (an earlier, unrelated sale)", function()
        local row = GC.Flips.BuildRow(flip({ posted = true, postedAt = 500 }), {}, nil,
          { { itemID = 42, kind = "sale", pending = false, at = 499 } })
        assert.equal("UNLISTED", row.status)
      end)

      it("SOLD_PENDING outranks SOLD when both a pending and a landed sale are present", function()
        local row = GC.Flips.BuildRow(flip({ posted = true, postedAt = 500 }), {}, nil, {
          { itemID = 42, kind = "sale", pending = false, at = 500 },
          { itemID = 42, kind = "sale", pending = true, at = 600 },
        })
        assert.equal("SOLD_PENDING", row.status)
      end)

      it("an owned lot blocks SOLD even with a matching landed sale (some OTHER batch sold)", function()
        local row = GC.Flips.BuildRow(flip({ posted = true, postedAt = 500 }),
          lots({ itemID = 42, unitPrice = 333 }), nil,
          { { itemID = 42, kind = "sale", pending = false, at = 500 } })
        assert.not_equal("SOLD", row.status)
        assert.equal("LISTED", row.status)
      end)

      it("UNDERCUT still wins over a landed sale when an owned lot IS present and undercut", function()
        local row = GC.Flips.BuildRow(flip({ posted = true, postedAt = 500, paidUnit = 100, qty = 2 }),
          lots({ itemID = 42, unitPrice = 150 }), { unit = 100, at = 0 },
          { { itemID = 42, kind = "sale", pending = false, at = 500 } })
        assert.equal("UNDERCUT", row.status)
      end)

      it("a pending==true sale alone does not satisfy SOLD (that's SOLD_PENDING's job)", function()
        local row = GC.Flips.BuildRow(flip({ posted = true, postedAt = 500 }), {}, nil,
          { { itemID = 42, kind = "sale", pending = true, at = 500 } })
        assert.equal("SOLD_PENDING", row.status)
      end)
    end)

    it("floors a fractional profit toward negative infinity, not toward zero", function()
      -- floor(99 * 1 * 95 / 100) - 1 = 93
      local row = GC.Flips.BuildRow(flip({ paidUnit = 1, paidTotal = 1, qty = 1 }),
        lots({ itemID = 42, unitPrice = 99 }), nil, {})
      assert.equal(93, row.profit)
    end)

    it("subtracts the exact non-divisible purchase total, not display unit times quantity", function()
      local row = GC.Flips.BuildRow(flip({ qty = 2, paidUnit = 100, paidTotal = 201 }),
        lots({ itemID = 42, unitPrice = 200 }), nil, {})
      assert.equal(179, row.profit) -- floor(200 * 2 * 95 / 100) - 201
    end)

    it("keeps a legacy flip without paidTotal visible but unprojectable", function()
      local legacy = flip()
      legacy.paidTotal = nil
      local row = GC.Flips.BuildRow(legacy, lots({ itemID = 42, unitPrice = 200 }), nil, {})
      assert.equal("LISTED", row.status)
      assert.is_nil(row.profit)
      assert.is_nil(row.paidTotal)
    end)

    describe("ahead/outlook wiring (Sell-tab upgrade)", function()
      it("ahead is nil when the quote carries no levels", function()
        local row = GC.Flips.BuildRow(flip(), lots({ itemID = 42, unitPrice = 500 }),
          { unit = 500 }, {})
        assert.is_nil(row.ahead)
      end)

      it("ahead is nil when there is no owned lot to compare the book against", function()
        local row = GC.Flips.BuildRow(flip(), {},
          { unit = 500, levels = { { unitPrice = 400, quantity = 10 } } }, {})
        assert.is_nil(row.ahead)
      end)

      it("ahead sums units below the row's OWN listedUnit, from the quote's levels", function()
        local row = GC.Flips.BuildRow(flip(), lots({ itemID = 42, unitPrice = 500 }),
          { unit = 400, levels = {
            { unitPrice = 300, quantity = 5 },
            { unitPrice = 400, quantity = 7 },
            { unitPrice = 600, quantity = 9 },
          } }, {})
        assert.equal(12, row.ahead) -- 300 and 400 are both < listedUnit(500) -> 5+7=12; the 600 level is not
      end)

      it("outlook is nil without GetItemValue stats (no sold/day data)", function()
        local row = GC.Flips.BuildRow(flip(), lots({ itemID = 42, unitPrice = 500 }), { unit = 500 }, {}, nil)
        assert.is_nil(row.outlook)
      end)

      it("outlook is populated when stats carries a positive sold/day", function()
        local row = GC.Flips.BuildRow(flip({ qty = 4 }), {}, nil, {}, { sold = 4 })
        -- ahead nil (no owned lot) -> treated as 0 by SellOutlook; days = (0+4)/4 = 1 -> tier OK
        assert.is_not_nil(row.outlook)
        assert.equal(1, row.outlook.days)
        assert.equal("OK", row.outlook.tier)
      end)

      it("passes stats.trend through to outlook's falling-market slowdown", function()
        local row = GC.Flips.BuildRow(flip({ qty = 3 }), {}, nil, {}, { sold = 3, trend = -20 })
        -- days = (0+3)/3 = 1, *1.5 = 1.5 -> tier OK
        assert.equal(1.5, row.outlook.days)
      end)

      it("tolerates a nil stats argument entirely (5-arg BuildRow still works with only 4 given)", function()
        assert.has_no.errors(function()
          GC.Flips.BuildRow(flip(), {}, nil, {})
      end)
    end)
  end)
  end)

  describe("Summary", function()
    it("sums invested for every row, known or not", function()
      local rows = {
        { boughtUnit = 100, paidTotal = 201, qty = 2, profit = nil },
        { boughtUnit = 50, paidTotal = 150, qty = 3, profit = nil },
      }
      local s = GC.Flips.Summary(rows)
      assert.equal(351, s.invested) -- 201 + 150
      assert.equal(0, s.projected)
      assert.equal(0, s.profit)
    end)

    it("Sell-tab upgrade: skips a row with boughtUnit == nil entirely (an orphan row) -- no cost basis to fold in", function()
      local rows = {
        { boughtUnit = 100, paidTotal = 200, qty = 2, profit = 50 }, -- invested 200, projected 250
        { boughtUnit = nil, qty = 999, profit = nil },    -- orphan: must not error, must not count
        { itemID = 7, qty = 3, listedUnit = 50, orphan = true }, -- a realistic OrphanLotRows-shaped row (no boughtUnit/profit fields at all)
      }
      assert.has_no.errors(function()
        local s = GC.Flips.Summary(rows)
        assert.equal(200, s.invested)
        assert.equal(250, s.projected)
        assert.equal(50, s.profit)
      end)
    end)

    it("only folds projected/profit in from rows with a known profit", function()
      local rows = {
        { boughtUnit = 100, paidTotal = 201, qty = 2, profit = 50 },  -- invested 201, projected 251
        { boughtUnit = 50, paidTotal = 50, qty = 1, profit = nil },   -- invested 50, contributes nothing else
        { boughtUnit = 10, paidTotal = 50, qty = 5, profit = -20 },   -- invested 50, projected 30
      }
      local s = GC.Flips.Summary(rows)
      assert.equal(301, s.invested)  -- 201 + 50 + 50
      assert.equal(281, s.projected) -- 251 + 30
      assert.equal(30, s.profit)     -- 50 + (-20)
    end)

    it("excludes legacy rows with unknown exact cost from monetary totals", function()
      local s = GC.Flips.Summary({
        { boughtUnit = 100, qty = 2, paidTotal = nil, profit = nil },
        { boughtUnit = 100, qty = 2, paidTotal = 201, profit = 9 },
      })
      assert.same({ invested = 201, projected = 210, profit = 9 }, s)
    end)

    it("returns all zeros for an empty row set", function()
      local s = GC.Flips.Summary({})
      assert.same({ invested = 0, projected = 0, profit = 0 }, s)
    end)

    it("tolerates a nil rows argument", function()
      assert.has_no.errors(function()
        assert.same({ invested = 0, projected = 0, profit = 0 }, GC.Flips.Summary(nil))
      end)
    end)
  end)

  -- Task 9 fix round 1 (minor): moved here from UI/SellFrame.lua so they're pure/tested like
  -- BuildRow/Summary above.
  describe("ExtractOwnedLots", function()
    it("uses a commodity's unitPrice as-is", function()
      local itemKey = { itemID = 42 }
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = itemKey, isCommodity = true,
        unitPrice = 500, quantity = 3, auctionID = 1 } })
      assert.same({ { itemID = 42, itemKey = itemKey, isCommodity = true,
        unitPrice = 500, auctionID = 1, quantity = 3 } }, result)
    end)

    it("preserves a normal lot's exact item variant for position accounting", function()
      local itemKey = { itemID = 7, itemLevel = 447, itemSuffix = 3, battlePetSpeciesID = 0 }
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = itemKey, buyoutAmount = 1000,
        quantity = 1, auctionID = 8, isCommodity = false } })
      assert.same(itemKey, result[1].itemKey)
      assert.is_false(result[1].isCommodity)
    end)

    it("I3: divides a stacked item lot's buyoutAmount by its quantity", function()
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = { itemID = 7 }, buyoutAmount = 1000, quantity = 5, auctionID = 2 } })
      assert.equal(200, result[1].unitPrice)
    end)

    it("treats a missing quantity as 1 (single-item lot, defensive default)", function()
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = { itemID = 7 }, buyoutAmount = 1000, auctionID = 3 } })
      assert.equal(1000, result[1].unitPrice)
    end)

    it("treats a zero quantity the same as missing (defensive, never divides by zero)", function()
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = { itemID = 7 }, buyoutAmount = 1000, quantity = 0, auctionID = 4 } })
      assert.equal(1000, result[1].unitPrice)
    end)

    it("Sell-tab upgrade: carries quantity through onto the returned lot, defaulted to 1 when missing", function()
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = { itemID = 7 }, buyoutAmount = 1000, auctionID = 3 } })
      assert.equal(1, result[1].quantity)
    end)

    it("Sell-tab upgrade: carries a real quantity through unchanged", function()
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = { itemID = 7 }, buyoutAmount = 1000, quantity = 5, auctionID = 2 } })
      assert.equal(5, result[1].quantity)
    end)

    it("Sell-tab upgrade: treats a zero quantity as 1 on the returned lot too", function()
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = { itemID = 7 }, buyoutAmount = 1000, quantity = 0, auctionID = 4 } })
      assert.equal(1, result[1].quantity)
    end)

    it("floors a fractional per-unit split", function()
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = { itemID = 7 }, buyoutAmount = 100, quantity = 3, auctionID = 5 } })
      assert.equal(33, result[1].unitPrice) -- floor(100/3)
    end)

    it("drops a lot with no buyout/unitPrice", function()
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = { itemID = 7 }, buyoutAmount = 0, auctionID = 6 } })
      assert.same({}, result)
    end)

    it("drops a lot with no itemKey.itemID", function()
      local result = GC.Flips.ExtractOwnedLots({ { unitPrice = 500, auctionID = 7 } })
      assert.same({}, result)
    end)

    it("tolerates a nil auctions argument", function()
      assert.same({}, GC.Flips.ExtractOwnedLots(nil))
    end)
  end)

  describe("CheapestOwnedLot", function()
    it("picks the lowest-priced lot for the item, with its auctionID", function()
      local lot = GC.Flips.CheapestOwnedLot(42, {
        { itemID = 42, unitPrice = 900, auctionID = 1 },
        { itemID = 42, unitPrice = 400, auctionID = 2 },
        { itemID = 42, unitPrice = 700, auctionID = 3 },
        { itemID = 99, unitPrice = 1, auctionID = 4 },
      })
      assert.equal(2, lot.auctionID)
      assert.equal(400, lot.unitPrice)
    end)

    it("returns nil when there is no lot for the item", function()
      assert.is_nil(GC.Flips.CheapestOwnedLot(42, {}))
    end)

    it("tolerates a nil lots argument", function()
      assert.is_nil(GC.Flips.CheapestOwnedLot(42, nil))
    end)
  end)

  describe("SalesForItem", function()
    local entries = {
      { kind = "sale", itemName = "Ironclaw Ore", at = 100 },
      { kind = "sale", itemName = "Ironclaw Ore", at = 50 },
      { kind = "sale", itemName = "Different Item", at = 200 },
      { kind = "buy",  itemName = "Ironclaw Ore", at = 300 },
    }

    it("matches by itemName only", function()
      local sales = GC.Flips.SalesForItem(entries, "Ironclaw Ore", 0)
      assert.equal(2, #sales)
    end)

    it("I6: drops sales recorded before sinceAt (a flip's own boughtAt)", function()
      local sales = GC.Flips.SalesForItem(entries, "Ironclaw Ore", 80)
      assert.equal(1, #sales)
      assert.equal(100, sales[1].at)
    end)

    it("includes a sale recorded exactly at sinceAt", function()
      local sales = GC.Flips.SalesForItem(entries, "Ironclaw Ore", 100)
      assert.equal(1, #sales)
    end)

    it("ignores non-sale entries even with a matching name", function()
      local sales = GC.Flips.SalesForItem(entries, "Ironclaw Ore", 300)
      assert.equal(0, #sales)
    end)

    it("returns an empty list for a nil itemName", function()
      assert.same({}, GC.Flips.SalesForItem(entries, nil, 0))
    end)

    it("tolerates a nil entries argument", function()
      assert.same({}, GC.Flips.SalesForItem(nil, "Ironclaw Ore", 0))
    end)
  end)

  describe("DepthBelow (Sell-tab upgrade)", function()
    it("sums quantity strictly below ourUnit", function()
      local levels = {
        { unitPrice = 100, quantity = 3 },
        { unitPrice = 200, quantity = 5 },
        { unitPrice = 300, quantity = 7 },
      }
      assert.equal(8, GC.Flips.DepthBelow(levels, 300)) -- 3 + 5, the 300 level itself excluded
    end)

    it("boundary: a level priced EXACTLY at ourUnit is not counted", function()
      local levels = { { unitPrice = 500, quantity = 100 } }
      assert.equal(0, GC.Flips.DepthBelow(levels, 500))
    end)

    it("counts every level cheaper than ourUnit when ourUnit is above all of them", function()
      local levels = { { unitPrice = 100, quantity = 3 }, { unitPrice = 200, quantity = 5 } }
      assert.equal(8, GC.Flips.DepthBelow(levels, 999))
    end)

    it("returns 0 (not nil) when ourUnit undercuts every level", function()
      local levels = { { unitPrice = 100, quantity = 3 }, { unitPrice = 200, quantity = 5 } }
      assert.equal(0, GC.Flips.DepthBelow(levels, 1))
    end)

    it("treats a missing quantity on a level as 0", function()
      local levels = { { unitPrice = 100 } }
      assert.equal(0, GC.Flips.DepthBelow(levels, 200))
    end)

    it("returns nil for a nil levels argument", function()
      assert.is_nil(GC.Flips.DepthBelow(nil, 500))
    end)

    it("returns nil for an empty levels array", function()
      assert.is_nil(GC.Flips.DepthBelow({}, 500))
    end)

    it("returns nil for a nil ourUnit", function()
      local levels = { { unitPrice = 100, quantity = 3 } }
      assert.is_nil(GC.Flips.DepthBelow(levels, nil))
    end)
  end)

  describe("SellOutlook (Sell-tab upgrade)", function()
    it("returns nil when sold is nil -- never fabricates a number without import data", function()
      assert.is_nil(GC.Flips.SellOutlook({ ahead = 0, qty = 5 }))
    end)

    it("returns nil when sold is zero", function()
      assert.is_nil(GC.Flips.SellOutlook({ ahead = 0, qty = 5, sold = 0 }))
    end)

    it("returns nil when sold is negative", function()
      assert.is_nil(GC.Flips.SellOutlook({ ahead = 0, qty = 5, sold = -1 }))
    end)

    it("tolerates a nil args table entirely", function()
      assert.is_nil(GC.Flips.SellOutlook(nil))
    end)

    it("treats a nil ahead/qty as 0", function()
      local o = GC.Flips.SellOutlook({ sold = 2 })
      assert.equal(0, o.days)
      assert.equal("FAST", o.tier)
    end)

    it("days = (ahead + qty) / sold", function()
      local o = GC.Flips.SellOutlook({ ahead = 10, qty = 10, sold = 5 })
      assert.equal(4, o.days)
    end)

    it("tier boundary: just under 1 day is FAST", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 9, sold = 10 })
      assert.equal(0.9, o.days)
      assert.equal("FAST", o.tier)
    end)

    it("tier boundary: exactly 1 day is OK, not FAST", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10 })
      assert.equal(1, o.days)
      assert.equal("OK", o.tier)
    end)

    it("tier boundary: exactly 3 days is SLOW, not OK", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 30, sold = 10 })
      assert.equal(3, o.days)
      assert.equal("SLOW", o.tier)
    end)

    it("tier boundary: exactly 7 days is STALL, not SLOW", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 70, sold = 10 })
      assert.equal(7, o.days)
      assert.equal("STALL", o.tier)
    end)

    it("trend <= -10 multiplies days by 1.5 (falling market slows sales)", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10, trend = -10 })
      assert.equal(1.5, o.days)
    end)

    it("trend just above -10 does NOT trigger the falling-market slowdown", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10, trend = -9 })
      assert.equal(1, o.days)
    end)

    it("trend >= 10 multiplies days by 0.75 (rising market speeds sales)", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10, trend = 10 })
      assert.equal(0.75, o.days)
    end)

    it("trend just below 10 does NOT trigger the rising-market speedup", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10, trend = 9 })
      assert.equal(1, o.days)
    end)

    it("trend between -10 and 10 (exclusive) leaves days unmodified", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10, trend = 0 })
      assert.equal(1, o.days)
    end)
  end)

  describe("OrphanLotRows (Sell-tab upgrade)", function()
    it("aggregates a single item's lots into one row: summed qty, cheapest listedUnit, lotCount", function()
      local ownedLots = {
        { itemID = 7, unitPrice = 500, auctionID = 1, quantity = 10 },
        { itemID = 7, unitPrice = 400, auctionID = 2, quantity = 5 },
      }
      local rows = GC.Flips.OrphanLotRows(ownedLots, {})
      assert.equal(1, #rows)
      assert.equal(7, rows[1].itemID)
      assert.equal(15, rows[1].qty)
      assert.equal(400, rows[1].listedUnit)
      assert.equal(2, rows[1].lotCount)
      assert.is_true(rows[1].orphan)
    end)

    it("excludes any itemID that has a matching flip record", function()
      local ownedLots = {
        { itemID = 7, unitPrice = 500, auctionID = 1, quantity = 10 },
        { itemID = 8, unitPrice = 300, auctionID = 2, quantity = 1 },
      }
      local flips = { { itemID = 7 } }
      local rows = GC.Flips.OrphanLotRows(ownedLots, flips)
      assert.equal(1, #rows)
      assert.equal(8, rows[1].itemID)
    end)

    it("is deterministic: sorted by itemID ascending regardless of input order", function()
      local ownedLots = {
        { itemID = 30, unitPrice = 1, auctionID = 1, quantity = 1 },
        { itemID = 10, unitPrice = 1, auctionID = 2, quantity = 1 },
        { itemID = 20, unitPrice = 1, auctionID = 3, quantity = 1 },
      }
      local rows = GC.Flips.OrphanLotRows(ownedLots, {})
      assert.equal(10, rows[1].itemID)
      assert.equal(20, rows[2].itemID)
      assert.equal(30, rows[3].itemID)
    end)

    it("treats a missing/zero lot quantity as 1 when summing qty", function()
      local ownedLots = { { itemID = 7, unitPrice = 500, auctionID = 1 } }
      local rows = GC.Flips.OrphanLotRows(ownedLots, {})
      assert.equal(1, rows[1].qty)
    end)

    it("returns an empty list when every lot is flip-covered", function()
      local ownedLots = { { itemID = 7, unitPrice = 500, auctionID = 1, quantity = 1 } }
      local rows = GC.Flips.OrphanLotRows(ownedLots, { { itemID = 7 } })
      assert.same({}, rows)
    end)

    it("tolerates nil ownedLots and nil flips", function()
      assert.has_no.errors(function()
        assert.same({}, GC.Flips.OrphanLotRows(nil, nil))
      end)
    end)
  end)

  describe("EnrichOrphanRow (Sell-tab upgrade)", function()
    local function orphan(overrides)
      local o = { itemID = 7, qty = 10, listedUnit = 500, lotCount = 2, orphan = true }
      for k, v in pairs(overrides or {}) do o[k] = v end
      return o
    end

    it("LISTED when there is no fresh quote to compare against", function()
      local row = GC.Flips.EnrichOrphanRow(orphan(), nil, nil)
      assert.equal("LISTED", row.status)
      assert.is_nil(row.marketUnit)
      assert.is_nil(row.ahead)
    end)

    it("LISTED when the fresh quote is at or below our listedUnit", function()
      local row = GC.Flips.EnrichOrphanRow(orphan(), { unit = 500 }, nil)
      assert.equal("LISTED", row.status)
      assert.equal(500, row.marketUnit)
    end)

    it("UNDERCUT when our listedUnit sits above the fresh ask", function()
      local row = GC.Flips.EnrichOrphanRow(orphan(), { unit = 400 }, nil)
      assert.equal("UNDERCUT", row.status)
    end)

    it("computes ahead from the quote's levels against the orphan's own listedUnit", function()
      local row = GC.Flips.EnrichOrphanRow(orphan(), { unit = 400, levels = {
        { unitPrice = 300, quantity = 4 },
        { unitPrice = 600, quantity = 9 },
      } }, nil)
      assert.equal(4, row.ahead)
    end)

    it("computes outlook from stats when provided", function()
      local row = GC.Flips.EnrichOrphanRow(orphan({ qty = 20 }), nil, { sold = 10 })
      assert.equal(2, row.outlook.days)
      assert.equal("OK", row.outlook.tier)
    end)

    it("does not mutate the input orphanRow", function()
      local o = orphan()
      GC.Flips.EnrichOrphanRow(o, { unit = 400 }, nil)
      assert.is_nil(o.marketUnit)
      assert.is_nil(o.status)
    end)

    it("preserves the original aggregate fields (itemID/qty/lotCount/orphan) on the returned row", function()
      local row = GC.Flips.EnrichOrphanRow(orphan(), nil, nil)
      assert.equal(7, row.itemID)
      assert.equal(10, row.qty)
      assert.equal(2, row.lotCount)
      assert.is_true(row.orphan)
    end)
  end)

  describe("RecommendPost (design update)", function()
    -- Part 0 (silver-grid fix): candidates are now normalized to whole silver, so the plain
    -- undercut-by-1-copper number this test used to assert (499) is no longer reachable -- it
    -- would silently fail to post. marketUnit=50000 (5g) sits well above the match/undercut
    -- share boundary (see silver_grid_spec.lua for the derivation), so undercut still fires;
    -- the candidate is one silver below, on the grid.
    it("undercuts a live market quote by one whole silver", function()
      local r = GC.Flips.RecommendPost(100, 50000, nil)
      assert.equal(49900, r.unit)
    end)

    -- Part 0: a price under one silver cannot be posted at all, so the grid's floor is 100
    -- copper, not 1 -- this replaces the old "floors at 1 copper" behavior.
    it("floors the undercut candidate at one silver (never zero/sub-silver)", function()
      local r = GC.Flips.RecommendPost(1, 1, nil)
      assert.equal(100, r.unit)
    end)

    it("falls back to mv when there is no live quote", function()
      local r = GC.Flips.RecommendPost(100, nil, 800)
      assert.equal(800, r.unit)
    end)

    -- Part 0: same grid normalization as the first test above.
    it("prefers a live quote over mv when both are present", function()
      local r = GC.Flips.RecommendPost(100, 50000, 800)
      assert.equal(49900, r.unit)
    end)

    it("returns nil when neither marketUnit nor mv is known", function()
      assert.is_nil(GC.Flips.RecommendPost(100, nil, nil))
    end)

    -- F5 queue-at-exit: a sniper-underwritten position posts at the exit its buy was approved
    -- against when the wall below it is hours of turnover, instead of matching the wall it was
    -- bought from (which locks in the 5% cut as a loss).
    describe("queue-at-exit", function()
      local ladder = {
        { unitPrice = 19800, quantity = 8000 },
        { unitPrice = 20000, quantity = 1500 },
        { unitPrice = 24000, quantity = 4000 },
        { unitPrice = 30000, quantity = 50000 },
      }

      it("queues at the target when everything below it fits the turnover budget", function()
        -- budget = 222000 * 2 / 24 = 18500 >= 13500 units below the 27300 target
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27300 })
        assert.equal("queue", r.mode)
        assert.equal(27300, r.unit)
        assert.is_false(r.belowCost)
      end)

      it("stops at the highest rung whose queue fits when the target does not", function()
        -- budget = 60000 * 2 / 24 = 5000: the 19800 wall (8000 units) already exceeds it once
        -- its own tail is joined... but the seller joining AT 19800 is the match case; the
        -- first rung ABOVE the wall needs 8000 queued -- over budget, so no climb at all.
        local tight = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 60000, targetUnit = 27300 })
        assert.not_equal("queue", tight.mode)
        -- budget = 150000 * 2 / 24 = 12500: rungs at 20000 (9500 queued) fit; 24000 (13500)
        -- does not, so the climb stops one rung below it.
        local mid = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 150000, targetUnit = 27300 })
        assert.equal("queue", mid.mode)
        assert.equal(20000, mid.unit)
      end)

      it("never jumps past the end of a truncated book to the target", function()
        -- Same ladder, but nothing visible above the 27300 target: the book may simply be
        -- cut off there (levels are capped), so the gap between the last rung and the target
        -- is unmeasured. The climb stops at the highest VISIBLE rung.
        local cut = {
          { unitPrice = 19800, quantity = 8000 },
          { unitPrice = 20000, quantity = 1500 },
          { unitPrice = 24000, quantity = 4000 },
        }
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = cut, sold = 222000, targetUnit = 27300 })
        assert.equal("queue", r.mode)
        assert.equal(24000, r.unit)
      end)

      it("deflates the target when the current trend says the market is mid-spike", function()
        -- Stored target 27300 with a +201% trend: pre-spike estimate 27300/3.01 = 9069 ->
        -- grid 9000, below the 19800 match candidate -- no queueing above the wall at all.
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27300, trendPct = 201 })
        assert.not_equal("queue", r.mode)
        -- At or below the threshold the target stands untouched.
        local calm = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27300, trendPct = 30 })
        assert.equal("queue", calm.mode)
        assert.equal(27300, calm.unit)
      end)

      it("does nothing without a target -- untracked stock keeps match/undercut", function()
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000 })
        assert.not_equal("queue", r.mode)
      end)

      it("is disabled by absorbHours = 0", function()
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27300, absorbHours = 0 })
        assert.not_equal("queue", r.mode)
      end)

      it("lands the queued price on the silver grid", function()
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27377 })
        assert.equal("queue", r.mode)
        assert.equal(27300, r.unit)
      end)
    end)

    it("computes breakeven as ceil(paidUnit / 0.95)", function()
      local r = GC.Flips.RecommendPost(100, 500, nil)
      assert.equal(106, r.breakeven) -- 100/0.95 = 105.26... -> ceil 106
    end)

    it("breakeven is nil when paidUnit is unknown (an orphan-shaped call)", function()
      local r = GC.Flips.RecommendPost(nil, 500, nil)
      assert.is_nil(r.breakeven)
      assert.is_false(r.belowCost)
    end)

    it("belowCost is true when the candidate sits below breakeven", function()
      -- Part 0: candidate is now the match price 100 (marketUnit=90 clamps up to the grid
      -- floor), not the old 89 -- still below breakeven=106 either way.
      local r = GC.Flips.RecommendPost(100, 90, nil) -- candidate=100 (grid floor), breakeven=106
      assert.is_true(r.belowCost)
    end)

    it("belowCost boundary: candidate exactly AT breakeven is NOT belowCost", function()
      -- paidUnit=95 -> breakeven=ceil(95/0.95)=100; drive candidate to exactly 100 via mv (no -1 undercut)
      local r = GC.Flips.RecommendPost(95, nil, 100)
      assert.equal(100, r.breakeven)
      assert.equal(100, r.unit)
      assert.is_false(r.belowCost)
    end)

    it("belowCost is false when candidate sits above breakeven", function()
      local r = GC.Flips.RecommendPost(100, 1000, nil)
      assert.is_false(r.belowCost)
    end)

    describe("mode selection: match vs undercut (F3)", function()
      -- Every price in this block is priced at 10g a unit, well clear of the 50-silver boundary
      -- where a flat one-silver step stops being worth taking. These tests are about WHICH RULE
      -- picks the mode -- tier depth and velocity -- so they must not sit at a price where the
      -- grid's own share rule decides the answer before the tier rule is even consulted. An
      -- earlier draft ran them at one silver, which is the one price where "undercut" cannot
      -- exist at all; the tightest-edge-of-the-grid cases live in spec/silver_grid_spec.lua,
      -- where they belong.
      it("plain 3-arg call (no opts) still undercuts, mode='undercut'", function()
        local r = GC.Flips.RecommendPost(50000, 100000, nil)
        assert.equal("undercut", r.mode)
        assert.equal(99900, r.unit)
      end)

      it("mode is nil in the no-quote (mv) fallback branch, even with opts present", function()
        local r = GC.Flips.RecommendPost(50, nil, 800, { levels = { { unitPrice = 1, quantity = 1 } }, sold = 1000 })
        assert.is_nil(r.mode)
        assert.equal(800, r.unit)
      end)

      it("recommends match when sold covers 2x the cheapest tier's depth", function()
        -- cheapest tier (unitPrice=100) depth = 5+5=10; sold=20 -> 20 >= 2*10 -> match
        local levels = {
          { unitPrice = 100, quantity = 5 }, { unitPrice = 100, quantity = 5 }, { unitPrice = 200, quantity = 50 },
        }
        local r = GC.Flips.RecommendPost(50, 100, nil, { levels = levels, sold = 20 })
        assert.equal("match", r.mode)
        assert.equal(100, r.unit) -- matches the ask, no -1c undercut
      end)

      it("boundary: sold exactly 2x tierDepth triggers match", function()
        local levels = { { unitPrice = 100, quantity = 10 } }
        local r = GC.Flips.RecommendPost(50, 100, nil, { levels = levels, sold = 20 })
        assert.equal("match", r.mode)
      end)

      it("boundary: sold just under 2x tierDepth stays undercut", function()
        local levels = { { unitPrice = 100000, quantity = 10 } }
        local r = GC.Flips.RecommendPost(50000, 100000, nil, { levels = levels, sold = 19 })
        assert.equal("undercut", r.mode)
        assert.equal(99900, r.unit) -- one whole silver below, the smallest step the grid allows
      end)

      it("only counts levels priced exactly at the cheapest tier toward tierDepth", function()
        -- tierDepth = 3 (only the 100-priced level); sold=6 -> 6 >= 2*3 -> match
        local levels = { { unitPrice = 100, quantity = 3 }, { unitPrice = 150, quantity = 100 } }
        local r = GC.Flips.RecommendPost(50, 100, nil, { levels = levels, sold = 6 })
        assert.equal("match", r.mode)
      end)

      it("falls back to undercut when opts.levels is missing", function()
        local r = GC.Flips.RecommendPost(50000, 100000, nil, { sold = 1000 })
        assert.equal("undercut", r.mode)
      end)

      it("falls back to undercut when opts.levels is empty (no levels[1] to read a cheapest price from)", function()
        local r = GC.Flips.RecommendPost(50000, 100000, nil, { levels = {}, sold = 1000 })
        assert.equal("undercut", r.mode)
      end)

      it("falls back to undercut when opts.sold is missing", function()
        local levels = { { unitPrice = 100000, quantity = 1 } }
        local r = GC.Flips.RecommendPost(50000, 100000, nil, { levels = levels })
        assert.equal("undercut", r.mode)
      end)

      it("falls back to undercut when opts.sold is zero (never a match with no measured velocity)", function()
        local levels = { { unitPrice = 100000, quantity = 1 } }
        local r = GC.Flips.RecommendPost(50000, 100000, nil, { levels = levels, sold = 0 })
        assert.equal("undercut", r.mode)
      end)

      it("belowCost/breakeven are still computed correctly in match mode", function()
        local levels = { { unitPrice = 100, quantity = 10 } }
        local r = GC.Flips.RecommendPost(100, 100, nil, { levels = levels, sold = 1000 })
        -- breakeven = ceil(100/0.95) = 106; candidate (match) = 100 < 106 -> belowCost
        assert.equal("match", r.mode)
        assert.equal(106, r.breakeven)
        assert.is_true(r.belowCost)
      end)
    end)
  end)

  describe("RepostAdvice (F4)", function()
    it("returns nil when RecommendPost itself has nothing to recommend", function()
      assert.is_nil(GC.Flips.RepostAdvice({ paidUnit = 100 }))
    end)

    it("tolerates a nil args table entirely", function()
      assert.is_nil(GC.Flips.RepostAdvice(nil))
    end)

    it("hold/loss when the recommended price would lock a loss", function()
      local r = GC.Flips.RepostAdvice({ paidUnit = 1000, marketUnit = 10, qty = 1 })
      assert.equal("hold", r.action)
      assert.equal("loss", r.reason)
      assert.is_not_nil(r.rec)
    end)

    it("hold/slow when the queue at the new (recommended) price is a STALL outlook", function()
      local r = GC.Flips.RepostAdvice({
        paidUnit = 10, marketUnit = 100, qty = 100, sold = 1,
        levels = { { unitPrice = 100, quantity = 1000 } },
      })
      -- rec.unit=100 (undercut, tierDepth 1000 vs sold 1 stays undercut; grid-clamped -- see
      -- Part 0 above); aheadAtNew = DepthBelow(levels, 100) = 0 (the 100-priced level is not
      -- < 100); days = (0+100)/1 = 100 -> STALL
      assert.equal("hold", r.action)
      assert.equal("slow", r.reason)
    end)

    it("repost when nothing blocks it", function()
      local r = GC.Flips.RepostAdvice({
        paidUnit = 10, marketUnit = 100, qty = 1, sold = 1,
        levels = { { unitPrice = 100, quantity = 1000 } },
      })
      -- days = (0+1)/1 = 1 -> tier OK, not STALL
      assert.equal("repost", r.action)
      assert.equal(100, r.rec.unit) -- grid-clamped, see Part 0 above
    end)

    it("does not block on missing levels/sold data (treats an unknowable queue as ok-to-repost)", function()
      local r = GC.Flips.RepostAdvice({ paidUnit = 10, marketUnit = 100, qty = 1 })
      assert.equal("repost", r.action)
    end)

    it("loss takes precedence over slow when both would apply", function()
      local r = GC.Flips.RepostAdvice({
        paidUnit = 1000, marketUnit = 10, qty = 100, sold = 1,
        levels = { { unitPrice = 10, quantity = 1000 } },
      })
      assert.equal("hold", r.action)
      assert.equal("loss", r.reason)
    end)
  end)
end)
