local helper = require("spec.spec_helper")

-- BUY 2.0's view rules (Core/BuyView.lua): pure, so every case is a row in a table.
describe("BuyView", function()
  local V

  before_each(function()
    V = helper.loadModule("Core/BuyView.lua").BuyView
  end)

  local BOOK = { { unit = 67, qty = 53 }, { unit = 68, qty = 156 }, { unit = 69, qty = 24 },
                 { unit = 70, qty = 514 } }

  describe("Ladder", function()
    -- The design's own example: buy 120 of Linen at a 91c cap.
    it("lists the levels the purchase takes from, then the next price up", function()
      assert.same({
        { qty = 53, unit = 67, take = 53, over = false },
        { qty = 156, unit = 68, take = 67, over = false },
        { qty = 24, unit = 69, take = 0, over = false },
      }, V.Ladder(BOOK, 120, 91))
    end)

    local cases = {
      { "a line the first level fills", 10, 91, { { 53, 67, 10, false }, { 156, 68, 0, false } } },
      { "a cap under the cheapest level", 10, 60, { { 53, 67, 0, true } } },
      { "a cap between two levels", 100, 67, { { 53, 67, 53, false }, { 156, 68, 0, true } } },
      { "no cap at all", 120, nil, { { 53, 67, 53, false }, { 156, 68, 67, false }, { 24, 69, 0, false } } },
      { "nothing left to buy", 0, 91, { { 53, 67, 0, false } } },
    }
    for _, case in ipairs(cases) do
      it(case[1], function()
        local want = {}
        for i, r in ipairs(case[4]) do want[i] = { qty = r[1], unit = r[2], take = r[3], over = r[4] } end
        assert.same(want, V.Ladder(BOOK, case[2], case[3]))
      end)
    end

    it("stops at maxRows even while it is still taking", function()
      local rows = V.Ladder(BOOK, 10000, nil, 2)
      assert.equal(2, #rows)
      assert.equal(156, rows[2].take)
    end)

    it("answers an empty list for an empty or missing book", function()
      assert.same({}, V.Ladder({}, 5, 10))
      assert.same({}, V.Ladder(nil, 5, 10))
    end)
  end)

  describe("RaiseTo", function()
    local FINE = { { unit = 186, qty = 26 }, { unit = 187, qty = 264 } }
    local cases = {
      -- The design: cheapest 1s 86c, cap 1s 40c, market 1s 87c -> raise to the market.
      { "the market when it is above the cheapest ask", FINE, 140, 187, 187 },
      { "the cheapest ask when the market is below it", FINE, 140, 150, 186 },
      { "the cheapest ask when there is no market", FINE, 140, nil, 186 },
      { "nothing when the cheapest ask already fits", FINE, 186, 187, nil },
      { "nothing for a line with no cap", FINE, nil, 187, nil },
      { "nothing for an empty book", {}, 140, 187, nil },
      { "nothing for a missing book", nil, 140, 187, nil },
    }
    for _, case in ipairs(cases) do
      it(case[1], function() assert.equal(case[5], V.RaiseTo(case[2], case[3], case[4])) end)
    end
  end)

  describe("Status", function()
    -- Whole tables, not overrides of a template: `{ cap = nil }` cannot remove a key in Lua.
    local cases = {
      { "done wins over everything", { buy = 0, cap = 100, done = true, vendor = true }, { skipped = true }, "done" },
      { "skipped", { buy = 5, cap = 100, floor = 50 }, { skipped = true }, "skipped" },
      { "a craft line", { buy = 5, cap = 100, kind = "craft" }, {}, "craft" },
      { "a vendor line", { buy = 5, cap = 100, vendor = true, floor = 500 }, {}, "vendor" },
      { "a stranded confirm", { buy = 5, cap = 100, floor = 50 }, { stranded = true }, "stranded" },
      { "not a commodity", { buy = 5, cap = 100, floor = 50 }, { byHand = true }, "lots" },
      { "the last read found nothing under the cap", { buy = 5, cap = 100, floor = 50 }, { quote = "over" }, "over" },
      { "the last read fits even though NOW says over", { buy = 5, cap = 100, floor = 150 }, { quote = "fits" }, "ready" },
      { "NOW over the cap with no read", { buy = 5, cap = 100, floor = 150 }, {}, "over" },
      { "NOW at the cap", { buy = 5, cap = 100, floor = 100 }, {}, "ready" },
      { "only a market price", { buy = 5, cap = 100, usual = 80 }, {}, "ready" },
      { "no cap and a price", { buy = 5, floor = 999 }, {}, "ready" },
      { "no price at all", { buy = 5 }, {}, "unpriced" },
    }
    for _, case in ipairs(cases) do
      it(case[1], function() assert.equal(case[4], V.Status(case[2], case[3])) end)
    end
  end)

  describe("Matches", function()
    local cases = {
      { "all keeps every status", "vendor", "Linen", "all", nil, true },
      { "nil filter is all", "done", "Linen", nil, nil, true },
      { "to buy keeps ready", "ready", "Linen", "buy", nil, true },
      { "to buy keeps unpriced, lots and stranded", "lots", "Boots", "buy", nil, true },
      { "to buy drops over", "over", "Linen", "buy", nil, false },
      { "over keeps over only", "over", "Linen", "over", nil, true },
      { "done keeps done", "done", "Linen", "done", nil, true },
      { "skipped keeps skipped", "skipped", "Linen", "skipped", nil, true },
      { "search is a plain, case-blind substring", "ready", "Linen Cloth", "all", "cLOT", true },
      { "search misses", "ready", "Linen Cloth", "all", "wool", false },
      { "search with magic characters is literal", "ready", "Linen (Cloth)", "all", "(cl", true },
      { "empty search matches", "ready", "Linen", "all", "", true },
      { "filter and search both have to agree", "vendor", "Linen", "buy", "lin", false },
    }
    for _, case in ipairs(cases) do
      it(case[1], function() assert.equal(case[6], V.Matches(case[2], case[3], case[4], case[5])) end)
    end
  end)

  it("counts progress over the run's own lines, not the reagents a split put under one", function()
    local lines = { { done = true }, { done = false }, { parent = 1, done = true }, { done = true } }
    local done, total = V.Progress(lines)
    assert.equal(2, done)
    assert.equal(3, total)
  end)

  describe("CostOf", function()
    local cases = {
      { "the quote for the whole remaining line", { buy = 10, floor = 5 }, { qty = 10, total = 70 }, 70, false },
      { "a quote for part of the line is an estimate", { buy = 10, floor = 5 }, { qty = 6, total = 30 }, 50, true },
      { "no quote: the floor", { buy = 10, floor = 5, usual = 9 }, nil, 50, true },
      { "no floor: the market", { buy = 10, usual = 9 }, nil, 90, true },
      { "nothing known", { buy = 10 }, nil, nil, nil },
      { "nothing left to buy", { buy = 0, floor = 5 }, nil, nil, nil },
    }
    for _, case in ipairs(cases) do
      it(case[1], function()
        local cost, estimated = V.CostOf(case[2], case[3])
        assert.equal(case[4], cost)
        assert.equal(case[5], estimated)
      end)
    end
  end)

  describe("MarketNote", function()
    it("says how many scanners and how old for a crowd price", function()
      assert.same({ scanners = 3, age = 720 }, V.MarketNote({ source = "crowd", scanners = 3, at = 1000 }, 1720))
    end)
    it("never reads a clock skew as negative age", function()
      assert.same({ scanners = 1, age = 0 }, V.MarketNote({ source = "crowd", scanners = 1, at = 2000 }, 1000))
    end)
    it("says nothing for any other source", function()
      assert.is_nil(V.MarketNote({ source = "own", at = 1000 }, 1720))
      assert.is_nil(V.MarketNote(nil, 1720))
      assert.is_nil(V.MarketNote({ source = "crowd" }, 1720))
    end)
  end)
end)
