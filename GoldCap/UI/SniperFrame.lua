local _, GC = ...

GC.Sniper = GC.Sniper or {}

local ROW_HEIGHT = 22
local ROW_CAP = 100 -- hard cap on rendered/pooled deal rows, for both watchlist and full-scan modes

-- Frame/row geometry. ROW_WIDTH is derived from FRAME_WIDTH (not hardcoded separately) so
-- the row pool (createRow) and the scroll child it lives in (createFrame) can never drift
-- apart the way they did before -- that drift is exactly what let the Buy button paint over
-- the profit column. Column widths/gaps below are shared between createRow's per-row
-- anchors and createFrame's header labels for the same reason: one set of numbers feeding
-- both the data rows and the header row that has to line up with them.
local FRAME_WIDTH = 560
local FRAME_HEIGHT = 480
-- E.4: SetResizeBounds' width min/max are both FRAME_WIDTH (see createFrame) -- only height
-- may change, so the column grid above never has to cope with a resized ROW_WIDTH.
local RESIZE_MIN_HEIGHT = 300
local RESIZE_MAX_HEIGHT = 900
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

-- D: Deals/Sell view switcher tab buttons, and the shared scroll-region geometry the Sell
-- container is built to fill (see GC.Sell.Attach below) -- named here, once, so createFrame's
-- own deals `scroll`  and the geometry table handed to GC.Sell.Attach can never drift apart the
-- way the row/header constants above already guard against for the deals grid itself.
local TAB_WIDTH = 50
local TAB_HEIGHT = 18
local TAB_GAP = 4
local SCROLL_TOP = -70
local SCROLL_BOTTOM = 12

-- Two tiers on purpose. A single alarm that fires on a 6% drift is exactly what teaches a
-- player to click through it, so the quiet tier stays where it was and the loud treatment
-- below is reserved for a rise that changes the decision.
local REQUOTE_WARN_RATIO = 0.05
local REQUOTE_LOUD_RATIO = 0.25
-- How long the loud prompt refuses the confirming click. Long enough that a second click
-- already on its way lands on a disabled button, short enough not to feel broken.
local REQUOTE_ARM_SECONDS = 1.5
local REQUOTE_BANNER_HEIGHT = 46
local DIALOG_BASE_HEIGHT = 348
-- How many order-book entries the dialog will read. Purely a bound on work done against
-- already-fetched results; a purchase never spans anywhere near this many price levels.
local MAX_BOOK_LEVELS = 100
-- How far above the live market an imported market value has to sit before the dialog stops
-- treating it as information and says so.
local MV_OUTLIER_RATIO = 3
-- How long a confirmed quote stays clickable in the dialog. Generous on purpose: the player
-- is reading a grid of numbers, and an older quote is safe on both paths -- an item auction
-- is immutable (PlaceBid either buys at exactly the shown price or fails because the lot is
-- gone), and a commodity purchase always re-quotes server-side via StartCommoditiesPurchase
-- before the separate Confirm click (with the >5% requote re-prompt on top).
local ARM_TIMEOUT_SECONDS = 30
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
local dialog           -- the single reusable purchase-confirmation dialog; lazily created (see createDialog)
local deals = {}        -- itemID -> latest watchlist deal shown for it (watchlist mode)
local scanDeals = {}     -- array of deals from the last completed full scan (full-scan mode)
local mode = "watchlist" -- "watchlist" | "fullscan": which backing store sortedDeals() renders
local scanning = false

-- D: top-level Deals/Sell view switcher -- independent of `mode` above (which only picks the
-- watchlist-vs-full-scan backing store WITHIN the Deals view). Default is "deals"; only
-- setView (near createFrame) ever changes it.
local view = "deals"

-- E.2 sortable headers: a click-set override applied on TOP of sortedDeals()'s own order at
-- render time only -- never mutates `deals` or `scanDeals`, so switching modes, rescanning,
-- or a purchase resolving never inherits a stale sort or fights with Evaluate's own order.
-- nil = default (tier rank asc, then profit desc, exactly today's behavior).
local sortOverride = nil        -- { key = "tier"|"pct"|"price"|"profit", desc = true|false }
local sortHeaders = {}          -- sortKey -> { label = FontString, base = string }; filled once by createFrame's addHeader calls

-- B: import staleness. Printed once per UI session (not per AH visit) the first time the
-- import is found stale on AH open -- reset only by /reload, deliberately not tied to a
-- fresh import landing mid-session (see GC.Sniper.OnAuctionHouseShow).
local staleWarnedThisSession = false
local STALE_YELLOW_SECONDS = 6 * 3600
local STALE_RED_SECONDS = 24 * 3600

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

-- Raw comparison value per sortable header (E.2). "Item" has no entry -- it's not sortable,
-- see createFrame's addHeader calls.
local SORT_VALUE = {
  tier = function(deal) return TIER_RANK[deal.tier] or 9 end,
  pct = function(deal) return deal.discount end,
  price = function(deal) return deal.unitPrice * deal.qty end,
  profit = function(deal) return deal.profit end,
}

-- Applies the header-click sort override (if any) on a COPY of `list` -- `list` here is
-- already sortedDeals()'s own freshly-built array (never the live `deals`/`scanDeals`
-- tables themselves), and this function copies it again before table.sort besides, so a
-- sort click can never be observed as having mutated either backing store.
local function applySortOverride(list)
  if not sortOverride then return list end
  local valueOf = SORT_VALUE[sortOverride.key]
  if not valueOf then return list end -- defensive: onHeaderSortClick never sets an unknown key
  local desc = sortOverride.desc
  local copy = {}
  for i, deal in ipairs(list) do copy[i] = deal end
  table.sort(copy, function(a, b)
    local va, vb = valueOf(a), valueOf(b)
    if va == vb then
      -- Same tiebreak as the default view, so ties under any override key never look shuffled.
      local ra, rb = TIER_RANK[a.tier] or 9, TIER_RANK[b.tier] or 9
      if ra ~= rb then return ra < rb end
      return a.profit > b.profit
    end
    if desc then return va > vb end
    return va < vb
  end)
  return copy
end

-- The single entry point refreshRows() renders from: sortedDeals()'s own order, with the
-- header-click override (if any) layered on top.
local function renderList()
  return applySortOverride(sortedDeals())
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

-- E.5 falling marker: deal.falling is set by the (parallel) trend/anti-dump gate once it
-- ships -- absent today, so this renders defensively and is a silent no-op until then. "v"
-- is the ASCII-safe fallback; swap for a real glyph ("↓") once verified in-game that the
-- default UI font renders it.
local function tierLabel(deal)
  if deal.falling then
    return deal.tier .. " |cffff4040v|r"
  end
  return deal.tier
end

local function setRowDeal(row, deal)
  row.deal = deal
  local color = TIER_COLOR[deal.tier] or TIER_COLOR.WATCH
  row.tierText:SetText(tierLabel(deal))
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
  local list = renderList()
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

-- E.2: re-stamps every sortable header's label with a " ▼"/" ▲" suffix on whichever one is
-- active (▼ = descending, ▲ = ascending); every other header falls back to its plain base
-- text. sortHeaders is populated once by createFrame's addHeader calls. Literal UTF-8 glyphs
-- (not \xXX escapes -- WoW's client Lua is 5.1, which has no hex string escape) in a file
-- saved as UTF-8; Lua strings are just byte arrays so this needs no special handling.
local function updateHeaderSortIndicators()
  for key, h in pairs(sortHeaders) do
    if sortOverride and sortOverride.key == key then
      h.label:SetText(h.base .. (sortOverride.desc and " ▼" or " ▲"))
    else
      h.label:SetText(h.base)
    end
  end
end

-- Header OnMouseDown handler (E.2): first click on a column sorts by it descending (biggest
-- raw value first, see SORT_VALUE); a second click on the SAME column flips to ascending.
-- Clicking a different column always starts over at descending. Never touches sortedDeals()'s
-- own backing order -- only renderList()'s copy.
local function onHeaderSortClick(key)
  if sortOverride and sortOverride.key == key then
    sortOverride.desc = not sortOverride.desc
  else
    sortOverride = { key = key, desc = true }
  end
  updateHeaderSortIndicators()
  refreshRows()
end

-- B: import staleness, in seconds since GC.db.imported.ts (nil = never imported this realm).
local function importAgeSeconds()
  local ts = GC.db and GC.db.imported and GC.db.imported.ts
  if not ts then return nil end
  local age = time() - ts
  return age < 0 and 0 or age -- a clock skew or bad ts must never show a negative age
end

-- Refreshes the staleness FontString from the CURRENT import age. Called on AH show and
-- after every full scan completes (deals are the moment the player is about to act on
-- prices, so that's when staleness should be freshest), not on a timer -- the age only
-- matters at those decision points.
local function refreshStaleText()
  if not frame or not frame.staleText then return end
  local age = importAgeSeconds()
  -- Companion sync (Task A): db.imported.origin == "app" means Core/Data.lua's
  -- AdoptAppData loaded this data from GoldCap_AppData rather than a manual paste --
  -- thresholds/colors below are unchanged, only the label differs.
  local isAppData = GC.db and GC.db.imported and GC.db.imported.origin == "app"
  if not age then
    frame.staleText:SetText("no import -- /goldcap import")
    frame.staleText:SetTextColor(1, 0.3, 0.3)
    frame.staleText:Show()
  elseif age < STALE_YELLOW_SECONDS then
    frame.staleText:Hide()
  elseif age < STALE_RED_SECONDS then
    local label = isAppData and "auto-synced %dh ago" or "import %dh old"
    frame.staleText:SetText(label:format(math.floor(age / 3600)))
    frame.staleText:SetTextColor(1, 0.82, 0)
    frame.staleText:Show()
  else
    frame.staleText:SetText(isAppData and "auto-synced data stale -- /goldcap import" or "import stale -- /goldcap import")
    frame.staleText:SetTextColor(1, 0.3, 0.3)
    frame.staleText:Show()
  end
end

-- One chat print per UI session (not per AH visit -- staleWarnedThisSession only resets on
-- /reload) the first time the import is found stale on AH open.
local function maybeWarnStale()
  if staleWarnedThisSession then return end
  local age = importAgeSeconds()
  if age and age < STALE_RED_SECONDS then return end -- fresh or yellow: no warning yet
  staleWarnedThisSession = true
  if age then
    GC.Print(("your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."):format(math.floor(age / 3600)))
  else
    GC.Print("you haven't imported realm prices yet -- prices may be off. Paste a string from goldcap.gg (/goldcap import).")
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

  -- Reads ALREADY-FETCHED search results only -- never issues a query, so this cannot
  -- compete with a Full Scan or the Sell tab's quote walker on the throttled message
  -- system. Capped because a deep commodity book can run to thousands of levels and the
  -- dialog only ever needs enough to cover one purchase plus the next surviving ask.
  commodityBook = function(itemID)
    local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    if not n or n <= 0 then return nil end
    if n > MAX_BOOK_LEVELS then n = MAX_BOOK_LEVELS end
    local levels = {}
    for i = 1, n do
      local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
      if info and info.unitPrice then
        levels[#levels + 1] = { unitPrice = info.unitPrice, quantity = info.quantity or 0 }
      end
    end
    if #levels == 0 then return nil end
    return levels
  end,

  -- Items are one lot per purchase, so there is nothing to walk: the only thing worth
  -- knowing is the cheapest OTHER lot, which is what a reseller has to undercut.
  -- buyoutAmount is the lot TOTAL (see itemResult above), so divide down per unit.
  itemCompetingUnit = function(itemID, excludeAuctionID)
    local key = C_AuctionHouse.MakeItemKey(itemID)
    local n = C_AuctionHouse.GetNumItemSearchResults(key)
    if not n or n <= 0 then return nil end
    if n > MAX_BOOK_LEVELS then n = MAX_BOOK_LEVELS end
    local best
    for i = 1, n do
      local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
      if info and info.auctionID ~= excludeAuctionID
          and info.buyoutAmount and info.buyoutAmount > 0
          and info.quantity and info.quantity > 0 then
        local unit = math.floor(info.buyoutAmount / info.quantity)
        if not best or unit < best then best = unit end
      end
    end
    return best
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

-- D: keeps the Sell tab's "Sell (N)" badge current. Called after a purchase (a new flip may
-- now exist), on every AH open (bag counts may have changed since a mailbox visit), and by
-- SellFrame.lua itself after Post/Remove/a bag-count refresh -- one shared place instead of
-- every call site re-deriving the label text. Safe to call before the frame/tab exist yet.
local function updateSellTabLabel()
  if not frame or not frame.sellTab then return end
  local n = GC.Sell.SellableCount and GC.Sell.SellableCount() or 0
  frame.sellTab:SetText(n > 0 and ("Sell (%d)"):format(n) or "Sell")
end
GC.Sniper.UpdateSellTabLabel = updateSellTabLabel

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
  refreshStaleText() -- B: refresh on every completed scan, not just AH open
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
-- Purchase flow. Clicking a row's Buy button never buys anything itself -- it opens the
-- single reusable confirmation dialog (createDialog/openDialog below), which shows the
-- profit math and takes every further click in the sequence on ITS OWN primary button. The
-- row's Buy button text never changes; only the dialog's does. Blizzard's API still forces
-- the same click counts as a plain row-button flow would, just relocated onto the dialog:
--   items:       Buy (opens dialog; kicks a live requery first if the deal is `.stale`) ->
--                dialog Buy (PlaceBid).
--   commodities: Buy (opens dialog) -> dialog Buy (StartCommoditiesPurchase) -> waits for
--                COMMODITY_PRICE_UPDATED -> dialog Confirm (ConfirmCommoditiesPurchase).
-- Stage machine (row.purchaseStage): nil (idle) -> "requerying" (stale-deal live requote in
-- flight, no purchase call yet) -> "ready" (dialog open, primary enabled, still no purchase
-- call) -> "buying" (PlaceBid or StartCommoditiesPurchase issued) -> for commodities only,
-- "confirm"/"requote" (quote landed, awaiting the explicit Confirm click) -> "confirming"
-- (ConfirmCommoditiesPurchase issued) -> nil once resolved.
-- Every C_AuctionHouse purchase call (PlaceBid / StartCommoditiesPurchase /
-- ConfirmCommoditiesPurchase) is reached ONLY from onDialogPrimaryClick, the dialog's own
-- primary button's OnClick closure — never from an event or a timer. Event handlers and
-- timeouts only ever update dialog text or enable/disable its buttons; only ONE commodity
-- purchase may be in flight at a time.
-- ---------------------------------------------------------------------------

-- Every stage that touches the primary button goes through here, so its colour can never be
-- left red from a previous requote. Gold is UIPanelButtonTemplate's own text colour.
local function setPrimaryLabel(text, r, g, b)
  dialog.primaryBtn:SetText(text)
  local fs = dialog.primaryBtn:GetFontString()
  if fs then fs:SetTextColor(r or 1, g or 0.82, b or 0) end
end

local function hideRequoteBanner()
  if not dialog then return end
  dialog.banner:Hide()
  dialog:SetHeight(DIALOG_BASE_HEIGHT)
end

local function showRequoteBanner(head, detail)
  dialog.banner.head:SetText(head)
  dialog.banner.detail:SetText(detail)
  dialog:SetHeight(DIALOG_BASE_HEIGHT + REQUOTE_BANNER_HEIGHT)
  dialog.banner:Show()
end

-- Refuses the confirming click for REQUOTE_ARM_SECONDS, counting down in the label so the
-- disabled button reads as deliberate rather than broken. The token invalidates a countdown
-- still in flight when the dialog moves on to a different row or stage.
--
-- Invariant: a pending countdown must never repaint a button some other path has taken
-- ownership of. armLoudConfirm bumps the token when it starts one; every OTHER path that also
-- sets the primary button's label/enabled state on the row the countdown was armed for --
-- whether or not that path itself arms a new countdown -- bumps it too, so a tick from an
-- older arming can never win a race against whoever owns the button now.
local requoteArmToken = 0
local function armLoudConfirm(row)
  requoteArmToken = requoteArmToken + 1
  local token = requoteArmToken
  local ticks = math.ceil(REQUOTE_ARM_SECONDS / 0.5)

  dialog.primaryBtn:Disable()

  local function tick(left)
    if token ~= requoteArmToken then return end
    if not dialog or dialog.row ~= row or row.purchaseStage ~= "requote" then return end
    if left <= 0 then
      setPrimaryLabel("Buy anyway", 1, 0.35, 0.35)
      dialog.primaryBtn:Enable()
      return
    end
    setPrimaryLabel(("Buy anyway (%d)"):format(left), 1, 0.35, 0.35)
    C_Timer.After(0.5, function() tick(left - 1) end)
  end

  tick(ticks)
end

-- Sets the dialog's status line text and color in one call; color defaults to plain white so
-- callers only pass r/g/b for an accent (green/red) message.
local function setDialogStatus(text, r, g, b)
  if not dialog then return end
  dialog.status:SetText(text or "")
  dialog.status:SetTextColor(r or 1, g or 1, b or 1)
end

-- Item icon + quality-colored name + qty suffix + tier badge, mirroring setRowDeal's async
-- load pattern but targeting the dialog's own widgets. dialog.deal (not row.deal) is the
-- identity guard here since the dialog can outlive the row being reassigned.
local function setDialogHeader(deal)
  local color = TIER_COLOR[deal.tier] or TIER_COLOR.WATCH
  dialog.tierText:SetText(deal.tier)
  dialog.tierText:SetTextColor(color[1], color[2], color[3])
  if deal.tier == "SUSPECT" then dialog.suspectNote:Show() else dialog.suspectNote:Hide() end
  dialog.nameText:SetText(("item %d"):format(deal.itemID) .. qtySuffix(deal))
  dialog.icon:SetTexture(nil)

  local item = Item:CreateFromItemID(deal.itemID)
  item:ContinueOnItemLoad(function()
    if dialog.deal ~= deal then return end -- dialog moved on before the async load finished
    dialog.icon:SetTexture(item:GetItemIcon())
    local quality = item:GetItemQuality()
    local qc = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
    local label = item:GetItemName() or ("item " .. deal.itemID)
    dialog.nameText:SetText((qc and qc:WrapTextInColorCode(label) or label) .. qtySuffix(deal))
  end)
end

-- Snapshots what the live order book says about `deal`, onto the dialog, so every later
-- re-stamp (a fresh requery, a commodity requote) projects against the same live evidence
-- instead of against the import alone. nil whenever the book has nothing usable to say.
local function refreshDialogBook(deal)
  if not dialog then return end
  if deal.isCommodity then
    local levels = driver.commodityBook(deal.itemID)
    dialog.book = levels and GC.Book.Fill(levels, deal.qty) or nil
  else
    local competing = driver.itemCompetingUnit(deal.itemID, deal.auctionID)
    dialog.book = competing and { competing = competing } or nil
  end
end

-- Re-stamps every number in the dialog's grid from a (possibly just-updated) unitPrice/
-- totalCost pair -- deal.mv/qty never change within one purchase flow, only the live price
-- does (a fresh requery, or a commodity requote), so this is the one place that formula
-- lives instead of duplicating it at every call site.
local function updateDialogAmounts(deal, unitPrice, totalCost)
  local qty = deal.qty
  local mv = deal.mv
  local discount = 1 - (unitPrice / mv)
  local competing = dialog.book and dialog.book.competing
  -- The projection can only be as good as its ceiling: you cannot sell above what is
  -- already listed, so an mv the book contradicts is clamped away here rather than
  -- multiplied out by qty into a five-figure fiction.
  local sellUnit, clamped, ratio = GC.DealMath.SellUnit(mv, competing)
  local resale = math.floor(sellUnit * 0.95) * qty
  local profit = resale - totalCost

  dialog.unitPriceText:SetText(formatColumnAmount(unitPrice))
  dialog.totalCostText:SetText(formatColumnAmount(totalCost))
  dialog.mvText:SetText(formatColumnAmount(mv))
  dialog.discountText:SetText(("%d%%"):format(math.floor(discount * 100 + 0.5)))
  dialog.resaleText:SetText(formatColumnAmount(resale))

  if competing then
    dialog.askLabel:Show()
    dialog.askText:Show()
    dialog.askText:SetText(formatColumnAmount(competing))
  else
    dialog.askLabel:Hide()
    dialog.askText:Hide()
  end

  if clamped and ratio and ratio >= MV_OUTLIER_RATIO then
    dialog.mvNote:SetText(("Market value %s is %.1fx the live market -- projection ignores it")
      :format(formatColumnAmount(mv), ratio))
    dialog.mvNote:Show()
  else
    dialog.mvNote:Hide()
  end

  local sign = profit < 0 and "-" or ""
  dialog.profitText:SetText(sign .. formatColumnAmount(math.abs(profit)))
  if profit >= 0 then
    dialog.profitText:SetTextColor(0.25, 0.85, 0.25)
  else
    dialog.profitText:SetTextColor(1, 0.3, 0.3)
  end

  local value = driver.getValue(deal.itemID)
  if value and value.sold then
    dialog.soldLabel:Show()
    dialog.soldText:Show()
    dialog.soldText:SetText(("%.1f"):format(value.sold))
  else
    dialog.soldLabel:Hide()
    dialog.soldText:Hide()
  end

  -- C/E.5 24h trend: only import-sourced values carry trend (and only when the export saw
  -- a >=5% move), so this line hides itself for everything else -- same Show/Hide pattern
  -- as Sold/day above.
  if value and value.trend then
    dialog.trendLabel:Show()
    dialog.trendText:Show()
    dialog.trendText:SetText(("%+d%%"):format(value.trend))
    if value.trend < 0 then
      dialog.trendText:SetTextColor(1, 0.3, 0.3)
    else
      dialog.trendText:SetTextColor(0.25, 0.85, 0.25)
    end
  else
    dialog.trendLabel:Hide()
    dialog.trendText:Hide()
  end
end

-- The one place the dialog's numbers get stamped from live evidence. A commodity's real cost
-- is the whole fill, not the cheapest level the deal was quoted from -- showing it here means
-- the player sees it before the Buy click instead of as a surprise after it. Items keep their
-- own exact lot price (see refreshDialogBook), and an unusable book falls back to the deal's
-- own snapshot, which is what this dialog has always shown.
local function stampDialogFromBook(deal)
  refreshDialogBook(deal)
  local book = dialog.book
  if deal.isCommodity and book and not book.exhausted then
    updateDialogAmounts(deal, book.unit, book.total)
  else
    updateDialogAmounts(deal, deal.unitPrice, deal.unitPrice * deal.qty)
  end
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
      -- D: every successful purchase becomes a flip candidate for the Sell view (Sniper v2
      -- §D) -- one line, no other change to this flow.
      GC.Data.RecordFlip(deal)
      -- The ledger's buy side. RecordFlip above is a resale to-do list that self-prunes once
      -- posted or aged out; this is the permanent record that makes "earned through GoldCap"
      -- computable later, and it snapshots the market value the deal was judged against.
      GC.Ledger.RecordSniperBuy(deal, GC.Ledger.Context())
      updateSellTabLabel()
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
  if dialog and dialog.row == row then
    dialog.row = nil
    dialog:Hide()
  end
  if frame and note then frame.status:SetText(note) end
  refreshRows()
end

-- Cancel button / Esc / a Buy click on a different row all fund into this: reset every bit of
-- bookkeeping for `row`'s purchase without crediting the session. A plain
-- resolvePurchase(row, false, ...) alone would leave a "requerying" row's
-- awaitingRequery/awaitingKeyInfo/pendingRequerySend entry dangling (keyed by itemID) --
-- exactly the kind of leftover that let a late search-results event resolve against this row
-- again after it's been reused for an unrelated deal.
local function abortRowPurchase(row, note)
  local deal = row.purchaseDeal or row.deal
  if deal then
    awaitingRequery[deal.itemID] = nil
    awaitingKeyInfo[deal.itemID] = nil
    pendingRequerySend[deal.itemID] = nil
  end
  resolvePurchase(row, false, note)
end

-- Expires a quote nobody clicked within ARM_TIMEOUT_SECONDS -- but never dead-ends the
-- player: the primary button flips to "Refresh" (stage "expired"), whose click re-runs the
-- live requery for fresh numbers. Refresh is NOT a purchase call, so looping through
-- expired -> Refresh -> ready any number of times stays compliant.
local function scheduleArmTimeout(row, deal)
  C_Timer.After(ARM_TIMEOUT_SECONDS, function()
    if row.purchaseStage == "ready" and row.deal == deal and dialog and dialog.row == row then
      row.purchaseStage = "expired"
      dialog.primaryBtn:Enable()
      dialog.primaryBtn:SetText("Refresh")
      setDialogStatus("quote expired -- Refresh to re-check the price", 1, 0.82, 0)
    end
  end)
end

-- Puts the dialog into the pre-purchase-call "ready" state: numbers reflect the best price
-- known so far (a watchlist snapshot, or the live quote finishRequery just landed), primary
-- button reads "Buy" and is enabled, and the ARM_TIMEOUT clock starts. Shared by openDialog
-- (non-stale deals arm immediately) and finishRequery (stale deals arm once the live requery
-- resolves) so there is exactly one place that flips this stage on.
local function armReady(row, deal)
  row.purchaseStage = "ready"
  row.purchaseDeal = nil
  activeItemID[deal.itemID] = true
  dialog.primaryBtn:Enable()
  hideRequoteBanner()
  setPrimaryLabel("Buy")
  stampDialogFromBook(deal)
  -- The dialog's OWN status must flip here -- the requery path otherwise leaves its
  -- "checking live price..." text up even though the button just enabled, and the player
  -- reads the stale text right up until the quote expires.
  setDialogStatus("price confirmed -- click Buy to purchase", 0.25, 0.85, 0.25)
  scheduleArmTimeout(row, deal)
end

-- Same BUY_TIMEOUT window as before (covers both PlaceBid and StartCommoditiesPurchase
-- waiting on their respective completion/quote events), but freezes the dialog with an
-- explanatory status instead of auto-resolving the purchase as failed: PlaceBid's completion
-- event is UNVERIFIED to always fire, so silently unpinning here could let the player
-- re-attempt a buy whose bid may in fact still land. The row stays pinned until Cancel.
local function scheduleBuyTimeout(row, deal)
  C_Timer.After(BUY_TIMEOUT_SECONDS, function()
    if row.purchaseStage == "buying" and row.purchaseDeal == deal
        and dialog and dialog.row == row then
      dialog.primaryBtn:Disable()
      setDialogStatus("no purchase confirmation received -- Cancel and retry")
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Task-3 buy-after-scan requery: the FIRST Buy click on a `.stale` (full-scan) deal never
-- arms straight off the scan snapshot. openDialog pins the row ("requerying") and disables
-- the dialog's primary button, issues a fresh driver.sendSearch(itemID) (guarding the item
-- key not being cached yet -- see GC.Sniper.OnItemKeyInfo below), and waits for the matching
-- search-results event. finishRequery() then either hands the row a real, non-stale live
-- deal and calls armReady (dialog numbers refresh from the live quote, primary button
-- enables as "Buy" -- the very NEXT click is the real purchase call, exactly like a
-- watchlist deal) or gives up gracefully ("gone / price changed", dialog closed, row
-- unpinned). No C_AuctionHouse purchase call is ever reached from this path -- only
-- PlaceBid/StartCommoditiesPurchase/ConfirmCommoditiesPurchase inside onDialogPrimaryClick
-- complete a purchase, unchanged.
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
  if row.purchaseStage ~= "requerying" then return end -- stale/late event: reset already ran (AH closed, timed out, canceled, ...)

  if liveDeal then
    setRowDeal(row, liveDeal) -- swaps the row onto the fresh, non-stale deal (real auctionID/unitPrice/qty/isCommodity)
    if dialog and dialog.row == row then
      dialog.deal = liveDeal
      setDialogHeader(liveDeal) -- tier/qty can shift between the scan snapshot and the live quote; refresh both
    end
    armReady(row, liveDeal) -- still pinned; NOT a purchase call -- the next dialog click is the first one
    if frame then frame.status:SetText("live price confirmed -- click Buy to purchase") end
  else
    activeItemID[itemID] = nil
    row.purchaseStage = nil
    if dialog and dialog.row == row then
      dialog.row = nil
      dialog:Hide()
    end
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

-- D: true while a Full Scan is paging (or queued to start) or any row has a purchase pinned
-- (armed/requerying/buying/confirming) -- GC.Sell's own quote walker (SellFrame.lua) checks
-- this before every send and simply refuses/waits while it's true, so the Sell tab's traffic
-- can never compete with, or queue ahead of, a scan or a buy requery on the shared throttled
-- message system.
function GC.Sniper.IsBusy()
  if scanRunning or pendingFullScanStart or pendingBrowsePage then return true end
  return next(activeItemID) ~= nil
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

function GC.Sniper.OnCommodityPriceUpdated(unitPrice, totalPrice)
  local row = commodityPurchase
  if not row then return end
  if row.purchaseStage == "confirming" then return end -- third-click confirm already in flight; don't re-enable the button
  local deal = row.purchaseDeal
  if not deal then return end

  -- COMPLIANCE: a commodity purchase's final ConfirmCommoditiesPurchase() must ALWAYS come
  -- from a human click (matching native WoW's always-present commodity confirm dialog), so
  -- BOTH branches only set a confirm STAGE and refresh the dialog here; the actual confirm
  -- call happens later in onDialogPrimaryClick. This handler never completes a purchase.
  if dialog and dialog.row == row then
    updateDialogAmounts(deal, unitPrice, totalPrice)
  end

  local quotedTotal = deal.unitPrice * deal.qty
  local severity, ratio = GC.DealMath.RequoteSeverity(
    quotedTotal, totalPrice, REQUOTE_WARN_RATIO, REQUOTE_LOUD_RATIO)

  if severity == "none" then
    row.purchaseStage = "confirm"
    if dialog and dialog.row == row then
      requoteArmToken = requoteArmToken + 1 -- taking the button back from any pending countdown
      hideRequoteBanner()
      setPrimaryLabel("Confirm")
      dialog.primaryBtn:Enable()
    end
    setDialogStatus(("quote %s -- click Confirm to buy"):format(GetCoinTextureString(totalPrice)))
    if frame then
      frame.status:SetText(("quote %s -- click Confirm to buy"):format(GetCoinTextureString(totalPrice)))
    end
    return
  end

  -- The number the player needed and never got: the per-unit comparison. A total alone
  -- ("price rose to 14,630g") is unanchored -- it was the whole content of this prompt on
  -- 2026-08-10, on a button that said Confirm in both branches, in the same place.
  row.purchaseStage = "requote"
  local detail = ("%s -> %s per unit    total %s -> %s"):format(
    GetCoinTextureString(deal.unitPrice), GetCoinTextureString(unitPrice),
    formatColumnAmount(quotedTotal), formatColumnAmount(totalPrice))

  -- Same `dialog.row == row` guard the original branch carried: a late COMMODITY_PRICE_UPDATED
  -- for a row the dialog has already moved off must never re-arm somebody else's buttons.
  if dialog and dialog.row == row then
    if severity == "loud" then
      showRequoteBanner(("PRICE ROSE %.1fx"):format(ratio), detail)
      armLoudConfirm(row)
    else
      requoteArmToken = requoteArmToken + 1 -- taking the button back from any pending countdown
      hideRequoteBanner()
      setPrimaryLabel("Buy anyway", 1, 0.35, 0.35)
      dialog.primaryBtn:Enable()
    end
  end

  if severity == "loud" and GC.db and GC.db.settings and GC.db.settings.sniper.sound then
    PlaySound(SOUNDKIT.RAID_WARNING)
  end

  setDialogStatus(detail, 1, 0.3, 0.3)
  if frame then
    frame.status:SetText(("price rose %.1fx -- %s"):format(ratio, GetCoinTextureString(totalPrice)))
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

-- The dialog's own primary button OnClick -- the ONLY place PlaceBid, StartCommoditiesPurchase
-- and ConfirmCommoditiesPurchase are ever called. A hardware click on this button is exactly
-- as synchronous/direct as the old row-button click was; only WHICH widget owns the click
-- moved.
local function onDialogPrimaryClick()
  local row = dialog.row
  if not row then return end
  local stage = row.purchaseStage

  if stage == "confirm" or stage == "requote" then
    -- Third overall click for a commodity deal (dialog-open + Start + this Confirm): the
    -- ONLY path that finalizes a commodity purchase, for both the within-tolerance
    -- ("confirm") and raised-price ("requote") prompts. Retail 12.0.7 requires
    -- (itemID, quantity) matching the StartCommoditiesPurchase call; use the frozen
    -- purchaseDeal, not row.deal (a rescan may have replaced row.deal).
    local pd = row.purchaseDeal
    C_AuctionHouse.ConfirmCommoditiesPurchase(pd.itemID, pd.qty)
    row.purchaseStage = "confirming"
    dialog.primaryBtn:Disable()
    setDialogStatus("confirming purchase...")
    if frame then frame.status:SetText("confirming purchase...") end
    return
  end

  if stage == "expired" then
    -- Refresh: NOT a purchase call -- re-runs the same live requery the dialog opened with,
    -- so a player who read the numbers past the quote window is never dead-ended into
    -- Cancel. finishRequery re-arms "ready" with fresh numbers (or closes on gone/changed).
    dialog.primaryBtn:Disable()
    setPrimaryLabel("Buy")
    setDialogStatus("checking live price...")
    startRequery(row, row.deal)
    return
  end

  if stage ~= "ready" then
    return -- every other stage's primary button is disabled; guard anyway against a stray click
  end

  -- Second overall click (first for a plain watchlist deal): fire the real purchase call
  -- synchronously, right here in OnClick.
  local deal = row.deal
  if deal.isCommodity and commodityPurchase and commodityPurchase ~= row then
    -- Only ONE commodity purchase may be in flight at a time. Unreachable in practice --
    -- opening a second dialog already refuses/replaces per the guard in onBuyClick -- kept as
    -- a last-resort guard against orphaning the pending one.
    setDialogStatus("finish the pending buy first", 1, 0.3, 0.3)
    driver.onStatus("finish the pending buy first")
    return
  end

  row.purchaseStage = "buying"
  row.purchaseDeal = deal
  dialog.primaryBtn:Disable()
  if deal.isCommodity then
    commodityPurchase = row
    C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, deal.qty)
    setDialogStatus("buying commodity...")
    if frame then frame.status:SetText("buying commodity...") end
  else
    pendingAuction[deal.auctionID] = row
    -- PlaceBid's bidAmount is the TOTAL price for the auction's whole lot, not a per-unit
    -- price -- deal.unitPrice is per-unit (see driver.itemResult), so multiply back out by
    -- qty here, the same unitPrice * qty = total convention resolvePurchase and
    -- GC.Sniper.OnPurchaseCompleted already use for session accounting and the status line.
    C_AuctionHouse.PlaceBid(deal.auctionID, deal.unitPrice * deal.qty)
    setDialogStatus("placing bid...")
    if frame then frame.status:SetText("placing bid...") end
  end
  scheduleBuyTimeout(row, deal)
end

-- Builds the single reusable confirmation dialog (see createDialog/openDialog usage below).
-- Created lazily on the first Buy click of a session, same pattern as GoldCapImportDialog --
-- never built eagerly alongside the sniper frame itself.
local function createDialog()
  local d = CreateFrame("Frame", "GoldCapSniperConfirm", UIParent, "BasicFrameTemplateWithInset")
  -- Height is driven by the two wrapped text blocks below the grid (suspectNote, mvNote),
  -- not by the grid's row count: both routinely wrap to two lines at this width, so the
  -- budget below the grid has to fit two two-line blocks plus the status line -- shrinking
  -- this back toward "one row taller" will clip them on exactly the deals they warn about.
  d:SetSize(300, DIALOG_BASE_HEIGHT)
  d:SetFrameStrata("DIALOG") -- must float above the sniper list frame it's anchored to
  d:SetPoint("CENTER", frame, "CENTER")
  d:EnableMouse(true)
  d.TitleText:SetText("Confirm Purchase")

  local icon = d:CreateTexture(nil, "ARTWORK")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 16, -30)
  d.icon = icon

  local tierText = d:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  tierText:SetPoint("TOPRIGHT", -16, -32)
  tierText:SetJustifyH("RIGHT")
  d.tierText = tierText

  local nameText = d:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  nameText:SetPoint("RIGHT", tierText, "LEFT", -6, 0)
  nameText:SetJustifyH("LEFT")
  nameText:SetWordWrap(false)
  d.nameText = nameText

  -- A: hover tooltip over the icon+name header, same as a row (see createRow) -- Texture and
  -- FontString objects can't take mouse scripts themselves, so this is an invisible Frame
  -- spanning both, same pattern as createFrame's header "hit" frames.
  local itemHit = CreateFrame("Frame", nil, d)
  itemHit:SetPoint("TOPLEFT", icon, "TOPLEFT")
  itemHit:SetPoint("BOTTOMRIGHT", nameText, "BOTTOMRIGHT")
  itemHit:EnableMouse(true)
  itemHit:SetScript("OnEnter", function(self)
    if not dialog.deal then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(dialog.deal.itemID)
    GameTooltip:Show()
  end)
  itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  d.itemHit = itemHit

  -- A four-letter yellow tier badge lost to a green five-figure profit on 2026-08-10.
  -- Said in words, right under the name, it competes on the same terms.
  local suspectNote = d:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  suspectNote:SetPoint("TOPLEFT", 16, -50)
  suspectNote:SetPoint("RIGHT", -16, 0)
  suspectNote:SetJustifyH("LEFT")
  suspectNote:SetWordWrap(true)
  suspectNote:SetTextColor(1, 0.85, 0.1)
  suspectNote:SetText("a discount this extreme usually means the market value is wrong, not that this is a bargain")
  suspectNote:Hide()
  d.suspectNote = suspectNote

  -- Label/value grid: one row per number the player needs to decide with. updateDialogAmounts
  -- re-stamps the value slots in place as fresher quotes come in -- the grid itself never
  -- grows or reflows.
  local GRID_TOP = -88
  local GRID_ROW = 16

  local function gridRow(index, label)
    local y = GRID_TOP - (index - 1) * GRID_ROW
    local labelFS = d:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    labelFS:SetPoint("TOPLEFT", 16, y)
    labelFS:SetJustifyH("LEFT")
    labelFS:SetText(label)

    local valueFS = d:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valueFS:SetPoint("TOPRIGHT", -16, y)
    valueFS:SetJustifyH("RIGHT")
    return labelFS, valueFS
  end

  local _, unitPriceText = gridRow(1, "Unit price (avg fill)")
  local _, totalCostText = gridRow(2, "Total cost")
  local _, mvText = gridRow(3, "Market value")
  local askLabel, askText = gridRow(4, "Lowest ask after buy")
  local _, discountText = gridRow(5, "Discount")
  local _, resaleText = gridRow(6, "Est. resale (after 5% AH cut)")
  local _, profitText = gridRow(7, "Est. profit")
  local soldLabel, soldText = gridRow(8, "Sold/day")
  local trendLabel, trendText = gridRow(9, "24h trend")
  d.unitPriceText, d.totalCostText, d.mvText = unitPriceText, totalCostText, mvText
  d.discountText, d.resaleText, d.profitText = discountText, resaleText, profitText
  d.askLabel, d.askText = askLabel, askText
  d.soldLabel, d.soldText = soldLabel, soldText
  d.trendLabel, d.trendText = trendLabel, trendText

  -- Sits between the grid and the status line; shown only when the clamp above actually bit.
  local mvNote = d:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  mvNote:SetPoint("TOPLEFT", 16, GRID_TOP - 9 * GRID_ROW - 6)
  mvNote:SetPoint("RIGHT", -16, 0)
  mvNote:SetJustifyH("LEFT")
  mvNote:SetWordWrap(true)
  mvNote:SetTextColor(1, 0.3, 0.3)
  mvNote:Hide()
  d.mvNote = mvNote

  local status = d:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", 16, GRID_TOP - 9 * GRID_ROW - 40)
  status:SetPoint("RIGHT", -16, 0)
  status:SetJustifyH("LEFT")
  status:SetWordWrap(true)
  d.status = status

  -- Anchored off the BOTTOM, just above the buttons, and hidden by default. Showing it grows
  -- the dialog by exactly its own height, so the window visibly changes shape rather than
  -- re-rendering a line of status text inside an unchanged outline -- which is what a player
  -- running on muscle memory does not notice.
  local banner = CreateFrame("Frame", nil, d)
  banner:SetPoint("BOTTOMLEFT", 12, 44)
  banner:SetPoint("BOTTOMRIGHT", -12, 44)
  banner:SetHeight(REQUOTE_BANNER_HEIGHT)

  local bannerBg = banner:CreateTexture(nil, "BACKGROUND")
  bannerBg:SetAllPoints()
  bannerBg:SetColorTexture(0.45, 0.04, 0.04, 0.9)

  local bannerHead = banner:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  bannerHead:SetPoint("TOPLEFT", 8, -6)
  bannerHead:SetJustifyH("LEFT")
  bannerHead:SetTextColor(1, 0.45, 0.45)
  banner.head = bannerHead

  local bannerDetail = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  bannerDetail:SetPoint("TOPLEFT", bannerHead, "BOTTOMLEFT", 0, -4)
  bannerDetail:SetPoint("RIGHT", banner, "RIGHT", -8, 0)
  bannerDetail:SetJustifyH("LEFT")
  bannerDetail:SetWordWrap(true)
  banner.detail = bannerDetail

  banner:Hide()
  d.banner = banner

  local cancelBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  cancelBtn:SetSize(90, 22)
  cancelBtn:SetPoint("BOTTOMLEFT", 16, 14)
  cancelBtn:SetText("Cancel")
  cancelBtn:SetScript("OnClick", function()
    -- COMPLIANCE: CancelCommoditiesPurchase is safe to call from anywhere (unlike
    -- Start/Confirm/PlaceBid), but a new call site only ever gets added here -- a real
    -- hardware click -- and only when a commodity purchase session is actually open
    -- server-side (Start has been called, Confirm has not).
    local row = dialog.row
    if row then
      local stage = row.purchaseStage
      if (stage == "buying" or stage == "confirm" or stage == "requote")
          and row.purchaseDeal and row.purchaseDeal.isCommodity then
        C_AuctionHouse.CancelCommoditiesPurchase()
      end
    end
    dialog:Hide() -- OnHide below does the actual local-state reset
  end)
  d.cancelBtn = cancelBtn

  local primaryBtn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  primaryBtn:SetSize(90, 22)
  primaryBtn:SetPoint("BOTTOMRIGHT", -16, 14)
  primaryBtn:SetText("Buy")
  primaryBtn:SetScript("OnClick", onDialogPrimaryClick)
  d.primaryBtn = primaryBtn

  -- Esc (via UISpecialFrames) just calls Hide() -- same abort as a hardware Cancel click,
  -- minus the CancelCommoditiesPurchase call above, which is deliberately scoped to the
  -- Cancel button's own OnClick only (Esc's frame-hide isn't guaranteed to run in that same
  -- synchronous hardware-click context). A late COMMODITY_PRICE_UPDATED/purchase-result event
  -- for a since-aborted row is still handled safely -- those handlers key off
  -- commodityPurchase/pendingAuction, which the reset below already clears.
  d:SetScript("OnHide", function()
    dialog.book = nil
    local row = dialog.row
    if not row then return end -- normal close: resolvePurchase already cleared this before hiding
    dialog.row = nil
    abortRowPurchase(row, "purchase canceled")
  end)

  table.insert(UISpecialFrames, "GoldCapSniperConfirm") -- Escape closes the dialog = cancel

  return d
end

-- Opens the dialog for `row`/`deal`: this is the row Buy button's entire OnClick job now, for
-- BOTH item and commodity deals, stale or not. Numbers are populated from the snapshot deal
-- immediately; a `.stale` full-scan deal then kicks the existing Task-3 requery machinery
-- (dialog stays open, primary disabled) instead of arming right away.
local function openDialog(row, deal)
  dialog = dialog or createDialog()
  dialog.row = row
  hideRequoteBanner()
  dialog.deal = deal
  setDialogHeader(deal)
  stampDialogFromBook(deal)
  dialog:Show()

  if deal.stale then
    dialog.primaryBtn:Disable()
    setPrimaryLabel("Buy")
    setDialogStatus("checking live price...")
    startRequery(row, deal) -- pins the row ("requerying"); finishRequery flips us to "ready"
  else
    setDialogStatus("")
    armReady(row, deal)
  end
end

local function onBuyClick(row)
  local deal = row.deal
  if not deal then return end

  if dialog and dialog.row == row then
    dialog:Show() -- already this row's dialog (e.g. it got buried); nothing else to do
    return
  end

  if dialog and dialog.row then
    local otherStage = dialog.row.purchaseStage
    if otherStage == "buying" or otherStage == "confirm" or otherStage == "requote"
        or otherStage == "confirming" then
      -- A purchase call has already been issued for the row the dialog is showing (between
      -- Start/PlaceBid and its resolution) -- never silently abandon that to open a different
      -- row's dialog; the player must resolve it or explicitly Cancel first.
      driver.onStatus("finish the pending buy first")
      return
    end
    -- The other row is only "ready" or "requerying" -- no purchase call in flight yet, so
    -- it's safe to close its dialog session and let this row take over the single dialog.
    abortRowPurchase(dialog.row, nil)
  end

  openDialog(row, deal)
end

-- Cancels/resets any purchase in flight and clears the tracking tables. Used on AH close
-- so stale disabled buttons or pinned rows never leak into the next Auction House visit.
local function resetAllPurchases()
  if not frame then return end
  for i = 1, #rows do
    local row = rows[i]
    row.purchaseStage = nil
    row.purchaseDeal = nil
  end
  for k in pairs(pendingAuction) do pendingAuction[k] = nil end
  for k in pairs(activeItemID) do activeItemID[k] = nil end
  for k in pairs(awaitingRequery) do awaitingRequery[k] = nil end
  for k in pairs(awaitingKeyInfo) do awaitingKeyInfo[k] = nil end
  for k in pairs(pendingRequerySend) do pendingRequerySend[k] = nil end
  commodityPurchase = nil
  if dialog then
    dialog.row = nil
    requoteArmToken = requoteArmToken + 1 -- invalidate any countdown still in flight
    hideRequoteBanner()
    dialog:Hide()
  end
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

  -- E.1 zebra + hover: full-width BACKGROUND textures, drawn behind every other row widget
  -- (including the Buy button) regardless of creation order -- BACKGROUND always renders
  -- under ARTWORK. The zebra fill alternates by POOL index, not by the deal's position in
  -- the current sorted view, so it stays visually stable across a resort/rescan instead of
  -- flickering as rows are reassigned to different deals.
  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetAllPoints()
  zebra:SetColorTexture(1, 1, 1, (index % 2 == 1) and 0.08 or 0)
  row.zebra = zebra

  local highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1) -- sublevel 1: above zebra, still under ARTWORK
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.12)
  highlight:Hide()
  row.highlight = highlight

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

  -- A + E.1: hover tooltip and highlight on the row ITSELF, not an overlay on top of the Buy
  -- button -- a Frame's OnEnter/OnLeave don't consume mouse events, so the button (a separate
  -- child widget) keeps handling its own clicks exactly as before. row.deal is nil for an
  -- empty/hidden pooled row (refreshRows clears it before Hide()), so there is nothing to
  -- show a tooltip for even if a stray event ever reached a hidden frame.
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    self.highlight:Show()
    if not self.deal then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.deal.itemID)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
    GameTooltip:Hide()
  end)

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

-- E.3/E.4: validates a saved window table before ever handing it to SetPoint/SetHeight --
-- corrupted or hand-edited SavedVariables must never be trusted at face value.
local function isValidSavedWindow(win)
  return type(win) == "table" and type(win.point) == "string"
    and type(win.x) == "number" and type(win.y) == "number"
end

local function clampWindowHeight(h)
  if h < RESIZE_MIN_HEIGHT then return RESIZE_MIN_HEIGHT end
  if h > RESIZE_MAX_HEIGHT then return RESIZE_MAX_HEIGHT end
  return h
end

-- Persists point/x/y (E.3) and height (E.4) together under one saved-variables key --
-- called from the frame's own OnDragStop and the resize handle's OnMouseUp, the only two
-- hardware-driven ways the window's geometry can change.
local function persistWindowGeometry(f)
  local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
  if not cfg then return end
  local point, _, _, x, y = f:GetPoint(1)
  if not point then return end
  cfg.window = { point = point, x = x, y = y, height = f:GetHeight() }
end

-- D: Deals/Sell view switcher. Full Scan/Live are separate widgets untouched by this and stay
-- clickable in both views. Sell's own container, rows, and bag-count refresh are entirely
-- GC.Sell's responsibility (built once by GC.Sell.Attach in createFrame) -- this function only
-- toggles the Deals-side widgets and the tab buttons' enabled state (a disabled
-- UIPanelButtonTemplate button doubles as the "this is the active tab" look).
local function setView(v)
  if view == v or not frame then return end
  view = v
  local isDeals = (v == "deals")
  if isDeals then
    frame.scroll:Show()
    for _, hit in ipairs(frame.dealHeaders) do hit:Show() end
    frame.dealsTab:Disable()
    frame.sellTab:Enable()
    if GC.Sell.Hide then GC.Sell.Hide() end
  else
    frame.scroll:Hide()
    for _, hit in ipairs(frame.dealHeaders) do hit:Hide() end
    frame.sellTab:Disable()
    frame.dealsTab:Enable()
    if GC.Sell.Show then GC.Sell.Show() end
  end
end

local function createFrame()
  local f = CreateFrame("Frame", "GoldCapSniperFrame", UIParent, "BasicFrameTemplateWithInset")

  local savedWindow = GC.db and GC.db.settings and GC.db.settings.sniper and GC.db.settings.sniper.window
  local restoreHeight = FRAME_HEIGHT
  if isValidSavedWindow(savedWindow) and type(savedWindow.height) == "number" then
    restoreHeight = clampWindowHeight(savedWindow.height)
  end
  f:SetSize(FRAME_WIDTH, restoreHeight)

  -- E.4 height-only resize: matching min AND max width to FRAME_WIDTH is what actually
  -- prevents a width change -- the column grid (ROW_WIDTH and every header x-offset above)
  -- is derived from FRAME_WIDTH, so a resized width would desync it from the header row.
  f:SetResizable(true)
  f:SetResizeBounds(FRAME_WIDTH, RESIZE_MIN_HEIGHT, FRAME_WIDTH, RESIZE_MAX_HEIGHT)

  -- E.3 window position: ClearAllPoints then either the saved point/x/y (validated, and
  -- guarded by pcall against a corrupted/hand-edited SavedVariables value) or the original
  -- CENTER default.
  f:ClearAllPoints()
  local restored = false
  if isValidSavedWindow(savedWindow) then
    restored = pcall(f.SetPoint, f, savedWindow.point, savedWindow.x, savedWindow.y)
  end
  if not restored then
    f:ClearAllPoints()
    f:SetPoint("CENTER")
  end

  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    persistWindowGeometry(self)
  end)
  f.TitleText:SetText("GoldCap Sniper")

  -- D: Deals/Sell view switcher tabs, top-left under the title. staleText (below) starts its
  -- TOPLEFT past both tabs so a long stale message can never visually collide with them --
  -- staleText right-justifies within its own span regardless, but this keeps the row's left
  -- portion unambiguously the tabs' own space rather than relying on that alone.
  local dealsTab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  dealsTab:SetSize(TAB_WIDTH, TAB_HEIGHT)
  dealsTab:SetPoint("TOPLEFT", PANEL_LEFT, -18)
  dealsTab:SetText("Deals")
  dealsTab:Disable() -- Deals is the default view; Disable() doubles as the "active tab" look
  dealsTab:SetScript("OnClick", function() setView("deals") end)
  f.dealsTab = dealsTab

  local sellTab = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sellTab:SetSize(TAB_WIDTH + 14, TAB_HEIGHT) -- extra width for the "Sell (NN)" badge text
  sellTab:SetPoint("LEFT", dealsTab, "RIGHT", TAB_GAP, 0)
  sellTab:SetText("Sell")
  sellTab:SetScript("OnClick", function() setView("sell") end)
  f.sellTab = sellTab

  local tabsWidth = TAB_WIDTH + TAB_GAP + (TAB_WIDTH + 14)

  -- B: import staleness. Full width so a long "import stale -- /goldcap import" message
  -- never clips, right-justified so it still reads as sitting on the right; sits between
  -- the title and the Full Scan/Live button row so it never crowds either. Hidden until
  -- refreshStaleText() (called on AH show and after every full scan) says otherwise.
  local staleText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  staleText:SetPoint("TOPLEFT", PANEL_LEFT + tabsWidth + 8, -18)
  staleText:SetPoint("TOPRIGHT", -34, -18)
  staleText:SetJustifyH("RIGHT")
  staleText:SetWordWrap(false)
  staleText:Hide()
  f.staleText = staleText

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

  -- D: every Deals-only header hit-frame collected here so setView (below) can hide/show them
  -- as a group when the player switches to the Sell tab, without hiding anything Sell-specific.
  f.dealHeaders = {}

  -- sortKey (E.2), when given, makes the header clickable: OnMouseDown sets/toggles the
  -- module-local sortOverride and re-renders. "Item" passes no sortKey and stays inert.
  local function addHeader(text, x, width, justify, tooltipLines, sortKey)
    local hit = CreateFrame("Frame", nil, f)
    f.dealHeaders[#f.dealHeaders + 1] = hit
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

    if sortKey then
      hit:EnableMouse(true) -- redundant when tooltipLines already enabled it; harmless otherwise
      sortHeaders[sortKey] = { label = label, base = text }
      hit:SetScript("OnMouseDown", function()
        onHeaderSortClick(sortKey)
      end)
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
  }, "tier")
  addHeader("%", discountX, DISCOUNT_WIDTH, "LEFT", {
    "Discount",
    "Discount vs market value from your GoldCap import",
  }, "pct")
  addHeader("Price", priceX, PRICE_WIDTH, "RIGHT", {
    "Price",
    "Total cost to buy this auction",
  }, "price")
  addHeader("Profit", profitX, PROFIT_WIDTH, "RIGHT", {
    "Profit",
    "Estimated resale profit at 95% of market value, whole stack",
  }, "profit")

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", PANEL_LEFT, SCROLL_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -PANEL_RIGHT_INSET, SCROLL_BOTTOM)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    local target = self:GetVerticalScroll() - delta * ROW_HEIGHT * 3
    if target < 0 then target = 0 end
    if target > range then target = range end
    self:SetVerticalScroll(target)
  end)
  f.scroll = scroll -- D: setView hides/shows this alongside f.dealHeaders for the Sell tab

  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(ROW_WIDTH, ROW_HEIGHT) -- refreshRows() stamps the real height once there are deals to show
  scroll:SetScrollChild(content)

  -- E.4 drag handle: a small BOTTOMRIGHT grip, sized/positioned to sit in the scrollbar
  -- gutter (PANEL_RIGHT_INSET) below the scroll frame's own bottom edge, not on top of the
  -- rows. StartSizing("BOTTOM") + the width-locked bounds above mean only the frame's height
  -- actually changes as the player drags. Created AFTER scroll (whose built-in scrollbar is
  -- a child one level deeper) and explicitly raised past it, so the grip always wins the
  -- corner's mouse-hit test instead of silently losing clicks to the scrollbar's own
  -- down-arrow button.
  local resizeHandle = CreateFrame("Button", nil, f)
  resizeHandle:SetSize(16, 16)
  resizeHandle:SetPoint("BOTTOMRIGHT", -4, 4)
  resizeHandle:EnableMouse(true)
  resizeHandle:SetFrameLevel(scroll:GetFrameLevel() + 10)
  local grip = resizeHandle:CreateTexture(nil, "OVERLAY")
  grip:SetAllPoints()
  grip:SetColorTexture(1, 1, 1, 0.35)
  resizeHandle:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOM")
  end)
  resizeHandle:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    persistWindowGeometry(f)
  end)
  f.resizeHandle = resizeHandle

  table.insert(UISpecialFrames, "GoldCapSniperFrame") -- Escape closes the window

  -- D: builds the Sell tab's container, hidden, filling the exact region `scroll` occupies
  -- above (same PANEL_LEFT/PANEL_RIGHT_INSET/SCROLL_TOP/SCROLL_BOTTOM/ROW_WIDTH/ROW_HEIGHT --
  -- passed through, never re-declared, so the two views can't silently drift out of alignment).
  GC.Sell.Attach(f, {
    panelLeft = PANEL_LEFT,
    panelRightInset = PANEL_RIGHT_INSET,
    top = SCROLL_TOP,
    bottom = SCROLL_BOTTOM,
    rowWidth = ROW_WIDTH,
    rowHeight = ROW_HEIGHT,
  })

  return f
end

function GC.Sniper.Toggle()
  frame = frame or createFrame()
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
    refreshStaleText() -- B: keep the banner current even if it's been a while since the last AH visit
    -- D: bag counts (and therefore the Sell tab badge) may be stale from whenever the window
    -- was last open -- cheap to recompute on every show regardless of which tab is active.
    GC.Sell.Refresh()
    updateSellTabLabel()
  end
end

function GC.Sniper.OnAuctionHouseShow()
  -- B: independent of autoOpen/window visibility -- the chat warning is meant to reach the
  -- player even if they keep the sniper window closed.
  maybeWarnStale()

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
  refreshStaleText() -- B: refresh on every AH show, not just once at window creation
  -- D: bag counts (mail may have been fetched since the last visit) and the Sell tab badge --
  -- refreshed regardless of which tab is active, same reasoning as GC.Sniper.Toggle() above.
  GC.Sell.Refresh()
  updateSellTabLabel()
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
  -- D: abort any in-flight Sell quote walk/post -- neither can safely resume once the AH
  -- session is gone (same reasoning as resetAllPurchases above for the Deals side).
  GC.Sell.Reset()
  if frame then frame:Hide() end
end
