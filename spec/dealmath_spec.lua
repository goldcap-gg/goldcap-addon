local helper = require("spec.spec_helper")

describe("DealMath", function()
  local GC
  local cfg = {
    hotDiscount = 0.40, hotProfit = 5000000,
    goodDiscount = 0.25, goodProfit = 1000000,
    watchDiscount = 0.10, suspectDiscount = 0.90,
    hotMinSold = 3, goodMinSold = 1,
    dumpTrendPct = 10,
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

    describe("liquidity gate (import-sourced values only)", function()
      -- mv 20000g, price 10000g: discount 0.5, profit 9000g -- clears HOT's discount+profit
      -- bars on its own, so every case below isolates the sold/day gate.
      local function hotLevel(sold)
        return { mv = 200000000, source = "import", sold = sold }
      end

      it("caps a zero-sold import deal below GOOD despite HOT-level discount/profit", function()
        local d = GC.DealMath.Evaluate(live(100000000), hotLevel(0), cfg)
        assert.equal("WATCH", d.tier)
      end)

      it("treats a missing sold figure on an import value as zero", function()
        local d = GC.DealMath.Evaluate(live(100000000), { mv = 200000000, source = "import" }, cfg)
        assert.equal("WATCH", d.tier)
      end)

      it("allows HOT once sold clears hotMinSold", function()
        local d = GC.DealMath.Evaluate(live(100000000), hotLevel(3), cfg)
        assert.equal("HOT", d.tier)
      end)

      it("allows GOOD but denies HOT for a sold figure between the two floors", function()
        local d = GC.DealMath.Evaluate(live(100000000), hotLevel(1.5), cfg)
        assert.equal("GOOD", d.tier)
      end)

      it("skips the gate entirely for bundled values, even with no sold figure", function()
        local d = GC.DealMath.Evaluate(live(100000000), { mv = 200000000, source = "bundled" }, cfg)
        assert.equal("HOT", d.tier)
      end)
    end)

    describe("anti-dump gate (falling trend)", function()
      -- mv 20000g, price 10000g: discount 0.5, profit 9000g -- clears HOT's
      -- discount+profit bars on its own (bundled source, so the liquidity
      -- gate never enters into it), so every case below isolates the trend
      -- gate.
      local function bundledLevel(trend)
        return { mv = 200000000, source = "bundled", trend = trend }
      end

      it("caps an otherwise-HOT deal to WATCH when trend clears -dumpTrendPct", function()
        local d = GC.DealMath.Evaluate(live(100000000), bundledLevel(-10), cfg)
        assert.equal("WATCH", d.tier)
        assert.is_true(d.falling)
      end)

      it("caps further below the threshold too", function()
        local d = GC.DealMath.Evaluate(live(100000000), bundledLevel(-40), cfg)
        assert.equal("WATCH", d.tier)
        assert.is_true(d.falling)
      end)

      it("does not gate a trend just short of the threshold", function()
        local d = GC.DealMath.Evaluate(live(100000000), bundledLevel(-9), cfg)
        assert.equal("HOT", d.tier)
        assert.is_false(d.falling)
      end)

      it("does not gate a rising (positive) trend", function()
        local d = GC.DealMath.Evaluate(live(100000000), bundledLevel(25), cfg)
        assert.equal("HOT", d.tier)
        assert.is_false(d.falling)
      end)

      it("passes through (no gate) when trend is missing -- current behavior", function()
        local d = GC.DealMath.Evaluate(live(100000000), { mv = 200000000, source = "bundled" }, cfg)
        assert.equal("HOT", d.tier)
        assert.is_false(d.falling)
      end)

      it("leaves SUSPECT untouched by a falling trend", function()
        -- mv 100000g, price 100g: discount 0.999 -- SUSPECT regardless of trend.
        local d = GC.DealMath.Evaluate(live(1000000), { mv = 1000000000, source = "bundled", trend = -90 }, cfg)
        assert.equal("SUSPECT", d.tier)
      end)

      it("composes with the liquidity gate: either one alone denies HOT/GOOD", function()
        -- Import-sourced, sold clears both floors (would be HOT on its own),
        -- but a falling trend still caps it to WATCH.
        local d = GC.DealMath.Evaluate(
          live(100000000), { mv = 200000000, source = "import", sold = 5, trend = -15 }, cfg)
        assert.equal("WATCH", d.tier)
        assert.is_true(d.falling)
      end)

      it("composes the other way: liquidity gate alone still denies HOT/GOOD despite a rising trend", function()
        local d = GC.DealMath.Evaluate(
          live(100000000), { mv = 200000000, source = "import", sold = 0, trend = 25 }, cfg)
        assert.equal("WATCH", d.tier)
        assert.is_false(d.falling)
      end)
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
