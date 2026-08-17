local helper = require("spec.spec_helper")

-- The embedded GoldCap tab on Blizzard's own Auction House. Owner-approved 2026-08-17,
-- superseding the earlier entry-point-only design: the tab now registers in Blizzard's own
-- tab machinery (ah.Tabs + PanelTemplates_SetNumTabs + ah.tabsForDisplayMode -- the pattern
-- Auctionator has shipped for years) and drives AuctionHouseFrame:SetDisplayMode with a
-- GoldCap display mode, so BLIZZARD's own code hides its panels, selects our tab, and
-- restores everything when one of its tabs is clicked. Verified against
-- Blizzard_AuctionHouseFrame.lua (Gethe/wow-ui-source, live): SetDisplayMode iterates the
-- MODE table (ours is empty -- shows nothing of theirs), compares modes by identity, and
-- numTabs/selectedTab feed insecure UI code only (UpdateTitle), never a protected path.
describe("Auction House tab", function()
  local GC, ah, created, docked

  local function widget(kind, parent)
    local w = { kind = kind, parent = parent, points = {}, scripts = {}, shown = true }
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:ClearAllPoints() self.points = {} end
    function w:SetSize(a, b) self.w, self.h = a, b end
    function w:SetText(t) self.text = t end
    function w:SetLabel(t) self.label = t end
    function w:SetScript(name, fn) self.scripts[name] = fn end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    return w
  end

  before_each(function()
    created, docked = {}, {}
    ah = widget("Frame")
    ah.Tabs = { widget("Button", ah), widget("Button", ah), widget("Button", ah) }
    ah.numTabs = 3
    ah.tabsForDisplayMode = {}
    -- Faithful to the verified Blizzard implementation in the two ways the addon depends on:
    -- it stores displayMode by identity and early-returns when the mode is unchanged.
    ah.SetDisplayMode = function(self, mode)
      if self.displayMode == mode then return end
      self.displayMode = mode
    end
    ah.SetTitle = function(self, title) self.title = title end
    _G.AuctionHouseFrame = ah
    _G.AuctionHouseFrameDisplayMode = { Buy = {} }
    _G.CreateFrame = function(kind, name, parent, template)
      local w = widget(kind, parent)
      w.template, w.name = template, name
      created[#created + 1] = w
      -- Faithful to the real client: PanelTabButtonTemplate carries parentArray="Tabs"
      -- (SharedUIPanelTemplates.xml:905, read verbatim), so creating a tab from the AH tab
      -- template APPENDS it to the parent's Tabs array by itself. The first shipped version
      -- of this module did not know that, inserted the tab a second time, anchored it to
      -- itself through the duplicate, and rendered no tab at all -- a fake without this line
      -- proves nothing about that whole failure class.
      if template == "AuctionHouseFrameTabTemplate" and parent and parent.Tabs then
        parent.Tabs[#parent.Tabs + 1] = w
      end
      return w
    end
    -- Faithful hooksecurefunc: the hook runs after the original, and cannot replace it.
    _G.hooksecurefunc = function(target, method, fn)
      local original = target[method]
      target[method] = function(...)
        original(...)
        fn(...)
      end
    end
    _G.PanelTemplates_TabResize = function() end
    _G.PanelTemplates_SetNumTabs = function(target, n) target.numTabs = n end
    GC = { Sniper = { shown = false } }
    GC.Sniper.SetDocked = function(host) docked[#docked + 1] = { host = host }; GC.Sniper.shown = host ~= nil end
    GC.Sniper.IsWindowShown = function() return GC.Sniper.shown end
    GC.Sniper.Toggle = function() GC.Sniper.shown = not GC.Sniper.shown end
    helper.loadModule("UI/AuctionHouseTab.lua", GC)
  end)

  after_each(function()
    _G.AuctionHouseFrame, _G.CreateFrame, _G.hooksecurefunc = nil, nil, nil
    _G.PanelTemplates_TabResize, _G.PanelTemplates_SetNumTabs = nil, nil
    _G.AuctionHouseFrameDisplayMode = nil
  end)

  local function tabButton()
    for _, w in ipairs(created) do
      if w.template == "AuctionHouseFrameTabTemplate" then return w end
    end
    return nil
  end

  local function dockPanel()
    for _, w in ipairs(created) do
      if w.name == "GoldCapAuctionHouseDock" then return w end
    end
    return nil
  end

  it("registers the tab in Blizzard's own tab machinery, after their tabs", function()
    GC.AuctionHouseTab.Install()
    local tab = tabButton()
    assert.is_table(tab)
    assert.equal(ah, tab.parent)
    assert.equal(tab, ah.Tabs[4])
    assert.equal(4, ah.numTabs)
    assert.is_table(tab.displayMode)
    assert.equal(4, ah.tabsForDisplayMode[tab.displayMode])
    assert.equal(ah.Tabs[3], tab.points[1][2]) -- anchored to the last Blizzard tab
  end)

  it("installs once however many times the auction house opens", function()
    GC.AuctionHouseTab.Install()
    GC.AuctionHouseTab.Install()
    GC.AuctionHouseTab.Install()
    assert.equal(4, #ah.Tabs)
    assert.equal(1, #(function()
      local tabs = {}
      for _, w in ipairs(created) do
        if w.template == "AuctionHouseFrameTabTemplate" then tabs[#tabs + 1] = w end
      end
      return tabs
    end)())
  end)

  it("a click drives Blizzard's own SetDisplayMode, docks the window, and names the title", function()
    GC.AuctionHouseTab.Install()
    local tab, dock = tabButton(), dockPanel()
    assert.is_table(dock)
    assert.is_false(dock:IsShown()) -- hidden until the tab is chosen
    tab.scripts.OnClick(tab)
    assert.equal(tab.displayMode, ah.displayMode)
    assert.is_true(dock:IsShown())
    assert.equal(1, #docked) -- the window was docked into the panel, once
    assert.equal(dock, docked[1].host)
    assert.equal("GoldCap", ah.title)
  end)

  it("hides the dock and the window when a Blizzard tab takes the display back", function()
    GC.AuctionHouseTab.Install()
    local tab, dock = tabButton(), dockPanel()
    tab.scripts.OnClick(tab)
    ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
    assert.is_false(dock:IsShown())
    assert.is_false(GC.Sniper.IsWindowShown())
  end)

  it("returns the auction house to Buy when the window hides while our mode is up", function()
    GC.AuctionHouseTab.Install()
    local tab, dock = tabButton(), dockPanel()
    tab.scripts.OnClick(tab)
    GC.Sniper.shown = false -- the window's own X / Escape
    GC.AuctionHouseTab.OnWindowHidden()
    assert.equal(_G.AuctionHouseFrameDisplayMode.Buy, ah.displayMode)
    assert.is_false(dock:IsShown())
  end)

  it("does nothing on a window hide when our mode is not the one showing", function()
    GC.AuctionHouseTab.Install()
    ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
    GC.AuctionHouseTab.OnWindowHidden()
    assert.equal(_G.AuctionHouseFrameDisplayMode.Buy, ah.displayMode)
  end)

  it("undocks the window when the auction house closes", function()
    GC.AuctionHouseTab.Install()
    local tab, dock = tabButton(), dockPanel()
    tab.scripts.OnClick(tab)
    GC.AuctionHouseTab.OnAuctionHouseClosed()
    assert.is_false(dock:IsShown())
    assert.equal(2, #docked)
    assert.is_nil(docked[2].host) -- SetDocked(nil): back to a floating window
  end)

  -- Install runs synchronously inside GC.Sniper.OnAuctionHouseShow. An error here would abort
  -- the rest of that function -- no ticker, no Auto, no auto-open -- which is far worse than a
  -- missing tab. A client without the tab template gets the addon's own button as a plain
  -- entry point and, crucially, NO registration: PanelTemplates_SetTab would reach into
  -- template textures the fallback button does not have.
  it("survives a client with no tab template, without registering the fallback", function()
    local realCreate = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent, template)
      if template then error("no such template") end
      return realCreate(kind, name, parent)
    end
    GC.Theme = { Button = function(parent) return widget("Button", parent) end }
    assert.has_no.errors(function() GC.AuctionHouseTab.Install() end)
    assert.equal(3, #ah.Tabs)
    assert.equal(3, ah.numTabs)
  end)

  it("survives an auction house frame that has not loaded yet", function()
    _G.AuctionHouseFrame = nil
    assert.has_no.errors(function() GC.AuctionHouseTab.Install() end)
    assert.equal(0, #created)
  end)

  -- The window-side wiring this module depends on, in the repo's source-text style: docking
  -- must neutralize geometry persistence (a docked frame's anchors are the host's, and saving
  -- them would corrupt the floating geometry), and the window's OnHide must hand off here.
  it("[wiring] the window skips geometry persistence while docked and hands OnHide to this module", function()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    assert.is_truthy(text:find("goldcapDockHost", 1, true))
    assert.is_truthy(text:find("GC.AuctionHouseTab.OnWindowHidden", 1, true))
    assert.is_truthy(text:find("function GC.Sniper.SetDocked", 1, true))
  end)
end)
