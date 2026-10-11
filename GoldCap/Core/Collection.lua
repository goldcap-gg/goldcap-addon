local _, GC = ...

-- Collection marks for the Items board: has this account already collected what a realm row
-- sells? The board is not this file's. It asks State(itemID[, petSpeciesID]) when it paints a
-- row (inside the row's ContinueOnItemLoad, so the item's own data is in), draws a mark only on
-- "missing", and repaints through OnChange when a collection changes.
--
--   "collected"  this item's appearance source, this pet species, toy or mount is the
--                account's. A recipe: the CURRENT character knows it (no API answers for alts).
--   "elsewhere"  the appearance is the account's through another item of the same class and
--                subclass, or through a cosmetic one. CanIMogIt's rule: a mail chest sharing a
--                cloth chest's model does not make the cloth one collected.
--   "missing"    the client said so, out of data it had loaded.
--   "unknown"    the client has not said: a function absent, a call that raised, data not
--                loaded yet, or a collection the game does not fill (WoW: Forever, unverified).
--   nil          not a collectible this module understands (a trade good, a ring); kind nil.
--
-- The rule everything below keeps: "missing" is never read off an absence. A function that is
-- not there, a pcall that failed, a nil where a bool belongs, each is "unknown", and "unknown"
-- draws nothing. A wrong "not collected" mark tells a player to spend gold on what they already
-- own; a mark that is not drawn costs nothing.
--
-- Every client read goes through `call`, which looks the function up at call time on the client
-- table: the real _G, or the API-shaped fake a spec hands in through SetClient. A game that
-- lacks a function, or a later patch that drops one, degrades to "unknown" instead of an error.
-- All of them exist on both games (wowsrc.py, live 12.1.0 69933 and forever 1.60.1 70338);
-- PlayerHasToy, C_ToyBox.GetToyInfo and the C_PetJournal reads are undocumented there and taken
-- from Blizzard's own callers (Blizzard_ToyBox.lua, DressUpFrames.lua, Blizzard_PetBattleUI.lua)
-- on both branches. Whether Forever's servers fill these collections at all is for an in-game
-- probe to measure, not for this file to assume.
GC.Collection = {}

local COLLECTED, ELSEWHERE, MISSING, UNKNOWN = "collected", "elsewhere", "missing", "unknown"

-- Enum.ItemClass / ItemArmorSubclass / ItemMiscellaneousSubclass, identical on both branches.
local CLASS_WEAPON, CLASS_ARMOR, CLASS_RECIPE, CLASS_MISC, CLASS_BATTLEPET = 2, 4, 9, 15, 17
local ARMOR_MISC, ARMOR_COSMETIC = 0, 5
local MISC_COMPANION_PET, MISC_MOUNT = 2, 5

-- The slots an appearance can be worn in: CanIMogIt's inventorySlotsMap. Rings, necks, trinkets,
-- bags and Classic's relics and thrown weapons are not here, so they are not collectibles at all.
local TRANSMOG_SLOT = {
  INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_BODY = true, INVTYPE_CHEST = true,
  INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true,
  INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_CLOAK = true, INVTYPE_WEAPON = true,
  INVTYPE_SHIELD = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
  INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_WEAPONOFFHAND = true,
  INVTYPE_HOLDABLE = true, INVTYPE_TABARD = true,
}
-- Miscellaneous armor has no appearance except in these slots (CanIMogIt's miscArmorExceptions).
local MISC_ARMOR_SLOT = { INVTYPE_HOLDABLE = true, INVTYPE_BODY = true, INVTYPE_TABARD = true }

local client -- nil: the real globals
local cache = {}
local listeners = {}

-- ok, ... -- ok is false when the function is absent or raised; the values are the call's own.
local function call(namespace, name, ...)
  local env = client or _G
  local owner = namespace and env[namespace] or env
  local fn = type(owner) == "table" and owner[name] or nil
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

-- ok, the nth value: for the reads whose answer is far down a long return list.
local function nth(n, ok, ...)
  if not ok then return false end
  return true, (select(n, ...))
end

-- A Forever-only "does this account have any" (C_TransmogCollection.HasAnyAppearance,
-- C_ToyBoxInfo.HasAnyToy): its own Collections journal hides a tab on false. Asked only before
-- a "missing", as the proof that the collection is filled at all. A client without the function
-- has nothing to say here (retail lacks both), so it does not hold anything back; one that has
-- it and raises, or says false, does.
local function emptyCollection(namespace, name)
  local env = client or _G
  local owner = env[namespace]
  local fn = type(owner) == "table" and owner[name] or nil
  if type(fn) ~= "function" then return false end
  local ok, any = pcall(fn)
  return not ok or any ~= true
end

local function petState(speciesID)
  local ok, owned, maxAllowed = call("C_PetJournal", "GetNumCollectedInfo", speciesID)
  if not ok or type(owned) ~= "number" then return UNKNOWN end
  if owned > 0 then return COLLECTED end
  -- A species the journal knows has a cap above zero (3, or 1 for a unique pet). A zero cap is
  -- a species it does not know, which is no proof of anything.
  if type(maxAllowed) == "number" and maxAllowed > 0 then return MISSING end
  return UNKNOWN
end

local function mountState(mountID)
  local ok, isCollected = nth(11, call("C_MountJournal", "GetMountInfoByID", mountID))
  if not ok then return UNKNOWN end
  if isCollected == true then return COLLECTED end
  if isCollected == false then return MISSING end
  return UNKNOWN -- MayReturnNothing
end

local function toyState(itemID)
  local ok, has = call(nil, "PlayerHasToy", itemID)
  if not ok then return UNKNOWN end
  if has == true then return COLLECTED end
  if has ~= false or emptyCollection("C_ToyBoxInfo", "HasAnyToy") then return UNKNOWN end
  return MISSING
end

-- "Already known" is the client's own ITEM_SPELL_KNOWN, localised, on the recipe's tooltip, and
-- only for the character that is logged in. A tooltip asked for before the item is in comes back
-- empty or as the one RETRIEVING_ITEM_INFO line, and neither says "not known".
local function recipeState(itemID)
  local env = client or _G
  local known, retrieving = env.ITEM_SPELL_KNOWN, env.RETRIEVING_ITEM_INFO
  if type(known) ~= "string" or known == "" or type(retrieving) ~= "string" then return UNKNOWN end
  local ok, data = call("C_TooltipInfo", "GetItemByID", itemID)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines == 0 then
    return UNKNOWN
  end
  for _, line in ipairs(data.lines) do
    local text = type(line) == "table" and line.leftText or nil
    if text == known then return COLLECTED end
    if text == retrieving then return UNKNOWN end
  end
  return MISSING
end

-- The class and subclass of the item behind another appearance source: GetSourceInfo's itemID,
-- then GetItemInfoInstant, which never waits on the server.
local function sourceClass(sourceID)
  local ok, info = call("C_TransmogCollection", "GetSourceInfo", sourceID)
  local itemID = ok and type(info) == "table" and info.itemID or nil
  if type(itemID) ~= "number" then return nil end
  local okI, _, _, _, _, _, classID, subclassID = call("C_Item", "GetItemInfoInstant", itemID)
  if not okI or type(classID) ~= "number" then return nil end
  return classID, subclassID
end

local function appearanceState(itemID, equipLoc, classID, subclassID)
  local TC = "C_TransmogCollection"
  local ok, appearanceID, sourceID = call(TC, "GetItemInfo", itemID)
  if not ok or type(appearanceID) ~= "number" or type(sourceID) ~= "number" then return UNKNOWN end
  -- A tabard asks by item, as CanIMogIt does: its source read is not the one to trust.
  local okOwn, own
  if equipLoc == "INVTYPE_TABARD" then
    okOwn, own = call(TC, "PlayerHasTransmog", itemID)
  else
    okOwn, own = call(TC, "PlayerHasTransmogItemModifiedAppearance", sourceID)
  end
  if not okOwn then return UNKNOWN end
  if own == true then return COLLECTED end

  local okAll, sources = call(TC, "GetAllAppearanceSources", appearanceID)
  if not okAll or type(sources) ~= "table" then return UNKNOWN end
  local unsure = false
  for _, other in ipairs(sources) do
    if other ~= sourceID then
      local okHas, has = call(TC, "PlayerHasTransmogItemModifiedAppearance", other)
      if not okHas then
        unsure = true
      elseif has == true then
        local otherClass, otherSub = sourceClass(other)
        if otherClass == nil then
          unsure = true -- a known source of a type we cannot read: maybe it counts
        elseif (otherClass == CLASS_ARMOR and otherSub == ARMOR_COSMETIC)
            or (otherClass == classID and otherSub == subclassID) then
          return ELSEWHERE
        end
      end
    end
  end
  if unsure then return UNKNOWN end

  if emptyCollection(TC, "HasAnyAppearance") then return UNKNOWN end
  -- hasItemData false is the client still loading the source; canCollect false is a character
  -- that cannot learn it (CanIMogIt's CharacterCanLearnTransmog). That one still counts as a
  -- gap in the ACCOUNT's collection when the account can collect it on another character.
  local okP, hasData, canCollect = call(TC, "PlayerCanCollectSource", sourceID)
  if not okP or hasData ~= true then return UNKNOWN end
  if canCollect == true then return MISSING end
  local okA, accountData, accountCan = call(TC, "AccountCanCollectSource", sourceID)
  if okA and accountData == true and accountCan == true then return MISSING end
  return UNKNOWN
end

local function isAppearanceItem(classID, subclassID, equipLoc)
  if classID ~= CLASS_WEAPON and classID ~= CLASS_ARMOR then return false end
  if not TRANSMOG_SLOT[equipLoc] then return false end
  if classID == CLASS_ARMOR and subclassID == ARMOR_MISC then return MISC_ARMOR_SLOT[equipLoc] == true end
  return true
end

-- state, kind. The journals are asked first: a toy can be any class (Worn Troll Dice is a
-- Consumable), and only GetToyInfo, GetMountFromItem and GetPetInfoByItemID say what an item
-- teaches. A classifier that could not answer leaves the item's "not a collectible" unproven,
-- so that ends as "unknown" rather than nil.
local function decide(itemID, speciesID)
  if speciesID then return petState(speciesID), "pet" end

  local okI, _, _, _, equipLoc, _, classID, subclassID = call("C_Item", "GetItemInfoInstant", itemID)
  local unsure = not okI or type(classID) ~= "number"

  local okM, mountID = call("C_MountJournal", "GetMountFromItem", itemID)
  if okM and type(mountID) == "number" and mountID > 0 then return mountState(mountID), "mount" end
  unsure = unsure or not okM

  local okT, toyItemID = call("C_ToyBox", "GetToyInfo", itemID)
  if okT and type(toyItemID) == "number" and toyItemID > 0 then return toyState(itemID), "toy" end
  unsure = unsure or not okT

  -- The 13th value is the species (DressUpFrames.lua reads it the same way).
  local okP, petSpecies = nth(13, call("C_PetJournal", "GetPetInfoByItemID", itemID))
  if okP and type(petSpecies) == "number" and petSpecies > 0 then return petState(petSpecies), "pet" end
  unsure = unsure or not okP

  if type(classID) ~= "number" then return UNKNOWN, nil end
  if classID == CLASS_RECIPE then return recipeState(itemID), "recipe" end
  -- Named as a collectible by its class, but no journal said which one: a cage without its
  -- species, or a mount or pet item the journal has not loaded.
  if classID == CLASS_BATTLEPET then return UNKNOWN, "pet" end
  if classID == CLASS_MISC and subclassID == MISC_MOUNT then return UNKNOWN, "mount" end
  if classID == CLASS_MISC and subclassID == MISC_COMPANION_PET then return UNKNOWN, "pet" end
  if isAppearanceItem(classID, subclassID, equipLoc) then
    return appearanceState(itemID, equipLoc, classID, subclassID), "appearance"
  end
  if unsure then return UNKNOWN, nil end
  return nil, nil
end

--- state, kind for one item (see the header). `petSpeciesID` is the auction key's
--- battlePetSpeciesID: a caged pet is item 82800 whatever is inside, so only the species says.
--- Answers are remembered until the next Reset; "unknown" is not, since the data it waited on
--- may be in by the next call.
function GC.Collection.State(itemID, petSpeciesID)
  if type(itemID) ~= "number" then return UNKNOWN, nil end
  local speciesID = type(petSpeciesID) == "number" and petSpeciesID > 0 and petSpeciesID or nil
  local key = speciesID and (itemID .. ":" .. speciesID) or itemID
  local hit = cache[key]
  if hit then return hit.state, hit.kind end
  local state, kind = decide(itemID, speciesID)
  if state ~= UNKNOWN then cache[key] = { state = state, kind = kind } end
  return state, kind
end

--- Forgets every answer, then tells each OnChange listener. A listener repaints; it must not
--- call Reset itself.
function GC.Collection.Reset()
  cache = {}
  for i = 1, #listeners do listeners[i]() end
end

function GC.Collection.OnChange(fn)
  if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

--- The table the client is read from: an API-shaped fake in a spec, nil for the real globals.
--- Forgets every answer the previous client gave.
function GC.Collection.SetClient(fake)
  client = fake
  cache = {}
end

-- Whatever changes a collection resets every answer: one learned appearance can turn many
-- rows into "elsewhere", and a caged pet lowers a species' count. Every name is in both branches'
-- API docs (wowsrc.py api). NEW_RECIPE_LEARNED is the profession window's own event;
-- LEARNED_SPELL_IN_SKILL_LINE and COMPANION_* are there in case Forever's Classic-style recipes,
-- mounts or pets arrive as a learned spell instead, which no probe has checked yet. They are rare,
-- so a reset each time costs nothing. Each in its own pcall, like Core/Init.lua's optional
-- events: a name one client does not know must not take the rest with it.
local EVENTS = {
  "TRANSMOG_COLLECTION_UPDATED", "TRANSMOG_COLLECTION_SOURCE_ADDED", "TRANSMOG_COLLECTION_SOURCE_REMOVED",
  "NEW_PET_ADDED", "PET_JOURNAL_LIST_UPDATE", "PET_JOURNAL_PET_DELETED",
  "NEW_TOY_ADDED", "TOYS_UPDATED",
  "NEW_MOUNT_ADDED", "COMPANION_LEARNED", "COMPANION_UNLEARNED",
  "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE",
}

if type(CreateFrame) == "function" then
  local frame = CreateFrame("Frame")
  for _, event in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
  frame:SetScript("OnEvent", function() GC.Collection.Reset() end)
end
