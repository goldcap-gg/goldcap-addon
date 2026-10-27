local _, GC = ...

-- One press that sends a run of mails, as a state machine over a driver, so every client call
-- stays in the UI file that owns the player's click (the Send to alts window). The first mail is
-- attached and sent synchronously by Press (inside the click), unless it holds a split part (below),
-- whose mail is attached and sent from a timer once the part has landed; the rest follow from
-- timers, each after re-checking that the mailbox is still open, the cursor is free, the Send Mail
-- slots are empty and each stack still sits where it was read (a mail with a split part checks its
-- stacks again right before it attaches them). A mail is sent only when the server has
-- answered the one before: MAIL_SEND_SUCCESS reaches OnSendResult(true), MAIL_FAILED
-- OnSendResult(false), MAIL_CLOSED OnClosed.
--
-- driver = {
--   open() -> boolean, reason,     -- the mail can still go; when not, why ("closed" if none given)
--   cursorBusy() -> boolean,       -- an item on the cursor, or a spell waiting for an item target
--   slot(bag, slot) -> { link, isLocked, count } | nil,
--   attach(stack) -> boolean,      -- picks the stack up and drops it into the Send Mail slots
--   split(stack) -> { bag, slot }?, why?,  -- (stacks with `split`) the first part of a split: splits
--                                  -- stack.count off the source into an empty slot of a plain bag;
--                                  -- nil and "room" (no empty slot), "cursor" or "gone" otherwise
--   landed(stack, dest) -> boolean, -- the split part shows in dest, whole and not locked
--   abandon(stack, dest),          -- it never did, or the run ended while it waited: the cursor gives
--                                  -- the part back (never left on it)
--   attached() -> number,          -- how many Send Mail slots hold an item
--   clear(),                       -- sends what is attached back to the bags
--   send(to, subject) -> false?,   -- SetSendMailCOD(0), SetSendMailMoney(0), SendMail(to, subject, "");
--                                  -- false when no gold could be made sure of, and nothing was sent
--   after(seconds, fn)             -- a timer
--   progress({ index, total, mail }),  -- right before each mail that gets attached; total leaves
--                                  -- out mails skipped as empty and a refused recipient's later ones
--   report({ sent, mails, stopped, why, failed, noRoom }),  -- once per run; stopped is nil for a finished
--                                  -- run, why the stack that would not attach ("refused"), failed
--                                  -- the recipients (mail.to) whose mail the server refused, in order
-- }
--
-- A stack with `split` (Core/BankGroups.lua's Plan: Keep leaves exactly its count) is the part of
-- a bigger stack: before its mail is attached, `split` puts that part in an empty slot of a plain bag
-- (inside the player's click when it is the first mail's) and the machine waits for `landed`, at
-- most SPLIT_TICKS ticks of SPLIT_STEP, then attaches and sends the mail from a timer, the part from
-- the slot it landed in. A part that never lands is given back (`abandon`) and the run stops,
-- "split"; so does a run that ends in any other way while a part waits, or `split` answering "stuck"
-- (the part stayed on the cursor, put back). With no empty slot (`split` answers "room") the stack is
-- skipped, named in `noRoom`. Nothing is attached before the mail goes, so a stop while a part waits
-- clears nothing from the Send Mail tab (what is there is the player's).
--
-- A stack whose slot no longer shows the same link, is locked, or holds more than was read (it
-- merged with another of its item, and would take what the group keeps) is skipped: never a
-- different item, or more of it, attached in its place. A mail with nothing left to attach is
-- skipped, not sent empty. A mail the server refuses goes back to the bags, and its recipient gets
-- nothing more in this run (a name that no longer exists, or a mailbox that is full): the run goes
-- on with the next recipient.
GC.MailPress = {}
local P = GC.MailPress

-- Seconds between a sent mail and the next one.
P.STEP = 0.5
-- Seconds to wait for the answer to a send before the run gives up.
P.SEND_WAIT = 15
-- A split part is looked for every SPLIT_STEP seconds, SPLIT_TICKS times (3 s).
P.SPLIT_STEP = 0.2
P.SPLIT_TICKS = 15

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
  if run.prep and run.prep.dest then
    self.driver.abandon(run.prep.stack, run.prep.dest)
    run.prep.dest = nil
  end
  if run.loaded and not run.issued then self.driver.clear() end
  self.driver.report({ sent = run.sent, mails = #run.mails, stopped = reason, why = why, failed = run.failedTo,
    noRoom = #run.noRoom > 0 and run.noRoom or nil })
end

local function finish(self)
  local run = self.run
  self.run = nil
  self.token = self.token + 1
  self.driver.report({ sent = run.sent, mails = #run.mails, stopped = nil, failed = run.failedTo,
    noRoom = #run.noRoom > 0 and run.noRoom or nil })
end

-- Moves run.idx past the mails of recipients whose mail the server refused in this run.
local function skipFailed(run)
  while run.idx <= #run.mails and run.failed[run.mails[run.idx].to] do run.idx = run.idx + 1 end
end

-- The `stacks` that still sit where they were read, no bigger than they were.
local function present(driver, stacks)
  local out = {}
  for _, stack in ipairs(stacks) do
    local info = driver.slot(stack.bag, stack.slot)
    if info and not info.isLocked and info.link == stack.link
      and not (type(info.count) == "number" and type(stack.count) == "number"
        and info.count > (stack.split or stack.count)) then
      out[#out + 1] = stack
    end
  end
  return out
end

-- The answer to a send did not come: give the attachments back and stop.
local function timeout(self, token, id)
  local run = self.run
  if not run or token ~= self.token or run.mailId ~= id or not run.issued then return end
  self.driver.clear()
  run.loaded = false
  stop(self, "timeout")
end

-- Attaches `stacks` as the mail in flight and sends it, then waits for the answer. Only from here
-- is anything of the Send Mail tab this run's (`loaded`), so a stop clears what it attached and
-- nothing the player put there.
local function go(self, mail, stacks)
  local run, d = self.run, self.driver
  run.shown = run.shown + 1
  d.progress({ index = run.shown, total = #run.mails - run.dropped, mail = mail })
  run.loaded, run.issued, run.mail = true, false, mail
  for _, stack in ipairs(stacks) do
    if not d.attach(stack) then return stop(self, "refused", stack) end
  end
  run.mailId = run.mailId + 1
  local token, id = self.token, run.mailId
  -- Marked in flight before the call: the driver may deliver the answer from inside send, and
  -- an answer for a mail not yet in flight is ignored.
  run.issued = true
  if d.send(mail.to, mail.subject) == false then
    -- Nothing was sent: what is attached goes back (stop clears a loaded mail not in flight).
    run.issued = false
    return stop(self, "refused")
  end
  -- Wait only when that same mail is still unanswered (an inline answer ended or moved on).
  if self.run == run and token == self.token and run.mailId == id and run.issued then
    d.after(P.SEND_WAIT, function() timeout(self, token, id) end)
  end
end

local attempt

-- Splits the parts a mail holds (stacks with `split`), one at a time, each waiting for its slot to
-- show it; then attaches and sends the mail with the parts in the slots they landed in. Called
-- inside the click for the first split, from a timer after. `prep.list` holds { stack, from } in
-- the mail's order: the stack to attach (a part is a stack of its own, in its own slot) and the
-- stack of the mail it stands for.
local function prepare(self, token, prep)
  local run, d = self.run, self.driver
  if not run or token ~= self.token or run.prep ~= prep then return end
  while true do
    local stack = prep.stacks[prep.idx]
    if not stack then break end
    -- A stack the player set not to be sent while this mail waits has left the mail: never split
    -- for it (the re-review, 2026-10-27).
    local still = false
    for _, s in ipairs(prep.mail.stacks) do still = still or s == stack end
    if not still then
      prep.idx = prep.idx + 1
    elseif not stack.split then
      prep.list[#prep.list + 1] = { stack = stack, from = stack }
      prep.idx = prep.idx + 1
    else
      local open, why = d.open()
      if not open then return stop(self, why or "closed") end
      if d.cursorBusy() then return stop(self, "cursor") end
      local dest, reason = d.split(stack)
      if not dest then
        if reason == "cursor" then return stop(self, "cursor") end
        if reason == "stuck" then return stop(self, "split", stack) end
        if reason == "room" then run.noRoom[#run.noRoom + 1] = stack.name or ("#" .. tostring(stack.itemID)) end
        prep.idx = prep.idx + 1
      else
        prep.stack, prep.dest, prep.ticks = stack, dest, 0
        local function poll()
          if not self.run or token ~= self.token or run.prep ~= prep then return end
          if d.landed(stack, dest) then
            prep.list[#prep.list + 1] = { from = stack, stack = { itemID = stack.itemID, bag = dest.bag,
              slot = dest.slot, name = stack.name, count = stack.count, link = stack.link, icon = stack.icon } }
            prep.idx, prep.dest = prep.idx + 1, nil
            return prepare(self, token, prep)
          end
          prep.ticks = prep.ticks + 1
          -- stop gives the part back (it is still pending in prep.dest).
          if prep.ticks >= P.SPLIT_TICKS then return stop(self, "split", stack) end
          d.after(P.SPLIT_STEP, poll)
        end
        return d.after(P.SPLIT_STEP, poll)
      end
    end
  end
  run.prep = nil
  -- From a timer: what the click checked is checked again. A stack the player set not to be sent
  -- meanwhile is no longer in the mail (its group's skip), and every stack must still be the item
  -- and no bigger, unlocked, as present() has it; one that changed is left out.
  local open, why = d.open()
  if not open then return stop(self, why or "closed") end
  if d.cursorBusy() then return stop(self, "cursor") end
  if d.attached() > 0 then return stop(self, "busy") end
  local inMail, kept = {}, {}
  for _, stack in ipairs(prep.mail.stacks) do inMail[stack] = true end
  for _, entry in ipairs(prep.list) do
    if inMail[entry.from] then kept[#kept + 1] = entry.stack end
  end
  local list = present(d, kept)
  if #list == 0 then
    -- Every part found no room, or nothing is left of the mail: nothing to send in it.
    run.dropped = run.dropped + 1
    return attempt(self)
  end
  go(self, prep.mail, list)
end

-- Attaches and sends mails from run.idx on, until one is in flight or the list ends.
attempt = function(self)
  local run, d = self.run, self.driver
  while true do
    skipFailed(run)
    if run.idx > #run.mails then return finish(self) end
    local open, why = d.open()
    if not open then return stop(self, why or "closed") end
    if d.cursorBusy() then return stop(self, "cursor") end
    -- Not ours: left in the slots by the player, so it is neither sent nor cleared.
    if d.attached() > 0 then return stop(self, "busy") end
    local mail = run.mails[run.idx]
    run.idx = run.idx + 1
    local stacks = present(d, mail.stacks)
    if #stacks == 0 then run.dropped = run.dropped + 1 end
    if #stacks > 0 then
      local splits = false
      for _, stack in ipairs(stacks) do splits = splits or stack.split ~= nil end
      if splits then
        local prep = { mail = mail, stacks = stacks, idx = 1, list = {}, ticks = 0 }
        run.prep, run.mail = prep, mail
        return prepare(self, self.token, prep)
      end
      return go(self, mail, stacks)
    end
  end
end

function Machine:Press(mails)
  if self.run then return stop(self, "pressed") end
  if not mails or #mails == 0 then return end
  self.token = self.token + 1
  self.run = { mails = mails, idx = 1, sent = 0, shown = 0, dropped = 0, mailId = 0, loaded = false,
    issued = false, failed = {}, failedTo = {}, noRoom = {} }
  attempt(self)
end

-- The server answered the mail in flight; an answer with no mail in flight is ignored.
function Machine:OnSendResult(ok)
  local run = self.run
  if not run or not run.issued then return end
  run.issued = false
  run.mailId = run.mailId + 1 -- the SEND_WAIT timer of this mail no longer matches
  run.loaded = false
  if ok then
    run.sent = run.sent + 1
  else
    -- MAIL_FAILED: the attachments are still in the Send Mail slots. Its recipient gets nothing
    -- more in this run.
    self.driver.clear()
    local to = run.mail.to
    if not run.failed[to] then
      run.failed[to] = true
      run.failedTo[#run.failedTo + 1] = to
      -- Its later mails will not go: they leave "Mail N of M" now.
      for i = run.idx, #run.mails do
        if run.mails[i].to == to then run.dropped = run.dropped + 1 end
      end
    end
  end
  skipFailed(run)
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
