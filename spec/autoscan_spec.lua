local helper = require("spec.spec_helper")

describe("AutoScan", function()
  local GC, log, actions

  before_each(function()
    GC = helper.loadModule("Core/AutoScan.lua")
    log = { start = 0, abort = 0 }
    actions = {
      startScan = function() log.start = log.start + 1 end,
      abortScan = function() log.abort = log.abort + 1 end,
    }
  end)

  local function newMachine()
    return GC.AutoScan.New({ breather = 2, settle = 1 }, actions)
  end

  it("does nothing until toggled on", function()
    local m = newMachine()
    assert.equal("OFF", m:State())
    m:Tick(1000)
    assert.equal(0, log.start)
    assert.equal("OFF", m:State())
  end)

  it("arms on toggleOn and starts scanning on the next Tick", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    assert.equal("IDLE", m:State())
    assert.equal(0, log.start) -- toggleOn itself does not start a scan
    m:Tick(1000)
    assert.equal(1, log.start)
    assert.equal("SCANNING", m:State())
  end)

  it("aborts exactly once and moves to PAUSED when a dialog opens mid-scan", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)
    assert.equal("SCANNING", m:State())

    m:Input("pause:dialog", 1005)
    assert.equal(1, log.abort)
    assert.equal("PAUSED", m:State())
    assert.same({ dialog = true }, m:PauseReasons())

    -- a second, unrelated pause input while already paused must not abort again
    m:Input("pause:search", 1006)
    assert.equal(1, log.abort)
  end)

  it("resumes into SCANNING only once the settle delay elapses", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)
    m:Input("pause:dialog", 1005)
    assert.equal("PAUSED", m:State())

    m:Input("resume:dialog", 1010)
    assert.equal("WAITING", m:State()) -- settle countdown, not an immediate rescan
    assert.equal(1, log.start)

    m:Tick(1010) -- settle = 1s, deadline is 1011: not yet
    assert.equal("WAITING", m:State())
    assert.equal(1, log.start)

    m:Tick(1011) -- deadline reached
    assert.equal("SCANNING", m:State())
    assert.equal(2, log.start)
  end)

  it("treats overlapping pause reasons as a set: resumes only when all clear", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)

    m:Input("pause:dialog", 1001)
    m:Input("pause:mail", 1002)
    assert.equal(1, log.abort) -- second pause while already PAUSED does not re-abort
    assert.same({ dialog = true, mail = true }, m:PauseReasons())

    m:Input("resume:dialog", 1003)
    assert.equal("PAUSED", m:State()) -- mail still holds it paused
    assert.same({ mail = true }, m:PauseReasons())

    m:Input("resume:mail", 1004)
    assert.equal("WAITING", m:State())
    m:Tick(1005) -- deadline 1005 (settle=1): reached
    assert.equal("SCANNING", m:State())
    assert.equal(2, log.start)
  end)

  it("does not call abortScan when a pause reason arrives before scanning has started", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    -- pause before the first Tick ever runs -- nothing is scanning yet
    m:Input("pause:dialog", 1000)
    assert.equal(0, log.abort)
    assert.equal("PAUSED", m:State())

    m:Tick(1000)
    assert.equal(0, log.start) -- still paused, Tick must not start a scan

    m:Input("resume:dialog", 1000)
    m:Tick(1001) -- settle elapses
    assert.equal(1, log.start)
    assert.equal("SCANNING", m:State())
  end)

  it("cycles scanFinished -> WAITING -> breather -> startScan", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)
    assert.equal(1, log.start)

    m:Input("scanFinished", 1050)
    assert.equal("WAITING", m:State())

    m:Tick(1051) -- breather = 2s, deadline 1052: not yet
    assert.equal("WAITING", m:State())
    assert.equal(1, log.start)

    m:Tick(1052)
    assert.equal("SCANNING", m:State())
    assert.equal(2, log.start)
  end)

  it("treats ahClosed/ahOpened as the ah pause reason", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)

    m:Input("ahClosed", 1010)
    assert.equal(1, log.abort)
    assert.equal("PAUSED", m:State())
    assert.same({ ah = true }, m:PauseReasons())

    m:Input("ahOpened", 1020)
    assert.equal("WAITING", m:State())
    m:Tick(1021) -- settle elapses
    assert.equal("SCANNING", m:State())
    assert.equal(2, log.start)
  end)

  it("treats tabHidden/tabShown as the tab pause reason", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)

    m:Input("tabHidden", 1010)
    assert.equal(1, log.abort)
    assert.equal("PAUSED", m:State())
    assert.same({ tab = true }, m:PauseReasons())

    m:Input("tabShown", 1020)
    assert.equal("WAITING", m:State())
    m:Tick(1021)
    assert.equal("SCANNING", m:State())
    assert.equal(2, log.start)
  end)

  it("toggleOff aborts an in-flight scan and forces OFF from any state", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)
    assert.equal("SCANNING", m:State())

    m:Input("toggleOff", 1010)
    assert.equal(1, log.abort)
    assert.equal("OFF", m:State())
    assert.same({}, m:PauseReasons())

    -- toggleOff while PAUSED must not abort a second time (nothing scanning);
    -- fresh log/actions so this doesn't accumulate onto the first machine's count.
    local log2 = { start = 0, abort = 0 }
    local m2 = GC.AutoScan.New({ breather = 2, settle = 1 }, {
      startScan = function() log2.start = log2.start + 1 end,
      abortScan = function() log2.abort = log2.abort + 1 end,
    })
    m2:Input("toggleOn", 1000)
    m2:Tick(1000)
    m2:Input("pause:mail", 1001) -- aborts once, now PAUSED
    assert.equal(1, log2.abort)
    m2:Input("toggleOff", 1002)
    assert.equal(1, log2.abort)
    assert.equal("OFF", m2:State())
  end)

  it("OFF state ignores every input except toggleOn", function()
    local m = newMachine()
    m:Input("scanFinished", 1000)
    m:Input("pause:dialog", 1000)
    m:Input("resume:dialog", 1000)
    m:Input("ahClosed", 1000)
    m:Input("tabHidden", 1000)
    m:Input("toggleOff", 1000)
    assert.equal("OFF", m:State())
    assert.same({}, m:PauseReasons())
    assert.equal(0, log.start)
    assert.equal(0, log.abort)

    m:Input("toggleOn", 1000)
    assert.equal("IDLE", m:State())
  end)

  it("cancels the breather deadline when a pause arrives mid-WAITING (post-scanFinished)", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)
    m:Input("scanFinished", 1050) -- breather = 2s, deadline 1052
    assert.equal("WAITING", m:State())

    m:Input("pause:dialog", 1051) -- before the breather deadline
    assert.equal("PAUSED", m:State())
    assert.equal(0, log.abort) -- nothing was in flight to abort (SCANNING had already finished)
    assert.same({ dialog = true }, m:PauseReasons())

    m:Tick(1052) -- old breather deadline: must NOT fire now that a pause cancelled it
    assert.equal("PAUSED", m:State())
    assert.equal(1, log.start)
    assert.equal(0, log.abort)
  end)

  it("cancels the settle deadline when a new pause arrives mid-WAITING (post-resume)", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)
    m:Input("pause:dialog", 1010) -- aborts the running scan
    assert.equal(1, log.abort)
    m:Input("resume:dialog", 1020) -- settle = 1s, deadline 1021
    assert.equal("WAITING", m:State())

    m:Input("pause:search", 1020) -- before the settle deadline
    assert.equal("PAUSED", m:State())
    assert.equal(1, log.abort) -- unchanged: nothing was in flight during WAITING
    assert.same({ search = true }, m:PauseReasons())

    m:Tick(1021) -- old settle deadline: must NOT fire now that a pause cancelled it
    assert.equal("PAUSED", m:State())
    assert.equal(1, log.start)
    assert.equal(1, log.abort)
  end)

  it("treats scanFinished arriving while PAUSED as a no-op (async abort race)", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)
    m:Input("pause:dialog", 1010) -- abortScan already fired; browse pagination is dead
    assert.equal(1, log.abort)
    assert.equal("PAUSED", m:State())

    -- a scanFinished event from the aborted pass lands after the pause
    m:Input("scanFinished", 1011)
    assert.equal("PAUSED", m:State()) -- must not clobber PAUSED into WAITING
    assert.equal(1, log.start)
    assert.equal(1, log.abort)
    assert.same({ dialog = true }, m:PauseReasons())

    m:Input("resume:dialog", 1020) -- settle = 1s, deadline 1021
    m:Tick(1021)
    assert.equal("SCANNING", m:State())
    assert.equal(2, log.start) -- exactly one rescan
  end)

  it("is idempotent on a repeated same-reason pause", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)
    m:Input("pause:dialog", 1010)
    assert.equal(1, log.abort)
    m:Input("pause:dialog", 1011) -- same reason again, still SCANNING-turned-PAUSED
    assert.equal(1, log.abort) -- no second abort
    assert.same({ dialog = true }, m:PauseReasons()) -- still a single entry

    m:Input("resume:dialog", 1012) -- one resume fully clears it
    assert.equal("WAITING", m:State())
    m:Tick(1013) -- settle = 1s, deadline 1013
    assert.equal("SCANNING", m:State())
    assert.equal(2, log.start)
  end)

  it("ignores resume for a reason that was never paused, in SCANNING and IDLE", function()
    local m = newMachine()
    m:Input("toggleOn", 1000)
    m:Tick(1000)
    assert.equal("SCANNING", m:State())
    m:Input("resume:mail", 1005) -- never paused
    assert.equal("SCANNING", m:State())
    assert.equal(1, log.start)
    assert.equal(0, log.abort)
    assert.same({}, m:PauseReasons())

    local log2 = { start = 0, abort = 0 }
    local m2 = GC.AutoScan.New({ breather = 2, settle = 1 }, {
      startScan = function() log2.start = log2.start + 1 end,
      abortScan = function() log2.abort = log2.abort + 1 end,
    })
    m2:Input("toggleOn", 1000) -- IDLE, no Tick yet
    m2:Input("resume:search", 1000) -- never paused
    assert.equal("IDLE", m2:State())
    assert.equal(0, log2.start)
    assert.equal(0, log2.abort)
  end)

  local function assertDefaultTimers(timersArg)
    local log2 = { start = 0, abort = 0 }
    local m = GC.AutoScan.New(timersArg, {
      startScan = function() log2.start = log2.start + 1 end,
      abortScan = function() log2.abort = log2.abort + 1 end,
    })
    m:Input("toggleOn", 1000)
    m:Tick(1000)
    assert.equal(1, log2.start)

    -- settle defaults to 1s
    m:Input("pause:dialog", 1010)
    m:Input("resume:dialog", 1020) -- deadline should be 1021
    m:Tick(1020)
    assert.equal("WAITING", m:State())
    assert.equal(1, log2.start)
    m:Tick(1021)
    assert.equal("SCANNING", m:State())
    assert.equal(2, log2.start)

    -- breather defaults to 2s
    m:Input("scanFinished", 1100) -- deadline should be 1102
    m:Tick(1101)
    assert.equal("WAITING", m:State())
    assert.equal(2, log2.start)
    m:Tick(1102)
    assert.equal("SCANNING", m:State())
    assert.equal(3, log2.start)
  end

  it("defaults breather to 2s and settle to 1s when timers is nil", function()
    assertDefaultTimers(nil)
  end)

  it("defaults breather to 2s and settle to 1s when timers is an empty table", function()
    assertDefaultTimers({})
  end)
end)
