local _, GC = ...

-- WoW: Forever only: GoldCap_Camelot.toc loads this file and GoldCap.toc does not. What SELL shows
-- of the sale pace (Core/ForeverPace.lua): the duration buttons and the pace lines in the dock's
-- post panel, a "24 h" mark on a slow seller's stock line, and the pace and the returns on its
-- row's tooltip. UI/Sell/PostPanel.lua, Row.lua and Tooltips.lua each look for the hook below
-- and skip it when it is nil, which is every hook on retail.
--
-- Nothing here posts. A duration button only changes what the next post will be and builds the
-- queue again, as the how-many box does; the post itself is POST's click (UI/Sell/Dock.lua).
local Theme = GC.Theme
local UI = GC.SellUI

local Forever = {}
UI.PostPanel.Forever = Forever

-- The room the duration row takes under the item's stock line, and the gap before the pace lines.
local HEAD_GAP, BUTTON_H, BUTTON_W, LINES_GAP = 6, 20, 46, 4
local ROW_H = HEAD_GAP + BUTTON_H

local function hoursOf(index)
  return GC.GroupRules and GC.GroupRules.HoursOf and GC.GroupRules.HoursOf(index) or nil
end

local function durationLabel(index)
  return (GC.L["%d h"]):format(hoursOf(index) or 24)
end

-- Days the tape covers, whole and at least 1: "in the last day" below two days' worth.
local function tapeDays(position)
  return math.max(1, math.floor((position.paceHours or 24) / 24))
end

-- What the tape says of the item: sales a day here, or none in the days it covers. nil without a
-- tape (a variant, a repair row, an item the tape does not know).
local function paceSentence(position)
  if type(position.pacePerDay) ~= "number" then return nil end
  if position.pacePerDay > 0 then
    return (GC.L["Sells about %s a day here"]):format(GC.Util.PerDay(position.pacePerDay))
  end
  local days = tapeDays(position)
  if days == 1 then return GC.L["No sales here in the last day"] end
  return (GC.L["No sales here in %d days"]):format(days)
end

-- How often it came back unsold since its last sale, or nil when it has not.
local function returnsSentence(position)
  local rounds = position.returnRounds
  if type(rounds) ~= "number" or rounds < 1 then return nil end
  if rounds == 1 then return GC.L["Came back unsold once since its last sale."] end
  return (GC.L["Came back unsold %d times since its last sale."]):format(rounds)
end

-- The duration a Settings choice stands for: the one the 24 h mark replaced.
local function settingIndex()
  local settings = GC.db and GC.db.settings and GC.db.settings.sniper
  return GC.SellUtil.validIndex(type(settings) == "table" and settings.postDuration) or 2
end

-- A duration button: only state, then the queue built again. No auction-house call, so it is
-- safe anywhere; the post is the dock's own click.
local function pick(index)
  local S, key = GC.SellState, UI.PostPanel.key
  if not key then return end
  if S.durationOverrides[key] ~= index then GC.SellPost.WalkAway() end
  S.durationOverrides[key] = index
  if not S.postingRow then GC.SellCompose.Queue() end
  UI.List.RenderRows()
end

--- The duration head, its three buttons and the pace lines, under the dock's stock line.
function Forever.Build(c)
  c.durationHead = Theme.Num(c, 9)
  c.durationHead:SetJustifyH("LEFT")
  c.durationHead:SetText(GC.Util.Upper(GC.L["Duration"]))
  UI.fmt.setColor(c.durationHead, Theme.color.fgDim)
  c.durationButtons = {}
  for index = 1, 3 do
    local button = Theme.Button(c, "ghost", "badge")
    button:SetSize(BUTTON_W, BUTTON_H)
    button:SetLabel(durationLabel(index))
    button:SetScript("OnClick", function() pick(index) end)
    c.durationButtons[index] = button
  end
  -- Wraps, and is never cut: the dock grows to hold it (Forever.Height).
  c.paceLines = Theme.Label(c, 11)
  c.paceLines:SetJustifyH("LEFT"); c.paceLines:SetWordWrap(true)
  UI.fmt.setColor(c.paceLines, Theme.color.fgDim)
  Forever.Hide(c)
end

function Forever.Hide(c)
  if not c.durationHead then return end
  c.durationHead:Hide(); c.paceLines:Hide()
  for _, button in ipairs(c.durationButtons) do button:Hide() end
end

-- The pace lines for the dock's item, top to bottom, each only when it applies.
local function lines(p, qty, why, duration, durationWhy)
  local out = {}
  local function add(text) if text then out[#out + 1] = text end end
  if why == "enough" then
    local unit = GC.SellUtil.effectivePostUnit(p)
    add(GC.Sell.EnoughListedText(p, GC.SellPositions.ListedAtOrBelow(p, unit), duration))
  elseif p.pacePerDay == 0 and why == "pace" then
    local days = tapeDays(p)
    add(days == 1 and GC.L["Nobody bought this here in the last day. Posting 1 to test the price."]
      or (GC.L["Nobody bought this here in the last %d days. Posting 1 to test the price."]):format(days))
  elseif why == "pace" then
    local target = type(p.paceTargets) == "table" and p.paceTargets[duration] or nil
    if target then
      add((GC.L["About %d sell in %d h on this auction house."]):format(target, hoursOf(duration) or 24))
    end
  else
    add(paceSentence(p))
  end
  if durationWhy == "slow" then
    if p.slowWhy == "pace" and (p.pacePerDay or 0) > 0 then
      add((GC.L["24 h: about %s sell a day here."]):format(GC.Util.PerDay(p.pacePerDay)))
    elseif p.slowWhy == "history" and p.returnShort then
      add((GC.L["24 h: came back unsold %d times at %d h."]):format(p.returnShort,
        hoursOf(p.returnShortIndex) or 24))
    end
    local slowQuote = GC.SellBags.Deposit(p, qty, 3)
    local settingQuote = GC.SellBags.Deposit(p, qty, settingIndex())
    if slowQuote and settingQuote and slowQuote ~= settingQuote then
      add((GC.L["Deposit %s instead of %s, returned when it sells."]):format(
        UI.fmt.cell(slowQuote), UI.fmt.cell(settingQuote)))
    end
  end
  add(returnsSentence(p))
  return out
end

--- Paints the row for the dock's item `p`: the lit duration, and the lines. `why` is
--- GC.SellPositions.PostQuantity's word for the number POST lists.
function Forever.Paint(c, p, _, qty, _, why)
  if not c.durationHead then return end
  local duration, durationWhy = GC.Sell.PostDurationFor(p)
  -- Under whichever line the item's name has under it (PostPanel's placeNews).
  local under = c.dockStatus:IsShown() and c.dockStatus or c.dockSub
  c.durationHead:ClearAllPoints()
  c.durationHead:SetPoint("LEFT", under, "BOTTOMLEFT", 0, -(HEAD_GAP + BUTTON_H / 2))
  local previous = c.durationHead
  for index, button in ipairs(c.durationButtons) do
    button:ClearAllPoints()
    button:SetPoint("LEFT", previous, "RIGHT", index == 1 and 8 or 4, 0)
    previous = button
    -- SetVariant before Show, as the kit asks.
    if button.SetVariant then button:SetVariant(index == duration and "active" or "ghost") end
    button:Show()
  end
  c.durationHead:Show()
  local text = table.concat(lines(p, qty, why, duration, durationWhy), "\n")
  c.paceLines:ClearAllPoints()
  c.paceLines:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 0, -(ROW_H + LINES_GAP))
  c.paceLines:SetPoint("TOPRIGHT", under, "BOTTOMRIGHT", 0, -(ROW_H + LINES_GAP))
  c.paceLines:SetText(text)
  if text == "" then c.paceLines:Hide() else c.paceLines:Show() end
end

--- The pixels the row and its lines add under the stock line (PostPanel's fitItem).
function Forever.Height(c)
  if not (c.durationHead and c.durationHead:IsShown()) then return 0 end
  local h = ROW_H
  if c.paceLines:IsShown() then
    local lineH = 14 -- an eleven-point line, where the face cannot be measured
    if c.paceLines.GetStringHeight then
      c.paceLines:SetText(c.paceLines:GetText() or "") -- laid out at this width
      lineH = c.paceLines:GetStringHeight() or lineH
    end
    h = h + LINES_GAP + math.ceil(lineH)
  end
  return h + 2
end

-- The "24 h" a slow seller's stock line ends with, after its tag.
function UI.ROW.foreverMark(position)
  if select(2, GC.Sell.PostDurationFor(position)) ~= "slow" then return "" end
  return "  " .. GC.Sell._InlineColor(Theme.color.fgDim, (GC.L["%d h"]):format(24))
end

-- The pace and the returns, after the rule lines of the row's tooltip.
function UI.fmt.paceTooltip(position)
  if not GameTooltip then return end
  for _, text in ipairs({ paceSentence(position) or "", returnsSentence(position) or "" }) do
    if text ~= "" then GameTooltip:AddLine(GC.Util.ClientText(text), 0.85, 0.85, 0.85, true) end
  end
end
