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

-- Same staleness bound as Claim: a claim nobody released within MAX_SECONDS is no longer
-- reported busy, exactly as it is no longer protected from being taken over.
function GC.PurchaseSlot.IsBusy(now)
  return owner ~= nil and (currentTime(now) - claimedAt) <= GC.PurchaseSlot.MAX_SECONDS
end
