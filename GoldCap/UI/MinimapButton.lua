local _, GC = ...

-- GoldCap's own round button on the minimap's edge (retail only; the owner, 2026-10-27 00:30: the
-- Disenchant entry above the bags blended in, and he asked for a button of GoldCap's by the minimap).
-- It replaces that entry. A left click opens a menu: the deals board (what the addon compartment's
-- entry opens, which stays as it is), Disenchant for an enchanter, and Hide this button; a left drag
-- moves it round the minimap's edge. For a character that knows Disenchant it counts, in a gold pill,
-- the items queued to disenchant (UI/DisenchantFrame.lua's Counts), painted whenever the window's plan
-- is read (DisenchantFrame calls Refresh), in combat too: nothing here is protected.
--
-- Its look is Blizzard's own round map button's (Blizzard_WorldMap/Blizzard_WorldMapTemplates.xml,
-- WorldMapTrackingOptionsButtonTemplate, live 12.1.5): 32 square, the dark round background
-- (Interface\Minimap\UI-Minimap-Background, 25 at 2,-4), the icon (20 at 7,-6), the ring
-- (Interface\Minimap\MiniMap-TrackingBorder, 54 from the top left) and the additive highlight
-- (Interface\Minimap\UI-Minimap-ZoomButton-Highlight). The icon is GoldCap's mark, as the windows'
-- headers draw it. No library is embedded for it.
--
-- Where it stands: GC.db.minimap = { angle = degrees, hide = true | nil }, for the account (GoldCapDB
-- is account-wide), made on first use. The angle is counted from the minimap's right, as math does;
-- the default, DEFAULT_ANGLE, is the lower left, where few buttons sit. A square minimap (a minimap
-- addon's GetMinimapShape answering "SQUARE") keeps it on the square's edge. /gc minimap shows or
-- hides it.
GC.MinimapButton = {}
local MB = GC.MinimapButton

MB.NAME = "GoldCapMinimapButton"
-- How far out from the minimap's edge its centre stands, and its angle until the player drags it.
MB.EDGE = 5
MB.DEFAULT_ANGLE = 225

local SIZE = 32
local MINIMAP = "Interface\\Minimap\\"
-- The count's pill: badge.png (the kit's), its height and its least width; where it sits.
local PILL_H, PILL_MIN = 14, 14

local button

-- One guarded client call (Core/Util.lua's Ask).
local ask = GC.Util.Ask

local function store()
  if type(GC.db) ~= "table" then return {} end
  if type(GC.db.minimap) ~= "table" then GC.db.minimap = {} end
  return GC.db.minimap
end

local function angleOf()
  local angle = store().angle
  return type(angle) == "number" and angle or MB.DEFAULT_ANGLE
end

-- Its centre at `angle` on the minimap's edge: on the circle, or on a square minimap's outline.
local function place(angle)
  local minimap = _G.Minimap
  if not (button and minimap) then return end
  local rad = math.rad(angle)
  local x, y = math.cos(rad), math.sin(rad)
  local shape = type(_G.GetMinimapShape) == "function" and ask(_G.GetMinimapShape) or "ROUND"
  if shape == "SQUARE" then
    local most = math.max(math.abs(x), math.abs(y))
    x, y = x / most, y / most
  end
  local rx = (minimap:GetWidth() or 0) / 2 + MB.EDGE
  local ry = (minimap:GetHeight() or 0) / 2 + MB.EDGE
  button:ClearAllPoints()
  button:SetPoint("CENTER", minimap, "CENTER", x * rx, y * ry)
end

-- The angle from the minimap's centre to the cursor, in degrees from 0 to 360.
local function cursorAngle()
  local minimap = _G.Minimap
  local mx, my = minimap:GetCenter()
  local scale = minimap:GetEffectiveScale()
  local cx, cy = _G.GetCursorPosition()
  if not (mx and my and scale and cx and cy) or scale <= 0 then return nil end
  local atan2 = math.atan2 or math.atan
  return math.deg(atan2(cy / scale - my, cx / scale - mx)) % 360
end

-- The Disenchant window's counts (nil for a character without Disenchant, and while no plan was
-- read); `readNow`: with none read yet, the window reads one now, out of combat.
local function counts(readNow)
  local DF = GC.DisenchantFrame
  if not (DF and DF.Counts) then return nil end
  return DF.Counts(readNow)
end

local function knows()
  local DF = GC.DisenchantFrame
  return DF ~= nil and DF.Known ~= nil and DF.Known() == true
end

local function onDragUpdate()
  local angle = cursorAngle()
  if angle then
    button.dragAngle = angle
    place(angle)
  end
end

local function onDragStart(self)
  self:SetScript("OnUpdate", onDragUpdate)
end

local function onDragStop(self)
  self:SetScript("OnUpdate", nil)
  if self.dragAngle then
    store().angle = self.dragAngle
    self.dragAngle = nil
  end
  place(angleOf())
end

-- The count's pill from the Disenchant window's last plan: the items queued to disenchant, for a
-- character that knows Disenchant, only above 0.
local function paintPill()
  local n = counts()
  local on = type(n) == "number" and n > 0
  button.pill:SetShown(on)
  button.count:SetShown(on)
  if not on then return end
  -- Cleared and set again: a one-line FontString shown again can come back undrawn (the addon
  -- notes, "Text").
  button.count:SetText("")
  button.count:SetText(tostring(n))
  local w = math.max(PILL_MIN, math.ceil(button.count:GetStringWidth() or 0) + 6)
  button.pill:ClearAllPoints()
  button.pill:SetPoint("CENTER", button, "TOPRIGHT", -5, -5)
  button.pill:SetSize(w, PILL_H)
  button.count:ClearAllPoints()
  button.count:SetPoint("CENTER", button.pill, "CENTER", 0, 0)
end

-- Its tooltip: GoldCap; for an enchanter how many are worth disenchanting (their learned mats pay
-- more than a vendor), how many GoldCap has not learned yet, and how many the auction house and a
-- vendor pay more for (with none of them, that nothing is in the bags); then how to use it, in grey.
-- The window reads its bags at once if they changed or none were read (out of combat), and the pill
-- follows; in combat then, no count is claimed.
local function showTip(self)
  local tooltip = _G.GameTooltip
  if not tooltip then return end
  local n, ah, vendor, worth, learning = counts(true)
  paintPill()
  tooltip:SetOwner(self, "ANCHOR_LEFT")
  local text = GC.Util.ClientText
  local K = GC.Kit.Tokens.color
  tooltip:AddLine("GoldCap", K.goldText[1], K.goldText[2], K.goldText[3])
  local c = K.text1
  if n and n + ah + vendor == 0 then
    tooltip:AddLine(text(GC.L["Nothing in your bags to disenchant."]), c[1], c[2], c[3])
  elseif n then
    -- "Worth disenchanting: 0" beside what is not learned yet says nothing (the re-review, 2026-10-27).
    if worth > 0 or learning == 0 then
      tooltip:AddLine(text(GC.L["Worth disenchanting: %d"]:format(worth)), c[1], c[2], c[3])
    end
    if learning > 0 then tooltip:AddLine(text(GC.L["Not learned yet: %d"]:format(learning)), c[1], c[2], c[3]) end
    if ah > 0 then tooltip:AddLine(text(GC.L["The auction house pays more: %d"]:format(ah)), c[1], c[2], c[3]) end
    if vendor > 0 then tooltip:AddLine(text(GC.L["A vendor pays more: %d"]:format(vendor)), c[1], c[2], c[3]) end
  end
  tooltip:AddLine(text(GC.L["Click for GoldCap. Drag to move it."]), K.text3[1], K.text3[2], K.text3[3])
  tooltip:Show()
end

local function hideTip()
  if _G.GameTooltip then _G.GameTooltip:Hide() end
end

--- Hides or shows the button for good (GC.db.minimap.hide); hidden, it says how to bring it back.
--- Shown again, it asks the Disenchant window for a fresh count (nothing read the bags for it while
--- it was hidden), which tells it back through Refresh.
function MB.SetHidden(hide)
  store().hide = hide and true or false
  if hide then
    if button then button:Hide() end
    GC.Print(GC.L["The GoldCap button by the minimap is hidden. Type /gc minimap to bring it back."])
    return
  end
  MB.Build()
  button:Show()
  MB.Refresh()
  local DF = GC.DisenchantFrame
  if DF and DF.Refresh then DF.Refresh() end
end

local function openMenu(self)
  local menu = _G.MenuUtil
  if not (menu and menu.CreateContextMenu) then return end
  menu.CreateContextMenu(self, function(_, root)
    local text = GC.Util.ClientText
    root:CreateTitle("GoldCap")
    root:CreateButton(text(GC.L["Deals board"]), function() GC.Sniper.Toggle() end)
    if knows() then
      local n = counts(true)
      paintPill()
      local label = n and n > 0 and GC.L["Disenchant (%d)"]:format(n) or GC.L["Disenchant"]
      root:CreateButton(text(label), function() GC.DisenchantFrame.Toggle() end)
    end
    root:CreateDivider()
    root:CreateButton(text(GC.L["Hide this button"]), function() MB.SetHidden(true) end)
  end)
end

--- Builds the button on the minimap, once.
function MB.Build()
  if button or not _G.Minimap then return button end
  local T = GC.Theme
  local K = GC.Kit.Tokens.color
  local b = CreateFrame("Button", MB.NAME, _G.Minimap)
  b:SetSize(SIZE, SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  b.back = b:CreateTexture(nil, "BACKGROUND")
  b.back:SetTexture(MINIMAP .. "UI-Minimap-Background")
  b.back:SetSize(25, 25)
  b.back:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -4)
  b.logo = b:CreateTexture(nil, "ARTWORK")
  b.logo:SetTexture(T.MEDIA .. "GoldCap")
  b.logo:SetSize(20, 20)
  b.logo:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -6)
  -- The ring over the icon, under the count's pill (Blizzard's stands in OVERLAY: here ARTWORK's top).
  b.border = b:CreateTexture(nil, "ARTWORK", nil, 2)
  b.border:SetTexture(MINIMAP .. "MiniMap-TrackingBorder")
  b.border:SetSize(54, 54)
  b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.wash = b:CreateTexture(nil, "HIGHLIGHT")
  b.wash:SetTexture(MINIMAP .. "UI-Minimap-ZoomButton-Highlight")
  b.wash:SetBlendMode("ADD")
  b.wash:SetAllPoints()
  -- The count: the kit's badge in gold, its figure in the lettering on gold above it, at the top right.
  b.pill = b:CreateTexture(nil, "OVERLAY", nil, -1)
  b.pill:SetTexture(T.MEDIA .. "badge.png")
  b.pill:SetTextureSliceMargins(T.SLICE.badge, T.SLICE.badge, T.SLICE.badge, T.SLICE.badge)
  b.pill:SetVertexColor(K.gold[1], K.gold[2], K.gold[3], 1)
  b.count = T.Num(b, 9, true)
  b.count:SetWordWrap(false)
  b.count:SetJustifyH("CENTER")
  b.count:SetTextColor(K.onGold[1], K.onGold[2], K.onGold[3], 1)
  b.pill:Hide()
  b.count:Hide()
  b:SetScript("OnClick", openMenu)
  b:SetScript("OnDragStart", onDragStart)
  b:SetScript("OnDragStop", onDragStop)
  b:SetScript("OnEnter", showTip)
  b:SetScript("OnLeave", hideTip)
  button = b
  MB._button = b
  place(angleOf())
  return b
end

--- Whether the button shows on the minimap.
function MB.Shown()
  return button ~= nil and button:IsShown()
end

-- Its tooltip again, while it shows for this button: the counts it names changed.
local function repaintTip()
  local tooltip = _G.GameTooltip
  if tooltip and tooltip.IsOwned and tooltip:IsOwned(button) and tooltip:IsShown() then showTip(button) end
end

--- Paints the count from the Disenchant window's last plan: the items queued to disenchant, for a
--- character that knows Disenchant, only above 0; and the tooltip again while it shows.
function MB.Refresh()
  if not button then return end
  paintPill()
  repaintTip()
end

--- PLAYER_LOGIN: built unless the player hid it (GC.db exists by then).
function MB.OnEvent(event)
  if event == "PLAYER_LOGIN" then
    if store().hide then return end
    MB.Build()
    MB.Refresh()
  end
end

GC.slashHandlers = GC.slashHandlers or {}
GC.slashHandlers.minimap = function()
  MB.SetHidden(MB.Shown())
end

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  pcall(events.RegisterEvent, events, "PLAYER_LOGIN")
  events:SetScript("OnEvent", function(_, event, ...) MB.OnEvent(event, ...) end)
end
