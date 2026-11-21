-- MY LOTS' sold side (Core/SoldLots.lua says what): the ring round a lot's icon with the share of it
-- sold, the SOLD SO FAR chip and its line, the SOLD OUT rows of lots sold out until their mail is
-- taken, the banner over the deck adding up what waits in the mailbox, and the quiet line under
-- it. Kept out of Row.lua and List.lua, which sit near Lua 5.1's limits: they call in here. A sold
-- row is never a position, so nothing here posts, cancels or opens anything.
local _, GC = ...

local Theme = GC.Theme
local S = GC.SellState
local UI = GC.SellUI
local ROW = UI.ROW
local setColor, formatCell, dimHex = UI.fmt.setColor, UI.fmt.cell, UI.fmt.dimHex
local itemName = GC.SellUtil.itemName

local Sold = {}
UI.Sold = Sold

-- The list entry kinds this file paints and styles (UI.List.RenderRows, Row.Style), and the ones
-- laid out as a card, a name over its stock line: a position, and a sold-out lot.
Sold.KINDS = { soldBanner = true, soldOut = true, soldFoot = true }
Sold.CARDED = { position = true, soldOut = true }

-- The ring: SEGMENTS short strokes round the icon, lit green clockwise from the top for the share
-- sold and dim for the rest, the track. Plain colour, no art: it is the same in every skin.
local SEGMENTS, RING_PAD = 32, 4
Sold.RING_PAD = RING_PAD
local BANNER_H, FOOT_H = 84, 30

local function green() return Theme.color.green end

local function money(amount) return "+" .. formatCell(amount) end

-- What a chip says and how wide it is: the kit's pill where there is one, else plain words.
local function setChip(chip, text, color)
  chip:SetLabel(text, color)
  chip.goldcapText = text
  if chip.text and chip.SetWidth then
    local w = chip.text.GetUnboundedStringWidth and chip.text:GetUnboundedStringWidth() or 0
    chip:SetWidth(math.max(40, math.ceil(w) + 2 * (Theme.pad and Theme.pad.s or 8)))
  end
end

local function makeChip(parent)
  if Theme.Chip then return Theme.Chip(parent) end
  local chip = Theme.Num(parent, 11)
  function chip.SetLabel(self, text, color) self:SetText(text); setColor(self, color) end
  return chip
end

-- The widgets a row needs for its sold part, made the first time it has one (a pooled row that is
-- only ever a TO POST row or a heading makes none): the ring, the chip and the line under it. The
-- line wraps onto a second line inside its column rather than widen it: at the default window a
-- column wide enough for "one sale · 51 min ago" on one line left no room for the item's name.
local function ensure(row)
  if row.soldNote then return end
  row.soldNote = Theme.Num(row, 9)
  row.soldNote:SetJustifyH("RIGHT")
  row.soldNote:SetWordWrap(true)
  row.soldNote:Hide()
  row.soldChip = makeChip(row)
  row.soldChip:Hide()
  local ring = { segments = {} }
  local radius = ROW.ICON / 2 + RING_PAD - 1.5
  for i = 1, SEGMENTS do
    local angle = (i - 0.5) / SEGMENTS * 2 * math.pi
    local seg = row:CreateTexture(nil, "OVERLAY")
    seg:SetSize(2, 4)
    seg:SetPoint("CENTER", row.icon, "CENTER", radius * math.sin(angle), radius * math.cos(angle))
    if seg.SetRotation then seg:SetRotation(-angle) end
    seg:Hide()
    ring.segments[i] = seg
  end
  ring.check = row:CreateTexture(nil, "OVERLAY")
  ring.check:SetSize(14, 14)
  ring.check:SetPoint("CENTER", row.icon, "BOTTOMRIGHT", -1, 1)
  ring.check:Hide()
  row.soldRing = ring
  -- The chip stands where SOLD SO FAR's figure would, its line under it (List.lua's SECOND_LINE).
  row.soldChip:SetPoint("RIGHT", row.cells.sold, "RIGHT", 0, 0)
end

--- MY LOTS' standing of a lot, for its stock line (Row.PaintPosition): "first in line" in green, or
-- "92 cheaper ahead of you" in amber, from where its average price stands in the live book
-- (GC.SellViewModel.Standing, the marks under the price). The row's own Cancel lot is how it is
-- reposted when the cancel queue finds it worth it. nil with no book.
function Sold.StandingText(position, listedQty)
  if not (type(position.listedValue) == "number" and listedQty > 0 and GC.SellViewModel.Standing) then return nil end
  local standing = GC.SellViewModel.Standing(position, math.floor(position.listedValue / listedQty))
  if not standing then return nil end
  if standing.ahead == 0 then return GC.Sell._InlineColor(green(), GC.L["first in line"]) end
  return GC.Sell._InlineColor(Theme.color.amber or Theme.color.gold, (GC.L["%s cheaper ahead of you"]):format(
    GC.Util.FormatCount(standing.ahead) or tostring(standing.ahead)))
end

-- `share` 0..1 lit, or nil for no ring; `done` puts the check mark on (sold out).
local function paintRing(row, share, done)
  local ring = row.soldRing
  if not ring then return end
  row.soldShare, row.soldDone = share, done or nil
  if share == nil then return end
  local lit = math.floor(share * SEGMENTS + 0.5)
  if share > 0 and lit == 0 then lit = 1 end
  local g, track = green(), Theme.color.fgDim
  for i, seg in ipairs(ring.segments) do
    if i <= lit then seg:SetColorTexture(g[1], g[2], g[3], 1)
    else seg:SetColorTexture(track[1], track[2], track[3], 0.35) end
  end
  if done and Theme.SetIcon then Theme.SetIcon(ring.check, "check", g) end
end

-- "one sale · 51 min ago", "3 sales", "nothing yet".
local function salesLine(sales, soldAt)
  if (sales or 0) == 0 then return GC.L["nothing yet"] end
  local words = sales == 1 and GC.L["one sale"] or (GC.L["%d sales"]):format(sales)
  local ago = GC.SoldLots.Ago(soldAt, time())
  return ago and (words .. " · " .. ago) or words
end

--- The sold side of MY LOTS this render (GC.SoldLots.Summary over S.soldLots), narrowed to the
-- group the GROUPS row picked. Kept for the rows to read; nil off MY LOTS.
function Sold.Summarize(onLots)
  Sold.summary = onLots and GC.SoldLots and GC.SoldLots.Summary(S.soldLots or {}, S.ownedLots or {},
    S.group and GC.Sell.InPickedGroup or nil) or nil
  return Sold.summary
end

--- How many sold rows the owned list holds: the badge on the MY LOTS deck button.
function Sold.Count()
  return GC.SoldLots and GC.SoldLots.Summary(S.soldLots or {}, S.ownedLots or {}).sales or 0
end

--- MY LOTS' line about a lot under its name: "28 of 48 sold · 20 left", or "48 listed · none sold yet".
function Sold.ListedText(position, listedQty)
  local sold = position.soldQty or 0
  if sold > 0 then return (GC.L["%d of %d sold · %d left"]):format(sold, listedQty + sold, listedQty) end
  return (GC.L["%d listed · none sold yet"]):format(listedQty)
end

--- A live position's sold part on MY LOTS (Row.PaintPosition): its ring, SOLD SO FAR's chip and
-- the line under it, from the summary's sold rows of the position's lots.
function Sold.PaintLive(row, position)
  ensure(row)
  local net, sales, soldAt = nil, 0, nil
  local byAuction = Sold.summary and Sold.summary.byAuction or {}
  for _, lot in ipairs(position.ownedLots or {}) do
    local part = byAuction[lot.auctionID]
    if part then
      sales = sales + part.sales
      if part.net then net = (net or 0) + part.net end
      if part.soldAt and (not soldAt or part.soldAt > soldAt) then soldAt = part.soldAt end
    end
  end
  local listed, sold = position.listedQty or 0, position.soldQty or 0
  paintRing(row, listed + sold > 0 and sold / (listed + sold) or 0, false)
  row.soldChipShown = net ~= nil
  if net then setChip(row.soldChip, money(net), green()) end
  row.soldNote:SetText(salesLine(sales, soldAt))
  setColor(row.soldNote, Theme.color.fgDim)
end

local function bannerBits(row)
  if row.soldBanner then return row.soldBanner end
  local bits = { chips = {} }
  bits.title = Theme.Num(row, 9, true)
  bits.title:SetJustifyH("LEFT")
  bits.title:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -12)
  bits.big = (Theme.Heading or Theme.Label)(row, 16)
  bits.big:SetJustifyH("LEFT")
  bits.big:SetPoint("TOPLEFT", bits.title, "BOTTOMLEFT", 0, -6)
  for i = 1, 2 do
    local chip = makeChip(row)
    if i == 1 then chip:SetPoint("TOPLEFT", bits.big, "BOTTOMLEFT", 0, -8)
    else chip:SetPoint("LEFT", bits.chips[1], "RIGHT", 6, 0) end
    bits.chips[i] = chip
  end
  bits.more = Theme.Num(row, 10)
  bits.more:SetJustifyH("LEFT")
  bits.more:SetPoint("LEFT", bits.chips[2], "RIGHT", 8, 0)
  row.soldBanner = bits
  return bits
end

local function footBits(row)
  if row.soldFoot then return row.soldFoot end
  local bits = {}
  bits.left = Theme.Num(row, 9)
  bits.left:SetJustifyH("LEFT")
  bits.left:SetPoint("LEFT", row, "LEFT", 14, 0)
  bits.right = Theme.Num(row, 9)
  bits.right:SetJustifyH("RIGHT")
  bits.right:SetPoint("RIGHT", row, "RIGHT", -14, 0)
  row.soldFoot = bits
  return bits
end

-- How wide SOLD SO FAR must be, by `width(size, text)` (UI/Sell/List.lua's FIT.width): for its line
-- to break into no more than two, the sales over the time, and for a chip of up to some 9,999g (its
-- condensed face draws "+9,999g 99s 99c" about as wide as the mono probe draws "+999g 99s 99c").
-- Measured on the fonts, at the default window this leaves the item's name its room once the price
-- column has squeezed to its minimum; a narrower window sheds the column (DECK_SHED).
function Sold.Need(width)
  return math.max(width(9, GC.L["nothing yet"]), width(9, GC.L["one sale"] .. " ·"),
    width(9, (GC.L["%d sales"]):format(99) .. " ·"), width(9, (GC.L["%d min ago"]):format(59)),
    width(9, (GC.L["%d h ago"]):format(99)), width(9, "+" .. formatCell(9999999)) + 16)
end

-- The search box, as it narrows every row: a plain substring of the lower-cased name.
local function matches(name)
  return not UI.chips.search or tostring(name or ""):lower():find(UI.chips.search, 1, true) ~= nil
end

--- The MY LOTS entries for the sold side, around `entries` (the live rows, already built):
-- the banner first, then the SOLD OUT heading and its rows, then the quiet line.
function Sold.PushEntries(entries)
  local summary = Sold.summary
  if not summary or summary.sales == 0 then return entries end
  local out = { { kind = "soldBanner", position = { itemID = 0 }, summary = summary } }
  for _, entry in ipairs(entries) do out[#out + 1] = entry end
  local shown = {}
  for _, sold in ipairs(summary.soldOut) do
    local name = itemName(sold.itemID)
    if matches(name) then
      shown[#shown + 1] = { kind = "soldOut", sold = sold,
        position = { itemID = sold.itemID, itemName = name, positionKey = sold.positionKey } }
    end
  end
  if #shown > 0 then
    out[#out + 1] = { kind = "section", position = shown[1].position,
      section = { id = "soldOut", positions = shown } }
    for _, entry in ipairs(shown) do out[#out + 1] = entry end
  end
  local lines = {}
  for _, position in ipairs(S.positions) do
    for _, lot in ipairs(position.ownedLots or {}) do
      lines[#lines + 1] = { qty = lot.quantity, unit = lot.unitPrice, position = position }
    end
  end
  out[#out + 1] = { kind = "soldFoot", position = { itemID = 0 }, listedNet = (GC.SellPositions.Proceeds(lines)) }
  return out
end

--- Fills one of this file's entries (UI.List.RenderRows), before Row.Style lays it out.
function Sold.Paint(row, entry)
  row.action:Hide()
  if entry.kind == "soldOut" then
    ensure(row)
    local sold = entry.sold
    local named = Theme.WithQuality and Theme.WithQuality(entry.position.itemName, sold.itemID)
      or entry.position.itemName
    row.cells.item:SetText(named)
    row.itemStock:SetText((GC.L["all %d sold · money in your mailbox"]):format(sold.soldQty))
    paintRing(row, 1, true)
    row.soldChipShown = sold.net ~= nil
    if sold.net then setChip(row.soldChip, money(sold.net), green()) end
    row.soldNote:SetText(salesLine(sold.sales, sold.soldAt))
    setColor(row.soldNote, Theme.color.fgDim)
  elseif entry.kind == "soldBanner" then
    local summary, bits = entry.summary, bannerBits(row)
    bits.title:SetText(summary.sales == 1 and GC.L["SINCE YOU LAST LOOKED · 1 SALE"]
      or (GC.L["SINCE YOU LAST LOOKED · %d SALES"]):format(summary.sales))
    setColor(bits.title, Theme.color.fgDim)
    bits.big:SetText(summary.net and (GC.L["%s waiting in your mailbox"]):format(money(summary.net))
      or GC.L["Waiting in your mailbox"])
    setColor(bits.big, green())
    for i, chip in ipairs(bits.chips) do
      local item = summary.chips[i]
      bits.chips[i].goldcapShown = item ~= nil
      if item then setChip(chip, itemName(item.itemID) .. "  " .. money(item.net), green()) end
    end
    bits.more:SetText(summary.more > 0 and (GC.L["+%d more"]):format(summary.more) or "")
    setColor(bits.more, Theme.color.fgDim)
  else
    local bits = footBits(row)
    bits.left:SetText(entry.listedNet and (GC.L["STILL ON THE AH %s after the 5%% cut"]):format(
      formatCell(entry.listedNet)) or "")
    setColor(bits.left, Theme.color.fgDim)
    bits.right:SetText(dimHex() .. GC.L["Sold-out lots leave once you open the mail"] .. "|r")
  end
end

--- The look of this file's kinds (Row.Style's branch for them): a sold-out lot is a card like a
-- position, dimmed, with no button; the banner a green-washed card; the footer bare.
function Sold.Style(row, entry)
  row.spine:Hide(); row.divider:Hide(); row.well:Hide()
  row.subItem:Hide(); row.sectionLabel:Hide(); row.sectionRule:Hide()
  row.action:Hide()
  if entry.kind == "soldOut" then
    row.zebra:Show(); row.cardRing:Show()
    row.cells.item:Show(); row.itemStock:Show()
    local icon
    if entry.position.itemID and C_Item and C_Item.GetItemIconByID then
      local ok, texture = pcall(C_Item.GetItemIconByID, entry.position.itemID)
      icon = ok and texture or nil
    end
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", 4 + RING_PAD, 0)
    row.itemInset = (icon and (ROW.ICON + 10) or 0) + RING_PAD
    if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end
    if row.SetAlpha then row:SetAlpha(0.6) end
    return
  end
  row.icon:Hide(); row.cells.item:Hide(); row.itemStock:Hide()
  row.itemInset = 2
  if entry.kind == "soldBanner" then
    local g = green()
    row.zebra:SetVertexColor(g[1], g[2], g[3], 0.08)
    row.zebra:Show(); row.cardRing:Show()
    row.fitHeight = BANNER_H
  else
    row.zebra:Hide(); row.cardRing:Hide()
    row.fitHeight = FOOT_H
  end
end

local function shown(widget, on)
  if not widget then return end
  if on then widget:Show() else widget:Hide() end
end

--- Shows this file's widgets on the rows they belong to and puts them away on every other: rows
-- are pooled, and a row that was a sold-out lot last render may be a heading now. The last word of
-- Row.Style, for every kind.
function Sold.Sync(row, entry)
  local kind = entry.kind
  local live = kind == "position" and not entry.panel and Sold.summary ~= nil
    and (entry.position.listedQty or 0) > 0
  local soldSide = live or kind == "soldOut"
  -- The column a narrow window sheds (UI/Sell/List.lua's DECK_SHED) takes its chip and line with it.
  local column = soldSide and row.cells.sold:IsShown()
  shown(row.soldNote, column)
  shown(row.soldChip, column and row.soldChipShown)
  if column then
    -- Hung from the middle of the row down, so a second line grows down the card, clear of the chip.
    row.soldNote:ClearAllPoints()
    row.soldNote:SetPoint("TOPLEFT", row.cells.sold, "LEFT", 0, -ROW.LIFT - 2)
    row.soldNote:SetPoint("TOPRIGHT", row.cells.sold, "RIGHT", 0, -ROW.LIFT - 2)
  end
  local ring = row.soldRing
  if ring then
    local share = soldSide and row.soldShare or nil
    for _, seg in ipairs(ring.segments) do shown(seg, share ~= nil and row.icon:IsShown()) end
    shown(ring.check, kind == "soldOut" and row.soldDone and row.icon:IsShown() and Theme.SetIcon ~= nil)
  end
  local banner = row.soldBanner
  if banner then
    shown(banner.title, kind == "soldBanner"); shown(banner.big, kind == "soldBanner")
    shown(banner.more, kind == "soldBanner")
    for _, chip in ipairs(banner.chips) do shown(chip, kind == "soldBanner" and chip.goldcapShown) end
  end
  if row.soldFoot then shown(row.soldFoot.left, kind == "soldFoot"); shown(row.soldFoot.right, kind == "soldFoot") end
end
