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
      merchantOpen = function() return open end,
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
    machine:OnMerchantClosed()
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
    machine:OnMerchantShow()
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
end)
