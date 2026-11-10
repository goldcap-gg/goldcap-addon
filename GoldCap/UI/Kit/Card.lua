-- Surfaces: a flat panel, a rounded card, the main window's glass (T.Window, which the main
-- window uses), and the glow and shadow around them. Panel, Card and Glow moved out of UI/Theme.lua; Shadow and Window are new.
local _, GC = ...
GC.Theme = GC.Theme or {}
local T = GC.Theme
local MEDIA = GC.Kit.MEDIA
local K = GC.Kit.Tokens.color
-- A panel's and a card's default fill: the window's top colour, opaque.
local PANEL = GC.Kit.Tokens.rgb("windowTop")

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
-- instead of the panel art -- for chrome small enough that the card margins would overlap and
-- notch. The panel art is the applied skin's panel radius: card.png/ring.png at 12 (goldcap).
function T.Card(parent, fill, border, small)
  local f = CreateFrame("Frame", nil, parent)
  local bgFile, ringFile, margin
  if small then
    bgFile, ringFile, margin = MEDIA .. "plaque.png", MEDIA .. "plaque_ring.png", T.SLICE.plaque
  else
    local radius = GC.Kit.Skins.Current().radius[2]
    bgFile, ringFile, margin = T.Art("card", radius), T.Art("ring", radius), T.ArtSlice("card", radius)
  end
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
  t:SetVertexColor(0, 0, 0, alpha or 0.6) -- untinted
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
-- the art's corner radius (12 at most, docs/addon/tools/gen_art.py) or the curve is cut off.
local CORNER = 16
-- Texture coordinates (left, right, top, bottom), row by row from the top left, for a corner
-- piece `cut` of the file wide.
local function piecesFor(cut)
  return {
    { 0, cut, 0, cut }, { cut, 1 - cut, 0, cut }, { 1 - cut, 1, 0, cut },
    { 0, cut, cut, 1 - cut }, { cut, 1 - cut, cut, 1 - cut }, { 1 - cut, 1, cut, 1 - cut },
    { 0, cut, 1 - cut, 1 }, { cut, 1 - cut, 1 - cut, 1 }, { 1 - cut, 1, 1 - cut, 1 },
  }
end
-- Each edge piece and the centre stretch between the two corners on either side of them:
-- { piece, corner its top left meets and where, corner its bottom right meets and where }.
local SPANS = {
  { 2, 1, "TOPRIGHT", 3, "BOTTOMLEFT" }, { 4, 1, "BOTTOMLEFT", 7, "TOPRIGHT" },
  { 5, 1, "BOTTOMRIGHT", 9, "TOPLEFT" }, { 6, 3, "BOTTOMLEFT", 9, "TOPRIGHT" },
  { 8, 7, "TOPRIGHT", 9, "BOTTOMLEFT" },
}

--- Colours the nine pieces of a gradient fill: the top row `top`, the bottom row `bottom`, the
--- middle row a vertical gradient between them.
function T.PaintGradientFill(p, top, bottom)
  for i = 1, 3 do p[i]:SetVertexColor(top[1], top[2], top[3], top[4] or 1) end
  for i = 7, 9 do p[i]:SetVertexColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1) end
  -- SetGradient takes the bottom colour first (minColor) and the top second.
  local low = CreateColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1)
  local high = CreateColor(top[1], top[2], top[3], top[4] or 1)
  for i = 4, 6 do p[i]:SetGradient("VERTICAL", low, high) end
end

--- A vertical gradient fill on `f` in `layer`, cut from `file`: a `size`px square (64 for card art,
--- 32 for plaque art) whose corners are `corner` px at 1:1.
function T.GradientFill(f, top, bottom, file, corner, size, layer)
  corner, size = corner or CORNER, size or 64
  local p = {}
  for i, coords in ipairs(piecesFor(corner / size)) do
    p[i] = f:CreateTexture(nil, layer or "BACKGROUND")
    p[i]:SetTexture(file)
    p[i]:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
  end
  for i, point in pairs({ [1] = "TOPLEFT", [3] = "TOPRIGHT", [7] = "BOTTOMLEFT", [9] = "BOTTOMRIGHT" }) do
    p[i]:SetPoint(point)
    p[i]:SetSize(corner, corner)
  end
  for _, s in ipairs(SPANS) do
    p[s[1]]:SetPoint("TOPLEFT", p[s[2]], s[3])
    p[s[1]]:SetPoint("BOTTOMRIGHT", p[s[4]], s[5])
  end
  T.PaintGradientFill(p, top, bottom)
  return p
end

local WINDOW_PIECES = piecesFor(CORNER / 64)
local function windowFill(f, top, bottom, file)
  return T.GradientFill(f, top, bottom, file, CORNER, 64)
end

-- The ornament a skin draws on its window, as a list of regions. `inside`: kept clear of the edge,
-- for a window against a Blizzard frame. Positions are the mock's (.sk-<id> .gcw > .orn), but for
-- the middle rivets, which the mock clips at the edge and are drawn 2px out.
local function ornamentOf(window, kind, inside)
  local list = {}
  local function add(layer)
    local t = window:CreateTexture(nil, layer or "ARTWORK")
    list[#list + 1] = t
    return t
  end
  if kind == "rivets" then
    -- Four in the corners, one on the middle of the top and bottom edges.
    local spots = { { "TOPLEFT", 0, 0 }, { "TOPRIGHT", 0, 0 }, { "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", 0, 0 },
      { "TOP", 0, inside and 0 or 2 }, { "BOTTOM", 0, inside and 0 or -2 } }
    for _, spot in ipairs(spots) do
      local t = add()
      t:SetTexture(MEDIA .. "rivet.png")
      t:SetSize(12, 12)
      t:SetPoint(spot[1], window, spot[1], spot[2], spot[3])
    end
  elseif kind == "brackets" then
    -- bracket.png is the top left L; the other corners flip it.
    local spots = { { "TOPLEFT", 6, -6, 0, 1, 0, 1 }, { "TOPRIGHT", -6, -6, 1, 0, 0, 1 },
      { "BOTTOMLEFT", 6, 6, 0, 1, 1, 0 }, { "BOTTOMRIGHT", -6, 6, 1, 0, 1, 0 } }
    for _, spot in ipairs(spots) do
      local t = add()
      t:SetTexture(MEDIA .. "bracket.png")
      t:SetSize(32, 32)
      t:SetPoint(spot[1], window, spot[1], spot[2], spot[3])
      t:SetTexCoord(spot[4], spot[5], spot[6], spot[7])
      t:SetVertexColor(K.goldText[1], K.goldText[2], K.goldText[3], 1)
    end
  elseif kind == "shimmer" then
    -- Two lines, centred: 70% of the window's width at the top, 50% at the bottom.
    local lines = { { "TOP", -1, 0.7, K.text2, 0.9 }, { "BOTTOM", 1, 0.5, K.goldText, 0.65 } }
    for _, line in ipairs(lines) do
      local t = add()
      t:SetTexture(MEDIA .. "shimmer.png")
      t:SetHeight(1)
      t:SetPoint(line[1], window, line[1], 0, line[2])
      t:SetVertexColor(line[4][1], line[4][2], line[4][3], line[5])
      line.region = t
    end
    local function fit(width)
      for _, line in ipairs(lines) do line.region:SetWidth(width * line[3]) end
    end
    fit(window:GetWidth() or 0)
    window:HookScript("OnSizeChanged", function(_, width) fit(width) end)
  elseif kind == "stitch" then
    -- A dashed line 6px inside the edge, tiled along each side.
    -- Two files, a dash tile along and a dash tile across, so no region needs a texcoord of its own.
    local sides = { { "TOPLEFT", "TOPRIGHT", 6, -6, -6, -6, true }, { "BOTTOMLEFT", "BOTTOMRIGHT", 6, 6, -6, 6, true },
      { "TOPLEFT", "BOTTOMLEFT", 6, -6, 6, 6, false }, { "TOPRIGHT", "BOTTOMRIGHT", -6, -6, -6, 6, false } }
    for _, side in ipairs(sides) do
      local t = add()
      t:SetTexture(MEDIA .. (side[7] and "stitch_h.png" or "stitch_v.png"), "REPEAT", "REPEAT")
      t:SetPoint(side[1], window, side[1], side[3], side[4])
      t:SetPoint(side[2], window, side[2], side[5], side[6])
      if side[7] then
        t:SetHeight(1); t:SetHorizTile(true)
      else
        t:SetWidth(1); t:SetVertTile(true)
      end
      t:SetVertexColor(K.goldText[1], K.goldText[2], K.goldText[3], 0.45)
    end
  end
  return #list > 0 and list or nil
end

--- The main window's surface, in the applied skin: a fill that shades from top to bottom, a frame (a
-- hairline ring, a tinted metal bevel, a pixel line, or Classic's), the skin's ornament, and a soft
-- shadow outside it, drawn by `window` itself over its whole rect. Returns the pieces: fill, ring,
-- shadow, glow, ornament (a list of regions, or nil), frameExtra, grain, and :SetDocked.
--
-- `opts.inside`: a window that sits against a Blizzard frame draws nothing outside its own edge, so
-- no shadow and no glow (goldcap's hairline look keeps its shadow, as it always had).
--
-- :SetDocked(true) is for the window in the auction house, whose Blizzard frame is its frame: the
-- ring, the ornament, the shadow and the glow go and the corners are square. Goldcap's look has
-- always kept its ring and rounded corners there and drops only the shadow.
--
-- Regions of the window, never a child frame: a child frame sits at the level every control in
-- the window gets (the window's plus one), and the client draws frames of one level layer by
-- layer together, so the glass's fill covered each button's own fill -- an active button's gold
-- plate -- and the window's own lines (seen in WoW: Forever, 2026-10-09). A frame's own regions
-- are under all of its children, whatever their levels.
function T.Window(window, opts)
  local skin = GC.Kit.Skins.Current()
  local inside = opts and opts.inside
  local radius = skin.radius[1]
  local classic = skin.frame == "classic"
  local win
  if classic then
    -- The client's marble, tiled in its own colours, in one piece (a tiled texture cannot be cut
    -- into the nine of the gradient fill).
    local marble = window:CreateTexture(nil, "BACKGROUND")
    marble:SetTexture(T.CLASSIC.marble, "REPEAT", "REPEAT")
    marble:SetHorizTile(true)
    marble:SetVertTile(true)
    marble:SetAllPoints()
    win = { fill = { marble } }
  elseif skin.paper then
    -- The client's quest paper where it has the atlas (GetAtlasInfo answers; SetAtlas says nothing
    -- of its own), else the one gen_art.py draws in the skin's window colours. One untinted piece
    -- over the window, 2px in from its edge (as the leather grain is) so no square corner shows past
    -- the ring's arc; a docked window, whose ring is gone and corners square, takes the whole of it.
    local paper = window:CreateTexture(nil, "BACKGROUND")
    local info = _G.C_Texture and _G.C_Texture.GetAtlasInfo
    if info and info("QuestBG-Parchment") then
      paper:SetAtlas("QuestBG-Parchment")
    else
      paper:SetTexture(MEDIA .. "parchment.png")
    end
    paper:SetPoint("TOPLEFT", window, "TOPLEFT", 2, -2)
    paper:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -2, 2)
    win = { fill = { paper }, paper = paper }
  else
    win = { fill = windowFill(window, K.windowTop, K.windowBottom, T.Art("card", radius)) }
  end

  if classic then
    -- The client's gold dialog border: a backdrop edge (the file's pieces are 32px) drawn at 40px,
    -- 14px outside the window; against a Blizzard frame it sits on the window's own edge. A frame of
    -- its own, since only a frame has a backdrop; made now, so the controls made later draw over it.
    local out = inside and 0 or 14
    local border = CreateFrame("Frame", nil, window, "BackdropTemplate")
    border:SetBackdrop({ edgeFile = T.CLASSIC.goldBorder, edgeSize = inside and 32 or 40 })
    border:SetUsingParentLevel(true) -- on the window's own level, under every control of it
    border:SetPoint("TOPLEFT", window, "TOPLEFT", -out, out)
    border:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", out, -out)
    win.ring = border
    if not inside then
      -- The title plate over the top edge, "GoldCap" in white on it.
      local plate = border:CreateTexture(nil, "OVERLAY")
      local coords = T.CLASSIC.headerCoords
      -- A client that has not the plate (SetTexture says so) gets the one gen_art.py draws.
      if plate:SetTexture(T.CLASSIC.goldHeader) == false then
        plate:SetTexture(MEDIA .. "classic_header.png")
        plate:SetTexCoord(0, 1, 0, 1)
      else
        plate:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
      end
      plate:SetSize(236, 66)
      plate:SetPoint("TOP", window, "TOP", 0, 31)
      local text = T.Heading(border, 16, "OVERLAY")
      text:SetPoint("CENTER", plate, "CENTER", 0, 0)
      text:SetText("GoldCap")
      text:SetTextColor(1, 1, 1, 1) -- untinted
      win.title, win.titleText = plate, text
    end
  elseif skin.frame == "bevel" then
    -- Baked in colour (outline, band from the skin's frame gradient, inner line), so drawn untinted.
    win.ring = T.SlicedTexture(window, "BORDER", T.Art("bevel", skin.id), { 1, 1, 1, 1 }, -- untinted
      T.ArtSlice("bevel", radius, skin.frameWidth))
  elseif skin.frame == "pixel" then
    win.ring = T.SlicedTexture(window, "BORDER", MEDIA .. "pixel_line.png", K.frameTint, T.ArtSlice("ring", 0))
    local inner = T.SlicedTexture(window, "BORDER", MEDIA .. "pixel_line.png", K.frameInner, T.ArtSlice("ring", 0))
    inner:SetPoint("TOPLEFT", window, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -1, 1)
    win.frameExtra = { inner }
  else -- hairline (today)
    win.ring = T.SlicedTexture(window, "BORDER", T.Art("ring", radius), K.windowBorder, T.ArtSlice("ring", radius))
  end
  if not classic then win.ring:SetAllPoints() end

  if skin.ornament == "stitch" then
    -- The stitched (leather) skin's grain, tiled over the gradient and under everything else.
    local grain = window:CreateTexture(nil, "BACKGROUND", nil, 1)
    grain:SetTexture(MEDIA .. "leather.png", "REPEAT", "REPEAT")
    grain:SetHorizTile(true)
    grain:SetVertTile(true)
    grain:SetPoint("TOPLEFT", window, "TOPLEFT", 2, -2)
    grain:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -2, 2)
    win.grain = grain
  end

  win.ornament = ornamentOf(window, skin.ornament, inside)

  local hairline = skin.frame == "hairline"
  -- Every look drops the same soft shadow (the mock gives all nine); a window against a Blizzard
  -- frame draws none outside itself, but for goldcap's, which always had it.
  if hairline or not inside then win.shadow = T.Shadow(window, 18, 0.65) end
  if skin.ornament == "shimmer" and not inside then
    -- Midnight's violet glow, in its accent colour.
    win.glow = T.Glow(window, { K.gold[1], K.gold[2], K.gold[3], 0.45 }, 28)
  end

  local frame = { win.ring }
  if win.title then frame[#frame + 1] = win.title; frame[#frame + 1] = win.titleText end
  if win.shadow then frame[#frame + 1] = win.shadow end
  if win.glow then frame[#frame + 1] = win.glow end
  for _, extra in ipairs(win.frameExtra or {}) do frame[#frame + 1] = extra end
  for _, region in ipairs(win.ornament or {}) do frame[#frame + 1] = region end
  local function setShown(region, shown)
    if shown then region:Show() else region:Hide() end
  end
  function win:SetDocked(docked)
    if hairline then
      if self.shadow then setShown(self.shadow, not docked) end
      return
    end
    for _, region in ipairs(frame) do setShown(region, not docked) end
    if self.paper then
      self.paper:ClearAllPoints()
      if docked then
        self.paper:SetAllPoints(window)
      else
        self.paper:SetPoint("TOPLEFT", window, "TOPLEFT", 2, -2)
        self.paper:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -2, 2)
      end
      return
    end
    if classic then return end -- the marble has no corners to square
    for _, i in ipairs({ 1, 3, 7, 9 }) do
      local c = docked and WINDOW_PIECES[5] or WINDOW_PIECES[i]
      self.fill[i]:SetTexCoord(c[1], c[2], c[3], c[4])
    end
  end
  return win
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
