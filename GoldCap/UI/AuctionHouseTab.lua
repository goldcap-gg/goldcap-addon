local _, GC = ...

-- A GoldCap tab on Blizzard's own Auction House window.
--
-- Scope, stated up front because the obvious next step is deliberately not taken
-- here. This adds an entry point: a tab in the row Blizzard's Buy/Sell/Auctions
-- tabs live in, which shows and hides the GoldCap window. It does NOT take over
-- the auction house's content area the way Auctionator does.
--
-- Taking over means hiding Blizzard's panels and drawing ours in their place,
-- and the failure mode is not cosmetic. Our purchase path is gated on hardware
-- input, and Blizzard's own tab machinery (`PanelTemplates_SetNumTabs` writes
-- `numTabs` and `Tabs` on the frame it is given, which Blizzard's code then
-- reads back) is the classic way an addon taints a frame it does not own. It
-- also has to restore whatever it hid, in the right order, against a
-- SetDisplayMode that has already run -- and every one of those failure modes
-- looks like "the auction house is broken", on the client where the owner does
-- their real buying. None of it is verifiable outside the game, so it is not
-- shipped on a guess.
--
-- What this file does instead touches nothing Blizzard reads:
--   * creates one Button parented to AuctionHouseFrame,
--   * calls PanelTemplates_TabResize on THAT button only,
--   * hooks with hooksecurefunc, never SetScript, on Blizzard's own widgets.
--
-- Every step is pcall-guarded: this runs synchronously inside
-- GC.Sniper.OnAuctionHouseShow, and an error here would abort the rest of that
-- function -- no ticker, no Auto, no auto-open -- which is a far worse failure
-- than a missing tab.
GC.AuctionHouseTab = {}

local tab, installed, hookedTabs = nil, false, false

-- Blizzard's tabs are `AuctionHouseFrame.Tabs` on current builds and globals
-- named AuctionHouseFrameTab1..N on older ones. Walk whichever exists; the last
-- one is what we anchor to.
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

local function windowShown()
  return GC.Sniper and GC.Sniper.IsWindowShown and GC.Sniper.IsWindowShown()
end

-- The tab's look follows the window, so the button never claims a state the
-- window is not in -- including when the window was closed by its own X, by the
-- slash command, or by the auction house closing.
local function refreshTab()
  if not tab then return end
  local on = windowShown()
  if tab.SetVariant then
    tab:SetVariant(on and "active" or "ghost")
  elseif PanelTemplates_SelectTab and PanelTemplates_DeselectTab then
    -- Only ever called on our own button. These read the button's own fields,
    -- not the parent frame's tab bookkeeping.
    pcall(on and PanelTemplates_SelectTab or PanelTemplates_DeselectTab, tab)
  end
end
GC.AuctionHouseTab.Refresh = refreshTab

local function buildTab(ah)
  local built
  -- Blizzard's own tab art, when the template is there. A client build without
  -- it falls back to the addon's button rather than to nothing: the entry point
  -- is the whole point of this file.
  pcall(function()
    built = CreateFrame("Button", "GoldCapAuctionHouseTab", ah, "AuctionHouseFrameTabTemplate")
  end)
  if built then
    pcall(function() built:SetText("GoldCap") end)
    -- Sizes the button to its own text. Touches this button only.
    pcall(function() PanelTemplates_TabResize(built, 0) end)
    return built
  end
  if not (GC.Theme and GC.Theme.Button) then return nil end
  built = GC.Theme.Button(ah, "ghost")
  built:SetSize(80, 22)
  built:SetLabel("GoldCap")
  return built
end

function GC.AuctionHouseTab.Install()
  if installed then return end
  local ah = _G.AuctionHouseFrame
  if not ah or not CreateFrame then return end
  installed = true

  tab = buildTab(ah)
  if not tab then return end

  local tabs = blizzardTabs(ah)
  local last = tabs[#tabs]
  pcall(function()
    tab:ClearAllPoints()
    if last then
      -- Blizzard's tab art overlaps its neighbour by a fixed amount; matching it
      -- is what makes the row read as one strip rather than a button parked
      -- beside it. With no tab to anchor to, sit at the frame's bottom-left
      -- where the strip would have started.
      tab:SetPoint("TOPLEFT", last, "TOPRIGHT", -15, 0)
    else
      tab:SetPoint("TOPLEFT", ah, "BOTTOMLEFT", 11, 2)
    end
  end)

  tab:SetScript("OnClick", function()
    if GC.Sniper and GC.Sniper.Toggle then GC.Sniper.Toggle() end
    refreshTab()
  end)

  -- Clicking one of Blizzard's tabs should leave ours looking unselected. Their
  -- OnClick is a template script we must not replace, so hook the frame method
  -- it ends up calling instead.
  if not hookedTabs and ah.SetDisplayMode then
    hookedTabs = true
    pcall(hooksecurefunc, ah, "SetDisplayMode", function() refreshTab() end)
  end

  refreshTab()
end

-- Called when the auction house closes. The button is a child of
-- AuctionHouseFrame and hides with it, but the addon window is not, so its
-- state can drift from what the tab last painted.
function GC.AuctionHouseTab.OnAuctionHouseClosed()
  refreshTab()
end
