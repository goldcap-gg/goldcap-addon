require("spec.spec_helper")

-- GC.L resolves through whichever table GC.ActivateLocale has installed, and that call
-- happens inside GC.ApplyLocale at ADDON_LOADED -- after every file in the .toc has run.
-- So a GC.L lookup evaluated WHILE a file loads returns the English fallback and keeps it
-- forever, in every language, with nothing failing to say so. It is the same shape of
-- defect as UI/Tooltip.lua shipping English in eleven languages, and just as silent: the
-- key is present, the translation exists, the base and every locale file agree, and the
-- player still reads English.
--
-- Three of them shipped that way and were found by hand (Core/SniperDecision's refusal
-- sentences, UI/SellFrame's action help and keybinding label, UI/SoldFrame's column
-- headers). This is the guard that makes the fourth impossible: nothing may resolve a
-- string at load time at all. A table built at file scope holds KEYS and looks them up
-- where it is read -- see the @localised-keys marker those three now carry.
describe("locale timing", function()
  local function stubFrame()
    local f
    f = setmetatable({}, { __index = function(_, key)
      -- Every widget method the load path touches. Load order is all this spec exercises,
      -- so a bare no-op is right for all of them -- unlike spec/sniper_window_layering_spec,
      -- which builds real rows and needs real nils for its absent fields.
      if key == "CreateFontString" or key == "CreateTexture" then return function() return stubFrame() end end
      if key == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 12, "" end end
      if key == "GetFrameLevel" or key == "GetWidth" or key == "GetHeight" then return function() return 0 end end
      if key == "IsShown" or key == "IsEnabled" then return function() return false end end
      return function() return f end
    end })
    return f
  end

  it("resolves no string while the addon's files are loading", function()
    _G.CreateFrame = function(_, name)
      local f = stubFrame()
      if name and name ~= "" then _G[name] = f end
      return f
    end
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    _G.hooksecurefunc = function() end
    _G.GetTime = function() return 0 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }

    local GC = {}
    local toc = assert(io.open("GoldCap/GoldCap.toc", "r"))
    local files = {}
    for rawLine in toc:lines() do
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^##") then files[#files + 1] = line end
    end
    toc:close()

    -- Locale/Core.lua is second in the .toc and is what creates GC.L. Load the files ahead
    -- of it normally, then wrap the lookup and keep going: everything the guard cares about
    -- loads afterwards.
    -- `loading` is an upvalue updated each iteration, not the loop variable captured when
    -- the wrapper was built -- otherwise every hit is blamed on Locale/Core.lua, the file
    -- that happened to be loading when the wrapper went in.
    local resolved, wrapped = {}, false
    local loading -- set per iteration below; read by the wrapper's closure
    for _, rel in ipairs(files) do
      loading = rel
      local chunk, err = loadfile("GoldCap/" .. rel:gsub("\\", "/"))
      assert(chunk, err)
      chunk("GoldCap", GC)
      if not wrapped and GC.L then
        local inner = getmetatable(GC.L).__index
        setmetatable(GC.L, {
          __index = function(t, key)
            resolved[#resolved + 1] = { key = key, file = loading }
            return inner(t, key)
          end,
          __newindex = function() error("GC.L is read-only", 2) end,
        })
        wrapped = true
      end
    end

    assert.is_true(wrapped, "GC.L was never created -- did Locale/Core.lua leave the .toc?")
    if #resolved > 0 then
      local lines = {}
      for _, hit in ipairs(resolved) do
        lines[#lines + 1] = ("  %s resolved %q while loading"):format(hit.file, hit.key)
      end
      error("a string was translated before ApplyLocale could choose a language, so it is "
        .. "frozen to English in every locale:\n" .. table.concat(lines, "\n"), 0)
    end
  end)
end)
