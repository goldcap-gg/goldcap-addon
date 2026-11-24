local helper = require("spec.spec_helper")

-- DEALS' AUTO readout (Core/AutoReadout.lua): the two lines under the toolbar's square buttons and
-- the block under the AUTO tooltip, from plain state, and the rolling five-minute count. How the lines
-- fit the tabs' row: spec/auto_readout_row_spec.lua.
describe("AUTO readout", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/AutoReadout.lua")
    GC.AutoReadout._Reset()
  end)

  local busy = { finds = 31, checked = 29, deals = 4 }

  -- Each case: the state, then line 1's rungs (longest first, nil for none), line 2's longest rung,
  -- and lines the tooltip must carry.
  local CASES = {
    { what = "retail Commodities mid-pass",
      state = { pass = { page = 14, lapPages = 27, items = 12300, seconds = 21, finds = 6, lastAgo = 9 },
        caps = { count = 407, batch = 2, batches = 5 }, queue = { depth = 3, oldest = 40 }, hot = 2,
        counts = busy, perMinute = 58 },
      now = { "Pass: page 14 of 27 · 12,300 items · lap 21 s", "Pass: page 14 · 12,300 items · lap 21 s",
        "Pass: page 14 · 12,300 items", "Pass: page 14" },
      recent = "5 min: 31 finds · 29 checked · 4 deals · 58 req/min",
      tip = { "Now: Pass: page 14 of 27 · 12,300 items · lap 21 s", "Last lap: 21 s · 12,300 items · 6 finds",
        "Checks waiting: 3 · oldest 40 s", "Your prices: 407 · batch 2 of 5", "Hot items: 2",
        "5 min: 31 finds · 29 checked · 4 deals", "Requests: 58 per minute" } },
    { what = "retail Commodities between passes",
      state = { pass = { items = 12300, seconds = 21, finds = 6, lastAgo = 4 },
        caps = { count = 407, nextIn = 3 }, queue = { depth = 0 }, counts = busy, perMinute = 58 },
      now = { "Last lap 4 s ago · 12,300 items · lap 21 s", "Last lap 4 s ago · 12,300 items", "Last lap 4 s ago" },
      tip = { "Now: Last lap 4 s ago · 12,300 items · lap 21 s", "Checks waiting: 0", "Your prices: 407 · next round in 3 s" } },
    { what = "the first pass, with no lap before it: no \"of N\", no lap figures",
      state = { pass = { page = 3, lapPages = nil }, counts = {}, perMinute = 12 },
      now = { "Pass: page 3" },
      tip = { "Now: Pass: page 3", "Last lap: none yet", "5 min: 0 finds · 0 checked · 0 deals" } },
    { what = "a page past the last lap's count never reads \"page 30 of 27\"",
      state = { pass = { page = 30, lapPages = 27, items = 12300, seconds = 21 } },
      now = { "Pass: page 30 · 12,300 items · lap 21 s", "Pass: page 30 · 12,300 items", "Pass: page 30" } },
    { what = "retail Items board, a round under way",
      state = { items = { targets = 512, round = 4, batch = 2, batches = 6 }, caps = { count = 40, batch = 1, batches = 1 },
        counts = busy, perMinute = 70 },
      now = { "Items: round 4 · batch 2 of 6 · 512 targets", "Items: round 4 · batch 2 of 6", "Items: round 4" },
      tip = { "Items poll: 512 targets · round 4 · batch 2 of 6", "Your prices: 40 · batch 1 of 1" } },
    { what = "retail Items board between rounds",
      state = { items = { targets = 512, round = 4, batch = 6, batches = 6, nextIn = 3.4 } },
      now = { "Items: next round in 3 s · 512 targets", "Items: next round in 3 s" },
      tip = { "Items poll: 512 targets · next round in 3 s" } },
    { what = "WoW: Forever, the full scan running",
      state = { full = { running = true, dueIn = 0 }, pass = { page = 2 }, moved = 18, counts = busy },
      now = { "Full scan running" },
      tip = { "Now: Full scan running", "Full scan: running", "Last pass: 18 new prices on DEALS" } },
    { what = "WoW: Forever, a pass while the next full scan counts down",
      state = { full = { running = false, dueIn = 9 * 60 - 20 }, pass = { page = 5, lapPages = 8, items = 900, seconds = 11 },
        moved = 3 },
      now = { "Pass: page 5 of 8 · 900 items · lap 11 s · full scan in 9 min", "Pass: page 5 of 8 · 900 items · lap 11 s",
        "Pass: page 5 · 900 items · lap 11 s", "Pass: page 5 · 900 items", "Pass: page 5" },
      tip = { "Full scan: in 9 min", "Last pass: 3 new prices on DEALS" } },
    { what = "WoW: Forever, the full scan ready",
      state = { full = { running = false, dueIn = 0 }, pass = { lastAgo = 2, items = 900, seconds = 11 } },
      now = { "Last lap 2 s ago · 900 items · lap 11 s · full scan ready", "Last lap 2 s ago · 900 items · lap 11 s",
        "Last lap 2 s ago · 900 items", "Last lap 2 s ago" },
      tip = { "Full scan: ready" } },
    { what = "WoW: Forever's gear loop on the Items board",
      state = { gear = { armor = true, page = 3, seconds = 41, last = 63 }, full = { running = false, dueIn = 300 } },
      now = { "Armor: page 3 · round 41 s", "Armor: page 3" },
      tip = { "Gear loop: Armor: page 3 · round 41 s", "Full scan: in 5 min" } },
    { what = "the gear loop between rounds",
      state = { gear = { armor = false, page = 0, last = 63 } },
      now = { "Gear loop: last round 63 s" },
      tip = { "Gear loop: last round 63 s" } },
    { what = "AUTO paused: no new line, the last one dims",
      state = { paused = true, pass = { page = 3 } }, dim = true,
      tip = { "Now: paused" } },
    { what = "nothing yet",
      state = { counts = {}, perMinute = 0 },
      now = nil, recent = "5 min: 0 finds · 0 checked · 0 deals · 0 req/min",
      tip = { "Now: waiting", "Requests: 0 per minute" } },
  }

  for _, case in ipairs(CASES) do
    it(case.what, function()
      local lines = GC.AutoReadout.Lines(case.state)
      if case.dim then
        assert.is_true(lines.dim)
        assert.is_nil(lines.now)
        assert.is_nil(lines.recent)
      else
        assert.is_false(lines.dim)
        assert.same(case.now, lines.now)
        if case.recent then assert.equal(case.recent, lines.recent[1]) end
        -- Line 2 drops its least important part first, down to the deals.
        assert.equal(4, #lines.recent)
        assert.truthy(lines.recent[#lines.recent]:find("deals", 1, true))
      end
      local tip = table.concat(GC.AutoReadout.Tooltip(case.state), "\n")
      for _, want in ipairs(case.tip or {}) do
        assert.truthy(tip:find(want, 1, true), ("%q not in:\n%s"):format(want, tip))
      end
    end)
  end

  it("fits the longest rung that is no wider than the room, and none rather than a cut one", function()
    local rungs = { "aaaaaaaa", "aaaa", "aa" }
    local function measure(text) return #text end
    assert.equal("aaaaaaaa", GC.AutoReadout.Fit(rungs, 8, measure))
    assert.equal("aaaa", GC.AutoReadout.Fit(rungs, 7, measure))
    assert.equal("aa", GC.AutoReadout.Fit(rungs, 2, measure))
    assert.is_nil(GC.AutoReadout.Fit(rungs, 1, measure))
    assert.is_nil(GC.AutoReadout.Fit(nil, 100, measure))
  end)

  it("counts finds, checks and deals over the last five minutes", function()
    local AR = GC.AutoReadout
    AR.Note("finds", 100)
    AR.Note("finds", 150)
    AR.Note("checked", 160)
    AR.Note("deals", 170)
    assert.same({ finds = 2, checked = 1, deals = 1 }, AR.Counts(200))
    assert.same({ finds = 1, checked = 1, deals = 1 }, AR.Counts(400)) -- the first find is five minutes old
    assert.same({ finds = 0, checked = 0, deals = 0 }, AR.Counts(470))
  end)
end)

-- What the readout reads, and where its five-minute count is fed.
describe("AUTO readout's sources", function()
  it("a browse pass tells its page and rows while it pages, and nothing between passes", function()
    local GC = helper.loadModule("Core/BookPass.lua")
    local now, results, full, done = 1000, {}, false, nil
    local pass = GC.BookPass.New({
      now = function() return now end,
      sendBrowseQuery = function() end, requestMoreBrowseResults = function() end,
      hasFullBrowseResults = function() return full end, getBrowseResults = function() return results end,
      triggerFor = function() return 100 end, onHit = function() end, onRows = function() end,
      onPassDone = function(info) done = info end,
    })
    assert.is_nil(pass:Progress())
    pass:Start("classes")
    pass:OnThrottleReady()
    now = 1004
    pass:OnResultsAdded({ { itemKey = { itemID = 1 }, minPrice = 50, totalQuantity = 1 },
      { itemKey = { itemID = 2 }, minPrice = 500, totalQuantity = 1 } })
    assert.same({ kind = "classes", pages = 1, items = 2, seconds = 4 }, pass:Progress())
    full = true
    now = 1009
    pass:OnResultsAdded({ { itemKey = { itemID = 3 }, minPrice = 60, totalQuantity = 1 } })
    assert.is_nil(pass:Progress())
    assert.same({ kind = "classes", pages = 2, items = 3, seconds = 9 }, done)
  end)

  it("a poll tells its cycle and which batch of how many it has handed out", function()
    local GC = helper.loadModule("Core/KeyPoll.lua")
    local poll = GC.KeyPoll.New({ now = function() return 0 end, triggerFor = function() return nil end,
      onHit = function() end }, { maxBatch = 2 })
    poll:SetTargets({ 1, 2, 3, 4, 5 })
    poll:BeginCycle()
    assert.same({ cycle = 1, batch = 0, batches = 3 }, poll:Progress())
    poll:NextBatch()
    poll:NextBatch()
    assert.same({ cycle = 1, batch = 2, batches = 3 }, poll:Progress())
  end)

  it("the drill queue tells a new find once, never a hit handed back, and its oldest hit's age", function()
    local GC = helper.loadModule("Core/DrillQueue.lua")
    local now, finds = 100, 0
    local queue = GC.DrillQueue.New({ now = function() return now end, onQueued = function() finds = finds + 1 end })
    assert.is_nil(queue:OldestAge())
    queue:Push({ itemID = 1, floor = 10, estProfit = 5 })
    now = 130
    queue:Push({ itemID = 2, floor = 10, estProfit = 3 })
    queue:Push({ itemID = 2, floor = 10, estProfit = 3 }) -- the same find again
    assert.equal(2, finds)
    assert.equal(30, queue:OldestAge())
    local hit = queue:Pop()
    hit.declined = true
    queue:Push(hit) -- a declined send, handed back
    assert.equal(2, finds)
  end)

  it("the gear loop's round tells when it began and each row it took", function()
    local GC = helper.loadModule("Core/ForeverGearLoop.lua")
    local pushed = {}
    local rounds = GC.ForeverGearLoop.New({ vendorFor = function() return nil end, known = function() return true end,
      onPush = function(itemID) pushed[#pushed + 1] = itemID end })
    assert.is_nil(rounds:StartedAt())
    rounds:BeginRound(50)
    assert.equal(50, rounds:StartedAt())
    rounds:Push(7, 100, 51)
    assert.same({ 7 }, pushed)
  end)

  it("the deal bell counts a deal whether or not it may play", function()
    local GC = helper.loadModule("Core/AutoReadout.lua")
    helper.loadModule("UI/DealSound.lua", GC)
    GC.AutoReadout._Reset()
    GC.DealSound.Ring({ sound = false })
    assert.equal(1, GC.AutoReadout.Counts().deals)
  end)
end)
