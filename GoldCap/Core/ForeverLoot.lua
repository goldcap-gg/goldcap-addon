local _, GC = ...

-- WoW: Forever's loot recorder (plan 3e, growth spec D8): what dropped from what the player
-- looted, counted per source and zone -- a drop-rate dataset nobody else has, because Blizzard
-- ships no loot tables for Forever (research F9). The companion uploads it; that contract is plan
-- 2a/3d's. Only counts: no character or realm name, no player or spawn GUID, no per-kill time.
-- Off with /gc loot off (GoldCapDB.forever.lootOff). Never on, and never written, on retail.
--
-- Saved shape "loot v1" -- GoldCapDB.foreverLoot:
--   { v = 1, id = "<16 hex, random per install>", gen = <n>, region = <GetCurrentRegion id>,
--     build = "<client build>", since = <epoch>, n = <row count>, rows = { ["<key>"] = "<value>" },
--     prev = { gen, since, to, n, rows } | nil }            -- the generation before, kept one rotation
--   key   = "c:<npcID>:<uiMapID>"            creature looted by hand
--         | "s:<npcID>:<uiMapID>:<spellID>"  creature looted through the player's own spell
--         | "o:<objectID>:<uiMapID>"         game object (herb, vein, chest)
--   value = "<opens>,<copper>,<minLevel>,<maxLevel>,<skipped>;<itemID>:<drops>:<units> ..."
-- A snapshot, not a log: an upload of the same (id, gen) replaces the one before, so sending it
-- again is harmless. Rows reach MAX_KEYS, or the build or region changes: the generation rotates.
-- Counts are per looted source ("opens"): a creature with nothing on it opens no window.
GC.ForeverLoot = GC.ForeverLoot or {}

local C = {
  VERSION = 1,
  MAX_KEYS = 1000,   -- rows per generation (~110 KB of SavedVariables)
  MAX_ITEMS = 24,    -- distinct items per row
  SPELL_WINDOW = 0.5, -- seconds from the player's own spell to the loot window it opened
  SEEN = 200,        -- sources remembered, so one corpse counts once
}
GC.ForeverLoot.C = C

-- "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>": the kind and the id. Vehicles are
-- creatures; everything else (a player, an item being opened) is not a drop source.
function GC.ForeverLoot.Source(guid)
  if type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
  id = tonumber(id)
  if not id or id <= 0 then return nil end
  if kind == "Creature" or kind == "Vehicle" then return "c", id end
  if kind == "GameObject" then return "o", id end
  return nil
end

function GC.ForeverLoot.Key(guid, mapID, spellID)
  local kind, id = GC.ForeverLoot.Source(guid)
  if not kind then return nil end
  mapID = tonumber(mapID) or 0
  if kind == "c" and spellID then return ("s:%d:%d:%d"):format(id, mapID, spellID) end
  return ("%s:%d:%d"):format(kind, id, mapID)
end

function GC.ForeverLoot.DecodeRow(s)
  local r = { opens = 0, coin = 0, skipped = 0, count = 0, items = {} }
  if type(s) ~= "string" then return r end
  local head, body = s:match("^([^;]*);?(.*)$")
  local o, c, lo, hi, sk = (head or ""):match("^(%d+),(%d+),(%d*),(%d*),(%d+)$")
  if not o then return r end
  r.opens, r.coin, r.minLevel, r.maxLevel, r.skipped = tonumber(o), tonumber(c), tonumber(lo), tonumber(hi), tonumber(sk)
  for id, drops, units in (body or ""):gmatch("(%d+):(%d+):(%d+)") do
    r.items[tonumber(id)] = { tonumber(drops), tonumber(units) }
    r.count = r.count + 1
  end
  return r
end

function GC.ForeverLoot.EncodeRow(r)
  local ids = {}
  for id in pairs(r.items) do ids[#ids + 1] = id end
  table.sort(ids)
  local parts = {}
  for i, id in ipairs(ids) do parts[i] = ("%d:%d:%d"):format(id, r.items[id][1], r.items[id][2]) end
  return ("%d,%d,%s,%s,%d;%s"):format(r.opens, r.coin, r.minLevel and tostring(r.minLevel) or "",
    r.maxLevel and tostring(r.maxLevel) or "", r.skipped, table.concat(parts, " "))
end

function GC.ForeverLoot.Rotate(store, now)
  store.prev = { gen = store.gen, since = store.since, to = now, n = store.n, rows = store.rows }
  store.gen = (store.gen or 0) + 1
  store.since, store.n, store.rows = now, 0, {}
end

-- A new client build or region starts a new generation: a patch may change what drops.
function GC.ForeverLoot.Ensure(store, ctx)
  local changed = (store.build ~= nil and store.build ~= ctx.build)
    or (store.region ~= nil and store.region ~= ctx.region)
  if changed and (store.n or 0) > 0 then GC.ForeverLoot.Rotate(store, ctx.now) end
  store.build, store.region = ctx.build, ctx.region
end

local function remember(seen, mark)
  if seen.set[mark] then return end
  seen.set[mark] = true
  seen.list[#seen.list + 1] = mark
  if #seen.list > C.SEEN then seen.set[table.remove(seen.list, 1)] = nil end
end

-- One loot window into the store. A source counts once per kind of opening (its GUID plus the
-- spell that opened it): LOOT_READY and LOOT_OPENED of one window, or a half-looted corpse opened
-- again, add nothing; skinning a corpse after looting it is its own "s" row.
function GC.ForeverLoot.Record(store, window, ctx, seen)
  if type(store) ~= "table" or type(window) ~= "table" or window.fishing == true then return 0 end
  store.rows = type(store.rows) == "table" and store.rows or {}
  store.n = tonumber(store.n) or 0
  local level = tonumber(ctx.level) or 0
  local bySource, order = {}, {}
  for _, slot in ipairs(window.slots or {}) do
    for _, src in ipairs(slot.sources or {}) do
      local guid, qty = src[1], tonumber(src[2])
      local key = GC.ForeverLoot.Key(guid, ctx.map, ctx.spell)
      local mark = key and (guid .. "|" .. tostring(ctx.spell or ""))
      if key and not (seen and seen.set[mark]) then
        local b = bySource[mark]
        if not b then
          b = { key = key, coin = 0, items = {} }
          bySource[mark] = b
          order[#order + 1] = mark
        end
        if qty and qty > 0 then
          if slot.kind == "money" then
            b.coin = b.coin + math.floor(qty)
          elseif slot.kind == "item" and not slot.quest and type(slot.itemID) == "number" then
            b.items[slot.itemID] = (b.items[slot.itemID] or 0) + math.floor(qty)
          end
        end
      end
    end
  end
  for _, mark in ipairs(order) do
    local b = bySource[mark]
    if store.rows[b.key] == nil then
      if store.n >= C.MAX_KEYS then GC.ForeverLoot.Rotate(store, ctx.now) end
      store.n = store.n + 1
    end
    local r = GC.ForeverLoot.DecodeRow(store.rows[b.key])
    r.opens, r.coin = r.opens + 1, r.coin + b.coin
    r.minLevel = math.min(r.minLevel or level, level)
    r.maxLevel = math.max(r.maxLevel or level, level)
    for itemID, units in pairs(b.items) do
      local cur = r.items[itemID]
      if cur then
        cur[1], cur[2] = cur[1] + 1, cur[2] + units
      elseif r.count < C.MAX_ITEMS then
        r.items[itemID], r.count = { 1, units }, r.count + 1
      else
        r.skipped = r.skipped + 1
      end
    end
    store.rows[b.key] = GC.ForeverLoot.EncodeRow(r)
    if seen then remember(seen, mark) end
  end
  return #order
end

-- The client. Every read guarded: a missing API reads as nothing to record, never an error.

-- Final review I3: UNIT_SPELLCAST_SUCCEEDED fires for every player spell -- Auto Shot, Shoot, a
-- wand, melee "next swing" abilities, instants, some procs -- not only the ones that open a
-- creature's loot. Only these open one: Skinning (every rank) and Pick Pocket.
local GATHER_SPELLS = {
  [921] = true,   -- Pick Pocket
  [8613] = true,  -- Skinning (Apprentice)
  [8617] = true,  -- Skinning (Journeyman)
  [8618] = true,  -- Skinning (Expert)
  [10768] = true, -- Skinning (Artisan)
}

local lastSpell
-- The spell this loot session (LOOT_READY through LOOT_CLOSED) is filed under, decided once at
-- its first event -- never re-derived from the clock on a later one. Without this, LOOT_READY
-- inside SPELL_WINDOW and LOOT_OPENED just outside it would disagree on the mark ("guid|8613"
-- against "guid|") and count the same corpse twice, once under each key.
local sessionOpen, sessionSpell
local seenMarks = { list = {}, set = {} }

local function prefs()
  return GC.ForeverScan and GC.ForeverScan.Prefs and GC.ForeverScan.Prefs() or nil
end

local function clock()
  local f = _G.GetTime
  if type(f) == "function" then
    local ok, t = pcall(f)
    if ok and type(t) == "number" then return t end
  end
  return time()
end

local function newId()
  -- Four 16-bit draws, not two 31-bit ones: Lua 5.1's math.random(m, n) computes n - m + 1
  -- in a C int, so math.random(0, 0x7fffffff) overflows there and yields negatives.
  return ("%04x%04x%04x%04x"):format(math.random(0, 0xffff), math.random(0, 0xffff),
    math.random(0, 0xffff), math.random(0, 0xffff))
end

-- GoldCapDB.foreverLoot, created on first use -- only in Forever, and not while the player has
-- turned the recorder off.
function GC.ForeverLoot.Store(now)
  local p = prefs()
  if not p or p.lootOff then return nil end
  local root = GC.ForeverScan.Root()
  local s = root.foreverLoot
  if type(s) ~= "table" or s.v ~= C.VERSION or type(s.rows) ~= "table" then
    s = { v = C.VERSION, id = newId(), gen = 1, since = now, n = 0, rows = {} }
    root.foreverLoot = s
  end
  return s
end

local function mapID()
  local map = _G.C_Map
  if type(map) ~= "table" or type(map.GetBestMapForUnit) ~= "function" then return 0 end
  local ok, id = pcall(map.GetBestMapForUnit, "player")
  return ok and tonumber(id) or 0
end

local function playerLevel()
  local ok, level = pcall(_G.UnitLevel, "player")
  return ok and tonumber(level) or 0
end

local SLOT_KIND = { [1] = "item", [2] = "money" } -- Enum.LootSlotType: Item 1, Money 2, Currency 3

local function readWindow()
  local w = { slots = {} }
  local okF, fishing = pcall(_G.IsFishingLoot)
  w.fishing = okF and fishing == true
  local okN, n = pcall(_G.GetNumLootItems)
  n = okN and tonumber(n) or 0
  for slot = 1, n do
    local okT, slotType = pcall(_G.GetLootSlotType, slot)
    local kind = okT and SLOT_KIND[slotType] or nil
    if kind then
      local entry = { kind = kind, sources = {} }
      if kind == "item" then
        local okL, link = pcall(_G.GetLootSlotLink, slot)
        entry.itemID = okL and type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
        local okI, _, _, _, _, _, _, isQuest = pcall(_G.GetLootSlotInfo, slot)
        entry.quest = okI and isQuest == true
      end
      -- guid, quantity, guid, quantity, ... -- for a coin slot the quantity is its copper (to be
      -- confirmed in the beta: /gc forever prints a recorded row).
      local src = { pcall(_G.GetLootSourceInfo, slot) }
      if src[1] then
        for i = 2, #src, 2 do entry.sources[#entry.sources + 1] = { src[i], src[i + 1] } end
      end
      w.slots[#w.slots + 1] = entry
    end
  end
  return w
end

-- UNIT_SPELLCAST_SUCCEEDED (player): skinning, pick pocket, herb gathering, opening a chest --
-- the loot window that follows within SPELL_WINDOW is that spell's. Kept, not consumed: the same
-- window's LOOT_READY and LOOT_OPENED must both see it.
function GC.ForeverLoot.OnSpellSucceeded(spellID)
  if not (GC.ForeverScan and GC.ForeverScan.Enabled and GC.ForeverScan.Enabled()) then return end
  if type(spellID) ~= "number" or not GATHER_SPELLS[spellID] then return end
  lastSpell = { id = spellID, at = clock() }
end

-- LOOT_CLOSED: the session ends, so the next LOOT_READY decides its own spell fresh.
function GC.ForeverLoot.OnLootClosed()
  sessionOpen, sessionSpell = false, nil
end

-- LOOT_READY and LOOT_OPENED (both registered: whichever this client sends; one window counts once).
function GC.ForeverLoot.OnLootReady()
  local now = time()
  local store = GC.ForeverLoot.Store(now)
  if not store then return end
  if not sessionOpen then
    sessionOpen = true
    sessionSpell = (lastSpell and clock() - lastSpell.at <= C.SPELL_WINDOW) and lastSpell.id or nil
  end
  local p = GC.Game and GC.Game.Passport and GC.Game.Passport() or {}
  local ctx = { map = mapID(), level = playerLevel(), spell = sessionSpell, now = now, region = p.regionId, build = p.build }
  GC.ForeverLoot.Ensure(store, ctx)
  GC.ForeverLoot.Record(store, readWindow(), ctx, seenMarks)
end

-- Once per account, in Forever: what it counts and how to stop it (D14).
function GC.ForeverLoot.MaybeIntro()
  local p = prefs()
  if not p or p.lootIntro then return false end
  p.lootIntro = true
  GC.Print(GC.L["GoldCap now counts what drops from what you loot, with no names, for drop rates on goldcap.gg. The Companion shares it once that part is released. Type /gc loot off to stop."])
  return true
end

-- /gc loot [on | off | clear]
function GC.ForeverLoot.Slash(rest)
  local p = prefs()
  if not p then return end
  local word = (type(rest) == "string" and rest or ""):lower()
  if word == "clear" then
    -- M7 (final review): /gc loot off only stops counting; this is the separate act of removing
    -- what has already been recorded.
    local root = GC.ForeverScan.Root()
    if root then root.foreverLoot = nil end
    GC.Print(GC.L["Loot record cleared."])
    return
  elseif word == "off" then
    p.lootOff = true
  elseif word == "on" then
    p.lootOff = nil
  end
  GC.Print(p.lootOff and GC.L["Loot counting is off. Type /gc loot clear to remove what was recorded."]
    or GC.L["Loot counting is on."])
end

-- For /gc forever (Core/ForeverCheck.lua): plain English, a diagnostic.
function GC.ForeverLoot.Summary()
  if not (GC.ForeverScan and GC.ForeverScan.Enabled and GC.ForeverScan.Enabled()) then return {} end
  local p = prefs()
  if p and p.lootOff then return { "loot recorder: off (/gc loot on)" } end
  local root = GC.ForeverScan.Root()
  local s = root and root.foreverLoot
  if type(s) ~= "table" or type(s.rows) ~= "table" then return { "loot recorder: nothing recorded yet" } end
  local lines = { ("loot recorder: generation %d, %d sources since %s, id %s"):format(s.gen or 0, s.n or 0,
    tostring(s.since), tostring(s.id)) }
  local key = next(s.rows)
  if key then lines[2] = ("loot recorder sample: %s = %s"):format(key, s.rows[key]) end
  return lines
end
