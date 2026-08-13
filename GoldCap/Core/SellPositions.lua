local _, GC = ...

GC.SellPositions = {}

local MAX_EXACT = 9007199254740991
local QUOTE_MAX_AGE = 10

local function exact(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

local function positive(value) return exact(value) and value > 0 end

local function exactSigned(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value) and value >= -MAX_EXACT and value <= MAX_EXACT
end

local function add(left, right)
  if not exact(left) or not exact(right) or left > MAX_EXACT - right then return nil end
  return left + right
end

-- The acquisition store's accounting has the same exact-number constraint.  Keep resale
-- projections inside that boundary too: this computes floor(left * right / denominator)
-- without ever constructing an unsafe product.
local function mulDivFloor(left, right, denominator)
  if not exact(left) or not exact(right) or not positive(denominator) then return nil end
  local whole = math.floor(left / denominator)
  local remainder = left - whole * denominator
  local bits, quotient, current = {}, 0, 0
  while right > 0 do
    bits[#bits + 1] = right % 2
    right = math.floor(right / 2)
  end
  local function addModulo(value)
    local untilWrap = denominator - value
    if current >= untilWrap then current = current - untilWrap return 1 end
    current = current + value
    return 0
  end
  for i = #bits, 1, -1 do
    quotient = add(quotient, quotient)
    if not quotient then return nil end
    local carry = addModulo(current)
    if bits[i] == 1 then
      quotient = add(quotient, whole)
      if not quotient then return nil end
      carry = carry + addModulo(remainder)
    end
    quotient = add(quotient, carry)
    if not quotient then return nil end
  end
  return quotient
end

local function valueFor(quantity, unit)
  return mulDivFloor(quantity, unit, 1)
end

local function netFor(quantity, unit)
  return mulDivFloor(valueFor(quantity, unit), 95, 100)
end

local function itemKeyFor(auction)
  return auction and auction.itemKey
end

local function keyForLot(auction)
  local itemID = auction and (auction.itemID or (auction.itemKey and auction.itemKey.itemID))
  local isCommodity = auction and auction.isCommodity
  if not positive(itemID) then return nil end
  return GC.Acquisitions.PositionKey(itemID, itemKeyFor(auction), isCommodity), itemID, isCommodity
end

local function lotUnit(auction)
  if positive(auction.unitPrice) then return auction.unitPrice end
  local qty = positive(auction.quantity) and auction.quantity or 1
  if positive(auction.buyoutAmount) then return math.floor(auction.buyoutAmount / qty) end
  return nil
end

function GC.SellPositions.NormalizeOwnedLots(auctionInfos, seenAt)
  local lots = {}
  for _, auction in ipairs(auctionInfos or {}) do
    local positionKey, itemID, isCommodity = keyForLot(auction)
    local quantity = positive(auction.quantity) and auction.quantity or 1
    local unitPrice = lotUnit(auction)
    if positionKey and positive(unitPrice) and positive(auction.auctionID) and exact(seenAt or 0) then
      lots[#lots + 1] = { positionKey = positionKey, itemID = itemID, quantity = quantity,
        unitPrice = unitPrice, auctionID = auction.auctionID, firstSeenAt = seenAt or 0,
        isCommodity = isCommodity == true }
    end
  end
  return lots
end

local function quoteInfo(quotes, itemID, now)
  local quote = GC.QuoteCache.Latest(quotes, itemID)
  if type(quote) == "number" and positive(quote) then
    return quote, quote, nil
  end
  if type(quote) ~= "table" or not positive(quote.unit) then return nil, nil, nil end
  local age = GC.QuoteCache.Age(quotes, itemID, now)
  local freshQuote = GC.QuoteCache.Fresh(quotes, itemID, now)
  local fresh = freshQuote == quote and quote.stale ~= true and (quote.fresh == true
    or (age ~= nil and age <= QUOTE_MAX_AGE))
  return fresh and quote.unit or nil, quote.unit, age
end

local function freshUnit(freshQuote)
  if type(freshQuote) == "number" and positive(freshQuote) then return freshQuote end
  if type(freshQuote) ~= "table" or not positive(freshQuote.unit) then return nil, "missing_quote" end
  if freshQuote.stale == true or freshQuote.fresh == false or freshQuote.at ~= nil then
    return nil, "stale_quote"
  end
  if freshQuote.fresh == true then return freshQuote.unit end
  return nil, "missing_quote"
end

local function compatibleBatch(batch, context)
  return type(batch) == "table" and batch.character == context.char and batch.region == context.region
    and positive(batch.itemID) and positive(batch.remainingQty) and exact(batch.remainingTotal)
end

local function stableLotOrder(left, right)
  local leftSeenAt, rightSeenAt = left.firstSeenAt or 0, right.firstSeenAt or 0
  if leftSeenAt ~= rightSeenAt then return leftSeenAt < rightSeenAt end
  return left.auctionID < right.auctionID
end

local function stablePositionOrder(left, right)
  if left.scopeKey ~= right.scopeKey then return left.scopeKey < right.scopeKey end
  return left.positionKey < right.positionKey
end

local function positionFor(positions, key, itemID, context)
  local position = positions[key]
  if position then return position end
  position = { itemID = itemID, positionKey = key,
    scopeKey = GC.Acquisitions.ScopeKey(key, context), character = context.char, region = context.region,
    batches = {}, sources = {}, trackedQty = 0, listedQty = 0, exposureQty = 0,
    allocations = {}, knownQty = 0, knownCost = 0, coverage = "UNKNOWN", ownedLots = {},
    listedValue = 0, freshMarketUnit = nil, displayMarketUnit = nil, quoteAge = nil,
    projectedNet = nil, profit = nil, status = "UNLISTED", ahead = nil, outlook = nil }
  positions[key] = position
  return position
end

local function uniqueVariants(batches, ownedLots)
  local variants = {}
  for _, batch in ipairs(batches) do
    if type(batch.positionKey) == "string" then variants[batch.positionKey] = true end
  end
  for _, ownedLot in ipairs(ownedLots) do
    if type(ownedLot.positionKey) == "string" then variants[ownedLot.positionKey] = true end
  end
  local only, count
  for key in pairs(variants) do only, count = key, (count or 0) + 1 end
  return count == 1 and only or nil
end

local function addBatch(position, batch)
  position.batches[#position.batches + 1] = batch
  local trackedQty = add(position.trackedQty, batch.remainingQty)
  local source = batch.source or "unknown"
  local sourceQty = add(position.sources[source] or 0, batch.remainingQty)
  if not trackedQty or not sourceQty then
    position.invalid = true
    position.trackedQty, position.sources[source] = nil, nil
    return
  end
  position.trackedQty, position.sources[source] = trackedQty, sourceQty
end

local function addLot(position, ownedLot)
  position.ownedLots[#position.ownedLots + 1] = ownedLot
  local listedQty = add(position.listedQty, ownedLot.quantity)
  local value = valueFor(ownedLot.quantity, ownedLot.unitPrice)
  local listedValue = value and add(position.listedValue, value)
  if not listedQty or not listedValue then
    position.invalid = true
    position.listedQty, position.listedValue = nil, nil
    return
  end
  position.listedQty, position.listedValue = listedQty, listedValue
end

local function decoratePosition(position, quotes, statsByItemID, now)
  table.sort(position.ownedLots, stableLotOrder)
  local fresh, display, age = quoteInfo(quotes, position.itemID, now)
  position.freshMarketUnit, position.displayMarketUnit, position.quoteAge = fresh, display, age
  if position.invalid then
    position.exposureQty, position.allocations, position.knownQty, position.knownCost = nil, {}, 0, 0
    position.coverage, position.projectedNet, position.profit = "UNKNOWN", nil, nil
    position.status, position.ahead, position.outlook = "NO_COST", nil, nil
    return
  end
  position.exposureQty = position.listedQty > 0 and position.listedQty or position.trackedQty
  local allocation = position.exposureQty > 0 and GC.Acquisitions.Allocate(position.batches, position.exposureQty)
  if allocation then
    position.allocations, position.knownQty, position.knownCost = allocation.allocations,
      allocation.knownQty, allocation.knownCost
    position.coverage = allocation.knownQty == 0 and "UNKNOWN"
      or allocation.knownQty < position.exposureQty and "PARTIAL" or "COMPLETE"
  end
  local projected = 0
  if position.listedQty > 0 then
    for _, ownedLot in ipairs(position.ownedLots) do
      local unit = fresh and math.min(ownedLot.unitPrice, fresh) or ownedLot.unitPrice
      local net = netFor(ownedLot.quantity, unit)
      projected = net and add(projected, net) or nil
      if not projected then break end
    end
  elseif fresh then
    projected = netFor(position.exposureQty, fresh)
  else
    projected = nil
  end
  position.projectedNet = projected
  if position.coverage == "COMPLETE" and projected ~= nil then position.profit = projected - position.knownCost end

  local cheapestListedUnit
  for _, ownedLot in ipairs(position.ownedLots) do
    if not cheapestListedUnit or ownedLot.unitPrice < cheapestListedUnit then cheapestListedUnit = ownedLot.unitPrice end
  end
  if position.coverage ~= "COMPLETE" then
    position.status = "NO_COST"
  elseif position.listedQty > 0 and fresh and cheapestListedUnit > fresh then
    position.status = "UNDERCUT"
  elseif position.listedQty > 0 then
    position.status = "LISTED"
  else
    position.status = "UNLISTED"
  end
  local levels = type(quotes and quotes[position.itemID]) == "table" and quotes[position.itemID].levels or nil
  position.ahead = GC.Flips.DepthBelow(levels, position.ownedLots[1] and position.ownedLots[1].unitPrice)
  local stats = statsByItemID and statsByItemID[position.itemID]
  position.outlook = GC.Flips.SellOutlook({ ahead = position.ahead, qty = position.exposureQty,
    sold = stats and stats.sold, trend = stats and stats.trend })

  local skipped = 0
  for _, ownedLot in ipairs(position.ownedLots) do
    ownedLot.allocation = GC.Acquisitions.AllocateRange(position.batches, skipped, ownedLot.quantity)
    skipped = add(skipped, ownedLot.quantity) or skipped
  end
end

function GC.SellPositions.Build(args)
  args = args or {}
  local context = args.context
  if type(context) ~= "table" or type(context.char) ~= "string" or context.char == ""
      or type(context.region) ~= "string" or context.region == "" then return {} end
  local scoped, lotsByItem, positions = {}, {}, {}
  for _, batch in ipairs(args.acquisitions or {}) do
    if compatibleBatch(batch, context) then
      scoped[batch.itemID] = scoped[batch.itemID] or {}
      scoped[batch.itemID][#scoped[batch.itemID] + 1] = batch
    end
  end
  for _, ownedLot in ipairs(args.ownedLots or {}) do
    local positionKey, itemID = ownedLot.positionKey, ownedLot.itemID
    if type(positionKey) == "string" and positive(itemID) and positive(ownedLot.quantity)
        and positive(ownedLot.unitPrice) and positive(ownedLot.auctionID)
        and exact(ownedLot.firstSeenAt or 0)
        and (not ownedLot.character or (ownedLot.character == context.char and ownedLot.region == context.region)) then
      local lot = {}
      for key, value in pairs(ownedLot) do lot[key] = value end
      lot.firstSeenAt = ownedLot.firstSeenAt or 0
      lotsByItem[itemID] = lotsByItem[itemID] or {}
      lotsByItem[itemID][#lotsByItem[itemID] + 1] = lot
      addLot(positionFor(positions, positionKey, itemID, context), lot)
    end
  end
  for itemID, batches in pairs(scoped) do
    local target = uniqueVariants(batches, lotsByItem[itemID] or {})
    for _, batch in ipairs(batches) do
      local positionKey = batch.positionKey or target
      if positionKey then addBatch(positionFor(positions, positionKey, itemID, context), batch) end
    end
  end
  local result = {}
  for _, position in pairs(positions) do
    decoratePosition(position, args.quotes or {}, args.statsByItemID or {}, args.now)
    result[#result + 1] = position
  end
  table.sort(result, stablePositionOrder)
  return result
end

function GC.SellPositions.BuildPostPlan(position, bagState, freshQuote)
  local unit, quoteReason = freshUnit(freshQuote)
  if not unit then return nil, quoteReason end
  if type(position) ~= "table" or position.invalid or not positive(position.trackedQty) then return nil, "no_tracked_quantity" end
  if type(bagState) ~= "table" or bagState.itemID ~= position.itemID or not positive(bagState.exactQty) then
    return nil, "missing_bag_quantity"
  end
  if type(position.positionKey) == "string" and position.positionKey:match("^item:")
      and bagState.positionKey ~= position.positionKey then
    return nil, "ambiguous_variant"
  end
  local unlisted = position.trackedQty - position.listedQty
  local quantity = math.min(math.max(0, unlisted), bagState.exactQty)
  if quantity <= 0 then return nil, "no_unlisted_quantity" end
  local allocation = GC.Acquisitions.AllocateRange(position.batches, position.listedQty, quantity)
  if not allocation or allocation.coverage ~= "COMPLETE" then return nil, "incomplete_cost" end
  return { positionKey = position.positionKey, scopeKey = position.scopeKey, itemID = position.itemID,
    quantity = quantity, cost = allocation.knownCost, allocations = allocation.allocations, unitPrice = unit }
end

function GC.SellPositions.BuildRepostPlan(position, auctionID, freshQuote)
  local unit, quoteReason = freshUnit(freshQuote)
  if not unit then return nil, quoteReason end
  if type(position) ~= "table" or position.invalid then return nil, "missing_position" end
  for _, ownedLot in ipairs(position.ownedLots or {}) do
    if ownedLot.auctionID == auctionID then
      if not ownedLot.allocation or ownedLot.allocation.coverage ~= "COMPLETE" then return nil, "incomplete_cost" end
      return { positionKey = position.positionKey, scopeKey = position.scopeKey, itemID = position.itemID,
        auctionID = ownedLot.auctionID, quantity = ownedLot.quantity, cost = ownedLot.allocation.knownCost,
        allocations = ownedLot.allocation.allocations, unitPrice = unit }
    end
  end
  return nil, "unknown_auction"
end

function GC.SellPositions.Summary(positions)
  local invested, projected = 0, 0
  for _, position in ipairs(positions or {}) do
    if position.coverage ~= "COMPLETE" then
      return { invested = nil, projected = nil, profit = nil }
    end
    invested = add(invested, position.knownCost)
    if not invested then return { invested = nil, projected = nil, profit = nil } end
    if projected == nil or position.projectedNet == nil then projected = nil
    else projected = add(projected, position.projectedNet) end
  end
  if projected == nil then return { invested = invested, projected = nil, profit = nil } end
  local profit = projected - invested
  if not exactSigned(profit) then return { invested = nil, projected = nil, profit = nil } end
  return { invested = invested, projected = projected, profit = profit }
end
