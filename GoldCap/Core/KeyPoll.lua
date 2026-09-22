local _, GC = ...

-- Sniper phase 2 (docs/superpowers/specs/2026-09-10-sniper-phase2-realm-items-design.md):
-- the realm-item counterpart of Core/BookPass.lua. A browse pass sweeps whatever the auction
-- house feels like returning; this one asks about a NAMED set of items -- the player's pins,
-- the site watchlist and the region's own list of realm items worth watching -- through
-- C_AuctionHouse.SearchForItemKeys, which answers with the same browse rows a pass produces.
--
-- Pure and driver-injected like every module in this batch: no WoW API call lives here. The
-- caller (UI/SniperFrame.lua) owns the item keys, the throttle slot and what a hit means;
-- this module owns "which 100 ids go out next" and "is this row news or the same thing we
-- already knew". driver = { now, triggerFor, onHit, onRows }.
--
-- One cycle = one visit to every target. HasPending() stays true until the whole set has been
-- handed out once since BeginCycle(), which the arbiter calls when a fresh book pass starts,
-- so the keys traffic paces itself against the pass loop instead of running flat out.
GC.KeyPoll = {}

-- Blizzard's documented ceiling for one SearchForItemKeys call. More than this disconnects
-- the client -- it is a hard cap, not a tuning knob, so opts.maxBatch may lower it and never
-- raise it (the specs use a small batch to exercise the round-robin without 100 ids).
local MAX_BATCH = 100

function GC.KeyPoll.New(driver, opts)
  opts = opts or {}
  local maxBatch = opts.maxBatch or MAX_BATCH
  if maxBatch > MAX_BATCH then maxBatch = MAX_BATCH end
  if maxBatch < 1 then maxBatch = 1 end

  local obj = {}
  local targets = {}    -- ascending itemIDs; the whole poll set
  local signature = ""  -- what `targets` holds right now, so an unchanged rebuild is a no-op
  local cursor = 1      -- index of the next id to hand out, wrapping
  local handed = 0      -- ids handed out since the last BeginCycle
  local book = {}       -- itemID -> { floor, qty, seenAt }; what each target last looked like

  -- Replaces the poll set. Deduplicated and sorted so the round-robin visits items in the
  -- same order every session. Returns whether anything actually changed: a set identical to
  -- the current one leaves the cursor and the cycle exactly where they were, which is what
  -- lets the caller rebuild freely (every pin toggle, every import) without a half-finished
  -- cycle restarting from the top each time.
  function obj:SetTargets(ids)
    local seen, next_ = {}, {}
    for i = 1, #(ids or {}) do
      local id = ids[i]
      if type(id) == "number" and id > 0 and not seen[id] then
        seen[id] = true
        next_[#next_ + 1] = id
      end
    end
    table.sort(next_)
    local nextSignature = table.concat(next_, ",")
    if nextSignature == signature then return false end
    targets = next_
    signature = nextSignature
    cursor = 1
    handed = 0
    return true
  end

  function obj:Count() return #targets end

  -- Marks the start of a cycle: every target is owed one visit again. Called at book-pass
  -- start, so a cycle of keys traffic is bounded by the pass loop rather than by a clock.
  function obj:BeginCycle() handed = 0 end

  function obj:HasPending() return #targets > 0 and handed < #targets end

  -- The next batch of item ids, at most maxBatch of them, or nil when this cycle has already
  -- visited every target. The cursor wraps, so a set that does not divide evenly into batches
  -- still visits every member exactly once per cycle.
  function obj:NextBatch()
    if not obj:HasPending() then return nil end
    local total = #targets
    local take = math.min(maxBatch, total - handed)
    local batch = {}
    for _ = 1, take do
      if cursor > total then cursor = 1 end
      batch[#batch + 1] = targets[cursor]
      cursor = cursor + 1
    end
    handed = handed + take
    return batch
  end

  -- Final review: SearchForItemKeys may answer with ONE row per item-level variant of an item,
  -- and it may answer with one row for the whole item group. Both shapes are legal and the
  -- client is contractually neither, so this module refuses to depend on the answer: several
  -- rows for one itemID become one row carrying the cheapest floor on offer and the whole
  -- quantity behind it, before anything downstream looks at them.
  --
  -- Folded row by row instead, the variant shape made the book flip between variants on every
  -- batch, so the ratchet below read noise as news; the arbiter's own `booked.floor ==
  -- hit.floor` re-check then dropped the drill that very hit had just queued; and the caller's
  -- own floor-per-item map (UI/SniperFrame.lua's onRows) took whichever variant came last.
  --
  -- The client's result rows are never written into: the first duplicate turns the kept entry
  -- into a copy of our own, and rows with no itemID at all are passed through untouched for the
  -- fold below to ignore exactly as it always has.
  local function collapse(rows)
    local out, index, owned = {}, {}, {}
    for i = 1, #rows do
      local row = rows[i]
      local itemID = row.itemKey and row.itemKey.itemID
      local at = itemID and index[itemID]
      if not at then
        if itemID then index[itemID] = #out + 1 end
        out[#out + 1] = row
      else
        local kept = out[at]
        if not owned[at] then
          local copy = {}
          for k, v in pairs(kept) do copy[k] = v end
          kept, out[at], owned[at] = copy, copy, true
        end
        if row.minPrice and (not kept.minPrice or row.minPrice < kept.minPrice) then
          kept.minPrice = row.minPrice
        end
        kept.totalQuantity = (kept.totalQuantity or 0) + (row.totalQuantity or 0)
      end
    end
    return out
  end

  -- Folds one keys result into the book. Same ratchet as BookPass.foldRow, deliberately: a
  -- hit is a floor UNDER the item's trigger that is also news -- a price that moved, a stack
  -- that grew, or an item nobody has seen this session. Without it every batch would re-report
  -- the same unsold lot every cycle, and the drill queue would spend its whole budget
  -- re-confirming listings nothing has happened to.
  function obj:Fold(rows)
    rows = collapse(rows or {})
    for i = 1, #rows do
      local row = rows[i]
      local itemKey = row.itemKey
      local itemID = itemKey and itemKey.itemID
      local floor = row.minPrice
      if itemID and floor and floor > 0 then
        local qty = row.totalQuantity
        local prev = book[itemID]
        local trigger = driver.triggerFor(itemID)
        local hit = trigger and floor < trigger
          and (not prev or prev.floor ~= floor or (qty or 0) > (prev.qty or 0))
        book[itemID] = { floor = floor, qty = qty, seenAt = driver.now() }
        if hit then
          driver.onHit({ itemID = itemID, floor = floor, qty = qty, prev = prev })
        end
      end
    end
    if driver.onRows then driver.onRows(rows) end
  end

  function obj:Book() return book end

  -- The book is a claim about one Auction House session's listings and does not outlive it,
  -- exactly as in BookPass: kept across the close, the first batch of the next session would
  -- say nothing about every item whose price has not moved since. The TARGET set is not
  -- session state -- it comes from the import and the player's pins -- so it survives, and
  -- the cycle simply starts over.
  function obj:Reset()
    for itemID in pairs(book) do book[itemID] = nil end
    cursor = 1
    handed = 0
  end

  return obj
end
