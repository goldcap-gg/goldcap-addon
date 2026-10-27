local helper = require("spec.spec_helper")

describe("VendorPress", function()
  local GC, P, bags, calls, timers, open, cursor, refuse, machine

  local function key(b, s) return b .. ":" .. s end

  local function rows(n)
    local out = {}
    for i = 1, n do
      bags[key(0, i)] = { link = "item:" .. i, isLocked = false }
      out[i] = { bag = 0, slot = i, link = "item:" .. i, copper = 10 * i }
    end
    return out
  end

  local function fire()
    local t = table.remove(timers, 1)
    if t then t.fn() end
    return t ~= nil
  end
  local function drain() while fire() do end end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/ForeverValue.lua", GC)
    helper.loadModule("Core/VendorSelect.lua", GC)
    helper.loadModule("Core/VendorPress.lua", GC)
    P = GC.VendorPress
    bags, timers = {}, {}
    calls = { use = {}, report = {} }
    open, cursor, refuse = true, false, false
    machine = P.New({
      open = function() return open end,
      slot = function(b, s)
        local x = bags[key(b, s)]
        return x and { link = x.link, isLocked = x.isLocked } or nil
      end,
      cursorBusy = function() return cursor end,
      use = function(b, s)
        calls.use[#calls.use + 1] = { b, s }
        if not refuse then bags[key(b, s)] = nil end
      end,
      after = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end,
      report = function(r) calls.report[#calls.report + 1] = r end,
      -- As UI/VendorSellCard.lua drives it.
      limit = GC.VendorSelect.MAX_STACKS,
      slowFallback = true,
    })
  end)

  it("makes the first call before any timer is armed", function()
    machine:Press(rows(3))
    assert.equal(1, #calls.use)
    assert.equal(1, #timers)
    assert.equal(0, #calls.report)
  end)

  it("sells the rest 0.2 s apart and reports once", function()
    machine:Press(rows(3))
    local delays = {}
    while #timers > 0 do
      delays[#delays + 1] = timers[1].seconds
      fire()
    end
    assert.equal(3, #calls.use)
    for _, d in ipairs(delays) do assert.equal(0.2, d) end
    assert.equal(1, #calls.report)
    assert.same({ sold = 3, copper = 60, stopped = nil }, calls.report[1])
    assert.is_false(machine:IsRunning())
  end)

  it("re-checks the merchant before every call", function()
    machine:Press(rows(3))
    open = false
    drain()
    assert.equal(1, #calls.use)
    assert.same({ sold = 1, copper = 10, stopped = "closed" }, calls.report[1])
  end)

  it("skips a slot whose item changed and sells the others", function()
    machine:Press(rows(3))
    bags[key(0, 2)].link = "item:other"
    drain()
    assert.equal(2, #calls.use)
    assert.same({ 0, 3 }, calls.use[2])
    assert.equal(2, calls.report[1].sold)
  end)

  it("skips an empty or locked slot", function()
    machine:Press(rows(4))
    bags[key(0, 2)] = nil
    bags[key(0, 3)].isLocked = true
    drain()
    assert.equal(2, #calls.use)
    assert.equal(2, calls.report[1].sold)
    assert.is_nil(calls.report[1].stopped)
  end)

  it("stops without calling when the cursor carries an item", function()
    machine:Press(rows(3))
    cursor = true
    drain()
    assert.equal(1, #calls.use)
    assert.equal("cursor", calls.report[1].stopped)
    assert.equal(1, calls.report[1].sold)
  end)

  it("falls back to one stack per press when a timer sale stays in the bag", function()
    machine:Press(rows(3))
    refuse = true -- the first sale already left; the second goes out from a timer and stays
    drain()
    assert.equal("slow", calls.report[1].stopped)
    assert.is_true(machine.oneAtATime)
    refuse = false
    local again = rows(3)
    calls.use = {}
    machine:Press(again)
    assert.equal(1, #calls.use)
    drain()
    assert.same({ sold = 1, copper = 10, stopped = nil }, calls.report[2])
  end)

  -- A sale leaves the bag when the server answers, which on a slow connection takes well over a
  -- second; the machine looks every 0.2 s for up to 3 s before it calls a sale refused.
  it("gives a timer sale 3 s to leave the bag, looking every 0.2 s, before falling back", function()
    machine:Press(rows(3))
    refuse = true
    fire() -- the first sale has left; the second is made from this timer and stays
    assert.equal(2, #calls.use)
    local looks = 0
    while #calls.report == 0 do
      assert.equal(0.2, timers[1].seconds)
      fire()
      looks = looks + 1
    end
    assert.equal(15, looks)
    assert.equal("slow", calls.report[1].stopped)
    assert.is_true(machine.oneAtATime)
  end)

  it("counts a timer sale that leaves after 2.8 s and goes on", function()
    machine:Press(rows(3))
    refuse = true
    fire() -- the second sale is made and stays for now
    for _ = 1, 13 do fire() end -- 2.6 s
    assert.equal(0, #calls.report)
    bags[key(0, 2)] = nil -- the server's answer arrives
    refuse = false
    drain()
    assert.equal(3, #calls.use)
    assert.same({ sold = 3, copper = 60, stopped = nil }, calls.report[1])
    assert.is_false(machine.oneAtATime)
  end)

  it("gives the sale made in the click the same 3 s before calling it refused", function()
    refuse = true
    machine:Press(rows(3))
    local looks = 0
    while #calls.report == 0 do
      fire()
      looks = looks + 1
    end
    assert.equal(15, looks)
    assert.equal("refused", calls.report[1].stopped)
  end)

  it("does not fall back when the sale made in the click stays", function()
    refuse = true
    machine:Press(rows(3))
    drain()
    assert.equal(1, #calls.use)
    assert.equal("refused", calls.report[1].stopped)
    assert.is_false(machine.oneAtATime)
  end)

  it("a second press stops the run", function()
    local r = rows(3)
    machine:Press(r)
    fire()
    machine:Press(r)
    assert.equal("pressed", calls.report[1].stopped)
    assert.equal(2, calls.report[1].sold) -- the second sale left the bag by then
    local n = #calls.use
    drain()
    assert.equal(n, #calls.use)
    assert.equal(1, #calls.report)
  end)

  it("counts the in-flight sale when stopped", function()
    machine:Press(rows(3))
    machine:OnClosed()
    assert.same({ sold = 1, copper = 10, stopped = "closed" }, calls.report[1])
  end)

  it("never sells more than 12 per press", function()
    machine:Press(rows(15))
    drain()
    assert.equal(12, calls.report[1].sold)
    assert.equal(12, #calls.use)
  end)

  -- Never sell this, chosen while a press runs: the item's rows still to come are left alone.
  it("skips the rows of an item kept during the run, and only those", function()
    local r = rows(4)
    r[1].itemID, r[2].itemID, r[3].itemID, r[4].itemID = 55, 66, 77, 77
    machine:Press(r)
    machine:Skip(77)
    drain()
    assert.same({ { 0, 1 }, { 0, 2 } }, calls.use)
    assert.same({ sold = 2, copper = 30, stopped = nil }, calls.report[1])
  end)

  it("Skip with no run going does nothing", function()
    machine:Skip(77)
    local r = rows(2)
    r[1].itemID, r[2].itemID = 77, 77
    machine:Press(r)
    drain()
    assert.equal(2, #calls.use)
  end)

  it("a new visit clears the one-per-press mode", function()
    machine.oneAtATime = true
    machine:OnShown()
    assert.is_false(machine.oneAtATime)
  end)

  it("ignores a stale timer after a stop", function()
    machine:Press(rows(3))
    local stale = timers[1]
    machine:Stop("closed")
    timers = {}
    stale.fn()
    assert.equal(1, #calls.use)
    assert.equal(1, #calls.report)
  end)

  it("does nothing for no rows", function()
    machine:Press({})
    assert.equal(0, #calls.use)
    assert.equal(0, #calls.report)
  end)

  -- As UI/HoardFrame.lua drives it: no cap beyond its rows, no fallback, and a `use` that may
  -- decline the call (GC.BankRoute.MoveStack's guards).
  describe("without a limit or a fallback", function()
    local declined
    before_each(function()
      declined = {}
      machine = P.New({
        open = function() return open end,
        slot = function(b, s)
          local x = bags[key(b, s)]
          return x and { link = x.link, isLocked = x.isLocked } or nil
        end,
        cursorBusy = function() return cursor end,
        use = function(b, s, row)
          if declined[s] then return false end
          calls.use[#calls.use + 1] = { b, s, row }
          if not refuse then bags[key(b, s)] = nil end
          return true
        end,
        after = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end,
        report = function(r) calls.report[#calls.report + 1] = r end,
      })
    end)

    it("makes a call for every row, the row handed to the call", function()
      local list = rows(20)
      machine:Press(list)
      drain()
      assert.equal(20, #calls.use)
      assert.equal(list[20], calls.use[20][3])
      assert.same({ sold = 20, copper = 2100, stopped = nil }, calls.report[1])
    end)

    it("skips a row whose call was declined and goes on", function()
      declined[2] = true
      machine:Press(rows(3))
      drain()
      assert.same({ 1, 3 }, { calls.use[1][2], calls.use[2][2] })
      assert.equal(2, calls.report[1].sold)
    end)

    it("stops quietly when a timer call stays, and the next press starts again in the click", function()
      machine:Press(rows(3))
      refuse = true
      drain()
      assert.equal("stalled", calls.report[1].stopped)
      assert.is_false(machine.oneAtATime)
      refuse = false
      calls.use = {}
      machine:Press(rows(3))
      assert.equal(1, #calls.use)
      drain()
      assert.same({ sold = 3, copper = 60, stopped = nil }, calls.report[2])
    end)
  end)

  -- A row with `split` moves a part of a stack in two parts: the split inside the click, the move
  -- from a timer once the part shows in its slot.
  describe("a split row", function()
    local landed, ticksToLand, abandoned, noRoom

    before_each(function()
      landed, ticksToLand, abandoned, noRoom = false, 1, false, false
      calls.part = {}
      bags[key(0, 1)] = { link = "item:1", isLocked = false, count = 10 }
      machine = P.New({
        open = function() return open end,
        slot = function(b, s)
          local x = bags[key(b, s)]
          return x and { link = x.link, isLocked = x.isLocked, count = x.count } or nil
        end,
        cursorBusy = function() return cursor end,
        use = function(b, s, row)
          calls.use[#calls.use + 1] = { b, s, split = row.split }
          if row.split then
            if noRoom then return false, "room" end
            row.dest = { bag = 2, slot = 3 }
            return true
          end
          bags[key(b, s)] = nil
        end,
        landed = function(row)
          if landed then return true end
          ticksToLand = ticksToLand - 1
          if ticksToLand < 0 then
            bags[key(row.dest.bag, row.dest.slot)] = { link = row.link, isLocked = false, count = 4 }
            landed = true
          end
          return landed
        end,
        part = function(row)
          return { bag = row.dest.bag, slot = row.dest.slot, link = row.link, itemID = row.itemID }
        end,
        abandon = function() abandoned = true end,
        after = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end,
        report = function(r) calls.report[#calls.report + 1] = r end,
      })
    end)

    local function row()
      return { bag = 0, slot = 1, link = "item:1", itemID = 1, split = 10, name = "Bloom" }
    end

    it("splits in the click, then moves the part from a timer once its slot shows it", function()
      machine:Press({ row() })
      assert.same({ { 0, 1, split = 10 } }, calls.use)
      drain()
      assert.same({ { 0, 1, split = 10 }, { 2, 3 } }, calls.use)
      assert.same({ sold = 1, copper = 0, stopped = nil }, calls.report[1])
    end)

    it("skips a row whose source holds another count than it was read with", function()
      bags[key(0, 1)].count = 11
      machine:Press({ row() })
      assert.same({}, calls.use)
    end)

    it("names a split with no empty slot and goes on with the next row", function()
      noRoom = true
      bags[key(0, 2)] = { link = "item:2", isLocked = false, count = 1 }
      machine:Press({ row(), { bag = 0, slot = 2, link = "item:2", itemID = 2 } })
      drain()
      assert.same({ { 0, 1, split = 10 }, { 0, 2 } }, calls.use)
      assert.same({ "Bloom" }, calls.report[1].noRoom)
      assert.equal(1, calls.report[1].sold)
    end)

    it("gives the part back and stops after CONFIRM_TICKS when the slot never fills", function()
      ticksToLand = 1000
      machine:Press({ row() })
      drain()
      assert.is_true(abandoned)
      assert.equal("split", calls.report[1].stopped)
      assert.equal(0, calls.report[1].sold)
      assert.equal(1, #calls.use)
    end)
  end)
end)
