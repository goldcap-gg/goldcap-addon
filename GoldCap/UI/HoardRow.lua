local _, GC = ...

-- A row of the GoldCap Hoard's list (UI/HoardFrame.lua, loaded before this file): a followed group,
-- or a folder holding the subgroups of one group on goldcap.gg, as Core/Hoard.lua's Rows lists
-- them. The same widget for both, pooled by place in the window. On its top line: a folder's
-- chevron, the name, the play's chip (a folder: how many groups), the items' icons with how many
-- there are and "+N" for the rest, what they are worth here, Store and Take out; along its bottom,
-- a bar of how much is in the bags and how much in the bank. A group row opened by a click shows
-- every item with where it is, how many of each item the group keeps in the bags, and which stacks
-- stay there and why. Store and Take out are the window's move buttons (HF.ui.moveButton): their
-- click is the window's press, and this file moves nothing. Its own clicks open a row or a folder
-- and ask the keep count.
--
-- Pressed again and again in one spot, so nothing on a row moves while a press runs: everything
-- right of the name stands at a fixed place from the row's right edge, the worth column is as wide
-- as the window's widest (it only widens), and an opened row keeps room for the most its lines can
-- say.
local HF = GC.HoardFrame
local K = GC.Kit.Tokens.color
local U = HF.ui
local L = U.L
local setText, colour, wrapping, heightOf = U.setText, U.colour, U.wrapping, U.heightOf

-- The colours the boards draw a row with, all from the kit's tokens: Store in the gold the bags'
-- share wears, an opened row ringed in it; an icon with no quality colour edged dark; the "+N" box
-- a few percent of white; each play's chip in its own colour.
local STORE_RING = { K.gold[1], K.gold[2], K.gold[3], 0.45 }
local OPEN_RING = { K.gold[1], K.gold[2], K.gold[3], 0.35 }
local ICON_EDGE = { 0, 0, 0, 0.75 }
local MORE_FILL = { 1, 1, 1, 0.06 }
local PLAY_COLOR = { gather = K.profit, craft = K.yours, flip = K.goldText, stock = K.text2 }
-- The bar's bank share: the legend's slate (HF.ui.SLATE) a step darker, as the board draws the
-- bar's track under the bags' gold.
local SLATE_TRACK = { U.SLATE[1], U.SLATE[2], U.SLATE[3], 0.38 }

-- The words for the bank the window works with: the Warband Bank's, else the character's own
-- bank's.
local function bankWords(bankType)
  if bankType == (Enum and Enum.BankType and Enum.BankType.Account) then
    return { counts = GC.L["%d in bags, %d in the Warband Bank"],
      refused = GC.L["Stays in bags: %s ×%d, the Warband Bank does not take it"] }
  end
  return { counts = GC.L["%d in bags, %d in your bank"],
    refused = GC.L["Stays in bags: %s ×%d, your bank does not take it"] }
end

local function playLabel(play)
  if play == "gather" then return GC.L["Gather"] end
  if play == "craft" then return GC.L["Craft"] end
  if play == "flip" then return GC.L["Flip"] end
  if play == "stock" then return GC.L["Stock"] end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- The clicks that move nothing
-- ---------------------------------------------------------------------------------------------

-- The keep count, asked in the kit's popup (UI/BuyCapEditor.lua) and saved for the account, by the
-- group's key; the question names the group.
local function askKeep(button)
  local key = button.group
  if not key then return end
  GC.BuyCapEditor.Open(button, {
    title = GC.L["How many of each item in %s to keep in your bags?"]:format(button.groupName or key),
    text = tostring(GC.BankGroups.KeepFor(GC.db, key)),
    read = function(text) return GC.CraftQueue.ParseCount(text, true) end,
    invalid = GC.L["Type a whole number"],
    setLabel = GC.L["Save"],
    onCommit = function(n)
      GC.BankGroups.SetKeep(GC.db, key, n)
      HF.Refresh()
    end,
  })
end

-- A row's own click, on its top line: a folder opens or closes, remembered for the account
-- (GC.db.hoard), or for this session when a newer GoldCap's memory cannot be written; a group row
-- opens (one at a time) or closes. A row is told apart by its kind as well as its key, as a
-- folder's key is its parent group's, which a followed top group may share.
local function onRowClick(head)
  local data = head.data
  if not data then return end
  if data.kind == "folder" then
    local open = not data.open
    if GC.Hoard.SetFolderOpen(GC.db, data.key, open) then
      HF._foldersHere[data.key] = nil
    else
      HF._foldersHere[data.key] = open
    end
  else
    HF._open = HF._open ~= data.key and data.key or nil
  end
  HF.Refresh()
end

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------

-- A row's Store or Take out, as the boards draw them: a small rounded button with the kit's arrow,
-- Store in the gold the bags' share wears, Take out quiet.
local function iconMove(parent, into)
  local b = U.moveButton(parent, into, into and "active" or "ghost")
  b:SetSize(L.MOVE, L.MOVE)
  b:SetRing(into and STORE_RING or K.windowBorder)
  b.icon = b:CreateTexture(nil, "OVERLAY")
  b.icon:SetSize(L.MOVE_ICON, L.MOVE_ICON)
  b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.iconColor = into and K.goldText or K.text2
  GC.Theme.SetIcon(b.icon, into and "caretDown" or "caretUp", b.iconColor)
  return b
end

-- A count over an item's icon: the condensed heavy face with an outline, as the game writes a
-- stack's count over its slot.
local function countText(parent, size)
  local T = GC.Theme
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(T.FONT_HEAD_HEAVY, size * T.Scale(), "OUTLINE")
  T.TrackFont(fs, { role = "count", path = T.FONT_HEAD_HEAVY, size = size, flags = "OUTLINE" })
  fs:SetJustifyH("RIGHT")
  fs:SetWordWrap(false)
  return fs
end

-- An item's icon in a 1px edge in its quality's colour (common and poor: a dark edge), the game's
-- own border cut off the art.
local function newIcon(parent, size, countSize)
  local edge = parent:CreateTexture(nil, "BORDER")
  edge:SetSize(size, size)
  local icon = parent:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local count = countSize and countText(parent, countSize) or nil
  if count then count:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", 0, 1) end
  return { edge = edge, icon = icon, count = count }
end

local function paintIcon(slot, itemID, file, count)
  local quality = GC.Theme.QualityColor(itemID)
  local c = quality and { quality.r, quality.g, quality.b, 1 } or ICON_EDGE
  slot.edge:SetColorTexture(c[1], c[2], c[3], c[4])
  slot.icon:SetTexture(file or 134400) -- the question mark, while the client has no icon for it yet
  slot.edge:Show()
  slot.icon:Show()
  if slot.count then
    setText(slot.count, count and GC.Util.FormatCount(count) or "")
    slot.count:Show()
  end
end

local function hideIcon(slot)
  slot.edge:Hide()
  slot.icon:Hide()
  if slot.count then slot.count:Hide() end
end

-- One row of the list, in the window's scroll (`parent`).
local function newRow(parent)
  local T = GC.Theme
  local row = CreateFrame("Frame", nil, parent)
  row.bg = T.SlicedTexture(row, "BACKGROUND", T.MEDIA .. "plaque.png", K.glassBottom, T.SLICE.plaque)
  row.bg:SetAllPoints()
  row.ring = T.SlicedTexture(row, "BORDER", T.MEDIA .. "plaque_ring.png", K.hairline, T.SLICE.plaque)
  row.ring:SetAllPoints()
  -- The click that opens the row is on its top line, under its buttons.
  row.head = U.plate(row, nil, "plaque")
  row.head:SetFrameLevel(row:GetFrameLevel() + 1)
  row.head:SetScript("OnClick", onRowClick)
  row.chevron = row:CreateTexture(nil, "ARTWORK")
  row.chevron:SetSize(L.CHEVRON, L.CHEVRON)
  row.name = wrapping(T.Label(row, 11))
  colour(row.name, K.text1)
  row.sub = wrapping(T.Label(row, 9))
  colour(row.sub, K.text3)
  row.chip = T.Chip(row)
  row.chip:SetHeight(L.CHIP_H)
  row.icons = {}
  for i = 1, GC.Hoard.ICONS do row.icons[i] = newIcon(row, L.ICON, 8) end
  row.more = T.SlicedTexture(row, "ARTWORK", T.MEDIA .. "badge.png", MORE_FILL, T.SLICE.badge)
  row.moreText = T.Num(row, 9)
  row.moreText:SetJustifyH("CENTER")
  colour(row.moreText, K.text2)
  row.worth = T.Num(row, 10)
  row.worth:SetWordWrap(false)
  colour(row.worth, K.goldText)
  row.store = iconMove(row, true)
  row.take = iconMove(row, false)
  row.bankBar = T.Solid(row, "ARTWORK", SLATE_TRACK)
  row.bagsBar = T.Solid(row, "OVERLAY", K.gold)
  row.keep = T.Button(row, "ghost", "badge")
  row.keep:SetHeight(L.KEEP_H)
  row.keep:SetRing(K.windowBorder)
  row.keep:SetScript("OnClick", askKeep)
  for _, b in ipairs({ row.store, row.take, row.keep }) do b:SetFrameLevel(row:GetFrameLevel() + 3) end
  row.items, row.stays = {}, {}
  return row
end

-- One item of an opened row: its icon, its name, and where it is.
local function newItemLine(row)
  local T = GC.Theme
  local line = newIcon(row, L.ITEM_ICON, nil)
  line.name = wrapping(T.Label(row, 10))
  colour(line.name, K.text1)
  line.counts = wrapping(T.Label(row, 9))
  colour(line.counts, K.text3)
  return line
end

-- ---------------------------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------------------------

-- A wrapping line's height at its width, with room for the longest it can say (`most`): a move
-- keeps a group's total, so neither number can grow longer than it.
local function heightFor(fs, text, most)
  setText(fs, most)
  local h = heightOf(fs, 12)
  setText(fs, text)
  return math.max(h, heightOf(fs, 12))
end

-- An opened group's lines under its top line, from `y`: the keep count, then every item with its
-- icon, its name and where it is, then each stack that stays in the bags and why. Answers the y
-- under them.
local function paintOpen(row, group, ctx, y)
  local x, width = L.ROW_PAD, row:GetWidth()
  local keep = row.keep
  keep.group, keep.groupName = group.key, group.name
  if ctx.writable then
    keep:SetLabel(GC.L["Keep in bags: %d of each"]:format(group.keep))
    keep:FitLabels({ keep.label }, 0)
    keep:ClearAllPoints()
    keep:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    keep:Show()
    y = y + L.KEEP_H + L.ITEM_GAP
  else
    keep:Hide()
  end
  local words = bankWords(ctx.bankType)
  local nameX = x + L.ITEM_ICON + 6
  for i, item in ipairs(group.items) do
    local line = row.items[i] or newItemLine(row)
    row.items[i] = line
    line.edge:ClearAllPoints()
    line.edge:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    paintIcon(line, item.itemID, ctx.icons[item.itemID], nil)
    line.name:SetWidth(width - nameX - L.ROW_PAD)
    setText(line.name, GC.Theme.WithQuality(item.name or ("#" .. tostring(item.itemID)), item.itemID, 12))
    line.name:ClearAllPoints()
    line.name:SetPoint("TOPLEFT", row, "TOPLEFT", nameX, -y)
    line.name:Show()
    local nameH = heightOf(line.name, 12)
    local here = ctx.perItem[item.itemID] or { bags = 0, bank = 0 }
    line.counts:SetWidth(width - nameX - L.ROW_PAD)
    local countsH = heightFor(line.counts, words.counts:format(here.bags, here.bank),
      words.counts:format(item.count, item.count))
    line.counts:ClearAllPoints()
    line.counts:SetPoint("TOPLEFT", row, "TOPLEFT", nameX, -(y + nameH + 1))
    line.counts:Show()
    y = y + math.ceil(math.max(L.ITEM_ICON, nameH + 1 + countsH)) + L.ITEM_GAP
  end
  for i = #group.items + 1, #row.items do
    local line = row.items[i]
    hideIcon(line)
    line.name:Hide()
    line.counts:Hide()
  end
  for i, entry in ipairs(group.stays) do
    local fs = row.stays[i]
    if not fs then
      fs = wrapping(GC.Theme.Label(row, 9))
      colour(fs, K.text3)
      row.stays[i] = fs
    end
    local why = entry.why == "refund" and GC.L["Stays in bags: %s ×%d, can still be refunded"] or words.refused
    fs:SetWidth(width - 2 * L.ROW_PAD)
    setText(fs, why:format(U.itemName(entry), entry.count))
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    fs:Show()
    y = y + math.ceil(heightOf(fs, 12)) + 2
  end
  for i = #group.stays + 1, #row.stays do row.stays[i]:Hide() end
  return y + L.ROW_PAD - L.ITEM_GAP
end

-- The lines only an opened row shows, hidden.
local function closeOpen(row)
  row.keep:Hide()
  for _, line in ipairs(row.items) do
    hideIcon(line)
    line.name:Hide()
    line.counts:Hide()
  end
  for _, fs in ipairs(row.stays) do fs:Hide() end
end

-- The name, the play's chip and a folder's chevron and group count, from the row's left edge to
-- `nameRight`: the name as wide as it is up to the room left, wrapping, its chip beside its first
-- line. Answers the top line's height, which grows for a name that wraps.
local function paintName(row, data, nameRight)
  local folder = data.kind == "folder"
  local x = L.ROW_PAD
  if folder then
    GC.Theme.SetIcon(row.chevron, (data.open or data.forcedOpen) and "caretDown" or "caretRight", K.text2)
    row.chevron:Show()
    x = x + L.CHEVRON + L.TEXT_PAD
  else
    row.chevron:Hide()
  end
  local play = not folder and playLabel(data.play) or nil
  local chipW = 0
  if play then
    row.chip:SetLabel(GC.Util.Upper(play), PLAY_COLOR[data.play])
    chipW = math.ceil(row.chip.text:GetUnboundedStringWidth() or 0) + 10
    row.chip:SetWidth(chipW)
    row.chip:Show()
  else
    row.chip:Hide()
  end
  local room = nameRight - x - (chipW > 0 and chipW + 4 or 0)
  setText(row.name, data.name)
  local nameW = math.max(L.NAME_MIN, math.min(math.ceil(row.name:GetUnboundedStringWidth() or 0) + 1, room))
  row.name:SetWidth(nameW)
  setText(row.name, data.name)
  local nameH = heightOf(row.name, 13)
  local textH = nameH
  if folder then
    row.sub:SetWidth(math.max(L.NAME_MIN, nameRight - x))
    setText(row.sub, GC.L["%d groups"]:format(data.childCount))
    textH = textH + 1 + heightOf(row.sub, 11)
    row.sub:Show()
  else
    row.sub:Hide()
  end
  local headH = math.max(folder and L.FOLDER_H or L.ROW_H, math.ceil(textH) + 2 * L.TEXT_PAD)
  local textTop = math.floor((headH - textH) / 2)
  row.name:ClearAllPoints()
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", x, -textTop)
  if folder then
    row.sub:ClearAllPoints()
    row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", x, -(textTop + nameH + 1))
    row.chevron:ClearAllPoints()
    row.chevron:SetPoint("TOPLEFT", row, "TOPLEFT", L.ROW_PAD, -math.floor((headH - L.CHEVRON) / 2))
  end
  if play then
    local firstLine = math.min(nameH, 14)
    row.chip:ClearAllPoints()
    row.chip:SetPoint("TOPLEFT", row, "TOPLEFT", x + nameW + 4, -(textTop + math.floor((firstLine - L.CHIP_H) / 2)))
  end
  return headH
end

-- The bar along the row's bottom (`height` its height so far): the bank's share under the bags',
-- inside the plate's rounded corners. Answers the row's height with it.
local function paintBar(row, data, height)
  height = height + L.BAR_H
  local track = row:GetWidth() - 2 * L.BAR_IN
  local total = data.inBags + data.inBank
  local barY = -(height - L.BAR_H - 1)
  row.bankBar:ClearAllPoints()
  row.bankBar:SetPoint("TOPLEFT", row, "TOPLEFT", L.BAR_IN, barY)
  row.bankBar:SetSize(track, L.BAR_H)
  local bagsW = total > 0 and math.floor(track * data.inBags / total + 0.5) or 0
  row.bagsBar:ClearAllPoints()
  row.bagsBar:SetPoint("TOPLEFT", row, "TOPLEFT", L.BAR_IN, barY)
  row.bagsBar:SetSize(bagsW, L.BAR_H)
  row.bagsBar:SetShown(bagsW > 0)
  return height
end

-- One row (Core/Hoard.lua's Rows) at the row's width, with the window's paint's ctx: the top line
-- (paintName on the left; right to left Take out, Store, the worth column, then the icons and "+N"
-- against it, each at a fixed place from the row's right edge, so they line up from row to row and
-- never move); under it, opened, its items (paintOpen); along its bottom the bar. Answers the row's
-- height.
local function paintRow(row, data, ctx)
  local folder = data.kind == "folder"
  local opened = not folder and HF._open == data.key
  local width = row:GetWidth()
  row.data, row.head.data = data, data
  local fill = folder and K.glassTop or K.glassBottom
  local ring = opened and OPEN_RING or (folder and K.glassBorder or K.hairline)
  row.bg:SetVertexColor(fill[1], fill[2], fill[3], fill[4])
  row.ring:SetVertexColor(ring[1], ring[2], ring[3], ring[4])

  local takeX = width - L.ROW_PAD - L.MOVE
  local storeX = takeX - L.MOVE_GAP - L.MOVE
  local worthRight = storeX - L.COL_GAP
  local iconsRight = worthRight - ctx.worthW - L.COL_GAP
  local moreW = 0
  if data.more > 0 then
    setText(row.moreText, "+" .. data.more)
    moreW = math.max(L.ICON, math.ceil(row.moreText:GetStringWidth() or 0) + 6)
  end
  local n = #data.icons
  local iconsW = n * L.ICON + math.max(0, n - 1) * L.ICON_GAP
  local blockW = iconsW + (moreW > 0 and ((n > 0 and L.ICON_GAP or 0) + moreW) or 0)
  local blockX = iconsRight - blockW
  local headH = paintName(row, data, blockW > 0 and (blockX - L.COL_GAP) or iconsRight)

  -- The icons, "+N", the worth and the two moves, centred on the top line.
  local iconY = math.floor((headH - L.ICON) / 2)
  for i, slot in ipairs(row.icons) do
    local icon = data.icons[i]
    if icon then
      slot.edge:ClearAllPoints()
      slot.edge:SetPoint("TOPLEFT", row, "TOPLEFT", blockX + (i - 1) * (L.ICON + L.ICON_GAP), -iconY)
      paintIcon(slot, icon.itemID, icon.icon, icon.count)
    else
      hideIcon(slot)
    end
  end
  if moreW > 0 then
    row.more:ClearAllPoints()
    row.more:SetPoint("TOPLEFT", row, "TOPLEFT", iconsRight - moreW, -iconY)
    row.more:SetSize(moreW, L.ICON)
    row.more:Show()
    row.moreText:ClearAllPoints()
    row.moreText:SetPoint("CENTER", row.more, "CENTER", 0, 0)
    row.moreText:Show()
  else
    row.more:Hide()
    row.moreText:Hide()
  end
  setText(row.worth, U.worthText(data.worth))
  row.worth:ClearAllPoints()
  row.worth:SetPoint("RIGHT", row, "TOPLEFT", worthRight, -headH / 2)
  local moveY = -math.floor((headH - L.MOVE) / 2)
  row.store:ClearAllPoints()
  row.store:SetPoint("TOPLEFT", row, "TOPLEFT", storeX, moveY)
  row.take:ClearAllPoints()
  row.take:SetPoint("TOPLEFT", row, "TOPLEFT", takeX, moveY)
  U.paintMove(row.store, data.toBank, GC.L["Store"])
  U.paintMove(row.take, data.toBags, GC.L["Take out"])
  -- Without the keep counts (a newer GoldCap's), Store is not offered; Take out keeps its place.
  row.store:SetShown(ctx.writable)
  row.head:ClearAllPoints()
  row.head:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.head:SetSize(width, headH)

  local height = headH
  if opened then height = paintOpen(row, data.group, ctx, headH) else closeOpen(row) end
  height = paintBar(row, data, height)
  row:SetHeight(height)
  return height
end

HF.Row = { New = newRow, Paint = paintRow }
