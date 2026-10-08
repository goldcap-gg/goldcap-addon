-- GoldCap's faces and which one draws what, per language. Moved out of UI/Theme.lua with the move
-- to Fira (wow-auction: docs/superpowers/specs/2026-10-09-addon-ui-kit-and-sell-design.md,
-- "Fonts"); the per-locale rules and the CJK probe below are Theme's own, unchanged except where
-- marked. Writes onto GC.Theme, so every caller keeps reading Theme.FONT_UI, Theme.Num and the rest.
local _, GC = ...
GC.Theme = GC.Theme or {}
local T = GC.Theme
local MEDIA = GC.Kit.MEDIA

-- The faces GoldCap ships, subset by docs/addon/tools/fonts.py (SIL OFL 1.1, Media/OFL-Fira.txt).
-- Text: Fira Sans. Headings, buttons, chips: Fira Sans Condensed. Figures: Fira Mono, whose digits
-- are all one width -- WoW applies no OpenType features, so Fira Sans's proportional digits would
-- shift in a column whenever a price changes.
T.FONT_TEXT = MEDIA .. "FiraSans-Medium.ttf"
T.FONT_TEXT_SEMI = MEDIA .. "FiraSans-SemiBold.ttf"
T.FONT_TEXT_BOLD = MEDIA .. "FiraSans-Bold.ttf"
T.FONT_HEAD = MEDIA .. "FiraSansCondensed-Bold.ttf"
T.FONT_HEAD_HEAVY = MEDIA .. "FiraSansCondensed-ExtraBold.ttf"
T.FONT_MONO = MEDIA .. "FiraMono-Medium.ttf"
T.FONT_MONO_BOLD = MEDIA .. "FiraMono-Bold.ttf"
-- Every face above, for UI/FontPreload.lua.
T.BUNDLED_FACES = { T.FONT_TEXT, T.FONT_TEXT_SEMI, T.FONT_TEXT_BOLD, T.FONT_HEAD, T.FONT_HEAD_HEAVY,
  T.FONT_MONO, T.FONT_MONO_BOLD }

-- The bundled faces cover Latin, Latin Extended and all of Cyrillic (measured by
-- docs/addon/tools/fonts.py, so Russian and Ukrainian need nothing here) and no CJK at all. On Korean and both Chinese
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
-- T.Label already does the equivalent by inheriting GameFontHighlightSmall; this is the same
-- idea for the places that ask for the mono face by name.
local CJK_LOCALES = { koKR = true, zhCN = true, zhTW = true }

-- Locales the CLIENT's own face can only draw when the client itself runs them. A client
-- font always covers Latin, plus exactly the script of the locale it shipped for -- so an
-- English client's FRIZQT__.TTF draws German and Spanish, and nothing else here. Which is
-- not the same as the client having no face for those scripts at all: see CJK_FACES.
local NON_LATIN_LOCALES = { ruRU = true, ukUA = true, koKR = true, zhCN = true, zhTW = true }

-- Languages Fira draws and a Korean or Chinese client's own face does not.
local CYRILLIC_LOCALES = { ruRU = true, ukUA = true }

T.FONT_UI = T.FONT_MONO
T.FONT_UI_BOLD = T.FONT_MONO_BOLD
-- The face T.Label draws with, or nil to keep the one it inherits from GameFontHighlightSmall
-- (the client's own). T.RefreshFonts sets it; see there for when it is nil.
T.FONT_LABEL = T.FONT_TEXT
-- The face T.Heading draws with: the condensed face, or the client's bold face for its script.
T.FONT_HEADING = T.FONT_HEAD

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
  if not CJK_LOCALES[code] then
    T.FONT_UI, T.FONT_UI_BOLD = T.FONT_MONO, T.FONT_MONO_BOLD
    T.FONT_HEADING = T.FONT_HEAD
    -- Fira draws Latin and Cyrillic, so GoldCap's own face carries every label in those languages,
    -- item names included -- except a Latin language on a Korean or Chinese client: an item name
    -- arrives in the client's script there, and only the client's own face can draw it. Cyrillic
    -- stays in Fira even then, because the client's face has no Cyrillic at all.
    -- Spelled as an if, not `cond and nil or X`: that idiom cannot yield nil in Lua.
    if CJK_LOCALES[clientLocale()] and not CYRILLIC_LOCALES[code] then
      T.FONT_LABEL = nil
    else
      T.FONT_LABEL = T.FONT_TEXT
    end
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
    T.FONT_HEADING = T.FONT_UI_BOLD
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
  T.FONT_HEADING = T.FONT_UI_BOLD
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
  elseif role == "head" then path = T.FONT_HEADING
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
  -- Fonts first: a hook lays its tab out again and measures its strings, which must already be
  -- at the new size -- measured at the old one, every fitted column came out too narrow.
  for fs, info in pairs(widgetFonts) do
    applyFont(fs, info)
  end
  for _, fn in ipairs(hooks) do
    fn(scale)
  end
end

--- Registers a FontString another kit file or UI/Theme.lua built, so the font-size slider and
-- T.RefontWidget reach it. `info` is the same data table this file keeps for its own widgets
-- (see widgetFonts above for why it must never reference the FontString).
function T.TrackFont(fs, info)
  widgetFonts[fs] = info
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

-- A FontString made from one of Blizzard's font objects draws in the CLIENT's face, which lacks
-- glyphs the bundled one has (GC.Util.ClientText says which, and how that was read). This gives
-- such a FontString a SetText that respells them, so no caller has to remember to; it returns
-- the FontString, so it wraps the CreateFontString call itself.
-- A widget in Fira Mono (T.Num, T.TierMark: roles "ui" and "uiBold") draws its text as written:
-- that face has every glyph GoldCap writes. Fira Sans and Fira Sans Condensed (roles "label" and
-- "head") have no ▲ or ▼, so their text goes through ClientText as well.
function T.ClientFont(fs)
  if fs.gcClientFont then return fs end
  fs.gcClientFont = true
  local setText = fs.SetText
  fs.SetText = function(self, text, ...)
    local info = widgetFonts[self]
    if not info or info.role == "label" or info.role == "head" then text = GC.Util.ClientText(text) end
    return setText(self, text, ...)
  end
  return fs
end

-- Label: native font (keeps client glyph fallback for localized/item-name text), LEFT-justified,
-- and therefore a ClientFont (above): what it is given is drawn through GC.Util.ClientText.
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
  local fs = T.ClientFont(parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
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

--- A heading, a button's label or a chip's: the condensed face in GoldCap's own languages, the
-- client's bold face for its script on Korean and Chinese (T.RefreshFonts). Drawn through
-- T.ClientFont, because the condensed face has no ▲ or ▼ either.
function T.Heading(parent, size, layer)
  local fs = T.ClientFont(parent:CreateFontString(nil, layer or "OVERLAY"))
  local path = T.FONT_HEADING or T.FONT_HEAD
  fs:SetFont(path, size * T.Scale(), "")
  widgetFonts[fs] = { role = "head", path = path, size = size }
  return fs
end
