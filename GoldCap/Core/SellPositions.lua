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

-- Whether a lot is one variant of its item -- one item level, one pet species -- rather than
-- the item as the tab has always keyed it: a caged pet (the key carries its species, or the link
-- is a battle-pet link) or an item link carrying bonus IDs, whose level the link cannot state.
-- Such a lot keeps being priced by its own key once nothing is left in the bags (Build).
local function lotIsVariant(auction)
  local key = auction.itemKey
  if type(key) == "table" and positive(key.battlePetSpeciesID) then return true end
  local link = auction.itemLink
  if type(link) ~= "string" then return false end
  if link:find("battlepet:", 1, true) then return true end
  local payload = link:match("|H(item:[^|]+)|h") or link:match("^(item:.-)$")
  if not payload then return false end
  local fields = {}
  for field in (payload .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
  local bonusCount = tonumber(fields[14])
  return bonusCount ~= nil and bonusCount > 0
end

function GC.SellPositions.NormalizeOwnedLots(auctionInfos, seenAt)
  local lots = {}
  for _, auction in ipairs(auctionInfos or {}) do
    local positionKey, itemID, isCommodity = keyForLot(auction)
    local quantity = positive(auction.quantity) and auction.quantity or 1
    local unitPrice = lotUnit(auction)
    if positionKey and positive(unitPrice) and positive(auction.auctionID) and exact(seenAt or 0) then
      -- My-auctions (docs/superpowers/specs/2026-09-06-my-auctions-design.md): carried here,
      -- not computed later, because this is the one place that already has both the auction
      -- and the seenAt it was read at. Only a genuine, positive, whole-second countdown counts
      -- -- a fractional or non-positive timeLeftSeconds is not a real API answer.
      local expiresAt = positive(auction.timeLeftSeconds) and ((seenAt or 0) + auction.timeLeftSeconds) or nil
      lots[#lots + 1] = { positionKey = positionKey, itemID = itemID, quantity = quantity,
        unitPrice = unitPrice, auctionID = auction.auctionID, firstSeenAt = seenAt or 0,
        isCommodity = isCommodity == true, expiresAt = expiresAt,
        variant = (isCommodity ~= true and lotIsVariant(auction)) or nil,
        itemLink = type(auction.itemLink) == "string" and auction.itemLink or nil }
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
    projectedNet = nil, profit = nil, profitAtHold = nil, status = "UNLISTED", ahead = nil, outlook = nil,
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

local function decoratePosition(position, quotes, statsByItemID, now, quoteMaxAge, chosenUnits)
  table.sort(position.ownedLots, stableLotOrder)
  -- An item-level variant is priced from a search for its own ItemKey, filed under its own
  -- `quoteKey` (UI/SellFrame.lua); anything else under its itemID, as ever.
  local quoteID = position.quoteKey or position.itemID
  local fresh, display, age = quoteInfo(quotes, quoteID, now, quoteMaxAge)
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
  -- The cost basis covers everything the player physically holds RIGHT NOW -- listed on the AH
  -- plus sitting in the bags -- not whichever slice happens to be listed. This is the incident
  -- fix: a 24-unit listing used to cap the FIFO allocation at 24, so 94 cheap units sitting in
  -- the bags were invisible to COST/UNIT and the row read as a loss that was not real.
  --
  -- `exposureQty` above is left exactly as it was (listedQty alone once anything is listed, else
  -- trackedQty, plus pending) -- it feeds SellOutlook's queue-depth math and RepostAdvice/
  -- RecommendPost's `qty` argument below, both asking "how many units are moving through the
  -- pipeline" (SellFrame.lua's uncostedQty/canSetCost already documents that this field stays
  -- capped at listedQty on purpose and works around it with trackedQty; nothing here changes
  -- that fact). `heldQty` answers a different question -- "what did the units I am holding right
  -- now cost" -- and only the allocation, knownQty/knownCost and coverage below follow it.
  --
  -- physicalQty (listed + bags) wins whenever there is any physical evidence at all; trackedQty
  -- is kept ONLY as the fallback for a position with nothing listed and nothing yet scanned into
  -- the bags (e.g. a GoldCap purchase still sitting in the mail) -- there is no better estimate
  -- of what is held in that state, and dropping it would make every unpicked-up purchase read as
  -- uncosted. pendingQty is deliberately excluded: a pending acquisition has not landed yet, so
  -- there is nothing physical to cost it against.
  local physicalQty = add(position.listedQty or 0, position.bagQty or 0)
  if not physicalQty then
    position.invalid = true
    position.exposureQty, position.allocations, position.knownQty, position.knownCost = nil, {}, 0, 0
    position.coverage, position.projectedNet, position.profit = "UNKNOWN", nil, nil
    position.status, position.ahead, position.outlook, position.recommendation = "NO_COST", nil, nil, nil
    return
  end
  local heldQty = physicalQty > 0 and physicalQty or position.trackedQty
  position.heldQty = heldQty
  local allocation = heldQty > 0 and GC.Acquisitions.Allocate(position.batches, heldQty)
  if allocation then
    position.allocations, position.knownQty, position.knownCost = allocation.allocations,
      allocation.knownQty, allocation.knownCost
    position.coverage = allocation.knownQty == 0 and "UNKNOWN"
      or allocation.knownQty < heldQty and "PARTIAL" or "COMPLETE"
  end
  -- projectedNet/profit are computed BELOW, after the recommendations -- they must price at
  -- the same number Post actually uses (see the projected block's own comment), and the
  -- queue-at-exit recommendation does not exist yet at this point in the walk.

  local levels = type(quotes and quotes[quoteID]) == "table" and quotes[quoteID].levels or nil
  -- Kept on the position, not just used and dropped. Every price decision below already reads
  -- the live book -- the floor, the recommendation, the depth ahead of your own lot -- and the
  -- one thing the seller could never see was the book itself. The Sell tab shows a price it
  -- picked and, until now, nothing about what that price is standing on.
  position.levels = levels
  -- The imported market data is keyed by item ID, and the site merges every item level of a
  -- piece of gear into one row -- and every caged pet into Pet Cage, across all species. A
  -- variant (keyed by its own ItemKey, `quoteKey`) therefore has no market figure: no value, no
  -- sales, no reach, no floor. Its price is its own live book's; a 15g pet was floored to 225g
  -- off the Pet Cage median (review I4). Items keyed as they always were keep their data.
  local petSpecies = type(position.quoteKey) == "string" and tonumber(position.quoteKey:match(":(%d+)$")) or nil
  position.variantKind = position.quoteKey and ((petSpecies or 0) > 0 and "pet" or "level") or nil
  local marketStats = not position.quoteKey and statsByItemID and statsByItemID[position.itemID] or nil
  position.trendPct = marketStats and marketStats.trend or nil
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
  -- The exit this position was underwritten at: sniper-bought batches store the stress exit
  -- their purchase was approved against (Acquisitions.RecordGoldCap's targetUnit). The highest
  -- one among batches still holding stock feeds RecommendPost's queue-at-exit rule; positions
  -- with no sniper history have none and keep plain match/undercut pricing.
  local targetUnit
  for _, batch in ipairs(position.batches or {}) do
    if (batch.remainingQty or 0) > 0 and type(batch.targetUnit) == "number" and batch.targetUnit > 0 then
      if not targetUnit or batch.targetUnit > targetUnit then targetUnit = batch.targetUnit end
    end
  end
  position.targetUnit = targetUnit
  local sniperSettings = GC.db and GC.db.settings and GC.db.settings.sniper or nil
  local absorbHours = sniperSettings and sniperSettings.wallAbsorbHours or nil
  local spikePct = sniperSettings and sniperSettings.spikeTrendPct or nil
  -- The two posting ceilings reach RecommendPost only through here, and only while the player
  -- has overcut on -- RecommendPost itself never reads settings. A save without the field yet
  -- (ApplyDefaults runs at login) counts as on, matching the default. reach is the real
  -- ceiling (what this item's floor actually reaches in a day, import R section); the
  -- cheap-quarter line is the fallback for items and imports that carry no reach figure, and
  -- both travel together so RecommendPost can say which one bound the price.
  local overcutOn = not sniperSettings or sniperSettings.overcut ~= false
  local quarterUnit = overcutOn and marketStats and marketStats.p25 or nil
  local reachUnit = overcutOn and marketStats and marketStats.reach or nil

  position.ahead = GC.Flips.DepthBelow(levels, position.ownedLots[1] and position.ownedLots[1].unitPrice)
  position.outlook = GC.Flips.SellOutlook({ ahead = position.ahead, qty = position.exposureQty,
    sold = marketStats and marketStats.sold, trend = marketStats and marketStats.trend })
  -- paidUnit is knownCost/knownQty, not knownCost/exposureQty: knownCost now covers heldQty
  -- (listed + bags), and knownQty equals heldQty exactly whenever coverage is COMPLETE (the
  -- guard both branches share), so this is the same per-unit figure COST/UNIT itself displays
  -- (SellFrame.lua). Dividing by exposureQty here would price the FULL blended cost per the
  -- narrower listed-only quantity -- exactly the incoherence this fix exists to remove.
  if position.coverage == "COMPLETE" and position.listedQty > 0 then
    position.recommendation = GC.Flips.RepostAdvice({ paidUnit = position.knownCost and math.floor(position.knownCost / position.knownQty),
      marketUnit = fresh, levels = levels, sold = position.soldPerDay, qty = position.exposureQty,
      floor = position.postFloor, reachUnit = reachUnit, quarterUnit = quarterUnit })
  elseif position.coverage == "COMPLETE" then
    position.recommendation = GC.Flips.RecommendPost(position.knownCost and math.floor(position.knownCost / position.knownQty),
      fresh, position.marketValue, { levels = levels, sold = position.soldPerDay, floor = position.postFloor,
        targetUnit = targetUnit, absorbHours = absorbHours, spikePct = spikePct,
        trendPct = marketStats and marketStats.trend, reachUnit = reachUnit, quarterUnit = quarterUnit })
  elseif positive(position.bagQty) and fresh then
    -- Stock GoldCap never bought still deserves an answer to "what should I list this at".
    -- No cost basis means no breakeven and no belowCost warning -- RecommendPost already
    -- degrades to exactly that on a nil paidUnit, rather than inventing a cost from the market.
    position.recommendation = GC.Flips.RecommendPost(nil, fresh, position.marketValue,
      { levels = levels, sold = position.soldPerDay, floor = position.postFloor,
        reachUnit = reachUnit, quarterUnit = quarterUnit })
  else
    position.recommendation = nil
  end

  -- What would I list the stock in my BAGS at -- a narrower, always-the-same question than
  -- `position.recommendation` above, which sometimes answers a different one: once coverage is
  -- COMPLETE and something is already listed, `recommendation` is RepostAdvice-shaped
  -- ({action, reason, rec}, no top-level `.unit`) and answers "should I cancel and relist the
  -- lot that's already up" instead. Bag stock still needs a post price of its own even when the
  -- SAME item is partly listed -- 100 bought, 50 posted, 50 still in the bags -- and conflating
  -- the two questions into one field is exactly what made GC.PostQueue skip that position: it
  -- read `recommendation.unit`, found no top-level `.unit` on the RepostAdvice shape, and
  -- reported `no_fresh_price` for a row whose own Post button, right beside it, worked fine
  -- (BuildPostPlan never reads `recommendation` at all). Computed for every position that has
  -- bag stock, independently of listedQty and of what `recommendation` above decided; `paidUnit`
  -- mirrors the COMPLETE branch above exactly when coverage is COMPLETE, and is nil otherwise --
  -- the same "no cost basis, no breakeven, no belowCost warning" degradation the untracked-stock
  -- branch above already relies on.
  if positive(position.bagQty) then
    -- Same re-derivation as the recommendation branches above: knownCost/knownQty, not
    -- knownCost/exposureQty (see that comment for why).
    local paidUnit = position.coverage == "COMPLETE"
      and (position.knownCost and math.floor(position.knownCost / position.knownQty)) or nil
    -- spikePct travels alongside targetUnit here for the same reason it does in the
    -- `recommendation` branch above: without it, the queue-at-exit deflation this options
    -- table enables (opts.targetUnit + opts.levels + opts.sold) falls back to the shared
    -- default instead of the player's own settings.sniper.spikeTrendPct, so PROFIT/UNIT and
    -- the Post button could price the SAME bag stock differently depending on which branch
    -- happened to compute it -- one honoring the player's setting, one silently ignoring it.
    position.postRecommendation = GC.Flips.RecommendPost(paidUnit, fresh, position.marketValue,
      { levels = levels, sold = position.soldPerDay, floor = position.postFloor,
        targetUnit = targetUnit, absorbHours = absorbHours, spikePct = spikePct,
        trendPct = marketStats and marketStats.trend, reachUnit = reachUnit, quarterUnit = quarterUnit })
  else
    position.postRecommendation = nil
  end

  -- A price the seller typed replaces the recommendation EVERYWHERE it is read, not only at
  -- the moment of posting: the row's PROFIT column, the posting queue's own label and the plan
  -- all have to be one number. This file has carried that defect twice already (see the
  -- floor-raise comment in BuildPostPlan) -- the displayed price and the posted price being
  -- two different numbers is the bug, not the fix. Rounded onto the silver grid here for the
  -- same reason BuildPostPlan rounds: the projection below must price at what will be listed.
  local chosen = chosenUnits and type(position.positionKey) == "string"
    and chosenUnits[position.positionKey] or nil
  if positive(chosen) and type(position.postRecommendation) == "table" then
    position.chosenUnit = GC.Flips.SilverUp(chosen) or chosen
    position.postRecommendation.unit = position.chosenUnit
    -- Not "queue" any more: the queue-at-exit raise in BuildPostPlan keys off that mode, and a
    -- raise applied on top of a chosen price would silently undo the choice.
    position.postRecommendation.mode = "chosen"
  end

  -- Projected income and profit, computed HERE -- after the recommendations -- so the row's
  -- PROFIT column and the price Post actually uses are one number, not two. Both branches
  -- price the way the queue-at-exit rule does:
  --  * A LISTED lot priced at or under the position's underwritten exit projects at ITS
  --    price -- the addon queued it there on purpose, and clamping it back down to the
  --    current cheapest ask (the old rule) showed a fresh queue post as an instant loss
  --    (seen in game: listed at 11g19s per the queue rule, PROFIT read -45s off the 8g93s
  --    floor). A lot priced ABOVE the exit keeps the conservative min(list, market) clamp:
  --    nothing underwrites that price, and projecting it would flatter a mistake.
  --  * BAG stock projects at what Post would actually list it at (postRecommendation.unit,
  --    floor/queue raises included) rather than the raw cheapest ask, for the same reason.
  --    Still only with a fresh live quote, exactly as before -- mv alone never projects.
  --
  -- Both branches must cover the SAME quantity knownCost was allocated over (heldQty, above),
  -- or PROFIT/UNIT subtracts a cost basis wider than the revenue it was compared against --
  -- the other half of the incident: 94 bag units were invisible to COST/UNIT AND to PROFIT/UNIT.
  -- So when something is listed, the bag units (if any) join the SAME gross the listed lots
  -- build, priced at postRecommendation exactly like the bag-only branch below -- and if bag
  -- stock exists but has no price yet, the whole projection stays unknown rather than silently
  -- comparing listed-only revenue against listed-plus-bags cost.
  local projected
  -- Set only by the bag-only branch below, and only when it actually priced the projection at
  -- postRecommendation.unit rather than the live ask -- i.e. PostFloor (or the queue-at-exit
  -- rule) held the recommendation ABOVE what MARKET/UNIT shows right now. The view reads this
  -- to know PROFIT/UNIT is answering "what would I clear at the price GoldCap recommends," not
  -- "what would I clear selling into today's book" -- two different numbers that happen to
  -- share a cell. Left nil for the ordinary case (rec at or under the live ask) so the view's
  -- rendering is untouched there.
  local holdUnit
  if position.listedQty > 0 then
    local gross = 0
    for _, ownedLot in ipairs(position.ownedLots) do
      local unit
      if targetUnit and ownedLot.unitPrice <= targetUnit then
        unit = ownedLot.unitPrice
      else
        unit = fresh and math.min(ownedLot.unitPrice, fresh) or ownedLot.unitPrice
      end
      local value = valueFor(ownedLot.quantity, unit)
      gross = value and add(gross, value) or nil
      if not gross then break end
    end
    if gross and positive(position.bagQty) then
      local rec = position.postRecommendation
      local bagUnit = (type(rec) == "table" and positive(rec.unit)) and rec.unit or fresh
      if bagUnit then
        -- Same hold rule as the bag-only branch below: bag units priced above the live ask
        -- mean this PROFIT rests on the recommendation holding, and the row must say so.
        if fresh and bagUnit > fresh then holdUnit = bagUnit end
        local bagValue = valueFor(position.bagQty, bagUnit)
        gross = bagValue and add(gross, bagValue) or nil
      else
        gross = nil
      end
    end
    projected = gross and mulDivFloor(gross, 95, 100) or nil
  elseif fresh then
    local rec = position.postRecommendation
    local unit = (type(rec) == "table" and positive(rec.unit)) and rec.unit or fresh
    if unit > fresh then holdUnit = unit end
    projected = netFor(heldQty, unit)
  else
    projected = nil
  end
  position.projectedNet = projected
  if position.coverage == "COMPLETE" and projected ~= nil then
    position.profit = projected - position.knownCost
    position.profitAtHold = holdUnit
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
      local position = positionFor(positions, positionKey, itemID, context)
      addLot(position, lot)
      -- A variant's lot keeps the position on its own market search once the bags are empty:
      -- the bare key answers with the item's cheapest variant, another item's price (review I3).
      if lot.variant then position.quoteKey = position.quoteKey or positionKey end
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
        -- An item-level variant's market search is its own (see decoratePosition).
        position.quoteKey = stock.quoteKey or position.quoteKey
        -- What ONE Post click can actually list, which is not the same number as what is in the
        -- bags: PostItem pins a single ItemLocation, so a normal item posts its largest stack
        -- and no more, while a commodity aggregates the whole pool (GC.BagStock.PostableQuantity
        -- owns that rule). The tab ranked and totalled on the bag SUM, so five stacks of twenty
        -- showed a YOU GET for a hundred units and sorted the queue on it, and the click listed
        -- twenty. Left nil when BagStock is absent (older fixtures); every reader falls back to
        -- bagQty, which is what they all used to do.
        position.postableQty = GC.BagStock and GC.BagStock.PostableQuantity
          and GC.BagStock.PostableQuantity(stock) or nil
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
        local provenIsCommodity = proven ~= nil and (proven:find("^commodity:") ~= nil) or nil
        -- The purchase record is not the only authority on whether an item sells as a
        -- commodity, and it is not the best one either: `commodityKinds` is what
        -- C_AuctionHouse.GetItemKeyInfo told the client, cached in SavedVariables the first
        -- time the item was seen at an auction house. It answers this exact question directly,
        -- where a purchase only answers it by implication -- and it answers for items that
        -- were never bought at all, which is where this used to give up. A live client's
        -- enchant had two contradictory keys, no purchases, and a cached `true` sitting right
        -- there; the sale went to a repair row anyway.
        if provenIsCommodity == nil then
          local kind = type(args.commodityKinds) == "table" and args.commodityKinds[matched.itemID]
          if kind == true or kind == false then provenIsCommodity = kind end
        end
        if provenIsCommodity ~= nil then
          local contradicts = false
          for _, activity in pairs(matchedByScope) do
            local key = activity.positionKey
            if type(key) == "string" and (key:find("^commodity:") ~= nil) ~= provenIsCommodity then
              contradicts = true
            end
          end
          if contradicts then
            -- Narrowed by FORM, and additionally by the exact key when a purchase proved one.
            -- Form alone is all the cache can prove, and it is enough for the only thing this
            -- branch is allowed to settle: `item:X:23:0:0` and `item:X:80:0:0` share a form,
            -- so two genuine variants still both survive the filter and stay a question.
            local narrowed, narrowedCount
            for _, activity in pairs(matchedByScope) do
              local key = activity.positionKey
              if type(key) == "string" and (key:find("^commodity:") ~= nil) == provenIsCommodity
                  and (proven == nil or key == proven) then
                narrowed, narrowedCount = activity, (narrowedCount or 0) + 1
              end
            end
            if narrowedCount == 1 then matched, count = narrowed, 1 end
          end
        end
      end
      -- The same tiebreak the ledger's own reconciliation uses (Acquisitions.ReconcileSale):
      -- where two candidates share an item NAME because they are two quality ranks of one
      -- reagent, the price the sale went through at is what separates them. Deliberately kept
      -- in step with that one -- this tab and the ledger disagreeing about which position a
      -- sale belongs to would be worse than either of them refusing.
      if count and count > 1 and positive(evidence.qty) and positive(evidence.total) then
        local unit = math.floor(evidence.total / evidence.qty)
        local narrowed, narrowedCount
        for _, activity in pairs(matchedByScope) do
          if GC.Acquisitions.WasListedAt(activity, unit, evidence.at) then
            narrowed, narrowedCount = activity, (narrowedCount or 0) + 1
          end
        end
        if narrowedCount == 1 then matched, count = narrowed, 1 end
      end
      -- A settled sale is the NORMAL end of owning something. Requiring `pending` here meant
      -- every paid sale fell through to a repair row with no itemID, no icon and no numbers --
      -- and nothing ever makes a paid sale pending again, so they accumulated forever.
      --
      -- ...but a settled sale only ATTACHES to a position that exists for another reason
      -- (stock in the bags, a live listing, an open purchase batch). It never creates one: a
      -- position with nothing bought, nothing held and nothing listed, carrying only a paid
      -- sale from weeks ago, is a row with a dash in every column -- the third in-game pass
      -- found dozens of them ("items I sold long ago") at the bottom of the list, one per
      -- ledger sale that no purchase batch ever consumed, and the ledger is never pruned by
      -- age. That sale is history, and history is the Sold tab's business. A PENDING sale
      -- (proceeds not collected yet) still gets its row -- "sale proceeds pending" is the
      -- one thing this tab can still tell the player about it.
      if count == 1 then
        local existing = positions[matched.positionKey]
        if existing or evidence.pending == true then
          local position = positionFor(positions, matched.positionKey, matched.itemID, context)
          position.itemName = position.itemName or matched.itemName
          if evidence.pending == true then position.facts.soldPending = true end
          position.sellerEvidence[#position.sellerEvidence + 1] = evidence
        end
      elseif evidence.pending == true then
        -- A SETTLED sale never creates a row, whether or not it could be attributed. That is
        -- the same rule the branch above already applies to a sale it did attribute -- attach
        -- to a position that exists for another reason, never conjure one -- and there is no
        -- reason it should hold for the sales GoldCap understood and not for the ones it did
        -- not. The row it used to make could not be acted on and could never be resolved: no
        -- itemID, no icon, a dash in every column and "Missing cost" underneath, one per
        -- unattributable invoice, accumulating for as long as the ledger is kept. A live
        -- client had seven, four of them the same reagent, and asked why sales that had
        -- plainly gone through were still sitting in the Sell tab.
        --
        -- The information is not lost with the row. A sale GoldCap could not cost still says
        -- so per sale, in Sold, where that sentence belongs -- "cost unknown" on the row for
        -- that exact invoice. What disappears is only the claim that the SELL tab, which is
        -- about what to do next, has something outstanding about it.
        --
        -- A PENDING sale is different and keeps its row: the proceeds are not collected yet,
        -- so it is not finished business, and this tab saying "sale proceeds pending" is the
        -- one useful thing left to say about it.
        unresolvedRows[#unresolvedRows + 1] = {
          unresolved = true, protectedAction = false,
          unresolvedKey = "seller-evidence:" .. evidence.key,
          unresolvedKind = count and count > 1 and "ambiguous_sale" or "pending_sale",
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
    decoratePosition(position, args.quotes or {}, args.statsByItemID or {}, args.now,
      args.quoteMaxAge, args.chosenUnits)
    result[#result + 1] = position
  end
  for _, unresolvedPosition in ipairs(unresolvedRows) do result[#result + 1] = unresolvedPosition end
  table.sort(result, stablePositionOrder)
  return result
end

--- What listing at `unit` would mean for this position: under the underprice floor, under what
-- the stock cost, or neither. Shared by BuildPostPlan and by the Sell tab's own price control,
-- deliberately -- the warning a seller reads beside the box has to be computed the same way as
-- the flag the plan carries, or the screen and the post can disagree about the same number.
--
-- `paidUnit` is knownCost/knownQty and only exists on COMPLETE coverage: a partial basis is
-- not a break-even, and claiming one would invent a cost the addon does not have.
function GC.SellPositions.PriceRisk(position, unit)
  position = type(position) == "table" and position or {}
  if not positive(unit) then return { belowFloor = false, belowCost = false } end
  local paidUnit = position.coverage == "COMPLETE" and positive(position.knownQty)
    and math.floor((position.knownCost or 0) / position.knownQty) or nil
  return {
    paidUnit = paidUnit,
    floor = positive(position.postFloor) and position.postFloor or nil,
    belowFloor = positive(position.postFloor) and unit < position.postFloor or false,
    belowCost = paidUnit ~= nil and unit < paidUnit or false,
  }
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
function GC.SellPositions.BuildPostPlan(position, bagState, freshQuote, opts)
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
  -- A price the seller typed replaces the derived one outright -- both raises below included.
  -- Those raises exist to stop the ADDON from underpricing on its own, against a thin cheap
  -- lot it cannot tell from a real market; they were never meant as a veto on a seller who
  -- has read the book and chosen. What this does instead of clamping is REPORT: `belowFloor`
  -- and `belowCost` ride on the plan so the caller can say it out loud before the second
  -- click, rather than quietly listing at a number the player did not ask for.
  local chosen = positive(opts and opts.overrideUnit) and opts.overrideUnit or nil
  if chosen then
    unit = chosen
  else
    -- The displayed recommendation and the price Post actually used were two
    -- different numbers: the plan took the raw cheapest competing ask. Apply the
    -- floor here as well, so what is listed is what was shown. It can only ever
    -- RAISE the price, so the freshness contract above is untouched -- a stale
    -- floor cannot cause an underpriced sale, which is the failure that matters.
    if positive(position.postFloor) and position.postFloor > unit then
      unit = position.postFloor
    end
    -- Queue-at-exit raise (F5), same asymmetry as the floor raise above: when RecommendPost
    -- decided this position should queue at its underwritten exit rather than match the wall it
    -- was bought from, the plan must list at that same number -- the displayed recommendation
    -- and the posted price being two different numbers is exactly the defect the floor raise
    -- comment describes. A raise can only ever increase the price, so a stale queue quote can
    -- delay a sale but never cause an underpriced one, which is the failure that matters.
    -- Overcut rides the same raise: the rung above the cheapest is the number the row shows, so
    -- it is the number the post uses.
    local queueRec = position.postRecommendation
    if type(queueRec) == "table" and (queueRec.mode == "queue" or queueRec.mode == "overcut")
        and positive(queueRec.unit) and queueRec.unit > unit then
      unit = queueRec.unit
    end
  end
  -- Part 0 of the posting-queue design (2026-08-17): PostCommodity/PostItem silently reject any
  -- price with a non-zero copper remainder, and neither the raw live quote above nor postFloor
  -- (derived from mv * UNDERPRICE_FLOOR, an arithmetic ratio, not a grid position) is guaranteed
  -- to land on the 100-copper grid. Normalize AFTER the floor raise, with SilverUp, so this can
  -- only ever move the price up -- never back under the floor the raise above just enforced.
  local graded = GC.Flips.SilverUp(unit)
  if not graded then return nil, "invalid_price" end
  -- ...but SilverUp is not the rounding the ROW published. RecommendPost normalises its match
  -- candidate with SilverDown, and an item auction's unit price is buyoutAmount/quantity, which
  -- need not sit on the grid at all -- so the price on screen (postRecommendation.unit, which
  -- every figure on the row and in the posting queue is computed from) could be a whole silver
  -- under the price this plan sent. Two different numbers for one click is the exact defect the
  -- floor-raise comment above describes; list at the number that was shown.
  --
  -- Narrowly: only when the published number is the SAME candidate this plan already holds,
  -- rounded the other way -- between SilverDown(unit) and SilverUp(unit), the two grid prices a
  -- single raw figure can land on. That is the rounding disagreement and nothing else. A
  -- recommendation that sits somewhere else entirely is a different decision, made against
  -- different inputs, and must not move the price: raising the plan is the queue/overcut
  -- branch's job above, on the modes that own it.
  if not chosen then
    local rec = position.postRecommendation
    -- Through SilverUp, exactly as UI/SellFrame's effectivePostUnit renders it, so the two are
    -- the same number by construction rather than by coincidence.
    local published = type(rec) == "table" and positive(rec.unit) and GC.Flips.SilverUp(rec.unit) or nil
    local floorGrid = GC.Flips.SilverDown(unit)
    if published and floorGrid and published >= floorGrid and published <= graded then
      graded = published
    end
  end
  unit = graded
  local allocation = GC.Acquisitions.AllocateRange(position.batches, position.listedQty or 0, quantity)
  local complete = allocation ~= nil and allocation.coverage == "COMPLETE"
  -- Measured AFTER SilverUp, against the final number this plan will actually list at -- the
  -- caller's warning has to describe the price that gets sent, not the one before rounding.
  local risk = GC.SellPositions.PriceRisk(position, unit)
  return { positionKey = position.positionKey, scopeKey = position.scopeKey, itemID = position.itemID,
    quantity = quantity, cost = complete and allocation.knownCost or nil, costKnown = complete,
    allocations = allocation and allocation.allocations or {}, unitPrice = unit,
    chosen = chosen ~= nil, belowFloor = risk.belowFloor, belowCost = risk.belowCost }
end

-- Repost is a cancel-only click: this plan's `unitPrice` is never posted at anything. Its only
-- runtime reader is onRepostClick's second-click confirm guard (UI/SellFrame.lua), which
-- compares it against the RAW fresh quote the row armed on -- never against a raised number --
-- so this must keep pricing at exactly the fresh quote. The actual relist happens later, once
-- the cancelled units are back in the bags, through the ordinary Post path (BuildPostPlan
-- above), which already carries the queue/overcut raise. A raise applied HERE instead would
-- make the confirm guard's comparison fail on every overcut-recommended lot and the second
-- click would read "Repost confirmation expired" forever.
function GC.SellPositions.BuildRepostPlan(position, auctionID, freshQuote)
  local unit, quoteReason = freshUnit(freshQuote)
  if not unit then return nil, quoteReason end
  if type(position) ~= "table" or position.unresolved or position.protectedAction == false
      or position.invalid then return nil, "missing_position" end
  for _, ownedLot in ipairs(position.ownedLots or {}) do
    if ownedLot.auctionID == auctionID then
      -- Cost is REPORTED, not required -- the same contract BuildPostPlan above has always
      -- had. This used to return nil, "incomplete_cost" whenever the lot's FIFO slice was
      -- anything but COMPLETE, and that refusal guarded nothing: a repost cancels a live
      -- auction, no caller reads `cost` or `allocations` off a repost plan, and what the
      -- units originally cost cannot make cancelling one unsafe. What it did do was kill the
      -- Repost button outright on every listing GoldCap has no purchase record for -- farmed,
      -- crafted, milled, or bought before it was installed -- while leaving the button on
      -- screen and enabled, so the click died into a status line nobody was looking at. The
      -- pair was inconsistent in the dangerous direction too: Post, which spends gold and
      -- lists stock, has always been willing to proceed with costKnown = false.
      local allocation = ownedLot.allocation
      local complete = allocation ~= nil and allocation.coverage == "COMPLETE"
      return { positionKey = position.positionKey, scopeKey = position.scopeKey, itemID = position.itemID,
        auctionID = ownedLot.auctionID, quantity = ownedLot.quantity,
        cost = complete and allocation.knownCost or nil, costKnown = complete,
        allocations = complete and allocation.allocations or {}, unitPrice = unit }
    end
  end
  return nil, "unknown_auction"
end

function GC.SellPositions.Summary(positions)
  local invested, listedValue, projected = 0, 0, 0
  local complete = true
  -- `profit` used to be all-or-nothing: one PARTIAL/UNKNOWN position, or one COMPLETE position
  -- with no live quote yet, nulled the entire total, even though every other position on the
  -- list had a perfectly good, individually-known profit. Count each position on its own terms
  -- instead -- COMPLETE coverage and a priced projection, the same two gates `position.profit`
  -- itself is set under at ~:496 -- and sum only those, reporting what got left out rather than
  -- pretending the whole total is unknown because of them.
  local countedCount, excludedNoCost, excludedNoPrice = 0, 0, 0
  local countedCost, countedNet = 0, 0
  for _, position in ipairs(positions or {}) do
    if position.coverage ~= "COMPLETE" then complete = false end
    invested = invested ~= nil and add(invested, position.knownCost) or nil
    listedValue = listedValue ~= nil and add(listedValue, position.listedValue) or nil
    if not complete or projected == nil or position.projectedNet == nil then projected = nil
    else projected = add(projected, position.projectedNet) end

    if position.coverage ~= "COMPLETE" then
      excludedNoCost = excludedNoCost + 1
    elseif position.projectedNet == nil then
      excludedNoPrice = excludedNoPrice + 1
    else
      countedCount = countedCount + 1
      countedCost = countedCost ~= nil and add(countedCost, position.knownCost) or nil
      countedNet = countedNet ~= nil and add(countedNet, position.projectedNet) or nil
    end
  end
  -- Same shape as the all-or-nothing `projected - invested` below: sum the two non-negative
  -- sides separately (add() rejects negatives, so a signed per-position profit can't be summed
  -- directly), subtract once, and gate the signed result through exactSigned -- the identical
  -- overflow guard `position.profit` itself relies on.
  local profit
  if countedCount > 0 and countedCost ~= nil and countedNet ~= nil then
    local candidate = countedNet - countedCost
    if exactSigned(candidate) then profit = candidate end
  end
  if not invested or not listedValue or not complete or projected == nil then
    return { invested = invested, listedValue = listedValue, projected = nil, profit = profit,
      countedCount = countedCount, excludedNoCost = excludedNoCost, excludedNoPrice = excludedNoPrice }
  end
  return { invested = invested, listedValue = listedValue, projected = projected, profit = profit,
    countedCount = countedCount, excludedNoCost = excludedNoCost, excludedNoPrice = excludedNoPrice }
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
