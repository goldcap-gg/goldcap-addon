local _, GC = ...

-- The returned-lots log: one entry for every lot that came back to the mailbox (expired, or
-- cancelled by the player). SELL's unsold-rounds count reads it (the groups-in-the-addon design,
-- section 5). The ledger's inbox scan writes it (Core/Ledger.lua, ScanInbox, through Observe
-- below): that scan reads every row on MAIL_SHOW and MAIL_INBOX_UPDATE, so a lot is logged when
-- it is seen, however the player then takes it (Collect, Blizzard's Open All, another mail addon,
-- a click on the attachment) or leaves it.
--
-- Entries are exactly { itemID, count, reason = "expired" | "cancelled", at }, one per lot even when
-- the lot comes back in several stacks, with `count` the stacks' sum and `at` the wall clock time
-- of the scan that first read it. They are pruned after 14 days and the log is versioned: a newer
-- save is read-only here, so an older build never rewrites a shape it does not know. The log is
-- created lazily, not through DEFAULTS, so a client that never loads this file (WoW: Forever)
-- keeps its SavedVariables untouched.

GC.MailReturns = {}

local VERSION = 1
local RETENTION_SECONDS = 14 * 86400
-- How far apart two reads of one mail's expiry may be and still be that mail: the ledger's own
-- margin for an invoice (Core/Ledger.lua, BUCKET_MATCH_TOLERANCE, 13 buckets of five minutes),
-- for the same reason: a fresh delivery can read half an hour off between two scans.
local MATCH_SECONDS = 13 * 300

GC.MailReturns.VERSION = VERSION
GC.MailReturns.RETENTION_SECONDS = RETENTION_SECONDS
GC.MailReturns.MATCH_SECONDS = MATCH_SECONDS

local db
local readOnly = false

local function isPositiveInteger(value)
  return type(value) == "number" and value == math.floor(value) and value > 0 and value < math.huge
end

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
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
  if type(db.mailReturnsSeen) ~= "table" then db.mailReturnsSeen = {} end
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

-- The lots one inbox scan read, each { itemID, count, reason, expiresAt }, `expiresAt` being the
-- mail's expiry in wall clock seconds. A lot is logged the first time a scan reads it; a mail read
-- again on every later scan is not, by the rule the ledger keeps for an invoice. The lots seen in
-- this character's inbox are kept in db.mailReturnsSeen as { char, region, reason, itemID,
-- expiresAt }: a read is a lot already seen when one of them has the same item and reason and an
-- expiry within MATCH_SECONDS, each matched by one read at most, so two lots that read the same are
-- two. The count is left out, so a lot taken one stack at a time stays the one lot. A seen lot is
-- added on every scan, and goes only when a `complete` scan (every row read, every attachment of a
-- returned lot named) no longer holds it, or once its mail has expired. Returns how many it logged.
function GC.MailReturns.Observe(lots, context, now, complete)
  if not db or readOnly or type(db.mailReturns) ~= "table" or not finite(now) then return 0 end
  if type(context) ~= "table" or type(context.char) ~= "string" or context.char == ""
      or type(context.region) ~= "string" or context.region == "" then return 0 end
  if type(db.mailReturnsSeen) ~= "table" then db.mailReturnsSeen = {} end
  local seen = db.mailReturnsSeen
  local function mine(record)
    return type(record) == "table" and record.char == context.char and record.region == context.region
  end
  local used, logged = {}, 0
  for _, lot in ipairs(type(lots) == "table" and lots or {}) do
    if type(lot) == "table" and finite(lot.expiresAt) then
      local match, gap
      for _, record in ipairs(seen) do
        if not used[record] and mine(record) and record.reason == lot.reason and record.itemID == lot.itemID
            and finite(record.expiresAt) then
          local apart = math.abs(record.expiresAt - lot.expiresAt)
          if apart <= MATCH_SECONDS and (not gap or apart < gap) then match, gap = record, apart end
        end
      end
      if match then
        used[match] = true
      elseif GC.MailReturns.Record(lot.itemID, lot.count, lot.reason, now) then
        local record = { char = context.char, region = context.region, reason = lot.reason,
          itemID = lot.itemID, expiresAt = lot.expiresAt }
        seen[#seen + 1] = record
        used[record] = true
        logged = logged + 1
      end
    end
  end
  local kept = {}
  for _, record in ipairs(seen) do
    local gone = complete and mine(record) and not used[record]
    local expired = type(record) ~= "table" or not finite(record.expiresAt)
      or record.expiresAt + MATCH_SECONDS < now
    if not gone and not expired then kept[#kept + 1] = record end
  end
  db.mailReturnsSeen = kept
  return logged
end
