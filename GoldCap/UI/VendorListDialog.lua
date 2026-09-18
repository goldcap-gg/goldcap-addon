local _, GC = ...

GC.UI = GC.UI or {}

-- A run's vendor stops as one selectable block of text. WoW gives an addon no way to put
-- anything on the clipboard, so the standard shape -- UI/CompanionDialog.lua's link box,
-- UI/ImportDialog.lua's paste box -- is an EditBox holding the text, focused and fully
-- selected, so Ctrl+C is the only thing left to do. Read-only in spirit: typing into it puts
-- the list straight back rather than letting the player wander off with half a shopping list.
local dialog
local shownText = ""

local function createDialog()
  local f = CreateFrame("Frame", "GoldCapVendorListDialog", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(420, 300)
  f:SetPoint("CENTER")
  -- Opened from the BUY band inside the docked auction house window, which sits at the AH's own
  -- strata with a much higher frame level than a bare MEDIUM frame -- without this the dialog
  -- renders behind it (the addon's engineering notes' "a popup needs three things").
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText(GC.L["Vendor list"])

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 12, -28)
  hint:SetWidth(396)
  hint:SetJustifyH("LEFT")
  hint:SetWordWrap(true)
  hint:SetText(GC.L["The run's vendor reagents. Press Ctrl+C to copy the list."])
  f.hint = hint

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -52)
  scroll:SetPoint("BOTTOMRIGHT", -32, 44)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(380)
  edit:SetAutoFocus(true)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  edit:SetScript("OnTextChanged", function(self)
    if self:GetText() ~= shownText then
      self:SetText(shownText)
      self:HighlightText()
    end
  end)
  scroll:SetScrollChild(edit)
  f.edit = edit

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  closeBtn:SetSize(100, 22)
  closeBtn:SetPoint("BOTTOMRIGHT", -12, 10)
  closeBtn:SetText(GC.L["Close"])
  closeBtn:SetScript("OnClick", function() f:Hide() end)
  f.closeBtn = closeBtn

  table.insert(UISpecialFrames, "GoldCapVendorListDialog") -- Escape closes the dialog
  return f
end

--- Shows `text` selected and ready to copy. Nothing to show is not an empty dialog: the caller
--- has already decided there is a list, and an empty box is a button that looks broken.
function GC.UI.ShowVendorList(text)
  if type(text) ~= "string" or text == "" then return end
  shownText = text
  dialog = dialog or createDialog()
  -- Above the docked window (HIGH, toplevel) and the auction house it docks into, every time
  -- it opens -- the same three-part fix UI/ImportDialog.lua needed after it came up behind
  -- them and read as a dead button.
  if dialog.SetToplevel then dialog:SetToplevel(true) end
  dialog:Show()
  if dialog.Raise then dialog:Raise() end
  dialog.edit:SetText(text)
  dialog.edit:SetFocus()
  dialog.edit:HighlightText()
end
