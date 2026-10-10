-- The Sell list: the deck on screen, row by row. List.RenderRows builds the entries for the deck --
-- its MY LOTS sections, the NOT ON HAND fold, the stock waiting for the auction house, and for the
-- open position the inspector's lines -- binds each to a pooled row (UI/Sell/Row.lua) and places it
-- in the list or in the inspector. Also the columns and their headings, each sized to fit its
-- words in every language. Moved from UI/SellFrame.lua as it was.
local _, GC = ...

local Theme = GC.Theme
local S = GC.SellState
local Bags, Walk = GC.SellBags, GC.SellWalk
local exact, itemName = GC.SellUtil.exact, GC.SellUtil.itemName
local UI = GC.SellUI
local List = UI.List
local COLUMNS, ROW, DR, INSP = UI.COLUMNS, UI.ROW, UI.DR, UI.INSP
local setColor, DIM_HEX = UI.fmt.setColor, UI.fmt.DIM_HEX
local renderGeneration = 0

-- Why the deck is empty, in the five ways the owner approved (3C mockup, 2026-10-10): the icon
-- for its tile, a title, and a line saying what to do about it. Each reason needs a different next
-- move: a deck that is genuinely empty, a chip or a search that emptied it, the other deck holding
-- everything. Read live from the deck and chip state rather than passed in, so it can never
-- disagree with what the switch is painting.
-- A GC.Sell field, not a top-level local: paint-only, same reason as _FormatAmount
-- (UI/Sell/Frame.lua) (final review "Headroom").
function GC.Sell._EmptyDeck()
  if UI.chips.search then
    return "search", GC.L["No match"],
      GC.L["Nothing on this deck matches that search. Clear the box to see everything."]
  end
  if S.filterMode == "listed" or S.filterMode == "cancelqueue" then
    return "sell", GC.L["No auctions up"],
      GC.L["No live auctions on this character. What you post shows up here, with what to cancel and what to leave."]
  end
  if UI.chips.ready then
    return "clock", GC.L["Still pricing"],
      GC.L["The auction house is still answering. Items show up here as their prices arrive."]
  end
  if UI.chips.nocost then
    return "check", GC.L["Every cost is known"],
      GC.L["Every item in your bags already has what you paid on record. Turn off NO COST to see them all."]
  end
  return "bag", GC.L["Nothing to sell"],
    GC.L["Nothing in your bags to list. Buy on the Deals tab or pick up your mail: anything you can sell shows up here with a price ready."]
end

local function currentPosition(positionKey)
  for _, position in ipairs(S.positions) do
    if position.positionKey == positionKey then return position end
  end
  return nil
end

-- A row posted whole goes (owner, 2026-10-11: it stayed on as "posted" until the bags caught up,
-- unmarked, moving, and then went with a jump). It fades where it stands, then the rows under it
-- close up over its gap, in a third of a second, by their anchors (UI.List.Leave starts it), and
-- it stays off the posting deck for as long as the bags still count what went up.
do
  local FADE, CLOSE = 0.15, 0.18
  local leaving -- { key, t, gone, gapY, gapH }
  local function rowOf(key)
    for _, row in ipairs(UI.rows or {}) do
      if row:IsShown() and row.kind == "position" and not row.inPanel and row.position
          and row.position.positionKey == key then return row end
    end
  end
  -- A list row `extra` px below the place renderRows gave it.
  local function anchor(row, extra)
    local y = -(row.placedY + extra)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row.surface, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", row.surface, "TOPRIGHT", 0, y)
  end
  local function shift(extra)
    for _, row in ipairs(UI.rows or {}) do
      if row:IsShown() and not row.inPanel and row.placedY and row.surface and row.placedY >= leaving.gapY then
        anchor(row, extra)
      end
    end
  end
  local function finish()
    List.leaveDriver:SetScript("OnUpdate", nil)
    local was = leaving
    if was.gone and was.gapY then shift(0) end
    leaving = nil
    if not was.gone then List.RenderRows() end
  end
  local function step(_, elapsed)
    leaving.t = leaving.t + (elapsed or 0)
    if not leaving.gone then
      local row = rowOf(leaving.key)
      if row and leaving.t < FADE then
        if row.SetAlpha then row:SetAlpha(1 - leaving.t / FADE) end
        return
      end
      -- Faded: out of the list, and the rows under it start where they stood.
      leaving.gone, leaving.t = true, 0
      leaving.gapY, leaving.gapH = row and row.placedY, row and row:GetHeight()
      List.RenderRows()
      if not (leaving.gapY and leaving.gapH) then finish() return end
    end
    local p = math.min(1, leaving.t / CLOSE)
    shift(leaving.gapH * (1 - p) * (1 - p)) -- quick at first, settling at the end
    if p >= 1 then finish() end
  end

  -- Starts the row's going. Nothing to watch -- the tab not on screen, the row not drawn -- and it
  -- simply goes with the next render.
  function List.Leave(key)
    if leaving then finish() end
    local container = UI.container
    if not (List.leaveDriver and container and container.IsVisible and container:IsVisible()
        and rowOf(key)) then return end
    leaving = { key = key, t = 0 }
    List.leaveDriver:SetScript("OnUpdate", step)
  end

  -- The posting deck less what went up whole, the row still fading kept on until it has.
  function List.DropPostedOut(filtered)
    for key, qty in pairs(S.postedOut) do
      local position = currentPosition(key)
      if not position or (position.bagQty or 0) ~= qty then S.postedOut[key] = nil end
    end
    if next(S.postedOut) == nil then return filtered end
    local kept = {}
    for _, position in ipairs(filtered) do
      local key = position.positionKey
      if not (key and S.postedOut[key]) or (leaving and leaving.key == key and not leaving.gone) then
        kept[#kept + 1] = position
      end
    end
    return kept
  end
end

-- The item name is the one column that must stay readable: every other cell is a number that
-- also lives in the tooltip or the expansion, but a row whose name is "Aze..." is useless.
-- `min` on the flex column was declared and never honoured, so the name silently collapsed to
-- nothing as soon as the fixed columns outgrew the window. Shed load-bearing weight in order
-- instead: the listed total (already in the summary), then squeeze the advice text, then drop
-- it entirely (the action button carries the same guidance on its tooltip), and only then the
-- cost per unit (which the expansion spells out per purchase).
-- 160, was 200. The name has its own truncation and a tooltip carrying it in full; COST/UNIT
-- has neither, and at 200 the name's floor was what pushed it off the screen.
local ITEM_MIN = 160
local STATUS_MIN = 110
local columnWidth = {}

-- Which columns each deck lays out. Not cosmetics: one column set had to serve both jobs at
-- once, which is what made it eight columns wide, which is what made the shedding order reach
-- load-bearing numbers at the DEFAULT window. At 720x600 the old set dropped LISTED and then
-- COST / UNIT by arithmetic, not by bad luck -- the column this whole tab exists to answer was
-- off screen for every player who never resized. Splitting by deck is what buys the room back.
local DECK_COLUMNS = {
  post = { item = true, price = true, gross = true, action = true },
  -- No cost/profit on a live lot: what a listed row is asked is "what did I list at, and who
  -- is under me". Its cost basis has not changed since it was posted and is one click away in
  -- the expansion. "Who is under me" is the line under YOUR PRICE now, in units, which is the
  -- half of that question the old UNDER YOU column (a bare price) never answered.
  listed = { item = true, price = true, listed = true, action = true },
}
-- What a deck gives up once squeezing every minimum still does not fit, in order.
--
-- Nothing, on either deck, since each is down to two figures and the button: at the narrowest
-- window the item name still clears ITEM_MIN with both at their minimum. The table stays so
-- that the next column anybody adds has to say where it goes when the room runs out.
local DECK_SHED = {
  post = {},
  listed = {},
}

-- Content-sized figure columns. FIT.need (below) answers how wide a
-- column must be to print its longest heading and second line in full in the active language
-- and font scale; shownColumns never makes a column narrower than that.
local FIT = {}

local function shownColumns()
  local width = INSP.listWidth()
  local deck = (S.filterMode == "listed" or S.filterMode == "cancelqueue") and "listed" or "post"
  local inDeck = DECK_COLUMNS[deck]
  local dropped = {}
  columnWidth = {}
  -- A column this deck does not carry is DROPPED, not merely absent from `shown`: layoutCells
  -- hides exactly what `dropped` names, and a pooled row that drew the column on the other deck
  -- last render would otherwise keep painting it here forever.
  for _, column in ipairs(COLUMNS) do
    if not inDeck[column.key] then dropped[column.key] = true end
  end

  -- A translation longer than the column's design width widens the column rather than being cut:
  -- the flexible ITEM column gives up the difference.
  for _, column in ipairs(COLUMNS) do
    if not column.flex and not dropped[column.key] then
      local need = FIT.need(column.key, deck)
      if need > column.w then columnWidth[column.key] = need end
    end
  end

  local function remaining()
    local total = 0
    for _, column in ipairs(COLUMNS) do
      if not column.flex and not dropped[column.key] then
        total = total + (columnWidth[column.key] or column.w) + 2
      end
    end
    return width - total
  end

  if width > 0 then
    -- Squeeze everything that has a floor before giving anything up. Every minimum here was
    -- measured against a real string at Theme.Scale() 1.3, not guessed.
    if remaining() < ITEM_MIN then columnWidth.status = STATUS_MIN end
    if remaining() < ITEM_MIN then
      for _, column in ipairs(COLUMNS) do
        if column.min then
          columnWidth[column.key] = math.max(column.min, FIT.need(column.key, deck))
        end
      end
    end
    for _, key in ipairs(DECK_SHED[deck]) do
      if remaining() >= ITEM_MIN then break end
      dropped[key] = true
      columnWidth[key] = nil
    end
  end

  local shown = {}
  for _, column in ipairs(COLUMNS) do
    if not dropped[column.key] then shown[#shown + 1] = column end
  end
  return shown, dropped
end

-- One hidden probe per font size, the same face and size as the text it stands in for: the
-- header cells (9), the stand line (10) and the margin line (11).
function FIT.width(size, text)
  if not UI.container or not Theme or type(text) ~= "string" or text == "" then return 0 end
  FIT.probes = FIT.probes or {}
  local probe = FIT.probes[size]
  if not probe then
    probe = Theme.Num(UI.container, size)
    probe:Hide()
    FIT.probes[size] = probe
  end
  probe:SetText(text)
  return probe.GetUnboundedStringWidth and probe:GetUnboundedStringWidth() or 0
end

-- MY LOTS, as the redesign drew it. Functions on ROW rather than file locals: written when this
-- code lived in UI/SellFrame.lua, whose chunk sat at Lua 5.1's limit of 200 locals and whose renderRows
-- sat at its limit of 60 upvalues.
-- (The two key tables stand at file scope, closing brace in column 0: that is how the locale
-- contract's scanner finds where an @localised-keys table ends.)
-- @localised-keys
ROW.SECTION_TITLES = {
  undercut = "UNDERCUT %d", low = "PRICED TOO LOW %d", hold = "HOLDING %d",
  selling = "SELLING %d", notSelling = "NOT SELLING %d",
}
-- @localised-keys
ROW.SECTION_HINTS = {
  undercut = "worth cancelling", hold = "leave these alone",
  selling = "POST lists these", notSelling = "click one to post it",
}
-- The deck in section order, and which section each position fell into.
function ROW.bySection(filtered)
  local ordered, sectionOf = {}, {}
  for _, section in ipairs(GC.SellViewModel.LotSections(filtered, S.cancelEntries)) do
    for _, position in ipairs(section.positions) do
      ordered[#ordered + 1] = position
      sectionOf[position] = section
    end
  end
  return ordered, sectionOf
end

-- TO POST, once the player keeps a selling list (GC.Sell.IsSelling): what POST lists, then what
-- only its own row's Post does, each in the order it came. Stock not on hand belongs to neither:
-- it keeps its place at the end, where renderRows folds it.
function ROW.bySelling(filtered)
  local selling = { id = "selling", positions = {} }
  local notSelling = { id = "notSelling", positions = {} }
  local away = {}
  for _, position in ipairs(filtered) do
    if not position.unresolved and (position.bagQty or 0) == 0 and (position.listedQty or 0) == 0 then
      away[#away + 1] = position
    else
      -- A row whose identity is not settled is never POST's to list, whatever was bought.
      local listable = not position.unresolved and type(position.positionKey) == "string"
      local section = listable and GC.Sell.IsSelling(position) and selling or notSelling
      section.positions[#section.positions + 1] = position
    end
  end
  local ordered, sectionOf = {}, {}
  for _, section in ipairs({ selling, notSelling }) do
    for _, position in ipairs(section.positions) do
      ordered[#ordered + 1] = position
      sectionOf[position] = section
    end
  end
  for _, position in ipairs(away) do ordered[#ordered + 1] = position end
  return ordered, sectionOf
end

function ROW.sectionText(section)
  local hint = ROW.SECTION_HINTS[section.id]
  local text = UI.fmt.count(GC.L[ROW.SECTION_TITLES[section.id]], #section.positions)
    .. (hint and ("  " .. DIM_HEX .. GC.L[hint] .. "|r") or "")
  -- SELLING carries the posting deck's totals: the dock is one row there (owner, 2026-10-10).
  local aside = section.id == "selling" and UI.Dock.SellingAside() or ""
  return aside ~= "" and (text .. "  ·  " .. aside) or text
end

-- The TO POST deck's last section: stock in the bags the tab cannot key yet (the client has
-- not said whether it is a commodity, or cannot give its ItemKey -- GC.Sell._waitingStock).
-- It used to be left out without a word. A heading and a line per item; nothing to post from
-- until the client answers, and then the rescan files it (GC.Sell.OnItemKeyInfo). The search
-- narrows it like every other row.
function ROW.pushWaiting(entries)
  local shown = {}
  for _, waiting in ipairs(GC.Sell._waitingStock or {}) do
    local name = type(waiting.itemName) == "string" and waiting.itemName ~= "" and waiting.itemName
      or itemName(waiting.itemID)
    if not UI.chips.search or name:lower():find(UI.chips.search, 1, true) then
      shown[#shown + 1] = { kind = "waitItem", name = name, quantity = waiting.quantity,
        position = { itemID = waiting.itemID, itemName = name } }
    end
  end
  if #shown == 0 then return end
  entries[#entries + 1] = { kind = "waitHead", count = #shown, position = { itemID = 0 } }
  for _, entry in ipairs(shown) do entries[#entries + 1] = entry end
end

-- The heading's title, and its aside for the heading's own hint cell (Row.PaintHeading): run on in
-- the label, the aside went past the list's edge and was cut mid-word (final review M1).
function ROW.waitText(entry)
  if entry.kind == "waitHead" then
    local open = GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen()
    return UI.fmt.count(GC.L["WAITING FOR THE AUCTION HOUSE %d"], entry.count),
      open and GC.L["the auction house has not sent details for these yet"]
        or GC.L["open the auction house once so GoldCap can tell how these sell"]
  end
  return ("%s ×%d"):format(entry.name, entry.quantity or 0)
end

-- One column can mean two things depending on the deck, and a heading that lies is worse than
-- no heading: MARKET / UNIT is "the cheapest ask that is not mine" while you are choosing a
-- price to post at, and "who is standing under my lot" once it is posted. Same number, two
-- questions, two words for it.
-- @localised-keys
local HEADINGS_POST = {
  item = "ITEM", gross = "YOU GET", price = "PRICE / UNIT",
  cost = "COST / UNIT", listed = "LISTED", market = "MARKET / UNIT",
  profit = "PROFIT / UNIT", status = "WHAT TO DO",
}
-- @localised-keys
local HEADINGS_LISTED = {
  item = "LISTED AS", gross = "IN THE LOT", price = "YOUR PRICE",
  cost = "COST / UNIT", listed = "LOT VALUE", market = "UNDER YOU",
  profit = "PROFIT / UNIT", status = "WHAT TO DO",
}

-- The widest thing a column prints besides its figure: its heading on either deck and, for the
-- two figures that carry one, the second line. The count in the stand line is FormatCount's
-- widest shape ("99.9k" -- five characters). Cached per language and font scale, the only two
-- things that change the answer.
function FIT.need(key, deck)
  local scale = Theme and Theme.Scale and Theme.Scale() or 1
  local stamp = tostring(GC.L["YOU GET"]) .. "|" .. tostring(scale) .. "|" .. tostring(deck)
  if FIT.stamp ~= stamp then
    FIT.stamp, FIT.cache = stamp, {}
    local words = deck == "listed" and HEADINGS_LISTED or HEADINGS_POST
    for columnKey, word in pairs(words) do
      FIT.cache[columnKey] = FIT.width(9, GC.L[word])
    end
    local count = "99.9k"
    local stand = math.max(FIT.width(10, GC.L["first in line"]),
      FIT.width(10, (GC.L["%s ahead"]):format(count)),
      FIT.width(10, (GC.L["%s+ ahead"]):format(count)),
      FIT.width(10, (GC.L["%s under you"]):format(count)))
    if stand > 0 then FIT.cache.price = math.max(FIT.cache.price or 0, stand + ROW.MARKS_W) end
    local margin = math.max(FIT.width(11, GC.L["no cost"]), FIT.width(11, "+9999%"))
    if margin > 0 then FIT.cache.gross = math.max(FIT.cache.gross or 0, margin) end
    -- A few pixels of air: an exactly-fitting string sits flush against its neighbour.
    for columnKey, width in pairs(FIT.cache) do
      FIT.cache[columnKey] = width > 0 and math.ceil(width + 6) or 0
    end
  end
  return FIT.cache[key] or 0
end

local function paintHeaderText(header, deck)
  local words = deck == "listed" and HEADINGS_LISTED or HEADINGS_POST
  for key, cell in pairs(header.cells) do
    local word = words[key]
    cell:SetText(word and GC.L[word] or "")
  end
end
List.PaintHeaderText = paintHeaderText

-- Which figure carries a second line, and the row field that line lives in.
ROW.SECOND_LINE = { price = "priceStand", gross = "grossNote", listed = "grossNote" }

-- How tall a position's name and stock line stand together at the width their anchors give them,
-- both wrapped (Row.CreateRow): what the card has to hold. nil where the client cannot say.
local function blockHeight(row)
  local name, stock = row.cells.item, row.itemStock
  if not (name.GetStringHeight and stock.GetStringHeight) then return nil end
  -- A FontString lays its lines out when its text is SET (UI/Sell/Book.lua's Book.Layout, seen in
  -- game): set again at the width just anchored, or a pooled row measures its last item's lines.
  name:SetText(name:GetText() or ""); stock:SetText(stock:GetText() or "")
  local h = name:GetStringHeight() or 0
  if (stock:GetText() or "") ~= "" then h = h + 2 + (stock:GetStringHeight() or 0) end
  return h > 0 and h or nil
end

-- A position's name over its stock line, the pair centred on the row with `top` the name's top
-- edge above the row's middle. Top points only: a LEFT or RIGHT point pins a FontString's middle,
-- and with it the height of one line, so a wrapped name would spill over its stock line.
local function placeName(row, right, rightLift, top)
  local cell, inset = row.cells.item, row.itemInset or 2
  cell:ClearAllPoints()
  cell:SetPoint("TOPLEFT", row, "LEFT", inset, top)
  cell:SetPoint("TOPRIGHT", right, "LEFT", -4, top - rightLift)
  row.itemStock:ClearAllPoints()
  row.itemStock:SetWordWrap(true) -- a pooled row that was a purchase in the panel held it to one line
  row.itemStock:SetPoint("TOPLEFT", cell, "BOTTOMLEFT", 0, -2)
  row.itemStock:SetPoint("TOPRIGHT", cell, "BOTTOMRIGHT", 0, -2)
end

local function layoutCells(row)
  local right = row
  -- How far `right` itself sits above the row's centre. Every cell anchors to its neighbour,
  -- so a lifted neighbour lifts whatever hangs off it: offsets are written relative to this,
  -- or the second lifted cell in a chain lands a full row-half too high (seen in game -- the
  -- price rode up into the row above it).
  local rightLift = 0
  local cols, dropped = shownColumns()
  for i = #cols, 1, -1 do
    local column, cell = cols[i], row.cells[cols[i].key]
    cell:ClearAllPoints()
    if column.flex then
      -- row.itemInset leaves room for the icon on a position row, and indents a child row so
      -- the hierarchy is carried by layout instead of by leading spaces in the string. The box
      -- this defines is shared by three mutually exclusive widgets -- this cell (a position),
      -- row.subItem (a detail/batch/lot/listing sub-row) and row.sectionLabel (a group heading)
      -- -- exactly one of which is shown per row (the kind branch in Row.Style), so all three
      -- get the same anchors rather than fighting over layout.
      -- The name sits in the upper half of the row and its stock line in the lower half; the
      -- header row and every sub-row keep the whole box, centred, because they carry one line.
      -- 8, not 7: at Theme.Scale 1.3 a 12px name is ~15.6 tall and a 10px stock line ~13, so
      -- the two boxes touch at ±7 and clear each other at ±8 inside the 32px row.
      if row.kind == "position" and row.itemStock then
        -- Laid out once to be measured at its real width, then again centred on what it measured;
        -- the card grows to hold it (row.fitHeight, read by List.RenderRows).
        placeName(row, right, rightLift, ROW.LIFT)
        local block = blockHeight(row)
        if block then placeName(row, right, rightLift, block / 2) end
        row.fitHeight = block and math.ceil(block + 2 * ROW.PAD + ROW.GAP) or nil
      else
        local nameY = row.itemStock and ROW.LIFT or 0
        cell:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, nameY)
        cell:SetPoint("RIGHT", right, "LEFT", -4, nameY - rightLift)
        if row.itemStock then
          row.itemStock:ClearAllPoints()
          row.itemStock:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, -ROW.LIFT)
          row.itemStock:SetPoint("RIGHT", right, "LEFT", -4, -ROW.LIFT - rightLift)
        end
      end
      -- The column header row (below) shares this function but carries neither widget -- it is
      -- a single fixed heading, never a position/sub-row/group in the pooled row sense.
      if row.subItem then
        row.subItem:ClearAllPoints()
        -- Clears the fixed width layoutBookRow gives it. Rows are pooled: a row that drew a
        -- book level last render would otherwise keep an 84px price column forever, fighting
        -- the LEFT/RIGHT pair below for the rest of its life.
        row.subItem:SetWidth(0)
        row.subItem:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, 0)
        row.subItem:SetPoint("RIGHT", right, "LEFT", -4, -rightLift)
      end
      if row.sectionLabel then
        row.sectionLabel:ClearAllPoints()
        row.sectionLabel:SetPoint("LEFT", row, "LEFT", row.itemInset or 2, 0)
      end
      -- Deliberately no cell:Show() here: which of item/subItem/sectionLabel is visible is the
      -- kind branch's call (Row.Style), not this function's -- forcing the flex column shown
      -- unconditionally would undo a "position" row's own cells.item:Hide() on every layout.
      -- The header row (below) sets its own item cell's text once and never hides it.
    else
      cell:SetWidth(columnWidth[column.key] or column.w)
      -- A position's figures share the row with a second line, exactly as its name does with the
      -- stock line (same +-8 split, same reason). Every other kind keeps the cell centred.
      local second = row.kind == "position" and ROW.SECOND_LINE[column.key] and row[ROW.SECOND_LINE[column.key]] or nil
      local lift = second and ROW.LIFT or 0
      -- The figure beside the button stands clear of it: at the usual 2px the row's total ran
      -- into the button's own edge. The button stands clear of the card's right edge in turn: at 0
      -- it sat against the card's ring (owner, 2026-10-10).
      local edge = column.key == "action" and -(ROW.PAD + ROW.GAP / 2) or 0
      local gap = right == row and edge or right == row.cells.action and -ROW.BUTTON_GAP or -2
      cell:SetPoint("RIGHT", right, right == row and "RIGHT" or "LEFT", gap, lift - rightLift)
      if second then
        second:ClearAllPoints()
        second:SetPoint("RIGHT", cell, "RIGHT", 0, -2 * ROW.LIFT)
        -- Held inside its own column: "нет себестоимости" under YOU GET grew leftwards straight
        -- across "24 впереди" under the price (owner, ruRU, Forever beta 2026-10-01). The column
        -- itself is sized to fit its longest second line (FIT.need), so nothing here is ever cut
        -- short -- the owner's rule is that text is read in full, never ended with "…". The stand
        -- line keeps its own width because its marks hang off its left edge; FIT.need leaves room
        -- for them.
        if second ~= row.priceStand then
          second:SetPoint("LEFT", cell, "LEFT", 0, -2 * ROW.LIFT)
        end
      end
      right, rightLift = cell, lift
      cell:Show()
    end
  end
  if row.standMarks then
    -- Chained leftwards from the words they belong to, so the pair stays together however long
    -- the count beside them grows.
    local anchor = row.priceStand
    for i = #row.standMarks, 1, -1 do
      local mark = row.standMarks[i]
      mark:ClearAllPoints()
      mark:SetPoint("RIGHT", anchor, "LEFT", anchor == row.priceStand and -5 or -2, 0)
      anchor = mark
    end
  end
  for _, column in ipairs(COLUMNS) do
    if dropped[column.key] then row.cells[column.key]:Hide() end
  end
end
List.LayoutCells = layoutCells

-- Explanatory tooltip on any frame. Guarded for busted, where no WoW globals exist.
local function explain(frame, title, body)
  if not frame or not frame.SetScript then return end
  -- HookScript, never SetScript: Theme.Button owns OnEnter/OnLeave for its hover fill, and
  -- replacing those would leave buttons stuck in whichever state they were painted in.
  local hook = frame.HookScript and "HookScript" or "SetScript"
  frame[hook](frame, "OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(GC.Util.ClientText(title), 1, 0.82, 0)
    for _, line in ipairs(body) do GameTooltip:AddLine(GC.Util.ClientText(line), 0.85, 0.85, 0.85, true) end
    GameTooltip:Show()
  end)
  frame[hook](frame, "OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
end

-- @localised-keys: literals in this table ARE GC.L keys, looked up where the table is
-- READ, not here. This is file scope, and GC.L only resolves once ApplyLocale has run
-- at ADDON_LOADED -- a lookup here captures the English fallback and keeps it in every
-- language. The table has to close with a `}` on its own line: that is where the
-- contract spec's scanner stops.
local HEADER_HELP = {
  cost = { "Cost per unit", { "What one of these actually cost you, averaged over the purchases still on hand.", "A dash means GoldCap does not know the cost of every unit yet -- it will never guess one from the market price." } },
  listed = { "Listed value", { "What your live auctions for this item add up to at their current asking price." } },
  market = { "Market per unit", {
    "The cheapest price somebody ELSE is currently asking, from a live Auction House query. Your own listings are excluded, so the number never chases itself downwards.",
    "It is what you must beat to sell quickly — not what the item is worth. One seller in a hurry can put it far below value, and GoldCap will refuse to follow them down: see WHAT TO DO for the price it would actually post at.",
    "Greyed out means the quote has aged; Post and Repost refresh it before they act." } },
  profit = { "Profit per unit", { "What you clear on one unit if it sells at the market price: sale price, minus the 5% Auction House cut, minus your cost.", "Unknown means the cost side is incomplete -- fill it in with Set cost." } },
  status = { "What to do", { "GoldCap's suggestion for this item, and the price it would use.", "Breakeven is the lowest price that still returns your cost after the Auction House cut. Selling under it loses money." } },
}
List.HEADER_HELP = HEADER_HELP

local function renderRows()
  if not UI.container then return end
  -- The Sell CONTENT may be attached but not the tab currently on screen -- Compose.Positions()
  -- and GC.Sell.Refresh() run regardless of which tab is active (bag counts and the tab badge
  -- must stay current either way), and that used to rebuild every visible row along with them:
  -- dragging the window's resize grip alone re-ran this at up to 60fps, and every quote landing
  -- during a background pricing walk re-ran it again, whether or not anyone could see the
  -- result. Defer instead, the same way an armed post/repost already defers below --
  -- GC.Sell.Show() reveals the container and then unconditionally calls Refresh(), which is
  -- what actually flushes this: the very next render it triggers runs for real once
  -- Walk.Shown() is true again, so nothing needs a second explicit flush call here.
  if not Walk.Shown() then
    S.deferredRender = true
    return
  end
  -- A post or repost that is armed is waiting on the player's confirming click,
  -- and the pin proving that click belongs to it is bound to a pooled row. A
  -- render rebinds those rows, so this used to answer by CANCELLING the
  -- confirmation the player was one click away from giving. That was already
  -- wrong; the tab now re-prices itself every few seconds, which made it certain.
  -- Hold the render instead. Every arm is timeout-bounded, so it cannot be held
  -- indefinitely, and Post.DisarmPost/Post.DisarmRepost/Post.DisarmRemove flush whatever was
  -- deferred.
  if S.postingRow or S.repostingRow or S.removingRow then
    S.deferredRender = true
    return
  end
  S.deferredRender = false
  renderGeneration = renderGeneration + 1
  -- One read of the bags for this whole pass (see GC.Sell._BagSnapshot); a local, so it dies with it.
  local bagSnapshot = GC.Sell._BagSnapshot()
  -- The two decks carry DIFFERENT column sets, so the heading row has to be re-laid out when
  -- the deck changes -- rows are laid out on every render (below) but the header is built once.
  -- Done here rather than in the deck buttons' own handler because filterMode also moves
  -- underneath us: onCancelQueueClick (UI/Sell/Dock.lua) sets "cancelqueue", which is the listed
  -- deck. Every path that can change the deck ends up here, so this is the one place that
  -- cannot be forgotten.
  local headerDeck = (S.filterMode == "listed" or S.filterMode == "cancelqueue") and "listed" or "post"
  -- The player's selling list (GC.Sell._QueueOpts): nil until the saved data is loaded, and then
  -- the posting deck marks every row and splits in two.
  local sellingList = headerDeck == "post" and GC.Sell._QueueOpts().marks ~= nil
  -- ITEM stands over the names, which the selling mark moves right on the posting deck.
  local headerInset = ROW.ICON + 10 + (sellingList and ROW.MARK_W or 0)
  local header = UI.container and UI.container.header
  if header and (UI.container.headerDeck ~= headerDeck or header.itemInset ~= headerInset) then
    UI.container.headerDeck = headerDeck
    header.itemInset = headerInset
    paintHeaderText(header, headerDeck)
    layoutCells(header)
  end
  local filtered
  if S.filterMode == "cancelqueue" then
    -- The cancel queue's own order, head first -- one row per position however many of its
    -- lots are queued; the queued lots themselves render through the position's expansion,
    -- which is where the Repost/Cancel action a click needs actually lives.
    filtered = {}
    local seen = {}
    for _, entry in ipairs(S.cancelEntries) do
      if not seen[entry.positionKey] then
        seen[entry.positionKey] = true
        local position = currentPosition(entry.positionKey)
        if position then filtered[#filtered + 1] = position end
      end
    end
  else
    -- Deck ends in SellViewModel.Order itself, so there is no second ordering pass here the
    -- way the old single-filter path needed one.
    filtered = GC.SellViewModel.Deck(S.positions, S.filterMode,
      { ready = UI.chips.ready, noCost = UI.chips.nocost })
    -- Deck ends in Order, which is the right answer for a list being BUILT and the wrong one
    -- for a list already on screen: the pricing walk answers one item at a time, and every
    -- answer re-ranked a row out from under the cursor.
    filtered = GC.SellViewModel.Settle(filtered, S.rowPlaces)
    if S.filterMode == "post" then filtered = List.DropPostedOut(filtered) end
  end
  -- MY LOTS reads in three sections (SellViewModel.LotSections); the queue's own focus state
  -- keeps the queue's order, which is the point of it.
  local sectionOf
  if S.filterMode == "listed" then filtered, sectionOf = ROW.bySection(filtered)
  elseif S.filterMode == "post" and sellingList then filtered, sectionOf = ROW.bySelling(filtered) end
  UI.Dock.UpdateSummary(headerDeck)
  -- Why a row is not in the bulk action, by position, for the tag on its stock line. Read off
  -- the same two skip lists the footer's held-back counter reads, so the row and the counter
  -- can never disagree about what was left out.
  local heldBackReason = {}
  local onListed = S.filterMode == "listed" or S.filterMode == "cancelqueue"
  for _, skip in ipairs(onListed and S.cancelSkipped or S.queueSkipped) do
    if type(skip.positionKey) == "string" then heldBackReason[skip.positionKey] = skip.reason end
  end
  -- An unmarked row is not held back, but a click still puts it in the dock, so it still says why
  -- it would not go up (Core/PostQueue.lua's Build keeps the reason).
  if not onListed then
    for _, rest in ipairs(S.notSelling or {}) do
      if type(rest.positionKey) == "string" and rest.reason then heldBackReason[rest.positionKey] = rest.reason end
    end
  end
  -- Posted or passed over this visit (GC.Sell._HoldDoneInQueue): the row says which.
  if not onListed then
    for _, done in ipairs(S.queueDone or {}) do heldBackReason[done.positionKey] = done.reason end
  end
  -- What every position row reads for this render (Row.PaintPosition).
  local ctx = { onListed = onListed, heldBackReason = heldBackReason }
  local entries = {}
  -- Stock that is neither in the bags nor listed is cost history, not work: it sits at the
  -- bottom of the posting deck folded under one heading, so the rows a seller acts on are not
  -- followed by a tail of rows they cannot. NO COST opens it by itself -- those positions are
  -- most of what that chip exists to find, and Set cost lives on their rows.
  local folded = {}
  -- The position whose detail panel is open, if it is on this deck at all: a deck change or a
  -- chip can take the row away, and a panel describing a row that is not there shuts.
  local openPosition
  local function pushPosition(position)
    -- `selling` is the row's selling mark, true or false; nil where there is none to draw.
    -- `markRoom`: the deck has marks, so every row's name starts after one, drawn or not.
    local selling, done
    if sellingList and not position.unresolved and type(position.positionKey) == "string" then
      selling = GC.Sell.IsSelling(position)
      done = selling and GC.Sell.DoneThisVisit(position.positionKey)
    end
    entries[#entries + 1] = { kind = "position", position = position, selling = selling, done = done,
      markRoom = sellingList }
    -- Cached here for every position this render pushes, not only an expanded one: the row's own
    -- Post button (Row.PaintPosition in UI/Sell/Row.lua, "bagQty > 0 and not onListed") is live
    -- whether or not the drawer is open, and onPostClick never builds an ItemLocation itself --
    -- see cacheBagLocation's own comment above Bags.LiveState.
    if (position.bagQty or 0) > 0 then
      GC.Sell._CacheBagLocation(position, Bags.LiveState(position, nil, bagSnapshot))
    end
    if UI.expanded[position.positionKey] and not openPosition then
      openPosition = position
      local first = #entries + 1
      local detail = GC.SellViewModel.Expansion(position, (GC.SellUtil.postQuantity(position)))
      -- ONE panel where this used to spend eleven separate 32px rows: the facts line, the
      -- price control, the book heading and eight levels. Opening a position buried the list
      -- it was opened from -- 25 rows of expansion inside a 430px scroll area -- which is the
      -- single complaint this redesign started from.
      entries[#entries + 1] = { kind = "drawer", position = position, detail = detail,
        -- Without a book the eight levels are not drawn, and neither is the room for them: the
        -- head used to keep 160px of nothing between its heading and "has not answered yet".
        slots = ((position.bagQty or 0) > 0 and DR.SLOTS or DR.SLOTS_BARE) - (detail.book and 0 or DR.NO_BOOK_SLOTS)
          - (((position.bagQty or 0) > 0 and not detail.factsText) and DR.NO_REASON_SLOTS or 0) }
      local head = table.remove(entries)
      -- What you are selling comes before what you paid: the listings are the thing a player
      -- acts on, the purchase history is only there to justify the cost number.
      local inBags = position.bagQty or 0
      -- The bag line earns its row when it says something the panel's heading ("x37 in bags")
      -- does not: that one click lists only part of the stock, that no stack can be pinned
      -- down, or that some of it has no cost and can be given one here.
      local bagState = inBags > 0 and Bags.LiveState(position, nil, bagSnapshot) or nil
      GC.Sell._CacheBagLocation(position, bagState)
      local postableNow = bagState and bagState.bag and exact(bagState.exactQty) and bagState.exactQty or 0
      local bagLine = inBags > 0 and (postableNow ~= inBags or UI.CostDialog.CanSetCost(position))
      -- On MY LOTS the lots ARE the subject, so they open the panel -- each with its own
      -- Cancel lot -- and the book follows as the evidence. On the posting deck the price
      -- control is the subject and the lots come after it, as before.
      if not onListed then entries[#entries + 1] = head end
      if #detail.ownedLots > 0 or bagLine then
        entries[#entries + 1] = { kind = "group", position = position,
          title = onListed and GC.L["YOUR LOTS"] or GC.L["ON THE AUCTION HOUSE"],
          aside = onListed and ROW.lotsAside(position) or nil }
      end
      for _, lot in ipairs(detail.ownedLots) do entries[#entries + 1] = { kind = "lot", position = position, lot = lot } end
      if bagLine then
        entries[#entries + 1] = { kind = "listing", position = position }
      end
      if onListed then entries[#entries + 1] = head end
      if #detail.batches > 0 then
        entries[#entries + 1] = { kind = "group", position = position, title = GC.L["WHAT YOU PAID"],
          hint = GC.L["Sales are costed from your oldest units first"],
          aside = GC.L["oldest units sell first"] }
      end
      for _, batch in ipairs(detail.batches) do entries[#entries + 1] = { kind = "batch", position = position, batch = batch } end
      -- Everything a position opens into is drawn in the side panel, not under the row. The
      -- entries keep their place in this one list -- and so their pooled rows and every pin a
      -- post or a cancel holds on one -- and only say where they are to be laid out.
      for index = first, #entries do entries[index].panel = true end
    end
  end
  for _, position in ipairs(filtered) do
    local notOnHand = S.filterMode == "post" and not position.unresolved
      and (position.bagQty or 0) == 0 and (position.listedQty or 0) == 0
    -- The search narrows what is DRAWN, after the ledger has been summed: the dock's totals
    -- are the deck's, and would otherwise jump about under every keystroke. Plain substring,
    -- lower-cased -- which folds ASCII only, so a Cyrillic name matches in the case it is
    -- written in; the client's Lua has no way to fold the rest.
    local name = type(position.itemName) == "string" and position.itemName:lower() or ""
    local matches = not UI.chips.search or name:find(UI.chips.search, 1, true) ~= nil
    if matches and notOnHand then folded[#folded + 1] = position
    elseif matches then
      -- A heading goes in ahead of the first of its positions that is actually drawn, so a
      -- search that empties a section takes its heading with it.
      local section = sectionOf and sectionOf[position]
      if section and not section.headed then
        section.headed = true
        entries[#entries + 1] = { kind = "section", position = position, section = section }
      end
      pushPosition(position)
    end
  end
  -- Only a TAIL is folded. When nothing on the deck is on hand there is no work for the fold to
  -- keep clear, and hiding the only rows there are would leave a heading over an empty list.
  if #folded > 0 and #entries == 0 then
    for _, position in ipairs(folded) do pushPosition(position) end
  elseif #folded > 0 then
    local open = UI.showNotOnHand or UI.chips.nocost
    entries[#entries + 1] = { kind = "fold", position = folded[1], count = #folded, open = open }
    if open then
      for _, position in ipairs(folded) do pushPosition(position) end
    end
  end
  if S.filterMode == "post" then ROW.pushWaiting(entries) end
  local empty = UI.container.empty
  if #entries == 0 then
    local icon, title, line = GC.Sell._EmptyDeck()
    if Theme.SetIcon then Theme.SetIcon(empty.icon, icon, Theme.color.gold) end
    -- The line no wider than a comfortable read, and never wider than the list leaves it.
    local width = math.min(340, math.max(160, (UI.rowWidth or 340) - 72))
    empty.title:SetWidth(width); empty.line:SetWidth(width)
    empty.title:SetText(GC.Util.Upper(title))
    empty.line:SetText(line)
    empty:Show()
  else
    empty:Hide()
  end
  for i = #UI.rows + 1, #entries do UI.rows[i] = UI.Row.CreateRow(UI.content) end
  -- Known before any row is laid out: a docked panel takes its width out of the list's, and
  -- shownColumns reads that. The heading row and the scroll area follow whenever it changes.
  INSP.sync(openPosition ~= nil)
  -- Running Y for the loop below, one per surface. Rows are pooled and re-anchored on every
  -- render, so both are rebuilt from scratch each time rather than remembered.
  local placedHeight, detailHeight = 0, 0
  for i, row in ipairs(UI.rows) do
    local entry = entries[i]
    if not entry then row.renderEntryID = nil; row:Hide()
    else
      -- One pool, two surfaces. A row is re-parented only when its entry moves between them,
      -- which a position being opened or shut does and a re-price never does -- so the price
      -- box a seller is typing into is not touched by the renders their typing causes.
      local surface = entry.panel and UI.detailContent or UI.content
      row.inPanel = entry.panel == true
      if surface and row.surface ~= surface then
        row.surface = surface
        if row.SetParent then row:SetParent(surface) end
      end
      -- Slot-based placement, not a fixed pitch off the index: an entry may claim several
      -- ROW_HEIGHT slots (entry.slots) so that one row can be a PANEL instead of a line. Every
      -- entry that does not ask for slots claims exactly one, which is the old arithmetic
      -- (offset == (i - 1) * ROW_HEIGHT) reproduced exactly -- so nothing but the drawer moves.
      local slots = entry.slots or 1
      local offset = entry.panel and detailHeight or placedHeight
      row:Show(); row:ClearAllPoints()
      row:SetPoint("TOPLEFT", surface, "TOPLEFT", 0, -offset); row:SetPoint("TOPRIGHT", surface, "TOPRIGHT", 0, -offset)
      -- Where it was placed, for a closing gap to move it from (List.Leave), and opaque: a pooled
      -- row may have been the one fading.
      row.placedY = offset
      if row.SetAlpha then row:SetAlpha(1) end
      -- A position in the list is a card at least ROW.H tall; everything else keeps the slot pitch.
      local card = entry.kind == "position" and not entry.panel
      row:SetHeight(card and ROW.H or slots * UI.rowHeight)
      row.kind, row.position, row.batch, row.lot = entry.kind, entry.position, entry.batch, entry.lot
      -- Read by this row's own OnEnter (Row.CreateRow) to decide whether to add a tooltip line about the
      -- number this row is showing. Reset for every kind, not just "position": rows are pooled
      -- and rebound, so a flag left set from an earlier position would otherwise ride along onto
      -- an unrelated expansion sub-row.
      row.marketFallback, row.notOnHand, row.groupHint = false, false, nil
      local p = entry.position
      local lotID = entry.lot and entry.lot.auctionID or 0
      row.renderEntryID = table.concat({ renderGeneration, i, entry.kind, p.scopeKey or "", p.positionKey or "", lotID }, ":")
      -- Every cell starts empty, whatever kind takes this pooled row next, so a branch only
      -- has to write what it actually shows. Enumerating the clears per branch is what leaked
      -- YOU GET / PRICE / MARGIN onto lot and batch sub-rows: those lists were written before
      -- the columns existed, and nothing made anybody update them.
      for _, column in ipairs(COLUMNS) do row.cells[column.key]:SetText("") end
      if entry.kind == "position" then
        UI.Row.PaintPosition(row, entry, ctx)
      elseif entry.kind == "drawer" then
        INSP.paintHead(row, p, entry.detail)
      elseif entry.kind == "fold" or entry.kind == "section" or entry.kind == "waitHead"
          or entry.kind == "waitItem" then
        UI.Row.PaintHeading(row, entry)
      elseif entry.kind == "batch" then
        UI.CostDialog.PaintBatch(row, entry)
      else
        UI.Inspector.PaintPanelRow(row, entry, bagSnapshot)
      end
      row.fitHeight = nil
      UI.Row.Style(row, entry)
      -- Taller when its words wrap: Row.Style measured them (a card's name and stock line, the
      -- waiting heading's aside).
      local height = math.max(card and ROW.H or slots * UI.rowHeight, row.fitHeight or 0)
      row:SetHeight(height)
      if entry.panel then detailHeight = detailHeight + height else placedHeight = placedHeight + height end
    end
  end
  UI.Inspector.PaintInspector(openPosition)
  -- Measured from what was actually placed, not from #entries: a multi-slot entry occupies
  -- more than one row's worth, and a scroll child sized by entry COUNT would clip the drawer.
  UI.content:SetHeight(math.max(UI.rowHeight, placedHeight))
  if UI.detailContent then UI.detailContent:SetHeight(math.max(UI.rowHeight, detailHeight)) end
  Walk.ScheduleExpiry()
  if GC.Sniper and GC.Sniper.UpdateSellTabLabel then GC.Sniper.UpdateSellTabLabel() end
  -- The dock's item is read off the rows just placed (UI.Dock.Current), so the dock is painted
  -- after every render that placed them.
  UI.Dock.PaintQueueButton()
end
List.RenderRows = renderRows

GC.SellView.render = function(...) return UI.List.RenderRows(...) end

function List.Build()
  local container = UI.container
  List.leaveDriver = CreateFrame("Frame", nil, container) -- runs a posted row's going (List.Leave)
  local header = CreateFrame("Frame", nil, container)
  -- Kept on the container so renderRows can re-lay it out when the deck changes; see its own
  -- comment for why that cannot live in the deck buttons' click handler.
  container.header = header
  container.headerDeck = "post"
  header:SetPoint("TOPLEFT", 0, -34); header:SetPoint("TOPRIGHT", 0, -34); header:SetHeight(16); header.cells = {}
  header.itemInset = ROW.ICON + 10 -- line the ITEM heading up with the names, not with the icons
  for _, column in ipairs(COLUMNS) do
    local cell = Theme.Num(header, 9); cell:SetWordWrap(false); cell:SetText(""); header.cells[column.key] = cell
    -- One line, hard capped -- the pair every other single-line cell in the kit carries
    -- (UI/SniperFrame.lua's buildHeaderCell): this row is 16px tall, and a line that does
    -- not fit the height it is given is not drawn at all.
    cell:SetMaxLines(1)
    setColor(cell, Theme.color.fgDim)
    -- Headings must sit over their own numbers. Row.CreateRow right-aligns every numeric cell, but
    -- these were left at the default left alignment, so each heading floated to the left edge
    -- of a right-aligned column and every value looked like it belonged to the column after it.
    cell:SetJustifyH(column.num and "RIGHT" or "LEFT")
    -- A FontString cannot take mouse scripts, so each heading gets an invisible hit frame over
    -- it. Every column here is a number a seller has to trust, so each one explains itself
    -- instead of expecting a one-word heading to carry the meaning.
    local help = HEADER_HELP[column.key]
    if help then
      local hit = CreateFrame("Frame", nil, header)
      hit:SetAllPoints(cell)
      hit:EnableMouse(true)
      -- Translated at READ time -- see HEADER_HELP's own comment for why the table
      -- itself cannot hold GC.L lookups.
      local body = {}
      for i = 1, #help[2] do body[i] = GC.L[help[2][i]] end
      explain(hit, GC.L[help[1]], body)
    end
  end
  -- Separates the column headings from the first row now that both read in the same mono
  -- font -- without it the header row visually fused with row 1.
  local rule = header:CreateTexture(nil, "ARTWORK")
  local bc = Theme.color.border
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
  paintHeaderText(header, "post")
  layoutCells(header)
  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT", 0, -52)
  container.scroll = scroll
  if Theme.QuietScrollBar then Theme.QuietScrollBar(scroll) end -- no Blizzard arrows beside a kit panel
  -- Stops above the footer instead of running to the container's own bottom edge: the bulk
  -- action and the ledger line live there now, and a list that scrolled under them would put
  -- rows behind a control that can spend gold.
  scroll:SetPoint("BOTTOMRIGHT", 0, UI.Dock.Height() + 6)
  -- The empty deck (GC.Sell._EmptyDeck): a gold tile with the reason's icon, the reason in
  -- capitals under it, and the line saying what to do, in the middle of where the rows would be.
  -- Parented to `scroll` (not `content`), so it never scrolls.
  local empty = CreateFrame("Frame", nil, scroll)
  empty:SetSize(64, 64)
  empty:SetPoint("BOTTOM", scroll, "CENTER", 0, 10)
  local gc = Theme.color.gold
  Theme.SlicedTexture(empty, "BACKGROUND", Theme.MEDIA .. "plaque.png", { gc[1], gc[2], gc[3], 0.08 }, 12)
    :SetAllPoints(empty)
  Theme.SlicedTexture(empty, "BORDER", Theme.MEDIA .. "plaque_ring.png", { gc[1], gc[2], gc[3], 0.3 }, 12)
    :SetAllPoints(empty)
  if Theme.Glow then Theme.Glow(empty, { gc[1], gc[2], gc[3], 0.12 }, 16) end
  empty.icon = empty:CreateTexture(nil, "ARTWORK")
  empty.icon:SetSize(30, 30)
  empty.icon:SetPoint("CENTER", empty, "CENTER", 0, 0)
  empty.title = (Theme.Heading or Theme.Label)(empty, 15)
  empty.title:SetPoint("TOP", empty, "BOTTOM", 0, -14)
  empty.title:SetJustifyH("CENTER"); empty.title:SetWordWrap(true)
  setColor(empty.title, Theme.color.fg)
  empty.line = Theme.Label(empty, 12)
  empty.line:SetPoint("TOP", empty.title, "BOTTOM", 0, -8)
  empty.line:SetJustifyH("CENTER"); empty.line:SetWordWrap(true)
  empty.line:SetSpacing(3)
  setColor(empty.line, Theme.color.fgDim)
  empty:Hide()
  container.empty = empty
  UI.content = CreateFrame("Frame", nil, scroll); UI.content:SetSize(UI.rowWidth, UI.rowHeight); scroll:SetScrollChild(UI.content)
end

-- The list's own width follows the panel: docked, it ends where the panel's column begins
-- (the gap is where the list's scroll bar hangs); as a sheet, it keeps the whole width and
-- the panel covers its right side. Called by renderRows when that changes and by the resize
-- hook, never per render.
function List.ApplyListGeometry()
  local container = UI.container
  local header, scroll = container.header, container.scroll
  local inset = INSP.docked() and (INSP.W + INSP.GAP) or 0
  header:ClearAllPoints()
  header:SetPoint("TOPLEFT", 0, -34); header:SetPoint("TOPRIGHT", -inset, -34)
  scroll:ClearAllPoints()
  scroll:SetPoint("TOPLEFT", 0, -52)
  scroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -inset, UI.Dock.Height() + 6)
  UI.content:SetWidth(INSP.listWidth())
  layoutCells(header)
end
