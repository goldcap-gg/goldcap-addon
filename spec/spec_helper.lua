local helper = {}

-- WoW globals that pure-ish modules may touch at load time
_G.time = _G.time or os.time
-- WoW runs Lua 5.1, where `unpack` is a global. Newer runners moved it to table.unpack, so
-- provide it here rather than making the client's runtime carry a shim for the test bed.
_G.unpack = _G.unpack or rawget(table, "unpack")

function helper.loadModule(relPath, GC)
  GC = GC or {}
  -- Locale/Core.lua is the second entry in the TOC, so in the real client GC.L exists before
  -- any other file runs. Mirror that here instead of making every spec that loads a UI file
  -- remember to load it: a spec's job is the module under test, not the load order.
  if relPath ~= "Locale/Core.lua" and GC.L == nil then
    local localeChunk = assert(loadfile("GoldCap/Locale/Core.lua"))
    localeChunk("GoldCap", GC)
  end
  local chunk, err = loadfile("GoldCap/" .. relPath)
  assert(chunk, err)
  chunk("GoldCap", GC)
  return GC
end

--- Every locale file that ships. Spelled out rather than globbed: the list IS the contract,
--- so adding a language without listing it here is a visible omission, and the specs stay
--- independent of the shell. Codes are added as their files land.
helper.LOCALE_CODES = { "enUS", "koKR", "ruRU", "ukUA", "zhTW" }

function helper.localeCodes()
  return helper.LOCALE_CODES
end

return helper
