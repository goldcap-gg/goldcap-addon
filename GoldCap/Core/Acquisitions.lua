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

local function sequenceFor(id)
  local value = type(id) == "string" and id:match("^acq:(%d+)$") or nil
  return value and tonumber(value) or 0
end

local function lessByFIFO(left, right)
  local leftAt, rightAt = left.acquiredAt or 0, right.acquiredAt or 0
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

local function takeCost(batch, qty)
  local beforeQty = batch.remainingQty
  local cost = (qty == beforeQty)
    and batch.remainingTotal
    or math.floor(batch.remainingTotal * qty / beforeQty)
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
      result.allocations[#result.allocations + 1] = {
        batchID = batch.id,
        quantity = qty,
        cost = cost,
        source = batch.source,
      }
      result.knownQty = result.knownQty + qty
      result.knownCost = result.knownCost + cost
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

  if args.evidenceKey then
    for _, batch in ipairs(db.acquisitions) do
      if batch.evidenceKeys and batch.evidenceKeys[args.evidenceKey] then return batch, false end
    end
  end

  db.acquisitionSeq = db.acquisitionSeq + 1
  local batch = {
    id = "acq:" .. db.acquisitionSeq,
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
  if args.evidenceKey then batch.evidenceKeys[args.evidenceKey] = true end
  db.acquisitions[#db.acquisitions + 1] = batch
  return batch, true
end

function GC.Acquisitions.RecordPending(args)
  if not db or type(args) ~= "table" or not isPositiveInteger(args.itemID)
      or not isPositiveInteger(args.quantity) or not isExactInteger(args.completedAt)
      or not isStringOrNil(args.positionKey) or not isStringOrNil(args.itemName)
      or not isStringOrNil(args.character) or not isStringOrNil(args.region)
      or type(args.reason) ~= "string" or args.reason == ""
      or not isStringOrNil(args.evidenceKey) or args.evidenceKey == "" then
    return nil, false
  end
  if args.evidenceKey then
    for _, pending in ipairs(db.acquisitionPending) do
      if pending.evidenceKeys and pending.evidenceKeys[args.evidenceKey] then return pending, false end
    end
  end
  db.acquisitionPendingSeq = db.acquisitionPendingSeq + 1
  local pending = {
    id = "pending:" .. db.acquisitionPendingSeq,
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
  return GC.Acquisitions.Record({
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
end

function GC.Acquisitions.RecordManual(args)
  if type(args) ~= "table" then return nil, false end
  local fields = {}
  for key, value in pairs(args) do fields[key] = value end
  fields.source = "manual"
  return GC.Acquisitions.Record(fields)
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
  local through = allocationFor(batches, skippedQty + quantity)
  local skipped = skippedQty == 0 and {
    allocations = {}, knownQty = 0, knownCost = 0,
  } or allocationFor(batches, skippedQty)
  if not through or not skipped then return nil end

  local before = {}
  for _, allocation in ipairs(skipped.allocations) do before[allocation.batchID] = allocation end
  local result = {
    allocations = {}, knownQty = through.knownQty - skipped.knownQty,
    knownCost = through.knownCost - skipped.knownCost,
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
  local available = 0
  for _, batch in ipairs(GC.Acquisitions.GetActive(context)) do
    if batch.positionKey == positionKey then
      eligible[#eligible + 1] = batch
      available = available + batch.remainingQty
      if batch.consumedEvidenceKeys and batch.consumedEvidenceKeys[evidenceKey] then return nil end
    end
  end
  if available < quantity then return nil end

  local remaining, cost, allocations = quantity, 0, {}
  for _, batch in ipairs(eligible) do
    if remaining == 0 then break end
    local qty = math.min(remaining, batch.remainingQty)
    local taken = takeCost(batch, qty)
    batch.consumedEvidenceKeys[evidenceKey] = true
    allocations[#allocations + 1] = { batchID = batch.id, quantity = qty, cost = taken,
      source = batch.source }
    remaining = remaining - qty
    cost = cost + taken
  end
  db.acquisitionConsumptionEvidence[evidenceKey] = true
  return {
    evidenceKey = evidenceKey,
    scopeKey = GC.Acquisitions.ScopeKey(positionKey, context),
    quantity = quantity,
    cost = cost,
    at = at,
    allocations = allocations,
  }
end
