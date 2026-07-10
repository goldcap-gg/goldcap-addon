local _, GC = ...

GC.Sniper = GC.Sniper or {}

local ROW_HEIGHT = 20
local ROW_CAP = 100 -- hard cap on rendered/pooled deal rows, for both watchlist and full-scan modes
local REQUOTE_MAX_RATIO = 0.05
local ARM_TIMEOUT_SECONDS = 5
local BUY_TIMEOUT_SECONDS = 8
local FULL_SCAN_COOLDOWN_SECONDS = 15 * 60
local FULL_SCAN_BATCH_SIZE = 250
local FULL_SCAN_TICK_DELAY = 0.01
local FULL_SCAN_SAFETY_SECONDS = 2

local TIER_COLOR = {
  HOT = { 1, 0.35, 0.15 },
  GOOD = { 0.25, 0.85, 0.25 },
  WATCH = { 0.65, 0.65, 0.65 },
  SUSPECT = { 1, 0.85, 0.1 },
}

local TIER_RANK = { HOT = 1, GOOD = 2, WATCH = 3, SUSPECT = 4 }

local frame           -- lazily created (see createFrame)
local content          -- scroll child frame; module-level so refreshRows() can grow the row pool into it
local rows = {}        -- pooled row widgets, grown lazily up to ROW_CAP
local deals = {}        -- itemID -> latest watchlist deal shown for it (watchlist mode)
local scanDeals = {}     -- array of deals from the last completed full scan (full-scan mode)
local mode = "watchlist" -- "watchlist" | "fullscan": which backing store sortedDeals() renders
local scanning = false

-- Full-scan (ReplicateItems) state. lastFullScanTime enforces a client-side cooldown
-- (session-only, not persisted -- a /reload resets it, matching the "client-side" scope
-- of this requirement rather than a saved-variable one). fullScanToken is bumped on every
-- new scan and on abort so any C_Timer closures from a superseded/aborted scan become
-- no-ops instead of racing a newer scan's state.
local lastFullScanTime = 0
local fullScanWaiting = false -- true from ReplicateItems() until OnReplicateReady handles the event
local fullScanBatch = nil     -- { rows = {...}, token = n } while batch-iterating; nil when idle
local fullScanToken = 0

-- Purchase-flow bookkeeping. A row is "pinned" (activeItemID[itemID] = true) from the
-- first arming click until the purchase resolves, so refreshRows() never repurposes it
-- mid-flight. pendingAuction tracks in-flight item (non-commodity) buys by auctionID for
-- AUCTION_HOUSE_PURCHASE_COMPLETED lookup; commodityPurchase tracks the single in-flight
-- commodity buy (Blizzard only allows one commodity purchase flow at a time).
local pendingAuction = {}
local activeItemID = {}
local commodityPurchase = nil

GC.Sniper.session = { buys = 0, spent = 0, estProfit = 0 }

local function sortedDeals()
  local list = {}
  if mode == "fullscan" then
    -- GC.FullScan.Evaluate already returns tier-rank/profit sorted order; filtering out
    -- pinned itemIDs preserves that order (no re-sort needed).
    for _, deal in ipairs(scanDeals) do
      if not activeItemID[deal.itemID] then
        list[#list + 1] = deal
      end
    end
    return list
  end
  for itemID, deal in pairs(deals) do
    if not activeItemID[itemID] then
      list[#list + 1] = deal
    end
  end
  table.sort(list, function(a, b)
    local ra, rb = TIER_RANK[a.tier] or 9, TIER_RANK[b.tier] or 9
    if ra ~= rb then return ra < rb end
    return a.profit > b.profit
  end)
  return list
end

local function setRowDeal(row, deal)
  row.deal = deal
  local color = TIER_COLOR[deal.tier] or TIER_COLOR.WATCH
  row.tierText:SetText(deal.tier)
  row.tierText:SetTextColor(color[1], color[2], color[3])
  row.discountText:SetText(("%d%%"):format(math.floor(deal.discount * 100 + 0.5)))
  row.profitText:SetText(GetCoinTextureString(deal.profit))
  row.nameText:SetText(("item %d"):format(deal.itemID))
  row.icon:SetTexture(nil)

  local item = Item:CreateFromItemID(deal.itemID)
  item:ContinueOnItemLoad(function()
    if row.deal ~= deal then return end -- row was repurposed before the async load finished
    row.icon:SetTexture(item:GetItemIcon())
    local quality = item:GetItemQuality()
    local qc = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
    local label = item:GetItemName() or ("item " .. deal.itemID)
    row.nameText:SetText(qc and qc:WrapTextInColorCode(label) or label)
  end)

  row:Show()
end

-- Forward-declared: createRow's real definition lives further down (it needs the row
-- widget-construction helpers), but refreshRows() (below) must be able to grow the row
-- pool on demand. Lua resolves an unbound name at closure-creation time, not call time,
-- so without this forward declaration refreshRows would silently capture a global.
local createRow

-- Rows mid-purchase (row.purchaseStage set) are pinned in place: refreshRows() leaves
-- their content untouched instead of repurposing the widget to a different deal out from
-- under an in-flight click sequence. sortedDeals() already excludes their itemID so no
-- other row duplicates them.
--
-- The row pool grows lazily up to `shown` (itself capped at ROW_CAP) instead of being
-- pre-built at a fixed size: full scans can return far more deals than the old
-- watchlist-only 20-row pool ever needed to hold. `shown` also bounds how many entries of
-- `list` get consumed even if `list` itself is longer (already true for full-scan mode,
-- since GC.FullScan.Evaluate caps to 100 -- this is just a second belt-and-suspenders cap
-- local to rendering). The scroll child's height is stamped every refresh so
-- GetVerticalScrollRange() has something to report once there are more rows than fit.
local function refreshRows()
  if not frame then return end
  local list = sortedDeals()
  local shown = math.min(#list, ROW_CAP)

  for i = #rows + 1, shown do
    rows[i] = createRow(content, i)
  end

  local li = 1
  for i = 1, #rows do
    local row = rows[i]
    if not row.purchaseStage then
      local deal = (li <= shown) and list[li] or nil
      if deal then
        setRowDeal(row, deal)
        li = li + 1
      else
        row.deal = nil
        row:Hide()
      end
    end
  end

  content:SetHeight(math.max(shown, 1) * ROW_HEIGHT)
end

-- Forward-declared: driver.onDeal (below) needs to call this for the "row vanished on
-- rescan" success fallback, but its real definition lives further down alongside the
-- rest of the purchase-flow helpers.
local resolvePurchase

-- Live driver bound to C_AuctionHouse; every WoW-API access below is wrapped in a
-- function so the table itself can be built at file-load with no side effects
-- (required for the headless busted load-order spec).
local driver = {
  isReady = function()
    return C_AuctionHouse.IsThrottledMessageSystemReady()
  end,

  getKeyInfo = function(itemID)
    return C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
  end,

  sendSearch = function(itemID)
    local key = C_AuctionHouse.MakeItemKey(itemID)
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    if info and info.isCommodity then
      C_AuctionHouse.SendSearchQuery(key, {}, false)
    else
      C_AuctionHouse.SendSearchQuery(
        key, { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }, false)
    end
  end,

  itemResult = function(itemID)
    local key = C_AuctionHouse.MakeItemKey(itemID)
    local info = C_AuctionHouse.GetItemSearchResultInfo(key, 1)
    if not info or not info.buyoutAmount or info.buyoutAmount == 0 then return nil end
    return { auctionID = info.auctionID, unitPrice = info.buyoutAmount, qty = info.quantity }
  end,

  commodityResult = function(itemID)
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    if not info then return nil end
    return { unitPrice = info.unitPrice, qty = info.quantity }
  end,

  getValue = GC.Data.GetItemValue,

  onStatus = function(text)
    if frame then frame.status:SetText(text) end
  end,

  onDeal = function(deal)
    -- Fallback success signal for item buys: AUCTION_HOUSE_PURCHASE_COMPLETED is
    -- UNVERIFIED to actually fire, so if a rescan reports a *different* top auction for
    -- an itemID we're mid-purchase on, the auction we bid on is gone from the book —
    -- treat that as a completed snipe.
    local prior = deals[deal.itemID]
    if prior and not deal.isCommodity and prior.auctionID and prior.auctionID ~= deal.auctionID then
      local staleRow = pendingAuction[prior.auctionID]
      if staleRow then
        resolvePurchase(staleRow, true, "sniped (listing changed on rescan)")
      end
    end

    deals[deal.itemID] = deal
    refreshRows()
    if deal.tier == "HOT" and GC.db.settings.sniper.sound then
      PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
  end,

  now = time,
}

local function clearDeals()
  for itemID in pairs(deals) do deals[itemID] = nil end
  refreshRows()
end

local function startScanning()
  if not GC.Sniper.scanner then return end
  mode = "watchlist"
  clearDeals()
  GC.Sniper.scanner:Stop() -- re-Start while a search is in flight drops it silently: always Stop first
  GC.Sniper.scanner:Start(GC.Data.GetWatchlist(100))
  scanning = true
  if frame then frame.toggleBtn:SetText("Stop") end
end

local function stopScanning()
  if GC.Sniper.scanner then GC.Sniper.scanner:Stop() end
  scanning = false
  if frame then frame.toggleBtn:SetText("Start") end
end

-- ---------------------------------------------------------------------------
-- Full Scan (C_AuctionHouse.ReplicateItems). Primary control: a one-shot dump of every
-- current auction, gated by a client-side 15-min cooldown (ReplicateItems is
-- account-wide-throttled server-side; this just avoids firing it needlessly and gives the
-- player a status message instead of a silent no-op). GC.Sniper.OnReplicateReady is the
-- REPLICATE_ITEM_LIST_UPDATE handler Core/Init.lua dispatches into; it batch-iterates
-- GetReplicateItemInfo over frames (FULL_SCAN_BATCH_SIZE per tick via C_Timer.After) so a
-- huge AH listing count never hitches a frame, then hands the collected rows to
-- GC.FullScan.Evaluate. fullScanToken invalidates any in-flight tick/safety-net closures
-- from a scan that was superseded (a new Full Scan click) or aborted (AH closed) so they
-- become no-ops instead of racing fresher state.
-- ---------------------------------------------------------------------------

local function applyFullScanResults(rowsList, listingCount)
  fullScanBatch = nil
  scanDeals = GC.FullScan.Evaluate(rowsList, GC.Data.GetItemValue, GC.db.settings.sniper, 100)
  if frame then
    frame.status:SetText(("full scan complete: %d deal%s from %d listings"):format(
      #scanDeals, #scanDeals == 1 and "" or "s", listingCount))
  end
  refreshRows()
end

local function fullScanTick(nextIndex, n, rowsAcc, token)
  if token ~= fullScanToken then return end -- superseded by a newer scan, or aborted
  local endIndex = math.min(nextIndex + FULL_SCAN_BATCH_SIZE - 1, n - 1)
  for i = nextIndex, endIndex do
    -- VERIFIED signature (12.0.7): 18 return values, 0-based index -- name, texture, count,
    -- qualityID, usable, level, levelType, minBid, minIncrement, buyoutPrice, bidAmount,
    -- highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAllInfo.
    -- Only count(3)/buyoutPrice(10)/itemID(17) are needed to evaluate a deal --
    -- hasAllInfo=false still supplies these even before the item name loads async.
    -- Captured into a table rather than 18 named locals to avoid a wall of unused vars.
    local info = { C_AuctionHouse.GetReplicateItemInfo(i) }
    local count, buyoutPrice, itemID = info[3], info[10], info[17]
    if itemID and count and count > 0 and buyoutPrice and buyoutPrice > 0 then
      rowsAcc[#rowsAcc + 1] = { itemID = itemID, count = count, buyoutStack = buyoutPrice }
    end
  end

  if endIndex >= n - 1 then
    fullScanBatch = nil
    applyFullScanResults(rowsAcc, n)
  else
    fullScanBatch = { rows = rowsAcc, token = token, lastProgress = time() }
    if frame then frame.status:SetText(("scanning %d/%d..."):format(endIndex + 1, n)) end
    C_Timer.After(FULL_SCAN_TICK_DELAY, function()
      fullScanTick(endIndex + 1, n, rowsAcc, token)
    end)
  end
end

-- Rolling safety net: re-arms itself every FULL_SCAN_SAFETY_SECONDS for as long as the
-- batch is still progressing, and only force-finishes (with whatever rows were collected so
-- far) if no tick has advanced within the last window -- i.e. the tick chain has genuinely
-- stalled. A single one-shot timer from scan start would instead cap EVERY full scan's
-- total duration at ~2s, which truncates any realm with enough listings that a full,
-- steadily-progressing scan legitimately takes longer than one window (easily true on a
-- populated realm at 250 indices/10ms). Bumping the token on force-finish invalidates the
-- stalled chain so it can't resume later and double-apply results.
local function fullScanWatchdog(token, n)
  if not (fullScanBatch and fullScanBatch.token == token) then return end -- already finished/aborted
  if time() - fullScanBatch.lastProgress >= FULL_SCAN_SAFETY_SECONDS then
    local pendingRows = fullScanBatch.rows
    fullScanBatch = nil
    fullScanToken = fullScanToken + 1
    applyFullScanResults(pendingRows, n)
    return
  end
  C_Timer.After(FULL_SCAN_SAFETY_SECONDS, function()
    fullScanWatchdog(token, n)
  end)
end

function GC.Sniper.OnReplicateReady()
  if not fullScanWaiting then return end -- not currently expecting this event; ignore
  fullScanWaiting = false

  local token = fullScanToken
  local n = C_AuctionHouse.GetNumReplicateItems() or 0
  local rowsAcc = {}

  if n == 0 then
    applyFullScanResults(rowsAcc, 0)
    return
  end

  fullScanBatch = { rows = rowsAcc, token = token, lastProgress = time() }
  fullScanTick(0, n, rowsAcc, token)
  C_Timer.After(FULL_SCAN_SAFETY_SECONDS, function()
    fullScanWatchdog(token, n)
  end)
end

-- Cancels any full scan in flight (waiting for the ready event, or mid-batch-iteration).
-- Called on AUCTION_HOUSE_CLOSED per the verified API note that a scan should not keep
-- running once the player has left the Auction House.
local function abortFullScan()
  if fullScanWaiting or fullScanBatch then
    fullScanToken = fullScanToken + 1 -- invalidates any in-flight tick/safety-net closures
  end
  fullScanWaiting = false
  fullScanBatch = nil
end

local function onFullScanClick()
  if not frame then return end
  if not GC.Sniper.scanner then
    frame.status:SetText("Open the Auction House first.")
    return
  end

  local now = time()
  if lastFullScanTime > 0 then
    local remaining = FULL_SCAN_COOLDOWN_SECONDS - (now - lastFullScanTime)
    if remaining > 0 then
      frame.status:SetText(("full scan on cooldown: %ds remaining"):format(remaining))
      return
    end
  end

  lastFullScanTime = now
  fullScanToken = fullScanToken + 1
  fullScanBatch = nil
  fullScanWaiting = true
  mode = "fullscan"
  refreshRows() -- reflect the mode switch immediately (shows the prior full-scan results, if any)
  C_AuctionHouse.ReplicateItems()
  frame.status:SetText("scanning...")
end

-- ---------------------------------------------------------------------------
-- Purchase flow. Item buy: two clicks (arm -> PlaceBid). Commodity buy: three
-- clicks (arm -> StartCommoditiesPurchase -> ConfirmCommoditiesPurchase),
-- because COMPLIANCE requires the final commodity confirm to ALWAYS come from a
-- human click regardless of whether the requote rose (matching native WoW's
-- always-present commodity confirm dialog). Every C_AuctionHouse purchase call
-- (PlaceBid / StartCommoditiesPurchase / ConfirmCommoditiesPurchase) is reached
-- ONLY from onBuyClick, the button OnClick closure — never from an event or a
-- timer. COMMODITY_PRICE_UPDATED only sets a confirm STAGE and re-enables the
-- button; only ONE commodity purchase may be in flight at a time.
-- ---------------------------------------------------------------------------

local function resetRowButton(row)
  row.buy:Enable()
  row.buy:SetText("Buy")
  local fs = row.buy.GetFontString and row.buy:GetFontString()
  if fs then fs:SetTextColor(1, 1, 1) end
end

resolvePurchase = function(row, success, note)
  local deal = row.purchaseDeal or row.deal
  if deal then
    activeItemID[deal.itemID] = nil
    if deal.isCommodity then
      if commodityPurchase == row then commodityPurchase = nil end
    elseif deal.auctionID then
      pendingAuction[deal.auctionID] = nil
    end
    if success then
      local session = GC.Sniper.session
      session.buys = session.buys + 1
      session.spent = session.spent + deal.unitPrice * deal.qty
      session.estProfit = session.estProfit + deal.profit
      if deals[deal.itemID] == deal then deals[deal.itemID] = nil end
    end
  end

  row.purchaseStage = nil
  row.purchaseDeal = nil
  resetRowButton(row)
  if frame and note then frame.status:SetText(note) end
  refreshRows()
end

local function disarmRow(row, deal)
  row.purchaseStage = nil
  activeItemID[deal.itemID] = nil
  resetRowButton(row)
end

local function armRow(row, deal)
  row.purchaseStage = "armed"
  row.purchaseDeal = nil
  activeItemID[deal.itemID] = true
  row.buy:SetText("Confirm")
  C_Timer.After(ARM_TIMEOUT_SECONDS, function()
    if row.purchaseStage == "armed" and row.deal == deal then
      disarmRow(row, deal)
    end
  end)
end

local function scheduleBuyTimeout(row, deal)
  C_Timer.After(BUY_TIMEOUT_SECONDS, function()
    if row.purchaseStage == "buying" and row.purchaseDeal == deal then
      resolvePurchase(row, false, "no purchase confirmation received")
    end
  end)
end

-- Router functions the Init.lua event frame dispatches into.

function GC.Sniper.OnPurchaseCompleted(auctionID)
  local row = pendingAuction[auctionID]
  if not row then return end
  local deal = row.purchaseDeal
  resolvePurchase(row, true, deal and ("sniped for " .. GetCoinTextureString(deal.unitPrice * deal.qty)) or "purchase complete")
end

function GC.Sniper.OnCommodityPriceUpdated(_unitPrice, totalPrice)
  local row = commodityPurchase
  if not row then return end
  if row.purchaseStage == "confirming" then return end -- third-click confirm already in flight; don't re-enable the button
  local deal = row.purchaseDeal
  if not deal then return end

  -- COMPLIANCE: a commodity purchase's final ConfirmCommoditiesPurchase() must ALWAYS come
  -- from a human click (matching native WoW's always-present commodity confirm dialog), so
  -- BOTH branches only set a confirm STAGE here and re-enable the button; the actual confirm
  -- call happens later in onBuyClick (the OnClick closure). This handler never completes a
  -- purchase.
  row.buy:Enable()
  if GC.DealMath.PriceIncreaseExceeds(deal.unitPrice * deal.qty, totalPrice, REQUOTE_MAX_RATIO) then
    -- Price rose beyond tolerance: red prompt, awaits an explicit third click.
    row.purchaseStage = "requote"
    row.buy:SetText("Confirm!")
    local fs = row.buy.GetFontString and row.buy:GetFontString()
    if fs then fs:SetTextColor(1, 0.2, 0.2) end
    if frame then
      frame.status:SetText(("price rose to %s -- click Confirm to accept"):format(GetCoinTextureString(totalPrice)))
    end
  else
    -- Within tolerance: neutral prompt, still awaits an explicit third click.
    row.purchaseStage = "confirm"
    row.buy:SetText("Confirm")
    local fs = row.buy.GetFontString and row.buy:GetFontString()
    if fs then fs:SetTextColor(1, 1, 1) end
    if frame then
      frame.status:SetText(("quote %s -- click Confirm to buy"):format(GetCoinTextureString(totalPrice)))
    end
  end
end

function GC.Sniper.OnCommodityPriceUnavailable()
  local row = commodityPurchase
  if not row then return end
  C_AuctionHouse.CancelCommoditiesPurchase()
  resolvePurchase(row, false, "commodity price unavailable -- canceled")
end

function GC.Sniper.OnCommodityPurchaseSucceeded()
  local row = commodityPurchase
  if not row then return end
  local deal = row.purchaseDeal
  resolvePurchase(row, true, deal and ("bought %d x item %d"):format(deal.qty, deal.itemID) or "purchase complete")
end

function GC.Sniper.OnCommodityPurchaseFailed()
  local row = commodityPurchase
  if not row then return end
  resolvePurchase(row, false, "commodity purchase failed")
end

local function onBuyClick(row)
  local deal = row.deal
  if not deal then return end

  if row.purchaseStage == "confirm" or row.purchaseStage == "requote" then
    -- Third explicit click: the ONLY path that confirms a commodity purchase, for both the
    -- within-tolerance ("confirm") and raised-price ("requote") prompts. Compliance: a
    -- commodity buy's final confirm always comes from a human click.
    -- Retail 12.0.7 requires (itemID, quantity) matching the StartCommoditiesPurchase call;
    -- use the frozen purchaseDeal, not row.deal (a rescan may have replaced row.deal).
    local pd = row.purchaseDeal
    C_AuctionHouse.ConfirmCommoditiesPurchase(pd.itemID, pd.qty)
    row.purchaseStage = "confirming"
    row.buy:Disable()
    if frame then frame.status:SetText("confirming purchase...") end
    return
  end

  if row.purchaseStage == "buying" or row.purchaseStage == "confirming" then
    return -- purchase already in flight; button is disabled but guard anyway
  end

  if row.purchaseStage == "armed" then
    -- Second click: fire the real purchase call synchronously, right here in OnClick.
    if deal.isCommodity and commodityPurchase and commodityPurchase ~= row then
      -- Only ONE commodity purchase may be in flight at a time; a second would silently
      -- overwrite commodityPurchase and orphan the first (its confirm, session credit and
      -- timeout would misattribute). Reject: re-disarm this row and leave the pending one.
      disarmRow(row, deal)
      driver.onStatus("finish the pending buy first")
      return
    end
    row.purchaseStage = "buying"
    row.purchaseDeal = deal
    row.buy:Disable()
    if deal.isCommodity then
      commodityPurchase = row
      C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, deal.qty)
      if frame then frame.status:SetText("buying commodity...") end
    else
      pendingAuction[deal.auctionID] = row
      C_AuctionHouse.PlaceBid(deal.auctionID, deal.unitPrice)
      if frame then frame.status:SetText("placing bid...") end
    end
    scheduleBuyTimeout(row, deal)
    return
  end

  -- First click: arm.
  armRow(row, deal)
end

-- Cancels/resets any purchase in flight and clears the tracking tables. Used on AH close
-- so stale disabled buttons or pinned rows never leak into the next Auction House visit.
local function resetAllPurchases()
  if not frame then return end
  for i = 1, #rows do
    local row = rows[i]
    if row.purchaseStage then
      row.purchaseStage = nil
      row.purchaseDeal = nil
      resetRowButton(row)
    end
  end
  for k in pairs(pendingAuction) do pendingAuction[k] = nil end
  for k in pairs(activeItemID) do activeItemID[k] = nil end
  commodityPurchase = nil
end

createRow = function(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(360, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(16, 16)
  icon:SetPoint("LEFT")
  row.icon = icon

  local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  nameText:SetWidth(130)
  nameText:SetJustifyH("LEFT")
  -- One line only: a wrapped name would grow taller than ROW_HEIGHT and visually overlap
  -- the row below it. SetWordWrap(false) keeps long names from wrapping; SetMaxLines(1) is
  -- a belt-and-suspenders cap on top of that.
  nameText:SetWordWrap(false)
  nameText:SetMaxLines(1)
  row.nameText = nameText

  local tierText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  tierText:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
  tierText:SetWidth(52)
  tierText:SetJustifyH("LEFT")
  row.tierText = tierText

  local discountText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  discountText:SetPoint("LEFT", tierText, "RIGHT", 4, 0)
  discountText:SetWidth(36)
  row.discountText = discountText

  local profitText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  profitText:SetPoint("LEFT", discountText, "RIGHT", 4, 0)
  profitText:SetWidth(90)
  profitText:SetJustifyH("LEFT")
  row.profitText = profitText

  local buy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  buy:SetSize(50, 18)
  buy:SetPoint("RIGHT")
  buy:SetText("Buy")
  row.buy = buy
  buy:SetScript("OnClick", function()
    onBuyClick(row)
  end)

  row:Hide()
  return row
end

local function createFrame()
  local f = CreateFrame("Frame", "GoldCapSniperFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(420, 480)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("GoldCap Sniper")

  -- Full Scan is the primary control (rightmost, larger). The watchlist Start/Stop toggle
  -- is now secondary: shrunk and anchored to Full Scan's left so it reads as the
  -- lesser-emphasis option.
  local fullScanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  fullScanBtn:SetSize(100, 24)
  fullScanBtn:SetPoint("TOPRIGHT", -14, -30)
  fullScanBtn:SetText("Full Scan")
  fullScanBtn:SetScript("OnClick", onFullScanClick)
  f.fullScanBtn = fullScanBtn

  local toggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  toggleBtn:SetSize(56, 18)
  toggleBtn:SetPoint("RIGHT", fullScanBtn, "LEFT", -6, 0)
  toggleBtn:SetText("Start")
  toggleBtn:SetScript("OnClick", function()
    if not GC.Sniper.scanner then
      f.status:SetText("Open the Auction House first.")
      return
    end
    if scanning then
      stopScanning()
    else
      startScanning()
    end
  end)
  f.toggleBtn = toggleBtn

  local status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", 14, -34)
  status:SetPoint("RIGHT", toggleBtn, "LEFT", -8, 0)
  status:SetJustifyH("LEFT")
  status:SetText("Open the Auction House to begin scanning.")
  f.status = status

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -58)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    local target = self:GetVerticalScroll() - delta * ROW_HEIGHT * 3
    if target < 0 then target = 0 end
    if target > range then target = range end
    self:SetVerticalScroll(target)
  end)

  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(360, ROW_HEIGHT) -- refreshRows() stamps the real height once there are deals to show
  scroll:SetScrollChild(content)

  table.insert(UISpecialFrames, "GoldCapSniperFrame") -- Escape closes the window

  return f
end

function GC.Sniper.Toggle()
  frame = frame or createFrame()
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
  end
end

function GC.Sniper.OnAuctionHouseShow()
  -- Build the scanner on the first AH visit regardless of autoOpen, so a later
  -- manual Toggle + Start has one to drive.
  GC.Sniper.scanner = GC.Sniper.scanner or GC.Scanner.New(driver, GC.db.settings.sniper)
  -- autoOpen gates the WINDOW: on it auto-appears and auto-scans; off it stays
  -- hidden until the player opens it via /goldcap sniper (Toggle) and clicks Start.
  if not GC.db.settings.sniper.autoOpen then return end
  frame = frame or createFrame()
  frame:Show()
  startScanning()
end

function GC.Sniper.OnAuctionHouseClosed()
  -- Wired from both PLAYER_INTERACTION_MANAGER_FRAME_HIDE and AUCTION_HOUSE_CLOSED (their
  -- overlap on a given close is unverified in 12.0.7 -- see in-game checklist), so this must
  -- tolerate being called twice for one AH visit without double-printing or double-crediting.
  stopScanning()
  abortFullScan()

  local session = GC.Sniper.session
  if session.buys > 0 then
    GC.Print(("session: %d snipes, spent %s, ~%s est. profit"):format(
      session.buys, GetCoinTextureString(session.spent), GetCoinTextureString(session.estProfit)))
    session.buys, session.spent, session.estProfit = 0, 0, 0
  end

  local scanner = GC.Sniper.scanner
  if scanner and scanner.scanned > 0 then
    GC.Print(("scanned %d listings over %d passes"):format(scanner.scanned, scanner.cycles))
    scanner.scanned = 0
  end

  resetAllPurchases()
  clearDeals() -- next AH visit starts from a clean slate; stale auctions are no longer live
  if frame then frame:Hide() end
end
