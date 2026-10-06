local helper = require("spec.spec_helper")

describe("Flips row model (Sniper v3 §5)", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Flips.lua")
  end)

  describe("SalesForItem", function()
    local entries = {
      { kind = "sale", itemName = "Ironclaw Ore", at = 100 },
      { kind = "sale", itemName = "Ironclaw Ore", at = 50 },
      { kind = "sale", itemName = "Different Item", at = 200 },
      { kind = "buy",  itemName = "Ironclaw Ore", at = 300 },
    }

    it("matches by itemName only", function()
      local sales = GC.Flips.SalesForItem(entries, "Ironclaw Ore", 0)
      assert.equal(2, #sales)
    end)

    it("I6: drops sales recorded before sinceAt (a flip's own boughtAt)", function()
      local sales = GC.Flips.SalesForItem(entries, "Ironclaw Ore", 80)
      assert.equal(1, #sales)
      assert.equal(100, sales[1].at)
    end)

    it("includes a sale recorded exactly at sinceAt", function()
      local sales = GC.Flips.SalesForItem(entries, "Ironclaw Ore", 100)
      assert.equal(1, #sales)
    end)

    it("ignores non-sale entries even with a matching name", function()
      local sales = GC.Flips.SalesForItem(entries, "Ironclaw Ore", 300)
      assert.equal(0, #sales)
    end)

    it("returns an empty list for a nil itemName", function()
      assert.same({}, GC.Flips.SalesForItem(entries, nil, 0))
    end)

    it("tolerates a nil entries argument", function()
      assert.same({}, GC.Flips.SalesForItem(nil, "Ironclaw Ore", 0))
    end)
  end)

  describe("DepthBelow (Sell-tab upgrade)", function()
    it("sums quantity strictly below ourUnit", function()
      local levels = {
        { unitPrice = 100, quantity = 3 },
        { unitPrice = 200, quantity = 5 },
        { unitPrice = 300, quantity = 7 },
      }
      assert.equal(8, GC.Flips.DepthBelow(levels, 300)) -- 3 + 5, the 300 level itself excluded
    end)

    it("boundary: a level priced EXACTLY at ourUnit is not counted", function()
      local levels = { { unitPrice = 500, quantity = 100 } }
      assert.equal(0, GC.Flips.DepthBelow(levels, 500))
    end)

    it("counts every level cheaper than ourUnit when ourUnit is above all of them", function()
      local levels = { { unitPrice = 100, quantity = 3 }, { unitPrice = 200, quantity = 5 } }
      assert.equal(8, GC.Flips.DepthBelow(levels, 999))
    end)

    it("returns 0 (not nil) when ourUnit undercuts every level", function()
      local levels = { { unitPrice = 100, quantity = 3 }, { unitPrice = 200, quantity = 5 } }
      assert.equal(0, GC.Flips.DepthBelow(levels, 1))
    end)

    it("treats a missing quantity on a level as 0", function()
      local levels = { { unitPrice = 100 } }
      assert.equal(0, GC.Flips.DepthBelow(levels, 200))
    end)

    it("returns nil for a nil levels argument", function()
      assert.is_nil(GC.Flips.DepthBelow(nil, 500))
    end)

    it("returns nil for an empty levels array", function()
      assert.is_nil(GC.Flips.DepthBelow({}, 500))
    end)

    it("returns nil for a nil ourUnit", function()
      local levels = { { unitPrice = 100, quantity = 3 } }
      assert.is_nil(GC.Flips.DepthBelow(levels, nil))
    end)
  end)

  describe("SellOutlook (Sell-tab upgrade)", function()
    it("returns nil when sold is nil -- never fabricates a number without import data", function()
      assert.is_nil(GC.Flips.SellOutlook({ ahead = 0, qty = 5 }))
    end)

    it("returns nil when sold is zero", function()
      assert.is_nil(GC.Flips.SellOutlook({ ahead = 0, qty = 5, sold = 0 }))
    end)

    it("returns nil when sold is negative", function()
      assert.is_nil(GC.Flips.SellOutlook({ ahead = 0, qty = 5, sold = -1 }))
    end)

    it("tolerates a nil args table entirely", function()
      assert.is_nil(GC.Flips.SellOutlook(nil))
    end)

    it("treats a nil ahead/qty as 0", function()
      local o = GC.Flips.SellOutlook({ sold = 2 })
      assert.equal(0, o.days)
      assert.equal("FAST", o.tier)
    end)

    it("days = (ahead + qty) / sold", function()
      local o = GC.Flips.SellOutlook({ ahead = 10, qty = 10, sold = 5 })
      assert.equal(4, o.days)
    end)

    it("tier boundary: just under 1 day is FAST", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 9, sold = 10 })
      assert.equal(0.9, o.days)
      assert.equal("FAST", o.tier)
    end)

    it("tier boundary: exactly 1 day is OK, not FAST", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10 })
      assert.equal(1, o.days)
      assert.equal("OK", o.tier)
    end)

    it("tier boundary: exactly 3 days is SLOW, not OK", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 30, sold = 10 })
      assert.equal(3, o.days)
      assert.equal("SLOW", o.tier)
    end)

    it("tier boundary: exactly 7 days is STALL, not SLOW", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 70, sold = 10 })
      assert.equal(7, o.days)
      assert.equal("STALL", o.tier)
    end)

    it("trend <= -10 multiplies days by 1.5 (falling market slows sales)", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10, trend = -10 })
      assert.equal(1.5, o.days)
    end)

    it("trend just above -10 does NOT trigger the falling-market slowdown", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10, trend = -9 })
      assert.equal(1, o.days)
    end)

    it("trend >= 10 multiplies days by 0.75 (rising market speeds sales)", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10, trend = 10 })
      assert.equal(0.75, o.days)
    end)

    it("trend just below 10 does NOT trigger the rising-market speedup", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10, trend = 9 })
      assert.equal(1, o.days)
    end)

    it("trend between -10 and 10 (exclusive) leaves days unmodified", function()
      local o = GC.Flips.SellOutlook({ ahead = 0, qty = 10, sold = 10, trend = 0 })
      assert.equal(1, o.days)
    end)
  end)

  describe("RecommendPost (design update)", function()
    -- v2 (2026-09-10): there is no undercut mode left. With no book to climb and no ceiling
    -- to climb toward, a live quote is MATCHED -- a fresh post at the cheapest rung sells
    -- ahead of everything already sitting on it, and a silver below it buys nothing the study
    -- could measure.
    it("matches a live market quote", function()
      local r = GC.Flips.RecommendPost(100, 50000, nil)
      assert.equal("match", r.mode)
      assert.equal(50000, r.unit)
    end)

    -- Part 0: a price under one silver cannot be posted at all, so the grid's floor is 100
    -- copper, not 1 -- this replaces the old "floors at 1 copper" behavior.
    it("floors the candidate at one silver (never zero/sub-silver)", function()
      local r = GC.Flips.RecommendPost(1, 1, nil)
      assert.equal(100, r.unit)
    end)

    it("falls back to mv when there is no live quote", function()
      local r = GC.Flips.RecommendPost(100, nil, 800)
      assert.equal(800, r.unit)
    end)

    -- Part 0: same grid normalization as the first test above.
    it("prefers a live quote over mv when both are present", function()
      local r = GC.Flips.RecommendPost(100, 50000, 800)
      assert.equal(50000, r.unit)
    end)

    it("returns nil when neither marketUnit nor mv is known", function()
      assert.is_nil(GC.Flips.RecommendPost(100, nil, nil))
    end)

    -- F5 queue-at-exit: a sniper-underwritten position posts at the exit its buy was approved
    -- against when the wall below it is hours of turnover, instead of matching the wall it was
    -- bought from (which locks in the 5% cut as a loss).
    describe("queue-at-exit", function()
      local ladder = {
        { unitPrice = 19800, quantity = 8000 },
        { unitPrice = 20000, quantity = 1500 },
        { unitPrice = 24000, quantity = 4000 },
        { unitPrice = 30000, quantity = 50000 },
      }

      it("queues at the target when everything below it fits the turnover budget", function()
        -- budget = 222000 * 2 / 24 = 18500 >= 13500 units below the 27300 target
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27300 })
        assert.equal("queue", r.mode)
        assert.equal(27300, r.unit)
        assert.is_false(r.belowCost)
      end)

      it("stops at the highest rung whose queue fits when the target does not", function()
        -- budget = 60000 * 2 / 24 = 5000: the 19800 wall (8000 units) already exceeds it once
        -- its own tail is joined... but the seller joining AT 19800 is the match case; the
        -- first rung ABOVE the wall needs 8000 queued -- over budget, so no climb at all.
        local tight = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 60000, targetUnit = 27300 })
        assert.not_equal("queue", tight.mode)
        -- budget = 150000 * 2 / 24 = 12500: rungs at 20000 (9500 queued) fit; 24000 (13500)
        -- does not, so the climb stops one rung below it.
        local mid = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 150000, targetUnit = 27300 })
        assert.equal("queue", mid.mode)
        assert.equal(20000, mid.unit)
      end)

      it("never jumps past the end of a truncated book to the target", function()
        -- Same ladder, but nothing visible above the 27300 target: the book may simply be
        -- cut off there (levels are capped), so the gap between the last rung and the target
        -- is unmeasured. The climb stops at the highest VISIBLE rung.
        local cut = {
          { unitPrice = 19800, quantity = 8000 },
          { unitPrice = 20000, quantity = 1500 },
          { unitPrice = 24000, quantity = 4000 },
        }
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = cut, sold = 222000, targetUnit = 27300 })
        assert.equal("queue", r.mode)
        assert.equal(24000, r.unit)
      end)

      it("deflates the target when the current trend says the market is mid-spike", function()
        -- Stored target 27300 with a +201% trend: pre-spike estimate 27300/3.01 = 9069 ->
        -- grid 9000, below the 19800 match candidate -- no queueing above the wall at all.
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27300, trendPct = 201 })
        assert.not_equal("queue", r.mode)
        -- At or below the threshold the target stands untouched.
        local calm = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27300, trendPct = 30 })
        assert.equal("queue", calm.mode)
        assert.equal(27300, calm.unit)
      end)

      it("reads the spike threshold from opts.spikePct instead of the baked-in constant", function()
        -- A raised threshold lets the same +201% trend keep the stored target...
        local calm = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27300, trendPct = 201, spikePct = 250 })
        assert.equal("queue", calm.mode)
        assert.equal(27300, calm.unit)
        -- ...and a lowered one deflates a +25% trend the default 30 would have left alone:
        -- ceiling = SilverDown(27300 / 1.25) = 21800, proven by the stocked 24000 ask above it.
        local strict = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27300, trendPct = 25, spikePct = 20 })
        assert.equal("queue", strict.mode)
        assert.equal(21800, strict.unit)
      end)

      it("does nothing without a target -- untracked stock keeps match/undercut", function()
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000 })
        assert.not_equal("queue", r.mode)
      end)

      it("is disabled by absorbHours = 0", function()
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27300, absorbHours = 0 })
        assert.not_equal("queue", r.mode)
      end)

      it("lands the queued price on the silver grid", function()
        local r = GC.Flips.RecommendPost(19800, 19800, 39100,
          { levels = ladder, sold = 222000, targetUnit = 27377 })
        assert.equal("queue", r.mode)
        assert.equal(27300, r.unit)
      end)
    end)

    it("computes breakeven as ceil(paidUnit / 0.95)", function()
      local r = GC.Flips.RecommendPost(100, 500, nil)
      assert.equal(106, r.breakeven) -- 100/0.95 = 105.26... -> ceil 106
    end)

    it("breakeven is nil when paidUnit is unknown (an orphan-shaped call)", function()
      local r = GC.Flips.RecommendPost(nil, 500, nil)
      assert.is_nil(r.breakeven)
      assert.is_false(r.belowCost)
    end)

    it("belowCost is true when the candidate sits below breakeven", function()
      -- Part 0: candidate is now the match price 100 (marketUnit=90 clamps up to the grid
      -- floor), not the old 89 -- still below breakeven=106 either way.
      local r = GC.Flips.RecommendPost(100, 90, nil) -- candidate=100 (grid floor), breakeven=106
      assert.is_true(r.belowCost)
    end)

    it("belowCost boundary: candidate exactly AT breakeven is NOT belowCost", function()
      -- paidUnit=95 -> breakeven=ceil(95/0.95)=100; drive candidate to exactly 100 via mv
      local r = GC.Flips.RecommendPost(95, nil, 100)
      assert.equal(100, r.breakeven)
      assert.equal(100, r.unit)
      assert.is_false(r.belowCost)
    end)

    it("belowCost is false when candidate sits above breakeven", function()
      local r = GC.Flips.RecommendPost(100, 1000, nil)
      assert.is_false(r.belowCost)
    end)

    -- v2 (2026-09-10): every one of these ends in match. The tier-velocity rule (F3) and the
    -- one-silver undercut it chose between are both gone -- newest-first collapsed them into
    -- the same answer -- so what these pin now is that the DEFAULT is match in every shape of
    -- missing input, and that only the climb (spec/overcut_spec.lua) can move off it.
    describe("mode selection: match is what is left when the climb declines", function()
      it("plain 3-arg call (no opts) matches, mode='match'", function()
        local r = GC.Flips.RecommendPost(50000, 100000, nil)
        assert.equal("match", r.mode)
        assert.equal(100000, r.unit)
      end)

      it("mode is nil in the no-quote (mv) fallback branch, even with opts present", function()
        local r = GC.Flips.RecommendPost(50, nil, 800, { levels = { { unitPrice = 1, quantity = 1 } }, sold = 1000 })
        assert.is_nil(r.mode)
        assert.equal(800, r.unit)
      end)

      it("matches with a book and a velocity but no ceiling to climb toward", function()
        local levels = {
          { unitPrice = 100, quantity = 5 }, { unitPrice = 100, quantity = 5 }, { unitPrice = 200, quantity = 50 },
        }
        local r = GC.Flips.RecommendPost(50, 100, nil, { levels = levels, sold = 20 })
        assert.equal("match", r.mode)
        assert.equal(100, r.unit)
      end)

      -- The old F3 boundary: a cheapest tier that turns over slowly used to mean undercut.
      -- It means match now, like everything else without a ceiling.
      it("matches even when the cheapest tier turns over slowly", function()
        local levels = { { unitPrice = 100000, quantity = 10 } }
        local r = GC.Flips.RecommendPost(50000, 100000, nil, { levels = levels, sold = 19 })
        assert.equal("match", r.mode)
        assert.equal(100000, r.unit)
      end)

      it("matches when opts.levels is missing", function()
        local r = GC.Flips.RecommendPost(50000, 100000, nil, { sold = 1000 })
        assert.equal("match", r.mode)
      end)

      it("matches when opts.levels is empty", function()
        local r = GC.Flips.RecommendPost(50000, 100000, nil, { levels = {}, sold = 1000 })
        assert.equal("match", r.mode)
      end)

      it("matches when opts.sold is missing", function()
        local levels = { { unitPrice = 100000, quantity = 1 } }
        local r = GC.Flips.RecommendPost(50000, 100000, nil, { levels = levels })
        assert.equal("match", r.mode)
      end)

      it("matches when opts.sold is zero", function()
        local levels = { { unitPrice = 100000, quantity = 1 } }
        local r = GC.Flips.RecommendPost(50000, 100000, nil, { levels = levels, sold = 0 })
        assert.equal("match", r.mode)
      end)

      it("belowCost/breakeven are still computed correctly in match mode", function()
        local levels = { { unitPrice = 100, quantity = 10 } }
        local r = GC.Flips.RecommendPost(100, 100, nil, { levels = levels, sold = 1000 })
        -- breakeven = ceil(100/0.95) = 106; candidate (match) = 100 < 106 -> belowCost
        assert.equal("match", r.mode)
        assert.equal(106, r.breakeven)
        assert.is_true(r.belowCost)
      end)
    end)
  end)

  describe("RepostAdvice (F4)", function()
    it("returns nil when RecommendPost itself has nothing to recommend", function()
      assert.is_nil(GC.Flips.RepostAdvice({ paidUnit = 100 }))
    end)

    it("tolerates a nil args table entirely", function()
      assert.is_nil(GC.Flips.RepostAdvice(nil))
    end)

    it("hold/loss when the recommended price would lock a loss", function()
      local r = GC.Flips.RepostAdvice({ paidUnit = 1000, marketUnit = 10, qty = 1 })
      assert.equal("hold", r.action)
      assert.equal("loss", r.reason)
      assert.is_not_nil(r.rec)
    end)

    it("hold/slow when the queue at the new (recommended) price is a STALL outlook", function()
      local r = GC.Flips.RepostAdvice({
        paidUnit = 10, marketUnit = 100, qty = 100, sold = 1,
        levels = { { unitPrice = 100, quantity = 1000 } },
      })
      -- rec.unit=100 (undercut, tierDepth 1000 vs sold 1 stays undercut; grid-clamped -- see
      -- Part 0 above); aheadAtNew = DepthBelow(levels, 100) = 0 (the 100-priced level is not
      -- < 100); days = (0+100)/1 = 100 -> STALL
      assert.equal("hold", r.action)
      assert.equal("slow", r.reason)
    end)

    it("repost when nothing blocks it", function()
      local r = GC.Flips.RepostAdvice({
        paidUnit = 10, marketUnit = 100, qty = 1, sold = 1,
        levels = { { unitPrice = 100, quantity = 1000 } },
      })
      -- days = (0+1)/1 = 1 -> tier OK, not STALL
      assert.equal("repost", r.action)
      assert.equal(100, r.rec.unit) -- grid-clamped, see Part 0 above
    end)

    it("does not block on missing levels/sold data (treats an unknowable queue as ok-to-repost)", function()
      local r = GC.Flips.RepostAdvice({ paidUnit = 10, marketUnit = 100, qty = 1 })
      assert.equal("repost", r.action)
    end)

    it("loss takes precedence over slow when both would apply", function()
      local r = GC.Flips.RepostAdvice({
        paidUnit = 1000, marketUnit = 10, qty = 100, sold = 1,
        levels = { { unitPrice = 10, quantity = 1000 } },
      })
      assert.equal("hold", r.action)
      assert.equal("loss", r.reason)
    end)
  end)
end)
