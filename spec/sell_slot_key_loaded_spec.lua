local helper = require("spec.spec_helper")

-- WoW: Forever drops item data for a moment on every price refresh: a SELL probe (10.11) read 32 to
-- 37 of 44 stacks uncached, and in that moment a gear stack's item level read 0, so the cloak's
-- row "item:4658:8:0:0" became "item:4658:0:0:0", took another place in the list and its name
-- with it ("Item 4658"), and came back a fraction of a second later. A key is only read from a
-- stack whose data the client holds; meanwhile the slot keeps the key it last read loaded.
describe("GC.Sell._SlotKey while the client has dropped the item's data", function()
  local GC, loaded, level

  -- No bonus IDs (field 14 is 0): the link alone keys it, with the level the client reads.
  local function link(itemID) return ("item:%d:0:0:0:0:0:0:0:0:0:0:0:0"):format(itemID) end

  before_each(function()
    loaded, level = { value = true }, { value = 8 }
    _G.C_Item = {
      GetDetailedItemLevelInfo = function() return level.value end,
      IsItemDataCached = function() return loaded.value end,
    }
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_AuctionHouse = {
      GetItemKeyFromItem = function() return { itemID = 4658, itemLevel = level.value, itemSuffix = 0 } end,
    }
    GC = { Sell = {}, Theme = { color = {}, pad = {} } }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadSell(GC)
  end)

  after_each(function() _G.C_Item, _G.ItemLocation, _G.C_AuctionHouse = nil, nil, nil end)

  it("keeps the key it read loaded while the data is gone, and its level-0 read is not used", function()
    assert.equal("item:4658:8:0:0", (GC.Sell._SlotKey(4658, link(4658), 0, 1)))
    loaded.value, level.value = false, 0
    assert.equal("item:4658:8:0:0", (GC.Sell._SlotKey(4658, link(4658), 0, 1)))
    loaded.value, level.value = true, 8
    assert.equal("item:4658:8:0:0", (GC.Sell._SlotKey(4658, link(4658), 0, 1)))
  end)

  it("gives a stack never read loaded no key yet, rather than one with level 0", function()
    loaded.value, level.value = false, 0
    assert.is_nil((GC.Sell._SlotKey(4658, link(4658), 0, 1)))
  end)

  it("does not hand the slot's key to another item put in that slot", function()
    assert.equal("item:4658:8:0:0", (GC.Sell._SlotKey(4658, link(4658), 0, 1)))
    loaded.value, level.value = false, 0
    assert.is_nil((GC.Sell._SlotKey(805, link(805), 0, 1)))
  end)

  it("keeps a gear stack keyed by the auction house's ItemKey the same way", function()
    local bonus = "item:4658:0:0:0:0:0:0:0:0:0:0:0:2:6652:1520"
    assert.equal("item:4658:8:0:0", (GC.Sell._SlotKey(4658, bonus, 1, 3)))
    loaded.value, level.value = false, 0
    assert.equal("item:4658:8:0:0", (GC.Sell._SlotKey(4658, bonus, 1, 3)))
  end)
end)
