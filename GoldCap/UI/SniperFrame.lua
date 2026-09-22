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
-- 470. DG.FIXED_HEIGHT_CLOSED alone is NOT the real closed-drawer floor:
-- resizeDialogDiagnostics's own non-debug branch (the one every real player sees) anchors
-- `status` BOTTOM-UP, independently of the top-down stack, and reserves the banner slot ABOVE
-- it -- so the true minimum has to fit BOTH stacks without them overlapping. Recomputed
-- straight off that function's own anchoring, each term named (check panel v3 blocks):
--   DG.HEADER_H(52) + DG.HERO_H(124) + DG.QTY_BLOCK_H(50) + DG.FACTS_H(84)
--     = 310  (top-down, through the four facts -- the tallest closed shape, a purchase)
--   + DG.TOGGLE_BLOCK_H(26)                                                 = 336  (the gap
--     after the facts plus the toggle itself)
--   + LIM.REQUOTE_BANNER_HEIGHT(46) + Theme.pad.xs(4)                       = 386  (the banner
--     slot createDialog reserves above the status line, plus the pad.xs gap under it)
--   + DG.STATUS_H(32)                                                       = 418  (status's
--     own reserved line height, anchored at DG.CONTROLS_H by resizeDialogDiagnostics)
--   + DG.CONTROLS_H(78)                                                     = 496  (bottom
--     margin + Cancel + gap + Buy + gap-to-status)
-- That is 496 against a drawer of (RESIZE_MIN_HEIGHT - CH.TITLEBAR(32)) = 438, so at the very
-- smallest window the banner slot and the top stack DO meet. Left at 470 deliberately: the
-- banner is the requote alarm, which only exists mid-purchase, and raising the floor to 540
-- would cost every player 70px of deals list to reserve a slot most sessions never draw. What
-- the v3 layout did buy is the Details toggle: it needs DG.FIXED_HEIGHT_OPEN(550) for a
-- purchase and 536 for a refusal (no quantity block), both now inside the docked AH drawer's
-- ~565 ceiling -- the old pair was 548/728 and could never open there at all.
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
-- How long the quiet zone (GC.Sniper.IsPurchaseQuiet) may veto every search sender before it
-- is released. The zone is what stops a scan page or a watch poll from replacing the client's
-- single commodity search buffer under an in-flight buy -- but a purchase the auction house
-- never answers produces no terminal event at all, and an unbounded veto is how the whole
-- board stopped. Longer than every purchase timeout above, so a real answer always lands
-- first, and only ever applied with no dialog on screen.
LIM.QUIET_ZONE_MAX_SECONDS = 30
-- How long the "waiting for previous commodity purchase to settle" tombstone may refuse the
-- next Buy. Commodity events carry no attempt identifier, so a cancelled or errored attempt
-- owns a tombstone until a terminal event consumes it -- and CancelCommoditiesPurchase fires
-- none of the three, an auction house error fires none of the three, so "until" can be never.
-- Longer than LIM.BUY_TIMEOUT_SECONDS so a real terminal event always lands first. Only ever
-- applied to an UNCONFIRMED attempt: no gold moved there, and the worst a misattributed late
-- event can then do is cancel a fresh attempt, which is the fail-safe direction.
LIM.DRAIN_TIMEOUT_SECONDS = 20
-- How long a SEARCH fence may refuse a fresh live check for the same item. Search results are
-- untagged, so a cancelled or timed-out query leaves a fence that only the late result can
-- lift -- and a query the auction house never answers at all leaves one nothing can. Past this
-- the reply is older than any real round trip and is presumed lost; the Sell tab's own
-- DRAIN_MAX_SECONDS is the same number for the same reason. Purely a search fence: no gold
-- depends on it, unlike LIM.DRAIN_TIMEOUT_SECONDS above.
LIM.DRAIN_FENCE_SECONDS = 15
-- How long a CONFIRMED commodity purchase the server never answered may hold its ownership --
-- and with it the quiet zone, which vetoes every search this addon makes. It used to be 60,
-- which is twice LIM.QUIET_ZONE_MAX_SECONDS: the zone's own release runs at 30s, finds a
-- confirmed attempt it must never touch, and restarts its clock, so the board and the Sell tab
-- stood still for a full minute. Still far longer than any real terminal event takes, and a
-- late one is still credited after the release (see takeStrandedConfirmed) -- so nothing about
-- the gold is decided any sooner, only the waiting.
LIM.STRANDED_RELEASE_SECONDS = 35
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

-- Sniper fast loop, phase 1: the book-pass wide-pass cadence and the drill-down queue's
-- per-minute SendSearchQuery budget. See Core/BookPass.lua / Core/DrillQueue.lua.
LIM.WIDE_PASS_SECONDS = 300
LIM.DRILL_PER_MINUTE = 60

-- Sniper phase 2: how long a sent keys batch may go unanswered before the arbiter stops
-- waiting for it. A batch answers in 200-400ms when it answers at all; this only exists so a
-- browse event that never arrives cannot stop the poll for the rest of the session.
-- A SearchForItemKeys of a hundred keys routinely answers after more than eight seconds. At
-- 8 the wait was written off early, a pass started, and the late answer -- gear rows -- was
-- read as that pass's first page: "full results" at once, zero commodities, pass after pass
-- (20 listings over 10 passes, measured in game), while the Items board kept only the
-- answers that happened to arrive fast.
LIM.KEYS_TIMEOUT_SECONDS = 30
-- The Sell tab's bulk fill is the one owner that stops wanting its answer sooner: its walk
-- stands still for eight seconds (GC.Sell.BulkOutstanding in UI/SellFrame.lua -- keep the two
-- equal) and then searches on, and a search sent over an unanswered keys call cancels its
-- answer. Held for the full thirty, a REFRESH on Sell followed by a switch to Deals kept the
-- board waiting half a minute for rows nobody was going to read.
LIM.KEYS_SELL_TIMEOUT_SECONDS = 8
-- The Items board's own loop: once a poll cycle has visited every target, the next one starts
-- this many seconds later. The cycle used to restart only when a book pass began, and the
-- pass is paused for as long as the Items board is on screen -- so the board polled its set
-- exactly once after a switch and then stood still for the rest of the visit (seen in game
-- 2026-09-15: "sat on Commodities, switched to Items, nothing updated").
LIM.KEYS_CYCLE_BREATHER_SECONDS = 5

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
local lastBrowseEventAt = 0        -- time() of the last browse-results event seen for the current scan; armScanWatchdog compares this against each send
local fullScanToken = 0

-- T6 streaming: deals now surface WHILE the scan pages instead of only once
-- HasFullBrowseResults() finally goes true. TWO counters, not one, because
-- GC.FullScan.RowsFromBrowse filters (a browse aggregate with no itemID/minPrice is
-- dropped), so "raw browse entries seen" and "rows produced from them" are different
-- lengths -- conflating them would either re-convert already-converted raw entries or skip
-- some on the next tail slice.
local streamRows = {}      -- rows (RowsFromBrowse's { itemID, count, buyoutStack } shape) accumulated across every page of the CURRENT scan pass
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
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("sniper") end
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
    --
    -- The timer is not the only retirement: onDialogPrimaryClick reads `drainingAt` below and
    -- retires an expired tombstone at the click itself, because a timer that was never armed
    -- (or never ran) is exactly how a Buy stayed refused with the button enabled.
    pending.drainingAt = GetTime()
    if not pending.confirmed then
      C_Timer.After(LIM.DRAIN_TIMEOUT_SECONDS, function()
        if commodityDraining == pending and not pending.confirmed then
          commodityDraining = nil
        end
      end)
    end
    return pending
  end
end

-- Retires an unconfirmed tombstone that OnCommodityPriceUpdated fenced on the requery (row +
-- token) whose result has now landed. The search that result answers was sent after the Cancel,
-- so any late quote for the cancelled attempt was delivered ahead of it; the tombstone has
-- nothing left to guard against. Confirmed tombstones are never touched -- their late success
-- still has to land on the attempt that paid.
--
-- One helper for the three places a fenced requery can end: finishRequery (the ordinary case),
-- GC.Sniper._FinishDrainWait (the requery that had to wait for an older search to drain) and
-- the drop in GC.Sniper.OnCommoditySearchResults for a requery that stopped being current before
-- its result arrived -- a board repaint under the dialog does that. That third one used to skip
-- the retirement, and the Buy was refused with "waiting for previous commodity purchase to
-- settle" for the tombstone's whole 20 seconds over a purchase that was cancelled and cost
-- nothing (observed live 2026-09-15, `/gc sniper`: tombstone fenced on token 2, no requery
-- waiting). A field on GC.Sniper rather than a file local: this chunk sits near Lua's 200-local
-- ceiling (see the addon's engineering notes).
function GC.Sniper._RetireFencedTombstone(row, token)
  local tombstone = commodityDraining
  if tombstone and not tombstone.confirmed and tombstone.fenceRow == row
      and tombstone.fenceToken == token then
    commodityDraining = nil
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

-- The drain fence for one item, or nil -- and the only way any of this file reads
-- requeryDraining, because the fence has to be able to expire. It is waiting for an untagged
-- search result that a cancelled/timed-out query may still produce; when the auction house
-- simply never answers, that result is never coming, and the fence used to stand for the whole
-- session: one unanswered search and that item could never be checked again, with the board
-- quietly skipping it and the Check button saying "waiting for previous search result to
-- settle" forever. Past LIM.DRAIN_FENCE_SECONDS the wait is older than any reply could be, so
-- it is lifted -- the same bound, for the same reason, as the Sell tab's own DRAIN_MAX_SECONDS.
-- Published as a field rather than a new top-level local: this file is at its 200-local ceiling.
function GC.Sniper._DrainFence(itemID)
  local attempt = requeryDraining[itemID]
  if not attempt then return nil end
  if attempt.drainAt and (GetTime() - attempt.drainAt) > LIM.DRAIN_FENCE_SECONDS then
    requeryDraining[itemID] = nil
    return nil
  end
  return attempt
end

-- Fences an item behind the sent-but-unanswered search `attempt`. Every caller went through
-- `requeryDraining[itemID] = attempt` by hand and none of them stamped a time, which is what
-- made the fence permanent.
function GC.Sniper._FenceDrain(itemID, attempt)
  attempt.drainAt = GetTime()
  requeryDraining[itemID] = attempt
end

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
-- Slot arbiter. The browse scan, the watch loop and the background verify walk are all
-- BACKGROUND consumers of one throttled search slot; the rotation below hands it round so
-- speeding up any one of them cannot silently stop the other two. Starts on the watch loop --
-- it is the latency-sensitive one, and the browse scan is a marathon either way. The order is
-- the rotation, so it is a table rather than three booleans: adding a fourth consumer must not
-- mean rewriting the arbiter's branching.
local SLOT_ORDER = { "watch", "verify" }
local slotTurn = 1
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
-- Timeline entries for `/gc board` (Core/Util.lua's GC.Util.Trace); a no-op in specs that load
-- this file without Util.
local function trace(tag)
  if GC.Util and GC.Util.Trace then GC.Util.Trace(tag) end
end
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
-- Forward-declared for the same reason again: applySortOverride (below) now reads the live
-- verdict through GC.BoardRows.Compare, and it is defined above verdictFor's own body.
local verdictFor
-- Live price caps, addon task 6: forward-declared for the same reason as stampVerdict above --
-- refreshRows() (below) drains pendingCapPings through this at the end of every render, but its
-- real body (built on flashRow) is defined far below refreshRows.
local pingNewHotDeals
-- Forward-declared for the same reason again: refreshRows() drains pendingCapPings through this
-- too, and its real body reuses onBuyClick -- the row's own click path -- which is defined far
-- below refreshRows.
local drainCapPings

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
-- Live price caps, addon task 6: cap deals GC.Caps.Announce just approved as newly-rung, queued
-- by evaluateLiveCommodityDeal/evaluateLiveItemDeal (wherever buildCapDeal merges one into board
-- state) and drained by refreshRows() at the end of its own render -- by then the row painting
-- loop above it has already stamped `row.deal` for this pass, so pingNewHotDeals' table-identity
-- match (the same one a full-scan HOT deal uses) can find the row this exact table landed on.
local pendingCapPings = {}
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

-- Which of the two boards the Deals view is showing: "commodities" (the browse scan's own
-- finds -- region-priced, live-verifiable, the only rows that can ever become BUY) or "items"
-- (the key poll's gear, pets and recipes -- realm-priced, unverified, WATCH-only).
--
-- They were one list until 0.9.2, and one list could not serve both: a realm lead is worth
-- five figures where a reagent flip is worth three, so the shared profit sort put realm rows
-- on top and the shared hundred-row cap then evicted the commodities underneath them --
-- "fewer commodities than before 0.9.0", measured on the owner's own board. Two boards, two
-- caps, two promises.
--
-- Read through here rather than off the setting directly so a save carrying anything else
-- (an older build, a hand-edited SavedVariables) lands on Commodities rather than on a board
-- that does not exist. A function on GC.Sniper, not a new top-level local: this file is at
-- its 200-local ceiling (see the addon's engineering notes).
function GC.Sniper._Board()
  local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
  return (cfg and cfg.board == "items") and "items" or "commodities"
end

-- Which tab the rail is on ("deals" | "sell" | "sold" | "buy"). The other UI files own their
-- own tab and have no business reading this file's `view` upvalue -- but a tab that competes
-- for the one throttled search slot has to know whether the player is looking at it, and
-- UI/BuyFrame.lua's floor refresh is exactly that. A function on GC.Sniper for the same
-- reason _Board() above is one: this file is at its 200-local ceiling.
function GC.Sniper.CurrentView() return view end

-- How many realm rows the Items board is holding right now -- the number its own chip carries.
function GC.Sniper._RealmCount()
  local count = 0
  for _ in pairs(GC.Sniper._realmDeals or {}) do count = count + 1 end
  return count
end

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
  -- The one membership rule, shared by all three stores below: a deal is on the board unless
  -- its row is frozen under the cursor, under an open Check/Buy, or under a display pin.
  -- A closure inside this function, not a file-level helper: locals declared inside a function
  -- cost nothing against Lua's 200-local chunk ceiling, and this file sits at it.
  local function renders(itemID)
    return not activeItemID[itemID] and itemID ~= hoveredItemID
      and not (frozen and frozen[itemID])
  end
  -- The Items board is the key poll's own store, in BOTH modes. The poll answers about realm
  -- items whether or not a full scan has ever run, so gating this board on `mode` would leave
  -- the player looking at an empty board with rows in hand.
  if GC.Sniper._Board() == "items" then
    for itemID, deal in pairs(GC.Sniper._realmDeals or {}) do
      if renders(itemID) then list[#list + 1] = deal end
    end
    return list
  end
  if mode == "fullscan" then
    -- Order is not decided here and is not preserved from here: applySortOverride re-sorts
    -- this list off the live verdict (GC.BoardRows.Compare) on every render, so all this loop
    -- owes the caller is membership -- every scanned deal except the ones frozen under the
    -- cursor or a purchase.
    for _, deal in ipairs(scanDeals) do
      if renders(deal.itemID) then
        list[#list + 1] = deal
      end
    end
    return list
  end
  for itemID, deal in pairs(deals) do
    if renders(itemID) then
      list[#list + 1] = deal
    end
  end
  -- Unsorted on purpose: applySortOverride (below) is the one place the board's real order
  -- gets decided now, default view included -- it runs GC.BoardRows.Compare over this list
  -- either way, so sorting it here first would only be thrown away.
  return list
end

-- Raw comparison value per sortable header (E.2). "Item" has no entry -- it's not sortable,
-- see the addHeader calls. I6: "unit" (per-unit price) is its OWN sort key, independent of
-- "price" (total = unit*qty) -- total's own column (COLUMNS "total") is one of the two
-- responsively-dropped columns (see computeHidden), so without a separate always-visible
-- sort key, sorting the list by price would become unreachable via the header at any window
-- width <=724px. "unit" lives on the never-dropped COLUMNS "unit" column instead.
local SORT_VALUE = {
  -- The column is the VERDICT column now, so clicking its header sorts by what the live check
  -- said -- GC.BoardRows' own bucket order, the same one the default view uses -- and not by
  -- the discovery-time tier, which the row has not shown since the verdict replaced it. The
  -- second argument (whether a live look is already queued for this row) is sampled once per
  -- render by the caller; every other entry here ignores it.
  tier = function(deal, pending) return GC.BoardRows.Rank(verdictFor(deal), pending) end,
  pct = function(deal) return deal.discount end,
  unit = function(deal) return deal.unitPrice end,
  price = function(deal) return deal.unitPrice * deal.qty end,
  profit = function(deal) return deal.profit end,
}

-- Applies the header-click sort override (if any) on a COPY of `list` -- `list` here is
-- already sortedDeals()'s own freshly-built array (never the live `deals`/`scanDeals`
-- tables themselves), and this function copies it again before table.sort besides, so a
-- sort click can never be observed as having mutated either backing store. With no override
-- this is also where the board's DEFAULT order now comes from (Sniper fast loop, phase 1):
-- SAFE before WATCH before UNVERIFIED off the live verdict, GC.BoardRows.Compare -- the same
-- comparator backs the header-click tiebreak below, so ties under any override key never look
-- shuffled relative to the default view either.
local function applySortOverride(list)
  -- The unknown-key bailout returns `list` itself, so allocating the copy above it was work
  -- thrown away on every render that hit it.
  local valueOf = sortOverride and SORT_VALUE[sortOverride.key]
  if sortOverride and not valueOf then return list end -- defensive: onHeaderSortClick never sets an unknown key
  -- Whether a live look is already queued for each row, sampled ONCE per render rather than
  -- inside the comparator, which table.sort calls O(n log n) times over up to a hundred rows.
  -- The verify walk's own window is deliberately NOT folded in: that window is defined BY the
  -- result of this sort, so feeding it back in as an input would rank whoever is already in
  -- the top rows above every unverified row below them -- and so keep them there, permanently,
  -- however much better the row underneath got.
  local copy, pending = {}, {}
  for i, deal in ipairs(list) do
    copy[i] = deal
    pending[deal.itemID] = GC.Sniper._drillQueue:Has(deal.itemID)
  end
  if not valueOf then
    table.sort(copy, function(a, b)
      return GC.BoardRows.Compare(a, verdictFor(a), pending[a.itemID], b, verdictFor(b), pending[b.itemID])
    end)
    return copy
  end
  local desc = sortOverride.desc
  table.sort(copy, function(a, b)
    local va, vb = valueOf(a, pending[a.itemID]), valueOf(b, pending[b.itemID])
    if va == vb then
      return GC.BoardRows.Compare(a, verdictFor(a), pending[a.itemID], b, verdictFor(b), pending[b.itemID])
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

-- Fix batch (stuck-hover freeze): shared by OnEnter/OnLeave's hover pin (createRow, below) and
-- the window's own OnHide -- releases the hover pin and hides the accent painted for it. OnLeave
-- is not reliably delivered when a frame hides under a stationary cursor (see the addon's engineering notes),
-- so OnHide calls this directly rather than counting on OnLeave firing first. Without it, hiding
-- the window (Escape, the title-bar X) while a row was hovered left `hoveredRow` pointing at a
-- pooled row forever: refreshRows() skips a row that still equals hoveredRow, and sortedDeals()
-- also excludes hoveredRow's own itemID from the list -- so that row could neither repaint nor
-- ever show anything else again.
local function clearHover()
  if not hoveredRow then return end
  local row = hoveredRow
  -- The row's OnEnter opened an item tooltip, and only its OnLeave ever closed it -- which is
  -- the one script that does not fire on these paths (the window hiding, the auction house
  -- closing). The tooltip was left floating over the screen with nothing under it, and stayed
  -- there until the cursor happened to cross something else that owns one.
  GameTooltip:Hide()
  row.highlight:Hide()
  -- A watched row keeps its blue rail up even once unhovered -- see the matching comment in
  -- setRowDeal.
  if not (row.deal and isPinned(row.deal.itemID)) then row.rail:Hide() end
  hoveredRow = nil
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
verdictFor = function(deal)
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
    -- `unverified` rows are not pruned and not counted either, for the same reason `manual`
    -- ones are not: a realm lot the check found under its region reference did not shorten
    -- this list, it is one of the things ON it (see stampVerdict).
    if verdict and not verdict.buyable and not verdict.manual and not verdict.unverified
        and not pinned then
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
  --
  -- On the board the pin's own item belongs to, and only there (0.9.2): a pinned piece of gear
  -- placed a dimmed twin on the Commodities board, which is exactly the mixing the two boards
  -- exist to end, and it is still right-clickable off wherever it does appear. An item nothing
  -- knows a realm reference for counts as a commodity here -- the same default the rest of the
  -- board reads it as.
  local itemsBoard = GC.Sniper._Board() == "items"
  for _, itemID in ipairs(GC.Sniper._WatchPins()) do
    local realmPin = (GC.Sniper._RealmValue and GC.Sniper._RealmValue(itemID)) ~= nil
    local present = realmPin ~= itemsBoard -- "already handled": it belongs to the other board
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

  -- Which rows may say "…" (something is checking this). Exactly two things check a row: the
  -- drill queue, which holds a specific item at a specific floor, and the verify walk, which
  -- only ever reaches the top LIM.VERIFY_TOP_ROWS of THIS list (see stepVerifyWalk, which
  -- calls renderList and slices the same way). Every other row is simply not being looked at,
  -- and the board used to promise all of them a check that was never coming. A pin placeholder
  -- is excluded because the walk skips it outright -- there is no price on it to verify.
  -- Published as a table field rather than a new top-level local: this file is at its
  -- 200-local ceiling (see the addon's engineering notes).
  -- The walk's reach is GC.Sniper._VerifySlice (defined beside stepVerifyWalk, which slices
  -- the very same way): its top rows per kind, not the top rows of the list as a whole.
  local pendingRows = {}
  local inSlice = {}
  if GC.Sniper._VerifySlice then
    local slice = GC.Sniper._VerifySlice(pinnedRows)
    -- Published for stepVerifyWalk, which needs this exact list and used to build it again
    -- itself -- a whole filter, sort and partition of the board plus one item-key lookup per
    -- row, every time the throttle offered it a slot, for a list this render had just finished
    -- computing. Every change to the board goes through refreshRows, and refreshRows is what
    -- calls this, so the published slice is never older than the board it describes.
    GC.Sniper._verifySlice = slice
    for i = 1, #slice do inSlice[slice[i].itemID] = true end
  end
  for i = 1, #pinnedRows do
    local entry = pinnedRows[i]
    if not entry.pinPlaceholder
        and (inSlice[entry.itemID] or GC.Sniper._drillQueue:Has(entry.itemID)) then
      pendingRows[entry.itemID] = true
    end
  end
  GC.Sniper._pendingRows = pendingRows

  return pinnedRows
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
  -- 80, not the 48 it shipped with (and not the 72 it grew to first). 48 was sized for a
  -- four-letter tier pill (HOT/GOOD/WATCH/SUSPECT); the cell now carries the live verdict,
  -- and GC.BoardRows.Label floors SAFE's money to whole gold (never "61g35s" -- see
  -- Core/BoardRows.lua), so its longest realistic form is "SAFE +9999g" -- eleven characters,
  -- which at this project's measured ~6px per mono character (see spec/button_label_width_
  -- spec.lua for where that figure comes from) needs about 66px of text plus the 11px the
  -- TierMark's dot and its gap take: 77px, over the 72px this column shipped with. 80 leaves
  -- 2px of the usual clearance. The 32px comes out of the flexible item column, which has 180
  -- to give. Theme.TierMark bounds its own FontString to these edges besides, so a longer
  -- translation clips inside the cell instead of painting across the discount and price
  -- columns beside it -- which is exactly what the old "WATCH <whole sentence>" label did.
  { key = "tier",   w = 80 },
  { key = "disc",   w = 56,  num = true, size = 15, bold = true },
  { key = "unit",   w = 76,  num = true, size = 12 },
  { key = "total",  w = 84,  num = true, size = 12, optional = true },
  { key = "profit", w = 84,  num = true, size = 13, bold = true },
  { key = "trend",  w = 44,  num = true, size = 11, optional = true },
  -- 64, not the 52 it shipped with. 52 was sized for English -- "Check" is five characters --
  -- and every other language's word for it is eight or nine, so the label drew straight across
  -- the profit figure to its left in nine of the eleven locales. Theme.Button now clips a label
  -- to its own button rather than letting it paint outside, but clipping "Comprobar" to fit 52
  -- is not a fix either; 64 holds the longest of them with the translations shortened to match
  -- (spec/button_label_width_spec.lua carries the budget). The 12px comes out of the flexible
  -- item column, which has 180 to give.
  { key = "buy",    w = 64 },
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
    deal.itemID, deal.unitPrice, deal.qty, tostring(deal.avail),
    (GC.Sniper._pendingRows or {})[deal.itemID] and 1 or 0, deal.profit, tostring(deal.discount),
    deal.pinPlaceholder and 1 or 0, deal.priceUnknown and 1 or 0, tostring(deal.action),
    pinned and 1 or 0, (verdict and verdict.status) or "", (verdict and verdict.buyable) and 1 or 0,
    (verdict and verdict.reason) or "", (verdict and verdict.stressProfit) or "",
    tostring(trend),
    -- Live price caps, addon task 6: a cap-bucket transition or a changed group/price at the
    -- SAME unitPrice+profit (a re-Adopt from the site swapping which group owns this item)
    -- moves the CAP tier chip and the row subtitle -- neither is covered by anything above.
    (verdict and verdict.cap) and 1 or 0, tostring(deal.capGroup),
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
      row.buy:SetLabel(GC.L["Buy"])
      row.buy:SetVariant("primary")
    elseif verdict then
      -- Only reachable with the toolbar toggle showing refused rows; the status is the engine's
      -- own word for it, and the row tooltip (createRow's OnEnter) carries the reason.
      row.buy:SetLabel(verdict.status or GC.L["Avoid"])
      row.buy:SetVariant("ghost")
    else
      row.buy:SetLabel(deal.action or GC.L["Check"])
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
  local verdictColor
  if verdict and verdict.buyable then
    verdictColor = Theme.color.green
  elseif verdict then
    verdictColor = Theme.tier.WATCH
  else
    verdictColor = Theme.color.fgDim
  end
  row.tierChip:SetLabel(
    GC.BoardRows.Label(verdict, (GC.Sniper._pendingRows or {})[deal.itemID]), verdictColor)

  -- A pin placeholder is not a deal -- there is nothing to discount against, so this cell says
  -- nothing rather than the "0%" renderList's placeholder table (discount = 0, kept for callers
  -- that need a number) would otherwise print.
  if deal.pinPlaceholder then
    row.discountText:SetText("—")
    row.discountText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  else
    row.discountText:SetText(("%d%%"):format(math.floor(deal.discount * 100 + 0.5)))
    row.discountText:SetTextColor(verdictColor[1], verdictColor[2], verdictColor[3])
  end

  -- A placeholder pin with nothing observed yet has no price to show -- deal.unitPrice is only
  -- the sentinel 0 kept in the table for callers that need a number. Rendering it through
  -- GC.Util.FormatMoney would print a literal 0-copper price nothing polled, so it gets the same
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
    row.unitText:SetText(GC.Util.FormatMoney(deal.unitPrice))
    row.unitText:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
    row.priceText:SetText("—")
    row.priceText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  else
    row.unitText:SetText(GC.Util.FormatMoney(deal.unitPrice))
    row.unitText:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
    row.priceText:SetText(GC.Util.FormatMoney(deal.unitPrice * deal.qty)) -- total cost, not per-unit
    row.priceText:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
  end

  -- A pin placeholder has no deal to have made a profit on -- this cell says nothing rather
  -- than a formatted 0-copper coin string (profit = 0, the same placeholder sentinel).
  --
  -- Live price caps, addon task 6: a cap deal with nothing to compare against (no market value
  -- at all for this item -- the cap needs none, Core/Caps.lua's own contract) has the same
  -- "nothing to show" problem. buildCapDeal's estProfit degrades to `-unit` in that case, which
  -- would read as a real loss instead of "we don't know" -- deal.profit already equals
  -- deal.estProfit for a cap deal (buildCapDeal sets both from the same number), so this is the
  -- one case that needs its own branch rather than a field swap.
  if deal.pinPlaceholder or (deal.cap and deal.mv == nil) then
    row.profitText:SetText("—")
    row.profitText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  else
    row.profitText:SetText((deal.profit > 0 and "+" or "") .. GC.Util.FormatMoney(deal.profit))
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
  local watchSuffix = deal.pinPlaceholder
    and ("|cff8c8a85%s|r"):format(GC.L[" · watching"]) or ""
  -- Live price caps, addon task 6: a cap row belongs to an alert group -- say so, and say the
  -- price it rang for, the same dim suffix pattern watchSuffix uses (own color code, so it
  -- never inherits the quality-colored name). Only for a named group; a manual (ungrouped) cap
  -- has nothing extra to say here that the CAP tier chip does not already.
  local capSuffix = deal.capGroup
    and ("|cff8c8a85 %s|r"):format((GC.L["%s · your price %s"]):format(
      deal.capGroup, GC.Util.FormatGoldFloor(deal.cap)))
    or ""
  local cached = nameIconCache[deal.itemID]
  if cached then
    row.icon:SetTexture(cached.icon)
    row.nameText:SetText(cached.named .. qtySuffix(deal) .. capSuffix .. watchSuffix)
  else
    row.nameText:SetText((GC.L["item %d"]):format(deal.itemID) .. qtySuffix(deal) .. capSuffix .. watchSuffix)
    row.icon:SetTexture(nil)

    local item = Item:CreateFromItemID(deal.itemID)
    item:ContinueOnItemLoad(function()
      if row.deal ~= deal then return end -- row was repurposed before the async load finished
      local icon = item:GetItemIcon()
      local quality = item:GetItemQuality()
      local qc = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
      local label = item:GetItemName() or ("item " .. deal.itemID)
      -- Reagent quality beside the name. Two tiers of the same reagent are
      -- separate itemIDs and so already price separately -- this is identification,
      -- not arithmetic, but on a list of ores and herbs it is the difference
      -- between reading a row and guessing at it.
      local named = (qc and qc:WrapTextInColorCode(label) or label)
      if Theme.QualityMarkup then
        local pip = Theme.QualityMarkup(deal.itemID, 12)
        if pip ~= "" then named = named .. " " .. pip end -- after the name, as Theme.WithQuality
      end
      nameIconCache[deal.itemID] = { icon = icon, named = named }
      row.icon:SetTexture(icon)
      row.nameText:SetText(named .. qtySuffix(deal) .. capSuffix .. watchSuffix)
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
        -- A row that empties mid-flash keeps the animation running behind the Hide(), and
        -- setRowDeal's own stop only fires for a slot that still remembers a deal -- which
        -- this one is about to forget. So the next deal to land here inherited a "new HOT
        -- deal" ping it never earned: a gold flash on an ordinary row.
        if row.flashAnim then
          row.flashAnim:Stop()
          row.flash:Hide()
          row.flash:SetAlpha(1)
        end
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
  -- Same breath, same reason: the Items chip carries a count of a store this render did not
  -- read (the player is on Commodities most of the time), so it is re-derived here rather
  -- than at each of the half-dozen places a realm row can appear or leave.
  GC.Sniper._PaintBoardChips()

  -- Live price caps, addon task 6: the row-painting loop above has just stamped `row.deal` for
  -- this render, so a cap deal GC.Caps.Announce approved earlier this call chain (queued into
  -- pendingCapPings by evaluateLiveCommodityDeal/evaluateLiveItemDeal) can now be matched to the
  -- row it landed on, the same way CollectNewHot's own HOT deals are. Reassigning the table
  -- (rather than clearing it in place) is safe: every closure that pushes into it shares this
  -- same upvalue, so the next push lands in the fresh one.
  if #pendingCapPings > 0 then
    local pings = pendingCapPings
    pendingCapPings = {}
    drainCapPings(pings)
  end
end

-- E.2: re-stamps every sortable header's label with a " ▼"/" ▲" suffix on whichever one is
-- active (▼ = descending, ▲ = ascending); every other header falls back to its plain base
-- text. sortHeaders is populated once by the addHeader calls. Literal UTF-8 glyphs
-- (not \xXX escapes -- WoW's client Lua is 5.1, which has no hex string escape) in a file
-- saved as UTF-8; Lua strings are just byte arrays so this needs no special handling.
--
-- It also re-stamps EVERY heading label, sortable or not, from its base text. A one-line
-- (SetMaxLines(1)) FontString that lives inside a frame which was hidden and shown again --
-- the header row behind the Sell/Sold tabs -- can come back with its text simply not drawn
-- (the PROFIT/TREND labels went blank in-game after a tab switch, and reappeared only when a
-- header was clicked, i.e. when this function next ran). SetText is what the client needs to
-- draw it again, so every caller that re-shows the row goes through here.
local function updateHeaderSortIndicators()
  local header = frame and frame.headerRow
  if header and header.cells then -- specs fake headerRow as a bare Show/Hide stub
    for _, cell in pairs(header.cells) do cell.label:SetText(cell.baseText) end
    if header.itemCell then header.itemCell.label:SetText(GC.L["ITEM"]) end
  end
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

-- Re-derives both board chips from the setting and from the Items store's own size. Same
-- contract as refreshAutoButton/refreshScanButton/refreshVerifyButton: driven off refreshRows
-- and the 0.25s ticker through it, rather than hooked into every place a realm row can land,
-- so a new path cannot silently leave a stale count on the toolbar. The count is what makes
-- the switch worth having while the player is on Commodities: it says how much is waiting on
-- the other board without moving them off this one.
function GC.Sniper._PaintBoardChips(target)
  local owner = target or frame
  local chips = owner and owner.boardChips
  if not chips then return end
  local count = GC.Sniper._RealmCount()
  -- Two keys, not one with a conditional count: "ITEMS 0" is a promise of a number that is
  -- not there, and a chip reading "ITEMS" says the same thing without pretending to count.
  local labels = {
    commodities = GC.L["COMMODITIES"],
    items = count > 0 and (GC.L["ITEMS %d"]):format(count) or GC.L["ITEMS"],
  }
  local board = GC.Sniper._Board()
  for id, chip in pairs(chips) do
    local text = labels[id]
    if text and chip.lastText ~= text then
      chip:SetLabel(text)
      chip.lastText = text
    end
    local on = (board == id)
    if chip.lastOn ~= on then
      chip.lastOn = on
      chip:SetVariant(on and "active" or "ghost")
    end
  end
end

-- The board switch itself. Persists the choice (it is a preference, not a session state --
-- a player who works the Items board should not be handed Commodities again on every login),
-- then re-paints the chips, re-stamps the header sort indicator (the heading labels are
-- one-line FontStrings and the sort arrow belongs to whichever board is now up) and re-renders.
-- Scroll goes back to the top: a different board is a different list, and the old one's
-- scroll offset describes rows that are not there any more.
function GC.Sniper._SetBoard(id)
  local board = (id == "items") and "items" or "commodities"
  local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
  if cfg then cfg.board = board end
  trace("board: " .. board)
  if frame and frame.scroll then frame.scroll:SetVerticalScroll(0) end
  GC.Sniper._PaintBoardChips()
  updateHeaderSortIndicators()
  refreshRows()
  -- One browse buffer serves both the pass's pages and the poll's keys batches, and the two
  -- cannot share it: a pass paging under the poll answered the Items board late and the
  -- Commodities board with two-row pages (measured in game: 20 listings over 10 passes).
  -- So the board on screen owns the buffer. Items pauses Auto's pass the way the Sell tab
  -- does (its keys batches then chain freely, one answer starting the next); Commodities
  -- resumes it. A manual pass still in flight is aborted by the pause itself.
  if feedAuto then feedAuto(board == "items" and "pause:items" or "resume:items") end
  if board == "items" and GC.Sniper._TrySendKeysBatch then GC.Sniper._TrySendKeysBatch() end
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
--
-- Companion nudge: GC.Data.OriginState() ("none"|"manual"|"app") is the one source of truth
-- for where these prices came from (Core/Data.lua). "none" and "manual" both point the player
-- at the free Companion (/goldcap companion) rather than leading with the manual paste, and
-- the banner itself becomes a click target for the same dialog -- see the lazily-built
-- frame.staleHit region below. "app" data already comes from the Companion, so its wording
-- and lack of a click target are both unchanged.
local function refreshStaleText()
  if not frame or not frame.staleText then return end
  -- Lazily built once: an invisible hit-region tracking staleText's own bounds (FontString/
  -- Texture objects can't take mouse scripts themselves -- same pattern as createHeaderRow's
  -- header hit-frames and the purchase dialog's itemHit). EnableMouse is re-set on every
  -- refresh below rather than at construction, since it depends on the current origin.
  if not frame.staleHit then
    local hit = CreateFrame("Frame", nil, frame)
    hit:SetAllPoints(frame.staleText)
    hit:SetScript("OnMouseUp", function(_, button)
      if button == "LeftButton" then GC.CompanionUI.Show() end
    end)
    -- The banner sits inside the 32px title bar, right-justified against the close button, so
    -- an EnableMouse'd hit region here would otherwise swallow the title bar's own drag (see
    -- Theme.TitleBar's `bar`, a sibling frame at the same level) for its whole width. Forward
    -- drag exactly the way Theme.lua's TitleBar does, IsMovable guard included -- a docked
    -- window (GC.Sniper.SetDocked) flips SetMovable off, and StartMoving on an immovable frame
    -- is a Lua error, not a no-op.
    hit:RegisterForDrag("LeftButton")
    hit:SetScript("OnDragStart", function() if frame:IsMovable() then frame:StartMoving() end end)
    hit:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    frame.staleHit = hit
  end

  local age = importAgeSeconds()
  local origin = GC.Data.OriginState()
  -- Defensive: OriginState() and importAgeSeconds() both read GC.db.imported.ts today, so a
  -- non-"none" origin with no age should never happen -- but nothing enforces that invariant
  -- across the two functions, and "attempt to compare nil with number" below would be an ugly
  -- way to find out it broke. Treat the divergence as "none" rather than raising.
  if origin ~= "none" and not age then origin = "none" end
  frame.staleHit:EnableMouse(origin ~= "app")

  -- Live price caps, addon task 6: text/color/shown are decided here and applied once at the
  -- end, rather than each branch calling SetText/SetTextColor/Show/Hide directly as before --
  -- the caps freshness note below needs to APPEND to (or stand in for) whatever this decided,
  -- including the "hide the banner entirely" case, without reading the widget back
  -- (frame.staleText is a bare fake in several specs, with no GetText/IsShown of its own).
  local text, color, shown

  if origin == "none" then
    -- Kept short deliberately: staleText is SetWordWrap(false) and right-justified against the
    -- title bar, so it overflows leftward rather than truncating -- the longer "install GoldCap
    -- Companion" phrasing risked overlapping the window title at RESIZE_MIN_WIDTH (640).
    text = GC.L["no prices yet -- /goldcap companion or /goldcap import"]
    color, shown = Theme.color.red, true
  elseif origin == "app" then
    if age < LIM.STALE_YELLOW_SECONDS then
      shown = false
    elseif age < LIM.STALE_RED_SECONDS then
      text = (GC.L["auto-synced %dh ago"]):format(math.floor(age / 3600))
      color, shown = Theme.tier.SUSPECT, true
    else
      text = GC.L["auto-synced data stale -- /goldcap import"]
      color, shown = Theme.color.red, true
    end
  else -- manual
    if age < LIM.STALE_YELLOW_SECONDS then
      -- Fresh manual data used to hide the banner entirely; it now stays up, dim, as the
      -- nudge toward the Companion -- the whole point is that "fresh" here still means
      -- "will go stale on its own", unlike auto-synced data.
      text = GC.L["manual import -- Companion keeps this fresh: /goldcap companion"]
      color, shown = Theme.color.fgDim, true
    elseif age < LIM.STALE_RED_SECONDS then
      text = (GC.L["import %dh old"]):format(math.floor(age / 3600))
      color, shown = Theme.tier.SUSPECT, true
    else
      text = GC.L["import stale -- /goldcap import or /goldcap companion"]
      color, shown = Theme.color.red, true
    end
  end

  -- Caps freshness is independent of the import-origin banner above: a companion-synced cap
  -- list is on its own clock, so a player running an all-caps alert group with fresh (or no)
  -- imports still needs to know how current the price ceilings they're being shown are.
  -- _G.date is a WoW-injected global, absent under busted (see UI/SoldFrame.lua's own guard
  -- for the same fact) -- this degrades to nothing where it isn't stubbed, rather than erroring.
  if GC.Caps and GC.Caps.Count() > 0 and _G.date then
    local capsNote = (GC.L["%d caps from %s"]):format(
      GC.Caps.Count(), _G.date("%H:%M", GC.Caps.GeneratedAt()))
    text = shown and (text .. "  " .. capsNote) or capsNote
    color = color or Theme.color.fgDim
    shown = true
  end

  if shown then
    frame.staleText:SetText(text)
    frame.staleText:SetTextColor(color[1], color[2], color[3])
    frame.staleText:Show()
  else
    frame.staleText:Hide()
  end
end

-- Whether the loaded import can ever arm the sniper at all -- see Core/Trigger.lua's own
-- comment. Only the verification-fact candidates matter: GC.Trigger.For needs a stressUnit,
-- and only those entries carry one (GC.Data.GetItemValue's own branching).
-- _UpdateEmptyState is driven by renderList()/refreshRows() and the 0.25s ticker, so a naive
-- rebuild-and-walk here re-walks the whole verification table ~4x/second for as long as a
-- large import's board stays empty. Memoized instead, keyed on the verification table's own
-- identity (the import is replaced wholesale on a fresh import, never mutated in place) and
-- the two settings GC.Trigger.For reads. Cached on GC.Sniper._armedCache -- a table field, not
-- a new top-level local, so this costs no headroom (see the addon's engineering notes' local-ceiling note).
local function anyItemArmed()
  local imp = GC.db and GC.db.imported
  local verification = imp and imp.verification
  if not verification then return false end
  local sniperSettings = GC.db.settings and GC.db.settings.sniper
  if not sniperSettings then return false end
  local minimumProfitCopper = sniperSettings.minimumProfitCopper
  local minimumRoi = sniperSettings.minimumRoi
  local cache = GC.Sniper._armedCache
  if cache and cache.verification == verification
      and cache.minimumProfitCopper == minimumProfitCopper and cache.minimumRoi == minimumRoi then
    return cache.result
  end
  local ids = {}
  for itemID in pairs(verification) do ids[#ids + 1] = itemID end
  local result = GC.Trigger.AnyArmed(ids, GC.Data.GetItemValue, sniperSettings)
  GC.Sniper._armedCache = { verification = verification, minimumProfitCopper = minimumProfitCopper,
    minimumRoi = minimumRoi, result = result }
  return result
end

-- The board's empty state. An empty list used to be exactly that -- rows silently absent,
-- with the only explanations living in a toolbar counter and a scan-completion status line
-- that the next write erased. That is the TSM failure mode this addon exists to avoid: the
-- filters work, and the player concludes the sniper is broken. When nothing renders, say WHY
-- nothing renders, in the space where the rows would be, picking the dominant cause: no realm
-- import (nothing can pass the safety pre-screen without one), everything filtered/refused
-- (with the counts and where to review them), or genuinely nothing scanned yet.
-- Exposed on GC.Sniper (not a local) so the spec suite can drive it directly.
--
-- Two boards, two empty states. Everything below the import branch is the COMMODITIES board's
-- story (the pre-screen, the refusals, "press Scan") and none of it is true of the Items
-- board, which no scan fills and no pre-screen empties -- it is the key poll's, and the only
-- two things that can leave it blank are having nothing to poll and nothing being cheap.
function GC.Sniper._UpdateEmptyState(shownCount)
  local label = frame and frame.emptyText
  if not label then return end
  local board = GC.Sniper._Board()
  -- The paging guard is the commodity scan's: it exists so a board that is mid-refill does not
  -- flash an explanation of its own emptiness. A pass says nothing about the Items board, so it
  -- must not silence it either.
  if shownCount > 0 or view ~= "deals"
      or (board == "commodities" and GC.Sniper._bookPass:IsPaging()) then
    label:Hide()
    return
  end
  local screened = GC.Sniper._screenedCount or 0
  local text
  if board == "items" and GC.Data.OriginState() ~= "none" then
    -- Count(), not the store: an empty poll set means the import carries no region reference
    -- for anything this board could watch, which is a different problem from a full poll set
    -- finding nothing cheap, and needs a different answer.
    if GC.Sniper._keyPoll:Count() == 0 then
      text = GC.L["Nothing to watch on this board yet."] .. "\n"
        .. GC.L["Gear, pets and recipes need an import that carries the region's prices for them -- paste a fresh string from goldcap.gg."]
    else
      text = GC.L["No gear, pets or recipes under their region price right now."] .. "\n"
        .. GC.L["GoldCap keeps checking them while this board is open."]
    end
  elseif GC.Data.OriginState() == "none" then
    -- A companion that is syncing into an addon that cannot read what it writes looks
    -- exactly like a companion that is not running. Say which one it is -- but only here,
    -- where there are no prices at all: a player who already has a working import is
    -- better served by the filtered/refused counts below, and hears about the failed sync
    -- in chat and in /goldcap status.
    local appErr = GC.Data.AppDataError and GC.Data.AppDataError()
    if appErr then
      text = GC.L["The Companion is syncing, but this addon could not read what it wrote:"] .. "\n"
        .. GC.Data.DescribeImportError(appErr.reason) .. "."
    else
      text = GC.L["No deals to show -- and no realm prices yet."] .. "\n"
        .. GC.L["Install the free GoldCap Companion to keep prices fresh automatically (/goldcap companion),"] .. "\n"
        .. GC.L["or paste a string from goldcap.gg with /goldcap import."]
    end
  elseif not anyItemArmed() then
    text = GC.L["Import from goldcap.gg to arm the sniper"]
  elseif refusedCount > 0 or screened > 0 then
    local parts = {}
    if screened > 0 then
      parts[#parts + 1] = GC.L["%d filtered out as hard to resell"]:format(screened)
    end
    if refusedCount > 0 then
      parts[#parts + 1] = (GC.L["%d refused by live checks -- press \"HIDDEN %d\" above to review them"]):format(
        refusedCount, refusedCount)
    end
    text = GC.L["No deals passed the safety checks right now."] .. "\n" .. table.concat(parts, "\n")
  else
    text = GC.L["No deals yet."] .. "\n"
      .. GC.L["Press Scan to search the whole auction house once, or Auto to keep scanning."]
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
    local msg = (GC.L["your import is %d hours old -- prices may be off. Paste a fresh string from goldcap.gg (/goldcap import)."]):format(math.floor(age / 3600))
    -- Only for a manual paste: app-synced data is already the Companion's own output, so
    -- telling the player to go get the Companion would be nonsensical there.
    if GC.Data.OriginState() == "manual" then
      msg = msg .. GC.L[" Companion keeps this fresh: /goldcap companion."]
    end
    GC.Print(msg)
  else
    GC.Print(GC.L["you haven't imported realm prices yet -- install GoldCap Companion (/goldcap companion) or paste a string from goldcap.gg (/goldcap import)."])
  end
end

-- The decision engine owns every purchase-safety judgement. Keep the raw Data shape at this
-- one boundary so a UI caller cannot accidentally make a tier/profit calculation authoritative.
local function marketForDecision(itemID)
  -- One mapping, in SniperDecision, shared with the scan's pre-screen: a second copy here
  -- would drift the first time a field is renamed on the import side.
  return GC.SniperDecision.MarketFromValue(GC.Data.GetItemValue(itemID))
end

-- The deposit the decision subtracts from the projected profit is the deposit the player will
-- actually pay, which depends on how long they list for: settings.sniper.postDuration (1 = 12h,
-- 2 = 24h, 3 = 48h), the very setting UI/SellFrame.lua's own postDuration() posts at. This was
-- hardcoded to 24h, so a player selling at 48h was quoted a cheaper deposit than the resale
-- costs. Same "anything that is not exactly one of the three falls back to 2" contract as the
-- Sell tab's reader -- a hand-edited value must never reach the API.
local function depositFor(itemID, quantity)
  local settings = GC.db and GC.db.settings and GC.db.settings.sniper
  local duration = settings and settings.postDuration
  if duration ~= 1 and duration ~= 2 and duration ~= 3 then duration = 2 end
  return C_AuctionHouse.CalculateCommodityDeposit(itemID, duration, quantity)
end

-- How many units of one commodity price level belong to the player. A commodity result is a
-- whole price point aggregated across every seller, and the player's own stock sits inside it:
-- C_AuctionHouse.GetCommoditySearchResultInfo reports `numOwnerItems` (and `containsOwnerItem`)
-- beside the total for exactly this reason. A level with no count but the flag set cannot be
-- split, so the whole level counts as the player's own -- on the buy side that errs towards
-- seeing LESS stock than there is, which refuses a fill rather than planning one that cannot
-- happen.
local function ownedUnits(info)
  if type(info.numOwnerItems) == "number" then return info.numOwnerItems end
  if info.containsOwnerItem == true then return info.quantity or 0 end
  return 0
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
  -- The Items board is a second store, not a second window on this one (0.9.2), so a realm
  -- item's current row lives only there. This answers "what does the board say about this item
  -- right now" for the purchase paths and the specs alike, and a realm lot is bought through
  -- the same flow a commodity is -- the answer must not depend on which chip is lit.
  return (GC.Sniper._realmDeals or {})[itemID]
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
    -- GC.Util.ThrottleReady, not the raw flag: see its comment for the stuck-flag client.
    -- (The raw flag remains for specs that load this file without Core/Util.lua.)
    if GC.Util and GC.Util.ThrottleReady then return GC.Util.ThrottleReady() end
    return C_AuctionHouse.IsThrottledMessageSystemReady()
  end,

  -- The other half of that read, and the one with a cost: isReady answers whether a send is
  -- permitted, this takes the permit. Asked once, immediately before a query actually goes out,
  -- so that under a throttle flag which has stopped changing this addon paces itself at one
  -- send per window per consumer -- and the Sell tab's pricing walk, which claims under its own
  -- name, still gets windows of its own. An absent claimSend means "no pacing", the same
  -- contract an absent mayScan carries above.
  claimSend = function()
    if GC.Util and GC.Util.ClaimThrottleSend then return GC.Util.ClaimThrottleSend("sniper") end
    return true
  end,

  mayScan = function()
    -- Shared throttle budget: while the player is busy on Blizzard's own AH panes -- posting,
    -- buying a browse result, or reading their own search -- their click outranks every
    -- watch-loop poll.
    if GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy and GC.AuctionHouseTab.PlayerIsBusy() then
      return false
    end
    -- Same quiet-zone veto as GC.Sniper.OnThrottleReady. That arbiter already refuses
    -- to hand the watch loop a grant while a purchase is in flight, so this is normally
    -- redundant -- but advance() (Core/Scanner.lua) is the one choke point every send passes
    -- through, including the result-handler tail that fires straight from an event, off the
    -- arbiter's own call stack. Checked here too so the veto holds even if that tail ever runs
    -- with a stale watchGrant.
    if GC.Sniper.IsPurchaseQuiet() then return false end
    return watchGrant
  end,

  getKeyInfo = function(itemID)
    -- Nil-safe: renderList now asks this for every board row (see _VerifySlice), and the
    -- specs that render a board without the AH API stub nothing here. Unknown is nil, the
    -- same answer an uncached key gives in the client.
    if not C_AuctionHouse then return nil end
    return C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
  end,

  sendSearch = function(itemID)
    trace("search: item " .. tostring(itemID))
    local key = C_AuctionHouse.MakeItemKey(itemID)
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    -- Blizzard's pane may open this item's buy page in answer; that page is ours, not a buy.
    if GC.AuctionHouseTab and GC.AuctionHouseTab.NoteAddonSearch then GC.AuctionHouseTab.NoteAddonSearch() end
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
    -- Level 1 is read FIRST and for one reason only: it is the probe. A nil here means the
    -- client's single commodity buffer holds something else entirely, and several callers rely
    -- on exactly that to tell "this item's book" from "whatever the last search left behind".
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    if not info then return nil end
    -- Fix 1: info.quantity above is only level 1's own stock (what a purchase quote is built
    -- from) -- `avail` is the market's real depth, summed across every fetched price level, so
    -- the row/dialog can show "x<qty> of <avail>" instead of implying the level-1 quantity is
    -- all there is. Same bounded LIM.MAX_BOOK_LEVELS idiom driver.commodityBook uses below, kept as
    -- its own small loop rather than calling commodityBook itself: this only needs a running
    -- total, not the per-level array GC.Book.Fill consumes.
    local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID)
    local avail, unitPrice, qty
    if n and n > 0 then
      if n > LIM.MAX_BOOK_LEVELS then n = LIM.MAX_BOOK_LEVELS end
      avail = 0
      for i = 1, n do
        local levelInfo = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if levelInfo and levelInfo.quantity then
          -- Minus the player's own units: "how much is out there" means how much is out there
          -- to BUY, and nobody can buy their own auction. Same subtraction the sell side makes
          -- in GC.SellPositions.CheapestCompetingUnit, from the same two API fields.
          local competing = math.max(0, levelInfo.quantity - ownedUnits(levelInfo))
          avail = avail + competing
          -- And the price is the cheapest level with something left on it after that
          -- subtraction, not level 1 blind. Level 1 is the player's own auction the moment they
          -- are the cheapest seller -- so an item the player owned the whole book of kept
          -- turning up on the board as its own deal, undercutting itself, priced against
          -- nobody. Same rule, same reason, as the Sell tab's CheapestCompetingUnit and as
          -- driver.commodityBook right below.
          if competing > 0 and not unitPrice then
            unitPrice, qty = levelInfo.unitPrice, competing
          end
        end
      end
    end
    -- Nothing on offer but the player's own units: there is no price here to act on, and
    -- saying so is what keeps the board from advertising the player their own stock.
    if not unitPrice then return nil end
    return { unitPrice = unitPrice, qty = qty, avail = avail }
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
        -- The player's own units are not part of this book. They cannot be bought, so a plan
        -- built on them fills from stock that will never be sold to the player; and the resale
        -- exit is anchored one copper under the cheapest ask left standing, which on a level of
        -- the player's own means undercutting their own auction. Levels that are entirely the
        -- player's own drop out.
        local quantity = (info.quantity or 0) - ownedUnits(info)
        if quantity > 0 then
          levels[#levels + 1] = { unitPrice = info.unitPrice, quantity = quantity }
        end
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

  -- Every lot currently listed for a realm item, from results the drill's own SendSearchQuery
  -- has already landed -- this never issues a query of its own, exactly like commodityBook.
  -- buyoutAmount is the whole lot's price (see itemResult above), and it is left that way:
  -- GC.SniperDecision.EvaluateRealm compares lots to each other and to a reference, and
  -- dividing here would only invent a per-unit price for a lot that cannot be split.
  --
  -- The player's own listings are skipped. Buying one is impossible, and letting one become
  -- the "cheapest comparable lot" would have the addon offer the player their own auction.
  itemLots = function(itemID)
    local key = C_AuctionHouse.MakeItemKey(itemID)
    local n = C_AuctionHouse.GetNumItemSearchResults(key)
    if not n or n <= 0 then return {} end
    if n > LIM.MAX_BOOK_LEVELS then n = LIM.MAX_BOOK_LEVELS end
    local lots = {}
    for i = 1, n do
      local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
      if info and info.auctionID and info.buyoutAmount and info.buyoutAmount > 0
          and not info.containsOwnerItem then
        lots[#lots + 1] = {
          auctionID = info.auctionID,
          buyout = info.buyoutAmount,
          -- The variant's own item level, which is the whole reason a realm item needs its
          -- own decision path: two lots of "the same" item can be twenty levels apart.
          itemLevel = info.itemKey and info.itemKey.itemLevel or 0,
          quantity = info.quantity or 1,
        }
      end
    end
    return lots
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
        resolvePurchase(staleRow, true, GC.L["sniped (listing changed on rescan)"])
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
    -- A realm item never joins the commodity board, whoever found it. The watch loop polls
    -- whatever the watch set holds -- pins included, and a pin may well be gear -- and its
    -- deal is measured against GC.Data.GetItemValue, this realm's own median, not the region
    -- reference the Items board prices realm rows by (GC.Sniper._RealmValue). Letting one
    -- through here would put a row on Commodities that the two-board split exists to keep off
    -- it, wearing a discount measured the way Core/DealMath.lua's own comment calls noise.
    -- The observation is not wasted: the verdict below still lands, and lastSeenPrice still
    -- records what the item costs right now, which is what a pin placeholder shows.
    local realmItem = GC.Sniper._RealmValue and GC.Sniper._RealmValue(itemID) ~= nil
    -- Built once and threaded through below (to evaluateLiveCommodityDeal and to the
    -- observation recorder) instead of letting each ask driver.commodityBook for its own copy
    -- of the same already-fetched poll.
    local book = driver.commodityBook(itemID)
    -- Live price caps, addon task 5 fix: the plain `deal` parameter is whatever the watch loop
    -- already measured against the MARKET (GC.DealMath.Evaluate) -- nil for exactly the item a
    -- cap exists to rescue, since GC.Caps.For needs no market reference to fire (Core/Caps.lua's
    -- own contract). Writing that nil straight into the board, unconditionally, deleted a
    -- capped commodity's row every single cycle it had no market-side deal of its own. Run the
    -- cap-aware evaluation FIRST when a cap exists, regardless of `deal` -- it already
    -- merges/refreshes the board deal itself when the cap decision is non-nil (see
    -- evaluateLiveCommodityDeal above) -- and only fall back to the plain write/removal below
    -- when this cycle's cap decision came back nil (no cap, the book emptied, or the floor
    -- climbed back above it), exactly as before.
    local capLive
    if not realmItem then
      local cap = GC.Caps and GC.Caps.For(itemID)
      if cap then
        capLive = evaluateLiveCommodityDeal(itemID, book)
      end
      if not (capLive and capLive.decision and capLive.decision.cap) then
        if GC.Sniper._liveTracksScanDeals then
          scanDeals = GC.FullScan.ApplyLiveObservation(scanDeals, itemID, deal, WIN.ROW_CAP)
        else
          deals[itemID] = deal
        end
      end
    end
    -- The poll has just pulled this item's live book, which is exactly what a verdict is
    -- computed from -- so compute it here, for nothing. A watched item therefore never costs
    -- tickAutoVerify a query, and the ring it may produce goes through the one shared
    -- transition path rather than a second notion of "buyable". Reuses `capLive` when the cap
    -- branch above already computed it, rather than asking the decision engine twice.
    if deal and GC.Sniper._IsWatched(itemID) then
      stampVerdict(deal, capLive or evaluateLiveCommodityDeal(itemID, book))
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
  if ahOpen and not scanning and not GC.Sniper._bookPass:IsPaging() and autoScan:State() == "OFF" then
    GC.Sniper._ResumeLiveScanner()
  end
end

function GC.Sniper._FinishDrainWait(itemID, draining)
  local wait = GC.Sniper._drainWaitRequery[itemID]
  if not wait or wait.draining ~= draining then return end
  GC.Sniper._drainWaitRequery[itemID] = nil
  -- The same retirement finishRequery performs for a requery that DID start: a cancelled,
  -- unconfirmed purchase left a tombstone fenced on this wait, and the wait is now over.
  GC.Sniper._RetireFencedTombstone(wait.row, wait.token)
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
pingNewHotDeals = function(newHotDeals)
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

-- `kind` is the book pass's own "wide" or "classes" (Core/BookPass.lua's onPassDone) -- the
-- difference matters twice below: what the status line may honestly claim to have looked at,
-- and whether a deal this pass did not report is a deal that is GONE or merely one this pass
-- could not see.
local function applyFullScanResults(rowsList, groupCount, kind)
  local screened
  scanDeals, screened = GC.FullScan.Evaluate(rowsList, GC.Data.GetItemValue, GC.db.settings.sniper, 100)
  GC.Sniper._screenedCount = screened or 0
  -- A classes pass browses four item classes; the wide pass browses everything. Replacing the
  -- board wholesale from a classes pass therefore DELETED every out-of-class find the last
  -- wide pass made -- a BoE the sniper flagged vanished a few seconds later, with nothing
  -- having disproved it, and came back only on the next wide pass minutes away. So the wide
  -- pass's own deals are kept aside, and after a classes pass the ones that pass did not even
  -- LOOK at (no browse row for that item) are merged back in. Anything the classes pass did
  -- look at and no longer reports really is gone, and stays gone. A table field, not a new
  -- top-level local: this file is at its 200-local ceiling (see the addon's engineering notes).
  if kind == "wide" then
    -- Only the genuinely out-of-class finds are worth holding past this pass. An item a
    -- classes pass has ever folded (GC.Sniper._bookPass:SeenByClasses) is in-class by
    -- definition -- carrying it here would let it get resurrected from _wideExtras later even
    -- after it sells out, instead of a classes pass's silence about it being trusted as "gone".
    local extras = {}
    for _, deal in ipairs(scanDeals) do
      if not GC.Sniper._bookPass:SeenByClasses(deal.itemID) then extras[deal.itemID] = deal end
    end
    GC.Sniper._wideExtras = extras
  elseif GC.Sniper._wideExtras then
    local seen = {}
    for _, row in ipairs(rowsList) do seen[row.itemID] = true end
    local carried = {}
    for itemID, deal in pairs(GC.Sniper._wideExtras) do
      -- "This pass did not see it" is not enough to keep an extra alive: an item this pass
      -- did not report a row for but that IS in-class (SeenByClasses, from this or an earlier
      -- classes pass) has genuinely sold out, not merely gone unmentioned -- carrying it would
      -- resurrect it from the wide pass for up to widePassSeconds.
      if not seen[itemID] and not GC.Sniper._bookPass:SeenByClasses(itemID) then
        carried[#carried + 1] = deal
      end
    end
    if #carried > 0 then scanDeals = GC.FullScan.MergeDeals(scanDeals, carried, 100) end
  end
  -- No realm rows are folded in here, and that is the whole of the two-board split (0.9.2).
  -- They used to be: the key poll's store was merged over this list on every completed pass,
  -- which is how gear, pets and recipes came to share one hundred-row cap and one profit sort
  -- with the commodities -- and, being worth five figures apiece, to take the board. They live
  -- on GC.Sniper._realmDeals alone now, which is the Items board's own store; scanDeals is
  -- commodities only. (The pass never produces a realm row of its own: the wide pass's own row
  -- for one is screened out for having no sell-through, velocity or liquidity facts, and a
  -- classes pass never browses one at all.)
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
      and (GC.L[", %d hidden as unsellable"]):format(GC.Sniper._screenedCount) or ""
    -- Sniper phase 2: what the realm-item poll asked about during the cycle that just ended,
    -- appended to the SAME trailing slot the hidden count uses. Both sentences below already
    -- end in a "%s" for it, and adding a second specifier would reword the key -- which
    -- orphans every translation of it, silently, back to English.
    if (GC.Sniper._keysLastCycle or 0) > 0 then
      hidden = hidden .. (GC.L[" · %d keys"]):format(GC.Sniper._keysLastCycle)
    end
    -- setStatus, not SetText: under Auto this recurs every few seconds, so losing one to a
    -- held announcement costs nothing -- the next pass rewrites it.
    -- Two sentences, because the two passes looked at different markets and only one of them
    -- looked at all of them. A classes pass that reported "full scan complete" was claiming to
    -- have swept an auction house it never asked about.
    if kind == "classes" then
      setStatus((GC.L["scan complete: %d deal%s from %d item%s in reagents, consumables, gems, enchants%s"]):format(
        #scanDeals, #scanDeals == 1 and "" or "s", groupCount, groupCount == 1 and "" or "s", hidden))
    else
      setStatus((GC.L["full scan complete: %d deal%s from %d item group%s%s"]):format(
        #scanDeals, #scanDeals == 1 and "" or "s", groupCount, groupCount == 1 and "" or "s", hidden))
    end
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
  streamRows, streamRowsCount = {}, 0
  -- Live price caps, addon task 4: a capped commodity whose floor THIS pass's own book shows
  -- at or under the player's cap goes straight to the drill queue, same priority = 1, cap =
  -- true the key poll's onHit already gives a capped realm item below -- the book pass is the
  -- only place a commodity floor is ever seen (commodities are excluded from the key poll's
  -- own target set, see _KeyTargetIds's isCommodity guard). DrillQueue's itemID:floor dedup
  -- means an unchanged floor does not re-drill on every pass. driver.getKeyInfo answers nil for
  -- an item key the client hasn't cached yet; treated as "not a commodity (yet)" rather than
  -- guessed -- a later pass, once the key resolves, picks it up.
  if GC.Caps then
    local hits = GC.Caps.BookHits(GC.Sniper._bookPass:Book(), function(itemID)
      local info = driver.getKeyInfo(itemID)
      return info ~= nil and info.isCommodity == true
    end)
    for _, hit in ipairs(hits) do
      GC.Sniper._drillQueue:Push({ itemID = hit.itemID, floor = hit.floor,
        estProfit = hit.estProfit, priority = 1, cap = true })
    end
  end
  -- Sniper v3 §3: tells AutoScan the scan it started (if it was the one that started this
  -- one) is done, so it can start its breather countdown toward the next pass. A no-op
  -- whenever the machine's own state isn't SCANNING -- e.g. a manual "Scan" click while Auto
  -- is off/paused -- see AutoScan.lua's onScanFinished.
  feedAuto("scanFinished")
  -- The settled buffer the Items board's keys batch needs -- see _TrySendKeysBatch.
  GC.Sniper._TrySendKeysBatch()
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
    and (GC.L["watching %s closely -- re-checked every few seconds"]):format(name)
    or (GC.L["stopped watching %s"]):format(name), 4)
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
      GC.Sniper._RebuildKeyTargets()
      refreshRows()
      repaintToggledRow(itemID)
      announcePin(itemID, false)
      return
    end
  end
  cfg.watchPins[#cfg.watchPins + 1] = itemID
  GC.Sniper._RefreshWatchSet()
  -- A pinned realm item joins the key poll's set (and an unpinned one leaves it, above): a pin
  -- is a standing instruction to watch, and the poll is what watching a realm item means now.
  GC.Sniper._RebuildKeyTargets()
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
    if token ~= fullScanToken or not GC.Sniper._bookPass:IsPaging() then return end -- superseded, aborted, or already finished
    if lastBrowseEventAt < sentAt then
      GC.Sniper._bookPass:Abort()
      if frame then
        -- (fix round 1, M6) "press Full Scan to retry" is dead advice while Auto is armed --
        -- the feedAuto("scanFinished") below already queues its own breather-delayed retry,
        -- and the very next Tick/refreshAutoButton call would immediately overwrite a
        -- "press Full Scan" line with "AUTO · SCANNING" anyway. Pick the text off the
        -- machine's OWN state (read before feeding scanFinished moves it along).
        if autoScan and autoScan:State() ~= "OFF" then
          frame.status:SetText(GC.L["full scan stalled -- retrying shortly"])
        else
          frame.status:SetText(GC.L["full scan stalled -- press Full Scan to retry"])
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

GC.Sniper._drillQueue = GC.DrillQueue.New({ now = time }, { perMinute = LIM.DRILL_PER_MINUTE })

-- No isReady in this driver: the pass never decides for itself whether the throttled system
-- is ready, because it never sends on its own initiative. Both of its sends happen inside
-- GC.Sniper.OnThrottleReady, where readiness is the event's own premise.
GC.Sniper._bookPass = GC.BookPass.New({
  now = time,
  sendBrowseQuery = function(query)
    trace("pass: SendBrowseQuery")
    C_AuctionHouse.SendBrowseQuery(query)
    if frame then frame.status:SetText(GC.L["scanning auction house..."]) end
    armScanWatchdog(fullScanToken)
  end,
  requestMoreBrowseResults = function()
    trace("pass: RequestMoreBrowseResults")
    C_AuctionHouse.RequestMoreBrowseResults()
    armScanWatchdog(fullScanToken)
  end,
  hasFullBrowseResults = function() return C_AuctionHouse.HasFullBrowseResults() end,
  getBrowseResults = function() return C_AuctionHouse.GetBrowseResults() end,
  triggerFor = function(itemID)
    return GC.Trigger.For(GC.Data.GetItemValue(itemID), GC.db.settings.sniper)
  end,
  -- Scores a hit the SAME way discovery already scores a browse row (Core/FullScan.lua's
  -- own RowsFromBrowse + DealMath.Evaluate pipeline), so the drill queue's priority mirrors
  -- what a live Check would approve, not just how far under mv the floor sits.
  onHit = function(hit)
    -- The same pre-screen Core/FullScan.lua applies before DealMath.Evaluate. Without it the
    -- queue spent its budget verifying rows discovery would never have put on the board:
    -- markets whose sell-through, velocity or liquidity already rule them out need no order
    -- book to refuse, and a live query cannot change any of those answers.
    local value = GC.Data.GetItemValue(hit.itemID)
    local blocked = GC.SniperDecision and GC.SniperDecision.PreScreen
      and GC.SniperDecision.PreScreen(GC.SniperDecision.MarketFromValue(value), GC.db.settings.sniper) or {}
    if #blocked > 0 then return end
    local hitRows = GC.FullScan.RowsFromBrowse(
      { { itemKey = { itemID = hit.itemID }, minPrice = hit.floor, totalQuantity = hit.qty } },
      GC.Data.GetItemValue, GC.db.settings.sniper)
    local row, estProfit = hitRows[1], 0
    if row then
      local deal = GC.DealMath.Evaluate(
        { itemID = row.itemID, isCommodity = false,
          unitPrice = math.floor(row.buyoutStack / row.count), qty = row.count, avail = row.avail },
        GC.Data.GetItemValue(hit.itemID), GC.db.settings.sniper)
      if deal then estProfit = deal.estProfit end
    end
    GC.Sniper._drillQueue:Push({ itemID = hit.itemID, floor = hit.floor, estProfit = estProfit })
  end,
  -- Exactly today's streaming pipeline (evaluate the new tail, merge, refresh, ping, status),
  -- just triggered from BookPass's own tail instead of from a raw browse event handler.
  onRows = function(tail, totalRawSeen)
    local tailRows = GC.FullScan.RowsFromBrowse(tail, GC.Data.GetItemValue, GC.db.settings.sniper)
    for _, row in ipairs(tailRows) do streamRows[#streamRows + 1] = row end
    local deltaDeals, newRowsCount, deltaScreened = GC.FullScan.EvaluateDelta(
      streamRows, streamRowsCount, GC.Data.GetItemValue, GC.db.settings.sniper)
    streamRowsCount = newRowsCount
    GC.Sniper._screenedCount = (GC.Sniper._screenedCount or 0) + (deltaScreened or 0)
    for _, deal in ipairs(deltaDeals) do deal.stale = true end
    local pingDeals = GC.FullScan.CollectNewHot(deltaDeals, seenHotDeals)
    GC.Sniper._churnSeq = GC.Sniper._churnSeq + 1
    GC.WatchSet.Observe(GC.Sniper._churn, deltaDeals, GC.Sniper._churnSeq)
    GC.Sniper._RefreshWatchSet()
    scanDeals = GC.FullScan.MergeDeals(scanDeals, deltaDeals, 100)
    refreshRows()
    if #pingDeals > 0 then pingNewHotDeals(pingDeals) end
    local screenedNote = (GC.Sniper._screenedCount or 0) > 0
      and (GC.L[" · %d hidden"]):format(GC.Sniper._screenedCount) or ""
    setStatus((GC.L["scanning… %d results · %d deals%s"]):format(
      totalRawSeen, #scanDeals, screenedNote))
  end,
  onPassDone = function(info)
    applyFullScanResults(streamRows, info.items, info.kind)
  end,
}, {
  widePassSeconds = LIM.WIDE_PASS_SECONDS,
  -- Same Enum-with-numeric-fallback trick as the (unshipped) Spike.lua measurement spike:
  -- an inline IIFE, not a named local -- this file is at its 200-local ceiling.
  itemClassFilters = (function()
    local ok, ids = pcall(function()
      return { Enum.ItemClass.Tradegoods, Enum.ItemClass.Consumable,
        Enum.ItemClass.Gem, Enum.ItemClass.ItemEnhancement }
    end)
    if not (ok and ids[1] and ids[2] and ids[3] and ids[4]) then ids = { 7, 0, 3, 8 } end
    local filters = {}
    for i = 1, #ids do filters[i] = { classID = ids[i] } end
    return filters
  end)(),
})

-- Sniper phase 2. The one rule for "what is a realm item worth here": the region reference
-- from the import's T section and this realm's own median from its I section, whichever is
-- lower (Core/Trigger.lua's RealmReference), presented as an ordinary value table so the
-- board's existing pipeline -- RowsFromBrowse, DealMath.Evaluate -- can score the row without
-- knowing anything new. nil for everything that is not a realm item with an IMPORTED
-- reference: a commodity (the book pass's job, and it has a V fact to be judged by), and
-- bundled sample data, which is not this realm's median and must not be treated as one.
function GC.Sniper._RealmValue(itemID)
  -- Guarded rather than assumed: this runs from the row tooltip and from the poll's own
  -- driver, both of which are reachable before (and, in the specs, without) the data and
  -- trigger modules being present. No data layer means no reference, which means no poll.
  if not (GC.Data and GC.Data.GetItemValue and GC.Trigger) then return nil end
  local value = GC.Data.GetItemValue(itemID)
  if not value or value.source ~= "import" or value.kind == "region_commodity" then return nil end
  local reference = GC.Trigger.RealmReference(value)
  if not reference then return nil end
  return { mv = reference, ts = value.ts, source = value.source, kind = "realm_item",
    trend = value.trend, ref = value.ref, refIlvl = value.refIlvl }
end

-- Whether this item is a realm item the region has published no price for -- the state that
-- keeps it off the board entirely (Core/DealMath.lua) and that only a pin can put in front of
-- the player. Read by the row tooltip; the Check panel gets the same answer from
-- GC.SniperDecision.EvaluateRealm's own realm_no_reference verdict.
function GC.Sniper._RealmNeedsReference(itemID)
  if not (GC.Data and GC.Data.GetItemValue) then return false end
  local value = GC.Data.GetItemValue(itemID)
  return (value and value.kind == "realm_item" and not value.ref) and true or false
end

-- Pure: which realm item ids the key poll watches, caps first. A capped item is the player's
-- own price (GC.Caps.For), so it needs no realm reference to be watched -- everything after it
-- does. Exposed for the spec (spec/caps_targets_spec.lua).
function GC.Sniper._KeyTargetIds(caps, pins, watchlist, targets, isCommodity, hasRealmValue)
  local ids, seen = {}, {}
  local function add(itemID, needsValue)
    if type(itemID) ~= "number" or seen[itemID] then return end
    if isCommodity(itemID) then return end
    if needsValue and not hasRealmValue(itemID) then return end
    seen[itemID] = true
    ids[#ids + 1] = itemID
  end
  for _, itemID in ipairs(caps) do add(itemID, false) end
  for _, itemID in ipairs(pins) do add(itemID, true) end
  for _, itemID in ipairs(watchlist) do add(itemID, true) end
  for _, itemID in ipairs(targets) do add(itemID, true) end
  return ids
end

-- The poll set: capped items first (see _KeyTargetIds), then the player's pins, the site
-- watchlist the import carried (W section) and the region's own list of realm items worth
-- watching (T section), realm items only. GetWatchlist(0) is deliberate -- with a zero fallback
-- it answers with the W section or nothing, never the top-N-by-value list it otherwise invents,
-- which is not a watchlist and has no business being polled. A commodity the Sell tab has
-- already classified is left out (the book pass sweeps those); an item nobody has classified is
-- polled and answers for itself.
--
-- Called when the set can actually have changed -- AH open, a pin toggle, a fresh import, a
-- caps adoption -- and never per page: SetTargets no-ops on an unchanged set, so a rebuild that
-- finds nothing new leaves a half-finished cycle exactly where it was.
function GC.Sniper._RebuildKeyTargets()
  local commodities = GC.db and GC.db.commodityByItem or {}
  local data = GC.Data or {}
  GC.Sniper._keyPoll:SetTargets(GC.Sniper._KeyTargetIds(
    GC.Caps and GC.Caps.Targets() or {},
    GC.Sniper._WatchPins(),
    data.GetWatchlist and data.GetWatchlist(0) or {},
    data.TargetIds and data.TargetIds() or {},
    function(id) return commodities[id] == true end,
    function(id) return GC.Sniper._RealmValue(id) ~= nil end))
end

-- The realm-item poll (Core/KeyPoll.lua), built beside the book pass above and driven from the
-- same arbiter. A keys call REPLACES the browse buffer, so it only ever runs between passes --
-- see GC.Sniper.OnThrottleReady.
GC.Sniper._keyPoll = GC.KeyPoll.New({
  now = time,
  -- The wider of the two triggers: a capped item polls at its own cap as well as (not
  -- instead of) its realm reference, so a price drop past either one wakes the poll.
  triggerFor = function(itemID)
    local value = GC.Sniper._RealmValue(itemID)
    local realm = value and GC.Trigger.ForRealm(value.mv, GC.db.settings.sniper) or nil
    local cap = GC.Caps and GC.Caps.TriggerFor(itemID) or nil
    if realm and cap then return math.max(realm, cap) end
    return realm or cap
  end,
  -- Same queue, same currency as a book-pass hit: what the lot would clear after the auction
  -- house's 5% cut, measured against the reference (Core/DrillQueue.lua sorts by it). A hit at
  -- or under the player's own cap is checked first, regardless of estProfit -- see
  -- Core/DrillQueue.lua's ranksBelow.
  onHit = function(hit)
    local cap = GC.Caps and GC.Caps.For(hit.itemID) or nil
    if cap and hit.floor <= cap.c then
      -- The player's own price: verify first in line, the saving is the profit estimate.
      GC.Sniper._drillQueue:Push({ itemID = hit.itemID, floor = hit.floor,
        estProfit = cap.c - hit.floor, priority = 1, cap = true })
      return
    end
    local value = GC.Sniper._RealmValue(hit.itemID)
    if not value then return end
    GC.Sniper._drillQueue:Push({ itemID = hit.itemID, floor = hit.floor,
      estProfit = math.floor(value.mv * 0.95) - hit.floor })
  end,
  -- Keys rows are browse rows: the same aggregate-per-itemKey shape a pass page produces, so
  -- they go through the same RowsFromBrowse -> DealMath path, with the realm reference
  -- standing in for the market value. NOT through FullScan.Evaluate, deliberately:
  -- its pre-screen refuses anything without sell-through, velocity and liquidity facts, and a
  -- realm item has none of the three by definition -- that screen is what a realm item is
  -- being rescued FROM here, and the row says "unverified" instead of pretending otherwise.
  onRows = function(results)
    local realmRows = GC.FullScan.RowsFromBrowse(results, GC.Sniper._RealmValue, GC.db.settings.sniper)
    local fresh, qualified, floorOf = {}, {}, {}
    for i = 1, #realmRows do
      local row = realmRows[i]
      -- Live price caps, addon task 5 fix: this batch's own floor for the item, kept regardless
      -- of whether it goes on to qualify as an ordinary deal below -- the null-out pass past the
      -- end of this loop reads it to judge a CAP row on its own terms (the cap needs no realm
      -- value at all, so an ordinary deal here will often be nil for exactly the item a cap
      -- exists to rescue).
      local unitPrice = math.floor(row.buyoutStack / row.count)
      floorOf[row.itemID] = unitPrice
      local value = GC.Sniper._RealmValue(row.itemID)
      local deal = value and GC.DealMath.Evaluate(
        { itemID = row.itemID, isCommodity = false,
          unitPrice = unitPrice, qty = row.count, avail = row.avail },
        value, GC.db.settings.sniper) or nil
      if deal then
        -- An aggregate across every seller, exactly like a browse row: no auctionID, no
        -- resolved lot, nothing to buy from. Stale until a live drill resolves it.
        deal.stale = true
        deal.status = "WATCH"
        deal.reason = "realm_item_unverified"
        deal.action = "Check"
        deal.buyable = false
        fresh[#fresh + 1] = deal
        qualified[row.itemID] = true
      end
    end
    -- GC.Sniper._realmDeals IS the Items board (0.9.2) -- not a copy kept beside the
    -- commodity one to survive a pass, which is what it was while the two shared a list.
    -- Nothing here writes to scanDeals any more: a realm row belongs to the board built for
    -- it, and the commodity board's hundred rows are the commodity scan's again.
    local asked = GC.Sniper._keysBatch
    GC.Sniper._keysBatch = nil
    if asked then
      -- This batch asked about these items by name, so its silence about one is an answer:
      -- sold out, or repriced back above the trigger. Either way it leaves the board with the
      -- batch that found out, rather than sitting there until something else happens to
      -- disprove it.
      for i = 1, #asked do
        local itemID = asked[i]
        if not qualified[itemID] then
          -- A CAP row gets a second life an ordinary deal does not: it needs no realm value to
          -- exist (GC.Caps.For's own contract, Core/Caps.lua), so `qualified` above -- which
          -- only ever fires off a REAL GC.DealMath.Evaluate against a realm/region value -- is
          -- silent about it by construction, not because the cap has stopped clearing. Keep it
          -- as long as this batch's own floor is still at or under the cap; only a floor that
          -- climbed back above it, or the id vanishing from the results entirely (no entry in
          -- `floorOf`), removes it -- same as an ordinary deal's silence always has.
          local existing = GC.Sniper._realmDeals[itemID]
          local cap = existing and existing.cap and GC.Caps and GC.Caps.For(itemID)
          local floor = floorOf[itemID]
          if not (cap and floor and floor <= cap.c) then
            GC.Sniper._realmDeals[itemID] = nil
          end
        end
      end
    end
    for i = 1, #fresh do GC.Sniper._realmDeals[fresh[i].itemID] = fresh[i] end
    -- A map grows for as long as the poll keeps finding things; the board under it renders a
    -- hundred rows. Same cap, same order (Core/FullScan.lua's own comparator) the commodity
    -- side has always had -- see GC.FullScan.CapDeals.
    GC.FullScan.CapDeals(GC.Sniper._realmDeals, WIN.ROW_CAP)
    refreshRows() -- also re-derives the ITEMS chip's count, see GC.Sniper._PaintBoardChips
    -- One answer brings the next turn: with the pass paused for this board there is no other
    -- sender to bring a ready tick, so the poll is its own clock (see _SetBoard). Through the
    -- arbiter, deferred a frame, not a direct send -- a queued drill-down for a specific lot
    -- still goes ahead of the next batch, exactly as it does on a real ready tick.
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function() if GC.Sniper.OnThrottleReady then GC.Sniper.OnThrottleReady() end end)
    end
  end,
})

-- itemID -> the deal the key poll last built for it: the ITEMS board's whole store, and the
-- only account of a realm item there is (nothing else on the board's read path ever writes a
-- realm row -- see onRows above and applyFullScanResults). Capped at WIN.ROW_CAP by the same
-- comparator the commodity board uses, in onRows.
GC.Sniper._realmDeals = {}

-- Cancels any full scan in flight (waiting on the throttle system, or mid-paging). Called on
-- AUCTION_HOUSE_CLOSED per the verified API note that a scan should not keep running once
-- the player has left the Auction House -- browse results die with the AH session anyway.
local function abortFullScan()
  if GC.Sniper._bookPass:IsPaging() then
    fullScanToken = fullScanToken + 1 -- invalidates any in-flight watchdog closures
  end
  GC.Sniper._bookPass:Abort()
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
    setStatus(GC.L["auto off"])
  else
    setStatus(GC.L["auto: paused"])
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
  lastBrowseEventAt = 0
  streamRows, streamRowsCount = {}, 0
  GC.Sniper._screenedCount = 0
  mode = "fullscan"
  refreshRows()
  -- Sniper phase 2: one loop cycle is one pass plus one visit to every key-poll target, so a
  -- fresh pass is what re-arms the poll. The count from the cycle that just ended is carried
  -- over for the pass readout (applyFullScanResults) -- the keys for THIS cycle have not run
  -- yet when that line is written.
  GC.Sniper._keysLastCycle = GC.Sniper._keysThisCycle or 0
  GC.Sniper._keysThisCycle = 0
  GC.Sniper._keyPoll:BeginCycle()
  local kind = GC.Sniper._bookPass:IsWidePassDue() and "wide" or "classes"
  GC.Sniper._bookPass:Start(kind)
  trace("pass: armed (" .. kind .. "), apiReady=" .. tostring(driver.isReady()))
  -- Start only ARMS the pass now (Core/BookPass.lua): the arbiter is the single sender for
  -- the one throttled search slot. AUCTION_HOUSE_THROTTLED_SYSTEM_READY fires when the system
  -- BECOMES ready, so an idle client that is ready already may not produce one -- poke the
  -- arbiter here rather than wait for an event that may never come. It still arbitrates: a
  -- parked Check, the quiet zone or a queued drill-down can take this slot instead, and the
  -- pass's own start stays pending for the next one.
  if driver.isReady() then GC.Sniper.OnThrottleReady() end
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
    -- A scan is already running and Auto is adopting it: SCANNING is the truth.
    if GC.Sniper._bookPass:IsPaging() then return true end
    -- Shared throttle budget: while the player is busy on Blizzard's own AH panes -- posting,
    -- buying a browse result, or reading their own search -- their click outranks a fresh
    -- background scan. Returning false is what keeps the machine honest about it: it used to
    -- advance to SCANNING regardless of what this did, so withholding the send left the button
    -- reading "AUTO · SCANNING" with nothing in flight and no event that could ever move it on
    -- -- reported from the game as an Auto that said it was scanning and never scanned. The
    -- machine now stays in WAITING and tries again a moment later.
    if GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy and GC.AuctionHouseTab.PlayerIsBusy() then return false end
    -- A keys batch is out: its answer is the next browse event, and a page sent now would be
    -- read as that answer (see _FoldKeysBatch). Wait; the batch times out in 8s at worst.
    if GC.Sniper._KeysOutstanding and GC.Sniper._KeysOutstanding() then return false end
    startFullScan()
    return true
  end,
  abortScan = cancelFullScan,
})

feedAuto = function(event)
  local before = autoScan:State()
  autoScan:Input(event, GetTime())
  local after = autoScan:State()
  if after ~= before or event == "toggleOn" or event == "toggleOff" then
    trace("auto: " .. event .. " -> " .. after)
  end
  if refreshAutoButton then refreshAutoButton() end
end

local AUTO_PAUSE_LABEL = { dialog = "buying", search = "searching", mail = "mail", sell = "selling",
  items = "items", buy = "buying" }
-- Display priority when more than one pause reason is set at once (e.g. a buy dialog opened
-- while the player's own search was already live) -- "buying" wins because it's the most
-- decisive of the four: the player is one click from spending gold. `ah`/`tab` are
-- deliberately absent -- per spec they render as plain "AUTO", not a paused chip, since
-- neither reflects something the player is actively DOING right now.
local AUTO_PAUSE_ORDER = { "dialog", "search", "mail", "sell", "items", "buy" }

local function autoButtonText(state, reasons)
  if state == "SCANNING" then return GC.L["AUTO · SCANNING"] end
  if state == "PAUSED" then
    for _, reason in ipairs(AUTO_PAUSE_ORDER) do
      if reasons[reason] then return GC.L["AUTO · PAUSED: "] .. AUTO_PAUSE_LABEL[reason] end
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
  local busy = GC.Sniper._bookPass:IsPaging()
  if f.fullScanBtn.lastBusy == busy then return end
  f.fullScanBtn.lastBusy = busy
  f.fullScanBtn:SetLabel(busy and GC.L["SCANNING…"] or GC.L["SCAN"])
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
  fs:SetText((GC.L["SESSION %s%s · %d BUYS"]):format(s.estProfit >= 0 and "+" or "",
    GC.Util.FormatMoney(s.estProfit), s.buys))
  fs:SetTextColor(c[1], c[2], c[3])
  fs:Show()
end

local function onFullScanClick()
  if not frame then return end
  if not GC.Sniper.scanner then
    frame.status:SetText(GC.L["Open the Auction House first."])
    return
  end

  if GC.Sniper._bookPass:IsPaging() then
    frame.status:SetText(GC.L["full scan already in progress"])
    return
  end

  frame.status:SetText(GC.L["starting full scan..."])
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
  -- Check panel v3: the chip is drawn, but WHETHER it is on screen belongs to the verdict --
  -- it sits in the reconciliation block, which layoutBlocks only stacks when what the board
  -- said and what this check found disagree. What the chip SAYS is the board's own label for
  -- this row (GC.BoardRows), so the reconciliation sentence sits next to the exact words the
  -- player just clicked on -- it used to show the discovery tier, which no row has displayed
  -- since the verdict replaced it. Hidden outright when there is no verdict to disagree with.
  local rowVerdict = verdictFor(deal)
  if rowVerdict then
    dialog.tierChip:SetLabel(GC.BoardRows.Label(rowVerdict),
      rowVerdict.buyable and Theme.color.green or Theme.tier.WATCH)
    dialog.tierChip:Show()
  else
    dialog.tierChip:Hide()
  end
  local quantity = decision and decision.quantity or nil
  local suffix = quantity and quantity > 0 and ("  x%d"):format(quantity) or ""
  dialog.nameText:SetText((GC.L["item %d"]):format(deal.itemID) .. suffix)
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
  return value and GC.Util.FormatMoney(value) or "—"
end

-- DG (dialog geometry): relocated here from down by createDialog (F4, whole-branch review) --
-- resizeDialogDiagnostics below needs DG.CONTROLS_H for its drawer-era status anchor, and a
-- local must be declared before the earliest function that closes over it (same chunk-order
-- requirement CH was moved for; see CH's own comment, and the "Sniper v3 dialog layout
-- constants" marker left in DG's old spot -- that exact text is a protected-spec section
-- boundary and could not move with the table). One table, not seventeen top-level locals: a
-- Lua chunk may hold 200 of those and this file sits at exactly 200 -- see the addon's engineering notes.
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
DG.DIAGNOSTIC_MIN_H = 36
DG.STATUS_H = 32
DG.PRIMARY_H = 32 -- Task 2 restyle (was 26): kit-value GC.L["big buy"] plaque height
DG.CANCEL_H = 22 -- Task 2 restyle (was 20)
-- Header is just top margin + icon + gap: the item, and nothing that competes with it.
-- 12 + 32 + 8 = 52
DG.HEADER_H = Theme.pad.m + DG.ICON + Theme.pad.s
-- The "ESC" hint's own column, and what is left for the item's name beside it. The name gets
-- ONE anchor and this width rather than a LEFT/RIGHT pair -- see its own comment in
-- createDialog for why that pair is a trap here.
DG.HEADER_ESC_W = 30
-- 320 - 12 - 32 - 8 - 30 - 8 - 12 = 218
DG.HEADER_NAME_W = DG.WIDTH - Theme.pad.m - DG.ICON - Theme.pad.s
  - DG.HEADER_ESC_W - Theme.pad.s - Theme.pad.m

-- Check panel v3 -- docs/design/2026-08-28-check-panel, the design the owner approved after
-- two in-game passes called this window cramped and hard to read. The panel stopped being one
-- fixed stack with holes punched in it: a REFUSAL and a PURCHASE are different shapes of
-- window, and every block below is present only when it has something to say. The old layout
-- reserved 94px for a profit figure a refusal never has, offered a quantity box on verdicts
-- where nothing could be bought, and printed the same sentence in three places.
--
-- Each block is a container frame built once by createDialog, with its children anchored
-- inside it at fixed offsets; layoutDialogBlocks stacks the ones that are shown and adds up
-- their heights. Nothing below is a *_TOP offset any more -- those could not survive blocks
-- that come and go.

-- THE ANSWER, edge to edge and tinted: the verdict word, then ONE figure that changes UNIT
-- rather than going blank (gold, days, units, or "can't price this" at the same weight), its
-- caption, and the sentence saying why. See Core/CheckVerdict.lua, which decides all of it.
-- 8 + 12 + 4 + 28 + 4 + 26 + 4 + 30 + 8 = 124
DG.HERO_KICKER_H = 12
DG.HERO_FIGURE_H = 28
DG.HERO_CAPTION_H = 26 -- two lines of Theme.Label(10) at this width
DG.HERO_SENTENCE_H = 30 -- two lines of Theme.Label(12)
DG.HERO_H = Theme.pad.s + DG.HERO_KICKER_H + Theme.pad.xs + DG.HERO_FIGURE_H + Theme.pad.xs
  + DG.HERO_CAPTION_H + Theme.pad.xs + DG.HERO_SENTENCE_H + Theme.pad.s

-- Shown only when the board's tier and this verdict actually disagree. A HOT chip 320 pixels
-- from "won't buy" is the window arguing with itself, and the tier came from the imported
-- snapshot while the verdict came from the live book -- so the chip lives HERE, beside the
-- sentence that reconciles the two, instead of in the header where it read as a peer of the
-- item's own name. 8 + 20 (chip) + 8 = 36, with room for a two-line note beside it.
DG.RECONCILE_H = 36

-- Quantity + its quick-fill chips, plus the gap under them. Present only when there IS
-- something to buy: on a refusal the box and its four chips are the bulk of what a player has
-- to read past to reach the reason.
-- 20 (label line) + 4 + 18 (chip row) = 42, + 8 gap = 50
DG.QTY_H = 20 + Theme.pad.xs + DG.QTY_QUICKFILL_H
DG.QTY_BLOCK_H = Theme.pad.s + DG.QTY_H
DG.QTY_BOX_H = 18

-- THE FACTS -- four, chosen to explain THIS verdict rather than to fill a fixed grid. Three
-- columns: the label, then a meter where a real scale exists (a percentage, a threshold the
-- engine itself applies, or a pair sharing one ceiling) or a quiet leader line where it does
-- not, then the value. A bar with no honest ceiling is a decoration competing with the figure
-- above it, which is why CheckVerdict hands out `meter` on some facts and not others.
-- 96 + 8 + 94 + 8 + 90 = 296 = the content width at DG.WIDTH.
DG.FACT_ROWS = 4
DG.FACT_ROW_H = 19
DG.FACT_LABEL_W = 96
DG.FACT_VALUE_W = 90
DG.FACT_METER_W = DG.WIDTH - 2 * Theme.pad.m - DG.FACT_LABEL_W - DG.FACT_VALUE_W - 2 * Theme.pad.s
DG.FACT_METER_H = 4
DG.FACTS_H = Theme.pad.s + DG.FACT_ROWS * DG.FACT_ROW_H -- 8 + 76 = 84

-- Task 2 restyle: no longer tied to DG.GRID_ROW_H (20) -- the kit gives the toggle its own
-- height (22), so it needs its own field now that the two numbers differ.
DG.TOGGLE_H = 22
DG.TOGGLE_BLOCK_H = Theme.pad.xs + DG.TOGGLE_H -- 26

-- The full transcript, behind the toggle. It REPLACES the four facts rather than stacking
-- under them: four of these ten rows ARE those facts, and reserving 84 + 188 at once is what
-- made the toggle refuse to open in the docked AH drawer (~565px, no resize handle) and print
-- "Enlarge the window" at a window that cannot be enlarged.
-- 8 + 10 * 18 = 188
DG.GRID_H = Theme.pad.s + DG.GRID_ROWS * DG.GRID_ROW_H

-- bottom margin + cancel + gap + primary + gap-to-status, measured up from the dialog's own
-- bottom edge.
-- 12 + 32 + 4 + 22 + 8 = 78
DG.CONTROLS_H = Theme.pad.m + DG.PRIMARY_H + Theme.pad.xs + DG.CANCEL_H + Theme.pad.s
-- Construction-time defaults, before any verdict is known: the TALLEST shape, a purchase with
-- the quantity block in. layoutDialogBlocks writes d.fixedHeightClosed/d.fixedHeightOpen per
-- verdict from the blocks actually shown, and applyDetailsState prefers those when they exist
-- -- so the fit guard measures the window the player is looking at, not a worst case.
-- 52 + 124 + 50 + 84 + 26 + 32 + 78 = 446
DG.FIXED_HEIGHT_CLOSED = DG.HEADER_H + DG.HERO_H + DG.QTY_BLOCK_H + DG.FACTS_H
  + DG.TOGGLE_BLOCK_H + DG.STATUS_H + DG.CONTROLS_H
-- 446 - 84 + 188 = 550, and a refusal (no quantity block) is 500 -- both inside the docked
-- drawer's own ceiling, which the old 548-closed/728-open pair never was.
DG.FIXED_HEIGHT_OPEN = DG.FIXED_HEIGHT_CLOSED - DG.FACTS_H + DG.GRID_H

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
  -- One number since check panel v3 (layoutBlocks writes it): the blocks above this point come
  -- and go with the verdict, so there is no longer a fixed open/closed pair to pick between.
  -- The pair is still read as a fallback for the hand-built fakeDialogs in the verdict specs,
  -- which never run layoutBlocks.
  local evidenceBottom = dialog.evidenceTop
    or (dialog.detailsOpen and dialog.evidenceTopOpen or dialog.evidenceTopClosed)
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

-- Draws what Core/CheckVerdict.lua decided (check panel v3). Named drawVerdict, not
-- stampVerdict: that name is already taken by the row-level recorder forward-declared far
-- above, and shadowing it left the recorder permanently nil. Nothing here decides anything:
-- the tone, the UNIT of the headline figure, which four facts back it, whether there is
-- anything left to act on and whether the board's tier needs reconciling are all settled
-- before this runs -- see that file's header for why the split exists at all.
--
-- Every write is guarded on the field existing: two protected specs stamp a hand-built
-- fakeDialog that carries only the handful of widgets they assert on, and a purchase must
-- never fail because a cosmetic slot is missing.
local function drawVerdict(deal, decision, market)
  local CV = GC.CheckVerdict
  local verdict = CV.Build(decision, market, { tier = deal.tier })
  local tone = verdict.tone
  local accent = Theme.color.green
  if tone == "refuse" then accent = Theme.color.red
  elseif tone == "adjust" or tone == "unverified" then accent = Theme.color.gold end

  if dialog.setHeroTone then dialog.setHeroTone(accent) end
  if dialog.verdictLabel then
    dialog.verdictLabel:SetText(GC.L[CV.TONE_WORD[tone] or ""])
    dialog.verdictLabel:SetTextColor(accent[1], accent[2], accent[3])
  end

  -- THE FIGURE. It changes unit rather than going blank: a refusal about the VALUE has no
  -- honest number at all, and printing "—" in a 28px slot reads as a value that failed to
  -- load rather than as a refusal to invent one.
  -- Each branch formats its OWN caption rather than collecting args for a shared
  -- `caption:format(unpack(args))`: `unpack` is a global in the game's Lua 5.1 and gone in the
  -- 5.4+ that runs the specs, so that spelling passes here and errors on the buy path.
  local hero, quantity = verdict.hero, decision.quantity or 0
  local figure, figureColor, caption
  if hero.kind == "gold" then
    local up = hero.copper >= 0
    figure = (up and "+" or "") .. displayDecisionAmount(hero.copper)
    figureColor = up and Theme.color.green or Theme.color.red
    caption = (GC.L[CV.HERO_CAPTION[up and "gold_up" or "gold_down"]]):format(quantity)
  elseif hero.kind == "reference" then
    -- Sniper phase 2's own figure: what this lot would clear against the region reference,
    -- with a caption that takes no arguments -- there is no quantity to name, an item auction
    -- being one atomic lot.
    local up = hero.copper >= 0
    figure = (up and "+" or "") .. displayDecisionAmount(hero.copper)
    figureColor = up and Theme.color.green or Theme.color.red
    caption = GC.L[CV.HERO_CAPTION.reference]
  elseif hero.kind == "days" then
    figure = (GC.L["%d days"]):format(hero.days)
    figureColor = Theme.color.gold
    caption = (GC.L[CV.HERO_CAPTION.days]):format(quantity,
      GC.Util.FormatCount(market.soldPerDay) or "—", displayDecisionAmount(decision.entryTotal))
  elseif hero.kind == "units" then
    figure = (GC.L["%d units"]):format(hero.quantity)
    figureColor = Theme.color.gold
    caption = GC.L[CV.HERO_CAPTION.units]
  else
    caption = GC.L[CV.HERO_CAPTION.unpriceable]
  end

  if dialog.verdictAmount then
    if figure then
      dialog.verdictAmount:SetText(figure)
      dialog.verdictAmount:SetTextColor(figureColor[1], figureColor[2], figureColor[3])
      dialog.verdictAmount:Show()
    else
      dialog.verdictAmount:Hide()
    end
  end
  -- The unpriceable case says so at the SAME weight the figures get, in words, because that is
  -- the answer -- not a missing one.
  if dialog.heroText then
    if figure then
      dialog.heroText:Hide()
    else
      dialog.heroText:SetText(GC.L["Can't price this"])
      dialog.heroText:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
      dialog.heroText:Show()
    end
  end
  if dialog.verdictAmountNote then
    dialog.verdictAmountNote:SetText(caption)
    dialog.verdictAmountNote:Show()
  end

  -- The sentence. On a refusal it is the reason the engine actually filed -- wrapped now, so
  -- it stops ending in the "…" the owner's screenshot caught.
  local sentence = tone == "refuse" and GC.SniperDecision.ReasonText(verdict.reason)
    or GC.L[CV.TONE_SENTENCE[tone] or ""]
  dialog.verdictHead:SetText(sentence)
  if tone == "refuse" then
    dialog.verdictHead:SetTextColor(1, 0.3, 0.3)
  else
    dialog.verdictHead:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3])
  end
  -- The old third copy of the same profit figure. Nothing shows it again.
  if dialog.verdictSub then dialog.verdictSub:Hide() end

  if dialog.reconcileText and verdict.reconcile then
    dialog.reconcileText:SetText(GC.L[CV.RECONCILE_TEXT.line])
  end

  -- THE FACTS. A meter only where CheckVerdict handed one out -- a bar drawn against a ceiling
  -- that does not exist is decoration competing with the figure above it.
  if dialog.factRows then
    for i = 1, #dialog.factRows do
      local slot, fact = dialog.factRows[i], verdict.facts[i]
      if not fact then
        slot.label:SetText("")
        slot.value:SetText("")
        slot.meter:Hide()
        slot.leader:Hide()
      else
        local color = Theme.color.fg
        if fact.tone == "bad" then color = Theme.color.red
        elseif fact.tone == "good" then color = Theme.color.green
        elseif fact.tone == "muted" then color = Theme.color.fgDim end

        local value
        if fact.copper then
          -- A signed figure only where the sign is the point: "+184g" answers "and if it
          -- does clear?", while a signed "+622g" against what you PAY reads as a gain.
          local signed = fact.id == "ifItClears" or fact.id == "worstCaseBack"
          value = ((signed and fact.copper >= 0) and "+" or "") .. displayDecisionAmount(fact.copper)
        elseif fact.bps then
          value = ("%d%%"):format(math.floor(fact.bps / 100 + 0.5))
        elseif fact.id == "confidence" then
          value = GC.L[CV.CONFIDENCE_WORD[CV.ConfidenceBand(fact.count) or ""] or ""]
        else
          value = GC.Util.FormatCount(fact.count) or "—"
        end

        slot.label:SetText(GC.L[CV.FACT_LABEL[fact.id] or fact.id])
        slot.value:SetText(value)
        slot.value:SetTextColor(color[1], color[2], color[3])

        if fact.meter then
          slot.leader:Hide()
          slot.fill:SetWidth(math.max(1, math.floor(DG.FACT_METER_W * fact.meter.at + 0.5)))
          slot.fill:SetColorTexture(color[1], color[2], color[3], 0.8)
          local tickX = math.floor(DG.FACT_METER_W * fact.meter.gate + 0.5)
          slot.tick:ClearAllPoints()
          slot.tick:SetPoint("TOP", slot.meter, "TOPLEFT", tickX, 0)
          slot.tick:SetPoint("BOTTOM", slot.meter, "BOTTOMLEFT", tickX, 0)
          slot.meter:Show()
        else
          slot.meter:Hide()
          slot.leader:Show()
        end
      end
    end
  end

  if dialog.layoutBlocks then
    dialog.layoutBlocks({ reconcile = verdict.reconcile, actionable = verdict.actionable })
  end
  return verdict
end

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

  -- The verdict block is drawn by drawVerdict (above), off Core/CheckVerdict.lua. The item's
  -- own name is not repeated here -- the header carries it, and "Buy 3 × Argentleaf for 453g"
  -- said the same thing the primary button says two inches below it.
  drawVerdict(deal, decision, market)

  local publicStatus = decision.status or "WATCH"
  local computedStatus = decision.computedStatus or publicStatus
  local diagnosticReasons = table.concat(decision.reasons or {}, ", ")
  if decision.computedStatus == "SAFE" and publicStatus == "WATCH" then
    dialog.decisionStatusText:SetText(GC.L["WATCH (computed SAFE)"])
  else
    dialog.decisionStatusText:SetText(publicStatus)
  end
  -- The item ID leads the line because this diagnostic is the only place it survives: the
  -- header shows "item <id>" for exactly as long as Item:ContinueOnItemLoad takes to replace
  -- it with the localized name, and a name is not an identity -- tiered reagents share one
  -- name across several IDs. Without this, a shadow observation transcribed from the dialog
  -- cannot be attributed to an item afterwards.
  dialog.diagnosticText:SetText((GC.L["item=%d computed=%s public=%s buyable=%s reasons=%s"]):format(
    deal.itemID, computedStatus, publicStatus, decision.buyable and "yes" or "no",
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
  -- Formatted, not printed raw. These three cells were showing "856146.0", "95.4%" and
  -- "3384s" in a 64px column: a trailing .0 on a figure whose last five digits carry no
  -- decision, a tenth of a percent nobody acts on, and an age in seconds. See
  -- GC.Util.FormatCount / FormatElapsed for why each rounds the way it does.
  dialog.soldText:SetText(market.soldPerDay and GC.Util.FormatCount(market.soldPerDay) or "—")
  dialog.sellThroughText:SetText(market.sellThroughBps
    and ("%d%%"):format(math.floor(market.sellThroughBps / 100 + 0.5)) or "—")
  dialog.sourceAgeText:SetText(sourceAge and GC.Util.FormatElapsed(sourceAge) or "—")
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
  if not decision or quote.itemID ~= deal.itemID
      or type(quote.total) ~= "number" or quote.total <= 0 then
    return nil
  end
  local market = quote.market or {}
  -- Sniper phase 2: a realm lot has no SAFE decision to anchor a cost basis to -- it is bought
  -- on a candidate, one named auction at one named price -- but a purchase is a purchase and
  -- gold that left the player's bags has to be recorded. `unverified` is the fact that carries
  -- what was NOT known: the price was checked against the region reference, the sale speed was
  -- never measured. It rides onto the ledger row so the site can tell the two apart later.
  local candidate = (decision.status == "WATCH" and type(decision.candidate) == "table")
    and decision.candidate or nil
  if candidate then
    local reference = decision.reference
    if type(reference) ~= "number" or reference ~= reference or reference <= 0 then return nil end
    local quantity = (type(candidate.quantity) == "number" and candidate.quantity >= 1)
      and math.floor(candidate.quantity) or 1
    return {
      itemID = deal.itemID,
      quantity = quantity,
      total = quote.total,
      unitDisplay = math.floor(quote.total / quantity),
      decisionVersion = decision.version,
      decisionStatus = decision.status,
      decisionReasons = copyReasons(decision.reasons),
      unverified = true,
      -- The region reference is the only price anything measured for this item, so it is also
      -- the honest posting target: GC.Data.RecordFlip stores it as the flip's targetUnit and
      -- the Sell tab prices against it.
      stressUnit = math.floor(reference),
      expectedProfit = math.max(0, math.floor(decision.estProfit or 0)),
      recommendedQuantity = quantity,
      -- A realm item carries no verification block, so there is no source timestamp behind it.
      -- 0 rather than nil: the ledger's own validator takes a non-negative integer, and "no
      -- fact" is the truth here rather than a missing field.
      sourceAt = market.sourceAt or 0,
    }
  end
  if decision.status ~= "SAFE" or not decision.buyable
      or quote.quantity ~= decision.quantity then
    return nil
  end
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

-- A confirmed attempt whose ownership _ReleaseStrandedConfirmed has already given up, kept
-- itemID -> { pending, at } for one last chance to be recorded. Confirm had reached Blizzard,
-- so the gold may well have left the player's bags; before this, a success that arrived after
-- the release was written down NOWHERE -- the sniper had let go, and Core/PurchaseCapture.lua
-- had stood down at the Start precisely because the sniper owned the attempt. A table field
-- rather than a file local: this chunk sits near Lua's 200-local ceiling (see the addon's engineering notes).
GC.Sniper._strandedConfirmed = {}

-- The one released attempt still inside its window, or nil. Commodity terminal events carry no
-- attempt identifier at all, so with two records in hand attribution would be a guess: fail
-- closed and record neither. Ten minutes is far past any real round trip, and expiry is checked
-- here rather than on a timer so a dead session cannot leave a record alive forever.
local function takeStrandedConfirmed()
  local records = GC.Sniper._strandedConfirmed
  local now = GetTime()
  local found, foundID, count = nil, nil, 0
  for itemID, record in pairs(records) do
    if now - (record.at or 0) > 600 then
      records[itemID] = nil
    else
      found, foundID, count = record.pending, itemID, count + 1
    end
  end
  if count ~= 1 then return nil end
  records[foundID] = nil
  return found
end

-- Whether any record above is still inside its window. The BUY tab asks before it books a late
-- success of its own (UI/BuyFrame.lua's mayOwnTerminal): a stranded confirm on both sides makes
-- the event nobody's to take. Read-only, so asking never consumes; and a field on GC.Sniper, not a
-- file local, for the same ceiling reason as the table itself.
--
-- A confirmed attempt that has let go of the shared purchase slot counts too. Esc on a dialog at
-- "confirming" drains the attempt into a confirmed tombstone and releases the slot; a confirmed
-- attempt still in flight holds the slot, but is listed all the same so the answer does not
-- depend on which of the two the release happens to reach first. Either way its success is still
-- owed to THIS window. Left out, a stranded BUY record took that success (the slot was free, a
-- record was live), booked it as a BUY purchase, and the confirmed tombstone -- which is never
-- retired on a timer -- refused every later commodity Buy with "waiting for previous commodity
-- purchase to settle" until /reload.
function GC.Sniper.HasStrandedConfirmed()
  if commodityDraining and commodityDraining.confirmed then return true end
  if commodityPurchase and commodityPurchase.confirmed then return true end
  local now = GetTime()
  for _, record in pairs(GC.Sniper._strandedConfirmed) do
    if now - (record.at or 0) <= 600 then return true end
  end
  return false
end

local function consumePurchasedDeal(deal)
  -- `deal` may be the purchase's own copy of the board entry (the realm path copies it at the
  -- click, so a bid that never lands cannot rewrite the price the board is showing), which is
  -- why identity alone is no longer proof of which entry was bought.
  if deals[deal.itemID] == deal or (deal.boardDeal and deals[deal.itemID] == deal.boardDeal) then
    deals[deal.itemID] = nil
  end
  -- The key poll's own copy of the realm board (see its onRows) survives a completed pass, so
  -- a bought realm lot has to be taken out of it too or the next pass puts it straight back.
  if GC.Sniper._realmDeals then GC.Sniper._realmDeals[deal.itemID] = nil end
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
  local text = (GC.L["item %d: %s"]):format(itemID, note)
  if frame then frame.status:SetText(text) end
  if GC.Print then GC.Print(text) end
end

local function settleDetachedConfirmed(pending, terminal)
  local deal = pending and pending.deal
  if terminal == "success" then
    local purchase = deal and purchaseFacts(deal, pending.quote)
    if purchase then
      recordPurchaseFacts(deal, purchase)
      reportDetachedCommodity(pending, (GC.L["bought %d x item %d after AH close"]):format(
        purchase.quantity, deal.itemID))
      return
    end
    reportDetachedCommodity(pending, GC.L["purchase total unavailable — inspect mailbox"])
    return
  end
  if terminal == "unavailable" then
    reportDetachedCommodity(pending, GC.L["purchase total unavailable — inspect mailbox"])
  else
    reportDetachedCommodity(pending, GC.L["confirmed commodity purchase failed after AH close"])
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
      -- Unconditional (not gated on the check above): some callers (the confirmed-failure and
      -- unavailable branches in GC.Sniper.OnCommodityPurchase*) already nil commodityPurchase
      -- themselves before calling in here, so this attempt's own claim would otherwise survive
      -- past its terminal event. Release() is a no-op unless "sniper" is still the owner, so
      -- calling it here for every commodity resolution is always safe.
      if GC.PurchaseSlot then GC.PurchaseSlot.Release("sniper") end
    elseif deal.auctionID then
      pendingAuction[deal.auctionID] = nil
    end
    if success then
      if not purchase and deal.isCommodity then
        -- There is no trustworthy cost basis without the final server quote. Keep the row
        -- frozen for mailbox inspection rather than inventing a total from a search result.
        row.purchaseStage = "frozen"
        row.purchaseDeal = nil
        row.decisionSnapshot = nil
        row.quoteSnapshot = nil
        row.armedLevels = nil
        row.armedItemID = nil
        -- `refreshRows()` only preserves pinned rows. Keep this unresolved server success
        -- visible (and its discovery deal excluded from a second attempt) until AH close or
        -- the player inspects the mailbox, rather than letting the pool repurpose it.
        activeItemID[deal.itemID] = true
        if dialog and dialog.row == row then
          dialog.primaryBtn:Disable()
          setDialogStatus(GC.L["purchase total unavailable — inspect mailbox"], 1, 0.3, 0.3)
        end
        if frame then frame.status:SetText(GC.L["purchase total unavailable — inspect mailbox"]) end
        refreshRows()
        return
      end
      if purchase then
        recordPurchaseFacts(deal, purchase)
      else
        -- A realm lot, bought at its buyout. An item auction has no server quote step at all
        -- -- PlaceBid pays exactly the price the dialog showed -- so there is nothing unknown
        -- to freeze the row over. It is not written to the ledger either: a sniper buy's cost
        -- basis there is anchored to the SAFE decision that permitted it, and this purchase
        -- deliberately never had one. What it must still do is stop the board advertising a
        -- listing that is now gone.
        consumePurchasedDeal(deal)
      end
    end
  end

  row.purchaseStage = nil
  row.purchaseDeal = nil
  row.decisionSnapshot = nil
  row.quoteSnapshot = nil
  row.armedLevels = nil
  row.armedItemID = nil
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
      if attempt.sent then GC.Sniper._FenceDrain(deal.itemID, attempt) end
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
    setPrimaryLabel(GC.L["Gone"])
    setDialogStatus(message, 1, 0.3, 0.3)
    dialog.cancelBtn:SetLabel(GC.L["Close"])
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
      setPrimaryLabel(GC.L["Refresh"])
      -- Task 2 restyle: red, not amber (Theme.color.red's own literal values -- see
      -- setDialogStatus's own comment for why this file hardcodes rather than reads the live
      -- table). The Kit's status color rule is green on armReady's own Buy confirmation, red on
      -- refusal OR expiry, fgDim (setDialogStatus's own default) everywhere else.
      setDialogStatus(GC.L["quote expired -- Refresh to re-check the price"], 0.898, 0.283, 0.302)
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
  -- The book this decision was made on, kept ON THE ROW and stamped with the item it belongs
  -- to. The client holds ONE commodity search buffer, and a dialog armed off a hover pre-warm
  -- cache (openDialog's own shortcut, up to LIM.PREWARM_TTL_SECONDS old) opens with that
  -- buffer already holding whatever the verify walk or a drill-down looked at last. The Buy
  -- click's final re-evaluation used to read the buffer blind and refuse the purchase --
  -- "the price moved and the trade is no longer safe" on a price that had not moved, which
  -- a second Check fixed only because a Check re-fills the buffer with this item.
  -- dialog.bookLevels cannot carry this: the dialog is a session-long singleton and the same
  -- field is cleared and overwritten by later stages.
  row.armedLevels = levels
  row.armedItemID = deal.itemID
  activeItemID[deal.itemID] = true
  -- Guarded like every sibling stage (armCheck, scheduleArmTimeout, applyRequeryResult's realm
  -- branch): a requery can land for a row the dialog has since moved off, and without this it
  -- painted ANOTHER deal's dialog as armed -- enabled Buy button, green "click Buy", this
  -- deal's numbers -- over the row the player is actually looking at. The row's own arming
  -- above is unconditional; only the screen has to belong to it.
  if dialog and dialog.row == row then
    dialog.primaryBtn:Enable()
    hideRequoteBanner()
    setPrimaryLabel("Buy")
    dialog.bookLevels = levels
    setDialogHeader(deal, decision)
    stampDialogFromDecision(deal, decision)
    -- The dialog's OWN status must flip here -- the requery path otherwise leaves its
    -- "checking live price..." text up even though the button just enabled, and the player
    -- reads the stale text right up until the quote expires.
    setDialogStatus(GC.L["price confirmed -- click Buy to purchase"], 0.25, 0.85, 0.25)
  end
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
    row.armedLevels = nil
    row.armedItemID = nil
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
    -- Inside the guard with the rest of the dialog. The quiet-zone release (and the auction
    -- house error path) calls this for EVERY mid-flight row, and each one used to overwrite the
    -- status line of whatever the dialog was showing -- so a player reading one item's check
    -- watched it say "Check again" about a different one. The window's own status line below
    -- is the right place for a board-wide message and still gets it.
    setDialogStatus(note or GC.L["live verification required"], 1, 0.82, 0)
  end
  if frame then frame.status:SetText(note or GC.L["live verification required"]) end
end

-- The dialog keeps its book depth only as display/quantity context. Every approval and total
-- still comes from the immutable SniperDecision snapshot, never from this UI cache.
local function availableFromLevels(levels)
  local total = 0
  for _, level in ipairs(levels or {}) do total = total + (level.quantity or 0) end
  return total > 0 and total or nil
end

-- Live price caps, addon task 5: the deal a capped item's own drilled result builds, once
-- GC.Caps.DecideRealm/DecideCommodity finds a lot/book at or under the player's price. Same
-- shape a GC.DealMath.Evaluate deal carries (the renderer reads either one identically) --
-- `mv`/`estProfit` degrade to no-reference/`-unit` gracefully since a capped item needs no
-- market value to qualify (GC.Caps.For's own contract: the cap IS the player's own price).
-- `discount`/`profit`/`tier` are given the same values an ordinary deal falls back to; nothing
-- reads a "CAP" tier, so there is no reason to invent one.
local function buildCapDeal(itemID, isCommodity, unit, qty, auctionID, cap)
  local value = GC.Data.GetItemValue(itemID)
  local estProfit = (value and math.floor(value.mv * 0.95) or 0) - unit
  return {
    itemID = itemID,
    isCommodity = isCommodity,
    unitPrice = unit,
    qty = qty,
    auctionID = auctionID,
    mv = value and value.mv,
    discount = 0,
    profit = estProfit,
    estProfit = estProfit,
    tier = "WATCH",
    cap = cap.c,
    capGroup = cap.group,
    capManual = cap.manual,
    -- Same flag every full-scan-derived deal carries: this snapshot is not itself the last
    -- word, and openDialog's first click on it is a live re-Check, exactly like any other
    -- `.stale` row -- never an arm straight off a background read.
    stale = true,
  }
end

-- `levels` is an optional pre-built book (from driver.commodityBook) the caller already has --
-- onObservation below passes its own so the same poll's book is not fetched twice. Every other
-- call site omits it and gets the old behaviour of building its own.
evaluateLiveCommodityDeal = function(itemID, levels)
  levels = levels or driver.commodityBook(itemID)
  if not levels then return nil end
  local result = driver.commodityResult(itemID)
  local avail = (result and result.avail) or availableFromLevels(levels)
  -- Task 5: a capped commodity is judged against the player's OWN price first -- the whole
  -- reason GC.Caps.For needs no market reference to fire (Core/Caps.lua's own contract). Only
  -- when there is nothing to buy under the cap (or the saving misses minimumProfitCopper) does
  -- this fall through to the ordinary region/market-value Evaluate below, exactly like any
  -- other item: a capped item that is not currently a deal by its own price can still be one
  -- by the market's.
  local cap = GC.Caps and GC.Caps.For(itemID)
  if cap then
    local capDecision = GC.Caps.DecideCommodity(cap, levels, GC.db.settings.sniper.minimumProfitCopper)
    if capDecision then
      local capDeal = buildCapDeal(itemID, true, capDecision.unit, capDecision.quantity, nil, cap)
      if GC.Sniper._liveTracksScanDeals then
        scanDeals = GC.FullScan.ApplyLiveObservation(scanDeals, itemID, capDeal, WIN.ROW_CAP)
      else
        deals[itemID] = capDeal
      end
      -- Addon task 6: queued for the board-ring (drained by refreshRows(), see pendingCapPings)
      -- only once per GC.Caps.Announce's own dedup -- an unchanged or worse floor on a re-poll
      -- stays silent.
      if GC.Caps.Announce(capDeal) then
        pendingCapPings[#pendingCapPings + 1] = capDeal
      end
      return { isCommodity = true, levels = levels, avail = avail, decision = capDecision }
    end
    -- The floor rose back above the cap (or the book emptied) -- forget the last announced
    -- price so the NEXT time this item dips under the cap, even at the same price as before,
    -- it rings again as the new opportunity it is, instead of staying silenced by a price the
    -- board hasn't shown in a while.
    GC.Caps.Forget(itemID)
  end
  return {
    isCommodity = true,
    levels = levels,
    avail = avail,
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
      if frame then frame.status:SetText(GC.L["live safety confirmed -- click Buy to purchase"]) end
    elseif not live.isCommodity and decision.status == "WATCH" and decision.candidate then
      -- Sniper phase 2: a realm lot, checked live and found under its region reference. The
      -- decision is deliberately not `buyable` -- nothing here measured how fast this item
      -- sells -- so this arms its own way rather than through armReady, and the button says
      -- what it is: a buy the player is making on their own judgement, not on a verdict.
      row.purchaseStage = "ready"
      row.purchaseDeal = nil
      row.decisionSnapshot = decision
      row.quoteSnapshot = nil
      activeItemID[deal.itemID] = true
      if dialog and dialog.row == row then
        hideRequoteBanner()
        setPrimaryLabel(GC.L["BUY — unverified"])
        setDialogHeader(deal, decision)
        stampDialogFromDecision(deal, decision)
        -- Affordability, checked here rather than through updateBuyAffordance: that helper
        -- ends by writing "price confirmed -- click Buy to purchase" in green, which is a
        -- promise this path is not allowed to make.
        local total = decision.candidate.buyout
        if total > GetMoney() then
          dialog.primaryBtn:Disable()
          setDialogStatus((GC.L["not enough gold -- total %s, you have %s"])
            :format(GC.Util.FormatMoney(total), GC.Util.FormatMoney(GetMoney())), 1, 0.3, 0.3)
        else
          dialog.primaryBtn:Enable()
          setDialogStatus(GC.L["price checked, sale speed unknown -- this one is your call"], 1, 0.82, 0)
        end
      end
      scheduleArmTimeout(row, deal, decision)
    else
      -- A sentence, not the engine's token: "source_stale" names the gate, it does not tell the
      -- player that the import is two hours old and that a Companion sync needs a /reload to be
      -- seen. The token itself is still on the reason line and in the diagnostic above it.
      armCheck(row, deal, decision,
        GC.SniperDecision.ReasonText(decision.reasons[1] or "live_verification_required"), false)
    end
  else
    showGoneState(row, GC.L["listing gone -- already bought out or price changed"])
    if deals[itemID] then deals[itemID] = nil end
    if GC.Sniper._realmDeals then GC.Sniper._realmDeals[itemID] = nil end -- same reason as consumePurchasedDeal
    for i = #scanDeals, 1, -1 do
      if scanDeals[i].itemID == itemID then table.remove(scanDeals, i) end
    end
    if frame then frame.status:SetText(GC.L["gone / price changed"]) end
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
      setDialogStatus(GC.L["no purchase confirmation received -- Cancel and retry"])
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
  -- An unconfirmed tombstone that OnCommodityPriceUpdated stamped with this exact requery
  -- (row + token) is retired here rather than by its 20s timer; see _RetireFencedTombstone.
  GC.Sniper._RetireFencedTombstone(attempt.row, attempt.token)
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
      if attempt.sent then GC.Sniper._FenceDrain(itemID, attempt) end
      applyRequeryResult(attempt.row, itemID, nil)
      GC.Sniper._ResumePausedLiveRequery(attempt)
    end
  end)
end

-- Returns the attempt it registered, or nil when no query could be started (an older sent
-- search for this item still has to drain first). A caller that fences something on the new
-- attempt's token -- the requote tombstone below does -- has to be able to tell the two apart:
-- a fence stamped with a token no attempt carries is never consumed, and the tombstone then
-- refused every commodity Buy for its full drain window even after a fresh Check had answered.
local function startRequery(row, deal)
  local itemID = deal.itemID
  local draining = GC.Sniper._DrainFence(itemID)
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
    setDialogStatus(GC.L["waiting for previous search result to settle"], 1, 0.82, 0)
    if frame then frame.status:SetText(GC.L["waiting for previous search result to settle"]) end
    return nil
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
  if frame then frame.status:SetText(GC.L["checking live price..."]) end

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
  return attempt
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
  -- the quiet zone is open while a purchase attempt is mid-flight server-side (armed/
  -- requerying/buying/confirming on some row, not necessarily this one), so a pre-warm still
  -- never competes with a real buy requery on the shared throttled message system. Pre-warm
  -- MAY fire during a scan now: it's ready-gated (driver.isReady() below, plus the "one
  -- pre-warm in flight globally" slot), so at worst it costs the scan a single browse-page
  -- throttle slot for one cycle -- a one-cycle pagination delay, not starvation.
  if GC.Sniper.IsPurchaseQuiet() then return end
  if prewarmAttempt then return end -- one pre-warm in flight globally
  if not driver.isReady() then return end -- never parks -- see comment above

  local itemID = deal.itemID
  if GC.Sniper._DrainFence(itemID) then return end -- an old untagged result must drain first
  -- Same item-key-not-cached guard startRequery uses, but pre-warm just skips instead of
  -- chasing ITEM_KEY_ITEM_INFO_RECEIVED -- this is a best-effort warm, not a purchase the
  -- player is blocked on; the dialog's own startRequery fallback still does the real,
  -- patient wait if the player clicks Buy before the key is ever resolved.
  if not driver.getKeyInfo(itemID) then return end
  -- The last gate before the query goes out, and the only one that costs anything: under a
  -- throttle flag that has stopped changing, this is the addon's forced send for the window,
  -- and the Sell tab's pricing walk gets its own. Asked HERE rather than beside the isReady
  -- read above so a decline further up (a cached warm, an uncached key) never spends it.
  if driver.claimSend and not driver.claimSend() then return end

  prewarmToken = prewarmToken + 1
  local attempt = { itemID = itemID, token = prewarmToken, deal = deal, sent = true }
  prewarmAttempt = attempt
  driver.sendSearch(itemID)

  -- Ultimate fallback so a pre-warm that never gets a matching event (or one whose deal was
  -- superseded before it landed) can't wedge the "one in flight globally" slot shut forever.
  C_Timer.After(LIM.REQUERY_TIMEOUT_SECONDS, function()
    if prewarmAttempt == attempt then
      prewarmAttempt = nil
      GC.Sniper._FenceDrain(itemID, attempt)
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
  -- Sniper phase 2: a realm lot the check found under its region reference. It is not buyable
  -- and never will be -- nothing measures how fast a realm item sells -- but it was not
  -- REFUSED either, and the refused-rows filter below must not treat it as one. Without this
  -- flag every realm row disappeared from the board the moment its own check came back, which
  -- is the one moment it finally had something to say.
  local unverified = (decision and decision.candidate and decision.status == "WATCH") and true or nil
  local status, reason
  if not data then
    status, reason = "Gone", GC.L["listing gone -- bought out or repriced"]
  else
    status = decision and decision.status or "WATCH"
    local token = decision and decision.reasons and decision.reasons[1]
    reason = GC.SniperDecision.ReasonText(token or "live_verification_required")
  end
  verdicts[deal.itemID] = {
    unitPrice = deal.unitPrice, at = GetTime(), manual = kept,
    buyable = buyable, unverified = unverified, status = status, reason = reason,
    stressProfit = data and data.decision and data.decision.stressProfit,
    -- Live price caps, addon task 6: carried through so GC.BoardRows.Bucket/Label (read off
    -- THIS table, not off `decision` directly -- see verdictFor) can rank/label a cap row ahead
    -- of an ordinary SAFE/WATCH one. GC.Caps.DecideRealm/DecideCommodity both set it.
    cap = decision and decision.cap or nil,
  }
  refreshRows()

  -- A row leaving the board has to account for itself where the player is looking. The count on
  -- the toolbar toggle is the standing answer, but it is a number on a button nobody watches,
  -- and refusals do not arrive evenly: the walk competes for one throttled slot, so a run of
  -- them lands together and the list visibly shortens with nothing on screen explaining it.
  -- Reported here, at the one place a verdict is ever recorded, rather than from renderList --
  -- that runs on hover and on every repaint, and a status line that fires on hover would say
  -- this over and over about rows that left minutes ago. `manual` is excluded because a Check
  -- the player ran themselves never removes its own row (see this function's own contract) and
  -- announcing a removal that did not happen is its own lie. refreshRows above has already
  -- recomputed refusedCount, so the number quoted is the one the toggle is about to show.
  if not manual and not buyable and not unverified and not isPinned(deal.itemID) and refusedCount > 0 then
    setStatus((GC.L["%d hidden -- the live check refused them"]):format(refusedCount), 4)
  end

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
-- One step of the walk: pick the row that most needs a live look and spend one query on it.
-- Returns true only if a query actually went out, which is what makes it usable as a slot
-- consumer -- see GC.Sniper.OnThrottleReady, where "does the walk want this slot" is answered
-- by trying to take it. Deliberately does NOT gate on driver.isReady(): the arbiter calls this
-- from inside the throttle-ready handler, where readiness is the event's own premise, and
-- maybeStartPrewarm re-checks it anyway before sending.
-- Everything that makes the walk stand down no matter whose turn it is. Its own function
-- because BOTH entry points need it and they need it at different moments: the arbiter asks
-- before offering a slot, the ticker asks before spending its once-a-second turn -- and a
-- stood-down walk must not burn that turn, which is the whole reason this is checked ahead of
-- the clock rather than inside the walk.
local function verifyWalkStandsDown()
  -- Shared throttle budget: while the player is busy on Blizzard's own AH panes -- posting,
  -- buying a browse result, or reading their own search -- their click outranks this
  -- background walk.
  if GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy and GC.AuctionHouseTab.PlayerIsBusy() then return true end
  if not ahOpen then return true end
  if view ~= "deals" then return true end -- the Sell tab is up; verifying what nobody is reading just costs throttle
  if not frame or not frame:IsShown() then return true end
  if prewarmAttempt then return true end -- one query in flight globally, shared with the hover pre-warm
  if GC.Sniper.IsSearchCritical() then return true end -- a Check or a purchase owns the search slot
  return false
end

-- The walk's slice of the board: the first LIM.VERIFY_TOP_ROWS rows that can become BUY --
-- commodities, and rows whose item key is not cached yet, which are treated as such until
-- known -- followed by the first LIM.VERIFY_TOP_ROWS realm rows (gear, pets, recipes). One
-- slice in plain board order used to serve both, and the moment realm rows joined the board
-- (0.9.0) their five-figure leads filled the top 24 outright: every commodity sat below the
-- cut, never got its first look, and the board showed no BUY for hours -- "it only finds
-- items now". A realm row can only ever verify to WATCH (armReady refuses it), so it must not
-- starve the rows the walk exists for; it still gets its facts, after them. Published as a
-- field rather than a new top-level local: this file is at its 200-local ceiling.
--
-- Since the two boards (0.9.2) the list handed in only ever holds ONE of the two kinds, so the
-- split below is no longer what saves the commodities -- the board switch is. It is kept
-- because it costs one already-cached lookup per row and because it is the cheaper guarantee
-- of the two: nothing here has to know which store the caller read.
function GC.Sniper._VerifySlice(list)
  local slice, realmRows = {}, {}
  for i = 1, #list do
    local deal = list[i]
    -- `deal.isCommodity` is not an answer to "is this a commodity". Every row the scan puts on
    -- the board is built with isCommodity = false -- Core/FullScan.lua fills that field in as a
    -- constant, and so does the realm poll -- so reading it put EVERY row in the realm half and
    -- the split this function exists for never happened in the game at all. Only a live
    -- commodity check ever sets it TRUE (applyRequeryResult); anything else is unknown, and the
    -- client is asked instead. An item key the client has not cached yet answers nil, which
    -- counts as commodity-capable: a row must never be parked behind the gear on a fact nobody
    -- has yet.
    local info = deal.isCommodity ~= true and driver.getKeyInfo(deal.itemID) or nil
    local realm = info ~= nil and not info.isCommodity
    if realm then
      if #realmRows < LIM.VERIFY_TOP_ROWS then realmRows[#realmRows + 1] = deal end
    elseif #slice < LIM.VERIFY_TOP_ROWS then
      slice[#slice + 1] = deal
    end
  end
  for i = 1, #realmRows do slice[#slice + 1] = realmRows[i] end
  return slice
end

local function stepVerifyWalk()
  if verifyWalkStandsDown() then return false end

  local now = GetTime()
  -- The slice the last render published (see renderList), not a fresh one: same list, none of
  -- the work. Only a walk that runs before anything has ever rendered builds its own.
  local list = GC.Sniper._verifySlice or GC.Sniper._VerifySlice(renderList())
  local limit = #list

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
        if maybeStartPrewarm(deal, true) then
          verifyWalkAt = now + LIM.VERIFY_WALK_SECONDS
          return true
        end
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
          if maybeStartPrewarm(deal, true) then
            verifyWalkAt = now + LIM.VERIFY_WALK_SECONDS
            return true
          end
        end
      end
    end
  end
  return false
end

-- The ticker path. The arbiter (GC.Sniper.OnThrottleReady) is where the walk gets its slot
-- while anything else is competing for one; this is what keeps it moving when nothing is --
-- an idle Auction House produces no throttle-ready traffic to ride on, and the walk still has
-- rows to cover. Readiness is checked BEFORE the once-a-second gate, deliberately: letting a
-- busy moment consume the walk's turn meant the turn was mostly spent at the one instant it
-- could do nothing, with the next opening a whole second away.
local function tickAutoVerify()
  -- Stand-down first, readiness second. The two used to be the other way round, which cost
  -- nothing while readiness was a plain read -- and everything while it was not: the old
  -- GC.Util.ThrottleReady spent a forced permit on being ASKED, so this line took the addon's
  -- one send under a stuck flag four times a second and then handed it to a walk that was
  -- standing down anyway. Nobody else got a turn. Readiness is now a pure read (see
  -- Core/Util.lua) and the permit is claimed where a query is actually issued.
  if verifyWalkStandsDown() then return end
  if not driver.isReady() then return end
  local now = GetTime()
  if now < verifyWalkAt then return end
  -- Stamped before the walk rather than after a successful send: the walk sorts and filters the
  -- whole deals list, and re-running that four times a second only to find nothing due is the
  -- cost this gate exists to avoid. Everything that could make the turn a waste has already
  -- been asked above, so what is being spent here is a turn the walk genuinely wanted.
  verifyWalkAt = now + LIM.VERIFY_WALK_SECONDS
  stepVerifyWalk()
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
-- Sniper phase 2: a keys batch answers on the SAME browse events a pass does, and replaces the
-- browse buffer with its own rows. While one is outstanding those rows belong to the poll, not
-- to a pass -- and the arbiter never grants a keys call while a pass is paging, so the two can
-- never be waiting on the same event. Both browse events are routed here rather than only the
-- documented one: if a client ever answers a keys call with the "added" event instead, the
-- poll still folds its results rather than silently stalling out for the whole session.
-- Whether a keys batch is still waiting for its browse event. Also where that wait is given
-- up: _keysBatch is dropped with it, because it is the list of items the fold treats as
-- "asked about" -- left behind, the NEXT fold (a later batch, or a browse page that arrives
-- after the timeout) reads a stale list and deletes realm rows nobody asked about this time.
function GC.Sniper._KeysOutstanding()
  local sentAt = GC.Sniper._keysAwaiting
  if not sentAt then return false end
  local limit = GC.Sniper._keysOwner == "sell" and LIM.KEYS_SELL_TIMEOUT_SECONDS
    or LIM.KEYS_TIMEOUT_SECONDS
  if (time() - sentAt) < limit then return true end
  GC.Sniper._keysAwaiting = nil
  GC.Sniper._keysBatch = nil
  GC.Sniper._keysOwner = nil
  return false
end

-- Two consumers share the one outstanding batch: the Items board's realm poll ("sniper") and
-- the BUY tab's floor refresh ("buy"). They can never both want it -- each is gated on its own
-- tab being the one on screen -- but the ANSWER arrives as an untagged browse event either
-- way, so the batch has to say whose it was. _keysOwner is that record, written beside
-- _keysAwaiting by whichever sender spent the slot and cleared on every path that gives the
-- wait up. Without it a BUY refresh's rows would be folded into the realm poll, which reads a
-- silence about an item as "sold out" and would wipe the Items board on every BUY refresh.
function GC.Sniper._FoldKeysBatch()
  -- An expired wait is not a wait. _KeysOutstanding gives it up (and drops the list of items
  -- it asked about with it), so a browse page arriving long after the batch was written off is
  -- the PASS's page and is folded as one -- rather than being read as the batch's answer and
  -- deleting every realm row that answer does not mention.
  if not GC.Sniper._KeysOutstanding() then return false end
  trace("keys: answer landed after " .. (time() - GC.Sniper._keysAwaiting) .. "s")
  local owner = GC.Sniper._keysOwner
  GC.Sniper._keysAwaiting = nil
  GC.Sniper._keysOwner = nil
  local browsed = C_AuctionHouse.GetBrowseResults()
  if owner == "buy" then
    -- The realm poll's own fold is what normally consumes _keysBatch (see its onRows driver);
    -- BUY's does not need the list, so it is dropped here rather than left to be read as the
    -- NEXT batch's "what we asked about".
    GC.Sniper._keysBatch = nil
    if GC.Buy and GC.Buy.FoldRefresh then GC.Buy.FoldRefresh(browsed) end
    return true
  end
  if owner == "sell" then
    -- The Sell tab's bulk price fill: same one batch, same reason to drop the asked-about
    -- list here -- the realm poll's fold would read it as its own.
    GC.Sniper._keysBatch = nil
    if GC.Sell and GC.Sell.FoldBulk then GC.Sell.FoldBulk(browsed) end
    return true
  end
  GC.Sniper._keyPoll:Fold(browsed)
  -- The cycle is over once nothing is left to hand out; the Items board's own loop starts
  -- the next one after a breather (see _TrySendKeysBatch).
  if not GC.Sniper._keyPoll:HasPending() then GC.Sniper._keysCycleDoneAt = time() end
  return true
end

-- AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED (Core/Init.lua). The client is saying it threw one
-- of our throttled messages away -- so whatever was waiting for the reply is waiting for
-- nothing. It was counted for `/gc sell` and nothing else, and the waits then ran their full
-- course: eight seconds of the one search slot held by a pre-warm whose answer had already been
-- discarded, and a keys batch that stopped the realm poll for the same eight.
--
-- The event carries no identity, so this cannot prove the dropped message was ours. It is still
-- the right trade: the worst case is a live pre-warm abandoned early, which costs one wasted
-- query and stamps no verdict -- against a search slot wedged shut for everyone. Deliberately
-- NOT fenced into requeryDraining either: a message that never reached the server cannot
-- produce the late untagged result that fence exists for.
function GC.Sniper.OnThrottledMessageDropped()
  GC.Sniper._keysAwaiting = nil
  GC.Sniper._keysBatch = nil
  GC.Sniper._keysOwner = nil
  prewarmAttempt = nil
  -- Re-arm whoever is next rather than waiting for a readiness event that may not come: the
  -- arbiter sends at most one message and refuses on its own if the system is genuinely busy.
  -- Claimed like any other send this addon makes off its own clock -- a client that is dropping
  -- messages must not be answered with one more message per drop.
  if driver.isReady() and (not driver.claimSend or driver.claimSend()) then
    GC.Sniper.OnThrottleReady()
  end
end

function GC.Sniper.OnBrowseResults()
  if GC.Sniper._FoldKeysBatch() then return end
  if not GC.Sniper._bookPass:IsPaging() then return end -- not our scan; ignore a manual Blizzard AH browse
  -- A pass that has not sent its query yet has no page to receive: whatever this event
  -- carries (a keys answer written off as lost, the player's own browse) is not ours.
  if GC.Sniper._bookPass:PendingStart() then return end
  lastBrowseEventAt = time()
  trace("pass: page landed")
  GC.Sniper._bookPass:OnResultsUpdated()
end

function GC.Sniper.OnBrowseResultsAdded()
  if GC.Sniper._FoldKeysBatch() then return end
  if not GC.Sniper._bookPass:IsPaging() then return end
  if GC.Sniper._bookPass:PendingStart() then return end -- see OnBrowseResults
  lastBrowseEventAt = time()
  GC.Sniper._bookPass:OnResultsAdded()
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
  local ok, sent = pcall(scanner.OnSystemReady, scanner)
  watchGrant = false
  -- The loop reports back whether a search actually went out, and a turn it did not spend is
  -- not the arbiter's to report as spent: Core/Scanner.lua's advance() sends nothing when every
  -- item in the set is waiting on an item key the client has not cached, and the verify walk
  -- behind it went hungry for a query nobody made. Only an explicit `false` counts as "did not
  -- send": a scanner that threw (ok == false) is treated as before -- the turn was spent trying
  -- -- and so is any older caller whose answer is nothing at all.
  if ok and sent == false then return false end
  -- Cycle time is MEASURED, never estimated: this project has not measured Blizzard's throttle
  -- interval and will not invent one. Count grants against the set size; every time the count
  -- wraps, one full pass has completed and its wall-clock is the number the UI shows.
  -- A wrap is the loop landing back on the item it started this pass on, which takes one MORE
  -- grant than the set has members (n grants visit every member once; the (n+1)th repeats the
  -- first) -- ">=" here would stamp every pass one grant short, permanently, not just the
  -- first. The grant that detects the wrap is also the first grant of the next pass, so the
  -- count restarts at 1 for it rather than 0. Counted even if the pcall above just swallowed a
  -- throw: the arbiter still spent this turn on the watch loop, and that is what is being
  -- timed -- not whether the scanner's own bookkeeping succeeded. A turn that sent nothing has
  -- already returned above and is not counted -- it visited nobody, so it timed nothing.
  GC.Sniper._grants = (GC.Sniper._grants or 0) + 1
  if #GC.Sniper._liveTargets > 0 and GC.Sniper._grants > #GC.Sniper._liveTargets then
    local started = GC.Sniper._passStartedAt
    if started then GC.Sniper._cycleSeconds = GetTime() - started end
    GC.Sniper._passStartedAt = GetTime()
    GC.Sniper._grants = 1
  end
  return true
end

-- The cheap global preconditions maybeStartPrewarm checks before it will send anything: no
-- AH session, a pre-warm already in flight, the quiet zone, or a throttle that is not
-- ready all refuse every caller equally, whatever item is asked about. Asked FIRST, before the
-- drill queue is charged for a send, because a queue that charges for a refusal lets one
-- undrillable item spend the whole 60/min budget on nothing. The per-item guards
-- (uncached item key, the drain fence, a still-fresh cached pre-warm) stay inside
-- maybeStartPrewarm -- they are what the returned "did it actually send" answer is for.
local function canDrillNow()
  if not ahOpen then return false end
  -- Same two gates the verify walk stands down for (verifyWalkStandsDown). A drill is a
  -- background query against the deals board: with the Sell tab on screen nobody is reading
  -- what it answers, and while the player is working Blizzard's own auction house panes their
  -- click outranks it. Without these the drill queue took slots out from under the Sell tab's
  -- pricing walk and out from under the player's own search.
  if view ~= "deals" then return false end
  if GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy and GC.AuctionHouseTab.PlayerIsBusy() then return false end
  if prewarmAttempt then return false end
  if GC.Sniper.IsPurchaseQuiet() then return false end
  return driver.isReady() and true or false
end

-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY handler: a parked authoritative Check always consumes
-- the next slot before anything else -- the Check has already stopped Live in startRequery, so
-- this works in watchlist mode without a scanner collision. Below that, a queued drill-down
-- outranks the book pass's own send: a drill-down is a specific item the pass already flagged
-- as worth a live look, and design doc §3 wants that live look before the pass pages on to the
-- next batch of rows. The book pass's own send comes next -- not a background page like the
-- old round-robin "browse" slot, but the one send that keeps the loop discovering anything at
-- all -- and only what is left (the watch loop and the verify walk) alternates turns, so
-- whichever of the two is hungry alone takes every slot instead of one going idle.
-- One keys batch for the Items board, if this is a moment one may go: the Items board is on
-- screen, the poll has something to ask, no batch is out, no pass is paging, the browse
-- buffer is settled, the player is not busy on Blizzard's panes, and the throttle will take
-- it. Returns true when a batch was sent.
--
-- Called from three places, and the last two are the fix for a board that never filled:
-- the ready-tick arbiter (step 3 below), the end of every pass, and the switch to the Items
-- board. Under Auto a pass pages back to back, and the one ready tick that follows its last
-- page arrives BEFORE that page lands -- so at every tick the pass was still paging, and in
-- the breather between passes no tick comes at all. 362 targets, `pending=true`, and not one
-- batch sent in thirteen passes, measured in game. The end of a pass is exactly the settled
-- buffer this batch needs, so it is asked for there; the next pass then waits on the answer
-- (passWants is gated on _KeysOutstanding, and so is Auto's start below).
--
-- Generalised over WHO is asking, because the BUY tab needs the same one batch on the same
-- one interlock (see _FoldKeysBatch's _keysOwner note): `poll` answers HasPending()/NextBatch()
-- like Core/KeyPoll.lua does, `wants()` is the caller's own "is my board the one on screen"
-- predicate, and `who` is the name the answer comes back under. Everything below `wants()` is
-- addon-wide law and is deliberately NOT the caller's to override: one batch outstanding, never
-- across a pass's browse buffer, never while the player is using Blizzard's own panes.
function GC.Sniper._TrySendKeysBatchFor(poll, who, wants, playerBusy)
  if playerBusy == nil then
    playerBusy = (GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy
      and GC.AuctionHouseTab.PlayerIsBusy()) or false
  end
  -- "Buffer settled" is asked as "no pass fetching or about to" -- not as
  -- HasFullBrowseResults(): opening the auction house straight onto the Items board has sent
  -- no browse at all, so that answer is false until a pass runs, and with the pass paused for
  -- this board it never does. The board sat empty from the first second, measured in game.
  if not (wants() and not playerBusy
      and poll:HasPending() and not GC.Sniper._bookPass:IsPaging()
      and not GC.Sniper._bookPass:PendingStart()
      and not GC.Sniper._KeysOutstanding()) then
    return false
  end
  if not driver.isReady() then return false end
  -- Claimed under the asker's own name: GC.Util.ClaimThrottleSend paces one forced send per
  -- consumer per stuck window, so BUY's refresh and the Items poll do not spend each other's.
  -- driver.claimSend is the Sniper's own spelling of that call and stays the path for "sniper",
  -- since specs that load this file without Core/Util.lua rely on its "no pacing" fallback.
  if who == "sniper" then
    if driver.claimSend and not driver.claimSend() then return false end
  elseif GC.Util and GC.Util.ClaimThrottleSend and not GC.Util.ClaimThrottleSend(who) then
    return false
  end
  local batch = poll:NextBatch()
  if not batch or #batch == 0 then return false end
  local keys = {}
  for i = 1, #batch do keys[i] = C_AuctionHouse.MakeItemKey(batch[i]) end
  GC.Sniper._keysAwaiting = time()
  GC.Sniper._keysOwner = who
  -- What this batch asked about, by name. The fold needs it to tell "no row came back for
  -- this item" (sold out, or repriced) from "this item was not in the batch at all".
  GC.Sniper._keysBatch = batch
  -- The cycle counters are the Items poll's own accounting (`/gc board` reports them against
  -- its target set); a BUY refresh is not part of that cycle and must not inflate it.
  if who == "sniper" then
    GC.Sniper._keysThisCycle = (GC.Sniper._keysThisCycle or 0) + #keys
  end
  if GC.AuctionHouseTab and GC.AuctionHouseTab.NoteAddonSearch then GC.AuctionHouseTab.NoteAddonSearch() end
  trace("keys: SearchForItemKeys x" .. #keys .. " (" .. who .. ")")
  C_AuctionHouse.SearchForItemKeys(keys, {})
  return true
end

function GC.Sniper._TrySendKeysBatch(playerBusy)
  local poll = GC.Sniper._keyPoll
  -- The Items board keeps its own cycle going: with the pass paused for this board nothing
  -- else ever calls BeginCycle, so an exhausted cycle would be the last one of the visit.
  -- A breather between cycles keeps a small poll set from hammering the one search slot.
  if view == "deals" and GC.Sniper._Board() == "items" and poll:Count() > 0
      and not poll:HasPending() and not GC.Sniper._KeysOutstanding()
      and (time() - (GC.Sniper._keysCycleDoneAt or 0)) >= LIM.KEYS_CYCLE_BREATHER_SECONDS then
    GC.Sniper._keysLastCycle = GC.Sniper._keysThisCycle or 0
    GC.Sniper._keysThisCycle = 0
    poll:BeginCycle()
    trace("keys: new cycle (Items board)")
  end
  return GC.Sniper._TrySendKeysBatchFor(poll, "sniper", function()
    return view == "deals" and GC.Sniper._Board() == "items"
  end, playerBusy)
end

function GC.Sniper.OnThrottleReady()
  -- 1. A parked Check requery always wins outright: a player is waiting on it, and it has
  -- already stopped the loop as a courtesy besides.
  for itemID, attempt in pairs(pendingRequerySend) do
    pendingRequerySend[itemID] = nil
    if isCurrentRequeryAttempt(attempt) then
      attempt.sent = true
      driver.sendSearch(itemID)
      return
    end
  end

  -- A purchase attempt in flight (the quiet zone -- see GC.Sniper.IsPurchaseQuiet) owns the
  -- throttled search slot until it resolves. Nothing below this line may compete with it: not
  -- a drill-down, not the book pass's own page, not the watch loop, not the verify walk.
  -- Without this, a purchase confirmation waiting on its terminal event was still losing slots
  -- to the scan/watch/verify traffic underneath it, which is what stretched "confirming
  -- purchase..." out to 5-10s on a busy board -- the confirm call itself was never slow, the
  -- SLOT was busy. Asked as the zone, not as `next(activeItemID) ~= nil`: that read also
  -- counted a frozen row's permanent display pin, which stopped the board for good.
  if GC.Sniper.IsPurchaseQuiet() then return end

  -- Steps 3 and 4 below both REPLACE the client's single browse buffer -- the same buffer
  -- Blizzard's own Browse pane is showing when the player is using it. Nothing stopped them:
  -- the reported symptom was the player's Browse jumping to some item page with a spinner on it
  -- while they were reading their own search. Their pane outranks both. (Step 1 is the player's
  -- own Check, step 2 and the tail ask this for themselves.)
  local playerBusy = (GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy
    and GC.AuctionHouseTab.PlayerIsBusy()) and true or false

  -- 2. Queued drill-downs, bounded by DrillQueue's own per-minute budget. Runs the SAME search
  -- path startRequery/evaluateLive use (maybeStartPrewarm -> resolvePrewarm -> stampVerdict),
  -- never a dialog, never a purchase call.
  --
  -- Peek, then charge. Three outcomes, and only one of them costs a send: nothing can drill at
  -- all this turn (fall through to the book pass, budget untouched); the head is describing a
  -- floor the book has since moved off, so no query was ever worth making for it (dropped, no
  -- charge, and the next hit gets this turn instead -- once, so a queue full of stale entries
  -- cannot be walked in one tick); or it is live and sendable, in which case Pop charges and a
  -- per-item decline inside maybeStartPrewarm (uncached item key, the drain fence, a fresh
  -- cached pre-warm) re-queues it for the next ready tick.
  for _ = 1, 2 do
    local hit = GC.Sniper._drillQueue:Peek()
    if not hit or not canDrillNow() then break end
    -- Either book may be the one that saw this floor: commodities come from the book pass,
    -- realm items from the key poll, and neither knows about the other's items. The hit is
    -- still worth a query as long as ONE of them still shows the price it was queued for.
    local booked = GC.Sniper._bookPass:Book()[hit.itemID]
    if not booked or booked.floor ~= hit.floor then
      booked = GC.Sniper._keyPoll:Book()[hit.itemID]
    end
    if not booked or booked.floor ~= hit.floor then
      GC.Sniper._drillQueue:Drop(hit)
    else
      -- Pop is what charges the per-minute budget, and it REFUSES once that budget is spent.
      -- Its answer was thrown away: the drill went out anyway, past the budget, and the entry
      -- it never removed stayed at the head of the queue to do the same again on the next
      -- ready tick. No answer means no send.
      if not GC.Sniper._drillQueue:Pop() then break end
      if maybeStartPrewarm({ itemID = hit.itemID, unitPrice = hit.floor }, true) then return end
      -- Declined (an uncached item key, the drain fence, a fresh cached warm). Back in the
      -- queue carrying its ORIGINAL age, so a hit that can never be sent still ages out
      -- instead of sitting at the head for the rest of the session -- see Core/DrillQueue.lua.
      GC.Sniper._drillQueue:Push(hit)
      break
    end
  end

  -- 3. One batch of item keys (Core/KeyPoll.lua), and only between book-pass pages. A keys
  -- call REPLACES the browse buffer, so one granted mid-pass would delete the page the pass is
  -- still folding -- hence both guards: IsPaging() goes false the moment the last page lands,
  -- but HasFullBrowseResults() is what says the buffer is settled and not mid-fetch. The batch
  -- is capped at 100 keys inside NextBatch (more than 100 disconnects the client), and only
  -- one may be outstanding at a time; the timeout is there so a browse event that never
  -- arrives cannot stop the poll for the rest of the session.
  --
  -- HasPending() is asked FIRST on purpose: with no poll set (no import, or nothing realm-side
  -- worth watching) nothing below is evaluated and this costs one table lookup per slot.
  --
  -- Deals view only, like the watch loop and the verify walk below (and unlike the book pass,
  -- which Auto already pauses for the Sell tab). This batch is one throttled message per
  -- ready tick, and with a realm-side poll set of any size it is pending again the moment
  -- it lands -- so with the Sell tab on screen it took EVERY slot ahead of the pricing walk,
  -- which runs after this handler and only ever saw the flag false: "PRICING…" at 0/20,
  -- 121 ready events, not one of them ours. The player is looking at the Sell tab; the poll
  -- refreshes a board nobody is reading.
  --
  -- And the ITEMS board only (0.9.2), for exactly the same reason one step finer: this poll
  -- fills that board and no other, so on Commodities it was spending the slot on rows the
  -- player cannot see -- at the commodity scan's and the Sell walk's expense. Switching to
  -- Items resumes it on the next ready tick with no state to restore: HasPending() is true
  -- again the moment the cycle has anything left to ask about.
  if GC.Sniper._TrySendKeysBatch(playerBusy) then return end

  -- The BUY tab's floor refresh: the same one batch, the same interlock, one board lower. It
  -- can never contend with the line above -- that one runs only on Deals, this one only on
  -- BUY -- so the order between them is arbitrary and the pair together is still at most one
  -- throttled message per grant. It sits above the pass and the tail for the reason the Items
  -- batch does: the player is looking at the board it fills, and its prices are what the next
  -- click spends gold on.
  if GC.Buy and GC.Buy.TrySendRefresh and GC.Buy.TrySendRefresh(playerBusy) then return end

  -- 4 and 5 ALTERNATE. The book pass and the tail below (the watch loop and the verify walk)
  -- take every other grant when both want one, and every grant when only one of them does.
  --
  -- The pass used to win outright, and that was measured wrong in the client: with Auto on,
  -- rows sat on "..." for five minutes and never got a verdict, then every one of them got
  -- one within seconds of Auto being switched off. Discovery is worth first refusal, but it
  -- is not worth the whole slot: a browse page finds new floors, and only the verify walk
  -- turns a row on screen into an answer. A pass that never yields is a board that never
  -- speaks. With Auto's two-second breather the pass is pending again almost immediately, so
  -- "outright" meant "always".
  --
  -- Wants() is asked rather than tried, because OnThrottleReady both answers and acts.
  -- Not while a keys batch is still outstanding. Both answer on the SAME browse events and
  -- both replace the client's one browse buffer, so a page sent under an outstanding batch is
  -- folded into the poll instead of into the pass (_FoldKeysBatch runs first and returns) --
  -- the pass loses the page it was waiting for, and the fold, believing the page is the batch's
  -- own answer, deletes every realm row the batch had asked about. The batch is capped at
  -- LIM.KEYS_TIMEOUT_SECONDS, so this can never hold the pass for long.
  local passWants = GC.Sniper._bookPass:Wants() and not playerBusy
    and not GC.Sniper._KeysOutstanding()
  if passWants and GC.Sniper._slotTurn ~= "tail" then
    if GC.Sniper._bookPass:OnThrottleReady() then
      GC.Sniper._slotTurn = "tail"
      return
    end
  end

  -- 5. What's left: the watch loop and the verify walk, round-robin, exactly as before minus
  -- "browse" (now item 4 above). Both stand down when the Deals view isn't the one on screen --
  -- polling for a screen nobody is looking at was never the point, and the Sell tab is the
  -- consumer that starves first when a background loop treats every ready tick as its own.
  --
  -- The verify walk running here at all is a bug fix, not a tidy-up. It used to live only on
  -- the 0.25s ticker, sending only if it happened to catch the throttled system idle -- but
  -- this handler gives the slot away synchronously the instant it opens, so under Auto, with
  -- the browse scan always hungry, the ticker essentially never saw an idle moment. The walk
  -- therefore only ran once the scan STOPPED. That is the whole of "stopping the scan deleted
  -- my deals": the rows had been sitting there unverified the entire time, and stopping is
  -- simply when the checks finally got to run and refuse them.
  --
  -- Round-robin rather than a two-way boolean: begin at whoever follows the last one served and
  -- take the first that is hungry, so a consumer with nothing to do never costs a slot and
  -- neither can starve the other. The walk is asked by TRYING it -- deciding whether it wants a
  -- slot is the same work as taking one, so stepVerifyWalk both answers and acts.
  --
  -- Note: the verify walk already skips a row with a fresh verdict (stepVerifyWalk's pass-1
  -- check), and a drill-down verdict lands in the exact same verdicts table via stampVerdict --
  -- so "the verify walk keeps running only for rows that have no drill-down verdict" (design
  -- doc §3) is already true with no further guard needed here.
  for step = 0, #SLOT_ORDER - 1 do
    local index = (slotTurn - 1 + step) % #SLOT_ORDER + 1
    local who = SLOT_ORDER[index]
    local served = false
    if who == "watch" then
      local scanner = GC.Sniper.scanner
      if scanner and scanner.Wants and view == "deals" and scanner:Wants() then
        served = GC.Sniper._GrantWatchSlot()
      end
    else
      served = stepVerifyWalk()
    end
    if served then
      slotTurn = index % #SLOT_ORDER + 1
      GC.Sniper._slotTurn = "pass"
      return
    end
  end

  -- Neither of the two wanted the turn the pass just yielded, so it is the pass's after all.
  -- This is what keeps "alternate" from manufacturing idle slots: a tail with nothing to do
  -- never costs the scan a page.
  if passWants and GC.Sniper._bookPass:OnThrottleReady() then
    GC.Sniper._slotTurn = "tail"
    return
  end
  trace("arbiter: slot unused (passWants=" .. tostring(passWants) .. ")")
end

-- ---------------------------------------------------------------------------
-- The quiet zone: the one predicate every search sender asks before it sends.
--
-- It replaces `next(activeItemID) ~= nil`, which was the wrong question in both directions.
-- activeItemID is a DISPLAY pin as well as a purchase pin -- resolvePurchase's "frozen" branch
-- (a server success with no final quote) sets it deliberately for the rest of the AH session,
-- so one such purchase used to veto every drill-down, book-pass page, watch poll and verify
-- check until the player closed the auction house: the board froze on "AUTO · SCANNING" with
-- every row showing "..." and no verdict ever landing again. And it was too narrow the other
-- way: a commodity purchase that owns the client's single commodity flow (commodityPurchase /
-- the commodityDraining tombstone) is not necessarily pinned to any row's itemID at all.
--
-- What the zone protects is the client's ONE commodity-search buffer and the throttled search
-- slot the player is waiting on. A stage is quiet when the answer to "is something of ours
-- outstanding at the server for this row" is yes: the live requery a Check is waiting on, the
-- server quote and its Confirm, the confirm itself. "check", "expired" and "frozen" are not:
-- nothing is in flight, the player is reading, and the board must keep working underneath.
--
-- Nor is "ready", and counting it as quiet was the expensive mistake. An armed quote has nothing
-- outstanding at the auction house: the numbers are already in, and the addon is waiting on a
-- human being to read them and click. Counting it as quiet froze every search consumer in the
-- addon for as long as the dialog stood there -- LIM.ARM_TIMEOUT_SECONDS of a dead board, and
-- the Sell tab stuck on "Waiting for the purchase to finish…" -- for a purchase nobody had
-- made yet. Nothing about the gold depends on the freeze: the Buy click spends from the
-- immutable decision snapshot the Check already took (see onDialogPrimaryClick), not from the
-- client's search buffer, so a background search cannot move a single number the player is
-- reading. Everything from the purchase call onward stays quiet, exactly as before.
function GC.Sniper._StageIsQuiet(stage)
  return stage == "requerying" or stage == "buying"
    or stage == "confirm" or stage == "requote" or stage == "confirming"
end

-- The raw read, with no expiry: is the zone open right now. Split out from IsPurchaseQuiet
-- below so the bounded veto can ask the same question again after it has released what it can.
function GC.Sniper._QuietZoneOpen()
  if commodityPurchase or commodityDraining then return true end
  local shown = dialog and dialog.row
  if shown and GC.Sniper._StageIsQuiet(shown.purchaseStage) then return true end
  for i = 1, #rows do
    local stage = rows[i].purchaseStage
    -- Cheap first: a pooled row is idle (stage nil) almost always, and this runs on every
    -- throttle-ready event.
    if stage and GC.Sniper._StageIsQuiet(stage) then return true end
  end
  return false
end

-- The bounded half of the veto. Commodity purchase events carry no attempt identifier and, as
-- this batch learned the hard way, may never arrive at all: an "Internal auction error" fires
-- none of the three terminal events, so the attempt that raised it holds the zone open for
-- good. Everything still mid-flight is therefore returned to the player as a Check they can
-- re-run, the unconfirmed tombstones are dropped, and the board starts moving again.
--
-- Never touches a CONFIRMED attempt (in either slot) or the row it owns: gold may have moved,
-- so freeing that row for a silent retry could buy the same lot twice. Those settle through
-- their own terminal event or GC.Sniper._ReleaseStrandedConfirmed, and the row they own is
-- released by the NEXT window once that has happened.
function GC.Sniper._ReleaseQuietZone()
  local note = GC.L["no answer from the auction house"] .. GC.L[" — Check again"]
  for i = 1, #rows do
    local row = rows[i]
    local stage = row.purchaseStage
    local owned = (commodityPurchase and commodityPurchase.confirmed and commodityPurchase.row == row)
      or (commodityDraining and commodityDraining.confirmed and commodityDraining.row == row)
    if stage and GC.Sniper._StageIsQuiet(stage) and not owned then
      local deal = row.purchaseDeal or row.deal
      if deal and deal.itemID then
        -- Retire the requery bookkeeping exactly as scheduleRequeryTimeout does: a search that
        -- was actually sent still has to drain before a new authoritative Check can exist, or
        -- its late untagged result becomes a quote for the next click.
        local attempt = awaitingRequery[deal.itemID]
        awaitingRequery[deal.itemID] = nil
        awaitingKeyInfo[deal.itemID] = nil
        pendingRequerySend[deal.itemID] = nil
        if attempt and attempt.sent then GC.Sniper._FenceDrain(deal.itemID, attempt) end
        armCheck(row, deal, nil, note, true)
      else
        row.purchaseStage = nil
        row.purchaseDeal = nil
      end
    end
  end
  local pending = commodityPurchase
  if pending and not pending.confirmed then
    -- Non-protected, and the same settle abortRowPurchase performs: an opened server session
    -- must not be left hanging just because nothing answered it here.
    if not pending.cancelRequested then
      C_AuctionHouse.CancelCommoditiesPurchase()
      pending.cancelRequested = true
    end
    commodityPurchase = nil
  end
  if commodityDraining and not commodityDraining.confirmed then commodityDraining = nil end
  refreshRows()
end

function GC.Sniper.IsPurchaseQuiet()
  -- The BUY tab owns the shared commodity purchase slot right now -- the same veto a sniper
  -- attempt would hold. GC.PurchaseSlot.MAX_SECONDS expires nothing by itself; IsBusy() is what
  -- applies that bound, so a leaked BUY claim cannot veto the scanner/pre-warm/drill queue/
  -- arbiter for the rest of the session the way a bare Owner() check would.
  if GC.PurchaseSlot and GC.PurchaseSlot.Owner() == "buy" and GC.PurchaseSlot.IsBusy() then return true end
  if not GC.Sniper._QuietZoneOpen() then
    GC.Sniper._quietSince = nil
    return false
  end
  local now = GetTime()
  if not GC.Sniper._quietSince then
    GC.Sniper._quietSince = now
    return true
  end
  if now - GC.Sniper._quietSince <= LIM.QUIET_ZONE_MAX_SECONDS then return true end
  -- A dialog on screen keeps the zone for as long as it is up: the player is mid-purchase and
  -- the pass is paused for the dialog anyway (GC.Sniper.NotifyDialogOpened), so there is
  -- nothing to release and nobody being starved. Closing it resolves the row.
  if dialog and dialog.IsShown and dialog:IsShown() then return true end
  GC.Sniper._ReleaseQuietZone()
  if GC.Sniper._QuietZoneOpen() then
    -- A confirmed attempt survived the release. Restart the clock rather than re-running the
    -- release on every single call for the rest of its life.
    GC.Sniper._quietSince = now
    return true
  end
  GC.Sniper._quietSince = nil
  return false
end

-- D: true while a Full Scan is paging (or queued to start) or a purchase attempt is mid-flight
-- -- GC.Sell's own quote walker (SellFrame.lua) checks this before every send and simply
-- refuses/waits while it's true, so the Sell tab's traffic can never compete with, or queue
-- ahead of, a scan or a buy requery on the shared throttled message system.
function GC.Sniper.IsBusy()
  if GC.Sniper._bookPass:IsPaging() then return true end
  return GC.Sniper.IsPurchaseQuiet()
end

-- Whether something the PLAYER is waiting on owns the throttled search slot: a
-- Check requery, or a purchase in flight -- the quiet zone above, in one word.
-- Short-lived, and nothing else may take the slot out from under it.
--
-- Deliberately narrower than IsBusy, which also counts the full browse scan. The
-- Sell tab used to stand aside for IsBusy, and under Auto the browse scan runs
-- back to back with a two-second breather forever -- so the Sell tab could never
-- price anything at all, and Refresh looked hung until a reload happened to
-- catch a gap. A background convenience does not get to starve the screen the
-- player is actually looking at; the scan may run slightly slower for it, and
-- its own watchdog and Auto's retry already cover a disturbed pass.
function GC.Sniper.IsSearchCritical()
  return GC.Sniper.IsPurchaseQuiet()
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
  if not driver.itemResult(itemID) then return nil end
  -- Live price caps, addon task 5: judged against the player's own price FIRST -- see the
  -- matching branch in evaluateLiveCommodityDeal above for why GC.Caps.For needs no market
  -- reference to fire, and Core/Caps.lua for the contract. Falls through to the ordinary
  -- realm/region verdict below when no lot qualifies under the cap.
  local cap = GC.Caps and GC.Caps.For(itemID)
  if cap then
    local capDecision = GC.Caps.DecideRealm(cap, driver.itemLots(itemID))
    if capDecision then
      local capDeal = buildCapDeal(itemID, false, capDecision.unit, capDecision.candidate.quantity,
        capDecision.candidate.auctionID, cap)
      GC.Sniper._realmDeals[itemID] = capDeal
      GC.FullScan.CapDeals(GC.Sniper._realmDeals, WIN.ROW_CAP)
      -- Addon task 6: queued for the board-ring, once per GC.Caps.Announce's own dedup -- a
      -- realm lot rings once per resolved auctionID, however many drills/polls see it again.
      if GC.Caps.Announce(capDeal) then
        pendingCapPings[#pendingCapPings + 1] = capDeal
      end
      return { isCommodity = false, decision = capDecision }
    end
  end
  -- Sniper phase 2: a realm item the import carries a region reference for gets the realm
  -- verdict -- a real comparison of the cheapest COMPARABLE lot against a price measured
  -- across the region, naming that exact auction as a candidate. It is still never SAFE and
  -- never `buyable`; what changed is that there is now something honest to compare against.
  --
  -- Everything else keeps v1's behaviour exactly: Evaluate with no commodity book, which
  -- visibly explains why it remains WATCH and never constructs a candidate at all.
  local stored = GC.Data.GetItemValue(itemID)
  if stored and stored.kind == "realm_item" then
    -- Every realm item answers here, with or without a region reference. Without one there is
    -- no board row for it any more (Core/DealMath.lua), but a PIN is an explicit instruction
    -- and a pinned row can still be Checked -- and the answer it gets has to be the sentence
    -- that says what would change it, not a comparison against a two-listing median.
    local value = GC.Sniper._RealmValue(itemID)
    return { isCommodity = false, decision = GC.SniperDecision.EvaluateRealm(
      driver.itemLots(itemID), value and value.mv or nil, value and value.refIlvl or 0,
      GC.db.settings.sniper) }
  end
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
    -- The requery is no longer the row's (a repaint replaced the deal under the dialog, or the
    -- token moved on), so its result arms nothing -- but the result still proves the cancelled
    -- attempt's late quote has been delivered, which is all the tombstone fenced on this
    -- requery was waiting for. Dropping the requery without this left the Buy refused for the
    -- tombstone's full 20 seconds.
    GC.Sniper._RetireFencedTombstone(attempt.row, attempt.token)
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
  -- Sniper phase 2: an item auction has no server quote step -- PlaceBid pays exactly the
  -- buyout the dialog showed -- so the immutable fact this purchase is recorded from can be
  -- built right here, from the candidate the click bought on, in the same shape the commodity
  -- path hands purchaseFacts. nil facts still resolve the row; they just record nothing.
  local decision = row.decisionSnapshot
  local candidate = decision and decision.candidate
  local facts = (deal and candidate and candidate.buyout) and purchaseFacts(deal, {
    itemID = deal.itemID,
    quantity = candidate.quantity,
    total = candidate.buyout,
    market = marketForDecision(deal.itemID),
    decision = decision,
  }) or nil
  resolvePurchase(row, true,
    deal and (GC.L["sniped for "] .. GetCoinTextureString(deal.unitPrice * deal.qty)) or GC.L["purchase complete"],
    facts)
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
      or row.purchaseToken ~= pending.token then
    return -- a late event cannot take ownership of a newer row/token
  end
  if row.purchaseStage == "confirming" then
    -- A price update AFTER Confirm is the server re-quoting, not a stray echo: the price moved
    -- between the quote and the Confirm click, the purchase did not happen, and Blizzard's own
    -- buy dialog handles exactly this by showing the new price and asking for another click
    -- (Blizzard_AuctionHouseBuyDialog.lua keeps COMMODITY_PRICE_UPDATED live through
    -- BuyState.Purchasing). No terminal event ever follows a re-quote, so treating the stage as
    -- deaf here left the attempt confirmed-and-owned forever: the dialog sat on "confirming
    -- purchase...", and after an AH close the confirmed tombstone refused every later commodity
    -- Buy with "waiting for previous commodity purchase to settle" until /reload. Unconfirm the
    -- attempt -- no gold moved -- and let the ordinary requote path below judge the new price
    -- exactly as it would have before Confirm (cancel on broken safety, else re-arm Confirm).
    if not pending.confirmed then return end
    pending.confirmed = nil
    -- Unconfirmed, but not forgotten. Confirm had already reached Blizzard once, and wiping the
    -- deal and quote with the flag left a late terminal event with nothing to say at all: the
    -- attempt was dropped in silence, and a player whose gold had moved was told nothing. These
    -- two are read by the drained-tombstone path below and by nothing else -- never by the
    -- Confirm gate, which still requires a fresh quoteSnapshot for the price now on offer.
    pending.wasConfirmed = true
    pending.lastDeal = pending.deal
    pending.deal = nil
    pending.quote = nil
    row.quoteSnapshot = nil
    row.purchaseStage = "buying"
    if dialog and dialog.row == row then dialog.cancelBtn:Enable() end
  end
  local deal = row.purchaseDeal
  local decision = row.decisionSnapshot
  if not deal or deal.itemID ~= pending.itemID or not decision or not decision.buyable
      or decision.status ~= "SAFE" then
    return
  end
  pending.priceReceived = true

  -- The client keeps ONE commodity search buffer, shared with every other search this addon
  -- and the player make, so "what is in the buffer" is not the same question as "what is this
  -- item's book". driver.commodityResult is the proof: it reads level 1 for THIS itemID, and
  -- comes back nil when the buffer belongs to something else. Only then is the buffer this
  -- item's book; otherwise fall back to the book this attempt was actually armed on, which is
  -- the one the SAFE decision was made against. The server's totalPrice below is still the
  -- authority for what the entry costs -- the book only says what is being bought into.
  local levels = driver.commodityResult(deal.itemID) and driver.commodityBook(deal.itemID) or nil
  if not levels and row.armedItemID == deal.itemID then levels = row.armedLevels end
  if not levels and dialog and dialog.row == row then levels = dialog.bookLevels end
  local finalDecision = evaluateLive(deal.itemID, levels, decision.quantity, totalPrice)
  if not finalDecision.buyable or finalDecision.status ~= "SAFE" then
    -- Visual price-change thresholds are never economic approval. A 1-copper or sub-5%
    -- repriced order that breaks the fixed safety decision cancels immediately.
    C_AuctionHouse.CancelCommoditiesPurchase()
    pending.cancelRequested = true
    local tombstone = drainCommodityPurchase(row)
    -- Owner-reported 2026-09-11: Buy on a 64-unit plan while 38 remained bounced here, and the
    -- old answer -- "the price moved, Check again" -- then refused the very next Buy for the
    -- tombstone's full 20s. The quote breaking the plan does not mean nothing is worth buying:
    -- it means the book moved under the plan. So re-run the same live requery Check would, and
    -- let the decision engine pick the largest quantity the book now fills safely (38 here).
    -- The re-armed dialog still needs the player's Buy click; no purchase call is issued from
    -- this event. finishRequery retires the tombstone once THIS requery's result lands: a
    -- search reply sent after the Cancel is proof no stray quote for the cancelled attempt is
    -- still on its way. Snapshots are cleared as before -- the next decision comes from the
    -- fresh book, never from the one the quote just contradicted.
    row.purchaseDeal = nil
    row.decisionSnapshot = nil
    row.quoteSnapshot = nil
    row.armedLevels = nil
    row.armedItemID = nil
    if dialog and dialog.row == row then
      dialog.bookLevels = nil
      dialog.primaryBtn:Disable()
      hideRequoteBanner()
      setPrimaryLabel("Buy")
    end
    setDialogStatus(GC.SniperDecision.ReasonText("requote_broke_safety") .. " "
      .. GC.L["re-checking what remains at a safe price..."], 1, 0.82, 0)
    if frame then frame.status:SetText(GC.L["re-checking what remains at a safe price..."]) end
    local restarted = startRequery(row, (row.deal and row.deal.itemID == deal.itemID) and row.deal or deal)
    -- Only a wait that will actually be settled can retire this tombstone: whoever settles it
    -- matches on the row and token stamped here, and a fence carrying a token nothing holds is
    -- never consumed -- which used to leave every later Buy refused with "waiting for previous
    -- commodity purchase to settle" until the tombstone's own 20-second timer ran out.
    --
    -- There are two such waits. Normally it is the fresh requery, retired by finishRequery when
    -- its result lands. When the requery could not even start -- an older sent search for this
    -- item still has to drain first -- startRequery registers a drain wait instead, and THAT is
    -- the thing that will be settled (GC.Sniper._FinishDrainWait, which retires the tombstone
    -- the same way). Either is a real event with a real owner; only "neither" waits for a timer.
    local owner = restarted or GC.Sniper._drainWaitRequery[deal.itemID]
    if tombstone and owner and owner.row == row then
      tombstone.fenceRow = row
      tombstone.fenceToken = owner.token
    end
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

  -- Fix 2: the server's own live quote can exceed what's in the player's bags even when the
  -- dialog's earlier stamp looked affordable (gold spent elsewhere mid-flow, or the quote
  -- simply landed higher than the last book read) -- Confirm must never be clickable against
  -- a purchase that would fail server-side anyway. Read ONCE, above the severity split: the
  -- two requote branches below used to enable Confirm without asking, so the exact case that
  -- most often outruns the player's gold -- a price that just rose -- was the one case where
  -- the affordability gate did not run.
  local affordable = totalPrice <= GetMoney()

  local severity, ratio = GC.DealMath.RequoteSeverity(
    decision.entryTotal, totalPrice, LIM.REQUOTE_WARN_RATIO, LIM.REQUOTE_LOUD_RATIO)
  if severity == "none" then
    row.purchaseStage = "confirm"
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
      setDialogStatus((GC.L["quote %s -- click Confirm to buy"]):format(GetCoinTextureString(totalPrice)))
      if frame then
        frame.status:SetText((GC.L["quote %s -- click Confirm to buy"]):format(GetCoinTextureString(totalPrice)))
      end
    else
      setDialogStatus(GC.L["not enough gold for this quote -- Cancel"], 1, 0.3, 0.3)
      if frame then frame.status:SetText(GC.L["not enough gold for this quote -- Cancel"]) end
    end
    return
  end

  row.purchaseStage = "requote"
  local detail = (GC.L["%s -> %s per unit    total %s -> %s"]):format(
    GC.Util.FormatMoney(math.floor(decision.entryTotal / decision.quantity)), GC.Util.FormatMoney(unitPrice),
    GC.Util.FormatMoney(decision.entryTotal), GC.Util.FormatMoney(totalPrice))
  if dialog and dialog.row == row then
    if severity == "loud" then
      showRequoteBanner((GC.L["PRICE ROSE %.1fx"]):format(ratio), detail)
      -- armLoudConfirm re-enables Confirm once its countdown is up; a quote the player cannot
      -- pay for never gets that far, so the countdown is not started at all.
      if affordable then
        armLoudConfirm(row)
      else
        requoteArmToken = requoteArmToken + 1
        dialog.primaryBtn:Disable()
        setPrimaryLabel("Confirm", 1, 0.35, 0.35)
      end
    else
      requoteArmToken = requoteArmToken + 1
      hideRequoteBanner()
      if affordable then
        dialog.primaryBtn:Enable()
      else
        dialog.primaryBtn:Disable()
      end
      setPrimaryLabel("Confirm", 1, 0.35, 0.35)
    end
    if refreshQtyRow then refreshQtyRow() end -- "requote" is not "ready" -- box/quick-fill stay greyed out
  end
  if severity == "loud" and GC.db and GC.db.settings and GC.db.settings.sniper.sound then
    PlaySound(SOUNDKIT.RAID_WARNING)
  end
  if not affordable then
    -- The rise itself is already on the banner and in the stamped figures; what the player
    -- needs from the status line is why the button is dead.
    setDialogStatus(GC.L["not enough gold for this quote -- Cancel"], 1, 0.3, 0.3)
    if frame then frame.status:SetText(GC.L["not enough gold for this quote -- Cancel"]) end
    return
  end
  setDialogStatus(detail, 1, 0.3, 0.3)
  if frame then frame.status:SetText((GC.L["price rose %.1fx — still safe, confirm"]):format(ratio)) end
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
  -- A terminal event with nothing owning the flow retires the record-only slot a released
  -- confirmed attempt left behind (see GC.Sniper._ReleaseStrandedConfirmed): the server has
  -- answered, so nothing later may be credited to it. Unavailable is not a purchase, and the
  -- release already told the player to inspect the mailbox -- there is nothing to record.
  if not pending then
    -- ...unless the BUY tab is holding a stranded confirm of its own. A commodity event carries
    -- no attempt identifier, so with a record on both sides this one cannot be shown to answer
    -- the Sniper's: dropping it here would leave the next success free to be taken by whichever
    -- window asked first. Fail closed, the same answer GC.Buy.mayOwnTerminal gives the other way.
    if GC.Buy and GC.Buy.HasStranded and GC.Buy.HasStranded() then return end
    takeStrandedConfirmed()
    return
  end
  if pending.confirmed then
    commodityPurchase = nil
    if confirmedAttemptOwnsRow(pending) then
      resolvePurchase(pending.row, true, GC.L["purchase total unavailable — inspect mailbox"], nil, pending.deal)
    else
      settleDetachedConfirmed(pending, "unavailable")
    end
    return
  end
  local row = pending.row
  if not row or row.purchaseToken ~= pending.token or row.purchaseDeal == nil then return end
  C_AuctionHouse.CancelCommoditiesPurchase()
  -- The server could not fill the quantity the plan asked for. That is not the same as the
  -- item being gone: a 64-unit plan with 38 left on the book lands here too, and the old
  -- "Gone" answer sent the player away from a buy that was still there for the taking
  -- (owner-reported 2026-09-11). So this is a terminal event for the attempt -- the slot is
  -- freed, nothing is credited, no tombstone (the server closed the session itself) -- and
  -- then the same live requery Check would run re-arms the dialog at whatever the fresh book
  -- fills safely. A book with nothing left still ends in "Gone", through applyRequeryResult.
  -- The re-armed Buy is the player's click; no purchase call is issued from this event.
  local deal = row.purchaseDeal
  commodityPurchase = nil
  if GC.PurchaseSlot then GC.PurchaseSlot.Release("sniper") end
  row.purchaseDeal = nil
  row.decisionSnapshot = nil
  row.quoteSnapshot = nil
  row.armedLevels = nil
  row.armedItemID = nil
  if dialog and dialog.row == row then
    dialog.bookLevels = nil
    dialog.primaryBtn:Disable()
    hideRequoteBanner()
    setPrimaryLabel("Buy")
  end
  setDialogStatus(GC.L["not enough units left for that quantity -- re-checking what remains..."], 1, 0.82, 0)
  if frame then frame.status:SetText(GC.L["not enough units left for that quantity -- re-checking what remains..."]) end
  startRequery(row, (row.deal and row.deal.itemID == deal.itemID) and row.deal or deal)
  refreshRows()
end

function GC.Sniper.OnCommodityPurchaseSucceeded()
  if commodityDraining then
    local pending = commodityDraining
    commodityDraining = nil
    if not pending.confirmed then
      -- An attempt the server re-quoted after Confirm is unconfirmed again (no gold moves on a
      -- re-quote) and this one was then cancelled -- but Confirm HAD reached Blizzard once, so
      -- a success landing here means the purchase went through after all. Deliberately not
      -- recorded from the retained quote: the server replaced that price, and a cost basis
      -- taken from a total nobody was charged is worse than no row at all. The player is told
      -- to inspect the mailbox instead, which is the same answer every other "confirmed but
      -- unquotable" outcome gives.
      if pending.wasConfirmed then
        settleDetachedConfirmed({ token = pending.token, itemID = pending.itemID,
          deal = pending.lastDeal }, "unavailable")
      end
      return
    end
    settleDetachedConfirmed(pending, "success")
    return
  end
  local pending = commodityPurchase
  if not pending then
    -- Nothing owns the flow any more. A confirmed attempt whose ownership was released while
    -- the server stayed silent (GC.Sniper._ReleaseStrandedConfirmed) keeps its immutable quote
    -- in a record-only slot for exactly this: the success is late, but the gold left the bags
    -- and the books have to say so.
    --
    -- Not while the BUY tab holds a stranded confirm too: the event says nothing about which
    -- window's purchase it answers, and booking it here would put a goldcap_sniper row on the
    -- site for a purchase that may well have been BUY's. Fail closed, exactly as
    -- GC.Buy.mayOwnTerminal does when this side is the one holding a record.
    if GC.Buy and GC.Buy.HasStranded and GC.Buy.HasStranded() then return end
    local stranded = takeStrandedConfirmed()
    if stranded then settleDetachedConfirmed(stranded, "success") end
    return
  end
  if not pending.confirmed then return end
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
    resolvePurchase(row, true, GC.L["purchase total unavailable — inspect mailbox"])
    return
  end
  local purchase = purchaseFacts(deal, quote)
  resolvePurchase(row, true, purchase and (GC.L["bought %d x item %d"]):format(purchase.quantity, deal.itemID)
    or GC.L["purchase total unavailable — inspect mailbox"], purchase, deal)
end

function GC.Sniper.OnCommodityPurchaseFailed()
  if commodityDraining then
    local pending = commodityDraining
    commodityDraining = nil
    if pending.confirmed then settleDetachedConfirmed(pending, "failed") end
    return -- terminal event for the cancelled/closed attempt, never the next one
  end
  local pending = commodityPurchase
  -- Same retirement as the unavailable path above: the server answered the released attempt,
  -- and a failure is proof no gold moved, so the record-only slot is dropped without a word.
  if not pending then
    -- And the same refusal: with a stranded confirm on the BUY side too, this failure cannot be
    -- shown to be the answer to the Sniper's. Dropping the record on it would free the NEXT
    -- success to be booked as the Sniper's when it was the other window's.
    if GC.Buy and GC.Buy.HasStranded and GC.Buy.HasStranded() then return end
    takeStrandedConfirmed()
    return
  end
  if pending.confirmed then
    commodityPurchase = nil
    if confirmedAttemptOwnsRow(pending) then
      resolvePurchase(pending.row, false, GC.L["commodity purchase failed"])
    else
      settleDetachedConfirmed(pending, "failed")
    end
    return
  end
  local row = pending.row
  if not row or row.purchaseToken ~= pending.token or row.purchaseDeal == nil then return end
  commodityPurchase = nil
  resolvePurchase(row, false, GC.L["commodity purchase failed"])
end

-- AUCTION_HOUSE_SHOW_ERROR (Core/Init.lua). Observed live 2026-09-11: the red "Internal
-- auction error." the player saw over the columns came with no commodity terminal event and no
-- search result behind it, so every wait this addon had open at that moment was waiting for
-- something that never arrived -- which is how a purchase ended up owning the search slot for
-- the rest of the session, and how a Check sat on "..." until its own timeout. Blizzard
-- documents no ordering guarantee either way, so this treats the error as the terminal event
-- it appeared to be, and every path below is written to be harmless if a real one still lands.
--
-- Not a purchase call and not a cancel: an unconfirmed attempt is settled here as failed
-- (nothing was confirmed, so no gold moved), and CancelCommoditiesPurchase stays where it
-- already lives. A CONFIRMED attempt is never resolved from here for the same reason the
-- confirming timeout does not resolve one -- gold may have moved and the row must not be freed
-- for a retry that buys the same lot twice; it is told what happened and left to its own
-- terminal event or GC.Sniper._ReleaseStrandedConfirmed. A success that already landed
-- resolved its row and cleared the slot, so there is nothing here for this to swallow.
-- The wiki documents one payload argument, `error` (Enum.AuctionHouseError), and no public
-- mapping to text. Blizzard_AuctionHouseUI carries its own table, so ask the client for the
-- sentence and fall back to our own rather than reimplementing 27 error strings.
function GC.Sniper.OnAuctionHouseError(errorCode)
  local text = GC.L["the auction house reported an error"]
  local messages = _G.AuctionHouseErrorMessages
  if type(messages) == "table" and type(messages[errorCode]) == "string" then
    text = messages[errorCode]
  end

  local pending = commodityPurchase
  local row = pending and pending.row
  if row and row.purchaseToken == pending.token and GC.Sniper._StageIsQuiet(row.purchaseStage) then
    if pending.confirmed then
      if dialog and dialog.row == row then
        dialog.cancelBtn:Enable()
        setDialogStatus(text, 1, 0.3, 0.3)
      end
    else
      commodityPurchase = nil
      if commodityDraining and not commodityDraining.confirmed then commodityDraining = nil end
      resolvePurchase(row, false, text)
    end
  end

  -- Every live Check waiting on a search result, retired exactly as its own timeout retires
  -- it: a search that was actually sent still has to drain before a new authoritative Check
  -- can exist, and the row goes back to a button the player can press again.
  local note = GC.L["auction house error"] .. GC.L[" — Check again"]
  for itemID, attempt in pairs(awaitingRequery) do
    awaitingRequery[itemID] = nil
    awaitingKeyInfo[itemID] = nil
    pendingRequerySend[itemID] = nil
    if attempt.sent then GC.Sniper._FenceDrain(itemID, attempt) end
    if attempt.row and attempt.deal and attempt.row.purchaseStage == "requerying" then
      armCheck(attempt.row, attempt.deal, nil, note, true)
    end
    GC.Sniper._ResumePausedLiveRequery(attempt)
  end
  if prewarmAttempt then
    if prewarmAttempt.sent then GC.Sniper._FenceDrain(prewarmAttempt.itemID, prewarmAttempt) end
    prewarmAttempt = nil
  end

  -- The client's own words, held on the status line long enough to be read -- the board is
  -- otherwise repainting a progress line several times a second over the top of it.
  setStatus(text, 10)
end

-- Armed by the hardware Confirm click for the exact attempt it confirmed. A confirmed attempt
-- normally settles through one of the three terminal events within a second or two; when none
-- ever arrives (dropped event, disconnect mid-buy, a server that answered with nothing) the
-- attempt must not hold the single commodity slot -- owned or as a tombstone -- until /reload,
-- with every later Buy refused. Release the bookkeeping and tell the player the honest thing:
-- the buy may or may not have gone through, inspect the mailbox. Deliberately NOT a resolve of
-- the row: gold may have moved, so the row is never freed for a silent retry here -- closing the
-- dialog does that, and only after this release has cleared the ownership that would otherwise
-- make Esc/Cancel a no-op. Bound to `pending` by identity, so a later attempt in either slot is
-- never touched.
function GC.Sniper._ReleaseStrandedConfirmed(pending)
  if not pending or not pending.confirmed then return end
  local stranded = false
  if commodityPurchase == pending then commodityPurchase = nil; stranded = true end
  if commodityDraining == pending then commodityDraining = nil; stranded = true end
  if not stranded then return end
  -- Whether this attempt still owns its row has to be asked BEFORE the settle, and the row has
  -- to be frozen after it. Releasing the ownership above is what lets the player close the
  -- dialog -- but it also made the row look unowned to the quiet-zone release, which about a
  -- minute later handed it back as "Check again": the same lot, on a row whose buy may already
  -- have been paid for, one click from being bought a second time. "frozen" is the same state
  -- resolvePurchase leaves a server success it cannot price at, and it is not a quiet stage, so
  -- the quiet-zone release passes it by.
  local row = confirmedAttemptOwnsRow(pending) and pending.row or nil
  settleDetachedConfirmed(pending, "unavailable")
  -- One record per item, kept for a late terminal event to find (see takeStrandedConfirmed).
  if pending.itemID and pending.deal and pending.quote then
    GC.Sniper._strandedConfirmed[pending.itemID] = { pending = pending, at = GetTime() }
  end
  if not row then return end
  row.purchaseStage = "frozen"
  row.purchaseDeal = nil
  row.decisionSnapshot = nil
  row.quoteSnapshot = nil
  row.armedLevels = nil
  row.armedItemID = nil
  -- Keeps the deal off the board (refreshRows only preserves pinned rows) until the player
  -- closes the dialog themselves, exactly as the unpriced-success freeze does.
  if pending.itemID then activeItemID[pending.itemID] = true end
  if dialog and dialog.row == row then
    dialog.primaryBtn:Disable()
    dialog.cancelBtn:Enable()
    setDialogStatus(GC.L["purchase total unavailable — inspect mailbox"], 1, 0.3, 0.3)
  end
  refreshRows()
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
  local wasScanning = GC.Sniper._bookPass:IsPaging()
  abortFullScan()
  if wasScanning and frame then
    frame.status:SetText(GC.L["full scan interrupted -- confirm your purchase"])
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
    setDialogStatus(GC.L["confirming purchase..."])
    if frame then frame.status:SetText(GC.L["confirming purchase..."]) end
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
      setDialogStatus(GC.L["no confirmation from the server -- the buy may still have gone through, check your mail. Closing this will not undo it."], 1, 0.82, 0)
    end)
    -- Far beyond any real server round trip, so a genuine terminal event always lands first --
    -- see GC.Sniper._ReleaseStrandedConfirmed and LIM.STRANDED_RELEASE_SECONDS.
    C_Timer.After(LIM.STRANDED_RELEASE_SECONDS, function() GC.Sniper._ReleaseStrandedConfirmed(pending) end)
    end
    return
  end

  if stage == "expired" then
    -- Refresh: NOT a purchase call -- re-runs the same live requery the dialog opened with,
    -- so a player who read the numbers past the quote window is never dead-ended into
    -- Cancel. finishRequery re-arms "ready" with fresh numbers (or closes on gone/changed).
    dialog.primaryBtn:Disable()
    setPrimaryLabel("Buy")
    setDialogStatus(GC.L["checking live price..."])
    startRequery(row, row.deal)
    return
  end

  if stage == "check" then
    dialog.primaryBtn:Disable()
    setPrimaryLabel("Check")
    setDialogStatus(GC.L["checking live safety..."])
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

  -- Second overall click. Two shapes of purchase reach this point, and each has its own gate.
  -- A commodity may only be bought on a current SAFE, buyable decision, exactly as before.
  -- A realm lot can never be either -- nothing measures how fast a realm item sells -- so it
  -- is gated on the candidate instead: one specific auction, at one specific buyout, that a
  -- live check found under the region reference (GC.SniperDecision.EvaluateRealm). Anything
  -- without one of the two stays Check-only, regardless of legacy discovery tier.
  local deal = row.deal
  local decision = row.decisionSnapshot
  local candidate = decision and decision.status == "WATCH" and decision.candidate or nil
  if candidate and not (candidate.auctionID and candidate.buyout and candidate.buyout > 0) then
    candidate = nil
  end
  if not deal.isCommodity and not candidate then
    armCheck(row, deal, decision or { status = "WATCH", reasons = { "live_verification_required" } },
      GC.L["live verification required"], false)
    return
  end
  if deal.isCommodity and (not decision or decision.status ~= "SAFE" or not decision.buyable) then
    armCheck(row, deal, decision or { status = "WATCH", reasons = { "live_verification_required" } },
      GC.L["live verification required"], false)
    return
  end
  if commodityDraining then
    -- Fail closed while the tombstone is young, but not forever: an attempt whose terminal
    -- event never arrives (a cancel, an auction house error) would otherwise refuse every
    -- later commodity Buy until the player reloaded -- with the Buy button sitting enabled,
    -- saying the purchase was possible. A CONFIRMED tombstone is never retired here; its late
    -- success still has to land on the attempt that paid for it.
    if commodityDraining.confirmed
        or (GetTime() - (commodityDraining.drainingAt or 0)) <= LIM.DRAIN_TIMEOUT_SECONDS then
      setDialogStatus(GC.L["waiting for previous commodity purchase to settle"], 1, 0.82, 0)
      if frame then frame.status:SetText(GC.L["waiting for previous commodity purchase to settle"]) end
      return
    end
    commodityDraining = nil
  end
  if commodityPurchase and commodityPurchase.row ~= row then
    -- Only ONE commodity purchase may be in flight at a time. Unreachable in practice --
    -- opening a second dialog already refuses/replaces per the guard in onBuyClick -- kept as
    -- a last-resort guard against orphaning the pending one.
    setDialogStatus(GC.L["finish the pending buy first"], 1, 0.3, 0.3)
    driver.onStatus(GC.L["finish the pending buy first"])
    return
  end

  local purchaseDeal = deal
  row.quoteSnapshot = nil
  row.purchaseToken = (row.purchaseToken or 0) + 1
  local token = row.purchaseToken
  row.purchaseStage = "buying"
  dialog.primaryBtn:Disable()
  if refreshQtyRow then refreshQtyRow() end -- Fix 2: purchase call about to fire -- box/quick-fill must not be editable while it's in flight
  if deal.isCommodity then
    if GC.PurchaseSlot and not GC.PurchaseSlot.Claim("sniper") then
      -- The BUY tab owns the shared commodity purchase slot right now -- refuse exactly as the
      -- "another commodity purchase already in flight" guard above does, and put the row back
      -- the way it was before this click started mutating it for a purchase that never fired.
      row.purchaseStage = "ready"
      dialog.primaryBtn:Enable()
      if refreshQtyRow then refreshQtyRow() end
      setDialogStatus(GC.L["finish the pending buy first"], 1, 0.3, 0.3)
      driver.onStatus(GC.L["finish the pending buy first"])
      return
    end
    row.purchaseDeal = purchaseDeal
    commodityPurchase = { row = row, itemID = deal.itemID, token = token }
    C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, decision.quantity)
    setDialogStatus(GC.L["buying commodity..."])
    if frame then frame.status:SetText(GC.L["buying commodity..."]) end
  else
    -- A realm lot. The candidate IS the identity of what is being bought -- one auction, one
    -- price -- so the purchase takes that identity here: resolvePurchase clears pendingAuction
    -- by deal.auctionID, and the completion line quotes deal.unitPrice * deal.qty, the same
    -- unit * qty = total convention the commodity path uses.
    --
    -- On a COPY, not on the board's own deal. These three fields used to be written straight
    -- onto the row's deal, so a bid that never landed left the board advertising the candidate's
    -- lot price and size instead of what the scan had actually seen -- a price nothing had
    -- confirmed. resolvePurchase and OnPurchaseCompleted both already prefer row.purchaseDeal.
    purchaseDeal = {}
    for key, value in pairs(deal) do purchaseDeal[key] = value end
    purchaseDeal.boardDeal = deal -- so consumePurchasedDeal can still find the entry it came from
    purchaseDeal.auctionID = candidate.auctionID
    purchaseDeal.qty = math.max(1, candidate.quantity or 1) -- never 0: unitPrice divides by it below
    purchaseDeal.unitPrice = math.floor(candidate.buyout / purchaseDeal.qty)
    -- The identity the acquisition store keys a position by. Without it
    -- GC.Acquisitions.PositionKey returns nil for an item auction, the batch is stored with no
    -- position at all, and ReconcileSale -- which only ever considers batches that have one --
    -- can never match the sale to it: the stock stays "on hand" forever and every later "You
    -- paid" line is averaged over items the player has already sold. Item level comes from the
    -- candidate because that is what separates two lots wearing the same name; suffix and pet
    -- species are 0, the same shape Core/PurchaseCapture.lua builds for an ordinary AH buy.
    purchaseDeal.itemKey = {
      itemID = deal.itemID,
      itemLevel = candidate.itemLevel or 0,
      itemSuffix = 0,
      battlePetSpeciesID = 0,
    }
    row.purchaseDeal = purchaseDeal
    pendingAuction[purchaseDeal.auctionID] = row
    -- PlaceBid's bidAmount is the TOTAL price for the auction's whole lot, not a per-unit
    -- price, and candidate.buyout is exactly that total -- the number the player just read on
    -- the dialog. It is passed through untouched rather than recomputed from unitPrice * qty,
    -- which floors and could bid a copper under the buyout.
    C_AuctionHouse.PlaceBid(candidate.auctionID, candidate.buyout)
    setDialogStatus(GC.L["placing bid..."])
    if frame then frame.status:SetText(GC.L["placing bid..."]) end
  end
  scheduleBuyTimeout(row, purchaseDeal, token)
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
      dialog.qtyOfLabel:SetText((GC.L["of %d"]):format(known))
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
    dialog.qtyLotText:SetText((GC.L["%d (whole lot)"]):format(deal.qty))
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
    setDialogStatus((GC.L["not enough gold -- total %s, you have %s"])
      :format(GC.Util.FormatMoney(total), GC.Util.FormatMoney(GetMoney())), 1, 0.3, 0.3)
  else
    dialog.primaryBtn:Enable()
    setDialogStatus(GC.L["price confirmed -- click Buy to purchase"], 0.25, 0.85, 0.25)
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
-- One strata up from whatever the window itself is in. The check drawer overlays the deals
-- list on any window narrower than WIN.PANEL_SHIFT_MIN -- which the docked auction house
-- always is -- and it is an OPAQUE sheet precisely so the rows underneath do not ghost
-- through it. A texture cannot cross a strata boundary, so "opaque" only holds while the
-- drawer is in a HIGHER strata than the rows; land the two in the SAME strata and the fight
-- is decided by frame level instead, which a scroll child can win. That is exactly what
-- docking started doing: GC.Sniper.SetDocked adopts the auction house's own strata for the
-- window, and if the host sits in DIALOG the window lands level with a drawer hardcoded to
-- DIALOG. Derived from the host rather than pinned, so no future host can reproduce it.
-- Capped below TOOLTIP: a purchase sheet must never draw over a tooltip.
CH.STRATA_ABOVE = {
  BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
  DIALOG = "FULLSCREEN", FULLSCREEN = "FULLSCREEN_DIALOG",
  FULLSCREEN_DIALOG = "FULLSCREEN_DIALOG", TOOLTIP = "TOOLTIP",
}

-- Builds the single reusable confirmation dialog (see createDialog/openDialog usage below).
-- Created lazily on the first Buy click of a session, same pattern as GoldCapImportDialog --
-- never built eagerly alongside the sniper frame itself.
local function createDialog()
  local d = CreateFrame("Frame", nil, frame)
  -- C1: this is an UNNAMED frame (CreateFrame(..., nil, ...)) published under a global name.
  -- Escape no longer travels through UISpecialFrames (see the OnKeyDown at the end of this
  -- function for why), but the name stays: it is how a player or another addon can reach this
  -- sheet at all, and how /framestack names it when something needs reporting.
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
  -- Re-derived on every show and on every dock/undock, never pinned: see CH.STRATA_ABOVE.
  d.raiseStrata = function()
    local host = (frame and frame.GetFrameStrata and frame:GetFrameStrata()) or "HIGH"
    d:SetFrameStrata(CH.STRATA_ABOVE[host] or "DIALOG")
    -- Belt and braces. SetFrameStrata reassigns the level within the new strata, so this comes
    -- after it: should the two ever land in one strata anyway, the level still decides, and a
    -- scroll child cannot out-level this.
    local base = (frame and frame.GetFrameLevel and frame:GetFrameLevel()) or 0
    d:SetFrameLevel(base + 50)
  end
  d.raiseStrata()
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
  -- Check panel v3: the header is IDENTITY and nothing else -- the item, and the one key that
  -- gets you out. "CONFIRM PURCHASE" (a document title above the thing it titled) and the tier
  -- chip both left: the chip is the imported snapshot's opinion, which belongs beside the
  -- verdict that disagrees with it, not level with the item's own name.
  local subtitle = Theme.Num(d, 9)
  subtitle:SetJustifyH("RIGHT")
  subtitle:SetWidth(DG.HEADER_ESC_W)
  subtitle:SetPoint("TOPRIGHT", -Theme.pad.m, -(Theme.pad.m + 10))
  subtitle:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  -- Not wrapped: "ESC" is the key cap the client itself prints, and a translated key name
  -- names a key the player's keyboard does not have.
  subtitle:SetText("ESC")
  d.subtitle = subtitle

  local nameText = Theme.Label(d, 13)
  -- ONE anchor plus an explicit width, deliberately -- not LEFT + RIGHT. Both of those are
  -- centre-Y constraints, and here they would disagree (the icon's centre against the ESC
  -- hint's), which is the exact trap the qtyLotText comment further down already records.
  -- Centred on the icon: with the old "CONFIRM PURCHASE" caption gone there is nothing under
  -- the name to balance a top-flush anchor against.
  nameText:SetPoint("LEFT", icon, "RIGHT", Theme.pad.s, 0)
  nameText:SetWidth(DG.HEADER_NAME_W)
  nameText:SetWordWrap(false)
  nameText:SetMaxLines(1)
  d.nameText = nameText

  -- Hover tooltip over the icon + name, same as a row (see createRow) -- Texture and
  -- FontString objects can't take mouse scripts themselves, so this is an invisible Frame
  -- spanning both, the same pattern createHeaderRow's own header hit-frames use.
  local itemHit = CreateFrame("Frame", nil, d)
  itemHit:SetPoint("TOPLEFT", icon, "TOPLEFT")
  -- One corner pair, both off the icon, with the name's own column added to the right edge:
  -- anchoring the bottom to nameText instead would size the hit region to a single line of
  -- text and leave the lower half of the icon dead.
  itemHit:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT",
    Theme.pad.s + DG.HEADER_NAME_W, 0)
  itemHit:EnableMouse(true)
  itemHit:SetScript("OnEnter", function(self)
    if not dialog.deal then return end
    -- Outside the window, never over it -- the dialog sits on top of the board this tooltip
    -- would otherwise cover (Theme.ItemTooltipOutside; see its own comment for the geometry).
    Theme.ItemTooltipOutside(self, frame)
    GameTooltip:SetItemByID(dialog.deal.itemID)
    GameTooltip:Show()
  end)
  itemHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  d.itemHit = itemHit

  -- THE ANSWER (check panel v3). Edge to edge and tinted: the verdict word, one figure that
  -- changes UNIT rather than going blank, its caption, and the sentence saying why. What goes
  -- in each slot is decided in Core/CheckVerdict.lua -- this block only draws it.
  local heroBlock = CreateFrame("Frame", nil, d)
  d.heroBlock = heroBlock

  -- A flat wash with two hairlines, not Theme.Card: the band runs the full width of the sheet,
  -- and a rounded card inset by pad.s reads as a plaque sitting ON the panel rather than as the
  -- panel's own answer. stampDialogFromDecision tints all three through d.setHeroTone below.
  local heroFill = heroBlock:CreateTexture(nil, "BACKGROUND")
  heroFill:SetAllPoints()
  local heroEdgeTop = heroBlock:CreateTexture(nil, "BORDER")
  heroEdgeTop:SetPoint("TOPLEFT")
  heroEdgeTop:SetPoint("TOPRIGHT")
  heroEdgeTop:SetHeight(1)
  local heroEdgeBottom = heroBlock:CreateTexture(nil, "BORDER")
  heroEdgeBottom:SetPoint("BOTTOMLEFT")
  heroEdgeBottom:SetPoint("BOTTOMRIGHT")
  heroEdgeBottom:SetHeight(1)
  -- Exposed as one call rather than three tinted fields: the wash and the two hairlines are a
  -- single visual decision (which colour this verdict is), and stampDialogFromDecision has no
  -- business knowing there are three textures. Guarded at every call site anyway -- the verdict
  -- specs stamp a hand-built fakeDialog that has none of this.
  d.setHeroTone = function(c)
    heroFill:SetColorTexture(c[1], c[2], c[3], 0.075)
    heroEdgeTop:SetColorTexture(c[1], c[2], c[3], 0.22)
    heroEdgeBottom:SetColorTexture(c[1], c[2], c[3], 0.22)
  end
  d.setHeroTone(Theme.color.fgDim)

  -- The verdict word: "Won't buy" / "Buy less" / "Clear to buy". Not a status code -- the old
  -- "LIVE VERDICT · REFUSED" named the machine's state, not the player's answer.
  local verdictLabel = Theme.Num(heroBlock, 9, true)
  verdictLabel:SetJustifyH("LEFT")
  verdictLabel:SetPoint("TOPLEFT", Theme.pad.m, -Theme.pad.s)
  d.verdictLabel = verdictLabel

  -- The figure. Two widgets sharing one slot rather than one that re-fonts itself: Theme.Num
  -- registers its size in Theme's rescale table at creation (see widgetFonts there), so a
  -- SetFont behind Theme's back would be undone the next time the player changes UI scale.
  -- verdictAmount carries the numbers; heroText carries "Can't price this" at the same weight,
  -- which is the whole point of the unpriceable case -- a dash would read as a missing value
  -- rather than as a refusal to invent one.
  local verdictAmount = Theme.Num(heroBlock, 22, true)
  verdictAmount:SetJustifyH("LEFT")
  verdictAmount:SetPoint("TOPLEFT", Theme.pad.m, -(Theme.pad.s + DG.HERO_KICKER_H + Theme.pad.xs))
  verdictAmount:SetPoint("RIGHT", -Theme.pad.m, 0)
  verdictAmount:SetWordWrap(false)
  verdictAmount:SetMaxLines(1)
  d.verdictAmount = verdictAmount

  local heroText = Theme.Label(heroBlock, 16)
  heroText:SetPoint("TOPLEFT", Theme.pad.m, -(Theme.pad.s + DG.HERO_KICKER_H + Theme.pad.xs + 2))
  heroText:SetPoint("RIGHT", -Theme.pad.m, 0)
  heroText:SetWordWrap(false)
  heroText:SetMaxLines(1)
  heroText:Hide()
  d.heroText = heroText

  -- The caption under the figure, wrapped: what the figure is OF. It used to sit beside the
  -- amount reading "EST. PROFIT AFTER AH CUT" on every verdict, including the ones with no
  -- figure at all.
  local verdictAmountNote = Theme.Label(heroBlock, 10)
  verdictAmountNote:SetPoint("TOPLEFT", Theme.pad.m,
    -(Theme.pad.s + DG.HERO_KICKER_H + Theme.pad.xs + DG.HERO_FIGURE_H + Theme.pad.xs))
  verdictAmountNote:SetPoint("RIGHT", -Theme.pad.m, 0)
  verdictAmountNote:SetWordWrap(true)
  verdictAmountNote:SetHeight(DG.HERO_CAPTION_H)
  verdictAmountNote:SetJustifyV("TOP")
  verdictAmountNote:SetTextColor(Theme.color.fgMuted[1], Theme.color.fgMuted[2], Theme.color.fgMuted[3])
  d.verdictAmountNote = verdictAmountNote

  -- The sentence: why the engine answered the way it did. Wraps now (it did not before -- a
  -- one-line SetWordWrap(false) headline is what put the "…" in the owner's screenshot).
  local verdictHead = Theme.Label(heroBlock, 12)
  verdictHead:SetPoint("TOPLEFT", Theme.pad.m, -(DG.HERO_H - Theme.pad.s - DG.HERO_SENTENCE_H))
  verdictHead:SetPoint("RIGHT", -Theme.pad.m, 0)
  verdictHead:SetWordWrap(true)
  verdictHead:SetHeight(DG.HERO_SENTENCE_H)
  verdictHead:SetJustifyV("TOP")
  d.verdictHead = verdictHead

  -- Kept as a field, never drawn: the old third copy of the same profit figure the hero and the
  -- facts already carry. Two specs stamp a fakeDialog that supplies it, so the field survives;
  -- the widget is hidden at construction and nothing shows it again.
  local verdictSub = Theme.Label(heroBlock, 10)
  verdictSub:SetPoint("TOPLEFT", Theme.pad.m, -DG.HERO_H)
  verdictSub:Hide()
  d.verdictSub = verdictSub

  -- THE RECONCILIATION. Only built into the layout when the board's tier and this verdict
  -- disagree; the tier chip lives here rather than in the header because that is the one place
  -- the tier is worth reading -- next to the sentence explaining why it is not the answer.
  local reconcileBlock = CreateFrame("Frame", nil, d)
  d.reconcileBlock = reconcileBlock

  local tierChip = Theme.Chip(reconcileBlock)
  tierChip:SetWidth(60)
  tierChip:SetPoint("TOPLEFT", Theme.pad.m, -Theme.pad.s)
  d.tierChip = tierChip

  local reconcileText = Theme.Label(reconcileBlock, 10)
  reconcileText:SetPoint("TOPLEFT", tierChip, "TOPRIGHT", Theme.pad.s, 0)
  reconcileText:SetPoint("RIGHT", -Theme.pad.m, 0)
  reconcileText:SetWordWrap(true)
  reconcileText:SetHeight(DG.RECONCILE_H - Theme.pad.s)
  reconcileText:SetJustifyV("TOP")
  reconcileText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  d.reconcileText = reconcileText

  -- HOW MANY. Its own block now, and out of the layout entirely on a refusal: the box and its
  -- four quick-fill chips were the bulk of what a player had to read past to reach the reason,
  -- on a verdict where nothing could be bought at any quantity.
  local qtyBlock = CreateFrame("Frame", nil, d)
  d.qtyBlock = qtyBlock

  local qtyLabel = Theme.Num(qtyBlock, 9)
  qtyLabel:SetJustifyH("LEFT")
  qtyLabel:SetPoint("TOPLEFT", Theme.pad.m, -(Theme.pad.s + 4))
  qtyLabel:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  qtyLabel:SetText(GC.L["QTY"])
  d.qtyLabel = qtyLabel

  -- Non-commodity fallback ("N (whole lot)"): takes the box's place after the label, bounded on
  -- the right so a long lot count ellipsizes instead of growing past the sheet (an unbounded
  -- single-point FontString grows without limit).
  local qtyLotText = Theme.Num(qtyBlock, 12)
  qtyLotText:SetJustifyH("LEFT")
  qtyLotText:SetPoint("TOPLEFT", qtyLabel, "TOPRIGHT", Theme.pad.s, 0)
  qtyLotText:SetPoint("RIGHT", -Theme.pad.m, 0)
  qtyLotText:SetWordWrap(false)
  qtyLotText:SetMaxLines(1)
  qtyLotText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  d.qtyLotText = qtyLotText

  local qtyBox = makeQtyEditBox(qtyBlock, 64, DG.QTY_BOX_H)
  qtyBox:SetPoint("LEFT", qtyLabel, "RIGHT", Theme.pad.s, 0)
  d.qtyBox = qtyBox

  local qtyOfLabel = Theme.Label(qtyBlock, 11) -- dim "of N" -- shown when the true available qty is known
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

  -- Quick-fill: four small ghost buttons that jump straight to a percentage of
  -- qtyMaxAvailable(deal) and commit immediately via applyChosenQty (the same path
  -- qtyBox.onCommit uses). Their own row under the box -- four 36px chips plus "of N" do not
  -- fit beside it at 320 wide.
  local quickFillBtns = {}
  local prevBtn
  for i = 1, #DG.QTY_QUICKFILL_PCTS do
    local pct = DG.QTY_QUICKFILL_PCTS[i]
    local btn = Theme.Button(qtyBlock, "ghost", "badge")
    btn:SetSize(DG.QTY_QUICKFILL_W, DG.QTY_QUICKFILL_H)
    if prevBtn then
      btn:SetPoint("TOPLEFT", prevBtn, "TOPRIGHT", Theme.pad.xs, 0)
    else
      btn:SetPoint("TOPLEFT", Theme.pad.m, -(Theme.pad.s + 24))
    end
    btn:SetLabel(pct .. "%")
    btn:SetScript("OnClick", function() applyQuickFillQty(pct) end)
    quickFillBtns[pct] = btn
    prevBtn = btn
  end
  d.quickFillBtns = quickFillBtns

  -- THE FACTS. Four rows, each label / meter-or-leader / value. The meter's tick is the
  -- engine's OWN threshold, so a short bar reads as a shortfall rather than as a small number;
  -- a fact with no honest ceiling gets the leader line instead, which is what stops the bars
  -- from competing with the figure above them. Fixed Y per row, like the evidence grid below
  -- and for the same reason: a chained anchor would let one wrapped row reflow the rest.
  local factsBlock = CreateFrame("Frame", nil, d)
  d.factsBlock = factsBlock
  d.factRows = {}
  for i = 1, DG.FACT_ROWS do
    local y = -(Theme.pad.s + (i - 1) * DG.FACT_ROW_H)
    local rowFacts = {}

    rowFacts.label = Theme.Label(factsBlock, 11)
    rowFacts.label:SetPoint("TOPLEFT", Theme.pad.m, y - 2)
    rowFacts.label:SetWidth(DG.FACT_LABEL_W)
    rowFacts.label:SetWordWrap(false)
    rowFacts.label:SetMaxLines(1)
    rowFacts.label:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])

    rowFacts.value = Theme.Num(factsBlock, 11)
    rowFacts.value:SetPoint("TOPRIGHT", -Theme.pad.m, y - 2)
    rowFacts.value:SetWidth(DG.FACT_VALUE_W)
    rowFacts.value:SetWordWrap(false)
    rowFacts.value:SetMaxLines(1)

    local meterX = Theme.pad.m + DG.FACT_LABEL_W + Theme.pad.s
    local meterY = y - math.floor((DG.FACT_ROW_H - DG.FACT_METER_H) / 2)
    local meter = CreateFrame("Frame", nil, factsBlock)
    meter:SetSize(DG.FACT_METER_W, DG.FACT_METER_H)
    meter:SetPoint("TOPLEFT", meterX, meterY)
    meter:Hide()
    rowFacts.meter = meter

    local track = meter:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.055)

    rowFacts.fill = meter:CreateTexture(nil, "ARTWORK")
    rowFacts.fill:SetPoint("TOPLEFT")
    rowFacts.fill:SetPoint("BOTTOMLEFT")
    rowFacts.fill:SetWidth(1)

    -- The engine's threshold, drawn ON the bar. Without it a 41% fill is just a short bar;
    -- with it the bar says "the line is at 70 and this is under it".
    rowFacts.tick = meter:CreateTexture(nil, "OVERLAY")
    rowFacts.tick:SetPoint("TOP")
    rowFacts.tick:SetPoint("BOTTOM")
    rowFacts.tick:SetWidth(1)
    rowFacts.tick:SetColorTexture(1, 1, 1, 0.38)

    rowFacts.leader = factsBlock:CreateTexture(nil, "BACKGROUND")
    rowFacts.leader:SetHeight(1)
    rowFacts.leader:SetWidth(DG.FACT_METER_W)
    rowFacts.leader:SetPoint("TOPLEFT", meterX, meterY - 2)
    rowFacts.leader:SetColorTexture(1, 1, 1, 0.045)
    rowFacts.leader:Hide()

    d.factRows[i] = rowFacts
  end

  -- Details toggle: the full transcript is opt-in, collapsed by default, restored per the
  -- player's own last choice (GC.db.settings.sniper.dialogDetailsOpen).
  -- "badge", not "plaque": DG.TOGGLE_H is 22px and PLAQUE_SLICE (12) is not below half of it
  -- (Theme.lua's own margin invariant), so plaque would notch this button's corners.
  local detailsToggle = Theme.Button(d, "ghost", "badge")
  detailsToggle:SetHeight(DG.TOGGLE_H)
  d.detailsToggle = detailsToggle

  -- Label/value grid: one row per number, aligned two-column (Theme.Label left, Theme.Num
  -- right). Fixed Y per row -- a chained anchor would let a wrapped neighbour reflow the rows
  -- underneath it.
  local gridBlock = CreateFrame("Frame", nil, d)
  d.gridBlock = gridBlock
  local function gridRow(index, label)
    local y = -(Theme.pad.s + (index - 1) * DG.GRID_ROW_H)
    local labelFS = Theme.Label(gridBlock, 11)
    labelFS:SetPoint("TOPLEFT", Theme.pad.m, y)
    labelFS:SetText(label)

    local valueFS = Theme.Num(gridBlock, 12)
    valueFS:SetPoint("TOPRIGHT", -Theme.pad.m, y)
    -- Bounded on the left by its own label, right-justified, single line: an unbounded
    -- TOPRIGHT-only FontString grows leftward without limit, and the Reason row's full
    -- sentence was painting straight past the dialog's edge onto whatever the window sat over.
    valueFS:SetPoint("LEFT", labelFS, "RIGHT", Theme.pad.s, 0)
    valueFS:SetJustifyH("RIGHT")
    valueFS:SetWordWrap(false)
    valueFS:SetMaxLines(1)
    return labelFS, valueFS
  end

  -- The ten immutable decision/evidence fields -- collapsed behind Details above. Every pair
  -- this loop builds is tracked in d.evidenceRows purely so applyDetailsState (below) can
  -- Show()/Hide() both halves of each row together; the values themselves are still stamped
  -- unconditionally by stampDialogFromDecision whether the row is visible or not, so expanding
  -- Details never shows anything stale.
  d.evidenceRows = {}
  local function evidenceRow(index, label)
    local labelFS, valueFS = gridRow(index, label)
    d.evidenceRows[#d.evidenceRows + 1] = { label = labelFS, value = valueFS }
    return valueFS
  end
  local decisionStatusText = evidenceRow(1, GC.L["Status"])
  local unitPriceText = evidenceRow(2, GC.L["Entry price (avg fill)"])
  local totalCostText = evidenceRow(3, GC.L["Entry total"])
  local exitUnitText = evidenceRow(4, GC.L["Stress exit unit"])
  local profitText = evidenceRow(5, GC.L["Stress profit"])
  local mvText = evidenceRow(6, GC.L["Market reference"])
  local soldText = evidenceRow(7, GC.L["Sold/day"])
  local sellThroughText = evidenceRow(8, GC.L["Sell-through"])
  local sourceAgeText = evidenceRow(9, GC.L["Source age"])
  local reasonText = evidenceRow(10, GC.L["Reason"])
  d.decisionStatusText = decisionStatusText
  d.unitPriceText, d.totalCostText, d.exitUnitText = unitPriceText, totalCostText, exitUnitText
  d.profitText, d.mvText, d.soldText = profitText, mvText, soldText
  d.sellThroughText, d.sourceAgeText, d.reasonText = sellThroughText, sourceAgeText, reasonText

  -- Stacks the blocks that are actually shown and measures what that costs. Called from every
  -- authoritative stamp (carrying the verdict's own shape) and from every Details toggle.
  -- A block with nothing to say is HIDDEN, not left as a reserved hole -- reserved holes are
  -- what made this panel read as a column of dashes on a refusal.
  --
  -- The four facts and the ten-row transcript share one slot rather than stacking: four of
  -- those ten rows ARE the facts, and reserving both at once is what made the toggle refuse to
  -- open inside the docked AH drawer and then tell the player to enlarge a window that has no
  -- resize handle.
  local function layoutBlocks(shape)
    shape = shape or d.blockShape or {}
    d.blockShape = shape
    local y = -DG.HEADER_H
    local function place(block, height, shown)
      if not shown then block:Hide() return end
      block:ClearAllPoints()
      block:SetPoint("TOPLEFT", d, "TOPLEFT", 0, y)
      block:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, y)
      block:SetHeight(height)
      block:Show()
      y = y - height
    end
    local reconcile = shape.reconcile and true or false
    -- Default TRUE: the shape is only known once a decision has been stamped, and before that
    -- the panel is showing a quantity it fully intends to buy.
    local actionable = shape.actionable ~= false
    place(heroBlock, DG.HERO_H, true)
    place(reconcileBlock, DG.RECONCILE_H, reconcile)
    place(qtyBlock, DG.QTY_BLOCK_H, actionable)
    place(factsBlock, DG.FACTS_H, not d.detailsOpen)
    place(gridBlock, DG.GRID_H, d.detailsOpen and true or false)

    y = y - Theme.pad.xs
    detailsToggle:ClearAllPoints()
    detailsToggle:SetPoint("TOPLEFT", Theme.pad.m, y)
    detailsToggle:SetPoint("TOPRIGHT", -Theme.pad.m, y)
    y = y - DG.TOGGLE_H

    -- One number now, not an open/closed pair: this IS the current layout either way.
    -- resizeDialogDiagnostics still falls back to the old pair for the hand-built fakeDialogs
    -- in the verdict specs, which never run this function.
    d.evidenceTop = y - Theme.pad.xs
    d.evidenceTopOpen, d.evidenceTopClosed = d.evidenceTop, d.evidenceTop

    local above = DG.HEADER_H + DG.HERO_H + (reconcile and DG.RECONCILE_H or 0)
      + (actionable and DG.QTY_BLOCK_H or 0) + DG.TOGGLE_BLOCK_H + DG.STATUS_H + DG.CONTROLS_H
    d.fixedHeightClosed = above + DG.FACTS_H
    d.fixedHeightOpen = above + DG.GRID_H
    -- Kept in step here too, not only in applyDetailsState: a verdict can drop the quantity
    -- block without the Details state changing at all, and resizeDialogDiagnostics measures
    -- the flowing block below off this number.
    d.fixedHeight = d.detailsOpen and d.fixedHeightOpen or d.fixedHeightClosed
  end
  d.layoutBlocks = layoutBlocks

  -- Sits between the grid and the status line; shown only when the clamp above actually bit.
  local mvNote = Theme.Label(d, 11)
  mvNote:SetPoint("TOPLEFT", Theme.pad.m, -DG.FIXED_HEIGHT_CLOSED)
  mvNote:SetPoint("RIGHT", -Theme.pad.m, 0)
  mvNote:SetWordWrap(true)
  mvNote:SetTextColor(Theme.color.red[1], Theme.color.red[2], Theme.color.red[3])
  mvNote:Hide()
  d.mvNote = mvNote

  -- Hidden unless GC.db.settings.sniper.debug is on (see resizeDialogDiagnostics) -- this is
  -- what a bug report gets copied from, not something a player one click from spending gold
  -- needs to see by default. The text it is given stays byte-identical either way.
  local diagnosticText = Theme.Label(d, 11)
  diagnosticText:SetPoint("TOPLEFT", Theme.pad.m, -DG.FIXED_HEIGHT_CLOSED)
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
  status:SetPoint("TOPLEFT", Theme.pad.m, -DG.FIXED_HEIGHT_CLOSED)
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
    -- Check panel v3: measured against THIS verdict's own open layout (layoutBlocks writes
    -- d.fixedHeightOpen from the blocks actually shown), not against a worst case that assumed
    -- every block was present. A refusal has no quantity block, so it clears the docked
    -- drawer's ceiling by 50px the old fixed budget spent on a control it did not draw.
    local openHeight = d.fixedHeightOpen or DG.FIXED_HEIGHT_OPEN
    local needed = openHeight + (debugOn and (d.diagnosticGaps + d.diagnosticMinimumHeight) or 0)
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
      if dialog and not d.detailsQuiet then setDialogStatus(GC.L["Enlarge the window to see details"]) end
    end
    -- layoutBlocks (called at the foot of this function) rewrites both of these for the shape
    -- that is actually on screen; the DG constants are the construction-time seed, before any
    -- verdict has been stamped.
    d.fixedHeight = d.detailsOpen and (d.fixedHeightOpen or DG.FIXED_HEIGHT_OPEN)
      or (d.fixedHeightClosed or DG.FIXED_HEIGHT_CLOSED)
    -- Task 2 restyle: uppercase kit-value labels (were "Show/Hide details"); the
    -- `d.detailsToggle:SetLabel(` call prefix itself is the pinned text (sniper_dialog_
    -- verdict_spec's "Details toggle wiring" describe block), not these strings.
    d.detailsToggle:SetLabel(d.detailsOpen and GC.L["HIDE DETAILS ▾"] or GC.L["SHOW DETAILS ▸"])
    for _, pair in ipairs(d.evidenceRows) do
      if d.detailsOpen then
        pair.label:Show()
        pair.value:Show()
      else
        pair.label:Hide()
        pair.value:Hide()
      end
    end
    -- The facts block and the transcript share one slot, so opening or closing Details moves
    -- everything under them. Runs AFTER the fit guard above has settled d.detailsOpen.
    layoutBlocks()
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
  cancelBtn:SetLabel(GC.L["Cancel"])
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
  primaryBtn:SetLabel(GC.L["Buy"])
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
    -- The sheet's own item hover (d.itemHit) opens a tooltip that only its OnLeave closes, and
    -- a sheet that closes under a stationary cursor -- a resolved purchase, Escape, the window
    -- going away -- never delivers one. Same release clearHover does for a deal row.
    GameTooltip:Hide()
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
    abortRowPurchase(row, GC.L["purchase canceled"])
  end)

  -- Mirror of the OnHide reset above: every time the sheet actually shows, the deals list
  -- shifts aside behind it (still gated on the window being wide enough -- see applyPanelInset).
  d:SetScript("OnShow", function()
    -- The window's own strata can have changed since this sheet was built -- docking adopts
    -- the auction house's -- and the sheet's opacity is only worth anything while it is in a
    -- strata above the rows it covers.
    d.raiseStrata()
    if frame and frame.applyPanelInset then frame.applyPanelInset(true) end
  end)

  -- Escape closes the drawer = cancel -- and ONLY the drawer. It used to be registered in
  -- UISpecialFrames, and CloseSpecialWindows hides every shown entry it holds: one press
  -- cancelled the check, closed the whole GoldCap window behind it, and (docked) handed the
  -- auction house back to Blizzard's own tab, for a player who only wanted out of the sheet.
  -- So the drawer captures the keypress itself and swallows ONLY Escape, exactly the way the
  -- settings overlay does (UI/SettingsFrame.lua) -- see there for why SetPropagateKeyboardInput
  -- is evaluated per keystroke rather than set once, and note that while the Quantity box has
  -- focus its own OnEscapePressed fires first and only clears focus.
  d:EnableKeyboard(true)
  d:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      self:Hide()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

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
    if prewarmAttempt.sent then GC.Sniper._FenceDrain(deal.itemID, prewarmAttempt) end
    prewarmAttempt = nil
  end

  dialog = dialog or createDialog()
  dialog.row = row
  dialog.cancelBtn:Enable()
  -- Fix 3: a prior visit may have left this relabeled "Close" (showGoneState) -- every fresh
  -- open is a normal purchase attempt again, never a "the thing you were looking at is gone"
  -- notice, so the label must reset unconditionally regardless of what the dialog last showed.
  dialog.cancelBtn:SetLabel(GC.L["Cancel"])
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
      -- Check panel v3: the kicker slot says the ANSWER in words now, so "LIVE VERDICT ·
      -- CHECKING" would be the only line left speaking the old machine-status voice.
      dialog.verdictLabel:SetText(GC.L["Checking..."])
      dialog.verdictLabel:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
    end
    if dialog.verdictAmount then
      dialog.verdictAmount:SetText("—")
      -- Item 3 (addon polish batch): the dialog is a session-long singleton, and the refusal
      -- branch above only Hides this widget -- it never resets its color, since a real refusal
      -- has nothing to show at all. Without this, a dash left over from an earlier buyable
      -- (green) check rendered CHECKING in leftover green, exactly like verdictLabel right
      -- above already resets.
      dialog.verdictAmount:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
      dialog.verdictAmount:Show()
    end
    -- Check panel v3: the discovery stamp above may have left the words "Can't price this"
    -- sitting in the figure's own slot, and the dash is now drawn over the top of them --
    -- they share the slot precisely because only one of the two is ever the answer.
    if dialog.heroText then dialog.heroText:Hide() end
    -- Same reason the amount is re-tinted: this band is a session-long singleton and would
    -- otherwise still be wearing the last deal's verdict colour while it says "Checking...".
    if dialog.setHeroTone then dialog.setHeroTone(Theme.color.fgDim) end
    -- The caption is shown but EMPTIED: whatever the discovery stamp captioned belongs to a
    -- figure that is no longer on screen.
    if dialog.verdictAmountNote then
      dialog.verdictAmountNote:SetText("")
      dialog.verdictAmountNote:Show()
    end
    setDialogStatus(GC.L["checking live safety..."])
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
      driver.onStatus(GC.L["finish the pending buy first"])
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

-- Live price caps, addon task 6: drains pendingCapPings (see refreshRows()'s own comment).
-- pingNewHotDeals is reused verbatim -- the SAME flash + PlaySound(MAP_PING) + FlashClientIcon
-- a full-scan HOT deal gets, never a second PlaySound for this bell. When the player has opted
-- in (settings.sniper.capStopAndOpen), onBuyClick is reused verbatim too: it is the row's own
-- click-path function, and openDialog inside it already calls GC.Sniper.NotifyDialogOpened
-- (the stop) before showing the dialog (the open) -- the exact reaction a manual click on the
-- row would trigger. Neither call reaches a protected purchase function: those stay behind
-- onDialogPrimaryClick's own hardware click, untouched (spec/sniper_purchase_wiring_spec.lua).
drainCapPings = function(pings)
  pingNewHotDeals(pings)
  if not (GC.db and GC.db.settings and GC.db.settings.sniper.capStopAndOpen) then return end
  for _, capDeal in ipairs(pings) do
    for i = 1, #rows do
      local row = rows[i]
      if row.deal == capDeal and row:IsShown() then
        onBuyClick(row)
        break
      end
    end
  end
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
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("sniper") end
    commodityDraining = nil
  end
  -- T6: a programmatic Hide() (this runs on AH close) doesn't reliably fire the row's own
  -- OnLeave, so clear the hover pin here too -- otherwise it could sit pinned to a hidden
  -- row across the next Auction House session. clearHover() (fix round 1, IMPORTANT-2): a
  -- bare `hoveredRow = nil` released the pin but left the row's highlight/rail textures
  -- painted -- nothing else ever hides `row.highlight` (setRowDeal only touches `rail`), so a
  -- row left hovered when the AH closes kept a permanent gold wash until hovered and left
  -- again.
  clearHover()
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
    btn:SetLabel(GC.L["Check"])
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
    -- Outside the window, never over it -- a row's own item tooltip used to cover the board
    -- it is describing (Theme.ItemTooltipOutside; see its own comment for the geometry).
    Theme.ItemTooltipOutside(self, frame)
    GameTooltip:SetItemByID(self.deal.itemID)
    -- What the background check found, in words. A refused row that the toolbar toggle has
    -- brought back into view is otherwise a status code and nothing else.
    local verdict = verdictFor(self.deal)
    if verdict then
      GameTooltip:AddLine(" ")
      if verdict.buyable then
        GameTooltip:AddLine(GC.L["GoldCap: checked live -- safe to buy"], 0.25, 0.85, 0.25)
      else
        -- The cell above says only WATCH; this is where the sentence behind it lives.
        GameTooltip:AddLine((GC.L["GoldCap: %s -- %s"]):format(verdict.status or "refused",
          GC.BoardRows.Reason(verdict) or GC.L["live verification required"]), 1, 0.82, 0)
      end
    elseif not self.deal.pinPlaceholder then
      -- Saying nothing here read as approval. The row already shows a tier, a discount and a
      -- profit -- all of it computed from the imported market snapshot, none of it confirmed
      -- against the live auction house -- and the only thing separating it from a row a live
      -- check HAD approved was the word on the button. That is too thin a line to carry the
      -- difference between an estimate and a finding, so the tooltip states it outright.
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(GC.L["GoldCap: not checked against the live auction house yet"], 0.7, 0.7, 0.7)
    end
    -- Sniper phase 2: a realm row's price is measured against the region, not against a
    -- verified market of its own, and the row's WATCH cell has no room to say so. The
    -- tooltip does -- with the reference itself and the item level it was measured on, so
    -- the player can see what the discount is a discount FROM.
    local realmValue = GC.Sniper._RealmValue(self.deal.itemID)
    if realmValue then
      GameTooltip:AddLine((GC.L["realm item — sale speed unverified · region reference %s (ilvl %d)"])
        :format(GC.Util.FormatMoney(realmValue.mv), realmValue.refIlvl or 0),
        Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
    elseif GC.Sniper._RealmNeedsReference(self.deal.itemID) then
      -- A pinned realm item the region has no price for. It is on the board because the player
      -- put it there, and the row cannot say anything about value -- so the tooltip says the
      -- same sentence a Check on it would, rather than leaving the blank cells to be read as
      -- "nothing to report".
      GameTooltip:AddLine(GC.SniperDecision.ReasonText("realm_no_reference"),
        Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
    end
    -- The hidden Buy button (setRowDeal's placeholder branch) leaves no control on this row to
    -- explain itself, so the tooltip carries the reason instead: watched, but nothing to buy.
    if self.deal.pinPlaceholder then
      GameTooltip:AddLine(GC.L["Watching — pinned, but not a deal right now"],
        Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
    end
    GameTooltip:AddLine(isPinned(self.deal.itemID)
      and GC.L["Right-click to stop watching this item"]
      or GC.L["Right-click to watch this item closely"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function(self)
    if hoveredRow == self then
      clearHover()
      refreshRows()
    else
      self.highlight:Hide()
      -- A watched row keeps its blue rail after the cursor leaves -- that is the whole point of
      -- it. Only the plain hover accent goes away here.
      if not (self.deal and isPinned(self.deal.itemID)) then self.rail:Hide() end
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

-- A saved position is only meaningful on the screen it was saved on, and nothing has ever
-- checked it: a resolution change, a UI-scale change, an eyefinity setup unplugged, or a
-- hand-edited SavedVariables can put the remembered offsets anywhere. The window then opens
-- off-screen, and an off-screen window cannot be dragged back -- the title bar you would drag
-- it by is off-screen with it, which is the whole bug. Offsets are measured from UIParent, so
-- half of the matching UIParent dimension keeps the anchor within the middle half of the
-- screen whichever corner it is anchored to: some of the window, including its title bar, is
-- always reachable. (`/goldcap reset`, and Settings' RESET WINDOW, are the way out if it ever
-- lands somewhere unhelpful anyway.)
local function clampWindowOffset(value, screen)
  if type(value) ~= "number" or type(screen) ~= "number" or screen <= 0 then return value end
  local limit = screen / 2
  if value < -limit then return -limit end
  if value > limit then return limit end
  return value
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
  -- A rail click can swap the view out from under a stationary cursor, and a row that hides
  -- that way never gets its own OnLeave (see clearHover's comment) -- so the hover pin stayed
  -- on a row nobody was pointing at, freezing that slot out of every later refreshRows(). The
  -- window's OnHide and the AH-close reset already release it here; this path did not.
  clearHover()
  -- One throttled search slot serves the whole addon: a Deals scan running behind the Sell
  -- tab starved the pricing walk's queries silently (see SellFrame.lua's advanceQuote). Auto
  -- pauses for as long as Sell is shown and resumes leaving it -- Sold never queries the AH,
  -- so switching to/from Sold neither pauses nor resumes this reason.
  if v == "sell" then
    feedAuto("pause:sell")
  elseif previousView == "sell" then
    feedAuto("resume:sell")
  end
  -- Same reason, same shape, for the BUY tab (see Core/AutoScan.lua's pause:buy).
  if v == "buy" then
    feedAuto("pause:buy")
  elseif previousView == "buy" then
    feedAuto("resume:buy")
  end
  -- A scan started by the Scan button is not Auto's, and Auto is the only thing those two feeds
  -- reach: addPause does nothing at all while the machine is OFF. So a manual pass carried on
  -- paging behind the Sell and Sold tabs -- replacing the browse buffer under the player's own
  -- Browse pane and taking throttle slots from the pricing walk, with no pause reason anywhere
  -- that could ever stop it. Auto's own passes still pause and resume as before.
  if v ~= "deals" and autoScan:State() == "OFF" and GC.Sniper._bookPass:IsPaging() then
    abortFullScan()
  end
  local isDeals = (v == "deals")
  if isDeals then
    frame.scroll:Show()
    frame.headerRow:Show()
    updateHeaderSortIndicators() -- re-draw the heading labels, see its comment
    if frame.restampRows then frame.restampRows() end -- and the rows under them, same reason
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
  -- AUTO, SCAN and HIDDEN each remember the label they last stamped and skip an identical
  -- restamp -- worth it off the 0.25s ticker, wrong here: a label that comes back from the
  -- hide above undrawn (the same thing that blanks the headings) would never be written
  -- again, leaving three blank buttons on the toolbar. Forget what was stamped, re-derive.
  if isDeals then
    if frame.autoBtn then frame.autoBtn.lastText, frame.autoBtn.lastOn = nil, nil end
    if frame.fullScanBtn then frame.fullScanBtn.lastBusy = nil end
    if frame.verifyBtn then frame.verifyBtn.lastText, frame.verifyBtn.lastOn = nil, nil end
    -- The board chips remember their last label for the same reason and come back from a hide
    -- undrawn for the same reason: forget, then re-derive.
    for _, chip in pairs(frame.boardChips or {}) do chip.lastText, chip.lastOn = nil, nil end
    refreshAutoButton()
    refreshScanButton()
    if refreshVerifyButton then refreshVerifyButton() end
    GC.Sniper._PaintBoardChips()
  end
  setTabActive(frame.dealsTab, isDeals)
  setTabActive(frame.sellTab, v == "sell")
  setTabActive(frame.soldTab, v == "sold")
  setTabActive(frame.buyTab, v == "buy")
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
  if v == "buy" then
    if GC.Buy and GC.Buy.Show then GC.Buy.Show() end
  elseif GC.Buy and GC.Buy.Hide then
    GC.Buy.Hide()
  end
end

-- Settings' OnHide (SettingsFrame.lua) calls this on every close path -- Escape, DONE, the
-- gear, a rail click, or the window closing -- to re-apply the active tab's Disable() that
-- setTabActive normally owns.
-- Settings enables every rail button for as long as it's open (see its own OnShow), so
-- closing it has to hand that Disable() back to whichever tab is actually current.
function GC.Sniper.RefreshRailActive()
  if not frame then return end
  setTabActive(frame.dealsTab, view == "deals")
  setTabActive(frame.sellTab, view == "sell")
  setTabActive(frame.soldTab, view == "sold")
  setTabActive(frame.buyTab, view == "buy")
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
  -- Uppercase in the key, never through :upper(): Lua's upper is byte-wise and leaves
  -- every non-ASCII letter alone, so a translated header would come back half-cased.
  local HEADER_TEXT = { item = GC.L["ITEM"], tier = GC.L["VERDICT"], disc = GC.L["DISC"],
    unit = GC.L["UNIT"], total = GC.L["PRICE"], profit = GC.L["PROFIT"], trend = GC.L["TREND"], buy = "" }
  local TOOLTIP = {
    tier = {
      GC.L["Verdict"],
      GC.L["SAFE = the live check approved this buy, at the profit shown"],
      GC.L["WATCH = the live check refused it -- hover the row for the reason"],
      GC.L["… = a live check is queued for this row"],
      GC.L["— = nothing is checking this row right now"],
    },
    disc = { GC.L["Discount"], GC.L["Discount vs market value from your GoldCap import"] },
    unit = { GC.L["Unit price"], GC.L["Per-unit price of this auction"] },
    total = { GC.L["Price"], GC.L["Total cost to buy this auction"] },
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
    profit = { GC.L["Profit"],
      GC.L["A lead, not a promise: resale at 95% of the imported market value, for the quantity Check itself would approve."],
      GC.L["Check re-derives it against the live order book before any gold moves, and can still land lower — or refuse — if the market has moved since your last import."],
      GC.L["Sort by it to decide what to Check first, not to decide what to buy."] },
  }

  local function buildHeaderCell(col)
    local hit = CreateFrame("Frame", nil, header)
    hit:SetHeight(CH.HEADER)
    local baseText = HEADER_TEXT[col.key] or ""
    local label = Theme.Num(hit, 9)
    -- One line, no wrapping -- the same pair buildRowCell puts on every deals row cell, and
    -- the same one the Sold and Sell headings carry. It is not cosmetic here: this label is
    -- SetAllPoints() onto a cell only CH.HEADER (16px) tall, and a wrapped line that does not
    -- fit the height it is given is not drawn at all. The whole heading row came out blank
    -- in-game with the hairline under it still showing and the cells still raising their
    -- tooltips -- text that is there, in a box that refuses to draw it.
    label:SetWordWrap(false)
    label:SetMaxLines(1)
    label:SetAllPoints()
    label:SetJustifyH(col.num and "RIGHT" or "LEFT")
    label:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3], Theme.color.fgDim[4] or 1)
    label:SetText(baseText)
    hit.label = label
    hit.baseText = baseText -- updateHeaderSortIndicators re-stamps from this on every re-show

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
  itemHit.label:SetWordWrap(false) -- see buildHeaderCell above for why both of these matter
  itemHit.label:SetMaxLines(1)
  itemHit.label:SetAllPoints()
  itemHit.label:SetJustifyH("LEFT")
  itemHit.label:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3], Theme.color.fgDim[4] or 1)
  itemHit.label:SetText(GC.L["ITEM"])

  -- Not read by any production code; exposed so the heading spec can reach the ITEM cell,
  -- which is not in header.cells (the flex column has no themed cell of its own). Same
  -- affordance UI/SoldFrame.lua's own header.itemCell exists for.
  header.itemCell = itemHit

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

  -- E.3 window position: ClearAllPoints then either the saved point/x/y (validated, clamped
  -- to the screen -- see clampWindowOffset -- and guarded by pcall against a corrupted/
  -- hand-edited SavedVariables value) or the original CENTER default.
  f:ClearAllPoints()
  local restored = false
  if isValidSavedWindow(savedWindow) then
    restored = pcall(f.SetPoint, f, savedWindow.point,
      clampWindowOffset(savedWindow.x, UIParent and UIParent:GetWidth()),
      clampWindowOffset(savedWindow.y, UIParent and UIParent:GetHeight()))
  end
  if not restored then
    f:ClearAllPoints()
    f:SetPoint("CENTER")
  end

  f:SetMovable(true)
  f:EnableMouse(true) -- blocks clicks from passing through to whatever's behind the window

  -- Layering. This window shipped with neither of these, so it sat at UIParent's own level:
  -- under the auction house, under the bags, under every Blizzard panel a goldmaker has
  -- open at once -- and clicking it did not bring it forward, because only a TOPLEVEL frame
  -- raises itself within its strata. Both are required; strata alone still loses to a
  -- sibling at HIGH, and toplevel alone cannot climb out of a lower strata.
  --
  -- HIGH, not DIALOG: the confirmation sheet above sits at DIALOG precisely so it clears
  -- this window, and Blizzard's own popups live there too. See GC.Sniper.SetDocked, which
  -- undoes both while the window is a child of the auction house panel.
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)

  -- Chrome: Theme.TitleBar owns the drag region (title bar only, not the whole window),
  -- the close button (outer top-right), and the gear (inboard-left of close).
  local titleBar = Theme.TitleBar(f, GC.L["GoldCap Sniper"])
  f.closeBtn = titleBar.close
  -- Kept as a field so docked mode (GC.Sniper.SetDocked below) can blank the duplicate
  -- chrome: inside the auction house the AH frame already provides the title and the close.
  f.titleBar = titleBar
  -- hooksecurefunc, not an OnDragStop/OnMouseUp script: see persistWindowGeometry's own
  -- comment for why the method-hook is what unifies both hardware-driven geometry changes.
  hooksecurefunc(f, "StopMovingOrSizing", persistWindowGeometry)

  -- Rail (Sniper v4): the Deals/Sell/Sold/Buy switcher is a 76px left rail of big
  -- targets (Theme.Rail), not a row of 50x18 ghost tabs. The f.dealsTab/
  -- f.sellTab/f.soldTab/f.buyTab FIELDS survive on purpose: setView and
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
  rail.buttons.buy:SetScript("OnClick", function()
    if GC.SettingsUI and GC.SettingsUI.Hide then GC.SettingsUI.Hide() end
    setView("buy")
  end)
  f.rail = rail
  f.dealsTab, f.sellTab, f.soldTab = rail.buttons.deals, rail.buttons.sell, rail.buttons.sold
  f.buyTab = rail.buttons.buy
  setTabActive(f.dealsTab, true) -- Deals is the default view
  setTabActive(f.sellTab, false)
  setTabActive(f.soldTab, false)
  setTabActive(f.buyTab, false)

  -- Settings entry lives on the rail now; TitleBar still builds its gear for
  -- other callers, this window just doesn't show two of them.
  titleBar.gear:Hide()
  rail.gear:SetScript("OnClick", function() GC.SettingsUI.Toggle() end)
  -- Item 8 (addon polish batch): point the field at the live control, not the hidden
  -- title-bar one just above -- a trap for future code reading f.gearBtn expecting a wired
  -- Settings button.
  f.gearBtn = rail.gear

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
  autoBtn:SetLabel(GC.L["AUTO"])
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
      if view == "buy" then feedAuto("pause:buy") end -- same standing reason as sell above
      if GC.Sniper._Board() == "items" then feedAuto("pause:items") end -- same standing reason, see _SetBoard
    else
      if cfg then cfg.auto = false end
      feedAuto("toggleOff")
    end
  end
  autoBtn:SetScript("OnClick", onAutoToggleClick)
  -- One key for the whole sentence, never a line-break's worth of fragments concatenated:
  -- word order is not a constant across languages, so a sentence assembled here can only ever
  -- come out in English order however well each piece is translated.
  setPlainTooltip(autoBtn, GC.L["Auto: keeps Full Scan running continuously, yielding instantly whenever you buy, search the Auction House yourself, or check your mail. Click to toggle."])

  -- The refused-rows toggle, in the slot the Live button vacated (see below). Background
  -- verification (tickAutoVerify) hides rows a live Check has refused, and a shorter list with
  -- nothing explaining it is its own lie -- this is the number and the switch. One button with
  -- two variants (never two swapped by Show/Hide), per the addon's engineering notes. Anchored top-RIGHT now
  -- (was Scan's slot): it and Scan swap sides of the row so Auto/Refused-Hidden bookend it.
  local verifyBtn = Theme.Button(f, "ghost", "plaque")
  verifyBtn:SetSize(76, CH.BTN_H)
  verifyBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -WIN.CONTENT_RIGHT_GUTTER, row2Y)
  verifyBtn:SetLabel(GC.L["HIDDEN 0"])
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
    GameTooltip:SetText(GC.L["Background check"], 1, 1, 1)
    GameTooltip:AddLine((GC.L["GoldCap re-checks the top %d rows against the live auction house about every %ds. Rows it refuses are hidden. Buying always stays a click you make."])
      :format(LIM.VERIFY_TOP_ROWS, LIM.VERIFY_INTERVAL_SECONDS), 1, 1, 1, true)

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
    GameTooltip:AddLine((GC.L["Checked: %d of the top %d on screen"]):format(
      checked, math.min(#list, LIM.VERIFY_TOP_ROWS)), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(newest
      and (GC.L["Last result: %ds ago"]):format(math.floor(GetTime() - newest))
      or GC.L["Last result: none yet this visit"], 0.7, 0.7, 0.7)
    GameTooltip:AddLine((GC.L["Refused so far: %d"]):format(refusedCount), 0.7, 0.7, 0.7)
    local watched = #GC.Sniper._liveTargets
    if watched > 0 then
      GameTooltip:AddLine((GC.L["Watching closely: %d item%s"]):format(watched, watched == 1 and "" or "s"),
        0.7, 0.7, 0.7)
      GameTooltip:AddLine(GC.Sniper._cycleSeconds
        and (GC.L["Full pass over them: %.1fs"]):format(GC.Sniper._cycleSeconds)
        or GC.L["Full pass over them: measuring..."], 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
  end)
  verifyBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
  f.verifyBtn = verifyBtn

  local fullScanBtn = Theme.Button(f, "ghost", "plaque")
  fullScanBtn:SetSize(64, CH.BTN_H)
  fullScanBtn:SetPoint("RIGHT", verifyBtn, "LEFT", -Theme.pad.xs, 0)
  fullScanBtn:SetLabel(GC.L["SCAN"])
  fullScanBtn:SetScript("OnClick", onFullScanClick)
  setPlainTooltip(fullScanBtn,
    GC.L["One-shot scan of the entire Auction House via paged browse queries. Takes roughly 15-60 seconds on busy realms. No cooldown -- rescan anytime."])
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
    -- Through GC.L: these two were the last labels on the toolbar still stamped in English on
    -- every client, because the first paint used the wrapped "HIDDEN 0" and every repaint after
    -- it came through here.
    local text = (show and GC.L["REFUSED %d"] or GC.L["HIDDEN %d"]):format(refusedCount)
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
  -- One line, no wrapping, same pair every other single-line cell in the kit carries. This
  -- one is anchored TOPLEFT *and* RIGHT, so it has a fixed width and a height of one line:
  -- a long message ("Posting…" and ~40 others from the Sell tab come through here) wrapped
  -- to a second line that does not fit, and a line that does not fit its box is not drawn at
  -- all -- the longest, most useful messages were the ones that said nothing.
  status:SetWordWrap(false)
  status:SetMaxLines(1)
  local muted = Theme.color.fgMuted
  status:SetTextColor(muted[1], muted[2], muted[3], muted[4] or 1)
  status:SetPoint("TOPLEFT", autoBtn, "TOPRIGHT", Theme.pad.s, 0)
  status:SetPoint("RIGHT", f.sessionText, "LEFT", -Theme.pad.s, 0)
  status:SetText(GC.L["Open the Auction House to begin scanning."])
  f.status = status

  -- Row 3: the board switch -- COMMODITIES | ITEMS N, the Sell tab's own deck chips
  -- (SellFrame.lua's deckButtons/paintDeckSwitch) applied to the same kind of question. Two
  -- boards, because the rows are two different promises: a commodity row is region-priced,
  -- live-verifiable and can become BUY, a realm row is a lead on gear/pets/recipes that can
  -- only ever be WATCH. See GC.Sniper._Board.
  --
  -- Its OWN row, directly above the headings, exactly where Sell puts its deck switch -- not
  -- in the control row above. That row is AUTO + status + SCAN + HIDDEN and 480 of the 600
  -- content pixels a 720-wide window has; two chips in it leave the status line about 80px,
  -- and a status line that does not fit its box is not drawn at all (see `status` above), so
  -- the longest, most useful messages would be the ones that vanished. One list row is the
  -- cheaper price.
  local boardY = row2Y - (CH.BTN_H + Theme.pad.s)
  f.boardChips = {}
  local chipPrevious
  for _, id in ipairs({ "commodities", "items" }) do
    local chip = Theme.Button(f, "ghost", "plaque")
    -- 132/96, sized the way every other label on this toolbar is: mono-10 at Theme.Scale()
    -- 1.3 is ~7.8px a character, so "COMMODITIES" is 86px and "ITEMS 100" 70px, plus the
    -- rounded plaque's own inset.
    chip:SetSize(id == "commodities" and 132 or 96, CH.BTN_H)
    if chipPrevious then chip:SetPoint("LEFT", chipPrevious, "RIGHT", Theme.pad.xs, 0)
    else chip:SetPoint("TOPLEFT", f, "TOPLEFT", WIN.CONTENT_LEFT, boardY) end
    chip:SetScript("OnClick", function() GC.Sniper._SetBoard(id) end)
    f.boardChips[id] = chip
    chipPrevious = chip
  end
  setPlainTooltip(f.boardChips.commodities,
    GC.L["Commodities: reagents, consumables, gems and enchants the scan found under their region price. These are the rows a live check can approve for buying."])
  setPlainTooltip(f.boardChips.items,
    GC.L["Items: gear, pets and recipes priced against the region reference from your import. Sale speed goes unmeasured, so these never clear SAFE -- the buy is your call, and GoldCap only checks them while this board is open."])
  GC.Sniper._PaintBoardChips(f)

  -- Deals-only toolbar chrome: setView shows/hides these alongside the scroll/header
  -- toggle it already drives, so Sell/Sold don't sit under a Deals-specific control/session
  -- row that means nothing on their view. See setView's own comment on this field.
  --
  -- `status` is deliberately NOT in this list. GC.Sell.Attach (SellFrame.lua) captures this
  -- same `f` as `statusOwner` and its own setStatus() routes ~40 user-facing messages
  -- ("Posting…", "Click Confirm to post", timeouts, etc.) through `statusOwner.status:SetText`
  -- -- it is a shared channel across every view, not a Deals-only readout. Hiding it here
  -- would mute Sell's entire posting-feedback channel while the Sell view is showing.
  f.dealsChrome = { verifyBtn, fullScanBtn, autoBtn, f.toolbarDivider, f.sessionText,
    f.boardChips.commodities, f.boardChips.items }

  -- Row 4: column headers, sticky above the scroll area.
  f.headerY = boardY - (CH.BTN_H + Theme.pad.xs)
  createHeaderRow(f)

  local scrollTop = f.headerY - (CH.HEADER + Theme.pad.xs)
  local scrollBottom = Theme.pad.m

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  if Theme.QuietScrollBar then Theme.QuietScrollBar(scroll) end -- no Blizzard arrows beside a kit panel
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

  -- The rows' half of updateHeaderSortIndicators' job (see its comment for the mechanism).
  -- Leaving Deals hides the rows' PARENT (setView hides `scroll`), so every pooled row still
  -- reports IsShown() and setRowDeal's repaint skip -- which exists so a row whose content
  -- never moved isn't rebuilt several times a second -- declines to touch it on the way back.
  -- Its cells are the same one-line FontStrings the headings are, and they come back from a
  -- parent's hide just as blank. Forgetting what each slot last stamped is what makes the
  -- refresh below write every cell again. A pool that is still empty has nothing to restamp
  -- and no scroll child sized for it yet -- the first real render does both.
  f.restampRows = function()
    if #rows == 0 then return end
    for i = 1, #rows do rows[i]._dealSig = nil end
    refreshRows()
  end
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
  -- SHIFT_MIN, 990 wide); narrower windows -- the docked AH is ~805 -- get an opaque overlay
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

  GC.Buy.Attach(f, {
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
    if GC.Sniper._Board() == "items" then feedAuto("pause:items") end -- the remembered board, see _SetBoard
    feedAuto("resume:search")
    updateHeaderSortIndicators() -- heading labels can come back blank after a hide, see its comment
    if view == "deals" then f.restampRows() end -- and so can the row cells under them
  end)
  f:SetScript("OnHide", function()
    feedAuto("tabHidden")
    -- Fix batch (stuck-hover freeze): a hidden window never fires the hovered row's own OnLeave
    -- reliably (see clearHover's comment) -- release the pin here too, or that row is stuck
    -- excluded from every future refreshRows() until the exact same screen position is
    -- re-hovered.
    clearHover()
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
    -- Give up the floating window's own layering (createFrame: HIGH + toplevel). Docked,
    -- this is a CHILD of the host panel and has to stack WITH it -- keeping HIGH would paint
    -- our content over the auction house's own dropdowns and its close button, and keeping
    -- toplevel would yank the whole thing forward on every click inside it.
    frame:SetFrameStrata(host:GetFrameStrata())
    frame:SetToplevel(false)
    -- The drawer follows the window up: adopting the host's strata can otherwise land the
    -- window level with a drawer that was pinned one strata above the UNDOCKED window, and
    -- level with is enough for the deals rows to draw through an opaque sheet.
    if dialog and dialog.raiseStrata then dialog.raiseStrata() end
    -- The settings overlay follows for the same reason: it wins on LEVEL inside the window's
    -- own strata, and the engine reassigns child levels when the parent's strata changes.
    if GC.SettingsUI and GC.SettingsUI.Raise then GC.SettingsUI.Raise() end
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
    -- Back to a window of its own: see createFrame for why both calls are needed.
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    if dialog and dialog.raiseStrata then dialog.raiseStrata() end
    if GC.SettingsUI and GC.SettingsUI.Raise then GC.SettingsUI.Raise() end
    frame:SetMovable(true)
    if frame.resizeHandle then frame.resizeHandle:Show() end
    if frame.titleBar and frame.titleBar.title then frame.titleBar.title:SetText(GC.L["GoldCap Sniper"]) end
    if frame.closeBtn then frame.closeBtn:Show() end
    frame:ClearAllPoints()
    local cfg = GC.db and GC.db.settings and GC.db.settings.sniper
    local saved = cfg and cfg.window
    local restored = false
    if isValidSavedWindow(saved) then
      restored = pcall(frame.SetPoint, frame, saved.point, -- clamped, same as createFrame's restore
        clampWindowOffset(saved.x, UIParent and UIParent:GetWidth()),
        clampWindowOffset(saved.y, UIParent and UIParent:GetHeight()))
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
  -- Sniper phase 2: same reasoning for the realm poll. Its set comes from SavedVariables (the
  -- pins) and the import (the site watchlist and the region's targets), none of which the AH
  -- session knows about until something asks -- and the first cycle of the visit is the one
  -- that most needs a set to walk.
  GC.Sniper._RebuildKeyTargets()

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
    -- And so does the one send that has nothing to ride on. A pass start parks until a grant
    -- (Core/BookPass.lua), but AUCTION_HOUSE_THROTTLED_SYSTEM_READY fires when the system
    -- BECOMES ready -- an idle, already-ready client may never fire one, and a pass that never
    -- sends never arms its own watchdog either, so Auto would sit on SCANNING forever. Only
    -- the START is nudged: a pending page always has a browse event behind it, and polling for
    -- pages at 4Hz would be the throttle hammering this addon has been burned by before.
    -- Claimed, not merely asked: with a throttle flag that has stopped changing, driver.isReady
    -- answers true on every one of these four-a-second ticks, and the arbiter below sends
    -- exactly one message per call -- so without the claim this line alone would page the
    -- auction house four times a second. One forced send per window, the Sell tab gets its own.
    if GC.Sniper._bookPass:PendingStart() and driver.isReady()
        and (not driver.claimSend or driver.claimSend()) then
      GC.Sniper.OnThrottleReady()
    end
    -- The Items board's first batch has the same problem as a pass start: with the pass
    -- paused for this board nothing else brings a ready tick, so a batch that could not go at
    -- the moment of the switch (throttle not ready, a page still landing) waited on luck --
    -- thirty seconds in game. Once a second, ask; the helper itself claims the send.
    local now = GetTime()
    if now - (GC.Sniper._keysPokeAt or 0) >= 1 then
      GC.Sniper._keysPokeAt = now
      if GC.Sniper._Board() == "items" and view == "deals" and not GC.Sniper._KeysOutstanding() then
        GC.Sniper._TrySendKeysBatch()
      end
      -- The BUY tab has exactly the same problem and no clock of its own at all: with Auto
      -- paused for it (setView's "pause:buy") nothing on that tab sends anything, so no ready
      -- tick ever arrives to carry its twenty-second refresh. Same once-a-second ask; the
      -- helper owns the interval, the view gate and the claim.
      if GC.Buy and GC.Buy.Tick then GC.Buy.Tick() end
      -- And the Sell tab's bulk price fill, asked for by a press of Refresh that found the
      -- slot taken: nothing else on that tab would carry the retry.
      if GC.Sell and GC.Sell.Tick then GC.Sell.Tick() end
    end
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
    if view == "buy" then feedAuto("pause:buy") end
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
      frame.status:SetText((GC.L["%d deals from your last scan -- Full Scan to refresh"]):format(#scanDeals))
    else
      frame.status:SetText(GC.L["Press Full Scan to find deals."])
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
    GC.Print((GC.L["session: %d snipes, spent %s, ~%s est. profit"]):format(
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
    GC.Print((GC.L["scanned %d listings over %d passes"]):format(scanner.scanned, scanner.cycles))
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
  -- Same reasoning, and the same session boundary: the book is what each item's floor was the
  -- last time we looked, and the drill queue is a list of prices worth a live look. Kept
  -- across the close, the first pass of the next session says nothing about every item whose
  -- price has not moved since -- the one pass that most needs to speak -- and the queue drills
  -- prices nobody has seen for hours. The wide-pass clock is left alone on purpose (see
  -- Core/BookPass.lua's Reset).
  GC.Sniper._bookPass:Reset()
  -- The key poll's book is the same kind of claim about the same session (Core/KeyPoll.lua's
  -- own Reset), and a batch that was in flight when the session ended has nothing left to
  -- answer it -- the counters go with it so the next visit's readout counts its own traffic.
  GC.Sniper._keyPoll:Reset()
  GC.Sniper._keysAwaiting = nil
  GC.Sniper._keysBatch = nil
  GC.Sniper._keysOwner = nil
  GC.Sniper._keysThisCycle = 0
  GC.Sniper._keysLastCycle = 0
  for itemID in pairs(GC.Sniper._realmDeals) do GC.Sniper._realmDeals[itemID] = nil end
  -- The Items chip carries that store's own count, and clearDeals above rendered before this
  -- wipe -- without this the chip would still be claiming rows until the next visit's first
  -- render. (The window is going away either way; a control that lies while it is on screen
  -- for one more frame is still a control that lies.)
  GC.Sniper._PaintBoardChips()
  GC.Sniper._drillQueue:Clear()
  GC.Sniper._wideExtras = nil
  -- Same reasoning for background verdicts, and one more: a verdict is a claim about a live
  -- order book, and there is no live order book once the session is gone. scanDeals survives
  -- the close on purpose (see OnAuctionHouseShow) -- its verdicts must not, or the next visit
  -- opens with gold Buy buttons vouched for by a market nobody has looked at since.
  for itemID in pairs(verdicts) do verdicts[itemID] = nil end
  refusedCount = 0
  verifyWalkAt = 0
  GC.Sniper._verifySlice = nil
  -- D: abort any in-flight Sell quote walk/post -- neither can safely resume once the AH
  -- session is gone (same reasoning as resetAllPurchases above for the Deals side).
  GC.Sell.Reset()
  if frame then frame:Hide() end
end

-- `/gc board`: the Items board's supply chain in one chat block -- what the key poll has to
-- ask about, whether a batch is out, what would stop the next one, and how many realm rows
-- the store holds. For a live client showing an empty Items board with nothing on screen
-- that says which gate is closed.
-- `/gc purchase`: the commodity purchase state, for the one question the board dump cannot answer
-- -- why a Buy is being refused. Every refusal in onDialogPrimaryClick reads from what is printed
-- here: the shared slot and its age, the attempt in flight and its stage, the tombstone and
-- whether it is confirmed (a confirmed one is never retired on a timer), the record-only
-- stranded confirms, and the requeries still waiting for a result.
function GC.Sniper.DebugPurchase()
  local function s(v) return tostring(v) end
  local now = GetTime()
  local owner = GC.PurchaseSlot and GC.PurchaseSlot.Owner()
  GC.Print(("slot: owner=%s busy=%s"):format(s(owner),
    s(GC.PurchaseSlot and GC.PurchaseSlot.IsBusy() or false)))
  local pending = commodityPurchase
  if pending then
    GC.Print(("attempt: item=%s token=%s stage=%s confirmed=%s wasConfirmed=%s cancelRequested=%s"):format(
      s(pending.itemID), s(pending.token), s(pending.row and pending.row.purchaseStage),
      s(pending.confirmed), s(pending.wasConfirmed), s(pending.cancelRequested)))
  else
    GC.Print("attempt: none")
  end
  local tomb = commodityDraining
  if tomb then
    GC.Print(("tombstone: item=%s token=%s confirmed=%s wasConfirmed=%s age=%ds fenceToken=%s"):format(
      s(tomb.itemID), s(tomb.token), s(tomb.confirmed), s(tomb.wasConfirmed),
      math.floor(now - (tomb.drainingAt or now)), s(tomb.fenceToken)))
  else
    GC.Print("tombstone: none")
  end
  local stranded = 0
  for _ in pairs(GC.Sniper._strandedConfirmed) do stranded = stranded + 1 end
  local waiting = {}
  for itemID in pairs(awaitingRequery) do waiting[#waiting + 1] = s(itemID) end
  local draining = {}
  for itemID in pairs(requeryDraining) do draining[#draining + 1] = s(itemID) end
  GC.Print(("strandedConfirmed=%d awaitingRequery=[%s] requeryDraining=[%s] quiet=%s"):format(
    stranded, table.concat(waiting, ","), table.concat(draining, ","), s(GC.Sniper.IsPurchaseQuiet())))
  for itemID, status in pairs(detachedCommodityStatus) do
    GC.Print(("detached: item=%s token=%s note=%s"):format(s(itemID), s(status.token), s(status.note)))
  end
end

function GC.Sniper.DebugBoard()
  local function s(v) return tostring(v) end
  local poll, pass = GC.Sniper._keyPoll, GC.Sniper._bookPass
  local data = GC.Data or {}
  local targets = data.TargetIds and #data.TargetIds() or -1
  local watch = data.GetWatchlist and #data.GetWatchlist(0) or -1
  local pins = #GC.Sniper._WatchPins()
  GC.Print(("board: %s view=%s mode=%s ahOpen=%s realmRows=%d scanDeals=%d"):format(
    GC.Sniper._Board(), s(view), s(mode), s(ahOpen), GC.Sniper._RealmCount(), #scanDeals))
  -- `owner` matters as much as `keysAwaiting` does: the BUY tab spends the same one batch, so
  -- "a batch is out" on a board that looks stuck is only half an answer without whose it is.
  GC.Print(("poll: targets=%d pending=%s (site targets=%d watchlist=%d pins=%d) keysAwaiting=%s owner=%s batch=%s thisCycle=%s lastCycle=%s"):format(
    poll:Count(), s(poll:HasPending()), targets, watch, pins,
    GC.Sniper._keysAwaiting and (time() - GC.Sniper._keysAwaiting) .. "s ago" or "nil",
    s(GC.Sniper._keysOwner),
    GC.Sniper._keysBatch and #GC.Sniper._keysBatch or "nil",
    s(GC.Sniper._keysThisCycle), s(GC.Sniper._keysLastCycle)))
  GC.Print(("gates: paging=%s passWants=%s fullBrowse=%s playerBusy=%s prewarm=%s quiet=%s apiReady=%s"):format(
    s(pass:IsPaging()), s(pass:Wants()),
    s(C_AuctionHouse and C_AuctionHouse.HasFullBrowseResults and C_AuctionHouse.HasFullBrowseResults()),
    s(GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy and GC.AuctionHouseTab.PlayerIsBusy()),
    s(prewarmAttempt ~= nil), s(GC.Sniper.IsPurchaseQuiet()),
    s(C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and C_AuctionHouse.IsThrottledMessageSystemReady())))
  local reasons = {}
  for r in pairs(autoScan:PauseReasons()) do reasons[#reasons + 1] = r end
  local tab = GC.AuctionHouseTab or {}
  GC.Print(("auto: state=%s reasons=[%s] pendingStart=%s busy: posting=%s buying=%s otherTab=%s searching=%s"):format(
    autoScan:State(), table.concat(reasons, ","), s(pass:PendingStart()),
    s(tab.PlayerIsPosting and tab.PlayerIsPosting()), s(tab.PlayerIsBuying and tab.PlayerIsBuying()),
    s(tab.PlayerIsUsingAnotherTab and tab.PlayerIsUsingAnotherTab()), s(tab.PlayerIsSearching and tab.PlayerIsSearching())))
  if GC.Util and GC.Util.TraceDump then
    local t = GC.Util.throttleStats
    GC.Print(("throttle events: queued=%d dropped=%d ready=%d forcedSends=%d"):format(t.queued, t.dropped, t.ready, t.forced))
    for _, line in ipairs(GC.Util.TraceDump(40)) do GC.Print(line) end
  end
end
