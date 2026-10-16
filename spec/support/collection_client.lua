-- API-shaped double of the client reads Core/Collection.lua makes: the C_Item, C_TransmogCollection,
-- C_PetJournal, C_ToyBox, C_ToyBoxInfo, C_MountJournal and C_TooltipInfo functions it calls,
-- PlayerHasToy, and the two client strings it compares tooltip lines with. Each function has the
-- real name and arguments and returns the real values in the real order (wowsrc.py api, live
-- 12.1.0 and forever 1.60.1; the undocumented ones as Blizzard's own callers read them), and the
-- client carries nothing else. What a spec wants to know about the calls lives in a side table,
-- never on the client.
--
-- A world describes what the client knows; the double reads it at call time, so a spec can change
-- it between two calls (an item's tooltip loading, a pet learned):
--   items        [itemID] = { classID, subclassID, equipLoc, appearanceID, sourceID, mountID,
--                toy = true, petSpecies, tooltip = { leftText, ... } }
--   sources      [sourceID] = itemID      GetSourceInfo's item
--   appearances  [appearanceID] = { sourceID, ... }
--   mounts       [mountID] = isCollected
--   species      [speciesID] = { owned, max }
--   owned        { sources = {}, tabards = {}, toys = {} }  sets of what the account has
--   collect      [sourceID] = { player = { hasItemData, canCollect }, account = { ... } }
--                (both default to true, true)
--   anyAppearance, anyToy   the Forever-only HasAnyAppearance / HasAnyToy answers; nil leaves the
--                function out, as on retail
--   absent       { "C_ToyBox.GetToyInfo" = true, "C_Item" = true, "ITEM_SPELL_KNOWN" = true }
--   raising      { "C_TransmogCollection.GetItemInfo" = true }
local C = {}

C.ITEM_SPELL_KNOWN = "Already known"
C.RETRIEVING_ITEM_INFO = "Retrieving item information"

local function set(t) return t or {} end

function C.new(world)
  local calls = {}
  local client = {}

  local function add(namespace, name, fn)
    local full = namespace and (namespace .. "." .. name) or name
    if world.absent and (world.absent[full] or (namespace and world.absent[namespace])) then return end
    local owner = client
    if namespace then
      client[namespace] = client[namespace] or {}
      owner = client[namespace]
    end
    owner[name] = function(...)
      calls[full] = (calls[full] or 0) + 1
      calls.total = (calls.total or 0) + 1
      if world.raising and world.raising[full] then error(full .. " raised") end
      return fn(...)
    end
  end

  local function item(itemID) return (world.items or {})[itemID] end
  local function owned(kind) return set(set(world.owned)[kind]) end

  add("C_Item", "GetItemInfoInstant", function(itemID)
    local it = item(itemID)
    if not it or not it.classID then return end
    return itemID, "itemType", "itemSubType", it.equipLoc or "", 134400, it.classID, it.subclassID or 0
  end)

  add("C_MountJournal", "GetMountFromItem", function(itemID)
    local it = item(itemID)
    return it and it.mountID or nil
  end)
  add("C_MountJournal", "GetMountInfoByID", function(mountID)
    local isCollected = set(world.mounts)[mountID]
    if isCollected == nil then return end
    -- name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction,
    -- shouldHideOnChar, isCollected, mountID, isSteadyFlight
    return "Mount", 1000 + mountID, 132261, false, isCollected, 1, false, false, nil, false, isCollected, mountID, false
  end)

  add("C_ToyBox", "GetToyInfo", function(itemID)
    local it = item(itemID)
    if not (it and it.toy) then return end
    -- itemID, toyName, icon, isFavorite, hasFanfare, itemQuality
    return itemID, "Toy", 134400, false, false, 3
  end)
  add(nil, "PlayerHasToy", function(itemID) return owned("toys")[itemID] == true end)
  if world.anyToy ~= nil then
    add("C_ToyBoxInfo", "HasAnyToy", function() return world.anyToy end)
  end

  add("C_PetJournal", "GetPetInfoByItemID", function(itemID)
    local it = item(itemID)
    if not (it and it.petSpecies) then return end
    -- name, icon, petType, creatureID, sourceText, description, isWild, canBattle, isTradeable,
    -- isUnique, obtainable, displayID, speciesID (DressUpFrames.lua)
    return "Pet", 132599, 1, 7380, "Vendor", "", false, true, true, false, true, 5556, it.petSpecies
  end)
  add("C_PetJournal", "GetNumCollectedInfo", function(speciesID)
    local s = set(world.species)[speciesID]
    if not s then return 0, 0 end
    return s.owned or 0, s.max or 3
  end)

  local TC = "C_TransmogCollection"
  add(TC, "GetItemInfo", function(itemID)
    local it = item(itemID)
    if not (it and it.appearanceID and it.sourceID) then return end
    return it.appearanceID, it.sourceID
  end)
  add(TC, "PlayerHasTransmog", function(itemID) return owned("tabards")[itemID] == true end)
  add(TC, "PlayerHasTransmogItemModifiedAppearance", function(sourceID)
    return owned("sources")[sourceID] == true
  end)
  add(TC, "GetAllAppearanceSources", function(appearanceID)
    local list = {}
    for i, sourceID in ipairs(set(set(world.appearances)[appearanceID])) do list[i] = sourceID end
    return list
  end)
  add(TC, "GetSourceInfo", function(sourceID)
    local itemID = set(world.sources)[sourceID]
    if not itemID then return end
    return { sourceID = sourceID, itemID = itemID, visualID = 1, itemModID = 0,
      isCollected = owned("sources")[sourceID] == true }
  end)
  local function canCollect(who)
    return function(sourceID)
      local c = set(set(world.collect)[sourceID])[who]
      if not c then return true, true end
      return c[1], c[2]
    end
  end
  add(TC, "PlayerCanCollectSource", canCollect("player"))
  add(TC, "AccountCanCollectSource", canCollect("account"))
  if world.anyAppearance ~= nil then
    add(TC, "HasAnyAppearance", function() return world.anyAppearance end)
  end

  add("C_TooltipInfo", "GetItemByID", function(itemID)
    local it = item(itemID)
    if not (it and it.tooltip) then return end
    local lines = {}
    for i, text in ipairs(it.tooltip) do lines[i] = { type = 0, leftText = text } end
    return { type = 0, id = itemID, lines = lines }
  end)

  for _, name in ipairs({ "ITEM_SPELL_KNOWN", "RETRIEVING_ITEM_INFO" }) do
    if not (world.absent and world.absent[name]) then client[name] = C[name] end
  end

  return client, calls
end

--- Every function and string the double can stand in for, as "Namespace.Name" (absent/raising keys).
C.NAMES = {
  "C_Item.GetItemInfoInstant", "C_MountJournal.GetMountFromItem", "C_MountJournal.GetMountInfoByID",
  "C_ToyBox.GetToyInfo", "PlayerHasToy", "C_ToyBoxInfo.HasAnyToy",
  "C_PetJournal.GetPetInfoByItemID", "C_PetJournal.GetNumCollectedInfo",
  "C_TransmogCollection.GetItemInfo", "C_TransmogCollection.PlayerHasTransmog",
  "C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance",
  "C_TransmogCollection.GetAllAppearanceSources", "C_TransmogCollection.GetSourceInfo",
  "C_TransmogCollection.PlayerCanCollectSource", "C_TransmogCollection.AccountCanCollectSource",
  "C_TransmogCollection.HasAnyAppearance", "C_TooltipInfo.GetItemByID",
}
C.STRINGS = { "ITEM_SPELL_KNOWN", "RETRIEVING_ITEM_INFO" }

return C
