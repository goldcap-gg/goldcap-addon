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

-- The bags GoldCap counts: UI/SellFrame.lua's SELL_BAGS (bag 5 is the reagent bag; a bag the
-- client does not have reports no slots).
GC.ForeverValue.BAGS = { 0, 1, 2, 3, 4, 5 }

function GC.ForeverValue.BagTotals(driver, valueFor, vendorFor)
  local t = { vendor = 0, ah = 0, priced = 0, unpriced = 0 }
  for _, bag in ipairs(GC.ForeverValue.BAGS) do
    for slot = 1, driver.numSlots(bag) or 0 do
      local info = driver.itemInfo(bag, slot)
      local id, n = info and info.itemID, info and info.stackCount
      if type(id) == "number" and type(n) == "number" and n > 0 then
        local vendor = not info.hasNoValue and vendorFor(id) or nil
        if type(vendor) == "number" and vendor > 0 then t.vendor = t.vendor + vendor * n end
        if not info.isBound then
          local value = valueFor(id)
          local mv = type(value) == "table" and value.mv or nil
          if type(mv) == "number" and mv > 0 then
            t.ah = t.ah + math.floor(mv * KEEP) * n
            t.priced = t.priced + 1
          else
            t.unpriced = t.unpriced + 1
          end
        end
      end
    end
  end
  return t
end

local function realBags()
  local c = _G.C_Container
  return {
    numSlots = function(bag)
      local ok, n = pcall(c.GetContainerNumSlots, bag)
      return ok and tonumber(n) or 0
    end,
    itemInfo = function(bag, slot)
      local ok, info = pcall(c.GetContainerItemInfo, bag, slot)
      return ok and type(info) == "table" and info or nil
    end,
  }
end

-- "your bags: X at a vendor, Y on the AH" (spec §3 Bag value), in chat: after every saved scan
-- and on /gc bags. The way to post the AH half is the Sell tab's POST queue, which in Forever
-- holds back anything a vendor pays more for (GC.Sell._QueueOpts).
function GC.ForeverValue.PrintBags(driver)
  local t = GC.ForeverValue.BagTotals(driver or realBags(), GC.Data.GetItemValue, GC.ForeverValue.VendorUnit)
  if t.priced > 0 then
    GC.Print(GC.L["Your bags: %s at a vendor, %s on the AH after its cut"]:format(
      GC.Util.CoinText(t.vendor), GC.Util.CoinText(t.ah)))
    GC.Print(GC.L["The Sell tab's POST button lists everything worth more than a vendor pays, one click each."])
  else
    GC.Print(GC.L["Your bags: %s at a vendor. Scan the auction house to see what they would fetch there."]
      :format(GC.Util.CoinText(t.vendor)))
  end
  return t
end
