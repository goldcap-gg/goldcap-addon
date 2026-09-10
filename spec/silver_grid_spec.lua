local helper = require("spec.spec_helper")

-- Part 0 of the posting-queue design (2026-08-17): warcraft.wiki.gg, verbatim, on
-- PostCommodity's unitPrice and PostItem's bid/buyout -- "Amount in copper, only accepts gold
-- and silver and silently fails for non-zero copper counts." GC.Flips.RecommendPost's old
-- undercut mode returned `marketUnit - 1`; against a whole-silver competitor -- the only kind
-- that can exist, since a non-whole-silver post could never have gone through in the first
-- place -- that is always exactly one copper short of a silver, so every undercut post failed
-- with no error the player could see. That mode is gone (v2, 2026-09-10) and the property is
-- not: the climb and its two ceilings are new sources of arbitrary copper, and every one of
-- them still has to come out on the grid. This file is the property the fix exists to satisfy: every price
-- either RecommendPost or SellPositions.BuildPostPlan can hand back must land on the 100-copper
-- grid, plus the specific shapes called out in the design doc.
describe("The silver grid (Part 0)", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua")
    GC = helper.loadModule("Core/Flips.lua", GC)
    GC = helper.loadModule("Core/QuoteCache.lua", GC)
    GC = helper.loadModule("Core/SellPositions.lua", GC)
  end)

  describe("GC.Flips.SilverDown / SilverUp", function()
    it("SILVER is one silver, in copper", function()
      assert.equal(100, GC.Flips.SILVER)
    end)

    it("rounds down to the grid", function()
      assert.equal(400, GC.Flips.SilverDown(499))
      assert.equal(400, GC.Flips.SilverDown(400))
    end)

    it("rounds up to the grid", function()
      assert.equal(500, GC.Flips.SilverUp(401))
      assert.equal(400, GC.Flips.SilverUp(400))
    end)

    it("clamps a sub-silver amount UP to 100 in both directions -- there is no lower rung", function()
      -- A price under one silver cannot be posted at all, so 100 is the floor of the whole
      -- grid, not a rounding preference that could ever land below it.
      assert.equal(100, GC.Flips.SilverDown(1))
      assert.equal(100, GC.Flips.SilverDown(99))
      assert.equal(100, GC.Flips.SilverDown(0))
      assert.equal(100, GC.Flips.SilverUp(1))
      assert.equal(100, GC.Flips.SilverUp(99))
      assert.equal(100, GC.Flips.SilverUp(0))
    end)

    it("fails closed on nil rather than guessing a price", function()
      assert.is_nil(GC.Flips.SilverDown(nil))
      assert.is_nil(GC.Flips.SilverUp(nil))
    end)

    it("fails closed on a non-number", function()
      assert.is_nil(GC.Flips.SilverDown("500"))
      assert.is_nil(GC.Flips.SilverUp({}))
    end)

    it("fails closed on NaN and on both infinities", function()
      local nan = 0 / 0
      assert.is_nil(GC.Flips.SilverDown(nan))
      assert.is_nil(GC.Flips.SilverUp(nan))
      assert.is_nil(GC.Flips.SilverDown(math.huge))
      assert.is_nil(GC.Flips.SilverUp(-math.huge))
    end)

    it("fails closed on a negative value instead of clamping it up to a plausible-looking 100", function()
      -- A negative copper amount is not a cheap price, it is a bug somewhere upstream. Silently
      -- turning it into a postable 100-copper price would hide that bug behind a real auction;
      -- nil forces the caller to decline the recommendation instead (every caller in Flips.lua
      -- already treats a nil candidate as "nothing to recommend").
      assert.is_nil(GC.Flips.SilverDown(-1))
      assert.is_nil(GC.Flips.SilverUp(-1))
    end)
  end)

  -- v2 (2026-09-10) retired the undercut mode and UNDERCUT_MAX_SHARE with it: a fresh post at
  -- the cheapest rung already sells ahead of everything on that rung, so the one-silver step
  -- below it bought nothing and the share rule had nothing left to decide. What survives is the
  -- property the share rule existed to protect -- a match price is the competitor's own price,
  -- and it is whole silver at every scale.
  describe("match, at the competitor's own whole-silver price", function()
    it("at 10g a unit", function()
      local r = GC.Flips.RecommendPost(nil, 100000, nil)
      assert.equal("match", r.mode)
      assert.equal(100000, r.unit)
      assert.equal(0, r.unit % 100)
    end)

    it("at 30s a unit", function()
      local r = GC.Flips.RecommendPost(nil, 3000, nil)
      assert.equal("match", r.mode)
      assert.equal(3000, r.unit)
    end)

    -- The grid has no rung below one silver. Whatever else changes, the price handed back at
    -- the very bottom of the grid must never be 0 or a sub-silver number the AH would refuse.
    it("at exactly one silver, never 0 and never sub-silver", function()
      local r = GC.Flips.RecommendPost(nil, 100, nil)
      assert.equal("match", r.mode)
      assert.equal(100, r.unit)
      assert.equal(0, r.unit % 100)
    end)
  end)

  describe("floor override", function()
    it("runs LAST, rounds UP, and never leaves the price under a non-whole-silver floor", function()
      local r = GC.Flips.RecommendPost(nil, 100, nil, { floor = 14999 })
      assert.equal("floor", r.mode)
      assert.equal(15000, r.unit)
      assert.is_true(r.unit >= 14999)
      assert.equal(0, r.unit % 100)
    end)
  end)

  describe("no-quote (mv) fallback", function()
    it("normalizes an arbitrary imported market value to the grid", function()
      local r = GC.Flips.RecommendPost(nil, nil, 123456)
      assert.equal(123400, r.unit)
    end)
  end)

  describe("SellPositions.BuildPostPlan", function()
    local function position(overrides)
      local p = { itemID = 42, positionKey = "commodity:42", listedQty = 0, batches = {} }
      for k, v in pairs(overrides or {}) do p[k] = v end
      return p
    end

    it("normalizes a non-whole-silver live quote", function()
      local plan = GC.SellPositions.BuildPostPlan(position(),
        { itemID = 42, exactQty = 5 }, { unit = 184719, fresh = true })
      assert.equal(184800, plan.unitPrice)
    end)

    it("normalizes AFTER raising to postFloor, with SilverUp, even when the floor itself isn't whole silver", function()
      local plan = GC.SellPositions.BuildPostPlan(position({ postFloor = 14999 }),
        { itemID = 42, exactQty = 5 }, { unit = 100, fresh = true })
      assert.equal(15000, plan.unitPrice)
      assert.is_true(plan.unitPrice >= 14999)
    end)

    it("leaves an already-whole-silver price untouched", function()
      local plan = GC.SellPositions.BuildPostPlan(position(),
        { itemID = 42, exactQty = 5 }, { unit = 70000, fresh = true })
      assert.equal(70000, plan.unitPrice)
    end)
  end)

  -- The test that matters most: not a case list, a property. Over a wide spread of market
  -- values, market units, floors, book shapes and sold figures, every price reachable through
  -- RecommendPost or BuildPostPlan is a positive integer multiple of 100.
  describe("property: every reachable price lands on the grid", function()
    -- A small deterministic PRNG (Lehmer/Park-Miller, fixed seed) instead of math.random: this
    -- repo runs under both PUC Lua and LuaJIT (see AGENTS.md), and a hand-rolled generator is
    -- reproducible across both and from run to run, so a failure can be reasoned about by seed
    -- and iteration number instead of chased.
    local function makeRng(seed)
      local state = seed % 2147483647
      if state <= 0 then state = state + 2147483646 end
      return function()
        state = (state * 48271) % 2147483647
        return state
      end
    end

    local function intIn(rng, lo, hi)
      return lo + (rng() % (hi - lo + 1))
    end

    local function coinFlip(rng)
      return intIn(rng, 0, 1) == 1
    end

    -- A live AH ask is always whole silver -- it could not have posted otherwise -- so a
    -- realistic marketUnit is generated pre-aligned to the grid, up to 500g. mv/floor are
    -- deliberately NOT constrained: mv is an imported average and a floor is
    -- floor(mv * UNDERPRICE_FLOOR), neither lives on the grid before this fix normalizes them.
    local function randomMarketUnit(rng)
      return intIn(rng, 1, 50000) * GC.Flips.SILVER
    end

    local function randomAmount(rng)
      return intIn(rng, 1, 5000000)
    end

    local function randomLevels(rng, cheapest)
      local levels = {}
      for i = 1, intIn(rng, 0, 4) do
        levels[#levels + 1] = { unitPrice = cheapest + (i - 1) * GC.Flips.SILVER,
          quantity = intIn(rng, 0, 500) }
      end
      return levels
    end

    local ITERATIONS = 2000
    local rng = makeRng(20260817)

    it("RecommendPost", function()
      for i = 1, ITERATIONS do
        local marketUnit = coinFlip(rng) and randomMarketUnit(rng) or nil
        local mv = coinFlip(rng) and randomAmount(rng) or nil
        local paidUnit = coinFlip(rng) and randomAmount(rng) or nil
        local floor = coinFlip(rng) and randomAmount(rng) or nil
        local levels = randomLevels(rng, marketUnit or randomMarketUnit(rng))
        local sold = coinFlip(rng) and intIn(rng, 0, 2000) or nil
        -- v2: the two ceilings are part of the reachable price space now, and neither is
        -- generated on the grid -- reach24 is a percentile of an hourly series and the quarter
        -- line is a percentile over listings, so both arrive as arbitrary copper.
        local reachUnit = coinFlip(rng) and randomAmount(rng) or nil
        local quarterUnit = coinFlip(rng) and randomAmount(rng) or nil

        local r = GC.Flips.RecommendPost(paidUnit, marketUnit, mv,
          { levels = levels, sold = sold, floor = floor,
            reachUnit = reachUnit, quarterUnit = quarterUnit })
        if r ~= nil then
          assert.is_true(r.unit > 0, "iteration " .. i .. ": unit must be positive")
          assert.equal(0, r.unit % GC.Flips.SILVER, "iteration " .. i .. ": unit must be whole silver")
        end
      end
    end)

    it("BuildPostPlan", function()
      for i = 1, ITERATIONS do
        local quoteUnit = randomAmount(rng) -- deliberately not pre-aligned to the grid
        local postFloor = coinFlip(rng) and randomAmount(rng) or nil
        local pos = { itemID = 42, positionKey = "commodity:42", listedQty = 0,
          batches = {}, postFloor = postFloor }
        local plan = GC.SellPositions.BuildPostPlan(pos,
          { itemID = 42, exactQty = intIn(rng, 1, 500) }, { unit = quoteUnit, fresh = true })
        if plan ~= nil then
          assert.is_true(plan.unitPrice > 0, "iteration " .. i .. ": unitPrice must be positive")
          assert.equal(0, plan.unitPrice % GC.Flips.SILVER,
            "iteration " .. i .. ": unitPrice must be whole silver")
          if postFloor then
            assert.is_true(plan.unitPrice >= postFloor,
              "iteration " .. i .. ": unitPrice must never fall under the floor")
          end
        end
      end
    end)
  end)
end)
