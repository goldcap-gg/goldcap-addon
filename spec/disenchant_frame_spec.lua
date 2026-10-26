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
  local sales, fighting, slotButtons, uncached, requested
  local KEYS = { "UIParent", "C_SpellBook", "C_Spell", "C_Container", "C_Item", "C_Timer", "GetTime", "time",
    "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "ERR_CANT_BE_DISENCHANTED", "SPELL_FAILED_CANT_BE_DISENCHANTED",
    "SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL", "MenuUtil", "GameTooltip", "ITEM_QUALITY_COLORS", "SETTINGS_KEYBINDINGS_LABEL",
    "CreateColor", "hooksecurefunc", "ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6", "NUM_CONTAINER_FRAMES", "INVTYPE_WAIST", "INVTYPE_CHEST",
    "BINDING_NAME_CLICK GoldCapDisenchantNext:LeftButton", "issecretvalue", "UnitAffectingCombat" }
  local NOW = 1800000000
  local DUST, SHARD = 9001, 9002

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
    slots[s.bag .. ":" .. s.slot] = { itemID = s.itemID, hyperlink = s.link, stackCount = s.count, isLocked = false }
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
    timers, stacks, slots, reads, prices, groups, printed, loot, sales = {}, {}, {}, 0, {}, {}, {}, {}, {}
    knows, clock, fighting = true, 1000, false
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
        return "Item " .. id, nil, 2, 201, 0, "Armor", "Plate", 1, "INVTYPE_WAIST"
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
    _G.SETTINGS_KEYBINDINGS_LABEL = "Keybindings"
    _G.INVTYPE_WAIST, _G.INVTYPE_CHEST = "Waist", "Chest"
    _G.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 },
      [4] = { r = 0.64, g = 0.21, b = 0.93 } }
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.hooksecurefunc = nil
    _G.issecretvalue = nil
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
      return n
    end
    _G.MenuUtil = { CreateContextMenu = function(owner, generator)
      menu = node("root")
      menu.owner = owner
      generator(owner, menu)
    end }
    _G.GameTooltip = {
      lines = {},
      SetOwner = function(self, owner) self.owner, self.lines = owner, {} end,
      ClearAllPoints = function() end,
      SetPoint = function() end,
      AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
      Show = function() end,
      Hide = function(self) self.owner = nil end,
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
    GC.VendorBags = { Read = function()
      reads = reads + 1
      local copy = {}
      for i, s in ipairs(stacks) do copy[i] = s end
      return copy
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

  it("keeps the entry hidden with nothing to disenchant, and with the bags closed", function()
    put(gear(0, 1, 501, { quality = 1 }))
    openBags()
    assert.is_false(entryUp())
    put(gear(0, 2, 502))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.is_true(entryUp())
    bags:Hide()
    W.state(bags).hooks.OnHide(bags)
    nextFrame()
    assert.is_false(entryUp())
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
    clock = clock + 4.9
    event("UNIT_SPELLCAST_START", "player", "Cast-1", 13262)
    nextFrame()
    clock = clock + 1.5
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 13262)
    nextFrame()
    assert.equal("Next", textOf(DF._frame.card.label))
    assert.same({ "spell", 13262, 0, 2 }, armedAt())
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
    assert.equal("A vendor pays more: 19g against about 2g in mats.", coins(DF._frame.card.verdict))
    put(gear(0, 2, 502, { quality = 3, vendorUnit = 10000 }))
    event("BAG_UPDATE_DELAYED")
    nextFrame()
    assert.equal("Mats pay more: about 9g against 1g from a vendor.", coins(DF._frame.card.verdict))
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

  it("takes the coins off when nothing is queued", function()
    put(gear(0, 1, 503, { ahUnit = 12400000, ahSource = "region", ahAt = NOW - 600 }))
    openBags()
    assert.is_nil(overlayOf("0:1"))
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

  it("waits for the client to name a kept item that is not in the bags before it opens the menu", function()
    put(gear(0, 1, 501))
    GC.Disenchant.Keep(GC.db, 777)
    uncached[777] = true
    slash()
    menu = nil
    press(DF._frame.kept.show)
    assert.same({ 777 }, requested)
    assert.is_nil(menu)
    uncached[777] = nil
    event("ITEM_DATA_LOAD_RESULT", 777, true)
    assert.is_not_nil(menu)
    assert.is_truthy(menu.entries[3].text:find("Item 777", 1, true))
  end)

  it("opens the menu after a moment when the client never answers, once", function()
    put(gear(0, 1, 501))
    GC.Disenchant.Keep(GC.db, 777)
    uncached[777] = true
    slash()
    menu = nil
    press(DF._frame.kept.show)
    assert.is_nil(menu)
    assert.equal(1, fire(DF.NAME_SECONDS))
    assert.is_not_nil(menu)
    local first = menu
    event("ITEM_DATA_LOAD_RESULT", 777, false)
    assert.equal(first, menu)
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
    assert.equal(1, #menu.entries[2].buttons)
    assert.equal("Disenchant it again", menu.entries[2].buttons[1].text)
    menu.entries[2].buttons[1].fn()
    nextFrame()
    assert.is_false(GC.Disenchant.Kept(GC.db, 501))
    assert.same({ 501, 502 }, listed())
    assert.is_false(DF._frame.kept.text:IsShown())
  end)

  it("lists a kept item that is not in the bags after a divider, and brings it back too", function()
    put(gear(0, 1, 501))
    GC.Disenchant.Keep(GC.db, 502)
    GC.Disenchant.Keep(GC.db, 777)
    put(gear(0, 2, 502))
    slash()
    assert.equal("Kept: 2 items", textOf(DF._frame.kept.text))
    press(DF._frame.kept.show)
    local kinds = {}
    for i, e in ipairs(menu.entries) do kinds[i] = e.kind end
    assert.same({ "title", "button", "divider", "title", "button" }, kinds)
    assert.equal("Not in your bags", menu.entries[4].text)
    assert.is_truthy(menu.entries[5].text:find("Item 777", 1, true))
    menu.entries[5].buttons[1].fn()
    assert.is_false(GC.Disenchant.Kept(GC.db, 777))
    assert.is_true(GC.Disenchant.Kept(GC.db, 502))
  end)

  it("keeps the Kept line inside the window, above the footer", function()
    put(gear(0, 1, 501))
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

  -- Sixteen and more items: the window keeps to about 85% of the screen's height, "In this order"
  -- scrolls, and the card, the strip, "Left out" and the footer stand outside the scroll.
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
    assert.equal(f, p)
    assert.equal(f, f.orderTitle:GetParent())
  end)
end)
