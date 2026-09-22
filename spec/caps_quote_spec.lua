local helper = require("spec.spec_helper")

-- Live price caps, addon task 7: the requote guard. `deal` is a board deal (buildCapDeal's own
-- `.cap`, the copper amount, or nil for an uncapped item) and `unit` is the unit price a live
-- server quote just came back with. Pure: UI/SniperFrame.lua's OnCommodityPriceUpdated is the
-- one caller, and routes a false result into the existing "loud" requote path -- the player
-- never pays above the price they set.
describe("Caps.QuoteOk", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Caps.lua")
  end)

  it("is true when the deal has no cap at all", function()
    assert.is_true(GC.Caps.QuoteOk({ itemID = 1 }, 5000))
  end)

  it("is true for a nil deal", function()
    assert.is_true(GC.Caps.QuoteOk(nil, 5000))
  end)

  it("is true when the quote is at the cap exactly", function()
    assert.is_true(GC.Caps.QuoteOk({ itemID = 1, cap = 1000 }, 1000))
  end)

  it("is true when the quote is under the cap", function()
    assert.is_true(GC.Caps.QuoteOk({ itemID = 1, cap = 1000 }, 999))
  end)

  it("is false when the quote is over the cap, however slightly", function()
    assert.is_false(GC.Caps.QuoteOk({ itemID = 1, cap = 1000 }, 1001))
  end)
end)
