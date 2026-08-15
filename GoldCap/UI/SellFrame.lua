local _, GC = ...

GC.Sell = GC.Sell or {}

local Theme = GC.Theme
local ROW_HEIGHT, ROW_WIDTH
local SELL_BAGS = { 0, 1, 2, 3, 4, 5 }
local POST_DURATION = 2
local QUOTE_STALE_SECONDS = (GC.QuoteCache and GC.QuoteCache.MAX_AGE_SECONDS) or 10
local POST_TIMEOUT_SECONDS, REPOST_ARM_SECONDS, REPOST_TIMEOUT_SECONDS = 8, 3, 10
local MAX_EXACT = 9007199254740991

-- The positions module owns all accounting and action-plan decisions.  This file only joins
-- live AH observations, a cached quote stream, and widgets around that single model.
local COLUMNS = {
  { key = "item", flex = true, min = 190 },
  { key = "cost", w = 88, num = true },
  { key = "listed", w = 88, num = true },
  { key = "market", w = 72, num = true, optional = true },
  { key = "profit", w = 82, num = true, bold = true },
  { key = "status", w = 98 },
  { key = "expand", w = 22 },
}

local container, content, statusOwner
local rows, positions, ownedLots, quotes = {}, {}, {}, {}
local expanded, filterMode = {}, "all"
local refresh = { generation = 0, phase = "idle", queue = {}, index = 0, pending = nil, awaiting = nil, drain = {} }
local quoteTimeoutToken = 0
local postingRow, postingPin, postTimeoutToken
local repostingRow, repostPin, repostArmToken = nil, nil, 0
local renderGeneration = 0
local quoteExpiryGeneration = 0
local manualRepairNonce = 0

local function restorePostRow(row)
  if not row then return end
  row.postStage = nil
  if row.action then row.action:Enable(); row.action:SetLabel("Post") end
end

local function restoreRepostRow(row)
  if not row then return end
  row.repostStage, row.repostReady = nil, nil
  if row.action then row.action:Enable(); row.action:SetLabel("Repost") end
end

local function disarmPost()
  local row = postingRow
  postingRow, postingPin = nil, nil
  postTimeoutToken = (postTimeoutToken or 0) + 1
  restorePostRow(row)
end

local function disarmRepost()
  local row = repostingRow
  repostingRow, repostPin = nil, nil
  repostArmToken = (repostArmToken or 0) + 1
  restoreRepostRow(row)
end

local function setStatus(text)
  if statusOwner and statusOwner.status then statusOwner.status:SetText(text) end
end

local function setColor(fontString, color)
  if fontString and color then fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
end

local function formatAmount(amount)
  if amount == nil then return "Unknown" end
  if amount < 0 then return "-" .. GetCoinTextureString(-amount) end
  return GetCoinTextureString(amount)
end

local function formatCell(value)
  return type(value) == "number" and formatAmount(value) or tostring(value or "")
end

local function recommendationText(recommendation)
  if type(recommendation) == "string" then return recommendation end
  if type(recommendation) ~= "table" then return "" end
  local action = recommendation.action
  if type(action) ~= "string" or action == "" then action = "post" end
  action = action:sub(1, 1):upper() .. action:sub(2)
  local nested = recommendation.rec
  local unit = nested and nested.unit or recommendation.unit
  local breakeven = nested and nested.breakeven or recommendation.breakeven
  local reason = type(recommendation.reason) == "string" and recommendation.reason
    or (type(recommendation.mode) == "string" and recommendation.mode or nil)
  local suffix = unit and (" @ " .. formatCell(unit)) or ""
  if recommendation.belowCost then reason = reason and (reason .. " · below cost") or "below cost" end
  local floor = breakeven and (" · breakeven " .. formatCell(breakeven)) or ""
  return action .. (reason and (" (" .. reason .. ")") or "") .. suffix .. floor
end

local function exact(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

local function safeAdd(left, right)
  if not exact(left) or not exact(right) or left > MAX_EXACT - right then return nil end
  return left + right
end

local function safeMultiply(left, right)
  if not exact(left) or not exact(right) or (left ~= 0 and right > math.floor(MAX_EXACT / left)) then return nil end
  return left * right
end

local function context()
  return GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
end

local function activeScope(position)
  local scope = context()
  if type(position) ~= "table" or type(position.positionKey) ~= "string"
      or type(scope) ~= "table" or type(scope.char) ~= "string" or scope.char == ""
      or type(scope.region) ~= "string" or scope.region == "" then return nil, nil end
  local scopeKey
  if GC.Acquisitions and GC.Acquisitions.ScopeKey then
    scopeKey = GC.Acquisitions.ScopeKey(position.positionKey, scope)
  else
    scopeKey = table.concat({ scope.region, scope.char, position.positionKey }, "\1")
  end
  if scopeKey ~= position.scopeKey then return nil, nil end
  return scope, scopeKey
end

local function exactRenderEntry(row, pin)
  return row and pin and type(row.renderEntryID) == "string" and row.renderEntryID ~= ""
    and row.renderEntryID == pin.renderEntryID and pin.row == row and pin.action == row.action
    and pin.position == row.position
end

local function itemName(itemID)
  if C_Item and C_Item.GetItemNameByID then
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return ("Item %d"):format(itemID or 0)
end

local function quoteDriver()
  local function boundedLevels(itemID, commodity)
    local levels, count = {}, commodity and C_AuctionHouse.GetNumCommoditySearchResults(itemID)
      or C_AuctionHouse.GetNumItemSearchResults(C_AuctionHouse.MakeItemKey(itemID))
    for i = 1, math.min(count or 0, 100) do
      local info = commodity and C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        or C_AuctionHouse.GetItemSearchResultInfo(C_AuctionHouse.MakeItemKey(itemID), i)
      local unit = info and (commodity and info.unitPrice
        or (info.buyoutAmount and info.quantity and info.quantity > 0 and math.floor(info.buyoutAmount / info.quantity)))
      if unit and unit > 0 then levels[#levels + 1] = { unitPrice = unit, quantity = info.quantity or 0 } end
    end
    return #levels > 0 and levels or nil
  end
  return {
    isReady = function() return C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and C_AuctionHouse.IsThrottledMessageSystemReady() end,
    keyInfo = function(itemID)
      return C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
    end,
    send = function(itemID)
      local key = C_AuctionHouse.MakeItemKey(itemID)
      local info = C_AuctionHouse.GetItemKeyInfo(key)
      if info and info.isCommodity then
        C_AuctionHouse.SendSearchQuery(key, {}, false)
      else
        C_AuctionHouse.SendSearchQuery(key, { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }, false)
      end
    end,
    item = function(itemID)
      local info = C_AuctionHouse.GetItemSearchResultInfo(C_AuctionHouse.MakeItemKey(itemID), 1)
      return info and info.buyoutAmount and info.quantity and info.quantity > 0 and math.floor(info.buyoutAmount / info.quantity) or nil
    end,
    commodity = function(itemID)
      local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
      return info and info.unitPrice or nil
    end,
    itemLevels = function(itemID) return boundedLevels(itemID, false) end,
    commodityLevels = function(itemID) return boundedLevels(itemID, true) end,
  }
end
local driver = quoteDriver()

local function composePositions()
  local scope = context()
  local stats = {}
  for _, lot in ipairs(ownedLots) do
    stats[lot.itemID] = GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(lot.itemID) or nil
  end
  local batches = GC.Acquisitions and GC.Acquisitions.GetActive and GC.Acquisitions.GetActive(scope) or {}
  for _, batch in ipairs(batches) do
    stats[batch.itemID] = stats[batch.itemID] or (GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(batch.itemID) or nil)
  end
  local pending = GC.Acquisitions and GC.Acquisitions.GetPending and GC.Acquisitions.GetPending(scope) or {}
  local activities = GC.Acquisitions and GC.Acquisitions.GetActivities and GC.Acquisitions.GetActivities(scope) or {}
  local consumed = {}
  for _, realized in ipairs(GC.Acquisitions and GC.Acquisitions.GetRealized and GC.Acquisitions.GetRealized(scope) or {}) do
    if realized.evidenceKey then consumed[realized.evidenceKey] = true end
  end
  local sellerEvidence = {}
  for _, entry in ipairs(GC.Ledger and GC.Ledger.GetEntries and GC.Ledger.GetEntries() or {}) do
    if entry.kind == "sale" and entry.source == "mail" and entry.char == scope.char
        and entry.region == scope.region and not consumed[entry.key] then
      sellerEvidence[#sellerEvidence + 1] = entry
    end
  end
  positions = GC.SellPositions.Build({ acquisitions = batches, pendingAcquisitions = pending,
    activities = activities, sellerEvidence = sellerEvidence, ownedLots = ownedLots,
    quotes = quotes, statsByItemID = stats, context = scope, now = time() })
  for _, position in ipairs(positions) do
    if position.itemID and not position.itemName then position.itemName = itemName(position.itemID) end
  end
end

local function uniqueQuoteItemIDs()
  local seen, result = {}, {}
  for _, position in ipairs(positions) do
    if not position.unresolved and position.itemID and not seen[position.itemID] then
      seen[position.itemID], result[#result + 1] = true, position.itemID
    end
  end
  return result
end

local function renderRows() end

local function scheduleQuoteExpiry()
  quoteExpiryGeneration = quoteExpiryGeneration + 1
  local token = quoteExpiryGeneration
  if not (C_Timer and C_Timer.After) then return end
  local delay
  for _, position in ipairs(positions) do
    if position.freshMarketUnit and type(position.quoteAge) == "number" then
      local remaining = QUOTE_STALE_SECONDS - position.quoteAge + 1
      if remaining > 0 and (not delay or remaining < delay) then delay = remaining end
    end
  end
  if not delay then return end
  C_Timer.After(delay, function()
    if token ~= quoteExpiryGeneration then return end
    composePositions()
    renderRows()
  end)
end

local function finishQuoteWalk()
  refresh.phase = "done"
  refresh.pending, refresh.awaiting = nil, nil
  setStatus("Updated just now")
  renderRows()
end

local function failPendingQuote(pending, awaitTerminal)
  if refresh.pending ~= pending or pending.generation ~= refresh.generation then return end
  if awaitTerminal then
    refresh.drain[pending.kind .. ":" .. pending.itemID] = {
      abandonedGeneration = pending.generation,
      terminals = 1,
    }
  end
  quotes[pending.itemID] = nil
  refresh.pending = nil
  refresh.phase = "error"
  setStatus("Refresh failed")
end

local function scheduleQuoteTimeout(pending)
  if not (C_Timer and C_Timer.After) then return end
  quoteTimeoutToken = quoteTimeoutToken + 1
  local token = quoteTimeoutToken
  C_Timer.After(QUOTE_STALE_SECONDS, function()
    if token == quoteTimeoutToken then failPendingQuote(pending, true) end
  end)
end

local function advanceQuote()
  if refresh.phase ~= "pricing" and refresh.phase ~= "waiting_key" then return end
  if refresh.pending then return end
  if refresh.index >= #refresh.queue then return finishQuoteWalk() end
  if GC.Sniper and GC.Sniper.IsBusy and GC.Sniper.IsBusy() then return end
  if not driver.isReady() then return end
  local itemID = refresh.awaiting or refresh.queue[refresh.index + 1]
  if driver.keyInfo(itemID) then
    local info = driver.keyInfo(itemID)
    local kind = info.isCommodity and "commodity" or "item"
    local tombstone = refresh.drain[kind .. ":" .. itemID]
    if tombstone then
      tombstone.resumeGeneration = refresh.generation
      refresh.phase = "draining"
      setStatus("Refresh waiting for prior result")
      return
    end
    refresh.awaiting = nil
    refresh.index = refresh.index + 1
    refresh.pending = { itemID = itemID, kind = kind, generation = refresh.generation, at = time() }
    refresh.phase = "waiting_result"
    setStatus(("Pricing %d/%d…"):format(refresh.index, #refresh.queue))
    driver.send(itemID)
    scheduleQuoteTimeout(refresh.pending)
  else
    refresh.awaiting, refresh.phase = itemID, "waiting_key"
  end
end

local function beginQuoteWalk()
  refresh.queue, refresh.index, refresh.phase, refresh.pending, refresh.awaiting = uniqueQuoteItemIDs(), 0, "pricing", nil, nil
  if #refresh.queue == 0 then return finishQuoteWalk() end
  advanceQuote()
end

local function requestOwnedAuctions()
  if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions and GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen() then
    if not driver.isReady() then return false, true end
    C_AuctionHouse.QueryOwnedAuctions({})
    return true, false
  end
  return false, false
end

local function onOwnedAuctionsReady()
  composePositions()
  renderRows()
  if refresh.phase == "owned" then
    beginQuoteWalk()
  end
end

function GC.Sell.OnOwnedAuctions()
  local auctions = C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and C_AuctionHouse.GetOwnedAuctions() or {}
  ownedLots = GC.SellPositions.NormalizeOwnedLots(auctions, time())
  local scope = context()
  if GC.Acquisitions and GC.Acquisitions.ObserveOwnedPosition and scope then
    for _, lot in ipairs(ownedLots) do
      GC.Acquisitions.ObserveOwnedPosition(lot.positionKey, lot.itemID, itemName(lot.itemID), scope.char, scope.region, time())
    end
    -- Pure composition is allowed to display a currently unique variant, but
    -- it must never make that inference durable.  The controller has the
    -- current owned-lot evidence and has just persisted matching activity, so
    -- it may ask the explicit fail-closed binding API to bind an item-only
    -- legacy batch only when every candidate and activity agrees on one key.
    if GC.Acquisitions.BindItemOnly and GC.Acquisitions.GetActive then
      for _, batch in ipairs(GC.Acquisitions.GetActive(scope)) do
        if not batch.positionKey then
          local candidates = {}
          for _, lot in ipairs(ownedLots) do
            if lot.itemID == batch.itemID then
              candidates[#candidates + 1] = { positionKey = lot.positionKey, itemID = lot.itemID,
                character = scope.char, region = scope.region }
            end
          end
          if #candidates > 0 then GC.Acquisitions.BindItemOnly(batch.id, candidates, scope) end
        end
      end
    end
  end
  if repostingRow and repostPin then
    local pinnedScope, scopeKey = activeScope(repostPin.position)
    local stillOwned = pinnedScope and scopeKey == repostPin.scopeKey
    if stillOwned then
      stillOwned = false
      for _, lot in ipairs(ownedLots) do
        if lot.positionKey == repostPin.positionKey and lot.itemID == repostPin.itemID
            and lot.auctionID == repostPin.auctionID and lot.quantity == repostPin.quantity
            and lot.unitPrice == repostPin.listedUnit then
          stillOwned = true
          break
        end
      end
    end
    if not stillOwned then
      disarmRepost()
      setStatus("Lot cancelled; wait for it to return to bags")
    end
  end
  onOwnedAuctionsReady()
end

function GC.Sell.OnThrottleReady()
  if refresh.phase == "waiting_owned" then
    local sent, waiting = requestOwnedAuctions()
    if sent then
      refresh.phase = "owned"
    elseif not waiting then
      refresh.phase = "idle"
      setStatus("Auction House is not open")
    end
    return
  end
  if refresh.pending and time() - refresh.pending.at > QUOTE_STALE_SECONDS then
    failPendingQuote(refresh.pending, true)
    return
  end
  advanceQuote()
end

function GC.Sell.OnItemKeyInfo(itemID)
  if refresh.phase == "waiting_key" and refresh.awaiting == itemID then advanceQuote() end
end

local function quoteResolved(kind, itemID, unit, levels)
  local drainKey = kind .. ":" .. itemID
  local tombstone = refresh.drain[drainKey]
  if tombstone then
    tombstone.terminals = tombstone.terminals - 1
    local resume = tombstone.terminals <= 0 and tombstone.resumeGeneration == refresh.generation
      and refresh.phase == "draining"
    if tombstone.terminals <= 0 then refresh.drain[drainKey] = nil end
    if resume then
      refresh.phase = "pricing"
      advanceQuote()
    elseif refresh.phase == "error" then
      refresh.phase = "idle"
    end
    return
  end
  local pending = refresh.pending
  if not pending or pending.kind ~= kind or pending.itemID ~= itemID or pending.generation ~= refresh.generation then return end
  if not exact(unit) or unit <= 0 then
    failPendingQuote(pending, false)
    return
  end
  refresh.pending = nil
  refresh.phase = "pricing"
  GC.QuoteCache.Set(quotes, itemID, unit, time())
  if unit and quotes[itemID] then quotes[itemID].levels = levels end
  composePositions()
  renderRows()
  advanceQuote()
end

function GC.Sell.OnItemSearchResults(itemID) quoteResolved("item", itemID, driver.item(itemID), driver.itemLevels(itemID)) end
function GC.Sell.OnCommoditySearchResults(itemID) quoteResolved("commodity", itemID, driver.commodity(itemID), driver.commodityLevels(itemID)) end

local function freshQuote(position)
  local quote = GC.QuoteCache.Fresh(quotes, position.itemID, time())
  if type(quote) ~= "table" or not exact(quote.unit) or quote.unit <= 0 or not exact(quote.at) then return nil end
  return quote
end

local function normalizedPositionKey(itemID, link)
  if type(link) ~= "string" or link:find("battlepet:", 1, true) then return nil end
  local payload = link:match("|H(item:[^|]+)|h") or link:match("^(item:.-)$")
  if not payload then return nil end
  local fields, start = {}, 1
  while true do
    local colon = payload:find(":", start, true)
    if not colon then fields[#fields + 1] = payload:sub(start); break end
    fields[#fields + 1], start = payload:sub(start, colon - 1), colon + 1
  end
  local actualID = tonumber(fields[2])
  if actualID ~= itemID then return nil end
  local bonusCount = tonumber(fields[14])
  if #fields < 14 or bonusCount == nil or bonusCount ~= 0 then return nil end
  local level = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
  local suffix = tonumber(fields[8])
  if type(level) ~= "number" or suffix == nil then return nil end
  return ("item:%d:%d:%d:%d"):format(itemID, math.floor(level), suffix, 0)
end

local function liveBagState(position, requiredQty)
  local total, matchedBag, matchedSlot, matchedStack = 0, nil, nil, nil
  local commodity = type(position.positionKey) == "string" and position.positionKey:match("^commodity:")
  for _, bag in ipairs(SELL_BAGS) do
    local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == position.itemID then
        local qty = info.stackCount or 1
        if exact(qty) and qty > 0 and commodity then
          total = safeAdd(total, qty)
          if not total then return { itemID = position.itemID, exactQty = nil } end
          if not matchedBag then matchedBag, matchedSlot, matchedStack = bag, slot, qty end
        else
          local link = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
          if exact(qty) and qty > 0 and normalizedPositionKey(position.itemID, link) == position.positionKey then
            if qty > total then total = qty end
            if (requiredQty and qty >= requiredQty and not matchedBag) or (not requiredQty and qty >= (matchedStack or 0)) then
              matchedBag, matchedSlot, matchedStack = bag, slot, qty
            end
          end
        end
      end
    end
  end
  return { itemID = position.itemID, exactQty = total, positionKey = matchedBag and position.positionKey or nil,
    bag = matchedBag, slot = matchedSlot, stackQty = matchedStack }
end

local function startQuoteRefreshFor(_)
  GC.Sell.Refresh()
end

local function currentPosition(positionKey)
  for _, position in ipairs(positions) do
    if position.positionKey == positionKey then return position end
  end
  return nil
end

local function schedulePostTimeout(row)
  if not (C_Timer and C_Timer.After) then return end
  postTimeoutToken = (postTimeoutToken or 0) + 1
  local token = postTimeoutToken
  C_Timer.After(POST_TIMEOUT_SECONDS, function()
    if token == postTimeoutToken and postingRow == row
        and (row.postStage == "posting" or row.postStage == "confirm" or row.postStage == "confirming") then
      disarmPost()
      setStatus("Posting timed out")
    end
  end)
end

local function onPostClick(row)
  local position = row.position
  local quote = freshQuote(position)
  if not quote then
    if postingRow == row then disarmPost() end
    -- Same silent first click as Repost had: without this the button looks broken.
    setStatus("Fetching a fresh price for this item — press Post again in a moment")
    startQuoteRefreshFor(position); return
  end
  if postingRow and postingRow ~= row then
    setStatus("Finish the pending post first")
    return
  end
  if postingRow == row and row.postStage ~= "confirm" then return end
  if row.postStage == "confirm" then
    local pin = postingPin
    local scope, scopeKey = activeScope(position)
    local bagState = pin and liveBagState(position, pin.isCommodity and nil or pin.quantity) or nil
    local sameQuote = pin and quote == pin.quote and quote.at == pin.quoteAt and quote.unit == pin.quoteUnit
    local checkedTotal = pin and safeMultiply(pin.unitPrice, pin.quantity) or nil
    local confirmAvailable = pin and C_AuctionHouse
      and ((pin.isCommodity and C_AuctionHouse.ConfirmPostCommodity)
        or (not pin.isCommodity and C_AuctionHouse.ConfirmPostItem))
    if not exactRenderEntry(row, pin) or not scope or scopeKey ~= pin.scopeKey
        or pin.positionKey ~= position.positionKey or pin.scopeKey ~= position.scopeKey
        or pin.itemID ~= position.itemID or pin.variantKey ~= position.positionKey
        or not exact(pin.quantity) or pin.quantity <= 0 or not exact(pin.unitPrice) or pin.unitPrice <= 0
        or not pin.location or not bagState or bagState.itemID ~= pin.itemID
        or bagState.positionKey ~= pin.variantKey or bagState.bag ~= pin.bag or bagState.slot ~= pin.slot
        or not exact(bagState.exactQty) or bagState.exactQty < pin.quantity
        or not checkedTotal or checkedTotal ~= pin.total
        or (not pin.isCommodity and pin.buyout ~= checkedTotal)
        or not sameQuote or not confirmAvailable then
      disarmPost()
      if not sameQuote then startQuoteRefreshFor(position)
      else setStatus("Post confirmation expired") end
      return
    end
    row.postStage = "confirming"; row.action:Disable(); setStatus("Posting…")
    if pin.isCommodity then
      C_AuctionHouse.ConfirmPostCommodity(pin.location, POST_DURATION, pin.quantity, pin.unitPrice)
    else
      C_AuctionHouse.ConfirmPostItem(pin.location, POST_DURATION, pin.quantity, nil, pin.buyout)
    end
    return
  end
  local bagState = liveBagState(position)
  local plan, reason = GC.SellPositions.BuildPostPlan(position, bagState, { unit = quote.unit, fresh = true })
  if not plan then
    setStatus(reason == "ambiguous_variant" and "No exact bag variant" or "Cannot post this position")
    return
  end
  local scope, scopeKey = activeScope(position)
  if not scope or type(row.renderEntryID) ~= "string" or row.renderEntryID == ""
      or plan.positionKey ~= position.positionKey or plan.scopeKey ~= position.scopeKey
      or plan.scopeKey ~= scopeKey or plan.itemID ~= position.itemID
      or not exact(plan.quantity) or plan.quantity <= 0 or not exact(plan.unitPrice) or plan.unitPrice <= 0 then
    setStatus("Cannot post this position")
    return
  end
  local info = driver.keyInfo(plan.itemID)
  if not info then setStatus("No exact auction key"); return end
  if (info.isCommodity and not (C_AuctionHouse and C_AuctionHouse.PostCommodity))
      or (not info.isCommodity and not (C_AuctionHouse and C_AuctionHouse.PostItem)) then
    setStatus("Posting unavailable")
    return
  end
  local buyout = not info.isCommodity and safeMultiply(plan.unitPrice, plan.quantity) or nil
  if not info.isCommodity and not buyout then setStatus("Cannot post this position"); return end
  local commodityTotal = info.isCommodity and safeMultiply(plan.unitPrice, plan.quantity) or nil
  if info.isCommodity and (not commodityTotal or not exact(bagState.exactQty) or bagState.exactQty < plan.quantity) then
    setStatus("No exact bag stack")
    return
  end
  if not ItemLocation or not ItemLocation.CreateFromBagAndSlot or not bagState.bag or not bagState.slot then
    setStatus("No exact bag stack")
    return
  end
  if not info.isCommodity then
    bagState = liveBagState(position, plan.quantity)
    if not bagState.bag or not bagState.slot or not bagState.stackQty or bagState.stackQty < plan.quantity then
      setStatus("No exact bag stack")
      return
    end
  end
  local location = ItemLocation:CreateFromBagAndSlot(bagState.bag, bagState.slot)
  if not location then setStatus("No exact bag stack"); return end
  postingRow = row
  postingPin = { scopeKey = plan.scopeKey, positionKey = plan.positionKey, itemID = plan.itemID,
    variantKey = bagState.positionKey, quantity = plan.quantity, bag = bagState.bag, slot = bagState.slot,
    quoteAt = quote.at, quoteUnit = quote.unit, quote = quote, location = location, isCommodity = info.isCommodity,
    unitPrice = plan.unitPrice, buyout = buyout, total = commodityTotal or buyout, row = row, action = row.action,
    position = position, renderEntryID = row.renderEntryID, character = scope.char, region = scope.region }
  row.postStage = "posting"; row.action:Disable(); setStatus("Posting…")
  local needsConfirmation
  if info.isCommodity then
    needsConfirmation = C_AuctionHouse.PostCommodity(location, POST_DURATION, plan.quantity, plan.unitPrice)
  else
    needsConfirmation = C_AuctionHouse.PostItem(location, POST_DURATION, plan.quantity, nil, buyout)
  end
  if needsConfirmation then
    row.postStage = "confirm"; row.action:Enable(); row.action:SetLabel("Confirm")
    setStatus("Click Confirm to post")
  end
  schedulePostTimeout(row)
end

local function onRepostClick(row, auctionID)
  local position = row.position
  if repostingRow and repostingRow ~= row then
    disarmRepost()
    setStatus("Previous repost selection cleared")
    return
  end
  local quote = freshQuote(position)
  if not quote then
    if repostingRow == row then disarmRepost() end
    -- Previously this refreshed the quote and returned in silence, so a first click looked like
    -- a dead button. Say what is happening; the click that follows is the one that arms.
    setStatus("Fetching a fresh price for this lot — press Repost again in a moment")
    startQuoteRefreshFor(position); return
  end
  if row.repostStage == "armed" then
    if not row.repostReady then return end
    local pin = repostPin
    if not exactRenderEntry(row, pin) then
      disarmRepost()
      setStatus("Repost confirmation expired")
      return
    end
    local scope, scopeKey = pin and activeScope(pin.position) or nil, nil
    if scope then
      if GC.Acquisitions and GC.Acquisitions.ScopeKey then
        scopeKey = GC.Acquisitions.ScopeKey(pin.positionKey, scope)
      else
        scopeKey = table.concat({ scope.region, scope.char, pin.positionKey }, "\1")
      end
    end
    if not (C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and GC.SellPositions.NormalizeOwnedLots) then
      disarmRepost()
      setStatus("Repost confirmation expired")
      return
    end
    ownedLots = GC.SellPositions.NormalizeOwnedLots(C_AuctionHouse.GetOwnedAuctions() or {}, time())
    composePositions()
    local livePosition = currentPosition(pin.positionKey)
    local current
    for _, candidate in ipairs(livePosition and livePosition.scopeKey == pin.scopeKey
        and livePosition.itemID == pin.itemID and livePosition.ownedLots or {}) do
      if candidate.auctionID == pin.auctionID and candidate.quantity == pin.quantity and candidate.unitPrice == pin.listedUnit then current = candidate break end
    end
    local plan = current and GC.SellPositions.BuildRepostPlan(livePosition, pin.auctionID, { unit = quote.unit, fresh = true })
    if not exactRenderEntry(row, pin) or not scope or scopeKey ~= pin.scopeKey
        or pin.position ~= position or pin.positionKey ~= position.positionKey
        or pin.scopeKey ~= position.scopeKey or pin.itemID ~= position.itemID
        or not plan or plan.positionKey ~= pin.positionKey or plan.scopeKey ~= pin.scopeKey
        or plan.itemID ~= pin.itemID or plan.auctionID ~= pin.auctionID
        or plan.quantity ~= pin.quantity or plan.unitPrice ~= pin.quoteUnit
        or quote ~= pin.quote or quote.at ~= pin.quoteAt or quote.unit ~= pin.quoteUnit
        or not (C_AuctionHouse and C_AuctionHouse.CancelAuction) then
      disarmRepost()
      setStatus("Repost confirmation expired")
      return
    end
    row.repostStage = "cancelling"; row.action:Disable()
    C_AuctionHouse.CancelAuction(plan.auctionID)
    setStatus("Cancelling lot…")
    if C_Timer and C_Timer.After then
      local token = repostArmToken
      C_Timer.After(REPOST_TIMEOUT_SECONDS, function()
        if token == repostArmToken and repostingRow == row and row.repostStage == "cancelling" then
          disarmRepost()
          setStatus("Cancel timed out")
        end
      end)
    end
    return
  end
  local plan = GC.SellPositions.BuildRepostPlan(position, auctionID, { unit = quote.unit, fresh = true })
  local scope, scopeKey = activeScope(position)
  if not plan or not scope or type(row.renderEntryID) ~= "string" or row.renderEntryID == ""
      or plan.positionKey ~= position.positionKey or plan.scopeKey ~= position.scopeKey
      or plan.scopeKey ~= scopeKey or plan.itemID ~= position.itemID
      or not exact(plan.auctionID) or plan.auctionID <= 0 or plan.auctionID ~= auctionID
      or not exact(plan.quantity) or plan.quantity <= 0
      or not exact(plan.unitPrice) or plan.unitPrice <= 0 then
    setStatus("Cannot repost this lot")
    return
  end
  local lot
  for _, candidate in ipairs(position.ownedLots or {}) do if candidate.auctionID == plan.auctionID then lot = candidate break end end
  if not lot or lot.quantity ~= plan.quantity or not exact(lot.unitPrice) or lot.unitPrice <= 0 then
    setStatus("Cannot repost this lot")
    return
  end
  repostingRow, repostPin = row, { scopeKey = plan.scopeKey, positionKey = plan.positionKey, auctionID = plan.auctionID,
    itemID = plan.itemID, quantity = plan.quantity, listedUnit = lot.unitPrice,
    quoteAt = quote.at, quoteUnit = quote.unit, quote = quote, row = row, action = row.action,
    position = position, renderEntryID = row.renderEntryID, character = scope.char, region = scope.region }
  row.repostStage, row.repostReady = "armed", false
  row.action:Disable(); row.action:SetLabel("Cancel lot?")
  setStatus("Cancel this lot and lose its deposit — click again to confirm")
  repostArmToken = repostArmToken + 1
  local token = repostArmToken
  if C_Timer and C_Timer.After then
    C_Timer.After(REPOST_ARM_SECONDS, function()
      if token == repostArmToken and repostingRow == row and row.repostStage == "armed" then row.repostReady = true; row.action:Enable() end
    end)
    C_Timer.After(REPOST_TIMEOUT_SECONDS, function()
      if token == repostArmToken and repostingRow == row and row.repostStage == "armed" then
        disarmRepost()
        setStatus("Repost confirmation expired")
      end
    end)
  end
end

function GC.Sell.OnAuctionCreated()
  local pin, row = postingPin, postingRow
  if not pin or not row then return end
  local valid = exactRenderEntry(row, pin) and (row.postStage == "posting" or row.postStage == "confirming")
    and pin.positionKey == row.position.positionKey and pin.scopeKey == row.position.scopeKey
    and pin.itemID == row.position.itemID and exact(pin.quantity) and pin.quantity > 0
    and exact(pin.total) and pin.total > 0 and type(pin.character) == "string" and pin.character ~= ""
    and type(pin.region) == "string" and pin.region ~= ""
  if valid and GC.Acquisitions and GC.Acquisitions.RecordPost then
    GC.Acquisitions.RecordPost(pin.positionKey, pin.itemID, itemName(pin.itemID), pin.character, pin.region, pin.quantity, time())
  end
  disarmPost()
  GC.Sell.Refresh()
end

function GC.Sell.OnPostError()
  disarmPost()
  disarmRepost()
  setStatus("Posting failed")
  GC.Sell.Refresh()
end

local function setDialogError(dialog, text)
  dialog.error:SetText(text or "")
  if text and text ~= "" then dialog.error:Show() else dialog.error:Hide() end
end

local function dialogNumber(edit)
  local value = tonumber(edit:GetText())
  return value and value == math.floor(value) and value or nil
end

local function dialogExactPositive(edit)
  local value = dialogNumber(edit)
  return exact(value) and value > 0 and value or nil
end

local function pendingRepairFor(position, scope)
  local pending = position and position.pendingAcquisitions
  if type(pending) ~= "table" or #pending ~= 1 or type(scope) ~= "table" then return nil end
  local row = pending[1]
  if type(row) ~= "table" or type(row.id) ~= "string" or row.id == ""
      or row.itemID ~= position.itemID or row.positionKey ~= position.positionKey
      or row.character ~= scope.char or row.region ~= scope.region
      or not exact(row.quantity) or row.quantity <= 0 then
    return nil
  end
  return row
end

local function canSetCost(position)
  if not position or position.unresolved or type(position.positionKey) ~= "string" then return false end
  local pending = position.pendingAcquisitions
  if type(pending) ~= "table" or #pending == 0 then return true end
  local scope = activeScope(position)
  return pendingRepairFor(position, scope) ~= nil
end

local function openCostDialog(position)
  local dialog = container.costDialog
  local missing = math.max(0, (position.exposureQty or 0) - (position.knownQty or 0))
  if missing < 1 then return end
  local scope = activeScope(position)
  local pending = pendingRepairFor(position, scope)
  if type(position.pendingAcquisitions) == "table" and #position.pendingAcquisitions > 0 and not pending then return end
  if pending then missing = math.min(missing, pending.quantity) end
  dialog.position, dialog.maximum, dialog.pendingRepair = position, missing, pending
  manualRepairNonce = manualRepairNonce + 1
  dialog.repairID = pending and table.concat({ "manual-repair", pending.id, tostring(time()),
    tostring(manualRepairNonce) }, "\1") or nil
  dialog.submitted, dialog.costMode, dialog.syncing = false, nil, false
  dialog.quantity:SetText("1")
  dialog.unit:SetText("")
  dialog.total:SetText("")
  setDialogError(dialog)
  dialog:Show()
end

local function confirmCostDialog(dialog)
  if dialog.submitted then return end
  local quantity, total = dialogExactPositive(dialog.quantity), dialogExactPositive(dialog.total)
  if not quantity or quantity < 1 then return setDialogError(dialog, "Enter a whole quantity") end
  if quantity > dialog.maximum then return setDialogError(dialog, "Quantity exceeds missing units") end
  if not total then return setDialogError(dialog, "Enter an exact positive cost") end
  if dialog.costMode == "unit" then
    local unit = dialogExactPositive(dialog.unit)
    if not unit or safeMultiply(quantity, unit) ~= total then
      return setDialogError(dialog, "Enter an exact positive cost")
    end
  elseif dialog.costMode ~= "total" then
    return setDialogError(dialog, "Enter an exact positive cost")
  end
  local position = dialog.position
  local scope = activeScope(position)
  if not scope then return setDialogError(dialog, "Position scope changed") end
  local batch
  if dialog.pendingRepair then
    local pending = pendingRepairFor(position, scope)
    if not pending or pending.id ~= dialog.pendingRepair.id or not dialog.repairID
        or not (GC.Acquisitions and GC.Acquisitions.RepairPendingManual) then
      return setDialogError(dialog, "Position scope changed")
    end
    batch = GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = dialog.repairID,
      itemID = position.itemID, positionKey = position.positionKey, itemName = position.itemName,
      quantity = quantity, total = total, acquiredAt = time(), character = scope.char, region = scope.region })
  else
    batch = GC.Acquisitions.RecordManual({ itemID = position.itemID, positionKey = position.positionKey,
      itemName = position.itemName, quantity = quantity, total = total, acquiredAt = time(),
      character = scope.char, region = scope.region })
  end
  if batch then dialog.submitted = true; dialog:Hide(); GC.Sell.Refresh() else setDialogError(dialog, "Enter an exact positive cost") end
end

local function shownColumns()
  local shown, wide = {}, ROW_WIDTH and ROW_WIDTH >= 700
  for _, column in ipairs(COLUMNS) do
    if not column.optional or wide then shown[#shown + 1] = column end
  end
  return shown
end

local function layoutCells(row)
  local right = row
  local cols = shownColumns()
  for i = #cols, 1, -1 do
    local column, cell = cols[i], row.cells[cols[i].key]
    cell:ClearAllPoints()
    if column.flex then
      -- row.itemInset leaves room for the icon on a position row, and indents a child row so
      -- the hierarchy is carried by layout instead of by leading spaces in the string.
      cell:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, 0)
      cell:SetPoint("RIGHT", right, "LEFT", -4, 0)
    else
      cell:SetWidth(column.w)
      cell:SetPoint("RIGHT", right, right == row and "RIGHT" or "LEFT", right == row and 0 or -2, 0)
      right = cell
    end
    cell:Show()
  end
  for _, column in ipairs(COLUMNS) do if column.optional and not (ROW_WIDTH and ROW_WIDTH >= 700) then row.cells[column.key]:Hide() end end
end

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_HEIGHT)

  -- Sell rows carried no banding, no hover feedback and no rule between them, so a screenful
  -- of positions read as one undifferentiated block -- and an expanded position's children were
  -- distinguishable only by two leading spaces in their text. Same treatment as the Deals list:
  -- BACKGROUND zebra, a highlight above it, a hairline at the bottom edge, and an item icon so
  -- rows are scannable by shape rather than by reading every name.
  local zc = Theme.color.zebra
  row.zebra = row:CreateTexture(nil, "BACKGROUND")
  row.zebra:SetAllPoints()
  row.zebra:SetColorTexture(zc[1], zc[2], zc[3], 0)
  row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.highlight:SetAllPoints()
  local hc = Theme.color.hover
  row.highlight:SetColorTexture(hc[1], hc[2], hc[3], hc[4] or 0.08)
  row.highlight:Hide()
  row.divider = row:CreateTexture(nil, "ARTWORK")
  row.divider:SetHeight(1)
  row.divider:SetPoint("BOTTOMLEFT", 0, 0)
  row.divider:SetPoint("BOTTOMRIGHT", 0, 0)
  local bc = Theme.color.border
  row.divider:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 0.06)
  -- Child rows (batch/detail/lot) get a gold spine at the left edge instead of a bottom rule,
  -- so an expanded group reads as one bracketed unit rather than as more top-level rows.
  row.spine = row:CreateTexture(nil, "ARTWORK")
  row.spine:SetWidth(2)
  row.spine:SetPoint("TOPLEFT", 0, 0)
  row.spine:SetPoint("BOTTOMLEFT", 0, 0)
  local gc = Theme.color.gold
  row.spine:SetColorTexture(gc[1], gc[2], gc[3], 0.45)
  row.spine:Hide()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the stock icon border
  row.icon:Hide()
  row:SetScript("OnEnter", function(self) self.highlight:Show() end)
  row:SetScript("OnLeave", function(self) self.highlight:Hide() end)

  row.cells = {}
  for _, column in ipairs(COLUMNS) do
    local cell = Theme.Label(row, column.key == "item" and 12 or 11)
    cell:SetJustifyH(column.num and "RIGHT" or "LEFT")
    cell:SetWordWrap(false)
    row.cells[column.key] = cell
  end
  row.cells.item:SetJustifyH("LEFT")
  row.action = Theme.Button(row, "ghost")
  row.action:SetSize(72, 18)
  row.action:SetPoint("CENTER", row.cells.status, "CENTER", 0, 0)
  row.action:Hide()
  row:SetScript("OnClick", function(self)
    if self.kind == "position" and type(self.position.positionKey) == "string" then
      expanded[self.position.positionKey] = not expanded[self.position.positionKey]
      renderRows()
    end
  end)
  return row
end

local function showRowAction(row, label, onClick)
  row.cells.status:SetText("")
  row.action:SetLabel(label)
  if onClick then row.action:SetScript("OnClick", onClick) end
  row.action:Show()
end

local function summaryFor(filtered)
  local partial, unknown, knownCost, listedValue = 0, 0, 0, 0
  for _, position in ipairs(filtered) do
    if position.coverage == "PARTIAL" then partial = partial + 1 end
    if position.coverage == "UNKNOWN" then unknown = unknown + 1 end
    if not exact(position.knownCost) then knownCost = nil
    elseif knownCost ~= nil then knownCost = safeAdd(knownCost, position.knownCost) end
    if not exact(position.listedValue) then listedValue = nil
    elseif listedValue ~= nil then listedValue = safeAdd(listedValue, position.listedValue) end
  end
  local raw = GC.SellPositions.Summary(filtered)
  return GC.SellViewModel.SummaryText({ knownCost = raw.invested or knownCost,
    listedValue = raw.listedValue or listedValue,
    profit = raw.profit, partialCount = partial, unknownCount = unknown })
end

local function updateSummary(filtered)
  local text = summaryFor(filtered)
  container.summary.cost:SetText(formatCell(text.knownCost))
  container.summary.listed:SetText(formatCell(text.listedValue))
  container.summary.profit:SetText(type(text.profit) == "number" and formatAmount(text.profit) or text.profit)
  setColor(container.summary.profit, type(text.profit) == "number" and text.profit < 0 and Theme.color.red or Theme.color.green)
end

renderRows = function()
  if not container then return end
  renderGeneration = renderGeneration + 1
  local filtered = GC.SellViewModel.Filter(positions, filterMode)
  if postingRow then disarmPost() end
  if repostingRow then disarmRepost() end
  updateSummary(filtered)
  local entries = {}
  for _, position in ipairs(filtered) do
    entries[#entries + 1] = { kind = "position", position = position }
    if expanded[position.positionKey] then
      local detail = GC.SellViewModel.Expansion(position)
      entries[#entries + 1] = { kind = "detail", position = position, detail = detail }
      for _, batch in ipairs(detail.batches) do entries[#entries + 1] = { kind = "batch", position = position, batch = batch } end
      for _, lot in ipairs(detail.ownedLots) do entries[#entries + 1] = { kind = "lot", position = position, lot = lot } end
      if (position.trackedQty or 0) > (position.listedQty or 0) then
        entries[#entries + 1] = { kind = "listing", position = position }
      end
    end
  end
  for i = #rows + 1, #entries do rows[i] = createRow(content) end
  for i, row in ipairs(rows) do
    local entry = entries[i]
    if not entry then row.renderEntryID = nil; row:Hide()
    else
      row:Show(); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
      row.kind, row.position, row.batch, row.lot = entry.kind, entry.position, entry.batch, entry.lot
      local p = entry.position
      local lotID = entry.lot and entry.lot.auctionID or 0
      row.renderEntryID = table.concat({ renderGeneration, i, entry.kind, p.scopeKey or "", p.positionKey or "", lotID }, ":")
      if entry.kind == "position" then
        row.cells.item:SetText((p.itemName or "Item") .. "\n" .. GC.SellViewModel.SourceText(p))
        row.cells.cost:SetText(formatCell(GC.SellViewModel.CostText(p)))
        row.cells.listed:SetText(formatCell(p.listedValue))
        local marketText = formatCell(p.displayMarketUnit)
        if p.displayMarketUnit and not p.freshMarketUnit and type(p.quoteAge) == "number" then
          marketText = marketText .. (" · stale %ds"):format(p.quoteAge)
        end
        row.cells.market:SetText(marketText)
        setColor(row.cells.market, p.displayMarketUnit and not p.freshMarketUnit
          and Theme.color.fgDim or Theme.color.fg)
        row.cells.profit:SetText(formatCell(GC.SellViewModel.ProfitText(p)))
        row.cells.status:SetText(p.status == "NO_COST" and "NO COST"
          or p.status == "PARTIAL_COST" and "PARTIAL COST" or p.status)
        row.cells.expand:SetText(expanded[p.positionKey] and "−" or "+")
        if p.coverage ~= "COMPLETE" and canSetCost(p) then
          showRowAction(row, "Set cost", function() openCostDialog(p) end)
        else
          row.action:Hide()
        end
      elseif entry.kind == "detail" then
        local d = entry.detail
        local quoteText
        if d.displayMarketUnit ~= nil then
          quoteText = ("market %s · %s · age %ss"):format(formatCell(d.displayMarketUnit),
            d.marketState or "unavailable", d.quoteAge or "?")
        else
          quoteText = ("quote %ss"):format(d.quoteAge or "?")
        end
        row.cells.item:SetText(("  %s · %s · ahead %s · sold/day %s · ETA %s%s"):format(d.note,
          quoteText, d.ahead or "?", d.sold or "?", d.days and ("~" .. math.floor(d.days + 0.5) .. "d") or "?",
          d.factsText and (" · " .. d.factsText) or ""))
        setColor(row.cells.item, d.marketStale and Theme.color.fgDim or Theme.color.fg)
        row.cells.cost:SetText(""); row.cells.listed:SetText(""); row.cells.market:SetText("")
        row.cells.profit:SetText(""); row.cells.status:SetText(recommendationText(d.recommendation)); row.cells.expand:SetText("")
        row.action:Hide()
      elseif entry.kind == "batch" then
        row.cells.item:SetText(("  %s · at %s · %d original / %d left / %d FIFO · unit %s · %s"):format(entry.batch.source or "manual",
          entry.batch.acquiredAt or "?", entry.batch.originalQty or entry.batch.quantity or 0,
          entry.batch.remainingQty or 0, entry.batch.allocatedQty or 0, formatCell(entry.batch.unitCost), entry.batch.evidence or "Recorded"))
        row.cells.cost:SetText(formatCell(entry.batch.totalCost)); row.cells.listed:SetText(""); row.cells.market:SetText("")
        row.cells.profit:SetText(""); row.cells.status:SetText("FIFO"); row.cells.expand:SetText("")
        row.action:Hide()
      elseif entry.kind == "lot" then
        local total = safeMultiply(entry.lot.unitPrice, entry.lot.quantity)
        row.cells.item:SetText(("  Auction %s · ×%d · unit %s"):format(entry.lot.auctionID,
          entry.lot.quantity, formatCell(entry.lot.unitPrice)))
        row.cells.cost:SetText(""); row.cells.listed:SetText(formatCell(total))
        -- What Repost will actually list at. BuildRepostPlan prices a repost at exactly the
        -- fresh quote unit, so showing that quote here answers "at what price?" before the
        -- player commits to cancelling a live auction and eating its deposit.
        if p.displayMarketUnit and p.freshMarketUnit then
          row.cells.market:SetText("→ " .. formatCell(p.displayMarketUnit))
          setColor(row.cells.market, Theme.color.gold)
        else
          row.cells.market:SetText("→ needs price")
          setColor(row.cells.market, Theme.color.fgDim)
        end
        row.cells.profit:SetText(""); row.cells.status:SetText(""); row.cells.expand:SetText("")
        showRowAction(row, "Repost", function() onRepostClick(row, entry.lot.auctionID) end)
      else
        row.cells.item:SetText(("  Unlisted ×%d"):format((p.trackedQty or 0) - (p.listedQty or 0)))
        row.cells.cost:SetText(""); row.cells.listed:SetText(""); row.cells.market:SetText(""); row.cells.profit:SetText(""); row.cells.expand:SetText("")
        if p.coverage == "COMPLETE" then
          local bagState = liveBagState(p)
          if bagState.bag and bagState.exactQty and bagState.exactQty > 0 then
            -- Same question as Repost: say what it will post at before it is clicked.
            if p.displayMarketUnit and p.freshMarketUnit then
              row.cells.market:SetText("→ " .. formatCell(p.displayMarketUnit))
              setColor(row.cells.market, Theme.color.gold)
            else
              row.cells.market:SetText("→ needs price")
              setColor(row.cells.market, Theme.color.fgDim)
            end
            showRowAction(row, "Post", function() onPostClick(row) end)
          else
            row.cells.status:SetText("Exact bag item required")
            row.action:Hide()
          end
        elseif canSetCost(p) then
          showRowAction(row, "Set cost", function() openCostDialog(p) end)
        else
          row.cells.status:SetText("Pending repair needs one exact invoice")
          row.action:Hide()
        end
      end
      -- Banding, hierarchy and the icon are decided here, after the cells are filled, because
      -- only `entry.kind` distinguishes a position from one of its expanded children.
      local zc2 = Theme.color.zebra
      row.zebra:SetColorTexture(zc2[1], zc2[2], zc2[3], (i % 2 == 1) and (zc2[4] or 0.04) or 0)
      if entry.kind == "position" then
        row.itemInset = 26
        row.spine:Hide()
        row.divider:Show()
        local icon = nil
        if p.itemID and C_Item and C_Item.GetItemIconByID then
          local ok, texture = pcall(C_Item.GetItemIconByID, p.itemID)
          icon = ok and texture or nil
        end
        if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
      else
        row.itemInset = 34
        row.icon:Hide()
        row.spine:Show()
        row.divider:Hide() -- a group's children are bracketed by the spine, not sliced by rules
      end
      layoutCells(row)
    end
  end
  content:SetHeight(math.max(1, #entries) * ROW_HEIGHT)
  scheduleQuoteExpiry()
  if GC.Sniper and GC.Sniper.UpdateSellTabLabel then GC.Sniper.UpdateSellTabLabel() end
end

function GC.Sell.SellableCount()
  composePositions()
  local n = 0
  for _, position in ipairs(positions) do
    if (position.trackedQty or 0) > (position.listedQty or 0) then n = n + 1 end
  end
  return n
end

function GC.Sell.Show()
  if container then container:Show() end
  GC.Sell.Refresh()
end
function GC.Sell.Hide() if container then container:Hide() end end
function GC.Sell.Refresh()
  if refresh.phase ~= "idle" and refresh.phase ~= "done" and refresh.phase ~= "error" then return end
  quoteExpiryGeneration = quoteExpiryGeneration + 1
  refresh.generation = refresh.generation + 1
  refresh.phase, refresh.pending, refresh.awaiting, refresh.queue, refresh.index = "owned", nil, nil, {}, 0
  setStatus("Refreshing listings…")
  local sent, waiting = requestOwnedAuctions()
  if waiting then
    refresh.phase = "waiting_owned"
    setStatus("Waiting for Auction House…")
  elseif not sent then
    refresh.phase = "idle"
    setStatus("Auction House is not open")
  end
end
function GC.Sell.Reset()
  local pending = refresh.pending
  if pending then
    refresh.drain[pending.kind .. ":" .. pending.itemID] = {
      abandonedGeneration = pending.generation,
      terminals = 1,
    }
  end
  refresh.generation = refresh.generation + 1
  refresh.phase, refresh.queue, refresh.index, refresh.pending, refresh.awaiting = "idle", {}, 0, nil, nil
  GC.QuoteCache.Clear(quotes)
  quoteExpiryGeneration = quoteExpiryGeneration + 1
  quoteTimeoutToken = quoteTimeoutToken + 1
  disarmPost()
  disarmRepost()
end

function GC.Sell.Attach(f, geometry)
  ROW_WIDTH, ROW_HEIGHT, statusOwner = geometry.rowWidth, geometry.rowHeight, f
  container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", geometry.panelLeft, geometry.top); container:SetPoint("BOTTOMRIGHT", -geometry.panelRightInset, geometry.bottom); container:Hide()
  local refreshButton = Theme.Button(container, "ghost")
  refreshButton:SetSize(72, 20); refreshButton:SetPoint("TOPRIGHT"); refreshButton:SetLabel("Refresh"); refreshButton:SetScript("OnClick", GC.Sell.Refresh)
  local labels = { all = "All", goldcap = "GC", auction_house = "AH", missing_cost = "Missing cost" }
  local previous = refreshButton
  for _, mode in ipairs({ "missing_cost", "auction_house", "goldcap", "all" }) do
    local button = Theme.Button(container, "ghost")
    button:SetSize(mode == "missing_cost" and 82 or 36, 20); button:SetPoint("RIGHT", previous, "LEFT", -2, 0); button:SetLabel(labels[mode])
    button:SetScript("OnClick", function() filterMode = mode; renderRows() end); previous = button
  end
  container.summary = {}
  for i, stat in ipairs({ { "cost", "KNOWN COST" }, { "listed", "LISTED VALUE" }, { "profit", "EST. PROFIT" } }) do
    local label = Theme.Label(container, 10); label:SetPoint("TOPLEFT", (i - 1) * 155, -24); label:SetText(stat[2]); setColor(label, Theme.color.fgDim)
    local value = Theme.Num(container, 14, true); value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1); container.summary[stat[1]] = value
  end
  local header = CreateFrame("Frame", nil, container); header:SetPoint("TOPLEFT", 0, -60); header:SetPoint("TOPRIGHT", 0, -60); header:SetHeight(16); header.cells = {}
  header.itemInset = 26 -- line the ITEM heading up with the names, not with the icons
  for _, column in ipairs(COLUMNS) do
    local cell = Theme.Label(header, 10); cell:SetWordWrap(false); cell:SetText(({ item = "ITEM", cost = "COST", listed = "LISTED", market = "MARKET", profit = "PROFIT", status = "STATUS", expand = "" })[column.key]); header.cells[column.key] = cell
    -- Headings must sit over their own numbers. createRow right-aligns every numeric cell, but
    -- these were left at the default left alignment, so each heading floated to the left edge
    -- of a right-aligned column and every value looked like it belonged to the column after it.
    cell:SetJustifyH(column.num and "RIGHT" or "LEFT")
  end
  layoutCells(header)
  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", 0, -78); scroll:SetPoint("BOTTOMRIGHT")
  content = CreateFrame("Frame", nil, scroll); content:SetSize(ROW_WIDTH, ROW_HEIGHT); scroll:SetScrollChild(content)
  local dialog = CreateFrame("Frame", nil, container, "BackdropTemplate"); dialog:SetSize(270, 130); dialog:SetPoint("CENTER"); dialog:Hide(); container.costDialog = dialog
  -- The template was carried but never given a backdrop, a strata or a frame level, so this
  -- opened as bare floating widgets: the rows underneath showed straight through it, its own
  -- error text collided with them, and clicks aimed at the dialog landed on whatever row sat
  -- behind. Give it a real surface, lift it above the list, and let it swallow its own mouse.
  dialog:SetFrameStrata("DIALOG")
  dialog:SetFrameLevel((container:GetFrameLevel() or 0) + 50)
  dialog:EnableMouse(true)
  local dialogBG = dialog:CreateTexture(nil, "BACKGROUND")
  dialogBG:SetAllPoints()
  local pc = Theme.color.panel
  dialogBG:SetColorTexture(pc[1], pc[2], pc[3], 0.98)
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local edge = dialog:CreateTexture(nil, "BORDER")
    local gc2 = Theme.color.gold
    edge:SetColorTexture(gc2[1], gc2[2], gc2[3], 0.5)
    if side == "TOP" or side == "BOTTOM" then
      edge:SetPoint(side .. "LEFT"); edge:SetPoint(side .. "RIGHT"); edge:SetHeight(1)
    else
      edge:SetPoint("TOP" .. side); edge:SetPoint("BOTTOM" .. side); edge:SetWidth(1)
    end
  end
  dialog.quantity, dialog.unit, dialog.total = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate"), CreateFrame("EditBox", nil, dialog, "InputBoxTemplate"), CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
  for i, field in ipairs({ { dialog.quantity, "Quantity" }, { dialog.unit, "Unit cost" }, { dialog.total, "Total cost" } }) do
    local label = Theme.Label(dialog, 10); label:SetPoint("TOPLEFT", 12 + (i - 1) * 82, -12); label:SetText(field[2])
    field[1]:SetSize(70, 20); field[1]:SetPoint("TOPLEFT", 12 + (i - 1) * 82, -26); field[1]:SetAutoFocus(false)
  end
  dialog.error = Theme.Label(dialog, 10); dialog.error:SetPoint("TOPLEFT", 12, -55); setColor(dialog.error, Theme.color.red)
  local cancel = Theme.Button(dialog, "ghost"); cancel:SetSize(70, 20); cancel:SetPoint("BOTTOMLEFT", 12, 10); cancel:SetLabel("Cancel"); cancel:SetScript("OnClick", function() dialog:Hide() end)
  local confirm = Theme.Button(dialog, "primary"); confirm:SetSize(70, 20); confirm:SetPoint("BOTTOMRIGHT", -12, 10); confirm:SetLabel("Confirm"); confirm:SetScript("OnClick", function() confirmCostDialog(dialog) end)
  local function syncText(edit, text)
    dialog.syncing = true
    edit:SetText(text)
    dialog.syncing = false
  end
  dialog.unit:SetScript("OnTextChanged", function()
    if dialog.syncing then return end
    dialog.costMode = "unit"
    local q, unit = dialogExactPositive(dialog.quantity), dialogExactPositive(dialog.unit)
    if not q or not unit then
      syncText(dialog.total, "")
      return setDialogError(dialog, "Enter an exact positive cost")
    end
    local total = safeMultiply(q, unit)
    if not total then
      syncText(dialog.total, "")
      return setDialogError(dialog, "Enter an exact positive cost")
    end
    setDialogError(dialog)
    syncText(dialog.total, tostring(total))
  end)
  dialog.quantity:SetScript("OnTextChanged", function()
    if dialog.syncing then return end
    local quantity = dialogExactPositive(dialog.quantity)
    if not quantity then
      if dialog.costMode == "unit" then syncText(dialog.total, "")
      elseif dialog.costMode == "total" then syncText(dialog.unit, "")
      else syncText(dialog.unit, ""); syncText(dialog.total, "") end
      return setDialogError(dialog, "Enter a whole quantity")
    end
    if dialog.maximum then
      local clamped = math.max(1, math.min(dialog.maximum, quantity))
      if clamped ~= quantity then syncText(dialog.quantity, tostring(clamped)); quantity = clamped end
    end
    if dialog.costMode == "unit" then
      local unit = dialogExactPositive(dialog.unit)
      local total = unit and safeMultiply(quantity, unit)
      if not total then
        syncText(dialog.total, "")
        return setDialogError(dialog, "Enter an exact positive cost")
      end
      syncText(dialog.total, tostring(total))
      setDialogError(dialog)
    elseif dialog.costMode == "total" then
      local total = dialogExactPositive(dialog.total)
      if not total then
        syncText(dialog.unit, "")
        return setDialogError(dialog, "Enter an exact positive cost")
      end
      syncText(dialog.unit, tostring(math.floor(total / quantity)))
      setDialogError(dialog)
    end
  end)
  dialog.total:SetScript("OnTextChanged", function()
    if dialog.syncing then return end
    dialog.costMode = "total"
    local q, total = dialogExactPositive(dialog.quantity), dialogExactPositive(dialog.total)
    if not q or not total then
      syncText(dialog.unit, "")
      return setDialogError(dialog, "Enter an exact positive cost")
    end
    syncText(dialog.unit, tostring(math.floor(total / q)))
    setDialogError(dialog)
  end)
  f:HookScript("OnSizeChanged", function(_, width)
    ROW_WIDTH = math.max(1, width - geometry.panelLeft - geometry.panelRightInset); content:SetWidth(ROW_WIDTH); layoutCells(header); renderRows()
  end)
end
