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
  READ_BATCH = 2000,               -- rows per frame at most; 59k rows read in well under the dump's life
  -- Owner, 2026-09-27: the game froze reading a ~72k-row dump while Auctionator read it too. Plan
  -- 3e added a link read and parse to every gear row, which put a 2000-row frame at three times
  -- its old Lua cost. A frame now stops at READ_BUDGET_MS of its own work (driver.clock, the
  -- client's debugprofilestop), links included, and always reads at least READ_MIN_ROWS so a slow
  -- frame still moves the read forward.
  READ_BUDGET_MS = 8,
  READ_MIN_ROWS = 100,
  READ_CLOCK_EVERY = 50,           -- rows between clock reads
  -- The dump arrives in pages of this many rows. A read that ends on a page boundary stopped
  -- early: the beta showed 1024, then 2048 of ~66k rows. A whole auction house lands on an exact
  -- multiple about once in a thousand scans.
  SUSPECT_CAP = 1024,
  BROWSE_WAIT_SECONDS = 180,       -- a wide pass on a busy auction house, behind the arbiter
  -- A partial replicate read merges into the saved fold (below) only while the saved fold is no
  -- older than this: otherwise every item they share would keep the OLD fold's price forever, as
  -- long as every later read happens to come back partial too. Past this, a partial read replaces
  -- the stale fold wholesale, same as a non-partial one already does.
  MERGE_MAX_AGE_SECONDS = 2 * 3600,
  -- How many of this account's own fold stamps are remembered (rememberAt below).
  KEEP_FOLD_ATS = 8,
}
GC.ForeverScan.C = C

-- GoldCapDB.foreverScan.foldAts: the `at` of the last few folds THIS account saved, oldest first.
-- One Companion install can hold two WoW accounts and each has its own GoldCapDB, but the
-- Companion's answer for a scan arrives keyed by the fold's `at` alone: a stamp in this list is how
-- the addon knows a result is for a scan its own account made (SayImpact).
local function rememberAt(s, at)
  if type(at) ~= "number" or at <= 0 then return end
  if type(s.foldAts) ~= "table" then s.foldAts = {} end
  local list = s.foldAts
  for i = 1, #list do
    if list[i] == at then return end
  end
  list[#list + 1] = at
  while #list > C.KEEP_FOLD_ATS do table.remove(list, 1) end
end

function GC.ForeverScan.New(driver)
  local obj = {}
  local state = "idle" -- idle | waiting | reading | browsing
  local token = 0
  local ahOpen = false
  local acc, total, readIndex
  -- The dump this scanner last read: its row count and when. The client can fire
  -- REPLICATE_ITEM_LIST_UPDATE again for a dump already read (another addon's request inside the
  -- account throttle, or item data arriving), and an idle scanner used to read all ~72k rows over
  -- again for it (owner, beta 2026-09-27). One read per dump: see OnReplicateUpdate.
  local lastRead

  local function reset()
    state, acc, total, readIndex = "idle", nil, nil, nil
    token = token + 1
  end

  -- The rule (final review I3, widened for the partial-replicate case): neither a browse-only
  -- result nor a ReplicateItems read that came back partial itself (the dump capped at
  -- SUSPECT_CAP, emptied under the read, or the browse watchdog firing) may REPLACE a stored fold
  -- that came from a real dump -- either would otherwise throw away every ladder/lot-count the
  -- fuller fold priced for a thinner read's single floor. So: merge. Every item the stored fold
  -- already has keeps its saved entry, UNLESS the saved fold was itself partial and this read is
  -- a real dump -- both reads are then incomplete, and this read's entry, the newer one, wins. An
  -- item the stored fold lacks entirely is added -- the same "only what the dump didn't cover"
  -- rule AddBrowse already applies inside one scan, now applied across two.
  --
  -- Age-gated for the partial-replicate case only (C.MERGE_MAX_AGE_SECONDS): a browse-only top-up
  -- always merges, as it always has, but a saved fold already older than the window is replaced
  -- rather than topped up again -- otherwise a player whose dumps keep coming back capped would
  -- keep every shared item at whatever price the very first dump saw, forever.
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

  -- A dump read that stopped early (a page boundary, emptied under the read, the auction house
  -- closed mid-read) saw only some lots of every item it reached: each such item's minimum is too
  -- high and its counts too low -- Linen Cloth at 2g from one of 201 lots, when the floor was 64c.
  -- Those entries go; the browse pass prices every item whole instead, and an item it does not
  -- reach keeps what the saved fold says.
  local function dropCutDump(a)
    if not a.cut then return end
    for itemID, e in pairs(a.items) do
      if not e.browse then a.items[itemID] = nil end
    end
  end

  local function commit()
    local a = acc
    reset()
    if a then dropCutDump(a) end
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
      local mergeableAge = type(existing) == "table" and type(existing.at) == "number"
        and (driver.now() - existing.at) <= C.MERGE_MAX_AGE_SECONDS
      if (source == "browse" or (a.partial and mergeableAge)) and isFullFold(existing) and sameHouse(existing, p) then
        -- Both reads incomplete: this attempt's entry is the newer one, so it wins over the
        -- saved fold's for any item they both priced.
        local overwrite = existing.partial == true and a.replicated == true
        local merged, mergedCount = {}, 0
        for itemID, encoded in pairs(existing.items) do
          merged[itemID] = encoded
          mergedCount = mergedCount + 1
        end
        for itemID, encoded in pairs(items) do
          if merged[itemID] == nil then
            merged[itemID] = encoded
            mergedCount = mergedCount + 1
          elseif overwrite then
            merged[itemID] = encoded
          end
        end
        -- Honest source/age (final review I3, re-review I2b): still fundamentally the dump's own
        -- fold -- its `rows` (a raw-row count only a real dump produces) is unchanged -- just
        -- topped up with a few more items' floors, which is exactly what `partial` is for
        -- elsewhere in this file. `at` follows the same rule: it stays the DUMP's own stamp, not
        -- driver.now(). The dump is still most of what this fold prices, so restamping it to "now"
        -- on every top-up would tell the companion (and the site's "N minutes ago") that a lot
        -- read hours ago was read this instant. Only a browse item added THIS merge is actually
        -- that fresh, and this fold format has no per-item timestamp to say so -- so `at` reports
        -- the oldest, honest bound rather than the newest, false one. (The account-wide request
        -- throttle is a separate stamp -- `s.requestedAt`, set in Request/OnReplicateUpdate -- and
        -- keeps ticking off driver.now() exactly as before; nothing here touches it.)
        s.fold = { v = GC.ForeverFold.VERSION, interface = p.interface, build = p.build, region = p.region,
          realm = p.realm, faction = p.faction, ruleset = p.ruleset, at = existing.at,
          source = existing.source, rows = existing.rows, itemCount = mergedCount, partial = true,
          items = merged }
        -- Plan 3e: the gear lots came from the very dump the merged fold keeps; they follow its stamp.
        if type(s.gear) == "table" then s.gear.at = s.fold.at end
      else
        s.fold = { v = GC.ForeverFold.VERSION, interface = p.interface, build = p.build, region = p.region,
          realm = p.realm, faction = p.faction, ruleset = p.ruleset, at = driver.now(), source = source,
          rows = a.replicated and a.rows or nil, itemCount = count, partial = a.partial or nil,
          items = items }
        -- A new stamp: the one the Companion will answer for. The merge above keeps the old `at`,
        -- which is already remembered.
        rememberAt(s, s.fold.at)
        -- Plan 3e: the gear lots of this dump, or none (a browse-only scan has no links).
        s.gear = a.gear and GC.ForeverGear.Freeze(a.gear, s.fold.at) or nil
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
    if acc.dumpRows % C.SUSPECT_CAP == 0 then acc.partial, acc.cut = true, true end
    if not toBrowse(acc.partial and "wide" or "classes") then commit() end
  end

  -- driver.isGearLot once per item id per scan: tens of thousands of rows share a few thousand
  -- ids. Falls back to driver.isGear for a driver that only offers that (M6, final review, is a
  -- narrower question than the fold's own "g" flag, so it is its own driver field).
  local function isGearRow(itemID)
    if type(itemID) ~= "number" then return false end
    local known = acc.gearIds[itemID]
    if known == nil then
      local ok, g = pcall(driver.isGearLot or driver.isGear, itemID)
      known = ok and g == true
      acc.gearIds[itemID] = known
    end
    return known
  end

  local readBatch
  readBatch = function(t)
    if token ~= t or state ~= "reading" then return end
    local now = driver.numRows() or 0
    if now < total then
      acc.partial, acc.cut = true, true
      total = now
      lastRead.rows = now
    end
    if readIndex < total then
      local last = math.min(readIndex + C.READ_BATCH, total) - 1
      local clock = driver.clock
      local started = clock and clock() or nil
      local i = readIndex
      while i <= last do
        local itemID, count, buyout, hasAll = driver.rowInfo(i)
        GC.ForeverFold.AddRow(acc, itemID, count, buyout, hasAll)
        -- Plan 3e: a gear row's link, for the Upgrade Finder (Core/ForeverGear.lua). Beside the
        -- fold, never in it.
        if acc.gear and isGearRow(itemID) then
          GC.ForeverGear.AddRow(acc.gear, itemID, count, buyout, driver.rowLink(i))
        end
        i = i + 1
        local done = i - readIndex
        if started and done >= C.READ_MIN_ROWS and done % C.READ_CLOCK_EVERY == 0
            and clock() - started >= C.READ_BUDGET_MS then
          break
        end
      end
      readIndex = i
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
    -- Only with a driver that reads links (the real one does); the fold is folded as before.
    if GC.ForeverGear and driver.rowLink and not acc.gear then
      acc.gear, acc.gearIds = GC.ForeverGear.New(), {}
    end
    acc.dumpRows = n
    acc.replicated = true
    lastRead = { rows = n, at = driver.now() }
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
    local n = driver.numRows() or 0
    if n <= 0 then return end
    -- The same dump again: the same row count inside the throttle window, which no new dump can
    -- beat. A different count, or a later event, is a dump this scanner has not read.
    if lastRead and n == lastRead.rows and driver.now() - lastRead.at < C.COOLDOWN_SECONDS then return end
    local s = driver.store()
    if s then s.requestedAt = driver.now() end
    acc = GC.ForeverFold.New()
    beginRead()
  end

  function obj:OnBrowsePassDone(book)
    if state ~= "browsing" then return end
    dropCutDump(acc)
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
    if state == "reading" then acc.cut = true end
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

-- What a finished scan tells the player. SavedVariables are written on /reload or logout only, so
-- "saved" reads that way. "Shared" is said only while a Companion paired with goldcap.gg writes
-- this install (GC.Data.CompanionShares): it uploads the saved scan after the next /reload
-- (plan 3d decision E12). Without one the scan stays on this computer and nothing claims otherwise.
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
  -- Plan 3e: how many upgrades the scan holds for this character's gear, when there are any --
  -- queued rather than called here (see _QueueUpgradesUpdate below): Core/ForeverUpgrades.lua's
  -- Build is a synchronous, potentially ~140-tooltip-read walk, and this line runs on the very
  -- frame that just froze the fold and refreshed Sniper.
  GC.ForeverScan._QueueUpgradesUpdate()
  if GC.Data and GC.Data.CompanionShares and GC.Data.CompanionShares() then
    GC.Print(GC.L["Shared with goldcap.gg on your next /reload"])
  end
end

-- Final review (re-review 2026-09-27): PrintCount and RefreshIfShown used to each run their own
-- Core/ForeverUpgrades.lua Build synchronously, right here, on top of the fold freeze, the Sniper
-- refresh and PrintBags already on this frame -- and paid for the tooltip pass (up to ~140
-- C_TooltipInfo.GetHyperlink calls) twice over whenever the upgrades window happened to be open.
-- One Build now, off this frame with C_Timer.After(0, ...) -- the idiom Core/Init.lua's OnTick and
-- UI/AuctionHouseTab.lua's tab-add already use -- feeds both the chat count and, only while the
-- window is actually open, its own render. Closed, there is nothing to render, so Build's own
-- tooltip pass is skipped too (its skipUsable argument): usability then comes only from the class
-- armour/weapon tables and CanDualWield (Core/ForeverUpgrades.lua's ClassAllows/canDualWield), the
-- same fallback a level-ahead pick already trusts.
function GC.ForeverScan._QueueUpgradesUpdate()
  local U = GC.ForeverUpgrades
  if not (U and U.PrintCount and U.Current) then return end
  local timer = _G.C_Timer
  if type(timer) ~= "table" or type(timer.After) ~= "function" then return end
  timer.After(0, function()
    local UI = GC.ForeverUpgradesUI
    local shown = UI ~= nil and UI.IsShown ~= nil and UI.IsShown() == true
    local r = U.Current(not shown)
    U.PrintCount(r)
    if shown and UI.Render then UI.Render(r, time()) end
  end)
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
    -- Milliseconds, for the read's per-frame budget (C.READ_BUDGET_MS).
    clock = type(_G.debugprofilestop) == "function" and _G.debugprofilestop or nil,
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
    -- Plan 3e: the row's link, "if loaded" (warcraft.wiki.gg) -- nil otherwise, never an error.
    rowLink = function(i)
      if type(ah.GetReplicateItemLink) ~= "function" then return nil end
      local ok, link = pcall(ah.GetReplicateItemLink, i)
      return ok and type(link) == "string" and link or nil
    end,
    isGear = function(itemID)
      local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
      return classID == 2 or classID == 4
    end,
    -- Final review M6: this flag above covers every weapon/armor item generically (the fold's "g"
    -- flag); gear LOTS (Core/ForeverGear.lua) are read only for the Upgrade Finder, which never
    -- compares a trinket or a shirt -- their worth is mostly effects GetItemStats does not list.
    -- Excluding them here saves SavedVariables space that would otherwise sit unread.
    isGearLot = function(itemID)
      local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
      if equipLoc == "INVTYPE_TRINKET" or equipLoc == "INVTYPE_BODY" then return false end
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
  -- The fold this save already holds is this account's own scan, whatever build saved it.
  if on and type(db) == "table" and type(db.foreverScan.fold) == "table" then
    rememberAt(db.foreverScan, db.foreverScan.fold.at)
  end
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

-- GoldCapDB.forever: plan 3e's Forever-only preferences and per-character state -- the riding
-- cost, stat weights, the loot opt-out, Road to 40's pace. Created on first use and only in
-- Forever, like Store: a retail save never gains the key.
function GC.ForeverScan.Prefs()
  local db = GC.ForeverScan._db
  if not GC.ForeverScan._on or type(db) ~= "table" then return nil end
  if type(db.forever) ~= "table" then db.forever = {} end
  return db.forever
end

-- The whole save, for a Forever module that keeps a top-level key of its own
-- (Core/ForeverLoot.lua's GoldCapDB.foreverLoot). nil on retail.
function GC.ForeverScan.Root()
  if not GC.ForeverScan._on or type(GC.ForeverScan._db) ~= "table" then return nil end
  return GC.ForeverScan._db
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

-- The gear lots of the saved fold (Core/ForeverGear.lua) and that fold, only while the lots are the
-- very scan Fold() answers with -- same `at` -- so they ride on its region/realm/faction check.
-- nil otherwise, and always on retail.
function GC.ForeverScan.Gear()
  local fold = GC.ForeverScan.Fold()
  if not fold then return nil end
  local s = GC.ForeverScan._db.foreverScan
  local gear = type(s) == "table" and s.gear or nil
  if type(gear) ~= "table" or type(gear.items) ~= "table" or gear.at ~= fold.at then return nil end
  return gear, fold
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
  local g = type(s) == "table" and s.gear or nil
  if type(g) == "table" and type(g.items) == "table" then
    local n = 0
    for _ in pairs(g.items) do n = n + 1 end
    lines[#lines + 1] = ("own scan: gear lots for %d items%s"):format(n,
      (type(f) == "table" and g.at == f.at) and "" or " (from an older scan, not used)")
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
  if GC.Data and GC.Data.CompanionShares and GC.Data.CompanionShares() then
    GC.Print(GC.L["The GoldCap Companion shares your scans with goldcap.gg after each /reload and brings everyone's prices back."])
  else
    GC.Print(GC.L["Your scans stay on this computer. The GoldCap Companion shares them with goldcap.gg and brings everyone's prices back."])
  end
  return true
end

-- What the last scan changed on the market, as the site counted it (the Companion writes it into
-- GoldCap_AppData.foreverImpact, one entry per WoW account it uploaded for; see
-- docs/addon/AGENTS.md). Companion 1.16.0 and later; an older one writes no key and nothing below
-- ever runs. Entry: { at, updated, onlyYours, first?, realm, faction? }, `at` the fold's own stamp.
local function isCount(n)
  return type(n) == "number" and n >= 0 and n % 1 == 0 and n <= 2 ^ 53
end

local function validImpact(e)
  if type(e) ~= "table" then return false end
  if not (isCount(e.at) and e.at > 0) then return false end
  if not (isCount(e.updated) and isCount(e.onlyYours) and e.onlyYours <= e.updated) then return false end
  if e.first ~= nil and type(e.first) ~= "boolean" then return false end
  if type(e.realm) ~= "string" or e.realm == "" then return false end
  -- Characters, not bytes: a Korean realm name is three bytes a letter.
  if select(2, e.realm:gsub("[^\128-\191]", "")) > 64 then return false end
  if e.faction ~= nil and type(e.faction) ~= "string" then return false end
  return true
end

-- Memory only, like the Forever payload: rebuilt from the file on every load. A value that is not
-- a table changes nothing (an old Companion writes no key); one bad entry costs only itself.
function GC.ForeverScan.AdoptImpact(list)
  if type(list) ~= "table" then return end
  local kept = {}
  for _, e in ipairs(list) do
    if validImpact(e) then
      kept[#kept + 1] = { at = e.at, updated = e.updated, onlyYours = e.onlyYours, first = e.first == true,
        realm = e.realm, faction = e.faction ~= "" and e.faction or nil }
    end
  end
  GC.ForeverScan._impacts = kept
end

-- The market as the Companion names it, `realm · faction`, with the client's own word for the
-- faction (FACTION_ALLIANCE / FACTION_HORDE exist in retail and in Forever) and a `|` in a name
-- doubled so chat does not read it as an escape.
local function marketLabel(e)
  local function chat(text) return (text:gsub("|", "||")) end
  local faction = e.faction
  if faction == nil then return chat(e.realm) end
  if faction == "Alliance" and type(_G.FACTION_ALLIANCE) == "string" then faction = _G.FACTION_ALLIANCE end
  if faction == "Horde" and type(_G.FACTION_HORDE) == "string" then faction = _G.FACTION_HORDE end
  return chat(e.realm) .. " · " .. chat(faction)
end

-- Once per upload, at the loading screen after the Companion wrote the answer: the newest entry
-- that is this account's own scan (its `at` is in foldAts) and newer than the last one said. The
-- stamp is kept even for a scan that changed nothing, so an older answer never speaks after a
-- newer one. Returns whether it printed.
function GC.ForeverScan.SayImpact()
  local s = GC.ForeverScan.Store()
  local impacts = GC.ForeverScan._impacts
  if not s or type(impacts) ~= "table" or type(s.foldAts) ~= "table" then return false end
  local mine = {}
  for _, at in ipairs(s.foldAts) do mine[at] = true end
  local said = type(s.impactSaidAt) == "number" and s.impactSaidAt or 0
  local best
  for _, e in ipairs(impacts) do
    if mine[e.at] and e.at > said and (not best or e.at > best.at) then best = e end
  end
  if not best then return false end
  s.impactSaidAt = best.at
  if best.updated == 0 then return false end
  local market = marketLabel(best)
  if best.first then
    GC.Print(GC.L["You opened %s -- its first %s prices are yours."]:format(market, count(best.updated)))
  elseif best.onlyYours > 0 then
    GC.Print(GC.L["Your scan updated %s prices on %s -- %s of them nobody else had in the last 24 hours."]
      :format(count(best.updated), market, count(best.onlyYours)))
  else
    GC.Print(GC.L["Your scan updated %s prices on %s."]:format(count(best.updated), market))
  end
  return true
end

local function scanner() return GC.ForeverScan._scanner end
function GC.ForeverScan.Request(reason) local s = scanner(); return s and s:Request(reason) or nil end
function GC.ForeverScan.OnReplicateUpdate() local s = scanner(); if s then s:OnReplicateUpdate() end end
function GC.ForeverScan.OnBrowsePassDone(book) local s = scanner(); if s then s:OnBrowsePassDone(book) end end
function GC.ForeverScan.OnAuctionHouseShow() local s = scanner(); return s and s:OnAuctionHouseShow() or nil end
function GC.ForeverScan.OnAuctionHouseClosed() local s = scanner(); if s then s:OnAuctionHouseClosed() end end
function GC.ForeverScan.IsBusy() local s = scanner(); return s ~= nil and s:IsBusy() end
