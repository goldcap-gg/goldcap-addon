local _, GC = ...

GC.PurchaseCapture = {}

local api
local contextFn
local attemptNumber = 0
local sessionStartedAt = 0
local hooksInstalled = false
local commodityAttempt
local itemResults = {}
local itemAttempts = {}

local MAX_EXACT = 9007199254740991

local function isExactInteger(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

local function isPositiveInteger(value)
  return isExactInteger(value) and value > 0
end

local function currentTime()
  return api and api.time and api.time() or 0
end

local function currentContext()
  return contextFn and contextFn() or nil
end

local function nextAttemptID()
  attemptNumber = attemptNumber + 1
  local context = currentContext()
  local character = context and context.char or "unknown"
  return ("normal-ah:%s:%s:%d"):format(character, tostring(sessionStartedAt), attemptNumber)
end

local function recordPending(attempt, reason)
  if not attempt or not isPositiveInteger(attempt.itemID) then
    return
  end
  local context = attempt.context or currentContext()
  GC.Acquisitions.RecordPending({
    itemID = attempt.itemID,
    positionKey = attempt.positionKey,
    quantity = attempt.quantity,
    completedAt = currentTime(),
    character = context and context.char or nil,
    region = context and context.region or nil,
    reason = reason,
    evidenceKey = attempt.attemptID,
  })
end

local function recordExact(attempt)
  local context = attempt.context or currentContext()
  GC.Acquisitions.Record({
    source = "auction_house",
    itemID = attempt.itemID,
    positionKey = attempt.positionKey,
    quantity = attempt.quantity,
    total = attempt.finalTotal,
    acquiredAt = currentTime(),
    character = context and context.char or nil,
    region = context and context.region or nil,
    evidenceKey = attempt.attemptID,
  })
end

local function hasCompleteItemIdentity(itemKey)
  return type(itemKey) == "table" and isPositiveInteger(itemKey.itemID)
    and isExactInteger(itemKey.itemLevel) and isExactInteger(itemKey.itemSuffix)
    and isExactInteger(itemKey.battlePetSpeciesID)
end

local function ownsCommodity(itemID, quantity)
  return GC.Sniper and GC.Sniper.OwnsCommodityPurchase
    and GC.Sniper.OwnsCommodityPurchase(itemID, quantity)
end

local function ownsAuction(auctionID)
  return GC.Sniper and GC.Sniper.OwnsAuctionPurchase and GC.Sniper.OwnsAuctionPurchase(auctionID)
end

local function onCommodityStart(itemID, quantity)
  if ownsCommodity(itemID, quantity) then
    commodityAttempt = nil
    return
  end
  if not isPositiveInteger(itemID) or not isPositiveInteger(quantity) then
    return
  end
  local attempt = {
    attemptID = nextAttemptID(), itemID = itemID, quantity = quantity,
    positionKey = GC.Acquisitions.PositionKey(itemID, nil, true),
    startedAt = currentTime(), context = currentContext(), confirmed = false,
  }
  commodityAttempt = attempt
  if api.after then
    api.after(15, function()
      if commodityAttempt and commodityAttempt.attemptID == attempt.attemptID then commodityAttempt = nil end
    end)
  end
end

local function onCommodityConfirm(itemID, quantity)
  if ownsCommodity(itemID, quantity) then
    commodityAttempt = nil
    return
  end
  local attempt = commodityAttempt
  if not attempt then return end
  if attempt.itemID ~= itemID or attempt.quantity ~= quantity then
    commodityAttempt = nil
    return
  end
  attempt.confirmed = true
end

local function onPlaceBid(auctionID, total)
  if ownsAuction(auctionID) then return end
  local result = itemResults[auctionID]
  if not result or not isPositiveInteger(result.itemID) then return end
  local exact = result.identityComplete and isPositiveInteger(result.quantity)
    and isPositiveInteger(result.total) and result.total == total
  local attempt = {
    attemptID = nextAttemptID(), auctionID = auctionID, itemID = result.itemID,
    quantity = result.quantity, positionKey = result.positionKey,
    finalTotal = exact and total or nil, exact = exact,
    startedAt = currentTime(), context = currentContext(),
  }
  itemAttempts[auctionID] = attempt
  if api.after then
    api.after(15, function()
      if itemAttempts[auctionID] == attempt then itemAttempts[auctionID] = nil end
    end)
  end
end

function GC.PurchaseCapture.Init(newApi, newContextFn)
  if hooksInstalled then return end
  api = newApi
  contextFn = newContextFn
  sessionStartedAt = currentTime()
  api.hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", onCommodityStart)
  api.hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", onCommodityConfirm)
  api.hooksecurefunc(C_AuctionHouse, "PlaceBid", onPlaceBid)
  hooksInstalled = true
end

function GC.PurchaseCapture.OnItemSearchResults(itemKey)
  if not api or not api.getNumItemSearchResults or not api.getItemSearchResultInfo
      or type(itemKey) ~= "table" or not isPositiveInteger(itemKey.itemID) then return end
  local count = api.getNumItemSearchResults(itemKey) or 0
  for index = 1, count do
    local info = api.getItemSearchResultInfo(itemKey, index)
    if type(info) == "table" and isPositiveInteger(info.auctionID) then
      local identityComplete = hasCompleteItemIdentity(itemKey)
      itemResults[info.auctionID] = {
        auctionID = info.auctionID,
        itemID = itemKey.itemID,
        positionKey = identityComplete and GC.Acquisitions.PositionKey(itemKey.itemID, itemKey, false) or nil,
        quantity = info.quantity,
        total = info.buyoutAmount,
        identityComplete = identityComplete,
      }
    end
  end
end

function GC.PurchaseCapture.OnPurchaseCompleted(auctionID)
  local attempt = itemAttempts[auctionID]
  if not attempt then return end
  itemAttempts[auctionID] = nil
  if attempt.exact and isPositiveInteger(attempt.finalTotal) and attempt.positionKey then
    recordExact(attempt)
  else
    recordPending(attempt, "item purchase exact evidence unavailable")
  end
end

function GC.PurchaseCapture.OnCommodityPriceUpdated(_, totalPrice)
  local attempt = commodityAttempt
  if attempt and not attempt.confirmed and isPositiveInteger(totalPrice) then attempt.finalTotal = totalPrice end
end

function GC.PurchaseCapture.OnCommodityPriceUnavailable()
  local attempt = commodityAttempt
  commodityAttempt = nil
  if attempt and attempt.confirmed then
    recordPending(attempt, "commodity purchase price unavailable")
  end
end

function GC.PurchaseCapture.OnCommodityPurchaseSucceeded()
  local attempt = commodityAttempt
  commodityAttempt = nil
  if not attempt or not attempt.confirmed then return end
  if isPositiveInteger(attempt.finalTotal) then
    recordExact(attempt)
  else
    recordPending(attempt, "commodity purchase exact total unavailable")
  end
end

function GC.PurchaseCapture.OnCommodityPurchaseFailed()
  commodityAttempt = nil
end

function GC.PurchaseCapture.Reset()
  commodityAttempt = nil
  itemResults = {}
  itemAttempts = {}
end
