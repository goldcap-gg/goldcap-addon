local helper = require("spec.spec_helper")

-- The position-in-the-book study (docs/research/2026-08-31-position-in-the-book.md): inside
-- the cheapest quarter of an item's listings the 24h sale rate is flat, and within one price
-- level the newest lot sells first. So a fresh post one occupied rung above the cheapest ask
-- sells at the same odds and pays more -- as long as it stays under the quarter line and the
-- units queued beneath it fit a turnover budget.
describe("RecommendPost overcut", function()
  local GC
  before_each(function() GC = helper.loadModule("Core/Flips.lua", {}) end)

  local function level(unitPrice, quantity) return { unitPrice = unitPrice, quantity = quantity } end

  -- 1g cheapest, rungs every half silver, then a wall.
  local ladder = {
    level(10000, 400), level(10500, 300), level(11000, 300), level(12000, 2000), level(15000, 5000),
  }

  it("posts at the highest occupied rung under the quarter whose queue fits six hours", function()
    -- budget = 4000 * 6 / 24 = 1000: 10500 (700 queued) fits, 11000 (1000) fits, cap is 11000.
    local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = ladder, sold = 4000, quarterUnit = 11000 })
    assert.equal("overcut", r.mode)
    assert.equal(11000, r.unit)
    assert.equal(700, r.ahead) -- units strictly below the chosen rung
  end)

  it("stops under a wall even when the quarter line sits above it", function()
    -- cap 12000, but the 12000 rung would queue 3000 > 1000.
    local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = ladder, sold = 4000, quarterUnit = 12000 })
    assert.equal("overcut", r.mode)
    assert.equal(11000, r.unit)
    assert.equal(700, r.ahead)
  end)

  it("takes one grid step above the cheapest when no occupied rung fits under the cap", function()
    local thin = { level(10000, 400), level(13000, 100) }
    local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = thin, sold = 4000, quarterUnit = 11000 })
    assert.equal("overcut", r.mode)
    assert.equal(10100, r.unit)
    assert.equal(400, r.ahead)
  end)

  it("declines when the cheapest tier alone exceeds the budget (the 90k-shards case)", function()
    -- 22k a day, 90k sitting at the cheapest: budget 5500 < 90000, so no rung is reachable.
    local shards = { level(50000, 90000), level(52000, 100) }
    local r = GC.Flips.RecommendPost(nil, 50000, 55000, { levels = shards, sold = 22000, quarterUnit = 52000 })
    assert.not_equal("overcut", r.mode)
    assert.is_true(r.unit <= 50000)
  end)

  it("declines when the quarter line is at or below the cheapest ask", function()
    local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = ladder, sold = 4000, quarterUnit = 10000 })
    assert.not_equal("overcut", r.mode)
    local moved = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = ladder, sold = 4000, quarterUnit = 9000 })
    assert.not_equal("overcut", moved.mode)
  end)

  it("declines without a sold figure", function()
    local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = ladder, quarterUnit = 11000 })
    assert.not_equal("overcut", r.mode)
    assert.is_nil(r.ahead)
  end)

  it("leaves the F3 match rule exactly as before when no quarter line is given", function()
    -- sold 4000 >= 2 * 400 (cheapest tier): F3 matches the cheapest.
    local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = ladder, sold = 4000 })
    assert.equal("match", r.mode)
    assert.equal(10000, r.unit)
  end)

  it("lets a flip's queue-at-exit raise climb above the overcut rung", function()
    -- absorb 24h => budget 4000: rungs up to 12000 (3000 queued) fit, 15000 is above the
    -- 12000 target, so the ceiling itself is proven and wins.
    local r = GC.Flips.RecommendPost(nil, 10000, 12000,
      { levels = ladder, sold = 4000, quarterUnit = 11000, targetUnit = 12000, absorbHours = 24 })
    assert.equal("queue", r.mode)
    assert.equal(12000, r.unit)
  end)

  it("still never posts under the floor", function()
    local r = GC.Flips.RecommendPost(nil, 10000, 12000,
      { levels = ladder, sold = 4000, quarterUnit = 11000, floor = 11500 })
    assert.equal("floor", r.mode)
    assert.equal(11500, r.unit)
  end)

  it("lands the candidate on the silver grid", function()
    local off = { level(10000, 400), level(10550, 100) }
    local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = off, sold = 4000, quarterUnit = 11000 })
    assert.equal("overcut", r.mode)
    assert.equal(10500, r.unit)
  end)

  it("reports breakeven and belowCost the same way as every other mode", function()
    local r = GC.Flips.RecommendPost(12000, 10000, 12000, { levels = ladder, sold = 4000, quarterUnit = 11000 })
    assert.equal("overcut", r.mode)
    assert.equal(math.ceil(12000 / 0.95), r.breakeven)
    assert.is_true(r.belowCost)
  end)

  it("declines when levels at or below the ask exceed the budget across more than one entry", function()
    -- 9500 (600) + 10000 (600) = 1200 units sit at or below the 10000 ask, budget is 1000: the
    -- walk breaks trying to add the second level, but the full total still must be checked.
    local levels = { level(9500, 600), level(10000, 600), level(10500, 100) }
    local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = levels, sold = 4000, quarterUnit = 11000 })
    assert.not_equal("overcut", r.mode)
  end)

  it("declines when sold is NaN instead of failing the budget check open", function()
    local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = ladder, sold = 0 / 0, quarterUnit = 15000 })
    assert.not_equal("overcut", r.mode)
  end)

  it("skips an occupied rung that rounds down onto the ask and takes the grid step instead", function()
    local levels = { level(10000, 400), level(10050, 100) }
    local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = levels, sold = 4000, quarterUnit = 11000 })
    assert.equal("overcut", r.mode)
    assert.equal(10100, r.unit)
    -- The off-grid rung at 10050 rounds DOWN onto the ask on the grid, so it never surfaces as
    -- its own occupied rung -- but a post at the synthetic step (10100) still queues behind it.
    -- ahead has to count it: 400 at the ask plus 100 on the off-grid rung, both strictly below
    -- the step.
    assert.equal(500, r.ahead)
  end)

  it("forwards quarterUnit through RepostAdvice", function()
    local seen
    local real = GC.Flips.RecommendPost
    GC.Flips.RecommendPost = function(paid, market, mv, opts) seen = opts; return real(paid, market, mv, opts) end
    GC.Flips.RepostAdvice({ paidUnit = 100, marketUnit = 10000, mv = 12000,
      levels = ladder, sold = 4000, quarterUnit = 11000, qty = 10 })
    assert.equal(11000, seen.quarterUnit)
  end)
end)
