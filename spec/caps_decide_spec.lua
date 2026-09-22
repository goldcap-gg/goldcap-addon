local helper = require("spec.spec_helper")

-- Live price caps, addon task 5: judging a drilled lot/book against the player's own price
-- cap, not the market. GC.Caps.DecideRealm picks the cheapest COMPARABLE lot (itemLevel >=
-- cap.l) at or under cap.c; GC.Caps.DecideCommodity buys the book's units at or under cap.c,
-- cheapest first, within the player's own per-buy limits. Both say what the chosen units cost
-- (`entryTotal`), and both are pure: same inputs untouched, in, decision out.
describe("Caps.DecideRealm", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Caps.lua")
  end)

  it("picks the cheapest lot per unit among comparable ones", function()
    local cap = { c = 100, l = 0 }
    local lots = {
      { auctionID = 1, buyout = 900, itemLevel = 10, quantity = 10 }, -- 90/unit
      { auctionID = 2, buyout = 400, itemLevel = 10, quantity = 5 },  -- 80/unit, cheapest
      { auctionID = 3, buyout = 100, itemLevel = 10, quantity = 1 },  -- 100/unit
    }
    local decision = GC.Caps.DecideRealm(cap, lots)
    assert.same({
      status = "WATCH", cap = true,
      candidate = { auctionID = 2, buyout = 400, quantity = 5, itemLevel = 10 },
      unit = 80,
      quantity = 5, entryTotal = 400, entryUnitDisplay = 80, capUnit = 100,
    }, decision)
  end)

  -- Caps fixes 2b: the buy dialog and the check panel read `entryTotal`/`entryUnitDisplay` off
  -- a decision to show UNIT and TOTAL, exactly as they do for GC.SniperDecision.EvaluateRealm's
  -- own result. Without them a realm cap showed "—" for both and "Can't price this" over a lot
  -- whose price is known to the copper -- and the button then paid that buyout with no sum on
  -- screen. For an item auction the lot's buyout IS what PlaceBid pays.
  it("says what the chosen lot costs: its whole buyout, per unit, and the player's own price", function()
    local cap = { c = 1000, l = 0 }
    local lots = { { auctionID = 7, buyout = 2700, itemLevel = 0, quantity = 3 } } -- 900/unit
    local decision = GC.Caps.DecideRealm(cap, lots)
    assert.equal(3, decision.quantity)
    assert.equal(2700, decision.entryTotal)
    assert.equal(900, decision.entryUnitDisplay)
    assert.equal(1000, decision.capUnit)
  end)

  it("skips a lot below the cap's item level floor", function()
    local cap = { c = 100, l = 20 }
    local lots = {
      { auctionID = 1, buyout = 50, itemLevel = 10, quantity = 1 },  -- cheaper, but below l
      { auctionID = 2, buyout = 90, itemLevel = 25, quantity = 1 },
    }
    local decision = GC.Caps.DecideRealm(cap, lots)
    assert.same(2, decision.candidate.auctionID)
    assert.same(90, decision.unit)
  end)

  it("skips a lot priced above the cap", function()
    local cap = { c = 100, l = 0 }
    local lots = {
      { auctionID = 1, buyout = 500, itemLevel = 10, quantity = 1 }, -- 500/unit, over cap
      { auctionID = 2, buyout = 90, itemLevel = 10, quantity = 1 },
    }
    local decision = GC.Caps.DecideRealm(cap, lots)
    assert.same(2, decision.candidate.auctionID)
  end)

  it("returns nil when no lot qualifies", function()
    local cap = { c = 100, l = 20 }
    local lots = {
      { auctionID = 1, buyout = 500, itemLevel = 10, quantity = 1 }, -- over cap AND below l
      { auctionID = 2, buyout = 90, itemLevel = 5, quantity = 1 },   -- below l
    }
    assert.is_nil(GC.Caps.DecideRealm(cap, lots))
  end)

  it("returns nil for an empty lot list", function()
    assert.is_nil(GC.Caps.DecideRealm({ c = 100, l = 0 }, {}))
  end)

  it("treats a missing quantity as 1", function()
    local cap = { c = 100, l = 0 }
    local lots = { { auctionID = 1, buyout = 80, itemLevel = 10 } } -- no quantity field
    local decision = GC.Caps.DecideRealm(cap, lots)
    assert.same(1, decision.candidate.quantity)
    assert.same(80, decision.unit)
  end)

  it("never mutates the lots it is handed", function()
    local cap = { c = 100, l = 0 }
    local lots = { { auctionID = 1, buyout = 80, itemLevel = 10, quantity = 2 } }
    local before = { auctionID = 1, buyout = 80, itemLevel = 10, quantity = 2 }
    GC.Caps.DecideRealm(cap, lots)
    assert.same(before, lots[1])
  end)
end)

describe("Caps.DecideCommodity", function()
  local GC
  -- Limits that bind nothing, for the tests about which units qualify at all.
  local ROOMY = { maxQuantity = 5000, budget = 1000000000000 }

  before_each(function()
    GC = helper.loadModule("Core/Caps.lua")
  end)

  it("buys only the levels at or under the cap, and says what those units cost", function()
    local cap = { c = 100 }
    local levels = {
      { unitPrice = 80, quantity = 3 },
      { unitPrice = 90, quantity = 2 },
      { unitPrice = 120, quantity = 10 }, -- over cap, excluded
    }
    local decision = GC.Caps.DecideCommodity(cap, levels, ROOMY)
    assert.same({
      status = "SAFE", buyable = true, cap = true,
      quantity = 5,
      entryTotal = 80 * 3 + 90 * 2,
      entryUnitDisplay = math.floor((80 * 3 + 90 * 2) / 5),
      unit = 80,
      capUnit = 100,
    }, decision)
  end)

  -- Caps fixes 2b: the requote guard holds the server's quote against `entryTotal`, and a cap
  -- decision used to carry none -- so it fell back to cheapest level x quantity. A cap spanning
  -- two levels (10 x 100g + 10 x 190g under 200g) was then "planned" at 2000g, quoted at its
  -- real 2900g, and rang RAID_WARNING as a 1.45x price rise on a quote wholly under the cap.
  it("totals every level it buys, not the cheapest level times the quantity", function()
    local levels = {
      { unitPrice = 1000000, quantity = 10 },
      { unitPrice = 1900000, quantity = 10 },
    }
    local decision = GC.Caps.DecideCommodity({ c = 2000000 }, levels, ROOMY)
    assert.equal(20, decision.quantity)
    assert.equal(29000000, decision.entryTotal)
  end)

  -- Caps fixes 2d: "at or under your price" is the whole promise, on the site and here. A 5g
  -- saving floor refused every cheap commodity and every floor sitting exactly at the cap,
  -- while the realm side had no floor at all.
  it("fires on a one-copper saving -- there is no profit floor on the player's own price", function()
    local decision = GC.Caps.DecideCommodity({ c = 100 }, { { unitPrice = 99, quantity = 1 } }, ROOMY)
    assert.is_table(decision)
    assert.equal(1, decision.quantity)
  end)

  it("fires with the floor exactly at the cap", function()
    local decision = GC.Caps.DecideCommodity({ c = 100 }, { { unitPrice = 100, quantity = 4 } }, ROOMY)
    assert.is_table(decision)
    assert.equal(4, decision.quantity)
    assert.equal(400, decision.entryTotal)
  end)

  -- Caps fixes 2c: a cap used to sum EVERY level under it into one purchase -- the whole book.
  -- The player's own "Max units per buy" and wallet limit bind a cap buy exactly as they bind
  -- any other; nothing market-derived does (a cap may have no market data at all).
  it("never buys more than the player's Max units per buy, cheapest first", function()
    local levels = {
      { unitPrice = 80, quantity = 3 },
      { unitPrice = 90, quantity = 2 },
    }
    local decision = GC.Caps.DecideCommodity({ c = 100 }, levels, { maxQuantity = 4, budget = 1000000 })
    assert.equal(4, decision.quantity)
    assert.equal(80 * 3 + 90, decision.entryTotal)
  end)

  it("stops where the player's wallet limit runs out, and buys part of a level up to it", function()
    local levels = {
      { unitPrice = 80, quantity = 3 },
      { unitPrice = 90, quantity = 5 },
    }
    -- 330 buys the three at 80 (240) and one at 90 (330), not a copper more.
    local decision = GC.Caps.DecideCommodity({ c = 100 }, levels, { maxQuantity = 200, budget = 330 })
    assert.equal(4, decision.quantity)
    assert.equal(330, decision.entryTotal)
  end)

  it("returns nil when not one unit fits the player's wallet limit", function()
    local levels = { { unitPrice = 80, quantity = 3 } }
    assert.is_nil(GC.Caps.DecideCommodity({ c = 100 }, levels, { maxQuantity = 200, budget = 79 }))
  end)

  it("fails closed without the player's limits", function()
    assert.is_nil(GC.Caps.DecideCommodity({ c = 100 }, { { unitPrice = 80, quantity = 3 } }, nil))
  end)

  -- Caps fixes 2e/2f: a quantity the player chose on the dialog, and the one a server quote was
  -- armed on, are judged by the cap rule too -- exactly that many units, at or under the cap,
  -- inside the same two limits -- or not at all.
  it("decides exactly a chosen quantity, cheapest first", function()
    local levels = {
      { unitPrice = 80, quantity = 3 },
      { unitPrice = 90, quantity = 2 },
    }
    local decision = GC.Caps.DecideCommodity({ c = 100 }, levels, ROOMY, 4)
    assert.equal(4, decision.quantity)
    assert.equal(80 * 3 + 90, decision.entryTotal)
    assert.equal(80, decision.unit)
  end)

  it("refuses a chosen quantity the book cannot fill at or under the cap", function()
    local levels = {
      { unitPrice = 80, quantity = 3 },
      { unitPrice = 120, quantity = 50 }, -- plenty of units, all of them over the cap
    }
    assert.is_nil(GC.Caps.DecideCommodity({ c = 100 }, levels, ROOMY, 4))
  end)

  it("refuses a chosen quantity past the player's Max units per buy", function()
    local levels = { { unitPrice = 80, quantity = 30 } }
    assert.is_nil(GC.Caps.DecideCommodity({ c = 100 }, levels, { maxQuantity = 20, budget = 1000000 }, 21))
  end)

  it("refuses a chosen quantity past the player's wallet limit", function()
    local levels = { { unitPrice = 80, quantity = 30 } }
    assert.is_nil(GC.Caps.DecideCommodity({ c = 100 }, levels, { maxQuantity = 200, budget = 799 }, 10))
  end)

  it("returns nil for an empty book", function()
    assert.is_nil(GC.Caps.DecideCommodity({ c = 100 }, {}, ROOMY))
  end)

  it("returns nil when every level is over the cap", function()
    local cap = { c = 100 }
    local levels = { { unitPrice = 150, quantity = 5 } }
    assert.is_nil(GC.Caps.DecideCommodity(cap, levels, ROOMY))
  end)

  it("never mutates the levels it is handed", function()
    local cap = { c = 100 }
    local levels = { { unitPrice = 90, quantity = 3 }, { unitPrice = 80, quantity = 3 } }
    GC.Caps.DecideCommodity(cap, levels, { maxQuantity = 4, budget = 1000000 })
    assert.same({ { unitPrice = 90, quantity = 3 }, { unitPrice = 80, quantity = 3 } }, levels)
  end)

  -- Final review M3: `unit` is what the board row, the ring dedup and the dialog header all
  -- show as the price on offer, so it has to be the CHEAPEST qualifying level and not merely
  -- the first one walked. The book is handed over ascending today, which made the two the same
  -- answer by luck -- and a client that ever answers unsorted would have put the wrong price in
  -- front of the player with nothing failing to say so. The same holds for WHICH units a
  -- limited buy takes: the cheapest ones, whatever order they arrived in.
  it("reports and buys the cheapest qualifying levels, not the first ones seen", function()
    local cap = { c = 100 }
    local levels = { -- deliberately not ascending
      { unitPrice = 95, quantity = 1 },
      { unitPrice = 70, quantity = 2 },
      { unitPrice = 120, quantity = 9 }, -- over cap, excluded
      { unitPrice = 90, quantity = 1 },
    }
    local decision = GC.Caps.DecideCommodity(cap, levels, ROOMY)
    assert.equal(70, decision.unit)
    assert.equal(4, decision.quantity)
    assert.equal(70 * 2 + 90 + 95, decision.entryTotal)

    local limited = GC.Caps.DecideCommodity(cap, levels, { maxQuantity = 3, budget = 1000000 })
    assert.equal(3, limited.quantity)
    assert.equal(70 * 2 + 90, limited.entryTotal)
  end)
end)
