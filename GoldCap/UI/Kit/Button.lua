-- Theme.Button: one control per button, variants switched in place, hover in the engine's
-- HIGHLIGHT layer, pressed in its pushed state. Moved out of UI/Theme.lua and restyled for the
-- dark-glass look: condensed labels, a glow under the primary action, a darker face while held.
local _, GC = ...
GC.Theme = GC.Theme or {}
local T = GC.Theme
local MEDIA = GC.Kit.MEDIA
local K = GC.Kit.Tokens.color

local HOVER_WASH = K.hoverWash
-- A square button's edge, and the shade the engine lays over any button while it is held.
local SQUARE_EDGE = { 1, 1, 1, 0.11 }
local PRESSED = { 0, 0, 0, 0.28 }
-- A disabled button draws its fill and ring at this share of their own alpha.
local DIM = 0.45
local PRIMARY_GLOW = { K.gold[1], K.gold[2], K.gold[3], 0.35 }
local DANGER_GLOW = { K.loss[1], K.loss[2], K.loss[3], 0.35 }

-- A trailing ▼ or ▲ on a label ("SHOW DETAILS ▼", a picker's "All ▼"): drawn as the atlas caret at
-- the right edge, because the condensed face has neither triangle (docs/addon/tools/fonts.py).
local CARETS = { ["\226\150\188"] = "caretDown", ["\226\150\178"] = "caretUp" } -- U+25BC ▼, U+25B2 ▲
local function splitCaret(text)
  local body, glyph = tostring(text):match("^(.-)%s*(\226\150[\178\188])$")
  if body then return body, CARETS[glyph] end
  return text, nil
end

-- `primary` is dark-on-gold, which is only legible while the gold fill is actually painted.
-- That is fine for a button built primary and left that way (the dialog's Buy/Confirm), but it
-- is a trap for a control that toggles: the Auto button was showing near-black text on a fill
-- that had not gone gold, leaving the label all but invisible. `active` states the same "this
-- is on" with gold TEXT over a faint gold tint, so the label survives no matter what the fill
-- is doing -- there is no state in which it becomes unreadable.
local BUTTON_VARIANTS = {
  primary = { bg = K.gold, text = K.onGold },
  active  = { bg = { K.gold[1], K.gold[2], K.gold[3], 0.14 }, text = K.goldText },
  ghost   = { bg = nil, text = K.text1 },
  danger  = { bg = K.lossFill, text = { 0.102, 0.024, 0.024 } },
  -- Attention without alarm: a purchase that is real but not the whole line (the BUY tab's
  -- capped fill). Red is what CANCEL and losses wear and reads as "do not".
  warn    = { bg = { K.warn[1], K.warn[2], K.warn[3], 0.16 }, text = K.warn },
}

-- rounded T.Button: file + margin per size class, keyed the same way T.Card's `small`
-- picks plaque over card -- badge is one size class down again (T.SLICE.badge, no ring: see
-- T.SLICE.badge's own comment, the same 16px art is too small for a second nine-slice ring
-- on top of its fill without the two notching each other).
local ROUNDED_BUTTON = {
  plaque = { bg = MEDIA .. "plaque.png", ring = MEDIA .. "plaque_ring.png", margin = T.SLICE.plaque },
  -- `askedRing`: badge_ring.png, a 1px outline on badge.png's own radius. Not drawn unless the
  -- caller asks (b:SetRing below) -- a badge button is a row control, and a list of outlined
  -- ones is a grid of boxes.
  badge  = { bg = MEDIA .. "badge.png", ring = nil, askedRing = MEDIA .. "badge_ring.png", margin = T.SLICE.badge },
}

-- Square mode's ghost has no fill by design -- T.EdgeBorder (below) draws its outline instead.
-- Rounded mode drops T.EdgeBorder entirely, and "badge" rounded buttons get no ring either (too
-- small for the ring art -- ROUNDED_BUTTON's own comment), so a rounded ghost painted with the
-- same alpha-0 fill has zero at-rest boundary: the row Buy button's "Check" state was bare
-- text. A faint white fill gives rounded ghost the affordance square ghost got from its border.
local ROUNDED_GHOST_FILL = { 1, 1, 1, 0.05 }

-- Button: variant "primary" (gold bg, dark text) | "ghost" (border only) | "danger" (red bg).
-- `rounded` (nil | "plaque" | "badge"): nil keeps the original square look (solid bg,
-- T.EdgeBorder) unchanged. "plaque"/"badge" swap the bg and hover wash for sliced textures of
-- that art (ROUNDED_BUTTON above) and drop the square T.EdgeBorder -- "plaque" gets a sliced
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
    b.bg = T.SlicedTexture(b, "BACKGROUND", roundedSpec.bg, spec.bg or ROUNDED_GHOST_FILL, roundedSpec.margin)
    b.bg:SetAllPoints()
  else
    b.bg = T.Solid(b, "BACKGROUND", spec.bg or { 0, 0, 0, 0 })
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

  -- Pressed: the engine shows the pushed texture for exactly as long as the button is held, the
  -- way it shows HIGHLIGHT under the cursor -- nothing to get stuck if the button hides mid-press.
  if roundedSpec then
    b.pressedTexture = T.SlicedTexture(b, "ARTWORK", roundedSpec.bg, PRESSED, roundedSpec.margin)
  else
    b.pressedTexture = T.Solid(b, "ARTWORK", PRESSED)
  end
  b.pressedTexture:SetAllPoints()
  b:SetPushedTexture(b.pressedTexture)

  -- A soft halo under the main action, only while it is live: a dim button with a bright glow
  -- reads as clickable. A primary button wears it in gold unless told not to; a danger one, in
  -- red, only when asked: b:SetGlow(true) or (false), nil for the variant's own say (the Sell
  -- dock's POST and CANCEL are the only ones on that tab, the owner's call of 2026-10-09).
  -- Built on first need.
  local glowAsked
  local function paintGlow()
    local danger = spec == BUTTON_VARIANTS.danger
    local glows = spec == BUTTON_VARIANTS.primary or (danger and glowAsked == true)
    local want = glows and glowAsked ~= false and not b.dimmed
    if want and not b.glow then b.glow = T.Glow(b, PRIMARY_GLOW, 12) end
    if b.glow then
      local c = danger and DANGER_GLOW or PRIMARY_GLOW
      b.glow:SetVertexColor(c[1], c[2], c[3], c[4])
      if want then b.glow:Show() else b.glow:Hide() end
    end
  end
  function b:SetGlow(on)
    glowAsked = on
    paintGlow()
  end

  if roundedSpec then
    if roundedSpec.ring then
      b.ring = T.SlicedTexture(b, "BORDER", roundedSpec.ring, K.glassBorder, roundedSpec.margin)
      b.ring:SetAllPoints()
    end
  else
    -- The border is drawn for every variant, at the variant's own strength: a ghost button
    -- needs it to have an edge at all, and a filled one keeps its shape while the fill is
    -- dimmed by OnDisable. Drawing it only for ghost meant a button that changed variant lost
    -- its outline.
    T.EdgeBorder(b, SQUARE_EDGE)
  end

  -- The condensed face (T.Heading), 10 on a rounded button and 12 on a square one. Fira Sans
  -- Condensed Bold averages 0.47 em a lower-case Latin letter, 0.54 em a Latin capital and 0.61 em
  -- a Cyrillic capital (measured from the font file): at 10 that is within 2% of the mono-10 the
  -- rounded buttons drew before, which spec/button_label_width_spec.lua's budgets were set for.
  b.text = T.Heading(b, roundedSpec and 10 or 12)
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

  -- `b.label` is the contract every caller and every spec test double already assumed --
  -- ACTION_HELP's tooltip lookup in UI/Sell/Row.lua reads `self.label`, and every fake
  -- button in the test suite implements SetLabel by writing exactly this field. The real
  -- widget never did, so anything reading `.label` off a REAL button got nil forever; the
  -- fakes just made every test that depended on it look green. Set both: the FontString for
  -- what is drawn, `.label` for what callers read back.
  function b:SetLabel(text)
    b.label = text
    local shown, caret = splitCaret(text)
    if caret then
      if not b.caret then
        b.caret = b:CreateTexture(nil, "OVERLAY")
        b.caret:SetSize(10, 10)
        b.caret:SetPoint("RIGHT", b, "RIGHT", -6, 0)
      end
      T.SetIcon(b.caret, caret, b.dimmed and K.text3 or spec.text)
      b.caret:Show()
    elseif b.caret then
      b.caret:Hide()
    end
    b.text:SetPoint("RIGHT", b, "RIGHT", caret and -16 or 0, 0)
    -- Lua 5.1's string.upper only touches bytes below 0x80 (ASCII); any byte >= 0x80 -- the
    -- lead/continuation bytes of a multi-byte UTF-8 sequence like ×/—/… -- passes through
    -- unchanged rather than being corrupted. b.label above stays the caller's exact SOURCE
    -- string either way; only the drawn FontString text is transformed.
    b.text:SetText(b.uppercase and shown:upper() or shown)
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

  -- The fill in its variant's colour, dimmed to 0.45 of its own alpha while disabled. Dimmed by
  -- re-tinting, never by Texture:SetAlpha: in the client SetAlpha REPLACES the alpha
  -- SetVertexColor set (see T.RailButton), so SetAlpha(0.45) turned a 5% ghost wash into a light
  -- plate and SetAlpha(1) turned it solid on enable.
  local function paintFill()
    local a = (base[4] or 1) * (b.dimmed and DIM or 1)
    -- `b.bg` in rounded mode is a textured region (see roundedMargin above): SetColorTexture
    -- there would erase the texture file and leave a flat fill, so recolor via SetVertexColor
    -- instead, the same way T.Card:SetTint does.
    if b.roundedMargin then
      b.bg:SetVertexColor(base[1], base[2], base[3], a)
    else
      b.bg:SetColorTexture(base[1], base[2], base[3], a)
    end
  end

  -- Switches a live button between variants. One control with two looks, rather than two
  -- controls taking turns being hidden.
  function b:SetVariant(name)
    spec = BUTTON_VARIANTS[name] or BUTTON_VARIANTS.ghost
    -- Rounded ghost (spec.bg == nil) falls back to ROUNDED_GHOST_FILL, not alpha-0 -- see that
    -- constant's own comment. `base` feeds OnEnable's restore below too, so that path inherits
    -- this fix for free -- it just repaints whatever `base` SetVariant last computed.
    base = spec.bg or (b.roundedMargin and ROUNDED_GHOST_FILL or { 0, 0, 0, 0 })
    paintFill()
    b.text:SetTextColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4] or 1)
    if b.caret then b.caret:SetVertexColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4] or 1) end
    paintGlow()
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
      b.ring = T.SlicedTexture(b, "BORDER", file, c, roundedSpec.margin)
      b.ring:SetAllPoints()
      b.ringAsked = true
    end
    b.ringColor = c
    b.ring:SetVertexColor(c[1], c[2], c[3], (c[4] or 1) * (b.dimmed and DIM or 1))
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
    b.text:SetPoint("RIGHT", b, "RIGHT", (b.caret and b.caret:IsShown()) and -16 or 0, 0)
  end

  -- I3: Theme.Button has no template-driven disabled look (unlike UIPanelButtonTemplate) --
  -- without this, Disable() (loud-requote arm window, buy/requery timeouts, ...) left a
  -- button looking exactly as live/clickable as ever. Dims the background and switches text
  -- to fgDim; OnEnable restores the variant's own colors. Purely visual -- every call site's
  -- Enable()/Disable() logic is unchanged, and a caller that sets a custom text color right
  -- after Enable() (e.g. the red "Buy anyway" requote state) still wins, since that call
  -- happens synchronously afterward in the same Lua step, before the next render.
  b:SetScript("OnDisable", function()
    b.dimmed = true
    paintFill()
    -- Only a ring SetRing drew: a plaque's own border keeps the button's shape while it is dim.
    if b.ringAsked then
      local c = b.ringColor
      b.ring:SetVertexColor(c[1], c[2], c[3], (c[4] or 1) * DIM)
    end
    b.text:SetTextColor(K.text3[1], K.text3[2], K.text3[3], 1)
    -- The engine keeps drawing HIGHLIGHT over a disabled button (that is how a dimmed control
    -- can still raise a tooltip), so the wash is hidden here instead of guarded in a script --
    -- hidden, not SetAlpha(0): see T.RailButton for how SetAlpha(1) turned the wash solid.
    b.highlightTexture:Hide()
    if b.caret then b.caret:SetVertexColor(K.text3[1], K.text3[2], K.text3[3], 1) end
    paintGlow()
  end)
  b:SetScript("OnEnable", function()
    b.dimmed = nil
    paintFill()
    if b.ringAsked then
      local c = b.ringColor
      b.ring:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
    b.text:SetTextColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4] or 1)
    b.highlightTexture:Show()
    if b.caret then b.caret:SetVertexColor(spec.text[1], spec.text[2], spec.text[3], spec.text[4] or 1) end
    paintGlow()
  end)

  return b
end
