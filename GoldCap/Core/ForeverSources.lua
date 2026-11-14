local _, GC = ...

-- WoW: Forever: what each profession trainer teaches and what each merchant sells, as the player
-- saw it at that npc, for goldcap.gg's leveling routes to say where each recipe is learned. The
-- trainer's and the merchant's own windows are what GoldCap reads for that.
--
-- Pure: the caller (Services/SourcesClient_Camelot.lua) reads the window and hands over the npc
-- and its rows.
--
-- Saved shape (GoldCapDB.foreverSources, made by the first visit with something to keep, only on
-- Forever):
--   { v = 1,
--     trainers = { [npcID] = { n = <name>, m = <uiMapID>, z = <zone>, s = <subzone>, f = <faction>,
--                              at = <epoch seconds>,
--                              sv = { [spellID] = { l = <skill line>, r = <skill required>,
--                                                   c = <copper>, lv = <character level>,
--                                                   i = <itemID it makes> | nil } } } },
--     vendors  = { [npcID] = { n, m, z, s, f, at,
--                              it = { [itemID] = { p = <copper for one stack>, k = <stack>,
--                                                  a = <stock, -1 unlimited>, c = <item class>,
--                                                  sc = <subclass>, x = true | nil } } } } }
-- `x` marks an item that costs a currency or items (the merchant's extended cost).
--
-- - A trainer's services merge: a visit adds or updates what it shows, field by field, and deletes
--   nothing. Blizzard's trainer window hides what the character has already learned, so each
--   character sees another part of the list. A row whose item the client had not loaded yet has no
--   link: it leaves `i` as it was, and a later visit with the link fills it.
-- - A merchant's items merge the same way: a visit adds or updates each item it shows, field by
--   field, and deletes nothing. Blizzard's merchant window resets its item filter to the player's
--   class at each show (ResetSetMerchantFilter), so one character's list can be part of what the
--   merchant sells. `x` is set by every visit that shows the item. A read with no rows changes
--   nothing.
-- - Only a creature is an npc here: a GUID of any other kind (a player, a vehicle) keeps nothing.
-- - At most C.MAX_TRAINERS trainers and C.MAX_VENDORS merchants: past that, the one seen longest
--   ago goes, never the one just written.
-- - Names, zones and skill lines are in the client's language; the ids are what to key on.
GC.ForeverSources = GC.ForeverSources or {}
local S = GC.ForeverSources

S.VERSION = 1

local C = {
  MAX_TRAINERS = 400,
  MAX_VENDORS = 600,
}
S.C = C

local function positiveInteger(n)
  return type(n) == "number" and n >= 1 and n < 2 ^ 53 and n == math.floor(n)
end

-- A whole number as the client gave it (0 and -1 stay), else nil.
local function int(n)
  if type(n) ~= "number" or n ~= n or n <= -2 ^ 53 or n >= 2 ^ 53 or n ~= math.floor(n) then return nil end
  return n
end

local function text(s)
  return type(s) == "string" and s ~= "" and s or nil
end

local function itemOf(link)
  local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
  return positiveInteger(id) and id or nil
end

--- The npc id of a creature's GUID ("Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>"),
--- nil for anything else. Core/ForeverLoot.lua's Source also takes a vehicle; a trainer or a
--- merchant is a creature.
function S.NpcId(guid)
  if type(guid) ~= "string" then return nil end
  local id = tonumber(guid:match("^Creature%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-"))
  return positiveInteger(id) and id or nil
end

--- The store under `root` (GoldCapDB), made when `create` and missing. nil for a store a newer
--- GoldCap wrote (its `v` above VERSION) or of another shape: that one is never read or written.
function S.Store(root, create)
  if type(root) ~= "table" then return nil end
  local s = root.foreverSources
  if s == nil and create then
    s = { v = S.VERSION, trainers = {}, vendors = {} }
    root.foreverSources = s
  end
  if type(s) ~= "table" or s.v ~= S.VERSION or type(s.trainers) ~= "table" or type(s.vendors) ~= "table" then
    return nil
  end
  return s
end

-- What a visit says of the npc. A field it could not read keeps what an earlier visit said.
local function stamp(entry, npc, now)
  local seen = { n = text(npc.name), m = positiveInteger(npc.map) and npc.map or nil, z = text(npc.zone),
    s = text(npc.subzone), f = text(npc.faction) }
  for k, v in pairs(seen) do entry[k] = v end
  entry.at = now
end

local function older(a, b)
  if a.at ~= b.at then return a.at < b.at end
  if type(a.id) == "number" and type(b.id) == "number" then return a.id < b.id end
  return tostring(a.id) < tostring(b.id)
end

-- Drops the entries seen longest ago (the lower id first on a tie) until `cap` are left, never `keep`.
local function trim(list, cap, keep)
  local n = 0
  for _ in pairs(list) do n = n + 1 end
  while n > cap do
    local oldest
    for id, e in pairs(list) do
      if id ~= keep then
        local at = type(e) == "table" and type(e.at) == "number" and e.at or -math.huge
        local this = { id = id, at = at }
        if not oldest or older(this, oldest) then oldest = this end
      end
    end
    if not oldest then return end
    list[oldest.id] = nil
    n = n - 1
  end
end

--- Keeps what one profession trainer showed: `npc` = { guid, name, map, zone, subzone, faction },
--- `services` = a list of { spellID, skillLine, requiredSkill, cost, level, link }. A row with no
--- spell id is skipped. Answers how many services it wrote.
function S.RecordTrainer(root, npc, services, now)
  if type(npc) ~= "table" or type(services) ~= "table" or type(now) ~= "number" then return 0 end
  local id = S.NpcId(npc.guid)
  if not id then return 0 end
  local rows, n = {}, 0
  for _, row in ipairs(services) do
    local spell = type(row) == "table" and row.spellID or nil
    if positiveInteger(spell) then
      if rows[spell] == nil then n = n + 1 end
      rows[spell] = { l = text(row.skillLine), r = int(row.requiredSkill), c = int(row.cost),
        lv = int(row.level), i = itemOf(row.link) }
    end
  end
  if n == 0 then return 0 end
  local s = S.Store(root, true)
  if not s then return 0 end
  local entry = s.trainers[id]
  if type(entry) ~= "table" or type(entry.sv) ~= "table" then
    entry = { sv = {} }
    s.trainers[id] = entry
  end
  stamp(entry, npc, now)
  for spell, row in pairs(rows) do
    local kept = entry.sv[spell]
    if type(kept) == "table" then
      -- A field this visit could not read (nil) is not in `row`, so the kept one stays.
      for k, v in pairs(row) do kept[k] = v end
    else
      entry.sv[spell] = row
    end
  end
  trim(s.trainers, C.MAX_TRAINERS, id)
  return n
end

--- Keeps what one merchant sells, beside what earlier visits saw: `npc` as for RecordTrainer,
--- `items` = a list of { itemID, price, stack, available, classID, subclassID, extended }. An item
--- listed twice keeps its row for gold over one for a currency, else its first row. Answers how
--- many items it wrote.
function S.RecordVendor(root, npc, items, now)
  if type(npc) ~= "table" or type(items) ~= "table" or type(now) ~= "number" then return 0 end
  local id = S.NpcId(npc.guid)
  if not id then return 0 end
  local list, n = {}, 0
  for _, row in ipairs(items) do
    local item = type(row) == "table" and row.itemID or nil
    if positiveInteger(item) then
      local kept = list[item]
      if kept == nil then n = n + 1 end
      if kept == nil or (kept.x and row.extended ~= true) then
        list[item] = { p = int(row.price), k = int(row.stack), a = int(row.available), c = int(row.classID),
          sc = int(row.subclassID), x = row.extended == true or nil }
      end
    end
  end
  if n == 0 then return 0 end
  local s = S.Store(root, true)
  if not s then return 0 end
  local entry = s.vendors[id]
  if type(entry) ~= "table" then
    entry = {}
    s.vendors[id] = entry
  end
  stamp(entry, npc, now)
  if type(entry.it) ~= "table" then entry.it = {} end
  for item, row in pairs(list) do
    local kept = entry.it[item]
    if type(kept) == "table" then
      -- A field this visit could not read (nil) is not in `row`, so the kept one stays. Whether the
      -- item costs a currency is read on every row, so `x` is this visit's.
      for k, v in pairs(row) do kept[k] = v end
      kept.x = row.x
    else
      entry.it[item] = row
    end
  end
  trim(s.vendors, C.MAX_VENDORS, id)
  return n
end
