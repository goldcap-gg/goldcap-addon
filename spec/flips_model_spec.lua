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
      local row = GC.Flips.BuildRow(flip({ paidUnit = 100, qty = 3 }), {}, { unit = 1000, at = 0 }, {})
      assert.equal("UNLISTED", row.status)
      assert.is_nil(row.listedUnit)
      assert.equal(1000, row.marketUnit)
      -- basis=1000, 1000*0.95=950, -100=850, *3=2550
      assert.equal(2550, row.profit)
    end)

    it("LISTED: owned lot exists and no fresh quote to compare against", function()
      local row = GC.Flips.BuildRow(flip({ paidUnit = 100, qty = 3 }),
        lots({ itemID = 42, unitPrice = 333 }), nil, {})
      assert.equal("LISTED", row.status)
      assert.equal(333, row.listedUnit)
      assert.is_nil(row.marketUnit)
      -- basis=333, 333*0.95=316.35, -100=216.35, *3=649.05 -> floor 649
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
      -- basis=min(150,100)=100, 100*0.95=95, -100=-5, *2=-10
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

    it("floors a fractional profit toward negative infinity, not toward zero", function()
      -- basis=99, 99*0.95=94.05, -1=93.05, *1=93.05 -> floor 93 (not 94)
      local row = GC.Flips.BuildRow(flip({ paidUnit = 1, qty = 1 }),
        lots({ itemID = 42, unitPrice = 99 }), nil, {})
      assert.equal(93, row.profit)
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
        { boughtUnit = 100, qty = 2, profit = nil },
        { boughtUnit = 50, qty = 3, profit = nil },
      }
      local s = GC.Flips.Summary(rows)
      assert.equal(350, s.invested) -- 200 + 150
      assert.equal(0, s.projected)
      assert.equal(0, s.profit)
    end)

    it("Sell-tab upgrade: skips a row with boughtUnit == nil entirely (an orphan row) -- no cost basis to fold in", function()
      local rows = {
        { boughtUnit = 100, qty = 2, profit = 50 },       -- invested 200, projected 250
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
        { boughtUnit = 100, qty = 2, profit = 50 },  -- invested 200, projected 250
        { boughtUnit = 50, qty = 1, profit = nil },  -- invested 50, contributes nothing else
        { boughtUnit = 10, qty = 5, profit = -20 },  -- invested 50, projected 30
      }
      local s = GC.Flips.Summary(rows)
      assert.equal(300, s.invested)  -- 200 + 50 + 50
      assert.equal(280, s.projected) -- 250 + 30
      assert.equal(30, s.profit)     -- 50 + (-20)
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
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = { itemID = 42 }, unitPrice = 500, quantity = 3, auctionID = 1 } })
      assert.same({ { itemID = 42, unitPrice = 500, auctionID = 1, quantity = 3 } }, result)
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
    it("undercuts a live market quote by 1 copper", function()
      local r = GC.Flips.RecommendPost(100, 500, nil)
      assert.equal(499, r.unit)
    end)

    it("floors the undercut candidate at 1 copper (never zero/negative)", function()
      local r = GC.Flips.RecommendPost(1, 1, nil)
      assert.equal(1, r.unit)
    end)

    it("falls back to mv when there is no live quote", function()
      local r = GC.Flips.RecommendPost(100, nil, 800)
      assert.equal(800, r.unit)
    end)

    it("prefers a live quote over mv when both are present", function()
      local r = GC.Flips.RecommendPost(100, 500, 800)
      assert.equal(499, r.unit)
    end)

    it("returns nil when neither marketUnit nor mv is known", function()
      assert.is_nil(GC.Flips.RecommendPost(100, nil, nil))
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
      local r = GC.Flips.RecommendPost(100, 90, nil) -- candidate=89, breakeven=106
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
  end)
end)
