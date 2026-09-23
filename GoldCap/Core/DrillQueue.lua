local _, GC = ...

-- Sniper fast loop, phase 1 (design doc §3 Drill-down): a bounded priority queue of
-- Core/BookPass.lua hits waiting for a live SendSearchQuery. Pure and driver-injected
-- (driver.now() only), like every other module in this batch. Push takes whatever the
-- caller hands it (itemID, floor, estProfit); Peek/Pop return the highest-estProfit entry
-- still queued, and Pop refuses once LIM.DRILL_PER_MINUTE sends have already gone out in the
-- trailing 60 seconds -- the budget this module enforces is SENDS, not pushes, so a busy
-- board never loses a hit for being unable to even queue it.
--
-- Three operations, not one, because only ONE of them costs a send. Pop charges the budget
-- and is therefore only correct once the caller knows the query will actually go out; Peek
-- lets the arbiter look at the head first, and Drop lets it discard a hit the order book has
-- already moved past. A queue with only Pop charged every declined attempt, so a single
-- undrillable item parked at the head could burn the whole per-minute budget forever.
GC.DrillQueue = {}

-- A queue that only ever grows is a memory leak with a priority order, and a hit that has
-- been waiting a minute and a half is describing a price nobody has seen since -- the book
-- pass has re-read that item several times over by then. Both bounds are enforced here
-- rather than by the caller: the arbiter drains at most one entry per throttle slot, so it
-- is in no position to notice either.
local MAX_ENTRIES = 200
local ENTRY_TTL_SECONDS = 90
-- Caps fixes 4b: strict priority, bounded. A priority hit (the player's own cap) still goes ahead
-- of every ordinary one -- but after this many priority pops in a row that an ordinary hit waited
-- through, the next pop is the best ordinary hit. A few hundred caps hitting at once (the first
-- round after opening the auction house) are a stream long enough to hold the ordinary drills back
-- for minutes; with this they still get one drill in five.
local PRIORITY_RUN = 4
-- Final review m7: and room. Ordering only helps a hit that is queued at all, and with two hundred
-- cap hits queued every ordinary one was refused at Push -- the worst entry of a full queue was
-- always a cap it could not outrank. Priority entries may hold this many places; the rest of the
-- queue is kept for ordinary hits, which can still fill all of it while no cap waits.
local PRIORITY_SLOTS = 150
GC.DrillQueue.PRIORITY_SLOTS = PRIORITY_SLOTS

function GC.DrillQueue.New(driver, opts)
  opts = opts or {}
  local perMinute = opts.perMinute or 60
  local obj = {}
  local items = {}       -- array of { itemID, floor, estProfit, key, pushedAt }
  local queued = {}      -- "itemID:floor" -> true, cleared the moment an entry leaves
  local queuedItems = {} -- itemID -> how many entries carry it, so Has() costs nothing per row
  local sentAt = {}      -- sliding 60s window of driver.now() timestamps, one per successful Pop
  -- When the oldest queued entry expires. math.huge while nothing can expire, so the sweep
  -- below is skipped outright on the overwhelming majority of calls -- Has() runs once per
  -- rendered row, several times a second.
  local nextExpiryAt = math.huge
  -- Priority pops in a row that an ordinary hit sat through (PRIORITY_RUN above).
  local priorityRun = 0

  local function key(itemID, floor) return itemID .. ":" .. floor end

  -- Caps fixes 4b: a cap hit that leaves without being drilled -- aged out, evicted from a full
  -- queue, or refused by one -- is told to the caller. It came from a ratchet (Core/KeyPoll.lua's
  -- Fold, GC.Caps.BookHits) that does not report an unchanged floor twice, so without a word here
  -- the item was never looked at again until its price happened to move. The caller re-arms that
  -- ratchet. An ordinary hit is not reported: the market's own leads were always best-effort.
  -- A drilled (Pop), discarded (Drop) or session-cleared (Clear) entry is not lost.
  local function lose(entry)
    if entry.cap and driver.onLost then
      driver.onLost({ itemID = entry.itemID, floor = entry.floor, priority = entry.priority, cap = true })
    end
  end

  local function forget(index)
    local entry = table.remove(items, index)
    queued[entry.key] = nil
    local held = (queuedItems[entry.itemID] or 1) - 1
    queuedItems[entry.itemID] = held > 0 and held or nil
    return entry
  end

  local function pruneExpired(now)
    if now < nextExpiryAt then return end
    nextExpiryAt = math.huge
    for i = #items, 1, -1 do
      local expiresAt = items[i].pushedAt + ENTRY_TTL_SECONDS
      if now >= expiresAt then
        lose(forget(i))
      elseif expiresAt < nextExpiryAt then
        nextExpiryAt = expiresAt
      end
    end
  end

  -- True when `a` ranks below `b`: lower priority first, estProfit desc breaks a tie. A cap
  -- hit is the player's own rule; it is verified before any market-derived re-check, so it
  -- outranks every priority-less (estProfit-only) hit regardless of how small its own
  -- estProfit is -- up to PRIORITY_RUN pops in a row, see bestIndex.
  local function ranksBelow(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.estProfit < b.estProfit
  end

  -- The entry the next Pop takes, which is also the one Peek names. Ordinarily the best-ranked
  -- one; once PRIORITY_RUN priority pops in a row have gone ahead of a waiting lower-priority
  -- hit, the best of those instead.
  local function bestIndex()
    if #items == 0 then return nil end
    local best = 1
    for i = 2, #items do
      if ranksBelow(items[best], items[i]) then best = i end
    end
    if priorityRun >= PRIORITY_RUN then
      local waiting
      for i = 1, #items do
        if items[i].priority < items[best].priority
            and (not waiting or ranksBelow(items[waiting], items[i])) then
          waiting = i
        end
      end
      if waiting then return waiting end
    end
    return best
  end

  -- Whether anything still queued ranks below `priority` -- i.e. is being made to wait by it.
  local function anyBelow(priority)
    for i = 1, #items do
      if items[i].priority < priority then return true end
    end
    return false
  end

  function obj:Push(hit)
    if type(hit) ~= "table" or type(hit.itemID) ~= "number" or type(hit.floor) ~= "number" then
      return false
    end
    local now = driver.now()
    pruneExpired(now)
    local k = key(hit.itemID, hit.floor)
    local estProfit = hit.estProfit or 0
    local priority = tonumber(hit.priority) or 0
    local cap = hit.cap == true
    if queued[k] then
      -- The same item at the same floor, already queued -- but maybe reported by another source
      -- at a higher priority (the realm poll's ordinary hit, then the player's own cap). Still one
      -- entry; it just may not stay queued at the lower of the two -- and among its new peers it
      -- is ordered by their measure, not by the one it was queued under (a cap's is the saving
      -- under the cap, an ordinary hit's the market's).
      for i = 1, #items do
        local entry = items[i]
        if entry.key == k and priority > entry.priority then
          entry.priority = priority
          entry.estProfit = estProfit
          entry.cap = entry.cap or cap
        end
      end
      return false
    end
    if priority > 0 then
      -- The caps' share is full: a new one competes with the worst priority entry, never with an
      -- ordinary hit (PRIORITY_SLOTS above).
      local held, worst = 0, nil
      for i = 1, #items do
        if items[i].priority > 0 then
          held = held + 1
          if not worst or ranksBelow(items[i], items[worst]) then worst = i end
        end
      end
      if held >= PRIORITY_SLOTS then
        if not ranksBelow(items[worst], { priority = priority, estProfit = estProfit }) then
          lose({ itemID = hit.itemID, floor = hit.floor, priority = priority, cap = cap })
          return false
        end
        lose(forget(worst))
      end
    end
    if #items >= MAX_ENTRIES then
      -- Full: the queue keeps the best MAX_ENTRIES hits it has been offered, so a new hit
      -- either displaces the worst one queued or is refused outright. Refusing the CHEAPEST
      -- of the two is the only ordering that cannot be gamed by arrival time -- and a
      -- low-priority entry is displaced before a high-priority one, same comparator as above.
      local worst = 1
      for i = 2, #items do
        if ranksBelow(items[i], items[worst]) then worst = i end
      end
      if not ranksBelow(items[worst], { priority = priority, estProfit = estProfit }) then
        lose({ itemID = hit.itemID, floor = hit.floor, priority = priority, cap = cap })
        return false
      end
      lose(forget(worst))
    end
    queued[k] = true
    queuedItems[hit.itemID] = (queuedItems[hit.itemID] or 0) + 1
    -- A hit handed back by Peek/Pop carries the moment it FIRST joined the queue, and keeps it
    -- when it is re-queued. The caller re-queues a hit whose send was declined, and stamping
    -- that with a fresh `now` made the entry immortal: it describes a price nobody has seen for
    -- minutes, it sits at the head on its own estProfit, and it can never age out -- so every
    -- re-queue bought the same undrillable item another ninety seconds at the front.
    local pushedAt = (type(hit.pushedAt) == "number" and hit.pushedAt < now) and hit.pushedAt or now
    items[#items + 1] = { itemID = hit.itemID, floor = hit.floor, estProfit = estProfit,
      priority = priority, cap = cap, key = k, pushedAt = pushedAt }
    local expiresAt = pushedAt + ENTRY_TTL_SECONDS
    if expiresAt < nextExpiryAt then nextExpiryAt = expiresAt end
    return true
  end

  local function pruneWindow(now)
    local kept = {}
    for i = 1, #sentAt do
      if now - sentAt[i] < 60 then kept[#kept + 1] = sentAt[i] end
    end
    sentAt = kept
  end

  -- The head of the queue, charged to nothing and removed from nothing. The arbiter looks
  -- here first so it can decide whether a send is even possible before spending one.
  function obj:Peek()
    pruneExpired(driver.now())
    local best = bestIndex()
    if not best then return nil end
    local entry = items[best]
    -- pushedAt travels with the hit so a caller that hands it back (a declined send is
    -- re-queued) cannot reset its age -- see Push. priority and cap travel too, for the same
    -- reason: a re-queued cap hit that lost its priority on the way back in would fall to the
    -- back of the line behind ordinary estProfit hits.
    return { itemID = entry.itemID, floor = entry.floor, estProfit = entry.estProfit,
      priority = entry.priority, cap = entry.cap, pushedAt = entry.pushedAt }
  end

  -- Discards one entry without charging the budget: the hit describes a floor the book has
  -- since moved off, so no send was ever going to be worth making for it.
  function obj:Drop(hit)
    if type(hit) ~= "table" or type(hit.itemID) ~= "number" or type(hit.floor) ~= "number" then
      return false
    end
    local k = key(hit.itemID, hit.floor)
    if not queued[k] then return false end
    for i = 1, #items do
      if items[i].key == k then
        forget(i)
        return true
      end
    end
    return false
  end

  function obj:Pop()
    local now = driver.now()
    pruneExpired(now)
    if #items == 0 then return nil end
    pruneWindow(now)
    if #sentAt >= perMinute then return nil end

    local chosen = forget(bestIndex())
    sentAt[#sentAt + 1] = now
    -- The run counts only pops that made something lower wait; an ordinary pop, or a priority
    -- pop with nothing below it in the queue, owes nobody anything.
    if anyBelow(chosen.priority) then
      priorityRun = priorityRun + 1
    else
      priorityRun = 0
    end
    return { itemID = chosen.itemID, floor = chosen.floor, estProfit = chosen.estProfit,
      priority = chosen.priority, cap = chosen.cap, pushedAt = chosen.pushedAt }
  end

  -- Whether a live look at this item is already queued -- what a board row asks before it is
  -- allowed to tell the player something is checking it.
  function obj:Has(itemID)
    pruneExpired(driver.now())
    return (queuedItems[itemID] or 0) > 0
  end

  function obj:Depth()
    pruneExpired(driver.now())
    return #items
  end

  -- Everything queued describes a live order book, and there is no live order book once the
  -- Auction House session is gone. The SENT window is deliberately left alone: that budget is
  -- a promise to Blizzard's throttle, which does not forget on AH close.
  function obj:Clear()
    for i = #items, 1, -1 do items[i] = nil end
    for k in pairs(queued) do queued[k] = nil end
    for itemID in pairs(queuedItems) do queuedItems[itemID] = nil end
    nextExpiryAt = math.huge
  end

  return obj
end
