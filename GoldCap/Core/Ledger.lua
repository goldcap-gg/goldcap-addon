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

-- Expiry is bucketed to five minutes so two scans of the SAME mail, taken
-- minutes apart, land on the same key: daysLeft is a float counting down in
-- real time, so an unbucketed expiry drifts by seconds on every read.
local BUCKET_SECONDS = 300

local function expiryBucket(now, daysLeft)
  return math.floor((now + (daysLeft or 0) * 86400) / BUCKET_SECONDS)
end

-- Bucketing has one seam: a mail whose expiry sits near a boundary can land in
-- adjacent buckets on consecutive scans. Rather than widen the bucket (which
-- would start merging genuinely different sales), try the neighbours too and
-- reuse an existing row's key when one matches.
local function keyForMail(fields, bucket)
  local candidates = {}
  for _, b in ipairs({ bucket, bucket - 1, bucket + 1 }) do
    fields.expiresAt = b
    candidates[#candidates + 1] = GC.Ledger.EntryKey(fields)
  end
  local entries = GC.Ledger.GetEntries()
  for i = 1, #entries do
    for _, candidate in ipairs(candidates) do
      if entries[i].key == candidate then return candidate end
    end
  end
  return candidates[1]
end

--- Walks the inbox and records every auction invoice it can read.
-- Called on MAIL_SHOW and MAIL_INBOX_UPDATE, i.e. BEFORE the player collects
-- anything -- a collected mail is gone from the client entirely, so a scan
-- that waited for collection would record nothing at all.
-- `api` is injected so this is testable without a running game client.
-- Returns the number of entries newly created; updates are not counted.
function GC.Ledger.ScanInbox(api, context, now)
  if not db then return 0 end
  now = now or time()
  local created = 0

  local ok, count = pcall(api.GetInboxNumItems)
  if not ok or type(count) ~= "number" then return 0 end

  for i = 1, count do
    -- Per-mail pcall: one malformed invoice must not abort the rest of the
    -- inbox, and must never surface as a Lua error over the mailbox UI.
    local readOk, entry = pcall(function()
      local _, _, sender, _, _, _, daysLeft = api.GetInboxHeaderInfo(i)
      local invoiceType, itemName, _, bid, buyout, deposit, consignment,
        moneyDelay, _, _, itemCount = api.GetInboxInvoiceInfo(i)

      if not invoiceType or not itemName then return nil end
      local isSale = invoiceType == "seller" or invoiceType == "seller_temp_invoice"
      local isBuy = invoiceType == "buyer"
      if not isSale and not isBuy then return nil end

      local fields = {
        sender = sender,
        itemName = itemName,
        count = itemCount or 1,
        bid = bid or 0,
        buyout = buyout or 0,
        deposit = deposit or 0,
        consignment = consignment or 0,
      }
      local key = keyForMail(fields, expiryBucket(now, daysLeft))

      -- A buy mail has the item attached, so its id is readable. A sale mail
      -- has money attached and nothing else -- itemName is all there is.
      local itemID = nil
      if isBuy then
        local _, boughtID = api.GetInboxItem(i)
        if type(boughtID) == "number" then itemID = boughtID end
      end

      local pending = invoiceType == "seller_temp_invoice"
      return {
        key = key,
        kind = isSale and "sale" or "buy",
        source = "mail",
        itemName = itemName,
        itemID = itemID,
        qty = fields.count,
        -- While pending, the proceeds live in moneyDelay rather than in the
        -- mail's attached money; once paid, bid carries them.
        total = pending and (moneyDelay or 0) or (bid or 0),
        cut = isSale and (consignment or 0) or 0,
        deposit = deposit or 0,
        pending = pending,
        at = now,
        char = context and context.char or nil,
        region = context and context.region or nil,
      }
    end)

    if readOk and entry then
      local _, isNew = GC.Ledger.Append(entry)
      if isNew then created = created + 1 end
    end
  end

  return created
end

local sniperSeq = 0

--- Records a purchase made through the Sniper. Unlike a mail invoice this has
-- no natural dedupe key -- two identical buys a second apart are two real buys
-- -- so the key carries a monotonic counter instead of the money fields.
-- `deal` is DealMath.Evaluate's shape. `mv` is snapshotted because attribution
-- later needs the market value the deal was JUDGED against, not today's.
function GC.Ledger.RecordSniperBuy(deal, context, now)
  if not db then return nil end
  now = now or time()
  sniperSeq = sniperSeq + 1

  return (GC.Ledger.Append({
    key = table.concat({ "snipe", tostring(deal.itemID), tostring(now), tostring(sniperSeq) }, "\1"),
    kind = "buy",
    source = "goldcap_sniper",
    itemID = deal.itemID,
    qty = deal.qty,
    total = (deal.unitPrice or 0) * (deal.qty or 0),
    cut = 0,
    deposit = 0,
    pending = false,
    mv = deal.mv,
    discount = deal.discount,
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
