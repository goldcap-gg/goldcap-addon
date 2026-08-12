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
      local result = GC.Flips.ExtractOwnedLots({ { itemKey = { itemID = 42 }, unitPrice = 500, auctionID = 1 } })
      assert.same({ { itemID = 42, unitPrice = 500, auctionID = 1 } }, result)
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
end)
