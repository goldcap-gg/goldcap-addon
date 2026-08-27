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
