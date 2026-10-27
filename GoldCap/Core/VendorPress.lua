local _, GC = ...

-- One press that makes a run of container calls, as a state machine over a driver, so the call
-- itself stays in the UI file that owns the player's click: at a vendor, the sales of
-- UI/VendorSellCard.lua; at a bank, the moves of the GoldCap Hoard, UI/HoardFrame.lua. The first
-- call is made synchronously by Press (inside the click); the rest follow from timers, each after
-- re-checking that the window is still open and the slot still holds the item that was chosen.
--
-- driver = {
--   open() -> boolean,             -- the window the calls need is still open (the merchant, the bank)
--   slot(bag, slot) -> { link, isLocked } | nil,
--   cursorBusy() -> boolean,       -- an item on the cursor, or a spell waiting for an item target
--   use(bag, slot, row) -> false?, why?  -- the call; false when it made none (the row is skipped);
--                                  -- a row with `split` is the first part of a split (below)
--   landed(row) -> boolean         -- (rows with `split`) the split part shows in row.dest, whole
--   part(row) -> row               -- (rows with `split`) the row that moves the part in row.dest,
--                                  -- which `use` then moves as any row
--   abandon(row)                   -- (rows with `split`) the part never showed: give it back
--   after(seconds, fn)             -- a timer
--   report({ sold, copper, stopped, noRoom })  -- once per run; stopped is nil for a finished run,
--                                  -- noRoom the names (row.name) of splits that found no empty slot
--   limit = n | nil,               -- the most calls one press makes; nil: every row
--   slowFallback = true | nil,     -- a timer call that stays switches the visit to one per press
-- }
--
-- A row with `split` (the count its source slot holds) moves a part of a stack, in two parts: `use`
-- splits it into an empty slot (and sets row.dest = { bag, slot }), then the machine waits for
-- `landed`, at most CONFIRM_TICKS ticks of STEP, and moves `part`'s row with `use` from a timer; the
-- part is then confirmed as any stack is, by its slot in row.dest. A part that never lands is given back
-- (`abandon`) and the run stops, "split". `use` answering false and "room" means no empty slot to
-- split into: the row is skipped and its name is reported in noRoom.
--
-- `slowFallback` is the vendor's: whether a sale made from a timer is honoured was not measured
-- (docs/superpowers/specs/2026-10-22-vendor-in-one-press-design.md), so a timer sale that stays in
-- the bag says the game sells one stack per press there. The bank leaves it off: a move that stays
-- is mostly a bank or bags with no room, which the game says itself, and one per press for the
-- visit would be wrong for that. Its run just stops ("stalled"), and the next press still makes
-- its first move inside the click, as every press did before runs.
GC.VendorPress = {}
local P = GC.VendorPress

P.STEP = 0.2
-- Ticks of STEP a sale gets to leave the bag (15 x 0.2 = 3 s); counted as integers. The slot
-- empties when the server answers, and a slow connection takes well over a second: at 1 s a
-- high-latency visit fell back to one stack per press, and a sale in the click ended silently.
P.CONFIRM_TICKS = 15

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
  self.driver.report({ sold = run.sold, copper = run.copper, stopped = reason, noRoom = #run.noRoom > 0 and run.noRoom or nil })
end

local function finish(self)
  local run = self.run
  self.run = nil
  self.token = self.token + 1
  self.driver.report({ sold = run.sold, copper = run.copper, stopped = nil, noRoom = #run.noRoom > 0 and run.noRoom or nil })
end

local attempt

local function tick(self, token)
  local run = self.run
  if not run or token ~= self.token then return end
  local row = run.cur
  if run.splitting then
    local d = self.driver
    if d.landed(row) then
      run.splitting = false
      if not d.open() then return stop(self, "closed") end
      if d.cursorBusy() then return stop(self, "cursor") end
      -- The part, from here on, is the row: its slot is what leaves.
      local part = d.part(row)
      if d.use(part.bag, part.slot, part) == false then
        run.cur = nil
        return attempt(self, true)
      end
      run.cur, run.ticks, run.fromTimer = part, 0, true
      return d.after(P.STEP, function() tick(self, token) end)
    end
    run.ticks = run.ticks + 1
    if run.ticks >= P.CONFIRM_TICKS then
      d.abandon(row)
      return stop(self, "split")
    end
    return d.after(P.STEP, function() tick(self, token) end)
  end
  if hasLeft(self.driver, row) then
    settle(self, run)
    if run.sold >= run.limit then return finish(self) end
    return attempt(self, true)
  end
  run.ticks = run.ticks + 1
  if run.ticks >= P.CONFIRM_TICKS then
    if run.fromTimer then
      if not self.driver.slowFallback then return stop(self, "stalled") end
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
    if not d.open() then return stop(self, "closed") end
    if d.cursorBusy() then return stop(self, "cursor") end
    local row = run.rows[run.idx]
    run.idx = run.idx + 1
    local kept = row.itemID ~= nil and run.skip[row.itemID]
    local info = not kept and d.slot(row.bag, row.slot) or nil
    local whole = info and not info.isLocked and info.link == row.link
      and not (row.split and info.count ~= nil and info.count ~= row.split)
    if whole then
      local used, why = d.use(row.bag, row.slot, row)
      if used ~= false then
        run.cur, run.ticks, run.fromTimer, run.splitting = row, 0, fromTimer, row.split ~= nil
        local token = self.token
        d.after(P.STEP, function() tick(self, token) end)
        return
      elseif why == "room" then
        run.noRoom[#run.noRoom + 1] = row.name or ("#" .. tostring(row.itemID))
      end
    end
  end
end

function Machine:Press(rows)
  if self.run then return stop(self, "pressed") end
  if not rows or #rows == 0 then return end
  self.token = self.token + 1
  self.run = {
    rows = rows, idx = 1, sold = 0, copper = 0, ticks = 0, fromTimer = false, skip = {}, noRoom = {},
    limit = self.oneAtATime and 1 or self.driver.limit or math.huge,
  }
  attempt(self, false)
end

-- Never sell this, chosen while a press runs: the item's rows still to come are skipped. A sale
-- already made stays made (Buyback has it).
function Machine:Skip(itemID)
  if self.run and itemID ~= nil then self.run.skip[itemID] = true end
end

function Machine:Stop(reason) stop(self, reason) end

function Machine:OnClosed()
  if self.run then stop(self, "closed") end
end

-- A new visit: forget the one-per-press mode and drop any run without a report.
function Machine:OnShown()
  self.oneAtATime = false
  self.run = nil
  self.token = self.token + 1
end
