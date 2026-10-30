local helper = require("spec.spec_helper")

-- Services/VendorBags.lua reads the client's bags into the shape Core/VendorSelect.lua takes.
-- The fakes carry the fields the real APIs have (ContainerDocumentation.lua: ContainerItemInfo,
-- ItemPurchaseInfo; EquipmentManagerDocumentation.lua; TooltipInfoDocumentation.lua; the
-- EquipmentManager_GetLocationData result), checked with wowsrc.py on live 12.1.5 and forever.
describe("VendorBags", function()
  local GC, B, saved, bags, items, flags, purchase, refundable, sets, setsFail, tooltips, tipReads, errors
  local infoAsked, levels, clock, uncached
  local KEYS = { "C_Container", "C_Item", "C_EquipmentSet", "EquipmentManager_GetLocationData",
    "C_TooltipInfo", "Enum", "ItemLocation", "BIND_TRADE_TIME_REMAINING", "GetTime" }

  local function put(bag, slot, id, over)
    local info = { iconFileID = 1, stackCount = 1, isLocked = false, quality = 0, isReadable = false,
      hasLoot = false, hyperlink = "|Hitem:" .. id .. "|h", isFiltered = false, hasNoValue = false,
      itemID = id, isBound = false, itemName = "Item " .. id }
    for k, v in pairs(over or {}) do info[k] = v end
    bags[bag] = bags[bag] or {}
    bags[bag][slot] = info
  end

  local function boom(name) if errors[name] then error(name .. " failed") end end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    bags, items, flags, purchase, refundable, sets, setsFail, tooltips, errors = {}, {}, {}, {}, {}, {}, false, {}, {}
    tipReads, infoAsked, levels, clock, uncached = 0, {}, {}, 1000, {}
    _G.GetTime = function() return clock end
    _G.Enum = { BagSlotFlags = { ExcludeJunkSell = 64 } }
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) boom("numSlots"); return bags[bag] and 4 or 0 end,
      GetContainerItemInfo = function(bag, slot) boom("info"); return bags[bag] and bags[bag][slot] or nil end,
      GetContainerItemPurchaseInfo = function(bag, slot)
        boom("purchase")
        return purchase[bag .. ":" .. slot]
      end,
      GetBagSlotFlag = function(bag, flag)
        boom("flag")
        return flag == 64 and flags[bag] == true
      end,
      GetBackpackSellJunkDisabled = function() boom("backpack"); return flags[0] == true end,
    }
    -- C_Item.GetItemInfo(itemInfo) takes an id or a link; a link the fake has no answer of its own
    -- for answers as its item (the client's answer for an unscaled link).
    _G.C_Item = {
      GetItemInfo = function(id)
        boom("itemInfo")
        infoAsked[#infoAsked + 1] = id
        local it = items[id]
        if not it and type(id) == "string" then it = items[tonumber(id:match("item:(%d+)"))] end
        if not it then return nil end
        return "Item " .. id, "link", it.quality or 0, 1, 1, "t", "s", 20, it.equip or "", 1, it.sell, it.class or 15, it.subclass or 0, 0, it.expansion or 0, nil, it.reagent == true
      end,
      CanBeRefunded = function(loc) boom("refund"); return refundable[loc.bag .. ":" .. loc.slot] == true end,
      -- ItemDocumentation.lua: IsItemDataCached(itemLocation), live and forever.
      IsItemDataCached = function(loc) return not uncached[loc.bag .. ":" .. loc.slot] end,
      -- ItemDocumentation.lua: actualItemLevel, previewLevel, sparseItemLevel; MayReturnNothing.
      GetDetailedItemLevelInfo = function(link)
        local level = levels[link]
        if level then return level, false, level end
      end,
    }
    _G.C_EquipmentSet = {
      GetEquipmentSetIDs = function() boom("setIDs"); return setsFail and error("x") or { 1 } end,
      GetItemLocations = function(id) boom("setLocs"); return sets[id] or {} end,
    }
    -- The real function decodes bit fields of a number; the fake uses its own number scheme.
    _G.EquipmentManager_GetLocationData = function(loc)
      if loc < 0 then return {} end
      if loc < 100 then return { isPlayer = true, isBank = false, isBags = false, slot = loc } end
      return { isPlayer = false, isBank = false, isBags = true, bag = math.floor((loc - 100) / 20), slot = (loc - 100) % 20 }
    end
    _G.C_TooltipInfo = { GetBagItem = function(bag, slot)
      tipReads = tipReads + 1
      boom("tooltip")
      return tooltips[bag .. ":" .. slot]
    end }
    _G.BIND_TRADE_TIME_REMAINING = "You may trade this item with players that were also eligible to loot this item for the next %s."
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/ForeverValue.lua", GC)
    GC.db = { sellMarks = {} }
    GC.Sell = { _SlotKey = function(id, _, bag, slot) return "pos:" .. id .. ":" .. bag .. ":" .. slot end }
    helper.loadModule("Services/VendorBags.lua", GC)
    B = GC.VendorBags
  end)

  after_each(function() for _, k in ipairs(KEYS) do _G[k] = saved[k] end end)

  local function one()
    local out = B.Read(function(id) return id == 50 and { mv = 400, source = "region", at = 1700000000 } or nil end)
    return out[1], out
  end

  it("reads a stack with its vendor price, quality and the auction house figure, its source and time", function()
    put(1, 2, 50, { stackCount = 7, quality = 2, isBound = true, isLocked = true, hasNoValue = true })
    items[50] = { quality = 2, sell = 40, class = 4, subclass = 1, equip = "INVTYPE_CHEST", expansion = 10, reagent = true }
    tooltips["1:2"] = { lines = { { leftText = "Soulbound" } } }
    local s = one()
    assert.same({
      bag = 1, slot = 2, itemID = 50, link = "|Hitem:50|h", count = 7, quality = 2, vendorUnit = 40,
      ahUnit = 400, ahSource = "region", ahAt = 1700000000, hasNoValue = true, isLocked = true,
      isBound = true, isGear = true, isReagent = true, refundable = false, tradeTimer = false,
      inSet = false, excludedBag = false, selling = false,
      classID = 4, subclassID = 1, equipLoc = "INVTYPE_CHEST", expansion = 10,
    }, s)
  end)

  -- Gear sells by its own item level and bonuses: C_Item.GetItemInfo with the stack's hyperlink
  -- answers that price (61g for an item level 198 axe whose base item sells for 2g, the owner's
  -- screenshot 2026-10-26); a link with no bonuses answers its item's base price.
  it("reads a stack's vendor price from its own link", function()
    local link = "|Hitem:60::::::::90:::2:10354:1:|h[Axe]|h"
    put(0, 1, 60, { hyperlink = link, quality = 3 })
    items[60] = { sell = 20000, class = 2 }
    items[link] = { sell = 610411, class = 2 }
    put(0, 2, 61, { hyperlink = "|Hitem:61::::::::90:::1:999:1:|h[Mace]|h", quality = 3 })
    items[61] = { sell = 500, class = 2 }
    local out = B.Read()
    assert.equal(610411, out[1].vendorUnit)
    assert.equal(500, out[2].vendorUnit)
  end)

  it("marks a refundable stack from either source", function()
    put(0, 1, 50); put(0, 2, 51)
    items[50], items[51] = { sell = 5 }, { sell = 5 }
    purchase["0:1"] = { money = 0, itemCount = 1, refundSeconds = 600, currencyCount = 0, hasEnchants = false }
    refundable["0:2"] = true
    local out = B.Read()
    assert.is_true(out[1].refundable)
    assert.is_true(out[2].refundable)
  end)

  it("marks the backpack excluded through GetBackpackSellJunkDisabled and other bags through the slot flag", function()
    put(0, 1, 50); put(2, 1, 51); put(3, 1, 52)
    for _, id in ipairs({ 50, 51, 52 }) do items[id] = { sell = 5 } end
    flags[0], flags[2] = true, true
    local out = B.Read()
    assert.is_true(out[1].excludedBag)
    assert.is_true(out[2].excludedBag)
    assert.is_false(out[3].excludedBag)
  end)

  it("marks a stack in an equipment set", function()
    put(0, 1, 50, { quality = 2 }); put(0, 2, 51, { quality = 2 })
    items[50], items[51] = { sell = 5, class = 4 }, { sell = 5, class = 4 }
    sets[1] = { 0, 1, nil, 101 } -- empty, ignored, a hole, bag 0 slot 1
    local out = B.Read()
    assert.is_true(out[1].inSet)
    assert.is_false(out[2].inSet)
  end)

  it("treats every gear stack as in a set when the set API fails", function()
    put(0, 1, 50); put(0, 2, 51)
    items[50], items[51] = { sell = 5, class = 2 }, { sell = 5, class = 15 }
    errors.setIDs = true
    local out = B.Read()
    assert.is_true(out[1].inSet)
    assert.is_false(out[2].inSet)
    _G.C_EquipmentSet = nil
    out = B.Read()
    assert.is_true(out[1].inSet)
    assert.is_false(out[2].inSet)
  end)

  -- Profession tools and accessories (Enum.ItemClass.Profession = 19, live
  -- ItemConstantsDocumentation.lua) come in ranks under one id, like weapons and armor, so their
  -- auction house figure is the cheapest rank's: gear, never sold by the value rule, and in a set
  -- when the set API cannot say.
  -- One C_Item.GetItemInfo a stack, by its link: the class fields, the expansion and the link's
  -- own (scaled) sell price all come from that one answer (the code review, 2026-10-27).
  it("asks C_Item.GetItemInfo once a stack, by its link", function()
    local link = "|Hitem:60::::::::90:::2:10354:1:|h[Axe]|h"
    put(0, 1, 60, { hyperlink = link, quality = 3 }); put(0, 2, 61, { quality = 1 })
    items[link] = { sell = 610411, class = 2, subclass = 7, equip = "INVTYPE_WEAPON", expansion = 10 }
    items[61] = { sell = 5, class = 7 }
    local out = B.Read()
    assert.same({ link, "|Hitem:61|h" }, infoAsked)
    assert.same({ 2, 7, "INVTYPE_WEAPON", 10, 610411 },
      { out[1].classID, out[1].subclassID, out[1].equipLoc, out[1].expansion, out[1].vendorUnit })
    assert.equal(7, out[2].classID)
  end)

  -- What disenchanting gear of an expansion before Dragonflight gives depends on its item level
  -- (Core/Disenchant.lua's KindOf): the stack carries it, read for such gear only.
  it("reads the item level of gear from before Dragonflight, and of nothing else", function()
    put(0, 1, 70, { quality = 3, hyperlink = "|Hitem:70|h" })
    put(0, 2, 71, { quality = 3, hyperlink = "|Hitem:71|h" })
    put(0, 3, 72, { quality = 1, hyperlink = "|Hitem:72|h" })
    items[70] = { class = 4, expansion = 7, sell = 5 }
    items[71] = { class = 2, expansion = 9, sell = 5 }
    items[72] = { class = 7, expansion = 7, sell = 5 }
    levels["|Hitem:70|h"], levels["|Hitem:71|h"], levels["|Hitem:72|h"] = 342, 400, 50
    local out = B.Read()
    assert.equal(342, out[1].itemLevel)
    assert.is_nil(out[2].itemLevel)
    assert.is_nil(out[3].itemLevel)
  end)

  it("counts profession equipment as gear", function()
    put(0, 1, 50, { quality = 2 }); put(0, 2, 51, { quality = 2 })
    items[50], items[51] = { sell = 5, class = 19 }, { sell = 5, class = 15 }
    local out = B.Read()
    assert.is_true(out[1].isGear)
    assert.is_false(out[2].isGear)
    errors.setIDs = true
    out = B.Read()
    assert.is_true(out[1].inSet)
    assert.is_false(out[2].inSet)
  end)

  describe("trade timer", function()
    it("marks a bound grey stack with the trade timer line", function()
      put(0, 1, 50, { isBound = true }); put(0, 2, 51, { isBound = true })
      items[50], items[51] = { sell = 5 }, { sell = 5 }
      tooltips["0:1"] = { lines = { { leftText = "Item 50" }, { leftText = "You may trade this item with players that were also eligible to loot this item for the next 1 hour." } } }
      tooltips["0:2"] = { lines = { { leftText = "Item 51" }, { leftText = "Soulbound" } } }
      local out = B.Read()
      assert.is_true(out[1].tradeTimer)
      assert.is_false(out[2].tradeTimer)
    end)

    it("fails closed when the tooltip API or the client string is missing", function()
      put(0, 1, 50, { isBound = true })
      items[50] = { sell = 5 }
      _G.C_TooltipInfo = nil
      assert.is_true((one()).tradeTimer)
      _G.C_TooltipInfo = { GetBagItem = function() return nil end }
      assert.is_true((one()).tradeTimer)
      _G.C_TooltipInfo = { GetBagItem = function() return { lines = {} } end }
      _G.BIND_TRADE_TIME_REMAINING = nil
      assert.is_true((one()).tradeTimer)
    end)

    it("never reads a tooltip for an unbound stack, or a bound one that is neither grey nor gear", function()
      put(0, 1, 50, { isBound = false }); put(0, 2, 51, { isBound = true, quality = 1 })
      put(0, 3, 52, { isBound = false, quality = 2 })
      items[50], items[51] = { sell = 5 }, { sell = 5 }
      items[52] = { sell = 5, class = 4 }
      B.Read()
      assert.equal(0, tipReads)
    end)

    it("marks bound epic gear with the trade timer line, and not without it", function()
      put(0, 1, 50, { isBound = true, quality = 4 }); put(0, 2, 51, { isBound = true, quality = 4 })
      items[50], items[51] = { quality = 4, class = 2 }, { quality = 4, class = 2 }
      tooltips["0:1"] = { lines = { { leftText = "You may trade this item with players that were also eligible to loot this item for the next 1 hour." } } }
      tooltips["0:2"] = { lines = { { leftText = "Soulbound" } } }
      local out = B.Read()
      assert.is_true(out[1].tradeTimer)
      assert.is_false(out[2].tradeTimer)
      assert.equal(2, tipReads)
    end)

    -- By the item's own GUID (the code review, 2026-10-27): an item read without a trade timer
    -- never gets one, so its tooltip is read once; one with a timer is read again after
    -- TRADE_RECHECK seconds; gear without a GUID, and grey junk, are read on every pass.
    it("reads a gear item's trade timer once when it has none, and again a minute later while it has one", function()
      _G.C_Item.GetItemGUID = function(loc) return loc.slot <= 2 and ("Item-" .. loc.slot) or nil end
      put(0, 1, 50, { isBound = true, quality = 4 }); put(0, 2, 51, { isBound = true, quality = 4 })
      put(0, 3, 52, { isBound = true, quality = 4 }); put(0, 4, 53, { isBound = true })
      items[50], items[51], items[52], items[53] = { class = 2 }, { class = 2 }, { class = 2 }, { sell = 5 }
      local timer = { leftText = "You may trade this item with players that were also eligible to loot this item for the next 1 hour." }
      tooltips["0:1"] = { lines = { { leftText = "Item 50" }, { leftText = "Soulbound" } } }
      tooltips["0:2"] = { lines = { { leftText = "Item 51" }, { leftText = "Soulbound" }, timer } }
      tooltips["0:3"] = { lines = { { leftText = "Item 52" }, { leftText = "Soulbound" } } }
      tooltips["0:4"] = { lines = { { leftText = "Item 53" }, { leftText = "Soulbound" } } }
      B.Read()
      assert.equal(4, tipReads)
      clock = clock + 30
      local out = B.Read()
      assert.equal(6, tipReads)
      assert.same({ false, true, false, false },
        { out[1].tradeTimer, out[2].tradeTimer, out[3].tradeTimer, out[4].tradeTimer })
      clock = clock + B.TRADE_RECHECK
      tooltips["0:2"] = { lines = { { leftText = "Item 51" }, { leftText = "Soulbound" } } }
      out = B.Read()
      assert.equal(9, tipReads)
      assert.is_false(out[2].tradeTimer)
      B.Read()
      assert.equal(11, tipReads)
    end)

    -- A wrong "no timer" would let tradeable raid loot be sold or disenchanted: it is kept only for
    -- an item whose data the client has loaded (C_Item.IsItemDataCached on its item location).
    it("never keeps 'no timer' for an item whose data is not loaded, and reads it again next time", function()
      _G.C_Item.GetItemGUID = function() return "Item-1" end
      put(0, 1, 50, { isBound = true, quality = 4 })
      items[50] = { class = 2 }
      tooltips["0:1"] = { lines = { { leftText = "Item 50" }, { leftText = "Soulbound" } } }
      uncached["0:1"] = true
      assert.is_false((one()).tradeTimer)
      assert.is_false((one()).tradeTimer)
      assert.equal(2, tipReads)
      uncached["0:1"] = nil
      one()
      one()
      assert.equal(3, tipReads)
    end)

    -- A read that could not see the tooltip (fail closed) is no answer: it is never kept.
    it("keeps no answer it could not read", function()
      _G.C_Item.GetItemGUID = function() return "Item-1" end
      put(0, 1, 50, { isBound = true, quality = 4 })
      items[50] = { class = 2 }
      tooltips["0:1"] = nil
      assert.is_true((one()).tradeTimer)
      tooltips["0:1"] = { lines = { { leftText = "Item 50" }, { leftText = "Soulbound" } } }
      assert.is_false((one()).tradeTimer)
      assert.equal(2, tipReads)
    end)
  end)

  it("marks a stack the player sells", function()
    put(0, 1, 50); put(0, 2, 51); put(0, 3, 52)
    for _, id in ipairs({ 50, 51, 52 }) do items[id] = { sell = 5 } end
    GC.db.sellMarks["commodity:50"] = true
    GC.db.sellMarks["pos:51:0:2"] = true
    GC.db.sellMarks["pos:52:0:3"] = false
    local out = B.Read()
    assert.is_true(out[1].selling)
    assert.is_true(out[2].selling)
    assert.is_false(out[3].selling)
  end)

  -- The item's own GUID (C_Item.GetItemGUID(itemLocation), ItemDocumentation.lua, live and forever)
  -- follows it wherever a sort of the bags moves it, and tells apart two items with one link: the
  -- Disenchant window holds its choices by it. Read for gear only, the window's only items.
  it("reads a gear stack's own GUID through its item location, and none for other stacks or a silent client", function()
    put(0, 1, 50, { quality = 2 }); put(0, 2, 51, { quality = 2 }); put(0, 3, 52, { quality = 2 })
    items[50], items[51], items[52] = { sell = 5, class = 4 }, { sell = 5, class = 15 }, { sell = 5, class = 2 }
    local asked = {}
    _G.C_Item.GetItemGUID = function(loc)
      asked[#asked + 1] = loc.bag .. ":" .. loc.slot
      if loc.slot == 3 then error("no item") end
      return "Item-1-0-" .. loc.bag .. loc.slot
    end
    local out = B.Read()
    assert.equal("Item-1-0-01", out[1].guid)
    assert.is_nil(out[2].guid)
    assert.is_nil(out[3].guid)
    assert.same({ "0:1", "0:3" }, asked)
    _G.C_Item.GetItemGUID = nil
    assert.is_nil(B.Read()[1].guid)
  end)

  it("leaves vendorUnit nil for an uncached item", function()
    put(0, 1, 50)
    local s = one()
    assert.is_nil(s.vendorUnit)
  end)

  describe("does not throw when a client call errors", function()
    for _, name in ipairs({ "numSlots", "info", "purchase", "flag", "backpack", "itemInfo", "refund", "setLocs", "tooltip" }) do
      it(name, function()
        put(0, 1, 50, { isBound = true }); put(1, 1, 51, { quality = 2 })
        items[50], items[51] = { sell = 5 }, { sell = 5, class = 4 }
        sets[1] = { 121 }
        errors[name] = true
        assert.has_no.errors(function() B.Read() end)
      end)
    end

    it("and fails closed on the protections", function()
      put(0, 1, 50, { isBound = true })
      items[50] = { sell = 5 }
      errors.backpack = true
      assert.is_true((one()).excludedBag)
      errors.backpack = nil
      errors.purchase, errors.refund = true, true
      assert.is_true((one()).refundable)
    end)
  end)
end)
