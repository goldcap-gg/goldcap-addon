local _, GC = ...

GC.SellViewModel = {}

local SOURCE_LABELS = { goldcap = "GC", auction_house = "AH", manual = "MANUAL" }
local SOURCE_ORDER = { "goldcap", "auction_house", "manual" }

local function copy(values)
  local result = {}
  for i, value in ipairs(values or {}) do
    if type(value) == "table" then
      local clone = {}
      for key, field in pairs(value) do clone[key] = field end
      result[i] = clone
    else
      result[i] = value
    end
  end
  return result
end

local function evidenceLabel(batch)
  if batch.source == "manual" then return "manual" end
  if type(batch.mailEvidenceKey) == "string" and batch.mailEvidenceKey ~= "" then return "mail-confirmed" end
  local captured
  for key, present in pairs(type(batch.evidenceKeys) == "table" and batch.evidenceKeys or {}) do
    if present and type(key) == "string" then
      if key:match("^mail:") then return "mail-confirmed" end
      captured = true
    end
  end
  if type(batch.sniperEvidenceKey) == "string" and batch.sniperEvidenceKey ~= "" or captured then
    return "captured"
  end
  if batch.evidence == "captured" or batch.evidence == "mail-confirmed"
      or batch.evidence == "manual" or batch.evidence == "unknown evidence" then
    return batch.evidence
  end
  return "unknown evidence"
end

function GC.SellViewModel.Filter(positions, mode)
  local filtered = {}
  for _, position in ipairs(positions or {}) do
    local include = mode == "all" or mode == nil
    if mode == "missing_cost" then
      include = position.coverage == "PARTIAL" or position.coverage == "UNKNOWN"
    elseif mode == "sellable" then
      include = type(position.bagQty) == "number" and position.bagQty > 0
    elseif mode == "listed" then
      include = type(position.listedQty) == "number" and position.listedQty > 0
    elseif SOURCE_LABELS[mode] then
      include = type(position.sources) == "table" and (position.sources[mode] or 0) > 0
    end
    if include then filtered[#filtered + 1] = position end
  end
  return filtered
end

-- Reading order, not storage order. SellPositions.Build sorts by scope and
-- position key, which is stable and completely meaningless to a seller: it put
-- an item you can list right now below thirty rows of finished business.
--
-- Rank, then value within rank:
--   0  in your bags AND priced -- one click from being listed
--   1  in your bags, price not in yet
--   2  everything else, in the order Build produced it
--
-- Deliberately only three ranks. Sorting the remainder by how much is listed or
-- how recently it sold is a preference, not an answer, and every reshuffle of
-- rows a player is not acting on costs them their place on the screen.
local function rankOf(position)
  local inBags = type(position.bagQty) == "number" and position.bagQty > 0
  if inBags then return position.freshMarketUnit and 0 or 1 end
  -- Listed rows above stockless ghosts: a position with nothing in the bags AND nothing
  -- listed is pure bookkeeping -- its stock is in the mail, the bank, or on another
  -- character -- and sitting between live listings it read as a broken row.
  local listed = type(position.listedQty) == "number" and position.listedQty > 0
  return listed and 2 or 3
end

local function weightOf(position)
  local unit = position.freshMarketUnit or position.displayMarketUnit
  local qty = (type(position.bagQty) == "number" and position.bagQty or 0)
  if unit and qty > 0 then return unit * qty end
  return 0
end

function GC.SellViewModel.Order(positions)
  local ordered, rank, weight = {}, {}, {}
  for index, position in ipairs(positions or {}) do
    ordered[index] = position
    rank[position], weight[position] = rankOf(position), weightOf(position)
  end
  -- Ties fall back to the incoming order, which Build already made stable, so a
  -- re-render never reshuffles rows under the cursor.
  local original = {}
  for index, position in ipairs(ordered) do original[position] = index end
  table.sort(ordered, function(left, right)
    if rank[left] ~= rank[right] then return rank[left] < rank[right] end
    if weight[left] ~= weight[right] then return weight[left] > weight[right] end
    return original[left] < original[right]
  end)
  return ordered
end

function GC.SellViewModel.SourceText(position)
  local parts, sources = {}, position and position.sources or {}
  for _, source in ipairs(SOURCE_ORDER) do
    local quantity = sources[source]
    if type(quantity) == "number" and quantity > 0 then
      parts[#parts + 1] = ("%s ×%d"):format(SOURCE_LABELS[source], quantity)
    end
  end
  return #parts > 0 and table.concat(parts, " · ") or "Missing cost"
end

function GC.SellViewModel.CostText(position)
  if not position then return "Unknown" end
  if position.unresolved then
    return type(position.knownCost) == "number" and position.knownCost > 0
      and (tostring(position.knownCost) .. " · identity unresolved") or "Unknown"
  end
  if position.coverage ~= "COMPLETE" then
    local known = type(position.knownCost) == "number" and position.knownCost or 0
    local knownQty = type(position.knownQty) == "number" and position.knownQty or 0
    local exposureQty = type(position.exposureQty) == "number" and position.exposureQty or 0
    return ("%d · %d/%d covered"):format(known, knownQty, exposureQty)
  end
  return position.knownCost
end

function GC.SellViewModel.ProfitText(position)
  if not position or position.profit == nil then return "Unknown" end
  return position.profit
end

function GC.SellViewModel.SummaryText(summary)
  summary = summary or {}
  local partial = summary.partialCount or 0
  local unknown = summary.unknownCount or 0
  local profit = summary.profit
  if profit == nil then
    local suffix = {}
    if partial > 0 then suffix[#suffix + 1] = ("%d partial"):format(partial) end
    if unknown > 0 then suffix[#suffix + 1] = ("%d missing"):format(unknown) end
    profit = "Unknown" .. (#suffix > 0 and (" · " .. table.concat(suffix, " · ")) or "")
  end
  return { knownCost = summary.knownCost, listedValue = summary.listedValue, profit = profit }
end

function GC.SellViewModel.Expansion(position)
  position = position or {}
  local marketFresh = position.displayMarketUnit ~= nil and position.freshMarketUnit ~= nil
  local marketStale = position.displayMarketUnit ~= nil and not marketFresh
  local marketState = marketFresh and "fresh" or marketStale and "stale" or "unavailable"
  local allocated = {}
  for _, allocation in ipairs(position.allocations or {}) do
    allocated[allocation.batchID] = (allocated[allocation.batchID] or 0) + (allocation.quantity or 0)
  end
  local batches = copy(position.batches)
  for _, batch in ipairs(batches) do
    batch.originalQty = batch.originalQty or batch.quantity
    batch.allocatedQty = batch.allocatedQty or allocated[batch.id] or (batch.allocation and batch.allocation.quantity) or 0
    batch.unitCost = batch.unitCost or (batch.remainingQty and batch.remainingQty > 0
      and math.floor((batch.remainingTotal or 0) / batch.remainingQty))
    batch.totalCost = batch.totalCost or batch.remainingTotal
    batch.evidence = evidenceLabel(batch)
  end
  -- Two clicks of the same buyout are one fact about cost, not two lines of history: adjacent
  -- batches agreeing on price, source and evidence collapse into one entry carrying a
  -- `purchases` count and the run's date range. Adjacent only -- merging across a
  -- different-priced purchase would re-order the oldest-first story the group hint promises.
  -- Evidence is part of the key on purpose: a confirmed invoice never averages into a guess.
  local collapsed = {}
  for _, batch in ipairs(batches) do
    local last = collapsed[#collapsed]
    if last and type(batch.unitCost) == "number" and last.unitCost == batch.unitCost
        and last.source == batch.source and last.evidence == batch.evidence then
      if not last.purchases then
        local at = type(last.acquiredAt) == "number" and last.acquiredAt or nil
        last = { source = last.source, evidence = last.evidence, unitCost = last.unitCost,
          purchases = 1, originalQty = last.originalQty or 0, remainingQty = last.remainingQty or 0,
          allocatedQty = last.allocatedQty or 0, totalCost = last.totalCost,
          acquiredAtFirst = at, acquiredAtLast = at }
        collapsed[#collapsed] = last
      end
      last.purchases = last.purchases + 1
      last.originalQty = last.originalQty + (batch.originalQty or 0)
      last.remainingQty = last.remainingQty + (batch.remainingQty or 0)
      last.allocatedQty = last.allocatedQty + (batch.allocatedQty or 0)
      last.totalCost = last.totalCost and batch.totalCost and (last.totalCost + batch.totalCost) or nil
      local at = type(batch.acquiredAt) == "number" and batch.acquiredAt or nil
      if at then
        if not last.acquiredAtFirst or at < last.acquiredAtFirst then last.acquiredAtFirst = at end
        if not last.acquiredAtLast or at > last.acquiredAtLast then last.acquiredAtLast = at end
      end
    else
      collapsed[#collapsed + 1] = batch
    end
  end
  batches = collapsed
  local facts = {}
  if position.facts and position.facts.pendingPurchase then facts[#facts + 1] = "purchase pending exact cost" end
  if position.facts and position.facts.undercut then facts[#facts + 1] = "undercut" end
  if position.facts and position.facts.soldPending then facts[#facts + 1] = "sale proceeds pending" end
  if position.unresolvedKind == "paid_sale" then facts[#facts + 1] = "paid sale unresolved" end
  if position.unresolvedKind == "ambiguous_sale" then facts[#facts + 1] = "sale name ambiguous" end
  if position.unresolvedKind == "unassigned_acquisition" then facts[#facts + 1] = "item variant unresolved" end
  if position.unresolvedKind == "pending_purchase" then facts[#facts + 1] = "purchase identity unresolved" end
  return {
    positionKey = position.positionKey, coverage = position.coverage, batches = batches,
    ownedLots = copy(position.ownedLots), displayMarketUnit = position.displayMarketUnit,
    marketState = marketState, marketFresh = marketFresh, marketStale = marketStale,
    quoteAge = position.quoteAge, ahead = position.ahead,
    sold = position.soldPerDay, days = position.outlook and position.outlook.days,
    recommendation = position.recommendation, note = "FIFO allocations",
    coverageText = ("%d/%d covered"):format(position.knownQty or 0, position.exposureQty or 0),
    pendingAcquisitions = copy(position.pendingAcquisitions),
    sellerEvidence = copy(position.sellerEvidence), facts = position.facts,
    factsText = #facts > 0 and table.concat(facts, " · ") or nil,
  }
end
