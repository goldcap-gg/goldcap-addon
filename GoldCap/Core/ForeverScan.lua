local _, GC = ...

-- WoW: Forever's own market scan. Nobody publishes Forever prices yet, so GoldCap reads the
-- auction house itself and keeps the latest fold (Core/ForeverFold.lua) in
-- GoldCapDB.foreverScan, with a passport the companion and the site key the market by.
--
-- What the beta showed (owner, build 1.60.1.70009): ReplicateItems answered 1024 rows by +2 s,
-- still 1024 at +5 s, none at +10 s; a second request after a /reload inside ~15 minutes
-- answered nothing. So:
--   * the dump is read at the FIRST rows -- REPLICATE_ITEM_LIST_UPDATE or a poll, whichever comes
--     first -- and the first batch inside that very call; it is never polled for later;
--   * a dump that empties under the read keeps what was read, marked partial;
--   * the last request time lives in SavedVariables and a spent throttle is never asked again --
--     somebody else's dump (Auctionator, /gc forever) is folded instead, and stamps the clock;
--   * every scan ends with one browse pass (Core/BookPass.lua, through UI/SniperFrame.lua's
--     GC.Sniper.StartBrowsePass): "classes" after a full dump, in case commodities are not in it,
--     "wide" after a capped, empty or refused one. Browse rows fill only items the dump lacked.
-- Pure over an injected driver (see New); the real one is built in this file's realDriver.
GC.ForeverScan = GC.ForeverScan or {}

local C = {
  COOLDOWN_SECONDS = 15 * 60 + 30, -- the account-wide throttle, plus slack for clock drift
  POLL_SECONDS = 0.5,
  WAIT_SECONDS = 8,                -- rows came by +2 s and were gone by +10 s
  READ_BATCH = 2000,               -- rows per frame; 59k rows read in well under the dump's life
  SUSPECT_CAP = 1024,              -- a dump of exactly this many rows reads as a page, not the AH
  BROWSE_WAIT_SECONDS = 180,       -- a wide pass on a busy auction house, behind the arbiter
}
GC.ForeverScan.C = C

function GC.ForeverScan.New(driver)
  local obj = {}
  local state = "idle" -- idle | waiting | reading | browsing
  local token = 0
  local ahOpen = false
  local acc, total, readIndex

  local function reset()
    state, acc, total, readIndex = "idle", nil, nil, nil
    token = token + 1
  end

  -- The rule (final review I3): a browse-only result never REPLACES a stored fold that came
  -- from a real ReplicateItems dump -- only the cooldown-SCAN path (Request, "button" reason,
  -- inside C.COOLDOWN_SECONDS) and a browse watchdog firing on that same empty accumulator ever
  -- produce one, and either would otherwise throw away every ladder/lot-count the dump priced
  -- for the single cheapest-listing floor a browse row carries. So: merge. Every item the stored
  -- fold already has stays exactly as it was folded; a browse item is added only for an item the
  -- stored fold lacks entirely -- the same "only what the dump didn't cover" rule AddBrowse
  -- already applies inside one scan, now applied across two.
  local function isFullFold(fold)
    return type(fold) == "table" and type(fold.items) == "table"
      and (fold.source == "replicate" or fold.source == "replicate+browse")
  end

  -- Final review N1 (plan 3b): a fold is one auction house's. A browse-only result tops up the
  -- saved one only when both are of the same region, realm, faction and ruleset -- otherwise a
  -- SCAN on another realm inside the 15-minute window carried the first realm's prices over.
  local function sameHouse(fold, p)
    return fold.region == p.region and fold.realm == p.realm and fold.faction == p.faction
      and fold.ruleset == p.ruleset
  end

  local function commit()
    local a = acc
    reset()
    if not a or next(a.items) == nil then
      driver.notify("done", nil)
      return
    end
    local items, count = GC.ForeverFold.Freeze(a, driver.isGear)
    local p = driver.passport() or {}
    local source = a.replicated and (a.browsed and "replicate+browse" or "replicate") or "browse"
    local s = driver.store()
    if s then
      local existing = s.fold
      if source == "browse" and isFullFold(existing) and sameHouse(existing, p) then
        local merged, mergedCount = {}, 0
        for itemID, encoded in pairs(existing.items) do
          merged[itemID] = encoded
          mergedCount = mergedCount + 1
        end
        for itemID, encoded in pairs(items) do
          if merged[itemID] == nil then
            merged[itemID] = encoded
            mergedCount = mergedCount + 1
          end
        end
        -- Honest source/age (final review I3): still fundamentally the dump's own fold -- its
        -- `rows` (a raw-row count only a real dump produces) is unchanged -- just topped up with
        -- a few more items' floors, which is exactly what `partial` is for elsewhere in this file.
        s.fold = { v = GC.ForeverFold.VERSION, interface = p.interface, build = p.build, region = p.region,
          realm = p.realm, faction = p.faction, ruleset = p.ruleset, at = driver.now(),
          source = existing.source, rows = existing.rows, itemCount = mergedCount, partial = true,
          items = merged }
      else
        s.fold = { v = GC.ForeverFold.VERSION, interface = p.interface, build = p.build, region = p.region,
          realm = p.realm, faction = p.faction, ruleset = p.ruleset, at = driver.now(), source = source,
          rows = a.replicated and a.rows or nil, itemCount = count, partial = a.partial or nil,
          items = items }
      end
    end
    driver.notify("done", { rows = a.replicated and a.rows or nil, items = count,
      partial = a.partial == true, replicated = a.replicated == true, pending = a.pending,
      skipped = a.skipped })
  end

  local function toBrowse(kind)
    local answer = driver.startBrowse(kind)
    if answer ~= "started" and answer ~= "running" then return false end
    state = "browsing"
    token = token + 1
    local t = token
    driver.after(C.BROWSE_WAIT_SECONDS, function()
      if token == t and state == "browsing" then
        acc.partial = true
        commit()
      end
    end)
    return true
  end

  local function afterRead()
    if acc.dumpRows == C.SUSPECT_CAP then acc.partial = true end
    if not toBrowse(acc.partial and "wide" or "classes") then commit() end
  end

  local readBatch
  readBatch = function(t)
    if token ~= t or state ~= "reading" then return end
    local now = driver.numRows() or 0
    if now < total then
      acc.partial = true
      total = now
    end
    if readIndex < total then
      local last = math.min(readIndex + C.READ_BATCH, total) - 1
      for i = readIndex, last do
        GC.ForeverFold.AddRow(acc, driver.rowInfo(i))
      end
      readIndex = last + 1
      driver.notify("progress", readIndex, total)
    end
    if readIndex < total then
      driver.after(0, function() readBatch(t) end)
      return
    end
    afterRead()
  end

  local function beginRead()
    local n = driver.numRows()
    if type(n) ~= "number" or n <= 0 then return false end
    acc = acc or GC.ForeverFold.New()
    acc.dumpRows = n
    acc.replicated = true
    state, total, readIndex = "reading", n, 0
    token = token + 1
    readBatch(token)
    return true
  end

  local function noAnswer()
    driver.notify("noanswer")
    acc.partial = true
    if not toBrowse("wide") then
      reset()
      driver.notify("done", nil)
    end
  end

  local function poll(t, waited)
    if token ~= t or state ~= "waiting" then return end
    if beginRead() then return end
    if waited >= C.WAIT_SECONDS then noAnswer(); return end
    driver.after(C.POLL_SECONDS, function() poll(t, waited + C.POLL_SECONDS) end)
  end

  function obj:Request(reason)
    if state ~= "idle" then return "busy" end
    if not ahOpen then
      if reason == "button" then driver.notify("closed") end
      return "closed"
    end
    local s = driver.store() or {}
    local now = driver.now()
    local since = type(s.requestedAt) == "number" and now - s.requestedAt or math.huge
    -- A stamp from the future is a clock that stepped back, not a throttle.
    if since < 0 then since = math.huge end
    if since < C.COOLDOWN_SECONDS then
      if reason ~= "button" then return "cooldown" end
      driver.notify("cooldown", math.ceil((C.COOLDOWN_SECONDS - since) / 60))
      acc = GC.ForeverFold.New()
      if not toBrowse("wide") then acc = nil end
      return "cooldown"
    end
    s.requestedAt = now
    acc = GC.ForeverFold.New()
    driver.notify("started")
    if not driver.replicate() then
      noAnswer()
      return "failed"
    end
    state = "waiting"
    token = token + 1
    local t = token
    driver.after(C.POLL_SECONDS, function() poll(t, C.POLL_SECONDS) end)
    return "started"
  end

  function obj:OnReplicateUpdate()
    if state == "waiting" then beginRead(); return end
    if state ~= "idle" or not ahOpen then return end
    -- Somebody else's full scan (another addon, /gc forever): the account's throttle is spent
    -- either way, so the dump is folded rather than asked for again.
    if (driver.numRows() or 0) <= 0 then return end
    local s = driver.store()
    if s then s.requestedAt = driver.now() end
    acc = GC.ForeverFold.New()
    beginRead()
  end

  function obj:OnBrowsePassDone(book)
    if state ~= "browsing" then return end
    for itemID, row in pairs(type(book) == "table" and book or {}) do
      -- A variant row (gear by item level, a caged pet by species) is one version, not the
      -- item's floor -- the same rule UI/SniperFrame.lua's _LiveRow applies to the tooltip.
      if type(row) == "table" and not row.variants then
        GC.ForeverFold.AddBrowse(acc, itemID, row.floor, row.qty)
      end
    end
    acc.browsed = true
    commit()
  end

  function obj:OnAuctionHouseShow()
    ahOpen = true
    return self:Request("auto")
  end

  function obj:OnAuctionHouseClosed()
    ahOpen = false
    if state == "idle" then return end
    if state == "waiting" then reset(); return end
    acc.partial = true
    commit()
  end

  function obj:IsBusy() return state ~= "idle" end
  function obj:State() return state end
  return obj
end

local function count(n)
  n = math.floor(tonumber(n) or 0)
  if type(_G.BreakUpLargeNumbers) == "function" then return tostring(_G.BreakUpLargeNumbers(n)) end
  return tostring(n)
end

-- What a finished scan tells the player. There is no Forever Companion or upload in this build
-- (final review I1) -- GC.Data.AdoptAppData refuses a retail Companion's GoldCap_AppData table
-- in Forever, and nothing here writes one of its own -- so a scan always stays on this computer,
-- and says so unconditionally, until plan 3c ships the upload. SavedVariables are written on
-- /reload or logout only; "saved" reads that way.
function GC.ForeverScan._SayDone(summary)
  if not summary then
    GC.Print(GC.L["The scan found nothing to save"])
    return
  end
  if summary.replicated then
    GC.Print(GC.L["%s lots scanned and saved"]:format(count(summary.rows)))
  else
    GC.Print(GC.L["%s items scanned and saved"]:format(count(summary.items)))
  end
  -- "your bags: X at a vendor, Y on the AH" after every saved scan (Core/ForeverValue.lua).
  -- Guarded: this file's own _SayDone spec never loads Core/ForeverValue.lua, so GC.ForeverValue
  -- is nil there -- degrade to nothing printed rather than an error.
  if GC.ForeverValue and GC.ForeverValue.PrintBags then GC.ForeverValue.PrintBags() end
end

local function notify(kind, a, b)
  if kind == "started" then
    GC.Print(GC.L["Scanning the auction house…"])
  elseif kind == "closed" then
    GC.Print(GC.L["Open the Auction House first."])
  elseif kind == "cooldown" then
    GC.Print(GC.L["The full scan is cooling down (%d min left) -- scanning by browsing instead"]:format(a))
  elseif kind == "noanswer" then
    GC.Print(GC.L["The auction house did not answer the full scan -- scanning by browsing instead"])
  elseif kind == "progress" then
    if GC.Sniper and GC.Sniper.SetScanStatus then
      GC.Sniper.SetScanStatus(GC.L["reading the auction house: %s of %s lots"]:format(count(a), count(b)))
    end
  elseif kind == "done" then
    GC.ForeverScan._SayDone(a)
    if GC.Sniper and GC.Sniper.OnForeverFold then GC.Sniper.OnForeverFold() end
  end
end

-- The client, for New. Every call is guarded: a missing API reads as "nothing there", never an
-- error inside an event handler.
local function realDriver()
  -- `or {}`: a client without the namespace makes every pcall below answer false, never throw.
  local ah = _G.C_AuctionHouse or {}
  return {
    now = function() return time() end,
    after = function(s, fn) C_Timer.After(s, fn) end,
    replicate = function() return (pcall(ah.ReplicateItems)) end,
    numRows = function()
      local ok, n = pcall(ah.GetNumReplicateItems)
      return ok and tonumber(n) or 0
    end,
    rowInfo = function(i)
      local ok, _, _, count_, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAll =
        pcall(ah.GetReplicateItemInfo, i)
      if not ok then return nil end
      return itemID, count_, buyout, hasAll
    end,
    isGear = function(itemID)
      local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
      return classID == 2 or classID == 4
    end,
    startBrowse = function(kind)
      return GC.Sniper and GC.Sniper.StartBrowsePass and GC.Sniper.StartBrowsePass(kind) or nil
    end,
    store = function() return GC.ForeverScan.Store() end,
    passport = function()
      local p = GC.Game and GC.Game.Passport and GC.Game.Passport() or {}
      local okR, realm = pcall(GetRealmName)
      local okF, faction = pcall(UnitFactionGroup, "player")
      return { interface = p.interface, build = p.build, region = p.regionId,
        realm = okR and type(realm) == "string" and realm ~= "" and realm or nil,
        faction = okF and type(faction) == "string" and faction or nil,
        ruleset = nil } -- no API names the ruleset yet (spec §Facts); nil, never a guess
    end,
    notify = notify,
  }
end

-- Module state: set once per load by Init (Core/Init.lua's ADDON_LOADED). Everything reads it
-- and nothing below writes to the save except the scanner and Store.
function GC.ForeverScan.Init(db, driver)
  driver = driver or realDriver()
  GC.ForeverScan._db = db
  local p = driver and driver.passport and driver.passport() or nil
  local on = p ~= nil and GC.Game ~= nil and GC.Game.IsForever({ interface = p.interface }) or false
  GC.ForeverScan._on = on
  GC.ForeverScan._region = p and p.region or nil
  GC.ForeverScan._realm = p and p.realm or nil
  GC.ForeverScan._faction = p and p.faction or nil
  GC.ForeverScan._ruleset = p and p.ruleset or nil
  -- Kept for Fold: a client that has not settled the realm or faction at ADDON_LOADED answers
  -- nil there, and the fold is only as safe as the house it is compared against.
  GC.ForeverScan._passport = on and driver.passport or nil
  GC.ForeverScan._scanner = on and GC.ForeverScan.New(driver) or nil
  if on and type(db) == "table" and type(db.foreverScan) ~= "table" then db.foreverScan = {} end
  return on
end

function GC.ForeverScan.Enabled() return GC.ForeverScan._on == true end

-- GoldCapDB.foreverScan, created on first use and only in Forever: a retail save never gains
-- the key.
function GC.ForeverScan.Store()
  local db = GC.ForeverScan._db
  if not GC.ForeverScan._on or type(db) ~= "table" then return nil end
  if type(db.foreverScan) ~= "table" then db.foreverScan = {} end
  return db.foreverScan
end

-- The character's realm and faction, read again while the load-time read left one unnamed.
local function settleHouse()
  local F = GC.ForeverScan
  if (F._realm ~= nil and F._faction ~= nil) or not F._passport then return end
  local ok, p = pcall(F._passport)
  if not ok or type(p) ~= "table" then return end
  if F._realm == nil then F._realm = p.realm end
  if F._faction == nil then F._faction = p.faction end
end

-- Both named and different: another auction house. Unnamed on either side is not evidence.
local function differs(saved, current)
  return saved ~= nil and current ~= nil and saved ~= current
end

-- The saved fold, when it is this game's, this region's and -- when both are named -- this
-- realm's, this faction's and this ruleset's: the one auction house Core/ForeverScan.lua's
-- sameHouse tops up. GoldCapDB is account-wide, so without the faction an alt of the other
-- faction on the same realm read the first character's scan as its own market (final review
-- I1, plan 3c). Read-only; nil anywhere else, and always nil on retail.
function GC.ForeverScan.Fold()
  if not GC.ForeverScan._on then return nil end
  local db = GC.ForeverScan._db
  local s = type(db) == "table" and db.foreverScan or nil
  local fold = type(s) == "table" and s.fold or nil
  if type(fold) ~= "table" or type(fold.items) ~= "table" then return nil end
  if fold.region ~= GC.ForeverScan._region then return nil end
  settleHouse()
  if differs(fold.realm, GC.ForeverScan._realm) or differs(fold.faction, GC.ForeverScan._faction)
      or differs(fold.ruleset, GC.ForeverScan._ruleset) then
    return nil
  end
  return fold
end

-- The player's own scan as a GC.Data.GetItemValue answer (Core/Data.lua, its last source), or
-- nil. Reads only: it runs wherever GetItemValue does, the Sell tab's compose included.
function GC.ForeverScan.ValueFor(itemID)
  local fold = GC.ForeverScan.Fold()
  if not fold then return nil end
  local e = GC.ForeverFold.Decode(fold.items[itemID])
  if not e then return nil end
  return { mv = e.value, min = e.min, currentQty = e.qty, listings = e.lots, ts = fold.at,
    source = "scan", kind = "own_scan", gear = e.gear or nil, browse = e.browse or nil }
end

-- For /gc forever (Core/ForeverCheck.lua): plain English, a diagnostic.
function GC.ForeverScan.Summary(now)
  if not GC.ForeverScan._on then return {} end
  local db = GC.ForeverScan._db
  local s = type(db) == "table" and db.foreverScan or nil
  local lines = {}
  local at = type(s) == "table" and s.requestedAt or nil
  lines[#lines + 1] = "own scan: last full-scan request "
    .. (type(at) == "number" and ((now - at) .. "s ago") or "never")
  local f = type(s) == "table" and s.fold or nil
  if type(f) == "table" then
    lines[#lines + 1] = ("own scan: last fold %s, %s rows, %d items%s, %ds old (region %s, realm %s, faction %s)")
      :format(tostring(f.source), tostring(f.rows or "-"), f.itemCount or 0, f.partial and ", partial" or "",
        now - (f.at or now), tostring(f.region), tostring(f.realm), tostring(f.faction))
  else
    lines[#lines + 1] = "own scan: no fold saved yet"
  end
  local scanner = GC.ForeverScan._scanner
  lines[#lines + 1] = "own scan: scanner " .. (scanner and scanner:State() or "off")
  return lines
end

-- The first time GoldCap loads in WoW: Forever on this account (spec §3 "First run in Forever"):
-- where prices come from, how to scan, and what the Companion adds. Once, ever.
function GC.ForeverScan.MaybeIntro()
  local s = GC.ForeverScan.Store()
  if not s or s.introShown then return false end
  s.introShown = true
  GC.Print(GC.L["In WoW: Forever, GoldCap's prices come from your own auction house scans."])
  GC.Print(GC.L["Open the auction house and GoldCap scans it for you; SCAN on the Deals tab scans again."])
  GC.Print(GC.L["Your scans stay on this computer for now; sharing them through the GoldCap Companion is on the way."])
  return true
end

local function scanner() return GC.ForeverScan._scanner end
function GC.ForeverScan.Request(reason) local s = scanner(); return s and s:Request(reason) or nil end
function GC.ForeverScan.OnReplicateUpdate() local s = scanner(); if s then s:OnReplicateUpdate() end end
function GC.ForeverScan.OnBrowsePassDone(book) local s = scanner(); if s then s:OnBrowsePassDone(book) end end
function GC.ForeverScan.OnAuctionHouseShow() local s = scanner(); return s and s:OnAuctionHouseShow() or nil end
function GC.ForeverScan.OnAuctionHouseClosed() local s = scanner(); if s then s:OnAuctionHouseClosed() end end
function GC.ForeverScan.IsBusy() local s = scanner(); return s ~= nil and s:IsBusy() end
