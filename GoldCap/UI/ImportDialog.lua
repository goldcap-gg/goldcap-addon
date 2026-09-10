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
  f.TitleText:SetText(GC.L["GoldCap — Import realm prices"])

  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 12, -28)
  hint:SetText(GC.L["Paste your realm string from goldcap.gg and press Import."])

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
  btn:SetText(GC.L["Import"])
  btn:SetScript("OnClick", function()
    local parsed, err = GC.ImportString.Parse(f.edit:GetText() or "")
    if not parsed then
      f.status:SetText("|cffff4040" .. GC.L["Import failed:"] .. " "
        .. GC.Data.DescribeImportError(err) .. "|r")
      return
    end
    GC.Data.SetImported(parsed)
    GC.db.imported.origin = "manual" -- a manual paste always wins the origin marker back from "app"
    -- A fresh import can carry a different set of realm items worth watching (T section), and
    -- the sniper's key poll is built from it -- see GC.Sniper._RebuildKeyTargets. Guarded
    -- because this file loads before UI/SniperFrame.lua and specs load it on its own.
    if GC.Sniper and GC.Sniper._RebuildKeyTargets then GC.Sniper._RebuildKeyTargets() end
    local st = GC.Data.GetStatus()
    GC.Print(GC.L["imported %d items for %s (%s) — prices are live now."]
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
  GC.Print(GC.L["region %s — bundled: %d items (%s), imported: %s"]:format(
    st.region,
    st.bundledCount,
    st.bundledTs and st.bundledTs > 0 and GC.Util.FormatAge(now - st.bundledTs) or "none",
    st.importedTs
      and ("%d items for %s (%s, %s)"):format(
        st.importedCount, st.importedRealm, GC.Util.FormatAge(now - st.importedTs), originLabel)
      or GC.L["none"]
  ))
  -- Only when there is something to report: the normal case stays a single line.
  local appErr = GC.Data.AppDataError()
  if appErr then
    GC.Print(GC.L["Companion sync rejected:"] .. " " .. GC.Data.DescribeImportError(appErr.reason))
  end
end
