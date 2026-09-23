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
    GC = helper.loadModule("Core/Book.lua")
    helper.loadModule("Core/DealMath.lua", GC)
  end)

  local function live(unitPrice, qty)
    return { itemID = 42, isCommodity = false, auctionID = 7, unitPrice = unitPrice, qty = qty or 1 }
  end

  describe("Evaluate", function()
    it("returns nil without a market value", function()
      assert.is_nil(GC.DealMath.Evaluate(live(100), nil, cfg))
      assert.is_nil(GC.DealMath.Evaluate(live(100), { mv = 0 }, cfg))
    end)

    -- Measured in game 2026-09-11, before the T section shipped: two listings of Leather
    -- Gauntlets of the Sun, 90,000 and 5.4 million, made a realm "median" of 2.7 million -- so
    -- the cheap one rendered as 97% off with 2.5 million gold of profit nobody could ever
    -- collect. A realm item is a deal against the REGION's price for it or it is not a row.
    it("returns nil for a realm item the region has no reference price for", function()
      assert.is_nil(GC.DealMath.Evaluate(live(89999),
        { mv = 2746440, kind = "realm_item", source = "import" }, cfg))
    end)

    it("evaluates the same realm item once a region reference exists", function()
      local d = GC.DealMath.Evaluate(live(500000),
        { mv = 1000000, ref = 1000000, kind = "realm_item", source = "import" }, cfg)
      assert.is_table(d)
      assert.equal(0.5, d.discount)
    end)

    it("leaves commodities alone -- their market value is a region figure already", function()
      local d = GC.DealMath.Evaluate(live(500000),
        { mv = 1000000, kind = "region_commodity", source = "import" }, cfg)
      assert.is_table(d)
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

    -- Fix 1 (honest quantity display): avail (the market's real total, distinct from `qty`,
    -- the amount this deal proposes to buy) rides through from `live` to the returned deal.
    it("carries avail through when present on live", function()
      local d = GC.DealMath.Evaluate(
        { itemID = 42, isCommodity = false, auctionID = 7, unitPrice = 500000, qty = 2, avail = 1646 },
        { mv = 1000000 }, cfg)
      assert.equal(1646, d.avail)
    end)

    it("leaves avail nil when live carries none", function()
      local d = GC.DealMath.Evaluate(live(500000, 2), { mv = 1000000 }, cfg)
      assert.is_nil(d.avail)
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

      it("gates a region-payload value exactly like an imported one", function()
        local quiet = GC.DealMath.Evaluate(live(100000000), { mv = 200000000, source = "region", sold = 0 }, cfg)
        assert.equal("WATCH", quiet.tier)
        local selling = GC.DealMath.Evaluate(live(100000000), { mv = 200000000, source = "region", sold = 3 }, cfg)
        assert.equal("HOT", selling.tier)
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

  describe("estProfit (Sniper discovery rework)", function()
    -- mv 100g, price 50g, qty 2 -- same fixture as the plain-profit test above, but with a
    -- stressUnit below mv so estExitUnit is genuinely stressUnit, not the mv fallback.
    it("uses stressUnit as the exit when it sits below mv", function()
      local d = GC.DealMath.Evaluate(live(500000, 2), { mv = 1000000, stressUnit = 800000 }, cfg)
      assert.equal(800000, d.estExitUnit)
      -- estProfit = floor(800000 * 2 * 0.95) - 500000 * 2 = 1520000 - 1000000
      assert.equal(520000, d.estProfit)
    end)

    it("caps estExitUnit at mv when stressUnit sits above it", function()
      local d = GC.DealMath.Evaluate(live(500000, 2), { mv = 1000000, stressUnit = 1500000 }, cfg)
      assert.equal(1000000, d.estExitUnit)
      -- Same arithmetic as the plain `profit` fixture: capped exit equals mv.
      assert.equal(900000, d.estProfit)
    end)

    it("falls back to mv when the value carries no stressUnit at all", function()
      local d = GC.DealMath.Evaluate(live(500000, 2), { mv = 1000000 }, cfg)
      assert.equal(1000000, d.estExitUnit)
      assert.equal(900000, d.estProfit)
    end)

    it("falls back to mv for a non-positive stressUnit", function()
      local d = GC.DealMath.Evaluate(live(500000, 2), { mv = 1000000, stressUnit = 0 }, cfg)
      assert.equal(1000000, d.estExitUnit)
      assert.equal(900000, d.estProfit)
    end)

    it("applies the 5% cut to the exact gross total, not per-unit", function()
      -- gross = 333333 * 3 = 999999; * 0.95 = 949999.05 -> floors to 949999; entry 300000*3=900000
      local d = GC.DealMath.Evaluate(live(300000, 3), { mv = 900000, stressUnit = 333333 }, cfg)
      assert.equal(333333, d.estExitUnit)
      assert.equal(49999, d.estProfit)
    end)

    it("can go negative when the stress exit does not clear the entry cost", function()
      local d = GC.DealMath.Evaluate(live(500000, 1), { mv = 1000000, stressUnit = 400000 }, cfg)
      -- floor(400000*0.95) - 500000 = 380000 - 500000 = -120000
      assert.equal(-120000, d.estProfit)
    end)
  end)

  -- The player's "Min profit per buy" on the board, not only on Check and the fast loop's
  -- trigger. In game 2026-09-23 a Coastal Rejuvenation Potion sat on the Deals board at 97% off
  -- and +92s: its planned buy projected 2s 61c against a 5g floor, and half the board wore AVOID.
  describe("BoardAdmits", function()
    local floor = { minimumProfitCopper = 50000, watchPins = {} }

    it("turns away a row whose projected profit is under the player's minimum", function()
      -- The potion: 3s asking against a 1g market value, stress exit 5s 91c, one unit.
      local d = GC.DealMath.Evaluate(live(300, 1), { mv = 10000, stressUnit = 591 }, cfg)
      assert.equal(261, d.estProfit)
      assert.is_false(GC.DealMath.BoardAdmits(d, floor))
    end)

    it("measures the buy the row plans, the figure Evaluate already projects", function()
      -- 2 units at 50g against a stress exit of 80g: 1520000 - 1000000 = 52g. Its mv-based
      -- `profit` (90g) is not the yardstick; estProfit is.
      local d = GC.DealMath.Evaluate(live(500000, 2), { mv = 1000000, stressUnit = 800000 }, cfg)
      assert.is_true(GC.DealMath.BoardAdmits(d, { minimumProfitCopper = 520000 }))
      assert.is_false(GC.DealMath.BoardAdmits(d, { minimumProfitCopper = 520001 }))
    end)

    it("keeps a pinned item whatever it projects: the player asked to watch it", function()
      local d = GC.DealMath.Evaluate(live(300, 1), { mv = 10000, stressUnit = 591 }, cfg)
      assert.is_true(GC.DealMath.BoardAdmits(d, { minimumProfitCopper = 50000, watchPins = { 7, 42 } }))
    end)

    it("keeps a YOUR PRICE row whatever it projects: the price is the player's", function()
      assert.is_true(GC.DealMath.BoardAdmits({ itemID = 42, cap = 1000, estProfit = -5000 }, floor))
    end)

    it("admits everything when no minimum is set", function()
      local d = GC.DealMath.Evaluate(live(300, 1), { mv = 10000, stressUnit = 591 }, cfg)
      assert.is_true(GC.DealMath.BoardAdmits(d, {}))
      assert.is_true(GC.DealMath.BoardAdmits(d, nil))
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

  describe("SellUnit", function()
    it("returns the market value untouched without a competing ask", function()
      local unit, clamped, ratio = GC.DealMath.SellUnit(1000000, nil)
      assert.equal(1000000, unit)
      assert.is_false(clamped)
      assert.is_nil(ratio)
    end)

    it("keeps the market value when the book is asking more", function()
      -- mv 100g, cheapest surviving ask 200g: nothing forces a markdown
      local unit, clamped, ratio = GC.DealMath.SellUnit(1000000, 2000000)
      assert.equal(1000000, unit)
      assert.is_false(clamped)
      assert.equal(0.5, ratio)
    end)

    it("clamps to one copper under the competing ask", function()
      -- mv 100g, cheapest surviving ask 40g: you cannot list above 39g99s99c
      local unit, clamped, ratio = GC.DealMath.SellUnit(1000000, 400000)
      assert.equal(399999, unit)
      assert.is_true(clamped)
      assert.equal(2.5, ratio)
    end)

    it("leaves a legitimate snipe alone", function()
      -- mv 20g, the rest of the book sits at 19g50s -- the profit must survive
      local unit, clamped = GC.DealMath.SellUnit(200000, 195000)
      assert.equal(194999, unit)
      assert.is_true(clamped)
      assert.is_true(unit > 190000)
    end)

    it("never returns a non-positive price", function()
      local unit = GC.DealMath.SellUnit(1000000, 1)
      assert.equal(1, unit)
    end)

    it("guards against a zero market value without competing ask", function()
      local unit, _, ratio = GC.DealMath.SellUnit(0, nil)
      assert.equal(1, unit)
      assert.is_true(unit > 0)
      assert.is_nil(ratio)
    end)

    it("guards against a negative market value without competing ask", function()
      local unit, _, ratio = GC.DealMath.SellUnit(-100000, nil)
      assert.equal(1, unit)
      assert.is_true(unit > 0)
      assert.is_nil(ratio)
    end)

    it("guards against a negative market value with competing ask present", function()
      local unit, clamped, ratio = GC.DealMath.SellUnit(-100000, 500000)
      assert.is_true(unit > 0)
      assert.equal(499999, unit)
      assert.is_true(clamped)
      assert.is_nil(ratio)
    end)
  end)

  describe("RequoteSeverity", function()
    it("stays quiet within tolerance", function()
      local severity, ratio = GC.DealMath.RequoteSeverity(1000, 1040, 0.05, 0.25)
      assert.equal("none", severity)
      assert.equal(1.04, ratio)
    end)

    it("warns past the warn ratio", function()
      assert.equal("warn", (GC.DealMath.RequoteSeverity(1000, 1100, 0.05, 0.25)))
    end)

    it("goes loud past the loud ratio", function()
      local severity, ratio = GC.DealMath.RequoteSeverity(1000, 2900, 0.05, 0.25)
      assert.equal("loud", severity)
      assert.equal(2.9, ratio)
    end)

    it("treats an exactly-at-threshold rise as still within tolerance", function()
      -- matches PriceIncreaseExceeds' own epsilon contract: strictly greater, not >=
      assert.equal("none", (GC.DealMath.RequoteSeverity(1000000, 1050000, 0.05, 0.25)))
      assert.equal("warn", (GC.DealMath.RequoteSeverity(1000000, 1250000, 0.05, 0.25)))
    end)

    it("reports none, and no ratio, without a usable quote", function()
      local severity, ratio = GC.DealMath.RequoteSeverity(0, 5000, 0.05, 0.25)
      assert.equal("none", severity)
      assert.is_nil(ratio)
    end)

    it("never reports a rise for a price that fell", function()
      assert.equal("none", (GC.DealMath.RequoteSeverity(1000, 400, 0.05, 0.25)))
    end)
  end)

  describe("the 2026-08-10 overpay incident", function()
    it("does not project a fantasy profit off a market value the book contradicts", function()
      -- 418 muffins. The import said mv 195g; the realm's book said the item changes
      -- hands around 35g. The dialog showed +63,201g60s of profit and the owner bought.
      local G = 10000
      local book = {
        { unitPrice = 12 * G, quantity = 30 },
        { unitPrice = 30 * G, quantity = 200 },
        { unitPrice = 40 * G, quantity = 500 },
      }

      local fill = GC.Book.Fill(book, 418)
      assert.equal(418, fill.filled)
      assert.equal(40 * G, fill.competing)

      local sellUnit, clamped, ratio = GC.DealMath.SellUnit(195 * G, fill.competing)
      assert.is_true(clamped)
      assert.is_true(ratio > 4)

      local profit = math.floor(sellUnit * 0.95) * 418 - fill.total
      assert.is_true(profit < 3000 * G)

      -- What the unclamped formula produced, for contrast.
      local fantasy = math.floor(195 * G * 0.95) * 418 - fill.total
      assert.is_true(fantasy > 60000 * G)
    end)
  end)
end)
