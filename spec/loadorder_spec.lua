require("spec.spec_helper") -- side effect: seeds _G.time for load-time use

describe("TOC load order", function()
  it("loads every TOC file in order and wires slash handlers", function()
    _G.CreateFrame = function()
      return {
        RegisterEvent = function() end,
        SetScript = function() end,
      }
    end
    _G.SlashCmdList = {}
    _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }

    local GC = {}
    local toc = assert(io.open("GoldCap/GoldCap.toc", "r"))
    local files = {}
    for rawLine in toc:lines() do
      -- Lua 5.5 makes for-loop control variables const, so trim into a new local
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^##") then
        files[#files + 1] = line
      end
    end
    toc:close()
    assert.is_true(#files >= 7)

    for _, rel in ipairs(files) do
      local chunk, err = loadfile("GoldCap/" .. rel:gsub("\\", "/"))
      assert.truthy(chunk, err)
      chunk("GoldCap", GC)
    end

    assert.is_function(GC.slashHandlers.import)
    assert.is_function(GC.slashHandlers.status)
    assert.is_function(GC.UI.ShowImportDialog)
    assert.is_function(GC.Tooltip.BuildLines)

    _G.CreateFrame = nil
    _G.SlashCmdList = nil
    _G.C_AddOns = nil
    _G.GoldCap_MarketData = nil
    _G.SLASH_GOLDCAP1 = nil
  end)
end)
