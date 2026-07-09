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

return helper
