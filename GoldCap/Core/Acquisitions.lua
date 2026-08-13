local _, GC = ...

GC.Acquisitions = {}

local db
local MAX_EXACT = 9007199254740991
local SOURCES = { goldcap = true, auction_house = true, manual = true }

local function isExactInteger(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value == math.floor(value)
    and value >= 0 and value <= MAX_EXACT
end

local function isPositiveInteger(value)
  return isExactInteger(value) and value > 0
end

local function isStringOrNil(value)
  return value == nil or type(value) == "string"
end

local function isNonEmptyString(value)
  return type(value) == "string" and value ~= ""
end

local function isSignedExactInteger(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value == math.floor(value)
    and value >= -MAX_EXACT and value <= MAX_EXACT
end

local function safeAdd(left, right)
  if not isExactInteger(left) or not isExactInteger(right) or left > MAX_EXACT - right then
    return nil
  end
  return left + right
end

-- Computes floor(left * right / denominator) without ever constructing the
-- product. SavedVariables numbers are exact only through MAX_EXACT, so a
-- direct multiply can wrap on Lua integer builds or round on double builds.
local function mulDivFloor(left, right, denominator)
  if not isExactInteger(left) or not isExactInteger(right)
      or not isPositiveInteger(denominator) then return nil end

  local whole = math.floor(left / denominator)
  local remainder = left - whole * denominator
  local bits = {}
  while right > 0 do
    bits[#bits + 1] = right % 2
    right = math.floor(right / 2)
  end

  local quotient, current = 0, 0
  local function addModulo(value)
    local untilWrap = denominator - value
    if current >= untilWrap then
      current = current - untilWrap
      return 1
    end
    current = current + value
    return 0
  end

  for i = #bits, 1, -1 do
    quotient = safeAdd(quotient, quotient)
    if not quotient then return nil end
    local carry = addModulo(current)
    if bits[i] == 1 then
      quotient = safeAdd(quotient, whole)
      if not quotient then return nil end
      carry = carry + addModulo(remainder)
    end
    quotient = safeAdd(quotient, carry)
    if not quotient then return nil end
  end
  return quotient
end

local function sequenceFor(id)
  local value = type(id) == "string" and id:match("^acq:(%d+)$") or nil
  return value and tonumber(value) or 0
end

local function lessByFIFO(left, right)
  local leftAt = left.acquiredAt or left.completedAt or 0
  local rightAt = right.acquiredAt or right.completedAt or 0
  if leftAt ~= rightAt then return leftAt < rightAt end
  return sequenceFor(left.id) < sequenceFor(right.id)
end

local function sortedBatches(batches)
  local copy = {}
  for _, batch in ipairs(batches or {}) do copy[#copy + 1] = batch end
  table.sort(copy, lessByFIFO)
  return copy
end

local function hasEvidence(key)
  if not key or not db then return false end
  if db.acquisitionConsumptionEvidence and db.acquisitionConsumptionEvidence[key] then return true end
  for _, batch in ipairs(db.acquisitions) do
    if batch.evidenceKeys and batch.evidenceKeys[key] then return true end
    if batch.mailEvidenceKey == key then return true end
  end
  for _, pending in ipairs(db.acquisitionPending) do
    if pending.evidenceKeys and pending.evidenceKeys[key] then return true end
    if pending.mailEvidenceKey == key then return true end
  end
  return false
end

local function activeWithEvidence(key)
  if not key or not db then return nil end
  for _, batch in ipairs(db.acquisitions) do
    if (batch.evidenceKeys and batch.evidenceKeys[key]) or batch.mailEvidenceKey == key then
      return batch
    end
  end
  return nil
end

local function pendingWithEvidence(key)
  if not key or not db then return nil end
  for index, pending in ipairs(db.acquisitionPending) do
    if (pending.evidenceKeys and pending.evidenceKeys[key]) or pending.mailEvidenceKey == key then
      return pending, index
    end
  end
  return nil
end

local function pendingMatchesExactRecord(pending, args)
  return pending.itemID == args.itemID and (pending.quantity == nil or pending.quantity == args.quantity)
    and (not pending.positionKey or not args.positionKey or pending.positionKey == args.positionKey)
    and (not pending.character or not args.character or pending.character == args.character)
    and (not pending.region or not args.region or pending.region == args.region)
end

local function compatible(batch, entry)
  return batch.itemID == entry.itemID
    and batch.originalQty == entry.qty
    and batch.originalTotal == entry.total
    and (not entry.char or not batch.character or entry.char == batch.character)
    and (not entry.region or not batch.region or entry.region == batch.region)
end

local function compatiblePending(pending, entry)
  return pending.itemID == entry.itemID and (pending.quantity == nil or pending.quantity == entry.qty)
    and (not entry.char or not pending.character or entry.char == pending.character)
    and (not entry.region or not pending.region or entry.region == pending.region)
end

local function compatibleByName(candidate, entry, quantity, total)
  return candidate.itemName == entry.itemName and quantity == entry.qty and total == entry.total
    and (not entry.char or not candidate.character or entry.char == candidate.character)
    and (not entry.region or not candidate.region or entry.region == candidate.region)
end

local function oldestCompatible(candidates, predicate)
  local oldest
  for _, candidate in ipairs(candidates or {}) do
    if predicate(candidate) and (not oldest or lessByFIFO(candidate, oldest)) then oldest = candidate end
  end
  return oldest
end

local function validBuyEntry(entry)
  return type(entry) == "table" and entry.kind == "buy" and type(entry.key) == "string"
    and entry.key ~= "" and isPositiveInteger(entry.qty) and isPositiveInteger(entry.total)
    and isExactInteger(entry.at) and isStringOrNil(entry.char) and isStringOrNil(entry.region)
    and isStringOrNil(entry.itemName)
end

local function attachMailEvidence(batch, entry)
  batch.evidenceKeys = type(batch.evidenceKeys) == "table" and batch.evidenceKeys or {}
  batch.evidenceKeys[entry.key] = true
  batch.mailEvidenceKey = entry.key
  batch.character = batch.character or entry.char
  batch.region = batch.region or entry.region
  return batch
end

local function takeCost(batch, qty)
  local beforeQty = batch.remainingQty
  local cost = (qty == beforeQty)
    and batch.remainingTotal
    or mulDivFloor(batch.remainingTotal, qty, beforeQty)
  if not isExactInteger(cost) then return nil end
  batch.remainingQty = beforeQty - qty
  batch.remainingTotal = batch.remainingTotal - cost
  return cost
end

local function copyBatchState(batch)
  return { remainingQty = batch.remainingQty, remainingTotal = batch.remainingTotal }
end

local function allocationFor(batches, quantity)
  local result = {
    allocations = {}, knownQty = 0, knownCost = 0, requestedQty = quantity,
    coverage = "MISSING",
  }
  if not isPositiveInteger(quantity) then return nil end

  for _, batch in ipairs(sortedBatches(batches)) do
    if result.knownQty >= quantity then break end
    if isPositiveInteger(batch.remainingQty) and isExactInteger(batch.remainingTotal) then
      local qty = math.min(quantity - result.knownQty, batch.remainingQty)
      local state = copyBatchState(batch)
      local cost = takeCost(state, qty)
      if cost == nil then return nil end
      local knownQty = safeAdd(result.knownQty, qty)
      local knownCost = safeAdd(result.knownCost, cost)
      if not knownQty or not knownCost then return nil end
      result.allocations[#result.allocations + 1] = {
        batchID = batch.id,
        quantity = qty,
        cost = cost,
        source = batch.source,
      }
      result.knownQty = knownQty
      result.knownCost = knownCost
    end
  end

  if result.knownQty == quantity then
    result.coverage = "COMPLETE"
  elseif result.knownQty > 0 then
    result.coverage = "PARTIAL"
  end
  return result
end

local function validContext(context)
  return type(context) == "table" and type(context.char) == "string" and context.char ~= ""
    and type(context.region) == "string" and context.region ~= ""
end

function GC.Acquisitions.PositionKey(itemID, itemKey, isCommodity)
  if isCommodity then return ("commodity:%d"):format(itemID) end
  if not itemKey then return nil end
  return table.concat({ "item", itemID, itemKey.itemLevel or 0,
    itemKey.itemSuffix or 0, itemKey.battlePetSpeciesID or 0 }, ":")
end

function GC.Acquisitions.ScopeKey(positionKey, context)
  if not positionKey or not context or not context.char or not context.region then return nil end
  return table.concat({ context.region, context.char, positionKey }, "\1")
end

function GC.Acquisitions.Init(database)
  db = database
  if type(db) ~= "table" then return end
  db.acquisitions = type(db.acquisitions) == "table" and db.acquisitions or {}
  db.acquisitionPending = type(db.acquisitionPending) == "table" and db.acquisitionPending or {}
  db.acquisitionRealized = type(db.acquisitionRealized) == "table" and db.acquisitionRealized or {}
  db.acquisitionActivity = type(db.acquisitionActivity) == "table" and db.acquisitionActivity or {}
  db.acquisitionConsumptionEvidence = type(db.acquisitionConsumptionEvidence) == "table"
    and db.acquisitionConsumptionEvidence or {}
  db.acquisitionSeq = isExactInteger(db.acquisitionSeq) and db.acquisitionSeq or 0
  db.acquisitionPendingSeq = isExactInteger(db.acquisitionPendingSeq)
    and db.acquisitionPendingSeq or 0
  db.acquisitionVersion = isExactInteger(db.acquisitionVersion) and db.acquisitionVersion or 0
  for _, batch in ipairs(db.acquisitions) do
    db.acquisitionSeq = math.max(db.acquisitionSeq, sequenceFor(batch.id))
    batch.evidenceKeys = type(batch.evidenceKeys) == "table" and batch.evidenceKeys or {}
    batch.consumedEvidenceKeys = type(batch.consumedEvidenceKeys) == "table"
      and batch.consumedEvidenceKeys or {}
  end
end

function GC.Acquisitions.Record(args)
  if not db or type(args) ~= "table" or not SOURCES[args.source]
      or not isPositiveInteger(args.itemID) or not isPositiveInteger(args.quantity)
      or not isPositiveInteger(args.total) or not isExactInteger(args.acquiredAt)
      or not isStringOrNil(args.positionKey) or not isStringOrNil(args.itemName)
      or not isStringOrNil(args.evidenceKey) or not isStringOrNil(args.character)
      or not isStringOrNil(args.region)
      or (args.targetUnit ~= nil and not isExactInteger(args.targetUnit)) then
    return nil, false
  end
  if args.evidenceKey == "" then return nil, false end

  local pending, pendingIndex
  if args.evidenceKey then
    local existing = activeWithEvidence(args.evidenceKey)
    if existing then return existing, false end
    pending, pendingIndex = pendingWithEvidence(args.evidenceKey)
    if pending and not pendingMatchesExactRecord(pending, args) then return nil, false end
  end

  local sequence = safeAdd(db.acquisitionSeq, 1)
  if not sequence then return nil, false end
  db.acquisitionSeq = sequence
  local batch = {
    id = "acq:" .. sequence,
    source = args.source,
    itemID = args.itemID,
    positionKey = args.positionKey,
    itemName = args.itemName,
    originalQty = args.quantity,
    originalTotal = args.total,
    remainingQty = args.quantity,
    remainingTotal = args.total,
    acquiredAt = args.acquiredAt,
    targetUnit = args.targetUnit,
    decisionEvidence = args.decisionEvidence,
    character = args.character,
    region = args.region,
    evidenceKeys = {},
    mailEvidenceKey = nil,
    consumedEvidenceKeys = {},
  }
  if pending then
    batch.positionKey = batch.positionKey or pending.positionKey
    batch.itemName = batch.itemName or pending.itemName
    batch.character = batch.character or pending.character
    batch.region = batch.region or pending.region
    batch.promotedPendingID = pending.id
    table.remove(db.acquisitionPending, pendingIndex)
  end
  if args.evidenceKey then batch.evidenceKeys[args.evidenceKey] = true end
  db.acquisitions[#db.acquisitions + 1] = batch
  return batch, true
end

function GC.Acquisitions.RecordPending(args)
  if not db or type(args) ~= "table" or not isPositiveInteger(args.itemID)
      or (args.quantity ~= nil and not isPositiveInteger(args.quantity)) or not isExactInteger(args.completedAt)
      or not isStringOrNil(args.positionKey) or not isStringOrNil(args.itemName)
      or not isStringOrNil(args.character) or not isStringOrNil(args.region)
      or type(args.reason) ~= "string" or args.reason == ""
      or not isStringOrNil(args.evidenceKey) or args.evidenceKey == "" then
    return nil, false
  end
  if args.evidenceKey then
    if activeWithEvidence(args.evidenceKey) then return nil, false end
    local pending = pendingWithEvidence(args.evidenceKey)
    if pending then return pending, false end
  end
  local sequence = safeAdd(db.acquisitionPendingSeq, 1)
  if not sequence then return nil, false end
  db.acquisitionPendingSeq = sequence
  local pending = {
    id = "pending:" .. sequence,
    itemID = args.itemID,
    positionKey = args.positionKey,
    itemName = args.itemName,
    quantity = args.quantity,
    completedAt = args.completedAt,
    character = args.character,
    region = args.region,
    reason = args.reason,
    evidenceKeys = {},
  }
  if args.evidenceKey then pending.evidenceKeys[args.evidenceKey] = true end
  db.acquisitionPending[#db.acquisitionPending + 1] = pending
  return pending, true
end

function GC.Acquisitions.ResolvePending(id, evidenceKey)
  if not db or type(id) ~= "string" or type(evidenceKey) ~= "string" or evidenceKey == ""
      or hasEvidence(evidenceKey) then return nil, false end
  for _, pending in ipairs(db.acquisitionPending) do
    if pending.id == id then
      if pending.mailEvidenceKey then return nil, false end
      pending.mailEvidenceKey = evidenceKey
      return pending, true
    end
  end
  return nil, false
end

function GC.Acquisitions.RecordGoldCap(deal, purchase, context, now, evidenceKey)
  if type(deal) ~= "table" or type(purchase) ~= "table" then return nil, false end
  local itemID = purchase.itemID or deal.itemID
  if not isPositiveInteger(itemID) then return nil, false end
  local batch, isNew = GC.Acquisitions.Record({
    source = "goldcap", itemID = itemID,
    positionKey = GC.Acquisitions.PositionKey(itemID, deal.itemKey, deal.isCommodity),
    itemName = deal.itemName, quantity = purchase.quantity, total = purchase.total,
    acquiredAt = now or time(), evidenceKey = evidenceKey, targetUnit = purchase.stressUnit,
    decisionEvidence = {
      version = purchase.decisionVersion, status = purchase.decisionStatus,
      reasons = purchase.decisionReasons,
    },
    character = context and context.char or nil, region = context and context.region or nil,
  })
  if batch and evidenceKey then batch.sniperEvidenceKey = evidenceKey end
  return batch, isNew
end

function GC.Acquisitions.RecordManual(args)
  if type(args) ~= "table" then return nil, false end
  local fields = {}
  for key, value in pairs(args) do fields[key] = value end
  fields.source = "manual"
  return GC.Acquisitions.Record(fields)
end

function GC.Acquisitions.HasEvidence(key)
  return hasEvidence(key)
end

local function validActivityArgs(positionKey, itemID, itemName, character, region, at)
  return type(positionKey) == "string" and positionKey ~= "" and isPositiveInteger(itemID)
    and isNonEmptyString(itemName) and isNonEmptyString(character) and isNonEmptyString(region)
    and isExactInteger(at)
end

local function recordActivity(positionKey, itemID, itemName, character, region, at, quantity)
  if not db or not validActivityArgs(positionKey, itemID, itemName, character, region, at) then return nil end
  if quantity ~= nil and not isPositiveInteger(quantity) then return nil end
  local context = { char = character, region = region }
  local scopeKey = GC.Acquisitions.ScopeKey(positionKey, context)
  if not scopeKey then return nil end
  local activity = db.acquisitionActivity[scopeKey]
  if activity then
    if activity.itemID ~= itemID or activity.itemName ~= itemName
        or activity.character ~= character or activity.region ~= region
        or not isExactInteger(activity.firstSeenAt) then return nil end
    activity.firstSeenAt = math.min(activity.firstSeenAt, at)
  else
    activity = { scopeKey = scopeKey, positionKey = positionKey, itemID = itemID,
      itemName = itemName, character = character, region = region, firstSeenAt = at }
    db.acquisitionActivity[scopeKey] = activity
  end
  activity.lastSeenAt = isExactInteger(activity.lastSeenAt) and math.max(activity.lastSeenAt, at) or at
  if quantity then
    activity.lastPostedAt = isExactInteger(activity.lastPostedAt) and math.max(activity.lastPostedAt, at) or at
    activity.lastPostedQty = quantity
  end
  return activity
end

-- Records positive evidence that a scoped position exists or was posted. It intentionally never
-- interprets a later missing owned-auctions result as a sale; paid seller mail is the sole sale
-- evidence that can consume a batch.
function GC.Acquisitions.ObserveOwnedPosition(positionKey, itemID, itemName, character, region, at)
  return recordActivity(positionKey, itemID, itemName, character, region, at)
end

function GC.Acquisitions.RecordPost(positionKey, itemID, itemName, character, region, quantity, at)
  return recordActivity(positionKey, itemID, itemName, character, region, at, quantity)
end

local function validSaleEntry(entry)
  return type(entry) == "table" and entry.kind == "sale" and entry.source == "mail"
    and isNonEmptyString(entry.key) and isNonEmptyString(entry.itemName)
    and isPositiveInteger(entry.qty) and isPositiveInteger(entry.total) and isExactInteger(entry.at)
    and isNonEmptyString(entry.char) and isNonEmptyString(entry.region) and entry.pending == false
end

local function unresolved(reason)
  return { status = "unresolved", reason = reason }
end

-- A seller invoice carries a name, never a trustworthy item id. Resolve it only through a
-- single scoped position with prior owned/post evidence, then consume that position's batches
-- atomically in FIFO order. No candidate or quantity failure mutates SavedVariables.
function GC.Acquisitions.ReconcileSale(entry)
  if not db or type(entry) ~= "table" then return unresolved("invalid_sale") end
  if type(entry.key) == "string" and db.acquisitionConsumptionEvidence[entry.key] then
    return { status = "duplicate" }
  end
  if entry.pending == true then return unresolved("pending") end
  if not validSaleEntry(entry) then return unresolved("invalid_sale") end
  if GC.Acquisitions.HasEvidence(entry.key) then return unresolved("duplicate_evidence") end

  local context = { char = entry.char, region = entry.region }
  local candidates = {}
  for _, batch in ipairs(GC.Acquisitions.GetActive(context)) do
    if batch.positionKey and batch.itemName == entry.itemName then
      local scopeKey = GC.Acquisitions.ScopeKey(batch.positionKey, context)
      local activity = scopeKey and db.acquisitionActivity[scopeKey] or nil
      if activity and activity.positionKey == batch.positionKey and activity.itemName == entry.itemName
          and activity.character == entry.char and activity.region == entry.region
          and isExactInteger(activity.firstSeenAt) and activity.firstSeenAt <= entry.at then
        local candidate = candidates[scopeKey]
        if not candidate then
          candidate = { positionKey = batch.positionKey, scopeKey = scopeKey, batches = {}, quantity = 0 }
          candidates[scopeKey] = candidate
        end
        local quantity = safeAdd(candidate.quantity, batch.remainingQty)
        if not quantity then return unresolved("invalid_quantity") end
        candidate.quantity = quantity
        candidate.batches[#candidate.batches + 1] = batch
      end
    end
  end

  local candidate, count
  for _, value in pairs(candidates) do candidate, count = value, (count or 0) + 1 end
  if count == nil then return unresolved("no_position") end
  if count ~= 1 then return unresolved("ambiguous_name") end
  if candidate.quantity < entry.qty then return unresolved("insufficient_quantity") end

  local allocation = allocationFor(candidate.batches, entry.qty)
  if not allocation or allocation.coverage ~= "COMPLETE" or not isExactInteger(allocation.knownCost) then
    return unresolved("insufficient_quantity")
  end
  local profit = entry.total - allocation.knownCost
  if not isSignedExactInteger(profit) then return unresolved("invalid_profit") end
  local realized = { key = entry.key, evidenceKey = entry.key, scopeKey = candidate.scopeKey,
    positionKey = candidate.positionKey, itemName = entry.itemName, character = entry.char,
    region = entry.region, quantity = entry.qty, cost = allocation.knownCost,
    proceeds = entry.total, profit = profit, at = entry.at }

  local consumed = GC.Acquisitions.Consume(candidate.positionKey, entry.qty, entry.key, entry.at, context)
  if not consumed or consumed.cost ~= realized.cost then return unresolved("consume_failed") end
  db.acquisitionRealized[#db.acquisitionRealized + 1] = realized
  return { status = "applied", positionKey = candidate.positionKey, quantity = entry.qty,
    cost = realized.cost, proceeds = entry.total, profit = profit }
end

--- Converts the unscoped pre-acquisition flip queue without ever pruning or
-- deleting it. Ledger rows are separately durable evidence: repeated passes
-- may attach newly-arrived rows, but acquisitionVersion prevents a second flip
-- import on an upgraded SavedVariables file.
function GC.Acquisitions.MigrateLegacy(flips, ledger)
  if not db then return end

  local importingFlips = db.acquisitionVersion < 1
  if importingFlips then
    for _, flip in ipairs(flips or {}) do
      if type(flip) == "table" then
        GC.Acquisitions.Record({
          source = "goldcap", itemID = flip.itemID, quantity = flip.qty,
          total = flip.paidTotal, acquiredAt = flip.boughtAt,
          targetUnit = flip.targetUnit,
        })
      end
    end
  end

  for _, entry in ipairs(ledger or {}) do
    if validBuyEntry(entry) and entry.source == "goldcap_sniper" then
      local matched = activeWithEvidence(entry.key)
      if not matched then
        matched = oldestCompatible(db.acquisitions, function(batch)
          return batch.source == "goldcap" and not batch.sniperEvidenceKey
            and compatible(batch, entry) and batch.acquiredAt == entry.at
        end)
        if matched then
          matched.evidenceKeys[entry.key] = true
          matched.sniperEvidenceKey = entry.key
          matched.character = matched.character or entry.char
          matched.region = matched.region or entry.region
        else
          matched = GC.Acquisitions.Record({
            source = "goldcap", itemID = entry.itemID, itemName = entry.itemName,
            quantity = entry.qty, total = entry.total, acquiredAt = entry.at,
            evidenceKey = entry.key, character = entry.char, region = entry.region,
          })
          if matched then matched.sniperEvidenceKey = entry.key end
        end
      end
    elseif validBuyEntry(entry) and entry.source == "mail" then
      GC.Acquisitions.ReconcileBuy(entry)
    end
  end
  if importingFlips then db.acquisitionVersion = 1 end
end

--- Reconciles one stored buyer-mail ledger row. Mail evidence is one-to-one:
-- a key already present wins before any compatibility search, and a compatible
-- batch may only receive its first mail key.
function GC.Acquisitions.ReconcileBuy(entry)
  if not db or not validBuyEntry(entry) or entry.source ~= "mail" then return nil, false end
  local existing = activeWithEvidence(entry.key)
  if existing then return existing, false end
  local resolved = pendingWithEvidence(entry.key)
  if resolved then return resolved, false end

  local hasItemID = isPositiveInteger(entry.itemID)
  local function activeMatch(batch)
    if batch.mailEvidenceKey or not isPositiveInteger(batch.remainingQty)
        or not isExactInteger(batch.remainingTotal) then return false end
    if hasItemID then return compatible(batch, entry) end
    return compatibleByName(batch, entry, batch.originalQty, batch.originalTotal)
  end
  local function pendingMatch(pending)
    if pending.mailEvidenceKey then return false end
    if hasItemID then return compatiblePending(pending, entry) end
    return compatibleByName(pending, entry, pending.quantity, entry.total)
  end

  if not hasItemID then
    if type(entry.itemName) ~= "string" or entry.itemName == "" then return nil, false end
    local candidates = {}
    for _, batch in ipairs(db.acquisitions) do
      if activeMatch(batch) then candidates[#candidates + 1] = batch end
    end
    for _, pending in ipairs(db.acquisitionPending) do
      if pendingMatch(pending) then candidates[#candidates + 1] = pending end
    end
    if #candidates ~= 1 then return nil, false end
    if candidates[1].originalTotal then return attachMailEvidence(candidates[1], entry), true end
    return GC.Acquisitions.ResolvePending(candidates[1].id, entry.key)
  end

  local batch = oldestCompatible(db.acquisitions, activeMatch)
  if batch then return attachMailEvidence(batch, entry), true end

  local pending = oldestCompatible(db.acquisitionPending, pendingMatch)
  if pending then return GC.Acquisitions.ResolvePending(pending.id, entry.key) end

  batch = GC.Acquisitions.Record({
    source = "auction_house", itemID = entry.itemID, itemName = entry.itemName,
    quantity = entry.qty, total = entry.total, acquiredAt = entry.at,
    evidenceKey = entry.key, character = entry.char, region = entry.region,
  })
  if batch then batch.mailEvidenceKey = entry.key end
  return batch, batch ~= nil
end

function GC.Acquisitions.GetAll()
  return (db and db.acquisitions) or {}
end

function GC.Acquisitions.GetActive(context)
  if not db or not validContext(context) then return {} end
  local active = {}
  for _, batch in ipairs(db.acquisitions) do
    if batch.character == context.char and batch.region == context.region
        and isPositiveInteger(batch.remainingQty) and isExactInteger(batch.remainingTotal) then
      active[#active + 1] = batch
    end
  end
  return sortedBatches(active)
end

function GC.Acquisitions.GetPending()
  return (db and db.acquisitionPending) or {}
end

function GC.Acquisitions.GetRealized(context)
  if not db then return {} end
  local realized = {}
  for _, row in pairs(db.acquisitionRealized) do
    if not context or (row.character == context.char and row.region == context.region) then
      realized[#realized + 1] = row
    end
  end
  table.sort(realized, function(left, right) return (left.at or 0) < (right.at or 0) end)
  return realized
end

function GC.Acquisitions.Allocate(batches, quantity)
  return allocationFor(batches, quantity)
end

function GC.Acquisitions.AllocateRange(batches, skippedQty, quantity)
  if not isExactInteger(skippedQty) or not isPositiveInteger(quantity) then return nil end
  local throughQuantity = safeAdd(skippedQty, quantity)
  if not throughQuantity then return nil end
  local through = allocationFor(batches, throughQuantity)
  local skipped = skippedQty == 0 and {
    allocations = {}, knownQty = 0, knownCost = 0,
  } or allocationFor(batches, skippedQty)
  if not through or not skipped then return nil end

  local before = {}
  for _, allocation in ipairs(skipped.allocations) do before[allocation.batchID] = allocation end
  local knownQty = through.knownQty - skipped.knownQty
  local knownCost = through.knownCost - skipped.knownCost
  if not isExactInteger(knownQty) or not isExactInteger(knownCost) then return nil end
  local result = {
    allocations = {}, knownQty = knownQty,
    knownCost = knownCost,
    requestedQty = quantity, coverage = "MISSING",
  }
  for _, allocation in ipairs(through.allocations) do
    local prior = before[allocation.batchID]
    local priorQty, priorCost = prior and prior.quantity or 0, prior and prior.cost or 0
    if allocation.quantity > priorQty then
      result.allocations[#result.allocations + 1] = {
        batchID = allocation.batchID,
        quantity = allocation.quantity - priorQty,
        cost = allocation.cost - priorCost,
        source = allocation.source,
      }
    end
  end
  if result.knownQty == quantity then
    result.coverage = "COMPLETE"
  elseif result.knownQty > 0 then
    result.coverage = "PARTIAL"
  end
  return result
end

function GC.Acquisitions.Consume(positionKey, quantity, evidenceKey, at, context)
  if not db or type(positionKey) ~= "string" or not isPositiveInteger(quantity)
      or type(evidenceKey) ~= "string" or evidenceKey == "" or not isExactInteger(at)
      or not validContext(context) or db.acquisitionConsumptionEvidence[evidenceKey] then
    return nil
  end
  local eligible = {}
  for _, batch in ipairs(GC.Acquisitions.GetActive(context)) do
    if batch.positionKey == positionKey then
      eligible[#eligible + 1] = batch
      if batch.consumedEvidenceKeys and batch.consumedEvidenceKeys[evidenceKey] then return nil end
    end
  end
  local plan = allocationFor(eligible, quantity)
  if not plan or plan.coverage ~= "COMPLETE" then return nil end

  local byID, updates = {}, {}
  for _, batch in ipairs(eligible) do byID[batch.id] = batch end
  for _, allocation in ipairs(plan.allocations) do
    local batch = byID[allocation.batchID]
    local state = batch and copyBatchState(batch) or nil
    local taken = state and takeCost(state, allocation.quantity) or nil
    if taken ~= allocation.cost then return nil end
    updates[#updates + 1] = { batch = batch, state = state }
  end
  for _, update in ipairs(updates) do
    update.batch.remainingQty = update.state.remainingQty
    update.batch.remainingTotal = update.state.remainingTotal
    update.batch.consumedEvidenceKeys[evidenceKey] = true
  end
  db.acquisitionConsumptionEvidence[evidenceKey] = true
  return {
    evidenceKey = evidenceKey,
    scopeKey = GC.Acquisitions.ScopeKey(positionKey, context),
    quantity = quantity,
    cost = plan.knownCost,
    at = at,
    allocations = plan.allocations,
  }
end
