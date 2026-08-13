local _, GC = ...

GC.Sniper = GC.Sniper or {}
GC.Sniper._liveTargets = {}
GC.Sniper._liveTracksScanDeals = false

local Theme = GC.Theme

local ROW_HEIGHT = Theme.ROW_H
local ROW_CAP = 100 -- hard cap on rendered/pooled deal rows, for both watchlist and full-scan modes

-- Sniper v3: window chrome is Theme.Panel + Theme.TitleBar (see createFrame) instead of
-- BasicFrameTemplateWithInset, and BOTH width and height are now resizable (T5 -- previously
-- only height could change, which is why the old column grid derived every offset from a
-- single fixed FRAME_WIDTH). The column grid below is now driven by COLUMNS + anchorColumns:
-- every fixed-width cell anchors relative to its neighbor (right-to-left off the row/header
-- container's own RIGHT edge), and the `content`/`header` containers themselves track the
-- frame's live width via SetPoint, so a resize re-flows the grid with no recompute step
-- anywhere in this file -- the one thing that DOES need an explicit resync is the ScrollFrame's
-- scroll child (`content`), which Blizzard's scroll widget requires an explicit SetWidth for
-- (see createFrame's f:SetScript("OnSizeChanged", ...) -- observed off the window frame
-- itself, not the ScrollFrame, so it keeps firing even while the ScrollFrame is hidden behind
-- the Sell tab; M8).
local FRAME_WIDTH = 640
local FRAME_HEIGHT = 520
local RESIZE_MIN_WIDTH = 560
local RESIZE_MAX_WIDTH = 1100
local RESIZE_MIN_HEIGHT = 300
local RESIZE_MAX_HEIGHT = 900

-- Content-area margins. CONTENT_RIGHT_GUTTER (scrollbar gutter reserved by
-- UIPanelScrollFrameTemplate) has no Theme equivalent -- Theme doesn't know about Blizzard's
-- scrollbar width -- so it stays a plain named constant, same as before.
local CONTENT_LEFT = Theme.pad.m
local CONTENT_RIGHT_GUTTER = 32

local ICON_SIZE = 16 -- row/dialog item icon size; no Theme equivalent (Theme has no icon factory)

-- E.2 sortable headers -- unchanged mapping (only "tier"/"pct"/"price"/"profit" were ever
-- sortable; the two columns COLUMNS adds for Sniper v3, unit/trend, stay inert like "buy").
local REQUOTE_WARN_RATIO = 0.05
local REQUOTE_LOUD_RATIO = 0.25
-- How long the loud prompt refuses the confirming click. Long enough that a second click
-- already on its way lands on a disabled button, short enough not to feel broken.
local REQUOTE_ARM_SECONDS = 1.5
local REQUOTE_BANNER_HEIGHT = 46
-- How many order-book entries the dialog will read. Purely a bound on work done against
-- already-fetched results; a purchase never spans anywhere near this many price levels.
local MAX_BOOK_LEVELS = 100
-- How far above the live market an imported market value has to sit before the dialog stops
-- treating it as information and says so.
-- How long a confirmed quote stays clickable in the dialog. Generous on purpose: the player
-- is reading a grid of numbers, and an older quote is safe on both paths -- an item auction
-- is immutable (PlaceBid either buys at exactly the shown price or fails because the lot is
-- gone), and a commodity purchase always re-quotes server-side via StartCommoditiesPurchase
-- before the separate Confirm click (with the >5% requote re-prompt on top).
local ARM_TIMEOUT_SECONDS = 30
local BUY_TIMEOUT_SECONDS = 8
local REQUERY_TIMEOUT_SECONDS = 8
-- Task 8 hover pre-warm: how long a cached deal.prewarm result stays consumable by openDialog
-- before it's treated as expired (falls back to today's requery-then-arm flow instead).
local PREWARM_TTL_SECONDS = 10
-- If no browse event arrives within this long after a send (initial query or page
-- request), the paging chain is presumed stalled -- see armScanWatchdog.
local SCAN_WATCHDOG_SECONDS = 15

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
local sortHeaders = {}          -- sortKey -> { label = FontString, base = string }; filled once by addHeader calls

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

-- T6 streaming: deals now surface WHILE the scan pages instead of only once
-- HasFullBrowseResults() finally goes true. TWO counters, not one, because
-- GC.FullScan.RowsFromBrowse filters (a browse aggregate with no itemID/minPrice is
-- dropped), so "raw browse entries seen" and "rows produced from them" are different
-- lengths -- conflating them would either re-convert already-converted raw entries or skip
-- some on the next tail slice.
local streamRows = {}      -- rows (RowsFromBrowse's { itemID, count, buyoutStack } shape) accumulated across every page of the CURRENT scan pass
local streamRawCount = 0   -- #C_AuctionHouse.GetBrowseResults() already converted into streamRows -- the raw-array watermark
local streamRowsCount = 0  -- #streamRows already handed to EvaluateDelta -- its fromIndex on the next call

-- Purchase-flow bookkeeping. A row is "pinned" (activeItemID[itemID] = true) from the
-- first arming click until the purchase resolves, so refreshRows() never repurposes it
-- mid-flight. pendingAuction tracks in-flight item (non-commodity) buys by auctionID for
-- AUCTION_HOUSE_PURCHASE_COMPLETED lookup; commodityPurchase tracks the single in-flight
-- commodity buy (Blizzard only allows one commodity purchase flow at a time).
local pendingAuction = {}
local activeItemID = {}

-- T6: the pooled row widget currently under the mouse (nil when none). refreshRows() runs
-- far more often once streaming is wired in (every browse page, not just once at scan end),
-- so without this a fast click mid-hover could land after a merge reassigned that screen
-- slot to a different deal. Pinned the same way purchaseStage rows already are: excluded
-- from sortedDeals()'s output (so the frozen deal doesn't ALSO reappear in some other row)
-- and skipped by refreshRows()'s re-stamp loop (so its own content never changes underneath
-- the cursor). Cleared on OnLeave (with an immediate refreshRows() to catch up on whatever
-- it missed while frozen) and on resetAllPurchases() so an AH close can never leave a stale
-- pin across sessions.
local hoveredRow = nil
local commodityPurchase = nil
-- Commodity events do not include an attempt identifier. A cancelled purchase therefore owns a
-- tombstone until a terminal event consumes it (or the AH session resets): a late price update
-- is not terminal and must never make a later Start safe to attribute its terminal event to.
-- A confirmed attempt can use the same tombstone across an AH close, carrying its immutable
-- final quote so a late success can still be recorded exactly rather than guessed.
local commodityDraining = nil

local function drainCommodityPurchase(row)
  local pending = commodityPurchase
  if pending and pending.row == row then
    commodityPurchase = nil
    commodityDraining = pending
    -- No event token can prove a terminal belongs to this attempt. Stay fail-closed until a
    -- terminal event arrives or the Auction House session resets, even after a price update.
    return pending
  end
end

-- Task-3 buy-after-scan requery. A full-scan deal's snapshot price/auction can be stale
-- (a browse result is a per-itemKey aggregate across every seller, not a resolved auction,
-- and it's a point-in-time snapshot besides), so the FIRST Buy click on one issues a fresh
-- SendSearchQuery instead of arming straight off scanDeals. These two tables are keyed by
-- itemID and live on the FRAME, deliberately separate from the watchlist scanner's own
-- single-slot `pending` state (Core/Scanner.lua), so a requery in flight can never collide
-- with -- or get misrouted into -- an unrelated watchlist scan cycle.
-- Every value below is the exact immutable attempt table
-- `{ row, itemID, token, deal, sent }`, never just a row. Search events are untagged, so a
-- sent attempt that is cancelled or times out moves to requeryDraining until one result event
-- consumes it; no authoritative same-item Check starts while that fence exists.
-- awaitingRequery: itemID -> attempt, from the moment the Check starts until its matching
-- search result arrives. awaitingKeyInfo: itemID -> attempt while item-key info is pending.
-- pendingRequerySend: itemID -> attempt while throttle readiness is pending.
local awaitingRequery = {}
local awaitingKeyInfo = {}
local pendingRequerySend = {}
local requeryDraining = {}
-- A row can be waiting only to consume an older untagged result (rather than waiting for a
-- query of its own). Keep that wait as an exact attempt too, so a retained Live pause has a
-- concrete lifecycle through the drain fence instead of being orphaned on the early return.
GC.Sniper._drainWaitRequery = {}

-- Task 8 hover pre-warm. Its OWN pending slot, deliberately separate from awaitingRequery
-- above -- that table is row-keyed (a dialog is always open for whichever row it tracks) and
-- can hold many rows worth of state across a session; pre-warm never opens or touches a
-- dialog, and the spec caps it at ONE in flight globally, so a single scalar slot is enough
-- and (critically) keeps the two consumers unambiguous: OnItemSearchResults/
-- OnCommoditySearchResults key their dialog-arming branch off awaitingRequery[itemID] exactly
-- as before, and separately, independently, check prewarmAttempt.itemID == itemID for the pre-warm
-- branch -- a stale/duplicate event can resolve either, both, or neither without the two ever
-- fighting over which one gets to touch the row/dialog (pre-warm's resolver never does).
-- prewarmAttempt: the exact item/token/deal query currently being pre-warmed, or nil. Its deal
-- table receives deal.prewarm only if that exact request receives the result.
-- stamped onto THIS table when the result lands, never looked up fresh by itemID (a full-scan
-- rescan can splice a NEW deal table for the same itemID while a pre-warm is still in flight;
-- stamping the original table, not whatever `deals`/`scanDeals` currently maps the itemID to,
-- is what "leaving the row does not cancel" means in practice -- the result is only ever
-- useful to openDialog via THIS row's THIS deal, not some unrelated later snapshot).
-- Pre-warm has the same untagged-result problem. It has no row, but still uses the exact
-- attempt identity `{ itemID, token, deal, sent }`; retiring a sent warm uses the shared
-- same-item drain fence before a real Check can issue a new authoritative query.
local prewarmAttempt = nil
local prewarmToken = 0
-- fix round 1 M-3: true only while a real Auction House session is live (set/cleared at the
-- very top of OnAuctionHouseShow/OnAuctionHouseClosed below). The Sniper window itself can
-- stay open, or be reopened via /goldcap, with leftover deals from the last visit still
-- rendered/hoverable after AH close -- pre-warm must not fire against those (SendSearchQuery
-- and friends are meaningless, possibly erroring, with no AH session backing them).
local ahOpen = false

GC.Sniper.session = { buys = 0, spent = 0, estProfit = 0 }

-- Sniper v3 §3: Core/AutoScan.lua's pure state machine, wired to the real Full Scan
-- machinery below (actions = { startScan = startFullScan, abortScan = cancelFullScan }) once
-- those exist -- see the `autoScan = GC.AutoScan.New(...)` assignment further down. Forward-
-- declared here, same pattern as `resolvePurchase`/`createRow` above and below, so every
-- call site ABOVE that assignment (applyFullScanResults, armScanWatchdog) can still close
-- over the same module-local upvalue. autoScanTicker drives m:Tick(GetTime()) at ~4Hz while
-- the Auction House is open; nil the rest of the time (C_Timer.NewTicker on AH show,
-- :Cancel() on AH close -- see GC.Sniper.OnAuctionHouseShow/OnAuctionHouseClosed).
local autoScan
local autoScanTicker
-- feedAuto funnels EVERY AutoScan input through one place (instead of bare
-- `autoScan:Input(...)` calls scattered across the file) so the Auto button's label/pulse
-- (refreshAutoButton, assigned once the button itself is built in createFrame) can never
-- drift out of sync with a state transition. Also forward-declared for the same upvalue
-- reason as autoScan.
local feedAuto
local refreshAutoButton

-- New-HOT-deal ping (spec §3): keyed itemID.."@"..unitPrice so a genuinely NEW listing at a
-- NEW price re-pings even for an item that already had an older HOT listing earlier in the
-- same AH session, while a recurring listing at the SAME price across rescans never re-pings.
-- Module-level (not per-scan) and reset only on ahClosed -- see GC.Sniper.OnAuctionHouseClosed
-- -- so consecutive Full Scans/Auto passes within one AH visit don't spam the same deals.
local seenHotDeals = {}

local function sortedDeals()
  -- T6: the hovered row's own deal (if any) is excluded here too, same as an
  -- activeItemID-pinned one -- refreshRows() below never re-stamps that row, so if its deal
  -- stayed in `list` it would render TWICE: frozen in its own row and fresh wherever the
  -- rest of the list now ranks it.
  local hoveredItemID = hoveredRow and hoveredRow.deal and hoveredRow.deal.itemID
  local list = {}
  if mode == "fullscan" then
    -- GC.FullScan.Evaluate already returns tier-rank/profit sorted order; filtering out
    -- pinned itemIDs preserves that order (no re-sort needed).
    for _, deal in ipairs(scanDeals) do
      if not activeItemID[deal.itemID] and deal.itemID ~= hoveredItemID then
        list[#list + 1] = deal
      end
    end
    return list
  end
  for itemID, deal in pairs(deals) do
    if not activeItemID[itemID] and itemID ~= hoveredItemID then
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
-- see the addHeader calls. I6: "unit" (per-unit price) is its OWN sort key, independent of
-- "price" (total = unit*qty) -- total's own column (COLUMNS "total") is one of the two
-- responsively-dropped columns (see computeHidden), so without a separate always-visible
-- sort key, sorting the list by price would become unreachable via the header at any window
-- width <=724px. "unit" lives on the never-dropped COLUMNS "unit" column instead.
local SORT_VALUE = {
  tier = function(deal) return TIER_RANK[deal.tier] or 9 end,
  pct = function(deal) return deal.discount end,
  unit = function(deal) return deal.unitPrice end,
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

-- GetCoinTextureString's inline coin icons are too wide for a narrow column once the amount
-- climbs into three-plus digit gold -- collapse anything >= 100g to a plain "<N>g" instead of
-- letting the icon string overflow the column.
local function formatColumnAmount(copper)
  if copper >= GOLD_COMPACT_THRESHOLD then
    return ("%dg"):format(math.floor(copper / 10000))
  end
  return GetCoinTextureString(copper)
end

-- Dim suffix appended after the (possibly quality-colored) item name; a separate color code
-- of its own so it never inherits the name's quality color.
--
-- Fix 1 (honest quantity display): `deal.qty` is a SUGGESTED flip size (FullScan.RowsFromBrowse
-- caps it well below what the market actually holds -- see that file's own comment), not the
-- lot size -- rendering it bare as "x200" reads as "that's all there is" when the board might
-- really carry 1646. Whenever `avail` (the real total) is known and bigger than qty, show
-- both so the number in the suffix stops implying a scarcity that isn't real.
local function qtySuffix(deal)
  if deal.avail and deal.avail > deal.qty then
    return ("|cffaaaaaa x%d of %d|r"):format(deal.qty, deal.avail)
  end
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

-- ---------------------------------------------------------------------------
-- Sniper v3 column grid. One table drives BOTH the header row and every pooled deal row
-- (createHeaderRow/createRow below) -- widths/order can never drift out of alignment with
-- each other, and (new for T5) a window WIDTH resize re-flows every column automatically:
-- anchorColumns chains each fixed column's RIGHT edge to the previous one's LEFT edge (or the
-- container's own RIGHT edge for the first), right-to-left, off a `container` that itself
-- tracks the frame's live width -- so nothing here ever needs a recomputed pixel offset.
--
-- `optional = true` (total, trend) marks the two columns that responsively drop when the item
-- (flex) column's own implied width would otherwise fall below its min -- see computeHidden
-- below. Both stay reachable in the buy dialog's own price grid (unit/total/trend each have
-- their own grid row there) whenever they're hidden from the list, so no information is lost,
-- only a glance-at-the-list convenience.
-- ---------------------------------------------------------------------------
local COLUMNS = {
  { key = "item",   flex = true, min = 180 },
  { key = "tier",   w = 48 },
  { key = "disc",   w = 56,  num = true, size = 15, bold = true },
  { key = "unit",   w = 76,  num = true, size = 12 },
  { key = "total",  w = 84,  num = true, size = 12, optional = true },
  { key = "profit", w = 84,  num = true, size = 13, bold = true },
  { key = "trend",  w = 44,  num = true, size = 11, optional = true },
  { key = "buy",    w = 52 },
}

-- Anchors every VISIBLE fixed COLUMNS entry's RIGHT edge right-to-left off `container`'s own
-- RIGHT edge; any entry present in `hidden` (a set of COLUMNS.key -> true) is Hidden and
-- skipped from the chain entirely -- the next visible column simply anchors past it, so
-- dropping/restoring a column never leaves a gap-shaped hole. `cellFor(col)` returns the
-- ALREADY-BUILT widget for `col` (built once, up front -- see buildRowCell/buildHeaderCell)
-- so re-running this on a resize only re-anchors/shows/hides, never re-creates widgets.
-- Returns the flex ("item") column's anchor pair -- {frame, point} -- for the caller to anchor
-- the item content's RIGHT edge to, since item has no single themed cell of its own
-- (createRow/createHeaderRow build icon+name directly).
local function anchorColumns(container, hidden, cellFor)
  local prev, prevPoint = container, "RIGHT"
  local flexAnchor
  for i = #COLUMNS, 1, -1 do
    local col = COLUMNS[i]
    if col.flex then
      flexAnchor = { frame = prev, point = prevPoint }
    else
      local cell = cellFor(col)
      if hidden[col.key] then
        cell:Hide()
      else
        cell:Show()
        cell:ClearAllPoints()
        cell:SetWidth(col.w)
        if prevPoint == "RIGHT" then
          cell:SetPoint("RIGHT", prev, "RIGHT")
        else
          cell:SetPoint("RIGHT", prev, "LEFT", -Theme.pad.s, 0)
        end
        prev, prevPoint = cell, "LEFT"
      end
    end
  end
  return flexAnchor
end

-- Column key -> row widget field name, for the plain numeric cells (tier/buy build their
-- own typed widgets directly in buildRowCell below).
local NUM_FIELD = { disc = "discountText", unit = "unitText", total = "priceText", profit = "profitText", trend = "trendText" }

-- Column key -> width, for the few places outside the row/header grid that need to match a
-- COLUMNS width exactly (M13: the dialog's own tier chip, so it can never drift out of sync
-- with the list's tier column width).
local COLUMN_W = {}
for _, col in ipairs(COLUMNS) do
  if col.w then COLUMN_W[col.key] = col.w end
end

-- ---------------------------------------------------------------------------
-- Sniper v3 responsive column drop. OPTIONAL_KEYS lists the `optional` COLUMNS entries in
-- table order (total, then trend) -- that order IS the drop priority (data-driven off COLUMNS
-- itself, not a hard-coded `if col.key == "total"`), and DROP_THRESHOLDS[i] is the item-column
-- width below which OPTIONAL_KEYS[i] hides. computeHidden recomputes from scratch on every
-- width sample rather than tracking incremental state, so re-showing a column as the window
-- grows back is just the same rule read the other way (trend re-appears before total, simply
-- because it was the last one dropped and its own threshold is the first one no longer failed).
-- ---------------------------------------------------------------------------
local OPTIONAL_KEYS, DROP_THRESHOLDS = {}, { 180, 150 }
for _, col in ipairs(COLUMNS) do
  if col.optional then OPTIONAL_KEYS[#OPTIONAL_KEYS + 1] = col.key end
end

-- Fixed pixel budget (every VISIBLE fixed column's width, plus one Theme.pad.s gap per visible
-- fixed column -- anchorColumns puts exactly one gap in front of each: the outer name-to-
-- first-column gap for the first one, an inter-column gap for every other one) for the columns
-- NOT in `hidden`. containerWidth minus this budget IS the item (flex) column's own implied
-- width: the icon and name both live inside that flex zone, so COLUMNS.item.min is measured
-- against the whole zone, not the name text alone.
local function fixedColumnBudget(hidden)
  local sum, visible = 0, 0
  for _, col in ipairs(COLUMNS) do
    if not col.flex and not hidden[col.key] then
      sum = sum + col.w
      visible = visible + 1
    end
  end
  return sum + visible * Theme.pad.s
end

local function computeHidden(containerWidth)
  local hidden = {}
  for i, key in ipairs(OPTIONAL_KEYS) do
    local itemWidth = containerWidth - fixedColumnBudget(hidden)
    if itemWidth < DROP_THRESHOLDS[i] then
      hidden[key] = true
    end
  end
  return hidden
end

local function sameHidden(a, b)
  for _, key in ipairs(OPTIONAL_KEYS) do
    if (not a[key]) ~= (not b[key]) then return false end
  end
  return true
end

-- Current drop state, shared by the header row and every pooled deal row -- recomputed by
-- applyColumnVisibility (below createRow) whenever the scroll/content width changes.
local hiddenColumns = {}

local function setRowDeal(row, deal)
  -- (fix round 1, M3) A pooled row's ping flash must not migrate onto whatever deal gets
  -- reassigned into this same screen slot on the next refresh -- Stop() doesn't fire
  -- OnFinished (that only runs on natural completion), so the highlight/alpha reset that
  -- normally happens there has to be done explicitly here too. Only stops on an itemID
  -- CHANGE -- the same item re-stamped with a fresher price (still mid-flash) keeps flashing.
  if row.flashAnim and row.deal and row.deal.itemID ~= deal.itemID then
    row.flashAnim:Stop()
    if hoveredRow ~= row then row.highlight:Hide() end
    row.highlight:SetAlpha(1)
  end
  row.deal = deal
  row.buy:SetLabel(deal.action or "Check")
  local color = Theme.tier[deal.tier] or Theme.tier.WATCH
  row.tierChip:SetLabel(tierLabel(deal), color)

  row.discountText:SetText(("%d%%"):format(math.floor(deal.discount * 100 + 0.5)))
  row.discountText:SetTextColor(color[1], color[2], color[3])

  row.unitText:SetText(formatColumnAmount(deal.unitPrice))
  row.priceText:SetText(formatColumnAmount(deal.unitPrice * deal.qty)) -- total cost, not per-unit
  row.profitText:SetText(formatColumnAmount(deal.profit))
  if deal.profit >= 0 then
    row.profitText:SetTextColor(Theme.color.green[1], Theme.color.green[2], Theme.color.green[3])
  else
    row.profitText:SetTextColor(Theme.color.red[1], Theme.color.red[2], Theme.color.red[3])
  end

  -- Sniper v3 trend column: mirrors the dialog's own value.trend read (updateDialogAmounts)
  -- -- import-sourced values only, absent for bundled/no-import (dim dash then). Reads
  -- GC.Data.GetItemValue directly rather than through `driver` -- `driver` (below) isn't
  -- declared yet at this point in the file, and driver.getValue is that same function anyway.
  local value = GC.Data.GetItemValue(deal.itemID)
  if value and value.trend then
    local glyph = value.trend < 0 and "▼" or "▲"
    row.trendText:SetText(("%s%d%%"):format(glyph, math.abs(value.trend)))
    local tc = value.trend < 0 and Theme.color.red or Theme.color.green
    row.trendText:SetTextColor(tc[1], tc[2], tc[3])
  else
    row.trendText:SetText("—")
    row.trendText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  end

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
-- layoutRow is forward-declared alongside it for the same reason: applyColumnVisibility
-- (right below) re-layouts every pooled row on a column-drop change, but its own real
-- definition (like createRow's) needs the row widget fields built further down. layoutHeaderRow
-- is forward-declared the same way (M7): applyColumnVisibility calls THIS module-local
-- directly, never `frame.layoutHeaderRow` -- reading a field off the module-level `frame` var
-- would let a stray early resize event (frame not yet assigned, or the header not built yet)
-- silently update `hiddenColumns` ("mark state applied") with nothing around to actually lay
-- it out; gating on the local being non-nil instead means the state genuinely isn't touched
-- until there's a real layout function to apply it with.
local createRow, layoutRow, layoutHeaderRow

-- Re-applies the current responsive column drop to the header and every pooled row --
-- called from createFrame's f:SetScript("OnSizeChanged", ...) (M8) whenever the window's live
-- width changes. Recomputes `hiddenColumns` from scratch (see computeHidden) and only touches
-- widgets when the drop STATE actually changed, so a resize that doesn't cross a threshold
-- costs nothing beyond the cheap sameHidden comparison.
local function applyColumnVisibility(containerWidth)
  if not layoutHeaderRow then return end -- header not built yet (see M7 comment above)
  local newHidden = computeHidden(containerWidth)
  if sameHidden(newHidden, hiddenColumns) then return end
  hiddenColumns = newHidden
  layoutHeaderRow()
  for i = 1, #rows do layoutRow(rows[i]) end
end

-- Rows mid-purchase (row.purchaseStage set) are pinned in place: refreshRows() leaves
-- their content untouched instead of repurposing the widget to a different deal out from
-- under an in-flight click sequence. sortedDeals() already excludes their itemID so no
-- other row duplicates them. T6: the hovered row (see `hoveredRow` above) is pinned the
-- same way, for the same reason -- streaming now calls this on every browse page, and the
-- row under the cursor must not change identity between a click landing and the button
-- underneath it processing that click.
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
    if not row.purchaseStage and row ~= hoveredRow then
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
-- text. sortHeaders is populated once by the addHeader calls. Literal UTF-8 glyphs
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
    frame.staleText:SetTextColor(Theme.color.red[1], Theme.color.red[2], Theme.color.red[3])
    frame.staleText:Show()
  elseif age < STALE_YELLOW_SECONDS then
    frame.staleText:Hide()
  elseif age < STALE_RED_SECONDS then
    local label = isAppData and "auto-synced %dh ago" or "import %dh old"
    frame.staleText:SetText(label:format(math.floor(age / 3600)))
    frame.staleText:SetTextColor(Theme.tier.SUSPECT[1], Theme.tier.SUSPECT[2], Theme.tier.SUSPECT[3])
    frame.staleText:Show()
  else
    frame.staleText:SetText(isAppData and "auto-synced data stale -- /goldcap import" or "import stale -- /goldcap import")
    frame.staleText:SetTextColor(Theme.color.red[1], Theme.color.red[2], Theme.color.red[3])
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

-- The decision engine owns every purchase-safety judgement. Keep the raw Data shape at this
-- one boundary so a UI caller cannot accidentally make a tier/profit calculation authoritative.
local function marketForDecision(itemID)
  local value = GC.Data.GetItemValue(itemID) or {}
  return {
    kind = value.kind,
    source = value.source,
    sourceAt = value.sourceAt,
    marketValue = value.mv,
    estimated = value.estimated,
    stressUnit = value.stressUnit,
    soldPerDay = value.sold,
    sellThroughBps = value.sellThroughBps,
    liquidityConfidence = value.liquidityConfidence,
    currentQty = value.currentQty,
    listings = value.listings,
    observations = value.observations,
    madBps = value.madBps,
    trend24hPct = value.trend,
  }
end

local function depositFor(itemID, quantity)
  return C_AuctionHouse.CalculateCommodityDeposit(itemID, 2, quantity)
end

local function evaluateLive(itemID, levels, fixedQuantity, quotedTotal)
  return GC.SniperDecision.Evaluate({
    now = time(),
    market = marketForDecision(itemID),
    live = {
      itemID = itemID,
      levels = levels,
      fixedQuantity = fixedQuantity,
      quotedTotal = quotedTotal,
    },
    walletCopper = GetMoney(),
    depositForQuantity = function(quantity) return depositFor(itemID, quantity) end,
    config = GC.db.settings.sniper,
  })
end

-- Forward-declared: driver.onDeal (below) needs to call this for the "row vanished on
-- rescan" success fallback, but its real definition lives further down alongside the
-- rest of the purchase-flow helpers.
local resolvePurchase

function GC.Sniper._CurrentLiveDeal(itemID)
  if not GC.Sniper._liveTracksScanDeals then return deals[itemID] end
  for _, deal in ipairs(scanDeals) do
    if deal.itemID == itemID then return deal end
  end
  return nil
end

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
    -- Fix 1: info.quantity above is only level 1's own stock (what a purchase quote is built
    -- from) -- `avail` is the market's real depth, summed across every fetched price level, so
    -- the row/dialog can show "x<qty> of <avail>" instead of implying the level-1 quantity is
    -- all there is. Same bounded MAX_BOOK_LEVELS idiom driver.commodityBook uses below, kept as
    -- its own small loop rather than calling commodityBook itself: this only needs a running
    -- total, not the per-level array GC.Book.Fill consumes.
    local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    local avail
    if n and n > 0 then
      if n > MAX_BOOK_LEVELS then n = MAX_BOOK_LEVELS end
      avail = 0
      for i = 1, n do
        local levelInfo = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if levelInfo and levelInfo.quantity then
          avail = avail + levelInfo.quantity
        end
      end
    end
    return { unitPrice = info.unitPrice, qty = info.quantity, avail = avail }
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
    local prior = GC.Sniper._CurrentLiveDeal(deal.itemID)
    if prior and not deal.isCommodity and prior.auctionID and prior.auctionID ~= deal.auctionID then
      local staleRow = pendingAuction[prior.auctionID]
      if staleRow then
        resolvePurchase(staleRow, true, "sniped (listing changed on rescan)")
      end
    end

    if not GC.Sniper._liveTracksScanDeals then deals[deal.itemID] = deal end
    refreshRows()
    if deal.tier == "HOT" and GC.db.settings.sniper.sound then
      PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
  end,

  onObservation = function(itemID, deal)
    if GC.Sniper._liveTracksScanDeals then
      scanDeals = GC.FullScan.ApplyLiveObservation(scanDeals, itemID, deal, ROW_CAP)
    else
      deals[itemID] = deal
    end
    refreshRows()
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
  frame.sellTab:SetLabel(n > 0 and ("Sell (%d)"):format(n) or "Sell")
end
GC.Sniper.UpdateSellTabLabel = updateSellTabLabel

local function clearDeals()
  for itemID in pairs(deals) do deals[itemID] = nil end
  refreshRows()
end

local function startScanning()
  if not GC.Sniper.scanner then return end

  GC.Sniper._liveTargets = {}
  GC.Sniper._liveTracksScanDeals = #scanDeals > 0
  if GC.Sniper._liveTracksScanDeals then
    local seen = {}
    for _, deal in ipairs(scanDeals) do
      local itemID = deal.itemID
      if itemID and not seen[itemID] and #GC.Sniper._liveTargets < ROW_CAP then
        seen[itemID] = true
        GC.Sniper._liveTargets[#GC.Sniper._liveTargets + 1] = itemID
      end
    end
  else
    GC.Sniper._liveTargets = GC.Data.GetWatchlist(100)
  end

  mode = GC.Sniper._liveTracksScanDeals and "fullscan" or "watchlist"
  GC.Sniper.scanner:Stop() -- re-Start while a search is in flight drops it silently: always Stop first
  GC.Sniper.scanner:Start(GC.Sniper._liveTargets)
  scanning = #GC.Sniper._liveTargets > 0
  if frame then frame.toggleBtn:SetLabel(scanning and "Stop" or "Live") end
  refreshRows()
end

function GC.Sniper._ResumeLiveScanner()
  if not GC.Sniper.scanner or #GC.Sniper._liveTargets == 0 then return end
  GC.Sniper.scanner:Resume()
  scanning = true
  if frame then frame.toggleBtn:SetLabel("Stop") end
end

local function stopScanning()
  if GC.Sniper.scanner then GC.Sniper.scanner:Stop() end
  scanning = false
  if frame then frame.toggleBtn:SetLabel("Live") end
end

-- A dialog Check owns the throttled search slot over the optional watchlist loop. Its exact
-- attempt lives on GC.Sniper so this very large file stays below Lua's 200-local chunk limit;
-- a result, timeout, or Cancel may resume only the scan it paused, while a manually stopped
-- scanner stays stopped.
function GC.Sniper._ResumePausedLiveRequery(attempt)
  if GC.Sniper._pausedLiveRequery ~= attempt then return end
  GC.Sniper._pausedLiveRequery = nil
  -- An exact Check owner may retire its Live pause only when no browse/Auto mode has claimed
  -- traffic in the meantime. A manual Scan can begin while Check is open; resuming Scanner
  -- into that browse session would create competing throttled searches.
  if ahOpen and not scanning and not scanRunning and not pendingFullScanStart
      and not pendingBrowsePage and autoScan:State() == "OFF" then
    GC.Sniper._ResumeLiveScanner()
  end
end

function GC.Sniper._FinishDrainWait(itemID, draining)
  local wait = GC.Sniper._drainWaitRequery[itemID]
  if not wait or wait.draining ~= draining then return end
  GC.Sniper._drainWaitRequery[itemID] = nil
  GC.Sniper._ResumePausedLiveRequery(wait)
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

-- New-HOT-deal ping (spec §3): 1.5s flash on the row's own hover-highlight texture (E.1's
-- `row.highlight`), reusing it rather than a dedicated texture. row.flashAnim (built once
-- per pooled row in createRow) owns an Alpha animation fading from full brightness to 0;
-- its OnFinished (also wired in createRow) re-hides the highlight unless the row is
-- genuinely under the mouse right now, so a flash ending mid-hover never fights the real
-- hover state.
local function flashRow(row)
  if not row.flashAnim then return end
  row.highlight:SetAlpha(1)
  row.highlight:Show()
  row.flashAnim:Stop()
  row.flashAnim:Play()
end

-- Flashes every surfaced deal's row, if it has one right now, and plays the ping sound ONCE
-- per merge (fix round 1, M4: only if at least one deal actually matched a visible row --
-- previously this played unconditionally off a non-empty `newHotDeals`, so a HOT deal that
-- MergeDeals' own cap truncated away, or that's currently pinned/hovered, still triggered a
-- sound with nothing on screen to look at). Row lookup is by TABLE IDENTITY against `deal` --
-- MergeDeals splices deal tables by reference (see FullScan.lua's MergeDeals), so the exact
-- same table handed to pingNewHotDeals is what refreshRows() (already called by the caller,
-- just before this) stamped onto whichever pooled row rendered it, if any.
local function pingNewHotDeals(newHotDeals)
  local matched = false
  for _, deal in ipairs(newHotDeals) do
    for i = 1, #rows do
      local row = rows[i]
      if row.deal == deal and row:IsShown() then
        flashRow(row)
        matched = true
        break
      end
    end
  end
  if matched and GC.db.settings.sniper.sound then
    PlaySound(SOUNDKIT.MAP_PING or 3175)
  end
end

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
  -- Sniper v3 §3 ping (fix round 1, I2): the completion reconcile needs its own ping pass
  -- too, not just the streaming per-page one below -- a tiny realm's very first browse event
  -- can already report HasFullBrowseResults()==true, so the streaming branch (advanceBrowseScan)
  -- never runs at all for that pass, and without this every HOT deal on such a realm would
  -- never ping. GC.FullScan.CollectNewHot shares the SAME seenHotDeals set the streaming
  -- branch uses, so anything already pinged this pass is correctly skipped here.
  local pingDeals = GC.FullScan.CollectNewHot(scanDeals, seenHotDeals)
  if #pingDeals > 0 then pingNewHotDeals(pingDeals) end
  refreshStaleText() -- B: refresh on every completed scan, not just AH open
  -- T6: the streaming counters only make sense within one scan pass -- the reconcile above
  -- just replaced scanDeals wholesale from the full rows list, so whatever EvaluateDelta had
  -- already walked is moot. Reset here (the scan's one completion point) rather than in
  -- every caller.
  streamRows, streamRawCount, streamRowsCount = {}, 0, 0
  -- Sniper v3 §3: tells AutoScan the scan it started (if it was the one that started this
  -- one) is done, so it can start its breather countdown toward the next pass. A no-op
  -- whenever the machine's own state isn't SCANNING -- e.g. a manual "Scan" click while Auto
  -- is off/paused -- see AutoScan.lua's onScanFinished.
  feedAuto("scanFinished")
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
      if frame then
        -- (fix round 1, M6) "press Full Scan to retry" is dead advice while Auto is armed --
        -- the feedAuto("scanFinished") below already queues its own breather-delayed retry,
        -- and the very next Tick/refreshAutoButton call would immediately overwrite a
        -- "press Full Scan" line with "Auto · scanning" anyway. Pick the text off the
        -- machine's OWN state (read before feeding scanFinished moves it along).
        if autoScan and autoScan:State() ~= "OFF" then
          frame.status:SetText("full scan stalled -- retrying shortly")
        else
          frame.status:SetText("full scan stalled -- press Full Scan to retry")
        end
      end
      -- Sniper v3 §3: without this, a stalled Auto-driven scan would leave the machine
      -- stuck in SCANNING forever (it only ever leaves that state on a scanFinished input) --
      -- feeding it here lets Auto's breather/settle timers retry on the next pass instead of
      -- silently hanging with the button stuck on "Auto · scanning".
      feedAuto("scanFinished")
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
--
-- T6: every call first converts only the NEW raw tail (browseResults[streamRawCount+1 .. n])
-- into rows and appends it to streamRows. RowsFromBrowse's per-row conversion has no
-- cross-row state (each row depends only on its own itemID via getValue), so this chunked
-- concatenation across pages is identical to running RowsFromBrowse once over the whole
-- browseResults array -- just without re-walking rows a prior page already converted. The
-- completion branch reuses streamRows for its own full reconcile for the same reason: by the
-- time HasFullBrowseResults() is true, the tail conversion above has already brought
-- streamRows fully up to date with browseResults, so there's nothing left to gain from
-- recomputing it from scratch.
local function advanceBrowseScan(token)
  local browseResults = C_AuctionHouse.GetBrowseResults()
  local n = #browseResults

  if n > streamRawCount then
    local tail = {}
    for i = streamRawCount + 1, n do tail[#tail + 1] = browseResults[i] end
    local tailRows = GC.FullScan.RowsFromBrowse(tail, GC.Data.GetItemValue)
    for _, row in ipairs(tailRows) do streamRows[#streamRows + 1] = row end
    streamRawCount = n
  end

  if C_AuctionHouse.HasFullBrowseResults() then
    scanRunning = false
    applyFullScanResults(streamRows, n)
  else
    -- Stream: evaluate only the rows added since the last event (EvaluateDelta's fromIndex),
    -- mark them .stale exactly like the completion reconcile does (still just a per-itemKey
    -- aggregate, not a resolved auction), and merge into whatever's already on screen --
    -- MergeDeals' incoming-wins rule means a later page's fresher read of an item replaces an
    -- earlier one instead of both lingering.
    local deltaDeals, newRowsCount = GC.FullScan.EvaluateDelta(
      streamRows, streamRowsCount, GC.Data.GetItemValue, GC.db.settings.sniper)
    streamRowsCount = newRowsCount
    for _, deal in ipairs(deltaDeals) do
      deal.stale = true
    end
    -- Sniper v3 §3 ping (fix round 1, I6): GC.FullScan.CollectNewHot is the SAME pure helper
    -- applyFullScanResults' own completion branch uses, against the same seenHotDeals set --
    -- see that call site's comment for why both branches need their own pass.
    local pingDeals = GC.FullScan.CollectNewHot(deltaDeals, seenHotDeals)
    scanDeals = GC.FullScan.MergeDeals(scanDeals, deltaDeals, 100)
    refreshRows()
    if #pingDeals > 0 then pingNewHotDeals(pingDeals) end
    -- Spec: no page % (Blizzard doesn't expose total pages) -- result count + running deal
    -- count instead.
    if frame then
      frame.status:SetText(("scanning… %d results · %d deals"):format(n, #scanDeals))
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

-- AutoScan's `abortScan` action (Core/AutoScan.lua's actions.abortScan, called only while
-- the machine's own state is SCANNING). Reuses abortFullScan rather than a second parallel
-- cancel path -- whatever already streamed into scanDeals during the aborted pass is left
-- exactly as-is (MergeDeals already folded each page in as it arrived; there's nothing to
-- roll back), only the in-flight pagination itself (throttle-parked requests, the watchdog)
-- needs clearing. A resumed Auto pass always starts a FRESH scan via startFullScan anyway --
-- see AutoScan.lua's own comment on why the aborted pass's browse state must be assumed
-- clobbered.
--
-- Status text (fix round 1, M2): actions.abortScan() is called uniformly by AutoScan.lua
-- with no arguments from three different transitions (any addPause reason, or toggleOff), so
-- the "why" has to be read back off the machine instead of threaded through as a parameter.
-- addPause sets reasons[reason]=true BEFORE calling this, and toggleOff clears `reasons` to
-- {} only AFTER, so PauseReasons() here reliably distinguishes the two: non-empty -> a real
-- pause (dialog/search/mail -- or "ah"/"tab", which get their own silent case since the
-- window/AH is going away regardless and a status line nobody can see would be a lie of a
-- different kind); empty -> this was toggleOff.
local function cancelFullScan()
  abortFullScan()
  if not frame then return end
  local reasons = autoScan and autoScan:PauseReasons() or {}
  if reasons.ah or reasons.tab then
    -- silent: the AH is closing or the window just got hidden -- either way the status line
    -- is about to become moot, and overwriting it here would just flash text nobody reads.
    return
  end
  if next(reasons) == nil then
    frame.status:SetText("auto off")
  else
    frame.status:SetText("auto: paused")
  end
end

-- Starts the actual browse scan. Only ever reached once the throttle system is confirmed
-- ready (synchronously from onFullScanClick, or deferred via GC.Sniper.OnThrottleReady when
-- pendingFullScanStart was set) -- SendBrowseQuery silently no-ops while
-- C_AuctionHouse.IsThrottledMessageSystemReady() is false, which is routinely the case for a
-- beat right after opening the Auction House.
local function startFullScan()
  if scanning then stopScanning() end
  fullScanToken = fullScanToken + 1
  local token = fullScanToken
  scanRunning = true
  pendingBrowsePage = false
  lastBrowseEventAt = 0
  streamRows, streamRawCount, streamRowsCount = {}, 0, 0 -- T6: fresh pass, fresh streaming state
  mode = "fullscan"
  refreshRows() -- reflect the mode switch immediately (shows the prior full-scan results, if any)

  if driver.isReady() then
    sendBrowseQuery(token)
  else
    pendingFullScanStart = true
    if frame then frame.status:SetText("waiting for server... full scan will start automatically") end
  end
end

-- Sniper v3 §3: assigns the forward-declared `autoScan` local now that both actions it needs
-- exist. Default timers (2s breather after a finished scan, 1s settle after every pause
-- reason clears) -- see Core/AutoScan.lua's own DEFAULT_BREATHER/DEFAULT_SETTLE.
--
-- startScan is wrapped (fix round 1, I1) rather than passed as bare `startFullScan`: the
-- machine's own Tick unconditionally sets its state to SCANNING right after calling this
-- action (see AutoScan.lua), regardless of what the action itself did -- so if a scan is
-- ALREADY running (a manual "Scan" click already in flight, or pendingFullScanStart still
-- waiting on the throttle) when Auto arms/resumes, calling startFullScan() again would
-- clobber that scan's own token/state out from under it. Guarding lets Auto instead silently
-- "adopt" the already-running scan: its eventual completion still feeds scanFinished (see
-- applyFullScanResults), which is all the machine needs to correctly continue from there.
autoScan = GC.AutoScan.New({}, {
  startScan = function()
    if scanRunning or pendingFullScanStart then return end
    startFullScan()
  end,
  abortScan = cancelFullScan,
})

feedAuto = function(event)
  autoScan:Input(event, GetTime())
  if refreshAutoButton then refreshAutoButton() end
end

function GC.Sniper._StartLiveMode()
  local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
  if autoScan:State() ~= "OFF" then
    if cfg then cfg.auto = false end
    feedAuto("toggleOff")
  end
  abortFullScan()
  startScanning()
end

local AUTO_PAUSE_LABEL = { dialog = "buying", search = "searching", mail = "mail" }
-- Display priority when more than one pause reason is set at once (e.g. a buy dialog opened
-- while the player's own search was already live) -- "buying" wins because it's the most
-- decisive of the three: the player is one click from spending gold. `ah`/`tab` are
-- deliberately absent -- per spec they render as plain "Auto", not a paused chip, since
-- neither reflects something the player is actively DOING right now.
local AUTO_PAUSE_ORDER = { "dialog", "search", "mail" }

local function autoButtonText(state, reasons)
  if state == "SCANNING" then return "Auto · scanning" end
  if state == "PAUSED" then
    for _, reason in ipairs(AUTO_PAUSE_ORDER) do
      if reasons[reason] then return "Auto · paused: " .. AUTO_PAUSE_LABEL[reason] end
    end
  end
  return "Auto" -- OFF, IDLE, WAITING, or PAUSED with only ah/tab reasons
end

-- Re-derives the Auto control's label/on-off look/pulse from the machine's own State()/
-- PauseReasons() -- called after every feedAuto() input and once per Tick (see the
-- autoScanTicker set up in GC.Sniper.OnAuctionHouseShow), so the button can never show a
-- state the machine itself has already moved past. Two overlapping buttons (frame.autoBtnOff
-- ghost / frame.autoBtnOn primary, built in createFrame), not one button whose colors get
-- poked at runtime -- Theme.Button's own hover-brighten closures capture their variant's
-- base/hover colors at construction time (see Theme.lua's T.Button), so repainting a single
-- button's `.bg` here would just get stomped by the very next OnEnter/OnLeave. Swapping which
-- of two correctly-built buttons is shown sidesteps that entirely, and keeps the control
-- clickable in both states (a real :Disable() would also block the click that's supposed to
-- turn it back on).
--
-- `targetFrame` (fix round 1, M1): createFrame calls this with its own local `f` right
-- before returning, since the module-level `frame` upvalue isn't assigned until AFTER
-- createFrame() returns (see GC.Sniper.Toggle()/OnAuctionHouseShow's `frame = frame or
-- createFrame()`) -- without this the very first Auto label paint would have to wait for a
-- later feedAuto/Tick instead of reflecting the freshly-built window immediately. Every other
-- caller (the ticker, feedAuto) omits it and falls back to the module-level `frame`.
refreshAutoButton = function(targetFrame)
  local f = targetFrame or frame
  if not f or not f.autoBtnOn then return end
  local state = autoScan:State()
  local on = state ~= "OFF"
  if f.autoBtnOn.lastOn ~= on then
    f.autoBtnOn.lastOn = on
    if on then
      f.autoBtnOff:Hide()
      f.autoBtnOn:Show()
    else
      f.autoBtnOn:Hide()
      f.autoBtnOff:Show()
    end
  end

  -- (fix round 1, I5) Pulse Play/Stop must run regardless of `on` -- previously this sat
  -- AFTER the off-state early return below, so toggling Auto off (or any other transition
  -- straight out of SCANNING) left the animation silently playing forever on a now-hidden
  -- button instead of being Stop()'d.
  local shouldPulse = (state == "SCANNING")
  if shouldPulse and not f.autoBtnOn.pulsing then
    f.autoBtnOn.pulsing = true
    f.autoBtnOn.pulse:Play()
  elseif not shouldPulse and f.autoBtnOn.pulsing then
    f.autoBtnOn.pulsing = false
    f.autoBtnOn.pulse:Stop()
    f.autoBtnOn:SetAlpha(1)
  end

  if not on then return end -- the off button's label never changes ("Auto") -- nothing else to update

  local text = autoButtonText(state, autoScan:PauseReasons())
  if f.autoBtnOn.lastText ~= text then
    f.autoBtnOn:SetLabel(text)
    f.autoBtnOn.lastText = text
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
-- Purchase flow. Clicking a row's Check button never buys anything itself -- it opens the
-- single reusable confirmation dialog (createDialog/openDialog below), which shows the
-- immutable decision facts and takes every further click in the sequence on ITS OWN primary
-- button. Both full-scan aggregates and realm items stay Check-only in v1. A live commodity
-- decision must be SAFE before the dialog can start, then it waits for
--                COMMODITY_PRICE_UPDATED -> dialog Confirm (ConfirmCommoditiesPurchase).
-- Stage machine (row.purchaseStage): nil (idle) -> "requerying" (stale-deal live requote in
-- flight, no purchase call yet) -> "ready" (dialog open, primary enabled, still no purchase
-- call) -> "buying" (StartCommoditiesPurchase issued) ->
-- "confirm"/"requote" (quote landed, awaiting the explicit Confirm click) -> "confirming"
-- (ConfirmCommoditiesPurchase issued) -> nil once resolved.
-- Every protected C_AuctionHouse purchase call is reached ONLY from onDialogPrimaryClick, the dialog's own
-- primary button's OnClick closure — never from an event or a timer. Event handlers and
-- timeouts only ever update dialog text or enable/disable its buttons; only ONE commodity
-- purchase may be in flight at a time.
-- Fix 2: the dialog's Quantity box/quick-fill buttons (commodities only) re-evaluate the deal
-- for a player-chosen qty (applyChosenQty) ONLY while row.purchaseStage == "ready" -- every
-- other stage above has already committed to (or is walking back from) a specific qty via a
-- live purchase call, so the controls are disabled/greyed everywhere else (see refreshQtyRow,
-- called from every stage transition below).
-- ---------------------------------------------------------------------------

-- Every stage that touches the primary button goes through here, so its colour can never be
-- left red from a previous requote. Gold is the dialog's own default text colour
-- (Theme.Button's "primary" text color is dark-on-gold; this only overrides for the
-- red Confirm state and back).
--
-- Final fix wave (item 4): the color write is skipped while the button is DISABLED --
-- previously this ran unconditionally, so e.g. armLoudConfirm's Disable() immediately followed
-- by setPrimaryLabel("Confirm", 1, 0.35, 0.35) overwrote Theme.Button's own OnDisable dim
-- (fgDim text -- Theme.lua) with bright red text on a button the player can't yet click,
-- defeating the "this isn't clickable" signal. Text (the label itself) always updates
-- regardless -- only the color write is gated. Theme.Button's OnEnable (Theme.lua) already
-- reapplies the variant's own default text color on re-enable, so a call site that enables the
-- button and THEN calls setPrimaryLabel with a color override (e.g. armLoudConfirm's own timer
-- callback, or the requote Confirm branch) still lands the intended color -- IsEnabled()
-- is true by the time this runs, so the write goes through same as before.
local function setPrimaryLabel(text, r, g, b)
  dialog.primaryBtn:SetLabel(text)
  if not dialog.primaryBtn:IsEnabled() then return end
  dialog.primaryBtn.text:SetTextColor(r or 0.05, g or 0.05, b or 0.06)
end

local function hideRequoteBanner()
  if not dialog then return end
  dialog.banner:Hide()
  dialog:SetHeight(dialog.baseHeight)
end

local function showRequoteBanner(head, detail)
  dialog.banner.head:SetText(head)
  dialog.banner.detail:SetText(detail)
  dialog:SetHeight(dialog.baseHeight + REQUOTE_BANNER_HEIGHT)
  dialog.banner:Show()
end

-- Refuses the confirming click for REQUOTE_ARM_SECONDS so a click already on its way when the
-- alarm fired can't land on it. Red-and-disabled reads as deliberate on its own; there is no
-- countdown number in the label (a dropped earlier version ticked on a 0.5s interval over a
-- 1.5s window, which reads as three seconds -- "(3) -> (2) -> (1)" -- for a wait that isn't).
--
-- Invariant: a stale countdown must never repaint a button some other path has taken
-- ownership of. Two independent things hold that together: armLoudConfirm bumps the token
-- every time it arms a NEW countdown, which is what lets an older one notice a fresher one has
-- since taken over (needed because two consecutive loud requotes both leave row.purchaseStage
-- at "requote" -- the stage alone can't tell them apart); every OTHER path that moves the row
-- off "requote" entirely (armReady back to "ready", a resolved purchase, an abort) is instead
-- caught by the timer's own `row.purchaseStage ~= "requote"` check, no token bump required.
local requoteArmToken = 0
local function armLoudConfirm(row)
  requoteArmToken = requoteArmToken + 1
  local token = requoteArmToken

  dialog.primaryBtn:Disable()
  setPrimaryLabel("Confirm", 1, 0.35, 0.35)

  C_Timer.After(REQUOTE_ARM_SECONDS, function()
    if token ~= requoteArmToken then return end
    if not dialog or dialog.row ~= row or row.purchaseStage ~= "requote" then return end
    dialog.primaryBtn:Enable()
    setPrimaryLabel("Confirm", 1, 0.35, 0.35)
  end)
end

-- Sets the dialog's status line text and color in one call; color defaults to plain white so
-- callers only pass r/g/b for an accent (green/red) message.
local function setDialogStatus(text, r, g, b)
  if not dialog then return end
  dialog.status:SetText(text or "")
  dialog.status:SetTextColor(r or 1, g or 1, b or 1)
end

-- Item icon + quality-colored name + qty suffix + tier chip, mirroring setRowDeal's async
-- load pattern but targeting the dialog's own widgets. dialog.deal (not row.deal) is the
-- identity guard here since the dialog can outlive the row being reassigned.
local function setDialogHeader(deal, decision)
  local color = Theme.tier[deal.tier] or Theme.tier.WATCH
  dialog.tierChip:SetLabel(deal.tier, color)
  if deal.tier == "SUSPECT" then dialog.suspectNote:Show() else dialog.suspectNote:Hide() end
  local quantity = decision and decision.quantity or nil
  local suffix = quantity and quantity > 0 and ("  x%d"):format(quantity) or ""
  dialog.nameText:SetText(("item %d"):format(deal.itemID) .. suffix)
  dialog.icon:SetTexture(nil)

  local item = Item:CreateFromItemID(deal.itemID)
  item:ContinueOnItemLoad(function()
    if dialog.deal ~= deal then return end -- dialog moved on before the async load finished
    dialog.icon:SetTexture(item:GetItemIcon())
    local quality = item:GetItemQuality()
    local qc = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
    local label = item:GetItemName() or ("item " .. deal.itemID)
    dialog.nameText:SetText((qc and qc:WrapTextInColorCode(label) or label) .. suffix)
  end)
end

local function displayDecisionAmount(value)
  return value and formatColumnAmount(value) or "—"
end

-- The diagnostic is evidence, not a purchase surface. Its height follows the rendered text so
-- every ordered reason remains visible at the player's current font scale. The buttons and
-- requote banner stay bottom-anchored; changing baseHeight moves that whole block together.
local function resizeDialogDiagnostics()
  local diagnostic = dialog.diagnosticText
  local measured = type(diagnostic.GetStringHeight) == "function" and diagnostic:GetStringHeight() or nil
  if type(measured) ~= "number" or measured <= 0 then measured = dialog.diagnosticMinimumHeight end
  local height = math.max(dialog.diagnosticMinimumHeight, math.ceil(measured))
  diagnostic:SetHeight(height)
  dialog.diagnosticHeight = height

  dialog.status:ClearAllPoints()
  dialog.status:SetPoint("TOPLEFT", diagnostic, "BOTTOMLEFT", 0, -Theme.pad.xs)
  dialog.status:SetPoint("RIGHT", -Theme.pad.m, 0)
  dialog.baseHeight = dialog.fixedHeight + dialog.diagnosticGaps + height
  local bannerVisible = dialog.banner and dialog.banner:IsShown()
  dialog:SetHeight(dialog.baseHeight + (bannerVisible and REQUOTE_BANNER_HEIGHT or 0))
end

-- Forward declarations for the quantity controls. Their definitions are intentionally below
-- the purchase state machine, but every authoritative decision stamp must refresh them.
local refreshQtyRow
local updateBuyAffordance

-- The dialog is a projection of the immutable decision snapshot, not another pricing model.
-- The only raw market number is explicitly labelled as a reference; every buy-facing number
-- comes from SniperDecision's live-book calculation.
local function stampDialogFromDecision(deal, decision)
  if not dialog then return end
  local market = marketForDecision(deal.itemID)
  local quantity = decision.quantity or 0
  local entryTotal = decision.entryTotal
  local average = entryTotal and quantity > 0 and math.floor(entryTotal / quantity) or nil
  local sourceAge = market.sourceAt and math.max(0, time() - market.sourceAt) or nil
  local firstReason = decision.reasons and decision.reasons[1] or "live_verification_required"

  local publicStatus = decision.status or "WATCH"
  local computedStatus = decision.computedStatus or publicStatus
  local diagnosticReasons = table.concat(decision.reasons or {}, ", ")
  if decision.computedStatus == "SAFE" and publicStatus == "WATCH" then
    dialog.decisionStatusText:SetText("WATCH (computed SAFE)")
  else
    dialog.decisionStatusText:SetText(publicStatus)
  end
  dialog.diagnosticText:SetText(("computed=%s public=%s buyable=%s reasons=%s"):format(
    computedStatus, publicStatus, decision.buyable and "yes" or "no",
    diagnosticReasons ~= "" and diagnosticReasons or "none"))
  resizeDialogDiagnostics()
  dialog.stampedUnit = average
  dialog.stampedTotal = entryTotal
  if dialog.qtyBox and quantity > 0 then dialog.qtyBox.editBox:SetText(tostring(quantity)) end
  dialog.unitPriceText:SetText(displayDecisionAmount(average))
  dialog.totalCostText:SetText(displayDecisionAmount(entryTotal))
  dialog.exitUnitText:SetText(displayDecisionAmount(decision.exitUnit))
  dialog.profitText:SetText(displayDecisionAmount(decision.stressProfit))
  dialog.mvText:SetText(displayDecisionAmount(market.marketValue))
  dialog.soldText:SetText(market.soldPerDay and ("%.1f"):format(market.soldPerDay) or "—")
  dialog.sellThroughText:SetText(market.sellThroughBps and ("%.1f%%"):format(market.sellThroughBps / 100) or "—")
  dialog.sourceAgeText:SetText(sourceAge and ("%ds"):format(sourceAge) or "—")
  dialog.reasonText:SetText(firstReason)
  if decision.status == "SAFE" then
    dialog.profitText:SetTextColor(0.25, 0.85, 0.25)
  else
    dialog.profitText:SetTextColor(1, 0.3, 0.3)
  end
  dialog.mvNote:Hide()
  if refreshQtyRow then refreshQtyRow() end
end

local function copyReasons(reasons)
  local copy = {}
  for i = 1, #(reasons or {}) do copy[i] = reasons[i] end
  return copy
end

local function purchaseFacts(deal, quote)
  local decision = quote and quote.decision
  if not decision or decision.status ~= "SAFE" or not decision.buyable
      or quote.itemID ~= deal.itemID or quote.quantity ~= decision.quantity
      or type(quote.total) ~= "number" or quote.total <= 0 then
    return nil
  end
  local market = quote.market or {}
  return {
    itemID = deal.itemID,
    quantity = quote.quantity,
    total = quote.total,
    unitDisplay = math.floor(quote.total / quote.quantity),
    decisionVersion = decision.version,
    decisionStatus = decision.status,
    decisionReasons = copyReasons(decision.reasons),
    stressUnit = decision.exitUnit,
    expectedProfit = decision.stressProfit,
    recommendedQuantity = decision.quantity,
    sourceAt = market.sourceAt,
  }
end

-- A confirmed commodity attempt can outlive the AH UI. This item-keyed, non-interactive
-- status keeps uncertain detached terminals visible to diagnostics/chat without pinning or
-- mutating a pooled row that may now belong to another Check.
local detachedCommodityStatus = {}
GC.Sniper.detachedCommodityStatus = detachedCommodityStatus

local function consumePurchasedDeal(deal)
  if deals[deal.itemID] == deal then deals[deal.itemID] = nil end
  -- A full-scan buy resolves against the LIVE deal finishRequery swapped in, not the original
  -- stale scan entry. Drop that consumed listing so it cannot reappear on the next refresh.
  for i = #scanDeals, 1, -1 do
    if scanDeals[i].itemID == deal.itemID then table.remove(scanDeals, i) end
  end
end

local function recordPurchaseFacts(deal, purchase)
  local session = GC.Sniper.session
  session.buys = session.buys + 1
  session.spent = session.spent + purchase.total
  session.estProfit = session.estProfit + purchase.expectedProfit
  local now = time()
  -- `purchase` is the one immutable final-quote object shared by both stores.
  local context = GC.Ledger.Context()
  local ledgerEntry = GC.Ledger.RecordSniperBuy(deal, purchase, context, now)
  GC.Data.RecordFlip(deal, purchase, now)
  if GC.Acquisitions and GC.Acquisitions.RecordGoldCap then
    GC.Acquisitions.RecordGoldCap(deal, purchase, context, now, ledgerEntry and ledgerEntry.key or nil)
  end
  updateSellTabLabel()
  consumePurchasedDeal(deal)
end

local function reportDetachedCommodity(pending, note)
  local deal = pending and pending.deal
  local itemID = (deal and deal.itemID) or (pending and pending.itemID)
  if not itemID then return end
  detachedCommodityStatus[itemID] = {
    token = pending.token,
    deal = deal,
    quote = pending.quote,
    note = note,
  }
  local text = ("item %d: %s"):format(itemID, note)
  if frame then frame.status:SetText(text) end
  if GC.Print then GC.Print(text) end
end

local function settleDetachedConfirmed(pending, terminal)
  local deal = pending and pending.deal
  if terminal == "success" then
    local purchase = deal and purchaseFacts(deal, pending.quote)
    if purchase then
      recordPurchaseFacts(deal, purchase)
      reportDetachedCommodity(pending, ("bought %d x item %d after AH close"):format(
        purchase.quantity, deal.itemID))
      return
    end
    reportDetachedCommodity(pending, "purchase total unavailable — inspect mailbox")
    return
  end
  if terminal == "unavailable" then
    reportDetachedCommodity(pending, "purchase total unavailable — inspect mailbox")
  else
    reportDetachedCommodity(pending, "confirmed commodity purchase failed after AH close")
  end
end

local function confirmedAttemptOwnsRow(pending)
  local row = pending and pending.row
  local deal = pending and pending.deal
  return row and deal and row.purchaseStage == "confirming"
    and row.purchaseToken == pending.token
    and row.purchaseDeal == deal
    and row.deal == deal
    and row.quoteSnapshot == pending.quote
    and pending.itemID == deal.itemID
end

resolvePurchase = function(row, success, note, purchase, purchaseDeal)
  -- A confirmed commodity attempt can outlive its visible row across an AH close. Its deal is
  -- captured at the hardware Confirm click and must win over a row that was reset/repooled.
  local deal = purchaseDeal or row.purchaseDeal or row.deal
  if deal then
    activeItemID[deal.itemID] = nil
    if deal.isCommodity then
      if commodityPurchase and commodityPurchase.row == row then commodityPurchase = nil end
    elseif deal.auctionID then
      pendingAuction[deal.auctionID] = nil
    end
    if success then
      if not purchase then
        -- There is no trustworthy cost basis without the final server quote. Keep the row
        -- frozen for mailbox inspection rather than inventing a total from a search result.
        row.purchaseStage = "frozen"
        row.purchaseDeal = nil
        row.decisionSnapshot = nil
        row.quoteSnapshot = nil
        -- `refreshRows()` only preserves pinned rows. Keep this unresolved server success
        -- visible (and its discovery deal excluded from a second attempt) until AH close or
        -- the player inspects the mailbox, rather than letting the pool repurpose it.
        activeItemID[deal.itemID] = true
        if dialog and dialog.row == row then
          dialog.primaryBtn:Disable()
          setDialogStatus("purchase total unavailable — inspect mailbox", 1, 0.3, 0.3)
        end
        if frame then frame.status:SetText("purchase total unavailable — inspect mailbox") end
        refreshRows()
        return
      end
      recordPurchaseFacts(deal, purchase)
    end
  end

  row.purchaseStage = nil
  row.purchaseDeal = nil
  row.decisionSnapshot = nil
  row.quoteSnapshot = nil
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
local function abortRowPurchase(row, note, retainLivePause)
  local deal = row.purchaseDeal or row.deal
  local pending = commodityPurchase
  local requeryAttempt
  if pending and pending.row == row and pending.confirmed then
    -- Confirm has already reached Blizzard. Esc/OnHide must not cancel, clear, or unpin that
    -- ownership; only a terminal event (or the retained close tombstone) may settle it.
    return
  end
  if deal then
    local attempt = awaitingRequery[deal.itemID]
    if attempt and attempt.row == row then
      requeryAttempt = attempt
      awaitingRequery[deal.itemID] = nil
      awaitingKeyInfo[deal.itemID] = nil
      pendingRequerySend[deal.itemID] = nil
      if attempt.sent then requeryDraining[deal.itemID] = attempt end
    else
      local wait = GC.Sniper._drainWaitRequery[deal.itemID]
      if wait and wait.row == row and wait.deal == deal then
        requeryAttempt = wait
        GC.Sniper._drainWaitRequery[deal.itemID] = nil
      end
      awaitingKeyInfo[deal.itemID] = nil
      pendingRequerySend[deal.itemID] = nil
    end
  end
  if pending and pending.row == row and not pending.cancelRequested then
    -- CancelCommoditiesPurchase is non-protected; Esc/OnHide must settle an opened server
    -- session too, otherwise a hidden dialog can leave a commodity transaction stranded.
    C_AuctionHouse.CancelCommoditiesPurchase()
    pending.cancelRequested = true
  end
  drainCommodityPurchase(row)
  resolvePurchase(row, false, note)
  if not retainLivePause then GC.Sniper._ResumePausedLiveRequery(requeryAttempt) end
end

-- Fix 3 (no flash-open-then-close): a listing that's already gone by the time the dialog would
-- show its numbers used to close the dialog within the same click that opened it -- worse with
-- the Task 8 pre-warm cache, where a stale-but-fresh-looking cache can resolve to nil the
-- instant openDialog consumes it. The only explanation landed in the tiny main-window status
-- line, which is nowhere near where the player's eye was. This clears the SAME purchase-pin
-- bookkeeping resolvePurchase's failure path clears (activeItemID, commodityPurchase/
-- pendingAuction) -- deliberately NOT crediting the session, same as resolvePurchase(row,
-- false, ...) never does -- but when the dialog IS showing THIS row, it leaves the dialog up
-- with an explanatory status instead of hiding it: primary button reads "Gone" and stays
-- disabled, Cancel is relabeled "Close", and dialog.row is cleared so the row itself is free to
-- be reused by the next refreshRows() while the dialog keeps talking about the deal that just
-- died. If the dialog is on some OTHER row (or isn't open at all), there is nothing to show --
-- today's silent bookkeeping-only cleanup is exactly right there.
--
-- Verified both of createDialog's own paths still work with dialog.row left nil afterward:
-- (1) OnHide (`d:SetScript("OnHide", ...)` below) reads `local row = dialog.row` and does
-- `if not row then return end` BEFORE calling abortRowPurchase -- so a hardware click on the
-- relabeled "Close" button (still just `dialog:Hide()`) triggers OnHide, which no-ops past that
-- guard instead of double-aborting a purchase that's already fully cleared. (2) onBuyClick's
-- reuse/steal-back checks are both `dialog.row == row` and `dialog and dialog.row` (truthy) --
-- with dialog.row nil neither fires, so a Buy click on ANY row (the same one or a different
-- one) falls straight through to openDialog(row, deal), the ordinary open path.
local function showGoneState(row, message)
  local deal = row.purchaseDeal or row.deal
  if deal then
    activeItemID[deal.itemID] = nil
    if deal.isCommodity then
      if commodityPurchase and commodityPurchase.row == row then commodityPurchase = nil end
    elseif deal.auctionID then
      pendingAuction[deal.auctionID] = nil
    end
  end
  row.purchaseStage = nil
  row.purchaseDeal = nil

  if dialog and dialog.row == row then
    dialog.row = nil
    dialog.primaryBtn:Disable()
    setPrimaryLabel("Gone")
    setDialogStatus(message, 1, 0.3, 0.3)
    dialog.cancelBtn:SetLabel("Close")
    -- Fix 2 x Fix 3 (review): the row just left its purchase stage, so the Quantity box/
    -- quick-fill must grey out too -- without this they'd keep whatever editable state the
    -- "ready" stage last painted, on a dialog whose deal is already dead.
    if refreshQtyRow then refreshQtyRow() end
  end
end

-- Expires a quote nobody clicked within ARM_TIMEOUT_SECONDS -- but never dead-ends the
-- player: the primary button flips to "Refresh" (stage "expired"), whose click re-runs the
-- live requery for fresh numbers. Refresh is NOT a purchase call, so looping through
-- expired -> Refresh -> ready any number of times stays compliant.
local function scheduleArmTimeout(row, deal, decision)
  C_Timer.After(ARM_TIMEOUT_SECONDS, function()
    if row.purchaseStage == "ready" and row.deal == deal and row.decisionSnapshot == decision
        and dialog and dialog.row == row then
      row.purchaseStage = "expired"
      dialog.primaryBtn:Enable()
      setPrimaryLabel("Refresh")
      setDialogStatus("quote expired -- Refresh to re-check the price", 1, 0.82, 0)
      if refreshQtyRow then refreshQtyRow() end -- Fix 2: "expired" is not "ready" -- box/quick-fill grey out until Refresh re-arms
    end
  end)
end

-- Puts the dialog into the pre-purchase-call "ready" state: numbers reflect the best price
-- known so far (a watchlist snapshot, or the live quote finishRequery just landed), primary
-- button reads "Buy" and is enabled, and the ARM_TIMEOUT clock starts. Shared by openDialog
-- (non-stale deals arm immediately) and finishRequery (stale deals arm once the live requery
-- resolves) so there is exactly one place that flips this stage on.
local function armReady(row, deal, decision, levels)
  if not decision or not decision.buyable or decision.status ~= "SAFE" or not deal.isCommodity then
    return
  end
  row.purchaseStage = "ready"
  row.purchaseDeal = nil
  row.decisionSnapshot = decision
  row.quoteSnapshot = nil
  activeItemID[deal.itemID] = true
  dialog.primaryBtn:Enable()
  hideRequoteBanner()
  setPrimaryLabel("Buy")
  dialog.bookLevels = levels
  setDialogHeader(deal, decision)
  stampDialogFromDecision(deal, decision)
  -- The dialog's OWN status must flip here -- the requery path otherwise leaves its
  -- "checking live price..." text up even though the button just enabled, and the player
  -- reads the stale text right up until the quote expires.
  setDialogStatus("price confirmed -- click Buy to purchase", 0.25, 0.85, 0.25)
  scheduleArmTimeout(row, deal, decision)
  if updateBuyAffordance then updateBuyAffordance() end
end

local function armCheck(row, deal, decision, note, clearSnapshots)
  activeItemID[deal.itemID] = nil
  row.purchaseStage = "check"
  row.purchaseDeal = nil
  if clearSnapshots then
    row.decisionSnapshot = nil
    row.quoteSnapshot = nil
    if dialog then dialog.bookLevels = nil end
  else
    row.decisionSnapshot = decision
    row.quoteSnapshot = nil
  end
  if dialog and dialog.row == row then
    dialog.primaryBtn:Enable()
    hideRequoteBanner()
    setPrimaryLabel("Check")
    setDialogHeader(deal, clearSnapshots and { status = "WATCH", reasons = { "requote_broke_safety" } } or decision)
    stampDialogFromDecision(deal, clearSnapshots and { status = "WATCH", reasons = { "requote_broke_safety" } } or decision)
  end
  setDialogStatus(note or "live verification required", 1, 0.82, 0)
  if frame then frame.status:SetText(note or "live verification required") end
end

-- The dialog keeps its book depth only as display/quantity context. Every approval and total
-- still comes from the immutable SniperDecision snapshot, never from this UI cache.
local function availableFromLevels(levels)
  local total = 0
  for _, level in ipairs(levels or {}) do total = total + (level.quantity or 0) end
  return total > 0 and total or nil
end

local function evaluateLiveCommodityDeal(itemID)
  local levels = driver.commodityBook(itemID)
  if not levels then return nil end
  local result = driver.commodityResult(itemID)
  return {
    isCommodity = true,
    levels = levels,
    avail = (result and result.avail) or availableFromLevels(levels),
    decision = evaluateLive(itemID, levels),
  }
end

-- Apply an authoritative live decision and preserve the same fetched depth for the quantity
-- controls. The decision remains the only purchase gate; `levels` never approves a buy alone.
local function applyRequeryResult(row, itemID, live)
  local deal = row.deal
  if not deal or deal.itemID ~= itemID then return end
  local decision = live and live.decision
  if decision then
    deal.isCommodity = live.isCommodity and true or false
    if live.avail then deal.avail = live.avail end
    if dialog then
      dialog.deal = deal
      dialog.bookLevels = live.levels
    end
    if live.isCommodity and decision.buyable then
      armReady(row, deal, decision, live.levels)
      if frame then frame.status:SetText("live safety confirmed -- click Buy to purchase") end
    else
      armCheck(row, deal, decision, decision.reasons[1] or "live_verification_required", false)
    end
  else
    showGoneState(row, "listing gone -- already bought out or price changed")
    if deals[itemID] then deals[itemID] = nil end
    for i = #scanDeals, 1, -1 do
      if scanDeals[i].itemID == itemID then table.remove(scanDeals, i) end
    end
    if frame then frame.status:SetText("gone / price changed") end
  end
  refreshRows()
end

-- Same BUY_TIMEOUT window as before (covers both PlaceBid and StartCommoditiesPurchase
-- waiting on their respective completion/quote events), but freezes the dialog with an
-- explanatory status instead of auto-resolving the purchase as failed: PlaceBid's completion
-- event is UNVERIFIED to always fire, so silently unpinning here could let the player
-- re-attempt a buy whose bid may in fact still land. The row stays pinned until Cancel.
local function scheduleBuyTimeout(row, deal, token)
  C_Timer.After(BUY_TIMEOUT_SECONDS, function()
    if row.purchaseStage == "buying" and row.purchaseDeal == deal and row.purchaseToken == token
        and (not deal.isCommodity or (commodityPurchase and commodityPurchase.row == row
          and commodityPurchase.token == token))
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
-- watchlist deal) or gives up gracefully (Fix 3: showGoneState -- the dialog stays open with
-- a "Gone" explanation instead of flashing shut, row unpinned). No C_AuctionHouse purchase
-- call is ever reached from this path -- only
-- PlaceBid/StartCommoditiesPurchase/ConfirmCommoditiesPurchase inside onDialogPrimaryClick
-- complete a purchase, unchanged.
-- ---------------------------------------------------------------------------

-- Issues the fresh live query for a requery, but ONLY when the throttle system is ready.
-- SendSearchQuery silently no-ops while IsThrottledMessageSystemReady() is false -- which it
-- routinely is for a beat right after a Full Scan (the scan's own browse paging saturates
-- the throttle) -- so if we're not ready, park the itemID in pendingRequerySend and let
-- GC.Sniper.OnThrottleReady flush it. The 8s requery timeout remains the ultimate fallback.
local function isCurrentRequeryAttempt(attempt)
  return attempt and awaitingRequery[attempt.itemID] == attempt
    and attempt.row.purchaseStage == "requerying"
    and attempt.row.purchaseToken == attempt.token
    and attempt.row.deal == attempt.deal
end

local function issueRequerySearch(attempt)
  if not isCurrentRequeryAttempt(attempt) then return end
  if driver.isReady() then
    attempt.sent = true
    driver.sendSearch(attempt.itemID)
  else
    pendingRequerySend[attempt.itemID] = attempt
  end
end

local function finishRequery(attempt, liveDeal)
  if not isCurrentRequeryAttempt(attempt) then return end
  local itemID = attempt.itemID
  awaitingRequery[itemID] = nil
  awaitingKeyInfo[itemID] = nil
  pendingRequerySend[itemID] = nil
  applyRequeryResult(attempt.row, itemID, liveDeal)
  GC.Sniper._ResumePausedLiveRequery(attempt)
end

local function scheduleRequeryTimeout(attempt)
  C_Timer.After(REQUERY_TIMEOUT_SECONDS, function()
    if isCurrentRequeryAttempt(attempt) then
      -- The server might still send an untagged result after this timeout. Fence it before
      -- returning the row to Check, so it cannot become a quote for a subsequent same-item
      -- click. The player can retry once that old result is consumed (or the AH is reset).
      local itemID = attempt.itemID
      awaitingRequery[itemID] = nil
      awaitingKeyInfo[itemID] = nil
      pendingRequerySend[itemID] = nil
      if attempt.sent then requeryDraining[itemID] = attempt end
      applyRequeryResult(attempt.row, itemID, nil)
      GC.Sniper._ResumePausedLiveRequery(attempt)
    end
  end)
end

local function startRequery(row, deal)
  local itemID = deal.itemID
  local draining = requeryDraining[itemID]
  if draining or awaitingRequery[itemID] then
    -- A prior sent search for this item must drain before any new authoritative Check can
    -- exist. Give only that drain case a distinct wait owner; the old result will clear ONLY
    -- this wait, never arm this row or revive a newer Check.
    if draining then
      row.purchaseToken = (row.purchaseToken or 0) + 1
      local wait = { row = row, itemID = itemID, token = row.purchaseToken, deal = deal, draining = draining }
      GC.Sniper._drainWaitRequery[itemID] = wait
      if GC.Sniper._pausedLiveRequery then GC.Sniper._pausedLiveRequery = wait end
    end
    row.purchaseStage = "check"
    row.purchaseDeal = nil
    activeItemID[itemID] = nil
    if dialog and dialog.row == row then
      dialog.primaryBtn:Enable()
      setPrimaryLabel("Check")
    end
    setDialogStatus("waiting for previous search result to settle", 1, 0.82, 0)
    if frame then frame.status:SetText("waiting for previous search result to settle") end
    return
  end
  row.purchaseToken = (row.purchaseToken or 0) + 1
  local attempt = { row = row, itemID = itemID, token = row.purchaseToken, deal = deal, sent = false }
  -- Stop Live before registering or sending the authoritative Check. Init.lua dispatches the
  -- scanner's throttle-ready hook first, so leaving it active even for this one turn lets it
  -- consume the only slot and starve a parked Check until it falsely times out as Gone.
  if GC.Sniper._pausedLiveRequery then
    -- A replacement Check is already taking over a paused dialog session. Preserve the
    -- original user's Live intent but hand ownership to the new immutable attempt.
    GC.Sniper._pausedLiveRequery = attempt
  elseif scanning then
    stopScanning()
    GC.Sniper._pausedLiveRequery = attempt
  end
  row.purchaseStage = "requerying"
  row.purchaseDeal = nil
  activeItemID[itemID] = true
  if refreshQtyRow then refreshQtyRow() end -- Fix 2: "requerying" is not "ready" -- box/quick-fill grey out until the live requote lands
  if frame then frame.status:SetText("checking live price...") end

  awaitingRequery[itemID] = attempt
  scheduleRequeryTimeout(attempt)

  -- Guard against the item key not being cached: GetItemKeyInfo (via driver.getKeyInfo) can
  -- return nil for an itemID nothing has queried yet this session. When it does, wait for
  -- ITEM_KEY_ITEM_INFO_RECEIVED (GC.Sniper.OnItemKeyInfo below) and retry once from there,
  -- rather than calling driver.sendSearch on a key WoW hasn't resolved yet.
  if driver.getKeyInfo(itemID) then
    issueRequerySearch(attempt)
  else
    awaitingKeyInfo[itemID] = attempt
  end
end

-- ---------------------------------------------------------------------------
-- Task 8: hover pre-warm of the buy requery (spec §4). Row OnEnter (see createRow's OnEnter
-- below) calls maybeStartPrewarm(self.deal) on every hover; this issues the SAME live query
-- startRequery would for a `.stale` deal, but into resolvePrewarm instead of finishRequery --
-- the result lands on deal.prewarm and NOTHING here ever opens, arms, or otherwise touches the
-- row/dialog. openDialog (below) is the only consumer: a fresh (<= PREWARM_TTL_SECONDS old)
-- deal.prewarm lets it skip straight to applyRequeryResult instead of calling startRequery, so
-- the dialog opens already armed. A stale/absent cache falls back to today's flow unchanged.
-- ---------------------------------------------------------------------------

-- Deliberately does NOT park behind pendingRequerySend the way issueRequerySearch does: a
-- pre-warm that missed its throttle window is worth nothing later that a fresh one issued on
-- the next hover wouldn't do better, and letting it queue would risk a parked pre-warm send
-- winning a throttle slot the T7 OnThrottleReady flush order reserves for scan traffic /
-- pendingRequerySend first -- simplest and safest is: not ready right now -> skip, hovering
-- again retries.
local function maybeStartPrewarm(deal)
  if not deal or not deal.stale then return end -- only the two-click full-scan flow ever needs this
  if not ahOpen then return end -- fix round 1 M-3: no AH session live (window can stay open/re-shown via /goldcap with leftover deals after AH close) -- nothing to query against
  if deal.prewarm and (GetTime() - deal.prewarm.at) <= PREWARM_TTL_SECONDS then return end -- fix round 1 I-3: re-hovering a deal with a still-fresh cache has nothing to gain from a second query
  if activeItemID[deal.itemID] then return end -- a purchase (or its own live dialog requery) is already in flight for this item
  -- Final fix wave (item 2), coordinator ruling restoring spec §4: gate narrowed from
  -- GC.Sniper.IsBusy() (which also covered a paging Full Scan) to purchase traffic ONLY --
  -- next(activeItemID) ~= nil is true while ANY purchase is mid-flight server-side (armed/
  -- requerying/buying/confirming on some row, not necessarily this one), so a pre-warm still
  -- never competes with a real buy requery on the shared throttled message system. Pre-warm
  -- MAY fire during a scan now: it's ready-gated (driver.isReady() below, plus the "one
  -- pre-warm in flight globally" slot), so at worst it costs the scan a single browse-page
  -- throttle slot for one cycle -- a one-cycle pagination delay, not starvation.
  if next(activeItemID) ~= nil then return end
  if prewarmAttempt then return end -- one pre-warm in flight globally
  if not driver.isReady() then return end -- never parks -- see comment above

  local itemID = deal.itemID
  if requeryDraining[itemID] then return end -- an old untagged result must drain first
  -- Same item-key-not-cached guard startRequery uses, but pre-warm just skips instead of
  -- chasing ITEM_KEY_ITEM_INFO_RECEIVED -- this is a best-effort warm, not a purchase the
  -- player is blocked on; the dialog's own startRequery fallback still does the real,
  -- patient wait if the player clicks Buy before the key is ever resolved.
  if not driver.getKeyInfo(itemID) then return end

  prewarmToken = prewarmToken + 1
  local attempt = { itemID = itemID, token = prewarmToken, deal = deal, sent = true }
  prewarmAttempt = attempt
  driver.sendSearch(itemID)

  -- Ultimate fallback so a pre-warm that never gets a matching event (or one whose deal was
  -- superseded before it landed) can't wedge the "one in flight globally" slot shut forever.
  C_Timer.After(REQUERY_TIMEOUT_SECONDS, function()
    if prewarmAttempt == attempt then
      prewarmAttempt = nil
      requeryDraining[itemID] = attempt
    end
  end)
end

-- The pre-warm result landing (or failing to materialize into a live deal): stamps
-- deal.prewarm on the EXACT deal table maybeStartPrewarm captured, and releases the "one in
-- flight" slot. `data` mirrors exactly what finishRequery's own `liveDeal` argument would be
-- for the same event -- nil means "gone / price changed", handled identically by
-- applyRequeryResult whenever this cache gets consumed. Never touches row/dialog/
-- activeItemID/purchaseStage -- that is the entire point of this being a separate path from
-- finishRequery.
local function resolvePrewarm(itemID, data)
  local attempt = prewarmAttempt
  if not attempt or attempt.itemID ~= itemID then return end
  local deal = attempt.deal
  prewarmAttempt = nil
  if deal then
    deal.prewarm = { data = data, at = GetTime(), token = attempt.token }
  end
end

-- Router functions the Init.lua event frame dispatches into.

function GC.Sniper.OnItemKeyInfo(itemID)
  local attempt = awaitingKeyInfo[itemID]
  if not attempt then return end -- not something Task-3 requery is waiting on for this item
  awaitingKeyInfo[itemID] = nil
  if not isCurrentRequeryAttempt(attempt) then return end

  if driver.getKeyInfo(itemID) then
    issueRequerySearch(attempt) -- retry: key is cached now; exact attempt owns the send
  else
    finishRequery(attempt, nil) -- still uncached after the retry -- give up gracefully
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

-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY handler: a parked authoritative Check always consumes
-- the next slot before any optional browse traffic. The Check has already stopped Live in
-- startRequery, so this works in watchlist mode without a scanner collision; returning after
-- the send also prevents a full-scan browse request from stealing the same ready turn.
function GC.Sniper.OnThrottleReady()
  for itemID, attempt in pairs(pendingRequerySend) do
    pendingRequerySend[itemID] = nil
    if isCurrentRequeryAttempt(attempt) then
      attempt.sent = true
      driver.sendSearch(itemID)
      return
    end
  end

  if pendingFullScanStart then
    pendingFullScanStart = false
    sendBrowseQuery(fullScanToken)
  elseif pendingBrowsePage then
    pendingBrowsePage = false
    sendBrowsePage(fullScanToken)
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

-- Task 9 fix round 1 (I4): one-line accessor over the existing `ahOpen` local (set true on
-- OnAuctionHouseShow, false on OnAuctionHouseClosed) -- GC.Sell's requestOwnedAuctions checks
-- this before ever calling C_AuctionHouse.QueryOwnedAuctions, so a stray owned-lots refresh
-- (e.g. the tab-show/ghost-Refresh paths firing after the player has already left the AH) can't
-- issue a query with no live session to answer it.
function GC.Sniper.IsAHOpen()
  return ahOpen
end

-- Shared by both the dialog-requery router branch and the Task 8 pre-warm branch below, so
-- the two paths always shape a search result into a "liveDeal" the exact same way -- a
-- deal.prewarm cache and a live finishRequery landing are indistinguishable to
-- applyRequeryResult by construction, not by coincidence.
local function evaluateLiveItemDeal(itemID)
  -- Realm/item auctions are discovery-only in v1. Evaluate them with no commodity book so the
  -- result visibly explains why it remains WATCH, and never construct a PlaceBid candidate.
  if not driver.itemResult(itemID) then return nil end
  return { isCommodity = false, decision = evaluateLive(itemID, nil) }
end

-- Both search-result events can carry EITHER consumer, BOTH, or neither: a dialog-open
-- requery (awaitingRequery[itemID]) and a hover pre-warm (prewarmAttempt.itemID == itemID) are
-- independent, separately-keyed waiters on the same underlying SendSearchQuery/
-- COMMODITY-equivalent traffic. openDialog retires the matching prewarm attempt for an itemID
-- starts a real purchase flow for it (see openDialog below), so in practice the two rarely
-- overlap -- but nothing here depends on that; each branch is a no-op when its own slot
-- doesn't match, regardless of what the other one does.
function GC.Sniper.OnItemSearchResults(itemID)
  if requeryDraining[itemID] then
    local draining = requeryDraining[itemID]
    requeryDraining[itemID] = nil
    GC.Sniper._FinishDrainWait(itemID, draining)
    return -- consume the old untagged result before any authoritative Check can restart
  end
  local attempt = awaitingRequery[itemID]
  local isPrewarm = prewarmAttempt and prewarmAttempt.itemID == itemID
  if not attempt and not isPrewarm then return end -- neither a Task-3 dialog requery nor a Task 8 pre-warm for this item (e.g. the watchlist scanner's own search)
  if attempt and not isCurrentRequeryAttempt(attempt) then
    -- A newer Check advanced the row token. Do not even inspect this old result: it belongs
    -- to no current attempt and must not stamp a live decision/cache by coincidence.
    awaitingRequery[itemID] = nil
    awaitingKeyInfo[itemID] = nil
    pendingRequerySend[itemID] = nil
    if not isPrewarm then return end
    attempt = nil
  end
  local liveDeal = evaluateLiveItemDeal(itemID)
  if attempt then finishRequery(attempt, liveDeal) end
  if isPrewarm then resolvePrewarm(itemID, liveDeal) end
end

function GC.Sniper.OnCommoditySearchResults(itemID)
  if requeryDraining[itemID] then
    local draining = requeryDraining[itemID]
    requeryDraining[itemID] = nil
    GC.Sniper._FinishDrainWait(itemID, draining)
    return -- consume the old untagged result before any authoritative Check can restart
  end
  local attempt = awaitingRequery[itemID]
  local isPrewarm = prewarmAttempt and prewarmAttempt.itemID == itemID
  if not attempt and not isPrewarm then return end -- neither a Task-3 dialog requery nor a Task 8 pre-warm for this item (e.g. the watchlist scanner's own search)
  if attempt and not isCurrentRequeryAttempt(attempt) then
    awaitingRequery[itemID] = nil
    awaitingKeyInfo[itemID] = nil
    pendingRequerySend[itemID] = nil
    if not isPrewarm then return end
    attempt = nil
  end
  local liveDeal = evaluateLiveCommodityDeal(itemID)
  if attempt then finishRequery(attempt, liveDeal) end
  if isPrewarm then resolvePrewarm(itemID, liveDeal) end
end

function GC.Sniper.OnPurchaseCompleted(auctionID)
  local row = pendingAuction[auctionID]
  if not row then return end
  local deal = row.purchaseDeal
  resolvePurchase(row, true, deal and ("sniped for " .. GetCoinTextureString(deal.unitPrice * deal.qty)) or "purchase complete")
end

function GC.Sniper.OnCommodityPriceUpdated(unitPrice, totalPrice)
  if commodityDraining then
    -- Price updates are non-terminal. Keep draining through every one, and re-send Cancel for
    -- a cancelled server session. A confirmed tombstone must never be cancelled after Confirm.
    if not commodityDraining.confirmed then C_AuctionHouse.CancelCommoditiesPurchase() end
    return
  end
  local pending = commodityPurchase
  local row = pending and pending.row
  if not row or pending.itemID == nil or pending.token == nil
      or row.purchaseToken ~= pending.token or row.purchaseStage == "confirming" then
    return -- a late event cannot take ownership of a newer row/token
  end
  local deal = row.purchaseDeal
  local decision = row.decisionSnapshot
  if not deal or deal.itemID ~= pending.itemID or not decision or not decision.buyable
      or decision.status ~= "SAFE" then
    return
  end
  pending.priceReceived = true

  local levels = driver.commodityBook(deal.itemID)
  local finalDecision = evaluateLive(deal.itemID, levels, decision.quantity, totalPrice)
  if not finalDecision.buyable or finalDecision.status ~= "SAFE" then
    -- Visual price-change thresholds are never economic approval. A 1-copper or sub-5%
    -- repriced order that breaks the fixed safety decision cancels immediately.
    C_AuctionHouse.CancelCommoditiesPurchase()
    pending.cancelRequested = true
    drainCommodityPurchase(row)
    armCheck(row, deal, nil, "requote_broke_safety — Check again", true)
    return
  end

  local market = marketForDecision(deal.itemID)
  row.quoteSnapshot = {
    token = pending.token,
    itemID = deal.itemID,
    quantity = decision.quantity,
    total = totalPrice,
    decision = finalDecision,
    market = { sourceAt = market.sourceAt },
  }
  if dialog and dialog.row == row then
    dialog.bookLevels = levels
    stampDialogFromDecision(deal, finalDecision)
  end

  local severity, ratio = GC.DealMath.RequoteSeverity(
    decision.entryTotal, totalPrice, REQUOTE_WARN_RATIO, REQUOTE_LOUD_RATIO)
  if severity == "none" then
    row.purchaseStage = "confirm"
    -- Fix 2: the server's own live quote can exceed what's in the player's bags even when the
    -- dialog's earlier stamp looked affordable (gold spent elsewhere mid-flow, or the quote
    -- simply landed higher than the last book read) -- Confirm must never be clickable against
    -- a purchase that would fail server-side anyway.
    local affordable = totalPrice <= GetMoney()
    if dialog and dialog.row == row then
      requoteArmToken = requoteArmToken + 1
      hideRequoteBanner()
      setPrimaryLabel("Confirm")
      if affordable then
        dialog.primaryBtn:Enable()
      else
        dialog.primaryBtn:Disable()
      end
      if refreshQtyRow then refreshQtyRow() end -- "confirm" is not "ready" -- box/quick-fill stay greyed out
    end
    if affordable then
      setDialogStatus(("quote %s -- click Confirm to buy"):format(GetCoinTextureString(totalPrice)))
      if frame then
        frame.status:SetText(("quote %s -- click Confirm to buy"):format(GetCoinTextureString(totalPrice)))
      end
    else
      setDialogStatus("not enough gold for this quote -- Cancel", 1, 0.3, 0.3)
      if frame then frame.status:SetText("not enough gold for this quote -- Cancel") end
    end
    return
  end

  row.purchaseStage = "requote"
  local detail = ("%s -> %s per unit    total %s -> %s"):format(
    formatColumnAmount(math.floor(decision.entryTotal / decision.quantity)), formatColumnAmount(unitPrice),
    formatColumnAmount(decision.entryTotal), formatColumnAmount(totalPrice))
  if dialog and dialog.row == row then
    if severity == "loud" then
      showRequoteBanner(("PRICE ROSE %.1fx"):format(ratio), detail)
      armLoudConfirm(row)
    else
      requoteArmToken = requoteArmToken + 1
      hideRequoteBanner()
      dialog.primaryBtn:Enable()
      setPrimaryLabel("Confirm", 1, 0.35, 0.35)
    end
    if refreshQtyRow then refreshQtyRow() end -- "requote" is not "ready" -- box/quick-fill stay greyed out
  end
  if severity == "loud" and GC.db and GC.db.settings and GC.db.settings.sniper.sound then
    PlaySound(SOUNDKIT.RAID_WARNING)
  end
  setDialogStatus(detail, 1, 0.3, 0.3)
  if frame then frame.status:SetText(("price rose %.1fx — still safe, confirm"):format(ratio)) end
end

function GC.Sniper.OnCommodityPriceUnavailable()
  if commodityDraining then
    local pending = commodityDraining
    commodityDraining = nil
    if pending.confirmed then
      -- This tombstone survived AH close. Its row may already be repooled, so freeze/report
      -- only detached item facts; never estimate a total or mutate an unrelated new Check.
      settleDetachedConfirmed(pending, "unavailable")
    end
    return -- terminal event for the cancelled/closed attempt, never the next one
  end
  local pending = commodityPurchase
  if not pending then return end
  if pending.confirmed then
    commodityPurchase = nil
    if confirmedAttemptOwnsRow(pending) then
      resolvePurchase(pending.row, true, "purchase total unavailable — inspect mailbox", nil, pending.deal)
    else
      settleDetachedConfirmed(pending, "unavailable")
    end
    return
  end
  local row = pending.row
  if not row or row.purchaseToken ~= pending.token or row.purchaseDeal == nil then return end
  C_AuctionHouse.CancelCommoditiesPurchase()
  -- Fix 3: was resolvePurchase(row, false, ...), which closed the dialog outright. The
  -- commodity is gone (someone bought it out between the quote and this event) -- showGoneState
  -- clears the exact same activeItemID/commodityPurchase bookkeeping resolvePurchase's failure
  -- path did (never crediting the session, same as before) but leaves the dialog up with an
  -- explanation instead of flashing it shut.
  showGoneState(row, "commodity no longer available -- someone bought it out")
  if frame then frame.status:SetText("commodity no longer available -- someone bought it out") end
  refreshRows()
end

function GC.Sniper.OnCommodityPurchaseSucceeded()
  if commodityDraining then
    local pending = commodityDraining
    commodityDraining = nil
    if not pending.confirmed then return end
    settleDetachedConfirmed(pending, "success")
    return
  end
  local pending = commodityPurchase
  if not pending or not pending.confirmed then return end
  if not confirmedAttemptOwnsRow(pending) then
    commodityPurchase = nil
    settleDetachedConfirmed(pending, "success")
    return
  end
  local row = pending.row
  local deal = pending.deal
  local quote = pending.quote
  if not deal or not quote or quote.token ~= pending.token or quote.itemID ~= pending.itemID
      or not quote.decision or quote.decision.status ~= "SAFE" then
    resolvePurchase(row, true, "purchase total unavailable — inspect mailbox")
    return
  end
  local purchase = purchaseFacts(deal, quote)
  resolvePurchase(row, true, purchase and ("bought %d x item %d"):format(purchase.quantity, deal.itemID)
    or "purchase total unavailable — inspect mailbox", purchase, deal)
end

function GC.Sniper.OnCommodityPurchaseFailed()
  if commodityDraining then
    local pending = commodityDraining
    commodityDraining = nil
    if pending.confirmed then settleDetachedConfirmed(pending, "failed") end
    return -- terminal event for the cancelled/closed attempt, never the next one
  end
  local pending = commodityPurchase
  if not pending then return end
  if pending.confirmed then
    commodityPurchase = nil
    if confirmedAttemptOwnsRow(pending) then
      resolvePurchase(pending.row, false, "commodity purchase failed")
    else
      settleDetachedConfirmed(pending, "failed")
    end
    return
  end
  local row = pending.row
  if not row or row.purchaseToken ~= pending.token or row.purchaseDeal == nil then return end
  commodityPurchase = nil
  resolvePurchase(row, false, "commodity purchase failed")
end

-- Sniper v3 §3 pause routers, forwarded from Core/Init.lua's MAIL_SHOW/MAIL_CLOSED dispatch
-- (MAIL_SHOW is also the P2 ledger's own inbox-scan trigger -- this is a second, independent
-- forward of the same event, not a replacement). Reading mail and driving the Sniper's own
-- Full Scan both hammer the throttled message system, so Auto yields for the whole mailbox
-- visit exactly like it does for a buy dialog or the player's own search.
function GC.Sniper.OnMailShow()
  feedAuto("pause:mail")
end

function GC.Sniper.OnMailClosed()
  feedAuto("resume:mail")
end

-- AutoScan pause hooks for the buy-confirmation dialog (spec §3's throttle-priority rule).
-- Called from openDialog / the dialog's own OnHide below -- future dialog work must keep both
-- call sites intact. Clearing pendingBrowsePage/pendingFullScanStart on open (regardless of
-- whether Auto itself is even on) means GC.Sniper.OnThrottleReady's scan-traffic-first order
-- (see its own comment) can never win a race against the live requery this dialog is about
-- to issue for a stale deal -- the next ready throttle slot always goes to the player's own
-- pending purchase, not a parked scan page.
function GC.Sniper.NotifyDialogOpened()
  -- (fix round 1, C1) abortFullScan(), not a bare poke at pendingBrowsePage/
  -- pendingFullScanStart -- those two flags only cover a scan PARKED waiting on the throttle
  -- system. A scan already mid-paging has scanRunning=true with neither flag set, and the
  -- machine's own addPause("dialog") (fed below) only aborts a scan it itself started
  -- (state=="SCANNING") -- a MANUAL "Scan" click is invisible to it. Leaving scanRunning
  -- stuck true forever (nothing else would ever clear it once the player's own browse query
  -- starts landing) means: the Scan button stays permanently "already in progress" (dead),
  -- GC.Sniper.IsBusy() never returns false again (deadlocks GC.Sell's throttle gate), and
  -- worse -- OnBrowseResults/OnBrowseResultsAdded are gated ONLY on scanRunning, not on whose
  -- query it was, so the player's own Browse-tab search would get ingested as if it were the
  -- next page of OUR scan. abortFullScan() clears all of that (and bumps fullScanToken,
  -- invalidating any in-flight watchdog closure from the aborted pass) regardless of who
  -- started it.
  local wasScanning = scanRunning or pendingFullScanStart
  abortFullScan()
  if wasScanning and frame then
    frame.status:SetText("full scan interrupted -- confirm your purchase")
  end
  feedAuto("pause:dialog") -- if THIS was an Auto-driven scan, cancelFullScan's own status wins below
end

function GC.Sniper.NotifyDialogClosed()
  feedAuto("resume:dialog")
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
    local pending = commodityPurchase
    local quoteSnapshot = row.quoteSnapshot
    if not pending or pending.row ~= row or pending.token ~= row.purchaseToken
        or not quoteSnapshot or quoteSnapshot.token ~= pending.token
        or quoteSnapshot.itemID ~= pending.itemID
        or not quoteSnapshot.decision or quoteSnapshot.decision.status ~= "SAFE"
        or not quoteSnapshot.decision.buyable then
      return
    end
    -- Hardware click only: the event prepares a quote; it never confirms one. The token and
    -- immutable final decision must still be current at this exact click.
    C_AuctionHouse.ConfirmCommoditiesPurchase(quoteSnapshot.itemID, quoteSnapshot.quantity)
    -- Preserve the immutable server quote/deal with the attempt itself. Dialog hide and AH
    -- close are UI/session transitions, not proof that a confirmed server purchase vanished.
    pending.confirmed = true
    pending.deal = row.purchaseDeal
    pending.quote = quoteSnapshot
    row.purchaseStage = "confirming"
    dialog.primaryBtn:Disable()
    dialog.cancelBtn:Disable()
    setDialogStatus("confirming purchase...")
    if frame then frame.status:SetText("confirming purchase...") end
    if refreshQtyRow then refreshQtyRow() end -- Fix 2: purchase call already issued -- box/quick-fill must stay greyed out
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

  if stage == "check" then
    dialog.primaryBtn:Disable()
    setPrimaryLabel("Check")
    setDialogStatus("checking live safety...")
    startRequery(row, row.deal)
    return
  end

  if stage ~= "ready" then
    return -- every other stage's primary button is disabled; guard anyway against a stray click
  end

  -- Fix 2 (review): a qty typed into the Quantity box only commits on OnEditFocusLost -- and a
  -- WoW EditBox KEEPS focus when the player clicks a Button, so a Buy click straight from the
  -- box would otherwise fire the purchase against the last-committed qty while the box shows
  -- the new number. ClearFocus() runs OnEditFocusLost synchronously (qtyBox.onCommit ->
  -- applyChosenQty), so by the time row.deal is read below it already carries the typed qty.
  -- That commit can also flip the button off ("not enough gold" -- updateBuyAffordance runs
  -- inside applyChosenQty), so re-check and bail rather than buy past the affordance gate the
  -- player hasn't even seen yet.
  if dialog.qtyBox and dialog.qtyBox.editBox:HasFocus() then
    dialog.qtyBox.editBox:ClearFocus()
    if row.purchaseStage ~= "ready" or not dialog.primaryBtn:IsEnabled() then return end
  end

  -- Second overall click: only a current SAFE commodity decision may begin a protected server
  -- purchase. Realm/item results remain Check-only, regardless of legacy discovery tier.
  local deal = row.deal
  local decision = row.decisionSnapshot
  if not deal.isCommodity or not decision or decision.status ~= "SAFE" or not decision.buyable then
    armCheck(row, deal, decision or { status = "WATCH", reasons = { "live_verification_required" } },
      "live verification required", false)
    return
  end
  if commodityDraining then
    setDialogStatus("waiting for previous commodity purchase to settle", 1, 0.82, 0)
    if frame then frame.status:SetText("waiting for previous commodity purchase to settle") end
    return
  end
  if commodityPurchase and commodityPurchase.row ~= row then
    -- Only ONE commodity purchase may be in flight at a time. Unreachable in practice --
    -- opening a second dialog already refuses/replaces per the guard in onBuyClick -- kept as
    -- a last-resort guard against orphaning the pending one.
    setDialogStatus("finish the pending buy first", 1, 0.3, 0.3)
    driver.onStatus("finish the pending buy first")
    return
  end

  row.purchaseDeal = deal
  row.quoteSnapshot = nil
  row.purchaseToken = (row.purchaseToken or 0) + 1
  local token = row.purchaseToken
  row.purchaseStage = "buying"
  dialog.primaryBtn:Disable()
  if refreshQtyRow then refreshQtyRow() end -- Fix 2: purchase call about to fire -- box/quick-fill must not be editable while it's in flight
  if deal.isCommodity then
    commodityPurchase = { row = row, itemID = deal.itemID, token = token }
    C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, decision.quantity)
    setDialogStatus("buying commodity...")
    if frame then frame.status:SetText("buying commodity...") end
  else
    -- Deliberately unreachable: v1 rejects non-commodity results above. Retaining this
    -- protected-call branch makes its hardware-click-only placement mechanically auditable
    -- while the decision gate ensures a realm/item scan can never reach PlaceBid.
    pendingAuction[deal.auctionID] = row
    -- PlaceBid's bidAmount is the TOTAL price for the auction's whole lot, not a per-unit
    -- price -- deal.unitPrice is per-unit (see driver.itemResult) -- multiply back out by
    -- qty here, the same unitPrice * qty = total convention resolvePurchase and
    -- GC.Sniper.OnPurchaseCompleted already use for session accounting and the status line.
    C_AuctionHouse.PlaceBid(deal.auctionID, deal.unitPrice * deal.qty)
    setDialogStatus("placing bid...")
    if frame then frame.status:SetText("placing bid...") end
  end
  scheduleBuyTimeout(row, deal, token)
end

-- ---------------------------------------------------------------------------
-- Fix 2 (quantity selector + affordability, commodities only -- an item auction is one
-- atomic lot, so there is nothing here to pick). The dialog's Quantity row lets the player
-- shrink (never grow past what's on the board) a commodity purchase below FullScan/Scanner's
-- own suggested qty, either by typing a number into the box or clicking one of the four
-- 25/50/75/100% quick-fill buttons -- both paths funnel through applyChosenQty (below) so
-- there is exactly one place that re-evaluates the immutable live decision for a new qty and
-- re-stamps the dialog. The widgets themselves are built in createDialog, further down; these are the
-- pure(ish) helpers that drive them, defined here so armReady/startRequery/
-- onDialogPrimaryClick/OnCommodityPriceUpdated/scheduleArmTimeout (all ABOVE this point in the
-- file) can already call refreshQtyRow/updateBuyAffordance via the forward declarations next
-- to the decision stamper.
-- ---------------------------------------------------------------------------

-- Sums a raw commodity order-book's level quantities (driver.commodityBook's own shape,
-- cached as dialog.bookLevels by the same live query that produced the decision) -- the total currently listed across every
-- level the dialog fetched (bounded by MAX_BOOK_LEVELS, same cap driver.commodityBook itself
-- applies).
local function sumLevelQty(levels)
  local total = 0
  for _, level in ipairs(levels) do
    total = total + (level.quantity or 0)
  end
  return total
end

-- The Quantity box's clamp ceiling, and what a 100% quick-fill resolves to. Priority order:
-- the LIVE book's own total (most trustworthy -- it is exactly what SniperDecision just read for
-- THIS deal), then deal.avail (FullScan/Scanner's own totalQuantity snapshot, Fix 1), then
-- deal.qty as a last resort (never less than what's already being proposed) -- floored at 1 so
-- a degenerate 0 can never make the controls unusable.
local function qtyMaxAvailable(deal)
  local maxQty
  if dialog and dialog.bookLevels then
    maxQty = sumLevelQty(dialog.bookLevels)
  end
  if not maxQty or maxQty < 1 then maxQty = deal.avail end
  if not maxQty or maxQty < 1 then maxQty = deal.qty end
  if not maxQty or maxQty < 1 then maxQty = 1 end
  return maxQty
end

-- Keeps the dialog's Quantity row (box + "of N" label + quick-fill buttons, or the
-- non-commodity "(whole lot)" fallback) in sync with the CURRENT dialog.deal and
-- dialog.row.purchaseStage. Embedded in stampDialogFromDecision (so every re-stamp re-syncs it
-- for free) plus called explicitly from every stage transition that does not produce a new
-- decision: startRequery, onDialogPrimaryClick's buying/confirming,
-- OnCommodityPriceUpdated's confirm/requote, and scheduleArmTimeout's expired branch -- the
-- same stage list the machine comment above (Task-3 requery section) enumerates.
refreshQtyRow = function()
  if not dialog or not dialog.qtyBox then return end -- dialog not built yet
  local deal = dialog.deal
  if not deal then return end
  local editable = dialog.row ~= nil and dialog.row.purchaseStage == "ready" and deal.isCommodity

  if deal.isCommodity then
    dialog.qtyLotText:Hide()
    dialog.qtyBox:Show()
    local known = deal.avail
    if not known and dialog.bookLevels then
      local bookTotal = sumLevelQty(dialog.bookLevels)
      if bookTotal > 0 then known = bookTotal end
    end
    if known then
      dialog.qtyOfLabel:SetText(("of %d"):format(known))
      dialog.qtyOfLabel:Show()
    else
      dialog.qtyOfLabel:Hide()
    end
    for _, btn in pairs(dialog.quickFillBtns) do btn:Show() end
  else
    -- A lot cannot be split -- there is nothing to type or quick-fill against.
    dialog.qtyBox:Hide()
    dialog.qtyOfLabel:Hide()
    dialog.qtyLotText:Show()
    dialog.qtyLotText:SetText(("%d (whole lot)"):format(deal.qty))
    for _, btn in pairs(dialog.quickFillBtns) do btn:Hide() end
  end

  local eb = dialog.qtyBox.editBox
  if editable then
    eb:EnableMouse(true)
    eb:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
    for _, btn in pairs(dialog.quickFillBtns) do btn:Enable() end
  else
    eb:ClearFocus() -- a stage transition mid-edit must not leave an uncommitted focus behind
    eb:EnableMouse(false)
    eb:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3], 1)
    for _, btn in pairs(dialog.quickFillBtns) do btn:Disable() end
  end
end

-- Only meaningful while the dialog is genuinely offering a "click Buy" decision (stage
-- "ready") -- every other stage either already fired the purchase call or is itself gating the
-- button for its own reason (loud requote's countdown, a buy timeout, ...), and this must
-- never override that. Reads dialog.stampedTotal, the number the decision stamper just put ON
-- SCREEN (not a raw deal.unitPrice*qty), so what disables the button is always the same figure
-- the player is looking at.
updateBuyAffordance = function()
  if not dialog or not dialog.row then return end
  local row = dialog.row
  if row.purchaseStage ~= "ready" then return end
  local total = dialog.stampedTotal
  if not total then return end
  if total > GetMoney() then
    dialog.primaryBtn:Disable()
    setDialogStatus(("not enough gold -- total %s, you have %s")
      :format(formatColumnAmount(total), formatColumnAmount(GetMoney())), 1, 0.3, 0.3)
  else
    dialog.primaryBtn:Enable()
    setDialogStatus("price confirmed -- click Buy to purchase", 0.25, 0.85, 0.25)
  end
end

-- Applies a player-chosen quantity (typed into the box, or one of the 25/50/75/100%
-- quick-fill buttons) to the dialog's live purchase attempt. Guarded to the exact identity/
-- stage the controls themselves are only ever editable in -- a stray call from a race (box
-- focus-lost firing after the row moved on) is a silent no-op, never a crash or a purchase
-- against the wrong row. activeItemID/row.purchaseStage are untouched -- this is a
-- re-evaluation of the SAME pinned purchase attempt, not a new one.
local function applyChosenQty(row, n)
  if not dialog or dialog.row ~= row then return end
  if row.purchaseStage ~= "ready" then return end
  local deal = dialog.deal
  if not deal or not deal.isCommodity then return end

  -- A player-selected quantity is a new safety decision, not a legacy UI price recomputation.
  -- It reuses the exact live book captured by the authoritative requery; missing depth fails
  -- closed rather than falling back to a discovery quote or an estimated total.
  local decision = evaluateLive(deal.itemID, dialog.bookLevels, n)
  if not decision or not decision.buyable or decision.status ~= "SAFE" then
    armCheck(row, deal, decision or { status = "WATCH", reasons = { "live_verification_required" } },
      (decision and decision.reasons and decision.reasons[1]) or "live_verification_required", false)
    return
  end

  row.decisionSnapshot = decision
  row.quoteSnapshot = nil
  setDialogHeader(deal, decision)
  stampDialogFromDecision(deal, decision)
  updateBuyAffordance()
  scheduleArmTimeout(row, deal, decision)
end

-- Shared by the Quantity box's OnEditFocusLost commit and every 25/50/75/100% quick-fill
-- button -- both must land on the exact same clamped qty for the exact same deal, or a 100%
-- click and a hand-typed max could disagree with each other on the same deal.
local function applyQuickFillQty(pct)
  if not dialog or not dialog.row then return end
  local row = dialog.row
  if row.purchaseStage ~= "ready" then return end
  local deal = dialog.deal
  if not deal or not deal.isCommodity then return end

  local maxQty = qtyMaxAvailable(deal)
  local n = math.floor(maxQty * pct / 100) -- 100% => maxQty exactly (100/100 = 1)
  if n < 1 then n = 1 end
  if n > maxQty then n = maxQty end
  if dialog.qtyBox then dialog.qtyBox.editBox:SetText(tostring(n)) end
  applyChosenQty(row, n)
end

-- ---------------------------------------------------------------------------
-- Sniper v3 dialog layout constants. The dialog is split into a TOP-anchored block (title,
-- item header, grid, notes, status -- every one of these keeps a FIXED offset from the
-- dialog's TOP edge) and a BOTTOM-anchored block (banner, buttons -- fixed offset from the
-- dialog's BOTTOM edge). Because `dialog` is positioned by a single CENTER point, growing its
-- height via SetHeight moves the TOP edge up and the BOTTOM edge down by half the delta each
-- -- so the two blocks drift apart and the requote banner's fixed offset from the bottom
-- block lands it in exactly the gap that opened up between them. This is the same mechanism
-- the pre-Theme dialog used (see hideRequoteBanner/showRequoteBanner); only the pixel budget
-- below is new, sized for the wider Theme fonts and the added item-header row.
-- ---------------------------------------------------------------------------
local DIALOG_WIDTH = 320
local DIALOG_ICON = 24
local DIALOG_TITLE_LINE_H = 13 -- Theme.Label(d, 13)'s line height (title row)
local DIALOG_GRID_ROW_H = 17
-- Quantity and quick-fill precede the ten immutable decision/evidence fields below.
local DIALOG_GRID_ROWS = 12
-- Fix 2 quick-fill row geometry: four small ghost buttons sharing grid row 2 (right under the
-- Quantity row) -- they don't fit alongside that row's own label + "of N" + edit box on one
-- 296px-wide line, so they get their own row instead of crowding it.
local QTY_QUICKFILL_H = 16
local QTY_QUICKFILL_W = 34
local QTY_QUICKFILL_PCTS = { 25, 50, 75, 100 }
-- I5: 36/32 (were 28/18) -- the requote path's status line can wrap to two full lines
-- ("<unit> -> <unit> per unit    total <total> -> <total>" at DIALOG_WIDTH), and the
-- suspect/mv notes must never clip a second line either; both budgets sized for two lines
-- of Theme.Label(d, 11) at this width, not one.
local DIALOG_NOTE_H = 36   -- reserved height for a 2-line suspect note at this width/font
local DIALOG_DIAGNOSTIC_MIN_H = 36
local DIALOG_STATUS_H = 32
local DIALOG_PRIMARY_H = 26
local DIALOG_CANCEL_H = 20
-- title line + gap + icon/name/chip row + gap + reserved suspect-note block + gap
local DIALOG_HEADER_H = Theme.pad.m + DIALOG_TITLE_LINE_H + Theme.pad.s + DIALOG_ICON + Theme.pad.s + DIALOG_NOTE_H + Theme.pad.s
local GRID_TOP = -DIALOG_HEADER_H
-- bottom margin + primary + gap + cancel + gap-to-banner, measured up from the dialog's own
-- bottom edge (mirrors GRID_TOP's measured-down-from-top pattern above).
local DIALOG_CONTROLS_H = Theme.pad.m + DIALOG_PRIMARY_H + Theme.pad.xs + DIALOG_CANCEL_H + Theme.pad.s
local DIALOG_FIXED_HEIGHT = DIALOG_HEADER_H + DIALOG_GRID_ROWS * DIALOG_GRID_ROW_H
  + DIALOG_STATUS_H + DIALOG_CONTROLS_H

-- Fix 2: a bordered box with a recolorable border, for the Quantity EditBox's focus ring.
-- Duplicated from SettingsFrame.lua's own private `borderedBox` (that one is a file-local
-- there, not reachable from here) rather than shared -- this is the only other Theme-styled
-- EditBox in the addon, and pulling a two-file dependency out of a settings-panel-only helper
-- for one reuse isn't worth it.
local function qtyBorderedBox(parent)
  local f = CreateFrame("Frame", nil, parent)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(Theme.color.bg[1], Theme.color.bg[2], Theme.color.bg[3], 1)

  local edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local e = f:CreateTexture(nil, "BORDER")
    if side == "TOP" or side == "BOTTOM" then
      e:SetPoint(side .. "LEFT")
      e:SetPoint(side .. "RIGHT")
      e:SetHeight(1)
    else
      e:SetPoint("TOP" .. side)
      e:SetPoint("BOTTOM" .. side)
      e:SetWidth(1)
    end
    edges[#edges + 1] = e
  end

  local function paint(c)
    for _, e in ipairs(edges) do
      e:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
  end
  paint(Theme.color.border)

  function f:SetBorderColor(c)
    paint(c)
  end

  return f
end

-- Fix 2: small numeric EditBox for the dialog's Quantity row -- same bordered-box + EditBox
-- idiom as SettingsFrame.lua's makeEditBox (mono font, gold border on focus, Escape/Enter
-- clear focus), NOT shared with it: bindNumberField's commit policy (clamp to a static
-- min/max, always write back to GC.db.settings.sniper) has nothing in common with this box's
-- (clamp to the LIVE order book via qtyMaxAvailable, commit through applyChosenQty) -- only
-- the widget shell is worth imitating, wired up separately in createDialog below.
local function makeQtyEditBox(parent, width, height)
  local box = qtyBorderedBox(parent)
  box:SetSize(width, height)

  local eb = CreateFrame("EditBox", nil, box)
  eb:SetPoint("TOPLEFT", 4, -1)
  eb:SetPoint("BOTTOMRIGHT", -4, 1)
  eb:SetAutoFocus(false)
  eb:SetNumeric(true)
  eb:SetJustifyH("CENTER")
  eb:SetMaxLetters(6) -- nothing plausible (even a full MAX_BOOK_LEVELS-deep book) needs more digits
  eb:SetFont(Theme.FONT_MONO, 12 * Theme.Scale(), "")
  eb:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  eb:SetScript("OnEnterPressed", eb.ClearFocus) -- commits via OnEditFocusLost, wired by the caller
  eb:SetScript("OnEditFocusGained", function() box:SetBorderColor(Theme.color.gold) end)
  -- The caller (createDialog) wires its own OnEditFocusLost on top of this one -- SetScript
  -- REPLACES rather than chains, so the border-reset here would be lost if the caller used
  -- SetScript directly. box.onCommit is the extension point: the border always resets first,
  -- then whatever commit logic the caller attached runs.
  eb:SetScript("OnEditFocusLost", function(self)
    box:SetBorderColor(Theme.color.border)
    if box.onCommit then box.onCommit(self) end
  end)

  Theme.OnRescale(function(scale)
    eb:SetFont(Theme.FONT_MONO, 12 * scale, "")
  end)

  box.editBox = eb
  return box
end

-- Builds the single reusable confirmation dialog (see createDialog/openDialog usage below).
-- Created lazily on the first Buy click of a session, same pattern as GoldCapImportDialog --
-- never built eagerly alongside the sniper frame itself.
local function createDialog()
  local d = Theme.Panel(UIParent)
  -- C1: Theme.Panel creates an UNNAMED frame (CreateFrame("Frame", nil, parent)), but
  -- UISpecialFrames (below) resolves "GoldCapSniperConfirm" by looking it up as a GLOBAL --
  -- without this, Escape can't find the dialog at all, so it falls through to hiding the main
  -- Sniper window instead, and the dialog's own OnHide (which calls abortRowPurchase) never
  -- fires -- silently orphaning an in-flight purchase's pinned row.
  _G.GoldCapSniperConfirm = d
  d.fixedHeight = DIALOG_FIXED_HEIGHT
  -- Match the two actual anchors: grid→diagnostic and diagnostic→status.
  d.diagnosticGaps = Theme.pad.xs + Theme.pad.xs
  d.diagnosticMinimumHeight = DIALOG_DIAGNOSTIC_MIN_H
  d.baseHeight = d.fixedHeight + d.diagnosticGaps + d.diagnosticMinimumHeight
  d:SetSize(DIALOG_WIDTH, d.baseHeight)
  d:SetFrameStrata("DIALOG") -- must float above the sniper list frame it's anchored to
  d:SetPoint("CENTER", frame, "CENTER")
  d:EnableMouse(true)

  local title = Theme.Label(d, 13)
  title:SetPoint("TOPLEFT", Theme.pad.m, -Theme.pad.m)
  title:SetText("Confirm Purchase")
  d.title = title

  local icon = d:CreateTexture(nil, "ARTWORK")
  icon:SetSize(DIALOG_ICON, DIALOG_ICON)
  icon:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -Theme.pad.s)
  d.icon = icon

  local tierChip = Theme.Chip(d)
  tierChip:SetWidth(COLUMN_W.tier) -- M13: matches the list's own tier column width, not a duplicated literal
  tierChip:SetPoint("TOPRIGHT", -Theme.pad.m, -(Theme.pad.m + DIALOG_TITLE_LINE_H + Theme.pad.s))
  d.tierChip = tierChip

  local nameText = Theme.Label(d, 12)
  nameText:SetPoint("LEFT", icon, "RIGHT", Theme.pad.s, 0)
  nameText:SetPoint("RIGHT", tierChip, "LEFT", -Theme.pad.s, 0)
  nameText:SetWordWrap(false)
  d.nameText = nameText

  -- A: hover tooltip over the icon+name header, same as a row (see createRow) -- Texture and
  -- FontString objects can't take mouse scripts themselves, so this is an invisible Frame
  -- spanning both, same pattern as createHeaderRow's own header hit-frames.
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

  -- A four-letter yellow tier chip lost to a green five-figure profit on 2026-08-10.
  -- Said in words, right under the header row, it competes on the same terms.
  local suspectNote = Theme.Label(d, 11)
  suspectNote:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -Theme.pad.s)
  suspectNote:SetPoint("RIGHT", -Theme.pad.m, 0)
  suspectNote:SetWordWrap(true)
  suspectNote:SetTextColor(Theme.tier.SUSPECT[1], Theme.tier.SUSPECT[2], Theme.tier.SUSPECT[3])
  suspectNote:SetText("a discount this extreme usually means the market value is wrong, not that this is a bargain")
  suspectNote:Hide()
  d.suspectNote = suspectNote

  -- Label/value grid: one row per number the player needs to decide with, aligned two-column
  -- (Theme.Label left, Theme.Num right) -- updateDialogAmounts re-stamps the value slots in
  -- place as fresher quotes come in; the grid itself never grows or reflows (fixed Y per row,
  -- same reasoning as GRID_TOP/DIALOG_GRID_ROW_H above: a chained anchor would let a wrapped
  -- neighbor note reflow rows underneath it).
  local function gridRow(index, label)
    local y = GRID_TOP - (index - 1) * DIALOG_GRID_ROW_H
    local labelFS = Theme.Label(d, 11)
    labelFS:SetPoint("TOPLEFT", Theme.pad.m, y)
    labelFS:SetText(label)

    local valueFS = Theme.Num(d, 12)
    valueFS:SetPoint("TOPRIGHT", -Theme.pad.m, y)
    return labelFS, valueFS
  end

  -- Fix 2: row 1 is Quantity -- commodities only editable (via qtyBox below); an item
  -- auction's row instead shows this plain dim qtyLotText ("N (whole lot)"), since a lot
  -- cannot be split. refreshQtyRow (above) toggles which of the two is shown/enabled.
  local _, qtyLotText = gridRow(1, "Quantity")
  qtyLotText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  d.qtyLotText = qtyLotText

  local qtyBox = makeQtyEditBox(d, 64, DIALOG_GRID_ROW_H - 3)
  qtyBox:SetPoint("TOPRIGHT", -Theme.pad.m, GRID_TOP - 1)
  d.qtyBox = qtyBox

  local qtyOfLabel = Theme.Label(d, 11) -- dim "of N" -- shown when the true available qty is known
  qtyOfLabel:SetPoint("RIGHT", qtyBox, "LEFT", -Theme.pad.xs, 0)
  qtyOfLabel:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  qtyOfLabel:Hide()
  d.qtyOfLabel = qtyOfLabel

  -- Commits a typed quantity: parse, clamp to [1, qtyMaxAvailable(deal)], write the clamped
  -- value back into the box (so a rejected out-of-range number never sits there un-corrected),
  -- and only call applyChosenQty when the clamped result actually differs from the deal's
  -- current qty -- an unchanged commit (re-typing the same number, or tabbing through
  -- untouched) has nothing to re-evaluate.
  qtyBox.onCommit = function(self)
    if not dialog or not dialog.row then return end
    local row = dialog.row
    if row.purchaseStage ~= "ready" then return end
    local deal = dialog.deal
    if not deal or not deal.isCommodity then return end

    local maxQty = qtyMaxAvailable(deal)
    local currentQty = row.decisionSnapshot and row.decisionSnapshot.quantity or deal.qty
    local n = tonumber(self:GetText())
    if not n then n = currentQty end
    n = math.floor(n + 0.5)
    if n < 1 then n = 1 end
    if n > maxQty then n = maxQty end
    self:SetText(tostring(n))

    if n ~= currentQty then
      applyChosenQty(row, n)
    end
  end

  -- Fix 2 quick-fill: row 2, right under Quantity -- four small ghost buttons that jump
  -- straight to a percentage of qtyMaxAvailable(deal) and commit immediately via
  -- applyChosenQty (same path qtyBox.onCommit uses -- see applyQuickFillQty). Built right-to-
  -- left off the grid's own right margin (100%, then 75%/50%/25% reading leftward), matching
  -- how every numeric grid column already anchors off the dialog's right edge.
  local quickFillBtns = {}
  local prevBtn
  for i = #QTY_QUICKFILL_PCTS, 1, -1 do
    local pct = QTY_QUICKFILL_PCTS[i]
    local btn = Theme.Button(d, "ghost")
    btn:SetSize(QTY_QUICKFILL_W, QTY_QUICKFILL_H)
    if prevBtn then
      btn:SetPoint("TOPRIGHT", prevBtn, "TOPLEFT", -Theme.pad.xs, 0)
    else
      btn:SetPoint("TOPRIGHT", -Theme.pad.m, GRID_TOP - DIALOG_GRID_ROW_H)
    end
    btn:SetLabel(pct .. "%")
    btn:SetScript("OnClick", function() applyQuickFillQty(pct) end)
    quickFillBtns[pct] = btn
    prevBtn = btn
  end
  d.quickFillBtns = quickFillBtns

  local _, decisionStatusText = gridRow(3, "Status")
  local _, unitPriceText = gridRow(4, "Entry price (avg fill)")
  local _, totalCostText = gridRow(5, "Entry total")
  local _, exitUnitText = gridRow(6, "Stress exit unit")
  local _, profitText = gridRow(7, "Stress profit")
  local _, mvText = gridRow(8, "Market reference")
  local _, soldText = gridRow(9, "Sold/day")
  local _, sellThroughText = gridRow(10, "Sell-through")
  local _, sourceAgeText = gridRow(11, "Source age")
  local _, reasonText = gridRow(12, "Reason")
  d.decisionStatusText = decisionStatusText
  d.unitPriceText, d.totalCostText, d.exitUnitText = unitPriceText, totalCostText, exitUnitText
  d.profitText, d.mvText, d.soldText = profitText, mvText, soldText
  d.sellThroughText, d.sourceAgeText, d.reasonText = sellThroughText, sourceAgeText, reasonText

  -- Sits between the grid and the status line; shown only when the clamp above actually bit.
  local mvNote = Theme.Label(d, 11)
  mvNote:SetPoint("TOPLEFT", Theme.pad.m, GRID_TOP - DIALOG_GRID_ROWS * DIALOG_GRID_ROW_H - Theme.pad.xs)
  mvNote:SetPoint("RIGHT", -Theme.pad.m, 0)
  mvNote:SetWordWrap(true)
  mvNote:SetTextColor(Theme.color.red[1], Theme.color.red[2], Theme.color.red[3])
  mvNote:Hide()
  d.mvNote = mvNote

  local diagnosticText = Theme.Label(d, 11)
  diagnosticText:SetPoint("TOPLEFT", Theme.pad.m, GRID_TOP - DIALOG_GRID_ROWS * DIALOG_GRID_ROW_H - Theme.pad.xs)
  diagnosticText:SetPoint("RIGHT", -Theme.pad.m, 0)
  diagnosticText:SetHeight(d.diagnosticMinimumHeight)
  diagnosticText:SetJustifyH("LEFT")
  diagnosticText:SetWordWrap(true)
  d.diagnosticText = diagnosticText

  local status = Theme.Label(d, 11)
  status:SetPoint("TOPLEFT", diagnosticText, "BOTTOMLEFT", 0, -Theme.pad.xs)
  status:SetPoint("RIGHT", -Theme.pad.m, 0)
  status:SetWordWrap(true)
  d.status = status

  -- Anchored off the BOTTOM, above the stacked buttons, and hidden by default. Showing it
  -- grows the dialog by exactly its own height (see the DIALOG_* block comment above), so the
  -- window visibly changes shape rather than re-rendering a line of status text inside an
  -- unchanged outline -- which is what a player running on muscle memory does not notice.
  local banner = Theme.Panel(d)
  banner:SetHeight(REQUOTE_BANNER_HEIGHT)
  banner:SetPoint("BOTTOMLEFT", Theme.pad.m, DIALOG_CONTROLS_H)
  banner:SetPoint("BOTTOMRIGHT", -Theme.pad.m, DIALOG_CONTROLS_H)
  -- Theme.Panel with red bg at 20% alpha: recolor the exposed .bg texture rather than
  -- reimplementing panel construction -- still built ONLY through the Theme factory.
  banner.bg:SetColorTexture(Theme.color.red[1], Theme.color.red[2], Theme.color.red[3], 0.2)

  local bannerHead = Theme.Label(banner, 12)
  bannerHead:SetPoint("TOPLEFT", Theme.pad.s, -Theme.pad.xs)
  bannerHead:SetTextColor(Theme.color.red[1], Theme.color.red[2], Theme.color.red[3])
  banner.head = bannerHead

  local bannerDetail = Theme.Label(banner, 11)
  bannerDetail:SetPoint("TOPLEFT", bannerHead, "BOTTOMLEFT", 0, -Theme.pad.xs)
  bannerDetail:SetPoint("RIGHT", -Theme.pad.s, 0)
  bannerDetail:SetWordWrap(true)
  banner.detail = bannerDetail

  banner:Hide()
  d.banner = banner

  local cancelBtn = Theme.Button(d, "ghost")
  cancelBtn:SetHeight(DIALOG_CANCEL_H)
  cancelBtn:SetPoint("BOTTOMLEFT", Theme.pad.m, Theme.pad.m + DIALOG_PRIMARY_H + Theme.pad.xs)
  cancelBtn:SetPoint("BOTTOMRIGHT", -Theme.pad.m, Theme.pad.m + DIALOG_PRIMARY_H + Theme.pad.xs)
  cancelBtn:SetLabel("Cancel")
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
        local pending = commodityPurchase
        if pending and pending.row == row then pending.cancelRequested = true end
      end
    end
    dialog:Hide() -- OnHide below does the actual local-state reset
  end)
  d.cancelBtn = cancelBtn

  -- Full-width primary button, bottom-most: the single most-clicked control in this window.
  local primaryBtn = Theme.Button(d, "primary")
  primaryBtn:SetHeight(DIALOG_PRIMARY_H)
  primaryBtn:SetPoint("BOTTOMLEFT", Theme.pad.m, Theme.pad.m)
  primaryBtn:SetPoint("BOTTOMRIGHT", -Theme.pad.m, Theme.pad.m)
  primaryBtn:SetLabel("Buy")
  primaryBtn:SetScript("OnClick", onDialogPrimaryClick)
  d.primaryBtn = primaryBtn

  -- Esc (via UISpecialFrames) hides the dialog. Before Confirm that follows the ordinary
  -- abort path; after Confirm abortRowPurchase deliberately preserves server ownership, so
  -- Esc can never discard the token/final quote while a terminal event is still possible.
  d:SetScript("OnHide", function()
    -- Unconditional -- fires whether this close was a resolved purchase, a hardware Cancel,
    -- or Esc, and regardless of whether `row` below is still set. AutoScan's own "dialog"
    -- pause reason cares only that the dialog is no longer up, not why.
    GC.Sniper.NotifyDialogClosed()
    dialog.decision = nil
    dialog.book = nil
    -- The requote baseline (see stampDialogFromBook) must not survive past this dialog
    -- session -- otherwise a stale stampedUnit/Total from THIS deal could be misread as the
    -- baseline for whatever the dialog gets reused for next.
    dialog.stampedUnit = nil
    dialog.stampedTotal = nil
    dialog.bookLevels = nil -- Fix 2: the Quantity box's clamp ceiling must not survive past this dialog session either
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
-- immediately; a `.stale` full-scan deal then either consumes a fresh Task 8 pre-warm cache
-- (dialog opens already armed -- no requery in flight, primary enabled straight away) or kicks
-- the existing Task-3 requery machinery (dialog stays open, primary disabled) instead of
-- arming right away.
local function openDialog(row, deal)
  -- This IS "purchase start" for `deal`'s itemID: from here on the row is about to be pinned
  -- (via startRequery or armReady, both below) for this purchase attempt, so any pre-warm
  -- still in flight for the SAME item is now moot -- release the "one in flight globally" slot
  -- rather than let it linger and (harmlessly, but pointlessly) resolve into a deal.prewarm
  -- cache nobody will ever read. A pre-warm in flight for a DIFFERENT item is untouched.
  if prewarmAttempt and prewarmAttempt.itemID == deal.itemID then
    -- Its response is untagged. Retire the warm behind the same drain fence a cancelled Check
    -- uses before this dialog can issue an authoritative query for the same item.
    if prewarmAttempt.sent then requeryDraining[deal.itemID] = prewarmAttempt end
    prewarmAttempt = nil
  end

  dialog = dialog or createDialog()
  dialog.row = row
  dialog.cancelBtn:Enable()
  -- Fix 3: a prior visit may have left this relabeled "Close" (showGoneState) -- every fresh
  -- open is a normal purchase attempt again, never a "the thing you were looking at is gone"
  -- notice, so the label must reset unconditionally regardless of what the dialog last showed.
  dialog.cancelBtn:SetLabel("Cancel")
  dialog.cancelBtn:Enable()
  hideRequoteBanner()
  dialog.deal = deal
  local discovery = { status = deal.status or "WATCH", reasons = { deal.reason or "live_verification_required" } }
  setDialogHeader(deal, discovery)
  stampDialogFromDecision(deal, discovery)
  dialog:Show()
  GC.Sniper.NotifyDialogOpened()

  local prewarm = deal.prewarm
  deal.prewarm = nil -- consumed either way below: a hit is used once, a miss/expiry is discarded so it can't be read again next open
  if deal.stale and prewarm and (GetTime() - prewarm.at) <= PREWARM_TTL_SECONDS then
    -- Task 8: feed the cached result into the exact same tail finishRequery uses to arm the
    -- button -- the dialog opens already armed, no "checking live price..." beat, no second
    -- SendSearchQuery. applyRequeryResult sets purchaseStage/activeItemID itself (via armReady
    -- or the nil-liveDeal branch), so there is nothing to pre-stage here.
    applyRequeryResult(row, deal.itemID, prewarm.data)
    -- A different-row handoff may have retained the old Check's Live pause through this
    -- openDialog call. A pre-warm resolves synchronously and does not call startRequery, so
    -- release that old owner here instead of leaving Live paused forever.
    if GC.Sniper._pausedLiveRequery and GC.Sniper._pausedLiveRequery.row ~= row then
      GC.Sniper._ResumePausedLiveRequery(GC.Sniper._pausedLiveRequery)
    end
  else
    dialog.primaryBtn:Disable()
    setPrimaryLabel("Check")
    setDialogStatus("checking live safety...")
    startRequery(row, deal) -- pins the row ("requerying"); only a SAFE commodity decision arms Buy
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
    -- The other row is only "ready" or "requerying" -- no purchase call in flight yet. This
    -- is a row replacement, not an ordinary Cancel: retain the paused Live intent until
    -- startRequery can transfer it to the new immutable Check. Resuming here would let
    -- Scanner:Start emit an untagged search in the gap before openDialog registers the new row.
    abortRowPurchase(dialog.row, nil, true)
  end

  openDialog(row, deal)
end

-- Cancels/resets non-confirmed work and clears tracking tables on AH close. A confirmed
-- commodity purchase becomes a retained tombstone instead: its exact quote may still receive
-- a late success and must not be silently lost.
local function resetAllPurchases()
  -- This bookkeeping also protects late server events after the visible AH has gone away, so
  -- it deliberately runs even in a headless/hidden UI state.
  local confirmed = commodityPurchase
  if confirmed and confirmed.confirmed then
    commodityPurchase = nil
    commodityDraining = confirmed
  end
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
  for k in pairs(requeryDraining) do requeryDraining[k] = nil end
  for k in pairs(GC.Sniper._drainWaitRequery) do GC.Sniper._drainWaitRequery[k] = nil end
  GC.Sniper._pausedLiveRequery = nil -- AH close must never revive a prior Live session
  -- Task 8: an AH close mid-pre-warm must release the "one in flight globally" slot too --
  -- otherwise a leftover prewarm attempt could block every hover pre-warm for the rest of the
  -- session (its own C_Timer.After fallback would eventually clear it, but there is no reason
  -- to wait REQUERY_TIMEOUT_SECONDS out when the AH session it belonged to just ended anyway).
  prewarmAttempt = nil
  if not (commodityDraining and commodityDraining.confirmed) then
    commodityPurchase = nil
    commodityDraining = nil
  end
  -- T6: a programmatic Hide() (this runs on AH close) doesn't reliably fire the row's own
  -- OnLeave, so clear the hover pin here too -- otherwise it could sit pinned to a hidden
  -- row across the next Auction House session.
  hoveredRow = nil
  if dialog then
    dialog.row = nil
    requoteArmToken = requoteArmToken + 1 -- invalidate any countdown still in flight
    hideRequoteBanner()
    dialog:Hide()
  end
end

-- ---------------------------------------------------------------------------
-- Row widgets (Sniper v3): built entirely from COLUMNS + anchorColumns (see above) instead of
-- the old per-field chain of independent fixed offsets -- one loop positions every fixed
-- column, and the flex "item" cell (icon + name, built directly rather than via a themed
-- factory) soaks up whatever width is left between the icon and the first fixed column.
--
-- Build (buildRowCell) and layout (layoutRow) are split so a responsive column-drop change
-- (applyColumnVisibility, above createRow's forward declaration) can re-run JUST the layout
-- pass -- re-anchoring/showing/hiding the SAME widgets -- on every existing pooled row without
-- rebuilding anything.
-- ---------------------------------------------------------------------------
local function buildRowCell(row, col)
  if col.key == "tier" then
    local chip = Theme.Chip(row)
    row.tierChip = chip
    return chip
  elseif col.key == "buy" then
    local btn = Theme.Button(row, "primary")
    btn:SetHeight(22)
    btn:SetLabel("Check")
    btn:SetScript("OnClick", function() onBuyClick(row) end)
    row.buy = btn
    return btn
  else
    local fs = Theme.Num(row, col.size, col.bold)
    fs:SetWordWrap(false)
    fs:SetMaxLines(1)
    row[NUM_FIELD[col.key]] = fs
    return fs
  end
end

layoutRow = function(row)
  local flexAnchor = anchorColumns(row, hiddenColumns, function(col) return row.cells[col.key] end)
  -- nameText is the one flexible widget, anchored on BOTH sides (icon's RIGHT, the first
  -- VISIBLE fixed column's LEFT via flexAnchor) so it soaks up whatever space is left over --
  -- this can never again drift out of sync with where the Buy button actually sits, since
  -- every visible fixed column between them is one link in the same anchorColumns chain, and
  -- a dropped optional column just isn't a link in that chain at all.
  row.nameText:ClearAllPoints()
  row.nameText:SetPoint("LEFT", row.icon, "RIGHT", Theme.pad.xs, 0)
  row.nameText:SetPoint("RIGHT", flexAnchor.frame, flexAnchor.point, -Theme.pad.s, 0)
end

createRow = function(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
  row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
  row:SetHeight(ROW_HEIGHT)

  -- E.1 zebra + hover: full-width BACKGROUND textures, drawn behind every other row widget
  -- (including the Buy button) regardless of creation order -- BACKGROUND always renders
  -- under ARTWORK. The zebra fill alternates by POOL index, not by the deal's position in
  -- the current sorted view, so it stays visually stable across a resort/rescan instead of
  -- flickering as rows are reassigned to different deals.
  local zc = Theme.color.zebra
  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetAllPoints()
  zebra:SetColorTexture(zc[1], zc[2], zc[3], (index % 2 == 1) and zc[4] or 0)
  row.zebra = zebra

  local hc = Theme.color.hover
  local highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1) -- sublevel 1: above zebra, still under ARTWORK
  highlight:SetAllPoints()
  highlight:SetColorTexture(hc[1], hc[2], hc[3], hc[4])
  highlight:Hide()
  row.highlight = highlight

  -- Sniper v3 §3 ping: 1.5s alpha fade-out flash for a newly-surfaced HOT deal (see
  -- pingNewHotDeals/flashRow above advanceBrowseScan). Built once per pooled row rather than
  -- per-flash -- an AnimationGroup is a real object with nontrivial construction cost, and
  -- rows are reused across scans/passes via the same pool. OnFinished re-hides the highlight
  -- unless the row is genuinely under the mouse right now (hoveredRow), so a flash that
  -- finishes mid-hover never fights the real hover state, and resets alpha back to 1 either
  -- way so a later genuine hover isn't dimmed.
  --
  -- (fix round 1, "insurance from cannot-verify") The group is built on the ROW frame
  -- (`row:CreateAnimationGroup()`), not `highlight:CreateAnimationGroup()` -- Frame is
  -- unambiguously a supported AnimationGroup owner; Texture's support for the same call
  -- wasn't independently verified against the live client, so this avoids betting createRow
  -- (which every pooled row, and therefore refreshRows() itself, depends on) on a Region-API
  -- gap. SetTarget points the specific Alpha animation at `highlight` instead.
  local flashAnim = row:CreateAnimationGroup()
  local flashAlpha = flashAnim:CreateAnimation("Alpha")
  flashAlpha:SetTarget(highlight)
  flashAlpha:SetFromAlpha(1)
  flashAlpha:SetToAlpha(0)
  flashAlpha:SetDuration(1.5)
  flashAlpha:SetSmoothing("OUT")
  flashAnim:SetScript("OnFinished", function()
    if hoveredRow ~= row then highlight:Hide() end
    highlight:SetAlpha(1)
  end)
  row.flashAnim = flashAnim

  -- Sniper v3: 2px gold left-rail shown alongside the hover highlight -- the accent that
  -- marks "this row" beyond the flat highlight wash alone.
  local rail = row:CreateTexture(nil, "BACKGROUND", nil, 2)
  rail:SetPoint("TOPLEFT")
  rail:SetPoint("BOTTOMLEFT")
  rail:SetWidth(2)
  rail:SetColorTexture(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3])
  rail:Hide()
  row.rail = rail

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("LEFT")
  row.icon = icon

  local nameText = Theme.Label(row, 11)
  nameText:SetWordWrap(false)
  nameText:SetMaxLines(1)
  row.nameText = nameText

  row.cells = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then
      row.cells[col.key] = buildRowCell(row, col)
    end
  end
  layoutRow(row)

  -- A + E.1: hover tooltip and highlight/rail on the row ITSELF, not an overlay on top of the
  -- Buy button -- a Frame's OnEnter/OnLeave don't consume mouse events, so the button (a
  -- separate child widget) keeps handling its own clicks exactly as before. row.deal is nil
  -- for an empty/hidden pooled row (refreshRows clears it before Hide()), so there is nothing
  -- to show a tooltip for even if a stray event ever reached a hidden frame.
  --
  -- T6: OnEnter also claims `hoveredRow` (see its declaration above) so refreshRows() pins
  -- this row's content for as long as the mouse stays over it -- streaming can call
  -- refreshRows() many times a second while a scan pages, and without this a merge could
  -- swap the deal under the cursor between the mouse landing and a click resolving. OnLeave
  -- releases the pin and immediately calls refreshRows() to catch up on anything it missed
  -- while frozen -- otherwise a stale row could sit there until the next unrelated refresh.
  --
  -- Task 8: OnEnter is also the hover pre-warm trigger (maybeStartPrewarm no-ops instantly
  -- unless self.deal is `.stale`, idle, and the throttle system is ready) -- deliberately NOT
  -- undone on OnLeave, unlike the hover pin above: leaving the row mid-query doesn't cancel
  -- anything, the result is still cached on the deal for whichever row/dialog eventually reads
  -- it.
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    self.highlight:Show()
    self.rail:Show()
    hoveredRow = self
    if not self.deal then return end
    maybeStartPrewarm(self.deal)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.deal.itemID)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
    self.rail:Hide()
    if hoveredRow == self then
      hoveredRow = nil
      refreshRows()
    end
    GameTooltip:Hide()
  end)

  row:Hide()
  return row
end

-- Simple single-line tooltip wired to OnEnter/OnLeave; shared by every control below that
-- just needs a plain hover explanation (no title/body split, no dynamic content).
-- I4: HookScript, not SetScript -- `widget` here is a Theme.Button (fullScanBtn/toggleBtn),
-- which already owns its own OnEnter/OnLeave for the hover-brighten (see Theme.lua's
-- T.Button). SetScript would silently REPLACE that handler and kill the hover-brighten
-- effect; HookScript runs this in addition to it.
local function setPlainTooltip(widget, text)
  widget:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- E.3/E.4: validates a saved window table before ever handing it to SetPoint/SetHeight/
-- SetWidth -- corrupted or hand-edited SavedVariables must never be trusted at face value.
local function isValidSavedWindow(win)
  return type(win) == "table" and type(win.point) == "string"
    and type(win.x) == "number" and type(win.y) == "number"
end

local function clampWindowHeight(h)
  if h < RESIZE_MIN_HEIGHT then return RESIZE_MIN_HEIGHT end
  if h > RESIZE_MAX_HEIGHT then return RESIZE_MAX_HEIGHT end
  return h
end

-- T5: width is now resizable too (previously only height could change -- see the FRAME_WIDTH
-- comment near the top), so the saved geometry needs the same clamp on the other axis.
local function clampWindowWidth(w)
  if w < RESIZE_MIN_WIDTH then return RESIZE_MIN_WIDTH end
  if w > RESIZE_MAX_WIDTH then return RESIZE_MAX_WIDTH end
  return w
end

-- Persists point/x/y (E.3) and width+height (E.4, T5) together under one saved-variables key.
-- Called via hooksecurefunc(frame, "StopMovingOrSizing", ...) in createFrame -- that native
-- method is the one thing BOTH hardware-driven geometry changes have in common now: dragging
-- calls it via Theme.TitleBar's own title-bar sub-frame (frame:StartMoving/StopMovingOrSizing,
-- Theme.lua), and the resize grip calls it directly (see createFrame's resizeHandle). Hooking
-- the method itself -- rather than an OnDragStop/OnMouseUp script -- means this fires no
-- matter which of those two hardware paths triggered the change, without needing a reference
-- to Theme.TitleBar's internal drag region (which Theme.lua doesn't expose).
local function persistWindowGeometry(f)
  local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
  if not cfg then return end
  local point, _, _, x, y = f:GetPoint(1)
  if not point then return end
  cfg.window = { point = point, x = x, y = y, width = f:GetWidth(), height = f:GetHeight() }
end

-- D: Deals/Sell view switcher. Full Scan/Live are separate widgets untouched by this and stay
-- clickable in both views. Sell's own container, rows, and bag-count refresh are entirely
-- GC.Sell's responsibility (built once by GC.Sell.Attach in createFrame) -- this function only
-- toggles the Deals-side widgets and the tab buttons' enabled state. Theme.Button has no
-- built-in "disabled" look (unlike the old UIPanelButtonTemplate), so the active tab is now
-- indicated explicitly via its own text color on top of Enable/Disable's functional gating.
local function setTabActive(btn, active)
  if active then
    btn:Disable()
    btn.text:SetTextColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3])
  else
    btn:Enable()
    btn.text:SetTextColor(Theme.color.fgMuted[1], Theme.color.fgMuted[2], Theme.color.fgMuted[3])
  end
end

local function setView(v)
  if view == v or not frame then return end
  view = v
  local isDeals = (v == "deals")
  if isDeals then
    frame.scroll:Show()
    frame.headerRow:Show()
    setTabActive(frame.dealsTab, true)
    setTabActive(frame.sellTab, false)
    if GC.Sell.Hide then GC.Sell.Hide() end
  else
    frame.scroll:Hide()
    frame.headerRow:Hide()
    setTabActive(frame.sellTab, true)
    setTabActive(frame.dealsTab, false)
    if GC.Sell.Show then GC.Sell.Show() end
  end
end

-- ---------------------------------------------------------------------------
-- Chrome (Sniper v3): Theme.Panel + Theme.TitleBar replace BasicFrameTemplateWithInset;
-- everything below the title bar is stacked top-down with named row-height constants and
-- Theme.pad gaps instead of ad-hoc absolute offsets.
-- ---------------------------------------------------------------------------
local TITLEBAR_H = 32    -- matches Theme.TitleBar's own fixed bar height (Theme.lua)
local TAB_WIDTH = 50
local TAB_HEIGHT = 18
local TOOLBAR_BTN_H = 24 -- Full Scan / Live button height
local HEADER_H = 16      -- column header row height

local function createHeaderRow(f)
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", f, "TOPLEFT", CONTENT_LEFT, f.headerY)
  header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CONTENT_RIGHT_GUTTER, f.headerY)
  header:SetHeight(HEADER_H)
  f.headerRow = header -- D: setView shows/hides this alongside f.scroll for the Sell tab

  -- sortKey (E.2), when present, makes the header clickable: OnMouseDown sets/toggles the
  -- module-local sortOverride and re-renders. Columns without an entry here (item/trend/buy)
  -- stay inert, exactly as "Item" always was. I6: "unit" is sortable too (its own SORT_VALUE
  -- key) -- unlike "total", "unit" is never one of the responsively-dropped columns, so it's
  -- always available as a by-price sort even at window widths where "total" itself is hidden.
  local SORT_KEY = { tier = "tier", disc = "pct", unit = "unit", total = "price", profit = "profit" }
  local HEADER_TEXT = { item = "Item", tier = "Tier", disc = "%", unit = "Unit", total = "Price", profit = "Profit", trend = "Trend", buy = "" }
  local TOOLTIP = {
    tier = {
      "Tier",
      "HOT = big discount + high profit + proven sales/day",
      "GOOD = solid discount + profit",
      "WATCH = discounted but unproven liquidity or small profit",
      "SUSPECT = discount so extreme it's probably a scam/mispriced-market item",
    },
    disc = { "Discount", "Discount vs market value from your GoldCap import" },
    unit = { "Unit price", "Per-unit price of this auction" },
    total = { "Price", "Total cost to buy this auction" },
    profit = { "Profit", "Estimated resale profit at 95% of market value, whole stack" },
  }

  local function buildHeaderCell(col)
    local hit = CreateFrame("Frame", nil, header)
    hit:SetHeight(HEADER_H)
    local baseText = (HEADER_TEXT[col.key] or ""):upper()
    local label = Theme.Label(hit, 11)
    label:SetAllPoints()
    label:SetJustifyH(col.num and "RIGHT" or "LEFT")
    label:SetText(baseText)
    hit.label = label

    local tooltipLines = TOOLTIP[col.key]
    local sortKey = SORT_KEY[col.key]
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
      -- E.2 + responsive drop: sortHeaders[sortKey] keeps pointing at this label even while
      -- the column is hidden (hit:Hide() below via anchorColumns), so an active sort on a
      -- since-hidden column (e.g. "total"/price) stays in full effect -- sortedDeals/
      -- applySortOverride never look at header visibility -- only its ▼/▲ indicator simply
      -- isn't visible until the column comes back (updateHeaderSortIndicators still writes to
      -- the FontString; SetText on a hidden widget is harmless, it just isn't drawn).
      hit:EnableMouse(true)
      sortHeaders[sortKey] = { label = label, base = baseText }
      hit:SetScript("OnMouseDown", function() onHeaderSortClick(sortKey) end)
    end
    return hit
  end

  header.cells = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then
      header.cells[col.key] = buildHeaderCell(col)
    end
  end

  local itemHit = CreateFrame("Frame", nil, header)
  itemHit.label = Theme.Label(itemHit, 11)
  itemHit.label:SetAllPoints()
  itemHit.label:SetJustifyH("LEFT")
  itemHit.label:SetText("ITEM")

  -- Re-anchors the visible-only column chain (see anchorColumns) and the item header cell's
  -- RIGHT edge to match -- callable again on a resize (applyColumnVisibility) without
  -- rebuilding any header widget. M7: assigned to the module-local `layoutHeaderRow` (forward-
  -- declared above, alongside createRow/layoutRow), not a field on `f` -- see that
  -- declaration's comment for why.
  layoutHeaderRow = function()
    local flexAnchor = anchorColumns(header, hiddenColumns, function(col) return header.cells[col.key] end)
    itemHit:ClearAllPoints()
    itemHit:SetPoint("TOPLEFT", header, "TOPLEFT")
    itemHit:SetPoint("BOTTOMRIGHT", flexAnchor.frame, "BOTTOMLEFT", -Theme.pad.s, 0)
  end
  layoutHeaderRow()

  return header
end

local function createFrame()
  local f = CreateFrame("Frame", "GoldCapSniperFrame", UIParent)

  local panel = Theme.Panel(f)
  panel:SetAllPoints(f)

  local savedWindow = GC.db and GC.db.settings and GC.db.settings.sniper and GC.db.settings.sniper.window
  local restoreWidth, restoreHeight = FRAME_WIDTH, FRAME_HEIGHT
  if isValidSavedWindow(savedWindow) then
    if type(savedWindow.width) == "number" then restoreWidth = clampWindowWidth(savedWindow.width) end
    if type(savedWindow.height) == "number" then restoreHeight = clampWindowHeight(savedWindow.height) end
  end
  f:SetSize(restoreWidth, restoreHeight)

  -- Sniper v3 responsive column drop: establish the correct drop state up front from the
  -- window's actual starting width, so the very first header/row layout already reflects it
  -- instead of waiting for a later resize event (see applyColumnVisibility, and the
  -- f:SetScript("OnSizeChanged", ...) below that keeps it current afterward -- M8).
  hiddenColumns = computeHidden(restoreWidth - CONTENT_LEFT - CONTENT_RIGHT_GUTTER)

  -- T5: BOTH width and height are resizable now (previously only height -- see FRAME_WIDTH's
  -- own comment above); the column grid no longer needs a fixed width to stay aligned, since
  -- every column anchors relative to its neighbor (see COLUMNS/anchorColumns).
  f:SetResizable(true)
  f:SetResizeBounds(RESIZE_MIN_WIDTH, RESIZE_MIN_HEIGHT, RESIZE_MAX_WIDTH, RESIZE_MAX_HEIGHT)

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
  f:EnableMouse(true) -- blocks clicks from passing through to whatever's behind the window

  -- Chrome: Theme.TitleBar owns the drag region (title bar only, not the whole window),
  -- the close button (outer top-right), and the gear (inboard-left of close).
  local titleBar = Theme.TitleBar(f, "GoldCap Sniper")
  f.gearBtn, f.closeBtn = titleBar.gear, titleBar.close
  -- T10: opens/closes the in-game settings overlay (UI/SettingsFrame.lua) -- built lazily on
  -- first click, same lazy-construction pattern as this window's own purchase confirm dialog
  -- (createDialog, below).
  titleBar.gear:SetScript("OnClick", function() GC.SettingsUI.Toggle() end)

  -- hooksecurefunc, not an OnDragStop/OnMouseUp script: see persistWindowGeometry's own
  -- comment for why the method-hook is what unifies both hardware-driven geometry changes.
  hooksecurefunc(f, "StopMovingOrSizing", persistWindowGeometry)

  -- D: Deals/Sell view switcher tabs, top-left under the title bar.
  local row1Y = -(TITLEBAR_H + Theme.pad.s)
  local dealsTab = Theme.Button(f, "ghost")
  dealsTab:SetSize(TAB_WIDTH, TAB_HEIGHT)
  dealsTab:SetPoint("TOPLEFT", f, "TOPLEFT", CONTENT_LEFT, row1Y)
  dealsTab:SetLabel("Deals")
  dealsTab:SetScript("OnClick", function() setView("deals") end)
  f.dealsTab = dealsTab

  local sellTab = Theme.Button(f, "ghost")
  sellTab:SetSize(TAB_WIDTH + 14, TAB_HEIGHT) -- extra width for the "Sell (NN)" badge text
  sellTab:SetPoint("LEFT", dealsTab, "RIGHT", Theme.pad.xs, 0)
  sellTab:SetLabel("Sell")
  sellTab:SetScript("OnClick", function() setView("sell") end)
  f.sellTab = sellTab
  setTabActive(dealsTab, true)  -- Deals is the default view
  setTabActive(sellTab, false)

  -- B: import staleness. Right-justified so it reads as sitting on the right of row 1,
  -- sharing the row with the Deals/Sell tabs; hidden until refreshStaleText() (called on AH
  -- show and after every full scan) says otherwise.
  local staleText = Theme.Label(f, 11)
  staleText:SetPoint("TOPLEFT", sellTab, "TOPRIGHT", Theme.pad.s, 0)
  staleText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CONTENT_RIGHT_GUTTER, row1Y)
  staleText:SetJustifyH("RIGHT")
  staleText:SetWordWrap(false)
  staleText:Hide()
  f.staleText = staleText

  -- Row 2: status line (left) + Live / Scan / Auto (right). Sniper v3 §3 replaces the old
  -- standalone "Full Scan" primary button with a split control: Auto (rightmost, the most
  -- prominent control now -- same slot Full Scan alone used to hold) + Scan (renamed "Full
  -- Scan", now ghost, still the manual one-shot fallback) to its left; the watchlist
  -- live-scan toggle stays exactly where it was, further left again.
  local row2Y = row1Y - (TAB_HEIGHT + Theme.pad.s)
  local AUTO_BTN_WIDTH = 148

  -- Auto (spec §3 "[Auto ⏻]"): two overlapping buttons -- ghost "off" look, primary "on"
  -- look -- swapped via Show/Hide by refreshAutoButton rather than one button repainted at
  -- runtime; see refreshAutoButton's own comment for why repainting a single Theme.Button
  -- doesn't survive its own hover-brighten. Both share the same click handler: it only cares
  -- whether the machine is currently OFF, not which of the two is visible.
  local autoBtnOff = Theme.Button(f, "ghost")
  autoBtnOff:SetSize(AUTO_BTN_WIDTH, TOOLBAR_BTN_H)
  autoBtnOff:SetPoint("TOPRIGHT", f, "TOPRIGHT", -CONTENT_RIGHT_GUTTER, row2Y)
  autoBtnOff:SetLabel("Auto")
  f.autoBtnOff = autoBtnOff

  local autoBtnOn = Theme.Button(f, "primary")
  autoBtnOn:SetAllPoints(autoBtnOff)
  autoBtnOn:SetLabel("Auto")
  autoBtnOn:Hide()
  f.autoBtnOn = autoBtnOn

  -- "Auto · scanning" pulse: a looping alpha animation on the "on" button itself, Played/
  -- Stopped only from refreshAutoButton (never here) so a rapid state flap can't stack
  -- overlapping Plays -- SetLooping("BOUNCE") free-runs forward/back on its own once started.
  local autoPulse = autoBtnOn:CreateAnimationGroup()
  autoPulse:SetLooping("BOUNCE")
  local autoPulseAlpha = autoPulse:CreateAnimation("Alpha")
  autoPulseAlpha:SetFromAlpha(1)
  -- 0.8, not lower: dipping the gold fill past ~0.7 over the near-black window desaturates
  -- it enough to read as the button flipping to gray, not as a scanning heartbeat.
  autoPulseAlpha:SetToAlpha(0.8)
  autoPulseAlpha:SetDuration(0.9)
  autoPulseAlpha:SetSmoothing("IN_OUT")
  autoBtnOn.pulse = autoPulse

  local function onAutoToggleClick()
    local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
    if autoScan:State() == "OFF" then
      if scanning then stopScanning() end
      if cfg then cfg.auto = true end
      feedAuto("toggleOn")
      -- (fix round 1, I4) toggleOn always arms with a clean reason set (AutoScan.lua wipes
      -- `reasons` on toggleOn), so re-seed "tab" immediately if the window isn't actually up
      -- -- defensive/unreachable in practice (this button lives INSIDE the window), but kept
      -- symmetric with the real case in GC.Sniper.OnAuctionHouseShow.
      if not frame or not frame:IsShown() then feedAuto("tabHidden") end
    else
      if cfg then cfg.auto = false end
      feedAuto("toggleOff")
    end
  end
  autoBtnOff:SetScript("OnClick", onAutoToggleClick)
  autoBtnOn:SetScript("OnClick", onAutoToggleClick)
  local autoTooltip =
    "Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, " ..
    "search the Auction House yourself, or check your mail. Click to toggle."
  setPlainTooltip(autoBtnOff, autoTooltip)
  setPlainTooltip(autoBtnOn, autoTooltip)

  local fullScanBtn = Theme.Button(f, "ghost")
  fullScanBtn:SetSize(64, TOOLBAR_BTN_H)
  fullScanBtn:SetPoint("RIGHT", autoBtnOff, "LEFT", -Theme.pad.xs, 0)
  fullScanBtn:SetLabel("Scan")
  fullScanBtn:SetScript("OnClick", onFullScanClick)
  setPlainTooltip(fullScanBtn,
    "One-shot scan of the entire Auction House via paged browse queries. Takes roughly " ..
    "15-60 seconds on busy realms. No cooldown -- rescan anytime.")
  f.fullScanBtn = fullScanBtn

  local toggleBtn = Theme.Button(f, "ghost")
  toggleBtn:SetSize(56, TAB_HEIGHT)
  toggleBtn:SetPoint("RIGHT", fullScanBtn, "LEFT", -Theme.pad.xs, 0)
  toggleBtn:SetLabel("Live")
  toggleBtn:SetScript("OnClick", function()
    if not GC.Sniper.scanner then
      f.status:SetText("Open the Auction House first.")
      return
    end
    if GC.Sniper._pausedLiveRequery then
      f.status:SetText("Live scan pauses while checking the selected listing.")
      return
    end
    if scanning then
      stopScanning()
    else
      GC.Sniper._StartLiveMode()
    end
  end)
  setPlainTooltip(toggleBtn,
    "Live: continuously re-checks the deals found by Auto/Scan without clearing the list. " ..
    "If no scan results exist, it monitors your imported watchlist.")
  f.toggleBtn = toggleBtn

  local status = Theme.Label(f, 11)
  status:SetPoint("TOPLEFT", f, "TOPLEFT", CONTENT_LEFT, row2Y)
  status:SetPoint("RIGHT", toggleBtn, "LEFT", -Theme.pad.s, 0)
  status:SetJustifyH("LEFT")
  status:SetText("Open the Auction House to begin scanning.")
  f.status = status

  -- Row 3: column headers, sticky above the scroll area.
  f.headerY = row2Y - (TOOLBAR_BTN_H + Theme.pad.s)
  createHeaderRow(f)

  local scrollTop = f.headerY - (HEADER_H + Theme.pad.xs)
  local scrollBottom = Theme.pad.m

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", CONTENT_LEFT, scrollTop)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -CONTENT_RIGHT_GUTTER, scrollBottom)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    local target = self:GetVerticalScroll() - delta * ROW_HEIGHT * 3
    if target < 0 then target = 0 end
    if target > range then target = range end
    self:SetVerticalScroll(target)
  end)
  f.scroll = scroll -- D: setView hides/shows this alongside f.headerRow for the Sell tab

  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(math.max(restoreWidth - CONTENT_LEFT - CONTENT_RIGHT_GUTTER, 1), ROW_HEIGHT) -- refreshRows() stamps the real height; OnSizeChanged below keeps width live
  scroll:SetScrollChild(content)
  -- T5/M8: the scroll child's WIDTH is the one piece of the grid Blizzard's ScrollFrame widget
  -- requires an explicit size for (unlike every row inside it, which anchors relatively) --
  -- keep it synced to the live content width so a frame resize re-flows the whole grid.
  -- Observed off `f` (the window frame) rather than `scroll` itself (M8): a ScrollFrame that's
  -- currently hidden (e.g. the Sell tab is showing, so `scroll:Hide()` -- see setView) is not
  -- guaranteed to fire its own OnSizeChanged while hidden, which would silently stop the
  -- Deals grid's column-drop from tracking a resize made while looking at Sell. `f` is never
  -- hidden while the window is open, so this fires regardless of which tab is active. The
  -- header's own width tracks the same CONTENT_LEFT/CONTENT_RIGHT_GUTTER margins off `f`
  -- directly, so the derived contentWidth here is exactly the header's width too -- one number
  -- feeds the responsive column-drop decision (applyColumnVisibility) for both.
  f:SetScript("OnSizeChanged", function(_, w)
    if not w or w <= 0 then return end
    local contentWidth = math.max(w - CONTENT_LEFT - CONTENT_RIGHT_GUTTER, 1)
    content:SetWidth(contentWidth)
    applyColumnVisibility(contentWidth)
  end)

  -- E.4 resize grip: a small BOTTOMRIGHT handle sized/positioned to sit in the scrollbar
  -- gutter (CONTENT_RIGHT_GUTTER) below the scroll frame's own bottom edge, not on top of the
  -- rows. StartSizing("BOTTOMRIGHT") (T5: both axes, not just "BOTTOM") + SetResizeBounds
  -- above are what actually let both width and height change. Created AFTER scroll (whose
  -- built-in scrollbar is a child one level deeper) and explicitly raised past it, so the
  -- grip always wins the corner's mouse-hit test instead of silently losing clicks to the
  -- scrollbar's own down-arrow button.
  local resizeHandle = CreateFrame("Button", nil, f)
  resizeHandle:SetSize(16, 16)
  resizeHandle:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Theme.pad.xs, Theme.pad.xs)
  resizeHandle:EnableMouse(true)
  resizeHandle:SetFrameLevel(scroll:GetFrameLevel() + 10)
  local grip = resizeHandle:CreateTexture(nil, "OVERLAY")
  grip:SetAllPoints()
  grip:SetColorTexture(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.35)
  resizeHandle:SetScript("OnMouseDown", function()
    f:StartSizing("BOTTOMRIGHT")
  end)
  resizeHandle:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing() -- persistWindowGeometry runs via the hooksecurefunc above
  end)
  f.resizeHandle = resizeHandle

  table.insert(UISpecialFrames, "GoldCapSniperFrame") -- Escape closes the window

  -- D: builds the Sell tab's container, hidden, filling the exact region `scroll` occupies
  -- above (same CONTENT_LEFT/CONTENT_RIGHT_GUTTER/scrollTop/scrollBottom -- passed through,
  -- never re-declared, so the two views can't silently drift out of alignment). rowWidth is a
  -- one-time snapshot at the window's CURRENT width -- GC.Sell.Attach only runs once, so
  -- (like before T5) the Sell tab's own column grid does not re-flow on a window resize; only
  -- the Deals grid gained that this task.
  GC.Sell.Attach(f, {
    panelLeft = CONTENT_LEFT,
    panelRightInset = CONTENT_RIGHT_GUTTER,
    top = scrollTop,
    bottom = scrollBottom,
    rowWidth = restoreWidth - CONTENT_LEFT - CONTENT_RIGHT_GUTTER,
    rowHeight = ROW_HEIGHT,
  })

  -- Sniper v3 §3 sniperTabShown/sniperTabHidden: the Sniper is a standalone floating window,
  -- not an AH-internal tab, so "the player returned to it" is just this window's own
  -- Show/Hide -- no separate tab-selection API to hook.
  --
  -- (fix round 1, I4 ruling) Auto runs ONLY while the Sniper window itself is shown -- a
  -- frame that starts hidden and is never shown this session never fires OnHide, so
  -- GC.Sniper.OnAuctionHouseShow/onAutoToggleClick are what seed the "tab" pause reason for
  -- that case (a toggleOn while the window doesn't exist/isn't shown yet); this OnShow is
  -- what always clears it once the window actually appears, whichever path armed it.
  -- resume:search is fed here too (C3/I3), same defensive rationale as the ahClosed feed
  -- below: a stuck "search" reason should never survive the player simply looking at the
  -- Sniper window again, even if Blizzard's own search box never fired OnEditFocusLost.
  f:SetScript("OnShow", function()
    feedAuto("tabShown")
    feedAuto("resume:search")
  end)
  f:SetScript("OnHide", function() feedAuto("tabHidden") end)

  refreshAutoButton(f) -- (fix round 1, M1) paint the initial label/visual before the very first Show
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

local searchHooksInstalled = false

-- Sniper v3 §3 player-search detection. AuctionHouseFrame doesn't exist until
-- Blizzard_AuctionHouseUI has loaded (first AH visit of the session), so this is called from
-- GC.Sniper.OnAuctionHouseShow -- by which point the AH frame is guaranteed to exist -- and
-- installs its hooks exactly once (searchHooksInstalled), never re-hooking on later visits.
--
-- Detection rule (documented here since Blizzard exposes no "are the live browse/search
-- results the player's own" flag to just read):
--   pause:search  -- fires the instant the player's own search box gains keyboard focus
--                    (about to type their own query), OR SetDisplayMode reports a mode OTHER
--                    than Buy/browse (switching to Sell/Auctions within Blizzard's OWN AH
--                    frame can itself re-issue a browse/search query we don't control).
--                    Either one means the live browse/search result state might stop being
--                    OUR scan's at any moment.
--   resume:search -- fires when the search box loses focus (AND our own Sniper window is
--                    shown -- window-visible is the closest available proxy for "the
--                    player's attention is back on the addon", since there's no API to ask
--                    "are the current results the player's search or ours"), OR when
--                    SetDisplayMode reports a return to the Buy/browse mode. Resuming is
--                    deliberately conservative for the same reason a resume always re-issues
--                    a FRESH browse query regardless of what's currently live (see
--                    AutoScan.lua): the worst case of resuming "too early" is clobbering
--                    results the player is still reading.
--
-- (fix round 1, C2) `AuctionHouseFrame.SearchBar` may be a plain container Frame whose actual
-- EditBox child is `.SearchBox` -- HookScript("OnEditFocusGained"/"OnEditFocusLost") on
-- anything that isn't an EditBox RAISES, which would abort GC.Sniper.OnAuctionHouseShow
-- mid-function (no ticker, no toggleOn, the window stops auto-opening) since this is called
-- synchronously from inside it. Resolve the actual box, duck-type it, and wrap both hook
-- installs in pcall as belt-and-braces against any client-version shape this wasn't verified
-- against (see the in-game checklist).
local function installSearchHooks()
  if searchHooksInstalled or not AuctionHouseFrame then return end
  searchHooksInstalled = true

  local searchBar = AuctionHouseFrame.SearchBar
  local box = searchBar and (searchBar.SearchBox or searchBar)
  if box and (box.SetFocus or (box.GetObjectType and box:GetObjectType() == "EditBox")) then
    pcall(function()
      box:HookScript("OnEditFocusGained", function() feedAuto("pause:search") end)
    end)
    pcall(function()
      box:HookScript("OnEditFocusLost", function()
        if frame and frame:IsShown() then
          feedAuto("resume:search")
        end
      end)
    end)
  end

  -- (fix round 1, C3) SetDisplayMode alone previously only ever fed pause:search, with no
  -- resume counterpart -- a single AH tab click would strand Auto in "paused: searching" for
  -- the rest of the session. Enum name unverified against the live client (see the in-game
  -- checklist) -- guarded so a missing/renamed enum degrades to the documented fallback
  -- instead of erroring.
  local buyMode = Enum.AuctionHouseDisplayMode and Enum.AuctionHouseDisplayMode.Buy
  if AuctionHouseFrame.SetDisplayMode then
    pcall(hooksecurefunc, AuctionHouseFrame, "SetDisplayMode", function(_, newDisplayMode)
      if buyMode ~= nil then
        if newDisplayMode == buyMode then
          feedAuto("resume:search")
        else
          feedAuto("pause:search")
        end
        return
      end
      -- Enum shape not verified: can't tell Buy mode from any other, so pause immediately
      -- (a mode change COULD be the player driving the AH's own search) and, if our window
      -- is up, resume after a short defer -- long enough for the mode transition's own query
      -- to land first -- so one stray SetDisplayMode call can't strand Auto for the session.
      feedAuto("pause:search")
      if frame and frame:IsShown() then
        C_Timer.After(0.5, function()
          if frame and frame:IsShown() then feedAuto("resume:search") end
        end)
      end
    end)
  end
end

function GC.Sniper.OnAuctionHouseShow()
  -- Task 8 fix round 1 M-3: flips first, unconditionally -- everything below (including an
  -- early-return path this function doesn't have today, but might grow) must see the AH
  -- session as live before any of it runs.
  ahOpen = true

  -- B: independent of autoOpen/window visibility -- the chat warning is meant to reach the
  -- player even if they keep the sniper window closed.
  maybeWarnStale()

  -- Build the scanner on the first AH visit regardless of autoOpen, so a later
  -- manual watchlist Live click has one to drive.
  GC.Sniper.scanner = GC.Sniper.scanner or GC.Scanner.New(driver, GC.db.settings.sniper)

  -- Sniper v3 §3: the AutoScan ticker only runs while the AH is open (nothing to drive
  -- otherwise -- SendBrowseQuery would silently no-op with no AH session live). This, the
  -- search-detection hooks, and the ahOpened/toggleOn feed below all run regardless of
  -- autoOpen -- toggleOn re-arms the MACHINE here even if autoOpen keeps the window itself
  -- from appearing, but (fix round 1, I4 ruling) Auto never actually SCANS until the window
  -- is shown, since toggleOn's own tab-seed just below re-adds "tab" if it isn't up yet.
  installSearchHooks()
  autoScanTicker = autoScanTicker or C_Timer.NewTicker(0.25, function()
    autoScan:Tick(GetTime())
    refreshAutoButton()
  end)
  feedAuto("ahOpened")
  if GC.db.settings.sniper.auto then
    feedAuto("toggleOn") -- re-arms Auto across a /reload or the first AH visit of the session; a no-op once already armed
    -- toggleOn always arms with a clean reason set (AutoScan.lua wipes `reasons`), so
    -- re-seed "tab" immediately whenever the window isn't up yet -- autoOpen==false, or this
    -- is the very first AH visit of the session and the frame hasn't been built at all.
    -- Whenever the window DOES appear (immediately below if autoOpen, or later via a manual
    -- GC.Sniper.Toggle()), its own OnShow -> tabShown clears this the normal way.
    if not frame or not frame:IsShown() then
      feedAuto("tabHidden")
    end
  end

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
  -- Task 8 fix round 1 M-3: flips first, unconditionally -- idempotent across the double-call
  -- this function already has to tolerate (see below), and must be false before
  -- resetAllPurchases/anything else runs so no code below it could observe a stale "AH still
  -- open" read.
  ahOpen = false

  -- Wired from both PLAYER_INTERACTION_MANAGER_FRAME_HIDE and AUCTION_HOUSE_CLOSED (their
  -- overlap on a given close is unverified in 12.0.7 -- see in-game checklist), so this must
  -- tolerate being called twice for one AH visit without double-printing or double-crediting.
  stopScanning()
  for i = #GC.Sniper._liveTargets, 1, -1 do GC.Sniper._liveTargets[i] = nil end
  GC.Sniper._liveTracksScanDeals = false
  abortFullScan()

  -- Sniper v3 §3: stop driving the machine's clock once there's nothing left for it to
  -- scan -- both idempotent against the double-call this function already has to tolerate.
  if autoScanTicker then
    autoScanTicker:Cancel()
    autoScanTicker = nil
  end
  feedAuto("ahClosed")
  -- Defensive: Blizzard's search EditBox isn't guaranteed to fire OnEditFocusLost as part of
  -- the AH frame's own close teardown, and AutoScan.lua's ahClosed handler only ever ADDS the
  -- "ah" pause reason -- it never clears any other reason already set. A "search"/"mail"
  -- reason left stuck true would otherwise silently block Auto forever on every future AH
  -- visit. Whatever the player's own search/mailbox was doing is moot once the AH session
  -- itself is gone. (fix round 1, C3: resume:mail added for symmetry with resume:search.)
  feedAuto("resume:search")
  feedAuto("resume:mail")

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
  -- Sniper v3 §3 ping: a HOT listing that pinged this session should be able to ping again
  -- next session even at the exact same price (a fresh AH visit is a fresh judgment of
  -- what's worth flagging) -- see seenHotDeals' own declaration.
  for key in pairs(seenHotDeals) do seenHotDeals[key] = nil end
  -- D: abort any in-flight Sell quote walk/post -- neither can safely resume once the AH
  -- session is gone (same reasoning as resetAllPurchases above for the Deals side).
  GC.Sell.Reset()
  if frame then frame:Hide() end
end
