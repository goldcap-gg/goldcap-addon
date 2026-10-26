local _, GC = ...

-- GoldCap Disenchant (retail only): a window of GoldCap's for an enchanter that disenchants the bags'
-- gear one press at a time and says, for each item, whether its mats or a vendor pay more (owner,
-- approved mockup 2026-10-26, canvas version 16, boards Disenchant and DisenchantInGame). Drawn in
-- the GoldCap Hoard's look (UI/HoardFrame.lua, UI/HoardRow.lua and UI/HoardFooter.lua, loaded
-- before this file, whose header, item icons, helpers and price line it builds with):
-- - the Next card: the item the next press disenchants, its kind, which figure pays more, how far the
--   visit has come, the Disenchant button, Skip, and how to put it on a key;
-- - the yield strip: what the queue gives, by what GoldCap has learned, or what this visit got;
-- - "In this order": the queue (Core/Disenchant.lua's Plan), with what the mats and a vendor pay for
--   each, the item now cast tinted, the ones done this visit dimmed with a check; a right click keeps
--   an item off the list for good;
-- - "Left out: the auction house pays more", each with Disenchant anyway for this visit;
-- - the footer: what Mats means and what never comes on the list, and where the prices come from.
-- A small button above the top right of Blizzard's open bags (ContainerFrameCombinedBags, else
-- ContainerFrame1) shows how many items are queued and opens and closes the window; /gc disenchant
-- does the same for a bag addon that replaces Blizzard's bags.
--
-- The Disenchant button is GoldCapDisenchantNext, a SecureActionButtonTemplate button, and it is the
-- only thing in GoldCap that casts: addon code never calls a cast. Built as probe D1 measured it
-- (retail 12.1.5, 2026-10-26): type "spell", spell 13262 by id, target-bag and target-slot,
-- RegisterForClicks("LeftButtonUp") and useOnKeyDown false; its click disenchanted that bag slot.
-- The window only points it at the queue's first item after each paint (arm), out of combat, and
-- clears it while nothing is to be pressed: the window closed, a cast of its own going, the queue
-- empty. Its PreClick re-reads the slot it points at and clears it when the slot no longer holds the
-- item the window names, so that press casts nothing; the window repaints on the next frame, never
-- inside the press, so no press ever lands on an item the window did not name.
--
-- The key binding is the button's own: Bindings.xml's CLICK GoldCapDisenchantNext:LeftButton. The
-- template's OnClick (SecureActionButton_OnClick, live Blizzard_FrameXML/SecureTemplates.lua:805-829)
-- acts on a click with `down` only while useOnKeyDown is on and on one without it only while it is
-- off: (down and useOnKeyDown) or (not down and not useOnKeyDown). With it off the button acts on
-- the key's release alone, and RegisterForClicks("LeftButtonUp") keeps the press's half from the
-- button at all, so a key press disenchants once, never twice, whatever halves the client sends.
-- A press while the window is closed opens it and casts nothing.
--
-- Combat: the button hides by RegisterStateDriver(button, "visibility", "[combat] hide; show"), as
-- the probe did. A frame a protected one stands under is protected too, so the window, its card and
-- the button are never shown, hidden, moved, sized or armed in combat: what the player asks for then
-- (open, close, a repaint the bags asked for) waits for PLAYER_REGEN_ENABLED, and the window keeps
-- naming exactly the item the button still points at. A key still clicks the hidden button, so in
-- combat two secure attribute drivers make its left click's type and target slot nothing (buildCast):
-- a press then casts nothing, whatever the slot holds by then. As a second guard the button is
-- pointed at nothing as the fight begins (PLAYER_REGEN_DISABLED, while the client still allows it),
-- and nothing arms it again until the fight is over. The window stands at absolute coordinates on
-- UIParent, beside the bags as it opens, never anchored to Blizzard's bag frame, which a protected
-- frame anchored to it would make protected in turn. The entry button holds nothing protected and
-- follows the bags in combat too.
--
-- What disenchanting gives is learned from the player's own presses only (Core/Disenchant.lua's
-- Learn): UNIT_SPELLCAST_SUCCEEDED of spell 13262 for a press of this button opens a LOOT_SECONDS
-- window in which the first LOOT_READY is read (GetNumLootItems, GetLootSlotLink, GetLootSlotInfo's
-- quantity, as Blizzard_UIPanels_Game/Mainline/LootFrame.lua reads them) and learned for the kind
-- of the item pressed. Loot outside it (a mob's, a chest's, a disenchant from the spellbook) is never
-- read. An item the client refuses ("Item cannot be disenchanted": ERR_CANT_BE_DISENCHANTED and
-- SPELL_FAILED_CANT_BE_DISENCHANTED, or the skill's SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL, as
-- UI_ERROR_MESSAGE carries it after a press of this button) is left out for the visit and the next
-- armed; a cast that was moved, interrupted or failed for any other reason keeps its item. Which
-- of UI_ERROR_MESSAGE and UNIT_SPELLCAST_FAILED comes first is not measured: either order counts.
--
-- A visit is from the window's opening to its closing: what was skipped, sent anyway, refused, done
-- and got. For a character that does not know Disenchant (C_SpellBook.IsSpellKnown(13262)) nothing
-- is built, read or shown. GoldCap_Camelot.toc does not load this file.
GC.DisenchantFrame = {}
local DF = GC.DisenchantFrame
local HF = GC.HoardFrame
local D = GC.Disenchant
local K = GC.Kit.Tokens.color
local hex = GC.Kit.Tokens.hex
local U = HF.ui
local L = U.L
local setText, colour, wrapping, heightOf, track, restamp = U.setText, U.colour, U.wrapping, U.heightOf, U.track,
  U.restamp

DF.BUTTON = "GoldCapDisenchantNext"
-- The key binding's name, as Bindings.xml declares it; its label is the global the client reads for it.
DF.BINDING = "CLICK GoldCapDisenchantNext:LeftButton"
-- How long after a press its cast's answer counts as the answer to that press: the cast took about
-- 1.55 s in probe D1 (CAST_SECONDS, the casting bar's length), with room for the server.
DF.PENDING_SECONDS = 5
DF.CAST_SECONDS = 1.55
-- How long after the cast succeeds its loot is waited for.
DF.LOOT_SECONDS = 3
-- The most of the screen's height the window takes.
DF.HEIGHT_SHARE = 0.85

-- In UI units; the approved boards are drawn at twice that. The window is the Hoard's width with its
-- margins and gutter (L). CARD_PAD: the Next card's margin; ICON: its item, BADGE the spell's mark
-- on it; TEXT_GAP right of the icon, COUNTER_GAP left of "1 of 7"; BLOCK_GAP between the card's
-- lines; VERDICT_ICON and VERDICT_GAP: the verdict's glyph; BAR_H: the cast bar; BUTTON_H: the
-- Disenchant and Skip buttons, BUTTON_ICON the spell's icon on Disenchant, SKIP_MIN Skip's least
-- width. STRIP_PAD: the yield strip's margin; MAT_ICON, MAT_GAP and MAT_LINE: a material, the room
-- after it and between lines of them. ROW_*: a line of the lists; COL_MIN the least width of the
-- Mats and Vendor columns, COL_GAP between them; ANYWAY_H and ANYWAY_MIN: Disenchant anyway. DOT and
-- DOT_GAP: the price line's dot; FOOT_GAP between the footer's two parts. ENTRY: the button beside
-- the bags, its GoldCap mark (ENTRY_LOGO), the spell's icon on it (ENTRY_SPELL) and its count's
-- badge (ENTRY_COUNT), ENTRY_GAP above the bags. ROWS_MIN: the fewest lines the scroll keeps room for.
local M = {
  CARD_PAD = 10, ICON = 36, BADGE = 16, TEXT_GAP = 10, COUNTER_GAP = 8, LINE_GAP = 2, BLOCK_GAP = 8,
  VERDICT_ICON = 10, VERDICT_GAP = 5, BAR_H = 3, BUTTON_H = 28, BUTTON_ICON = 14, BUTTON_PAD = 10, SKIP_MIN = 64,
  BUTTON_GAP = 6, STRIP_PAD = 8, MAT_ICON = 16, MAT_GAP = 10, MAT_LINE = 4, ROW_PAD = 5, ROW_ICON = 18,
  ROW_GAP = 3, ROW_MIN_H = 28, COL_MIN = 44, COL_GAP = 8, ANYWAY_H = 18, ANYWAY_MIN = 70, SECTION_GAP = 10,
  HEADING_GAP = 5, TITLE_GAP = 1, DOT = 6, DOT_GAP = 5, FOOT_GAP = 6, ENTRY = 32, ENTRY_LOGO = 20, ENTRY_SPELL = 13,
  ENTRY_COUNT = 14, ENTRY_GAP = 4, ROWS_MIN = 3,
}

-- The boards' colours: the Disenchant purple; the main button's gradient and its dark words; the
-- casting look (the fill at 22%, light purple words, not pressable); the mats' winning green (the
-- kit's profit), the vendor's winning amber, the losing figure's grey (the kit's fourth text step).
local PURPLE = { 176 / 255, 100 / 255, 240 / 255, 1 }
local FILL_TOP, FILL_BOTTOM, ON_PURPLE = hex("C58BFA"), hex("9A55E0"), hex("14081F")
local CASTING_FILL = { PURPLE[1], PURPLE[2], PURPLE[3], 0.22 }
local CASTING_TEXT = hex("C9A3F5")
local MATS_C, VENDOR_C, LOSER_C = K.profit, hex("F2B544"), K.text4
local CARD_FILL = { PURPLE[1], PURPLE[2], PURPLE[3], 0.06 }
local CARD_RING = { PURPLE[1], PURPLE[2], PURPLE[3], 0.35 }
local ROW_CAST_FILL = { PURPLE[1], PURPLE[2], PURPLE[3], 0.10 }
local ROW_CAST_RING = { PURPLE[1], PURPLE[2], PURPLE[3], 0.6 }
local BAR_TRACK = { 1, 1, 1, 0.08 }
-- The shade the engine lays over a held button (UI/Kit/Button.lua's PRESSED).
local PRESSED = { 0, 0, 0, 0.28 }
-- A line done this visit.
local DONE_ALPHA = 0.55
-- The Disenchant spell's icon, where the client will not say it.
local SPELL_ICON = "Interface\\Icons\\INV_Enchant_Disenchant"
-- plaque.png (32px, its corners 8px round inside a 12px slice) cut in three, so the main button's
-- fill can carry a vertical gradient without a sliced texture (UI/Kit/Card.lua's windowFill says
-- why not one): a cap at each end as wide as the slice at the button's height, the middle stretched.
local CUT = 12 / 32
local CAP = math.floor(M.BUTTON_H * CUT + 0.5)
local PIECES = { { 0, CUT }, { CUT, 1 - CUT }, { 1 - CUT, 1 } }

-- What the window remembers, for the visit (newVisit): skipped, sent anyway and refused items (Plan's
-- skipped, anyway and failed), the items done in it (their plan rows, in order) and their slots with
-- the link each held, until the bags show it gone (gone), the materials got ({ [itemID] = units }),
-- and the room the Next card keeps (only grows). The last plan; what the button points at
-- (`armed`: the row, its slot and link and the item's kind); the press waiting for its cast's answer
-- (`pending`: the row, its item and kind, when, its cast's GUID, `over` once the cast failed); the
-- cast of a press going (`casting`: the row, since when); the loot awaited after a cast succeeded
-- (`loot`: the kind, until when). What combat held: the window's wanted state (`wantShown`), a
-- repaint (`dirty`); a key press asking the window open (`openNext`); a paint asked for on the next
-- frame (`queued`). The lines, pooled by place.
DF._visit = nil
DF._plan = nil
DF._armed, DF._pending, DF._casting, DF._loot = nil, nil, nil, nil
DF._wantShown, DF._dirty, DF._openNext, DF._queued = nil, nil, nil, nil
DF._rows, DF._leftRows = {}, {}
-- The items the player keeps that the bags hold, as the last read saw them: in bag order (`list`) and
-- by slot (`bySlot`), for the Kept menu and for the tooltip.
DF._kept = { list = {}, bySlot = {} }

local frame, entry
local refresh

-- One guarded client call: its first answer, or nil when it is missing or fails.
local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- A spell cast's payload can be secret in some content (Midnight's rules): such a value is never
-- compared, it reads as nothing.
local function plain(value)
  local secret = _G.issecretvalue
  if type(secret) == "function" and secret(value) then return nil end
  return value
end

local function now()
  return ask(GetTime) or 0
end

-- In combat: the client's lockdown, or the fight as this window heard it begin (PLAYER_REGEN_DISABLED
-- to PLAYER_REGEN_ENABLED, `fight`), so that nothing arms the button between that event and the
-- lockdown. The fight is over, though PLAYER_REGEN_ENABLED was not heard, once neither the lockdown
-- nor UnitAffectingCombat("player") says it goes on (true from PLAYER_REGEN_DISABLED on).
local function inCombat()
  if type(InCombatLockdown) == "function" and InCombatLockdown() == true then return true end
  if not DF._fight then return false end
  local affecting = _G.UnitAffectingCombat
  if type(affecting) == "function" and affecting("player") ~= true then
    DF._fight = nil
    return false
  end
  return true
end

-- This button's press, while its cast's answer still counts as the answer to it.
local function pendingNow()
  local p = DF._pending
  if p and now() - p.at <= DF.PENDING_SECONDS then return p end
  return nil
end

-- The cast of a press going, until its answer is overdue (CAST_SECONDS and PENDING_SECONDS after it
-- started: a cast that ended in a way this window does not hear, a loading screen); then forgotten.
local function castingNow()
  local casting = DF._casting
  if casting and now() - casting.at > DF.CAST_SECONDS + DF.PENDING_SECONDS then
    DF._casting = nil
    return nil
  end
  return casting
end

--- Whether this character knows Disenchant: nothing of the window is built, read or shown otherwise.
function DF.Known()
  local book = _G.C_SpellBook
  return type(book) == "table" and ask(book.IsSpellKnown, D.SPELL) == true
end

local function newVisit()
  DF._visit = { skipped = {}, anyway = {}, failed = {}, done = {}, gone = {}, got = {}, topH = 0, verdictH = 0 }
end
newVisit()

-- ---------------------------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------------------------

-- What a material fetches: its price as its tooltip prints it (UI/MerchantNote.lua's ValueFor),
-- after the auction house's 5% cut, as Plan takes an item's own auction house figure.
local function priceOf(itemID)
  local note = GC.MerchantNote
  local value = note and note.ValueFor and note.ValueFor(itemID)
  local unit = type(value) == "table" and value.mv or nil
  if type(unit) ~= "number" or unit <= 0 then return nil end
  return math.floor(unit * GC.VendorSelect.KEEP)
end

local function inGroup(itemID)
  return GC.GroupRules ~= nil and GC.GroupRules.GroupOf(itemID) ~= nil
end

-- The bags as Services/VendorBags.lua reads them, planned (Core/Disenchant.lua's Plan) with what
-- this visit skipped, refused and sent anyway. An item done this visit whose slot still shows it (the
-- bags have not told the change yet) stays off the list; its slot is forgotten once it holds
-- anything else or nothing.
local function readPlan()
  local visit = DF._visit
  local note = GC.MerchantNote
  local stacks, seen = {}, {}
  local kept = { list = {}, bySlot = {} }
  for _, stack in ipairs(GC.VendorBags.Read(note and note.ValueFor)) do
    local key = stack.bag .. ":" .. stack.slot
    seen[key] = true
    if stack.itemID and D.CanDisenchant(stack) and D.Kept(GC.db, stack.itemID) then
      kept.list[#kept.list + 1], kept.bySlot[key] = stack, stack
    end
    if visit.gone[key] ~= nil and visit.gone[key] ~= stack.link then visit.gone[key] = nil end
    if visit.gone[key] == nil then stacks[#stacks + 1] = stack end
  end
  for key in pairs(visit.gone) do
    if not seen[key] then visit.gone[key] = nil end
  end
  DF._kept = kept
  return D.Plan(stacks, { db = GC.db, priceOf = priceOf, inGroup = inGroup, now = time(),
    skipped = visit.skipped, failed = visit.failed, anyway = visit.anyway })
end

-- Blizzard's open bags: the combined backpack when it shows, else the separate bags' backpack.
local function bagFrame()
  for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
    local f = _G[name]
    if type(f) == "table" and f.IsVisible and f:IsVisible() then return f end
  end
  return nil
end

local function spellIcon()
  local spell = _G.C_Spell
  return spell and ask(spell.GetSpellTexture, D.SPELL) or SPELL_ICON
end

DF.SpellIcon = spellIcon

local function nameOf(stack)
  local name = C_Item and ask(C_Item.GetItemInfo, stack.link or stack.itemID)
  if type(name) ~= "string" or name == "" then name = C_Item and ask(C_Item.GetItemNameByID, stack.itemID) end
  if type(name) ~= "string" or name == "" then return "#" .. tostring(stack.itemID) end
  return name
end

local function qualityColour(quality)
  local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
  if type(c) ~= "table" then return K.text1 end
  return { c.r, c.g, c.b, 1 }
end

local function iconOf(itemID)
  return C_Item and ask(C_Item.GetItemIconByID, itemID) or nil
end

-- "Plate, Waist, item level 201": the item's subtype (C_Item.GetItemInfo's seventh answer), its slot
-- in the client's words (the INVTYPE_ global its equip location names) and its item level.
local function kindLine(stack)
  local parts = {}
  local ok, info = pcall(function() return { C_Item.GetItemInfo(stack.link or stack.itemID) } end)
  local subType = ok and info[7] or nil
  if type(subType) == "string" and subType ~= "" then parts[#parts + 1] = subType end
  local slotName = type(stack.equipLoc) == "string" and stack.equipLoc ~= "" and _G[stack.equipLoc] or nil
  if type(slotName) == "string" and slotName ~= "" and slotName ~= subType then parts[#parts + 1] = slotName end
  local level = C_Item and stack.link and ask(C_Item.GetDetailedItemLevelInfo, stack.link)
  if type(level) == "number" and level > 0 then parts[#parts + 1] = GC.L["item level %d"]:format(level) end
  return table.concat(parts, ", ")
end

-- A figure as the lists show it: whole gold from a gold up, as the Hoard's worth column does (the
-- silver is noise there), silver and copper below it.
local function money(copper)
  if type(copper) ~= "number" or copper <= 0 then return GC.Util.Money(0) end
  return U.worthText(copper)
end

-- What a row's card line says pays more, its colour and its glyph.
local function verdictOf(row)
  if row.best == "ah" then
    return GC.L["The auction house pays more: %s after its cut."]:format(money(row.ah)), VENDOR_C, "warning"
  end
  if row.mats == nil then
    if (row.n or 0) == 0 then return GC.L["GoldCap learns what this gives the first time."], K.text3, "info" end
    return GC.L["GoldCap has no price yet for what this gives."], K.text3, "info"
  end
  if row.best == "mats" then
    return GC.L["Mats pay more: about %s against %s from a vendor."]:format(money(row.mats), money(row.vendor)),
      MATS_C, "check"
  end
  return GC.L["A vendor pays more: %s against about %s in mats."]:format(money(row.vendor), money(row.mats)),
    VENDOR_C, "warning"
end

-- What `mats` ({ [itemID] = units }) fetch, after the cut; nil when one of them has no price.
local function worthOf(mats)
  local total = 0
  for itemID, units in pairs(mats) do
    local price = priceOf(itemID)
    if not price then return nil end
    total = total + units * price
  end
  return math.floor(total + 0.5)
end

-- How many of a material, as the strip writes it: exact for what was got, "~" and the average for
-- what the queue would give (a tenth under one).
local function unitsText(units, exact)
  if exact then return tostring(math.floor(units + 0.5)) end
  if units < 1 then return ("~%.1f"):format(units) end
  return "~" .. tostring(math.floor(units + 0.5))
end

-- ---------------------------------------------------------------------------------------------
-- The button
-- ---------------------------------------------------------------------------------------------

-- Points the button at `row`'s bag slot, or at nothing: the attributes probe D1 measured. Out of
-- combat only; the caller never asks in it.
local function setArmed(row)
  local b = DF._button
  if not b or inCombat() then return end
  if row then
    local stack = row.stack
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", D.SPELL)
    b:SetAttribute("target-bag", stack.bag)
    b:SetAttribute("target-slot", stack.slot)
    DF._armed = { row = row, bag = stack.bag, slot = stack.slot, link = stack.link, itemID = stack.itemID,
      kind = D.KindOf(stack), slotKey = row.slotKey }
  else
    for _, key in ipairs({ "type", "spell", "target-bag", "target-slot" }) do b:SetAttribute(key, nil) end
    DF._armed = nil
  end
end

-- After a paint: the queue's first item while the window shows and no cast of its own goes.
local function arm()
  local row
  if frame and frame:IsShown() and not castingNow() and DF._plan then row = DF._plan.queue[1] end
  setArmed(row)
end

local function schedule()
  if DF._queued then return end
  if not (C_Timer and C_Timer.After) then return refresh() end
  DF._queued = true
  C_Timer.After(0, function() refresh() end)
end

--- The button's PreClick, before the template's OnClick casts: the press's half that acts is the
--- release (useOnKeyDown off), so a half with `down` changes nothing. In combat the secure drivers
--- make the press cast nothing (buildCast), so it is neither remembered nor allowed to open the
--- window when the fight is over. The slot the button points at is read again; when it no longer
--- holds the item the window names, the button is cleared, so this press casts nothing, and the
--- window repaints on the next frame. Nothing pointed at: a press while the window is closed opens
--- it on the next frame. Else this press is remembered for its cast's answer, unless an earlier
--- press of the same item still waits for one (a double click before the cast starts: the second
--- fails, the first one's cast is the one to follow).
function DF._PreClick(_, _, down)
  if down or inCombat() then return end
  local armed = DF._armed
  if not armed then
    if not (frame and frame:IsShown()) then DF._openNext = true end
    return schedule()
  end
  local info = C_Container and ask(C_Container.GetContainerItemInfo, armed.bag, armed.slot)
  local link = type(info) == "table" and info.hyperlink or nil
  if link ~= armed.link then
    setArmed(nil)
    return schedule()
  end
  local p = pendingNow()
  if p and not p.over and p.slotKey == armed.slotKey and p.link == armed.link then
    -- Its cast's answer counts from this press now: the earlier one may have failed before it started.
    p.at = now()
    return
  end
  DF._pending = { row = armed.row, itemID = armed.itemID, kind = armed.kind, slotKey = armed.slotKey,
    link = armed.link, at = now() }
end

-- ---------------------------------------------------------------------------------------------
-- The clicks that cast nothing
-- ---------------------------------------------------------------------------------------------

--- Skip: the item named next is left for this visit, and the next one armed.
function DF.Skip()
  local row = DF._plan and DF._plan.queue[1]
  if not row or castingNow() then return end
  DF._visit.skipped[row.slotKey] = true
  refresh()
end

--- Never disenchant this: the item stays off the list from now on (Core/Disenchant.lua's Keep).
function DF.Keep(itemID)
  D.Keep(GC.db, itemID)
  refresh()
end

--- Disenchant it again: a kept item comes back on the list.
function DF.Unkeep(itemID)
  D.Unkeep(GC.db, itemID)
  refresh()
end

--- Disenchant anyway: an item the auction house pays more for joins the queue for this visit.
function DF.Anyway(slotKey)
  DF._visit.anyway[slotKey] = true
  refresh()
end

-- The bag slot an item button stands for: Blizzard's own (ContainerFrameItemButtonMixin:GetBagID, the
-- engine's GetID), "bag:slot", or nil for any other owner (a merchant's button, a chat link's tooltip).
local function slotKeyOf(button)
  if type(button) ~= "table" or type(button.GetBagID) ~= "function" or type(button.GetID) ~= "function" then
    return nil
  end
  local okBag, bag = pcall(button.GetBagID, button)
  local okSlot, slot = pcall(button.GetID, button)
  if okBag and okSlot and type(bag) == "number" and type(slot) == "number" then return bag .. ":" .. slot end
  return nil
end

--- Where the item in a bag slot stands, from the last plan: { state = "next" | "listed" | "left" |
--- "kept", mats = copper its kind gave or nil, n = the disenchants behind it }. Nil for a character
--- without Disenchant, for any button that is not a bag slot and for a slot that holds another item.
function DF.Standing(button, itemID)
  if not DF.Known() then return nil end
  local key = slotKeyOf(button)
  local plan = DF._plan
  if not key or not plan then return nil end
  for i, row in ipairs(plan.queue) do
    if row.slotKey == key and row.stack.itemID == itemID then
      return { state = i == 1 and "next" or "listed", mats = row.mats, n = row.n or 0 }
    end
  end
  for _, row in ipairs(plan.left) do
    if row.slotKey == key and row.stack.itemID == itemID then
      return { state = "left", mats = row.mats, n = row.n or 0 }
    end
  end
  local stack = DF._kept.bySlot[key]
  if stack and stack.itemID == itemID then
    local mats, n = D.MatsValue(GC.db, D.KindOf(stack), priceOf)
    return { state = "kept", mats = mats, n = n }
  end
  return nil
end

local function openKeepMenu(owner, itemID)
  local menu = _G.MenuUtil
  if not (menu and menu.CreateContextMenu) then return end
  menu.CreateContextMenu(owner, function(_, root)
    root:CreateButton(GC.Util.ClientText(GC.L["Never disenchant this"]), function() DF.Keep(itemID) end)
  end)
end

-- A kept item's line in the menu: its icon and its name in its quality's colour.
local function keptLabel(itemID, stack)
  local quality = stack and stack.quality or (C_Item and ask(C_Item.GetItemQualityByID, itemID))
  local name = GC.Util.Colored(qualityColour(quality), nameOf({ itemID = itemID, link = stack and stack.link }))
  local icon = iconOf(itemID)
  if icon then return ("|T%s:14|t %s"):format(tostring(icon), name) end
  return name
end

-- "Never disenchanted": the kept items the bags hold, then, after a divider, the others; each opens
-- "Disenchant it again" (Unkeep).
local function fillKeptMenu(root)
  local text = GC.Util.ClientText
  root:CreateTitle(text(GC.L["Never disenchanted"]))
  local held, away = {}, {}
  for _, stack in ipairs(DF._kept.list) do
    if not held[stack.itemID] then held[stack.itemID] = stack end
  end
  local function addKept(itemID, stack)
    local item = root:CreateButton(text(keptLabel(itemID, stack)))
    item:CreateButton(text(GC.L["Disenchant it again"]), function() DF.Unkeep(itemID) end)
  end
  local shown = {}
  for _, stack in ipairs(DF._kept.list) do
    if not shown[stack.itemID] then
      shown[stack.itemID] = true
      addKept(stack.itemID, stack)
    end
  end
  for _, itemID in ipairs(D.KeptIDs(GC.db)) do
    if not held[itemID] then away[#away + 1] = itemID end
  end
  if #away == 0 then return end
  if next(shown) then root:CreateDivider() end
  root:CreateTitle(text(GC.L["Not in your bags"]))
  for _, itemID in ipairs(away) do addKept(itemID, nil) end
end

local function openKeptMenu(owner)
  local menu = _G.MenuUtil
  if not (menu and menu.CreateContextMenu) then return end
  menu.CreateContextMenu(owner, function(_, root) fillKeptMenu(root) end)
end

local function onRowClick(row, mouseButton)
  if mouseButton == "RightButton" and row.itemID and not row.done then openKeepMenu(row, row.itemID) end
end

-- A line's item, beside the window.
local function showRowTip(row)
  local tooltip = _G.GameTooltip
  if not (tooltip and row.link and tooltip.SetHyperlink) then return end
  GC.Theme.ItemTooltipOutside(row, frame)
  tooltip:SetHyperlink(row.link)
  tooltip:Show()
end

local function showEntryTip(button)
  local tooltip = _G.GameTooltip
  if not tooltip then return end
  tooltip:SetOwner(button, "ANCHOR_LEFT")
  local n = DF._plan and #DF._plan.queue or 0
  local text = n == 1 and GC.L["GoldCap Disenchant, 1 item"] or GC.L["GoldCap Disenchant, %d items"]:format(n)
  tooltip:AddLine(GC.Util.ClientText(text), K.goldText[1], K.goldText[2], K.goldText[3])
  tooltip:Show()
end

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------

-- The Disenchant button: the secure frame, its three-piece fill, the engine's gold wash under the
-- cursor and its held shade, the spell's icon and its word.
local function buildCast(card)
  local T = GC.Theme
  local b = CreateFrame("Button", DF.BUTTON, card, "SecureActionButtonTemplate")
  b:RegisterForClicks("LeftButtonUp")
  b:SetAttribute("useOnKeyDown", false)
  b:EnableMouse(true)
  b.fill = {}
  for i, cut in ipairs(PIECES) do
    local t = b:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(T.MEDIA .. "plaque.png")
    t:SetTexCoord(cut[1], cut[2], 0, 1)
    b.fill[i] = t
  end
  local left, middle, right = b.fill[1], b.fill[2], b.fill[3]
  left:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  left:SetWidth(CAP)
  right:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  right:SetWidth(CAP)
  middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
  middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
  b.wash = T.SlicedTexture(b, "HIGHLIGHT", T.MEDIA .. "plaque.png", K.hoverWash, T.SLICE.plaque)
  b.wash:SetAllPoints()
  b.wash:SetBlendMode("ADD")
  b.held = T.SlicedTexture(b, "ARTWORK", T.MEDIA .. "plaque.png", PRESSED, T.SLICE.plaque)
  b.held:SetAllPoints()
  b:SetPushedTexture(b.held)
  b.icon = b:CreateTexture(nil, "OVERLAY")
  b.icon:SetSize(M.BUTTON_ICON, M.BUTTON_ICON)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.icon:SetTexture(spellIcon())
  b.text = track(frame, T.Heading(b, 12))
  b.text:SetWordWrap(false)
  b:SetScript("PreClick", DF._PreClick)
  _G.RegisterStateDriver(b, "visibility", "[combat] hide; show")
  -- In combat a key still clicks the hidden button, and PreClick can no longer clear it: the secure
  -- manager then sets the left click's type and target slot to ATTRIBUTE_NOOP (""), so that click
  -- casts nothing and aims no waiting spell at a bag slot, whatever the slot holds by then. Live
  -- Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua:97-118 (resolveDriver: an empty
  -- action sets "", "nil" sets nil and only over another value) and Blizzard_FrameXML/
  -- SecureTemplates.lua:22-27, :119-137 (ATTRIBUTE_NOOP; "*type1" is found before "type" and ""
  -- reads as nil), :762-781 (the target slot is read whatever the type). Out of combat both resolve
  -- to nil and leave setArmed's own "type" and "target-slot" alone; the manager rescans on
  -- PLAYER_REGEN_DISABLED and PLAYER_REGEN_ENABLED (:193-194), from secure code, in combat too.
  _G.RegisterAttributeDriver(b, "*type1", "[combat] ; nil")
  _G.RegisterAttributeDriver(b, "*target-slot1", "[combat] ; nil")
  DF._button = b
  return b
end

local function buildCard()
  local T = GC.Theme
  local card = T.Card(frame, CARD_FILL, CARD_RING, true)
  card.slot = HF.Row.NewIcon(card, M.ICON)
  card.badge = card:CreateTexture(nil, "OVERLAY", nil, 3)
  card.badge:SetSize(M.BADGE, M.BADGE)
  card.badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  card.badge:SetTexture(spellIcon())
  card.badge:SetPoint("CENTER", card.slot.edge, "BOTTOMRIGHT", -3, 3)
  card.label = track(frame, T.Heading(card, 9))
  card.label:SetWordWrap(false)
  card.name = track(frame, wrapping(T.Label(card, 12)))
  card.kind = track(frame, wrapping(T.Label(card, 10)))
  colour(card.kind, K.text3)
  card.counter = track(frame, T.Num(card, 11))
  card.counter:SetWordWrap(false)
  colour(card.counter, K.text2)
  card.mark = card:CreateTexture(nil, "ARTWORK")
  card.mark:SetSize(M.VERDICT_ICON, M.VERDICT_ICON)
  card.verdict = track(frame, wrapping(T.Label(card, 10)))
  -- The cast's bar, in a frame of its own whose OnUpdate fills it while a cast goes.
  local bar = CreateFrame("Frame", nil, card)
  bar.label = track(frame, T.Label(bar, 9))
  bar.label:SetWordWrap(false)
  colour(bar.label, PURPLE)
  bar.track = T.Solid(bar, "ARTWORK", BAR_TRACK)
  bar.fill = T.Solid(bar, "OVERLAY", PURPLE)
  bar:SetScript("OnUpdate", function(self)
    if not DF._casting then return end
    local casting = castingNow()
    if not casting then return schedule() end
    local share = math.min(1, math.max(0, (now() - casting.at) / DF.CAST_SECONDS))
    self.fill:SetWidth(math.max(1, (self:GetWidth() or 0) * share))
  end)
  bar:Hide()
  card.bar = bar
  card.cast = buildCast(card)
  card.skip = T.Button(card, "ghost", "plaque")
  card.skip:SetHeight(M.BUTTON_H)
  card.skip:SetScript("OnClick", function() DF.Skip() end)
  track(frame, card.skip.text)
  card.keys = track(frame, wrapping(T.Label(card, 9)))
  colour(card.keys, K.text3)
  frame.card = card
end

local function buildStrip()
  local T = GC.Theme
  local strip = T.Card(frame, K.glassTop, K.glassBorder, true)
  strip.label = track(frame, wrapping(T.Label(strip, 10)))
  colour(strip.label, K.text2)
  strip.value = track(frame, T.Num(strip, 11))
  strip.value:SetWordWrap(false)
  colour(strip.value, K.goldText)
  strip.chips = {}
  frame.strip = strip
end

-- A material on the strip: its icon, how many, its name.
local function chipAt(i)
  local strip = frame.strip
  local chip = strip.chips[i]
  if chip then return chip end
  local T = GC.Theme
  chip = { icon = strip:CreateTexture(nil, "ARTWORK") }
  chip.icon:SetSize(M.MAT_ICON, M.MAT_ICON)
  chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  chip.count = track(frame, T.Num(strip, 10))
  chip.count:SetWordWrap(false)
  chip.count:SetJustifyH("LEFT")
  colour(chip.count, K.text1)
  chip.name = track(frame, wrapping(T.Label(strip, 10)))
  colour(chip.name, K.text2)
  strip.chips[i] = chip
  return chip
end

-- A line of "In this order": a right click keeps its item.
local function newRow()
  local T = GC.Theme
  local row = CreateFrame("Button", nil, frame.content)
  row:RegisterForClicks("RightButtonUp")
  row:EnableMouse(true)
  row.bg = T.SlicedTexture(row, "BACKGROUND", T.MEDIA .. "plaque.png", K.glassBottom, T.SLICE.plaque)
  row.bg:SetAllPoints()
  row.ring = T.SlicedTexture(row, "BORDER", T.MEDIA .. "plaque_ring.png", K.hairline, T.SLICE.plaque)
  row.ring:SetAllPoints()
  row.slot = HF.Row.NewIcon(row, M.ROW_ICON)
  row.name = track(row, wrapping(T.Label(row, 11)))
  row.mats = track(row, T.Num(row, 10))
  row.mats:SetWordWrap(false)
  row.vendor = track(row, T.Num(row, 10))
  row.vendor:SetWordWrap(false)
  row:SetScript("OnClick", onRowClick)
  row:SetScript("OnEnter", showRowTip)
  row:SetScript("OnLeave", U.hideTip)
  return row
end

-- A line of "Left out": its item, what its mats would give, what the auction house pays, and
-- Disenchant anyway.
local function newLeftRow()
  local T = GC.Theme
  local row = CreateFrame("Frame", nil, frame.leftBox)
  row:EnableMouse(true)
  row.bg = T.SlicedTexture(row, "BACKGROUND", T.MEDIA .. "plaque.png", K.glassBottom, T.SLICE.plaque)
  row.bg:SetAllPoints()
  row.ring = T.SlicedTexture(row, "BORDER", T.MEDIA .. "plaque_ring.png", K.hairline, T.SLICE.plaque)
  row.ring:SetAllPoints()
  row.slot = HF.Row.NewIcon(row, M.ROW_ICON)
  row.name = track(row, wrapping(T.Label(row, 11)))
  row.note = track(row, wrapping(T.Label(row, 9)))
  colour(row.note, K.text3)
  row.price = track(row, T.Num(row, 10))
  row.price:SetWordWrap(false)
  colour(row.price, K.goldText)
  row.anyway = T.Button(row, U.QUIET.variant, "badge")
  row.anyway:SetGlow(false)
  row.anyway:SetRing(U.QUIET.ring)
  row.anyway:SetHeight(M.ANYWAY_H)
  row.anyway:SetScript("OnClick", function(self) DF.Anyway(self.slotKey) end)
  track(row, row.anyway.text)
  row:SetScript("OnEnter", showRowTip)
  row:SetScript("OnLeave", U.hideTip)
  return row
end

-- The X: the window goes (in combat, once the fight is over).
local function onCloseClick()
  if inCombat() then
    DF._wantShown = false
    return
  end
  DF.Close()
end

-- The window: its glass, the Hoard's header ("GoldCap" over "Disenchant", and the X), the Next
-- card, the yield strip, "In this order" with its column heads over the kit's scroll whose child
-- holds its lines, "Left out" under the scroll (`leftBox`), and the footer. HIGH strata: above
-- Blizzard's bags (ContainerFrame.xml:218, :290, MEDIUM) and action bars (MultiActionBars.xml,
-- MEDIUM; MainActionBar.xml:29, UIParent's MEDIUM at frame level 50), below a menu
-- (Blizzard_Menu/Menu.lua:2142, FULLSCREEN_DIALOG) and a tooltip (SharedTooltipTemplates.xml:95,
-- TOOLTIP). Set here, out of combat, before the secure button stands under it.
local function build()
  local T = GC.Theme
  frame = CreateFrame("Frame", nil, UIParent)
  frame:SetFrameStrata("HIGH")
  frame:SetSize(L.WIDTH, L.MIN_H)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame.glass = T.Window(frame)
  U.newHeader(frame, onCloseClick)
  buildCard()
  buildStrip()
  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  if T.QuietScrollBar then T.QuietScrollBar(scroll) end
  scroll.scrollBarHideable = true
  if scroll.ScrollBar then scroll.ScrollBar:Hide() end
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(L.WIDTH - 2 * L.PAD - L.GUTTER, 1)
  scroll:SetScrollChild(content)
  frame.scroll, frame.content = scroll, content
  frame.orderTitle = track(frame, T.Heading(frame, 9))
  frame.orderTitle:SetWordWrap(false)
  colour(frame.orderTitle, K.text3)
  frame.matsHead = track(frame, T.Heading(frame, 8))
  frame.vendorHead = track(frame, T.Heading(frame, 8))
  for _, head in ipairs({ frame.matsHead, frame.vendorHead }) do
    head:SetWordWrap(false)
    head:SetJustifyH("RIGHT")
    colour(head, K.text3)
  end
  frame.leftBox = CreateFrame("Frame", nil, frame)
  frame.leftTitle = track(frame, wrapping(T.Heading(frame.leftBox, 9)))
  colour(frame.leftTitle, K.text3)
  -- Measures what a column must hold; never shown.
  frame.measure = T.Num(content, 10, true)
  frame.measure:Hide()
  frame.footer = track(frame, wrapping(T.Label(frame, 9)))
  colour(frame.footer, K.text3)
  -- The way back for the items kept: "Kept: 2 items" and a quiet button that opens their menu.
  local kept = {}
  kept.text = track(frame, wrapping(T.Label(frame, 9)))
  colour(kept.text, K.text3)
  kept.show = T.Button(frame, U.QUIET.variant, "badge")
  kept.show:SetGlow(false)
  kept.show:SetRing(U.QUIET.ring)
  kept.show:SetHeight(M.ANYWAY_H)
  kept.show:SetScript("OnClick", function(self) openKeptMenu(self) end)
  track(frame, kept.show.text)
  frame.kept = kept
  -- The badge art is round at this size, as the Hoard's footer draws its dot.
  frame.dot = frame:CreateTexture(nil, "ARTWORK")
  frame.dot:SetTexture(T.MEDIA .. "badge.png")
  frame.dot:SetSize(M.DOT, M.DOT)
  frame.prices = track(frame, wrapping(T.Label(frame, 9)))
  colour(frame.prices, K.text3)
  -- A frame made from Lua starts shown: hidden until a paint shows it, so its first show is a re-show
  -- like any other (restamp).
  frame:Hide()
  DF._frame = frame
end

-- The button above the bags: the GoldCap mark on the window's glass, the spell's icon on it and a
-- purple badge with how many items are queued.
local function buildEntry()
  local T = GC.Theme
  entry = U.plate(UIParent, K.windowBorder, "plaque")
  entry:SetSize(M.ENTRY, M.ENTRY)
  entry:SetClampedToScreen(true)
  entry.bg = T.SlicedTexture(entry, "BACKGROUND", T.MEDIA .. "plaque.png", K.windowTop, T.SLICE.plaque)
  entry.bg:SetAllPoints()
  entry.logo = entry:CreateTexture(nil, "ARTWORK")
  entry.logo:SetTexture(T.MEDIA .. "GoldCap")
  entry.logo:SetSize(M.ENTRY_LOGO, M.ENTRY_LOGO)
  entry.logo:SetPoint("CENTER", entry, "CENTER", 0, 1)
  entry.spell = entry:CreateTexture(nil, "ARTWORK", nil, 1)
  entry.spell:SetSize(M.ENTRY_SPELL, M.ENTRY_SPELL)
  entry.spell:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  entry.spell:SetTexture(spellIcon())
  entry.spell:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 2, 2)
  entry.pill = entry:CreateTexture(nil, "ARTWORK", nil, 2)
  entry.pill:SetTexture(T.MEDIA .. "badge.png")
  entry.pill:SetTextureSliceMargins(T.SLICE.badge, T.SLICE.badge, T.SLICE.badge, T.SLICE.badge)
  entry.pill:SetVertexColor(PURPLE[1], PURPLE[2], PURPLE[3], 1)
  entry.count = track(entry, T.Num(entry, 9, true))
  entry.count:SetWordWrap(false)
  entry.count:SetJustifyH("CENTER")
  colour(entry.count, K.text1)
  entry:SetScript("OnClick", function() DF.Toggle() end)
  entry:SetScript("OnEnter", showEntryTip)
  entry:SetScript("OnLeave", U.hideTip)
  entry:Hide()
  DF._entry = entry
end

-- ---------------------------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------------------------

-- The Disenchant button's look: "ready" (the gradient and dark words), "casting" or "idle" (the fill
-- at 22% and light purple words: nothing to press), as wide as `width`, its icon and word centred.
local function paintCast(look, width)
  local b = frame.card.cast
  local low, high = FILL_BOTTOM, FILL_TOP
  if look ~= "ready" then low, high = CASTING_FILL, CASTING_FILL end
  for _, t in ipairs(b.fill) do
    t:SetGradient("VERTICAL", CreateColor(low[1], low[2], low[3], low[4]), CreateColor(high[1], high[2], high[3], high[4]))
  end
  local c = look == "ready" and ON_PURPLE or CASTING_TEXT
  setText(b.text, GC.L["Disenchant"])
  colour(b.text, c)
  b.icon:SetVertexColor(1, 1, 1, look == "ready" and 1 or 0.5)
  b:SetSize(width, M.BUTTON_H)
  local textW = math.ceil(b.text:GetStringWidth() or 0)
  local x = math.max(M.BUTTON_PAD, math.floor((width - M.BUTTON_ICON - 6 - textW) / 2))
  b.icon:ClearAllPoints()
  b.icon:SetPoint("LEFT", b, "LEFT", x, 0)
  b.text:ClearAllPoints()
  b.text:SetPoint("LEFT", b, "LEFT", x + M.BUTTON_ICON + 6, 0)
end

-- The Next card, `w` wide: the item next (or now cast), its kind, "i of n", the verdict, the cast's
-- bar, Disenchant and Skip, and the key line. Its lines keep, for the visit, the room the tallest of
-- the queue's items needs, so Disenchant stands still from one press to the next. Answers its height.
local function paintCard(plan, w)
  local card, visit, casting = frame.card, DF._visit, castingNow()
  local row = casting and casting.row or plan.queue[1]
  local x, inner = M.CARD_PAD, w - 2 * M.CARD_PAD
  local total = #visit.done + #plan.queue
  local counterW = 0
  if row then
    setText(card.counter, GC.L["%d of %d"]:format(total, total))
    counterW = math.ceil(card.counter:GetStringWidth() or 0)
    setText(card.counter, GC.L["%d of %d"]:format(math.min(#visit.done + 1, total), total))
  end
  card.counter:SetShown(row ~= nil)
  local textX = x + M.ICON + M.TEXT_GAP
  local textW = w - textX - M.CARD_PAD - (row and (counterW + M.COUNTER_GAP) or 0)
  local verdictW = inner - M.VERDICT_ICON - M.VERDICT_GAP

  -- The room: every item the queue may name in this visit, measured now.
  local names, kinds, verdicts = {}, {}, {}
  for _, r in ipairs(plan.queue) do
    names[#names + 1] = nameOf(r.stack)
    kinds[#kinds + 1] = kindLine(r.stack)
    verdicts[#verdicts + 1] = (verdictOf(r))
  end
  setText(card.label, casting and GC.L["Now"] or GC.L["Next"])
  colour(card.label, casting and PURPLE or K.text3)
  local labelH = math.ceil(heightOf(card.label, 11))
  local nameH = U.tallest(card.name, names, textW)
  local kindH = U.tallest(card.kind, kinds, textW)
  visit.verdictH = math.max(visit.verdictH, U.tallest(card.verdict, verdicts, verdictW))

  if row then
    local stack = row.stack
    HF.Row.PaintIcon(card.slot, stack.itemID, iconOf(stack.itemID), nil, nil)
    card.badge:Show()
    card.label:Show()
    setText(card.name, nameOf(stack))
    colour(card.name, qualityColour(stack.quality))
    setText(card.kind, kindLine(stack))
    card.kind:Show()
    local text, c, glyph = verdictOf(row)
    setText(card.verdict, text)
    colour(card.verdict, c)
    GC.Theme.SetIcon(card.mark, glyph, c)
    card.verdict:Show()
    card.mark:Show()
  else
    HF.Row.HideIcon(card.slot)
    card.badge:Hide()
    card.label:Hide()
    card.kind:Hide()
    card.verdict:Hide()
    card.mark:Hide()
    card.name:SetWidth(inner)
    setText(card.name, GC.L["Nothing in your bags to disenchant."])
    colour(card.name, K.text2)
    nameH = math.ceil(heightOf(card.name, 12))
  end
  local textH = labelH + M.LINE_GAP + nameH + (kindH > 0 and (M.LINE_GAP + kindH) or 0)
  visit.topH = math.max(visit.topH, row and math.max(M.ICON, textH) or nameH)

  local y = M.CARD_PAD
  card.slot.edge:ClearAllPoints()
  card.slot.edge:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
  card.counter:ClearAllPoints()
  card.counter:SetPoint("TOPRIGHT", card, "TOPLEFT", w - M.CARD_PAD, -y)
  card.label:ClearAllPoints()
  card.label:SetPoint("TOPLEFT", card, "TOPLEFT", textX, -y)
  card.name:ClearAllPoints()
  if row then
    card.name:SetWidth(textW)
    card.name:SetPoint("TOPLEFT", card, "TOPLEFT", textX, -(y + labelH + M.LINE_GAP))
  else
    card.name:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
  end
  card.kind:ClearAllPoints()
  card.kind:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -M.LINE_GAP)
  y = y + visit.topH + M.BLOCK_GAP
  card.mark:ClearAllPoints()
  card.mark:SetPoint("TOPLEFT", card, "TOPLEFT", x, -(y + 1))
  card.verdict:SetWidth(verdictW)
  card.verdict:ClearAllPoints()
  card.verdict:SetPoint("TOPLEFT", card, "TOPLEFT", x + M.VERDICT_ICON + M.VERDICT_GAP, -y)
  y = y + visit.verdictH + M.BLOCK_GAP

  -- The cast's bar: its room kept whether a cast goes or not.
  local bar = card.bar
  setText(bar.label, GC.L["Disenchanting"])
  local barLabelH = math.ceil(heightOf(bar.label, 11))
  local barH = barLabelH + 2 + M.BAR_H
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
  bar:SetSize(inner, barH)
  bar.label:ClearAllPoints()
  bar.label:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  bar.track:ClearAllPoints()
  bar.track:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  bar.track:SetSize(inner, M.BAR_H)
  bar.fill:ClearAllPoints()
  bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  bar.fill:SetSize(1, M.BAR_H)
  bar:SetShown(casting ~= nil)
  y = y + barH + M.BLOCK_GAP

  local skip = card.skip
  skip:SetLabel(GC.L["Skip"])
  skip:FitLabels({ GC.L["Skip"] }, M.SKIP_MIN)
  if row and not casting then skip:Enable() else skip:Disable() end
  local skipW = skip:GetWidth()
  paintCast(casting and "casting" or (row and "ready" or "idle"), inner - skipW - M.BUTTON_GAP)
  card.cast:ClearAllPoints()
  card.cast:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
  skip:ClearAllPoints()
  skip:SetPoint("TOPRIGHT", card, "TOPLEFT", w - M.CARD_PAD, -y)
  y = y + M.BUTTON_H + M.BLOCK_GAP

  local where = _G.SETTINGS_KEYBINDINGS_LABEL or _G.KEY_BINDINGS or ""
  card.keys:SetWidth(inner)
  setText(card.keys, GC.L["One press, one item. A key works too: %s, GoldCap, %s."]:format(where, GC.L["Disenchant next"]))
  card.keys:ClearAllPoints()
  card.keys:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
  y = y + math.ceil(heightOf(card.keys, 11)) + M.CARD_PAD
  return y
end

-- The yield strip, `w` wide: what this visit got, exactly, once something was disenchanted; else
-- what the queue gives by what GoldCap has learned, "~" each, and its worth when every item's mats
-- are known; with nothing learned for the queue, the line that says GoldCap learns it. Nothing with
-- an empty queue and nothing got. Answers its height.
local function paintStrip(plan, w)
  local strip, visit = frame.strip, DF._visit
  local got = next(visit.got) ~= nil
  local mats = got and visit.got or plan.yields
  local any = next(mats) ~= nil
  for _, chip in ipairs(strip.chips) do
    chip.icon:Hide()
    chip.count:Hide()
    chip.name:Hide()
  end
  if not got and #plan.queue == 0 then
    strip:Hide()
    return 0
  end
  local value
  if got then
    value = worthOf(visit.got)
  elseif any then
    value = plan.matsTotal
  end
  local inner = w - 2 * M.STRIP_PAD
  setText(strip.value, value and value > 0 and money(value) or "")
  strip.value:SetShown(value ~= nil and value > 0)
  local valueW = strip.value:IsShown() and math.ceil(strip.value:GetStringWidth() or 0) + 8 or 0
  local label = got and GC.L["Got so far"] or (any and GC.L["You get about"]
    or GC.L["GoldCap learns what these give as you disenchant."])
  strip.label:SetWidth(math.max(1, inner - valueW))
  setText(strip.label, label)
  local labelH = math.ceil(heightOf(strip.label, 12))
  strip.label:ClearAllPoints()
  strip.label:SetPoint("TOPLEFT", strip, "TOPLEFT", M.STRIP_PAD, -M.STRIP_PAD)
  strip.value:ClearAllPoints()
  strip.value:SetPoint("TOPRIGHT", strip, "TOPLEFT", w - M.STRIP_PAD, -M.STRIP_PAD)
  local y = M.STRIP_PAD + labelH
  if any then
    local ids = {}
    for itemID in pairs(mats) do ids[#ids + 1] = itemID end
    table.sort(ids)
    y = y + M.MAT_LINE
    local cx, lineH = 0, 0
    for i, itemID in ipairs(ids) do
      local chip = chipAt(i)
      setText(chip.count, unitsText(mats[itemID], got))
      local countW = math.ceil(chip.count:GetStringWidth() or 0)
      local nameText = C_Item and ask(C_Item.GetItemNameByID, itemID) or ""
      setText(chip.name, nameText)
      local fixed = M.MAT_ICON + 3 + countW + 4
      local nameW = math.ceil(chip.name:GetUnboundedStringWidth() or 0)
      if cx > 0 and cx + fixed + nameW > inner then
        y = y + lineH + M.MAT_LINE
        cx, lineH = 0, 0
      end
      chip.name:SetWidth(math.max(1, math.min(nameW, inner - cx - fixed)))
      local h = math.max(M.MAT_ICON, math.ceil(heightOf(chip.name, 12)))
      chip.icon:SetTexture(iconOf(itemID) or 134400)
      chip.icon:ClearAllPoints()
      chip.icon:SetPoint("TOPLEFT", strip, "TOPLEFT", M.STRIP_PAD + cx, -y)
      chip.count:ClearAllPoints()
      chip.count:SetPoint("LEFT", chip.icon, "RIGHT", 3, 0)
      chip.name:ClearAllPoints()
      chip.name:SetPoint("TOPLEFT", strip, "TOPLEFT", M.STRIP_PAD + cx + fixed, -(y + 2))
      for _, part in ipairs({ chip.icon, chip.count, chip.name }) do part:Show() end
      cx = cx + fixed + math.ceil(chip.name:GetWidth() or nameW) + M.MAT_GAP
      lineH = math.max(lineH, h)
    end
    y = y + lineH
  end
  strip:Show()
  return y + M.STRIP_PAD
end

-- A figure bold or not, in the mono face.
local function setBold(fs, bold)
  local T = GC.Theme
  local path = bold and T.FONT_UI_BOLD or T.FONT_UI
  fs:SetFont(path, 10 * T.Scale(), "")
  T.TrackFont(fs, { role = bold and "uiBold" or "ui", path = path, size = 10 })
end

-- A line of "In this order": `data` is a plan row; `state` "done" (this visit), "casting" or nil.
-- Answers its height.
local function paintRow(row, data, state, inner, colW)
  local stack = data.stack
  row.itemID, row.link, row.done = stack.itemID, stack.link, state == "done"
  HF.Row.PaintIcon(row.slot, stack.itemID, iconOf(stack.itemID), nil, state == "done" and "moved" or nil)
  local nameX = M.ROW_PAD + M.ROW_ICON + 6
  local nameW = inner - nameX - 2 * colW - M.COL_GAP - M.ROW_PAD - 6
  row.name:SetWidth(math.max(1, nameW))
  setText(row.name, nameOf(stack))
  colour(row.name, qualityColour(stack.quality))
  local h = math.max(M.ROW_MIN_H, math.ceil(heightOf(row.name, 12)) + 2 * M.ROW_PAD)
  row.slot.edge:ClearAllPoints()
  row.slot.edge:SetPoint("TOPLEFT", row, "TOPLEFT", M.ROW_PAD, -math.floor((h - M.ROW_ICON) / 2))
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", row, "LEFT", nameX, 0)
  local best = data.best
  setText(row.mats, data.mats and ("~" .. money(data.mats)) or "?")
  setText(row.vendor, money(data.vendor))
  setBold(row.mats, best == "mats")
  setBold(row.vendor, best == "vendor")
  colour(row.mats, best == "mats" and MATS_C or LOSER_C)
  colour(row.vendor, best == "vendor" and VENDOR_C or (data.mats == nil and best ~= "ah" and K.text2 or LOSER_C))
  for i, fs in ipairs({ row.vendor, row.mats }) do
    fs:SetWidth(colW)
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", row, "LEFT", inner - M.ROW_PAD - (i - 1) * (colW + M.COL_GAP), 0)
  end
  local casting = state == "casting"
  local fill, ring = casting and ROW_CAST_FILL or K.glassBottom, casting and ROW_CAST_RING or K.hairline
  row.bg:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)
  row.ring:SetVertexColor(ring[1], ring[2], ring[3], ring[4] or 1)
  row:SetAlpha(state == "done" and DONE_ALPHA or 1)
  row:SetSize(inner, h)
  return h
end

-- How wide the Mats and Vendor columns must be for `rows`' figures and their heads.
local function columnWidth(rows)
  local widest = M.COL_MIN
  local function measure(text)
    setText(frame.measure, text)
    widest = math.max(widest, math.ceil(frame.measure:GetStringWidth() or 0))
  end
  for _, data in ipairs(rows) do
    measure(data.mats and ("~" .. money(data.mats)) or "?")
    measure(money(data.vendor))
  end
  for _, head in ipairs({ frame.matsHead, frame.vendorHead }) do
    widest = math.max(widest, math.ceil(head:GetStringWidth() or 0))
  end
  return widest
end

-- "In this order": its heading and column heads `top` down the window, over the scroll, and its
-- lines in the scroll: the items done this visit, then the queue. Answers the heading's height and
-- the lines' (0 and 0 with none).
local function paintOrder(plan, inner, top)
  local visit, casting = DF._visit, castingNow()
  local lines = {}
  for _, data in ipairs(visit.done) do lines[#lines + 1] = { data = data, state = "done" } end
  for _, data in ipairs(plan.queue) do
    local state = casting and casting.row.slotKey == data.slotKey and "casting" or nil
    lines[#lines + 1] = { data = data, state = state }
  end
  local any = #lines > 0
  for _, part in ipairs({ frame.orderTitle, frame.matsHead, frame.vendorHead }) do part:SetShown(any) end
  local index, headH, cy = 1, 0, 0
  if any then
    setText(frame.orderTitle, GC.Util.Upper(GC.L["In this order"]))
    setText(frame.matsHead, GC.Util.Upper(GC.L["Mats"]))
    setText(frame.vendorHead, GC.Util.Upper(GC.L["Vendor"]))
    local datas = {}
    for i, line in ipairs(lines) do datas[i] = line.data end
    local colW = columnWidth(datas)
    frame.orderTitle:ClearAllPoints()
    frame.orderTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -top)
    for i, head in ipairs({ frame.vendorHead, frame.matsHead }) do
      head:SetWidth(colW)
      head:ClearAllPoints()
      head:SetPoint("TOPRIGHT", frame, "TOPLEFT", L.PAD + inner - M.ROW_PAD - (i - 1) * (colW + M.COL_GAP), -top)
    end
    headH = math.ceil(heightOf(frame.orderTitle, 11)) + M.HEADING_GAP
    for _, line in ipairs(lines) do
      local row = DF._rows[index] or newRow()
      DF._rows[index] = row
      local wasUp = row:IsShown()
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -cy)
      row:Show()
      cy = cy + paintRow(row, line.data, line.state, inner, colW) + M.ROW_GAP
      if not wasUp and frame:IsShown() then restamp(row) end
      index = index + 1
    end
    cy = cy - M.ROW_GAP
  end
  for i = index, #DF._rows do DF._rows[i]:Hide() end
  return headH, cy
end

-- A line of "Left out". Answers its height.
local function paintLeftRow(row, data, inner)
  local stack = data.stack
  row.itemID, row.link = stack.itemID, stack.link
  HF.Row.PaintIcon(row.slot, stack.itemID, iconOf(stack.itemID), nil, nil)
  setText(row.price, money(data.ah))
  local priceW = math.ceil(row.price:GetStringWidth() or 0)
  local anyway = row.anyway
  anyway.slotKey = data.slotKey
  anyway:SetLabel(GC.L["Disenchant anyway"])
  anyway:FitLabels({ GC.L["Disenchant anyway"] }, M.ANYWAY_MIN)
  colour(anyway.text, U.QUIET.textColor)
  local rightW = math.max(priceW, anyway:GetWidth())
  local nameX = M.ROW_PAD + M.ROW_ICON + 6
  local nameW = math.max(1, inner - nameX - rightW - 8 - M.ROW_PAD)
  row.name:SetWidth(nameW)
  setText(row.name, nameOf(stack))
  colour(row.name, qualityColour(stack.quality))
  -- The note: what its mats would give, and how many sell a day or that it sells slowly, as the
  -- craft panel says it (UI/CraftPanel.lua's paintRow: never both).
  local notes = {}
  if data.mats then notes[#notes + 1] = GC.L["Mats: about %s"]:format(money(data.mats)) end
  local sold = select(2, GC.CraftClient.SellOf(stack.itemID))
  if type(sold) == "number" then
    notes[#notes + 1] = GC.CraftMath.IsSlow(sold) and GC.L["Slow seller"]
      or GC.L["Sells about %s a day"]:format(GC.Util.Grouped(sold))
  end
  row.note:SetWidth(nameW)
  setText(row.note, table.concat(notes, "\n"))
  row.note:SetShown(#notes > 0)
  local textH = math.ceil(heightOf(row.name, 12)) + (#notes > 0 and (2 + math.ceil(heightOf(row.note, 11))) or 0)
  local rightH = math.ceil(heightOf(row.price, 12)) + 4 + M.ANYWAY_H
  local h = math.max(M.ROW_MIN_H, textH + 2 * M.ROW_PAD, rightH + 2 * M.ROW_PAD)
  row.slot.edge:ClearAllPoints()
  row.slot.edge:SetPoint("TOPLEFT", row, "TOPLEFT", M.ROW_PAD, -M.ROW_PAD)
  row.name:ClearAllPoints()
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", nameX, -M.ROW_PAD)
  row.note:ClearAllPoints()
  row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
  row.price:ClearAllPoints()
  row.price:SetPoint("TOPRIGHT", row, "TOPLEFT", inner - M.ROW_PAD, -M.ROW_PAD)
  anyway:ClearAllPoints()
  anyway:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -M.ROW_PAD, M.ROW_PAD)
  row:SetSize(inner, h)
  return h
end

-- "Left out: the auction house pays more", when there is any, in its own box under the scroll (the
-- caller places the box). Answers the box's height, 0 with none.
local function paintLeft(plan, inner)
  local any = #plan.left > 0
  frame.leftTitle:SetShown(any)
  frame.leftBox:SetShown(any)
  local index, cy = 1, 0
  if any then
    frame.leftTitle:SetWidth(inner)
    setText(frame.leftTitle, GC.Util.Upper(GC.L["Left out: the auction house pays more"]))
    frame.leftTitle:ClearAllPoints()
    frame.leftTitle:SetPoint("TOPLEFT", frame.leftBox, "TOPLEFT", 0, 0)
    cy = cy + math.ceil(heightOf(frame.leftTitle, 11)) + M.HEADING_GAP
    for _, data in ipairs(plan.left) do
      local row = DF._leftRows[index] or newLeftRow()
      DF._leftRows[index] = row
      local wasUp = row:IsShown()
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", frame.leftBox, "TOPLEFT", 0, -cy)
      row:Show()
      cy = cy + paintLeftRow(row, data, inner) + M.ROW_GAP
      if not wasUp and frame:IsShown() then restamp(row) end
      index = index + 1
    end
    cy = cy - M.ROW_GAP
  end
  for i = index, #DF._leftRows do DF._leftRows[i]:Hide() end
  return cy
end

-- The footer at the window's foot, `w` wide: what Mats means and what never comes on the list, then
-- the Hoard's price line under its dot. Answers its height.
local function paintFooter(w)
  frame.footer:SetWidth(w)
  setText(frame.footer, GC.L["Mats is what your own disenchants of such items gave, at today's prices. Never on the list: items in an equipment set, items you can still return or trade, items in a group you follow, and items you keep. Right-click a line to keep an item."])
  local text, fresh = HF.Footer.PricesNow()
  frame.prices:SetWidth(w - M.DOT - M.DOT_GAP)
  setText(frame.prices, text)
  local c = fresh and K.profit or K.warn
  frame.dot:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  local footH = math.ceil(heightOf(frame.footer, 12))
  local pricesH = math.ceil(heightOf(frame.prices, 12))
  frame.prices:ClearAllPoints()
  frame.prices:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", L.PAD + M.DOT + M.DOT_GAP, L.PAD)
  frame.dot:ClearAllPoints()
  frame.dot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", L.PAD, L.PAD + math.floor((math.min(pricesH, 12) - M.DOT) / 2))
  frame.footer:ClearAllPoints()
  frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", L.PAD, L.PAD + pricesH + M.FOOT_GAP)
  return footH + M.FOOT_GAP + pricesH
end

-- The Kept line over the footer, `w` wide with its foot `y` above the window's: how many items are
-- kept and the button that opens them. Answers its height, 0 with none kept.
local function paintKept(w, y)
  local kept = frame.kept
  local n = #D.KeptIDs(GC.db)
  kept.text:SetShown(n > 0)
  kept.show:SetShown(n > 0)
  if n == 0 then return 0 end
  kept.show:SetLabel(GC.L["Show"])
  kept.show:FitLabels({ GC.L["Show"] }, M.ANYWAY_MIN / 2)
  colour(kept.show.text, U.QUIET.textColor)
  local buttonW = kept.show:GetWidth()
  kept.text:SetWidth(math.max(1, w - buttonW - M.COL_GAP))
  setText(kept.text, n == 1 and GC.L["Kept: 1 item"] or GC.L["Kept: %d items"]:format(n))
  local textH = math.ceil(heightOf(kept.text, 12))
  local h = math.max(M.ANYWAY_H, textH)
  kept.text:ClearAllPoints()
  kept.text:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", L.PAD, y + math.floor((h - textH) / 2))
  kept.show:ClearAllPoints()
  kept.show:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", L.PAD + w - buttonW, y + math.floor((h - M.ANYWAY_H) / 2))
  return h
end

-- The most the window may be tall: from its top (the bags' top) down to the room the Hoard leaves
-- above the action bars, or the screen less twice that where it stands without the bags; and never
-- more than HEIGHT_SHARE of the screen (the owner, 2026-10-26: sixteen items made it the screen's
-- full height).
local function roomHeight()
  local room = DF._top and math.max(L.MIN_H, DF._top - L.SCREEN_GAP) or U.maxHeight(nil)
  local screen = UIParent and UIParent.GetHeight and UIParent:GetHeight()
  if type(screen) == "number" and screen > 0 then room = math.min(room, math.floor(screen * DF.HEIGHT_SHARE)) end
  return room
end

-- The window, top to bottom: the header, the Next card, the yield strip and "In this order"'s
-- heading, fixed; its lines in the scroll; "Left out" under the scroll and the footer at the
-- window's foot, fixed. Never taller than roomHeight while the scroll keeps one line's room: the
-- lines scroll, everything else stays in view. Laid out, not shown.
local function paint()
  local plan = DF._plan
  local width = L.WIDTH
  local head, inner = width - 2 * L.PAD, width - 2 * L.PAD - L.GUTTER
  frame:SetWidth(width)
  setText(frame.brand, "GoldCap")
  setText(frame.title, GC.L["Disenchant"])
  -- The approved board's header: "Disenchant" under "GoldCap", the two beside the mark and level
  -- with its middle, the X level with it too.
  local brandH, titleH = math.ceil(heightOf(frame.brand, 18)), math.ceil(heightOf(frame.title, 14))
  local nameH = brandH + M.TITLE_GAP + titleH
  local headH = math.max(L.HEAD_H, nameH)
  frame.logo:ClearAllPoints()
  frame.logo:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -(L.PAD + math.floor((headH - L.LOGO) / 2)))
  frame.brand:ClearAllPoints()
  frame.brand:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD + L.LOGO + 7, -(L.PAD + math.floor((headH - nameH) / 2)))
  frame.title:ClearAllPoints()
  frame.title:SetPoint("TOPLEFT", frame.brand, "BOTTOMLEFT", 0, -M.TITLE_GAP)
  frame.close:ClearAllPoints()
  frame.close:SetPoint("TOPRIGHT", frame, "TOPLEFT", L.PAD + head, -(L.PAD + math.floor((headH - L.CLOSE) / 2)))
  local y = L.PAD + headH + M.SECTION_GAP
  local cardH = paintCard(plan, head)
  frame.card:ClearAllPoints()
  frame.card:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -y)
  frame.card:SetSize(head, cardH)
  y = y + cardH + M.SECTION_GAP
  local stripH = paintStrip(plan, head)
  if stripH > 0 then
    frame.strip:ClearAllPoints()
    frame.strip:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -y)
    frame.strip:SetSize(head, stripH)
    y = y + stripH + M.SECTION_GAP
  end
  local orderH, rowsH = paintOrder(plan, inner, y)
  local top = y + orderH
  local leftH = paintLeft(plan, inner)
  local leftBlock = leftH > 0 and (M.SECTION_GAP + leftH) or 0
  local footH = paintFooter(head)
  local keptH = paintKept(head, L.PAD + footH + M.FOOT_GAP)
  local foot = L.PAD + footH + (keptH > 0 and keptH + M.FOOT_GAP or 0) + M.SECTION_GAP
  frame.content:SetSize(inner, math.max(1, rowsH))
  local fixed = top + leftBlock + foot
  local least = fixed + math.min(rowsH, M.ROW_MIN_H)
  local height = math.min(fixed + rowsH, math.max(least, roomHeight()))
  local scrollH = math.max(1, height - fixed)
  frame:SetHeight(height)
  frame.scroll:ClearAllPoints()
  frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -top)
  frame.scroll:SetSize(inner, scrollH)
  if leftH > 0 then
    frame.leftBox:ClearAllPoints()
    frame.leftBox:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -(top + scrollH + M.SECTION_GAP))
    frame.leftBox:SetSize(inner, leftH)
  end
end

-- The marks on the bag slots, from the plan just read (UI/DisenchantMarks.lua): drawn while Blizzard's
-- bags are open, off otherwise. `bags`: the open bag frame, or nil. `fight`: in combat.
local function paintMarks(bags, fight)
  local marks = GC.DisenchantMarks
  if not marks then return end
  if bags and DF._plan then marks.Paint(DF._plan, spellIcon(), fight) else marks.Clear() end
end

-- The entry above the bags' top right, with how many are queued; hidden with the bags closed or
-- nothing queued. `bags`: the open bag frame, or nil.
local function paintEntry(bags)
  local n = DF._plan and #DF._plan.queue or 0
  if not bags or n == 0 then
    if entry then entry:Hide() end
    return
  end
  if not entry then buildEntry() end
  entry:ClearAllPoints()
  entry:SetPoint("BOTTOMRIGHT", bags, "TOPRIGHT", 0, M.ENTRY_GAP)
  setText(entry.count, tostring(n))
  local pillW = math.max(M.ENTRY_COUNT, math.ceil(entry.count:GetStringWidth() or 0) + 6)
  entry.pill:ClearAllPoints()
  entry.pill:SetPoint("CENTER", entry, "TOPRIGHT", -3, -3)
  entry.pill:SetSize(pillW, M.ENTRY_COUNT)
  entry.count:ClearAllPoints()
  entry.count:SetPoint("CENTER", entry.pill, "CENTER", 0, 0)
  local wasUp = entry:IsShown()
  entry:Show()
  if not wasUp then restamp(entry) end
  local tooltip = _G.GameTooltip
  if tooltip and tooltip.IsOwned and tooltip:IsOwned(entry) then showEntryTip(entry) end
end

-- ---------------------------------------------------------------------------------------------
-- Opening, closing, refreshing
-- ---------------------------------------------------------------------------------------------

-- Blizzard's bag frames: the combined backpack and each separate bag, the reagent bag's too
-- (ContainerFrame.xml:283-290; NUM_CONTAINER_FRAMES, ContainerFrame.lua:5).
local function bagNames()
  local names = { "ContainerFrameCombinedBags" }
  for i = 1, tonumber(_G.NUM_CONTAINER_FRAMES) or 6 do names[#names + 1] = "ContainerFrame" .. i end
  return names
end

-- The left edge of the leftmost of Blizzard's bag frames that show and the top of the highest, in
-- UIParent's units; nil with none showing (or none laid out yet).
local function bagEdges()
  local ui = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
  if type(ui) ~= "number" or ui <= 0 then return nil end
  local left, top
  for _, name in ipairs(bagNames()) do
    local f = _G[name]
    if type(f) == "table" and f.IsVisible and f:IsVisible() then
      local l = f.GetLeft and f:GetLeft()
      local t = f.GetTop and f:GetTop()
      local scale = f.GetEffectiveScale and f:GetEffectiveScale()
      if type(l) == "number" and type(t) == "number" and type(scale) == "number" then
        local k = scale / ui
        left = math.min(left or math.huge, l * k)
        top = math.max(top or -math.huge, t * k)
      end
    end
  end
  return left, top
end

-- Left of the leftmost bag frame that shows, its top level with the highest, at the coordinates
-- they have now (the engine keeps it on the screen: SetClampedToScreen). With no bags of Blizzard's
-- open: in the middle of the screen as it opens (`opening`), else where it stands. Out of combat
-- only: as it opens, and when a bag frame shows or hides while it is open (`replace`).
local function place(opening)
  local left, top = bagEdges()
  if left then
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - L.X, top)
    DF._top = top
  elseif opening then
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    DF._top = nil
  end
end

local function openNow()
  if not frame then build() end
  newVisit()
  DF._replace = nil
  place(true)
  DF._plan = readPlan()
  paint()
  frame:Show()
  restamp(frame)
  for _, row in ipairs(DF._rows) do
    if row:IsShown() then restamp(row) end
  end
  for _, row in ipairs(DF._leftRows) do
    if row:IsShown() then restamp(row) end
  end
  arm()
  paintEntry(bagFrame())
end

--- Closes the window, its button pointed at nothing. Out of combat only (onCloseClick, Toggle).
function DF.Close()
  setArmed(nil)
  if frame then frame:Hide() end
end

-- A character that does not know Disenchant (any more): nothing of the window stands.
local function hideAll()
  if GC.DisenchantMarks then GC.DisenchantMarks.Clear() end
  if entry then entry:Hide() end
  if frame and frame:IsShown() and not inCombat() then DF.Close() end
end

-- In combat: the entry follows the bags with what the last paint read, and nothing else moves.
local function holdEntry()
  paintMarks(bagFrame(), true)
  if not entry then return end
  local bags = bagFrame()
  if bags and DF._plan and #DF._plan.queue > 0 then
    entry:ClearAllPoints()
    entry:SetPoint("BOTTOMRIGHT", bags, "TOPRIGHT", 0, M.ENTRY_GAP)
    entry:Show()
  else
    entry:Hide()
  end
end

-- Reads the bags and paints the window and the entry, or hides them. In combat only the entry
-- follows the bags; the rest waits for PLAYER_REGEN_ENABLED (`dirty`), and with it the window's
-- opening or closing asked for meanwhile (`wantShown`). With neither the window nor Blizzard's bags
-- open nothing is read.
refresh = function()
  DF._queued = nil
  if not DF.Known() then return hideAll() end
  if inCombat() then
    DF._dirty = true
    return holdEntry()
  end
  DF._dirty = nil
  local up = frame ~= nil and frame:IsShown()
  local want = DF._wantShown
  if DF._openNext and not up then want = true end
  DF._wantShown, DF._openNext = nil, nil
  if want == true and not up then return openNow() end
  if want == false and up then
    DF.Close()
    up = false
  end
  if up and DF._replace then place(false) end
  DF._replace = nil
  local bags = bagFrame()
  if not (up or bags) then
    if entry then entry:Hide() end
    return paintMarks(nil)
  end
  DF._plan = readPlan()
  paintEntry(bags)
  paintMarks(bags)
  if up then
    paint()
    arm()
  end
end

--- Paints the window and the entry again now (a click's paint); in combat, once the fight is over.
function DF.Refresh()
  refresh()
end

--- Opens or closes the window: the entry's click and /gc disenchant. In combat the window cannot be
--- shown or hidden: it then does so once the fight is over. A character without Disenchant is told so.
function DF.Toggle()
  if not DF.Known() then
    GC.Print(GC.L["This character does not know Disenchant."])
    return
  end
  local up = frame ~= nil and frame:IsShown()
  if inCombat() then
    local shown = DF._wantShown
    if shown == nil then shown = up end
    DF._wantShown = not shown
    return
  end
  DF._wantShown, DF._openNext = nil, nil
  if up then DF.Close() else openNow() end
end

GC.slashHandlers = GC.slashHandlers or {}
GC.slashHandlers.disenchant = function() DF.Toggle() end

-- ---------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------

-- The client's words for an item it will not disenchant (GlobalStrings), as UI_ERROR_MESSAGE
-- carries them.
local function refused(message)
  if type(message) ~= "string" then return false end
  for _, name in ipairs({ "ERR_CANT_BE_DISENCHANTED", "SPELL_FAILED_CANT_BE_DISENCHANTED",
    "SPELL_FAILED_CANT_BE_DISENCHANTED_SKILL" }) do
    if _G[name] == message then return true end
  end
  return false
end

local function ours(unit, spellID)
  return plain(unit) == "player" and plain(spellID) == D.SPELL
end

-- What the loot window holds now: { [itemID] = units }.
local function readLoot()
  local mats = {}
  local n = ask(_G.GetNumLootItems) or 0
  for i = 1, n do
    local link = plain(ask(_G.GetLootSlotLink, i))
    local itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    if itemID then
      local ok, _, _, quantity = pcall(_G.GetLootSlotInfo, i)
      quantity = ok and plain(quantity) or nil
      if type(quantity) == "number" and quantity > 0 then mats[itemID] = (mats[itemID] or 0) + quantity end
    end
  end
  return mats
end

-- Built for a character that knows Disenchant, out of combat, so its key works before the window was
-- first opened: a press then opens it.
local function prepare()
  if frame or inCombat() or not DF.Known() then return end
  build()
end

-- A key bound to the button clicks it in combat too, while the driver hides it, and in combat its
-- PreClick cannot clear it: a press after the bags changed in the fight (the item disenchanted, loot
-- landing in its slot) would cast at whatever the slot then holds. So as the fight begins the button
-- is pointed at nothing, and the window repaints, and arms, once it is over. Only while the client
-- still allows it (InCombatLockdown false as PLAYER_REGEN_DISABLED is handled, not measured in game):
-- when it does not, nothing is touched and the button keeps the item the window names.
local function disarmForCombat()
  if not DF._armed or inCombat() then return end
  setArmed(nil)
  DF._dirty = true
end

-- The cast START bound to a press (`casting`, its GUID and its press), when `guid` is that cast's.
local function castOf(guid)
  local casting = DF._casting
  if casting and casting.castGUID ~= nil and casting.castGUID == guid then return casting end
  return nil
end

local function onCastStart(castGUID)
  local p = pendingNow()
  if not p or p.castGUID or p.over then return end
  p.castGUID = plain(castGUID)
  DF._casting = { row = p.row, at = now(), castGUID = p.castGUID, press = p }
  schedule()
end

-- The cast START bound answers its press however long the press waited; else a press still waiting
-- whose cast was not seen to start.
local function onCastSucceeded(castGUID)
  local guid = plain(castGUID)
  local casting = castOf(guid)
  local p = casting and casting.press or pendingNow()
  if not (p and not p.over and (p.castGUID == nil or p.castGUID == guid)) then return end
  local visit = DF._visit
  DF._loot = { kind = p.kind, untilT = now() + DF.LOOT_SECONDS }
  visit.done[#visit.done + 1] = p.row
  visit.gone[p.slotKey] = p.link
  DF._pending, DF._casting = nil, nil
  schedule()
end

-- Only the cast this window saw start answers its press. A failure before any start can be a second
-- press's ("Another action is in progress"), so it is left alone: the press then waits out
-- PENDING_SECONDS, and an item the client refuses is still dropped by its words (onError).
local function onCastFailed(castGUID)
  local casting = castOf(plain(castGUID))
  if not casting then return end
  casting.press.over = true
  DF._casting = nil
  schedule()
end

local function onLootReady()
  local loot = DF._loot
  if not loot then return end
  DF._loot = nil
  if now() > loot.untilT then return end
  local mats = readLoot()
  if next(mats) == nil then return end
  D.Learn(GC.db, loot.kind, mats)
  local got = DF._visit.got
  for itemID, units in pairs(mats) do got[itemID] = (got[itemID] or 0) + units end
  schedule()
end

local function onError(message)
  local p = pendingNow()
  if not p or not refused(plain(message)) then return end
  DF._visit.failed[p.itemID] = true
  DF._pending, DF._casting = nil, nil
  schedule()
end

--- The window's events, as its own event frame below hears them. PLAYER_LOGIN: the key binding's
--- label in the player's language (chosen at ADDON_LOADED, after every file loaded), and the window
--- built for an enchanter. SPELLS_CHANGED: built once Disenchant is learned; with the window open,
--- a paint, which closes it once the spell is gone. BAG_UPDATE_DELAYED: a paint on the next frame.
--- PLAYER_REGEN_DISABLED: the button pointed at nothing while the client still allows it (see
--- disarmForCombat), and the fight remembered. PLAYER_REGEN_ENABLED: what combat held, a paint of an
--- open window (the button is armed again), and the window built for an enchanter who logged in
--- during a fight. EQUIPMENT_SETS_CHANGED: a paint, as for the bags (an item saved into a set leaves
--- the list). The spell's events and LOOT_READY and UI_ERROR_MESSAGE: what this
--- button's press did.
function DF.OnEvent(event, ...)
  if event == "PLAYER_LOGIN" then
    _G["BINDING_NAME_" .. DF.BINDING] = GC.L["Disenchant next"]
    return prepare()
  elseif event == "SPELLS_CHANGED" then
    prepare()
    if (frame and frame:IsShown()) or bagFrame() then schedule() end
  elseif event == "BAG_UPDATE_DELAYED" or event == "EQUIPMENT_SETS_CHANGED" then
    if (frame and frame:IsShown()) or (bagFrame() and DF.Known()) then schedule() end
  elseif event == "PLAYER_REGEN_DISABLED" then
    disarmForCombat()
    DF._fight = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    DF._fight = nil
    prepare()
    if DF._dirty or DF._wantShown ~= nil or (frame and frame:IsShown()) then schedule() end
  elseif event == "UNIT_SPELLCAST_START" then
    local unit, castGUID, spellID = ...
    if ours(unit, spellID) then onCastStart(castGUID) end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, castGUID, spellID = ...
    if ours(unit, spellID) then onCastSucceeded(castGUID) end
  elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
    local unit, castGUID, spellID = ...
    if ours(unit, spellID) then onCastFailed(castGUID) end
  elseif event == "LOOT_READY" then
    onLootReady()
  elseif event == "UI_ERROR_MESSAGE" then
    local _, message = ...
    onError(message)
  end
end

-- Blizzard's bags opening or closing show or hide the entry and move an open window beside them: a
-- post-hook on each bag frame's own show and hide (Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml),
-- which only marks the move (`replace`) and paints, on the next frame (in combat, once it is over).
for _, name in ipairs(bagNames()) do
  local bags = _G[name]
  if type(bags) == "table" and type(bags.HookScript) == "function" then
    local function changed()
      if not DF.Known() then return end
      DF._replace = true
      schedule()
    end
    pcall(bags.HookScript, bags, "OnShow", changed)
    pcall(bags.HookScript, bags, "OnHide", changed)
  end
end

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  for _, name in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "BAG_UPDATE_DELAYED", "EQUIPMENT_SETS_CHANGED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "LOOT_READY", "UI_ERROR_MESSAGE" }) do
    pcall(events.RegisterEvent, events, name)
  end
  for _, name in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED" }) do
    if type(events.RegisterUnitEvent) == "function" then
      pcall(events.RegisterUnitEvent, events, name, "player")
    else
      pcall(events.RegisterEvent, events, name)
    end
  end
  events:SetScript("OnEvent", function(_, event, ...) DF.OnEvent(event, ...) end)
  DF._events = events
end
