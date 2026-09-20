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

  it("is first in line at or under the cheapest level", function()
    assert.same({ ahead = 0, slot = 1 }, GC.SellViewModel.Standing({ levels = BOOK }, 1790))
    assert.same({ ahead = 0, slot = 1 }, GC.SellViewModel.Standing({ levels = BOOK }, 1700))
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

  it("answers nothing without a book or without a price", function()
    assert.is_nil(GC.SellViewModel.Standing({}, 100))
    assert.is_nil(GC.SellViewModel.Standing({ levels = {} }, 100))
    assert.is_nil(GC.SellViewModel.Standing({ levels = BOOK }, nil))
    assert.is_nil(GC.SellViewModel.Standing({ levels = { { quantity = 5 } } }, 100))
  end)
end)
