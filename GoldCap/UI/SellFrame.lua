local _, GC = ...

GC.Sell = GC.Sell or {}

-- ---------------------------------------------------------------------------
-- Sniper v2 §D: the Sell view. Lists every recorded flip (GC.Data.GetFlips -- one entry per
-- successful sniper purchase), splits what's already in bags from what's still in the mail
-- (AH purchases always arrive by mail; this addon cannot touch mail), quotes the current
-- lowest AH price on demand ("Refresh prices"), and posts with one click once the item is in
-- bags. GC.Sell.Attach(f, geometry) is called once from SniperFrame.lua's createFrame; every
-- other entry point here (Show/Hide/Refresh/Reset/the throttle+search-result routers) is
-- driven by SniperFrame.lua's tab switcher or Core/Init.lua's event dispatch.
-- ---------------------------------------------------------------------------

local ROW_HEIGHT   -- from geometry (GC.Sell.Attach)
local ROW_WIDTH    -- from geometry (GC.Sell.Attach)

local ICON_SIZE = 16
local NAME_GAP = 4
local COL_GAP = 6
local BTN_GAP = 4
local REMOVE_WIDTH = 18
local POST_WIDTH = 50
local REC_WIDTH = 64
local LOWEST_WIDTH = 64
local PAID_WIDTH = 64
local BAGS_WIDTH = 80
local HEADER_HEIGHT = 14
local HEADER_TOP_ROW = 22 -- Refresh prices button row, reserved above the column headers
local HEADER_GAP = 4

local POST_DURATION = 2 -- 24h; C_AuctionHouse.PostItem/PostCommodity duration enum: 1=12h, 2=24h, 3=48h (verified against warcraft.wiki.gg)
local POST_TIMEOUT_SECONDS = 8
local QUOTE_STALE_SECONDS = 10 -- mirrors Core/Scanner.lua's own STALE_SECONDS for a pending search that never got an answer

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

-- Posting state: only ONE post may be in flight addon-wide (mirrors SniperFrame's single
-- in-flight commodityPurchase slot) -- AUCTION_HOUSE_AUCTION_CREATED/AUCTION_HOUSE_POST_ERROR
-- carry no per-post identity, so a single pinned row is the only way to attribute either event
-- to the right flip.
local postingRow = nil

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

local function setStatus(text)
  if statusOwner and statusOwner.status then statusOwner.status:SetText(text) end
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
-- rows by the flip's own table identity (see postingRow above and row.flip below), which stays
-- valid across renders even as other entries get posted/removed/pruned around it.
local function currentIndexOf(flip)
  local flips = GC.Data.GetFlips()
  for i, f in ipairs(flips) do
    if f == flip then return i end
  end
  return nil
end

local createRow  -- forward-declared; real definition below needs the click handlers first
local setRowFlip -- forward-declared; real definition below, mirrors SniperFrame.lua's setRowDeal

-- D: mirrors SniperFrame.lua's refreshRows exactly -- the pinned (mid-post) row's widget
-- content is left untouched instead of being reassigned out from under a pending Post/Confirm
-- click; sortedDeals()'s activeItemID exclusion there is this module's `f ~= postingRow.flip`
-- filter here.
local function renderRows()
  if not container then return end
  local flips = GC.Data.GetFlips()
  local pinnedFlip = postingRow and postingRow.flip

  local list = {}
  for _, f in ipairs(flips) do
    if f ~= pinnedFlip then list[#list + 1] = f end
  end

  local shown = #list + (pinnedFlip and 1 or 0)
  for i = #rows + 1, shown do
    rows[i] = createRow(content, i)
  end

  local li = 1
  for i = 1, #rows do
    local row = rows[i]
    if row ~= postingRow then
      local f = (li <= #list) and list[li] or nil
      if f then
        setRowFlip(row, f)
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

local function onRefreshClick()
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
  renderRows()
  advanceQuote()
end

function GC.Sell.OnCommoditySearchResults(itemID)
  if itemID ~= pendingQuote then return end
  pendingQuote = nil
  local price = driver.commodityResult(itemID)
  if price then quotes[itemID] = price end
  renderRows()
  advanceQuote()
end

-- ---------------------------------------------------------------------------
-- Posting. COMPLIANCE: C_AuctionHouse.PostItem/PostCommodity/ConfirmPostItem/
-- ConfirmPostCommodity are called ONLY from onPostClick below, itself only ever reached from
-- the Post button's own OnClick -- a real hardware click, same discipline as every purchase
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
    row.postBtn:Disable()
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
  -- call, floored at 1 silver. The displayed recommended price (row.recommendedText) is left
  -- un-rounded -- this only affects what's actually posted.
  local postUnit = math.max(100, math.floor(recommended / 100) * 100)
  local qty = math.min(inBags, flip.qty)
  local location = ItemLocation:CreateFromBagAndSlot(bag, slot)

  postingRow = row
  row.postStage = "posting"
  row.postBtn:Disable()
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
    row.postBtn:Enable()
    row.postBtn:SetText("Confirm")
    setStatus("posting below usual price -- click Post again to confirm")
  else
    schedulePostTimeout(row)
  end
end

local function onRemoveClick(row)
  local flip = row.flip
  if not flip then return end
  if row == postingRow then
    setStatus("finish the pending post first")
    return
  end
  local index = currentIndexOf(flip)
  if index then GC.Data.RemoveFlip(index) end
  renderRows()
end

function GC.Sell.OnAuctionCreated()
  local row = postingRow
  if not row then return end -- not something we posted (e.g. the player posted manually via Blizzard's own AH window)
  postingRow = nil
  local index = row.flip and currentIndexOf(row.flip)
  if index then GC.Data.MarkFlipPosted(index) end
  setStatus("posted")
  renderRows()
end

function GC.Sell.OnPostError()
  local row = postingRow
  if not row then return end
  postingRow = nil
  row.postStage = nil
  row.pendingPost = nil
  row.postBtn:Enable()
  row.postBtn:SetText("Post")
  setStatus("posting failed -- check the item and try again")
  renderRows()
end

-- Stamps every widget in `row` from a (possibly reused) flip entry -- mirrors
-- SniperFrame.lua's setRowDeal exactly, including the async icon/name load's identity guard
-- (`row.flip ~= flip`, same reason as setRowDeal's `row.deal ~= deal`).
setRowFlip = function(row, flip)
  row.flip = flip
  row.postStage = nil
  row.pendingPost = nil
  row.postBtn:SetText("Post")

  local inBags = countInBags(flip.itemID)
  row.bagsText:SetText(("%d / %d"):format(inBags, flip.qty))
  row.paidText:SetText(formatAmount(flip.paidUnit))

  local quote = quotes[flip.itemID]
  local recommended
  if quote then
    row.lowestText:SetText(formatAmount(quote))
    recommended = math.max(1, quote - 1)
  else
    row.lowestText:SetText("?")
    recommended = flip.targetUnit
  end

  local breakeven = flip.paidUnit / 0.95
  local isLoss = recommended < breakeven
  row.recommendedText:SetText(formatAmount(recommended))
  if isLoss then
    row.recommendedText:SetTextColor(1, 0.3, 0.3)
    row.recTooltip = ("Below break-even (%s) -- (loss)"):format(formatAmount(math.ceil(breakeven)))
  else
    row.recommendedText:SetTextColor(1, 1, 1)
    row.recTooltip = "Current lowest quote minus 1 copper (or the buy-time target before a quote exists)"
  end

  if inBags > 0 then row.postBtn:Enable() else row.postBtn:Disable() end

  row.nameText:SetText(("item %d"):format(flip.itemID))
  row.icon:SetTexture(nil)
  local item = Item:CreateFromItemID(flip.itemID)
  item:ContinueOnItemLoad(function()
    if row.flip ~= flip then return end -- row was repurposed before the async load finished
    row.icon:SetTexture(item:GetItemIcon())
    local quality = item:GetItemQuality()
    local qc = quality and ITEM_QUALITY_COLORS[quality] and ITEM_QUALITY_COLORS[quality].color
    local label = item:GetItemName() or ("item " .. flip.itemID)
    row.nameText:SetText(qc and qc:WrapTextInColorCode(label) or label)
  end)

  row:Show()
end

-- ---------------------------------------------------------------------------
-- Row widgets. Column order left to right: icon+name (flex) | bags/bought | paid | lowest |
-- recommended | Post | remove (x). Anchored right-to-left off the remove button, same reason
-- as SniperFrame.lua's createRow: a fixed-width column can never end up painted over by a
-- neighboring button.
-- ---------------------------------------------------------------------------

createRow = function(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(ROW_WIDTH, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetAllPoints()
  zebra:SetColorTexture(1, 1, 1, (index % 2 == 1) and 0.08 or 0)

  local highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.12)
  highlight:Hide()
  row.highlight = highlight

  local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  removeBtn:SetSize(REMOVE_WIDTH, 18)
  removeBtn:SetPoint("RIGHT")
  removeBtn:SetText("x")
  removeBtn:SetScript("OnClick", function() onRemoveClick(row) end)
  row.removeBtn = removeBtn

  local postBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  postBtn:SetSize(POST_WIDTH, 18)
  postBtn:SetPoint("RIGHT", removeBtn, "LEFT", -BTN_GAP, 0)
  postBtn:SetText("Post")
  postBtn:SetScript("OnClick", function() onPostClick(row) end)
  row.postBtn = postBtn

  local recommendedText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  recommendedText:SetPoint("RIGHT", postBtn, "LEFT", -COL_GAP, 0)
  recommendedText:SetWidth(REC_WIDTH)
  recommendedText:SetJustifyH("RIGHT")
  recommendedText:SetWordWrap(false)
  row.recommendedText = recommendedText

  -- Recommended-price hover: "(loss)" detail, same invisible-hit-frame pattern as
  -- SniperFrame.lua's dialog itemHit (FontStrings can't take mouse scripts themselves).
  local recHit = CreateFrame("Frame", nil, row)
  recHit:SetPoint("TOPLEFT", recommendedText, "TOPLEFT")
  recHit:SetPoint("BOTTOMRIGHT", recommendedText, "BOTTOMRIGHT")
  recHit:EnableMouse(true)
  recHit:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Recommended post price", 1, 0.82, 0)
    GameTooltip:AddLine(row.recTooltip or "", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  recHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row.recHit = recHit

  local lowestText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  lowestText:SetPoint("RIGHT", recommendedText, "LEFT", -COL_GAP, 0)
  lowestText:SetWidth(LOWEST_WIDTH)
  lowestText:SetJustifyH("RIGHT")
  lowestText:SetWordWrap(false)
  row.lowestText = lowestText

  local paidText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  paidText:SetPoint("RIGHT", lowestText, "LEFT", -COL_GAP, 0)
  paidText:SetWidth(PAID_WIDTH)
  paidText:SetJustifyH("RIGHT")
  paidText:SetWordWrap(false)
  row.paidText = paidText

  local bagsText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  bagsText:SetPoint("RIGHT", paidText, "LEFT", -COL_GAP, 0)
  bagsText:SetWidth(BAGS_WIDTH)
  bagsText:SetJustifyH("RIGHT")
  bagsText:SetWordWrap(false)
  row.bagsText = bagsText

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("LEFT")
  row.icon = icon

  local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  nameText:SetPoint("LEFT", icon, "RIGHT", NAME_GAP, 0)
  nameText:SetPoint("RIGHT", bagsText, "LEFT", -COL_GAP, 0)
  nameText:SetJustifyH("LEFT")
  nameText:SetWordWrap(false)
  nameText:SetMaxLines(1)
  row.nameText = nameText

  -- Whole-row hover: item GameTooltip + highlight, same pattern as SniperFrame.lua's deal rows.
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    self.highlight:Show()
    if not self.flip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.flip.itemID)
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
-- quote walk nor a post can safely resume once the AH session is gone. Cached `quotes` are
-- deliberately left alone (same "persist across a close/reopen" choice as Full Scan results),
-- since a slightly-stale lowest price is still useful until the player refreshes again.
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
end

-- Builds the Sell tab's container: a hidden frame filling the exact region `geometry` describes
-- (the same rectangle SniperFrame.lua's deals `scroll` occupies) -- its own Refresh-prices
-- button, static column headers, and pooled-row scroll frame. geometry.rowWidth/rowHeight are
-- SniperFrame.lua's own ROW_WIDTH/ROW_HEIGHT passed through so the two views' row grids can
-- never drift out of sync with each other.
function GC.Sell.Attach(f, geometry)
  ROW_WIDTH = geometry.rowWidth
  ROW_HEIGHT = geometry.rowHeight
  statusOwner = f

  container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", geometry.panelLeft, geometry.top)
  container:SetPoint("BOTTOMRIGHT", -geometry.panelRightInset, geometry.bottom)
  container:Hide()

  local refreshBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
  refreshBtn:SetSize(110, HEADER_TOP_ROW - 2)
  refreshBtn:SetPoint("TOPRIGHT", 0, 0)
  refreshBtn:SetText("Refresh prices")
  refreshBtn:SetScript("OnClick", onRefreshClick)
  container.refreshBtn = refreshBtn

  -- Static column header labels (no sort, no per-header tooltip -- unlike the Deals headers,
  -- Sell's columns are numeric and small enough to read directly).
  local HEADER_Y = -(HEADER_TOP_ROW + 4)
  local removeX = ROW_WIDTH - REMOVE_WIDTH
  local postX = removeX - BTN_GAP - POST_WIDTH
  local recX = postX - COL_GAP - REC_WIDTH
  local lowestX = recX - COL_GAP - LOWEST_WIDTH
  local paidX = lowestX - COL_GAP - PAID_WIDTH
  local bagsX = paidX - COL_GAP - BAGS_WIDTH
  local itemWidth = bagsX - COL_GAP

  local function addSellHeader(text, x, width, justify)
    local label = container:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", x, HEADER_Y)
    label:SetWidth(width)
    label:SetJustifyH(justify)
    label:SetText(text)
  end

  addSellHeader("Item", 0, itemWidth, "LEFT")
  addSellHeader("Bags / Bought", bagsX, BAGS_WIDTH, "RIGHT")
  addSellHeader("Paid", paidX, PAID_WIDTH, "RIGHT")
  addSellHeader("Lowest", lowestX, LOWEST_WIDTH, "RIGHT")
  addSellHeader("Rec.", recX, REC_WIDTH, "RIGHT")

  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -(HEADER_TOP_ROW + HEADER_HEIGHT + HEADER_GAP))
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
