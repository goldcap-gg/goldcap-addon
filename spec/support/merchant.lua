-- An API-shaped double of an open merchant window: GetMerchantNumItems, GetMerchantItemID,
-- GetMerchantItemMaxStack and C_MerchantFrame.GetItemInfo, as Blizzard's own merchant window reads
-- them (Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua, loaded by both retail and WoW: Forever).
-- A slot answers only MerchantItemInfo's fields (MerchantFrameDocumentation.lua, the same in both
-- games): name, texture, price (for the whole stack), stackCount, numAvailable (-1 unlimited, 0 sold
-- out), isPurchasable, isUsable, hasExtendedCost, currencyID, spellID, isQuestStartItem.
--
--   local restore = Merchant.install({ { itemID = 2320, price = 10, stackCount = 1 }, ... })
--   Merchant.shelf: the slots, which a spec may change while the window is open.
local Merchant = {}

local NAMES = { "GetMerchantNumItems", "GetMerchantItemID", "GetMerchantItemMaxStack", "C_MerchantFrame" }
local FIELDS = { "name", "texture", "price", "stackCount", "numAvailable", "isPurchasable", "isUsable",
  "hasExtendedCost", "currencyID", "spellID", "isQuestStartItem" }
local DEFAULTS = { texture = 0, price = 0, stackCount = 1, numAvailable = -1, isPurchasable = true,
  isUsable = true, hasExtendedCost = false, isQuestStartItem = false }

function Merchant.install(shelf)
  Merchant.shelf = shelf or {}
  local saved = {}
  for _, k in ipairs(NAMES) do saved[k] = _G[k] end
  _G.GetMerchantNumItems = function() return #Merchant.shelf end
  _G.GetMerchantItemID = function(index)
    local slot = Merchant.shelf[index]
    return slot and slot.itemID or nil
  end
  _G.GetMerchantItemMaxStack = function(index)
    local slot = Merchant.shelf[index]
    return slot and (slot.maxStack or 20) or 0
  end
  _G.C_MerchantFrame = setmetatable({
    GetItemInfo = function(index)
      local slot = Merchant.shelf[index]
      if not slot then return nil end
      local info = {}
      for _, field in ipairs(FIELDS) do
        local v = slot[field]
        if v == nil then v = DEFAULTS[field] end
        info[field] = v
      end
      return info
    end,
  }, { __index = function(_, key) error(("C_MerchantFrame.%s: the client has no such name"):format(tostring(key)), 2) end })
  return function()
    for _, k in ipairs(NAMES) do _G[k] = saved[k] end
  end
end

return Merchant
