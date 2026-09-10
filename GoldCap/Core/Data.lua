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

-- The portal CVar is the only region signal the client offers, and it is not a reliable
-- one: warcraft.wiki.gg notes GetCurrentRegion() derives from this same CVar and "does
-- not necessarily indicate the region of the realm that the player is logged into" --
-- Taiwanese realms in particular connect through the Korean portal, so TW cannot be
-- detected at all. Hence this is only the fallback: adoptRegion below prefers the region
-- named by the imported string, which the player (or the companion) chose explicitly.
local function portalRegion()
  local ok, portal = pcall(function() return GetCVar and GetCVar("portal") end)
  portal = ok and type(portal) == "string" and portal:lower() or nil
  if portal and GC.ImportString and GC.ImportString.REGIONS[portal] then return portal end
  return nil
end

local function detectRegion()
  return portalRegion() or "us"
end

-- One place that decides which region we are in and which bundled table backs it, called
-- both at load and whenever an import lands. An import arriving mid-session used to leave
-- `region` on whatever the portal guessed, so GetStatus() reported the wrong region and
-- GetItemValue fell back to another region's bundled prices.
local function adoptRegion()
  local imported = db and db.imported
  region = (imported and imported.region) or detectRegion()
  local all = _G.GoldCap_MarketData
  bundled = all and all[region] or nil
end

function GC.Data.Init(database)
  db = database
  adoptRegion()
end

-- The region the CLIENT is connected to -- a different question from GetStatus().region,
-- which is the region whose PRICES are loaded. Those two are the same for almost every
-- player and diverge the moment somebody imports another region's snapshot, which is a
-- perfectly reasonable thing to do (comparing markets, testing, a companion pointed at the
-- wrong realm). Callers that record a FACT about where the player is -- the ledger above
-- all -- must ask this one; callers that value an item must keep asking GetStatus().
--
-- nil, never a guess: detectRegion above answers "us" when the portal CVar is unreadable
-- because a price table has to come from somewhere, but stamping a guessed region onto an
-- accounting row is exactly the defect this function exists to end. A caller that gets nil
-- should fall back to whatever it did before, not invent an answer here.
--
-- Note that TW clients connect through the Korean portal and so report `kr` (see
-- portalRegion's own note). That is a wrong LABEL but a consistent one: every row a TW
-- player records carries it, buys and sales alike, so nothing fails to pair. The defect
-- being fixed is inconsistency over time, not the label.
function GC.Data.ClientRegion()
  return portalRegion()
end

--- Non-nil when the loaded snapshot is from a different region than the client is playing
-- in -- i.e. every discount, tier and profit figure on screen is being measured against a
-- market the player is not standing in. Silent until now; the caller is expected to say so.
function GC.Data.RegionMismatch()
  local imported = db and db.imported
  local importedRegion = imported and imported.region
  local client = portalRegion()
  if type(importedRegion) ~= "string" or importedRegion == "" then return nil end
  if not client or client == importedRegion then return nil end
  return { imported = importedRegion, client = client, realm = imported.realm }
end

-- Human sentences for ImportString.Parse's error codes. The manual dialog used to print
-- the bare code ("Import failed: bad_header"), and the companion path printed nothing at
-- all -- a player whose sync silently did nothing had no way to tell a broken file from an
-- addon that simply does not support their region.
local IMPORT_ERRORS = {
  bad_region = "this build of GoldCap does not know that region -- update the addon",
  bad_header = "that does not look like a GoldCap import string",
  too_long = "that string is too long to import",
  no_items = "that string carried no prices",
  empty = "there was nothing to import",
}

function GC.Data.DescribeImportError(reason)
  local sentence = IMPORT_ERRORS[reason]
  if sentence then return GC.L[sentence] end
  return GC.L["the import failed (%s)"]:format(tostring(reason))
end

-- nil, or { reason = <parser code>, writtenAt = <companion's stamp> }. Read by /goldcap
-- status and the Sniper's empty board so both say the same thing.
function GC.Data.AppDataError()
  return db and db.appDataError or nil
end

-- Just the region. GetStatus() also counts every bundled and imported item, which is a
-- full walk of tables holding thousands of entries -- fine for a slash command, ruinous
-- on the tooltip path, which runs on every mouseover.
function GC.Data.Region()
  return region
end

function GC.Data.SetImported(parsed)
  local imported = {
    region = parsed.region,
    realm = parsed.realm,
    ts = parsed.ts,
    items = parsed.items,
    watchlist = parsed.watchlist or {},
    namesWanted = parsed.namesWanted or {},
  }
  -- Keep pre-V SavedVariables byte-for-byte shaped as before; a supplied non-empty V section
  -- is persisted alongside its I records and adopted by the companion through this same path.
  if parsed.verification and next(parsed.verification) then
    imported.verification = parsed.verification
  end
  -- Q section (cheap-quarter line per commodity). Same rule as V: persisted only when the
  -- string carried one, so an older string leaves the save shaped exactly as before.
  if parsed.quarter and next(parsed.quarter) then
    imported.quarter = parsed.quarter
  end
  -- R section (reach24 per commodity). Same rule again -- and it has to be listed HERE
  -- explicitly, because this function copies a named field list rather than the parsed table:
  -- a section the list does not name is parsed, ignored and lost on the way to the save.
  if parsed.reach and next(parsed.reach) then
    imported.reach = parsed.reach
  end
  -- T section (region reference price + item level per realm item). Named here for the same
  -- reason R is: this function copies a named field list, so a section it does not name is
  -- parsed and then lost on the way to the save. Absent on every string the companion wrote
  -- before the section existed, and absent from the save in that case rather than empty.
  if parsed.targets and next(parsed.targets) then
    imported.targets = parsed.targets
  end
  db.imported = imported
  adoptRegion()
  GC.Data.WarnRegionMismatch()
  -- A fresh import can carry a fresh wanted list; resolve it now if the client is already
  -- in the world (the login path starts the first pass from Core/Init.lua instead).
  if GC.ItemNames and GC.ItemNames.Start then GC.ItemNames.Start(db, imported) end
end

-- Said once per distinct mismatch per session -- an import and the login check both call
-- this, and repeating it on every companion sync would train the player to ignore it.
local warnedFor = nil

--- Tells the player, in the one place they will see it, that the prices on screen are from
-- a market they are not standing in. Nothing said this before: an EU account running a KR
-- snapshot saw KR discounts, KR tiers and KR profit on every EU auction for a full day, and
-- the only symptom was that Check kept refusing deals the board called HOT.
function GC.Data.WarnRegionMismatch()
  local mismatch = GC.Data.RegionMismatch()
  if not mismatch then warnedFor = nil return nil end
  local token = mismatch.imported .. "\1" .. mismatch.client
  if warnedFor == token then return mismatch end
  warnedFor = token
  if GC.Print then
    GC.Print((GC.L["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"])
      :format(mismatch.imported:upper(), tostring(mismatch.realm or "?"), mismatch.client:upper()))
  end
  return mismatch
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

  local parsed, reason = GC.ImportString.Parse(appData.importString)
  if not parsed then
    local writtenAt = type(appData.writtenAt) == "number" and appData.writtenAt or nil
    local previous = db and db.appDataError
    -- Once per companion write, never once per login: this runs on every ADDON_LOADED and
    -- a per-call print would be indistinguishable from spam.
    local isNew = not previous or previous.writtenAt ~= writtenAt or previous.reason ~= reason
    if db then db.appDataError = { reason = reason, writtenAt = writtenAt } end
    if isNew and GC.Print then
      GC.Print(GC.L["the Companion wrote prices this addon could not read --"] .. " "
        .. GC.Data.DescribeImportError(reason))
    end
    return
  end
  if db then db.appDataError = nil end

  local existing = db and db.imported
  if existing and parsed.ts <= existing.ts then return end

  GC.Data.SetImported(parsed)
  db.imported.origin = "app"

  local age = time() - parsed.ts
  if age < 0 then age = 0 end -- clock skew must never show a negative age, see importAgeSeconds
  if GC.Print then
    GC.Print(GC.L["auto-synced data for %s loaded (%s old)"]:format(parsed.realm, GC.Util.FormatAge(age)))
  end
end

function GC.Data.GetItemValue(itemID)
  local imp = db and db.imported
  local e = imp and imp.items and imp.items[itemID]
  -- Region reference for a realm item (import T section): what the item goes for across the
  -- region, and the item level that price was measured on. Import-path only, like p25 and
  -- reach, and independent of the I section -- the region can know a reference for an item
  -- this realm has no median for at all, which is the case the branch below exists for.
  local target = imp and imp.targets and imp.targets[itemID] or nil
  if e then
    -- Cheap-quarter line (import Q section). Absent on imports that predate it and on every
    -- realm item, and now only the fallback ceiling -- see `reach` just below.
    local p25 = imp.quarter and imp.quarter[itemID] or nil
    -- reach24 (import R section): what the item's floor actually reaches within a day. The
    -- Sell tab's ceiling for posting above the cheapest ask, with p25 above as the fallback
    -- for imports that predate it. Import-path only, like p25 -- bundled data carries neither.
    local reach = imp.reach and imp.reach[itemID] or nil
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
        p25 = p25,
        reach = reach,
      }
    end
    return { mv = e.m, sold = e.s, trend = e.t, ts = imp.ts, source = "import", kind = "realm_item",
      p25 = p25, reach = reach,
      ref = target and target.ref or nil, refIlvl = target and target.ilvl or nil }
  end
  if target then
    -- No I entry, but the region named a reference: a realm item this realm has no median
    -- for. There is no mv to return and nothing pretends there is -- GC.Trigger.RealmReference
    -- takes whichever of the two exists, and everything that needs an mv (DealMath, the
    -- commodity decision path) already refuses a value table without one.
    return { ts = imp.ts, source = "import", kind = "realm_item",
      ref = target.ref, refIlvl = target.ilvl }
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

-- One source of truth for "where did these prices come from" -- used by the Sniper header,
-- the empty-board copy and the stale-import warning so they agree with each other and with
-- GC.Data.GetStatus()'s importedOrigin field. Mirrors ImportDialog's slash-status rule: a
-- nil origin marker (SavedVariables written before the marker existed, or a manual paste,
-- which always wins the marker back to nil-equivalent "manual") reads the same as "manual".
function GC.Data.OriginState()
  local imp = db and db.imported
  if not imp or not imp.ts then return "none" end
  if imp.origin == "app" then return "app" end
  return "manual"
end

-- The item ids the region named as worth watching (import T section), ascending. The poll set
-- Core/KeyPoll.lua walks is built from this plus the player's pins and the site watchlist.
-- Sorted rather than pairs()-ordered so the round-robin cursor visits the same items in the
-- same order across sessions, and an empty list -- not nil -- when the import carried no T
-- section, which is every string written before the section existed.
function GC.Data.TargetIds()
  local imp = db and db.imported
  local ids = {}
  if not imp or not imp.targets then return ids end
  for id in pairs(imp.targets) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
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
      or not isPositiveInteger(purchase.decisionVersion)
      -- Same gate as GC.Ledger.RecordSniperBuy, and for the same reason: a realm lot is bought
      -- on a candidate and is never SAFE, so it is admitted on `unverified` -- and only on
      -- that, never on a bare WATCH. targetUnit below is the region reference, which is the
      -- one price anything measured for the item.
      or not (purchase.decisionStatus == "SAFE"
        or (purchase.decisionStatus == "WATCH" and purchase.unverified == true))
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

-- Live observations: bounded facts about the book the client just saw,
-- carried out via SavedVariables for the companion to upload (spec:
-- docs/superpowers/specs/2026-08-19-live-prices-from-player-scans-design.md).
-- Unlike sellQuotes — which deliberately does NOT persist levels — this
-- table persists at most five levels per item, newest scan wins per item,
-- 200 items, day-old rows pruned on write: the whole table stays small by
-- construction, which is the condition Init.lua's sellQuotes comment set.
GC.Data.LIVE_OBSERVATIONS_CAP = 200
GC.Data.LIVE_OBSERVATION_MAX_AGE = 24 * 60 * 60
GC.Data.LIVE_OBSERVATION_MAX_LEVELS = 5

function GC.Data.RecordLiveObservation(database, observation, now)
  if type(database) ~= "table" or type(observation) ~= "table" then return nil end
  if database.liveObservations == nil then database.liveObservations = {} end
  if type(database.liveObservations) ~= "table" then return nil end
  if not isPositiveInteger(now) or not isPositiveInteger(observation.itemID)
      or not isPositiveInteger(observation.minUnit)
      or (observation.region ~= "us" and observation.region ~= "eu") then return nil end
  if observation.listings ~= nil and not isPositiveInteger(observation.listings) then return nil end
  if observation.totalQty ~= nil and not isPositiveInteger(observation.totalQty) then return nil end

  local levels
  if type(observation.levels) == "table" then
    levels = {}
    for _, level in ipairs(observation.levels) do
      if #levels >= GC.Data.LIVE_OBSERVATION_MAX_LEVELS then break end
      if type(level) == "table" and isPositiveInteger(level.unitPrice) and isPositiveInteger(level.quantity) then
        levels[#levels + 1] = { unit = level.unitPrice, qty = level.quantity }
      end
    end
    if #levels == 0 then levels = nil end
  end

  local store = database.liveObservations
  -- Prune: same item (newest wins) and anything a day stale.
  for index = #store, 1, -1 do
    local row = store[index]
    if type(row) ~= "table" or row.itemID == observation.itemID
        or not isPositiveInteger(row.scannedAt)
        or now - row.scannedAt > GC.Data.LIVE_OBSERVATION_MAX_AGE then
      table.remove(store, index)
    end
  end
  -- Cap: evict the oldest scan until there is room.
  while #store >= GC.Data.LIVE_OBSERVATIONS_CAP do
    local oldestIndex, oldestAt = 1, math.huge
    for index, row in ipairs(store) do
      if (row.scannedAt or 0) < oldestAt then oldestIndex, oldestAt = index, row.scannedAt or 0 end
    end
    table.remove(store, oldestIndex)
  end

  store[#store + 1] = { itemID = observation.itemID, region = observation.region,
    scannedAt = now, minUnit = observation.minUnit, listings = observation.listings,
    totalQty = observation.totalQty, levels = levels }
  return true
end

-- Owned lots: the roster the Sell tab already reads via GetOwnedAuctions, kept for the
-- companion to upload so goldcap.gg's My auctions page can track a lot from post through
-- sale or cancellation (spec: docs/superpowers/specs/2026-09-06-my-auctions-design.md).
-- Unlike live observations, a row here survives even when it drops out of the roster --
-- absence IS the "gone by this account" signal the server reads, so the row must live long
-- enough to be uploaded before it is pruned.
GC.Data.OWNED_LOTS_CAP = 500
GC.Data.OWNED_LOT_MAX_AGE = 3 * 24 * 60 * 60

-- Deliberately GC.ImportString.REGIONS (us/eu/kr/tw), not RecordLiveObservation's narrower
-- "us" or "eu" check above: that check predates the kr/tw region rollout, and
-- GC.Ledger.Context().region -- this function's scope.region -- can genuinely be kr or tw
-- (GC.Data.ClientRegion -> portalRegion reads the client's own portal CVar against this same
-- list). Fixing RecordLiveObservation's narrower check is a separate change, not this one.
local function knownRegion(value)
  return GC.ImportString ~= nil and GC.ImportString.REGIONS ~= nil and GC.ImportString.REGIONS[value] == true
end

-- "Name-Realm", each half non-empty and no embedded hyphen (a realm name's own
-- hyphens are stripped by the client's own unique-name format) -- guards the
-- per-character scoping the upsert below and MarkOwnedLotCancelled rely on.
local function validCharScope(value)
  return type(value) == "string" and value:match("^[^-]+%-[^-]+$") ~= nil
end

function GC.Data.RecordOwnedLots(database, lots, scope, now)
  if type(database) ~= "table" then return nil end
  if database.ownedLots == nil then database.ownedLots = {} end
  if type(database.ownedLots) ~= "table" then return nil end
  if type(scope) ~= "table" or not validCharScope(scope.char)
      or not knownRegion(scope.region) then return nil end
  if not isPositiveInteger(now) then return nil end
  if type(lots) ~= "table" then return nil end

  local store = database.ownedLots
  -- Index this character's existing rows for O(1) upsert lookup. Scoped to scope.char so a
  -- roster from one character can never touch another's rows, even in the (never expected in
  -- practice) case of an auctionID collision across characters.
  local existingByAuction = {}
  for _, row in ipairs(store) do
    if type(row) == "table" and row.char == scope.char and isPositiveInteger(row.auctionID) then
      existingByAuction[row.auctionID] = row
    end
  end

  for _, incoming in ipairs(lots) do
    -- isCommodity must be an actual boolean -- coercing a missing/malformed
    -- value to false would silently mislabel a commodity lot as a per-realm
    -- item (or vice versa), which the server's watch set relies on being
    -- correct. Drop the row rather than guess.
    if type(incoming) == "table" and isPositiveInteger(incoming.auctionID)
        and isPositiveInteger(incoming.itemID) and isPositiveInteger(incoming.quantity)
        and isPositiveInteger(incoming.unitPrice) and type(incoming.isCommodity) == "boolean" then
      local expiresAt = isPositiveInteger(incoming.expiresAt) and incoming.expiresAt or nil
      local existing = existingByAuction[incoming.auctionID]
      if existing then
        -- Same price and quantity: not a new fact, cancelledAt (if any) survives. A changed
        -- price or quantity IS a new fact -- see RecordOwnedLots' own spec section.
        local samePriceQty = existing.quantity == incoming.quantity
          and existing.unitPrice == incoming.unitPrice
        existing.itemID = incoming.itemID
        existing.isCommodity = incoming.isCommodity
        existing.quantity = incoming.quantity
        existing.unitPrice = incoming.unitPrice
        existing.expiresAt = expiresAt
        existing.region = scope.region
        existing.seenAt = now
        if not samePriceQty then existing.cancelledAt = nil end
      else
        local row = { auctionID = incoming.auctionID, itemID = incoming.itemID,
          isCommodity = incoming.isCommodity, quantity = incoming.quantity,
          unitPrice = incoming.unitPrice, expiresAt = expiresAt, char = scope.char,
          region = scope.region, seenAt = now, cancelledAt = nil }
        existingByAuction[incoming.auctionID] = row
        store[#store + 1] = row
      end
    end
  end
  -- Rows for this char NOT in the roster, and every other char's rows, are left with their
  -- old seenAt untouched: absence is what the server reads as "gone by this account".

  -- Prune: anything past the retention window, for any character.
  for index = #store, 1, -1 do
    local row = store[index]
    if type(row) ~= "table" or not isPositiveInteger(row.seenAt)
        or now - row.seenAt > GC.Data.OWNED_LOT_MAX_AGE then
      table.remove(store, index)
    end
  end
  -- Cap: evict the oldest-seen row, across every character, until the table fits.
  while #store > GC.Data.OWNED_LOTS_CAP do
    local oldestIndex, oldestAt = 1, math.huge
    for index, row in ipairs(store) do
      if (row.seenAt or 0) < oldestAt then oldestIndex, oldestAt = index, row.seenAt or 0 end
    end
    table.remove(store, oldestIndex)
  end

  return true
end

function GC.Data.MarkOwnedLotCancelled(database, auctionID, scope, now)
  if type(database) ~= "table" or type(database.ownedLots) ~= "table" then return nil end
  if not isPositiveInteger(auctionID) or not isPositiveInteger(now) then return nil end
  -- Scoped to the current character, same as RecordOwnedLots' upsert: an
  -- auctionID collision across characters must never stamp the wrong row.
  if type(scope) ~= "table" or not validCharScope(scope.char) then return nil end
  local found = nil
  for _, row in ipairs(database.ownedLots) do
    if type(row) == "table" and row.auctionID == auctionID and row.char == scope.char then
      row.cancelledAt = now
      found = true
    end
  end
  return found
end
