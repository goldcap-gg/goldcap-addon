local helper = require("spec.spec_helper")

-- A gear line's lots (Core/BuyLots.lua). A search row is N identical auctions and its
-- buyoutAmount is what ONE of them costs; PlaceBid buys one.
describe("BuyLots", function()
  local L
  before_each(function() L = helper.loadModule("Core/BuyLots.lua").BuyLots end)

  local function row(id, buyout, qty, over)
    local r = { auctionID = id, buyoutAmount = buyout, quantity = qty or 1, containsOwnerItem = false,
      itemKey = { itemID = 7, itemLevel = 20, itemSuffix = 0 } }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
  end

  it("turns rows into lots, cheapest first, one buyout per lot", function()
    local lots = L.FromRows({ row(3, 1000, 2), row(1, 900, 4), row(2, 1900, 1) })
    assert.same({ 1, 3, 2 }, { lots[1].auctionID, lots[2].auctionID, lots[3].auctionID })
    assert.equal(900, lots[1].buyout)
    assert.equal(4, lots[1].count)
  end)

  -- Review Focus 3.
  it("never offers the player's own lot, or one with no buyout", function()
    -- The bid-only row is written out whole: `{ buyoutAmount = nil }` cannot remove a key in Lua.
    local bidOnly = { auctionID = 2, quantity = 1, containsOwnerItem = false, minBid = 400,
      itemKey = { itemID = 7, itemLevel = 20, itemSuffix = 0 } }
    local lots = L.FromRows({ row(1, 500, 1, { containsOwnerItem = true }), bidOnly, row(3, 900, 1) })
    assert.equal(1, #lots)
    assert.equal(3, lots[1].auctionID)
  end)

  it("keeps each lot's item level and suffix", function()
    local lots = L.FromRows({ row(1, 900, 1, { itemKey = { itemID = 7, itemLevel = 25, itemSuffix = 1019,
      battlePetSpeciesID = 0 } }) })
    assert.same({ 25, 1019, 0 }, { lots[1].itemLevel, lots[1].itemSuffix, lots[1].species })
  end)

  describe("Groups", function()
    local LOTS
    before_each(function() LOTS = L.FromRows({ row(1, 900, 4), row(2, 1000, 2), row(3, 1900, 1), row(4, 2500, 1) }) end)
    it("groups by price, cheapest first, three at most, marking what is over the cap", function()
      assert.same({ { buyout = 900, count = 4, over = false }, { buyout = 1000, count = 2, over = false },
        { buyout = 1900, count = 1, over = true } }, L.Groups(LOTS, 1170))
    end)
    it("adds the counts of two rows at one price", function()
      local lots = L.FromRows({ row(1, 900, 4), row(5, 900, 3) })
      assert.same({ { buyout = 900, count = 7, over = false } }, L.Groups(lots, 1000))
    end)
    it("leaves out lots below the line's item level", function()
      local lots = L.FromRows({ row(1, 500, 1, { itemKey = { itemLevel = 10 } }), row(2, 900, 1) })
      assert.equal(900, L.Groups(lots, 1000, 20)[1].buyout)
    end)
    it("marks nothing over with no cap", function()
      assert.is_false(L.Groups(LOTS, nil)[1].over)
    end)
  end)

  describe("Next", function()
    local LOTS
    before_each(function() LOTS = L.FromRows({ row(1, 900, 4), row(2, 1000, 2), row(3, 1900, 1) }) end)
    local cases = {
      { "the cheapest lot at or under the cap", 1170, nil, 100000, 1, nil },
      { "a lot exactly at the cap", 900, nil, 100000, 1, nil },
      { "nothing without a cap", nil, nil, 100000, nil, "nocap" },
      { "nothing when the cheapest is over the cap", 800, nil, 100000, nil, "over" },
      { "nothing the wallet cannot pay", 1170, nil, 850, nil, "wallet" },
      { "no money given means no wallet limit", 1170, nil, nil, 1, nil },
    }
    for _, case in ipairs(cases) do
      it(case[1], function()
        local lot, why = L.Next(LOTS, case[2], case[3], case[4])
        assert.equal(case[5], lot and lot.auctionID or nil)
        assert.equal(case[6], why)
      end)
    end
    it("skips lots below the item level", function()
      local lots = L.FromRows({ row(1, 500, 1, { itemKey = { itemLevel = 10 } }), row(2, 900, 1) })
      assert.equal(2, L.Next(lots, 1000, 20, 100000).auctionID)
    end)
    it("says none for an empty list", function()
      local lot, why = L.Next({}, 1000, nil, 100000)
      assert.is_nil(lot)
      assert.equal("none", why)
    end)
  end)

  it("swaps one variant's lots for its fresh read and keeps the others", function()
    local all = L.FromRows({ row(1, 900, 4), row(2, 1000, 2), row(3, 800, 1, { itemKey = { itemLevel = 25 } }) })
    local fresh = L.FromRows({ row(2, 1000, 2) })
    local lots = L.Replace(all, fresh, { itemID = 7, itemLevel = 20, itemSuffix = 0, battlePetSpeciesID = 0 })
    assert.same({ 3, 2 }, { lots[1].auctionID, lots[2].auctionID })
  end)

  it("gives the tooltip and the raise a ladder: one level per lot row", function()
    local lots = L.FromRows({ row(1, 900, 4), row(2, 1000, 2) })
    assert.same({ { unit = 900, qty = 4 }, { unit = 1000, qty = 2 } }, L.AsLevels(lots))
  end)
end)
