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
frame:SetScript("OnEvent", function(_, _, name)
  if name ~= ADDON_NAME then return end
  GoldCapDB = GoldCapDB or {}
  if GC.Util then GC.Util.ApplyDefaults(GoldCapDB, GC.DEFAULTS) end
  GC.db = GoldCapDB
  if GC.Data then GC.Data.Init(GC.db) end
  frame:UnregisterEvent("ADDON_LOADED")
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
    GC.Print("v" .. GC.version .. " — commands: /goldcap import, /goldcap status")
  end
end

SLASH_GOLDCAP1 = "/goldcap"
SlashCmdList.GOLDCAP = GC.OnSlash
