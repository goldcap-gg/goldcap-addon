require("spec.spec_helper")

-- Task 1 (check panel + deals list, addon-rail-kit): applyPanelInset owns every right-edge
-- anchor the check panel's 320px sheet (DG.WIDTH) can push aside -- the scroll's BOTTOMRIGHT,
-- the header row's TOPRIGHT, verifyBtn's TOPRIGHT -- so this must be driven against a REAL
-- createFrame() construction, not a synthetic double standing in for applyPanelInset itself:
-- it is a `local function` closed over inside createFrame's own body (never a module upvalue
-- reachable via debug.getupvalue the way setView/refreshSessionText are in
-- spec/toolbar_chrome_spec.lua), and the only handle on it the rest of the file gets is the
-- `f.applyPanelInset` field stamped on the real frame. So this spec follows
-- spec/loadorder_spec.lua's own recipe -- the full GoldCap.toc load order against a fully
-- rigged CreateFrame stub, then a real GC.Sniper.Toggle() -- to get a real `frame` back and
-- calls `frame.applyPanelInset` on it directly, the same way createDialog's OnShow/OnHide
-- closures do.
describe("Sniper check panel inset (applyPanelInset)", function()
  -- Same setupvalue idiom as spec/sniper_dialog_verdict_spec.lua and
  -- spec/sniper_purchase_wiring_spec.lua: `dialog` is a module-level local shared by every
  -- function SniperFrame.lua defines, so setting it via one closure's upvalue slot (here,
  -- the real OnSizeChanged handler captured off `frame.scripts`) is visible to every other
  -- function that reads it.
  local function setUpvalue(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  -- Copied from spec/loadorder_spec.lua's own stubFrame(): every widget method createFrame's
  -- real construction path touches, from Theme.Card/TitleBar/Rail/Button down to GC.Sell.Attach
  -- and GC.Sold.Attach. Kept as a per-spec double (addon/AGENTS.md: "when a widget starts
  -- calling a new method... the fake regions need it too") rather than shared, since a change to
  -- either spec's construction needs should not silently perturb the other's.
  local function stubFrame()
    local f
    f = {
      RegisterEvent = function() end,
      UnregisterEvent = function() end,
      -- Records every handler by name (fix wave addition) so a spec can fire the real
      -- OnSizeChanged closure createFrame installs on `f`, the same "scripts" idiom
      -- spec/sell_widget_behavior_spec.lua's stub already uses.
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

  -- Records the last SetPoint call made for each anchor point name (e.g. "BOTTOMRIGHT"), so an
  -- assertion can read back applyPanelInset's live re-anchor rather than a snapshot taken at
  -- construction time. Works for both the 4-offset form (point, relativeTo, relativePoint, x, y)
  -- scroll/headerRow use and the 2-offset shorthand (point, x, y) the brief's verifyBtn anchor
  -- uses: the x/y offsets are always the last two varargs regardless of which form was called.
  local function withPointRecorder(widget)
    widget.pointCalls = {}
    widget.SetPoint = function(_, point, ...)
      widget.pointCalls[point] = { ... }
    end
    return widget
  end

  local function lastOffsetX(widget, point)
    local args = widget.pointCalls[point]
    assert(args, "no SetPoint call recorded for " .. point)
    return args[#args - 1]
  end

  -- Builds a real GoldCap addon table via the exact same load-order recipe
  -- spec/loadorder_spec.lua uses, then constructs the real Sniper window through
  -- GC.Sniper.Toggle() (which does `frame = frame or createFrame()`), and hands back that real
  -- frame with point-recorders wired onto the three widgets applyPanelInset re-anchors.
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
    assert.is_function(frame.applyPanelInset)

    withPointRecorder(frame.scroll)
    withPointRecorder(frame.headerRow)
    withPointRecorder(frame.verifyBtn)

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

  -- 320 (DG.WIDTH) + 12 (Theme.pad.m) = 332 pushed past the 32px scrollbar gutter
  -- (WIN.CONTENT_RIGHT_GUTTER) already reserved -- -(32 + 332) = -364.
  it("shifts the deals list left by DG.WIDTH + Theme.pad.m when open on a >=990 window", function()
    local frame = buildFrame()
    frame.GetWidth = function() return 1000 end

    frame.applyPanelInset(true)

    assert.are.equal(-364, lastOffsetX(frame.scroll, "BOTTOMRIGHT"))
    assert.are.equal(-364, lastOffsetX(frame.headerRow, "TOPRIGHT"))
    assert.are.equal(-364, lastOffsetX(frame.verifyBtn, "TOPRIGHT"))
    assert.are.equal(332, frame.panelInset)
  end)

  -- Below WIN.PANEL_SHIFT_MIN (990) the panel overlays instead of shifting: docked mode (the
  -- in-game AH host) is 792 wide and must keep the plain -32 gutter anchor.
  it("keeps the plain gutter anchor when open but narrower than WIN.PANEL_SHIFT_MIN", function()
    local frame = buildFrame()
    frame.GetWidth = function() return 800 end

    frame.applyPanelInset(true)

    assert.are.equal(-32, lastOffsetX(frame.scroll, "BOTTOMRIGHT"))
    assert.are.equal(-32, lastOffsetX(frame.headerRow, "TOPRIGHT"))
    assert.are.equal(-32, lastOffsetX(frame.verifyBtn, "TOPRIGHT"))
    assert.are.equal(0, frame.panelInset)
  end)

  -- Fix 3 (check-panel-deals-list, task 4): WIN.PANEL_SHIFT_MIN moved from 900 to 990 -- at 900
  -- the item column landed at 92px, well under its own declared min (180). 990 is derived so
  -- that even with BOTH optional columns dropped, the item column still clears 180: 88
  -- (CONTENT_LEFT) + 32 (GUTTER) + 332 (inset) + 356 (fixed columns) + 180 (item min) = 988,
  -- rounded up. These three widths pin the boundary exactly on either side of that floor.
  it("keeps the plain gutter anchor at 989, one pixel short of WIN.PANEL_SHIFT_MIN", function()
    local frame = buildFrame()
    frame.GetWidth = function() return 989 end

    frame.applyPanelInset(true)

    assert.are.equal(-32, lastOffsetX(frame.scroll, "BOTTOMRIGHT"))
    assert.are.equal(0, frame.panelInset)
  end)

  it("shifts the deals list at exactly WIN.PANEL_SHIFT_MIN (990)", function()
    local frame = buildFrame()
    frame.GetWidth = function() return 990 end

    frame.applyPanelInset(true)

    assert.are.equal(-364, lastOffsetX(frame.scroll, "BOTTOMRIGHT"))
    assert.are.equal(332, frame.panelInset)
  end)

  it("keeps shifting the deals list one pixel past WIN.PANEL_SHIFT_MIN (991)", function()
    local frame = buildFrame()
    frame.GetWidth = function() return 991 end

    frame.applyPanelInset(true)

    assert.are.equal(-364, lastOffsetX(frame.scroll, "BOTTOMRIGHT"))
    assert.are.equal(332, frame.panelInset)
  end)

  it("resets to the plain gutter anchor once the panel closes, even on a wide window", function()
    local frame = buildFrame()
    frame.GetWidth = function() return 1000 end
    frame.applyPanelInset(true)
    assert.are.equal(-364, lastOffsetX(frame.scroll, "BOTTOMRIGHT"))

    frame.applyPanelInset(false)

    assert.are.equal(-32, lastOffsetX(frame.scroll, "BOTTOMRIGHT"))
    assert.are.equal(-32, lastOffsetX(frame.headerRow, "TOPRIGHT"))
    assert.are.equal(-32, lastOffsetX(frame.verifyBtn, "TOPRIGHT"))
    assert.are.equal(0, frame.panelInset)
  end)

  -- Item 8 (addon polish batch): Settings moved to rail.gear when the nav rail replaced the tab
  -- row -- titleBar.gear is hidden immediately after (createFrame's own comment: "TitleBar
  -- still builds its gear for other callers, this window just doesn't show two of them"), so
  -- f.gearBtn pointing at it was a hidden, unwired control -- a trap for future code that reads
  -- it expecting a live Settings button.
  it("points gearBtn at the live rail gear, not the hidden title-bar one", function()
    local frame = buildFrame()
    assert.is_truthy(frame.rail and frame.rail.gear)
    assert.equal(frame.rail.gear, frame.gearBtn)
  end)

  -- Fix wave (check panel v2 review): an open evidence grid painted its rows straight over
  -- BUY/CANCEL when the window shrank to the 470 floor (no SetClipsChildren anywhere), and
  -- enlarging again after the F5 refusal needed a manual toggle click. createFrame's own
  -- OnSizeChanged now re-applies the SAVED preference (not the live flag) on every resize, so a
  -- downsize closes the grid without eating the player's "open" and an upsize reopens it.
  describe("re-applying the saved details preference on resize", function()
    -- dialog is a plain double here, not a real createDialog() product (see this file's own
    -- header comment on why createDialog's real widget tree stays out of this suite) --
    -- applyDetailsState is a bare recorder so the assertions are about what OnSizeChanged
    -- calls it WITH, not about applyDetailsState's own internals (covered separately by
    -- spec/sniper_dialog_verdict_spec.lua's source-text pins).
    local function fakeDialog()
      local d = { IsShown = function() return false end }
      d.applyDetailsState = function(open)
        d.lastOpen = open
        d.quietDuringCall = d.detailsQuiet
      end
      return d
    end

    it("calls dialog.applyDetailsState with the saved cfg value, quietly, and clears the flag after", function()
      local frame, GC = buildFrame()
      GC.db = { settings = { sniper = { dialogDetailsOpen = true } } }
      local d = fakeDialog()
      assert.is_function(frame.scripts.OnSizeChanged)
      setUpvalue(frame.scripts.OnSizeChanged, "dialog", d)
      frame.GetWidth = function() return 1000 end

      frame.scripts.OnSizeChanged(frame, 1000)

      assert.is_true(d.lastOpen) -- the SAVED preference, not a live flag this test never set
      assert.is_true(d.quietDuringCall) -- no status spam while the resize re-apply is in flight
      assert.is_nil(d.detailsQuiet) -- cleared once the re-apply finishes
    end)

    it("passes a closed preference through just as faithfully", function()
      local frame, GC = buildFrame()
      GC.db = { settings = { sniper = { dialogDetailsOpen = false } } }
      local d = fakeDialog()
      setUpvalue(frame.scripts.OnSizeChanged, "dialog", d)
      frame.GetWidth = function() return 1000 end

      frame.scripts.OnSizeChanged(frame, 1000)

      assert.is_false(d.lastOpen)
      assert.is_nil(d.detailsQuiet)
    end)

    it("does nothing when the dialog has never been opened (no applyDetailsState field yet)", function()
      local frame = buildFrame()
      setUpvalue(frame.scripts.OnSizeChanged, "dialog", nil)
      frame.GetWidth = function() return 1000 end

      -- Must not error just because no dialog has ever been constructed.
      frame.scripts.OnSizeChanged(frame, 1000)
    end)
  end)
end)
