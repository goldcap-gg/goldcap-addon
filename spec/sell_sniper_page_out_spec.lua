local helper = require("spec.spec_helper") -- luacheck: ignore helper

-- A Deals page still on the wire when the player switches to Sell. The switch aborts the pass
-- (a manual scan through abortFullScan, an Auto one through pause:sell), and the book pass stops
-- "paging" at once -- but the page it sent just before is still out, and a shared-code error
-- ("The Auction House is busy.") that lands next may be that page's answer, not the post's.
-- GC.Sell._OtherRequestOut must count it (review NM-C: it asked GC.Sniper.IsBusy, which reads
-- the pass's paging, so it could never fire in play). Driven through the real addon: the whole
-- GoldCap.toc against a rigged CreateFrame, a real Sniper window, its real Sell rail button.
describe("Sell tab, a Sniper request still out after the switch", function()
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


  local browseSent, searches, madeEnum

  local function buildFrame()
    browseSent, searches = 0, {}
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
      MakeItemKey = function(itemID) return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
      SendSearchQuery = function(key) searches[#searches + 1] = key end,
      -- The answers, empty: nothing listed.
      GetNumCommoditySearchResults = function() return 0 end,
      GetCommoditySearchResultInfo = function() return nil end,
      HasFullCommoditySearchResults = function() return true end,
      GetNumItemSearchResults = function() return 0 end,
      GetItemSearchResultInfo = function() return nil end,
      HasFullItemSearchResults = function() return true end,
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
    if madeEnum then _G.Enum, madeEnum = nil, nil elseif _G.Enum then _G.Enum.AuctionHouseSortOrder = nil end
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

  -- Final money review M2: a confirm either window stopped waiting on can still answer -- its
  -- stranded record says so for as long as it is kept -- and a late shared error from it (no gold)
  -- must not be read as the post's own refusal and free the row for a second press.
  it("counts a confirm the Sniper stopped waiting on, for as long as it can still answer", function()
    local _, GC = buildFrame()
    assert.is_false(GC.Sell._OtherRequestOut())
    GC.Sniper._strandedConfirmed[42] = { pending = { itemID = 42 }, at = GetTime() }
    assert.is_true(GC.Sell._OtherRequestOut())
    local at = GetTime()
    _G.GetTime = function() return at + 601 end
    assert.is_false(GC.Sell._OtherRequestOut())
  end)

  it("counts a confirm the BUY tab stopped waiting on, for as long as it can still answer", function()
    local _, GC = buildFrame()
    local function up(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end
    local session = up(up(GC.Buy.HasStranded, "liveStranded"), "sessionToken")
    GC.Buy._stranded[101] = { qty = 1, total = 100, at = time(), session = session }
    assert.is_true(GC.Sell._OtherRequestOut())
    GC.Buy._stranded[101].session = session - 1 -- a session that can no longer answer
    assert.is_false(GC.Sell._OtherRequestOut())
  end)

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

  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value, i end
    end
    error("missing upvalue " .. wanted)
  end

  -- A hover pre-warm on the Deals board, sent through the real maybeStartPrewarm and the real
  -- search driver, then the switch (review NM-F: an item search out was invisible to the Sell
  -- tab once the Sniper's quiet zone closed).
  local function searchOut(frame, GC, isCommodity)
    frame.dealsTab.scripts.OnClick()
    _G.C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = isCommodity } end
    if not _G.Enum then _G.Enum, madeEnum = {}, true end
    _G.Enum.AuctionHouseSortOrder = { Buyout = 4 }
    local prewarm = upvalue(GC.Sniper.OnThrottleReady, "maybeStartPrewarm")
    local _, index = upvalue(prewarm, "ahOpen")
    debug.setupvalue(prewarm, index, true)
    assert.is_true(GC.Sniper._HoverPrewarm({ deal = { itemID = 42, unitPrice = 90, stale = true } }))
    assert.equal(1, #searches)
    frame.sellTab.scripts.OnClick()
  end

  it("counts a commodity search as a request of ours until its answer lands", function()
    local frame, GC = buildFrame()
    searchOut(frame, GC, true)
    assert.is_true(GC.Sell._OtherRequestOut())
    GC.Sniper.OnCommoditySearchResults(42)
    assert.is_false(GC.Sell._OtherRequestOut())
  end)

  it("counts an item search until the answer for its own key lands", function()
    local frame, GC = buildFrame()
    searchOut(frame, GC, false)
    assert.is_true(GC.Sell._OtherRequestOut())
    GC.Sniper.OnItemSearchResults(42, { itemID = 42, itemLevel = 619, itemSuffix = 0, battlePetSpeciesID = 0 })
    assert.is_true(GC.Sell._OtherRequestOut()) -- another key's answer: somebody else's search
    GC.Sniper.OnItemSearchResults(42, searches[1])
    assert.is_false(GC.Sell._OtherRequestOut())
  end)

  it("stops counting a search nothing answered, after the Check's own timeout", function()
    local frame, GC = buildFrame()
    searchOut(frame, GC, true)
    _G.time = function() return 1000 + 9 end
    assert.is_false(GC.Sell._OtherRequestOut())
  end)

  it("forgets a search when the auction house closes", function()
    local frame, GC = buildFrame()
    searchOut(frame, GC, true)
    GC.Sniper.OnAuctionHouseClosed()
    assert.is_false(GC.Sell._OtherRequestOut())
  end)

  -- Every search out is its own entry, by the key it went out with: a newer search's answer
  -- does not answer an older one still out (review sell-fix4 N5).
  it("keeps an older search counted while a newer one is answered", function()
    local frame, GC = buildFrame()
    searchOut(frame, GC, false)
    GC.Sniper._NoteSearchSent({ itemID = 77, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
    GC.Sniper.OnItemSearchResults(77, { itemID = 77, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
    assert.is_true(GC.Sell._OtherRequestOut()) -- item 42's search is still out
    GC.Sniper.OnItemSearchResults(42, searches[1])
    assert.is_false(GC.Sell._OtherRequestOut())
  end)

  -- The BUY tab's own quote search goes in the same book (review sell-fix4 M3); its sending side
  -- is pinned in spec/buy_purchase_spec.lua. Answered through the router like any search.
  it("counts a search the BUY tab noted until its commodity answer lands", function()
    local frame, GC = buildFrame()
    frame.sellTab.scripts.OnClick()
    GC.Sniper._NoteSearchSent({ itemID = 101 })
    assert.is_true(GC.Sell._OtherRequestOut())
    GC.Sniper.OnCommoditySearchResults(101)
    assert.is_false(GC.Sell._OtherRequestOut())
  end)

  it("forgets it when the auction house closes", function()
    local frame, GC = buildFrame()
    pageOut(frame, GC)
    GC.Sniper.OnAuctionHouseClosed()
    assert.is_false(GC.Sell._OtherRequestOut())
  end)
end)
