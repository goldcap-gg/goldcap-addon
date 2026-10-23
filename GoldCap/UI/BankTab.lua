local _, GC = ...

-- At a bank: a GoldCap tab on Blizzard's bank window, after its own Bank and Warband Bank tabs
-- (owner, 2026-10-23). Picked, it lays a panel of GoldCap's over the bank's slots, in the same
-- window and at the same size, holding the bank by group card (UI/BankGroupsCard.lua) at its left
-- and the carry list (UI/BankRoute.lua) at its right; picking Blizzard's own tab again shows the
-- bank. While Blizzard's tab shows, neither card does. The bank opens on the tab the player had at
-- the last close (GC.db.bankTab, "goldcap" or nil).
--
-- Nothing of Blizzard's is written to, so nothing of its bank runs tainted: the tab and the panel
-- are frames of ours parented to the window, Blizzard's tab system never learns of the tab
-- (AddNamedTab would put it in Blizzard's own tables), and the bank panel stays shown under ours,
-- so a right click on a bag item still deposits into the bank it shows (BankFrame:GetActiveBankType,
-- Blizzard_UIPanels_Game's ContainerFrame.lua, needs the panel shown). Blizzard's tab that stays
-- selected under the panel is drawn as a tab that is not: its selected art and its name are hidden
-- (widget calls on its textures, no field set) and a button of ours drawn as an unselected tab
-- lies over it, whose click shows the bank again. A click on Blizzard's other tab, or on a bank tab
-- down the panel's right edge, shows the bank too: post-hooks see it (OnBlizzardTabClick,
-- OnBankTabPicked), and the panel goes on the next frame, outside Blizzard's call.
--
-- With a bag addon that takes the bank over, Blizzard's window is shown under a hidden or tiny
-- parent (Bagnon: BagBrother's core/features/uiOverrides.lua), so there is no window to hang the
-- tab on: the cards stay beside the bank as before (Where answers "beside"). No tab either when
-- GoldCap has nothing for a bank: no followed group and no route data. Retail only, like the
-- cards: GoldCap_Camelot.toc loads none of the bank files.
GC.BankTab = {}
local B = GC.BankTab

-- PAD: the room the panel leaves around the cards, and between them. INSET: the panel inside the
-- window, under its title bar and above the strip with the money (BankFrame.xml's own Background,
-- 20 down from the top and 30 up from the bottom), a little in from the window's edges. TAB_H, TAB_GAP,
-- TAB_MIN_W: Blizzard's own tab (TabSystemButtonTemplate's 32, TabSystemTemplate's spacing 1 and
-- the bank's minTabWidth 100). PANEL_LEVELS: how far over the bank's own frames the panel lies,
-- under the portrait (PortraitFrameBaseTemplate's PortraitContainer).
B.PAD = 8
local INSET = { LEFT = 4, TOP = 22, RIGHT = 4, BOTTOM = 30 }
local TAB_H, TAB_GAP, TAB_MIN_W, TAB_TEXT_PAD = 32, 1, 100, 40
local PANEL_LEVELS = 100
local ACTIVE_ART = { "LeftActive", "MiddleActive", "RightActive" }

-- Whether the GoldCap tab is picked, for this visit to the bank.
B._on = false
local tab, back, panel, covered, savedTitle

local function isUp(widget)
  return type(widget) == "table" and widget.IsShown and widget:IsShown()
end

-- Blizzard's bank window is what the player sees: shown under shown parents, at a real size and not
-- see-through, with the tab system and the panel this hangs on.
local function windowUp(bank)
  if not (type(bank) == "table" and bank.IsVisible and bank:IsVisible()) then return false end
  if not (type(bank.TabSystem) == "table" and type(bank.BankPanel) == "table") then return false end
  local scale = bank.GetEffectiveScale and bank:GetEffectiveScale()
  local ui = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
  if type(scale) == "number" and type(ui) == "number" and scale < ui / 2 then return false end
  local alpha = bank.GetEffectiveAlpha and bank:GetEffectiveAlpha()
  if type(alpha) == "number" and alpha < 0.1 then return false end
  return true
end

-- Something for the panel to hold: a followed group, or route data for the carry list.
local function hasSomething()
  if GC.GroupRules and GC.GroupRules.HasGroups() then return true end
  return GC.SellRoute ~= nil and GC.SellRoute.HereId() ~= nil
end

local function tabbed()
  return GC.BankRoute._open == true and windowUp(_G.BankFrame) and hasSomething()
end

--- Where the bank cards go now: "inside" the panel while the GoldCap tab is picked, "away" (not
--- shown) while Blizzard's tab is, "beside" the bank when there is no tab (no window to hang it on,
--- or nothing for it to hold).
function B.Where()
  if not tabbed() then return "beside" end
  return B._on and "inside" or "away"
end

--- Inside the panel: `frame` parented to it, its top at the panel's top, at its left (`side`
--- "left", the group card) or its right ("right", the carry list). Answers the room the panel has
--- for the cards, its width and height inside PAD, or nil when the tab is not picked.
function B.Hold(frame, side)
  if B.Where() ~= "inside" or not panel then return nil end
  if frame:GetParent() ~= panel then frame:SetParent(panel) end
  -- Drawn with the window, over the panel, whatever layer the window is drawn in.
  if panel.GetFrameStrata then frame:SetFrameStrata(panel:GetFrameStrata()) end
  frame:SetFrameLevel(panel:GetFrameLevel() + 2)
  frame:ClearAllPoints()
  if side == "right" then
    frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -B.PAD, -B.PAD)
  else
    frame:SetPoint("TOPLEFT", panel, "TOPLEFT", B.PAD, -B.PAD)
  end
  local bank = _G.BankFrame
  return bank:GetWidth() - INSET.LEFT - INSET.RIGHT - 2 * B.PAD,
    bank:GetHeight() - INSET.TOP - INSET.BOTTOM - 2 * B.PAD
end

--- Beside the bank again: `frame` back on UIParent, where it was built.
function B.Release(frame)
  if not UIParent or frame:GetParent() == UIParent then return end
  frame:SetParent(UIParent)
  if UIParent.GetFrameStrata then frame:SetFrameStrata(UIParent:GetFrameStrata()) end
end

-- Blizzard's tab under the panel, which stays selected there, drawn as nothing: its selected art
-- and its name hidden, for our button over it to draw an unselected tab. Widget calls only: the
-- tab's own fields stay Blizzard's. Its unselected art is Blizzard's to show
-- (TabSystemButtonArtMixin:SetTabSelected), and stays hidden while the tab is selected.
local function hideArt(blizzard)
  for _, key in ipairs(ACTIVE_ART) do
    local art = blizzard[key]
    if art and art.Hide then art:Hide() end
  end
  if blizzard.Text and blizzard.Text.Hide then blizzard.Text:Hide() end
end

-- Blizzard's tab drawn again as its tab system has it: the selected art if it still is selected
-- (the player's click on the other tab selects that one after the panel's SelectTab), and its name.
local function uncover()
  if covered then
    local selected = not covered.IsSelected or covered:IsSelected()
    for _, key in ipairs(ACTIVE_ART) do
      local art = covered[key]
      if art and art.SetShown then art:SetShown(selected) end
    end
    if covered.Text and covered.Text.Show then covered.Text:Show() end
    covered = nil
  end
  if back then back:Hide() end
end

-- The selected one of Blizzard's tabs, which stays selected under the panel, drawn as a tab that is
-- not, under our button that shows the bank again.
local function cover(bank)
  local system = bank.TabSystem
  local id = system.selectedTabID
  local blizzard = id and system.GetTabButton and system:GetTabButton(id)
  if blizzard == covered then return end
  uncover()
  if not blizzard then return end
  covered = blizzard
  hideArt(blizzard)
  back:ClearAllPoints()
  back:SetAllPoints(blizzard)
  back:SetText(blizzard:GetText() or "")
  back:SetFrameLevel(blizzard:GetFrameLevel() + 2)
  if back.SetTabSelected then back:SetTabSelected(false) end
  back:Show()
end

-- The window's title reads GoldCap while the panel shows, and the bank's own name again after.
local function title(bank, on)
  local fs = bank.TitleContainer and bank.TitleContainer.TitleText
  if not (fs and fs.SetText and fs.GetText) then return end
  if on then
    if savedTitle == nil then savedTitle = fs:GetText() or "" end
    fs:SetText("GoldCap")
  elseif savedTitle ~= nil then
    if fs:GetText() == "GoldCap" then fs:SetText(savedTitle) end
    savedTitle = nil
  end
end

local function sound()
  if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
end

local function onTabClick()
  sound()
  B.Select(true, true)
end

local function onBackClick()
  sound()
  B.Select(false, true)
end

-- Our tab and the button over Blizzard's are Blizzard's own tab art (TabSystemButtonArtTemplate,
-- the art half of the bank's tab buttons, without their tab system), so they look like the tabs
-- beside them. The panel lies over the bank's slots with the bank window's own background.
local function build(bank)
  local T = GC.Theme
  tab = CreateFrame("Button", nil, bank, "TabSystemButtonArtTemplate")
  tab:SetHeight(TAB_H)
  tab:SetText("GoldCap")
  tab:SetScript("OnClick", onTabClick)
  back = CreateFrame("Button", nil, bank, "TabSystemButtonArtTemplate")
  back:SetScript("OnClick", onBackClick)
  back:Hide()
  panel = CreateFrame("Frame", nil, bank)
  panel:SetPoint("TOPLEFT", bank, "TOPLEFT", INSET.LEFT, -INSET.TOP)
  panel:SetPoint("BOTTOMRIGHT", bank, "BOTTOMRIGHT", -INSET.RIGHT, INSET.BOTTOM)
  -- Over the slots: a click or a hover never reaches the bank's items under it.
  panel:EnableMouse(true)
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(panel)
  if bg.SetAtlas then
    bg:SetAtlas("bank-frame-background")
    if bg.SetHorizTile then bg:SetHorizTile(true) end
    if bg.SetVertTile then bg:SetVertTile(true) end
  else
    bg:SetColorTexture(T.color.panel[1], T.color.panel[2], T.color.panel[3], 1)
  end
  panel.empty = T.Label(panel, 12)
  panel.empty:SetPoint("CENTER", panel, "CENTER", 0, 0)
  panel.empty:SetWidth(bank:GetWidth() - INSET.LEFT - INSET.RIGHT - 4 * B.PAD)
  panel.empty:SetJustifyH("CENTER")
  panel.empty:SetWordWrap(true)
  panel.empty:SetTextColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3])
  panel:Hide()
  B._tab, B._back, B._panel = tab, back, panel
end

-- After Blizzard's tabs, as wide as a tab of theirs with its name; as high as theirs and level
-- with them.
local function placeTab(bank)
  local system = bank.TabSystem
  tab:ClearAllPoints()
  tab:SetPoint("TOPLEFT", system, "TOPRIGHT", TAB_GAP, 0)
  local fs = tab.GetFontString and tab:GetFontString()
  local textW = fs and fs.GetStringWidth and fs:GetStringWidth() or 0
  tab:SetWidth(math.max(TAB_MIN_W, math.ceil(textW) + TAB_TEXT_PAD))
  local first = system.GetTabButton and system:GetTabButton(1)
  if first and first.GetFrameLevel then tab:SetFrameLevel(first:GetFrameLevel()) end
end

-- Over the bank's own frames, under the portrait.
local function panelLevel(bank)
  local level = bank:GetFrameLevel() + PANEL_LEVELS
  local portrait = bank.PortraitContainer
  local top = portrait and portrait.GetFrameLevel and portrait:GetFrameLevel()
  if type(top) == "number" and top <= level then level = math.max(bank:GetFrameLevel() + 1, top - 1) end
  return level
end

--- Shows the tab when there is a window to hang it on and something for it, drawn picked or not,
--- and the panel over the slots while it is picked; hides all of it, and draws Blizzard's tab as
--- its own again, otherwise.
function B.Apply()
  local bank = _G.BankFrame
  if not tabbed() then
    if tab then
      tab:Hide()
      panel:Hide()
      uncover()
      title(bank, false)
    end
    return
  end
  if not tab then build(bank) end
  placeTab(bank)
  tab:Show()
  local inside = B._on
  if tab.SetTabSelected then tab:SetTabSelected(inside) end
  panel:SetFrameLevel(panelLevel(bank))
  panel:SetShown(inside)
  if inside then
    cover(bank)
  else
    uncover()
  end
  title(bank, inside)
end

--- The panel's own line when it holds nothing: no card shows in it.
function B._PaintEmpty()
  if not panel then return end
  local function held(frame) return isUp(frame) and frame:GetParent() == panel end
  local empty = panel:IsShown() and not held(GC.BankGroupsCard and GC.BankGroupsCard._frame)
    and not held(GC.BankRoute._frame)
  panel.empty:SetText(GC.L["Nothing to move at this bank."])
  panel.empty:SetShown(empty)
end

--- The GoldCap tab picked (`on`) or Blizzard's again; `save` remembers it for the next visit. The
--- cards repaint where they now go.
function B.Select(on, save)
  B._on = on == true
  if save and type(GC.db) == "table" then GC.db.bankTab = B._on and "goldcap" or nil end
  B.Apply()
  GC.BankRoute.Refresh()
  if GC.BankGroupsCard then GC.BankGroupsCard.Refresh() end
  B._PaintEmpty()
end

-- The bank opened. The cards have painted already (this runs after the route's handler and the
-- card's hook) with the tab not picked. The tab picked at the last close comes on the frame after
-- both the bank's event and Blizzard's window showing, whichever comes last (the window opens on
-- the banker interaction, PLAYER_INTERACTION_MANAGER_FRAME_SHOW, not on BANKFRAME_OPENED): the
-- window's OnShow selects its own first tab (BankFrameMixin:SelectDefaultTab), which must not count
-- as the player leaving the GoldCap tab.
local function settle()
  if not B._opening then return end
  B._opening = nil
  B.Select(type(GC.db) == "table" and GC.db.bankTab == "goldcap", false)
end

local function settleSoon()
  if not (C_Timer and C_Timer.After) then return settle() end
  if B._settleQueued then return end
  B._settleQueued = true
  C_Timer.After(0, function()
    B._settleQueued = nil
    settle()
  end)
end

function B.OnBankOpened()
  B._on, B._opening = false, true
  if isUp(_G.BankFrame) then settleSoon() end
end

-- Blizzard's window showed: after the bank's event, the tab picked at the last close comes now.
function B.OnWindowShown()
  if B._opening then settleSoon() end
end

function B.OnBankClosed()
  B._on, B._opening = false, nil
  B.Apply()
end

-- The player picked something of Blizzard's: the GoldCap tab goes, on the next frame, never inside
-- Blizzard's call. Picked is Blizzard's other bank tab (its OnClick, BankFrame:SetTab, which sets
-- the panel's bank type and resets it) or a bank tab down the panel's right edge, the one to buy
-- included (BankPanelMixin:OnBankTabClicked, the panel's SelectTab). The panel also selects a tab
-- when it resets by itself (its OnShow, BANK_TABS_CHANGED when a tab is bought or the server sends
-- the bank's tabs): a SelectTab inside a Reset is not the player's, and the Reset's post-hook, which
-- comes right after it, takes it back.
local function leaveSoon()
  B._leave = true
  if not (C_Timer and C_Timer.After) then
    B._leave = nil
    return B.Select(false, true)
  end
  if B._leaveQueued then return end
  B._leaveQueued = true
  C_Timer.After(0, function()
    B._leaveQueued = nil
    local leave = B._leave
    B._leave = nil
    if leave and B._on then B.Select(false, true) end
  end)
end

function B.OnBankTabPicked()
  if B._on then leaveSoon() end
end

function B.OnPanelReset()
  B._leave = nil
end

function B.OnBlizzardTabClick()
  if B._on then leaveSoon() end
end

if hooksecurefunc and GC.BankRoute then
  hooksecurefunc(GC.BankRoute, "OnBankOpened", B.OnBankOpened)
  hooksecurefunc(GC.BankRoute, "OnBankClosed", B.OnBankClosed)
  hooksecurefunc(GC.BankRoute, "Refresh", B._PaintEmpty)
  if GC.BankGroupsCard then hooksecurefunc(GC.BankGroupsCard, "Refresh", B._PaintEmpty) end
end
-- BankPanelMixin:SelectTab and Reset are reached through the panel (self:SelectTab in
-- OnBankTabClicked and SelectFirstAvailableTab, self:Reset in SetBankType, OnShow and OnEvent), so
-- post-hooks on the panel see every call. Nothing protected goes through either. Blizzard's two
-- tab buttons are made as the window loads, before GoldCap; each gets a post-hook on its click
-- (HookScript runs after Blizzard's own OnClick, whatever that did).
local bankPanel, bankFrame = _G.BankPanel, _G.BankFrame
if type(bankFrame) == "table" and bankFrame.HookScript then bankFrame:HookScript("OnShow", B.OnWindowShown) end
if hooksecurefunc and type(bankPanel) == "table" and type(bankPanel.SelectTab) == "function"
  and type(bankPanel.Reset) == "function" then
  hooksecurefunc(bankPanel, "SelectTab", B.OnBankTabPicked)
  hooksecurefunc(bankPanel, "Reset", B.OnPanelReset)
end
local system = type(bankFrame) == "table" and bankFrame.TabSystem or nil
for _, blizzardTab in ipairs(type(system) == "table" and type(system.tabs) == "table" and system.tabs or {}) do
  if blizzardTab.HookScript then blizzardTab:HookScript("OnClick", B.OnBlizzardTabClick) end
end
