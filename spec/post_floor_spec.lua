local helper = require("spec.spec_helper")

-- Written from two real losses. Sanguithorn sold at 7g against a market value of
-- 20g, and five Arcane Crystals bought at 70g went on sale at 18g42s against a
-- market of 92g12s. Both times a single cheap lot was the entire basis for the
-- price, because the Sell tab's only notion of "market" was the cheapest
-- competing ask and Post listed at exactly that.
describe("PostFloor", function()
  local GC
  before_each(function() GC = helper.loadModule("Core/Flips.lua", {}) end)

  local function level(unitPrice, quantity, ownerQty)
    return { unitPrice = unitPrice, quantity = quantity, ownerQty = ownerQty }
  end

  it("refuses to follow one cheap lot down", function()
    -- Sanguithorn: one lot at 7g, worth 20g, and the realm moves 500 a day.
    local floor, below = GC.Flips.PostFloor({
      marketUnit = 70000, mv = 200000, sold = 500,
      levels = { level(70000, 3), level(195000, 400) },
    })
    assert.equal(150000, floor) -- 75% of 20g
    assert.equal(3, below)
  end)

  it("believes the book when a whole day's supply sits under the floor", function()
    -- Not a thin undercut: the price really has moved, and holding out at a
    -- stale market value would just leave the stock unsold.
    local floor = GC.Flips.PostFloor({
      marketUnit = 70000, mv = 200000, sold = 100,
      levels = { level(70000, 400) },
    })
    assert.is_nil(floor)
  end)

  it("stays out of the way when the book agrees with the value", function()
    assert.is_nil(GC.Flips.PostFloor({ marketUnit = 195000, mv = 200000, sold = 500,
      levels = { level(195000, 50) } }))
  end)

  it("does not count the player's own units as evidence the market moved", function()
    -- Otherwise a big cheap listing of your own proves itself right, and the
    -- price walks down against nobody -- the same trap CheapestCompetingUnit
    -- exists to avoid.
    local floor = GC.Flips.PostFloor({
      marketUnit = 70000, mv = 200000, sold = 100,
      levels = { level(70000, 400, 400) },
    })
    assert.equal(150000, floor)
  end)

  it("needs a market value to have an opinion at all", function()
    assert.is_nil(GC.Flips.PostFloor({ marketUnit = 70000, sold = 500, levels = {} }))
    assert.is_nil(GC.Flips.PostFloor({ marketUnit = 70000, mv = 0, levels = {} }))
  end)

  describe("RecommendPost", function()
    it("never recommends below the floor", function()
      local rec = GC.Flips.RecommendPost(nil, 70000, nil, { floor = 150000 })
      assert.equal(150000, rec.unit)
      assert.equal("floor", rec.mode)
    end)

    it("leaves an honest book alone", function()
      local rec = GC.Flips.RecommendPost(nil, 195000, nil, { floor = 150000 })
      assert.equal(194999, rec.unit)
      assert.equal("undercut", rec.mode)
    end)
  end)
end)

describe("Underpriced listings", function()
  local GC
  local context = { char = "Owner-Dentarg", region = "eu" }

  before_each(function()
    GC = {}
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    GC.Acquisitions.Init({})
  end)

  -- The Arcane Crystal row, exactly: ten bought at 70g, five listed at 18g42s40c,
  -- market value 92g12s. The addon had no name for this and said nothing.
  it("names a listing that sits far below what the item is worth", function()
    GC.Acquisitions.Record({ source = "goldcap", itemID = 12363, positionKey = "commodity:12363",
      itemName = "Arcane Crystal", quantity = 10, total = 7000000, acquiredAt = 1,
      evidenceKey = "buy:1", character = context.char, region = context.region })
    local position = GC.SellPositions.Build({
      acquisitions = GC.Acquisitions.GetActive(context),
      ownedLots = { { positionKey = "commodity:12363", itemID = 12363, quantity = 5,
        unitPrice = 184240, auctionID = 1, firstSeenAt = 1 } },
      quotes = { [12363] = { unit = 921200, at = 10,
        levels = { { unitPrice = 184240, quantity = 5, ownerQty = 5 },
                   { unitPrice = 921200, quantity = 60 } } } },
      statsByItemID = { [12363] = { mv = 921200, sold = 40 } },
      context = context, now = 10, quoteMaxAge = 45,
    })[1]

    assert.is_true(position.facts.underpriced)
    assert.equal(184240, position.underpricedUnit)
    -- And the advice is to get out of it at a real price, not to go lower still.
    assert.is_not_nil(position.recommendation)
  end)

  it("says nothing when the listing is where it should be", function()
    local position = GC.SellPositions.Build({
      ownedLots = { { positionKey = "commodity:12363", itemID = 12363, quantity = 5,
        unitPrice = 900000, auctionID = 1, firstSeenAt = 1 } },
      quotes = { [12363] = { unit = 921200, at = 10,
        levels = { { unitPrice = 921200, quantity = 60 } } } },
      statsByItemID = { [12363] = { mv = 921200, sold = 40 } },
      context = context, now = 10, quoteMaxAge = 45,
    })[1]
    assert.is_falsy(position.facts.underpriced)
  end)

  it("posts at the floor rather than at the cheap lot", function()
    local position = GC.SellPositions.Build({
      bagStock = { { positionKey = "commodity:12363", itemID = 12363, quantity = 10,
        isCommodity = true } },
      quotes = { [12363] = { unit = 70000, at = 10,
        levels = { { unitPrice = 70000, quantity = 3 }, { unitPrice = 195000, quantity = 400 } } } },
      statsByItemID = { [12363] = { mv = 200000, sold = 500 } },
      context = context, now = 10, quoteMaxAge = 45,
    })[1]
    assert.equal(150000, position.postFloor)
    local plan = GC.SellPositions.BuildPostPlan(position,
      { itemID = 12363, exactQty = 10, positionKey = "commodity:12363" },
      { unit = 70000, fresh = true })
    -- What Post lists at, not just what the row says. These were two different
    -- numbers: the plan took the raw cheapest ask no matter what was displayed.
    assert.equal(150000, plan.unitPrice)
  end)
  -- Sanguithorn's exact shape: you are the ONLY seller, so the live book cannot
  -- tell you anything -- CheapestCompetingUnit falls back to your own price and
  -- agrees with itself. Only the imported market value knows.
  it("catches an underpriced listing even when nobody else is selling", function()
    local position = GC.SellPositions.Build({
      ownedLots = { { positionKey = "commodity:1", itemID = 1, quantity = 3,
        unitPrice = 70000, auctionID = 1, firstSeenAt = 1 } },
      quotes = { [1] = { unit = 70000, at = 10,
        levels = { { unitPrice = 70000, quantity = 3, ownerQty = 3 } } } },
      statsByItemID = { [1] = { mv = 200000, sold = 500 } },
      context = context, now = 10, quoteMaxAge = 45,
    })[1]
    assert.is_true(position.facts.underpriced)
    assert.equal(70000, position.underpricedUnit)
  end)
end)
