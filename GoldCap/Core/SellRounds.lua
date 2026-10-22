-- How many times an item came back unsold since its last sale: the "rounds" a followed flip
-- group's rule posts it a little cheaper for (Core/SellPositions.lua's step-down). Retail only:
-- GoldCap_Camelot.toc does not load this file, so every caller asks `if GC.SellRounds`.
--
-- A round is a lot that came back EXPIRED, read from the returns log (GC.MailReturns, entries
-- `{ itemID, count, reason = "expired" | "cancelled", at }`, `at` in wall clock seconds). The
-- ledger's inbox scan (Core/Ledger.lua's ScanInbox) writes an entry the first time it reads the
-- lot's mail, however that mail is then taken. A cancelled lot does not count: the player chose to
-- take it down. Returns of one item logged within ROUND_GAP_SECONDS of the last one counted are
-- one round, so five copies of one flip coming back in one mailbox visit cut its price once, not
-- five times. A sale of the item (a new sale mail, read by the same scan) sets the count back to 0,
-- and returns from before that sale never count again. A return stamped in the same second as the
-- sale counts as after it: one scan stamps a sale and a lot it reads in the same pass with the same
-- `now`, and a batch's unsold lots expire after its sales. Ingesting the same log twice adds nothing.
--
-- An entry younger than SETTLE_SECONDS is read afresh from the log on every Ingest and never
-- written into the save, so while it is young the count follows the log; an older entry is counted
-- once, for good, as above.
--
-- Saved in GC.db.sellRounds = { v = 1, lastReturnAt, items = { [itemID] = { rounds, returnAt,
-- soldAt, at } } }, created lazily here and not through DEFAULTS, so a client that never loads
-- this file keeps its SavedVariables as they were. A save with a newer `v` is read-only: nothing
-- writes to it and every item reads 0 rounds. An item untouched for PRUNE_SECONDS is dropped.
local _, GC = ...
GC.SellRounds = {}
local M = GC.SellRounds

M.VERSION = 1
M.PRUNE_SECONDS = 30 * 86400
M.ROUND_GAP_SECONDS = 3600
-- How long an entry is counted from the log before it is counted into the save.
M.SETTLE_SECONDS = 3600

-- The live table (db.sellRounds) when it is ours to write, else nil.
local store
-- The rounds of entries not yet settled, by item: { ats = sorted `at`s, rounds = n }. Rebuilt from
-- the log by every Ingest and never saved: the log they come from is.
local fresh = {}

local function finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function itemKey(v)
  return finite(v) and v > 0 and v % 1 == 0
end

function M.Init(db)
  store, fresh = nil, {}
  if type(db) ~= "table" then return end
  local saved = db.sellRounds
  if type(saved) == "table" and type(saved.v) == "number" and saved.v > M.VERSION then return end
  if type(saved) ~= "table" or saved.v ~= M.VERSION then
    saved = { v = M.VERSION, lastReturnAt = 0, items = {} }
    db.sellRounds = saved
  end
  if not finite(saved.lastReturnAt) then saved.lastReturnAt = 0 end
  if type(saved.items) ~= "table" then saved.items = {} end
  store = saved
end

function M.Prune(now)
  if not store or not finite(now) then return 0 end
  local cutoff, dropped = now - M.PRUNE_SECONDS, 0
  for id, item in pairs(store.items) do
    if type(item) ~= "table" or not finite(item.at) or item.at < cutoff then
      store.items[id] = nil
      dropped = dropped + 1
    end
  end
  return dropped
end

-- Whether a return at `at` came before the item's last sale and so never counts. At the same
-- second it is after the sale (see the header).
local function beforeSale(item, at)
  return item ~= nil and finite(item.soldAt) and at < item.soldAt
end

-- How many rounds the returns at `ats` (sorted) add to `item`, the saved state, without writing
-- it: the same sale and hour rules Ingest counts by.
local function roundsAfter(item, ats)
  local last = item and finite(item.returnAt) and item.returnAt or nil
  local n = 0
  for _, at in ipairs(ats) do
    if not beforeSale(item, at) and not (last and at < last + M.ROUND_GAP_SECONDS) then
      n, last = n + 1, at
    end
  end
  return n
end

-- `entries` is the log as GC.MailReturns.Entries() hands it (an array), or a table holding it
-- as `.entries`; nil is no returns. Returns how many rounds it added, less any that an entry taken
-- back since the last Ingest had given.
function M.Ingest(entries, now)
  if not store or type(entries) ~= "table" or not finite(now) then return 0 end
  local list = type(entries.entries) == "table" and entries.entries or entries
  local readable = {}
  for _, entry in ipairs(list) do
    if type(entry) == "table" and itemKey(entry.itemID) and finite(entry.at) then
      readable[#readable + 1] = entry
    end
  end
  -- Oldest first, so the hour between two counted returns is measured from the earlier one.
  table.sort(readable, function(a, b) return a.at < b.at end)
  local settled = now - M.SETTLE_SECONDS
  local added, newest = 0, store.lastReturnAt
  local young = {}
  for _, entry in ipairs(readable) do
    local at = entry.at
    if at >= settled then
      -- Not settled: the mail loop may still take it back. Counted below, never into the save.
      if entry.reason == "expired" and at >= store.lastReturnAt then
        local ats = young[entry.itemID] or {}
        young[entry.itemID] = ats
        ats[#ats + 1] = at
      end
    else
      if entry.reason == "expired" and at >= store.lastReturnAt then
        local item = store.items[entry.itemID]
        if not beforeSale(item, at)
            and not (item and finite(item.returnAt) and at < item.returnAt + M.ROUND_GAP_SECONDS) then
          if not item then
            item = { rounds = 0 }
            store.items[entry.itemID] = item
          end
          item.rounds = (finite(item.rounds) and item.rounds or 0) + 1
          item.returnAt, item.at = at, now
          added = added + 1
        end
      end
      if at > newest then newest = at end
    end
  end
  store.lastReturnAt = newest
  M.Prune(now)
  for _, f in pairs(fresh) do added = added - f.rounds end
  fresh = {}
  for itemID, ats in pairs(young) do
    local n = roundsAfter(store.items[itemID], ats)
    fresh[itemID] = { ats = ats, rounds = n }
    added = added + n
  end
  return added
end

-- A sale of `itemID` at `at`: the count goes back to 0. False when a sale at or after `at` was
-- already recorded, or when nothing may be written.
function M.Sold(itemID, at)
  if not store or not itemKey(itemID) or not finite(at) then return false end
  local item = store.items[itemID]
  if item and finite(item.soldAt) and at <= item.soldAt then return false end
  if not item then
    item = {}
    store.items[itemID] = item
  end
  item.rounds, item.soldAt, item.at = 0, at, at
  local f = fresh[itemID]
  if f then f.rounds = roundsAfter(item, f.ats) end
  return true
end

function M.Rounds(itemID)
  if not store then return 0 end
  local item = store.items[itemID]
  local n = type(item) == "table" and finite(item.rounds) and item.rounds > 0 and item.rounds or 0
  local f = fresh[itemID]
  return n + (f and f.rounds or 0)
end
