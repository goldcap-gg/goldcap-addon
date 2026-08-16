local helper = require("spec.spec_helper")

describe("Auction House tab", function()
  local GC, ah, created, hooks

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
    created, hooks = {}, {}
    ah = widget("Frame")
    ah.Tabs = { widget("Button", ah), widget("Button", ah) }
    ah.SetDisplayMode = function() end
    _G.AuctionHouseFrame = ah
    _G.CreateFrame = function(kind, name, parent, template)
      local w = widget(kind, parent)
      w.template, w.name = template, name
      created[#created + 1] = w
      return w
    end
    _G.hooksecurefunc = function(target, method, fn) hooks[#hooks + 1] = { target, method, fn } end
    _G.PanelTemplates_TabResize = function() end
    GC = { Sniper = { toggles = 0, shown = false } }
    GC.Sniper.Toggle = function() GC.Sniper.toggles = GC.Sniper.toggles + 1; GC.Sniper.shown = not GC.Sniper.shown end
    GC.Sniper.IsWindowShown = function() return GC.Sniper.shown end
    helper.loadModule("UI/AuctionHouseTab.lua", GC)
  end)

  after_each(function()
    _G.AuctionHouseFrame, _G.CreateFrame, _G.hooksecurefunc = nil, nil, nil
    _G.PanelTemplates_TabResize, _G.PanelTemplates_SetNumTabs = nil, nil
  end)

  it("puts one tab on the auction house, after Blizzard's own", function()
    GC.AuctionHouseTab.Install()
    assert.equal(1, #created)
    assert.equal("AuctionHouseFrameTabTemplate", created[1].template)
    assert.equal(ah, created[1].parent)
    assert.equal(ah.Tabs[2], created[1].points[1][2])
  end)

  it("installs once however many times the auction house opens", function()
    GC.AuctionHouseTab.Install()
    GC.AuctionHouseTab.Install()
    GC.AuctionHouseTab.Install()
    assert.equal(1, #created)
    assert.equal(1, #hooks)
  end)

  it("toggles the addon window and follows its state", function()
    GC.AuctionHouseTab.Install()
    created[1].scripts.OnClick()
    assert.equal(1, GC.Sniper.toggles)
    assert.is_true(GC.Sniper.IsWindowShown())
  end)

  -- The taint rule this file exists to respect: PanelTemplates_SetNumTabs writes
  -- `numTabs` and `Tabs` onto the frame it is given, and Blizzard's own code
  -- reads them back. Calling it on AuctionHouseFrame is how an addon taints a
  -- frame it does not own -- and our purchase path is hardware-input gated, so a
  -- tainted auction house is not a cosmetic problem.
  it("never touches Blizzard's tab bookkeeping", function()
    local violations = 0
    _G.PanelTemplates_SetNumTabs = function() violations = violations + 1 end
    GC.AuctionHouseTab.Install()
    created[1].scripts.OnClick()
    GC.AuctionHouseTab.Refresh()
    assert.equal(0, violations)
    assert.is_nil(ah.numTabs)
  end)

  it("hooks Blizzard's widgets rather than replacing their scripts", function()
    local before = ah.SetDisplayMode
    GC.AuctionHouseTab.Install()
    assert.equal(before, ah.SetDisplayMode)
    assert.equal("SetDisplayMode", hooks[1][2])
  end)

  -- Install runs synchronously inside GC.Sniper.OnAuctionHouseShow. An error
  -- here would abort the rest of that function -- no ticker, no Auto, no
  -- auto-open -- which is far worse than a missing tab.
  it("survives a client with no tab template at all", function()
    _G.CreateFrame = function() error("no such template") end
    GC.Theme = { Button = function(parent) return widget("Button", parent) end }
    assert.has_no.errors(function() GC.AuctionHouseTab.Install() end)
  end)

  it("survives an auction house frame that has not loaded yet", function()
    _G.AuctionHouseFrame = nil
    assert.has_no.errors(function() GC.AuctionHouseTab.Install() end)
    assert.equal(0, #created)
  end)
end)
