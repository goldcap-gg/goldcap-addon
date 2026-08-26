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
  f:SetSize(420, 160)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("GoldCap Companion")

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 12, -28)
  hint:SetWidth(396)
  hint:SetJustifyH("LEFT")
  hint:SetWordWrap(true)
  hint:SetText("The free desktop Companion keeps your prices fresh automatically and syncs "
    .. "your sales. Copy the link (Ctrl+C) and open it in a browser:")

  local edit = CreateFrame("EditBox", nil, f)
  edit:SetFontObject(ChatFontNormal)
  edit:SetSize(396, 20)
  edit:SetPoint("TOPLEFT", 12, -86)
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
  closeBtn:SetText("Close")
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
