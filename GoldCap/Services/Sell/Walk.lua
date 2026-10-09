-- The Sell tab's pricing walk: one throttled search per item, the deck on screen first, each answer
-- read into a quote and its book; the timers that let an item that does not answer go, the
-- watchdog that lets a phase go, the repeat that keeps prices live while the tab is up, and the
-- one-item walk a Post or a Repost asks for. Moved from UI/SellFrame.lua as it was.
local _, GC = ...

local S, View = GC.SellState, GC.SellView
local Quotes, Compose, Owned, Walk = GC.SellQuotes, GC.SellCompose, GC.SellOwned, GC.SellWalk
local exact, context = GC.SellUtil.exact, GC.SellUtil.context
local QUOTE_STALE_SECONDS, SELL_QUOTE_ACTION_AGE = GC.Sell.QUOTE_STALE_SECONDS, GC.Sell.SELL_QUOTE_ACTION_AGE
local QUOTE_REWALK_AGE, EMPTY_ANSWER_AGE = GC.Sell.QUOTE_REWALK_AGE, GC.Sell.EMPTY_ANSWER_AGE

-- How long a yielded pricing walk (purchase in flight, throttle window closed) waits before
-- asking again from the same queue position -- see advanceQuote's retryLater.
local QUOTE_RETRY_SECONDS = 2
-- Gap between automatic re-pricing passes while the tab is open and the auction
-- house is up. Prices stay live on their own instead of waiting for Refresh --
-- which is also why PROFIT / UNIT no longer reads Unknown until you press it.
local WALK_REPEAT_SECONDS = 5
-- A phase that answers no event is a wedge: Refresh used to refuse to run while
-- one was in flight, so a single unanswered owned-auctions query or item-key
-- lookup made the button dead for the rest of the session.
local PHASE_WATCHDOG_SECONDS = 15
local quoteTimeoutToken, keyTimeoutToken = 0, 0

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
-- When this item was last rested, or nil. Written as a table (State.lua's emptyAnswers) and read here so every
-- caller agrees on the shape.
function Walk.RestedAt(itemID)
  local rest = S.emptyAnswers[itemID]
  return type(rest) == "table" and type(rest.at) == "number" and rest.at or nil
end
-- Did the auction house ANSWER, and recently enough that the answer still stands?
function Walk.RestedEmptyFresh(itemID, now)
  local rest = S.emptyAnswers[itemID]
  local at = Walk.RestedAt(itemID)
  return at ~= nil and (now - at) <= EMPTY_ANSWER_AGE and rest.answered == true
end
-- How long a drain tombstone may fence off an item. The fence exists so a LATE answer to an
-- abandoned request cannot be credited to a new request for the same item -- but it used to
-- be permanent, cleared only by the very event that never comes for a silently-lost request,
-- and ONE such item then wedged every later pass in "draining" until the watchdog shot it.
-- Past this window the lost answer is not arriving; the fence lifts and the item is asked
-- again (advanceQuote).
local DRAIN_MAX_SECONDS = 15

-- Whether a position has a row on the deck that is up: bag stock on the posting deck, a live
-- lot on the other. Kept on `refresh` rather than as two more file locals -- this chunk sits at
-- Lua 5.1's limit of 200.
function S.refresh.onDeck(position)
  if S.filterMode == "listed" or S.filterMode == "cancelqueue" then return (position.listedQty or 0) > 0 end
  return (position.bagQty or 0) > 0
end

-- How far the walk has got through the rows of the deck on screen: asked about, out of queued.
-- The queue covers both decks, and the Refresh button read "BOOKS 4/27" over a list of ten.
-- Counted when asked rather than when the queue is built, so a deck change mid-walk is followed.
function S.refresh.deckProgress()
  local shown = {}
  for _, position in ipairs(S.positions) do
    -- By quote id, as the walk queues them: a variant's entry is its own key (_QuoteItemKey).
    if position.itemID and S.refresh.onDeck(position) then shown[position.quoteKey or position.itemID] = true end
  end
  local done, total = 0, 0
  for index, itemID in ipairs(S.refresh.queue) do
    if shown[itemID] then
      total = total + 1
      if index <= S.refresh.index then done = done + 1 end
    end
  end
  return done, total
end

function Walk.Queue()
  local actionable = {}
  for _, position in ipairs(S.positions) do
    local inBags = type(position.bagQty) == "number" and position.bagQty > 0
    local listed = type(position.listedQty) == "number" and position.listedQty > 0
    -- Membership, not just order: a still-fresh quote is excluded from the pass entirely.
    -- Freshness used to decide only the ORDER, so every pass re-asked the server about the
    -- whole tab -- see QUOTE_REWALK_AGE (State.lua) for what that cost. A remembered "nothing
    -- listed" answer counts as fresh too (EMPTY_ANSWER_AGE, State.lua).
    -- Resting, whether the rest was earned by an answer or by silence: both cost the same
    -- throttled round trip to repeat. Only the DISPLAY distinguishes them (see renderRows).
    local quoteID = position.quoteKey or position.itemID
    local restingSince = Walk.RestedAt(quoteID)
    local answeredEmpty = restingSince ~= nil and (time() - restingSince) <= EMPTY_ANSWER_AGE
    -- A PRESS of Refresh is served by the bulk fill (GC.Sell.TrySendBulk): one message
    -- re-prices every commodity on the tab, which is what a press asks for. The walk does not
    -- also re-ask about all of them -- at one search per throttled round trip that is twelve
    -- seconds for a tab of twenty-seven, every press (measured in game). It asks about what is
    -- still owed a real quote: rows never priced, rows gone stale, rows holding a bulk price.
    -- A bulk price is a placeholder the walk still owes a real answer: it has no book under
    -- it and may not back a post (see freshQuote), however young it is.
    local held = S.quotes[quoteID]
    local due = (type(held) == "table" and (held.bulk == true or held.bookless == true))
      or ((position.displayMarketUnit == nil or type(position.quoteAge) ~= "number"
      or position.quoteAge > QUOTE_REWALK_AGE) and not answeredEmpty)
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
  -- The deck on screen first, in the order it is drawn. The queue covers BOTH decks -- stock
  -- in the bags and every live lot -- so a walk of twenty-seven over a deck showing ten spent
  -- its first seconds on rows of the other deck while the ones being looked at waited.
  local need, weight, onScreen, place = {}, {}, {}, {}
  for index, position in ipairs(actionable) do
    onScreen[position] = S.refresh.onDeck(position)
    place[position] = S.rowPlaces[position.positionKey] or math.huge
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
    if onScreen[left] ~= onScreen[right] then return onScreen[left] end
    -- Within the deck on screen, top to bottom as drawn; need and value order the rest, and
    -- break ties between rows that have no place yet.
    if onScreen[left] and place[left] ~= place[right] then return place[left] < place[right] end
    if need[left] ~= need[right] then return need[left] > need[right] end
    if weight[left] ~= weight[right] then return weight[left] > weight[right] end
    return left.__walkOrder < right.__walkOrder
  end)
  local seen, result = {}, {}
  for _, position in ipairs(actionable) do
    local quoteID = position.quoteKey or position.itemID
    if not seen[quoteID] then
      seen[quoteID], result[#result + 1] = true, quoteID
      if #result >= QUOTE_WALK_CAP then break end
    end
  end
  return result
end

function Walk.ScheduleExpiry()
  S.quoteExpiryGeneration = S.quoteExpiryGeneration + 1
  local token = S.quoteExpiryGeneration
  if not (C_Timer and C_Timer.After) then return end
  local delay
  for _, position in ipairs(S.positions) do
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
    if token ~= S.quoteExpiryGeneration then return end
    Compose.Positions()
    View.render()
  end)
end

-- Whether the Sell CONTENT is the tab actually on screen right now, as opposed to merely
-- attached. `composePositions()`/`GC.Sell.Refresh()` run regardless of which tab the player
-- is looking at (bag counts and the tab badge stay current either way) -- this is the
-- narrower check that guards the expensive part, rebuilding the visible ROWS.
--
-- The container's own flag answers only which tab of the window is up: hiding a parent leaves a
-- child's shown flag alone. So the window is asked too -- closed with its X or Escape while on
-- Sell, or docked and hidden because the player picked another auction-house tab, the walk used
-- to carry on pricing a screen nobody could see. Reopening it runs GC.Sell.Refresh
-- (GC.Sniper.Toggle), which is what picks the walk and any deferred render back up.
function Walk.Shown()
  if not View.isShown() then return false end
  return not (GC.Sniper and GC.Sniper.IsWindowShown) or GC.Sniper.IsWindowShown()
end

function Walk.Live()
  return Walk.Shown() and GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen()
end

-- Keeps the prices on screen live instead of frozen at whatever the last button
-- press fetched. Without it the market column ages out and PROFIT / UNIT falls
-- back to Unknown until the player presses Refresh, which is the sort of chore a
-- program should not be delegating.
local function scheduleNextWalk()
  S.walkRepeatToken = S.walkRepeatToken + 1
  local token = S.walkRepeatToken
  if not (C_Timer and C_Timer.After) then return end
  C_Timer.After(WALK_REPEAT_SECONDS, function()
    if token ~= S.walkRepeatToken or not Walk.Live() then return end
    if S.refresh.phase ~= "done" and S.refresh.phase ~= "idle" and S.refresh.phase ~= "error" then return end
    GC.Sell.Refresh(true)
  end)
end

-- Let go of a request we are no longer waiting for, leaving a tombstone so its
-- late terminal event is consumed rather than mistaken for the next run's.
function Walk.Abandon()
  local pending = S.refresh.pending
  if pending then
    S.refresh.drain[pending.kind .. ":" .. pending.itemID] = {
      abandonedGeneration = pending.generation,
      terminals = 1,
      at = time(),
    }
  end
  S.refresh.pending, S.refresh.awaiting = nil, nil
  quoteTimeoutToken = quoteTimeoutToken + 1
end

function Walk.MarkProgress()
  S.refresh.progressAt = time()
end

local function finishQuoteWalk()
  S.refresh.phase = "done"
  S.refresh.pending, S.refresh.awaiting = nil, nil
  local skipped = S.refresh.skipped or 0
  View.status(skipped > 0
    and (GC.L["Prices up to date · %d did not answer"]):format(skipped)
    or GC.L["Prices up to date"])
  View.render()
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
function Walk.SkipPending(pending, timedOut)
  if S.refresh.pending ~= pending or pending.generation ~= S.refresh.generation then return end
  -- Either way -- an empty answer or no answer at all -- this item earned a rest: re-asking
  -- it on the very next pass is what burned the walk's slots (and, for the silent ones, a
  -- whole request timeout each) on items with nothing to say. See EMPTY_ANSWER_AGE.
  -- `answered` is the honest half: a timeout taught us nothing, so nothing on screen may claim
  -- the auction house said this item is unlisted (see renderRows and /gc sellstate).
  S.emptyAnswers[pending.itemID] = { at = time(), answered = not timedOut }
  if timedOut then
    -- A late terminal event for this request must still be consumed rather than
    -- credited to whatever the walk is asking about by then.
    S.refresh.drain[pending.kind .. ":" .. pending.itemID] = {
      abandonedGeneration = pending.generation,
      terminals = 1,
      at = time(),
    }
  else
    S.quotes[pending.itemID] = nil
    local persisted = Quotes.Persisted()
    if persisted then persisted[pending.itemID] = nil end
  end
  S.refresh.pending = nil
  S.refresh.skipped = (S.refresh.skipped or 0) + 1
  S.refresh.phase = "pricing"
  Walk.MarkProgress()
  Walk.Advance()
end

local function scheduleQuoteTimeout(pending)
  if not (C_Timer and C_Timer.After) then return end
  quoteTimeoutToken = quoteTimeoutToken + 1
  local token = quoteTimeoutToken
  C_Timer.After(QUOTE_STALE_SECONDS, function()
    if token == quoteTimeoutToken then Walk.SkipPending(pending, true) end
  end)
end

-- Three of the refresh phases wait on an event that is not guaranteed to arrive:
-- an owned-auctions query, an item-key lookup, and a drain waiting for the
-- terminal of a request that already timed out. Each one used to hold the
-- machine in a phase Refresh refused to leave, so a single unanswered call made
-- the button dead until the player logged out. This lets the phase go.
function Walk.ArmWatchdog()
  S.watchdogToken = S.watchdogToken + 1
  local token = S.watchdogToken
  if not (C_Timer and C_Timer.After) then return end
  local function tick()
    if token ~= S.watchdogToken then return end
    local phase = S.refresh.phase
    if phase == "idle" or phase == "done" or phase == "error" then return end
    if time() - (S.refresh.progressAt or 0) >= PHASE_WATCHDOG_SECONDS then
      Walk.Abandon()
      S.refresh.phase = "error"
      View.status(GC.L["Auction House did not answer — press Refresh"])
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
function Walk.Parked()
  return View.attached() and not Walk.Shown()
end

-- An item key that never resolves used to hold the pass in "waiting_key" until the phase
-- watchdog declared the whole thing dead -- and startQuoteRefreshFor's one-item walk armed no
-- watchdog at all, so there it sat in "PRICING…" for the rest of the session. One item failing
-- is not the pass failing: rest it and carry on, exactly as skipPendingQuote does.
local function scheduleKeyTimeout(itemID, fromPriority)
  if not (C_Timer and C_Timer.After) then return end
  keyTimeoutToken = keyTimeoutToken + 1
  local token, generation = keyTimeoutToken, S.refresh.generation
  C_Timer.After(QUOTE_STALE_SECONDS, function()
    if token ~= keyTimeoutToken or generation ~= S.refresh.generation then return end
    if S.refresh.phase ~= "waiting_key" or S.refresh.awaiting ~= itemID then return end
    -- Never answered, so nothing here may later read as the auction house saying "nothing
    -- listed" -- see the emptyAnswers comment.
    S.emptyAnswers[itemID] = { at = time(), answered = false }
    S.refresh.awaiting, S.refresh.awaitingPriority = nil, nil
    if fromPriority then table.remove(S.refresh.priority, 1) else S.refresh.index = S.refresh.index + 1 end
    S.refresh.skipped = (S.refresh.skipped or 0) + 1
    S.refresh.phase = "pricing"
    Walk.MarkProgress()
    Walk.Advance()
  end)
end

function Walk.Advance()
  -- "draining" belongs here as much as the other two: the fence branch below parks in it, and
  -- with it excluded nothing could ever come back -- not this function's own retry, not
  -- OnThrottleReady's tail -- so one fenced item held the pass until the watchdog shot it.
  if S.refresh.phase ~= "pricing" and S.refresh.phase ~= "waiting_key" and S.refresh.phase ~= "draining" then return end
  if S.refresh.pending then return end
  -- Stands still while this tab's own bulk batch is out. The arbiter holds its passes for an
  -- outstanding batch for a reason: a search sent on top of an unanswered SearchForItemKeys
  -- takes its answer with it -- the batch never landed, and the walk's first two searches
  -- came back empty besides (seen in game: the top two rows at "--" with the walk at 21/27).
  -- FoldBulk and the ticker are what start it again.
  if GC.Sell.BulkOutstanding() then return end
  if Walk.Parked() then
    -- Give the queue up rather than hold a phase nobody is watching: a held phase is one
    -- Refresh(automatic) refuses to leave.
    S.refresh.queue, S.refresh.index, S.refresh.awaiting, S.refresh.awaitingPriority = {}, 0, nil, nil
    S.refresh.phase = "idle"
    return
  end
  if S.refresh.index >= #S.refresh.queue and #S.refresh.priority == 0 then return finishQuoteWalk() end
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
    S.refresh.retryToken = (S.refresh.retryToken or 0) + 1
    local token, generation = S.refresh.retryToken, S.refresh.generation
    C_Timer.After(QUOTE_RETRY_SECONDS, function()
      if token ~= S.refresh.retryToken or generation ~= S.refresh.generation then return end
      Walk.Advance()
    end)
  end
  if blocking and blocking() then
    -- Yielding is the walk working correctly, not stalling, so the watchdog must
    -- not read it as an unanswered request.
    Walk.MarkProgress()
    View.status(GC.L["Waiting for the purchase to finish…"])
    retryLater()
    return
  end
  -- ...and so, just as much, while a keys batch this tab did not send is still out: one still in
  -- flight from the board the player just left (the Sniper's price caps, its Items poll, BUY's).
  -- Same evidence as the wait for this tab's own batch above -- a search sent on top of it takes
  -- its answer and comes back empty. It is written off after eight seconds while this tab is on
  -- screen (UI/SniperFrame.lua's _KeysOutstanding), so the wait is short, and nothing announces
  -- its end: the walk comes back by itself, like the yields around it.
  if GC.Sniper and GC.Sniper._KeysOutstanding and GC.Sniper._KeysOutstanding() then
    Walk.MarkProgress()
    retryLater()
    return
  end
  if not Quotes.driver.isReady() then
    -- The throttle window is closed -- IsThrottledMessageSystemReady() is false -- so the walk
    -- is stalled on purpose, not stuck, and this must feed the watchdog exactly like the
    -- purchase-yield branch above. I4 (fix wave, sell honesty): the code cannot actually tell
    -- WHY the slot is busy -- another search, the walk's own last query still cooling down, or
    -- the player's own Post -- so say only what is known, once per walk rather than every tick.
    Walk.MarkProgress()
    if not S.refresh.waitingNoted then
      S.refresh.waitingNoted = true
      -- Its own words, not the posting line's: this is the walk pricing rows in the
      -- background, and "Waiting for the Auction House…" beside a queue with nothing posting
      -- read as though a post the player never made was stuck (2026-09-26).
      View.status(GC.L["Checking prices — waiting for the Auction House…"])
    end
    retryLater()
    return
  end
  -- The tab-wide pass is background traffic, and the player outranks it the same way they
  -- outrank Auto, the verify walk and the watch loop: posting or buying on Blizzard's panes,
  -- reading their own search, or working another addon's tab. It was the one sender that did
  -- not ask, so with the Sell tab open it re-priced forty items back to back, every pass,
  -- while Auctionator's Selling tab sat on "Fetching item info..." waiting for a turn on the
  -- same throttled slot (reported in game). A click's own item still goes: that IS the player.
  local playerBusy = GC.AuctionHouseTab and GC.AuctionHouseTab.PlayerIsBusy
    and GC.AuctionHouseTab.PlayerIsBusy()
  -- Three sources, in the order a seller would expect: the key we are already waiting on, then
  -- whatever a click asked for (refresh.priority), then the pass's own queue. A queue item
  -- waiting on its key does not hold a click up while the pass is paused: it is still
  -- queue[index + 1], and is picked up again from there.
  local itemID, fromPriority
  if S.refresh.awaiting and not (playerBusy and not S.refresh.awaitingPriority) then
    itemID, fromPriority = S.refresh.awaiting, S.refresh.awaitingPriority == true
  elseif S.refresh.priority[1] then
    itemID, fromPriority = S.refresh.priority[1], true
  else
    itemID, fromPriority = S.refresh.queue[S.refresh.index + 1], false
  end
  if playerBusy and not fromPriority then
    -- Let go of a key the pass was waiting on, timeout and all: left armed, it fired under the
    -- pause -- posting outlasts it -- and wrote the item off as never having answered, even
    -- with the key already in. It is still queue[index + 1], and is asked for again from there.
    if S.refresh.awaiting and not S.refresh.awaitingPriority then
      S.refresh.awaiting, S.refresh.awaitingPriority = nil, nil
      S.refresh.phase = "pricing"
      keyTimeoutToken = keyTimeoutToken + 1
    end
    Walk.MarkProgress()
    View.status(GC.L["Pricing paused while you use the Auction House"])
    retryLater()
    return
  end
  if Quotes.driver.keyInfo(itemID) then
    local info = Quotes.driver.keyInfo(itemID)
    local kind = info.isCommodity and "commodity" or "item"
    local tombstone = S.refresh.drain[kind .. ":" .. itemID]
    if tombstone and type(tombstone.at) == "number" and time() - tombstone.at > DRAIN_MAX_SECONDS then
      -- The lost answer this fence was guarding against is too old to still arrive -- see
      -- DRAIN_MAX_SECONDS. Lift it and ask for real instead of wedging in "draining".
      S.refresh.drain[kind .. ":" .. itemID] = nil
      tombstone = nil
    end
    if tombstone then
      tombstone.resumeGeneration = S.refresh.generation
      S.refresh.phase = "draining"
      -- Waiting behind a fence is the walk working, not stalling: feed the watchdog and come
      -- back by itself, exactly like the two yield branches above. Without these the only exit
      -- was the watchdog killing the pass over one item, 15s later.
      Walk.MarkProgress()
      View.status(GC.L["Refresh waiting for prior result"])
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
    if Quotes.driver.claimSend and not Quotes.driver.claimSend() then
      Walk.MarkProgress()
      retryLater()
      return
    end
    S.refresh.awaiting, S.refresh.awaitingPriority = nil, nil
    if fromPriority then table.remove(S.refresh.priority, 1) else S.refresh.index = S.refresh.index + 1 end
    S.refresh.pending = { itemID = itemID, kind = kind, generation = S.refresh.generation, at = time() }
    S.refresh.phase = "waiting_result"
    Walk.MarkProgress()
    View.status(fromPriority and GC.L["Checking this item's price…"]
      or (GC.L["Pricing %d/%d…"]):format(S.refresh.index, #S.refresh.queue))
    Quotes.driver.send(itemID)
    scheduleQuoteTimeout(S.refresh.pending)
  else
    -- Armed once per item, not once per poke: OnThrottleReady drives this function again while
    -- the same key is still outstanding, and re-arming there would push the deadline out
    -- forever.
    local alreadyWaiting = S.refresh.awaiting == itemID
    S.refresh.awaiting, S.refresh.awaitingPriority, S.refresh.phase = itemID, fromPriority, "waiting_key"
    if not alreadyWaiting then scheduleKeyTimeout(itemID, fromPriority) end
  end
end

function Walk.Begin()
  if Walk.Parked() then
    -- The tab is not on screen. Composition and the owned lots have already been done by the
    -- caller; the forty throttled round trips have not, and will not until GC.Sell.Show asks.
    S.refresh.queue, S.refresh.index, S.refresh.phase = {}, 0, "idle"
    S.refresh.pending, S.refresh.awaiting, S.refresh.awaitingPriority = nil, nil, nil
    return
  end
  S.refresh.queue, S.refresh.index, S.refresh.phase, S.refresh.pending, S.refresh.awaiting = Walk.Queue(), 0, "pricing", nil, nil
  S.refresh.awaitingPriority = nil
  S.refresh.skipped = 0
  S.refresh.waitingNoted = false
  -- refresh.priority deliberately survives: it holds the items a CLICK asked about, and this
  -- rebuild is exactly what used to throw them away.
  if #S.refresh.queue == 0 and #S.refresh.priority == 0 then return finishQuoteWalk() end
  Walk.Advance()
end

function GC.Sell.OnThrottleReady()
  -- A bulk fill that a press asked for goes before anything else this tab sends. It was tried
  -- only at the press itself and from a once-a-second ticker, and lost both ways: at the press
  -- the throttle was still shut by the walk's own search in flight, and after it the walk took
  -- every ready tick the moment it came -- so the one message that prices the whole tab went
  -- out last, or not at all, and a press looked exactly as slow as it always had (seen in game).
  if S.refresh.bulkWanted and GC.Sell.TrySendBulk() then return end
  -- ...and nothing else goes out over an unanswered batch, the listings query included.
  if GC.Sell.BulkOutstanding() then return end
  if S.refresh.phase == "waiting_owned" then
    local sent, waiting = Owned.Request()
    if sent then
      S.refresh.phase = "owned"
    elseif not waiting then
      S.refresh.phase = "idle"
      View.status(GC.L["Auction House is not open"])
    end
    return
  end
  if S.refresh.pending and time() - S.refresh.pending.at > QUOTE_STALE_SECONDS then
    Walk.SkipPending(S.refresh.pending, true)
    return
  end
  Walk.Advance()
end

local function quoteResolved(kind, itemID, unit, levels)
  local drainKey = kind .. ":" .. itemID
  local tombstone = S.refresh.drain[drainKey]
  if tombstone then
    tombstone.terminals = tombstone.terminals - 1
    local resume = tombstone.terminals <= 0 and tombstone.resumeGeneration == S.refresh.generation
      and S.refresh.phase == "draining"
    if tombstone.terminals <= 0 then S.refresh.drain[drainKey] = nil end
    if resume then
      S.refresh.phase = "pricing"
      Walk.Advance()
    elseif S.refresh.phase == "error" then
      S.refresh.phase = "idle"
    end
    return
  end
  local pending = S.refresh.pending
  if not pending or pending.kind ~= kind or pending.itemID ~= itemID or pending.generation ~= S.refresh.generation then return end
  if not exact(unit) or unit <= 0 then
    -- An empty READ is not an empty ANSWER. GetNum*SearchResults reports whatever result set
    -- the client holds for this key right now, and these events are raised by the Sniper's
    -- searches too -- so a zero can mean "the auction house says nothing is listed" or "our own
    -- reply is not in that slot". Only the first may wipe a quote and gag the item for a
    -- minute; without the client's own proof this is treated as a timeout, which keeps the
    -- quote and leaves the fence to catch the real answer when it lands.
    local proven = Quotes.driver.hasFullResults == nil
      or Quotes.driver.hasFullResults(itemID, kind == "commodity") ~= false
    Walk.SkipPending(pending, not proven)
    return
  end
  S.refresh.pending = nil
  S.refresh.phase = "pricing"
  Walk.MarkProgress()
  S.emptyAnswers[itemID] = nil -- a real price supersedes any remembered GC.L["nothing listed"]
  -- Stamped from when the QUERY went out, not from now. The auction house's results events
  -- carry no request identifier, so a reply cannot be proven to belong to the request waiting
  -- for it (the addon's engineering notes says the same of commodity purchases) -- the drain fence below is
  -- the best this file can do, and past DRAIN_MAX_SECONDS a lost reply can still be credited to
  -- a re-ask. Dating the quote from the ask errs the only safe way: it can make a price look
  -- older than it is, never fresher, so it ages out and is re-asked rather than backing a post.
  GC.QuoteCache.Set(S.quotes, itemID, unit, pending.at or time())
  -- Mirror the result into the persisted store: whatever Set just did to `quotes[itemID]` --
  -- write it in (it never clears here, since `unit` is already known-valid above, but the
  -- contract matches Set's either way) so a later reload can seed from it.
  local persisted = Quotes.Persisted()
  if persisted then
    local resolved = S.quotes[itemID]
    persisted[itemID] = resolved and { unit = resolved.unit, at = resolved.at } or nil
  end
  if unit and S.quotes[itemID] then S.quotes[itemID].levels = levels end
  -- Carry what this walk just saw out of the game (live-prices spec).
  -- Summarize gives the TRUE floor; `unit` here is the competing-not-own
  -- price and must not masquerade as the book minimum. Guarded like every
  -- other cross-module call in this file: specs load only the modules a
  -- given test needs, so GC.Book/GC.Data may be absent outside the client.
  -- An item's own floor only: a variant's answer is one variant's, not the item's.
  local summary = type(itemID) == "number" and GC.Book and GC.Book.Summarize(levels)
  if summary and GC.Data and GC.Data.RecordLiveObservation then
    local scope = context()
    GC.Data.RecordLiveObservation(GC.db, { itemID = itemID,
      region = scope and scope.region, minUnit = summary.minUnit,
      listings = summary.listings, totalQty = summary.totalQty,
      levels = levels }, time())
  end
  Compose.Positions()
  View.render()
  Walk.Advance()
end

-- `itemKey` is the key the answer is for (Core/Init.lua hands it on). An answer for an item-level
-- variant this walk asked about -- or is still draining -- is that variant's, filed under its
-- quote id; anything else goes by itemID, exactly as before.
function GC.Sell.OnItemSearchResults(itemID, itemKey)
  local id = itemID
  local variant = type(itemKey) == "table" and GC.Acquisitions and GC.Acquisitions.PositionKey
    and GC.Acquisitions.PositionKey(itemID, itemKey, false) or nil
  if variant and ((S.refresh.pending and S.refresh.pending.itemID == variant) or S.refresh.drain["item:" .. variant]) then
    id = variant
  end
  quoteResolved("item", id, Quotes.driver.item(id), Quotes.driver.itemLevels(id))
end
function GC.Sell.OnCommoditySearchResults(itemID) quoteResolved("commodity", itemID, Quotes.driver.commodity(itemID), Quotes.driver.commodityLevels(itemID)) end

-- Post and Repost both need a quote fresher than they have. This used to call
-- the full Refresh, which re-queried the owned auctions and then every priced
-- item in the tab, one throttled round trip at a time -- so the "press it again
-- in a moment" the button promised could be a minute away, by which point the
-- quote for THIS item had aged out again and the next click started another
-- walk. That loop is why Post could not be pressed at all.
--
-- One item, one query. If a walk is already running the item is spliced in as
-- its next step rather than restarting anything.
function Walk.RefreshFor(position)
  local itemID = type(position) == "table" and (position.quoteKey or position.itemID) or nil
  if not itemID then return GC.Sell.Refresh() end
  if not (GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen()) then
    View.status(GC.L["Auction House is not open"])
    return
  end
  -- Held OUTSIDE refresh.queue -- see the refresh table's own comment. Inserting into that
  -- array dropped the item into a slot the walk stepped over whenever it was waiting on an
  -- item key, and the queue rebuild that ends the owned phase threw it away outright. On an
  -- idle tab too: refresh.priority is how advanceQuote knows a click asked for this, and a
  -- click is the one request that does not stand aside for the player being busy elsewhere.
  local queued = false
  for _, waitingID in ipairs(S.refresh.priority) do
    if waitingID == itemID then queued = true break end
  end
  if not queued then S.refresh.priority[#S.refresh.priority + 1] = itemID end
  View.status(GC.L["Checking this item's price…"])
  if S.refresh.phase == "idle" or S.refresh.phase == "done" or S.refresh.phase == "error" then
    S.refresh.generation = S.refresh.generation + 1
    S.refresh.queue, S.refresh.index = {}, 0
    S.refresh.pending, S.refresh.awaiting, S.refresh.awaitingPriority = nil, nil, nil
    S.refresh.phase = "pricing"
    Walk.MarkProgress()
    Walk.Advance()
    -- This one-item walk armed no watchdog at all, so an item that landed in "waiting_key" or
    -- behind a drain fence left the machine sitting there: "PRICING…" for the rest of the
    -- session, with the automatic repeat refusing to run (it will not leave a set phase) and
    -- nothing but a manual REFRESH to get out.
    Walk.ArmWatchdog()
  else
    -- A pass paused for the player has nothing in flight and is only waiting on its retry
    -- timer; ask now rather than make the click wait for it. With a request already out, or
    -- outside the pricing phases, advanceQuote declines on its own.
    Walk.Advance()
  end
end
