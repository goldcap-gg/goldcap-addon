local helper = require("spec.spec_helper")

describe("BookPass", function()
  local GC
  local now, sent, browseResults, hasFullResults
  local hits, rowsEmitted, passesDone

  local function row(itemID, minPrice, totalQuantity)
    return { itemKey = { itemID = itemID }, minPrice = minPrice, totalQuantity = totalQuantity }
  end

  local function fakeDriver()
    return {
      now = function() return now end,
      isReady = function() return sent.ready end,
      sendBrowseQuery = function(query) sent.queries[#sent.queries + 1] = query end,
      requestMoreBrowseResults = function() sent.pages = sent.pages + 1 end,
      hasFullBrowseResults = function() return hasFullResults end,
      getBrowseResults = function() return browseResults end,
      triggerFor = function(itemID) return sent.triggers[itemID] end,
      onHit = function(hit) hits[#hits + 1] = hit end,
      onRows = function(tail, total) rowsEmitted[#rowsEmitted + 1] = { tail = tail, total = total } end,
      onPassDone = function(info) passesDone[#passesDone + 1] = info end,
    }
  end

  before_each(function()
    GC = helper.loadModule("Core/BookPass.lua")
    now = 1000
    browseResults, hasFullResults = {}, false
    hits, rowsEmitted, passesDone = {}, {}, {}
    sent = { ready = true, queries = {}, pages = 0, triggers = {} }
  end)

  local function newPass(opts)
    return GC.BookPass.New(fakeDriver(), opts)
  end

  -- Start() never sends. The arbiter (UI/SniperFrame.lua's OnThrottleReady) is the single
  -- sender for every consumer of the one throttled search slot, and a pass that sent its own
  -- first query took that slot before the arbiter could weigh it against anything else.
  it("sends the caller's filtered query on the grant after Start, never from Start itself", function()
    local bp = newPass({ itemClassFilters = { { classID = 7 } } })
    bp:Start("classes")
    assert.equal(0, #sent.queries)
    assert.is_true(bp:OnThrottleReady())
    assert.equal(1, #sent.queries)
    assert.same({ { classID = 7 } }, sent.queries[1].itemClassFilters)
  end)

  it("sends an empty itemClassFilters query for a wide pass", function()
    local bp = newPass({ itemClassFilters = { { classID = 7 } } })
    bp:Start("wide")
    bp:OnThrottleReady()
    assert.same({}, sent.queries[1].itemClassFilters)
  end)

  it("waits for a grant even when the throttle is ready at Start time", function()
    sent.ready = true
    local bp = newPass()
    bp:Start("classes")
    assert.equal(0, #sent.queries)
    assert.is_true(bp:OnThrottleReady())
    assert.equal(1, #sent.queries)
    assert.is_false(bp:OnThrottleReady()) -- nothing else pending
  end)

  -- A pending page rides the browse event that answers it; a pending START may have nothing
  -- coming at all, so the caller nudges the arbiter for that one case (UI/SniperFrame.lua's
  -- 0.25s ticker) and needs to be able to tell the two apart.
  it("reports a pending start separately from a pending page", function()
    local bp = newPass()
    assert.is_false(bp:PendingStart())
    bp:Start("classes")
    assert.is_true(bp:PendingStart())
    bp:OnThrottleReady()
    assert.is_false(bp:PendingStart())
    browseResults, hasFullResults = { row(1, 10, 1) }, false
    bp:OnResultsUpdated()
    assert.is_true(bp:Wants())
    assert.is_false(bp:PendingStart()) -- a page, not a start
  end)

  -- Wants() answers without spending: the arbiter has to know whether the pass is hungry
  -- before it decides whose turn it is, and asking by trying would be the turn itself.
  it("wants a slot while a start or a page is pending, and not otherwise", function()
    local bp = newPass()
    assert.is_false(bp:Wants())
    bp:Start("classes")
    assert.is_true(bp:Wants())          -- the start
    bp:OnThrottleReady()
    assert.is_false(bp:Wants())
    browseResults, hasFullResults = { row(1, 10, 1) }, false
    bp:OnResultsUpdated()
    assert.is_true(bp:Wants())          -- a page
    bp:OnThrottleReady()
    assert.is_false(bp:Wants())
  end)

  it("seeds the book and hits on the very first sighting below trigger", function()
    sent.triggers[1] = 100
    local bp = newPass()
    bp:Start("classes")
    browseResults, hasFullResults = { row(1, 90, 10) }, true
    bp:OnResultsUpdated()
    assert.equal(1, #hits)
    assert.equal(1, hits[1].itemID)
    assert.equal(90, hits[1].floor)
    assert.is_nil(hits[1].prev)
  end)

  it("never hits an item at or above its trigger", function()
    sent.triggers[1] = 100
    local bp = newPass()
    bp:Start("classes")
    browseResults, hasFullResults = { row(1, 100, 10) }, true -- floor == trigger
    bp:OnResultsUpdated()
    assert.equal(0, #hits)
  end)

  it("never hits an item with no trigger at all", function()
    local bp = newPass() -- sent.triggers stays empty -> triggerFor always nil
    bp:Start("classes")
    browseResults, hasFullResults = { row(1, 1, 10) }, true
    bp:OnResultsUpdated()
    assert.equal(0, #hits)
  end)

  it("does not hit an already-seen item at the same floor and an unchanged quantity", function()
    sent.triggers[1] = 100
    local bp = newPass()
    bp:Start("classes")
    browseResults = { row(1, 90, 10) }
    bp:OnResultsUpdated() -- seeds, hits once
    bp:Start("classes")
    browseResults, hasFullResults = { row(1, 90, 10) }, true -- identical reading
    bp:OnResultsUpdated()
    assert.equal(1, #hits)
  end)

  it("hits again when the floor changes, even upward, as long as it stays below trigger", function()
    sent.triggers[1] = 100
    local bp = newPass()
    bp:Start("classes")
    browseResults = { row(1, 80, 10) }
    bp:OnResultsUpdated()
    bp:Start("classes")
    browseResults, hasFullResults = { row(1, 95, 10) }, true -- rose, still below 100
    bp:OnResultsUpdated()
    assert.equal(2, #hits)
    assert.equal(80, hits[2].prev.floor)
  end)

  it("hits again when quantity grows at the same floor, and not when it only shrinks", function()
    sent.triggers[1] = 100
    local bp = newPass()
    bp:Start("classes")
    browseResults = { row(1, 90, 10) }
    bp:OnResultsUpdated()
    bp:Start("classes")
    browseResults, hasFullResults = { row(1, 90, 5) }, true -- shrank
    bp:OnResultsUpdated()
    assert.equal(1, #hits)
    bp:Start("classes")
    browseResults = { row(1, 90, 40) } -- grew past the original 10
    hasFullResults = true
    bp:OnResultsUpdated()
    assert.equal(2, #hits)
  end)

  it("emits only the new tail rows via onRows across two pages, with the running raw total", function()
    local bp = newPass()
    bp:Start("classes")
    browseResults = { row(1, 10, 1), row(2, 20, 1) }
    bp:OnResultsUpdated()
    assert.equal(2, #rowsEmitted[1].tail)
    assert.equal(2, rowsEmitted[1].total)
    browseResults, hasFullResults = { row(1, 10, 1), row(2, 20, 1), row(3, 30, 1) }, true
    bp:OnResultsAdded()
    assert.equal(1, #rowsEmitted[2].tail)
    assert.equal(3, rowsEmitted[2].total)
    assert.equal(3, rowsEmitted[2].tail[1].itemKey.itemID)
  end)

  it("requests the next page only once OnThrottleReady is called, and only when one is due", function()
    local bp = newPass()
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults, hasFullResults = { row(1, 10, 1) }, false
    bp:OnResultsUpdated() -- not the final page -> a page becomes due
    -- The results event itself sends nothing, whatever the throttle says: the browse event is
    -- where the slot used to be taken out from under everyone else.
    sent.ready = true
    assert.equal(0, sent.pages)
    assert.is_true(bp:OnThrottleReady())
    assert.equal(1, sent.pages)
    assert.is_false(bp:OnThrottleReady()) -- nothing pending right now
  end)

  it("finishes the pass and reports onPassDone once HasFullBrowseResults is true", function()
    local bp = newPass()
    bp:Start("classes")
    browseResults, hasFullResults = { row(1, 10, 1), row(2, 20, 1) }, true
    now = 1007
    bp:OnResultsUpdated()
    assert.equal(1, #passesDone)
    assert.equal("classes", passesDone[1].kind)
    assert.equal(1, passesDone[1].pages)
    assert.equal(2, passesDone[1].items)
    assert.equal(7, passesDone[1].seconds)
    assert.is_false(bp:IsPaging())
  end)

  it("aborts mid-pass: IsPaging goes false and a pending page is never sent afterward", function()
    local bp = newPass()
    bp:Start("classes")
    browseResults, hasFullResults = { row(1, 10, 1) }, false
    bp:OnResultsUpdated() -- a page becomes due
    bp:Abort()
    assert.is_false(bp:IsPaging())
    assert.is_false(bp:OnThrottleReady())
    assert.equal(0, sent.pages)
  end)

  it("keeps its book across an abort, so the next pass's ratchet is against real history", function()
    sent.triggers[1] = 100
    local bp = newPass()
    bp:Start("classes")
    browseResults = { row(1, 90, 10) }
    bp:OnResultsUpdated() -- seeds and hits
    bp:Abort()
    bp:Start("classes")
    browseResults, hasFullResults = { row(1, 90, 10) }, true -- unchanged from before the abort
    bp:OnResultsUpdated()
    assert.equal(1, #hits) -- no second hit: the book remembered the abort's reading
  end)

  it("is not due for a wide pass immediately after construction", function()
    local bp = newPass()
    assert.is_false(bp:IsWidePassDue())
  end)

  it("does not advance the wide-pass clock if Start('wide') is deferred and then aborted before firing", function()
    local bp = newPass({ widePassSeconds = 300 })
    now = 1000
    bp:Start("wide") -- pending, never sent
    now = 1300 + 1 -- 300+ seconds after construction
    bp:Abort() -- killed before OnThrottleReady grants a slot
    assert.is_true(bp:IsWidePassDue()) -- still due: pass never fired, clock unchanged
  end)

  describe("Reset", function()
    it("re-seeds the book, so the next pass hits everything below trigger again", function()
      local bp = newPass()
      sent.triggers[1] = 100
      browseResults, hasFullResults = { row(1, 50, 5) }, true
      bp:Start("classes")
      bp:OnResultsUpdated()
      assert.equal(1, #hits)

      -- Without the reset this is the "already seen at the same floor" case, and the second
      -- pass says nothing at all.
      bp:Reset()
      hits = {}
      bp:Start("classes")
      bp:OnResultsUpdated()
      assert.equal(1, #hits)
      assert.equal(50, hits[1].floor)
      assert.is_nil(hits[1].prev) -- a first sighting again, not a change against a stale book
    end)

    it("clears the paging state so a half-finished pass cannot resume", function()
      local bp = newPass()
      hasFullResults = false
      bp:Start("classes")
      assert.is_true(bp:IsPaging())
      bp:Reset()
      assert.is_false(bp:IsPaging())
      sent.pages = 0
      assert.is_false(bp:OnThrottleReady())
      assert.equal(0, sent.pages)
    end)

    it("leaves the wide-pass clock alone", function()
      local bp = newPass({ widePassSeconds = 300 })
      now = 1000 + 299
      bp:Reset()
      assert.is_false(bp:IsWidePassDue()) -- the clock still runs from construction
      now = 1000 + 300
      assert.is_true(bp:IsWidePassDue())
    end)
  end)

  describe("SeenByClasses", function()
    it("is true for an item folded by a classes pass", function()
      local bp = newPass()
      bp:Start("classes")
      browseResults, hasFullResults = { row(1, 90, 10) }, true
      bp:OnResultsUpdated()
      assert.is_true(bp:SeenByClasses(1))
    end)

    it("is false for an item only ever folded by a wide pass", function()
      local bp = newPass()
      bp:Start("wide")
      browseResults, hasFullResults = { row(1, 90, 10) }, true
      bp:OnResultsUpdated()
      assert.is_false(bp:SeenByClasses(1))
    end)

    it("goes false again after Reset", function()
      local bp = newPass()
      bp:Start("classes")
      browseResults, hasFullResults = { row(1, 90, 10) }, true
      bp:OnResultsUpdated()
      assert.is_true(bp:SeenByClasses(1))
      bp:Reset()
      assert.is_false(bp:SeenByClasses(1))
    end)
  end)

  it("resets the wide-pass clock only when a wide pass actually completes", function()
    local bp = newPass({ widePassSeconds = 300 })
    now = 1000
    assert.is_false(bp:IsWidePassDue())
    now = 1000 + 300
    assert.is_true(bp:IsWidePassDue()) -- due after 300s
    bp:Start("wide")
    browseResults, hasFullResults = { row(1, 10, 1) }, true
    bp:OnResultsUpdated() -- completes the wide pass -> clock resets
    assert.is_false(bp:IsWidePassDue()) -- clock just reset via finishPass
    now = 1000 + 600
    assert.is_true(bp:IsWidePassDue()) -- due again after another 300s
  end)

  describe("re-hits (whole-market coverage)", function()
    local function passOf(rows, bp)
      browseResults = rows
      bp:Start("classes")
      bp:OnThrottleReady()
      bp:OnResultsUpdated()
    end

    it("reports an unchanged floor again once the queue lost it, no sooner than rehitSeconds after the last report", function()
      sent.triggers[1] = 1000
      local bp = newPass({ rehitSeconds = 120 })
      passOf({ row(1, 500, 10) }, bp)
      assert.equal(1, #hits)
      bp:Lost(1, 500)
      now = 1000 + 60
      passOf({ row(1, 500, 10) }, bp)
      assert.equal(1, #hits)            -- lost, but only 60 s since it was reported
      now = 1000 + 120
      passOf({ row(1, 500, 10) }, bp)
      assert.equal(2, #hits)            -- lost, and 120 s on: reported again
      assert.is_true(hits[2].rehit)
      assert.equal(1, bp:Rehits())
      now = 1000 + 400
      passOf({ row(1, 500, 10) }, bp)
      assert.equal(2, #hits)            -- not lost again since: silent, as before
    end)

    it("still reports a floor that moved at once, lost or not", function()
      sent.triggers[1] = 1000
      local bp = newPass({ rehitSeconds = 120 })
      passOf({ row(1, 500, 10) }, bp)
      bp:Lost(1, 500)
      now = 1000 + 5
      passOf({ row(1, 490, 10) }, bp)
      assert.equal(2, #hits)
      assert.is_nil(hits[2].rehit)
      assert.equal(0, bp:Rehits())
    end)

    it("never re-reports an unchanged floor nobody lost", function()
      sent.triggers[1] = 1000
      local bp = newPass({ rehitSeconds = 120 })
      passOf({ row(1, 500, 10) }, bp)
      now = 1000 + 600
      passOf({ row(1, 500, 10) }, bp)
      assert.equal(1, #hits)
    end)

    -- Fix round 1 (m2): an entry for a floor the book has moved off can age out in the queue after
    -- the new floor's hit was drilled. That loss says nothing about the floor on offer now.
    it("ignores a loss of a floor the book no longer shows", function()
      sent.triggers[1] = 1000
      local bp = newPass({ rehitSeconds = 120 })
      passOf({ row(1, 500, 10) }, bp)
      now = 1000 + 10
      passOf({ row(1, 490, 10) }, bp)
      assert.equal(2, #hits)
      bp:Lost(1, 500)                   -- the 500 entry aged out; 490 is what the book shows
      now = 1000 + 400
      passOf({ row(1, 490, 10) }, bp)
      assert.equal(2, #hits)
      bp:Lost(1, 490)
      now = 1000 + 401
      passOf({ row(1, 490, 10) }, bp)
      assert.equal(3, #hits)
      assert.is_true(hits[3].rehit)
    end)

    it("forgets what it lost when the auction house closes", function()
      sent.triggers[1] = 1000
      local bp = newPass({ rehitSeconds = 120 })
      passOf({ row(1, 500, 10) }, bp)
      bp:Lost(1, 500)
      bp:Reset()
      now = 1000 + 5
      passOf({ row(1, 500, 10) }, bp)  -- the first sighting after a reset reports, as always
      assert.equal(2, #hits)
      assert.is_nil(hits[2].rehit)
    end)

    -- Fix round 1 (m5): Reset also empties the book, so the next sighting is a first one whatever
    -- `lost` still holds -- the test above cannot tell. Read the two tables Reset must empty.
    it("empties its loss and report memory on Reset", function()
      local function upvalue(fn, wanted)
        for i = 1, math.huge do
          local name, value = debug.getupvalue(fn, i)
          if not name then break end
          if name == wanted then return value end
        end
        error("missing upvalue " .. wanted)
      end
      sent.triggers[1] = 1000
      local bp = newPass({ rehitSeconds = 120 })
      passOf({ row(1, 500, 10) }, bp)
      bp:Lost(1, 500)
      -- From the closures that use them, not from Reset's own: a Reset that stopped touching them
      -- must fail the assertions below, not the lookup.
      local lost = upvalue(bp.Lost, "lost")
      local foldRow = upvalue(upvalue(bp.OnResultsUpdated, "handleResults"), "foldRow")
      local reportedAt = upvalue(foldRow, "reportedAt")
      assert.is_true(lost[1])
      assert.equal(1000, reportedAt[1])
      bp:Reset()
      assert.is_nil(next(lost))
      assert.is_nil(next(reportedAt))
    end)
  end)

  it("keeps what it saw in the last seenSeconds readable across Reset, for the tooltip", function()
    local bp = newPass({ seenSeconds = 900 })
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(1, 500, 7) }
    bp:OnResultsUpdated()            -- folded at now = 1000
    now = 1500
    bp:Reset()
    assert.is_nil(bp:Book()[1])
    assert.same({ floor = 500, qty = 7, seenAt = 1000, kind = "classes" }, bp:Seen(1))
    now = 1000 + 900
    bp:Reset()
    assert.is_nil(bp:Seen(1))
  end)

  it("keeps nothing across Reset by default", function()
    local bp = newPass()
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(1, 500, 7) }
    bp:OnResultsUpdated()
    assert.equal(500, bp:Seen(1).floor)
    bp:Reset()
    assert.is_nil(bp:Seen(1))
  end)

  it("answers Seen from this session's book before anything carried over Reset", function()
    local bp = newPass({ seenSeconds = 900 })
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(1, 500, 7) }
    bp:OnResultsUpdated()
    now = 1100
    bp:Reset()
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(1, 450, 9) }
    bp:OnResultsUpdated()
    assert.same({ floor = 450, qty = 9, seenAt = 1100, kind = "classes" }, bp:Seen(1))
  end)

  -- The book is keyed by item, the browse list by item KEY: a piece of gear comes back as one row
  -- per item level, and every caged pet as item 82800 with its own species. The book row is
  -- whichever of them was folded last, so it is marked, and the tooltip does not print it as the
  -- item's price (UI/SniperFrame.lua's LiveFloor).
  it("marks an item that came back as more than one variant, and keeps the mark for the visit", function()
    local function variantRow(itemID, minPrice, qty, itemLevel)
      return { itemKey = { itemID = itemID, itemLevel = itemLevel }, minPrice = minPrice, totalQuantity = qty }
    end
    local bp = newPass({ seenSeconds = 900 })
    bp:Start("wide")
    bp:OnThrottleReady()
    browseResults = { variantRow(5, 900, 1, 606), variantRow(6, 300, 2, 600), variantRow(5, 70000, 1, 623) }
    bp:OnResultsUpdated()
    assert.is_true(bp:Seen(5).variants)
    assert.is_nil(bp:Seen(6).variants)
    -- The next pass's first row of the item does not make it a single-variant item again.
    bp:Start("wide")
    bp:OnThrottleReady()
    browseResults = { variantRow(5, 900, 1, 606) }
    bp:OnResultsUpdated()
    assert.is_true(bp:Seen(5).variants)
    -- Final review M1: nothing would print a variant's row, so it is not carried over the close.
    now = 1100
    bp:Reset()
    assert.is_nil(bp:Seen(5))
    assert.equal(300, bp:Seen(6).floor)
  end)

  -- Every caged pet is item 82800 with its own species: a pet row is one species of the cage, never
  -- the cage's floor, even when it is the only one the pass has met so far.
  it("marks a caged pet as one of its variants from its first row", function()
    local bp = newPass({ seenSeconds = 900 })
    bp:Start("wide")
    bp:OnThrottleReady()
    browseResults = { { itemKey = { itemID = 82800, battlePetSpeciesID = 1234 }, minPrice = 5000,
      totalQuantity = 1 } }
    bp:OnResultsUpdated()
    assert.is_true(bp:Seen(82800).variants)
  end)

  -- Final review M1: Reset used to carry every row of the last book, tens of thousands on a big realm,
  -- for the rest of the session. Only a row the tooltip could print is worth the memory.
  it("carries over Reset only the rows the driver would tell", function()
    local driver = fakeDriver()
    driver.keepSeen = function(itemID, kept)
      assert.equal("number", type(kept.floor))
      return itemID ~= 2
    end
    local bp = GC.BookPass.New(driver, { seenSeconds = 900 })
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(1, 500, 7), row(2, 600, 8) }
    bp:OnResultsUpdated()
    now = 1100
    bp:Reset()
    assert.equal(500, bp:Seen(1).floor)
    assert.is_nil(bp:Seen(2))
  end)

  -- What Reset carried over, read off Seen's own upvalue.
  local function recentOf(bp)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(bp.Seen, i)
      if not name then break end
      if name == "recent" then return value end
    end
    error("missing upvalue recent")
  end

  -- ... and it goes once it can no longer answer: a Start lets go of every carried row past the
  -- window, and of every one this visit's book has seen again (Seen answers from the book first).
  it("lets go at Start of carried rows past the window, and of rows the book has seen again", function()
    local bp = newPass({ seenSeconds = 900 })
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(1, 500, 7), row(2, 600, 8) }
    bp:OnResultsUpdated()                 -- seenAt 1000
    now = 1200
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(1, 500, 7), row(2, 600, 8), row(3, 700, 9) }
    bp:OnResultsUpdated()
    bp:Reset()                            -- carries 1, 2 and 3, all seen at 1200
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(2, 650, 8) }
    bp:OnResultsUpdated()                 -- the new visit's book sees 2 again
    local recent = recentOf(bp)
    assert.equal(600, recent[2].floor)    -- not yet: let go at the NEXT Start
    now = 1200 + 899
    bp:Start("classes")
    recent = recentOf(bp)
    assert.is_nil(recent[2])
    assert.equal(500, recent[1].floor)
    now = 1200 + 900
    bp:Start("classes")
    recent = recentOf(bp)
    assert.is_nil(next(recent))
    assert.equal(650, bp:Seen(2).floor)   -- the book's row is untouched
  end)

  -- The close path schedules this for LIVE_TOOLTIP_SECONDS after the close (UI/SniperFrame.lua): by
  -- then every row that close carried is past the window. A later close's rows are not, and the book
  -- of a visit open when it fires is never touched.
  it("Prune lets go of what the window no longer covers, and never touches the book", function()
    local bp = newPass({ seenSeconds = 900 })
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(1, 500, 7) }
    bp:OnResultsUpdated()                 -- seenAt 1000
    bp:Reset()                            -- first close, at 1000
    now = 1300
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(2, 600, 8) }
    bp:OnResultsUpdated()                 -- seenAt 1300
    bp:Reset()                            -- second close, at 1300
    now = 1400
    bp:Start("classes")
    bp:OnThrottleReady()
    browseResults = { row(3, 700, 9) }
    bp:OnResultsUpdated()                 -- a third visit, open when the first close's timer fires
    now = 1000 + 900
    bp:Prune()
    assert.is_nil(bp:Seen(1))
    assert.equal(600, bp:Seen(2).floor)
    assert.equal(700, bp:Seen(3).floor)
    assert.equal(700, bp:Book()[3].floor)
  end)

  -- Gear the auction house lists at ONE item level is never marked above, so the row keeps the level
  -- it was listed at: the reader (UI/SniperFrame.lua's LiveFloor) refuses a leveled row of anything
  -- that is not a commodity, whatever level the player's own copy is.
  it("keeps the item level of the row it kept, for gear listed at one level", function()
    local bp = newPass({ seenSeconds = 900 })
    bp:Start("wide")
    bp:OnThrottleReady()
    browseResults = { { itemKey = { itemID = 6, itemLevel = 600 }, minPrice = 300, totalQuantity = 2 },
      row(7, 500, 9) }
    bp:OnResultsUpdated()
    assert.is_nil(bp:Seen(6).variants)
    assert.equal(600, bp:Seen(6).itemLevel)
    assert.is_nil(bp:Seen(7).itemLevel)
  end)
end)
