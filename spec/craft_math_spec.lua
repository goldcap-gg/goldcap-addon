local helper = require("spec.spec_helper")

-- Core/CraftMath.lua: what one craft costs, what it sells for after the auction house cut, the
-- profit, profit an hour, the slow mark and the ranking. Prices are injected functions, in copper.
describe("craft maths", function()
  local M

  before_each(function()
    M = helper.loadModule("Core/CraftMath.lua").CraftMath
  end)

  local function unit(t) return function(id) return t[id] end end
  local SLOT = { slotIndex = 1, q = 3, ids = { 101, 102, 103 } }
  local R = { recipeID = 7, name = "Potion", per = 1, output = 900, outputs = { 900, 901 }, slots = { SLOT } }

  it("prices each required slot at its cheapest priced quality", function()
    assert.same({ 103, 400 }, { M.SlotChoice(SLOT, unit({ [102] = 500, [103] = 400 })) })
    assert.same({ 101, 400 }, { M.SlotChoice(SLOT, unit({ [101] = 400, [103] = 400 })) }) -- tie: lower quality
    assert.same({}, { M.SlotChoice({ slotIndex = 2, q = 1, currency = 3008 }, unit({})) })
  end)

  it("gives no choice when no quality of a reagent has a price", function()
    assert.same({}, { M.SlotChoice(SLOT, unit({})) })
  end)

  it("prices an allocated slot as allocated", function()
    local r = M.Profit(R, unit({ [101] = 500, [102] = 450, [103] = 400 }), unit({ [900] = 10000 }),
      { alloc = { [1] = { { itemID = 101, q = 2 }, { itemID = 102, q = 1 } } } })
    assert.same({ cost = 1450, sells = 9500, profit = 8050 }, r)
  end)

  it("falls back to the cheapest quality when the allocation does not cover the slot", function()
    local r = M.Profit(R, unit({ [101] = 500, [103] = 400 }), unit({ [900] = 10000 }),
      { alloc = { [1] = { { itemID = 101, q = 1 } } } })
    assert.equal(1200, r.cost)
  end)

  it("takes the 5% cut off each unit sold, times the units one craft makes", function()
    local two = { recipeID = 7, name = "Potion", per = 2, output = 900, outputs = { 900 }, slots = { SLOT } }
    assert.same({ cost = 1200, sells = 19000, profit = 17800 }, M.Profit(two, unit({ [103] = 400 }), unit({ [900] = 10000 })))
  end)

  it("names every reagent and the crafted item with no price, and gives no figure", function()
    local both = { recipeID = 7, name = "Potion", per = 1, output = 900, outputs = { 900 },
      slots = { SLOT, { slotIndex = 2, q = 1, currency = 3008 } } }
    assert.same({ missing = { { itemID = 101 }, { currencyID = 3008 }, { itemID = 900 } } },
      M.Profit(both, unit({}), unit({})))
  end)

  it("names an allocated reagent with no price instead of pricing another quality", function()
    assert.same({ missing = { { itemID = 102 } } }, M.Profit(R, unit({ [103] = 400 }), unit({ [900] = 10000 }),
      { alloc = { [1] = { { itemID = 102, q = 3 } } } }))
  end)

  it("prices the crafted item the window shows over the recipe's usual one", function()
    local r = M.Profit(R, unit({ [103] = 400 }), unit({ [900] = 10000, [901] = 20000 }), { output = 901 })
    assert.equal(19000, r.sells)
  end)

  it("shows a loss as a negative profit", function()
    local r = M.Profit(R, unit({ [103] = 4000 }), unit({ [900] = 10000 }))
    assert.same({ cost = 12000, sells = 9500, profit = -2500 }, r)
  end)

  it("works out profit an hour from the market's daily sales", function()
    assert.equal(5000, M.PerHour(10000, 12, 1))
    assert.equal(2500, M.PerHour(10000, 12, 2))
    assert.is_nil(M.PerHour(10000, nil, 1))
  end)

  it("marks a recipe slow when its item sells under once a day", function()
    assert.is_true(M.IsSlow(0.5)); assert.is_true(M.IsSlow(0))
    assert.is_false(M.IsSlow(1)); assert.is_false(M.IsSlow(nil))
  end)

  it("ranks by profit per craft and counts recipes it cannot price", function()
    local ranked, unpriced = M.Rank({
      { recipeID = 1, name = "B", result = { profit = 500 } },
      { recipeID = 2, name = "C", result = { profit = 900 } },
      { recipeID = 3, name = "D", result = { missing = { { itemID = 1 } } } },
      { recipeID = 4, name = "A", result = { profit = 500 } } })
    assert.same({ 2, 4, 1 }, { ranked[1].recipeID, ranked[2].recipeID, ranked[3].recipeID })
    assert.equal(3, #ranked); assert.equal(1, unpriced)
  end)

  it("breaks a tie of profit and name by recipe id", function()
    local ranked = M.Rank({
      { recipeID = 9, name = "Same", result = { profit = 100 } },
      { recipeID = 3, name = "Same", result = { profit = 100 } } })
    assert.same({ 3, 9 }, { ranked[1].recipeID, ranked[2].recipeID })
  end)
end)
