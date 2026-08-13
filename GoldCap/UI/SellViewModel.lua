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

function GC.SellViewModel.Filter(positions, mode)
  local filtered = {}
  for _, position in ipairs(positions or {}) do
    local include = mode == "all" or mode == nil
    if mode == "missing_cost" then
      include = position.coverage == "PARTIAL" or position.coverage == "UNKNOWN"
    elseif SOURCE_LABELS[mode] then
      include = type(position.sources) == "table" and (position.sources[mode] or 0) > 0
    end
    if include then filtered[#filtered + 1] = position end
  end
  return filtered
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
  if not position or position.coverage ~= "COMPLETE" then return "Set cost" end
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
    batch.evidence = batch.evidence or batch.sniperEvidenceKey or batch.mailEvidenceKey or "Recorded"
  end
  return {
    positionKey = position.positionKey, coverage = position.coverage, batches = batches,
    ownedLots = copy(position.ownedLots), quoteAge = position.quoteAge, ahead = position.ahead,
    sold = position.outlook and position.outlook.sold, days = position.outlook and position.outlook.days,
    recommendation = position.recommendation or position.status, note = "FIFO allocations",
  }
end
