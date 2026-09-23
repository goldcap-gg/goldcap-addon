local _, GC = ...

-- An embedded GoldCap tab on Blizzard's own Auction House window.
--
-- Owner-approved 2026-08-17, superseding this file's earlier entry-point-only design (which
-- toggled the floating window and deliberately avoided Blizzard's tab bookkeeping). The
-- earlier taint fear was re-examined against the actual source before this shipped --
-- Blizzard_AuctionHouseFrame.lua, Gethe/wow-ui-source (live), read verbatim:
--
--   * SetDisplayMode(mode) compares modes BY IDENTITY against its own tables, hides every
--     subframe not in the target mode, then `for i = 1, #mode do self[mode[i]]:Show() end`.
--     Our mode is a fresh EMPTY table: no identity ever matches (all their panels hide) and
--     the show loop is a no-op. Nothing of ours is indexed by their code beyond that.
--   * `numTabs`/`selectedTab` (PanelTemplates_SetNumTabs / PanelTemplates_SetTab) feed
--     insecure UI code only -- UpdateTitle is the lone reader -- never a protected path. Our
--     own purchase calls are already addon code; they are gated on HARDWARE input, not on
--     taint, and registering a tab changes nothing about that.
--   * This registration pattern (append to ah.Tabs, SetNumTabs, tabsForDisplayMode) is what
--     Auctionator has shipped at scale for years.
--
-- With the tab registered, the ENGINE does the whole dance: clicking our tab makes Blizzard
-- hide its panels and paint our tab selected; clicking Buy/Sell/Auctions restores their
-- panels and deselects ours -- no bookkeeping of "what was showing before" on our side, ever.
-- The addon window is reparented into a dock panel over the vacated content area
-- (GC.Sniper.SetDocked), and undocked back to a floating window when the auction house
-- closes. `/goldcap` away from an auctioneer keeps the floating window exactly as before.
--
-- Every step stays pcall-guarded: this runs synchronously inside
-- GC.Sniper.OnAuctionHouseShow, and an error here would abort the rest of that function --
-- no ticker, no Auto, no auto-open -- which is a far worse failure than a missing tab.
GC.AuctionHouseTab = {}

local tab, dock, installed, hookedTabs = nil, nil, false, false
local registered = false
-- Set when the tab was created through LibAHTab-1-0 (see libAHTab below) rather than built
-- here: the library then owns its position, its click, and its visibility.
local libRegistered = false
local LIB_TAB_ID = "GoldCap"
-- The Blizzard mode last recorded by the SetDisplayMode hook below -- nil until the hook has
-- fired at least once. Read by PlayerIsPosting().
local currentMode = nil
-- When this addon last sent a per-item search of its own (see NoteAddonSearch), and whether
-- the buy page Blizzard is showing was opened by that search rather than by the player.
local addonSearchAt = nil
local provokedBuyMode = false
local PROVOKED_PAGE_SECONDS = 3
-- When the player last clicked a browse row (AuctionHouseFrameMixin:SelectBrowseResult, the
-- one path Blizzard's own list uses to open a purchase page -- Blizzard_AuctionHouseFrame.lua
-- and Blizzard_AuctionHouseBrowseResultsFrame.lua, read verbatim). A buy page that lands
-- without that click in front of it was opened by a search -- ours or another addon's --
-- however long ago the search went out. The 3-second window above stays as the fallback for a
-- client where the method could not be hooked.
local playerSelectedAt = nil
local selectHooked = false
-- The GoldCap display mode: identity is the contract (Blizzard compares modes with `==`),
-- and empty is the content (their show loop iterates it and finds nothing to show).
local DISPLAY_MODE = {}
-- Final review S1 (b): whether a browse query that was not ours has gone out this visit -- the
-- player's own search, a category click, a sort (Blizzard_AuctionHouseFrame.lua's
-- SendBrowseQueryInternal is the one place all of them reach C_AuctionHouse.SendBrowseQuery),
-- another addon's, or the player's own favourites search (installFavouritesHooks). Read by
-- PlayerOwnsBrowseList, cleared when the auction house closes.
local playerBrowsed = false
local browseHooked, favouritesHooked = false, false
-- Set by our own sender for the length of its own SendBrowseQuery call (UI/SniperFrame.lua's book
-- pass), so the hook below does not count it. A field, so that sender can reach it.
GC.AuctionHouseTab.addonBrowse = false

-- Blizzard's tabs are `AuctionHouseFrame.Tabs` on current builds and globals named
-- AuctionHouseFrameTab1..N on older ones. Walk whichever exists; the last one is the anchor.
local function blizzardTabs(ah)
  local found = {}
  local index = 1
  while true do
    local candidate = (ah.Tabs and ah.Tabs[index]) or _G["AuctionHouseFrameTab" .. index]
    if not candidate then break end
    found[#found + 1] = candidate
    index = index + 1
  end
  return found
end

-- Where our tab sits on the bar: beside whatever is furthest RIGHT right now and is not us.
-- Position, not array order -- another addon's tab can be created after ours and still anchor
-- itself to a tab BEFORE ours. Auctionator's four do exactly that (they hang off Blizzard's
-- last), so when ours was built first both addons anchored to the same tab and ours drew
-- underneath: the bar showed Buy / Sell / Auctions and Auctionator's four, and no GoldCap
-- anywhere (reported in-game 2026-08-28). Which of us gets there first is a load-order race
-- nobody wins reliably, so this is recomputed on EVERY auction house visit rather than pinned
-- once at install.
--
-- Array order is the fallback for a bar that has not been laid out yet (GetRight is nil until
-- it has), which is exactly the state at the first install of a session.
local function anchorTab(ah)
  if not tab then return end
  local rightmost, rightmostEdge, lastInArray
  for _, candidate in ipairs(blizzardTabs(ah)) do
    if candidate ~= tab then
      lastInArray = candidate
      local ok, edge = pcall(candidate.GetRight, candidate)
      if ok and type(edge) == "number" and (not rightmostEdge or edge > rightmostEdge) then
        rightmost, rightmostEdge = candidate, edge
      end
    end
  end
  local anchor = rightmost or lastInArray
  pcall(function()
    tab:ClearAllPoints()
    if anchor then
      -- Blizzard's own tabs sit at -15, but our resized button rides visibly onto the tab
      -- before it at that offset (seen in game 2026-08-17) -- ease it out to -10.
      tab:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -10, 0)
    else
      tab:SetPoint("TOPLEFT", ah, "BOTTOMLEFT", 11, 2)
    end
  end)
end

-- Anchoring twice: once now, once a frame later. The FIRST auction house of a session is the
-- case the inline pass cannot answer -- nothing on the bar has been laid out when
-- AUCTION_HOUSE_SHOW fires, so every GetRight is nil and only array order is available, and an
-- addon that adds its own tabs off the same event may not have run yet. C_Timer.After(0) lands
-- after both: every handler for this event, and the layout pass.
local function scheduleAnchor(ah)
  anchorTab(ah)
  if not (_G.C_Timer and _G.C_Timer.After) then return end
  pcall(_G.C_Timer.After, 0, function()
    anchorTab(ah)
    -- Reclaim the tab count in the same breath. Another addon setting it to ITS OWN total
    -- after we set ours leaves our index outside frame.numTabs, and Blizzard's
    -- PanelTemplates_UpdateTabs then walks straight past our tab.
    pcall(function()
      if registered and ah.Tabs then PanelTemplates_SetNumTabs(ah, #ah.Tabs) end
    end)
  end)
end

local function buildTab(ah)
  local built
  pcall(function()
    built = CreateFrame("Button", "GoldCapAuctionHouseTab", ah, "AuctionHouseFrameTabTemplate")
  end)
  if built then
    pcall(function() built:SetText("GoldCap") end)
    -- The template's own OnShow already resized -- at creation, with EMPTY text. Re-run the
    -- exact call PanelTabButtonMixin:OnShow makes (same paddings from the parent), now that
    -- the label exists. This button only.
    pcall(function() PanelTemplates_TabResize(built, ah.tabPadding, nil, ah.minTabWidth, ah.maxTabWidth) end)
    return built, true
  end
  -- A client build without the template falls back to the addon's own button as a plain
  -- entry point -- and must NOT register: PanelTemplates_SetTab reaches into template
  -- textures this button does not have.
  if not (GC.Theme and GC.Theme.Button) then return nil, false end
  built = GC.Theme.Button(ah, "ghost")
  built:SetSize(80, 22)
  built:SetLabel("GoldCap")
  return built, false
end

-- Docking is driven off the dock's own visibility rather than from each call site that changes
-- it. On the LibAHTab path below the library owns Show/Hide -- it hides every registered tab's
-- frame whenever any other tab is picked -- so hooking the frame is the only way to hear about
-- it; on the native path our own showDock/hideDock trip the same hooks. One rule, both paths.
-- The one self-initiated Companion intro: the player has just opened GoldCap's own tab and
-- there are no prices at all, so nothing on the board can work yet -- the exact moment the
-- Companion's pitch answers a question the player is actually asking. Once ever per save
-- (the flag persists in SavedVariables), and only while the save still has no import at
-- all; a click before SavedVariables load neither errors nor spends the shot.
local function maybeShowCompanionIntro()
  local db = GC.db
  if not db or db.companionIntroShown then return end
  if not (GC.Data and GC.Data.OriginState) or GC.Data.OriginState() ~= "none" then return end
  if not (GC.CompanionUI and GC.CompanionUI.Show) then return end
  db.companionIntroShown = true
  pcall(GC.CompanionUI.Show)
end

local function attachWindow()
  if not dock then return end
  if GC.Sniper and GC.Sniper.SetDocked then
    pcall(GC.Sniper.SetDocked, dock)
  end
  maybeShowCompanionIntro()
end

local function detachWindow()
  -- The window is a CHILD of the dock, so visually it is already gone -- but its own shown
  -- flag would stay true, and everything that reads IsWindowShown (Auto's pause causes, the
  -- Sell tab badge) would believe the player is still looking at it. Hide it for real.
  if GC.Sniper and GC.Sniper.IsWindowShown and GC.Sniper.IsWindowShown()
      and GC.Sniper.Toggle then
    pcall(GC.Sniper.Toggle)
  end
end

local function showDock()
  if dock then dock:Show() end
end

local function hideDock()
  if dock and dock:IsShown() then dock:Hide() end
end

-- One hook, both directions on the native path: our mode up -> show the dock, any other mode
-- -> hide it. Their OnClick is a template script we must not replace, so hook the frame method
-- it calls. On the LibAHTab path the library already hides every registered tab's frame -- ours
-- included -- whenever a mode with content is set, so the hook only records the mode there:
-- doing it twice would have us hide the dock in the same breath the library shows it.
local function installSetDisplayModeHook(ah)
  if hookedTabs or not ah.SetDisplayMode then return end
  hookedTabs = true
  if type(ah.SelectBrowseResult) == "function" then
    -- SelectBrowseResult opens the page by calling SetDisplayMode as its last line
    -- (Blizzard_AuctionHouseFrame.lua, read verbatim), and a post-hook runs only once the whole
    -- function has returned -- so the SetDisplayMode hook below has already judged the page
    -- this click opened, before the click was stamped, and judged it ours. Every page the player
    -- clicked open read as provoked: PlayerIsBuying stayed false under their own buy page, and
    -- the background senders it gates wiped that page's results mid-read ("Searching..." for
    -- good, seen in game). The click is the proof, so it settles the page it opened.
    selectHooked = pcall(hooksecurefunc, ah, "SelectBrowseResult", function()
      playerSelectedAt = time()
      provokedBuyMode = false
    end) and true or false
  end
  pcall(hooksecurefunc, ah, "SetDisplayMode", function(_, mode)
    -- SetDisplayMode itself resolves a Sell-family request (ItemSell/CommoditiesSell/
    -- WoWTokenSell) against whichever SellFrame actually has an item loaded before it stores
    -- self.displayMode (Blizzard_AuctionHouseFrame.lua, read verbatim) -- so read the RESOLVED
    -- field back off `ah` here, hooksecurefunc runs after the original, rather than trust the
    -- raw `mode` argument this hook was called with.
    currentMode = ah.displayMode
    -- An item page the ADDON opened is not the player buying. A search this addon sends for
    -- one item (the verify walk, a Check, the Sell tab's quote, the realm key poll) makes
    -- Blizzard's own pane jump to that item's purchase page -- seen in game as a page for a
    -- gear piece nobody clicked, spinner and all. PlayerIsBuying then read that page as the
    -- player mid-purchase and held every background sender, Auto's scan included, until the
    -- player happened to press Back: "AUTO" lit, nothing scanning, an empty board. A buy mode
    -- that lands within moments of our own search is ours; the player's own click on a browse
    -- row is the one that arrives with no search of ours in front of it.
    local modes = _G.AuctionHouseFrameDisplayMode
    local buyMode = modes and (currentMode == modes.ItemBuy or currentMode == modes.CommoditiesBuy)
    if not buyMode then
      provokedBuyMode = false
    elseif selectHooked then
      provokedBuyMode = not (playerSelectedAt ~= nil and (time() - playerSelectedAt) <= 1)
    else
      provokedBuyMode = addonSearchAt ~= nil and (time() - addonSearchAt) <= PROVOKED_PAGE_SECONDS
    end
    if libRegistered then return end
    if mode == DISPLAY_MODE then
      showDock()
    else
      hideDock()
    end
  end)
end

-- LibAHTab-1-0 is the shared registry for auction-house tabs that AuctionHouseFrame.Tabs is
-- not. Auctionator embeds it, and its tabs live nowhere we could ever have found them: not in
-- ah.Tabs, not among the auction house's children, but in the library's own chain hanging off
-- a root frame of its own -- and walking UIParent to look for them is not allowed at all (the
-- engine refuses an addon access to protected frames mid-walk). So two addons each anchoring
-- to "the last tab I can see" both land on Auctions, and one draws underneath the other: seven
-- tabs on the bar and no GoldCap, reported in-game 2026-08-28. Our tab WAS there, shown,
-- exactly under Auctionator's Shopping.
--
-- Registering through the library is the fix, not a workaround: it chains our tab after every
-- other tab it owns, hides the other tabs' frames when ours is picked and ours when theirs is,
-- deselects the auction house's own tabs, and sets the title. Source read verbatim from
-- Auctionator/Libs_ModernAH/LibAHTab/LibAHTab.lua (version 4).
--
-- Two paths, and only because the library is not ours to require: with no LibAHTab loaded
-- (nobody on the machine embeds it) the native tab below is the one that works, and it is what
-- shipped. Returns the library only if it can actually take a tab.
local function libAHTab()
  local LibStub = _G.LibStub
  if type(LibStub) ~= "function" and type(LibStub) ~= "table" then return nil end
  local ok, lib = pcall(LibStub, "LibAHTab-1-0", true)
  if not ok or type(lib) ~= "table" then return nil end
  if type(lib.CreateTab) ~= "function" or type(lib.GetButton) ~= "function" then return nil end
  return lib
end

-- A post-hook on C_AuctionHouse.SendBrowseQuery, the same kind Core/PurchaseCapture.lua hangs on
-- the purchase calls: it observes a query and cannot make or change one. Our own sends are told
-- apart by GC.AuctionHouseTab.addonBrowse, which the hook consumes. Deliberately NOT on
-- C_AuctionHouse.SearchForFavorites: the auction house lists the favourites itself every time it
-- opens (Blizzard_AuctionHouseFrame.lua's OnShow -> QueryAll), and counting that as the player's
-- search would hold every browse writer back for the whole of every visit. The player's own
-- favourites search is caught where only the player reaches it (installFavouritesHooks below).
local function installBrowseHook()
  if browseHooked then return end
  local api = _G.C_AuctionHouse
  if not (api and type(api.SendBrowseQuery) == "function" and type(hooksecurefunc) == "function") then
    return
  end
  browseHooked = pcall(hooksecurefunc, api, "SendBrowseQuery", function()
    if GC.AuctionHouseTab.addonBrowse then
      GC.AuctionHouseTab.addonBrowse = false
      return
    end
    GC.AuctionHouseTab.NotePlayerBrowse()
  end) and true or false
end

-- Follow-up 1: the player's own ways into C_AuctionHouse.SearchForFavorites, which the hook above
-- does not see. Blizzard_AuctionHouseSearchBar.lua's Favorites button calls the search bar's
-- StartFavoritesSearch, and a sort on the list the Buy pane shows goes through the frame's
-- SetBrowseSortOrder (SetSortOrder -> QueryAll for the favourites list, SendBrowseQueryInternal
-- otherwise) -- both read verbatim, and both reached only from the player's click. The favourites
-- list the auction house shows by itself as it opens (OnShow -> QueryAll) passes through neither,
-- so it still does not count. Post-hooks on the frames' own methods, like the SetDisplayMode one.
local function installFavouritesHooks(ah)
  if favouritesHooked or type(hooksecurefunc) ~= "function" then return end
  local bar = ah.SearchBar
  if not (bar and type(bar.StartFavoritesSearch) == "function"
      and type(ah.SetBrowseSortOrder) == "function") then
    return
  end
  local barHooked = pcall(hooksecurefunc, bar, "StartFavoritesSearch", function()
    GC.AuctionHouseTab.NotePlayerBrowse()
  end)
  local sortHooked = pcall(hooksecurefunc, ah, "SetBrowseSortOrder", function()
    GC.AuctionHouseTab.NotePlayerBrowse()
  end)
  favouritesHooked = barHooked or sortHooked
end

-- The player (or another addon) just sent a browse query. The Sniper gives up a keys batch still
-- out under it: that batch's answer went with it, and the answer coming is not the batch's.
function GC.AuctionHouseTab.NotePlayerBrowse()
  playerBrowsed = true
  local sniper = GC.Sniper
  if sniper and sniper._OnPlayerBrowse then pcall(sniper._OnPlayerBrowse) end
end

function GC.AuctionHouseTab.Install()
  -- First, and on every visit until it takes: it needs no auction house frame, only the API.
  installBrowseHook()
  local ah = _G.AuctionHouseFrame
  if not ah or not CreateFrame then return end
  installFavouritesHooks(ah)
  if installed then
    -- Every visit, not just the first: the bar can have grown since we were built. See
    -- anchorTab for the collision this exists to get out of. The library owns the position of
    -- a tab it created, so this is the native path's business only.
    if not libRegistered then scheduleAnchor(ah) end
    return
  end

  -- The content host, built FIRST: the window docks INTO it (SetDocked), so one Show/Hide
  -- moves everything -- and LibAHTab's CreateTab takes the frame its tab shows as an argument,
  -- so on that path the dock has to exist before the tab does. Anchors leave the title bar
  -- above and the money strip below visible: both live outside the display-mode lists and stay
  -- useful.
  pcall(function()
    dock = CreateFrame("Frame", "GoldCapAuctionHouseDock", ah)
    dock:SetPoint("TOPLEFT", 7, -28)
    dock:SetPoint("BOTTOMRIGHT", -7, 32)
    dock:Hide()
  end)
  -- The "we are built" latch is set here, not above: everything below hangs off this dock, and
  -- the pcall that builds it can come back empty (another addon's taint on the auction house
  -- frame, a name collision). Latching first meant one failed build cost the player the GoldCap
  -- tab for the whole session -- every later visit took the early return above and tried
  -- nothing. Now a visit that could not build it simply tries again on the next one.
  if not dock then return end
  installed = true

  if dock.HookScript then
    -- Whoever changes the dock's visibility -- our own tab, the library on somebody else's tab,
    -- Blizzard hiding it with the rest of a display mode -- the window follows.
    pcall(dock.HookScript, dock, "OnShow", attachWindow)
    pcall(dock.HookScript, dock, "OnHide", detachWindow)
  end

  local lib = libAHTab()
  if lib then
    local ok = pcall(lib.CreateTab, lib, LIB_TAB_ID, dock, "GoldCap")
    if ok then
      local gotButton, button = pcall(lib.GetButton, lib, LIB_TAB_ID)
      tab = gotButton and button or nil
      libRegistered = tab ~= nil
    end
  end

  if libRegistered then
    -- Everything else the native path sets up below -- our own OnClick, the anchor, the
    -- display-mode registration -- is the library's job now, and doing it twice is how two
    -- owners of one tab disagree. The SetDisplayMode hook still goes in: PlayerIsPosting and
    -- PlayerIsBuying read the mode it records, on every path.
    installSetDisplayModeHook(ah)
    return
  end

  local native
  tab, native = buildTab(ah)
  if not tab then return end
  tab.displayMode = DISPLAY_MODE

  if native then
    -- The registration the header explains: with these writes the engine owns tab selection,
    -- panel hiding and restoration end to end. PanelTabButtonTemplate itself carries
    -- parentArray="Tabs" (SharedUIPanelTemplates.xml:905, read verbatim), so CreateFrame has
    -- ALREADY appended this button to ah.Tabs -- the first shipped version inserted it a
    -- second time, which made "the last tab" the button itself, turned the anchor below into
    -- an anchor-to-self error swallowed by pcall, and rendered NO tab at all. Register only
    -- what the template did not do: the count and the display-mode lookup.
    pcall(function()
      PanelTemplates_SetNumTabs(ah, #ah.Tabs)
      ah.tabsForDisplayMode = ah.tabsForDisplayMode or {}
      for index, candidate in ipairs(ah.Tabs) do
        if candidate == tab then
          ah.tabsForDisplayMode[DISPLAY_MODE] = index
          break
        end
      end
    end)
    registered = true
  end

  -- Ours is already in ah.Tabs (see above), and a frame cannot anchor to itself -- anchorTab
  -- skips it and runs again a frame later, and on every later visit.
  scheduleAnchor(ah)

  tab:SetScript("OnClick", function()
    local frame = _G.AuctionHouseFrame
    if not frame then return end
    if registered and frame.SetDisplayMode then
      -- The hook below is what shows the dock, so a mode change from ANY source behaves the
      -- same. SetTitle runs after: SetDisplayMode's own UpdateTitle only knows Blizzard's
      -- three tab indices and would have fallen back to the Buy title.
      pcall(frame.SetDisplayMode, frame, DISPLAY_MODE)
      pcall(function() frame:SetTitle("GoldCap") end)
    else
      -- Fallback button on a template-less client: plain entry point, old behaviour.
      if GC.Sniper and GC.Sniper.Toggle then GC.Sniper.Toggle() end
    end
  end)

  installSetDisplayModeHook(ah)
end

-- True while Blizzard's own auction house is showing the Create Auction form (the ItemSell or
-- CommoditiesSell display mode) -- i.e. while the player could click Create Auction at any
-- moment. Blizzard throttles every auction-house request through one shared budget, and
-- GoldCap's background traffic (auto-scan, the background verify walk, the watch loop's live
-- polls -- see PlayerIsBusy below and the gated tickers it feeds in UI/SniperFrame.lua) must
-- yield to it: a player's own click outranks all of it. Fails open (false) whenever the hook
-- has not recorded a mode yet or Blizzard's own mode table is missing -- a broken detector
-- must never permanently silence the sniper.
function GC.AuctionHouseTab.PlayerIsPosting()
  if not currentMode then return false end
  local modes = _G.AuctionHouseFrameDisplayMode
  if not modes then return false end
  return currentMode == modes.ItemSell or currentMode == modes.CommoditiesSell
end

-- True while Blizzard's own auction house is showing a purchase form for a browse result the
-- player clicked open -- the ItemBuy or CommoditiesBuy display mode. Verified against the same
-- Blizzard_AuctionHouseFrame.lua (Gethe/wow-ui-source, live) the header cites:
-- AuctionHouseFrameMixin:SelectBrowseResult (the handler for clicking a browse row) sets
-- self.displayMode to exactly AuctionHouseFrameDisplayMode.CommoditiesBuy or .ItemBuy depending
-- on the item, distinct from .Buy (the browse list itself, read verbatim) and from the
-- Sell-family modes PlayerIsPosting already covers. Same fail-open shape and for the same
-- reason: a broken detector must never permanently silence the sniper.
function GC.AuctionHouseTab.PlayerIsBuying()
  if not currentMode then return false end
  local modes = _G.AuctionHouseFrameDisplayMode
  if not modes then return false end
  if provokedBuyMode then return false end -- our own search opened this page, see the hook
  return currentMode == modes.ItemBuy or currentMode == modes.CommoditiesBuy
end

-- Every per-item search this addon sends passes through here first (SniperFrame's driver,
-- the realm key poll, SellFrame's quote driver), so the SetDisplayMode hook can tell a page
-- our search opened from one the player clicked open. `now` is for specs.
function GC.AuctionHouseTab.NoteAddonSearch(now)
  addonSearchAt = now or time()
end

-- Test seam and a hand-hold for a client whose SelectBrowseResult could not be hooked: the
-- player just clicked a browse row.
function GC.AuctionHouseTab.NotePlayerSelected(now)
  playerSelectedAt = now or time()
end

-- The player's own search-box activity. Called from UI/SniperFrame.lua's installSearchHooks on
-- every focus change of Blizzard's own search box, so this module -- the one place that already
-- tracks what the player is doing on the default AH panes -- can answer for this too.
local searchFocused = false
local searchLostFocusAt = nil
-- C_AuctionHouse.SendSearchQuery is throttled: the query the player just typed lands and gets
-- READ after the box loses focus (tabbing away, or clicking a browse row, while results are
-- still streaming in) -- so treating "unfocused" as "done reading" the instant it happens would
-- let a background query (the verify walk, the watch loop) replace what the player is reading.
-- ~10s covers a normal throttled round trip with margin.
local SEARCH_GRACE_SECONDS = 10

function GC.AuctionHouseTab.NoteSearchFocus(focused)
  searchFocused = focused
  if not focused then
    searchLostFocusAt = time()
  end
end

-- `now` is an explicit, optional parameter (defaulting to time()) purely so specs can drive it
-- with a fake clock -- production callers never pass it.
function GC.AuctionHouseTab.PlayerIsSearching(now)
  if searchFocused then return true end
  if not searchLostFocusAt then return false end
  now = now or time()
  return (now - searchLostFocusAt) < SEARCH_GRACE_SECONDS
end

-- One predicate for the background tickers in UI/SniperFrame.lua (the auto-scan send,
-- tickAutoVerify, and the watch-loop poll): the player outranks all of it for the shared
-- request throttle whether they are posting, buying a browse result, or reading their own
-- search -- any one of the three means a hardware click could land at any moment.
-- True while ANOTHER addon's tab owns the auction house window. LibAHTab clears
-- AuctionHouseFrame.displayMode to nil when one of its tabs is selected (LibAHTab.lua's
-- SetSelected, read verbatim) -- a state Blizzard's own tabs never leave the frame in, since
-- every one of theirs sets a mode. So "no display mode, and the panel that replaced it is not
-- our dock" is exactly "somebody else's tab is up".
--
-- This has to count as busy, and PlayerIsPosting could never have caught it: it reads
-- Blizzard's display mode, and Blizzard does not know a sell form is on screen when the form
-- belongs to Auctionator. A player posting through Auctionator's Selling tab found Post greyed
-- out, flickering back only occasionally, because GoldCap's own background traffic -- the
-- verify walk and the watch loop, neither of which Auto gates -- was spending the auction
-- house's shared request budget the entire time (reported in-game 2026-08-28). Whatever the
-- player is doing on another addon's panel outranks all of it, exactly as it does on
-- Blizzard's own.
function GC.AuctionHouseTab.PlayerIsUsingAnotherTab()
  local ah = _G.AuctionHouseFrame
  if not ah then return false end
  -- Nothing has been selected yet this session: fail open, the same way the detectors above do.
  -- `currentMode` is what the hook read back DURING SetDisplayMode, and LibAHTab clears the
  -- field to nil only afterwards -- so a library tab leaves currentMode holding the empty table
  -- it passed and ah.displayMode nil, which is precisely the pair this distinguishes from
  -- "the auction house has never chosen anything".
  if not currentMode then return false end
  if ah.displayMode ~= nil then return false end
  return not (dock and dock:IsShown())
end

-- True while Blizzard's own Buy/Browse pane -- the browse list itself, .Buy, distinct from the
-- .ItemBuy/.CommoditiesBuy purchase form PlayerIsBuying reads -- is the visible panel and our
-- own window is not. The player's own browse results are theirs: the book pass
-- (SendBrowseQuery/RequestMoreBrowseResults) and the key polls (SearchForItemKeys, both the
-- Items board's and the BUY tab's floor refresh, all in UI/SniperFrame.lua) answer through the
-- same GetBrowseResults() buffer Blizzard's list reads from, so while that pane is on screen and
-- GoldCap's window is not, nothing of ours may send a browse or keys query. None of the other
-- predicates catch this alone: PlayerIsBuying reads a different display mode, PlayerIsUsingAnotherTab
-- is false here because Blizzard's own tab leaves ah.displayMode non-nil, and PlayerIsSearching
-- only covers focus plus a 10s grace, not simply having Buy on screen. Same dock read as
-- PlayerIsUsingAnotherTab: our own tab showing the dock is not "using another tab", but it is
-- also not "the player's browse results, undisturbed" once GoldCap's own board is what the dock
-- holds -- so the dock hides this window the same way it exempts that predicate.
--
-- The window open floating is the other half of "our own window is not" on screen. The auction
-- house opens on Buy and autoOpen (on by default) shows the window floating beside it, so a
-- predicate that read only the dock was true from the moment the auction house opened, and
-- every sender PlayerIsBusy gates stood down for the whole visit -- the window open, nothing in
-- it moving (confirmed in game 2026-09-22). A window that cannot be asked fails open, like
-- every detector here: a broken read must never silence the addon.
function GC.AuctionHouseTab.PlayerIsBrowsing()
  if not currentMode then return false end
  local modes = _G.AuctionHouseFrameDisplayMode
  if not modes then return false end
  if currentMode ~= modes.Buy then return false end
  if dock and dock:IsShown() then return false end
  local sniper = GC.Sniper
  if not (sniper and sniper.IsWindowShown) then return false end
  return not sniper.IsWindowShown()
end

-- Final review S1 (b): true while Blizzard's Buy pane is the visible panel -- not our dock --
-- after a browse query that was not ours has gone out this visit: the pane is showing that
-- query's results, and SearchForItemKeys and a pass page answer into the same buffer. Unlike
-- PlayerIsBrowsing it holds with the GoldCap window open: a player who searched there is reading
-- that list whether or not our window floats beside it. Not part of PlayerIsBusy -- it holds back
-- only what writes that buffer (UI/SniperFrame.lua's GC.Sniper._BrowseOwned), never a per-item
-- search, and a visit where the player never searched there is exactly as before. Fails open.
function GC.AuctionHouseTab.PlayerOwnsBrowseList()
  if not (playerBrowsed and currentMode) then return false end
  local modes = _G.AuctionHouseFrameDisplayMode
  if not modes or currentMode ~= modes.Buy then return false end
  return not (dock and dock:IsShown())
end

function GC.AuctionHouseTab.PlayerIsBusy(now)
  return GC.AuctionHouseTab.PlayerIsPosting() or GC.AuctionHouseTab.PlayerIsBuying()
    or GC.AuctionHouseTab.PlayerIsUsingAnotherTab()
    or GC.AuctionHouseTab.PlayerIsSearching(now)
    or GC.AuctionHouseTab.PlayerIsBrowsing()
end

-- Called from the window's own OnHide (see UI/SniperFrame.lua): the player closed the docked
-- window with its X or with Escape, so hand the auction house back to Blizzard's Buy tab --
-- leaving our empty mode up would show a hollowed-out auction house.
function GC.AuctionHouseTab.OnWindowHidden()
  local ah = _G.AuctionHouseFrame
  if not ah or not dock or not dock:IsShown() then return end
  -- On the LibAHTab path the auction house's own displayMode is nil while our tab is selected
  -- (the library sets it to nil after clearing the mode), so the dock being up is the whole
  -- condition there.
  if not libRegistered and ah.displayMode ~= DISPLAY_MODE then return end
  local buy = _G.AuctionHouseFrameDisplayMode and _G.AuctionHouseFrameDisplayMode.Buy
  if buy and ah.SetDisplayMode then
    pcall(ah.SetDisplayMode, ah, buy) -- the hook above hides the dock
  else
    hideDock()
  end
end

-- Kept for the fallback button (the native tab's look is engine-owned now); callers may
-- invoke it unconditionally.
function GC.AuctionHouseTab.Refresh()
  if tab and tab.SetVariant then
    local on = GC.Sniper and GC.Sniper.IsWindowShown and GC.Sniper.IsWindowShown()
    tab:SetVariant(on and "active" or "ghost")
  end
end

-- The auction house closed. The dock (a child of AuctionHouseFrame) vanishes with it either
-- way; what must not linger is the WINDOW's docked state -- undock it back to a floating
-- window with its saved geometry, hidden, so the next `/goldcap` opens it normally.
function GC.AuctionHouseTab.OnAuctionHouseClosed()
  playerBrowsed = false
  if dock and dock:IsShown() then dock:Hide() end
  if GC.Sniper and GC.Sniper.SetDocked then pcall(GC.Sniper.SetDocked, nil) end
  GC.AuctionHouseTab.Refresh()
end
