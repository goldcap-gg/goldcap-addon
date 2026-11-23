local helper = require("spec.spec_helper")

describe("DrillQueue.SlotTurn", function()
  local GC
  before_each(function()
    GC = helper.loadModule("Core/DrillQueue.lua")
    GC = helper.loadModule("Core/KeyPoll.lua", GC)
  end)

  it("gives the slot by the table", function()
    local cases = {
      -- batch wants, drill wants, urgent, drills since the last batch -> turn
      { false, false, false, 0, nil },
      { false, true,  false, 5, "drill" },
      { true,  false, true,  0, "batch" },
      { true,  true,  false, 0, "drill" },  -- after a batch, a drill
      { true,  true,  false, 1, "batch" },  -- after a drill, a batch
      { true,  true,  true,  1, "drill" },  -- an urgent hit takes one drill more
      { true,  true,  true,  2, "batch" },  -- and no more: the round still moves
      { true,  true,  false, 9, "batch" },
    }
    for i, c in ipairs(cases) do
      local turn = GC.DrillQueue.SlotTurn({ batch = c[1], drill = c[2], urgent = c[3], run = c[4] })
      assert.equal(c[5], turn, "case " .. i)
    end
  end)

  it("drills the oldest hit first once it is near its age limit", function()
    local now = 0
    local q = GC.DrillQueue.New({ now = function() return now end })
    q:Push({ itemID = 1, floor = 10, estProfit = 1 })
    now = 40
    q:Push({ itemID = 2, floor = 10, estProfit = 1000 })
    assert.is_false(q:Urgent())
    assert.equal(2, q:Peek().itemID)
    now = GC.DrillQueue.TTL_SECONDS - GC.DrillQueue.URGENT_SECONDS
    assert.is_true(q:Urgent())
    assert.equal(1, q:Pop().itemID)
    assert.is_false(q:Urgent())
  end)

  -- The Items board as measured in 0.33.0: 600 realm targets and 407 caps, so a round is always
  -- pending; a burst of 25 key-poll hits, then a key-poll hit every 15 s and a cap hit every 18 s
  -- for eight minutes; one slot a second.
  local function replay(rule)
    local now, lost, waits = 0, 0, {}
    local q = GC.DrillQueue.New({ now = function() return now end, onLost = function() lost = lost + 1 end })
    local noop = { now = function() return now end, triggerFor = function() return nil end,
      onHit = function() end, onRows = function() end }
    local keys, caps = GC.KeyPoll.New(noop), GC.KeyPoll.New(noop)
    local function ids(n, base)
      local list = {}
      for i = 1, n do list[i] = base + i end
      return list
    end
    keys:SetTargets(ids(600, 1000))
    caps:SetTargets(ids(407, 5000))
    local nextID, pushed = 1, 0
    local function hit(priority)
      q:Push({ itemID = nextID, floor = 100, estProfit = 50, priority = priority })
      nextID, pushed = nextID + 1, pushed + 1
    end
    for _ = 1, 25 do hit(0) end
    local run, batches, drills = 1, 0, 0
    for t = 0, 599 do
      now = t
      if t > 0 and t < 480 and t % 15 == 0 then hit(0) end
      if t > 0 and t < 480 and t % 18 == 0 then hit(1) end
      local turn = rule({ batch = true, drill = q:Depth() > 0, urgent = q:Urgent(), run = run })
      if turn == "drill" then
        local h = q:Pop()
        waits[#waits + 1] = now - h.pushedAt
        run, drills = run + 1, drills + 1
      elseif turn == "batch" then
        local poll = caps:HasPending() and caps or keys
        poll:NextBatch()
        if not caps:HasPending() and not keys:HasPending() then
          caps:BeginCycle()
          keys:BeginCycle()
        end
        run, batches = 0, batches + 1
      end
    end
    local maxWait = 0
    for _, w in ipairs(waits) do maxWait = math.max(maxWait, w) end
    return { pushed = pushed, lost = lost, drilled = #waits, maxWait = maxWait, batches = batches, drills = drills }
  end

  it("replays the measured Items board: no hit ages out, and the rounds keep most of the slots", function()
    local r = replay(GC.DrillQueue.SlotTurn)
    assert.equal(82, r.pushed)
    assert.equal(0, r.lost)
    assert.equal(r.pushed, r.drilled)
    -- The burst drains one drill in two slots, with the caps' hits ahead of it: the longest wait
    -- is 53 s, inside the 60 after which a hit is urgent and well inside the 90 it may live.
    assert.equal(53, r.maxWait)
    assert.is_true(r.maxWait < GC.DrillQueue.TTL_SECONDS - GC.DrillQueue.URGENT_SECONDS)
    -- 518 of the 600 slots still go to the rounds.
    assert.equal(518, r.batches)
  end)

  it("loses every hit under the old rule, which gave a pending round every slot", function()
    local r = replay(function(s) return s.batch and "batch" or (s.drill and "drill" or nil) end)
    assert.equal(0, r.drilled)
    assert.equal(r.pushed, r.lost)
  end)
end)
