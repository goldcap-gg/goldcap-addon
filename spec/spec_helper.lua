local helper = {}

-- WoW globals that pure-ish modules may touch at load time
_G.time = _G.time or os.time
-- WoW runs Lua 5.1, where `unpack` is a global. Newer runners moved it to table.unpack, so
-- provide it here rather than making the client's runtime carry a shim for the test bed.
_G.unpack = _G.unpack or rawget(table, "unpack")
-- The client's securecallfunction runs `fn` without letting it taint the caller; there is no
-- taint here, so it is a plain call. Errors propagate rather than going to an error handler, so
-- a spec sees them. spec/forever_taint_flow_spec.lua swaps in its own model and puts this back.
function helper.securecallfunction(fn, ...)
  return fn(...)
end
_G.securecallfunction = _G.securecallfunction or helper.securecallfunction

--- UI/Kit/*.lua, in the order both TOCs load them, right before UI/Theme.lua
--- (spec/kit_structure_spec.lua holds the TOCs to this list). Theme.lua builds on them.
helper.KIT_FILES = { "UI/Kit/Tokens.lua", "UI/Kit/Icons.lua", "UI/Kit/Fonts.lua", "UI/Kit/Textures.lua", "UI/Kit/Card.lua", "UI/Kit/Button.lua" }

function helper.loadModule(relPath, GC)
  GC = GC or {}
  -- Locale/Core.lua is the second entry in the TOC, so in the real client GC.L exists before
  -- any other file runs. Mirror that here instead of making every spec that loads a UI file
  -- remember to load it: a spec's job is the module under test, not the load order.
  if relPath ~= "Locale/Core.lua" and GC.L == nil then
    local localeChunk = assert(loadfile("GoldCap/Locale/Core.lua"))
    localeChunk("GoldCap", GC)
  end
  -- Core/PurchaseCall.lua loads before every UI file in both TOCs; the purchase clicks in
  -- UI/SniperFrame.lua and UI/BuyFrame.lua go through it. Same reasoning as the locale above.
  if relPath:match("^UI/") and GC.PurchaseCall == nil then
    local callChunk = assert(loadfile("GoldCap/Core/PurchaseCall.lua"))
    callChunk("GoldCap", GC)
  end
  -- UI/Theme.lua builds on the kit, which loads right before it in both TOCs, and draws its
  -- headings and labels through Core/Util.lua's ClientText, which loads long before it. Same
  -- reasoning as the locale above: a spec loading Theme gets what the client would already have
  -- loaded. A spec that brought its own GC.Util keeps it.
  if relPath == "UI/Theme.lua" and GC.Kit == nil then
    if GC.Util == nil then
      local utilChunk = assert(loadfile("GoldCap/Core/Util.lua"))
      utilChunk("GoldCap", GC)
    end
    for _, kit in ipairs(helper.KIT_FILES) do
      local kitChunk = assert(loadfile("GoldCap/" .. kit))
      kitChunk("GoldCap", GC)
    end
  end
  local chunk, err = loadfile("GoldCap/" .. relPath)
  assert(chunk, err)
  chunk("GoldCap", GC)
  return GC
end

--- Every locale file that ships. Spelled out rather than globbed: the list IS the contract,
--- so adding a language without listing it here is a visible omission, and the specs stay
--- independent of the shell. Codes are added as their files land.
helper.LOCALE_CODES = { "deDE", "enUS", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "ukUA", "zhCN", "zhTW" }

function helper.localeCodes()
  return helper.LOCALE_CODES
end

return helper
