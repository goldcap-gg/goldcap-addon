local _, GC = ...

-- The AH Upgrade Finder's window (Core/ForeverUpgrades.lua), WoW: Forever only (/gc upgrades): one
-- row per equipment slot with an upgrade in the last scan. Built the engine's way
-- (docs/addon/AGENTS.md): a Blizzard template frame at DIALOG strata with its own mouse, rows that
-- are mouse-enabled Buttons with a HIGHLIGHT texture for hover, the item's own tooltip on hover, and
-- the client's HandleModifiedItemClick on click (shift links it, ctrl previews it). It buys nothing:
-- the player searches the item on the auction house (plan 3e, D4).
GC.ForeverUpgradesUI = GC.ForeverUpgradesUI or {}

-- Every text wraps and the window grows to it, never "..." (owner, 2026-11-06: "+1 к силе, +1 к
-- ловкости,..." cut what a piece adds): the header is as tall as its words, each row as tall as its
-- longest cell, and the rows stack under them. ROW_H is a row's least height; the price column is
-- wide enough for three coin icons.
local UP = { W = 640, ROW_H = 20, ROWS = 14, HEADER_Y = 28, GAP = 10, PAD_BOTTOM = 16,
  NAME = "GoldCapUpgradesFrame", STALE_LIMIT = 6 }
GC.ForeverUpgradesUI.C = UP
local frame
local pending = false
-- M1 (final review): the exact ids the last render is still waiting on, and how many repaints in
-- a row have not shrunk that count -- so an item that never answers cannot keep the window
-- rebuilding at 2 Hz for as long as it stays open.
local lastLoadingIds
local staleRepaints, lastLoadingCount = 0, nil

local function createRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(UP.W - 24, UP.ROW_H)
  -- Hover is the engine's HIGHLIGHT layer on a mouse-enabled frame, the same fill UI/BuyFrame.lua's
  -- rows use -- never painted in OnEnter. Its ink is the game's: this is a Blizzard frame, so a
  -- skin's window ink (dark brown on Parchment) would vanish on it.
  row:EnableMouse(true)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  local ink = GC.Kit.Tokens.blizzard.ink
  hl:SetColorTexture(ink[1], ink[2], ink[3], 0.08)
  local function cell(template, x, width, justify, wrap)
    local fs = GC.Theme.ClientFont(row:CreateFontString(nil, "ARTWORK", template))
    fs:SetPoint("TOPLEFT", x, -3)
    fs:SetWidth(width)
    fs:SetJustifyH(justify)
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(wrap)
    return fs
  end
  row.slot = cell("GameFontNormalSmall", 4, 96, "LEFT", true)
  row.item = cell("GameFontHighlightSmall", 106, 210, "LEFT", true)
  row.gain = cell("GameFontHighlightSmall", 322, 196, "LEFT", true)
  row.price = cell("GameFontHighlightSmall", 522, 94, "RIGHT", false)
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
  f:SetSize(UP.W, UP.HEADER_Y + UP.GAP + UP.PAD_BOTTOM)
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
  header:SetPoint("TOPLEFT", 12, -UP.HEADER_Y)
  header:SetWidth(UP.W - 24)
  header:SetJustifyH("LEFT")
  header:SetWordWrap(true)
  f.header = header
  f.rows = {}
  for i = 1, UP.ROWS do f.rows[i] = createRow(f) end
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

-- The height a wrapped text takes at its set width (UI/WelcomeFrame.lua does the same).
local function textHeight(fs)
  return math.ceil(fs.GetStringHeight and fs:GetStringHeight() or 0)
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
    header = (r.dearer or 0) > 0
      and GC.L["Everything on the auction house that beats your gear costs more than the gold you carry."]
      or GC.L["Nothing on the auction house beats what you wear at your level."]
  else
    header = GC.L["From your scan %s ago: in each slot, the piece that adds the most for the gold you carry, or a cheaper one nearly as good. Counts only %s. Change with /gc weights."]:format(
      GC.Util.FormatElapsedWords(math.max(0, (now or 0) - (r.at or now or 0))) or "",
      GC.ForeverUpgrades.WeightsText(r.weights or {}))
    if (r.dearer or 0) > 0 then
      header = header .. " " .. GC.L["Slots where the upgrades cost more than you carry: %d."]:format(r.dearer)
    end
  end
  if (r.loading or 0) > 0 then
    header = header .. " " .. GC.L["Items still loading: %d. Open this again in a moment."]:format(r.loading)
  end
  setText(f.header, header)
  local y = UP.HEADER_Y + textHeight(f.header) + UP.GAP
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
      local h = math.max(UP.ROW_H, 6 + math.max(textHeight(row.slot), textHeight(row.item), textHeight(row.gain)))
      row:SetHeight(h)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -y)
      y = y + h
      row:Hide()
      row:Show()
    else
      row.link = nil
      row:Hide()
    end
  end
  f:SetHeight(y + UP.PAD_BOTTOM)
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

-- notLoad: a repaint for another reason (the gold carried, a worn piece -- OnChange), which says
-- nothing about whether the items still loading answer, so it leaves the storm cap's count alone.
function GC.ForeverUpgradesUI.RefreshIfShown(notLoad)
  if not (frame and frame:IsShown()) then return end
  local r = current()
  local loading = r.loading or 0
  -- M1: a repaint that did not shrink the loading count is one item (or more) that still has not
  -- answered; after STALE_LIMIT of those in a row, stop chasing it until the window reopens.
  if not notLoad then
    if lastLoadingCount ~= nil and loading > 0 and loading >= lastLoadingCount then
      staleRepaints = staleRepaints + 1
    else
      staleRepaints = 0
    end
    lastLoadingCount = loading
  end
  GC.ForeverUpgradesUI.Render(r, time())
end

-- GET_ITEM_INFO_RECEIVED: an item the last build counted as loading may have arrived. One repaint
-- half a second after the first answer, not one per answer; nothing at all while the window is not
-- up (retail, where it never is, included). M1 (final review): itemID, when given, is checked
-- against the last render's own loading set -- an answer for something nobody asked about should
-- not itself trigger a rebuild -- and a storm that has stopped shrinking the loading count gives up
-- until the window is reopened.
local function repaintSoon(notLoad)
  local timer = _G.C_Timer
  if type(timer) ~= "table" or type(timer.After) ~= "function" then return end
  pending = true
  timer.After(0.5, function()
    pending = false
    GC.ForeverUpgradesUI.RefreshIfShown(notLoad)
  end)
end

function GC.ForeverUpgradesUI.OnItemInfo(itemID)
  if pending or not (frame and frame:IsShown()) then return end
  if lastLoadingIds and itemID ~= nil and not lastLoadingIds[itemID] then return end
  if staleRepaints >= UP.STALE_LIMIT then return end
  repaintSoon()
end

-- PLAYER_MONEY and PLAYER_EQUIPMENT_CHANGED: the gold carried or a worn piece moved, and the rows
-- are weighed against both. The same single repaint half a second on, only while the window is up.
function GC.ForeverUpgradesUI.OnChange()
  if pending or not (frame and frame:IsShown()) then return end
  repaintSoon(true)
end
