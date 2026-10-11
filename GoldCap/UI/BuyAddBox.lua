local _, GC = ...

-- The BUY tab's one box (BUY 2.0): at the top of the tab, over the list -- on every list, and on the
-- empty first-time state -- a well to type or shift-click into, and a button beside it that does
-- what Enter does with what is there:
--
--   * links and item ids, several at once (Core/BuyView.lua's ParseAddMany: commas, semicolons or
--     line breaks between them, each with an optional x<count>) -- "Add". Each shift-click is
--     appended after what is there (GC.Buy._WatchLinks), and the line under the well says what
--     Enter will add and which entries it cannot read.
--   * a name -- "Search": the items GoldCap already knows by a name like it (UI/BuyLists.lua's
--     KnownNames: the bags and the bank, every list, the ledger, what GoldCap bought, the names the
--     site asked about), compared case- and accent-blind in the client's language
--     (Core/NameMatch.lua). A click on one, or the arrow keys and Enter, adds it. The client itself
--     places almost no typed names (the BUY 2.0 probe: C_Item.GetItemInfoInstant answered 0 of 15 in
--     retail), so nothing is guessed. With the auction house open, Enter searches what is on sale
--     instead (UI/BuySearch.lua); without it, the line under the well says to open it.
--
-- Under it, the last searches and items added (Core/BuyRecents.lua), as chips: an item's adds it
-- again, a search's runs it again.
--
-- An item goes onto the player's own list on screen; with a goldcap.gg list on screen, or none,
-- onto a new list made in the game -- the site's lists are edited on the site, and the next sync
-- would drop it. Its own file: UI/BuyFrame.lua is near its ceiling of top-level locals
-- (docs/addon/AGENTS.md, "Hard limits"). UI/BuyFrame.lua places it (layoutBand) and reaches it as
-- GC.Buy._view.add.
GC.BuyAddBox = {}

local AB = {
  WELL_H = 22,
  BUTTON_MIN_W = 72,
  GAP = 4,
  -- The items a name offers, best first. A match's least height; a long name wraps and grows it.
  MAX_MATCHES = 6,
  MATCH_H = 20,
  CHIP_H = 18,
  CHIP_MIN_W = 24,
  -- A name is looked up as it is typed from two bytes on: one Latin letter offers too much to
  -- read, one Cyrillic letter is two bytes already, one Chinese or Korean one three.
  MIN_QUERY_BYTES = 2,
}

local function setColor(fs, c)
  if fs and c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

local function measure(fs)
  local width = fs and fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  return type(width) == "number" and width or nil
end

local function itemName(itemID)
  if C_Item and C_Item.GetItemInfo then
    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return nil
end

-- What an entry the player gave reads as on screen: a link's name, without its codes.
local function plainText(text)
  return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
    :gsub("|H.-|h%[?(.-)%]?|h", "%1"))
end

-- An item by the client's name for it, else the name its link carried, else its id.
local function nameOf(item)
  return itemName(item.itemID) or (type(item.text) == "string" and item.text:match("|h%[(.-)%]|h"))
    or tostring(item.itemID)
end

local function ahOpen()
  return GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen() or false
end

local function relayout()
  if GC.Buy._LayoutTop then GC.Buy._LayoutTop() end
end

local function recents()
  local db = GC.db
  return type(db) == "table" and type(db.buyRecents) == "table" and db.buyRecents or {}
end

local function remember(entry)
  if type(GC.db) == "table" then GC.db.buyRecents = GC.BuyRecents.Push(GC.db.buyRecents, entry) end
end

-- The names GoldCap knows, folded once per time the box is in use (forgotten by stop).
local function known(bar)
  if bar.known then return bar.known end
  local list, seen = {}, {}
  if GC.BuyLists and GC.BuyLists.KnownNames then
    GC.BuyLists.KnownNames(function(itemID, name)
      if type(itemID) ~= "number" or itemID <= 0 or type(name) ~= "string" or name == "" then return end
      local key = itemID .. "\0" .. name
      if seen[key] then return end
      seen[key] = true
      list[#list + 1] = { itemID = itemID, name = name, folded = GC.NameMatch.Fold(name) }
    end)
  end
  bar.known = list
  return list
end

-- The box is no longer the one being filled: Enter, Escape, or the tab going away.
local function stop(bar)
  bar.collecting = false
  bar.known, bar.lookup = nil, nil
  bar.selected = 0
end

-- The entries as items the client knows ({ itemID, qty, text }, one per item, in order, the counts
-- of a repeated item added up) and what could not be read. A name among several entries is placed
-- only exactly (UI/BuyLists.lua's NameLookup, the import's), and an id the client does not know is
-- no item.
local function resolve(bar, entries)
  local items, missed, byItem = {}, {}, {}
  for _, entry in ipairs(entries or {}) do
    local id = entry.itemID
    if not id and entry.name and GC.BuyLists and GC.BuyLists.NameLookup then
      bar.lookup = bar.lookup or GC.BuyLists.NameLookup()
      local found = bar.lookup(entry.name)
      if type(found) == "number" and found > 0 then id = found end
    end
    if id and C_Item and C_Item.GetItemInfoInstant then
      local ok, isKnown = pcall(C_Item.GetItemInfoInstant, id)
      if not (ok and isKnown) then id = nil end
    end
    if id and byItem[id] then
      byItem[id].qty = byItem[id].qty + (entry.qty or 1)
    elseif id then
      byItem[id] = { itemID = id, qty = entry.qty or 1, text = entry.text }
      items[#items + 1] = byItem[id]
    else
      missed[#missed + 1] = plainText(entry.text)
    end
  end
  return items, missed
end

-- What the text in the box is: nil (nothing), "add" (items, bar.items and bar.missed) or "search"
-- (one name, bar.query and bar.qty, and what it matches in bar.found).
local function read(bar)
  local entries = GC.BuyView.ParseAddMany(bar.box:GetText() or "")
  bar.items, bar.missed, bar.query, bar.qty = nil, nil, nil, 1
  bar.mode, bar.found = nil, {}
  if entries and #entries == 1 and entries[1].name then
    bar.mode, bar.query, bar.qty = "search", entries[1].name, entries[1].qty or 1
    if #GC.NameMatch.Fold(bar.query) >= AB.MIN_QUERY_BYTES then
      bar.found = GC.NameMatch.Find(known(bar), bar.query, AB.MAX_MATCHES)
    end
  elseif entries then
    bar.mode = "add"
    bar.items, bar.missed = resolve(bar, entries)
  end
  if (bar.selected or 0) > #bar.found then bar.selected = 0 end
end


local function matchRow(bar, i)
  local row = bar.matches[i]
  if row then return row end
  local Theme = GC.Theme
  row = CreateFrame("Button", nil, bar.frame)
  row:SetHeight(AB.MATCH_H)
  row:RegisterForClicks("LeftButtonUp")
  -- Hover is the engine's HIGHLIGHT layer on a mouse-enabled frame (the BUY rows' own), the arrow
  -- keys' pick a gold wash shown and hidden, never an alpha.
  row:EnableMouse(true)
  local hc, gc = Theme.color.hover, Theme.color.gold
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture(Theme.MEDIA .. "plaque.png")
  highlight:SetTextureSliceMargins(12, 12, 12, 12)
  highlight:SetAllPoints()
  highlight:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 0.08)
  local picked = row:CreateTexture(nil, "BORDER")
  picked:SetTexture(Theme.MEDIA .. "plaque.png")
  picked:SetTextureSliceMargins(12, 12, 12, 12)
  picked:SetAllPoints()
  picked:SetVertexColor(gc[1], gc[2], gc[3], 0.14)
  picked:Hide()
  row.picked = picked
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.text = Theme.Label(row, 11)
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(true)
  row.text:SetPoint("LEFT", row, "LEFT", 26, 0)
  row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row:SetScript("OnClick", function(self) GC.BuyAddBox.Pick(bar, self.index) end)
  bar.matches[i] = row
  return row
end

local function chipFor(bar, i)
  local chip = bar.chips[i]
  if chip then return chip end
  chip = GC.Theme.Button(bar.frame, "ghost", "badge")
  chip:SetHeight(AB.CHIP_H)
  chip:SetScript("OnClick", function(self) GC.BuyAddBox.UseRecent(bar, self.recent) end)
  bar.chips[i] = chip
  return chip
end

-- A chip as wide as its label; one longer than the row takes the row and wraps its label rather
-- than cut it. Returns its width and height.
local function fitChip(chip, maxW)
  local w = math.max(AB.CHIP_MIN_W, math.ceil((measure(chip.text) or 40) + 2 * GC.Theme.pad.s))
  if maxW <= 0 or w <= maxW then
    chip.text:SetWordWrap(false)
    chip.text:SetMaxLines(1)
    chip:SetSize(w, AB.CHIP_H)
    return w, AB.CHIP_H
  end
  chip.text:SetWordWrap(true)
  chip.text:SetMaxLines(0)
  chip:SetWidth(maxW)
  local h = math.max(AB.CHIP_H, math.ceil((chip.text:GetStringHeight() or 12) + 6))
  chip:SetHeight(h)
  return maxW, h
end

local function chipLabel(entry)
  if entry.i then
    local label = GC.Theme.WithQuality(itemName(entry.i) or entry.n or tostring(entry.i), entry.i)
    if (entry.q or 1) > 1 then label = ("%s ×%d"):format(label, entry.q) end
    return label
  end
  return "“" .. entry.s .. "”"
end

-- Everything the bar says for its state; GC.BuyAddBox.Layout places it.
local function paint(bar)
  local Theme = GC.Theme
  local box = bar.box
  local text = box:GetText() or ""
  local focused = box.HasFocus and box:HasFocus() or false
  if text ~= "" or focused then bar.hint:Hide() else bar.hint:Show() end
  -- The button says what Enter does: a name searches, unless the arrow keys picked a match.
  local searching = bar.mode == "search" and (bar.selected or 0) == 0
  bar.button:SetLabel(searching and GC.L["Search"] or GC.L["Add"])
  if bar.mode then bar.button:Enable() else bar.button:Disable() end

  if bar.mode == "add" then
    local parts = {}
    for _, item in ipairs(bar.items or {}) do
      parts[#parts + 1] = item.qty > 1 and ("%s ×%d"):format(nameOf(item), item.qty) or nameOf(item)
    end
    local line = #parts > 0 and (GC.L["Items to add: %d (%s)"]):format(#parts, table.concat(parts, ", ")) or ""
    if #(bar.missed or {}) > 0 then
      local missed = (GC.L["Could not read: %s."]):format(table.concat(bar.missed, ", "))
      line = line ~= "" and (line .. "\n" .. missed) or missed
    end
    bar.collected:SetText(line)
    setColor(bar.collected, Theme.color.fg)
    bar.collected:Show()
  else
    bar.collected:SetText("")
    bar.collected:Hide()
  end

  local found = bar.found or {}
  for i, entry in ipairs(found) do
    local row = matchRow(bar, i)
    row.index, row.itemID = i, entry.itemID
    local icon
    if C_Item and C_Item.GetItemIconByID then
      local ok, texture = pcall(C_Item.GetItemIconByID, entry.itemID)
      icon = ok and texture or nil
    end
    if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
    row.text:SetText(Theme.WithQuality(itemName(entry.itemID) or entry.name, entry.itemID, 12))
    if i == bar.selected then row.picked:Show() else row.picked:Hide() end
    row:Show()
  end
  for i = #found + 1, #bar.matches do bar.matches[i]:Hide() end

  local note
  if bar.feedback then
    note = bar.feedback
  elseif bar.mode == "search" and not ahOpen()
      and (bar.searched or #GC.NameMatch.Fold(bar.query) >= AB.MIN_QUERY_BYTES) then
    -- Without the auction house a name is looked for only among the items GoldCap knows (the rows
    -- above, if any). With it open, Enter searches what is on sale (UI/BuySearch.lua) and says so
    -- there.
    note = GC.L["Open the auction house to search what's on sale."]
  elseif not bar.mode and (focused or bar.collecting or not (GC.Buy.CurrentRun and GC.Buy.CurrentRun())) then
    note = GC.L["Shift-click items, type a name, or an item id with x and a count: 2589 x20."]
  end
  bar.note:SetText(note or "")
  if note then bar.note:Show() else bar.note:Hide() end

  local list = recents()
  for i, entry in ipairs(list) do
    local chip = chipFor(bar, i)
    chip.recent = entry
    chip:SetLabel(chipLabel(entry))
    chip:Show()
  end
  for i = #list + 1, #bar.chips do bar.chips[i]:Hide() end
  if #list > 0 then
    bar.recentCaption:Show()
    bar.clear:Show()
  else
    bar.recentCaption:Hide()
    bar.clear:Hide()
  end
end

--- Reads the box again and redraws the bar, and the tab under it moves with its height.
function GC.BuyAddBox.Update(bar)
  read(bar)
  paint(bar)
  relayout()
end

--- The bar's geometry at `width` (the tab's right-hand pane): the well and its button, then -- each
--- wrapping, never cut -- what Enter will add, the matches, the note, and the recent chips, which
--- flow onto as many rows as they need. Returns its height.
function GC.BuyAddBox.Layout(bar, width)
  local Theme = GC.Theme
  width = math.max(0, width or 0)
  local frame = bar.frame
  local y = -AB.GAP
  local labelW = measure(bar.button.text)
  bar.button:SetWidth(math.max(AB.BUTTON_MIN_W, labelW and math.ceil(labelW + 2 * Theme.pad.m) or 0))
  bar.button:ClearAllPoints()
  bar.button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, y)
  bar.well:ClearAllPoints()
  bar.well:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
  bar.well:SetPoint("RIGHT", bar.button, "LEFT", -Theme.pad.s, 0)
  y = y - AB.WELL_H
  local textW = math.max(0, width - 8)
  local function place(fs)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, y - AB.GAP)
    fs:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    if textW > 0 then fs:SetWidth(textW) end
    y = y - AB.GAP - math.ceil(fs:GetStringHeight() or 12)
  end
  if bar.collected:IsShown() then place(bar.collected) end
  local first = true
  for _, row in ipairs(bar.matches) do
    if row:IsShown() then
      if textW > 30 then row.text:SetWidth(textW - 30) end
      local h = math.max(AB.MATCH_H, math.ceil((row.text:GetStringHeight() or 12) + 6))
      row:SetHeight(h)
      local top = y - (first and AB.GAP or 0)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, top)
      row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, top)
      y, first = top - h, false
    end
  end
  if bar.note:IsShown() then place(bar.note) end
  if bar.recentCaption:IsShown() then
    y = y - AB.GAP
    local x, lineH = 0, AB.CHIP_H
    local function flow(region, w, h)
      if x > 0 and width > 0 and x + w > width then
        y, x, lineH = y - lineH - AB.GAP, 0, AB.CHIP_H
      end
      region:ClearAllPoints()
      region:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
      x, lineH = x + w + Theme.pad.xs, math.max(lineH, h)
    end
    local captionW = math.ceil(measure(bar.recentCaption) or 48)
    bar.recentCaption:SetSize(captionW, AB.CHIP_H)
    flow(bar.recentCaption, captionW, AB.CHIP_H)
    for _, chip in ipairs(bar.chips) do
      if chip:IsShown() then flow(chip, fitChip(chip, width)) end
    end
    flow(bar.clear, fitChip(bar.clear, width))
    y = y - lineH
  end
  local h = math.ceil(-y + AB.GAP + 2)
  frame:SetHeight(h)
  bar.h = h
  return h
end

--- Puts items onto the list Enter adds to (see the header) and says what it did, naming what could
--- not be read. `items` are { itemID, qty }. Returns true when anything was added.
function GC.BuyAddBox.AddItems(bar, items, missed)
  missed = missed or {}
  if #items == 0 then
    bar.feedback = #missed > 1 and (GC.L["Could not read: %s."]):format(table.concat(missed, ", "))
      or GC.L["Could not find that item. Shift-click it, or type its item id."]
    paint(bar)
    relayout()
    return false
  end
  local run = GC.Buy.CurrentRun and GC.Buy.CurrentRun()
  local stored = run and GC.AppRuns.Get(run:Code()) or nil
  local own = type(stored) == "table" and (stored.origin == "game" or stored.origin == "paste")
  local made = not own and GC.AppRuns.NewList() or nil
  local code = own and stored.code or (made and made.code)
  local lines = {}
  for i, item in ipairs(items) do lines[i] = { i = item.itemID, q = item.qty or 1 } end
  if not (code and GC.AppRuns.AddLines(code, lines)) then return false end
  for _, item in ipairs(items) do remember({ i = item.itemID, q = item.qty or 1, n = itemName(item.itemID) }) end
  local label = GC.AppRuns.Label(GC.AppRuns.Get(code))
  local said
  if #items == 1 then
    said = (made and GC.L["Added %d× %s to a new list, %s."] or GC.L["Added %d× %s to %s."])
      :format(items[1].qty or 1, nameOf(items[1]), label)
  else
    said = (made and GC.L["Added %d items to a new list, %s."] or GC.L["Added %d items to %s."]):format(#items, label)
  end
  if #missed > 0 then said = said .. " " .. (GC.L["Could not read: %s."]):format(table.concat(missed, ", ")) end
  bar.feedback = said
  stop(bar)
  bar.box:SetText("")
  bar.box:ClearFocus()
  read(bar)
  GC.Buy.SelectRun(code)
  GC.Buy.RefreshIfShown()
  return true
end

--- Redraws the bar for what is around it now: the list on screen (the first-time hint), the recents.
--- UI/BuyFrame.lua's render calls it; the bar's own changes repaint it themselves.
function GC.BuyAddBox.Paint(bar)
  if bar then paint(bar) end
end

--- Enter, or the button: the match the arrow keys picked, the items in the box, or a search for the
--- name in it.
function GC.BuyAddBox.Submit(bar)
  read(bar)
  if bar.mode == "search" then
    local pick = (bar.selected or 0) > 0 and bar.found[bar.selected] or nil
    if pick then return GC.BuyAddBox.AddItems(bar, { { itemID = pick.itemID, qty = bar.qty } }) end
    return GC.Buy._SearchSubmit(bar.query, bar.qty)
  end
  if bar.mode == "add" then return GC.BuyAddBox.AddItems(bar, bar.items, bar.missed) end
  return false
end

--- A click on a match adds it, with the count typed beside the name.
function GC.BuyAddBox.Pick(bar, index)
  local entry = bar.found and bar.found[index]
  if not entry then return false end
  return GC.BuyAddBox.AddItems(bar, { { itemID = entry.itemID, qty = bar.qty or 1 } })
end

--- The arrow keys walk the matches (round), and Enter then adds the one picked.
function GC.BuyAddBox.Arrow(bar, key)
  local n = #(bar.found or {})
  if n == 0 then return end
  local at = bar.selected or 0
  if key == "DOWN" then
    at = at % n + 1
  elseif key == "UP" then
    at = at <= 1 and n or at - 1
  else
    return
  end
  bar.selected = at
  paint(bar)
end

--- A recent chip: an item is added again, to where the box adds; a search runs again.
function GC.BuyAddBox.UseRecent(bar, entry)
  if type(entry) ~= "table" then return false end
  if entry.i then return GC.BuyAddBox.AddItems(bar, { { itemID = entry.i, qty = entry.q or 1 } }) end
  if type(entry.s) ~= "string" then return false end
  bar.feedback = nil
  bar.box:SetText(entry.s)
  bar.box:SetFocus()
  bar.collecting = true
  read(bar)
  return GC.Buy._SearchSubmit(entry.s, 1)
end

--- Puts `found` ({ itemID, name }) up as the matches to pick from. The auction house's own search
--- (next) answers into the same rows.
function GC.BuyAddBox.SetMatches(found)
  local bar = GC.Buy._view and GC.Buy._view.add
  if not bar then return end
  bar.found, bar.selected, bar.searched = found or {}, 0, true
  paint(bar)
  relayout()
end

--- The one way a name is searched: Enter or the button on a name, and a search chip. Remembered
--- among the recents. The auction house's own search plugs in here: GC.BuySearch.Submit(query, qty),
--- when it exists, answers true when it took the search (only while the auction house is open), and
--- GoldCap's own matches stand otherwise -- the ones the client and GoldCap already know.
function GC.Buy._SearchSubmit(query, qty)
  if type(query) ~= "string" or not query:match("%S") then return false end
  query = query:match("^%s*(.-)%s*$")
  remember({ s = query })
  local bar = GC.Buy._view and GC.Buy._view.add
  if GC.BuySearch and GC.BuySearch.Submit and GC.BuySearch.Submit(query, qty or 1) then
    if bar then
      -- What is on sale answers now: GoldCap's own matches give way to it.
      bar.found, bar.selected, bar.searched = {}, 0, true
      paint(bar)
      relayout()
    end
    return true
  end
  if not bar then return false end
  bar.found, bar.selected, bar.searched = GC.NameMatch.Find(known(bar), query, AB.MAX_MATCHES), 0, true
  paint(bar)
  relayout()
  return true
end

--- A shift-click of an item while the box is the one being filled: the link goes after what is there
--- (Core/BuyView.lua's AppendLink), the cursor to the end. The box is being filled from the moment
--- it takes the focus until Enter, Escape or the tab goes away -- a click on a bag may move the
--- client's focus, and the next shift-click still belongs here. Never a link the player is putting
--- into chat (ChatFrameUtil.GetActiveWindow: the open chat box Blizzard's InsertLink just gave it to)
--- or into another box that has the keyboard now (a macro, the auction house's own search).
--- Answers whether it took the link.
function GC.BuyAddBox.TakeLink(text)
  local bar = GC.Buy._view and GC.Buy._view.add
  if not (bar and type(text) == "string" and text:find("|Hitem:", 1, true)) then return false end
  local box = bar.box
  local focused = box.HasFocus and box:HasFocus() or false
  if not (focused or bar.collecting) then return false end
  local chat = _G.ChatFrameUtil
  if chat and chat.GetActiveWindow and chat.GetActiveWindow() then return false end
  local keyboard = _G.GetCurrentKeyBoardFocus and _G.GetCurrentKeyBoardFocus() or nil
  if keyboard and keyboard ~= box then return false end
  local new = GC.BuyView.AppendLink(box:GetText() or "", text)
  box:SetText(new)
  if box.SetCursorPosition then box:SetCursorPosition(#new) end
  GC.BuyAddBox.Update(bar)
  return true
end

-- A post-hook on Blizzard's ChatFrameUtil.InsertLink (the same function in live and forever), where
-- every shift-click of an item ends: it sees what InsertLink was handed and changes nothing that
-- function did -- which, with the auction house open, also fills Blizzard's own search box.
function GC.Buy._WatchLinks()
  if GC.Buy._watchingLinks or not (hooksecurefunc and _G.ChatFrameUtil
      and type(_G.ChatFrameUtil.InsertLink) == "function") then return end
  GC.Buy._watchingLinks = true
  hooksecurefunc(_G.ChatFrameUtil, "InsertLink", function(text) GC.BuyAddBox.TakeLink(text) end)
end

--- Builds the bar, hidden from nothing: UI/BuyFrame.lua's Attach makes it once, over the tab.
function GC.BuyAddBox.Create(parent)
  local Theme = GC.Theme
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetHeight(AB.WELL_H + 2 * AB.GAP)
  local well = CreateFrame("Frame", nil, frame)
  well:SetHeight(AB.WELL_H)
  local wc = Theme.color.bg or Theme.color.panel
  Theme.SlicedTexture(well, "BACKGROUND", Theme.MEDIA .. "plaque.png", { wc[1], wc[2], wc[3], 1 }, 12):SetAllPoints(well)
  Theme.SlicedTexture(well, "BORDER", Theme.MEDIA .. "plaque_ring.png", { 1, 1, 1, 0.12 }, 12):SetAllPoints(well)
  local box = CreateFrame("EditBox", nil, well)
  box:SetAutoFocus(false)
  box:SetPoint("TOPLEFT", 10, -2)
  box:SetPoint("BOTTOMRIGHT", -8, 2)
  -- Guarded for busted; in the client a bare EditBox with no font draws no text at all.
  if box.SetFont then
    box:SetFont(Theme.FONT_UI, 11 * Theme.Scale(), "")
    box:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
  end
  -- Up and Down without Alt reach OnArrowPressed, as Blizzard's own completion lists use them.
  if box.SetAltArrowKeyMode then box:SetAltArrowKeyMode(false) end
  local hint = Theme.Num(well, 10)
  hint:SetJustifyH("LEFT")
  hint:SetPoint("LEFT", well, "LEFT", 10, 0)
  hint:SetPoint("RIGHT", well, "RIGHT", -8, 0)
  hint:SetWordWrap(false)
  hint:SetText(GC.L["Item to add"])
  setColor(hint, Theme.color.fgDim)
  local button = Theme.Button(frame, "ghost", "plaque")
  button:SetSize(AB.BUTTON_MIN_W, AB.WELL_H)
  local collected = Theme.Num(frame, 10)
  collected:SetJustifyH("LEFT")
  collected:SetWordWrap(true)
  collected:Hide()
  local note = Theme.Num(frame, 10)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  setColor(note, Theme.color.fgDim)
  note:Hide()
  local recentCaption = Theme.Num(frame, 9)
  recentCaption:SetJustifyH("LEFT")
  recentCaption:SetWordWrap(false)
  recentCaption:SetText(GC.L["Recent:"])
  setColor(recentCaption, Theme.color.fgDim)
  recentCaption:Hide()
  local clear = Theme.Button(frame, "ghost", "badge")
  clear:SetHeight(AB.CHIP_H)
  clear:SetLabel(GC.L["Clear"])
  clear:Hide()

  local bar = { frame = frame, well = well, box = box, hint = hint, button = button, collected = collected,
    note = note, recentCaption = recentCaption, clear = clear, matches = {}, chips = {}, found = {},
    selected = 0, h = AB.WELL_H + 2 * AB.GAP }

  box:SetScript("OnTextChanged", function(self)
    -- What the last Enter did stays said until something new goes in.
    if (self:GetText() or "") ~= "" then bar.feedback, bar.searched = nil, nil end
    GC.BuyAddBox.Update(bar)
  end)
  box:SetScript("OnEditFocusGained", function()
    bar.collecting = true
    paint(bar)
    relayout()
  end)
  box:SetScript("OnEditFocusLost", function()
    paint(bar)
    relayout()
  end)
  box:SetScript("OnEnterPressed", function(self)
    if GC.BuyAddBox.Submit(bar) or (self:GetText() or ""):match("%S") then return end
    -- Enter on an empty box is done with it, as in chat.
    stop(bar)
    self:ClearFocus()
    paint(bar)
  end)
  box:SetScript("OnArrowPressed", function(_, key) GC.BuyAddBox.Arrow(bar, key) end)
  box:SetScript("OnEscapePressed", function(self)
    stop(bar)
    bar.feedback = nil
    self:SetText("")
    self:ClearFocus()
    GC.BuyAddBox.Update(bar)
  end)
  button:SetScript("OnClick", function() GC.BuyAddBox.Submit(bar) end)
  clear:SetScript("OnClick", function()
    if type(GC.db) == "table" then GC.db.buyRecents = {} end
    paint(bar)
    relayout()
  end)
  -- The tab put away (another tab, or the window closed): the box is no longer being filled.
  frame:SetScript("OnHide", function() stop(bar) end)
  GC.Buy._WatchLinks()

  read(bar)
  paint(bar)
  return bar
end
