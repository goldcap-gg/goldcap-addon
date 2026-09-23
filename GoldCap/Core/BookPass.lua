local _, GC = ...

-- Sniper fast loop, phase 1 (design doc §1 Book pass): a pure state machine over an injected
-- driver, like Core/AutoScan.lua -- no WoW API calls live here. Pages one SendBrowseQuery to
-- completion (HasFullBrowseResults), folding every row into
-- book[itemID] = { floor, qty, seenAt } and firing driver.onHit for anything that crosses
-- below its trigger. The caller (UI/SniperFrame.lua) owns the query's itemClassFilters (an
-- Enum lookup, a WoW global this module never touches), the trigger formula
-- (Core/Trigger.lua) and what happens with a hit or a row -- this module only knows "paging"
-- vs "not", and "the book says X changed" vs "the book says X is the same as last time".
--
-- It also never decides WHEN to send. Both of its sends -- the opening query and each next
-- page -- happen only inside OnThrottleReady, so the caller's arbiter is the single allocator
-- of the client's one throttled search slot; see obj:Start and obj:Wants below.
GC.BookPass = {}

function GC.BookPass.New(driver, opts)
  opts = opts or {}
  local widePassSeconds = opts.widePassSeconds or 300
  -- Whole-market coverage: how soon an unchanged floor whose hit the drill queue let go of
  -- undrilled (obj:Lost) may be reported again. A moved floor is reported at once, as always.
  local rehitSeconds = opts.rehitSeconds or 120
  local classFilters = opts.itemClassFilters or {}

  local obj = {}
  local book = {}          -- itemID -> { floor, qty, seenAt, kind }; SURVIVES Abort() and every Start()
  local classesSeen = {}   -- itemID -> true, for any item EVER folded by a classes pass this
                            -- session (survives Abort()/Start(), cleared only by Reset())
  local lost = {}          -- itemID -> true: its last hit left the drill queue undrilled (obj:Lost)
  local reportedAt = {}    -- itemID -> driver.now() of its last hit
  local rehits = 0         -- hits reported again after a loss, this session (/gc board)
  local kind = nil         -- nil | "classes" | "wide"
  local paging = false
  local pendingStart = false
  local pendingPage = false
  local rawWatermark = 0   -- #driver.getBrowseResults() already folded/emitted THIS pass
  local pagesThisPass = 0
  local passStartedAt = nil
  -- The clock starts at construction, not at the first pass: an untouched addon load must
  -- not force the very first pass (right after the AH opens, when speed matters most) to be
  -- the slow unfiltered one.
  local lastWideAt = driver.now()

  local function queryFor(k)
    if k == "wide" then
      return { searchString = "", sorts = {}, filters = {}, itemClassFilters = {} }
    end
    return { searchString = "", sorts = {}, filters = {}, itemClassFilters = classFilters }
  end

  -- Hit = floor < trigger AND (floor changed since the previous pass OR qty grew). The first
  -- sighting of an item ever (prev == nil) counts as "changed": it seeds the book AND hits,
  -- per the design doc's "the first pass ... emits hits for everything below trigger".
  -- Whole-market coverage: an unchanged floor is news again once the drill queue has let its last
  -- hit go undrilled (obj:Lost) -- at most once per rehitSeconds, so a queue that keeps refusing an
  -- item is not handed it on every 7-14 s pass.
  local function foldRow(row)
    local itemKey = row.itemKey
    local itemID = itemKey and itemKey.itemID
    local floor = row.minPrice
    if not itemID or not floor or floor <= 0 then return end
    local qty = row.totalQuantity
    local prev = book[itemID]
    local now = driver.now()
    local trigger = driver.triggerFor(itemID)
    local changed = not prev or prev.floor ~= floor or (qty or 0) > (prev.qty or 0)
    local again = not changed and lost[itemID] == true
      and (now - (reportedAt[itemID] or 0)) >= rehitSeconds
    local hit = trigger and floor < trigger and (changed or again)
    book[itemID] = { floor = floor, qty = qty, seenAt = now, kind = kind }
    if kind == "classes" then classesSeen[itemID] = true end
    if hit then
      lost[itemID] = nil
      reportedAt[itemID] = now
      if again then rehits = rehits + 1 end
      driver.onHit({ itemID = itemID, floor = floor, qty = qty, prev = prev, rehit = again or nil })
    end
  end

  local function finishPass()
    paging = false
    if kind == "wide" then lastWideAt = driver.now() end
    driver.onPassDone({ kind = kind, pages = pagesThisPass, items = rawWatermark,
      seconds = passStartedAt and (driver.now() - passStartedAt) or 0 })
    kind = nil
  end

  local function handleResults()
    if not paging then return end
    pagesThisPass = pagesThisPass + 1
    local results = driver.getBrowseResults()
    local tail = {}
    for i = rawWatermark + 1, #results do tail[#tail + 1] = results[i] end
    rawWatermark = #results
    for i = 1, #tail do foldRow(tail[i]) end
    driver.onRows(tail, rawWatermark)
    if driver.hasFullBrowseResults() then
      finishPass()
    else
      pendingPage = true
    end
  end

  -- Start ARMS a pass; it never sends one. There is a single throttled search slot and the
  -- arbiter (UI/SniperFrame.lua's OnThrottleReady) is its only allocator -- a pass that sent
  -- its own first query the moment the throttle happened to be ready took that slot before
  -- the arbiter could weigh it against a drill-down, the watch loop or the verify walk. With
  -- Auto's two-second breather the pass is armed again almost immediately, so "whoever asks
  -- the client first" resolved to "the pass, always", and the checks that judge the rows on
  -- screen only ran once the scan stopped. The caller pokes the arbiter after arming (see
  -- startFullScan) so an idle-but-ready client still starts at once.
  function obj:Start(k)
    kind = k
    paging = true
    pendingStart = true
    pendingPage = false
    rawWatermark = 0
    pagesThisPass = 0
    passStartedAt = driver.now()
  end

  function obj:OnResultsUpdated() handleResults() end
  function obj:OnResultsAdded() handleResults() end

  -- Sends whichever of "the pass hasn't started yet" or "a page is due" is pending, at most
  -- one per call. Returns true only if it actually sent something -- the arbiter's own
  -- contract (see UI/SniperFrame.lua's OnThrottleReady) for every slot consumer in this file.
  function obj:OnThrottleReady()
    if pendingStart then
      pendingStart = false
      driver.sendBrowseQuery(queryFor(kind))
      return true
    end
    if not pendingPage then return false end
    pendingPage = false
    driver.requestMoreBrowseResults()
    return true
  end

  -- Does the pass want the slot? Asked by the arbiter BEFORE it decides whose turn it is --
  -- OnThrottleReady above both answers and acts, so it cannot be the question as well.
  function obj:Wants() return pendingStart or pendingPage end

  -- Narrower: armed and never sent. A pending PAGE always has a browse event behind it and
  -- therefore a throttle-ready event to ride; a pending START may have nothing at all coming,
  -- which is why the caller's ticker nudges the arbiter for this case and only this one.
  function obj:PendingStart() return pendingStart end

  function obj:Abort()
    paging = false
    pendingStart = false
    pendingPage = false
    kind = nil
  end

  -- Everything this module remembers is a claim about one Auction House session's order
  -- book: the book itself (what each item's floor was last time we looked) and whatever pass
  -- was mid-flight. Neither survives the AH closing -- a book kept across the close makes the
  -- first pass of the next session silent about every item whose price has not moved since,
  -- which is exactly the pass that most needs to say something. The wide-pass clock is NOT
  -- reset: it paces an expensive unfiltered pass against wall time, and reopening the AH does
  -- not make one more urgent.
  function obj:Reset()
    for itemID in pairs(book) do book[itemID] = nil end
    for itemID in pairs(classesSeen) do classesSeen[itemID] = nil end
    for itemID in pairs(lost) do lost[itemID] = nil end
    for itemID in pairs(reportedAt) do reportedAt[itemID] = nil end
    kind = nil
    paging = false
    pendingStart = false
    pendingPage = false
    rawWatermark = 0
    pagesThisPass = 0
    passStartedAt = nil
  end

  function obj:IsPaging() return paging end

  function obj:IsWidePassDue()
    return (driver.now() - lastWideAt) >= widePassSeconds
  end

  function obj:Book() return book end

  -- True once an itemID has ever been folded by a CLASSES pass this session (i.e. it is
  -- in-class), regardless of what pass folded it most recently. Distinct from "does the book
  -- have a row for it right now" -- an item can leave the book (Reset) but classesSeen only
  -- clears with it.
  function obj:SeenByClasses(itemID) return classesSeen[itemID] == true end

  -- The drill queue let this item's hit go undrilled (UI/SniperFrame.lua's _OnDrillLost): its
  -- unchanged floor may be reported again, rehitSeconds after the last report.
  function obj:Lost(itemID) lost[itemID] = true end

  function obj:Rehits() return rehits end

  return obj
end
