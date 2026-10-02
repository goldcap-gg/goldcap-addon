local helper = require("spec.spec_helper")

-- Core/VendorBuys.lua: every merchant purchase becomes a cost lot once the bags prove it arrived,
-- at the merchant's own price per unit, exactly once. The merchant and the bags are API-shaped
-- fakes (C_MerchantFrame.GetItemInfo's price/stackCount/hasExtendedCost, GetMerchantItemID); the
-- acquisition store and Core/BuyVendor.lua are the real ones.
describe("vendor purchases as cost", function()
  local GC, db, bag, shelf
  local me = { char = "Cook-Realm", region = "eu" }

  local function vendorLots()
    local out = {}
    for _, batch in ipairs(db.acquisitions) do
      if batch.source == "vendor" then out[#out + 1] = batch end
    end
    return out
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadModule("Core/BuyVendor.lua", GC)
    helper.loadModule("Core/VendorBuys.lua", GC)
    db = {}
    GC.db = db
    GC.Acquisitions.Init(db)
    GC.Ledger = { Context = function() return me end }
    bag = { [2320] = 0, [3371] = 0 }
    -- 1: Coarse Thread, 10c for 1. 2: Empty Vial, 8c for a stack of 4. 3: a sold-for-tokens item.
    shelf = {
      { itemID = 2320, price = 10, stackCount = 1, numAvailable = -1, isPurchasable = true, hasExtendedCost = false },
      { itemID = 3371, price = 8, stackCount = 4, numAvailable = -1, isPurchasable = true, hasExtendedCost = false },
      { itemID = 4000, price = 500, stackCount = 1, numAvailable = -1, isPurchasable = true, hasExtendedCost = true },
    }
    _G.C_MerchantFrame = { GetItemInfo = function(index) return shelf[index] end }
    _G.GetMerchantItemID = function(index) return shelf[index] and shelf[index].itemID end
    _G.GetMerchantItemMaxStack = function() return 20 end
    _G.C_Item = {
      GetItemCount = function(itemID) return bag[itemID] or 0 end,
      GetItemMaxStackSizeByID = function(itemID) return itemID == 4000 and 1 or 20 end,
      GetItemNameByID = function(itemID) return "Item" .. itemID end,
    }
    _G.hooksecurefunc, _G.BuyMerchantItem = nil, nil
    GC.VendorBuys.Install()
  end)

  after_each(function()
    _G.C_MerchantFrame, _G.GetMerchantItemID, _G.GetMerchantItemMaxStack, _G.C_Item = nil, nil, nil, nil
  end)

  it("books a bought stack at the price per unit once the bags show it", function()
    GC.VendorBuys.OnBuy(2, 8, 100)             -- 8 units of a 4-stack at 8c: two stacks, 16c
    assert.equal(0, #vendorLots())             -- nothing arrived yet: nothing booked
    GC.VendorBuys.OnBagsChanged(101)
    assert.equal(0, #vendorLots())
    bag[3371] = 8
    GC.VendorBuys.OnBagsChanged(102)
    local lots = vendorLots()
    assert.equal(1, #lots)
    assert.equal(8, lots[1].originalQty)
    assert.equal(16, lots[1].originalTotal)    -- 2c a unit, not 8c
    assert.equal("commodity:3371", lots[1].positionKey)
    assert.equal(me.char, lots[1].character)
    assert.equal("Item3371", lots[1].itemName)
  end)

  it("prices one unit of a stacked offer pro rata, rounded up and never under what was paid", function()
    GC.VendorBuys.OnBuy(2, 1, 100)
    bag[3371] = 1
    GC.VendorBuys.OnBagsChanged(101)
    assert.equal(2, vendorLots()[1].originalTotal)
  end)

  it("books once however many bag updates follow", function()
    GC.VendorBuys.OnBuy(1, 5, 100)
    bag[2320] = 5
    GC.VendorBuys.OnBagsChanged(101)
    GC.VendorBuys.OnBagsChanged(102)
    GC.VendorBuys.OnBagsChanged(103)
    assert.equal(1, #vendorLots())
    assert.equal(50, vendorLots()[1].originalTotal)
    assert.equal(0, GC.VendorBuys.Pending())
  end)

  it("books the call the BUY vendor button made once, carrying its list", function()
    -- The panel tags the call and the hook sees the same call: one lot, not two.
    GC.VendorBuys.Tag("run-1")
    GC.VendorBuys.OnBuy(1, 20, 100)
    bag[2320] = 20
    GC.VendorBuys.OnBagsChanged(101)
    assert.equal(1, #vendorLots())
    assert.equal("run-1", vendorLots()[1].runCode)
    -- the tag was spent: a later click on the merchant's own window carries none
    GC.VendorBuys.OnBuy(1, 1, 200)
    bag[2320] = 21
    GC.VendorBuys.OnBagsChanged(201)
    assert.is_nil(vendorLots()[2].runCode)
  end)

  it("does not let a tag outlive a call that booked nothing", function()
    GC.VendorBuys.Tag("run-1")
    GC.VendorBuys.OnBuy(3, 1, 100)             -- an item bought with tokens: not a gold purchase
    GC.VendorBuys.OnBuy(1, 1, 101)
    bag[2320] = 1
    GC.VendorBuys.OnBagsChanged(102)
    assert.is_nil(vendorLots()[1].runCode)
  end)

  it("ignores purchases that cost something other than gold", function()
    GC.VendorBuys.OnBuy(3, 1, 100)
    assert.equal(0, GC.VendorBuys.Pending())
  end)

  it("never books more than the call asked for when other loot of the item lands too", function()
    GC.VendorBuys.OnBuy(1, 3, 100)
    bag[2320] = 10                             -- 3 bought, 7 looted meanwhile
    GC.VendorBuys.OnBagsChanged(101)
    assert.equal(3, vendorLots()[1].originalQty)
    assert.equal(30, vendorLots()[1].originalTotal)
  end)

  it("pools two calls made before the bags moved and books what arrives", function()
    GC.VendorBuys.OnBuy(1, 20, 100)
    GC.VendorBuys.OnBuy(1, 5, 100)
    bag[2320] = 25
    GC.VendorBuys.OnBagsChanged(101)
    assert.equal(1, #vendorLots())
    assert.equal(25, vendorLots()[1].originalQty)
    assert.equal(250, vendorLots()[1].originalTotal)
  end)

  it("books a partial arrival at its share and gives up on the rest after a while", function()
    GC.VendorBuys.OnBuy(1, 10, 100)
    bag[2320] = 4
    GC.VendorBuys.OnBagsChanged(101)
    assert.equal(40, vendorLots()[1].originalTotal)
    assert.equal(1, GC.VendorBuys.Pending())
    GC.VendorBuys.OnBagsChanged(100 + GC.VendorBuys.EXPIRE_SECONDS + 1)
    assert.equal(0, GC.VendorBuys.Pending())
    assert.equal(1, #vendorLots())
  end)

  it("treats a call with no quantity as one stack", function()
    GC.VendorBuys.OnBuy(2, nil, 100)
    bag[3371] = 4
    GC.VendorBuys.OnBagsChanged(101)
    assert.equal(4, vendorLots()[1].originalQty)
    assert.equal(8, vendorLots()[1].originalTotal)
  end)

  it("files a non-stackable item keyless, to be keyed at the auction house", function()
    shelf[3].hasExtendedCost = false
    GC.VendorBuys.OnBuy(3, 1, 100)
    bag[4000] = 1
    GC.VendorBuys.OnBagsChanged(101)
    assert.is_nil(vendorLots()[1].positionKey)
  end)

  it("hooks BuyMerchantItem as a post-hook when the client has one", function()
    local hooked
    _G.BuyMerchantItem = function() end
    _G.hooksecurefunc = function(name, fn) hooked = { name = name, fn = fn } end
    GC.VendorBuys.Install()
    _G.hooksecurefunc, _G.BuyMerchantItem = nil, nil
    assert.equal("BuyMerchantItem", hooked.name)
    hooked.fn(1, 2)
    assert.equal(1, GC.VendorBuys.Pending())
  end)
end)

describe("AppRuns.VendorUnitFor", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/AppRuns.lua", {})
    GC.db = { runs = {
      old = { code = "old", updatedAt = 10, lines = { { i = 2320, q = 1, v = true, vu = 9 } } },
      new = { code = "new", updatedAt = 20, lines = {
        { i = 2320, q = 1, v = true, vu = 10 },
        { i = 500, q = 1, v = false, vu = 77 },              -- a ceiling for the AH, not a vendor stop
        { i = 600, q = 1, cr = { i = { { i = 3371, q = 1, v = true, vu = 2 } } } },
      } },
    } }
  end)

  it("answers the newest list's vendor price for a vendor stop", function()
    assert.equal(10, GC.AppRuns.VendorUnitFor(2320))
  end)

  it("reads a vendor reagent of an attached recipe", function()
    assert.equal(2, GC.AppRuns.VendorUnitFor(3371))
  end)

  it("answers nil for a line that is not a vendor stop, or an unknown item", function()
    assert.is_nil(GC.AppRuns.VendorUnitFor(500))
    assert.is_nil(GC.AppRuns.VendorUnitFor(12345))
  end)
end)
