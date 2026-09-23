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
  local GC, ah, created, docked, clock, deferred

  -- Runs whatever the module scheduled for the next frame, in order.
  local function runDeferred()
    local pending = deferred
    deferred = {}
    for _, fn in ipairs(pending) do fn() end
  end

  local function widget(kind, parent)
    local w = { kind = kind, parent = parent, points = {}, scripts = {}, shown = true }
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:ClearAllPoints() self.points = {} end
    function w:SetSize(a, b) self.w, self.h = a, b end
    function w:SetText(t) self.text = t end
    function w:SetLabel(t) self.label = t end
    function w:SetScript(name, fn) self.scripts[name] = fn end
    -- Show/Hide run the frame's own OnShow/OnHide, the way the engine does: the module docks
    -- and undocks the window off those hooks now, because on the LibAHTab path the LIBRARY is
    -- what shows and hides the dock and there is no call site of ours to hang it on.
    function w:Show()
      self.shown = true
      if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function w:Hide()
      self.shown = false
      if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function w:HookScript(name, fn)
      local existing = self.scripts[name]
      self.scripts[name] = existing and function(...) existing(...) fn(...) end or fn
    end
    function w:IsShown() return self.shown end
    -- Screen position, which is what decides where the bar actually ends -- array order does
    -- not: another addon's tab can be appended after ours and still anchor itself to a tab
    -- BEFORE ours. Left nil unless a test sets it, so the anchor falls back to array order the
    -- way it does on a bar that has not been laid out yet.
    function w:GetRight() return self.right end
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
    _G.AuctionHouseFrameDisplayMode = {
      Buy = {}, ItemSell = {}, CommoditiesSell = {}, ItemBuy = {}, CommoditiesBuy = {},
    }
    clock = 1000
    _G.time = function() return clock end
    -- The module defers its second anchor pass by one frame (C_Timer.After(0)); the spec runs
    -- them on demand via runDeferred() rather than pretending they fire inline, so a test that
    -- does NOT call it still exercises the inline pass on its own.
    deferred = {}
    _G.C_Timer = { After = function(_, fn) deferred[#deferred + 1] = fn end }
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
    _G.time = os.time
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

  -- Auctionator adds four tabs of its own and anchors them to Blizzard's last one. Whether
  -- they exist when ours is built is a load-order race, and when they do not, both addons
  -- anchor to the same tab and one of the two draws underneath the other. Reported in-game
  -- 2026-08-28: Buy / Sell / Auctions / Shopping / Selling / Cancelling / Auctionator, and no
  -- GoldCap anywhere on the bar.
  it("moves clear of tabs another addon added after ours", function()
    GC.AuctionHouseTab.Install()
    local tab = tabButton()
    local foreign = widget("Button", ah)
    ah.Tabs[#ah.Tabs + 1] = foreign
    for index, entry in ipairs(ah.Tabs) do entry.right = index * 100 end
    foreign.right = 900

    GC.AuctionHouseTab.Install() -- the next auction house visit

    assert.equal(1, #tab.points)
    assert.equal(foreign, tab.points[1][2])
    assert.equal(5, #ah.Tabs) -- and no second tab of ours
  end)

  -- The FIRST auction house of a session is the case the inline pass cannot answer: nothing on
  -- the bar has been laid out when AUCTION_HOUSE_SHOW fires, so every GetRight is nil, and an
  -- addon adding its own tabs off the same event may not have run yet. Both are settled one
  -- frame later.
  it("re-anchors a frame later, once the bar exists and every other addon has had its turn",
    function()
      GC.AuctionHouseTab.Install() -- nothing measurable yet: array order decides
      local tab = tabButton()
      assert.equal(ah.Tabs[3], tab.points[1][2])

      local foreign = widget("Button", ah)
      ah.Tabs[#ah.Tabs + 1] = foreign
      for index, entry in ipairs(ah.Tabs) do entry.right = index * 100 end
      foreign.right = 900
      runDeferred()

      assert.equal(foreign, tab.points[1][2])
      assert.equal(5, ah.numTabs) -- and the count covers our index again
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

  -- Everything here hangs off the dock, and the pcall that builds it can come back empty.
  -- "We are installed" used to be latched BEFORE that attempt, so one failed build cost the
  -- player the GoldCap tab for the rest of the session: every later visit took the
  -- already-installed early return and tried nothing.
  it("tries again on the next visit when the dock could not be built", function()
    local realCreate = _G.CreateFrame
    _G.CreateFrame = function(_, name)
      if name == "GoldCapAuctionHouseDock" then error("taint") end
      error("nothing else should be built once the dock has failed")
    end

    assert.has_no.errors(function() GC.AuctionHouseTab.Install() end)
    assert.is_nil(dockPanel())
    assert.equal(3, #ah.Tabs) -- no tab of ours on the bar yet

    _G.CreateFrame = realCreate
    GC.AuctionHouseTab.Install()

    assert.is_table(dockPanel())
    assert.equal(4, #ah.Tabs)
  end)

  -- Blizzard's request throttle is one shared budget: while the player is on the default
  -- Create Auction form, GoldCap's background traffic must go quiet. Verified against the same
  -- Blizzard_AuctionHouseFrame.lua the header cites: AuctionHouseFrameDisplayMode has distinct
  -- ItemSell and CommoditiesSell entries (Blizzard's own IsListingAuctions checks exactly these
  -- two plus WoWTokenSell, which the Create Auction form never uses), and SetDisplayMode
  -- resolves a Sell-family request against self.displayMode before this hook ever sees it, so
  -- the predicate reads the RESOLVED field, not the raw call argument.
  describe("PlayerIsPosting", function()
    it("fails open before Install has ever run", function()
      assert.is_false(GC.AuctionHouseTab.PlayerIsPosting())
    end)

    it("fails open right after Install, before any SetDisplayMode call landed", function()
      GC.AuctionHouseTab.Install()
      assert.is_false(GC.AuctionHouseTab.PlayerIsPosting())
    end)

    -- Seen in game: the realm key poll's search made Blizzard's pane open a gear piece's buy
    -- page, and PlayerIsBuying read it as the player mid-purchase -- Auto sat in WAITING with
    -- an empty board until the player pressed Back.
    it("a buy page opened right after the addon's own search does not count as buying", function()
      GC.AuctionHouseTab.Install()
      GC.AuctionHouseTab.NoteAddonSearch(clock)
      clock = clock + 1
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemBuy)
      assert.is_false(GC.AuctionHouseTab.PlayerIsBuying())
      assert.is_false(GC.AuctionHouseTab.PlayerIsBusy())
      -- The player's own click, long after any search of ours, still counts.
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      clock = clock + 10
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.CommoditiesBuy)
      assert.is_true(GC.AuctionHouseTab.PlayerIsBuying())
    end)

    -- The window above is the fallback. On a client whose browse list can be hooked, the
    -- player's own click is the signal: a page that lands without one was opened by a search,
    -- however long that search took to answer -- a queued search answering 20s later used to
    -- read as the player mid-purchase and stop every background sender until Back was pressed.
    --
    -- The fake is Blizzard's own shape (Blizzard_AuctionHouseFrame.lua, Gethe/wow-ui-source live,
    -- read verbatim): SelectBrowseResult opens the page by calling SetDisplayMode as its LAST
    -- line, so the SetDisplayMode hook fires INSIDE it, before SelectBrowseResult's own post-hook
    -- has seen the click. A no-op fake followed by a separate SetDisplayMode had the order the
    -- other way round, and passed while the real client read every clicked page as ours: Auto,
    -- the verify walk and the Sell tab's pricing all carried on under the player's buy page, and
    -- the page sat on "Searching..." for good (seen in game).
    it("tells the player's browse click from a page a slow search opened", function()
      ah.SelectBrowseResult = function(self)
        self:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.CommoditiesBuy)
      end
      GC.AuctionHouseTab.Install()
      GC.AuctionHouseTab.NoteAddonSearch(clock)
      clock = clock + 20
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemBuy)
      assert.is_false(GC.AuctionHouseTab.PlayerIsBuying())
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      -- The player clicks a browse row: Blizzard's list calls SelectBrowseResult, which opens
      -- the page itself.
      clock = clock + 30
      ah:SelectBrowseResult({})
      assert.is_true(GC.AuctionHouseTab.PlayerIsBuying())
      assert.is_true(GC.AuctionHouseTab.PlayerIsBusy())
    end)

    it("is true once Blizzard's own display mode is ItemSell", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemSell)
      assert.is_true(GC.AuctionHouseTab.PlayerIsPosting())
    end)

    it("is true once Blizzard's own display mode is CommoditiesSell", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.CommoditiesSell)
      assert.is_true(GC.AuctionHouseTab.PlayerIsPosting())
    end)

    it("goes false again once the player leaves the sell panel", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemSell)
      assert.is_true(GC.AuctionHouseTab.PlayerIsPosting())
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      assert.is_false(GC.AuctionHouseTab.PlayerIsPosting())
    end)

    it("fails open if Blizzard's own display-mode table ever goes missing", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemSell)
      _G.AuctionHouseFrameDisplayMode = nil
      assert.is_false(GC.AuctionHouseTab.PlayerIsPosting())
    end)
  end)

  -- Same shared-throttle reasoning as PlayerIsPosting, for the other half of Blizzard's own AH:
  -- a browse result the player clicked open (ItemBuy/CommoditiesBuy -- SelectBrowseResult puts
  -- the frame into exactly these two modes, Blizzard_AuctionHouseFrame.lua read verbatim) is a
  -- purchase form the player is one click from confirming, same as Create Auction is.
  describe("PlayerIsBuying", function()
    it("fails open before Install has ever run", function()
      assert.is_false(GC.AuctionHouseTab.PlayerIsBuying())
    end)

    it("fails open right after Install, before any SetDisplayMode call landed", function()
      GC.AuctionHouseTab.Install()
      assert.is_false(GC.AuctionHouseTab.PlayerIsBuying())
    end)

    it("is true once Blizzard's own display mode is ItemBuy", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemBuy)
      assert.is_true(GC.AuctionHouseTab.PlayerIsBuying())
    end)

    it("is true once Blizzard's own display mode is CommoditiesBuy", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.CommoditiesBuy)
      assert.is_true(GC.AuctionHouseTab.PlayerIsBuying())
    end)

    it("goes false again once the player is back on the browse list", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemBuy)
      assert.is_true(GC.AuctionHouseTab.PlayerIsBuying())
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      assert.is_false(GC.AuctionHouseTab.PlayerIsBuying())
    end)

    it("fails open if Blizzard's own display-mode table ever goes missing", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemBuy)
      _G.AuctionHouseFrameDisplayMode = nil
      assert.is_false(GC.AuctionHouseTab.PlayerIsBuying())
    end)
  end)

  -- The player's own search-box activity, tracked by SniperFrame's focus hooks calling
  -- NoteSearchFocus. SendSearchQuery is throttled -- the query the player just typed lands and
  -- gets READ after the box loses focus (they tab away or click a browse row while results are
  -- still streaming in) -- so unfocus alone is not "done reading". A ~10s grace window covers a
  -- normal throttled round trip; `now` is an explicit parameter (default GC.AuctionHouseTab's
  -- own time()) purely so this spec can drive it with a fake clock.
  describe("PlayerIsSearching", function()
    it("is false before the search box has ever been focused", function()
      assert.is_false(GC.AuctionHouseTab.PlayerIsSearching())
    end)

    it("is true while the box is focused", function()
      GC.AuctionHouseTab.NoteSearchFocus(true)
      assert.is_true(GC.AuctionHouseTab.PlayerIsSearching())
    end)

    it("stays true through the grace window after focus is lost", function()
      GC.AuctionHouseTab.NoteSearchFocus(true)
      GC.AuctionHouseTab.NoteSearchFocus(false)
      clock = 1009
      assert.is_true(GC.AuctionHouseTab.PlayerIsSearching(clock))
    end)

    it("goes false once the grace window has passed", function()
      GC.AuctionHouseTab.NoteSearchFocus(true)
      GC.AuctionHouseTab.NoteSearchFocus(false)
      clock = 1011
      assert.is_false(GC.AuctionHouseTab.PlayerIsSearching(clock))
    end)

    it("goes false immediately if the box was never focused again after a previous grace window", function()
      GC.AuctionHouseTab.NoteSearchFocus(true)
      GC.AuctionHouseTab.NoteSearchFocus(false)
      assert.is_true(GC.AuctionHouseTab.PlayerIsSearching(1000))
      assert.is_false(GC.AuctionHouseTab.PlayerIsSearching(1500))
    end)
  end)

  -- One predicate the background tickers in UI/SniperFrame.lua read: the player is busy if
  -- they are posting, buying, or reading their own search -- any one of the three outranks
  -- background traffic for the shared request throttle.
  -- Another addon's auction-house tab. LibAHTab clears AuctionHouseFrame.displayMode to nil
  -- when one of its tabs is selected (LibAHTab.lua's SetSelected, read verbatim), which is a
  -- state Blizzard's own tabs never leave the frame in -- every one of theirs sets a mode. So
  -- "no display mode, and our own dock is not the thing on screen" means someone else's panel
  -- owns the auction house.
  --
  -- It has to count as busy. The player posting through Auctionator's Selling tab could not
  -- click Post: it greyed out and only flickered back occasionally, because GoldCap's own
  -- background traffic -- the verify walk and the watch loop, neither of which Auto gates --
  -- was spending the auction house's shared request budget the whole time. Reported in-game
  -- 2026-08-28. PlayerIsPosting never saw it: it reads Blizzard's display mode, and Blizzard
  -- had no idea a sell form was on screen.
  describe("PlayerIsUsingAnotherTab", function()
    before_each(function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
    end)

    it("is false while one of Blizzard's own panels is up", function()
      assert.is_false(GC.AuctionHouseTab.PlayerIsUsingAnotherTab())
    end)

    it("is true once the display mode is cleared and our dock is not what replaced it", function()
      ah.displayMode = nil
      assert.is_true(GC.AuctionHouseTab.PlayerIsUsingAnotherTab())
    end)

    it("is false when the panel with no display mode behind it is our own", function()
      ah.displayMode = nil
      dockPanel():Show()
      assert.is_false(GC.AuctionHouseTab.PlayerIsUsingAnotherTab())
    end)

    it("is false when there is no auction house to read", function()
      _G.AuctionHouseFrame = nil
      assert.is_false(GC.AuctionHouseTab.PlayerIsUsingAnotherTab())
    end)


    it("makes the background traffic yield", function()
      ah.displayMode = nil
      assert.is_true(GC.AuctionHouseTab.PlayerIsBusy())
    end)
  end)

  -- The player's own browse results (a plain search like "Teebu") are theirs. The book pass
  -- and the key polls (SearchForItemKeys, both the Items board's and the BUY tab's floor
  -- refresh) all answer through the same GetBrowseResults() buffer Blizzard's Buy pane reads
  -- from, so while that pane is on screen and GoldCap's own window is not, nothing of ours may
  -- touch it. Reported in-game 2026-09-22: with GoldCap closed, a player's own "Teebu" search
  -- on Blizzard's Buy tab turned into the alphabetical "everything" list after ~10s and kept
  -- jumping, because none of the other predicates fire merely from Buy being the visible pane.
  describe("PlayerIsBrowsing", function()
    it("fails open before Install has ever run", function()
      assert.is_false(GC.AuctionHouseTab.PlayerIsBrowsing())
    end)

    it("is true on the Buy display mode with our dock and our window both hidden", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      assert.is_true(GC.AuctionHouseTab.PlayerIsBrowsing())
    end)

    it("is false on the Buy display mode when our own dock is shown", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      dockPanel():Show()
      assert.is_false(GC.AuctionHouseTab.PlayerIsBrowsing())
    end)

    -- The auction house opens on Buy, and autoOpen (on by default) shows the GoldCap window
    -- floating beside it. Reading that as "the player is browsing" switched the whole addon
    -- off for the entire visit (confirmed in game 2026-09-22): the window was open and nothing
    -- in it ever moved.
    it("is false on the Buy display mode while the GoldCap window is shown floating", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      GC.Sniper.shown = true
      assert.is_false(GC.AuctionHouseTab.PlayerIsBrowsing())
    end)

    it("fails open when the window cannot be asked whether it is shown", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      GC.Sniper.IsWindowShown = nil
      assert.is_false(GC.AuctionHouseTab.PlayerIsBrowsing())
    end)

    it("is false on the ItemSell display mode", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemSell)
      assert.is_false(GC.AuctionHouseTab.PlayerIsBrowsing())
    end)

    it("is false on the CommoditiesSell display mode", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.CommoditiesSell)
      assert.is_false(GC.AuctionHouseTab.PlayerIsBrowsing())
    end)

    it("is false when there is no auction house frame at all", function()
      _G.AuctionHouseFrame = nil
      assert.is_false(GC.AuctionHouseTab.PlayerIsBrowsing())
    end)
  end)

  -- Final review S1 (b). With the window floating over Blizzard's Buy pane nothing counts as the
  -- player browsing (PlayerIsBrowsing above: the auction house opens that way, and reading it as
  -- busy stood the whole addon down). But once the player has sent a browse query of their own,
  -- that pane is showing THEIR results, and a keys batch or a pass page replaces them. Told apart
  -- from ours by a post-hook on C_AuctionHouse.SendBrowseQuery and a flag our own sender sets.
  describe("PlayerOwnsBrowseList", function()
    local sent, told
    before_each(function()
      sent, told = 0, 0
      _G.C_AuctionHouse = {
        SendBrowseQuery = function() sent = sent + 1 end,
        SearchForFavorites = function() end,
      }
      GC.Sniper._OnPlayerBrowse = function() told = told + 1 end
      -- Blizzard's two player-only ways into SearchForFavorites (follow-up 1, below).
      ah.SearchBar = { StartFavoritesSearch = function() _G.C_AuctionHouse.SearchForFavorites({}) end }
      ah.SetBrowseSortOrder = function() end
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      GC.Sniper.shown = true -- floating over the pane, the default visit
    end)
    after_each(function() _G.C_AuctionHouse = nil end)

    it("is false on the Buy pane before the player has searched", function()
      assert.is_false(GC.AuctionHouseTab.PlayerOwnsBrowseList())
      assert.is_false(GC.AuctionHouseTab.PlayerIsBusy(clock))
    end)

    -- The auction house lists the player's favourites as it opens (Blizzard_AuctionHouseFrame's
    -- OnShow: QueryAll -> C_AuctionHouse.SearchForFavorites). That is not a search of theirs.
    it("is not tripped by the favourites list the auction house opens with", function()
      _G.C_AuctionHouse.SearchForFavorites({})
      assert.is_false(GC.AuctionHouseTab.PlayerOwnsBrowseList())
    end)

    it("is true once the player's own browse query has gone out, while the pane is shown", function()
      _G.C_AuctionHouse.SendBrowseQuery({ searchString = "ore" })
      assert.equal(1, sent)
      assert.is_true(GC.AuctionHouseTab.PlayerOwnsBrowseList())
      assert.equal(1, told) -- the Sniper gives up a keys batch out under it
    end)

    it("is not tripped by a browse query of ours", function()
      GC.AuctionHouseTab.addonBrowse = true
      _G.C_AuctionHouse.SendBrowseQuery({})
      GC.AuctionHouseTab.addonBrowse = false
      assert.is_false(GC.AuctionHouseTab.PlayerOwnsBrowseList())
      assert.equal(0, told)
      -- ...and the player's next one still is.
      _G.C_AuctionHouse.SendBrowseQuery({})
      assert.is_true(GC.AuctionHouseTab.PlayerOwnsBrowseList())
    end)

    it("is false while another pane, or our own dock, is up", function()
      _G.C_AuctionHouse.SendBrowseQuery({})
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.CommoditiesSell)
      assert.is_false(GC.AuctionHouseTab.PlayerOwnsBrowseList())
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      assert.is_true(GC.AuctionHouseTab.PlayerOwnsBrowseList())
      dockPanel():Show()
      assert.is_false(GC.AuctionHouseTab.PlayerOwnsBrowseList())
    end)

    it("is reset when the auction house closes", function()
      _G.C_AuctionHouse.SendBrowseQuery({})
      GC.AuctionHouseTab.OnAuctionHouseClosed()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.CommoditiesSell)
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      assert.is_false(GC.AuctionHouseTab.PlayerOwnsBrowseList())
    end)

    -- Follow-up 1. The Favorites button and a sort on the list the pane shows reach the auction
    -- house through SearchForFavorites (Blizzard_AuctionHouseSearchBar.lua's StartFavoritesSearch;
    -- Blizzard_AuctionHouseFrame.lua's SetBrowseSortOrder -> SetSortOrder -> QueryAll), not
    -- SendBrowseQuery: the player reading their favourites had them replaced all the same. Those
    -- two player-only entries count; the list the auction house shows by itself as it opens
    -- (OnShow -> QueryAll) does not.
    it("counts the player's own Favorites search, and a sort on the list", function()
      assert.is_false(GC.AuctionHouseTab.PlayerOwnsBrowseList())

      ah.SearchBar:StartFavoritesSearch()
      assert.is_true(GC.AuctionHouseTab.PlayerOwnsBrowseList())
      assert.equal(1, told)

      GC.AuctionHouseTab.OnAuctionHouseClosed()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.CommoditiesSell)
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      ah:SetBrowseSortOrder(1)
      assert.is_true(GC.AuctionHouseTab.PlayerOwnsBrowseList())
    end)

    it("hooks the query once however many times the auction house opens", function()
      GC.AuctionHouseTab.Install()
      GC.AuctionHouseTab.Install()
      _G.C_AuctionHouse.SendBrowseQuery({})
      assert.equal(1, sent)
      assert.equal(1, told)
    end)
  end)

  describe("PlayerIsBusy", function()
    -- Also the "nothing has been selected yet" case for PlayerIsUsingAnotherTab: an auction
    -- house that has chosen nothing has no display mode either, and reading THAT as "the player
    -- is busy" would silence the sniper for a whole session.
    it("is false when none of the five are true", function()
      assert.is_false(GC.AuctionHouseTab.PlayerIsBusy())
    end)

    it("is true while posting", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemSell)
      assert.is_true(GC.AuctionHouseTab.PlayerIsBusy())
    end)

    it("is true while buying", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.ItemBuy)
      assert.is_true(GC.AuctionHouseTab.PlayerIsBusy())
    end)

    it("is true while searching", function()
      GC.AuctionHouseTab.NoteSearchFocus(true)
      assert.is_true(GC.AuctionHouseTab.PlayerIsBusy())
    end)

    it("is true while browsing Blizzard's own Buy pane with our window closed", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      assert.is_true(GC.AuctionHouseTab.PlayerIsBusy())
    end)

    -- The default visit: the auction house opens on Buy and the window opens floating with it.
    -- Every background sender reads this predicate, so a true here is the whole addon idle.
    it("is false on Blizzard's Buy pane while the GoldCap window is shown floating", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      GC.Sniper.shown = true
      assert.is_false(GC.AuctionHouseTab.PlayerIsBusy(clock))
    end)

    it("stays false as time passes with the window up over the Buy pane", function()
      GC.AuctionHouseTab.Install()
      ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
      GC.Sniper.shown = true
      for _ = 1, 3 do
        clock = clock + 60
        assert.is_false(GC.AuctionHouseTab.PlayerIsBusy(clock))
      end
    end)

    it("is false while the window is docked in our own tab", function()
      GC.AuctionHouseTab.Install()
      local tab = tabButton()
      tab.scripts.OnClick(tab)
      assert.is_true(GC.Sniper.IsWindowShown())
      assert.is_false(GC.AuctionHouseTab.PlayerIsBusy(clock))
    end)
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

  -- installSearchHooks' own focus hooks are the only place NoteSearchFocus can be called from
  -- (there's no other trigger for "the player's search box gained/lost focus" in the addon).
  it("[wiring] the search box focus hooks in SniperFrame.lua record focus here", function()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    assert.is_truthy(text:find("pcall(GC.AuctionHouseTab.NoteSearchFocus, true)", 1, true))
    assert.is_truthy(text:find("pcall(GC.AuctionHouseTab.NoteSearchFocus, false)", 1, true))
  end)

  -- The one moment the addon introduces the Companion on its own: the player has just
  -- opened GoldCap's own tab and there are no prices at all, so nothing on the board
  -- works yet. Once ever per save -- the flag persists -- never again after that,
  -- whatever the origin later becomes.
  it("offers the Companion once ever when the tab first opens with no prices", function()
    GC.db = {}
    GC.Data = { OriginState = function() return "none" end }
    local shows = 0
    GC.CompanionUI = { Show = function() shows = shows + 1 end }
    GC.AuctionHouseTab.Install()
    local tab = tabButton()
    tab.scripts.OnClick(tab)
    assert.equal(1, shows)
    assert.is_true(GC.db.companionIntroShown)

    ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
    tab.scripts.OnClick(tab) -- the next visit stays quiet
    assert.equal(1, shows)
  end)

  it("stays quiet when prices already exist, and does not trip over a missing db", function()
    GC.db = {}
    GC.Data = { OriginState = function() return "manual" end }
    local shows = 0
    GC.CompanionUI = { Show = function() shows = shows + 1 end }
    GC.AuctionHouseTab.Install()
    local tab = tabButton()
    tab.scripts.OnClick(tab)
    assert.equal(0, shows)
    assert.is_nil(GC.db.companionIntroShown) -- the one-shot is spent only when it fires

    GC.db = nil -- a click before SavedVariables load must not error or burn the shot
    ah:SetDisplayMode(_G.AuctionHouseFrameDisplayMode.Buy)
    tab.scripts.OnClick(tab)
    assert.equal(0, shows)
  end)

end)
