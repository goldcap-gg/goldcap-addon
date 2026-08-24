local _, GC = ...
local Theme = GC.Theme

GC.SettingsUI = GC.SettingsUI or {}

-- ============================================================================
-- T10: in-game settings panel. An overlay Theme.Panel drawn ON TOP of the
-- Sniper window's own content -- never a second floating window. The title
-- bar (title text, gear, close) lives on GoldCapSniperFrame itself and stays
-- visible/live above this overlay: the gear toggles the overlay back off, and
-- the window's own [X] still closes the whole addon window regardless of
-- whether the overlay is showing.
-- ============================================================================

local function cfg()
  return GC.db and GC.db.settings and GC.db.settings.sniper
end

-- ---------------------------------------------------------------------------
-- Minimal Theme-consistent widgets (bordered box / editbox / checkbox /
-- slider). Theme.lua has factories for Panel/Card/Chip/Num/Label/Button/
-- TitleBar because every one of those is reused across SniperFrame +
-- SellFrame + ImportDialog + Tooltip. Nothing else in the addon needs a
-- slider, a checkbox, or a raw numeric input -- this settings screen is the
-- only consumer -- so adding first-class Theme factories for them now would
-- be speculative API surface nobody else calls. These stay built inline,
-- reusing Theme's own colors/fonts/pad/slice constants so they still look
-- like Theme widgets.
--
-- Batch 5 moved the editbox onto the kit's rounded chrome: its box
-- (editBoxBg below) is a sliced badge.png background (Theme.SlicedTexture,
-- margin 6, valid on its 64x20 size) tinted between Theme.color.bg and a
-- faint gold wash on focus via SetFocusTint(on), not ringed with a separate
-- recolorable border -- a vertex-colored sliced texture has no independent
-- edge layer to brighten, only a whole-fill tint. borderedBox (flat bg + 4
-- recolorable hairline edges) survives unchanged below for the checkbox and
-- slider track, which still want a square, border-recolorable look -- Task 5
-- replaces those controls with the kit's own pill toggle / rounded slider
-- and decides then whether borderedBox has any callers left.
-- ---------------------------------------------------------------------------

-- A bordered dark box with a recolorable border. Theme.Panel also draws a
-- flat dark bg + 1px border, but its border textures are private locals
-- inside Theme.lua's `edgeBorder` helper and are never attached to the
-- returned frame -- there is no way to brighten them for a focus/hover accent
-- from outside Theme.lua. Reimplemented here, minimally, for exactly that
-- reason (checkboxes/slider track want a gold border on hover; the editbox
-- has its own rounded box below instead).
local function borderedBox(parent)
  local f = CreateFrame("Frame", nil, parent)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(Theme.color.bg[1], Theme.color.bg[2], Theme.color.bg[3], 1)

  local edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local e = f:CreateTexture(nil, "BORDER")
    if side == "TOP" or side == "BOTTOM" then
      e:SetPoint(side .. "LEFT")
      e:SetPoint(side .. "RIGHT")
      e:SetHeight(1)
    else
      e:SetPoint("TOP" .. side)
      e:SetPoint("BOTTOM" .. side)
      e:SetWidth(1)
    end
    edges[#edges + 1] = e
  end

  local function paint(c)
    for _, e in ipairs(edges) do
      e:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
  end
  paint(Theme.color.border)

  function f:SetBorderColor(c)
    paint(c)
  end

  return f
end

-- Rounded editbox background: sliced badge.png (margin 6, valid at this box's 64x20 size),
-- recolored between Theme.color.bg and a faint gold wash via :SetFocusTint(on) rather than a
-- recolorable border -- see the design comment above borderedBox for why the editbox no longer
-- uses that widget.
local function editBoxBg(parent)
  local f = CreateFrame("Frame", nil, parent)
  local bg = Theme.SlicedTexture(f, "BACKGROUND", Theme.MEDIA .. "badge.png", Theme.color.bg, 6)
  bg:SetAllPoints()

  function f:SetFocusTint(on)
    if on then
      bg:SetVertexColor(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 0.25)
    else
      bg:SetVertexColor(Theme.color.bg[1], Theme.color.bg[2], Theme.color.bg[3], 1)
    end
  end

  return f
end

-- Numeric editbox: mono font, centered, gold tint on focus (SetFocusTint). Returns the rounded
-- wrapper box (positionable) with `.editBox` set to the real EditBox (for :GetText/:SetText/
-- binding scripts). Validation/clamp policy lives in bindNumberField below, not here -- this
-- only builds the widget.
local function makeEditBox(parent, width, height)
  local box = editBoxBg(parent)
  box:SetSize(width, height or 20)

  local eb = CreateFrame("EditBox", nil, box)
  eb:SetPoint("TOPLEFT", 4, -1)
  eb:SetPoint("BOTTOMRIGHT", -4, 1)
  eb:SetAutoFocus(false)
  eb:SetJustifyH("CENTER")
  eb:SetMaxLetters(6)
  eb:SetFont(Theme.FONT_MONO, 12 * Theme.Scale(), "")
  eb:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
  -- Escape clears focus (cancels the in-progress edit) rather than bubbling up to the
  -- overlay's own ESC-closes-panel handler below -- EditBox's OnEscapePressed is a distinct
  -- script event that fires before any generic keyboard capture on a parent, so this alone is
  -- enough to keep "backspace out of a bad number" from also closing the whole settings panel.
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  eb:SetScript("OnEnterPressed", eb.ClearFocus) -- commits via OnEditFocusLost below
  eb:SetScript("OnEditFocusGained", function() box:SetFocusTint(true) end)
  eb:SetScript("OnEditFocusLost", function() box:SetFocusTint(false) end)

  -- Live font-scale slider support: Theme.Num/Chip re-font themselves on rescale via Theme.lua's
  -- own private weak-keyed `widgetFonts` table, which isn't reachable from outside Theme.lua.
  -- Theme.OnRescale is the public hook for exactly this case (a non-Theme-factory widget that
  -- still needs to track T.Scale()).
  Theme.OnRescale(function(scale)
    eb:SetFont(Theme.FONT_MONO, 12 * scale, "")
  end)

  box.editBox = eb
  return box
end

-- Checkbox: a real CreateFrame("CheckButton") for its built-in checked-state semantics
-- (GetChecked/SetChecked, auto-flip on click) -- but with no template, so it carries none of
-- UICheckButtonTemplate's default artwork/sizing. The checkmark is a plain gold square texture
-- set as the CheckButton's checked-texture, matching Theme's flat/no-icon aesthetic.
local function makeCheckbox(parent, size)
  size = size or 18
  local box = borderedBox(parent)
  box:SetSize(size, size)

  local cb = CreateFrame("CheckButton", nil, box)
  cb:SetAllPoints()
  cb:RegisterForClicks("LeftButtonUp")

  local mark = cb:CreateTexture(nil, "ARTWORK")
  mark:SetPoint("TOPLEFT", 3, -3)
  mark:SetPoint("BOTTOMRIGHT", -3, 3)
  mark:SetColorTexture(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 1)
  cb:SetCheckedTexture(mark)

  cb:SetScript("OnEnter", function() box:SetBorderColor(Theme.color.gold) end)
  cb:SetScript("OnLeave", function() box:SetBorderColor(Theme.color.border) end)

  box.checkButton = cb
  return box
end

-- Slider: a bare CreateFrame("Slider") -- deliberately NOT OptionsSliderTemplate, which also
-- creates its own title/low/high FontString trio and a default Blizzard thumb texture that
-- would have to be hidden/reworked piece by piece to match Theme. The bare Slider widget type
-- still gives real drag/click-to-set/keyboard-step mechanics for free via
-- SetMinMaxValues/SetValueStep/SetObeyStepOnDrag -- only the visuals (track + thumb) are ours,
-- so this is "Blizzard template for functionality, restyled" rather than a hand-rolled drag
-- implementation.
local function makeSlider(parent, width, min, max, step)
  local track = borderedBox(parent)
  track:SetSize(width, 4)

  local slider = CreateFrame("Slider", nil, parent)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(width, 16)
  slider:SetPoint("LEFT", track, "LEFT", 0, 0) -- vertically centers the 16px slider on the 4px track
  slider:SetMinMaxValues(min, max)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)

  local thumb = slider:CreateTexture(nil, "OVERLAY")
  thumb:SetSize(10, 16)
  thumb:SetColorTexture(Theme.color.gold[1], Theme.color.gold[2], Theme.color.gold[3], 1)
  slider:SetThumbTexture(thumb)

  return slider, track
end

-- ---------------------------------------------------------------------------
-- Binding helpers: wire a built widget to a GC.db.settings.sniper[key], with
-- validation/clamp policy centralized here rather than duplicated per field.
-- ---------------------------------------------------------------------------

-- Binds an editbox to GC.db.settings.sniper[key]. `toUI`/`toStorage` convert between the value
-- as TYPED (UI units) and the value as STORED (storage units) -- e.g. hotDiscount/goodDiscount
-- are stored as 0..1 FRACTIONS (see Core/Init.lua's GC.DEFAULTS) while this settings screen
-- shows/accepts whole PERCENT (1-90); hotMinSold/goodMinSold/dumpTrendPct need no conversion,
-- so those fields simply omit toUI/toStorage. `min`/`max` clamp in UI units, matching the task
-- brief's ranges (discounts 1-90, sold 0-1000, trend 1-99). Invalid (non-numeric) OR
-- out-of-range input on focus-lost is clamped/reverted and the box is re-stamped from the
-- stored value -- never left showing something that was silently rejected without visual
-- feedback.
local function bindNumberField(box, key, opts)
  local eb = box.editBox
  local toUI = opts.toUI or function(v) return v end
  local toStorage = opts.toStorage or function(v) return v end

  local function display()
    local c = cfg()
    local stored = c and c[key]
    if stored == nil then
      local d = GC.DEFAULTS and GC.DEFAULTS.settings and GC.DEFAULTS.settings.sniper
      stored = d and d[key] or 0
    end
    local ui = toUI(stored)
    eb:SetText(string.format("%.0f", ui))
  end

  eb:SetScript("OnEditFocusLost", function(self)
    local num = tonumber(self:GetText())
    local c = cfg()
    if not num or not c then
      display()
      return
    end
    if num < opts.min then num = opts.min end
    if num > opts.max then num = opts.max end
    num = math.floor(num + 0.5) -- every field here is whole-number in UI units
    c[key] = toStorage(num)
    display()
  end)

  display()
  return display
end

-- Binds a checkbox to a boolean GC.db.settings.sniper[key].
local function bindCheckbox(box, key)
  local cb = box.checkButton

  local function display()
    local c = cfg()
    cb:SetChecked(c and c[key] and true or false)
  end

  cb:SetScript("OnClick", function(self)
    local c = cfg()
    if c then c[key] = self:GetChecked() and true or false end
  end)

  display()
  return display
end

-- Cycles GC.db.settings.sniper.postDuration through the three durations
-- C_AuctionHouse.PostCommodity/PostItem accept -- 1 = 12h, 2 = 24h, 3 = 48h, see Core/Init.lua's
-- own comment on that field. A numeric field (like the ones bindNumberField above builds) would
-- happily let a player type a 4th value the API would reject; a three-state cycle can't express
-- a duration that does not exist.
local DURATION_LABELS = { [1] = "Duration: 12h", [2] = "Duration: 24h", [3] = "Duration: 48h" }

local function bindDurationButton(button)
  -- Same "invalid/missing falls back to the default" contract as UI/SellFrame.lua's own
  -- postDuration() reader -- this control must never show, let alone cycle from, a value that
  -- reader would refuse to post at.
  local function storedValue()
    local c = cfg()
    local value = c and c.postDuration
    if value == 1 or value == 2 or value == 3 then return value end
    local d = GC.DEFAULTS and GC.DEFAULTS.settings and GC.DEFAULTS.settings.sniper
    local default = d and d.postDuration
    return (default == 1 or default == 2 or default == 3) and default or 2
  end

  local function display()
    button:SetLabel(DURATION_LABELS[storedValue()])
  end

  button:SetScript("OnClick", function()
    local c = cfg()
    if not c then return end
    c.postDuration = (storedValue() % 3) + 1
    display()
  end)

  display()
  return display
end

-- Binds the font-scale slider straight to GC.Theme.SetScale -- live (every drag tick rescales
-- the whole addon's already-built widgets via Theme's OnRescale hooks/widgetFonts), and
-- self-persisting (Theme.SetScale itself writes GC.db.settings.sniper.fontScale on every call,
-- see Theme.lua -- no extra plumbing needed here).
-- Fix round 1 (M4): `display()` below calls slider:SetValue(...) to re-sync the widget from
-- Theme's current scale (on build, and every panel Show -- see the OnShow refresh loop) -- in
-- the REAL client SetValue fires OnValueChanged exactly like a user drag does, so without a
-- guard, every re-sync would re-enter Theme.SetScale with a value that's already current. Harmless
-- by itself (SetScale is idempotent for an unchanged value), but wasteful (re-walks every
-- registered OnRescale hook + the widgetFonts table on every panel open) and, if a future
-- Theme.OnRescale hook ever gains a side effect beyond re-fonting, a latent re-entrancy trap. A
-- module-local suppress flag distinguishes "this SetValue came from display()" from "this
-- OnValueChanged came from an actual drag/click/keyboard step."
local function bindFontSlider(slider, readout)
  local suppress = false

  slider:SetScript("OnValueChanged", function(_, value)
    if suppress then return end
    Theme.SetScale(value)
    readout:SetText(string.format("%.2fx", Theme.Scale()))
  end)

  local function display()
    suppress = true
    slider:SetValue(Theme.Scale())
    suppress = false
    readout:SetText(string.format("%.2fx", Theme.Scale()))
  end

  display()
  return display
end

-- Reset window: clears the persisted geometry and re-applies the built-in default straight to
-- the LIVE frame -- found via its global name (CreateFrame("Frame", "GoldCapSniperFrame", ...)
-- in SniperFrame.lua's createFrame auto-publishes it to _G, real WoW WidgetAPI behavior).
-- Deliberately NOT routed through SniperFrame.lua's persistWindowGeometry/
-- StopMovingOrSizing hook: that function's whole job is to WRITE the current geometry back into
-- settings.sniper.window, which would immediately re-persist the very position/size this button
-- exists to clear. SetSize below still fires the window's own OnSizeChanged script (SniperFrame
-- .lua's createFrame wires that unconditionally, not gated on how the resize happened), so the
-- column grid re-flows to the restored width with no extra plumbing from here.
--
-- Batch 5: the default geometry comes straight from GC.Sniper.DefaultWindowSize() (SniperFrame
-- .lua, next to its other GC.Sniper.* exports) instead of a mirrored local constant here -- this
-- file used to carry its own DEFAULT_WINDOW_WIDTH/HEIGHT = 640, 520, and that copy had already
-- gone stale (SniperFrame.lua's real default had moved to 720x520) with nothing to catch the
-- drift. Reading the live table field instead of a second copy makes that class of bug
-- impossible.
local function resetWindow()
  local c = cfg()
  if c then c.window = nil end
  local sniperFrame = _G.GoldCapSniperFrame
  if sniperFrame then
    sniperFrame:ClearAllPoints()
    sniperFrame:SetPoint("CENTER")
    local w, h = GC.Sniper.DefaultWindowSize()
    sniperFrame:SetSize(w, h)
  end
end

-- ---------------------------------------------------------------------------
-- Panel construction (lazy -- built on first gear click, same pattern as
-- SniperFrame.lua's purchase-confirm dialog / UI/ImportDialog.lua).
-- ---------------------------------------------------------------------------

local ROW_H = 20
local STEP = 26 -- kit row rhythm (batch 5): 26px between row tops inside a card
local FIELD_W = 64

local function build(sniperFrame)
  local panel = Theme.Panel(sniperFrame)
  -- HIGH strata guarantees this draws above every other child of sniperFrame regardless of
  -- build order -- it's necessarily constructed well AFTER the rest of the window (lazy, on
  -- first gear click), so relying on creation-order z-stacking alone would be fragile.
  panel:SetFrameStrata("HIGH")
  -- Covers everything below the 32px title bar (Theme.TitleBar's own fixed height) and clear
  -- of the rail (Theme.RAIL_W) -- title text/gear/close stay visible and live above this
  -- overlay, and the overlay owns the content area only: the rail stays visible and clickable,
  -- matching the design where Settings is a view beside the rail, not a panel that covers it.
  panel:SetPoint("TOPLEFT", sniperFrame, "TOPLEFT", Theme.RAIL_W, -32)
  panel:SetPoint("BOTTOMRIGHT", sniperFrame, "BOTTOMRIGHT", 0, 0)
  panel:EnableMouse(true) -- blocks clicks from reaching the deal rows/tabs underneath

  -- ESC closes the OVERLAY, never the whole Sniper window: deliberately NOT added to
  -- UISpecialFrames (SniperFrame.lua already registers "GoldCapSniperFrame" there for the
  -- window itself -- adding this panel's own name too would risk Escape closing both on one
  -- press, exactly what the brief rules out). Instead this frame captures the keypress directly
  -- and swallows ONLY Escape so the keybinding-driven "close GoldCapSniperFrame" path never sees
  -- it while the overlay is up. While an editbox inside has focus, ITS OWN OnEscapePressed
  -- (above) fires first and only clears focus -- a second Escape (nothing focused) is what
  -- reaches here.
  --
  -- Fix round 1 (C1): SetPropagateKeyboardInput is evaluated PER KEYSTROKE inside OnKeyDown, not
  -- set once (false) at build time. A static false would eat every key the whole time the panel
  -- is open -- movement keys, action-bar hotkeys, Enter-to-open-chat -- not just Escape, since
  -- EnableKeyboard(true) alone makes this frame receive OnKeyDown for ALL keys, not just the one
  -- being handled. Every non-Escape key must re-arm propagation (true) so it still reaches
  -- whatever would normally receive it.
  panel:EnableKeyboard(true)
  panel:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      GC.SettingsUI.Toggle()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)

  -- Header: title + subtitle + DONE, closed off by a hairline rule at y -40. Everything below
  -- that rule belongs to the two card columns (thresholds/safety on the left, posting/
  -- automation/display on the right).
  local title = Theme.Label(panel, 14)
  title:SetPoint("TOPLEFT", 16, -12)
  title:SetText("Settings")

  local subtitle = Theme.Num(panel, 9)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetWordWrap(false)
  subtitle:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  subtitle:SetText("SAVED INSTANTLY · ESC OR DONE TO CLOSE")
  subtitle:SetPoint("LEFT", title, "RIGHT", 12, 0)

  local done = Theme.Button(panel, "active", "plaque")
  done:SetSize(64, 26)
  done:SetPoint("TOPRIGHT", -16, -7)
  done:SetLabel("DONE")
  done:SetScript("OnClick", function() GC.SettingsUI.Toggle() end)

  do
    local bc = Theme.color.border
    local headerRule = panel:CreateTexture(nil, "ARTWORK")
    headerRule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    headerRule:SetPoint("TOPLEFT", 0, -40)
    headerRule:SetPoint("TOPRIGHT", 0, -40)
    headerRule:SetHeight(1)
  end

  local refreshers = {}

  -- One card per settings group. Rows are laid out from the card's own top so the
  -- two columns can stack independently; height = 24 (title band) + n*STEP + 6.
  local function card(parent, cardTitle, rowCount)
    local c = Theme.Card(parent, Theme.color.panelHi, nil)
    c:SetHeight(24 + rowCount * STEP + 6)
    local t = Theme.Num(c, 9); t:SetJustifyH("LEFT"); t:SetPoint("TOPLEFT", Theme.pad.m, -8)
    t:SetText(cardTitle); t:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
    function c.rowY(i) return -(24 + (i - 1) * STEP) end
    return c
  end

  -- Left column: DEAL THRESHOLDS above SAFETY, both spanning panel-left to panel-CENTER-7.
  local thresholds = card(panel, "DEAL THRESHOLDS", 4)
  thresholds:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -48)
  thresholds:SetPoint("RIGHT", panel, "CENTER", -7, 0)

  local safety = card(panel, "SAFETY", 5)
  safety:SetPoint("TOPLEFT", thresholds, "BOTTOMLEFT", 0, -12)
  safety:SetPoint("RIGHT", panel, "CENTER", -7, 0)

  -- Right column: POSTING, AUTOMATION & ALERTS, DISPLAY stacked, spanning panel-CENTER+7 to
  -- panel-right.
  local posting = card(panel, "POSTING", 1)
  posting:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -48)
  posting:SetPoint("LEFT", panel, "CENTER", 7, 0)

  local automation = card(panel, "AUTOMATION & ALERTS", 2)
  automation:SetPoint("TOPRIGHT", posting, "BOTTOMRIGHT", 0, -12)
  automation:SetPoint("LEFT", panel, "CENTER", 7, 0)

  local display = card(panel, "DISPLAY", 2)
  display:SetPoint("TOPRIGHT", automation, "BOTTOMRIGHT", 0, -12)
  display:SetPoint("LEFT", panel, "CENTER", 7, 0)

  local function fieldRow(cardFrame, i, labelText, key, opts)
    local box = makeEditBox(cardFrame, FIELD_W, ROW_H)
    box:SetPoint("TOPRIGHT", -Theme.pad.m, cardFrame.rowY(i))

    local label = Theme.Label(cardFrame, 12)
    label:SetPoint("TOPLEFT", Theme.pad.m, cardFrame.rowY(i))
    label:SetPoint("RIGHT", box, "LEFT", -Theme.pad.s, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(labelText)

    refreshers[#refreshers + 1] = bindNumberField(box, key, opts)
  end

  local PCT = { min = 1, max = 90, toUI = function(v) return v * 100 end, toStorage = function(v) return v / 100 end }
  local WALLET_PCT = { min = 1, max = 20, toUI = function(v) return v * 100 end, toStorage = function(v) return v / 100 end }
  local GOLD = { min = 1, max = 100000,
    toUI = function(v) return v / 10000 end,
    toStorage = function(v) return v * 10000 end }

  fieldRow(thresholds, 1, "HOT — min discount %", "hotDiscount", PCT)
  fieldRow(thresholds, 2, "HOT — min sold/day", "hotMinSold", { min = 0, max = 1000 })
  fieldRow(thresholds, 3, "GOOD — min discount %", "goodDiscount", PCT)
  fieldRow(thresholds, 4, "GOOD — min sold/day", "goodMinSold", { min = 0, max = 1000 })

  fieldRow(safety, 1, "Max wallet per buy %", "maxCapitalShare", WALLET_PCT)
  fieldRow(safety, 2, "Min profit per buy (gold)", "minimumProfitCopper", GOLD)
  fieldRow(safety, 3, "Dump-trend cap %", "dumpTrendPct", { min = 1, max = 99 })
  -- Spike threshold above 99 is legitimate (observed trends run past +200%), so its cap is
  -- 500 rather than dumpTrendPct's 99 -- matching SniperDecision.normalizeConfig's clamp so
  -- the box can never store a value the engine would then silently re-clamp.
  fieldRow(safety, 4, "Spike-trend threshold %", "spikeTrendPct", { min = 1, max = 500 })
  -- 0 disables the velocity release outright; 6 is normalizeConfig's own ceiling.
  fieldRow(safety, 5, "Wall absorb window (hours)", "wallAbsorbHours", { min = 0, max = 6 })

  -- Ghost cycling button, not a fieldRow: FIELD_W (64px) is sized for a 6-letter numeric
  -- editbox, and "Duration: 48h" would not fit it. Sized separately below.
  do
    local button = Theme.Button(posting, "ghost")
    button:SetSize(118, ROW_H)
    button:SetPoint("TOPRIGHT", -Theme.pad.m, posting.rowY(1))

    local label = Theme.Label(posting, 12)
    label:SetPoint("TOPLEFT", Theme.pad.m, posting.rowY(1))
    label:SetPoint("RIGHT", button, "LEFT", -Theme.pad.s, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText("Auction duration")

    refreshers[#refreshers + 1] = bindDurationButton(button)
  end

  local function checkRow(cardFrame, i, labelText, key)
    local box = makeCheckbox(cardFrame, 18)
    box:SetPoint("TOPLEFT", Theme.pad.m, cardFrame.rowY(i) - 1)

    local label = Theme.Label(cardFrame, 12)
    label:SetPoint("LEFT", box, "RIGHT", Theme.pad.s, 0)
    label:SetWordWrap(false)
    label:SetText(labelText)

    refreshers[#refreshers + 1] = bindCheckbox(box, key)
  end

  checkRow(automation, 1, "Sound on HOT deal", "sound")
  -- Final fix wave (item 5): the plain "Auto-scan by default" label read as if toggling it
  -- would also start/stop a session already in progress -- it only decides whether Auto is
  -- armed the NEXT time the Auction House is opened; it deliberately does not touch a live
  -- Auto session (see Core/Init.lua's OnAuctionHouseShow / SniperFrame.lua's Auto wiring).
  checkRow(automation, 2, "Auto-scan on next AH visit", "auto")

  local scaleLabel = Theme.Label(display, 12)
  scaleLabel:SetPoint("TOPLEFT", Theme.pad.m, display.rowY(1))
  scaleLabel:SetWordWrap(false)
  scaleLabel:SetText("Font scale")

  local scaleReadout = Theme.Num(display, 12)
  scaleReadout:SetPoint("TOPRIGHT", -Theme.pad.m, display.rowY(1))

  local slider, sliderTrack = makeSlider(display, 160, 0.9, 1.3, 0.05)
  sliderTrack:SetPoint("TOPRIGHT", scaleReadout, "TOPLEFT", -Theme.pad.s, -(ROW_H / 2 - 2))

  refreshers[#refreshers + 1] = bindFontSlider(slider, scaleReadout)

  local windowLabel = Theme.Label(display, 12)
  windowLabel:SetPoint("TOPLEFT", Theme.pad.m, display.rowY(2))
  windowLabel:SetWordWrap(false)
  windowLabel:SetText("Window position & size")

  local resetBtn = Theme.Button(display, "ghost", "plaque")
  resetBtn:SetSize(120, 26)
  resetBtn:SetPoint("TOPRIGHT", -Theme.pad.m, display.rowY(2) + 3)
  resetBtn:SetLabel("RESET WINDOW")
  resetBtn:SetScript("OnClick", resetWindow)

  windowLabel:SetPoint("RIGHT", resetBtn, "LEFT", -Theme.pad.s, 0)

  -- Re-syncs every control from GC.db.settings.sniper (and Theme.Scale()) each time the overlay
  -- is shown -- covers external changes made while it was closed, e.g. the toolbar's own Auto
  -- on/off button (SniperFrame.lua's onAutoToggleClick) also writes sniper.auto directly.
  panel:SetScript("OnShow", function()
    for _, refresh in ipairs(refreshers) do refresh() end
  end)

  -- Fix round 1 (C2): WoW frames are SHOWN by default -- without this, build() hands back an
  -- already-visible panel, and GC.SettingsUI.Toggle()'s very first call (`if panel:IsShown()
  -- then Hide() else Show() end`) immediately hides it again on the first gear click of every
  -- session (100% repro: click gear -> nothing visible; click again -> it opens). Unlike
  -- SniperFrame.lua's purchase-confirm dialog (created and immediately opened unconditionally,
  -- never IsShown()-toggled), THIS panel's own open path branches on IsShown(), so it needs to
  -- start explicitly hidden for that first branch to be correct.
  panel:Hide()

  return panel
end

local panel

function GC.SettingsUI.Toggle()
  local sniperFrame = _G.GoldCapSniperFrame
  if not sniperFrame then return end -- gear can't be clicked before the Sniper window exists
  panel = panel or build(sniperFrame)
  if panel:IsShown() then
    panel:Hide()
  else
    panel:Show()
  end
end
