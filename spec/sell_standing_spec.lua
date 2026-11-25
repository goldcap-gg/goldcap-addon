local helper = require("spec.spec_helper")

-- The line under a row's price: how much stock is queued under it and which price level it
-- lands on. Read straight off position.levels, the same book the expanded row draws.
describe("Sell standing", function()
  local GC

  before_each(function()
    GC = {}
    helper.loadModule("UI/SellViewModel.lua", GC)
  end)

  local BOOK = {
    { unitPrice = 1790, quantity = 35 },
    { unitPrice = 1795, quantity = 85 },
    { unitPrice = 1815, quantity = 240 },
    { unitPrice = 1840, quantity = 410 },
  }

  it("counts only the stock at a strictly cheaper price", function()
    local standing = GC.SellViewModel.Standing({ levels = BOOK }, 1815)
    assert.equal(120, standing.ahead)
    assert.equal(3, standing.slot)
  end)

  it("puts a price between two levels on the level it would sit in front of", function()
    local standing = GC.SellViewModel.Standing({ levels = BOOK }, 1800)
    assert.equal(120, standing.ahead)
    assert.equal(3, standing.slot)
  end)

  -- At the cheapest level nothing is ahead, but the 35 listed there are level with the price
  -- (goldcap-addon#59: a rival's 1g70s row above the player's own 1g70s one read "first in line").
  it("counts nothing ahead at or under the cheapest level, and the level's own units as tied", function()
    assert.same({ ahead = 0, tied = 35, slot = 1 }, GC.SellViewModel.Standing({ levels = BOOK }, 1790))
    assert.same({ ahead = 0, tied = 0, slot = 1 }, GC.SellViewModel.Standing({ levels = BOOK }, 1700))
    assert.equal(240, GC.SellViewModel.Standing({ levels = BOOK }, 1815).tied)
    assert.equal(0, GC.SellViewModel.Standing({ levels = BOOK }, 1800).tied)
  end)

  it("lands one past the last level when the price is above the whole book", function()
    local standing = GC.SellViewModel.Standing({ levels = BOOK }, 5000)
    assert.equal(770, standing.ahead)
    assert.equal(5, standing.slot)
  end)

  it("does not count the player's own cheaper lots as competition", function()
    local levels = {
      { unitPrice = 100, quantity = 50, ownerQty = 20 },
      { unitPrice = 110, quantity = 30, ownerItem = true },
      { unitPrice = 120, quantity = 10 },
    }
    assert.equal(30, GC.SellViewModel.Standing({ levels = levels }, 120).ahead)
  end)

  -- An item's book has a row per listing: a rival's row and the player's own at one price are two
  -- rows, and only the rival's units are level with the lot. A commodity's level splits the
  -- player's own out of its count (numOwnerItems).
  it("sums the units that are not the player's over every row at the exact price", function()
    local item = {
      { unitPrice = 17000, quantity = 1 },
      { unitPrice = 17000, quantity = 1, ownerItem = true },
      { unitPrice = 17000, quantity = 2 },
      { unitPrice = 18000, quantity = 5 },
    }
    assert.same({ ahead = 0, tied = 3, slot = 1 }, GC.SellViewModel.Standing({ levels = item }, 17000))
    local commodity = { { unitPrice = 500, quantity = 40, ownerQty = 15 }, { unitPrice = 510, quantity = 9 } }
    assert.same({ ahead = 0, tied = 25, slot = 1 }, GC.SellViewModel.Standing({ levels = commodity }, 500))
    assert.same({ ahead = 25, tied = 9, slot = 2 }, GC.SellViewModel.Standing({ levels = commodity }, 510))
    -- A level all the player's own is no tie.
    assert.equal(0, GC.SellViewModel.Standing({ levels = { { unitPrice = 500, quantity = 4, ownerQty = 4 } } }, 500).tied)
  end)

  it("answers nothing without a book or without a price", function()
    assert.is_nil(GC.SellViewModel.Standing({}, 100))
    assert.is_nil(GC.SellViewModel.Standing({ levels = {} }, 100))
    assert.is_nil(GC.SellViewModel.Standing({ levels = BOOK }, nil))
    assert.is_nil(GC.SellViewModel.Standing({ levels = { { quantity = 5 } } }, 100))
  end)

  -- A commodity post at an equal price is the newest listing there, and the auction house sells
  -- the newest first (live tape, 2026-10-17): the level at its price is behind it, not ahead.
  it("counts no level at the same price as ahead of a commodity post", function()
    local position = { positionKey = "commodity:42", levels = BOOK }
    assert.equal(120, GC.SellViewModel.Standing(position, 1815).ahead)
    assert.equal(3, GC.SellViewModel.Standing(position, 1815).slot)
    assert.equal(0, GC.SellViewModel.Standing(position, 1790).ahead)
    assert.equal(GC.SellViewModel.UnitsAhead(BOOK, 1815), GC.SellViewModel.Standing(position, 1815).ahead)
  end)
end)
