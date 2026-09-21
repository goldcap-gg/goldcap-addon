local helper = require("spec.spec_helper")

-- Sell pricing v2 (docs/superpowers/specs/2026-09-10-sell-reach-pricing-design.md). A post at
-- unit price X sells within the day when the item's own floor visits X within the day, so the
-- ceiling for climbing above the cheapest ask is reach24 -- what the floor actually reached in
-- the last 24 hours -- and not a rank in today's book. The units that have to fit the turnover
-- budget are the ones queued STRICTLY below the chosen rung: inside one price level the newest
-- lot sells first, so the rung's own stock is behind a fresh post, not in front of it.
describe("RecommendPost, the climb (v2)", function()
  local GC
  before_each(function() GC = helper.loadModule("Core/Flips.lua", {}) end)

  local function level(unitPrice, quantity) return { unitPrice = unitPrice, quantity = quantity } end

  -- The two books the owner actually saw on 2026-09-10, the ones that made v1 wrong.
  --
  -- Stinky Bright Potion: a 93g floor 507 units deep, then 94g and 95g, a real 100g rung, and
  -- a tail of near-empty rungs running to 300g. p25 over LISTINGS lands at 209g in a book
  -- shaped like this, and v1 recommended exactly that -- a 170% premium over the floor, at a
  -- price nobody buys.
  local stinky = {
    level(930000, 507), level(940000, 233), level(950000, 40), level(1000000, 34),
    level(1250000, 12), level(1500000, 1), level(2000000, 1), level(2500000, 1), level(3000000, 1),
  }
  local STINKY_SOLD = 11046 -- budget = 11046 * 6 / 24 = 2761.5 units

  -- Amphibious Scrap: a dense book in silver steps just over a 5g99s floor. v1 posted at 7g50s.
  local amphibious = {
    level(59900, 300), level(60000, 250), level(60800, 120), level(60900, 90),
    level(61000, 200), level(63500, 150), level(65000, 400), level(75000, 800),
  }
  local AMPHIBIOUS_SOLD = 4000 -- budget = 1000 units

  -- 1g cheapest, rungs every half silver, then a wall.
  local ladder = {
    level(10000, 400), level(10500, 300), level(11000, 300), level(12000, 2000), level(15000, 5000),
  }

  describe("the worked examples", function()
    it("posts Stinky at the 100g rung the floor reaches, not the 209g quarter line", function()
      local r = GC.Flips.RecommendPost(nil, 930000, 1000000,
        { levels = stinky, sold = STINKY_SOLD, reachUnit = 1020000 })
      assert.equal("overcut", r.mode)
      assert.equal(1000000, r.unit)
      assert.equal(780, r.ahead) -- 507 + 233 + 40, strictly below 100g
      assert.equal("reach", r.capBy)
      assert.equal(1020000, r.cap)
    end)

    it("reaches the same 100g on the quarter fallback, because the fallback is capped at +10%", function()
      -- cap = min(209g, 93g * 1.10 = 102g30s) -> 102g30s, and the highest occupied rung under
      -- it is the same 100g. The uncapped quarter line would have said 209g.
      local r = GC.Flips.RecommendPost(nil, 930000, 1000000,
        { levels = stinky, sold = STINKY_SOLD, quarterUnit = 2090000 })
      assert.equal("overcut", r.mode)
      assert.equal(1000000, r.unit)
      assert.equal("quarter", r.capBy)
      assert.equal(1023000, r.cap)
    end)

    it("posts Amphibious inside the day's reach instead of 7g50s", function()
      -- cap 6g40s; 6g35s is the highest occupied rung under it, and the 960 units strictly
      -- below it fit the 1000-unit budget.
      local r = GC.Flips.RecommendPost(nil, 59900, 62000,
        { levels = amphibious, sold = AMPHIBIOUS_SOLD, reachUnit = 64000 })
      assert.equal("overcut", r.mode)
      assert.equal(63500, r.unit)
      assert.equal(960, r.ahead)
    end)

    it("does not count the chosen rung's own units against the budget", function()
      -- The 150 units sitting AT 6g35s would push the queue to 1110 and disqualify the rung,
      -- dropping the post to 6g10s. They are behind a fresh post, not ahead of it.
      local r = GC.Flips.RecommendPost(nil, 59900, 62000,
        { levels = amphibious, sold = AMPHIBIOUS_SOLD, reachUnit = 64000 })
      assert.equal(63500, r.unit)
      assert.not_equal(61000, r.unit)
    end)
  end)

  describe("the ceiling", function()
    it("prefers reach over the quarter line when both are present", function()
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = ladder, sold = 4000, reachUnit = 10500, quarterUnit = 15000 })
      assert.equal("reach", r.capBy)
      assert.equal(10500, r.cap)
      assert.equal(10500, r.unit)
    end)

    it("caps the quarter fallback at 10% over the cheapest ask", function()
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = ladder, sold = 4000, quarterUnit = 15000 })
      assert.equal("quarter", r.capBy)
      assert.equal(11000, r.cap) -- 10000 * 1.10, on the grid
      assert.equal(11000, r.unit)
    end)

    it("matches when the cap sits at or below the cheapest ask", function()
      local at = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = ladder, sold = 4000, reachUnit = 10000 })
      assert.equal("match", at.mode)
      assert.equal(10000, at.unit)
      -- The line that was in force still comes back, so the caller can say why.
      assert.equal("reach", at.capBy)

      local under = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = ladder, sold = 4000, reachUnit = 9000 })
      assert.equal("match", under.mode)
    end)

    it("reports no cap at all when neither line reaches it", function()
      local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = ladder, sold = 4000 })
      assert.equal("match", r.mode)
      assert.is_nil(r.cap)
      assert.is_nil(r.capBy)
      assert.is_nil(r.ahead)
    end)
  end)

  describe("the budget", function()
    it("stops under a wall even when the ceiling sits above it", function()
      -- cap 12000, but the 12000 rung has 1000 units strictly below it and the budget is 1000
      -- -- so it fits; the 15000 rung above the cap is what is out of reach. The highest rung
      -- inside the cap is 12000 itself.
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = ladder, sold = 4000, reachUnit = 12000 })
      assert.equal("overcut", r.mode)
      assert.equal(12000, r.unit)
      assert.equal(1000, r.ahead)
    end)

    it("matches in front of a fresh wall (the 90k-shards case)", function()
      -- 22k a day, 90k sitting at the cheapest ask: nothing above it is reachable, and a post
      -- at the ask sells ahead of the whole wall rather than a silver behind it.
      local shards = { level(50000, 90000), level(52000, 100) }
      local r = GC.Flips.RecommendPost(nil, 50000, 55000,
        { levels = shards, sold = 22000, reachUnit = 55000 })
      assert.equal("match", r.mode)
      assert.equal(50000, r.unit)
      assert.is_nil(r.ahead)
    end)

    it("counts everything below the rung, not just the level immediately under it", function()
      -- 9500 (600) + 10000 (600) = 1200 units under the 10500 rung, budget 1000.
      local levels = { level(9500, 600), level(10000, 600), level(10500, 100) }
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = levels, sold = 4000, reachUnit = 11000 })
      assert.equal("match", r.mode)
    end)

    it("declines without a sold figure", function()
      local r = GC.Flips.RecommendPost(nil, 10000, 12000, { levels = ladder, reachUnit = 12000 })
      assert.equal("match", r.mode)
      assert.is_nil(r.ahead)
    end)

    it("declines when sold is NaN instead of failing the budget check open", function()
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = ladder, sold = 0 / 0, reachUnit = 15000 })
      assert.equal("match", r.mode)
    end)
  end)

  -- Seen in game 2026-09-21, Tranquility Bloom: 1g88s:338, 1g89s:1.0k, 1g90s:8.6k, a wall of
  -- 46k at 1g91s and another of 52k at 1g92s, selling 387k a day with the floor reaching 2g03s.
  -- The budget alone (six hours = 97k units) let the climb step OVER the 46k wall onto 1g92s:
  -- 56k units in front of the post, for one silver more than the head of that wall. The spec's
  -- own words for that trade are "behind the entire rung for one silver of gain". The whole
  -- budget is what the whole climb to the cap is worth; a share of the climb earns that share
  -- of the budget, and no more.
  describe("the queue a step is worth", function()
    local bloom = {
      level(18800, 338), level(18900, 1000), level(19000, 8600), level(19100, 46000),
      level(19200, 52000), level(19300, 1900), level(19400, 1700), level(19500, 1000),
      level(20400, 5000),
    }
    local opts = { levels = bloom, sold = 386749, reachUnit = 20300 }

    it("joins the head of a wall instead of stepping over it for a silver", function()
      local unit, ahead = GC.Flips.OvercutCandidate(18800, opts)
      assert.equal(19100, unit)
      assert.equal(338 + 1000 + 8600, ahead)
    end)

    it("still steps over the same wall when the step is worth the wait", function()
      -- The same 56k in front, but the next occupied rung is most of the way to the cap: most
      -- of the climb for most of the budget is the trade the budget was set for.
      local far = { level(18800, 338), level(18900, 1000), level(19000, 8600), level(19100, 46000),
        level(20000, 52000), level(20400, 5000) }
      local unit = GC.Flips.OvercutCandidate(18800, { levels = far, sold = 386749, reachUnit = 20300 })
      assert.equal(20000, unit)
    end)

    it("leaves a climb whose queue is small for its gain exactly where it was", function()
      -- Stinky: 814 units under the 100g rung against a 2,761-unit budget, for 7g of a 7g climb.
      local unit = GC.Flips.OvercutCandidate(930000, { levels = stinky, sold = STINKY_SOLD, reachUnit = 1000000 })
      assert.equal(1000000, unit)
    end)
  end)

  describe("the synthetic rung at the cap", function()
    it("posts at the cap when no rung is occupied under it, with a stocked level above it", function()
      local thin = { level(10000, 400), level(13000, 100) }
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = thin, sold = 4000, reachUnit = 11000 })
      assert.equal("overcut", r.mode)
      assert.equal(11000, r.unit)
      assert.equal(400, r.ahead)
    end)

    it("refuses the cap when the book simply ends under it", function()
      -- Nothing above the cap is visible, so nothing proves what sits between the last rung
      -- and the cap. The book is cut at 100 levels; its end is not the market's end.
      local ends = { level(10000, 400) }
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = ends, sold = 4000, reachUnit = 11000 })
      assert.equal("match", r.mode)
      assert.equal(10000, r.unit)
    end)

    it("never invents a rung one silver above the cheapest ask", function()
      -- v1's fallback. A post at 10100 sits behind all 400 units of the 10000 rung; a post AT
      -- 10000 sits in front of them, for one silver less.
      local thin = { level(10000, 400), level(30000, 100) }
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = thin, sold = 4000, reachUnit = 10050 })
      assert.equal("match", r.mode)
      assert.equal(10000, r.unit)
    end)
  end)

  describe("the silver grid", function()
    it("lands an off-grid rung on the grid, and counts the queue below the price it posts at", function()
      -- 10550 rounds down to 10500, the same grid price the 10500 rung already holds, so the
      -- 300 units there queue alongside the new post rather than below it.
      local levels = { level(10000, 400), level(10500, 300), level(10550, 100) }
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = levels, sold = 4000, reachUnit = 11000 })
      assert.equal("overcut", r.mode)
      assert.equal(10500, r.unit)
      assert.equal(400, r.ahead)
    end)

    it("does not call it a climb when the only rung above the ask rounds down onto it", function()
      local levels = { level(10000, 400), level(10050, 100) }
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = levels, sold = 4000, reachUnit = 11000 })
      assert.equal("match", r.mode)
      assert.equal(10000, r.unit)
    end)

    it("puts every candidate on the grid, cap included", function()
      local thin = { level(10000, 400), level(13000, 100) }
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = thin, sold = 4000, reachUnit = 11049 })
      assert.equal(11000, r.unit)
      assert.equal(0, r.unit % GC.Flips.SILVER)
    end)
  end)

  describe("the rules that run after the climb", function()
    -- F5, queue-at-exit. A flip's approved exit above what the floor reaches within a day is a
    -- hold, not a post, so reach caps that ceiling too.
    local slow = { level(10000, 2000), level(11000, 100), level(12000, 100), level(15000, 50) }

    it("caps a flip's queue-at-exit ceiling by reach", function()
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = slow, sold = 4000, reachUnit = 12000, targetUnit = 15000, absorbHours = 24 })
      assert.equal("queue", r.mode)
      assert.equal(12000, r.unit)
    end)

    it("queues at the stored exit itself when no reach figure caps it", function()
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = slow, sold = 4000, targetUnit = 15000, absorbHours = 24 })
      assert.equal("queue", r.mode)
      assert.equal(15000, r.unit)
    end)

    it("lets the queue-at-exit raise climb above the chosen rung", function()
      -- The climb spends six hours of turnover and stops at 11000; the flip's own exit is
      -- allowed a full day of it, and 12000 is inside both that budget and the reach cap.
      local thinner = {
        level(10000, 400), level(10500, 300), level(11000, 300), level(12000, 300), level(15000, 5000),
      }
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = thinner, sold = 2800, reachUnit = 12000, targetUnit = 12000, absorbHours = 24 })
      assert.equal("queue", r.mode)
      assert.equal(12000, r.unit)
    end)

    it("still never posts under the floor", function()
      local r = GC.Flips.RecommendPost(nil, 10000, 12000,
        { levels = ladder, sold = 4000, reachUnit = 11000, floor = 11500 })
      assert.equal("floor", r.mode)
      assert.equal(11500, r.unit)
    end)

    it("reports breakeven and belowCost the same way as every other mode", function()
      local r = GC.Flips.RecommendPost(12000, 10000, 12000,
        { levels = ladder, sold = 4000, reachUnit = 11000 })
      assert.equal("overcut", r.mode)
      assert.equal(math.ceil(12000 / 0.95), r.breakeven)
      assert.is_true(r.belowCost)
    end)
  end)

  it("forwards both ceilings through RepostAdvice", function()
    local seen
    local real = GC.Flips.RecommendPost
    GC.Flips.RecommendPost = function(paid, market, mv, opts) seen = opts; return real(paid, market, mv, opts) end
    GC.Flips.RepostAdvice({ paidUnit = 100, marketUnit = 10000, mv = 12000,
      levels = ladder, sold = 4000, reachUnit = 11000, quarterUnit = 15000, qty = 10 })
    assert.equal(11000, seen.reachUnit)
    assert.equal(15000, seen.quarterUnit)
  end)
end)
