local _, GC = ...

GC.Acquisitions = {}

local db
local MAX_EXACT = 9007199254740991
local SOURCES = { goldcap = true, auction_house = true, manual = true }
local migrateLegacyRepairGroups
local validRepairGroup
local repairGroupEvidenceState
local repairGroupOwnsEvidence
local repairGroupClaimsPending
local sameMailEvidence

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
  if repairGroupOwnsEvidence and repairGroupOwnsEvidence(key) then return true end
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
  batch.itemName = batch.itemName or entry.itemName
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

local function validAcquisitionStoreShape(acquisitions)
  if type(acquisitions) ~= "table" then return false end
  local acquisitionCount = 0
  for index, batch in pairs(acquisitions) do
    acquisitionCount = acquisitionCount + 1
    if not isPositiveInteger(index) or type(batch) ~= "table" then return false end
  end
  for index = 1, acquisitionCount do
    if rawget(acquisitions, index) == nil then return false end
  end
  return true
end

function GC.Acquisitions.Init(database)
  db = database
  if type(db) ~= "table" then return false end
  if db.acquisitions ~= nil and not validAcquisitionStoreShape(db.acquisitions) then return false end
  db.acquisitions = type(db.acquisitions) == "table" and db.acquisitions or {}
  db.acquisitionPending = type(db.acquisitionPending) == "table" and db.acquisitionPending or {}
  db.acquisitionRealized = type(db.acquisitionRealized) == "table" and db.acquisitionRealized or {}
  db.acquisitionActivity = type(db.acquisitionActivity) == "table" and db.acquisitionActivity or {}
  db.acquisitionConsumptionEvidence = type(db.acquisitionConsumptionEvidence) == "table"
    and db.acquisitionConsumptionEvidence or {}
  -- Repair groups are introduced after pending repairs already existed.  Leave
  -- a non-table value intact so reconciliation can fail closed instead of
  -- silently discarding corrupted SavedVariables evidence.
  local needsRepairGroupMigration = db.acquisitionRepairGroups == nil
  if needsRepairGroupMigration then db.acquisitionRepairGroups = {} end
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
  if needsRepairGroupMigration and migrateLegacyRepairGroups then migrateLegacyRepairGroups() end
  return true
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
    if repairGroupOwnsEvidence and repairGroupOwnsEvidence(args.evidenceKey) then return nil, false end
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
    for key, present in pairs(type(pending.evidenceKeys) == "table" and pending.evidenceKeys or {}) do
      if present then batch.evidenceKeys[key] = true end
    end
    if pending.mailEvidenceKey then
      batch.evidenceKeys[pending.mailEvidenceKey] = true
      batch.mailEvidenceKey = pending.mailEvidenceKey
    end
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
    if repairGroupOwnsEvidence and repairGroupOwnsEvidence(args.evidenceKey) then return nil, false end
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
  if repairGroupClaimsPending and repairGroupClaimsPending(id) then return nil, false end
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

local function pendingByID(id)
  for index, pending in ipairs(db and db.acquisitionPending or {}) do
    if type(pending) == "table" and pending.id == id then return pending, index end
  end
  return nil
end

local function batchByID(id)
  for _, batch in ipairs(db and db.acquisitions or {}) do
    if type(batch) == "table" and batch.id == id then return batch end
  end
  return nil
end

local function positionKeyMatchesItem(positionKey, itemID)
  if positionKey == ("commodity:%d"):format(itemID) then return true end
  if type(positionKey) ~= "string" then return false end
  local matchedID, itemLevel, itemSuffix, petSpecies = positionKey:match("^item:(%d+):(-?%d+):(-?%d+):(-?%d+)$")
  return matchedID == tostring(itemID) and isExactInteger(tonumber(itemLevel))
    and isSignedExactInteger(tonumber(itemSuffix)) and isExactInteger(tonumber(petSpecies))
end

local function validStoredActivity(mapKey, activity)
  if not isNonEmptyString(mapKey) or type(activity) ~= "table"
      or not isPositiveInteger(activity.itemID)
      or not positionKeyMatchesItem(activity.positionKey, activity.itemID)
      or not isNonEmptyString(activity.itemName) or not isNonEmptyString(activity.character)
      or not isNonEmptyString(activity.region) or not isExactInteger(activity.firstSeenAt)
      or (activity.lastSeenAt ~= nil and not isExactInteger(activity.lastSeenAt))
      or (activity.lastPostedAt ~= nil and not isExactInteger(activity.lastPostedAt))
      or (activity.lastPostedQty ~= nil and not isPositiveInteger(activity.lastPostedQty)) then
    return nil
  end
  local scopeKey = GC.Acquisitions.ScopeKey(activity.positionKey,
    { char = activity.character, region = activity.region })
  if not scopeKey or activity.scopeKey ~= scopeKey or mapKey ~= scopeKey then return nil end
  return scopeKey
end

local function validEvidenceKeys(keys)
  if type(keys) ~= "table" then return false end
  for key, present in pairs(keys) do
    if not isNonEmptyString(key) or present ~= true then return false end
  end
  return true
end

local function copyEvidenceKeys(keys)
  local copy = {}
  for key, present in pairs(keys or {}) do
    if present then copy[key] = true end
  end
  return copy
end

local function sameEvidenceKeys(left, right)
  if not validEvidenceKeys(left) or not validEvidenceKeys(right) then return false end
  for key in pairs(left) do
    if right[key] ~= true then return false end
  end
  for key in pairs(right) do
    if left[key] ~= true then return false end
  end
  return true
end

local function matchingPendingForGroup(group)
  local pending, pendingIndex, matches
  for index, candidate in ipairs(db and db.acquisitionPending or {}) do
    if type(candidate) == "table" and candidate.id == group.pendingID then
      pending, pendingIndex, matches = candidate, index, (matches or 0) + 1
    end
  end
  if matches ~= 1 then return nil end
  return pending, pendingIndex
end

validRepairGroup = function(groupKey, group)
  if not isNonEmptyString(groupKey) or type(group) ~= "table" or group.pendingID ~= groupKey
      or not isPositiveInteger(group.itemID) or not positionKeyMatchesItem(group.positionKey, group.itemID)
      or not isStringOrNil(group.itemName) or not isPositiveInteger(group.originalQty)
      or not isExactInteger(group.completedAt) or not isNonEmptyString(group.character)
      or not isNonEmptyString(group.region) or not validEvidenceKeys(group.completionEvidenceKeys)
      or type(group.repairs) ~= "table" or type(group.mailEvidenceKeys) ~= "table"
      or type(group.mailEvidence) ~= "table" then
    return nil
  end

  local repairedQty, repairedTotal, repairIDs, repairBatchIDs, repairCount = 0, 0, {}, {}, 0
  for _, repair in ipairs(group.repairs) do
    repairCount = repairCount + 1
    if type(repair) ~= "table" or not isNonEmptyString(repair.repairID)
        or not isNonEmptyString(repair.batchID) or not isPositiveInteger(repair.quantity)
        or not isPositiveInteger(repair.total) or repairIDs[repair.repairID]
        or repairBatchIDs[repair.batchID] then
      return nil
    end
    repairIDs[repair.repairID], repairBatchIDs[repair.batchID] = true, true
    repairedQty, repairedTotal = safeAdd(repairedQty, repair.quantity), safeAdd(repairedTotal, repair.total)
    local batch = batchByID(repair.batchID)
    if not repairedQty or not repairedTotal or not batch or batch.source ~= "manual"
        or batch.repairedPendingID ~= group.pendingID or batch.repairEvidenceKey ~= repair.repairID
        or batch.itemID ~= group.itemID or batch.positionKey ~= group.positionKey
        or batch.originalQty ~= repair.quantity or batch.originalTotal ~= repair.total
        or batch.character ~= group.character or batch.region ~= group.region
        or type(batch.evidenceKeys) ~= "table" or batch.evidenceKeys[repair.repairID] ~= true
        or (group.itemName and batch.itemName and group.itemName ~= batch.itemName) then
      return nil
    end
  end
  for index in pairs(group.repairs) do
    if not isPositiveInteger(index) or index > repairCount then return nil end
  end
  if repairCount == 0 or group.repairedQty ~= repairedQty or group.repairedTotal ~= repairedTotal
      or repairedQty > group.originalQty then
    return nil
  end
  local markedCount = 0
  for _, batch in ipairs(db and db.acquisitions or {}) do
    if type(batch) == "table" and batch.repairedPendingID == group.pendingID then
      if batch.source ~= "manual" or not isNonEmptyString(batch.repairEvidenceKey)
          or not repairBatchIDs[batch.id] then
        return nil
      end
      markedCount = markedCount + 1
    end
  end
  if markedCount ~= repairCount then return nil end

  local mailCount, mailRecord
  for key, present in pairs(group.mailEvidenceKeys) do
    if not isNonEmptyString(key) or present ~= true or type(group.mailEvidence[key]) ~= "table" then
      return nil
    end
    local evidence = group.mailEvidence[key]
    if evidence.key ~= key or evidence.source ~= "mail" or evidence.kind ~= "buy"
        or evidence.itemID ~= group.itemID or evidence.qty ~= group.originalQty
        or not isPositiveInteger(evidence.total) or not isExactInteger(evidence.at)
        or evidence.char ~= group.character or evidence.region ~= group.region
        or not isStringOrNil(evidence.itemName) then
      return nil
    end
    if group.itemName and evidence.itemName and group.itemName ~= evidence.itemName then return nil end
    mailCount, mailRecord = (mailCount or 0) + 1, evidence
  end
  for key in pairs(group.mailEvidence) do
    if group.mailEvidenceKeys[key] ~= true then return nil end
  end
  if (mailCount or 0) > 1 then return nil end

  local remainingQty = group.originalQty - repairedQty
  local pending, pendingIndex = matchingPendingForGroup(group)
  if mailCount then
    local mailBatch = isNonEmptyString(group.mailBatchID) and batchByID(group.mailBatchID) or nil
    if pending or not mailBatch then return nil end
    if remainingQty == 0 then
      if mailRecord.total ~= repairedTotal or not repairBatchIDs[group.mailBatchID]
          or type(mailBatch.evidenceKeys) ~= "table"
          or mailBatch.evidenceKeys[mailRecord.key] ~= true then
        return nil
      end
    else
      local residualTotal = mailRecord.total - repairedTotal
      if not isPositiveInteger(residualTotal) or mailBatch.source ~= "auction_house"
          or mailBatch.promotedPendingID ~= group.pendingID or mailBatch.itemID ~= group.itemID
          or mailBatch.positionKey ~= group.positionKey or mailBatch.originalQty ~= remainingQty
          or mailBatch.originalTotal ~= residualTotal or mailBatch.character ~= group.character
          or mailBatch.region ~= group.region or type(mailBatch.evidenceKeys) ~= "table"
          or mailBatch.evidenceKeys[mailRecord.key] ~= true then
        return nil
      end
    end
  elseif remainingQty == 0 then
    if pending then return nil end
  else
    if not pending or not isPositiveInteger(pending.quantity) or pending.quantity ~= remainingQty
        or pending.itemID ~= group.itemID or pending.positionKey ~= group.positionKey
        or pending.character ~= group.character or pending.region ~= group.region
        or pending.completedAt ~= group.completedAt
        or pending.mailEvidenceKey ~= nil
        or not sameEvidenceKeys(pending.evidenceKeys, group.completionEvidenceKeys)
        or (pending.itemName and group.itemName and pending.itemName ~= group.itemName) then
      return nil
    end
  end
  return {
    group = group, remainingQty = remainingQty, pending = pending,
    pendingIndex = pendingIndex, mailEvidence = mailRecord,
  }
end

local function invalidRepairGroupClaimsEvidence(group, key)
  if type(group) ~= "table" then return false end
  if type(group.completionEvidenceKeys) == "table" and group.completionEvidenceKeys[key] ~= nil then
    return true
  end
  if type(group.mailEvidenceKeys) == "table" and group.mailEvidenceKeys[key] ~= nil then return true end
  if type(group.mailEvidence) == "table" and group.mailEvidence[key] ~= nil then return true end
  if type(group.repairs) == "table" then
    for _, repair in pairs(group.repairs) do
      if type(repair) == "table" and repair.repairID == key then return true end
    end
  end
  return false
end

-- Group evidence is authoritative even when its group can no longer be
-- validated.  A corrupt claimant must block a replay rather than allowing a
-- generic pending/acquisition record to duplicate the original event.
repairGroupEvidenceState = function(key)
  if not isNonEmptyString(key) then return "NONE" end
  local groups = db and db.acquisitionRepairGroups
  if groups == nil then return "NONE" end
  if type(groups) ~= "table" then return "BLOCKED" end
  local owned = false
  for groupKey, group in pairs(db.acquisitionRepairGroups) do
    local state = validRepairGroup(groupKey, group)
    if state then
      if state.group.completionEvidenceKeys[key] or state.group.mailEvidenceKeys[key] then owned = true end
      for _, repair in ipairs(state.group.repairs) do
        if repair.repairID == key then owned = true end
      end
    elseif invalidRepairGroupClaimsEvidence(group, key) then
      return "BLOCKED"
    end
  end
  return owned and "OWNED" or "NONE"
end

repairGroupOwnsEvidence = function(key)
  return repairGroupEvidenceState(key) ~= "NONE"
end

repairGroupClaimsPending = function(id)
  local groups = db and db.acquisitionRepairGroups
  if groups == nil then return false end
  if type(groups) ~= "table" then return true end
  if groups[id] ~= nil then return true end
  for _, group in pairs(groups) do
    if type(group) == "table" and group.pendingID == id then return true end
  end
  return false
end

-- Every repair marker on an acquisition is a reverse reference into the group
-- store.  Group validation proves the forward fields; this pass prevents an
-- orphaned or multiply claimed allocation from falling through to generic
-- buyer-mail creation after the group entry is deleted or corrupted.
local function validRepairGroupAllocations()
  if type(db and db.acquisitionRepairGroups) ~= "table"
      or not validAcquisitionStoreShape(db.acquisitions) then return false end
  local claimed = {}
  for groupKey, group in pairs(db.acquisitionRepairGroups) do
    local state = validRepairGroup(groupKey, group)
    if not state then return false end
    for _, repair in ipairs(state.group.repairs) do
      local batch = batchByID(repair.batchID)
      if not batch or claimed[batch] then return false end
      claimed[batch] = true
    end
  end
  for _, batch in pairs(db.acquisitions) do
    if (batch.repairedPendingID ~= nil or batch.repairEvidenceKey ~= nil)
        and not claimed[batch] then
      return false
    end
  end
  return true
end

local function repairGroupForMail(entry)
  if type(db.acquisitionRepairGroups) ~= "table" or not validRepairGroupAllocations() then
    return nil, "BLOCKED"
  end
  local found
  for groupKey, group in pairs(db.acquisitionRepairGroups) do
    local state = validRepairGroup(groupKey, group)
    if not state then return nil, "BLOCKED" end
    local candidate = state.group
    -- An already-absorbed group is auditable for its own exact mail key but
    -- cannot reserve a later, distinct buyer invoice with the same shape.
    if not state.mailEvidence and candidate.itemID == entry.itemID
        and candidate.character == entry.char and candidate.region == entry.region then
      if candidate.originalQty ~= entry.qty
          or (candidate.itemName and entry.itemName and candidate.itemName ~= entry.itemName) then
        return nil, "BLOCKED"
      end
      if found then return nil, "BLOCKED" end
      found = state
    end
  end
  return found, found and "EXACT" or "NONE"
end

-- Group-owned mail must validate the group and the complete original ledger
-- entry before the ordinary active-batch shortcut can return it.
local function repairGroupMailForEntry(entry)
  if type(db.acquisitionRepairGroups) ~= "table" then return nil, "BLOCKED" end
  local found
  for groupKey, group in pairs(db.acquisitionRepairGroups) do
    local state = validRepairGroup(groupKey, group)
    if not state then return nil, "BLOCKED" end
    if state.mailEvidence and state.mailEvidence.key == entry.key then
      if found or not sameMailEvidence(state.mailEvidence, entry) then return nil, "BLOCKED" end
      found = state
    end
  end
  return found, found and "EXACT" or "NONE"
end

-- Pre-group repairs already persist a batch marker and, for partial repairs,
-- the residual pending row. Rebuild only metadata from that exact evidence;
-- anything that cannot be proven leaves an invalid sentinel so mail cannot
-- fall through into a duplicate full batch after an upgrade.
migrateLegacyRepairGroups = function()
  local store = db and db.acquisitionRepairGroups
  if type(store) ~= "table" then return end
  local groups, invalid = {}, false
  for _, batch in ipairs(db.acquisitions or {}) do
    if type(batch) == "table" and batch.source == "manual" and batch.repairedPendingID ~= nil then
      local pendingID = batch.repairedPendingID
      if not isNonEmptyString(pendingID) or not isNonEmptyString(batch.repairEvidenceKey)
          or not isPositiveInteger(batch.itemID) or not positionKeyMatchesItem(batch.positionKey, batch.itemID)
          or not isStringOrNil(batch.itemName) or not isPositiveInteger(batch.originalQty)
          or not isPositiveInteger(batch.originalTotal) or not isExactInteger(batch.acquiredAt)
          or not isNonEmptyString(batch.character) or not isNonEmptyString(batch.region) then
        invalid = true
      else
        local group = groups[pendingID]
        if not group then
          group = { pendingID = pendingID, itemID = batch.itemID, positionKey = batch.positionKey,
            itemName = batch.itemName, character = batch.character, region = batch.region,
            completedAt = batch.acquiredAt, completionEvidenceKeys = {}, repairs = {},
            repairedQty = 0, repairedTotal = 0, mailEvidenceKeys = {}, mailEvidence = {} }
          groups[pendingID] = group
        end
        if group.itemID ~= batch.itemID or group.positionKey ~= batch.positionKey
            or group.character ~= batch.character or group.region ~= batch.region
            or (group.itemName and batch.itemName and group.itemName ~= batch.itemName) then
          invalid = true
        else
          group.itemName = group.itemName or batch.itemName
          group.completedAt = math.min(group.completedAt, batch.acquiredAt)
          group.repairedQty = safeAdd(group.repairedQty, batch.originalQty)
          group.repairedTotal = safeAdd(group.repairedTotal, batch.originalTotal)
          if not group.repairedQty or not group.repairedTotal then
            invalid = true
          else
            group.repairs[#group.repairs + 1] = { repairID = batch.repairEvidenceKey,
              batchID = batch.id, quantity = batch.originalQty, total = batch.originalTotal }
          end
        end
      end
    end
  end
  for pendingID, group in pairs(groups) do
    local pending = pendingByID(pendingID)
    if pending then
      if not isPositiveInteger(pending.quantity) or pending.itemID ~= group.itemID
          or pending.positionKey ~= group.positionKey or pending.character ~= group.character
          or pending.region ~= group.region or not isExactInteger(pending.completedAt)
          or not isStringOrNil(pending.itemName) or not validEvidenceKeys(pending.evidenceKeys)
          or (group.itemName and pending.itemName and group.itemName ~= pending.itemName) then
        invalid = true
      else
        group.itemName = group.itemName or pending.itemName
        group.completedAt = pending.completedAt
        group.completionEvidenceKeys = copyEvidenceKeys(pending.evidenceKeys)
        group.originalQty = safeAdd(group.repairedQty, pending.quantity)
      end
    else
      -- A full legacy repair has no remaining pending row from which to prove
      -- its original quantity or completion evidence. Keep the group invalid
      -- instead of inventing facts that could admit duplicate buyer mail.
      invalid = true
    end
    if not group.originalQty or not validRepairGroup(pendingID, group) then invalid = true end
    store[pendingID] = group
  end
  if invalid then store["__invalid_legacy_repair_group"] = false end
end

local function exactRepairMatches(batch, args)
  return batch and batch.source == "manual" and batch.repairedPendingID == args.pendingID
    and batch.itemID == args.itemID and batch.positionKey == args.positionKey
    and batch.originalQty == args.quantity and batch.originalTotal == args.total
    and batch.character == args.character and batch.region == args.region
end

-- Converts an exact quantity of one persisted unresolved purchase into manual
-- cost.  The repair key is an audit identity supplied by the dialog/caller:
-- replaying it returns the original batch, while a different key is a distinct
-- explicit repair.  Every validation precedes Record(), so a bad quantity,
-- scope, or identity leaves both the pending evidence and active basis alone.
function GC.Acquisitions.RepairPendingManual(args)
  if not db or type(args) ~= "table" or not isNonEmptyString(args.pendingID)
      or not isNonEmptyString(args.repairID) or not isPositiveInteger(args.itemID)
      or not isNonEmptyString(args.positionKey) or not isStringOrNil(args.itemName)
      or not isPositiveInteger(args.quantity) or not isPositiveInteger(args.total)
      or not isExactInteger(args.acquiredAt) or not isNonEmptyString(args.character)
      or not isNonEmptyString(args.region) or not positionKeyMatchesItem(args.positionKey, args.itemID)
      or type(db.acquisitionRepairGroups) ~= "table" then
    return nil, false
  end

  local existingGroup = db.acquisitionRepairGroups[args.pendingID]
  local groupState = existingGroup and validRepairGroup(args.pendingID, existingGroup) or nil
  if existingGroup and not groupState then return nil, false end
  local repeated = activeWithEvidence(args.repairID)
  if repeated then
    if not groupState or not exactRepairMatches(repeated, args) then return nil, false end
    for _, repair in ipairs(groupState.group.repairs) do
      if repair.repairID == args.repairID and repair.batchID == repeated.id then return repeated, false end
    end
    return nil, false
  end
  if hasEvidence(args.repairID) then return nil, false end

  local pending, pendingIndex = pendingByID(args.pendingID)
  if not pending or not isPositiveInteger(pending.quantity) or pending.itemID ~= args.itemID
      or pending.positionKey ~= args.positionKey or pending.character ~= args.character
      or pending.region ~= args.region or args.quantity > pending.quantity
      or not positionKeyMatchesItem(pending.positionKey, pending.itemID)
      or not isStringOrNil(pending.itemName) or not isExactInteger(pending.completedAt)
      or not validEvidenceKeys(pending.evidenceKeys)
      or (pending.itemName and args.itemName and pending.itemName ~= args.itemName) then
    return nil, false
  end

  local group = groupState and groupState.group or {
    pendingID = pending.id, itemID = pending.itemID, positionKey = pending.positionKey,
    itemName = pending.itemName, originalQty = pending.quantity, completedAt = pending.completedAt,
    character = pending.character, region = pending.region,
    completionEvidenceKeys = copyEvidenceKeys(pending.evidenceKeys), repairs = {},
    repairedQty = 0, repairedTotal = 0, mailEvidenceKeys = {}, mailEvidence = {},
  }
  if group.itemName and args.itemName and group.itemName ~= args.itemName then return nil, false end
  local repairedQty, repairedTotal = safeAdd(group.repairedQty, args.quantity), safeAdd(group.repairedTotal, args.total)
  if not repairedQty or not repairedTotal or repairedQty > group.originalQty
      or pending.quantity ~= group.originalQty - group.repairedQty then
    return nil, false
  end

  local batch, isNew = GC.Acquisitions.Record({ source = "manual", itemID = args.itemID,
    positionKey = args.positionKey, itemName = args.itemName or pending.itemName,
    quantity = args.quantity, total = args.total, acquiredAt = args.acquiredAt,
    evidenceKey = args.repairID, character = args.character, region = args.region })
  if not batch or not isNew then return nil, false end

  batch.repairedPendingID, batch.repairEvidenceKey = pending.id, args.repairID
  group.itemName = group.itemName or args.itemName or pending.itemName
  group.repairs[#group.repairs + 1] = { repairID = args.repairID, batchID = batch.id,
    quantity = args.quantity, total = args.total }
  group.repairedQty, group.repairedTotal = repairedQty, repairedTotal
  db.acquisitionRepairGroups[pending.id] = group
  pending.repairEvidenceKeys = type(pending.repairEvidenceKeys) == "table"
    and pending.repairEvidenceKeys or {}
  pending.repairEvidenceKeys[args.repairID] = true
  if args.quantity == pending.quantity then
    table.remove(db.acquisitionPending, pendingIndex)
  else
    pending.quantity = pending.quantity - args.quantity
  end
  return batch, true
end

local function uniqueBoundVariant(batch, candidates, context)
  if type(candidates) ~= "table" then return nil end
  local candidateKey
  for _, candidate in ipairs(candidates) do
    if type(candidate) ~= "table" or candidate.itemID ~= batch.itemID
        or candidate.character ~= context.char or candidate.region ~= context.region
        or not positionKeyMatchesItem(candidate.positionKey, batch.itemID) then
      return nil
    end
    if candidateKey and candidateKey ~= candidate.positionKey then return nil end
    candidateKey = candidate.positionKey
  end
  if not candidateKey then return nil end

  -- Current owned evidence enters the store through ObserveOwnedPosition.
  -- Require all durable scoped activity evidence for this item to agree too:
  -- a caller cannot hide a second known variant by passing just the convenient
  -- candidate to this explicit binding API.
  if type(db.acquisitionActivity) ~= "table" then return nil end
  local activityKey
  for mapKey, activity in pairs(db.acquisitionActivity) do
    if not validStoredActivity(mapKey, activity) then return nil end
    if activity.character == context.char and activity.region == context.region
        and activity.itemID == batch.itemID then
      if activityKey and activityKey ~= activity.positionKey then return nil end
      activityKey = activity.positionKey
    end
  end
  if activityKey ~= candidateKey then return nil end
  return candidateKey
end

-- Item-only migrated evidence has no safe variant identity on its own.  This
-- is intentionally explicit and persisted: pure Sell composition may display
-- a uniquely compatible live variant, but only this API turns that fact into a
-- position key that a later exact sale may consume.
function GC.Acquisitions.BindItemOnly(batchID, candidates, context)
  if not db or not isNonEmptyString(batchID) or not validContext(context) then return nil, false end
  local batch = batchByID(batchID)
  if not batch or batch.character ~= context.char or batch.region ~= context.region
      or not isPositiveInteger(batch.itemID) or not isPositiveInteger(batch.remainingQty)
      or not isExactInteger(batch.remainingTotal) then
    return nil, false
  end
  local positionKey = uniqueBoundVariant(batch, candidates, context)
  if not positionKey then return nil, false end
  if batch.positionKey then return batch.positionKey == positionKey and batch or nil, false end
  batch.positionKey = positionKey
  batch.positionBinding = { positionKey = positionKey, itemID = batch.itemID,
    character = context.char, region = context.region,
    scopeKey = GC.Acquisitions.ScopeKey(positionKey, context) }
  return batch, true
end

function GC.Acquisitions.HasEvidence(key)
  return hasEvidence(key)
end

local function validActivityArgs(positionKey, itemID, itemName, character, region, at)
  return type(positionKey) == "string" and positionKey ~= "" and isPositiveInteger(itemID)
    and positionKeyMatchesItem(positionKey, itemID)
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
    if not validStoredActivity(scopeKey, activity) or activity.itemID ~= itemID or activity.itemName ~= itemName
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
  local activeByScope = {}
  for _, batch in ipairs(GC.Acquisitions.GetActive(context)) do
    if batch.positionKey then
      local scopeKey = GC.Acquisitions.ScopeKey(batch.positionKey, context)
      local candidate = activeByScope[scopeKey]
      if not candidate then
        candidate = { positionKey = batch.positionKey, scopeKey = scopeKey,
          itemID = batch.itemID, batches = {}, quantity = 0 }
        activeByScope[scopeKey] = candidate
      elseif candidate.itemID ~= batch.itemID then
        return unresolved("invalid_position")
      end
      local quantity = safeAdd(candidate.quantity, batch.remainingQty)
      if not quantity then return unresolved("invalid_quantity") end
      candidate.quantity = quantity
      candidate.batches[#candidate.batches + 1] = batch
    end
  end

  if type(db.acquisitionActivity) ~= "table" then return unresolved("invalid_activity") end
  local candidates = {}
  for scopeKey, activity in pairs(db.acquisitionActivity) do
    if not validStoredActivity(scopeKey, activity) then return unresolved("invalid_activity") end
    local candidate = activeByScope[scopeKey]
    if candidate and activity.positionKey == candidate.positionKey and activity.itemID == candidate.itemID
        and activity.itemName == entry.itemName
        and activity.character == entry.char and activity.region == entry.region
        and isExactInteger(activity.firstSeenAt) and activity.firstSeenAt <= entry.at then
      candidates[scopeKey] = candidate
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

  local consumed = GC.Acquisitions.Consume(candidate.positionKey, entry.qty, entry.key, entry.at,
    context, allocation)
  if not consumed then return unresolved("consume_failed") end
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

local function copyMailEvidence(entry)
  return { key = entry.key, kind = entry.kind, source = entry.source, itemID = entry.itemID,
    itemName = entry.itemName, qty = entry.qty, total = entry.total, at = entry.at,
    char = entry.char, region = entry.region }
end

sameMailEvidence = function(stored, entry)
  return stored and stored.key == entry.key and stored.kind == entry.kind
    and stored.source == entry.source and stored.itemID == entry.itemID
    and stored.itemName == entry.itemName and stored.qty == entry.qty
    and stored.total == entry.total and stored.at == entry.at
    and stored.char == entry.char and stored.region == entry.region
end

-- Reconciles mail against the durable identity created by RepairPendingManual.
-- The entire group is validated before Record() or table.remove(), so corrupt
-- state can never fall through to the generic full-mail batch path.
local function reconcileRepairGroup(state, entry)
  local group = state.group
  if state.mailEvidence then
    if not sameMailEvidence(state.mailEvidence, entry) then return nil, false end
    return batchByID(group.mailBatchID), false
  end

  if state.remainingQty == 0 then
    if group.repairedTotal ~= entry.total then return nil, false end
    if activeWithEvidence(entry.key) or pendingWithEvidence(entry.key) then return nil, false end
    local batch = batchByID(group.repairs[1].batchID)
    if not batch then return nil, false end
    attachMailEvidence(batch, entry)
    group.mailEvidenceKeys[entry.key] = true
    group.mailEvidence[entry.key] = copyMailEvidence(entry)
    group.mailBatchID = batch.id
    return batch, false
  end

  local residualQty = state.remainingQty
  local repairedAndResidual = safeAdd(group.repairedQty, residualQty)
  local residualTotal = entry.total - group.repairedTotal
  if repairedAndResidual ~= entry.qty or residualTotal <= 0 or not isPositiveInteger(residualTotal)
      or not state.pending or not state.pendingIndex then
    return nil, false
  end
  for key, present in pairs(group.completionEvidenceKeys) do
    if present and activeWithEvidence(key) then return nil, false end
  end
  if pendingWithEvidence(entry.key) then return nil, false end

  local residual, isNew = GC.Acquisitions.Record({ source = "auction_house", itemID = group.itemID,
    positionKey = group.positionKey, itemName = entry.itemName or group.itemName,
    quantity = residualQty, total = residualTotal, acquiredAt = group.completedAt,
    evidenceKey = entry.key, character = group.character, region = group.region })
  if not residual or not isNew then return nil, false end

  residual.promotedPendingID = group.pendingID
  for key, present in pairs(group.completionEvidenceKeys) do
    if present then residual.evidenceKeys[key] = true end
  end
  residual.mailEvidenceKey = entry.key
  group.mailEvidenceKeys[entry.key] = true
  group.mailEvidence[entry.key] = copyMailEvidence(entry)
  group.mailBatchID = residual.id
  table.remove(db.acquisitionPending, state.pendingIndex)
  return residual, true
end

--- Reconciles one stored buyer-mail ledger row. Mail evidence is one-to-one:
-- a key already present wins before any compatibility search, and a compatible
-- batch may only receive its first mail key.
function GC.Acquisitions.ReconcileBuy(entry)
  if not db or not validBuyEntry(entry) or entry.source ~= "mail" then return nil, false end
  if not isNonEmptyString(entry.char) or not isNonEmptyString(entry.region) then return nil, false end
  if not validRepairGroupAllocations() then return nil, false end
  local groupMail, groupMailState = repairGroupMailForEntry(entry)
  if groupMailState == "BLOCKED" then return nil, false end
  if groupMailState == "EXACT" then return reconcileRepairGroup(groupMail, entry) end
  if repairGroupOwnsEvidence(entry.key) then return nil, false end
  local hasItemID = isPositiveInteger(entry.itemID)
  -- A buyer invoice without its attachment item ID cannot authoritatively
  -- select an acquisition position. Keep the immutable ledger row visible for
  -- repair; exact name-only matches are still guesses and must not mutate cost.
  if not hasItemID then return nil, false end
  local repairGroup, repairGroupState = repairGroupForMail(entry)
  if repairGroupState == "BLOCKED" then return nil, false end
  if repairGroupState == "EXACT" then return reconcileRepairGroup(repairGroup, entry) end
  local existing = activeWithEvidence(entry.key)
  if existing then
    existing.itemName = existing.itemName or entry.itemName
    return existing, false
  end
  local resolved, resolvedIndex = pendingWithEvidence(entry.key)
  local function activeMatch(batch)
    if batch.mailEvidenceKey or batch.repairedPendingID ~= nil or batch.repairEvidenceKey ~= nil
        or not isPositiveInteger(batch.remainingQty)
        or not isExactInteger(batch.remainingTotal) then return false end
    return compatible(batch, entry)
  end
  local function pendingMatch(pending)
    if pending.mailEvidenceKey and pending.mailEvidenceKey ~= entry.key then return false end
    return compatiblePending(pending, entry)
  end


  local function promote(pending, pendingIndex)
    if not pending or not pendingIndex or not pendingMatch(pending) then return nil, false end
    for key, present in pairs(type(pending.evidenceKeys) == "table" and pending.evidenceKeys or {}) do
      if present and activeWithEvidence(key) then return nil, false end
    end
    if pending.mailEvidenceKey and pending.mailEvidenceKey ~= entry.key
        and activeWithEvidence(pending.mailEvidenceKey) then return nil, false end

    local wasLinked = (pending.evidenceKeys and pending.evidenceKeys[entry.key])
      or pending.mailEvidenceKey == entry.key
    local batch, isNew = GC.Acquisitions.Record({
      source = "auction_house", itemID = entry.itemID, positionKey = pending.positionKey,
      itemName = entry.itemName or pending.itemName, quantity = entry.qty, total = entry.total,
      acquiredAt = pending.completedAt, evidenceKey = entry.key,
      character = pending.character or entry.char, region = pending.region or entry.region,
    })
    if not batch or not isNew then return nil, false end
    if not wasLinked then
      -- Record could not discover this pending through the new mail key. Only
      -- now that the exact batch exists do we merge its attempt evidence and
      -- retire the pending row, preserving atomic failure semantics.
      for key, present in pairs(type(pending.evidenceKeys) == "table" and pending.evidenceKeys or {}) do
        if present then batch.evidenceKeys[key] = true end
      end
      if pending.mailEvidenceKey then batch.evidenceKeys[pending.mailEvidenceKey] = true end
      batch.positionKey = batch.positionKey or pending.positionKey
      batch.itemName = batch.itemName or pending.itemName
      batch.character = batch.character or pending.character
      batch.region = batch.region or pending.region
      batch.promotedPendingID = pending.id
      table.remove(db.acquisitionPending, pendingIndex)
    end
    batch.evidenceKeys[entry.key] = true
    batch.mailEvidenceKey = entry.key
    batch.itemName = batch.itemName or entry.itemName
    return batch, true
  end

  if resolved then return promote(resolved, resolvedIndex) end

  local batch = oldestCompatible(db.acquisitions, activeMatch)
  if batch then return attachMailEvidence(batch, entry), true end

  local pending = oldestCompatible(db.acquisitionPending, pendingMatch)
  if pending then
    for index, candidate in ipairs(db.acquisitionPending) do
      if candidate == pending then return promote(pending, index) end
    end
  end

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

function GC.Acquisitions.GetPending(context)
  if not db then return {} end
  if not context then return db.acquisitionPending end
  if not validContext(context) then return {} end
  local pending = {}
  for _, row in ipairs(db.acquisitionPending) do
    if row.character == context.char and row.region == context.region then pending[#pending + 1] = row end
  end
  return pending
end

function GC.Acquisitions.GetActivities(context)
  if not db or type(db.acquisitionActivity) ~= "table" then return {} end
  local activities = {}
  for scopeKey, activity in pairs(db.acquisitionActivity) do
    if validStoredActivity(scopeKey, activity) and (not context or (validContext(context)
        and activity.character == context.char and activity.region == context.region)) then
      activities[#activities + 1] = activity
    end
  end
  table.sort(activities, function(left, right) return (left.scopeKey or "") < (right.scopeKey or "") end)
  return activities
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

function GC.Acquisitions.Consume(positionKey, quantity, evidenceKey, at, context, prevalidatedPlan)
  if not db or type(positionKey) ~= "string" or not isPositiveInteger(quantity)
      or type(evidenceKey) ~= "string" or evidenceKey == "" or not isExactInteger(at)
      or not validContext(context) or db.acquisitionConsumptionEvidence[evidenceKey] then
    return nil
  end
  local eligible, byID = {}, {}
  for _, batch in ipairs(GC.Acquisitions.GetActive(context)) do
    if batch.positionKey == positionKey then
      eligible[#eligible + 1] = batch
      byID[batch.id] = batch
      if batch.consumedEvidenceKeys and batch.consumedEvidenceKeys[evidenceKey] then return nil end
    end
  end
  local plan = prevalidatedPlan or allocationFor(eligible, quantity)
  if not plan or plan.coverage ~= "COMPLETE" then return nil end

  local plannedQty, plannedCost, usedBatchIDs = 0, 0, {}
  local updates = {}
  for _, allocation in ipairs(plan.allocations) do
    local batch = byID[allocation.batchID]
    if usedBatchIDs[allocation.batchID] or not isPositiveInteger(allocation.quantity)
        or not isExactInteger(allocation.cost) then return nil end
    usedBatchIDs[allocation.batchID] = true
    local state = batch and copyBatchState(batch) or nil
    local taken = state and takeCost(state, allocation.quantity) or nil
    if taken ~= allocation.cost then return nil end
    plannedQty = safeAdd(plannedQty, allocation.quantity)
    plannedCost = safeAdd(plannedCost, allocation.cost)
    if not plannedQty or not plannedCost then return nil end
    updates[#updates + 1] = { batch = batch, state = state }
  end
  if plannedQty ~= quantity or plannedCost ~= plan.knownCost then return nil end
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
    cost = plannedCost,
    at = at,
    allocations = plan.allocations,
  }
end
