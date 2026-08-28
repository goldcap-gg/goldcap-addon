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
-- Minimal Theme-consistent widgets (editbox / pill toggle / segmented
-- duration / slider). Theme.lua has factories for Panel/Card/Chip/Num/Label/
-- Button/TitleBar because every one of those is reused across SniperFrame +
-- SellFrame + ImportDialog + Tooltip. Nothing else in the addon needs a
-- slider, a toggle, or a raw numeric input -- this settings screen is the
-- only consumer -- so adding first-class Theme factories for them now would
-- be speculative API surface nobody else calls. These stay built inline,
-- reusing Theme's own colors/fonts/pad/slice constants so they still look
-- like Theme widgets.
--
-- Every control on this screen now sits on the kit's own chrome: the editbox
-- background (editBoxBg below) and the pill toggle's track/knob are sliced
-- badge.png (Theme.SlicedTexture, margin 6, valid at their sizes) tinted via
-- SetVertexColor rather than ringed with a separate recolorable border -- a
-- vertex-colored sliced texture has no independent edge layer to brighten,
-- only a whole-fill tint. The one holdout is the font-scale slider's track:
-- at 4px tall it is well under BADGE_SLICE's 6px margin, so nine-slicing it
-- would notch the corners into the fill -- a plain SetColorTexture bar is the
-- correct primitive there, not a workaround. There is no longer a shared
-- "bordered box" helper: the old checkbox/slider-track look it backed is
-- gone, and the editbox's rounded box is a one-off (editBoxBg below).
-- ---------------------------------------------------------------------------

-- Rounded editbox background: sliced badge.png (margin 6, valid at this box's 64x20 size),
-- recolored between Theme.color.bg and a faint gold wash via :SetFocusTint(on) rather than a
-- recolorable border -- see the design comment above for why nothing on this screen uses a
-- separate recolorable edge anymore.
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

-- Pill toggle: one control, two paints. The CheckButton underneath owns click + state
-- (bindCheckbox's contract below -- GetChecked/SetChecked, auto-flip on click, no template so
-- it carries none of UICheckButtonTemplate's default artwork/sizing); :Paint() moves the knob
-- and tints the track. Track and knob are both sliced badge.png (margin 6, valid at their 36x20
-- / 16x16 sizes) recolored via SetVertexColor -- gold wash + bright knob when on, dim track/knob
-- when off -- rather than a checkmark glyph.
local function makeToggle(parent)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(36, 20)

  box.track = Theme.SlicedTexture(box, "BACKGROUND", Theme.MEDIA .. "badge.png", Theme.color.bg, 6)
  box.track:SetAllPoints()

  box.knob = Theme.SlicedTexture(box, "OVERLAY", Theme.MEDIA .. "badge.png", Theme.color.fgDim, 6)
  box.knob:SetSize(16, 16)

  local cb = CreateFrame("CheckButton", nil, box)
  cb:SetAllPoints()
  box.checkButton = cb

  -- M10: hover affordance, engine-driven -- a HIGHLIGHT-layer sliced badge.png (margin 6, valid
  -- at the 36x20 track it's sized to), additive blend, the same gold @ ~0.18 wash T.Button's own
  -- hover texture uses (Theme.lua's file-local HOVER_WASH isn't exported, so this is built from
  -- Theme.color.gold directly rather than duplicated as a second unlinked constant). Nothing is
  -- painted in OnEnter/OnLeave -- addon/AGENTS.md's "never paint hover by hand" rule.
  cb:EnableMouse(true)
  local hover = cb:CreateTexture(nil, "HIGHLIGHT")
  hover:SetTexture(Theme.MEDIA .. "badge.png")
  hover:SetTextureSliceMargins(6, 6, 6, 6)
  hover:SetAllPoints()
  hover:SetBlendMode("ADD")
  local hg = Theme.color.gold
  hover:SetVertexColor(hg[1], hg[2], hg[3], 0.18)

  function box:Paint()
    local on = cb:GetChecked()
    local g, d, b = Theme.color.gold, Theme.color.fgDim, Theme.color.bg
    self.knob:ClearAllPoints()
    if on then
      self.track:SetVertexColor(g[1], g[2], g[3], 0.30)
      self.knob:SetVertexColor(Theme.color.goldHi[1], Theme.color.goldHi[2], Theme.color.goldHi[3], 1)
      self.knob:SetPoint("RIGHT", -2, 0)
    else
      self.track:SetVertexColor(b[1], b[2], b[3], b[4] or 1)
      self.knob:SetVertexColor(d[1], d[2], d[3], 1)
      self.knob:SetPoint("LEFT", 2, 0)
    end
  end

  return box
end

-- Slider: a bare CreateFrame("Slider") -- deliberately NOT OptionsSliderTemplate, which also
-- creates its own title/low/high FontString trio and a default Blizzard thumb texture that
-- would have to be hidden/reworked piece by piece to match Theme. The bare Slider widget type
-- still gives real drag/click-to-set/keyboard-step mechanics for free via
-- SetMinMaxValues/SetValueStep/SetObeyStepOnDrag -- only the visuals (track + thumb) are ours,
-- so this is "Blizzard template for functionality, restyled" rather than a hand-rolled drag
-- implementation. The track is a plain 4px Theme.color.bg fill, not sliced: a 4px bar is
-- shorter than BADGE_SLICE's 6px margin, so nine-slicing it would notch the corners into the
-- fill -- flat is the correct primitive at this size, not a fallback. The thumb, at 12x16, is
-- comfortably above the margin and gets the kit's sliced badge.png like every other control.
local function makeSlider(parent, width, min, max, step)
  local track = parent:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(Theme.color.bg[1], Theme.color.bg[2], Theme.color.bg[3], Theme.color.bg[4] or 1)
  track:SetSize(width, 4)

  local slider = CreateFrame("Slider", nil, parent)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(width, 16)
  slider:SetPoint("LEFT", track, "LEFT", 0, 0) -- vertically centers the 16px slider on the 4px track
  slider:SetMinMaxValues(min, max)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)

  local thumb = Theme.SlicedTexture(slider, "OVERLAY", Theme.MEDIA .. "badge.png", Theme.color.gold, 6)
  thumb:SetSize(12, 16)
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

-- Binds a pill toggle to a boolean GC.db.settings.sniper[key]. display() and the OnClick
-- handler both re-run box:Paint() so the knob/track repaint whether the value changed from
-- inside this screen (a click) or from outside it (OnShow's refresh loop below).
local function bindCheckbox(box, key)
  local cb = box.checkButton

  local function display()
    local c = cfg()
    cb:SetChecked(c and c[key] and true or false)
    box:Paint()
  end

  cb:SetScript("OnClick", function(self)
    local c = cfg()
    if c then c[key] = self:GetChecked() and true or false end
    box:Paint()
  end)

  display()
  return display
end

-- GC.db.settings.sniper.postDuration stores one of the three durations
-- C_AuctionHouse.PostCommodity/PostItem accept -- 1 = 12h, 2 = 24h, 3 = 48h, see Core/Init.lua's
-- own comment on that field. DURATION_INDEX maps the segment's own label hours (12/24/48) to
-- that stored index; a numeric field (like the ones bindNumberField above builds) would happily
-- let a player type a 4th value the API would reject, and a three-state segment group can't
-- express a duration that does not exist.
local DURATION_INDEX = { [12] = 1, [24] = 2, [48] = 3 }

-- Same "invalid/missing falls back to the default" contract as UI/SellFrame.lua's own
-- postDuration() reader -- these controls must never show, let alone write, a value that
-- reader would refuse to post at.
local function storedDurationIndex()
  local c = cfg()
  local value = c and c.postDuration
  if value == 1 or value == 2 or value == 3 then return value end
  local d = GC.DEFAULTS and GC.DEFAULTS.settings and GC.DEFAULTS.settings.sniper
  local default = d and d.postDuration
  return (default == 1 or default == 2 or default == 3) and default or 2
end

-- Binds the three 12H/24H/48H segment buttons: `buttons`/`hoursList` are parallel arrays
-- (buttons[i] labeled hoursList[i] .. "H"). display() paints the current duration's button
-- "active" and every other "ghost"; each button writes DURATION_INDEX[its own hours] on click,
-- then repaints -- same db key, same 1/2/3 value type the old cycling button wrote.
local function bindDurationSegments(buttons, hoursList)
  local function display()
    local current = storedDurationIndex()
    for i, button in ipairs(buttons) do
      button:SetVariant(DURATION_INDEX[hoursList[i]] == current and "active" or "ghost")
    end
  end

  for i, button in ipairs(buttons) do
    local hours = hoursList[i]
    button:SetScript("OnClick", function()
      local c = cfg()
      if not c then return end
      c.postDuration = DURATION_INDEX[hours]
      display()
    end)
  end

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
-- file used to carry its own DEFAULT_WINDOW_WIDTH/HEIGHT, and that copy had already gone stale
-- against SniperFrame.lua's real WIN.FRAME_WIDTH/HEIGHT with nothing to catch the drift. Reading
-- the live values through the function instead of a second copy makes that class of bug
-- impossible -- whatever WIN.FRAME_WIDTH/HEIGHT are today, this always matches.
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
  -- Layering. This shipped as SetFrameStrata("HIGH"), which drew above the window's own
  -- content for exactly as long as the WINDOW was not also HIGH. Once createFrame started
  -- declaring HIGH + toplevel (SniperFrame.lua, for a window that used to sit under the
  -- auction house), the overlay landed in its parent's own strata -- and SetFrameStrata
  -- reassigns the level within the strata it moves to, so it came out UNDER the scroll rows
  -- it exists to cover: the Sold list read straight through the settings cards.
  --
  -- The strata is not this panel's to pick anyway. Docking adopts the auction house's for the
  -- whole window (GC.Sniper.SetDocked), and an overlay pinned one strata above would paint
  -- over the host's dropdowns exactly the way the window itself must not. So it stays in
  -- whatever strata its parent is in and wins on LEVEL, which is what decides inside one
  -- strata: +50 clears the ScrollFrame, its pooled rows and the resize handle (scroll level
  -- + 10), while the check drawer -- a whole strata above the window -- still draws on top.
  --
  -- Re-derived rather than chosen once: the engine reassigns a child's level whenever the
  -- parent changes strata, which docking does. Called again from panel:OnShow below and from
  -- SetDocked (both directions), the same way the check drawer's raiseStrata is.
  local function raiseLevel()
    local base = (sniperFrame.GetFrameLevel and sniperFrame:GetFrameLevel()) or 0
    panel:SetFrameLevel(base + 50)
  end
  panel.raiseLevel = raiseLevel
  raiseLevel()
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
  title:SetText(GC.L["Settings"])

  local subtitle = Theme.Num(panel, 9)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetWordWrap(false)
  subtitle:SetTextColor(Theme.color.fgDim[1], Theme.color.fgDim[2], Theme.color.fgDim[3])
  subtitle:SetText(GC.L["SAVED INSTANTLY · ESC OR DONE TO CLOSE"])
  subtitle:SetPoint("LEFT", title, "RIGHT", 12, 0)

  local done = Theme.Button(panel, "active", "plaque")
  done:SetSize(64, 26)
  done:SetPoint("TOPRIGHT", -16, -7)
  done:SetLabel(GC.L["DONE"])
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
  local thresholds = card(panel, GC.L["DEAL THRESHOLDS"], 4)
  thresholds:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -48)
  thresholds:SetPoint("RIGHT", panel, "CENTER", -7, 0)

  local safety = card(panel, GC.L["SAFETY"], 5)
  safety:SetPoint("TOPLEFT", thresholds, "BOTTOMLEFT", 0, -12)
  safety:SetPoint("RIGHT", panel, "CENTER", -7, 0)

  -- Right column: POSTING, AUTOMATION & ALERTS, DISPLAY stacked, spanning panel-CENTER+7 to
  -- panel-right.
  local posting = card(panel, GC.L["POSTING"], 1)
  posting:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -48)
  posting:SetPoint("LEFT", panel, "CENTER", 7, 0)

  local automation = card(panel, GC.L["AUTOMATION & ALERTS"], 2)
  automation:SetPoint("TOPRIGHT", posting, "BOTTOMRIGHT", 0, -12)
  automation:SetPoint("LEFT", panel, "CENTER", 7, 0)

  local display = card(panel, GC.L["DISPLAY"], 3)
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

  fieldRow(thresholds, 1, GC.L["HOT — min discount %"], "hotDiscount", PCT)
  fieldRow(thresholds, 2, GC.L["HOT — min sold/day"], "hotMinSold", { min = 0, max = 1000 })
  fieldRow(thresholds, 3, GC.L["GOOD — min discount %"], "goodDiscount", PCT)
  fieldRow(thresholds, 4, GC.L["GOOD — min sold/day"], "goodMinSold", { min = 0, max = 1000 })

  fieldRow(safety, 1, GC.L["Max wallet per buy %"], "maxCapitalShare", WALLET_PCT)
  fieldRow(safety, 2, GC.L["Min profit per buy (gold)"], "minimumProfitCopper", GOLD)
  fieldRow(safety, 3, GC.L["Dump-trend cap %"], "dumpTrendPct", { min = 1, max = 99 })
  -- Spike threshold above 99 is legitimate (observed trends run past +200%), so its cap is
  -- 500 rather than dumpTrendPct's 99 -- matching SniperDecision.normalizeConfig's clamp so
  -- the box can never store a value the engine would then silently re-clamp.
  fieldRow(safety, 4, GC.L["Spike-trend threshold %"], "spikeTrendPct", { min = 1, max = 500 })
  -- 0 disables the velocity release outright; 6 is normalizeConfig's own ceiling.
  fieldRow(safety, 5, GC.L["Wall absorb window (hours)"], "wallAbsorbHours", { min = 0, max = 6 })

  -- Segmented duration, not a fieldRow: three 40x20 kit buttons chained from the card's right
  -- edge, rightmost (48H) placed first so each earlier one anchors off the one already placed.
  do
    local h48 = Theme.Button(posting, "ghost", "badge")
    h48:SetSize(40, ROW_H)
    h48:SetPoint("TOPRIGHT", -Theme.pad.m, posting.rowY(1))
    h48:SetLabel("48H")

    local h24 = Theme.Button(posting, "ghost", "badge")
    h24:SetSize(40, ROW_H)
    h24:SetPoint("RIGHT", h48, "LEFT", -2, 0)
    h24:SetLabel("24H")

    local h12 = Theme.Button(posting, "ghost", "badge")
    h12:SetSize(40, ROW_H)
    h12:SetPoint("RIGHT", h24, "LEFT", -2, 0)
    h12:SetLabel("12H")

    local label = Theme.Label(posting, 12)
    label:SetPoint("TOPLEFT", Theme.pad.m, posting.rowY(1))
    label:SetPoint("RIGHT", h12, "LEFT", -Theme.pad.s, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    -- M11: "Auction duration" truncated to "Auction du..." at the 640 minimum / 1.3x scale --
    -- relabeled to the shorter "Duration" (no spec pins on the string).
    label:SetText(GC.L["Duration"])

    refreshers[#refreshers + 1] = bindDurationSegments({ h12, h24, h48 }, { 12, 24, 48 })
  end

  local function toggleRow(cardFrame, i, labelText, key)
    local box = makeToggle(cardFrame)
    box:SetPoint("TOPRIGHT", -Theme.pad.m, cardFrame.rowY(i))

    local label = Theme.Label(cardFrame, 12)
    label:SetPoint("TOPLEFT", Theme.pad.m, cardFrame.rowY(i))
    label:SetPoint("RIGHT", box, "LEFT", -Theme.pad.s, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(labelText)

    refreshers[#refreshers + 1] = bindCheckbox(box, key)
  end

  toggleRow(automation, 1, GC.L["Sound on HOT deal"], "sound")
  -- Final fix wave (item 5): the plain "Auto-scan by default" label read as if toggling it
  -- would also start/stop a session already in progress -- it only decides whether Auto is
  -- armed the NEXT time the Auction House is opened; it deliberately does not touch a live
  -- Auto session (see Core/Init.lua's OnAuctionHouseShow / SniperFrame.lua's Auto wiring).
  toggleRow(automation, 2, GC.L["Auto-scan on next AH visit"], "auto")

  -- I1: unlike every other row, this label wasn't RIGHT-bound to anything, so at the 640
  -- minimum (card 259px) it ran straight into the readout -- 32px of overlap at 1.0x scale, 63px
  -- at 1.3x. Budget at the 640 minimum: 12 (pad.m) + label + 8 (pad.s) + 48 (readout) +
  -- 8 (pad.s) + 110 (slider track) + 12 (pad.m) = 259 -> label gets 61px, which ellipsizes at
  -- 1.3x scale and fits at 1.0x.
  local scaleLabel = Theme.Label(display, 12)
  scaleLabel:SetPoint("TOPLEFT", Theme.pad.m, display.rowY(1))
  scaleLabel:SetWordWrap(false)
  scaleLabel:SetText(GC.L["Font scale"])

  local slider, sliderTrack = makeSlider(display, 110, 0.9, 1.3, 0.05)
  sliderTrack:SetPoint("TOPRIGHT", -Theme.pad.m, display.rowY(1) - 8)

  local scaleReadout = Theme.Num(display, 12)
  scaleReadout:SetWidth(48)
  scaleReadout:SetPoint("RIGHT", sliderTrack, "LEFT", -Theme.pad.s, 0)

  scaleLabel:SetPoint("RIGHT", scaleReadout, "LEFT", -Theme.pad.s, 0)

  refreshers[#refreshers + 1] = bindFontSlider(slider, scaleReadout)

  local windowLabel = Theme.Label(display, 12)
  windowLabel:SetPoint("TOPLEFT", Theme.pad.m, display.rowY(2))
  windowLabel:SetWordWrap(false)
  windowLabel:SetText(GC.L["Window position & size"])

  local resetBtn = Theme.Button(display, "ghost", "plaque")
  resetBtn:SetSize(120, 26)
  resetBtn:SetPoint("TOPRIGHT", -Theme.pad.m, display.rowY(2) + 3)
  resetBtn:SetLabel(GC.L["RESET WINDOW"])
  resetBtn:SetScript("OnClick", resetWindow)

  windowLabel:SetPoint("RIGHT", resetBtn, "LEFT", -Theme.pad.s, 0)

  -- Language. A twelve-way choice is not a segment group, and this addon embeds no dropdown
  -- library -- MenuUtil is the engine's own menu framework (Patch 11.0, the replacement for
  -- the deprecated UIDropDownMenu), so the button just opens a radio context menu.
  --
  -- The picker exists because Ukrainian cannot be detected: there is no Ukrainian WoW client
  -- and GetLocale() never returns ukUA. It serves anyone on an English client who would
  -- rather read their own language too, but that is the side effect, not the reason.
  local langLabel = Theme.Label(display, 12)
  langLabel:SetPoint("TOPLEFT", Theme.pad.m, display.rowY(3))
  langLabel:SetWordWrap(false)
  langLabel:SetText(GC.L["Language"])

  local langBtn = Theme.Button(display, "ghost", "plaque")
  langBtn:SetSize(120, 26)
  langBtn:SetPoint("TOPRIGHT", -Theme.pad.m, display.rowY(3) + 3)

  langLabel:SetPoint("RIGHT", langBtn, "LEFT", -Theme.pad.s, 0)

  local function localeSetting()
    return (GC.db and GC.db.settings and GC.db.settings.locale) or "auto"
  end

  local function displayLanguage()
    langBtn:SetLabel(GC.LocaleChoiceLabel(localeSetting()))
    -- This label is the ONE piece of text in the addon rewritten in the newly picked language
    -- on the spot -- every other widget still says what it said in the old one until the
    -- /reload below. So this is the one widget whose FACE has to move with it, and the whole
    -- kit deliberately does not (Theme.RefontWidget's own comment covers why moving the rest
    -- is worse). Without it the control the player had just used came back as "♦♦♦": Hangul
    -- written into a FontString still pinned to the bundled latin mono.
    if Theme.RefontWidget then Theme.RefontWidget(langBtn.text) end
  end

  langBtn:SetScript("OnClick", function(self)
    local menu = _G.MenuUtil
    if not menu or not menu.CreateRadioContextMenu then return end
    local entries = {}
    for _, choice in ipairs(GC.LOCALE_CHOICES) do
      entries[#entries + 1] = { choice.label, choice.code }
    end
    menu.CreateRadioContextMenu(self,
      function(code) return localeSetting() == code end,
      function(code)
        if not (GC.db and GC.db.settings) then return end
        GC.db.settings.locale = code
        GC.ApplyLocale()
        displayLanguage()
        -- Labels are written when a widget is built, so already-built frames keep the old
        -- language until they are rebuilt. Saying so beats pretending the switch is total.
        if GC.Print then
          GC.Print(GC.L["Language changed. Type /reload to apply it everywhere."])
          -- A language the installed fonts cannot draw renders as empty boxes, and nothing
          -- on our side can change that -- an English client has no Hangul anywhere in it.
          -- Say so here rather than let the player read a wall of squares as a broken addon.
          if GC.Theme and GC.Theme.LocaleIsDrawable and not GC.Theme.LocaleIsDrawable(code) then
            GC.Print(GC.L["your game client has no font for this language — the text will show as empty boxes"])
          end
        end
      end,
      unpack(entries))
  end)

  refreshers[#refreshers + 1] = displayLanguage

  -- Re-syncs every control from GC.db.settings.sniper (and Theme.Scale()) each time the overlay
  -- is shown -- covers external changes made while it was closed, e.g. the toolbar's own Auto
  -- on/off button (SniperFrame.lua's onAutoToggleClick) also writes sniper.auto directly.
  panel:SetScript("OnShow", function()
    -- The window's own strata (and with it every child level the engine reassigned) can have
    -- changed since this panel was built -- docking adopts the auction house's.
    raiseLevel()
    for _, refresh in ipairs(refreshers) do refresh() end
  end)

  -- T6: the rail gear lights up while this overlay is open, so its own state (lit while a view
  -- is active) reads as true parity with T.RailButton:SetActive -- that also tints the icon
  -- (goldHi active / fgDim inactive), not just the plate behind it, so the gear icon is tinted
  -- here too (M8) instead of staying a still-fgDim icon on a gold plate. HookScript, not
  -- SetScript, for OnShow -- the refresh loop above already owns that event and this must not
  -- clobber it. OnShow also Enables the three rail tab buttons (NOT SetActive(false), which
  -- would drop the active tab's tint): a rail click has to dismiss this overlay AND still land
  -- on a clickable button (see SniperFrame.lua's rail OnClick closures), and setTabActive
  -- Disable()s whichever tab is current, so they'd otherwise be unclickable the whole time
  -- Settings is open. OnHide undoes that via GC.Sniper.RefreshRailActive, which re-Disable()s
  -- the active tab. However this overlay closes -- Escape's OnKeyDown, DONE's OnClick, the gear,
  -- a rail click routed through GC.SettingsUI.Hide() below, or the Sniper window itself hiding
  -- (the engine fires OnHide on children too) -- it funnels through this same
  -- panel:Hide(), so one OnShow/OnHide pair here covers all of them without duplicating the
  -- wiring at each call site. Guarded: sniperFrame.rail doesn't exist for a bare Settings-panel
  -- construction (there is none in production, but this file's own specs build
  -- SettingsFrame.lua standalone).
  local rail = sniperFrame.rail
  local gear = rail and rail.gear
  if gear and gear.SetVariant then
    panel:HookScript("OnShow", function()
      gear:SetVariant("active")
      if gear.icon and gear.icon.SetVertexColor then
        local c = Theme.color.goldHi
        gear.icon:SetVertexColor(c[1], c[2], c[3], 1)
      end
      local buttons = rail and rail.buttons
      if buttons then
        for _, b in pairs(buttons) do
          if b.Enable then b:Enable() end
        end
      end
    end)
    panel:SetScript("OnHide", function()
      gear:SetVariant("ghost")
      if gear.icon and gear.icon.SetVertexColor then
        local c = Theme.color.fgDim
        gear.icon:SetVertexColor(c[1], c[2], c[3], 1)
      end
      if GC.Sniper and GC.Sniper.RefreshRailActive then GC.Sniper.RefreshRailActive() end
    end)
  end

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

-- Called from SniperFrame.lua's rail OnClick closures so a Deals/Sell/Sold click dismisses
-- Settings first. No-op if the panel was never built (gear never clicked this session) or is
-- already hidden -- unlike Toggle, this never opens it.
function GC.SettingsUI.Hide()
  if panel and panel:IsShown() then panel:Hide() end
end

-- Called from SniperFrame.lua's GC.Sniper.SetDocked, both directions, beside the check
-- drawer's own raiseStrata: docking changes the window's strata, and the engine reassigns
-- every child's level when it does -- so an overlay ALREADY open when the auction house
-- opens would drop back under the rows it covers. No-op before the first gear click.
function GC.SettingsUI.Raise()
  if panel and panel.raiseLevel then panel.raiseLevel() end
end
