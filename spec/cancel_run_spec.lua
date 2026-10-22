local helper = require("spec.spec_helper")

-- The CANCEL button's run (plan 2026-10-22, task 13): one confirm for the whole queue, then one
-- lot per press. Core/CancelRun.lua only decides what a press does; the press itself, and the one
-- CancelAuction it may make, stay in UI/Sell/Dock.lua. The clock is injected.
describe("the cancel run", function()
  local Run

  before_each(function()
    Run = helper.loadModule("Core/CancelRun.lua").CancelRun
  end)

  local function entries(n)
    local out = {}
    for i = 1, n do out[i] = { auctionID = 100 + i, positionKey = "commodity:" .. i } end
    return out
  end

  it("waits a second before a confirm counts, and twenty seconds for a press", function()
    assert.equal(1, Run.ARM_SECONDS)
    assert.equal(20, Run.IDLE_SECONDS)
  end)

  it("Start sums the deposits", function()
    local costs = { [101] = 100, [102] = 250 }
    local run = Run.Start(entries(2), function(id) return costs[id] end, 50)
    assert.same({ stage = "armed", count = 2, cost = 350, armedAt = 50, lastPressAt = 50,
      ids = { [101] = true, [102] = true } }, run)
    -- One deposit the client cannot say makes the total unknown, not smaller.
    run = Run.Start(entries(2), function(id) return id == 101 and 100 or nil end, 50)
    assert.equal(2, run.count)
    assert.is_nil(run.cost)
    assert.is_nil(Run.Start(entries(2), nil, 50).cost)
    assert.is_nil(Run.Start(entries(1), function() return 0 / 0 end, 50).cost)
    assert.is_nil(Run.Start(entries(1), function() return -5 end, 50).cost)
    assert.is_nil(Run.Start(entries(1), function() error("no auction house") end, 50).cost)
    -- Nothing queued, nothing to run.
    assert.is_nil(Run.Start({}, function() return 1 end, 50))
    assert.is_nil(Run.Start(nil, function() return 1 end, 50))
  end)

  it("Press", function()
    local queue = entries(3)
    local run = Run.Start(queue, function() return 1 end, 100)
    assert.equal("early", (Run.Press(run, queue, 100.5)))
    assert.equal("armed", run.stage)
    local action, entry = Run.Press(run, queue, 101.2)
    assert.equal("cancel", action)
    assert.equal(queue[1], entry)
    assert.equal("running", run.stage)
    assert.equal(101.2, run.lastPressAt)
    -- Running, a press counts at once: the second only guards the confirm.
    action, entry = Run.Press(run, queue, 101.3)
    assert.equal("cancel", action)
    assert.equal(queue[1], entry)
    action = Run.Press(run, queue, 105)
    assert.equal("cancel", action)
    -- Twenty seconds without a press ends it.
    assert.is_false(Run.Expired(run, 125))
    assert.is_true(Run.Expired(run, 126))
    assert.equal("expired", (Run.Press(run, queue, 126)))
    -- The queue ran out.
    run = Run.Start(queue, function() return 1 end, 200)
    assert.equal("done", (Run.Press(run, {}, 205)))
  end)

  -- The confirm covers the lots it counted and priced, and no other: a lot that reaches the head
  -- later (the market moved, a lot came back) is "changed", which arms again with a new count
  -- and a new total, never a cancel the player did not see.
  it("cancels only the lots the confirm showed", function()
    local queue = entries(2)
    local run = Run.Start(queue, function() return 1 end, 100)
    assert.is_true(Run.Covers(run, queue[1]))
    assert.is_true(Run.Covers(run, queue[2]))
    local late = { auctionID = 109, positionKey = "commodity:9" }
    assert.is_false(Run.Covers(run, late))
    assert.is_false(Run.Covers(nil, queue[1]))
    assert.is_false(Run.Covers(run, nil))
    -- Before the confirm: a new head is not what CONFIRM would confirm, and the button no longer
    -- says CONFIRM, so even a press inside the second arms again rather than doing nothing.
    assert.equal("changed", (Run.Press(run, { late, queue[1], queue[2] }, 100.5)))
    assert.equal("changed", (Run.Press(run, { late, queue[1], queue[2] }, 101.2)))
    -- Running: the next head joined after the confirm.
    assert.equal("cancel", (Run.Press(run, queue, 101.2)))
    assert.equal("changed", (Run.Press(run, { late, queue[2] }, 102)))
    -- A confirmed lot is still the run's while it stays queued: a press that could not reach it
    -- (its row was not on screen) leaves it for the next press.
    local action, entry = Run.Press(run, { queue[2], late }, 103)
    assert.equal("cancel", action)
    assert.equal(queue[2], entry)
    -- Counting what is left of the run: the confirmed lots still queued.
    assert.equal(1, Run.Left(run, { queue[2], late }))
    assert.equal(0, Run.Left(run, { late }))
    assert.equal(0, Run.Left(nil, { queue[2] }))
  end)

  it("lets an armed run lapse after twenty seconds without its confirm", function()
    local queue = entries(1)
    local run = Run.Start(queue, function() return 1 end, 0)
    assert.equal("expired", (Run.Press(run, queue, 21)))
    assert.is_false(Run.Expired(nil, 21))
  end)
end)
