local _, GC = ...

-- Names for items the site cannot name itself. Blizzard's item endpoint answers 404 for a
-- class of items that exist only through hotfixes (Tuskarr Jerky is one), so goldcap.gg
-- shows them as "Item #201421" and its search cannot find them. The client always knows
-- them. The import string lists the ids the site is missing (its N section), this module
-- asks the client and writes the answers to GoldCapDB.itemNames, and the Companion uploads
-- that table. Nothing here is shown to the player.
GC.ItemNames = {
  CAP = 300,
  REFRESH_AFTER = 7 * 24 * 60 * 60,
  BATCH = 25,
  BATCH_DELAY = 0.5,
}

-- itemID -> true while a client data request is outstanding for a still-wanted id. Set only
-- when a lookup answers nil (the client has not cached it yet); a lookup that answered but
-- failed to persist (e.g. the 300-entry cap) is not "outstanding" and must not sit here, or a
-- later GET_ITEM_INFO_RECEIVED for that id would re-admit it past Prune. Cleared by a
-- successful lookup, by OnItemInfoReceived once it has answered, and by Prune when the id
-- drops out of the wanted list -- so this table never outlives the current wanted list either.
local awaiting = {}

local function isPositiveInteger(v)
  return type(v) == "number" and v == math.floor(v) and v > 0
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function GC.ItemNames.Record(database, itemID, info, locale, now)
  if type(database) ~= "table" or type(info) ~= "table" then return nil end
  if not isPositiveInteger(itemID) or type(info.name) ~= "string" or info.name == "" then return nil end
  if database.itemNames == nil then database.itemNames = {} end
  if type(database.itemNames) ~= "table" then return nil end
  if database.itemNames[itemID] == nil and count(database.itemNames) >= GC.ItemNames.CAP then
    return nil
  end
  database.itemNames[itemID] = {
    n = info.name, l = locale, q = info.quality, il = info.itemLevel, ml = info.minLevel,
    ct = info.className, sct = info.subClassName, st = info.stackCount, ic = info.iconFileID,
    sp = info.sellPrice, c = info.classID, sc = info.subclassID, b = info.bindType,
    e = info.expansionID, at = now,
  }
  return true
end

-- Wanted ids with no record, or a record old enough to be worth re-sending.
function GC.ItemNames.Pending(database, wanted, now)
  local out = {}
  local names = type(database) == "table" and type(database.itemNames) == "table" and database.itemNames or {}
  for _, id in ipairs(wanted or {}) do
    local row = names[id]
    if type(row) ~= "table" or type(row.at) ~= "number" or now - row.at > GC.ItemNames.REFRESH_AFTER then
      out[#out + 1] = id
    end
  end
  return out
end

-- Forget ids the site stopped asking for, so the save file only ever holds the current list.
-- Also drops `awaiting` entries for ids no longer wanted -- otherwise a GET_ITEM_INFO_RECEIVED
-- that arrives late for an id an earlier wanted list asked about could re-admit it after this
-- one dropped it.
function GC.ItemNames.Prune(database, wanted)
  local keep = {}
  for _, id in ipairs(wanted or {}) do keep[id] = true end
  for id in pairs(awaiting) do
    if not keep[id] then awaiting[id] = nil end
  end
  if type(database) ~= "table" or type(database.itemNames) ~= "table" then return end
  for id in pairs(database.itemNames) do
    if not keep[id] then database.itemNames[id] = nil end
  end
end

-- One pass over the wanted list. `lookup(id)` returns an info table or nil (nil means the
-- client has not cached the item yet -- GET_ITEM_INFO_RECEIVED follows, see below).
-- Returns how many were recorded and the ids still unresolved.
function GC.ItemNames.Sync(database, wanted, lookup, locale, now)
  GC.ItemNames.Prune(database, wanted)
  local recorded, unresolved = 0, {}
  for _, id in ipairs(GC.ItemNames.Pending(database, wanted, now)) do
    local info = lookup(id)
    if info == nil then
      -- Not recorded yet, and the client hasn't answered -- GET_ITEM_INFO_RECEIVED follows.
      unresolved[#unresolved + 1] = id
      awaiting[id] = true
    else
      -- The client answered, one way or another; nothing is outstanding for this id anymore.
      awaiting[id] = nil
      if GC.ItemNames.Record(database, id, info, locale, now) then
        recorded = recorded + 1
      else
        unresolved[#unresolved + 1] = id
      end
    end
  end
  return recorded, unresolved
end

function GC.ItemNames.OnItemInfoReceived(database, itemID, success, lookup, locale, now)
  if not awaiting[itemID] then return nil end
  awaiting[itemID] = nil
  if not success then return nil end
  local info = lookup(itemID)
  if not info then return nil end
  return GC.ItemNames.Record(database, itemID, info, locale, now)
end

-- ---- engine adapter: everything below touches the client and is not covered by specs ----

function GC.ItemNames.EngineLookup(itemID)
  if not C_Item or not C_Item.GetItemInfo then return nil end
  local name, _, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, _, texture,
    sellPrice, classID, subclassID, bindType, expansionID = C_Item.GetItemInfo(itemID)
  if not name then return nil end
  return { name = name, quality = quality, itemLevel = itemLevel, minLevel = minLevel,
    className = itemType, subClassName = itemSubType, stackCount = stackCount,
    iconFileID = texture, sellPrice = sellPrice, classID = classID, subclassID = subclassID,
    bindType = bindType, expansionID = expansionID }
end

local inWorld = false

-- Walks the wanted list in small batches so a 300-id list never turns into one burst of
-- item queries on login. Safe to call again at any time: Pending() makes it idempotent.
function GC.ItemNames.Start(database, imported)
  if not inWorld or type(database) ~= "table" or type(imported) ~= "table" then return end
  local wanted = imported.namesWanted
  if type(wanted) ~= "table" or #wanted == 0 then
    GC.ItemNames.Prune(database, {})
    return
  end
  local locale = GetLocale and GetLocale() or "enUS"
  local index = 1
  local function step()
    local slice = {}
    for i = index, math.min(index + GC.ItemNames.BATCH - 1, #wanted) do slice[#slice + 1] = wanted[i] end
    index = index + GC.ItemNames.BATCH
    -- Prune only against the FULL list; a slice would delete everything outside it.
    local pending = GC.ItemNames.Pending(database, slice, time())
    for _, id in ipairs(pending) do
      local info = GC.ItemNames.EngineLookup(id)
      if info == nil then
        awaiting[id] = true
      else
        awaiting[id] = nil
        GC.ItemNames.Record(database, id, info, locale, time())
      end
    end
    if index <= #wanted and C_Timer then C_Timer.After(GC.ItemNames.BATCH_DELAY, step) end
  end
  GC.ItemNames.Prune(database, wanted)
  step()
end

function GC.ItemNames.OnEnteringWorld(database, imported)
  inWorld = true
  GC.ItemNames.Start(database, imported)
end

function GC.ItemNames.OnEngineItemInfo(database, itemID, success)
  local locale = GetLocale and GetLocale() or "enUS"
  return GC.ItemNames.OnItemInfoReceived(database, itemID, success, GC.ItemNames.EngineLookup, locale, time())
end
