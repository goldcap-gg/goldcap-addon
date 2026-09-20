local _, GC = ...

GC.SellViewModel = {}

-- Compact provenance tokens, not prose -- they sit inside a cell beside a quantity, and they
-- double as the chip filter's own mode names (Filter below). `goldcap_buy` is a BUY-tab run
-- purchase (UI/BuyFrame.lua) and `craft` is a crafting session (Core/CraftCapture.lua): a
-- source with no entry here is invisible to SourceText, which then reports a position whose
-- cost is fully known as "Missing cost".
local SOURCE_LABELS = { goldcap = "GC", auction_house = "AH", goldcap_buy = "BUY",
  craft = "CRAFT", manual = "MANUAL" }
local SOURCE_ORDER = { "goldcap", "auction_house", "goldcap_buy", "craft", "manual" }

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
  return GC.L["unknown evidence"]
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

--- The deck a position belongs to, and the chip filters on top of it.
--
-- Two decks, because "what can I list" and "what is already listed" are two different jobs and
-- the single table had to change the verb in its action column from row to row to serve both.
-- `Filter` above is untouched and still serves the provenance and coverage cuts; this is the
-- split the tab's own chrome is built on.
--
-- POST is deliberately "not on the auction house right now", not "has bag stock": a position
-- with nothing in the bags AND nothing listed is real cost history whose stock is in the mail,
-- the bank or on another character, and it has to stay reachable or Set cost goes with it.
-- SellViewModel.Order already ranks those last, so they sit at the bottom of the deck rather
-- than among the rows a player is acting on.
--
-- A position can be on BOTH decks and that is correct, not a leak: 40 units in the bags and 20
-- listed is forty to post and twenty to watch.
local function onPostDeck(position)
  local bags = type(position.bagQty) == "number" and position.bagQty or 0
  local listed = type(position.listedQty) == "number" and position.listedQty or 0
  return bags > 0 or listed == 0
end

local function onListedDeck(position)
  return (type(position.listedQty) == "number" and position.listedQty or 0) > 0
end

-- "Ready" is what Post can act on THIS second: stock in the bags and a price the addon will
-- stand behind. Deliberately not "has any price" -- a stale quote is what Post refreshes before
-- it acts, and calling that ready would promise a click that turns into a wait.
local function isReady(position)
  local bags = type(position.bagQty) == "number" and position.bagQty or 0
  return bags > 0 and position.freshMarketUnit ~= nil
end

local function needsCost(position)
  return position.coverage == "PARTIAL" or position.coverage == "UNKNOWN"
end

--- Positions for one deck, in reading order.
-- @param deck string  "post" (default) or "listed"
-- @param chips table   optional { ready = boolean, noCost = boolean }
function GC.SellViewModel.Deck(positions, deck, chips)
  chips = type(chips) == "table" and chips or {}
  local belongs = deck == "listed" and onListedDeck or onPostDeck
  local picked = {}
  for _, position in ipairs(positions or {}) do
    local include = belongs(position)
    -- Both chips ask POST-deck questions: a live lot is already priced and already paid for, so
    -- neither narrows anything there. Applying them anyway would silently empty the deck.
    if include and deck ~= "listed" then
      if chips.ready and not isReady(position) then include = false end
      if chips.noCost and not needsCost(position) then include = false end
    end
    if include then picked[#picked + 1] = position end
  end
  return GC.SellViewModel.Order and GC.SellViewModel.Order(picked) or picked
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

--- Hold the order the list has already settled on.
--
-- Order() answers "what should this list look like when it is built". This answers the other
-- question, which the tab could not answer at all: what should it look like on the NEXT render,
-- two seconds later, when one more quote has landed.
--
-- The pricing walk fills freshMarketUnit one item at a time, and Order ranks a priced bag stack
-- above an unpriced one and then sorts by value -- so every single answer from the auction
-- house moved a row, and for the first half-minute after opening the tab the list rearranged
-- itself under the cursor. That is the complaint this exists to end: a refresh changes the
-- NUMBERS on a row, never where the row is.
--
-- `places` is the caller's memory, mutated here: a position keeps the place it was given until
-- the caller throws the table away, which it does only when the player asks for a new order
-- (Refresh, a deck change, a chip). Anything the caller has never seen is appended in Order's
-- own sequence, so a stack that appears mid-session lands at the bottom rather than shouldering
-- into the middle of a list somebody is working down.
function GC.SellViewModel.Settle(positions, places)
  if type(places) ~= "table" then return positions or {} end
  local highest = 0
  for _, place in pairs(places) do
    if type(place) == "number" and place > highest then highest = place end
  end
  local ordered, place = {}, {}
  for index, position in ipairs(positions or {}) do
    ordered[index] = position
    local key = position.positionKey
    if type(key) == "string" and key ~= "" then
      if places[key] == nil then
        highest = highest + 1
        places[key] = highest
      end
      place[position] = places[key]
    else
      -- No key to remember it by: keep it in the incoming order, after everything that has
      -- one, rather than letting an unkeyed row jitter against the settled ones.
      place[position] = 1e9 + index
    end
  end
  table.sort(ordered, function(left, right) return place[left] < place[right] end)
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
  return #parts > 0 and table.concat(parts, " · ") or GC.L["Missing cost"]
end

function GC.SellViewModel.CostText(position)
  if not position then return GC.L["Unknown"] end
  if position.unresolved then
    return type(position.knownCost) == "number" and position.knownCost > 0
      and (tostring(position.knownCost) .. GC.L[" · identity unresolved"]) or GC.L["Unknown"]
  end
  if position.coverage ~= "COMPLETE" then
    local known = type(position.knownCost) == "number" and position.knownCost or 0
    local knownQty = type(position.knownQty) == "number" and position.knownQty or 0
    local exposureQty = type(position.exposureQty) == "number" and position.exposureQty or 0
    return (GC.L["%d · %d/%d covered"]):format(known, knownQty, exposureQty)
  end
  return position.knownCost
end

function GC.SellViewModel.ProfitText(position)
  if not position or position.profit == nil then return GC.L["Unknown"] end
  return position.profit
end

function GC.SellViewModel.SummaryText(summary)
  summary = summary or {}
  local partial = summary.partialCount or 0
  local unknown = summary.unknownCount or 0
  local profit = summary.profit
  local profitDetail
  local isPartial = false
  if profit == nil then
    local suffix = {}
    if partial > 0 then suffix[#suffix + 1] = (GC.L["%d partial"]):format(partial) end
    if unknown > 0 then suffix[#suffix + 1] = (GC.L["%d missing"]):format(unknown) end
    profit = GC.L["Unknown"] .. (#suffix > 0 and (" · " .. table.concat(suffix, " · ")) or "")
  else
    -- The number is a real total now (SellPositions.Summary sums only the positions that
    -- individually clear both gates), but it is still a partial one whenever something got
    -- left out -- say so here, the same way the "Unknown · N partial · M missing" string above
    -- carries its own detail, so the stat card's tooltip can show it without a second query.
    local n = summary.countedCount or 0
    local parts = { (GC.L["over %d position%s"]):format(n, n == 1 and "" or "s") }
    local noCost = summary.excludedNoCost or 0
    local noPrice = summary.excludedNoPrice or 0
    if noCost > 0 then parts[#parts + 1] = (GC.L["%d without cost"]):format(noCost) end
    if noPrice > 0 then parts[#parts + 1] = (GC.L["%d without a price"]):format(noPrice) end
    profitDetail = table.concat(parts, " · ")
    -- Item 2 (addon polish batch): a partial total painted with full confidence contradicts the
    -- comment above this one -- the number itself must carry a marker, not just the tooltip a
    -- player might never hover.
    isPartial = noCost > 0 or noPrice > 0
  end
  return { knownCost = summary.knownCost, listedValue = summary.listedValue, profit = profit,
    profitDetail = profitDetail, partial = isPartial, profitMarker = isPartial and "*" or nil }
end

-- How many price levels the expanded row shows. The book runs to 100 (Core/SellPositions'
-- boundedLevels), and nobody undercuts the 40th cheapest seller -- what a seller is deciding
-- is where to stand among the first handful. Levels beyond the cut are still counted in the
-- totals, so the header never claims the book is smaller than it is.
local BOOK_ROWS = 8

--- The live order book, as the expanded Sell row needs to read it.
--
-- Everything here comes off `position.levels`, which the addon has been fetching all along to
-- price with and never showed. Three things a seller cannot answer without it: what the
-- cheapest price that is NOT mine is, how much stock is sitting on it, and where my own price
-- would land in the queue. `ownerQty` is what makes the first one answerable -- the commodity
-- API aggregates a whole price point into one row, so the player's own units have to be
-- subtracted rather than the level skipped (see CheapestCompetingUnit for the same reasoning).
local function book(position)
  local levels = type(position.levels) == "table" and position.levels or nil
  if not levels or #levels == 0 then return nil end

  local rows, totalUnits, sellerLevels, running = {}, 0, 0, 0
  for i = 1, #levels do
    local level = levels[i]
    if type(level) == "table" and type(level.unitPrice) == "number" and level.unitPrice > 0 then
      local units = type(level.quantity) == "number" and level.quantity or 0
      local ownerUnits
      if type(level.ownerQty) == "number" then
        ownerUnits = level.ownerQty
      elseif level.ownerItem == true then
        ownerUnits = units -- unsplittable: the whole level reads as the player's own
      else
        ownerUnits = 0
      end
      totalUnits = totalUnits + units
      sellerLevels = sellerLevels + 1
      if #rows < BOOK_ROWS then
        running = running + units
        rows[#rows + 1] = { unit = level.unitPrice, units = units, ownerUnits = ownerUnits,
          mine = ownerUnits > 0, cumulative = running }
      end
    end
  end
  if #rows == 0 then return nil end

  -- Where the price GoldCap picked would sit. `postRecommendation` is the bag-stock answer
  -- (see its own comment in SellPositions) -- the same number Post lists at -- so this marks
  -- the row the seller is about to join rather than one they already hold.
  local yours = type(position.postRecommendation) == "table" and position.postRecommendation.unit or nil
  local yourRow
  if type(yours) == "number" and yours > 0 then
    for i = 1, #rows do
      if rows[i].unit >= yours then yourRow = i break end
    end
  end

  local widest = 0
  for i = 1, #rows do if rows[i].units > widest then widest = rows[i].units end end
  return {
    rows = rows, levels = sellerLevels, totalUnits = totalUnits, widest = widest,
    truncated = sellerLevels > #rows,
    yourUnit = yours, yourRow = yourRow,
    cheapestCompeting = GC.SellPositions and GC.SellPositions.CheapestCompetingUnit
      and GC.SellPositions.CheapestCompetingUnit(levels) or nil,
  }
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
  --
  -- `ids` rides along on every entry, collapsed or not -- the underlying acquisition batch ids
  -- a manual-cost removal needs, since the collapse itself already discards which physical
  -- batches it stands for. The merge key guarantees every id in one run shares one `source`,
  -- so a caller checking `source == "manual"` on the entry never has to also check each id.
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
          acquiredAtFirst = at, acquiredAtLast = at, ids = { last.id } }
        collapsed[#collapsed] = last
      end
      last.purchases = last.purchases + 1
      last.originalQty = last.originalQty + (batch.originalQty or 0)
      last.remainingQty = last.remainingQty + (batch.remainingQty or 0)
      last.allocatedQty = last.allocatedQty + (batch.allocatedQty or 0)
      last.totalCost = last.totalCost and batch.totalCost and (last.totalCost + batch.totalCost) or nil
      last.ids[#last.ids + 1] = batch.id
      local at = type(batch.acquiredAt) == "number" and batch.acquiredAt or nil
      if at then
        if not last.acquiredAtFirst or at < last.acquiredAtFirst then last.acquiredAtFirst = at end
        if not last.acquiredAtLast or at > last.acquiredAtLast then last.acquiredAtLast = at end
      end
    else
      batch.ids = { batch.id }
      collapsed[#collapsed + 1] = batch
    end
  end
  batches = collapsed
  local facts = {}
  if position.facts and position.facts.pendingPurchase then facts[#facts + 1] = GC.L["purchase pending exact cost"] end
  -- Overcut explains itself: the row shows a price above the cheapest ask, which every seller
  -- has been taught is wrong, so the reason and the queue ahead ride next to it. Bag stock
  -- carries the mode on postRecommendation; a listed lot's repost advice nests it under rec.
  -- Computed before the plain "undercut" fact so overcut can suppress it: being above the
  -- cheapest is the state GoldCap chose, not a fact worth restating as "undercut" too.
  local rec = position.postRecommendation
  if type(rec) ~= "table" or rec.mode ~= "overcut" then
    rec = position.recommendation
    if type(rec) == "table" and type(rec.rec) == "table" then rec = rec.rec end
  end
  local isOvercut = type(rec) == "table" and rec.mode == "overcut" and type(rec.ahead) == "number"
  if position.facts and position.facts.undercut and not isOvercut then facts[#facts + 1] = "undercut" end
  -- Which line held the price down is the interesting half of the sentence, so it is named:
  -- "the day's reach" is what the item's own floor actually climbs to (import R section), and
  -- the cheap quarter is the fallback wording for an import that carries no reach figure yet.
  -- Both spelled out rather than picking a key into a variable: a key has to be a literal at
  -- the lookup or the locale contract scanner cannot see it (the addon's engineering notes).
  if isOvercut and rec.capBy == "reach" then
    facts[#facts + 1] =
      (GC.L["above the cheapest, within the day's reach · %d units queued below"]):format(rec.ahead)
  elseif isOvercut then
    facts[#facts + 1] =
      (GC.L["above the cheapest, inside the cheap quarter · %d units queued below"]):format(rec.ahead)
  end
  if position.facts and position.facts.soldPending then facts[#facts + 1] = GC.L["sale proceeds pending"] end
  if position.unresolvedKind == "paid_sale" then facts[#facts + 1] = GC.L["paid sale unresolved"] end
  if position.unresolvedKind == "ambiguous_sale" then facts[#facts + 1] = GC.L["sale name ambiguous"] end
  if position.unresolvedKind == "unassigned_acquisition" then facts[#facts + 1] = GC.L["item variant unresolved"] end
  if position.unresolvedKind == "pending_purchase" then facts[#facts + 1] = GC.L["purchase identity unresolved"] end
  return {
    positionKey = position.positionKey, coverage = position.coverage, batches = batches,
    ownedLots = copy(position.ownedLots), displayMarketUnit = position.displayMarketUnit,
    marketState = marketState, marketFresh = marketFresh, marketStale = marketStale,
    quoteAge = position.quoteAge, ahead = position.ahead,
    sold = position.soldPerDay, days = position.outlook and position.outlook.days,
    recommendation = position.recommendation, note = GC.L["FIFO allocations"],
    coverageText = (GC.L["%d/%d covered"]):format(position.knownQty or 0, position.exposureQty or 0),
    pendingAcquisitions = copy(position.pendingAcquisitions),
    sellerEvidence = copy(position.sellerEvidence), facts = position.facts,
    factsText = #facts > 0 and table.concat(facts, " · ") or nil,
    book = book(position),
  }
end
