-- A lot's cancel, the Sell tab's half of the Cancel lot click: what the click checks and pins
-- before the protected call its handler makes (UI/Sell/Dock.lua's onRepostClick -- nothing here
-- makes one), the arm and its deposit guard, the timeouts that give a row back, and what a sent
-- cancel owes the tab. The only widget it touches is the clicked row's own button, through the
-- button's methods, and never on the way to a protected call. Moved from Services/Sell/Post.lua
-- as it was; the functions stay on GC.SellPost, so every caller reaches them as before.
local _, GC = ...

local S, View = GC.SellState, GC.SellView
local Quotes, Compose, Owned, Walk, Post = GC.SellQuotes, GC.SellCompose, GC.SellOwned, GC.SellWalk, GC.SellPost
local exact, activeScope, exactRenderEntry = GC.SellUtil.exact, GC.SellUtil.activeScope,
  GC.SellUtil.exactRenderEntry

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
local REPOST_ARM_SECONDS, REPOST_TIMEOUT_SECONDS = 1, 20
-- The in-flight cancel is a SERVER round trip and gets its own, longer watchdog. It used to
-- share REPOST_TIMEOUT_SECONDS, so a cancel the auction house took more than ten seconds to
-- confirm was announced as "Cancel timed out" -- over a lot that had in fact been cancelled.
-- That is the worst thing this control can say: it tells the player the opposite of what
-- happened to their gold. Waiting longer before giving up is the honest side to err on.
local REPOST_CANCEL_TIMEOUT_SECONDS = 30
local repostArmToken = 0

local function restoreRepostRow(row)
  if not row then return end
  row.repostStage, row.repostReady = nil, nil
  if row.action then row.action:Enable(); row.action.helpKey = "Cancel lot"; row.action:SetLabel(GC.L["Cancel lot"]) end
end

function Post.DisarmRepost()
  local row = S.repostingRow
  S.repostingRow, S.repostPin = nil, nil
  repostArmToken = (repostArmToken or 0) + 1
  restoreRepostRow(row)
  Post.FlushDeferredRender()
  View.paintCancel()
end

-- Everything a Cancel lot click does before the protected call. A first click arms (the deposit
-- warning, REPOST_ARM_SECONDS before a confirm counts, the timeout) and returns nil; the
-- confirming click checks the pin against a fresh read of the player's own auctions, marks the
-- row "cancelling" and returns the pin and its scope for onRepostClick to cancel. Plain reads
-- and writes only on the way there. With `now` (the cancel run, ROW.runLot) one press does both.
function Post.PrepareCancel(row, auctionID, now)
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
    View.status(GC.L["Fetching a fresh price for this lot. Press Repost again in a moment"])
    Walk.RefreshFor(position); return
  end
  if row.repostStage == "armed" and not now then
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
  -- The run's own confirm was this lot's arm delay: on to the confirm's checks, nothing painted.
  if now then row.repostStage, row.repostReady = "armed", true; return Post.PrepareCancel(row, auctionID) end
  row.repostStage, row.repostReady = "armed", false
  row.action.helpKey = "Cancel lot?"; row.action:Disable(); row.action:SetLabel(GC.L["Cancel lot?"])
  View.status(GC.L["Cancel this lot and lose its deposit. Click again to confirm"])
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
