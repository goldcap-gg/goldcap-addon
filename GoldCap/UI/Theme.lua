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
T.ROW_H = 32

T.FONT_MONO = "Interface\\AddOns\\GoldCap\\Media\\JetBrainsMono-Regular.ttf"
T.FONT_MONO_BOLD = "Interface\\AddOns\\GoldCap\\Media\\JetBrainsMono-Bold.ttf"

-- The bundled monospace face covers Latin, Greek and all of Cyrillic (verified from its cmap,
-- so Russian and Ukrainian need nothing here) and no CJK at all. On Korean and both Chinese
-- locales anything drawn with it would be empty boxes, so those locales draw in one of
-- Blizzard's own faces for the script instead -- see CJK_FACES below for which, and for why
-- "the client's own font" is NOT the same thing.
--
-- This covers T.Num too, not just buttons and chips. T.Num draws the column headers and band
-- labels as well as the figures, so leaving it on the bundled face would render those headers
-- as empty boxes on exactly the locales this batch exists for. The trade is real and taken
-- deliberately: on CJK the digits stop being monospaced, so number columns line up by their
-- RIGHT anchor rather than by character width. Boxes would be worse.
--
-- The brand logo keeps the bundled face: it is always the Latin "G".
-- T.Label already does the equivalent by inheriting GameFontHighlightSmall; this is the same
-- idea for the places that ask for the mono face by name.
local CJK_LOCALES = { koKR = true, zhCN = true, zhTW = true }

-- Locales the CLIENT's own face can only draw when the client itself runs them. A client
-- font always covers Latin, plus exactly the script of the locale it shipped for -- so an
-- English client's FRIZQT__.TTF draws German and Spanish, and nothing else here. Which is
-- not the same as the client having no face for those scripts at all: see CJK_FACES.
local NON_LATIN_LOCALES = { ruRU = true, ukUA = true, koKR = true, zhCN = true, zhTW = true }

T.FONT_UI = T.FONT_MONO
T.FONT_UI_BOLD = T.FONT_MONO_BOLD

-- The face T.Label draws with, or nil to keep the one it inherits from
-- GameFontHighlightSmall. Nil is the normal answer and the one that preserves the kit's
-- look: prose and item names in the game's own face, figures and headers in the mono.
--
-- It stops being the right answer the moment the addon speaks a language the client does
-- not. That is not an edge case -- it is what the language picker is FOR (there is no
-- Ukrainian client at all), and it shipped broken: on an English client, choosing Russian
-- turned every Label in the addon into empty boxes while the mono-faced numbers beside
-- them read fine, because FRIZQT__.TTF has no Cyrillic. Measured, not assumed.
T.FONT_LABEL = nil

local function clientLocale()
  local ok, code = pcall(function() return GetLocale and GetLocale() end)
  return ok and type(code) == "string" and code ~= "" and code or nil
end

-- Blizzard's locale faces live in the CLIENT's own data, not in the locale install -- probed
-- in-game on an enUS-only install 2026-08-28: Fonts\ARKai_T.ttf, Fonts\ARHei.ttf,
-- Fonts\2002.TTF, Fonts\2002B.TTF and Fonts\bKAI00M.ttf all load; bLEI00D, bHEI01B,
-- bHEI00M and ARKai_C do not. Reading "the client's own face" instead (GameFontNormal) hands
-- back Fonts\FRIZQT__.TTF there, which has no CJK at all -- so the whole interface drew empty
-- boxes while the language picker beside it drew 한국어 and 简体中文 perfectly, and the
-- "your game client has no font for this language" warning printed in flawless Korean.
-- Blizzard's own font OBJECTS reach these faces; our SetFont(path) pinned the latin one.
--
-- Ordered best-first per locale and PROBED, never assumed: an install missing one has to fall
-- through to the next face of the SAME script before borrowing another's, and an install
-- missing all of them keeps the old answer rather than blanking the kit. The regular/bold
-- split mirrors Blizzard's own roman->CJK mapping, so bold stays a real weight where the
-- script has one instead of collapsing into the regular face.
local CJK_FACES = {
  koKR = { regular = { "2002.TTF" }, bold = { "2002B.TTF", "2002.TTF" } },
  zhCN = { regular = { "ARKai_T.ttf", "ARHei.ttf" }, bold = { "ARHei.ttf", "ARKai_T.ttf" } },
  zhTW = {
    regular = { "bLEI00D.ttf", "bKAI00M.ttf", "ARKai_T.ttf" },
    bold = { "bHEI01B.ttf", "bKAI00M.ttf", "ARHei.ttf" },
  },
}

-- One scratch FontString, built once and never shown, purely to ask the engine whether a face
-- loads: SetFont returns false for a file this client does not have. pcall throughout because
-- this runs at ADDON_LOADED and must degrade to "no face found" rather than error -- and
-- because only an explicit `true` counts, a client whose SetFont returns nothing leaves the
-- previous behaviour exactly as it was instead of losing a face that already worked.
local probeFontString, faceCache = nil, {}
local function faceLoads(path)
  if not probeFontString then
    local ok, fs = pcall(function()
      return _G.UIParent and _G.UIParent:CreateFontString(nil, "OVERLAY")
    end)
    if not ok or not fs then return false end
    probeFontString = fs
  end
  local cached = faceCache[path]
  if cached ~= nil then return cached end
  local ok, valid = pcall(probeFontString.SetFont, probeFontString, path, 12, "")
  local loads = (ok and valid == true) and true or false
  faceCache[path] = loads
  return loads
end

--- First face in `list` this client actually has, or nil.
local function firstFace(list)
  if not list then return nil end
  for _, file in ipairs(list) do
    local path = "Fonts\\" .. file
    if faceLoads(path) then return path end
  end
  return nil
end

--- False only when NOTHING in the client can draw `code`. Cyrillic is always drawable (the
-- bundled face covers it); CJK is drawable exactly when one of Blizzard's own faces for that
-- script is present. Derived from the same probe RefreshFonts uses, so the picker can no
-- longer warn that a client cannot draw a language while the menu item under the cursor is
-- drawing it.
function T.LocaleIsDrawable(code)
  if not NON_LATIN_LOCALES[code] then return true end
  if code == clientLocale() then return true end
  if not CJK_LOCALES[code] then return true end
  local faces = CJK_FACES[code]
  return firstFace(faces and faces.regular) ~= nil
end

function T.RefreshFonts(code)
  -- Latin needs nothing; a script the client shipped for needs nothing. Cyrillic comes from
  -- the bundled face, which covers it. CJK the bundled face cannot help with at all, so Label
  -- follows whatever FONT_UI settles on below -- one script, one face, rather than a second
  -- answer that would only be a second guess.
  --
  -- Spelled as an if, not `cond and nil or T.FONT_MONO`: that idiom cannot yield nil in Lua,
  -- so it silently forced the mono face on every locale.
  if not NON_LATIN_LOCALES[code] or code == clientLocale() then
    T.FONT_LABEL = nil
  else
    T.FONT_LABEL = T.FONT_MONO
  end

  if not CJK_LOCALES[code] then
    T.FONT_UI, T.FONT_UI_BOLD = T.FONT_MONO, T.FONT_MONO_BOLD
    return T.FONT_UI
  end
  -- The face for the SCRIPT, taken from the client's own data (see CJK_FACES). This is the
  -- answer whenever the client has it, including on a client already running that language --
  -- there it resolves to the same file GameFontNormal would have named.
  local faces = CJK_FACES[code]
  local regular = firstFace(faces and faces.regular)
  if regular then
    T.FONT_UI = regular
    T.FONT_UI_BOLD = firstFace(faces.bold) or regular
    T.FONT_LABEL = T.FONT_UI
    return T.FONT_UI
  end
  -- Nothing for that script in this install. GameFontNormal is one of the client's own Font
  -- objects, so its path is whatever face the running client uses for its locale -- right on a
  -- CJK client, and the least-wrong latin face anywhere else. pcall because a Font object is
  -- not guaranteed to be there at every point in load order, and an unreadable one must
  -- degrade to a face that at least draws Latin rather than blanking the interface.
  local ok, path = pcall(function()
    return _G.GameFontNormal and _G.GameFontNormal:GetFont()
  end)
  if ok and type(path) == "string" and path ~= "" then
    T.FONT_UI, T.FONT_UI_BOLD = path, path
  else
    T.FONT_UI, T.FONT_UI_BOLD = T.FONT_MONO, T.FONT_MONO_BOLD
  end
  -- CJK: the bundled face has no glyphs at all, so Label draws in whatever FONT_UI just
  -- settled on. Set explicitly rather than left nil, because the inherited
  -- GameFontHighlightSmall is not necessarily the same face this just chose.
  T.FONT_LABEL = T.FONT_UI
  return T.FONT_UI
end

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

local function applyFont(fs, info)
  if not info.path then return end
  -- Flags come from the widget, not from "": a Label inherits its outline from
  -- GameFontHighlightSmall, and passing "" here used to strip it off every label the first
  -- time the font-scale slider moved.
  pcall(fs.SetFont, fs, info.path, info.size * scale, info.flags or "")
end

--- Moves ONE already-built widget onto the face in force now, and pins it there (a later
-- rescale keeps it). Deliberately not a wholesale pass over every widget: the text on screen
-- is still written in the language it was built in, and moving all of it onto the new script's
-- face is actively worse -- switching from Ukrainian to Korean drew the still-Ukrainian
-- interface in Fonts\2002.TTF, which has Cyrillic but no і, є or ї, so half the words came
-- back with boxes punched through the middle of them. A face has to match the text it draws,
-- and the text only changes on the /reload the picker asks for.
--
-- The exception is a widget whose text is rewritten in the new language right there and then.
-- That is the Settings language button, and it is the one that matters most: picking Korean
-- wrote Hangul into a FontString still pinned to the bundled latin mono, so the control that
-- had just been used read as three empty diamonds.
function T.RefontWidget(fs)
  local info = fs and widgetFonts[fs]
  if not info then return end
  local role = info.role
  local path
  if role == "mono" then path = T.FONT_MONO_BOLD       -- the brand "G": latin, always
  elseif role == "uiBold" then path = T.FONT_UI_BOLD
  elseif role == "label" then path = T.FONT_LABEL or info.inherited
  else path = T.FONT_UI end
  if not path then return end
  info.path = path
  applyFont(fs, info)
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
    applyFont(fs, info)
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
  widgetFonts[b.text] = { role = "uiBold", path = T.FONT_UI_BOLD, size = 8 }

  b.highlightTexture = b:CreateTexture(nil, "HIGHLIGHT")
  b.highlightTexture:SetAllPoints()
  b.highlightTexture:SetBlendMode("ADD")
  b.highlightTexture:SetColorTexture(HOVER_WASH[1], HOVER_WASH[2], HOVER_WASH[3], HOVER_WASH[4])

  -- The engine keeps drawing HIGHLIGHT over a disabled button (that is how a dimmed control
  -- can still raise a tooltip), so the wash is muted here instead of guarded in a script.
  b:SetScript("OnDisable", function() b.highlightTexture:SetAlpha(0) end)
  b:SetScript("OnEnable", function() b.highlightTexture:SetAlpha(1) end)

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
  widgetFonts[b.badge.text] = { role = "uiBold", path = T.FONT_UI_BOLD, size = 9 }
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

  -- `small` (plaque.png/PLAQUE_SLICE): the 32px logo is the same size class as the
  -- badge -- card.png's 24px margins would overlap and notch its corners too.
  local logo = T.Card(frame, T.color.gold, { T.color.goldHi[1], T.color.goldHi[2], T.color.goldHi[3], 0.5 }, true)
  logo:SetSize(32, 32)
  logo:SetPoint("TOP", 0, -16)
  logo.text = logo:CreateFontString(nil, "OVERLAY")
  logo.text:SetFont(T.FONT_MONO_BOLD, 16 * T.Scale(), "")
  logo.text:SetPoint("CENTER")
  logo.text:SetText("G")
  logo.text:SetTextColor(BADGE_TEXT[1], BADGE_TEXT[2], BADGE_TEXT[3])
  widgetFonts[logo.text] = { role = "mono", path = T.FONT_MONO_BOLD, size = 16 }

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

  widgetFonts[f.text] = { role = "uiBold", path = T.FONT_UI_BOLD, size = 9 }

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
  widgetFonts[f.text] = { role = "uiBold", path = T.FONT_UI_BOLD, size = 10 }

  function f:SetLabel(text, colorTable)
    f.text:SetText(text)
    local c = colorTable or T.color.fg
    f.dot:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    f.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  end

  return f
end

-- Num: mono font, size*Scale(), RIGHT-justified. Re-fonts on rescale.
function T.Num(parent, size, bold)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local font = bold and T.FONT_UI_BOLD or T.FONT_UI
  fs:SetFont(font, size * T.Scale(), "")
  fs:SetJustifyH("RIGHT")
  widgetFonts[fs] = { role = bold and "uiBold" or "ui", path = font, size = size }
  return fs
end

-- Label: native font (keeps client glyph fallback for localized/item-name text), LEFT-justified.
-- Final fix wave (item 3): applies size*T.Scale() at creation (was a bare `size`, so a Label
-- never actually respected the current scale on first render) AND registers in widgetFonts
-- (same data-valued-weak-table idiom T.Num already uses -- see that table's own comment for
-- why the value must never close over `fs`), so SetScale's re-font pass now reaches every
-- Label too, not just Num/Chip fontstrings.
--
-- Deliberately NOT extended to ROW_H (Theme.ROW_H, 32px) or the dialog's own pixel budgets --
-- those stay fixed regardless of T.Scale(). At 1.3x a Label's text can get visually tight
-- against an unscaled row/dialog height; that's an accepted tradeoff here (the in-game
-- checklist covers verifying it reads fine at the scale extremes), not a bug to fix by also
-- scaling layout geometry.
function T.Label(parent, size)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  local inherited, _, flags = fs:GetFont()
  -- T.FONT_LABEL overrides the inherited face only where the client cannot draw the active
  -- language -- see its declaration. Normally nil, and the inherited face stands.
  local fontPath = T.FONT_LABEL or inherited
  if fontPath then
    fs:SetFont(fontPath, size * T.Scale(), flags)
    -- Both faces are kept: `path` is what this label draws in now, `inherited` is what it
    -- goes back to if T.RefontWidget ever moves it and the override has since been dropped.
    widgetFonts[fs] = { role = "label", path = fontPath, inherited = inherited, size = size,
      flags = flags }
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

-- rounded T.Button: file + margin per size class, keyed the same way T.Card's `small`
-- picks plaque over card -- badge is one size class down again (BADGE_SLICE, no ring: see
-- BADGE_SLICE's own comment, the same 16px art is too small for a second nine-slice ring
-- on top of its fill without the two notching each other).
local ROUNDED_BUTTON = {
  plaque = { bg = T.MEDIA .. "plaque.png", ring = T.MEDIA .. "plaque_ring.png", margin = PLAQUE_SLICE },
  badge  = { bg = T.MEDIA .. "badge.png", ring = nil, margin = BADGE_SLICE },
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
    widgetFonts[b.text] = { role = "ui", path = T.FONT_UI, size = 10 }
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
    -- Same rounded-vs-square branch as SetVariant above: SetColorTexture on a textured
    -- rounded bg would erase the texture file the re-enable path is meant to restore.
    if b.roundedMargin then
      b.bg:SetVertexColor(base[1], base[2], base[3], base[4] or 1)
    else
      b.bg:SetColorTexture(base[1], base[2], base[3], base[4] or 1)
    end
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
