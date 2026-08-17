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

-- The unit price of one of the player's own live auctions.
--
-- This divided buyoutAmount by the stack size unconditionally, which is right
-- for an item auction and wrong for a commodity -- and every reagent, ore, herb
-- and flask a seller posts is a commodity. Five Arcane Crystals posted at 92g12s
-- each were reported as listed at 18g42s40c, because 921200/5 = 184240, and
-- every number downstream inherited it: the projected proceeds, and therefore a
-- profit of -52g49s72c on a position that was actually making 17g51s a unit.
--
-- Commodities are priced per unit throughout this API -- PostCommodity takes a
-- unit price, GetCommoditySearchResultInfo returns one -- and buyoutAmount
-- follows suit. An item auction carries the total for the whole stack.
--
-- Fails toward NOT dividing when the kind is unknown. GetOwnedAuctions does not
-- report isCommodity itself (see classifyOwnedAuctions in UI/SellFrame.lua), so
-- unknown is a real state, and for a genuine item auction the divisor is almost
-- always 1 anyway -- in retail, anything that stacks IS a commodity. Dividing on
-- a guess understates the price, which reads as selling far below market and
-- would have the player cancel a perfectly good listing.
local function lotUnit(auction)
  if positive(auction.unitPrice) then return auction.unitPrice end
  if not positive(auction.buyoutAmount) then return nil end
  if auction.isCommodity == false and positive(auction.quantity) and auction.quantity > 1 then
    return math.floor(auction.buyoutAmount / auction.quantity)
  end
  return auction.buyoutAmount
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

local function quoteInfo(quotes, itemID, now, maxAge)
  local quote = GC.QuoteCache.Latest(quotes, itemID)
  if type(quote) == "number" and positive(quote) then
    return quote, quote, nil
  end
  if type(quote) ~= "table" or not positive(quote.unit) then return nil, nil, nil end
  local age = GC.QuoteCache.Age(quotes, itemID, now)
  local freshQuote = GC.QuoteCache.Fresh(quotes, itemID, now, maxAge)
  local fresh = freshQuote == quote and quote.stale ~= true and (quote.fresh == true
    or (age ~= nil and age <= (maxAge or QUOTE_MAX_AGE)))
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
  local leftScope = left.scopeKey or left.unresolvedKey or ""
  local rightScope = right.scopeKey or right.unresolvedKey or ""
  if leftScope ~= rightScope then return leftScope < rightScope end
  return (left.positionKey or left.unresolvedKey or "") < (right.positionKey or right.unresolvedKey or "")
end

local function positionFor(positions, key, itemID, context)
  local position = positions[key]
  if position then return position end
  position = { itemID = itemID, positionKey = key,
    scopeKey = GC.Acquisitions.ScopeKey(key, context), character = context.char, region = context.region,
    batches = {}, sources = {}, trackedQty = 0, listedQty = 0, exposureQty = 0,
    allocations = {}, knownQty = 0, knownCost = 0, coverage = "UNKNOWN", ownedLots = {},
    bagQty = 0, bagStacks = {},
    listedValue = 0, freshMarketUnit = nil, displayMarketUnit = nil, quoteAge = nil,
    projectedNet = nil, profit = nil, status = "UNLISTED", ahead = nil, outlook = nil,
    pendingAcquisitions = {}, pendingQty = 0, sellerEvidence = {},
    facts = { soldPending = false, pendingPurchase = false, undercut = false } }
  positions[key] = position
  return position
end

-- Whether a batch may speak about what this item IS, as opposed to what is still held.
--
-- Deliberately weaker than compatibleBatch: it does NOT require a remaining quantity. Selling
-- your last unit tells you nothing new about whether the item trades as a commodity, and the
-- two questions -- "what do I still own" and "what is this item's auction identity" -- were
-- being answered from the same filtered list. So the moment an item's last KEYED batch reached
-- zero, every keyless batch for it was orphaned into its own REPAIR_IDENTITY row: fourteen rows
-- for one herb, with no cost, no market and no Post button, while an identical herb with a
-- single leftover unit collapsed into one correct row. Identity is not consumed by selling.
local function identityBatch(batch, context)
  return type(batch) == "table" and batch.character == context.char and batch.region == context.region
    and positive(batch.itemID) and type(batch.positionKey) == "string" and batch.positionKey ~= ""
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
  position.itemName = position.itemName or batch.itemName
end

local function addPending(position, pending)
  position.pendingAcquisitions[#position.pendingAcquisitions + 1] = pending
  position.facts.pendingPurchase = true
  position.itemName = position.itemName or pending.itemName
  if pending.quantity ~= nil then
    local pendingQty = add(position.pendingQty, pending.quantity)
    local sourceQty = add(position.sources.auction_house or 0, pending.quantity)
    if not pendingQty or not sourceQty then
      position.invalid = true
      position.pendingQty, position.sources.auction_house = nil, nil
      return
    end
    position.pendingQty, position.sources.auction_house = pendingQty, sourceQty
  end
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

local function decoratePosition(position, quotes, statsByItemID, now, quoteMaxAge)
  table.sort(position.ownedLots, stableLotOrder)
  local fresh, display, age = quoteInfo(quotes, position.itemID, now, quoteMaxAge)
  position.freshMarketUnit, position.displayMarketUnit, position.quoteAge = fresh, display, age
  if position.invalid then
    position.exposureQty, position.allocations, position.knownQty, position.knownCost = nil, {}, 0, 0
    position.coverage, position.projectedNet, position.profit = "UNKNOWN", nil, nil
    position.status, position.ahead, position.outlook, position.recommendation = "NO_COST", nil, nil, nil
    return
  end
  local accountedExposure = position.listedQty > 0 and position.listedQty or position.trackedQty
  position.accountedExposureQty = accountedExposure
  position.exposureQty = add(accountedExposure, position.pendingQty or 0)
  if not position.exposureQty then
    position.invalid = true
    position.exposureQty, position.allocations, position.knownQty, position.knownCost = nil, {}, 0, 0
    position.coverage, position.projectedNet, position.profit = "UNKNOWN", nil, nil
    position.status, position.ahead, position.outlook, position.recommendation = "NO_COST", nil, nil, nil
    return
  end
  local allocation = position.exposureQty > 0 and GC.Acquisitions.Allocate(position.batches, position.exposureQty)
  if allocation then
    position.allocations, position.knownQty, position.knownCost = allocation.allocations,
      allocation.knownQty, allocation.knownCost
    position.coverage = allocation.knownQty == 0 and "UNKNOWN"
      or allocation.knownQty < position.exposureQty and "PARTIAL" or "COMPLETE"
  end
  local projected
  if position.listedQty > 0 then
    local gross = 0
    for _, ownedLot in ipairs(position.ownedLots) do
      local unit = fresh and math.min(ownedLot.unitPrice, fresh) or ownedLot.unitPrice
      local value = valueFor(ownedLot.quantity, unit)
      gross = value and add(gross, value) or nil
      if not gross then break end
    end
    projected = gross and mulDivFloor(gross, 95, 100) or nil
  elseif fresh then
    projected = netFor(position.exposureQty, fresh)
  else
    projected = nil
  end
  position.projectedNet = projected
  if position.coverage == "COMPLETE" and projected ~= nil then position.profit = projected - position.knownCost end

  local levels = type(quotes and quotes[position.itemID]) == "table" and quotes[position.itemID].levels or nil
  local marketStats = statsByItemID and statsByItemID[position.itemID]
  position.marketValue = marketStats and marketStats.mv or nil
  position.soldPerDay = marketStats and marketStats.sold or nil
  -- The imported market value. Fetched all along for its sold/day and trend, and
  -- its price ignored -- which is how a single cheap lot became both the price
  -- GoldCap recommended and the price Post listed at. It is not the price; it is
  -- the sanity check on the price. See GC.Flips.PostFloor.
  position.postFloor = GC.Flips.PostFloor({ marketUnit = fresh, mv = position.marketValue,
    levels = levels, sold = position.soldPerDay,
    heldQty = (position.bagQty or 0) + (position.listedQty or 0) })

  local cheapestListedUnit
  for _, ownedLot in ipairs(position.ownedLots) do
    if not cheapestListedUnit or ownedLot.unitPrice < cheapestListedUnit then cheapestListedUnit = ownedLot.unitPrice end
  end
  position.facts.undercut = position.listedQty > 0 and fresh ~= nil
    and cheapestListedUnit ~= nil and cheapestListedUnit > fresh
  -- The expensive direction, which had no name and no warning until it cost
  -- real gold twice: your own listing sits far BELOW what the item is worth.
  -- `undercut` above is the cheap direction -- somebody else is under you, and
  -- the worst case is that you wait. This one is money leaving, and it happens
  -- silently, because a listing posted against a thin cheap lot looks perfectly
  -- normal until that lot clears and the book springs back.
  --
  -- Measured against the better of two references, because they fail in
  -- opposite directions. The live competing ask is hard evidence -- if others
  -- are asking 92g and you are asking 18g, you are giving it away, full stop --
  -- but it collapses to your own price when you are the only seller, which is
  -- exactly the Sanguithorn shape. The imported market value covers that, and is
  -- in turn the one that can be stale. Taking the higher of the two means an
  -- alarm needs only one of them to be right.
  local reference = math.max(fresh or 0, position.marketValue or 0)
  local valueFloor = reference > 0
    and math.floor(reference * (GC.Flips.UNDERPRICE_FLOOR or 0.75)) or nil
  position.facts.underpriced = position.listedQty > 0 and valueFloor ~= nil
    and cheapestListedUnit ~= nil and cheapestListedUnit < valueFloor
  position.underpricedUnit = position.facts.underpriced and cheapestListedUnit or nil
  if position.coverage ~= "COMPLETE" then
    position.status = position.coverage == "PARTIAL" and "PARTIAL_COST" or "NO_COST"
  elseif position.facts.undercut then
    position.status = "UNDERCUT"
  elseif position.facts.soldPending then
    position.status = "SOLD_PENDING"
  elseif position.listedQty > 0 then
    position.status = "LISTED"
  else
    position.status = "UNLISTED"
  end
  position.ahead = GC.Flips.DepthBelow(levels, position.ownedLots[1] and position.ownedLots[1].unitPrice)
  position.outlook = GC.Flips.SellOutlook({ ahead = position.ahead, qty = position.exposureQty,
    sold = marketStats and marketStats.sold, trend = marketStats and marketStats.trend })
  if position.coverage == "COMPLETE" and position.listedQty > 0 then
    position.recommendation = GC.Flips.RepostAdvice({ paidUnit = position.knownCost and math.floor(position.knownCost / position.exposureQty),
      marketUnit = fresh, levels = levels, sold = position.soldPerDay, qty = position.exposureQty,
      floor = position.postFloor })
  elseif position.coverage == "COMPLETE" then
    position.recommendation = GC.Flips.RecommendPost(position.knownCost and math.floor(position.knownCost / position.exposureQty),
      fresh, position.marketValue, { levels = levels, sold = position.soldPerDay, floor = position.postFloor })
  elseif positive(position.bagQty) and fresh then
    -- Stock GoldCap never bought still deserves an answer to "what should I list this at".
    -- No cost basis means no breakeven and no belowCost warning -- RecommendPost already
    -- degrades to exactly that on a nil paidUnit, rather than inventing a cost from the market.
    position.recommendation = GC.Flips.RecommendPost(nil, fresh, position.marketValue,
      { levels = levels, sold = position.soldPerDay, floor = position.postFloor })
  else
    position.recommendation = nil
  end

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
  local scoped, lotsByItem, positions, unresolvedRows = {}, {}, {}, {}
  -- `known` is the identity evidence pool: every batch of this item that ever carried a key,
  -- including ones sold down to nothing. `scoped` stays what it was -- only batches with stock
  -- left -- because that is what the accounting below is about. See identityBatch.
  local known = {}
  -- Supplied separately because the caller's own batch list is already filtered to what is
  -- still held (GC.Acquisitions.GetActive), so a spent batch's key never arrives by that route
  -- -- which is exactly how the evidence went missing. Callers that hand over raw batches are
  -- still covered by the identityBatch pass below.
  for _, record in ipairs(args.identityEvidence or {}) do
    if type(record) == "table" and positive(record.itemID)
        and type(record.positionKey) == "string" and record.positionKey ~= "" then
      known[record.itemID] = known[record.itemID] or {}
      known[record.itemID][#known[record.itemID] + 1] = record
    end
  end
  for _, batch in ipairs(args.acquisitions or {}) do
    if identityBatch(batch, context) then
      known[batch.itemID] = known[batch.itemID] or {}
      known[batch.itemID][#known[batch.itemID] + 1] = batch
    end
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
  -- Bag stock joins the same position table as purchases and listings, so an item that is
  -- partly bought, partly listed and partly farmed reads as ONE row rather than three. It is
  -- deliberately kept out of uniqueVariants below: that inference binds a legacy item-only
  -- batch to a variant key durably, and a bag's contents are too transient to justify a
  -- permanent accounting decision.
  for _, stock in ipairs(args.bagStock or {}) do
    if type(stock) == "table" and type(stock.positionKey) == "string" and stock.positionKey ~= ""
        and positive(stock.itemID) and positive(stock.quantity) then
      local position = positionFor(positions, stock.positionKey, stock.itemID, context)
      local bagQty = add(position.bagQty or 0, stock.quantity)
      if bagQty then
        position.bagQty = bagQty
        position.bagStacks = stock.stacks or position.bagStacks
        position.bagIsCommodity = stock.isCommodity == true
      end
      position.itemName = position.itemName or stock.itemName
    end
  end

  for itemID, batches in pairs(scoped) do
    local target = uniqueVariants(known[itemID] or batches, lotsByItem[itemID] or {})
    for _, batch in ipairs(batches) do
      local positionKey = batch.positionKey or target
      if positionKey then
        addBatch(positionFor(positions, positionKey, itemID, context), batch)
      else
        unresolvedRows[#unresolvedRows + 1] = {
          unresolved = true, protectedAction = false,
          unresolvedKey = "unassigned-acquisition:" .. tostring(batch.id or #unresolvedRows + 1),
          unresolvedKind = "unassigned_acquisition", itemID = batch.itemID,
          itemName = batch.itemName, character = context.char, region = context.region,
          batches = { batch }, pendingAcquisitions = {}, ownedLots = {}, allocations = {},
          sources = { [batch.source or "unknown"] = batch.remainingQty },
          trackedQty = 0, listedQty = 0, exposureQty = batch.remainingQty,
          knownQty = batch.remainingQty, knownCost = batch.remainingTotal,
          listedValue = 0, coverage = "UNKNOWN", projectedNet = nil, profit = nil,
          status = "REPAIR_IDENTITY", facts = { unassignedAcquisition = true },
        }
      end
    end
  end


  for _, pending in ipairs(args.pendingAcquisitions or {}) do
    if type(pending) == "table" and pending.character == context.char and pending.region == context.region
        and positive(pending.itemID) then
      local target = pending.positionKey
        or uniqueVariants(known[pending.itemID] or scoped[pending.itemID] or {}, lotsByItem[pending.itemID] or {})
      if target then
        addPending(positionFor(positions, target, pending.itemID, context), pending)
      else
        unresolvedRows[#unresolvedRows + 1] = {
          unresolved = true, protectedAction = false,
          unresolvedKey = "pending-purchase:" .. tostring(pending.id or #unresolvedRows + 1),
          unresolvedKind = "pending_purchase", itemID = pending.itemID,
          itemName = pending.itemName, character = context.char, region = context.region,
          batches = {}, pendingAcquisitions = { pending }, ownedLots = {}, allocations = {},
          sources = type(pending.quantity) == "number" and { auction_house = pending.quantity } or {},
          trackedQty = 0, pendingQty = pending.quantity or 0, listedQty = 0,
          exposureQty = pending.quantity or 0, knownQty = 0, knownCost = 0,
          listedValue = 0, coverage = "UNKNOWN", projectedNet = nil, profit = nil,
          status = "REPAIR_PURCHASE", facts = { pendingPurchase = true },
        }
      end
    end
  end

  local activities = {}
  for _, activity in pairs(args.activities or {}) do
    if type(activity) == "table" and activity.character == context.char and activity.region == context.region
        and type(activity.positionKey) == "string" and activity.positionKey ~= ""
        and positive(activity.itemID) and type(activity.itemName) == "string" and activity.itemName ~= ""
        and exact(activity.firstSeenAt) then
      activities[#activities + 1] = activity
    end
  end
  for _, evidence in ipairs(args.sellerEvidence or {}) do
    if type(evidence) == "table" and evidence.kind == "sale" and evidence.source == "mail"
        and evidence.char == context.char and evidence.region == context.region
        and type(evidence.key) == "string" and evidence.key ~= ""
        and type(evidence.itemName) == "string" and evidence.itemName ~= "" and exact(evidence.at) then
      local matchedByScope = {}
      for _, activity in ipairs(activities) do
        if activity.itemName == evidence.itemName and activity.firstSeenAt <= evidence.at then
          matchedByScope[activity.scopeKey or GC.Acquisitions.ScopeKey(activity.positionKey, context)] = activity
        end
      end
      local matched, count
      for _, activity in pairs(matchedByScope) do matched, count = activity, (count or 0) + 1 end
      -- An item is EITHER a commodity or a variant item; it cannot be both. So an activity set
      -- holding `commodity:X` alongside `item:X:...` for one itemID is a contradiction -- one
      -- of them is stale bookkeeping, not a real question about what was sold. When the
      -- purchase record proves which form is right (known[itemID], see above), that settles it.
      --
      -- Deliberately narrower than "one proven key wins". `item:X:23:0:0` and `item:X:80:0:0`
      -- do not contradict each other: they are two genuine variants of one itemID, two
      -- different things to sell, and choosing between them on the strength of having bought
      -- only one would misreport what the sale earned. That case still gets a repair row.
      if count and count > 1 then
        local proven = uniqueVariants(known[matched.itemID] or {}, {})
        local provenIsCommodity = proven and proven:find("^commodity:") ~= nil
        local contradicts = false
        for _, activity in pairs(matchedByScope) do
          local key = activity.positionKey
          if proven and type(key) == "string" and key ~= proven
              and (key:find("^commodity:") ~= nil) ~= provenIsCommodity then
            contradicts = true
          end
        end
        if contradicts then
          local narrowed, narrowedCount
          for _, activity in pairs(matchedByScope) do
            if activity.positionKey == proven then
              narrowed, narrowedCount = activity, (narrowedCount or 0) + 1
            end
          end
          if narrowedCount == 1 then matched, count = narrowed, 1 end
        end
      end
      -- A settled sale is the NORMAL end of owning something. Requiring `pending` here meant
      -- every paid sale fell through to a repair row with no itemID, no icon and no numbers --
      -- and nothing ever makes a paid sale pending again, so they accumulated forever.
      if count == 1 then
        local position = positionFor(positions, matched.positionKey, matched.itemID, context)
        position.itemName = position.itemName or matched.itemName
        if evidence.pending == true then position.facts.soldPending = true end
        position.sellerEvidence[#position.sellerEvidence + 1] = evidence
      else
        unresolvedRows[#unresolvedRows + 1] = {
          unresolved = true, protectedAction = false,
          unresolvedKey = "seller-evidence:" .. evidence.key,
          unresolvedKind = count and count > 1 and "ambiguous_sale"
            or (evidence.pending == true and "pending_sale" or "paid_sale"),
          itemName = evidence.itemName, character = context.char, region = context.region,
          batches = {}, pendingAcquisitions = {}, sellerEvidence = { evidence },
          ownedLots = {}, allocations = {}, sources = {}, trackedQty = 0,
          listedQty = 0, exposureQty = evidence.qty or 0, knownQty = 0, knownCost = 0,
          listedValue = 0, coverage = "UNKNOWN", projectedNet = nil, profit = nil,
          status = "REPAIR_SALE", facts = { unresolvedSale = true },
        }
      end
    end
  end
  local result = {}
  for _, position in pairs(positions) do
    decoratePosition(position, args.quotes or {}, args.statsByItemID or {}, args.now, args.quoteMaxAge)
    result[#result + 1] = position
  end
  for _, unresolvedPosition in ipairs(unresolvedRows) do result[#result + 1] = unresolvedPosition end
  table.sort(result, stablePositionOrder)
  return result
end

-- What Post will actually list, priced at the fresh quote.
--
-- This used to refuse anything GoldCap could not fully cost: a position needed a tracked
-- purchase (`trackedQty`), and its allocation had to come back COMPLETE, or Post was withheld.
-- That made the Sell tab useless for the majority of a seller's stock -- everything farmed,
-- crafted, milled, or acquired before the addon existed -- and it was the wrong instinct
-- anyway. Not knowing what something cost is a reason to report the profit as unknown, not a
-- reason to refuse to sell it. Cost coverage is now reported (`costKnown`) instead of enforced.
--
-- The quantity is the bag quantity, full stop. Listed units are on the auction house and not in
-- the bags, so "what is in the bags" is already exactly "what is not yet listed" -- the old
-- min(trackedQty - listedQty, bags) capped a real 200-unit stack at the 5 units GoldCap happened
-- to have a receipt for.
function GC.SellPositions.BuildPostPlan(position, bagState, freshQuote)
  local unit, quoteReason = freshUnit(freshQuote)
  if not unit then return nil, quoteReason end
  if type(position) ~= "table" or position.unresolved or position.protectedAction == false
      or position.invalid then
    return nil, "no_tracked_quantity"
  end
  -- Without a key there is nothing for the caller to check the plan against:
  -- onPostClick proves a plan belongs to the clicked row by comparing keys, and
  -- nil == nil would sail straight through that comparison.
  if type(position.positionKey) ~= "string" or position.positionKey == "" then
    return nil, "missing_position_key"
  end
  if type(bagState) ~= "table" or bagState.itemID ~= position.itemID or not positive(bagState.exactQty) then
    return nil, "missing_bag_quantity"
  end
  if type(position.positionKey) == "string" and position.positionKey:match("^item:")
      and bagState.positionKey ~= position.positionKey then
    return nil, "ambiguous_variant"
  end
  local quantity = bagState.exactQty
  if quantity <= 0 then return nil, "no_unlisted_quantity" end
  -- The displayed recommendation and the price Post actually used were two
  -- different numbers: the plan took the raw cheapest competing ask. Apply the
  -- floor here as well, so what is listed is what was shown. It can only ever
  -- RAISE the price, so the freshness contract above is untouched -- a stale
  -- floor cannot cause an underpriced sale, which is the failure that matters.
  if positive(position.postFloor) and position.postFloor > unit then
    unit = position.postFloor
  end
  local allocation = GC.Acquisitions.AllocateRange(position.batches, position.listedQty or 0, quantity)
  local complete = allocation ~= nil and allocation.coverage == "COMPLETE"
  return { positionKey = position.positionKey, scopeKey = position.scopeKey, itemID = position.itemID,
    quantity = quantity, cost = complete and allocation.knownCost or nil, costKnown = complete,
    allocations = allocation and allocation.allocations or {}, unitPrice = unit }
end

function GC.SellPositions.BuildRepostPlan(position, auctionID, freshQuote)
  local unit, quoteReason = freshUnit(freshQuote)
  if not unit then return nil, quoteReason end
  if type(position) ~= "table" or position.unresolved or position.protectedAction == false
      or position.invalid then return nil, "missing_position" end
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
  local invested, listedValue, projected = 0, 0, 0
  local complete = true
  for _, position in ipairs(positions or {}) do
    if position.coverage ~= "COMPLETE" then complete = false end
    invested = invested ~= nil and add(invested, position.knownCost) or nil
    listedValue = listedValue ~= nil and add(listedValue, position.listedValue) or nil
    if not complete or projected == nil or position.projectedNet == nil then projected = nil
    else projected = add(projected, position.projectedNet) end
  end
  if not invested or not listedValue then
    return { invested = invested, listedValue = listedValue, projected = nil, profit = nil }
  end
  if not complete or projected == nil then
    return { invested = invested, listedValue = listedValue, projected = nil, profit = nil }
  end
  local profit = projected - invested
  if not exactSigned(profit) then
    return { invested = invested, listedValue = listedValue, projected = nil, profit = nil }
  end
  return { invested = invested, listedValue = listedValue, projected = projected, profit = profit }
end

-- Cheapest unit price in the book at which somebody OTHER than the player is selling.
--
-- Pricing a sale off `GetCommoditySearchResultInfo(itemID, 1)` prices it off the player's own
-- listing the moment they are the cheapest seller, so each Post/Repost undercuts the previous
-- one and the price walks down against nobody.
--
-- Sharing a price level with real competitors is the common case and must still count: the
-- commodity API aggregates a whole price point into one row, but reports numOwnerItems
-- alongside the total, so the player's own units can be subtracted and the level kept whenever
-- anything is left. Only a level that is entirely the player's own is skipped.
--
-- When the API reports containsOwnerItem without a count, the level cannot be split, and it is
-- skipped. That errs high -- a genuine competitor sharing the price goes unmatched, costing a
-- sale at worst -- where erring low restarts the spiral this exists to stop.
function GC.SellPositions.CheapestCompetingUnit(levels)
  if type(levels) ~= "table" then return nil end
  local best
  for i = 1, #levels do
    local level = levels[i]
    if type(level) == "table" and type(level.unitPrice) == "number" and level.unitPrice > 0 then
      local quantity = type(level.quantity) == "number" and level.quantity or 0
      local ownerQty
      if type(level.ownerQty) == "number" then
        ownerQty = level.ownerQty
      elseif level.ownerItem == true then
        ownerQty = quantity -- unsplittable: treat the level as entirely the player's own
      else
        ownerQty = 0
      end
      if quantity - ownerQty > 0 and (best == nil or level.unitPrice < best) then
        best = level.unitPrice
      end
    end
  end
  return best
end
