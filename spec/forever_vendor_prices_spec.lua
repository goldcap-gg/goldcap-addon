local helper = require("spec.spec_helper")

-- Core/ForeverVendorPrices.lua: WoW: Forever's merchant prices for crafting reagents, as the
-- player saw them at a merchant. Offers are GC.BuyVendor.Offers' answer for that merchant.
describe("Forever merchant prices", function()
  local GC, V

  before_each(function()
    GC = helper.loadModule("Core/BuyVendor.lua")
    helper.loadModule("Core/ForeverVendorPrices.lua", GC)
    V = GC.ForeverVendorPrices
  end)

  local function reagents(...)
    local set = {}
    for _, id in ipairs({ ... }) do set[id] = true end
    return function(id) return set[id] == true end
  end

  -- What one of an item costs for each merchant offer, whole copper, never under what is paid.
  local UNITS = {
    { name = "one for 10c", offer = { price = 10, stack = 1 }, unit = 10 },
    { name = "a stack of 5 for 10c, 2c each", offer = { price = 10, stack = 5 }, unit = 2 },
    { name = "a stack of 3 for 10c, rounded up", offer = { price = 10, stack = 3 }, unit = 4 },
    { name = "a stack of 20 for 1c, rounded up to 1c", offer = { price = 1, stack = 20 }, unit = 1 },
    { name = "a price of nothing is no price", offer = { price = 0, stack = 1 }, unit = nil },
    { name = "a stack of none is no price", offer = { price = 10, stack = 0 }, unit = nil },
    { name = "a price that is not a number is no price", offer = { price = "x", stack = 1 }, unit = nil },
  }
  for _, case in ipairs(UNITS) do
    it("keeps " .. case.name, function()
      local root = {}
      V.Record(root, { [2320] = case.offer }, reagents(2320), 100)
      assert.equal(case.unit, V.UnitFor(root, 2320))
    end)
  end

  it("keeps only crafting reagents, from the merchant's own offers", function()
    local root = {}
    local offers = GC.BuyVendor.Offers({
      { index = 1, itemID = 2320, price = 10, stackCount = 1, numAvailable = -1 },  -- Coarse Thread
      { index = 2, itemID = 159, price = 25, stackCount = 1, numAvailable = -1 },   -- water: not a reagent
      { index = 3, itemID = 3371, price = 20, stackCount = 1, numAvailable = 0 },   -- sold out: not an offer
      { index = 4, itemID = 2324, price = 25, stackCount = 1, hasExtendedCost = true }, -- not for gold
    })
    assert.equal(1, V.Record(root, offers, reagents(2320, 3371, 2324), 100))
    assert.equal(10, V.UnitFor(root, 2320))
    for _, id in ipairs({ 159, 3371, 2324 }) do assert.is_nil(V.UnitFor(root, id), id) end
    assert.same({ v = 1, items = { [2320] = { u = 10, at = 100 } } }, root.foreverVendor)
  end)

  it("takes the newest visit's price: reputation can change what a merchant asks", function()
    local root = {}
    V.Record(root, { [2320] = { price = 10, stack = 1 } }, reagents(2320), 100)
    V.Record(root, { [2320] = { price = 9, stack = 1 } }, reagents(2320), 200)
    assert.equal(9, V.UnitFor(root, 2320))
    assert.equal(200, root.foreverVendor.items[2320].at)
  end)

  it("keeps a price a later merchant does not sell", function()
    local root = {}
    V.Record(root, { [2320] = { price = 10, stack = 1 } }, reagents(2320), 100)
    V.Record(root, { [3371] = { price = 20, stack = 1 } }, reagents(3371), 200)
    assert.equal(10, V.UnitFor(root, 2320))
    assert.equal(20, V.UnitFor(root, 3371))
  end)

  it("makes no store until a merchant sells a reagent", function()
    local root = {}
    assert.equal(0, V.Record(root, { [159] = { price = 25, stack = 1 } }, reagents(), 100))
    assert.is_nil(root.foreverVendor)
    assert.is_nil(V.UnitFor(root, 159))
  end)

  -- A store a newer GoldCap wrote, or one of another shape, is neither read nor written.
  local FOREIGN = {
    { name = "a newer version", store = { v = 2, items = { [2320] = { u = 10, at = 1 } } } },
    { name = "no items table", store = { v = 1 } },
    { name = "not a table", store = "x" },
  }
  for _, case in ipairs(FOREIGN) do
    it("leaves " .. case.name .. " alone", function()
      local root = { foreverVendor = case.store }
      assert.equal(0, V.Record(root, { [2320] = { price = 7, stack = 1 } }, reagents(2320), 100))
      assert.is_nil(V.UnitFor(root, 2320))
      assert.equal(case.store, root.foreverVendor)
    end)
  end

  -- A kept price that is not whole copper above zero (a hand-edited save) is no price.
  for _, u in ipairs({ 0, -5, 2.5, "10" }) do
    it("reads no price from a kept " .. tostring(u), function()
      local root = { foreverVendor = { v = 1, items = { [2320] = { u = u, at = 1 } } } }
      assert.is_nil(V.UnitFor(root, 2320))
    end)
  end

  it("answers nothing without a save, an id or offers", function()
    assert.is_nil(V.UnitFor(nil, 2320))
    assert.is_nil(V.UnitFor({}, nil))
    assert.equal(0, V.Record(nil, { [2320] = { price = 10, stack = 1 } }, reagents(2320), 100))
    assert.equal(0, V.Record({}, nil, reagents(2320), 100))
    assert.equal(0, V.Record({}, {}, nil, 100))
  end)
end)
