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
    _G.C_AuctionHouse = { CalculateCommodityDeposit = function() error("AH closed") end }
    assert.is_nil(GC.ForeverValue.DepositUnit(2589))
    GC.db.settings.sniper.postDuration = "48"
    assert.equal(2, GC.Flips.PostDurationIndex())
  end)
end)
