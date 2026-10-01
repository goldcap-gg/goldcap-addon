local _, GC = ...

-- The AH Upgrade Finder's window (Core/ForeverUpgrades.lua), WoW: Forever only (/gc upgrades): one
-- row per equipment slot with an upgrade in the last scan. Built the engine's way
-- (docs/addon/AGENTS.md): a Blizzard template frame at DIALOG strata with its own mouse, rows that
-- are mouse-enabled Buttons with a HIGHLIGHT texture for hover, the item's own tooltip on hover, and
-- the client's HandleModifiedItemClick on click (shift links it, ctrl previews it). It buys nothing:
-- the player searches the item on the auction house (plan 3e, D4).
GC.ForeverUpgradesUI = GC.ForeverUpgradesUI or {}

-- M5 (final review): TOP gives the header enough room for a 3-line translation plus the loading
-- suffix (de/ru) before row 1 starts; the price column is widened so three coin icons don't clip.
local UP = { W = 560, ROW_H = 20, ROWS = 14, TOP = 92, NAME = "GoldCapUpgradesFrame", STALE_LIMIT = 6 }
GC.ForeverUpgradesUI.C = UP
local frame
local pending = false
-- M1 (final review): the exact ids the last render is still waiting on, and how many repaints in
-- a row have not shrunk that count -- so an item that never answers cannot keep the window
-- rebuilding at 2 Hz for as long as it stays open.
local lastLoadingIds
local staleRepaints, lastLoadingCount = 0, nil

local function createRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(UP.W - 24, UP.ROW_H)
  row:SetPoint("TOPLEFT", 12, -(UP.TOP + (i - 1) * UP.ROW_H))
  -- Hover is the engine's HIGHLIGHT layer on a mouse-enabled frame, the same fill UI/BuyFrame.lua's
  -- rows use -- never painted in OnEnter.
  row:EnableMouse(true)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)
  local function cell(template, x, width, justify)
    local fs = GC.Theme.ClientFont(row:CreateFontString(nil, "ARTWORK", template))
    fs:SetPoint("LEFT", x, 0)
    fs:SetWidth(width)
    fs:SetJustifyH(justify)
    fs:SetWordWrap(false)
    return fs
  end
  row.slot = cell("GameFontNormalSmall", 4, 90, "LEFT")
  row.item = cell("GameFontHighlightSmall", 98, 200, "LEFT")
  row.gain = cell("GameFontHighlightSmall", 302, 130, "LEFT")
  row.price = cell("GameFontHighlightSmall", 436, 96, "RIGHT")
  -- The item's own tooltip is information, not a hover look.
  row:SetScript("OnEnter", function(self)
    if not (self.link and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.link)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  row:SetScript("OnClick", function(self)
    local handle = _G.HandleModifiedItemClick
    if self.link and type(handle) == "function" then handle(self.link) end
  end)
  row:Hide()
  return row
end

local function build()
  if frame then return frame end
  local f = CreateFrame("Frame", UP.NAME, UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(UP.W, UP.TOP + UP.ROWS * UP.ROW_H + 16)
  f:SetPoint("CENTER")
  -- A window, not an overlay: DIALOG strata above the docked Sniper (HIGH), toplevel, and its own
  -- mouse so a click never falls through to what is behind it ("Layering").
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.TitleText:SetText(GC.Util.ClientText(GC.L["Gear upgrades on the auction house"]))
  local header = GC.Theme.ClientFont(f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
  header:SetPoint("TOPLEFT", 12, -28)
  header:SetWidth(UP.W - 24)
  header:SetJustifyH("LEFT")
  header:SetWordWrap(true)
  f.header = header
  f.rows = {}
  for i = 1, UP.ROWS do f.rows[i] = createRow(f, i) end
  table.insert(UISpecialFrames, UP.NAME) -- Escape closes it
  f:Hide()
  frame = f
  return f
end
GC.ForeverUpgradesUI._Build = build

-- M5 (final review): SetText with the text a FontString already holds is a no-op and does not
-- redraw it (docs/addon/AGENTS.md "Text") -- a row hidden then shown again, or the window closed
-- and reopened with nothing changed, could come back blank. Clear before every set, here and on
-- every cell below.
local function setText(fs, text)
  fs:SetText("")
  fs:SetText(text)
end

function GC.ForeverUpgradesUI.Render(r, now)
  local f = build()
  lastLoadingIds = r.loadingIds
  local header
  if r.noScan then
    header = GC.L["No scan with gear in it yet. Open the auction house and let GoldCap scan it."]
  elseif r.noStats then
    header = GC.L["This client does not report item stats, so GoldCap cannot compare gear."]
  elseif r.noWeights then
    header = GC.L["No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5"]
  elseif #r.rows == 0 then
    header = GC.L["Nothing on the auction house beats what you wear at your level."]
  else
    header = GC.L["From your scan %s ago. Counts only %s. Change with /gc weights."]:format(
      GC.Util.FormatElapsedWords(math.max(0, (now or 0) - (r.at or now or 0))) or "",
      GC.ForeverUpgrades.WeightsText(r.weights or {}))
  end
  if (r.loading or 0) > 0 then
    header = header .. " " .. GC.L["Items still loading: %d. Open this again in a moment."]:format(r.loading)
  end
  setText(f.header, header)
  for i = 1, UP.ROWS do
    local row, data = f.rows[i], r.rows[i]
    if data then
      row.link = data.link or data.itemString
      setText(row.slot, _G[data.labelKey] or data.labelKey or "")
      setText(row.item, row.link)
      local gain = GC.ForeverUpgrades.DiffText(data.diffs)
      if data.later then gain = gain .. "  " .. GC.L["at level %d"]:format(data.later) end
      setText(row.gain, gain)
      setText(row.price, GC.Util.CoinText(data.unit))
      row:Hide()
      row:Show()
    else
      row.link = nil
      row:Hide()
    end
  end
end

local function current()
  local r = GC.ForeverUpgrades and GC.ForeverUpgrades.Current and GC.ForeverUpgrades.Current()
  return r or { rows = {}, loading = 0, noScan = true }
end

function GC.ForeverUpgradesUI.Show()
  local f = build()
  f:Show()
  if f.Raise then f:Raise() end
  -- M1: a fresh open always gets a fresh chance, whatever a previous visit's storm cap reached.
  staleRepaints, lastLoadingCount = 0, nil
  GC.ForeverUpgradesUI.Render(current(), time())
end

function GC.ForeverUpgradesUI.Hide()
  if frame then frame:Hide() end
end

-- Whether there is anything to render right now (Core/ForeverScan.lua's post-scan update): the
-- window's own frame, created only by the first Show/Toggle, so a fresh login with the window
-- never opened answers false rather than erroring on a nil frame.
function GC.ForeverUpgradesUI.IsShown()
  return frame ~= nil and frame:IsShown() == true
end

function GC.ForeverUpgradesUI.Toggle()
  if frame and frame:IsShown() then frame:Hide() else GC.ForeverUpgradesUI.Show() end
end

function GC.ForeverUpgradesUI.RefreshIfShown()
  if not (frame and frame:IsShown()) then return end
  local r = current()
  local loading = r.loading or 0
  -- M1: a repaint that did not shrink the loading count is one item (or more) that still has not
  -- answered; after STALE_LIMIT of those in a row, stop chasing it until the window reopens.
  if lastLoadingCount ~= nil and loading > 0 and loading >= lastLoadingCount then
    staleRepaints = staleRepaints + 1
  else
    staleRepaints = 0
  end
  lastLoadingCount = loading
  GC.ForeverUpgradesUI.Render(r, time())
end

-- GET_ITEM_INFO_RECEIVED: an item the last build counted as loading may have arrived. One repaint
-- half a second after the first answer, not one per answer; nothing at all while the window is not
-- up (retail, where it never is, included). M1 (final review): itemID, when given, is checked
-- against the last render's own loading set -- an answer for something nobody asked about should
-- not itself trigger a rebuild -- and a storm that has stopped shrinking the loading count gives up
-- until the window is reopened.
function GC.ForeverUpgradesUI.OnItemInfo(itemID)
  if pending or not (frame and frame:IsShown()) then return end
  if lastLoadingIds and itemID ~= nil and not lastLoadingIds[itemID] then return end
  if staleRepaints >= UP.STALE_LIMIT then return end
  local timer = _G.C_Timer
  if type(timer) ~= "table" or type(timer.After) ~= "function" then return end
  pending = true
  timer.After(0.5, function()
    pending = false
    GC.ForeverUpgradesUI.RefreshIfShown()
  end)
end
