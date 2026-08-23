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
  -- "The watch loop is polling this row." Its own colour on purpose: gold already means the
  -- cursor is here, and green and red already mean profit and loss. A state that persists
  -- while you look elsewhere cannot borrow a colour that means something else.
  watch   = { 0.35, 0.72, 0.90 },
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

T.MEDIA = "Interface\\AddOns\\GoldCap\\Media\\"
T.RAIL_W = 76

-- Rounded chrome comes from ONE white 64px rounded-rect PNG stretched with
-- SetTextureSliceMargins (nine-slice on a single texture, 10.2.0+ -- wiki:
-- API_TextureBase_SetTextureSliceMargins) and recolored via SetVertexColor.
-- White art + vertex color means one file serves every tint; regenerate the
-- PNGs with addon/tools/gen_art.py, never edit them by hand. Margins are 24
-- of the 64px file so the 16px corners survive any widget size.
local CARD_SLICE = 24

-- Drawn additively in the HIGHLIGHT layer by the engine while the cursor is over a button, so
-- it must stay subtle: it lands on top of a gold fill as readily as on bare panel.
local HOVER_WASH = { T.color.gold[1], T.color.gold[2], T.color.gold[3], 0.18 }

local function slicedTexture(parent, layer, file, c)
  local tx = parent:CreateTexture(nil, layer)
  tx:SetTexture(file)
  tx:SetTextureSliceMargins(CARD_SLICE, CARD_SLICE, CARD_SLICE, CARD_SLICE)
  tx:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  return tx
end

-- Card: rounded panel (fill + 2px ring). The rounded sibling of T.Panel; use
-- it for chrome that should read as a surface, keep T.Panel for flat fills.
function T.Card(parent, fill, border)
  local f = CreateFrame("Frame", nil, parent)
  f.bg = slicedTexture(f, "BACKGROUND", T.MEDIA .. "card.png", fill or T.color.panel)
  f.bg:SetAllPoints()
  f.ring = slicedTexture(f, "BORDER", T.MEDIA .. "ring.png", border or T.color.border)
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
  b.text:SetFont(T.FONT_MONO_BOLD, 8 * T.Scale(), "")
  b.text:SetPoint("BOTTOM", 0, 7)
  b.text:SetText(labelText)
  widgetFonts[b.text] = { path = T.FONT_MONO_BOLD, size = 8 }

  b.highlightTexture = b:CreateTexture(nil, "HIGHLIGHT")
  b.highlightTexture:SetAllPoints()
  b.highlightTexture:SetBlendMode("ADD")
  b.highlightTexture:SetColorTexture(HOVER_WASH[1], HOVER_WASH[2], HOVER_WASH[3], HOVER_WASH[4])

  -- The engine keeps drawing HIGHLIGHT over a disabled button (that is how a dimmed control
  -- can still raise a tooltip), so the wash is muted here instead of guarded in a script.
  b:SetScript("OnDisable", function() b.highlightTexture:SetAlpha(0) end)
  b:SetScript("OnEnable", function() b.highlightTexture:SetAlpha(1) end)

  b.badge = CreateFrame("Frame", nil, b)
  b.badge:SetHeight(14)
  b.badge:SetPoint("TOPRIGHT", -4, -4)
  b.badge.bg = slicedTexture(b.badge, "BACKGROUND", T.MEDIA .. "card.png", T.color.gold)
  b.badge.bg:SetAllPoints()
  b.badge.text = b.badge:CreateFontString(nil, "OVERLAY")
  b.badge.text:SetFont(T.FONT_MONO_BOLD, 9 * T.Scale(), "")
  b.badge.text:SetPoint("CENTER")
  b.badge.text:SetTextColor(BADGE_TEXT[1], BADGE_TEXT[2], BADGE_TEXT[3])
  widgetFonts[b.badge.text] = { path = T.FONT_MONO_BOLD, size = 9 }
  b.badge:Hide()

  function b:SetBadge(count)
    if count then
      b.badge.text:SetText(tostring(count))
      b.badge:SetWidth((14 + 6 * #tostring(count)) * T.Scale())
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

  local logo = T.Card(frame, T.color.gold, { T.color.goldHi[1], T.color.goldHi[2], T.color.goldHi[3], 0.5 })
  logo:SetSize(32, 32)
  logo:SetPoint("TOP", 0, -16)
  logo.text = logo:CreateFontString(nil, "OVERLAY")
  logo.text:SetFont(T.FONT_MONO_BOLD, 16 * T.Scale(), "")
  logo.text:SetPoint("CENTER")
  logo.text:SetText("G")
  logo.text:SetTextColor(BADGE_TEXT[1], BADGE_TEXT[2], BADGE_TEXT[3])
  widgetFonts[logo.text] = { path = T.FONT_MONO_BOLD, size = 16 }

  local buttons = {}
  local order = {
    { key = "deals", icon = "icon_deals.png", label = "DEALS" },
    { key = "sell", icon = "icon_sell.png", label = "SELL" },
    { key = "sold", icon = "icon_sold.png", label = "SOLD" },
  }
  local prev = logo
  for i, item in ipairs(order) do
    local b = T.RailButton(frame, T.MEDIA .. item.icon, item.label)
    b:SetPoint("TOP", prev, "BOTTOM", 0, i == 1 and -22 or -T.pad.s)
    buttons[item.key] = b
    prev = b
  end

  local gear = T.Button(frame, "ghost")
  gear:SetSize(28, 28)
  gear:SetPoint("BOTTOM", 0, 14)
  gear.icon = gear:CreateTexture(nil, "ARTWORK")
  gear.icon:SetTexture(T.MEDIA .. "icon_gear.png")
  gear.icon:SetSize(17, 17)
  gear.icon:SetPoint("CENTER")
  gear.icon:SetVertexColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3], 1)

  return { frame = frame, buttons = buttons, gear = gear }
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
  b.bg = solid(b, "BACKGROUND", spec.bg or { 0, 0, 0, 0 })
  b.bg:SetAllPoints()

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
  b.highlightTexture:SetColorTexture(HOVER_WASH[1], HOVER_WASH[2], HOVER_WASH[3], HOVER_WASH[4])

  -- The border is drawn for every variant, at the variant's own strength: a ghost button needs
  -- it to have an edge at all, and a filled one keeps its shape while the fill is dimmed by
  -- OnDisable. Drawing it only for ghost meant a button that changed variant lost its outline.
  edgeBorder(b, T.color.border)

  b.text = T.Label(b, 12)
  b.text:SetJustifyH("CENTER")
  b.text:ClearAllPoints()
  b.text:SetPoint("CENTER")

  -- `b.label` is the contract every caller and every spec test double already assumed --
  -- ACTION_HELP's tooltip lookup in UI/SellFrame.lua reads `self.label`, and every fake
  -- button in the test suite implements SetLabel by writing exactly this field. The real
  -- widget never did, so anything reading `.label` off a REAL button got nil forever; the
  -- fakes just made every test that depended on it look green. Set both: the FontString for
  -- what is drawn, `.label` for what callers read back.
  function b:SetLabel(text)
    b.label = text
    b.text:SetText(text)
  end

  -- Switches a live button between variants. One control with two looks, rather than two
  -- controls taking turns being hidden.
  function b:SetVariant(name)
    spec = BUTTON_VARIANTS[name] or BUTTON_VARIANTS.ghost
    base = spec.bg or { 0, 0, 0, 0 }
    b.bg:SetColorTexture(base[1], base[2], base[3], base[4] or 1)
    b.text:SetTextColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4] or 1)
  end
  b:SetVariant(variant)


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
    -- The engine keeps drawing HIGHLIGHT over a disabled button (that is how a dimmed control
    -- can still raise a tooltip), so the wash is muted here instead of guarded in a script.
    b.highlightTexture:SetAlpha(0)
  end)
  b:SetScript("OnEnable", function()
    b.bg:SetAlpha(1)
    b.bg:SetColorTexture(base[1], base[2], base[3], base[4] or 1)
    b.text:SetTextColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4] or 1)
    b.highlightTexture:SetAlpha(1)
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
  return { gear = gear, close = close, title = bar.title }
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
local QUALITY_CACHE = {}
local LEGACY_QUALITY_ATLAS = {
  "Professions-ChatIcon-Quality-Tier1",
  "Professions-ChatIcon-Quality-Tier2",
  "Professions-ChatIcon-Quality-Tier3",
  "Professions-ChatIcon-Quality-Tier4",
  "Professions-ChatIcon-Quality-Tier5",
}

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

local function atlasForQuality(itemID, quality)
  local cached = QUALITY_CACHE[itemID]
  if cached ~= nil then return cached ~= false and cached or nil end
  local atlas = atlasFromTooltip(itemID)
  if not atlas then
    -- The tooltip may simply not be cached client-side yet, which is temporary,
    -- so nothing is remembered in that case -- only a resolved answer is.
    local legacy = LEGACY_QUALITY_ATLAS[quality]
    if legacy and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(legacy) then
      QUALITY_CACHE[itemID] = legacy
      return legacy
    end
    return nil
  end
  QUALITY_CACHE[itemID] = atlas
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
  local atlas = atlasForQuality(itemID, quality)
  if not atlas then return "" end
  size = size or 14
  return ("|A:%s:%d:%d|a"):format(atlas, size, size)
end

--- `name` with its quality pip in front, or `name` unchanged. Convenience so a
-- caller never has to remember the trailing space.
function T.WithQuality(name, itemID, size)
  local markup = T.QualityMarkup(itemID, size)
  if markup == "" then return name end
  return markup .. " " .. tostring(name)
end
