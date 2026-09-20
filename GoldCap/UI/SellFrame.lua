local _, GC = ...

GC.Sell = GC.Sell or {}

-- Labels for the posting-queue keybinding (Bindings.xml, auto-loaded by the client -- see that
-- file for the binding itself and GC.Sell.Attach below for the handler it calls). Purely
-- cosmetic: the Key Bindings UI falls back to the raw action name if these are missing, so the
-- feature works without them, but a human label is worth the two lines. `_G.` explicit, not a
-- bare assignment, so this is a plain field write on the standard `_G` table rather than a new
-- global luacheck would need to be told about.
_G.BINDING_HEADER_GOLDCAP = "GoldCap"
-- Assigned through GC.SellUI.RefreshBindingName, called from Init once the locale is
-- active. Resolving GC.L here would capture the English fallback: this file loads long
-- before ApplyLocale picks a language, so the binding would read English forever.
function GC.SellUI_RefreshBindingName()
  _G.BINDING_NAME_GOLDCAP_POST_NEXT = GC.L["Post the next queued item"]
end

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
-- How long a yielded pricing walk (purchase in flight, throttle window closed) waits before
-- asking again from the same queue position -- see advanceQuote's retryLater.
local QUOTE_RETRY_SECONDS = 2
-- REPOST_ARM_SECONDS is the deposit guard: how long after the first click a confirming second
-- click does not count. It was 3, and three seconds of a greyed-out button that still reads
-- "Cancel lot?" is indistinguishable from a broken control -- reported from a live client as
-- "it glows like that for ages and then may not press at all". One second still defeats what
-- the guard is actually for, an accidental double-click, which lands inside half of it.
--
-- REPOST_TIMEOUT_SECONDS is the other half of that report. At 10 it gave a player seven usable
-- seconds to read "lose its deposit" and decide, after which the arm silently reverted to
-- "Repost" and the next click armed it all over again. Twenty leaves nineteen, and the window
-- still closes rather than staying armed across a render or a walk.
local POST_TIMEOUT_SECONDS, REPOST_ARM_SECONDS, REPOST_TIMEOUT_SECONDS = 8, 1, 20
-- The in-flight cancel is a SERVER round trip and gets its own, longer watchdog. It used to
-- share REPOST_TIMEOUT_SECONDS, so a cancel the auction house took more than ten seconds to
-- confirm was announced as "Cancel timed out" -- over a lot that had in fact been cancelled.
-- That is the worst thing this control can say: it tells the player the opposite of what
-- happened to their gold. Waiting longer before giving up is the honest side to err on.
local REPOST_CANCEL_TIMEOUT_SECONDS = 30
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
  -- The three the posting deck is really about: what this stack fetches at the price GoldCap
  -- would list it at, that price, and how it compares with what it cost. They replaced COST /
  -- MARKET / PROFIT / WHAT TO DO on the row -- four columns whose headings, translated, ran
  -- into one another at every width ("РИНОК / ШТ ПРИБУТОК / ШТ ЩО РОБИТИ", seen in game).
  -- Those four facts did not disappear: they are what the drawer is made of.
  -- PRICE leads and carries a second line -- where that price stands in the live book -- so it
  -- is wide enough for five queue marks and "12 340 ahead" beside them. MARGIN is no longer a
  -- column: it is the line under YOU GET, the figure it qualifies.
  { key = "price", w = 132, min = 116, num = true, bold = true },
  { key = "gross", w = 100, min = 84, num = true, bold = true },
  -- `min` is what a numeric column shrinks to before anything is DROPPED. Without it the
  -- shedding order jumped straight from "everything at full width" to "COST/UNIT is gone",
  -- and at the default 720-wide window it landed on the gone side: a seller looking at a
  -- market price and a profit with nothing on screen saying what either was measured against.
  { key = "cost", w = 92, min = 72, num = true },
  { key = "listed", w = 88, num = true, optional = true },
  { key = "market", w = 92, min = 72, num = true },
  { key = "profit", w = 96, min = 76, num = true, bold = true },
  { key = "status", w = 176 },
  { key = "action", w = 88 },
}

local container, content, detailContent, statusOwner
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
-- itemIDs whose OWNED lots could not be told commodity-from-item yet (classifyOwnedAuctions).
-- Read by GC.Sell.OnItemKeyInfo, which re-keys those lots the moment the client learns the
-- answer -- without it a lot stayed filed under a guessed key until the next owned-auctions
-- query happened to come round.
local ownedAwaitingKind = {}
-- Still "all": hiding the player's live listings behind a filter to answer "what
-- can I list" would trade one blind spot for another. What changed is the order
-- -- everything postable now sorts to the top (see SellViewModel.Order) -- and a
-- Sellable chip for narrowing to it deliberately.
-- Prices the seller typed, keyed by position. Deliberately NOT persisted and deliberately not
-- a second source of truth about what to list at: BuildPostPlan is still the one place a post
-- price is decided, and this is only what gets handed to it. Cleared when the position is
-- posted (the stock leaves the bags and the row with it) or when the box is emptied.
local priceOverrides = {}

-- "post" and "listed" are the two DECKS this tab is built on (SellViewModel.Deck). "queue" and
-- "cancelqueue" are transient FOCUS states the queue controls set for a single render, so their
-- head entry lands on row 1 -- a deck is what the switch paints, a focus state is not.
local expanded, filterMode = {}, "post"
-- Whether the posting deck's "not on hand" fold is open. The player's to set and kept for the
-- session: a fold that shut itself on every refresh would be a control that does not work.
local showNotOnHand = false
-- The two chips beside the deck switch, keyed by the same stable ids CHIP_IDS carries. Flags
-- that NARROW whichever deck is up rather than replacing it -- which is exactly what the five
-- mutually-exclusive chips this replaced could not express -- so both can be on at once.
local chips = { ready = false, nocost = false }
-- Where each position sits, remembered across renders (SellViewModel.Settle). Thrown away only
-- when the PLAYER asks for a new order -- Refresh, a deck change, a chip -- never by a quote
-- landing, an owned-auction scan or the walk's own repeat. Those change numbers, not places.
local rowPlaces = {}

-- Labels for the deck switch and the two chips. Parallel tables, exactly like
-- PRICE_CHIP_LABELS/PRICE_CHIP_IDS further down and for both of the same reasons: the contract
-- scanner reads EVERY literal inside an @localised-keys table as a key, so an id sitting in the
-- same table would be collected as a translatable string nobody ever shows; and the id is what
-- the code switches on, never the label, which a translation changes out from under it.
-- @localised-keys
local DECK_LABELS = {
  "TO POST %d", "MY LOTS %d",
}
local DECK_IDS = { "post", "listed" }
-- @localised-keys
local CHIP_LABELS = {
  "READY", "NO COST",
}
local CHIP_IDS = { "ready", "nocost" }
-- "READY" is 5 chars and "NO COST" 7, but both carry the rounded badge's own inset: 92/76 match
-- what the five chips they replaced used for labels of the same length.
local CHIP_WIDTHS = { 92, 76 }
-- `priority` holds items a CLICK asked about while a pass was already running (Post/Repost on a
-- row whose quote had aged out). Deliberately outside `queue`: splicing into that array put the
-- item in a slot the walk then stepped over -- and a queue rebuilt by beginQuoteWalk, which is
-- what the owned-auctions phase ends in, dropped it outright. advanceQuote drains this before
-- the queue's own next step, so the row the player is standing on is answered first.
local refresh = { generation = 0, phase = "idle", queue = {}, index = 0, pending = nil, awaiting = nil,
  drain = {}, priority = {} }
local quoteTimeoutToken, keyTimeoutToken = 0, 0
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
-- Forward-declared for the same reason: scanBagStock (above) calls it, and it is defined beside
-- the classifier whose store it keeps within bounds.
local pruneCommodityKinds
-- Forward-declared for the same reason: composePositions hands the store to
-- SellPositions.Build (which uses it to settle a commodity-versus-item contradiction over one
-- itemID), and it is defined much further down, beside the classifier that fills it.
local commodityKindCache

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
  if row.action then row.action:Enable(); row.action.helpKey = "Post"; row.action:SetLabel(GC.L["Post"]) end
end

local function restoreRepostRow(row)
  if not row then return end
  row.repostStage, row.repostReady = nil, nil
  if row.action then row.action:Enable(); row.action.helpKey = "Repost"; row.action:SetLabel(GC.L["Repost"]) end
end

local function restoreRemoveRow(row)
  if not row then return end
  row.removeStage = nil
  if row.action then row.action:Enable(); row.action.helpKey = "Remove"; row.action:SetLabel(GC.L["Remove"]) end
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
      and (GC.L["PRICING %d/%d"]):format(refresh.index, #refresh.queue) or GC.L["PRICING…"]
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
  -- And in the dock, under the bulk action: the toolbar line above is a window's width from
  -- every control on this tab, which is why REFRESH, POST and each row button had to grow a
  -- copy of the state. Said here, it is said beside the button that was just pressed.
  if container and container.dockStatus then container.dockStatus:SetText(text or "") end
  paintRefreshButton()
  paintQueueButton()
  -- The cancel control is driven from here for the same reason the queue control is: renderRows
  -- DEFERS for the whole time a repost is armed, so a render cannot be relied on to keep it in
  -- step with the arm/confirm dance. It was missing, and the one transition that mattered most
  -- went unpainted -- the footer still read "CANCEL LOT?", still enabled, while the cancel it
  -- named was already on the wire.
  paintCancelButton()
end

local function setColor(fontString, color)
  if fontString and color then fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
end

-- Gold-carrying amounts render as plain text ("65g24s"), not GetCoinTextureString's coin
-- icons: the icon escapes are wide, and a truncated FontString cuts them MID-ESCAPE, which
-- painted lot labels as "bought 17 Aug at 1|..." in game. Sub-gold amounts keep the icons,
-- where they fit. Mirrors the Deals board's formatColumnAmount rule.
local function formatAmount(amount)
  if amount == nil then return GC.L["Unknown"] end
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

-- Theme.color.goldHi as an inline escape, for the one number on the stock line that is money.
-- The line under an item name is a run-on -- count, then listed, then what a unit cost -- drawn
-- at size 10 in a single uniform weight, and the owner of a live client said of the cost he had
-- asked to be shown: "I did not even see it, it just sits there." He was right. It is the figure
-- the PRICE / UNIT column two feet to the right is meant to be compared against, and it carried
-- no more emphasis than the word "in". Colouring the amount (never the words around it) gives
-- the eye something to land on without adding a row, a column or a line.
local MONEY_HEX = "|cffe8c15a"

-- The one-word state a row wears at the end of its stock line, and only when something is off:
-- a row that is ready says nothing. It replaces the WHAT TO DO column, which no deck had room
-- for at any width, so the reason a row was left out of the queue was one hover away on a
-- counter in the footer and nowhere on the row it was about. Keyed by GC.PostQueue's and
-- GC.CancelQueue's own reason tokens; `alarm` paints red, `wait` the watch blue, the rest dim.
-- @localised-keys
local ROW_TAG_TEXT = {
  below_breakeven = "below cost",
  no_fresh_price = "needs a price",
  unresolved_identity = "stack not identified",
  advised_hold = "hold",
}
local rowTag
do
local ROW_TAG_TONE = { below_breakeven = "alarm", no_fresh_price = "wait" }

local function inlineColor(color, text)
  return ("|cff%02x%02x%02x%s|r"):format(
    math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5), text)
end

-- The tag itself, already coloured, or "" for a row with nothing to say. `reason` is the skip
-- token the deck's queue gave this position, if it skipped it. Money leaving silently outranks
-- everything: a lot standing far below market is the one thing on the row that has to be read
-- first, and it used to be written into a column no deck shows.
--
-- A function of its own rather than lines inside renderRows for a reason the client enforces
-- and busted does not: WoW runs Lua 5.1, which caps a function at 60 upvalues, and renderRows
-- sits close enough to that cap that three more tables put the whole file out of action.
rowTag = function(position, reason, notOnHand)
  local tag, tone
  if position.facts and position.facts.underpriced then
    tag, tone = GC.L["far below market"], "alarm"
  elseif reason then
    tag, tone = ROW_TAG_TEXT[reason] and GC.L[ROW_TAG_TEXT[reason]] or nil, ROW_TAG_TONE[reason]
  end
  local uncosted = math.max(0, (position.exposureQty or 0) - (position.knownQty or 0))
  if not tag and position.coverage ~= "COMPLETE" and not notOnHand and uncosted > 0 then
    tag = (GC.L["no cost for %d"]):format(uncosted)
  end
  if not tag then return "" end
  local color = tone == "alarm" and Theme.color.red or tone == "wait" and Theme.color.watch
    or Theme.color.fgDim
  return "  " .. inlineColor(color, tag)
end
end -- do: keeps the helpers above out of the file's own local count (Lua 5.1 allows 200)

-- Skip reasons in words a seller would actually read, never GC.PostQueue's own internal token
-- -- see that module's own `evaluate` comment for what each one means structurally. A silently
-- short queue is the same lie as a silently short deals list; naming the reason in plain words
-- is what keeps it from being a DIFFERENT lie instead.
-- @localised-keys: literals in this table ARE GC.L keys, looked up where the table is
-- READ, not here. This is file scope, and GC.L only resolves once ApplyLocale has run
-- at ADDON_LOADED -- a lookup here captures the English fallback and keeps it in every
-- language. The table has to close with a `}` on its own line: that is where the
-- contract spec's scanner stops.
local QUEUE_SKIP_TEXT = {
  no_fresh_price = "needs a fresh price -- press Refresh",
  below_breakeven = "would sell at a loss",
  unresolved_identity = "GoldCap can't pin down which bag stack this is",
  -- The cancel queue's own reasons (GC.CancelQueue.Build): a cancel burns a deposit, so a
  -- held-back listing needs its why stated even more than a held-back post does.
  advised_hold = "relisting now would lock in a loss or a stall -- hold",
  no_advice = "cost basis incomplete -- set costs to get repost advice",
}

-- Three different emptinesses needing three different next moves, where the old copy had one
-- sentence ("No items match this filter") that answered none of them: a deck that is genuinely
-- empty, a chip that emptied it, or the OTHER deck holding everything. Read live from the deck
-- and chip state rather than passed in, so it can never disagree with what the switch is
-- painting.
local function emptyDeckText()
  if filterMode == "listed" or filterMode == "cancelqueue" then
    return GC.L["No live auctions on this character"]
  end
  if chips.ready then return GC.L["Nothing is priced yet - the Auction House is still answering"] end
  if chips.nocost then return GC.L["Every position in your bags already has a cost on record"] end
  return GC.L["Nothing in your bags to list"]
end

-- The real body, promised by the forward declaration above. Needs formatCell (just above) and
-- container/queueEntries/queueSkipped/postingRow (all declared well above this point), so it
-- could not be written any earlier than here.
paintQueueButton = function()
  local button, label = container and container.queueButton, container and container.queueLabel
  if not button then return end
  local heldBack, heldBackHit = container.queueHeldBack, container.queueHeldBackHit
  -- The post queue is the POST deck's bulk action and shares the footer slot with the cancel
  -- queue's. Hidden, not disabled, on the other deck: a disabled control invites a click that
  -- can never work, and this one belongs to a screen the player is not on.
  if filterMode == "listed" or filterMode == "cancelqueue" then
    button:Hide()
    if label then label:SetText(""); label:Hide() end
    if heldBack then heldBack:Hide() end
    if heldBackHit then heldBackHit:Hide() end
    return
  end
  button:Show()
  if label then label:Show() end
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
      button:SetLabel(GC.L["CONFIRM"]); button:Enable()
    else
      button:SetLabel(GC.L["POSTING…"]); button:Disable()
    end
    if label and head then label:SetText(head.itemName or "") end
  elseif not head then
    button:SetLabel(GC.L["NOTHING TO POST"])
    button:Disable()
    if label then label:SetText("") end
  else
    button:SetLabel((GC.L["POST %d"]):format(#queueEntries))
    button:Enable()
    if label then label:SetText(("%s @ %s"):format(head.itemName or GC.L["Item"], formatCell(head.unitPrice))) end
  end
  if heldBack then
    if #queueSkipped > 0 then
      -- "from posting", because the cancel queue paints an identical counter near its own
      -- button (paintCancelButton below) and two bare "N held back" strings on one screen
      -- would leave the reader guessing which queue each one describes.
      heldBack:SetText((GC.L["%d held back from posting"]):format(#queueSkipped))
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
  -- The cancel queue's half of the same footer slot -- see paintQueueButton's own comment.
  if container and container.cancelButton
      and filterMode ~= "listed" and filterMode ~= "cancelqueue" then
    container.cancelButton:Hide()
    if container.cancelHeldBack then container.cancelHeldBack:Hide() end
    if container.cancelHeldBackHit then container.cancelHeldBackHit:Hide() end
    return
  end
  if container and container.cancelButton then container.cancelButton:Show() end
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
      button:SetLabel(GC.L["CANCELLING…"]); button:Disable()
    elseif sameHead and repostingRow.repostStage == "armed" then
      button:SetLabel(GC.L["CANCEL LOT?"])
      if repostingRow.repostReady then button:Enable() else button:Disable() end
    else
      button:SetLabel((GC.L["CANCEL %d"]):format(#cancelEntries)); button:Disable()
    end
  elseif not head then
    button:SetVariant("ghost")
    button:SetLabel(GC.L["NOTHING TO CANCEL"])
    button:Disable()
  else
    button:SetVariant("danger")
    button:SetLabel((GC.L["CANCEL %d"]):format(#cancelEntries))
    button:Enable()
  end
  if heldBack then
    if #cancelSkipped > 0 then
      heldBack:SetText((GC.L["%d held back"]):format(#cancelSkipped))
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
-- The one line a seller needs before reading a single price: who is actually under me, and
-- how much stock is sitting there. `cheapestCompeting` subtracts the player's own units from a
-- shared price level rather than dropping the level (see CheapestCompetingUnit), so this is
-- the price to beat, not the cheapest row on screen.
local function bookHint(book)
  if type(book) ~= "table" then return "" end
  local parts = {}
  if book.cheapestCompeting then
    parts[#parts + 1] = (GC.L["cheapest not yours %s"]):format(formatCell(book.cheapestCompeting))
  end
  parts[#parts + 1] = (GC.L["%d units · %d prices"]):format(book.totalUnits or 0, book.levels or 0)
  -- Said once, here, rather than on every row: the rows carry the two facts in COLOUR (the
  -- marker glyphs the design drew are not in the bundled face and rendered as empty boxes),
  -- and a colour nobody explained is a colour nobody reads.
  local mine = false
  for i = 1, #(book.rows or {}) do if book.rows[i].mine then mine = true break end end
  if book.yourRow and mine then
    parts[#parts + 1] = GC.L["gold is where your price lands, blue is already yours"]
  elseif book.yourRow then
    parts[#parts + 1] = GC.L["gold is where your price lands"]
  elseif mine then
    parts[#parts + 1] = GC.L["blue is already yours"]
  end
  return table.concat(parts, " · ")
end

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
  if recommendation.belowCost then text = text .. GC.L[" · below cost"] end
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

-- One key per position for the typed price. The scope key carries the character and region as
-- well, which is what keeps a price chosen on one character from following the same item onto
-- another; positionKey alone is the fallback for a position composed before a scope exists.
local function overrideKey(position)
  if type(position) ~= "table" then return nil end
  -- positionKey, not scopeKey: the decoration (Core/SellPositions) has to key the same table,
  -- and it runs over positions that do not all carry a scope yet. The Sell tab composes for
  -- one character at a time anyway, so this cannot leak a price across characters in practice.
  local key = position.positionKey
  return type(key) == "string" and key ~= "" and key or nil
end

-- What Post would list this position at right now: the seller's own number when they have
-- given one, otherwise whatever GoldCap worked out. Both go through the SAME silver-grid
-- rounding BuildPostPlan applies, so the figure in the box is the figure that gets sent.
local function effectivePostUnit(position)
  local key = overrideKey(position)
  local chosen = key and priceOverrides[key] or nil
  local rec = type(position.postRecommendation) == "table" and position.postRecommendation.unit or nil
  local unit = chosen or rec
  if not exact(unit) or unit <= 0 then return nil, chosen ~= nil end
  return (GC.Flips.SilverUp and GC.Flips.SilverUp(unit)) or unit, chosen ~= nil
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
  return (GC.L["Item %d"]):format(itemID or 0)
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
    -- GC.Util.ThrottleReady, not the raw flag: see its comment for the stuck-flag client.
    isReady = function()
      if GC.Util and GC.Util.ThrottleReady then return GC.Util.ThrottleReady() end
      return C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and C_AuctionHouse.IsThrottledMessageSystemReady()
    end,
    -- isReady answers whether a send is permitted; this takes the permit, once, immediately
    -- before a query goes out. Under a throttle flag that has stopped changing it is what keeps
    -- this walk moving at all: the permit used to be one global one, and the Sniper's arbiter
    -- runs immediately ahead of this tab on every ready event, so the tab never saw one.
    claimSend = function()
      if GC.Util and GC.Util.ClaimThrottleSend then return GC.Util.ClaimThrottleSend("sell") end
      return true
    end,
    keyInfo = function(itemID)
      return C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
    end,
    send = function(itemID)
      local key = C_AuctionHouse.MakeItemKey(itemID)
      local info = C_AuctionHouse.GetItemKeyInfo(key)
      -- Blizzard's pane may open this item's buy page in answer; that page is ours, not a buy.
      if GC.AuctionHouseTab and GC.AuctionHouseTab.NoteAddonSearch then GC.AuctionHouseTab.NoteAddonSearch() end
      if info and info.isCommodity then
        if GC.Util and GC.Util.Trace then GC.Util.Trace("sell: search") end
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
    -- Is the client holding a COMPLETE reply for this key, or merely whatever result set the
    -- last search left in the slot? GetNum*SearchResults answers the second question only, and
    -- the results events this file listens to are raised by the Sniper's searches as well as
    -- our own -- so a zero read is not proof the auction house said "nothing listed". This is
    -- the proof; see quoteResolved, which will not gag an item without it.
    --
    -- Returns TRUE when the client offers no way to ask. A missing API is not evidence of
    -- anything, and failing that case closed would gag nothing ever again.
    hasFullResults = function(itemID, commodity)
      if not C_AuctionHouse then return true end
      if commodity then
        if not C_AuctionHouse.HasFullCommoditySearchResults then return true end
        return C_AuctionHouse.HasFullCommoditySearchResults(itemID) == true
      end
      if not (C_AuctionHouse.HasFullItemSearchResults and C_AuctionHouse.MakeItemKey) then return true end
      return C_AuctionHouse.HasFullItemSearchResults(C_AuctionHouse.MakeItemKey(itemID)) == true
    end,
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

  -- A craft happens away from the auction house, where the client will not say whether the
  -- item sells as a commodity, so Core/CraftCapture.lua records those batches keyless rather
  -- than filing them under a guessed key. The bag walk immediately above has just put that
  -- question to GetItemKeyInfo -- the authority itself -- so this is where a crafted batch
  -- stops being keyless, and it runs before the batches are read below so the cost shows on
  -- this very pass. BindItemOnly cannot serve here: it is for legacy item-only evidence and
  -- requires the item to have been LISTED, which stock the player has only just made has not.
  if GC.Acquisitions and GC.Acquisitions.BindClassifiedIdentity and scope then
    local classified, ambiguous = {}, {}
    for _, stock in ipairs(bagStock) do
      if type(stock.positionKey) == "string" and stock.positionKey ~= "" then
        if classified[stock.itemID] and classified[stock.itemID] ~= stock.positionKey then
          ambiguous[stock.itemID] = true
        end
        classified[stock.itemID] = stock.positionKey
      end
    end
    for _, batch in ipairs(GC.Acquisitions.GetActive(scope)) do
      -- Two stacks of one item under different keys means the bags cannot say which one this
      -- batch is; leaving it keyless is the honest answer.
      if not batch.positionKey and classified[batch.itemID] and not ambiguous[batch.itemID] then
        GC.Acquisitions.BindClassifiedIdentity(batch.id, classified[batch.itemID], scope)
      end
    end
  end
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
    -- "Does this item sell as a commodity", straight from C_AuctionHouse.GetItemKeyInfo and
    -- remembered. Build cannot reach SavedVariables and must not; it is handed the answer so
    -- it can settle an activity set holding `commodity:X` and `item:X:...` for one itemID --
    -- provable corruption that a purchase record can only settle when there IS a purchase.
    commodityKinds = commodityKindCache and commodityKindCache() or nil,
    -- A price the seller typed has to reach the decoration, not just the post: the PROFIT
    -- column, the posting queue's own label and the plan all read the recommendation, and
    -- this file has twice shipped a bug where the price shown and the price sent were two
    -- different numbers.
    chosenUnits = priceOverrides,
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
  -- The deck switch's two counts are read straight off `positions`, so they have to be
  -- repainted whenever `positions` moves. `container.paintDeckSwitch` was exported for exactly
  -- this and then never called by anybody: the switch was painted once at construction, over an
  -- empty table, and after that only when the player clicked one of its own two buttons. So it
  -- sat at "TO POST 0 · MY LOTS 0" above a full list -- and that zero is what made a fixed
  -- bag-stock bug look like it was still broken, twice, to two different readers.
  if container and container.paintDeckSwitch then container.paintDeckSwitch() end
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
-- One entry per rested item, `{ at = when, answered = did the auction house actually reply }`.
-- The second field is the whole point. A request that timed out and a reply that genuinely
-- carried no listings both earn the item a rest -- re-asking either on the very next pass is
-- what burned the walk's slots -- but only one of them is an ANSWER, and only an answer may be
-- shown to the player as "none"/"Nothing listed". This was a bare timestamp, so an item that
-- never came back was reported on screen, and by /gc sellstate, as the auction house saying it
-- was unlisted.
local emptyAnswers = {}
-- When this item was last rested, or nil. Written as a table (above) and read here so every
-- caller agrees on the shape.
local function restedAt(itemID)
  local rest = emptyAnswers[itemID]
  return type(rest) == "table" and type(rest.at) == "number" and rest.at or nil
end
-- Did the auction house ANSWER, and recently enough that the answer still stands?
local function restedEmptyFresh(itemID, now)
  local rest = emptyAnswers[itemID]
  local at = restedAt(itemID)
  return at ~= nil and (now - at) <= EMPTY_ANSWER_AGE and rest.answered == true
end
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
    -- Resting, whether the rest was earned by an answer or by silence: both cost the same
    -- throttled round trip to repeat. Only the DISPLAY distinguishes them (see renderRows).
    local restingSince = restedAt(position.itemID)
    local answeredEmpty = restingSince ~= nil and (time() - restingSince) <= EMPTY_ANSWER_AGE
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
    and (GC.L["Prices up to date · %d did not answer"]):format(skipped)
    or GC.L["Prices up to date"])
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
  -- `answered` is the honest half: a timeout taught us nothing, so nothing on screen may claim
  -- the auction house said this item is unlisted (see renderRows and /gc sellstate).
  emptyAnswers[pending.itemID] = { at = time(), answered = not timedOut }
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
      setStatus(GC.L["Auction House did not answer — press Refresh"])
      scheduleNextWalk()
      return
    end
    C_Timer.After(PHASE_WATCHDOG_SECONDS, tick)
  end
  C_Timer.After(PHASE_WATCHDOG_SECONDS, tick)
end

-- The Sell CONTENT is attached but not on screen: the player is looking at Deals, Sold or the
-- Sniper. Everything that costs nothing carries on (bag composition, owned lots, the tab's own
-- count), but forty throttled server round trips for prices nobody is looking at are forty the
-- Sniper's scans and the player's own searches do not get. Parked, not cancelled -- GC.Sell.Show
-- calls Refresh unconditionally, which starts the pass for real the moment the tab is up.
--
-- `container == nil` is NOT parked: nothing has been attached yet, so there is no tab to be
-- hidden, and refusing to price there would refuse it forever.
local function walkParked()
  return container ~= nil and not containerShown()
end

-- An item key that never resolves used to hold the pass in "waiting_key" until the phase
-- watchdog declared the whole thing dead -- and startQuoteRefreshFor's one-item walk armed no
-- watchdog at all, so there it sat in "PRICING…" for the rest of the session. One item failing
-- is not the pass failing: rest it and carry on, exactly as skipPendingQuote does.
local function scheduleKeyTimeout(itemID, fromPriority)
  if not (C_Timer and C_Timer.After) then return end
  keyTimeoutToken = keyTimeoutToken + 1
  local token, generation = keyTimeoutToken, refresh.generation
  C_Timer.After(QUOTE_STALE_SECONDS, function()
    if token ~= keyTimeoutToken or generation ~= refresh.generation then return end
    if refresh.phase ~= "waiting_key" or refresh.awaiting ~= itemID then return end
    -- Never answered, so nothing here may later read as the auction house saying "nothing
    -- listed" -- see the emptyAnswers comment.
    emptyAnswers[itemID] = { at = time(), answered = false }
    refresh.awaiting, refresh.awaitingPriority = nil, nil
    if fromPriority then table.remove(refresh.priority, 1) else refresh.index = refresh.index + 1 end
    refresh.skipped = (refresh.skipped or 0) + 1
    refresh.phase = "pricing"
    markProgress()
    advanceQuote()
  end)
end

advanceQuote = function()
  -- "draining" belongs here as much as the other two: the fence branch below parks in it, and
  -- with it excluded nothing could ever come back -- not this function's own retry, not
  -- OnThrottleReady's tail -- so one fenced item held the pass until the watchdog shot it.
  if refresh.phase ~= "pricing" and refresh.phase ~= "waiting_key" and refresh.phase ~= "draining" then return end
  if refresh.pending then return end
  if walkParked() then
    -- Give the queue up rather than hold a phase nobody is watching: a held phase is one
    -- Refresh(automatic) refuses to leave.
    refresh.queue, refresh.index, refresh.awaiting, refresh.awaitingPriority = {}, 0, nil, nil
    refresh.phase = "idle"
    return
  end
  if refresh.index >= #refresh.queue and #refresh.priority == 0 then return finishQuoteWalk() end
  -- Yields to a Check or a purchase -- short, and the player is waiting on it --
  -- but NOT to the background full scan. Under Auto that scan never stops, and
  -- standing aside for it meant the Sell tab priced nothing at all while Auto
  -- was on: Refresh looked hung until a reload happened to catch a gap.
  local blocking = GC.Sniper and (GC.Sniper.IsSearchCritical or GC.Sniper.IsBusy)
  -- A yield needs its own way back. Nothing fires when a purchase's quiet zone
  -- ends, and the throttle-ready event can land while the walk has nothing
  -- pending to catch it -- so a yield used to sit until the 15s phase watchdog
  -- declared the pass dead and restarted it from item 1, which then yielded
  -- again: a live client showed "PRICING…" with two rows priced and the other
  -- 38 blank for as long as the tab stayed open. Re-ask in place instead, on a
  -- short timer, keeping the queue position; the token makes repeated yields
  -- collapse into one pending retry, and the generation check drops a retry
  -- that outlives the walk it was armed for.
  local function retryLater()
    if not (C_Timer and C_Timer.After) then return end
    refresh.retryToken = (refresh.retryToken or 0) + 1
    local token, generation = refresh.retryToken, refresh.generation
    C_Timer.After(QUOTE_RETRY_SECONDS, function()
      if token ~= refresh.retryToken or generation ~= refresh.generation then return end
      advanceQuote()
    end)
  end
  if blocking and blocking() then
    -- Yielding is the walk working correctly, not stalling, so the watchdog must
    -- not read it as an unanswered request.
    markProgress()
    setStatus(GC.L["Waiting for the purchase to finish…"])
    retryLater()
    return
  end
  if not driver.isReady() then
    -- The throttle window is closed -- IsThrottledMessageSystemReady() is false -- so the walk
    -- is stalled on purpose, not stuck, and this must feed the watchdog exactly like the
    -- purchase-yield branch above. I4 (fix wave, sell honesty): the code cannot actually tell
    -- WHY the slot is busy -- another search, the walk's own last query still cooling down, or
    -- the player's own Post -- so say only what is known, once per walk rather than every tick.
    markProgress()
    if not refresh.waitingNoted then
      refresh.waitingNoted = true
      setStatus(GC.L["Waiting for the Auction House…"])
    end
    retryLater()
    return
  end
  -- Three sources, in the order a seller would expect: the key we are already waiting on, then
  -- whatever a click asked for (refresh.priority), then the pass's own queue.
  local itemID, fromPriority
  if refresh.awaiting then
    itemID, fromPriority = refresh.awaiting, refresh.awaitingPriority == true
  elseif refresh.priority[1] then
    itemID, fromPriority = refresh.priority[1], true
  else
    itemID, fromPriority = refresh.queue[refresh.index + 1], false
  end
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
      -- Waiting behind a fence is the walk working, not stalling: feed the watchdog and come
      -- back by itself, exactly like the two yield branches above. Without these the only exit
      -- was the watchdog killing the pass over one item, 15s later.
      markProgress()
      setStatus(GC.L["Refresh waiting for prior result"])
      retryLater()
      return
    end
    -- The last gate before the query goes out. driver.isReady() above is a pure read of the
    -- throttle flag; THIS is the one call that spends the pacing budget a stuck flag puts the
    -- addon on, and it is asked here rather than up there so a decline further down (the drain
    -- fence, an uncached key) never spends it. The Sniper claims under its own name, so the
    -- board and this walk each get a turn instead of whichever of the two happens to ask first
    -- taking every one of them -- which is exactly what left this tab reading "PRICING… 0/20"
    -- through a hundred and twenty ready events.
    if driver.claimSend and not driver.claimSend() then
      markProgress()
      retryLater()
      return
    end
    refresh.awaiting, refresh.awaitingPriority = nil, nil
    if fromPriority then table.remove(refresh.priority, 1) else refresh.index = refresh.index + 1 end
    refresh.pending = { itemID = itemID, kind = kind, generation = refresh.generation, at = time() }
    refresh.phase = "waiting_result"
    markProgress()
    setStatus(fromPriority and GC.L["Checking this item's price…"]
      or (GC.L["Pricing %d/%d…"]):format(refresh.index, #refresh.queue))
    driver.send(itemID)
    scheduleQuoteTimeout(refresh.pending)
  else
    -- Armed once per item, not once per poke: OnThrottleReady drives this function again while
    -- the same key is still outstanding, and re-arming there would push the deadline out
    -- forever.
    local alreadyWaiting = refresh.awaiting == itemID
    refresh.awaiting, refresh.awaitingPriority, refresh.phase = itemID, fromPriority, "waiting_key"
    if not alreadyWaiting then scheduleKeyTimeout(itemID, fromPriority) end
  end
end

local function beginQuoteWalk()
  if walkParked() then
    -- The tab is not on screen. Composition and the owned lots have already been done by the
    -- caller; the forty throttled round trips have not, and will not until GC.Sell.Show asks.
    refresh.queue, refresh.index, refresh.phase = {}, 0, "idle"
    refresh.pending, refresh.awaiting, refresh.awaitingPriority = nil, nil, nil
    return
  end
  refresh.queue, refresh.index, refresh.phase, refresh.pending, refresh.awaiting = uniqueQuoteItemIDs(), 0, "pricing", nil, nil
  refresh.awaitingPriority = nil
  refresh.skipped = 0
  refresh.waitingNoted = false
  -- refresh.priority deliberately survives: it holds the items a CLICK asked about, and this
  -- rebuild is exactly what used to throw them away.
  if #refresh.queue == 0 and #refresh.priority == 0 then return finishQuoteWalk() end
  advanceQuote()
end

local function requestOwnedAuctions()
  if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions and GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen() then
    if not driver.isReady() then return false, true end
    if GC.Util and GC.Util.Trace then GC.Util.Trace("sell: QueryOwnedAuctions") end
    C_AuctionHouse.QueryOwnedAuctions({})
    return true, false
  end
  return false, false
end

local function onOwnedAuctionsReady()
  composePositions()
  renderRows()
  if refresh.phase == "owned" then
    -- Progress is stamped ONLY by the phase that was actually waiting for this. OWNED_AUCTIONS_
    -- UPDATED and AUCTION_CANCELED fire on their own schedule -- a lot expiring, a cancel from
    -- the Blizzard panel -- and stamping on every one of them fed the watchdog while a pricing
    -- phase sat wedged on a request that never came back, which is the one thing the watchdog
    -- exists to catch.
    markProgress()
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
--
-- Asking GetItemKeyInfo alone was not enough: it answers nil until the client has cached that
-- key, and a lot left unclassified files itself under an `item:...` key while the SAME item's
-- bag stock -- classified from the remembered answer in GC.db.commodityByItem (classifyBagItem
-- below) -- files under `commodity:...`. Two rows for one item, the listing holding no stock
-- and the stock reading "not on hand"; and when the lot was later re-classified, the repost
-- pin stopped matching and the tab announced "Lot cancelled; wait for it to return to bags"
-- about a lot that was still live. So: read the remembered answer first, and write every fresh
-- answer back into it, exactly as the bag classifier does.
local function classifyOwnedAuctions(auctions)
  local cache = commodityKindCache and commodityKindCache() or nil
  for _, auction in ipairs(auctions or {}) do
    local itemID = auction.itemID or (auction.itemKey and auction.itemKey.itemID)
    if auction.isCommodity == nil and type(itemID) == "number" then
      local remembered = cache and cache[itemID]
      if remembered ~= nil then
        auction.isCommodity = remembered
      elseif auction.itemKey and C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
        local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, auction.itemKey)
        if ok and type(info) == "table" and info.isCommodity ~= nil then
          auction.isCommodity = info.isCommodity == true
          if cache then cache[itemID] = auction.isCommodity end
        end
      end
    end
    -- What the next ITEM_KEY_ITEM_INFO_RECEIVED has to re-run for: a lot nobody can key yet.
    if type(itemID) == "number" then
      if auction.isCommodity == nil then
        ownedAwaitingKind[itemID] = true
      else
        ownedAwaitingKind[itemID] = nil
      end
    end
  end
  return auctions
end

function GC.Sell.OnOwnedAuctions()
  local auctions = C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and C_AuctionHouse.GetOwnedAuctions() or {}
  ownedLots = GC.SellPositions.NormalizeOwnedLots(classifyOwnedAuctions(auctions), time())
  local scope = context()
  -- My-auctions (docs/superpowers/specs/2026-09-06-my-auctions-design.md): the roster this
  -- read just produced is the roster the companion uploads, unchanged. No second query.
  if GC.Data and GC.Data.RecordOwnedLots and scope then
    GC.Data.RecordOwnedLots(GC.db, ownedLots, scope, time())
  end
  if GC.Acquisitions and GC.Acquisitions.ObserveOwnedPosition and scope then
    for _, lot in ipairs(ownedLots) do
      -- `lot.unitPrice` is what this position stands at on the auction house right now, and it
      -- is the only thing that can later tell one quality rank of a reagent from another when a
      -- mail invoice names both -- see GC.Acquisitions.WasListedAt.
      GC.Acquisitions.ObserveOwnedPosition(lot.positionKey, lot.itemID, itemName(lot.itemID),
        scope.char, scope.region, time(), lot.unitPrice)
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
      setStatus(GC.L["Lot cancelled; wait for it to return to bags"])
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
      setStatus(GC.L["Auction House is not open"])
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
  -- A lot this character owns was filed under a guessed key because the client could not say
  -- whether the item sells as a commodity. It can now: re-key the roster from the auctions the
  -- client is already holding (a local read, not a second query) so the listing and the bag
  -- stock land on the same row again.
  if ownedAwaitingKind[itemID] then
    ownedAwaitingKind[itemID] = nil
    if C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and GC.SellPositions.NormalizeOwnedLots then
      ownedLots = GC.SellPositions.NormalizeOwnedLots(
        classifyOwnedAuctions(C_AuctionHouse.GetOwnedAuctions() or {}), time())
      composePositions()
      renderRows()
    end
  end
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
    -- An empty READ is not an empty ANSWER. GetNum*SearchResults reports whatever result set
    -- the client holds for this key right now, and these events are raised by the Sniper's
    -- searches too -- so a zero can mean "the auction house says nothing is listed" or "our own
    -- reply is not in that slot". Only the first may wipe a quote and gag the item for a
    -- minute; without the client's own proof this is treated as a timeout, which keeps the
    -- quote and leaves the fence to catch the real answer when it lands.
    local proven = driver.hasFullResults == nil
      or driver.hasFullResults(itemID, kind == "commodity") ~= false
    skipPendingQuote(pending, not proven)
    return
  end
  refresh.pending = nil
  refresh.phase = "pricing"
  markProgress()
  emptyAnswers[itemID] = nil -- a real price supersedes any remembered GC.L["nothing listed"]
  -- Stamped from when the QUERY went out, not from now. The auction house's results events
  -- carry no request identifier, so a reply cannot be proven to belong to the request waiting
  -- for it (the addon's engineering notes says the same of commodity purchases) -- the drain fence below is
  -- the best this file can do, and past DRAIN_MAX_SECONDS a lost reply can still be credited to
  -- a re-ask. Dating the quote from the ask errs the only safe way: it can make a price look
  -- older than it is, never fresher, so it ages out and is re-asked rather than backing a post.
  GC.QuoteCache.Set(quotes, itemID, unit, pending.at or time())
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
commodityKindCache = function()
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
  pruneCommodityKinds()
end

-- GC.db.commodityByItem is SavedVariables-resident and was append-only: one boolean for every
-- item this character has ever carried, kept for the life of the account. Capped the way
-- db.postStats is (Core/Data.lua's POST_STATS_CAP) -- past the cap, keep only what is on hand
-- or on sale right now. Nothing is lost that cannot be learned again: every entry came from a
-- GetItemKeyInfo call the next visit to an auctioneer makes anyway.
local COMMODITY_KIND_CAP = 2000
pruneCommodityKinds = function()
  local cache = commodityKindCache()
  local count = 0
  for _ in pairs(cache) do count = count + 1 end
  if count <= COMMODITY_KIND_CAP then return end
  local keep = {}
  for _, stock in ipairs(bagStock) do keep[stock.itemID] = true end
  for _, lot in ipairs(ownedLots) do keep[lot.itemID] = true end
  for itemID in pairs(cache) do
    if not keep[itemID] then cache[itemID] = nil end
  end
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
    setStatus(GC.L["Auction House is not open"])
    return
  end
  if refresh.phase == "idle" or refresh.phase == "done" or refresh.phase == "error" then
    refresh.generation = refresh.generation + 1
    refresh.queue, refresh.index = { itemID }, 0
    refresh.pending, refresh.awaiting, refresh.awaitingPriority = nil, nil, nil
    refresh.phase = "pricing"
    markProgress()
    setStatus(GC.L["Checking this item's price…"])
    advanceQuote()
    -- This one-item walk armed no watchdog at all, so an item that landed in "waiting_key" or
    -- behind a drain fence left the machine sitting there: "PRICING…" for the rest of the
    -- session, with the automatic repeat refusing to run (it will not leave a set phase) and
    -- nothing but a manual REFRESH to get out.
    armPhaseWatchdog()
  else
    -- Held OUTSIDE refresh.queue -- see the refresh table's own comment. Inserting into that
    -- array dropped the item into a slot the walk stepped over whenever it was waiting on an
    -- item key, and the queue rebuild that ends the owned phase threw it away outright.
    local queued = false
    for _, waitingID in ipairs(refresh.priority) do
      if waitingID == itemID then queued = true break end
    end
    if not queued then refresh.priority[#refresh.priority + 1] = itemID end
    setStatus(GC.L["Checking this item's price…"])
  end
end

local function currentPosition(positionKey)
  for _, position in ipairs(positions) do
    if position.positionKey == positionKey then return position end
  end
  return nil
end

-- The pin of a post whose CONFIRM was sent and then timed out, kept for one more timeout window
-- so a slow server's AUCTION_HOUSE_AUCTION_CREATED still lands on its own bookkeeping.
--
-- The timeout used to be armed once, on the first click, and never re-armed for the confirming
-- one -- so a player who read the deposit line for nine seconds got "Posting timed out" over a
-- post that had gone through, and because the pin was gone with it, GC.Sell.OnAuctionCreated
-- found nothing: the post was never recorded against the batch and the price the seller had
-- typed was never cleared, so the NEXT stack of that item quietly inherited it. Re-arming (see
-- the confirm branch below) closes the ordinary case; this closes the one where the auction
-- house really is slower than the watchdog.
local postedGrace
local function schedulePostTimeout(row)
  if not (C_Timer and C_Timer.After) then return end
  postTimeoutToken = (postTimeoutToken or 0) + 1
  local token = postTimeoutToken
  C_Timer.After(POST_TIMEOUT_SECONDS, function()
    if token == postTimeoutToken and postingRow == row
        and (row.postStage == "posting" or row.postStage == "confirm" or row.postStage == "confirming") then
      -- Only when the confirm actually went to the server. A post still waiting for its own
      -- first answer has nothing on the wire to arrive late.
      if row.postStage == "confirming" and postingPin then
        postedGrace = { pin = postingPin, at = time() }
      end
      disarmPost()
      setStatus(GC.L["Posting timed out"])
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
    if row.action then row.action:SetLabel(GC.L["Pricing…"]) end
    setStatus(GC.L["Fetching a fresh price for this item — press Post again in a moment"])
    startQuoteRefreshFor(position); return
  end
  if postingRow and postingRow ~= row then
    setStatus(GC.L["Finish the pending post first"])
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
      else setStatus(GC.L["Post confirmation expired"]) end
      return
    end
    row.postStage = "confirming"; row.action:Disable(); setStatus(GC.L["Posting…"])
    -- The confirming click gets its own full window. Sharing the first click's clock meant the
    -- time a player spent reading the confirmation came out of the time the server had to
    -- answer it -- see schedulePostTimeout.
    schedulePostTimeout(row)
    if pin.isCommodity then
      C_AuctionHouse.ConfirmPostCommodity(pin.location, pin.duration, pin.quantity, pin.unitPrice)
    else
      C_AuctionHouse.ConfirmPostItem(pin.location, pin.duration, pin.quantity, nil, pin.buyout)
    end
    return
  end
  local bagState = liveBagState(position)
  -- Passed explicitly as well as through the decoration above: BuildPostPlan's own floor and
  -- queue raises can only ever raise, and a raise on top of a chosen price would silently undo
  -- the choice. The override branch there skips both.
  local chosenKey = overrideKey(position)
  local plan, reason = GC.SellPositions.BuildPostPlan(position, bagState, { unit = quote.unit, fresh = true },
    { overrideUnit = chosenKey and priceOverrides[chosenKey] or nil })
  if not plan then
    setStatus(reason == "ambiguous_variant" and GC.L["No exact bag variant"] or GC.L["Cannot post this position"])
    return
  end
  local scope, scopeKey = activeScope(position)
  if not scope or type(row.renderEntryID) ~= "string" or row.renderEntryID == ""
      or plan.positionKey ~= position.positionKey or plan.scopeKey ~= position.scopeKey
      or plan.scopeKey ~= scopeKey or plan.itemID ~= position.itemID
      or not exact(plan.quantity) or plan.quantity <= 0 or not exact(plan.unitPrice) or plan.unitPrice <= 0 then
    setStatus(GC.L["Cannot post this position"])
    return
  end
  local info = driver.keyInfo(plan.itemID)
  if not info then setStatus(GC.L["No exact auction key"]); return end
  if (info.isCommodity and not (C_AuctionHouse and C_AuctionHouse.PostCommodity))
      or (not info.isCommodity and not (C_AuctionHouse and C_AuctionHouse.PostItem)) then
    setStatus(GC.L["Posting unavailable"])
    return
  end
  local buyout = not info.isCommodity and safeMultiply(plan.unitPrice, plan.quantity) or nil
  if not info.isCommodity and not buyout then setStatus(GC.L["Cannot post this position"]); return end
  local commodityTotal = info.isCommodity and safeMultiply(plan.unitPrice, plan.quantity) or nil
  if info.isCommodity and (not commodityTotal or not exact(bagState.exactQty) or bagState.exactQty < plan.quantity) then
    setStatus(GC.L["No exact bag stack"])
    return
  end
  if not ItemLocation or not ItemLocation.CreateFromBagAndSlot or not bagState.bag or not bagState.slot then
    setStatus(GC.L["No exact bag stack"])
    return
  end
  if not info.isCommodity then
    bagState = liveBagState(position, plan.quantity)
    if not bagState.bag or not bagState.slot or not bagState.stackQty or bagState.stackQty < plan.quantity then
      setStatus(GC.L["No exact bag stack"])
      return
    end
  end
  local location = ItemLocation:CreateFromBagAndSlot(bagState.bag, bagState.slot)
  if not location then setStatus(GC.L["No exact bag stack"]); return end
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
  row.postStage = "posting"; row.action:Disable(); setStatus(GC.L["Posting…"])
  local needsConfirmation
  if info.isCommodity then
    needsConfirmation = C_AuctionHouse.PostCommodity(location, duration, plan.quantity, plan.unitPrice)
  else
    needsConfirmation = C_AuctionHouse.PostItem(location, duration, plan.quantity, nil, buyout)
  end
  if needsConfirmation then
    row.postStage = "confirm"; row.action:Enable(); row.action:SetLabel(GC.L["Confirm"])
    setStatus(GC.L["Click Confirm to post"])
  end
  schedulePostTimeout(row)
end

local function onRepostClick(row, auctionID)
  local position = row.position
  if repostingRow and repostingRow ~= row then
    disarmRepost()
    setStatus(GC.L["Previous repost selection cleared"])
    return
  end
  -- A cancel already on the wire is not a click target. Only nil (nothing armed) and "armed"
  -- are: a second click while the stage was "cancelling" fell straight past the armed branch
  -- below into the arm branch at the bottom and re-armed the very lot whose cancel the server
  -- was still working on.
  if row.repostStage ~= nil and row.repostStage ~= "armed" then
    setStatus(GC.L["Cancelling lot…"])
    return
  end
  local quote = freshQuote(position)
  if not quote then
    if repostingRow == row then disarmRepost() end
    -- Previously this refreshed the quote and returned in silence, so a first click looked like
    -- a dead button. Say what is happening; the click that follows is the one that arms.
    setStatus(GC.L["Fetching a fresh price for this lot — press Repost again in a moment"])
    startQuoteRefreshFor(position); return
  end
  if row.repostStage == "armed" then
    if not row.repostReady then return end
    local pin = repostPin
    if not exactRenderEntry(row, pin) then
      disarmRepost()
      setStatus(GC.L["Repost confirmation expired"])
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
      setStatus(GC.L["Repost confirmation expired"])
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
      setStatus(GC.L["Repost confirmation expired"])
      return
    end
    row.repostStage = "cancelling"; row.action:Disable()
    C_AuctionHouse.CancelAuction(plan.auctionID)
    if GC.Data and GC.Data.MarkOwnedLotCancelled and scope then
      GC.Data.MarkOwnedLotCancelled(GC.db, plan.auctionID, scope, time())
    end
    setStatus(GC.L["Cancelling lot…"])
    if C_Timer and C_Timer.After then
      local token = repostArmToken
      C_Timer.After(REPOST_CANCEL_TIMEOUT_SECONDS, function()
        if token == repostArmToken and repostingRow == row and row.repostStage == "cancelling" then
          disarmRepost()
          setStatus(GC.L["Cancel timed out"])
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
    setStatus(GC.L["Cannot repost this lot"])
    return
  end
  local lot
  for _, candidate in ipairs(position.ownedLots or {}) do if candidate.auctionID == plan.auctionID then lot = candidate break end end
  if not lot or lot.quantity ~= plan.quantity or not exact(lot.unitPrice) or lot.unitPrice <= 0 then
    setStatus(GC.L["Cannot repost this lot"])
    return
  end
  repostingRow, repostPin = row, { scopeKey = plan.scopeKey, positionKey = plan.positionKey, auctionID = plan.auctionID,
    itemID = plan.itemID, quantity = plan.quantity, listedUnit = lot.unitPrice,
    quoteAt = quote.at, quoteUnit = quote.unit, quote = quote, row = row, action = row.action,
    position = position, renderEntryID = row.renderEntryID, character = scope.char, region = scope.region }
  row.repostStage, row.repostReady = "armed", false
  row.action.helpKey = "Cancel lot?"; row.action:Disable(); row.action:SetLabel(GC.L["Cancel lot?"])
  setStatus(GC.L["Cancel this lot and lose its deposit — click again to confirm"])
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
        setStatus(GC.L["Repost confirmation expired"])
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
    setStatus(GC.L["Previous removal selection cleared"])
    return
  end
  if row.removeStage == "armed" then
    local pin = removePin
    if not exactRenderEntry(row, pin) then
      disarmRemove()
      setStatus(GC.L["Removal confirmation expired"])
      return
    end
    local removed = 0
    for _, id in ipairs(pin.ids) do
      if GC.Acquisitions.RemoveManual(id) then removed = removed + 1 end
    end
    disarmRemove()
    setStatus(removed > 0
      and (removed > 1 and (GC.L["Removed %d entries"]):format(removed) or GC.L["Removed"])
      or GC.L["Nothing to remove"])
    GC.Sell.Refresh()
    return
  end
  if postingRow or repostingRow then
    setStatus(GC.L["Finish the pending post or repost first"])
    return
  end
  local ids = row.batch and row.batch.ids
  if type(ids) ~= "table" or #ids == 0 or type(row.renderEntryID) ~= "string" or row.renderEntryID == "" then
    setStatus(GC.L["Cannot remove this entry"])
    return
  end
  removingRow, removePin = row, { ids = ids, row = row, action = row.action,
    position = row.position, renderEntryID = row.renderEntryID }
  row.removeStage = "armed"
  row.action.helpKey = "Remove?"; row.action:SetLabel(GC.L["Remove?"])
  setStatus(#ids > 1
    and GC.L["Removes every entered-by-hand purchase in this run -- click again to confirm"]
    or GC.L["Removes this entered-by-hand purchase -- click again to confirm"])
  removeArmToken = removeArmToken + 1
  local token = removeArmToken
  if C_Timer and C_Timer.After then
    C_Timer.After(REMOVE_TIMEOUT_SECONDS, function()
      if token == removeArmToken and removingRow == row and row.removeStage == "armed" then
        disarmRemove()
        setStatus(GC.L["Removal confirmation expired"])
      end
    end)
  end
end

-- Everything a completed post owes the rest of the addon, from the pin alone: shared by the
-- ordinary path below and by the late one, where the row and its render entry are long gone.
local function recordPostedPin(pin)
  if GC.Acquisitions and GC.Acquisitions.RecordPost then
    -- Derived as total/quantity rather than read off the pin, deliberately: a sale invoice
    -- carries a total and a quantity and nothing else, so the price this remembers has to be
    -- computed the same way the price it will be matched against is (Acquisitions.ReconcileSale).
    local postedUnit = math.floor(pin.total / pin.quantity)
    GC.Acquisitions.RecordPost(pin.positionKey, pin.itemID, itemName(pin.itemID), pin.character,
      pin.region, pin.quantity, time(), postedUnit)
  end
end

-- The pin's own fields, with nothing said about the row it came from. Everything RecordPost
-- needs and nothing a render can invalidate.
local function postPinSound(pin)
  return type(pin) == "table" and exact(pin.quantity) and pin.quantity > 0
    and exact(pin.total) and pin.total > 0 and type(pin.character) == "string" and pin.character ~= ""
    and type(pin.region) == "string" and pin.region ~= ""
end

function GC.Sell.OnAuctionCreated()
  local pin, row = postingPin, postingRow
  if not pin or not row then
    -- Nothing armed -- but a confirm the watchdog gave up on can still be answered a moment
    -- later, and the auction it announces is a real one. Record it from the pin that was kept
    -- for exactly this window and then forget it, so a second, unrelated creation cannot be
    -- credited to it. No render-entry check is possible here: the row is gone.
    local grace = postedGrace
    postedGrace = nil
    if not grace or time() - (grace.at or 0) > POST_TIMEOUT_SECONDS or not postPinSound(grace.pin) then return end
    recordPostedPin(grace.pin)
    if type(grace.pin.positionKey) == "string" then priceOverrides[grace.pin.positionKey] = nil end
    GC.Sell.Refresh()
    return
  end
  local valid = exactRenderEntry(row, pin) and (row.postStage == "posting" or row.postStage == "confirming")
    and pin.positionKey == row.position.positionKey and pin.scopeKey == row.position.scopeKey
    and pin.itemID == row.position.itemID and postPinSound(pin)
  if valid then recordPostedPin(pin) end
  -- The choice was for THIS listing. Keeping it would quietly price the next batch of the same
  -- item at a number chosen against a book that has since moved -- which is the one real risk
  -- of letting the price be typed at all.
  if type(pin.positionKey) == "string" then priceOverrides[pin.positionKey] = nil end
  postedGrace = nil
  disarmPost()
  GC.Sell.Refresh()
end

function GC.Sell.OnPostError()
  disarmPost()
  disarmRepost()
  setStatus(GC.L["Posting failed"])
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
  dialog.header:SetText((GC.L["%s — %d unit%s without a cost"]):format(
    position.itemName or GC.L["Item"], missing, missing == 1 and "" or "s"))
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
  if not quantity or quantity < 1 then return setDialogError(dialog, GC.L["Enter a whole quantity"]) end
  if quantity > dialog.maximum then return setDialogError(dialog, GC.L["Quantity exceeds missing units"]) end
  if not total then return setDialogError(dialog, GC.L["Enter an exact positive cost"]) end
  if dialog.costMode == "unit" then
    local unit = dialogGoldPositive(dialog.unit)
    if not unit or safeMultiply(quantity, unit) ~= total then
      return setDialogError(dialog, GC.L["Enter an exact positive cost"])
    end
  elseif dialog.costMode ~= "total" then
    return setDialogError(dialog, GC.L["Enter an exact positive cost"])
  end
  local position = dialog.position
  local scope = activeScope(position)
  if not scope then return setDialogError(dialog, GC.L["Position scope changed"]) end
  local batch
  if dialog.pendingRepair then
    local pending = pendingRepairFor(position, scope)
    if not pending or pending.id ~= dialog.pendingRepair.id or not dialog.repairID
        or not (GC.Acquisitions and GC.Acquisitions.RepairPendingManual) then
      return setDialogError(dialog, GC.L["Position scope changed"])
    end
    batch = GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = dialog.repairID,
      itemID = position.itemID, positionKey = position.positionKey, itemName = position.itemName,
      quantity = quantity, total = total, acquiredAt = time(), character = scope.char, region = scope.region })
  else
    batch = GC.Acquisitions.RecordManual({ itemID = position.itemID, positionKey = position.positionKey,
      itemName = position.itemName, quantity = quantity, total = total, acquiredAt = time(),
      character = scope.char, region = scope.region })
  end
  if batch then dialog.submitted = true; dialog:Hide(); GC.Sell.Refresh() else setDialogError(dialog, GC.L["Enter an exact positive cost"]) end
end

-- The item name is the one column that must stay readable: every other cell is a number that
-- also lives in the tooltip or the expansion, but a row whose name is "Aze..." is useless.
-- `min` on the flex column was declared and never honoured, so the name silently collapsed to
-- nothing as soon as the fixed columns outgrew the window. Shed load-bearing weight in order
-- instead: the listed total (already in the summary), then squeeze the advice text, then drop
-- it entirely (the action button carries the same guidance on its tooltip), and only then the
-- cost per unit (which the expansion spells out per purchase).
-- 160, was 200. The name has its own truncation and a tooltip carrying it in full; COST/UNIT
-- has neither, and at 200 the name's floor was what pushed it off the screen.
local ITEM_MIN = 160
local STATUS_MIN = 110
local columnWidth = {}

-- Which columns each deck lays out. Not cosmetics: one column set had to serve both jobs at
-- once, which is what made it eight columns wide, which is what made the shedding order reach
-- load-bearing numbers at the DEFAULT window. At 720x600 the old set dropped LISTED and then
-- COST / UNIT by arithmetic, not by bad luck -- the column this whole tab exists to answer was
-- off screen for every player who never resized. Splitting by deck is what buys the room back.
local DECK_COLUMNS = {
  post = { item = true, price = true, gross = true, action = true },
  -- No cost/profit on a live lot: what a listed row is asked is "what did I list at, and who
  -- is under me". Its cost basis has not changed since it was posted and is one click away in
  -- the expansion. "Who is under me" is the line under YOUR PRICE now, in units, which is the
  -- half of that question the old UNDER YOU column (a bare price) never answered.
  listed = { item = true, price = true, listed = true, action = true },
}
-- What a deck gives up once squeezing every minimum still does not fit, in order.
--
-- Nothing, on either deck, since each is down to two figures and the button: at the narrowest
-- window the item name still clears ITEM_MIN with both at their minimum. The table stays so
-- that the next column anybody adds has to say where it goes when the room runs out.
local DECK_SHED = {
  post = {},
  listed = {},
}

-- The side panel a position opens into. W is its whole width; the scroll bar lives INSIDE it
-- (SCROLL_GUTTER) so that docked beside the list or laid over it the panel is one rectangle.
-- DOCK_MIN is the content width from which the list can give the panel its own column and
-- still read; under it the panel is a sheet over the list's right side -- the item names stay
-- visible at the left, which is what a seller picks the next row by.
local INSP = { W = 320, GAP = 28, HEAD_H = 48, SCROLL_GUTTER = 26, PAD = 8, DOCK_MIN = 860 }

-- Whether the panel is open, and whether it has a column of its own. Hung on INSP rather than
-- left as four more file-level locals: WoW's Lua 5.1 allows a chunk 200 of them, and this file
-- is close enough to that for the client to refuse to load it (busted's newer Lua never says).
do
  local isOpen = false
  function INSP.docked()
    return isOpen and (ROW_WIDTH or 0) >= INSP.DOCK_MIN
  end
  -- The LIST's width, which is the container's less a docked panel's column.
  function INSP.listWidth()
    local width = ROW_WIDTH or 0
    if INSP.docked() then width = width - INSP.W - INSP.GAP end
    return width
  end
  -- Opens or shuts the panel as far as geometry goes: the list's heading row and scroll area
  -- are re-anchored only when that changes whether the panel has a column of its own.
  function INSP.sync(open)
    isOpen = open
    if container.applyListGeometry and container.listDocked ~= INSP.docked() then
      container.listDocked = INSP.docked()
      container.applyListGeometry()
    end
  end
end

local function shownColumns()
  local width = INSP.listWidth()
  local deck = (filterMode == "listed" or filterMode == "cancelqueue") and "listed" or "post"
  local inDeck = DECK_COLUMNS[deck]
  local dropped = {}
  columnWidth = {}
  -- A column this deck does not carry is DROPPED, not merely absent from `shown`: layoutCells
  -- hides exactly what `dropped` names, and a pooled row that drew the column on the other deck
  -- last render would otherwise keep painting it here forever.
  for _, column in ipairs(COLUMNS) do
    if not inDeck[column.key] then dropped[column.key] = true end
  end

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
    -- Squeeze everything that has a floor before giving anything up. Every minimum here was
    -- measured against a real string at Theme.Scale() 1.3, not guessed.
    if remaining() < ITEM_MIN then columnWidth.status = STATUS_MIN end
    if remaining() < ITEM_MIN then
      for _, column in ipairs(COLUMNS) do
        if column.min then columnWidth[column.key] = column.min end
      end
    end
    for _, key in ipairs(DECK_SHED[deck]) do
      if remaining() >= ITEM_MIN then break end
      dropped[key] = true
      columnWidth[key] = nil
    end
  end

  local shown = {}
  for _, column in ipairs(COLUMNS) do
    if not dropped[column.key] then shown[#shown + 1] = column end
  end
  return shown, dropped
end

-- The book's own four columns, mirroring the design: price, depth at that price, a bar for
-- that depth, and the units queued in front of it. Fixed, and deliberately independent of
-- shownColumns -- a book row shows the same four things at every window width.
-- The price control's own widths. Laid out by layoutDrawer now, independently of the shedding
-- column set: the panel shows the same things at every width.
local PRICE_BOX_W, PRICE_BOX_H, PRICE_CHIP_W = 84, 18, 52
-- The chips, by slot. Two parallel tables rather than one of {id, label} pairs: the contract
-- scanner reads every literal inside an @localised-keys table, and an id sitting in the same
-- table would be collected as a translatable string nobody ever shows.
-- @localised-keys
local PRICE_CHIP_LABELS = {
  "MATCH", "UNDERCUT", "MARKET", "COST",
}
-- What each slot fills from. The SLOT is the stable key the click handler switches on, never
-- the label -- a translated label would look up nothing (the addon's engineering notes' own rule).
local PRICE_CHIP_IDS = { "match", "under", "market", "cost" }

-- The footer ledger's three labels, same split as PRICE_CHIP_LABELS/PRICE_CHIP_IDS above and
-- for the same reason. "AT MARKET" and "ASKING", not "PROFIT" and "LISTED" (2026-09-11): a
-- player reads three figures left to right as ASKING minus COST equalling the rightmost one,
-- and that arithmetic is false -- ASKING is the sum of the player's own typed prices, AT
-- MARKET is what GoldCap projects these lots clear after the 5% cut, at a price nobody typed.
-- Distinct labels don't fix the misreading by themselves; the AT MARKET tooltip carries the
-- actual sentence.
-- @localised-keys
local SUMMARY_STAT_LABELS = {
  "AT MARKET", "ASKING", "COST",
}
local SUMMARY_STAT_IDS = { "profit", "listed", "cost" }

local BOOK_PRICE_W, BOOK_UNITS_W, BOOK_BAR_H = 84, 58, 6
-- Queue marks under a row's price: one per price level, counted from the cheapest. Five is
-- where a seller stops caring which level exactly -- past that the words beside them carry it.
local ROW = { MARKS = 5 }
-- The dock along the bottom of the tab. STAT_W fits "1234567g89s" at mono-10 and Theme.Scale()
-- 1.3 (~7.8px/char); NARROW is the content width under which the ledger keeps only the total a
-- seller is here for -- at the default 720px window all three would leave the line beside the
-- bulk action no room to name the item it is about to post.
local DOCK = { H = 44, PAD = 8, STAT_W = 92, NARROW = 700 }

-- The detail panel's head: one row that is a PANEL rather than a line, claiming DR.SLOTS of the
-- list's own pitch. It used to open INLINE under its position, two columns wide, with the lot
-- and purchase rows stacked under it -- ten rows of detail that buried the list it was opened
-- from, and only five book levels because that was all a panel that short could carry.
--
-- It lives in the side panel now (see INSP), one column: the price you are about to list at,
-- then the book that price lands in, all eight levels the view model hands over.
local DR = {
  SLOTS = 12,              -- 12 * ROW_H(32) = 384px
  LINE_H = 18,             -- one book level
  LINES = 8,               -- SellViewModel's own BOOK_ROWS
  HEAD_Y = -8,             -- "YOUR PRICE"
  BOX_Y = -24,             -- the price box
  NOTE_Y = -48,            -- what that price does
  CHIPS_Y = -68,           -- the four one-click fills
  REC_Y = -94,             -- GoldCap's own recommendation
  BOOK_HEAD_Y = -122,      -- "THE BOOK"
  HINT_Y = -138,           -- cheapest not yours, depth, the colour key -- two lines of it
  BODY_Y = -170,           -- first book level
  BAR_MAX = 96,
}
-- Derived, not typed twice: the two lines under the book hang off where its last level ends.
DR.STAND_Y = DR.BODY_Y - DR.LINES * DR.LINE_H - 4
DR.FACTS_Y = DR.STAND_Y - 20

-- The panel head's own layout, one column. Independent of shownColumns: the panel shows the
-- same things at every window width, and its width is INSP's, not the list's.
local layoutDetailRow
do
local function layoutDrawer(row)
  local left, right = INSP.PAD, -INSP.PAD

  row.drawerPriceHead:ClearAllPoints()
  row.drawerPriceHead:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.HEAD_Y)
  row.priceBox:ClearAllPoints()
  row.priceBox:SetSize(PRICE_BOX_W, PRICE_BOX_H)
  row.priceBox:SetPoint("TOPLEFT", row, "TOPLEFT", left + 4, DR.BOX_Y)
  -- The head's Post sits on the price box's own line, at the panel's right edge.
  row.cells.action:ClearAllPoints()
  row.cells.action:SetSize(88, PRICE_BOX_H)
  row.cells.action:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, DR.BOX_Y)
  row.priceNote:ClearAllPoints()
  row.priceNote:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.NOTE_Y)
  row.priceNote:SetPoint("RIGHT", row, "RIGHT", right, 0)
  row.priceNote:SetWordWrap(false)

  local prev
  for i = 1, #row.priceChips do
    local chip = row.priceChips[i]
    chip:ClearAllPoints()
    if prev then chip:SetPoint("LEFT", prev, "RIGHT", Theme.pad.xs, 0)
    else chip:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.CHIPS_Y) end
    prev = chip
  end

  -- The recommendation lives HERE, not on the position row: WHAT TO DO is not a column on
  -- either deck, so this is the one place the sentence is ever shown.
  row.subItem:ClearAllPoints()
  row.subItem:SetWidth(0)
  row.subItem:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.REC_Y)
  row.subItem:SetPoint("RIGHT", row, "RIGHT", right, 0)
  row.subItem:SetWordWrap(false)

  row.drawerBookHead:ClearAllPoints()
  row.drawerBookHead:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.BOOK_HEAD_Y)
  -- Under the heading rather than beside it, and allowed its second line: at the panel's width
  -- the hint is longer than the row, and what it cuts off first is the colour key.
  row.drawerHint:ClearAllPoints()
  row.drawerHint:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.HINT_Y)
  row.drawerHint:SetPoint("RIGHT", row, "RIGHT", right, 0)
  row.drawerHint:SetJustifyH("LEFT")
  row.drawerHint:SetWordWrap(true)
  row.drawerHint:SetMaxLines(2)

  for i = 1, DR.LINES do
    local line = row.bookLines[i]
    local y = DR.BODY_Y - (i - 1) * DR.LINE_H
    line.price:ClearAllPoints()
    line.price:SetWidth(BOOK_PRICE_W)
    line.price:SetPoint("TOPLEFT", row, "TOPLEFT", left, y)
    line.qty:ClearAllPoints()
    line.qty:SetWidth(BOOK_UNITS_W)
    line.qty:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, y)
    line.bar:ClearAllPoints()
    line.bar:SetPoint("LEFT", line.price, "RIGHT", Theme.pad.s, 0)
    line.bar:SetPoint("RIGHT", line.qty, "LEFT", -Theme.pad.s, 0)
  end

  row.drawerStand:ClearAllPoints()
  row.drawerStand:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.STAND_Y)
  row.drawerStand:SetPoint("RIGHT", row, "RIGHT", right, 0)
  row.drawerStand:SetWordWrap(false)

  row.drawerFacts:ClearAllPoints()
  row.drawerFacts:SetPoint("TOPLEFT", row, "TOPLEFT", left, DR.FACTS_Y)
  row.drawerFacts:SetPoint("RIGHT", row, "RIGHT", right, 0)
  row.drawerFacts:SetJustifyH("LEFT")
  row.drawerFacts:SetWordWrap(true)
  row.drawerFacts:SetMaxLines(3)
end

-- A lot, a bag line, a purchase or a heading inside the panel. None of the deck's columns
-- apply at this width: a line is its sentence, with its one button -- or, for a purchase, its
-- unit cost -- at the right edge. Two lines allowed, because "x50 . 3 purchases . bought 29 Aug
-- . GoldCap . mail-confirmed" is a sentence the panel is narrower than.
layoutDetailRow = function(row)
  for _, column in ipairs(COLUMNS) do row.cells[column.key]:Hide() end
  local edge, edgePoint, inset = row, "RIGHT", -INSP.PAD
  if row.action:IsShown() then
    row.cells.action:ClearAllPoints()
    row.cells.action:SetWidth(88)
    row.cells.action:SetPoint("RIGHT", row, "RIGHT", -INSP.PAD, 0)
    edge, edgePoint, inset = row.cells.action, "LEFT", -4
  elseif row.kind == "batch" then
    row.cells.cost:ClearAllPoints()
    row.cells.cost:SetWidth(72)
    row.cells.cost:SetPoint("RIGHT", row, "RIGHT", -INSP.PAD, 0)
    row.cells.cost:Show()
    edge, edgePoint, inset = row.cells.cost, "LEFT", -4
  end
  row.subItem:ClearAllPoints()
  row.subItem:SetWidth(0)
  row.subItem:SetPoint("LEFT", row, "LEFT", INSP.PAD, 0)
  row.subItem:SetPoint("RIGHT", edge, edgePoint, inset, 0)
  row.subItem:SetWordWrap(true)
  row.subItem:SetMaxLines(2)
  row.sectionLabel:ClearAllPoints()
  row.sectionLabel:SetPoint("LEFT", row, "LEFT", INSP.PAD, 0)
  -- The head lays itself out over this: called from here so renderRows has one panel layout
  -- to know about, not two (see rowTag on why that function counts its upvalues).
  if row.kind == "drawer" then layoutDrawer(row) end
end
end -- do: layoutDrawer is layoutDetailRow's own



-- One column can mean two things depending on the deck, and a heading that lies is worse than
-- no heading: MARKET / UNIT is "the cheapest ask that is not mine" while you are choosing a
-- price to post at, and "who is standing under my lot" once it is posted. Same number, two
-- questions, two words for it.
-- @localised-keys
local HEADINGS_POST = {
  item = "ITEM", gross = "YOU GET", price = "PRICE / UNIT",
  cost = "COST / UNIT", listed = "LISTED", market = "MARKET / UNIT",
  profit = "PROFIT / UNIT", status = "WHAT TO DO",
}
-- @localised-keys
local HEADINGS_LISTED = {
  item = "LISTED AS", gross = "IN THE LOT", price = "YOUR PRICE",
  cost = "COST / UNIT", listed = "LOT VALUE", market = "UNDER YOU",
  profit = "PROFIT / UNIT", status = "WHAT TO DO",
}

local function paintHeaderText(header, deck)
  local words = deck == "listed" and HEADINGS_LISTED or HEADINGS_POST
  for key, cell in pairs(header.cells) do
    local word = words[key]
    cell:SetText(word and GC.L[word] or "")
  end
end

-- Which figure carries a second line, and the row field that line lives in.
ROW.SECOND_LINE = { price = "priceStand", gross = "grossNote", listed = "grossNote" }

local function layoutCells(row)
  local right = row
  -- How far `right` itself sits above the row's centre. Every cell anchors to its neighbour,
  -- so a lifted neighbour lifts whatever hangs off it: offsets are written relative to this,
  -- or the second lifted cell in a chain lands a full row-half too high (seen in game -- the
  -- price rode up into the row above it).
  local rightLift = 0
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
      -- The name sits in the upper half of the row and its stock line in the lower half; the
      -- header row and every sub-row keep the whole box, centred, because they carry one line.
      -- 8, not 7: at Theme.Scale 1.3 a 12px name is ~15.6 tall and a 10px stock line ~13, so
      -- the two boxes touch at ±7 and clear each other at ±8 inside the 32px row.
      local nameY = row.itemStock and 8 or 0
      cell:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, nameY)
      cell:SetPoint("RIGHT", right, "LEFT", -4, nameY - rightLift)
      if row.itemStock then
        row.itemStock:ClearAllPoints()
        row.itemStock:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, -8)
        row.itemStock:SetPoint("RIGHT", right, "LEFT", -4, -8 - rightLift)
      end
      -- The column header row (below) shares this function but carries neither widget -- it is
      -- a single fixed heading, never a position/sub-row/group in the pooled row sense.
      if row.subItem then
        row.subItem:ClearAllPoints()
        -- Clears the fixed width layoutBookRow gives it. Rows are pooled: a row that drew a
        -- book level last render would otherwise keep an 84px price column forever, fighting
        -- the LEFT/RIGHT pair below for the rest of its life.
        row.subItem:SetWidth(0)
        row.subItem:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, 0)
        row.subItem:SetPoint("RIGHT", right, "LEFT", -4, -rightLift)
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
      -- A position's figures share the row with a second line, exactly as its name does with the
      -- stock line (same +-8 split, same reason). Every other kind keeps the cell centred.
      local second = row.kind == "position" and ROW.SECOND_LINE[column.key] and row[ROW.SECOND_LINE[column.key]] or nil
      local lift = second and 8 or 0
      cell:SetPoint("RIGHT", right, right == row and "RIGHT" or "LEFT", right == row and 0 or -2, lift - rightLift)
      if second then
        second:ClearAllPoints()
        second:SetPoint("RIGHT", cell, "RIGHT", 0, -16)
      end
      right, rightLift = cell, lift
      cell:Show()
    end
  end
  if row.standMarks then
    -- Chained leftwards from the words they belong to, so the pair stays together however long
    -- the count beside them grows.
    local anchor = row.priceStand
    for i = #row.standMarks, 1, -1 do
      local mark = row.standMarks[i]
      mark:ClearAllPoints()
      mark:SetPoint("RIGHT", anchor, "LEFT", anchor == row.priceStand and -5 or -2, 0)
      anchor = mark
    end
  end
  for _, column in ipairs(COLUMNS) do
    if dropped[column.key] then row.cells[column.key]:Hide() end
  end
end

-- Keyed by the label the button currently carries. Every one of these either spends gold or
-- destroys a deposit, so none of them should be a word a player has to guess at.
--
-- English here on purpose, and translated where it is READ (actionHelp below). This table
-- is built at file scope, and GC.L only resolves once ApplyLocale has run at ADDON_LOADED
-- -- so GC.L[...] in these entries would capture the English fallback once and stay English
-- in every language. The outer KEYS stay English for a different reason: they are the
-- stable helpKey the buttons carry, which is the defect helpKey was introduced to fix.
-- @localised-keys: literals in this table ARE GC.L keys; see the comment above for why
-- the lookup happens where the table is read rather than where it is built.
local ACTION_HELP = {
  ["Set cost"] = { "Set cost", { "Tell GoldCap what you actually paid for these units.", "It will not invent a cost from the market price, so profit stays unknown until you enter one." } },
  -- Two short paragraphs each, never more (sell_action_help_spec locks the length): the
  -- tooltip opens beside a button inside the list, so every extra line is a row it covers.
  ["Post"] = { "Post", { "Lists what is in your bags at the WHAT TO DO price: the whole bag for a commodity, one stack for a regular item.", "The price is the last quote, up to 45 seconds old. If it moves before you confirm, the post is dropped rather than sent at the old price." } },
  ["Repost"] = { "Repost", { "Cancels this live auction — it does NOT relist it. The deposit is forfeit and the items come back by mail; list them again from this row once they arrive.", "Asks for a second click to confirm." } },
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
    -- The list's rows are what a hover picks between; a wash over the panel's twelve-slot
    -- head, or over a heading inside it, points at nothing.
    if not self.inPanel then self.highlight:Show() end
    -- Rows are pooled and rebound every render, so the item tooltip is wired once here and
    -- reads whatever position the row currently holds. Hooking it per render would stack.
    if GameTooltip and self.kind == "position" and self.position and self.position.itemID then
      -- Outside the window, never over it -- a row's own item tooltip used to cover the deck
      -- it is describing (Theme.ItemTooltipOutside; see UI/Theme.lua's own comment on it).
      Theme.ItemTooltipOutside(self, statusOwner)
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.position.itemID) end
      -- Flags painted onto the row at the same time as the cells they describe (MARKET/UNIT's
      -- fallback, the item cell's "· not on hand" suffix) -- read here rather than re-derived,
      -- so the tooltip can never disagree with what the row is actually showing.
      if self.marketFallback then
        GameTooltip:AddLine(GC.L["≈ goldcap.gg market value — no live quote yet"], 0.85, 0.85, 0.85, true)
      end
      if self.notOnHand then
        GameTooltip:AddLine(GC.L["Not on hand — the stock is in the mail, the bank, or on another character"],
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
  -- The stock line ("×246 in bags · ×11 listed") used to ride in cells.item as a second line
  -- behind a "\n". cells.item is SetWordWrap(false) like every other cell, which renders ONE
  -- line and marks the rest with an ellipsis -- so the second line was never drawn at all and
  -- every item on the screen appeared truncated, whatever its name. Its own FontString, its
  -- own anchor (layoutCells splits the flex box in half vertically for the pair).
  row.itemStock = Theme.Label(row, 10)
  -- Said out loud rather than inherited from the font template: this line is deliberately one
  -- step back from the item name above it, so that the money coloured into it (MONEY_HEX) is
  -- the thing that steps forward. Leaving it on the template's own colour made the whole line
  -- compete with the name and the cost compete with nothing.
  row.itemStock:SetTextColor(Theme.color.fgMuted[1], Theme.color.fgMuted[2], Theme.color.fgMuted[3])
  row.itemStock:SetJustifyH("LEFT")
  row.itemStock:SetWordWrap(false)
  row.itemStock:Hide()

  -- The second line of the two figures, the same split the name and its stock line already
  -- make. Under the price: where that price stands in the live book -- five marks, one per
  -- price level from the cheapest, the one this price lands on lit -- and the stock queued
  -- under it in words. Under YOU GET: the margin, which used to be a column of its own a row's
  -- width away from the figure it qualifies. Both answer before anything is opened.
  row.priceStand = Theme.Num(row, 9)
  row.priceStand:SetJustifyH("RIGHT")
  row.priceStand:SetWordWrap(false)
  row.priceStand:Hide()
  row.standMarks = {}
  for i = 1, ROW.MARKS do
    local mark = row:CreateTexture(nil, "ARTWORK")
    mark:SetSize(3, 8)
    mark:Hide()
    row.standMarks[i] = mark
  end
  row.grossNote = Theme.Num(row, 9)
  row.grossNote:SetJustifyH("RIGHT")
  row.grossNote:SetWordWrap(false)
  row.grossNote:Hide()

  -- The drawer's own five book lines. Built here rather than lazily on first open: a widget
  -- created mid-render is how this suite's fakes start failing on a method they were never
  -- taught, and rows are pooled and few.
  row.bookLines = {}
  for i = 1, DR.LINES do
    local line = {}
    line.price = Theme.Num(row, 11)
    line.price:SetJustifyH("RIGHT")
    line.price:SetWordWrap(false)
    line.qty = Theme.Num(row, 10)
    line.qty:SetJustifyH("RIGHT")
    line.qty:SetWordWrap(false)
    line.bar = CreateFrame("Frame", nil, row)
    line.bar:SetHeight(BOOK_BAR_H)
    line.bar.track = line.bar:CreateTexture(nil, "BACKGROUND")
    line.bar.track:SetAllPoints()
    line.bar.track:SetColorTexture(1, 1, 1, 0.05)
    line.bar.fill = line.bar:CreateTexture(nil, "ARTWORK")
    line.bar.fill:SetPoint("TOPLEFT")
    line.bar.fill:SetPoint("BOTTOMLEFT")
    line.bar.fill:SetWidth(1)
    line.price:Hide(); line.qty:Hide(); line.bar:Hide()
    row.bookLines[i] = line
  end
  -- Column headings and the bottom line. Separate FontStrings rather than reusing subItem and
  -- sectionLabel: the drawer shows all four AT ONCE, where every other row kind shows exactly
  -- one of them.
  row.drawerPriceHead = Theme.Num(row, 9)
  row.drawerBookHead = Theme.Num(row, 9)
  row.drawerHint = Theme.Num(row, 9)
  row.drawerHint:SetJustifyH("RIGHT")
  row.drawerStand = Theme.Label(row, 10)
  row.drawerFacts = Theme.Label(row, 10)
  row.drawerFacts:SetWordWrap(false)
  row.drawerPriceHead:Hide(); row.drawerBookHead:Hide()
  row.drawerHint:Hide(); row.drawerStand:Hide(); row.drawerFacts:Hide()

  -- The price control. The one number on this screen that spends real gold was, until now, the
  -- one number a seller could not see the workings of or change: GoldCap picked it and Post
  -- sent it. The box is prefilled with exactly what Post would list at, in gold, and emptying
  -- it hands the decision back to GoldCap rather than leaving nothing behind.
  row.priceBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
  row.priceBox:SetSize(PRICE_BOX_W, PRICE_BOX_H)
  row.priceBox:SetAutoFocus(false)
  row.priceBox:Hide()

  row.priceNote = Theme.Label(row, 10)
  row.priceNote:SetJustifyH("LEFT")
  row.priceNote:SetWordWrap(false)
  row.priceNote:Hide()

  -- Four one-click fills, each from a number already on the screen. They exist beside the box,
  -- not instead of it: the box is what the owner asked for, and these are what stop the common
  -- cases from needing arithmetic.
  -- Reads the box and records (or clears) the seller's choice. Emptying it is a real answer,
  -- not a failure to type one: it hands the decision back to GoldCap rather than leaving the
  -- position with no price at all.
  -- Re-entrant by construction: ClearFocus below raises OnEditFocusLost, which is bound to
  -- this same function. One extra pass would be harmless, but a loop inside the client is
  -- not the kind of thing to leave to luck on a path that spends gold. The same flag is what
  -- renderRows raises when it has to take the box away from a row it just rebound.
  local function commitPrice(box)
    if row.priceCommitting then return end
    local key = overrideKey(row.position)
    -- Rows are POOLED: a refresh between the click into the box and this commit can rebind
    -- this very row to a different position. `priceEditingKey` is the position the typing
    -- started on, and a price typed for one item must never land on another.
    if not key or key ~= row.priceEditingKey then
      row.priceEditingKey = nil
      return
    end
    local text = box:GetText() or ""
    if text:match("^%s*$") then
      priceOverrides[key] = nil
    else
      local copper = dialogGoldPositive(box)
      if not copper then
        setStatus(GC.L["Type a price in gold, or clear the box to use GoldCap's"])
        return
      end
      priceOverrides[key] = copper
    end
    row.priceEditingKey = nil
    row.priceCommitting = true
    box:ClearFocus()
    row.priceCommitting = false
    renderRows()
  end
  -- Remembers which position the typing belongs to, for the pooled-row check above.
  row.priceBox:SetScript("OnEditFocusGained", function()
    row.priceEditingKey = overrideKey(row.position)
  end)
  -- Live while typing. Everything this number DRIVES -- what the stack fetches, the margin,
  -- the note under the box and where the gold marker sits in the book -- used to sit still
  -- until Enter or until the box lost focus, so the seller was typing into a screen that did
  -- not answer (reported in game). Each keystroke that reads as a price now re-renders.
  --
  -- The write to priceOverrides is what makes the rest of the screen move, and it is safe to
  -- make it here: OnEscapePressed already discards by re-rendering from the committed state,
  -- and clearing the box still means "hand the decision back to GoldCap", exactly as commit
  -- does. What this must NOT do is fight the typist -- renderRows leaves a focused box alone
  -- (see the drawer branch's own guard), so the text itself is never restamped.
  row.priceBox:SetScript("OnTextChanged", function(box, byUser)
    -- Only the player's own typing. A SetText from a render fires this too, and reacting to
    -- that would re-enter the render that caused it.
    if not byUser or row.priceCommitting then return end
    local key = overrideKey(row.position)
    if not key or key ~= row.priceEditingKey then return end
    local text = box:GetText() or ""
    if text:match("^%s*$") then
      priceOverrides[key] = nil
    else
      local copper = dialogGoldPositive(box)
      -- Half-typed text ("39." between two keystrokes) parses to nothing. Keep the last price
      -- that did read as one and leave the box alone rather than snapping it back.
      if not copper then return end
      priceOverrides[key] = copper
    end
    renderRows()
  end)
  row.priceBox:SetScript("OnEnterPressed", commitPrice)
  -- Committing on focus loss as well: a price typed and then clicked away from is still a
  -- price the seller typed, and the alternative is a box that silently reverts.
  row.priceBox:SetScript("OnEditFocusLost", commitPrice)
  row.priceBox:SetScript("OnEscapePressed", function(box)
    row.priceEditingKey = nil
    row.priceCommitting = true
    box:ClearFocus()
    row.priceCommitting = false
    renderRows() -- puts the committed price back, discarding whatever was half-typed
  end)

  row.priceChips = {}
  for slot = 1, #PRICE_CHIP_LABELS do
    local chip = Theme.Button(row, "ghost", "badge")
    chip:SetSize(PRICE_CHIP_W, PRICE_BOX_H)
    chip:SetScript("OnClick", function(self)
      local key = overrideKey(row.position)
      if not key or not self.priceSource then return end
      priceOverrides[key] = self.priceSource
      renderRows()
    end)
    chip:Hide()
    row.priceChips[slot] = chip
  end
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
  row.sectionRule:SetColorTexture(gc2[1], gc2[2], gc2[3], 0.25)
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
      -- helpKey is the English action name the row set; self.label is display text and may be
      -- in any language. Fall back to the label for buttons that predate the key.
      local help = ACTION_HELP[self.helpKey or ""]
        or ACTION_HELP[self.label]
        or ACTION_HELP[(self.label or ""):gsub("%s*%(.*", "")]
      if not help then return end
      -- Not ANCHOR_RIGHT: this button sits in the far-right column of a window that can fill
      -- the screen, and a tooltip told to grow rightward from there gets clamped back over the
      -- list, the header and the button itself. Theme reads where the button is and opens the
      -- tooltip on the side that has room.
      GameTooltip:SetOwner(self, Theme.TooltipAnchor(self))
      -- Translated at READ time -- see ACTION_HELP's own comment for why the table itself
      -- cannot hold GC.L lookups.
      GameTooltip:AddLine(GC.L[help[1]], 1, 0.82, 0)
      for _, line in ipairs(help[2]) do GameTooltip:AddLine(GC.L[line], 0.85, 0.85, 0.85, true) end
      GameTooltip:Show()
    end)
    row.action:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  end
  row:SetScript("OnClick", function(self)
    if self.kind == "fold" then
      showNotOnHand = not showNotOnHand
      renderRows()
    elseif self.kind == "position" and type(self.position.positionKey) == "string" then
      -- One open position at a time. Two open panels are two hundred pixels of detail each,
      -- and the second one pushed the first -- the one being compared against -- off screen.
      local key = self.position.positionKey
      local wasOpen = expanded[key]
      for other in pairs(expanded) do expanded[other] = nil end
      expanded[key] = not wasOpen or nil
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

-- @localised-keys: literals in this table ARE GC.L keys, looked up where the table is
-- READ, not here. This is file scope, and GC.L only resolves once ApplyLocale has run
-- at ADDON_LOADED -- a lookup here captures the English fallback and keeps it in every
-- language. The table has to close with a `}` on its own line: that is where the
-- contract spec's scanner stops.
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

-- `key` is the ENGLISH action name, not display text. ACTION_HELP is keyed by it, so once the
-- interface is translated a lookup by the visible label would miss every time and silently
-- drop the help from exactly the buttons that spend gold. The key is remembered on the button;
-- the label is only what the player reads.
local function showRowAction(row, key, onClick)
  -- Deliberately does NOT clear `status` any more: that cell holds the recommendation -- what
  -- to do, at what unit price, and the breakeven under it -- and blanking it was the reason a
  -- player could never tell what a Post or Repost was about to charge.
  row.action.helpKey = key
  row.action:SetLabel(GC.L[key])
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
    -- Item 2 (addon polish batch): the number is a sum over only the positions that
    -- individually cleared both gates, so it can still be a partial total -- the card's own
    -- hit frame (below) shows the detail on hover, but a player who never hovers must not read
    -- a partial sum as the whole picture. profitMarker carries that onto the number itself.
    container.summary.profit:SetText(formatAmount(text.profit) .. (text.profitMarker or ""))
    container.summaryProfitDetail = text.profitDetail
  else
    -- SellViewModel.SummaryText's non-number reads "Unknown" or "Unknown · 12 partial · 37
    -- missing" -- at Theme.Scale() 1.3 the longer form doesn't fit the mono value line, so the
    -- card itself stays a plain "Unknown" and everything after the first " · " moves to
    -- summaryProfitHit's own tooltip (see the stat-card loop below), read live at hover time.
    container.summary.profit:SetText(GC.L["Unknown"])
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
  -- The two decks carry DIFFERENT column sets, so the heading row has to be re-laid out when
  -- the deck changes -- rows are laid out on every render (below) but the header is built once.
  -- Done here rather than in the deck buttons' own handler because filterMode also moves
  -- underneath us: onCancelQueueClick sets "cancelqueue", which is the listed deck, and
  -- onQueueClick sets "queue", which is the post one. Every path that can change the deck ends
  -- up here, so this is the one place that cannot be forgotten.
  local headerDeck = (filterMode == "listed" or filterMode == "cancelqueue") and "listed" or "post"
  if container and container.header and container.headerDeck ~= headerDeck then
    container.headerDeck = headerDeck
    paintHeaderText(container.header, headerDeck)
    layoutCells(container.header)
  end
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
    -- Deck ends in SellViewModel.Order itself, so there is no second ordering pass here the
    -- way the old single-filter path needed one.
    filtered = GC.SellViewModel.Deck(positions, filterMode,
      { ready = chips.ready, noCost = chips.nocost })
    -- Deck ends in Order, which is the right answer for a list being BUILT and the wrong one
    -- for a list already on screen: the pricing walk answers one item at a time, and every
    -- answer re-ranked a row out from under the cursor.
    filtered = GC.SellViewModel.Settle(filtered, rowPlaces)
  end
  updateSummary(filtered)
  -- Why a row is not in the bulk action, by position, for the tag on its stock line. Read off
  -- the same two skip lists the footer's held-back counter reads, so the row and the counter
  -- can never disagree about what was left out.
  local heldBackReason = {}
  local onListed = filterMode == "listed" or filterMode == "cancelqueue"
  for _, skip in ipairs(onListed and cancelSkipped or queueSkipped) do
    if type(skip.positionKey) == "string" then heldBackReason[skip.positionKey] = skip.reason end
  end
  local entries = {}
  -- Stock that is neither in the bags nor listed is cost history, not work: it sits at the
  -- bottom of the posting deck folded under one heading, so the rows a seller acts on are not
  -- followed by a tail of rows they cannot. NO COST opens it by itself -- those positions are
  -- most of what that chip exists to find, and Set cost lives on their rows.
  local folded = {}
  -- The position whose detail panel is open, if it is on this deck at all: a deck change or a
  -- chip can take the row away, and a panel describing a row that is not there shuts.
  local openPosition
  local function pushPosition(position)
    entries[#entries + 1] = { kind = "position", position = position }
    if expanded[position.positionKey] and not openPosition then
      openPosition = position
      local first = #entries + 1
      local detail = GC.SellViewModel.Expansion(position)
      -- ONE panel where this used to spend eleven separate 32px rows: the facts line, the
      -- price control, the book heading and eight levels. Opening a position buried the list
      -- it was opened from -- 25 rows of expansion inside a 430px scroll area -- which is the
      -- single complaint this redesign started from.
      entries[#entries + 1] = { kind = "drawer", position = position, detail = detail,
        slots = DR.SLOTS }
      -- What you are selling comes before what you paid: the listings are the thing a player
      -- acts on, the purchase history is only there to justify the cost number.
      local inBags = position.bagQty or 0
      if #detail.ownedLots > 0 or inBags > 0 then
        entries[#entries + 1] = { kind = "group", position = position, title = GC.L["ON THE AUCTION HOUSE"] }
      end
      for _, lot in ipairs(detail.ownedLots) do entries[#entries + 1] = { kind = "lot", position = position, lot = lot } end
      if inBags > 0 then
        entries[#entries + 1] = { kind = "listing", position = position }
      end
      if #detail.batches > 0 then
        entries[#entries + 1] = { kind = "group", position = position, title = GC.L["WHAT YOU PAID"],
          hint = GC.L["Sales are costed from your oldest units first"] }
      end
      for _, batch in ipairs(detail.batches) do entries[#entries + 1] = { kind = "batch", position = position, batch = batch } end
      -- Everything a position opens into is drawn in the side panel, not under the row. The
      -- entries keep their place in this one list -- and so their pooled rows and every pin a
      -- post or a cancel holds on one -- and only say where they are to be laid out.
      for index = first, #entries do entries[index].panel = true end
    end
  end
  for _, position in ipairs(filtered) do
    local notOnHand = filterMode == "post" and not position.unresolved
      and (position.bagQty or 0) == 0 and (position.listedQty or 0) == 0
    if notOnHand then folded[#folded + 1] = position else pushPosition(position) end
  end
  -- Only a TAIL is folded. When nothing on the deck is on hand there is no work for the fold to
  -- keep clear, and hiding the only rows there are would leave a heading over an empty list.
  if #folded > 0 and #entries == 0 then
    for _, position in ipairs(folded) do pushPosition(position) end
  elseif #folded > 0 then
    local open = showNotOnHand or chips.nocost
    entries[#entries + 1] = { kind = "fold", position = folded[1], count = #folded, open = open }
    if open then
      for _, position in ipairs(folded) do pushPosition(position) end
    end
  end
  if #entries == 0 then
    -- M7: sentence case, not shouted -- this is a native-font (Theme.Label) empty state, like
    -- Deals', and reads like the rest of that font's copy rather than a toolbar label.
    -- Say which of the three reasons it is, because they need different next moves: a deck
    -- that is genuinely empty, versus a chip that emptied it, versus the other deck holding
    -- everything. "No items match this filter" answered none of them.
    container.emptyText:SetText(emptyDeckText())
    container.emptyText:Show()
  else
    container.emptyText:Hide()
  end
  for i = #rows + 1, #entries do rows[i] = createRow(content) end
  -- Known before any row is laid out: a docked panel takes its width out of the list's, and
  -- shownColumns reads that. The heading row and the scroll area follow whenever it changes.
  INSP.sync(openPosition ~= nil)
  -- Running Y for the loop below, one per surface. Rows are pooled and re-anchored on every
  -- render, so both are rebuilt from scratch each time rather than remembered.
  local placedHeight, detailHeight, listIndex = 0, 0, 0
  for i, row in ipairs(rows) do
    local entry = entries[i]
    if not entry then row.renderEntryID = nil; row:Hide()
    else
      -- One pool, two surfaces. A row is re-parented only when its entry moves between them,
      -- which a position being opened or shut does and a re-price never does -- so the price
      -- box a seller is typing into is not touched by the renders their typing causes.
      local surface = entry.panel and detailContent or content
      row.inPanel = entry.panel == true
      if surface and row.surface ~= surface then
        row.surface = surface
        if row.SetParent then row:SetParent(surface) end
      end
      -- Slot-based placement, not a fixed pitch off the index: an entry may claim several
      -- ROW_HEIGHT slots (entry.slots) so that one row can be a PANEL instead of a line. Every
      -- entry that does not ask for slots claims exactly one, which is the old arithmetic
      -- (offset == (i - 1) * ROW_HEIGHT) reproduced exactly -- so nothing but the drawer moves.
      local slots = entry.slots or 1
      local offset = entry.panel and detailHeight or placedHeight
      row:Show(); row:ClearAllPoints()
      row:SetPoint("TOPLEFT", surface, "TOPLEFT", 0, -offset); row:SetPoint("TOPRIGHT", surface, "TOPRIGHT", 0, -offset)
      row:SetHeight(slots * ROW_HEIGHT)
      if entry.panel then detailHeight = detailHeight + slots * ROW_HEIGHT
      else placedHeight = placedHeight + slots * ROW_HEIGHT; listIndex = listIndex + 1 end
      row.kind, row.position, row.batch, row.lot = entry.kind, entry.position, entry.batch, entry.lot
      -- Read by this row's own OnEnter (below) to decide whether to add a tooltip line about the
      -- number this row is showing. Reset for every kind, not just "position": rows are pooled
      -- and rebound, so a flag left set from an earlier position would otherwise ride along onto
      -- an unrelated expansion sub-row.
      row.marketFallback, row.notOnHand = false, false
      local p = entry.position
      local lotID = entry.lot and entry.lot.auctionID or 0
      row.renderEntryID = table.concat({ renderGeneration, i, entry.kind, p.scopeKey or "", p.positionKey or "", lotID }, ":")
      -- Every cell starts empty, whatever kind takes this pooled row next, so a branch only
      -- has to write what it actually shows. Enumerating the clears per branch is what leaked
      -- YOU GET / PRICE / MARGIN onto lot and batch sub-rows: those lists were written before
      -- the columns existed, and nothing made anybody update them.
      for _, column in ipairs(COLUMNS) do row.cells[column.key]:SetText("") end
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
        if bagQty > 0 then stockParts[#stockParts + 1] = (GC.L["×%d in bags"]):format(bagQty) end
        if listedQty > 0 then stockParts[#stockParts + 1] = (GC.L["×%d listed"]):format(listedQty) end
        -- What one of these cost, on the line under the name. COST / UNIT was its own column
        -- until this deck's column set replaced it; the fact is too load-bearing to lose with
        -- the column, and it reads better beside the quantity it applies to anyway.
        local paidUnit = nil
        if p.coverage == "COMPLETE" and exact(p.knownCost) and exact(p.knownQty) and p.knownQty > 0 then
          paidUnit = math.floor(p.knownCost / p.knownQty)
          -- Escaped around the AMOUNT, not around the whole phrase: a translation is free to
          -- put the money anywhere in its own sentence, and only the money should light up.
          stockParts[#stockParts + 1] =
            (GC.L["paid %s each"]):format(MONEY_HEX .. formatCell(paidUnit) .. "|r")
        end
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
        -- I2 (fix wave, sell honesty): an unresolved position (unassigned_acquisition/
        -- pending_purchase/paid_sale/ambiguous_sale, see Core/SellPositions.lua ~:579-616) has
        -- no batch or lot backing it at all -- there is no stock to be "elsewhere", so the
        -- mail/bank/alt claim below would be a fabrication about a position that is really
        -- "GoldCap doesn't know what this is yet". Mirrors the STATUS branch's own
        -- `not p.unresolved` guard further down.
        local notOnHand = not p.unresolved and (p.bagQty or 0) == 0 and (p.listedQty or 0) == 0
        row.notOnHand = notOnHand
        row.cells.item:SetText(named)
        -- What is off about this row, if anything -- see rowTag.
        row.itemStock:SetText((#stockParts > 0 and table.concat(stockParts, " · ")
          or GC.SellViewModel.SourceText(p))
          .. (notOnHand and "|cff8c8a85 · not on hand|r" or "")
          .. rowTag(p, heldBackReason[p.positionKey], notOnHand))
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
        -- Item 5 (addon polish batch): a bare `emptyAnswers[p.itemID]` presence check made a
        -- ONE-OFF empty AH answer hide the fallback forever -- only a manual Refresh (which
        -- wipes emptyAnswers outright) brought it back. Age-gate it the same way
        -- uniqueQuoteItemIDs already does for re-query eligibility, so a stale empty answer
        -- lets the fallback show again instead of only a fresh one suppressing it. While the
        -- walk is actively re-querying THIS exact item (refresh.pending, the walk's one
        -- in-flight slot), keep "none" rather than flicker the fallback in for the few seconds
        -- until the real (still probably empty) answer lands.
        --
        -- Fix wave: a request that never came back was recorded in emptyAnswers exactly like a
        -- reply that carried no listings, so an item the auction house had said nothing about
        -- at all rendered as "none" here and "Nothing listed on the AH right now" in STATUS.
        -- Only an ANSWER may drive that text now (emptyAnswers' own comment); silence falls
        -- back to the dash and "Waiting for a live price", which is what it is. The re-query
        -- guard keeps its job -- holding the last KNOWN-EMPTY answer on screen while the walk
        -- re-asks -- but it cannot invent one for an item that has never answered.
        local answeredEmpty = restedEmptyFresh(p.itemID, time())
        local requeryingThis = refresh.pending and refresh.pending.itemID == p.itemID
        local rest = emptyAnswers[p.itemID]
        local emptyKnown = answeredEmpty
          or (requeryingThis and type(rest) == "table" and rest.answered == true) or false
        local marketFallback = p.displayMarketUnit == nil and type(p.marketValue) == "number"
          and p.marketValue > 0 and not emptyKnown
        row.marketFallback = marketFallback
        local marketText
        if p.displayMarketUnit then
          marketText = formatCell(p.displayMarketUnit)
        elseif marketFallback then
          marketText = "≈" .. formatCell(p.marketValue)
        else
          marketText = emptyKnown and "none" or "—"
        end
        if p.displayMarketUnit and not p.freshMarketUnit and type(p.quoteAge) == "number" then
          marketText = marketText .. (GC.L[" · stale %ds"]):format(p.quoteAge)
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
        -- unrelated number lands in the same slot afterward. Same failure class the addon's engineering notes
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
          -- Minor (fix wave, sell honesty): "Unknown" beside a dim "≈" market used to render in
          -- the row's ordinary fg -- a confident-looking pair next to an admittedly approximate
          -- number. Dim whenever there is no real number here; the gold/red hold-price branch
          -- above (a real number either way) is untouched.
          setColor(row.cells.profit, type(profit) == "number" and Theme.color.fg or Theme.color.fgDim)
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
          row.cells.status:SetText((GC.L["Listed at %s — far below market. Repost."]):format(
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
          -- MINOR-1 (fix round 1): reuses the same age-gated `emptyKnown` the MARKET column
          -- decides its fallback from, above -- a bare `emptyAnswers[p.itemID]` here disagreed
          -- with MARKET once the answer went stale (MARKET said "≈…", STATUS still said
          -- "Nothing listed").
          if p.displayMarketUnit == nil and emptyKnown then
            row.cells.status:SetText(GC.L["Nothing listed on the AH right now"])
          else
            row.cells.status:SetText(GC.L["Waiting for a live price"])
          end
          setColor(row.cells.status, Theme.color.fgDim)
        elseif not p.unresolved and (p.listedQty or 0) == 0 then
          -- Nothing in the bags AND nothing listed: the stock this row tracks is in the
          -- mail, the bank, or on another character. Cost coverage is a real question too,
          -- but "where is my ore?" is the one the player is actually asking here.
          row.cells.status:SetText(GC.L["Not in your bags or listed — mail or bank?"])
          setColor(row.cells.status, Theme.color.fgDim)
        elseif p.coverage ~= "COMPLETE" then
          row.cells.status:SetText((GC.L["Cost unknown for %d of %d"]):format(
            math.max(0, exposureQty - knownQty), exposureQty))
          setColor(row.cells.status, Theme.color.fgDim)
        else
          row.cells.status:SetText("")
          setColor(row.cells.status, Theme.color.fg)
        end
        -- The deck's own three figures. Written for BOTH decks and shown per DECK_COLUMNS, so
        -- a cell never carries a number belonging to the deck the player is not looking at.
        local onListedDeck = filterMode == "listed" or filterMode == "cancelqueue"
        local rowUnit
        if onListedDeck and listedQty > 0 and exact(p.listedValue) then
          -- The average a live lot is actually standing at, which is what "your price" means
          -- once it is posted -- not what Post would choose for the stock still in the bags.
          rowUnit = math.floor(p.listedValue / listedQty)
        else
          rowUnit = effectivePostUnit(p)
        end
        -- YOU GET answers "what does this row fetch if I click Post", so on the post deck it is
        -- counted over what one click LISTS -- the largest stack for a normal item, the whole
        -- pool for a commodity (position.postableQty, see Core/SellPositions). Counting the bag
        -- sum quoted a figure four fifths of which stayed in the bags.
        local postableQty = exact(p.postableQty) and p.postableQty > 0 and p.postableQty or bagQty
        local grossQty = onListedDeck and listedQty or postableQty
        local gross = rowUnit and safeMultiply(rowUnit, grossQty) or nil
        row.cells.gross:SetText(gross and formatCell(gross) or "—")
        setColor(row.cells.gross, gross and Theme.color.fg or Theme.color.fgDim)
        row.cells.price:SetText(rowUnit and formatCell(rowUnit) or "—")
        setColor(row.cells.price, rowUnit and Theme.color.fg or Theme.color.fgDim)
        if rowUnit and paidUnit and paidUnit > 0 then
          local pct = math.floor(((rowUnit - paidUnit) / paidUnit) * 100 + 0.5)
          row.grossNote:SetText((pct >= 0 and "+" or "") .. pct .. "%")
          setColor(row.grossNote, pct >= 0 and Theme.color.green or Theme.color.red)
        else
          -- Nothing is "no price yet"; the words are "no receipt, so the margin is not a number
          -- anybody can know". Conflating them is what made Unknown read as broken.
          row.grossNote:SetText(rowUnit and not paidUnit and GC.L["no cost"] or "")
          setColor(row.grossNote, Theme.color.fgDim)
        end
        -- Where rowUnit stands in the live book. The marks count price levels from the
        -- cheapest; the lit one is where this price lands -- gold for a price about to be
        -- posted, the watch blue for a lot already standing there, the same two colours the
        -- book itself uses for the same two facts.
        local standing = rowUnit and GC.SellViewModel.Standing and GC.SellViewModel.Standing(p, rowUnit) or nil
        local lit = onListedDeck and Theme.color.watch or Theme.color.gold
        for slot, mark in ipairs(row.standMarks) do
          if not standing then
            -- No book, no marks: five grey ticks beside nothing read as a broken widget.
            mark:SetColorTexture(1, 1, 1, 0)
          elseif slot == standing.slot then
            mark:SetColorTexture(lit[1], lit[2], lit[3], 1)
          else
            mark:SetColorTexture(1, 1, 1, slot < standing.slot and 0.32 or 0.10)
          end
        end
        if not standing then
          row.priceStand:SetText("")
        elseif standing.ahead == 0 then
          row.priceStand:SetText(GC.L["first in line"])
          setColor(row.priceStand, Theme.color.green)
        else
          row.priceStand:SetText((onListedDeck and GC.L["%s under you"] or GC.L["%s ahead"]):format(
            GC.Util.FormatCount(standing.ahead) or tostring(standing.ahead)))
          setColor(row.priceStand, Theme.color.fgDim)
        end
        -- Post is the point of this screen, so it lives on the row itself. It
        -- used to be reachable only by expanding the position and finding a
        -- sub-row, and only for stock GoldCap had a receipt for -- which is why
        -- the honest answer to "what can I list" was "go use the Blizzard tab".
        -- Set cost is bookkeeping and stays available whenever there is no
        -- stock to act on; the expansion carries it in either case.
        if bagQty > 0 then
          showRowAction(row, "Post", function() onPostClick(row) end)
        elseif canSetCost(p) then
          showRowAction(row, GC.L["Set cost"], function() openCostDialog(p) end)
        else
          row.action:Hide()
        end
      elseif entry.kind == "drawer" then
        local d = entry.detail
        local book = d and d.book or nil
        local postable = (p.bagQty or 0) > 0
        row.drawerBookHead:SetText(GC.L["THE BOOK"]); row.drawerBookHead:Show()
        setColor(row.drawerBookHead, Theme.color.fgDim)

        -- ---- the price side: the same widgets and the same commit path the price ROW used,
        -- so nothing about what a typed price does has changed -- only where it is shown.
        local unit, chosen = effectivePostUnit(p)
        local risk = GC.SellPositions.PriceRisk(p, unit)
        row.drawerPriceHead:SetText(GC.L["YOUR PRICE"]); row.drawerPriceHead:Show()
        setColor(row.drawerPriceHead, chosen and Theme.color.gold or Theme.color.fgDim)
        if postable then
          local box = row.priceBox
          local focused = box.HasFocus and box:HasFocus() or false
          -- Someone typing into this box, on this same position, owns it -- see the price row's
          -- own note: a render that stamped it unconditionally wiped half-typed prices.
          if not (focused and row.priceEditingKey == overrideKey(p)) then
            if focused then
              row.priceEditingKey = nil
              row.priceCommitting = true
              box:ClearFocus()
              row.priceCommitting = false
            end
            box:SetText(unit and copperToGoldText(unit) or "")
          end
          box:Show()
          if risk.belowCost then
            row.priceNote:SetText((GC.L["below the %s you paid"]):format(formatCell(risk.paidUnit)))
            setColor(row.priceNote, Theme.color.red)
          elseif risk.belowFloor then
            row.priceNote:SetText((GC.L["under GoldCap's own floor of %s"]):format(formatCell(risk.floor)))
            setColor(row.priceNote, Theme.color.red)
          elseif unit then
            -- The quantity this note prices is the one a click lists, not the one in the bags --
            -- the same rule YOU GET follows above, and for the same reason.
            local postQty = exact(p.postableQty) and p.postableQty > 0 and p.postableQty or (p.bagQty or 0)
            local total = safeMultiply(unit, postQty)
            row.priceNote:SetText(("%s · ×%d · %s"):format(
              chosen and GC.L["yours"] or GC.L["GoldCap's"], postQty,
              total and formatCell(total) or "—"))
            setColor(row.priceNote, Theme.color.fgDim)
          else
            row.priceNote:SetText(GC.L["no live price yet"])
            setColor(row.priceNote, Theme.color.fgDim)
          end
          row.priceNote:Show()
          -- UNDERCUT is a rung BELOW the cheapest competing ask, and a silver under an ask of a
          -- silver or less is zero or negative. Zero is truthy in Lua, so the chip enabled
          -- itself, stored a price of 0 as the seller's choice, and effectivePostUnit then
          -- refused it -- which emptied the box the player had just filled. Nothing here may
          -- offer a price that is not a price.
          local competing = book and exact(book.cheapestCompeting) and book.cheapestCompeting > 0
            and book.cheapestCompeting or nil
          local sources = {
            match = competing,
            under = competing and competing > 100 and (competing - 100) or nil,
            market = exact(p.marketValue) and p.marketValue > 0 and p.marketValue or nil,
            cost = exact(risk.paidUnit) and risk.paidUnit > 0 and risk.paidUnit or nil,
          }
          for slot, chip in ipairs(row.priceChips) do
            local source = sources[PRICE_CHIP_IDS[slot]]
            chip:SetLabel(GC.L[PRICE_CHIP_LABELS[slot]])
            chip.priceSource = source
            if source then chip:Enable() else chip:Disable() end
            chip:Show()
          end
        else
          -- Nothing in the bags: there is no price to set, and an editable box that cannot post
          -- is an invitation to a click that does nothing. Say why instead.
          row.priceBox:Hide()
          for _, chip in ipairs(row.priceChips) do chip:Hide() end
          row.priceNote:SetText(GC.L["nothing in your bags to price"])
          setColor(row.priceNote, Theme.color.fgDim)
          row.priceNote:Show()
        end

        -- ---- the book side: the evidence the price on the left stands on, beside it rather
        -- than eight rows below it.
        if book then
          row.drawerHint:SetText(bookHint(book)); row.drawerHint:Show()
          setColor(row.drawerHint, Theme.color.fgDim)
          local widest = book.widest or 0
          for lineIndex = 1, DR.LINES do
            local line, level = row.bookLines[lineIndex], book.rows[lineIndex]
            if level then
              -- Colour carries the two facts a single number cannot: gold is where GoldCap's
              -- price would put you, blue is stock already yours. Same code as the level row.
              local colour, tint = Theme.color.fg, nil
              if book.yourRow == lineIndex then colour, tint = Theme.color.gold, Theme.color.gold
              elseif level.mine then colour, tint = Theme.color.watch, Theme.color.watch end
              line.price:SetText(formatCell(level.unit)); setColor(line.price, colour)
              line.qty:SetText(GC.Util.FormatCount(level.units) or "—")
              setColor(line.qty, Theme.color.fgDim)
              local span = widest > 0 and (level.units / widest) or 0
              line.bar.fill:SetWidth(math.max(1, math.floor(DR.BAR_MAX * span + 0.5)))
              if tint then line.bar.fill:SetColorTexture(tint[1], tint[2], tint[3], 0.8)
              else line.bar.fill:SetColorTexture(1, 1, 1, 0.22) end
              line.price:Show(); line.qty:Show(); line.bar:Show()
            else
              line.price:Hide(); line.qty:Hide(); line.bar:Hide()
            end
          end
          if book.yourRow then
            row.drawerStand:SetText((GC.L["your price stands %d of %d"]):format(
              book.yourRow, book.levels or 0))
            setColor(row.drawerStand, Theme.color.goldHi)
          else
            row.drawerStand:SetText(GC.L["your price is above every level shown"])
            setColor(row.drawerStand, Theme.color.fgDim)
          end
        else
          row.drawerHint:Hide()
          for _, line in ipairs(row.bookLines) do
            line.price:Hide(); line.qty:Hide(); line.bar:Hide()
          end
          row.drawerStand:SetText(GC.L["the Auction House has not answered for this item yet"])
          setColor(row.drawerStand, Theme.color.fgDim)
        end
        row.drawerStand:Show()

        -- ---- the bottom line: exactly what the separate "detail" row carried.
        local facts = {}
        if d and d.displayMarketUnit ~= nil then
          local lead = ("market %s · %s"):format(formatCell(d.displayMarketUnit),
            d.marketState or "unavailable")
          if type(d.quoteAge) == "number" then lead = lead .. (" · age %ss"):format(d.quoteAge) end
          facts[#facts + 1] = lead
        elseif d and type(d.quoteAge) == "number" then
          facts[#facts + 1] = (GC.L["quote %ss ago"]):format(d.quoteAge)
        end
        if d and type(d.ahead) == "number" then facts[#facts + 1] = ("%d ahead of you"):format(d.ahead) end
        if d and d.sold ~= nil then facts[#facts + 1] = (GC.L["sells %s/day"]):format(d.sold) end
        if d and type(d.days) == "number" then facts[#facts + 1] = ("clears in ~%dd"):format(math.floor(d.days + 0.5)) end
        if d and d.factsText then facts[#facts + 1] = d.factsText end
        local notPriced = (p.bagQty or 0) == 0 and (p.listedQty or 0) == 0 and not p.unresolved
        row.drawerFacts:SetText(#facts > 0 and table.concat(facts, " · ")
          or (notPriced and "not priced — nothing on hand to sell" or "no live quote yet — pricing…"))
        setColor(row.drawerFacts, (#facts == 0 or (d and d.marketStale))
          and Theme.color.fgDim or Theme.color.fg)
        row.drawerFacts:Show()

        -- What GoldCap would do and at what price -- the text the expansion's own detail row
        -- used to put in the status CELL, which the deck's shed order now takes off the row at
        -- the default window width.
        row.subItem:SetText(recommendationText(d and d.recommendation))
        setColor(row.subItem, Theme.color.fg)
        row.subItem:Show()
        for _, column in ipairs(COLUMNS) do row.cells[column.key]:SetText("") end
        -- Post, beside the price it posts at. As a sheet the panel lies over the right side of
        -- the list -- over the open row's own button -- so without this the one position a
        -- seller had just priced was the one they could not post. It is the row's Post, through
        -- the same onPostClick and the same pin; two buttons for one position cannot both arm
        -- (onPostClick refuses a second row while one is pending).
        if postable then
          showRowAction(row, "Post", function() onPostClick(row) end)
        else
          row.action:Hide()
        end
      elseif entry.kind == "fold" then
        -- "+" and "-" rather than an arrow: only in-game-proven punctuation goes on screen (the
        -- bundled face drew tofu for the arrows the design used).
        row.sectionLabel:SetText((entry.open and "- " or "+ ")
          .. (GC.L["NOT ON HAND %d"]):format(entry.count)
          .. "  " .. DIM_HEX .. GC.L["in the mail, the bank or on another character"] .. "|r")
        row.action:Hide()
      elseif entry.kind == "group" then
        -- The hint rides IN the heading, not in the status cell. That cell is the first thing
        -- a narrow window sheds, and the book's own hint -- the cheapest ask that is not yours
        -- -- is the single most useful line in the section: losing it exactly when the window
        -- is too small to show much else is backwards.
        row.sectionLabel:SetText(entry.title
          .. (entry.hint and entry.hint ~= "" and ("  " .. DIM_HEX .. entry.hint .. "|r") or ""))
        for _, column in ipairs(COLUMNS) do row.cells[column.key]:SetText("") end
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
        local sourceLabel = ({ goldcap = "GoldCap", auction_house = "Auction House",
          goldcap_buy = GC.L["Buy run"], manual = "entered by hand" })[entry.batch.source]
          or (entry.batch.source or "manual")
        -- The evidence word stays: it is how the player knows whether that cost is a confirmed
        -- invoice or a guess, which is exactly the thing this whole tab refuses to fake. The
        -- unit price no longer repeats here -- the COST/LISTED cells two columns over already
        -- carry the unit and total, and this line was the one place on the row saying the same
        -- number twice.
        -- Pooled rows keep whatever colour the last kind painted: a dim detail line must not
        -- bleed into the next render's batch text.
        setColor(row.subItem, Theme.color.fg)
        if entry.batch.source == "craft" then
          -- A craft was not bought, and calling it a purchase is exactly the kind of small
          -- untruth this tab exists not to tell. The verb already says where the units came
          -- from, so the source word would only say it twice. The count is crafting RUNS, not
          -- crafts: one Create All press settles as one batch however many times it fired.
          row.subItem:SetText((GC.L["×%d%s · made %s · %s"]):format(
            entry.batch.originalQty or entry.batch.quantity or 0,
            purchases and purchases > 1 and (" · %d crafting runs"):format(purchases) or "",
            when, entry.batch.evidence or GC.L["unknown evidence"]))
        else
          row.subItem:SetText((GC.L["×%d%s · bought %s · %s · %s"]):format(
            entry.batch.originalQty or entry.batch.quantity or 0,
            purchases and purchases > 1 and (" · %d purchases"):format(purchases) or "",
            when, sourceLabel, entry.batch.evidence or GC.L["unknown evidence"]))
        end
        row.cells.cost:SetText(formatCell(entry.batch.unitCost)); row.cells.listed:SetText(formatCell(entry.batch.totalCost)); row.cells.market:SetText("")
        row.cells.profit:SetText("")
        row.cells.status:SetText((entry.batch.remainingQty or 0) > 0
          and ("%d still unsold"):format(entry.batch.remainingQty) or "all sold")
        setColor(row.cells.status, Theme.color.fgDim)
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
        row.subItem:SetText((GC.L["×%d listed at %s each"]):format(
          entry.lot.quantity, formatCell(entry.lot.unitPrice)))
        row.cells.listed:SetText(formatCell(total))
        -- Repost only cancels this lot -- Core/SellPositions.lua's BuildRepostPlan prices that
        -- cancel at exactly the fresh quote, and nothing here ever posts at anything else. The
        -- actual relist happens later, once the units are back in the bags, through the
        -- ordinary Post path (BuildPostPlan), which DOES apply the queue/overcut/floor raise --
        -- so this cell shows that as a DISPLAY of what the units will be posted at once they
        -- are back on hand, not a number Repost itself uses. `queue` never reaches a listed
        -- lot's own recommendation (RepostAdvice never passes it a targetUnit), so only
        -- overcut/floor are worth predicting here.
        if p.displayMarketUnit and p.freshMarketUnit then
          local rec = type(p.recommendation) == "table" and p.recommendation.rec or nil
          local repostUnit = p.displayMarketUnit
          if type(rec) == "table" and (rec.mode == "overcut" or rec.mode == "floor")
              and type(rec.unit) == "number" and rec.unit > repostUnit then
            repostUnit = rec.unit
          end
          row.cells.market:SetText("» " .. formatCell(repostUnit))
          setColor(row.cells.market, Theme.color.gold)
        else
          row.cells.market:SetText(GC.L["» needs price"])
          setColor(row.cells.market, Theme.color.fgDim)
        end
        row.cells.profit:SetText("")
        row.cells.status:SetText(recommendationText(p.recommendation))
        setColor(row.cells.status, Theme.color.fg)
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
          row.subItem:SetText((GC.L["×%d in your bags · Post lists %d of them, the largest stack"]):format(
            inBags, postable))
        elseif postable > 0 then
          row.subItem:SetText((GC.L["×%d in your bags, ready to list"]):format(postable))
        else
          row.subItem:SetText((GC.L["×%d in your bags · no stack GoldCap can identify exactly"]):format(inBags))
        end

        if postable > 0 then
          -- Say what Post will charge before it is clicked -- postRecommendation.unit when
          -- there is one (floor/queue/overcut raises included), not the raw cheapest ask:
          -- BuildPostPlan lists at postRecommendation.unit when it applies, and this cell has
          -- to name the same price or it is exactly the "two different numbers" defect the
          -- floor-raise comment in Core/SellPositions.lua describes.
          local postUnit = type(p.postRecommendation) == "table" and type(p.postRecommendation.unit) == "number"
            and p.postRecommendation.unit > 0 and p.postRecommendation.unit or p.displayMarketUnit
          if postUnit and p.freshMarketUnit then
            row.cells.market:SetText("» " .. formatCell(postUnit))
            setColor(row.cells.market, Theme.color.gold)
          else
            row.cells.market:SetText(GC.L["» needs price"])
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
          showRowAction(row, GC.L["Set cost"], function() openCostDialog(p) end)
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
      -- An OPEN position and the panel under it are one block, so the row wears the same gold
      -- the panel's left rail does instead of its turn in the white zebra. Without it the pair
      -- read as two unrelated rows that happened to land next to each other.
      if entry.kind == "position" and expanded[p.positionKey] then
        local gc3 = Theme.color.gold
        row.zebra:SetVertexColor(gc3[1], gc3[2], gc3[3], 0.10)
      else
        row.zebra:SetVertexColor(zc2[1], zc2[2], zc2[3], (listIndex % 2 == 1) and (zc2[4] or 0.04) or 0)
      end
      -- The drawer is a SURFACE, not a shaded row: at the well's usual half alpha the window
      -- behind it (and, docked, the auction house's own art at the edges) mixed straight
      -- through and left the panel looking washed out rather than the flat panel colour the
      -- design is drawn in. Every other sub-row keeps the translucent well, so this is set on
      -- both branches -- rows are pooled and one would otherwise inherit the other's fill.
      local pnc = Theme.color.panel
      local phc2 = Theme.color.panelHi
      if entry.kind == "drawer" then
        row.well:SetVertexColor(pnc[1], pnc[2], pnc[3], 1)
      else
        row.well:SetVertexColor(phc2[1], phc2[2], phc2[3], 0.5)
      end
      -- Pooled rows are rebound to a different kind on every render, so a book row's own
      -- widgets have to be put away by whatever kind takes the row next.
      if entry.kind ~= "price" and entry.kind ~= "drawer" then
        row.priceBox:Hide(); row.priceNote:Hide()
        for _, chip in ipairs(row.priceChips) do chip:Hide() end
      end
      -- Same rule, and the drawer has the most to put away: five book lines and four headings.
      -- A pooled row that painted a panel last render would otherwise keep every one of them
      -- on top of whatever line it becomes next.
      if entry.kind ~= "drawer" then
        row.drawerPriceHead:Hide(); row.drawerBookHead:Hide()
        row.drawerHint:Hide(); row.drawerStand:Hide(); row.drawerFacts:Hide()
        for _, line in ipairs(row.bookLines) do
          line.price:Hide(); line.qty:Hide(); line.bar:Hide()
        end
      end
      -- The second lines belong to a position alone; a pooled row that was one last render
      -- must not keep its queue marks under a lot or a batch.
      local twoLine = entry.kind == "position"
      if twoLine then row.priceStand:Show(); row.grossNote:Show()
      else row.priceStand:Hide(); row.grossNote:Hide() end
      for _, mark in ipairs(row.standMarks) do
        if twoLine then mark:Show() else mark:Hide() end
      end
      if entry.kind == "position" then
        row.spine:Hide()
        row.divider:Show()
        row.zebra:Show()
        row.well:Hide()
        row.cells.item:Show()
        row.itemStock:Show()
        row.subItem:Hide()
        row.sectionLabel:Hide()
        row.sectionRule:Hide()
        local icon = nil
        if p.itemID and C_Item and C_Item.GetItemIconByID then
          local ok, texture = pcall(C_Item.GetItemIconByID, p.itemID)
          icon = ok and texture or nil
        end
        -- Item 4 (addon polish batch): no icon means nothing to indent past -- the old
        -- unconditional 26 left the name floating in a blank gap for a row with no
        -- resolvable icon.
        row.itemInset = icon and 26 or 0
        if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
      elseif entry.kind == "fold" then
        -- A heading in the list's own column, not a child of the row above it: no spine, no
        -- well, and the label starts where the item names do.
        row.itemInset = 2
        row.icon:Hide(); row.spine:Hide(); row.divider:Hide()
        row.zebra:Hide(); row.well:Hide()
        row.cells.item:Hide(); row.itemStock:Hide(); row.subItem:Hide()
        row.sectionLabel:Show(); row.sectionRule:Show()
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
        row.itemStock:Hide()
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
      if entry.panel then
        -- The panel is the surface these sit on: no well, no spine bracketing them to a row
        -- that is a column away.
        row.spine:Hide(); row.well:Hide(); row.zebra:Hide()
        layoutDetailRow(row)
      else
        layoutCells(row)
      end
    end
  end
  if container.paintInspector then container.paintInspector(openPosition) end
  -- Measured from what was actually placed, not from #entries: a multi-slot entry occupies
  -- more than one row's worth, and a scroll child sized by entry COUNT would clip the drawer.
  content:SetHeight(math.max(ROW_HEIGHT, placedHeight))
  if detailContent then detailContent:SetHeight(math.max(ROW_HEIGHT, detailHeight)) end
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
    setStatus(GC.L["Nothing queued to post"])
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
    setStatus(GC.L["Could not find the queue's next item to post — try again"])
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
    setStatus(GC.L["Nothing queued to cancel"])
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
    setStatus(GC.L["Could not find the queue's next lot to cancel — try again"])
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
  -- The headings are otherwise only ever stamped when the DECK changes (renderRows), and this
  -- tab spends most of its life hidden behind Deals or Sold: a one-line FontString that was on
  -- screen when its parent hid can come back with its text simply not drawn, and SetText is
  -- what the client needs to draw it again (UI/SniperFrame.lua's updateHeaderSortIndicators
  -- carries the full story). Unconditional, from the deck the header is currently showing.
  if container and container.header then
    paintHeaderText(container.header, container.headerDeck)
  end
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
  -- A PRESS of Refresh is the player asking for the list to be re-ordered; the walk's own
  -- five-second repeat (`automatic`) is not, and neither is opening the tab mid-session. This
  -- is the one place a settled order is deliberately given up -- see rowPlaces.
  if not automatic then rowPlaces = {} end
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
  setStatus(automatic and GC.L["Checking prices…"] or GC.L["Refreshing listings…"])
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
    setStatus(GC.L["Waiting for Auction House…"])
  elseif not sent then
    refresh.phase = "idle"
    setStatus(GC.L["Auction House is not open"])
  end
  armPhaseWatchdog()
end
function GC.Sell.Reset()
  abandonInFlightQuote()
  refresh.generation = refresh.generation + 1
  refresh.phase, refresh.queue, refresh.index = "idle", {}, 0
  -- The rest of what the walk accumulates goes with the quote cache. It used to outlive it: the
  -- rested-item list carried a stale "nothing listed" into a session that had not asked anything
  -- yet, the skipped count made the next pass finish with "N did not answer" about items from
  -- the previous one, and a click's pending price request survived a close it could no longer be
  -- answered by.
  --
  -- refresh.drain is the deliberate exception and must NOT be cleared here: its whole job is to
  -- consume the late terminal of a request that was in flight when this ran, which is precisely
  -- a request from before the reset (spec/sell_action_safety_spec.lua's close test, and
  -- sell_refresh_state_spec's [I1], both pin that).
  refresh.priority = {}
  refresh.awaitingPriority = nil
  refresh.skipped = 0
  refresh.waitingNoted = false
  for key in pairs(emptyAnswers) do emptyAnswers[key] = nil end
  for key in pairs(ownedAwaitingKind) do ownedAwaitingKind[key] = nil end
  postedGrace = nil
  GC.QuoteCache.Clear(quotes)
  -- The SESSION cache goes, the persisted mirror STAYS. Reset's only caller is the auction
  -- house closing (UI/SniperFrame.lua), which is not the player asking to forget anything --
  -- it is the live session ending. Wiping the store there defeated the whole point of keeping
  -- one: every visit re-priced every position from a dash, and the tab spent its first half
  -- minute saying "—" about prices it had known thirty seconds earlier (reported in game,
  -- "ЦІНИ 4/17" on a list of seventeen). The store already carries its own age limit
  -- (QUOTE_PERSIST_MAX_AGE, three days) and every row it seeds is drawn with its real age, so
  -- nothing here can pass an old price off as a live one.
  --
  -- Seeding is armed again with it: seedPersistedQuotes runs once per session, and without
  -- this the next compose would find an empty live cache and no permission to refill it.
  quotesSeeded = false
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
  -- Two rows of chrome and a footer, down from three rows of chrome. The three stat cards that
  -- used to own row 3 were 40px of ACCOUNTING sitting above the work; they are one quiet line
  -- in the footer now, beside the bulk action, where the eye ends rather than where it starts.
  --   row 1 (y   0): [TO POST N][MY LOTS N] ·········· [NO COST][READY][REFRESH]
  --   row 2 (y -34): column headings for the deck below
  --   list  (y -52) ......................................................... (to footer)
  --   footer (bottom, h32): [POST N] head label ··· held-back · cost / listed / profit
  -- Each row still owns its whole width: the layout this replaced let two anchor chains grow
  -- toward each other on one shared row and collide at ordinary window widths (the queue's head
  -- label ran under the filter chips; the cancel cluster ran under EST. PROFIT).
  -- The dock: one raised surface along the bottom carrying the deck's bulk action, what it
  -- will do next, what is happening, and the session's three totals. It used to be a bare strip
  -- of widgets on the window's own background, which read as leftovers under the list rather
  -- than as the place the tab is driven from.
  local phc = Theme.color.panelHi
  local dockFill = Theme.SlicedTexture(container, "BACKGROUND", Theme.MEDIA .. "plaque.png",
    { phc[1], phc[2], phc[3], 1 }, 12)
  dockFill:SetPoint("BOTTOMLEFT"); dockFill:SetPoint("BOTTOMRIGHT")
  dockFill:SetHeight(DOCK.H)
  container.dockFill = dockFill
  local refreshButton = Theme.Button(container, "ghost", "plaque")
  -- 104, not 72: the busy label is "PRICING 10/24" (see paintRefreshButton), which is 101.4px
  -- at mono-10 and Theme.Scale() 1.3 (JetBrains Mono ~0.6em/char -> 7.8px/char) -- a button
  -- sized for "REFRESH" alone would have let that overflow its own edges into the filter chip
  -- beside it.
  refreshButton:SetSize(104, 26); refreshButton:SetPoint("TOPRIGHT", 0, 0); refreshButton:SetLabel(GC.L["REFRESH"])
  container.refreshButton = refreshButton
  -- Wrapped, not passed directly: OnClick hands the handler (self, button, down),
  -- so GC.Sell.Refresh would receive the button as its `automatic` flag -- truthy
  -- -- and every press would take the stand-aside path that exists for the timer.
  -- The button would have gone on doing nothing, which is the bug this argument
  -- was added to fix.
  refreshButton:SetScript("OnClick", function() GC.Sell.Refresh() end)
  -- Two chips, where there were five. Not a cut: three of the old five became the DECK switch
  -- below ("in bags" and "listed" are the decks themselves) and "GC" was a provenance cut
  -- sitting where a player expected "my auctions" -- provenance stays on the tooltip. What is
  -- left are the two questions that NARROW a deck instead of replacing it, which is why they
  -- are booleans and can both be on at once. The old five could not express that at all.
  container.filterButtons = {}
  local previous = refreshButton
  -- State on the chip itself: SetVariant, never a second overlaid button (one control, two
  -- variants -- see the addon's engineering notes on buttons).
  local function paintFilterChips()
    for _, id in ipairs(CHIP_IDS) do
      local chip = container.filterButtons[id]
      if chip then
        -- Both chips ask POST-deck questions, so on LISTED they are disabled rather than
        -- hidden: a control that vanishes reads as a bug, one that dims reads as "not here".
        local onPostDeck = filterMode ~= "listed" and filterMode ~= "cancelqueue"
        chip:SetVariant(chips[id] and onPostDeck and "active" or "ghost")
        if onPostDeck then chip:Enable() else chip:Disable() end
      end
    end
  end
  container.paintFilterChips = paintFilterChips
  for slot, id in ipairs(CHIP_IDS) do
    local button = Theme.Button(container, "ghost", "badge")
    button:SetSize(CHIP_WIDTHS[slot], 20)
    button:SetPoint("RIGHT", previous, "LEFT", -2, 0)
    button:SetLabel(GC.L[CHIP_LABELS[slot]])
    button:SetScript("OnClick", function()
      chips[id] = not chips[id]
      -- "queue" and "cancelqueue" are transient FOCUS states, not decks, and nothing ever
      -- cleared them: press the POST control once and the tab rendered the queue's own order
      -- for the rest of the session, with these chips lighting up over a list they could not
      -- narrow. Pressing a chip is a request to filter a deck, so give the chip its deck back.
      if filterMode == "queue" then filterMode = "post"
      elseif filterMode == "cancelqueue" then filterMode = "listed" end
      -- A chip changes which rows are on screen, so the order is the player's to have again.
      rowPlaces = {}
      -- Through the container, not the local: paintDeckSwitch is declared below this loop.
      if container.paintDeckSwitch then container.paintDeckSwitch() end
      paintFilterChips()
      renderRows()
    end)
    container.filterButtons[id] = button
    previous = button
  end

  -- The deck switch: the one control this redesign turns on. "What can I list" and "what is
  -- already listed" are two jobs, and serving both from one table is what forced the action
  -- column to change its verb from row to row -- Post here, Repost there, Set cost on the next
  -- -- so no player could ever read ahead. One deck, one verb.
  container.deckButtons = {}
  local function deckCounts()
    local post, listed = 0, 0
    for _, position in ipairs(positions) do
      local bags = type(position.bagQty) == "number" and position.bagQty or 0
      local live = type(position.listedQty) == "number" and position.listedQty or 0
      if bags > 0 or live == 0 then post = post + 1 end
      if live > 0 then listed = listed + 1 end
    end
    return post, listed
  end
  -- Deliberately reads the deck the QUEUE focus states belong to: "queue" is a focus inside the
  -- post deck and "cancelqueue" one inside listed, so pressing a queue control must not leave
  -- the switch painting neither half as active.
  local function activeDeck()
    return (filterMode == "listed" or filterMode == "cancelqueue") and "listed" or "post"
  end
  local function paintDeckSwitch()
    local post, listed = deckCounts()
    local counts = { post = post, listed = listed }
    for slot, id in ipairs(DECK_IDS) do
      local button = container.deckButtons[id]
      if button then
        button:SetLabel((GC.L[DECK_LABELS[slot]]):format(counts[id] or 0))
        button:SetVariant(activeDeck() == id and "active" or "ghost")
      end
    end
  end
  container.paintDeckSwitch = paintDeckSwitch
  local deckPrevious
  for _, id in ipairs(DECK_IDS) do
    local button = Theme.Button(container, "ghost", "plaque")
    -- 128, sized for "TO POST 88" at mono-10 and Theme.Scale() 1.3 (~7.8px/char = 78px) with
    -- room for the rounded plaque's own inset, the same way REFRESH is sized for "PRICING 10/24".
    button:SetSize(128, 26)
    if deckPrevious then button:SetPoint("LEFT", deckPrevious, "RIGHT", 4, 0)
    else button:SetPoint("TOPLEFT") end
    button:SetScript("OnClick", function()
      filterMode = id
      rowPlaces = {} -- a different deck is a different list; settle it fresh
      -- A deck change invalidates whatever the other deck's chips were narrowing to, and an
      -- expansion opened on a row that is not on this deck would render against nothing.
      paintDeckSwitch(); paintFilterChips(); renderRows()
    end)
    container.deckButtons[id] = button
    deckPrevious = button
  end
  paintDeckSwitch()
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
  queueButton:SetPoint("BOTTOMLEFT", DOCK.PAD, (DOCK.H - 26) / 2)
  queueButton:SetScript("OnClick", function() onQueueClick() end)
  container.queueButton = queueButton

  -- Two lines beside the button: what the next press does, and under it what is happening.
  local queueLabel = Theme.Num(container, 10)
  queueLabel:SetPoint("LEFT", queueButton, "RIGHT", 10, 7)
  queueLabel:SetJustifyH("LEFT")
  queueLabel:SetWordWrap(false)
  container.queueLabel = queueLabel

  local dockStatus = Theme.Num(container, 9)
  dockStatus:SetPoint("LEFT", queueButton, "RIGHT", 10, -7)
  dockStatus:SetJustifyH("LEFT")
  dockStatus:SetWordWrap(false)
  setColor(dockStatus, Theme.color.fgMuted)
  container.dockStatus = dockStatus

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
    GameTooltip:AddLine(GC.L["Held back from the queue"], 1, 0.82, 0)
    if #queueSkipped == 0 then
      GameTooltip:AddLine(GC.L["Nothing is being held back."], 0.85, 0.85, 0.85, true)
    else
      for _, skip in ipairs(queueSkipped) do
        GameTooltip:AddLine(("%s — %s"):format(skip.itemName or GC.L["Item"],
          (QUEUE_SKIP_TEXT[skip.reason] and GC.L[QUEUE_SKIP_TEXT[skip.reason]]
            or GC.L["not ready to post"])), 0.85, 0.85, 0.85, true)
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
  -- The SAME footer slot as the post queue's control, not the far end of a row: only one deck
  -- is ever on screen, so only one of these is ever shown, and putting them in one place means
  -- the bulk action never moves under the cursor when the deck changes.
  cancelButton:SetPoint("BOTTOMLEFT", DOCK.PAD, (DOCK.H - 26) / 2)
  cancelButton:SetScript("OnClick", function() onCancelQueueClick() end)
  container.cancelButton = cancelButton

  local cancelHeldBack = Theme.Num(container, 9)
  cancelHeldBack:SetJustifyH("LEFT")
  setColor(cancelHeldBack, Theme.color.fgDim)
  cancelHeldBack:SetPoint("LEFT", cancelButton, "RIGHT", 10, 7)
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
    GameTooltip:AddLine(GC.L["Held back from cancelling"], 1, 0.82, 0)
    if #cancelSkipped == 0 then
      GameTooltip:AddLine(GC.L["Nothing is being held back."], 0.85, 0.85, 0.85, true)
    else
      for _, skip in ipairs(cancelSkipped) do
        GameTooltip:AddLine(("%s — %s"):format(skip.itemName or GC.L["Item"],
          (QUEUE_SKIP_TEXT[skip.reason] and GC.L[QUEUE_SKIP_TEXT[skip.reason]]
            or GC.L["not ready to cancel"])), 0.85, 0.85, 0.85, true)
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
  queueLabel:SetPoint("RIGHT", queueHeldBack, "LEFT", -10, 0)
  -- RIGHT edge deliberately NOT set here: the ledger line built further down owns the
  -- footer's right corner, and anchoring both to it painted the held-back count straight
  -- through the profit figure. Bound against the ledger's leftmost label once that exists.
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

  -- The same three figures updateSummary has always written, moved out of 40px of stat cards
  -- sitting ABOVE the work into one right-aligned line in the footer. They are what the session
  -- adds up to -- a thing to glance at on the way out, not a thing to read before starting. The
  -- labels shortened with the move: at Theme.Scale() 1.3 three full phrases plus their figures
  -- would have run into the bulk action sharing this row. See SUMMARY_STAT_LABELS/
  -- SUMMARY_STAT_IDS above for what each one is and why.
  container.summary = {}
  local ledgerPrevious
  for i, id in ipairs(SUMMARY_STAT_IDS) do
    local stat = { id, SUMMARY_STAT_LABELS[i] }
    -- Label over figure in a fixed-width column, where they used to run inline as "LABEL
    -- figure LABEL figure": stacked, three totals take half the width, and that width is what
    -- the line beside the bulk action needs at the default window.
    local value = Theme.Num(container, 10, true)
    value:SetJustifyH("RIGHT"); value:SetWordWrap(false)
    value:SetWidth(DOCK.STAT_W)
    if ledgerPrevious then value:SetPoint("RIGHT", ledgerPrevious, "LEFT", -8, 0)
    else value:SetPoint("RIGHT", container, "BOTTOMRIGHT", -DOCK.PAD, DOCK.H / 2 - 7) end
    local label = Theme.Num(container, 9)
    label:SetJustifyH("RIGHT"); label:SetWordWrap(false)
    label:SetWidth(DOCK.STAT_W)
    label:SetPoint("BOTTOMRIGHT", value, "TOPRIGHT", 0, 3)
    label:SetText(GC.L[stat[2]]); setColor(label, Theme.color.fgDim)
    container.summary[stat[1]] = value
    container.summaryLabels = container.summaryLabels or {}
    container.summaryLabels[stat[1]] = label
    if stat[1] == "profit" then
      -- Same invisible-hit-frame trick the stat card used, for the same reason: a FontString
      -- cannot take mouse scripts, and the partial/missing detail is read from
      -- container.summaryProfitDetail LIVE at hover time so it can never go stale between
      -- renders. Covers the label as well as the figure -- the two read as one control.
      local hit = CreateFrame("Frame", nil, container)
      hit:SetPoint("TOPLEFT", label, "TOPLEFT", 0, 2)
      hit:SetPoint("BOTTOMRIGHT", value, "BOTTOMRIGHT", 0, -2)
      hit:EnableMouse(true)
      hit:SetScript("OnEnter", function(self)
        if not GameTooltip or not container.summaryProfitDetail then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(GC.L["Est. profit"], 1, 0.82, 0)
        GameTooltip:AddLine(
          GC.L["at the price GoldCap expects these to sell for, after the 5% cut — not your asking price"],
          0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(container.summaryProfitDetail, 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(GC.L["Positions without a cost or a live price are excluded."],
          0.85, 0.85, 0.85, true)
        GameTooltip:Show()
      end)
      hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      container.summaryProfitHit = hit
    end
    ledgerPrevious = value
  end
  -- The leftmost thing in the ledger line, whatever it turned out to be: the held-back counter
  -- and the queue's head label chain LEFT from here, so the footer's two halves can never
  -- overlap however long either grows.
  -- Re-run on every resize: under DOCK.NARROW the ledger keeps AT MARKET alone, and whatever
  -- is leftmost afterwards is what the two lines beside the bulk action stop short of. The
  -- held-back counter rides the upper line (14 above a figure's own centre), the status the
  -- lower one, level with the figures.
  local function layoutLedger()
    local narrow = (ROW_WIDTH or 0) < DOCK.NARROW
    local left
    for _, id in ipairs(SUMMARY_STAT_IDS) do
      local value, label = container.summary[id], container.summaryLabels[id]
      if id == "profit" or not narrow then
        value:Show(); label:Show()
        left = value
      else
        value:Hide(); label:Hide()
      end
    end
    container.ledgerLeft = left
    queueHeldBack:ClearAllPoints()
    queueHeldBack:SetPoint("RIGHT", left, "LEFT", -12, 14)
    dockStatus:ClearAllPoints()
    dockStatus:SetPoint("LEFT", queueButton, "RIGHT", 10, -7)
    dockStatus:SetPoint("RIGHT", left, "LEFT", -12, 0)
  end
  container.layoutLedger = layoutLedger
  layoutLedger()
  local header = CreateFrame("Frame", nil, container)
  -- Kept on the container so renderRows can re-lay it out when the deck changes; see its own
  -- comment for why that cannot live in the deck buttons' click handler.
  container.header = header
  container.headerDeck = "post"
  header:SetPoint("TOPLEFT", 0, -34); header:SetPoint("TOPRIGHT", 0, -34); header:SetHeight(16); header.cells = {}
  header.itemInset = 26 -- line the ITEM heading up with the names, not with the icons
  for _, column in ipairs(COLUMNS) do
    local cell = Theme.Num(header, 9); cell:SetWordWrap(false); cell:SetText(""); header.cells[column.key] = cell
    -- One line, hard capped -- the pair every other single-line cell in the kit carries
    -- (UI/SniperFrame.lua's buildHeaderCell): this row is 16px tall, and a line that does
    -- not fit the height it is given is not drawn at all.
    cell:SetMaxLines(1)
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
      -- Translated at READ time -- see HEADER_HELP's own comment for why the table
      -- itself cannot hold GC.L lookups.
      local body = {}
      for i = 1, #help[2] do body[i] = GC.L[help[2][i]] end
      explain(hit, GC.L[help[1]], body)
    end
  end
  -- Separates the column headings from the first row now that both read in the same mono
  -- font -- without it the header row visually fused with row 1.
  local rule = header:CreateTexture(nil, "ARTWORK")
  local bc = Theme.color.border
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
  paintHeaderText(header, "post")
  layoutCells(header)
  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", 0, -52)
  -- Stops above the footer instead of running to the container's own bottom edge: the bulk
  -- action and the ledger line live there now, and a list that scrolled under them would put
  -- rows behind a control that can spend gold.
  scroll:SetPoint("BOTTOMRIGHT", 0, DOCK.H + 6)
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

  -- The detail panel: what a position opens INTO, beside the list instead of inside it. Opening
  -- a row used to push ten rows of panel, lots and purchases into the list under it, so the
  -- list a seller was working down scrolled away from under the cursor on every click. The
  -- list now stays exactly where it is, and the panel has the height for the whole book.
  --
  -- From INSP.DOCK_MIN up it takes a column of its own and the list narrows to make room;
  -- under that it lies over the list's right side as a sheet (see applyListGeometry). Its rows
  -- are the SAME pooled rows renderRows has always made -- re-parented, not rebuilt -- so every
  -- Post, Repost and Remove in it runs the code, and holds the pin, it always has.
  local inspector = CreateFrame("Frame", nil, container)
  inspector:SetPoint("TOPRIGHT", 0, -34)
  inspector:SetPoint("BOTTOMRIGHT", 0, DOCK.H + 6)
  inspector:SetWidth(INSP.W)
  -- Above the list it may be lying over, and swallowing its own mouse: a click on the panel's
  -- background must not land on whichever row sits behind it.
  inspector:SetFrameLevel((container:GetFrameLevel() or 0) + 20)
  inspector:EnableMouse(true)
  inspector:Hide()
  container.inspector = inspector
  local ipc = Theme.color.panel
  local inspectorFill = Theme.SlicedTexture(inspector, "BACKGROUND", Theme.MEDIA .. "card.png",
    { ipc[1], ipc[2], ipc[3], 1 }, 24)
  inspectorFill:SetAllPoints(inspector)
  local ibc = Theme.color.border
  local inspectorEdge = Theme.SlicedTexture(inspector, "BORDER", Theme.MEDIA .. "ring.png",
    { 1, 1, 1, (ibc[4] or 0.06) * 2 }, 24)
  inspectorEdge:SetAllPoints(inspector)

  inspector.icon = inspector:CreateTexture(nil, "ARTWORK")
  inspector.icon:SetSize(28, 28)
  inspector.icon:SetPoint("TOPLEFT", INSP.PAD + 2, -10)
  -- Guarded for busted: most of this suite's frame doubles hand back textures that were never
  -- taught SetTexCoord, because nothing built at Attach time trimmed an icon before this.
  if inspector.icon.SetTexCoord then inspector.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  inspector.name = Theme.Label(inspector, 13)
  inspector.name:SetJustifyH("LEFT"); inspector.name:SetWordWrap(false)
  inspector.stock = Theme.Label(inspector, 10)
  inspector.stock:SetJustifyH("LEFT"); inspector.stock:SetWordWrap(false)
  setColor(inspector.stock, Theme.color.fgMuted)
  local closeInspector = Theme.Button(inspector, "ghost", "badge")
  closeInspector:SetSize(22, 20)
  closeInspector:SetPoint("TOPRIGHT", -INSP.PAD, -12)
  closeInspector:SetLabel("X")
  closeInspector:SetScript("OnClick", function()
    for key in pairs(expanded) do expanded[key] = nil end
    renderRows()
  end)
  inspector.close = closeInspector
  local headRule = inspector:CreateTexture(nil, "ARTWORK")
  headRule:SetColorTexture(ibc[1], ibc[2], ibc[3], ibc[4] or 0.06)
  headRule:SetHeight(1)
  headRule:SetPoint("TOPLEFT", INSP.PAD, -INSP.HEAD_H + 2)
  headRule:SetPoint("TOPRIGHT", -INSP.PAD, -INSP.HEAD_H + 2)

  local detailScroll = CreateFrame("ScrollFrame", nil, inspector, "UIPanelScrollFrameTemplate")
  detailScroll:SetPoint("TOPLEFT", 4, -INSP.HEAD_H)
  detailScroll:SetPoint("BOTTOMRIGHT", -INSP.SCROLL_GUTTER, 6)
  detailContent = CreateFrame("Frame", nil, detailScroll)
  detailContent:SetSize(INSP.W - 4 - INSP.SCROLL_GUTTER, ROW_HEIGHT)
  detailScroll:SetScrollChild(detailContent)

  -- The list's own width follows the panel: docked, it ends where the panel's column begins
  -- (the gap is where the list's scroll bar hangs); as a sheet, it keeps the whole width and
  -- the panel covers its right side. Called by renderRows when that changes and by the resize
  -- hook, never per render.
  container.applyListGeometry = function()
    local inset = INSP.docked() and (INSP.W + INSP.GAP) or 0
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 0, -34); header:SetPoint("TOPRIGHT", -inset, -34)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 0, -52); scroll:SetPoint("BOTTOMRIGHT", -inset, DOCK.H + 6)
    content:SetWidth(INSP.listWidth())
    layoutCells(header)
  end

  -- The panel's head: which item this is, and where its stock is. Read off the position at
  -- render time -- the panel is one frame reused for every position, like the cost dialog.
  container.paintInspector = function(position)
    if not position then inspector:Hide(); return end
    local icon
    if position.itemID and C_Item and C_Item.GetItemIconByID then
      local ok, texture = pcall(C_Item.GetItemIconByID, position.itemID)
      icon = ok and texture or nil
    end
    if icon then inspector.icon:SetTexture(icon); inspector.icon:Show() else inspector.icon:Hide() end
    local left = icon and (INSP.PAD + 38) or (INSP.PAD + 2)
    inspector.name:ClearAllPoints()
    inspector.name:SetPoint("TOPLEFT", left, -9)
    inspector.name:SetPoint("RIGHT", closeInspector, "LEFT", -6, 0)
    inspector.stock:ClearAllPoints()
    inspector.stock:SetPoint("TOPLEFT", left, -27)
    inspector.stock:SetPoint("RIGHT", closeInspector, "LEFT", -6, 0)
    local name = position.itemName or GC.L["Item"]
    inspector.name:SetText(Theme.WithQuality and Theme.WithQuality(name, position.itemID) or name)
    local parts = {}
    if (position.bagQty or 0) > 0 then parts[#parts + 1] = (GC.L["×%d in bags"]):format(position.bagQty) end
    if (position.listedQty or 0) > 0 then parts[#parts + 1] = (GC.L["×%d listed"]):format(position.listedQty) end
    inspector.stock:SetText(#parts > 0 and table.concat(parts, " · ") or GC.SellViewModel.SourceText(position))
    inspector:Show()
  end
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
  local cancel = Theme.Button(dialog, "ghost", "badge"); cancel:SetSize(70, 20); cancel:SetPoint("BOTTOMLEFT", 12, 10); cancel:SetLabel(GC.L["Cancel"]); cancel:SetScript("OnClick", function() dialog:Hide() end)
  local confirm = Theme.Button(dialog, "primary", "badge"); confirm:SetSize(70, 20); confirm:SetPoint("BOTTOMRIGHT", -12, 10); confirm:SetLabel(GC.L["Confirm"]); confirm:SetScript("OnClick", function() confirmCostDialog(dialog) end)
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
      return setDialogError(dialog, GC.L["Enter an exact positive cost"])
    end
    local totalCopper = safeMultiply(q, unitCopper)
    if not totalCopper then
      syncText(dialog.total, "")
      updateTotalPreview(dialog, nil)
      return setDialogError(dialog, GC.L["Enter an exact positive cost"])
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
      return setDialogError(dialog, GC.L["Enter a whole quantity"])
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
        return setDialogError(dialog, GC.L["Enter an exact positive cost"])
      end
      syncText(dialog.total, copperToGoldText(totalCopper))
      updateTotalPreview(dialog, totalCopper)
      setDialogError(dialog)
    elseif dialog.costMode == "total" then
      local totalCopper = dialogGoldPositive(dialog.total)
      if not totalCopper then
        syncText(dialog.unit, "")
        updateTotalPreview(dialog, nil)
        return setDialogError(dialog, GC.L["Enter an exact positive cost"])
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
      return setDialogError(dialog, GC.L["Enter an exact positive cost"])
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
    -- Through the same function a panel opening uses: the width a resize leaves decides
    -- whether the panel still has a column of its own.
    container.listDocked = INSP.docked()
    container.applyListGeometry()
    layoutLedger()
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
-- The throttle flag as the CLIENT reports it, with no side effect.
--
-- driver.isReady() is GC.Util.ThrottleReady(), which past its stuck window answers true on a
-- flag the client is still reporting false. That is the right answer for a sender and the
-- wrong one for a readout of what the CLIENT says, which is what these two printers want.
local function throttleReadyForDisplay()
  return C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady
    and C_AuctionHouse.IsThrottledMessageSystemReady() == true or false
end

GC.slashHandlers.sellstate = function()
  local pending = refresh.pending
  GC.Print((GC.L["sell walk: phase=%s queue=%d index=%d skipped=%d progress %ds ago%s"]):format(
    tostring(refresh.phase), #refresh.queue, refresh.index or 0, refresh.skipped or 0,
    time() - (refresh.progressAt or 0),
    pending and (" · pending item %s for %ds"):format(tostring(pending.itemID), time() - pending.at) or ""))
  local blocking = GC.Sniper and (GC.Sniper.IsSearchCritical or GC.Sniper.IsBusy)
  local rested = 0
  for _, rest in pairs(emptyAnswers) do
    if type(rest) == "table" and type(rest.at) == "number"
        and time() - rest.at <= EMPTY_ANSWER_AGE then rested = rested + 1 end
  end
  GC.Print((GC.L["throttle ready=%s · sniper busy=%s · empty answers resting=%d"]):format(
    tostring(throttleReadyForDisplay()),
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
      local restingAt = restedAt(position.itemID)
      local resting = restingAt ~= nil and (time() - restingAt) <= EMPTY_ANSWER_AGE
      local why
      if position.unresolved and not commodity then
        why = GC.L["identity unresolved (variant item -- not priced by design)"]
      elseif not (inBags or listed) then
        why = GC.L["no stock in bags or listed -- nothing to price for"]
      elseif resting and restedEmptyFresh(position.itemID, time()) then
        why = (GC.L["AH answered empty %ds ago"]):format(time() - restingAt)
      elseif resting then
        -- Rested but never ANSWERED. Printing the line above here is what made a wedged walk
        -- read as a quiet auction house.
        why = (GC.L["no answer %ds ago -- resting"]):format(time() - restingAt)
      else
        why = GC.L["due -- will be asked next pass"]
      end
      shown = shown + 1
      GC.Print(("  %s (%d): %s"):format(tostring(position.itemName or "?"), position.itemID, why))
    end
  end
end

-- `/gc sell`: the pricing walk's state and who holds the shared search slot, printed to
-- chat. For a live client that sits at "PRICING…" -- the walk yields to whatever owns the
-- slot and there is otherwise nothing on screen that says which gate it is waiting on.
function GC.Sell.DebugPrint()
  local sniper = GC.Sniper or {}
  local function call(fn, ...) if type(fn) == "function" then return tostring(fn(...)) end return "n/a" end
  GC.Print(("sell walk: phase=%s index=%d/%d pending=%s awaiting=%s gen=%d progress=%ds ago waitingNoted=%s"):format(
    tostring(refresh.phase), refresh.index or 0, #(refresh.queue or {}),
    tostring(refresh.pending and refresh.pending.itemID), tostring(refresh.awaiting),
    refresh.generation or 0, time() - (refresh.progressAt or time()), tostring(refresh.waitingNoted)))
  -- `apiReady` is the CLIENT's own flag, read with no side effect -- see throttleReadyForDisplay.
  GC.Print(("slot: ahOpen=%s apiReady=%s searchCritical=%s busy=%s paging=%s quietZone=%s quietSince=%s"):format(
    call(sniper.IsAHOpen),
    tostring(throttleReadyForDisplay()),
    call(sniper.IsSearchCritical), call(sniper.IsBusy),
    sniper._bookPass and call(function() return sniper._bookPass:IsPaging() end) or "n/a",
    call(sniper._QuietZoneOpen), tostring(sniper._quietSince)))
  local status = statusOwner and statusOwner.status and statusOwner.status.GetText and statusOwner.status:GetText()
  GC.Print("status: " .. tostring(status))
  local t = GC.Util.throttleStats
  GC.Print(("throttle events: queued=%d dropped=%d ready=%d forcedSends=%d"):format(t.queued, t.dropped, t.ready, t.forced))
end
