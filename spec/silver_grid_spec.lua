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

  -- WoW: Forever's own auction house allows copper in a commodity price (the book carries 67c,
  -- 68c...) -- Auctionator 339's Source_ModernAH/Selling/ItemPrice.lua returns the price
  -- unrounded there (studied, not copied). Gated on the CLIENT's capability, not the game name:
  -- C_AuctionHouse.SupportsCopperValues, read fresh on every call the same way every other
  -- capability probe in this addon works (Core/ForeverCheck.lua's `has`). And on the lot's
  -- kind: only a commodity takes copper there (see the item block below).
  describe("WoW: Forever -- a commodity's 1-copper grid, gated on C_AuctionHouse.SupportsCopperValues", function()
    after_each(function() _G.C_AuctionHouse = nil end)

    -- The reported bug: a book whose cheapest ask is 67c (below any price the RETAIL grid can
    -- express) used to round UP to 1 silver -- posting 3.6k units behind the wall it was meant
    -- to undercut. docs "sell-price-diagnosis.md", Linen Cloth: cheapest ask 67c, 129 units;
    -- next rung 68c, 103 units; a wall of 936 at 80c.
    it("matches the raw cheapest ask instead of rounding it up to a silver", function()
      _G.C_AuctionHouse = { SupportsCopperValues = function() return true end }
      local r = GC.Flips.RecommendPost(nil, 67, nil, { isCommodity = true })
      assert.equal("match", r.mode)
      assert.equal(67, r.unit)
      assert.is_true(r.unit <= 67)
    end)

    it("still rounds a whole-silver ask the same as before -- the grid is finer, not different",
      function()
        _G.C_AuctionHouse = { SupportsCopperValues = function() return true end }
        local r = GC.Flips.RecommendPost(nil, 100000, nil, { isCommodity = true })
        assert.equal("match", r.mode)
        assert.equal(100000, r.unit)
      end)

    it("floors SilverDown/SilverUp at 1 copper, not 100, for a commodity when the client supports copper prices",
      function()
        _G.C_AuctionHouse = { SupportsCopperValues = function() return true end }
        assert.equal(1, GC.Flips.PriceStep(true))
        assert.equal(1, GC.Flips.SilverDown(1, true))
        assert.equal(1, GC.Flips.SilverDown(0, true))
        assert.equal(68, GC.Flips.SilverUp(68, true))
        assert.equal(67, GC.Flips.SilverDown(67, true))
      end)

    it("keeps a commodity's floor and its post plan in copper", function()
      _G.C_AuctionHouse = { SupportsCopperValues = function() return true end }
      local r = GC.Flips.RecommendPost(nil, 100, nil, { floor = 225, isCommodity = true })
      assert.equal("floor", r.mode)
      assert.equal(225, r.unit)
      local plan = GC.SellPositions.BuildPostPlan(
        { itemID = 2589, positionKey = "commodity:2589", listedQty = 0, batches = {}, postFloor = 225 },
        { itemID = 2589, exactQty = 5 }, { unit = 100, fresh = true })
      assert.equal(225, plan.unitPrice)
      -- And a step under a commodity's 1s ask is a copper.
      assert.equal(99, GC.SellPositions.FillUnit("under", 100, nil, true))
    end)

    it("fails closed on garbage input the same as the retail grid does", function()
      _G.C_AuctionHouse = { SupportsCopperValues = function() return true end }
      assert.is_nil(GC.Flips.SilverDown(-1, true))
      assert.is_nil(GC.Flips.SilverDown(nil, true))
    end)

    -- Retail must not change. Byte-identical: no C_AuctionHouse global at all (busted's normal
    -- environment, and any client without the API), and a client that HAS the function but
    -- answers false -- for either kind of lot.
    it("is byte-identical to today when the client has no such function", function()
      _G.C_AuctionHouse = nil
      for _, kind in ipairs({ true, false }) do
        local r = GC.Flips.RecommendPost(nil, 67, nil, { isCommodity = kind })
        assert.equal("match", r.mode)
        assert.equal(100, r.unit)
        assert.equal(100, GC.Flips.SilverDown(67, kind))
        assert.equal(100, GC.Flips.PriceStep(kind))
      end
      local r = GC.Flips.RecommendPost(nil, 67, nil)
      assert.equal(100, r.unit)
    end)

    it("is byte-identical to today when SupportsCopperValues answers false", function()
      _G.C_AuctionHouse = { SupportsCopperValues = function() return false end }
      local r = GC.Flips.RecommendPost(nil, 67, nil, { isCommodity = true })
      assert.equal(100, r.unit)
      assert.equal(100, GC.Flips.RecommendPost(nil, 67, nil, { isCommodity = false }).unit)
    end)

    it("is byte-identical to today when SupportsCopperValues errors", function()
      _G.C_AuctionHouse = { SupportsCopperValues = function() error("boom") end }
      assert.equal(100, GC.Flips.SilverDown(67, true))
    end)
  end)

  -- WoW: Forever, 2026-11-06 (owner, in game): SupportsCopperValues() is true there and
  -- Blizzard's own item sell frame shows a copper box, but a green belt posted at 1s 10c never
  -- went up -- not in the Auctions tab, its 1s deposit not taken. The scan's fold had 0 of 4,120
  -- gear price levels with copper, against 406 of 508 commodities. So an item (non-commodity)
  -- posts at whole silver there as on retail, and only a commodity takes copper. A lot of no
  -- known kind is priced as an item: a post that goes through beats one that silently fails.
  describe("WoW: Forever -- an item's grid is whole silver", function()
    before_each(function()
      _G.C_AuctionHouse = { SupportsCopperValues = function() return true end }
    end)
    after_each(function() _G.C_AuctionHouse = nil end)

    it("steps a whole silver for an item and for a lot of no known kind", function()
      assert.equal(100, GC.Flips.PriceStep(false))
      assert.equal(100, GC.Flips.PriceStep(nil))
      assert.equal(100, GC.Flips.PriceStep())
      assert.equal(100, GC.Flips.SilverDown(67))
      assert.equal(100, GC.Flips.SilverUp(1, false))
      assert.equal(200, GC.Flips.SilverDown(299, false))
      assert.equal(300, GC.Flips.SilverUp(201, false))
    end)

    -- The bottom rung: the cheapest ask is an item at 1s 0c. A copper under it (99c) is the post
    -- that silently fails, and there is no whole silver under 1s. So GoldCap's own price matches
    -- the ask at 1s, and UNDERCUT offers no price at all -- what retail does at its bottom rung.
    it("cannot undercut an item at 1s: GoldCap matches at 1s and UNDERCUT has no price", function()
      local r = GC.Flips.RecommendPost(nil, 100, nil, { isCommodity = false })
      assert.equal("match", r.mode)
      assert.equal(100, r.unit)
      assert.is_nil(GC.SellPositions.FillUnit("under", 100, nil, false))
      assert.equal(100, GC.SellPositions.FillUnit("match", 100, nil, false))
      -- Above the bottom rung an item's UNDERCUT is a silver under the ask, as on retail.
      assert.equal(200, GC.SellPositions.FillUnit("under", 300, nil, false))
    end)

    it("rounds an item's floor of 2s 25c up to 3s", function()
      local r = GC.Flips.RecommendPost(nil, 100, nil, { floor = 225, isCommodity = false })
      assert.equal("floor", r.mode)
      assert.equal(300, r.unit)
    end)

    it("rounds an item's match and its climb down onto whole silver", function()
      assert.equal(100, GC.Flips.RecommendPost(nil, 150, nil, { isCommodity = false }).unit)
      -- A climb under a reach line of 2s 50c over a 1s ask, with a rung at 2s 40c: an item's
      -- ceiling is 2s, rounded down, so it climbs to 2s; a commodity's is 2s 50c, and it takes
      -- the 2s 40c rung itself.
      local function climb(kind)
        return GC.Flips.RecommendPost(nil, 100, nil, { isCommodity = kind, sold = 1000, reachUnit = 250,
          levels = { { unitPrice = 100, quantity = 1 }, { unitPrice = 240, quantity = 1 },
            { unitPrice = 900, quantity = 5 } } })
      end
      local r = climb(false)
      assert.equal("overcut", r.mode)
      assert.equal(200, r.unit)
      assert.equal(200, r.cap)
      assert.equal(240, climb(true).unit)
    end)

    it("relists an item on whole silver in the repost advice", function()
      local advice = GC.Flips.RepostAdvice({ marketUnit = 150, floor = 225, isCommodity = false })
      assert.equal(300, advice.rec.unit)
      assert.equal(225, GC.Flips.RepostAdvice({ marketUnit = 150, floor = 225, isCommodity = true }).rec.unit)
    end)

    it("lists an item's post plan on whole silver: the floor, the quote, and a price the seller typed", function()
      local function item(over)
        local p = { itemID = 5, positionKey = "item:5:0:0:0", listedQty = 0, batches = {} }
        for k, v in pairs(over or {}) do p[k] = v end
        return p
      end
      local bag = { itemID = 5, exactQty = 1, positionKey = "item:5:0:0:0" }
      assert.equal(300, GC.SellPositions.BuildPostPlan(item({ postFloor = 225 }), bag,
        { unit = 100, fresh = true }).unitPrice)
      assert.equal(200, GC.SellPositions.BuildPostPlan(item(), bag, { unit = 110, fresh = true }).unitPrice)
      -- Typed 1s 10c, the price the green did not go up at: listed at 2s.
      assert.equal(200, GC.SellPositions.BuildPostPlan(item(), bag, { unit = 100, fresh = true },
        { overrideUnit = 110 }).unitPrice)
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
    -- repo runs under both PUC Lua and LuaJIT (see the addon's engineering notes), and a hand-rolled generator is
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

    -- WoW: Forever (2026-11-06): the client takes copper, and an item still posts at whole silver
    -- only (a green at 1s 10c never went up). The same property, on that client, for an item:
    -- off-grid asks, rungs, ceilings, floors and quotes all come out whole silver.
    describe("for an item on WoW: Forever, where the client takes copper", function()
      before_each(function()
        _G.C_AuctionHouse = { SupportsCopperValues = function() return true end }
      end)
      after_each(function() _G.C_AuctionHouse = nil end)

      it("RecommendPost", function()
        for i = 1, ITERATIONS do
          local marketUnit = coinFlip(rng) and randomAmount(rng) or nil
          local levels = randomLevels(rng, marketUnit or randomAmount(rng))
          for _, level in ipairs(levels) do level.unitPrice = level.unitPrice + intIn(rng, 0, 99) end
          local r = GC.Flips.RecommendPost(coinFlip(rng) and randomAmount(rng) or nil, marketUnit,
            coinFlip(rng) and randomAmount(rng) or nil,
            { levels = levels, sold = coinFlip(rng) and intIn(rng, 0, 2000) or nil,
              floor = coinFlip(rng) and randomAmount(rng) or nil,
              reachUnit = coinFlip(rng) and randomAmount(rng) or nil,
              quarterUnit = coinFlip(rng) and randomAmount(rng) or nil, isCommodity = false })
          if r ~= nil then
            assert.equal(0, r.unit % GC.Flips.SILVER, "iteration " .. i .. ": an item's unit must be whole silver")
          end
        end
      end)

      it("BuildPostPlan", function()
        for i = 1, ITERATIONS do
          local postFloor = coinFlip(rng) and randomAmount(rng) or nil
          local pos = { itemID = 5, positionKey = "item:5:0:0:0", listedQty = 0, batches = {},
            postFloor = postFloor }
          local plan = GC.SellPositions.BuildPostPlan(pos,
            { itemID = 5, exactQty = 1, positionKey = "item:5:0:0:0" },
            { unit = randomAmount(rng), fresh = true },
            { overrideUnit = coinFlip(rng) and randomAmount(rng) or nil })
          if plan ~= nil then
            assert.equal(0, plan.unitPrice % GC.Flips.SILVER,
              "iteration " .. i .. ": an item's unitPrice must be whole silver")
          end
        end
      end)
    end)
  end)
end)
