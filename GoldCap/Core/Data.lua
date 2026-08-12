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
  local imported = {
    region = parsed.region,
    realm = parsed.realm,
    ts = parsed.ts,
    items = parsed.items,
    watchlist = parsed.watchlist or {},
  }
  -- Keep pre-V SavedVariables byte-for-byte shaped as before; a supplied non-empty V section
  -- is persisted alongside its I records and adopted by the companion through this same path.
  if parsed.verification and next(parsed.verification) then
    imported.verification = parsed.verification
  end
  db.imported = imported
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
    local fact = imp.verification and imp.verification[itemID]
    if fact then
      return {
        mv = e.m, sold = e.s, trend = e.t, ts = imp.ts, source = "import",
        kind = "region_commodity",
        sourceAt = fact.sourceAt,
        estimated = fact.flags % 2 == 1,
        stressUnit = fact.stressUnit,
        sellThroughBps = fact.sellThroughBps,
        liquidityConfidence = fact.liquidityConfidence,
        currentQty = fact.currentQty,
        listings = fact.listings,
        observations = fact.observations,
        madBps = fact.madBps,
      }
    end
    return { mv = e.m, sold = e.s, trend = e.t, ts = imp.ts, source = "import", kind = "realm_item" }
  end
  e = bundled and bundled.items and bundled.items[itemID]
  if e then
    return {
      mv = e.m, sold = e.s, listings = e.l, ts = bundled.ts, source = "bundled",
      kind = e.s and "region_commodity" or "realm_item",
    }
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
local MAX_EXACT = 9007199254740991

local function isExactInteger(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
      and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

local function isPositiveInteger(value)
  return isExactInteger(value) and value > 0
end

local function isNonNegativeInteger(value)
  return isExactInteger(value)
end

local function isReasonsArray(reasons)
  if type(reasons) ~= "table" then return false end
  for i = 1, #reasons do
    if type(reasons[i]) ~= "string" then return false end
  end
  return true
end

-- Every successful protected sniper purchase becomes one flip entry. `purchase` is the immutable
-- success fact: its total is authoritative, while unitDisplay is only for presentation. The
-- stress target comes from the decision that permitted the purchase, never from a later market
-- read or a paid-unit fallback. Invalid legacy/direct calls deliberately record nothing: inventing
-- a target or reconstructing a total would turn an unknown cost into false accounting.
function GC.Data.RecordFlip(deal, purchase, now)
  if not db then return nil end -- defensive: mirrors GetItemValue/GetStatus/GetWatchlist above, which all tolerate GC.Data.Init not having run yet
  if type(deal) ~= "table" or type(purchase) ~= "table"
      or not isPositiveInteger(deal.itemID) or purchase.itemID ~= deal.itemID
      or not isPositiveInteger(purchase.quantity) or not isPositiveInteger(purchase.total)
      or not isNonNegativeInteger(purchase.unitDisplay) or purchase.unitDisplay ~= math.floor(purchase.total / purchase.quantity)
      or not isPositiveInteger(purchase.decisionVersion) or purchase.decisionStatus ~= "SAFE"
      or not isReasonsArray(purchase.decisionReasons)
      or not isPositiveInteger(purchase.stressUnit)
      or not isNonNegativeInteger(purchase.expectedProfit)
      or not isPositiveInteger(purchase.recommendedQuantity)
      or not isNonNegativeInteger(purchase.sourceAt) then
    return nil
  end
  now = now or time()
  db.flips = db.flips or {}

  local flip = {
    itemID = deal.itemID,
    qty = purchase.quantity,
    paidUnit = purchase.unitDisplay,
    paidTotal = purchase.total,
    boughtAt = now,
    targetUnit = purchase.stressUnit,
  }
  db.flips[#db.flips + 1] = flip
  return flip
end

-- Prunes db.flips IN PLACE (anything older than FLIP_MAX_AGE_SECONDS as of `now`) and returns
-- the same live table -- not a copy, unlike GetWatchlist above -- so GC.Data.MarkFlipPosted/
-- RemoveFlip's index-based API stays valid against whatever GetFlips most recently handed back,
-- as long as nothing else prunes/removes in between. `now` is injectable for tests; defaults to
-- time(). Age is a strict `>` so an entry exactly FLIP_MAX_AGE_SECONDS old is still shown one
-- more time, not silently dropped a tick early.
--
-- F1 (lifecycle fix): NO LONGER prunes on `f.posted`. The old rule pruned a flip the instant
-- MarkFlipPosted fired (AUCTION_HOUSE_AUCTION_CREATED, see UI/SellFrame.lua's OnAuctionCreated)
-- -- meaning the exact moment a player posted a lot, its cost basis vanished from db.flips and
-- the live lot degraded to a basis-less orphan row (Core/Flips.lua's OrphanLotRows) for the
-- REST of its time on the AH. Direct player requirement: the paid price must always stay
-- visible while the lot is up, through a sale AND through a cancel-and-repost. Age alone is now
-- the only prune condition -- a posted flip ages out same as any other, FLIP_MAX_AGE_SECONDS
-- after it was originally bought (not re-based off postedAt), which is generous enough to
-- outlive any realistic listing duration.
--
-- No SavedVariables migration needed for this change: the OLD rule pruned on every single
-- GetFlips() call (renderRows/uniqueQuoteItemIDs/currentIndexOf/SellableCount in
-- UI/SellFrame.lua all call it constantly), so a posted flip was removed from db.flips within
-- one call of ever being marked -- no player's persisted db.flips can contain a lingering
-- `posted = true` row from before this fix; there is nothing stale to migrate away from.
function GC.Data.GetFlips(now)
  if not db then return {} end -- defensive: same as RecordFlip above
  now = now or time()
  local flips = db.flips or {}
  db.flips = flips
  for i = #flips, 1, -1 do
    local f = flips[i]
    if (now - f.boughtAt) > FLIP_MAX_AGE_SECONDS then
      table.remove(flips, i)
    end
  end
  return flips
end

-- index is a position into the array GetFlips() most recently returned (the live db.flips
-- table). F1: marking a flip posted no longer causes it to be pruned at all (see GetFlips'
-- own comment) -- `postedAt` (defaulting to time(), injectable for tests same as RecordFlip's
-- `now`) is stamped alongside `posted` purely as a timestamp for Core/Flips.lua's BuildRow to
-- compare a ledger sale's `at` against (the SOLD status floor), replacing boughtAt for that one
-- purpose once a flip has actually been posted.
function GC.Data.MarkFlipPosted(index, now)
  local f = db and db.flips and db.flips[index]
  if f then
    f.posted = true
    f.postedAt = now or time()
  end
end

function GC.Data.RemoveFlip(index)
  if db and db.flips and db.flips[index] then table.remove(db.flips, index) end
end

-- ---------------------------------------------------------------------------
-- F2: personal sale rate -- TSM's "SaleRate" concept, but computed from OUR OWN post/sale
-- history rather than realm-wide scraped data. Deliberately a SEPARATE axis from
-- GC.Data.GetItemValue's `sold` field (imported sold-per-day, realm market VELOCITY -- what
-- Core/Flips.lua's SellOutlook already projects an ETA from): "of the lots I posted, how many
-- of them sold" answers a different question -- a per-posting probability, not a throughput
-- rate -- and conflating the two would misrepresent an item that moves fast realm-wide but that
-- THIS player has a poor track record pricing competitively for, or vice versa.
--
-- Storage lives on the SAME db table Data.lua already owns (db.postStats, sibling to db.flips/
-- db.imported), lazily initialized the same way RecordFlip lazily inits db.flips -- one entry
-- per itemID: { posts, sales, name }.
-- ---------------------------------------------------------------------------

-- A posting-stats table keyed by itemID can't be allowed to grow unbounded in SavedVariables
-- the way db.flips (age-pruned, Sniper v2 §D) and db.ledger (GC.Ledger.MAX_ENTRIES-capped)
-- already guard against -- without a cap, a player who tries selling hundreds of different items
-- over months of play would accumulate one entry per distinct item forever. 500 is a generous
-- ceiling for "distinct items this player has ever posted through GoldCap."
local POST_STATS_CAP = 500

-- Evicts the single least-posted entry once db.postStats exceeds POST_STATS_CAP. A low-posts
-- item is, almost definitionally, the one whose sale-rate signal matters least -- GetSaleRate
-- itself refuses to answer below 3 posts anyway (see below), so an evicted entry was never
-- surfacing a rate to the player in the first place. Ties (several entries share the current
-- minimum) are broken by whichever pairs() happens to visit first -- there is no ordering signal
-- among equally-low entries worth preserving, and this only ever runs once per call, on however
-- many entries currently exceed the cap by exactly one.
local function evictLeastPosted(stats)
  local victimID, victimPosts
  for id, entry in pairs(stats) do
    if victimID == nil or entry.posts < victimPosts then
      victimID, victimPosts = id, entry.posts
    end
  end
  if victimID then stats[victimID] = nil end
end

--- Records one posting event for itemID -- called from UI/SellFrame.lua's OnAuctionCreated
-- right after a post is confirmed via MarkFlipPosted. `itemName` refreshes the cached display
-- name whenever a real (non-nil) one is passed -- RecordSaleEvent below has nothing else to key
-- a sale against, so an entry's name needs to track the item's actual current name, not freeze
-- at whatever was known the first time this item was ever posted.
function GC.Data.RecordPostEvent(itemID, itemName)
  if not db then return end -- defensive: mirrors RecordFlip/GetFlips above
  db.postStats = db.postStats or {}
  local entry = db.postStats[itemID]
  if not entry then
    entry = { posts = 0, sales = 0, name = itemName }
    db.postStats[itemID] = entry
  end
  entry.posts = entry.posts + 1
  if itemName then entry.name = itemName end

  local count = 0
  for _ in pairs(db.postStats) do count = count + 1 end
  if count > POST_STATS_CAP then
    evictLeastPosted(db.postStats)
  end
end

--- Records one sale event, matched by item NAME -- Core/Ledger.lua's sale entries never carry
-- an itemID (a sale mail has money attached and nothing else; itemName is all there is to key
-- on, the same constraint GC.Flips.SalesForItem already documents). Finds the postStats entry
-- whose cached `.name` equals `itemName`; a miss (no entry posted through GoldCap ever carried
-- this name -- a manual AH post, or a sale of an item posted before this feature existed) is a
-- SILENT no-op, not an error: that sale carries no signal for what THIS addon posted, so there
-- is nothing to attribute it to.
function GC.Data.RecordSaleEvent(itemName)
  if not db or not db.postStats or not itemName then return end
  for _, entry in pairs(db.postStats) do
    if entry.name == itemName then
      entry.sales = entry.sales + 1
      return
    end
  end
end

--- Returns { rate, posts, sales } for itemID, or nil when the signal isn't trustworthy yet.
--
-- Below 3 posts the "rate" is noise -- a single sale out of one or two posts swings from 0% to
-- 100% and back on the very next data point, telling the player nothing actionable. 3 is a
-- deliberately low, cheap-to-reach floor, not a statistically rigorous minimum sample size --
-- the goal is filtering out the single-post case, not building a confidence interval.
--
-- rate is min-clamped at 1: `entry.sales` can exceed `entry.posts` when an item is ALSO posted
-- manually (via Blizzard's own AH window, never counted by RecordPostEvent) and that manual
-- posting later sells -- RecordSaleEvent's name-match counts the sale regardless of which path
-- posted it, so the denominator (posts, GoldCap-attributed only) can undercount relative to the
-- numerator (sales, name-attributed). A rate over 100% would be a nonsensical number to show a
-- player; clamping communicates "this item sells reliably" without the confusing overshoot.
function GC.Data.GetSaleRate(itemID)
  local entry = db and db.postStats and db.postStats[itemID]
  if not entry or entry.posts < 3 then return nil end
  return {
    rate = math.min(entry.sales / entry.posts, 1),
    posts = entry.posts,
    sales = entry.sales,
  }
end
