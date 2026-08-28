require("spec.spec_helper")

-- The Deals column headings (ITEM / TIER / DISC / UNIT / PRICE / PROFIT / TREND) were not
-- drawn at all in-game: the hairline under them was there, the cells were still live -- a
-- hover over DISC raised its tooltip -- and the labels themselves were blank space. Reported
-- 2026-08-28 with a screenshot of the band between the toolbar and the first deal row.
--
-- Every OTHER single-line cell in the kit is built with word wrap off and a one-line cap:
-- the deals ROW cells (buildRowCell), the Sold headings (UI/SoldFrame.lua) and the Sell
-- headings (UI/SellFrame.lua). The Deals headings were the one place that left the default
-- on -- and they are also the one place whose FontString is SetAllPoints() onto a cell that
-- is only CH.HEADER (16px) tall, so a wrapped line that does not fit that height is simply
-- not drawn rather than clipped.
--
-- What this spec can prove is the shape, not the pixels: busted has no font engine, so it
-- guards that every heading is built the way every other single-line cell in the addon is,
-- which is what went missing. The rendering itself is the in-game pass.
describe("Sniper deals column headings", function()
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
      SetText = function(self, text) self.text = text end,
      SetTexture = function() end,
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
      SetWordWrap = function(self, on) self.wordWrap = on end,
      SetMaxLines = function(self, lines) self.maxLines = lines end,
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

    return frame, GC
  end

  after_each(function()
    for _, name in ipairs({ "CreateFrame", "GoldCapSniperFrame", "UISpecialFrames", "SlashCmdList",
      "C_AddOns", "GoldCap_MarketData", "SLASH_GOLDCAP1", "SLASH_GOLDCAP2", "hooksecurefunc",
      "GetTime", "PlaySound", "SOUNDKIT", "C_Timer", "GetCoinTextureString", "GoldCapDB" }) do
      _G[name] = nil
    end
  end)

  -- ITEM is not in header.cells: the flex column has no themed cell of its own, so
  -- createHeaderRow builds it as its own hit frame beside them. It went blank with the rest,
  -- so it is asserted with the rest.
  local function everyLabel(frame)
    local labels = { frame.headerRow.itemCell.label }
    for key, cell in pairs(frame.headerRow.cells) do
      labels[#labels + 1] = cell.label
      assert.is_not_nil(cell.label, key .. " heading has no label")
    end
    return labels
  end

  it("names every column it draws", function()
    local frame = buildFrame()
    local seen = {}
    for key, cell in pairs(frame.headerRow.cells) do seen[key] = cell.label.text end
    assert.equal("ITEM", frame.headerRow.itemCell.label.text)
    assert.equal("TIER", seen.tier)
    assert.equal("DISC", seen.disc)
    assert.equal("UNIT", seen.unit)
    assert.equal("PRICE", seen.total)
    assert.equal("PROFIT", seen.profit)
    assert.equal("TREND", seen.trend)
    assert.equal("", seen.buy) -- the action column is deliberately unlabelled
  end)

  it("draws each heading as one non-wrapping line, like every other cell in the kit", function()
    local frame = buildFrame()
    for _, label in ipairs(everyLabel(frame)) do
      assert.is_false(label.wordWrap)
      assert.equal(1, label.maxLines)
    end
  end)
end)
