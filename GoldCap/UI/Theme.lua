local _, GC = ...

GC.Theme = GC.Theme or {}
local T = GC.Theme

T.color = {
  bg      = { 0.051, 0.055, 0.071 },
  panel   = { 0.078, 0.086, 0.110 },
  panelHi = { 0.102, 0.114, 0.141 },
  border  = { 1, 1, 1, 0.06 },
  gold    = { 0.831, 0.643, 0.216 },
  goldHi  = { 0.910, 0.757, 0.353 },
  fg      = { 0.92, 0.91, 0.89 },
  fgMuted = { 0.72, 0.71, 0.69 },
  fgDim   = { 0.55, 0.54, 0.52 },
  red     = { 0.898, 0.283, 0.302 },
  green   = { 0.25, 0.85, 0.25 },
  zebra   = { 1, 1, 1, 0.04 },
  -- Hover is the brand gold, not a neutral white lift: on a panel this dark a white film just
  -- reads as "grayer", while a gold wash reads as "this is the row you are on".
  hover   = { 0.831, 0.643, 0.216, 0.16 },
}

T.tier = {
  HOT     = { 1, 0.35, 0.15 },
  GOOD    = { 0.25, 0.85, 0.25 },
  WATCH   = { 0.65, 0.65, 0.65 },
  SUSPECT = { 1, 0.85, 0.1 },
}

T.pad = { xs = 4, s = 8, m = 12, l = 16 }
T.ROW_H = 28

T.FONT_MONO = "Interface\\AddOns\\GoldCap\\Media\\JetBrainsMono-Regular.ttf"
T.FONT_MONO_BOLD = "Interface\\AddOns\\GoldCap\\Media\\JetBrainsMono-Bold.ttf"

local scale, hooks = 1.0, {}

-- Widget-bound re-fonting (Chip/Num fontstrings, created afresh on every row/cell) is
-- tracked as DATA in a weak-KEYED table, never as a closure. Lua 5.1 (WoW's runtime) has
-- no ephemeron tables: a weak-keyed table only collects an entry once NOTHING reachable
-- still points at the key, and that includes the entry's own VALUE. A closure stored as
-- the value captures the FontString (its key) as an upvalue -- e.g. `function() fs:SetFont(...)
-- end` -- so the value keeps its own key alive forever and the entry never collects. The
-- fix is to store a plain data table `{ path, size }` that holds NO reference back to the
-- FontString (or any parent frame): once nothing else references the FontString, the
-- weak-keyed entry is free to collect on the next GC cycle. SetScale does the SetFont
-- call itself, in its own scope, using the stored data.
local widgetFonts = setmetatable({}, { __mode = "k" })

function T.Scale()
  return scale
end

function T.OnRescale(fn)
  hooks[#hooks + 1] = fn
end

function T.SetScale(s)
  scale = math.max(0.9, math.min(1.3, s or 1.0))
  if GC.db and GC.db.settings and GC.db.settings.sniper then
    GC.db.settings.sniper.fontScale = scale
  end
  for _, fn in ipairs(hooks) do
    fn(scale)
  end
  for fs, info in pairs(widgetFonts) do
    fs:SetFont(info.path, info.size * scale, "")
  end
end

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

-- Chip: solid dark plaque + colored text + colored 1px underline.
function T.Chip(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(16)

  f.bg = solid(f, "BACKGROUND", { T.color.bg[1], T.color.bg[2], T.color.bg[3], 0.9 })
  f.bg:SetAllPoints()

  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetFont(T.FONT_MONO_BOLD, 10 * T.Scale(), "")
  f.text:SetJustifyH("CENTER")
  -- M14: bounded to the chip's own width (a bare CENTER point has no width limit at all) and
  -- non-wrapping, so a long label (e.g. "SUSPECT" plus the falling-tier marker) truncates
  -- inside the chip instead of overflowing into whatever sits to its right.
  f.text:SetPoint("LEFT", 2, 0)
  f.text:SetPoint("RIGHT", -2, 0)
  f.text:SetWordWrap(false)

  f.underline = solid(f, "ARTWORK", T.color.border)
  f.underline:SetPoint("BOTTOMLEFT")
  f.underline:SetPoint("BOTTOMRIGHT")
  f.underline:SetHeight(1)

  widgetFonts[f.text] = { path = T.FONT_MONO_BOLD, size = 10 }

  function f:SetLabel(text, colorTable)
    f.text:SetText(text)
    local c = colorTable or T.color.fg
    f.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    f.underline:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  end

  return f
end

-- Num: mono font, size*Scale(), RIGHT-justified. Re-fonts on rescale.
function T.Num(parent, size, bold)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local font = bold and T.FONT_MONO_BOLD or T.FONT_MONO
  fs:SetFont(font, size * T.Scale(), "")
  fs:SetJustifyH("RIGHT")
  widgetFonts[fs] = { path = font, size = size }
  return fs
end

-- Label: native font (keeps client glyph fallback for localized/item-name text), LEFT-justified.
-- Final fix wave (item 3): applies size*T.Scale() at creation (was a bare `size`, so a Label
-- never actually respected the current scale on first render) AND registers in widgetFonts
-- (same data-valued-weak-table idiom T.Num already uses -- see that table's own comment for
-- why the value must never close over `fs`), so SetScale's re-font pass now reaches every
-- Label too, not just Num/Chip fontstrings.
--
-- Deliberately NOT extended to ROW_H (Theme.ROW_H, ~28px) or the dialog's own pixel budgets --
-- those stay fixed regardless of T.Scale(). At 1.3x a Label's text can get visually tight
-- against an unscaled row/dialog height; that's an accepted tradeoff here (the in-game
-- checklist covers verifying it reads fine at the scale extremes), not a bug to fix by also
-- scaling layout geometry.
function T.Label(parent, size)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local fontPath, _, flags = fs:GetFont()
  if fontPath then
    fs:SetFont(fontPath, size * T.Scale(), flags)
    widgetFonts[fs] = { path = fontPath, size = size }
  end
  fs:SetJustifyH("LEFT")
  return fs
end

-- Hover always LIGHTENS, for every variant. An earlier revision darkened instead, to stop a
-- white film reading as "gray" beside the gold primary; on a panel this dark that overshot the
-- other way -- hovering the gold Auto button turned it nearly black, which reads as disabled
-- rather than as the thing under your cursor. Lightening both variants keeps the direction
-- consistent (the two Auto buttons swap in place, so they must agree) and keeps a hovered
-- control looking live.
local function lightened(c)
  return { c[1] + (1 - c[1]) * 0.18, c[2] + (1 - c[2]) * 0.18, c[3] + (1 - c[3]) * 0.18, c[4] or 1 }
end

-- Ghost buttons have no fill of their own, so their hover IS the fill: a gold wash, the same
-- accent the hovered row uses, so "under the cursor" always looks like one thing in this UI.
local GHOST_HOVER = { T.color.gold[1], T.color.gold[2], T.color.gold[3], 0.22 }

local BUTTON_VARIANTS = {
  primary = { bg = T.color.gold, text = { 0.05, 0.05, 0.06 } },
  ghost   = { bg = nil, text = T.color.fg },
  danger  = { bg = T.color.red, text = T.color.fg },
}

-- Button: variant "primary" (gold bg, dark text) | "ghost" (border only) | "danger" (red bg).
function T.Button(parent, variant)
  local spec = BUTTON_VARIANTS[variant] or BUTTON_VARIANTS.ghost
  -- Held on the button, not captured as upvalues, so SetVariant below can genuinely change how
  -- a live button looks. Capturing them made a repaint impossible: the next OnEnter/OnLeave
  -- would stomp it back, which is why the Auto control used to be two overlaid buttons swapped
  -- by Show/Hide -- and that swap is what made it flicker, miss hovers, and reappear painted in
  -- a stale state under a stationary cursor.
  local b = CreateFrame("Button", nil, parent)
  local base, hoverColor
  -- I2: LEFT-click only. This reverses an earlier "AnyUp" choice -- a purchase-flow button
  -- (row Buy, dialog primary/Confirm) must never let a right- or middle-click reach
  -- PlaceBid/StartCommoditiesPurchase/ConfirmCommoditiesPurchase; only a left-click OnClick
  -- may fire.
  b:RegisterForClicks("LeftButtonUp")
  b.bg = solid(b, "BACKGROUND", spec.bg or { 0, 0, 0, 0 })
  b.bg:SetAllPoints()

  -- The border is drawn for every variant, at the variant's own strength: a ghost button needs
  -- it to have an edge at all, and a filled one keeps its shape while the fill is dimmed by
  -- OnDisable. Drawing it only for ghost meant a button that changed variant lost its outline.
  edgeBorder(b, T.color.border)

  b.text = T.Label(b, 12)
  b.text:SetJustifyH("CENTER")
  b.text:ClearAllPoints()
  b.text:SetPoint("CENTER")

  function b:SetLabel(text)
    b.text:SetText(text)
  end

  -- Switches a live button between variants. One control with two looks, rather than two
  -- controls taking turns being hidden.
  function b:SetVariant(name)
    spec = BUTTON_VARIANTS[name] or BUTTON_VARIANTS.ghost
    base = spec.bg or { 0, 0, 0, 0 }
    hoverColor = spec.bg and lightened(spec.bg) or GHOST_HOVER
    local hovered = b.IsMouseOver and b:IsMouseOver() and b:IsEnabled()
    local paint = hovered and hoverColor or base
    b.bg:SetColorTexture(paint[1], paint[2], paint[3], paint[4] or 1)
    b.text:SetTextColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4] or 1)
  end
  b:SetVariant(variant)

  -- I3: hover-brighten only applies while enabled -- a disabled button (see OnDisable below)
  -- still receives OnEnter/OnLeave in WoW (that's how a disabled control can still show an
  -- explanatory tooltip), so without this guard hovering a dimmed/disabled button would
  -- brighten it right back to looking clickable.
  b:SetScript("OnEnter", function()
    if not b:IsEnabled() then return end
    b.bg:SetColorTexture(hoverColor[1], hoverColor[2], hoverColor[3], hoverColor[4] or 1)
  end)
  b:SetScript("OnLeave", function()
    if not b:IsEnabled() then return end
    b.bg:SetColorTexture(base[1], base[2], base[3], base[4] or 1)
  end)

  -- I3: Theme.Button has no template-driven disabled look (unlike UIPanelButtonTemplate) --
  -- without this, Disable() (loud-requote arm window, buy/requery timeouts, ...) left a
  -- button looking exactly as live/clickable as ever. Dims the background and switches text
  -- to fgDim; OnEnable restores the variant's own colors. Purely visual -- every call site's
  -- Enable()/Disable() logic is unchanged, and a caller that sets a custom text color right
  -- after Enable() (e.g. the red "Buy anyway" requote state) still wins, since that call
  -- happens synchronously afterward in the same Lua step, before the next render.
  b:SetScript("OnDisable", function()
    b.bg:SetAlpha(0.45)
    b.text:SetTextColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3], T.color.fgDim[4] or 1)
  end)
  b:SetScript("OnEnable", function()
    b.bg:SetAlpha(1)
    b.bg:SetColorTexture(base[1], base[2], base[3], base[4] or 1)
    b.text:SetTextColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4] or 1)
  end)

  -- Hiding a hovered frame doesn't reliably deliver OnLeave, so a button that goes away under
  -- a stationary cursor would keep its hover fill and reappear pre-painted.
  b:SetScript("OnHide", function()
    b.bg:SetColorTexture(base[1], base[2], base[3], base[4] or 1)
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
    frame:StartMoving()
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

  return { gear = gear, close = close }
end
