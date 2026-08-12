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
end)

describe("FullScan.RowsFromBrowse", function()
  local GC
  local values = {
    [100] = { sold = 50 },   -- a day's sold volume bounds the flip qty
    [200] = {},              -- no sold figure at all (unknown liquidity)
    [300] = { sold = 5000 }, -- sold volume far past the hard sanity cap
  }
  local function getValue(id) return values[id] end

  before_each(function()
    GC = helper.loadModule("Core/DealMath.lua")
    helper.loadModule("Core/FullScan.lua", GC)
  end)

  it("caps estimated qty at a day's sold volume for a commodity-like entry", function()
    -- totalQuantity (10000) is far above sold (50): flip qty is bounded by what's
    -- realistically sellable in a day, not by how much is listed.
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 100 }, totalQuantity = 10000, minPrice = 500 },
    }, getValue)
    assert.equal(1, #rows)
    assert.equal(100, rows[1].itemID)
    assert.equal(50, rows[1].count)
    assert.equal(500 * 50, rows[1].buyoutStack)
  end)

  -- Fix 1 (honest quantity display): avail is the market's REAL total, independent of the
  -- suggested flip size above -- the "x200 when the market really has 1646" bug this fixes.
  it("emits avail = totalQuantity alongside the (possibly much smaller) estimated qty", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 100 }, totalQuantity = 1646, minPrice = 500 },
    }, getValue)
    assert.equal(1646, rows[1].avail)
    assert.equal(50, rows[1].count) -- unchanged: still capped by sold/day
  end)

  it("falls back to totalQuantity when it is the smaller bound", function()
    -- Only 30 are actually listed, even though sold/day (50) would allow more -- can't flip
    -- more than what's on the board.
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 100 }, totalQuantity = 30, minPrice = 500 },
    }, getValue)
    assert.equal(30, rows[1].count)
  end)

  it("collapses to qty 1 when there is no sold figure", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 200 }, totalQuantity = 10000, minPrice = 500 },
    }, getValue)
    assert.equal(1, #rows)
    assert.equal(1, rows[1].count)
  end)

  it("caps qty at 200 even when sold volume is huge", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 300 }, totalQuantity = 10000, minPrice = 500 },
    }, getValue)
    assert.equal(200, rows[1].count)
  end)

  it("skips zero/nil minPrice and nil-itemID entries", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 100 }, totalQuantity = 10, minPrice = 0 },
      { itemKey = { itemID = 100 }, totalQuantity = 10, minPrice = nil },
      { itemKey = {}, totalQuantity = 10, minPrice = 500 },
      { totalQuantity = 10, minPrice = 500 },
    }, getValue)
    assert.equal(0, #rows)
  end)

  it("feeds Evaluate end-to-end so unitPrice comes out equal to minPrice", function()
    local rows = GC.FullScan.RowsFromBrowse({
      { itemKey = { itemID = 100 }, totalQuantity = 10000, minPrice = 777 },
    }, getValue)
    local cfg = {
      hotDiscount = 0.40, hotProfit = 5000000,
      goodDiscount = 0.25, goodProfit = 1000000,
      watchDiscount = 0.10, suspectDiscount = 0.90,
    }
    local marketValues = { [100] = { mv = 2000 } }
    local deals = GC.FullScan.Evaluate(rows, function(id) return marketValues[id] end, cfg, 100)
    assert.equal(1, #deals)
    assert.equal(777, deals[1].unitPrice)
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
