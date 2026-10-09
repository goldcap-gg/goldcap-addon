local _, GC = ...

GC.Theme = GC.Theme or {}
local T = GC.Theme

-- The names every window reads, drawn from UI/Kit/Tokens.lua. Each keeps its meaning: `red` and
-- `green` are what TEXT wears (a loss, a profit), `redFill` is what a BUTTON is filled with,
-- `cost` is a price paid, `hover` is the gold wash a row wears under the cursor, `watch` is a
-- state that persists while you look elsewhere (the player's own lots) and so has its own colour.
local K = GC.Kit.Tokens.color
local function rgb(color) return { color[1], color[2], color[3] } end
T.color = {
  bg      = rgb(K.windowBottom),
  panel   = rgb(K.windowTop),
  panelHi = rgb(K.raised),
  border  = K.glassBorder,
  gold    = rgb(K.gold),
  goldHi  = rgb(K.goldText),
  fg      = rgb(K.text1),
  fgMuted = rgb(K.text2),
  fgDim   = rgb(K.text3),
  red     = rgb(K.loss),
  redFill = rgb(K.lossFill),
  green   = rgb(K.profit),
  cost    = rgb(K.cost),
  zebra   = { 1, 1, 1, 0.035 },
  hover   = { K.gold[1], K.gold[2], K.gold[3], 0.16 },
  watch   = rgb(K.yours),
}

T.tier = {
  HOT     = { 1, 0.35, 0.15 },
  GOOD    = { 0.25, 0.85, 0.25 },
  WATCH   = { 0.65, 0.65, 0.65 },
  SUSPECT = { 1, 0.85, 0.1 },
}

T.pad = { xs = 4, s = 8, m = 12, l = 16 }
T.ROW_H = 32

T.MEDIA = GC.Kit.MEDIA
T.RAIL_W = 76

-- Drawn additively in the HIGHLIGHT layer by the engine while the cursor is over a button, so
-- it must stay subtle: it lands on top of a gold fill as readily as on bare panel.
local HOVER_WASH = { T.color.gold[1], T.color.gold[2], T.color.gold[3], 0.18 }

-- QuietScrollBar: UIPanelScrollFrameTemplate's scrollbar without Blizzard's chrome -- the two
-- arrow buttons and the knurled thumb floated beside panels drawn in none of that style (seen
-- in game beside the Sell list AND its detail panel at once). The bar itself stays: the wheel
-- and a drag of the thumb still scroll. The arrows are made invisible and unclickable rather
-- than hidden, because the template's own scripts Enable/Disable them and anchor the track
-- between them. Every part is optional -- which keys a scrollbar carries has changed between
-- client versions, and a missing one is simply skipped.
function T.QuietScrollBar(scroll)
  local bar = scroll and scroll.ScrollBar
  if not bar then return end
  for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
    local button = bar[key]
    if button then
      if button.SetAlpha then button:SetAlpha(0) end
      if button.EnableMouse then button:EnableMouse(false) end
    end
  end
  for _, key in ipairs({ "Top", "Middle", "Bottom", "Background", "trackBG" }) do
    if bar[key] and bar[key].Hide then bar[key]:Hide() end
  end
  local thumb = bar.ThumbTexture or (bar.GetThumbTexture and bar:GetThumbTexture())
  if thumb and thumb.SetTexture then
    -- bar.png at its own slice (2), the same pill the Sell book's depth bars are drawn with.
    thumb:SetTexture(T.MEDIA .. "bar.png")
    if thumb.SetTexCoord then thumb:SetTexCoord(0, 1, 0, 1) end
    if thumb.SetTextureSliceMargins then thumb:SetTextureSliceMargins(2, 2, 2, 2) end
    if thumb.SetVertexColor then thumb:SetVertexColor(1, 1, 1, 0.22) end
    if thumb.SetSize then thumb:SetSize(4, 36) end
  end
end

-- Rail: the window's primary navigation. Big targets on purpose -- the old
-- 50x18 ghost tabs were the main menu and read as decoration. Active state
-- reuses setTabActive's functional contract: the current view's button is
-- Disable()d (not clickable), visuals ride on top of that.
local RAIL_BTN_W, RAIL_BTN_H = 60, 54
local RAIL_FILL = { T.color.gold[1], T.color.gold[2], T.color.gold[3], 0.13 }
local RAIL_RING = { T.color.gold[1], T.color.gold[2], T.color.gold[3], 0.40 }
local RAIL_GLOW = { T.color.gold[1], T.color.gold[2], T.color.gold[3], 0.14 }
local BADGE_TEXT = { 0.05, 0.05, 0.06 }

function T.RailButton(parent, iconName, labelText)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(RAIL_BTN_W, RAIL_BTN_H)
  b:RegisterForClicks("LeftButtonUp")
  -- Required for the HIGHLIGHT layer, exactly as in T.Button.
  b:EnableMouse(true)

  b.glow = T.Glow(b, RAIL_GLOW, 10)
  b.bg = T.SlicedTexture(b, "BACKGROUND", T.MEDIA .. "card.png", RAIL_FILL)
  b.bg:SetAllPoints()
  b.ring = T.SlicedTexture(b, "BORDER", T.MEDIA .. "ring.png", RAIL_RING)
  b.ring:SetAllPoints()

  b.icon = b:CreateTexture(nil, "ARTWORK")
  T.SetIcon(b.icon, iconName)
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("TOP", 0, -8)

  b.text = b:CreateFontString(nil, "OVERLAY")
  b.text:SetFont(T.FONT_UI_BOLD, 8 * T.Scale(), "")
  b.text:SetPoint("BOTTOM", 0, 7)
  b.text:SetText(labelText)
  T.TrackFont(b.text, { role = "uiBold", path = T.FONT_UI_BOLD, size = 8 })

  -- The same rounded card as the active fill, not a flat colour: a SetColorTexture wash filled
  -- the button's whole square, so hovering a rail button drew a square around the rounded
  -- plate the active one wears (owner, Forever beta 2026-10-01).
  b.highlightTexture = T.SlicedTexture(b, "HIGHLIGHT", T.MEDIA .. "card.png", HOVER_WASH)
  b.highlightTexture:SetAllPoints()
  b.highlightTexture:SetBlendMode("ADD")

  -- The engine keeps drawing HIGHLIGHT over a disabled button (that is how a dimmed control
  -- can still raise a tooltip), so the wash is hidden here instead of guarded in a script.
  -- Hide/Show, never SetAlpha: on a texture, SetAlpha writes the same alpha SetVertexColor set,
  -- so SetAlpha(1) on the way back turned the 18% wash into solid gold -- a tab the player had
  -- visited and left lit up bright yellow under the cursor (owner, Forever beta 2026-10-01).
  b:SetScript("OnDisable", function() b.highlightTexture:Hide() end)
  b:SetScript("OnEnable", function() b.highlightTexture:Show() end)

  b.badge = CreateFrame("Frame", nil, b)
  b.badge:SetPoint("TOPRIGHT", -4, -4)
  -- badge.png/T.SLICE.badge, not card.png/T.SLICE.card or plaque.png/T.SLICE.plaque: the badge is
  -- 14px tall and both of those margins exceed half that (see T.SLICE.badge's own comment).
  b.badge.bg = T.SlicedTexture(b.badge, "BACKGROUND", T.MEDIA .. "badge.png", T.color.gold, T.SLICE.badge)
  b.badge.bg:SetAllPoints()
  b.badge.text = b.badge:CreateFontString(nil, "OVERLAY")
  b.badge.text:SetFont(T.FONT_UI_BOLD, 9 * T.Scale(), "")
  b.badge.text:SetPoint("CENTER")
  b.badge.text:SetTextColor(BADGE_TEXT[1], BADGE_TEXT[2], BADGE_TEXT[3])
  T.TrackFont(b.badge.text, { role = "uiBold", path = T.FONT_UI_BOLD, size = 9 })
  b.badge:Hide()

  function b:SetBadge(count)
    if count then
      b.badge.text:SetText(tostring(count))
      b.badge:SetWidth((14 + 6 * #tostring(count)) * T.Scale())
      -- Item 7 (addon polish batch): height scales the same way -- it used to stay a fixed 14,
      -- distorting the pill's aspect ratio at the font-scale slider's extremes.
      b.badge:SetHeight(14 * T.Scale())
      b.badge:Show()
    else
      b.badge:Hide()
    end
  end

  function b:SetActive(active)
    local c = active and T.color.goldHi or T.color.fgDim
    b.icon:SetVertexColor(c[1], c[2], c[3], 1)
    b.text:SetTextColor(c[1], c[2], c[3], 1)
    if active then
      b.glow:Show(); b.bg:Show(); b.ring:Show()
      b:Disable()
    else
      b.glow:Hide(); b.bg:Hide(); b.ring:Hide()
      b:Enable()
    end
  end
  b:SetActive(false)

  return b
end

function T.Rail(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(T.RAIL_W)
  -- card_left.png: left corners rounded to match the window card's own radius 16, right edge
  -- square (it borders content, not window chrome) -- a flat rectangle here would poke square
  -- corners past the window's rounded top-left/bottom-left arcs.
  local bg = T.SlicedTexture(frame, "BACKGROUND", T.MEDIA .. "card_left.png", { T.color.bg[1], T.color.bg[2], T.color.bg[3], 0.9 })
  bg:SetAllPoints()
  local edge = frame:CreateTexture(nil, "BORDER")
  edge:SetColorTexture(T.color.border[1], T.color.border[2], T.color.border[3], T.color.border[4])
  edge:SetPoint("TOPRIGHT")
  edge:SetPoint("BOTTOMRIGHT")
  edge:SetWidth(1)

  -- The GoldCap mark itself -- the coin in the crosshair the site, the store pages and the
  -- AddOns list show -- rather than a gold plate with a "G" on it (owner, 2026-10-01). Same
  -- file as the .toc's IconTexture, full colour on transparent, so it is drawn as it is and
  -- never tinted. 40px, where the plate was 32: the crosshair's arms take the outer ring, and
  -- at 32 the coin inside was smaller than a rail icon. The gap under it shrinks by the same
  -- 8px (LOGO_GAP) so the buttons below stay where they were.
  local logo = CreateFrame("Frame", nil, frame)
  logo:SetSize(40, 40)
  logo:SetPoint("TOP", 0, -16)
  logo.mark = logo:CreateTexture(nil, "ARTWORK")
  logo.mark:SetTexture(T.MEDIA .. "GoldCap")
  logo.mark:SetAllPoints()
  local LOGO_GAP = 14

  local buttons = {}
  local order = {
    { key = "deals", icon = "deals", label = "DEALS" },
    { key = "sell", icon = "sell", label = "SELL" },
    { key = "sold", icon = "sold", label = "SOLD" },
    { key = "buy", icon = "buy", label = "BUY" },
  }
  local prev = logo
  for i, item in ipairs(order) do
    local b = T.RailButton(frame, item.icon, item.label)
    b:SetPoint("TOP", prev, "BOTTOM", 0, i == 1 and -LOGO_GAP or -T.pad.s)
    buttons[item.key] = b
    prev = b
  end

  -- "badge" rounded (margin 6, no ring -- see ROUNDED_BUTTON's own comment): 28px is the same
  -- size class as T.RailButton's own badge, and SetVariant("active") below (SettingsFrame.lua)
  -- needs a rounded fill to switch, not the square edgeBorder look a bare "ghost" button has.
  local gear = T.Button(frame, "ghost", "badge")
  gear:SetSize(28, 28)
  gear:SetPoint("BOTTOM", 0, 14)
  gear.icon = gear:CreateTexture(nil, "ARTWORK")
  T.SetIcon(gear.icon, "gear", T.color.fgDim)
  gear.icon:SetSize(17, 17)
  gear.icon:SetPoint("CENTER")

  -- Docked into the Auction House the host's portrait overhangs the rail's top-left corner;
  -- SetDocked pushes the logo (and the nav chain anchored to it) below it. The gear is
  -- bottom-anchored and unaffected.
  local function setTopInset(px)
    logo:ClearAllPoints()
    logo:SetPoint("TOP", 0, -(16 + (px or 0)))
  end

  return { frame = frame, buttons = buttons, gear = gear, logo = logo, SetTopInset = setTopInset }
end

-- Chip: a tinted pill, not the old solid plaque + underline. Nine-slice invariant (see
-- T.SLICE.plaque/T.SLICE.badge's own comments above): margins must stay BELOW half the smallest
-- widget edge, or the sliced corners overlap and notch. This pill is 20px tall -- T.SLICE.plaque
-- (12) is not below half of a 24px pill (12), so plaque.png was ruled out; T.SLICE.badge (6) IS
-- below half of 20 (10), so this uses badge.png at height 20, with no separate ring texture
-- (badge.png has none -- unlike T.Card's card.png/plaque.png, which pair with ring.png/
-- plaque_ring.png).
-- Grepped every spec and every UI source before removing the old `f.underline` texture: nothing
-- reads `.underline` off a chip (SoldFrame.lua's own header-underline is an unrelated feature
-- with its own texture), so it is dropped outright rather than kept as a hidden stand-in.
function T.Chip(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(20)

  -- File texture, recolored via SetVertexColor only (never SetColorTexture, which would strip
  -- the art) -- same rule T.Card:SetTint and Theme.Button's rounded bg follow.
  f.bg = T.SlicedTexture(f, "BACKGROUND", T.MEDIA .. "badge.png", T.color.panel, T.SLICE.badge)
  f.bg:SetAllPoints()

  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetFont(T.FONT_UI_BOLD, 9 * T.Scale(), "")
  f.text:SetJustifyH("CENTER")
  -- Bounded to the pill's own width (a bare CENTER point has no width limit at all) and
  -- non-wrapping, so a long label (e.g. "SUSPECT") truncates inside the pill instead of
  -- overflowing into whatever sits to its right.
  f.text:SetPoint("LEFT", 4, 0)
  f.text:SetPoint("RIGHT", -4, 0)
  f.text:SetWordWrap(false)

  T.TrackFont(f.text, { role = "uiBold", path = T.FONT_UI_BOLD, size = 9 })

  function f:SetLabel(text, colorTable)
    f.text:SetText(text)
    local c = colorTable or T.color.fg
    f.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    -- Fill at low alpha over the dark panel underneath -- a pill reads as a tinted surface,
    -- not a solid block of the tier color. No ring layer to tint alongside it (see above).
    f.bg:SetVertexColor(c[1], c[2], c[3], 0.12)
  end

  return f
end

-- TierMark: a 6x6 color dot + mono label, a plainer stand-in for T.Chip's tinted badge pill
-- (see T.Chip's own comment above) everywhere a tier marker sits inline in a row rather than
-- boxed on its own. `:SetLabel(text, colorTable)` is the exact call signature SniperFrame's
-- row-stamping line already uses on T.Chip, so swapping the widget that builds `row.tierChip`
-- does not touch that call site.
function T.TierMark(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(10)

  f.dot = T.Solid(f, "ARTWORK", T.color.fgDim)
  f.dot:SetSize(6, 6)
  f.dot:SetPoint("LEFT")

  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetFont(T.FONT_UI_BOLD, 10 * T.Scale(), "")
  f.text:SetJustifyH("LEFT")
  -- Bounded to the mark's own width and non-wrapping, exactly as T.Chip's label is (see its
  -- comment): a bare LEFT point has no width limit at all, so a label longer than the cell
  -- paints straight across whatever sits to its right instead of clipping. The Sniper board's
  -- verdict cell is what found this -- a refusal sentence in that column ran over the discount
  -- and price figures beside it.
  f.text:SetPoint("LEFT", f.dot, "RIGHT", 5, 0)
  f.text:SetPoint("RIGHT")
  f.text:SetWordWrap(false)
  T.TrackFont(f.text, { role = "uiBold", path = T.FONT_UI_BOLD, size = 10 })

  function f:SetLabel(text, colorTable)
    f.text:SetText(text)
    local c = colorTable or T.color.fg
    f.dot:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    f.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  end

  return f
end

-- TitleBar: 32px drag region at top of `frame`, title Label 13; close sits at the outer
-- top-right corner, gear sits immediately inboard (left) of close.
function T.TitleBar(frame, titleText)
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("TOPRIGHT")
  bar:SetHeight(32)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function()
    -- A docked window (GC.Sniper.SetDocked flips SetMovable off) must not be draggable, and
    -- StartMoving on an immovable frame is a Lua error, not a no-op.
    if frame:IsMovable() then frame:StartMoving() end
  end)
  bar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)

  bar.title = T.Label(bar, 13)
  bar.title:SetPoint("LEFT", bar, "LEFT", T.pad.m, 0)
  bar.title:SetText(titleText or "")

  local close = T.Button(bar, "ghost")
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -T.pad.s, -T.pad.xs)
  close:SetLabel("X")
  close:SetScript("OnClick", function()
    frame:Hide()
  end)

  local gear = T.Button(bar, "ghost")
  gear:SetSize(20, 20)
  gear:SetPoint("RIGHT", close, "LEFT", -T.pad.xs, 0)
  gear:SetLabel("*")

  -- `title` is part of the return on purpose: docked mode (GC.Sniper.SetDocked) blanks and
  -- restores it. It shipped without this field once, and the caller's nil-guard turned the
  -- missing key into a silently-still-visible duplicate title.
  -- `bar` (the title bar FRAME) is returned too because a caller may need to re-anchor the
  -- title relative to it (e.g. to make room for a rail on the left) -- the RETURN TABLE
  -- itself is a plain Lua table, not a region, and must never be passed to SetPoint.
  return { gear = gear, close = close, title = bar.title, bar = bar }
end

-- Reagent quality, as the game itself draws it.
--
-- The first attempt hardcoded `Professions-ChatIcon-Quality-Tier1..5`, which are
-- the Dragonflight diamonds. The client draws something else now, so the list
-- showed two diamonds beside an item whose own tooltip showed a different mark
-- entirely -- the addon disagreeing with the game about the same item.
--
-- The lesson is not "use the newer atlas names". It is that an atlas name is art
-- and art is versioned, so hardcoding one means being wrong again at the next
-- expansion. The tooltip already renders the correct icon for whatever build is
-- running, and C_TooltipInfo hands us that tooltip as data with its escape
-- sequences intact -- so the icon is lifted from there and rescaled, and this
-- file never needs to know what the art is called.
--
-- Matching is on the atlas NAME, never on the label beside it: atlas names are
-- not localised and the label is. "quality" or "tier" covers every naming the
-- art has used so far; a client that matches neither shows no pip at all, which
-- is honest -- an absent mark costs nothing, a wrong one contradicts the game.
--
-- There is deliberately no hardcoded fallback atlas here. There used to be
-- one, kept for a client that supposedly still carried the old art -- but
-- Blizzard does not delete atlas entries it stops using, so the fallback's own
-- existence check (C_Texture.GetAtlasInfo) kept succeeding long after the game
-- moved on to different art, and whenever it won a race against a tooltip that
-- simply had not warmed up yet, the wrong icon got cached for the rest of the
-- session -- the exact contradiction this file exists to avoid. A guess that
-- is sometimes wrong is worse than the pip being briefly absent while the
-- tooltip catches up, so an unresolved lookup is left unresolved instead of
-- being answered from memory.
local QUALITY_CACHE = {}

local function atlasFromTooltip(itemID)
  if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  for _, line in ipairs(data.lines) do
    for _, text in ipairs({ line.leftText, line.rightText }) do
      if type(text) == "string" then
        for atlas in text:gmatch("|A:([^:|]+):") do
          local name = atlas:lower()
          if name:find("quality", 1, true) or name:find("tier", 1, true) then return atlas end
        end
      end
    end
  end
  return nil
end

local function atlasForQuality(itemID)
  local cached = QUALITY_CACHE[itemID]
  if cached ~= nil then return cached end
  local atlas = atlasFromTooltip(itemID)
  if atlas then
    QUALITY_CACHE[itemID] = atlas
  end
  -- Nothing is remembered when the tooltip has no answer yet -- that is
  -- temporary, so the next call is free to try again once it warms up.
  return atlas
end

--- The quality of `itemID` as an inline atlas escape, or "" when the item has no
-- quality tier (most items do not) or the client will not say what to draw.
function T.QualityMarkup(itemID, size)
  if type(itemID) ~= "number" then return "" end
  local api = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
  if not api then return "" end
  local ok, quality = pcall(api, itemID)
  if not ok or type(quality) ~= "number" then return "" end
  local atlas = atlasForQuality(itemID)
  if not atlas then return "" end
  size = size or 14
  return ("|A:%s:%d:%d|a"):format(atlas, size, size)
end

--- `name` as a list shows an item: in its item quality's colour (uncommon and better -- the
-- game's colour for common is pure white, brighter than anything else on these panels, so a
-- common name stays in the interface's own foreground) with its reagent-tier pip AFTER it, so
-- names start on one edge down a list. `name` unchanged when the client knows neither.
function T.WithQuality(name, itemID, size)
  local label = tostring(name)
  local api = _G.C_Item and _G.C_Item.GetItemQualityByID
  if api and itemID then
    local ok, quality = pcall(api, itemID)
    local colour = ok and type(quality) == "number" and quality >= 2
      and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality]
    if colour and type(colour.hex) == "string" then label = colour.hex .. label .. "|r" end
  end
  local markup = T.QualityMarkup(itemID, size)
  if markup == "" then return label end
  return label .. " " .. markup
end

--- The GameTooltip anchor that opens a tooltip from `owner` into the part of the screen
-- that has room for it.
--
-- SetOwner's ANCHOR_RIGHT pins the tooltip's bottom-left corner to the owner's top-right,
-- so it grows up and to the right. That is empty space for a control on the left of the
-- screen and no space at all for one in the right-hand column of a window that fills it:
-- the client clamps the tooltip back inside the screen, which drags it left across the
-- list it describes and over the very button under the cursor, and a long body runs into
-- the top edge the same way. So the side is chosen from where the owner sits -- leftward
-- in the right half of the screen, downward in the top half -- and the tooltip lands
-- beside the control every time.
--
-- GetCenter answers in the owner's own scaled space, and the Sniper window carries its own
-- scale, so both centres are brought to screen pixels before they are compared. Falls back
-- to ANCHOR_RIGHT wherever a position cannot be read: a frame with no anchors yet, or the
-- headless test bed with no UIParent.
function T.TooltipAnchor(owner)
  local screen = UIParent
  if not (owner and owner.GetCenter and screen and screen.GetCenter) then return "ANCHOR_RIGHT" end
  local x, y = owner:GetCenter()
  local midX, midY = screen:GetCenter()
  if not (x and y and midX and midY) then return "ANCHOR_RIGHT" end
  local ownerScale, screenScale = owner:GetEffectiveScale(), screen:GetEffectiveScale()
  local right = x * ownerScale > midX * screenScale
  local top = y * ownerScale > midY * screenScale
  if right then return top and "ANCHOR_BOTTOMLEFT" or "ANCHOR_LEFT" end
  return top and "ANCHOR_BOTTOMRIGHT" or "ANCHOR_RIGHT"
end

-- How much horizontal room an item tooltip needs beside the window before T.ItemTooltipOutside
-- decides the right edge has space for it. Not measured off the real tooltip (its width
-- depends on the item's own name/quality/flavor text, none of which is known before
-- SetItemByID runs) -- 330 is a deliberately generous upper estimate so the check fails
-- toward the side that is SURE to have room rather than clipping against the screen edge.
local ITEM_TOOLTIP_WIDTH = 330

--- Opens GameTooltip beside `windowFrame` -- its right edge, or its left edge when the right
-- has no room -- never inside it. For an ITEM tooltip (SetItemByID), whose body can run long
-- enough to cover the very row that opened it if it were anchored to the row the ordinary way.
--
-- `rowFrame` is the hovered row; the tooltip's TOP lands level with the row's own top (read
-- off GetTop(), not GetCenter() -- a multi-line item tooltip grows DOWN from its anchor, so
-- top-aligning is what keeps it beside the row that triggered it instead of drifting below).
-- Whether the right edge has room is windowFrame's own right edge, converted to screen pixels
-- via GetEffectiveScale() (the window carries its own scale, see T.SetScale) and compared
-- against the screen's, the same coordinate-space conversion T.TooltipAnchor above uses.
--
-- Falls back to ANCHOR_RIGHT off `rowFrame` when either frame lacks real geometry -- a frame
-- with no anchors yet, or the headless test bed with no UIParent.
function T.ItemTooltipOutside(rowFrame, windowFrame)
  local screen = UIParent
  local ready = rowFrame and rowFrame.GetTop and windowFrame and windowFrame.GetTop
    and windowFrame.GetRight and windowFrame.GetEffectiveScale
    and screen and screen.GetRight and screen.GetEffectiveScale
  local rowTop = ready and rowFrame:GetTop()
  local windowTop = ready and windowFrame:GetTop()
  local windowRight = ready and windowFrame:GetRight()
  local screenRight = ready and screen:GetRight()

  if not (rowTop and windowTop and windowRight and screenRight) then
    GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
    return
  end

  GameTooltip:SetOwner(rowFrame, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()

  local windowScale, screenScale = windowFrame:GetEffectiveScale(), screen:GetEffectiveScale()
  local fitsRight = (windowRight * windowScale + ITEM_TOOLTIP_WIDTH) <= (screenRight * screenScale)
  local yOffset = rowTop - windowTop

  if fitsRight then
    GameTooltip:SetPoint("TOPLEFT", windowFrame, "TOPRIGHT", 8, yOffset)
  else
    GameTooltip:SetPoint("TOPRIGHT", windowFrame, "TOPLEFT", -8, yOffset)
  end
end
