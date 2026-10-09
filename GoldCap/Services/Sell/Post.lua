-- The Sell tab's post, cancel and removal: what each click checks and pins before the protected
-- call its handler makes (UI/Sell/Dock.lua's onPostClick and onRepostClick -- nothing here makes
-- one), the timeouts that give a row back, the answers that come late, and the auction house's
-- created, error and queued events. The only widget it touches is the clicked row's own button,
-- through the button's methods, and never on the way to a protected call. Moved from
-- UI/SellFrame.lua as it was.
local _, GC = ...

local S, View = GC.SellState, GC.SellView
local Quotes, Bags, Compose, Owned, Walk, Post = GC.SellQuotes, GC.SellBags, GC.SellCompose, GC.SellOwned,
  GC.SellWalk, GC.SellPost
local exact, safeMultiply, overrideKey = GC.SellUtil.exact, GC.SellUtil.safeMultiply, GC.SellUtil.overrideKey
local activeScope, exactRenderEntry, itemName = GC.SellUtil.activeScope, GC.SellUtil.exactRenderEntry,
  GC.SellUtil.itemName

-- The auction's listing duration: 1 = 12h, 2 = 24h, 3 = 48h, matching the `duration` argument
-- the two posting calls in onPostClick (UI/Sell/Dock.lua) take -- see Core/Init.lua's own comment
-- on settings.sniper.postDuration for the same mapping. Read fresh on every post rather than
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
local postTimeoutToken
local repostArmToken = 0
local removeArmToken = 0

local function restorePostRow(row)
  if not row then return end
  row.postStage = nil
  if row.action then
    row.action:Enable(); row.action.helpKey = "Post"; row.action:SetLabel(GC.L["Post"])
    if row.action.SetBusy then row.action:SetBusy(false) end
  end
end

local function restoreRepostRow(row)
  if not row then return end
  row.repostStage, row.repostReady = nil, nil
  if row.action then row.action:Enable(); row.action.helpKey = "Cancel lot"; row.action:SetLabel(GC.L["Cancel lot"]) end
end

local function restoreRemoveRow(row)
  if not row then return end
  row.removeStage = nil
  if row.action then row.action:Enable(); row.action.helpKey = "Remove"; row.action:SetLabel(GC.L["Remove"]) end
end

local function flushDeferredRender()
  if S.deferredRender and not S.postingRow and not S.repostingRow and not S.removingRow then View.render() end
end

function Post.DisarmPost()
  local row = S.postingRow
  S.postingRow, S.postingPin = nil, nil
  postTimeoutToken = (postTimeoutToken or 0) + 1
  restorePostRow(row)
  flushDeferredRender()
  -- "Posting…" and "Click Confirm to post" in the dock were about this post and go with it; an
  -- outcome (Posted, the auction house's refusal) is noted by the caller after this and stays
  -- its few seconds. The dock's POST lets go of its spinner here too, whatever else repaints.
  View.endPostNote(true)
  View.paintQueue()
end

function Post.DisarmRepost()
  local row = S.repostingRow
  S.repostingRow, S.repostPin = nil, nil
  repostArmToken = (repostArmToken or 0) + 1
  restoreRepostRow(row)
  flushDeferredRender()
  View.paintCancel()
end

function Post.DisarmRemove()
  local row = S.removingRow
  S.removingRow, S.removePin = nil, nil
  removeArmToken = (removeArmToken or 0) + 1
  restoreRemoveRow(row)
  flushDeferredRender()
end

-- How long the dock keeps a post's outcome, in seconds: a moment for a post that went up, long
-- enough to read for one that did not.
GC.Sell.POST_NOTE_SECONDS = { posted = 1.5, failed = 10 }

-- Posts we stopped waiting for that the auction house may still answer: the watchdog gave up on
-- one that was SENT, or an AUCTION_HOUSE_SHOW_ERROR -- which names no request, so it can be
-- somebody else's -- freed its row. Each keeps its pin for LATE_ANSWER_SECONDS, so an
-- AUCTION_HOUSE_AUCTION_CREATED that comes after is still credited to it (GC.Sell.OnAuctionCreated):
-- the dock says Posted over "did not answer", the hold is released and its typed price spent. The
-- owned-auctions list writes the durable record, as for any auction on it. While one is open, that
-- item is not posted again (onPostClick holds it, the dock's queue skips it): a second post of a
-- stack the first may still be taking is the double post.
--
-- The window is 60 s. The watchdog is 8 s; the slowest round trip this tab already waits for
-- is a cancel, given 30 s (REPOST_CANCEL_TIMEOUT_SECONDS) after one was seen to take more than
-- ten; a post the client queued behind the throttle goes out only when a slot frees. Twice the
-- cancel's budget covers those without keeping an item from posting for long when its post
-- really was lost -- and a post after the window needs a fresh quote anyway (45 s).
--
-- It used to be one slot, kept for 8 s and only for a timed-out CONFIRM: a first-click post the
-- watchdog gave up on was thrown away when it went up late -- never recorded against its batch,
-- the typed price never spent, so the next stack of the item quietly inherited it.
GC.Sell.LATE_ANSWER_SECONDS = 60
GC.Sell._lateAnswers = {}

-- The late answers still in their window, oldest first; the rest are forgotten here. A window
-- that closes unanswered keeps its typed price, like a refused post: it stays on the row for the
-- retry (GC.Sell._SpendPrice).
function GC.Sell._LiveLate()
  local live, now = {}, time()
  for _, late in ipairs(GC.Sell._lateAnswers) do
    if now - late.at <= GC.Sell.LATE_ANSWER_SECONDS then live[#live + 1] = late end
  end
  GC.Sell._lateAnswers = live
  return live
end

-- A late answer ended by a guess -- a creation the client names nothing about, or a shared error
-- the order rule gives it -- may still be owed its real answer until its minute is over: the guess
-- can have been somebody else's (Blizzard's own Sell pane, another request's "busy"). Until then
-- a post that goes out is not certain of the next creation either -- it can be that late post's --
-- so `clean` waits for it (review sell-fix4 M1). `GC.Sell._owedUntil`: when the last such minute
-- ends.
function GC.Sell._OweAnswer(late)
  local untilAt = late.at + GC.Sell.LATE_ANSWER_SECONDS
  if untilAt > (GC.Sell._owedUntil or 0) then GC.Sell._owedUntil = untilAt end
end

-- Whether a post going out now is certain to be what the next creation answers: no late answer
-- open, and none owed (GC.Sell._OweAnswer).
function GC.Sell._Certain()
  return #GC.Sell._LiveLate() == 0 and time() > (GC.Sell._owedUntil or 0)
end

-- The one rule for a typed price (the price column's own choice, priceOverrides), and for a
-- typed quantity (quantityOverrides) with it: each was chosen for ONE listing, against a book
-- that will move, and five of ten is a choice about this post, not about the next five. The
-- post that carried them spends them when a creation is credited to that post, and they are
-- dropped when the auction house closes over a post that went out and was never answered --
-- carried into the next visit after an outcome nobody saw, they would shape that listing with
-- numbers chosen for a market that is gone. Only then: a post whose minute ran out unanswered
-- keeps them, on the row, for the retry, as a refused one does. Dropping them there, behind the
-- row, left the row showing a price while the next Post sent GoldCap's (review sell-fix4 I1);
-- at a close the next visit composes before anything can be pressed. Only what that post
-- carried: a number the player has typed since is their next choice and stays. Nothing ever
-- puts a spent one back.
function GC.Sell._SpendPrice(pin)
  local key = type(pin) == "table" and pin.positionKey or nil
  if type(key) == "string" and pin.override ~= nil and pin.override == S.priceOverrides[key] then
    S.priceOverrides[key] = nil
  end
  if type(key) == "string" and pin.overrideQuantity ~= nil and pin.overrideQuantity == S.quantityOverrides[key] then
    S.quantityOverrides[key] = nil
  end
end

function GC.Sell._LateFor(positionKey, scopeKey)
  for _, late in ipairs(GC.Sell._LiveLate()) do
    if late.pin.positionKey == positionKey and late.pin.scopeKey == scopeKey then return late end
  end
  return nil
end

-- The dock's queue leaves out an item whose last post may still be answered, and counts it held
-- back with the reason: its head is what the dock's POST posts, and held there it would stand
-- in front of every other item for the whole window.
function GC.Sell._HoldLateInQueue()
  if #GC.Sell._LiveLate() == 0 then return end
  local kept = {}
  for _, entry in ipairs(S.queueEntries) do
    if GC.Sell._LateFor(entry.positionKey, entry.scopeKey) then
      S.queueSkipped[#S.queueSkipped + 1] = { positionKey = entry.positionKey, itemID = entry.itemID,
        itemName = entry.itemName, reason = "awaiting_answer" }
    else
      kept[#kept + 1] = entry
    end
  end
  S.queueEntries = kept
end

-- Called while `pin` is still the post on the wire, before it is let go. Only a post that was
-- sent: a Confirm nobody pressed asked the auction house nothing.
function GC.Sell._AwaitLate(pin)
  if not (type(pin) == "table" and pin.sent) then return end
  local live = GC.Sell._LiveLate()
  live[#live + 1] = { pin = pin, at = time() }
  GC.Sell._HoldLateInQueue()
  View.paintQueue()
end

local function schedulePostTimeout(row)
  if not (C_Timer and C_Timer.After) then return end
  postTimeoutToken = (postTimeoutToken or 0) + 1
  local token = postTimeoutToken
  C_Timer.After(POST_TIMEOUT_SECONDS, function()
    local stage = row.postStage
    if token == postTimeoutToken and S.postingRow == row
        and (stage == "posting" or stage == "confirm" or stage == "confirming") then
      -- A post that was sent can still go up after this; keep listening for it.
      local sent = S.postingPin and S.postingPin.sent
      GC.Sell._AwaitLate(S.postingPin)
      Post.DisarmPost()
      -- Said by what is actually true. A Confirm nobody pressed asked the auction house nothing:
      -- the player's confirmation lapsed. A post that went out is still listened for and the
      -- item held meanwhile, so "try again" there would be contradicted by the very next press
      -- (review I3). Only a post that never left -- its call raised -- is free to try again.
      View.notePost(stage == "confirm" and GC.L["Post confirmation expired"]
        or sent and GC.L["No answer yet -- listening for a minute"]
        or GC.L["The auction house did not answer -- try again"], "red", GC.Sell.POST_NOTE_SECONDS.failed)
    end
  end)
end

-- Everything a Post click does before the protected call: the guards, the plan, the pin, the
-- row's stage and the timeout that recovers the row. Returns the call for onPostClick to make
-- -- { confirm = true, pin = pin } or { pin = S.postingPin } -- or nil when the click ends here,
-- having already said why. On the way to a returned call it only reads and writes plain fields:
-- the button, the dock and the spinner wait for the handler, after the call.
function Post.PreparePost(row)
  -- A post already on its way answers every further press with nothing. Its buttons are
  -- disabled, but the keybinding reaches here through onQueueClick whatever they look like --
  -- and the stale-quote branch just below let go of a post in flight the moment its quote
  -- passed SELL_QUOTE_ACTION_AGE, handing the row back as Post for the next press to post the
  -- same stack again.
  if S.postingRow == row and (row.postStage == "posting" or row.postStage == "confirming") then return end
  -- With another post out, that post's answer is the one to wait for -- said at once, before any
  -- hold or any search for a fresh price, and leaving the dock saying what that post is doing.
  if S.postingRow and S.postingRow ~= row then
    View.status(GC.L["Finish the pending post first"])
    return
  end
  -- Nor is a new post of an item whose last post the auction house may still be answering (see
  -- GC.Sell._lateAnswers): the stack it would send is the one that post may be taking.
  if row.postStage ~= "confirm" and row.position
      and GC.Sell._LateFor(row.position.positionKey, row.position.scopeKey) then
    View.notePost(GC.L["Last post may still go up -- wait a minute"], "fg",
      GC.Sell.POST_NOTE_SECONDS.failed)
    return
  end
  local position = row.position
  local quote = Quotes.Fresh(position)
  if not quote then
    if S.postingRow == row then Post.DisarmPost() end
    -- Same silent first click as Repost had: without this the button looks
    -- broken. The status line alone is not enough -- it sits in the Sniper's
    -- toolbar, a window's width from the button that was just pressed -- so the
    -- button says it too. The next render restores the label once the price
    -- lands, which is one query away now rather than a whole pass.
    if row.action then row.action:SetLabel(GC.L["Pricing…"]) end
    View.status(GC.L["Fetching a fresh price for this item — press Post again in a moment"])
    Walk.RefreshFor(position); return
  end
  if S.postingRow == row and row.postStage ~= "confirm" then return end
  if row.postStage == "confirm" then
    local pin = S.postingPin
    local scope, scopeKey = activeScope(position)
    local bagState = pin and Bags.ClickSafe(position, pin.isCommodity and nil or pin.quantity) or nil
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
      Post.DisarmPost()
      if not sameQuote then Walk.RefreshFor(position)
      else View.status(GC.L["Post confirmation expired"]) end
      return
    end
    -- Plain field write only, before the call: row.postStage = "confirming" is what the
    -- re-entrancy guard at the top of this function reads. The busy look -- Disable() (runs
    -- GoldCap's own OnDisable script), SetLabel() (GoldCap Lua, not a widget call) and SetBusy()
    -- (lazily creates a Blizzard SpinnerTemplate frame -- mixin OnLoad the first time, and
    -- SpinnerMixin's OnShow every time after) -- moves after the call, beside _NotePost (final
    -- review C3): all three can run Blizzard or GoldCap Lua ahead of the protected call in
    -- onPostClick (UI/Sell/Dock.lua), which is exactly what WoW: Forever's taint engine blocks on.
    row.postStage = "confirming"
    -- The confirming click gets its own full window. Sharing the first click's clock meant the
    -- time a player spent reading the confirmation came out of the time the server had to
    -- answer it -- see schedulePostTimeout. Armed BEFORE the call for the same reason the first
    -- click arms it before posting: a call that raises aborts onPostClick (UI/Sell/Dock.lua), and
    -- the timeout is what recovers the row if that happens. C_Timer.After only registers a
    -- callback -- it does not read anything GoldCap-owned synchronously, so arming here is not a
    -- taint risk.
    schedulePostTimeout(row)
    return { confirm = true, pin = pin }
  end
  local bagState = Bags.ClickSafe(position)
  -- Passed explicitly as well as through the position's decoration (Compose.Positions):
  -- BuildPostPlan's own floor and
  -- queue raises can only ever raise, and a raise on top of a chosen price would silently undo
  -- the choice. The override branch there skips both.
  local chosenKey = overrideKey(position)
  local chosenQty = chosenKey and S.quantityOverrides[chosenKey] or nil
  local plan, reason = GC.SellPositions.BuildPostPlan(position, bagState, { unit = quote.unit, fresh = true },
    { overrideUnit = chosenKey and S.priceOverrides[chosenKey] or nil, overrideQuantity = chosenQty })
  if not plan then
    View.status(reason == "ambiguous_variant" and GC.L["No exact bag variant"] or GC.L["Cannot post this position"])
    return
  end
  local scope, scopeKey = activeScope(position)
  if not scope or type(row.renderEntryID) ~= "string" or row.renderEntryID == ""
      or plan.positionKey ~= position.positionKey or plan.scopeKey ~= position.scopeKey
      or plan.scopeKey ~= scopeKey or plan.itemID ~= position.itemID
      or not exact(plan.quantity) or plan.quantity <= 0 or not exact(plan.unitPrice) or plan.unitPrice <= 0 then
    View.status(GC.L["Cannot post this position"])
    return
  end
  local info = Quotes.driver.keyInfo(plan.itemID)
  if not info then View.status(GC.L["No exact auction key"]); return end
  if (info.isCommodity and not (C_AuctionHouse and C_AuctionHouse.PostCommodity))
      or (not info.isCommodity and not (C_AuctionHouse and C_AuctionHouse.PostItem)) then
    View.status(GC.L["Posting unavailable"])
    return
  end
  local buyout = not info.isCommodity and safeMultiply(plan.unitPrice, plan.quantity) or nil
  if not info.isCommodity and not buyout then View.status(GC.L["Cannot post this position"]); return end
  local commodityTotal = info.isCommodity and safeMultiply(plan.unitPrice, plan.quantity) or nil
  if info.isCommodity and (not commodityTotal or not exact(bagState.exactQty) or bagState.exactQty < plan.quantity) then
    View.status(GC.L["No exact bag stack"])
    return
  end
  if not bagState.bag or not bagState.slot then
    View.status(GC.L["No exact bag stack"])
    return
  end
  if not info.isCommodity then
    bagState = Bags.ClickSafe(position, plan.quantity)
    if not bagState.bag or not bagState.slot or not bagState.stackQty or bagState.stackQty < plan.quantity then
      View.status(GC.L["No exact bag stack"])
      return
    end
  end
  -- Never build the bag/slot location fresh here: Bags.ResolveLocation only reuses the one
  -- cacheBagLocation already built at the last paint, re-proven by a plain C API just above (and,
  -- for a commodity, again inside Bags.ResolveLocation itself) -- see the comment above
  -- Bags.LiveState in Bags.lua for why building it in this click is exactly what WoW: Forever's
  -- taint engine
  -- blocks ahead of the protected call in onPostClick (UI/Sell/Dock.lua).
  local location = Bags.ResolveLocation(position)
  if not location then View.status(GC.L["No exact bag stack"]); return end
  S.postingRow = row
  -- Pinned once, here, rather than re-read at Confirm time: everything else about a post is
  -- pinned the same way (unitPrice, quantity, ...) precisely so the two clicks of a two-click
  -- post cannot disagree about what they are doing. A duration changed in the settings panel
  -- between the two clicks must not let a post start at one duration and confirm at another.
  local duration = postDuration()
  S.postingPin = { scopeKey = plan.scopeKey, positionKey = plan.positionKey, itemID = plan.itemID,
    variantKey = bagState.positionKey, quantity = plan.quantity, bag = bagState.bag, slot = bagState.slot,
    quoteAt = quote.at, quoteUnit = quote.unit, quote = quote, location = location, isCommodity = info.isCommodity,
    unitPrice = plan.unitPrice, buyout = buyout, total = commodityTotal or buyout, row = row, action = row.action,
    position = position, renderEntryID = row.renderEntryID, character = scope.char, region = scope.region,
    duration = duration, override = chosenKey and S.priceOverrides[chosenKey] or nil, overrideQuantity = chosenQty }
  -- Plain field write only, before the call: row.postStage = "posting" is what the re-entrancy
  -- guard at the top of this function reads. The busy look -- Disable() (runs GoldCap's own
  -- OnDisable script), SetLabel() (GoldCap Lua, not a widget call) and SetBusy() (lazily creates
  -- a Blizzard SpinnerTemplate frame -- mixin OnLoad the first time, and SpinnerMixin's OnShow
  -- every time after) -- moves after the call, beside _NotePost (final review C3): all three can
  -- run Blizzard or GoldCap Lua ahead of the protected call in onPostClick (UI/Sell/Dock.lua),
  -- which is exactly what WoW: Forever's taint engine blocks on. The owner could not tell a
  -- pressed Post from a dead one when it only dimmed; it still says so, just a beat later, once
  -- the call is behind it.
  row.postStage = "posting"
  -- Armed BEFORE the call: a call that raises (a client "bad argument") aborts onPostClick
  -- (UI/Sell/Dock.lua), and armed after it the row and the dock stayed on "Posting…" until the
  -- auction house closed, with every other Post answering "Finish the pending post first" (review
  -- I2). An answer that lands inside the call lets this go through Post.DisarmPost's token, like any
  -- other. C_Timer.After only registers a callback -- it does not read anything GoldCap-owned
  -- synchronously, so arming here is not a taint risk the way the busy look in onPostClick is.
  schedulePostTimeout(row)
  return { pin = S.postingPin }
end

-- A post the auction house took without asking for a Confirm, or a Confirm it took: on its way now
-- (Blizzard's own sell frame reads the answer the same way), and anything that gives up on it from
-- here listens for it late. `clean`: no late answer open or owed as it went out, so the next
-- creation can only be its own (GC.Sell.OnAuctionCreated books it then, and only then).
function Post.Sent(pin)
  pin.sent, pin.clean = true, GC.Sell._Certain()
end

-- Everything a Cancel lot click does before the protected call. A first click arms (the deposit
-- warning, REPOST_ARM_SECONDS before a confirm counts, the timeout) and returns nil; the
-- confirming click checks the pin against a fresh read of the player's own auctions, marks the
-- row "cancelling" and returns the pin and its scope for onRepostClick to cancel. Plain reads
-- and writes only on the way there.
function Post.PrepareCancel(row, auctionID)
  local position = row.position
  if S.repostingRow and S.repostingRow ~= row then
    Post.DisarmRepost()
    View.status(GC.L["Previous repost selection cleared"])
    return
  end
  -- A cancel already on the wire is not a click target. Only nil (nothing armed) and "armed"
  -- are: a second click while the stage was "cancelling" fell straight past the armed branch
  -- below into the arm branch at the bottom and re-armed the very lot whose cancel the server
  -- was still working on.
  if row.repostStage ~= nil and row.repostStage ~= "armed" then
    View.status(GC.L["Cancelling lot…"])
    return
  end
  local quote = Quotes.Fresh(position)
  if not quote then
    if S.repostingRow == row then Post.DisarmRepost() end
    -- Previously this refreshed the quote and returned in silence, so a first click looked like
    -- a dead button. Say what is happening; the click that follows is the one that arms.
    View.status(GC.L["Fetching a fresh price for this lot — press Repost again in a moment"])
    Walk.RefreshFor(position); return
  end
  if row.repostStage == "armed" then
    if not row.repostReady then return end
    local pin = S.repostPin
    if not exactRenderEntry(row, pin) then
      Post.DisarmRepost()
      View.status(GC.L["Repost confirmation expired"])
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
      Post.DisarmRepost()
      View.status(GC.L["Repost confirmation expired"])
      return
    end
    -- A fresh, plain read of the server's own owned-auctions list -- auctionID, quantity, unit
    -- price -- and nothing else. Bag stock plays no part in whether a lot can be cancelled
    -- (final review C2), so this click no longer calls Compose.Positions()/Bags.Scan() at all:
    -- that used to run classifyBagItem -> C_AuctionHouse.IsSellItemValid on a bag location built
    -- fresh, right here, from the Blizzard mixin method cacheBagLocation's own comment (in Bags.lua,
    -- above Bags.LiveState) names -- for every unbound non-commodity bag stack, ahead of the protected
    -- CancelAuction in onRepostClick (UI/Sell/Dock.lua). Owned.Classify's own
    -- GetItemKeyInfo call is a plain C API, not a mixin method.
    local freshLots = GC.SellPositions.NormalizeOwnedLots(
      Owned.Classify(C_AuctionHouse.GetOwnedAuctions() or {}), time())
    S.ownedLots = freshLots
    local current
    for _, candidate in ipairs(freshLots) do
      if candidate.auctionID == pin.auctionID and candidate.positionKey == pin.positionKey
          and candidate.itemID == pin.itemID and candidate.quantity == pin.quantity
          and candidate.unitPrice == pin.listedUnit then
        current = candidate
        break
      end
    end
    if not exactRenderEntry(row, pin) or not scope or scopeKey ~= pin.scopeKey
        or pin.position ~= position or pin.positionKey ~= position.positionKey
        or pin.scopeKey ~= position.scopeKey or pin.itemID ~= position.itemID
        or not current
        or quote ~= pin.quote or quote.at ~= pin.quoteAt or quote.unit ~= pin.quoteUnit
        or not (C_AuctionHouse and C_AuctionHouse.CancelAuction) then
      Post.DisarmRepost()
      View.status(GC.L["Repost confirmation expired"])
      return
    end
    -- Plain field write only, before the call: row.repostStage = "cancelling" is what the
    -- re-entrancy guard at the top of this function reads. row.action:Disable() -- GoldCap Lua,
    -- runs its own OnDisable script -- moves after the call, with the recompose in
    -- Post.Cancelling (final review C3's "related" note on this same shape).
    row.repostStage = "cancelling"
    return pin, scope
  end
  local plan = GC.SellPositions.BuildRepostPlan(position, auctionID, { unit = quote.unit, fresh = true })
  local scope, scopeKey = activeScope(position)
  if not plan or not scope or type(row.renderEntryID) ~= "string" or row.renderEntryID == ""
      or plan.positionKey ~= position.positionKey or plan.scopeKey ~= position.scopeKey
      or plan.scopeKey ~= scopeKey or plan.itemID ~= position.itemID
      or not exact(plan.auctionID) or plan.auctionID <= 0 or plan.auctionID ~= auctionID
      or not exact(plan.quantity) or plan.quantity <= 0
      or not exact(plan.unitPrice) or plan.unitPrice <= 0 then
    View.status(GC.L["Cannot repost this lot"])
    return
  end
  local lot
  for _, candidate in ipairs(position.ownedLots or {}) do if candidate.auctionID == plan.auctionID then lot = candidate break end end
  if not lot or lot.quantity ~= plan.quantity or not exact(lot.unitPrice) or lot.unitPrice <= 0 then
    View.status(GC.L["Cannot repost this lot"])
    return
  end
  S.repostingRow, S.repostPin = row, { scopeKey = plan.scopeKey, positionKey = plan.positionKey, auctionID = plan.auctionID,
    itemID = plan.itemID, quantity = plan.quantity, listedUnit = lot.unitPrice,
    quoteAt = quote.at, quoteUnit = quote.unit, quote = quote, row = row, action = row.action,
    position = position, renderEntryID = row.renderEntryID, character = scope.char, region = scope.region }
  row.repostStage, row.repostReady = "armed", false
  row.action.helpKey = "Cancel lot?"; row.action:Disable(); row.action:SetLabel(GC.L["Cancel lot?"])
  View.status(GC.L["Cancel this lot and lose its deposit — click again to confirm"])
  repostArmToken = repostArmToken + 1
  local token = repostArmToken
  if C_Timer and C_Timer.After then
    C_Timer.After(REPOST_ARM_SECONDS, function()
      if token == repostArmToken and S.repostingRow == row and row.repostStage == "armed" then
        row.repostReady = true; row.action:Enable()
        -- The cancel control mirrors this arm (see paintCancelButton); without this repaint it
        -- would stay disabled after the delay even though the row's own button just enabled.
        View.paintCancel()
      end
    end)
    C_Timer.After(REPOST_TIMEOUT_SECONDS, function()
      if token == repostArmToken and S.repostingRow == row and row.repostStage == "armed" then
        Post.DisarmRepost()
        View.status(GC.L["Repost confirmation expired"])
      end
    end)
  end
end

-- What a sent cancel owes the tab, run by onRepostClick straight after the call, once the
-- button is disabled.
function Post.Cancelling(row, pin, scope)
  -- Full recompose and its paints, now that the protected call is behind us: rebuilds
  -- `positions` from the fresh ownedLots already set above (and a fresh bag scan, safe here --
  -- no protected call follows in this click), and repaints the deck switch, queue and cancel
  -- buttons this click used to paint through Compose.Positions(true) before the call.
  Compose.Positions()
  if GC.Data and GC.Data.MarkOwnedLotCancelled and scope then
    GC.Data.MarkOwnedLotCancelled(GC.db, pin.auctionID, scope, time())
  end
  View.status(GC.L["Cancelling lot…"])
  if C_Timer and C_Timer.After then
    local token = repostArmToken
    C_Timer.After(REPOST_CANCEL_TIMEOUT_SECONDS, function()
      if token == repostArmToken and S.repostingRow == row and row.repostStage == "cancelling" then
        Post.DisarmRepost()
        View.status(GC.L["Cancel timed out"])
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
function Post.Remove(row)
  if S.removingRow and S.removingRow ~= row then
    Post.DisarmRemove()
    View.status(GC.L["Previous removal selection cleared"])
    return
  end
  if row.removeStage == "armed" then
    local pin = S.removePin
    if not exactRenderEntry(row, pin) then
      Post.DisarmRemove()
      View.status(GC.L["Removal confirmation expired"])
      return
    end
    local removed = 0
    for _, id in ipairs(pin.ids) do
      if GC.Acquisitions.RemoveManual(id) then removed = removed + 1 end
    end
    Post.DisarmRemove()
    View.status(removed > 0
      and (removed > 1 and (GC.L["Removed %d entries"]):format(removed) or GC.L["Removed"])
      or GC.L["Nothing to remove"])
    GC.Sell.Refresh()
    return
  end
  if S.postingRow or S.repostingRow then
    View.status(GC.L["Finish the pending post or repost first"])
    return
  end
  local ids = row.batch and row.batch.ids
  if type(ids) ~= "table" or #ids == 0 or type(row.renderEntryID) ~= "string" or row.renderEntryID == "" then
    View.status(GC.L["Cannot remove this entry"])
    return
  end
  S.removingRow, S.removePin = row, { ids = ids, row = row, action = row.action,
    position = row.position, renderEntryID = row.renderEntryID }
  row.removeStage = "armed"
  row.action.helpKey = "Remove?"; row.action:SetLabel(GC.L["Remove?"])
  View.status(#ids > 1
    and GC.L["Removes every entered-by-hand purchase in this run -- click again to confirm"]
    or GC.L["Removes this entered-by-hand purchase -- click again to confirm"])
  removeArmToken = removeArmToken + 1
  local token = removeArmToken
  if C_Timer and C_Timer.After then
    C_Timer.After(REMOVE_TIMEOUT_SECONDS, function()
      if token == removeArmToken and S.removingRow == row and row.removeStage == "armed" then
        Post.DisarmRemove()
        View.status(GC.L["Removal confirmation expired"])
      end
    end)
  end
end

-- What a completed post owes the rest of the addon, from the pin alone -- written only for a post
-- that is CERTAINLY the one the auction house answered (GC.Sell.OnAuctionCreated).
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

-- "Posted · Eternium Ore ×246" -- which post went up, since the dock's label beside it has
-- already moved on to the next item.
function GC.Sell._PostedText(pin)
  -- The position's own name: a caged pet's is the pet's, where the item's is "Pet Cage" for every
  -- one of them (final review M4).
  local name = type(pin.position) == "table" and pin.position.itemName or itemName(pin.itemID)
  return GC.L["Posted"] .. " · " .. ("%s ×%d"):format(name, pin.quantity or 0)
end

-- The ItemKey an AUCTION_HOUSE_AUCTION_CREATED is about, when the client can say: the event
-- carries the new auction's id, and C_AuctionHouse.GetAuctionInfoByID answers with it. That
-- answer is Nilable, and nothing in Blizzard's own UI looks up an auction it has just created,
-- so nil is to be expected in game. Also returns what the client said, for the trace.
function GC.Sell._CreatedKey(auctionID)
  if type(auctionID) ~= "number" or not (C_AuctionHouse and C_AuctionHouse.GetAuctionInfoByID) then return nil, nil end
  local ok, info = pcall(C_AuctionHouse.GetAuctionInfoByID, auctionID)
  if not ok then return nil, nil end
  local key = type(info) == "table" and info.itemKey or nil
  return type(key) == "table" and type(key.itemID) == "number" and key or nil, info
end

-- Whether a pin's variant is the one an ItemKey names: item level, suffix and pet species, which
-- two variants of one item -- two positions -- differ in. A commodity has one variant.
function GC.Sell._SameVariant(pin, key)
  local level, suffix, pet = tostring(pin.positionKey):match("^item:%d+:(%d+):(%d+):(%d+)$")
  if not level then return true end
  return tonumber(level) == (key.itemLevel or 0) and tonumber(suffix) == (key.itemSuffix or 0)
    and tonumber(pet) == (key.battlePetSpeciesID or 0)
end

-- Which of our SENT posts a creation belongs to, or nil for one that is none of ours. The
-- candidates are the late answers (sent, and older) and `wire`, the post still on the wire --
-- never a post waiting for its Confirm, which has sent nothing. Answers come in the order the
-- posts went out, so the oldest candidate owns it; where the client names the item, only posts
-- of that item are candidates, and between two of them the named variant decides. A late
-- answer that is chosen is taken out of the window: one creation is one post -- and the post on
-- the wire, if any, is no longer certain of the next creation (`clean`).
--
-- It used to go to the post on the wire whenever the client named nothing: that freed a post
-- still out (the next press sent its stack again), booked it as posted when it was refused, and
-- took a pending Confirm for an answer (review I1).
--
-- `info` is what the client said besides the key, GetAuctionInfoByID's AuctionInfo: a quantity
-- it names must be the post's; for gear, a buyout it names must be the post's total -- two posts
-- of one item are told apart by it.
function GC.Sell._CreationOwner(named, wire, info)
  local live = GC.Sell._LiveLate()
  local function fits(pin)
    if named and pin.itemID ~= named.itemID then return false end
    if type(info) == "table" then
      if type(info.quantity) == "number" and type(pin.quantity) == "number" and info.quantity ~= pin.quantity then
        return false
      end
      if not pin.isCommodity and type(info.buyoutAmount) == "number" and type(pin.buyout) == "number"
          and info.buyoutAmount ~= pin.buyout then
        return false
      end
    end
    return true
  end
  local candidates = {}
  for index, late in ipairs(live) do
    if fits(late.pin) then candidates[#candidates + 1] = { pin = late.pin, index = index } end
  end
  if wire and fits(wire) then candidates[#candidates + 1] = { pin = wire } end
  local chosen = candidates[1]
  if named and #candidates > 1 then
    for _, candidate in ipairs(candidates) do
      if GC.Sell._SameVariant(candidate.pin, named) then chosen = candidate break end
    end
  end
  if chosen and chosen.index then
    local late = table.remove(live, chosen.index)
    if wire then wire.clean = false end
    -- Unnamed, it is the order rule's guess: the real answer may still come (_OweAnswer).
    if not named then GC.Sell._OweAnswer(late) end
  end
  return chosen and chosen.pin or nil
end

-- Refresh talks in the window's toolbar; off the tab the list is only composed again, and Show
-- refreshes it when the tab comes back. The owned list is asked for either way -- off the tab a
-- query alone, no walk -- so an auction credited there is on record (OnOwnedAuctions) before the
-- player can close the auction house from Deals or BUY (review sell-fix4 M2). Not while a post of
-- ours is on the wire: a "busy" the query drew would be read as that post's; its own creation
-- asks next.
function GC.Sell._RefreshAfterPost()
  if View.attached() and not View.isShown() then
    Compose.Positions()
    if not S.postingRow then Owned.Request() end
  else
    GC.Sell.Refresh()
  end
end

--
-- What it writes down depends on how sure it is. The owned-auctions list the refresh asks for
-- next is the durable record for every auction on it, ours or not (OnOwnedAuctions ->
-- ObserveOwnedPosition, with the auction's own key and price). A creation adds a booking of its
-- own only when it is CERTAINLY the post on the wire's -- no late answer open when that post went
-- out or taken since (`clean`) -- so a post the player closes the auction house straight after is
-- still on record. Everything the order rule decides while a late answer is open is a guess, and
-- a guess only moves the screen: the Posted line, the hold released, the typed price spent. It
-- used to be booked and then settled against the owned list -- corrected, restored, replayed --
-- to reach what that list writes seconds later anyway; every round found a new edge in it.
function GC.Sell.OnAuctionCreated(auctionID)
  local named, info = GC.Sell._CreatedKey(auctionID)
  -- What the client said, for the owner to read with /gc board and /gc sell: whether
  -- GetAuctionInfoByID names a just-created auction at all decides how often the order rule
  -- in _CreationOwner is the one doing the work.
  local said = type(info) ~= "table" and "nil" or type(info.itemKey) ~= "table" and "no itemKey"
    or table.concat({ tostring(info.itemKey.itemID), info.itemKey.itemLevel or 0, info.itemKey.itemSuffix or 0,
      info.itemKey.battlePetSpeciesID or 0 }, ":")
  GC.Sell._createdSeen = ("sell: created %s -> %s"):format(tostring(auctionID), said)
  if GC.Util and GC.Util.Trace then GC.Util.Trace(GC.Sell._createdSeen) end
  local pin, row = S.postingPin, S.postingRow
  -- Only a post that was SENT: a creation is a server answer, never the answer to a post call
  -- that raised and sent nothing (review NM1).
  local wire = pin and pin.sent and row and (row.postStage == "posting" or row.postStage == "confirming")
    and pin or nil
  local owner = GC.Sell._CreationOwner(named, wire, info)
  if not owner then return end
  GC.Sell._SpendPrice(owner)
  if owner ~= wire then
    -- A post we stopped waiting for, going up late (GC.Sell._lateAnswers): the dock said the
    -- auction house had not answered, or named an error that was not this post's. It did answer,
    -- late -- say that instead, and let the item post again. The post on the wire, if any, stays
    -- armed for its own answer.
    View.notePost(GC.Sell._PostedText(owner), "green", GC.Sell.POST_NOTE_SECONDS.posted)
    GC.Sell._RefreshAfterPost()
    return
  end
  if pin.clean and exactRenderEntry(row, pin) and (row.postStage == "posting" or row.postStage == "confirming")
      and pin.positionKey == row.position.positionKey and pin.scopeKey == row.position.scopeKey
      and pin.itemID == row.position.itemID and postPinSound(pin) then
    recordPostedPin(pin)
  end
  Post.DisarmPost()
  -- Said for a moment, then the list moves on as it always has: the stack leaves the bags, the
  -- row goes or shrinks, and the dock's POST names the next item.
  View.notePost(GC.Sell._PostedText(pin), "green", GC.Sell.POST_NOTE_SECONDS.posted)
  GC.Sell._RefreshAfterPost()
end

-- AUCTION_HOUSE_POST_ERROR carries nothing. It answers a post that needed confirming -- the
-- auction house's warning before a maintenance-window update -- and the default UI shows
-- AUCTION_POSTING_ERROR_TEXT for it ("Items can't be posted right now.|n|nThe auction house is
-- about to undergo a major update."), so that is what the dock says, on one line. Blizzard's own
-- Sell pane raises it too: with no post of ours out, it keeps the old generic line.
function GC.Sell.OnPostError()
  local ours = S.postingRow ~= nil
  Post.DisarmPost()
  Post.DisarmRepost()
  if ours then
    View.notePost(GC.Util and GC.Util.ClientLine and GC.Util.ClientLine(_G.AUCTION_POSTING_ERROR_TEXT)
      or GC.L["Posting failed"], "red", GC.Sell.POST_NOTE_SECONDS.failed)
  else
    View.status(GC.L["Posting failed"])
  end
  GC.Sell._RefreshAfterPost()
end

-- AUCTION_HOUSE_SHOW_ERROR, the auction house's error channel (Core/Init.lua routes it here as
-- well as to the Sniper). A refused post -- no gold for the deposit, an item the auction house
-- will not take, "Internal auction error." -- is refused here and nowhere else, and this used to
-- reach the Sniper only: the row sat disabled until the watchdog called the refusal a timeout.
-- The event names no request, so it is read as the post's answer only while a post of ours is on
-- the wire -- the same one-slot correlation OnAuctionCreated makes -- and in the client's own
-- words where it has them (GC.Util.AuctionHouseErrorText).
--
-- The code says whose it can be (AuctionHouseUtil.GetErrorText's own table, by name): a bid or a
-- purchase code is not the post's answer at all -- the post stays out; a code only a post can
-- raise is the post's refusal, whole -- nothing listened for, nothing held, press again at once;
-- a code a post shares with other requests -- "The Auction House is busy." (IsBusy) is one -- is
-- the post's when nothing else of ours is out, so busy can be pressed again at once, and
-- otherwise may be somebody else's, so the post is let go of but listened for (review I2: every
-- refusal used to hold the item for a minute).
GC.Sell.ERROR_CODES = {
  bid = { "HigherBid", "BidIncrement", "BidOwn", "MinBid", "DoubleBid", "ItemHasQuote" },
  post = { "NotEnoughItems", "RepairItem", "UsedCharges", "QuestItem", "BoundItem", "ConjuredItem",
    "LimitedDurationItem", "IsBag", "EquippedBag", "WrappedItem", "LootItem" },
}

function GC.Sell._ErrorKind(code)
  local enum = Enum and Enum.AuctionHouseError
  if type(enum) == "table" then
    for kind, names in pairs(GC.Sell.ERROR_CODES) do
      for _, name in ipairs(names) do
        if enum[name] ~= nil and enum[name] == code then return kind end
      end
    end
  end
  return "shared"
end

-- Whether a request of ours other than the post is out and could be what an error answers:
-- this tab's own search or cancel, a purchase (either window's), a keys batch. (A late post still
-- open is not asked here: OnAuctionHouseError's order rule has already answered that case.)
function GC.Sell._OtherRequestOut()
  if S.refresh.pending then return true end
  -- This tab's own owned-auctions query: every Posted sends one.
  if S.refresh.phase == "owned" then return true end
  -- A Deals page or a Sniper search still in flight. Showing this tab aborts the Sniper's pass at
  -- once, so it no longer reads as paging (GC.Sniper.IsBusy) -- but what it sent just before is
  -- still out and can still be answered, "busy" included (review NM-C, NM-F).
  if GC.Sniper and GC.Sniper.RequestOut and GC.Sniper.RequestOut() then return true end
  if GC.Sniper and GC.Sniper.IsBusy and GC.Sniper.IsBusy() then return true end
  if S.repostingRow and S.repostingRow.repostStage == "cancelling" then return true end
  if GC.PurchaseSlot and GC.PurchaseSlot.IsBusy and GC.PurchaseSlot.IsBusy() then return true end
  -- A purchase either window confirmed is out until it is answered, which can be after its claim
  -- has gone stale and IsBusy has stopped saying so (GC.PurchaseSlot.ConfirmOwed).
  if GC.PurchaseSlot and GC.PurchaseSlot.ConfirmOwed and GC.PurchaseSlot.ConfirmOwed() then return true end
  -- Final money review M2: and one either window stopped waiting on -- BUY's "unknown", the
  -- Sniper's released confirm -- which can still answer for as long as its record is kept.
  if GC.Buy and GC.Buy.HasStranded and GC.Buy.HasStranded() then return true end
  if GC.Sniper and GC.Sniper.HasStrandedConfirmed and GC.Sniper.HasStrandedConfirmed() then return true end
  if GC.Sniper and GC.Sniper._KeysOutstanding and GC.Sniper._KeysOutstanding() then return true end
  return false
end

function GC.Sell.OnAuctionHouseError(errorCode)
  local row = S.postingRow
  if not (row and (row.postStage == "posting" or row.postStage == "confirming")) then return end
  local kind = GC.Sell._ErrorKind(errorCode)
  if kind == "bid" then return end
  local text = GC.Util and GC.Util.AuctionHouseErrorText and GC.Util.AuctionHouseErrorText(errorCode)
    or GC.L["Posting failed"]
  -- The order rule, as for a creation: while a post we stopped waiting for is still unanswered
  -- and this one has gone out, that older post's answer comes first. The refusal ends the OLDEST
  -- late answer -- nothing booked, its item free again -- and this post stays armed for its own
  -- answer. It used to free this one: the next press sent its stack twice, and its creation was
  -- then booked as the late item (review NI1). An error while this post has not been sent yet
  -- fired inside the post call itself, and is this post's.
  local sent = S.postingPin and S.postingPin.sent
  if sent then
    local live = GC.Sell._LiveLate()
    if #live > 0 then
      GC.Sell._OweAnswer(table.remove(live, 1))
      S.postingPin.clean = false
      View.notePost(text, "red", GC.Sell.POST_NOTE_SECONDS.failed)
      Compose.Positions() -- the dock's queue offers that item again
      return
    end
  end
  -- A shared code with something else of ours out may be that request's: this post can still go
  -- up, and the late answer corrects the line below to Posted.
  if kind == "shared" and sent and GC.Sell._OtherRequestOut() then GC.Sell._AwaitLate(S.postingPin) end
  Post.DisarmPost()
  View.notePost(text, "red", GC.Sell.POST_NOTE_SECONDS.failed)
end

-- AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED: the client is holding a message back until the
-- throttle frees a slot. It fires as the post call queues the post, so while ours is on its way
-- the dock says what the wait is rather than a bare "Posting…". The row keeps turning; the post
-- goes out on its own when the slot frees, and the watchdog still bounds the wait.
function GC.Sell.OnThrottleQueued()
  local row = S.postingRow
  if not (row and (row.postStage == "posting" or row.postStage == "confirming")) then return end
  if S.postingPin then S.postingPin.queued = true end
  View.notePost(GC.L["Waiting for the Auction House…"])
end

-- An arm that is still a QUESTION -- a post awaiting Confirm, a cancel or a removal awaiting
-- its second click -- is answered "no" by a click on a row or on the panel's X. Without this
-- that click was swallowed by the render the arm holds back, for as long as the arm lived
-- (twenty seconds for a cancel): rows would not open, the panel would not shut, and the tab
-- looked hung. Anything already SENT keeps its pin until the server answers.
function Post.WalkAway()
  if S.postingRow and S.postingRow.postStage == "confirm" then Post.DisarmPost() end
  if S.repostingRow and S.repostingRow.repostStage == "armed" then Post.DisarmRepost() end
  if S.removingRow and S.removingRow.removeStage == "armed" then Post.DisarmRemove() end
end

-- Straight after a click that reached onRepostClick -- the lot's own button, the row's, the
-- dock's. If that click SENT the cancel, the pin has done its job: record the lot, let the arm
-- go (which releases every held render) and show the tab without it. See GC.Sell.cancelledLots
-- for why nothing here waits for the server. onRepostClick itself is untouched.
function Post.CancelSent()
  if not (S.repostingRow and S.repostingRow.repostStage == "cancelling" and S.repostPin) then return end
  GC.Sell.cancelledLots[S.repostPin.auctionID] = { at = time() }
  S.refresh.ownedWanted = true -- ask for the listings again as soon as the throttle allows
  Post.DisarmRepost()
  GC.Sell.OnOwnedAuctions()
  View.status(GC.L["Cancelling lot…"])
end
