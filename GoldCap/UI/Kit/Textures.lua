-- Solid fills, the rounded white art sliced to any size, and the icon atlas. Every file is white
-- art tinted in code (SetVertexColor), so one file serves every colour; docs/addon/tools/gen_art.py
-- and gen_icons.py (wow-auction) draw them. Moved out of UI/Theme.lua; the slicing rules are its own.
local _, GC = ...
GC.Theme = GC.Theme or {}
local T = GC.Theme

-- Rounded chrome comes from ONE white 64px rounded-rect PNG stretched with
-- SetTextureSliceMargins (nine-slice on a single texture, 10.2.0+ -- wiki:
-- API_TextureBase_SetTextureSliceMargins) and recolored via SetVertexColor.
-- White art + vertex color means one file serves every tint; regenerate the
-- PNGs with the project's gen_art.py, never edit them by hand. Margins are 24
-- of the 64px file so the 12px corners survive any widget size.
local CARD_SLICE = 24
-- Small-radius sibling for plaque.png/plaque_ring.png (32px, radius 8), used
-- for chrome like the 32px rail logo. Margins must stay below half the
-- smallest widget edge they're applied to, or nine-slice corners overlap and
-- notch -- which is also why the 14px badge below gets its own BADGE_SLICE
-- rather than reusing this one (12 is not below half of 14).
local PLAQUE_SLICE = 12
-- badge.png (16px, radius 6): the rail-button badge is only 14px tall, so
-- even PLAQUE_SLICE (12) would exceed half its smallest edge (7) and notch
-- it. 6 < 14/2 satisfies the margin invariant above.
local BADGE_SLICE = 6

T.SLICE = { card = CARD_SLICE, plaque = PLAQUE_SLICE, badge = BADGE_SLICE }

-- The art for a shape at a radius. Today's radii keep today's files (card.png and ring.png at 12,
-- plaque.png and plaque_ring.png at 8); every other radius a skin uses has a file of its own, drawn
-- by gen_art.py: card_r<N>.png and ring_r<N>.png (64px), plaque_r<N>.png and plaque_ring_r<N>.png
-- (32px), and bevel_<skin>.png (a bevel skin's window ring, baked in colour from the skin's frame
-- gradient, drawn untinted), plate_<skin>.png (a plate skin's ring for rail buttons, tabs and buttons,
-- baked the same way).
local TODAY = { card = { 12, "card.png" }, ring = { 12, "ring.png" },
  plaque = { 8, "plaque.png" }, plaqueRing = { 8, "plaque_ring.png" } }
local STEM = { card = "card_r", ring = "ring_r", plaque = "plaque_r", plaqueRing = "plaque_ring_r" }

function T.Art(kind, radius)
  local MEDIA = GC.Kit.MEDIA
  if kind == "bevel" or kind == "plate" then return MEDIA .. kind .. "_" .. radius .. ".png" end -- `radius` is the skin's id
  local today = TODAY[kind]
  if today and today[1] == radius then return MEDIA .. today[2] end
  return MEDIA .. STEM[kind] .. radius .. ".png"
end

--- The slice margin that goes with T.Art(kind, radius): today's files keep today's margins, any other
-- file the radius, at least 2 (a radius of 0 still needs a margin), and every use stays under half
-- its smallest edge. A bevel ring's margin also covers its whole band: the outline pixel, `width`
-- and the inner line.
function T.ArtSlice(kind, radius, width)
  if kind == "bevel" then return math.max(radius, math.ceil((width or 0) + 2), 2) end
  -- A plate ring is its outline and its `width` band, nothing inside.
  if kind == "plate" then return math.max(radius, 1 + (width or 0), 2) end
  local today = TODAY[kind]
  if today and today[1] == radius then
    return (kind == "card" or kind == "ring") and CARD_SLICE or PLAQUE_SLICE
  end
  return math.max(radius, 2)
end

--- The fill, the ring and the slice margin of a small control (a chip, a badge-class button) at
-- `radius`, the margin at most `cap` so it stays under half the control's height. Radius 6 is
-- today's badge.png and badge_ring.png, which goldcap's controls keep; any other radius is the
-- plaque art cut at it.
function T.SmallArt(radius, cap)
  local MEDIA = GC.Kit.MEDIA
  if radius == 6 then return MEDIA .. "badge.png", MEDIA .. "badge_ring.png", T.SLICE.badge end
  return T.Art("plaque", radius), T.Art("plaqueRing", radius), math.min(T.ArtSlice("plaque", radius), cap)
end

-- A plate ring's band, in px, inside its 1px outline (docs/addon/tools/gen_art.py PLATE_BAND).
local PLATE_BAND = 2

-- Classic's art is the client's own, by path (we ship none of it). Each piece: its file, the part of
-- the file that is the art as texture coordinates (left, right, top, bottom; the file's size is in
-- the comment), and the slice margins (left, top, right, bottom) it stretches by.
local function crop(w, h, x1, y1, x2, y2) return { x1 / w, x2 / w, y1 / h, y2 / h } end
T.CLASSIC = {
  marble = "Interface\\FrameGeneral\\UI-Background-Marble",
  goldBorder = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  goldHeader = "Interface\\DialogFrame\\UI-DialogBox-Gold-Header",
  headerCoords = crop(256, 64, 58, 0, 197, 40), -- 256x64
  tooltipBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
  nameFrame = { file = "Interface\\AuctionFrame\\UI-AuctionItemNameFrame", coords = crop(128, 32, 0, 0, 106, 32), -- 128x32
    slice = { 8, 8, 8, 8 } },
  quickslot = { file = "Interface\\Buttons\\UI-Quickslot2", coords = crop(64, 64, 12, 12, 51, 51),
    slice = { 6, 6, 6, 6 } },
  hilight = "Interface\\Buttons\\CheckButtonHilight",
  checkHover = "Interface\\Buttons\\UI-CheckBox-Highlight",
  checkBox = "Interface\\Buttons\\UI-CheckBox-Up",
  checkMark = "Interface\\Buttons\\UI-CheckBox-Check",
  panelButton = { file = "Interface\\Buttons\\UI-Panel-Button-Up", coords = crop(128, 32, 0, 0, 80, 22),
    slice = { 10, 5, 10, 5 } },
  -- The rail's icons: item icons both clients have.
  icons = { deals = "Interface\\Icons\\INV_Misc_Spyglass_02", sell = "Interface\\Icons\\INV_Misc_Bag_10",
    sold = "Interface\\Icons\\INV_Misc_Coin_02", buy = "Interface\\Icons\\INV_Scroll_03",
    gear = "Interface\\Icons\\INV_Misc_Gear_01" },
}

--- What the applied skin frames its rail buttons, tabs and buttons with, or nil when it frames none:
-- { ring = the baked ring (vertex colour white), ringSlice, fill = plaque art at the control radius,
-- fillSlice (also the corner of the gradient cut from it) }. Classic's are the client's textures
-- (T.CLASSIC), which each control draws itself: { client = true }.
function T.Plate()
  local skin = GC.Kit.Skins.Current()
  if skin.frame == "classic" then return { client = true } end
  if not (skin.plates and skin.plateArt) then return nil end
  local radius = skin.radius[3]
  return { ring = T.Art("plate", skin.id), ringSlice = T.ArtSlice("plate", radius, PLATE_BAND),
    fill = T.Art("plaque", radius), fillSlice = T.ArtSlice("plaque", radius) }
end

--- Classic's piece `art` (an entry of T.CLASSIC with a crop and slices) as a texture of `parent`, in
-- its own colours, stretched by its slice margins.
function T.ClientSliced(parent, layer, art, sublevel)
  local tx = parent:CreateTexture(nil, layer, nil, sublevel)
  tx:SetTexture(art.file)
  tx:SetTexCoord(art.coords[1], art.coords[2], art.coords[3], art.coords[4])
  tx:SetTextureSliceMargins(art.slice[1], art.slice[2], art.slice[3], art.slice[4])
  tx:SetVertexColor(1, 1, 1, 1) -- untinted
  return tx
end

--- The client's quickslot frame round an item icon (a texture), or nil in a skin that has none. It
-- is a texture of its own: the caller shows and hides it with the icon.
function T.IconFrame(icon, parent)
  if GC.Kit.Skins.Current().frame ~= "classic" then return nil end
  local frame = T.ClientSliced(parent, "OVERLAY", T.CLASSIC.quickslot)
  frame:SetAllPoints(icon)
  return frame
end

--- The plate of a list row (the client's auction name frame), or nil in a skin that has none.
function T.RowPlate(parent)
  if GC.Kit.Skins.Current().frame ~= "classic" then return nil end
  return T.ClientSliced(parent, "BACKGROUND", T.CLASSIC.nameFrame, -1)
end

--- A panel in the client's tooltip border over the popup colour (#10101f in Classic), drawn 14px, or
-- nil in a skin that has none. A frame of its own (a backdrop is one) on its parent's level, so the
-- parent's own text and the controls above it draw over it. `alpha` is the fill's, 1 by default.
function T.ClientPanel(parent, alpha)
  if GC.Kit.Skins.Current().frame ~= "classic" then return nil end
  local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  panel:SetUsingParentLevel(true)
  local c = GC.Kit.Tokens.color.popup
  panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = T.CLASSIC.tooltipBorder, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  panel:SetBackdropColor(c[1], c[2], c[3], alpha or 1)
  return panel
end

--- A solid colour fill.
function T.Solid(parent, layer, c)
  local tx = parent:CreateTexture(nil, layer)
  tx:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  return tx
end

--- A 1px outline of four solid edges, in colour `c`, drawn on the BORDER layer of `f`.
function T.EdgeBorder(f, c)
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local e = T.Solid(f, "BORDER", c)
    if side == "TOP" or side == "BOTTOM" then
      e:SetPoint(side .. "LEFT")
      e:SetPoint(side .. "RIGHT")
      e:SetHeight(1)
    else
      e:SetPoint("TOP" .. side)
      e:SetPoint("BOTTOM" .. side)
      e:SetWidth(1)
    end
  end
end

local function slicedTexture(parent, layer, file, c, margin)
  local m = margin or CARD_SLICE
  local tx = parent:CreateTexture(nil, layer)
  tx:SetTexture(file)
  tx:SetTextureSliceMargins(m, m, m, m)
  tx:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  return tx
end

-- SlicedTexture: public wrapper around slicedTexture (default margin CARD_SLICE).
function T.SlicedTexture(parent, layer, file, c, margin)
  return slicedTexture(parent, layer, file, c, margin)
end

--- The texture coordinates of icon `name` in the atlas (UI/Kit/Icons.lua). An unknown name is a
-- typo in GoldCap's own code, so it errors rather than drawing nothing.
function T.IconCoords(name)
  local icons = GC.Kit.Icons
  local index = icons.index[name]
  if not index then error("GoldCap: no icon named " .. tostring(name), 2) end
  local step = icons.cell / icons.size
  local col, row = index % icons.columns, math.floor(index / icons.columns)
  return col * step, (col + 1) * step, row * step, (row + 1) * step
end

--- Draws icon `name` on `texture`, tinted `color` when given.
function T.SetIcon(texture, name, color)
  texture:SetTexture(GC.Kit.Icons.file)
  texture:SetTexCoord(T.IconCoords(name))
  if color then texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
end
