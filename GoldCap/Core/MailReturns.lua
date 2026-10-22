local _, GC = ...

-- The returned-lots log: one entry for every lot that came back to the mailbox (expired, or
-- cancelled by the player) and that the Collect button took. SELL's unsold-rounds count reads
-- it (the groups-in-the-addon design, section 5). An entry is
-- written BEFORE the items are taken, because the mail's own record is gone afterwards; the loop
-- retracts it when the take turns out to have done nothing (Core/MailLoop.lua).
--
-- Entries are exactly { itemID, count, reason = "expired" | "cancelled", at }, one per lot even when
-- the lot comes back in several stacks, with `count` the stacks' sum. They are pruned
-- after 14 days and the log is versioned: a newer save is read-only here, so an older build never
-- rewrites a shape it does not know. The log is created lazily, not through DEFAULTS, so a
-- client that never loads this file (WoW: Forever) keeps its SavedVariables untouched.

GC.MailReturns = {}

local VERSION = 1
local RETENTION_SECONDS = 14 * 86400

GC.MailReturns.VERSION = VERSION
GC.MailReturns.RETENTION_SECONDS = RETENTION_SECONDS

local db
local readOnly = false

local function isPositiveInteger(value)
  return type(value) == "number" and value == math.floor(value) and value > 0 and value < math.huge
end

function GC.MailReturns.Entries()
  if db and type(db.mailReturns) == "table" then return db.mailReturns end
  return {}
end

-- Drops entries older than the retention window; returns how many went.
function GC.MailReturns.Prune(now)
  if not db or readOnly or type(db.mailReturns) ~= "table" or type(now) ~= "number" then return 0 end
  local cutoff = now - RETENTION_SECONDS
  local kept, dropped = {}, 0
  for _, entry in ipairs(db.mailReturns) do
    if type(entry) == "table" and type(entry.at) == "number" and entry.at < cutoff then
      dropped = dropped + 1
    else
      kept[#kept + 1] = entry
    end
  end
  if dropped > 0 then
    -- In place: SELL holds the array Entries() handed out.
    for i = #db.mailReturns, 1, -1 do db.mailReturns[i] = nil end
    for i, entry in ipairs(kept) do db.mailReturns[i] = entry end
  end
  return dropped
end

function GC.MailReturns.Init(savedDb)
  db, readOnly = nil, false
  if type(savedDb) ~= "table" then return end
  db = savedDb
  if type(db.mailReturnsVersion) == "number" and db.mailReturnsVersion > VERSION then
    readOnly = true
    return
  end
  if type(db.mailReturns) ~= "table" then db.mailReturns = {} end
  if db.mailReturnsVersion == nil then db.mailReturnsVersion = VERSION end
  GC.MailReturns.Prune(time())
end

function GC.MailReturns.Record(itemID, count, reason, now)
  if not db or readOnly or type(db.mailReturns) ~= "table" then return nil end
  if not isPositiveInteger(itemID) or not isPositiveInteger(count) then return nil end
  if reason ~= "expired" and reason ~= "cancelled" then return nil end
  if type(now) ~= "number" then return nil end
  GC.MailReturns.Prune(now)
  local entry = { itemID = itemID, count = count, reason = reason, at = now }
  db.mailReturns[#db.mailReturns + 1] = entry
  return entry
end

-- Removes that exact entry (by identity), for a take that did nothing.
function GC.MailReturns.Retract(entry)
  if not db or readOnly or type(db.mailReturns) ~= "table" then return false end
  for i, stored in ipairs(db.mailReturns) do
    if stored == entry then
      table.remove(db.mailReturns, i)
      return true
    end
  end
  return false
end
