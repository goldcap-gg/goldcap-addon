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
-- The brand (the name, KP.newBrand): the heavy face, or the skin's heading face (ApplySkinFonts).
-- FONT_HEAD_HEAVY itself stays Fira in every skin: it draws the counts over an item's icon, which
-- are numbers and 6 to 8px.
T.FONT_BRAND = T.FONT_HEAD_HEAVY
-- What a skin falls back to, per role: ApplySkinFonts starts from these every time.
local FIRA = { text = T.FONT_TEXT, semi = T.FONT_TEXT_SEMI, bold = T.FONT_TEXT_BOLD, head = T.FONT_HEAD,
  heavy = T.FONT_HEAD_HEAVY }
T.FONT_MONO = MEDIA .. "FiraMono-Medium.ttf"
T.FONT_MONO_BOLD = MEDIA .. "FiraMono-Bold.ttf"
-- Every face above, for UI/FontPreload.lua.
T.BUNDLED_FACES = { T.FONT_TEXT, T.FONT_TEXT_SEMI, T.FONT_TEXT_BOLD, T.FONT_HEAD, T.FONT_HEAD_HEAVY,
  T.FONT_MONO, T.FONT_MONO_BOLD }

-- The bundled faces cover Latin, Latin Extended and all of Cyrillic (measured by
-- docs/addon/tools/fonts.py, so Russian and Ukrainian need nothing here) and no CJK at all.
-- On Korean and both Chinese locales anything drawn with it would be empty boxes, so those
-- locales draw in one of Blizzard's own faces for the script instead -- see CJK_FACES below
-- for which, and for why "the client's own font" is NOT the same thing.
--
-- This covers T.Num too, not just buttons and chips. T.Num draws the column headers and band
-- labels as well as the figures, so leaving it on the bundled face would render those headers
-- as empty boxes on exactly the locales this batch exists for. The trade is real and taken
-- deliberately: on CJK the digits stop being monospaced, so number columns line up by their
-- RIGHT anchor rather than by character width. Boxes would be worse.
--
-- T.Label and T.Heading follow the same rule through T.FONT_LABEL and T.FONT_HEADING (see
-- T.RefreshFonts); this is the same idea for the places that ask for the mono face by name.
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
-- The face for GoldCap text placed inside Blizzard's own frames (the quest window), or nil to
-- keep Blizzard's face, which is right whenever the client draws the language. T.RefreshFonts
-- sets it.
T.FONT_FOREIGN = nil

local function clientLocale()
  local ok, code = pcall(function() return GetLocale and GetLocale() end)
  return ok and type(code) == "string" and code ~= "" and code or nil
end

-- Paths of the bundled faces, to tell a widget on one of them from one moved to a client face.
local bundledFace = {}
for _, path in ipairs(T.BUNDLED_FACES) do bundledFace[path] = true end

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
-- Only a yes is remembered: a face the client has not loaded yet in this run fails its first
-- SetFont (an error or false) and loads a moment later (skin probe, WoW: Forever 2026-11-10).
local probeFontString, faceCache = nil, {}
local function faceLoads(path)
  if not probeFontString then
    local ok, fs = pcall(function()
      return _G.UIParent and _G.UIParent:CreateFontString(nil, "OVERLAY")
    end)
    if not ok or not fs then return false end
    probeFontString = fs
  end
  if faceCache[path] then return true end
  local ok, valid = pcall(probeFontString.SetFont, probeFontString, path, 12, "")
  local loads = (ok and valid == true) and true or false
  if loads then faceCache[path] = true end
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

-- The language last given to RefreshFonts, so a skin applied later settles on the same one.
local lastCode

function T.RefreshFonts(code)
  lastCode = code
  if not CJK_LOCALES[code] then
    T.FONT_UI, T.FONT_UI_BOLD = T.FONT_MONO, T.FONT_MONO_BOLD
    T.FONT_HEADING = T.FONT_HEAD
    -- Inside Blizzard's frames the client's face stands, unless GoldCap speaks Cyrillic on a
    -- client that is not running it (the client's face has none).
    if CYRILLIC_LOCALES[code] and code ~= clientLocale() then
      T.FONT_FOREIGN = T.FONT_TEXT
    else
      T.FONT_FOREIGN = nil
    end
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
    T.FONT_FOREIGN = code ~= clientLocale() and T.FONT_UI or nil
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
  T.FONT_FOREIGN = code ~= clientLocale() and T.FONT_UI or nil
  return T.FONT_UI
end

-- Headings and body text of the applied skin (UI/Kit/Skins.lua `fonts`); the shipped faces are
-- listed in docs/addon/tools/fonts.py. Figures never change: T.FONT_MONO and T.FONT_UI stay Fira
-- Mono in every skin. Each role starts from Fira and takes the skin's face only if the client
-- loads it (faceLoads), so a missing file leaves that role on Fira rather than drawing nothing.
-- The skin's `display` flag turns on the 11px floor of T.Heading and T.Label.
T.MIN_DISPLAY_SIZE = 11
local displayFaces = false
-- The skin draws headings and body text through the client's own Font objects (Classic).
local clientFonts = false

-- Classic's family: one member per alphabet, so the client picks the face for the script of the text
-- (Latin, Cyrillic, Korean, both Chinese). A Font object has one size, so there is one family per
-- size, made on first use and kept; sizes go in half-pixel steps, so a font-scale drag makes few.
-- Where the client cannot make one, GameFontNormal stands, at its own size; where it has not even
-- that, nil, and the caller keeps the bundled face.
local CLASSIC_FACES = {
  { "roman", "Fonts\\FRIZQT__.TTF" }, { "russian", "Fonts\\FRIZQT___CYR.TTF" },
  { "korean", "Fonts\\2002.TTF" }, { "simplifiedchinese", "Fonts\\ARKai_T.ttf" },
  { "traditionalchinese", "Fonts\\bLEI00D.ttf" },
}
T.CLASSIC_FACES = CLASSIC_FACES
local classicFamilies = {}

function T.ClassicFont(size)
  size = math.floor(size * 2 + 0.5) / 2
  local cached = classicFamilies[size]
  if cached ~= nil then return cached or nil end
  local name = "GoldCapClassic" .. string.format("%g", size):gsub("%.", "_")
  local family = _G[name]
  if not family and _G.CreateFontFamily then
    local members = {}
    for i, face in ipairs(CLASSIC_FACES) do
      members[i] = { alphabet = face[1], file = face[2], height = size, flags = "" }
    end
    local ok, made = pcall(_G.CreateFontFamily, name, members)
    family = ok and made or nil
  end
  family = family or _G.GameFontNormal
  classicFamilies[size] = family or false
  return family
end

-- A Font object made here carries no shadow; Classic's text has the client's.
local function clientShadow(fs)
  if fs.SetShadowOffset then
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.95) -- untinted
  end
end

--- Puts `fs` on the client's face for `size` at the font scale; false when there is none, and the
-- caller draws in Fira.
function T.UseClientFont(fs, size)
  local object = T.ClassicFont(size * T.Scale())
  if not object then return false end
  fs:SetFontObject(object)
  clientShadow(fs)
  return true
end

-- Puts a FontString already drawn through a Font object on `object` (the font scale moved), keeping
-- what its caller gave it since: a Font object carries a colour and a justification of its own.
local function reuseFontObject(fs, object)
  local r, g, b, a
  if fs.GetTextColor then r, g, b, a = fs:GetTextColor() end
  local justifyH = fs.GetJustifyH and fs:GetJustifyH()
  local justifyV = fs.GetJustifyV and fs:GetJustifyV()
  fs:SetFontObject(object)
  if r then fs:SetTextColor(r, g, b, a) end
  if justifyH then fs:SetJustifyH(justifyH) end
  if justifyV then fs:SetJustifyV(justifyV) end
  clientShadow(fs)
end

local function skinFace(file)
  if not file then return nil end
  local path = MEDIA .. file
  if faceLoads(path) then
    bundledFace[path] = true
    return path
  end
  return nil
end

local function setSkinFaces(fonts)
  local text = fonts.text or {}
  local head = skinFace(fonts.head)
  T.FONT_HEAD = head or FIRA.head
  T.FONT_BRAND = head or FIRA.heavy
  T.FONT_TEXT = skinFace(text.regular) or FIRA.text
  T.FONT_TEXT_SEMI = skinFace(text.semi) or FIRA.semi
  T.FONT_TEXT_BOLD = skinFace(text.bold) or FIRA.bold
  displayFaces = fonts.display == true
  clientFonts = fonts.client == true
  -- FONT_HEADING and FONT_LABEL derive from the faces above, and from the language (CJK keeps
  -- its own faces).
  T.RefreshFonts(lastCode)
end

local function allFacesLoad(fonts)
  if fonts.head and not faceLoads(MEDIA .. fonts.head) then return false end
  for _, file in pairs(fonts.text or {}) do
    if not faceLoads(MEDIA .. file) then return false end
  end
  return true
end

-- A skin face the client is still loading draws in Fira for now. The skin's faces are asked again
-- every half second for ten seconds, each one taken as it loads: long before a window is built
-- (the first is built on the first auction house visit). A face that never loads stays Fira.
local ASK_EVERY, ASK_TIMES = 0.5, 20
local waiting

local function askAgain()
  if not waiting then return end
  waiting.asked = waiting.asked + 1
  setSkinFaces(waiting.fonts)
  if allFacesLoad(waiting.fonts) or waiting.asked >= ASK_TIMES then
    waiting = nil
  else
    _G.C_Timer.After(ASK_EVERY, askAgain)
  end
end

function T.ApplySkinFonts(fonts)
  fonts = fonts or {}
  setSkinFaces(fonts)
  waiting = nil
  if not allFacesLoad(fonts) and _G.C_Timer and _G.C_Timer.After then
    waiting = { fonts = fonts, asked = 0 }
    _G.C_Timer.After(ASK_EVERY, askAgain)
  end
end

--- True while the applied skin draws its text through the client's Font objects.
function T.ClientFonts() return clientFonts end

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

-- The widget's own face at the scale: its path, or its Font object (Classic) made for the scaled size.
local function applyOwnFont(fs, info)
  if info.object then
    local object = T.ClassicFont(info.size * scale)
    if object then reuseFontObject(fs, object) end
    return
  end
  if not info.path then return end
  -- Flags come from the widget, not from "": a Label inherits its outline from
  -- GameFontHighlightSmall, and passing "" here used to strip it off every label the first
  -- time the font-scale slider moved.
  pcall(fs.SetFont, fs, info.path, info.size * scale, info.flags or "")
end

-- A heading given a room (T.FitHeading) whose text runs wider than that in its own face: drawn in
-- the face and at the size goldcap draws it (info.fallback, info.fallbackSize) instead. Expects the
-- own face on.
local function fitHeading(fs, info)
  info.fitted = nil
  local room = info.room
  if not (room and room > 0 and fs.GetUnboundedStringWidth) then return end
  if (fs:GetUnboundedStringWidth() or 0) <= room then return end
  pcall(fs.SetFont, fs, info.fallback, info.fallbackSize * scale, "")
  info.fitted = true
end

local function applyFont(fs, info)
  applyOwnFont(fs, info)
  if info.fallback then fitHeading(fs, info) end
end

-- What T.FitHeading falls back to for a heading T.Heading built at `info.asked`: the face goldcap
-- draws it in, Fira's condensed face (the language's own on Korean and Chinese, which Fira cannot
-- draw), at the size asked for, under the display floor. None where the heading is drawn so already:
-- goldcap's look.
local function setFallback(info)
  local fallback = CJK_LOCALES[lastCode] and (T.FONT_HEADING or FIRA.head) or FIRA.head
  if info.object or info.path ~= fallback or info.size ~= info.asked then
    info.fallback, info.fallbackSize = fallback, info.asked
  else
    info.fallback, info.fallbackSize = nil, nil
  end
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
  if info.object then return end -- on one of the client's Font objects, which names its own face
  local role = info.role
  local path
  if role == "mono" then path = T.FONT_MONO_BOLD       -- the brand "G": latin, always
  elseif role == "uiBold" then path = T.FONT_UI_BOLD
  elseif role == "head" then path = T.FONT_HEADING
  elseif role == "label" then path = T.FONT_LABEL or info.inherited
  else path = T.FONT_UI end
  if not path then return end
  info.path = path
  if info.asked then setFallback(info) end
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

-- Gives a FontString a SetText that respells the glyphs its face lacks, so no caller has to
-- remember to; it returns the FontString, so it wraps the CreateFontString call itself.
-- The respelling follows the FACE the widget draws in now (GC.Util.ClientText says what the
-- client's faces lack, and how that was read):
--   - roles "ui" and "uiBold" (Fira Mono: T.Num, T.TierMark) draw their text as written, the
--     face has every glyph GoldCap writes;
--   - roles "label" and "head" on a bundled Fira face lack only ▲ and ▼ (GC.Util.TriangleText),
--     so a button's "AUTO · SCANNING" keeps its dot and arrow;
--   - a "label" or "head" widget on any other face (the client's own, or a CJK face after
--     T.RefontWidget), or one with no tracked info, gets the full ClientText respelling.
function T.ClientFont(fs)
  if fs.gcClientFont then return fs end
  fs.gcClientFont = true
  local setText = fs.SetText
  fs.SetText = function(self, text, ...)
    local info = widgetFonts[self]
    if not info then
      text = GC.Util.ClientText(text)
    elseif info.role == "label" or info.role == "head" then
      text = bundledFace[info.path] and GC.Util.TriangleText(text) or GC.Util.ClientText(text)
    end
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
  if displayFaces then size = math.max(size, T.MIN_DISPLAY_SIZE) end
  local fs = T.ClientFont(parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
  -- On a light window (Parchment's paper) the template's white text and black shadow do not read:
  -- a label starts in the window's ink, unshadowed. A caller that colours it still does.
  if GC.Kit.Skins.Current().paper then
    local ink = GC.Kit.Tokens.color.text1
    fs:SetTextColor(ink[1], ink[2], ink[3], 1)
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
  end
  if clientFonts and T.UseClientFont(fs, size) then
    -- A font object carries its size; SetScale re-applies a family at size * scale.
    widgetFonts[fs] = { role = "label", size = size, object = true }
    fs:SetJustifyH("LEFT")
    return fs
  end
  local inherited, _, flags = fs:GetFont()
  -- T.FONT_LABEL is Fira for every Latin or Cyrillic language and nil only where the client's
  -- own face must stand (a Latin language on a Korean or Chinese client); then the inherited
  -- face is used.
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
  local asked = size
  if displayFaces then size = math.max(size, T.MIN_DISPLAY_SIZE) end
  local fs = T.ClientFont(parent:CreateFontString(nil, layer or "OVERLAY"))
  local info
  if clientFonts and T.UseClientFont(fs, size) then
    info = { role = "head", size = size, object = true }
  else
    local path = T.FONT_HEADING or T.FONT_HEAD
    fs:SetFont(path, size * T.Scale(), "")
    info = { role = "head", path = path, size = size }
  end
  info.asked = asked
  setFallback(info)
  widgetFonts[fs] = info
  return fs
end

--- Whether a heading T.Heading built can be drawn in a second face when its own runs too wide
-- (T.FitHeading): false in goldcap's look, where its face is the second one.
function T.CanFitHeading(fs)
  local info = fs and widgetFonts[fs]
  return info ~= nil and info.fallback ~= nil
end

--- Keeps a heading T.Heading built inside `room` px (nil: no room to keep): in its own face while
-- its text fits there, else in the face and size goldcap draws it (T.Heading's fallback). Asked by
-- whoever changes the text or the room (Theme.Button); T.SetScale and T.RefontWidget ask again.
function T.FitHeading(fs, room)
  local info = fs and widgetFonts[fs]
  if not (info and info.fallback) then return end
  info.room = room
  if info.fitted then applyOwnFont(fs, info) end
  fitHeading(fs, info)
end
