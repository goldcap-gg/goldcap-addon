local helper = require("spec.spec_helper")

describe("ForeverValue", function()
  local GC, saved
  before_each(function()
    saved = { C_Item = _G.C_Item, C_AuctionHouse = _G.C_AuctionHouse }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/ForeverValue.lua", GC)
  end)
  after_each(function() for k, v in pairs(saved) do _G[k] = v end end)

  describe("Verdict", function()
    local V
    before_each(function() V = GC.ForeverValue.Verdict end)
    it("sends to the vendor what the AH pays no more for, after its cut", function()
      assert.equal("vendor", V(100, 95, 5, false))    -- floor(95) - 95 = 0
    end)
    it("says the AH when the gain beats the deposit", function()
      assert.equal("ah", V(1000, 100, 50, false))
    end)
    it("says not worth the deposit when the gain does not cover it", function()
      assert.equal("deposit", V(200, 100, 90, false)) -- gain 90
      assert.equal("deposit", V(20, nil, 30, false))  -- no vendor price, tiny AH value
    end)
    it("says the AH without counting a deposit it cannot know", function()
      assert.equal("ah_nodeposit", V(1000, 100, nil, false))
    end)
    it("never sends gear to the vendor on its cheapest version's price", function()
      assert.is_nil(V(100, 200, 5, true))
      assert.equal("ah", V(1000, 100, 5, true))
    end)
    it("says nothing without an AH value, or when nobody pays anything", function()
      assert.is_nil(V(nil, 100, 5, false))
      assert.is_nil(V(0, 100, 5, false))
      assert.is_nil(V(1, nil, nil, false))             -- floor(0.95) = 0, no vendor
    end)
  end)

  it("reads the vendor price from the client, and nil where it has none", function()
    _G.C_Item = { GetItemInfo = function(id)
      if id == 2589 then return "Linen Cloth", nil, 1, 1, 1, "Trade Goods", "Cloth", 20, "", 1, 13 end
      if id == 5 then error("not cached") end
      return "Thing", nil, 1, 1, 1, "Misc", "Junk", 1, "", 1, 0
    end }
    assert.equal(13, GC.ForeverValue.VendorUnit(2589))
    assert.is_nil(GC.ForeverValue.VendorUnit(7))
    assert.is_nil(GC.ForeverValue.VendorUnit(5))
    _G.C_Item = nil
    assert.is_nil(GC.ForeverValue.VendorUnit(2589))
  end)

  it("asks a commodity's deposit at the player's post duration, and nothing of an unknown item", function()
    local asked
    _G.C_AuctionHouse = { CalculateCommodityDeposit = function(id, duration, qty)
      asked = { id, duration, qty }; return 12 end }
    GC.db = { settings = { sniper = { postDuration = 3 } }, commodityByItem = { [2589] = true, [9] = false } }
    assert.equal(12, GC.ForeverValue.DepositUnit(2589))
    assert.same({ 2589, 3, 1 }, asked)
    assert.is_nil(GC.ForeverValue.DepositUnit(9))
    assert.is_nil(GC.ForeverValue.DepositUnit(10))
    -- The Deals board's own read (the caller already knows it is a commodity): no bag history needed.
    assert.equal(12, GC.ForeverValue.CommodityDepositUnit(10))
    assert.same({ 10, 3, 1 }, asked)
    _G.C_AuctionHouse = { CalculateCommodityDeposit = function() error("AH closed") end }
    assert.is_nil(GC.ForeverValue.DepositUnit(2589))
    assert.is_nil(GC.ForeverValue.CommodityDepositUnit(2589))
    GC.db.settings.sniper.postDuration = "48"
    assert.equal(2, GC.Flips.PostDurationIndex())
  end)
end)

describe("ForeverValue bags", function()
  local GC
  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/ForeverValue.lua", GC)
  end)

  local BAGS = {
    [0] = {
      { itemID = 2589, stackCount = 20 },                       -- AH 67, vendor 13
      { itemID = 6948, stackCount = 1, isBound = true },        -- hearthstone: bound, no value
      { itemID = 99, stackCount = 2, isBound = true },          -- bound, vendor 50
    },
    [1] = { nil, { itemID = 7, stackCount = 3 } },               -- no AH value, vendor 5
    [5] = { { itemID = 8, stackCount = 1, hasNoValue = true } }, -- reagent bag, AH 1000
  }
  local driver = {
    numSlots = function(bag) return BAGS[bag] and 3 or 0 end,
    itemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] or nil end,
  }
  local AH = { [2589] = 67, [8] = 1000 }
  local VENDOR = { [2589] = 13, [99] = 50, [7] = 5, [8] = 400 }

  it("adds a vendor's price for everything and the AH's, after its cut, for what can be sold there", function()
    local t = GC.ForeverValue.BagTotals(driver,
      function(id) return AH[id] and { mv = AH[id] } or nil end,
      function(id) return VENDOR[id] end)
    assert.equal(20 * 13 + 2 * 50 + 3 * 5, t.vendor)            -- hasNoValue: the vendor takes nothing
    assert.equal(20 * math.floor(67 * 0.95) + math.floor(1000 * 0.95), t.ah)
    assert.equal(2, t.priced)
    assert.equal(1, t.unpriced)
  end)

  it("prints the two totals and the way to post, or the vendor total and the scan hint", function()
    local printed = {}
    GC.Print = function(m) printed[#printed + 1] = m end
    GC.Data = { GetItemValue = function(id) return AH[id] and { mv = AH[id] } or nil end }
    GC.ForeverValue.VendorUnit = function(id) return VENDOR[id] end
    GC.ForeverValue.PrintBags(driver)
    assert.truthy(printed[1]:find("^Your bags: .* at a vendor, .* on the AH after its cut$"))
    assert.equal("The Sell tab's POST button lists everything worth more than a vendor pays, one click each.", printed[2])
    GC.Data.GetItemValue = function() return nil end
    GC.ForeverValue.PrintBags(driver)
    assert.truthy(printed[3]:find("Scan the auction house to see what they would fetch there.", 1, true))
  end)
end)
