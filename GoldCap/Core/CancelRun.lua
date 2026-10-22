-- The CANCEL button's run over the cancel queue: the first press arms the whole queue and says
-- how many lots and what deposits they forfeit; a press at least ARM_SECONDS later confirms it and
-- cancels the head lot; every press after that cancels the next lot, until IDLE_SECONDS pass
-- without a press or the queue is empty. A run cancels only the lots its confirm counted: a lot
-- that reaches the head later is not in the count or the deposits the player saw, so the press
-- on it arms again. This module only decides what a press does. The press
-- itself, and the one CancelAuction it may make, stay in UI/Sell/Dock.lua (onCancelQueueClick,
-- ROW.runLot): a protected call is the player's own click, one per click (docs/addon/AGENTS.md
-- "Protected actions"). Pure, with the clock passed in. Retail only: GoldCap_Camelot.toc does not
-- load this file, and the dock keeps its two-press arm per lot when GC.CancelRun is nil.
local _, GC = ...
GC.CancelRun = {}
local M = GC.CancelRun

-- The same deposit guard as a lot's own Cancel lot (REPOST_ARM_SECONDS and REPOST_TIMEOUT_SECONDS
-- in Services/Sell/Post.lua): a double click is not a confirm, and a run left alone lapses.
M.ARM_SECONDS = 1
M.IDLE_SECONDS = 20

-- A run over `entries` (the cancel queue, head first), or nil when there is nothing to run.
-- `costOf(auctionID)` is the deposit the client says a cancel forfeits; one it cannot say makes
-- `cost` nil, never a smaller total.
function M.Start(entries, costOf, now)
  if type(entries) ~= "table" or #entries == 0 then return nil end
  local cost = type(costOf) == "function" and 0 or nil
  for _, entry in ipairs(entries) do
    if not cost then break end
    local ok, value = pcall(costOf, entry.auctionID)
    if not ok or type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
      cost = nil
    else
      cost = cost + value
    end
  end
  local ids = {}
  for _, entry in ipairs(entries) do ids[entry.auctionID] = true end
  return { stage = "armed", count = #entries, cost = cost, armedAt = now, lastPressAt = now, ids = ids }
end

-- Whether the run's confirm counted this lot.
function M.Covers(run, entry)
  return type(run) == "table" and type(run.ids) == "table" and type(entry) == "table"
    and run.ids[entry.auctionID] == true
end

-- How many of the queue's lots the run's confirm counted: what is left of the run.
function M.Left(run, entries)
  local left = 0
  for _, entry in ipairs(entries or {}) do
    if M.Covers(run, entry) then left = left + 1 end
  end
  return left
end

function M.Expired(run, now)
  return type(run) == "table" and now - run.lastPressAt > M.IDLE_SECONDS
end

-- What a press at `now` does: "expired" (arm again), "early" (a confirm inside ARM_SECONDS:
-- nothing), "done" (the queue is empty), "changed" (the head is a lot the confirm did not count:
-- arm again), or "cancel" with the head entry, which marks the run running from this press. A
-- confirmed lot stays the run's while it is queued, so a press that could not reach it leaves it
-- for the next.
function M.Press(run, entries, now)
  if M.Expired(run, now) then return "expired" end
  if #entries == 0 then return "done" end
  if not M.Covers(run, entries[1]) then return "changed" end
  if run.stage == "armed" and now - run.armedAt < M.ARM_SECONDS then return "early" end
  run.stage, run.lastPressAt = "running", now
  return "cancel", entries[1]
end
