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
    local text = f.edit:GetText() or ""
    -- Buy runs (Core/AppRuns.lua): a GCR1 string is a different grammar entirely, so it is
    -- routed to its own parser rather than GC.ImportString.Parse, which only knows GCS1.
    -- Leading whitespace is allowed for, because the parser itself strips it (ImportString's
    -- own gsub) -- an anchored match without it sent a pasted string with one space in front
    -- to the GCS1 parser, which answered "not a GoldCap import string" about a run it had
    -- never been asked to read.
    if text:match("^%s*GCR1;") then
      local run = GC.AppRuns.ImportString(text)
      if not run then
        f.status:SetText("|cffff4040" .. GC.L["Import failed:"] .. " "
          .. GC.L["the run string is not valid"] .. "|r")
        return
      end
      GC.Print(GC.L["run imported: %s (%d lines)"]:format(run.name or run.code, #run.lines))
      -- ...and the tab shows it now. GC.Buy picks a run in Show(), so a run pasted while the BUY
      -- tab was already on screen sat in the list unseen until the player left the tab and came
      -- back -- which reads as an import that did nothing. Guarded because this file loads
      -- before UI/BuyFrame.lua and specs load it on its own.
      if GC.Buy and GC.Buy.SelectRun then
        GC.Buy.SelectRun(run.code)
        GC.Buy.RefreshIfShown()
      end
      f.edit:SetText("")
      f:Hide()
      return
    end
    local parsed, err = GC.ImportString.Parse(text)
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
  -- Three literals here never went through the string layer, so this line came back half
  -- English in every other language: the two origin words, the whole imported clause and the
  -- bundled "none". The clause keeps its own key so a translator can move the realm, the age
  -- and the origin around each other -- Lua 5.1 has no positional specifiers, so the ORDER of
  -- %d %s %s %s is fixed even where the words around them are not.
  local originLabel = st.importedOrigin == "app" and GC.L["auto-synced"] or GC.L["manual import"]
  GC.Print(GC.L["region %s — bundled: %d items (%s), imported: %s"]:format(
    st.region,
    st.bundledCount,
    st.bundledTs and st.bundledTs > 0 and GC.Util.FormatAge(now - st.bundledTs) or GC.L["none"],
    st.importedTs
      and (GC.L["%d items for %s (%s, %s)"]):format(
        st.importedCount, st.importedRealm, GC.Util.FormatAge(now - st.importedTs), originLabel)
      or GC.L["none"]
  ))
  -- Only when there is something to report: the normal case stays a single line.
  local appErr = GC.Data.AppDataError()
  if appErr then
    GC.Print(GC.L["Companion sync rejected:"] .. " " .. GC.Data.DescribeImportError(appErr.reason))
  end
  -- A snapshot from another region is the one status fact that explains everything else
  -- looking wrong, and it was said once when the import landed and never again. The realm
  -- and region above are what a player checks it against.
  local mismatch = GC.Data.RegionMismatchText and GC.Data.RegionMismatchText()
  if mismatch then GC.Print(mismatch) end
end
