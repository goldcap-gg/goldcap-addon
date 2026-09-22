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

  -- Caps fixes 2f: the server quotes an AVERAGE unit price, and an average at or under the cap
  -- says nothing about the dearest unit inside it -- 10 x 100g + 10 x 190g + 5 x 250g averages
  -- 166g under a 200g cap while five of those units are above it. What the handler does know is
  -- the freshest book: `fresh` is the cap decision for exactly the armed quantity on it
  -- (GC.Caps.DecideCommodity), whose entryTotal is what those units cost at or under the cap.
  -- A quote costing more than that is not proven to stay under the cap; a book that cannot fill
  -- the quantity at or under the cap at all (`false`) proves the quote cannot.
  describe("held to the freshest book", function()
    local deal = { itemID = 1, cap = 2000000 }

    it("is true when the quote costs what the book's units at or under the cap cost", function()
      assert.is_true(GC.Caps.QuoteOk(deal, 1450000, 29000000, { entryTotal = 29000000 }))
    end)

    it("is true when the quote costs less -- the book only got cheaper", function()
      assert.is_true(GC.Caps.QuoteOk(deal, 1400000, 28000000, { entryTotal = 29000000 }))
    end)

    it("is false when the quote costs more than those units, however low its average", function()
      assert.is_false(GC.Caps.QuoteOk(deal, 1450100, 29002000, { entryTotal = 29000000 }))
    end)

    it("is false when the book cannot fill the armed quantity at or under the cap", function()
      assert.is_false(GC.Caps.QuoteOk(deal, 1660000, 41500000, false))
    end)

    it("still refuses an average above the cap, whatever the book says", function()
      assert.is_false(GC.Caps.QuoteOk(deal, 2000001, 2000001, { entryTotal = 99999999 }))
    end)

    it("judges on the average alone when there is no book to hold the quote to", function()
      assert.is_true(GC.Caps.QuoteOk(deal, 1450000, 29000000, nil))
    end)

    it("is true for a deal with no cap, whatever else it is handed", function()
      assert.is_true(GC.Caps.QuoteOk({ itemID = 1 }, 1450000, 29000000, false))
    end)
  end)
end)
