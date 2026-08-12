local _, GC = ...

GC.Sell = GC.Sell or {}

local Theme = GC.Theme

-- ---------------------------------------------------------------------------
-- Sniper v3 Task 9: the Sell view is now a flips TABLE (bought/listed/market/profit/status),
-- not a bags-vs-mail checklist -- GC.Flips.BuildRow/Summary (Core/Flips.lua, T4) own the pure
-- data model; this file's job is composing their inputs (db.flips + owned AH lots + live
-- quotes + ledger sales) and rendering the result on Theme, same COLUMNS-table idiom
-- UI/SniperFrame.lua's T5 restyle established for the Deals grid. GC.Sell.Attach(f, geometry)
-- is called once from SniperFrame.lua's createFrame; every other entry point here (Show/Hide/
-- Refresh/Reset/the throttle+search-result routers/OnOwnedAuctions) is driven by SniperFrame.lua's
-- tab switcher or Core/Init.lua's event dispatch.
--
-- KEPT UNCHANGED (constraint: rebuild rendering AROUND these, not through them): the quote
-- walker (advanceQuote/onRefreshClick/OnThrottleReady/OnItemKeyInfo/OnItemSearchResults/
-- OnCommoditySearchResults), the Post flow's PostItem/PostCommodity/Confirm* compliance
-- discipline and postingRow single-in-flight-post gate, and AUCTION_HOUSE_AUCTION_CREATED/
-- AUCTION_HOUSE_POST_ERROR event correlation via that same pinned slot.
-- ---------------------------------------------------------------------------

local ROW_HEIGHT   -- from geometry (GC.Sell.Attach), == Theme.ROW_H via SniperFrame.lua
local ROW_WIDTH    -- from geometry (GC.Sell.Attach)

local ICON_SIZE = 16
local DASH = "—"

local POST_DURATION = 2 -- 24h; C_AuctionHouse.PostItem/PostCommodity duration enum: 1=12h, 2=24h, 3=48h (verified against warcraft.wiki.gg)
local POST_TIMEOUT_SECONDS = 8
local QUOTE_STALE_SECONDS = 10 -- mirrors Core/Scanner.lua's own STALE_SECONDS for a pending search that never got an answer
local REPOST_ARM_SECONDS = 3    -- brief's "3s window" -- mirrors SniperFrame.lua's REQUOTE_ARM_SECONDS idiom (armLoudConfirm): a click already on its way when the button morphs must not land on the confirm
local REPOST_DISARM_SECONDS = 10 -- fix round 1 (I1): total window an ARMED-but-unconfirmed repost stays armed before auto-disarming back to idle -- an escape hatch for a player who clicked Repost and then walked away, so the row doesn't sit showing "Cancel lot?" forever

-- Bag range: backpack (0) + four bags (1-4) + reagent bag (5).
local SELL_BAGS = { 0, 1, 2, 3, 4, 5 }

local container -- built once by Attach; hidden until the Sell tab is shown
local content   -- scroll child; rows are pooled into this, same pattern as SniperFrame's `content`
local rows = {}
local statusOwner -- the sniper frame `f` -- status text is shared with the Deals view (only one view is ever visible)

-- Quoting state: exactly one SendSearchQuery-style query in flight at a time (see requestQuote/
-- advanceQuote below), scoped entirely to this module -- zero crosstalk with the watchlist
-- scanner's own pending slot or the buy-requery's awaitingRequery/awaitingKeyInfo tables in
-- SniperFrame.lua.
local quoting = false
local quoteQueue = {}
local quoteIndex = 0
local pendingQuote = nil       -- itemID awaiting its search-results event (nil = idle)
local pendingQuoteSince = 0
local awaitingKeyInfo = nil    -- itemID waiting on ITEM_KEY_ITEM_INFO_RECEIVED before its query can even be sent
local quotes = {}              -- itemID -> last-quoted lowest unit price (session-only; survives an AH close, like Full Scan results do)

-- Owned-lots state (Task 9): C_AuctionHouse.QueryOwnedAuctions({})/GetOwnedAuctions() results,
-- extracted to the {itemID, unitPrice, auctionID} shape GC.Flips.BuildRow expects. Queried on
-- tab show and on the ghost Refresh button ONLY -- never in the Auto loop or any other timer --
-- and left alone (not requeried) on every other render, same "persist across a close/reopen"
-- choice as `quotes` above.
local ownedLots = {}

-- Task 9 §5: a sale ledger entry never carries itemID (Core/Ledger.lua's ScanInbox -- a sale
-- mail has money attached and nothing else, itemName is all there is to key on), so SOLD_PENDING
-- detection has to go through the item's resolved display name instead. itemNames caches
-- itemID -> name as it becomes available (both the synchronous best-effort lookup in
-- resolveItemName below and the async icon/name load in setRowFlip keep it current).
local itemNames = {}

-- Posting state: only ONE post may be in flight addon-wide (mirrors SniperFrame's single
-- in-flight commodityPurchase slot) -- AUCTION_HOUSE_AUCTION_CREATED/AUCTION_HOUSE_POST_ERROR
-- carry no per-post identity, so a single pinned row is the only way to attribute either event
-- to the right flip.
local postingRow = nil

-- Repost state (Task 9): a SECOND, independent single-in-flight slot -- cancelling one item's
-- undercut lot and posting a different item are unrelated C_AuctionHouse calls, so there is no
-- reason to serialize them behind the same gate as postingRow. Pinned the same way: renderRows
-- leaves this row's widget content untouched instead of reassigning it mid-flow.
local repostingRow = nil
local repostArmToken = 0

-- Live driver bound to C_AuctionHouse, built the same way SniperFrame.lua's own `driver` is
-- (every WoW-API access wrapped in a function, so the table itself has no side effects at
-- file-load -- required for the headless busted load-order spec). Deliberately mirrors
-- SniperFrame's driver.itemResult/commodityResult exactly (same per-unit price extraction,
-- same buyoutAmount-is-a-lot-TOTAL-for-items division) -- this module just returns the bare
-- unit price instead of a whole result table, since that's all the Sell view ever needs.
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
    -- buyoutAmount is the TOTAL price for the whole lot, not per-unit -- see SniperFrame.lua's
    -- driver.itemResult for the same division.
    return math.floor(info.buyoutAmount / info.quantity)
  end,

  commodityResult = function(itemID)
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
    if not info then return nil end
    return info.unitPrice
  end,
}

local GOLD_COMPACT_THRESHOLD = 100 * 10000 -- mirrors SniperFrame.lua's formatColumnAmount

local function formatAmount(copper)
  if not copper then return "?" end
  if copper >= GOLD_COMPACT_THRESHOLD then
    return ("%dg"):format(math.floor(copper / 10000))
  end
  return GetCoinTextureString(copper)
end

-- Profit can go negative (an UNDERCUT row projecting a loss) -- GetCoinTextureString expects a
-- non-negative amount, so the sign is peeled off and reapplied around formatAmount rather than
-- handed to it directly.
local function formatProfitText(copper)
  if copper == nil then return DASH end
  if copper < 0 then return "-" .. formatAmount(-copper) end
  return formatAmount(copper)
end

local function setStatus(text)
  if statusOwner and statusOwner.status then statusOwner.status:SetText(text) end
end

local function setColor(fs, c)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function countInBags(itemID)
  local n = 0
  for _, bag in ipairs(SELL_BAGS) do
    local slots = C_Container.GetContainerNumSlots(bag)
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == itemID then
        n = n + (info.stackCount or 1)
      end
    end
  end
  return n
end

-- First stack matching itemID -- exactly what the Post click needs an ItemLocation for.
local function findBagSlot(itemID)
  for _, bag in ipairs(SELL_BAGS) do
    local slots = C_Container.GetContainerNumSlots(bag)
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == itemID then
        return bag, slot
      end
    end
  end
  return nil
end

local function uniqueFlipItemIDs()
  local seen, ids = {}, {}
  for _, flip in ipairs(GC.Data.GetFlips()) do
    if not seen[flip.itemID] then
      seen[flip.itemID] = true
      ids[#ids + 1] = flip.itemID
    end
  end
  return ids
end

-- Position of `flip` (a table reference, not a copy) in the CURRENT db.flips array -- needed
-- because GC.Data.MarkFlipPosted/RemoveFlip take an index, but this module tracks in-flight
-- rows by the flip's own table identity (see postingRow/repostingRow above and row.flip below),
-- which stays valid across renders even as other entries get posted/removed/pruned around it.
local function currentIndexOf(flip)
  local flips = GC.Data.GetFlips()
  for i, f in ipairs(flips) do
    if f == flip then return i end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Owned auctions (Task 9 Step 1): extraction (GC.Flips.ExtractOwnedLots, moved to Core/Flips.lua
-- in fix round 1 so it's pure/tested there -- see I3's stacked-item-lot division fix) and the
-- cheapest-pick lookup (GC.Flips.CheapestOwnedLot) both live there now; this file just drives
-- the WoW-API side of fetching/requesting them.
-- ---------------------------------------------------------------------------

-- fix round 1 (I4): no-ops without a live AH session -- QueryOwnedAuctions has nothing to
-- answer once the player has left the auction house, and firing it anyway risked a stray
-- OWNED_AUCTIONS_UPDATED landing well after the fact. GC.Sniper.IsAHOpen() is a one-line
-- accessor SniperFrame.lua added over its existing `ahOpen` local for exactly this gate.
local function requestOwnedAuctions()
  if not (C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions) then return end
  if GC.Sniper.IsAHOpen and not GC.Sniper.IsAHOpen() then return end
  C_AuctionHouse.QueryOwnedAuctions({})
end

function GC.Sell.OnOwnedAuctions()
  local auctions = C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and C_AuctionHouse.GetOwnedAuctions() or nil
  ownedLots = GC.Flips.ExtractOwnedLots(auctions)

  -- A repost's cancel step has no dedicated "cancel confirmed" event (C_AuctionHouse.CancelAuction
  -- just issues the request) -- this refresh is how the flow actually learns the lot is gone.
  -- Once the cancelled auctionID no longer shows up as this item's cheapest lot, release the pin
  -- and let the row fall back to its normal computed status (UNLISTED once the item lands back
  -- in the mail, same as any other unposted flip).
  if repostingRow and repostingRow.repostStage == "cancelling" then
    local flip = repostingRow.flip
    local stillThere = flip and GC.Flips.CheapestOwnedLot(flip.itemID, ownedLots)
    if not stillThere or stillThere.auctionID ~= repostingRow.cancelAuctionID then
      repostingRow.repostStage = nil
      repostingRow.cancelAuctionID = nil
      repostingRow = nil
      setStatus("lot cancelled -- Post again once it's back in your bags")
    end
  end

  -- Minor (fix round 1): gated HERE, not inside renderRows/GC.Sell.Refresh -- SniperFrame.lua's
  -- own GC.Sniper.Toggle() calls GC.Sell.Refresh() unconditionally on every show to keep the
  -- Sell tab's badge count current even while the Deals view is active, and that path must keep
  -- working regardless of container visibility. This handler's OWN render, though, is purely a
  -- reaction to fresh owned-lots data -- pointless (and a wasted pass over every flip) while the
  -- Sell tab isn't even on screen to show it.
  if container and container:IsShown() then GC.Sell.Refresh() end
end

-- Best-effort synchronous name lookup, same call RecordSniperBuy already leans on
-- (Core/Ledger.lua) -- works instantly whenever the client already has the item cached (true
-- for nearly every item that's ever had its icon/tooltip drawn this session), so
-- GC.Flips.SalesForItem matching doesn't have to wait on the row's own async icon/name load
-- most of the time.
local function resolveItemName(itemID)
  local cached = itemNames[itemID]
  if cached then return cached end
  if C_Item and C_Item.GetItemNameByID then
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if ok and type(name) == "string" and name ~= "" then
      itemNames[itemID] = name
      return name
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Quoting ("Refresh prices"). Sequential, one query in flight at a time, exactly like
-- Core/Scanner.lua's own advance() loop -- but gated additionally on GC.Sniper.IsBusy() so this
-- can never compete with a Full Scan or an in-flight buy requery on the shared throttled
-- message system (see SniperFrame.lua's GC.Sniper.IsBusy and OnThrottleReady comments).
-- ---------------------------------------------------------------------------

local function advanceQuote()
  if not quoting or pendingQuote or awaitingKeyInfo then return end

  if quoteIndex >= #quoteQueue then
    quoting = false
    setStatus(("refreshed %d price%s"):format(#quoteQueue, #quoteQueue == 1 and "" or "s"))
    return
  end

  if GC.Sniper.IsBusy() then
    setStatus("waiting -- a scan or purchase is in progress")
    return
  end

  if not driver.isReady() then
    setStatus("waiting for server...")
    return -- next AUCTION_HOUSE_THROTTLED_SYSTEM_READY tick (GC.Sell.OnThrottleReady) retries
  end

  quoteIndex = quoteIndex + 1
  local itemID = quoteQueue[quoteIndex]

  -- Guard against the item key not being cached yet, same pattern as SniperFrame.lua's
  -- startRequery/GC.Sniper.OnItemKeyInfo.
  if driver.getKeyInfo(itemID) then
    pendingQuote = itemID
    pendingQuoteSince = time()
    driver.sendSearch(itemID)
  else
    awaitingKeyInfo = itemID
  end
end

local function onRefreshPricesClick()
  if quoting then
    setStatus("already refreshing prices...")
    return
  end
  local ids = uniqueFlipItemIDs()
  if #ids == 0 then
    setStatus("no flips to quote")
    return
  end
  quoteQueue = ids
  quoteIndex = 0
  quoting = true
  setStatus(("refreshing %d price%s..."):format(#ids, #ids == 1 and "" or "s"))
  advanceQuote()
end

-- Task 9 Step 1's OTHER ghost Refresh button -- owned lots only, never quotes. Distinct from
-- "Refresh prices" above: QueryOwnedAuctions is a separate, cheap, on-demand call (fires on
-- tab show too), not part of the sequential quote walk.
local function onRefreshLotsClick()
  requestOwnedAuctions()
  setStatus("refreshing your auctions...")
end

function GC.Sell.OnThrottleReady()
  -- Recovers a stale pending search, same idiom as Core/Scanner.lua's OnSystemReady -- the
  -- matching ITEM_SEARCH_RESULTS_UPDATED/COMMODITY_SEARCH_RESULTS_UPDATED event is not
  -- guaranteed to have arrived by the next throttle-ready tick under load.
  if pendingQuote and (time() - pendingQuoteSince) > QUOTE_STALE_SECONDS then
    pendingQuote = nil
  end
  advanceQuote()
end

function GC.Sell.OnItemKeyInfo(itemID)
  if awaitingKeyInfo ~= itemID then return end -- not something this module is waiting on
  awaitingKeyInfo = nil
  advanceQuote()
end

function GC.Sell.OnItemSearchResults(itemID)
  if itemID ~= pendingQuote then return end -- e.g. the watchlist scanner's or the buy-requery's own search; not ours
  pendingQuote = nil
  local price = driver.itemResult(itemID)
  if price then quotes[itemID] = price end
  GC.Sell.Refresh()
  advanceQuote()
end

function GC.Sell.OnCommoditySearchResults(itemID)
  if itemID ~= pendingQuote then return end
  pendingQuote = nil
  local price = driver.commodityResult(itemID)
  if price then quotes[itemID] = price end
  GC.Sell.Refresh()
  advanceQuote()
end

-- ---------------------------------------------------------------------------
-- Posting. COMPLIANCE: C_AuctionHouse.PostItem/PostCommodity/ConfirmPostItem/
-- ConfirmPostCommodity are called ONLY from onPostClick below, itself only ever reached from
-- the action button's own OnClick -- a real hardware click, same discipline as every purchase
-- call in SniperFrame.lua. Verified 12.x signatures (warcraft.wiki.gg):
--   needsConfirmation = C_AuctionHouse.PostItem(itemLocation, duration, quantity, bid, buyout)
--   needsConfirmation = C_AuctionHouse.PostCommodity(itemLocation, duration, quantity, unitPrice)
-- needsConfirmation mirrors Blizzard's OWN Blizzard_AuctionHouseUI (AuctionHouseItemSellFrameMixin/
-- AuctionHouseCommoditiesSellFrameMixin:StartPost+ConfirmPost, Gethe/wow-ui-source): when true,
-- the addon must NOT call Post* again -- the confirming click instead replays the exact same
-- args into ConfirmPostItem(itemLocation, duration, quantity, bid, buyout) /
-- ConfirmPostCommodity(itemLocation, duration, quantity, unitPrice). AUCTION_HOUSE_AUCTION_CREATED
-- and AUCTION_HOUSE_POST_ERROR are the same two events Blizzard's own UI reacts to for
-- success/failure (ShowPostConfirmationDialog); neither carries an addon-usable per-post
-- identity, hence the single postingRow slot instead of trying to match on event payload.
-- ---------------------------------------------------------------------------

local function schedulePostTimeout(row)
  local flip = row.flip
  C_Timer.After(POST_TIMEOUT_SECONDS, function()
    if postingRow == row and row.flip == flip and (row.postStage == "posting" or row.postStage == "confirming") then
      -- Unverified whether AUCTION_HOUSE_AUCTION_CREATED/AUCTION_HOUSE_POST_ERROR always fire
      -- (same caution as SniperFrame.lua's scheduleBuyTimeout) -- freeze instead of silently
      -- resetting, since the post may in fact have already gone through server-side.
      setStatus("no post confirmation received -- check your auctions, then Refresh prices")
    end
  end)
end

local function onPostClick(row)
  local flip = row.flip
  if not flip then return end

  if row.postStage == "confirm" then
    -- Second click of a needsConfirmation post: replay the SAME args into ConfirmPostItem/
    -- ConfirmPostCommodity (see the compliance block above).
    local pending = row.pendingPost
    if not pending then return end
    row.postStage = "confirming"
    row.actionBtn:Disable()
    setStatus("confirming posting...")
    if pending.isCommodity then
      C_AuctionHouse.ConfirmPostCommodity(pending.location, pending.duration, pending.qty, pending.unitPrice)
    else
      C_AuctionHouse.ConfirmPostItem(pending.location, pending.duration, pending.qty, pending.bid, pending.buyout)
    end
    schedulePostTimeout(row)
    return
  end

  if postingRow and postingRow ~= row then
    setStatus("finish the pending post first")
    return
  end

  local inBags = countInBags(flip.itemID)
  if inBags <= 0 then
    setStatus("not in bags yet -- check your mailbox")
    return
  end

  local keyInfo = driver.getKeyInfo(flip.itemID)
  if not keyInfo then
    setStatus("click Refresh prices first, then Post")
    return
  end

  local bag, slot = findBagSlot(flip.itemID)
  if not bag then
    setStatus("not in bags yet -- check your mailbox")
    return
  end

  local quote = quotes[flip.itemID]
  local recommended = quote and math.max(1, quote - 1) or flip.targetUnit
  -- The AH only accepts whole-silver prices (no copper digit) -- non-zero copper silently
  -- fails the post (verified via warcraft.wiki.gg) -- so round DOWN before the actual API
  -- call, floored at 1 silver.
  local postUnit = math.max(100, math.floor(recommended / 100) * 100)
  local qty = math.min(inBags, flip.qty)
  local location = ItemLocation:CreateFromBagAndSlot(bag, slot)

  postingRow = row
  row.postStage = "posting"
  row.actionBtn:Disable()
  setStatus("posting...")

  local needsConfirmation
  if keyInfo.isCommodity then
    needsConfirmation = C_AuctionHouse.PostCommodity(location, POST_DURATION, qty, postUnit)
    row.pendingPost = { isCommodity = true, location = location, duration = POST_DURATION, qty = qty, unitPrice = postUnit }
  else
    local buyoutTotal = postUnit * qty
    needsConfirmation = C_AuctionHouse.PostItem(location, POST_DURATION, qty, nil, buyoutTotal)
    row.pendingPost = { isCommodity = false, location = location, duration = POST_DURATION, qty = qty, bid = nil, buyout = buyoutTotal }
  end

  if needsConfirmation then
    row.postStage = "confirm"
    row.actionBtn:Enable()
    row.actionBtn:SetLabel("Confirm")
    setStatus("posting below usual price -- click Post again to confirm")
  else
    schedulePostTimeout(row)
  end
end

function GC.Sell.OnAuctionCreated()
  local row = postingRow
  if not row then return end -- not something we posted (e.g. the player posted manually via Blizzard's own AH window)
  postingRow = nil
  local index = row.flip and currentIndexOf(row.flip)
  if index then GC.Data.MarkFlipPosted(index) end
  setStatus("posted")
  GC.Sell.Refresh()
end

function GC.Sell.OnPostError()
  local row = postingRow
  if not row then return end
  postingRow = nil
  row.postStage = nil
  row.pendingPost = nil
  row.actionBtn:Enable()
  row.actionBtn:SetLabel("Post")
  setStatus("posting failed -- check the item and try again")
  GC.Sell.Refresh()
end

-- ---------------------------------------------------------------------------
-- Repost (Task 9 Step 3): UNDERCUT rows only. Two explicit clicks -- never one, because
-- deposits are real money. First click ARMS: the action button hides, a danger-variant
-- "Cancel lot?" button takes its place, disabled for REPOST_ARM_SECONDS (mirrors
-- SniperFrame.lua's armLoudConfirm -- a click already on its way when the button morphs can't
-- land on it), and the status line shows the deposit estimate. Second click (on the now-enabled
-- danger button) actually cancels; the row then flows into the ordinary Post path once
-- GC.Sell.OnOwnedAuctions confirms the lot is gone and the item lands back in the mail --
-- nothing repost-specific happens after the cancel, by design (see that handler above).
-- ---------------------------------------------------------------------------

-- CalculateCommodityDeposit(itemID, duration, quantity) needs no ItemLocation -- unlike
-- PostCommodity, which needs the physical stack in hand, the commodity deposit is priced off
-- the fungible itemID alone (verified against warcraft.wiki.gg). That's exactly why a deposit
-- preview is possible HERE, before the old lot is even cancelled and the item is still sitting
-- in an active auction, nowhere near the player's bags. CalculateItemDeposit, by contrast,
-- takes an ItemLocation -- unavailable for the same reason (the item isn't in bags yet) -- so a
-- single-item (non-commodity) repost shows no deposit estimate rather than a guessed one.
local function estimateDeposit(itemID, qty)
  if not (C_AuctionHouse and C_AuctionHouse.CalculateCommodityDeposit) then return nil end
  local keyInfo = driver.getKeyInfo(itemID)
  if not keyInfo or not keyInfo.isCommodity then return nil end
  local ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, POST_DURATION, qty)
  if ok and type(deposit) == "number" then return deposit end
  return nil
end

local function showRepostButtons(row, armed)
  if armed then
    row.actionBtn:Hide()
    row.cancelBtn:Show()
  else
    row.cancelBtn:Hide()
    row.actionBtn:Show()
  end
end

-- fix round 1 (I1): the shared escape hatch every repost exit path (auto-disarm, stale-id
-- abort, the cancel timeout) now funnels through -- releases the pin, clears the row's repost
-- fields, restores the action button, and re-renders from whatever data is CURRENTLY live
-- (never leaves the row frozen showing a stale "Cancelling..."/"Cancel lot?" state).
local function disarmRepost(row, statusText)
  if repostingRow == row then repostingRow = nil end
  row.repostStage = nil
  row.cancelAuctionID = nil
  if statusText then setStatus(statusText) end
  GC.Sell.Refresh()
end

local function onRepostClick(row)
  local flip = row.flip
  if not flip then return end

  if repostingRow and repostingRow ~= row then
    setStatus("finish the pending repost first")
    return
  end

  local lot = GC.Flips.CheapestOwnedLot(flip.itemID, ownedLots)
  if not lot then
    setStatus("no active lot found for this item -- click Refresh")
    return
  end

  repostingRow = row
  row.repostStage = "armed"
  row.cancelAuctionID = lot.auctionID

  repostArmToken = repostArmToken + 1
  local token = repostArmToken

  showRepostButtons(row, true)
  row.cancelBtn:Disable()
  row.cancelBtn:SetLabel("Cancel lot?")

  -- Minor (fix round 1): names the forfeited-deposit fact explicitly instead of only showing
  -- the NEW deposit -- cancelling always burns the deposit already paid on the existing lot,
  -- independent of whether a new deposit figure is even known. "unknown" (not silence) for a
  -- non-commodity, since estimateDeposit's nil is ambiguous between "not a commodity" and "the
  -- API call failed" -- either way the player should not read a blank as "free."
  local keyInfo = driver.getKeyInfo(flip.itemID)
  local deposit = estimateDeposit(flip.itemID, flip.qty)
  local newDepositText
  if deposit then
    newDepositText = "~" .. formatAmount(deposit)
  elseif keyInfo and not keyInfo.isCommodity then
    newDepositText = "unknown (non-commodity)"
  else
    newDepositText = "unknown"
  end
  setStatus(("cancel your %s lot? existing deposit is lost; new deposit %s -- click Cancel lot? again to confirm")
    :format(formatAmount(lot.unitPrice), newDepositText))

  C_Timer.After(REPOST_ARM_SECONDS, function()
    if token ~= repostArmToken then return end
    if repostingRow ~= row or row.repostStage ~= "armed" then return end
    row.cancelBtn:Enable()
  end)

  -- I1: auto-disarm -- an armed-but-never-confirmed repost must not sit showing "Cancel lot?"
  -- indefinitely (e.g. the player clicked Repost, got distracted, and never came back).
  C_Timer.After(REPOST_DISARM_SECONDS, function()
    if token ~= repostArmToken then return end
    if repostingRow ~= row or row.repostStage ~= "armed" then return end
    disarmRepost(row, "repost window expired -- press Repost again")
  end)
end

local function onCancelConfirmClick(row)
  if row.repostStage ~= "armed" or not row.cancelBtn:IsEnabled() then return end
  local flip = row.flip
  if not flip then return end

  -- I2: re-resolve the cheapest lot right before firing -- ownedLots may have changed since
  -- this row armed (a manual cancel via Blizzard's own AH window, a fresh owned-lots refresh
  -- landing, the lot selling out from under the player). A stale auctionID must never reach
  -- CancelAuction -- that could cancel the WRONG lot if the player has since re-posted at a
  -- different auctionID for the same item.
  local current = GC.Flips.CheapestOwnedLot(flip.itemID, ownedLots)
  if not current or current.auctionID ~= row.cancelAuctionID then
    disarmRepost(row, "lot changed -- press Repost again")
    return
  end

  row.repostStage = "cancelling"
  row.cancelBtn:Disable()
  row.cancelBtn:SetLabel("Cancelling...")
  setStatus("cancelling lot...")

  if C_AuctionHouse and C_AuctionHouse.CancelAuction then
    C_AuctionHouse.CancelAuction(row.cancelAuctionID)
  end
  -- Minor (fix round 1): deterministic post-cancel refresh -- don't wait solely on whatever
  -- OWNED_AUCTIONS_UPDATED/AUCTION_CANCELED timing the client happens to deliver; ask again
  -- right away too (requestOwnedAuctions itself no-ops safely if the AH session is somehow
  -- already gone, per I4).
  requestOwnedAuctions()

  -- I1: this fallback used to just print a status message and freeze -- it now RELEASES the
  -- pin and re-renders from whatever's currently live, via the same disarmRepost every other
  -- exit path uses, instead of leaving the row stuck on "Cancelling..." forever if
  -- OWNED_AUCTIONS_UPDATED/AUCTION_CANCELED never arrives. The cancel may still have gone
  -- through server-side even if this fires -- the status line says so, it doesn't claim failure.
  C_Timer.After(POST_TIMEOUT_SECONDS, function()
    if repostingRow == row and row.repostStage == "cancelling" then
      disarmRepost(row, "no confirmation of the cancel yet -- check your auctions, then Refresh")
    end
  end)
end

local function onActionClick(row)
  if row.status == "UNDERCUT" then
    onRepostClick(row)
  else
    onPostClick(row)
  end
end

-- Restored per review: dropping this in the Task 9 rebuild was a scope error -- the brief's
-- column list never said to remove it, and absent an explicit instruction, existing
-- functionality has to survive a rebuild (a player who decides NOT to sell something needs a
-- way to drop it from the queue without waiting out FLIP_MAX_AGE_SECONDS). Same handler as the
-- pre-Task-9 file (git show HEAD~1:addon/GoldCap/UI/SellFrame.lua's onRemoveClick):
-- GC.Data.RemoveFlip(currentIndexOf(flip)). Non-destructive to gold -- the ledger already has
-- the buy record independent of db.flips -- so no confirm step, unlike Repost's cancel (which
-- burns a real deposit). The in-flight guard now also covers repostingRow, the second pin this
-- task added.
local function onRemoveClick(row)
  local flip = row.flip
  if not flip then return end
  if row == postingRow or row == repostingRow then
    setStatus("finish the pending action first")
    return
  end
  local index = currentIndexOf(flip)
  if index then GC.Data.RemoveFlip(index) end
  GC.Sell.Refresh()
end

-- ---------------------------------------------------------------------------
-- Task 9 columns: item(flex) | bought | listed | market | profit | status chip | action | remove.
-- Same COLUMNS-table + anchor-chain idiom as UI/SniperFrame.lua's T5 Deals grid (buildRowCell/
-- anchorColumns there). `remove` is LAST in this array on purpose -- anchorColumns walks
-- COLUMNS back-to-front, so the last fixed entry lands flush against the row's own right edge,
-- i.e. visually furthest right.
--
-- fix round 1 (I8): bought/listed/market shrank 76->64px each, and `optional = true` (bought,
-- then market) now ports SniperFrame.lua's OWN computeHidden responsive-drop mechanism -- the
-- grid genuinely didn't fit before this (item-name zone was well under 150px at the DEFAULT
-- 640 window width, not just at the resize floor). Both are individually recoverable without
-- losing information: `bought` still drives the ledger/profit math and shows in the row
-- tooltip when hidden (see createRow's OnEnter below); `market` is one Refresh-prices click
-- away from being re-quoted, also shown in the tooltip when hidden.
--
-- Unlike Sniper's Deals grid this is still a ONE-TIME computation (see GC.Sell.Attach), not a
-- live OnSizeChanged re-flow -- Sell's rowWidth remains a snapshot taken once at Attach time
-- (unchanged design from before this task); computeHidden below just makes that one-time
-- snapshot degrade gracefully across whatever width it happens to capture, instead of a single
-- fixed layout that only worked at some widths and not others.
-- ---------------------------------------------------------------------------
local COLUMNS = {
  { key = "item",   flex = true, min = 150 },
  { key = "bought", w = 64, num = true, size = 12, optional = true },
  { key = "listed", w = 64, num = true, size = 12 },
  { key = "market", w = 64, num = true, size = 12, optional = true },
  { key = "profit", w = 84, num = true, size = 13, bold = true },
  { key = "status", w = 88 },
  { key = "action", w = 64 },
  { key = "remove", w = 20 },
}

local NUM_FIELD = { bought = "boughtText", listed = "listedText", market = "marketText", profit = "profitText" }

local STATUS_STYLE = {
  UNLISTED     = { label = "UNLISTED",     color = "gold" },
  LISTED       = { label = "LISTED",       color = "fgDim" },
  UNDERCUT     = { label = "UNDERCUT",     color = "red" },
  SOLD_PENDING = { label = "SOLD-PENDING", color = "green" },
}

-- Anchors every VISIBLE fixed COLUMNS entry's RIGHT edge right-to-left off `container`'s own
-- RIGHT edge (mirrors SniperFrame.lua's anchorColumns exactly, including the hidden-set this
-- time -- I8 ported it in). Any entry present in `hidden` (a set of COLUMNS.key -> true) is
-- Hidden and skipped from the chain entirely. Returns the flex ("item") column's anchor pair --
-- {frame, point} -- for the caller to anchor the item content's RIGHT edge to.
local function anchorColumns(rowContainer, hidden, cellFor)
  local prev, prevPoint = rowContainer, "RIGHT"
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

-- fix round 1 (I8): ported from SniperFrame.lua's own OPTIONAL_KEYS/DROP_THRESHOLDS/
-- fixedColumnBudget/computeHidden (same data-driven-off-COLUMNS approach, same drop-priority-is-
-- table-order rule) -- see that file's own comments for the full reasoning. Computed ONCE here
-- (GC.Sell.Attach, before any row exists), not on a live resize -- Sell's rowWidth is a
-- snapshot, unchanged from before this task.
local OPTIONAL_KEYS, DROP_THRESHOLDS = {}, { 150, 120 }
for _, col in ipairs(COLUMNS) do
  if col.optional then OPTIONAL_KEYS[#OPTIONAL_KEYS + 1] = col.key end
end

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

-- Set once by GC.Sell.Attach (computeHidden(ROW_WIDTH)) before the header/any row is built;
-- read by layoutRow/header-building below. Module-local rather than a parameter threaded
-- through createRow/buildRowCell, same as SniperFrame.lua's own hiddenColumns.
local hiddenColumns = {}

local function buildRowCell(row, col)
  if col.key == "status" then
    local chip = Theme.Chip(row)
    row.statusChip = chip
    return chip
  elseif col.key == "action" then
    local cell = CreateFrame("Frame", nil, row)
    cell:SetHeight(20)

    local actionBtn = Theme.Button(cell, "primary")
    actionBtn:SetAllPoints()
    actionBtn:SetScript("OnClick", function() onActionClick(row) end)
    row.actionBtn = actionBtn

    local cancelBtn = Theme.Button(cell, "danger")
    cancelBtn:SetAllPoints()
    cancelBtn:SetScript("OnClick", function() onCancelConfirmClick(row) end)
    cancelBtn:Hide()
    row.cancelBtn = cancelBtn

    row.actionCell = cell
    return cell
  elseif col.key == "remove" then
    -- Task 9 restore: small ghost "x" dismiss button, independent of flip status (unlike
    -- action/status, which are UNLISTED/UNDERCUT/etc.-driven) -- a player can drop a flip from
    -- any state. HookScript, not SetScript, for OnEnter/OnLeave -- Theme.Button already installs
    -- its own OnEnter/OnLeave for the hover-brighten effect (Theme.lua), and SetScript would
    -- silently replace that handler instead of adding a tooltip alongside it (same I4 rule
    -- SniperFrame.lua's setPlainTooltip follows).
    local btn = Theme.Button(row, "ghost")
    btn:SetHeight(16)
    btn:SetLabel("×")
    btn:SetScript("OnClick", function() onRemoveClick(row) end)
    btn:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Remove from flips", 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    row.removeBtn = btn
    return btn
  else
    local fs = Theme.Num(row, col.size, col.bold)
    fs:SetWordWrap(false)
    fs:SetMaxLines(1)
    row[NUM_FIELD[col.key]] = fs
    return fs
  end
end

local function layoutRow(row)
  local flexAnchor = anchorColumns(row, hiddenColumns, function(col) return row.cells[col.key] end)
  row.nameText:ClearAllPoints()
  row.nameText:SetPoint("LEFT", row.icon, "RIGHT", Theme.pad.xs, 0)
  row.nameText:SetPoint("RIGHT", flexAnchor.frame, flexAnchor.point, -Theme.pad.s, 0)
end

-- ---------------------------------------------------------------------------
-- Stamps every widget in `row` from a (possibly reused) flip + its pre-computed flipRow
-- (GC.Flips.BuildRow's own return shape) -- mirrors SniperFrame.lua's setRowDeal, including the
-- async icon/name load's identity guard (`row.flip ~= flip`, same reason as setRowDeal's
-- `row.deal ~= deal`).
-- ---------------------------------------------------------------------------
local function setRowFlip(row, flip, flipRow)
  row.flip = flip
  row.flipRow = flipRow -- I8: kept for the row tooltip to show any column hidden by the responsive drop
  row.status = flipRow.status
  row.postStage = nil
  row.pendingPost = nil
  row.repostStage = nil
  row.cancelAuctionID = nil

  setColor(row.boughtText, Theme.color.fg)
  row.boughtText:SetText(formatAmount(flipRow.boughtUnit))

  if flipRow.listedUnit then
    setColor(row.listedText, Theme.color.fg)
    row.listedText:SetText(formatAmount(flipRow.listedUnit))
  else
    setColor(row.listedText, Theme.color.fgDim)
    row.listedText:SetText(DASH)
  end

  if flipRow.marketUnit then
    setColor(row.marketText, Theme.color.fg)
    row.marketText:SetText(formatAmount(flipRow.marketUnit))
  else
    setColor(row.marketText, Theme.color.fgDim)
    row.marketText:SetText(DASH)
  end

  row.profitText:SetText(formatProfitText(flipRow.profit))
  if flipRow.profit == nil then
    setColor(row.profitText, Theme.color.fgDim)
  elseif flipRow.profit < 0 then
    setColor(row.profitText, Theme.color.red)
  else
    setColor(row.profitText, Theme.color.green)
  end

  local style = STATUS_STYLE[flipRow.status] or STATUS_STYLE.UNLISTED
  row.statusChip:SetLabel(style.label, Theme.color[style.color])

  -- fix round 1 (I5): LISTED/SOLD_PENDING used to hide the action button entirely -- wrong for
  -- the common multi-flip-same-item pattern (buy the same item across several Sniper purchases,
  -- so several flip rows share one itemID). Posting flip #1 (marking IT posted, pruning IT from
  -- db.flips -- see Core/Data.lua's GetFlips) does NOT mean flips #2/#3's own bought stock is
  -- posted too; they can easily still have bag stock waiting. A Post button gated purely on
  -- "is this item's OWN status not already spoken for" would strand that stock behind a hidden
  -- button until the FIRST lot resolves. So: Post is available whenever there's bag stock,
  -- regardless of the row's own listed/pending status -- only UNDERCUT changes the button to
  -- Repost, since that's the one state where posting more stock isn't the right first move.
  row.actionCell:Show()
  row.cancelBtn:Hide()
  row.actionBtn:Show()
  if flipRow.status == "UNDERCUT" then
    row.actionBtn:SetLabel("Repost")
    row.actionBtn:Enable()
  else
    row.actionBtn:SetLabel("Post")
    if countInBags(flip.itemID) > 0 then row.actionBtn:Enable() else row.actionBtn:Disable() end
  end

  row.nameText:SetText(("item %d"):format(flip.itemID))
  row.icon:SetTexture(nil)
  local item = Item:CreateFromItemID(flip.itemID)
  item:ContinueOnItemLoad(function()
    if row.flip ~= flip then return end -- row was repurposed before the async load finished
    row.icon:SetTexture(item:GetItemIcon())
    local quality = item:GetItemQuality()
    local qc = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
    local realName = item:GetItemName()
    local label = realName or ("item " .. flip.itemID)
    row.nameText:SetText(qc and qc:WrapTextInColorCode(label) or label)
    -- Minor (fix round 1): only cache a REAL name -- the "item <id>" placeholder above is a
    -- display fallback, never a name GC.Flips.SalesForItem could match against a real ledger
    -- sale entry, so caching it would just poison itemNames with a string that can never hit.
    if realName then itemNames[flip.itemID] = realName end
  end)

  row:Show()
end

local function createRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(ROW_WIDTH, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

  local zc = Theme.color.zebra
  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetAllPoints()
  zebra:SetColorTexture(zc[1], zc[2], zc[3], (index % 2 == 1) and zc[4] or 0)

  local hc = Theme.color.hover
  local highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  highlight:SetAllPoints()
  highlight:SetColorTexture(hc[1], hc[2], hc[3], hc[4])
  highlight:Hide()
  row.highlight = highlight

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

  -- Whole-row hover: item GameTooltip + highlight, same pattern as SniperFrame.lua's deal rows.
  -- I8: when the responsive drop has hidden `bought`/`market`, their values are appended here
  -- instead of just vanishing -- nothing the grid can't fit is actually lost, only a
  -- glance-at-the-list convenience (same "stays reachable elsewhere" principle SniperFrame.lua's
  -- own optional columns follow, there via the buy dialog's price grid).
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    self.highlight:Show()
    if not self.flip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.flip.itemID)
    local fr = self.flipRow
    if fr then
      if hiddenColumns.bought then
        GameTooltip:AddLine(("Bought: %s"):format(formatAmount(fr.boughtUnit)), 1, 1, 1)
      end
      if hiddenColumns.market then
        GameTooltip:AddLine(("Market: %s"):format(fr.marketUnit and formatAmount(fr.marketUnit) or DASH), 1, 1, 1)
      end
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
    GameTooltip:Hide()
  end)

  row:Hide()
  return row
end

-- ---------------------------------------------------------------------------
-- Summary strip + pending-sync hint (Task 9 Steps 4/4b).
-- ---------------------------------------------------------------------------

local function updateSummary(allRows)
  if not container or not container.summary then return end
  local s = GC.Flips.Summary(allRows)

  setColor(container.summary.investedVal, Theme.color.fg)
  container.summary.investedVal:SetText(formatAmount(s.invested))
  setColor(container.summary.projectedVal, Theme.color.fg)
  container.summary.projectedVal:SetText(formatAmount(s.projected))

  container.summary.profitVal:SetText(formatProfitText(s.profit))
  setColor(container.summary.profitVal, s.profit < 0 and Theme.color.red or Theme.color.green)

  -- T4 review note: projected/profit only fold in rows with a known profit while invested
  -- counts every row -- when some rows have no owned lot AND no fresh quote, the three numbers
  -- would otherwise read as silently contradictory (invested > projected for no visible
  -- reason). This dim suffix makes the gap legible instead.
  local unpriced = 0
  for _, r in ipairs(allRows) do
    if r.profit == nil then unpriced = unpriced + 1 end
  end
  if unpriced > 0 then
    container.summary.profitSuffix:SetText(("· %d unpriced"):format(unpriced))
    container.summary.profitSuffix:Show()
  else
    container.summary.profitSuffix:Hide()
  end

  -- Task 9 Step 4b: WoW only flushes SavedVariables to disk on /reload or logout, so
  -- goldcap.gg's /ledger cannot see this session's buys/sales until then -- a source of
  -- recurring player confusion. GC.Ledger.SessionEventCount() is a module-local counter,
  -- incremented only on a genuinely NEW ledger append (Core/Ledger.lua's Append), so a mailbox
  -- re-scan that just updates an existing pending-sale row doesn't inflate it.
  local hintN = GC.Ledger and GC.Ledger.SessionEventCount and GC.Ledger.SessionEventCount() or 0
  if hintN > 0 then
    container.hint:SetText(("%d event%s sync to goldcap.gg on /reload or logout"):format(hintN, hintN == 1 and "" or "s"))
    container.hint:Show()
  else
    container.hint:Hide()
  end
end

-- ---------------------------------------------------------------------------
-- Composition (Task 9 Step 1): db.flips + ownedLots + quotes + ledger sales -> GC.Flips.BuildRow
-- per flip -> render. Mirrors SniperFrame.lua's refreshRows exactly for the pin/pool mechanics:
-- a row mid-Post (postingRow) or mid-Repost (repostingRow) is left untouched instead of being
-- reassigned out from under an in-flight click sequence; both pinned flips are excluded from
-- the pool the same way sortedDeals() excludes an active purchase there.
-- ---------------------------------------------------------------------------
local function renderRows()
  if not container then return end
  local flips = GC.Data.GetFlips()
  -- Minor (fix round 1): the public accessor, not a direct GC.db.ledger reach-through -- same
  -- data either way (GC.Ledger.GetEntries() is just `(db and db.ledger) or {}`), but going
  -- through the module's own API means this file doesn't need to assume GC.db and Core/Ledger.lua's
  -- private `db` upvalue are always the same table reference.
  local entries = GC.Ledger and GC.Ledger.GetEntries() or {}

  local allRows, rowByFlip = {}, {}
  for _, f in ipairs(flips) do
    local name = resolveItemName(f.itemID)
    local quote = quotes[f.itemID]
    -- I6: sales are matched by name AND narrowed to at-or-after this flip's OWN boughtAt --
    -- without the date floor, an ancient sale of a same-named item could keep a brand-new,
    -- never-yet-posted flip showing SOLD_PENDING forever (name-only matching has no other way
    -- to tell two purchases of the same item apart). See GC.Flips.SalesForItem (Core/Flips.lua).
    local sales = name and GC.Flips.SalesForItem(entries, name, f.boughtAt) or {}
    -- I7: BuildRow projects profit from listed/market ALONE -- no fallback to flip.targetUnit/mv
    -- when neither an owned lot nor a fresh quote exists yet. A freshly-bought, never-quoted,
    -- never-posted flip legitimately shows profit "—" rather than a guessed number; the amended
    -- spec (§5) blesses this as the intended behavior, not a gap to fill in here.
    local flipRow = GC.Flips.BuildRow(f, ownedLots, quote and { unit = quote } or nil, sales)
    allRows[#allRows + 1] = flipRow
    rowByFlip[f] = flipRow
  end

  updateSummary(allRows)

  local pinnedFlips = {}
  if postingRow and postingRow.flip then pinnedFlips[postingRow.flip] = true end
  if repostingRow and repostingRow.flip then pinnedFlips[repostingRow.flip] = true end

  local list = {}
  for _, f in ipairs(flips) do
    if not pinnedFlips[f] then list[#list + 1] = f end
  end

  local pinnedCount = (postingRow and 1 or 0) + (repostingRow and 1 or 0)
  local shown = #list + pinnedCount
  for i = #rows + 1, shown do
    rows[i] = createRow(content, i)
  end

  local li = 1
  for i = 1, #rows do
    local row = rows[i]
    if row ~= postingRow and row ~= repostingRow then
      local f = (li <= #list) and list[li] or nil
      if f then
        setRowFlip(row, f, rowByFlip[f])
        li = li + 1
      else
        row.flip = nil
        row:Hide()
      end
    end
  end

  content:SetHeight(math.max(shown, 1) * ROW_HEIGHT)

  -- D: keeps the Deals-view tab badge current even while Sell isn't the active view -- see
  -- SniperFrame.lua's updateSellTabLabel/GC.Sniper.UpdateSellTabLabel.
  if GC.Sniper.UpdateSellTabLabel then GC.Sniper.UpdateSellTabLabel() end
end

-- ---------------------------------------------------------------------------
-- Public entry points.
-- ---------------------------------------------------------------------------

function GC.Sell.SellableCount()
  local n = 0
  for _, flip in ipairs(GC.Data.GetFlips()) do
    if countInBags(flip.itemID) > 0 then n = n + 1 end
  end
  return n
end

function GC.Sell.Show()
  if not container then return end
  container:Show()
  requestOwnedAuctions() -- Task 9 Step 1: tab show is one of the only two triggers (the other is the ghost Refresh button) -- never the Auto loop
  renderRows()
end

function GC.Sell.Hide()
  if not container then return end
  container:Hide()
end

function GC.Sell.Refresh()
  renderRows()
end

-- Called on AH close (SniperFrame.lua's GC.Sniper.OnAuctionHouseClosed) -- neither an in-flight
-- quote walk, a post, nor a repost can safely resume once the AH session is gone. Cached
-- `quotes`/`ownedLots` are deliberately left alone (same "persist across a close/reopen" choice
-- as Full Scan results), since a slightly-stale read is still useful until the player refreshes
-- again.
function GC.Sell.Reset()
  quoting = false
  quoteQueue = {}
  quoteIndex = 0
  pendingQuote = nil
  awaitingKeyInfo = nil
  if postingRow then
    postingRow.postStage = nil
    postingRow.pendingPost = nil
    postingRow = nil
  end
  if repostingRow then
    repostingRow.repostStage = nil
    repostingRow.cancelAuctionID = nil
    repostingRow = nil
  end
end

-- Builds the Sell tab's container: a hidden frame filling the exact region `geometry` describes
-- (the same rectangle SniperFrame.lua's deals `scroll` occupies) -- its own two ghost Refresh
-- buttons, summary strip, pending-sync hint, static column headers, and pooled-row scroll frame.
-- geometry.rowWidth/rowHeight are SniperFrame.lua's own ROW_WIDTH/ROW_HEIGHT passed through so
-- the two views' row grids can never drift out of alignment with each other. Unchanged from
-- before this task: GC.Sell.Attach only runs once, so (like before) the Sell tab's own column
-- grid does not re-flow on a window resize; only the Deals grid does.
function GC.Sell.Attach(f, geometry)
  ROW_WIDTH = geometry.rowWidth
  ROW_HEIGHT = geometry.rowHeight
  statusOwner = f

  -- I8: computed ONCE, before the header or any row exists, from whatever width Attach happens
  -- to capture (see the COLUMNS comment above for why this stays a one-time snapshot, not a
  -- live OnSizeChanged re-flow). Every buildRowCell/header cell below reads this same table.
  hiddenColumns = computeHidden(ROW_WIDTH)

  container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", geometry.panelLeft, geometry.top)
  container:SetPoint("BOTTOMRIGHT", -geometry.panelRightInset, geometry.bottom)
  container:Hide()

  -- Toolbar: two independent ghost buttons -- "Refresh prices" (the pre-existing quote walker)
  -- and "Refresh" (Task 9's new owned-lots query, Step 1). Distinct actions, distinct buttons,
  -- so neither one's status text gets mistaken for the other's.
  local TOOLBAR_H = 22
  local REFRESH_PRICES_W = 96
  local REFRESH_LOTS_W = 64

  local refreshPricesBtn = Theme.Button(container, "ghost")
  refreshPricesBtn:SetSize(REFRESH_PRICES_W, TOOLBAR_H - 2)
  refreshPricesBtn:SetPoint("TOPRIGHT", 0, 0)
  refreshPricesBtn:SetLabel("Refresh prices")
  refreshPricesBtn:SetScript("OnClick", onRefreshPricesClick)
  container.refreshPricesBtn = refreshPricesBtn

  -- Minor (fix round 1): offset derived from refreshPricesBtn's own width + one Theme.pad.s gap
  -- (the same "one gap in front of each fixed element" idiom anchorColumns uses), instead of a
  -- bare magic number that would silently go stale the moment either button's width changed.
  local refreshLotsBtn = Theme.Button(container, "ghost")
  refreshLotsBtn:SetSize(REFRESH_LOTS_W, TOOLBAR_H - 2)
  refreshLotsBtn:SetPoint("TOPRIGHT", -(REFRESH_PRICES_W + Theme.pad.s), 0)
  refreshLotsBtn:SetLabel("Refresh")
  refreshLotsBtn:SetScript("OnClick", onRefreshLotsClick)
  container.refreshLotsBtn = refreshLotsBtn

  -- Summary strip (Step 4): invested / projected / profit, Theme.Num 15 bold. Minor (fix round
  -- 1): x offsets derived from STAT_W (looped) instead of hardcoded 0/150/300; SUMMARY_ROW_H
  -- documents where the wrap's own fixed 30px height comes from (a 10pt caption + 15pt value,
  -- stacked, plus a couple px of breathing room) instead of leaving it as a bare number.
  local SUMMARY_TOP = -(TOOLBAR_H + Theme.pad.s)
  local STAT_W = 150
  local SUMMARY_ROW_H = 30
  local function addStat(index, caption)
    local wrap = CreateFrame("Frame", nil, container)
    wrap:SetPoint("TOPLEFT", (index - 1) * STAT_W, SUMMARY_TOP)
    wrap:SetSize(STAT_W, SUMMARY_ROW_H)

    local label = Theme.Label(wrap, 10)
    label:SetPoint("TOPLEFT")
    setColor(label, Theme.color.fgDim)
    label:SetText(caption)

    local value = Theme.Num(wrap, 15, true)
    value:ClearAllPoints()
    value:SetJustifyH("LEFT")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    return value
  end

  container.summary = {}
  container.summary.investedVal = addStat(1, "INVESTED")
  container.summary.projectedVal = addStat(2, "PROJECTED")
  container.summary.profitVal = addStat(3, "PROFIT")

  local profitSuffix = Theme.Label(container, 10)
  setColor(profitSuffix, Theme.color.fgDim)
  profitSuffix:SetPoint("LEFT", container.summary.profitVal, "RIGHT", Theme.pad.xs, 0)
  profitSuffix:Hide()
  container.summary.profitSuffix = profitSuffix

  -- Pending-sync hint (Step 4b): dim, only shown once N > 0 this session -- reserved a fixed
  -- row of its own so toggling it never shifts the header/rows below. Minor (fix round 1):
  -- derived from SUMMARY_ROW_H + Theme.pad.xs (the summary wrap's own height plus a small gap)
  -- instead of the bare "-34" it replaced.
  local HINT_TOP = SUMMARY_TOP - SUMMARY_ROW_H - Theme.pad.xs
  local hint = Theme.Label(container, 10)
  hint:SetPoint("TOPLEFT", 0, HINT_TOP)
  setColor(hint, Theme.color.fgDim)
  hint:Hide()
  container.hint = hint

  -- Static column header labels (no sort, no per-header tooltip -- unlike the Deals headers,
  -- Sell's columns are numeric and small enough to read directly).
  local HEADER_TOP = HINT_TOP - 16
  local HEADER_H = 16
  local header = CreateFrame("Frame", nil, container)
  header:SetPoint("TOPLEFT", 0, HEADER_TOP)
  header:SetPoint("TOPRIGHT", 0, HEADER_TOP)
  header:SetHeight(HEADER_H)

  local HEADER_TEXT = { item = "Item", bought = "Bought", listed = "Listed", market = "Market", profit = "Profit", status = "Status", action = "", remove = "" }
  header.cells = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then
      local label = Theme.Label(header, 11)
      label:SetJustifyH(col.num and "RIGHT" or "LEFT")
      label:SetText((HEADER_TEXT[col.key] or ""):upper())
      header.cells[col.key] = label
    end
  end
  local itemFlexAnchor = anchorColumns(header, hiddenColumns, function(col) return header.cells[col.key] end)
  local itemHeader = Theme.Label(header, 11)
  itemHeader:SetPoint("LEFT")
  itemHeader:SetPoint("RIGHT", itemFlexAnchor.frame, itemFlexAnchor.point, -Theme.pad.s, 0)
  itemHeader:SetText("ITEM")

  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, HEADER_TOP - HEADER_H - Theme.pad.xs)
  scroll:SetPoint("BOTTOMRIGHT", 0, 0)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    local target = self:GetVerticalScroll() - delta * ROW_HEIGHT * 3
    if target < 0 then target = 0 end
    if target > range then target = range end
    self:SetVerticalScroll(target)
  end)

  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(ROW_WIDTH, ROW_HEIGHT)
  scroll:SetScrollChild(content)
end
