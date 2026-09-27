local _, GC = ...

-- The one place a purchase click reaches the auction house's protected purchase calls
-- (StartCommoditiesPurchase, ConfirmCommoditiesPurchase, PlaceBid), for both the Deals buy
-- window (UI/SniperFrame.lua) and the BUY tab (UI/BuyFrame.lua).
--
-- WoW: Forever blocks one of those calls when the click's execution has read anything a tainted
-- execution wrote -- and by the time a player clicks Buy, everything GoldCap's board, its buy
-- window and its clocks wrote may be tainted (the owner's /gc taint, 3c beta: every field). The
-- client starts each click clean; Auctionator's Buy works because its click reads nothing
-- tainted before its call. Ours cannot avoid reading the board, so the reading is fenced off:
-- the click's own code runs inside securecallfunction, which hands back its answer and puts the
-- click's execution back the way it was -- the same way Blizzard's CallbackRegistry reads a
-- table an addon may have tainted (`securecallfunction(unpack, value)`). The protected call is
-- then made here, straight from the click, from what the plan returned.
--
-- On retail every addon click runs tainted anyway, and the hardware event is what lets the call
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
