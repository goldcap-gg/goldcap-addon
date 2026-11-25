local helper = require("spec.spec_helper")

-- The words for a lot's place in line (goldcap-addon#59, the tie rule shared with the site): never
-- "first in line" while a listing that is not the player's sits at the same unit price. A lot
-- already listed there is "tied with N"; a price about to be posted is first at its price for a
-- commodity (it will be the newest, and the newest sells first) and tied for an item (the order of
-- equal-price item listings is the game's). The player's own listings are never rivals.
describe("Sell place words", function()
  local GC

  before_each(function()
    GC = {}
    helper.loadModule("UI/SellViewModel.lua", GC)
  end)

  local COMMODITY = { positionKey = "commodity:42" }
  local ITEM = { positionKey = "item:7:0:0:0" }

  -- One book for both kinds: 30 of a rival's under 100, 12 at 100 beside 8 of the player's own,
  -- and the player's own 5 alone at 110.
  local LEVELS = {
    { unitPrice = 90, quantity = 30 },
    { unitPrice = 100, quantity = 20, ownerQty = 8 },
    { unitPrice = 110, quantity = 5, ownerQty = 5 },
  }

  local CASES = {
    -- position, price, listed, words, place
    { "commodity post under the book", COMMODITY, 80, false, "first in line", "first" },
    { "commodity post at a rival's price", COMMODITY, 90, false, "first in line", "first" },
    { "commodity lot at a rival's price", COMMODITY, 90, true, "tied with 30", "tied" },
    { "commodity post over a level", COMMODITY, 100, false, "30 ahead", "ahead" },
    { "commodity lot over a level", COMMODITY, 100, true, "30 ahead", "ahead" },
    { "item post under the book", ITEM, 80, false, "first in line", "first" },
    { "item post at a rival's price", ITEM, 90, false, "tied with 30", "tied" },
    { "item lot at a rival's price", ITEM, 90, true, "tied with 30", "tied" },
    { "item lot over a level", ITEM, 100, true, "30 ahead", "ahead" },
  }

  for _, case in ipairs(CASES) do
    local name, position, unit, listed, words, place = case[1], case[2], case[3], case[4], case[5], case[6]
    it(("says %q for a %s"):format(words, name), function()
      local p = { positionKey = position.positionKey, levels = LEVELS }
      local said, kind = GC.SellViewModel.PlaceWords(p, GC.SellViewModel.Standing(p, unit), listed)
      assert.equal(words, said)
      assert.equal(place, kind)
    end)
  end

  -- Own units at the tied level are not counted: at 100 the level holds 20, 8 of them the
  -- player's; a lot there with the 30 under it gone is tied with the other 12.
  it("leaves the player's own units at the price out of the tie", function()
    local levels = { { unitPrice = 100, quantity = 20, ownerQty = 8 } }
    for _, position in ipairs({ COMMODITY, ITEM }) do
      local p = { positionKey = position.positionKey, levels = levels }
      assert.equal("tied with 12", (GC.SellViewModel.PlaceWords(p, GC.SellViewModel.Standing(p, 100), true)))
    end
    -- An item row the client says holds the player's lot and no count is all theirs.
    local mine = { positionKey = ITEM.positionKey, levels = { { unitPrice = 100, quantity = 1, ownerItem = true } } }
    assert.equal("first in line", (GC.SellViewModel.PlaceWords(mine, GC.SellViewModel.Standing(mine, 100), true)))
    -- A level only the player's own holds is first in line, listed or about to be posted.
    local own = { positionKey = ITEM.positionKey, levels = { { unitPrice = 110, quantity = 5, ownerQty = 5 } } }
    assert.equal("first in line", (GC.SellViewModel.PlaceWords(own, GC.SellViewModel.Standing(own, 110), false)))
  end)

  it("says nothing without a standing", function()
    assert.is_nil(GC.SellViewModel.PlaceWords(ITEM, nil, true))
  end)

  it("formats the count the way the row's other counts are formatted", function()
    helper.loadModule("Core/Util.lua", GC)
    local p = { positionKey = ITEM.positionKey, levels = { { unitPrice = 100, quantity = 5600 } } }
    assert.equal("tied with 5.6k", (GC.SellViewModel.PlaceWords(p, GC.SellViewModel.Standing(p, 100), true)))
  end)

  it("reads the listed lots' unit off what they are listed for", function()
    assert.equal(150, GC.SellViewModel.ListedUnit({ listedQty = 2, listedValue = 301 }))
    assert.is_nil(GC.SellViewModel.ListedUnit({ listedQty = 0, listedValue = 300 }))
    assert.is_nil(GC.SellViewModel.ListedUnit({ listedQty = 2, listedValue = 0 }))
    assert.is_nil(GC.SellViewModel.ListedUnit({ listedQty = 2 }))
  end)
end)
