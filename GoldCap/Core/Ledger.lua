local _, GC = ...

GC.Ledger = {}

local db

-- Roughly a year of active goldmaking at a few dozen mails a day, and far below
-- the size at which SavedVariables writes start costing a noticeable logout
-- pause. The ledger is never pruned by AGE -- unlike db.flips, which is a
-- resale to-do list -- because a profit history whose old rows silently vanish
-- is worse than no history at all.
GC.Ledger.MAX_ENTRIES = 5000

-- Every money field an auction invoice reports, joined. Deliberately EXCLUDES
-- moneyDelay/etaHour/etaMin: those are exactly the fields that change when a
-- "Sale Pending" invoice matures into a paid one on the very same mail, and
-- keying on them would turn one sale into two rows -- the most common
-- accounting bug in this class of addon.
function GC.Ledger.EntryKey(fields)
  return table.concat({
    tostring(fields.sender or ""),
    tostring(fields.itemName or ""),
    tostring(fields.count or 0),
    tostring(fields.bid or 0),
    tostring(fields.buyout or 0),
    tostring(fields.deposit or 0),
    tostring(fields.consignment or 0),
    tostring(fields.expiresAt or 0),
  }, "\1")
end

function GC.Ledger.Init(database)
  db = database
  db.ledger = db.ledger or {}
  db.gold = db.gold or {}
end

local function indexOf(key)
  local entries = db and db.ledger
  if not entries then return nil end
  for i = 1, #entries do
    if entries[i].key == key then return i end
  end
  return nil
end

-- Evicts one row to make space: the oldest ALREADY-UPLOADED row first, because
-- losing it costs nothing (the server has it), and only when there is no such
-- row does it fall back to the oldest row overall.
local function evictOne(entries)
  local victim, victimAt
  for i = 1, #entries do
    if entries[i].uploaded and (victimAt == nil or (entries[i].at or 0) < victimAt) then
      victim, victimAt = i, entries[i].at or 0
    end
  end
  if not victim then
    for i = 1, #entries do
      if victimAt == nil or (entries[i].at or 0) < victimAt then
        victim, victimAt = i, entries[i].at or 0
      end
    end
  end
  if victim then table.remove(entries, victim) end
end

-- Returns entry, isNew. A repeat key UPDATES the stored row rather than
-- appending: the mailbox re-reports the same invoice on every
-- MAIL_INBOX_UPDATE until the player collects it, and a Sale Pending row
-- legitimately changes once, when the money lands.
function GC.Ledger.Append(entry)
  if not db then return entry, false end
  local entries = db.ledger

  local existing = indexOf(entry.key)
  if existing then
    local stored = entries[existing]
    for k, v in pairs(entry) do stored[k] = v end
    -- The row's contents changed, so any prior upload is now out of date.
    stored.uploaded = nil
    return stored, false
  end

  entries[#entries + 1] = entry
  while #entries > GC.Ledger.MAX_ENTRIES do
    evictOne(entries)
  end
  return entry, true
end

function GC.Ledger.GetEntries()
  return (db and db.ledger) or {}
end

function GC.Ledger.MarkUploaded(keys)
  if not db then return 0 end
  local marked = 0
  for _, key in ipairs(keys or {}) do
    local i = indexOf(key)
    if i then
      db.ledger[i].uploaded = true
      marked = marked + 1
    end
  end
  return marked
end
