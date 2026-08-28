local helper = require("spec.spec_helper")

-- The list used to rearrange itself under the cursor for the first half-minute after opening,
-- because the pricing walk answers one item at a time and Order ranks a priced stack above an
-- unpriced one. Settle is what makes a refresh change the numbers on a row instead of where the
-- row is.
describe("Sell settled order", function()
  local GC

  before_each(function()
    GC = {}
    helper.loadModule("UI/SellViewModel.lua", GC)
  end)

  local function keys(list)
    local out = {}
    for _, position in ipairs(list) do out[#out + 1] = position.positionKey end
    return out
  end

  local function bag(key, fields)
    local p = { positionKey = key, coverage = "COMPLETE", bagQty = 10 }
    for name, value in pairs(fields or {}) do p[name] = value end
    return p
  end

  it("keeps a row in place when its price finally arrives", function()
    local a, b = bag("a"), bag("b", { freshMarketUnit = 500 })
    local places = {}
    -- First render: b is priced, so Order puts it first, and that is the order that settles.
    local first = GC.SellViewModel.Settle(GC.SellViewModel.Deck({ a, b }, "post"), places)
    assert.same({ "b", "a" }, keys(first))

    -- The walk answers for `a`. Order alone would now rank it above b (same rank, higher
    -- value), which is exactly the jump a player was fighting.
    a.freshMarketUnit = 900
    local reordered = GC.SellViewModel.Deck({ a, b }, "post")
    assert.same({ "a", "b" }, keys(reordered))

    -- Settled, it does not move.
    assert.same({ "b", "a" }, keys(GC.SellViewModel.Settle(reordered, places)))
  end)

  it("appends a position it has never seen instead of shouldering into the middle", function()
    local a, b = bag("a", { freshMarketUnit = 100 }), bag("b", { freshMarketUnit = 900 })
    local places = {}
    assert.same({ "b", "a" }, keys(GC.SellViewModel.Settle(GC.SellViewModel.Deck({ a, b }, "post"), places)))
    -- Looted mid-session, and worth more than either: Order would put it first, which would
    -- push both settled rows down a line while somebody is working down the list.
    local c = bag("c", { freshMarketUnit = 5000 })
    assert.same({ "b", "a", "c" },
      keys(GC.SellViewModel.Settle(GC.SellViewModel.Deck({ a, b, c }, "post"), places)))
  end)

  it("closes the gap when a position leaves, without moving the survivors", function()
    local a, b, c = bag("a"), bag("b"), bag("c")
    local places = {}
    GC.SellViewModel.Settle({ a, b, c }, places)
    assert.same({ "a", "c" }, keys(GC.SellViewModel.Settle({ a, c }, places)))
  end)

  it("gives a fresh order once the caller throws its memory away", function()
    local a, b = bag("a"), bag("b", { freshMarketUnit = 500 })
    local places = {}
    assert.same({ "b", "a" }, keys(GC.SellViewModel.Settle(GC.SellViewModel.Deck({ a, b }, "post"), places)))
    a.freshMarketUnit = 900
    -- A new table is what "the player asked for a new order" looks like: Refresh, a deck
    -- change, a chip.
    assert.same({ "a", "b" }, keys(GC.SellViewModel.Settle(GC.SellViewModel.Deck({ a, b }, "post"), {})))
  end)

  it("keeps an unkeyed position out of the settled sequence rather than jittering it", function()
    local a = bag("a")
    local ghost = { coverage = "COMPLETE", bagQty = 1 }
    local places = {}
    assert.same({ "a" }, keys(GC.SellViewModel.Settle({ a, ghost }, places)))
    assert.equal(2, #GC.SellViewModel.Settle({ a, ghost }, places))
  end)

  it("hands the list back untouched when there is no memory to settle against", function()
    local a, b = bag("a"), bag("b")
    assert.same({ "a", "b" }, keys(GC.SellViewModel.Settle({ a, b }, nil)))
  end)
end)
