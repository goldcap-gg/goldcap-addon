local _, GC = ...

-- WoW: Forever's "where should this go" arithmetic: what a vendor pays, what the auction house
-- deposit is, and the verdict the tooltip prints. Pure except for the two client reads, both
-- guarded.
GC.ForeverValue = GC.ForeverValue or {}

-- What the player keeps of an auction house sale: the 5% cut, the same factor Core/DealMath.lua
-- and Core/Trigger.lua apply.
local KEEP = 0.95

function GC.ForeverValue.VendorUnit(itemID)
  local item = _G.C_Item
  if type(itemID) ~= "number" or type(item) ~= "table" or type(item.GetItemInfo) ~= "function" then
    return nil
  end
  local ok, sellPrice = pcall(function() return select(11, item.GetItemInfo(itemID)) end)
  if ok and type(sellPrice) == "number" and sellPrice > 0 then return sellPrice end
  return nil
end

-- One unit's deposit, for an item the client has said is a commodity (GC.db.commodityByItem,
-- learned at the auction house). An item needs an ItemLocation the tooltip does not reliably
-- carry, so it gets nil and its verdict says the deposit is not counted.
function GC.ForeverValue.DepositUnit(itemID)
  local known = GC.db and GC.db.commodityByItem and GC.db.commodityByItem[itemID]
  if known ~= true then return nil end
  local ok, deposit = pcall(GC.Flips.CommodityDeposit, itemID, 1)
  if ok and type(deposit) == "number" and deposit >= 0 then return deposit end
  return nil
end

function GC.ForeverValue.Verdict(ahUnit, vendorUnit, depositUnit, gear)
  if type(ahUnit) ~= "number" or ahUnit <= 0 then return nil end
  local vendor = (type(vendorUnit) == "number" and vendorUnit > 0) and vendorUnit or 0
  local gain = math.floor(ahUnit * KEEP) - vendor
  if gain <= 0 then
    -- Gear's figure is its cheapest version's; the one in the bags may be worth more.
    if vendor == 0 or gear then return nil end
    return "vendor"
  end
  if type(depositUnit) ~= "number" then return "ah_nodeposit" end
  -- The deposit is lost when the lot does not sell; a gain that does not cover it is a bet
  -- the vendor never asks the player to make.
  if gain <= depositUnit then return "deposit" end
  return "ah"
end
