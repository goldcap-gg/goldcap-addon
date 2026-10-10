-- Surfaces: a flat panel, a rounded card, the main window's glass (T.Window, which the main
-- window uses), and the glow and shadow around them. Panel, Card and Glow moved out of UI/Theme.lua; Shadow and Window are new.
local _, GC = ...
GC.Theme = GC.Theme or {}
local T = GC.Theme
local MEDIA = GC.Kit.MEDIA
local K = GC.Kit.Tokens.color
-- A panel's and a card's default fill: the window's top colour, opaque.
local PANEL = { K.windowTop[1], K.windowTop[2], K.windowTop[3] }

-- Panel: flat dark texture + 1px border.
function T.Panel(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.bg = T.Solid(f, "BACKGROUND", PANEL)
  f.bg:SetAllPoints()
  T.EdgeBorder(f, K.glassBorder)
  return f
end

-- Card: rounded panel (fill + 1px ring). The rounded sibling of T.Panel; use
-- it for chrome that should read as a surface, keep T.Panel for flat fills.
-- `small`: use plaque.png/plaque_ring.png (radius 8, T.SLICE.plaque margins)
-- instead of card.png/ring.png (radius 12, T.SLICE.card margins) -- for chrome
-- small enough that the 24px card margins would overlap and notch.
function T.Card(parent, fill, border, small)
  local f = CreateFrame("Frame", nil, parent)
  local bgFile = small and (MEDIA .. "plaque.png") or (MEDIA .. "card.png")
  local ringFile = small and (MEDIA .. "plaque_ring.png") or (MEDIA .. "ring.png")
  local margin = small and T.SLICE.plaque or nil
  f.bg = T.SlicedTexture(f, "BACKGROUND", bgFile, fill or PANEL, margin)
  f.bg:SetAllPoints()
  f.ring = T.SlicedTexture(f, "BORDER", ringFile, border or K.glassBorder, margin)
  f.ring:SetAllPoints()
  function f:SetTint(fillC, borderC)
    if fillC then f.bg:SetVertexColor(fillC[1], fillC[2], fillC[3], fillC[4] or 1) end
    if borderC then f.ring:SetVertexColor(borderC[1], borderC[2], borderC[3], borderC[4] or 1) end
  end
  return f
end

-- Glow: additive halo hung `inset` px outside the parent's own rect. ADD
-- blend keeps it readable over any fill, same reasoning as HOVER_WASH.
function T.Glow(parent, c, inset)
  local pad = inset or 14
  -- Sublevel -7: below every fill (sublevel 0), above T.Shadow's -8, so a halo never brightens
  -- the face it surrounds.
  local tx = parent:CreateTexture(nil, "BACKGROUND", nil, -7)
  tx:SetTexture(MEDIA .. "glow.png")
  tx:SetBlendMode("ADD")
  tx:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  tx:SetPoint("TOPLEFT", -pad, pad)
  tx:SetPoint("BOTTOMRIGHT", pad, -pad)
  return tx
end

--- A small round light that says whether a process is alive, drawn on `parent`. SetState: "live"
-- (green, its halo breathing), "held" (amber, still), nil (out). The pulse is started once and
-- left running; a repaint four times a second does not restart it. Place it with :SetPoint, which
-- places the dot; the halo is centred on it.
function T.LiveDot(parent)
  local dot = parent:CreateTexture(nil, "OVERLAY")
  dot:SetTexture(MEDIA .. "badge.png") -- 16px at radius 6: round at this size
  dot:SetSize(7, 7)
  local halo = parent:CreateTexture(nil, "ARTWORK")
  halo:SetTexture(MEDIA .. "glow.png")
  halo:SetBlendMode("ADD")
  halo:SetSize(22, 22)
  halo:SetPoint("CENTER", dot, "CENTER", 0, 0)
  -- An Alpha animation sets the halo's own alpha, which replaces what SetVertexColor gave it (see
  -- T.RailButton), so the colour goes in at full alpha and the animation alone dims it.
  local pulse = halo:CreateAnimationGroup()
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(0.85)
  fade:SetToAlpha(0.15)
  fade:SetDuration(0.8)
  fade:SetSmoothing("IN_OUT")
  pulse:SetLooping("BOUNCE")

  local light = { dot = dot, halo = halo, pulse = pulse }
  function light:SetPoint(...) dot:SetPoint(...) end
  function light:SetState(state)
    if state == nil then
      pulse:Stop(); halo:Hide(); dot:Hide()
      return
    end
    local c = state == "held" and K.warn or K.profit
    dot:SetVertexColor(c[1], c[2], c[3], 1)
    dot:Show()
    if state == "live" then
      halo:SetVertexColor(c[1], c[2], c[3], 1)
      halo:Show()
      if not pulse:IsPlaying() then pulse:Play() end
    else
      pulse:Stop(); halo:Hide()
    end
  end
  light:SetState(nil)
  return light
end

--- A soft shadow hung `spread` px outside `frame`, below everything else the frame draws.
function T.Shadow(frame, spread, alpha)
  local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
  t:SetTexture(MEDIA .. "shadow.png")
  t:SetTextureSliceMargins(24, 24, 24, 24)
  t:SetVertexColor(0, 0, 0, alpha or 0.6)
  t:SetPoint("TOPLEFT", -spread, spread)
  t:SetPoint("BOTTOMRIGHT", spread, -spread)
  return t
end

-- The window's fill: card.png cut into nine plain pieces, so the middle row can carry a vertical
-- gradient while the top row stays flat in the top colour and the bottom row in the bottom one,
-- and the pieces meet without a seam. Not one sliced texture with SetGradient: no Blizzard code
-- sets a gradient on a sliced texture (both games' source, searched 2026-10-09), so how the
-- engine would spread it over the slices is unknown.
-- CORNER is how many px of the 64px card.png a corner piece shows, at 1:1. It must stay at least
-- the art's corner radius (12, docs/addon/tools/gen_art.py) or the curve is cut off.
local CORNER = 16
local CUT = CORNER / 64
-- Texture coordinates (left, right, top, bottom), row by row from the top left.
local PIECES = {
  { 0, CUT, 0, CUT }, { CUT, 1 - CUT, 0, CUT }, { 1 - CUT, 1, 0, CUT },
  { 0, CUT, CUT, 1 - CUT }, { CUT, 1 - CUT, CUT, 1 - CUT }, { 1 - CUT, 1, CUT, 1 - CUT },
  { 0, CUT, 1 - CUT, 1 }, { CUT, 1 - CUT, 1 - CUT, 1 }, { 1 - CUT, 1, 1 - CUT, 1 },
}
-- Each edge piece and the centre stretch between the two corners on either side of them:
-- { piece, corner its top left meets and where, corner its bottom right meets and where }.
local SPANS = {
  { 2, 1, "TOPRIGHT", 3, "BOTTOMLEFT" }, { 4, 1, "BOTTOMLEFT", 7, "TOPRIGHT" },
  { 5, 1, "BOTTOMRIGHT", 9, "TOPLEFT" }, { 6, 3, "BOTTOMLEFT", 9, "TOPRIGHT" },
  { 8, 7, "TOPRIGHT", 9, "BOTTOMLEFT" },
}

local function windowFill(f, top, bottom)
  local p = {}
  for i, coords in ipairs(PIECES) do
    p[i] = f:CreateTexture(nil, "BACKGROUND")
    p[i]:SetTexture(MEDIA .. "card.png")
    p[i]:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
  end
  for i, point in pairs({ [1] = "TOPLEFT", [3] = "TOPRIGHT", [7] = "BOTTOMLEFT", [9] = "BOTTOMRIGHT" }) do
    p[i]:SetPoint(point)
    p[i]:SetSize(CORNER, CORNER)
  end
  for _, s in ipairs(SPANS) do
    p[s[1]]:SetPoint("TOPLEFT", p[s[2]], s[3])
    p[s[1]]:SetPoint("BOTTOMRIGHT", p[s[4]], s[5])
  end
  for i = 1, 3 do p[i]:SetVertexColor(top[1], top[2], top[3], top[4]) end
  for i = 7, 9 do p[i]:SetVertexColor(bottom[1], bottom[2], bottom[3], bottom[4]) end
  -- SetGradient takes the bottom colour first (minColor) and the top second.
  local low = CreateColor(bottom[1], bottom[2], bottom[3], bottom[4])
  local high = CreateColor(top[1], top[2], top[3], top[4])
  for i = 4, 6 do p[i]:SetGradient("VERTICAL", low, high) end
  return p
end

--- The main window's surface: dark glass shading from top to bottom, a faint white edge, and a
-- soft shadow outside it, drawn by `window` itself over its whole rect. Returns the pieces.
--
-- Regions of the window, never a child frame: a child frame sits at the level every control in
-- the window gets (the window's plus one), and the client draws frames of one level layer by
-- layer together, so the glass's fill covered each button's own fill -- an active button's gold
-- plate -- and the window's own lines (seen in WoW: Forever, 2026-10-09). A frame's own regions
-- are under all of its children, whatever their levels.
function T.Window(window)
  local ring = T.SlicedTexture(window, "BORDER", MEDIA .. "ring.png", K.windowBorder, T.SLICE.card)
  ring:SetAllPoints()
  return { fill = windowFill(window, K.windowTop, K.windowBottom), ring = ring, shadow = T.Shadow(window, 18, 0.65) }
end

--- Slides `frame` in from the right as it opens, over 0.15 s, and back out as it shuts, over
-- 0.12 s, hiding it at the end. `place(dx)` anchors the frame `dx` px right of where it lives;
-- its alpha goes with it. Moved by its anchor and faded by SetAlpha a frame at a time, never by an
-- animation group: the coins in a figure are textures inside its text, and a Translation carried
-- the panel away from under coins that stayed where they were (owner, 2026-10-11). The steps run
-- on a frame of its own, so the frame's own OnUpdate is left alone.
--
-- Returns a slider. :Open() shows the frame and brings it in, from where it is if it was on its
-- way out. :Shut() takes it out, and a frame the client is not drawing simply goes. :Leaving()
-- is true while it is on its way out. :Settle() puts it home, hidden, at once.
function T.Slide(frame, place)
  local DX, IN_S, OUT_S = 24, 0.15, 0.12
  local away, goal = 0, 0 -- 0 home, 1 gone
  local driver = CreateFrame("Frame", nil, frame)
  local slider = {}
  -- The offset goes as the square: out slowly while it is still clear, in softly at the end.
  local function apply()
    place(DX * away * away)
    frame:SetAlpha(1 - away)
  end
  local function step(_, elapsed)
    local by = (elapsed or 0) / (goal == 1 and OUT_S or IN_S)
    away = goal == 1 and math.min(1, away + by) or math.max(0, away - by)
    apply()
    if away ~= goal then return end
    driver:SetScript("OnUpdate", nil)
    if goal == 1 then
      frame:Hide()
      away, goal = 0, 0
      apply()
    end
  end
  function slider:Open()
    if frame:IsShown() and goal == 0 then return end -- up already, or on its way in
    if not frame:IsShown() then away = 1 end
    goal = 0
    frame:Show()
    apply()
    driver:SetScript("OnUpdate", step)
  end
  function slider:Shut()
    if not frame:IsShown() or goal == 1 then return end
    if not frame:IsVisible() then slider:Settle() return end
    goal = 1
    driver:SetScript("OnUpdate", step)
  end
  function slider:Settle()
    driver:SetScript("OnUpdate", nil)
    away, goal = 0, 0
    apply()
    frame:Hide()
  end
  function slider:Leaving() return goal == 1 end
  return slider
end
