local helper = require("spec.spec_helper")

describe("MailPress", function()
  local GC, P, bags, log, timers, state, reports, progresses, machine

  local function key(b, s) return b .. ":" .. s end

  -- n mails of two stacks each; mail m holds slots (m-1)*2+1 and (m-1)*2+2 of bag 0.
  local function mails(n)
    local out = {}
    for m = 1, n do
      local stacks = {}
      for k = 1, 2 do
        local s = (m - 1) * 2 + k
        bags[key(0, s)] = { link = "item:" .. s, isLocked = false }
        stacks[k] = { itemID = s, bag = 0, slot = s, count = 1, link = "item:" .. s }
      end
      out[m] = { to = "Alt" .. m .. "-Realm", stacks = stacks, subject = "Mail " .. m }
    end
    return out
  end

  local function fire()
    local t = table.remove(timers, 1)
    if t then t.fn() end
    return t ~= nil
  end

  local function count(name)
    local n = 0
    for _, c in ipairs(log) do if c[1] == name then n = n + 1 end end
    return n
  end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/MailPress.lua", GC)
    P = GC.MailPress
    bags, log, timers, reports, progresses = {}, {}, {}, {}, {}
    state = { open = true, cursor = false, refuse = nil, attached = 0 }
    machine = P.New({
      open = function() return state.open end,
      cursorBusy = function() return state.cursor end,
      slot = function(b, s) return bags[key(b, s)] end,
      attach = function(stack)
        if state.refuse == stack.slot then return false end
        state.attached = state.attached + 1
        log[#log + 1] = { "attach", stack.slot }
        return true
      end,
      attached = function() return state.attached end,
      clear = function() state.attached = 0; log[#log + 1] = { "clear" } end,
      send = function(to, subject)
        state.attached = 0
        log[#log + 1] = { "send", to, subject }
      end,
      after = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end,
      progress = function(p) progresses[#progresses + 1] = p end,
      report = function(r) reports[#reports + 1] = r end,
    })
  end)

  it("attaches and sends the first mail before Press returns", function()
    machine.Press(machine, mails(2))
    assert.are.same({ { "attach", 1 }, { "attach", 2 }, { "send", "Alt1-Realm", "Mail 1" } }, log)
    assert.is_true(machine:IsRunning())
    assert.are.same({ index = 1, total = 2 }, { index = progresses[1].index, total = progresses[1].total })
  end)

  it("sends the second mail only after a confirmed send and a STEP timer", function()
    machine:Press(mails(2))
    assert.are.equal(1, count("send"))
    machine:OnSendResult(true)
    assert.are.equal(1, count("send"))
    assert.are.equal(P.STEP, timers[#timers].seconds)
    fire() -- the SEND_WAIT timer of mail 1, now stale
    assert.are.equal(1, count("send"))
    fire() -- STEP
    assert.are.equal(2, count("send"))
    machine:OnSendResult(true)
    assert.is_false(machine:IsRunning())
    assert.are.same({ sent = 2, mails = 2 }, { sent = reports[1].sent, mails = reports[1].mails })
    assert.is_nil(reports[1].stopped)
    assert.are.equal(1, #reports)
  end)

  it("skips a stack whose link changed and sends the rest", function()
    local m = mails(1)
    bags[key(0, 1)] = { link = "item:other", isLocked = false }
    machine:Press(m)
    assert.are.same({ { "attach", 2 }, { "send", "Alt1-Realm", "Mail 1" } }, log)
  end)

  it("skips a locked stack", function()
    local m = mails(1)
    bags[key(0, 2)].isLocked = true
    machine:Press(m)
    assert.are.same({ { "attach", 1 }, { "send", "Alt1-Realm", "Mail 1" } }, log)
  end)

  it("sends nothing for a mail whose stacks all moved", function()
    local m = mails(2)
    bags[key(0, 1)], bags[key(0, 2)] = nil, nil
    machine:Press(m)
    assert.are.same({ { "attach", 3 }, { "attach", 4 }, { "send", "Alt2-Realm", "Mail 2" } }, log)
    assert.are.equal(1, progresses[1].index)
  end)

  it("finishes without a send when every stack moved", function()
    local m = mails(1)
    bags[key(0, 1)], bags[key(0, 2)] = nil, nil
    machine:Press(m)
    assert.are.equal(0, count("send"))
    assert.is_false(machine:IsRunning())
    assert.are.equal(0, reports[1].sent)
    assert.is_nil(reports[1].stopped)
  end)

  it("stops closed when the mailbox closed before mail 2", function()
    machine:Press(mails(2))
    machine:OnSendResult(true)
    state.open = false
    fire(); fire()
    assert.are.equal(1, count("send"))
    assert.are.equal("closed", reports[1].stopped)
    assert.are.equal(1, reports[1].sent)
  end)

  it("stops cursor when an item is on the cursor before mail 2", function()
    machine:Press(mails(2))
    machine:OnSendResult(true)
    state.cursor = true
    fire(); fire()
    assert.are.equal("cursor", reports[1].stopped)
  end)

  it("stops busy, without clearing, when something else sits in the slots", function()
    machine:Press(mails(2))
    machine:OnSendResult(true)
    state.attached = 1
    fire(); fire()
    assert.are.equal("busy", reports[1].stopped)
    assert.are.equal(0, count("clear"))
  end)

  it("clears and reports refused when attach says no, naming the stack", function()
    local m = mails(1)
    state.refuse = 2
    machine:Press(m)
    assert.are.equal(1, count("clear"))
    assert.are.equal(0, count("send"))
    assert.are.equal("refused", reports[1].stopped)
    assert.are.equal(m[1].stacks[2], reports[1].why)
  end)

  it("clears and reports failed when the send is refused", function()
    machine:Press(mails(2))
    machine:OnSendResult(false)
    assert.are.equal(1, count("clear"))
    assert.are.equal("failed", reports[1].stopped)
    assert.are.equal(0, reports[1].sent)
  end)

  it("clears and reports timeout when no answer comes", function()
    machine:Press(mails(2))
    assert.are.equal(P.SEND_WAIT, timers[1].seconds)
    fire()
    assert.are.equal(1, count("clear"))
    assert.are.equal("timeout", reports[1].stopped)
  end)

  it("ignores an answer when no mail is in flight", function()
    machine:OnSendResult(true)
    machine:OnSendResult(false)
    assert.are.equal(0, #reports)
    machine:Press(mails(2))
    machine:OnSendResult(true)
    machine:OnSendResult(true) -- the second answer belongs to no mail in flight
    assert.are.equal(1, count("send"))
    assert.are.equal(0, #reports)
  end)

  it("stops pressed on a second Press, without clearing a sent mail", function()
    machine:Press(mails(2))
    machine:Press(mails(2))
    assert.are.equal("pressed", reports[1].stopped)
    assert.are.equal(0, reports[1].sent)
    assert.are.equal(0, count("clear"))
    assert.is_false(machine:IsRunning())
    fire(); fire()
    assert.are.equal(1, #reports)
  end)

  it("OnClosed stops a running run, and does nothing otherwise", function()
    machine:OnClosed()
    assert.are.equal(0, #reports)
    machine:Press(mails(2))
    machine:OnClosed()
    assert.are.equal("closed", reports[1].stopped)
  end)

  it("a new run after a stop is not disturbed by the old timers", function()
    machine:Press(mails(1))
    machine:Stop("pressed")
    bags, log = {}, {}
    machine:Press(mails(1))
    fire() -- old SEND_WAIT
    assert.is_true(machine:IsRunning())
  end)

  it("keeps an answer delivered from inside send: success moves on, no timeout", function()
    local drv = machine.driver
    local send = drv.send
    local first = true
    drv.send = function(to, subject)
      send(to, subject)
      if first then first = false; machine:OnSendResult(true) end
    end
    machine:Press(mails(2))
    assert.are.equal(1, count("send"))
    assert.are.equal(P.STEP, timers[1].seconds)
    assert.are.equal(1, #timers)
    fire()
    assert.are.equal(2, count("send"))
    assert.are.equal(0, #reports)
    machine:OnSendResult(true)
    assert.is_nil(reports[1].stopped)
    assert.are.equal(2, reports[1].sent)
    fire()
    assert.are.equal(1, #reports)
  end)

  it("keeps a failure delivered from inside send: clears and reports failed", function()
    local drv = machine.driver
    local send = drv.send
    drv.send = function(to, subject)
      send(to, subject)
      machine:OnSendResult(false)
    end
    machine:Press(mails(2))
    assert.are.equal(1, count("clear"))
    assert.are.equal("failed", reports[1].stopped)
    assert.are.equal(0, #timers)
    assert.are.equal(1, #reports)
  end)
end)
