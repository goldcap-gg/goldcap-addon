local helper = require("spec.spec_helper")

-- The addon's market data is keyed by item ID, and the site merges every item level of a piece
-- of gear into one row -- and every caged battle pet into Pet Cage (82800), "min and median
-- taken across completely different pets". A position keyed by one item level or one pet
-- species therefore has no market figure of its own: its price comes from the live search of
-- its exact key and nothing else. A 15g pet was being floored to 225g off the Pet Cage median.
describe("Sell tab, a variant's market is its own", function()
  local GC
  local context = { char = "A-R", region = "eu" }

  local function build(args)
    args.acquisitions = args.acquisitions or {}
    args.ownedLots = args.ownedLots or {}
    args.quotes = args.quotes or {}
    args.statsByItemID = args.statsByItemID or {}
    args.context = context
    args.now = 1000
    args.quoteMaxAge = 45
    return GC.SellPositions.Build(args)
  end

  local function find(positions, positionKey)
    for _, p in ipairs(positions) do if p.positionKey == positionKey then return p end end
    return nil
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadModule("Core/SellPositions.lua", GC)
    helper.loadModule("UI/SellViewModel.lua", GC)
    GC.db = { settings = { sniper = {} } }
  end)

  local PET = "item:82800:25:0:1234"
  local PET_STATS = { [82800] = { mv = 3000000, sold = 12000, p25 = 2000000, reach = 2500000, trend = 0 } }

  it("prices a caged pet from its own live book, never a floor off the Pet Cage median", function()
    local p = find(build({
      bagStock = { { positionKey = PET, itemID = 82800, itemName = "Mechanical Squirrel", quantity = 1,
        isCommodity = false, quoteKey = PET, stacks = { { bag = 0, slot = 1, quantity = 1 } } } },
      quotes = { [PET] = { unit = 150000, at = 1000, levels = { { unitPrice = 150000, quantity = 1 } } } },
      statsByItemID = PET_STATS,
    }), PET)
    assert.equal(150000, p.freshMarketUnit)
    assert.is_nil(p.marketValue)
    assert.is_nil(p.soldPerDay)
    assert.is_nil(p.postFloor)
    assert.equal(150000, p.postRecommendation.unit)
    assert.equal("pet", p.variantKind)
  end)

  it("gives a gear variant no market value, sales or floor from the merged item", function()
    local key = "item:222:619:0:0"
    local p = find(build({
      bagStock = { { positionKey = key, itemID = 222, quantity = 1, isCommodity = false, quoteKey = key,
        stacks = { { bag = 0, slot = 1, quantity = 1 } } } },
      quotes = { [key] = { unit = 500000, at = 1000, levels = { { unitPrice = 500000, quantity = 1 } } } },
      statsByItemID = { [222] = { mv = 9000000, sold = 50, reach = 9500000 } },
    }), key)
    assert.is_nil(p.marketValue)
    assert.is_nil(p.soldPerDay)
    assert.equal(500000, p.postRecommendation.unit)
    assert.equal("level", p.variantKind)
    -- And says so, rather than leaving the figure to look merely missing.
    assert.matches("no market figure for this item level", GC.SellViewModel.Expansion(p).factsText or "", 1, true)
  end)

  it("keeps market data for an item keyed the way it always was", function()
    local key = "item:42:100:7:0"
    local p = find(build({
      bagStock = { { positionKey = key, itemID = 42, quantity = 1, isCommodity = false,
        stacks = { { bag = 0, slot = 1, quantity = 1 } } } },
      quotes = { [42] = { unit = 500000, at = 1000, levels = { { unitPrice = 500000, quantity = 1 } } } },
      statsByItemID = { [42] = { mv = 600000, sold = 50 } },
    }), key)
    assert.equal(600000, p.marketValue)
    assert.equal(50, p.soldPerDay)
    assert.is_nil(p.variantKind)
  end)

  -- The last copy posted, the position lives on its lot alone -- and must keep being priced by
  -- its exact key: the bare key's answer is the item's cheapest variant, which made a 619 lot
  -- read undercut by a 610 (review I3).
  it("keeps a posted variant's lot on its own key when nothing is left in the bags", function()
    local key = "item:222:619:0:0"
    local p = find(build({
      ownedLots = { { positionKey = key, itemID = 222, quantity = 1, unitPrice = 5000000, auctionID = 7,
        firstSeenAt = 1, variant = true } },
      quotes = { [key] = { unit = 5000000, at = 1000 }, [222] = { unit = 1000000, at = 1000 } },
      statsByItemID = { [222] = { mv = 9000000, sold = 50 } },
    }), key)
    assert.equal(key, p.quoteKey)
    assert.equal(5000000, p.freshMarketUnit)
    assert.is_false(p.facts.undercut)
    assert.is_nil(p.marketValue)
  end)

  it("marks an owned lot a variant from what the client says about it", function()
    local lots = GC.SellPositions.NormalizeOwnedLots({
      { auctionID = 1, itemKey = { itemID = 222, itemLevel = 619 }, quantity = 1, buyoutAmount = 500,
        isCommodity = false, itemLink = "|cffa335ee|Hitem:222:0::0:0:0:0:0:0:0:0:0:2:6652:1520|h[Helm]|h|r" },
      { auctionID = 2, itemKey = { itemID = 42, itemLevel = 100, itemSuffix = 7 }, quantity = 1, buyoutAmount = 500,
        isCommodity = false, itemLink = "|cffffffff|Hitem:42:0::0:0:0:7:0:0:0:0:0:0|h[Plain]|h|r" },
      { auctionID = 3, itemKey = { itemID = 82800, itemLevel = 25, battlePetSpeciesID = 1234 }, quantity = 1,
        buyoutAmount = 500, isCommodity = false },
    }, 10)
    assert.is_true(lots[1].variant)
    assert.is_nil(lots[2].variant)
    assert.is_true(lots[3].variant)
  end)

  -- A posted pet with nothing left in the bags is named from its lot's own link, not "Pet Cage"
  -- (review N3).
  it("names a lot-only pet from its lot's link", function()
    local lots = GC.SellPositions.NormalizeOwnedLots({
      { auctionID = 9, itemKey = { itemID = 82800, itemLevel = 25, battlePetSpeciesID = 1234 }, quantity = 1,
        buyoutAmount = 150000, isCommodity = false,
        itemLink = "|cff0070dd|Hbattlepet:1234:25:3:1500:300:300:0|h[Mechanical Squirrel]|h|r" },
    }, 10)
    local p = find(build({ ownedLots = lots }), lots[1].positionKey)
    assert.equal("Mechanical Squirrel", p.itemName)
  end)

  -- Bonus IDs on a non-gear item (its ItemKey carries no item level) make no level variant: its
  -- market data is the item's own, and stays (review N8).
  it("keeps market data for a bonus-ID item with no item level", function()
    local key = "item:5:0:0:0"
    local p = find(build({
      bagStock = { { positionKey = key, itemID = 5, quantity = 1, isCommodity = false, quoteKey = key,
        stacks = { { bag = 0, slot = 1, quantity = 1 } } } },
      quotes = { [key] = { unit = 500000, at = 1000 }, [5] = { unit = 500000, at = 1000 } },
      statsByItemID = { [5] = { mv = 600000, sold = 50 } },
    }), key)
    assert.is_nil(p.variantKind)
    assert.equal(600000, p.marketValue)
    local lots = GC.SellPositions.NormalizeOwnedLots({
      { auctionID = 4, itemKey = { itemID = 5 }, quantity = 1, buyoutAmount = 500, isCommodity = false,
        itemLink = "|cffffffff|Hitem:5:0::0:0:0:0:0:0:0:0:0:1:1520|h[Trinket]|h|r" },
    }, 10)
    assert.is_nil(lots[1].variant)
  end)

  -- WoW: Forever (2026-11-06): an item ID has one item level there, and its ItemKey states it for
  -- every non-commodity, gear or not (the owner's save: item:828:5:0:0, Small Blue Pouch). Read as
  -- a level variant, every one of them lost its AH value and its floor. Compose passes
  -- `oneLevelPerItem` only there.
  describe("in WoW: Forever, where an item ID has one item level", function()
    local POUCH = "item:828:5:0:0"
    local savedAH

    before_each(function()
      savedAH = _G.C_AuctionHouse
      _G.C_AuctionHouse = { SupportsCopperValues = function() return true end }
    end)

    after_each(function() _G.C_AuctionHouse = savedAH end)

    -- One troll lot at 1s over the real shelf, 157 at 3s and 300 at 4s; the scan's value is 3s.
    local function pouch(oneLevel, key)
      key = key or POUCH
      return find(build({
        bagStock = { { positionKey = key, itemID = 828, itemName = "Small Blue Pouch", quantity = 1,
          isCommodity = false, quoteKey = key, stacks = { { bag = 0, slot = 1, quantity = 1 } } } },
        quotes = { [key] = { unit = 100, at = 1000, levels = { { unitPrice = 100, quantity = 1 },
          { unitPrice = 300, quantity = 157 }, { unitPrice = 400, quantity = 300 } } } },
        statsByItemID = { [828] = { mv = 300, source = "scan", kind = "own_scan" } },
        oneLevelPerItem = oneLevel,
      }), key)
    end

    it("values a level-keyed item from its own item ID, and holds it at the floor over one troll lot", function()
      local p = pouch(true)
      assert.is_nil(p.variantKind)
      assert.equal(300, p.marketValue)
      assert.equal(225, p.postFloor)
      -- The floor is 2s 25c and the pouch is an item: an item posts at whole silver only, on
      -- WoW: Forever too (a green posted at 1s 10c never went up, owner, 2026-11-06), so it holds
      -- at 3s, the next whole silver up, and so does the price Post sends.
      assert.equal(300, p.postRecommendation.unit)
      assert.equal("floor", p.postRecommendation.mode)
      local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 828, exactQty = 1, positionKey = POUCH },
        { unit = 100, fresh = true })
      assert.equal(300, plan.unitPrice)
      -- Still searched by the stack's own key, the one the client answers for.
      assert.equal(POUCH, p.quoteKey)
      assert.is_nil((GC.SellViewModel.Expansion(p).factsText or ""):find("no market figure", 1, true))
    end)

    it("keeps retail's level variant as it was", function()
      local p = pouch(nil)
      assert.equal("level", p.variantKind)
      assert.is_nil(p.marketValue)
      assert.is_nil(p.postFloor)
      assert.equal(100, p.postRecommendation.unit)
    end)

    it("keeps a suffix variant on its own book, with no market figure", function()
      local key = "item:828:5:1234:0"
      local p = pouch(true, key)
      assert.equal("level", p.variantKind)
      assert.is_nil(p.marketValue)
      assert.is_nil(p.postFloor)
    end)

    -- The owner's save (2026-11-06): one scroll (211785) listed at 1s, nothing left in the bags.
    -- A Forever link carries no bonus IDs, so the lot is no variant, and the position went back
    -- to the bare item ID's quote (2s there) while the fold had 2,812 of 2,921 lots at 1s.
    local SCROLL = "item:211785:10:0:0"
    local function scrollLot(oneLevel)
      local lots = GC.SellPositions.NormalizeOwnedLots({
        { auctionID = 6929041, itemKey = { itemID = 211785, itemLevel = 10, itemSuffix = 0, battlePetSpeciesID = 0 },
          itemLink = "|cffffffff|Hitem:211785::::::::10:::::::::|h[Scroll]|h|r", quantity = 1,
          buyoutAmount = 100, isCommodity = false, timeLeftSeconds = 27000 },
      }, 900)
      return find(build({
        ownedLots = lots, oneLevelPerItem = oneLevel,
        -- Under the lot's own key, its row of 2,774 at 1s counts other sellers' lots (Quotes.lua).
        quotes = { [SCROLL] = { unit = 100, at = 1000, fresh = true, levels = {
            { unitPrice = 100, quantity = 2774, ownerItem = true, ownerQty = 2735 },
            { unitPrice = 200, quantity = 38 } } },
          [211785] = { unit = 200, at = 1000, fresh = true, levels = {
            { unitPrice = 100, quantity = 2774, ownerItem = true }, { unitPrice = 200, quantity = 38 } } } },
        statsByItemID = { [211785] = { mv = 100, source = "scan", kind = "own_scan", ts = 700 } },
      }), SCROLL)
    end

    it("prices a lot with nothing left in the bags by its own key", function()
      helper.loadModule("Core/CancelQueue.lua", GC)
      local p = scrollLot(true)
      assert.is_nil(p.ownedLots[1].variant)
      assert.equal(SCROLL, p.quoteKey)
      assert.equal(100, p.freshMarketUnit)
      assert.is_false(p.facts.underpriced)
      assert.same({}, (GC.CancelQueue.Build({ p }, {})))
    end)

    it("keeps retail's lot-only item on its bare item ID", function()
      local p = scrollLot(nil)
      assert.is_nil(p.quoteKey)
      assert.equal(200, p.freshMarketUnit)
    end)

    it("leaves a lot-only item with a bare key on its item ID", function()
      local lots = GC.SellPositions.NormalizeOwnedLots({
        { auctionID = 5, itemKey = { itemID = 4306, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
          itemLink = "|cffffffff|Hitem:4306:::::::::::::::::|h[Silk Cloth]|h|r", quantity = 1,
          buyoutAmount = 100, isCommodity = false },
      }, 900)
      local p = find(build({ ownedLots = lots, oneLevelPerItem = true }), "item:4306:0:0:0")
      assert.is_nil(p.quoteKey)
    end)
  end)
end)
