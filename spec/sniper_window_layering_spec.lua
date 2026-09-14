require("spec.spec_helper")

-- The floating Sniper window was created with `CreateFrame("Frame", ..., UIParent)` and
-- nothing else: no strata, no toplevel. It therefore sat at UIParent's own level, which puts
-- it UNDER the auction house, under the bags, under essentially every Blizzard panel a
-- goldmaker has open -- and clicking it did not bring it forward, because only a toplevel
-- frame raises itself within its strata. Reported in-game 2026-08-28 as "the window is
-- always behind everything and I cannot even select it properly".
--
-- Docked inside the auction house the opposite is required: the window is a CHILD of the
-- host panel and must layer with it, or it would paint over the AH's own dropdowns and the
-- close button sitting above it.
--
-- Built against the real construction path (the whole GoldCap.toc, then GC.Sniper.Toggle),
-- following spec/sniper_panel_inset_spec.lua's recipe -- the strata calls happen inside
-- createFrame and SetDocked, neither of which is reachable as a module upvalue.
describe("Sniper window layering", function()
  -- spec/sniper_panel_inset_spec.lua's own double, with the layering calls recorded instead
  -- of discarded. A blanket "every unknown method is a no-op" metatable was tried first and
  -- is wrong for this construction path: SellFrame's layoutCells branches on `row.subItem`
  -- being nil for the header row, and a metatable that answers every field with a function
  -- makes that branch always true.
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
      Show = function(self) self.shown = true end,
      Hide = function(self) self.shown = false end,
      IsShown = function(self) return self.shown == true end,
      SetText = function() end,
      SetTexture = function() end,
      SetTextColor = function() end,
      SetJustifyH = function() end,
      -- Check panel v3: the hero caption and the reconciliation note are fixed-height wrapped
      -- blocks, so they top-align their text rather than centring it in the slot.
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
      GetFrameLevel = function(self) return self.level or 1 end,
      SetFrameLevel = function(self, level) self.level = level end,
      SetParent = function() end,
      SetColorTexture = function() end,
      SetBlendMode = function() end,
      SetTextureSliceMargins = function() end,
      SetVertexColor = function() end,
      SetAllPoints = function() end,
      SetHeight = function() end,
      SetFont = function() end,
      GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
      RegisterForClicks = function() end,
      -- Recorded, not discarded: layering IS this spec's subject.
      SetFrameStrata = function(self, strata) self.strata = strata end,
      GetFrameStrata = function(self) return self.strata or "MEDIUM" end,
      SetToplevel = function(self, on) self.toplevel = on end,
      IsMovable = function() return true end,
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
      EnableKeyboard = function(self, on) self.keyboard = on end,
      -- Recorded, not discarded: the check drawer swallows Escape and must hand every OTHER
      -- key straight back to the game (see the Escape test below).
      SetPropagateKeyboardInput = function(self, on) self.propagate = on end,
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

  local function buildFrame()
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
    _G.PlaySound = function() end
    _G.SOUNDKIT = { MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.GetCoinTextureString = function(amount) return tostring(amount) .. "c" end

    local GC = {}
    local toc = assert(io.open("GoldCap/GoldCap.toc", "r"))
    local files = {}
    for rawLine in toc:lines() do
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^##") then files[#files + 1] = line end
    end
    toc:close()
    for _, rel in ipairs(files) do
      local chunk, err = loadfile("GoldCap/" .. rel:gsub("\\", "/"))
      assert(chunk, err)
      chunk("GoldCap", GC)
    end

    GC.Sniper.Toggle()
    local frame = _G.GoldCapSniperFrame
    assert(frame, "GC.Sniper.Toggle() did not publish _G.GoldCapSniperFrame")
    return frame, GC
  end

  after_each(function()
    for _, name in ipairs({ "CreateFrame", "GoldCapSniperFrame", "UISpecialFrames", "SlashCmdList",
      "C_AddOns", "GoldCap_MarketData", "SLASH_GOLDCAP1", "SLASH_GOLDCAP2", "hooksecurefunc",
      "GetTime", "PlaySound", "SOUNDKIT", "C_Timer", "GetCoinTextureString", "GoldCapDB" }) do
      _G[name] = nil
    end
  end)

  it("floats above Blizzard's own panels", function()
    local frame = buildFrame()
    assert.equal("HIGH", frame.strata)
  end)

  it("raises itself when clicked, instead of staying wherever it was stacked", function()
    local frame = buildFrame()
    assert.is_true(frame.toplevel)
  end)

  it("layers with its host once docked, rather than painting over it", function()
    local frame, GC = buildFrame()
    local host = stubFrame()
    host:SetFrameStrata("MEDIUM")
    GC.Sniper.SetDocked(host)
    assert.equal("MEDIUM", frame.strata)
    assert.is_false(frame.toplevel)
  end)

  -- The check drawer overlays the deals list on any window narrower than WIN.PANEL_SHIFT_MIN,
  -- which the docked auction house always is, and it is an OPAQUE sheet so the rows do not
  -- ghost through. A texture cannot cross a strata boundary, so that only holds while the
  -- drawer is in a HIGHER strata than the rows -- and docking adopts the host's strata for the
  -- window, which put the two level whenever the host sat where the drawer was pinned.
  -- Reported in-game 2026-08-28 as "видишь просвечивается".
  describe("the check drawer against the list it covers", function()
    local function upvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    -- Builds the drawer AND publishes it as the module's own `dialog`, the way openDialog does
    -- on the first Buy click. SetDocked can only follow a drawer that exists; one built behind
    -- its back would make every assertion below pass for the wrong reason.
    local function drawerOf(GC)
      local clearDeals = upvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
      local refreshRows = upvalue(clearDeals, "refreshRows")
      local createRow = upvalue(refreshRows, "createRow")
      local buildRowCell = upvalue(createRow, "buildRowCell")
      local onBuyClick = upvalue(buildRowCell, "onBuyClick")
      local openDialog = upvalue(onBuyClick, "openDialog")
      local drawer = upvalue(openDialog, "createDialog")()
      -- Upvalues from one enclosing scope are shared, so setting it through this closure sets
      -- the same `dialog` every other function in the file reads.
      for i = 1, math.huge do
        local name = debug.getupvalue(openDialog, i)
        if not name then error("missing upvalue dialog") end
        if name == "dialog" then debug.setupvalue(openDialog, i, drawer) break end
      end
      return drawer
    end

    it("sits one strata above the window, whatever strata that is", function()
      local frame, GC = buildFrame()
      local drawer = drawerOf(GC)
      assert.equal("HIGH", frame.strata)
      assert.equal("DIALOG", drawer.strata)

      -- The case that broke it: a host already in the drawer's own strata.
      local host = stubFrame()
      host:SetFrameStrata("DIALOG")
      GC.Sniper.SetDocked(host)
      assert.equal("DIALOG", frame.strata)
      assert.not_equal(frame.strata, drawer.strata)
      assert.equal("FULLSCREEN", drawer.strata)
    end)

    it("never climbs over a tooltip, however high the host is", function()
      local _, GC = buildFrame()
      local drawer = drawerOf(GC)
      local host = stubFrame()
      host:SetFrameStrata("FULLSCREEN_DIALOG")
      GC.Sniper.SetDocked(host)
      assert.equal("FULLSCREEN_DIALOG", drawer.strata)
    end)

    -- Belt and braces for the same failure: should the two ever land in one strata anyway,
    -- the level has to decide, and a scroll child must not be able to out-level the sheet.
    it("also out-levels the window it is anchored to", function()
      local frame, GC = buildFrame()
      local drawer = drawerOf(GC)
      assert.is_true((drawer.level or 0) > (frame.level or 1))
    end)

    it("follows the window back down when the auction house closes", function()
      local _, GC = buildFrame()
      local drawer = drawerOf(GC)
      local host = stubFrame()
      host:SetFrameStrata("DIALOG")
      GC.Sniper.SetDocked(host)
      GC.Sniper.SetDocked(nil)
      assert.equal("DIALOG", drawer.strata)
    end)

    -- One Escape, one thing closed. The drawer was registered in UISpecialFrames alongside the
    -- window itself, and CloseSpecialWindows hides EVERY shown entry it holds -- so backing out
    -- of a check also shut the whole GoldCap window behind it and, docked, handed the auction
    -- house back to Blizzard's own tab. It captures the key itself now, the same way the
    -- settings overlay does.
    it("takes Escape for itself instead of closing the window behind it", function()
      local frame, GC = buildFrame()
      local drawer = drawerOf(GC)
      for _, name in ipairs(_G.UISpecialFrames) do
        assert.not_equal("GoldCapSniperConfirm", name)
      end
      assert.is_function(drawer.scripts.OnKeyDown)

      drawer:Show()
      frame:Show()
      drawer.scripts.OnKeyDown(drawer, "ESCAPE")

      assert.is_false(drawer:IsShown())
      assert.is_true(frame:IsShown()) -- the window it covers stays exactly where it was
      assert.is_false(drawer.propagate) -- and the game never sees that keypress

      -- Every other key still reaches whatever would normally receive it -- movement, action
      -- bars, Enter-to-chat. EnableKeyboard(true) delivers them all here, not just Escape.
      drawer.scripts.OnKeyDown(drawer, "W")
      assert.is_true(drawer.propagate)
    end)
  end)

  -- The Settings screen is an OVERLAY on the window's own content -- an opaque Theme.Panel
  -- drawn over the deals/sell/sold list, never a second floating window. It shipped pinned to
  -- SetFrameStrata("HIGH"), which sat above the list for exactly as long as the WINDOW did not
  -- also declare HIGH. The moment createFrame started (above), the overlay landed in its own
  -- parent's strata -- and SetFrameStrata reassigns the level within the strata it moves to, so
  -- the overlay came out UNDER the scroll rows it exists to cover. Reported in-game 2026-08-28
  -- with a screenshot of the Sold list reading straight through the settings cards.
  --
  -- The strata is not the overlay's to pick anyway: docking adopts the auction house's for the
  -- whole window (SetDocked above), and an overlay pinned one strata higher would paint over the
  -- host's dropdowns exactly the way the window itself must not. So it stays in its parent's
  -- strata and wins on LEVEL, which is what decides inside one strata.
  describe("the settings overlay against the list it covers", function()
    -- The panel is a file-local in UI/SettingsFrame.lua, built lazily on the first gear click
    -- and never published on a frame or on GC -- the same upvalue reach the check drawer needs
    -- above, one hop shorter because Toggle() itself closes over it.
    local function settingsPanel(GC)
      GC.SettingsUI.Toggle() -- builds it (first call) and shows it, exactly as the gear does
      for i = 1, math.huge do
        local name, value = debug.getupvalue(GC.SettingsUI.Toggle, i)
        if not name then break end
        if name == "panel" then return assert(value, "GC.SettingsUI.Toggle() built no panel") end
      end
      error("missing upvalue panel")
    end

    it("keeps its parent's strata rather than pinning one that can fall level with it", function()
      local frame, GC = buildFrame()
      local panel = settingsPanel(GC)
      assert.equal("HIGH", frame.strata)
      assert.is_nil(panel.strata)
    end)

    it("out-levels the window whose content it covers", function()
      local frame, GC = buildFrame()
      local panel = settingsPanel(GC)
      assert.is_true((panel.level or 0) > (frame.level or 1))
    end)

    -- Docking changes the window's strata, and the engine reassigns levels when it does -- so
    -- an overlay that only chose its level once, at build time, is back under the rows the
    -- first time the auction house opens with Settings already showing.
    it("re-derives its level when docking moves the window", function()
      local frame, GC = buildFrame()
      local panel = settingsPanel(GC)
      local host = stubFrame()
      host:SetFrameStrata("DIALOG")
      frame:SetFrameLevel(7)
      panel:SetFrameLevel(0) -- whatever the engine reassigned it to under the new strata
      GC.Sniper.SetDocked(host)
      assert.is_true((panel.level or 0) > 7)
    end)

    it("follows the window back down when the auction house closes", function()
      local frame, GC = buildFrame()
      local panel = settingsPanel(GC)
      local host = stubFrame()
      host:SetFrameStrata("DIALOG")
      GC.Sniper.SetDocked(host)
      frame:SetFrameLevel(3)
      panel:SetFrameLevel(0)
      GC.Sniper.SetDocked(nil)
      assert.is_true((panel.level or 0) > 3)
    end)
  end)

  it("goes back to floating above everything when the auction house closes", function()
    local frame, GC = buildFrame()
    local host = stubFrame()
    host:SetFrameStrata("MEDIUM")
    GC.Sniper.SetDocked(host)
    GC.Sniper.SetDocked(nil)
    assert.equal("HIGH", frame.strata)
    assert.is_true(frame.toplevel)
  end)
end)
