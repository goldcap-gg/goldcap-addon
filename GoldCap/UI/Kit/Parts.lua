-- The parts GoldCap's windows beside Blizzard's draw with (Theme.Parts): the GoldCap Hoard
-- (UI/HoardFrame.lua, UI/HoardRow.lua, UI/HoardFooter.lua, retail only), Disenchant and Send to alts
-- (retail only), and the crafting panel beside the profession window (UI/CraftPanel.lua and
-- UI/CraftQueueView.lua, both games). Moved here unchanged out of the Hoard's files, which still
-- hand them on under their old names (HF.ui, HF.Row, HF.Footer), so the crafting panel looks the
-- same on WoW: Forever, where none of the Hoard loads.
--
-- Text lines that wrap and redraw on a re-show (docs/addon/AGENTS.md "Text"), a quiet clickable
-- plate, a switch's sunken track, the GoldCap mark and brand, an item's icon with its count, its
-- quality pip and a run's marks, and the price line's dot and words. Each is called after
-- UI/Theme.lua has loaded: this file reads only the kit's tokens as it loads.
local _, GC = ...
GC.Theme = GC.Theme or {}
local K = GC.Kit.Tokens.color

GC.Theme.Parts = {}
local KP = GC.Theme.Parts

-- The sunken track of a two-way switch, the bank switch's and the search row's filter
-- (UI/HoardList.lua): black at 0.35 under the glass, as the boards draw it; the kit has no token for
-- it.
local SWITCH_TRACK = { 0, 0, 0, 0.35 } -- untinted
-- An icon with no quality colour edged dark.
local ICON_EDGE = { 0, 0, 0, 0.75 } -- untinted
-- An icon whose item has moved in the run: shaded in the window's own dark under the check, as
-- the board draws it.
local MOVED_SHADE = GC.Kit.Tokens.alpha("windowBottom", 0.6)
-- The sizes an item's count over its icon tries, largest first, so it fits inside the icon.
local COUNT_SIZES = { 8, 7, 6 }
-- In UI units: the check a moved item's icon wears, and the price line's dot and the room right of
-- it.
local MARK, DOT, DOT_GAP = 9, 6, 5
KP.DOT, KP.DOT_GAP = DOT, DOT_GAP

function KP.heightOf(fs, fallback)
  local h = fs.GetStringHeight and fs:GetStringHeight()
  return type(h) == "number" and h or fallback
end
local heightOf = KP.heightOf

function KP.colour(fs, c)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end
local colour = KP.colour

-- SetText with the text a FontString already holds does not redraw it (docs/addon/AGENTS.md
-- "Text"): clear first.
function KP.setText(fs, text)
  fs:SetText("")
  fs:SetText(text or "")
end
local setText = KP.setText

-- A line that wraps, at word breaks and, for a name with none (a Chinese one, or one long German
-- word), anywhere.
function KP.wrapping(fs)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  fs:SetNonSpaceWrap(true)
  return fs
end
local wrapping = KP.wrapping

-- Every FontString a frame of the window draws in (`owner`: the window, a row, the handle), so a
-- re-show can redraw them all (restamp).
function KP.track(owner, fs)
  owner.texts = owner.texts or {}
  owner.texts[#owner.texts + 1] = fs
  return fs
end
local track = KP.track

-- docs/addon/AGENTS.md "Text", measured in game: a one-line FontString whose frame or a parent was
-- hidden and shown again can come back with its text not drawn, and SetText with the text it holds
-- does not redraw it. The cure is clear, set, hide, show, on every re-show: here for each of
-- `owner`'s lines that shows.
function KP.restamp(owner)
  for _, fs in ipairs(owner.texts or {}) do
    if fs:IsShown() then
      local text = fs:GetText()
      fs:SetText("")
      fs:SetText(text or "")
      fs:Hide()
      fs:Show()
    end
  end
end

function KP.hideTip()
  if _G.GameTooltip then _G.GameTooltip:Hide() end
end

-- A switch's sunken track in the glass's border, over the whole of `switch`: the Hoard's switches
-- and the crafting panel's tabs (UI/CraftPanel.lua).
-- `plated`: the switch's tabs are plaque-class buttons, which a skin that frames its tabs
-- (Theme.Plate) gives each a plate of its own, so it draws no track. The crafting panel's badge-class
-- tabs are never plated and keep the track in every skin.
function KP.sunkenTrack(switch, plated)
  local T = GC.Theme
  if plated and T.Plate() then return end
  switch.track = T.ShapeTexture(switch, "BACKGROUND", "control", SWITCH_TRACK)
  switch.track:SetAllPoints(switch)
  switch.edge = T.ShapeTexture(switch, "BORDER", "control", K.glassBorder, true)
  switch.edge:SetAllPoints(switch)
end

-- The kit's rounded art a plate is cut from, by its size class: plaque (the control shape) for a
-- widget taller than twice its 12px slice, badge (the chip shape, 6px) for one down to 13px
-- (UI/Kit/Textures.lua's slice rule), each at the applied skin's radius for it (Theme.Shape).
local PLATE_ROLE = { plaque = "control", badge = "chip" }

-- A quiet clickable plate: a ring when asked, and the engine's gold wash under the cursor.
function KP.plate(parent, ring, art)
  local T = GC.Theme
  local role = PLATE_ROLE[art]
  local b = CreateFrame("Button", nil, parent)
  b:RegisterForClicks("LeftButtonUp")
  -- Required for the HIGHLIGHT layer (docs/addon/AGENTS.md "Buttons and hover").
  b:EnableMouse(true)
  if ring then
    b.ring = T.ShapeTexture(b, "BORDER", role, ring, true)
    b.ring:SetAllPoints()
  end
  b.wash = T.ShapeTexture(b, "HIGHLIGHT", role, K.hoverWash)
  b.wash:SetAllPoints()
  b.wash:SetBlendMode("ADD")
  return b
end

-- The GoldCap mark on `f` (f.logo, `logo` square, full colour as the rail and the welcome window
-- draw it) and the brand `gap` right of it (f.brand, `size` points, among f's lines for the
-- re-show), in the condensed heavy face whatever the language: it is the name, written in Latin. A
-- skin with a heading face of its own writes it in that (T.FONT_BRAND).
-- The caller places the mark: a window's header (UI/HoardFrame.lua's newHeader), and the crafting
-- panel's (UI/CraftPanel.lua).
function KP.newBrand(f, logo, size, gap)
  local T = GC.Theme
  f.logo = f:CreateTexture(nil, "ARTWORK")
  f.logo:SetTexture(T.MEDIA .. "GoldCap")
  f.logo:SetSize(logo, logo)
  f.brand = track(f, f:CreateFontString(nil, "OVERLAY"))
  if T.ClientFonts() and T.UseClientFont(f.brand, size) then
    T.TrackFont(f.brand, { role = "brand", size = size, object = true }) -- the client's own face
  else
    f.brand:SetFont(T.FONT_BRAND, size * T.Scale(), "")
    T.TrackFont(f.brand, { role = "brand", path = T.FONT_BRAND, size = size })
  end
  f.brand:SetWordWrap(false)
  colour(f.brand, K.goldText)
  f.brand:SetPoint("LEFT", f.logo, "RIGHT", gap, 0)
end

-- ---------------------------------------------------------------------------------------------
-- An item's icon
-- ---------------------------------------------------------------------------------------------

-- A count over an item's icon: the condensed heavy face with an outline, as the game writes a
-- stack's count over its slot. Fira in every skin (a number, and smaller than a display face goes).
local function countText(parent, size)
  local T = GC.Theme
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(T.FONT_HEAD_HEAVY, size * T.Scale(), "OUTLINE")
  T.TrackFont(fs, { role = "count", path = T.FONT_HEAD_HEAVY, size = size, flags = "OUTLINE" })
  fs:SetJustifyH("RIGHT")
  fs:SetWordWrap(false)
  return fs
end

-- A count drawn inside its icon, `iconSize` wide, in from the icon's 1px edge: at the largest of
-- COUNT_SIZES it fits at, else in whole thousands ("1k" for 1.2k) at the smallest, else not at all
-- (the opened row still says it in full).
local function fitCount(fs, count, iconSize)
  local T = GC.Theme
  local text = count and GC.Util.FormatCount(count) or ""
  local room = iconSize - 2
  for _, candidate in ipairs({ text, (text:gsub("%.%d", "")) }) do
    for _, size in ipairs(COUNT_SIZES) do
      fs:SetFont(T.FONT_HEAD_HEAVY, size * T.Scale(), "OUTLINE")
      T.TrackFont(fs, { role = "count", path = T.FONT_HEAD_HEAVY, size = size, flags = "OUTLINE" })
      setText(fs, candidate)
      if (fs:GetStringWidth() or 0) <= room then return end
    end
  end
  setText(fs, "")
end

-- An item's icon in a 1px edge in its quality's colour (common and poor: a dark edge), the game's
-- own border cut off the art; with a count over it when `counted`. A run's marks: a ring 1px out
-- round the edge, which turns gold with it, while a stack of the item is on its way; the kit's
-- check over the shaded icon once one has moved.
function KP.NewIcon(row, size, counted)
  local T = GC.Theme
  local edge = row:CreateTexture(nil, "BORDER")
  edge:SetSize(size, size)
  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local count = counted and track(row, countText(row, COUNT_SIZES[1])) or nil
  if count then count:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", 0, 1) end
  local ring = row:CreateTexture(nil, "BORDER", nil, -1)
  ring:SetColorTexture(K.goldText[1], K.goldText[2], K.goldText[3], 1)
  ring:SetPoint("TOPLEFT", edge, "TOPLEFT", -1, 1)
  ring:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", 1, -1)
  local shade = T.Solid(row, "OVERLAY", MOVED_SHADE)
  shade:SetAllPoints(icon)
  local mark = row:CreateTexture(nil, "OVERLAY", nil, 1)
  mark:SetSize(MARK, MARK)
  mark:SetPoint("CENTER", edge, "CENTER", 0, 0)
  T.SetIcon(mark, "check", K.profit)
  local pip = row:CreateTexture(nil, "OVERLAY", nil, 2)
  pip:SetSize(math.floor(size / 3), math.floor(size / 3))
  pip:SetPoint("TOPLEFT", edge, "TOPLEFT", 0, 0)
  local slot = { edge = edge, icon = icon, count = count, ring = ring, shade = shade, mark = mark, pip = pip, size = size }
  for _, part in ipairs({ ring, shade, mark, pip }) do part:Hide() end
  return slot
end

-- `mark`: the run's for the item (UI/HoardList.lua's RunState), "moving", "moved" or nil. `opts`
-- (optional): `pip`, the item's crafting quality top left over the icon, nothing for an item
-- without one; `link`, the item's link, with which crafted gear's quality is asked
-- (Theme.QualityAtlas).
function KP.PaintIcon(slot, itemID, file, count, mark, opts)
  local T = GC.Theme
  local quality = T.QualityColor(itemID)
  local c = quality and { quality.r, quality.g, quality.b, 1 } or ICON_EDGE
  if mark == "moving" then c = K.goldText end
  slot.edge:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  slot.icon:SetTexture(file or 134400) -- the question mark, while the client has no icon for it yet
  slot.edge:Show()
  slot.icon:Show()
  if slot.count then
    fitCount(slot.count, count, slot.size)
    slot.count:Show()
  end
  slot.ring:SetShown(mark == "moving")
  slot.shade:SetShown(mark == "moved")
  slot.mark:SetShown(mark == "moved")
  local atlas = opts and opts.pip and T.QualityAtlas(itemID, opts.link)
  if atlas then slot.pip:SetAtlas(atlas) end
  slot.pip:SetShown(atlas ~= nil)
end

function KP.HideIcon(slot)
  for _, part in ipairs({ slot.edge, slot.icon, slot.ring, slot.shade, slot.mark, slot.pip }) do part:Hide() end
  if slot.count then slot.count:Hide() end
end

-- ---------------------------------------------------------------------------------------------
-- The price line
-- ---------------------------------------------------------------------------------------------

--- The price line on `f`: its dot (f.dot) and its words (f.prices, wrapping, among `owner`'s lines
--- for the re-show), as the Hoard's footer, the Disenchant window's and the crafting panel's draw it.
function KP.NewPriceLine(f, owner)
  local T = GC.Theme
  -- The badge art is round at this size (T.LiveDot draws its light the same way).
  f.dot = f:CreateTexture(nil, "ARTWORK")
  f.dot:SetTexture(T.MEDIA .. "badge.png")
  f.dot:SetSize(DOT, DOT)
  f.prices = track(owner, wrapping(T.Label(f, 9)))
  colour(f.prices, K.text3)
end

--- The price line NewPriceLine built on `f`, along f's foot from `x` in and `y` up, `w` wide with
--- its dot, saying `text`: the words wrapped right of the dot, the dot level with their last line
--- (both stand on the foot) in the kit's green while the prices are `fresh`, amber after or with
--- none. Where the words come from is the caller's (UI/HoardFooter.lua's PricesNow on retail).
--- Answers its height.
function KP.PaintPriceLine(f, x, y, w, text, fresh)
  f.prices:SetWidth(w - DOT - DOT_GAP)
  setText(f.prices, text)
  local c = fresh and K.profit or K.warn
  f.dot:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  local h = math.ceil(heightOf(f.prices, 12))
  f.prices:ClearAllPoints()
  f.prices:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x + DOT + DOT_GAP, y)
  f.dot:ClearAllPoints()
  f.dot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, y + math.floor((math.min(h, 12) - DOT) / 2))
  return h
end
