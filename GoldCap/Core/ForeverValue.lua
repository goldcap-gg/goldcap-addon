local _, GC = ...

-- WoW: Forever's "where should this go" arithmetic: what a vendor pays, what the auction house
-- deposit is, and the verdict the tooltip prints. Pure except for the two client reads, both
-- guarded.
GC.ForeverValue = GC.ForeverValue or {}

-- What the player keeps of an auction house sale: the 5% cut, the same factor Core/DealMath.lua
-- and Core/Trigger.lua apply.
local KEEP = 0.95

-- The client forgets. On WoW: Forever (owner's client, 2026-11-10, a probe of 56 board builds from
-- one unchanged scan) C_Item.GetItemInfo answered for an item at one build and not at the next,
-- five seconds on: the items with a quality went 138 to 184 and back, the Deals board's rows 2 to
-- 8 and back, and 2,740 of 4,710 items had none whenever they were asked. A vendor price and a
-- quality are the item's own and never change, so the first answer is kept with the account
-- (GoldCapDB.foreverItemInfo, [itemID] = sellPrice * 8 + quality) and stands in whenever the
-- client has none to give.
local function itemInfo(itemID)
  if type(itemID) ~= "number" then return nil end
  local item = _G.C_Item
  if type(item) == "table" and type(item.GetItemInfo) == "function" then
    local ok, quality, sellPrice = pcall(function()
      local _, _, q, _, _, _, _, _, _, _, price = item.GetItemInfo(itemID)
      return q, price
    end)
    if ok and type(quality) == "number" and quality >= 0 and quality < 8 then
      sellPrice = type(sellPrice) == "number" and sellPrice > 0 and math.floor(sellPrice) or 0
      if GC.db then
        GC.db.foreverItemInfo = GC.db.foreverItemInfo or {}
        GC.db.foreverItemInfo[itemID] = sellPrice * 8 + quality
      end
      return quality, sellPrice
    end
    if ok and type(sellPrice) == "number" and sellPrice > 0 then return nil, sellPrice end
  end
  local kept = GC.db and type(GC.db.foreverItemInfo) == "table" and GC.db.foreverItemInfo[itemID] or nil
  if type(kept) ~= "number" then return nil end
  return kept % 8, math.floor(kept / 8)
end

function GC.ForeverValue.VendorUnit(itemID)
  local _, sellPrice = itemInfo(itemID)
  if type(sellPrice) == "number" and sellPrice > 0 then return sellPrice end
  return nil
end

-- The item's quality (0 poor, 1 common, ...) from the same C_Item.GetItemInfo answer VendorUnit
-- reads, so an item with a vendor price has a quality too. nil while the client has not loaded it.
function GC.ForeverValue.Quality(itemID)
  return (itemInfo(itemID))
end

-- One unit's deposit for a commodity, as the client quotes it from the item alone
-- (C_AuctionHouse.CalculateCommodityDeposit): the caller has already been told the item IS a
-- commodity. nil when the client does not answer.
function GC.ForeverValue.CommodityDepositUnit(itemID)
  local ok, deposit = pcall(GC.Flips.CommodityDeposit, itemID, 1)
  if ok and type(deposit) == "number" and deposit >= 0 then return deposit end
  return nil
end

-- The client's deposit quotes, per item and "duration:quantity", for this session. The client
-- forgets these as it forgets an item's own figures (itemInfo above): on the owner's client
-- (2026-11-10), from one scan and with every other answer steady, it quoted 45 of 53 asks at one
-- board build and 5 of 28 at the next, and the board's commodity rows went 8, 0, 8, 0. The last
-- quote the client gave stands in when it gives none. Not saved: a patch may change the rule. The
-- Post and Buy clicks ask the client themselves (Core/Flips.lua) and never read this.
local depositQuotes = {}

-- The deposit for one post of `quantity` units of a commodity, as the client quotes it. On WoW:
-- Forever a post pays at least 1s whatever its size, and about a fifth of the vendor price a unit
-- above that (owner's client, 2026-11-07: Linen Cloth 1s for 1 unit, 1s for 10, 2s for 100), so
-- the 1-unit quote is a post's floor, never a unit's share of a bigger one. nil when the client
-- does not answer.
function GC.ForeverValue.CommodityDeposit(itemID, quantity)
  -- The duration Core/Flips.lua's CommodityDeposit will quote at, for the key alone.
  local duration = GC.GroupRules and GC.GroupRules.durationByItem and GC.GroupRules.durationByItem[itemID]
  if duration ~= 1 and duration ~= 2 and duration ~= 3 then duration = GC.Flips.PostDurationIndex() end
  local key = duration .. ":" .. tostring(quantity)
  local ok, deposit = pcall(GC.Flips.CommodityDeposit, itemID, quantity)
  if ok and type(deposit) == "number" and deposit >= 0 then
    local quotes = depositQuotes[itemID]
    if not quotes then quotes = {}; depositQuotes[itemID] = quotes end
    quotes[key] = deposit
    return deposit
  end
  return depositQuotes[itemID] and depositQuotes[itemID][key] or nil
end

-- The tooltip's deposit: only for an item the Sell tab has seen is a commodity
-- (GC.db.commodityByItem, learned at the auction house). An item needs an ItemLocation the
-- tooltip does not reliably carry, so it gets nil and its verdict says the deposit is not counted.
function GC.ForeverValue.DepositUnit(itemID)
  local known = GC.db and GC.db.commodityByItem and GC.db.commodityByItem[itemID]
  if known ~= true then return nil end
  return GC.ForeverValue.CommodityDepositUnit(itemID)
end

-- `perDay` (optional): the units a day the house sells of the item (GC.Data.ForeverSales). A slow
-- seller's post comes back unsold several times for each time it sells, so its gain is held to
-- that many deposits, as the Sell tab's queue holds it (Core/PostQueue.lua's below_deposit): the
-- tooltip must not say "Sell it on the AH" of a post the queue holds back.
function GC.ForeverValue.Verdict(ahUnit, vendorUnit, depositUnit, gear, perDay)
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
  local unsoldX2 = GC.PostQueue and GC.PostQueue.UnsoldPerSaleX2 and GC.PostQueue.UnsoldPerSaleX2(perDay) or 2
  if gain * 2 <= depositUnit * unsoldX2 then return "deposit" end
  return "ah"
end

-- The bags GoldCap counts: Services/Sell/Bags.lua's SELL_BAGS (bag 5 is the reagent bag; a bag the
-- client does not have reports no slots).
GC.ForeverValue.BAGS = { 0, 1, 2, 3, 4, 5 }

-- vendor/ah/priced/unpriced: /gc bags and the scan's chat line. best: each stack at the better of
-- a vendor and the AH after its cut -- Road to 40's "bags" (Core/ForeverRoad.lua); a soulbound
-- stack counts at a vendor only. gain/gainItems: what the AH adds over a vendor, where both pay.
function GC.ForeverValue.BagTotals(driver, valueFor, vendorFor)
  local t = { vendor = 0, ah = 0, priced = 0, unpriced = 0, best = 0, gain = 0, gainItems = 0 }
  local gainSeen = {}
  for _, bag in ipairs(GC.ForeverValue.BAGS) do
    for slot = 1, driver.numSlots(bag) or 0 do
      local info = driver.itemInfo(bag, slot)
      local id, n = info and info.itemID, info and info.stackCount
      if type(id) == "number" and type(n) == "number" and n > 0 then
        local vendor = not info.hasNoValue and vendorFor(id) or nil
        local vendorTotal = (type(vendor) == "number" and vendor > 0) and vendor * n or 0
        t.vendor = t.vendor + vendorTotal
        local ahTotal = 0
        if not info.isBound then
          local value = valueFor(id)
          local mv = type(value) == "table" and value.mv or nil
          if type(mv) == "number" and mv > 0 then
            ahTotal = math.floor(mv * KEEP) * n
            t.ah = t.ah + ahTotal
            t.priced = t.priced + 1
          else
            t.unpriced = t.unpriced + 1
          end
        end
        t.best = t.best + math.max(vendorTotal, ahTotal)
        if vendorTotal > 0 and ahTotal > vendorTotal then
          t.gain = t.gain + (ahTotal - vendorTotal)
          if not gainSeen[id] then
            gainSeen[id] = true
            t.gainItems = t.gainItems + 1
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

-- The client's own bags, priced the way the tooltip prices them. `valueFor` (optional) answers an
-- item's value table, as GC.Data.GetItemValue does when it is left out: the vendor note
-- (UI/MerchantNote.lua) hands in the tooltip's own figure, which on retail is an imported realm
-- item's region price rather than its realm median.
function GC.ForeverValue.RealBagTotals(valueFor)
  return GC.ForeverValue.BagTotals(realBags(), valueFor or GC.Data.GetItemValue, GC.ForeverValue.VendorUnit)
end

-- "your bags: X at a vendor, Y on the AH" (spec §3 Bag value), in chat: after every saved scan
-- and on /gc bags. The way to post the AH half is the Sell tab's POST queue, which in Forever
-- holds back anything a vendor pays more for (GC.Sell._QueueOpts).
--
-- `said`, when given (the scan's summary passes it), is the session's record of what chat already
-- has: the bags line is skipped while it reads the same as last time, and the POST hint prints
-- once. Without it (`/gc bags`) everything prints.
function GC.ForeverValue.PrintBags(driver, said)
  local t = driver and GC.ForeverValue.BagTotals(driver, GC.Data.GetItemValue, GC.ForeverValue.VendorUnit)
    or GC.ForeverValue.RealBagTotals()
  local line, hint
  if t.priced > 0 then
    line = GC.L["Your bags: %s at a vendor, %s on the AH after its cut"]:format(
      GC.Util.CoinText(t.vendor), GC.Util.CoinText(t.ah))
    hint = GC.L["The Sell tab's POST button lists everything worth more than a vendor pays, one click each."]
  else
    line = GC.L["Your bags: %s at a vendor. Scan the auction house to see what they would fetch there."]
      :format(GC.Util.CoinText(t.vendor))
  end
  if not said or said.bags ~= line then GC.Print(line) end
  if said then said.bags = line end
  if hint and not (said and said.postHint) then
    GC.Print(hint)
    if said then said.postHint = true end
  end
  return t
end
