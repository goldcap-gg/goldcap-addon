local ADDON_NAME, GC = ...

local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
GC.version = getMeta and getMeta(ADDON_NAME, "Version") or "dev"

GC.DEFAULTS = {
  dbVersion = 1,
  settings = {
    tooltip = true,
    sniper = {
      autoOpen = true,
      sound = true,
      hotDiscount = 0.40, hotProfit = 5000000,
      goodDiscount = 0.25, goodProfit = 1000000,
      watchDiscount = 0.10, suspectDiscount = 0.90,
    },
  },
}

GC.slashHandlers = GC.slashHandlers or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
frame:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
frame:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
frame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
frame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
frame:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED")
frame:RegisterEvent("COMMODITY_PRICE_UPDATED")
frame:RegisterEvent("COMMODITY_PRICE_UNAVAILABLE")
frame:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
frame:RegisterEvent("COMMODITY_PURCHASE_FAILED")

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON_NAME then return end
    GoldCapDB = GoldCapDB or {}
    if GC.Util then GC.Util.ApplyDefaults(GoldCapDB, GC.DEFAULTS) end
    GC.db = GoldCapDB
    if GC.Data then GC.Data.Init(GC.db) end
    frame:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
    local interactionType = ...
    if interactionType == Enum.PlayerInteractionType.Auctioneer then
      GC.Sniper.OnAuctionHouseShow()
    end
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local interactionType = ...
    if interactionType == Enum.PlayerInteractionType.Auctioneer then
      GC.Sniper.OnAuctionHouseClosed()
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if GC.Sniper.scanner then GC.Sniper.scanner:OnSystemReady() end
  elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
    if GC.Sniper.scanner then
      local itemID = ...
      GC.Sniper.scanner:OnKeyInfo(itemID)
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if GC.Sniper.scanner then
      local itemKey = ...
      GC.Sniper.scanner:OnItemResults(itemKey.itemID)
    end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if GC.Sniper.scanner then
      local itemID = ...
      GC.Sniper.scanner:OnCommodityResults(itemID)
    end
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    if GC.Sniper.OnPurchaseCompleted then
      local auctionID = ...
      GC.Sniper.OnPurchaseCompleted(auctionID)
    end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    if GC.Sniper.OnCommodityPriceUpdated then
      local unitPrice, totalPrice = ...
      GC.Sniper.OnCommodityPriceUpdated(unitPrice, totalPrice)
    end
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    if GC.Sniper.OnCommodityPriceUnavailable then
      GC.Sniper.OnCommodityPriceUnavailable()
    end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if GC.Sniper.OnCommodityPurchaseSucceeded then
      GC.Sniper.OnCommodityPurchaseSucceeded()
    end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if GC.Sniper.OnCommodityPurchaseFailed then
      GC.Sniper.OnCommodityPurchaseFailed()
    end
  end
end)

function GC.Print(msg)
  print("|cffffd100GoldCap|r: " .. tostring(msg))
end

function GC.OnSlash(msg)
  msg = (msg or ""):match("^%s*(%S*)") or ""
  local handler = GC.slashHandlers[msg:lower()]
  if handler then
    handler()
  else
    GC.Print("v" .. GC.version .. " — commands: /goldcap import, /goldcap status, /goldcap sniper")
  end
end

GC.slashHandlers.sniper = function() GC.Sniper.Toggle() end

SLASH_GOLDCAP1 = "/goldcap"
SlashCmdList.GOLDCAP = GC.OnSlash
