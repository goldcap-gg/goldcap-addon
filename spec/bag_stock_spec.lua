local helper = require("spec.spec_helper")

describe("BagStock", function()
  local GC

  -- Two bags. Each slot is { itemID, stackCount, [flags] }; a nil slot is empty.
  local function driverFor(bags, classify)
    return {
      numSlots = function(bag) return #(bags[bag] or {}) end,
      itemInfo = function(bag, slot)
        local entry = (bags[bag] or {})[slot]
        if not entry or entry == false then return nil end
        return entry
      end,
      classify = classify or function(itemID)
        return ("commodity:%d"):format(itemID), true
      end,
    }
  end

  before_each(function() GC = helper.loadModule("Core/BagStock.lua", {}) end)

  it("adds up one item across every bag and slot holding it", function()
    local stock = GC.BagStock.Scan(driverFor({
      [0] = { { itemID = 42, stackCount = 200 }, { itemID = 7, stackCount = 3 } },
      [1] = { { itemID = 42, stackCount = 46 } },
    }), { 0, 1 })
    assert.equal(2, #stock)
    local byKey = {}
    for _, entry in ipairs(stock) do byKey[entry.positionKey] = entry end
    assert.equal(246, byKey["commodity:42"].quantity)
    assert.equal(2, #byKey["commodity:42"].stacks)
    assert.equal(3, byKey["commodity:7"].quantity)
  end)

  it("leaves out what the auction house would refuse", function()
    -- Soulbound is a hard refusal at the auction house, so offering it would be a lie
    -- the player only finds out about on click. An empty stack is not stock at all.
    local stock = GC.BagStock.Scan(driverFor({
      [0] = {
        { itemID = 1, stackCount = 1, isBound = true },
        { itemID = 3, stackCount = 0 },
        { itemID = 4, stackCount = 1 },
      },
    }), { 0 })
    assert.equal(1, #stock)
    assert.equal(4, stock[1].itemID)
  end)

  it("keeps stock the vendor will not buy but the auction house will", function()
    -- `hasNoValue` is "no VENDOR sell price", which says nothing about the auction
    -- house. Reading it as a refusal hid a client's whole reagent inventory: a live
    -- bag dump had 322 Venomous Combatant's Heraldry, 850 Gloom Dust and 38 Greater
    -- Eternal Essence -- every one of them hasNoValue, bindType 0, isCommodity true,
    -- and every one of them missing from the Sell tab, which reported "not on hand"
    -- over a stack the Blizzard sell frame was offering to post.
    local stock = GC.BagStock.Scan(driverFor({
      [0] = {
        { itemID = 275380, stackCount = 322, hasNoValue = true },
        { itemID = 152875, stackCount = 850, hasNoValue = true, isBound = false },
      },
    }), { 0 })
    assert.equal(2, #stock)
    local byKey = {}
    for _, entry in ipairs(stock) do byKey[entry.positionKey] = entry end
    assert.equal(322, byKey["commodity:275380"].quantity)
    assert.equal(850, byKey["commodity:152875"].quantity)
  end)

  it("still refuses a soulbound item that is also vendor-worthless", function()
    -- The two flags travel together on most soulbound reagents (the same live dump had
    -- 118 of them), so dropping the hasNoValue test must not weaken the bind test.
    local stock = GC.BagStock.Scan(driverFor({
      [0] = { { itemID = 210814, stackCount = 190, isBound = true, hasNoValue = true } },
    }), { 0 })
    assert.equal(0, #stock)
  end)

  it("leaves out an item whose auction identity cannot be derived", function()
    -- A bonus-id bearing link has no exact position key. Filing it under a guessed
    -- one is what split a single item into two positions -- the purchase holding
    -- no listings and the listing holding no cost.
    local stock = GC.BagStock.Scan(driverFor({
      [0] = { { itemID = 9, stackCount = 1 }, { itemID = 10, stackCount = 1 } },
    }, function(itemID)
      if itemID == 9 then return nil, nil end
      return ("commodity:%d"):format(itemID), true
    end), { 0 })
    assert.equal(1, #stock)
    assert.equal(10, stock[1].itemID)
  end)

  it("drops a position whose total cannot be stated exactly", function()
    local huge = 9007199254740991
    local stock = GC.BagStock.Scan(driverFor({
      [0] = { { itemID = 5, stackCount = huge }, { itemID = 5, stackCount = huge } },
    }), { 0 })
    assert.equal(0, #stock)
  end)

  it("returns positions in a stable order", function()
    local first = GC.BagStock.Scan(driverFor({
      [0] = { { itemID = 9, stackCount = 1 }, { itemID = 2, stackCount = 1 }, { itemID = 5, stackCount = 1 } },
    }), { 0 })
    local second = GC.BagStock.Scan(driverFor({
      [0] = { { itemID = 5, stackCount = 1 }, { itemID = 9, stackCount = 1 }, { itemID = 2, stackCount = 1 } },
    }), { 0 })
    local function keys(stock)
      local out = {}
      for i, entry in ipairs(stock) do out[i] = entry.positionKey end
      return out
    end
    assert.same(keys(first), keys(second))
  end)

  describe("PostableQuantity", function()
    it("aggregates a commodity across stacks", function()
      assert.equal(246, GC.BagStock.PostableQuantity({ isCommodity = true, quantity = 246,
        stacks = { { quantity = 200 }, { quantity = 46 } } }))
    end)

    it("gives a normal item its largest single stack", function()
      -- PostItem pins ONE ItemLocation, and GoldCap only ever posts a quantity it
      -- has proven sits in the slot it pinned.
      assert.equal(12, GC.BagStock.PostableQuantity({ isCommodity = false, quantity = 19,
        stacks = { { quantity = 7 }, { quantity = 12 } } }))
    end)
  end)

  it("survives a driver that is missing pieces rather than erroring mid-walk", function()
    assert.same({}, GC.BagStock.Scan(nil, { 0 }))
    assert.same({}, GC.BagStock.Scan({ numSlots = function() return 1 end }, { 0 }))
  end)

  -- The stack's exact identity is a property of the stack (its own ItemLocation), so classify is
  -- told where it is; and what nothing could key is handed back, never dropped.
  it("hands classify the slot, carries its quote key, and returns what it could not key", function()
    local asked = {}
    local stock, waiting = GC.BagStock.Scan({
      numSlots = function(bag) return bag == 0 and 3 or 0 end,
      itemInfo = function(_, slot)
        return ({ { itemID = 7, stackCount = 1, itemName = "Helm" },
          { itemID = 8, stackCount = 2, itemName = "Jeb's Underwear" },
          { itemID = 8, stackCount = 1, itemName = "Jeb's Underwear", isBound = true } })[slot]
      end,
      classify = function(itemID, _, bag, slot)
        asked[#asked + 1] = bag .. ":" .. slot
        if itemID == 7 then return "item:7:619:0:0", false, "item:7:619:0:0" end
        return nil, nil
      end,
    }, { 0 })
    assert.same({ "0:1", "0:2" }, asked) -- the bound stack is never classified
    assert.equal(1, #stock)
    assert.equal("item:7:619:0:0", stock[1].quoteKey)
    assert.same({ { itemID = 8, itemName = "Jeb's Underwear", quantity = 2 } }, waiting)
  end)

  -- Every caged pet is item 82800: two waiting pets are two lines, not one named after the first.
  it("keeps two different waiting pets apart", function()
    local _, waiting = GC.BagStock.Scan({
      numSlots = function(bag) return bag == 0 and 2 or 0 end,
      itemInfo = function(_, slot)
        return ({ { itemID = 82800, stackCount = 1, itemName = "Mechanical Squirrel" },
          { itemID = 82800, stackCount = 1, itemName = "Tiny Snowman" } })[slot]
      end,
      classify = function() return nil, nil end,
    }, { 0 })
    assert.equal(2, #waiting)
  end)
end)
