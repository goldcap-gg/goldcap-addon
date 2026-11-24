local helper = require("spec.spec_helper")

-- WoW: Forever's gear loop on the Items board shares the slot with the Checks of its finds and the
-- drills (UI/SniperGearLoop_Camelot.lua's GC.Sniper._GearShare) by the Items polls' own rule,
-- GC.DrillQueue.SlotTurn. Replayed on the shape measured on 2026-11-24: a round is 29 pages
-- (weapons 5, armor 24), a find every 2 to 3 seconds, one slot a second.
describe("Forever gear loop slot share", function()
  local GC, L, DQ

  before_each(function()
    GC = helper.loadModule("Core/ForeverGearLoop.lua")
    helper.loadModule("Core/DrillQueue.lua", GC)
    L, DQ = GC.ForeverGearLoop, GC.DrillQueue
  end)

  it("calls a find urgent once URGENT_SECONDS of its wait are left", function()
    local loop = L.New({ vendorFor = function() return nil end, known = function() return false end })
    loop:Push(1, 100, 0)
    assert.is_false(loop:Urgent(L.C.HIT_WAIT_SECONDS - L.C.URGENT_SECONDS - 1))
    assert.is_true(loop:Urgent(L.C.HIT_WAIT_SECONDS - L.C.URGENT_SECONDS))
    loop:Take(1)
    assert.is_false(loop:Urgent(L.C.HIT_WAIT_SECONDS))
  end)

  local PAGES = 29

  -- One round, a slot a second. `share`: the new order (the page and the Checks or drills take
  -- turns); without it the old one (every drill, then every Check, then a page). `finds`: the loop
  -- finds a lot every 2 and 3 seconds in turn. `polls`: a poll's live hit waits in the drill queue
  -- on every slot. `perPage`: each page's fold lands that many finds. After the round the slots
  -- that are left go to the Checks, so a find still waiting is either checked or lost.
  local function replay(share, finds, polls, perPage)
    local now = 0
    local loop = L.New({ vendorFor = function() return nil end, known = function() return false end })
    local queue = DQ.New({ now = function() return now end })
    local pushed, checked, drilled, pages, run, nextFind, gap, nextPoll = 0, 0, 0, 0, 1, 1, 2, 1
    local roundAt
    for t = 0, 599 do
      now = t
      if finds and not roundAt and t == nextFind then
        pushed = pushed + 1
        loop:Push(pushed, 100, t)
        nextFind, gap = nextFind + gap, 5 - gap
      end
      if polls and queue:Depth() == 0 then
        queue:Push({ itemID = 100000 + nextPoll, floor = 10, estProfit = 1 })
        nextPoll = nextPoll + 1
      end
      local find = #loop:Waiting(t) > 0
      local drill = queue:Depth() > 0
      local turn
      if roundAt then
        turn = find and "check" or nil
      elseif share and (find or drill) then
        turn = DQ.SlotTurn({ batch = true, drill = true, urgent = loop:Urgent(t) or queue:Urgent(), run = run })
        if turn == "drill" then turn = find and "check" or "drill" end
      else
        turn = drill and "drill" or (find and "check" or "batch")
      end
      if turn == "batch" then
        pages, run = pages + 1, 0
        for _ = 1, perPage or 0 do
          pushed = pushed + 1
          loop:Push(pushed, 100, t)
        end
        if pages == PAGES then roundAt = t + 1 end
      elseif turn == "check" then
        loop:Take(loop:Waiting(t)[1].itemID)
        checked, run = checked + 1, run + 1
      elseif turn == "drill" then
        queue:Pop()
        drilled, run = drilled + 1, run + 1
      end
      if roundAt and #loop:Waiting(t) == 0 then break end
    end
    return { seconds = roundAt, pushed = pushed, lost = pushed - checked, drilled = drilled }
  end

  it("replays the measured round: twice its undisturbed time at most, and no find lost", function()
    local undisturbed = replay(true, false, false).seconds
    assert.equal(PAGES, undisturbed)
    local old, new = replay(false, true, false), replay(true, true, false)
    -- A Check is a slot either way: the round carries the Checks of the finds it makes.
    assert.equal(48, old.seconds)
    assert.equal(0, old.lost)
    assert.equal(48, new.seconds)
    assert.equal(0, new.lost)
    assert.is_true(new.seconds <= 2 * undisturbed)
    assert.equal(19, new.pushed)
  end)

  -- Six finds a page is the load that makes the old order's round about 200 s, as measured. A Check
  -- is a slot whatever the order, and a find waits HIT_WAIT_SECONDS at most: no order both ends the
  -- round inside twice its time and checks every find. The new one ends it in 75 s and lets the
  -- finds it cannot reach in time go.
  it("ends a round that finds six lots a page in 75 s, where the old order took 197", function()
    local old, new = replay(false, false, false, 6), replay(true, false, false, 6)
    assert.equal(197, old.seconds)
    assert.equal(0, old.lost)
    assert.equal(75, new.seconds)
    assert.equal(174, new.pushed)
    assert.equal(98, new.lost)
    assert.is_true(new.seconds <= 3 * PAGES)
  end)

  it("keeps the round going while a drill waits on every slot, and checks every find first", function()
    local old = replay(false, true, true)
    assert.is_nil(old.seconds)                -- no page in ten minutes: the round never ends
    assert.equal(0, old.pushed - old.lost)    -- and not one find is checked
    local new = replay(true, true, true)
    assert.equal(57, new.seconds)
    assert.is_true(new.seconds <= 2 * PAGES)
    assert.equal(0, new.lost)
    assert.is_true(new.drilled > 0)
  end)
end)
