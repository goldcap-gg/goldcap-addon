local _, GC = ...

GC.CompanionUI = GC.CompanionUI or {}
GC.slashHandlers = GC.slashHandlers or {}

-- WoW cannot open a URL from an addon, so the standard pattern (same one ImportDialog.lua
-- uses for its paste box) is a small frame with an EditBox holding the link, focused and
-- fully selected so Ctrl+C just works.
local COMPANION_URL = "https://goldcap.gg/downloads"

local dialog

local function createDialog()
  local f = CreateFrame("Frame", "GoldCapCompanionDialog", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(420, 230)
  f:SetPoint("CENTER")
  -- Reachable from a click inside the docked AH window (SniperFrame.lua's staleText banner),
  -- which sits at the AH's own strata with a much higher frame level than a bare MEDIUM frame --
  -- without this the dialog renders behind it. Same rule SniperFrame.lua/SellFrame.lua's own
  -- dialogs follow (see the addon's engineering notes' "a popup needs three things" note).
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText(GC.L["GoldCap Companion"])

  -- Why before where: this dialog is the landing spot of every Companion nudge in the addon
  -- (the tooltip hint, the sniper's staleness banner, the empty board, the first-open intro),
  -- so it carries the actual case for installing, not just the link.
  local why = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  why:SetPoint("TOPLEFT", 12, -28)
  why:SetWidth(396)
  why:SetJustifyH("LEFT")
  why:SetWordWrap(true)
  why:SetText("\226\128\162 " .. GC.L["Without it, GoldCap runs on a price snapshot from its release date — deals get hunted with old prices."]
    .. "\n\226\128\162 " .. GC.L["With it, your realm's prices refresh automatically and your sales feed your ledger on goldcap.gg."]
    .. "\n\226\128\162 " .. GC.L["Free, sits in the tray, nothing to set up in game."])
  f.why = why

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", why, "BOTTOMLEFT", 0, -10)
  hint:SetWidth(396)
  hint:SetJustifyH("LEFT")
  hint:SetWordWrap(true)
  hint:SetText(GC.L["Copy the link (Ctrl+C) and open it in a browser:"])
  f.hint = hint

  local edit = CreateFrame("EditBox", nil, f)
  edit:SetFontObject(ChatFontNormal)
  edit:SetSize(396, 20)
  edit:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
  edit:SetAutoFocus(true)
  edit:SetText(COMPANION_URL)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  -- The link is read-only in spirit: if the player types into it, put the URL straight back
  -- and reselect it rather than letting them wander off with a half-edited link.
  edit:SetScript("OnTextChanged", function(self)
    if self:GetText() ~= COMPANION_URL then
      self:SetText(COMPANION_URL)
      self:HighlightText()
    end
  end)
  f.edit = edit

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  closeBtn:SetSize(100, 22)
  closeBtn:SetPoint("BOTTOMRIGHT", -12, 10)
  closeBtn:SetText(GC.L["Close"])
  closeBtn:SetScript("OnClick", function() f:Hide() end)
  f.closeBtn = closeBtn

  table.insert(UISpecialFrames, "GoldCapCompanionDialog") -- Escape closes the dialog

  return f
end

function GC.CompanionUI.Show()
  dialog = dialog or createDialog()
  dialog.edit:SetText(COMPANION_URL)
  dialog:Show()
  dialog.edit:SetFocus()
  dialog.edit:HighlightText()
end

function GC.CompanionUI.Hide()
  if dialog then dialog:Hide() end
end

GC.slashHandlers.companion = function() GC.CompanionUI.Show() end
