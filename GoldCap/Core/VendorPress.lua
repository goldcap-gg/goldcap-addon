local _, GC = ...

-- One press at a vendor as a state machine over a driver, so the sale call itself stays in the
-- UI file that owns the player's click. The first sale is made synchronously by Press (inside the
-- click); the rest follow from timers, each after re-checking that the merchant is still open and
-- the slot still holds the item that was chosen.
--
-- driver = {
--   merchantOpen() -> boolean,
--   slot(bag, slot) -> { link, isLocked } | nil,
--   cursorBusy() -> boolean,       -- an item on the cursor, or a spell waiting for an item target
--   use(bag, slot)                 -- the sale call
--   after(seconds, fn)             -- a timer
--   report({ sold, copper, stopped })  -- once per run; stopped is nil for a finished run
-- }
GC.VendorPress = {}
local P = GC.VendorPress

P.STEP = 0.2
-- Ticks of STEP a sale gets to leave the bag (5 x 0.2 = 1 s); counted as integers.
P.CONFIRM_TICKS = 5

local Machine = {}
Machine.__index = Machine

function P.New(driver)
  return setmetatable({ driver = driver, oneAtATime = false, token = 0, run = nil }, Machine)
end

function Machine:IsRunning() return self.run ~= nil end

local function hasLeft(driver, row)
  local info = driver.slot(row.bag, row.slot)
  return info == nil or info.link ~= row.link
end

-- Counts the row in flight once, if it has left the bag.
local function settle(self, run)
  local row = run.cur
  if not row then return end
  run.cur = nil
  if hasLeft(self.driver, row) then
    run.sold = run.sold + 1
    run.copper = run.copper + (row.copper or 0)
  end
end

local function stop(self, reason)
  local run = self.run
  if not run then return end
  settle(self, run)
  self.run = nil
  self.token = self.token + 1
  self.driver.report({ sold = run.sold, copper = run.copper, stopped = reason })
end

local function finish(self)
  local run = self.run
  self.run = nil
  self.token = self.token + 1
  self.driver.report({ sold = run.sold, copper = run.copper, stopped = nil })
end

local attempt

local function tick(self, token)
  local run = self.run
  if not run or token ~= self.token then return end
  local row = run.cur
  if hasLeft(self.driver, row) then
    settle(self, run)
    if run.sold >= run.limit then return finish(self) end
    return attempt(self, true)
  end
  run.ticks = run.ticks + 1
  if run.ticks >= P.CONFIRM_TICKS then
    if run.fromTimer then
      self.oneAtATime = true
      return stop(self, "slow")
    end
    return stop(self, "refused")
  end
  self.driver.after(P.STEP, function() tick(self, token) end)
end

attempt = function(self, fromTimer)
  local run, d = self.run, self.driver
  while true do
    if run.idx > #run.rows then return finish(self) end
    if not d.merchantOpen() then return stop(self, "closed") end
    if d.cursorBusy() then return stop(self, "cursor") end
    local row = run.rows[run.idx]
    run.idx = run.idx + 1
    local info = d.slot(row.bag, row.slot)
    if info and not info.isLocked and info.link == row.link then
      run.cur, run.ticks, run.fromTimer = row, 0, fromTimer
      d.use(row.bag, row.slot)
      local token = self.token
      d.after(P.STEP, function() tick(self, token) end)
      return
    end
  end
end

function Machine:Press(rows)
  if self.run then return stop(self, "pressed") end
  if not rows or #rows == 0 then return end
  self.token = self.token + 1
  self.run = {
    rows = rows, idx = 1, sold = 0, copper = 0, ticks = 0, fromTimer = false,
    limit = self.oneAtATime and 1 or GC.VendorSelect.MAX_STACKS,
  }
  attempt(self, false)
end

function Machine:Stop(reason) stop(self, reason) end

function Machine:OnMerchantClosed()
  if self.run then stop(self, "closed") end
end

-- A new visit: forget the one-per-press mode and drop any run without a report.
function Machine:OnMerchantShow()
  self.oneAtATime = false
  self.run = nil
  self.token = self.token + 1
end
