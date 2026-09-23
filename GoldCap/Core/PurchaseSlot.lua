local _, GC = ...

-- The client allows exactly one commodity purchase in flight, and its terminal events
-- (COMMODITY_PRICE_UPDATED, COMMODITY_PURCHASE_SUCCEEDED, COMMODITY_PURCHASE_FAILED,
-- COMMODITY_PRICE_UNAVAILABLE) carry no attempt id -- so two owners (the Deals dialog in
-- UI/SniperFrame.lua and the BUY tab, GC.Buy) can never both have one in flight, and a
-- terminal event has to route by owner rather than by attempt. MAX_SECONDS mirrors
-- GC.Sniper's own quiet-zone bound (LIM.QUIET_ZONE_MAX_SECONDS): a claim nobody released
-- within that window is stale and may be taken over, the same fail-safe the quiet zone
-- already relies on for a terminal event that never arrives.
GC.PurchaseSlot = {}

GC.PurchaseSlot.MAX_SECONDS = 30

local owner, claimedAt = nil, nil

local function currentTime(now)
  return now or (GetTime and GetTime() or time())
end

-- Refuses a different owner while the claim is live; a stale claim (older than MAX_SECONDS)
-- may be taken over. The same owner re-claiming always succeeds and refreshes the timestamp.
function GC.PurchaseSlot.Claim(claimant, now)
  now = currentTime(now)
  if owner and owner ~= claimant and (now - claimedAt) <= GC.PurchaseSlot.MAX_SECONDS then
    return false
  end
  owner = claimant
  claimedAt = now
  return true
end

-- No-op unless `claimant` is the current owner -- releasing a slot you don't hold must never
-- steal it out from under whoever does.
function GC.PurchaseSlot.Release(claimant)
  if owner == claimant then
    owner, claimedAt = nil, nil
  end
end

function GC.PurchaseSlot.Owner()
  return owner
end

-- The one rule both Start sites keep (the Sniper's onDialogPrimaryClick, the BUY tab's
-- onBuyClick): no commodity purchase starts while a purchase either window CONFIRMED is still owed
-- its answer -- the claim above is not enough on its own. It goes stale after MAX_SECONDS, and a
-- confirmed purchase can be owed longer than that (the Sniper's stranded release waits 35 s, and a
-- confirm carried across an auction house close keeps the claim it had), so the other window took
-- the stale claim over and started a purchase on top of one that may already have taken gold.
-- Returns the window whose confirm is owed ("sniper" or "buy"), or nil. Each window answers for
-- itself: GC.Sniper._ConfirmedOwed and GC.Buy.ConfirmOwed; a window not loaded owes nothing.
function GC.PurchaseSlot.ConfirmOwed()
  if GC.Sniper and GC.Sniper._ConfirmedOwed and GC.Sniper._ConfirmedOwed() then return "sniper" end
  if GC.Buy and GC.Buy.ConfirmOwed and GC.Buy.ConfirmOwed() then return "buy" end
  return nil
end

-- Same staleness bound as Claim: a claim nobody released within MAX_SECONDS is no longer
-- reported busy, exactly as it is no longer protected from being taken over.
function GC.PurchaseSlot.IsBusy(now)
  return owner ~= nil and (currentTime(now) - claimedAt) <= GC.PurchaseSlot.MAX_SECONDS
end
