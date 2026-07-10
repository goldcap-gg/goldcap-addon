std = "lua51"
max_line_length = false
self = false

-- both keys so the busted std applies when luacheck runs from addon/ (local)
-- AND from the repo root (CI passes paths like addon/spec/...)
files["spec/"] = { std = "lua51+busted" }
files["addon/spec/"] = { std = "lua51+busted" }

globals = { "GoldCapDB", "GoldCap_MarketData", "SLASH_GOLDCAP1", "SlashCmdList" }

read_globals = {
  "CreateFrame", "UIParent", "GameTooltip", "ItemRefTooltip",
  "GetCoinTextureString",
  "GetCVar", "GetRealmName", "time",
  "C_Item", "C_AddOns", "GetAddOnMetadata", "Item",
  "Enum", "TooltipDataProcessor", "print", "ChatFontNormal",
}
