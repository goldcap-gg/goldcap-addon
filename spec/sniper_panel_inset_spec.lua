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

  local function getUpvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  -- Copied from spec/loadorder_spec.lua's own stubFrame(): every widget method createFrame's
  -- real construction path touches, from Theme.Card/TitleBar/Rail/Button down to GC.Sell.Attach
  -- and GC.Sold.Attach. Kept as a per-spec double (the addon's engineering notes: "when a widget starts
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
      SetTexCoord = function() end,
      SetGradient = function() end,
      SetTextColor = function() end,
      SetJustifyH = function() end,
      -- Check panel v3: the hero caption and the reconciliation note are fixed-height
      -- wrapped blocks, so they top-align their text rather than centring it in the slot.
      SetJustifyV = function() end,
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
      -- The dialog's Reason row wraps, and layoutBlocks sizes the transcript off its height.
      GetStringHeight = function() return 0 end,
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
      SetPushedTexture = function() end,
      SetFrameStrata = function() end,
      -- The window declares its own layering (SniperFrame's createFrame/SetDocked):
      -- HIGH + toplevel while floating, the host's strata while docked.
      SetToplevel = function() end,
      GetFrameStrata = function() return "MEDIUM" end,
      GetWidth = function() return 0 end,
      HookScript = function() end,
      SetParent = function() end,
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
      SetNumeric = function() end,
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
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
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
      if line ~= "" and not line:match("^#") then
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
    _G.CreateFrame, _G.CreateColor = nil, nil
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
  it("shifts the deals list left by DG.WIDTH + Theme.pad.m when open on a wide window", function()
    local frame = buildFrame()
    frame.GetWidth = function() return 1000 end

    frame.applyPanelInset(true)

    assert.are.equal(-364, lastOffsetX(frame.scroll, "BOTTOMRIGHT"))
    assert.are.equal(-364, lastOffsetX(frame.headerRow, "TOPRIGHT"))
    assert.are.equal(-364, lastOffsetX(frame.verifyBtn, "TOPRIGHT"))
    assert.are.equal(332, frame.panelInset)
  end)

  -- The panel used to lie over the list on any window under 990px -- the docked auction house
  -- always -- and covered its price column (owner, 2026-11-21). It shifts the list at every
  -- width now; the list drops columns instead (computeHidden).
  for _, width in ipairs({ 640, 800, 989, 990 }) do
    it(("shifts the deals list on a %dpx window too"):format(width), function()
      local frame = buildFrame()
      frame.GetWidth = function() return width end

      frame.applyPanelInset(true)

      assert.are.equal(-364, lastOffsetX(frame.scroll, "BOTTOMRIGHT"))
      assert.are.equal(-364, lastOffsetX(frame.headerRow, "TOPRIGHT"))
      assert.are.equal(332, frame.panelInset)
    end)
  end

  -- What the docked window keeps beside an open panel: the item, the price, the profit and Buy.
  -- The discount and the verdict word go first; Buy never does, the row's click acts through it.
  it("drops the discount and the verdict column for an open panel on a narrow window, never Buy", function()
    local function upvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then return nil end
        if name == wanted then return value end
      end
    end
    local frame = buildFrame()
    local apply = upvalue(frame.applyPanelInset, "applyColumnVisibility")
    local function hidden() return upvalue(apply, "hiddenColumns") end
    frame.GetWidth = function() return 800 end
    frame.applyPanelInset(true)
    assert.is_true(hidden().disc)
    assert.is_true(hidden().tier)
    assert.is_nil(hidden().profit)
    assert.is_nil(hidden().buy)

    frame.applyPanelInset(false)
    assert.is_nil(hidden().disc)
    assert.is_nil(hidden().tier)
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

  -- The check panel as UI/SniperInspector.lua draws it (owner, 2026-11-21): the hero, the
  -- cheapest listings and the three tiles, head to tail, and nothing else -- the four facts, the
  -- reconciliation, the quantity block and the Details transcript are not stacked (the footer's
  -- stepper is the quantity now). This drives the REAL createDialog and reads back where each
  -- block landed.
  describe("Check panel block stack (real createDialog)", function()
    local function realDialog(saved)
      local _, GC = buildFrame()
      GC.db = { settings = { sniper = { dialogDetailsOpen = saved } } }
      local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
      local refreshRows = getUpvalue(clearDeals, "refreshRows")
      local createRow = getUpvalue(refreshRows, "createRow")
      local buildRowCell = getUpvalue(createRow, "buildRowCell")
      local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
      local openDialog = getUpvalue(onBuyClick, "openDialog")
      return getUpvalue(openDialog, "createDialog")()
    end

    local function watch(block)
      local rec = {}
      block.ClearAllPoints = function() end
      block.SetPoint = function(_, point, _, _, _, y)
        if point == "TOPLEFT" then rec.top = y end
      end
      block.SetHeight = function(_, h) rec.height = h end
      block.Show = function() rec.shown = true end
      block.Hide = function() rec.shown = false end
      return rec
    end

    local function watchAll(d)
      return {
        hero = watch(d.heroBlock), reconcile = watch(d.reconcileBlock), qty = watch(d.qtyBlock),
        facts = watch(d.factsBlock), grid = watch(d.gridBlock), toggle = watch(d.detailsToggle),
        ladder = watch(d.ladderBlock), tiles = watch(d.tilesBlock),
      }
    end

    it("stacks the hero, the cheapest listings and the tiles head to tail, and nothing else", function()
      for _, saved in ipairs({ false, true }) do
        local d = realDialog(saved)
        local rec = watchAll(d)
        d.inspect = { heroH = 90, ladderH = 110, tilesH = 50 }
        d.layoutBlocks({ reconcile = true, actionable = true })

        assert.equal(-d.headerH, rec.hero.top)
        assert.equal(90, rec.hero.height)
        assert.equal(rec.hero.top - rec.hero.height, rec.ladder.top)
        assert.equal(rec.ladder.top - rec.ladder.height, rec.tiles.top)
        for _, gone in ipairs({ "reconcile", "qty", "facts", "grid", "toggle" }) do
          assert.is_false(rec[gone].shown, gone)
        end
        assert.equal(rec.tiles.top - 50 - 4, d.evidenceTop)
      end
    end)

    it("leaves out a ladder with no book and tiles with no figure, without a hole", function()
      local d = realDialog(false)
      local rec = watchAll(d)
      d.inspect = { heroH = 70 }
      d.layoutBlocks({ actionable = false })
      assert.is_false(rec.ladder.shown)
      assert.is_false(rec.tiles.shown)
      assert.equal(rec.hero.top - rec.hero.height - 4, d.evidenceTop)
    end)

    it("fits the docked drawer with a full ladder, the tiles and the buy footer", function()
      local d = realDialog(false)
      watchAll(d)
      local DG = getUpvalue(getUpvalue(d.applyDetailsState, "layoutBlocks"), "DG")
      -- A three-line sentence, five levels and the limit line, the tiles.
      d.inspect = { heroH = 8 + 12 + 4 + 28 + 4 + 42 + 8, ladderH = 8 + 16 + 5 * 16 + 16 + 4, tilesH = 8 + 40 + 4 }
      d.layoutBlocks({ actionable = true })
      local DOCKED_CEILING = 565 - 32 -- under the title bar
      assert.is_true(d.fixedHeight + 4 + 46 <= DOCKED_CEILING,
        ("the panel needs %d of %d"):format(d.fixedHeight + 50, DOCKED_CEILING)) -- with the banner slot
      assert.equal(102, d.footerH)
      assert.equal(78, DG.CONTROLS_H) -- the panel without UI/SniperInspector.lua keeps its own
    end)
  end)

  -- Item 10 (addon polish batch): the F5 guard itself (openDialog's own createDialog closure,
  -- ~4658-4715) only had SOURCE-TEXT coverage before this (sniper_dialog_verdict_spec.lua's
  -- "Details toggle wiring (source)" describe) -- nothing actually drove a real dialog short
  -- enough to trip it. createDialog() needs no purchase-flow plumbing (dialog stays the nil
  -- module upvalue throughout, since this never goes through openDialog), so it is called
  -- directly here, the same "real construction, not a synthetic double" approach as
  -- applyPanelInset above.
  describe("Evidence-grid F5 guard (real createDialog)", function()
    it("closes the grid on a real dialog too short for it, even with a saved 'open' preference", function()
      local _, GC = buildFrame()
      GC.db = { settings = { sniper = { dialogDetailsOpen = true } } }

      local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
      local refreshRows = getUpvalue(clearDeals, "refreshRows")
      local createRow = getUpvalue(refreshRows, "createRow")
      local buildRowCell = getUpvalue(createRow, "buildRowCell")
      local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
      local openDialog = getUpvalue(onBuyClick, "openDialog")
      local createDialog = getUpvalue(openDialog, "createDialog")

      local d = createDialog()
      assert.is_true(d.detailsOpen) -- construction seed: fits at its own just-set height

      -- Simulate a real narrow/short window: GetHeight now comes back too small for
      -- DG.FIXED_HEIGHT_OPEN, the way a drag-resize genuinely shrinks the dialog.
      d.GetHeight = function() return 100 end
      d.applyDetailsState(true)

      assert.is_false(d.detailsOpen)
    end)

    -- Counterpart: proves the guard is genuinely height-gated, not just "any re-apply closes
    -- it" -- without this, the test above could pass for the wrong reason.
    it("keeps the grid open on a re-apply when the dialog is tall enough for it", function()
      local _, GC = buildFrame()
      GC.db = { settings = { sniper = { dialogDetailsOpen = true } } }

      local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
      local refreshRows = getUpvalue(clearDeals, "refreshRows")
      local createRow = getUpvalue(refreshRows, "createRow")
      local buildRowCell = getUpvalue(createRow, "buildRowCell")
      local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
      local openDialog = getUpvalue(onBuyClick, "openDialog")
      local createDialog = getUpvalue(openDialog, "createDialog")

      local d = createDialog()
      d.GetHeight = function() return 10000 end
      d.applyDetailsState(true)

      assert.is_true(d.detailsOpen)
    end)
  end)
end)
