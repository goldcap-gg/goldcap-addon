local helper = require("spec.spec_helper")

-- Fix round (C1/I1 on the toolbar rework): `status` is a shared cross-view channel --
-- SellFrame.lua's setStatus routes ~40 user-facing messages through it -- and must survive
-- setView's Deals-only chrome toggle, while `sessionText` must never be left showing a stale
-- or zero-buy figure. Self-contained per house style; reaches setView/refreshSessionText the
-- same debug.getupvalue way spec/auto_verify_spec.lua and spec/sniper_pin_feedback_spec.lua
-- already do (see their own comments on the seam: every closure in the SniperFrame.lua chunk
-- shares the same upvalue cell for a given module-local, so setting one through any function
-- that reaches it sets it for all of them).
describe("Toolbar chrome: shared status channel + honest session block", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local function widget()
    local w = { shown = false }
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:SetActive(active) self.active = active end
    function w:SetText(text) self.text = text end
    function w:SetTextColor(...) self.color = { ... } end
    return w
  end

  local function loadSniper()
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.GetCoinTextureString = function(copper) return tostring(copper) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}

    local GC = {
      Theme = {
        ROW_H = 20,
        RAIL_W = 76,
        pad = { m = 8, s = 4, xs = 2 },
        tier = { WATCH = { 1, 1, 1 } },
        color = { watch = { 0.35, 0.72, 0.90 }, gold = { 0.83, 0.64, 0.22 }, fgDim = { 0.5, 0.5, 0.5 }, fgMuted = { 0.72, 0.71, 0.69 },
          fg = { 0.92, 0.91, 0.89 }, green = { 0, 1, 0 }, red = { 1, 0, 0 } },
      },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end }
      end },
      Scanner = { New = function() return { Start = function() end, Stop = function() end } end },
      Data = { GetItemValue = function() return nil end },
      FullScan = {},
      -- setView's Sell branch calls these directly.
      Sell = { Show = function() end, Hide = function() end },
      db = { settings = { sniper = {} } },
    }
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/BoardRows.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.C_Timer, _G.Item = nil, os.time, nil, nil
    _G.GetCoinTextureString, _G.ITEM_QUALITY_COLORS = nil, nil
  end)

  it("status stays shown after switching off Deals -- it is a shared cross-view channel, not deals-only chrome", function()
    local GC = loadSniper()
    -- createFrame is a direct upvalue of OnAuctionHouseShow (it calls `frame = frame or
    -- createFrame()`); setView is a direct upvalue of createFrame (its rail buttons' OnClick
    -- closures call it) -- neither hop requires actually invoking createFrame's real widget
    -- construction.
    local createFrame = upvalue(GC.Sniper.OnAuctionHouseShow, "createFrame")
    local setView = upvalue(createFrame, "setView")

    local status = widget()
    status.shown = true -- SellFrame.setStatus keeps writing through this while Sell is showing
    local fakeFrame = {
      scroll = widget(), headerRow = widget(),
      -- Deals-only widgets ONLY -- status is deliberately absent, matching the real
      -- f.dealsChrome built in createFrame after the C1 fix.
      dealsChrome = { widget(), widget(), widget(), widget(), widget() },
      dealsTab = widget(), sellTab = widget(), soldTab = widget(),
      status = status,
    }
    set(setView, "frame", fakeFrame)

    setView("sell")

    assert.is_true(status.shown)
  end)

  it("refreshSessionText hides the session block when the session has zero buys", function()
    local GC = loadSniper()
    -- refreshSessionText is a direct upvalue of OnAuctionHouseShow: its 0.25s ticker closure
    -- calls it by name, which pulls it into OnAuctionHouseShow's own upvalue chain too (see
    -- this file's describe-block comment on the shared-cell seam).
    local refreshSessionText = upvalue(GC.Sniper.OnAuctionHouseShow, "refreshSessionText")

    local sessionText = widget()
    sessionText.shown = true -- starts visible, so the assertion below proves a real flip
    set(refreshSessionText, "frame", { sessionText = sessionText })
    GC.Sniper.session.buys = 0

    refreshSessionText()

    assert.is_false(sessionText.shown)
  end)

  -- I1(b): OnAuctionHouseClosed's session wipe plus its own refreshSessionText() call,
  -- exercised directly against refreshSessionText rather than through the full
  -- GC.Sniper.OnAuctionHouseClosed pipeline (stopScanning/abortFullScan/resetAllPurchases/...),
  -- which needs a much larger stub surface for no additional coverage of THIS behavior -- the
  -- fix is entirely "wipe the session fields, then call refreshSessionText()", and that is
  -- exactly what this test drives.
  it("simulates an AH-close session wipe: refreshSessionText hides a stale session block on Deals", function()
    local GC = loadSniper()
    local refreshSessionText = upvalue(GC.Sniper.OnAuctionHouseShow, "refreshSessionText")

    local sessionText = widget()
    set(refreshSessionText, "frame", { sessionText = sessionText })

    -- A session with buys, rendered once mid-visit (the module-local `view` defaults to
    -- "deals", matching the toolbar's own view at that point).
    GC.Sniper.session.buys, GC.Sniper.session.spent, GC.Sniper.session.estProfit = 2, 500, 900
    refreshSessionText()
    assert.is_true(sessionText.shown)

    -- ...the wipe GC.Sniper.OnAuctionHouseClosed performs (session fields zeroed), immediately
    -- followed by the same refreshSessionText() call the fix added right after it.
    GC.Sniper.session.buys, GC.Sniper.session.spent, GC.Sniper.session.estProfit = 0, 0, 0
    refreshSessionText()

    assert.is_false(sessionText.shown)
  end)

  local function fakeToolbarFrame()
    return {
      scroll = widget(), headerRow = widget(),
      dealsChrome = { widget(), widget(), widget(), widget(), widget() },
      dealsTab = widget(), sellTab = widget(), soldTab = widget(),
      status = widget(),
    }
  end

  -- One throttled search slot serves the whole addon: a Deals scan running behind the Sell
  -- tab starved the pricing walk's queries silently. setView now feeds Auto a pause/resume
  -- reason on every transition into/out of the Sell view; feedAuto is stubbed via
  -- debug.setupvalue on setView itself, same seam this file already uses for frame/view.
  it("setView pauses Auto entering Sell and resumes it leaving Sell for Deals", function()
    local GC = loadSniper()
    local createFrame = upvalue(GC.Sniper.OnAuctionHouseShow, "createFrame")
    local setView = upvalue(createFrame, "setView")

    local calls = {}
    set(setView, "feedAuto", function(event) calls[#calls + 1] = event end)
    set(setView, "frame", fakeToolbarFrame())

    setView("sell")
    assert.same({ "pause:sell" }, calls)

    setView("deals")
    assert.same({ "pause:sell", "resume:sell" }, calls)
  end)

  -- Sold never queries the AH, so it neither pauses nor is resumed-from unless the player
  -- was actually leaving Sell.
  it("setView('sold') resumes Auto only when coming from Sell, not from Deals", function()
    local GC = loadSniper()
    local createFrame = upvalue(GC.Sniper.OnAuctionHouseShow, "createFrame")
    local setView = upvalue(createFrame, "setView")

    local calls = {}
    set(setView, "feedAuto", function(event) calls[#calls + 1] = event end)
    set(setView, "frame", fakeToolbarFrame())

    setView("sold") -- Deals -> Sold: nothing to pause or resume
    assert.same({}, calls)

    setView("sell")
    assert.same({ "pause:sell" }, calls)

    setView("sold") -- Sell -> Sold: releases the search slot
    assert.same({ "pause:sell", "resume:sell" }, calls)
  end)

  it("renders 'AUTO · PAUSED: selling' when the sell pause reason is the one set", function()
    local GC = loadSniper()
    local createFrame = upvalue(GC.Sniper.OnAuctionHouseShow, "createFrame")
    local setView = upvalue(createFrame, "setView")
    local feedAuto = upvalue(setView, "feedAuto")
    local refreshAutoButton = upvalue(feedAuto, "refreshAutoButton")
    local autoButtonText = upvalue(refreshAutoButton, "autoButtonText")

    assert.equal("AUTO · PAUSED: selling", autoButtonText("PAUSED", { sell = true }))
  end)
end)

-- I1 (fix wave, sell honesty): reproduces the bug through the actual Auto button click rather
-- than the FSM/upvalue seam above -- onAutoToggleClick is a `local function` closed over
-- inside createFrame's own body (never a module upvalue reachable via debug.getupvalue the
-- way setView/feedAuto are), so the only way to drive it for real is a real `frame.autoBtn`,
-- which needs a real createFrame() construction. Follows spec/loadorder_spec.lua and
-- spec/sniper_panel_inset_spec.lua's own recipe: the full GoldCap.toc load order against a
-- fully rigged CreateFrame stub, then a real GC.Sniper.Toggle(), to get real autoBtn/sellTab
-- widgets back and read their real OnClick handlers off `.scripts.OnClick`.
describe("Auto toggle click: sell pause survives an off->on cycle while Sell is showing", function()
  -- Copied from spec/sniper_panel_inset_spec.lua's own stubFrame() (itself copied from
  -- spec/loadorder_spec.lua) -- kept as a per-spec double per addon/AGENTS.md's own note on
  -- this pattern, rather than shared, so a change to either spec's construction needs does not
  -- silently perturb this one.
  local function stubFrame()
    local f
    f = {
      RegisterEvent = function() end,
      UnregisterEvent = function() end,
      scripts = {},
      SetScript = function(self, name, fn) self.scripts = self.scripts or {}; self.scripts[name] = fn end,
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
      SetSpacing = function() end,
      Enable = function() end,
      Disable = function() end,
      GetFontString = function() return nil end,
      SetResizable = function() end,
      SetResizeBounds = function() end,
      StartSizing = function() end,
      ClearAllPoints = function() end,
      GetPoint = function() return nil end,
      GetHeight = function() return 0 end,
      GetFrameLevel = function() return 1 end,
      SetFrameLevel = function() end,
      SetColorTexture = function() end,
      SetBlendMode = function() end,
      SetTextureSliceMargins = function() end,
      SetVertexColor = function() end,
      SetAllPoints = function() end,
      SetHeight = function() end,
      SetFont = function() end,
      GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
      RegisterForClicks = function() end,
      SetFrameStrata = function() end,
      -- The window declares its own layering (SniperFrame's createFrame/SetDocked):
      -- HIGH + toplevel while floating, the host's strata while docked.
      SetToplevel = function() end,
      GetFrameStrata = function() return "MEDIUM" end,
      GetWidth = function() return 0 end,
      HookScript = function() end,
      IsEnabled = function() return true end,
      SetAlpha = function() end,
      CreateAnimationGroup = function()
        return {
          CreateAnimation = function()
            return {
              SetFromAlpha = function() end,
              SetToAlpha = function() end,
              SetDuration = function() end,
              SetSmoothing = function() end,
              SetOrder = function() end,
              SetTarget = function() end,
            }
          end,
          SetLooping = function() end,
          SetScript = function() end,
          Play = function() end,
          Stop = function() end,
          IsPlaying = function() return false end,
        }
      end,
      EnableKeyboard = function() end,
      SetPropagateKeyboardInput = function() end,
      SetAutoFocus = function() end,
      SetMaxLetters = function() end,
      GetText = function() return "" end,
      ClearFocus = function() end,
      SetChecked = function() end,
      GetChecked = function() return false end,
      SetCheckedTexture = function() end,
      SetOrientation = function() end,
      SetMinMaxValues = function() end,
      SetValueStep = function() end,
      SetObeyStepOnDrag = function() end,
      SetThumbTexture = function() end,
      SetValue = function() end,
      GetValue = function() return 0 end,
    }
    return f
  end

  local function buildFrame()
    _G.CreateFrame = function(_, name)
      local f = stubFrame()
      if name and name ~= "" then
        _G[name] = f
      end
      return f
    end
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    _G.SlashCmdList = {}
    _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    _G.hooksecurefunc = _G.hooksecurefunc or function() end
    _G.GetTime = _G.GetTime or function() return 0 end
    _G.PlaySound = _G.PlaySound or function() end
    _G.SOUNDKIT = _G.SOUNDKIT or { MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = _G.C_Timer or { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.GetCoinTextureString = _G.GetCoinTextureString or function(amount) return tostring(amount) .. "c" end

    local GC = {}
    local toc = assert(io.open("GoldCap/GoldCap.toc", "r"))
    local files = {}
    for rawLine in toc:lines() do
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^##") then
        files[#files + 1] = line
      end
    end
    toc:close()
    for _, rel in ipairs(files) do
      local chunk, err = loadfile("GoldCap/" .. rel:gsub("\\", "/"))
      assert(chunk, err)
      chunk("GoldCap", GC)
    end

    GC.Sniper.Toggle() -- constructs and shows the real window; frame = frame or createFrame()
    local frame = _G.GoldCapSniperFrame
    assert(frame, "GC.Sniper.Toggle() did not publish _G.GoldCapSniperFrame")
    assert.is_function(frame.autoBtn.scripts.OnClick)
    assert.is_function(frame.sellTab.scripts.OnClick)

    return frame, GC
  end

  local function teardown()
    _G.CreateFrame = nil
    _G.GoldCapSniperFrame = nil
    _G.UISpecialFrames = nil
    _G.SlashCmdList = nil
    _G.C_AddOns = nil
    _G.GoldCap_MarketData = nil
    _G.SLASH_GOLDCAP1 = nil
    _G.hooksecurefunc = nil
    _G.GetTime = nil
    _G.PlaySound = nil
    _G.SOUNDKIT = nil
    _G.C_Timer = nil
    _G.GetCoinTextureString = nil
  end

  after_each(teardown)

  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  it("re-arms the sell pause when Auto is toggled off then back on while Sell is the active view", function()
    local frame = buildFrame()
    local autoScan = upvalue(frame.autoBtn.scripts.OnClick, "autoScan")

    frame.autoBtn.scripts.OnClick() -- OFF -> IDLE: arms Auto for the first time (still on Deals)
    frame.sellTab.scripts.OnClick() -- Deals -> Sell: setView("sell") feeds pause:sell for real
    assert.is_true(autoScan:PauseReasons().sell)

    frame.autoBtn.scripts.OnClick() -- ON -> OFF: toggleOff wipes every reason
    assert.is_falsy(autoScan:PauseReasons().sell)

    frame.autoBtn.scripts.OnClick() -- OFF -> IDLE again, still on Sell: toggleOn also wipes
    -- every reason -- without the I1 fix this leaves the walk racing Auto's own browse query.
    assert.is_true(autoScan:PauseReasons().sell)
  end)

  it("does not re-arm a sell pause on the same off->on cycle while Deals is the active view", function()
    local frame = buildFrame()
    local autoScan = upvalue(frame.autoBtn.scripts.OnClick, "autoScan")

    frame.autoBtn.scripts.OnClick() -- OFF -> IDLE, still on Deals
    frame.autoBtn.scripts.OnClick() -- ON -> OFF
    frame.autoBtn.scripts.OnClick() -- OFF -> IDLE

    assert.is_falsy(autoScan:PauseReasons().sell)
  end)
end)
