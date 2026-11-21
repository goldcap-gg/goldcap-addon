local helper = require("spec.spec_helper")

-- The sold side of the owned list: NormalizeOwnedLots hands the sold rows back on their own, the
-- live lot of a sold row's auctionID carries what sold, SellPositions.Build adds it up per
-- position, and GC.SoldLots says what MY LOTS shows of it (Core/SoldLots.lua).
describe("Sold lots", function()
  local GC
  local context = { char = "A-R", region = "eu" }
  local SHELLFISH = 13545

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua")
    GC = helper.loadModule("Core/Flips.lua", GC)
    GC = helper.loadModule("Core/QuoteCache.lua", GC)
    GC = helper.loadModule("Core/SellPositions.lua", GC)
    GC = helper.loadModule("Core/SoldLots.lua", GC)
    GC.L = setmetatable({}, { __index = function(_, key) return key end })
  end)

  -- The owner's read, WoW: Forever, 2026-11-21.
  local function shellfish(order)
    local rows = {
      { auctionID = 198344858, itemKey = { itemID = SHELLFISH }, isCommodity = true, quantity = 5, status = 1,
        buyoutAmount = 1100, timeLeftSeconds = 3591 },
      { auctionID = 198344858, itemKey = { itemID = SHELLFISH }, isCommodity = true, quantity = 10, status = 0,
        buyoutAmount = 220, timeLeftSeconds = 28776 },
    }
    return order == "live first" and { rows[2], rows[1] } or rows
  end

  describe("NormalizeOwnedLots", function()
    for _, order in ipairs({ "sold first", "live first" }) do
      it("keeps a part-sold lot's 10 live units, with its 5 sold (" .. order .. ")", function()
        local lots, sold = GC.SellPositions.NormalizeOwnedLots(shellfish(order), 500)
        assert.equal(1, #lots)
        assert.same({ positionKey = "commodity:13545", itemID = SHELLFISH, quantity = 10, unitPrice = 220,
          auctionID = 198344858, firstSeenAt = 500, isCommodity = true, expiresAt = 500 + 28776,
          soldQty = 5, soldTotal = 1100 }, lots[1])
        assert.same({ { auctionID = 198344858, itemID = SHELLFISH, positionKey = "commodity:13545",
          isCommodity = true, soldQty = 5, soldTotal = 1100, seenAt = 500 } }, sold)
      end)
    end

    local cases = {
      { name = "a fully sold lot is a sold row and no lot",
        rows = { { auctionID = 7, itemKey = { itemID = 42 }, isCommodity = true, quantity = 62, status = 1,
          buyoutAmount = 6200 } },
        lots = 0, sold = { { auctionID = 7, soldQty = 62, soldTotal = 6200 } } },
      { name = "a sold row with no total still counts as sold, with none",
        rows = { { auctionID = 7, itemKey = { itemID = 42 }, isCommodity = true, quantity = 3, status = 1 } },
        lots = 0, sold = { { auctionID = 7, soldQty = 3 } } },
      { name = "separate auctionIDs (no merged rows) leave the live lot with nothing sold",
        rows = { { auctionID = 7, itemKey = { itemID = 42 }, isCommodity = true, quantity = 3, status = 1,
          buyoutAmount = 30 },
          { auctionID = 8, itemKey = { itemID = 42 }, isCommodity = true, quantity = 9, status = 0, buyoutAmount = 10 } },
        lots = 1, liveSold = nil, sold = { { auctionID = 7, soldQty = 3, soldTotal = 30 } } },
      { name = "no sold rows at all (a client that returns none)",
        rows = { { auctionID = 8, itemKey = { itemID = 42 }, isCommodity = true, quantity = 9, status = 0, buyoutAmount = 10 } },
        lots = 1, liveSold = nil, sold = {} },
      { name = "two sold rows of one lot add up on it",
        rows = { { auctionID = 8, itemKey = { itemID = 42 }, isCommodity = true, quantity = 2, status = 1, buyoutAmount = 20 },
          { auctionID = 8, itemKey = { itemID = 42 }, isCommodity = true, quantity = 3, status = 1, buyoutAmount = 30 },
          { auctionID = 8, itemKey = { itemID = 42 }, isCommodity = true, quantity = 9, status = 0, buyoutAmount = 10 } },
        lots = 1, liveSold = 5, liveTotal = 50,
        sold = { { auctionID = 8, soldQty = 2, soldTotal = 20 }, { auctionID = 8, soldQty = 3, soldTotal = 30 } } },
    }
    for _, case in ipairs(cases) do
      it(case.name, function()
        local lots, sold = GC.SellPositions.NormalizeOwnedLots(case.rows, 500)
        assert.equal(case.lots, #lots)
        if lots[1] then
          assert.equal(case.liveSold, lots[1].soldQty)
          assert.equal(case.liveTotal, lots[1].soldTotal)
        end
        assert.equal(#case.sold, #sold)
        for i, want in ipairs(case.sold) do
          assert.equal(want.auctionID, sold[i].auctionID)
          assert.equal(want.soldQty, sold[i].soldQty)
          assert.equal(want.soldTotal, sold[i].soldTotal)
        end
      end)
    end
  end)

  describe("SellPositions.Build", function()
    it("carries the sold units on the position, and lists only the live ones", function()
      local lots = GC.SellPositions.NormalizeOwnedLots(shellfish(), 500)
      local positions = GC.SellPositions.Build({ ownedLots = lots, context = context, now = 600 })
      assert.equal(1, #positions)
      assert.equal(10, positions[1].listedQty)
      assert.equal(2200, positions[1].listedValue)
      assert.equal(5, positions[1].soldQty)
      assert.equal(1100, positions[1].soldTotal)
    end)

    it("leaves soldQty unset on a position nothing of which sold", function()
      local lots = GC.SellPositions.NormalizeOwnedLots({ shellfish()[2] }, 500)
      local positions = GC.SellPositions.Build({ ownedLots = lots, context = context, now = 600 })
      assert.is_nil(positions[1].soldQty)
      assert.is_nil(positions[1].soldTotal)
    end)
  end)

  describe("SoldLots.Summary", function()
    local function row(auctionID, key, qty, total, soldAt)
      return { auctionID = auctionID, positionKey = key, itemID = tonumber(key:match("%d+$")), soldQty = qty,
        soldTotal = total, soldAt = soldAt }
    end
    local LIVE = { { auctionID = 1 } }

    local cases = {
      { name = "nothing sold", sold = {}, sales = 0, net = nil, soldOut = 0, chips = {}, more = 0 },
      { name = "a part sold: on its live lot, not SOLD OUT", sold = { row(1, "commodity:42", 5, 1100) },
        sales = 1, net = 1045, soldOut = 0, chips = { 1045 }, more = 0, byAuction = { [1] = 1045 } },
      { name = "a lot sold out", sold = { row(2, "commodity:43", 62, 10000) },
        sales = 1, net = 9500, soldOut = 1, outQty = { 62 }, chips = { 9500 }, more = 0 },
      { name = "two sold-out lots of one item are one SOLD OUT row",
        sold = { row(2, "commodity:43", 2, 100), row(3, "commodity:43", 3, 200) },
        sales = 2, net = 95 + 190, soldOut = 1, outQty = { 5 }, chips = { 285 }, more = 0 },
      { name = "the two items that brought most are the chips, the rest is +N more",
        sold = { row(1, "commodity:42", 1, 100), row(2, "commodity:43", 1, 900), row(3, "commodity:44", 1, 500),
          row(4, "commodity:45", 1, 10) },
        sales = 4, net = 95 + 855 + 475 + 9, soldOut = 3, chips = { 855, 475 }, more = 2 },
      { name = "a sold row with no total adds nothing to the money and makes no chip",
        sold = { row(2, "commodity:43", 4, nil), row(3, "commodity:44", 1, 100) },
        sales = 2, net = 95, soldOut = 2, outQty = { 4, 1 }, chips = { 95 }, more = 0 },
    }
    for _, case in ipairs(cases) do
      it(case.name, function()
        local summary = GC.SoldLots.Summary(case.sold, LIVE)
        assert.equal(case.sales, summary.sales)
        assert.equal(case.net, summary.net)
        assert.equal(case.soldOut, #summary.soldOut)
        for i, qty in ipairs(case.outQty or {}) do assert.equal(qty, summary.soldOut[i].soldQty) end
        local chips = {}
        for i, chip in ipairs(summary.chips) do chips[i] = chip.net end
        assert.same(case.chips, chips)
        assert.equal(case.more, summary.more)
        for id, net in pairs(case.byAuction or {}) do assert.equal(net, summary.byAuction[id].net) end
      end)
    end

    it("the banner's money is the chips' money and the rest, so they add up", function()
      local summary = GC.SoldLots.Summary({ row(2, "commodity:43", 1, 333), row(3, "commodity:44", 1, 777) }, {})
      assert.equal(summary.chips[1].net + summary.chips[2].net, summary.net)
    end)

    it("counts only the rows the GROUPS pick keeps", function()
      local summary = GC.SoldLots.Summary({ row(2, "commodity:43", 1, 100), row(3, "commodity:44", 1, 100) }, {},
        function(key) return key == "commodity:44" end)
      assert.equal(1, summary.sales)
      assert.equal("commodity:44", summary.soldOut[1].positionKey)
    end)
  end)

  describe("SoldLots.Stamp", function()
    it("dates a sale only when a read close before it did not have it", function()
      local memory = {}
      local first = { { auctionID = 1, soldQty = 5 } }
      GC.SoldLots.Stamp(memory, first, 1000, nil)
      assert.is_nil(first[1].soldAt) -- there at the first read: when it sold is not known
      local later = { { auctionID = 1, soldQty = 5 }, { auctionID = 2, soldQty = 3 } }
      GC.SoldLots.Stamp(memory, later, 1100, 1000)
      assert.is_nil(later[1].soldAt)
      assert.equal(1100, later[2].soldAt)
      local after = { { auctionID = 2, soldQty = 3 }, { auctionID = 3, soldQty = 1 } }
      GC.SoldLots.Stamp(memory, after, 1100 + 3600, 1100) -- an hour since the last read
      assert.equal(1100, after[1].soldAt)
      assert.is_nil(after[2].soldAt)
    end)

    it("says how long ago, in minutes and then hours", function()
      assert.equal("51 min ago", GC.SoldLots.Ago(1000, 1000 + 51 * 60 + 20))
      assert.equal("3 h ago", GC.SoldLots.Ago(1000, 1000 + 3 * 3600 + 5))
      assert.is_nil(GC.SoldLots.Ago(nil, 1000))
    end)
  end)
end)
