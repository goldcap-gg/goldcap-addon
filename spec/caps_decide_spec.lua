local helper = require("spec.spec_helper")

-- Live price caps, addon task 5: judging a drilled lot/book against the player's own price
-- cap, not the market. GC.Caps.DecideRealm picks the cheapest COMPARABLE lot (itemLevel >=
-- cap.l) at or under cap.c; GC.Caps.DecideCommodity sums how much of the book sits at or under
-- cap.c and refuses to arm unless the saving clears the player's own minimum-profit floor. Both
-- are pure: same inputs untouched, in, decision out.
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
    }, decision)
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

  before_each(function()
    GC = helper.loadModule("Core/Caps.lua")
  end)

  it("counts only levels at or under the cap", function()
    local cap = { c = 100 }
    local levels = {
      { unitPrice = 80, quantity = 3 },
      { unitPrice = 90, quantity = 2 },
      { unitPrice = 120, quantity = 10 }, -- over cap, excluded
    }
    local decision = GC.Caps.DecideCommodity(cap, levels, 1)
    assert.same({
      status = "SAFE", buyable = true, cap = true,
      quantity = 5,
      stressProfit = (100 - 80) * 3 + (100 - 90) * 2,
      unit = 80,
    }, decision)
  end)

  it("returns nil when the saving is under the minimum profit floor", function()
    local cap = { c = 100 }
    local levels = { { unitPrice = 99, quantity = 1 } } -- saves 1 copper
    assert.is_nil(GC.Caps.DecideCommodity(cap, levels, 1000))
  end)

  it("returns nil for an empty book", function()
    assert.is_nil(GC.Caps.DecideCommodity({ c = 100 }, {}, 0))
  end)

  it("returns nil when every level is over the cap", function()
    local cap = { c = 100 }
    local levels = { { unitPrice = 150, quantity = 5 } }
    assert.is_nil(GC.Caps.DecideCommodity(cap, levels, 0))
  end)

  it("never mutates the levels it is handed", function()
    local cap = { c = 100 }
    local levels = { { unitPrice = 80, quantity = 3 } }
    local before = { unitPrice = 80, quantity = 3 }
    GC.Caps.DecideCommodity(cap, levels, 0)
    assert.same(before, levels[1])
  end)
end)
