local _, GC = ...

GC.Data = {}

local db
local bundled -- region table from GoldCap_MarketData
local region
-- The whole-market region payload (GCM1) the Companion writes beside the import string as
-- GoldCap_AppData.regionString. Parsed at load and kept HERE, in memory only: it is never copied
-- into db. GoldCapDB is this addon's one SavedVariables table, written on every logout and read by
-- the Companion four times a sync, and thousands of facts would add megabytes to both.
local payload
-- How far ahead of this machine's clock a payload may be dated: clock skew between the player and
-- the site, and nothing more (see AdoptRegionPayload).
local PAYLOAD_FUTURE_SLACK_SECONDS = 3600
-- How much newer than the payload an import of its region may be before the payload yields to it
-- (see inactiveReason). The Companion's own freshness window for the payload.
local PAYLOAD_IMPORT_LAG_SECONDS = 3 * 3600
-- { reason, ts } for the last payload offered that could not be used, or nil; read through
-- RegionPayloadStatus. In memory only, like the payload. One set aside for the prices loaded at the
-- time (inactiveReason) also keeps its region, so the reason can be judged again when asked.
local payloadFailure
local dropIdlePayload -- defined beside inactiveReason, called from SetImported
-- FactItemIds' memo. It holds the payload it was built from, so it goes wherever the payload is let go.
local factIds

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
  GC.Data.WarnRegionUnknown()
end

-- Said once per session, at load: the portal CVar could not be read, so nothing knows which
-- region this client is in and detectRegion's "us" fallback is what picked the price table.
-- That fallback is fine -- a price table has to come from somewhere -- but it was completely
-- silent, so a player outside the US could spend a session reading US prices for their own
-- realm with nothing on screen saying so. The tooltip's own "Bundled US data" line already
-- appears for every item answered this way (opts.region comes from GC.Data.Region); this is
-- the one line that explains why it says US.
--
-- Nothing is said once an import is loaded: an import names its own region explicitly, so
-- there is no guess left to warn about.
local warnedRegionUnknown = false
function GC.Data.WarnRegionUnknown()
  if warnedRegionUnknown then return nil end
  -- No GetCVar at all is no CLIENT at all (the spec bed, or a load outside the game); there
  -- is nothing to tell anybody. The warning is for a client that has the CVar and still
  -- cannot answer -- a PTR portal, say.
  if not GetCVar then return nil end
  if portalRegion() then return nil end
  local imported = db and db.imported
  if imported and type(imported.region) == "string" and imported.region ~= "" then return nil end
  warnedRegionUnknown = true
  if GC.Print then
    GC.Print(GC.L["GoldCap could not tell which region you are playing in, so it is showing bundled US prices -- /goldcap import or /goldcap companion loads your own realm's"])
  end
  return true
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
  -- Taiwanese realms connect through the KOREAN portal (see portalRegion's own note), so a
  -- TW player's client reports `kr` and there is no client-side fact that can tell the two
  -- apart. Calling that a mismatch told every TW player, every session, that their own TW
  -- prices came from a market they were not standing in -- a warning that was always wrong
  -- and that trains players to ignore the one case it exists for.
  if client == "kr" and importedRegion == "tw" then return nil end
  return { imported = importedRegion, client = client, realm = imported.realm }
end

-- Human sentences for ImportString.Parse's error codes. The manual dialog used to print
-- the bare code ("Import failed: bad_header"), and the companion path printed nothing at
-- all -- a player whose sync silently did nothing had no way to tell a broken file from an
-- addon that simply does not support their region.
--
-- @localised-keys: the literals below ARE GC.L keys, looked up in DescribeImportError where
-- the table is READ rather than here -- this is file scope, and GC.L only resolves once
-- ApplyLocale has run at ADDON_LOADED, so a lookup here would freeze the English fallback
-- into every language. Without the marker the contract spec cannot see them at all, and
-- these five sentences sat English in eleven languages. The table has to close with a `}`
-- on its own line: that is where the spec's scanner stops.
local IMPORT_ERRORS = {
  bad_region = "this build of GoldCap does not know that region -- update the addon",
  bad_header = "that does not look like a GoldCap import string",
  no_realm = "that string does not name a realm",
  two_strings = "that looks like two import strings pasted together -- paste just one",
  too_long = "that string is too long to import",
  no_items = "that string carried no prices",
  empty = "there was nothing to import",
}

function GC.Data.DescribeImportError(reason)
  local sentence = IMPORT_ERRORS[reason]
  if sentence then return GC.L[sentence] end
  return GC.L["the import failed (%s)"]:format(tostring(reason))
end

-- Which companion failure this SESSION has already printed, as reason+writtenAt. The gate
-- used to be the PERSISTED db.appDataError, which meant a broken companion write was
-- announced once and then never again -- not next login, not next week, while every session
-- silently went on using stale prices. A session flag says it once a session instead, which
-- is the cadence WarnRegionMismatch already uses for the same kind of fact.
local warnedAppDataError = nil

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
  if not db then return end -- defensive: mirrors GetItemValue/GetStatus/GetWatchlist, which all tolerate Init not having run
  db.imported = imported
  -- A working import is the answer to "the Companion wrote prices this addon could not read":
  -- the recorded error described a payload that is no longer what is loaded, and it used to
  -- survive a manual paste for good -- /goldcap status and the Sniper's empty board kept
  -- reporting a sync failure at a player whose prices were fine.
  db.appDataError = nil
  warnedAppDataError = nil
  adoptRegion()
  dropIdlePayload()
  GC.Data.WarnRegionMismatch()
  -- A fresh import can carry a fresh wanted list; resolve it now if the client is already
  -- in the world (the login path starts the first pass from Core/Init.lua instead).
  if GC.ItemNames and GC.ItemNames.Start then GC.ItemNames.Start(db, imported) end
end

-- Said once per distinct mismatch per session -- an import and the login check both call
-- this, and repeating it on every companion sync would train the player to ignore it.
local warnedFor = nil

--- The mismatch as one sentence, or nil when there is none. One sentence in one place: the
-- warning below and /goldcap status both say it, and a player who scrolled past the chat
-- line an hour ago needs the status command to still be able to tell them.
function GC.Data.RegionMismatchText()
  local mismatch = GC.Data.RegionMismatch()
  if not mismatch then return nil end
  return (GC.L["prices loaded are %s (%s) but you are playing in %s — every discount and profit figure is measured against another market"])
    :format(mismatch.imported:upper(), tostring(mismatch.realm or "?"), mismatch.client:upper())
end

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
  if GC.Print then GC.Print(GC.Data.RegionMismatchText()) end
  return mismatch
end

local function recordAppDataError(reason, writtenAt)
  if db then db.appDataError = { reason = reason, writtenAt = writtenAt } end
  -- Once per session per distinct failure. This runs on every ADDON_LOADED, so a per-call
  -- print would be spam; the old per-WRITE gate went the other way and said it once, ever.
  local token = tostring(reason) .. "\1" .. tostring(writtenAt)
  if warnedAppDataError == token then return end
  warnedAppDataError = token
  if GC.Print then
    GC.Print(GC.L["the Companion wrote prices this addon could not read --"] .. " "
      .. GC.Data.DescribeImportError(reason))
  end
end

-- Why a payload would not answer, or nil when it would. Checked on every read, so an import
-- mid-session (SetImported -> adoptRegion) takes the payload out of play at once when it is:
--   "other_region"      -- for another region than the one prices are loaded for;
--   "older_than_import" -- more than PAYLOAD_IMPORT_LAG_SECONDS older than the loaded import of its
--                          region. A Companion that stopped syncing leaves its last payload on disk
--                          and it is adopted again on every load; without this a fresher manual
--                          paste would lose to it, facts and all, until the AppData folder went. Not
--                          a strict "older": the site dates an import string by its newest snapshot,
--                          commodity or realm, and the payload by its commodity snapshot, so within
--                          one sync the import is legitimately up to an hour newer.
local function inactiveReason(p)
  if p.region ~= region then return "other_region" end
  local imp = db and db.imported
  if imp and imp.ts and imp.ts - p.ts > PAYLOAD_IMPORT_LAG_SECONDS then return "older_than_import" end
  return nil
end

local function activePayload()
  if payload and not inactiveReason(payload) then return payload end
  return nil
end

-- A payload that stops answering mid-session -- the import just loaded is another region's, or its
-- region's and more than PAYLOAD_IMPORT_LAG_SECONDS newer -- is let go there and then, as one that
-- could not answer at load is (AdoptRegionPayload). Held, it would be megabytes kept for nothing, and
-- it would come back into play the moment the loaded import changed back: an older paste of its
-- region, or its region's prices pasted again after another region's. Only the next load's payload
-- answers after this.
function dropIdlePayload()
  local why = payload and inactiveReason(payload)
  if why then
    payloadFailure = { reason = why, ts = payload.ts, region = payload.region }
    payload, factIds = nil, nil
  end
end

function GC.Data.RegionPayload()
  return activePayload()
end

--- Why there is no whole-market data, for /goldcap status: { reason, ts } -- the reason the last
-- payload offered could not be used (a parser code, "bad_ts", or one of inactiveReason's), and its
-- date when it got as far as having one -- or nil when a payload is answering or none was offered.
-- One set aside for the prices loaded at the time is judged again against the prices loaded now:
-- the player may have pasted since, and a cause that no longer holds sends them after the wrong
-- thing. When none does, it is "set_aside" -- only the next load reads the payload again.
function GC.Data.RegionPayloadStatus()
  local reason, ts
  if payload then
    reason, ts = inactiveReason(payload), payload.ts
  elseif payloadFailure then
    reason, ts = payloadFailure.reason, payloadFailure.ts
    if payloadFailure.region then reason = inactiveReason(payloadFailure) or "set_aside" end
  end
  if not reason then return nil end
  return { reason = reason, ts = ts }
end

local function refusePayload(reason, ts, payloadRegion)
  payloadFailure = { reason = reason, ts = ts, region = payloadRegion }
  return nil, reason
end

--- Parses the Companion's GCM1 payload into memory, replacing whatever was held. A payload that
-- cannot be used leaves nothing held -- the import string and the bundled table then answer
-- exactly as they did before the payload existed -- and its reason is kept for
-- RegionPayloadStatus. Returns the payload, or nil and that reason.
function GC.Data.AdoptRegionPayload(str)
  payload, payloadFailure, factIds = nil, nil, nil
  if type(str) ~= "string" then return refusePayload("empty") end
  local parsed, reason = GC.ImportString.ParseRegion(str)
  if not parsed then return refusePayload(reason) end
  -- An item the payload prices without a fact takes the payload's date as its own (GetItemValue),
  -- so a date of 0, or one ahead of the clock by more than skew, would make those items look fresh
  -- for as long as the payload stays loaded.
  if parsed.ts <= 0 or parsed.ts > time() + PAYLOAD_FUTURE_SLACK_SECONDS then
    return refusePayload("bad_ts", parsed.ts)
  end
  -- One that would not answer now is not held either: megabytes kept all session for nothing, and
  -- another region's would quietly come back into play if the player later pasted that region's
  -- prices by hand. The import string is adopted first (AdoptAppData), so this is judged against
  -- the region and the import this load settled on.
  local idle = inactiveReason(parsed)
  if idle then return refusePayload(idle, parsed.ts, parsed.region) end
  payload = parsed
  return parsed
end

local function copyTree(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and copyTree(v) or v end
  return c
end

--- What the active payload keeps in memory, in KB, or nil when there is none. Measured the first
-- time the status command asks and never at load: a full collection walks every addon's heap, a
-- hitch nobody should pay on each login for a figure they may never read. One collection, then
-- the payload's tables are built again and the heap growth read off -- a copy allocates exactly
-- the tables the payload holds and no garbage, so after the collection nothing else moves the
-- count. A plain count around the parse would add the parse's garbage, half as much again.
function GC.Data.RegionPayloadMemoryKB()
  local p = activePayload()
  if not p then return nil end
  if not p.memoryKB then
    collectgarbage("collect")
    local before = collectgarbage("count")
    -- The copy is dropped on return, but nothing allocates between that and the count, so no
    -- collection step runs in between to take any of it back.
    copyTree(p)
    p.memoryKB = math.max(0, math.floor(collectgarbage("count") - before))
  end
  return p.memoryKB
end

-- Whether the import answers for an item the payload prices (final review M4, e2e m4): it carries a
-- fact for the item, and the payload either carries none -- V covers only what sold in the last day,
-- while the import's busiest items all carry one -- or is older than the import. Anything else about
-- the item is the payload's, as the whole payload yields to the import only per inactiveReason.
local function importOutranks(p, itemID)
  local imp = db and db.imported
  if not (imp and imp.items and imp.items[itemID] and imp.verification and imp.verification[itemID]) then
    return false
  end
  return p.verification[itemID] == nil or (imp.ts or 0) > p.ts
end

-- The payload when it answers for this item, or nil: it prices the item and the import does not
-- outrank it. The one precedence GetItemValue, Facts and FactItemIds all read.
local function payloadFor(itemID)
  local p = activePayload()
  if p and p.items[itemID] and not importOutranks(p, itemID) then return p end
  return nil
end

--- The one answer to "which facts does item X have". The payload's, for every item the payload
-- answers for (payloadFor) -- even when it has none for it (nothing sold in a day) -- and the
-- import's for everything else.
function GC.Data.Facts(itemID)
  local p = payloadFor(itemID)
  if p then return p.verification[itemID] end
  local imp = db and db.imported
  return imp and imp.verification and imp.verification[itemID] or nil
end

-- The ids anything holds facts for, ascending -- exactly the items Facts answers for: the payload's
-- for items it answers for (payloadFor), plus the import's for every other item. Memoized on the
-- identity of both sources -- the sniper's empty state asks four times a second, and each source is
-- replaced wholesale, never edited in place -- so an unchanged answer is the SAME table, which is
-- what the caller's own memo keys on. Shared, so a caller reads it and never edits it.
function GC.Data.FactItemIds()
  local p = activePayload()
  local imp = db and db.imported
  local imported = imp and imp.verification or nil
  if factIds and factIds.payload == p and factIds.imp == imp and factIds.imported == imported then
    return factIds.ids
  end
  local ids = {}
  if p then
    -- Only for items it answers for: a fact whose I token did not survive, or one the import
    -- outranks, is not the one Facts answers with, and the import's would be listed a second time.
    for id in pairs(p.verification) do
      if payloadFor(id) then ids[#ids + 1] = id end
    end
  end
  if imported then
    for id in pairs(imported) do
      if not payloadFor(id) then ids[#ids + 1] = id end
    end
  end
  table.sort(ids)
  factIds = { payload = p, imp = imp, imported = imported, ids = ids }
  return ids
end

-- Companion sync (companion-v1 plan, Task A): a separate `GoldCap_AppData` addon --
-- see the .toc's OptionalDeps, which loads it before this one when present -- sets
-- `GoldCap_AppData = { importString = "GCS1;...", writtenAt = <unix ts> }` (a current Companion
-- adds `regionString = "GCM1;..."`, see AdoptRegionPayload). This runs the import
-- string through the SAME ImportString.Parse manual import uses (one parser, one validation
-- path) and only adopts it over whatever's already in db.imported when strictly newer --
-- ts equality is a no-op, not churn, same "freshest wins" rule manual import follows. An
-- absent global is a silent no-op -- the companion is optional and never required for the
-- addon to work standalone -- while a global that is THERE and unusable is recorded and
-- said once a session (recordAppDataError above). GC.Print is guarded
-- because it's only defined once Core/Init.lua has loaded (true by the time this runs for
-- real, at ADDON_LOADED -- see Init.lua -- but not in specs that load Data.lua on its own).
local function adoptImportString(appData)
  -- No GoldCap_AppData at all is the normal standalone case (see AdoptAppData). A GoldCap_AppData
  -- that IS there and carries no string is a different thing: the companion ran and wrote
  -- something unusable, which is exactly the state the player needs told.
  if type(appData.importString) ~= "string" then
    recordAppDataError("empty", type(appData.writtenAt) == "number" and appData.writtenAt or nil)
    return
  end

  local parsed, reason = GC.ImportString.Parse(appData.importString)
  if not parsed then
    recordAppDataError(reason, type(appData.writtenAt) == "number" and appData.writtenAt or nil)
    return
  end
  if db then db.appDataError = nil end
  warnedAppDataError = nil

  local existing = db and db.imported
  if existing and parsed.ts <= existing.ts then return end

  GC.Data.SetImported(parsed)
  -- Guarded like every other entry point here: SetImported stores nothing without a db, so
  -- stamping the origin on it would be an error rather than a no-op.
  if not (db and db.imported) then return end
  db.imported.origin = "app"

  local age = time() - parsed.ts
  if age < 0 then age = 0 end -- clock skew must never show a negative age, see importAgeSeconds
  if GC.Print then
    GC.Print(GC.L["auto-synced data for %s loaded (%s old)"]:format(parsed.realm, GC.Util.FormatAge(age)))
  end
end

function GC.Data.AdoptAppData()
  local appData = _G.GoldCap_AppData
  if type(appData) ~= "table" then return end
  adoptImportString(appData)
  -- The whole-market payload, when the Companion wrote one. After the import string, so the region
  -- it is checked against is the one this load settled on; on every load, whether or not the
  -- import string was newer, because the payload is never saved; and dropped from the global once
  -- parsed -- the raw string is a megabyte the parsed tables already hold.
  if appData.regionString ~= nil then
    GC.Data.AdoptRegionPayload(appData.regionString)
    appData.regionString = nil
  end
end

-- The verification fact's fields on a value table: one copy of the list for the two answers that
-- carry facts (the payload's and the import's).
local function withFacts(value, fact)
  value.sourceAt = fact.sourceAt
  value.estimated = fact.flags % 2 == 1
  value.stressUnit = fact.stressUnit
  value.sellThroughBps = fact.sellThroughBps
  value.liquidityConfidence = fact.liquidityConfidence
  value.currentQty = fact.currentQty
  value.listings = fact.listings
  value.observations = fact.observations
  value.madBps = fact.madBps
  return value
end

function GC.Data.GetItemValue(itemID)
  -- 1. The region payload (GCM1): every commodity of the region at its latest snapshot, facts
  -- where it sold in the last day, p25 and reach where it has them. Ahead of the import on
  -- purpose: the same snapshot's figures, for every commodity instead of the busiest 400 -- except
  -- an item the import has a fact for that the payload lacks, or a fresher one (payloadFor).
  local p = payloadFor(itemID)
  local pe = p and p.items[itemID]
  if pe then
    local value = { mv = pe.m, sold = pe.s, trend = pe.t, ts = p.ts, source = "region",
      kind = "region_commodity", p25 = p.quarter[itemID], reach = p.reach[itemID] }
    local fact = GC.Data.Facts(itemID)
    if fact then return withFacts(value, fact) end
    -- No fact (nothing sold in a day): still this snapshot's price, so its age is the payload's;
    -- nothing can arm on it -- Trigger.For needs a stressUnit.
    value.sourceAt = p.ts
    return value
  end

  -- 2. The import, as before: realm items, and every commodity the payload does not answer for.
  local imp = db and db.imported
  local e = imp and imp.items and imp.items[itemID]
  -- Region reference for a realm item (import T section): what the item goes for across the
  -- region, and the item level that price was measured on. Import-path only, like p25 and
  -- reach, and independent of the I section -- the region can know a reference for an item
  -- this realm has no median for at all, which is the case the branch below exists for.
  local target = imp and imp.targets and imp.targets[itemID] or nil
  if e then
    -- Cheap-quarter line (import Q section) and reach24 (import R section): the Sell tab's
    -- ceilings for posting above the cheapest ask, R first. Import-path only -- bundled data
    -- carries neither. trend is import-path only too: bundled entries never carry a `t`.
    local p25 = imp.quarter and imp.quarter[itemID] or nil
    local reach = imp.reach and imp.reach[itemID] or nil
    local fact = GC.Data.Facts(itemID)
    if fact then
      return withFacts({ mv = e.m, sold = e.s, trend = e.t, ts = imp.ts, source = "import",
        kind = "region_commodity", p25 = p25, reach = reach }, fact)
    end
    return { mv = e.m, sold = e.s, trend = e.t, ts = imp.ts, source = "import", kind = "realm_item",
      p25 = p25, reach = reach,
      ref = target and target.ref or nil, refIlvl = target and target.ilvl or nil }
  end

  -- 3. No I entry, but the region named a reference: a realm item this realm has no median for.
  -- There is no mv to return and nothing pretends there is -- GC.Trigger.RealmReference takes
  -- whichever of the two exists, and everything that needs an mv (DealMath, the commodity
  -- decision path) already refuses a value table without one.
  if target then
    return { ts = imp.ts, source = "import", kind = "realm_item",
      ref = target.ref, refIlvl = target.ilvl }
  end

  -- 4. The payload's realm-item reference (M): the region median the bundled table would have
  -- answered with, from this hour instead of release day. Tooltip role only -- a realm item with
  -- no `ref` is never a deal (Core/DealMath.lua), and _RealmValue reads imports alone.
  p = activePayload()
  local ref = p and p.refs[itemID]
  if ref then
    return { mv = ref.m, listings = ref.l, ts = p.ts, source = "region", kind = "realm_item" }
  end

  -- 5. Bundled, as before.
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
  local p = activePayload()
  return {
    region = region,
    bundledTs = bundled and bundled.ts or nil,
    bundledCount = countItems(bundled and bundled.items),
    importedTs = imp and imp.ts or nil,
    importedRealm = imp and imp.realm or nil,
    importedCount = countItems(imp and imp.items),
    importedOrigin = imp and imp.origin or nil,
    -- The whole-market payload while one answers. memoryKB only once RegionPayloadMemoryKB has
    -- measured it: that is a full collection, and the ledger falls back to this function.
    payload = p and { items = p.counts.items, facts = p.counts.facts, refs = p.counts.refs,
      ts = p.ts, memoryKB = p.memoryKB } or nil,
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

  -- Asked for nothing, answer nothing -- before sorting every item in the import to throw
  -- the whole sorted list away one entry at a time.
  local cap = math.max(fallbackN or 100, 0)
  if cap == 0 then return {} end

  local ids = {}
  for id in pairs(imp.items or {}) do ids[#ids + 1] = id end
  -- Tiebreak by id so the top-N boundary is stable across sessions.
  table.sort(ids, function(a, b)
    local ma, mb = imp.items[a].m, imp.items[b].m
    if ma == mb then return a < b end
    return ma > mb
  end)
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

-- The regions this addon understands, from the one list that defines them
-- (Core/ImportString.lua's REGIONS: us/eu/kr/tw). Both upload paths below scope their rows
-- by region and both have to accept every region a client can actually be in -- the live
-- observation path took "us" or "eu" only, written before kr and tw existed here, so a
-- Korean or Taiwanese player scanned the auction house and every fact they saw was dropped
-- on the floor without a word.
local function knownRegion(value)
  return GC.ImportString ~= nil and GC.ImportString.REGIONS ~= nil and GC.ImportString.REGIONS[value] == true
end

function GC.Data.RecordLiveObservation(database, observation, now)
  if type(database) ~= "table" or type(observation) ~= "table" then return nil end
  if database.liveObservations == nil then database.liveObservations = {} end
  if type(database.liveObservations) ~= "table" then return nil end
  if not isPositiveInteger(now) or not isPositiveInteger(observation.itemID)
      or not isPositiveInteger(observation.minUnit)
      or not knownRegion(observation.region) then return nil end
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

-- "Name-Realm", both halves non-empty -- guards the per-character scoping the upsert below
-- and MarkOwnedLotCancelled rely on.
--
-- The realm half may contain hyphens of its own, and it usually does where it matters:
-- GC.Ledger.Context builds this string as UnitName .. "-" .. GetRealmName(), and
-- GetRealmName keeps the realm's own punctuation ("Azjol-Nerub", "Khaz'goroth"). Requiring
-- a SINGLE hyphen therefore rejected every character on a hyphenated realm, so their lots
-- were never recorded and never reached the My auctions page -- silently, since an invalid
-- scope simply returns nil.
local function validCharScope(value)
  return type(value) == "string" and value:match("^[^-]+%-.+$") ~= nil
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
