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
  local sales
  local KEYS = { "UIParent", "C_SpellBook", "C_Spell", "C_Container", "C_Item", "C_Timer", "GetTime", "time",
    "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo", "ERR_CANT_BE_DISENCHANTED", "SPELL_FAILED_CANT_BE_DISENCHANTED",
    "SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL", "MenuUtil", "GameTooltip", "ITEM_QUALITY_COLORS", "SETTINGS_KEYBINDINGS_LABEL",
    "CreateColor", "hooksecurefunc", "ContainerFrameCombinedBags", "ContainerFrame1", "INVTYPE_WAIST", "INVTYPE_CHEST",
    "BINDING_NAME_CLICK GoldCapDisenchantNext:LeftButton", "issecretvalue" }
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
    knows, clock = true, 1000
    _G.time = function() return NOW end
    _G.GetTime = function() return clock end
    _G.UIParent = CreateFrame("Frame")
    _G.ContainerFrameCombinedBags = CreateFrame("Frame", nil, _G.UIParent)
    _G.ContainerFrameCombinedBags:Hide()
    _G.ContainerFrame1 = CreateFrame("Frame", nil, _G.UIParent)
    _G.ContainerFrame1:Hide()
    bags = _G.ContainerFrameCombinedBags
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
    _G.MenuUtil = { CreateContextMenu = function(owner, generator)
      menu = { owner = owner, buttons = {} }
      function menu:CreateButton(text, fn) self.buttons[#self.buttons + 1] = { text = text, fn = fn } end
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
    event("PLAYER_REGEN_DISABLED")
    nextFrame()
    assert.same({}, armedAt())
    S.enterCombat()
    S.key(button())
    assert.same({}, S.casts)
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
end)
