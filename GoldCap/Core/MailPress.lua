local _, GC = ...

-- One press that sends a run of mails, as a state machine over a driver, so every client call
-- stays in the UI file that owns the player's click (the Send to alts window). The first mail is
-- attached and sent synchronously by Press (inside the click); the rest follow from timers, each
-- after re-checking that the mailbox is still open, the cursor is free, the Send Mail slots are
-- empty and each stack still sits where it was read. A mail is sent only when the server has
-- answered the one before: MAIL_SEND_SUCCESS reaches OnSendResult(true), MAIL_FAILED
-- OnSendResult(false), MAIL_CLOSED OnClosed.
--
-- driver = {
--   open() -> boolean,             -- the mailbox is still open
--   cursorBusy() -> boolean,       -- an item on the cursor, or a spell waiting for an item target
--   slot(bag, slot) -> { link, isLocked } | nil,
--   attach(stack) -> boolean,      -- picks the stack up and drops it into the Send Mail slots
--   attached() -> number,          -- how many Send Mail slots hold an item
--   clear(),                       -- sends what is attached back to the bags
--   send(to, subject),             -- SetSendMailCOD(0), SetSendMailMoney(0), SendMail(to, subject, "")
--   after(seconds, fn)             -- a timer
--   progress({ index, total, mail }),  -- right before each mail that gets attached
--   report({ sent, mails, stopped, why }),  -- once per run; stopped is nil for a finished run,
--                                           -- why is the stack that would not attach ("refused")
-- }
--
-- A stack whose slot no longer shows the same link, or is locked, is skipped: never a different
-- item attached in its place. A mail with nothing left to attach is skipped, not sent empty.
GC.MailPress = {}
local P = GC.MailPress

-- Seconds between a sent mail and the next one.
P.STEP = 0.5
-- Seconds to wait for the answer to a send before the run gives up.
P.SEND_WAIT = 15

local Machine = {}
Machine.__index = Machine

function P.New(driver)
  return setmetatable({ driver = driver, token = 0, run = nil }, Machine)
end

function Machine:IsRunning() return self.run ~= nil end

-- Ends the run once, reporting what was confirmed. Whatever is attached and not yet sent goes
-- back to the bags; a mail already handed to SendMail is the server's, so it is left alone.
local function stop(self, reason, why)
  local run = self.run
  if not run then return end
  self.run = nil
  self.token = self.token + 1
  if run.loaded and not run.issued then self.driver.clear() end
  self.driver.report({ sent = run.sent, mails = #run.mails, stopped = reason, why = why })
end

local function finish(self)
  local run = self.run
  self.run = nil
  self.token = self.token + 1
  self.driver.report({ sent = run.sent, mails = #run.mails, stopped = nil })
end

-- The stacks of a mail that still sit where they were read.
local function present(driver, mail)
  local out = {}
  for _, stack in ipairs(mail.stacks) do
    local info = driver.slot(stack.bag, stack.slot)
    if info and not info.isLocked and info.link == stack.link then out[#out + 1] = stack end
  end
  return out
end

local attempt

-- The answer to a send did not come: give the attachments back and stop.
local function timeout(self, token, id)
  local run = self.run
  if not run or token ~= self.token or run.mailId ~= id or not run.issued then return end
  self.driver.clear()
  run.loaded = false
  stop(self, "timeout")
end

-- Attaches and sends mails from run.idx on, until one is in flight or the list ends.
attempt = function(self)
  local run, d = self.run, self.driver
  while true do
    if run.idx > #run.mails then return finish(self) end
    if not d.open() then return stop(self, "closed") end
    if d.cursorBusy() then return stop(self, "cursor") end
    -- Not ours: left in the slots by the player, so it is neither sent nor cleared.
    if d.attached() > 0 then return stop(self, "busy") end
    local mail = run.mails[run.idx]
    run.idx = run.idx + 1
    local stacks = present(d, mail)
    if #stacks > 0 then
      run.shown = run.shown + 1
      d.progress({ index = run.shown, total = #run.mails, mail = mail })
      run.loaded, run.issued = true, false
      for _, stack in ipairs(stacks) do
        if not d.attach(stack) then return stop(self, "refused", stack) end
      end
      run.mailId = run.mailId + 1
      local token, id = self.token, run.mailId
      d.send(mail.to, mail.subject)
      run.issued = true
      d.after(P.SEND_WAIT, function() timeout(self, token, id) end)
      return
    end
  end
end

function Machine:Press(mails)
  if self.run then return stop(self, "pressed") end
  if not mails or #mails == 0 then return end
  self.token = self.token + 1
  self.run = { mails = mails, idx = 1, sent = 0, shown = 0, mailId = 0, loaded = false, issued = false }
  attempt(self)
end

-- The server answered the mail in flight; an answer with no mail in flight is ignored.
function Machine:OnSendResult(ok)
  local run = self.run
  if not run or not run.issued then return end
  run.issued = false
  run.mailId = run.mailId + 1 -- the SEND_WAIT timer of this mail no longer matches
  if not ok then
    -- MAIL_FAILED: the attachments are still in the Send Mail slots.
    self.driver.clear()
    run.loaded = false
    return stop(self, "failed")
  end
  run.loaded = false
  run.sent = run.sent + 1
  if run.idx > #run.mails then return finish(self) end
  local token = self.token
  self.driver.after(P.STEP, function()
    if self.run and token == self.token then attempt(self) end
  end)
end

function Machine:Stop(reason) stop(self, reason) end

function Machine:OnClosed()
  if self.run then stop(self, "closed") end
end
