local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local S = require("spec.support.secure_button")

-- UI/DisenchantFrame.lua: the Disenchant window, its one secure button, the entry beside the bags,
-- the loot it learns from and the refusals it drops (retail only). The real Theme and kit, the real
-- planner (Core/Disenchant.lua over Core/VendorSelect.lua's freshness rule) and the Hoard's helpers;
-- the bag reader is a seam (GC.VendorBags.Read hands the stacks a spec puts), the slots the button
-- re-reads are C_Container's, and the secure parts are spec/support/secure_button.lua's.
describe("Disenchant window", function()
  local GC, DF, restore, saved, timers, stacks, slots, reads, prices, groups, loot, printed, menu, knows, clock, bags
  local sales, fighting, binds, shift, compared, cleared, tips, slotButtons, uncached, requested, blocked, errors
  local KEYS = { "UIParent", "C_SpellBook", "C_Spell", "C_Container", "C_Item", "C_Timer", "GetTime", "time",
    "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "ERR_CANT_BE_DISENCHANTED", "SPELL_FAILED_CANT_BE_DISENCHANTED",
    "SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL", "ERR_INVALID_ITEM_TARGET", "SPELL_FAILED_WRONG_ARTIFACT_EQUIPPED", "MenuUtil", "GameTooltip", "ITEM_QUALITY_COLORS", "SETTINGS_KEYBINDINGS_LABEL",
    "CreateColor", "hooksecurefunc", "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6", "NUM_CONTAINER_FRAMES", "INVTYPE_WAIST", "INVTYPE_CHEST",
    "BINDING_NAME_CLICK GoldCapDisenchantNext:LeftButton", "issecretvalue", "UnitAffectingCombat", "Enum", "IsModifiedClick",
    "GameTooltip_ShowCompareItem", "TooltipComparisonManager", "GoldCapDisenchantTooltip", "C_TooltipComparison",
    "GetGameMessageInfo" }
  local NOW = 1800000000
  local DUST, SHARD, ESSENCE = 9001, 9002, 9003

  -- A piece of gear in the bags: unbound green armour of the current expansion, a vendor paying
  -- `vendorUnit`, no auction house figure unless a case gives one.
  local function gear(bag, slot, itemID, over)
    local s = {
      bag = bag, slot = slot, itemID = itemID, link = "|Hitem:" .. itemID .. "|h[Item " .. itemID .. "]|h", count = 1,
      quality = 2, vendorUnit = 10000, hasNoValue = false, isLocked = false, isBound = true, isGear = true,
      isReagent = false, refundable = false, tradeTimer = false, inSet = false, excludedBag = false, selling = false,
      classID = 4, subclassID = 4, equipLoc = "INVTYPE_WAIST", expansion = 11,
    }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
  end
  local function put(s)
    stacks[#stacks + 1] = s
    slots[s.bag .. ":" .. s.slot] = { itemID = s.itemID, hyperlink = s.link, stackCount = s.count, isLocked = false,
      guid = s.guid }
    return s
  end
  local function take(s)
    for i, other in ipairs(stacks) do
      if other == s then table.remove(stacks, i) break end
    end
    slots[s.bag .. ":" .. s.slot] = nil
  end

  local function textOf(fs) return helper.plain(W.state(fs).text or "") end
  local function press(widget, mouseButton) W.state(widget).scripts.OnClick(widget, mouseButton or "LeftButton", false) end
  local function at(widget) return W.state(widget).points[1] end
  local function event(name, ...) DF.OnEvent(name, ...) end
  local function button() return _G.GoldCapDisenchantNext end
  local function attr(name) return button():GetAttribute(name) end
  local function windowUp() return DF._frame ~= nil and DF._frame:IsShown() end
  local function entryUp() return DF._entry ~= nil and DF._entry:IsShown() end

  -- Blizzard's item buttons of a container frame, as ContainerFrameMixin:EnumerateValidItems hands them
  -- (live ContainerFrame.lua:522-526: index, button) and ContainerFrameItemButtonMixin answers
  -- GetBagID (:1648) and the engine's GetID the slot.
  local function giveButtons(container, bag, n)
    local list = {}
    for slot = 1, n do
      local b = CreateFrame("Button", nil, container)
      b:SetID(slot)
      b.GetBagID = function() return bag end
      list[slot] = b
      slotButtons[bag .. ":" .. slot] = b
    end
    function container:EnumerateValidItems()
      return function(_, i)
        i = i + 1
        if list[i] then return i, list[i] end
      end, self, 0
    end
    return list
  end
  -- Our overlay on a bag button: the one child frame it carries, and what is drawn on it.
  local function overlayOf(key)
    local b = slotButtons[key]
    return b and (b:GetChildren())
  end
  local function drawn(key, part)
    local o = overlayOf(key)
    return o ~= nil and o:IsShown() and o[part]:IsShown()
  end

  local function fire(seconds)
    local n = 0
    for i = 1, #timers do
      local t = timers[i]
      if t and not t.done and t.seconds == seconds then
        t.done = true
        t.fn()
        n = n + 1
      end
    end
    return n
  end
  local function nextFrame() while fire(0) > 0 do end end

  local function openBags()
    bags:Show()
    local hook = W.state(bags).hooks and W.state(bags).hooks.OnShow
    if hook then hook(bags) end
    nextFrame()
  end
  local function slash() GC.slashHandlers.disenchant("") nextFrame() end
  local function armedAt() return { attr("type"), attr("spell"), attr("target-bag"), attr("target-slot") } end

  -- The queue as the window lists it: the item ids of "In this order", in order.
  local function listed()
    local out = {}
    for _, row in ipairs(DF._rows) do
      if row:IsShown() and row.itemID and not row.done then out[#out + 1] = row.itemID end
    end
    return out
  end
  local function rowOf(itemID)
    for _, row in ipairs(DF._rows) do
      if row:IsShown() and row.itemID == itemID and not row.done then return row end
    end
  end

  -- The client's disenchant, from the press to the loot: the cast starts, goes and gives `mats`.
  local function disenchant(castGUID, mats)
    event("UNIT_SPELLCAST_START", "player", castGUID, 13262)
    nextFrame()
    clock = clock + 1.5
    event("UNIT_SPELLCAST_SUCCEEDED", "player", castGUID, 13262)
    loot = mats or {}
    event("LOOT_READY", false)
  end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = S.install()
    -- A GameTooltip made from GameTooltipTemplate: the widget's own methods a window uses on it.
    local create = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent, template)
      local f = create(kind, name, parent, template)
      if kind == "GameTooltip" then
        local tip = { template = template }
        tips[#tips + 1] = { frame = f, state = tip }
        function f:SetOwner(owner, anchor) tip.owner, tip.anchor = owner, anchor end
        function f:GetOwner() return tip.owner end
        function f:IsOwned(owner) return tip.owner == owner end
        function f:SetBagItem(bag, slot) tip.bag, tip.slot, tip.link = bag, slot, nil end
        function f:SetHyperlink(link) tip.link, tip.bag, tip.slot = link, nil, nil end
      end
      return f
    end
    timers, stacks, slots, reads, prices, groups, printed, loot, sales = {}, {}, {}, 0, {}, {}, {}, {}, {}
    knows, clock, fighting = true, 1000, false
    -- What C_Item.GetItemInfo's 14th answer (bindType, Enum.ItemBind) says of an item; 0 (None) else.
    binds = { [ESSENCE] = 1 }
    shift, compared, cleared, tips, blocked = false, {}, {}, {}, {}
    _G.time = function() return NOW end
    _G.GetTime = function() return clock end
    _G.UIParent = CreateFrame("Frame")
    _G.ContainerFrameCombinedBags = CreateFrame("Frame", nil, _G.UIParent)
    _G.ContainerFrameCombinedBags:Hide()
    -- Blizzard's separate bags, the reagent bag the last (ContainerFrame.xml:283-288), all closed.
    _G.NUM_CONTAINER_FRAMES = 6
    for i = 1, 6 do
      _G["ContainerFrame" .. i] = CreateFrame("Frame", nil, _G.UIParent)
      _G["ContainerFrame" .. i]:Hide()
    end
    bags = _G.ContainerFrameCombinedBags
    slotButtons, uncached, requested = {}, {}, {}
    giveButtons(bags, 0, 6)
    _G.C_SpellBook = { IsSpellKnown = function(spellID) return knows and spellID == 13262 end }
    _G.C_Spell = { GetSpellTexture = function() return 136244 end }
    _G.C_Container = { GetContainerItemInfo = function(bag, slot) return slots[bag .. ":" .. slot] end }
    _G.C_Item = {
      GetItemInfo = function(item)
        local id = tonumber(tostring(item):match("item:(%d+)")) or item
        if uncached[id] then return nil end
        return "Item " .. id, nil, 2, 201, 0, "Armor", "Plate", 1, "INVTYPE_WAIST", 1000 + id, 10000, 4, 4,
          binds[id] or 0, 11
      end,
      GetItemNameByID = function(id) return "Item " .. id end,
      GetItemIconByID = function(id) return 1000 + id end,
      IsItemDataCachedByID = function(id) return not uncached[id] end,
      RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end,
      GetDetailedItemLevelInfo = function() return 201 end,
    }
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    -- The client's loot window (Blizzard_UIPanels_Game/Mainline/LootFrame.lua reads it so): a link
    -- per slot, and GetLootSlotInfo's third answer the quantity.
    _G.GetNumLootItems = function() return #loot end
    _G.GetLootSlotLink = function(i) return loot[i] and ("|Hitem:" .. loot[i][1] .. "|h[Mat]|h") end
    _G.GetLootSlotInfo = function(i)
      local l = loot[i]
      if not l then return nil end
      return 134400, "Mat", l[2], nil, 1, false, false, nil, true, false
    end
    -- GlobalStrings (Ketho/BlizzardInterfaceResources live, enUS).
    _G.ERR_CANT_BE_DISENCHANTED = "Item cannot be disenchanted"
    _G.SPELL_FAILED_CANT_BE_DISENCHANTED = "Item cannot be disenchanted"
    _G.SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL = "Your Enchanting skill is not high enough to disenchant that"
    -- Two globals with the one English text (live enUS; frFR spells them apart).
    _G.ERR_INVALID_ITEM_TARGET = "That item is not a valid target."
    _G.SPELL_FAILED_WRONG_ARTIFACT_EQUIPPED = "That item is not a valid target."
    -- UI_ERROR_MESSAGE's first argument is a game error's index, and GetGameMessageInfo answers its
    -- name, sound kit and voice (live GameErrorDocumentation.lua; UIErrorsFrame.lua:150 reads it).
    -- The client always has it. The indices are the client's own, in no source: these stand for
    -- them. A spell's failure with no game error of its own comes as ERR_SPELL_FAILED_S ("%s"), its
    -- words the spell's (UIErrorsFrame.lua:60 throttles that type): "Interrupted", the skill's
    -- refusal, "That item is not a valid target." as SPELL_FAILED_WRONG_ARTIFACT_EQUIPPED.
    errors = { [1] = "ERR_SPELL_FAILED_S", [50] = "ERR_SPELL_FAILED_S", [52] = "ERR_CANT_BE_DISENCHANTED",
      [53] = "ERR_GENERIC_NO_TARGET", [54] = "ERR_INVALID_ITEM_TARGET" }
    _G.GetGameMessageInfo = function(index)
      local name = errors[index]
      if name then return name, nil, nil end
    end
    _G.SETTINGS_KEYBINDINGS_LABEL = "Keybindings"
    _G.INVTYPE_WAIST, _G.INVTYPE_CHEST = "Waist", "Chest"
    _G.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 },
      [4] = { r = 0.64, g = 0.21, b = 0.93 } }
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.hooksecurefunc = nil
    _G.issecretvalue = nil
    _G.Enum = { ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4, ToWoWAccount = 7,
      ToBnetAccount = 8, ToBnetAccountUntilEquipped = 9 } }
    -- The compare modifier (Shift unless the player bound it elsewhere), and Blizzard's comparison:
    -- GameTooltip_ShowCompareItem (GameTooltip.lua:483-490) calls C_TooltipComparison.CompareItem,
    -- a protected function in live and Forever (TooltipComparisonDocumentation.lua:11-14). Called
    -- from addon code the client blocks it (ADDON_ACTION_BLOCKED) and compares nothing; here every
    -- caller is addon code, so every call is blocked.
    _G.IsModifiedClick = function(action) return action == "COMPAREITEMS" and shift end
    _G.C_TooltipComparison = { CompareItem = function() blocked[#blocked + 1] = "C_TooltipComparison.CompareItem" end }
    _G.GameTooltip_ShowCompareItem = function(tooltip)
      compared[#compared + 1] = tooltip
      _G.C_TooltipComparison.CompareItem()
    end
    _G.TooltipComparisonManager = { Clear = function(_, tooltip) cleared[#cleared + 1] = tooltip end }
    -- The player in combat: from PLAYER_REGEN_DISABLED (a spec sets `fighting`) and through the lockdown.
    _G.UnitAffectingCombat = function(unit) return unit == "player" and (fighting or S.combat) end
    -- MenuUtil's description (live Blizzard_Menu/MenuUtil.lua:151, BaseMenuDescriptionMixin): titles,
    -- dividers and buttons, a button taking a submenu of its own.
    local function node(kind, text, fn)
      local n = { kind = kind, text = text, fn = fn, buttons = {}, entries = {} }
      function n:CreateButton(t, f)
        local c = node("button", t, f)
        self.buttons[#self.buttons + 1], self.entries[#self.entries + 1] = c, c
        return c
      end
      function n:CreateTitle(t) self.entries[#self.entries + 1] = node("title", t) end
      function n:CreateDivider() self.entries[#self.entries + 1] = node("divider") end
      function n:SetScrollMode(extent) self.scroll = extent end
      return n
    end
    _G.MenuUtil = { CreateContextMenu = function(owner, generator)
      menu = node("root")
      menu.owner = owner
      generator(owner, menu)
    end }
    -- Blizzard's GameTooltip: the methods a window calls on it, each recorded. It carries
    -- supportsItemComparison, so Blizzard compares an item shown through its accessors itself.
    _G.GameTooltip = {
      lines = {},
      SetOwner = function(self, owner, anchor, x, y)
        self.owner, self.anchor, self.x, self.y = owner, anchor, x, y
        self.lines, self.bag, self.slot, self.link, self.point = {}, nil, nil, nil, nil
      end,
      ClearAllPoints = function(self) self.point = nil end,
      SetPoint = function(self, ...) self.point = { ... } end,
      AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
      SetBagItem = function(self, bag, slot) self.bag, self.slot = bag, slot end,
      SetHyperlink = function(self, link) self.link = link end,
      Show = function(self) self.shown = true end,
      Hide = function(self) self.owner, self.shown = nil, false end,
      IsShown = function(self) return self.shown == true end,
      IsOwned = function(self, owner) return self.owner == owner end,
    }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/ForeverValue.lua", GC)
    helper.loadModule("Core/VendorSelect.lua", GC)
    helper.loadModule("Core/Disenchant.lua", GC)
    helper.loadModule("Core/CraftMath.lua", GC)
    GC.db = { imported = { ts = NOW - 720 } }
    -- Services/CraftClient.lua's SellOf, a seam: an item's market price and how many sell a day.
    GC.CraftClient = { SellOf = function(itemID) return sales[itemID] and 1000000, sales[itemID] end }
    GC.Data = { GetItemValue = function() return nil end, OriginState = function() return "app" end }
    GC.Print = function(msg) printed[#printed + 1] = msg end
    GC.slashHandlers = {}
    -- The bag reader's GuidOf answers the GUID of the item a slot holds now (C_Item.GetItemGUID).
    GC.VendorBags = { Read = function()
      reads = reads + 1
      local copy = {}
      for i, s in ipairs(stacks) do copy[i] = s end
      return copy
    end, GuidOf = function(bag, slot)
      local info = slots[bag .. ":" .. slot]
      return info and info.guid or nil
    end }
    GC.MerchantNote = { ValueFor = function(itemID)
      local p = prices[itemID]
      return p and { mv = p, source = "region", at = NOW - 60 } or nil
    end }
    GC.GroupRules = { GroupOf = function(itemID) return groups[itemID] end }
    helper.loadModule("UI/HoardFrame.lua", GC)
    helper.loadModule("UI/HoardRow.lua", GC)
    helper.loadModule("UI/HoardList.lua", GC)
    helper.loadModule("UI/HoardFooter.lua", GC)
    helper.loadModule("UI/DisenchantFrame.lua", GC)
    helper.loadModule("UI/DisenchantMarks.lua", GC)
    DF = GC.DisenchantFrame
  end)

  after_each(function()
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  -- Greens and blues of this expansion, learned: dust 2.5 a green, a shard a blue; dust sells for
  -- 1g and a shard for 10g, so after the auction house's cut a green's mats are worth about 2.4g and
  -- a blue's 9.5g.
  local function learned()
    GC.Disenchant.Learn(GC.db, "q2:x11", { [DUST] = 2 })
    GC.Disenchant.Learn(GC.db, "q2:x11", { [DUST] = 3 })
    GC.Disenchant.Learn(GC.db, "q3:x11", { [SHARD] = 1 })
    prices[DUST], prices[SHARD] = 10000, 100000
  end

  -- ---------------------------------------------------------------------------------------------
  -- Who sees it
  -- ---------------------------------------------------------------------------------------------

  it("stays out of sight and reads nothing for a character without Disenchant", function()
    knows = false
    put(gear(0, 1, 501))
    event("PLAYER_LOGIN")
    openBags()
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    slash()
    assert.is_false(entryUp())
    assert.is_false(windowUp())
    assert.is_nil(_G.GoldCapDisenchantNext)
    assert.equal(0, reads)
    assert.same({ "This character does not know Disenchant." }, printed)
  end)

  it("shows the entry beside the open bags with how many are queued, and toggles the window", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    openBags()
    assert.is_true(entryUp())
    assert.equal("2", textOf(DF._entry.count))
    local point = at(DF._entry)
    assert.equal(bags, point[2])
    press(DF._entry)
    nextFrame()
    assert.is_true(windowUp())
    press(DF._entry)
    nextFrame()
    assert.is_false(windowUp())
  end)

  -- The owner, 2026-10-26 23:15-23:21: with everything left out the entry hid, and Left out, Kept and
  -- Got so far could be reached only by /gc disenchant. It shows with the bags for an enchanter.
  it("shows the entry with the bags whatever is queued, with no count when nothing can be disenchanted", function()
    put(gear(0, 1, 501, { quality = 1 }))
    openBags()
    assert.is_true(entryUp())
    assert.is_false(DF._entry.pill:IsShown())
    assert.is_false(DF._entry.count:IsShown())
    put(gear(0, 2, 502))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.is_true(entryUp())
    assert.is_true(DF._entry.pill:IsShown())
    assert.equal("1", textOf(DF._entry.count))
    bags:Hide()
    W.state(bags).hooks.OnHide(bags)
    nextFrame()
    assert.is_false(entryUp())
  end)

  -- The owner, 23:22: a number beside it, so the player sees how many can be disenchanted: the queue
  -- in gold; with none queued, what is left out in grey; kept items not counted.
  it("counts the queue on the entry in gold, and with none queued what is left out in grey", function()
    local K = GC.Kit.Tokens.color
    local function rgb(c) return { c[1], c[2], c[3] } end
    learned()
    put(gear(0, 1, 501, { vendorUnit = 190000 }))
    put(gear(0, 2, 502, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    local kept = put(gear(0, 4, 504, { vendorUnit = 190000 }))
    GC.Disenchant.Keep(GC.db, kept.itemID)
    openBags()
    assert.is_true(entryUp())
    assert.equal("2", textOf(DF._entry.count))
    assert.same(rgb(K.text5), rgb(W.state(DF._entry.pill).vertex))
    assert.same(rgb(K.text2), rgb(W.state(DF._entry.count).color))
    put(gear(0, 3, 503, { quality = 3, vendorUnit = 10000 }))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.equal("1", textOf(DF._entry.count))
    assert.same(rgb(K.gold), rgb(W.state(DF._entry.pill).vertex))
    assert.same(rgb(K.onGold), rgb(W.state(DF._entry.count).color))
  end)

  it("says in the entry's tooltip how many are worth disenchanting and how many pay more elsewhere", function()
    learned()
    local function hover()
      W.state(DF._entry).scripts.OnEnter(DF._entry)
      return _G.GameTooltip.lines
    end
    openBags()
    assert.same({ "GoldCap Disenchant", "Nothing in your bags to disenchant." }, hover())
    put(gear(0, 1, 501, { vendorUnit = 190000 }))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.same({ "GoldCap Disenchant", "Worth disenchanting: 0", "A vendor pays more: 1" }, hover())
    put(gear(0, 2, 502, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    put(gear(0, 3, 503, { quality = 3, vendorUnit = 10000 }))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.same({ "GoldCap Disenchant", "Worth disenchanting: 1", "The auction house pays more: 1",
      "A vendor pays more: 1" }, hover())
  end)

  it("toggles with /gc disenchant, for bag addons that replace Blizzard's bags", function()
    put(gear(0, 1, 501))
    slash()
    assert.is_true(windowUp())
    slash()
    assert.is_false(windowUp())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The one secure button
  -- ---------------------------------------------------------------------------------------------

  it("is the probe's button: named for its binding, left button up, never on key down, hidden in combat", function()
    put(gear(0, 1, 501))
    slash()
    local b = button()
    assert.is_not_nil(b)
    assert.same({ "LeftButtonUp" }, W.state(b).clicks)
    assert.is_false(b:GetAttribute("useOnKeyDown"))
    assert.equal("[combat] hide; show", S.driver(b, "visibility"))
  end)

  it("points the button at the first item in the queue after a paint", function()
    learned()
    put(gear(0, 1, 501))
    put(gear(1, 3, 502, { quality = 3, vendorUnit = 100 }))
    slash()
    assert.same({ "spell", 13262, 1, 3 }, armedAt())
    assert.equal("Item 502", textOf(DF._frame.card.name))
    assert.equal("1 of 2", textOf(DF._frame.card.counter))
  end)

  it("disenchants the item the window names on a click, and once on a key press", function()
    put(gear(0, 1, 501))
    slash()
    S.click(button())
    assert.same({ { spell = 13262, bag = 0, slot = 1 } }, S.casts)
    S.key(button())
    assert.equal(2, #S.casts)
  end)

  it("clears the button in PreClick when the slot no longer holds the item, so that click casts nothing", function()
    local first = put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
    -- Moved away between the paint and the press: another item stands in the slot now.
    take(first)
    slots["0:1"] = { itemID = 777, hyperlink = "|Hitem:777|h[Other]|h", stackCount = 1 }
    S.click(button())
    assert.same({}, S.casts)
    assert.same({}, armedAt())
    nextFrame()
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
  end)

  -- A sort that moves an identical twin (one link) into the armed slot before the window repaints:
  -- the link still matches, the item's own GUID does not, so the press casts nothing.
  it("casts nothing when an identical twin stands in the armed slot, by the item's GUID", function()
    put(gear(0, 1, 601, { guid = "Item-A" }))
    put(gear(0, 2, 601, { guid = "Item-B" }))
    slash()
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
    slots["0:1"].guid, slots["0:2"].guid = "Item-B", "Item-A"
    S.click(button())
    assert.same({}, S.casts)
    assert.same({}, armedAt())
    assert.is_nil(DF._pending)
  end)

  it("arms the next item when Skip is pressed", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    press(DF._frame.card.skip)
    nextFrame()
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
    assert.same({ 502 }, listed())
  end)

  it("casts nothing while its own cast goes, and names the item Now", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UNIT_SPELLCAST_START", "player", "Cast-1", 13262)
    nextFrame()
    assert.same({}, armedAt())
    assert.equal("Now", textOf(DF._frame.card.label))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Learning and refusals
  -- ---------------------------------------------------------------------------------------------

  it("learns what its own disenchant gave from the first LOOT_READY after it", function()
    local first = put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    prices[DUST] = 10000
    slash()
    S.click(button())
    disenchant("Cast-1", { { DUST, 3 } })
    take(first)
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    local y, n = GC.Disenchant.Yield(GC.db, "q2:x11")
    assert.equal(1, n)
    assert.equal(3, y[DUST])
    assert.equal("Got so far", textOf(DF._frame.strip.label))
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
    assert.equal("2 of 2", textOf(DF._frame.card.counter))
  end)

  it("learns nothing from loot that did not follow its own disenchant", function()
    put(gear(0, 1, 501))
    slash()
    -- A mob's loot.
    loot = { { DUST, 9 } }
    event("LOOT_READY", false)
    -- The player's own Disenchant from the spellbook, not the window's press.
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 13262)
    event("LOOT_READY", false)
    -- The window's press, and loot that comes after its window is over.
    S.click(button())
    event("UNIT_SPELLCAST_START", "player", "Cast-2", 13262)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 13262)
    clock = clock + 4
    event("LOOT_READY", false)
    assert.is_nil(GC.Disenchant.Yield(GC.db, "q2:x11"))
  end)

  it("reads the first LOOT_READY only, once", function()
    put(gear(0, 1, 501))
    slash()
    S.click(button())
    disenchant("Cast-1", { { DUST, 3 } })
    loot = { { DUST, 7 } }
    event("LOOT_READY", false)
    local y, n = GC.Disenchant.Yield(GC.db, "q2:x11")
    assert.equal(1, n)
    assert.equal(3, y[DUST])
  end)

  it("drops an item the client says cannot be disenchanted and arms the next", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UI_ERROR_MESSAGE", 52, "Item cannot be disenchanted")
    event("UNIT_SPELLCAST_FAILED", "player", "Cast-1", 13262)
    nextFrame()
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
    assert.same({ 502 }, listed())
    assert.is_true(GC.Disenchant.Cant(GC.db, 501))
  end)

  -- Torc of Passed Time, a neck the client refused with "That item is not a valid target." and the
  -- window kept naming (the owner, 2026-10-26 22:35): every press after failed the same way.
  it("leaves out for good an item the client says is not a valid target, arms the next, and Try again brings it back", function()
    put(gear(0, 1, 501, { quality = 4, subclassID = 0, equipLoc = "INVTYPE_NECK" }))
    put(gear(0, 2, 502))
    slash()
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
    S.click(button())
    event("UI_ERROR_MESSAGE", 1, _G.ERR_INVALID_ITEM_TARGET)
    nextFrame()
    assert.same({ 502 }, listed())
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
    assert.equal("Item 502", textOf(DF._frame.card.name))
    assert.equal("Next", textOf(DF._frame.card.label))
    -- A new visit, as after /reload: what the saved store holds is all that remains.
    DF.Close()
    slash()
    assert.same({ 502 }, listed())
    assert.equal("cant", DF.Standing(slotButtons["0:1"], 501).state)
    assert.equal("Kept: 1 item", textOf(DF._frame.kept.text))
    press(DF._frame.kept.show)
    local kinds, title, item = {}, nil, nil
    for i, e in ipairs(menu.entries) do
      kinds[i] = e.kind
      if e.kind == "title" then title = e.text end
      if e.kind == "button" then item = e end
    end
    assert.same({ "title", "button" }, kinds)
    assert.equal("GoldCap could not disenchant these", title)
    assert.is_truthy(item.text:find("Item 501", 1, true))
    assert.is_truthy(item.text:find("Try again", 1, true))
    assert.same({}, item.buttons)
    item.fn()
    nextFrame()
    assert.is_false(GC.Disenchant.Cant(GC.db, 501))
    assert.same({ 501, 502 }, listed())
  end)

  -- "That item is not a valid target." is any item's refusal, so it marks an item for good only as
  -- the answer to a press: within REFUSAL_SECONDS of it and before any cast of the player's starts
  -- or another spell of theirs is sent (the re-review's T1).
  it("marks nothing for good when the refusal comes 2 s after the press, and drops the item for the visit only", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    clock = clock + 2
    event("UI_ERROR_MESSAGE", 1, _G.ERR_INVALID_ITEM_TARGET)
    nextFrame()
    assert.is_false(GC.Disenchant.Cant(GC.db, 501))
    assert.same({ 502 }, listed())
    DF.Close()
    slash()
    assert.same({ 501, 502 }, listed())
  end)

  it("ignores a refusal once the press's cast started", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UNIT_SPELLCAST_START", "player", "Cast-1", 13262)
    event("UI_ERROR_MESSAGE", 1, _G.ERR_INVALID_ITEM_TARGET)
    nextFrame()
    assert.is_false(GC.Disenchant.Cant(GC.db, 501))
    assert.same({ 501, 502 }, listed())
  end)

  it("ignores a refusal once another spell of the player's was sent after the press", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UNIT_SPELLCAST_SENT", "player", "", "Cast-9", 6603)
    event("UI_ERROR_MESSAGE", 1, _G.ERR_INVALID_ITEM_TARGET)
    nextFrame()
    assert.is_false(GC.Disenchant.Cant(GC.db, 501))
    assert.same({ 501, 502 }, listed())
  end)

  it("casts nothing and waits for no answer on a press while the item is on the cursor", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    slots["0:1"].isLocked = true
    S.click(button())
    assert.same({}, S.casts)
    assert.is_nil(DF._pending)
    event("UI_ERROR_MESSAGE", 1, _G.ERR_INVALID_ITEM_TARGET)
    nextFrame()
    assert.is_false(GC.Disenchant.Cant(GC.db, 501))
  end)

  -- UI_ERROR_MESSAGE's first argument names the error (GetGameMessageInfo): a name of ours decides
  -- whatever the words, and any other name leaves the words to decide.
  it("takes a refusal named by GetGameMessageInfo whatever its words, and no other error", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UI_ERROR_MESSAGE", 53, "You have no target.")
    nextFrame()
    assert.is_false(GC.Disenchant.Cant(GC.db, 501))
    assert.same({ 501, 502 }, listed())
    event("UI_ERROR_MESSAGE", 54, "Ce n'est pas une cible valide.")
    nextFrame()
    assert.is_true(GC.Disenchant.Cant(GC.db, 501))
    assert.same({ 502 }, listed())
  end)

  -- In the client the name of a spell's failure is the carrier ERR_SPELL_FAILED_S, whose words are
  -- the spell's own (the final review's I1): there the words decide.
  it("marks an item for good on 'Item cannot be disenchanted' carried as a spell's failure", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UI_ERROR_MESSAGE", 1, "Item cannot be disenchanted")
    nextFrame()
    assert.is_true(GC.Disenchant.Cant(GC.db, 501))
    assert.same({ 502 }, listed())
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
  end)

  it("drops for the visit an item the skill is too low for, its words carried as a spell's failure", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UI_ERROR_MESSAGE", 1, "Your Enchanting skill is not high enough to disenchant that")
    nextFrame()
    assert.is_false(GC.Disenchant.Cant(GC.db, 501))
    assert.same({ 502 }, listed())
    DF.Close()
    slash()
    assert.same({ 501, 502 }, listed())
  end)

  it("leaves out for this visit only an item the Enchanting skill is too low for", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UI_ERROR_MESSAGE", 1, _G.SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL)
    nextFrame()
    assert.same({ 502 }, listed())
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
    assert.is_false(GC.Disenchant.Cant(GC.db, 501))
    DF.Close()
    slash()
    assert.same({ 501, 502 }, listed())
  end)

  it("drops it too when the cast's failure comes before the client's words", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UNIT_SPELLCAST_FAILED", "player", "Cast-1", 13262)
    event("UI_ERROR_MESSAGE", 52, "Item cannot be disenchanted")
    nextFrame()
    assert.same({ 502 }, listed())
  end)

  it("keeps an item whose cast was moved or interrupted", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UNIT_SPELLCAST_START", "player", "Cast-1", 13262)
    event("UI_ERROR_MESSAGE", 50, "Interrupted")
    event("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-1", 13262, "Player-1")
    nextFrame()
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
    assert.same({ 501, 502 }, listed())
  end)

  -- A double click (or a key tapped twice) before the cast starts: the second press fails
  -- ("Another action is in progress") with a cast of its own, before or after the first one starts.
  it("learns a double press's one cast once, and never arms again while it goes", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    S.click(button())
    event("UNIT_SPELLCAST_FAILED", "player", "Cast-2", 13262)
    nextFrame()
    event("UNIT_SPELLCAST_START", "player", "Cast-1", 13262)
    nextFrame()
    assert.equal("Now", textOf(DF._frame.card.label))
    assert.same({}, armedAt())
    event("UNIT_SPELLCAST_FAILED", "player", "Cast-3", 13262)
    nextFrame()
    assert.equal("Now", textOf(DF._frame.card.label))
    assert.same({}, armedAt())
    clock = clock + 1.5
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 13262)
    loot = { { DUST, 3 } }
    event("LOOT_READY", false)
    local y, n = GC.Disenchant.Yield(GC.db, "q2:x11")
    assert.equal(1, n)
    assert.equal(3, y[DUST])
  end)

  -- The first click is refused before any cast starts (the player was moving: no START, a FAILED);
  -- the second, 3.5 s later, is kept as that press's, and its cast succeeds 5.2 s after the first.
  it("learns a cast that answers a kept press late, and names the next item right after", function()
    local first = put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    event("UNIT_SPELLCAST_FAILED", "player", "Cast-1", 13262)
    clock = clock + 3.5
    S.click(button())
    event("UNIT_SPELLCAST_START", "player", "Cast-2", 13262)
    nextFrame()
    assert.equal("Now", textOf(DF._frame.card.label))
    clock = clock + 1.7
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 13262)
    loot = { { DUST, 3 } }
    event("LOOT_READY", false)
    nextFrame()
    local y, n = GC.Disenchant.Yield(GC.db, "q2:x11")
    assert.equal(1, n)
    assert.equal(3, y[DUST])
    assert.equal("Next", textOf(DF._frame.card.label))
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
    take(first)
  end)

  -- The cast this window bound at START ends it, by its GUID, even after its press stopped waiting.
  it("ends its own cast by the cast's GUID once the press has stopped waiting", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    clock = clock + 1.4
    event("UNIT_SPELLCAST_START", "player", "Cast-1", 13262)
    nextFrame()
    clock = clock + 4
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 13262)
    nextFrame()
    assert.equal("Next", textOf(DF._frame.card.label))
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
  end)

  -- A cast starts at once or never: a START later than START_SECONDS after the press is a Disenchant
  -- from elsewhere (the spellbook, another addon's button) after a press that never started (the
  -- final review's M2), and neither teaches the press's kind nor counts its item done.
  it("takes no Disenchant that starts 2 s after its press for its own: nothing learned, nothing done", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    clock = clock + 2
    event("UNIT_SPELLCAST_START", "player", "Cast-9", 13262)
    nextFrame()
    assert.equal("Next", textOf(DF._frame.card.label))
    clock = clock + 1.5
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 13262)
    loot = { { DUST, 3 } }
    event("LOOT_READY", false)
    nextFrame()
    assert.is_nil(GC.Disenchant.Yield(GC.db, "q2:x11"))
    assert.same({ 501, 502 }, listed())
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
  end)

  it("names the next item again when its cast never answers", function()
    put(gear(0, 1, 501))
    slash()
    S.click(button())
    event("UNIT_SPELLCAST_START", "player", "Cast-1", 13262)
    nextFrame()
    assert.equal("Now", textOf(DF._frame.card.label))
    clock = clock + DF.CAST_SECONDS + DF.PENDING_SECONDS + 1
    local bar = DF._frame.card.bar
    W.state(bar).scripts.OnUpdate(bar, 0.1)
    nextFrame()
    assert.equal("Next", textOf(DF._frame.card.label))
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
  end)

  it("ignores the client's refusal when no press of its own was waiting for it", function()
    put(gear(0, 1, 501))
    slash()
    event("UI_ERROR_MESSAGE", 52, "Item cannot be disenchanted")
    nextFrame()
    assert.same({ 501 }, listed())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The lists
  -- ---------------------------------------------------------------------------------------------

  it("keeps an item off the list for good with Never disenchant this", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    press(rowOf(501), "RightButton")
    assert.equal("Never disenchant this", menu.buttons[1].text)
    menu.buttons[1].fn()
    nextFrame()
    assert.is_true(GC.Disenchant.Kept(GC.db, 501))
    assert.same({ 502 }, listed())
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
  end)

  it("leaves out what the auction house pays more for, until Disenchant anyway", function()
    put(gear(0, 1, 501, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    put(gear(0, 2, 502))
    slash()
    assert.same({ 502 }, listed())
    local left = DF._leftRows[1]
    assert.is_true(left:IsShown())
    assert.equal(501, left.itemID)
    press(left.anyway)
    nextFrame()
    -- Neither has mats learned: the two stand in bag order.
    assert.same({ 501, 502 }, listed())
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
  end)

  -- Disenchant anyway and Skip follow the item, never its bag slot (the final review's I2): the bags
  -- sorted, the item sent anyway moves on and another the auction house pays as much for lands in
  -- its slot; the skipped item leaves and another takes its slot.
  it("follows the item sent anyway, not its slot, when the bags are sorted", function()
    local function dear(slot, itemID) return gear(0, slot, itemID, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }) end
    local x = put(dear(5, 501))
    put(gear(0, 2, 502))
    slash()
    press(DF._leftRows[1].anyway)
    nextFrame()
    assert.same({ 502, 501 }, listed())
    take(x)
    put(dear(7, 501))
    put(dear(5, 503))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.same({ 502 }, listed())
    local left = {}
    for _, row in ipairs(DF._leftRows) do
      if row:IsShown() then left[#left + 1] = row.itemID end
    end
    table.sort(left)
    assert.same({ 501, 503 }, left)
  end)

  -- The owner, 2026-10-27 00:2x: Disenchant anyway on two of four identical slippers (one link), one
  -- of them disenchanted, the bags sorted: the queue then held the other three. The visit's choices
  -- hold an item by its GUID (the bag reader's `guid`), so a twin never inherits one.
  local function guids(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.stack.guid end
    return out
  end
  local function vendorLine(guid)
    for _, row in ipairs(DF._vendorRows) do
      if row:IsShown() and row.stack and row.stack.guid == guid then return row end
    end
  end
  -- Moves each stack to the slot given, as a sort of the bags does: { [stack] = slot }.
  local function sortBags(moves)
    for stack in pairs(moves) do slots[stack.bag .. ":" .. stack.slot] = nil end
    for stack, slot in pairs(moves) do
      stack.slot = slot
      slots[stack.bag .. ":" .. slot] = { itemID = stack.itemID, hyperlink = stack.link, stackCount = 1, isLocked = false }
    end
    event("BAG_UPDATE_DELAYED")
    nextFrame()
  end

  it("keeps Disenchant anyway on the identical items chosen, by their GUIDs, through a disenchant and a sort", function()
    learned()
    local slippers = {}
    for i = 1, 4 do slippers[i] = put(gear(0, i, 601, { vendorUnit = 190000, guid = "Item-S" .. i })) end
    slash()
    assert.same({}, listed())
    press(vendorLine("Item-S2").anyway)
    nextFrame()
    press(vendorLine("Item-S4").anyway)
    nextFrame()
    assert.same({ "Item-S2", "Item-S4" }, guids(DF._plan.queue))
    S.click(button())
    disenchant("Cast-1", { { DUST, 3 } })
    take(slippers[2])
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    sortBags({ [slippers[4]] = 1, [slippers[1]] = 2, [slippers[3]] = 4 })
    assert.same({ "Item-S4" }, guids(DF._plan.queue))
    assert.equal("0:1", DF._plan.queue[1].slotKey)
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
    local left = guids(DF._plan.leftVendor)
    table.sort(left)
    assert.same({ "Item-S1", "Item-S3" }, left)
  end)

  it("keeps a skip and a chosen line on the identical item, by its GUID, through a sort", function()
    local a = put(gear(0, 1, 601, { guid = "Item-A" }))
    local b = put(gear(0, 2, 601, { guid = "Item-B" }))
    local c = put(gear(0, 3, 601, { guid = "Item-C" }))
    slash()
    press(DF._frame.card.skip)
    nextFrame()
    assert.same({ "Item-B", "Item-C" }, guids(DF._plan.queue))
    sortBags({ [a] = 2, [b] = 1 })
    assert.same({ "Item-B", "Item-C" }, guids(DF._plan.queue))
    -- Item-C chosen to go next, then a sort puts it last: still first.
    local line
    for _, row in ipairs(DF._rows) do
      if row:IsShown() and row.stack and row.stack.guid == "Item-C" and not row.done then line = row end
    end
    press(line)
    nextFrame()
    assert.same({ "Item-C", "Item-B" }, guids(DF._plan.queue))
    sortBags({ [c] = 1, [b] = 3 })
    assert.same({ "Item-C", "Item-B" }, guids(DF._plan.queue))
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
  end)

  it("follows the item skipped, not its slot: another item there is listed", function()
    local a = put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    press(DF._frame.card.skip)
    nextFrame()
    assert.same({ 502 }, listed())
    take(a)
    put(gear(0, 1, 503))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.same({ 503, 502 }, listed())
  end)

  -- A green whose mats are worth about 2g that a vendor pays 19g for (the owner, 2026-10-26: a 61g
  -- axe for 2g of dust was one key press away).
  it("leaves out what a vendor pays more for than its mats, under its own heading after the auction house's", function()
    learned()
    put(gear(0, 1, 501, { vendorUnit = 190000 }))
    put(gear(0, 2, 502, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    put(gear(0, 3, 503))
    put(gear(0, 4, 504, { quality = 4, vendorUnit = 99990000 }))
    slash()
    -- The epic's mats are unknown: it stays, that is how GoldCap learns.
    assert.same({ 503, 504 }, listed())
    local f = DF._frame
    assert.equal("LEFT OUT: A VENDOR PAYS MORE", textOf(f.vendorTitle))
    local row = DF._vendorRows[1]
    assert.is_true(row:IsShown())
    assert.equal(501, row.itemID)
    assert.equal("Vendor 19g, mats about 2g", (textOf(row.note):gsub("|T.-|t", "g")))
    assert.equal("Disenchant anyway", textOf(row.anyway.text))
    -- In the scroll, under the auction house's box.
    assert.equal(f.content, at(f.vendorBox)[2])
    assert.is_true(-at(f.vendorBox)[5] >= -at(f.leftBox)[5] + f.leftBox:GetHeight())
    -- No mark on its bag slot, and its tooltip says why it is out.
    openBags()
    assert.is_false(drawn("0:1", "icon"))
    assert.is_false(drawn("0:1", "coin"))
    assert.equal("leftVendor", DF.Standing(slotButtons["0:1"], 501).state)
    press(row.anyway)
    nextFrame()
    assert.same({ 503, 504, 501 }, listed())
    assert.is_false(f.vendorBox:IsShown())
  end)

  -- Valdrakken Guards Belt carries the game's NO_DISENCHANT flag; the client refused it with "That
  -- item is not a valid target." after Disenchant anyway (the owner, 2026-10-26).
  it("never offers gear the game will not disenchant: no line, no mark, and its tooltip says so", function()
    helper.loadModule("Data/NoDisenchant.lua", GC)
    learned()
    put(gear(0, 1, 199762, { quality = 3, vendorUnit = 100 }))
    put(gear(0, 2, 199762, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    put(gear(0, 3, 199762, { vendorUnit = 190000 }))
    put(gear(0, 4, 501))
    openBags()
    slash()
    assert.same({ 501 }, listed())
    assert.is_false(DF._frame.leftBox:IsShown())
    assert.is_false(DF._frame.vendorBox:IsShown())
    for slot = 1, 3 do
      assert.is_false(drawn("0:" .. slot, "icon"))
      assert.is_false(drawn("0:" .. slot, "coin"))
      assert.equal("cant", DF.Standing(slotButtons["0:" .. slot], 199762).state)
    end
    -- Nothing to try again: the Kept line does not count it.
    assert.is_false(DF._frame.kept.text:IsShown())
  end)

  it("names no vendor figure for an item a vendor will not buy", function()
    put(gear(0, 1, 501, { vendorUnit = 0 }))
    slash()
    assert.equal("", textOf(rowOf(501).vendor))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Choosing the next item (the owner, 2026-10-26)
  -- ---------------------------------------------------------------------------------------------

  it("makes a line the Next item on a left click: the card, the button and the bag ring follow, nothing is cast", function()
    learned()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502, { quality = 3 }))
    openBags()
    slash()
    assert.same({ 502, 501 }, listed())
    menu = nil
    press(rowOf(501), "LeftButton")
    nextFrame()
    assert.same({ 501, 502 }, listed())
    assert.equal("Item 501", textOf(DF._frame.card.name))
    assert.equal("1 of 2", textOf(DF._frame.card.counter))
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
    assert.is_true(drawn("0:1", "glow"))
    assert.is_false(drawn("0:2", "glow"))
    assert.equal("next", DF.Standing(slotButtons["0:1"], 501).state)
    assert.same({}, S.casts)
    assert.is_nil(menu)
  end)

  it("keeps the chosen item first as the bags change, until another is chosen or it is skipped", function()
    learned()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502, { quality = 3 }))
    put(gear(0, 3, 503, { quality = 3 }))
    slash()
    press(rowOf(501), "LeftButton")
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.same({ 501, 502, 503 }, listed())
    press(rowOf(503), "LeftButton")
    assert.same({ 503, 502, 501 }, listed())
    press(DF._frame.card.skip)
    nextFrame()
    assert.same({ 502, 501 }, listed())
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
  end)

  it("queues a left-out line's item as the Next one on a left click, from either list", function()
    learned()
    put(gear(0, 1, 501, { vendorUnit = 190000 }))
    put(gear(0, 2, 502, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    put(gear(0, 3, 503))
    slash()
    press(DF._vendorRows[1], "LeftButton")
    assert.same({ 501, 503 }, listed())
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
    press(DF._leftRows[1], "LeftButton")
    assert.same({ 502, 503, 501 }, listed())
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
  end)

  it("changes nothing on a left click in combat, then or after the fight", function()
    learned()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502, { quality = 3 }))
    slash()
    S.enterCombat()
    event("PLAYER_REGEN_DISABLED")
    press(rowOf(501), "LeftButton")
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    nextFrame()
    assert.same({ 502, 501 }, listed())
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
    assert.same({}, S.casts)
  end)

  it("lights a line under the cursor and takes left and right clicks on it", function()
    learned()
    put(gear(0, 1, 501, { vendorUnit = 190000 }))
    put(gear(0, 2, 502, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    put(gear(0, 3, 503))
    slash()
    for _, row in ipairs({ rowOf(503), DF._leftRows[1], DF._vendorRows[1] }) do
      assert.equal("HIGHLIGHT", W.state(row.hover).layer)
      assert.same({ "LeftButtonUp", "RightButtonUp" }, W.state(row).clicks)
    end
  end)

  it("says in a left-out item's note how many sell a day, or that it sells slowly", function()
    learned()
    put(gear(0, 1, 501, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    put(gear(0, 2, 503, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    put(gear(0, 3, 504, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    sales[501], sales[503] = 3, 0.4
    slash()
    local notes = {}
    for _, row in ipairs(DF._leftRows) do notes[row.itemID] = textOf(row.note) end
    assert.truthy(notes[501]:find("Mats: about", 1, true))
    assert.truthy(notes[501]:find("Sells about 3 a day", 1, true))
    assert.truthy(notes[503]:find("Slow seller", 1, true))
    assert.is_nil(notes[504]:find("Sells about", 1, true))
    assert.is_nil(notes[504]:find("Slow seller", 1, true))
  end)

  it("drops an item saved into an equipment set while the window is open", function()
    local first = put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    first.inSet = true
    event("EQUIPMENT_SETS_CHANGED")
    nextFrame()
    assert.same({ 502 }, listed())
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
  end)

  it("writes Disenchant under GoldCap in its header, as the approved board does", function()
    put(gear(0, 1, 501))
    slash()
    local f = DF._frame
    assert.equal("GoldCap", textOf(f.brand))
    assert.equal("Disenchant", textOf(f.title))
    local p = at(f.title)
    assert.equal("TOPLEFT", p[1])
    assert.equal(f.brand, p[2])
    assert.equal("BOTTOMLEFT", p[3])
  end)

  it("says on the card what pays more", function()
    learned()
    put(gear(0, 1, 501, { vendorUnit = 190000 }))
    slash()
    local function coins(fs) return (textOf(fs):gsub("|T.-|t", "g")) end
    press(DF._vendorRows[1].anyway)
    nextFrame()
    assert.equal("A vendor pays more: 19g against about 2g in mats.", coins(DF._frame.card.verdict))
    put(gear(0, 2, 502, { quality = 3, vendorUnit = 10000 }))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.equal("Mats pay more: about 9g against 1g from a vendor.", coins(DF._frame.card.verdict))
    -- No vendor buys it: the mats alone.
    take(DF._plan.queue[1].stack)
    put(gear(0, 3, 503, { quality = 3, vendorUnit = 0 }))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.equal("Mats: about 9g", coins(DF._frame.card.verdict))
  end)

  -- The owner, 23:19: after the mail, all seven items a vendor paid more for, and the card said
  -- there was nothing in the bags to disenchant.
  it("says why nothing is queued when everything is left out", function()
    learned()
    put(gear(0, 1, 501, { vendorUnit = 190000 }))
    slash()
    assert.equal("Nothing worth disenchanting now: a vendor pays more for everything below.",
      textOf(DF._frame.card.name))
    put(gear(0, 2, 502, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.equal("Nothing worth disenchanting now: everything below sells for more.", textOf(DF._frame.card.name))
    take(DF._plan.left[1].stack)
    take(DF._plan.leftVendor[1].stack)
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.equal("Nothing in your bags to disenchant.", textOf(DF._frame.card.name))
  end)

  -- The owner, 23:19: with nothing to press, Disenchant looked live. It takes the kit's disabled look
  -- (UI/Kit/Button.lua: grey words, no wash under the cursor), never by Disable(), and Skip is
  -- disabled.
  it("makes Disenchant look disabled with nothing to press, and disables Skip", function()
    local K = GC.Kit.Tokens.color
    local function rgb(c) return { c[1], c[2], c[3] } end
    local b
    slash()
    b = button()
    assert.same(rgb(K.text3), rgb(W.state(b.text).color))
    assert.is_false(b.wash:IsShown())
    -- No pressed shade under a click either (the re-review's N4): the engine still shows the pushed
    -- texture of an enabled button.
    assert.equal(0, W.state(b.held).alpha)
    assert.is_true(b:IsEnabled())
    assert.is_false(DF._frame.card.skip:IsEnabled())
    put(gear(0, 1, 501))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.are_not.same(rgb(K.text3), rgb(W.state(b.text).color))
    assert.is_true(b.wash:IsShown())
    assert.equal(1, W.state(b.held).alpha)
    assert.is_true(b:IsEnabled())
    assert.is_true(DF._frame.card.skip:IsEnabled())
  end)

  it("says GoldCap learns it the first time with nothing learned, and invents no mats", function()
    put(gear(0, 1, 501))
    slash()
    assert.equal("GoldCap learns what this gives the first time.", textOf(DF._frame.card.verdict))
    assert.equal("GoldCap learns what these give as you disenchant.", textOf(DF._frame.strip.label))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Combat
  -- ---------------------------------------------------------------------------------------------

  it("touches nothing protected in combat, and catches up after it", function()
    local first = put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.enterCombat()
    event("PLAYER_REGEN_DISABLED")
    assert.is_false(button():IsShown())
    take(first)
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    slash()
    -- The fake raises on any Show, Hide, SetPoint, size or SetAttribute of the window or the button
    -- in combat: getting here means none was made. The window still names what the button holds.
    assert.is_true(windowUp())
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    nextFrame()
    assert.is_true(button():IsShown())
    -- The /gc disenchant typed in combat closes it now.
    assert.is_false(windowUp())
  end)

  it("repaints after combat what the bags did meanwhile", function()
    local first = put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.enterCombat()
    take(first)
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    nextFrame()
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
    assert.same({ 502 }, listed())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The key binding
  -- ---------------------------------------------------------------------------------------------

  it("names the key binding in the player's language once the addon has loaded", function()
    event("PLAYER_LOGIN")
    assert.equal("Disenchant next", _G["BINDING_NAME_CLICK GoldCapDisenchantNext:LeftButton"])
  end)

  it("opens the window on a key press while it is closed, and casts nothing with it", function()
    put(gear(0, 1, 501))
    event("PLAYER_LOGIN")
    assert.is_not_nil(button())
    S.key(button())
    nextFrame()
    assert.same({}, S.casts)
    assert.is_true(windowUp())
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
  end)

  -- A key bound to the button still clicks it while the driver hides it, and in combat the button
  -- cannot be cleared: so it is pointed at nothing as the fight begins, if the client still lets it
  -- (PLAYER_REGEN_DISABLED before the lockdown), and at the next item once the fight is over.
  it("points its button at nothing as a fight begins, and at the next item once it is over", function()
    put(gear(0, 1, 501))
    slash()
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
    event("PLAYER_REGEN_DISABLED")
    S.enterCombat()
    S.key(button())
    assert.same({}, S.casts)
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    nextFrame()
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
  end)

  -- The fight began before its own PLAYER_REGEN_DISABLED (or a paint ran in between), so the
  -- button still points at 0:3; in the fight the player equips the named weapon from the bags and
  -- the old one lands in 0:3. The secure drivers make the button's left click and its target slot
  -- nothing in combat, so the key casts nothing and aims no waiting spell at the slot.
  it("casts nothing on a key press in combat, though it was armed and the slot changed", function()
    local first = put(gear(0, 3, 501))
    put(gear(0, 4, 502, { vendorUnit = 20000 }))
    slash()
    assert.same({ "spell", 13262, 0, 3 }, armedAt())
    S.enterCombat()
    event("PLAYER_REGEN_DISABLED")
    take(first)
    slots["0:3"] = { itemID = 778, hyperlink = "|Hitem:778|h[Old weapon]|h", stackCount = 1 }
    S.key(button())
    assert.same({}, S.casts)
    -- Another spell of the player's own waiting for an item is not aimed at the slot either.
    S.awaiting = true
    S.key(button())
    assert.same({}, S.targets)
    S.awaiting = nil
    -- Once the fight is over the button's own attributes act again.
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    nextFrame()
    assert.same({ "spell", 13262, 0, 4 }, armedAt())
    S.click(button())
    assert.same({ { spell = 13262, bag = 0, slot = 4 } }, S.casts)
  end)

  it("does not arm again between its PLAYER_REGEN_DISABLED and the lockdown", function()
    put(gear(0, 1, 501))
    slash()
    event("BAG_UPDATE_DELAYED")
    fighting = true
    event("PLAYER_REGEN_DISABLED")
    nextFrame()
    assert.same({}, armedAt())
    S.enterCombat()
    S.key(button())
    assert.same({}, S.casts)
  end)

  -- A fight that ended without the PLAYER_REGEN_ENABLED this window heard (not measured: across a
  -- loading screen, say): once neither the client's lockdown nor the player's combat says it goes
  -- on, a bag change paints and arms again.
  it("takes a fight as over once the client says so, though PLAYER_REGEN_ENABLED never came", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    fighting = true
    event("PLAYER_REGEN_DISABLED")
    assert.same({}, armedAt())
    fighting = false
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
  end)

  it("records no press in combat, so a cast then is not taken for its own", function()
    put(gear(0, 1, 501))
    slash()
    S.enterCombat()
    S.key(button())
    event("UNIT_SPELLCAST_START", "player", "Cast-1", 13262)
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    nextFrame()
    assert.equal("Next", textOf(DF._frame.card.label))
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
  end)

  it("does not open the window after the fight for a key pressed during it", function()
    put(gear(0, 1, 501))
    event("PLAYER_LOGIN")
    S.enterCombat()
    S.key(button())
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    nextFrame()
    assert.is_false(windowUp())
  end)

  it("builds its button once the fight is over for a character who logged in during one", function()
    put(gear(0, 1, 501))
    S.enterCombat()
    event("PLAYER_LOGIN")
    assert.is_nil(_G.GoldCapDisenchantNext)
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    assert.is_not_nil(button())
  end)

  it("closes the window, its button pointed at nothing, once the character no longer knows Disenchant", function()
    put(gear(0, 1, 501))
    slash()
    assert.same({ "spell", 13262, 0, 1 }, armedAt())
    knows = false
    event("SPELLS_CHANGED")
    nextFrame()
    assert.is_false(windowUp())
    assert.same({}, armedAt())
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Marks on the bag slots
  -- ---------------------------------------------------------------------------------------------

  it("marks each queued slot with the spell's icon, the first with a glow, a left-out one with a coin", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    put(gear(0, 3, 503, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    put(gear(0, 4, 504, { quality = 1 }))
    openBags()
    assert.is_true(drawn("0:1", "icon"))
    assert.equal(136244, W.state(overlayOf("0:1").icon).file)
    assert.is_true(drawn("0:1", "glow"))
    assert.is_true(drawn("0:2", "icon"))
    assert.is_false(drawn("0:2", "glow"))
    assert.is_false(drawn("0:3", "icon"))
    assert.is_true(drawn("0:3", "coin"))
    assert.is_false(drawn("0:1", "coin"))
    assert.is_nil(overlayOf("0:4"))
    assert.is_nil(overlayOf("0:5"))
  end)

  it("moves the glow to the next item when one is skipped", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    openBags()
    slash()
    press(DF._frame.card.skip)
    assert.is_false(drawn("0:1", "icon"))
    assert.is_true(drawn("0:2", "glow"))
  end)

  it("marks nothing for a character without Disenchant", function()
    knows = false
    put(gear(0, 1, 501))
    openBags()
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.is_nil(overlayOf("0:1"))
  end)

  it("takes the marks off when the bags close, and when nothing is left to disenchant", function()
    local only = put(gear(0, 1, 501))
    openBags()
    assert.is_true(drawn("0:1", "icon"))
    bags:Hide()
    W.state(bags).hooks.OnHide(bags)
    nextFrame()
    assert.is_false(drawn("0:1", "icon"))
    openBags()
    assert.is_true(drawn("0:1", "icon"))
    take(only)
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.is_false(drawn("0:1", "icon"))
    assert.is_false(drawn("0:1", "glow"))
  end)

  it("takes the marks off a character that no longer knows Disenchant", function()
    put(gear(0, 1, 501))
    openBags()
    knows = false
    event("SPELLS_CHANGED")
    nextFrame()
    assert.is_false(drawn("0:1", "icon"))
  end)

  it("paints the marks from the plan the window reads: one read of the bags a paint", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    openBags()
    local before = reads
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.equal(before + 1, reads)
    slash()
    before = reads
    press(DF._frame.card.skip)
    assert.equal(before + 1, reads)
  end)

  it("draws on its own overlay, never on Blizzard's button", function()
    put(gear(0, 1, 501))
    openBags()
    local slot = slotButtons["0:1"]
    assert.is_nil(next(W.state(slot).scripts))
    assert.is_nil(W.state(slot).hooks)
    assert.equal(0, #W.state(slot).points)
    assert.is_true(slot:IsShown())
    assert.is_false(overlayOf("0:1"):IsMouseEnabled())
  end)

  it("follows the bags in combat with what it last read, dropping a slot that no longer holds the item", function()
    local first = put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    openBags()
    S.enterCombat()
    event("PLAYER_REGEN_DISABLED")
    take(first)
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.is_false(drawn("0:1", "icon"))
    assert.is_true(drawn("0:2", "icon"))
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    nextFrame()
    assert.is_true(drawn("0:2", "glow"))
  end)

  it("makes an overlay in combat for a bag frame that opens then: the item button is not protected", function()
    put(gear(0, 1, 501))
    openBags()
    S.enterCombat()
    event("PLAYER_REGEN_DISABLED")
    local list = giveButtons(_G.ContainerFrame1, 0, 3)
    _G.ContainerFrame1:Show()
    W.state(_G.ContainerFrame1).hooks.OnShow(_G.ContainerFrame1)
    nextFrame()
    assert.is_true((list[1]:GetChildren()):IsShown())
  end)

  it("puts the ring back on the first item when the window opens again after a Skip", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    openBags()
    slash()
    press(DF._frame.card.skip)
    assert.is_true(drawn("0:2", "glow"))
    slash()
    assert.is_false(windowUp())
    slash()
    assert.is_true(windowUp())
    assert.is_true(drawn("0:1", "glow"))
    assert.is_false(drawn("0:2", "glow"))
    assert.equal("next", DF.Standing(slotButtons["0:1"], 501).state)
  end)

  -- A bag frame and its buttons that Blizzard hands to another bag (ContainerFrame_GetOpenFrame).
  local function reusedFrame(container, bagOf)
    local slotButton = CreateFrame("Button", nil, container)
    slotButton:SetID(1)
    slotButton.GetBagID = function() return bagOf() end
    function container:EnumerateValidItems()
      return function(_, i) if i == 0 then return 1, slotButton end end, self, 0
    end
    return slotButton
  end
  local function shows(container)
    container:Show()
    W.state(container).hooks.OnShow(container)
    nextFrame()
  end

  it("leaves no mark on a bag frame Blizzard reuses for another bag", function()
    put(gear(2, 1, 502))
    put(gear(4, 1, 504, { quality = 1 }))
    put(gear(0, 1, 501))
    local bag = 2
    local second = reusedFrame(_G.ContainerFrame2, function() return bag end)
    giveButtons(_G.ContainerFrame1, 0, 2)
    shows(_G.ContainerFrame1)
    shows(_G.ContainerFrame2)
    assert.is_true((second:GetChildren()):IsShown())
    _G.ContainerFrame2:Hide()
    W.state(_G.ContainerFrame2).hooks.OnHide(_G.ContainerFrame2)
    nextFrame()
    -- The pass that no longer visits the closed bag takes its mark off (DisenchantMarks.Paint's sweep).
    assert.is_false((second:GetChildren()):IsShown())
    bag = 4
    shows(_G.ContainerFrame2)
    assert.is_false((second:GetChildren()):IsShown())
  end)

  it("marks a bag opened alone, without the backpack", function()
    put(gear(2, 1, 502))
    local second = reusedFrame(_G.ContainerFrame2, function() return 2 end)
    shows(_G.ContainerFrame2)
    assert.is_true((second:GetChildren()):IsShown())
  end)

  -- The marks follow the entry's rule (the owner's E1): drawn whenever Blizzard's bags are open for a
  -- character that knows Disenchant, queue or not, so a left-out item keeps its coin with nothing
  -- queued; in combat too, from the last plan.
  it("keeps the coins with nothing queued, in combat too, and takes them off once Disenchant is not known", function()
    put(gear(0, 1, 503, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    openBags()
    assert.equal(0, #DF._plan.queue)
    assert.is_true(drawn("0:1", "coin"))
    assert.is_false(drawn("0:1", "icon"))
    S.enterCombat()
    event("PLAYER_REGEN_DISABLED")
    bags:Hide()
    W.state(bags).hooks.OnHide(bags)
    nextFrame()
    assert.is_false(drawn("0:1", "coin"))
    openBags()
    assert.is_true(drawn("0:1", "coin"))
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    nextFrame()
    knows = false
    event("SPELLS_CHANGED")
    nextFrame()
    assert.is_false(drawn("0:1", "coin"))
  end)

  it("answers no standing once neither the window nor the bags are open, or when the slot holds another link", function()
    local item = put(gear(0, 1, 501))
    openBags()
    assert.equal("next", DF.Standing(slotButtons["0:1"], 501).state)
    slots["0:1"] = { itemID = 501, hyperlink = "|Hitem:501:other|h[Item 501]|h", stackCount = 1, isLocked = false }
    assert.is_nil(DF.Standing(slotButtons["0:1"], 501))
    slots["0:1"] = { itemID = 501, hyperlink = item.link, stackCount = 1, isLocked = false }
    bags:Hide()
    W.state(bags).hooks.OnHide(bags)
    nextFrame()
    assert.is_nil(DF.Standing(slotButtons["0:1"], 501))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- Where an item stands (the tooltip's words), and the way back for a kept one
  -- ---------------------------------------------------------------------------------------------

  it("says where a bag slot's item stands: next, listed, left out or kept", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    put(gear(0, 3, 503, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    put(gear(0, 4, 504))
    GC.Disenchant.Keep(GC.db, 504)
    openBags()
    local function standing(key, itemID) return DF.Standing(slotButtons[key], itemID) end
    assert.equal("next", standing("0:1", 501).state)
    assert.equal("listed", standing("0:2", 502).state)
    assert.equal("left", standing("0:3", 503).state)
    assert.equal("kept", standing("0:4", 504).state)
    -- Another item than the slot holds, an empty slot and no slot at all: nothing.
    assert.is_nil(standing("0:1", 999))
    assert.is_nil(standing("0:5", 501))
    assert.is_nil(DF.Standing(nil, 501))
    knows = false
    assert.is_nil(standing("0:1", 501))
  end)

  it("gives what its own disenchants of the kind gave, and says nothing learned before that", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502, { quality = 3 }))
    GC.Disenchant.Keep(GC.db, 503)
    put(gear(0, 3, 503))
    prices[DUST] = 1000
    GC.Disenchant.Learn(GC.db, "q2:x11", { [DUST] = 4 })
    GC.Disenchant.Learn(GC.db, "q2:x11", { [DUST] = 2 })
    openBags()
    local first, other, kept = DF.Standing(slotButtons["0:1"], 501), DF.Standing(slotButtons["0:2"], 502),
      DF.Standing(slotButtons["0:3"], 503)
    assert.equal(3 * math.floor(1000 * GC.VendorSelect.KEEP), first.mats)
    assert.equal(2, first.n)
    assert.equal(first.mats, kept.mats)
    assert.is_nil(other.mats)
    assert.equal(0, other.n)
  end)

  it("shows no Kept line with nothing kept", function()
    put(gear(0, 1, 501))
    slash()
    assert.is_false(DF._frame.kept.text:IsShown())
    assert.is_false(DF._frame.kept.show:IsShown())
  end)

  it("says how many are kept and lists them in a menu, each with a way back onto the list", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    press(rowOf(501), "RightButton")
    menu.buttons[1].fn()
    nextFrame()
    assert.same({ 502 }, listed())
    assert.is_true(DF._frame.kept.text:IsShown())
    assert.equal("Kept: 1 item", textOf(DF._frame.kept.text))
    press(DF._frame.kept.show)
    assert.equal("title", menu.entries[1].kind)
    assert.equal("Never disenchanted", menu.entries[1].text)
    assert.is_truthy(menu.entries[2].text:find("Item 501", 1, true))
    assert.is_truthy(menu.entries[2].text:find("Disenchant it again", 1, true))
    assert.same({}, menu.entries[2].buttons)
    menu.entries[2].fn()
    nextFrame()
    assert.is_false(GC.Disenchant.Kept(GC.db, 501))
    assert.same({ 501, 502 }, listed())
    assert.is_false(DF._frame.kept.text:IsShown())
  end)

  -- After days of play the stored sets hold many items the bags no longer do (the owner,
  -- 2026-10-26): the line and its menu are about the bags as they are.
  it("counts and lists only the kept and refused items the bags hold, each set apart, the store kept whole", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    put(gear(0, 3, 503))
    GC.Disenchant.Keep(GC.db, 502)
    GC.Disenchant.Keep(GC.db, 777)
    GC.Disenchant.MarkCant(GC.db, 503)
    GC.Disenchant.MarkCant(GC.db, 888)
    slash()
    assert.equal("Kept: 2 items", textOf(DF._frame.kept.text))
    press(DF._frame.kept.show)
    local kinds, texts = {}, {}
    for i, e in ipairs(menu.entries) do kinds[i], texts[i] = e.kind, e.text end
    assert.same({ "title", "button", "divider", "title", "button" }, kinds)
    assert.equal("Never disenchanted", texts[1])
    assert.is_truthy(texts[2]:find("Item 502", 1, true))
    assert.equal("GoldCap could not disenchant these", texts[4])
    assert.is_truthy(texts[5]:find("Item 503", 1, true))
    assert.same({ 502, 777 }, GC.Disenchant.KeptIDs(GC.db))
    assert.same({ 503, 888 }, GC.Disenchant.CantIDs(GC.db))
  end)

  it("hides the Kept line while the bags hold none of the kept items, and shows it once one is back", function()
    put(gear(0, 1, 501))
    GC.Disenchant.Keep(GC.db, 777)
    GC.Disenchant.MarkCant(GC.db, 888)
    slash()
    assert.is_false(DF._frame.kept.text:IsShown())
    assert.is_false(DF._frame.kept.show:IsShown())
    put(gear(0, 2, 777))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.is_true(DF._frame.kept.text:IsShown())
    assert.equal("Kept: 1 item", textOf(DF._frame.kept.text))
  end)

  it("scrolls the Kept menu past about twelve lines, so it never runs off the screen", function()
    for slot = 1, 20 do
      put(gear(1, slot, 600 + slot))
      GC.Disenchant.Keep(GC.db, 600 + slot)
    end
    put(gear(0, 1, 501))
    slash()
    press(DF._frame.kept.show)
    assert.equal(DF.MENU_ROWS * DF.MENU_ROW_H, menu.scroll)
    assert.equal(21, #menu.entries)
  end)

  it("keeps the Kept line inside the window, above the footer", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 777))
    GC.Disenchant.Keep(GC.db, 777)
    slash()
    local kept, footer = at(DF._frame.kept.text), at(DF._frame.footer)
    assert.is_true(kept[5] > footer[5])
  end)
  -- ---------------------------------------------------------------------------------------------
  -- Where it stands, and how tall (the owner's screenshot, 2026-10-26)
  -- ---------------------------------------------------------------------------------------------

  -- Where a frame stands on the screen, as the client answers it: its left and top edges and its
  -- effective scale.
  local function standAt(f, left, top, scale)
    function f:GetLeft() return left end
    function f:GetTop() return top end
    function f:GetEffectiveScale() return scale or 1 end
  end

  local function screen(w, h)
    _G.UIParent:SetSize(w, h)
    function _G.UIParent:GetEffectiveScale() return 1 end
  end

  it("stands above the action bars and Blizzard's bags, under menus and tooltips", function()
    put(gear(0, 1, 501))
    slash()
    assert.equal("HIGH", W.state(DF._frame).strata)
  end)

  it("opens left of the leftmost bag that shows, level with the highest, and moves when one shows or hides", function()
    screen(1920, 1080)
    standAt(bags, 1300, 1000)
    local reagent = _G.ContainerFrame6
    standAt(reagent, 1050, 600)
    put(gear(0, 1, 501))
    openBags()
    reagent:Show()
    slash()
    assert.same({ "TOPRIGHT", _G.UIParent, "BOTTOMLEFT", 1046, 1000 }, at(DF._frame))
    reagent:Hide()
    W.state(reagent).hooks.OnHide(reagent)
    nextFrame()
    assert.same({ "TOPRIGHT", _G.UIParent, "BOTTOMLEFT", 1296, 1000 }, at(DF._frame))
    reagent:Show()
    W.state(reagent).hooks.OnShow(reagent)
    nextFrame()
    assert.same({ "TOPRIGHT", _G.UIParent, "BOTTOMLEFT", 1046, 1000 }, at(DF._frame))
  end)

  it("moves in combat only once the fight is over", function()
    screen(1920, 1080)
    standAt(bags, 1300, 1000)
    local reagent = _G.ContainerFrame6
    standAt(reagent, 1050, 600)
    put(gear(0, 1, 501))
    openBags()
    slash()
    S.enterCombat()
    reagent:Show()
    W.state(reagent).hooks.OnShow(reagent)
    nextFrame()
    assert.same({ "TOPRIGHT", _G.UIParent, "BOTTOMLEFT", 1296, 1000 }, at(DF._frame))
    S.leaveCombat()
    event("PLAYER_REGEN_ENABLED")
    nextFrame()
    assert.same({ "TOPRIGHT", _G.UIParent, "BOTTOMLEFT", 1046, 1000 }, at(DF._frame))
  end)

  it("stays where it is when the last bag closes", function()
    screen(1920, 1080)
    standAt(bags, 1300, 1000)
    put(gear(0, 1, 501))
    openBags()
    slash()
    bags:Hide()
    W.state(bags).hooks.OnHide(bags)
    nextFrame()
    assert.same({ "TOPRIGHT", _G.UIParent, "BOTTOMLEFT", 1296, 1000 }, at(DF._frame))
  end)

  -- Separate bags stack 8 apart (ContainerFrame.lua:10, :1236): the entry stands above the highest
  -- that shows, so it covers no slot of the bag above the first (the final review's M3); in combat
  -- too, as it follows the bags.
  it("stands the entry above the highest of the bags that show", function()
    screen(1920, 1080)
    local backpack, second = _G.ContainerFrame1, _G.ContainerFrame2
    standAt(backpack, 1500, 400)
    standAt(second, 1500, 700)
    put(gear(0, 1, 501))
    backpack:Show()
    second:Show()
    W.state(second).hooks.OnShow(second)
    nextFrame()
    assert.is_true(entryUp())
    assert.same({ "BOTTOMRIGHT", second, "TOPRIGHT", 0, 4 }, at(DF._entry))
    S.enterCombat()
    event("PLAYER_REGEN_DISABLED")
    second:Hide()
    W.state(second).hooks.OnHide(second)
    nextFrame()
    assert.same({ "BOTTOMRIGHT", backpack, "TOPRIGHT", 0, 4 }, at(DF._entry))
  end)

  -- A full column of separate bags reaches the screen's top (UpdateContainerFrameAnchors,
  -- ContainerFrame.lua:1212-1240, subtracts frame heights only): with no room above the highest bag
  -- the clamp would push the entry onto its close button, so it stands left of that bag's top left
  -- (the re-review's N1); in combat too.
  it("stands the entry left of the highest bag when the screen leaves no room above it", function()
    screen(1920, 1080)
    local backpack, second = _G.ContainerFrame1, _G.ContainerFrame2
    standAt(backpack, 1500, 700)
    standAt(second, 1500, 1060)
    put(gear(0, 1, 501))
    backpack:Show()
    second:Show()
    W.state(second).hooks.OnShow(second)
    nextFrame()
    assert.is_true(entryUp())
    assert.same({ "TOPRIGHT", second, "TOPLEFT", -4, 0 }, at(DF._entry))
    S.enterCombat()
    event("PLAYER_REGEN_DISABLED")
    second:Hide()
    W.state(second).hooks.OnHide(second)
    nextFrame()
    assert.same({ "BOTTOMRIGHT", backpack, "TOPRIGHT", 0, 4 }, at(DF._entry))
    second:Show()
    W.state(second).hooks.OnShow(second)
    nextFrame()
    assert.same({ "TOPRIGHT", second, "TOPLEFT", -4, 0 }, at(DF._entry))
  end)

  -- Sixteen and more items: the window keeps to about 85% of the screen's height, "In this order"
  -- scrolls, and the card, the strip, "Left out" and the footer stand outside the scroll.
  -- Twenty queued and twenty left out on a 768-high screen: the two lists share the scroll, and the
  -- card with its Disenchant button, the Kept line and the footer stay on the screen.
  it("keeps to 85% of a small screen with many items left out, the two lists sharing the scroll", function()
    W.CLIENT_METRICS = true
    finally(function() W.CLIENT_METRICS = false end)
    screen(1366, 768)
    standAt(bags, 1000, 740)
    for slot = 1, 20 do put(gear(1, slot, 600 + slot)) end
    for slot = 1, 20 do
      put(gear(2, slot, 700 + slot, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    end
    put(gear(3, 1, 999))
    GC.Disenchant.Keep(GC.db, 999)
    openBags()
    slash()
    local f = DF._frame
    local height = f:GetHeight()
    assert.is_true(height <= math.floor(768 * 0.85), ("the window is %d tall"):format(height))
    -- The window hangs from the bags' top: its foot stays on the screen.
    local top = at(f)[5]
    assert.is_true(top <= 768 and top - height >= 0)
    -- The card, with the Disenchant button in it, stands inside the window.
    local card = at(f.card)
    assert.is_true(-card[5] + f.card:GetHeight() <= height)
    local cast = at(f.card.cast)
    assert.is_true(-cast[5] + f.card.cast:GetHeight() <= f.card:GetHeight())
    -- The Kept line and the footer, from the window's foot.
    local kept = at(f.kept.text)
    assert.is_true(f.kept.text:IsShown() and kept[5] + f.kept.text:GetHeight() <= height)
    assert.is_true(at(f.footer)[5] + f.footer:GetHeight() <= height)
    -- Both lists in the scroll's child, the last "Left out" line inside it.
    local last = DF._leftRows[20]
    assert.is_true(last:IsShown())
    local y, p = 0, last
    while p and p ~= f.content do
      y = y - (at(p)[5] or 0)
      p = p:GetParent()
    end
    assert.equal(f.content, p)
    assert.is_true(y + last:GetHeight() <= f.content:GetHeight())
    assert.is_true(f.content:GetHeight() > f.scroll:GetHeight())
  end)

  it("keeps to 85% of the screen with a long queue, its lines scrolling and the rest in view", function()
    -- Text measured as the client does, so a line is as tall as one line of words and a money figure
    -- as wide as its digits and coin.
    W.CLIENT_METRICS = true
    finally(function() W.CLIENT_METRICS = false end)
    screen(1920, 1000)
    standAt(bags, 1300, 1000)
    for slot = 1, 30 do put(gear(1, slot, 600 + slot)) end
    put(gear(0, 1, 501, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    openBags()
    slash()
    local f = DF._frame
    assert.is_true(f:GetHeight() <= 850, ("the window is %d tall"):format(f:GetHeight()))
    assert.is_true(f.content:GetHeight() > f.scroll:GetHeight())
    assert.is_true(f.scroll:GetHeight() >= 28)
    local left = DF._leftRows[1]
    assert.is_true(left:IsShown())
    local p = left
    while p and p ~= f.content and p ~= f do p = p:GetParent() end
    assert.equal(f.content, p)
    assert.equal(f, f.orderTitle:GetParent())
  end)
  -- ---------------------------------------------------------------------------------------------
  -- Materials nobody can sell, and the counts the strip writes (the owner's screenshots, 2026-10-26)
  -- ---------------------------------------------------------------------------------------------

  -- Swirling Arcane Essence binds on pickup: it adds nothing to what a disenchant is worth, and the
  -- total stays known.
  it("counts a material that binds on pickup as worth nothing, not unknown", function()
    GC.Disenchant.Learn(GC.db, "q2:x11", { [DUST] = 2, [ESSENCE] = 1 })
    prices[DUST] = 10000
    put(gear(0, 1, 501))
    slash()
    assert.equal(2 * 9500, DF._plan.queue[1].mats)
  end)

  it("keeps a tradeable material with no price unknown", function()
    GC.Disenchant.Learn(GC.db, "q2:x11", { [DUST] = 2, [SHARD] = 1 })
    prices[DUST] = 10000
    put(gear(0, 1, 501))
    slash()
    assert.is_nil(DF._plan.queue[1].mats)
  end)

  it("asks the client about a material it has not loaded yet, and prices it once it has", function()
    GC.Disenchant.Learn(GC.db, "q2:x11", { [DUST] = 2, [ESSENCE] = 1 })
    prices[DUST] = 10000
    uncached[ESSENCE] = true
    put(gear(0, 1, 501))
    slash()
    assert.is_nil(DF._plan.queue[1].mats)
    assert.is_truthy(table.concat(requested, ","):find(tostring(ESSENCE), 1, true))
    uncached[ESSENCE] = nil
    event("ITEM_DATA_LOAD_RESULT", ESSENCE, true)
    nextFrame()
    assert.equal(2 * 9500, DF._plan.queue[1].mats)
  end)

  it("asks once about a material the client fails to load, and keeps it unknown", function()
    GC.Disenchant.Learn(GC.db, "q2:x11", { [DUST] = 2, [ESSENCE] = 1 })
    prices[DUST] = 10000
    uncached[ESSENCE] = true
    put(gear(0, 1, 501))
    slash()
    event("ITEM_DATA_LOAD_RESULT", ESSENCE, false)
    nextFrame()
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    local asked = 0
    for _, id in ipairs(requested) do
      if id == ESSENCE then asked = asked + 1 end
    end
    assert.equal(1, asked)
    assert.is_nil(DF._plan.queue[1].mats)
  end)

  it("writes whole counts in the strip: ~1 for half a material, <1 for less", function()
    GC.Disenchant.Learn(GC.db, "q2:x11", { [DUST] = 1 })
    for _ = 1, 3 do GC.Disenchant.Learn(GC.db, "q2:x11", { [SHARD] = 1 }) end
    put(gear(0, 1, 501))
    slash()
    local chips = DF._frame.strip.chips
    assert.equal("<1", textOf(chips[1].count))
    assert.equal("~1", textOf(chips[2].count))
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The item's tooltip, over a line and over the card (the owner's screenshots, 2026-10-26)
  -- ---------------------------------------------------------------------------------------------

  local function ourTip()
    for _, t in ipairs(tips) do
      if t.state.template == "GameTooltipTemplate" then return t.frame, t.state end
    end
  end

  it("shows a line's own bag item in GoldCap's tooltip, beside the window away from the bags, with no comparison", function()
    screen(1920, 1080)
    standAt(bags, 1300, 1000)
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    openBags()
    slash()
    local row = rowOf(502)
    W.state(row).scripts.OnEnter(row)
    local tip, st = ourTip()
    assert.is_not_nil(tip)
    assert.equal(row, st.owner)
    assert.equal(0, st.bag)
    assert.equal(2, st.slot)
    local p = W.state(tip).points[1]
    assert.equal("TOPRIGHT", p[1])
    assert.equal(DF._frame, p[2])
    assert.equal("TOPLEFT", p[3])
    assert.same({}, compared)
    -- GoldCap's lines (the Disenchant status among them) read the line as the bag slot it stands for.
    assert.equal("listed", DF.Standing(row, 502).state)
  end)

  it("hands the item to Blizzard's GameTooltip while Shift is held, so Blizzard compares it, and calls no comparison itself", function()
    put(gear(0, 1, 501))
    slash()
    local row = rowOf(501)
    local game = _G.GameTooltip
    W.state(row).scripts.OnEnter(row)
    local tip = ourTip()
    assert.is_true(tip:IsShown())
    assert.is_false(game:IsOwned(row))
    shift = true
    event("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    assert.is_false(tip:IsShown())
    assert.is_true(game:IsOwned(row))
    assert.is_true(game:IsShown())
    assert.equal("ANCHOR_BOTTOMRIGHT", game.anchor)
    assert.equal(0, game.bag)
    assert.equal(1, game.slot)
    shift = false
    event("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
    assert.is_false(game:IsOwned(row))
    assert.is_true(tip:IsShown())
    -- Hovered with Shift already held: Blizzard's tooltip at once; leaving hides it.
    W.state(row).scripts.OnLeave(row)
    shift = true
    W.state(row).scripts.OnEnter(row)
    assert.is_true(game:IsOwned(row))
    assert.is_false(tip:IsShown())
    W.state(row).scripts.OnLeave(row)
    assert.is_false(game:IsOwned(row))
    -- The card's item too.
    local hit = DF._frame.card.hit
    W.state(hit).scripts.OnEnter(hit)
    assert.is_true(game:IsOwned(hit))
    assert.same({}, blocked)
    assert.same({}, compared)
    assert.same({}, cleared)
  end)

  -- Owned with ANCHOR_NONE, Blizzard's comparison took the side with more room, over the list (the
  -- re-review's S1: TooltipComparisonManager.lua:91-100 keeps to an owner's LEFT or RIGHT anchor).
  it("opens Blizzard's tooltip with Shift on the side away from the bags, where its own stands", function()
    screen(1920, 1080)
    standAt(bags, 1300, 1000)
    put(gear(0, 1, 501))
    openBags()
    slash()
    local row = rowOf(501)
    standAt(DF._frame, 900, 1000)
    function DF._frame:GetRight() return 1290 end
    function row:GetLeft() return 916 end
    shift = true
    W.state(row).scripts.OnEnter(row)
    local game = _G.GameTooltip
    assert.is_true(game:IsOwned(row))
    assert.equal("ANCHOR_BOTTOMLEFT", game.anchor)
    -- Its top right 8 left of the window, level with the line's top: as the window's own tooltip.
    assert.equal(900 - 8 - 916, game.x)
    assert.equal(row:GetHeight(), game.y)
    assert.is_nil(game.point)
  end)

  -- With no room for the comparison left of the window, Blizzard would slide it with
  -- SetAnchorType(anchor, slide, 0), dropping the offsets, over the window's edge (the re-review's
  -- T2): the item opens on the window's other side, clear of the list and on the screen.
  it("opens Blizzard's tooltip with Shift on the other side when the comparison has no room on the near one", function()
    screen(1920, 1080)
    standAt(bags, 700, 1000)
    put(gear(0, 1, 501))
    openBags()
    slash()
    local row = rowOf(501)
    standAt(DF._frame, 300, 1000)
    function DF._frame:GetRight() return 690 end
    function row:GetLeft() return 316 end
    function row:GetRight() return 674 end
    shift = true
    W.state(row).scripts.OnEnter(row)
    local game = _G.GameTooltip
    assert.equal("ANCHOR_BOTTOMRIGHT", game.anchor)
    assert.equal(690 + 8 - 674, game.x)
    -- The window's own tooltip, without Shift, keeps to the side away from the bags.
    W.state(row).scripts.OnLeave(row)
    shift = false
    W.state(row).scripts.OnEnter(row)
    assert.equal("TOPRIGHT", W.state(ourTip()).points[1][1])
  end)

  -- A ring, a trinket or a one-hand weapon is compared with both equipped ones: room for three.
  it("counts two equipped items beside a ring, so it turns where a belt still fits", function()
    screen(2560, 1440)
    standAt(bags, 1150, 1000)
    put(gear(0, 1, 501, { equipLoc = "INVTYPE_FINGER" }))
    put(gear(0, 2, 502))
    openBags()
    slash()
    standAt(DF._frame, 800, 1000)
    function DF._frame:GetRight() return 1140 end
    shift = true
    for _, id in ipairs({ 501, 502 }) do
      local row = rowOf(id)
      function row:GetLeft() return 816 end
      function row:GetRight() return 1124 end
      W.state(row).scripts.OnEnter(row)
      assert.equal(id == 501 and "ANCHOR_BOTTOMRIGHT" or "ANCHOR_BOTTOMLEFT", _G.GameTooltip.anchor)
      W.state(row).scripts.OnLeave(row)
    end
  end)

  -- GameTooltip_ShowCompareItem reaches C_TooltipComparison.CompareItem, protected in live and
  -- Forever; TooltipComparisonManager is Blizzard's to drive. No GoldCap path calls either.
  it("names no comparison function of Blizzard's anywhere in GoldCap", function()
    local listing = assert(io.popen("find GoldCap -name '*.lua'"))
    for path in listing:lines() do
      local f = assert(io.open(path, "r"))
      local text = f:read("*a"):gsub("%-%-[^\n]*", "")
      f:close()
      for _, name in ipairs({ "GameTooltip_ShowCompareItem", "TooltipComparisonManager", "C_TooltipComparison" }) do
        assert.is_nil(text:find(name, 1, true), path .. " names " .. name)
      end
    end
    listing:close()
  end)

  it("shows the Next item's tooltip over the card's icon and name, and leaves the Disenchant button alone", function()
    put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    local hit = DF._frame.card.hit
    W.state(hit).scripts.OnEnter(hit)
    local _, st = ourTip()
    assert.equal(0, st.bag)
    assert.equal(1, st.slot)
    assert.is_nil(W.state(button()).scripts.OnEnter)
    assert.is_nil(W.state(button()).scripts.OnLeave)
  end)

  it("shows a line done this visit by its link, its slot holding something else now", function()
    local first = put(gear(0, 1, 501))
    put(gear(0, 2, 502))
    slash()
    S.click(button())
    disenchant("Cast-1", { { DUST, 3 } })
    take(first)
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    local done
    for _, row in ipairs(DF._rows) do
      if row:IsShown() and row.done then done = row end
    end
    W.state(done).scripts.OnEnter(done)
    local _, st = ourTip()
    assert.equal(first.link, st.link)
    assert.is_nil(st.bag)
  end)
end)
