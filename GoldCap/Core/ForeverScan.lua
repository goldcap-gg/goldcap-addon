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
  -- Owner, 2026-09-30: the client hands the dump over in stages (2048 rows, then 54139, each with
  -- its own REPLICATE_ITEM_LIST_UPDATE), and both reads are saved. A partial replicate read holds
  -- its chat block this long for a fuller read to replace it, so one SCAN prints the block once.
  SAY_GRACE_SECONDS = 20,
  -- How long after the request the rest of a list handed over in stages is still this scan's: the
  -- first 1024 or 2048 rows come at once, the rest 52 to 64 seconds after the request (owner's
  -- journal, 2026-11-23). Till then the full scan is on (FullListOn), and the rest does not stamp
  -- the throttle again.
  REST_WAIT_SECONDS = 150,
  BROWSE_WAIT_SECONDS = 180,       -- a wide pass on a busy auction house, behind the arbiter
  -- A cut replicate read merges into the saved fold (below) only while the saved fold is no
  -- older than this: otherwise every item they share would keep the OLD fold's price forever, as
  -- long as every later read happens to come back cut too. Past this, a cut read replaces the
  -- stale fold wholesale, same as a whole one always does. Twelve hours, where it was two: a cut
  -- read prices an item by its lowest price alone, and one that replaced a whole scan three hours
  -- old left the Deals board 470 floors to weigh in place of 4,792 items' lots (owner's client,
  -- 2026-11-10). Merged, a known item keeps its lots under the floor the pass just saw
  -- (GC.ForeverFold.Refloor), and the Check reads the live book before any buy. Half a day is one
  -- sitting; yesterday's scan still goes.
  MERGE_MAX_AGE_SECONDS = 12 * 3600,
  -- How many of this account's own fold stamps are remembered (rememberAt below).
  KEEP_FOLD_ATS = 8,
  -- Steps of the scan's journal kept in the save (note below): three or four scans' worth.
  JOURNAL_KEEP = 60,
  -- HERO probe P1b (13.11): 28,736 of the 79,250 gear rows a scan read (36%) had no link yet, and
  -- a row with no link has no version to keep. Such rows are remembered (this many at most: 2000 a
  -- second for GEAR_LATE_SECONDS) and read again once a second after the save, for GEAR_LATE_SECONDS
  -- at most (lateStep below).
  GEAR_LATE_ROWS = 60000,
  GEAR_LATE_SECONDS = 30,
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

-- WoW: Forever's neutral auction house, Blackwater (Booty Bay, Gadgetzan, Everlook), shared by
-- both factions: what it lists is not this character's faction's market, and a scan read there was
-- filed under that faction and sent to goldcap.gg as its prices. It is the only auction house
-- outside the capitals, so the zone says which one is open: Stranglethorn Vale, Tanaris and
-- Winterspring, by the client's map ids. Forever keeps classic's numbering (Undercity is 1458 in the
-- owner's loot log, Core/ForeverLoot.lua, 2026-11-22); a town's own map, should it have one, is
-- walked up to its zone.
GC.ForeverScan.NEUTRAL_MAPS = { [1434] = true, [1446] = true, [1452] = true }

--- Whether map `mapID`, or a map above it (`parentOf(mapID)`, the parent's id or nil), is one of
--- Blackwater's zones.
function GC.ForeverScan.IsNeutralMap(mapID, parentOf)
  for _ = 1, 8 do
    if type(mapID) ~= "number" or mapID <= 0 then return false end
    if GC.ForeverScan.NEUTRAL_MAPS[mapID] then return true end
    mapID = parentOf and parentOf(mapID) or nil
  end
  return false
end

function GC.ForeverScan.New(driver)
  local obj = {}
  local state = "idle" -- idle | waiting | reading | browsing | saving
  local token = 0
  local ahOpen = false
  -- The auction house open is Blackwater (driver.neutral, asked as it opens): nothing read there is
  -- scanned, folded or saved.
  local neutral = false
  local acc, total, readIndex
  -- The dump this scanner last read: its row count and when. The client can fire
  -- REPLICATE_ITEM_LIST_UPDATE again for a dump already read (another addon's request inside the
  -- account throttle, or item data arriving), and an idle scanner used to read all ~72k rows over
  -- again for it (owner, beta 2026-09-27). One read per dump: see OnReplicateUpdate.
  local lastRead
  local busySince -- driver.now() when the scan now running began (obj:Since)
  -- The late-link pass under way (startLate), or nil. It runs while the scanner is idle, so a scan
  -- asked for meanwhile is never told the scanner is busy; a new scan's token ends it.
  local late

  -- The scan's journal, GoldCapDB.foreverScan.journal: each step with its time and what the client
  -- answered, the last C.JOURNAL_KEEP of them. A scan that comes back short leaves no other trace
  -- of why (owner's client, 2026-11-10: one scan saved nothing and the next 2,048 rows of 286,158,
  -- and the save could not say whether the window was closed or the dump never came). Read by
  -- /gc forever (Summary).
  local function note(step, a, b)
    local s = driver.store()
    if type(s) ~= "table" then return end
    if type(s.journal) ~= "table" then s.journal = {} end
    local j = s.journal
    -- The same step with the same answer again is counted on the one line: the client fired the
    -- dump's event 23 times in a second and pushed a whole scan out of the journal (owner's
    -- client, 2026-11-10).
    local last = j[#j]
    if last and last[2] == step and last[3] == a and last[4] == b then
      last[5] = (last[5] or 1) + 1
      return
    end
    j[#j + 1] = { driver.now(), step, a, b }
    while #j > C.JOURNAL_KEEP do table.remove(j, 1) end
  end

  -- driver.now() of the request for the full list on its way or being read, from the request until
  -- a read of it to the end is saved; nil otherwise. The client hands a list over in stages, and a
  -- cut stage is saved as it stands: the scanner went idle there, SCAN's spyglass stopped turning
  -- and the board read as a plain browse while the rest of the list, the 298,578 lots that matter,
  -- was still on its way (owner, 2026-11-23: "I want to see from start to end that a full scan is
  -- running").
  local fullSince

  local function reset()
    state, acc, total, readIndex = "idle", nil, nil, nil
    token = token + 1
  end

  -- The rule (final review I3, widened for the partial-replicate case): neither a browse-only
  -- result nor a ReplicateItems read that was cut (the dump capped at SUSPECT_CAP, emptied under
  -- the read, the auction house closed mid-read) may REPLACE a stored fold that came from a real
  -- dump -- either would otherwise throw away every ladder/lot-count the fuller fold priced for a
  -- thinner read's single floor. So: merge. A dump read to the end is not such a read, however its
  -- browse pass ended (see commit's `whole`). Every item the stored fold already has keeps its
  -- saved entry, UNLESS the saved fold was itself partial and this read is a real dump -- both
  -- reads are then incomplete, and this read's entry, the newer one, wins. An item the stored
  -- fold lacks entirely is added -- the same "only what the dump didn't cover" rule AddBrowse
  -- already applies inside one scan, now applied across two.
  --
  -- Age-gated for the cut-replicate case only (C.MERGE_MAX_AGE_SECONDS): a browse-only top-up
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

  -- Writes what the scan `a` saw, frozen to `items` (`count` of them), to the save. Returns the
  -- fold it wrote when the gear lots beside it are this scan's own (a merge keeps the saved ones).
  local function save(a, items, count)
    local gearOf
    local p = driver.passport() or {}
    local source = a.replicated and (a.browsed and "replicate+browse" or "replicate") or "browse"
    -- A dump read to the end is the whole auction house: commodities and all (the owner's save of
    -- 2026-11-06: 2349 items from a 155345-row dump, one of them from the browse pass after it).
    -- The browse pass that follows ending early -- a Deals row opened (it aborts the pass), the
    -- player's own search, the auction house closed, the watchdog -- takes nothing from it. It
    -- used to make the read partial, and so merged UNDER a saved fold up to 2 h old: the saved
    -- entry won for every item both held, the fresh prices were thrown away, and `at` kept the
    -- old stamp (review, 2026-11-06). Now it replaces the saved fold, stamped now, not partial.
    local whole = a.replicated == true and not a.cut
    local partial = a.partial == true and not whole
    local s = driver.store()
    if s then
      local existing = s.fold
      local mergeableAge = type(existing) == "table" and type(existing.at) == "number"
        and (driver.now() - existing.at) <= C.MERGE_MAX_AGE_SECONDS
      -- Bumped on every write, merges included: a merge keeps `at` (below) and may keep
      -- `itemCount` too while every entry it overwrote changed, so the Deals board
      -- (Core/ForeverDeals.lua's foldChanged) tells one write from the next by this. The
      -- Companion reads the fold's fields by name and the site's schema drops a key it does not
      -- know, so the upload is unchanged.
      local rev = (type(existing) == "table" and type(existing.rev) == "number" and existing.rev or 0) + 1
      if (source == "browse" or (partial and mergeableAge)) and isFullFold(existing) and sameHouse(existing, p) then
        -- Both reads incomplete: this attempt's entry is the newer one, so it wins over the
        -- saved fold's for any item they both priced.
        local overwrite = existing.partial == true and a.replicated == true
        local merged, mergedCount = {}, 0
        for itemID, encoded in pairs(existing.items) do
          merged[itemID] = encoded
          mergedCount = mergedCount + 1
        end
        for itemID, encoded in pairs(items) do
          local fresh = a.items[itemID]
          if merged[itemID] == nil then
            merged[itemID] = encoded
            mergedCount = mergedCount + 1
          elseif overwrite then
            merged[itemID] = encoded
          elseif fresh and fresh.browse then
            -- A known item's floor from this pass: the saved ladder as it stands now (lots under
            -- the floor gone, a cheaper one new), not the dump's as it stood then.
            merged[itemID] = GC.ForeverFold.Refloor(merged[itemID], fresh.min, fresh.qty)
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
          realm = p.realm, server = p.server, faction = p.faction, ruleset = p.ruleset, at = existing.at,
          source = existing.source, rows = existing.rows, itemCount = mergedCount, partial = true,
          rev = rev, items = merged }
        -- Plan 3e: the gear lots came from the very dump the merged fold keeps; they follow its stamp.
        if type(s.gear) == "table" then s.gear.at = s.fold.at end
      else
        s.fold = { v = GC.ForeverFold.VERSION, interface = p.interface, build = p.build, region = p.region,
          realm = p.realm, server = p.server, faction = p.faction, ruleset = p.ruleset, at = driver.now(), source = source,
          rows = a.replicated and a.rows or nil, itemCount = count, partial = partial or nil,
          rev = rev, items = items }
        -- A new stamp: the one the Companion will answer for. The merge above keeps the old `at`,
        -- which is already remembered.
        rememberAt(s, s.fold.at)
        -- Plan 3e: the gear lots of this dump, or none (a browse-only scan has no links).
        s.gear = a.gear and GC.ForeverGear.Freeze(a.gear, s.fold.at) or nil
        gearOf = a.gear and s.fold or nil
      end
    end
    note("saved", count, (a.cut and "cut " or "") .. (a.partial and "partial " or "") .. (a.givenUp and "given up" or ""))
    driver.notify("done", { rows = a.replicated and a.rows or nil, items = count,
      partial = a.partial == true, replicated = a.replicated == true, pending = a.pending,
      skipped = a.skipped, givenUp = a.givenUp })
    return gearOf
  end

  -- The late-link pass (HERO plan, finding 8): the gear rows the read found with no link yet, read
  -- again once a second after the save while their links load (each item's data was asked for at
  -- the read, rememberLate). A row that still holds the same item and now has a link goes into
  -- the scan's gear lots; one whose index now holds another item is dropped. Each second reads up
  -- to READ_BATCH of the rows still waiting, within the read's own frame budget, and goes on the
  -- next frame when the budget cuts it short. It ends when every row is read, after
  -- GEAR_LATE_SECONDS, when the auction house closes, at logout, or when another scan starts (the
  -- token); then the gear lots are frozen again under the same `at`, with `late` saying how many
  -- rows waited and how many were found. Nothing is written once the saved fold is no longer the
  -- one this scan wrote: its gear lots are another scan's then.
  local function finishLate(l)
    if late ~= l then return end
    late = nil
    note("late links", l.found, l.missing)
    local s = driver.store()
    if type(s) ~= "table" or s.fold ~= l.fold then return end
    local gear = GC.ForeverGear.Freeze(l.a.gear, l.fold.at)
    if gear then gear.late = { missing = l.missing, found = l.found } end
    s.gear = gear
    driver.notify("late", { missing = l.missing, found = l.found })
  end

  local lateStep
  lateStep = function(l, left)
    if late ~= l then return end
    if token ~= l.token or state ~= "idle" or not ahOpen then
      finishLate(l)
      return
    end
    local clock = driver.clock
    local started = clock and clock() or nil
    local done = 0
    while left > 0 do
      if l.k > #l.rows then
        -- One sweep over the waiting rows is done: what is still waiting is read next second.
        l.rows, l.ids, l.waitRows, l.waitIds, l.k = l.waitRows, l.waitIds, {}, {}, 1
        if #l.rows == 0 then
          finishLate(l)
          return
        end
        left = 0
        break
      end
      local i, id = l.rows[l.k], l.ids[l.k]
      l.k = l.k + 1
      local itemID, count, buyout = driver.rowInfo(i)
      if itemID == id then
        local link = driver.rowLink(i)
        if link then
          if GC.ForeverGear.AddRow(l.a.gear, itemID, count, buyout, link) then l.found = l.found + 1 end
        else
          l.waitRows[#l.waitRows + 1], l.waitIds[#l.waitIds + 1] = i, id
        end
      end
      left, done = left - 1, done + 1
      if started and done >= C.READ_MIN_ROWS and done % C.READ_CLOCK_EVERY == 0
          and clock() - started >= C.READ_BUDGET_MS then
        break
      end
    end
    if left > 0 then
      driver.after(0, function() lateStep(l, left) end)
      return
    end
    if l.ticks >= C.GEAR_LATE_SECONDS then
      finishLate(l)
      return
    end
    l.ticks = l.ticks + 1
    driver.after(1, function() lateStep(l, C.READ_BATCH) end)
  end

  -- After a save that wrote this scan's gear lots (`fold`), with rows still waiting for a link, while
  -- that fold is still the saved one and nothing new began.
  local function startLate(a, fold)
    local w = a.late
    if not (fold and a.gear and w and #w.rows > 0) or state ~= "idle" then return end
    local s = driver.store()
    if type(s) ~= "table" or s.fold ~= fold then return end
    if late then finishLate(late) end
    late = { a = a, fold = fold, rows = w.rows, ids = w.ids, waitRows = {}, waitIds = {}, k = 1,
      missing = #w.rows, found = 0, ticks = 1, token = token }
    note("late links", "waiting", #w.rows)
    local l = late
    driver.after(1, function() lateStep(l, C.READ_BATCH) end)
  end

  -- The save under way ("saving"): the scan it writes, how far the freeze got, and whether a dump
  -- came in the meantime (OnReplicateUpdate).
  local saving

  -- Freezes the scan a slice a frame, within the read's own budget, and saves it once all of it
  -- is frozen. In one go it was one frame of 76 ms in the game for the owner's 5800 items, on top
  -- of the board's refresh that "done" sets off: the scan's end was its one long stall. `unbounded`
  -- finishes it now (a logout). A driver without a clock freezes it all at once, as before.
  local function saveStep(unbounded)
    local sv = saving
    if not sv or state ~= "saving" then return end
    local clock = driver.clock
    local started = not unbounded and clock and clock() or nil
    local over
    if started then
      local entries = 0
      over = function()
        entries = entries + 1
        return entries % C.READ_CLOCK_EVERY == 0 and clock() - started >= C.READ_BUDGET_MS
      end
    end
    local items, count = GC.ForeverFold.Freeze(sv.a, driver.isGear, over, sv.job)
    if not items then
      sv.job = count
      driver.after(0, function() if saving == sv then saveStep() end end)
      return
    end
    saving = nil
    reset()
    -- A list read to the end ends the full scan; a cut stage leaves it on for the rest (FullListOn).
    if sv.a.replicated and not sv.a.cut then fullSince = nil end
    local gearOf = save(sv.a, items, count)
    -- A dump stage that came while this saved is read as it would have been had the save taken
    -- no time: as a dump this scanner has not read, if it is one.
    if sv.dumpCame then obj:OnReplicateUpdate() end
    -- Only while nothing new began: a stage read in place of this one owns the rows now.
    startLate(sv.a, gearOf)
  end

  local function commit()
    local a = acc
    if a then dropCutDump(a) end
    if not a or next(a.items) == nil then
      reset()
      note("saved nothing")
      driver.notify("done", nil)
      return
    end
    state = "saving"
    token = token + 1
    saving = { a = a }
    saveStep()
  end

  -- The pass this scan waits for, or one an earlier stage of its list armed, ends with the scan's
  -- need of it (driver.stopBrowse, UI/SniperFrame.lua's GC.Sniper.StopBrowsePass). Left out, a pass
  -- that could not start held SCAN on SCANNING with nothing running, and every press of it
  -- answered "full scan already in progress" until the auction house closed (a player,
  -- 2026-11-17). A pass that was out answers through OnBrowsePassAbandoned.
  local function endBrowse()
    if driver.stopBrowse then driver.stopBrowse() end
  end

  local function toBrowse(kind)
    local answer = driver.startBrowse(kind)
    note("browse pass", kind, tostring(answer))
    if answer ~= "started" and answer ~= "running" then return false end
    state = "browsing"
    token = token + 1
    local t = token
    driver.after(C.BROWSE_WAIT_SECONDS, function()
      if token ~= t or state ~= "browsing" then return end
      -- The wait and the pass end together, by the one path that gives a pass up: its end saves
      -- what it saw (OnBrowsePassAbandoned). Still browsing after it: no pass was out to end.
      endBrowse()
      if token == t and state == "browsing" then
        acc.partial, acc.givenUp = true, true
        commit()
      end
    end)
    return true
  end

  -- What a browse pass saw goes into the fold: every item's whole floor, over a cut dump's partial
  -- view of it. A variant row (gear by item level, a caged pet by species) is one version, not the
  -- item's floor -- the same rule UI/SniperFrame.lua's _LiveRow applies to the tooltip.
  local function takeBook(book)
    dropCutDump(acc)
    for itemID, row in pairs(type(book) == "table" and book or {}) do
      if type(row) == "table" and not row.variants then
        GC.ForeverFold.AddBrowse(acc, itemID, row.floor, row.qty)
        acc.browsed = true
      end
    end
  end

  local function afterRead()
    if acc.dumpRows % C.SUSPECT_CAP == 0 then acc.partial, acc.cut = true, true end
    note("read", acc.dumpRows, acc.cut and "cut" or nil)
    -- A list read to the end is every price there is (save's `whole`), and its "classes" pass adds
    -- next to nothing. While the player's own use of the auction house holds that pass back
    -- (driver.browseHeld: their search on the Buy list, a buy page, another tab) the list is
    -- saved now: it used to wait out BROWSE_WAIT_SECONDS behind a pass that could not start, the
    -- board on the last scan's prices all the while (a player, 2026-11-17). A cut list still
    -- waits: its "wide" pass is the scan.
    if not acc.partial and driver.browseHeld and driver.browseHeld() then
      note("browse pass", "classes", "held")
      endBrowse()
      commit()
      return
    end
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

  -- A gear row read with no link: its index and item, for the late-link pass (startLate), and the
  -- item's data asked for once per scan, so the link can load meanwhile. Kept on the scan's own
  -- accumulator: a later stage read in its place starts over with its own.
  local function rememberLate(i, itemID)
    local w = acc.late
    if not w then
      w = { rows = {}, ids = {}, asked = {} }
      acc.late = w
    end
    if #w.rows < C.GEAR_LATE_ROWS then
      w.rows[#w.rows + 1], w.ids[#w.ids + 1] = i, itemID
    end
    if not w.asked[itemID] then
      w.asked[itemID] = true
      if driver.requestLoad then pcall(driver.requestLoad, itemID) end
    end
  end

  local readBatch
  readBatch = function(t)
    if token ~= t or state ~= "reading" then return end
    local now = driver.numRows() or 0
    if now < total then
      note("dump shrank", now, total)
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
        -- fold, never in it. A row whose link has not loaded is read again after the save.
        if acc.gear and isGearRow(itemID) then
          local _, why = GC.ForeverGear.AddRow(acc.gear, itemID, count, buyout, driver.rowLink(i))
          if why == "nolink" then rememberLate(i, itemID) end
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
    note("rows", n)
    lastRead = { rows = n, at = driver.now() }
    state, total, readIndex = "reading", n, 0
    token = token + 1
    readBatch(token)
    return true
  end

  local function noAnswer()
    note("no rows")
    fullSince = nil
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
    if neutral then
      note("refused", "neutral")
      if reason == "button" then driver.notify("neutral") end
      return "neutral"
    end
    local s = driver.store() or {}
    local now = driver.now()
    local wait = self:DueIn()
    if wait > 0 then
      note("throttled", reason, math.floor(C.COOLDOWN_SECONDS - wait))
      if reason ~= "button" then return "cooldown" end
      driver.notify("cooldown", math.ceil(wait / 60))
      acc = GC.ForeverFold.New()
      busySince = now
      if not toBrowse("wide") then acc = nil end
      return "cooldown"
    end
    s.requestedAt = now
    note("asked", reason)
    acc = GC.ForeverFold.New()
    busySince, fullSince = now, now
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
    note("dump event", state, driver.numRows() or 0)
    if state == "waiting" then beginRead(); return end
    if state == "saving" then saving.dumpCame = true; return end
    -- A later stage of the dump this scan is reading or browsing after: the client hands a dump
    -- over in stages, each with its own event (2048 rows, then the rest). It is read from the
    -- start, in place of the stage the scan has; the browse pass that stage started goes on, and
    -- its end is still this scan's. A repeat for the stage it has (item data landing) changes
    -- nothing: the count is the same.
    if (state == "reading" or state == "browsing") and acc and acc.replicated and ahOpen then
      if (driver.numRows() or 0) > (acc.dumpRows or 0) then
        acc = GC.ForeverFold.New()
        beginRead()
      end
      return
    end
    if state ~= "idle" or not ahOpen or neutral then return end
    -- Somebody else's full scan (another addon, /gc forever): the account's throttle is spent
    -- either way, so the dump is folded rather than asked for again.
    local n = driver.numRows() or 0
    if n <= 0 then return end
    -- The same dump again: the same row count inside the throttle window, which no new dump can
    -- beat. A different count, or a later event, is a dump this scanner has not read.
    if lastRead and n == lastRead.rows and driver.now() - lastRead.at < C.COOLDOWN_SECONDS then return end
    -- The rest of the list this scan asked for, after its first stage was saved: the same request,
    -- whose stamp and seconds stand. Anything else is a new list, and the throttle starts again.
    if not self:FullListOn() then
      local s = driver.store()
      if s then s.requestedAt = driver.now() end
      fullSince = driver.now()
    end
    acc = GC.ForeverFold.New()
    busySince = fullSince
    beginRead()
  end

  function obj:OnBrowsePassDone(book)
    if state ~= "browsing" then return end
    note("pass done")
    takeBook(book)
    acc.browsed = true
    commit()
  end

  -- The pass this scan waits for was given up (the stall watchdog, the player's own search, Auto
  -- pausing): its end is not coming, so what it saw is saved now, marked partial, rather than at
  -- BROWSE_WAIT_SECONDS with the SCAN button on SCANNING all the while.
  function obj:OnBrowsePassAbandoned(book)
    if state ~= "browsing" then return end
    note("pass abandoned")
    takeBook(book)
    acc.partial, acc.givenUp = true, true
    commit()
  end

  function obj:OnAuctionHouseShow()
    ahOpen = true
    neutral = driver.neutral ~= nil and driver.neutral() == true
    note("opened", neutral and "neutral" or nil)
    return self:Request("auto")
  end

  function obj:OnAuctionHouseClosed()
    ahOpen, neutral = false, false
    -- Closing drops what the client was still handing over.
    fullSince = nil
    note("closed", state)
    -- The late-link pass reads the dump this auction house handed over: it ends here, with what it found.
    if late then finishLate(late) end
    -- A scan that is saving saw all it was going to: closing changes nothing it writes.
    if state == "idle" or state == "saving" then return end
    if state == "waiting" then reset(); return end
    acc.partial = true
    if state == "reading" then acc.cut = true end
    commit()
  end

  -- The game writes the save only after the logout's handlers: a save under way is finished now,
  -- and the late-link pass keeps what it found (chat says to /reload right after a scan).
  function obj:OnLogout()
    saveStep(true)
    if late then finishLate(late) end
  end

  function obj:IsBusy() return state ~= "idle" end
  -- Whether the auction house open is Blackwater: nothing read there is this house's.
  function obj:Neutral() return neutral end
  -- Whether a full list may be asked for now: no scan running, the home auction house open, and
  -- the account's throttle spent (Auto asks then, GC.Sniper's startScan).
  function obj:Due()
    if state ~= "idle" or not ahOpen or neutral then return false end
    return self:DueIn() == 0
  end
  -- Seconds until the account's throttle allows the next full list, 0 once it does: the one reading
  -- of the stamp that Request, Due and the countdown on SCAN share (GC.Sniper's refreshScanButton).
  -- A stamp from the future is a clock that stepped back, not a throttle.
  function obj:DueIn()
    local s = driver.store() or {}
    local since = type(s.requestedAt) == "number" and driver.now() - s.requestedAt or math.huge
    if since < 0 then return 0 end
    return math.max(0, C.COOLDOWN_SECONDS - since)
  end
  function obj:State() return state end
  -- When this scan began (driver.now), from the request to the save; nil while idle. The board
  -- counts its seconds from it (GC.Sniper._ScanLine).
  function obj:Since()
    if state ~= "idle" then return busySince end
    return self:FullListOn() and fullSince or nil
  end
  -- Whether a full list is on: asked for and not yet read to the end, the wait for the rest of one
  -- handed over in stages included. Not a browse in its place (the throttle not spent, no answer).
  function obj:FullListOn()
    if not fullSince or not ahOpen then return false end
    if state == "waiting" or state == "reading" then return true end
    -- Browsing after a read of the list, or saving it.
    if state ~= "idle" and acc and acc.replicated then return true end
    return driver.now() - fullSince < C.REST_WAIT_SECONDS
  end
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
-- What the chat has already said this session (see _SayDone). Not saved: a /reload starts over.
GC.ForeverScan._said = {}

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
  -- `said` is what this session has already printed: the how-to hints and an unchanged bags or
  -- upgrades line are not printed again by the next scan (owner, beta 2026-09-30). /gc bags and
  -- /gc upgrades pass nothing and always print in full.
  local said = GC.ForeverScan._said
  if GC.ForeverValue and GC.ForeverValue.PrintBags then GC.ForeverValue.PrintBags(nil, said) end
  -- Plan 3e: how many upgrades the scan holds for this character's gear, when there are any --
  -- queued rather than called here (see _QueueUpgradesUpdate below): Core/ForeverUpgrades.lua's
  -- Build is a synchronous, potentially ~140-tooltip-read walk, and this line runs on the very
  -- frame that just froze the fold and refreshed Sniper.
  GC.ForeverScan._QueueUpgradesUpdate()
  if GC.Data and GC.Data.CompanionShares and GC.Data.CompanionShares() and not said.shared then
    said.shared = true
    GC.Print(GC.L["Shared with goldcap.gg on your next /reload"])
  end
end

-- Final review (re-review 2026-09-27): PrintCount and RefreshIfShown used to each run their own
-- Core/ForeverUpgrades.lua Build synchronously, right here, on top of the fold freeze, the Sniper
-- refresh and PrintBags already on this frame -- and paid for the tooltip pass (up to ~140
-- C_TooltipInfo.GetHyperlink calls) twice over whenever the upgrades window happened to be open.
-- One Build now, off this frame with C_Timer.After(0, ...) -- the idiom Core/Init.lua's OnTick and
-- UI/AuctionHouseTab.lua's tab-add already use -- feeds both the chat count and, only while the
-- HERO tab (UI/HeroFrame.lua) is on screen, its render. Off screen, there is nothing to render, so Build's own
-- tooltip pass is skipped too (its skipUsable argument): usability then comes only from the class
-- armour/weapon tables and CanDualWield (Core/ForeverUpgrades.lua's ClassAllows/canDualWield), the
-- same fallback a level-ahead pick already trusts.
function GC.ForeverScan._QueueUpgradesUpdate()
  local U = GC.ForeverUpgrades
  if not (U and U.PrintCount and U.Current) then return end
  local timer = _G.C_Timer
  if type(timer) ~= "table" or type(timer.After) ~= "function" then return end
  timer.After(0, function()
    local UI = GC.Hero
    local shown = UI ~= nil and UI.IsShown ~= nil and UI.IsShown() == true
    local r = U.Current(not shown)
    U.PrintCount(r, GC.ForeverScan._said)
    if shown and UI.Render then UI.Render(r, time()) end
  end)
end

-- Bumped by every "started" and "done": a deferred post-scan block runs only if nothing newer
-- arrived during its grace period.
local sayToken = 0
-- True while a partial read's chat block is held for a fuller one (C.SAY_GRACE_SECONDS): the scan
-- is still considered running then, so the SCAN button says so and a click does not start another.
local sayHeld = false

local function notify(kind, a, b)
  if kind == "started" or kind == "done" then sayToken = sayToken + 1; sayHeld = false end
  if kind == "started" then
    GC.Print(GC.L["Scanning the auction house…"])
    -- On the board from the press: the client takes about ten seconds to hand the list over, and
    -- until the first "reading the auction house" line the board said nothing (owner, 2026-11-10).
    -- Said here at once; the board's ticker keeps it there and counts the seconds
    -- (GC.Sniper._ScanLine).
    if GC.Sniper and GC.Sniper.SetScanStatus then
      GC.Sniper.SetScanStatus(GC.Sniper._ScanWords(GC.L["Scanning the auction house…"]), 1)
    end
  elseif kind == "closed" then
    GC.Print(GC.L["Open the Auction House first."])
  elseif kind == "neutral" then
    local text = GC.L["This is Blackwater, the neutral auction house. GoldCap does not scan it: its prices are not your faction's."]
    GC.Print(text)
    if GC.Sniper and GC.Sniper.SetScanStatus then GC.Sniper.SetScanStatus(text, 6) end
  elseif kind == "cooldown" then
    local text = GC.L["The full scan is cooling down (%d min left). Scanning by browsing instead"]:format(a)
    GC.Print(text)
    -- On the board too, where the SCAN that was pressed is: the chat line scrolls away under the
    -- auction house window (owner, 2026-11-10).
    if GC.Sniper and GC.Sniper.SetScanStatus then GC.Sniper.SetScanStatus(text, 6) end
  elseif kind == "noanswer" then
    GC.Print(GC.L["The auction house did not answer the full scan. Scanning by browsing instead"])
  elseif kind == "late" then
    -- Gear rows whose links loaded after the save: the upgrades are built again, once, if any did.
    if type(a) == "table" and (a.found or 0) > 0 then GC.ForeverScan._QueueUpgradesUpdate() end
  elseif kind == "progress" then
    if GC.Sniper and GC.Sniper.SetScanStatus then
      -- Each line holds the status line for a second, against the board's other writers; the
      -- read's last one holds nothing, so what the scan says next lands: a list saved at once
      -- (afterRead) ended inside that second, and its readout was dropped behind the hold.
      GC.Sniper.SetScanStatus(GC.Sniper._ScanWords(GC.L["reading the auction house: %s of %s lots"]:format(count(a), count(b))),
        (tonumber(a) or 0) < (tonumber(b) or 0) and 1 or 0)
    end
  elseif kind == "done" then
    local timer = _G.C_Timer
    -- Not after a browse pass that was given up: a dump stage that came while the scan browsed was
    -- not read (OnReplicateUpdate), so no fuller read is on its way to replace this one.
    if a and a.replicated and a.partial and not a.givenUp
        and type(timer) == "table" and type(timer.After) == "function" then
      local mine = sayToken
      sayHeld = true
      timer.After(C.SAY_GRACE_SECONDS, function()
        if sayToken == mine then
          sayHeld = false
          GC.ForeverScan._SayDone(a)
          if GC.Sniper and GC.Sniper.RepaintScanState then GC.Sniper.RepaintScanState() end
        end
      end)
    else
      GC.ForeverScan._SayDone(a)
    end
    if GC.Sniper and GC.Sniper.OnForeverFold then GC.Sniper.OnForeverFold() end
  end
  -- The toolbar's SCAN button and AUTO chip follow the scanner's own state; repainted on every
  -- edge of it rather than left to a clock that other work in the same tick can starve.
  if (kind == "done" or kind == "noanswer") and GC.Sniper and GC.Sniper.RepaintScanState then
    GC.Sniper.RepaintScanState()
  end
end

GC.ForeverScan._Notify = notify

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
    -- A gear row read with no link: the item's data is asked for, for the late-link pass.
    requestLoad = function(itemID)
      local item = _G.C_Item
      if type(item) == "table" and type(item.RequestLoadItemDataByID) == "function" then
        pcall(item.RequestLoadItemDataByID, itemID)
      end
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
    -- The pass ends with the scan's need of it (endBrowse above).
    stopBrowse = function()
      if GC.Sniper and GC.Sniper.StopBrowsePass then GC.Sniper.StopBrowsePass() end
    end,
    -- Whether the player's own use of the auction house holds a pass back right now (afterRead).
    browseHeld = function()
      return GC.Sniper ~= nil and GC.Sniper.BrowseHeld ~= nil and GC.Sniper.BrowseHeld() == true
    end,
    store = function() return GC.ForeverScan.Store() end,
    -- Blackwater's zones (GC.ForeverScan.IsNeutralMap), from where the player stands.
    neutral = function()
      local map = _G.C_Map
      if type(map) ~= "table" or type(map.GetBestMapForUnit) ~= "function" then return false end
      local ok, id = pcall(map.GetBestMapForUnit, "player")
      return GC.ForeverScan.IsNeutralMap(ok and id or nil, function(m)
        local okI, info = pcall(map.GetMapInfo, m)
        return okI and type(info) == "table" and info.parentMapID or nil
      end)
    end,
    passport = function()
      local p = GC.Game and GC.Game.Passport and GC.Game.Passport() or {}
      -- GetRealmName() answers "" on Forever's 1.60.1.71037 (Core/Game.lua RealmName).
      local realm = GC.Game and GC.Game.RealmName and GC.Game.RealmName() or nil
      local okF, faction = pcall(UnitFactionGroup, "player")
      return { interface = p.interface, build = p.build, region = p.regionId,
        realm = realm,
        -- The server number in the player's GUID: goldcap.gg names the realm from it when the
        -- client names none and GoldCap never saw it (a character first played after the patch).
        server = GC.Game and GC.Game.ServerId and GC.Game.ServerId((select(2, pcall(_G.UnitGUID, "player")))) or nil,
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

-- This character's realm and faction, as far as the client has named them yet (settleHouse): nil
-- for either one it has not. Core/Data.lua checks an adopted crowd payload against them.
function GC.ForeverScan.House()
  settleHouse()
  return GC.ForeverScan._realm, GC.ForeverScan._faction
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
--
-- What it read from an entry is kept, with the entry's text: GetItemValue asks about an item
-- several times a row on every page of a scan pass and once more for every row at its end, and
-- decoding the text each time was most of that work (5800 items: 15 ms in LuaJIT, about six times
-- that in the game, at the end of every pass). The same text reads the same whichever scan wrote
-- it, so a new scan needs nothing reset: its entries are new text, and are read again.
local readEntries = {}

function GC.ForeverScan.ValueFor(itemID)
  local fold = GC.ForeverScan.Fold()
  if not fold then return nil end
  local encoded = fold.items[itemID]
  if encoded == nil then return nil end
  local kept = readEntries[itemID]
  if not kept or kept.text ~= encoded then
    local e = GC.ForeverFold.Decode(encoded)
    kept = { text = encoded, ok = e ~= nil }
    if e then
      kept.value, kept.min, kept.qty, kept.lots, kept.gear, kept.browse =
        e.value, e.min, e.qty, e.lots, e.gear or nil, e.browse or nil
    end
    readEntries[itemID] = kept
  end
  if not kept.ok then return nil end
  return { mv = kept.value, min = kept.min, currentQty = kept.qty, listings = kept.lots, ts = fold.at,
    source = "scan", kind = "own_scan", gear = kept.gear, browse = kept.browse }
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
  -- The journal's last steps, newest last: seconds ago, the step, what came with it.
  local journal = type(s) == "table" and type(s.journal) == "table" and s.journal or {}
  for i = math.max(1, #journal - 19), #journal do
    local e = journal[i]
    lines[#lines + 1] = ("own scan: %ds ago %s%s%s%s"):format(now - (e[1] or now), tostring(e[2]),
      e[3] ~= nil and (" " .. tostring(e[3])) or "", e[4] ~= nil and (" " .. tostring(e[4])) or "",
      e[5] and (" x" .. e[5]) or "")
  end
  local g = type(s) == "table" and s.gear or nil
  if type(g) == "table" and type(g.items) == "table" then
    local n = 0
    for _ in pairs(g.items) do n = n + 1 end
    local lateText = ""
    if type(g.late) == "table" then
      lateText = (", %s of %s rows with no link at the read found later"):format(tostring(g.late.found),
        tostring(g.late.missing))
    end
    lines[#lines + 1] = ("own scan: gear lots for %d items%s%s"):format(n,
      (type(f) == "table" and g.at == f.at) and "" or " (from an older scan, not used)", lateText)
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
    GC.Print(GC.L["You opened %s: its first %s prices are yours."]:format(market, count(best.updated)))
  elseif best.onlyYours > 0 then
    GC.Print(GC.L["Your scan updated %s prices on %s. %s of them nobody else had in the last 24 hours."]
      :format(count(best.updated), market, count(best.onlyYours)))
  else
    GC.Print(GC.L["Your scan updated %s prices on %s."]:format(count(best.updated), market))
  end
  return true
end

local function scanner() return GC.ForeverScan._scanner end
-- Every entry point repaints the toolbar after the scanner has moved: the scanner's state is the
-- one truth the SCAN button and the AUTO chip read (GC.Sniper.ScanActive), and these are its edges
-- that no notify() is sent from (a request accepted, an open, a close, a dump, a pass done).
local function repaint()
  if GC.Sniper and GC.Sniper.RepaintScanState then GC.Sniper.RepaintScanState() end
end
function GC.ForeverScan.Request(reason)
  local s = scanner(); local r = s and s:Request(reason) or nil; repaint(); return r
end
function GC.ForeverScan.OnReplicateUpdate() local s = scanner(); if s then s:OnReplicateUpdate(); repaint() end end
-- Every pass between full scans also moves the Deals board's live view (GC.ForeverDeals.OnBrowsePass),
-- before the scanner takes the pass: a full scan's pass then lands in a new fold, which starts
-- the view anew. Not at Blackwater: what it lists is not the fold's house.
local function toBoard(s, book, whole)
  if s:Neutral() then return end
  if GC.ForeverDeals and GC.ForeverDeals.OnBrowsePass then GC.ForeverDeals.OnBrowsePass(book, whole) end
end
function GC.ForeverScan.OnBrowsePassDone(book)
  local s = scanner()
  if s then toBoard(s, book, true); s:OnBrowsePassDone(book); repaint() end
end
function GC.ForeverScan.OnBrowsePassAbandoned(book)
  local s = scanner()
  if s then toBoard(s, book, false); s:OnBrowsePassAbandoned(book); repaint() end
end
function GC.ForeverScan.OnAuctionHouseShow() local s = scanner(); local r = s and s:OnAuctionHouseShow() or nil; repaint(); return r end
function GC.ForeverScan.OnAuctionHouseClosed() local s = scanner(); if s then s:OnAuctionHouseClosed(); repaint() end end
function GC.ForeverScan.OnLogout() local s = scanner(); if s then s:OnLogout() end end
-- The scan machine's state and when it began, nil while it is idle. Not IsBusy: the hold on a
-- partial read's chat block is not a scan the board should count seconds for.
function GC.ForeverScan.Running()
  local s = scanner()
  if not s then return nil end
  if s:State() ~= "idle" then return s:State(), s:Since() end
  -- Between a list's first stage and its rest: the client is waited on again.
  if s:FullListOn() then return "waiting", s:Since() end
  return nil
end
function GC.ForeverScan.FullListOn() local s = scanner(); return s ~= nil and s:FullListOn() end
function GC.ForeverScan.IsBusy() local s = scanner(); return s ~= nil and (s:IsBusy() or sayHeld) end
function GC.ForeverScan.Due() local s = scanner(); return s ~= nil and not sayHeld and s:Due() end
function GC.ForeverScan.DueIn() local s = scanner(); return s and s:DueIn() or nil end
