local _, GC = ...

-- Library-free localisation, the pattern warcraft.wiki.gg's "Localizing an addon"
-- documents: a table whose metatable returns the key, so a missing translation degrades to
-- readable English instead of a blank or a raw identifier. The key IS the English sentence,
-- which also means the spec suite -- where no locale is ever active -- keeps seeing the
-- English text it already asserts on.
--
-- One deliberate deviation from the wiki's version: its locale files self-select with
-- `if GetLocale() == "deDE"`. Ours cannot. Ukrainian has no WoW client locale at all, so the
-- language has to be selectable at runtime, which means every table must be present and the
-- active one chosen afterwards. Roughly 7 KB per language, resident.
GC.Locales = {}

local active = nil

GC.L = setmetatable({}, {
  __index = function(_, key)
    local translated = active and active[key]
    return translated or key
  end,
  __newindex = function()
    error("GC.L is read-only -- add strings to Locale/<code>.lua", 2)
  end,
})

--- Switches the active table. Returns whether a table was found; an unknown code leaves
--- every lookup as the identity, which is exactly English.
function GC.ActivateLocale(code)
  active = code and GC.Locales[code] or nil
  return active ~= nil
end

-- Pure so it can be tested without the client. "auto" means follow the game; anything else
-- is the player's explicit choice from Settings -- the only way to reach ukUA, which
-- GetLocale() never returns because no Ukrainian client exists. enGB is mapped rather than
-- listed: the wiki states enGB clients report enUS, so it should be unreachable, but a
-- stray value must resolve to something readable rather than blank the interface.
local CLIENT_LOCALES = {
  enUS = true, koKR = true, frFR = true, deDE = true, zhCN = true, esES = true,
  zhTW = true, esMX = true, ruRU = true, ptBR = true, itIT = true,
  enGB = "enUS",
}

function GC.ResolveLocale(setting, clientLocale)
  if setting and setting ~= "auto" then return setting end
  local mapped = clientLocale and CLIENT_LOCALES[clientLocale]
  if mapped == true then return clientLocale end
  if type(mapped) == "string" then return mapped end
  return "enUS"
end

-- The picker's contents, in display order: "follow the game" first, then every language
-- written in ITSELF -- a player who cannot read the language currently active must still be
-- able to find their own. Ukrainian sits in the list on equal terms even though no Ukrainian
-- client exists; the picker is the only way to reach it.
GC.LOCALE_CHOICES = {
  { code = "auto",  label = "Game language" },
  { code = "deDE",  label = "Deutsch" },
  { code = "enUS",  label = "English" },
  { code = "esES",  label = "Espanol" },
  { code = "esMX",  label = "Espanol (Mexico)" },
  { code = "frFR",  label = "Francais" },
  { code = "itIT",  label = "Italiano" },
  { code = "ptBR",  label = "Portugues" },
  { code = "ruRU",  label = "Русский" },
  { code = "ukUA",  label = "Українська" },
  { code = "koKR",  label = "한국어" },
  { code = "zhCN",  label = "简体中文" },
  { code = "zhTW",  label = "繁體中文" },
}

--- The label the picker shows for a stored setting value.
function GC.LocaleChoiceLabel(code)
  for _, choice in ipairs(GC.LOCALE_CHOICES) do
    if choice.code == code then return choice.label end
  end
  return GC.LOCALE_CHOICES[1].label
end

-- The one call that turns the saved setting into the active table, plus the font that can
-- actually draw it. Kept here rather than in Init.lua so the whole locale decision lives in
-- one file.
function GC.ApplyLocale()
  local setting = GC.db and GC.db.settings and GC.db.settings.locale or "auto"
  local clientLocale = _G.GetLocale and _G.GetLocale() or nil
  local code = GC.ResolveLocale(setting, clientLocale)
  GC.ActivateLocale(code)
  if GC.Theme and GC.Theme.RefreshFonts then GC.Theme.RefreshFonts(code) end
  return code
end

