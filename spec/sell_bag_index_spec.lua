local helper = require("spec.spec_helper")

-- The per-pass bag snapshot (GC.Sell._BagSnapshot) must answer exactly what the live full scan
-- answers, for every kind of position; both go through liveBagState (GC.Sell._LiveBagState).
describe("Sell tab bag snapshot", function()
  local GC, bags, slotKeys, infoCalls

  local function region()
    local v = setmetatable({}, { __index = function() return function() end end })
    return v
  end

  -- Field 14 is the bonus-ID count: a bonus-ID link cannot be keyed from the link, so the slot's own
  -- ItemKey (GetItemKeyFromItem) decides, which is the path a modern gear stack takes.
  local PLAIN = "item:%d:0::0:0:0:0:0:0:0:0:0:2:6652:1520"

  before_each(function()
    bags, slotKeys, infoCalls = { [0] = {}, [1] = {} }, {}, 0
    _G.time = function() return 1000 end
    _G.CreateFrame = function() return region() end
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return #(bags[bag] or {}) end,
      -- A fresh table per call, as the client hands it out.
      GetContainerItemInfo = function(bag, slot)
        infoCalls = infoCalls + 1
        local held = (bags[bag] or {})[slot]
        if not held then return nil end
        return { itemID = held.itemID, stackCount = held.stackCount, isBound = held.isBound,
          hyperlink = held.hyperlink }
      end,
      GetContainerItemLink = function(bag, slot) return ((bags[bag] or {})[slot] or {}).hyperlink end,
    }
    _G.C_Item = { GetDetailedItemLevelInfo = function() return 100 end }
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_AuctionHouse = {
      GetItemKeyFromItem = function(location) return slotKeys[location.bag .. ":" .. location.slot] end,
    }
    GC = { Sell = {}, Theme = { color = {}, pad = {} } }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    helper.loadSell(GC)
  end)

  after_each(function()
    _G.time, _G.CreateFrame = os.time, nil
    _G.C_Container, _G.C_AuctionHouse, _G.C_Item, _G.ItemLocation = nil, nil, nil, nil
  end)

  local function put(bag, slot, itemID, count, over)
    local held = { itemID = itemID, stackCount = count, hyperlink = PLAIN:format(itemID) }
    for k, v in pairs(over or {}) do held[k] = v end
    bags[bag][slot] = held
  end

  local function key(itemID, level) return { itemID = itemID, itemLevel = level, itemSuffix = 0, battlePetSpeciesID = 0 } end

  -- The live scan first, then the snapshot; identical tables or the test fails.
  local function both(position, requiredQty)
    local full = GC.Sell._LiveBagState(position, requiredQty)
    local indexed = GC.Sell._LiveBagState(position, requiredQty, GC.Sell._BagSnapshot())
    assert.same(full, indexed)
    return indexed
  end

  it("aggregates a commodity across stacks, skipping a bound copy and other items", function()
    put(0, 1, 42, 20); put(0, 2, 99, 7); put(0, 3, 42, 200, { isBound = true }); put(1, 1, 42, 5)
    local state = both({ itemID = 42, positionKey = "commodity:42" })
    assert.equal(25, state.exactQty)
    assert.equal(0, state.bag); assert.equal(1, state.slot); assert.equal(20, state.stackQty)
    assert.is_nil(state.hyperlink, "a commodity match carries no hyperlink")
  end)

  it("answers zero and no slot for an item that is not in the bags, or only bound", function()
    put(0, 1, 42, 20, { isBound = true })
    local state = both({ itemID = 42, positionKey = "commodity:42" })
    assert.equal(0, state.exactQty)
    assert.is_nil(state.bag); assert.is_nil(state.positionKey)
    state = both({ itemID = 7, positionKey = "item:7:100:0:0" })
    assert.equal(0, state.exactQty)
  end)

  it("gives up on an overflowing commodity total exactly as the scan does", function()
    put(0, 1, 42, 9007199254740991); put(0, 2, 42, 5)
    local state = both({ itemID = 42, positionKey = "commodity:42" })
    assert.is_nil(state.exactQty)
  end)

  it("treats a commodity stack of zero as the scan does", function()
    put(0, 1, 42, 0); put(0, 2, 42, 4)
    both({ itemID = 42, positionKey = "commodity:42" })
  end)

  it("pins a single non-commodity stack by its own ItemKey, with its hyperlink", function()
    put(0, 1, 222, 1); put(0, 2, 222, 1)
    slotKeys["0:1"], slotKeys["0:2"] = key(222, 619), key(222, 626)
    local state = both({ itemID = 222, positionKey = "item:222:626:0:0" })
    assert.equal(2, state.slot)
    assert.equal(1, state.exactQty)
    assert.equal(PLAIN:format(222), state.hyperlink)
  end)

  it("skips a bound twin that shares the ItemKey", function()
    put(0, 1, 222, 1, { isBound = true }); put(0, 2, 222, 1)
    slotKeys["0:1"], slotKeys["0:2"] = key(222, 619), key(222, 619)
    local state = both({ itemID = 222, positionKey = "item:222:619:0:0" })
    assert.equal(2, state.slot)
  end)

  it("picks the largest split stack, and the first big enough for a required quantity", function()
    put(0, 1, 222, 3); put(0, 2, 222, 5); put(1, 1, 222, 5); put(1, 2, 222, 4)
    for _, slot in ipairs({ "0:1", "0:2", "1:1", "1:2" }) do slotKeys[slot] = key(222, 619) end
    local position = { itemID = 222, positionKey = "item:222:619:0:0" }
    local largest = both(position)
    assert.equal(5, largest.stackQty)
    assert.equal(1, largest.bag); assert.equal(1, largest.slot) -- ties go to the later stack
    local four = both(position, 4)
    assert.equal(0, four.bag); assert.equal(2, four.slot)
    local three = both(position, 3)
    assert.equal(0, three.bag); assert.equal(1, three.slot)
    local nine = both(position, 9)
    assert.is_nil(nine.bag); assert.is_nil(nine.positionKey)
    assert.equal(5, nine.exactQty)
  end)

  it("reads only the wanted item's slots once the snapshot is built", function()
    for slot = 1, 30 do put(0, slot, 1000 + slot, 1) end
    put(1, 1, 42, 9)
    local snapshot = GC.Sell._BagSnapshot()
    assert.equal(31, infoCalls, "one read per slot to build it")
    infoCalls = 0
    for _ = 1, 20 do GC.Sell._LiveBagState({ itemID = 42, positionKey = "commodity:42" }, nil, snapshot) end
    assert.equal(0, infoCalls)
    GC.Sell._LiveBagState({ itemID = 42, positionKey = "commodity:42" })
    assert.equal(31, infoCalls, "without a snapshot the live bags are scanned")
  end)

  it("never lets an old snapshot answer a call that was not handed it", function()
    put(0, 1, 42, 9)
    local stale = GC.Sell._BagSnapshot()
    bags[0][1].stackCount = 3
    local position = { itemID = 42, positionKey = "commodity:42" }
    assert.equal(9, GC.Sell._LiveBagState(position, nil, stale).exactQty)
    assert.equal(3, GC.Sell._LiveBagState(position).exactQty, "a click-path read is live")
  end)

  it("OnBagsChanged reads the bags afresh each pass, and reads none when the tab is hidden", function()
    put(0, 1, 42, 9)
    local shown = false
    GC.Sniper = { IsWindowShown = function() return shown end }
    GC.Sell.OnBagsChanged()
    assert.equal(0, infoCalls, "hidden tab: early return builds nothing")
    shown = true
    GC.Sell.OnBagsChanged() -- no positions yet: the pass still ends cleanly
    bags[0][1].stackCount = 3
    assert.equal(3, GC.Sell._LiveBagState({ itemID = 42, positionKey = "commodity:42" }).exactQty)
  end)
end)
