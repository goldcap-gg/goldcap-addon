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
