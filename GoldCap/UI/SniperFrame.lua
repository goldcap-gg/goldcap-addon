local _, GC = ...

GC.Sniper = GC.Sniper or {}

local ROW_HEIGHT = 20
local ROW_CAP = 100 -- hard cap on rendered/pooled deal rows, for both watchlist and full-scan modes

-- Frame/row geometry. ROW_WIDTH is derived from FRAME_WIDTH (not hardcoded separately) so
-- the row pool (createRow) and the scroll child it lives in (createFrame) can never drift
-- apart the way they did before -- that drift is exactly what let the Buy button paint over
-- the profit column. Column widths/gaps below are shared between createRow's per-row
-- anchors and createFrame's header labels for the same reason: one set of numbers feeding
-- both the data rows and the header row that has to line up with them.
local FRAME_WIDTH = 560
local FRAME_HEIGHT = 480
local PANEL_LEFT = 14
local PANEL_RIGHT_INSET = 32 -- scrollbar gutter reserved by UIPanelScrollFrameTemplate
local ROW_WIDTH = FRAME_WIDTH - PANEL_LEFT - PANEL_RIGHT_INSET

local ICON_SIZE = 16
local NAME_GAP = 4    -- icon -> name
local COLUMN_GAP = 6   -- name -> tier -> discount -> price -> profit
local BUY_GAP = 4     -- profit -> buy; tighter so the button reads as attached to the price it buys
local TIER_WIDTH = 44
local DISCOUNT_WIDTH = 40
local PRICE_WIDTH = 95
local PROFIT_WIDTH = 95
local BUY_WIDTH = 50

local REQUOTE_MAX_RATIO = 0.05
local ARM_TIMEOUT_SECONDS = 5
local BUY_TIMEOUT_SECONDS = 8
local REQUERY_TIMEOUT_SECONDS = 8
-- If no browse event arrives within this long after a send (initial query or page
-- request), the paging chain is presumed stalled -- see armScanWatchdog.
local SCAN_WATCHDOG_SECONDS = 15

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

-- Full-scan (Auctionator-style incremental browse) state. A full scan pages through
-- C_AuctionHouse's browse results with SendBrowseQuery + RequestMoreBrowseResults until
-- HasFullBrowseResults() reports true. Browse queries carry no server-side cooldown -- there
-- is no timestamp to track, and a scan is always safe to re-run immediately. fullScanToken is
-- bumped on every new scan and on abort so any C_Timer watchdog closures from a
-- superseded/aborted scan become no-ops instead of racing a newer scan's state.
local scanRunning = false          -- true from startFullScan() until the browse pages finish, stall, or the scan is aborted
local pendingFullScanStart = false -- Full Scan was clicked while the throttle system was busy; GC.Sniper.OnThrottleReady sends the initial query once it clears
local pendingBrowsePage = false    -- a page (RequestMoreBrowseResults) is due but the throttle system was busy; GC.Sniper.OnThrottleReady sends it once it clears
local lastBrowseEventAt = 0        -- time() of the last browse-results event seen for the current scan; armScanWatchdog compares this against each send
local fullScanToken = 0

-- Purchase-flow bookkeeping. A row is "pinned" (activeItemID[itemID] = true) from the
-- first arming click until the purchase resolves, so refreshRows() never repurposes it
-- mid-flight. pendingAuction tracks in-flight item (non-commodity) buys by auctionID for
-- AUCTION_HOUSE_PURCHASE_COMPLETED lookup; commodityPurchase tracks the single in-flight
-- commodity buy (Blizzard only allows one commodity purchase flow at a time).
local pendingAuction = {}
local activeItemID = {}
local commodityPurchase = nil

-- Task-3 buy-after-scan requery. A full-scan deal's snapshot price/auction can be stale
-- (a browse result is a per-itemKey aggregate across every seller, not a resolved auction,
-- and it's a point-in-time snapshot besides), so the FIRST Buy click on one issues a fresh
-- SendSearchQuery instead of arming straight off scanDeals. These two tables are keyed by
-- itemID and live on the FRAME, deliberately separate from the watchlist scanner's own
-- single-slot `pending` state (Core/Scanner.lua), so a requery in flight can never collide
-- with -- or get misrouted into -- an unrelated watchlist scan cycle.
-- awaitingRequery: itemID -> row, from the moment SendSearchQuery is issued until the
-- matching ITEM_SEARCH_RESULTS_UPDATED/COMMODITY_SEARCH_RESULTS_UPDATED arrives.
-- awaitingKeyInfo: itemID -> row, only populated when GetItemKeyInfo wasn't cached yet and
-- the requery is waiting on ITEM_KEY_ITEM_INFO_RECEIVED before it can even send the query.
-- pendingRequerySend: itemID -> true, when the requery is ready to search but the throttle
-- system was busy (typical right after a Full Scan, which saturates it) so the actual
-- SendSearchQuery is deferred to the next AUCTION_HOUSE_THROTTLED_SYSTEM_READY.
local awaitingRequery = {}
local awaitingKeyInfo = {}
local pendingRequerySend = {}

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

local GOLD_COMPACT_THRESHOLD = 100 * 10000 -- 100g in copper

-- GetCoinTextureString's inline coin icons are too wide for a 95px price/profit column once
-- the amount climbs into three-plus digit gold -- collapse anything >= 100g to a plain
-- "<N>g" instead of letting the icon string overflow the column.
local function formatColumnAmount(copper)
  if copper >= GOLD_COMPACT_THRESHOLD then
    return ("%dg"):format(math.floor(copper / 10000))
  end
  return GetCoinTextureString(copper)
end

-- Dim suffix appended after the (possibly quality-colored) item name; a separate color code
-- of its own so it never inherits the name's quality color.
local function qtySuffix(deal)
  if deal.qty and deal.qty > 1 then
    return ("|cffaaaaaa x%d|r"):format(deal.qty)
  end
  return ""
end

local function setRowDeal(row, deal)
  row.deal = deal
  local color = TIER_COLOR[deal.tier] or TIER_COLOR.WATCH
  row.tierText:SetText(deal.tier)
  row.tierText:SetTextColor(color[1], color[2], color[3])
  row.discountText:SetText(("%d%%"):format(math.floor(deal.discount * 100 + 0.5)))
  row.priceText:SetText(formatColumnAmount(deal.unitPrice * deal.qty)) -- total cost, not per-unit
  row.profitText:SetText(formatColumnAmount(deal.profit))
  row.nameText:SetText(("item %d"):format(deal.itemID) .. qtySuffix(deal))
  row.icon:SetTexture(nil)

  local item = Item:CreateFromItemID(deal.itemID)
  item:ContinueOnItemLoad(function()
    if row.deal ~= deal then return end -- row was repurposed before the async load finished
    row.icon:SetTexture(item:GetItemIcon())
    local quality = item:GetItemQuality()
    local qc = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
    local label = item:GetItemName() or ("item " .. deal.itemID)
    row.nameText:SetText((qc and qc:WrapTextInColorCode(label) or label) .. qtySuffix(deal))
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
    if not info.quantity or info.quantity <= 0 then return nil end
    -- info.buyoutAmount is the TOTAL price for the whole lot, not a per-unit price (unlike
    -- GetCommoditySearchResultInfo's unitPrice below) -- divide down so GC.DealMath.Evaluate
    -- compares against value.mv (a per-unit market value) correctly, matching how
    -- FullScan.Evaluate derives unitPrice from a row's per-group buyoutStack total.
    return {
      auctionID = info.auctionID,
      unitPrice = math.floor(info.buyoutAmount / info.quantity),
      qty = info.quantity,
    }
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
  if frame then frame.toggleBtn:SetText("Live") end
end

-- ---------------------------------------------------------------------------
-- Full Scan (Auctionator-style incremental browse). Primary control: pages through the
-- entire realm auction house via C_AuctionHouse.SendBrowseQuery (an empty search matches
-- everything) followed by repeated RequestMoreBrowseResults calls until
-- HasFullBrowseResults() reports true. GC.Sniper.OnBrowseResults/OnBrowseResultsAdded are the
-- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED/ADDED handlers Core/Init.lua dispatches into; each one
-- advances the paging state machine by one step. Browse queries carry no server-side
-- cooldown, so a scan is always safe to re-run immediately -- there is no timestamp to gate
-- on. fullScanToken invalidates any in-flight watchdog closures from a scan that was
-- superseded (a new Full Scan click) or aborted (AH closed) so they become no-ops instead of
-- racing fresher state.
-- ---------------------------------------------------------------------------

local function applyFullScanResults(rowsList, groupCount)
  scanDeals = GC.FullScan.Evaluate(rowsList, GC.Data.GetItemValue, GC.db.settings.sniper, 100)
  -- A browse result is a per-itemKey aggregate across every seller of that item group, not a
  -- single resolved auction: isCommodity is unknown here and auctionID is always nil. Mark
  -- every deal `.stale` so onBuyClick knows to requery live before it will let one arm for
  -- purchase, instead of ever placing a bid/commodity purchase off the aggregate.
  for _, deal in ipairs(scanDeals) do
    deal.stale = true
  end
  if frame then
    frame.status:SetText(("full scan complete: %d deal%s from %d item group%s"):format(
      #scanDeals, #scanDeals == 1 and "" or "s", groupCount, groupCount == 1 and "" or "s"))
  end
  refreshRows()
end

-- Re-armed after every send (the initial SendBrowseQuery and each RequestMoreBrowseResults).
-- If no browse event has landed by the time this fires, the paging chain has genuinely
-- stalled -- clear scan state instead of leaving the status frozen forever. Browse queries
-- have no server cooldown, so retrying costs nothing; the status line says so.
local function armScanWatchdog(token)
  local sentAt = time()
  C_Timer.After(SCAN_WATCHDOG_SECONDS, function()
    if token ~= fullScanToken or not scanRunning then return end -- superseded, aborted, or already finished
    if lastBrowseEventAt < sentAt then
      scanRunning = false
      pendingBrowsePage = false
      if frame then frame.status:SetText("full scan stalled -- press Full Scan to retry") end
    end
  end)
end

local function sendBrowseQuery(token)
  C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
  if frame then frame.status:SetText("scanning auction house...") end
  armScanWatchdog(token)
end

local function sendBrowsePage(token)
  C_AuctionHouse.RequestMoreBrowseResults()
  armScanWatchdog(token)
end

-- Requests the next page, but ONLY when the throttle system is ready --
-- RequestMoreBrowseResults silently no-ops while IsThrottledMessageSystemReady() is false
-- (routine mid-scan, since a full scan's own traffic saturates the throttle). If busy, park
-- the request in pendingBrowsePage for GC.Sniper.OnThrottleReady to flush once it clears.
local function requestNextPage(token)
  if driver.isReady() then
    sendBrowsePage(token)
  else
    pendingBrowsePage = true
  end
end

-- Shared step for both browse events: a batch of itemKey aggregates arrived (the first
-- batch on OnBrowseResults, an increment on OnBrowseResultsAdded) -- either it's the final
-- page (HasFullBrowseResults) and the scan is done, or there's more to fetch.
local function advanceBrowseScan(token)
  if C_AuctionHouse.HasFullBrowseResults() then
    scanRunning = false
    local browseResults = C_AuctionHouse.GetBrowseResults()
    applyFullScanResults(GC.FullScan.RowsFromBrowse(browseResults, GC.Data.GetItemValue), #browseResults)
  else
    local n = #C_AuctionHouse.GetBrowseResults()
    if frame then
      frame.status:SetText(("scanning... %d item group%s"):format(n, n == 1 and "" or "s"))
    end
    requestNextPage(token)
  end
end

-- Cancels any full scan in flight (waiting on the throttle system, or mid-paging). Called on
-- AUCTION_HOUSE_CLOSED per the verified API note that a scan should not keep running once
-- the player has left the Auction House -- browse results die with the AH session anyway.
local function abortFullScan()
  if scanRunning or pendingFullScanStart then
    fullScanToken = fullScanToken + 1 -- invalidates any in-flight watchdog closures
  end
  scanRunning = false
  pendingFullScanStart = false
  pendingBrowsePage = false
end

-- Starts the actual browse scan. Only ever reached once the throttle system is confirmed
-- ready (synchronously from onFullScanClick, or deferred via GC.Sniper.OnThrottleReady when
-- pendingFullScanStart was set) -- SendBrowseQuery silently no-ops while
-- C_AuctionHouse.IsThrottledMessageSystemReady() is false, which is routinely the case for a
-- beat right after opening the Auction House.
local function startFullScan()
  fullScanToken = fullScanToken + 1
  local token = fullScanToken
  scanRunning = true
  pendingBrowsePage = false
  lastBrowseEventAt = 0
  mode = "fullscan"
  refreshRows() -- reflect the mode switch immediately (shows the prior full-scan results, if any)

  if driver.isReady() then
    sendBrowseQuery(token)
  else
    pendingFullScanStart = true
    if frame then frame.status:SetText("waiting for server... full scan will start automatically") end
  end
end

local function onFullScanClick()
  if not frame then return end
  if not GC.Sniper.scanner then
    frame.status:SetText("Open the Auction House first.")
    return
  end

  if scanRunning or pendingFullScanStart then
    frame.status:SetText("full scan already in progress")
    return
  end

  startFullScan()
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
      -- A full-scan buy resolves against the LIVE deal finishRequery swapped in, not the
      -- original .stale scanDeals entry -- which still holds the pre-purchase snapshot for
      -- this itemID (now deduped to one row per item, see FullScan.Evaluate). Drop it so the
      -- consumed listing doesn't reappear as a ghost row on the next refreshRows().
      for i = #scanDeals, 1, -1 do
        if scanDeals[i].itemID == deal.itemID then table.remove(scanDeals, i) end
      end
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

-- ---------------------------------------------------------------------------
-- Task-3 buy-after-scan requery: the FIRST Buy click on a `.stale` (full-scan) deal never
-- arms straight off the scan snapshot. It pins the row ("requerying"), issues a fresh
-- driver.sendSearch(itemID) (guarding the item key not being cached yet -- see
-- GC.Sniper.OnItemKeyInfo below), and waits for the matching search-results event.
-- finishRequery() then either hands the row a real, non-stale live deal ("requeried" --
-- pinned, button back to "Buy", so the very NEXT click runs onBuyClick's normal first-click
-- arm path exactly like a watchlist deal) or gives up gracefully ("gone / price changed",
-- row re-enabled, unpinned). No C_AuctionHouse purchase call is ever reached from this
-- path -- only PlaceBid/StartCommoditiesPurchase/ConfirmCommoditiesPurchase inside
-- onBuyClick complete a purchase, unchanged.
-- ---------------------------------------------------------------------------

-- Issues the fresh live query for a requery, but ONLY when the throttle system is ready.
-- SendSearchQuery silently no-ops while IsThrottledMessageSystemReady() is false -- which it
-- routinely is for a beat right after a Full Scan (the scan's own browse paging saturates
-- the throttle) -- so if we're not ready, park the itemID in pendingRequerySend and let
-- GC.Sniper.OnThrottleReady flush it. The 8s requery timeout remains the ultimate fallback.
local function issueRequerySearch(itemID)
  if driver.isReady() then
    driver.sendSearch(itemID)
  else
    pendingRequerySend[itemID] = true
  end
end

local function finishRequery(row, itemID, liveDeal)
  awaitingRequery[itemID] = nil
  awaitingKeyInfo[itemID] = nil
  pendingRequerySend[itemID] = nil
  if row.purchaseStage ~= "requerying" then return end -- stale/late event: reset already ran (AH closed, timed out, ...)

  if liveDeal then
    setRowDeal(row, liveDeal) -- swaps the row onto the fresh, non-stale deal (real auctionID/unitPrice/qty/isCommodity)
    row.purchaseStage = "requeried" -- still pinned; NOT armed yet -- the next Buy click arms it
    resetRowButton(row)
    if frame then frame.status:SetText("live price confirmed -- click Buy to purchase") end
  else
    activeItemID[itemID] = nil
    row.purchaseStage = nil
    resetRowButton(row)
    if frame then frame.status:SetText("gone / price changed") end
  end
  refreshRows()
end

local function scheduleRequeryTimeout(row, deal)
  C_Timer.After(REQUERY_TIMEOUT_SECONDS, function()
    if row.purchaseStage == "requerying" and row.deal == deal then
      finishRequery(row, deal.itemID, nil)
    end
  end)
end

local function startRequery(row, deal)
  local itemID = deal.itemID
  row.purchaseStage = "requerying"
  row.purchaseDeal = nil
  activeItemID[itemID] = true
  row.buy:Disable()
  row.buy:SetText("...")
  if frame then frame.status:SetText("checking live price...") end

  awaitingRequery[itemID] = row
  scheduleRequeryTimeout(row, deal)

  -- Guard against the item key not being cached: GetItemKeyInfo (via driver.getKeyInfo) can
  -- return nil for an itemID nothing has queried yet this session. When it does, wait for
  -- ITEM_KEY_ITEM_INFO_RECEIVED (GC.Sniper.OnItemKeyInfo below) and retry once from there,
  -- rather than calling driver.sendSearch on a key WoW hasn't resolved yet.
  if driver.getKeyInfo(itemID) then
    issueRequerySearch(itemID)
  else
    awaitingKeyInfo[itemID] = row
  end
end

-- Router functions the Init.lua event frame dispatches into.

function GC.Sniper.OnItemKeyInfo(itemID)
  local row = awaitingKeyInfo[itemID]
  if not row then return end -- not something Task-3 requery is waiting on for this item
  awaitingKeyInfo[itemID] = nil
  if row.purchaseStage ~= "requerying" then return end

  if driver.getKeyInfo(itemID) then
    issueRequerySearch(itemID) -- retry: the key is cached now, safe to issue the fresh query (throttle permitting)
  else
    finishRequery(row, itemID, nil) -- still uncached after the retry -- give up gracefully
  end
end

-- Browse events fire for ANY browse query, not just this addon's Full Scan -- the sniper
-- window is standalone, so the player can open Blizzard's own Auction House browse tab
-- mid-scan. Guard on scanRunning so a manual browse never gets mistaken for scan progress
-- (and, symmetrically, never hijacks an in-flight scan's status/paging once ours already
-- claimed the running state).
function GC.Sniper.OnBrowseResults()
  if not scanRunning then return end -- not our scan; ignore a manual Blizzard AH browse
  lastBrowseEventAt = time()
  advanceBrowseScan(fullScanToken)
end

function GC.Sniper.OnBrowseResultsAdded()
  if not scanRunning then return end
  lastBrowseEventAt = time()
  advanceBrowseScan(fullScanToken)
end

-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY handler with two independent jobs: (1) send whatever
-- browse step (the initial query, or the next page) startFullScan/advanceBrowseScan
-- deferred because the throttle system was busy; (2) flush the requery flow's deferred
-- searches. In fullscan mode the watchlist scanner isn't running (mode gates which one is
-- live), so flushing deferred requery searches here can't fight the scanner's own
-- throttle-gated send loop; the mode guard keeps watchlist mode entirely unaffected. Scan
-- traffic is serviced first (deterministic order), but the requery flush below always runs
-- regardless of which scan branch fired -- neither queue can starve the other.
function GC.Sniper.OnThrottleReady()
  if pendingFullScanStart then
    pendingFullScanStart = false
    sendBrowseQuery(fullScanToken)
  elseif pendingBrowsePage then
    pendingBrowsePage = false
    sendBrowsePage(fullScanToken)
  end

  if mode ~= "fullscan" then return end
  for itemID in pairs(pendingRequerySend) do
    pendingRequerySend[itemID] = nil
    local row = awaitingRequery[itemID]
    if row and row.purchaseStage == "requerying" then
      driver.sendSearch(itemID)
    end
  end
end

function GC.Sniper.OnItemSearchResults(itemID)
  local row = awaitingRequery[itemID]
  if not row then return end -- not a Task-3 requery for this item (e.g. the watchlist scanner's own search)
  local res = driver.itemResult(itemID)
  local liveDeal = res and GC.DealMath.Evaluate(
    { itemID = itemID, isCommodity = false, auctionID = res.auctionID, unitPrice = res.unitPrice, qty = res.qty },
    driver.getValue(itemID), GC.db.settings.sniper)
  finishRequery(row, itemID, liveDeal)
end

function GC.Sniper.OnCommoditySearchResults(itemID)
  local row = awaitingRequery[itemID]
  if not row then return end -- not a Task-3 requery for this item (e.g. the watchlist scanner's own search)
  local res = driver.commodityResult(itemID)
  local liveDeal = res and GC.DealMath.Evaluate(
    { itemID = itemID, isCommodity = true, unitPrice = res.unitPrice, qty = res.qty },
    driver.getValue(itemID), GC.db.settings.sniper)
  finishRequery(row, itemID, liveDeal)
end

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

  if row.purchaseStage == "buying" or row.purchaseStage == "confirming" or row.purchaseStage == "requerying" then
    return -- purchase (or a Task-3 live-price check) already in flight; button is disabled but guard anyway
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
      -- PlaceBid's bidAmount is the TOTAL price for the auction's whole lot, not a per-unit
      -- price -- deal.unitPrice is per-unit (see driver.itemResult), so multiply back out by
      -- qty here, the same unitPrice * qty = total convention resolvePurchase and
      -- GC.Sniper.OnPurchaseCompleted already use for session accounting and the status line.
      C_AuctionHouse.PlaceBid(deal.auctionID, deal.unitPrice * deal.qty)
      if frame then frame.status:SetText("placing bid...") end
    end
    scheduleBuyTimeout(row, deal)
    return
  end

  -- First click on a `.stale` full-scan deal: the scan snapshot's price/auction may no
  -- longer be real, so requery live instead of arming off it. Task-3: this is the ONLY new
  -- branch in onBuyClick; no C_AuctionHouse purchase call is reachable from it. A deal
  -- reaches here without `.stale` either because it's a watchlist deal (unchanged path,
  -- arms immediately below) or because it's the live deal finishRequery() just swapped onto
  -- this row ("requeried" stage falls through the checks above to here) -- in which case
  -- this click is exactly the normal first arm click, just like any watchlist deal.
  if deal.stale then
    startRequery(row, deal)
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
  for k in pairs(awaitingRequery) do awaitingRequery[k] = nil end
  for k in pairs(awaitingKeyInfo) do awaitingKeyInfo[k] = nil end
  for k in pairs(pendingRequerySend) do pendingRequerySend[k] = nil end
  commodityPurchase = nil
end

-- Column order left to right: icon | name (flex) | tier | discount | price | profit | buy.
-- price/profit/buy are anchored right-to-left off the buy button (profit's RIGHT off buy's
-- LEFT, price's RIGHT off profit's LEFT, discount's RIGHT off price's LEFT, ...) rather than
-- given independent fixed offsets, so the Buy button can never again end up painted over a
-- text column the way it did when profitText's width was chained left-to-right off
-- discountText with no relationship to where the (separately, flush-right-anchored) buy
-- button actually sat. nameText is the one flexible widget, anchored on BOTH sides (icon's
-- RIGHT, tierText's LEFT) so it soaks up whatever space is left over.
createRow = function(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(ROW_WIDTH, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("LEFT")
  row.icon = icon

  local buy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  buy:SetSize(BUY_WIDTH, 18)
  buy:SetPoint("RIGHT")
  buy:SetText("Buy")
  row.buy = buy
  buy:SetScript("OnClick", function()
    onBuyClick(row)
  end)

  local profitText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  profitText:SetPoint("RIGHT", buy, "LEFT", -BUY_GAP, 0)
  profitText:SetWidth(PROFIT_WIDTH)
  profitText:SetJustifyH("RIGHT")
  profitText:SetWordWrap(false)
  profitText:SetMaxLines(1)
  row.profitText = profitText

  local priceText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  priceText:SetPoint("RIGHT", profitText, "LEFT", -COLUMN_GAP, 0)
  priceText:SetWidth(PRICE_WIDTH)
  priceText:SetJustifyH("RIGHT")
  priceText:SetWordWrap(false)
  priceText:SetMaxLines(1)
  row.priceText = priceText

  local discountText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  discountText:SetPoint("RIGHT", priceText, "LEFT", -COLUMN_GAP, 0)
  discountText:SetWidth(DISCOUNT_WIDTH)
  discountText:SetJustifyH("LEFT")
  discountText:SetWordWrap(false)
  discountText:SetMaxLines(1)
  row.discountText = discountText

  local tierText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  tierText:SetPoint("RIGHT", discountText, "LEFT", -COLUMN_GAP, 0)
  tierText:SetWidth(TIER_WIDTH)
  tierText:SetJustifyH("LEFT")
  tierText:SetWordWrap(false)
  tierText:SetMaxLines(1)
  row.tierText = tierText

  local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  nameText:SetPoint("LEFT", icon, "RIGHT", NAME_GAP, 0)
  nameText:SetPoint("RIGHT", tierText, "LEFT", -COLUMN_GAP, 0)
  nameText:SetJustifyH("LEFT")
  -- One line only: a wrapped name would grow taller than ROW_HEIGHT and visually overlap
  -- the row below it. SetWordWrap(false) keeps long names from wrapping; SetMaxLines(1) is
  -- a belt-and-suspenders cap on top of that.
  nameText:SetWordWrap(false)
  nameText:SetMaxLines(1)
  row.nameText = nameText

  row:Hide()
  return row
end

-- Simple single-line tooltip wired to OnEnter/OnLeave; shared by every control below that
-- just needs a plain hover explanation (no title/body split, no dynamic content).
local function setPlainTooltip(widget, text)
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function createFrame()
  local f = CreateFrame("Frame", "GoldCapSniperFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("GoldCap Sniper")

  -- Full Scan is the primary control (rightmost, larger). The watchlist live-scan toggle
  -- is now secondary: shrunk and anchored to Full Scan's left so it reads as the
  -- lesser-emphasis option.
  local fullScanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  fullScanBtn:SetSize(100, 24)
  fullScanBtn:SetPoint("TOPRIGHT", -14, -30)
  fullScanBtn:SetText("Full Scan")
  fullScanBtn:SetScript("OnClick", onFullScanClick)
  setPlainTooltip(fullScanBtn,
    "Scans the entire Auction House via paged browse queries. Takes roughly 15-60 seconds " ..
    "on busy realms. No cooldown -- rescan anytime.")
  f.fullScanBtn = fullScanBtn

  local toggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  toggleBtn:SetSize(56, 18)
  toggleBtn:SetPoint("RIGHT", fullScanBtn, "LEFT", -6, 0)
  toggleBtn:SetText("Live")
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
  setPlainTooltip(toggleBtn,
    "Live scan: continuously re-checks your watchlist for fresh deals. Independent of Full Scan.")
  f.toggleBtn = toggleBtn

  local status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", PANEL_LEFT, -34)
  status:SetPoint("RIGHT", toggleBtn, "LEFT", -8, 0)
  status:SetJustifyH("LEFT")
  status:SetText("Open the Auction House to begin scanning.")
  f.status = status

  -- Column headers: non-scrolling FontStrings parented straight to the frame (never to
  -- `content`), so they stay put while rows scroll underneath and never become per-row
  -- widgets themselves. x-offsets are computed from the same width/gap constants createRow
  -- anchors off of, right-to-left from the buy column, so a header can't silently drift out
  -- of alignment with the column it labels.
  local HEADER_Y = -46
  local buyX = ROW_WIDTH - BUY_WIDTH
  local profitX = buyX - BUY_GAP - PROFIT_WIDTH
  local priceX = profitX - COLUMN_GAP - PRICE_WIDTH
  local discountX = priceX - COLUMN_GAP - DISCOUNT_WIDTH
  local tierX = discountX - COLUMN_GAP - TIER_WIDTH
  local itemWidth = tierX - COLUMN_GAP -- spans the icon+name columns

  local function addHeader(text, x, width, justify, tooltipLines)
    local hit = CreateFrame("Frame", nil, f)
    hit:SetSize(width, 14)
    hit:SetPoint("TOPLEFT", PANEL_LEFT + x, HEADER_Y)

    local label = hit:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT")
    label:SetPoint("BOTTOMRIGHT")
    label:SetJustifyH(justify)
    label:SetText(text)

    if tooltipLines then
      hit:EnableMouse(true)
      hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipLines[1], 1, 0.82, 0)
        for i = 2, #tooltipLines do
          GameTooltip:AddLine(tooltipLines[i], 1, 1, 1, true)
        end
        GameTooltip:Show()
      end)
      hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return hit
  end

  addHeader("Item", 0, itemWidth, "LEFT")
  addHeader("Tier", tierX, TIER_WIDTH, "LEFT", {
    "Tier",
    "HOT = big discount + high profit + proven sales/day",
    "GOOD = solid discount + profit",
    "WATCH = discounted but unproven liquidity or small profit",
    "SUSPECT = discount so extreme it's probably a scam/mispriced-market item",
  })
  addHeader("%", discountX, DISCOUNT_WIDTH, "LEFT", {
    "Discount",
    "Discount vs market value from your GoldCap import",
  })
  addHeader("Price", priceX, PRICE_WIDTH, "RIGHT", {
    "Price",
    "Total cost to buy this auction",
  })
  addHeader("Profit", profitX, PROFIT_WIDTH, "RIGHT", {
    "Profit",
    "Estimated resale profit at 95% of market value, whole stack",
  })

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", PANEL_LEFT, -70)
  scroll:SetPoint("BOTTOMRIGHT", -PANEL_RIGHT_INSET, 12)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    local target = self:GetVerticalScroll() - delta * ROW_HEIGHT * 3
    if target < 0 then target = 0 end
    if target > range then target = range end
    self:SetVerticalScroll(target)
  end)

  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(ROW_WIDTH, ROW_HEIGHT) -- refreshRows() stamps the real height once there are deals to show
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
  -- manual watchlist Live click has one to drive.
  GC.Sniper.scanner = GC.Sniper.scanner or GC.Scanner.New(driver, GC.db.settings.sniper)
  -- autoOpen gates only whether the WINDOW auto-appears. It does NOT auto-start any
  -- scan: Full Scan is the primary mode (one burst on the player's button press), and
  -- the continuous watchlist scan is opt-in via its own Live button -- auto-running it
  -- on every AH visit was the source of the reported AH lag.
  if not GC.db.settings.sniper.autoOpen then return end
  frame = frame or createFrame()
  frame:Show()
  -- Re-show the previous Full Scan's deals if they persisted across the AH close. Buying
  -- re-queries the live price anyway, and a browse scan has no cooldown to wait out, so
  -- there is no reason to force a re-scan every visit -- the player can always press Full
  -- Scan again for fresher data.
  refreshRows()
  if frame.status then
    if mode == "fullscan" and #scanDeals > 0 then
      frame.status:SetText(("%d deals from your last scan -- Full Scan to refresh"):format(#scanDeals))
    else
      frame.status:SetText("Press Full Scan to find deals.")
    end
  end
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
