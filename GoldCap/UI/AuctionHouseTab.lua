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
-- The GoldCap display mode: identity is the contract (Blizzard compares modes with `==`),
-- and empty is the content (their show loop iterates it and finds nothing to show).
local DISPLAY_MODE = {}

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

local function showDock()
  if not dock then return end
  if GC.Sniper and GC.Sniper.SetDocked then
    pcall(GC.Sniper.SetDocked, dock)
  end
  dock:Show()
end

local function hideDock()
  if not dock or not dock:IsShown() then return end
  dock:Hide()
  -- The window is a CHILD of the dock, so visually it is already gone -- but its own shown
  -- flag would stay true, and everything that reads IsWindowShown (Auto's pause causes, the
  -- Sell tab badge) would believe the player is still looking at it. Hide it for real.
  if GC.Sniper and GC.Sniper.IsWindowShown and GC.Sniper.IsWindowShown()
      and GC.Sniper.Toggle then
    pcall(GC.Sniper.Toggle)
  end
end

function GC.AuctionHouseTab.Install()
  if installed then return end
  local ah = _G.AuctionHouseFrame
  if not ah or not CreateFrame then return end
  installed = true

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

  -- The anchor is the last tab that is NOT ours: ours is already in ah.Tabs (see above), and
  -- a frame cannot anchor to itself.
  local last
  for _, candidate in ipairs(blizzardTabs(ah)) do
    if candidate ~= tab then last = candidate end
  end
  pcall(function()
    tab:ClearAllPoints()
    if last then
      -- Blizzard's own tabs sit at -15, but our resized button rides visibly onto the
      -- Auctions tab at that offset (seen in game 2026-08-17) -- ease it out to -10. The
      -- anchor is "the last tab that is not ours" in ah.Tabs, so another tab-adding addon
      -- (Auctionator does exactly this) slots in cleanly whichever of us installs first.
      tab:SetPoint("TOPLEFT", last, "TOPRIGHT", -10, 0)
    else
      tab:SetPoint("TOPLEFT", ah, "BOTTOMLEFT", 11, 2)
    end
  end)

  -- The content host: a plain panel over the area Blizzard's own panels vacate while our
  -- mode is up. The window docks INTO it (SetDocked), so one Show/Hide moves everything.
  -- Anchors leave the title bar above and the money strip below visible -- both live outside
  -- the display-mode lists and stay useful.
  pcall(function()
    dock = CreateFrame("Frame", "GoldCapAuctionHouseDock", ah)
    dock:SetPoint("TOPLEFT", 7, -28)
    dock:SetPoint("BOTTOMRIGHT", -7, 32)
    dock:Hide()
  end)

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

  -- One hook, both directions: our mode up -> dock and show; any other mode -> hide. Their
  -- OnClick is a template script we must not replace, so hook the frame method it calls.
  if not hookedTabs and ah.SetDisplayMode then
    hookedTabs = true
    pcall(hooksecurefunc, ah, "SetDisplayMode", function(_, mode)
      if mode == DISPLAY_MODE then
        showDock()
      else
        hideDock()
      end
    end)
  end
end

-- Called from the window's own OnHide (see UI/SniperFrame.lua): the player closed the docked
-- window with its X or with Escape, so hand the auction house back to Blizzard's Buy tab --
-- leaving our empty mode up would show a hollowed-out auction house.
function GC.AuctionHouseTab.OnWindowHidden()
  local ah = _G.AuctionHouseFrame
  if not ah or not dock or not dock:IsShown() then return end
  if ah.displayMode ~= DISPLAY_MODE then return end
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
  if dock and dock:IsShown() then dock:Hide() end
  if GC.Sniper and GC.Sniper.SetDocked then pcall(GC.Sniper.SetDocked, nil) end
  GC.AuctionHouseTab.Refresh()
end
