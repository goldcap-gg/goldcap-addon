local helper = require("spec.spec_helper")

describe("DealMath", function()
  local GC
  local cfg = {
    hotDiscount = 0.40, hotProfit = 5000000,
    goodDiscount = 0.25, goodProfit = 1000000,
    watchDiscount = 0.10, suspectDiscount = 0.90,
  }

  before_each(function()
    GC = helper.loadModule("Core/DealMath.lua")
  end)

  local function live(unitPrice, qty)
    return { itemID = 42, isCommodity = false, auctionID = 7, unitPrice = unitPrice, qty = qty or 1 }
  end

  describe("Evaluate", function()
    it("returns nil without a market value", function()
      assert.is_nil(GC.DealMath.Evaluate(live(100), nil, cfg))
      assert.is_nil(GC.DealMath.Evaluate(live(100), { mv = 0 }, cfg))
    end)

    it("returns nil below the watch threshold", function()
      -- 5% discount
      assert.is_nil(GC.DealMath.Evaluate(live(9500000), { mv = 10000000 }, cfg))
    end)

    it("computes discount and after-cut profit", function()
      -- mv 100g, price 50g, qty 2: profit = (95g - 50g) * 2 = 90g
      local d = GC.DealMath.Evaluate(live(500000, 2), { mv = 1000000 }, cfg)
      assert.equal(0.5, d.discount)
      assert.equal(900000, d.profit)
      assert.equal(2, d.qty)
      assert.equal(42, d.itemID)
      assert.equal(7, d.auctionID)
    end)

    it("tiers HOT when discount and profit clear the bars", function()
      -- mv 20000g, price 10000g: discount 0.5, profit = 9000g >= 500g
      local d = GC.DealMath.Evaluate(live(100000000), { mv = 200000000 }, cfg)
      assert.equal("HOT", d.tier)
    end)

    it("tiers GOOD on mid discount with enough profit", function()
      -- mv 1000g, price 700g: discount 0.3, profit = 250g >= 100g
      local d = GC.DealMath.Evaluate(live(7000000), { mv = 10000000 }, cfg)
      assert.equal("GOOD", d.tier)
    end)

    it("downgrades big discount with tiny profit to WATCH", function()
      -- mv 10g, price 5g: discount 0.5 but profit 4.5g < 100g
      local d = GC.DealMath.Evaluate(live(50000), { mv = 100000 }, cfg)
      assert.equal("WATCH", d.tier)
    end)

    it("flags near-free listings as SUSPECT before HOT", function()
      -- mv 100000g, price 100g: discount 0.999
      local d = GC.DealMath.Evaluate(live(1000000), { mv = 1000000000 }, cfg)
      assert.equal("SUSPECT", d.tier)
    end)

    it("qualifies an exact watch-boundary discount", function()
      -- mv 100g, price 90g: discount exactly 0.10 (float ratio ~0.09999999999999998)
      local d = GC.DealMath.Evaluate(live(900000), { mv = 1000000 }, cfg)
      assert.is_not_nil(d)
      assert.equal("WATCH", d.tier)
    end)

    it("tiers HOT on an exact hot-boundary discount with big profit", function()
      -- mv 20000g, price 12000g: discount exactly 0.40, profit 7000g >= 500g
      local d = GC.DealMath.Evaluate(live(120000000), { mv = 200000000 }, cfg)
      assert.equal("HOT", d.tier)
    end)

    it("tiers GOOD on an exact good-boundary discount", function()
      -- mv 1000g, price 750g: discount exactly 0.25, profit 200g >= 100g
      local d = GC.DealMath.Evaluate(live(7500000), { mv = 10000000 }, cfg)
      assert.equal("GOOD", d.tier)
    end)

    it("does not flag an exact suspect-boundary discount as SUSPECT", function()
      -- mv 100g, price 10g: discount exactly 0.90 — strict > rule must not fire
      local d = GC.DealMath.Evaluate(live(100000), { mv = 1000000 }, cfg)
      assert.not_equal("SUSPECT", d.tier)
    end)

    it("carries commodity fields through", function()
      local d = GC.DealMath.Evaluate(
        { itemID = 7, isCommodity = true, unitPrice = 500000, qty = 10 },
        { mv = 1000000 }, cfg)
      assert.is_true(d.isCommodity)
      assert.is_nil(d.auctionID)
      assert.equal(10, d.qty)
      assert.equal(1000000, d.mv)
      assert.equal(500000, d.unitPrice)
    end)
  end)

  describe("PriceIncreaseExceeds", function()
    it("is false at or under the tolerance", function()
      assert.is_false(GC.DealMath.PriceIncreaseExceeds(1000, 1050, 0.05))
    end)
    it("is true over the tolerance", function()
      assert.is_true(GC.DealMath.PriceIncreaseExceeds(1000, 1051, 0.05))
    end)
    it("treats a float-exact tolerance as not exceeded", function()
      -- 700 * 1.15 = 804.99999999999989 in IEEE doubles; 805 is exactly the tolerance
      assert.is_false(GC.DealMath.PriceIncreaseExceeds(700, 805, 0.15))
      assert.is_true(GC.DealMath.PriceIncreaseExceeds(700, 806, 0.15))
    end)
  end)
end)
