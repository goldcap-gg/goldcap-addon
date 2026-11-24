-- The answer of a live Check on WoW: Forever's Deals board goes to the board's own count of
-- checks (GC.ForeverDeals.Checked), whoever sent it: the verify walk or the gear loop's own
-- Check. Any other row's answer is counted as before, when it is the check of a find. The whole
-- addon as GoldCap_Camelot.toc loads it, driven through GC.Sniper's own functions.
describe("Forever AUTO checks wiring", function()
  local GC, sent, checked

  local function noop() end
  local function zero() return 0 end
  local stubFrame
  local METHODS = {
    SetScript = function(self, name, fn) self.scripts[name] = fn end,
    GetScript = function(self, name) return self.scripts[name] end,
    HookScript = function(self, name, fn)
      local prev = self.scripts[name]
      self.scripts[name] = function(...)
        if prev then prev(...) end
        return fn(...)
      end
    end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown == true end,
    IsVisible = function(self) return self.shown == true end,
    SetText = function(self, text) self.text = text end,
    GetText = function(self) return self.text or "" end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
    IsEnabled = function() return true end,
    HasFocus = function() return false end,
    GetChecked = function() return false end,
    GetFrameStrata = function() return "MEDIUM" end,
    GetFrameLevel = function() return 1 end,
    CreateFontString = function() return stubFrame() end,
    CreateTexture = function() return stubFrame() end,
    CreateAnimationGroup = function() return stubFrame() end,
    CreateAnimation = function() return stubFrame() end,
    IsPlaying = function() return false end,
  }
  local ZERO = { GetWidth = true, GetHeight = true, GetStringWidth = true, GetUnboundedStringWidth = true,
    GetStringHeight = true, GetVerticalScroll = true, GetVerticalScrollRange = true, GetValue = true,
    GetNumPoints = true, GetScale = true, GetEffectiveScale = true, GetLeft = true, GetRight = true,
    GetTop = true, GetBottom = true }
  local VERBS = { "Set", "Get", "Is", "Has", "Can", "Create", "Enable", "Disable", "Register",
    "Unregister", "Clear", "Start", "Stop", "Play", "Lock", "Unlock", "Raise", "Lower", "Adjust",
    "Update", "Refresh", "Insert", "Highlight", "Unhighlight", "Resume", "Pause", "Restart" }
  local function method(_, key)
    if METHODS[key] then return METHODS[key] end
    if ZERO[key] then return zero end
    if type(key) ~= "string" then return nil end
    for _, verb in ipairs(VERBS) do
      if key:sub(1, #verb) == verb then return noop end
    end
    return nil
  end
  stubFrame = function() return setmetatable({ scripts = {}, shown = false }, { __index = method }) end

  before_each(function()
    sent, checked = {}, {}
    local frames = {}
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.CreateFrame = function(_, name)
      local f = stubFrame()
      frames[#frames + 1] = f
      if name and name ~= "" then _G[name] = f end
      return f
    end
    _G.GetBuildInfo = function() return "1.60.1", "70009", "Sep 1 2026", 16001 end
    _G.UISpecialFrames, _G.SlashCmdList = {}, {}
    _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    _G.hooksecurefunc = noop
    _G.GetTime = function() return 100 end
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.PlaySound = noop
    _G.SOUNDKIT = { MAP_PING = 3175, RAID_WARNING = 1, READY_CHECK = 3 }
    _G.C_CurrencyInfo = { GetCoinTextureString = function(copper) return tostring(copper) .. "c" end }
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function(_, itemID)
      return { ContinueOnItemLoad = function(_, cb) cb() end, GetItemIcon = function() return "icon" end,
        GetItemQuality = function() return nil end, GetItemName = function() return "Item " .. itemID end }
    end }
    _G.C_Timer = { After = noop, NewTicker = function() return { Cancel = noop } end }
    _G.C_AuctionHouse = {
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      GetItemKeyInfo = function() return { isCommodity = true } end,
      SendSearchQuery = function(key) sent[#sent + 1] = key.itemID end,
      SendBrowseQuery = noop,
      HasFullBrowseResults = function() return false end,
      GetNumCommoditySearchResults = function() return 0 end,
      GetCommoditySearchResultInfo = function() return nil end,
      IsThrottledMessageSystemReady = function() return true end,
    }

    GC = {}
    local toc = assert(io.open("GoldCap/GoldCap_Camelot.toc", "r"))
    for rawLine in toc:lines() do
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^#") then
        local chunk = assert(loadfile("GoldCap/" .. line:gsub("\\", "/")))
        chunk("GoldCap", GC)
      end
    end
    toc:close()
    GC.Print = noop
    for _, f in ipairs(frames) do
      if f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "GoldCap") end
    end
    GC.Sniper.OnAuctionHouseShow()
    GC.AutoReadout._Reset()
    GC.ForeverDeals.Checked = function(itemID) checked[#checked + 1] = itemID end
  end)

  after_each(function()
    for _, name in ipairs({ "CreateFrame", "CreateColor", "GoldCapSniperFrame", "GoldCapAuctionHouseDock",
      "UISpecialFrames", "SlashCmdList", "C_AddOns", "SLASH_GOLDCAP1", "SLASH_GOLDCAP2",
      "hooksecurefunc", "GetTime", "GetMoney", "PlaySound", "SOUNDKIT", "C_Timer", "C_CurrencyInfo",
      "ITEM_QUALITY_COLORS", "Item", "GoldCapDB", "GetBuildInfo", "C_AuctionHouse", "Enum" }) do
      _G[name] = nil
    end
    _G.time = os.time
  end)

  local function check(deal)
    assert.is_true(GC.Sniper._CheckNow(deal))
    assert.same({ deal.itemID }, sent)
    GC.Sniper.OnCommoditySearchResults(deal.itemID)
  end

  it("a Forever row's answered Check goes to its board's count, not the find's", function()
    check({ itemID = 2589, unitPrice = 60, qty = 1, forever = "vendor", stale = true })
    assert.same({ 2589 }, checked)
    assert.equal(0, GC.AutoReadout.Counts().checked)
  end)

  it("any other row's answered Check of a find is counted as before", function()
    check({ itemID = 2589, unitPrice = 60, qty = 1, stale = true })
    assert.same({}, checked)
    assert.equal(1, GC.AutoReadout.Counts().checked)
  end)

  -- A Forever commodity row under its vendor price, five units at 60c: the Check's answer.
  local function vendorRow(minimumProfit)
    GC.ForeverDeals.CeilingFor = function()
      return { ceilingUnit = 80, kind = "vendor", exitUnit = 90, minimumProfit = minimumProfit }
    end
    _G.C_AuctionHouse.GetNumCommoditySearchResults = function() return 1 end
    _G.C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i)
      if i == 1 then return { unitPrice = 60, quantity = 5, auctionID = 1, numOwnerItems = 0 } end
    end
    GC.ForeverDeals.Checked = function(itemID) checked[#checked + 1] = itemID; return true end
  end

  it("a find's first answer that is a buy is a deal", function()
    vendorRow(1)
    check({ itemID = 2589, unitPrice = 60, qty = 5, forever = "vendor", stale = true })
    assert.same({ 2589 }, checked)
    assert.equal(1, GC.AutoReadout.Counts().deals)
  end)

  it("a find's first answer that refuses it is no deal", function()
    vendorRow(100000)
    check({ itemID = 2589, unitPrice = 60, qty = 5, forever = "vendor", stale = true })
    assert.same({ 2589 }, checked)
    assert.equal(0, GC.AutoReadout.Counts().deals)
  end)

  -- A piece of gear under its vendor price: one lot at 60c, which the vendor pays 90c for. Its
  -- Check answers WATCH with a candidate, the lot shape, which the board reads as a buy.
  it("a gear lot's first answer that the board reads BUY is a deal", function()
    vendorRow(1)
    _G.Enum = { AuctionHouseSortOrder = { Buyout = 4 } }
    _G.C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = false } end
    _G.C_AuctionHouse.GetNumItemSearchResults = function() return 1 end
    _G.C_AuctionHouse.GetItemSearchResultInfo = function(_, i)
      if i == 1 then
        return { itemKey = { itemID = 3021, itemLevel = 20, itemSuffix = 0, battlePetSpeciesID = 0 },
          auctionID = 77, buyoutAmount = 60, quantity = 1, containsOwnerItem = false }
      end
    end
    assert.is_true(GC.Sniper._CheckNow({ itemID = 3021, unitPrice = 60, qty = 1, forever = "vendor", stale = true }))
    GC.Sniper.OnItemSearchResults(3021)
    assert.same({ 3021 }, checked)
    assert.equal(1, GC.AutoReadout.Counts().deals)
  end)

  it("a recheck that is a buy is no new deal", function()
    vendorRow(1)
    GC.ForeverDeals.Checked = function() return false end
    check({ itemID = 2589, unitPrice = 60, qty = 5, forever = "vendor", stale = true })
    assert.equal(0, GC.AutoReadout.Counts().deals)
  end)
end)
