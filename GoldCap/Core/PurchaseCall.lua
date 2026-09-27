local _, GC = ...

-- The one place a purchase click reaches the auction house's protected purchase calls
-- (StartCommoditiesPurchase, ConfirmCommoditiesPurchase, PlaceBid), for both the Deals buy
-- window (UI/SniperFrame.lua) and the BUY tab (UI/BuyFrame.lua).
--
-- What WoW: Forever refuses (beta, 2026-09-28): StartCommoditiesPurchase and PlaceBid from a click
-- whose own button was disabled before the call. A plan must therefore leave the clicked button
-- alone; its `after` closure, run straight after the call in the same click, is where the button
-- goes busy. Taint is not the gate: every addon click there starts tainted, and a tainted click
-- that reads the addon's own data may make these calls -- a throwaway test addon's twelve buttons
-- and GoldCap's own test buttons all did, the Deals plan included when another button ran it.
-- The securecallfunction fence below predates that finding; it is kept because it costs nothing
-- and the calls it wraps are proven in game.
--
-- On retail every addon click runs tainted too, and the hardware event is what lets the call
-- through; that is unchanged: the call is still made synchronously inside the same OnClick or
-- OnKeyDown, after the same checks, before the same bookkeeping.
GC.PurchaseCall = {}

-- What the last purchase click looked like to the client: whether it began clean, and whether
-- it was still clean at its protected call. Read by /gc taint; written only after the call.
GC.PurchaseCall.last = nil

-- `plan(...)` does everything the click decides and returns either nothing (no purchase call
-- this click) or the one call to make: "start", itemID, quantity | "confirm", itemID, quantity |
-- "bid", auctionID, bidAmount -- and a function to run once the call has been made. An error in
-- the plan is reported by the client and makes no call.
function GC.PurchaseCall.Click(plan, ...)
  local enteredSecure = issecure and issecure()
  local call, first, second, after = securecallfunction(plan, ...)
  local calledSecure = issecure and issecure()
  if call == "start" then
    C_AuctionHouse.StartCommoditiesPurchase(first, second)
  elseif call == "confirm" then
    C_AuctionHouse.ConfirmCommoditiesPurchase(first, second)
  elseif call == "bid" then
    C_AuctionHouse.PlaceBid(first, second)
  else
    return
  end
  GC.PurchaseCall.last = { call = call, enteredSecure = enteredSecure, calledSecure = calledSecure }
  if after then securecallfunction(after) end
end
