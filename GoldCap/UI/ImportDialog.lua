local _, GC = ...

GC.UI = GC.UI or {}
GC.slashHandlers = GC.slashHandlers or {}

local dialog

local function createDialog()
  local f = CreateFrame("Frame", "GoldCapImportDialog", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(520, 300)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText("GoldCap — Import realm prices")

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 12, -28)
  hint:SetText("Paste your realm string from goldcap.gg and press Import.")

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -48)
  scroll:SetPoint("BOTTOMRIGHT", -32, 44)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(460)
  edit:SetAutoFocus(true)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  scroll:SetScrollChild(edit)
  f.edit = edit

  local status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", 12, 16)
  f.status = status

  local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btn:SetSize(100, 22)
  btn:SetPoint("BOTTOMRIGHT", -12, 10)
  btn:SetText("Import")
  btn:SetScript("OnClick", function()
    local parsed, err = GC.ImportString.Parse(f.edit:GetText() or "")
    if not parsed then
      f.status:SetText("|cffff4040Import failed: " .. tostring(err) .. "|r")
      return
    end
    GC.Data.SetImported(parsed)
    GC.db.imported.origin = "manual" -- a manual paste always wins the origin marker back from "app"
    local st = GC.Data.GetStatus()
    GC.Print(("imported %d items for %s (%s) — prices are live now.")
      :format(st.importedCount, st.importedRealm, parsed.region))
    f.edit:SetText("")
    f:Hide()
  end)

  return f
end

function GC.UI.ShowImportDialog()
  dialog = dialog or createDialog()
  dialog.status:SetText("")
  dialog:Show()
  dialog.edit:SetFocus()
end

GC.slashHandlers.import = function() GC.UI.ShowImportDialog() end

GC.slashHandlers.status = function()
  local st = GC.Data.GetStatus()
  local now = time()
  -- importedOrigin is nil for SavedVariables written before the origin marker existed --
  -- treat that the same as "manual" since every import used to be a manual paste.
  local originLabel = st.importedOrigin == "app" and "auto-synced" or "manual import"
  GC.Print(("region %s — bundled: %d items (%s), imported: %s"):format(
    st.region,
    st.bundledCount,
    st.bundledTs and st.bundledTs > 0 and GC.Util.FormatAge(now - st.bundledTs) or "none",
    st.importedTs
      and ("%d items for %s (%s, %s)"):format(
        st.importedCount, st.importedRealm, GC.Util.FormatAge(now - st.importedTs), originLabel)
      or "none"
  ))
end
