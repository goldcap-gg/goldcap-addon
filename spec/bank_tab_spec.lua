local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/BankTab.lua: a GoldCap tab on Blizzard's bank window, after its Bank and Warband Bank tabs,
-- whose panel over the bank's slots holds the bank by group card and the carry list. The real
-- Theme, group rules, selection, press machine, carry list and group card; the bank window (its
-- tab system, its two tabs, its panel), the bags and the client calls are faked, the window's
-- shapes as Blizzard_UIPanels_Game's Mainline/BankFrame.lua and BankFrame.xml build them.
describe("GoldCap tab on the bank window", function()
  local GC, B, C, restore, saved, bags, used, timers, blizzard, selects, route
  local CHARACTER, ACCOUNT = 0, 2
  local KEYS = { "Enum", "UIParent", "BankFrame", "BankPanel", "MerchantFrame", "ItemLocation", "C_Container",
    "C_Item", "C_Bank", "C_Timer", "hooksecurefunc", "GoldCap_AppRuns", "SpellIsTargeting", "GetCursorInfo", "BANK",
    "ACCOUNT_BANK_PANEL_TITLE", "CreateFrame", "PlaySound", "SOUNDKIT" }

  local FILE = {
    v = 3, generatedAt = 1, runs = {}, groups = { "G" },
    caps = { { i = 1, c = 700, u = 1000, r = 1, k = true }, { i = 3, c = 700, u = 1000, r = 2, k = true } },
    rules = { { n = "Herbs", p = "gather", d = 24, fp = 80 }, { n = "Ore", p = "gather", d = 24, fp = 80 } },
  }
  local NAMES = { [1] = "Bloom", [3] = "Bismuth", [100] = "Gem-Inlaid Velvet Cinch" }

  local function info(itemID, count)
    return { itemID = itemID, itemName = NAMES[itemID], stackCount = count, iconFileID = itemID,
      hyperlink = "item:" .. itemID, isBound = false, isLocked = false }
  end

  local function textOf(fs) return W.state(fs).text end
  local function up(widget) return widget ~= nil and widget:IsShown() end
  local function at(widget) return W.state(widget).points[1] end
  local function press(button) W.state(button).scripts.OnClick(button) end

  -- The art half of a tab button (TabSystemButtonArtTemplate): its six textures, its name, and
  -- TabSystemButtonArtMixin:SetTabSelected, which shows one set of art or the other and disables
  -- the selected tab.
  local function tabArt(f)
    for _, key in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive" }) do
      f[key] = f:CreateTexture(nil, "BACKGROUND")
    end
    f.Text = f:CreateFontString(nil, "OVERLAY")
    function f:SetText(text) self.Text:SetText(text) end
    function f:GetText() return self.Text:GetText() end
    function f:GetFontString() return self.Text end
    function f:SetTabSelected(selected)
      W.state(self).selected = selected
      for _, key in ipairs({ "LeftActive", "MiddleActive", "RightActive" }) do self[key]:SetShown(selected) end
      for _, key in ipairs({ "Left", "Middle", "Right" }) do self[key]:SetShown(not selected) end
      if selected then self:Disable() else self:Enable() end
    end
    return f
  end

  local function selected(tab) return W.state(tab).selected end
  local function activeShown(tab) return tab.LeftActive:IsShown() and tab.MiddleActive:IsShown() and tab.RightActive:IsShown() end

  -- The frames a frame of the next frame runs: every C_Timer.After(0) armed, and those they arm.
  local function nextFrame()
    while true do
      local due
      for k, t in ipairs(timers) do
        if t.seconds == 0 then due = k break end
      end
      if not due then return end
      table.remove(timers, due).fn()
    end
  end

  -- Blizzard's window shows (its OnShow selects its first tab, BankFrameMixin:SelectDefaultTab, and
  -- the panel resets and selects its first bank tab), then the bank's event comes, then a frame.
  local function open()
    _G.BankFrame:Show()
    _G.BankPanel:Reset()
    local onShow = W.state(_G.BankFrame).hooks and W.state(_G.BankFrame).hooks.OnShow
    if onShow then onShow(_G.BankFrame) end
    GC.BankRoute.OnBankOpened()
    nextFrame()
  end

  local function close()
    GC.BankRoute.OnBankClosed()
    _G.BankFrame:Hide()
  end

  -- The player clicks Blizzard's tab `id`: its OnClick selects it (BankFrame:SetTab sets the
  -- panel's bank type, the panel resets and selects its first bank tab, then the tab system draws
  -- the tab selected), then the click's post-hooks run.
  local function clickBlizzard(id)
    _G.BankPanel:Reset()
    for i, tab in ipairs(blizzard) do tab:SetTabSelected(i == id) end
    _G.BankFrame.TabSystem.selectedTabID = id
    W.state(blizzard[id]).hooks.OnClick(blizzard[id])
  end

  -- Carry list data from the Companion's region payload: one flip in the bags to put in the Warband
  -- Bank for another realm (Core/SellRoute.lua's CarryPlan, faked).
  local function withRoute(putIn)
    GC.SellRoute = {
      HereId = function() return 1084 end,
      CarryPlan = function() return { putIn = putIn, takeOut = {}, stuck = {} } end,
      ForItem = function() return nil end,
      PaceText = function() return "sells in about 2 days" end,
      RealmName = function() return "Kazzak" end,
    }
    GC.Data = { SellSpots = function() return false end, FlipLevel = function() return 0 end }
  end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    _G.CreateFrame = function(kind, name, parent, template)
      local f = W.CreateFrame(kind, name, parent)
      if template == "TabSystemButtonArtTemplate" then tabArt(f) end
      return f
    end
    used, timers, selects = {}, {}, 0
    bags = { [0] = { info(1, 200), info(3, 50) }, [6] = {}, [12] = { info(1, 600) } }
    _G.Enum = { BankType = { Character = CHARACTER, Account = ACCOUNT } }
    _G.BANK, _G.ACCOUNT_BANK_PANEL_TITLE = "Bank", "Warband Bank"
    _G.SpellIsTargeting = function() return false end
    _G.GetCursorInfo = function() return nil end
    _G.PlaySound, _G.SOUNDKIT = function() end, { IG_CHARACTER_INFO_TAB = 841 }
    _G.UIParent = W.CreateFrame("Frame")
    -- BankFrame.xml: 738 by 460, its TabSystem under its bottom left with the two tabs
    -- GenerateBankTypeTabs adds, its BankPanel, and the title PortraitFrameBaseTemplate puts in
    -- its TitleContainer.
    local bank = W.CreateFrame("Frame")
    bank:SetSize(738, 460)
    _G.BankFrame = bank
    function bank:GetActiveBankType() return ACCOUNT end
    bank.TitleContainer = W.CreateFrame("Frame", nil, bank)
    bank.TitleContainer.TitleText = bank.TitleContainer:CreateFontString(nil, "OVERLAY")
    bank.TitleContainer.TitleText:SetText("Warband Bank")
    local system = W.CreateFrame("Frame", nil, bank)
    bank.TabSystem = system
    blizzard = {}
    for i, name in ipairs({ "Bank", "Warband Bank" }) do
      local tab = tabArt(W.CreateFrame("Button", nil, system))
      tab:SetText(name)
      function tab:IsSelected() return W.state(self).selected == true end
      blizzard[i] = tab
    end
    system.tabs = blizzard
    function system:GetTabButton(id) return blizzard[id] end
    blizzard[1]:SetTabSelected(false)
    blizzard[2]:SetTabSelected(true)
    system.selectedTabID = 2
    _G.BankPanel = W.CreateFrame("Frame", nil, bank)
    bank.BankPanel = _G.BankPanel
    -- BankPanelMixin:Reset selects the first bank tab (SelectFirstAvailableTab), through the panel.
    function _G.BankPanel:Reset() self:SelectTab(1) end
    function _G.BankPanel:SelectTab() selects = selects + 1 end
    bank:Hide()
    _G.MerchantFrame = W.CreateFrame("Frame")
    _G.MerchantFrame:Hide()
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_Container = {
      GetContainerNumSlots = function(b) return bags[b] and #bags[b] or 0 end,
      GetContainerItemInfo = function(b, slot) return bags[b] and bags[b][slot] or nil end,
      UseContainerItem = function(...) used[#used + 1] = { ... } end,
    }
    _G.C_Item = {
      IsBoundToAccountUntilEquip = function() return false end,
      CanBeRefunded = function() return false end,
      GetCurrentItemLevel = function() return 0 end,
    }
    _G.C_Bank = {
      CanUseBank = function() return true end,
      IsItemAllowedInBankType = function() return true end,
      FetchPurchasedBankTabIDs = function(t) return t == ACCOUNT and { 12 } or { 6 } end,
    }
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    _G.hooksecurefunc = function(t, name, fn)
      local original = t[name]
      t[name] = function(...)
        local result = original(...)
        fn(...)
        return result
      end
    end
    _G.GoldCap_AppRuns = FILE
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("Core/GroupRules.lua", GC)
    helper.loadModule("Core/CraftQueue.lua", GC)
    helper.loadModule("Core/BankGroups.lua", GC)
    helper.loadModule("Core/VendorPress.lua", GC)
    GC.GroupRules.Adopt()
    GC.SellRoute = { HereId = function() return nil end }
    GC.db = {}
    GC.BuyCapEditor = { Open = function() end, CloseFor = function() end }
    helper.loadModule("UI/BankRoute.lua", GC)
    helper.loadModule("UI/BankGroupsCard.lua", GC)
    helper.loadModule("UI/BankTab.lua", GC)
    B, C = GC.BankTab, GC.BankGroupsCard
    route = GC.BankRoute
  end)

  after_each(function()
    GC.ActivateLocale(nil)
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  it("hangs a GoldCap tab after Blizzard's two, and the bank shows as Blizzard's until it is picked", function()
    open()
    local tab = B._tab
    assert.is_true(up(tab))
    assert.equal("GoldCap", tab:GetText())
    assert.same({ "TOPLEFT", _G.BankFrame.TabSystem, "TOPRIGHT", 1, 0 }, at(tab))
    assert.equal(32, tab:GetHeight())
    assert.is_true(tab:GetWidth() >= 100)
    assert.is_false(selected(tab))
    -- Nothing of GoldCap's over the bank or beside it.
    assert.is_false(up(B._panel))
    assert.is_false(up(C._frame))
    -- Blizzard's tab as Blizzard drew it.
    assert.is_true(activeShown(blizzard[2]))
    assert.is_true(blizzard[2].Text:IsShown())
    assert.is_nil(GC.db.bankTab)
  end)

  it("picked, lays its panel over the slots with the group card in it, and draws Blizzard's tab as not selected", function()
    open()
    press(B._tab)
    local panel = B._panel
    assert.is_true(up(panel))
    assert.is_true(W.state(panel).mouse)
    assert.is_true(selected(B._tab))
    -- Over the bank's own frames, inside the window.
    assert.is_true(panel:GetFrameLevel() > _G.BankPanel:GetFrameLevel())
    assert.equal(panel, C._frame:GetParent())
    assert.is_true(up(C._frame))
    assert.same({ "TOPLEFT", panel, "TOPLEFT", 8, -8 }, at(C._frame))
    -- As wide as the panel's room: 738 less 4 and 4 for the panel, less 8 and 8 around the card.
    assert.equal(738 - 8 - 16, C._frame:GetWidth())
    assert.equal(460 - 22 - 30 - 16, C._slot.height)
    -- Blizzard's selected tab drawn as nothing, our button over it as an unselected tab with its name.
    assert.is_false(blizzard[2].LeftActive:IsShown())
    assert.is_false(blizzard[2].Text:IsShown())
    assert.is_true(up(B._back))
    assert.equal(blizzard[2], W.state(B._back).allPoints)
    assert.equal("Warband Bank", B._back:GetText())
    assert.is_false(selected(B._back))
    -- The other tab is Blizzard's own, untouched.
    assert.is_true(blizzard[1].Text:IsShown())
    assert.equal("GoldCap", textOf(_G.BankFrame.TitleContainer.TitleText))
    assert.equal("goldcap", GC.db.bankTab)
  end)

  it("stands the groups in as many columns as fit on the panel", function()
    open()
    press(B._tab)
    local xs = {}
    for _, b in ipairs(C._blocks) do
      if b:IsShown() then xs[#xs + 1] = at(b)[4] end
    end
    assert.same({ 0 }, { xs[1] })
    assert.is_true(xs[2] > 0)
    assert.equal(at(C._blocks[1])[5], at(C._blocks[2])[5])
  end)

  it("shows the bank again from the button over Blizzard's tab, and remembers that", function()
    open()
    press(B._tab)
    press(B._back)
    assert.is_false(up(B._panel))
    assert.is_false(up(B._back))
    assert.is_false(up(C._frame))
    assert.is_false(selected(B._tab))
    assert.is_true(activeShown(blizzard[2]))
    assert.is_true(blizzard[2].Text:IsShown())
    assert.equal("Warband Bank", textOf(_G.BankFrame.TitleContainer.TitleText))
    assert.is_nil(GC.db.bankTab)
  end)

  it("goes on the frame after the player clicks Blizzard's other tab, never inside Blizzard's call", function()
    open()
    press(B._tab)
    clickBlizzard(1)
    assert.is_true(up(B._panel))
    nextFrame()
    assert.is_false(up(B._panel))
    assert.is_nil(GC.db.bankTab)
    -- The tab it covered is no longer selected: its selected art stays hidden, its name comes back.
    assert.is_false(activeShown(blizzard[2]))
    assert.is_true(blizzard[2].Text:IsShown())
    assert.is_true(activeShown(blizzard[1]))
  end)

  it("goes when the player clicks a bank tab down the panel's edge, the one to buy included", function()
    open()
    press(B._tab)
    _G.BankPanel:SelectTab(-1)
    nextFrame()
    assert.is_false(up(B._panel))
    assert.is_true(activeShown(blizzard[2]))
    assert.is_true(blizzard[2].Text:IsShown())
  end)

  it("stays when the bank panel resets by itself (a tab bought, the server's tab list)", function()
    open()
    press(B._tab)
    _G.BankPanel:Reset()
    nextFrame()
    assert.is_true(up(B._panel))
    assert.equal("goldcap", GC.db.bankTab)
  end)

  it("opens on the GoldCap tab when the bank was closed on it, Blizzard's own first tab at the open not counting", function()
    open()
    press(B._tab)
    close()
    assert.is_false(up(B._panel))
    assert.is_true(blizzard[2].Text:IsShown())
    assert.equal("goldcap", GC.db.bankTab)
    open()
    assert.is_true(up(B._panel))
    assert.equal("goldcap", GC.db.bankTab)
    assert.is_true(up(C._frame))
  end)

  it("waits for Blizzard's window when the bank's event comes first", function()
    GC.db.bankTab = "goldcap"
    GC.BankRoute.OnBankOpened()
    nextFrame()
    assert.is_true(B._panel == nil or not up(B._panel))
    _G.BankFrame:Show()
    _G.BankPanel:Reset()
    W.state(_G.BankFrame).hooks.OnShow(_G.BankFrame)
    nextFrame()
    assert.is_true(up(B._panel))
    assert.equal("goldcap", GC.db.bankTab)
  end)

  it("has no tab when a bag addon keeps Blizzard's window under a hidden parent: the card stays beside the bank", function()
    local hidden = W.CreateFrame("Frame")
    hidden:Hide()
    _G.BankFrame:SetParent(hidden)
    GC.db.bankTab = "goldcap"
    open()
    assert.is_true(B._tab == nil or not up(B._tab))
    assert.equal("beside", B.Where())
    assert.is_true(up(C._frame))
    assert.equal(_G.UIParent, C._frame:GetParent())
    assert.same({ "TOPLEFT", _G.BankFrame, "TOPRIGHT", 4, 0 }, at(C._frame))
  end)

  it("has no tab when Blizzard's window is shrunk to nothing (Bagnon's tiny parent)", function()
    function _G.UIParent:GetEffectiveScale() return 1 end
    function _G.BankFrame:GetEffectiveScale() return 0.001 end
    open()
    assert.is_true(B._tab == nil or not up(B._tab))
    assert.is_true(up(C._frame))
  end)

  it("has no tab with nothing to hold: no followed group and no route data", function()
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = {}, caps = {}, rules = {} }
    GC.GroupRules.Adopt()
    open()
    assert.is_true(B._tab == nil or not up(B._tab))
  end)

  it("keeps the card on the panel with none of the groups here, saying so, with its bank choice", function()
    bags = { [0] = {}, [6] = {}, [12] = {} }
    open()
    press(B._tab)
    assert.is_true(up(C._frame))
    assert.is_true(up(C._frame.empty))
    assert.equal("None of your groups' items are in your bags or this bank.", textOf(C._frame.empty))
    assert.is_true(up(C._frame.choice))
    assert.is_false(up(B._panel.empty))
  end)

  it("puts the carry list at the panel's right, and the card makes room for it", function()
    withRoute({ { itemID = 100, name = NAMES[100], count = 1, icon = 100,
      spot = { realmId = 1305, list = 22000000, days = 2.4 }, locations = { { bag = 0, slot = 3 } } } })
    bags[0][3] = info(100, 1)
    open()
    press(B._tab)
    local list = route._frame
    assert.is_true(up(list))
    assert.equal(B._panel, list:GetParent())
    assert.same({ "TOPRIGHT", B._panel, "TOPRIGHT", -8, -8 }, at(list))
    assert.equal(738 - 8 - 16 - list:GetWidth() - 8, C._frame:GetWidth())
    -- Blizzard's tab again: neither shows.
    press(B._back)
    assert.is_false(up(list))
    assert.is_false(up(C._frame))
  end)

  it("says so on the panel when it holds nothing", function()
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = {}, caps = {}, rules = {} }
    GC.GroupRules.Adopt()
    withRoute({})
    open()
    press(B._tab)
    assert.is_true(up(B._panel.empty))
    assert.equal("Nothing to move at this bank.", textOf(B._panel.empty))
  end)
end)
