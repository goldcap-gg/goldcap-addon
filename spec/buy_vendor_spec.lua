local helper = require("spec.spec_helper")

-- Buying a list's vendor lines at a merchant (Core/BuyVendor.lua). The merchant sells in stacks
-- (`stackCount` units for `price`), a purchase quantity is in units, and one call buys at most
-- GetMerchantItemMaxStack units.
describe("BuyVendor", function()
  local V
  before_each(function() V = helper.loadModule("Core/BuyVendor.lua").BuyVendor end)

  local THREAD = { index = 3, itemID = 2320, price = 10, stackCount = 1, numAvailable = -1,
    isPurchasable = true, hasExtendedCost = false, maxStack = 20 }
  local VIAL = { index = 5, itemID = 3371, price = 20, stackCount = 5, numAvailable = -1,
    isPurchasable = true, hasExtendedCost = false, maxStack = 20 }

  describe("Offers", function()
    it("reads what each item costs a unit and how many one call may buy", function()
      local o = V.Offers({ THREAD, VIAL })
      assert.same({ index = 3, price = 10, stack = 1, unit = 10, maxStack = 20 }, o[2320])
      assert.equal(4, o[3371].unit)
    end)
    it("skips what gold cannot buy, what is not for sale and what is sold out", function()
      local o = V.Offers({
        { index = 1, itemID = 1, price = 10, stackCount = 1, isPurchasable = true, hasExtendedCost = true, maxStack = 1 },
        { index = 2, itemID = 2, price = 10, stackCount = 1, isPurchasable = false, maxStack = 1 },
        { index = 4, itemID = 4, price = 10, stackCount = 1, isPurchasable = true, numAvailable = 0, maxStack = 1 },
      })
      assert.is_nil(next(o))
    end)
    it("keeps limited stock as a limit", function()
      local o = V.Offers({ { index = 6, itemID = 6, price = 100, stackCount = 1, numAvailable = 3, isPurchasable = true, maxStack = 1 } })
      assert.equal(3, o[6].available)
    end)
  end)

  describe("Plan", function()
    local OFFERS
    before_each(function() OFFERS = V.Offers({ THREAD, VIAL }) end)
    it("buys the line's remaining need in calls of at most the merchant's max", function()
      local p = V.Plan({ { itemID = 2320, buy = 45, name = "Coarse Thread" } }, OFFERS, 100000)[1]
      assert.same({ itemID = 2320, index = 3, qty = 45, cost = 450, calls = { 20, 20, 5 }, short = false,
        name = "Coarse Thread" }, p)
    end)
    it("rounds up to the merchant's stack", function()
      local p = V.Plan({ { itemID = 3371, buy = 12 } }, OFFERS, 100000)[1]
      assert.equal(15, p.qty)
      assert.equal(60, p.cost)
      assert.same({ 15 }, p.calls)
    end)
    -- Review Focus 4.
    it("buys only what the wallet can pay, and says it is short", function()
      local p = V.Plan({ { itemID = 2320, buy = 45 } }, OFFERS, 205)[1]
      assert.equal(20, p.qty)
      assert.equal(200, p.cost)
      assert.is_true(p.short)
    end)
    it("offers nothing it cannot pay a single stack of", function()
      local p = V.Plan({ { itemID = 3371, buy = 5 } }, OFFERS, 19)[1]
      assert.equal(0, p.qty)
      assert.is_true(p.short)
    end)
    it("holds a limited item to the merchant's stock", function()
      local offers = V.Offers({ { index = 6, itemID = 6, price = 100, stackCount = 1, numAvailable = 3, isPurchasable = true, maxStack = 1 } })
      local p = V.Plan({ { itemID = 6, buy = 10 } }, offers, 100000)[1]
      assert.equal(3, p.qty)
      assert.same({ 1, 1, 1 }, p.calls)
    end)
    it("leaves out lines this merchant does not sell and lines with nothing left", function()
      assert.same({}, V.Plan({ { itemID = 999, buy = 5 }, { itemID = 2320, buy = 0 } }, OFFERS, 100000))
    end)
  end)

  describe("Settle", function()
    local PENDING = { itemID = 2320, qty = 45, unit = 10, countBefore = 5 }
    it("credits what arrived, at the merchant's own price", function()
      assert.same({ itemID = 2320, qty = 45, spent = 450 }, V.Settle(PENDING, 50))
    end)
    it("says nothing while nothing has arrived", function()
      assert.is_nil(V.Settle(PENDING, 5))
    end)
    -- Review Focus 5: loot of the same item landing meanwhile is not this purchase.
    it("never credits more than the press asked for", function()
      assert.same({ itemID = 2320, qty = 45, spent = 450 }, V.Settle(PENDING, 58))
    end)
    it("credits a part that arrived", function()
      assert.same({ itemID = 2320, qty = 20, spent = 200 }, V.Settle(PENDING, 25))
    end)
  end)
end)
