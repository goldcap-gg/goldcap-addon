local _, GC = ...

GC.Sniper = GC.Sniper or {}
GC.Sniper._liveTargets = {}
GC.Sniper._liveTracksScanDeals = false

-- Churn observations and the resulting target list live on GC.Sniper as table fields rather
-- than as module locals: this chunk is at Lua's 200-local ceiling, and a field costs nothing.
GC.Sniper._churn = {}
GC.Sniper._churnSeq = 0
-- itemID -> GetTime() of the last ring stampVerdict rang for it. Same "field, not a local"
-- reasoning as _churn above.
GC.Sniper._rangAt = {}
-- itemID -> the last live unit price any observation reported for it, so a pinned placeholder
-- (renderList) can show a real number instead of a dash. Same "field, not a local" reasoning
-- as _churn above.
GC.Sniper._lastPrice = {}

local Theme = GC.Theme

-- Window and row geometry, folded into one table for the same reason DG below
-- is: this chunk is at Lua's 200-local ceiling exactly.
local WIN = {}
WIN.ROW_HEIGHT = Theme.ROW_H
WIN.ROW_CAP = 100 -- hard cap on rendered/pooled deal rows, for both watchlist and full-scan modes

-- Sniper v3: window chrome is Theme.Panel + Theme.TitleBar (see createFrame) instead of
-- BasicFrameTemplateWithInset, and BOTH width and height are now resizable (T5 -- previously
-- only height could change, which is why the old column grid derived every offset from a
-- single fixed WIN.FRAME_WIDTH). The column grid below is now driven by COLUMNS + anchorColumns:
-- every fixed-width cell anchors relative to its neighbor (right-to-left off the row/header
-- container's own RIGHT edge), and the `content`/`header` containers themselves track the
-- frame's live width via SetPoint, so a resize re-flows the grid with no recompute step
-- anywhere in this file -- the one thing that DOES need an explicit resync is the ScrollFrame's
-- scroll child (`content`), which Blizzard's scroll widget requires an explicit SetWidth for
-- (see createFrame's f:SetScript("OnSizeChanged", ...) -- observed off the window frame
-- itself, not the ScrollFrame, so it keeps firing even while the ScrollFrame is hidden behind
-- the Sell tab; M8).
-- 720, not 716: UI/SellFrame.lua's own COLUMNS grid derives its content width from this same
-- FRAME_WIDTH (minus the rail and the scrollbar gutter), and at 716 that content area comes
-- out to 596px -- short of the 600px shownColumns needs to keep the COST column past its
-- other fixed columns, so a fresh install silently opened with COST already dropped.
-- 720 gives 600px, which keeps it.
WIN.FRAME_WIDTH = 720
-- 600, was 520 (check panel v2 fix round 1: at 520 the drawer -- window height minus
-- CH.TITLEBAR(32) -- was 488, short of DG.FIXED_HEIGHT_OPEN(548), so a FRESH profile's
-- default-open evidence grid (Init.lua's dialogDetailsOpen = true) got refused by the F5 guard
-- before the player ever touched the toggle, seeding "Enlarge the window to see details" on a
-- window the player hadn't resized. 600 - CH.TITLEBAR(32) = 568 >= 548, matching the docked AH
-- drawer's own ~565px ceiling. Only fresh installs and RESET WINDOW see this default -- a
-- player's saved window size (persistWindowGeometry) is untouched.
WIN.FRAME_HEIGHT = 600
-- 640, was 560: the rail consumes RAIL_W of every width, so the old floor
-- left the item column ~90px after the responsive drops -- unreadable. 640
-- restores the same worst-case content width the 560 floor used to give.
WIN.RESIZE_MIN_WIDTH = 640
WIN.RESIZE_MAX_WIDTH = 1100
-- 470, was 460 (check panel v2: DG.FIXED_HEIGHT_CLOSED alone -- 368, a pure top-down sum --
-- is NOT the real closed-drawer floor. resizeDialogDiagnostics's own non-debug branch (the one
-- every real player sees) anchors `status` BOTTOM-UP, independently of the top-down stack, and
-- reserves the banner slot ABOVE it -- so the true minimum has to fit BOTH stacks without them
-- overlapping, not just the top-down sum. Recomputed straight off that function's own
-- anchoring, each term named:
--   DG.HEADER_H(52) + DG.VERDICT_H(94) + DG.QTY_H(42) + DG.CARDS_H(48) + DG.TOGGLE_H(22)
--     = 258  (top-down, through the Details toggle -- this magnitude IS DG.GRID_TOP)
--   + Theme.pad.xs(4)                                                       = 262  (gap after
--     the toggle, mirroring DG.EVIDENCE_BOTTOM_CLOSED's own toggle-to-content offset)
--   + LIM.REQUOTE_BANNER_HEIGHT(46) + Theme.pad.xs(4)                       = 312  (the banner
--     slot createDialog reserves above the status line, plus the pad.xs gap under it)
--   + DG.STATUS_H(32)                                                       = 344  (status's
--     own reserved line height, anchored at DG.CONTROLS_H by resizeDialogDiagnostics)
--   + DG.CONTROLS_H(78)                                                     = 422  (bottom
--     margin + Cancel + gap + Buy + gap-to-status)
-- stack = 422. The drawer itself is (window height - CH.TITLEBAR(32)); smallest multiple of 10
-- such that (RESIZE_MIN_HEIGHT - 32) - 422 >= 8 (an 8px safety margin, not zero-clearance) is
-- 470: 470 - 32 = 438, 438 - 422 = 16 >= 8. The F5 details-open guard (applyDetailsState) still
-- refuses at this floor by a wide margin -- it needs DG.FIXED_HEIGHT_OPEN(548) alone for the
-- default (debug off) player, or +diagnosticGaps(8)+diagnosticMinimumHeight(36) = 592 once
-- GC.db.settings.sniper.debug is on, and the drawer here is only 438 either way.
WIN.RESIZE_MIN_HEIGHT = 470
WIN.RESIZE_MAX_HEIGHT = 900

-- Content-area margins. WIN.CONTENT_RIGHT_GUTTER (scrollbar gutter reserved by
-- UIPanelScrollFrameTemplate) has no Theme equivalent -- Theme doesn't know about Blizzard's
-- scrollbar width -- so it stays a plain named constant, same as before.
WIN.RAIL_W = Theme.RAIL_W                     -- left navigation rail (Theme.Rail)
WIN.CONTENT_LEFT = WIN.RAIL_W + Theme.pad.m   -- content starts right of the rail
WIN.CONTENT_RIGHT_GUTTER = 32

-- The check panel (DG.WIDTH, a 320px sheet -- see createDialog) shifts the deals list aside
-- only when the window is wide enough to fit both without crushing the item column below its
-- own declared min (COLUMNS.item.min = 180) -- below this floor the panel overlays instead
-- (see applyPanelInset in createFrame). Derived, not guessed: contentWidth = window width -
-- WIN.CONTENT_LEFT(88) - WIN.CONTENT_RIGHT_GUTTER(32) - inset(DG.WIDTH(320) + Theme.pad.m(12)
-- = 332); with both optional columns dropped the fixed-column budget is 356 (fixedColumnBudget
-- above: tier 48 + disc 56 + unit 76 + profit 84 + buy 52 = 316, plus 5 * Theme.pad.s(8) = 40),
-- so item = contentWidth - 356, and item >= 180 needs contentWidth >= 536, i.e. window width >=
-- 88 + 32 + 332 + 356 + 180 = 988 -- rounded up to 990. The docked-in-the-AH host is 792px wide
-- (AuctionHouseFrame's own 806px, minus the dock's 7px inset on each side), well under this
-- floor, so it always keeps the overlay.
WIN.PANEL_SHIFT_MIN = 990

WIN.ICON_SIZE = 20 -- row item icon size; no Theme equivalent (Theme has no icon factory)

-- E.2 sortable headers -- unchanged mapping (only "tier"/"pct"/"price"/"profit" were ever
-- sortable; the two columns COLUMNS adds for Sniper v3, unit/trend, stay inert like "buy").
-- Timeouts, ratios and caps. Same reason as WIN above.
local LIM = {}
LIM.REQUOTE_WARN_RATIO = 0.05
LIM.REQUOTE_LOUD_RATIO = 0.25
-- How long the loud prompt refuses the confirming click. Long enough that a second click
-- already on its way lands on a disabled button, short enough not to feel broken.
LIM.REQUOTE_ARM_SECONDS = 1.5
LIM.REQUOTE_BANNER_HEIGHT = 46
-- How many order-book entries the dialog will read. Purely a bound on work done against
-- already-fetched results; a purchase never spans anywhere near this many price levels.
LIM.MAX_BOOK_LEVELS = 100
-- How far above the live market an imported market value has to sit before the dialog stops
-- treating it as information and says so.
-- How long a confirmed quote stays clickable in the dialog. Generous on purpose: the player
-- is reading a grid of numbers, and an older quote is safe on both paths -- an item auction
-- is immutable (PlaceBid either buys at exactly the shown price or fails because the lot is
-- gone), and a commodity purchase always re-quotes server-side via StartCommoditiesPurchase
-- before the separate Confirm click (with the >5% requote re-prompt on top).
LIM.ARM_TIMEOUT_SECONDS = 30
LIM.BUY_TIMEOUT_SECONDS = 8
LIM.REQUERY_TIMEOUT_SECONDS = 8
-- Task 8 hover pre-warm: how long a cached deal.prewarm result stays consumable by openDialog
-- before it's treated as expired (falls back to today's requery-then-arm flow instead).
LIM.PREWARM_TTL_SECONDS = 10
-- If no browse event arrives within this long after a send (initial query or page
-- request), the paging chain is presumed stalled -- see armScanWatchdog.
LIM.SCAN_WATCHDOG_SECONDS = 15
-- Background verification (tickAutoVerify): how far down the visible list to check, how often
-- a row already carrying a verdict is checked again, and how long a SAFE verdict may go
-- unrefreshed before the row stops advertising it. The scan, the Sell tab's pricing walk and
-- this all share one throttled search slot, and the Sell tab is the one that starves first
-- when something greedy runs -- but with Commit 1's estProfit ranking, renderList()'s order is
-- now best-first, so covering more of it (24, not the old 8) is worth the wider net; the walk
-- itself is still one query per second regardless of how many rows this covers.
LIM.VERIFY_TOP_ROWS = 24
LIM.VERIFY_INTERVAL_SECONDS = 30
LIM.VERIFY_TRUST_SECONDS = 120
-- How long a row whose last stamped verdict was AVOID goes before the walk spends another
-- query re-confirming it. An AVOID that was true LIM.VERIFY_INTERVAL_SECONDS ago is almost
-- always still true -- the gates that produce it (demand/velocity/liquidity limits) do not
-- move on a 30-second clock -- so the walk's scarce one-query-per-tick budget belongs to rows
-- nothing has looked at yet, not to reconfirming a refusal that hasn't had time to change.
LIM.VERIFY_AVOID_INTERVAL_SECONDS = 120
-- The verify walk runs off the same 0.25s ticker as everything else, but the walk itself
-- sorts and filters the whole deals list -- once a second is far more often than a 30s
-- re-check cadence can consume, and four times a second is just wasted work.
LIM.VERIFY_WALK_SECONDS = 1
-- How many items the dormant poll loop watches at once. This, not the arbiter's split, is
-- what shrinks if the cycle proves too slow -- the split only decides who goes first among
-- however many targets there are.
LIM.WATCH_SET_SIZE = 10
-- Per-item floor between rings (stampVerdict): a churning watched item can transition into
-- buyable several times a minute, and every one of those is worth SHOWING, but not worth a
-- separate bell each time. See stampVerdict's own comment for why this is per item, not global.
LIM.RING_FLOOR_SECONDS = 30

local TIER_RANK = { HOT = 1, GOOD = 2, WATCH = 3, SUSPECT = 4 }

local frame           -- lazily created (see createFrame)
local content          -- scroll child frame; module-level so refreshRows() can grow the row pool into it
local rows = {}        -- pooled row widgets, grown lazily up to WIN.ROW_CAP
local dialog           -- the single reusable purchase-confirmation dialog; lazily created (see createDialog)
local deals = {}        -- itemID -> latest watchlist deal shown for it (watchlist mode)
local scanDeals = {}     -- array of deals from the last completed full scan (full-scan mode)
local mode = "watchlist" -- "watchlist" | "fullscan": which backing store sortedDeals() renders
local scanning = false

-- D: top-level Deals/Sell view switcher -- independent of `mode` above (which only picks the
-- watchlist-vs-full-scan backing store WITHIN the Deals view). Default is "deals"; only
-- setView (near createFrame) ever changes it.
local view = "deals"

-- The status line has two dozen writers and no arbiter -- last write wins, and during a scan
-- the per-page progress line lands several times a second. A one-shot answer to a player
-- action (right-click pin, most visibly) was therefore overwritten before it could be read,
-- which made the action itself look dead. setStatus is the arbiter: a write that passes
-- `holdSeconds` claims the line for that long, and held-out writes are DROPPED, not queued --
-- every suppressed writer here is periodic (next page, next poll, next tick re-writes it),
-- so the freshest one after the hold expires is strictly better than a replay of the backlog.
-- One-shot writers that must always land (purchase flow) keep calling SetText directly.
local statusHoldUntil = 0
local function setStatus(text, holdSeconds)
  if not frame then return end
  local now = GetTime()
  if holdSeconds then
    statusHoldUntil = now + holdSeconds
  elseif now < statusHoldUntil then
    return
  end
  frame.status:SetText(text)
end

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
LIM.STALE_YELLOW_SECONDS = 6 * 3600
LIM.STALE_RED_SECONDS = 24 * 3600

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
    --
    -- Except that CancelCommoditiesPurchase produces none of the three terminal events, so an
    -- unconfirmed cancellation used to hold this tombstone until the player happened to close
    -- the Auction House -- and every commodity buy in between was refused with "waiting for
    -- previous commodity purchase to settle". Retire it on a timer instead. This is safe only
    -- because the attempt is unconfirmed: ConfirmCommoditiesPurchase was never called, so no
    -- gold moved and no late event can credit a purchase to a later row. The worst a
    -- misattributed late event can now do is cancel a fresh attempt, which is the fail-safe
    -- direction. A CONFIRMED tombstone is never retired here -- its late success must land.
    -- 10s, written inline rather than as a named constant: this chunk is at Lua's 200-local
    -- ceiling. Longer than LIM.BUY_TIMEOUT_SECONDS so a real terminal event still lands first.
    if not pending.confirmed then
      C_Timer.After(10, function()
        if commodityDraining == pending and not pending.confirmed then
          commodityDraining = nil
        end
      end)
    end
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
-- Slot arbiter. The browse scan and the watch loop are both BACKGROUND consumers of one
-- throttled search slot; `watchTurn` alternates between them so speeding up watching cannot
-- silently stop discovery. Starts true so the watch loop takes the first contested slot -- it
-- is the latency-sensitive one, and the browse scan is a marathon either way.
local watchTurn = true
-- True only for the instant a grant is open. Core/Scanner.lua's advance() reads this through
-- driver.mayScan and will not send outside it, which is what stops it chaining result -> send
-- straight past the arbiter.
local watchGrant = false
-- feedAuto funnels EVERY AutoScan input through one place (instead of bare
-- `autoScan:Input(...)` calls scattered across the file) so the Auto button's label/pulse
-- (refreshAutoButton, assigned once the button itself is built in createFrame) can never
-- drift out of sync with a state transition. Also forward-declared for the same upvalue
-- reason as autoScan.
local feedAuto
local refreshAutoButton
-- Assigned below, once the button exists. Driven off the same 0.25s ticker as
-- refreshAutoButton rather than hooked into all six places scanRunning changes,
-- so a transition can never be added without the button following it.
local refreshScanButton
-- Assigned once the refused-rows toggle exists (createFrame). Forward-declared for the same
-- reason the two above are: refreshRows() re-stamps its count on every render, and that runs
-- long before the button is built.
local refreshVerifyButton
-- Assigned once f.sessionText exists (createFrame). Driven off the same 0.25s ticker as the
-- three refresh* functions above -- same "one place drives it" contract, see the ticker's own
-- comment. Deals-only: early-returns when the module-local `view` isn't "deals" so it can't
-- re-Show the text out from under setView's per-view chrome toggle (dealsChrome).
local refreshSessionText
-- Assigned below (it needs refreshRows and flashRow), forward-declared because
-- applyRequeryResult -- which sits above it -- must record what a real Check just found, or a
-- row could sit there advertising a background verdict the player has since disproved.
local stampVerdict
-- Forward-declared for the same reason as stampVerdict above: driver.onObservation is built
-- far above this function's real definition, so the closure needs the local to already exist
-- at closure-creation time or it would silently bind the global of this name (nil) instead.
local evaluateLiveCommodityDeal

-- Background verification. itemID -> { unitPrice, at, buyable, status, reason }: what a live
-- Check said about this item the last time one was run for it in the background.
--
-- Keyed by itemID and held HERE rather than stamped on the deal table, because a scan pass
-- replaces every deal table wholesale (FullScan.MergeDeals: the incoming row wins
-- unconditionally), which would throw away a verdict that is still perfectly true. `unitPrice`
-- is what keeps carrying it forward honest: the same item at a different asking price was
-- never verified, so verdictFor refuses to match it.
--
-- This is a rendering hint and nothing more. It never arms, approves or shortcuts a purchase
-- -- clicking a row still runs the same live Check it always did (openDialog -> startRequery),
-- and the purchase calls themselves are protected and reachable only from a hardware click.
local verdicts = {}
-- How many of the rows the current render WOULD have shown carry a refusal. Recomputed by
-- renderList on every render and displayed by the toolbar toggle, so a shorter list always
-- comes with the number that explains it.
local refusedCount = 0
-- GetTime() before which tickAutoVerify does not walk the list again -- see LIM.VERIFY_WALK_SECONDS.
local verifyWalkAt = 0

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
  -- Same reasoning, second case: refreshRows() also skips any row carrying a purchaseStage, so
  -- an open Check/Buy freezes that row on its deal. activeItemID is NOT a substitute here --
  -- armCheck deliberately releases the pin (so a second Check can be started) while leaving
  -- purchaseStage set, and that is exactly the window in which the item rendered twice.
  -- Built inline rather than as a file-level helper: this chunk is at Lua's 200-local ceiling.
  local frozen = nil
  for i = 1, #rows do
    local frozenDeal = rows[i].purchaseStage and (rows[i].purchaseDeal or rows[i].deal) or nil
    if frozenDeal and frozenDeal.itemID then
      frozen = frozen or {}
      frozen[frozenDeal.itemID] = true
    end
  end
  local list = {}
  if mode == "fullscan" then
    -- GC.FullScan.Evaluate already returns tier-rank/profit sorted order; filtering out
    -- pinned itemIDs preserves that order (no re-sort needed).
    for _, deal in ipairs(scanDeals) do
      if not activeItemID[deal.itemID] and deal.itemID ~= hoveredItemID
          and not (frozen and frozen[deal.itemID]) then
        list[#list + 1] = deal
      end
    end
    return list
  end
  for itemID, deal in pairs(deals) do
    if not activeItemID[itemID] and itemID ~= hoveredItemID
        and not (frozen and frozen[itemID]) then
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

-- Whether refused rows are currently shown. Default is hidden -- the whole point of verifying
-- in the background is that the list stops offering flips a Check has already ruled out.
local function showRefused()
  local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
  return (cfg and cfg.showRefused) and true or false
end

local function isPinned(itemID)
  for _, pin in ipairs(GC.Sniper._WatchPins()) do
    if pin == itemID then return true end
  end
  return false
end

-- The last unit price any observation reported for this item, so a pinned placeholder shows a
-- real number rather than a dash. Filled by driver.onObservation; nil until the loop has been
-- round the set once, which is why the placeholder must tolerate 0.
local function lastSeenPrice(itemID)
  return GC.Sniper._lastPrice[itemID]
end

-- The verdict that applies to `deal` RIGHT NOW, or nil if it has none.
--
-- Two ways a stored verdict stops applying. A price change voids it outright: what was checked
-- was this item at that asking price, and a fresher scan quoting a different one was never
-- verified. And a SAFE verdict that has gone LIM.VERIFY_TRUST_SECONDS without a refresh stops
-- being advertised -- the row falls back to plain "Check" rather than keep a gold Buy button up
-- on a claim nothing has re-tested. A REFUSAL does not expire that way: refusals come from
-- demand and velocity limits that do not move in two minutes, and expiring them would flicker
-- hidden rows back into the list every couple of minutes for no new information.
local function verdictFor(deal)
  local v = deal and deal.itemID and verdicts[deal.itemID]
  if not v then return nil end
  if v.unitPrice ~= deal.unitPrice then return nil end
  if v.buyable and (GetTime() - v.at) > LIM.VERIFY_TRUST_SECONDS then return nil end
  return v
end

-- The single entry point refreshRows() renders from: sortedDeals()'s own order, with the
-- header-click override (if any) layered on top, and rows a background Check has refused
-- filtered out (unless the toolbar toggle says otherwise).
--
-- The filter is what makes the verify walk work its way DOWN the list: a refused row leaves,
-- the row beneath it moves into the top LIM.VERIFY_TOP_ROWS, and gets checked in its turn. The
-- count it leaves behind in `refusedCount` is not optional -- a silently shorter list is its
-- own lie, so the toolbar carries the number and the switch to see them.
local function renderList()
  local list = applySortOverride(sortedDeals())
  local show = showRefused()
  local kept = {}
  refusedCount = 0
  for i = 1, #list do
    local deal = list[i]
    local verdict = verdictFor(deal)
    -- A pin that is currently a deal is exempt from the refused-rows filter outright -- no
    -- capacity condition attached. `_IsWatched` alone would be wrong here: it is only true for
    -- items that made the poll set's CAPACITY cut, and a pin squeezed out by capacity is still
    -- a pin.
    local pinned = isPinned(deal.itemID)
    -- `manual` rows are never pruned -- see stampVerdict. And they are not counted either:
    -- this number exists to explain a list that got shorter, and they did not shorten it.
    if verdict and not verdict.buyable and not verdict.manual and not pinned then
      refusedCount = refusedCount + 1
      if show then kept[#kept + 1] = deal end
    else
      kept[#kept + 1] = deal
    end
  end

  -- A pin whose item is no longer a deal still gets a row -- dimmed, below everything, with
  -- its live price and no profit. Without this a pin is a roach motel: ApplyLiveObservation
  -- drops an item that stops qualifying, and an invisible pin cannot be right-clicked off.
  -- It is also the thing worth watching: what the item you are watching costs right now.
  for _, itemID in ipairs(GC.Sniper._WatchPins()) do
    local present = false
    for i = 1, #kept do
      if kept[i].itemID == itemID then present = true; break end
    end
    -- The hovered row counts as present. sortedDeals() excludes the item under the cursor
    -- (its row is frozen so the deal cannot change beneath a click), so a pinned item being
    -- hovered is missing from `kept` for that reason alone -- and appending a placeholder for
    -- it here rendered the SAME item twice: the frozen real row under the cursor plus a
    -- dimmed "Watching" twin below it, for as long as the mouse sat still.
    if not present and hoveredRow and hoveredRow.deal
        and hoveredRow.deal.itemID == itemID and hoveredRow:IsShown() then
      present = true
    end
    if not present then
      local lastPrice = lastSeenPrice(itemID)
      -- `_lastPrice` is wiped on every AH close (see OnAuctionHouseClosed), so a fresh session
      -- has no observation for a pin nothing has polled yet. `unitPrice = 0` stays the sentinel
      -- in the table -- `priceUnknown` is what setRowDeal checks before it will render that as
      -- a real number, so a session-old pin never shows a fabricated 0-copper price.
      kept[#kept + 1] = { itemID = itemID, pinPlaceholder = true, unitPrice = lastPrice or 0,
        qty = 1, profit = 0, discount = 0, tier = "WATCH", action = "Check", priceUnknown = lastPrice == nil }
    end
  end

  -- A pin is a standing instruction and outranks the automatic list -- exactly how
  -- WatchSet.Select already reserves pins ahead of the poll set's own capacity, pins first,
  -- then everything else. Two reasons this partition is unconditional, not only past the
  -- row cap. Past the cap it is survival: refreshRows only renders list[1..WIN.ROW_CAP], and
  -- a pin truncated away has no row and so can never be right-clicked off (see clearDeals).
  -- Below the cap it is feedback: the one thing a right-click visibly does RIGHT NOW is move
  -- the row to the top of the board -- the watched items live in one fixed place instead of
  -- wherever the profit sort happens to put them, and the pin action stops reading as dead.
  -- The partition is stable, so relative order within each half is untouched.
  local pinnedRows, otherRows = {}, {}
  for i = 1, #kept do
    local entry = kept[i]
    if isPinned(entry.itemID) then
      pinnedRows[#pinnedRows + 1] = entry
    else
      otherRows[#otherRows + 1] = entry
    end
  end
  for i = 1, #otherRows do pinnedRows[#pinnedRows + 1] = otherRows[i] end
  return pinnedRows
end

local GOLD_COMPACT_THRESHOLD = 100 * 10000 -- 100g in copper

-- GetCoinTextureString's inline coin icons are too wide for a narrow column once gold enters
-- the amount at all: two-digit gold plus a silver coin icon already clipped mid-glyph in game
-- ("15g 4|..."), which reads as a broken number, not a shortened one. Whole-gold amounts
-- collapse to "<N>g"; anything from 1g up shows plain "<N>g<M>s" text; only sub-gold amounts
-- keep the coin icons, where they fit. Negative amounts (a losing profit cell) format their
-- magnitude and keep the sign.
local function formatColumnAmount(copper)
  if copper < 0 then return "-" .. formatColumnAmount(-copper) end
  if copper >= GOLD_COMPACT_THRESHOLD then
    return ("%dg"):format(math.floor(copper / 10000))
  end
  if copper >= 10000 then
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    if silver == 0 then return ("%dg"):format(gold) end
    return ("%dg%02ds"):format(gold, silver)
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
    return ("|cff8c8a85 x%d of %d|r"):format(deal.qty, deal.avail)
  end
  if deal.qty and deal.qty > 1 then
    return ("|cff8c8a85 x%d|r"):format(deal.qty)
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

-- itemID -> { icon, named } once setRowDeal has resolved a name/icon through Item:ContinueOnItemLoad.
-- A quality-colored name and icon are properties of the ITEM, never of a particular deal on it,
-- so a tiered reagent's second sighting (a fresh price, a different row slot, a later render)
-- never needs its own Item object, its own closure, or its own Theme.QualityMarkup tooltip scan.
local nameIconCache = {}

local function setRowDeal(row, deal)
  -- (fix round 1, M3) A pooled row's ping flash must not migrate onto whatever deal gets
  -- reassigned into this same screen slot on the next refresh -- Stop() doesn't fire
  -- OnFinished (that only runs on natural completion), so the flash/alpha reset that
  -- normally happens there has to be done explicitly here too. Only stops on an itemID
  -- CHANGE -- the same item re-stamped with a fresher price (still mid-flash) keeps flashing.
  if row.flashAnim and row.deal and row.deal.itemID ~= deal.itemID then
    row.flashAnim:Stop()
    row.flash:Hide()
    row.flash:SetAlpha(1)
    -- A press that never saw its OnLeave (rows hidden programmatically) must not
    -- carry over to the item that takes this row next.
    row.leftPressed = nil
  end
  row.deal = deal
  -- What the background Check found, if anything. Gold "Buy" is reserved for a row a live
  -- Check has actually approved; an unverified row is a plain ghost "Check", exactly the
  -- two-click flow it always was. Neither label changes what the click DOES: openDialog still
  -- re-verifies live before anything can arm, so an aged hint can only cost a beat, never gold.
  local verdict = verdictFor(deal)
  local pinned = isPinned(deal.itemID)
  local value = GC.Data.GetItemValue(deal.itemID)
  local trend = value and value.trend

  -- refreshRows runs on every browse page while a full scan streams, on every watch-loop
  -- observation, on every verdict stamp, and off the 0.25s ticker -- with up to WIN.ROW_CAP
  -- rows that is a fresh Item object, a fresh ContinueOnItemLoad closure and a Theme.QualityMarkup
  -- tooltip scan per row, several times a second, even for a row whose content never moved.
  -- Skip the whole repaint once nothing the player can actually see has changed since this row
  -- slot was last stamped -- every field folded into `sig` drives a visible pixel below,
  -- including ones the verdict/pin/trend systems can change out from under an unchanged `deal`
  -- object, so this is a value comparison, never an identity (`deal1 == deal2`) one. A hidden
  -- row (pooled slot reused after sitting empty) always falls through and repaints regardless --
  -- otherwise a row that goes empty and comes back showing the exact same deal would stay
  -- invisible, `row:Show()` below being the one thing the skip must never skip.
  local sig = table.concat({
    deal.itemID, deal.unitPrice, deal.qty, tostring(deal.avail), tostring(deal.tier),
    deal.falling and 1 or 0, deal.profit, tostring(deal.discount),
    deal.pinPlaceholder and 1 or 0, deal.priceUnknown and 1 or 0, tostring(deal.action),
    pinned and 1 or 0, (verdict and verdict.status) or "", (verdict and verdict.buyable) and 1 or 0,
    tostring(trend),
  }, "|")
  if row._dealSig == sig and row:IsShown() then
    return
  end
  row._dealSig = sig

  if deal.pinPlaceholder then
    -- Nothing to buy here -- this is a pin that has fallen out of the deals list, not a deal.
    -- The first in-game pass shipped this as a disabled ghost button labeled "Watching", and it
    -- read as a broken control -- a button that looks clickable but never responds. A watched
    -- item that is not currently a deal is information, not an action, so the row hides the
    -- button entirely instead of faking one that does nothing; the name gets a dim suffix
    -- (below) and OnEnter's tooltip spells it out. Hiding row.buy also does double duty: this
    -- row's own left-click handler (below) only fires when `row.buy:IsShown() and
    -- row.buy:IsEnabled()`, so a hidden button already makes the whole row un-clickable with no
    -- second guard needed.
    --
    -- Hide() alone is not enough: a column re-layout (applyColumnVisibility, triggered e.g. by
    -- the check panel opening/closing) re-runs anchorColumns over every pooled row, and
    -- anchorColumns unconditionally cell:Show()s every VISIBLE fixed column -- including this
    -- one, since "buy" is a fixed column, never one of the responsive optional ones a re-layout
    -- can drop. Disable() keeps the button inert even where layoutRow's own placeholder re-Hide
    -- (below) is bypassed or raced.
    row.buy:Hide()
    row.buy:Disable()
    row:SetAlpha(0.55)
  else
    row:SetAlpha(1)
    row.buy:Show() -- undo the placeholder branch's Hide() for a pooled row reused after a placeholder
    row.buy:Enable()
    if verdict and verdict.buyable then
      row.buy:SetLabel("Buy")
      row.buy:SetVariant("primary")
    elseif verdict then
      -- Only reachable with the toolbar toggle showing refused rows; the status is the engine's
      -- own word for it, and the row tooltip (createRow's OnEnter) carries the reason.
      row.buy:SetLabel(verdict.status or "Avoid")
      row.buy:SetVariant("ghost")
    else
      row.buy:SetLabel(deal.action or "Check")
      row.buy:SetVariant("ghost")
    end
  end
  -- The left rail is the row's state edge, and "the watch loop is polling this" is a state that
  -- has to be readable while you are looking somewhere else. Without it, right-clicking a row
  -- that is still a deal changed nothing visible at all -- the pin only became apparent later,
  -- when the item fell out of the list and reappeared as a "Watching" placeholder, which reads
  -- as the addon doing something on its own.
  --
  -- Blue stays up even under the cursor: hover already announces itself with the full-row
  -- highlight wash, so there is nothing to gain from also taking the rail and everything to
  -- lose -- the one row you are pointing at would be the one row that stops telling you.
  if pinned then
    row.rail:SetColorTexture(Theme.color.watch[1], Theme.color.watch[2], Theme.color.watch[3])
    row.rail:Show()
    row.pinBg:Show()
  else
    row.rail:SetColorTexture(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3])
    if hoveredRow ~= row then row.rail:Hide() end
    row.pinBg:Hide()
  end
  local color = Theme.tier[deal.tier] or Theme.tier.WATCH
  row.tierChip:SetLabel(tierLabel(deal), color)

  -- A pin placeholder is not a deal -- there is nothing to discount against, so this cell says
  -- nothing rather than the "0%" renderList's placeholder table (discount = 0, kept for callers
  -- that need a number) would otherwise print.
  if deal.pinPlaceholder then
    row.discountText:SetText("—")
    row.discountText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  else
    row.discountText:SetText(("%d%%"):format(math.floor(deal.discount * 100 + 0.5)))
    row.discountText:SetTextColor(color[1], color[2], color[3])
  end

  -- A placeholder pin with nothing observed yet has no price to show -- deal.unitPrice is only
  -- the sentinel 0 kept in the table for callers that need a number. Rendering it through
  -- formatColumnAmount would print a literal 0-copper price nothing polled, so it gets the same
  -- dimmed em-dash the trend column below already uses for its own unknown state.
  if deal.priceUnknown then
    row.unitText:SetText("—")
    row.unitText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
    row.priceText:SetText("—")
    row.priceText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  elseif deal.pinPlaceholder then
    -- A real price WAS observed for this pin (lastSeenPrice), but a placeholder's qty is
    -- always the sentinel 1 -- unitPrice*qty is never an actual total, just the same unit
    -- price rendered a second time ("20g/20g"). Show the one real number (what it costs per
    -- unit right now) and nothing where a total was never actually quoted.
    row.unitText:SetText(formatColumnAmount(deal.unitPrice))
    row.unitText:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
    row.priceText:SetText("—")
    row.priceText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  else
    row.unitText:SetText(formatColumnAmount(deal.unitPrice))
    row.unitText:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
    row.priceText:SetText(formatColumnAmount(deal.unitPrice * deal.qty)) -- total cost, not per-unit
    row.priceText:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
  end

  -- A pin placeholder has no deal to have made a profit on -- this cell says nothing rather
  -- than a formatted 0-copper coin string (profit = 0, the same placeholder sentinel).
  if deal.pinPlaceholder then
    row.profitText:SetText("—")
    row.profitText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  else
    row.profitText:SetText((deal.profit > 0 and "+" or "") .. formatColumnAmount(deal.profit))
    if deal.profit >= 0 then
      row.profitText:SetTextColor(Theme.color.green[1], Theme.color.green[2], Theme.color.green[3])
    else
      row.profitText:SetTextColor(Theme.color.red[1], Theme.color.red[2], Theme.color.red[3])
    end
  end

  -- Sniper v3 trend column: mirrors the dialog's own value.trend read (updateDialogAmounts)
  -- -- import-sourced values only, absent for bundled/no-import (dim dash then). Reads
  -- GC.Data.GetItemValue directly rather than through `driver` -- `driver` (below) isn't
  -- declared yet at this point in the file, and driver.getValue is that same function anyway.
  if trend then
    local glyph = trend < 0 and "▼" or "▲"
    row.trendText:SetText(("%s%d%%"):format(glyph, math.abs(trend)))
    local tc = trend < 0 and Theme.color.red or Theme.color.green
    row.trendText:SetTextColor(tc[1], tc[2], tc[3])
  else
    row.trendText:SetText("—")
    row.trendText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  end

  -- A quality-colored name and icon are properties of the item, not of this particular deal on
  -- it -- once resolved for an itemID they never change, so a second sighting (a fresher price,
  -- a different pooled row slot, a later render) is served from cache instead of paying for
  -- another Item object, another closure and another QualityMarkup tooltip scan.
  --
  -- A placeholder pin is watched, not up for sale -- the dim "· watching" suffix goes AFTER the
  -- qty suffix (its own color code so it never inherits the quality-colored name), on every path
  -- that stamps nameText below, including the async ContinueOnItemLoad callback that can land
  -- well after this call returns.
  local watchSuffix = deal.pinPlaceholder and "|cff8c8a85 · watching|r" or ""
  local cached = nameIconCache[deal.itemID]
  if cached then
    row.icon:SetTexture(cached.icon)
    row.nameText:SetText(cached.named .. qtySuffix(deal) .. watchSuffix)
  else
    row.nameText:SetText(("item %d"):format(deal.itemID) .. qtySuffix(deal) .. watchSuffix)
    row.icon:SetTexture(nil)

    local item = Item:CreateFromItemID(deal.itemID)
    item:ContinueOnItemLoad(function()
      if row.deal ~= deal then return end -- row was repurposed before the async load finished
      local icon = item:GetItemIcon()
      local quality = item:GetItemQuality()
      local qc = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
      local label = item:GetItemName() or ("item " .. deal.itemID)
      -- Reagent quality in front of the name. Two tiers of the same reagent are
      -- separate itemIDs and so already price separately -- this is identification,
      -- not arithmetic, but on a list of ores and herbs it is the difference
      -- between reading a row and guessing at it.
      local named = (qc and qc:WrapTextInColorCode(label) or label)
      if Theme.QualityMarkup then
        local pip = Theme.QualityMarkup(deal.itemID, 12)
        if pip ~= "" then named = pip .. " " .. named end
      end
      nameIconCache[deal.itemID] = { icon = icon, named = named }
      row.icon:SetTexture(icon)
      row.nameText:SetText(named .. qtySuffix(deal) .. watchSuffix)
    end)
  end

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
-- The row pool grows lazily up to `shown` (itself capped at WIN.ROW_CAP) instead of being
-- pre-built at a fixed size: full scans can return far more deals than the old
-- watchlist-only 20-row pool ever needed to hold. `shown` also bounds how many entries of
-- `list` get consumed even if `list` itself is longer (already true for full-scan mode,
-- since GC.FullScan.Evaluate caps to 100 -- this is just a second belt-and-suspenders cap
-- local to rendering). The scroll child's height is stamped every refresh so
-- GetVerticalScrollRange() has something to report once there are more rows than fit.
local function refreshRows()
  if not frame then return end
  local list = renderList()
  local shown = math.min(#list, WIN.ROW_CAP)

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
        row.leftPressed = nil
        row:Hide()
      end
    end
  end

  content:SetHeight(math.max(shown, 1) * WIN.ROW_HEIGHT)
  -- renderList() just recomputed refusedCount for exactly this list -- publish it in the same
  -- breath, so the number beside the list can never describe a different render than the one
  -- on screen. (The 0.25s ticker also calls it, for the window's first paint.) The empty-state
  -- panel is driven from the same spot for the same reason: it describes THIS render.
  if GC.Sniper._UpdateEmptyState then GC.Sniper._UpdateEmptyState(shown) end
  if refreshVerifyButton then refreshVerifyButton() end
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
  elseif age < LIM.STALE_YELLOW_SECONDS then
    frame.staleText:Hide()
  elseif age < LIM.STALE_RED_SECONDS then
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

-- The board's empty state. An empty list used to be exactly that -- rows silently absent,
-- with the only explanations living in a toolbar counter and a scan-completion status line
-- that the next write erased. That is the TSM failure mode this addon exists to avoid: the
-- filters work, and the player concludes the sniper is broken. When nothing renders, say WHY
-- nothing renders, in the space where the rows would be, picking the dominant cause: no realm
-- import (nothing can pass the safety pre-screen without one), everything filtered/refused
-- (with the counts and where to review them), or genuinely nothing scanned yet.
-- Exposed on GC.Sniper (not a local) so the spec suite can drive it directly.
function GC.Sniper._UpdateEmptyState(shownCount)
  local label = frame and frame.emptyText
  if not label then return end
  if shownCount > 0 or view ~= "deals" or scanRunning then
    label:Hide()
    return
  end
  local screened = GC.Sniper._screenedCount or 0
  local text
  if not importAgeSeconds() then
    text = "No deals to show -- and no realm prices imported.\n"
      .. "Without an import, almost nothing can be safety-checked.\n"
      .. "Get your realm's data at goldcap.gg, then type /goldcap import."
  elseif refusedCount > 0 or screened > 0 then
    local parts = {}
    if screened > 0 then
      parts[#parts + 1] = ("%d filtered out as hard to resell"):format(screened)
    end
    if refusedCount > 0 then
      parts[#parts + 1] = ("%d refused by live checks -- press \"HIDDEN %d\" above to review them"):format(
        refusedCount, refusedCount)
    end
    text = "No deals passed the safety checks right now.\n" .. table.concat(parts, "\n")
  else
    text = "No deals yet.\nPress Scan to search the whole auction house once, or Auto to keep scanning."
  end
  label:SetText(text)
  label:Show()
end

-- One chat print per UI session (not per AH visit -- staleWarnedThisSession only resets on
-- /reload) the first time the import is found stale on AH open.
local function maybeWarnStale()
  if staleWarnedThisSession then return end
  local age = importAgeSeconds()
  if age and age < LIM.STALE_RED_SECONDS then return end -- fresh or yellow: no warning yet
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
  -- One mapping, in SniperDecision, shared with the scan's pre-screen: a second copy here
  -- would drift the first time a field is renamed on the import side.
  return GC.SniperDecision.MarketFromValue(GC.Data.GetItemValue(itemID))
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
--
-- Forward-declared, then filled by a plain `driver = {...}` assignment below rather than
-- `local driver = {...}` in one step: onObservation (a field of this same literal) needs to
-- call driver.commodityResult, and a name first bound by the `local` statement that CONTAINS
-- the literal is not in scope until that statement finishes -- referenced from inside the
-- literal it would resolve to an unset global instead. Splitting the declaration from the
-- assignment (same idiom as resolvePurchase/stampVerdict/evaluateLiveCommodityDeal above) puts
-- `driver` in scope before the closures that capture it are even parsed.
local driver
driver = {
  isReady = function()
    return C_AuctionHouse.IsThrottledMessageSystemReady()
  end,

  mayScan = function()
    -- Shared throttle budget: while the player is busy on Blizzard's own AH panes -- posting,
    -- buying a browse result, or reading their own search -- their click outranks every
    -- watch-loop poll.
    if GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy and GC.AuctionHouseTab.PlayerIsBusy() then
      return false
    end
    return watchGrant
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
    -- all there is. Same bounded LIM.MAX_BOOK_LEVELS idiom driver.commodityBook uses below, kept as
    -- its own small loop rather than calling commodityBook itself: this only needs a running
    -- total, not the per-level array GC.Book.Fill consumes.
    local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    local avail
    if n and n > 0 then
      if n > LIM.MAX_BOOK_LEVELS then n = LIM.MAX_BOOK_LEVELS end
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
    if n > LIM.MAX_BOOK_LEVELS then n = LIM.MAX_BOOK_LEVELS end
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
    if n > LIM.MAX_BOOK_LEVELS then n = LIM.MAX_BOOK_LEVELS end
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
    -- setStatus, not SetText: the poll loop writes this on every send, and it must not be
    -- able to stamp over a held one-shot announcement (right-click pin feedback, most
    -- visibly) within the same second the player acted.
    setStatus(text)
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
    -- No PlaySound here, deliberately. A DealMath tier is a lead, not a promise -- ringing is
    -- the verdict path's job: stampVerdict rings on the transition into buyable, once, floored
    -- 30 seconds per item. Doing it here as well would ring on every "HOT" poll result with
    -- neither the verdict gate nor that floor in the way.
  end,

  onObservation = function(itemID, deal)
    if GC.Sniper._liveTracksScanDeals then
      scanDeals = GC.FullScan.ApplyLiveObservation(scanDeals, itemID, deal, WIN.ROW_CAP)
    else
      deals[itemID] = deal
    end
    -- Built once and threaded through below (to evaluateLiveCommodityDeal and to the
    -- observation recorder) instead of letting each ask driver.commodityBook for its own copy
    -- of the same already-fetched poll.
    local book = driver.commodityBook(itemID)
    -- The poll has just pulled this item's live book, which is exactly what a verdict is
    -- computed from -- so compute it here, for nothing. A watched item therefore never costs
    -- tickAutoVerify a query, and the ring it may produce goes through the one shared
    -- transition path rather than a second notion of "buyable".
    if deal and GC.Sniper._IsWatched(itemID) then
      stampVerdict(deal, evaluateLiveCommodityDeal(itemID, book))
    end
    -- The live price this observation just fetched, independent of whether it qualified as a
    -- deal (DealMath.Evaluate above returns nil `deal` for a price that isn't cheap enough --
    -- which is exactly the state a pin sits in most of the time). See lastSeenPrice.
    -- commodityResult is nil for a non-commodity (item-class) itemID -- GetCommoditySearchResultInfo
    -- has nothing to say about it -- so fall back to itemResult, which is what this same poll
    -- actually queried for such an item (see driver.getKeyInfo/sendSearch above).
    local live = driver.commodityResult(itemID)
    local unitPrice = live and live.unitPrice
    if not unitPrice then
      local itemLive = driver.itemResult(itemID)
      unitPrice = itemLive and itemLive.unitPrice
    end
    if unitPrice then GC.Sniper._lastPrice[itemID] = unitPrice end
    -- Live observation for the export pipeline. Commodities get the real
    -- book (driver.commodityBook reads already-fetched results, no query);
    -- item searches only ever read the top listing here, so the observation
    -- is the floor alone -- listings/totalQty stay honestly absent. Guarded
    -- like every other cross-module call in this file: specs load only the
    -- modules a given test needs, so GC.Book/GC.Data/GC.Ledger may be absent
    -- outside the client.
    if GC.Data and GC.Data.RecordLiveObservation then
      local region = GC.Ledger and GC.Ledger.Context and GC.Ledger.Context().region
      local recordBook = live and live.avail and book or nil
      local summary = GC.Book and GC.Book.Summarize(recordBook)
      if summary then
        GC.Data.RecordLiveObservation(GC.db, { itemID = itemID,
          region = region, minUnit = summary.minUnit,
          listings = summary.listings, totalQty = summary.totalQty,
          levels = recordBook }, time())
      elseif unitPrice then
        GC.Data.RecordLiveObservation(GC.db, { itemID = itemID,
          region = region, minUnit = unitPrice }, time())
      end
    end
    refreshRows()
  end,

  now = time,
}

-- D: keeps the Sell rail button's count badge current. Called after a purchase (a new flip may
-- now exist), on every AH open (bag counts may have changed since a mailbox visit), and by
-- SellFrame.lua itself after Post/Remove/a bag-count refresh -- one shared place instead of
-- every call site re-deriving the badge. Safe to call before the frame/tab exist yet.
local function updateSellTabLabel()
  if not frame or not frame.sellTab then return end
  local n = GC.Sell.SellableCount and GC.Sell.SellableCount() or 0
  frame.sellTab:SetBadge(n > 0 and n or nil)
end
GC.Sniper.UpdateSellTabLabel = updateSellTabLabel

-- UI/SettingsFrame.lua's RESET WINDOW button needs the real built-in default to restore --
-- exposed here (a table field, not a new top-level local: this file sits at its 200-local
-- ceiling) rather than SettingsFrame.lua mirroring WIN.FRAME_WIDTH/HEIGHT in its own copy,
-- which is exactly how that file's old default silently went stale (640x520, while this
-- window's real default had already moved on -- WIN.FRAME_WIDTH/HEIGHT above are the current
-- numbers, so read those rather than trusting a second hardcoded pair here too).
function GC.Sniper.DefaultWindowSize() return WIN.FRAME_WIDTH, WIN.FRAME_HEIGHT end

local function clearDeals()
  for itemID in pairs(deals) do deals[itemID] = nil end
  refreshRows()
end

-- The Live scan loop no longer has a manual way to start -- its button is gone (see
-- createFrame), and nothing calls startScanning, so `scanning` itself is still permanently
-- false. But `_liveTargets` is no longer permanently empty: GC.Sniper._RefreshWatchSet
-- populates it from the watch set (churn + pins) and starts the scanner on it whenever
-- membership changes. Read every `if scanning` below with the manual path in mind: those
-- branches exist to yield the single throttled search slot to a Check, and there is still
-- nothing manual to yield it from -- the watch loop's own contention for that slot goes
-- through the arbiter (GC.Sniper._GrantWatchSlot), not through `scanning`.
--
-- What is deliberately NOT removed: GC.Sniper.scanner itself, which Core/Init.lua
-- still feeds events to, and the pause/resume pair, which the Check requery path
-- calls unconditionally. startRequery sends its own search and only pauses the
-- scanner as a courtesy, so with the manual loop stopped the whole Check flow is
-- unchanged apart from a contention it no longer has. Restoring Live means
-- restoring one function and one button, not untangling this.
function GC.Sniper._ResumeLiveScanner()
  if not GC.Sniper.scanner or #GC.Sniper._liveTargets == 0 then return end
  GC.Sniper.scanner:Resume()
  scanning = true
end

local function stopScanning()
  if GC.Sniper.scanner then GC.Sniper.scanner:Stop() end
  scanning = false
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

-- New-HOT-deal ping (spec §3): 1.5s flash on the row's OWN dedicated texture (`row.flash`,
-- built alongside `row.highlight` in createRow). It used to reuse row.highlight itself,
-- which left the hover wash inheriting whatever alpha the fade animation had last written to
-- it. row.flashAnim (built once per pooled row in createRow) owns an Alpha animation fading
-- row.flash from full brightness to 0; its OnFinished (also wired in createRow) hides
-- row.flash and resets its alpha, entirely independent of hover state -- the highlight is
-- shown/hidden purely by OnEnter/OnLeave now.
local function flashRow(row)
  if not row.flashAnim then return end
  row.flash:SetAlpha(1)
  row.flash:Show()
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
  -- A sniper is an alarm, not a dashboard (the pattern every dedicated sniping addon ships:
  -- PBS's Alert, AnS's flashWoWIcon): a HOT deal found while the player is alt-tabbed must
  -- reach them, and FlashClientIcon is the platform's one sanctioned way to flash the
  -- taskbar/dock icon. Guarded: absent in the headless test environment.
  if matched and FlashClientIcon then
    FlashClientIcon()
  end
end

local function applyFullScanResults(rowsList, groupCount)
  local screened
  scanDeals, screened = GC.FullScan.Evaluate(rowsList, GC.Data.GetItemValue, GC.db.settings.sniper, 100)
  GC.Sniper._screenedCount = screened or 0
  GC.Sniper._churnSeq = GC.Sniper._churnSeq + 1
  GC.WatchSet.Observe(GC.Sniper._churn, scanDeals, GC.Sniper._churnSeq)
  GC.Sniper._RefreshWatchSet()
  -- A browse result is a per-itemKey aggregate across every seller of that item group, not a
  -- single resolved auction: isCommodity is unknown here and auctionID is always nil. Mark
  -- every deal `.stale` so onBuyClick knows to requery live before it will let one arm for
  -- purchase, instead of ever placing a bid/commodity purchase off the aggregate.
  for _, deal in ipairs(scanDeals) do
    deal.stale = true
  end
  if frame then
    -- Name the rows the pre-screen removed rather than presenting a shorter list as if it were
    -- the whole market: a player who cannot see the number cannot tell a quiet market from a
    -- strict filter.
    local hidden = (GC.Sniper._screenedCount or 0) > 0
      and (", %d hidden as unsellable"):format(GC.Sniper._screenedCount) or ""
    -- setStatus, not SetText: under Auto this recurs every few seconds, so losing one to a
    -- held announcement costs nothing -- the next pass rewrites it.
    setStatus(("full scan complete: %d deal%s from %d item group%s%s"):format(
      #scanDeals, #scanDeals == 1 and "" or "s", groupCount, groupCount == 1 and "" or "s", hidden))
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

function GC.Sniper._WatchPins()
  local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
  return (cfg and cfg.watchPins) or {}
end

function GC.Sniper._IsWatched(itemID)
  for i = 1, #GC.Sniper._liveTargets do
    if GC.Sniper._liveTargets[i] == itemID then return true end
  end
  return false
end

-- Recomputes the target list and restarts the loop ONLY if membership actually changed.
-- Restarting is not free: Scanner:Start wipes alertedCommodity/alertedAuctions, so a needless
-- restart re-arms every alert and would ring for lots that have been sitting there all along.
function GC.Sniper._RefreshWatchSet()
  local targets = GC.WatchSet.Select(GC.Sniper._churn, GC.Sniper._WatchPins(), LIM.WATCH_SET_SIZE)
  local current = GC.Sniper._liveTargets
  -- Membership, not order. Select ranks by recency among other things, so a fresh observation
  -- on an ALREADY-watched item can re-rank it without changing who is watched -- and treating
  -- that as a change would restart the scanner, wiping alertedCommodity/alertedAuctions and
  -- re-arming an alert for every lot that has been sitting there untouched. Order genuinely
  -- does not matter: the poll is round-robin and visits every member either way. Returning
  -- without touching `current` is deliberate too -- the scanner is actively indexing into that
  -- exact table, so there is nothing to gain from reshuffling it underneath the index.
  local same = #targets == #current
  if same then
    local have = {}
    for i = 1, #current do have[current[i]] = true end
    for i = 1, #targets do
      if not have[targets[i]] then same = false; break end
    end
  end
  if same then return end

  for i = #current, 1, -1 do current[i] = nil end
  for i = 1, #targets do current[i] = targets[i] end

  -- A different set is a different measurement: the pass the loop was timing no longer visits
  -- the same members, so its partial count means nothing against the new one.
  GC.Sniper._passStartedAt = GetTime()
  GC.Sniper._grants = 0
  GC.Sniper._cycleSeconds = nil

  if not GC.Sniper.scanner then return end
  if #current == 0 then
    GC.Sniper.scanner:Stop()
    return
  end
  -- Observations rewrite the full-scan list in place (FullScan.ApplyLiveObservation) rather
  -- than the watchlist map -- the board the player is looking at is scanDeals.
  GC.Sniper._liveTracksScanDeals = true
  GC.Sniper.scanner:Start(current)
end

-- Adds or removes a pin, persists it, and refreshes both the watch set (so the loop starts
-- polling it -- or stops, if nothing else keeps it alive) and the rendered list (so a newly
-- pinned/unpinned row shows up or drops its placeholder immediately, not on the next tick).
-- Says out loud what just happened. A right-click that silently edits a saved list is
-- indistinguishable from a right-click that did nothing, and the only other evidence -- the row
-- turning into a "Watching" placeholder -- arrives minutes later, when the item happens to fall
-- out of the deals list. By then it reads as the addon acting on its own.
local function announcePin(itemID, watching)
  if not frame or not frame.status then return end
  local name
  if Item and Item.CreateFromItemID then
    local ok, item = pcall(Item.CreateFromItemID, Item, itemID)
    if ok and item and item.GetItemName then name = item:GetItemName() end
  end
  name = name or ("item " .. tostring(itemID))
  -- Held for a few seconds: without the hold, the next scan page / poll status overwrote this
  -- within a frame or two, and the right-click read as having done nothing at all.
  setStatus(watching
    and ("watching %s closely -- re-checked every few seconds"):format(name)
    or ("stopped watching %s"):format(name), 4)
end

-- The row the pin was toggled on is, by definition, under the cursor -- and refreshRows()
-- deliberately skips the hovered row to keep its content stable across streaming renders.
-- That skip is right for streaming and exactly wrong here: it suppressed the rail/label
-- repaint on the ONE row the player is looking at, so the click showed no change where the
-- eyes were. Repaint that row explicitly (setRowDeal re-reads the pin state; its signature
-- includes the pinned bit, so this is never a wasted repaint) and flash it.
local function repaintToggledRow(itemID)
  local row = hoveredRow
  if not (row and row.deal and row.deal.itemID == itemID) then return end
  setRowDeal(row, row.deal)
  flashRow(row)
end

function GC.Sniper._TogglePin(itemID)
  local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
  if not cfg or not itemID then return end
  cfg.watchPins = cfg.watchPins or {}
  for i = 1, #cfg.watchPins do
    if cfg.watchPins[i] == itemID then
      table.remove(cfg.watchPins, i)
      GC.Sniper._RefreshWatchSet()
      refreshRows()
      repaintToggledRow(itemID)
      announcePin(itemID, false)
      return
    end
  end
  cfg.watchPins[#cfg.watchPins + 1] = itemID
  GC.Sniper._RefreshWatchSet()
  refreshRows()
  repaintToggledRow(itemID)
  announcePin(itemID, true)
end

-- Right-click pin dispatch for deal rows; createRow wires BOTH mouse phases here. A desktop
-- mouse delivers down then up for one press; a macOS trackpad two-finger tap was observed to
-- deliver only one of the two (the original OnMouseUp-only handler never fired from a tap,
-- which is why the handler moved to OnMouseDown -- betting on the other single phase). The
-- latch makes one physical press toggle exactly once whichever subset arrives: a down always
-- toggles and arms the latch, an up toggles only when no down armed it (and disarms it either
-- way, so a down-then-up press over two different rows can never toggle the second row).
function GC.Sniper._RowPinEvent(row, phase, button)
  if button ~= "RightButton" or not row.deal then return end
  if phase == "down" then
    GC.Sniper._pinPressLatch = true
    GC.Sniper._TogglePin(row.deal.itemID)
  else
    if GC.Sniper._pinPressLatch then
      GC.Sniper._pinPressLatch = nil
      return
    end
    GC.Sniper._TogglePin(row.deal.itemID)
  end
end

-- Re-armed after every send (the initial SendBrowseQuery and each RequestMoreBrowseResults).
-- If no browse event has landed by the time this fires, the paging chain has genuinely
-- stalled -- clear scan state instead of leaving the status frozen forever. Browse queries
-- have no server cooldown, so retrying costs nothing; the status line says so.
local function armScanWatchdog(token)
  local sentAt = time()
  C_Timer.After(LIM.SCAN_WATCHDOG_SECONDS, function()
    if token ~= fullScanToken or not scanRunning then return end -- superseded, aborted, or already finished
    if lastBrowseEventAt < sentAt then
      scanRunning = false
      pendingBrowsePage = false
      if frame then
        -- (fix round 1, M6) "press Full Scan to retry" is dead advice while Auto is armed --
        -- the feedAuto("scanFinished") below already queues its own breather-delayed retry,
        -- and the very next Tick/refreshAutoButton call would immediately overwrite a
        -- "press Full Scan" line with "AUTO · SCANNING" anyway. Pick the text off the
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
      -- silently hanging with the button stuck on "AUTO · SCANNING".
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
    -- The config is not optional here even though RowsFromBrowse tolerates its absence: the
    -- quantity every row advertises is now SniperDecision's own demand cap, and that cap reads
    -- maxDailyDemandShare/maxQuantity off these settings. Omitting it does not fall back to the
    -- old sold/day estimate -- it fails closed to a quantity of 1 for every row on the board,
    -- silently, which reads as "the scan found nothing worth buying" rather than as a bug.
    local tailRows = GC.FullScan.RowsFromBrowse(tail, GC.Data.GetItemValue, GC.db.settings.sniper)
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
    -- The third return is the pre-screen's removal count for THIS page. It used to be
    -- discarded here, which meant the "hidden as unsellable" number stayed at zero for the
    -- whole streaming phase and only appeared at the final reconcile -- mid-scan, a heavily
    -- filtered board was indistinguishable from a quiet market. Accumulate it as pages land;
    -- applyFullScanResults overwrites it with the authoritative full-walk count at the end.
    local deltaDeals, newRowsCount, deltaScreened = GC.FullScan.EvaluateDelta(
      streamRows, streamRowsCount, GC.Data.GetItemValue, GC.db.settings.sniper)
    streamRowsCount = newRowsCount
    GC.Sniper._screenedCount = (GC.Sniper._screenedCount or 0) + (deltaScreened or 0)
    for _, deal in ipairs(deltaDeals) do
      deal.stale = true
    end
    -- Sniper v3 §3 ping (fix round 1, I6): GC.FullScan.CollectNewHot is the SAME pure helper
    -- applyFullScanResults' own completion branch uses, against the same seenHotDeals set --
    -- see that call site's comment for why both branches need their own pass.
    local pingDeals = GC.FullScan.CollectNewHot(deltaDeals, seenHotDeals)
    GC.Sniper._churnSeq = GC.Sniper._churnSeq + 1
    GC.WatchSet.Observe(GC.Sniper._churn, deltaDeals, GC.Sniper._churnSeq)
    GC.Sniper._RefreshWatchSet()
    scanDeals = GC.FullScan.MergeDeals(scanDeals, deltaDeals, 100)
    refreshRows()
    if #pingDeals > 0 then pingNewHotDeals(pingDeals) end
    -- Spec: no page % (Blizzard doesn't expose total pages) -- result count + running deal
    -- count instead, plus the running pre-screen count so a strict filter is visible WHILE it
    -- filters. setStatus, not SetText: this line lands on every page, and it must lose to a
    -- held one-shot announcement (see setStatus).
    local screenedNote = (GC.Sniper._screenedCount or 0) > 0
      and (" · %d hidden"):format(GC.Sniper._screenedCount) or ""
    setStatus(("scanning… %d results · %d deals%s"):format(n, #scanDeals, screenedNote))
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
    setStatus("auto off")
  else
    setStatus("auto: paused")
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
  GC.Sniper._screenedCount = 0 -- fresh pass, fresh pre-screen tally (accumulated per page while streaming)
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
    -- Shared throttle budget: while the player is busy on Blizzard's own AH panes -- posting,
    -- buying a browse result, or reading their own search -- their click outranks a fresh
    -- background scan. The FSM's own state still advances to SCANNING regardless (see
    -- AutoScan.lua's Tick) -- this only withholds the send, and the very next tick after the
    -- player is no longer busy starts a real scan.
    if GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy and GC.AuctionHouseTab.PlayerIsBusy() then return end
    startFullScan()
  end,
  abortScan = cancelFullScan,
})

feedAuto = function(event)
  autoScan:Input(event, GetTime())
  if refreshAutoButton then refreshAutoButton() end
end

local AUTO_PAUSE_LABEL = { dialog = "buying", search = "searching", mail = "mail", sell = "selling" }
-- Display priority when more than one pause reason is set at once (e.g. a buy dialog opened
-- while the player's own search was already live) -- "buying" wins because it's the most
-- decisive of the four: the player is one click from spending gold. `ah`/`tab` are
-- deliberately absent -- per spec they render as plain "AUTO", not a paused chip, since
-- neither reflects something the player is actively DOING right now.
local AUTO_PAUSE_ORDER = { "dialog", "search", "mail", "sell" }

local function autoButtonText(state, reasons)
  if state == "SCANNING" then return "AUTO · SCANNING" end
  if state == "PAUSED" then
    for _, reason in ipairs(AUTO_PAUSE_ORDER) do
      if reasons[reason] then return "AUTO · PAUSED: " .. AUTO_PAUSE_LABEL[reason] end
    end
  end
  return "AUTO" -- OFF, IDLE, WAITING, or PAUSED with only ah/tab reasons
end

-- Re-derives the Auto control's label and look from the machine's own State()/PauseReasons()
-- -- called after every feedAuto() input and once per Tick (see the autoScanTicker set up in
-- GC.Sniper.OnAuctionHouseShow), so the button can never show a state the machine itself has
-- already moved past.
--
-- ONE button with two variants, not two overlaid buttons swapped by Show/Hide. The swap was
-- there because Theme.Button used to capture its colors at construction, making a repaint
-- impossible; Theme.Button:SetVariant now exists, so the swap can go. It was the direct cause
-- of the control feeling broken: hiding a frame under a stationary cursor does not reliably
-- deliver OnLeave or OnEnter, so hovers were missed and the button that came back was painted
-- for a state it was no longer in. The scanning alpha pulse went with it -- on a near-black
-- panel it read as the button dimming to grey rather than as a heartbeat, which is exactly the
-- "it goes black" the owner reported. Scanning is said in words instead.
--
-- `targetFrame` (fix round 1, M1): createFrame calls this with its own local `f` right
-- before returning, since the module-level `frame` upvalue isn't assigned until AFTER
-- createFrame() returns (see GC.Sniper.Toggle()/OnAuctionHouseShow's `frame = frame or
-- createFrame()`) -- without this the very first Auto label paint would have to wait for a
-- later feedAuto/Tick instead of reflecting the freshly-built window immediately. Every other
-- caller (the ticker, feedAuto) omits it and falls back to the module-level `frame`.
refreshAutoButton = function(targetFrame)
  local f = targetFrame or frame
  if not f or not f.autoBtn then return end
  local state = autoScan:State()
  local on = state ~= "OFF"
  if f.autoBtn.lastOn ~= on then
    f.autoBtn.lastOn = on
    -- `active`, not `primary`: primary is dark text on a gold fill, so the label is only legible
    -- while that fill is painted, and the owner saw it reduced to near-black text on a dark
    -- button. `active` carries the on-state in gold text, which cannot become unreadable.
    f.autoBtn:SetVariant(on and "active" or "ghost")
  end
  local text = on and autoButtonText(state, autoScan:PauseReasons()) or "AUTO"
  if f.autoBtn.lastText ~= text then
    f.autoBtn:SetLabel(text)
    f.autoBtn.lastText = text
  end
end

-- Scan did its work in silence. The status line said "scanning auction
-- house..." but it sits at the far left of the toolbar, a window's width away
-- from the button that was just pressed, and the button itself did not move --
-- so the honest read of a press was "nothing happened". Same class of defect as
-- the Repost that refreshed a quote and returned without saying so.
--
-- The button now carries its own state, the way Auto already does.
refreshScanButton = function(targetFrame)
  local f = targetFrame or frame
  if not f or not f.fullScanBtn then return end
  local busy = scanRunning or pendingFullScanStart
  if f.fullScanBtn.lastBusy == busy then return end
  f.fullScanBtn.lastBusy = busy
  f.fullScanBtn:SetLabel(busy and "SCANNING…" or "SCAN")
  -- `active`, not `primary`, and not Disable(): a disabled button reads as
  -- broken, and the click while busy has something useful to say (see
  -- onFullScanClick). Same reasoning as the Auto button's on-state.
  f.fullScanBtn:SetVariant(busy and "active" or "ghost")
end

-- Re-derives the toolbar's session readout from GC.Sniper.session (buys/spent/estProfit).
-- Same "one place drives it" contract as refreshAutoButton/refreshScanButton/refreshVerifyButton
-- above -- driven off the same 0.25s ticker (see its own comment there) rather than hooked into
-- every path that can change s.buys/s.estProfit, so a new one can't leave a stale figure on
-- screen. Deals-only: f.sessionText is part of f.dealsChrome, which setView Hides on Sell/Sold
-- -- but this function re-Shows it whenever it runs (Show() at the bottom), so without this
-- early return the very next tick after switching away from Deals would undo that Hide.
refreshSessionText = function()
  if view ~= "deals" then return end
  local fs = frame and frame.sessionText
  if not fs then return end
  local s = GC.Sniper.session
  if not s or s.buys == 0 then fs:Hide() return end
  local c = s.estProfit >= 0 and Theme.color.green or Theme.color.red
  fs:SetText(("SESSION %s%s · %d BUYS"):format(s.estProfit >= 0 and "+" or "",
    formatColumnAmount(s.estProfit), s.buys))
  fs:SetTextColor(c[1], c[2], c[3])
  fs:Show()
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

  frame.status:SetText("starting full scan...")
  startFullScan()
  refreshScanButton()
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
  dialog:SetHeight(dialog.baseHeight + LIM.REQUOTE_BANNER_HEIGHT)
  dialog.banner:Show()
end

-- Refuses the confirming click for LIM.REQUOTE_ARM_SECONDS so a click already on its way when the
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

  C_Timer.After(LIM.REQUOTE_ARM_SECONDS, function()
    if token ~= requoteArmToken then return end
    if not dialog or dialog.row ~= row or row.purchaseStage ~= "requote" then return end
    dialog.primaryBtn:Enable()
    setPrimaryLabel("Confirm", 1, 0.35, 0.35)
  end)
end

-- Sets the dialog's status line text and color in one call; color defaults to Theme.color.fgDim
-- (Task 2 restyle, was plain white) so a caller that passes no r/g/b at all -- every "checking"
-- message -- reads as quiet/neutral instead of full-brightness, and callers only pass r/g/b for
-- an accent (green when armReady confirms Buy, red on refusal/expiry) message.
local function setDialogStatus(text, r, g, b)
  if not dialog then return end
  dialog.status:SetText(text or "")
  -- Theme.color.fgDim's own literal values (0.55, 0.54, 0.52 -- Theme.lua), not a live table
  -- read: several purchase-wiring specs build a bare-bones GC.Theme fixture with no `color`
  -- field at all (they only ever exercised the old hardcoded-white default), and this function
  -- runs on every one of their setDialogStatus("...") no-color call sites.
  dialog.status:SetTextColor(r or 0.55, g or 0.54, b or 0.52)
end

-- Item icon + quality-colored name + qty suffix + tier chip, mirroring setRowDeal's async
-- load pattern but targeting the dialog's own widgets. dialog.deal (not row.deal) is the
-- identity guard here since the dialog can outlive the row being reassigned.
local function setDialogHeader(deal, decision)
  local color = Theme.tier[deal.tier] or Theme.tier.WATCH
  dialog.tierChip:SetLabel(deal.tier, color)
  local suspect = deal.tier == "SUSPECT"
  if suspect then dialog.suspectNote:Show() else dialog.suspectNote:Hide() end
  -- Check panel v2: the cards slot doubles as the suspect-note slot -- never both. Guarded
  -- (entryCard/exitCard are new fields) so every fakeDialog in sniper_dialog_verdict_spec /
  -- sniper_purchase_wiring_spec without them keeps passing unmodified.
  if dialog.entryCard then
    if suspect then dialog.entryCard:Hide() else dialog.entryCard:Show() end
  end
  if dialog.exitCard then
    if suspect then dialog.exitCard:Hide() else dialog.exitCard:Show() end
  end
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

-- DG (dialog geometry): relocated here from down by createDialog (F4, whole-branch review) --
-- resizeDialogDiagnostics below needs DG.CONTROLS_H for its drawer-era status anchor, and a
-- local must be declared before the earliest function that closes over it (same chunk-order
-- requirement CH was moved for; see CH's own comment, and the "Sniper v3 dialog layout
-- constants" marker left in DG's old spot -- that exact text is a protected-spec section
-- boundary and could not move with the table). One table, not seventeen top-level locals: a
-- Lua chunk may hold 200 of those and this file sits at exactly 200 -- see addon/AGENTS.md.
local DG = {}
DG.WIDTH = 320
DG.ICON = 32 -- Task 2 restyle (was 24): the header icon reads as the item itself now, not a bullet
-- Check panel v2 (was 20): shrunk one notch so the ten-row evidence grid reads denser without
-- growing DG.FIXED_HEIGHT_OPEN past the docked drawer's own ceiling. No longer a component of
-- DG.QTY_H (see that constant's own comment below) -- only the evidence grid itself now.
DG.GRID_ROW_H = 18
-- The label/value grid now holds only the ten immutable decision/evidence fields (Status
-- through Reason) -- Quantity and its quick-fill row moved out into their own always-visible
-- block (DG.QTY_H below), reachable whether Details is open or not.
DG.GRID_ROWS = 10
-- Fix 2 quick-fill row geometry: four small ghost buttons sharing the row right under
-- Quantity -- they don't fit alongside that row's own label + "of N" + edit box on one
-- 296px-wide line, so they get their own row instead of crowding it.
DG.QTY_QUICKFILL_H = 18 -- Task 2 restyle (was 16): kit-value 36x18 quick-fill badge
DG.QTY_QUICKFILL_W = 36 -- Task 2 restyle (was 34)
DG.QTY_QUICKFILL_PCTS = { 25, 50, 75, 100 }
-- I5: 36/32 (were 28/18) -- the requote path's status line can wrap to two full lines
-- ("<unit> -> <unit> per unit    total <total> -> <total>" at DG.WIDTH), and the
-- suspect/mv notes must never clip a second line either; both budgets sized for two lines
-- of Theme.Label(d, 11) at this width, not one.
-- Check panel v2: no longer read by DG.HEADER_H (the suspect note left the header for the
-- cards slot below) -- kept defined as the reserved-note-height figure in case a future budget
-- needs it again; nothing currently reads it.
DG.NOTE_H = 36   -- reserved height for a 2-line suspect note at this width/font
DG.DIAGNOSTIC_MIN_H = 36
DG.STATUS_H = 32
DG.PRIMARY_H = 32 -- Task 2 restyle (was 26): kit-value "big buy" plaque height
DG.CANCEL_H = 22 -- Task 2 restyle (was 20)
-- Check panel v2: the header no longer reserves a blank note slot under the item name -- that
-- was the single biggest hole the second in-game pass called out ("это окно надо улучшить").
-- d.suspectNote now shares the cards slot after the Quantity row (see DG.CARDS_TOP below)
-- instead of living here. Header is just top margin + icon + gap.
-- 12 + 32 + 8 = 52
DG.HEADER_H = Theme.pad.m + DG.ICON + Theme.pad.s

-- Verdict block: a small live-status kicker (d.verdictLabel), the headline -- what the click
-- DOES and what it costs when buyable, the refusal sentence in refusal red when it is not --
-- a big signed profit figure (d.verdictAmount) with its own caption, and a quieter sub-line
-- naming the stress profit. VERDICT_HEAD_H covers the kicker+headline pair, VERDICT_SUB_H the
-- amount+sub-line pair; both are fixed reservations (the headline no longer wraps -- one line
-- now, see createDialog), not GetStringHeight()-measured -- diagnosticText already owns the one
-- dynamically-measured block this dialog needs.
DG.VERDICT_HEAD_H = 32 -- Task 2 restyle (was 28): label + headline
DG.VERDICT_SUB_H = 42 -- Task 2 restyle (was 26): amount line + sub-line
-- 8 + 32 + 4 + 42 + 8 = 94 (controller ruling: the plan's kit-values table said 90, an addition
-- slip -- this is the verified sum of the components above)
DG.VERDICT_H = Theme.pad.s + DG.VERDICT_HEAD_H + Theme.pad.xs + DG.VERDICT_SUB_H + Theme.pad.s

-- Quantity + its quick-fill row: the one interactive control in this dialog besides the
-- buttons, so it stays visible above the Details toggle rather than being hidden behind it.
-- 18px box (Task 2 restyle, DG.QTY_BOX_H below); check panel v2 stopped tying this to
-- DG.GRID_ROW_H (now 18, was 20) once the evidence grid and the QTY row needed different row
-- heights -- 20 (label line) + pad.xs (gap) + DG.QTY_QUICKFILL_H (18, the chip row).
DG.QTY_H = 20 + Theme.pad.xs + DG.QTY_QUICKFILL_H -- 20 + 4 + 18 = 42
-- Check panel v2: the qty edit box's own height, split out from DG.GRID_ROW_H now that the
-- grid row shrank to 18 and the box did not need to shrink with it.
DG.QTY_BOX_H = 18
-- Task 2 restyle: no longer tied to DG.GRID_ROW_H (20) -- the kit gives the toggle its own
-- height (22), so it needs its own field now that the two numbers differ.
DG.TOGGLE_H = 22

-- Measured down from the header, in the order the dialog actually stacks: verdict, then
-- Quantity, then the ENTRY AVG / STRESS EXIT cards (or the suspect note, sharing the same
-- slot), then the Details toggle, then (only while open) the evidence grid.
DG.VERDICT_TOP = -DG.HEADER_H
DG.QTY_TOP = DG.VERDICT_TOP - DG.VERDICT_H
-- Check panel v2: two 40px-tall cards side by side (kit-value height) plus pad.s below them,
-- same idiom as DG.VERDICT_H/DG.CONTROLS_H above (a fixed component sum, not a bare literal).
DG.CARDS_H = 40 + Theme.pad.s -- 48
DG.CARDS_TOP = DG.QTY_TOP - DG.QTY_H
DG.TOGGLE_TOP = DG.CARDS_TOP - DG.CARDS_H
DG.GRID_TOP = DG.TOGGLE_TOP - DG.TOGGLE_H
-- Where the diagnostic/status block starts: right after the (shown) evidence grid when
-- Details is open, or right after the toggle itself -- the grid simply skipped -- when it is
-- closed. resizeDialogDiagnostics picks between these depending on dialog.detailsOpen.
DG.EVIDENCE_BOTTOM_OPEN = DG.GRID_TOP - DG.GRID_ROWS * DG.GRID_ROW_H - Theme.pad.xs
DG.EVIDENCE_BOTTOM_CLOSED = DG.TOGGLE_TOP - DG.TOGGLE_H - Theme.pad.xs

-- bottom margin + cancel + gap + primary + gap-to-status, measured up from the dialog's own
-- bottom edge (mirrors DG.GRID_TOP's measured-down-from-top pattern above).
-- 12 + 32 + 4 + 22 + 8 = 78
DG.CONTROLS_H = Theme.pad.m + DG.PRIMARY_H + Theme.pad.xs + DG.CANCEL_H + Theme.pad.s
-- Two fixed-height budgets, Details closed and open -- resizeDialogDiagnostics only ever
-- READS dialog.fixedHeight (same contract as before); applyDetailsState (createDialog) is
-- the one place that picks between these and writes it, on open/close.
-- 52 + 94 + 42 + 48 + 22 + 32 + 78 = 368 (check panel v2, was 362)
DG.FIXED_HEIGHT_CLOSED = DG.HEADER_H + DG.VERDICT_H + DG.QTY_H + DG.CARDS_H + DG.TOGGLE_H
  + DG.STATUS_H + DG.CONTROLS_H
DG.FIXED_HEIGHT_OPEN = DG.FIXED_HEIGHT_CLOSED + DG.GRID_ROWS * DG.GRID_ROW_H -- 368 + 180 = 548

-- The diagnostic is evidence, not a purchase surface, and (fix round N) is now hidden unless
-- the player has turned on GC.db.settings.sniper.debug -- it is a bug-report transcript, not
-- something a player one click from spending gold needs to see by default. Its height still
-- follows the rendered text when it IS shown, so every ordered reason remains visible at the
-- player's current font scale; when it is not shown it contributes nothing, and `status`
-- anchors directly below wherever the (open or closed) evidence grid ends instead. The buttons
-- and requote banner stay bottom-anchored; changing baseHeight moves that whole block together.
--
-- F4 (whole-branch review): in the old centered modal, dialog:SetHeight below actually grew
-- the dialog to fit whatever status ended up flowing to, so a top-flowed status could never
-- collide with the bottom-anchored banner/buttons -- the dialog just got taller around it. In
-- the check drawer that SetHeight is an anchor-overridden no-op (createDialog's own drawer-
-- anchor comment): nothing grows anymore, so a status positioned by flowing down from the
-- (open or closed) evidence grid could run into the fixed bottom block instead. The DEFAULT
-- (debug off) branch below now anchors `status` bottom-up, pinned clear of the banner slot,
-- for exactly this reason. The debug-ON branch keeps flowing status directly under the
-- (dynamically measured) diagnostic text unchanged -- that exact anchor is pinned by
-- sniper_purchase_wiring_spec's "sizes, banners, and shrinks..." test (statusAnchors[1]), a
-- protected spec this task may not modify; debug is a developer-only view, already denser
-- than the default one (see the accepted evidence-rows-9-10-under-banner ruling), so the
-- default path every real player sees is the one this fix actually needs to cover.
local function resizeDialogDiagnostics()
  local evidenceBottom = dialog.detailsOpen and dialog.evidenceTopOpen or dialog.evidenceTopClosed
  dialog.mvNote:ClearAllPoints()
  dialog.mvNote:SetPoint("TOPLEFT", Theme.pad.m, evidenceBottom)
  dialog.mvNote:SetPoint("RIGHT", -Theme.pad.m, 0)

  local diagnostic = dialog.diagnosticText
  diagnostic:ClearAllPoints()
  diagnostic:SetPoint("TOPLEFT", Theme.pad.m, evidenceBottom)
  diagnostic:SetPoint("RIGHT", -Theme.pad.m, 0)

  local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
  local debugOn = (cfg and cfg.debug) and true or false
  local height, gap = 0, 0
  dialog.status:ClearAllPoints() -- idempotent: every call below re-sets both points fresh
  if debugOn then
    diagnostic:Show()
    local measured = type(diagnostic.GetStringHeight) == "function" and diagnostic:GetStringHeight() or nil
    if type(measured) ~= "number" or measured <= 0 then measured = dialog.diagnosticMinimumHeight end
    height = math.max(dialog.diagnosticMinimumHeight, math.ceil(measured))
    gap = dialog.diagnosticGaps
    diagnostic:SetHeight(height)
    dialog.status:SetPoint("TOPLEFT", diagnostic, "BOTTOMLEFT", 0, -Theme.pad.xs)
    dialog.status:SetPoint("RIGHT", -Theme.pad.m, 0)
  else
    diagnostic:Hide()
    -- Bottom-up, not top-flowed: the status line sits directly on the button block (DG.CONTROLS_H
    -- up from the drawer's bottom, its own top padding included), the way the mockup reads
    -- "price confirmed" right above BUY. The fixed banner slot (LIM.REQUOTE_BANNER_HEIGHT) is
    -- reserved ABOVE the status (see the banner's anchors in createDialog), so the two never
    -- overlap regardless of how much room the evidence grid above actually used.
    dialog.status:SetPoint("BOTTOMLEFT", Theme.pad.m, DG.CONTROLS_H)
    dialog.status:SetPoint("BOTTOMRIGHT", -Theme.pad.m, DG.CONTROLS_H)
  end
  dialog.diagnosticHeight = height

  dialog.baseHeight = dialog.fixedHeight + gap + height
  local bannerVisible = dialog.banner and dialog.banner:IsShown()
  dialog:SetHeight(dialog.baseHeight + (bannerVisible and LIM.REQUOTE_BANNER_HEIGHT or 0))
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
  -- The headline names the first reason that actually REFUSED, skipping the informational ones
  -- SniperDecision marks. `demand_limit` is added as a note whenever the chosen quantity is
  -- below the player's maximum, which is ordinary, and it sorts ahead of the gate that really
  -- refused -- so reasons[1] showed "demand_limit" while stress_profit_below_buffer, the actual
  -- answer, sat further down the list. The full ordered list below is unchanged.
  local firstReason
  for _, reason in ipairs(decision.reasons or {}) do
    if not (decision.informational and decision.informational[reason]) then
      firstReason = reason
      break
    end
  end
  firstReason = firstReason or (decision.reasons and decision.reasons[1]) or "live_verification_required"

  -- Verdict block: what a click DOES, not a debug dump. Money is formatColumnAmount (via
  -- displayDecisionAmount) and this decision snapshot alone -- nothing here is recomputed.
  -- The item label reuses the SAME per-itemID name/icon cache setRowDeal populates -- the
  -- dialog only ever opens from a row's own Buy click, so that row has already resolved it;
  -- "item <id>" is the same placeholder setDialogHeader itself falls back to when it has not.
  local itemLabel = (nameIconCache[deal.itemID] and nameIconCache[deal.itemID].named)
    or ("item " .. deal.itemID)
  if decision.buyable then
    dialog.verdictHead:SetText(("Buy %d × %s for %s"):format(
      quantity, itemLabel, displayDecisionAmount(entryTotal)))
    dialog.verdictHead:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
    -- Sniper v4 check drawer: tints the card behind the verdict headline/sub-line. Guarded --
    -- not every dialog stand-in in the test suite builds a real createDialog widget tree (the
    -- protected purchase-wiring/verdict specs stamp a hand-built fakeDialog without this
    -- field), and this is purely visual, so a stand-in without it just skips the tint.
    if dialog.verdictCard then
      dialog.verdictCard:SetTint(
        { Theme.color.green[1], Theme.color.green[2], Theme.color.green[3], 0.06 },
        { Theme.color.green[1], Theme.color.green[2], Theme.color.green[3], 0.30 })
    end
    -- Task 2 restyle: the live-verdict kicker above the headline and the big signed profit
    -- figure below it -- same guard as verdictCard just above (the protected purchase-wiring/
    -- verdict specs' fakeDialog stand-ins don't build these either), same profit value
    -- verdictSub's own sentence uses just below so the two never disagree.
    if dialog.verdictLabel then
      dialog.verdictLabel:SetText("LIVE VERDICT · SAFE")
      dialog.verdictLabel:SetTextColor(Theme.color.green[1], Theme.color.green[2], Theme.color.green[3])
    end
    if dialog.verdictAmount then
      dialog.verdictAmount:SetText(decision.stressProfit
        and ("+" .. displayDecisionAmount(decision.stressProfit)) or "—")
      dialog.verdictAmount:SetTextColor(Theme.color.green[1], Theme.color.green[2], Theme.color.green[3])
      dialog.verdictAmount:Show()
    end
    -- Fix round 1: the caption is orphaned (still visible, captioning nothing) if it isn't
    -- hidden alongside verdictAmount on refusal -- same guard, shown here.
    if dialog.verdictAmountNote then dialog.verdictAmountNote:Show() end
    dialog.verdictSub:SetText(decision.stressProfit
      and ("you should clear about %s"):format(displayDecisionAmount(decision.stressProfit))
      or "")
    dialog.verdictSub:Show()
  else
    -- Same refusal red as profitText below, and the same firstReason logic above -- never a
    -- second copy of either.
    dialog.verdictHead:SetText(GC.SniperDecision.ReasonText(firstReason))
    dialog.verdictHead:SetTextColor(1, 0.3, 0.3)
    -- See the buyable branch's own comment above -- same guard, refusal tint.
    if dialog.verdictCard then
      dialog.verdictCard:SetTint(
        { Theme.color.red[1], Theme.color.red[2], Theme.color.red[3], 0.07 },
        { Theme.color.red[1], Theme.color.red[2], Theme.color.red[3], 0.30 })
    end
    -- Task 2 restyle: same guard as the buyable branch above. There is nothing to clear when
    -- a decision refuses, so the amount hides rather than showing a misleading "—".
    if dialog.verdictLabel then
      dialog.verdictLabel:SetText("LIVE VERDICT · REFUSED")
      dialog.verdictLabel:SetTextColor(Theme.color.red[1], Theme.color.red[2], Theme.color.red[3])
    end
    if dialog.verdictAmount then dialog.verdictAmount:Hide() end
    if dialog.verdictAmountNote then dialog.verdictAmountNote:Hide() end
    dialog.verdictSub:Hide()
  end

  local publicStatus = decision.status or "WATCH"
  local computedStatus = decision.computedStatus or publicStatus
  local diagnosticReasons = table.concat(decision.reasons or {}, ", ")
  if decision.computedStatus == "SAFE" and publicStatus == "WATCH" then
    dialog.decisionStatusText:SetText("WATCH (computed SAFE)")
  else
    dialog.decisionStatusText:SetText(publicStatus)
  end
  -- The item ID leads the line because this diagnostic is the only place it survives: the
  -- header shows "item <id>" for exactly as long as Item:ContinueOnItemLoad takes to replace
  -- it with the localized name, and a name is not an identity -- tiered reagents share one
  -- name across several IDs. Without this, a shadow observation transcribed from the dialog
  -- cannot be attributed to an item afterwards.
  dialog.diagnosticText:SetText(("item=%d computed=%s public=%s buyable=%s reasons=%s"):format(
    deal.itemID, computedStatus, publicStatus, decision.buyable and "yes" or "no",
    diagnosticReasons ~= "" and diagnosticReasons or "none"))
  resizeDialogDiagnostics()
  dialog.stampedUnit = average
  dialog.stampedTotal = entryTotal
  if dialog.qtyBox and quantity > 0 then dialog.qtyBox.editBox:SetText(tostring(quantity)) end
  dialog.unitPriceText:SetText(displayDecisionAmount(average))
  if dialog.entryValue then dialog.entryValue:SetText(displayDecisionAmount(average)) end
  dialog.totalCostText:SetText(displayDecisionAmount(entryTotal))
  dialog.exitUnitText:SetText(displayDecisionAmount(decision.exitUnit))
  if dialog.exitValue then dialog.exitValue:SetText(displayDecisionAmount(decision.exitUnit)) end
  dialog.profitText:SetText(displayDecisionAmount(decision.stressProfit))
  dialog.mvText:SetText(displayDecisionAmount(market.marketValue))
  dialog.soldText:SetText(market.soldPerDay and ("%.1f"):format(market.soldPerDay) or "—")
  dialog.sellThroughText:SetText(market.sellThroughBps and ("%.1f%%"):format(market.sellThroughBps / 100) or "—")
  dialog.sourceAgeText:SetText(sourceAge and ("%ds"):format(sourceAge) or "—")
  dialog.reasonText:SetText(GC.SniperDecision.ReasonText(firstReason))
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

-- Expires a quote nobody clicked within LIM.ARM_TIMEOUT_SECONDS -- but never dead-ends the
-- player: the primary button flips to "Refresh" (stage "expired"), whose click re-runs the
-- live requery for fresh numbers. Refresh is NOT a purchase call, so looping through
-- expired -> Refresh -> ready any number of times stays compliant.
local function scheduleArmTimeout(row, deal, decision)
  C_Timer.After(LIM.ARM_TIMEOUT_SECONDS, function()
    if row.purchaseStage == "ready" and row.deal == deal and row.decisionSnapshot == decision
        and dialog and dialog.row == row then
      row.purchaseStage = "expired"
      dialog.primaryBtn:Enable()
      setPrimaryLabel("Refresh")
      -- Task 2 restyle: red, not amber (Theme.color.red's own literal values -- see
      -- setDialogStatus's own comment for why this file hardcodes rather than reads the live
      -- table). The Kit's status color rule is green on armReady's own Buy confirmation, red on
      -- refusal OR expiry, fgDim (setDialogStatus's own default) everywhere else.
      setDialogStatus("quote expired -- Refresh to re-check the price", 0.898, 0.283, 0.302)
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

-- `levels` is an optional pre-built book (from driver.commodityBook) the caller already has --
-- onObservation below passes its own so the same poll's book is not fetched twice. Every other
-- call site omits it and gets the old behaviour of building its own.
evaluateLiveCommodityDeal = function(itemID, levels)
  levels = levels or driver.commodityBook(itemID)
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
      -- A sentence, not the engine's token: "source_stale" names the gate, it does not tell the
      -- player that the import is two hours old and that a Companion sync needs a /reload to be
      -- seen. The token itself is still on the reason line and in the diagnostic above it.
      armCheck(row, deal, decision,
        GC.SniperDecision.ReasonText(decision.reasons[1] or "live_verification_required"), false)
    end
  else
    showGoneState(row, "listing gone -- already bought out or price changed")
    if deals[itemID] then deals[itemID] = nil end
    for i = #scanDeals, 1, -1 do
      if scanDeals[i].itemID == itemID then table.remove(scanDeals, i) end
    end
    if frame then frame.status:SetText("gone / price changed") end
  end
  -- The Check the player just ran is the most authoritative thing anyone knows about this
  -- item, so it replaces whatever the background walk had recorded. Without this, cancelling
  -- out of a dialog that said AVOID would drop the player back onto a row still wearing the
  -- gold Buy button an older background verdict had earned it.
  stampVerdict(deal, live, true)
  refreshRows()
end

-- Same BUY_TIMEOUT window as before (covers both PlaceBid and StartCommoditiesPurchase
-- waiting on their respective completion/quote events), but freezes the dialog with an
-- explanatory status instead of auto-resolving the purchase as failed: PlaceBid's completion
-- event is UNVERIFIED to always fire, so silently unpinning here could let the player
-- re-attempt a buy whose bid may in fact still land. The row stays pinned until Cancel.
local function scheduleBuyTimeout(row, deal, token)
  C_Timer.After(LIM.BUY_TIMEOUT_SECONDS, function()
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
  C_Timer.After(LIM.REQUERY_TIMEOUT_SECONDS, function()
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
  -- Stop Live before registering or sending the authoritative Check. This comment used to claim
  -- Init.lua dispatches the scanner's throttle-ready hook first, which stopped being true once
  -- the slot arbiter (GC.Sniper.OnThrottleReady/_GrantWatchSlot) took over allocation: a parked
  -- Check now wins its slot outright through the arbiter regardless of this branch. `scanning`
  -- itself is permanently false besides -- the Live button that used to flip it true is gone
  -- (see the comment above GC.Sniper._ResumeLiveScanner) -- so the `elseif scanning` arm below
  -- is retained-but-unreachable, not removed: `scanning` is still read in several other places
  -- in this file (e.g. the pause/resume pair the Check requery path calls unconditionally), and
  -- restoring Live means restoring one function and one button, not untangling those reads.
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
-- row/dialog. openDialog (below) is the only consumer: a fresh (<= LIM.PREWARM_TTL_SECONDS old)
-- deal.prewarm lets it skip straight to applyRequeryResult instead of calling startRequery, so
-- the dialog opens already armed. A stale/absent cache falls back to today's flow unchanged.
-- ---------------------------------------------------------------------------

-- Deliberately does NOT park behind pendingRequerySend the way issueRequerySearch does: a
-- pre-warm that missed its throttle window is worth nothing later that a fresh one issued on
-- the next hover wouldn't do better, and letting it queue would risk a parked pre-warm send
-- winning a throttle slot the T7 OnThrottleReady flush order reserves for scan traffic /
-- pendingRequerySend first -- simplest and safest is: not ready right now -> skip, hovering
-- again retries.
-- `auto` marks the background-verification caller (tickAutoVerify below). It relaxes exactly
-- one guard: the `.stale` requirement, which exists because a hover pre-warm is only ever
-- useful to openDialog's own stale-deal shortcut. Background verification wants a verdict for
-- whatever the player is looking at, stale or not. Relaxed explicitly rather than by deleting
-- the guard: today every deal on the board comes from the full scan and is therefore stale, so
-- deleting it would look correct and quietly make the auto path depend on that staying true.
--
-- **Returns true only if a query actually went out.** Eleven of the twelve paths through this
-- function are declines, and two of them never clear on their own: an item whose key the
-- client has not cached (a pre-warm may not chase ITEM_KEY_ITEM_INFO_RECEIVED the way
-- startRequery does) and one parked behind the untagged-result drain fence. A caller that
-- cannot tell "sent" from "declined" treats a permanently unsendable row as work in progress
-- -- which is exactly how one bad row at the top of the list starved every row beneath it.
local function maybeStartPrewarm(deal, auto)
  if not deal then return end
  if not auto and not deal.stale then return end -- hover pre-warm only helps the two-click full-scan flow
  if not ahOpen then return end -- fix round 1 M-3: no AH session live (window can stay open/re-shown via /goldcap with leftover deals after AH close) -- nothing to query against
  if deal.prewarm and (GetTime() - deal.prewarm.at) <= LIM.PREWARM_TTL_SECONDS then return end -- fix round 1 I-3: re-hovering a deal with a still-fresh cache has nothing to gain from a second query
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
  C_Timer.After(LIM.REQUERY_TIMEOUT_SECONDS, function()
    if prewarmAttempt == attempt then
      prewarmAttempt = nil
      requeryDraining[itemID] = attempt
    end
  end)
  return true
end

-- Records what the live query just said about `deal`, re-renders the list around it, and rings
-- once on the transition into buyable.
--
-- `data` is exactly the liveDeal shape finishRequery/applyRequeryResult consume, so `buyable`
-- here is armReady's own gate verbatim (SAFE + buyable + commodity) -- one place decides what
-- "you can buy this" means, and this is not a second one. nil data means the listing is gone.
--
-- Called from every pre-warm landing, hover ones included: a hover already pays for the query,
-- so there is no reason for it not to leave a verdict behind.
-- `manual` marks a verdict the player asked for by clicking Check, and it changes two things.
--
-- It does not ring: the ping exists to say "something became buyable while you were not
-- looking", and somebody reading the dialog they just opened is looking.
--
-- And the row is never pruned from the list, however the Check turned out. Answering "what
-- about this one?" by making it disappear is not an answer -- the row stays, wearing the
-- engine's own word for the refusal, which is strictly more than it said before. Pruning is
-- for rows nobody asked about. It survives the background walk's own re-checks (a kept row is
-- still on screen, so it still gets re-checked) but not a price change: a new asking price is
-- a new question, and nobody has asked it yet.
stampVerdict = function(deal, data, manual)
  if not deal or not deal.itemID then return end
  local previous = verdicts[deal.itemID]
  local samePrice = previous and previous.unitPrice == deal.unitPrice
  local wasBuyable = samePrice and previous.buyable
  local kept = manual or (samePrice and previous.manual) or nil
  local decision = data and data.decision
  local buyable = (decision and decision.buyable and decision.status == "SAFE"
    and data.isCommodity) and true or false
  local status, reason
  if not data then
    status, reason = "Gone", "listing gone -- bought out or repriced"
  else
    status = decision and decision.status or "WATCH"
    local token = decision and decision.reasons and decision.reasons[1]
    reason = GC.SniperDecision.ReasonText(token or "live_verification_required")
  end
  verdicts[deal.itemID] = {
    unitPrice = deal.unitPrice, at = GetTime(), manual = kept,
    buyable = buyable, status = status, reason = reason,
  }
  refreshRows()

  if manual or not buyable or wasBuyable then return end -- ping the transition only, never every re-check
  -- Per ITEM, never a global mute. A watched item whose floor is reset every few seconds is a
  -- real sequence of opportunities and every one of them still SHOWS -- but a bell every five
  -- seconds stops carrying information, and two different items must never silence each other.
  local rang = GC.Sniper._rangAt[deal.itemID]
  if rang and (GetTime() - rang) < LIM.RING_FLOOR_SECONDS then return end
  GC.Sniper._rangAt[deal.itemID] = GetTime()
  -- Find the row by the SAME key the verdict itself is filed under -- item and asking price --
  -- and NOT by table identity the way pingNewHotDeals does. That difference is the whole bug
  -- behind "the Buy button appeared but it never made a sound": identity is right for a HOT
  -- ping, which fires within one merge of the tables it was handed, but a verdict outlives the
  -- table it was measured on. Streaming re-evaluates on every browse page and MergeDeals
  -- splices in FRESH tables each time, so by the time a query came back the row was usually
  -- carrying an equal-but-different table, no row matched, and the ping was dropped on the
  -- floor. Row-not-on-screen must still mean no sound -- a ping with nothing to look at is
  -- noise -- but "not on screen" has to mean what the player sees, not what Lua allocated.
  for i = 1, #rows do
    local row = rows[i]
    if row.deal and row.deal.itemID == deal.itemID
        and row.deal.unitPrice == deal.unitPrice and row:IsShown() then
      flashRow(row)
      if GC.db and GC.db.settings and GC.db.settings.sniper.sound then
        PlaySound(SOUNDKIT.READY_CHECK or SOUNDKIT.MAP_PING or 3175, "Master")
      end
      return
    end
  end
end

-- The pre-warm result landing (or failing to materialize into a live deal): stamps
-- deal.prewarm on the EXACT deal table maybeStartPrewarm captured, records the verdict, and
-- releases the "one in flight" slot. `data` mirrors exactly what finishRequery's own `liveDeal`
-- argument would be for the same event -- nil means "gone / price changed", handled identically
-- by applyRequeryResult whenever this cache gets consumed.
--
-- Never touches row.purchaseStage/activeItemID/the dialog -- that is still the entire point of
-- this being a separate path from finishRequery. stampVerdict below it re-renders the list,
-- which is a read of the same purchase state, never a write to it.
local function resolvePrewarm(itemID, data)
  local attempt = prewarmAttempt
  if not attempt or attempt.itemID ~= itemID then return end
  local deal = attempt.deal
  prewarmAttempt = nil
  if not deal then return end
  deal.prewarm = { data = data, at = GetTime(), token = attempt.token }
  stampVerdict(deal, data)
end

-- ---------------------------------------------------------------------------
-- Background verification. The player asked for automatic BUYING; that cannot be built and
-- deliberately is not. Purchase calls (StartCommoditiesPurchase, ConfirmCommoditiesPurchase,
-- PlaceBid) are protected: the client runs them only out of a hardware input handler, and
-- automating gameplay actions violates the Terms of Use besides
-- (spec/sniper_purchase_wiring_spec.lua asserts that statically, on purpose).
--
-- What IS buildable is everything except the final click. This runs the same live query a
-- Check runs, on the handful of rows the player is actually looking at, so the list carries
-- real verdicts instead of thirty identical Check clicks. The click that spends gold stays
-- exactly where it was.
-- ---------------------------------------------------------------------------
local function tickAutoVerify()
  -- Shared throttle budget: while the player is busy on Blizzard's own AH panes -- posting,
  -- buying a browse result, or reading their own search -- their click outranks this
  -- background walk.
  if GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy and GC.AuctionHouseTab.PlayerIsBusy() then return end
  if not ahOpen then return end
  if view ~= "deals" then return end -- the Sell tab is up; verifying what nobody is reading just costs throttle
  if not frame or not frame:IsShown() then return end
  if prewarmAttempt then return end -- one query in flight globally, shared with the hover pre-warm
  if GC.Sniper.IsSearchCritical() then return end -- a Check or a purchase owns the search slot
  -- Checked BEFORE the once-a-second gate below, and deliberately so. Under Auto the browse
  -- scan is paging almost continuously, so the throttled system is unready most of the time --
  -- letting a busy moment consume the walk's turn meant the walk mostly ran during the
  -- fraction of a second it could do nothing, and the next opening a whole second away.
  if not driver.isReady() then return end

  local now = GetTime()
  if now < verifyWalkAt then return end
  verifyWalkAt = now + LIM.VERIFY_WALK_SECONDS

  local list = renderList()
  local limit = math.min(#list, LIM.VERIFY_TOP_ROWS)

  -- Two passes over the SAME top-`limit` slice, in renderList()'s own order (best-first as of
  -- Commit 1's estProfit ranking). Pass 1 gives first claim on the walk's one query per tick to
  -- rows with no verdict at their current asking price -- never checked at all, or checked at a
  -- price that has since moved, which is the same "know nothing about this" state. Without this
  -- priority, an already-verified row sitting ahead of a brand-new one in the list could keep
  -- winning every tick's single slot forever, and the new row would never get its first look.
  -- Pass 2 only runs (finds anything) when pass 1 sent nothing, and covers rows that already
  -- carry a same-price verdict but are due for a recheck -- see the interval comment inside it.
  for i = 1, limit do
    local deal = list[i]
    -- Already covered by the watch loop, which re-reads its live book far more often than
    -- this walk could. Spending a slot here would buy nothing and starve an unwatched row.
    -- A placeholder is skipped too -- there is nothing to buy and its unitPrice may be 0, so
    -- verifying one would burn a search slot and stamp a verdict keyed to a meaningless price.
    if not GC.Sniper._IsWatched(deal.itemID) and not deal.pinPlaceholder then
      local v = verdicts[deal.itemID]
      if not (v and v.unitPrice == deal.unitPrice) then
        -- Stop on a query actually going out -- one per walk at most. A row that DECLINED to
        -- send is not progress and must not end the walk: its blocker may never clear (an
        -- uncached item key, the drain fence), and treating it as work in flight is what let one
        -- row at the top hold the whole list hostage. Move on and check the next one.
        if maybeStartPrewarm(deal, true) then return end
      end
    end
  end
  for i = 1, limit do
    local deal = list[i]
    if not GC.Sniper._IsWatched(deal.itemID) and not deal.pinPlaceholder then
      -- Read `verdicts` directly rather than through verdictFor: re-checking is on its own
      -- cadence, and a refusal that verdictFor still honours is exactly the thing whose price
      -- may have moved underneath it since. Only reached for a row pass 1 already confirmed
      -- carries a same-price verdict (a mismatched or absent one would have sent above and
      -- returned) -- an AVOID verdict gets the long leash, everything else the normal one.
      local v = verdicts[deal.itemID]
      if v and v.unitPrice == deal.unitPrice then
        local interval = (v.status == "AVOID") and LIM.VERIFY_AVOID_INTERVAL_SECONDS
          or LIM.VERIFY_INTERVAL_SECONDS
        if (now - v.at) >= interval then
          if maybeStartPrewarm(deal, true) then return end
        end
      end
    end
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

-- Hands the watch loop exactly one send. The grant is a window, not a flag the scanner keeps:
-- advance() runs synchronously inside OnSystemReady, so opening the window around that one
-- call is what bounds the loop to a single query per turn.
function GC.Sniper._GrantWatchSlot()
  local scanner = GC.Sniper.scanner
  if not scanner or not scanner.Wants or not scanner:Wants() then return false end
  watchGrant = true
  -- pcall, not a bare call. If the scanner throws, the `watchGrant = false` below would never
  -- run and Scanner.advance()'s veto would stay permanently open -- the watch loop would then
  -- take every ready tick for the rest of the session, which is the exact failure this arbiter
  -- exists to prevent. And OnThrottleReady is a shared handler: Init.lua runs
  -- GC.Sell.OnThrottleReady() right after it, so an escaping error takes the Sell tab's quote
  -- walk down too. The error is deliberately swallowed rather than surfaced -- a broken
  -- optional poll must not break the throttle chain a purchase Check depends on, the same
  -- reasoning that already pcall-guards AuctionHouseTab.Install.
  pcall(scanner.OnSystemReady, scanner)
  watchGrant = false
  -- Cycle time is MEASURED, never estimated: this project has not measured Blizzard's throttle
  -- interval and will not invent one. Count grants against the set size; every time the count
  -- wraps, one full pass has completed and its wall-clock is the number the UI shows.
  -- A wrap is the loop landing back on the item it started this pass on, which takes one MORE
  -- grant than the set has members (n grants visit every member once; the (n+1)th repeats the
  -- first) -- ">=" here would stamp every pass one grant short, permanently, not just the
  -- first. The grant that detects the wrap is also the first grant of the next pass, so the
  -- count restarts at 1 for it rather than 0. Counted even if the pcall above just swallowed a
  -- throw: the arbiter still spent this turn on the watch loop, and that is what is being
  -- timed -- not whether the scanner's own bookkeeping succeeded.
  GC.Sniper._grants = (GC.Sniper._grants or 0) + 1
  if #GC.Sniper._liveTargets > 0 and GC.Sniper._grants > #GC.Sniper._liveTargets then
    local started = GC.Sniper._passStartedAt
    if started then GC.Sniper._cycleSeconds = GetTime() - started end
    GC.Sniper._passStartedAt = GetTime()
    GC.Sniper._grants = 1
  end
  return true
end

-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY handler: a parked authoritative Check always consumes
-- the next slot before any optional browse traffic, exactly as before -- the Check has already
-- stopped Live in startRequery, so this works in watchlist mode without a scanner collision.
-- Starting a Full Scan pass is next, keeping its place ahead of everything optional. What's
-- left after those two is the split this task adds: the watch loop and browse paging are the
-- only two consumers that are genuinely optional, so they alternate turns while both are
-- hungry, and whichever one is hungry alone takes the slot outright so no slot goes idle.
function GC.Sniper.OnThrottleReady()
  -- A parked Check wins outright, exactly as before: a player is waiting on it, and it has
  -- already stopped the loop as a courtesy besides.
  for itemID, attempt in pairs(pendingRequerySend) do
    pendingRequerySend[itemID] = nil
    if isCurrentRequeryAttempt(attempt) then
      attempt.sent = true
      driver.sendSearch(itemID)
      return
    end
  end

  -- Starting a pass is not a background page -- it is the one send that makes the scan exist
  -- at all, and delaying it just leaves the scan idle. It keeps its place ahead of the split.
  if pendingFullScanStart then
    pendingFullScanStart = false
    sendBrowseQuery(fullScanToken)
    return
  end

  -- The even split, between the only two consumers that are genuinely optional. The watch poll
  -- stands down when the Deals view is not the one on screen, exactly as tickAutoVerify already
  -- does (it early-returns on `view ~= "deals"`): polling for a screen nobody is looking at was
  -- never the point, and the Sell tab is the consumer that starves first when the watch loop
  -- treats every ready tick as its own.
  local scanner = GC.Sniper.scanner
  local watchWants = (scanner and scanner.Wants and view == "deals" and scanner:Wants()) and true or false
  if not watchWants and not pendingBrowsePage then return end

  -- Alternate only while BOTH are hungry. If one has nothing to do the other takes the slot:
  -- a split that manufactures idle slots is worse than no split at all.
  local giveWatch = watchWants
  if watchWants and pendingBrowsePage then giveWatch = watchTurn end

  if giveWatch then
    watchTurn = false
    GC.Sniper._GrantWatchSlot()
  else
    watchTurn = true
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

-- Whether something the PLAYER is waiting on owns the throttled search slot: a
-- Check requery, or a purchase in flight. Short-lived, and nothing else may take
-- the slot out from under it.
--
-- Deliberately narrower than IsBusy, which also counts the full browse scan. The
-- Sell tab used to stand aside for IsBusy, and under Auto the browse scan runs
-- back to back with a two-second breather forever -- so the Sell tab could never
-- price anything at all, and Refresh looked hung until a reload happened to
-- catch a gap. A background convenience does not get to starve the screen the
-- player is actually looking at; the scan may run slightly slower for it, and
-- its own watchdog and Auto's retry already cover a disturbed pass.
function GC.Sniper.IsSearchCritical()
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

-- Read-only ownership checks used by Core/PurchaseCapture.lua's post-call observers. The
-- Sniper installs its in-flight state immediately before issuing its hardware-click purchase
-- call, so the passive hook can identify our call without issuing or changing any AH action.
function GC.Sniper.OwnsCommodityPurchase(itemID, quantity)
  local pending = commodityPurchase
  if not pending or pending.itemID ~= itemID then return false end
  if quantity == nil then return true end
  local decision = pending.row and pending.row.decisionSnapshot
  return decision and decision.quantity == quantity or false
end

function GC.Sniper.OwnsAuctionPurchase(auctionID)
  return pendingAuction[auctionID] ~= nil
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
    armCheck(row, deal, nil,
      GC.SniperDecision.ReasonText("requote_broke_safety") .. " — Check again", true)
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
    decision.entryTotal, totalPrice, LIM.REQUOTE_WARN_RATIO, LIM.REQUOTE_LOUD_RATIO)
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
    -- The confirming stage had no timeout at all: both buttons are disabled here, so if the
    -- server's terminal event never arrived the dialog sat on "confirming purchase..." with no
    -- way out. 15s, written inline because this chunk is at Lua's 200-local ceiling.
    --
    -- What this may NOT do is resolve the purchase. ConfirmCommoditiesPurchase has already been
    -- called, so gold may well have moved; marking it failed or freeing the row for a retry
    -- could buy the same lot twice. The attempt stays confirmed and owned -- a late success
    -- still settles through the tombstone -- and the only thing that changes is that the player
    -- is told what happened and can close the window.
    local confirmedToken = pending.token
    if C_Timer and C_Timer.After then
    C_Timer.After(20, function()
      if row.purchaseStage ~= "confirming" or row.purchaseToken ~= confirmedToken then return end
      if not (dialog and dialog.row == row) then return end
      dialog.cancelBtn:Enable()
      setDialogStatus("no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it.", 1, 0.82, 0)
    end)
    end
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
-- level the dialog fetched (bounded by LIM.MAX_BOOK_LEVELS, same cap driver.commodityBook itself
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
      GC.SniperDecision.ReasonText((decision and decision.reasons and decision.reasons[1])
        or "live_verification_required"), false)
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
-- DG itself (the constants this comment block describes) now lives up by
-- resizeDialogDiagnostics (F4, whole-branch review): that function's drawer-era status anchor
-- needs DG.CONTROLS_H, and a local must be declared before the earliest function that closes
-- over it (same chunk-order requirement CH was moved for -- see CH's own comment). This marker
-- comment stays here UNMOVED: sniper_purchase_wiring_spec's "keeps purchase calls in the
-- hardware-click handler" test locates it by exact source text as onDialogPrimaryClick's own
-- section boundary.
-- ---------------------------------------------------------------------------

-- Fix 2: a bordered box with a recolorable border, for the Quantity EditBox's focus ring.
-- Duplicated from SettingsFrame.lua's own private `borderedBox` (that one is a file-local
-- there, not reachable from here) rather than shared -- this is the only other Theme-styled
-- EditBox in the addon, and pulling a two-file dependency out of a settings-panel-only helper
-- for one reuse isn't worth it.
-- Task 2 restyle: badge.png (margin 6 -- BADGE_SLICE, Theme.lua) replaces the old flat
-- SetColorTexture fill + four hand-drawn 1px edge textures. Sized 64x18 (makeQtyEditBox's own
-- call below), margin 6 is well under half the smallest edge (9) -- Theme.lua's own nine-slice
-- invariant. badge.png has no ring counterpart (ROUNDED_BUTTON.badge.ring is nil, Theme.lua),
-- so the "border" is simulated the same trick a ring would give: an outer sliced badge tinted
-- the border/focus color, and a second one inset 1px on every side tinted Theme.color.bg, so
-- only a 1px rounded rim of the outer layer ever shows.
local function qtyBorderedBox(parent)
  local f = CreateFrame("Frame", nil, parent)
  local outer = Theme.SlicedTexture(f, "BACKGROUND", Theme.MEDIA .. "badge.png", Theme.color.border, 6)
  outer:SetAllPoints()

  local inner = Theme.SlicedTexture(f, "BORDER", Theme.MEDIA .. "badge.png", Theme.color.bg, 6)
  inner:SetPoint("TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", -1, 1)

  -- After SetTexture (inside Theme.SlicedTexture), recolor only via SetVertexColor -- same rule
  -- every other sliced surface in this file follows (Theme.Card:SetTint, Theme.Button
  -- SetVariant/OnEnable/OnDisable).
  function f:SetBorderColor(c)
    outer:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
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
  eb:SetMaxLetters(6) -- nothing plausible (even a full LIM.MAX_BOOK_LEVELS-deep book) needs more digits
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

-- CH.TITLEBAR is needed by the check drawer's anchor below (its top hugs the title bar), so
-- the table is declared here rather than down by createHeaderRow, which is its other consumer
-- -- a chunk-order requirement: a local declared after this function's body is compiled is not
-- an upvalue of it, it would resolve as an (absent) global instead.
local CH = {}
CH.TITLEBAR = 32    -- matches Theme.TitleBar's own fixed bar height (Theme.lua)
CH.BTN_H = 26 -- toolbar row: Auto / Scan / Refused-Hidden, all "plaque" buttons
CH.HEADER = 16      -- column header row height
-- Docked into the Auction House, the host's portrait overhangs the rail's top-left corner
-- (measured in the 2026-08-24 screenshot: logo top ~= 59px, portrait bottom ~= 70px at 1x);
-- 28 clears it with margin. Passed to rail.SetTopInset in SetDocked below.
CH.DOCK_RAIL_INSET = 28

-- Builds the single reusable confirmation dialog (see createDialog/openDialog usage below).
-- Created lazily on the first Buy click of a session, same pattern as GoldCapImportDialog --
-- never built eagerly alongside the sniper frame itself.
local function createDialog()
  local d = CreateFrame("Frame", nil, frame)
  -- C1: this is an UNNAMED frame (CreateFrame(..., nil, ...)), but UISpecialFrames (below)
  -- resolves "GoldCapSniperConfirm" by looking it up as a GLOBAL -- without this, Escape can't
  -- find the dialog at all, so it falls through to hiding the main Sniper window instead, and
  -- the dialog's own OnHide (which calls abortRowPurchase) never fires -- silently orphaning an
  -- in-flight purchase's pinned row.
  _G.GoldCapSniperConfirm = d
  -- Collapsed-by-default placeholder; applyDetailsState (below, once the toggle and evidence
  -- rows it drives actually exist) overwrites this from the restored setting before the
  -- dialog is ever shown -- openDialog always stamps immediately after this returns.
  d.fixedHeight = DG.FIXED_HEIGHT_CLOSED
  -- Match the two actual anchors: grid→diagnostic and diagnostic→status.
  d.diagnosticGaps = Theme.pad.xs + Theme.pad.xs
  d.diagnosticMinimumHeight = DG.DIAGNOSTIC_MIN_H
  d.baseHeight = d.fixedHeight + d.diagnosticGaps + d.diagnosticMinimumHeight
  d:SetSize(DG.WIDTH, d.baseHeight)
  d:SetFrameStrata("DIALOG") -- must float above the sniper list frame it's anchored to
  -- Check drawer (Sniper v4): full-height sheet on the window's right edge. TOP+BOTTOM
  -- anchors own the height -- the engine ignores every SetHeight below them, so the
  -- dialog's height bookkeeping (baseHeight/fixedHeight and their call sites) keeps
  -- running as harmless no-ops and the bottom-anchored controls/banner block just sits
  -- at the drawer's foot with the middle stretching.
  d:SetWidth(DG.WIDTH)
  d:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -CH.TITLEBAR)
  d:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  -- Sheet chrome: right corners must match the window card's radius; the drawer's
  -- top-left/bottom-left corners are square against the content area.
  -- Opaque by design (alpha 1, not 0.97): at 0.97 the Deals rows underneath ghosted through
  -- just enough to read as a rendering bug in the first in-game pass. The panel now also
  -- shifts the list out from behind it on wide windows (applyPanelInset, createFrame) --
  -- opacity is what keeps the narrower/docked case, which still overlays, honest instead.
  d.sheet = Theme.SlicedTexture(d, "BACKGROUND", Theme.MEDIA .. "card_right.png",
    { Theme.color.bg[1], Theme.color.bg[2], Theme.color.bg[3], 1 })
  d.sheet:SetAllPoints()
  d.edge = d:CreateTexture(nil, "BORDER")
  d.edge:SetColorTexture(Theme.color.border[1], Theme.color.border[2], Theme.color.border[3], Theme.color.border[4])
  d.edge:SetPoint("TOPLEFT")
  d.edge:SetPoint("BOTTOMLEFT")
  d.edge:SetWidth(1)
  d:EnableMouse(true)

  -- Task 2 restyle: the old mono "CONFIRM PURCHASE" kicker (d.title) is gone from the top of
  -- the header -- that text now lives in d.subtitle, under the item name, where it reads as a
  -- caption on the item rather than a document title above it. Nothing pins d.title (grepped
  -- every spec before removing it), so there is no field to keep/Hide() here.
  local icon = d:CreateTexture(nil, "ARTWORK")
  icon:SetSize(DG.ICON, DG.ICON)
  icon:SetPoint("TOPLEFT", Theme.pad.m, -Theme.pad.m)
  d.icon = icon

  -- Task 2 restyle: width 60 (was 56/48 -- see the pill rebuild in Theme.lua's T.Chip, and its
  -- own comment for why the pill lands at 20px tall rather than 24). Anchored -pad.m,
  -- -(pad.m+6) so the 20-tall pill's vertical center lines up with the 32px icon's own center
  -- (icon top is -pad.m, so its center sits at -(pad.m+16); a 20-tall pill centered there tops
  -- out at -(pad.m+16)+10 = -(pad.m+6)). This deliberately drops M13's old "never drift from
  -- the list's own tier column" sync: the dialog's chip now needs to fit "SUSPECT" at this
  -- bigger geometry, and the two surfaces (row chip, dialog chip) have diverged on purpose.
  local tierChip = Theme.Chip(d)
  tierChip:SetWidth(60)
  tierChip:SetPoint("TOPRIGHT", -Theme.pad.m, -(Theme.pad.m + 6))
  d.tierChip = tierChip

  local nameText = Theme.Label(d, 13)
  nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", Theme.pad.s, 0)
  nameText:SetPoint("RIGHT", tierChip, "LEFT", -Theme.pad.s, 0)
  nameText:SetWordWrap(false)
  d.nameText = nameText

  -- New (Task 2 restyle): the old title kicker's text, now a caption under the item name
  -- instead of a line above it. RIGHT-bound to nameText's own right edge purely so itemHit
  -- below (icon+name+subtitle) gets a clean two-point BOTTOMRIGHT anchor -- the text itself is
  -- short and LEFT-justified, so the bound never clips it.
  local subtitle = Theme.Num(d, 9)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
  subtitle:SetPoint("RIGHT", nameText, "RIGHT", 0, 0)
  subtitle:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  subtitle:SetText("CONFIRM PURCHASE")
  d.subtitle = subtitle

  -- A: hover tooltip over the icon+name+subtitle header, same as a row (see createRow) --
  -- Texture and FontString objects can't take mouse scripts themselves, so this is an
  -- invisible Frame spanning all three, same pattern as createHeaderRow's own header hit-frames.
  -- Task 2 restyle: BOTTOMRIGHT now targets subtitle (was nameText) so the hit region covers
  -- the new caption line too -- subtitle's own RIGHT anchor above keeps this the same width as
  -- before.
  local itemHit = CreateFrame("Frame", nil, d)
  itemHit:SetPoint("TOPLEFT", icon, "TOPLEFT")
  itemHit:SetPoint("BOTTOMRIGHT", subtitle, "BOTTOMRIGHT")
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
  -- Check panel v2: this used to live under the header, in its own reserved blank slot
  -- (DG.NOTE_H) that the second in-game pass called the single biggest hole in the dialog when
  -- a deal wasn't SUSPECT. It now shares the cards slot after the Quantity row instead -- the
  -- same rect ENTRY AVG/STRESS EXIT occupy (setDialogHeader's Show/Hide toggle below picks one
  -- or the other, never both).
  local suspectNote = Theme.Label(d, 11)
  suspectNote:SetPoint("TOPLEFT", Theme.pad.m, DG.CARDS_TOP)
  suspectNote:SetPoint("RIGHT", -Theme.pad.m, 0)
  suspectNote:SetWordWrap(true)
  suspectNote:SetTextColor(Theme.tier.SUSPECT[1], Theme.tier.SUSPECT[2], Theme.tier.SUSPECT[3])
  suspectNote:SetText("a discount this extreme usually means the market value is wrong, not that this is a bargain")
  suspectNote:Hide()
  d.suspectNote = suspectNote

  -- Verdict card: a rounded, tinted highlight behind the headline/sub-line, in reading order
  -- if not in draw order -- (F6a correction) Theme.Card is a CHILD FRAME, which defaults to
  -- frameLevel d+1 and therefore composites ABOVE every one of `d`'s own regions, verdictHead/
  -- verdictSub included, regardless of creation order. It reads as "behind" the text purely
  -- because its fill sits at 6-7% alpha (stampDialogFromDecision's SetTint calls below) -- the
  -- text shows straight through a wash that thin. The 2px ring (up to 30% alpha) stays clear
  -- of the glyphs because the card is padded Theme.pad.s beyond the text's own bounds, so the
  -- outline never crosses over a character. stampDialogFromDecision tints it green/red beside
  -- the two dialog.verdictHead:SetTextColor sets it already makes -- see the
  -- `dialog.verdictCard:SetTint(...)` calls there, the only lines this task adds outside this
  -- function.
  local verdictCard = Theme.Card(d, nil, nil, true)
  verdictCard:SetPoint("TOPLEFT", Theme.pad.m - Theme.pad.s, DG.VERDICT_TOP + Theme.pad.s)
  -- The bottom edge is measured from the dialog's TOP, like every other DG.*_TOP offset: a bare
  -- SetPoint("BOTTOMRIGHT", x, y) would take y from the dialog's own BOTTOMRIGHT and put the
  -- card's bottom ~180px BELOW the drawer (a full-height green ring down into the action bars
  -- in the second in-game pass). Sits just inside the verdict block's reserved bottom
  -- (DG.VERDICT_TOP - DG.VERDICT_H), padded the same Theme.pad.s as the other three edges.
  verdictCard:SetPoint("BOTTOMRIGHT", d, "TOPRIGHT", -(Theme.pad.m - Theme.pad.s), DG.VERDICT_TOP - DG.VERDICT_H + Theme.pad.s)
  d.verdictCard = verdictCard

  -- Verdict block, directly under the item header: a small live-status kicker
  -- (d.verdictLabel: LIVE VERDICT · SAFE/REFUSED/CHECKING), a prominent one-line headline (buy
  -- action or refusal sentence), a big signed profit figure (d.verdictAmount) with its own
  -- caption, and a quieter sub-line naming the stress profit -- see stampDialogFromDecision and
  -- openDialog for the text/color logic. verdictHead no longer wraps (Task 2 restyle -- the
  -- sentence fits one line at this width/font); verdictSub still does, into the fixed
  -- DG.VERDICT_HEAD_H/DG.VERDICT_SUB_H budgets above.
  -- Fix round 1: x = Theme.pad.s + Theme.pad.xs (12), NOT Theme.pad.m + Theme.pad.s (20) --
  -- the kit-values table (binding over the brief's own prose) puts every line in this block
  -- 8px inside the card rect, aligned with verdictHead/verdictAmount/verdictSub below (all of
  -- which inherit this x via their own 0-offset BOTTOMLEFT anchors off this widget/each other).
  local verdictLabel = Theme.Num(d, 9, true)
  verdictLabel:SetJustifyH("LEFT")
  verdictLabel:SetPoint("TOPLEFT", Theme.pad.s + Theme.pad.xs, DG.VERDICT_TOP - Theme.pad.s)
  d.verdictLabel = verdictLabel

  local verdictHead = Theme.Label(d, 12)
  verdictHead:SetPoint("TOPLEFT", verdictLabel, "BOTTOMLEFT", 0, -4)
  verdictHead:SetPoint("RIGHT", -Theme.pad.m, 0)
  verdictHead:SetWordWrap(false)
  d.verdictHead = verdictHead

  -- Fix round 1: SetWordWrap(false) + SetMaxLines(1), no RIGHT bound -- a RIGHT anchor here
  -- would be circular with verdictAmountNote's own LEFT anchor (BOTTOMRIGHT of this widget), so
  -- the caption is the one that ellipsizes at the sheet's edge (see verdictAmountNote just
  -- below); this just keeps a long "1234g56s" figure from wrapping into a second line and
  -- blowing the fixed DG.VERDICT_SUB_H budget.
  local verdictAmount = Theme.Num(d, 22, true)
  verdictAmount:SetJustifyH("LEFT")
  verdictAmount:SetPoint("TOPLEFT", verdictHead, "BOTTOMLEFT", 0, -4)
  verdictAmount:SetWordWrap(false)
  verdictAmount:SetMaxLines(1)
  d.verdictAmount = verdictAmount

  -- Fix round 1: bounded on the RIGHT (dialog's own right inset, same idiom verdictHead uses
  -- two-point-anchor style just above) + SetWordWrap(false) -- at Theme.Scale 1.3 a big amount
  -- plus this caption's full 24 characters can run past the 320px sheet; this caption is the
  -- one that ellipsizes, not the amount (see verdictAmount's own comment above).
  local verdictAmountNote = Theme.Num(d, 9)
  verdictAmountNote:SetJustifyH("LEFT")
  verdictAmountNote:SetPoint("BOTTOMLEFT", verdictAmount, "BOTTOMRIGHT", Theme.pad.s, 3)
  verdictAmountNote:SetPoint("RIGHT", -Theme.pad.m, 0)
  verdictAmountNote:SetWordWrap(false)
  verdictAmountNote:SetMaxLines(1)
  verdictAmountNote:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  verdictAmountNote:SetText("EST. PROFIT AFTER AH CUT")
  d.verdictAmountNote = verdictAmountNote

  local verdictSub = Theme.Num(d, 9)
  verdictSub:SetJustifyH("LEFT")
  verdictSub:SetPoint("TOPLEFT", verdictAmount, "BOTTOMLEFT", 0, -4)
  verdictSub:SetPoint("RIGHT", -Theme.pad.m, 0)
  verdictSub:SetWordWrap(true)
  verdictSub:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  d.verdictSub = verdictSub

  -- Label/value grid: one row per number the player needs to decide with, aligned two-column
  -- (Theme.Label left, Theme.Num right) -- updateDialogAmounts re-stamps the value slots in
  -- place as fresher quotes come in; the grid itself never grows or reflows (fixed Y per row,
  -- same reasoning as DG.GRID_TOP/DG.GRID_ROW_H above: a chained anchor would let a wrapped
  -- neighbor note reflow rows underneath it).
  local function gridRow(top, index, label)
    local y = top - (index - 1) * DG.GRID_ROW_H
    local labelFS = Theme.Label(d, 11)
    labelFS:SetPoint("TOPLEFT", Theme.pad.m, y)
    labelFS:SetText(label)

    local valueFS = Theme.Num(d, 12)
    valueFS:SetPoint("TOPRIGHT", -Theme.pad.m, y)
    -- Bounded on the left by its own label, right-justified, single line: an unbounded
    -- TOPRIGHT-only FontString grows leftward without limit, and the Reason row's full
    -- sentence ("Cheaper listings remain...") was painting straight past the dialog's edge
    -- onto whatever the window sat over. Bounded, the engine ellipsizes it instead.
    valueFS:SetPoint("LEFT", labelFS, "RIGHT", Theme.pad.s, 0)
    valueFS:SetJustifyH("RIGHT")
    valueFS:SetWordWrap(false)
    valueFS:SetMaxLines(1)
    return labelFS, valueFS
  end

  -- Quantity + its quick-fill row: the one interactive control in this dialog besides Buy/
  -- Cancel, so it lives here -- above the Details toggle, always reachable -- rather than
  -- inside the collapsible evidence grid below. Fix 2: commodities only editable (via qtyBox);
  -- an item auction's row instead shows this plain dim qtyLotText ("N (whole lot)"), since a
  -- lot cannot be split. refreshQtyRow (above) toggles which of the two is shown/enabled.
  -- Task 2 restyle: a bespoke "QTY" kicker (Theme.Num, fgDim, uppercase), not gridRow's shared
  -- Theme.Label(d, 11) -- the evidence grid below still uses gridRow as-is (out of scope for
  -- this restyle), and gridRow itself cannot change without also restyling every evidence row.
  -- The row reads left to right like the mockup -- QTY, the box, "of N" -- instead of a kicker
  -- stranded at the left with the box and chips right-aligned (the second in-game pass called
  -- that "crooked"). The label's TOP sits 4px under DG.QTY_TOP so its ~11px line centres on the
  -- 18px box; the box and the "of N" text then hang off the label's vertical centre.
  local qtyLabel = Theme.Num(d, 9)
  qtyLabel:SetJustifyH("LEFT")
  qtyLabel:SetPoint("TOPLEFT", Theme.pad.m, DG.QTY_TOP - 4)
  qtyLabel:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  qtyLabel:SetText("QTY")
  d.qtyLabel = qtyLabel

  -- Non-commodity fallback ("N (whole lot)"): takes the box's place after the label, bounded on
  -- the right so a long lot count ellipsizes instead of growing past the sheet (gridRow's own
  -- valueFS reasoning -- an unbounded single-point FontString grows without limit).
  -- TOPLEFT off qtyLabel's TOPRIGHT, not LEFT: a LEFT+RIGHT pair are both centre-Y constraints,
  -- and they disagreed here -- LEFT centred on qtyLabel, RIGHT centred on the whole drawer -- so
  -- the anchor that actually pinned the top was accidental. TOPLEFT supplies the top explicitly;
  -- RIGHT still bounds the width for the ellipsis.
  local qtyLotText = Theme.Num(d, 12)
  qtyLotText:SetJustifyH("LEFT")
  qtyLotText:SetPoint("TOPLEFT", qtyLabel, "TOPRIGHT", Theme.pad.s, 0)
  qtyLotText:SetPoint("RIGHT", -Theme.pad.m, 0)
  qtyLotText:SetWordWrap(false)
  qtyLotText:SetMaxLines(1)
  qtyLotText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  d.qtyLotText = qtyLotText

  -- 64x18: check panel v2 split this off DG.GRID_ROW_H (now 18, the evidence grid's own row
  -- height) into its own DG.QTY_BOX_H constant, since the two no longer share one number.
  local qtyBox = makeQtyEditBox(d, 64, DG.QTY_BOX_H)
  qtyBox:SetPoint("LEFT", qtyLabel, "RIGHT", Theme.pad.s, 0)
  d.qtyBox = qtyBox

  local qtyOfLabel = Theme.Label(d, 11) -- dim "of N" -- shown when the true available qty is known
  qtyOfLabel:SetPoint("LEFT", qtyBox, "RIGHT", Theme.pad.s, 0)
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
  -- applyChosenQty (same path qtyBox.onCommit uses -- see applyQuickFillQty). Laid out left to
  -- right from the dialog's left margin (25% ... 100%), under the QTY row it belongs to -- the
  -- mockup's chip strip; four 36px chips plus "of N" do not fit beside the box at 320 wide.
  local quickFillBtns = {}
  local prevBtn
  for i = 1, #DG.QTY_QUICKFILL_PCTS do
    local pct = DG.QTY_QUICKFILL_PCTS[i]
    local btn = Theme.Button(d, "ghost", "badge")
    btn:SetSize(DG.QTY_QUICKFILL_W, DG.QTY_QUICKFILL_H)
    if prevBtn then
      btn:SetPoint("TOPLEFT", prevBtn, "TOPRIGHT", Theme.pad.xs, 0)
    else
      -- 24 = the 20px label line + pad.xs(4) gap above this row -- DG.QTY_H's own two
      -- components (see that constant's comment) -- not DG.GRID_ROW_H, which is the unrelated
      -- evidence-grid row height and no longer sized to match.
      btn:SetPoint("TOPLEFT", Theme.pad.m, DG.QTY_TOP - 24)
    end
    btn:SetLabel(pct .. "%")
    btn:SetScript("OnClick", function() applyQuickFillQty(pct) end)
    quickFillBtns[pct] = btn
    prevBtn = btn
  end
  d.quickFillBtns = quickFillBtns

  -- Check panel v2: ENTRY AVG / STRESS EXIT cards, directly under the Quantity row -- the
  -- mockup's own layout, and the fix for the dialog reading as a column of holes (no header
  -- note, no summary before the collapsed grid). Two Theme.Card(small=true) plaques side by
  -- side, split at the dialog's own horizontal center so each gets an equal half of the
  -- content width. d.suspectNote (above) shares this exact rect for SUSPECT deals -- the
  -- setDialogHeader Show/Hide toggle beside its own suspectNote line picks one or the other.
  local entryCard = Theme.Card(d, nil, nil, true)
  entryCard:SetHeight(40)
  entryCard:SetPoint("TOPLEFT", Theme.pad.m, DG.CARDS_TOP)
  entryCard:SetPoint("RIGHT", d, "CENTER", -Theme.pad.xs, 0)
  d.entryCard = entryCard

  -- fix round 1: bounded on the RIGHT + SetWordWrap(false) -- the file's own gridRow/
  -- verdictAmountNote comments already warn that an unbounded single-point FontString grows
  -- without limit; a caption this short never actually reaches the card's right edge, but the
  -- pattern stays consistent rather than being the one label in this dialog left unbounded.
  local entryCaption = Theme.Num(entryCard, 9)
  entryCaption:SetJustifyH("LEFT")
  entryCaption:SetPoint("TOPLEFT", Theme.pad.s, -6)
  entryCaption:SetPoint("RIGHT", -Theme.pad.s, 0)
  entryCaption:SetWordWrap(false)
  entryCaption:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  entryCaption:SetText("ENTRY AVG")

  local entryValue = Theme.Num(entryCard, 12, true)
  entryValue:SetJustifyH("LEFT")
  entryValue:SetPoint("TOPLEFT", entryCaption, "BOTTOMLEFT", 0, -2)
  entryValue:SetPoint("RIGHT", -Theme.pad.s, 0)
  entryValue:SetWordWrap(false)
  -- fix round 1: Theme.Num does not tint (see its own comment -- callers own color), so without
  -- this the amount rendered in the font's raw white rather than the dialog's own fg tone every
  -- other stamped number in this dialog uses.
  entryValue:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
  d.entryValue = entryValue

  local exitCard = Theme.Card(d, nil, nil, true)
  exitCard:SetHeight(40)
  exitCard:SetPoint("LEFT", d, "CENTER", Theme.pad.xs, 0)
  exitCard:SetPoint("TOPRIGHT", -Theme.pad.m, DG.CARDS_TOP)
  d.exitCard = exitCard

  local exitCaption = Theme.Num(exitCard, 9)
  exitCaption:SetJustifyH("LEFT")
  exitCaption:SetPoint("TOPLEFT", Theme.pad.s, -6)
  exitCaption:SetPoint("RIGHT", -Theme.pad.s, 0)
  exitCaption:SetWordWrap(false)
  exitCaption:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  exitCaption:SetText("STRESS EXIT")

  local exitValue = Theme.Num(exitCard, 12, true)
  exitValue:SetJustifyH("LEFT")
  exitValue:SetPoint("TOPLEFT", exitCaption, "BOTTOMLEFT", 0, -2)
  exitValue:SetPoint("RIGHT", -Theme.pad.s, 0)
  exitValue:SetWordWrap(false)
  exitValue:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
  d.exitValue = exitValue

  -- Details toggle: the 12-row evidence grid used to be the whole dialog below the item
  -- header; now it is opt-in, collapsed by default, restored per the player's own last choice
  -- (GC.db.settings.sniper.dialogDetailsOpen) rather than re-defaulting shut every time.
  -- "badge", not "plaque": DG.TOGGLE_H is 22px (Task 2 restyle, was 17 -- a shared layout
  -- constant that DG.GRID_TOP and the FIXED_HEIGHT_* budgets flow from). PLAQUE_SLICE (12) is
  -- not below half of 22 (11) -- Theme.lua's own margin invariant (see PLAQUE_SLICE's
  -- comment) -- so plaque would notch this button's corners; BADGE_SLICE (6) is safely below.
  local detailsToggle = Theme.Button(d, "ghost", "badge")
  detailsToggle:SetHeight(DG.TOGGLE_H)
  detailsToggle:SetPoint("TOPLEFT", Theme.pad.m, DG.TOGGLE_TOP)
  detailsToggle:SetPoint("TOPRIGHT", -Theme.pad.m, DG.TOGGLE_TOP)
  d.detailsToggle = detailsToggle

  -- The ten immutable decision/evidence fields -- collapsed behind Details above. Every pair
  -- this loop builds is tracked in d.evidenceRows purely so applyDetailsState (below) can
  -- Show()/Hide() both halves of each row together; the values themselves are still stamped
  -- unconditionally by stampDialogFromDecision whether the row is visible or not, so expanding
  -- Details never shows anything stale.
  d.evidenceRows = {}
  local function evidenceRow(index, label)
    local labelFS, valueFS = gridRow(DG.GRID_TOP, index, label)
    d.evidenceRows[#d.evidenceRows + 1] = { label = labelFS, value = valueFS }
    return valueFS
  end
  local decisionStatusText = evidenceRow(1, "Status")
  local unitPriceText = evidenceRow(2, "Entry price (avg fill)")
  local totalCostText = evidenceRow(3, "Entry total")
  local exitUnitText = evidenceRow(4, "Stress exit unit")
  local profitText = evidenceRow(5, "Stress profit")
  local mvText = evidenceRow(6, "Market reference")
  local soldText = evidenceRow(7, "Sold/day")
  local sellThroughText = evidenceRow(8, "Sell-through")
  local sourceAgeText = evidenceRow(9, "Source age")
  local reasonText = evidenceRow(10, "Reason")
  d.decisionStatusText = decisionStatusText
  d.unitPriceText, d.totalCostText, d.exitUnitText = unitPriceText, totalCostText, exitUnitText
  d.profitText, d.mvText, d.soldText = profitText, mvText, soldText
  d.sellThroughText, d.sourceAgeText, d.reasonText = sellThroughText, sourceAgeText, reasonText

  -- Where diagnosticText/mvNote/status actually sit is a function of dialog.detailsOpen --
  -- resizeDialogDiagnostics (above) re-anchors them on every stamp and every toggle click, so
  -- the SetPoint calls below are only a safe initial placement before that first runs.
  d.evidenceTopOpen = DG.EVIDENCE_BOTTOM_OPEN
  d.evidenceTopClosed = DG.EVIDENCE_BOTTOM_CLOSED

  -- Sits between the grid and the status line; shown only when the clamp above actually bit.
  local mvNote = Theme.Label(d, 11)
  mvNote:SetPoint("TOPLEFT", Theme.pad.m, DG.EVIDENCE_BOTTOM_CLOSED)
  mvNote:SetPoint("RIGHT", -Theme.pad.m, 0)
  mvNote:SetWordWrap(true)
  mvNote:SetTextColor(Theme.color.red[1], Theme.color.red[2], Theme.color.red[3])
  mvNote:Hide()
  d.mvNote = mvNote

  -- Hidden unless GC.db.settings.sniper.debug is on (see resizeDialogDiagnostics) -- this is
  -- what a bug report gets copied from, not something a player one click from spending gold
  -- needs to see by default. The text it is given stays byte-identical either way.
  local diagnosticText = Theme.Label(d, 11)
  diagnosticText:SetPoint("TOPLEFT", Theme.pad.m, DG.EVIDENCE_BOTTOM_CLOSED)
  diagnosticText:SetPoint("RIGHT", -Theme.pad.m, 0)
  diagnosticText:SetHeight(d.diagnosticMinimumHeight)
  diagnosticText:SetJustifyH("LEFT")
  diagnosticText:SetWordWrap(true)
  diagnosticText:Hide()
  d.diagnosticText = diagnosticText

  -- Task 2 restyle: Theme.Num (was Theme.Label(d, 11)), CENTER-justified (Theme.Num defaults
  -- RIGHT) -- a centered status line reads as a system message, not a left-aligned label/value
  -- row like the grid above it. setDialogStatus (above) still owns text/color.
  local status = Theme.Num(d, 10)
  status:SetJustifyH("CENTER")
  status:SetPoint("TOPLEFT", Theme.pad.m, DG.EVIDENCE_BOTTOM_CLOSED)
  status:SetPoint("RIGHT", -Theme.pad.m, 0)
  status:SetWordWrap(true)
  d.status = status

  -- Applies (and, on a real toggle click, flips and persists) whether the evidence grid is
  -- shown. `dialog` -- the module upvalue -- is still nil the one time this runs from inside
  -- createDialog itself, seeding the initial state; openDialog's own stampDialogFromDecision
  -- call, right after `dialog = dialog or createDialog()`, performs the first real resize.
  local function applyDetailsState(open)
    -- d.detailsOpen starts as the RAW request and is persisted immediately, before the F5
    -- spill guard below can downgrade it -- sniper_dialog_verdict_spec's "persists the open/
    -- closed choice" test pins this exact `cfg.dialogDetailsOpen = d.detailsOpen` line (a
    -- protected spec this task may not modify), so the persisted value has to keep riding on
    -- d.detailsOpen itself rather than a second requestedOpen local. Net effect is the same
    -- either way: a saved "open" preference survives a momentarily short window and takes
    -- effect again once it's resized back up, because it was written here, before the guard
    -- had a chance to force d.detailsOpen back to false for this session's visuals.
    -- `dialog` gates the write too (same nil-during-construction predicate the status write
    -- below already relies on): the one call that runs before `dialog` exists is createDialog's
    -- own construction seed above, and that seed is GoldCap's boot value, not a player's choice
    -- -- earlier builds let it fall straight through to cfg, so every fresh dialog re-persisted
    -- false and no saved-default migration (Core/Init.lua's migrateSniperDialogDetails) could
    -- ever stick. Every real caller -- the toggle's own OnClick, and the resize re-apply in
    -- createFrame's OnSizeChanged (below) -- already has `dialog` set, so this changes nothing
    -- for an actual player action or a real resize.
    d.detailsOpen = open and true or false
    local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
    if cfg and dialog then cfg.dialogDetailsOpen = d.detailsOpen end
    -- F5 (whole-branch review): the open grid is a fixed-offset block below the toggle, not
    -- something the drawer can grow to fit -- SetHeight is an anchor-overridden no-op (see
    -- createDialog's own drawer-anchor comment), so a short window can't be rescued by growing
    -- around the open layout the way the old centered modal could. Refuse the open instead of
    -- silently spilling the grid past the drawer's actual bottom -- a lying toggle (says "open"
    -- while the rows are cut off) is worse than a plain refusal. This runs AFTER the persist
    -- above on purpose (see that comment): only this session's visuals get forced shut.
    --
    -- (fix round, "docked SHOW DETAILS dead") The diagnostic block (diagnosticGaps +
    -- diagnosticMinimumHeight) is only ever laid out by resizeDialogDiagnostics's debugOn
    -- branch -- a normal player draws nothing there. Reserving it here unconditionally made the
    -- guard demand DG.FIXED_HEIGHT_OPEN(548) + 8 + 36 = 592 even for players who will never see
    -- a diagnostic block at all, and the docked AH drawer (~565px, no resize handle) can never
    -- clear that -- a dead toggle with an impossible instruction. Same predicate
    -- resizeDialogDiagnostics itself reads, so the two can never disagree about what's reserved.
    local debugOn = (cfg and cfg.debug) and true or false
    local needed = DG.FIXED_HEIGHT_OPEN + (debugOn and (d.diagnosticGaps + d.diagnosticMinimumHeight) or 0)
    -- Check panel v2 fix round 1: `d:SetSize` (createDialog, above) always gives `d` a real,
    -- positive height before this ever runs, and every anchor in this dialog resolves against
    -- that already-sized frame -- `h` is not actually expected to come back nil/0 here. The
    -- `h and h > 0` half of this check is defensive widening, not a reachable scenario: if the
    -- engine ever DID hand back an unresolved height, treating it as "fits" is the safer failure
    -- than refusing a saved/default "open" over a number this guard can't trust yet.
    local h = d:GetHeight()
    if d.detailsOpen and h and h > 0 and h < needed then
      d.detailsOpen = false
      -- Check panel v2 fix round 1: `dialog` (the module upvalue) is still nil the one time
      -- this guard runs from inside createDialog's own construction-time seed (see this
      -- function's opening comment) -- that seed is not a player action, so it must stay
      -- silent instead of announcing "Enlarge the window..." before the player has touched
      -- anything. Every later call (the toggle's own OnClick) has `dialog` set.
      --
      -- Fix wave: `d.detailsQuiet` additionally silences this during createFrame's OnSizeChanged
      -- re-apply (below) -- a drag-resize re-runs this guard on every pixel crossed, and without
      -- the quiet flag a downsize past the fit floor would spam this status line the whole way
      -- down instead of just quietly closing the grid.
      if dialog and not d.detailsQuiet then setDialogStatus("Enlarge the window to see details") end
    end
    d.fixedHeight = d.detailsOpen and DG.FIXED_HEIGHT_OPEN or DG.FIXED_HEIGHT_CLOSED
    -- Task 2 restyle: uppercase kit-value labels (were "Show/Hide details"); the
    -- `d.detailsToggle:SetLabel(` call prefix itself is the pinned text (sniper_dialog_
    -- verdict_spec's "Details toggle wiring" describe block), not these strings.
    d.detailsToggle:SetLabel(d.detailsOpen and "HIDE DETAILS ▾" or "SHOW DETAILS ▸")
    for _, pair in ipairs(d.evidenceRows) do
      if d.detailsOpen then
        pair.label:Show()
        pair.value:Show()
      else
        pair.label:Hide()
        pair.value:Hide()
      end
    end
    if dialog then resizeDialogDiagnostics() end
  end
  detailsToggle:SetScript("OnClick", function() applyDetailsState(not d.detailsOpen) end)
  local savedCfg = GC.db and GC.db.settings and GC.db.settings.sniper
  applyDetailsState(savedCfg and savedCfg.dialogDetailsOpen)
  -- Exposed so createFrame's OnSizeChanged (below) can re-apply the saved preference on every
  -- resize without reaching into createDialog's locals -- the only handle the rest of the file
  -- gets on this closure, same idiom as f.applyPanelInset.
  d.applyDetailsState = applyDetailsState

  -- Anchored off the BOTTOM, above the stacked buttons, and hidden by default. (F6b
  -- correction) In the old centered modal, showing it grew the dialog by exactly its own
  -- height, visibly changing the window's shape. In the check drawer that SetHeight is an
  -- anchor-overridden no-op (see createDialog's own drawer-anchor comment) -- the banner is
  -- now a fixed slot in the bottom-anchored block, always reserved whether shown or not. The
  -- slot sits ABOVE the status line (DG.CONTROLS_H + DG.STATUS_H + pad.xs up from the bottom),
  -- so the status stays glued to the buttons and the empty slot never reads as a gap between
  -- them; F4's resizeDialogDiagnostics anchors `status` at DG.CONTROLS_H to match.
  -- Task 2 restyle: Theme.Card(small=true) -- a rounded plaque.png/PLAQUE_SLICE(12) alarm
  -- instead of Theme.Panel's flat rectangle + edgeBorder. Sized LIM.REQUOTE_BANNER_HEIGHT (46)
  -- tall by up to DG.WIDTH-2*pad.m (296) wide -- margin 12 is well under half the smallest
  -- edge (23) either way. Fill tinted red@0.2 at construction (the `fill` argument), the same
  -- SetVertexColor path slicedTexture always uses -- SetColorTexture on `.bg` (the old call)
  -- would have stripped the texture file the moment it became a real sliced surface.
  local banner = Theme.Card(d, { Theme.color.red[1], Theme.color.red[2], Theme.color.red[3], 0.2 }, nil, true)
  banner:SetHeight(LIM.REQUOTE_BANNER_HEIGHT)
  banner:SetPoint("BOTTOMLEFT", Theme.pad.m, DG.CONTROLS_H + DG.STATUS_H + Theme.pad.xs)
  banner:SetPoint("BOTTOMRIGHT", -Theme.pad.m, DG.CONTROLS_H + DG.STATUS_H + Theme.pad.xs)

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

  -- "badge", not "plaque": DG.CANCEL_H is 22px (Task 2 restyle, was 20), another shared/pinned
  -- constant (see detailsToggle's own comment above) -- PLAQUE_SLICE (12) is not below half
  -- of 22 (11), BADGE_SLICE (6) is.
  -- Bottom-most, UNDER the primary (mockup order: BUY, then CANCEL) -- the secondary action
  -- sits furthest from the verdict it declines.
  local cancelBtn = Theme.Button(d, "ghost", "badge")
  cancelBtn:SetHeight(DG.CANCEL_H)
  cancelBtn:SetPoint("BOTTOMLEFT", Theme.pad.m, Theme.pad.m)
  cancelBtn:SetPoint("BOTTOMRIGHT", -Theme.pad.m, Theme.pad.m)
  -- Task 2 restyle: uppercase display only -- every setDialogHeader/close-flow call site below
  -- still passes "Cancel"/"Close" and dialog.cancelBtn.label reads back exactly that.
  cancelBtn:SetUppercase(true)
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

  -- Full-width primary button, directly above Cancel: the single most-clicked control in this
  -- window. "plaque" is safe here (unlike cancelBtn/detailsToggle above): DG.PRIMARY_H is 32px
  -- (Task 2 restyle, was 26 -- the kit's "big buy" height), and PLAQUE_SLICE (12) IS below half
  -- of that (16). Height stays DG.PRIMARY_H -- that constant also drives DG.CONTROLS_H/
  -- DG.FIXED_HEIGHT_*, so it isn't a per-button size free to change here.
  local primaryBtn = Theme.Button(d, "primary", "plaque")
  primaryBtn:SetHeight(DG.PRIMARY_H)
  primaryBtn:SetPoint("BOTTOMLEFT", Theme.pad.m, Theme.pad.m + DG.CANCEL_H + Theme.pad.xs)
  primaryBtn:SetPoint("BOTTOMRIGHT", -Theme.pad.m, Theme.pad.m + DG.CANCEL_H + Theme.pad.xs)
  -- Task 2 restyle: uppercase display only -- setPrimaryLabel's "Buy"/"Check" calls elsewhere
  -- in this file are untouched, and dialog.primaryBtn.label still reads back the exact string.
  primaryBtn:SetUppercase(true)
  primaryBtn:SetLabel("Buy")
  primaryBtn:SetScript("OnClick", onDialogPrimaryClick)
  d.primaryBtn = primaryBtn

  -- Esc (via UISpecialFrames) hides the dialog. Before Confirm that follows the ordinary
  -- abort path; after Confirm abortRowPurchase deliberately preserves server ownership, so
  -- Esc can never discard the token/final quote while a terminal event is still possible.
  d:SetScript("OnHide", function()
    -- Panel-inset reset comes first and unconditionally, same reasoning as
    -- GC.Sniper.NotifyDialogClosed() right below it: the deals list must snap back to the
    -- plain gutter anchor whenever the sheet stops covering it, regardless of why it closed.
    if frame and frame.applyPanelInset then frame.applyPanelInset(false) end
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

  -- Mirror of the OnHide reset above: every time the sheet actually shows, the deals list
  -- shifts aside behind it (still gated on the window being wide enough -- see applyPanelInset).
  d:SetScript("OnShow", function()
    if frame and frame.applyPanelInset then frame.applyPanelInset(true) end
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
  if deal.stale and prewarm and (GetTime() - prewarm.at) <= LIM.PREWARM_TTL_SECONDS then
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
    -- Task 2 restyle: the discovery stamp just above already routed through
    -- stampDialogFromDecision's refusal branch (discovery.buyable is always nil), so without
    -- this the kicker would read REFUSED for the couple of ticks a real check takes -- override
    -- to the neutral CHECKING state for exactly that window. Guarded the same way every other
    -- verdictLabel/verdictAmount write is.
    if dialog.verdictLabel then
      dialog.verdictLabel:SetText("LIVE VERDICT · CHECKING")
      dialog.verdictLabel:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
    end
    if dialog.verdictAmount then
      dialog.verdictAmount:SetText("—")
      dialog.verdictAmount:Show()
    end
    -- Fix round 1: caption goes with the amount, checking or not (see stampDialogFromDecision's
    -- own show/hide pair for the buyable/refusal branches).
    if dialog.verdictAmountNote then dialog.verdictAmountNote:Show() end
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
  -- to wait LIM.REQUERY_TIMEOUT_SECONDS out when the AH session it belonged to just ended anyway).
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
    local chip = Theme.TierMark(row)
    row.tierChip = chip
    return chip
  elseif col.key == "buy" then
    local btn = Theme.Button(row, "primary", "badge")
    btn:SetHeight(22)
    -- Task 2 restyle: uppercase display only -- setRowDeal's "Buy"/"Check"/verdict.status
    -- ("AVOID") calls below are untouched, and row.buy.label still reads back the exact string.
    btn:SetUppercase(true)
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
  -- anchorColumns shows every fixed cell unconditionally; a watching row (pin placeholder) has
  -- no action to take, so hide the Buy button back down after the fact.
  if row.deal and row.deal.pinPlaceholder then row.buy:Hide() end
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
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * WIN.ROW_HEIGHT)
  row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(index - 1) * WIN.ROW_HEIGHT)
  row:SetHeight(WIN.ROW_HEIGHT)

  -- E.1 zebra + hover: full-width BACKGROUND textures, drawn behind every other row widget
  -- (including the Buy button) regardless of creation order -- BACKGROUND always renders
  -- under ARTWORK. The zebra fill alternates by POOL index, not by the deal's position in
  -- the current sorted view, so it stays visually stable across a resort/rescan instead of
  -- flickering as rows are reassigned to different deals.
  -- Rounded fills inset 1px top/bottom (2px total) and 2px left/right. The scrollbar lives in
  -- WIN.CONTENT_RIGHT_GUTTER, OUTSIDE the row, so the fill runs to the row's own right edge --
  -- the action button sits flush with that edge, and a shorter fill (the old 26px right inset)
  -- left half the button hanging off the hover wash. The fill is 30px tall after the insets
  -- (32px row height minus 2px), so margin 12 <= 15 = half of 30, satisfying the constraint.
  local zc = Theme.color.zebra
  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetTexture(Theme.MEDIA .. "plaque.png")
  zebra:SetTextureSliceMargins(12, 12, 12, 12)
  zebra:SetVertexColor(zc[1], zc[2], zc[3], (index % 2 == 1) and zc[4] or 0)
  zebra:SetPoint("TOPLEFT", 2, -1)
  zebra:SetPoint("BOTTOMRIGHT", -2, 1)
  row.zebra = zebra

  -- Persistent full-row wash for a pinned (watched) row, so tracking an item reads at a
  -- glance instead of hanging on a 2px rail alone. Sublevel 1 (above the zebra fill), created
  -- BEFORE the hover highlight at the same sublevel so the hover wash still draws on top of
  -- it -- same-sublevel textures stack in creation order (the HOT flash texture below is
  -- created after both and so draws topmost of the three). Shown/hidden by setRowDeal off the
  -- pin state; the watch color at low alpha, matching the rail it accompanies.
  local pc = Theme.color.watch
  local pinBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  pinBg:SetTexture(Theme.MEDIA .. "plaque.png")
  pinBg:SetTextureSliceMargins(12, 12, 12, 12)
  pinBg:SetVertexColor(pc[1], pc[2], pc[3], 0.09)
  pinBg:SetPoint("TOPLEFT", 2, -1)
  pinBg:SetPoint("BOTTOMRIGHT", -2, 1)
  pinBg:Hide()
  row.pinBg = pinBg

  local hc = Theme.color.hover
  local highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1) -- sublevel 1: above zebra, still under ARTWORK
  highlight:SetTexture(Theme.MEDIA .. "plaque.png")
  highlight:SetTextureSliceMargins(12, 12, 12, 12)
  highlight:SetVertexColor(hc[1], hc[2], hc[3], hc[4])
  highlight:SetPoint("TOPLEFT", 2, -1)
  highlight:SetPoint("BOTTOMRIGHT", -2, 1)
  highlight:Hide()
  row.highlight = highlight

  -- The new-HOT-deal ping fades its OWN texture. It used to animate row.highlight's alpha,
  -- which left the hover wash inheriting whatever alpha the animation last wrote.
  local flash = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  flash:SetTexture(Theme.MEDIA .. "plaque.png")
  flash:SetTextureSliceMargins(12, 12, 12, 12)
  flash:SetVertexColor(hc[1], hc[2], hc[3], 0.35)
  flash:SetPoint("TOPLEFT", 2, -1)
  flash:SetPoint("BOTTOMRIGHT", -2, 1)
  flash:Hide()
  row.flash = flash

  -- Sniper v3 §3 ping: 1.5s alpha fade-out flash for a newly-surfaced HOT deal (see
  -- pingNewHotDeals/flashRow above advanceBrowseScan). Built once per pooled row rather than
  -- per-flash -- an AnimationGroup is a real object with nontrivial construction cost, and
  -- rows are reused across scans/passes via the same pool. It targets its OWN dedicated
  -- texture (`flash`, above) rather than `highlight` -- the highlight is shown/hidden purely
  -- by OnEnter/OnLeave (see below) and must never inherit whatever alpha an in-flight
  -- animation last wrote. OnFinished hides `flash` and resets its alpha back to 1 so a later
  -- flash isn't dimmed.
  --
  -- (fix round 1, "insurance from cannot-verify") The group is built on the ROW frame
  -- (`row:CreateAnimationGroup()`), not `flash:CreateAnimationGroup()` -- Frame is
  -- unambiguously a supported AnimationGroup owner; Texture's support for the same call
  -- wasn't independently verified against the live client, so this avoids betting createRow
  -- (which every pooled row, and therefore refreshRows() itself, depends on) on a Region-API
  -- gap. SetTarget points the specific Alpha animation at `flash` instead.
  local flashAnim = row:CreateAnimationGroup()
  local flashAlpha = flashAnim:CreateAnimation("Alpha")
  flashAlpha:SetTarget(flash)
  flashAlpha:SetFromAlpha(1)
  flashAlpha:SetToAlpha(0)
  flashAlpha:SetDuration(1.5)
  flashAlpha:SetSmoothing("OUT")
  flashAnim:SetScript("OnFinished", function()
    flash:Hide()
    flash:SetAlpha(1)
  end)
  row.flashAnim = flashAnim

  -- Sniper v3: 3px gold left-rail shown alongside the hover highlight -- the accent that
  -- marks "this row" beyond the flat highlight wash alone. Inset 6px top/bottom (kit value)
  -- so it reads as a short accent mark rather than a bar spanning the full row edge to edge.
  local rail = row:CreateTexture(nil, "BACKGROUND", nil, 2)
  rail:SetPoint("TOPLEFT", 0, -6)
  rail:SetPoint("BOTTOMLEFT", 0, 6)
  rail:SetWidth(3)
  rail:SetColorTexture(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3])
  rail:Hide()
  row.rail = rail

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(WIN.ICON_SIZE, WIN.ICON_SIZE)
  icon:SetPoint("LEFT")
  row.icon = icon

  local nameText = Theme.Label(row, 12)
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
    -- What the background check found, in words. A refused row that the toolbar toggle has
    -- brought back into view is otherwise a status code and nothing else.
    local verdict = verdictFor(self.deal)
    if verdict then
      GameTooltip:AddLine(" ")
      if verdict.buyable then
        GameTooltip:AddLine("GoldCap: checked live -- safe to buy", 0.25, 0.85, 0.25)
      else
        GameTooltip:AddLine(("GoldCap: %s -- %s"):format(verdict.status or "refused",
          verdict.reason or "live verification required"), 1, 0.82, 0)
      end
    end
    -- The hidden Buy button (setRowDeal's placeholder branch) leaves no control on this row to
    -- explain itself, so the tooltip carries the reason instead: watched, but nothing to buy.
    if self.deal.pinPlaceholder then
      GameTooltip:AddLine("Watching — pinned, but not a deal right now",
        Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
    end
    GameTooltip:AddLine(isPinned(self.deal.itemID)
      and "Right-click to stop watching this item"
      or "Right-click to watch this item closely", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
    -- A watched row keeps its blue rail after the cursor leaves -- that is the whole point of
    -- it. Only the plain hover accent goes away here.
    if not (self.deal and isPinned(self.deal.itemID)) then self.rail:Hide() end
    if hoveredRow == self then
      hoveredRow = nil
      refreshRows()
    end
    -- A left press that started on this row and then dragged off it (cursor left before the
    -- button came back up) must not act when it eventually lifts somewhere else -- see
    -- OnMouseUp below.
    self.leftPressed = nil
    GameTooltip:Hide()
  end)

  -- Right-click pins. Left-click acts on the whole row. Both mouse-down and mouse-up are
  -- wired, not RegisterForClicks: `row` is a plain Frame, so it has no RegisterForClicks at
  -- all (that is a Button method -- the guarded call that used to sit here was a no-op
  -- dressed up as intent). The first attempt used OnMouseUp alone and did not fire from a
  -- trackpad two-finger tap; OnMouseDown alone is the same single-phase bet in the other
  -- direction, so GC.Sniper._RowPinEvent listens to both and latches so one physical
  -- right-click press toggles exactly once -- see its own comment.
  --
  -- Firing the PIN on the press is fine HERE and only here: pinning is a reversible view
  -- preference, not a purchase. Nothing on THIS path (the pin dispatch) reaches a protected
  -- call -- _RowPinEvent is a plain settings-list mutation.
  --
  -- The left-click ACTION is different: it runs the exact same onBuyClick as row.buy's own
  -- OnClick (buildRowCell, above), on release, gated by `leftPressed` -- armed only by a down
  -- that landed on this row and cleared by OnLeave, so a press that drags off the row before
  -- releasing is not this row's click, and a right-click or a disabled/hidden Buy button never
  -- fires it. This mirrors ordinary button-click semantics rather than adding a new one: it
  -- does not reach a protected call directly, and everything downstream of onBuyClick (Check,
  -- the dialog, the eventual purchase) still runs its own live re-verification and still needs
  -- its own separate hardware click to arm a purchase.
  row:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then self.leftPressed = true end
    GC.Sniper._RowPinEvent(self, "down", button)
  end)
  row:SetScript("OnMouseUp", function(self, button)
    -- A left click anywhere on the row is the row's action (the same handler as row.buy);
    -- the button itself sits above the row and keeps its own click. Disabled = no action.
    if button == "LeftButton" and self.leftPressed then
      self.leftPressed = nil
      if self.buy and self.buy:IsShown() and self.buy:IsEnabled() then onBuyClick(self) end
    end
    GC.Sniper._RowPinEvent(self, "up", button)
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
  if h < WIN.RESIZE_MIN_HEIGHT then return WIN.RESIZE_MIN_HEIGHT end
  if h > WIN.RESIZE_MAX_HEIGHT then return WIN.RESIZE_MAX_HEIGHT end
  return h
end

-- T5: width is now resizable too (previously only height could change -- see the WIN.FRAME_WIDTH
-- comment near the top), so the saved geometry needs the same clamp on the other axis.
local function clampWindowWidth(w)
  if w < WIN.RESIZE_MIN_WIDTH then return WIN.RESIZE_MIN_WIDTH end
  if w > WIN.RESIZE_MAX_WIDTH then return WIN.RESIZE_MAX_WIDTH end
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
  -- A docked window's anchors belong to the auction-house host (GC.Sniper.SetDocked below);
  -- persisting them would overwrite the FLOATING geometry this field exists to remember.
  if f.goldcapDockHost then return end
  local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
  if not cfg then return end
  local point, _, _, x, y = f:GetPoint(1)
  if not point then return end
  cfg.window = { point = point, x = x, y = y, width = f:GetWidth(), height = f:GetHeight() }
end

-- D: Deals/Sell view switcher. Full Scan/Live are separate widgets untouched by this and stay
-- clickable in both views. Sell's own container, rows, and bag-count refresh are entirely
-- GC.Sell's responsibility (built once by GC.Sell.Attach in createFrame) -- this function only
-- toggles the Deals-side widgets and the rail buttons' active state.
-- The rail button owns its whole active look (fill/ring/glow/recolor) AND the
-- functional gating: active == Disable()d, exactly the contract the old text
-- recolor version enforced.
local function setTabActive(btn, active)
  btn:SetActive(active)
end

local function setView(v)
  if view == v or not frame then return end
  local previousView = view
  view = v
  -- One throttled search slot serves the whole addon: a Deals scan running behind the Sell
  -- tab starved the pricing walk's queries silently (see SellFrame.lua's advanceQuote). Auto
  -- pauses for as long as Sell is shown and resumes leaving it -- Sold never queries the AH,
  -- so switching to/from Sold neither pauses nor resumes this reason.
  if v == "sell" then
    feedAuto("pause:sell")
  elseif previousView == "sell" then
    feedAuto("resume:sell")
  end
  local isDeals = (v == "deals")
  if isDeals then
    frame.scroll:Show()
    frame.headerRow:Show()
  else
    frame.scroll:Hide()
    frame.headerRow:Hide()
  end
  -- Deals-only toolbar chrome (verify/scan/auto/divider/session -- `status` is NOT here, see
  -- f.dealsChrome's own comment in createFrame: it's a shared cross-view channel). Note:
  -- refreshSessionText re-Shows f.sessionText on its own clock whenever it runs, so it carries
  -- a `view ~= "deals"` early return of its own -- this loop's Hide() here would otherwise be
  -- undone by the very next 0.25s tick.
  for _, w in ipairs(frame.dealsChrome) do
    if isDeals then w:Show() else w:Hide() end
  end
  -- The blanket Show() above just unconditionally showed f.sessionText even if the session has
  -- zero buys (e.g. switching to Deals before ever buying this AH visit) -- re-derive right
  -- away instead of trusting that Show and waiting up to 0.25s for the ticker to hide it again.
  if isDeals then refreshSessionText() end
  setTabActive(frame.dealsTab, isDeals)
  setTabActive(frame.sellTab, v == "sell")
  setTabActive(frame.soldTab, v == "sold")
  if v == "sell" then
    if GC.Sell.Show then GC.Sell.Show() end
  elseif GC.Sell.Hide then
    GC.Sell.Hide()
  end
  if v == "sold" then
    if GC.Sold and GC.Sold.Show then GC.Sold.Show() end
  elseif GC.Sold and GC.Sold.Hide then
    GC.Sold.Hide()
  end
end

-- Settings' OnHide (SettingsFrame.lua) calls this on every close path -- Escape, DONE, the
-- gear, a rail click, or the window closing -- to re-apply the active tab's Disable() that
-- setTabActive normally owns.
-- Settings enables all three rail buttons for as long as it's open (see its own OnShow), so
-- closing it has to hand that Disable() back to whichever tab is actually current.
function GC.Sniper.RefreshRailActive()
  if not frame then return end
  setTabActive(frame.dealsTab, view == "deals")
  setTabActive(frame.sellTab, view == "sell")
  setTabActive(frame.soldTab, view == "sold")
end

-- ---------------------------------------------------------------------------
-- Chrome (Sniper v3): Theme.Panel + Theme.TitleBar replace BasicFrameTemplateWithInset;
-- everything below the title bar is stacked top-down with named row-height constants and
-- Theme.pad gaps instead of ad-hoc absolute offsets. CH itself is declared up by createDialog
-- now (the check drawer's TOPRIGHT anchor needs CH.TITLEBAR too, and a local must be declared
-- before the earliest function that closes over it) -- this comment stays here as the doc for
-- CH.BTN_H/CH.HEADER's consumers below.
-- ---------------------------------------------------------------------------

local function createHeaderRow(f)
  local header = CreateFrame("Frame", nil, f)
  header:SetPoint("TOPLEFT", f, "TOPLEFT", WIN.CONTENT_LEFT, f.headerY)
  header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -WIN.CONTENT_RIGHT_GUTTER, f.headerY)
  header:SetHeight(CH.HEADER)
  f.headerRow = header -- D: setView shows/hides this alongside f.scroll for the Sell tab

  -- sortKey (E.2), when present, makes the header clickable: OnMouseDown sets/toggles the
  -- module-local sortOverride and re-renders. Columns without an entry here (item/trend/buy)
  -- stay inert, exactly as "Item" always was. I6: "unit" is sortable too (its own SORT_VALUE
  -- key) -- unlike "total", "unit" is never one of the responsively-dropped columns, so it's
  -- always available as a by-price sort even at window widths where "total" itself is hidden.
  local SORT_KEY = { tier = "tier", disc = "pct", unit = "unit", total = "price", profit = "profit" }
  local HEADER_TEXT = { item = "Item", tier = "Tier", disc = "Disc", unit = "Unit", total = "Price", profit = "Profit", trend = "Trend", buy = "" }
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
    -- This column used to be measured against a lot size the engine would never approve --
    -- a day's sold volume, capped at 200 -- while Check would go on to authorise one unit.
    -- Rows advertised five figures and the very next click refused them, which is not a
    -- caveat, it is the addon lying to the player. Both sides now multiply by the SAME
    -- quantity: SniperDecision.DemandCap, called once at discovery and again live.
    --
    -- What honestly remains is a difference of EVIDENCE, not of arithmetic. Discovery reads
    -- the import's snapshot of stock and turnover; Check reads the order book that exists at
    -- the moment of the click. So Check can still land lower or refuse -- because the market
    -- moved, not because the number here was inflated on purpose.
    profit = { "Profit",
      "A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve.",
      "Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import.",
      "Sort by it to decide what to Check first, not to decide what to buy." },
  }

  local function buildHeaderCell(col)
    local hit = CreateFrame("Frame", nil, header)
    hit:SetHeight(CH.HEADER)
    local baseText = (HEADER_TEXT[col.key] or ""):upper()
    local label = Theme.Num(hit, 9)
    label:SetAllPoints()
    label:SetJustifyH(col.num and "RIGHT" or "LEFT")
    label:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3], Theme.color.fgDim[4] or 1)
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
  itemHit.label = Theme.Num(itemHit, 9)
  itemHit.label:SetAllPoints()
  itemHit.label:SetJustifyH("LEFT")
  itemHit.label:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3], Theme.color.fgDim[4] or 1)
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

  -- 1px rule under the mono column labels, the same border color used elsewhere as a hairline
  -- (the toolbar divider) -- separates the header row from the
  -- first data row now that the labels themselves are small and dim rather than a filled bar.
  header.underline = header:CreateTexture(nil, "ARTWORK")
  header.underline:SetHeight(1)
  header.underline:SetColorTexture(Theme.color.border[1], Theme.color.border[2],
    Theme.color.border[3], Theme.color.border[4])
  header.underline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
  header.underline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")

  return header
end

local function createFrame()
  local f = CreateFrame("Frame", "GoldCapSniperFrame", UIParent)

  -- Rounded card window (Sniper v4). Theme.Panel stays untouched for the
  -- overlays that still use it; only the main window goes rounded.
  local panel = Theme.Card(f)
  panel:SetAllPoints(f)

  local savedWindow = GC.db and GC.db.settings and GC.db.settings.sniper and GC.db.settings.sniper.window
  local restoreWidth, restoreHeight = WIN.FRAME_WIDTH, WIN.FRAME_HEIGHT
  if isValidSavedWindow(savedWindow) then
    if type(savedWindow.width) == "number" then restoreWidth = clampWindowWidth(savedWindow.width) end
    if type(savedWindow.height) == "number" then restoreHeight = clampWindowHeight(savedWindow.height) end
  end
  f:SetSize(restoreWidth, restoreHeight)

  -- Sniper v3 responsive column drop: establish the correct drop state up front from the
  -- window's actual starting width, so the very first header/row layout already reflects it
  -- instead of waiting for a later resize event (see applyColumnVisibility, and the
  -- f:SetScript("OnSizeChanged", ...) below that keeps it current afterward -- M8).
  hiddenColumns = computeHidden(restoreWidth - WIN.CONTENT_LEFT - WIN.CONTENT_RIGHT_GUTTER)

  -- T5: BOTH width and height are resizable now (previously only height -- see WIN.FRAME_WIDTH's
  -- own comment above); the column grid no longer needs a fixed width to stay aligned, since
  -- every column anchors relative to its neighbor (see COLUMNS/anchorColumns).
  f:SetResizable(true)
  f:SetResizeBounds(WIN.RESIZE_MIN_WIDTH, WIN.RESIZE_MIN_HEIGHT, WIN.RESIZE_MAX_WIDTH, WIN.RESIZE_MAX_HEIGHT)

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
  -- Kept as a field so docked mode (GC.Sniper.SetDocked below) can blank the duplicate
  -- chrome: inside the auction house the AH frame already provides the title and the close.
  f.titleBar = titleBar
  -- hooksecurefunc, not an OnDragStop/OnMouseUp script: see persistWindowGeometry's own
  -- comment for why the method-hook is what unifies both hardware-driven geometry changes.
  hooksecurefunc(f, "StopMovingOrSizing", persistWindowGeometry)

  -- Rail (Sniper v4): the Deals/Sell/Sold switcher is a 76px left rail of big
  -- targets (Theme.Rail), not a row of 50x18 ghost tabs. The f.dealsTab/
  -- f.sellTab/f.soldTab FIELDS survive on purpose: setView and
  -- updateSellTabLabel address the buttons only through them.
  local rail = Theme.Rail(f)
  rail.frame:SetPoint("TOPLEFT")
  rail.frame:SetPoint("BOTTOMLEFT")
  -- Settings overlays the content but not the rail, so a rail click must dismiss it first --
  -- and closing it re-disables the active tab (RefreshRailActive above), which is why the tabs
  -- are enabled while Settings is open (SettingsFrame.lua's own OnShow).
  rail.buttons.deals:SetScript("OnClick", function()
    if GC.SettingsUI and GC.SettingsUI.Hide then GC.SettingsUI.Hide() end
    setView("deals")
  end)
  rail.buttons.sell:SetScript("OnClick", function()
    if GC.SettingsUI and GC.SettingsUI.Hide then GC.SettingsUI.Hide() end
    setView("sell")
  end)
  rail.buttons.sold:SetScript("OnClick", function()
    if GC.SettingsUI and GC.SettingsUI.Hide then GC.SettingsUI.Hide() end
    setView("sold")
  end)
  f.rail = rail
  f.dealsTab, f.sellTab, f.soldTab = rail.buttons.deals, rail.buttons.sell, rail.buttons.sold
  setTabActive(f.dealsTab, true) -- Deals is the default view
  setTabActive(f.sellTab, false)
  setTabActive(f.soldTab, false)

  -- Settings entry lives on the rail now; TitleBar still builds its gear for
  -- other callers, this window just doesn't show two of them.
  titleBar.gear:Hide()
  rail.gear:SetScript("OnClick", function() GC.SettingsUI.Toggle() end)

  -- Theme.TitleBar anchors the title at the window's own LEFT edge, which the rail now covers
  -- (it owns x in [0, RAIL_W]) -- without this the title text renders underneath/behind the
  -- rail. SetDocked's blank/restore (UI/SniperFrame.lua) only calls title:SetText, so it is
  -- unaffected by this re-anchor.
  titleBar.title:ClearAllPoints()
  titleBar.title:SetPoint("LEFT", titleBar.bar, "LEFT", WIN.CONTENT_LEFT, 0)

  -- B: import staleness. Staleness lives in the title bar since the tab row died; the gear
  -- there is hidden (rail.gear owns Settings now, see above), so the strip is free. Right-
  -- justified against the close button, hidden until refreshStaleText() (called on AH show
  -- and after every full scan) says otherwise.
  local staleText = Theme.Label(f, 11)
  staleText:SetPoint("RIGHT", f.closeBtn, "LEFT", -Theme.pad.m, 0)
  staleText:SetJustifyH("RIGHT")
  staleText:SetWordWrap(false)
  staleText:Hide()
  f.staleText = staleText

  -- Row 2 (now the only row below the title bar -- the empty ex-tab row it used to share
  -- with staleText is gone), left-to-right: Auto pill, status line, session block, divider,
  -- Scan, Refused/Hidden. Sniper v4 toolbar rework: the three buttons all share the same
  -- "plaque" rounded chrome (Theme.Button's rounded arg from the rail kit) at height 26
  -- (CH.BTN_H), and every label on this row is UPPERCASE mono.
  local row2Y = -(CH.TITLEBAR + Theme.pad.xs)

  -- Auto: now anchored top-LEFT of the content column (was top-right) -- the rail kit put
  -- navigation on its own strip at the window's left edge, so the toolbar's own left edge is
  -- free, and Auto (the most-used control) gets the first, most consistent anchor point.
  -- Same click handler/tooltip as before; only the anchor and label case changed.
  local autoBtn = Theme.Button(f, "ghost", "plaque")
  autoBtn:SetSize(132, CH.BTN_H)
  autoBtn:SetPoint("TOPLEFT", f, "TOPLEFT", WIN.CONTENT_LEFT, row2Y)
  autoBtn:SetLabel("AUTO")
  f.autoBtn = autoBtn

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
      -- (fix wave, I1) Same reason toggleOn wipes "tab": a Sell-view pause made while AUTO was
      -- off was silently dropped -- addPause is a no-op in state OFF (Core/AutoScan.lua) -- so
      -- an off/on cycle made while the Sell tab is showing used to leave Auto free to browse
      -- the AH right underneath the pricing walk's own throttled search. The Sell view is a
      -- standing reason exactly like the hidden tab above, so it gets the same re-seed.
      if view == "sell" then feedAuto("pause:sell") end
    else
      if cfg then cfg.auto = false end
      feedAuto("toggleOff")
    end
  end
  autoBtn:SetScript("OnClick", onAutoToggleClick)
  local autoTooltip =
    "Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, " ..
    "search the Auction House yourself, or check your mail. Click to toggle."
  setPlainTooltip(autoBtn, autoTooltip)

  -- The refused-rows toggle, in the slot the Live button vacated (see below). Background
  -- verification (tickAutoVerify) hides rows a live Check has refused, and a shorter list with
  -- nothing explaining it is its own lie -- this is the number and the switch. One button with
  -- two variants (never two swapped by Show/Hide), per addon/AGENTS.md. Anchored top-RIGHT now
  -- (was Scan's slot): it and Scan swap sides of the row so Auto/Refused-Hidden bookend it.
  local verifyBtn = Theme.Button(f, "ghost", "plaque")
  verifyBtn:SetSize(76, CH.BTN_H)
  verifyBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -WIN.CONTENT_RIGHT_GUTTER, row2Y)
  verifyBtn:SetLabel("HIDDEN 0")
  verifyBtn:SetScript("OnClick", function()
    local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
    if not cfg then return end
    cfg.showRefused = not showRefused()
    refreshRows() -- re-renders and, through it, re-labels this button
  end)
  -- A live tooltip rather than setPlainTooltip's fixed text. "It seems to work sometimes" is
  -- not a report anyone can act on, and the walk is invisible by nature -- so it says what it
  -- has actually done: how many of the rows it is responsible for carry a verdict, and how
  -- long ago the last one landed. A stalled walk shows up here as a number that stops moving.
  verifyBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Background check", 1, 1, 1)
    GameTooltip:AddLine("GoldCap re-checks the top " .. LIM.VERIFY_TOP_ROWS ..
      " rows against the live auction house about every " .. LIM.VERIFY_INTERVAL_SECONDS ..
      "s. Rows it refuses are hidden. Buying always stays a click you make.", 1, 1, 1, true)

    local list = renderList()
    local checked, newest = 0, nil
    for i = 1, math.min(#list, LIM.VERIFY_TOP_ROWS) do
      local v = verdicts[list[i].itemID]
      if v and v.unitPrice == list[i].unitPrice then
        checked = checked + 1
        if not newest or v.at > newest then newest = v.at end
      end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Checked: %d of the top %d on screen"):format(
      checked, math.min(#list, LIM.VERIFY_TOP_ROWS)), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(newest
      and ("Last result: %ds ago"):format(math.floor(GetTime() - newest))
      or "Last result: none yet this visit", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(("Refused so far: %d"):format(refusedCount), 0.7, 0.7, 0.7)
    local watched = #GC.Sniper._liveTargets
    if watched > 0 then
      GameTooltip:AddLine(("Watching closely: %d item%s"):format(watched, watched == 1 and "" or "s"),
        0.7, 0.7, 0.7)
      GameTooltip:AddLine(GC.Sniper._cycleSeconds
        and ("Full pass over them: %.1fs"):format(GC.Sniper._cycleSeconds)
        or "Full pass over them: measuring...", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
  end)
  verifyBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
  f.verifyBtn = verifyBtn

  local fullScanBtn = Theme.Button(f, "ghost", "plaque")
  fullScanBtn:SetSize(64, CH.BTN_H)
  fullScanBtn:SetPoint("RIGHT", verifyBtn, "LEFT", -Theme.pad.xs, 0)
  fullScanBtn:SetLabel("SCAN")
  fullScanBtn:SetScript("OnClick", onFullScanClick)
  setPlainTooltip(fullScanBtn,
    "One-shot scan of the entire Auction House via paged browse queries. Takes roughly " ..
    "15-60 seconds on busy realms. No cooldown -- rescan anytime.")
  f.fullScanBtn = fullScanBtn

  -- Divider + session block sit further left of Scan, between it and the status line -- the
  -- session figures (buys/profit this AH visit) are secondary to the toolbar's controls, so
  -- they read as a trailing readout rather than another button.
  f.toolbarDivider = f:CreateTexture(nil, "ARTWORK")
  f.toolbarDivider:SetSize(1, 16)
  f.toolbarDivider:SetColorTexture(Theme.color.border[1], Theme.color.border[2],
    Theme.color.border[3], Theme.color.border[4])
  f.toolbarDivider:SetPoint("RIGHT", fullScanBtn, "LEFT", -Theme.pad.s, 0)

  -- Hidden by default: refreshSessionText only Shows it once GC.Sniper.session has a buy this
  -- visit (see that function). SESSION resets to zero-buys at AH close, same as the session
  -- table itself (GC.Sniper.OnAuctionHouseClosed) -- an empty session says nothing here rather
  -- than showing a stale "0 buys" from the last visit.
  f.sessionText = Theme.Num(f, 11, true)
  f.sessionText:SetPoint("RIGHT", f.toolbarDivider, "LEFT", -Theme.pad.s, 0)
  f.sessionText:Hide()

  -- Re-derives the toggle's label and look from `refusedCount`, which renderList recomputes on
  -- every render. Same contract as refreshAutoButton/refreshScanButton: driven off the 0.25s
  -- ticker and off refreshRows, rather than hooked into every place a verdict can land, so a
  -- new path cannot silently leave a stale number on screen.
  refreshVerifyButton = function(target)
    local owner = target or frame
    local btn = owner and owner.verifyBtn
    if not btn then return end
    local show = showRefused()
    local text = (show and "REFUSED %d" or "HIDDEN %d"):format(refusedCount)
    if btn.lastText ~= text then
      btn:SetLabel(text)
      btn.lastText = text
    end
    if btn.lastOn ~= show then
      btn.lastOn = show
      btn:SetVariant(show and "active" or "ghost")
    end
  end
  refreshVerifyButton(f)

  -- The "Live" button is gone. It started a second, narrower scan loop over the
  -- items the last Full Scan had turned up (or, failing that, the imported
  -- watchlist), which is a real capability -- but Auto is strictly broader: it
  -- re-browses the whole auction house on a loop and finds everything Live would,
  -- plus everything Live's fixed target list could not. The two also fought each
  -- other -- starting Live forcibly switched Auto off -- with nothing in the
  -- interface saying so, which left two adjacent buttons that could not be told
  -- apart. Scan (once) and Auto (continuously) is the whole story.
  --
  -- The scanner itself stays: the Check flow pauses and resumes it, and the deal
  -- rows it produces are still the ones a Full Scan feeds.

  -- Theme.Num (mono), not Theme.Label (native font): the status line sits in the same row as
  -- three mono-labeled plaque buttons now, and the native-font Label read as a mismatched
  -- typeface against them. fgMuted, not fg: this is secondary readout text, same as the
  -- session block beside it, not a control label.
  local status = Theme.Num(f, 10)
  status:SetJustifyH("LEFT")
  local muted = Theme.color.fgMuted
  status:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
  status:SetPoint("TOPLEFT", autoBtn, "TOPRIGHT", Theme.pad.s, 0)
  status:SetPoint("RIGHT", f.sessionText, "LEFT", -Theme.pad.s, 0)
  status:SetText("Open the Auction House to begin scanning.")
  f.status = status

  -- Deals-only toolbar chrome: setView shows/hides these five alongside the scroll/header
  -- toggle it already drives, so Sell/Sold don't sit under a Deals-specific control/session
  -- row that means nothing on their view. See setView's own comment on this field.
  --
  -- `status` is deliberately NOT in this list. GC.Sell.Attach (SellFrame.lua) captures this
  -- same `f` as `statusOwner` and its own setStatus() routes ~40 user-facing messages
  -- ("Posting…", "Click Confirm to post", timeouts, etc.) through `statusOwner.status:SetText`
  -- -- it is a shared channel across every view, not a Deals-only readout. Hiding it here
  -- would mute Sell's entire posting-feedback channel while the Sell view is showing.
  f.dealsChrome = { verifyBtn, fullScanBtn, autoBtn, f.toolbarDivider, f.sessionText }

  -- Row 3: column headers, sticky above the scroll area.
  f.headerY = row2Y - (CH.BTN_H + Theme.pad.s)
  createHeaderRow(f)

  local scrollTop = f.headerY - (CH.HEADER + Theme.pad.xs)
  local scrollBottom = Theme.pad.m

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", WIN.CONTENT_LEFT, scrollTop)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -WIN.CONTENT_RIGHT_GUTTER, scrollBottom)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    local target = self:GetVerticalScroll() - delta * WIN.ROW_HEIGHT * 3
    if target < 0 then target = 0 end
    if target > range then target = range end
    self:SetVerticalScroll(target)
  end)
  f.scroll = scroll -- D: setView hides/shows this alongside f.headerRow for the Sell tab

  -- Empty-state panel for the deals board, living where the rows would be. Parented to
  -- `scroll` (not `content`) so it shows/hides with the Deals view via setView's existing
  -- scroll:Hide(), and never scrolls (an empty board has nothing to scroll). Driven solely by
  -- GC.Sniper._UpdateEmptyState from refreshRows -- see that function for what it says when.
  local emptyText = Theme.Label(scroll, 12)
  emptyText:SetPoint("TOP", scroll, "TOP", 0, -WIN.ROW_HEIGHT * 2)
  emptyText:SetPoint("LEFT", scroll, "LEFT", Theme.pad.m * 3, 0)
  emptyText:SetPoint("RIGHT", scroll, "RIGHT", -Theme.pad.m * 3, 0)
  emptyText:SetJustifyH("CENTER")
  emptyText:SetWordWrap(true)
  emptyText:SetSpacing(4)
  emptyText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  emptyText:Hide()
  f.emptyText = emptyText

  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(math.max(restoreWidth - WIN.CONTENT_LEFT - WIN.CONTENT_RIGHT_GUTTER, 1), WIN.ROW_HEIGHT) -- refreshRows() stamps the real height; OnSizeChanged below keeps width live
  scroll:SetScrollChild(content)
  -- T5/M8: the scroll child's WIDTH is the one piece of the grid Blizzard's ScrollFrame widget
  -- requires an explicit size for (unlike every row inside it, which anchors relatively) --
  -- keep it synced to the live content width so a frame resize re-flows the whole grid.
  -- Observed off `f` (the window frame) rather than `scroll` itself (M8): a ScrollFrame that's
  -- currently hidden (e.g. the Sell tab is showing, so `scroll:Hide()` -- see setView) is not
  -- guaranteed to fire its own OnSizeChanged while hidden, which would silently stop the
  -- Deals grid's column-drop from tracking a resize made while looking at Sell. `f` is never
  -- hidden while the window is open, so this fires regardless of which tab is active. The
  -- header's own width tracks the same WIN.CONTENT_LEFT/WIN.CONTENT_RIGHT_GUTTER margins off `f`
  -- directly, so the derived contentWidth here is exactly the header's width too -- one number
  -- feeds the responsive column-drop decision (applyColumnVisibility) for both.
  --
  -- The check panel shifts the list aside only when there is room for both (>= WIN.PANEL_
  -- SHIFT_MIN, 900 wide); narrower windows -- the docked AH is ~805 -- get an opaque overlay
  -- instead (see createDialog's sheet alpha). One function owns every right-edge anchor
  -- (scroll's BOTTOMRIGHT, f.headerRow's TOPRIGHT, verifyBtn's TOPRIGHT) plus the derived
  -- content width, so they can never drift apart -- called from here on every resize, and from
  -- createDialog's OnShow/OnHide whenever the sheet itself appears or disappears.
  local function applyPanelInset(open)
    local w = f:GetWidth() or 0
    local inset = (open and w >= WIN.PANEL_SHIFT_MIN) and (DG.WIDTH + Theme.pad.m) or 0
    f.panelInset = inset
    local right = -(WIN.CONTENT_RIGHT_GUTTER + inset)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", WIN.CONTENT_LEFT, scrollTop)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", right, scrollBottom)
    f.headerRow:ClearAllPoints()
    f.headerRow:SetPoint("TOPLEFT", f, "TOPLEFT", WIN.CONTENT_LEFT, f.headerY)
    f.headerRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", right, f.headerY)
    verifyBtn:ClearAllPoints()
    verifyBtn:SetPoint("TOPRIGHT", right, row2Y)
    local contentWidth = math.max(w - WIN.CONTENT_LEFT - WIN.CONTENT_RIGHT_GUTTER - inset, 1)
    content:SetWidth(contentWidth)
    applyColumnVisibility(contentWidth)
  end
  f.applyPanelInset = applyPanelInset

  -- OnSizeChanged now fully delegates to applyPanelInset (above), which supersedes what this
  -- handler used to do inline (compute contentWidth off `w` alone, content:SetWidth it,
  -- applyColumnVisibility it) -- passing the dialog's live open/shown state re-evaluates the
  -- inset on every resize too, so dragging the window across WIN.PANEL_SHIFT_MIN while the
  -- panel is open re-flows the list instead of leaving it stuck at whichever side it started on.
  f:SetScript("OnSizeChanged", function(_, w)
    if not w or w <= 0 then return end
    applyPanelInset(dialog ~= nil and dialog:IsShown())
    -- Fix wave (check panel v2 review): the open evidence grid is a fixed-offset block, not
    -- something that reflows with the drawer -- without this, an open grid painted its rows
    -- straight over BUY/CANCEL when the window shrank to the 470 floor (no SetClipsChildren
    -- anywhere), and enlarging again after an F5 refusal needed a manual toggle click.
    -- Re-applies the SAVED preference (not d.detailsOpen, the live flag) on every resize, so a
    -- downsize closes the grid without eating the player's "open" and an upsize reopens it.
    -- detailsQuiet silences applyDetailsState's own F5 refusal status write (see that
    -- function's guard) so a drag-resize doesn't spam "Enlarge the window..." on every pixel.
    if dialog and dialog.applyDetailsState then
      local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
      dialog.detailsQuiet = true
      dialog.applyDetailsState(cfg and cfg.dialogDetailsOpen)
      dialog.detailsQuiet = nil
    end
  end)

  -- E.4 resize grip: a small BOTTOMRIGHT handle sized/positioned to sit in the scrollbar
  -- gutter (WIN.CONTENT_RIGHT_GUTTER) below the scroll frame's own bottom edge, not on top of the
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

  -- D: builds the Sell tab's container, hidden, filling the region below the title bar. Sell
  -- and Sold own their toolbars (their own Auto/Scan-equivalent row), so their containers start
  -- where the Deals toolbar starts (row2Y), not below Deals' header row -- Deals is the only
  -- view with a third (column-header) row. The shared invariant across all three views is
  -- horizontal (WIN.CONTENT_LEFT/WIN.CONTENT_RIGHT_GUTTER) plus the bottom edge (scrollBottom);
  -- rowWidth is initial geometry only -- SellFrame keeps its own responsive column layout
  -- current from this same window's OnSizeChanged hook.
  GC.Sell.Attach(f, {
    panelLeft = WIN.CONTENT_LEFT,
    panelRightInset = WIN.CONTENT_RIGHT_GUTTER,
    top = row2Y,
    bottom = scrollBottom,
    rowWidth = restoreWidth - WIN.CONTENT_LEFT - WIN.CONTENT_RIGHT_GUTTER,
    rowHeight = WIN.ROW_HEIGHT,
  })

  GC.Sold.Attach(f, {
    panelLeft = WIN.CONTENT_LEFT,
    panelRightInset = WIN.CONTENT_RIGHT_GUTTER,
    top = row2Y,
    bottom = scrollBottom,
    rowWidth = restoreWidth - WIN.CONTENT_LEFT - WIN.CONTENT_RIGHT_GUTTER,
    rowHeight = WIN.ROW_HEIGHT,
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
  f:SetScript("OnHide", function()
    feedAuto("tabHidden")
    -- F2 (whole-branch review): the drawer is now a CHILD of this window frame (createDialog's
    -- own re-host), not a UIParent-anchored sibling -- hiding the window no longer implies
    -- hiding it. Blizzard's engine hides children visually when a parent hides, but does NOT
    -- flip the child's own shown-flag or fire its OnHide -- so without this, reopening the
    -- window would resurrect a stale drawer (no row, stale decision) still reporting IsShown().
    -- Explicit Hide() fires the drawer's own OnHide (abort runs; its row-guard already makes a
    -- second/redundant Hide() a no-op, so this is safe whether or not the drawer was open).
    if dialog then dialog:Hide() end
    -- Closing the DOCKED window (its X, or Escape) must hand the auction house back to
    -- Blizzard's own tab -- see GC.AuctionHouseTab.OnWindowHidden, which no-ops when the
    -- window is not docked or its mode is not the one showing.
    if GC.AuctionHouseTab and GC.AuctionHouseTab.OnWindowHidden then
      pcall(GC.AuctionHouseTab.OnWindowHidden)
    end
  end)

  refreshAutoButton(f) -- (fix round 1, M1) paint the initial label/visual before the very first Show
  return f
end

-- Whether the addon window is up. Read by UI/AuctionHouseTab.lua so the tab it
-- draws on Blizzard's auction house never claims a state the window is not in.
function GC.Sniper.IsWindowShown()
  return frame ~= nil and frame:IsShown()
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
  if GC.AuctionHouseTab and GC.AuctionHouseTab.Refresh then
    pcall(GC.AuctionHouseTab.Refresh)
  end
end

-- Docked mode: the window lives inside a host panel on Blizzard's auction house instead of
-- floating -- UI/AuctionHouseTab.lua owns the host and decides when. Docking neutralizes the
-- free-window chrome that would fight a fixed host: the title-bar drag (Theme.TitleBar's
-- OnDragStart checks IsMovable before StartMoving), the resize grip, and geometry
-- persistence (persistWindowGeometry skips a frame whose goldcapDockHost is set -- saving the
-- host's anchors would corrupt the remembered floating geometry). Undocking restores the
-- saved floating geometry the same way createFrame does on load, and leaves the window
-- HIDDEN: it runs when the auction house closes, and a window popping to mid-screen at that
-- moment would be the addon opening itself unasked.
function GC.Sniper.SetDocked(host)
  if host then
    frame = frame or createFrame()
    frame.goldcapDockHost = host
    frame:SetMovable(false)
    if frame.resizeHandle then frame.resizeHandle:Hide() end
    -- Docked chrome: the auction house already shows a "GoldCap" title and its own close
    -- button, and the AH portrait overlaps where our title text sits -- so the window's own
    -- duplicates go. The BAR stays (every content offset hangs from its height); only the
    -- text and the X are the duplicates. The gear moved to the rail (createFrame) and stays
    -- visible there regardless of dock state -- the titlebar's own gear is permanently hidden.
    if frame.titleBar and frame.titleBar.title then frame.titleBar.title:SetText("") end
    if frame.closeBtn then frame.closeBtn:Hide() end
    frame:SetParent(host)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT")
    frame:SetPoint("BOTTOMRIGHT")
    if frame.rail and frame.rail.SetTopInset then frame.rail.SetTopInset(CH.DOCK_RAIL_INSET) end
    if not frame:IsShown() then
      GC.Sniper.Toggle() -- the ordinary open path: stale banner, bag counts, the tab badge
    end
  else
    if not frame or not frame.goldcapDockHost then return end
    frame.goldcapDockHost = nil
    frame:Hide()
    frame:SetParent(UIParent)
    frame:SetMovable(true)
    if frame.resizeHandle then frame.resizeHandle:Show() end
    if frame.titleBar and frame.titleBar.title then frame.titleBar.title:SetText("GoldCap Sniper") end
    if frame.closeBtn then frame.closeBtn:Show() end
    frame:ClearAllPoints()
    local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
    local saved = cfg and cfg.window
    local restored = false
    if isValidSavedWindow(saved) then
      restored = pcall(frame.SetPoint, frame, saved.point, saved.x, saved.y)
    end
    if not restored then
      frame:ClearAllPoints()
      frame:SetPoint("CENTER")
    end
    local width = (saved and type(saved.width) == "number") and clampWindowWidth(saved.width)
      or WIN.FRAME_WIDTH
    local height = (saved and type(saved.height) == "number") and clampWindowHeight(saved.height)
      or WIN.FRAME_HEIGHT
    pcall(frame.SetSize, frame, width, height)
    if frame.rail and frame.rail.SetTopInset then frame.rail.SetTopInset(0) end
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
      box:HookScript("OnEditFocusGained", function()
        feedAuto("pause:search")
        -- GC.AuctionHouseTab is the one place PlayerIsBusy lives -- record this independently
        -- of the FSM pause reason above, which only governs OUR OWN auto-scan and says nothing
        -- about the verify walk or the watch loop.
        if GC.AuctionHouseTab and GC.AuctionHouseTab.NoteSearchFocus then
          pcall(GC.AuctionHouseTab.NoteSearchFocus, true)
        end
      end)
    end)
    pcall(function()
      box:HookScript("OnEditFocusLost", function()
        if frame and frame:IsShown() then
          feedAuto("resume:search")
        end
        -- Unconditional, unlike the feedAuto resume above: PlayerIsBusy must know the player
        -- left the box even when our own window is closed.
        if GC.AuctionHouseTab and GC.AuctionHouseTab.NoteSearchFocus then
          pcall(GC.AuctionHouseTab.NoteSearchFocus, false)
        end
      end)
    end)
  end

  -- (fix round 1, C3) SetDisplayMode alone previously only ever fed pause:search, with no
  -- resume counterpart -- a single AH tab click would strand Auto in "paused: searching" for
  -- the rest of the session.
  --
  -- (fix round 2) Enum.AuctionHouseDisplayMode does not exist on the live client -- confirmed
  -- against Gethe/wow-ui-source, Interface/AddOns/Blizzard_AuctionHouseUI/Shared/
  -- Blizzard_AuctionHouseFrame.lua, read verbatim: the mode identifiers are keys of the plain
  -- Lua table AuctionHouseFrameDisplayMode (Buy/WoWTokenBuy/CommoditiesBuy/ItemBuy/
  -- CommoditiesSell/ItemSell/WoWTokenSell/Auctions), never an Enum, so the old comparison
  -- always fell through to the degraded branch below. Use the same verified global
  -- GC.AuctionHouseTab.PlayerIsPosting/PlayerIsBuying already read, guarded the same way in
  -- case some future client build renames or drops it.
  local buyMode = _G.AuctionHouseFrameDisplayMode and _G.AuctionHouseFrameDisplayMode.Buy
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
      -- AuctionHouseFrameDisplayMode itself missing (a client shape this was never verified
      -- against): can't tell Buy mode from any other, so pause immediately (a mode change
      -- COULD be the player driving the AH's own search) and, if our window is up, resume
      -- after a short defer -- long enough for the mode transition's own query to land first --
      -- so one stray SetDisplayMode call can't strand Auto for the session.
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
  -- A pin persists in SavedVariables across an AH close, but `_liveTargets` does not -- it is
  -- wiped in OnAuctionHouseClosed like every other live claim. Without this call, a pin made
  -- last session (or with Auto off, which is the only other thing that used to reach
  -- _RefreshWatchSet) sits inert until a scan happens to run: nothing polls it. Must come
  -- after the scanner is built just above, or there is nothing for the refresh to Start.
  GC.Sniper._RefreshWatchSet()

  -- Sniper v3 §3: the AutoScan ticker only runs while the AH is open (nothing to drive
  -- otherwise -- SendBrowseQuery would silently no-op with no AH session live). This, the
  -- search-detection hooks, and the ahOpened/toggleOn feed below all run regardless of
  -- autoOpen -- toggleOn re-arms the MACHINE here even if autoOpen keeps the window itself
  -- from appearing, but (fix round 1, I4 ruling) Auto never actually SCANS until the window
  -- is shown, since toggleOn's own tab-seed just below re-adds "tab" if it isn't up yet.
  installSearchHooks()
  -- Same guarantee installSearchHooks carries: this runs synchronously inside
  -- this function, so it must not be able to raise. AuctionHouseTab.Install is
  -- pcall-guarded end to end, and pcall'd again here rather than trusted.
  if GC.AuctionHouseTab and GC.AuctionHouseTab.Install then
    pcall(GC.AuctionHouseTab.Install)
  end
  autoScanTicker = autoScanTicker or C_Timer.NewTicker(0.25, function()
    autoScan:Tick(GetTime())
    refreshAutoButton()
    refreshScanButton()
    -- Background verification rides the same clock, for the same reason the two buttons above
    -- do: one place drives it, so it cannot be forgotten by a path that changes state.
    tickAutoVerify()
    refreshVerifyButton()
    -- Same clock, same reason: the session readout cannot be forgotten by a path that changes
    -- GC.Sniper.session either.
    refreshSessionText()
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
    -- (fix wave, I1) Same wipe, same fix as onAutoToggleClick above: a Sell-view pause made
    -- while AUTO was off is otherwise lost on every AH close/reopen, not just a manual toggle.
    if view == "sell" then feedAuto("pause:sell") end
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

  -- Undock the window from the auction house before anything else tears down: the dock host
  -- is a child of the AH frame and is about to vanish with it. Idempotent (SetDocked(nil)
  -- no-ops on an undocked window), so the double-call above is tolerated here too.
  if GC.AuctionHouseTab and GC.AuctionHouseTab.OnAuctionHouseClosed then
    pcall(GC.AuctionHouseTab.OnAuctionHouseClosed)
  end

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
  -- The wipe above (or a no-op when buys was already 0) can leave f.sessionText showing a
  -- figure for a session that no longer exists -- re-derive right away rather than waiting for
  -- the 0.25s ticker (which isn't even running here, see autoScanTicker:Cancel() above). On
  -- Deals this hides the now-wiped block; off-Deals it's already hidden (dealsChrome).
  refreshSessionText()

  local scanner = GC.Sniper.scanner
  if scanner and scanner.scanned > 0 then
    GC.Print(("scanned %d listings over %d passes"):format(scanner.scanned, scanner.cycles))
    scanner.scanned = 0
  end

  resetAllPurchases()
  -- Clears the live/watchlist `deals` map ONLY. A completed full scan's `scanDeals` array is
  -- deliberately left intact and re-renders on the next AH visit -- see OnAuctionHouseShow's
  -- own comment for why (a browse scan has no cooldown, and every buy re-quotes live anyway).
  -- So this is not "a clean slate": what a closed AH guarantees is that no purchase or Sell
  -- state survives (resetAllPurchases above, GC.Sell.Reset below), not that the board is empty.
  clearDeals()
  -- Sniper v3 §3 ping: a HOT listing that pinged this session should be able to ping again
  -- next session even at the exact same price (a fresh AH visit is a fresh judgment of
  -- what's worth flagging) -- see seenHotDeals' own declaration.
  for key in pairs(seenHotDeals) do seenHotDeals[key] = nil end
  -- What the addon worked out for itself is a claim about a live market and does not survive
  -- the session, exactly like a verdict. Pins do: they are a standing instruction, and they
  -- live in SavedVariables.
  for itemID in pairs(GC.Sniper._churn) do GC.Sniper._churn[itemID] = nil end
  GC.Sniper._churnSeq = 0
  for itemID in pairs(GC.Sniper._rangAt) do GC.Sniper._rangAt[itemID] = nil end
  for itemID in pairs(GC.Sniper._lastPrice) do GC.Sniper._lastPrice[itemID] = nil end
  -- Same reasoning for background verdicts, and one more: a verdict is a claim about a live
  -- order book, and there is no live order book once the session is gone. scanDeals survives
  -- the close on purpose (see OnAuctionHouseShow) -- its verdicts must not, or the next visit
  -- opens with gold Buy buttons vouched for by a market nobody has looked at since.
  for itemID in pairs(verdicts) do verdicts[itemID] = nil end
  refusedCount = 0
  verifyWalkAt = 0
  -- D: abort any in-flight Sell quote walk/post -- neither can safely resume once the AH
  -- session is gone (same reasoning as resetAllPurchases above for the Deals side).
  GC.Sell.Reset()
  if frame then frame:Hide() end
end
