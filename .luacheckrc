std = "lua51"
max_line_length = false
self = false

-- both keys so the busted std applies when luacheck runs from addon/ (local)
-- AND from the repo root (CI passes paths like addon/spec/...)
files["spec/"] = { std = "lua51+busted" }
files["addon/spec/"] = { std = "lua51+busted" }

-- The three GoldCap_OnAddonCompartment* globals are named by GoldCap.toc's
-- AddonCompartment* directives, which is the only way the client can reach them.
globals = { "GoldCapDB", "GoldCap_MarketData", "GoldCap_AppData", "GoldCap_AppLedger", "GoldCap_AppRuns", "SLASH_GOLDCAP1", "SLASH_GOLDCAP2", "SlashCmdList", "GoldCapSniperFrame",
  "GoldCap_OnAddonCompartmentClick", "GoldCap_OnAddonCompartmentEnter", "GoldCap_OnAddonCompartmentLeave" }

read_globals = {
  "CreateFrame", "UIParent", "GameTooltip", "ItemRefTooltip",
  "GetCoinTextureString",
  "GetCVar", "GetRealmName", "GetLocale", "time",
  "C_Item", "C_AddOns", "GetAddOnMetadata", "Item",
  "Enum", "TooltipDataProcessor", "print", "ChatFontNormal",
  "C_AuctionHouse", "C_Timer", "PlaySound", "SOUNDKIT", "ITEM_QUALITY_COLORS",
  "CreateFromMixins", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "UISpecialFrames",
  "hooksecurefunc",
  -- Sniper v3 §3 AutoScan wiring: the machine's own clock domain, and the native AH frame
  -- whose SearchBar/SetDisplayMode are hooked for player-search detection.
  "GetTime", "AuctionHouseFrame",
  -- HOT-deal alert for alt-tabbed players (pingNewHotDeals): flashes the OS taskbar/dock icon.
  "FlashClientIcon",
  -- Blizzard's tab helpers. UI/AuctionHouseTab.lua calls TabResize/SelectTab on
  -- SetNumTabs registration was re-examined against Blizzard's own source and approved for
  -- the embedded AH tab (see UI/AuctionHouseTab.lua's header): numTabs/selectedTab feed
  -- insecure UI code only, and the pattern is what Auctionator ships at scale.
  "PanelTemplates_TabResize", "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab",
  "PanelTemplates_SetNumTabs",
  "C_Container", "ItemLocation",
  -- Reagent quality (Dragonflight+). The client is the authority on an item's
  -- tier; the goldcap.gg import is not -- see UI/Theme.lua's QualityMarkup.
  "C_TradeSkillUI", "C_TooltipInfo", "C_Texture",
  -- Combat lockdown: SetPropagateKeyboardInput is protected in combat, so the BUY tab's own
  -- keyboard handler has to ask before it touches it (UI/BuyFrame.lua).
  "InCombatLockdown",
  -- P2 ledger: player identity, gold, and the mailbox invoice API.
  "UnitName", "GetMoney",
  "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "GetInboxItem",
}
