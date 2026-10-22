local _, GC = ...

-- Reads the real bags into the stacks Core/VendorSelect.lua chooses from. This is the one place
-- that knows the client's reasons a stack must not be sold: refundable, a loot-trade timer, an
-- equipment set, a bag the player excluded from junk selling. Every client read is under pcall;
-- where a protection cannot be read, the stack is marked as protected (fail closed).
GC.VendorBags = {}
local B = GC.VendorBags

-- EQUIPMENT_SET_EMPTY_SLOT = 0, EQUIPMENT_SET_IGNORED_SLOT = 1, EQUIPMENT_SET_ITEM_MISSING = -1
-- (Blizzard_FrameXMLBase/Constants.lua): a set's location is a real place only above 1.
local LAST_SENTINEL = 1

-- C_Item.GetItemInfo returns: classID is the 12th value, isCraftingReagent the 17th. Gear is a
-- weapon (2), armor (4) or profession equipment (19; Enum.ItemClass, live
-- ItemConstantsDocumentation.lua): each comes in ranks or levels under one id, so its auction house
-- figure is the cheapest version's and the value rule never sells it.
local GEAR_CLASS = { [2] = true, [4] = true, [19] = true }

-- pcall that returns ok and the answer.
local function try(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

-- Equipment sets (C_EquipmentSet.GetEquipmentSetIDs, GetItemLocations;
-- EquipmentManager_GetLocationData in Blizzard_FrameXML/Shared/EquipmentManager.lua): the
-- "bag:slot" places a set holds. nil when the API cannot be read, which the caller treats as
-- "every gear stack is in a set".
local function setPlaces()
  local sets = _G.C_EquipmentSet
  if type(sets) ~= "table" or type(_G.EquipmentManager_GetLocationData) ~= "function" then return nil end
  local ok, ids = try(sets.GetEquipmentSetIDs)
  if not ok or type(ids) ~= "table" then return nil end
  local places = {}
  for _, id in ipairs(ids) do
    local okLocs, locations = try(sets.GetItemLocations, id)
    if not okLocs then return nil end
    for _, location in pairs(type(locations) == "table" and locations or {}) do
      if type(location) == "number" and location > LAST_SENTINEL then
        local okData, data = try(_G.EquipmentManager_GetLocationData, location)
        if not okData then return nil end
        if type(data) == "table" and data.isBags and not data.isBank and data.bag and data.slot then
          places[data.bag .. ":" .. data.slot] = true
        end
      end
    end
  end
  return places
end

-- BIND_TRADE_TIME_REMAINING with its %s turned into a pattern for the tooltip line.
local function tradeTimerPattern()
  local text = _G.BIND_TRADE_TIME_REMAINING
  if type(text) ~= "string" or text == "" then return nil end
  return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", ".+"))
end

-- A bound stack may still be tradeable raid loot, which a scripted sale turns into a confirm on
-- the cursor item. C_TooltipInfo.GetBagItem (TooltipInfoDocumentation.lua) carries the line.
local function hasTradeTimer(bag, slot)
  local tooltip = _G.C_TooltipInfo
  local pattern = tradeTimerPattern()
  if type(tooltip) ~= "table" or not pattern then return true end
  local ok, data = try(tooltip.GetBagItem, bag, slot)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return true end
  for _, line in ipairs(data.lines) do
    if type(line) == "table" and type(line.leftText) == "string" and line.leftText:find(pattern) then
      return true
    end
  end
  return false
end

-- Refundable by either source: C_Container.GetContainerItemPurchaseInfo (ItemPurchaseInfo.refundSeconds)
-- or C_Item.CanBeRefunded. Neither answering at all is read as refundable.
local function isRefundable(bag, slot)
  local okInfo, info = try(C_Container.GetContainerItemPurchaseInfo, bag, slot, false)
  if okInfo and type(info) == "table" and type(info.refundSeconds) == "number" and info.refundSeconds > 0 then
    return true
  end
  local okLoc, can = false, nil
  if _G.ItemLocation and ItemLocation.CreateFromBagAndSlot and C_Item then
    okLoc, can = try(function()
      return C_Item.CanBeRefunded(ItemLocation:CreateFromBagAndSlot(bag, slot))
    end)
  end
  if okLoc and can == true then return true end
  return not okInfo and not okLoc
end

-- ExcludeJunkSell: the backpack has its own call (ContainerFrame.lua), the other bags a slot flag.
local function isExcluded(bag)
  local ok, answer
  if bag == 0 then
    ok, answer = try(C_Container.GetBackpackSellJunkDisabled)
  else
    local flag = _G.Enum and Enum.BagSlotFlags and Enum.BagSlotFlags.ExcludeJunkSell
    ok, answer = try(C_Container.GetBagSlotFlag, bag, flag)
  end
  if not ok then return true end
  return answer == true
end

local function isSelling(info, bag, slot)
  local marks = type(GC.db) == "table" and GC.db.sellMarks
  if type(marks) ~= "table" then return false end
  if marks["commodity:" .. info.itemID] == true then return true end
  if GC.Sell and GC.Sell._SlotKey then
    local ok, key = try(GC.Sell._SlotKey, info.itemID, info.hyperlink, bag, slot)
    if ok and key and marks[key] == true then return true end
  end
  return false
end

function B.Read(valueFor)
  local stacks = {}
  if type(_G.C_Container) ~= "table" then return stacks end
  local places = setPlaces()
  for _, bag in ipairs(GC.ForeverValue.BAGS) do
    local okN, n = try(C_Container.GetContainerNumSlots, bag)
    n = okN and type(n) == "number" and n or 0
    local excluded
    for slot = 1, n do
      local okI, info = try(C_Container.GetContainerItemInfo, bag, slot)
      if okI and type(info) == "table" and info.itemID then
        if excluded == nil then excluded = isExcluded(bag) end
        local itemID = info.itemID
        local classID, reagent
        if C_Item and C_Item.GetItemInfo then
          local okG, got = pcall(function() return { C_Item.GetItemInfo(itemID) } end)
          if okG then classID, reagent = got[12], got[17] end
        end
        local gear = GEAR_CLASS[classID] == true
        local value = type(valueFor) == "function" and valueFor(itemID) or nil
        if type(value) ~= "table" then value = {} end
        local quality = info.quality
        stacks[#stacks + 1] = {
          bag = bag, slot = slot, itemID = itemID, link = info.hyperlink, count = info.stackCount,
          quality = quality, vendorUnit = GC.ForeverValue.VendorUnit(itemID),
          ahUnit = value.mv, ahSource = value.source, ahAt = value.at,
          hasNoValue = info.hasNoValue == true, isLocked = info.isLocked == true,
          isBound = info.isBound == true, isGear = gear, isReagent = reagent == true,
          refundable = isRefundable(bag, slot),
          tradeTimer = info.isBound == true and quality == 0 and hasTradeTimer(bag, slot) or false,
          inSet = (places == nil and gear) or (places ~= nil and places[bag .. ":" .. slot] == true),
          excludedBag = excluded, selling = isSelling(info, bag, slot),
        }
      end
    end
  end
  return stacks
end
