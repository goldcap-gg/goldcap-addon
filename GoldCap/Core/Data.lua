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
