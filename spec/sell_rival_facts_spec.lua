local helper = require("spec.spec_helper")

-- What one answer of the auction house says about one of the player's own listed lots, in the
-- shape GoldCapDB.ownedLots carries up to goldcap.gg: the cheapest unit that is not the player's
-- (`rivalUnit`), units not the player's under the lot's price (`rivalAhead`) and at exactly it
-- (`rivalTied`). The player's own listings are never rivals, the same rule THE BOOK reads by.
describe("Sell rival facts", function()
  local GC

  before_each(function()
    GC = {}
    helper.loadModule("UI/SellViewModel.lua", GC)
  end)

  -- A commodity's levels split the player's own out of each count (numOwnerItems).
  local COMMODITY = {
    { unitPrice = 90, quantity = 30 },
    { unitPrice = 100, quantity = 20, ownerQty = 8 },
    { unitPrice = 110, quantity = 5, ownerQty = 5 },
    { unitPrice = 120, quantity = 7 },
  }
  -- An item's rows: one per group of identical listings, the player's own a row of its own on
  -- retail (containsOwnerItem, no count) and a counted share on WoW: Forever.
  local ITEM = {
    { unitPrice = 17000, quantity = 1 },
    { unitPrice = 17000, quantity = 1, ownerItem = true },
    { unitPrice = 18000, quantity = 40, ownerItem = true, ownerQty = 37 },
    { unitPrice = 19000, quantity = 2 },
  }
  local OWN_ONLY = { { unitPrice = 22400, quantity = 1, ownerItem = true } }

  local CASES = {
    -- name, levels, lot price, rivalUnit, rivalAhead, rivalTied
    { "commodity lot under the book", COMMODITY, 80, 90, 0, 0 },
    { "commodity lot at a rival's price", COMMODITY, 90, 90, 0, 30 },
    { "commodity lot sharing a level with its own", COMMODITY, 100, 90, 30, 12 },
    { "commodity lot alone at its own level", COMMODITY, 110, 90, 42, 0 },
    { "commodity lot over the book", COMMODITY, 130, 90, 49, 0 },
    { "item lot level with a rival's row (goldcap-addon#59)", ITEM, 17000, 17000, 0, 1 },
    { "item lot in a row it shares with other sellers", ITEM, 18000, 17000, 1, 3 },
    { "item lot behind every row", ITEM, 19000, 17000, 4, 2 },
    { "item lot nobody else sells", OWN_ONLY, 22400, nil, 0, 0 },
  }

  for _, case in ipairs(CASES) do
    local name, levels, unit, rival, ahead, tied = case[1], case[2], case[3], case[4], case[5], case[6]
    it("reads a " .. name, function()
      assert.same({ rivalUnit = rival, rivalAhead = ahead, rivalTied = tied },
        GC.SellViewModel.RivalFacts(levels, unit))
    end)
  end

  -- A read cut short (more rows than it takes, or an answer the client does not hold in full)
  -- says nothing past its last level: a count there would be a floor, not the fact.
  describe("a read cut short", function()
    local function cut(levels)
      local copy = {}
      for i, level in ipairs(levels) do copy[i] = level end
      copy.cut = true
      return copy
    end

    it("still speaks for a lot priced under its last level", function()
      assert.same({ rivalUnit = 90, rivalAhead = 30, rivalTied = 12 }, GC.SellViewModel.RivalFacts(cut(COMMODITY), 100))
    end)

    it("says nothing of a lot at or past its last level", function()
      assert.is_nil(GC.SellViewModel.RivalFacts(cut(COMMODITY), 120))
      assert.is_nil(GC.SellViewModel.RivalFacts(cut(COMMODITY), 130))
    end)

    it("says nothing when every level it read is the player's own", function()
      local mine = cut({ { unitPrice = 100, quantity = 5, ownerQty = 5 }, { unitPrice = 200, quantity = 5, ownerQty = 5 } })
      assert.is_nil(GC.SellViewModel.RivalFacts(mine, 100))
    end)
  end)

  it("says nothing without a level read or a price", function()
    assert.is_nil(GC.SellViewModel.RivalFacts(nil, 100))
    assert.is_nil(GC.SellViewModel.RivalFacts({}, 100))
    assert.is_nil(GC.SellViewModel.RivalFacts(COMMODITY, nil))
    assert.is_nil(GC.SellViewModel.RivalFacts(COMMODITY, 0))
  end)
end)
