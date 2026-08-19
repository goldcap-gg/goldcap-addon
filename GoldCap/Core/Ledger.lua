local _, GC = ...

GC.Ledger = {}

local db
local MAX_EXACT = 9007199254740991

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
  db.mailOccurrences = type(db.mailOccurrences) == "table" and db.mailOccurrences or {}
  db.mailOccurrenceSeq = type(db.mailOccurrenceSeq) == "number"
    and db.mailOccurrenceSeq == math.floor(db.mailOccurrenceSeq)
    and db.mailOccurrenceSeq >= 0 and db.mailOccurrenceSeq <= MAX_EXACT
    and db.mailOccurrenceSeq or 0
  db.mailOccurrenceGeneration = type(db.mailOccurrenceGeneration) == "number"
    and db.mailOccurrenceGeneration == math.floor(db.mailOccurrenceGeneration)
    and db.mailOccurrenceGeneration >= 0 and db.mailOccurrenceGeneration <= MAX_EXACT
    and db.mailOccurrenceGeneration or 0
  for _, occurrence in ipairs(db.mailOccurrences) do
    if type(occurrence.sequence) == "number" and occurrence.sequence == math.floor(occurrence.sequence)
        and occurrence.sequence >= 0 and occurrence.sequence <= MAX_EXACT
        and occurrence.sequence > db.mailOccurrenceSeq then
      db.mailOccurrenceSeq = occurrence.sequence
    end
    if type(occurrence.lastPresentGeneration) == "number"
        and occurrence.lastPresentGeneration == math.floor(occurrence.lastPresentGeneration)
        and occurrence.lastPresentGeneration >= 0 and occurrence.lastPresentGeneration <= MAX_EXACT
        and occurrence.lastPresentGeneration > db.mailOccurrenceGeneration then
      db.mailOccurrenceGeneration = occurrence.lastPresentGeneration
    end
    if type(occurrence.retiredGeneration) == "number"
        and occurrence.retiredGeneration == math.floor(occurrence.retiredGeneration)
        and occurrence.retiredGeneration >= 0 and occurrence.retiredGeneration <= MAX_EXACT
        and occurrence.retiredGeneration > db.mailOccurrenceGeneration then
      db.mailOccurrenceGeneration = occurrence.retiredGeneration
    end
  end
end

-- Task 9 Step 4b: counts ledger entries genuinely NEW this session (both RecordSniperBuy and
-- ScanInbox funnel through Append below, so incrementing there covers both without either
-- caller needing to know about the counter). Deliberately module-local, not persisted --
-- "this session" means "since the addon loaded", the same window SavedVariables stays
-- unflushed for (WoW only writes them to disk on /reload or logout), which is exactly the gap
-- UI/SellFrame.lua's pending-sync hint exists to explain. A dedupe-skipped mailbox re-scan
-- (Append's repeat-key UPDATE branch) must NOT bump this -- it isn't a new fact reaching the
-- ledger, just the same invoice being re-read.
local sessionEventCount = 0

function GC.Ledger.SessionEventCount()
  return sessionEventCount
end

local function indexOf(key)
  local entries = db and db.ledger
  if not entries then return nil end
  for i = 1, #entries do
    if entries[i].key == key then return i end
  end
  return nil
end

local function compatibleKeyOwner(stored, entry)
  if type(stored) ~= "table" or type(entry) ~= "table" then return false end
  if stored.kind ~= nil and entry.kind ~= nil and stored.kind ~= entry.kind then return false end
  if stored.char ~= nil and entry.char ~= nil and stored.char ~= entry.char then return false end
  if stored.region ~= nil and entry.region ~= nil and stored.region ~= entry.region then return false end
  return true
end

-- Evicts one row to make space: the oldest ALREADY-UPLOADED row first, because
-- losing it costs nothing (the server has it), and only when there is no such
-- row does it fall back to the oldest row overall.
--
-- In a live client only the fallback ever runs: nothing marks rows uploaded
-- today. See MarkUploaded below for why, and for the one channel that could
-- change it.
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
  if not db or type(entry) ~= "table" or type(entry.key) ~= "string" or entry.key == "" then
    return entry, false, "invalid_entry"
  end
  local entries = db.ledger

  local existing = indexOf(entry.key)
  if existing then
    local stored = entries[existing]
    if not compatibleKeyOwner(stored, entry) then return stored, false, "incompatible_key" end
    -- A seller invoice can be observed as pending before its proceeds land. A
    -- later complete snapshot must be allowed to promote it, but a stale or
    -- reordered pending observation must never turn a paid immutable fact back
    -- into a pending one. The inbox reconciler below normally avoids that
    -- pairing; this guard keeps the ledger monotonic if an old SavedVariables
    -- occurrence or a direct caller ever presents the unsafe update anyway.
    if stored.kind == "sale" and stored.pending == false and entry.pending == true then
      return stored, false
    end
    for k, v in pairs(entry) do stored[k] = v end
    -- The row's contents changed, so any prior upload is now out of date.
    stored.uploaded = nil
    return stored, false
  end

  entries[#entries + 1] = entry
  sessionEventCount = sessionEventCount + 1
  while #entries > GC.Ledger.MAX_ENTRIES do
    evictOne(entries)
  end
  return entry, true
end

function GC.Ledger.GetEntries()
  return (db and db.ledger) or {}
end

--- Marks rows the server has already accepted, so evictOne can drop those
-- first. Returns how many keys matched a stored row.
--
-- NOTHING CALLS THIS IN A LIVE CLIENT. That is not a loose wire: the companion
-- is the thing that knows what was uploaded, and it cannot write
-- SavedVariables -- WoW rewrites that file wholesale on logout and would
-- discard any outside edit -- so it tracks uploads in its own uploaded.json
-- (companion/src-tauri/src/upload.rs) and the flag here stays unset.
--
-- Kept rather than deleted along with evictOne's first branch, because the
-- channel that would feed it already exists and is already used the other way:
-- the companion writes GoldCap_AppData/AppData.lua for prices (Core/Data.lua),
-- and publishing its uploaded keys through the same file would let Init call
-- this on load. It also only pays off in the one case worth protecting -- the
-- ledger reaching MAX_ENTRIES while the companion has been away long enough
-- for the oldest rows to be ones the server has never seen.
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

-- Expiry is bucketed to five minutes so two scans of the SAME mail, taken
-- minutes apart, land on the same key: daysLeft is a float counting down in
-- real time, so an unbucketed expiry drifts by seconds on every read.
local BUCKET_SECONDS = 300

local function expiryBucket(now, daysLeft)
  if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge
      or now < 0 or now > MAX_EXACT
      or type(daysLeft) ~= "number" or daysLeft ~= daysLeft
      or daysLeft == math.huge or daysLeft == -math.huge or daysLeft < 0 then return nil end
  local expiresAt = now + daysLeft * 86400
  if expiresAt ~= expiresAt or expiresAt == math.huge or expiresAt > MAX_EXACT then return nil end
  return math.floor(expiresAt / BUCKET_SECONDS)
end

local function valueFingerprint(fields)
  local copy = {}
  for key, value in pairs(fields) do copy[key] = value end
  copy.expiresAt = 0
  return GC.Ledger.EntryKey(copy)
end

local function scopedMailIdentity(fields, context, invoiceClass)
  return table.concat({ tostring(context and context.region or ""),
    tostring(context and context.char or ""), invoiceClass, valueFingerprint(fields) }, "\1")
end

local function exactNonNegative(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

local function occurrenceIsActive(occurrence)
  return type(occurrence) == "table" and occurrence.present ~= false
end

-- Two reads of the SAME mail can disagree about its expiry by far more than
-- the bucket width: on 2026-08-19 five sale mails read 30 minutes "younger"
-- between two scans 3 seconds apart (a placeholder daysLeft on a fresh
-- delivery), and the old ±1-bucket match re-keyed all five into duplicate
-- sales that doubled proceeds. 13 buckets (65 minutes) covers that jump plus
-- the hour a Sale Pending payout can shift the final mail's expiry. Distinct
-- identical mails never depended on this margin being tight: co-present
-- twins are split by the snapshot multiset (`used` in planSnapshot), and a
-- collected mail's occurrence is retired before its value-twin can arrive.
local BUCKET_MATCH_TOLERANCE = 13

local function occurrenceMatches(occurrence, identity, bucket, invoiceClass, context)
  return occurrenceIsActive(occurrence) and occurrence.identity == identity
    and occurrence.invoiceClass == invoiceClass
    and occurrence.char == context.char and occurrence.region == context.region
    and exactNonNegative(occurrence.expiryBucket)
    and math.abs(occurrence.expiryBucket - bucket) <= BUCKET_MATCH_TOLERANCE
    and type(occurrence.key) == "string" and occurrence.key ~= ""
end

local function occurrenceSequence(occurrence)
  return exactNonNegative(occurrence and occurrence.sequence) and occurrence.sequence or 0
end

local function validOccurrence(occurrence)
  return type(occurrence) == "table" and type(occurrence.key) == "string" and occurrence.key ~= ""
    and type(occurrence.identity) == "string" and occurrence.identity ~= ""
    and (occurrence.invoiceClass == "buy" or occurrence.invoiceClass == "sale")
    and type(occurrence.char) == "string" and occurrence.char ~= ""
    and type(occurrence.region) == "string" and occurrence.region ~= ""
    and exactNonNegative(occurrence.expiryBucket) and exactNonNegative(occurrence.sequence)
    and (occurrence.present == nil or type(occurrence.present) == "boolean")
    and (occurrence.lastPresentGeneration == nil or exactNonNegative(occurrence.lastPresentGeneration))
    and (occurrence.retiredGeneration == nil or exactNonNegative(occurrence.retiredGeneration))
end

local function validOccurrenceStore()
  if type(db.mailOccurrences) ~= "table" then return false end
  local keys = {}
  for _, occurrence in ipairs(db.mailOccurrences) do
    if not validOccurrence(occurrence) or keys[occurrence.key] then return false end
    keys[occurrence.key] = true
  end
  return true
end

local function occurrenceKeySet()
  local keys = {}
  for _, occurrence in ipairs(db.mailOccurrences) do
    if type(occurrence.key) == "string" and occurrence.key ~= "" then keys[occurrence.key] = true end
  end
  return keys
end

local function storedForOccurrence(occurrence)
  local storedIndex = occurrence and indexOf(occurrence.key)
  return storedIndex and db.ledger[storedIndex] or nil
end

local function occurrenceCandidates(mail, context, used)
  local candidates = {}
  local probe = { kind = mail.invoiceClass, char = context.char, region = context.region }
  for _, occurrence in ipairs(db.mailOccurrences) do
    if not used[occurrence.key] and occurrenceMatches(occurrence, mail.identity, mail.bucket,
        mail.invoiceClass, context) then
      local stored = storedForOccurrence(occurrence)
      if not stored or compatibleKeyOwner(stored, probe) then
        candidates[#candidates + 1] = { occurrence = occurrence, stored = stored }
      end
    end
  end
  table.sort(candidates, function(left, right)
    return occurrenceSequence(left.occurrence) < occurrenceSequence(right.occurrence)
  end)
  return candidates
end

-- Pending and paid seller invoices have the same stable value fingerprint, but
-- not the same accounting state.  Select from the complete snapshot with the
-- state rules here rather than the transient scan order: paid prefers paid,
-- then promotes one pending; pending may reuse only a pending/unknown slot and
-- can never regress a paid one.
local function selectOccurrence(mail, context, used)
  local candidates = occurrenceCandidates(mail, context, used)
  if mail.invoiceClass ~= "sale" then return candidates[1] and candidates[1].occurrence or nil end

  local paid, pending, unknown
  for _, candidate in ipairs(candidates) do
    if candidate.stored and candidate.stored.pending == false then
      paid = paid or candidate.occurrence
    elseif candidate.stored and candidate.stored.pending == true then
      pending = pending or candidate.occurrence
    else
      unknown = unknown or candidate.occurrence
    end
  end
  if mail.entry.pending then return pending or unknown end
  return paid or pending or unknown
end

local function legacyOccurrenceKey(mail, context, used, occurrenceKeys)
  local legacyCandidates = {}
  for _, adjacent in ipairs({ mail.bucket, mail.bucket - 1, mail.bucket + 1 }) do
    local fields = {}
    for key, value in pairs(mail.fields) do fields[key] = value end
    fields.expiresAt = adjacent
    legacyCandidates[GC.Ledger.EntryKey(fields)] = true
  end
  for _, stored in ipairs(db.ledger) do
    if legacyCandidates[stored.key] and not used[stored.key] and not occurrenceKeys[stored.key]
        and compatibleKeyOwner(stored, { kind = mail.invoiceClass,
          char = context.char, region = context.region }) then
      return stored.key
    end
  end
  return nil
end

local function scanOrder(left, right)
  local function rank(mail)
    if mail.invoiceClass ~= "sale" then return 3 end
    return mail.entry.pending and 2 or 1
  end
  local leftRank, rightRank = rank(left), rank(right)
  if leftRank ~= rightRank then return leftRank < rightRank end
  if left.identity ~= right.identity then return left.identity < right.identity end
  return left.index < right.index
end

local function validMailGeneration(value)
  return exactNonNegative(value) and value < MAX_EXACT
end

-- Plans an entire inbox snapshot before touching SavedVariables.  This gives
-- a complete scan one deterministic multiset reconciliation and lets a bad
-- mailbox read fail closed without retiring or shuffling any prior occurrence.
local function planSnapshot(mails, context)
  if not validOccurrenceStore() then return nil end
  local generation = db.mailOccurrenceGeneration
  if not validMailGeneration(generation) then return nil end
  local sequence = db.mailOccurrenceSeq
  if not exactNonNegative(sequence) then return nil end

  local used, planned, occurrenceKeys = {}, {}, occurrenceKeySet()
  local ordered = {}
  for _, mail in ipairs(mails) do ordered[#ordered + 1] = mail end
  table.sort(ordered, scanOrder)

  for _, mail in ipairs(ordered) do
    local occurrence = selectOccurrence(mail, context, used)
    if occurrence then
      used[occurrence.key] = true
      mail.entry.key = occurrence.key
    else
      if sequence >= MAX_EXACT then return nil end
      sequence = sequence + 1
      local key = legacyOccurrenceKey(mail, context, used, occurrenceKeys)
      if not key then key = table.concat({ "mail", mail.identity, tostring(mail.bucket), tostring(sequence) }, "\1") end
      if used[key] or occurrenceKeys[key] then return nil end
      used[key] = true
      occurrenceKeys[key] = true
      mail.entry.key = key
      planned[#planned + 1] = { key = key, identity = mail.identity, expiryBucket = mail.bucket,
        invoiceClass = mail.invoiceClass, char = context.char, region = context.region,
        sequence = sequence, present = true, lastPresentGeneration = generation + 1 }
    end
  end

  for _, mail in ipairs(mails) do
    if type(mail.entry.key) ~= "string" or mail.entry.key == "" then return nil end
    local existing = indexOf(mail.entry.key)
    if existing and not compatibleKeyOwner(db.ledger[existing], mail.entry) then return nil end
  end
  return { mails = mails, planned = planned, used = used, sequence = sequence,
    generation = generation + 1 }
end

-- `complete` gates the ABSENCE inference and the presence/generation bookkeeping, exactly as
-- before -- but the NEW occurrences a plan allocated, and the sequence numbers they consumed,
-- persist on EVERY scan. An entry was just Appended under each planned occurrence's key, and
-- an occurrence store that forgets that key re-invents a fresh one on the next inbox tick and
-- Appends the SAME mail again. That is precisely how one purchase mail became four ledger
-- buys and three phantom cost batches in one mailbox visit (2026-08-17): WoW streams inbox
-- rows, so the first scans of a visit are almost always incomplete, and every incomplete
-- scan re-keyed every not-yet-committed mail. Everything else -- retiring absentees, the
-- present flags, the generation counter -- still requires a complete snapshot: a mail's
-- absence cannot be inferred from a partial view.
local function commitOccurrencePlan(plan, context, complete)
  db.mailOccurrenceSeq = plan.sequence
  for _, occurrence in ipairs(plan.planned) do db.mailOccurrences[#db.mailOccurrences + 1] = occurrence end
  if not complete then return end
  db.mailOccurrenceGeneration = plan.generation
  for _, occurrence in ipairs(db.mailOccurrences) do
    if occurrence.char == context.char and occurrence.region == context.region then
      if plan.used[occurrence.key] then
        occurrence.present, occurrence.lastPresentGeneration, occurrence.retiredGeneration = true,
          plan.generation, nil
      elseif occurrenceIsActive(occurrence) then
        occurrence.present, occurrence.retiredGeneration = false, plan.generation
      end
    end
  end
end

local function readInboxMail(api, index, context, now)
  local headerOk, _, _, sender, _, _, _, daysLeft, _, _, _, _, canReply = pcall(api.GetInboxHeaderInfo, index)
  if not headerOk then return nil, "incomplete" end
  local invoiceOk, invoiceType, itemName, _, bid, buyout, deposit, consignment,
    moneyDelay, _, _, itemCount = pcall(api.GetInboxInvoiceInfo, index)
  if not invoiceOk then return nil, "incomplete" end
  local isSale = invoiceType == "seller" or invoiceType == "seller_temp_invoice"
  local isBuy = invoiceType == "buyer"
  if not isSale and not isBuy then
    -- canReply is the locale-independent ordinary-mail signal. Anything else
    -- is unreadable rather than positively non-AH and cannot retire evidence.
    return nil, canReply == true and "ignored" or "incomplete"
  end

  local fields = { sender = sender, itemName = itemName, count = itemCount or 1,
    bid = bid or 0, buyout = buyout or 0, deposit = deposit or 0,
    consignment = consignment or 0 }
  if type(itemName) ~= "string" or itemName == "" or not exactNonNegative(fields.count)
      or fields.count == 0 or not exactNonNegative(fields.bid) or not exactNonNegative(fields.buyout)
      or not exactNonNegative(fields.deposit) or not exactNonNegative(fields.consignment)
      or not exactNonNegative(moneyDelay or 0) then
    return nil, "incomplete"
  end
  local bucket = expiryBucket(now, daysLeft)
  if not bucket then return nil, "incomplete" end

  -- A buy mail has the item attached, so its id is readable. A sale mail has
  -- money attached and nothing else. Attachment lookup remains best-effort:
  -- losing a cache lookup must not turn authoritative invoice evidence into an
  -- invented item identity or abort a trustworthy invoice snapshot.
  local itemID
  if isBuy then
    local gotItem, _, boughtID = pcall(api.GetInboxItem, index, 1)
    if gotItem and type(boughtID) == "number" then itemID = boughtID end
  end
  local pending = invoiceType == "seller_temp_invoice"
  local invoiceClass = isSale and "sale" or "buy"
  return {
    fields = fields, bucket = bucket, invoiceClass = invoiceClass,
    identity = scopedMailIdentity(fields, context, invoiceClass),
    entry = { kind = invoiceClass, source = "mail", itemName = itemName, itemID = itemID,
      qty = fields.count, total = pending and (moneyDelay or 0) or (bid or 0),
      cut = isSale and (consignment or 0) or 0, deposit = deposit or 0, pending = pending,
      at = now, char = context.char, region = context.region },
  }
end

-- Walks the inbox and records every auction invoice it can read.  Occurrence
-- reconciliation deliberately waits until every row in the snapshot is known
-- good; a partial read is informative only to the mailbox UI and cannot erase
-- durable presence state.
function GC.Ledger.ScanInbox(api, context, now)
  if not db or type(context) ~= "table"
      or type(context.char) ~= "string" or context.char == ""
      or type(context.region) ~= "string" or context.region == "" then return 0 end
  now = now or time()
  local ok, count = pcall(api.GetInboxNumItems)
  if not ok or not exactNonNegative(count) then return 0 end

  -- An unreadable row no longer discards the whole pass. WoW streams mail data, so immediately
  -- after MAIL_SHOW some rows have neither header nor invoice loaded yet; on a busy mailbox at
  -- least one is unreadable on nearly every scan, and aborting meant a perfectly readable sale
  -- sitting beside it was never recorded. That is how a ledger ends up holding one mail-sourced
  -- entry from days ago while every sale since went missing.
  --
  -- The all-or-nothing rule was protecting one specific thing -- occurrence reconciliation,
  -- which infers a mail is GONE from its absence and cannot do that from a partial view. So
  -- that step, and only that step, still requires a complete snapshot. Recording an invoice we
  -- positively read is safe either way: it is evidence of presence, not of absence.
  local mails, complete = {}, true
  for index = 1, count do
    local mail, state = readInboxMail(api, index, context, now)
    if state == "incomplete" then complete = false end
    if mail then mail.index = index; mails[#mails + 1] = mail end
  end
  local plan = planSnapshot(mails, context)
  if not plan then return 0 end
  commitOccurrencePlan(plan, context, complete)

  local created = 0
  for _, mail in ipairs(plan.mails) do
    local stored, isNew, appendError = GC.Ledger.Append(mail.entry)
    if not appendError and stored then
      if stored.kind == "buy" and GC.Acquisitions and GC.Acquisitions.ReconcileBuy then
        GC.Acquisitions.ReconcileBuy(stored)
      end
      if stored.kind == "sale" and GC.Acquisitions and GC.Acquisitions.ReconcileSale then
        GC.Acquisitions.ReconcileSale(stored)
      end
      if isNew then
        created = created + 1
        -- Only new sale evidence contributes to personal sale-rate history;
        -- pending -> paid is the same immutable invoice, not a second sale.
        if mail.entry.kind == "sale" and GC.Data and GC.Data.RecordSaleEvent then
          GC.Data.RecordSaleEvent(mail.entry.itemName)
        end
      end
    end
  end

  -- Sold tab: a mailbox scan is exactly when new sale rows appear, so the
  -- tab's local section refreshes live if it is currently up. Guarded --
  -- Core files must not assume UI files loaded (specs load Ledger alone).
  if GC.Sold and GC.Sold.RefreshIfShown then GC.Sold.RefreshIfShown() end

  return created
end

local sniperSeq = 0

local function isExactInteger(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
      and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

local function isPositiveInteger(value)
  return isExactInteger(value) and value > 0
end

local function isNonNegativeInteger(value)
  return isExactInteger(value)
end

local function isReasonsArray(reasons)
  if type(reasons) ~= "table" then return false end
  for i = 1, #reasons do
    if type(reasons[i]) ~= "string" then return false end
  end
  return true
end

local function copyReasons(reasons)
  local copy = {}
  for i = 1, #reasons do copy[i] = reasons[i] end
  return copy
end

--- Records a purchase made through the Sniper. Unlike a mail invoice this has
-- no natural dedupe key -- two identical buys a second apart are two real buys
-- -- so the key carries a monotonic counter instead of the money fields.
-- `deal` is the discovery context; `purchase` is the immutable successful-purchase fact. Its
-- exact total is the ledger cost basis, and decision fields are saved under stable camelCase
-- names for later companion/API persistence.
function GC.Ledger.RecordSniperBuy(deal, purchase, context, now)
  if not db then return nil end
  if type(deal) ~= "table" or type(purchase) ~= "table"
      or not isPositiveInteger(deal.itemID) or purchase.itemID ~= deal.itemID
      or not isPositiveInteger(purchase.quantity) or not isPositiveInteger(purchase.total)
      or not isNonNegativeInteger(purchase.unitDisplay) or purchase.unitDisplay ~= math.floor(purchase.total / purchase.quantity)
      or not isPositiveInteger(purchase.decisionVersion)
      or purchase.decisionStatus ~= "SAFE"
      or not isReasonsArray(purchase.decisionReasons)
      or not isPositiveInteger(purchase.stressUnit)
      or not isNonNegativeInteger(purchase.expectedProfit)
      or not isPositiveInteger(purchase.recommendedQuantity)
      or not isNonNegativeInteger(purchase.sourceAt) then
    return nil
  end
  now = now or time()
  sniperSeq = sniperSeq + 1

  -- The mail twin normally supplies the name, but only if the player opens
  -- the mailbox with the addon running. Best-effort here: the client has the
  -- item cached (the Sniper just displayed it), so ask it. nil is fine --
  -- the server resolves names by id as a fallback.
  local itemName = deal.itemName
  if not itemName and C_Item and C_Item.GetItemNameByID then
    local ok, name = pcall(C_Item.GetItemNameByID, deal.itemID)
    if ok and type(name) == "string" then itemName = name end
  end

  return (GC.Ledger.Append({
    key = table.concat({ "snipe", tostring(deal.itemID), tostring(now), tostring(sniperSeq) }, "\1"),
    kind = "buy",
    source = "goldcap_sniper",
    itemID = deal.itemID,
    itemName = itemName,
    qty = purchase.quantity,
    total = purchase.total,
    cut = 0,
    deposit = 0,
    pending = false,
    mv = deal.mv,
    discount = deal.discount,
    decisionVersion = purchase.decisionVersion,
    decisionStatus = purchase.decisionStatus,
    decisionReasons = copyReasons(purchase.decisionReasons),
    stressUnit = purchase.stressUnit,
    expectedProfit = purchase.expectedProfit,
    recommendedQuantity = purchase.recommendedQuantity,
    sourceAt = purchase.sourceAt,
    at = now,
    char = context and context.char or nil,
    region = context and context.region or nil,
  }))
end

--- "Name-Realm" plus region, for stamping entries. Every lookup is guarded
-- because specs (and the TOC load-order spec) run with no player present.
function GC.Ledger.Context()
  local name = UnitName and UnitName("player") or nil
  local realm = GetRealmName and GetRealmName() or nil
  local status = GC.Data and GC.Data.GetStatus and GC.Data.GetStatus() or nil
  return {
    char = (name and realm) and (name .. "-" .. realm) or name,
    region = status and status.region or nil,
  }
end

-- ~7 months of five-minute samples at typical play rates. The curve exists to
-- answer "how much of my gold growth does the ledger actually explain", which
-- needs shape, not resolution.
GC.Ledger.MAX_GOLD_POINTS = 2000
local GOLD_MIN_INTERVAL = 300

--- Records a per-character gold reading. Debounced because PLAYER_MONEY fires
-- on every loot, vendor sale and repair. `force` (used on PLAYER_LOGOUT)
-- bypasses the interval but NOT the unchanged-amount check: a flat line needs
-- one point, not one per session.
function GC.Ledger.RecordGold(copper, context, now, force)
  if not db or type(copper) ~= "number" then return false end
  now = now or time()
  local points = db.gold
  local char = context and context.char or nil

  local last
  for i = #points, 1, -1 do
    if points[i].char == char then last = points[i] break end
  end

  if last then
    -- GetMoney() answers 0 when the client hasn't loaded the player's money
    -- yet, or has already torn it down -- which is precisely what the forced
    -- PLAYER_LOGOUT sample tends to catch. Observed in real SavedVariables: a
    -- 259k-gold character logging a single 0 between two identical real
    -- readings. A curve that dives to zero and back is always that artifact,
    -- never an event, and one such point flips the dashboard's coverage figure
    -- from "explains 60%" to a large negative delta. Refused even when forced,
    -- because forced is when it happens.
    if copper == 0 and last.copper > 0 then return false end
    if last.copper == copper then return false end
    if not force and (now - (last.at or 0)) < GOLD_MIN_INTERVAL then return false end
  end

  points[#points + 1] = {
    at = now,
    copper = copper,
    char = char,
    region = context and context.region or nil,
  }
  while #points > GC.Ledger.MAX_GOLD_POINTS do
    table.remove(points, 1)
  end
  return true
end

function GC.Ledger.GetGold()
  return (db and db.gold) or {}
end
