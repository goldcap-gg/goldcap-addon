local helper = require("spec.spec_helper")

-- Followed groups (plan 2026-10-22, task 10): a followed group's selling rule composed into the
-- one place SELL decides a price, a floor and a quantity (Core/SellPositions.lua), and into the
-- posting queue (Core/PostQueue.lua). The rule and the rounds arrive through injected functions,
-- so both modules stay pure: here they are plain stubs. Prices are copper on the silver grid (100).
describe("SELL by a followed group's rules", function()
  local GC
  local context = { char = "A-R", region = "eu" }

  local GATHER = { name = "Herbs", play = "gather", durationIndex = 2, floorPct = 80, floorUnit = 7000, usualUnit = 10000 }
  local FLIP = { name = "Transmog", play = "flip", durationIndex = 3, perItem = 1, stepPct = 5, floorPct = 70,
    floorUnit = 7000, usualUnit = 10000 }

  local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
  end

  -- One commodity position of item 10 in the bags, quoted fresh at `ask`.
  local function position(opts)
    opts = opts or {}
    local rule = opts.rule
    local calls = {}
    local args = {
      acquisitions = {}, ownedLots = {},
      bagStock = { { positionKey = opts.positionKey or "commodity:10", itemID = 10, itemName = "Herb",
        quantity = opts.qty or 5, isCommodity = (opts.isCommodity == nil) and (opts.quoteKey == nil) or opts.isCommodity,
        quoteKey = opts.quoteKey } },
      quotes = { [opts.quoteKey or 10] = { unit = opts.ask or 12000, at = 9, levels = opts.levels } },
      statsByItemID = opts.stats or {},
      context = context, now = 10,
      chosenUnits = opts.chosen and { [opts.positionKey or "commodity:10"] = opts.chosen } or nil,
    }
    if rule ~= false then
      args.rules = {
        ruleFor = function(itemID, itemLevel)
          calls[#calls + 1] = { itemID, itemLevel }
          if type(rule) == "function" then return rule(itemID, itemLevel) end
          return rule and copy(rule) or nil
        end,
        roundsFor = function() return opts.rounds or 0 end,
      }
    end
    return GC.SellPositions.Build(args)[1], calls
  end

  local function plan(p, opts)
    return GC.SellPositions.BuildPostPlan(p, { itemID = 10, exactQty = p.bagQty, positionKey = p.positionKey },
      { unit = p.freshMarketUnit, fresh = true }, opts)
  end

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("Core/PostQueue.lua", GC)
    GC.db = { settings = { sniper = {} } }
  end)

  it("the rule floor raises the floor and never lowers it", function()
    local p = position({ rule = GATHER, ask = 12000 })
    assert.equal(7000, p.postFloor)
    assert.equal("Herbs", p.rule.name)
    assert.equal(2, p.ruleDurationIndex)
    assert.is_nil(p.rulePostQty)
    -- mv 12000: the market's own floor is 9000 against a 6000 ask, over the rule's 7000.
    p = position({ rule = GATHER, ask = 6000, stats = { [10] = { mv = 12000 } } })
    assert.equal(9000, p.postFloor)
    -- Without a rule, the floor is the market's alone, as before.
    assert.equal(9000, position({ rule = false, ask = 6000, stats = { [10] = { mv = 12000 } } }).postFloor)
    assert.is_nil(position({ rule = false, ask = 12000 }).postFloor)
    assert.is_nil(position({ rule = false }).rule)
  end)

  it("a lower-level variant is floored by PostFloor alone", function()
    local p, calls = position({ positionKey = "item:10:600:0:0", quoteKey = "item:10:600:0:0",
      rule = function(_, level)
        if level < 610 then return { name = "Transmog", play = "flip", durationIndex = 3, perItem = 1 } end
        return copy(FLIP)
      end })
    assert.same({ { 10, 600 } }, calls)
    assert.is_nil(p.postFloor) -- a variant has no market figure, so no PostFloor either
    assert.equal(1, p.rulePostQty)
    local _, bare = position({ rule = GATHER })
    assert.same({ { 10, 0 } }, bare)
  end)

  -- A piece of gear with no bonus IDs has no variant key (quoteKey), but its position key still
  -- states its level, item:<id>:<level>:<suffix>:<pet> (Acquisitions.PositionKey): a transmog flip
  -- posted with none left in the bags, or a bag stack keyed the way it always was, is read at that
  -- level, so the group's floor holds, not dropped as a level-0 variant would be.
  it("reads a gear position's level from its key when it has no variant key", function()
    local function gearRule(_, level)
      if level < 610 then return { name = "Transmog", play = "flip", durationIndex = 3, perItem = 1 } end
      return copy(FLIP)
    end
    local calls = {}
    local listed = GC.SellPositions.Build({
      acquisitions = {}, bagStock = {},
      ownedLots = { { positionKey = "item:10:610:0:0", itemID = 10, quantity = 1, unitPrice = 15000,
        auctionID = 5, firstSeenAt = 1, isCommodity = false } },
      quotes = { [10] = { unit = 12000, at = 9 } },
      statsByItemID = {}, context = context, now = 10,
      rules = { ruleFor = function(itemID, level) calls[#calls + 1] = { itemID, level }; return gearRule(itemID, level) end,
        roundsFor = function() return 0 end },
    })[1]
    assert.is_nil(listed.quoteKey)
    assert.same({ { 10, 610 } }, calls)
    assert.equal(7000, listed.postFloor)
    assert.equal(5, listed.rule.stepPct)
    -- In the bags under the same key: the same rule.
    local bagged, bagCalls = position({ positionKey = "item:10:610:0:0", isCommodity = false, rule = gearRule })
    assert.same({ { 10, 610 } }, bagCalls)
    assert.equal(7000, bagged.postFloor)
    -- A commodity has no level to read.
    local _, commodity = position({ rule = gearRule })
    assert.same({ { 10, 0 } }, commodity)
  end)

  describe("step-down", function()
    it("takes stepPct of usual off for each round, down to the floor", function()
      local p = position({ rule = FLIP, ask = 12000, rounds = 2 })
      assert.equal(9000, p.postRecommendation.unit)
      assert.equal("rule", p.postRecommendation.mode)
      assert.equal(2, p.postRecommendation.ruleRounds)
      assert.equal(2, p.sellRounds)
      assert.equal(9500, position({ rule = FLIP, ask = 12000, rounds = 1 }).postRecommendation.unit)
      assert.equal(7000, position({ rule = FLIP, ask = 12000, rounds = 8 }).postRecommendation.unit)
      assert.equal(7000, position({ rule = FLIP, ask = 12000, rounds = 40 }).postRecommendation.unit)
    end)

    -- Owner, 2026-10-23: a market above the usual price is the market's to take until a round
    -- comes back unsold; the recommendation guards against a lone dear listing on its own.
    it("posts at the market's price before the first unsold round, above the usual price too", function()
      local p = position({ rule = FLIP, ask = 12000, rounds = 0 })
      local free = position({ rule = false, ask = 12000 })
      assert.equal(free.postRecommendation.unit, p.postRecommendation.unit)
      assert.is_true(p.postRecommendation.unit > FLIP.usualUnit)
      assert.is_not.equal("rule", p.postRecommendation.mode)
    end)

    it("never raises a price the market already put under it", function()
      local p = position({ rule = FLIP, ask = 8000, rounds = 2 })
      assert.equal(8000, p.postRecommendation.unit)
      assert.is_not.equal("rule", p.postRecommendation.mode)
    end)

    it("needs a usual price and a floor", function()
      local p = position({ rule = { name = "Transmog", play = "flip", durationIndex = 3, perItem = 1 },
        ask = 12000, rounds = 2 })
      assert.equal(12000, p.postRecommendation.unit)
      assert.is_not.equal("rule", p.postRecommendation.mode)
    end)

    it("a typed price still wins", function()
      local p = position({ rule = FLIP, ask = 12000, rounds = 2, chosen = 15000 })
      assert.equal(15000, p.postRecommendation.unit)
      assert.equal("chosen", p.postRecommendation.mode)
    end)

    it("says a stepped price is under what the stock cost", function()
      local p = GC.SellPositions.Build({
        acquisitions = { { id = "a", source = "goldcap", itemID = 10, positionKey = "commodity:10",
          remainingQty = 5, remainingTotal = 5 * 9500, acquiredAt = 1, character = context.char, region = context.region } },
        ownedLots = {},
        bagStock = { { positionKey = "commodity:10", itemID = 10, itemName = "Herb", quantity = 5, isCommodity = true } },
        quotes = { [10] = { unit = 12000, at = 9 } }, statsByItemID = {}, context = context, now = 10,
        rules = { ruleFor = function() return copy(FLIP) end, roundsFor = function() return 2 end },
      })[1]
      assert.equal(9000, p.postRecommendation.unit)
      assert.is_true(p.postRecommendation.belowCost)
    end)
  end)

  it("the post plan lists at the rule price under the cheapest ask", function()
    local p = position({ rule = FLIP, ask = 12000, rounds = 2 })
    assert.equal(9000, plan(p).unitPrice)
    local typed = plan(p, { overrideUnit = 5000 })
    assert.equal(5000, typed.unitPrice)
    assert.is_true(typed.belowFloor)
  end)

  it("one at a time", function()
    local p = position({ rule = FLIP, ask = 12000, qty = 5 })
    assert.equal(1, p.rulePostQty)
    assert.equal(1, plan(p).quantity)
    assert.equal(3, plan(p, { overrideQuantity = 3 }).quantity)
    -- "all you have" lists the bag.
    assert.equal(5, plan(position({ rule = GATHER, ask = 12000, qty = 5 })).quantity)
  end)

  it("a floor above the market holds POST", function()
    local p = position({ rule = GATHER, ask = 6000 })
    local entries, skipped = GC.PostQueue.Build({ p })
    assert.equal(0, #entries)
    assert.equal("below_rule_floor", skipped[1].reason)
    -- The row's own Post, with no typed price, lists at the floor, never under it.
    assert.is_true(plan(p).unitPrice >= 7000)

    local typed = position({ rule = GATHER, ask = 6000, chosen = 6500 })
    assert.equal("chosen", typed.postRecommendation.mode)
    entries = GC.PostQueue.Build({ typed })
    assert.equal(1, #entries)
    assert.equal(6500, entries[1].unitPrice)
  end)

  it("POST takes one at a time", function()
    local entries = GC.PostQueue.Build({ position({ rule = FLIP, ask = 12000, qty = 5 }) })
    assert.equal(1, entries[1].postableQty)
    -- A quantity the player typed still wins.
    local p = position({ rule = FLIP, ask = 12000, qty = 5 })
    entries = GC.PostQueue.Build({ p }, { quantities = { [p.positionKey] = 3 } })
    assert.equal(3, entries[1].postableQty)
    assert.equal(5, GC.PostQueue.Build({ position({ rule = GATHER, ask = 12000, qty = 5 }) })[1].postableQty)
  end)

  it("flip and gather sell by default", function()
    local function selling(rule, marks)
      local p = position({ rule = rule })
      return GC.PostQueue.Selling(p, marks or {})
    end
    assert.is_true(selling(FLIP))
    assert.is_true(selling(GATHER))
    assert.is_false(selling({ name = "Potions", play = "craft", durationIndex = 2 }))
    assert.is_false(selling({ name = "Food", play = "stock", durationIndex = 2 }))
    assert.is_false(selling(FLIP, { ["commodity:10"] = false }))
    assert.is_false(selling(false))
  end)
end)
