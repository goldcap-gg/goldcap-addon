local _, GC = ...

GC.UI = GC.UI or {}
GC.slashHandlers = GC.slashHandlers or {}

local dialog

-- The status line under the box wraps, and the box gives up the height it takes: an import that
-- left names out says which, in full, in every language.
local function setStatus(f, text)
  f.status:SetText(text or "")
  local h = (text and text ~= "" and f.status.GetStringHeight) and f.status:GetStringHeight() or 0
  f.scroll:ClearAllPoints()
  f.scroll:SetPoint("TOPLEFT", f.hint, "BOTTOMLEFT", 0, -8)
  f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 44 + math.ceil(tonumber(h) or 0))
end

local function createDialog()
  local f = CreateFrame("Frame", "GoldCapImportDialog", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(520, 300)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local hint = GC.Theme.ClientFont(f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
  hint:SetPoint("TOPLEFT", 12, -28)
  hint:SetWidth(496)
  hint:SetJustifyH("LEFT")
  hint:SetWordWrap(true)
  f.hint = hint

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  f.scroll = scroll

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(460)
  edit:SetAutoFocus(true)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  scroll:SetScrollChild(edit)
  f.edit = edit

  local status = GC.Theme.ClientFont(f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
  status:SetPoint("BOTTOMLEFT", 12, 40)
  status:SetWidth(496)
  status:SetJustifyH("LEFT")
  status:SetWordWrap(true)
  f.status = status

  local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  btn:SetSize(100, 22)
  btn:SetPoint("BOTTOMRIGHT", -12, 10)
  btn:SetText(GC.Util.ClientText(GC.L["Import"]))
  btn:SetScript("OnClick", function()
    local text = f.edit:GetText() or ""
    -- A list -- a goldcap.gg run string (GCR1), a TSM string or an Auctionator list -- goes to
    -- the BUY tab's lists (UI/BuyLists.lua); a GCS1 price string, and anything that is no list
    -- when the box was opened for prices, to GC.ImportString.Parse. Leading whitespace is allowed
    -- for: a GCR1 string pasted with a space in front once went to the price parser, which
    -- answered "not a GoldCap import string" about a run it had never been asked to read.
    if not text:find("GCS1;", 1, true) and GC.BuyLists and GC.BuyLists.ImportText then
      local result, why = GC.BuyLists.ImportText(text, f.into)
      if result and result.error then
        setStatus(f, "|cffff4040" .. GC.L["Import failed:"] .. " " .. result.error .. "|r")
        return
      end
      if result then
        for _, line in ipairs(result.printed or {}) do GC.Print(line) end
        -- ...and the tab shows it now. GC.Buy picks a run in Show(), so a run pasted while the BUY
        -- tab was already on screen sat in the list unseen until the player left the tab and came
        -- back -- which reads as an import that did nothing. Guarded because this file loads
        -- before UI/BuyFrame.lua and specs load it on its own.
        if result.code and GC.Buy and GC.Buy.SelectRun then
          GC.Buy.SelectRun(result.code)
          GC.Buy.RefreshIfShown()
        end
        f.edit:SetText("")
        -- What was left out stays on screen until the player has read it.
        if result.missed then
          setStatus(f, result.missed)
        else
          f:Hide()
        end
        return
      end
      if f.lists then
        setStatus(f, "|cffff4040" .. GC.L["Import failed:"] .. " " .. GC.BuyLists.NotAList(why) .. "|r")
        return
      end
    end
    -- Final review I2: no Forever import string exists yet (goldcap.gg has not shipped one),
    -- so anything pasted here on a Forever client is a retail string -- and would feed the
    -- tooltip, Deals and Sell with another client's prices. Refused before the string is even
    -- parsed, at the one place a price string is committed, so both /goldcap import (which
    -- only opens this dialog) and the dialog's own Import button are covered. Buy runs (above)
    -- are a different grammar and unaffected.
    if GC.Game and GC.Game.IsForever(GC.Game.Passport()) then
      setStatus(f, "|cffff4040" .. GC.L["goldcap.gg prices for WoW: Forever are not out yet."] .. "|r")
      return
    end
    local parsed, err = GC.ImportString.Parse(text)
    if not parsed then
      setStatus(f, "|cffff4040" .. GC.L["Import failed:"] .. " "
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

-- Opened for prices (/goldcap import) or -- `opts.lists` -- for the BUY tab's lists: a new list, or
-- every item of the paste into `opts.into`, one of the player's own lists.
function GC.UI.ShowImportDialog(opts)
  opts = opts or {}
  dialog = dialog or createDialog()
  dialog.lists, dialog.into = opts.lists == true, opts.into
  local into = opts.into and GC.AppRuns and GC.AppRuns.Get(opts.into) or nil
  if opts.lists then
    dialog.TitleText:SetText(GC.Util.ClientText(GC.L["GoldCap — Import a list"]))
    dialog.hint:SetText(into
      and (GC.L["Paste a list from goldcap.gg, TSM or Auctionator and press Import. Its items are added to %s."])
        :format(GC.AppRuns.Label(into))
      or GC.L["Paste a list from goldcap.gg, TSM or Auctionator and press Import."])
  else
    dialog.TitleText:SetText(GC.Util.ClientText(GC.L["GoldCap — Import realm prices"]))
    dialog.hint:SetText(GC.L["Paste your realm string from goldcap.gg and press Import."])
  end
  setStatus(dialog, "")
  -- Above the docked window (HIGH, toplevel) and the auction house it docks into: opened from
  -- the BUY tab's run menu, a MEDIUM-strata dialog came up behind them and read as a dead entry.
  if dialog.SetFrameStrata then dialog:SetFrameStrata("DIALOG") end
  if dialog.SetToplevel then dialog:SetToplevel(true) end
  dialog:Show()
  if dialog.Raise then dialog:Raise() end
  dialog.edit:SetFocus()
end

GC.slashHandlers.import = function() GC.UI.ShowImportDialog() end

-- Why a whole-market payload the Companion wrote could not be read, by ParseRegion's refusal code.
-- Not the manual import's sentences (GC.Data.DescribeImportError): those answer a player who pasted
-- a string, and nobody pasted this one. The addon reads the Companion's file only at load, so the
-- two that a new sync can fix end with the /reload that brings it in.
--
-- @localised-keys: the literals below ARE GC.L keys, looked up in the status handler where the table
-- is read -- file scope runs before ApplyLocale picks the language. The table closes with a brace on
-- its own line, where the locale contract spec stops reading.
local PAYLOAD_REFUSALS = {
  empty = "the Companion wrote an empty copy -- let it sync, then /reload",
  no_items = "the Companion wrote it with no prices -- let it sync, then /reload",
  bad_header = "it is in a format this build of GoldCap cannot read -- update the addon",
  bad_region = "it is for a region this build of GoldCap does not know -- update the addon",
  too_long = "it is larger than this build of GoldCap can read -- update the addon",
}

-- How old a whole-market payload's date is, for a status line: never negative (a payload may be
-- dated up to an hour ahead of this clock) and never past the clock's own epoch, however absurd the
-- date -- a refused one can be 0, or a digit run so long that tonumber reads it as inf.
local function payloadAge(now, ts)
  local age = type(ts) == "number" and now - ts or 0
  if age <= 0 then return 0 end -- ahead of this clock, or inf
  return math.min(age, now)
end

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
  -- The whole-market payload, when one is loaded: what it carried, how old its snapshot is, and
  -- what it keeps in memory -- measured here, when asked, never at load (RegionPayloadMemoryKB).
  local payload = st.payload
  if payload then
    GC.Print(GC.L["whole-market data: %d commodities, %d with sale facts, %d realm items (%s old, %d KB)"]:format(
      payload.items, payload.facts, payload.refs, GC.Util.FormatAge(payloadAge(now, payload.ts)),
      GC.Data.RegionPayloadMemoryKB() or 0))
  else
    -- One the Companion wrote that this session is not using, and why. Nothing when none was
    -- offered: an older Companion writes none, and that is nothing to report.
    local idle = GC.Data.RegionPayloadStatus and GC.Data.RegionPayloadStatus()
    if idle then
      local why
      if idle.reason == "older_than_import" then
        why = GC.L["it is %s old, and the prices you imported are newer"]:format(
          GC.Util.FormatAge(payloadAge(now, idle.ts)))
      elseif idle.reason == "other_region" then
        why = GC.L["it is for another region than the prices loaded"]
      elseif idle.reason == "set_aside" then
        why = GC.L["it was set aside when other prices were loaded this session -- /reload to use it again"]
      elseif idle.reason == "bad_ts" then
        -- The date is what is wrong, so it is not shown: 0, far ahead of the clock, or inf.
        why = GC.L["its date cannot be right -- check this computer's clock"]
      elseif PAYLOAD_REFUSALS[idle.reason] then
        why = GC.L[PAYLOAD_REFUSALS[idle.reason]]
      else
        why = GC.L["it could not be read (%s)"]:format(tostring(idle.reason))
      end
      GC.Print(GC.L["whole-market data not in use: %s"]:format(why))
    end
  end
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
