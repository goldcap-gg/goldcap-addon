local _, GC = ...

GC.Sell = GC.Sell or {}

local Theme = GC.Theme
local ROW_HEIGHT, ROW_WIDTH
local SELL_BAGS = { 0, 1, 2, 3, 4, 5 }
local POST_DURATION = 2
local QUOTE_STALE_SECONDS = (GC.QuoteCache and GC.QuoteCache.MAX_AGE_SECONDS) or 10

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
local quoting, refreshPending = false, false
local quoteQueue, quoteIndex, pendingQuote, pendingQuoteSince, awaitingKeyInfo = {}, 0, nil, 0, nil
local postingPlan, pendingPost

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
  quoting = false
  setStatus("Updated just now")
  renderRows()
end

local function advanceQuote()
  if not quoting or pendingQuote or awaitingKeyInfo then return end
  if quoteIndex >= #quoteQueue then return finishQuoteWalk() end
  if GC.Sniper and GC.Sniper.IsBusy and GC.Sniper.IsBusy() then return end
  if not driver.isReady() then return end
  quoteIndex = quoteIndex + 1
  local itemID = quoteQueue[quoteIndex]
  if driver.keyInfo(itemID) then
    pendingQuote, pendingQuoteSince = itemID, time()
    setStatus(("Pricing %d/%d…"):format(quoteIndex, #quoteQueue))
    driver.send(itemID)
  else
    awaitingKeyInfo = itemID
  end
end

local function beginQuoteWalk()
  quoteQueue, quoteIndex, quoting = uniqueQuoteItemIDs(), 0, true
  if #quoteQueue == 0 then return finishQuoteWalk() end
  advanceQuote()
end

local function requestOwnedAuctions()
  if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions
      and (not GC.Sniper or not GC.Sniper.IsAHOpen or GC.Sniper.IsAHOpen()) then
    C_AuctionHouse.QueryOwnedAuctions({})
    return true
  end
  return false
end

local function onOwnedAuctionsReady()
  composePositions()
  renderRows()
  if refreshPending then
    refreshPending = false
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
  onOwnedAuctionsReady()
end

function GC.Sell.OnThrottleReady()
  if pendingQuote and time() - pendingQuoteSince > QUOTE_STALE_SECONDS then pendingQuote = nil end
  advanceQuote()
end

function GC.Sell.OnItemKeyInfo(itemID)
  if awaitingKeyInfo == itemID then awaitingKeyInfo = nil; advanceQuote() end
end

local function quoteResolved(itemID, unit)
  if itemID ~= pendingQuote then return end
  pendingQuote = nil
  GC.QuoteCache.Set(quotes, itemID, unit, time())
  composePositions()
  renderRows()
  advanceQuote()
end

function GC.Sell.OnItemSearchResults(itemID) quoteResolved(itemID, driver.item(itemID)) end
function GC.Sell.OnCommoditySearchResults(itemID) quoteResolved(itemID, driver.commodity(itemID)) end

local function freshPlanQuote(position)
  local quote = GC.QuoteCache.Fresh(quotes, position.itemID, time())
  return quote and { unit = quote.unit, fresh = true } or nil
end

local function normalizedPositionKey(itemID, link)
  if type(link) ~= "string" then return nil end
  local actualID = tonumber(link:match("item:(%d+)"))
  if actualID ~= itemID then return nil end
  local level = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
  local fields, n = {}, 0
  for part in link:gmatch("[^:|]+") do n = n + 1; fields[n] = part end
  local suffix = tonumber(fields[8])
  local pet = tonumber(link:match("battlepet:(%d+)")) or 0
  if type(level) ~= "number" or suffix == nil then return nil end
  return ("item:%d:%d:%d:%d"):format(itemID, math.floor(level), suffix, pet)
end

local function liveBagState(position)
  local total, matched, matchedBag, matchedSlot = 0, 0, nil, nil
  for _, bag in ipairs(SELL_BAGS) do
    local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == position.itemID then
        local qty = info.stackCount or 1
        if position.positionKey:match("^commodity:") then
          if not matchedBag then matchedBag, matchedSlot, total = bag, slot, qty end
          matched = matched + qty
        else
          local link = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
          if normalizedPositionKey(position.itemID, link) == position.positionKey then
            if not matchedBag then matchedBag, matchedSlot, total = bag, slot, qty end
            matched = matched + qty
          end
        end
      end
    end
  end
  return { itemID = position.itemID, exactQty = total, positionKey = matched > 0 and position.positionKey or nil,
    bag = matchedBag, slot = matchedSlot }
end

local function startQuoteRefreshFor(position)
  if not quoting then
    quoteQueue, quoteIndex, quoting = { position.itemID }, 0, true
    advanceQuote()
  end
end

local function protectedPost(plan, bagState, row)
  local bag, slot = bagState.bag, bagState.slot
  if not bag then setStatus("No exact bag item") return end
  local location, info = ItemLocation:CreateFromBagAndSlot(bag, slot), driver.keyInfo(plan.itemID)
  if not info then setStatus("No exact auction key") return end
  postingPlan = plan
  local needsConfirmation
  if info.isCommodity then
    needsConfirmation = C_AuctionHouse.PostCommodity(location, POST_DURATION, plan.quantity, plan.unitPrice)
  else
    needsConfirmation = C_AuctionHouse.PostItem(location, POST_DURATION, plan.quantity, nil, plan.unitPrice * plan.quantity)
  end
  if needsConfirmation then
    pendingPost = { positionKey = plan.positionKey, location = location, isCommodity = info.isCommodity,
      quantity = plan.quantity, unitPrice = plan.unitPrice }
    row.action:SetLabel("Confirm")
  end
  setStatus("Posting…")
end

local function onPostClick(row)
  local position = row.position
  local quote = freshPlanQuote(position)
  if not quote then startQuoteRefreshFor(position); setStatus("Pricing 0/1…"); return end
  if postingPlan and postingPlan.positionKey ~= position.positionKey then
    setStatus("Finish the pending post first")
    return
  end
  if pendingPost and pendingPost.positionKey == position.positionKey then
    local pending = pendingPost
    pendingPost = nil
    if pending.isCommodity then
      C_AuctionHouse.ConfirmPostCommodity(pending.location, POST_DURATION, pending.quantity, pending.unitPrice)
    else
      C_AuctionHouse.ConfirmPostItem(pending.location, POST_DURATION, pending.quantity, nil, pending.unitPrice * pending.quantity)
    end
    setStatus("Posting…")
    return
  end
  local bagState = liveBagState(position)
  local plan, reason = GC.SellPositions.BuildPostPlan(position, bagState, quote)
  if not plan then
    if reason == "stale_quote" then startQuoteRefreshFor(position) end
    setStatus(reason == "ambiguous_variant" and "No exact bag variant" or "Cannot post this position")
    return
  end
  protectedPost(plan, bagState, row)
end

local function onRepostClick(row, auctionID)
  local position = row.position
  local quote = freshPlanQuote(position)
  if not quote then startQuoteRefreshFor(position); setStatus("Pricing 0/1…"); return end
  local plan = GC.SellPositions.BuildRepostPlan(position, auctionID, quote)
  if not plan then setStatus("Cannot repost this lot") return end
  C_AuctionHouse.CancelAuction(plan.auctionID)
  setStatus("Cancelling lot…")
end

function GC.Sell.OnAuctionCreated()
  if not postingPlan then return end
  local scope = context()
  if GC.Acquisitions and GC.Acquisitions.RecordPost and scope then
    GC.Acquisitions.RecordPost(postingPlan.positionKey, postingPlan.itemID, itemName(postingPlan.itemID),
      scope.char, scope.region, postingPlan.quantity, time())
  end
  postingPlan, pendingPost = nil, nil
  GC.Sell.Refresh()
end

function GC.Sell.OnPostError()
  postingPlan, pendingPost = nil, nil
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
    if column.flex then cell:SetPoint("LEFT", row, "LEFT", 2, 0); cell:SetPoint("RIGHT", right, "LEFT", -4, 0)
    else cell:SetPoint("RIGHT", right, "RIGHT", 0, 0); cell:SetWidth(column.w); right = cell end
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
    knownCost = knownCost + (position.knownCost or 0)
    listedValue = listedValue + (position.listedValue or 0)
  end
  local raw = GC.SellPositions.Summary(filtered)
  return GC.SellViewModel.SummaryText({ knownCost = raw.invested or knownCost, listedValue = listedValue,
    profit = raw.profit, partialCount = partial, unknownCount = unknown })
end

local function updateSummary(filtered)
  local text = summaryFor(filtered)
  container.summary.cost:SetText(formatAmount(text.knownCost))
  container.summary.listed:SetText(formatAmount(text.listedValue))
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
    if not entry then row:Hide()
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
        row.action:Hide()
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
          row.cells.status:SetText("Ready to post")
          row.action:SetLabel("Post"); row.action:SetScript("OnClick", function() onPostClick(row) end)
        else
          row.cells.status:SetText("Missing cost")
          row.action:SetLabel("Set cost"); row.action:SetScript("OnClick", function() openCostDialog(p) end)
        end
        row.action:Show()
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
  refreshPending = true
  setStatus("Refreshing listings…")
  if not requestOwnedAuctions() then onOwnedAuctionsReady() end
end
function GC.Sell.Reset()
  quoting, refreshPending, quoteQueue, quoteIndex, pendingQuote, awaitingKeyInfo = false, false, {}, 0, nil, nil
  GC.QuoteCache.Clear(quotes)
  postingPlan, pendingPost = nil, nil
end

function GC.Sell.Attach(f, geometry)
  ROW_WIDTH, ROW_HEIGHT, statusOwner = geometry.rowWidth, geometry.rowHeight, f
  container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", geometry.panelLeft, geometry.top); container:SetPoint("BOTTOMRIGHT", -geometry.panelRightInset, geometry.bottom); container:Hide()
  local refresh = Theme.Button(container, "ghost")
  refresh:SetSize(72, 20); refresh:SetPoint("TOPRIGHT"); refresh:SetLabel("Refresh"); refresh:SetScript("OnClick", GC.Sell.Refresh)
  local labels = { all = "All", goldcap = "GC", auction_house = "AH", missing_cost = "Missing cost" }
  local previous = refresh
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
  local headerRow = { cells = header.cells }
  layoutCells(headerRow)
  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", 0, -78); scroll:SetPoint("BOTTOMRIGHT")
  content = CreateFrame("Frame", nil, scroll); content:SetSize(ROW_WIDTH, ROW_HEIGHT); scroll:SetScrollChild(content)
  local dialog = CreateFrame("Frame", nil, container, "BackdropTemplate"); dialog:SetSize(270, 130); dialog:SetPoint("CENTER"); dialog:Hide(); container.costDialog = dialog
  dialog.quantity, dialog.unit, dialog.total = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate"), CreateFrame("EditBox", nil, dialog, "InputBoxTemplate"), CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
  for i, edit in ipairs({ dialog.quantity, dialog.unit, dialog.total }) do edit:SetSize(70, 20); edit:SetPoint("TOPLEFT", 12 + (i - 1) * 82, -26); edit:SetAutoFocus(false) end
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
    ROW_WIDTH = math.max(1, width - geometry.panelLeft - geometry.panelRightInset); content:SetWidth(ROW_WIDTH); layoutCells(headerRow); renderRows()
  end)
end
