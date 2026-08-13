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
  { key = "cost", w = 82, num = true },
  { key = "listed", w = 72, num = true },
  { key = "market", w = 72, num = true, optional = true },
  { key = "profit", w = 76, num = true, bold = true },
  { key = "status", w = 92 },
  { key = "expand", w = 22 },
}

local container, content, statusOwner
local rows, positions, ownedLots, quotes = {}, {}, {}, {}
local expanded, filterMode = {}, "all"
local refresh = { generation = 0, phase = "idle", queue = {}, index = 0, pending = nil, awaiting = nil }
local postingRow, postingPin, postTimeoutToken
local repostingRow, repostPin, repostArmToken = nil, nil, 0

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
  local stats = {}
  for _, lot in ipairs(ownedLots) do
    stats[lot.itemID] = GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(lot.itemID) or nil
  end
  local batches = GC.Acquisitions and GC.Acquisitions.GetActive and GC.Acquisitions.GetActive(context()) or {}
  for _, batch in ipairs(batches) do
    stats[batch.itemID] = stats[batch.itemID] or (GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(batch.itemID) or nil)
  end
  positions = GC.SellPositions.Build({ acquisitions = batches, ownedLots = ownedLots,
    quotes = quotes, statsByItemID = stats, context = context(), now = time() })
  for _, position in ipairs(positions) do position.itemName = itemName(position.itemID) end
end

local function uniqueQuoteItemIDs()
  local seen, result = {}, {}
  for _, position in ipairs(positions) do
    if not seen[position.itemID] then seen[position.itemID], result[#result + 1] = true, position.itemID end
  end
  return result
end

local function renderRows() end

local function finishQuoteWalk()
  refresh.phase = "idle"
  refresh.pending, refresh.awaiting = nil, nil
  setStatus("Updated just now")
  renderRows()
end

local function advanceQuote()
  if refresh.phase ~= "pricing" and refresh.phase ~= "waiting_key" then return end
  if refresh.pending then return end
  if refresh.index >= #refresh.queue then return finishQuoteWalk() end
  if GC.Sniper and GC.Sniper.IsBusy and GC.Sniper.IsBusy() then return end
  if not driver.isReady() then return end
  local itemID = refresh.awaiting or refresh.queue[refresh.index + 1]
  if driver.keyInfo(itemID) then
    refresh.awaiting = nil
    refresh.index = refresh.index + 1
    refresh.pending = { itemID = itemID, generation = refresh.generation, at = time() }
    refresh.phase = "pricing"
    setStatus(("Pricing %d/%d…"):format(refresh.index, #refresh.queue))
    driver.send(itemID)
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
    C_AuctionHouse.QueryOwnedAuctions({})
    return true
  end
  return false
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
  end
  if repostingRow and repostPin then
    local stillOwned
    for _, lot in ipairs(ownedLots) do
      if lot.positionKey == repostPin.positionKey and lot.auctionID == repostPin.auctionID and lot.quantity == repostPin.quantity then stillOwned = true break end
    end
    if not stillOwned then
      repostArmToken = repostArmToken + 1
      repostingRow, repostPin = nil, nil
      setStatus("Lot cancelled; wait for it to return to bags")
    end
  end
  onOwnedAuctionsReady()
end

function GC.Sell.OnThrottleReady()
  if refresh.pending and time() - refresh.pending.at > QUOTE_STALE_SECONDS then refresh.pending = nil end
  advanceQuote()
end

function GC.Sell.OnItemKeyInfo(itemID)
  if refresh.phase == "waiting_key" and refresh.awaiting == itemID then advanceQuote() end
end

local function quoteResolved(itemID, unit, levels)
  local pending = refresh.pending
  if not pending or pending.itemID ~= itemID or pending.generation ~= refresh.generation then return end
  refresh.pending = nil
  GC.QuoteCache.Set(quotes, itemID, unit, time())
  if unit and quotes[itemID] then quotes[itemID].levels = levels end
  composePositions()
  renderRows()
  advanceQuote()
end

function GC.Sell.OnItemSearchResults(itemID) quoteResolved(itemID, driver.item(itemID), driver.itemLevels(itemID)) end
function GC.Sell.OnCommoditySearchResults(itemID) quoteResolved(itemID, driver.commodity(itemID), driver.commodityLevels(itemID)) end

local function freshQuote(position)
  return GC.QuoteCache.Fresh(quotes, position.itemID, time())
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
  local level = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
  local suffix = tonumber(fields[8])
  if type(level) ~= "number" or suffix == nil then return nil end
  return ("item:%d:%d:%d:%d"):format(itemID, math.floor(level), suffix, 0)
end

local function liveBagState(position)
  local total, matchedBag, matchedSlot, matchedStack = 0, nil, nil, nil
  for _, bag in ipairs(SELL_BAGS) do
    local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == position.itemID then
        local qty = info.stackCount or 1
        if exact(qty) and qty > 0 and position.positionKey:match("^commodity:") then
          total = safeAdd(total, qty)
          if not total then return { itemID = position.itemID, exactQty = nil } end
          if not matchedBag then matchedBag, matchedSlot, matchedStack = bag, slot, qty end
        else
          local link = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
          if exact(qty) and qty > 0 and normalizedPositionKey(position.itemID, link) == position.positionKey then
            total = safeAdd(total, qty)
            if not total then return { itemID = position.itemID, exactQty = nil } end
            if not matchedBag then matchedBag, matchedSlot, matchedStack = bag, slot, qty end
          end
        end
      end
    end
  end
  return { itemID = position.itemID, exactQty = total, positionKey = matchedBag and position.positionKey or nil,
    bag = matchedBag, slot = matchedSlot, stackQty = matchedStack }
end

local function startQuoteRefreshFor(position)
  if refresh.phase == "idle" then
    refresh.generation = refresh.generation + 1
    refresh.queue, refresh.index, refresh.phase, refresh.pending, refresh.awaiting = { position.itemID }, 0, "pricing", nil, nil
    advanceQuote()
  end
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
      postingRow, postingPin = nil, nil
      row.postStage = nil; row.action:Enable(); row.action:SetLabel("Post")
      setStatus("Posting timed out")
    end
  end)
end

local function onPostClick(row)
  local position = row.position
  local quote = freshQuote(position)
  if not quote then
    if postingRow == row then
      postingRow, postingPin = nil, nil
      row.postStage = nil; row.action:Enable(); row.action:SetLabel("Post")
    end
    startQuoteRefreshFor(position); setStatus("Pricing 0/1…"); return
  end
  if postingRow and postingRow ~= row then
    setStatus("Finish the pending post first")
    return
  end
  if postingRow == row and row.postStage ~= "confirm" then return end
  if row.postStage == "confirm" then
    local pin = postingPin
    if not pin or pin.positionKey ~= position.positionKey or quote.at ~= pin.quoteAt or quote.unit ~= pin.quoteUnit then
      postingRow, postingPin = nil, nil
      row.postStage = nil; row.action:Enable(); row.action:SetLabel("Post")
      startQuoteRefreshFor(position); setStatus("Pricing 0/1…"); return
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
  if not bagState.bag or not bagState.stackQty or plan.quantity > bagState.stackQty then
    setStatus("No exact bag stack")
    return
  end
  local info = driver.keyInfo(plan.itemID)
  if not info or not ItemLocation or not ItemLocation.CreateFromBagAndSlot then setStatus("No exact auction key"); return end
  if (info.isCommodity and not (C_AuctionHouse and C_AuctionHouse.PostCommodity))
      or (not info.isCommodity and not (C_AuctionHouse and C_AuctionHouse.PostItem)) then
    setStatus("Posting unavailable")
    return
  end
  local buyout = not info.isCommodity and safeMultiply(plan.unitPrice, plan.quantity) or nil
  if not info.isCommodity and not buyout then setStatus("Cannot post this position"); return end
  local location = ItemLocation:CreateFromBagAndSlot(bagState.bag, bagState.slot)
  postingRow = row
  postingPin = { positionKey = plan.positionKey, itemID = plan.itemID, quantity = plan.quantity,
    quoteAt = quote.at, quoteUnit = quote.unit, location = location, isCommodity = info.isCommodity,
    unitPrice = plan.unitPrice, buyout = buyout }
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
  local quote = freshQuote(position)
  if not quote then startQuoteRefreshFor(position); setStatus("Pricing 0/1…"); return end
  if repostingRow and repostingRow ~= row then setStatus("Finish the pending repost first"); return end
  if row.repostStage == "armed" then
    if not row.repostReady then return end
    local pin = repostPin
    composePositions()
    local livePosition = currentPosition(pin.positionKey)
    local current
    for _, candidate in ipairs(livePosition and livePosition.ownedLots or {}) do
      if candidate.auctionID == pin.auctionID and candidate.quantity == pin.quantity then current = candidate break end
    end
    local plan = current and GC.SellPositions.BuildRepostPlan(livePosition, pin.auctionID, { unit = quote.unit, fresh = true })
    if not plan or quote.at ~= pin.quoteAt or quote.unit ~= pin.quoteUnit or not (C_AuctionHouse and C_AuctionHouse.CancelAuction) then
      repostingRow, repostPin = nil, nil; row.repostStage = nil; row.action:Enable(); row.action:SetLabel("Repost")
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
          repostingRow, repostPin = nil, nil; row.repostStage = nil; row.action:Enable(); row.action:SetLabel("Repost")
          setStatus("Cancel timed out")
        end
      end)
    end
    return
  end
  local plan = GC.SellPositions.BuildRepostPlan(position, auctionID, { unit = quote.unit, fresh = true })
  if not plan then setStatus("Cannot repost this lot") return end
  repostingRow, repostPin = row, { positionKey = plan.positionKey, auctionID = plan.auctionID,
    quantity = plan.quantity, quoteAt = quote.at, quoteUnit = quote.unit }
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
        repostingRow, repostPin = nil, nil; row.repostStage = nil; row.action:Enable(); row.action:SetLabel("Repost")
        setStatus("Repost confirmation expired")
      end
    end)
  end
end

function GC.Sell.OnAuctionCreated()
  local pin, row = postingPin, postingRow
  if not pin or not row then return end
  local scope = context()
  if GC.Acquisitions and GC.Acquisitions.RecordPost and scope then
    GC.Acquisitions.RecordPost(pin.positionKey, pin.itemID, itemName(pin.itemID), scope.char, scope.region, pin.quantity, time())
  end
  postTimeoutToken = (postTimeoutToken or 0) + 1
  postingRow, postingPin = nil, nil
  GC.Sell.Refresh()
end

function GC.Sell.OnPostError()
  if postingRow then postingRow.postStage = nil; postingRow.action:Enable(); postingRow.action:SetLabel("Post") end
  postTimeoutToken = (postTimeoutToken or 0) + 1
  postingRow, postingPin = nil, nil
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

local function openCostDialog(position)
  local dialog = container.costDialog
  local missing = math.max(0, (position.exposureQty or 0) - (position.knownQty or 0))
  if missing < 1 then return end
  dialog.position, dialog.maximum = position, missing
  dialog.quantity:SetText("1")
  dialog.unit:SetText("")
  dialog.total:SetText("")
  setDialogError(dialog)
  dialog:Show()
end

local function confirmCostDialog(dialog)
  local quantity, total = dialogNumber(dialog.quantity), dialogNumber(dialog.total)
  if not quantity or quantity < 1 then return setDialogError(dialog, "Enter a whole quantity") end
  if quantity > dialog.maximum then return setDialogError(dialog, "Quantity exceeds missing units") end
  if not total or total < 1 then return setDialogError(dialog, "Enter an exact positive cost") end
  local position, scope = dialog.position, context()
  local batch = GC.Acquisitions.RecordManual({ itemID = position.itemID, positionKey = position.positionKey,
    itemName = position.itemName, quantity = quantity, total = total, acquiredAt = time(),
    character = scope and scope.char, region = scope and scope.region })
  if batch then dialog:Hide(); GC.Sell.Refresh() else setDialogError(dialog, "Enter an exact positive cost") end
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
      cell:SetPoint("LEFT", row, "LEFT", 2, 0)
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
  row.cells = {}
  for _, column in ipairs(COLUMNS) do
    local cell = Theme.Label(row, column.key == "item" and 12 or 11)
    cell:SetJustifyH(column.num and "RIGHT" or "LEFT")
    row.cells[column.key] = cell
  end
  row.cells.item:SetJustifyH("LEFT")
  row.cells.item:SetWordWrap(false)
  row.action = Theme.Button(row, "ghost")
  row.action:SetSize(54, 18)
  row.action:SetPoint("RIGHT", row.cells.status, "RIGHT", 0, 0)
  row.action:Hide()
  row:SetScript("OnClick", function(self)
    if self.kind == "position" then expanded[self.position.positionKey] = not expanded[self.position.positionKey]; renderRows() end
  end)
  return row
end

local function summaryFor(filtered)
  local partial, unknown, knownCost, listedValue = 0, 0, 0, 0
  for _, position in ipairs(filtered) do
    if position.coverage == "PARTIAL" then partial = partial + 1 end
    if position.coverage == "UNKNOWN" then unknown = unknown + 1 end
    if position.coverage ~= "COMPLETE" or not exact(position.knownCost) or not exact(position.listedValue) then
      knownCost, listedValue = nil, nil
    elseif knownCost ~= nil then
      knownCost, listedValue = safeAdd(knownCost, position.knownCost), safeAdd(listedValue, position.listedValue)
    end
  end
  local raw = GC.SellPositions.Summary(filtered)
  return GC.SellViewModel.SummaryText({ knownCost = raw.invested or knownCost, listedValue = listedValue,
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
  local filtered = GC.SellViewModel.Filter(positions, filterMode)
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
    if row == postingRow or row == repostingRow then
      row:Show()
    elseif not entry then row:Hide()
    else
      row:Show(); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
      row.kind, row.position, row.batch, row.lot = entry.kind, entry.position, entry.batch, entry.lot
      local p = entry.position
      if entry.kind == "position" then
        row.cells.item:SetText((p.itemName or "Item") .. "\n" .. GC.SellViewModel.SourceText(p))
        row.cells.cost:SetText(formatCell(GC.SellViewModel.CostText(p)))
        row.cells.listed:SetText(formatCell(p.listedValue))
        row.cells.market:SetText(formatCell(p.displayMarketUnit))
        row.cells.profit:SetText(formatCell(GC.SellViewModel.ProfitText(p)))
        row.cells.status:SetText(p.status == "NO_COST" and "Set cost" or p.status)
        row.cells.expand:SetText(expanded[p.positionKey] and "−" or "+")
        if p.coverage ~= "COMPLETE" then
          row.action:SetLabel("Set cost"); row.action:Show(); row.action:SetScript("OnClick", function() openCostDialog(p) end)
        else
          row.action:Hide()
        end
      elseif entry.kind == "detail" then
        local d = entry.detail
        row.cells.item:SetText(("  %s · quote %ss · ahead %s · sold/day %s · ETA %s"):format(d.note,
          d.quoteAge or "?", d.ahead or "?", d.sold or "?", d.days and ("~" .. math.floor(d.days + 0.5) .. "d") or "?"))
        row.cells.cost:SetText(""); row.cells.listed:SetText(""); row.cells.market:SetText("")
        row.cells.profit:SetText(""); row.cells.status:SetText(d.recommendation or ""); row.cells.expand:SetText("")
        row.action:Hide()
      elseif entry.kind == "batch" then
        row.cells.item:SetText(("  %s · at %s · %d original / %d left / %d FIFO · unit %s · %s"):format(entry.batch.source or "manual",
          entry.batch.acquiredAt or "?", entry.batch.originalQty or entry.batch.quantity or 0,
          entry.batch.remainingQty or 0, entry.batch.allocatedQty or 0, formatCell(entry.batch.unitCost), entry.batch.evidence or "Recorded"))
        row.cells.cost:SetText(formatCell(entry.batch.totalCost)); row.cells.listed:SetText(""); row.cells.market:SetText("")
        row.cells.profit:SetText(""); row.cells.status:SetText("FIFO"); row.cells.expand:SetText("")
        row.action:Hide()
      elseif entry.kind == "lot" then
        row.cells.item:SetText(("  Auction %s · ×%d"):format(entry.lot.auctionID, entry.lot.quantity))
        row.cells.cost:SetText(""); row.cells.listed:SetText(formatCell(entry.lot.unitPrice * entry.lot.quantity))
        row.cells.market:SetText(""); row.cells.profit:SetText(""); row.cells.status:SetText("Repost"); row.cells.expand:SetText("")
        row.action:SetLabel("Repost"); row.action:Show(); row.action:SetScript("OnClick", function() onRepostClick(row, entry.lot.auctionID) end)
      else
        row.cells.item:SetText(("  Unlisted ×%d"):format((p.trackedQty or 0) - (p.listedQty or 0)))
        row.cells.cost:SetText(""); row.cells.listed:SetText(""); row.cells.market:SetText(""); row.cells.profit:SetText(""); row.cells.expand:SetText("")
        if p.coverage == "COMPLETE" then
          local bagState = liveBagState(p)
          if bagState.bag and bagState.exactQty and bagState.exactQty > 0 then
            row.cells.status:SetText("Ready to post")
            row.action:SetLabel("Post"); row.action:SetScript("OnClick", function() onPostClick(row) end); row.action:Show()
          else
            row.cells.status:SetText("Exact bag item required")
            row.action:Hide()
          end
        else
          row.cells.status:SetText("Missing cost")
          row.action:SetLabel("Set cost"); row.action:SetScript("OnClick", function() openCostDialog(p) end); row.action:Show()
        end
      end
      layoutCells(row)
    end
  end
  content:SetHeight(math.max(1, #entries) * ROW_HEIGHT)
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
  if refresh.phase ~= "idle" then return end
  refresh.generation = refresh.generation + 1
  refresh.phase, refresh.pending, refresh.awaiting, refresh.queue, refresh.index = "owned", nil, nil, {}, 0
  setStatus("Refreshing listings…")
  if not requestOwnedAuctions() then
    refresh.phase = "idle"
    setStatus("Auction House is not open")
  end
end
function GC.Sell.Reset()
  refresh.generation = refresh.generation + 1
  refresh.phase, refresh.queue, refresh.index, refresh.pending, refresh.awaiting = "idle", {}, 0, nil, nil
  GC.QuoteCache.Clear(quotes)
  postTimeoutToken = (postTimeoutToken or 0) + 1
  repostArmToken = (repostArmToken or 0) + 1
  if postingRow then postingRow.postStage = nil; postingRow.action:Enable(); postingRow.action:SetLabel("Post") end
  if repostingRow then repostingRow.repostStage = nil; repostingRow.action:Enable(); repostingRow.action:SetLabel("Repost") end
  postingRow, postingPin, repostingRow, repostPin = nil, nil, nil, nil
end

function GC.Sell.Attach(f, geometry)
  ROW_WIDTH, ROW_HEIGHT, statusOwner = geometry.rowWidth, geometry.rowHeight, f
  container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", geometry.panelLeft, geometry.top); container:SetPoint("BOTTOMRIGHT", -geometry.panelRightInset, geometry.bottom); container:Hide()
  local refreshButton = Theme.Button(container, "ghost")
  refreshButton:SetSize(72, 20); refreshButton:SetPoint("TOPRIGHT"); refreshButton:SetLabel("Refresh"); refreshButton:SetScript("OnClick", GC.Sell.Refresh)
  local labels = { all = "All", goldcap = "GC", auction_house = "AH", missing_cost = "Missing cost" }
  local previous = refreshButton
  for _, mode in ipairs({ "all", "goldcap", "auction_house", "missing_cost" }) do
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
  for _, column in ipairs(COLUMNS) do
    local cell = Theme.Label(header, 10); cell:SetText(({ item = "ITEM", cost = "COST", listed = "LISTED", market = "MARKET", profit = "PROFIT", status = "STATUS", expand = "" })[column.key]); header.cells[column.key] = cell
  end
  layoutCells(header)
  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", 0, -78); scroll:SetPoint("BOTTOMRIGHT")
  content = CreateFrame("Frame", nil, scroll); content:SetSize(ROW_WIDTH, ROW_HEIGHT); scroll:SetScrollChild(content)
  local dialog = CreateFrame("Frame", nil, container, "BackdropTemplate"); dialog:SetSize(270, 130); dialog:SetPoint("CENTER"); dialog:Hide(); container.costDialog = dialog
  dialog.quantity, dialog.unit, dialog.total = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate"), CreateFrame("EditBox", nil, dialog, "InputBoxTemplate"), CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
  for i, field in ipairs({ { dialog.quantity, "Quantity" }, { dialog.unit, "Unit cost" }, { dialog.total, "Total cost" } }) do
    local label = Theme.Label(dialog, 10); label:SetPoint("TOPLEFT", 12 + (i - 1) * 82, -12); label:SetText(field[2])
    field[1]:SetSize(70, 20); field[1]:SetPoint("TOPLEFT", 12 + (i - 1) * 82, -26); field[1]:SetAutoFocus(false)
  end
  dialog.error = Theme.Label(dialog, 10); dialog.error:SetPoint("TOPLEFT", 12, -55); setColor(dialog.error, Theme.color.red)
  local cancel = Theme.Button(dialog, "ghost"); cancel:SetSize(70, 20); cancel:SetPoint("BOTTOMLEFT", 12, 10); cancel:SetLabel("Cancel"); cancel:SetScript("OnClick", function() dialog:Hide() end)
  local confirm = Theme.Button(dialog, "primary"); confirm:SetSize(70, 20); confirm:SetPoint("BOTTOMRIGHT", -12, 10); confirm:SetLabel("Confirm"); confirm:SetScript("OnClick", function() confirmCostDialog(dialog) end)
  dialog.unit:SetScript("OnTextChanged", function()
    local q, unit = dialogNumber(dialog.quantity), dialogNumber(dialog.unit)
    if not dialog.editingTotal and q and unit and q > 0 and unit > 0 then dialog.total:SetText(tostring(q * unit)) end
  end)
  dialog.quantity:SetScript("OnTextChanged", function()
    local quantity = dialogNumber(dialog.quantity)
    if quantity and dialog.maximum then
      local clamped = math.max(1, math.min(dialog.maximum, quantity))
      if clamped ~= quantity then dialog.quantity:SetText(tostring(clamped)) end
    end
  end)
  dialog.total:SetScript("OnTextChanged", function()
    local q, total = dialogNumber(dialog.quantity), dialogNumber(dialog.total)
    if q and total and q > 0 and total > 0 then
      dialog.editingTotal = true
      dialog.unit:SetText(tostring(math.floor(total / q)))
      dialog.editingTotal = false
    end
  end)
  f:HookScript("OnSizeChanged", function(_, width)
    ROW_WIDTH = math.max(1, width - geometry.panelLeft - geometry.panelRightInset); content:SetWidth(ROW_WIDTH); layoutCells(header); renderRows()
  end)
end
