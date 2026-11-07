local _, GC = ...

-- WoW: Forever: what a merchant charges for a crafting reagent, as the player saw it at that
-- merchant. Thread, vials, flux, dyes and salt are sold by vendors and rarely or never listed on
-- the auction house, so a scan has no price for them and a recipe that needs one had no figure at
-- all. The merchant window is the only honest source: the client's own item data carries a nominal
-- buy price that is no proof a vendor sells the item at all (ItemSparse's BuyPrice is set on cloth
-- and ore nobody sells), and four times the sell price is a guess. So GoldCap keeps the price the
-- merchant asked, per item, the last one seen, and never one it did not see.
--
-- Pure: the caller reads the merchant (GC.VendorBuys.MerchantRow for each slot, then
-- GC.BuyVendor.Offers, which leaves out anything sold out, sold for a currency or items, or not
-- purchasable) and hands over the offers and whether an item is a crafting reagent
-- (GC.VendorBuys.IsReagent, the rule Core/VendorBuys.lua books a merchant purchase by).
--
-- Saved shape (GoldCapDB.foreverVendor, made by the first merchant visit, only on Forever):
--   { v = 1, items = { [itemID] = { u = <copper for one>, at = <epoch seconds> } } }
-- `u` is whole copper: a merchant's price buys a stack (`price` for `stack` units, the 2026-10-01
-- probe in Core/BuyVendor.lua), and a price that does not split evenly is rounded up, so a cost
-- said is never under the cost paid. The price is this character's at that merchant (reputation
-- can lower it): the newest visit wins.
GC.ForeverVendorPrices = GC.ForeverVendorPrices or {}
local V = GC.ForeverVendorPrices

V.VERSION = 1

local function wholeUnit(offer)
  local price, stack = tonumber(offer.price), tonumber(offer.stack)
  if not (price and stack) or price <= 0 or stack < 1 then return nil end
  local unit = math.ceil(price / stack - 1e-9)
  return unit >= 1 and unit or nil
end

--- The store under `root` (GoldCapDB), made when `create` and missing. nil for a store a newer
--- GoldCap wrote (its `v` above VERSION) or of another shape: that one is never read or written.
function V.Store(root, create)
  if type(root) ~= "table" then return nil end
  local s = root.foreverVendor
  if s == nil and create then
    s = { v = V.VERSION, items = {} }
    root.foreverVendor = s
  end
  if type(s) ~= "table" or s.v ~= V.VERSION or type(s.items) ~= "table" then return nil end
  return s
end

--- Keeps what one merchant asks for each crafting reagent among `offers` (GC.BuyVendor.Offers'
--- answer, by item id) at `now`. Answers how many items it wrote.
function V.Record(root, offers, isReagent, now)
  if type(offers) ~= "table" or type(isReagent) ~= "function" or type(now) ~= "number" then return 0 end
  local s
  local n = 0
  for itemID, offer in pairs(offers) do
    local unit = type(itemID) == "number" and type(offer) == "table" and wholeUnit(offer) or nil
    if unit and isReagent(itemID) == true then
      s = s or V.Store(root, true)
      if not s then return n end
      s.items[itemID] = { u = unit, at = now }
      n = n + 1
    end
  end
  return n
end

--- What a merchant asked for one of `itemID`, in copper, when the player has seen one sell it.
function V.UnitFor(root, itemID)
  local s = V.Store(root, false)
  local e = s and type(itemID) == "number" and s.items[itemID] or nil
  local u = type(e) == "table" and e.u or nil
  if type(u) == "number" and u >= 1 and u == math.floor(u) then return u end
  return nil
end
