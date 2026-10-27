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
    state = { open = true, why = nil, cursor = false, refuse = nil, attached = 0, unsafe = false }
    machine = P.New({
      open = function()
        if state.open then return true end
        return false, state.why
      end,
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
        if state.unsafe then return false end
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

  -- A mail the server refuses (MAIL_FAILED) is given back to the bags; its recipient gets nothing
  -- more in this run, and the run goes on with the next one.
  it("clears a refused mail, skips that recipient's other mails and goes on with the next", function()
    local m = mails(3)
    m[2].to = m[1].to
    machine:Press(m)
    machine:OnSendResult(false)
    assert.are.equal(1, count("clear"))
    assert.is_true(machine:IsRunning())
    assert.are.equal(P.STEP, timers[#timers].seconds)
    fire() -- the SEND_WAIT timer of mail 1, now stale
    fire() -- STEP
    assert.are.same({ "send", "Alt3-Realm", "Mail 3" }, log[#log])
    assert.are.equal(2, count("send"))
    machine:OnSendResult(true)
    assert.are.equal(1, #reports)
    assert.is_nil(reports[1].stopped)
    assert.are.equal(1, reports[1].sent)
    assert.are.same({ "Alt1-Realm" }, reports[1].failed)
  end)

  -- "Mail N of M" counts only mails that can still go: a refused recipient's later ones leave it.
  it("counts a refused recipient's later mails out of the total", function()
    local m = mails(3)
    m[2].to = m[1].to
    machine:Press(m)
    assert.are.equal(3, progresses[1].total)
    machine:OnSendResult(false)
    fire() -- the SEND_WAIT timer of mail 1, now stale
    fire() -- STEP
    assert.are.same({ index = 2, total = 2 }, { index = progresses[2].index, total = progresses[2].total })
  end)

  it("finishes at once when every mail left is to a recipient that failed", function()
    local m = mails(2)
    m[2].to = m[1].to
    machine:Press(m)
    machine:OnSendResult(false)
    assert.is_false(machine:IsRunning())
    assert.are.equal(1, count("send"))
    assert.is_nil(reports[1].stopped)
    assert.are.equal(0, reports[1].sent)
    assert.are.same({ "Alt1-Realm" }, reports[1].failed)
  end)

  it("reports no failed recipient for a run that had none", function()
    machine:Press(mails(1))
    machine:OnSendResult(true)
    assert.are.same({}, reports[1].failed)
  end)

  -- The driver could not set COD and money to none: the mail is not sent, and goes back.
  it("sends nothing, clears and reports refused when the mail could not be made safe", function()
    state.unsafe = true
    machine:Press(mails(2))
    assert.are.equal(0, count("send"))
    assert.are.equal(1, count("clear"))
    assert.are.equal("refused", reports[1].stopped)
    assert.is_nil(reports[1].why)
    assert.are.equal(0, #timers)
    assert.is_false(machine:IsRunning())
  end)

  -- A stack that grew (merged with another of its item) since it was read would take more than
  -- the group's keep leaves: it stays. A smaller one goes.
  it("skips a stack whose count grew since it was read", function()
    local m = mails(1)
    bags[key(0, 1)].count = 5
    bags[key(0, 2)].count = 1
    machine:Press(m)
    assert.are.same({ { "attach", 2 }, { "send", "Alt1-Realm", "Mail 1" } }, log)
  end)

  it("stops with the driver's reason when it says the mail cannot go on", function()
    machine:Press(mails(2))
    machine:OnSendResult(true)
    state.open, state.why = false, "tab"
    fire(); fire()
    assert.are.equal("tab", reports[1].stopped)
    assert.are.equal(1, count("send"))
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

  it("keeps a failure delivered from inside send: clears, and goes on after STEP", function()
    local drv = machine.driver
    local send = drv.send
    drv.send = function(to, subject)
      send(to, subject)
      machine:OnSendResult(false)
    end
    machine:Press(mails(2))
    assert.are.equal(1, count("clear"))
    assert.are.equal(0, #reports)
    assert.are.equal(1, #timers)
    assert.are.equal(P.STEP, timers[1].seconds)
    fire()
    assert.are.equal(2, count("send"))
    assert.are.equal(1, #reports)
    assert.is_nil(reports[1].stopped)
    assert.are.same({ "Alt1-Realm", "Alt2-Realm" }, reports[1].failed)
  end)

  -- A stack with `split` is the part of a bigger one (Keep leaves exactly its count): split into an
  -- empty slot inside the click, then attached and sent from a timer once the slot shows it.
  describe("a split part", function()
    local free, landedAfter, splitLog, cursorCleared, stuck, lockPart

    local function splitMachine()
      return P.New({
        open = function() return true end,
        cursorBusy = function() return state.cursor end,
        slot = function(b, s) return bags[key(b, s)] end,
        attach = function(stack)
          state.attached = state.attached + 1
          log[#log + 1] = { "attach", stack.bag, stack.slot, stack.count }
          return true
        end,
        split = function(stack)
          if stuck then return nil, "stuck" end
          if not free then return nil, "room" end
          splitLog[#splitLog + 1] = { stack.slot, stack.count }
          return { bag = 1, slot = 5 }
        end,
        landed = function(stack)
          if landedAfter == nil or landedAfter > 0 then return false end
          bags[key(1, 5)] = { link = stack.link, isLocked = lockPart, count = stack.count }
          return true
        end,
        abandon = function() cursorCleared = true end,
        attached = function() return state.attached end,
        clear = function() state.attached = 0; log[#log + 1] = { "clear" } end,
        send = function(to, subject)
          state.attached = 0
          log[#log + 1] = { "send", to, subject }
        end,
        after = function(seconds, fn)
          timers[#timers + 1] = { seconds = seconds, fn = function()
            if landedAfter then landedAfter = landedAfter - 1 end
            fn()
          end }
        end,
        progress = function(p) progresses[#progresses + 1] = p end,
        report = function(r) reports[#reports + 1] = r end,
      })
    end

    local function splitMail()
      bags[key(0, 1)] = { link = "item:1", isLocked = false, count = 4 }
      bags[key(0, 2)] = { link = "item:2", isLocked = false, count = 1 }
      return { { to = "Alt-Realm", subject = "S", stacks = {
        { itemID = 1, bag = 0, slot = 1, count = 3, split = 4, link = "item:1" },
        { itemID = 2, bag = 0, slot = 2, count = 1, link = "item:2" },
      } } }
    end

    before_each(function()
      free, landedAfter, splitLog, cursorCleared, stuck, lockPart = true, 2, {}, false, false, false
      machine = splitMachine()
    end)

    it("splits inside the click and attaches and sends from a timer once the slot holds the part", function()
      machine:Press(splitMail())
      assert.same({ { 1, 3 } }, splitLog)
      assert.same({}, log)
      assert.is_true(machine:IsRunning())
      assert.equal(P.SPLIT_STEP, timers[1].seconds)
      table.remove(timers, 1).fn() -- the slot does not show it yet
      assert.same({}, log)
      table.remove(timers, 1).fn() -- now it does
      -- The part is attached from the slot it landed in, the other stack from where it was.
      assert.same({ { "attach", 1, 5, 3 }, { "attach", 0, 2, 1 }, { "send", "Alt-Realm", "S" } }, log)
      machine:OnSendResult(true)
      assert.equal(1, reports[1].sent)
      assert.is_nil(reports[1].stopped)
      assert.is_nil(reports[1].noRoom)
    end)

    it("does not take the source growing past what the split was read from for a merge", function()
      local m = splitMail()
      bags[key(0, 1)].count = 5
      machine:Press(m)
      -- The source holds more than it was read with: skipped, only the plain stack is left.
      assert.same({}, splitLog)
      assert.same({ { "attach", 0, 2, 1 }, { "send", "Alt-Realm", "S" } }, log)
    end)

    it("skips a part with no empty slot, names it, and sends the rest", function()
      free = false
      machine:Press(splitMail())
      assert.same({ { "attach", 0, 2, 1 }, { "send", "Alt-Realm", "S" } }, log)
      machine:OnSendResult(true)
      assert.same({ "#1" }, reports[1].noRoom)
    end)

    it("sends nothing and moves on when every part of a mail found no room", function()
      free = false
      local m = splitMail()
      m[1].stacks[2] = nil
      machine:Press(m)
      assert.same({}, log)
      assert.is_false(machine:IsRunning())
      assert.same({ "#1" }, reports[1].noRoom)
      assert.is_nil(reports[1].stopped)
    end)

    it("gives the part back and stops when the slot never fills within SPLIT_TICKS", function()
      landedAfter = 1000
      machine:Press(splitMail())
      for _ = 1, P.SPLIT_TICKS + 1 do
        if #timers > 0 then table.remove(timers, 1).fn() end
      end
      assert.is_true(cursorCleared)
      assert.is_false(machine:IsRunning())
      assert.equal("split", reports[1].stopped)
      assert.equal(0, count("attach") + count("send"))
    end)

    it("announces a mail only once it goes, so a mail that found no room is not counted", function()
      free = false
      local m = splitMail()
      m[1].stacks[2] = nil
      machine:Press(m)
      assert.equal(0, #progresses)
      -- And one that goes is announced when it is attached, not when the split starts.
      free = true
      reports, log = {}, {}
      machine = splitMachine()
      machine:Press(splitMail())
      assert.equal(0, #progresses)
      table.remove(timers, 1).fn()
      table.remove(timers, 1).fn()
      assert.equal(1, #progresses)
      assert.same({ index = 1, total = 1 }, { index = progresses[1].index, total = progresses[1].total })
    end)

    it("gives the part back and clears nothing of the player's when the run ends while it waits", function()
      local ends = {
        function() machine:Stop("pressed") end,
        function() machine:OnClosed() end,
        function() machine:Press(splitMail()) end,
      }
      for i, ending in ipairs(ends) do
        cursorCleared, log, reports = false, {}, {}
        landedAfter = 1000
        machine:Press(splitMail())
        assert.is_true(machine:IsRunning(), i)
        state.attached = 1 -- the player puts an item of their own in the Send Mail tab
        ending()
        assert.is_true(cursorCleared, i)
        assert.is_false(machine:IsRunning(), i)
        assert.equal(0, count("clear"), i)
        state.attached = 0
      end
    end)

    it("stops busy, clearing nothing of the player's, when they fill the Send Mail tab during the wait", function()
      machine:Press(splitMail())
      state.attached = 1
      table.remove(timers, 1).fn()
      table.remove(timers, 1).fn()
      assert.equal("busy", reports[1].stopped)
      assert.equal(0, count("clear"))
      assert.equal(0, count("attach"))
    end)

    it("leaves out a stack that changed during the wait, and attaches the rest", function()
      machine:Press(splitMail())
      -- Another item in slot 2, and more than was read in the part's own slot is checked too.
      bags[key(0, 2)] = { link = "item:other", isLocked = false, count = 1 }
      table.remove(timers, 1).fn()
      table.remove(timers, 1).fn()
      assert.same({ { "attach", 1, 5, 3 }, { "send", "Alt-Realm", "S" } }, log)
    end)

    it("leaves out a stack that grew or locked during the wait", function()
      machine:Press(splitMail())
      bags[key(0, 2)].count = 5
      table.remove(timers, 1).fn()
      table.remove(timers, 1).fn()
      assert.same({ { "attach", 1, 5, 3 }, { "send", "Alt-Realm", "S" } }, log)
    end)

    it("sends nothing for a mail whose stacks all changed during the wait", function()
      lockPart = true
      machine:Press(splitMail())
      bags[key(0, 2)].isLocked = true
      table.remove(timers, 1).fn()
      table.remove(timers, 1).fn()
      assert.equal(0, count("send"))
      assert.equal(0, count("attach"))
    end)

    it("takes out of the mail a stack removed from it during the wait", function()
      local m = splitMail()
      machine:Press(m)
      -- The group of the plain stack was set not to be sent (UI/MailAltsFrame.lua's setSkipped).
      m[1].stacks[2] = nil
      table.remove(timers, 1).fn()
      table.remove(timers, 1).fn()
      assert.same({ { "attach", 1, 5, 3 }, { "send", "Alt-Realm", "S" } }, log)
    end)

    it("stops and puts the part back when the split leaves it on the cursor", function()
      stuck = true
      machine:Press(splitMail())
      assert.equal("split", reports[1].stopped)
      assert.same({}, log)
    end)

    it("stops for something on the cursor before it splits", function()
      state.cursor = true
      machine:Press(splitMail())
      assert.same({}, splitLog)
      assert.equal("cursor", reports[1].stopped)
    end)
  end)
end)
