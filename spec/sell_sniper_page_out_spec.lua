local helper = require("spec.spec_helper") -- luacheck: ignore helper

-- A Deals page still on the wire when the player switches to Sell. The switch aborts the pass
-- (a manual scan through abortFullScan, an Auto one through pause:sell), and the book pass stops
-- "paging" at once -- but the page it sent just before is still out, and a shared-code error
-- ("The Auction House is busy.") that lands next may be that page's answer, not the post's.
-- GC.Sell._OtherRequestOut must count it (review NM-C: it asked GC.Sniper.IsBusy, which reads
-- the pass's paging, so it could never fire in play). Driven through the real addon: the whole
-- GoldCap.toc against a rigged CreateFrame, a real Sniper window, its real Sell rail button.
describe("Sell tab, a Deals page still out after the switch", function()
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


  local browseSent

  local function buildFrame()
    browseSent = 0
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
    _G.time = function() return 1000 end
    _G.PlaySound = function() end
    _G.SOUNDKIT = { MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.GetCoinTextureString = function(amount) return tostring(amount) .. "c" end
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() browseSent = browseSent + 1 end,
      RequestMoreBrowseResults = function() browseSent = browseSent + 1 end,
      HasFullBrowseResults = function() return false end,
      GetBrowseResults = function() return {} end,
    }

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
    _G.CreateFrame, _G.GoldCapSniperFrame, _G.UISpecialFrames, _G.SlashCmdList = nil, nil, nil, nil
    _G.C_AddOns, _G.GoldCap_MarketData, _G.SLASH_GOLDCAP1, _G.hooksecurefunc = nil, nil, nil, nil
    _G.GetTime, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.C_AuctionHouse, _G.time = nil, nil, os.time
  end)

  -- A manual scan's first page, sent by the real arbiter through the real book pass.
  local function pageOut(frame, GC)
    frame.dealsTab.scripts.OnClick()
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper.OnThrottleReady()
    assert.equal(1, browseSent)
    frame.sellTab.scripts.OnClick() -- the real switch: the pass is aborted
    assert.is_false(GC.Sniper._bookPass:IsPaging())
  end

  it("counts the page as a request of ours until it lands", function()
    local frame, GC = buildFrame()
    pageOut(frame, GC)
    assert.is_true(GC.Sell._OtherRequestOut())
    GC.Sniper.OnBrowseResults() -- its answer, ignored by the aborted pass
    assert.is_false(GC.Sell._OtherRequestOut())
  end)

  it("stops counting a page nothing ever answered, after the scan's own stall time", function()
    local frame, GC = buildFrame()
    pageOut(frame, GC)
    _G.time = function() return 1000 + 16 end
    assert.is_false(GC.Sell._OtherRequestOut())
  end)

  it("forgets it when the auction house closes", function()
    local frame, GC = buildFrame()
    pageOut(frame, GC)
    GC.Sniper.OnAuctionHouseClosed()
    assert.is_false(GC.Sell._OtherRequestOut())
  end)
end)
