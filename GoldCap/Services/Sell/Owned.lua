-- The player's own auctions, for the Sell tab: the query for them, filing each under the key it
-- posts under, and the events that say one went up, changed or was cancelled. Moved from
-- UI/SellFrame.lua as it was.
local _, GC = ...

local S, View = GC.SellState, GC.SellView
local Quotes, Bags, Compose, Owned, Walk, Post = GC.SellQuotes, GC.SellBags, GC.SellCompose, GC.SellOwned,
  GC.SellWalk, GC.SellPost
local exact, context, activeScope, itemName = GC.SellUtil.exact, GC.SellUtil.context, GC.SellUtil.activeScope,
  GC.SellUtil.itemName

function Owned.Request()
  if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions and GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen() then
    if not Quotes.driver.isReady() then return false, true end
    if GC.Util and GC.Util.Trace then GC.Util.Trace("sell: QueryOwnedAuctions") end
    C_AuctionHouse.QueryOwnedAuctions({})
    return true, false
  end
  return false, false
end


function Owned.OnReady()
  Compose.Positions()
  View.render()
  if S.refresh.phase == "owned" then
    -- Progress is stamped ONLY by the phase that was actually waiting for this. OWNED_AUCTIONS_
    -- UPDATED and AUCTION_CANCELED fire on their own schedule -- a lot expiring, a cancel from
    -- the Blizzard panel -- and stamping on every one of them fed the watchdog while a pricing
    -- phase sat wedged on a request that never came back, which is the one thing the watchdog
    -- exists to catch.
    Walk.MarkProgress()
    Walk.Begin()
  end
end


-- GetOwnedAuctions does not report whether an auction is a commodity, so keyForLot saw
-- isCommodity = nil and filed every owned lot under an item-style key built from itemKey's
-- item level. A commodity bought as `commodity:12363` therefore listed itself as
-- `item:12363:10:0:0`: two positions for one item, the purchase holding no listings and the
-- listing holding no cost. On screen that read as "x5 in your bags, not listed" while the
-- Blizzard auctions panel showed those same five on sale.
--
-- GetItemKeyInfo is the authority on that flag -- the quote driver (Services/Sell/Quotes.lua) already relies on it --
-- so classify here, where the API is reachable, and leave NormalizeOwnedLots pure.
--
-- Asking GetItemKeyInfo alone was not enough: it answers nil until the client has cached that
-- key, and a lot left unclassified files itself under an `item:...` key while the SAME item's
-- bag stock -- classified from the remembered answer in GC.db.commodityByItem (classifyBagItem in
-- Services/Sell/Bags.lua) -- files under `commodity:...`. Two rows for one item, the listing holding no stock
-- and the stock reading "not on hand"; and when the lot was later re-classified, the repost
-- pin stopped matching and the tab announced "Lot cancelled; wait for it to return to bags"
-- about a lot that was still live. So: read the remembered answer first, and write every fresh
-- answer back into it, exactly as the bag classifier does.
function Owned.Classify(auctions)
  local cache = Bags.CommodityKinds()
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
        S.ownedAwaitingKind[itemID] = true
      else
        S.ownedAwaitingKind[itemID] = nil
      end
    end
  end
  return auctions
end


-- Lots this tab has cancelled, by auction ID: `{ at = when the cancel was sent, confirmed =
-- whether the server said so }`. A lot in here is left out of every list this tab reads.
--
-- It exists because the tab used to wait, holding every render, until it SAW the lot leave
-- C_AuctionHouse.GetOwnedAuctions() -- and that is a cache only a new QueryOwnedAuctions
-- refreshes, so straight after a cancel it still holds the lot the server has just removed.
-- Seen in game (twice) as a tab that went dead after the confirming click: the lot still
-- listed, its button greyed at "Cancel lot?", no row opening, the panel refusing to shut, until
-- the cancel's own 30-second timeout -- or a trip to another tab, which re-queries. Nothing is
-- waited for any more: the moment CancelAuction is sent the arm is let go (Post.CancelSent) and
-- the lot stops being shown. AUCTION_CANCELED confirms it when the client sends one; an auction
-- ID is never reused, so a confirmed entry stands for the session. One that nothing confirmed
-- is given SENT_WAIT seconds, after which a list that still holds the lot is believed instead:
-- the cancel did not go through, the lot comes back and the tab says so.
GC.Sell.cancelledLots = {}
-- How long a cancel nothing confirmed is believed over a list that still holds the lot.
GC.Sell.CANCEL_SENT_WAIT = 15

function GC.Sell.OnAuctionCanceled(auctionID)
  local lots = GC.Sell.cancelledLots
  if not exact(auctionID) or auctionID <= 0 then
    -- An event that names no lot answers the one cancel still waiting, when there is exactly
    -- one; with none, or several, it concludes nothing.
    local waiting
    for id, lot in pairs(lots) do
      if not lot.confirmed then
        if waiting then return end
        waiting = id
      end
    end
    auctionID = waiting
  end
  if not auctionID then return end
  local known = lots[auctionID] ~= nil
  lots[auctionID] = { at = time(), confirmed = true }
  if known then View.status(GC.L["Lot cancelled; wait for it to return to bags"]) end
end

function GC.Sell.OnOwnedAuctions()
  local auctions = C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and C_AuctionHouse.GetOwnedAuctions() or {}
  do
    local live, returned = {}, false
    for _, auction in ipairs(auctions) do
      local lot = GC.Sell.cancelledLots[auction.auctionID]
      if lot and not lot.confirmed and time() - lot.at > GC.Sell.CANCEL_SENT_WAIT then
        GC.Sell.cancelledLots[auction.auctionID], lot, returned = nil, nil, true
      end
      if not lot then live[#live + 1] = auction end
    end
    auctions = live
    if returned then View.status(GC.L["The cancel did not go through: the lot is still listed"]) end
  end
  S.ownedLots = GC.SellPositions.NormalizeOwnedLots(Owned.Classify(auctions), time())
  local scope = context()
  -- My-auctions (docs/superpowers/specs/2026-09-06-my-auctions-design.md): the roster this
  -- read just produced is the roster the companion uploads, unchanged. No second query.
  if GC.Data and GC.Data.RecordOwnedLots and scope then
    GC.Data.RecordOwnedLots(GC.db, S.ownedLots, scope, time())
  end
  if GC.Acquisitions and GC.Acquisitions.ObserveOwnedPosition and scope then
    for _, lot in ipairs(S.ownedLots) do
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
          for _, lot in ipairs(S.ownedLots) do
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
  if S.repostingRow and S.repostPin then
    local pinnedScope, scopeKey = activeScope(S.repostPin.position)
    local stillOwned = pinnedScope and scopeKey == S.repostPin.scopeKey
    if stillOwned then
      stillOwned = false
      for _, lot in ipairs(S.ownedLots) do
        if lot.positionKey == S.repostPin.positionKey and lot.itemID == S.repostPin.itemID
            and lot.auctionID == S.repostPin.auctionID and lot.quantity == S.repostPin.quantity
            and lot.unitPrice == S.repostPin.listedUnit then
          stillOwned = true
          break
        end
      end
    end
    if not stillOwned then
      Post.DisarmRepost()
      View.status(GC.L["Lot cancelled; wait for it to return to bags"])
    end
  end
  Owned.OnReady()
end

function GC.Sell.OnItemKeyInfo(itemID)
  -- A lot this character owns was filed under a guessed key because the client could not say
  -- whether the item sells as a commodity. It can now: re-key the roster from the auctions the
  -- client is already holding (a local read, not a second query) so the listing and the bag
  -- stock land on the same row again.
  if S.ownedAwaitingKind[itemID] then
    S.ownedAwaitingKind[itemID] = nil
    if C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions and GC.SellPositions.NormalizeOwnedLots then
      S.ownedLots = GC.SellPositions.NormalizeOwnedLots(
        Owned.Classify(C_AuctionHouse.GetOwnedAuctions() or {}), time())
      Compose.Positions()
      View.render()
    end
  end
  -- Stock the tab could not key without this answer is scanned again: it can be filed now.
  for _, waiting in ipairs(GC.Sell._waitingStock or {}) do
    if waiting.itemID == itemID then
      Compose.Positions()
      View.render()
      break
    end
  end
  local awaiting = S.refresh.awaiting
  if type(awaiting) == "string" then awaiting = GC.Sell._QuoteItemKey(awaiting) end
  if S.refresh.phase == "waiting_key" and awaiting == itemID then Walk.Advance() end
end
