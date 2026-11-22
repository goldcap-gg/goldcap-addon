local _, GC = ...

-- Which game client this is. WoW: Forever reports WOW_PROJECT_ID 1, the same as retail, so
-- the interface number is the only reliable tell: retail's are six digits (120100), every
-- other client is below (Classic Era 11508, Anniversary 20505, MoP Classic 50500, Forever
-- 16001). The passport is written into GoldCapDB.client on every load; the companion sends
-- it with every upload and keeps another game's files away from the retail routes
-- (docs/companion/AGENTS.md "Client passport").
GC.Game = GC.Game or {}
GC.Game.RETAIL_MIN_INTERFACE = 100000

local function defaultApi()
  return { GetBuildInfo = _G.GetBuildInfo, GetCurrentRegion = _G.GetCurrentRegion }
end

function GC.Game.Passport(api)
  api = api or defaultApi()
  if type(api.GetBuildInfo) ~= "function" then return nil end
  local ok, version, build, _, toc = pcall(api.GetBuildInfo)
  if not ok or type(toc) ~= "number" or type(version) ~= "string" or build == nil then return nil end
  local regionId
  if type(api.GetCurrentRegion) == "function" then
    local rok, region = pcall(api.GetCurrentRegion)
    if rok and type(region) == "number" then regionId = region end
  end
  return { interface = toc, build = version .. "." .. tostring(build), regionId = regionId }
end

function GC.Game.IsRetail(passport)
  if passport == nil then return true end
  return passport.interface >= GC.Game.RETAIL_MIN_INTERFACE
end

-- WoW: Forever's interface numbers (16001 in the beta). A range, not one value: the number
-- moves with every Forever patch, the way retail's does.
GC.Game.FOREVER_MIN_INTERFACE = 16000
GC.Game.FOREVER_MAX_INTERFACE = 16999

function GC.Game.IsForever(passport)
  if passport == nil or type(passport.interface) ~= "number" then return false end
  return passport.interface >= GC.Game.FOREVER_MIN_INTERFACE and passport.interface <= GC.Game.FOREVER_MAX_INTERFACE
end

-- ---------------------------------------------------------------------------------------------
-- The realm's name. WoW: Forever's client 1.60.1.71037 answers GetRealmName() with "" and
-- GetNormalizedRealmName() with nil (owner's save: the last row with a realm 2026-11-19, the first
-- without 2026-11-21; a player's report the same day). Every row then went out keyed "Name-": the
-- scan's fold had no realm and never uploaded, and the cost batches keyed "Name-Realm" stopped
-- matching ("no cost for N"). The answer, in the order it can be trusted:
--   1. the live API, remembered per server (the GUID's "Player-<server>-…") whenever it answers;
--   2. what it last said on this server;
--   3. the realm this character's own rows in the save were written with, when there is one;
--   4. nil. Never a guess: a region has several realms.
-- ---------------------------------------------------------------------------------------------

GC.Game._historyMissed = {}

local function realmApi()
  return {
    GetRealmName = _G.GetRealmName, GetNormalizedRealmName = _G.GetNormalizedRealmName,
    UnitGUID = _G.UnitGUID, UnitName = _G.UnitName,
    db = function() return GC.db end,
  }
end

local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

local function named(value) return type(value) == "string" and value ~= "" and value or nil end

--- The server number in a player GUID ("Player-6949-00C1ADCA" -> "6949"), or nil.
function GC.Game.ServerId(guid)
  return type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
end

-- The realms this character's own rows were written with ("Name-Realm" in a `char` or
-- `character` field anywhere in the save), when exactly one: two realms under one name are two
-- characters, and neither is a safe answer.
local function fromHistory(db, name)
  if type(db) ~= "table" or not named(name) then return nil end
  local prefix, found, seen = name .. "-", nil, {}
  local function walk(t, depth)
    if depth > 6 or seen[t] then return end
    seen[t] = true
    for key, value in pairs(t) do
      if type(value) == "table" then
        walk(value, depth + 1)
      elseif (key == "char" or key == "character") and type(value) == "string"
          and value:sub(1, #prefix) == prefix and #value > #prefix then
        local realm = value:sub(#prefix + 1)
        if found and found ~= realm then found = false end
        if found == nil then found = realm end
      end
    end
  end
  walk(db, 0)
  return found or nil
end

--- This character's realm name, or nil. `api` replaces the client for specs.
function GC.Game.RealmName(api)
  api = api or realmApi()
  local db = api.db and api.db() or nil
  local server = GC.Game.ServerId(ask(api.UnitGUID, "player"))
  local known = type(db) == "table" and type(db.realmByServer) == "table" and db.realmByServer or nil
  local function remember(realm)
    if server and type(db) == "table" then
      db.realmByServer = db.realmByServer or {}
      db.realmByServer[server] = realm
    end
    return realm
  end
  local live = named(ask(api.GetRealmName))
  if live then return remember(live) end
  if server and known and named(known[server]) then return known[server] end
  -- The history walk reads the whole save: once a session per server when it finds nothing.
  local missKey = tostring(server)
  if GC.Game._historyMissed[missKey] and not api.fresh then return nil end
  local recovered = fromHistory(db, ask(api.UnitName, "player"))
  if not recovered then
    GC.Game._historyMissed[missKey] = true
    return nil
  end
  return remember(recovered)
end

--- The realm as the client normalizes it for "Name-Realm" whispers and mail (no spaces, no
-- hyphens), or nil: GetNormalizedRealmName when it answers, else RealmName normalized.
function GC.Game.NormalizedRealmName(api)
  api = api or realmApi()
  local live = named(ask(api.GetNormalizedRealmName))
  if live then return live end
  local realm = GC.Game.RealmName(api)
  return realm and (realm:gsub("[%s%-]", "")) or nil
end

--- Rewrites what this character wrote without a realm ("Name-") to "Name-Realm", once the realm
-- is known:
--   - a `char` or `character` field of this region (or with none: another region's "Name-" is
--     someone else);
--   - a table keyed "Name-" or "Name-<region>" (craft.chars, buyProgress, foreverDeposits.streaks);
--   - a scope key "<region>\1Name-\1<position>" (GC.Acquisitions.ScopeKey), as a table key
--     (acquisitionActivity) or a `scopeKey` field: Acquisitions refuses every sale while one
--     activity's key and character disagree (validStoredActivity), so the field alone is not enough.
-- A key that already has its "Name-Realm" twin is merged into it: the realmless side wins, as the
-- newer, except that a `firstSeenAt` keeps the earlier stamp and another `...At` the later one.
-- Returns how many it rewrote.
function GC.Game.RepairRealmless(db, name, realm, region)
  if type(db) ~= "table" or not named(name) or not named(realm) then return 0 end
  local bare, full, fixed, seen = name .. "-", name .. "-" .. realm, 0, {}
  local suffix = named(region) and region or nil
  local scopedBare, scopedFull = "\1" .. bare .. "\1", "\1" .. full .. "\1"
  local function rescoped(value)
    if type(value) ~= "string" then return nil end
    local at = value:find(scopedBare, 1, true)
    if not at then return nil end
    return value:sub(1, at - 1) .. scopedFull .. value:sub(at + #scopedBare)
  end
  local function merge(into, from)
    for k, v in pairs(from) do
      local old = into[k]
      if type(k) == "string" and type(v) == "number" and type(old) == "number" and k:match("At$") then
        into[k] = (k == "firstSeenAt") and math.min(old, v) or math.max(old, v)
      else
        into[k] = v
      end
    end
  end
  local function walk(t, depth)
    if depth > 6 or seen[t] then return end
    seen[t] = true
    local sameRegion = t.region == nil or region == nil or t.region == region
    local moves = {}
    for key, value in pairs(t) do
      if key == bare then
        moves[#moves + 1] = { key, full }
      elseif suffix and key == bare .. suffix then
        moves[#moves + 1] = { key, full .. suffix }
      elseif rescoped(key) then
        moves[#moves + 1] = { key, rescoped(key) }
      end
      if type(value) == "table" then
        walk(value, depth + 1)
      elseif sameRegion and (key == "char" or key == "character") and value == bare then
        t[key] = full
        fixed = fixed + 1
      elseif key == "scopeKey" and rescoped(value) then
        t[key] = rescoped(value)
        fixed = fixed + 1
      end
    end
    for _, move in ipairs(moves) do
      local from, to = t[move[1]], move[2]
      if type(from) == "table" and type(t[to]) == "table" then
        merge(t[to], from)
      elseif t[to] == nil then
        t[to] = from
      end
      t[move[1]] = nil
      fixed = fixed + 1
    end
  end
  walk(db, 0)
  return fixed
end

-- WoW: Forever's client stopped naming the realm on 2026-11-19 (00:00 UTC). Sales before it
-- matched their stock when they arrived.
GC.Game.REALMLESS_SINCE = 1795046400

--- Offers this character's sales since REALMLESS_SINCE that consumed no stock back to
-- GC.Acquisitions.ReconcileSale, once per character (db.realmSalesReconciled). ReconcileSale
-- refuses a duplicate and changes nothing on any refusal. Returns how many it applied.
function GC.Game.ReconcileRealmlessSales(db, char, reconcile)
  reconcile = reconcile or (GC.Acquisitions and GC.Acquisitions.ReconcileSale)
  if type(db) ~= "table" or not named(char) or type(reconcile) ~= "function" then return 0 end
  db.realmSalesReconciled = type(db.realmSalesReconciled) == "table" and db.realmSalesReconciled or {}
  if db.realmSalesReconciled[char] then return 0 end
  local consumed = type(db.acquisitionConsumptionEvidence) == "table" and db.acquisitionConsumptionEvidence or {}
  local sales = {}
  for _, entry in ipairs(type(db.ledger) == "table" and db.ledger or {}) do
    if type(entry) == "table" and entry.kind == "sale" and entry.source == "mail" and entry.char == char
        and type(entry.at) == "number" and entry.at >= GC.Game.REALMLESS_SINCE
        and type(entry.key) == "string" and not consumed[entry.key] then
      sales[#sales + 1] = entry
    end
  end
  -- Oldest first: the stock they consume goes oldest first too.
  table.sort(sales, function(a, b) return a.at < b.at end)
  local applied = 0
  for _, entry in ipairs(sales) do
    local result = reconcile(entry)
    if type(result) == "table" and result.status == "applied" then applied = applied + 1 end
  end
  db.realmSalesReconciled[char] = true
  return applied
end
