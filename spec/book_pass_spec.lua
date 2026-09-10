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

  it("sends the caller's filtered query on Start when the throttle is ready", function()
    local bp = newPass({ itemClassFilters = { { classID = 7 } } })
    bp:Start("classes")
    assert.equal(1, #sent.queries)
    assert.same({ { classID = 7 } }, sent.queries[1].itemClassFilters)
  end)

  it("sends an empty itemClassFilters query for a wide pass", function()
    local bp = newPass({ itemClassFilters = { { classID = 7 } } })
    bp:Start("wide")
    assert.same({}, sent.queries[1].itemClassFilters)
  end)

  it("defers the send until OnThrottleReady when the throttle is not ready", function()
    sent.ready = false
    local bp = newPass()
    bp:Start("classes")
    assert.equal(0, #sent.queries)
    assert.is_true(bp:OnThrottleReady())
    assert.equal(1, #sent.queries)
    assert.is_false(bp:OnThrottleReady()) -- nothing else pending
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
    browseResults, hasFullResults = { row(1, 10, 1) }, false
    bp:OnResultsUpdated() -- not the final page -> a page becomes due
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

  it("is not due for a wide pass immediately after construction", function()
    local bp = newPass()
    assert.is_false(bp:IsWidePassDue())
  end)

  it("does not advance the wide-pass clock if Start('wide') is deferred and then aborted before firing", function()
    local bp = newPass({ widePassSeconds = 300 })
    sent.ready = false
    now = 1000
    bp:Start("wide") -- deferred, not sent
    now = 1300 + 1 -- 300+ seconds after construction
    bp:Abort() -- killed before OnThrottleReady grants a slot
    assert.is_true(bp:IsWidePassDue()) -- still due: pass never fired, clock unchanged
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
end)
