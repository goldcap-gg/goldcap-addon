require("spec.spec_helper") -- side effect: seeds _G.time for load-time use

describe("TOC load order", function()
  it("loads every TOC file in order and wires slash handlers", function()
    local function stubFrame()
      local f
      f = {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function() end,
        SetSize = function() end,
        SetPoint = function() end,
        SetMovable = function() end,
        EnableMouse = function() end,
        RegisterForDrag = function() end,
        Show = function() end,
        Hide = function() end,
        IsShown = function() return false end,
        SetText = function() end,
        SetTexture = function() end,
        SetTextColor = function() end,
        SetJustifyH = function() end,
        SetWidth = function() end,
        SetScrollChild = function() end,
        StartMoving = function() end,
        StopMovingOrSizing = function() end,
        CreateFontString = function() return stubFrame() end,
        CreateTexture = function() return stubFrame() end,
        TitleText = { SetText = function() end },
        EnableMouseWheel = function() end,
        SetVerticalScroll = function() end,
        GetVerticalScroll = function() return 0 end,
        GetVerticalScrollRange = function() return 0 end,
        SetWordWrap = function() end,
        SetMaxLines = function() end,
        Enable = function() end,
        Disable = function() end,
        GetFontString = function() return nil end,
        -- E.2/E.3/E.4 (Sniper v2 UI polish): resize/reposition/texture-fill widget API
        -- SniperFrame.lua's createFrame/createRow now touch during frame construction.
        SetResizable = function() end,
        SetResizeBounds = function() end,
        StartSizing = function() end,
        ClearAllPoints = function() end,
        GetPoint = function() return nil end,
        GetHeight = function() return 0 end,
        GetFrameLevel = function() return 1 end,
        SetFrameLevel = function() end,
        SetColorTexture = function() end,
        SetAllPoints = function() end,
        -- D (Sniper v2 Sell view): GC.Sell.Attach/renderRows stamp the scroll child's height
        -- the same way the Deals view's refreshRows always has -- now reachable from
        -- GC.Sniper.Toggle() too, since it refreshes the Sell tab's rows on every show.
        SetHeight = function() end,
        -- Sniper v3 (Theme.lua): Label/Num fontstrings and Chip/Button custom fonts
        -- re-font via SetFont; Label reads the native font path via GetFont first.
        SetFont = function() end,
        GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
        RegisterForClicks = function() end,
      }
      return f
    end
    _G.CreateFrame = function()
      return stubFrame()
    end
    _G.UISpecialFrames = _G.UISpecialFrames or {}
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
    assert.is_function(GC.Scanner.New)
    assert.is_function(GC.DealMath.Evaluate)
    assert.is_function(GC.slashHandlers.sniper)
    assert.is_function(GC.Sniper.Toggle)

    -- exercise real frame construction through the stubbed CreateFrame
    assert.has_no.errors(function() GC.Sniper.Toggle() end)

    _G.CreateFrame = nil
    _G.UISpecialFrames = nil
    _G.SlashCmdList = nil
    _G.C_AddOns = nil
    _G.GoldCap_MarketData = nil
    _G.SLASH_GOLDCAP1 = nil
  end)
end)
