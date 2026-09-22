local helper = require("spec.spec_helper")

describe("FullScan.Evaluate", function()
  local GC
  local cfg = {
    hotDiscount = 0.40, hotProfit = 5000000,
    goodDiscount = 0.25, goodProfit = 1000000,
    watchDiscount = 0.10, suspectDiscount = 0.90,
  }
  local values = {
    [10] = { mv = 1000000 },   -- 100g market
    [20] = { mv = 200000000 }, -- 20000g market
    [30] = { mv = 100000 },    -- 10g market
  }
  local function getValue(id) return values[id] end

  before_each(function()
    GC = helper.loadModule("Core/DealMath.lua")
    helper.loadModule("Core/FullScan.lua", GC)
  end)

  it("derives per-unit price from a per-stack buyout", function()
    -- item 10: stack of 5 for 2500000 => unit 500000 => 50% discount vs 1000000
    local deals = GC.FullScan.Evaluate({ { itemID = 10, count = 5, buyoutStack = 2500000 } }, getValue, cfg, 100)
    assert.equal(1, #deals)
    assert.equal(500000, deals[1].unitPrice)
    assert.equal(5, deals[1].qty)
    assert.equal(0.5, deals[1].discount)
  end)

  it("marks every aggregate as a CHECK-only live-verification discovery", function()
    -- A browse aggregate can preserve its old discovery tier for sorting, but it is not a
    -- resolved purchasable lot. Even a HOT aggregate must therefore be WATCH/Check until a
    -- live commodity search supplies the book that SniperDecision can evaluate.
    local deals = GC.FullScan.Evaluate({
      { itemID = 20, count = 1, buyoutStack = 120000000 }, -- old HOT economics
      { itemID = 10, count = 1, buyoutStack = 500000 },
    }, getValue, cfg, 100)

    assert.equal("HOT", deals[1].tier) -- discovery context is retained
    for _, deal in ipairs(deals) do
      assert.equal("WATCH", deal.status)
      assert.equal("live_verification_required", deal.reason)
      assert.equal("Check", deal.action)
      assert.is_false(deal.buyable)
    end
  end)

  it("skips rows with no value, zero count, or zero buyout", function()
    local deals = GC.FullScan.Evaluate({
      { itemID = 999, count = 1, buyoutStack = 100 },   -- no market value
      { itemID = 10, count = 0, buyoutStack = 100 },    -- zero count
      { itemID = 10, count = 1, buyoutStack = 0 },      -- zero buyout
    }, getValue, cfg, 100)
    assert.equal(0, #deals)
  end)

  it("skips rows below the watch threshold", function()
    -- item 10 at 950000 unit = 5% discount < watch 10%
    local deals = GC.FullScan.Evaluate({ { itemID = 10, count = 1, buyoutStack = 950000 } }, getValue, cfg, 100)
    assert.equal(0, #deals)
  end)

  it("dedupes same-itemID rows to the single higher-profit (cheaper) deal", function()
    -- item 10, mv 1000000: one seller at 700000 (30% off, 250000 profit), one at 500000
    -- (50% off, 450000 profit). Only the cheaper/higher-profit one survives, so downstream
    -- itemID-keyed requery state can't collide on the same item.
    local deals = GC.FullScan.Evaluate({
      { itemID = 10, count = 1, buyoutStack = 700000 },
      { itemID = 10, count = 1, buyoutStack = 500000 },
    }, getValue, cfg, 100)
    assert.equal(1, #deals)
    assert.equal(10, deals[1].itemID)
    assert.equal(500000, deals[1].unitPrice)
    assert.equal(450000, deals[1].profit)
  end)

  it("sorts by tier rank then profit desc and truncates to cap", function()
    local rows = {
      { itemID = 30, count = 1, buyoutStack = 5000 },        -- 10g mv, 50% off, tiny profit => WATCH
      { itemID = 20, count = 1, buyoutStack = 120000000 },   -- 20000g mv, 40% off, big profit => HOT
      { itemID = 10, count = 1, buyoutStack = 500000 },      -- 100g mv, 50% off, ~45g profit => WATCH
    }
    local deals = GC.FullScan.Evaluate(rows, getValue, cfg, 2)
    assert.equal(2, #deals)
    assert.equal("HOT", deals[1].tier)           -- HOT first
    assert.equal(20, deals[1].itemID)
    assert.equal("WATCH", deals[2].tier)          -- then the higher-profit WATCH (item 10, 45g > item 30's ~4.5g)
    assert.equal(10, deals[2].itemID)
  end)

  -- Fix 1 (honest quantity display): avail rides the row through to the deal untouched.
  it("carries avail through from the row to the deal", function()
    local deals = GC.FullScan.Evaluate(
      { { itemID = 10, count = 5, buyoutStack = 2500000, avail = 1646 } }, getValue, cfg, 100)
    assert.equal(1646, deals[1].avail)
  end)

  it("leaves avail nil when the row carries none", function()
    local deals = GC.FullScan.Evaluate(
      { { itemID = 10, count = 5, buyoutStack = 2500000 } }, getValue, cfg, 100)
    assert.is_nil(deals[1].avail)
  end)

  -- Sniper discovery rework: the board ranks by estProfit -- the number that mirrors what a
  -- live Check would approve -- not by tier-then-mv-profit. This is the whole point of the
  -- rework: a lower-tier row whose stress exit still clears a real profit must outrank a
  -- higher-tier row whose stress exit does not.
  it("ranks a WATCH-tier row with a genuine stress profit above a HOT-tier row that has none", function()
    local stressValues = {
      -- item 1: HOT by mv-based discount/profit (discount 0.4, profit 7000g), but a stressUnit
      -- barely above its own entry price means a live Check would find almost nothing left.
      [1] = { mv = 200000000, stressUnit = 121000000 },
      -- item 2: only a WATCH-tier discount (15%), but no stressUnit means the full mv-based
      -- projection survives -- a real 100g of estimated profit.
      [2] = { mv = 10000000 },
    }
    local function getStressValue(id) return stressValues[id] end
    local rows = {
      { itemID = 1, count = 1, buyoutStack = 120000000 }, -- estProfit = -505g (see fixture comment)
      { itemID = 2, count = 1, buyoutStack = 8500000 },   -- estProfit = 100g
    }
    local deals = GC.FullScan.Evaluate(rows, getStressValue, cfg, 100)
    assert.equal(2, #deals)
    assert.equal("HOT", deals[2].tier)
    assert.equal(1, deals[2].itemID)
    assert.equal(-5050000, deals[2].estProfit)
    assert.equal("WATCH", deals[1].tier)
    assert.equal(2, deals[1].itemID)
    assert.equal(1000000, deals[1].estProfit)
  end)

  it("falls back to the old tier-then-profit order when estProfit ties", function()
    local stressValues = {
      -- item 3 (WATCH): no stressUnit, mv-based estProfit lands at 470000 on its own.
      [3] = { mv = 1000000 },
      -- item 4 (HOT): a stressUnit engineered so its estProfit lands at the SAME 470000,
      -- despite a much bigger mv-based profit (5500g).
      [4] = { mv = 100000000, stressUnit = 42600000 },
    }
    local function getStressValue(id) return stressValues[id] end
    local rows = {
      { itemID = 3, count = 1, buyoutStack = 480000 },
      { itemID = 4, count = 1, buyoutStack = 40000000 },
    }
    local deals = GC.FullScan.Evaluate(rows, getStressValue, cfg, 100)
    assert.equal(2, #deals)
    assert.equal(470000, deals[1].estProfit)
    assert.equal(470000, deals[2].estProfit)
    -- Tied on estProfit: the old tiebreak (tier rank, then mv-profit, then itemID) applies --
    -- HOT (item 4) sorts ahead of WATCH (item 3).
    assert.equal("HOT", deals[1].tier)
    assert.equal(4, deals[1].itemID)
    assert.equal("WATCH", deals[2].tier)
    assert.equal(3, deals[2].itemID)
  end)

  -- The silent drop fix: a row whose mv-discount falls below watchDiscount used to vanish from
  -- `screened` entirely, undercounting what the "N hidden" banner reports.
  it("counts a below-watch-discount drop into `screened`", function()
    local deals, screened = GC.FullScan.Evaluate({
      { itemID = 10, count = 1, buyoutStack = 950000 }, -- 5% off, below watchDiscount 0.10
    }, getValue, cfg, 100)
    assert.equal(0, #deals)
    assert.equal(1, screened)
  end)

  it("adds below-watch-discount drops to PreScreen drops in the same `screened` total", function()
    -- item 10 has no PreScreen-relevant facts (no SniperDecision loaded in this describe block,
    -- so PreScreen never runs) -- this isolates the below-watch-discount branch's own counting
    -- across two rows.
    local deals, screened = GC.FullScan.Evaluate({
      { itemID = 10, count = 1, buyoutStack = 960000 }, -- 4% off
      { itemID = 20, count = 1, buyoutStack = 199000000 }, -- 0.5% off item 20 (mv 200000000)
    }, getValue, cfg, 100)
    assert.equal(0, #deals)
    assert.equal(2, screened)
  end)
end)

-- RowsFromBrowse's estimated quantity is no longer a raw sold/day figure: the deals list used
-- to advertise flip sizes (up to a flat 200) the live safety engine would never approve, often
-- by 5x-200x (see SniperDecision.DemandCap's own spec for the measured gap). This describe
-- block deliberately loads only DealMath + FullScan, NOT SniperDecision -- it proves
-- RowsFromBrowse degrades gracefully (fails closed to a single-unit flip, never the old
-- inflated behaviour) when the engine module isn't present, and that unitPrice is invariant to
-- whatever quantity ends up chosen.
describe("FullScan.RowsFromBrowse (no SniperDecision loaded)", function()
  local GC
  local cfg = { maxDailyDemandShare = 0.02, maxQuantity = 200 }
  local values = {
    [100] = { sold = 50 },
  }
  local function getValue(id) return values[id] end

  before_each(function()
    GC = helper.loadModule("Core/DealMath.lua")
    helper.loadModule("Core/FullScan.lua", GC)
  end)

  it("fails closed to a single-unit flip when the engine module is unavailable", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 100 }, totalQuantity = 10000, minPrice = 500 },
    }, getValue, cfg)
    assert.equal(1, #rows)
    assert.equal(100, rows[1].itemID)
    assert.equal(1, rows[1].count)
    assert.equal(500, rows[1].buyoutStack)
  end)

  it("skips zero/nil minPrice and nil-itemID entries", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 100 }, totalQuantity = 10, minPrice = 0 },
      { itemKey = { itemID = 100 }, totalQuantity = 10, minPrice = nil },
      { itemKey = {}, totalQuantity = 10, minPrice = 500 },
      { totalQuantity = 10, minPrice = 500 },
    }, getValue, cfg)
    assert.equal(0, #rows)
  end)

  -- Sniper phase 2: a realm item with no region reference is not a row at all -- dropped here
  -- as well as in DealMath, so it never reaches the streaming counters or the carried-deal
  -- bookkeeping either. Commodities and referenced realm items are untouched.
  it("drops a realm row the region has no reference price for", function()
    local realmValues = {
      [100] = { mv = 2746440, kind = "realm_item", source = "import" },        -- no ref
      [101] = { mv = 1000000, ref = 900000, kind = "realm_item", source = "import" },
      [102] = { mv = 1000000, kind = "region_commodity", source = "import" },
    }
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 100 }, totalQuantity = 2, minPrice = 89999 },
      { itemKey = { itemID = 101 }, totalQuantity = 2, minPrice = 500000 },
      { itemKey = { itemID = 102 }, totalQuantity = 2, minPrice = 500000 },
    }, function(id) return realmValues[id] end, cfg)
    assert.equal(2, #rows)
    assert.equal(101, rows[1].itemID)
    assert.equal(102, rows[2].itemID)
  end)

  it("feeds Evaluate end-to-end so unitPrice comes out equal to minPrice", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 100 }, totalQuantity = 10000, minPrice = 777 },
    }, getValue, cfg)
    local dealCfg = {
      hotDiscount = 0.40, hotProfit = 5000000,
      goodDiscount = 0.25, goodProfit = 1000000,
      watchDiscount = 0.10, suspectDiscount = 0.90,
    }
    local marketValues = { [100] = { mv = 2000 } }
    local deals = GC.FullScan.Evaluate(rows, function(id) return marketValues[id] end, dealCfg, 100)
    assert.equal(1, #deals)
    assert.equal(777, deals[1].unitPrice)
  end)
end)

-- The live demand-cap path: FullScan.RowsFromBrowse calling GC.SniperDecision.DemandCap so a
-- row's suggested quantity is one a live Check could actually approve.
describe("FullScan.RowsFromBrowse (engine demand cap)", function()
  local GC
  local cfg = {
    maxDailyDemandShare = 0.02, maxQuantity = 200,
    hotDiscount = 0.40, hotProfit = 5000000,
    goodDiscount = 0.25, goodProfit = 1000000,
    watchDiscount = 0.10, suspectDiscount = 0.90,
  }
  -- Field names match GC.Data.GetItemValue's verification-block shape (Core/Data.lua), which
  -- MarketFromValue reads from directly.
  local values = {
    -- sold=5000/currentQty=5000/madBps=250 -> DemandCap = 42 (matches the measured-gap table's
    -- 5000/5000 row in SniperDecision.DemandCap's own spec).
    [400] = { mv = 1000000, sold = 5000, currentQty = 5000, madBps = 250,
      listings = 5, sellThroughBps = 7000, liquidityConfidence = 70, stressUnit = 1000000 },
    [500] = { sold = 5000, currentQty = 5000, madBps = 250 },
    [600] = { sold = 1000000, currentQty = 10, madBps = 0 },
    [700] = {},
    [800] = { sold = 5000 }, -- no currentQty: falls back to totalQuantity for stock
  }
  local function getValue(id) return values[id] end

  before_each(function()
    GC = helper.loadModule("Core/Book.lua")
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
  end)

  it("caps a high-velocity, deep-stock item at the engine's approvable quantity", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 400 }, totalQuantity = 10000, minPrice = 500000 },
    }, getValue, cfg)
    assert.equal(1, #rows)
    assert.equal(42, rows[1].count)
  end)

  it("still yields 1 for an item with no velocity data at all", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 700 }, totalQuantity = 5000, minPrice = 500 },
    }, getValue, cfg)
    assert.equal(1, rows[1].count)
  end)

  it("carries the untouched totalQuantity through as avail even though count is capped small", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 400 }, totalQuantity = 10000, minPrice = 500000 },
    }, getValue, cfg)
    assert.equal(10000, rows[1].avail)
    assert.equal(42, rows[1].count)
  end)

  it("falls back to totalQuantity when it is smaller than the demand cap", function()
    -- Item 500's demand cap alone would be 42 (same market facts as item 400), but only 30
    -- units are actually listed -- can't flip more than what's on the board.
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 500 }, totalQuantity = 30, minPrice = 500 },
    }, getValue, cfg)
    assert.equal(30, rows[1].count)
  end)

  it("caps qty at the player's ceiling even when the raw demand-cap arithmetic would allow far more", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 600 }, totalQuantity = 100000, minPrice = 500 },
    }, getValue, cfg)
    assert.equal(200, rows[1].count)
  end)

  -- The flip size a row advertises is the one a live Check can approve: raise the ceiling and
  -- the board follows it, up to the engine's own bound and no further.
  it("follows a raised ceiling, and stops at the engine's bound", function()
    local browse = { { itemKey = { itemID = 600 }, totalQuantity = 100000, minPrice = 500 } }
    local raised = { maxDailyDemandShare = 0.02, maxQuantity = 1000 }
    local wild = { maxDailyDemandShare = 0.02, maxQuantity = 100000000 }
    local atRaised = GC.FullScan.RowsFromBrowse(browse, getValue, raised)[1].count
    local atWild = GC.FullScan.RowsFromBrowse(browse, getValue, wild)[1].count
    assert.is_true(atRaised > 200 and atRaised <= 1000, "count " .. atRaised)
    assert.is_true(atWild <= GC.SniperDecision.MAX_QUANTITY_CEILING, "count " .. atWild)
    assert.equal(GC.SniperDecision.DemandCap(
      GC.SniperDecision.MarketFromValue(getValue(600)), raised, 0), atRaised)
  end)

  it("falls back to the browse result's totalQuantity for stock when currentQty is absent", function()
    -- Item 800 carries no currentQty (no verification block), so the substitution documented
    -- in RowsFromBrowse's comment applies: totalQuantity stands in for stock. A shallow board
    -- (30, supplyFactor near 1) yields a demand cap immediately clipped back down to the board
    -- itself; a deep board (100000, supplyFactor near 0) yields a much smaller demand cap --
    -- proving the fallback value is actually reaching the formula, not just being ignored.
    local shallow = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 800 }, totalQuantity = 30, minPrice = 500 },
    }, getValue, cfg)
    local deep = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 800 }, totalQuantity = 100000, minPrice = 500 },
    }, getValue, cfg)
    assert.equal(30, shallow[1].count)
    assert.equal(4, deep[1].count)
  end)

  -- The whole point of the fix: a row's profit is the per-unit margin times a quantity the
  -- engine could actually approve, not an inflated number the safety engine would refuse.
  it("produces a profit equal to the per-unit margin times the capped quantity", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 400 }, totalQuantity = 10000, minPrice = 500000 },
    }, getValue, cfg)
    local deals = GC.FullScan.Evaluate(rows, getValue, cfg, 100)
    assert.equal(1, #deals)
    assert.equal(42, deals[1].qty)
    local expectedUnitMargin = math.floor(1000000 * 0.95) - 500000
    assert.equal(expectedUnitMargin * 42, deals[1].profit)
    assert.equal("HOT", deals[1].tier)
  end)
end)

describe("EvaluateDelta/MergeDeals", function()
  local GC
  local settings = {
    hotDiscount = 0.40, hotProfit = 5000000,
    goodDiscount = 0.25, goodProfit = 1000000,
    watchDiscount = 0.10, suspectDiscount = 0.90,
  }

  before_each(function()
    GC = helper.loadModule("Core/DealMath.lua")
    helper.loadModule("Core/FullScan.lua", GC)
  end)

  -- EvaluateDelta consumes the same { itemID, count, buyoutStack } row shape Evaluate
  -- already does (what RowsFromBrowse produces), so reuse that shape rather than the raw
  -- C_AuctionHouse browse-result shape used by the RowsFromBrowse tests above.
  local function mkBrowseRow(itemID, buyoutStack, count)
    return { itemID = itemID, count = count or 1, buyoutStack = buyoutStack }
  end

  local function mkDeal(itemID, unitPrice, overrides)
    overrides = overrides or {}
    local deal = {
      itemID = itemID,
      isCommodity = false,
      auctionID = nil,
      unitPrice = unitPrice,
      qty = 1,
      mv = 1000000,
      discount = 0.5,
      profit = 100000,
      tier = "WATCH",
      falling = false,
    }
    for k, v in pairs(overrides) do deal[k] = v end
    return deal
  end

  local function findDeal(deals, itemID)
    for _, deal in ipairs(deals) do
      if deal.itemID == itemID then return deal end
    end
    return nil
  end

  it("evaluates only rows past fromIndex", function()
    local values = { [1] = { mv = 200 }, [2] = { mv = 400 }, [3] = { mv = 600 } }
    local function getValue(id) return values[id] end
    local rows = { mkBrowseRow(1, 100), mkBrowseRow(2, 100), mkBrowseRow(3, 100) }

    local deals, n = GC.FullScan.EvaluateDelta(rows, 2, getValue, settings)
    assert.equals(3, n)
    assert.equals(1, #deals)          -- only item 3 evaluated
    assert.equals(3, deals[1].itemID)
  end)

  -- Fix 1 (honest quantity display): EvaluateDelta's per-row Evaluate call carries avail
  -- through exactly like the single-shot Evaluate already does (fullscan_spec above).
  it("carries avail through EvaluateDelta", function()
    local values = { [1] = { mv = 200 } }
    local function getValue(id) return values[id] end
    local rows = { { itemID = 1, count = 1, buyoutStack = 100, avail = 500 } }

    local deals = GC.FullScan.EvaluateDelta(rows, 0, getValue, settings)
    assert.equal(500, deals[1].avail)
  end)

  it("evaluates nothing when fromIndex is already at the end", function()
    local values = { [1] = { mv = 200 }, [2] = { mv = 400 } }
    local function getValue(id) return values[id] end
    local rows = { mkBrowseRow(1, 100), mkBrowseRow(2, 100) }

    local deals, n = GC.FullScan.EvaluateDelta(rows, 2, getValue, settings)
    assert.equals(2, n)
    assert.equals(0, #deals)
  end)

  it("merge dedupes by itemID with the incoming row winning unconditionally", function()
    local a = { mkDeal(1, 100), mkDeal(2, 300) }
    local b = { mkDeal(2, 250) }
    local m = GC.FullScan.MergeDeals(a, b, 100)
    assert.equals(2, #m)
    assert.equals(250, findDeal(m, 2).unitPrice)
  end)

  it("merge lets the incoming row win even when it is pricier", function()
    -- A second scan pass's fresher row replaces the first pass's cheaper one: the cheap
    -- listing may already be gone (bought out, requoted, or expired) by the time the new
    -- pass ran, so keeping it would advertise a lot that no longer exists.
    local a = { mkDeal(1, 100) }
    local b = { mkDeal(1, 150) }
    local m = GC.FullScan.MergeDeals(a, b, 100)
    assert.equals(1, #m)
    assert.equals(150, findDeal(m, 1).unitPrice)
  end)

  it("merge lets the incoming row win even at an identical price", function()
    local a = { mkDeal(1, 100, { profit = 111 }) }
    local b = { mkDeal(1, 100, { profit = 222 }) }
    local m = GC.FullScan.MergeDeals(a, b, 100)
    assert.equals(1, #m)
    assert.equals(222, findDeal(m, 1).profit)
  end)

  it("merge respects cap and final Evaluate equals single-shot", function()
    -- 5 rows, all past the watch threshold with distinct profit so the sort order is
    -- unambiguous: item5 (highest profit) ... item1 (lowest).
    local values = {
      [1] = { mv = 200 }, [2] = { mv = 400 }, [3] = { mv = 600 },
      [4] = { mv = 800 }, [5] = { mv = 1000 },
    }
    local function getValue(id) return values[id] end
    local rows = {
      mkBrowseRow(1, 100), mkBrowseRow(2, 100), mkBrowseRow(3, 100),
      mkBrowseRow(4, 100), mkBrowseRow(5, 100),
    }

    -- Stream in two chunks: rows 1-3 arrive first, then rows 4-5.
    local firstChunk = { rows[1], rows[2], rows[3] }
    local deals1 = GC.FullScan.EvaluateDelta(firstChunk, 0, getValue, settings)
    local merged = GC.FullScan.MergeDeals({}, deals1, 100)

    local deals2, n2 = GC.FullScan.EvaluateDelta(rows, 3, getValue, settings)
    assert.equals(5, n2)
    merged = GC.FullScan.MergeDeals(merged, deals2, 100)

    local single = GC.FullScan.Evaluate(rows, getValue, settings, 100)
    assert.same(single, merged)

    -- Cap truncation matches a single-shot capped Evaluate too.
    local mergedCapped = GC.FullScan.MergeDeals(merged, {}, 2)
    local singleCapped = GC.FullScan.Evaluate(rows, getValue, settings, 2)
    assert.same(singleCapped, mergedCapped)
  end)
end)

-- Sniper v3 §3 ping (fix round 1, I2/I6): pulled out of SniperFrame.lua so both of its call
-- sites (the streaming per-page merge and the scan-completion reconcile) share one tested
-- rule instead of two copies that could drift.
describe("FullScan.CollectNewHot", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/FullScan.lua")
  end)

  local function mkDeal(itemID, unitPrice, tier)
    return { itemID = itemID, unitPrice = unitPrice, tier = tier }
  end

  it("collects an unseen HOT deal and marks its key seen", function()
    local seen = {}
    local newly = GC.FullScan.CollectNewHot({ mkDeal(1, 100, "HOT") }, seen)
    assert.equals(1, #newly)
    assert.equals(1, newly[1].itemID)
    assert.is_true(seen["1@100"])
  end)

  it("skips a HOT deal whose key is already in `seen`", function()
    local seen = { ["1@100"] = true }
    local newly = GC.FullScan.CollectNewHot({ mkDeal(1, 100, "HOT") }, seen)
    assert.equals(0, #newly)
  end)

  it("ignores non-HOT deals entirely, even unseen ones", function()
    local seen = {}
    local newly = GC.FullScan.CollectNewHot({
      mkDeal(1, 100, "GOOD"), mkDeal(2, 200, "WATCH"), mkDeal(3, 300, "SUSPECT"),
    }, seen)
    assert.equals(0, #newly)
    assert.is_nil(seen["1@100"]) -- non-HOT deals never touch `seen` either
  end)

  it("returns an empty list for an empty deals array", function()
    local newly = GC.FullScan.CollectNewHot({}, {})
    assert.equals(0, #newly)
  end)

  it("a different price for the same item is a NEW key, even if the old price was seen", function()
    local seen = { ["1@100"] = true }
    local newly = GC.FullScan.CollectNewHot({ mkDeal(1, 90, "HOT") }, seen)
    assert.equals(1, #newly)
    assert.is_true(seen["1@90"])
  end)
end)

describe("FullScan.ApplyLiveObservation", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/FullScan.lua")
  end)

  local function deal(itemID, tier, profit, unitPrice)
    return {
      itemID = itemID,
      tier = tier,
      profit = profit,
      unitPrice = unitPrice,
      qty = 1,
    }
  end

  local function find(deals, itemID)
    for _, candidate in ipairs(deals) do
      if candidate.itemID == itemID then return candidate end
    end
    return nil
  end

  it("replaces exactly one candidate even when the live price rises", function()
    local first = deal(10, "GOOD", 500, 100)
    local untouched = deal(20, "WATCH", 200, 300)
    local raised = deal(10, "WATCH", 250, 150)

    local updated = GC.FullScan.ApplyLiveObservation({ first, untouched }, 10, raised, 100)

    assert.equal(2, #updated)
    assert.is_true(find(updated, 10) == raised)
    assert.is_true(find(updated, 20) == untouched)
  end)

  it("removes only the observed item when it is no longer a deal", function()
    local keep = deal(20, "WATCH", 200, 300)
    local updated = GC.FullScan.ApplyLiveObservation({ deal(10, "GOOD", 500, 100), keep }, 10, nil, 100)

    assert.equal(1, #updated)
    assert.is_nil(find(updated, 10))
    assert.is_true(updated[1] == keep)
  end)

  it("re-adds a removed target and preserves comparator order and cap", function()
    local watch = deal(20, "WATCH", 200, 300)
    local hot = deal(10, "HOT", 900, 80)
    local updated = GC.FullScan.ApplyLiveObservation({ watch }, 10, hot, 2)

    assert.same({ hot, watch }, updated)
    assert.same({ hot }, GC.FullScan.ApplyLiveObservation(updated, 30, deal(30, "GOOD", 800, 90), 1))
  end)
end)

-- The Items board (UI/SniperFrame.lua's GC.Sniper._realmDeals) is a MAP of itemID -> deal that
-- the key poll keeps adding to, under a board that renders at most a hundred rows. Nothing
-- else in this file caps a store that is not an array.
describe("FullScan.CapDeals", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/FullScan.lua")
  end)

  local function deal(itemID, profit)
    return { itemID = itemID, tier = "WATCH", profit = profit, estProfit = profit,
      unitPrice = 100, qty = 1 }
  end

  it("returns a map's deals in the board's own order, best first", function()
    local store = { [1] = deal(1, 100), [2] = deal(2, 900), [3] = deal(3, 500) }
    local kept = GC.FullScan.CapDeals(store, 10)
    assert.same({ 2, 3, 1 }, { kept[1].itemID, kept[2].itemID, kept[3].itemID })
  end)

  it("drops the worst keys from the map itself once it is over the cap", function()
    local store = {}
    for id = 1, 120 do store[id] = deal(id, id * 1000) end -- item 120 is the best lead

    local kept = GC.FullScan.CapDeals(store, 100)

    assert.equal(100, #kept)
    assert.equal(120, kept[1].itemID)
    -- The store is trimmed too, not merely reported on: it is what the next fold adds to.
    local left = 0
    for _ in pairs(store) do left = left + 1 end
    assert.equal(100, left)
    assert.is_nil(store[1])   -- the twenty cheapest leads are gone
    assert.is_nil(store[20])
    assert.is_table(store[21])
    assert.is_table(store[120])
  end)

  it("leaves a map alone when it is under the cap", function()
    local store = { [7] = deal(7, 10) }
    assert.equal(1, #GC.FullScan.CapDeals(store, 100))
    assert.is_table(store[7])
  end)

  -- The store is keyed by itemID, and an item id is an integer, so a store holding item 1 is
  -- indistinguishable from an array -- which is why this caps by KEY and never by position.
  it("caps by key, so a store that happens to hold item 1 is not read as an array", function()
    local store = { [1] = deal(1, 100), [2] = deal(2, 900), [3] = deal(3, 500) }
    local kept = GC.FullScan.CapDeals(store, 2)
    assert.same({ 2, 3 }, { kept[1].itemID, kept[2].itemID })
    assert.is_nil(store[1])
    assert.is_table(store[2])
    assert.is_table(store[3])
  end)

  -- Final review M7: the comparator ranks by estProfit against the MARKET, and a cap deal
  -- needs no market at all (Core/Caps.lua's own contract) -- so a cap set ABOVE the region
  -- reference, which the design wants shown in red, carries a NEGATIVE estProfit and sorts
  -- last. On a full board it was then the first thing truncated away, and the one row the
  -- player themselves asked for never reached the screen. A cap row is the player's standing
  -- instruction, not a lead this addon found: it is never dropped to make room.
  local function capDeal(itemID, profit)
    local d = deal(itemID, profit)
    d.cap = 1000
    return d
  end

  it("never truncates a cap row off a full board, however badly it ranks", function()
    local store = {}
    for id = 1, 10 do store[id] = deal(id, id * 1000) end
    store[99] = capDeal(99, -5000) -- a cap above the reference: worst possible estProfit

    local kept = GC.FullScan.CapDeals(store, 5)

    assert.equal(5, #kept)
    assert.is_table(store[99])
    assert.equal(99, kept[#kept].itemID) -- still last in the board's own order
    -- The cap row costs an ordinary one its place; the board does not grow past its own cap.
    assert.same({ 10, 9, 8, 7 }, { kept[1].itemID, kept[2].itemID, kept[3].itemID, kept[4].itemID })
    assert.is_nil(store[6])
  end)

  it("keeps every cap row even when the caps alone exceed the board", function()
    local store = {}
    for id = 1, 8 do store[id] = capDeal(id, -id) end
    store[50] = deal(50, 9000)

    local kept = GC.FullScan.CapDeals(store, 3)

    assert.equal(8, #kept) -- every cap, and no budget left for the ordinary lead
    assert.is_nil(store[50])
    for id = 1, 8 do assert.is_table(store[id]) end
  end)
end)
