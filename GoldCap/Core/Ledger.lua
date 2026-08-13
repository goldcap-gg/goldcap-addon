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
      --
      -- GetInboxItem takes (index, itemIndex) and BOTH are required; attachment
      -- slots are 1-based and an auction buy puts its item in the first one.
      -- The call gets its own pcall rather than riding the caller's, because
      -- the id is a nice-to-have: losing it should cost the id, not the whole
      -- purchase. Sales never reach this branch, which is exactly why a
      -- failure here looked like "buys are never recorded, sales are fine".
      local itemID = nil
      if isBuy then
        local gotItem, _, boughtID = pcall(api.GetInboxItem, i, 1)
        if gotItem and type(boughtID) == "number" then itemID = boughtID end
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
      local stored, isNew = GC.Ledger.Append(entry)
      if stored.kind == "buy" and GC.Acquisitions and GC.Acquisitions.ReconcileBuy then
        GC.Acquisitions.ReconcileBuy(stored)
      end
      -- Append updates an existing seller invoice in place when "Sale Pending" matures. Run
      -- reconciliation for every stored sale row so the exact paid total can be consumed once;
      -- ReconcileSale itself refuses pending and already-consumed evidence without mutation.
      if stored.kind == "sale" and GC.Acquisitions and GC.Acquisitions.ReconcileSale then
        GC.Acquisitions.ReconcileSale(stored)
      end
      if isNew then
        created = created + 1
        -- F2 (personal sale rate): only on isNew, deliberately -- Append's repeat-key branch
        -- (a Sale Pending invoice maturing into a paid one on a LATER scan of the SAME mail,
        -- see Append's own comment above) UPDATES the stored row rather than appending a
        -- second one; crediting a sale event on that update too would double-count one real
        -- sale as two against GC.Data's postStats denominator. Guarded the same defensive way
        -- GC.Ledger.Context above guards its own GC.Data reads -- this module has no
        -- compile-time load-order guarantee that Core/Data.lua has already loaded.
        if entry.kind == "sale" and GC.Data and GC.Data.RecordSaleEvent then
          GC.Data.RecordSaleEvent(entry.itemName)
        end
      end
    end
  end

  return created
end

local sniperSeq = 0
local MAX_EXACT = 9007199254740991

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
