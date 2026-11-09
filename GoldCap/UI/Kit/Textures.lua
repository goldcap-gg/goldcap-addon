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
-- gradient, drawn untinted).
local TODAY = { card = { 12, "card.png" }, ring = { 12, "ring.png" },
  plaque = { 8, "plaque.png" }, plaqueRing = { 8, "plaque_ring.png" } }
local STEM = { card = "card_r", ring = "ring_r", plaque = "plaque_r", plaqueRing = "plaque_ring_r" }

function T.Art(kind, radius)
  local MEDIA = GC.Kit.MEDIA
  if kind == "bevel" then return MEDIA .. "bevel_" .. radius .. ".png" end -- `radius` is the skin's id
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
  local today = TODAY[kind]
  if today and today[1] == radius then
    return (kind == "card" or kind == "ring") and CARD_SLICE or PLAQUE_SLICE
  end
  return math.max(radius, 2)
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
