local helper = require("spec.spec_helper")

-- The seller's default price (Settings, POSTING; owner, 2026-10-25): MATCH, UNDERCUT or MARKET in
-- place of GoldCap's own price as what every item opens at, composed into the one place SELL
-- decides a price (Core/SellPositions.lua), so the row, the dock, the queue and the post plan hold
-- one number. A group's floor still holds and a price under what was paid is still said. Prices
-- are copper on the silver grid (100).
describe("SELL's default price", function()
  local GC
  local context = { char = "A-R", region = "eu" }
  local BOOK = { { unitPrice = 12000, quantity = 50 }, { unitPrice = 13000, quantity = 20 } }

  local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
  end

  -- One commodity of item 10, five in the bags, its book `levels`, quoted fresh at 12000.
  local function position(opts)
    opts = opts or {}
    local key = "commodity:10"
    return GC.SellPositions.Build({
      acquisitions = opts.acquisitions or {}, ownedLots = {},
      bagStock = { { positionKey = key, itemID = 10, itemName = "Herb", quantity = 5, isCommodity = true } },
      quotes = { [10] = { unit = 12000, at = 9, levels = opts.levels == nil and BOOK or opts.levels or nil } },
      statsByItemID = opts.stats or {},
      context = context, now = 10,
      chosenUnits = opts.chosen and { [key] = opts.chosen } or nil,
      defaultPrice = opts.default,
      rules = opts.rule and { ruleFor = function() return copy(opts.rule) end,
        roundsFor = function() return opts.rounds or 0 end } or nil,
    })[1]
  end

  local function plan(p)
    return GC.SellPositions.BuildPostPlan(p, { itemID = 10, exactQty = p.bagQty, positionKey = p.positionKey },
      { unit = p.freshMarketUnit, fresh = true })
  end

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("Core/PostQueue.lua", GC)
    GC.db = { settings = { sniper = {} } }
  end)

  it("opens at the cheapest ask, a step under it or the market value, keeping GoldCap's own beside it", function()
    local own = position({ stats = { [10] = { mv = 15000 } } }).postRecommendation.unit
    local match = position({ default = "match", stats = { [10] = { mv = 15000 } } }).postRecommendation
    assert.equal(12000, match.unit)
    assert.equal("default", match.mode)
    assert.equal("match", match.defaultId)
    assert.equal(own, match.goldcapUnit)
    assert.equal(11900, position({ default = "under" }).postRecommendation.unit)
    assert.equal(15000, position({ default = "market", stats = { [10] = { mv = 15000 } } }).postRecommendation.unit)
  end)

  it("keeps GoldCap's own price with none, with GOLDCAP or COST, and with nothing to fill from", function()
    local own = position().postRecommendation
    for _, default in ipairs({ "goldcap", "cost", "anything" }) do
      local rec = position({ default = default }).postRecommendation
      assert.equal(own.unit, rec.unit, default)
      assert.is_nil(rec.defaultId, default)
    end
    -- No ask but the player's own: nothing to match. No market value: nothing for MARKET.
    local mine = position({ default = "match", levels = { { unitPrice = 12000, quantity = 5, ownerQty = 5 } } })
    assert.is_not.equal("default", mine.postRecommendation.mode)
    assert.is_not.equal("default", position({ default = "market" }).postRecommendation.mode)
  end)

  it("never opens under a followed group's floor", function()
    local rule = { name = "Herbs", play = "gather", durationIndex = 2, floorPct = 80, floorUnit = 12500, usualUnit = 15625 }
    local p = position({ default = "under", rule = rule })
    assert.equal(12500, p.postRecommendation.unit)
    assert.equal(12500, plan(p).unitPrice)
  end)

  it("gives way to a typed price, and a step down starts from it", function()
    local typed = position({ default = "match", chosen = 15000 }).postRecommendation
    assert.equal(15000, typed.unit)
    assert.equal("chosen", typed.mode)
    assert.equal("match", typed.defaultId) -- the way back is the default's chip
    local FLIP = { name = "Transmog", play = "flip", durationIndex = 3, stepPct = 5, floorPct = 70,
      floorUnit = 7000, usualUnit = 10000 }
    assert.equal(11900, position({ default = "under", rule = FLIP }).postRecommendation.unit)
    local stepped = position({ default = "under", rule = FLIP, rounds = 2 }).postRecommendation
    assert.equal(9000, stepped.unit)
    assert.equal("rule", stepped.mode)
  end)

  it("says a default under what the stock cost, and the queue holds it back", function()
    local p = position({ default = "match",
      acquisitions = { { id = "a", source = "goldcap", itemID = 10, positionKey = "commodity:10",
        remainingQty = 5, remainingTotal = 5 * 12500, acquiredAt = 1, character = context.char, region = context.region } } })
    assert.equal(12000, p.postRecommendation.unit)
    assert.is_true(p.postRecommendation.belowCost)
    local entries, skipped = GC.PostQueue.Build({ p })
    assert.same({}, entries)
    assert.equal("below_breakeven", skipped[1].reason)
  end)

  -- The number on screen is the number sent: the plan lists at the default as it stands, and the
  -- queue values each Post at it.
  it("posts and queues at the default it opened at", function()
    local under = position({ default = "under" })
    assert.equal(11900, plan(under).unitPrice)
    assert.equal(11900, GC.PostQueue.Build({ under })[1].unitPrice)
    local market = position({ default = "market", stats = { [10] = { mv = 15000 } } })
    assert.equal(15000, plan(market).unitPrice)
    assert.equal(15000, GC.PostQueue.Build({ market })[1].unitPrice)
  end)
end)
