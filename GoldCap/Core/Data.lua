local _, GC = ...

GC.Data = {}

local db
local bundled -- region table from GoldCap_MarketData
local region

local function countItems(t)
  local n = 0
  if t then for _ in pairs(t) do n = n + 1 end end
  return n
end

local function detectRegion()
  local ok, portal = pcall(function() return GetCVar and GetCVar("portal") end)
  portal = ok and type(portal) == "string" and portal:lower() or nil
  if portal == "eu" then return "eu" end
  return "us"
end

function GC.Data.Init(database)
  db = database
  region = detectRegion()
  local all = _G.GoldCap_MarketData
  bundled = all and all[region] or nil
end

function GC.Data.SetImported(parsed)
  db.imported = {
    region = parsed.region,
    realm = parsed.realm,
    ts = parsed.ts,
    items = parsed.items,
    watchlist = parsed.watchlist or {},
  }
end

-- Companion sync (companion-v1 plan, Task A): a separate `GoldCap_AppData` addon --
-- see the .toc's OptionalDeps, which loads it before this one when present -- sets
-- `GoldCap_AppData = { importString = "GCS1;...", writtenAt = <unix ts> }`. This runs that
-- string through the SAME ImportString.Parse manual import uses (one parser, one validation
-- path) and only adopts it over whatever's already in db.imported when strictly newer --
-- ts equality is a no-op, not churn, same "freshest wins" rule manual import follows. A
-- malformed importString or an absent/malshaped global are both silent no-ops: the companion
-- is optional and never required for the addon to work standalone. GC.Print is guarded
-- because it's only defined once Core/Init.lua has loaded (true by the time this runs for
-- real, at ADDON_LOADED -- see Init.lua -- but not in specs that load Data.lua on its own).
function GC.Data.AdoptAppData()
  local appData = _G.GoldCap_AppData
  if type(appData) ~= "table" or type(appData.importString) ~= "string" then return end

  local parsed = GC.ImportString.Parse(appData.importString)
  if not parsed then return end

  local existing = db and db.imported
  if existing and parsed.ts <= existing.ts then return end

  GC.Data.SetImported(parsed)
  db.imported.origin = "app"

  local age = time() - parsed.ts
  if age < 0 then age = 0 end -- clock skew must never show a negative age, see importAgeSeconds
  if GC.Print then
    GC.Print(("auto-synced data for %s loaded (%s old)"):format(parsed.realm, GC.Util.FormatAge(age)))
  end
end

function GC.Data.GetItemValue(itemID)
  local imp = db and db.imported
  local e = imp and imp.items and imp.items[itemID]
  if e then
    -- trend (24h market-value momentum) is import-path only: MarketData.lua's
    -- bundled entries never carry a `t` field (see ImportString.Parse), so
    -- there's nothing to pass through for the bundled branch below.
    return { mv = e.m, sold = e.s, trend = e.t, ts = imp.ts, source = "import" }
  end
  e = bundled and bundled.items and bundled.items[itemID]
  if e then
    return { mv = e.m, sold = e.s, listings = e.l, ts = bundled.ts, source = "bundled" }
  end
  return nil
end

function GC.Data.GetStatus()
  local imp = db and db.imported
  return {
    region = region,
    bundledTs = bundled and bundled.ts or nil,
    bundledCount = countItems(bundled and bundled.items),
    importedTs = imp and imp.ts or nil,
    importedRealm = imp and imp.realm or nil,
    importedCount = countItems(imp and imp.items),
    importedOrigin = imp and imp.origin or nil,
  }
end

function GC.Data.GetWatchlist(fallbackN)
  local imp = db and db.imported
  if not imp then return {} end

  -- Copy: callers must never mutate persisted SavedVariables state.
  if imp.watchlist and #imp.watchlist > 0 then
    local copy = {}
    for i = 1, #imp.watchlist do copy[i] = imp.watchlist[i] end
    return copy
  end

  local ids = {}
  for id in pairs(imp.items or {}) do ids[#ids + 1] = id end
  -- Tiebreak by id so the top-N boundary is stable across sessions.
  table.sort(ids, function(a, b)
    local ma, mb = imp.items[a].m, imp.items[b].m
    if ma == mb then return a < b end
    return ma > mb
  end)
  local cap = math.max(fallbackN or 100, 0)
  while #ids > cap do table.remove(ids) end
  return ids
end

-- D: flip queue (Sniper v2 §D). db.flips is a plain SavedVariables array, same persistence
-- shape as db.imported -- GC.DEFAULTS.flips = {} (Init.lua) seeds it via GC.Util.ApplyDefaults
-- on first login and never touches it again once populated (ApplyDefaults only fills a table
-- default in when the existing value isn't already a table, and recurses over an EMPTY default
-- table's own pairs(), which is a no-op either way).
local FLIP_MAX_AGE_SECONDS = 14 * 24 * 3600

-- Every successful sniper purchase becomes one flip entry: `deal` only needs itemID/qty/
-- unitPrice (the shape SniperFrame's resolvePurchase already has in hand). `now` is
-- injectable for tests; defaults to time() so a live purchase never has to pass it.
-- targetUnit is resale-side math (floor(mv * 0.95), matching DealMath/SniperFrame's own resale
-- formula) evaluated fresh from GC.Data.GetItemValue AT RECORD TIME -- not the deal's own .mv --
-- so a flip's target reflects the freshest market read available, not a possibly-older
-- snapshot the deal was originally evaluated against. Falls back to paidUnit (breakeven-ish,
-- never a loss-looking recommendation out of the gate) when the item has no known value at all.
function GC.Data.RecordFlip(deal, now)
  if not db then return nil end -- defensive: mirrors GetItemValue/GetStatus/GetWatchlist above, which all tolerate GC.Data.Init not having run yet
  now = now or time()
  db.flips = db.flips or {}

  local value = GC.Data.GetItemValue(deal.itemID)
  local mv = value and value.mv
  local targetUnit = mv and math.floor(mv * 0.95) or deal.unitPrice

  local flip = {
    itemID = deal.itemID,
    qty = deal.qty,
    paidUnit = deal.unitPrice,
    paidTotal = deal.unitPrice * deal.qty,
    boughtAt = now,
    targetUnit = targetUnit,
  }
  db.flips[#db.flips + 1] = flip
  return flip
end

-- Prunes db.flips IN PLACE (posted entries, and anything older than FLIP_MAX_AGE_SECONDS as of
-- `now`) and returns the same live table -- not a copy, unlike GetWatchlist above -- so
-- GC.Data.MarkFlipPosted/RemoveFlip's index-based API stays valid against whatever GetFlips
-- most recently handed back, as long as nothing else prunes/removes in between. `now` is
-- injectable for tests; defaults to time(). Age is a strict `>` so an entry exactly
-- FLIP_MAX_AGE_SECONDS old is still shown one more time, not silently dropped a tick early.
function GC.Data.GetFlips(now)
  if not db then return {} end -- defensive: same as RecordFlip above
  now = now or time()
  local flips = db.flips or {}
  db.flips = flips
  for i = #flips, 1, -1 do
    local f = flips[i]
    if f.posted or (now - f.boughtAt) > FLIP_MAX_AGE_SECONDS then
      table.remove(flips, i)
    end
  end
  return flips
end

-- index is a position into the array GetFlips() most recently returned (the live db.flips
-- table) -- marking a flip posted here doesn't remove it immediately; the NEXT GetFlips() call
-- prunes it (see above), same one-call-later pattern as the age-based prune.
function GC.Data.MarkFlipPosted(index)
  local f = db and db.flips and db.flips[index]
  if f then f.posted = true end
end

function GC.Data.RemoveFlip(index)
  if db and db.flips and db.flips[index] then table.remove(db.flips, index) end
end
