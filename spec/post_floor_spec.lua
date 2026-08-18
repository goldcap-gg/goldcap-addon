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

  -- The velocity escape above needs an imported `sold` figure that most items don't have
  -- (GC.Data.GetItemValue's `sold` is the import's optional `s` field -- absent for every realm
  -- item and any commodity the ingest has no throughput figure for). Without `sold`, these cases
  -- have no other way to tell "the price really moved" from "one troll lot" except how many
  -- independent sellers agree on the lower price.
  describe("without a velocity figure", function()
    it("holds the floor against one lot, no matter the quantity", function()
      -- The ladder/troll case this floor exists for in the first place: a single price point,
      -- however deep, is not a second opinion.
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000,
        levels = { level(70000, 5000) },
      })
      assert.equal(150000, floor)
    end)

    it("holds the floor against two levels", function()
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000,
        levels = { level(70000, 500), level(80000, 500) },
      })
      assert.equal(150000, floor)
    end)

    it("releases the floor once three distinct levels agree", function()
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000,
        levels = { level(70000, 10), level(80000, 10), level(90000, 10) },
      })
      assert.is_nil(floor)
    end)

    it("does not count the player's own levels toward the three, via ownerQty", function()
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000,
        levels = { level(70000, 10, 10), level(80000, 10, 10), level(90000, 10, 10) },
      })
      assert.equal(150000, floor)
    end)

    it("does not count the player's own levels toward the three, via unsplittable ownerItem", function()
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000,
        levels = {
          { unitPrice = 70000, quantity = 10, ownerItem = true },
          { unitPrice = 80000, quantity = 10, ownerItem = true },
          { unitPrice = 90000, quantity = 10, ownerItem = true },
        },
      })
      assert.equal(150000, floor)
    end)

    it("holds when only two of three levels below the floor have real competition", function()
      -- One of the three is entirely the player's own -- that leaves two independent sellers,
      -- one short of the three the rule requires.
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000,
        levels = { level(70000, 10, 10), level(80000, 10), level(90000, 10) },
      })
      assert.equal(150000, floor)
    end)

    it("releases the floor on three competing levels even when sold is present but unmet", function()
      -- sold is known but the queue hasn't cleared a day's worth yet -- the velocity escape
      -- alone would hold the floor here. The level-count escape is independent and still fires.
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000, sold = 1000,
        levels = { level(70000, 10), level(80000, 10), level(90000, 10) },
      })
      assert.is_nil(floor)
    end)
  end)

  -- The level-count escape above has no depth requirement on its own: three distinct prices
  -- below the floor release it even if they carry three units between them. That is cheap to
  -- exploit -- a seller posting one unit each at three prices under the floor makes GoldCap
  -- price the player's WHOLE stack against the cheapest of them, which is the exact underpricing
  -- loss this file exists to prevent, reached through a different door. `heldQty` (the player's
  -- own bag-plus-listed quantity, from SellPositions.decoratePosition) closes it: the level-count
  -- escape now also requires `below >= heldQty`, the same shape as the velocity escape one line
  -- up -- "a day's worth sits under the floor" and "more sits under the floor than I'm trying to
  -- sell" are both ways of saying the cheap stock won't simply clear ahead of mine. Three units
  -- under a 200-unit stack clear in minutes and my price is still the market; 200 units under my
  -- 200 mean the market really is down there.
  describe("with heldQty gating the level-count escape", function()
    it("holds the floor against the thin three-level attack once heldQty is known", function()
      -- The attack: one unit at each of three prices under the floor. Distinct-level count
      -- alone would release this; the depth requirement catches it.
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000, heldQty = 200,
        levels = { level(70000, 1), level(80000, 1), level(90000, 1) },
      })
      assert.equal(150000, floor)
    end)

    it("releases once the competing depth below the floor covers heldQty", function()
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000, heldQty = 200,
        levels = { level(70000, 200), level(80000, 150), level(90000, 150) },
      })
      assert.is_nil(floor)
    end)

    it("falls back to the level count alone when heldQty is absent", function()
      -- Every caller today (RecommendPost, RepostAdvice, and every other existing spec in this
      -- file) omits heldQty entirely -- PostFloor must not start refusing to answer, or go
      -- stickier than before, just because a caller hasn't been taught the new argument yet.
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000,
        levels = { level(70000, 10), level(80000, 10), level(90000, 10) },
      })
      assert.is_nil(floor)
    end)

    it("treats heldQty == 0 the same as absent", function()
      -- SellPositions always computes heldQty as a number (bagQty + listedQty, both default 0),
      -- so "nothing held" arrives as 0, not nil -- 0 must not be read as "require 0 units of
      -- depth" (which every level count would trivially satisfy) or the gate does nothing for
      -- exactly the positions it matters most for: ones with no bag/listed stock recorded yet.
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000, heldQty = 0,
        levels = { level(70000, 10), level(80000, 10), level(90000, 10) },
      })
      assert.is_nil(floor)
    end)

    it("does not let the player's own quantity count toward the depth comparison either", function()
      -- Same owner-subtraction the level count above already relies on: a huge owner-only level
      -- must not pad `below` past heldQty any more than it can pad the distinct-level count.
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000, heldQty = 200,
        levels = { level(60000, 1000, 1000), level(70000, 5), level(80000, 5), level(90000, 5) },
      })
      assert.equal(150000, floor)
    end)

    it("leaves the velocity escape untouched by heldQty", function()
      -- below >= sold releases on its own, regardless of heldQty -- even when heldQty is far
      -- bigger than below. The two escapes are independent; heldQty only ever gates the
      -- level-count one.
      local floor = GC.Flips.PostFloor({
        marketUnit = 70000, mv = 200000, sold = 100, heldQty = 100000,
        levels = { level(70000, 150) },
      })
      assert.is_nil(floor)
    end)
  end)

  describe("RecommendPost", function()
    it("never recommends below the floor", function()
      local rec = GC.Flips.RecommendPost(nil, 70000, nil, { floor = 150000 })
      assert.equal(150000, rec.unit)
      assert.equal("floor", rec.mode)
    end)

    it("leaves an honest book alone", function()
      -- Part 0 (silver-grid fix): the undercut candidate is now normalized to whole silver, so
      -- one silver below 195000 is 194900, not the raw 194999 (one copper below) this test
      -- asserted before -- 194999 could never actually have posted.
      local rec = GC.Flips.RecommendPost(nil, 195000, nil, { floor = 150000 })
      assert.equal(194900, rec.unit)
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
-- The Arcane Crystal report: five posted at 92g12s each, shown as listed at
-- 18g42s40c, with a profit of -52g49s72c on a position that was making money.
-- 921200 / 5 = 184240 -- the posted unit price divided by the stack size.
describe("Owned lot unit price", function()
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

  it("reads a commodity buyout as the per-unit price it is", function()
    local lots = GC.SellPositions.NormalizeOwnedLots({
      { itemKey = { itemID = 12363 }, itemID = 12363, isCommodity = true,
        quantity = 5, buyoutAmount = 921200, auctionID = 1 },
    }, 10)
    assert.equal(1, #lots)
    assert.equal(921200, lots[1].unitPrice)
  end)

  it("still splits an item auction's total across its stack", function()
    local lots = GC.SellPositions.NormalizeOwnedLots({
      { itemKey = { itemID = 999, itemLevel = 10 }, itemID = 999, isCommodity = false,
        quantity = 4, buyoutAmount = 4000, auctionID = 2 },
    }, 10)
    assert.equal(1000, lots[1].unitPrice)
  end)

  it("does not divide on a guess", function()
    -- GetOwnedAuctions does not report isCommodity, so unknown is a real state.
    -- Dividing there understates the price, which reads as selling far below
    -- market and would have the player cancel a perfectly good listing.
    local lots = GC.SellPositions.NormalizeOwnedLots({
      { itemKey = { itemID = 12363 }, itemID = 12363, isCommodity = true,
        quantity = 5, buyoutAmount = 921200, auctionID = 3 },
    }, 10)
    assert.equal(921200, lots[1].unitPrice)
  end)

  it("reports the real profit on the position that read as a 52g loss", function()
    GC.Acquisitions.Record({ source = "goldcap", itemID = 12363,
      positionKey = "commodity:12363", itemName = "Arcane Crystal", quantity = 10,
      total = 7000000, acquiredAt = 1, evidenceKey = "buy:1",
      character = context.char, region = context.region })
    local position = GC.SellPositions.Build({
      acquisitions = GC.Acquisitions.GetActive(context),
      ownedLots = GC.SellPositions.NormalizeOwnedLots({
        { itemKey = { itemID = 12363 }, itemID = 12363, isCommodity = true,
          quantity = 5, buyoutAmount = 921200, auctionID = 1 },
      }, 1),
      quotes = { [12363] = { unit = 921200, at = 10,
        levels = { { unitPrice = 921200, quantity = 60 } } } },
      statsByItemID = { [12363] = { mv = 921200, sold = 40 } },
      context = context, now = 10, quoteMaxAge = 45,
    })[1]

    assert.equal(921200, position.ownedLots[1].unitPrice)
    -- Five units at 92g12s, less the 5% cut, against 70g each paid.
    assert.equal(4375700, position.projectedNet)
    assert.equal(875700, position.profit)
    -- And no false alarm: this listing is exactly where it should be.
    assert.is_falsy(position.facts.underpriced)
  end)
end)
