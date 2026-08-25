local _, GC = ...

GC.Sell = GC.Sell or {}

-- Labels for the posting-queue keybinding (Bindings.xml, auto-loaded by the client -- see that
-- file for the binding itself and GC.Sell.Attach below for the handler it calls). Purely
-- cosmetic: the Key Bindings UI falls back to the raw action name if these are missing, so the
-- feature works without them, but a human label is worth the two lines. `_G.` explicit, not a
-- bare assignment, so this is a plain field write on the standard `_G` table rather than a new
-- global luacheck would need to be told about.
_G.BINDING_HEADER_GOLDCAP = "GoldCap"
_G.BINDING_NAME_GOLDCAP_POST_NEXT = "Post the next queued item"

local Theme = GC.Theme
local ROW_HEIGHT, ROW_WIDTH
local SELL_BAGS = { 0, 1, 2, 3, 4, 5 }
-- The auction's listing duration: 1 = 12h, 2 = 24h, 3 = 48h, matching the `duration` argument
-- the two posting calls in onPostClick below take -- see Core/Init.lua's own comment on
-- settings.sniper.postDuration for the same mapping. Read fresh on every post rather than
-- cached once, so a change in the settings panel takes effect on the very next click with no
-- reload. Falls back to 2 (this addon's long-standing default) for a missing settings table, a
-- value nobody has ever set, or anything that is not exactly one of the three durations the API
-- accepts -- a typo or a hand-edited SavedVariables value must never reach a protected call.
local function postDuration()
  local settings = GC.db and GC.db.settings and GC.db.settings.sniper
  local value = settings and settings.postDuration
  if value == 1 or value == 2 or value == 3 then return value end
  return 2
end
local QUOTE_STALE_SECONDS = (GC.QuoteCache and GC.QuoteCache.MAX_AGE_SECONDS) or 10
local POST_TIMEOUT_SECONDS, REPOST_ARM_SECONDS, REPOST_TIMEOUT_SECONDS = 8, 3, 10
-- Removing a manual cost has no deposit at stake, so it skips REPOST_ARM_SECONDS' forced delay
-- before the second click counts -- that delay exists to stop an accidental double-click from
-- burning a deposit, and there is no deposit here. The confirmation window still expires, the
-- same way a repost's does.
local REMOVE_TIMEOUT_SECONDS = 8
local MAX_EXACT = 9007199254740991
-- How old a quote may be and still back a Post or a Repost.
--
-- The Sniper's 10s window is right for a purchase: it commits gold against one
-- price point. A listing competes over hours, and 10s made Post effectively
-- unclickable -- pricing the whole tab takes longer than that, so by the time
-- the walk finished the first row's quote had already expired, and clicking Post
-- only ever started another walk. Wide enough that a click lands, narrow enough
-- that the price on screen is the price you get.
local SELL_QUOTE_ACTION_AGE = 45
-- Gap between automatic re-pricing passes while the tab is open and the auction
-- house is up. Prices stay live on their own instead of waiting for Refresh --
-- which is also why PROFIT / UNIT no longer reads Unknown until you press it.
local WALK_REPEAT_SECONDS = 5
-- A phase that answers no event is a wedge: Refresh used to refuse to run while
-- one was in flight, so a single unanswered owned-auctions query or item-key
-- lookup made the button dead for the rest of the session.
local PHASE_WATCHDOG_SECONDS = 15

-- The positions module owns all accounting and action-plan decisions.  This file only joins
-- live AH observations, a cached quote stream, and widgets around that single model.
-- Per-unit framing: a seller reasons in "what did one cost me, what does one fetch, what do I
-- clear on one", not in position totals -- the totals already sit in the summary above the list.
-- `status` carries the recommendation (what to do and at what price) and `action` owns the
-- button. They used to be one column, with the button drawn over the text, which destroyed the
-- only place the target price was ever shown. `listed` is the optional one now: its total is in
-- the summary, whereas the market price is what every decision on this screen turns on.
local COLUMNS = {
  { key = "item", flex = true, min = 200 },
  { key = "cost", w = 92, num = true },
  { key = "listed", w = 88, num = true, optional = true },
  { key = "market", w = 92, num = true },
  { key = "profit", w = 96, num = true, bold = true },
  { key = "status", w = 176 },
  { key = "action", w = 88 },
  { key = "expand", w = 22 },
}

local container, content, statusOwner
local rows, positions, ownedLots, quotes = {}, {}, {}, {}
-- Stamped by composePositions() as it walks every position, so SellableCount() can read it
-- without recomposing. nil only until the first compose has ever run.
local sellableCount
-- The posting queue, DERIVED, never stored: rebuilt by composePositions() every time positions
-- are, straight from GC.PostQueue.Build(positions). There is deliberately no separate stateful
-- queue with an index into it -- a post empties that item from the bags, so the entry drops out
-- of the very next build on its own. A stored queue is a second source of truth that can
-- disagree with the bags, which is exactly the class of bug this codebase has been bitten by
-- before (see the price-ladder and market-value postmortems). Both default to {} so the toolbar
-- control has something sane to paint before the very first compose ever runs.
local queueEntries, queueSkipped = {}, {}
-- The cancel twin, same statelessness contract: rebuilt from the positions on every compose,
-- never kept as its own list with an index. A confirmed cancel makes the lot vanish from
-- GetOwnedAuctions, so the entry drops out of the very next build on its own.
local cancelEntries, cancelSkipped = {}, {}
local bagStock = {}
local sessionCommodityKind = {}
-- Still "all": hiding the player's live listings behind a filter to answer "what
-- can I list" would trade one blind spot for another. What changed is the order
-- -- everything postable now sorts to the top (see SellViewModel.Order) -- and a
-- Sellable chip for narrowing to it deliberately.
local expanded, filterMode = {}, "all"
local refresh = { generation = 0, phase = "idle", queue = {}, index = 0, pending = nil, awaiting = nil, drain = {} }
local quoteTimeoutToken = 0
local walkRepeatToken, watchdogToken = 0, 0
local postingRow, postingPin, postTimeoutToken
local repostingRow, repostPin, repostArmToken = nil, nil, 0
local removingRow, removePin, removeArmToken = nil, nil, 0
local renderGeneration = 0
local quoteExpiryGeneration = 0
local manualRepairNonce = 0
-- Defined below, once normalizedPositionKey exists to derive an auction identity
-- from a bag link; composePositions only ever calls it at runtime.
local scanBagStock

-- Forward-declared here rather than further down: disarmPost/disarmRepost below
-- need to flush a render that was deferred while a purchase was armed.
local function renderRows() end
local deferredRender = false
-- Forward-declared for the same reason renderRows is: setStatus (defined further down, but
-- above formatCell) needs to call this on every state change, and composePositions (much
-- further down) needs to call it on every data change -- see this function's real body, well
-- below formatCell, for why it cannot be defined this early itself. renderRows DEFERS for the
-- whole time a post is armed (disarmPost/disarmRepost's own flushDeferredRender), so a render is
-- not a reliable place to keep the queue control's own label in sync with the confirm/posting
-- dance -- this is driven the same way paintRefreshButton already is, from setStatus.
local function paintQueueButton() end
-- Forward-declared for the same reason paintQueueButton is: disarmRepost and the repost arm
-- timer (both above the real body) must keep the cancel control's label in sync with the
-- arm/confirm dance, because renderRows defers for the whole time a repost is armed.
local function paintCancelButton() end

local function restorePostRow(row)
  if not row then return end
  row.postStage = nil
  if row.action then row.action:Enable(); row.action:SetLabel("Post") end
end

local function restoreRepostRow(row)
  if not row then return end
  row.repostStage, row.repostReady = nil, nil
  if row.action then row.action:Enable(); row.action:SetLabel("Repost") end
end

local function restoreRemoveRow(row)
  if not row then return end
  row.removeStage = nil
  if row.action then row.action:Enable(); row.action:SetLabel("Remove") end
end

local function flushDeferredRender()
  if deferredRender and not postingRow and not repostingRow and not removingRow then renderRows() end
end

local function disarmPost()
  local row = postingRow
  postingRow, postingPin = nil, nil
  postTimeoutToken = (postTimeoutToken or 0) + 1
  restorePostRow(row)
  flushDeferredRender()
end

local function disarmRepost()
  local row = repostingRow
  repostingRow, repostPin = nil, nil
  repostArmToken = (repostArmToken or 0) + 1
  restoreRepostRow(row)
  flushDeferredRender()
  paintCancelButton()
end

local function disarmRemove()
  local row = removingRow
  removingRow, removePin = nil, nil
  removeArmToken = (removeArmToken or 0) + 1
  restoreRemoveRow(row)
  flushDeferredRender()
end

-- The status line lives in the Sniper's toolbar, at the far left of a different
-- row from the Refresh button -- a window's width away from what was just
-- pressed. That is the same distance that made Scan look dead. So the button
-- carries the state too, and the progress with it: "PRICING 3/24" answers "is it
-- running" without the player having to hunt for a line of text.
local function paintRefreshButton()
  local button = container and container.refreshButton
  if not button then return end
  local phase = refresh.phase
  local busy = phase ~= "idle" and phase ~= "done" and phase ~= "error"
  local label = "REFRESH"
  if busy then
    -- "PRICING 10/24", not a bare "10/24". This button sits at the end of a row of filter
    -- chips, so a naked ratio reads as one more filter -- and the owner reasonably asked why
    -- the tab only had 24 items in it. It is not a count of anything the player owns: it is
    -- how far this pass has got through the pricing queue, which is capped at QUOTE_WALK_CAP
    -- because every entry is a round trip on the same throttled slot the Sniper's scans use.
    label = (#refresh.queue > 0 and refresh.index > 0)
      and ("PRICING %d/%d"):format(refresh.index, #refresh.queue) or "PRICING…"
  end
  if button.lastLabel ~= label then
    button.lastLabel = label
    button:SetLabel(label)
  end
  if button.lastBusy ~= busy then
    button.lastBusy = busy
    if button.SetVariant then button:SetVariant(busy and "active" or "ghost") end
  end
end

local function setStatus(text)
  if statusOwner and statusOwner.status then statusOwner.status:SetText(text) end
  paintRefreshButton()
  paintQueueButton()
end

local function setColor(fontString, color)
  if fontString and color then fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
end

-- Gold-carrying amounts render as plain text ("65g24s"), not GetCoinTextureString's coin
-- icons: the icon escapes are wide, and a truncated FontString cuts them MID-ESCAPE, which
-- painted lot labels as "bought 17 Aug at 1|..." in game. Sub-gold amounts keep the icons,
-- where they fit. Mirrors the Deals board's formatColumnAmount rule.
local function formatAmount(amount)
  if amount == nil then return "Unknown" end
  if amount < 0 then return "-" .. formatAmount(-amount) end
  if amount >= 10000 then
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    if silver == 0 then return ("%dg"):format(gold) end
    return ("%dg%02ds"):format(gold, silver)
  end
  return GetCoinTextureString(amount)
end

local function formatCell(value)
  return type(value) == "number" and formatAmount(value) or tostring(value or "")
end

-- Same inline color escape UI/SoldFrame.lua's DIM_HEX uses, for the same reason: the hold-price
-- suffix on the PROFIT/UNIT cell shares one FontString with the number in front of it, so there
-- is no separate region to SetTextColor -- the only way to dim part of the text is to color it
-- inline and close with |r.
local DIM_HEX = "|cff9d9d9d"

-- Skip reasons in words a seller would actually read, never GC.PostQueue's own internal token
-- -- see that module's own `evaluate` comment for what each one means structurally. A silently
-- short queue is the same lie as a silently short deals list; naming the reason in plain words
-- is what keeps it from being a DIFFERENT lie instead.
local QUEUE_SKIP_TEXT = {
  no_fresh_price = "needs a fresh price -- press Refresh",
  below_breakeven = "would sell at a loss",
  unresolved_identity = "GoldCap can't pin down which bag stack this is",
  -- The cancel queue's own reasons (GC.CancelQueue.Build): a cancel burns a deposit, so a
  -- held-back listing needs its why stated even more than a held-back post does.
  advised_hold = "relisting now would lock in a loss or a stall -- hold",
  no_advice = "cost basis incomplete -- set costs to get repost advice",
}

-- The real body, promised by the forward declaration above. Needs formatCell (just above) and
-- container/queueEntries/queueSkipped/postingRow (all declared well above this point), so it
-- could not be written any earlier than here.
paintQueueButton = function()
  local button, label = container and container.queueButton, container and container.queueLabel
  if not button then return end
  local heldBack, heldBackHit = container.queueHeldBack, container.queueHeldBackHit
  -- Row 1 of the QUEUE's own order, not of whatever filter chip happens to be on screen right
  -- now: this control acts on GC.PostQueue's own head regardless of what the player is currently
  -- looking at, and paints itself from that same head so what it says is never a guess about
  -- what a render would show if one ran right now.
  local head = queueEntries[1]
  if postingRow then
    -- Mirror the row postingRow itself pins to -- see onQueueClick/onPostClick -- only when
    -- that row genuinely IS the queue's own head. If some OTHER row's post is in flight (the
    -- player clicked a row's own Post button directly, on a position that is not the head),
    -- this control simply disables rather than offering a second, conflicting click; it must
    -- never claim "CONFIRM" for a click that would land on the wrong row.
    local sameHead = head and postingRow.position and postingRow.position.positionKey == head.positionKey
    if sameHead and postingRow.postStage == "confirm" then
      button:SetLabel("CONFIRM"); button:Enable()
    else
      button:SetLabel("POSTING…"); button:Disable()
    end
    if label and head then label:SetText(head.itemName or "") end
  elseif not head then
    button:SetLabel("NOTHING TO POST")
    button:Disable()
    if label then label:SetText("") end
  else
    button:SetLabel(("POST %d"):format(#queueEntries))
    button:Enable()
    if label then label:SetText(("%s @ %s"):format(head.itemName or "Item", formatCell(head.unitPrice))) end
  end
  if heldBack then
    if #queueSkipped > 0 then
      -- "from posting", because the cancel queue paints an identical counter near its own
      -- button (paintCancelButton below) and two bare "N held back" strings on one screen
      -- would leave the reader guessing which queue each one describes.
      heldBack:SetText(("%d held back from posting"):format(#queueSkipped))
      heldBack:Show()
      if heldBackHit then heldBackHit:Show() end
    else
      heldBack:SetText("")
      heldBack:Hide()
      if heldBackHit then heldBackHit:Hide() end
    end
  end
end

-- The cancel control's mirror of paintQueueButton, over the repost arm instead of the post
-- pin. States, in the order a click sequence produces them: "CANCEL N" -> "CANCEL LOT?" (the
-- head lot is armed; enabled only once the REPOST_ARM_SECONDS delay has passed, exactly like
-- the row's own button) -> "CANCELLING…". While some OTHER lot's repost is in flight the
-- control keeps its count but disables -- it must never offer a click that would land on the
-- wrong lot, the same rule paintQueueButton applies to a non-head post.
paintCancelButton = function()
  local button = container and container.cancelButton
  if not button then return end
  local heldBack, heldBackHit = container.cancelHeldBack, container.cancelHeldBackHit
  local head = cancelEntries[1]
  -- SetVariant runs BEFORE Enable/Disable in every branch: Theme.Button's OnDisable dims the
  -- text to fgDim, and SetVariant restores full-brightness text -- calling SetVariant after
  -- Disable() silently wiped the dimmed look this button needs while it has nothing to do.
  if repostingRow then
    local sameHead = head and repostPin and repostPin.auctionID == head.auctionID
    button:SetVariant("danger")
    if sameHead and repostingRow.repostStage == "cancelling" then
      button:SetLabel("CANCELLING…"); button:Disable()
    elseif sameHead and repostingRow.repostStage == "armed" then
      button:SetLabel("CANCEL LOT?")
      if repostingRow.repostReady then button:Enable() else button:Disable() end
    else
      button:SetLabel(("CANCEL %d"):format(#cancelEntries)); button:Disable()
    end
  elseif not head then
    button:SetVariant("ghost")
    button:SetLabel("NOTHING TO CANCEL")
    button:Disable()
  else
    button:SetVariant("danger")
    button:SetLabel(("CANCEL %d"):format(#cancelEntries))
    button:Enable()
  end
  if heldBack then
    if #cancelSkipped > 0 then
      heldBack:SetText(("%d held back"):format(#cancelSkipped))
      heldBack:Show()
      if heldBackHit then heldBackHit:Show() end
    else
      heldBack:SetText("")
      heldBack:Hide()
      if heldBackHit then heldBackHit:Hide() end
    end
  end
end

-- Action and price, nothing else. This cell used to narrate the pricing mode
-- in a sentence ("Post (queueing at your exit -- cheaper lots sell through
-- first) @ 18g15s · breakeven 20g41s"), and in game the words won: the column
-- truncated BEFORE the price, showing "Post (queueing at…" — advice with the
-- one number that matters cut off (owner, 2026-08-19). What survives the trim
-- is only what changes the player's next move: RepostAdvice's one-word hold
-- reason ("loss"/"slow"), and the below-cost warning.
local function recommendationText(recommendation)
  if type(recommendation) == "string" then return recommendation end
  if type(recommendation) ~= "table" then return "" end
  local action = recommendation.action
  if type(action) ~= "string" or action == "" then action = "post" end
  action = action:sub(1, 1):upper() .. action:sub(2)
  local nested = recommendation.rec
  local unit = nested and nested.unit or recommendation.unit
  local reason = type(recommendation.reason) == "string" and recommendation.reason or nil
  local text = action .. (reason and (" (" .. reason .. ")") or "")
    .. (unit and (" @ " .. formatCell(unit)) or "")
  if recommendation.belowCost then text = text .. " · below cost" end
  return text
end

local function exact(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

local function safeAdd(left, right)
  if not exact(left) or not exact(right) or left > MAX_EXACT - right then return nil end
  return left + right
end

local function safeMultiply(left, right)
  if not exact(left) or not exact(right) or (left ~= 0 and right > math.floor(MAX_EXACT / left)) then return nil end
  return left * right
end

local function context()
  return GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
end

local function activeScope(position)
  local scope = context()
  if type(position) ~= "table" or type(position.positionKey) ~= "string"
      or type(scope) ~= "table" or type(scope.char) ~= "string" or scope.char == ""
      or type(scope.region) ~= "string" or scope.region == "" then return nil, nil end
  local scopeKey
  if GC.Acquisitions and GC.Acquisitions.ScopeKey then
    scopeKey = GC.Acquisitions.ScopeKey(position.positionKey, scope)
  else
    scopeKey = table.concat({ scope.region, scope.char, position.positionKey }, "\1")
  end
  if scopeKey ~= position.scopeKey then return nil, nil end
  return scope, scopeKey
end

local function exactRenderEntry(row, pin)
  return row and pin and type(row.renderEntryID) == "string" and row.renderEntryID ~= ""
    and row.renderEntryID == pin.renderEntryID and pin.row == row and pin.action == row.action
    and pin.position == row.position
end

local function itemName(itemID)
  if C_Item and C_Item.GetItemNameByID then
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return ("Item %d"):format(itemID or 0)
end

local function quoteDriver()
  local function boundedLevels(itemID, commodity)
    local levels, count = {}, commodity and C_AuctionHouse.GetNumCommoditySearchResults(itemID)
      or C_AuctionHouse.GetNumItemSearchResults(C_AuctionHouse.MakeItemKey(itemID))
    for i = 1, math.min(count or 0, 100) do
      local info = commodity and C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        or C_AuctionHouse.GetItemSearchResultInfo(C_AuctionHouse.MakeItemKey(itemID), i)
      local unit = info and (commodity and info.unitPrice
        or (info.buyoutAmount and info.quantity and info.quantity > 0 and math.floor(info.buyoutAmount / info.quantity)))
      if unit and unit > 0 then
        levels[#levels + 1] = { unitPrice = unit, quantity = info.quantity or 0,
          ownerItem = info.containsOwnerItem == true, ownerQty = info.numOwnerItems }
      end
    end
    return #levels > 0 and levels or nil
  end

  local function competingOrOwnUnit(levels)
    if not levels then return nil end
    local competing = GC.SellPositions.CheapestCompetingUnit(levels)
    if competing then return competing end
    local own
    for i = 1, #levels do
      local unit = levels[i].unitPrice
      if type(unit) == "number" and unit > 0 and (own == nil or unit < own) then own = unit end
    end
    return own
  end
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
    -- Both price against the cheapest level somebody ELSE is selling at. Reading level 1 blind
    -- means pricing against your own auction the moment you are the cheapest seller, so every
    -- Post/Repost undercut the previous one and the price walked down against nobody. Sharing a
    -- level with real competitors still counts -- see SellPositions.CheapestCompetingUnit.
    --
    -- With no competition at all the fallback is the player's OWN cheapest listing: holding the
    -- current price is the honest answer there, where undercutting would just resume the walk.
    item = function(itemID)
      return competingOrOwnUnit(boundedLevels(itemID, false))
    end,
    commodity = function(itemID)
      return competingOrOwnUnit(boundedLevels(itemID, true))
    end,
    itemLevels = function(itemID) return boundedLevels(itemID, false) end,
    commodityLevels = function(itemID) return boundedLevels(itemID, true) end,
  }
end
local driver = quoteDriver()

-- The Sell tab's own persisted mirror of `quotes` (declared above, near COLUMNS): only
-- {unit, at}, never `levels` -- see Core/Init.lua's `sellQuotes` default for the write side
-- and why. nil once GC.db does not exist yet: Init.lua runs LAST in the .toc, so no store
-- exists at file load, and persistence is simply skipped until it does. Unlike
-- commodityKindCache above, there is no session-local fallback -- an unpersisted quote costs
-- nothing worse than today's behavior (a dash until the walk answers).
local function persistedQuotes()
  if not GC.db then return nil end
  GC.db.sellQuotes = type(GC.db.sellQuotes) == "table" and GC.db.sellQuotes or {}
  return GC.db.sellQuotes
end

-- How old a persisted quote may be and still seed `quotes` on the first compose after a
-- reload. Loose on purpose: a days-old price is still a better anchor than a dash (the
-- renderer's own " . stale %ds" tag already tells the truth about its age), but week-old
-- garbage should not resurrect and confuse a Post decision. Pruning here is also what stops
-- the persisted store growing forever, since nothing else ever deletes an old entry from it.
local QUOTE_PERSIST_MAX_AGE = 3 * 24 * 60 * 60

-- One-shot: composePositions() runs on every refresh tick, and re-merging the persisted store
-- on every one of them would let a persisted quote silently resurrect over a quote this
-- session has already, correctly, forgotten (an empty answer via skipPendingQuote). Guarded on
-- GC.db existing at all -- the very first compose can run before ADDON_LOADED has -- so a
-- session with no store yet simply retries on the next compose instead of flipping the flag on
-- nothing.
local quotesSeeded = false
local function seedPersistedQuotes()
  local store = persistedQuotes()
  if not store then return end
  quotesSeeded = true
  local now = time()
  for itemID, entry in pairs(store) do
    local unit = type(entry) == "table" and entry.unit or nil
    local at = type(entry) == "table" and entry.at or nil
    local valid = exact(unit) and unit > 0 and exact(at) and at <= now and (now - at) <= QUOTE_PERSIST_MAX_AGE
    if valid then
      -- A live answer this session already produced beats a persisted one.
      if quotes[itemID] == nil then quotes[itemID] = { unit = unit, at = at } end
    else
      store[itemID] = nil
    end
  end
end

local function composePositions()
  if not quotesSeeded then seedPersistedQuotes() end
  local scope = context()
  if scanBagStock then scanBagStock() end
  local stats = {}
  for _, lot in ipairs(ownedLots) do
    stats[lot.itemID] = GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(lot.itemID) or nil
  end
  for _, stock in ipairs(bagStock) do
    stats[stock.itemID] = stats[stock.itemID]
      or (GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(stock.itemID) or nil)
  end
  local batches = GC.Acquisitions and GC.Acquisitions.GetActive and GC.Acquisitions.GetActive(scope) or {}
  for _, batch in ipairs(batches) do
    stats[batch.itemID] = stats[batch.itemID] or (GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(batch.itemID) or nil)
  end
  local pending = GC.Acquisitions and GC.Acquisitions.GetPending and GC.Acquisitions.GetPending(scope) or {}
  local activities = GC.Acquisitions and GC.Acquisitions.GetActivities and GC.Acquisitions.GetActivities(scope) or {}
  local consumed = {}
  for _, realized in ipairs(GC.Acquisitions and GC.Acquisitions.GetRealized and GC.Acquisitions.GetRealized(scope) or {}) do
    if realized.evidenceKey then consumed[realized.evidenceKey] = true end
  end
  local sellerEvidence = {}
  for _, entry in ipairs(GC.Ledger and GC.Ledger.GetEntries and GC.Ledger.GetEntries() or {}) do
    if entry.kind == "sale" and entry.source == "mail" and entry.char == scope.char
        and entry.region == scope.region and not consumed[entry.key] then
      sellerEvidence[#sellerEvidence + 1] = entry
    end
  end
  -- Identity evidence travels separately from `batches`: GetActive drops a batch the moment it
  -- is sold out, and taking the item's auction identity from that same list is what orphaned
  -- every keyless batch of a fully-sold item into its own repair row.
  local identityEvidence = GC.Acquisitions and GC.Acquisitions.GetIdentityEvidence
    and GC.Acquisitions.GetIdentityEvidence(scope) or {}
  positions = GC.SellPositions.Build({ acquisitions = batches, identityEvidence = identityEvidence,
    pendingAcquisitions = pending,
    activities = activities, sellerEvidence = sellerEvidence, ownedLots = ownedLots,
    bagStock = bagStock, quotes = quotes, statsByItemID = stats, context = scope, now = time(),
    quoteMaxAge = SELL_QUOTE_ACTION_AGE })
  -- Stamped in the same walk this function already does over every position, rather than a
  -- second pass triggered from SellableCount() -- see that function for why a fresh compose
  -- per label-read was wasteful (a six-bag scan plus every Acquisitions/Ledger walk, on a tab
  -- that may not even be the one currently shown).
  local sellable = 0
  for _, position in ipairs(positions) do
    if position.itemID and not position.itemName then position.itemName = itemName(position.itemID) end
    if (position.bagQty or 0) > 0 then sellable = sellable + 1 end
  end
  sellableCount = sellable
  -- Rebuilt from THESE positions, every time -- never kept as a separate stateful list. See
  -- this file's own queueEntries/queueSkipped declaration for why. Guarded for GC.PostQueue
  -- being absent: every real load carries Core/PostQueue.lua (GoldCap.toc), but a handful of
  -- older fixtures in this spec suite load UI/SellFrame.lua without it, and a missing queue
  -- module must degrade to "nothing queued," never a crash.
  if GC.PostQueue and GC.PostQueue.Build then
    queueEntries, queueSkipped = GC.PostQueue.Build(positions)
  else
    queueEntries, queueSkipped = {}, {}
  end
  paintQueueButton()
  -- The cancel twin, same degradation contract for fixtures loaded without the module.
  if GC.CancelQueue and GC.CancelQueue.Build then
    cancelEntries, cancelSkipped = GC.CancelQueue.Build(positions)
  else
    cancelEntries, cancelSkipped = {}, {}
  end
  paintCancelButton()
end

-- Which items the pricing walk asks the server about.
--
-- This used to be every position, which was fine when a position only existed
-- for something GoldCap had bought. Now that the tab knows what is in the bags,
-- a full inventory is easily sixty sellable stacks -- and the walk repeats. Sixty
-- throttled round trips on a loop would crowd out the Sniper's own scans and the
-- player's own searches, for prices on rows nobody is going to act on.
--
-- So: only what can be acted on (stock in the bags, or a live listing that could
-- be reposted), most valuable first, and capped. Everything else keeps whatever
-- quote it already has and shows its age honestly.
local QUOTE_WALK_CAP = 40
-- A quote younger than this is not re-asked about: it is already fresh enough for every
-- decision on this screen, and re-pricing it burns one of the walk's throttled server round
-- trips that a never-priced row further down the list needed. 30 sits under
-- SELL_QUOTE_ACTION_AGE (45) by more than a whole pass takes, so a quote is renewed before
-- the Post/Repost window on it ever closes. This is what turned the permanent
-- "PRICING N/24" grind into an empty steady-state pass.
local QUOTE_REWALK_AGE = 30
-- How long "the auction house answered: nothing listed" is remembered and treated like a
-- fresh quote. Without this, an item with zero live listings was indistinguishable from one
-- never asked about -- its cache entry was wiped on the empty answer -- so EVERY pass re-asked
-- it (or burned the full request timeout on one that never answers), which is what ground a
-- tab full of niche items to a crawl. A manual Refresh wipes these: the player asked for real.
local EMPTY_ANSWER_AGE = 60
local emptyAnswers = {}
-- How long a drain tombstone may fence off an item. The fence exists so a LATE answer to an
-- abandoned request cannot be credited to a new request for the same item -- but it used to
-- be permanent, cleared only by the very event that never comes for a silently-lost request,
-- and ONE such item then wedged every later pass in "draining" until the watchdog shot it.
-- Past this window the lost answer is not arriving; the fence lifts and the item is asked
-- again (advanceQuote).
local DRAIN_MAX_SECONDS = 15

local function uniqueQuoteItemIDs()
  local actionable = {}
  for _, position in ipairs(positions) do
    local inBags = type(position.bagQty) == "number" and position.bagQty > 0
    local listed = type(position.listedQty) == "number" and position.listedQty > 0
    -- Membership, not just order: a still-fresh quote is excluded from the pass entirely.
    -- Freshness used to decide only the ORDER, so every pass re-asked the server about the
    -- whole tab -- see QUOTE_REWALK_AGE above for what that cost. A remembered "nothing
    -- listed" answer counts as fresh too (EMPTY_ANSWER_AGE above).
    local answeredEmptyAt = emptyAnswers[position.itemID]
    local answeredEmpty = type(answeredEmptyAt) == "number"
      and (time() - answeredEmptyAt) <= EMPTY_ANSWER_AGE
    local due = (position.displayMarketUnit == nil or type(position.quoteAge) ~= "number"
      or position.quoteAge > QUOTE_REWALK_AGE) and not answeredEmpty
    -- An unresolved position is priced anyway when it is a COMMODITY holding stock: the
    -- identity question is about cost, and a commodity's market price is exact for its
    -- itemID no matter whose stock it is -- leaving every tiered reagent caught in identity
    -- repair at "—" forever read as this walk being broken. Unresolved variant ITEMS stay
    -- excluded: a basic-key quote can be a different variant's price, and a wrong number is
    -- worse than none.
    local commodity = type(position.positionKey) == "string"
      and position.positionKey:find("commodity:", 1, true) == 1
    local pricable = not position.unresolved or commodity
    if pricable and position.itemID and (inBags or listed) and due then
      actionable[#actionable + 1] = position
    end
  end
  -- Ordered by NEED, not by value. Ordering by value starved the tail: a row
  -- that had just been priced sorted to the front of the very next pass, ahead
  -- of rows that had never been priced at all, so the bottom of a long list
  -- never got asked about. Never-priced first, then oldest quote first, and only
  -- then by value -- which still decides between two equally stale rows, because
  -- a stale price on a 200-unit stack of ore costs more than one on a lone flask.
  local need, weight = {}, {}
  for index, position in ipairs(actionable) do
    local age = position.quoteAge
    need[position] = (position.displayMarketUnit == nil or type(age) ~= "number")
      and math.huge or age
    local unit = position.freshMarketUnit or position.displayMarketUnit
    local qty = position.bagQty or 0
    weight[position] = (unit and qty > 0 and unit * qty)
      or (type(position.listedValue) == "number" and position.listedValue) or 0
    position.__walkOrder = index
  end
  table.sort(actionable, function(left, right)
    if need[left] ~= need[right] then return need[left] > need[right] end
    if weight[left] ~= weight[right] then return weight[left] > weight[right] end
    return left.__walkOrder < right.__walkOrder
  end)
  local seen, result = {}, {}
  for _, position in ipairs(actionable) do
    if not seen[position.itemID] then
      seen[position.itemID], result[#result + 1] = true, position.itemID
      if #result >= QUOTE_WALK_CAP then break end
    end
  end
  return result
end

local function scheduleQuoteExpiry()
  quoteExpiryGeneration = quoteExpiryGeneration + 1
  local token = quoteExpiryGeneration
  if not (C_Timer and C_Timer.After) then return end
  local delay
  for _, position in ipairs(positions) do
    if position.freshMarketUnit and type(position.quoteAge) == "number" then
      -- Must be the same window the rest of the tab treats as fresh. Left at the
      -- Sniper's 10s it would wake while the quote was still good and then never
      -- wake again, so a quote that HAD gone stale kept rendering as current.
      local remaining = SELL_QUOTE_ACTION_AGE - position.quoteAge + 1
      if remaining > 0 and (not delay or remaining < delay) then delay = remaining end
    end
  end
  if not delay then return end
  C_Timer.After(delay, function()
    if token ~= quoteExpiryGeneration then return end
    composePositions()
    renderRows()
  end)
end

-- Whether the Sell CONTENT is the tab actually on screen right now, as opposed to merely
-- attached. `composePositions()`/`GC.Sell.Refresh()` run regardless of which tab the player
-- is looking at (bag counts and the tab badge stay current either way) -- this is the
-- narrower check that guards the expensive part, rebuilding the visible ROWS.
local function containerShown()
  return container ~= nil and container.IsShown and container:IsShown()
end

local function tabIsLive()
  return containerShown() and GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen()
end

-- Keeps the prices on screen live instead of frozen at whatever the last button
-- press fetched. Without it the market column ages out and PROFIT / UNIT falls
-- back to Unknown until the player presses Refresh, which is the sort of chore a
-- program should not be delegating.
local function scheduleNextWalk()
  walkRepeatToken = walkRepeatToken + 1
  local token = walkRepeatToken
  if not (C_Timer and C_Timer.After) then return end
  C_Timer.After(WALK_REPEAT_SECONDS, function()
    if token ~= walkRepeatToken or not tabIsLive() then return end
    if refresh.phase ~= "done" and refresh.phase ~= "idle" and refresh.phase ~= "error" then return end
    GC.Sell.Refresh(true)
  end)
end

-- Let go of a request we are no longer waiting for, leaving a tombstone so its
-- late terminal event is consumed rather than mistaken for the next run's.
local function abandonInFlightQuote()
  local pending = refresh.pending
  if pending then
    refresh.drain[pending.kind .. ":" .. pending.itemID] = {
      abandonedGeneration = pending.generation,
      terminals = 1,
      at = time(),
    }
  end
  refresh.pending, refresh.awaiting = nil, nil
  quoteTimeoutToken = quoteTimeoutToken + 1
end

local function markProgress()
  refresh.progressAt = time()
end

-- Forward-declared: skipPendingQuote below has to be able to carry the pass on
-- to the next item, and advanceQuote's real definition needs the walk state it
-- sits above.
local advanceQuote

local function finishQuoteWalk()
  refresh.phase = "done"
  refresh.pending, refresh.awaiting = nil, nil
  local skipped = refresh.skipped or 0
  setStatus(skipped > 0
    and ("Prices up to date · %d did not answer"):format(skipped)
    or "Prices up to date")
  renderRows()
  scheduleNextWalk()
end

-- One item failing is not the pass failing.
--
-- This used to park the whole machine in "error" and stop, so a single item that
-- did not answer within the request window ended the pass -- and with a tab full
-- of bag stock, the automatic repeat then restarted from the top and hit the
-- same item again. Items further down the queue were never reached at all, which
-- is why most rows sat with no market price no matter how long you waited.
--
-- `timedOut` distinguishes the two failures. A timeout taught us nothing, so any
-- quote already on hand is kept and left to age visibly; an answer that came
-- back empty or nonsensical means there is genuinely nothing on sale, and the
-- stale quote must go rather than be presented as current.
local function skipPendingQuote(pending, timedOut)
  if refresh.pending ~= pending or pending.generation ~= refresh.generation then return end
  -- Either way -- an empty answer or no answer at all -- this item earned a rest: re-asking
  -- it on the very next pass is what burned the walk's slots (and, for the silent ones, a
  -- whole request timeout each) on items with nothing to say. See EMPTY_ANSWER_AGE.
  emptyAnswers[pending.itemID] = time()
  if timedOut then
    -- A late terminal event for this request must still be consumed rather than
    -- credited to whatever the walk is asking about by then.
    refresh.drain[pending.kind .. ":" .. pending.itemID] = {
      abandonedGeneration = pending.generation,
      terminals = 1,
      at = time(),
    }
  else
    quotes[pending.itemID] = nil
    local persisted = persistedQuotes()
    if persisted then persisted[pending.itemID] = nil end
  end
  refresh.pending = nil
  refresh.skipped = (refresh.skipped or 0) + 1
  refresh.phase = "pricing"
  markProgress()
  advanceQuote()
end

local function scheduleQuoteTimeout(pending)
  if not (C_Timer and C_Timer.After) then return end
  quoteTimeoutToken = quoteTimeoutToken + 1
  local token = quoteTimeoutToken
  C_Timer.After(QUOTE_STALE_SECONDS, function()
    if token == quoteTimeoutToken then skipPendingQuote(pending, true) end
  end)
end

-- Three of the refresh phases wait on an event that is not guaranteed to arrive:
-- an owned-auctions query, an item-key lookup, and a drain waiting for the
-- terminal of a request that already timed out. Each one used to hold the
-- machine in a phase Refresh refused to leave, so a single unanswered call made
-- the button dead until the player logged out. This lets the phase go.
local function armPhaseWatchdog()
  watchdogToken = watchdogToken + 1
  local token = watchdogToken
  if not (C_Timer and C_Timer.After) then return end
  local function tick()
    if token ~= watchdogToken then return end
    local phase = refresh.phase
    if phase == "idle" or phase == "done" or phase == "error" then return end
    if time() - (refresh.progressAt or 0) >= PHASE_WATCHDOG_SECONDS then
      abandonInFlightQuote()
      refresh.phase = "error"
      setStatus("Auction House did not answer — press Refresh")
      scheduleNextWalk()
      return
    end
    C_Timer.After(PHASE_WATCHDOG_SECONDS, tick)
  end
  C_Timer.After(PHASE_WATCHDOG_SECONDS, tick)
end

advanceQuote = function()
  if refresh.phase ~= "pricing" and refresh.phase ~= "waiting_key" then return end
  if refresh.pending then return end
  if refresh.index >= #refresh.queue then return finishQuoteWalk() end
  -- Yields to a Check or a purchase -- short, and the player is waiting on it --
  -- but NOT to the background full scan. Under Auto that scan never stops, and
  -- standing aside for it meant the Sell tab priced nothing at all while Auto
  -- was on: Refresh looked hung until a reload happened to catch a gap.
  local blocking = GC.Sniper and (GC.Sniper.IsSearchCritical or GC.Sniper.IsBusy)
  if blocking and blocking() then
    -- Yielding is the walk working correctly, not stalling, so the watchdog must
    -- not read it as an unanswered request.
    markProgress()
    setStatus("Waiting for the purchase to finish…")
    return
  end
  if not driver.isReady() then
    -- The shared search slot is busy with someone else's request (the Deals scan, a purchase
    -- Check) -- the walk is stalled on purpose, not stuck, so this must feed the watchdog
    -- exactly like the purchase-yield branch above and say why, once per walk rather than on
    -- every tick.
    markProgress()
    if not refresh.waitingNoted then
      refresh.waitingNoted = true
      setStatus("Waiting for the Auction House… (another search holds the slot)")
    end
    return
  end
  local itemID = refresh.awaiting or refresh.queue[refresh.index + 1]
  if driver.keyInfo(itemID) then
    local info = driver.keyInfo(itemID)
    local kind = info.isCommodity and "commodity" or "item"
    local tombstone = refresh.drain[kind .. ":" .. itemID]
    if tombstone and type(tombstone.at) == "number" and time() - tombstone.at > DRAIN_MAX_SECONDS then
      -- The lost answer this fence was guarding against is too old to still arrive -- see
      -- DRAIN_MAX_SECONDS. Lift it and ask for real instead of wedging in "draining".
      refresh.drain[kind .. ":" .. itemID] = nil
      tombstone = nil
    end
    if tombstone then
      tombstone.resumeGeneration = refresh.generation
      refresh.phase = "draining"
      setStatus("Refresh waiting for prior result")
      return
    end
    refresh.awaiting = nil
    refresh.index = refresh.index + 1
    refresh.pending = { itemID = itemID, kind = kind, generation = refresh.generation, at = time() }
    refresh.phase = "waiting_result"
    markProgress()
    setStatus(("Pricing %d/%d…"):format(refresh.index, #refresh.queue))
    driver.send(itemID)
    scheduleQuoteTimeout(refresh.pending)
  else
    refresh.awaiting, refresh.phase = itemID, "waiting_key"
  end
end

local function beginQuoteWalk()
  refresh.queue, refresh.index, refresh.phase, refresh.pending, refresh.awaiting = uniqueQuoteItemIDs(), 0, "pricing", nil, nil
  refresh.skipped = 0
  refresh.waitingNoted = false
  if #refresh.queue == 0 then return finishQuoteWalk() end
  advanceQuote()
end

local function requestOwnedAuctions()
  if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions and GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen() then
    if not driver.isReady() then return false, true end
    C_AuctionHouse.QueryOwnedAuctions({})
    return true, false
  end
  return false, false
end

local function onOwnedAuctionsReady()
  markProgress()
  composePositions()
  renderRows()
  if refresh.phase == "owned" then
    beginQuoteWalk()
  end
end

-- GetOwnedAuctions does not report whether an auction is a commodity, so keyForLot saw
-- isCommodity = nil and filed every owned lot under an item-style key built from itemKey's
-- item level. A commodity bought as `commodity:12363` therefore listed itself as
-- `item:12363:10:0:0`: two positions for one item, the purchase holding no listings and the
-- listing holding no cost. On screen that read as "x5 in your bags, not listed" while the
-- Blizzard auctions panel showed those same five on sale.
--
-- GetItemKeyInfo is the authority on that flag -- the quote driver above already relies on it --
-- so classify here, where the API is reachable, and leave NormalizeOwnedLots pure.
local function classifyOwnedAuctions(auctions)
  if not (C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo) then return auctions end
  for _, auction in ipairs(auctions or {}) do
    if auction.isCommodity == nil and auction.itemKey then
      local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, auction.itemKey)
      if ok and type(info) == "table" and info.isCommodity ~= nil then
        auction.isCommodity = info.isCommodity
      end
    end
  end
  return auctions
end

function GC.Sell.OnOwnedAuctions()
  local auctions = C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and C_AuctionHouse.GetOwnedAuctions() or {}
  ownedLots = GC.SellPositions.NormalizeOwnedLots(classifyOwnedAuctions(auctions), time())
  local scope = context()
  if GC.Acquisitions and GC.Acquisitions.ObserveOwnedPosition and scope then
    for _, lot in ipairs(ownedLots) do
      GC.Acquisitions.ObserveOwnedPosition(lot.positionKey, lot.itemID, itemName(lot.itemID), scope.char, scope.region, time())
    end
    -- Pure composition is allowed to display a currently unique variant, but
    -- it must never make that inference durable.  The controller has the
    -- current owned-lot evidence and has just persisted matching activity, so
    -- it may ask the explicit fail-closed binding API to bind an item-only
    -- legacy batch only when every candidate and activity agrees on one key.
    if GC.Acquisitions.BindItemOnly and GC.Acquisitions.GetActive then
      for _, batch in ipairs(GC.Acquisitions.GetActive(scope)) do
        if not batch.positionKey then
          local candidates = {}
          for _, lot in ipairs(ownedLots) do
            if lot.itemID == batch.itemID then
              candidates[#candidates + 1] = { positionKey = lot.positionKey, itemID = lot.itemID,
                character = scope.char, region = scope.region }
            end
          end
          if #candidates > 0 then GC.Acquisitions.BindItemOnly(batch.id, candidates, scope) end
        end
      end
    end
  end
  if repostingRow and repostPin then
    local pinnedScope, scopeKey = activeScope(repostPin.position)
    local stillOwned = pinnedScope and scopeKey == repostPin.scopeKey
    if stillOwned then
      stillOwned = false
      for _, lot in ipairs(ownedLots) do
        if lot.positionKey == repostPin.positionKey and lot.itemID == repostPin.itemID
            and lot.auctionID == repostPin.auctionID and lot.quantity == repostPin.quantity
            and lot.unitPrice == repostPin.listedUnit then
          stillOwned = true
          break
        end
      end
    end
    if not stillOwned then
      disarmRepost()
      setStatus("Lot cancelled; wait for it to return to bags")
    end
  end
  onOwnedAuctionsReady()
end

function GC.Sell.OnThrottleReady()
  if refresh.phase == "waiting_owned" then
    local sent, waiting = requestOwnedAuctions()
    if sent then
      refresh.phase = "owned"
    elseif not waiting then
      refresh.phase = "idle"
      setStatus("Auction House is not open")
    end
    return
  end
  if refresh.pending and time() - refresh.pending.at > QUOTE_STALE_SECONDS then
    skipPendingQuote(refresh.pending, true)
    return
  end
  advanceQuote()
end

function GC.Sell.OnItemKeyInfo(itemID)
  if refresh.phase == "waiting_key" and refresh.awaiting == itemID then advanceQuote() end
end

local function quoteResolved(kind, itemID, unit, levels)
  local drainKey = kind .. ":" .. itemID
  local tombstone = refresh.drain[drainKey]
  if tombstone then
    tombstone.terminals = tombstone.terminals - 1
    local resume = tombstone.terminals <= 0 and tombstone.resumeGeneration == refresh.generation
      and refresh.phase == "draining"
    if tombstone.terminals <= 0 then refresh.drain[drainKey] = nil end
    if resume then
      refresh.phase = "pricing"
      advanceQuote()
    elseif refresh.phase == "error" then
      refresh.phase = "idle"
    end
    return
  end
  local pending = refresh.pending
  if not pending or pending.kind ~= kind or pending.itemID ~= itemID or pending.generation ~= refresh.generation then return end
  if not exact(unit) or unit <= 0 then
    skipPendingQuote(pending, false)
    return
  end
  refresh.pending = nil
  refresh.phase = "pricing"
  markProgress()
  emptyAnswers[itemID] = nil -- a real price supersedes any remembered "nothing listed"
  GC.QuoteCache.Set(quotes, itemID, unit, time())
  -- Mirror the result into the persisted store: whatever Set just did to `quotes[itemID]` --
  -- write it in (it never clears here, since `unit` is already known-valid above, but the
  -- contract matches Set's either way) so a later reload can seed from it.
  local persisted = persistedQuotes()
  if persisted then
    local resolved = quotes[itemID]
    persisted[itemID] = resolved and { unit = resolved.unit, at = resolved.at } or nil
  end
  if unit and quotes[itemID] then quotes[itemID].levels = levels end
  -- Carry what this walk just saw out of the game (live-prices spec).
  -- Summarize gives the TRUE floor; `unit` here is the competing-not-own
  -- price and must not masquerade as the book minimum. Guarded like every
  -- other cross-module call in this file: specs load only the modules a
  -- given test needs, so GC.Book/GC.Data may be absent outside the client.
  local summary = GC.Book and GC.Book.Summarize(levels)
  if summary and GC.Data and GC.Data.RecordLiveObservation then
    local scope = context()
    GC.Data.RecordLiveObservation(GC.db, { itemID = itemID,
      region = scope and scope.region, minUnit = summary.minUnit,
      listings = summary.listings, totalQty = summary.totalQty,
      levels = levels }, time())
  end
  composePositions()
  renderRows()
  advanceQuote()
end

function GC.Sell.OnItemSearchResults(itemID) quoteResolved("item", itemID, driver.item(itemID), driver.itemLevels(itemID)) end
function GC.Sell.OnCommoditySearchResults(itemID) quoteResolved("commodity", itemID, driver.commodity(itemID), driver.commodityLevels(itemID)) end

local function freshQuote(position)
  local quote = GC.QuoteCache.Fresh(quotes, position.itemID, time(), SELL_QUOTE_ACTION_AGE)
  if type(quote) ~= "table" or not exact(quote.unit) or quote.unit <= 0 or not exact(quote.at) then return nil end
  return quote
end

local function normalizedPositionKey(itemID, link)
  if type(link) ~= "string" or link:find("battlepet:", 1, true) then return nil end
  local payload = link:match("|H(item:[^|]+)|h") or link:match("^(item:.-)$")
  if not payload then return nil end
  local fields, start = {}, 1
  while true do
    local colon = payload:find(":", start, true)
    if not colon then fields[#fields + 1] = payload:sub(start); break end
    fields[#fields + 1], start = payload:sub(start, colon - 1), colon + 1
  end
  local actualID = tonumber(fields[2])
  if actualID ~= itemID then return nil end
  local bonusCount = tonumber(fields[14])
  if #fields < 14 or bonusCount == nil or bonusCount ~= 0 then return nil end
  local level = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
  local suffix = tonumber(fields[8])
  if type(level) ~= "number" or suffix == nil then return nil end
  return ("item:%d:%d:%d:%d"):format(itemID, math.floor(level), suffix, 0)
end

-- Whether an item sells as a commodity decides its whole auction identity, and
-- GetItemKeyInfo is the only authority on it -- but it is only reachable while
-- the auction house is open, and the Sell tab is useful standing anywhere. So
-- the answer is remembered in SavedVariables the first time it is learned, and
-- an item nobody has ever classified is left out rather than filed under a
-- guessed key. Guessing is what split one item into two positions before.
local function commodityKindCache()
  if GC.db then
    GC.db.commodityByItem = type(GC.db.commodityByItem) == "table" and GC.db.commodityByItem or {}
    return GC.db.commodityByItem
  end
  return sessionCommodityKind
end

local function classifyBagItem(itemID, link)
  local cache = commodityKindCache()
  local isCommodity = cache[itemID]
  if isCommodity == nil and C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.MakeItemKey then
    local ok, info = pcall(function() return C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID)) end)
    if ok and type(info) == "table" and info.isCommodity ~= nil then
      isCommodity = info.isCommodity == true
      cache[itemID] = isCommodity
    end
  end
  if isCommodity == true then return ("commodity:%d"):format(itemID), true end
  if isCommodity == false then return normalizedPositionKey(itemID, link), false end
  return nil, nil
end

scanBagStock = function()
  if not GC.BagStock then bagStock = {} return end
  bagStock = GC.BagStock.Scan({
    numSlots = function(bag)
      return C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    end,
    itemInfo = function(bag, slot)
      if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if type(info) ~= "table" then return nil end
      return {
        itemID = info.itemID, stackCount = info.stackCount, isBound = info.isBound,
        hasNoValue = info.hasNoValue, itemName = info.itemName,
        hyperlink = info.hyperlink
          or (C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or nil,
      }
    end,
    classify = classifyBagItem,
  }, SELL_BAGS)
end

local function liveBagState(position, requiredQty)
  local total, matchedBag, matchedSlot, matchedStack = 0, nil, nil, nil
  local commodity = type(position.positionKey) == "string" and position.positionKey:match("^commodity:")
  for _, bag in ipairs(SELL_BAGS) do
    local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == position.itemID then
        local qty = info.stackCount or 1
        if exact(qty) and qty > 0 and commodity then
          total = safeAdd(total, qty)
          if not total then return { itemID = position.itemID, exactQty = nil } end
          if not matchedBag then matchedBag, matchedSlot, matchedStack = bag, slot, qty end
        else
          local link = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
          if exact(qty) and qty > 0 and normalizedPositionKey(position.itemID, link) == position.positionKey then
            if qty > total then total = qty end
            if (requiredQty and qty >= requiredQty and not matchedBag) or (not requiredQty and qty >= (matchedStack or 0)) then
              matchedBag, matchedSlot, matchedStack = bag, slot, qty
            end
          end
        end
      end
    end
  end
  return { itemID = position.itemID, exactQty = total, positionKey = matchedBag and position.positionKey or nil,
    bag = matchedBag, slot = matchedSlot, stackQty = matchedStack }
end

-- Post and Repost both need a quote fresher than they have. This used to call
-- the full Refresh, which re-queried the owned auctions and then every priced
-- item in the tab, one throttled round trip at a time -- so the "press it again
-- in a moment" the button promised could be a minute away, by which point the
-- quote for THIS item had aged out again and the next click started another
-- walk. That loop is why Post could not be pressed at all.
--
-- One item, one query. If a walk is already running the item is spliced in as
-- its next step rather than restarting anything.
local function startQuoteRefreshFor(position)
  local itemID = type(position) == "table" and position.itemID or nil
  if not itemID then return GC.Sell.Refresh() end
  if not (GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen()) then
    setStatus("Auction House is not open")
    return
  end
  if refresh.phase == "idle" or refresh.phase == "done" or refresh.phase == "error" then
    refresh.generation = refresh.generation + 1
    refresh.queue, refresh.index = { itemID }, 0
    refresh.pending, refresh.awaiting = nil, nil
    refresh.phase = "pricing"
    setStatus("Checking this item's price…")
    advanceQuote()
  else
    table.insert(refresh.queue, math.min(refresh.index + 1, #refresh.queue + 1), itemID)
    setStatus("Checking this item's price…")
  end
end

local function currentPosition(positionKey)
  for _, position in ipairs(positions) do
    if position.positionKey == positionKey then return position end
  end
  return nil
end

local function schedulePostTimeout(row)
  if not (C_Timer and C_Timer.After) then return end
  postTimeoutToken = (postTimeoutToken or 0) + 1
  local token = postTimeoutToken
  C_Timer.After(POST_TIMEOUT_SECONDS, function()
    if token == postTimeoutToken and postingRow == row
        and (row.postStage == "posting" or row.postStage == "confirm" or row.postStage == "confirming") then
      disarmPost()
      setStatus("Posting timed out")
    end
  end)
end

local function onPostClick(row)
  local position = row.position
  local quote = freshQuote(position)
  if not quote then
    if postingRow == row then disarmPost() end
    -- Same silent first click as Repost had: without this the button looks
    -- broken. The status line alone is not enough -- it sits in the Sniper's
    -- toolbar, a window's width from the button that was just pressed -- so the
    -- button says it too. The next render restores the label once the price
    -- lands, which is one query away now rather than a whole pass.
    if row.action then row.action:SetLabel("Pricing…") end
    setStatus("Fetching a fresh price for this item — press Post again in a moment")
    startQuoteRefreshFor(position); return
  end
  if postingRow and postingRow ~= row then
    setStatus("Finish the pending post first")
    return
  end
  if postingRow == row and row.postStage ~= "confirm" then return end
  if row.postStage == "confirm" then
    local pin = postingPin
    local scope, scopeKey = activeScope(position)
    local bagState = pin and liveBagState(position, pin.isCommodity and nil or pin.quantity) or nil
    local sameQuote = pin and quote == pin.quote and quote.at == pin.quoteAt and quote.unit == pin.quoteUnit
    local checkedTotal = pin and safeMultiply(pin.unitPrice, pin.quantity) or nil
    local confirmAvailable = pin and C_AuctionHouse
      and ((pin.isCommodity and C_AuctionHouse.ConfirmPostCommodity)
        or (not pin.isCommodity and C_AuctionHouse.ConfirmPostItem))
    if not exactRenderEntry(row, pin) or not scope or scopeKey ~= pin.scopeKey
        or pin.positionKey ~= position.positionKey or pin.scopeKey ~= position.scopeKey
        or pin.itemID ~= position.itemID or pin.variantKey ~= position.positionKey
        or not exact(pin.quantity) or pin.quantity <= 0 or not exact(pin.unitPrice) or pin.unitPrice <= 0
        or not pin.location or not bagState or bagState.itemID ~= pin.itemID
        or bagState.positionKey ~= pin.variantKey or bagState.bag ~= pin.bag or bagState.slot ~= pin.slot
        or not exact(bagState.exactQty) or bagState.exactQty < pin.quantity
        or not checkedTotal or checkedTotal ~= pin.total
        or (not pin.isCommodity and pin.buyout ~= checkedTotal)
        or not sameQuote or not confirmAvailable
        or (pin.duration ~= 1 and pin.duration ~= 2 and pin.duration ~= 3) then
      disarmPost()
      if not sameQuote then startQuoteRefreshFor(position)
      else setStatus("Post confirmation expired") end
      return
    end
    row.postStage = "confirming"; row.action:Disable(); setStatus("Posting…")
    if pin.isCommodity then
      C_AuctionHouse.ConfirmPostCommodity(pin.location, pin.duration, pin.quantity, pin.unitPrice)
    else
      C_AuctionHouse.ConfirmPostItem(pin.location, pin.duration, pin.quantity, nil, pin.buyout)
    end
    return
  end
  local bagState = liveBagState(position)
  local plan, reason = GC.SellPositions.BuildPostPlan(position, bagState, { unit = quote.unit, fresh = true })
  if not plan then
    setStatus(reason == "ambiguous_variant" and "No exact bag variant" or "Cannot post this position")
    return
  end
  local scope, scopeKey = activeScope(position)
  if not scope or type(row.renderEntryID) ~= "string" or row.renderEntryID == ""
      or plan.positionKey ~= position.positionKey or plan.scopeKey ~= position.scopeKey
      or plan.scopeKey ~= scopeKey or plan.itemID ~= position.itemID
      or not exact(plan.quantity) or plan.quantity <= 0 or not exact(plan.unitPrice) or plan.unitPrice <= 0 then
    setStatus("Cannot post this position")
    return
  end
  local info = driver.keyInfo(plan.itemID)
  if not info then setStatus("No exact auction key"); return end
  if (info.isCommodity and not (C_AuctionHouse and C_AuctionHouse.PostCommodity))
      or (not info.isCommodity and not (C_AuctionHouse and C_AuctionHouse.PostItem)) then
    setStatus("Posting unavailable")
    return
  end
  local buyout = not info.isCommodity and safeMultiply(plan.unitPrice, plan.quantity) or nil
  if not info.isCommodity and not buyout then setStatus("Cannot post this position"); return end
  local commodityTotal = info.isCommodity and safeMultiply(plan.unitPrice, plan.quantity) or nil
  if info.isCommodity and (not commodityTotal or not exact(bagState.exactQty) or bagState.exactQty < plan.quantity) then
    setStatus("No exact bag stack")
    return
  end
  if not ItemLocation or not ItemLocation.CreateFromBagAndSlot or not bagState.bag or not bagState.slot then
    setStatus("No exact bag stack")
    return
  end
  if not info.isCommodity then
    bagState = liveBagState(position, plan.quantity)
    if not bagState.bag or not bagState.slot or not bagState.stackQty or bagState.stackQty < plan.quantity then
      setStatus("No exact bag stack")
      return
    end
  end
  local location = ItemLocation:CreateFromBagAndSlot(bagState.bag, bagState.slot)
  if not location then setStatus("No exact bag stack"); return end
  postingRow = row
  -- Pinned once, here, rather than re-read at Confirm time: everything else about a post is
  -- pinned the same way (unitPrice, quantity, ...) precisely so the two clicks of a two-click
  -- post cannot disagree about what they are doing. A duration changed in the settings panel
  -- between the two clicks must not let a post start at one duration and confirm at another.
  local duration = postDuration()
  postingPin = { scopeKey = plan.scopeKey, positionKey = plan.positionKey, itemID = plan.itemID,
    variantKey = bagState.positionKey, quantity = plan.quantity, bag = bagState.bag, slot = bagState.slot,
    quoteAt = quote.at, quoteUnit = quote.unit, quote = quote, location = location, isCommodity = info.isCommodity,
    unitPrice = plan.unitPrice, buyout = buyout, total = commodityTotal or buyout, row = row, action = row.action,
    position = position, renderEntryID = row.renderEntryID, character = scope.char, region = scope.region,
    duration = duration }
  row.postStage = "posting"; row.action:Disable(); setStatus("Posting…")
  local needsConfirmation
  if info.isCommodity then
    needsConfirmation = C_AuctionHouse.PostCommodity(location, duration, plan.quantity, plan.unitPrice)
  else
    needsConfirmation = C_AuctionHouse.PostItem(location, duration, plan.quantity, nil, buyout)
  end
  if needsConfirmation then
    row.postStage = "confirm"; row.action:Enable(); row.action:SetLabel("Confirm")
    setStatus("Click Confirm to post")
  end
  schedulePostTimeout(row)
end

local function onRepostClick(row, auctionID)
  local position = row.position
  if repostingRow and repostingRow ~= row then
    disarmRepost()
    setStatus("Previous repost selection cleared")
    return
  end
  local quote = freshQuote(position)
  if not quote then
    if repostingRow == row then disarmRepost() end
    -- Previously this refreshed the quote and returned in silence, so a first click looked like
    -- a dead button. Say what is happening; the click that follows is the one that arms.
    setStatus("Fetching a fresh price for this lot — press Repost again in a moment")
    startQuoteRefreshFor(position); return
  end
  if row.repostStage == "armed" then
    if not row.repostReady then return end
    local pin = repostPin
    if not exactRenderEntry(row, pin) then
      disarmRepost()
      setStatus("Repost confirmation expired")
      return
    end
    local scope, scopeKey = pin and activeScope(pin.position) or nil, nil
    if scope then
      if GC.Acquisitions and GC.Acquisitions.ScopeKey then
        scopeKey = GC.Acquisitions.ScopeKey(pin.positionKey, scope)
      else
        scopeKey = table.concat({ scope.region, scope.char, pin.positionKey }, "\1")
      end
    end
    if not (C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and GC.SellPositions.NormalizeOwnedLots) then
      disarmRepost()
      setStatus("Repost confirmation expired")
      return
    end
    ownedLots = GC.SellPositions.NormalizeOwnedLots(
      classifyOwnedAuctions(C_AuctionHouse.GetOwnedAuctions() or {}), time())
    composePositions()
    local livePosition = currentPosition(pin.positionKey)
    local current
    for _, candidate in ipairs(livePosition and livePosition.scopeKey == pin.scopeKey
        and livePosition.itemID == pin.itemID and livePosition.ownedLots or {}) do
      if candidate.auctionID == pin.auctionID and candidate.quantity == pin.quantity and candidate.unitPrice == pin.listedUnit then current = candidate break end
    end
    local plan = current and GC.SellPositions.BuildRepostPlan(livePosition, pin.auctionID, { unit = quote.unit, fresh = true })
    if not exactRenderEntry(row, pin) or not scope or scopeKey ~= pin.scopeKey
        or pin.position ~= position or pin.positionKey ~= position.positionKey
        or pin.scopeKey ~= position.scopeKey or pin.itemID ~= position.itemID
        or not plan or plan.positionKey ~= pin.positionKey or plan.scopeKey ~= pin.scopeKey
        or plan.itemID ~= pin.itemID or plan.auctionID ~= pin.auctionID
        or plan.quantity ~= pin.quantity or plan.unitPrice ~= pin.quoteUnit
        or quote ~= pin.quote or quote.at ~= pin.quoteAt or quote.unit ~= pin.quoteUnit
        or not (C_AuctionHouse and C_AuctionHouse.CancelAuction) then
      disarmRepost()
      setStatus("Repost confirmation expired")
      return
    end
    row.repostStage = "cancelling"; row.action:Disable()
    C_AuctionHouse.CancelAuction(plan.auctionID)
    setStatus("Cancelling lot…")
    if C_Timer and C_Timer.After then
      local token = repostArmToken
      C_Timer.After(REPOST_TIMEOUT_SECONDS, function()
        if token == repostArmToken and repostingRow == row and row.repostStage == "cancelling" then
          disarmRepost()
          setStatus("Cancel timed out")
        end
      end)
    end
    return
  end
  local plan = GC.SellPositions.BuildRepostPlan(position, auctionID, { unit = quote.unit, fresh = true })
  local scope, scopeKey = activeScope(position)
  if not plan or not scope or type(row.renderEntryID) ~= "string" or row.renderEntryID == ""
      or plan.positionKey ~= position.positionKey or plan.scopeKey ~= position.scopeKey
      or plan.scopeKey ~= scopeKey or plan.itemID ~= position.itemID
      or not exact(plan.auctionID) or plan.auctionID <= 0 or plan.auctionID ~= auctionID
      or not exact(plan.quantity) or plan.quantity <= 0
      or not exact(plan.unitPrice) or plan.unitPrice <= 0 then
    setStatus("Cannot repost this lot")
    return
  end
  local lot
  for _, candidate in ipairs(position.ownedLots or {}) do if candidate.auctionID == plan.auctionID then lot = candidate break end end
  if not lot or lot.quantity ~= plan.quantity or not exact(lot.unitPrice) or lot.unitPrice <= 0 then
    setStatus("Cannot repost this lot")
    return
  end
  repostingRow, repostPin = row, { scopeKey = plan.scopeKey, positionKey = plan.positionKey, auctionID = plan.auctionID,
    itemID = plan.itemID, quantity = plan.quantity, listedUnit = lot.unitPrice,
    quoteAt = quote.at, quoteUnit = quote.unit, quote = quote, row = row, action = row.action,
    position = position, renderEntryID = row.renderEntryID, character = scope.char, region = scope.region }
  row.repostStage, row.repostReady = "armed", false
  row.action:Disable(); row.action:SetLabel("Cancel lot?")
  setStatus("Cancel this lot and lose its deposit — click again to confirm")
  repostArmToken = repostArmToken + 1
  local token = repostArmToken
  if C_Timer and C_Timer.After then
    C_Timer.After(REPOST_ARM_SECONDS, function()
      if token == repostArmToken and repostingRow == row and row.repostStage == "armed" then
        row.repostReady = true; row.action:Enable()
        -- The cancel control mirrors this arm (see paintCancelButton); without this repaint it
        -- would stay disabled after the delay even though the row's own button just enabled.
        paintCancelButton()
      end
    end)
    C_Timer.After(REPOST_TIMEOUT_SECONDS, function()
      if token == repostArmToken and repostingRow == row and row.repostStage == "armed" then
        disarmRepost()
        setStatus("Repost confirmation expired")
      end
    end)
  end
end

-- The "What you paid" affordance for a hand-entered cost: a mistaken "Set cost" entry used to
-- have no way back out short of raw SavedVariables surgery. Mirrors onRepostClick's arm/confirm
-- shape (first click arms with explicit text, a second click within the window executes) but
-- without its deposit-guard forced delay -- there is no deposit here to protect against a fast
-- double-click, only a typo to walk back.
--
-- `row.batch.ids` is however many acquisition batch ids this row stands for -- one for a lone
-- purchase, several for a collapsed run (SellViewModel.Expansion). Every id in the list shares
-- one source, because that is one of Expansion's own collapse keys, so the button only ever
-- appears when the whole run is manual and removes the whole run when confirmed.
local function onRemoveClick(row)
  if removingRow and removingRow ~= row then
    disarmRemove()
    setStatus("Previous removal selection cleared")
    return
  end
  if row.removeStage == "armed" then
    local pin = removePin
    if not exactRenderEntry(row, pin) then
      disarmRemove()
      setStatus("Removal confirmation expired")
      return
    end
    local removed = 0
    for _, id in ipairs(pin.ids) do
      if GC.Acquisitions.RemoveManual(id) then removed = removed + 1 end
    end
    disarmRemove()
    setStatus(removed > 0
      and (removed > 1 and ("Removed %d entries"):format(removed) or "Removed")
      or "Nothing to remove")
    GC.Sell.Refresh()
    return
  end
  if postingRow or repostingRow then
    setStatus("Finish the pending post or repost first")
    return
  end
  local ids = row.batch and row.batch.ids
  if type(ids) ~= "table" or #ids == 0 or type(row.renderEntryID) ~= "string" or row.renderEntryID == "" then
    setStatus("Cannot remove this entry")
    return
  end
  removingRow, removePin = row, { ids = ids, row = row, action = row.action,
    position = row.position, renderEntryID = row.renderEntryID }
  row.removeStage = "armed"
  row.action:SetLabel("Remove?")
  setStatus(#ids > 1
    and "Removes every entered-by-hand purchase in this run -- click again to confirm"
    or "Removes this entered-by-hand purchase -- click again to confirm")
  removeArmToken = removeArmToken + 1
  local token = removeArmToken
  if C_Timer and C_Timer.After then
    C_Timer.After(REMOVE_TIMEOUT_SECONDS, function()
      if token == removeArmToken and removingRow == row and row.removeStage == "armed" then
        disarmRemove()
        setStatus("Removal confirmation expired")
      end
    end)
  end
end

function GC.Sell.OnAuctionCreated()
  local pin, row = postingPin, postingRow
  if not pin or not row then return end
  local valid = exactRenderEntry(row, pin) and (row.postStage == "posting" or row.postStage == "confirming")
    and pin.positionKey == row.position.positionKey and pin.scopeKey == row.position.scopeKey
    and pin.itemID == row.position.itemID and exact(pin.quantity) and pin.quantity > 0
    and exact(pin.total) and pin.total > 0 and type(pin.character) == "string" and pin.character ~= ""
    and type(pin.region) == "string" and pin.region ~= ""
  if valid and GC.Acquisitions and GC.Acquisitions.RecordPost then
    GC.Acquisitions.RecordPost(pin.positionKey, pin.itemID, itemName(pin.itemID), pin.character, pin.region, pin.quantity, time())
  end
  disarmPost()
  GC.Sell.Refresh()
end

function GC.Sell.OnPostError()
  disarmPost()
  disarmRepost()
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

local function dialogExactPositive(edit)
  local value = dialogNumber(edit)
  return exact(value) and value > 0 and value or nil
end

local COPPER_PER_GOLD = 10000

-- The Unit/Total cost fields are GOLD, explicitly -- see the field labels in Attach below.
-- A player typing "250" means 250 gold, and used to be recorded as 250 COPPER with no unit
-- shown anywhere; that number then drove cost basis, profit and the below-cost warning
-- forever. This is the one place that boundary is crossed, and it is crossed the same way
-- GetCoinTextureString's own rounding implies: round to the nearest copper, never truncate.
local function dialogGoldCopper(edit)
  local value = tonumber(edit:GetText())
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then
    return nil
  end
  local copper = math.floor(value * COPPER_PER_GOLD + 0.5)
  return exact(copper) and copper or nil
end

local function dialogGoldPositive(edit)
  local copper = dialogGoldCopper(edit)
  return copper and copper > 0 and copper or nil
end

-- Exact copper -> a decimal gold string with no trailing noise ("2.5", never "2.5000"), so
-- the Unit/Total fields can keep syncing each other in the same units the player types in.
-- Copper is always an integer count of 1/10000 gold, so this round-trips exactly -- no
-- floating point is involved in this direction, only integer division and remainder.
local function copperToGoldText(copper)
  if not exact(copper) then return "" end
  local whole = math.floor(copper / COPPER_PER_GOLD)
  local remainder = copper - whole * COPPER_PER_GOLD
  if remainder == 0 then return tostring(whole) end
  local text = ("%d.%04d"):format(whole, remainder)
  text = (text:gsub("0+$", ""))
  text = (text:gsub("%.$", ""))
  return text
end

-- The live "what this will actually record" readout under the Total field. Typing "12.5" is
-- ambiguous on its own -- seeing "12g 50s 0c" appear while typing is what makes the unit
-- unambiguous no matter what the player assumed it was.
local function updateTotalPreview(dialog, copper)
  local preview = dialog.totalPreview
  if not preview then return end
  preview:SetText(exact(copper) and copper > 0 and GetCoinTextureString(copper) or "")
end

local function pendingRepairFor(position, scope)
  local pending = position and position.pendingAcquisitions
  if type(pending) ~= "table" or #pending ~= 1 or type(scope) ~= "table" then return nil end
  local row = pending[1]
  if type(row) ~= "table" or type(row.id) ~= "string" or row.id == ""
      or row.itemID ~= position.itemID or row.positionKey ~= position.positionKey
      or row.character ~= scope.char or row.region ~= scope.region
      or not exact(row.quantity) or row.quantity <= 0 then
    return nil
  end
  return row
end

-- How many units the player is holding that GoldCap cannot put a cost against.
--
-- This used to be `exposureQty - knownQty`, and exposureQty counts tracked
-- purchases and live listings -- it knows nothing about the bags. For anything
-- GoldCap never bought that difference is zero, so Set cost returned before it
-- showed the dialog and the button was simply dead. Bag stock is exactly the
-- case the tab now exists to serve, and it is also the case most likely to need
-- a cost typed in by hand.
--
-- Held = what is listed plus what is in the bags, or the accounting exposure,
-- whichever is larger. The two disagree while an observation lags, and the
-- larger is the safe one here: offering to cost a unit that turns out not to
-- exist is a correctable mistake, refusing to cost one that does is the bug.
--
-- knownQty is FIFO allocation against exposureQty, and exposureQty is capped
-- at listedQty once a lot is listed (decoratePosition, SellPositions.lua) --
-- so allocation can stop well short of what is actually on record. trackedQty
-- is the sum of every batch's remainingQty regardless of that cap, so a unit
-- a recorded batch covers but allocation hasn't reached yet is costed even
-- when knownQty says otherwise. Comparing against max(knownQty, trackedQty)
-- reads what is recorded, not just what allocation reached: a live incident
-- had 24 listed capping allocation at 24 while a batch actually covered 118,
-- and the dialog offering to cost the "difference" let the player double it.
local function uncostedQty(position)
  if type(position) ~= "table" then return 0 end
  local physical = (position.listedQty or 0) + (position.bagQty or 0)
  local held = math.max(position.exposureQty or 0, physical)
  return math.max(0, held - math.max(position.knownQty or 0, position.trackedQty or 0))
end

local function canSetCost(position)
  if not position or position.unresolved or type(position.positionKey) ~= "string" then return false end
  -- Not offered where it would do nothing. A button that opens no dialog is
  -- indistinguishable from a broken one, which is how this defect presented.
  if uncostedQty(position) < 1 then return false end
  local pending = position.pendingAcquisitions
  if type(pending) ~= "table" or #pending == 0 then return true end
  local scope = activeScope(position)
  return pendingRepairFor(position, scope) ~= nil
end

local function openCostDialog(position)
  local dialog = container.costDialog
  local missing = uncostedQty(position)
  if missing < 1 then return end
  local scope = activeScope(position)
  local pending = pendingRepairFor(position, scope)
  if type(position.pendingAcquisitions) == "table" and #position.pendingAcquisitions > 0 and not pending then return end
  if pending then missing = math.min(missing, pending.quantity) end
  dialog.position, dialog.maximum, dialog.pendingRepair = position, missing, pending
  manualRepairNonce = manualRepairNonce + 1
  dialog.repairID = pending and table.concat({ "manual-repair", pending.id, tostring(time()),
    tostring(manualRepairNonce) }, "\1") or nil
  dialog.submitted, dialog.costMode, dialog.syncing = false, nil, false
  -- Which item, and how many of its units have no cost -- the two facts a player needs
  -- before touching any of the numbers below. The dialog used to be anonymous: nothing on
  -- it said which of several open positions it belonged to.
  dialog.header:SetText(("%s — %d unit%s without a cost"):format(
    position.itemName or "Item", missing, missing == 1 and "" or "s"))
  -- Defaults to the full uncosted count, not "1" -- entering a cost for stock GoldCap never
  -- saw the player buy is the ordinary case this dialog exists for, and "1" made the player
  -- retype the real quantity every single time.
  dialog.quantity:SetText(tostring(missing))
  dialog.unit:SetText("")
  dialog.total:SetText("")
  updateTotalPreview(dialog, nil)
  setDialogError(dialog)
  dialog:Show()
end

local function confirmCostDialog(dialog)
  if dialog.submitted then return end
  -- Quantity is a whole unit count; Unit/Total are gold, converted to exact copper here --
  -- the same conversion the live preview already showed, so what gets recorded is never a
  -- surprise. Everything from here down is copper, exactly as it always was.
  local quantity, total = dialogExactPositive(dialog.quantity), dialogGoldPositive(dialog.total)
  if not quantity or quantity < 1 then return setDialogError(dialog, "Enter a whole quantity") end
  if quantity > dialog.maximum then return setDialogError(dialog, "Quantity exceeds missing units") end
  if not total then return setDialogError(dialog, "Enter an exact positive cost") end
  if dialog.costMode == "unit" then
    local unit = dialogGoldPositive(dialog.unit)
    if not unit or safeMultiply(quantity, unit) ~= total then
      return setDialogError(dialog, "Enter an exact positive cost")
    end
  elseif dialog.costMode ~= "total" then
    return setDialogError(dialog, "Enter an exact positive cost")
  end
  local position = dialog.position
  local scope = activeScope(position)
  if not scope then return setDialogError(dialog, "Position scope changed") end
  local batch
  if dialog.pendingRepair then
    local pending = pendingRepairFor(position, scope)
    if not pending or pending.id ~= dialog.pendingRepair.id or not dialog.repairID
        or not (GC.Acquisitions and GC.Acquisitions.RepairPendingManual) then
      return setDialogError(dialog, "Position scope changed")
    end
    batch = GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = dialog.repairID,
      itemID = position.itemID, positionKey = position.positionKey, itemName = position.itemName,
      quantity = quantity, total = total, acquiredAt = time(), character = scope.char, region = scope.region })
  else
    batch = GC.Acquisitions.RecordManual({ itemID = position.itemID, positionKey = position.positionKey,
      itemName = position.itemName, quantity = quantity, total = total, acquiredAt = time(),
      character = scope.char, region = scope.region })
  end
  if batch then dialog.submitted = true; dialog:Hide(); GC.Sell.Refresh() else setDialogError(dialog, "Enter an exact positive cost") end
end

-- The item name is the one column that must stay readable: every other cell is a number that
-- also lives in the tooltip or the expansion, but a row whose name is "Aze..." is useless.
-- `min` on the flex column was declared and never honoured, so the name silently collapsed to
-- nothing as soon as the fixed columns outgrew the window. Shed load-bearing weight in order
-- instead: the listed total (already in the summary), then squeeze the advice text, then drop
-- it entirely (the action button carries the same guidance on its tooltip), and only then the
-- cost per unit (which the expansion spells out per purchase).
local ITEM_MIN = 200
local STATUS_MIN = 110
local columnWidth = {}

local function shownColumns()
  local width = ROW_WIDTH or 0
  local dropped = {}
  columnWidth = {}

  local function remaining()
    local total = 0
    for _, column in ipairs(COLUMNS) do
      if not column.flex and not dropped[column.key] then
        total = total + (columnWidth[column.key] or column.w) + 2
      end
    end
    return width - total
  end

  if width > 0 then
    if remaining() < ITEM_MIN then dropped.listed = true end
    if remaining() < ITEM_MIN then columnWidth.status = STATUS_MIN end
    if remaining() < ITEM_MIN then dropped.status = true; columnWidth.status = nil end
    if remaining() < ITEM_MIN then dropped.cost = true end
  end

  local shown = {}
  for _, column in ipairs(COLUMNS) do
    if not dropped[column.key] then shown[#shown + 1] = column end
  end
  return shown, dropped
end

local function layoutCells(row)
  local right = row
  local cols, dropped = shownColumns()
  for i = #cols, 1, -1 do
    local column, cell = cols[i], row.cells[cols[i].key]
    cell:ClearAllPoints()
    if column.flex then
      -- row.itemInset leaves room for the icon on a position row, and indents a child row so
      -- the hierarchy is carried by layout instead of by leading spaces in the string. The box
      -- this defines is shared by three mutually exclusive widgets -- this cell (a position),
      -- row.subItem (a detail/batch/lot/listing sub-row) and row.sectionLabel (a group heading)
      -- -- exactly one of which is shown per row (the kind branch in renderRows), so all three
      -- get the same anchors rather than fighting over layout.
      cell:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, 0)
      cell:SetPoint("RIGHT", right, "LEFT", -4, 0)
      -- The column header row (below) shares this function but carries neither widget -- it is
      -- a single fixed heading, never a position/sub-row/group in the pooled row sense.
      if row.subItem then
        row.subItem:ClearAllPoints()
        row.subItem:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, 0)
        row.subItem:SetPoint("RIGHT", right, "LEFT", -4, 0)
      end
      if row.sectionLabel then
        row.sectionLabel:ClearAllPoints()
        row.sectionLabel:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, 0)
      end
      -- Deliberately no cell:Show() here: which of item/subItem/sectionLabel is visible is the
      -- kind branch's call (renderRows), not this function's -- forcing the flex column shown
      -- unconditionally would undo a "position" row's own cells.item:Hide() on every layout.
      -- The header row (below) sets its own item cell's text once and never hides it.
    else
      cell:SetWidth(columnWidth[column.key] or column.w)
      cell:SetPoint("RIGHT", right, right == row and "RIGHT" or "LEFT", right == row and 0 or -2, 0)
      right = cell
      cell:Show()
    end
  end
  for _, column in ipairs(COLUMNS) do
    if dropped[column.key] then row.cells[column.key]:Hide() end
  end
end

-- Keyed by the label the button currently carries. Every one of these either spends gold or
-- destroys a deposit, so none of them should be a word a player has to guess at.
local ACTION_HELP = {
  ["Set cost"] = { "Set cost", { "Tell GoldCap what you actually paid for these units.", "It will not invent a cost from the market price, so profit stays unknown until you enter one." } },
  ["Post"] = { "Post", { "Lists what is sitting in your bags at the price shown under WHAT TO DO.", "A commodity lists the whole bag total at once; a normal item lists one stack, the largest GoldCap can identify exactly.", "It will list stock GoldCap never saw you buy — not knowing what something cost is a reason to report the profit as unknown, not a reason to refuse to sell it.", "The price is the last one GoldCap fetched, at most 45 seconds old — not a fresh check made at the moment you click. If it changes between arming the post and confirming it, the post is abandoned rather than sent at the old price." } },
  ["Repost"] = { "Repost", { "Cancels this live auction. It does NOT relist it: the deposit is forfeit, and the cancelled items come back by mail, not straight into your bags.", "Cancelling forfeits the deposit, so this asks for a second click to confirm.", "Once the mail arrives, list it again yourself at the new price -- from this same row.", "Worth doing when someone has undercut you; not worth it if the price barely moved." } },
  ["Cancel lot?"] = { "Confirm the cancel", { "Clicking again cancels the live auction. It does not relist it: the deposit is forfeit, and the items return by mail rather than straight into your bags.", "The button waits a moment before it can be pressed, so this is never an accidental double-click." } },
  ["Remove"] = { "Remove this cost", { "Deletes a hand-entered cost you typed into Set cost -- never a purchase GoldCap itself captured or matched to your mail.", "There is no undo. Clicking asks for a second click to confirm." } },
  ["Remove?"] = { "Confirm the removal", { "Clicking again deletes this hand-entered cost for good.", "A run of several purchases collapsed onto one line removes every one of them." } },
}

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW_HEIGHT)

  -- Sell rows carried no banding, no hover feedback and no rule between them, so a screenful
  -- of positions read as one undifferentiated block -- and an expanded position's children were
  -- distinguishable only by two leading spaces in their text. Same treatment as the Deals list:
  -- BACKGROUND zebra, a highlight above it, a hairline at the bottom edge, and an item icon so
  -- rows are scannable by shape rather than by reading every name.
  -- Sliced rounded fills (batch-2 pattern). Insets: 1px top/bottom so margin 12 <= 15 = half of
  -- the 30px effective fill (Theme.ROW_H 32 minus 2px); right inset is 2, NOT Deals' 26 -- this
  -- container is already inset by CONTENT_RIGHT_GUTTER (see Attach) and the scrollbar hangs
  -- outside in that gutter.
  local zc = Theme.color.zebra
  row.zebra = row:CreateTexture(nil, "BACKGROUND")
  row.zebra:SetTexture(Theme.MEDIA .. "plaque.png")
  row.zebra:SetTextureSliceMargins(12, 12, 12, 12)
  row.zebra:SetPoint("TOPLEFT", 2, -1); row.zebra:SetPoint("BOTTOMRIGHT", -2, 1)
  row.zebra:SetVertexColor(zc[1], zc[2], zc[3], 0)
  -- The "well": a sunken fill an expanded position's children sit in instead of the list's
  -- alternating zebra, so a sub-row reads as nested inside its position rather than as one more
  -- row in the same flat list (row.spine, below, is the other half of that cue). Same sliced
  -- plaque and insets as the zebra it replaces -- only shown for sub-rows (the kind branch in
  -- renderRows), never alongside it.
  row.well = row:CreateTexture(nil, "BACKGROUND")
  row.well:SetTexture(Theme.MEDIA .. "plaque.png")
  row.well:SetTextureSliceMargins(12, 12, 12, 12)
  row.well:SetPoint("TOPLEFT", 2, -1); row.well:SetPoint("BOTTOMRIGHT", -2, 1)
  local phc = Theme.color.panelHi
  row.well:SetVertexColor(phc[1], phc[2], phc[3], 0.5)
  row.well:Hide()
  row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.highlight:SetTexture(Theme.MEDIA .. "plaque.png")
  row.highlight:SetTextureSliceMargins(12, 12, 12, 12)
  row.highlight:SetPoint("TOPLEFT", 2, -1); row.highlight:SetPoint("BOTTOMRIGHT", -2, 1)
  local hc = Theme.color.hover
  row.highlight:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 0.08)
  row.highlight:Hide()
  row.divider = row:CreateTexture(nil, "ARTWORK")
  row.divider:SetHeight(1)
  row.divider:SetPoint("BOTTOMLEFT", 0, 0)
  row.divider:SetPoint("BOTTOMRIGHT", 0, 0)
  local bc = Theme.color.border
  row.divider:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 0.06)
  -- Child rows (batch/detail/lot) get a gold spine at the left edge instead of a bottom rule,
  -- so an expanded group reads as one bracketed unit rather than as more top-level rows.
  row.spine = row:CreateTexture(nil, "ARTWORK")
  row.spine:SetWidth(2)
  row.spine:SetPoint("TOPLEFT", 0, 0)
  row.spine:SetPoint("BOTTOMLEFT", 0, 0)
  local gc = Theme.color.gold
  row.spine:SetColorTexture(gc[1], gc[2], gc[3], 0.45)
  row.spine:Hide()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the stock icon border
  row.icon:Hide()
  row:SetScript("OnEnter", function(self)
    self.highlight:Show()
    -- Rows are pooled and rebound every render, so the item tooltip is wired once here and
    -- reads whatever position the row currently holds. Hooking it per render would stack.
    if GameTooltip and self.kind == "position" and self.position and self.position.itemID then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.position.itemID) end
      -- Flags painted onto the row at the same time as the cells they describe (MARKET/UNIT's
      -- fallback, the item cell's "· not on hand" suffix) -- read here rather than re-derived,
      -- so the tooltip can never disagree with what the row is actually showing.
      if self.marketFallback then
        GameTooltip:AddLine("≈ goldcap.gg market value — no live quote yet", 0.85, 0.85, 0.85, true)
      end
      if self.notOnHand then
        GameTooltip:AddLine("Not on hand — the stock is in the mail, the bank, or on another character",
          0.85, 0.85, 0.85, true)
      end
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
    if GameTooltip then GameTooltip:Hide() end
  end)

  row.cells = {}
  for _, column in ipairs(COLUMNS) do
    local cell = Theme.Label(row, column.key == "item" and 12 or 11)
    cell:SetJustifyH(column.num and "RIGHT" or "LEFT")
    cell:SetWordWrap(false)
    row.cells[column.key] = cell
  end
  row.cells.item:SetJustifyH("LEFT")
  -- Sub-rows (detail/batch/lot/listing) write into their own widget, one size down from a
  -- position's name (11, not 12) -- the flex column's box is shared by three mutually
  -- exclusive widgets (this, row.cells.item, row.sectionLabel below), and layoutCells anchors
  -- all three to the same LEFT/RIGHT points every render since exactly one is shown per row
  -- (the kind branch in renderRows).
  row.subItem = Theme.Label(row, 11)
  row.subItem:SetJustifyH("LEFT")
  row.subItem:SetWordWrap(false)
  row.subItem:Hide()
  -- Group headings (Sold's own pattern, UI/SoldFrame.lua's row.sectionLabel/row.sectionRule):
  -- a mono micro-label plus a hairline rule running to the row's right edge, instead of a
  -- gold line sharing the item cell's own font -- gold and uppercase are the group's whole
  -- visual language, so nothing about the flex column's shared styling has to bend for it.
  row.sectionLabel = Theme.Num(row, 9, true)
  row.sectionLabel:SetJustifyH("LEFT")
  setColor(row.sectionLabel, Theme.color.gold)
  row.sectionLabel:Hide()
  local gc2 = Theme.color.gold
  row.sectionRule = row:CreateTexture(nil, "ARTWORK")
  row.sectionRule:SetColorTexture(gc2[1], gc2[2], gc2[3], 0.35)
  row.sectionRule:SetHeight(1)
  row.sectionRule:SetPoint("LEFT", row.sectionLabel, "RIGHT", Theme.pad.s, 0)
  row.sectionRule:SetPoint("RIGHT", row, "RIGHT", -Theme.pad.s, 0)
  row.sectionRule:Hide()
  row.action = Theme.Button(row, "ghost", "badge")
  -- 86, not 84: "Cancel lot?" is 85.8px at mono-10 and Theme.Scale() 1.3 (JetBrains Mono
  -- ~0.6em/char -> 7.8px/char); 86 is the largest width that still leaves >=2px clearance
  -- from the neighbouring cells inside the 88px `action` column (layoutCells packs cells with
  -- an explicit 2px gap between them, so an inset button never touches the gap).
  row.action:SetSize(86, 18)
  -- Its own column. Anchored over `status` it covered the recommendation text, which is where
  -- the price and the breakeven are written.
  row.action:SetPoint("CENTER", row.cells.action, "CENTER", 0, 0)
  row.action:Hide()
  -- Wired once on the pooled button; the text is chosen at hover time from the label it
  -- currently carries, so it always describes the action actually on offer.
  if row.action.HookScript then
    row.action:HookScript("OnEnter", function(self)
      if not GameTooltip then return end
      local help = ACTION_HELP[self.label] or ACTION_HELP[(self.label or ""):gsub("%s*%(.*", "")]
      if not help then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(help[1], 1, 0.82, 0)
      for _, line in ipairs(help[2]) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
      GameTooltip:Show()
    end)
    row.action:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  end
  row:SetScript("OnClick", function(self)
    if self.kind == "position" and type(self.position.positionKey) == "string" then
      expanded[self.position.positionKey] = not expanded[self.position.positionKey]
      renderRows()
    end
  end)
  return row
end

-- Explanatory tooltip on any frame. Guarded for busted, where no WoW globals exist.
local function explain(frame, title, body)
  if not frame or not frame.SetScript then return end
  -- HookScript, never SetScript: Theme.Button owns OnEnter/OnLeave for its hover fill, and
  -- replacing those would leave buttons stuck in whichever state they were painted in.
  local hook = frame.HookScript and "HookScript" or "SetScript"
  frame[hook](frame, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 0.82, 0)
    for _, line in ipairs(body) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
    GameTooltip:Show()
  end)
  frame[hook](frame, "OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
end

local HEADER_HELP = {
  cost = { "Cost per unit", { "What one of these actually cost you, averaged over the purchases still on hand.", "A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price." } },
  listed = { "Listed value", { "What your live auctions for this item add up to at their current asking price." } },
  market = { "Market per unit", {
    "The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards.",
    "It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at.",
    "Greyed out means the quote has aged; Post and Repost refresh it before they act." } },
  profit = { "Profit per unit", { "What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost.", "Unknown means the cost side is incomplete -- fill it in with Set cost." } },
  status = { "What to do", { "GoldCap's suggestion for this item, and the price it would use.", "Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money." } },
}

local function showRowAction(row, label, onClick)
  -- Deliberately does NOT clear `status` any more: that cell holds the recommendation -- what
  -- to do, at what unit price, and the breakeven under it -- and blanking it was the reason a
  -- player could never tell what a Post or Repost was about to charge.
  row.action:SetLabel(label)
  if onClick then row.action:SetScript("OnClick", onClick) end
  row.action:Show()
end

local function summaryFor(filtered)
  local partial, unknown, knownCost, listedValue = 0, 0, 0, 0
  for _, position in ipairs(filtered) do
    if position.coverage == "PARTIAL" then partial = partial + 1 end
    if position.coverage == "UNKNOWN" then unknown = unknown + 1 end
    if not exact(position.knownCost) then knownCost = nil
    elseif knownCost ~= nil then knownCost = safeAdd(knownCost, position.knownCost) end
    if not exact(position.listedValue) then listedValue = nil
    elseif listedValue ~= nil then listedValue = safeAdd(listedValue, position.listedValue) end
  end
  local raw = GC.SellPositions.Summary(filtered)
  return GC.SellViewModel.SummaryText({ knownCost = raw.invested or knownCost,
    listedValue = raw.listedValue or listedValue,
    profit = raw.profit, partialCount = partial, unknownCount = unknown,
    countedCount = raw.countedCount, excludedNoCost = raw.excludedNoCost, excludedNoPrice = raw.excludedNoPrice })
end

local function updateSummary(filtered)
  local text = summaryFor(filtered)
  container.summary.cost:SetText(formatCell(text.knownCost))
  container.summary.listed:SetText(formatCell(text.listedValue))
  if type(text.profit) == "number" then
    container.summary.profit:SetText(formatAmount(text.profit))
    -- No longer always nil: the number is a sum over only the positions that individually
    -- cleared both gates, so it can still be a partial total, and the card's own hit frame
    -- (below) shows that detail on hover exactly like the "Unknown · ..." case does.
    container.summaryProfitDetail = text.profitDetail
  else
    -- SellViewModel.SummaryText's non-number reads "Unknown" or "Unknown · 12 partial · 37
    -- missing" -- at Theme.Scale() 1.3 the longer form doesn't fit the mono value line, so the
    -- card itself stays a plain "Unknown" and everything after the first " · " moves to
    -- summaryProfitHit's own tooltip (see the stat-card loop below), read live at hover time.
    container.summary.profit:SetText("Unknown")
    local sepStart, sepEnd = text.profit:find(" · ", 1, true)
    container.summaryProfitDetail = sepStart and text.profit:sub(sepEnd + 1) or nil
  end
  -- A non-number here is an absence, not a result: painting "Unknown" in the same confident
  -- green as a real profit read as a figure the addon stood behind.
  setColor(container.summary.profit, type(text.profit) == "number"
    and (text.profit < 0 and Theme.color.red or Theme.color.green) or Theme.color.fgDim)
end

renderRows = function()
  if not container then return end
  -- The Sell CONTENT may be attached but not the tab currently on screen -- composePositions()
  -- and GC.Sell.Refresh() run regardless of which tab is active (bag counts and the tab badge
  -- must stay current either way), and that used to rebuild every visible row along with them:
  -- dragging the window's resize grip alone re-ran this at up to 60fps, and every quote landing
  -- during a background pricing walk re-ran it again, whether or not anyone could see the
  -- result. Defer instead, the same way an armed post/repost already defers below --
  -- GC.Sell.Show() reveals the container and then unconditionally calls Refresh(), which is
  -- what actually flushes this: the very next render it triggers runs for real once
  -- containerShown() is true again, so nothing needs a second explicit flush call here.
  if not containerShown() then
    deferredRender = true
    return
  end
  -- A post or repost that is armed is waiting on the player's confirming click,
  -- and the pin proving that click belongs to it is bound to a pooled row. A
  -- render rebinds those rows, so this used to answer by CANCELLING the
  -- confirmation the player was one click away from giving. That was already
  -- wrong; the tab now re-prices itself every few seconds, which made it certain.
  -- Hold the render instead. Every arm is timeout-bounded, so it cannot be held
  -- indefinitely, and disarmPost/disarmRepost/disarmRemove flush whatever was deferred.
  if postingRow or repostingRow or removingRow then
    deferredRender = true
    return
  end
  deferredRender = false
  renderGeneration = renderGeneration + 1
  local filtered
  if filterMode == "queue" then
    -- The queue's own order, head first -- deliberately NOT SellViewModel.Order, which ranks
    -- by a different question ("what could I act on, roughly") than GC.PostQueue.Build's "what
    -- is most valuable to post right now, in a stable order." See PostQueue.lua's own
    -- entryLess. Every entry maps back to its live position object -- the queue itself carries
    -- only display figures, never a second copy of the position -- so the row this produces is
    -- the exact same row a normal filter chip would have rendered for that position.
    filtered = {}
    for _, entry in ipairs(queueEntries) do
      local position = currentPosition(entry.positionKey)
      if position then filtered[#filtered + 1] = position end
    end
  elseif filterMode == "cancelqueue" then
    -- The cancel queue's own order, head first -- one row per position however many of its
    -- lots are queued; the queued lots themselves render through the position's expansion,
    -- which is where the Repost/Cancel action a click needs actually lives.
    filtered = {}
    local seen = {}
    for _, entry in ipairs(cancelEntries) do
      if not seen[entry.positionKey] then
        seen[entry.positionKey] = true
        local position = currentPosition(entry.positionKey)
        if position then filtered[#filtered + 1] = position end
      end
    end
  else
    filtered = GC.SellViewModel.Filter(positions, filterMode)
    if GC.SellViewModel.Order then filtered = GC.SellViewModel.Order(filtered) end
  end
  updateSummary(filtered)
  local entries = {}
  for _, position in ipairs(filtered) do
    entries[#entries + 1] = { kind = "position", position = position }
    if expanded[position.positionKey] then
      local detail = GC.SellViewModel.Expansion(position)
      entries[#entries + 1] = { kind = "detail", position = position, detail = detail }
      -- What you are selling comes before what you paid: the listings are the thing a player
      -- acts on, the purchase history is only there to justify the cost number.
      local inBags = position.bagQty or 0
      if #detail.ownedLots > 0 or inBags > 0 then
        entries[#entries + 1] = { kind = "group", position = position, title = "ON THE AUCTION HOUSE" }
      end
      for _, lot in ipairs(detail.ownedLots) do entries[#entries + 1] = { kind = "lot", position = position, lot = lot } end
      if inBags > 0 then
        entries[#entries + 1] = { kind = "listing", position = position }
      end
      if #detail.batches > 0 then
        entries[#entries + 1] = { kind = "group", position = position, title = "WHAT YOU PAID",
          hint = "Sales are costed from your oldest units first" }
      end
      for _, batch in ipairs(detail.batches) do entries[#entries + 1] = { kind = "batch", position = position, batch = batch } end
    end
  end
  if #entries == 0 then
    -- M7: sentence case, not shouted -- this is a native-font (Theme.Label) empty state, like
    -- Deals', and reads like the rest of that font's copy rather than a toolbar label.
    container.emptyText:SetText(filterMode == "all"
      and "Nothing to sell — no items in bags or listed" or "No items match this filter")
    container.emptyText:Show()
  else
    container.emptyText:Hide()
  end
  for i = #rows + 1, #entries do rows[i] = createRow(content) end
  for i, row in ipairs(rows) do
    local entry = entries[i]
    if not entry then row.renderEntryID = nil; row:Hide()
    else
      row:Show(); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT); row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
      row.kind, row.position, row.batch, row.lot = entry.kind, entry.position, entry.batch, entry.lot
      -- Read by this row's own OnEnter (below) to decide whether to add a tooltip line about the
      -- number this row is showing. Reset for every kind, not just "position": rows are pooled
      -- and rebound, so a flag left set from an earlier position would otherwise ride along onto
      -- an unrelated expansion sub-row.
      row.marketFallback, row.notOnHand = false, false
      local p = entry.position
      local lotID = entry.lot and entry.lot.auctionID or 0
      row.renderEntryID = table.concat({ renderGeneration, i, entry.kind, p.scopeKey or "", p.positionKey or "", lotID }, ":")
      if entry.kind == "position" then
        -- Second line answers "how many of these do I have, and where are they" -- the question
        -- a seller actually asks. Where each unit came from stays available on the tooltip.
        -- The bag count is now measured, not inferred. It used to be tracked
        -- minus listed -- an accounting leftover that announced stock as "in
        -- your bags" whenever GoldCap had not seen one of the player's own
        -- auctions, and that showed nothing at all for anything GoldCap never
        -- bought, which was most of what a seller actually has to sell.
        local listedQty, bagQty = p.listedQty or 0, p.bagQty or 0
        local stockParts = {}
        if bagQty > 0 then stockParts[#stockParts + 1] = ("×%d in bags"):format(bagQty) end
        if listedQty > 0 then stockParts[#stockParts + 1] = ("×%d listed"):format(listedQty) end
        -- The quality pip goes in the label rather than beside it: this row and
        -- the Sniper's deal row anchor their cells completely differently, and an
        -- inline atlas escape needs no layout in either. Empty for the vast
        -- majority of items, which have no quality tier at all.
        local named = Theme.WithQuality and Theme.WithQuality(p.itemName or "Item", p.itemID)
          or (p.itemName or "Item")
        -- Nothing in the bags and nothing listed means the stock this row tracks is real cost
        -- history sitting somewhere else -- the mail, the bank, another character -- not a
        -- position that vanished. The dim "· not on hand" suffix goes AFTER the qty suffix (or
        -- its SourceText fallback, when there is no qty to show), same idiom as SniperFrame's
        -- "· watching" suffix in setRowDeal, and its own color code so it never inherits
        -- whatever color the line before it painted.
        --
        -- Deliberately not queued into the pricing walk: uniqueQuoteItemIDs (above) only picks
        -- up a position with `inBags or listed`, so this row keeps whatever quote it already
        -- has (or none) and stays ranked last -- there is nothing actionable to price a quote
        -- for, and spending one of the walk's throttled requests on it would starve a row a
        -- player can actually act on right now.
        local notOnHand = (p.bagQty or 0) == 0 and (p.listedQty or 0) == 0
        row.notOnHand = notOnHand
        row.cells.item:SetText(named .. "\n"
          .. (#stockParts > 0 and table.concat(stockParts, " · ") or GC.SellViewModel.SourceText(p))
          .. (notOnHand and "|cff8c8a85 · not on hand|r" or ""))
        -- Cost per unit, not the position total: it is the number that compares against the
        -- market price in the very next column. An incomplete basis says so in words below.
        local unitCost = nil
        if p.coverage == "COMPLETE" and exact(p.knownCost) and exact(p.knownQty) and p.knownQty > 0 then
          unitCost = math.floor(p.knownCost / p.knownQty)
        end
        row.cells.cost:SetText(unitCost and formatCell(unitCost) or "—")
        row.cells.listed:SetText(formatCell(p.listedValue))
        -- "none" ~= "—": the first is an answer ("the AH has zero listings right now",
        -- remembered in emptyAnswers), the second is the absence of one. Conflating them made
        -- honestly-unlisted items read as the pricing walk being slow or stuck.
        --
        -- Below both of those sits a third case: no live quote yet AT ALL (not even a stale
        -- one), but the item was imported from goldcap.gg with a market value -- the same
        -- number Deals shows. That value is not live, so it never overrides an actual AH
        -- answer (an empty one included -- the AH answered "none", which outranks a guess from
        -- the last import), but showing it beats a "—" that reads as "the addon hasn't checked
        -- yet" for as long as the pricing walk takes to reach this row.
        local marketFallback = p.displayMarketUnit == nil and type(p.marketValue) == "number"
          and p.marketValue > 0 and not emptyAnswers[p.itemID]
        row.marketFallback = marketFallback
        local marketText
        if p.displayMarketUnit then
          marketText = formatCell(p.displayMarketUnit)
        elseif marketFallback then
          marketText = "≈" .. formatCell(p.marketValue)
        else
          marketText = emptyAnswers[p.itemID] and "none" or "—"
        end
        if p.displayMarketUnit and not p.freshMarketUnit and type(p.quoteAge) == "number" then
          marketText = marketText .. (" · stale %ds"):format(p.quoteAge)
        end
        row.cells.market:SetText(marketText)
        setColor(row.cells.market, (marketFallback or (p.displayMarketUnit and not p.freshMarketUnit))
          and Theme.color.fgDim or Theme.color.fg)
        -- Per unit, to match the two columns it is compared against. The view model reports the
        -- position total; showing that under a "/ UNIT" heading turned a loss of under a gold
        -- per unit into a headline "-128g".
        local profit = GC.SellViewModel.ProfitText(p)
        if type(profit) == "number" and exact(p.knownQty) and p.knownQty > 0 then
          local perUnit = profit / p.knownQty
          profit = perUnit >= 0 and math.floor(perUnit) or -math.floor(-perUnit)
        end
        -- position.profitAtHold names the case where this number was computed at
        -- postRecommendation.unit and that unit sat ABOVE the fresh live quote (PostFloor, or
        -- the queue-at-exit rule, holding the recommendation above what a seller could actually
        -- get selling into today's book right now). The number itself stays the recommendation
        -- -- it IS the price GoldCap would post at -- but green would claim it as ordinary
        -- market profit when it is really a bet on the hold, so it renders in the same gold the
        -- MARKET/UNIT column already uses for a computed forward price (see the "» <price>"
        -- cells below), with the price it assumes named in the cell rather than left implicit.
        -- A hold that is STILL a loss is not softened by the gold tone -- red outranks it.
        --
        -- setColor runs in BOTH branches, never just the hold one: rows are pooled and rebound
        -- to a new position on every render (renderRows reuses `rows[i]` rather than creating a
        -- fresh cell each time -- see createRow's own call site), so a row painted gold or red
        -- here on one render and left uncolored on the next would carry that tint into whatever
        -- unrelated number lands in the same slot afterward. Same failure class AGENTS.md
        -- already documents for hover fills painted in OnEnter and never cleared in OnLeave.
        if type(profit) == "number" and exact(p.profitAtHold) then
          -- Whole gold only: "@ 18g15s" was precisely the tail the column cut
          -- off in game. The exact figure is the Post price, one column over.
          local hold = p.profitAtHold >= 10000
            and ("%dg"):format(math.floor(p.profitAtHold / 10000))
            or formatCell(p.profitAtHold)
          row.cells.profit:SetText(("%s %s@%s|r"):format(
            formatCell(profit), DIM_HEX, hold))
          setColor(row.cells.profit, profit < 0 and Theme.color.red or Theme.color.gold)
        else
          row.cells.profit:SetText(formatCell(profit))
          setColor(row.cells.profit, Theme.color.fg)
        end
        -- "Unknown" (profit) sitting beside "UNLISTED" (status) read as one meaningless phrase.
        -- This column now says what to do about it, in a sentence, or names what is missing.
        local knownQty, exposureQty = p.knownQty or 0, p.exposureQty or 0
        if p.facts and p.facts.underpriced then
          -- Money leaving, silently. A listing posted against a thin cheap lot
          -- looks ordinary until that lot clears and the book springs back --
          -- which is how five Arcane Crystals bought at 70g ended up on sale at
          -- 18g against a 92g market. This is the one thing on the row that has
          -- to be read before anything else, so it takes the column and the
          -- alarm colour, and the advice moves aside for it.
          row.cells.status:SetText(("Listed at %s — far below market. Repost."):format(
            formatCell(p.underpricedUnit)))
          setColor(row.cells.status, Theme.color.red)
        elseif p.recommendation then
          row.cells.status:SetText(recommendationText(p.recommendation))
          setColor(row.cells.status, Theme.color.fg)
        elseif bagQty > 0 then
          -- The advice column is not the place to report bookkeeping when the
          -- player is holding sellable stock: say what is missing to price it.
          -- "Waiting" when the answer already arrived and was "nothing on sale"
          -- is a lie that reads as the addon being slow -- name the real state.
          if p.displayMarketUnit == nil and emptyAnswers[p.itemID] then
            row.cells.status:SetText("Nothing listed on the AH right now")
          else
            row.cells.status:SetText("Waiting for a live price")
          end
          setColor(row.cells.status, Theme.color.fgDim)
        elseif not p.unresolved and (p.listedQty or 0) == 0 then
          -- Nothing in the bags AND nothing listed: the stock this row tracks is in the
          -- mail, the bank, or on another character. Cost coverage is a real question too,
          -- but "where is my ore?" is the one the player is actually asking here.
          row.cells.status:SetText("Not in your bags or listed — mail or bank?")
          setColor(row.cells.status, Theme.color.fgDim)
        elseif p.coverage ~= "COMPLETE" then
          row.cells.status:SetText(("Cost unknown for %d of %d"):format(
            math.max(0, exposureQty - knownQty), exposureQty))
          setColor(row.cells.status, Theme.color.fgDim)
        else
          row.cells.status:SetText("")
          setColor(row.cells.status, Theme.color.fg)
        end
        row.cells.expand:SetText(expanded[p.positionKey] and "−" or "+")
        -- Post is the point of this screen, so it lives on the row itself. It
        -- used to be reachable only by expanding the position and finding a
        -- sub-row, and only for stock GoldCap had a receipt for -- which is why
        -- the honest answer to "what can I list" was "go use the Blizzard tab".
        -- Set cost is bookkeeping and stays available whenever there is no
        -- stock to act on; the expansion carries it in either case.
        if bagQty > 0 then
          showRowAction(row, "Post", function() onPostClick(row) end)
        elseif canSetCost(p) then
          showRowAction(row, "Set cost", function() openCostDialog(p) end)
        else
          row.action:Hide()
        end
      elseif entry.kind == "detail" then
        -- Facts joined only when GoldCap actually has them -- a "quote 7s / ? ahead of you /
        -- sells ?/day" used to paper over missing data with a question mark on every field that
        -- happened not to apply to this position, which read as the addon being broken rather
        -- than as "this one doesn't have that fact". A live market quote replaces the "quote"
        -- fact with its own richer lead (unchanged shape, just no "?" filler within it either);
        -- everything else after it -- competition, velocity, time to clear, any structural
        -- facts -- still only appears when it is actually known.
        local d = entry.detail
        local facts = {}
        if d.displayMarketUnit ~= nil then
          local lead = ("market %s · %s"):format(formatCell(d.displayMarketUnit), d.marketState or "unavailable")
          if type(d.quoteAge) == "number" then lead = lead .. (" · age %ss"):format(d.quoteAge) end
          facts[#facts + 1] = lead
        elseif type(d.quoteAge) == "number" then
          facts[#facts + 1] = ("quote %ss ago"):format(d.quoteAge)
        end
        if type(d.ahead) == "number" then facts[#facts + 1] = ("%d ahead of you"):format(d.ahead) end
        if d.sold ~= nil then facts[#facts + 1] = ("sells %s/day"):format(d.sold) end
        if type(d.days) == "number" then facts[#facts + 1] = ("clears in ~%dd"):format(math.floor(d.days + 0.5)) end
        if d.factsText then facts[#facts + 1] = d.factsText end
        row.subItem:SetText(#facts > 0 and table.concat(facts, " · ") or "no live quote yet — pricing…")
        setColor(row.subItem, (#facts == 0 or d.marketStale) and Theme.color.fgDim or Theme.color.fg)
        row.cells.cost:SetText(""); row.cells.listed:SetText(""); row.cells.market:SetText("")
        row.cells.profit:SetText(""); row.cells.status:SetText(recommendationText(d.recommendation)); row.cells.expand:SetText("")
        row.action:Hide()
      elseif entry.kind == "group" then
        row.sectionLabel:SetText(entry.title)
        row.cells.cost:SetText(""); row.cells.listed:SetText(""); row.cells.market:SetText("")
        row.cells.profit:SetText(""); row.cells.expand:SetText("")
        row.cells.status:SetText(entry.hint or "")
        setColor(row.cells.status, Theme.color.fgDim)
        row.action:Hide()
      elseif entry.kind == "batch" then
        -- Was "goldcap · at 1786831966 · 5 original / 2 left / 2 FIFO · unit 100 · captured".
        -- A raw epoch and the allocator's internal counters are not facts a seller can use; how
        -- many, when, at what price and from where are.
        local function acquiredWhen(at)
          if type(at) == "number" and _G.date then
            local ok, formatted = pcall(_G.date, "%d %b", at)
            if ok and type(formatted) == "string" then return formatted end
          elseif at ~= nil then
            return tostring(at)
          end
          return "?"
        end
        -- A collapsed run (SellViewModel.Expansion merges adjacent same-price purchases) shows
        -- its date range and how many buys it stands for; a lone purchase reads as before.
        -- The count follows the quantity directly: this cell ellipsizes from the tail at
        -- narrow widths, and the count is the one fact the collapse exists to surface. The
        -- range separator is an ASCII hyphen -- the client font is missing glyphs as common
        -- as U+2192 (it drew a tofu box), so only in-game-proven punctuation goes on screen.
        local purchases = entry.batch.purchases
        local when
        if purchases and purchases > 1 then
          local first = acquiredWhen(entry.batch.acquiredAtFirst)
          local last = acquiredWhen(entry.batch.acquiredAtLast)
          when = first == last and first or (first .. " - " .. last)
        else
          when = acquiredWhen(entry.batch.acquiredAt)
        end
        local sourceLabel = ({ goldcap = "GoldCap", auction_house = "Auction House", manual = "entered by hand" })[entry.batch.source] or (entry.batch.source or "manual")
        -- The evidence word stays: it is how the player knows whether that cost is a confirmed
        -- invoice or a guess, which is exactly the thing this whole tab refuses to fake. The
        -- unit price no longer repeats here -- the COST/LISTED cells two columns over already
        -- carry the unit and total, and this line was the one place on the row saying the same
        -- number twice.
        -- Pooled rows keep whatever colour the last kind painted: a dim detail line must not
        -- bleed into the next render's batch text.
        setColor(row.subItem, Theme.color.fg)
        row.subItem:SetText(("×%d%s · bought %s · %s · %s"):format(
          entry.batch.originalQty or entry.batch.quantity or 0,
          purchases and purchases > 1 and (" · %d purchases"):format(purchases) or "",
          when, sourceLabel, entry.batch.evidence or "unknown evidence"))
        row.cells.cost:SetText(formatCell(entry.batch.unitCost)); row.cells.listed:SetText(formatCell(entry.batch.totalCost)); row.cells.market:SetText("")
        row.cells.profit:SetText("")
        row.cells.status:SetText((entry.batch.remainingQty or 0) > 0
          and ("%d still unsold"):format(entry.batch.remainingQty) or "all sold")
        setColor(row.cells.status, Theme.color.fgDim)
        row.cells.expand:SetText("")
        -- Only a hand-entered cost gets a removal affordance -- goldcap and auction_house
        -- batches are evidence-backed, and Core/Acquisitions' own RemoveManual already refuses
        -- them, but the button should never even offer the click. entry.batch.source is the one
        -- source every id in `ids` shares (Expansion's own collapse key), so this single check
        -- covers a lone purchase and a collapsed run alike -- and a mixed run cannot occur here.
        if entry.batch.source == "manual" and type(entry.batch.ids) == "table" and #entry.batch.ids > 0 then
          showRowAction(row, "Remove", function() onRemoveClick(row) end)
        else
          row.action:Hide()
        end
      elseif entry.kind == "lot" then
        local total = safeMultiply(entry.lot.unitPrice, entry.lot.quantity)
        -- The auction ID is the addon's handle for cancelling the right lot; it means nothing to
        -- a player, so it moves to the tooltip and the row says what is actually listed.
        setColor(row.subItem, Theme.color.fg) -- see the batch branch: pooled rows keep colour
        row.subItem:SetText(("×%d listed at %s each"):format(
          entry.lot.quantity, formatCell(entry.lot.unitPrice)))
        row.cells.cost:SetText(""); row.cells.listed:SetText(formatCell(total))
        -- What Repost will actually list at. BuildRepostPlan prices a repost at exactly the
        -- fresh quote unit, so showing that quote here answers "at what price?" before the
        -- player commits to cancelling a live auction and eating its deposit.
        if p.displayMarketUnit and p.freshMarketUnit then
          row.cells.market:SetText("» " .. formatCell(p.displayMarketUnit))
          setColor(row.cells.market, Theme.color.gold)
        else
          row.cells.market:SetText("» needs price")
          setColor(row.cells.market, Theme.color.fgDim)
        end
        row.cells.profit:SetText("")
        row.cells.status:SetText(recommendationText(p.recommendation))
        setColor(row.cells.status, Theme.color.fg)
        row.cells.expand:SetText("")
        showRowAction(row, "Repost", function() onRepostClick(row, entry.lot.auctionID) end)
      else
        -- "In your bags" used to be inferred as tracked minus listed, which is an accounting
        -- leftover, not a measurement: whenever GoldCap had not seen one of the player's own
        -- auctions, the difference was announced as sitting in their bags when it was in fact on
        -- the Auction House. The real bag count is available -- it already gates the Post button
        -- below -- so state it, and when the two disagree say what is unaccounted for instead of
        -- picking one and presenting it as fact.
        -- Post moved up to the position row, so this line's job is now to say
        -- exactly what one click would list, and how much would be left behind.
        -- A normal item posts from ONE bag stack (PostItem pins a single
        -- ItemLocation), so a split stack cannot all go at once; a commodity
        -- aggregates across the bags and can.
        local inBags = p.bagQty or 0
        local bagState = liveBagState(p)
        local postable = bagState and bagState.bag and exact(bagState.exactQty) and bagState.exactQty or 0
        setColor(row.subItem, Theme.color.fg) -- see the batch branch: pooled rows keep colour
        if postable > 0 and postable < inBags then
          row.subItem:SetText(("×%d in your bags · Post lists %d of them, the largest stack"):format(
            inBags, postable))
        elseif postable > 0 then
          row.subItem:SetText(("×%d in your bags, ready to list"):format(postable))
        else
          row.subItem:SetText(("×%d in your bags · no stack GoldCap can identify exactly"):format(inBags))
        end
        row.cells.cost:SetText(""); row.cells.listed:SetText(""); row.cells.market:SetText(""); row.cells.profit:SetText(""); row.cells.expand:SetText("")
        if postable > 0 then
          -- Say what Post will charge before it is clicked.
          if p.displayMarketUnit and p.freshMarketUnit then
            row.cells.market:SetText("» " .. formatCell(p.displayMarketUnit))
            setColor(row.cells.market, Theme.color.gold)
          else
            row.cells.market:SetText("» needs price")
            setColor(row.cells.market, Theme.color.fgDim)
          end
          row.cells.status:SetText(recommendationText(p.recommendation))
          setColor(row.cells.status, Theme.color.fg)
        else
          row.cells.status:SetText("")
          setColor(row.cells.status, Theme.color.fgDim)
        end
        -- Gated on canSetCost alone, not on the coverage label. A position that
        -- is COMPLETE against its tracked purchases can still hold uncosted
        -- stock -- five units bought through GoldCap and two hundred farmed is
        -- the ordinary case -- and the coverage flag would have hidden the
        -- button for exactly those.
        if canSetCost(p) then
          showRowAction(row, "Set cost", function() openCostDialog(p) end)
        else
          row.action:Hide()
        end
      end
      -- Banding, hierarchy and the icon are decided here, after the cells are filled, because
      -- only `entry.kind` distinguishes a position from one of its expanded children. Exactly
      -- one of row.cells.item / row.subItem / row.sectionLabel is shown per row -- the other
      -- two are hidden here rather than merely left un-set, since rows are pooled and rebound
      -- to a different kind on every render (a "batch" this pass can be a "position" the next).
      local zc2 = Theme.color.zebra
      row.zebra:SetVertexColor(zc2[1], zc2[2], zc2[3], (i % 2 == 1) and (zc2[4] or 0.04) or 0)
      if entry.kind == "position" then
        row.itemInset = 26
        row.spine:Hide()
        row.divider:Show()
        row.zebra:Show()
        row.well:Hide()
        row.cells.item:Show()
        row.subItem:Hide()
        row.sectionLabel:Hide()
        row.sectionRule:Hide()
        local icon = nil
        if p.itemID and C_Item and C_Item.GetItemIconByID then
          local ok, texture = pcall(C_Item.GetItemIconByID, p.itemID)
          icon = ok and texture or nil
        end
        if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
      else
        row.itemInset = 34
        row.icon:Hide()
        row.spine:Show()
        row.divider:Hide() -- a group's children are bracketed by the spine, not sliced by rules
        -- The well, not the zebra: a sub-row sits on a nested fill instead of the list's own
        -- banding, so an expanded group reads as one bracketed unit (the spine is the other
        -- half of that cue) rather than as more top-level rows in the same alternating list.
        row.zebra:Hide()
        row.well:Show()
        row.cells.item:Hide()
        if entry.kind == "group" then
          row.subItem:Hide()
          row.sectionLabel:Show()
          row.sectionRule:Show()
        else
          row.subItem:Show()
          row.sectionLabel:Hide()
          row.sectionRule:Hide()
        end
      end
      layoutCells(row)
    end
  end
  content:SetHeight(math.max(1, #entries) * ROW_HEIGHT)
  scheduleQuoteExpiry()
  if GC.Sniper and GC.Sniper.UpdateSellTabLabel then GC.Sniper.UpdateSellTabLabel() end
end

-- The toolbar queue control's own click. Arms queue mode (so row 1 is guaranteed to be the
-- head -- see renderRows' own "queue" branch above and the design document's own reasoning for
-- why this, rather than teaching onPostClick a second way to find a row) and then posts row 1
-- through onPostClick EXACTLY -- its own pin validation, its needsConfirmation branch, its
-- timeout. There is no second posting implementation here, and nothing here calls a protected
-- API directly; see spec/sell_post_wiring_spec.lua for the static guard on both.
--
-- Failure mode, spelled out rather than reassured about: if row 1 does not come back as a
-- rendered "position" row after this -- the container hidden, a render some other in-flight
-- arm is still deferring, or (the one this file's own code cannot create today, but a future
-- edit might) the queue's head position vanishing from `positions` between compose and render
-- -- this does nothing further. No protected call is attempted on a guess. The player sees a
-- status line saying so and can press the control again once a render has actually happened.
local function onQueueClick()
  if #queueEntries == 0 then
    setStatus("Nothing queued to post")
    return
  end
  filterMode = "queue"
  renderRows()
  local row = rows[1]
  -- `row:IsShown()`, never `row.shown`. A real Frame has no `shown` FIELD -- only the method --
  -- but every widget double in this suite implements Show/Hide by writing `self.shown`, so
  -- reading the field is true in every test and nil in the client, and this button would have
  -- shipped refusing to post anything at all while seven tests proved it worked. That is the
  -- third time today a field only the fakes define reached production; see
  -- spec/ui_widget_field_spec.lua, which now fails the build for it.
  if row and row.IsShown and row:IsShown() and row.kind == "position" then
    onPostClick(row)
  else
    setStatus("Could not find the queue's next item to post — try again")
  end
end

-- The cancel control's click. Same discipline as onQueueClick, plus the destructive-action
-- rule: this function never cancels anything itself -- it finds the head's rendered LOT row
-- and hands the click to onRepostClick, whose two-click arm (the deposit warning, the
-- REPOST_ARM_SECONDS delay before a confirm counts, the timeout) and pin validation apply
-- unchanged. A first click therefore arms at most; nothing here calls a protected API --
-- see spec/sell_post_wiring_spec.lua's static guard on exactly that.
local function onCancelQueueClick()
  if #cancelEntries == 0 then
    setStatus("Nothing queued to cancel")
    return
  end
  local head = cancelEntries[1]
  filterMode = "cancelqueue"
  -- Force-expand the head's position: onRepostClick pins to a rendered lot row, and a
  -- collapsed position renders no lot rows at all. (While an arm is already in flight this
  -- render defers, deliberately -- the armed row's binding must not be rebuilt under it.)
  expanded[head.positionKey] = true
  renderRows()
  local target
  for _, row in ipairs(rows) do
    -- `row:IsShown()`, never `row.shown` -- see onQueueClick's own comment on the widget-double
    -- field that shipped a dead button.
    if row.IsShown and row:IsShown() and row.kind == "lot" and row.lot and row.lot.auctionID == head.auctionID then
      target = row
      break
    end
  end
  if target then
    onRepostClick(target, head.auctionID)
    paintCancelButton()
  else
    setStatus("Could not find the queue's next lot to cancel — try again")
  end
end

-- The number on the Sell tab. It counted positions whose tracked purchases
-- outran their known listings -- an accounting difference, not a count of
-- anything a player can act on. It now counts items sitting in the bags that
-- the auction house would accept, which is what "Sell (9)" reads as.
--
-- Reads the count composePositions() already stamped rather than recomposing to answer this --
-- a compose is a full six-bag scan plus every Acquisitions/Ledger walk, and every caller of
-- this function calls it right where composePositions() was either just run or is about to be:
--   * updateSellTabLabel(), from renderRows()'s own tail -- always after this same render's
--     composePositions() has already run.
--   * GC.Sniper.Toggle() and the AH-open handler -- both call GC.Sell.Refresh() (which
--     composes synchronously, before any network round trip) immediately before reading this.
--   * recordPurchaseFacts(), right after a purchase -- calls this WITHOUT a fresh compose, but
--     a GoldCap purchase always lands in the mailbox, never straight into the bags, so bagQty
--     (what this counts) cannot have changed at that exact instant; the cached value is still
--     correct, and was already the only thing an immediate recompose there would have measured.
-- Only a cold call before anything has ever composed falls back to composing once itself.
function GC.Sell.SellableCount()
  if sellableCount == nil then composePositions() end
  return sellableCount or 0
end

function GC.Sell.Show()
  if container then container:Show() end
  -- This is what flushes a render renderRows() deferred while the container was hidden: Show()
  -- has always called Refresh() unconditionally, and Refresh()'s own composePositions()+
  -- renderRows() pass now runs for real the instant containerShown() is true. An explicit
  -- flushDeferredRender() call here would render this same pass a second time.
  GC.Sell.Refresh()
end
function GC.Sell.Hide() if container then container:Hide() end end
-- `automatic` marks the self-driven repeat below, which politely stands aside
-- for anything already in flight. A press of the button does not: it means "do
-- it now", and refusing while a phase was set is what made the button dead.
-- Whatever was in flight is let go of behind a drain tombstone, exactly the way
-- Reset already did it, so a late terminal event is consumed rather than
-- credited to this run.
function GC.Sell.Refresh(automatic)
  if automatic and refresh.phase ~= "idle" and refresh.phase ~= "done" and refresh.phase ~= "error" then
    return
  end
  abandonInFlightQuote()
  quoteExpiryGeneration = quoteExpiryGeneration + 1
  refresh.generation = refresh.generation + 1
  refresh.phase, refresh.queue, refresh.index = "owned", {}, 0
  markProgress()
  if not automatic then
    -- A manual press means "ask for real": remembered no-listing answers are wiped so every
    -- row gets a genuine re-ask instead of being gagged by a minute-old empty result.
    for key in pairs(emptyAnswers) do emptyAnswers[key] = nil end
  end
  -- Draw what is already known before asking the server anything. Bag contents
  -- need no auction house at all, and every path below can fail -- the auction
  -- house not being open being the ordinary one. Without this, opening the Sell
  -- tab anywhere but at an auctioneer showed an empty list and a line of text,
  -- when the answer to "what could I sell" was sitting in the player's bags.
  composePositions()
  renderRows()
  setStatus(automatic and "Checking prices…" or "Refreshing listings…")
  if automatic then
    -- The repeat prices only. Owned lots change through OWNED_AUCTIONS_UPDATED /
    -- AUCTION_CANCELED events regardless, and re-querying them here cost a throttled round
    -- trip plus its wait on every 5-second tick before a single price was asked -- and was
    -- one more phase the walk could wedge in.
    beginQuoteWalk()
    armPhaseWatchdog()
    return
  end
  local sent, waiting = requestOwnedAuctions()
  if waiting then
    refresh.phase = "waiting_owned"
    setStatus("Waiting for Auction House…")
  elseif not sent then
    refresh.phase = "idle"
    setStatus("Auction House is not open")
  end
  armPhaseWatchdog()
end
function GC.Sell.Reset()
  abandonInFlightQuote()
  refresh.generation = refresh.generation + 1
  refresh.phase, refresh.queue, refresh.index = "idle", {}, 0
  GC.QuoteCache.Clear(quotes)
  -- Reset means "forget everything" -- the persisted mirror too, not just the session cache.
  local persisted = persistedQuotes()
  if persisted then GC.QuoteCache.Clear(persisted) end
  quoteExpiryGeneration = quoteExpiryGeneration + 1
  walkRepeatToken = walkRepeatToken + 1
  watchdogToken = watchdogToken + 1
  disarmPost()
  disarmRepost()
  disarmRemove()
end

function GC.Sell.Attach(f, geometry)
  ROW_WIDTH, ROW_HEIGHT, statusOwner = geometry.rowWidth, geometry.rowHeight, f
  container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", geometry.panelLeft, geometry.top); container:SetPoint("BOTTOMRIGHT", -geometry.panelRightInset, geometry.bottom); container:Hide()
  -- The header block is a fixed three-row grid on a 30px pitch (was 24px -- the rounded mono
  -- buttons below are h26, and a 24px pitch would have clipped them), each row owning its whole
  -- width, because the previous layout let two anchor chains grow toward each other on a
  -- shared row and collide at ordinary window widths (the queue's head label ran under the
  -- filter chips; the cancel cluster ran under EST. PROFIT):
  --   row 1 (y   0): [POST N] head label ················· held-back · [CANCEL N]
  --   row 2 (y -30): ················· chips (filters for the list below) · [REFRESH]
  --   row 3 (y -60): KNOWN COST / LISTED VALUE / EST. PROFIT
  local refreshButton = Theme.Button(container, "ghost", "plaque")
  -- 104, not 72: the busy label is "PRICING 10/24" (see paintRefreshButton), which is 101.4px
  -- at mono-10 and Theme.Scale() 1.3 (JetBrains Mono ~0.6em/char -> 7.8px/char) -- a button
  -- sized for "REFRESH" alone would have let that overflow its own edges into the filter chip
  -- beside it.
  refreshButton:SetSize(104, 26); refreshButton:SetPoint("TOPRIGHT", 0, -30); refreshButton:SetLabel("REFRESH")
  container.refreshButton = refreshButton
  -- Wrapped, not passed directly: OnClick hands the handler (self, button, down),
  -- so GC.Sell.Refresh would receive the button as its `automatic` flag -- truthy
  -- -- and every press would take the stand-aside path that exists for the timer.
  -- The button would have gone on doing nothing, which is the bug this argument
  -- was added to fix.
  refreshButton:SetScript("OnClick", function() GC.Sell.Refresh() end)
  local labels = { all = "ALL", goldcap = "GC", missing_cost = "MISSING COST",
    sellable = "IN BAGS", listed = "LISTED" }
  -- missing_cost is 96, not 82: "MISSING COST" is 93.6px at mono-10 and Theme.Scale() 1.3
  -- (JetBrains Mono ~0.6em/char -> 7.8px/char) -- 82 let it overflow the chip's own edges.
  local widths = { missing_cost = 96, sellable = 56, listed = 52, all = 36, goldcap = 36 }
  local previous = refreshButton
  -- The active filter must be visible on the chip itself: SetVariant, never a second
  -- overlaid button (one control, two variants -- see addon/AGENTS.md on buttons).
  local function paintFilterChips()
    for mode, chip in pairs(container.filterButtons) do
      chip:SetVariant(mode == filterMode and "active" or "ghost")
    end
  end
  container.filterButtons = {}
  -- "AH" was a provenance filter (units GoldCap saw arrive by mail) sitting
  -- where a player expected "my auctions". The two useful cuts of this list are
  -- what is in the bags and what is already up; provenance stays on the tooltip.
  for _, mode in ipairs({ "missing_cost", "listed", "sellable", "goldcap", "all" }) do
    local button = Theme.Button(container, "ghost", "badge")
    button:SetSize(widths[mode] or 36, 20); button:SetPoint("RIGHT", previous, "LEFT", -2, 0); button:SetLabel(labels[mode])
    button:SetScript("OnClick", function() filterMode = mode; paintFilterChips(); renderRows() end)
    container.filterButtons[mode] = button
    previous = button
  end
  paintFilterChips()
  -- The posting queue control: the toolbar's own left end, opposite Refresh/the filter chips.
  -- "POST N" (its own count, so the number is on the button a click actually is), a label
  -- beside it naming the item and unit price that click will post -- a blind click is not one a
  -- seller should be asked to make -- and a held-back indicator with a tooltip that explains,
  -- in words, everything GC.PostQueue.Build held back. See paintQueueButton for how all three
  -- are painted, and onQueueClick for what a click does.
  local queueButton = Theme.Button(container, "primary", "plaque")
  -- 136, not 110: matches cancelButton below, sized for its own widest label ("NOTHING TO
  -- CANCEL", 132.6px at mono-10 and Theme.Scale() 1.3 -- JetBrains Mono ~0.6em/char ->
  -- 7.8px/char) -- a narrower button let "NOTHING TO POST" spill past its own borders.
  queueButton:SetSize(136, 26)
  queueButton:SetPoint("TOPLEFT")
  queueButton:SetScript("OnClick", function() onQueueClick() end)
  container.queueButton = queueButton

  local queueLabel = Theme.Num(container, 10)
  queueLabel:SetPoint("LEFT", queueButton, "RIGHT", 8, 0)
  queueLabel:SetJustifyH("LEFT")
  queueLabel:SetWordWrap(false)
  container.queueLabel = queueLabel

  local queueHeldBack = Theme.Num(container, 9)
  queueHeldBack:SetJustifyH("LEFT")
  setColor(queueHeldBack, Theme.color.fgDim)
  -- Both anchors set below, once its row-2 position and the ALL chip it abuts exist -- see the
  -- row-1 bounding block after the cancel cluster (M5: RIGHT-bound against the ALL chip, or a
  -- long held-back count ran under the filter chips at narrow widths).
  queueHeldBack:Hide()
  container.queueHeldBack = queueHeldBack

  -- A FontString cannot take mouse scripts (see the header-cell hit frames a little further
  -- down for the same fix) -- this invisible frame over the label is what actually raises the
  -- tooltip. Content is read from queueSkipped live, at hover time, rather than baked in when
  -- the label's text was last set, so it can never go stale between two renders.
  local queueHeldBackHit = CreateFrame("Frame", nil, container)
  queueHeldBackHit:SetAllPoints(queueHeldBack)
  queueHeldBackHit:EnableMouse(true)
  queueHeldBackHit:Hide()
  queueHeldBackHit:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Held back from the queue", 1, 0.82, 0)
    if #queueSkipped == 0 then
      GameTooltip:AddLine("Nothing is being held back.", 0.85, 0.85, 0.85, true)
    else
      for _, skip in ipairs(queueSkipped) do
        GameTooltip:AddLine(("%s — %s"):format(skip.itemName or "Item",
          QUEUE_SKIP_TEXT[skip.reason] or "not ready to post"), 0.85, 0.85, 0.85, true)
      end
    end
    GameTooltip:Show()
  end)
  queueHeldBackHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  container.queueHeldBackHit = queueHeldBackHit

  paintQueueButton() -- honest empty/disabled state before the very first compose ever runs

  -- The cancel queue control: row 1's right end, the far side of the row from Post -- the two
  -- queue actions are siblings, but a destructive control does not belong ADJACENT to a
  -- non-destructive one. Danger when it can burn a deposit, ghost when idle -- still the
  -- quieter look next to POST. See paintCancelButton for the states and onCancelQueueClick
  -- for what a click does (and, more importantly, does not) do.
  local cancelButton = Theme.Button(container, "ghost", "plaque")
  -- 136 for the same reason as the Post button: "NOTHING TO CANCEL" (132.6px at mono-10 and
  -- Theme.Scale() 1.3) must fit inside.
  cancelButton:SetSize(136, 26)
  cancelButton:SetPoint("TOPRIGHT")
  cancelButton:SetScript("OnClick", function() onCancelQueueClick() end)
  container.cancelButton = cancelButton

  local cancelHeldBack = Theme.Num(container, 9)
  cancelHeldBack:SetJustifyH("LEFT")
  setColor(cancelHeldBack, Theme.color.fgDim)
  cancelHeldBack:SetPoint("RIGHT", cancelButton, "LEFT", -8, 0)
  cancelHeldBack:Hide()
  container.cancelHeldBack = cancelHeldBack

  -- Same FontString-cannot-take-mouse-scripts fix as the posting queue's held-back label.
  local cancelHeldBackHit = CreateFrame("Frame", nil, container)
  cancelHeldBackHit:SetAllPoints(cancelHeldBack)
  cancelHeldBackHit:EnableMouse(true)
  cancelHeldBackHit:Hide()
  cancelHeldBackHit:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Held back from cancelling", 1, 0.82, 0)
    if #cancelSkipped == 0 then
      GameTooltip:AddLine("Nothing is being held back.", 0.85, 0.85, 0.85, true)
    else
      for _, skip in ipairs(cancelSkipped) do
        GameTooltip:AddLine(("%s — %s"):format(skip.itemName or "Item",
          QUEUE_SKIP_TEXT[skip.reason] or "not ready to cancel"), 0.85, 0.85, 0.85, true)
      end
    end
    GameTooltip:Show()
  end)
  cancelHeldBackHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  container.cancelHeldBackHit = cancelHeldBackHit

  -- Row-1 bounding, settable only now that the cancel cluster exists: the head label
  -- stretches between the Post button and the cancel cluster, so a long item name TRUNCATES
  -- instead of running under the controls to its right -- exactly the collision the old
  -- one-row toolbar shipped. The post queue's own held-back count does NOT sit here: two
  -- identical "N held back" strings side by side (one the post queue's, one the cancel
  -- queue's) read as one meaningless phrase, so the post one moves to row 2's empty left
  -- end, under the cluster it belongs to, and says which queue it is about in words.
  queueLabel:SetPoint("RIGHT", cancelHeldBack, "LEFT", -12, 0)
  queueHeldBack:SetPoint("TOPLEFT", 0, -35)
  -- M5: RIGHT-bound against the ALL chip -- the leftmost of the filter chips, and the last
  -- one built by the chain above -- with no wrap, the same truncate-not-overflow fix
  -- queueLabel gets on row 1: without it a long held-back count ran under the chips at
  -- narrow widths and Theme.Scale() 1.3.
  queueHeldBack:SetPoint("RIGHT", container.filterButtons.all, "LEFT", -8, 0)
  queueHeldBack:SetWordWrap(false)

  paintCancelButton()

  -- The real keybinding (Bindings.xml, auto-loaded by the client, not listed in the .toc -- see
  -- that file) reaches into this exact field on the Sniper window frame, because Bindings.xml
  -- executes as its own isolated Lua chunk with no upvalues into this file. It calls the SAME
  -- Lua function the button's own OnClick calls above -- never Button:Click(), which both
  -- inherits the caller's taint and skips RegisterForClicks/the mouse-down handling (see the
  -- design document's own reasoning). A keybinding handler already runs synchronously inside a
  -- real hardware input event, which is what a protected post actually requires.
  f.GoldCapPostNext = onQueueClick

  container.summary = {}
  for i, stat in ipairs({ { "cost", "KNOWN COST" }, { "listed", "LISTED VALUE" }, { "profit", "EST. PROFIT" } }) do
    -- 3 cards * 156px pitch = 468, under the 520px content width at the 640px minimum window.
    local card = Theme.Card(container, Theme.color.panel, nil, true)
    card:SetSize(148, 40); card:SetPoint("TOPLEFT", (i - 1) * 156, -60)
    local label = Theme.Num(card, 9); label:SetJustifyH("LEFT")
    label:SetPoint("TOPLEFT", 10, -6)
    -- RIGHT-bound and non-wrapping: a FontString with LEFT/RIGHT bounds and no wrap truncates
    -- with an ellipsis instead of escaping the 148px card -- belt and suspenders now that
    -- updateSummary caps the profit card's own value at a plain "Unknown" itself, with the
    -- missing/partial detail moved to that card's hover tooltip instead of riding along in the
    -- text (which used to ellipsize into unreadable garbage at Theme.Scale() 1.3).
    label:SetPoint("TOPRIGHT", -10, -6); label:SetWordWrap(false)
    label:SetText(stat[2]); setColor(label, Theme.color.fgDim)
    local value = Theme.Num(card, 13, true); value:SetJustifyH("LEFT")
    value:SetPoint("TOPLEFT", 10, -18)
    value:SetPoint("TOPRIGHT", -10, -18); value:SetWordWrap(false)
    container.summary[stat[1]] = value
    if stat[1] == "profit" then
      -- A FontString cannot take mouse scripts, so the missing/partial detail that used to ride
      -- along in the value text (see updateSummary) gets the same invisible-hit-frame trick as
      -- queueHeldBackHit above: content is read from container.summaryProfitDetail live, at
      -- hover time, so the tooltip can never go stale between renders, and it stays hidden
      -- entirely once every position's cost is known.
      local hit = CreateFrame("Frame", nil, card)
      hit:SetAllPoints(card)
      hit:EnableMouse(true)
      hit:SetScript("OnEnter", function(self)
        if not GameTooltip or not container.summaryProfitDetail then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Est. profit", 1, 0.82, 0)
        GameTooltip:AddLine(container.summaryProfitDetail, 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Positions without a cost or a live price are excluded.",
          0.85, 0.85, 0.85, true)
        GameTooltip:Show()
      end)
      hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      container.summaryProfitHit = hit
    end
  end
  local header = CreateFrame("Frame", nil, container); header:SetPoint("TOPLEFT", 0, -106); header:SetPoint("TOPRIGHT", 0, -106); header:SetHeight(16); header.cells = {}
  header.itemInset = 26 -- line the ITEM heading up with the names, not with the icons
  for _, column in ipairs(COLUMNS) do
    local cell = Theme.Num(header, 9); cell:SetWordWrap(false); cell:SetText(({ item = "ITEM", cost = "COST / UNIT", listed = "LISTED", market = "MARKET / UNIT", profit = "PROFIT / UNIT", status = "WHAT TO DO", action = "", expand = "" })[column.key]); header.cells[column.key] = cell
    setColor(cell, Theme.color.fgDim)
    -- Headings must sit over their own numbers. createRow right-aligns every numeric cell, but
    -- these were left at the default left alignment, so each heading floated to the left edge
    -- of a right-aligned column and every value looked like it belonged to the column after it.
    cell:SetJustifyH(column.num and "RIGHT" or "LEFT")
    -- A FontString cannot take mouse scripts, so each heading gets an invisible hit frame over
    -- it. Every column here is a number a seller has to trust, so each one explains itself
    -- instead of expecting a one-word heading to carry the meaning.
    local help = HEADER_HELP[column.key]
    if help then
      local hit = CreateFrame("Frame", nil, header)
      hit:SetAllPoints(cell)
      hit:EnableMouse(true)
      explain(hit, help[1], help[2])
    end
  end
  -- Separates the column headings from the first row now that both read in the same mono
  -- font -- without it the header row visually fused with row 1.
  local rule = header:CreateTexture(nil, "ARTWORK")
  local bc = Theme.color.border
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
  layoutCells(header)
  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", 0, -124); scroll:SetPoint("BOTTOMRIGHT")
  -- Empty-state panel, mirroring the Deals board's own (SniperFrame.lua) exactly: parented to
  -- `scroll` (not `content`), living where the rows would be, never scrolling.
  local emptyText = Theme.Label(scroll, 12)
  emptyText:SetPoint("TOP", scroll, "TOP", 0, -ROW_HEIGHT * 2)
  emptyText:SetPoint("LEFT", scroll, "LEFT", Theme.pad.m * 3, 0)
  emptyText:SetPoint("RIGHT", scroll, "RIGHT", -Theme.pad.m * 3, 0)
  emptyText:SetJustifyH("CENTER")
  emptyText:SetWordWrap(true)
  emptyText:SetSpacing(4)
  emptyText:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  emptyText:Hide()
  container.emptyText = emptyText
  content = CreateFrame("Frame", nil, scroll); content:SetSize(ROW_WIDTH, ROW_HEIGHT); scroll:SetScrollChild(content)
  local dialog = CreateFrame("Frame", nil, container, "BackdropTemplate"); dialog:SetSize(270, 170); dialog:SetPoint("CENTER"); dialog:Hide(); container.costDialog = dialog
  -- The template was carried but never given a backdrop, a strata or a frame level, so this
  -- opened as bare floating widgets: the rows underneath showed straight through it, its own
  -- error text collided with them, and clicks aimed at the dialog landed on whatever row sat
  -- behind. Give it a real surface, lift it above the list, and let it swallow its own mouse.
  dialog:SetFrameStrata("DIALOG")
  dialog:SetFrameLevel((container:GetFrameLevel() or 0) + 50)
  dialog:EnableMouse(true)
  -- Rounded kit surface. card.png margin 24 <= 85 = half of the 170px edge. Regions on the
  -- dialog frame itself, not a child Card frame: a child frame would draw over the dialog's
  -- own FontStrings.
  local pc = Theme.color.panel
  local dialogBG = Theme.SlicedTexture(dialog, "BACKGROUND", Theme.MEDIA .. "card.png", { pc[1], pc[2], pc[3], 0.98 }, 24)
  dialogBG:SetAllPoints(dialog)
  local gc2 = Theme.color.gold
  local dialogEdge = Theme.SlicedTexture(dialog, "BORDER", Theme.MEDIA .. "ring.png", { gc2[1], gc2[2], gc2[3], 0.5 }, 24)
  dialogEdge:SetAllPoints(dialog)
  -- Which item, and how many units it is missing a cost for -- filled in by openCostDialog
  -- every time it opens, since the dialog is pooled across positions. Reserves two lines'
  -- worth of height: item names run long enough that one line is not always enough.
  dialog.header = Theme.Label(dialog, 11)
  dialog.header:SetPoint("TOPLEFT", 12, -10)
  dialog.header:SetPoint("TOPRIGHT", -12, -10)
  dialog.header:SetWordWrap(true)
  setColor(dialog.header, Theme.color.fg)
  dialog.quantity, dialog.unit, dialog.total = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate"), CreateFrame("EditBox", nil, dialog, "InputBoxTemplate"), CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
  -- Pushed down FIELD_LABEL_Y/FIELD_BOX_Y (was -12/-26) to leave room for the header above.
  -- Unit/Total are labelled "(gold)" -- explicitly, because the fields used to carry no unit
  -- at all and every amount typed here was read as bare copper.
  local FIELD_LABEL_Y, FIELD_BOX_Y = -40, -54
  for i, field in ipairs({ { dialog.quantity, "Quantity" }, { dialog.unit, "Unit cost (gold)" }, { dialog.total, "Total cost (gold)" } }) do
    local label = Theme.Label(dialog, 10); label:SetPoint("TOPLEFT", 12 + (i - 1) * 82, FIELD_LABEL_Y); label:SetText(field[2])
    field[1]:SetSize(70, 20); field[1]:SetPoint("TOPLEFT", 12 + (i - 1) * 82, FIELD_BOX_Y); field[1]:SetAutoFocus(false)
  end
  -- Live coin readout of exactly what Total will record, under the Total field itself. This
  -- is what makes the unit unambiguous no matter what the player assumed it was.
  dialog.totalPreview = Theme.Label(dialog, 10)
  dialog.totalPreview:SetPoint("TOPLEFT", 12 + 2 * 82, FIELD_BOX_Y - 24)
  dialog.totalPreview:SetPoint("TOPRIGHT", -12, FIELD_BOX_Y - 24)
  setColor(dialog.totalPreview, Theme.color.fgDim)
  dialog.error = Theme.Label(dialog, 10); dialog.error:SetPoint("TOPLEFT", 12, FIELD_BOX_Y - 44); setColor(dialog.error, Theme.color.red)
  local cancel = Theme.Button(dialog, "ghost", "badge"); cancel:SetSize(70, 20); cancel:SetPoint("BOTTOMLEFT", 12, 10); cancel:SetLabel("Cancel"); cancel:SetScript("OnClick", function() dialog:Hide() end)
  local confirm = Theme.Button(dialog, "primary", "badge"); confirm:SetSize(70, 20); confirm:SetPoint("BOTTOMRIGHT", -12, 10); confirm:SetLabel("Confirm"); confirm:SetScript("OnClick", function() confirmCostDialog(dialog) end)
  local function syncText(edit, text)
    dialog.syncing = true
    edit:SetText(text)
    dialog.syncing = false
  end
  -- All three handlers read/write GOLD text now (dialogGoldPositive / copperToGoldText), but
  -- do every comparison and every downstream write in COPPER -- the sync must stay exact in
  -- the unit RecordManual/RepairPendingManual actually store, not in the decimal the player
  -- is typing, or rounding in one direction and not the other would drift the two fields
  -- apart from what Confirm's own validation checks.
  dialog.unit:SetScript("OnTextChanged", function()
    if dialog.syncing then return end
    dialog.costMode = "unit"
    local q, unitCopper = dialogExactPositive(dialog.quantity), dialogGoldPositive(dialog.unit)
    if not q or not unitCopper then
      syncText(dialog.total, "")
      updateTotalPreview(dialog, nil)
      return setDialogError(dialog, "Enter an exact positive cost")
    end
    local totalCopper = safeMultiply(q, unitCopper)
    if not totalCopper then
      syncText(dialog.total, "")
      updateTotalPreview(dialog, nil)
      return setDialogError(dialog, "Enter an exact positive cost")
    end
    setDialogError(dialog)
    syncText(dialog.total, copperToGoldText(totalCopper))
    updateTotalPreview(dialog, totalCopper)
  end)
  dialog.quantity:SetScript("OnTextChanged", function()
    if dialog.syncing then return end
    local quantity = dialogExactPositive(dialog.quantity)
    if not quantity then
      if dialog.costMode == "unit" then syncText(dialog.total, "")
      elseif dialog.costMode == "total" then syncText(dialog.unit, "")
      else syncText(dialog.unit, ""); syncText(dialog.total, "") end
      updateTotalPreview(dialog, nil)
      return setDialogError(dialog, "Enter a whole quantity")
    end
    if dialog.maximum then
      local clamped = math.max(1, math.min(dialog.maximum, quantity))
      if clamped ~= quantity then syncText(dialog.quantity, tostring(clamped)); quantity = clamped end
    end
    if dialog.costMode == "unit" then
      local unitCopper = dialogGoldPositive(dialog.unit)
      local totalCopper = unitCopper and safeMultiply(quantity, unitCopper)
      if not totalCopper then
        syncText(dialog.total, "")
        updateTotalPreview(dialog, nil)
        return setDialogError(dialog, "Enter an exact positive cost")
      end
      syncText(dialog.total, copperToGoldText(totalCopper))
      updateTotalPreview(dialog, totalCopper)
      setDialogError(dialog)
    elseif dialog.costMode == "total" then
      local totalCopper = dialogGoldPositive(dialog.total)
      if not totalCopper then
        syncText(dialog.unit, "")
        updateTotalPreview(dialog, nil)
        return setDialogError(dialog, "Enter an exact positive cost")
      end
      syncText(dialog.unit, copperToGoldText(math.floor(totalCopper / quantity)))
      updateTotalPreview(dialog, totalCopper)
      setDialogError(dialog)
    end
  end)
  dialog.total:SetScript("OnTextChanged", function()
    if dialog.syncing then return end
    dialog.costMode = "total"
    local q, totalCopper = dialogExactPositive(dialog.quantity), dialogGoldPositive(dialog.total)
    if not q or not totalCopper then
      syncText(dialog.unit, "")
      updateTotalPreview(dialog, nil)
      return setDialogError(dialog, "Enter an exact positive cost")
    end
    syncText(dialog.unit, copperToGoldText(math.floor(totalCopper / q)))
    updateTotalPreview(dialog, totalCopper)
    setDialogError(dialog)
  end)
  -- OnSizeChanged fires once per pixel while the resize grip is being dragged -- as often as
  -- every frame -- and renderRows is not free: it walks the filtered position list and
  -- rebuilds every visible row. Layout (the width-driven column drop) is cheap and stays
  -- immediate; the row rebuild is coalesced to a single pass once the size has settled,
  -- rather than rebuilding the model up to 60 times a second while the grip is dragged.
  local resizeRenderToken = 0
  f:HookScript("OnSizeChanged", function(_, width)
    ROW_WIDTH = math.max(1, width - geometry.panelLeft - geometry.panelRightInset)
    content:SetWidth(ROW_WIDTH)
    layoutCells(header)
    resizeRenderToken = resizeRenderToken + 1
    local token = resizeRenderToken
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        if token == resizeRenderToken then renderRows() end
      end)
    else
      renderRows()
    end
  end)
end

-- Live diagnosis for a wedged pricing walk, straight from the client: /goldcap sellstate
-- prints the machine's actual state instead of leaving "PRICING…" to be guessed about.
-- Registered here (not Core/Init.lua) because every field it reads is this file's own.
GC.slashHandlers = GC.slashHandlers or {}
GC.slashHandlers.sellstate = function()
  local pending = refresh.pending
  GC.Print(("sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"):format(
    tostring(refresh.phase), #refresh.queue, refresh.index or 0, refresh.skipped or 0,
    time() - (refresh.progressAt or 0),
    pending and (" · pending item %s for %ds"):format(tostring(pending.itemID), time() - pending.at) or ""))
  local blocking = GC.Sniper and (GC.Sniper.IsSearchCritical or GC.Sniper.IsBusy)
  local rested = 0
  for _, at in pairs(emptyAnswers) do
    if time() - at <= EMPTY_ANSWER_AGE then rested = rested + 1 end
  end
  GC.Print(("throttle ready=%s · sniper busy=%s · empty answers resting=%d"):format(
    tostring(driver and driver.isReady and driver.isReady() or false),
    tostring(blocking and blocking() or false), rested))
  -- Every row without a market price, and the EXACT reason the walk is not asking about it --
  -- mirrors uniqueQuoteItemIDs' own membership rules, so a "—" can always be explained.
  local shown = 0
  for _, position in ipairs(positions) do
    if position.displayMarketUnit == nil and position.itemID and shown < 12 then
      local inBags = type(position.bagQty) == "number" and position.bagQty > 0
      local listed = type(position.listedQty) == "number" and position.listedQty > 0
      local commodity = type(position.positionKey) == "string"
        and position.positionKey:find("commodity:", 1, true) == 1
      local restingAt = emptyAnswers[position.itemID]
      local why
      if position.unresolved and not commodity then
        why = "identity unresolved (variant item -- not priced by design)"
      elseif not (inBags or listed) then
        why = "no stock in bags or listed -- nothing to price for"
      elseif type(restingAt) == "number" and (time() - restingAt) <= EMPTY_ANSWER_AGE then
        why = ("AH answered empty %ds ago"):format(time() - restingAt)
      else
        why = "due -- will be asked next pass"
      end
      shown = shown + 1
      GC.Print(("  %s (%d): %s"):format(tostring(position.itemName or "?"), position.itemID, why))
    end
  end
end
