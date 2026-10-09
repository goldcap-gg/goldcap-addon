-- The three calls the Sniper makes into the Sell tab's services: Refresh (the auction house opens,
-- the tab is shown, the player presses REFRESH), Tick (once a second while it is open) and Reset
-- (it closes; spec/sell_state_reset_spec.lua holds what Reset clears and what it keeps). Moved
-- from UI/SellFrame.lua as they were.
local _, GC = ...

local S, View = GC.SellState, GC.SellView
local Compose, Owned, Walk, Post = GC.SellCompose, GC.SellOwned, GC.SellWalk, GC.SellPost

-- The once-a-second nudge from UI/SniperFrame.lua's auction-house ticker, like GC.Buy.Tick.
function GC.Sell.Tick()
  -- The listings again after a cancel, once, when the throttle lets it through: the client's
  -- own list is a cache that nothing else refreshes (see GC.Sell.cancelledLots).
  if S.refresh.ownedWanted and Owned.Request() then S.refresh.ownedWanted = nil end
  GC.Sell.TrySendBulk()
  -- A batch that never answered: once the wait is over, hand the tab's turn back. Nothing else
  -- would -- the ready event that the walk stood still through has been and gone.
  if S.refresh.bulkSent and not GC.Sell.BulkOutstanding() then
    S.refresh.bulkSent = nil
    GC.Sell.OnThrottleReady()
  end
end

-- `automatic` marks the self-driven repeat below, which politely stands aside
-- for anything already in flight. A press of the button does not: it means "do
-- it now", and refusing while a phase was set is what made the button dead.
-- Whatever was in flight is let go of behind a drain tombstone, exactly the way
-- Reset already did it, so a late terminal event is consumed rather than
-- credited to this run.
function GC.Sell.Refresh(automatic)
  if automatic and S.refresh.phase ~= "idle" and S.refresh.phase ~= "done" and S.refresh.phase ~= "error" then
    return
  end
  -- A PRESS of Refresh is the player asking for the list to be re-ordered; the walk's own
  -- five-second repeat (`automatic`) is not, and neither is opening the tab mid-session. This
  -- is the one place a settled order is deliberately given up -- see rowPlaces.
  if not automatic then S.rowPlaces = {} end
  Walk.Abandon()
  S.quoteExpiryGeneration = S.quoteExpiryGeneration + 1
  S.refresh.generation = S.refresh.generation + 1
  S.refresh.phase, S.refresh.queue, S.refresh.index = "owned", {}, 0
  Walk.MarkProgress()
  if not automatic then
    -- A manual press means "ask for real": remembered no-listing answers are wiped so every
    -- row gets a genuine re-ask instead of being gagged by a minute-old empty result.
    for key in pairs(S.emptyAnswers) do S.emptyAnswers[key] = nil end
  end
  -- Draw what is already known before asking the server anything. Bag contents
  -- need no auction house at all, and every path below can fail -- the auction
  -- house not being open being the ordinary one. Without this, opening the Sell
  -- tab anywhere but at an auctioneer showed an empty list and a line of text,
  -- when the answer to "what could I sell" was sitting in the player's bags.
  Compose.Positions()
  View.render()
  View.status(automatic and GC.L["Checking prices…"] or GC.L["Refreshing listings…"])
  if automatic then
    -- The repeat prices only. Owned lots change through OWNED_AUCTIONS_UPDATED /
    -- AUCTION_CANCELED events regardless, and re-querying them here cost a throttled round
    -- trip plus its wait on every 5-second tick before a single price was asked -- and was
    -- one more phase the walk could wedge in.
    Walk.Begin()
    Walk.ArmWatchdog()
    return
  end
  -- The whole tab in one message, before anything else is asked: if it goes, the listings
  -- query takes the next ready tick (the waiting_owned path below is exactly that).
  S.refresh.bulkWanted, S.refresh.bulkLanded = true, nil
  if GC.Sell.TrySendBulk() then
    S.refresh.phase = "waiting_owned"
    Walk.ArmWatchdog()
    return
  end
  local sent, waiting = Owned.Request()
  if waiting then
    S.refresh.phase = "waiting_owned"
    View.status(GC.L["Waiting for Auction House…"])
  elseif not sent then
    S.refresh.phase = "idle"
    View.status(GC.L["Auction House is not open"])
  end
  Walk.ArmWatchdog()
end
function GC.Sell.Reset()
  Walk.Abandon()
  S.refresh.generation = S.refresh.generation + 1
  S.refresh.phase, S.refresh.queue, S.refresh.index = "idle", {}, 0
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
  S.refresh.priority = {}
  S.refresh.awaitingPriority = nil
  S.refresh.skipped = 0
  S.refresh.waitingNoted = false
  for key in pairs(S.emptyAnswers) do S.emptyAnswers[key] = nil end
  for key in pairs(S.ownedAwaitingKind) do S.ownedAwaitingKind[key] = nil end
  -- Cached ItemLocations are a live session's own bag snapshot; the next visit's first paint
  -- rebuilds whatever it finds (cacheBagLocation), so nothing here is lost, only stopped from
  -- outliving the visit it was pinned to.
  for key in pairs(S.bagLocationCache) do S.bagLocationCache[key] = nil end
  -- Nothing is answered once the auction house has closed: every post that went out and was never
  -- answered -- the late ones and the one on the wire -- drops the price and quantity typed for it
  -- (GC.Sell._SpendPrice). A Confirm nobody pressed sent nothing, and keeps it.
  for _, late in ipairs(GC.Sell._lateAnswers) do GC.Sell._SpendPrice(late.pin) end
  if S.postingPin and S.postingPin.sent then GC.Sell._SpendPrice(S.postingPin) end
  GC.Sell._lateAnswers = {}
  GC.Sell._owedUntil = nil
  -- A new visit starts the selling list again: what was posted from a typed number is POST's again.
  for key in pairs(S.postedThisVisit) do S.postedThisVisit[key] = nil end
  GC.QuoteCache.Clear(S.quotes)
  -- The SESSION cache goes, the persisted mirror STAYS. Reset's only caller is the auction
  -- house closing (UI/SniperFrame.lua), which is not the player asking to forget anything --
  -- it is the live session ending. Wiping the store there defeated the whole point of keeping
  -- one: every visit re-priced every position from a dash, and the tab spent its first half
  -- minute saying "—" about prices it had known thirty seconds earlier (reported in game,
  -- "ЦІНИ 4/17" on a list of seventeen). The store already carries its own age limit
  -- (QUOTE_PERSIST_MAX_AGE, three days) and every row it seeds is drawn with its real age, so
  -- nothing here can pass an old price off as a live one.
  --
  -- Seeding is armed again with it: Quotes.Seed runs once per session, and without
  -- this the next compose would find an empty live cache and no permission to refill it.
  S.quotesSeeded = false
  S.quoteExpiryGeneration = S.quoteExpiryGeneration + 1
  S.walkRepeatToken = S.walkRepeatToken + 1
  S.watchdogToken = S.watchdogToken + 1
  Post.DisarmPost()
  Post.DisarmRepost()
  Post.DisarmRemove()
end
