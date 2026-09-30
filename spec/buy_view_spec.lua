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
end)
