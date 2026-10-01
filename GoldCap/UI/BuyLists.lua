local _, GC = ...

-- The player's lists in the BUY tab (BUY 2.0): making one in the game, naming it, pinning and
-- ordering lists, importing a TSM or Auctionator string into one, exporting one, and deleting
-- one. What the lists are lives in Core/AppRuns.lua and the two foreign strings in
-- Core/ListStrings.lua; UI/BuyFrame.lua draws the picker and the YOUR LISTS column and asks this
-- file for each list's menu (FillActions), its title and where it came from. Its own file because
-- UI/BuyFrame.lua is near its ceiling of top-level locals (docs/addon/AGENTS.md, "Hard limits").
--
-- Every popup here is UI/BuyCapEditor.lua's -- a kit popup with a background, DIALOG strata and its
-- own mouse -- and every copy or paste box is a dialog that already exists: UI/ImportDialog.lua
-- and UI/VendorListDialog.lua's.
GC.BuyLists = {}

-- The star Blizzard's auction house marks a favourite with (Blizzard_AuctionHouseUI, the same atlas
-- in retail and WoW: Forever). An escape, so every face draws it: no client font has a ★ glyph we
-- have read (docs/addon/AGENTS.md, "Text").
local STAR = "|A:auctionhouse-icon-favorite:12:12|a "
-- The bags a name is looked for in: the backpack and the carried bags, as the BUY tab counts them.
local BAGS = { 0, 1, 2, 3, 4, 5 }
-- How many names an import that missed some lists before "and N more".
local MAX_NAMES = 10

--- A list's name as the picker and the column show it: a favourite's star, then its name.
function GC.BuyLists.Title(run)
  local label = GC.AppRuns.Label(run)
  return GC.AppRuns.IsFavourite(run.code) and (STAR .. label) or label
end

--- Where a list came from, in a word: made or pasted in the game, followed from somebody, or
--- goldcap.gg's.
function GC.BuyLists.Origin(run)
  if GC.AppRuns.IsLocal(run) then return GC.L["in game"] end
  if type(run.by) == "string" and run.by ~= "" then return (GC.L["from %s"]):format(run.by) end
  return "goldcap.gg"
end

local function onScreen(code)
  local current = GC.Buy.CurrentRun and GC.Buy.CurrentRun()
  return current ~= nil and current:Code() == code
end

-- A purchase the client has in hand is booked against the list on screen: that list is not
-- archived or deleted under it (UI/BuyFrame.lua's archive guard, Finding 1).
local function held(code)
  return onScreen(code) and GC.Buy._InFlight ~= nil and GC.Buy._InFlight()
end

-- After a list changed: a list that went away while on screen hands the tab to the first one left.
local function after(code, gone)
  if gone and onScreen(code) then
    local list = GC.AppRuns.List()
    GC.Buy.SelectRun(list[1] and list[1].code or nil)
  end
  GC.Buy.RefreshIfShown()
end

-- What a popup about a list sits over: the list's entry in the column when the column is up,
-- the band's picker otherwise.
local function anchorFor(code)
  local view = GC.Buy._view
  local lists = view and view.lists
  if lists and lists.frame:IsShown() then
    for _, entry in ipairs(lists.entries) do
      if entry.button.code == code and entry.button:IsShown() then return entry.button end
    end
  end
  return view and view.band and view.band.picker or UIParent
end

--- Puts the name box over a list: the name typed is kept (an empty one, or the default typed
--- back, is "List N"), and Escape or Cancel leaves the name as it was.
function GC.BuyLists.Rename(code)
  local run = GC.AppRuns.Get(code)
  if not (GC.AppRuns.IsLocal(run) and GC.BuyCapEditor) then return end
  GC.BuyCapEditor.Open(anchorFor(code), {
    over = true, title = GC.L["Name this list"], text = GC.AppRuns.Label(run), setLabel = GC.L["Save"],
    onCommit = function(text)
      GC.AppRuns.Rename(code, text)
      GC.Buy.RefreshIfShown()
    end,
  })
end

--- "+ New": a list made in the game, "List N", picked, with the name box over it.
function GC.BuyLists.New()
  local run = GC.AppRuns.NewList()
  if not run then return nil end
  GC.Buy.SelectRun(run.code)
  GC.Buy.RefreshIfShown()
  GC.BuyLists.Rename(run.code)
  return run
end

function GC.BuyLists.Archive(code)
  if held(code) then return end
  if GC.AppRuns.SetArchived(code, true) then after(code, true) end
end

--- Asks first, in the kit's popup; only the player's own lists are deleted here.
function GC.BuyLists.Delete(code)
  local run = GC.AppRuns.Get(code)
  if not (GC.AppRuns.IsLocal(run) and GC.BuyCapEditor) then return end
  GC.BuyCapEditor.Open(anchorFor(code), {
    over = true, box = false, danger = true, setLabel = GC.L["Delete"],
    title = (GC.L["Delete %s? This cannot be undone."]):format(GC.AppRuns.Label(run)),
    onCommit = function()
      if held(code) then return end
      if GC.AppRuns.Remove(code) then after(code, true) end
    end,
  })
end

local function itemName(itemID)
  if not (C_Item and C_Item.GetItemInfo) then return nil end
  local ok, name = pcall(C_Item.GetItemInfo, itemID)
  return (ok and type(name) == "string" and name ~= "") and name or nil
end

--- A list as text to take out of the game, in the copy box: "auctionator" (the client's names, its
--- shopping list format) or "tsm" (item ids). Vendor lines are left out of both: either addon would
--- look for them on the auction house. An item the client has not loaded yet has no name to
--- write; it is asked for and left out, and the box says so.
function GC.BuyLists.Export(code, format)
  local run = GC.AppRuns.Get(code)
  if not (run and GC.UI and GC.UI.ShowCopyText) then return end
  local lines = {}
  for _, line in ipairs(run.lines or {}) do
    if not line.v then lines[#lines + 1] = line end
  end
  if format == "tsm" then
    GC.UI.ShowCopyText(GC.ListStrings.TSM(lines), {
      title = GC.L["Copy as a TSM item list"],
      hint = GC.L["Press Ctrl+C to copy, then import it into a TSM group."],
    })
    return
  end
  local text, missing = GC.ListStrings.Auctionator(GC.AppRuns.Label(run), lines, itemName)
  local hint = GC.L["Press Ctrl+C to copy, then import it in Auctionator's Shopping tab."]
  if #missing > 0 then
    for _, itemID in ipairs(missing) do
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    end
    hint = hint .. " " .. (GC.L["Items the game has not loaded yet are left out: %d. Export again in a moment."])
      :format(#missing)
  end
  GC.UI.ShowCopyText(text, { title = GC.L["Copy for Auctionator"], hint = hint })
end

--- The paste box, for a new list or -- `into` -- for one of the player's own lists.
function GC.BuyLists.Import(into)
  if GC.UI and GC.UI.ShowImportDialog then GC.UI.ShowImportDialog({ lists = true, into = into }) end
end

-- The bank's containers, by the client's own names for them (Enum.BagIndex: CharacterBankTab_1..6
-- and AccountBankTab_1..5 in retail, ..9 each in WoW: Forever). A bank the client has not loaded
-- this session answers no slots, and is simply not there.
local function bankBags()
  local out = {}
  for name, index in pairs(type(Enum) == "table" and type(Enum.BagIndex) == "table" and Enum.BagIndex or {}) do
    if type(name) == "string" and type(index) == "number"
        and (name:match("^CharacterBankTab_%d+$") or name:match("^AccountBankTab_%d+$")) then
      out[#out + 1] = index
    end
  end
  table.sort(out)
  return out
end

local function walkBags(bags, add)
  if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
  for _, bag in ipairs(bags) do
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
    for slot = 1, (ok and tonumber(slots)) or 0 do
      local got, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
      if got and type(info) == "table" and info.itemID then add(info.itemID, itemName(info.itemID)) end
    end
  end
end

--- Every name GoldCap already knows for an item, as add(itemID, name) -- an item may come more than
--- once, under one name or several: every stored list's lines (their own name and the client's),
--- the bags and the bank as far as the client has it, the item names the site asked about, the
--- ledger's purchases and sales, and what GoldCap recorded buying. The client resolves almost no
--- typed names itself (the BUY 2.0 probe: C_Item.GetItemInfoInstant answered 0 of 15 in retail).
function GC.BuyLists.KnownNames(add)
  local db = type(GC.db) == "table" and GC.db or {}
  for _, run in pairs(type(db.runs) == "table" and db.runs or {}) do
    for _, line in ipairs(type(run.lines) == "table" and run.lines or {}) do
      add(line.i, line.n)
      add(line.i, itemName(line.i))
    end
  end
  walkBags(BAGS, add)
  walkBags(bankBags(), add)
  for itemID, row in pairs(type(db.itemNames) == "table" and db.itemNames or {}) do
    if type(row) == "table" then add(itemID, row.n) end
  end
  for _, row in ipairs(type(db.ledger) == "table" and db.ledger or {}) do
    if type(row) == "table" then add(row.itemID, row.itemName) end
  end
  for _, batch in ipairs(type(db.acquisitions) == "table" and db.acquisitions or {}) do
    if type(batch) == "table" then add(batch.itemID, batch.itemName) end
  end
end

--- Turns a name into an item the way an import needs it: one item exactly, or nothing. The names
--- GoldCap already knows go first (KnownNames), and a name two items share is nobody's; then the
--- client's own C_Item.GetItemInfoInstant.
function GC.BuyLists.NameLookup()
  local index = GC.ListStrings.NameIndex()
  GC.BuyLists.KnownNames(function(itemID, name) index:Add(itemID, name) end)
  return function(name)
    local found = index:Find(name)
    if found ~= nil then return found end
    if C_Item and C_Item.GetItemInfoInstant then
      local ok, itemID = pcall(C_Item.GetItemInfoInstant, name)
      if ok and type(itemID) == "number" and itemID > 0 then return itemID end
    end
    return nil
  end
end

-- An id the client does not know is no item: it joins the names nobody could place.
local function knownLines(lines, unresolved)
  if not (C_Item and C_Item.GetItemInfoInstant) then return lines end
  local out = {}
  for _, line in ipairs(lines) do
    local ok, known = pcall(C_Item.GetItemInfoInstant, line.i)
    if ok and known then
      out[#out + 1] = line
    else
      unresolved[#unresolved + 1] = "i:" .. tostring(line.i)
    end
  end
  return out
end

local function namesText(names)
  local shown = {}
  for i = 1, math.min(#names, MAX_NAMES) do shown[i] = names[i] end
  local text = table.concat(shown, ", ")
  if #names > MAX_NAMES then text = (GC.L["%s and %d more"]):format(text, #names - MAX_NAMES) end
  return text
end

--- Imports a pasted list: a goldcap.gg run string (GCR1), a TSM string or an Auctionator list,
--- each list of it as a new list, or every item of it into `into` (one of the player's own lists).
--- Names are resolved with NameLookup; what could not be is named back, and the rest imported.
--- Returns nil and why (Core/ListStrings.lua's Parse) when the text is none of the three, else
--- { error = text } when nothing could be imported, or { code = <the list to show>, printed =
--- { chat lines }, missed = <a sentence, when names were left out> }.
function GC.BuyLists.ImportText(text, into)
  if type(text) ~= "string" then return nil, "empty" end
  local lists
  if text:match("^%s*GCR1;") then
    local run = GC.AppRuns.ParseRunString(text)
    if not run then return { error = GC.L["the run string is not valid"] } end
    if not into then
      -- A goldcap.gg run keeps its code and stays the site's paste, exactly as before.
      run = GC.AppRuns.ImportString(text)
      return { code = run.code,
        printed = { GC.L["run imported: %s (%d lines)"]:format(GC.AppRuns.Label(run), #run.lines) } }
    end
    lists = { { name = run.name, lines = run.lines, unresolved = {} } }
  else
    local parsed, why = GC.ListStrings.Parse(text)
    if not parsed then return nil, why end
    local lookup = GC.BuyLists.NameLookup()
    lists = {}
    for _, list in ipairs(parsed.lists) do
      local lines, unresolved = GC.ListStrings.Resolve(list.items, lookup)
      lists[#lists + 1] = { name = list.name, lines = knownLines(lines, unresolved), unresolved = unresolved }
    end
  end
  local printed, missed, first, added = {}, {}, nil, 0
  for _, list in ipairs(lists) do
    for _, name in ipairs(list.unresolved) do missed[#missed + 1] = name end
    if #list.lines > 0 then
      if into then
        local _, count = GC.AppRuns.AddLines(into, list.lines)
        added = added + (count or 0)
      else
        local run = GC.AppRuns.NewList(list.name, list.lines)
        first = first or run.code
        printed[#printed + 1] = (GC.L["Imported %s with %d items."]):format(GC.AppRuns.Label(run), #run.lines)
      end
    end
  end
  if into and added > 0 then
    first = into
    printed[#printed + 1] = (GC.L["Added %d items to %s."]):format(added, GC.AppRuns.Label(GC.AppRuns.Get(into)))
  end
  local missedText = #missed > 0
    and (GC.L["The game could not tell which items these are: %s. Shift-click them into the item box instead."])
      :format(namesText(missed)) or nil
  if not first then return { error = missedText or GC.L["There are no items in this list."] } end
  if missedText then printed[#printed + 1] = missedText end
  return { code = first, printed = printed, missed = missedText }
end

--- Why a paste is not a list, in words, for the import box.
function GC.BuyLists.NotAList(why)
  if why == "tsm_packed" then
    return GC.L["This is TSM's packed group export, which only TSM can unpack. Paste it into goldcap.gg/list, press Copy as TSM group there, and paste that here."]
  end
  return GC.L["This is not a list GoldCap can read. Paste a list from goldcap.gg, TSM or Auctionator."]
end

--- Everything that can be done to one list, into a MenuUtil menu (`root`): the picker's menu for
--- the list on screen, and a right-click on a list in the column. A goldcap.gg list is renamed,
--- removed and managed on goldcap.gg -- its next sync would undo any of it here -- so it gets
--- what stays in the game: favourite, order, export and archive.
function GC.BuyLists.FillActions(root, run)
  local menuText = GC.Util.ClientText
  local code = run.code
  local own = GC.AppRuns.IsLocal(run)
  local alert = run.k == "alert"
  local siteManaged = alert or (type(run.by) == "string" and run.by ~= "")
  if own then
    root:CreateButton(menuText(GC.L["Rename…"]), function() GC.BuyLists.Rename(code) end)
  end
  if not alert then
    local favourite = GC.AppRuns.IsFavourite(code)
    root:CreateButton(menuText(favourite and GC.L["Remove from favourites"] or GC.L["Add to favourites"]), function()
      GC.AppRuns.SetFavourite(code, not favourite)
      GC.Buy.RefreshIfShown()
    end)
    if GC.AppRuns.CanMove(code, -1) then
      root:CreateButton(menuText(GC.L["Move up"]), function()
        GC.AppRuns.Move(code, -1)
        GC.Buy.RefreshIfShown()
      end)
    end
    if GC.AppRuns.CanMove(code, 1) then
      root:CreateButton(menuText(GC.L["Move down"]), function()
        GC.AppRuns.Move(code, 1)
        GC.Buy.RefreshIfShown()
      end)
    end
  end
  -- Nothing to export but vendor stops is nothing to export (Export leaves them out).
  local exportable = false
  for _, line in ipairs(type(run.lines) == "table" and run.lines or {}) do
    if not line.v then exportable = true end
  end
  if exportable then
    -- MenuUtil's own submenu shape: an entry with entries added to it opens as one (the run cap's
    -- submenu in UI/BuyFrame.lua is built the same way).
    local export = root:CreateButton(menuText(GC.L["Export"]))
    if export and export.CreateButton then
      export:CreateButton(menuText(GC.L["Copy for Auctionator"]), function() GC.BuyLists.Export(code, "auctionator") end)
      export:CreateButton(menuText(GC.L["Copy as a TSM item list"]), function() GC.BuyLists.Export(code, "tsm") end)
    end
  end
  if own then
    root:CreateButton(menuText(GC.L["Import into this list…"]), function() GC.BuyLists.Import(code) end)
  end
  if siteManaged then
    root:CreateTitle(menuText(GC.L["From goldcap.gg — manage it there"]))
    return
  end
  if not held(code) then
    root:CreateButton(menuText(GC.L["Archive this run"]), function() GC.BuyLists.Archive(code) end)
    if own then
      root:CreateButton(menuText(GC.L["Delete this list…"]), function() GC.BuyLists.Delete(code) end)
    end
  end
  if not own then root:CreateTitle(menuText(GC.L["From goldcap.gg — rename or remove it there"])) end
end

--- A right-click on a list in the column: its name, then what can be done to it.
function GC.BuyLists.OpenMenu(owner, code)
  local menu = _G.MenuUtil
  local run = GC.AppRuns.Get(code)
  if not (run and menu and menu.CreateContextMenu) then return false end
  menu.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(GC.Util.ClientText(GC.AppRuns.Label(run)))
    GC.BuyLists.FillActions(root, run)
  end)
  return true
end
