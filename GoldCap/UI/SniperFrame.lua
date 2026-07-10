local _, GC = ...

GC.Sniper = GC.Sniper or {}

local ROW_HEIGHT = 20
local MAX_ROWS = 20
local REQUOTE_MAX_RATIO = 0.05
local ARM_TIMEOUT_SECONDS = 5
local BUY_TIMEOUT_SECONDS = 8

local TIER_COLOR = {
  HOT = { 1, 0.35, 0.15 },
  GOOD = { 0.25, 0.85, 0.25 },
  WATCH = { 0.65, 0.65, 0.65 },
  SUSPECT = { 1, 0.85, 0.1 },
}

local TIER_RANK = { HOT = 1, GOOD = 2, WATCH = 3, SUSPECT = 4 }

local frame           -- lazily created (see createFrame)
local rows = {}        -- pooled row widgets, index 1..MAX_ROWS
local deals = {}        -- itemID -> latest deal shown for it
local scanning = false

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

-- Rows mid-purchase (row.purchaseStage set) are pinned in place: refreshRows() leaves
-- their content untouched instead of repurposing the widget to a different deal out from
-- under an in-flight click sequence. sortedDeals() already excludes their itemID so no
-- other row duplicates them.
local function refreshRows()
  if not frame then return end
  local list = sortedDeals()
  local li = 1
  for i = 1, MAX_ROWS do
    local row = rows[i]
    if not row.purchaseStage then
      local deal = list[li]
      if deal then
        setRowDeal(row, deal)
        li = li + 1
      else
        row.deal = nil
        row:Hide()
      end
    end
  end
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
  for i = 1, MAX_ROWS do
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

local function createRow(parent, index)
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

  local toggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  toggleBtn:SetSize(80, 22)
  toggleBtn:SetPoint("TOPRIGHT", -14, -30)
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

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(360, MAX_ROWS * ROW_HEIGHT)
  scroll:SetScrollChild(content)

  for i = 1, MAX_ROWS do
    rows[i] = createRow(content, i)
  end

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
  stopScanning()

  local session = GC.Sniper.session
  if session.buys > 0 then
    GC.Print(("session: %d snipes, spent %s, ~%s est. profit"):format(
      session.buys, GetCoinTextureString(session.spent), GetCoinTextureString(session.estProfit)))
    session.buys, session.spent, session.estProfit = 0, 0, 0
  end

  local scanner = GC.Sniper.scanner
  if scanner and scanner.scanned > 0 then
    GC.Print(("scanned %d listings over %d passes"):format(scanner.scanned, scanner.cycles))
  end

  resetAllPurchases()
  clearDeals() -- next AH visit starts from a clean slate; stale auctions are no longer live
  if frame then frame:Hide() end
end
