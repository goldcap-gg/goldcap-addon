local helper = {}

-- WoW globals that pure-ish modules may touch at load time
_G.time = _G.time or os.time

function helper.loadModule(relPath, GC)
  GC = GC or {}
  local chunk, err = loadfile("GoldCap/" .. relPath)
  assert(chunk, err)
  chunk("GoldCap", GC)
  return GC
end

--- Every locale file that ships. Spelled out rather than globbed: the list IS the contract,
--- so adding a language without listing it here is a visible omission, and the specs stay
--- independent of the shell. Codes are added as their files land.
helper.LOCALE_CODES = { "enUS" }

function helper.localeCodes()
  return helper.LOCALE_CODES
end

return helper
