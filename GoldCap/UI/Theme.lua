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

local function solid(parent, layer, c)
  local tx = parent:CreateTexture(nil, layer)
  tx:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  return tx
end

local function edgeBorder(f, c)
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local e = solid(f, "BORDER", c)
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

-- Panel: flat dark texture + 1px border.
function T.Panel(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.bg = solid(f, "BACKGROUND", T.color.panel)
  f.bg:SetAllPoints()
  edgeBorder(f, T.color.border)
  return f
end

T.MEDIA = GC.Kit.MEDIA
T.RAIL_W = 76

-- Rounded chrome comes from ONE white 64px rounded-rect PNG stretched with
-- SetTextureSliceMargins (nine-slice on a single texture, 10.2.0+ -- wiki:
-- API_TextureBase_SetTextureSliceMargins) and recolored via SetVertexColor.
-- White art + vertex color means one file serves every tint; regenerate the
-- PNGs with the project's gen_art.py, never edit them by hand. Margins are 24
-- of the 64px file so the 16px corners survive any widget size.
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

-- Drawn additively in the HIGHLIGHT layer by the engine while the cursor is over a button, so
-- it must stay subtle: it lands on top of a gold fill as readily as on bare panel.
local HOVER_WASH = { T.color.gold[1], T.color.gold[2], T.color.gold[3], 0.18 }

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

-- Card: rounded panel (fill + 2px ring). The rounded sibling of T.Panel; use
-- it for chrome that should read as a surface, keep T.Panel for flat fills.
-- `small`: use plaque.png/plaque_ring.png (radius 8, PLAQUE_SLICE margins)
-- instead of card.png/ring.png (radius 16, CARD_SLICE margins) -- for chrome
-- small enough that the 24px card margins would overlap and notch.
function T.Card(parent, fill, border, small)
  local f = CreateFrame("Frame", nil, parent)
  local bgFile = small and (T.MEDIA .. "plaque.png") or (T.MEDIA .. "card.png")
  local ringFile = small and (T.MEDIA .. "plaque_ring.png") or (T.MEDIA .. "ring.png")
  local margin = small and PLAQUE_SLICE or nil
  f.bg = slicedTexture(f, "BACKGROUND", bgFile, fill or T.color.panel, margin)
  f.bg:SetAllPoints()
  f.ring = slicedTexture(f, "BORDER", ringFile, border or T.color.border, margin)
  f.ring:SetAllPoints()
  function f:SetTint(fillC, borderC)
    if fillC then f.bg:SetVertexColor(fillC[1], fillC[2], fillC[3], fillC[4] or 1) end
    if borderC then f.ring:SetVertexColor(borderC[1], borderC[2], borderC[3], borderC[4] or 1) end
  end
  return f
end

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

-- Glow: additive halo hung `inset` px outside the parent's own rect. ADD
-- blend keeps it readable over any fill, same reasoning as HOVER_WASH.
function T.Glow(parent, c, inset)
  local pad = inset or 14
  local tx = parent:CreateTexture(nil, "BACKGROUND")
  tx:SetTexture(T.MEDIA .. "glow.png")
  tx:SetBlendMode("ADD")
  tx:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  tx:SetPoint("TOPLEFT", -pad, pad)
  tx:SetPoint("BOTTOMRIGHT", pad, -pad)
  return tx
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

function T.RailButton(parent, iconFile, labelText)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(RAIL_BTN_W, RAIL_BTN_H)
  b:RegisterForClicks("LeftButtonUp")
  -- Required for the HIGHLIGHT layer, exactly as in T.Button.
  b:EnableMouse(true)

  b.glow = T.Glow(b, RAIL_GLOW, 10)
  b.bg = slicedTexture(b, "BACKGROUND", T.MEDIA .. "card.png", RAIL_FILL)
  b.bg:SetAllPoints()
  b.ring = slicedTexture(b, "BORDER", T.MEDIA .. "ring.png", RAIL_RING)
  b.ring:SetAllPoints()

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexture(iconFile)
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
  b.highlightTexture = slicedTexture(b, "HIGHLIGHT", T.MEDIA .. "card.png", HOVER_WASH)
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
  -- badge.png/BADGE_SLICE, not card.png/CARD_SLICE or plaque.png/PLAQUE_SLICE: the badge is
  -- 14px tall and both of those margins exceed half that (see BADGE_SLICE's own comment).
  b.badge.bg = slicedTexture(b.badge, "BACKGROUND", T.MEDIA .. "badge.png", T.color.gold, BADGE_SLICE)
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
  local bg = slicedTexture(frame, "BACKGROUND", T.MEDIA .. "card_left.png", { T.color.bg[1], T.color.bg[2], T.color.bg[3], 0.9 })
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
    { key = "deals", icon = "icon_deals.png", label = "DEALS" },
    { key = "sell", icon = "icon_sell.png", label = "SELL" },
    { key = "sold", icon = "icon_sold.png", label = "SOLD" },
    { key = "buy", icon = "icon_buy.png", label = "BUY" },
  }
  local prev = logo
  for i, item in ipairs(order) do
    local b = T.RailButton(frame, T.MEDIA .. item.icon, item.label)
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
  gear.icon:SetTexture(T.MEDIA .. "icon_gear.png")
  gear.icon:SetSize(17, 17)
  gear.icon:SetPoint("CENTER")
  gear.icon:SetVertexColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3], 1)

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
-- PLAQUE_SLICE/BADGE_SLICE's own comments above): margins must stay BELOW half the smallest
-- widget edge, or the sliced corners overlap and notch. This pill is 20px tall -- PLAQUE_SLICE
-- (12) is not below half of a 24px pill (12), so plaque.png was ruled out; BADGE_SLICE (6) IS
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
  f.bg = slicedTexture(f, "BACKGROUND", T.MEDIA .. "badge.png", T.color.panel, BADGE_SLICE)
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

  f.dot = solid(f, "ARTWORK", T.color.fgDim)
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

-- `primary` is dark-on-gold, which is only legible while the gold fill is actually painted.
-- That is fine for a button built primary and left that way (the dialog's Buy/Confirm), but it
-- is a trap for a control that toggles: the Auto button was showing near-black text on a fill
-- that had not gone gold, leaving the label all but invisible. `active` states the same "this
-- is on" with gold TEXT over a faint gold tint, so the label survives no matter what the fill
-- is doing -- there is no state in which it becomes unreadable.
local BUTTON_VARIANTS = {
  primary = { bg = T.color.gold, text = { 0.05, 0.05, 0.06 } },
  active  = { bg = { T.color.gold[1], T.color.gold[2], T.color.gold[3], 0.16 }, text = T.color.goldHi },
  ghost   = { bg = nil, text = T.color.fg },
  danger  = { bg = T.color.redFill, text = { 0.102, 0.024, 0.024 } },
  -- Attention without alarm: a purchase that is real but not the whole line (the BUY tab's
  -- capped fill). Red is what CANCEL and losses wear and reads as "do not".
  warn    = { bg = { T.tier.SUSPECT[1], T.tier.SUSPECT[2], T.tier.SUSPECT[3], 0.16 }, text = T.tier.SUSPECT },
}

-- rounded T.Button: file + margin per size class, keyed the same way T.Card's `small`
-- picks plaque over card -- badge is one size class down again (BADGE_SLICE, no ring: see
-- BADGE_SLICE's own comment, the same 16px art is too small for a second nine-slice ring
-- on top of its fill without the two notching each other).
local ROUNDED_BUTTON = {
  plaque = { bg = T.MEDIA .. "plaque.png", ring = T.MEDIA .. "plaque_ring.png", margin = PLAQUE_SLICE },
  -- `askedRing`: badge_ring.png, a 1px outline on badge.png's own radius. Not drawn unless the
  -- caller asks (b:SetRing below) -- a badge button is a row control, and a list of outlined
  -- ones is a grid of boxes.
  badge  = { bg = T.MEDIA .. "badge.png", ring = nil, askedRing = T.MEDIA .. "badge_ring.png", margin = BADGE_SLICE },
}

-- Square mode's ghost has no fill by design -- edgeBorder (below) draws its outline instead.
-- Rounded mode drops edgeBorder entirely, and "badge" rounded buttons get no ring either (too
-- small for the ring art -- ROUNDED_BUTTON's own comment), so a rounded ghost painted with the
-- same alpha-0 fill has zero at-rest boundary: the row Buy button's "Check" state was bare
-- text. A faint white fill gives rounded ghost the affordance square ghost got from its border.
local ROUNDED_GHOST_FILL = { 1, 1, 1, 0.07 }

-- Button: variant "primary" (gold bg, dark text) | "ghost" (border only) | "danger" (red bg).
-- `rounded` (nil | "plaque" | "badge"): nil keeps the original square look (solid bg,
-- edgeBorder) unchanged. "plaque"/"badge" swap the bg and hover wash for sliced textures of
-- that art (ROUNDED_BUTTON above) and drop the square edgeBorder -- "plaque" gets a sliced
-- plaque_ring.png ring in its place, "badge" gets none (too small for the ring art, same as
-- T.RailButton's own badge).
function T.Button(parent, variant, rounded)
  local spec = BUTTON_VARIANTS[variant] or BUTTON_VARIANTS.ghost
  local roundedSpec = rounded and ROUNDED_BUTTON[rounded]
  -- Held on the button, not captured as upvalues, so SetVariant below can genuinely change how
  -- a live button looks. Capturing them made a repaint impossible: the next OnEnter/OnLeave
  -- would stomp it back, which is why the Auto control used to be two overlaid buttons swapped
  -- by Show/Hide -- and that swap is what made it flicker, miss hovers, and reappear painted in
  -- a stale state under a stationary cursor.
  local b = CreateFrame("Button", nil, parent)
  local base
  -- I2: LEFT-click only. This reverses an earlier "AnyUp" choice -- a purchase-flow button
  -- (row Buy, dialog primary/Confirm) must never let a right- or middle-click reach
  -- PlaceBid/StartCommoditiesPurchase/ConfirmCommoditiesPurchase; only a left-click OnClick
  -- may fire.
  b:RegisterForClicks("LeftButtonUp")
  -- Required, not decorative: the HIGHLIGHT layer below is shown and hidden by the engine only
  -- on a mouse-enabled frame ("Setting Frame:EnableMouse() causes HIGHLIGHT to show/hide as the
  -- cursor hovers the Frame" -- warcraft.wiki.gg/wiki/Layer). Without it the hover silently
  -- never appears.
  b:EnableMouse(true)
  -- `b.roundedMargin` records which mode built this button so SetVariant/OnEnable below can
  -- branch on it later -- a rounded bg is a textured region (SetVertexColor tints it),
  -- SetColorTexture on that same region would strip the texture file and leave a flat fill.
  b.roundedMargin = roundedSpec and roundedSpec.margin or nil
  if roundedSpec then
    b.bg = slicedTexture(b, "BACKGROUND", roundedSpec.bg, spec.bg or ROUNDED_GHOST_FILL, roundedSpec.margin)
    b.bg:SetAllPoints()
  else
    b.bg = solid(b, "BACKGROUND", spec.bg or { 0, 0, 0, 0 })
    b.bg:SetAllPoints()
  end

  -- Hover is a HIGHLIGHT-layer texture, not an OnEnter/OnLeave repaint. The engine draws that
  -- layer for exactly as long as the cursor is over the button and stops on its own, the same
  -- way UIPanelButtonTemplate works -- so a hover cannot be missed, cannot stick, and cannot
  -- survive the frame being hidden under a stationary cursor. Painting it by hand is what made
  -- these buttons feel broken: OnLeave is not delivered reliably when a frame is hidden or
  -- swapped, leaving a button stuck in the hovered fill or repainted for a state it had left.
  --
  -- One additive gold wash for every variant, rather than a per-variant colour: additive keeps
  -- it readable over a gold fill and over bare panel alike, and "the cursor is here" should
  -- look like one thing everywhere in this UI.
  b.highlightTexture = b:CreateTexture(nil, "HIGHLIGHT")
  b.highlightTexture:SetAllPoints()
  b.highlightTexture:SetBlendMode("ADD")
  if roundedSpec then
    -- A sliced ADD texture reads fine here -- the wash never needs a flat edge, only the
    -- rounded corners not to draw square outside the art.
    b.highlightTexture:SetTexture(roundedSpec.bg)
    b.highlightTexture:SetTextureSliceMargins(roundedSpec.margin, roundedSpec.margin, roundedSpec.margin, roundedSpec.margin)
    b.highlightTexture:SetVertexColor(HOVER_WASH[1], HOVER_WASH[2], HOVER_WASH[3], HOVER_WASH[4])
  else
    b.highlightTexture:SetColorTexture(HOVER_WASH[1], HOVER_WASH[2], HOVER_WASH[3], HOVER_WASH[4])
  end

  if roundedSpec then
    if roundedSpec.ring then
      b.ring = slicedTexture(b, "BORDER", roundedSpec.ring, T.color.border, roundedSpec.margin)
      b.ring:SetAllPoints()
    end
  else
    -- The border is drawn for every variant, at the variant's own strength: a ghost button
    -- needs it to have an edge at all, and a filled one keeps its shape while the fill is
    -- dimmed by OnDisable. Drawing it only for ghost meant a button that changed variant lost
    -- its outline.
    edgeBorder(b, T.color.border)
  end

  b.text = T.Label(b, 12)
  b.text:SetJustifyH("CENTER")
  b.text:ClearAllPoints()
  -- Bounded LEFT-to-RIGHT rather than pinned at CENTER. A CENTER-anchored FontString has no
  -- width of its own: it grows in both directions until the whole label fits, straight over
  -- whatever sits beside the button. English never showed it -- every label here is short --
  -- but the longer translations do, most visibly the Sell tab's "Set cost" in its 88px action
  -- column, which painted across the price column to its left. Word wrap off and one line mean
  -- the engine truncates within these bounds instead, so an over-long translation degrades to a
  -- clipped label inside its own button rather than damaging the row around it. SetMaxLines is
  -- not redundant with SetWordWrap: a label that still wraps in a ~22px button draws NOTHING at
  -- all, which is the worse of the two failures.
  -- Zero inset, deliberately. Callers already size these buttons to their longest ENGLISH
  -- label down to the pixel -- row.action's 86 is "the largest width that still leaves >=2px
  -- clearance" for "Cancel lot?" at 85.8px -- so any inset here would clip a label that fits
  -- today. Bounding at exactly the button's own edges takes nothing away from what already
  -- fits and only bites on the labels that are painting outside the button anyway.
  b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.text:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  b.text:SetWordWrap(false)
  b.text:SetMaxLines(1)
  if roundedSpec then
    b.text:SetFont(T.FONT_UI, 10 * T.Scale(), "")
    T.TrackFont(b.text, { role = "ui", path = T.FONT_UI, size = 10 })
  end

  -- `b.label` is the contract every caller and every spec test double already assumed --
  -- ACTION_HELP's tooltip lookup in UI/SellFrame.lua reads `self.label`, and every fake
  -- button in the test suite implements SetLabel by writing exactly this field. The real
  -- widget never did, so anything reading `.label` off a REAL button got nil forever; the
  -- fakes just made every test that depended on it look green. Set both: the FontString for
  -- what is drawn, `.label` for what callers read back.
  function b:SetLabel(text)
    b.label = text
    -- Lua 5.1's string.upper only touches bytes below 0x80 (ASCII); any byte >= 0x80 -- the
    -- lead/continuation bytes of a multi-byte UTF-8 sequence like ×/—/… -- passes through
    -- unchanged rather than being corrupted. b.label above stays the caller's exact SOURCE
    -- string either way; only the drawn FontString text is transformed.
    b.text:SetText(b.uppercase and text:upper() or text)
  end

  -- Draws the label upper-case without touching `.label` -- theme_button_contract_spec pins
  -- `btn.label == "Post"` even with uppercase on, since ACTION_HELP-style lookups and pooled-row
  -- rebinding both read `.label` as the exact string the caller passed. Re-invokes SetLabel so
  -- toggling this AFTER a label is already drawn re-renders it immediately, and calling it
  -- before any label exists is a harmless no-op that only takes effect on the next SetLabel.
  function b:SetUppercase(on)
    b.uppercase = on and true or nil
    if b.label then b:SetLabel(b.label) end
  end

  -- Switches a live button between variants. One control with two looks, rather than two
  -- controls taking turns being hidden.
  function b:SetVariant(name)
    spec = BUTTON_VARIANTS[name] or BUTTON_VARIANTS.ghost
    -- Rounded ghost (spec.bg == nil) falls back to ROUNDED_GHOST_FILL, not alpha-0 -- see that
    -- constant's own comment. `base` feeds OnEnable's restore below too, so that path inherits
    -- this fix for free -- it just repaints whatever `base` SetVariant last computed.
    base = spec.bg or (b.roundedMargin and ROUNDED_GHOST_FILL or { 0, 0, 0, 0 })
    -- `b.bg` in rounded mode is a textured region (see roundedMargin above): SetColorTexture
    -- there would erase the texture file and leave a flat fill, so recolor via SetVertexColor
    -- instead, the same way T.Card:SetTint does.
    if b.roundedMargin then
      b.bg:SetVertexColor(base[1], base[2], base[3], base[4] or 1)
    else
      b.bg:SetColorTexture(base[1], base[2], base[3], base[4] or 1)
    end
    b.text:SetTextColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4] or 1)
  end
  b:SetVariant(variant)

  -- An outline for the one badge button that should stand out of its list (the Sell row's
  -- Post). nil takes it off again: rows are pooled, and the next kind to take the row must not
  -- inherit it. Built on first use and kept, so a render does not mint a texture per call.
  function b:SetRing(c)
    if not c then
      if b.ring then b.ring:Hide() end
      return
    end
    if not b.ring then
      local file = roundedSpec and (roundedSpec.ring or roundedSpec.askedRing)
      if not file then return end
      b.ring = slicedTexture(b, "BORDER", file, c, roundedSpec.margin)
      b.ring:SetAllPoints()
      b.ringAsked = true
    end
    b.ring:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    b.ring:Show()
  end

  -- "A request of yours is out": the client's own spinner turning inside the button, left of
  -- the label. The owner pressed the Sell tab's Post and could not tell a post on its way from a
  -- dead button -- a dimmed label says "not now", not "working". The ring is Blizzard_SharedXML's
  -- SpinnerTemplate, the one its dialogs turn while a request is out (SpinnerMixin plays it on
  -- show and stops it on hide), so nothing here draws or drives an animation. A child frame, so
  -- OnDisable's dimming does not touch it: the one thing still moving on a disabled button is
  -- the thing saying why it is disabled. Built on first use -- a list of pooled rows would
  -- otherwise mint one per row -- and a client without the template keeps the label alone.
  -- The label is re-bounded to start after the ring: 2px in, 12px wide, 1px gap (the budgets in
  -- spec/button_label_width_spec.lua are that width less), and gets the whole button back after.
  -- A no-op when nothing changes: the Sell dock repaints its POST on every status line.
  function b:SetBusy(on)
    on = on and true or false
    if b.busy == on then return end
    b.busy = on
    if on and b.spinner == nil then
      local ok, spinner = pcall(CreateFrame, "Frame", nil, b, "SpinnerTemplate")
      b.spinner = ok and spinner or false -- false: asked once, and the client had none
      if b.spinner then
        b.spinner:SetSize(12, 12)
        b.spinner:SetPoint("LEFT", b, "LEFT", 2, 0)
        -- A frame made from Lua starts SHOWN, and SpinnerMixin plays the ring only from OnShow,
        -- which fires on a hidden-to-shown change. Hidden here, so the Show below is one: left
        -- shown, every button's first post sat beside a ring that did not turn (review I1).
        -- Blizzard never makes this template from Lua; its XML uses start hidden.
        b.spinner:Hide()
      end
    end
    if not b.spinner then return end
    b.text:ClearAllPoints()
    if on then
      b.spinner:Show()
      b.text:SetPoint("LEFT", b.spinner, "RIGHT", 1, 0)
    else
      b.spinner:Hide()
      b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    end
    b.text:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  end

  -- I3: Theme.Button has no template-driven disabled look (unlike UIPanelButtonTemplate) --
  -- without this, Disable() (loud-requote arm window, buy/requery timeouts, ...) left a
  -- button looking exactly as live/clickable as ever. Dims the background and switches text
  -- to fgDim; OnEnable restores the variant's own colors. Purely visual -- every call site's
  -- Enable()/Disable() logic is unchanged, and a caller that sets a custom text color right
  -- after Enable() (e.g. the red "Buy anyway" requote state) still wins, since that call
  -- happens synchronously afterward in the same Lua step, before the next render.
  b:SetScript("OnDisable", function()
    b.bg:SetAlpha(0.45)
    -- Only a ring SetRing drew: a plaque's own border keeps the button's shape while it is dim.
    if b.ringAsked then b.ring:SetAlpha(0.45) end
    b.text:SetTextColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3], T.color.fgDim[4] or 1)
    -- The engine keeps drawing HIGHLIGHT over a disabled button (that is how a dimmed control
    -- can still raise a tooltip), so the wash is hidden here instead of guarded in a script --
    -- hidden, not SetAlpha(0): see T.RailButton for how SetAlpha(1) turned the wash solid.
    b.highlightTexture:Hide()
  end)
  b:SetScript("OnEnable", function()
    b.bg:SetAlpha(1)
    if b.ringAsked then b.ring:SetAlpha(1) end
    -- Same rounded-vs-square branch as SetVariant above: SetColorTexture on a textured
    -- rounded bg would erase the texture file the re-enable path is meant to restore.
    if b.roundedMargin then
      b.bg:SetVertexColor(base[1], base[2], base[3], base[4] or 1)
    else
      b.bg:SetColorTexture(base[1], base[2], base[3], base[4] or 1)
    end
    b.text:SetTextColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4] or 1)
    b.highlightTexture:Show()
  end)

  return b
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
