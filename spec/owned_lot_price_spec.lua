local helper = require("spec.spec_helper")

-- Five Arcane Crystals were posted at 92g12s each and reported as listed at
-- 18g42s40c, with a profit of -52g49s72c on a position that was making money.
-- 921200 / 5 = 184240: the posted unit price divided by the stack size.
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
      { itemKey = { itemID = 12363 }, itemID = 12363,
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
    -- Five at 92g12s, less the 5% cut, against 70g each paid: a profit, not a loss.
    assert.equal(4375700, position.projectedNet)
    assert.equal(875700, position.profit)
    -- And no false alarm from the underpriced check on a perfectly good listing.
    assert.is_falsy(position.facts.underpriced)
  end)
end)
