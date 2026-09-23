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

-- MY LOTS in three sections: lots worth cancelling, lots priced far under the market, and lots
-- to leave alone -- the three answers a seller opens the deck for. Cut from the cancel queue's
-- own entries (GC.CancelQueue.Build; `urgent` is its word for an underpriced lot) rather than
-- judged again here, so a heading's count and the dock's CANCEL n cannot disagree. Positions
-- keep the order they came in inside a section; an empty section is not returned at all.
local LOT_SECTIONS = { "undercut", "low", "hold" }
function GC.SellViewModel.LotSections(positions, cancelEntries)
  local class = {}
  for _, entry in ipairs(cancelEntries or {}) do
    local key = entry.positionKey
    if type(key) == "string" and (entry.urgent or not class[key]) then
      class[key] = entry.urgent and "low" or "undercut"
    end
  end
  local byId = {}
  for _, position in ipairs(positions or {}) do
    local id = class[position.positionKey] or "hold"
    byId[id] = byId[id] or { id = id, positions = {} }
    byId[id].positions[#byId[id].positions + 1] = position
  end
  local sections = {}
  for _, id in ipairs(LOT_SECTIONS) do
    if byId[id] then sections[#sections + 1] = byId[id] end
  end
  return sections
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

-- How many lines THE BOOK draws: the panel has room for eight and never scrolls (SellFrame's
-- DR.LINES). Levels beyond them are still counted in the totals, so the header never claims
-- the book is smaller than it is.
local BOOK_ROWS = 8
-- The most price levels the tab reads per item (UI/SellFrame.lua's quote driver reads through
-- this). A book of this many may have been cut there: a price past its last level has at least
-- all of it ahead, and an unknown amount more.
GC.SellViewModel.BOOK_READ_MAX = 100
-- A level holding this share of a day's sales or more is a wall: priced under it, a post sells
-- first; at or over it, the post waits for the whole wall to clear.
local WALL_SHARE = 0.25

-- How much of one price level is the player's own stock. Shared by the book below and by
-- Standing: both have to agree on what "not mine" means, or the row says one queue depth and
-- the panel under it another.
local function ownUnits(level, units)
  if type(level.ownerQty) == "number" then return level.ownerQty end
  if level.ownerItem == true then return units end -- unsplittable: the whole level is the player's
  return 0
end

--- Units a post at `unit` waits behind: every unit listed at or under that price that is not
-- the player's own. At an equal price the auction house sells the older listing first, so the
-- units already at the exact price are ahead too. THE BOOK's marker, the strategy line under
-- the price and a TO POST row's standing all say this one count. nil with no book or no price.
function GC.SellViewModel.UnitsAhead(levels, unit)
  if type(levels) ~= "table" or type(unit) ~= "number" or unit <= 0 then return nil end
  local ahead, seen = 0, 0
  for i = 1, #levels do
    local level = levels[i]
    if type(level) == "table" and type(level.unitPrice) == "number" and level.unitPrice > 0 then
      seen = seen + 1
      if level.unitPrice <= unit then
        local units = type(level.quantity) == "number" and level.quantity or 0
        ahead = ahead + math.max(0, units - ownUnits(level, units))
      end
    end
  end
  return seen > 0 and ahead or nil
end

local function isCommodity(position)
  return type(position.positionKey) == "string" and position.positionKey:find("^commodity:") ~= nil
end

-- Which levels THE BOOK draws for a commodity with a price of the player's: the cheapest
-- ones, a gap line for what is skipped, the levels just under the price, a marker for the price
-- itself (after the levels at an equal price -- it would join their tail), and the levels
-- above. Eight lines in all. Room the levels under the price do not need goes to those above.
local function ladder(valid, yours)
  local k = #valid + 1
  for i = 1, #valid do
    if valid[i].unit > yours then k = i break end
  end
  local below, aboveAvail = k - 1, #valid - k + 1
  local above = math.min(2, aboveAvail)
  local rest = BOOK_ROWS - 1 - above
  local rows = {}
  if below <= rest then
    above = math.min(aboveAvail, above + (rest - below))
    for i = 1, below do rows[#rows + 1] = valid[i] end
  else
    local cheap = math.floor((rest - 1) / 2)
    local near = rest - 1 - cheap
    for i = 1, cheap do rows[#rows + 1] = valid[i] end
    local units, prices = 0, 0
    for i = cheap + 1, below - near do units, prices = units + valid[i].units, prices + 1 end
    rows[#rows + 1] = { kind = "gap", units = units, prices = prices }
    for i = below - near + 1, below do rows[#rows + 1] = valid[i] end
  end
  rows[#rows + 1] = { kind = "yours", unit = yours }
  local yourRow = #rows
  for i = k, k + above - 1 do rows[#rows + 1] = valid[i] end
  return rows, yourRow
end

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

  local valid, totalUnits, running = {}, 0, 0
  for i = 1, #levels do
    local level = levels[i]
    if type(level) == "table" and type(level.unitPrice) == "number" and level.unitPrice > 0 then
      local units = type(level.quantity) == "number" and level.quantity or 0
      local ownerUnits = ownUnits(level, units)
      totalUnits = totalUnits + units
      running = running + units
      valid[#valid + 1] = { kind = "level", unit = level.unitPrice, units = units, ownerUnits = ownerUnits,
        mine = ownerUnits > 0, cumulative = running }
    end
  end
  if #valid == 0 then return nil end

  -- Where the price GoldCap picked would sit. `postRecommendation` is the bag-stock answer
  -- (see its own comment in SellPositions) -- the same number Post lists at, a typed price
  -- included -- so this marks the place the seller is about to join rather than one they hold.
  local yours = type(position.postRecommendation) == "table" and position.postRecommendation.unit or nil
  if type(yours) ~= "number" or yours <= 0 then yours = nil end
  local commodity = isCommodity(position)
  local sold = type(position.soldPerDay) == "number" and position.soldPerDay > 0 and position.soldPerDay or nil

  local rows, yourRow, ahead, pastRead, wallBelow, wallAbove, hoursToReach
  if commodity and yours then
    rows, yourRow = ladder(valid, yours)
    ahead = GC.SellViewModel.UnitsAhead(levels, yours)
    -- Past the last level read, and the read may have been cut: at least everything read is
    -- ahead, and nobody knows how much more. A book that ended before the cut is all of it.
    pastRead = yours > valid[#valid].unit and #levels >= GC.SellViewModel.BOOK_READ_MAX
    rows[yourRow].ahead, rows[yourRow].pastRead = ahead, pastRead
    -- Walls, on the stock that is not the player's own. With the day's sales unknown, the
    -- biggest level read is the one to name.
    local biggest = 0
    for i = 1, #valid do biggest = math.max(biggest, valid[i].units - valid[i].ownerUnits) end
    for i = 1, #valid do
      local competing = valid[i].units - valid[i].ownerUnits
      valid[i].wall = competing > 0 and (sold and competing >= sold * WALL_SHARE or (not sold and competing == biggest))
      if valid[i].wall then
        local wall = { unit = valid[i].unit, units = competing }
        if valid[i].unit <= yours then wallBelow = wall
        elseif not wallAbove then wallAbove = wall end
      end
    end
    if sold and ahead and ahead > 0 and not pastRead then hoursToReach = ahead / sold * 24 end
  else
    rows = {}
    for i = 1, math.min(#valid, BOOK_ROWS) do rows[i] = valid[i] end
    if yours then
      for i = 1, #rows do
        if rows[i].unit >= yours then yourRow = i break end
      end
    end
  end

  local widest, shown = 0, 0
  for i = 1, #rows do
    if rows[i].kind == "level" then
      shown = shown + 1
      if rows[i].units > widest then widest = rows[i].units end
    end
  end
  return {
    rows = rows, levels = #valid, totalUnits = totalUnits, widest = widest,
    truncated = #valid > shown, commodity = commodity,
    yourUnit = yours, yourRow = yourRow, ahead = ahead, pastRead = pastRead == true,
    wallBelow = wallBelow, wallAbove = wallAbove, hoursToReach = hoursToReach,
    cheapestCompeting = GC.SellPositions and GC.SellPositions.CheapestCompetingUnit
      and GC.SellPositions.CheapestCompetingUnit(levels) or nil,
  }
end

--- Where a price would stand in the live book, for the line under a row's price.
--
-- `ahead` is the stock queued at a strictly cheaper price that is NOT the player's own -- their
-- own cheaper lots are not competition, the same subtraction the book makes level by level.
-- `slot` is which price level the unit lands on, counting from the cheapest (1), so a row can
-- show a position in the queue without opening anything; one past the last level means the
-- price sits above everything the auction house returned. nil when there is no book or no
-- price: an absent answer must not read as "nobody is ahead of you".
--
-- `joining`: the price is about to be POSTED on a commodity, so it joins the tail of a level at
-- the same price and that level is ahead of it too (GC.SellViewModel.UnitsAhead) -- the count
-- THE BOOK's marker shows. A lot already standing at its price, or a realm item's lot, is not
-- joining anything: strictly cheaper, as before.
function GC.SellViewModel.Standing(position, unit, joining)
  local levels = type(position) == "table" and type(position.levels) == "table" and position.levels or nil
  if not levels or #levels == 0 or type(unit) ~= "number" or unit <= 0 then return nil end
  local ahead, slot, seen = 0, nil, 0
  for i = 1, #levels do
    local level = levels[i]
    if type(level) == "table" and type(level.unitPrice) == "number" and level.unitPrice > 0 then
      seen = seen + 1
      if level.unitPrice < unit then
        local units = type(level.quantity) == "number" and level.quantity or 0
        ahead = ahead + math.max(0, units - ownUnits(level, units))
      elseif not slot then
        slot = seen
      end
    end
  end
  if seen == 0 then return nil end
  if joining and isCommodity(position) then ahead = GC.SellViewModel.UnitsAhead(levels, unit) end
  return { ahead = ahead, slot = slot or seen + 1 }
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
  -- The count is THE BOOK's own (UnitsAhead): at or under the price, less the player's own --
  -- the engine's `ahead` counts strictly below, so the line and the marker could say two
  -- numbers about one price. The engine's figure stands in only where there is no book to count.
  if isOvercut then
    local ahead = GC.SellViewModel.UnitsAhead(position.levels, rec.unit) or rec.ahead
    ahead = GC.Util and GC.Util.FormatCount and GC.Util.FormatCount(ahead) or tostring(ahead)
    if rec.capBy == "reach" then
      facts[#facts + 1] =
        (GC.L["above the cheapest, within the day's reach · %s units ahead of you"]):format(ahead)
    else
      facts[#facts + 1] =
        (GC.L["above the cheapest, inside the cheap quarter · %s units ahead of you"]):format(ahead)
    end
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
