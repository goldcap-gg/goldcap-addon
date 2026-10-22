local _, GC = ...

-- The craft panel's Queue view (retail, beside the profession window): this character's queued
-- recipes with what is left to craft, the reagents the queue is short of, and Make a BUY list,
-- which turns exactly those into a list the BUY tab buys at the auction house. Nothing is bought
-- here, and nothing is crafted here: a craft from Blizzard's own button takes one off a counted
-- line all the same (UNIT_SPELLCAST_SUCCEEDED).
--
-- Its events are its own, each registered under pcall (Core/Collection.lua's shape), so
-- Core/Init.lua is not touched. The arithmetic is Core/CraftQueue.lua's; every count and price
-- comes through Services/CraftClient.lua.
GC.CraftQueueView = GC.CraftQueueView or {}
local QV = GC.CraftQueueView

local LAYOUT = { GAP = 6, LINE_GAP = 2, NAME = 11, SMALL = 10, HEAD = 12, ROW_PAD = 4, BAR = 16,
  BUTTON_H = 24, BUTTON_MIN = 72 }

local function bodyWidth()
  return GC.CraftPanel and GC.CraftPanel.BODY_W or 280
end

local function after(fn)
  local timer = _G.C_Timer
  if type(timer) == "table" and type(timer.After) == "function" then timer.After(0, fn) else fn() end
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function wrapped(parent, size, width)
  local fs = GC.Theme.Label(parent, size)
  fs:SetWordWrap(true)
  fs:SetWidth(width)
  return fs
end

-- The queue as it stands: one row per entry ({ entry, crafts, held }), what the queue is short
-- of, and when the auction house was last read for this character (nil: not yet).
local function work(char)
  local CC, Q = GC.CraftClient, GC.CraftQueue
  local entries = Q.Entries(char)
  local listed, listedAt = Q.Listed(char)
  local rows, crafts = {}, {}
  for i, e in ipairs(entries) do
    local held = e.restock and Q.Held(e, CC.CountOf, listed) or nil
    local n = Q.CraftsNeeded(e, held or 0)
    crafts[e] = n
    rows[i] = { entry = e, crafts = n, held = held }
  end
  local missing = Q.Missing(Q.Needs(entries, function(e) return crafts[e] end), CC.CountOf, CC.CurrencyCount)
  return rows, missing, listedAt
end

--- A queue line's right click: more crafts, a restock target, or off the queue.
function QV.OpenLineMenu(owner, entry)
  local menu = _G.MenuUtil
  if not (type(menu) == "table" and menu.CreateContextMenu and type(entry) == "table" and GC.CraftQueue.Writable()) then
    return false
  end
  local recipe = entry.recipe
  menu.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(GC.Util.ClientText(recipe.name))
    root:CreateButton(GC.Util.ClientText(GC.L["Add to queue"]), function() GC.CraftPanel.AskCount(owner, recipe) end)
    root:CreateButton(GC.Util.ClientText(GC.L["Restock to"]), function() GC.CraftPanel.AskRestock(owner, recipe) end)
    root:CreateButton(GC.Util.ClientText(GC.L["Remove from queue"]), function()
      local char = GC.CraftClient.Char()
      if char then GC.CraftQueue.Remove(char, recipe.recipeID) end
      QV.Queue()
    end)
  end)
  return true
end

local function newLine(v)
  local T = GC.Theme
  local width = bodyWidth() - LAYOUT.BAR
  local frame = CreateFrame("Button", nil, v.content)
  frame:SetWidth(width)
  local line = { frame = frame }
  line.name = wrapped(frame, LAYOUT.NAME, width)
  line.name:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -LAYOUT.ROW_PAD)
  setColor(line.name, T.color.fg)
  line.detail = wrapped(frame, LAYOUT.SMALL, width)
  line.detail:SetPoint("TOPLEFT", line.name, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  setColor(line.detail, T.color.fgMuted)
  line.note = wrapped(frame, LAYOUT.SMALL, width)
  line.note:SetPoint("TOPLEFT", line.detail, "BOTTOMLEFT", 0, -LAYOUT.LINE_GAP)
  setColor(line.note, T.color.fgDim)
  frame:RegisterForClicks("RightButtonUp")
  frame:SetScript("OnClick", function(self, button)
    if button == "RightButton" and line.entry then QV.OpenLineMenu(self, line.entry) end
  end)
  return line
end

--- Builds the view in the panel's body (UI/CraftPanel.lua calls this once, hidden until picked).
function QV.Build(host)
  if QV._frame then return QV._frame end
  local T = GC.Theme
  local width = bodyWidth() - LAYOUT.BAR
  local v = CreateFrame("Frame", nil, host)
  v:SetAllPoints(host)
  v.buy = T.Button(v, "primary", "plaque")
  v.buy:SetHeight(LAYOUT.BUTTON_H)
  v.buy:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 0, 0)
  v.buy:SetScript("OnClick", function() QV.MakeBuyList() end)
  v.scroll = CreateFrame("ScrollFrame", nil, v, "UIPanelScrollFrameTemplate")
  if T.QuietScrollBar then T.QuietScrollBar(v.scroll) end
  v.scroll:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
  v.scroll:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", -LAYOUT.BAR, LAYOUT.BUTTON_H + LAYOUT.GAP)
  v.content = CreateFrame("Frame", nil, v.scroll)
  v.content:SetSize(width, 1)
  v.scroll:SetScrollChild(v.content)
  v.empty = wrapped(v.content, LAYOUT.NAME, width)
  setColor(v.empty, T.color.fgMuted)
  v.missingHeading = T.Heading(v.content, LAYOUT.HEAD)
  v.missingHeading:SetJustifyH("LEFT")
  v.missingHeading:SetWordWrap(true)
  v.missingHeading:SetWidth(width)
  setColor(v.missingHeading, T.color.gold)
  v.none = wrapped(v.content, LAYOUT.SMALL, width)
  setColor(v.none, T.color.fgMuted)
  v.lines, v.missingLines = {}, {}
  v:Hide()
  QV._frame = v
  return v
end

-- Places `region` at `y` down the content and answers the y under it.
local function stack(v, region, y, gap)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, -(y + gap))
  region:Show()
  return y + gap + region:GetHeight()
end

local function paintLine(line, row, listedAt)
  local e = row.entry
  line.entry = e
  line.name:SetText(e.recipe.name)
  if e.count then
    line.detail:SetText(GC.L["%d to craft"]:format(e.count))
  else
    line.detail:SetText(GC.L["Restock to %d: %d held"]:format(e.restock, row.held or 0))
  end
  local height = LAYOUT.ROW_PAD + line.name:GetHeight() + LAYOUT.LINE_GAP + line.detail:GetHeight()
  -- A restock counts what is up on the auction house too, and that is read only there, when
  -- something asks the auction house for the character's own auctions: in GoldCap, the Sell tab
  -- (Services/Sell/Owned.lua). Until then, say so rather than craft more than is needed without
  -- a word.
  if e.restock and listedAt == nil then
    line.note:SetText(GC.L["Auctions not counted yet: open GoldCap's Sell tab at the auction house"])
    line.note:Show()
    height = height + LAYOUT.LINE_GAP + line.note:GetHeight()
  else
    line.note:Hide()
  end
  line.frame:SetHeight(height + LAYOUT.ROW_PAD)
end

local function missingText(row)
  local CC = GC.CraftClient
  if row.currency then
    return GC.L["%s is not sold on the auction house"]:format(CC.MissingName({ currencyID = row.currency }))
  end
  return GC.L["%d %s"]:format(row.missing, CC.MissingName({ itemID = row.ids[1] }))
end

--- Reads the queue again and repaints the view, while it is on screen.
function QV.Refresh()
  QV._pending = false
  local v = QV._frame
  if not (v and v:IsVisible()) then return end
  local char = GC.CraftClient.Char()
  local rows, missing, listedAt = work(char)
  QV._rows = rows
  local y = 0
  for i, row in ipairs(rows) do
    local line = v.lines[i] or newLine(v)
    v.lines[i] = line
    paintLine(line, row, listedAt)
    row.widget = line
    y = stack(v, line.frame, y, 0)
  end
  for i = #rows + 1, #v.lines do
    v.lines[i].frame:Hide()
    v.lines[i].entry = nil
  end

  local width = bodyWidth() - LAYOUT.BAR
  if #rows == 0 then
    v.empty:SetText(GC.L["The queue is empty. Add a recipe from This recipe."])
    y = stack(v, v.empty, y, LAYOUT.ROW_PAD)
    v.missingHeading:Hide()
    v.none:Hide()
  else
    v.empty:Hide()
    v.missingHeading:SetText(GC.L["Missing"])
    y = stack(v, v.missingHeading, y, 2 * LAYOUT.GAP)
    if #missing == 0 then
      v.none:SetText(GC.L["Nothing is missing for the queue"])
      y = stack(v, v.none, y, LAYOUT.LINE_GAP)
    else
      v.none:Hide()
    end
  end
  local shown = #rows > 0 and #missing or 0
  for i = 1, shown do
    local fs = v.missingLines[i]
    if not fs then
      fs = wrapped(v.content, LAYOUT.SMALL, width)
      setColor(fs, GC.Theme.color.fg)
      v.missingLines[i] = fs
    end
    fs:SetText(missingText(missing[i]))
    y = stack(v, fs, y, LAYOUT.LINE_GAP)
  end
  for i = shown + 1, #v.missingLines do v.missingLines[i]:Hide() end
  v.content:SetHeight(math.max(1, y + LAYOUT.ROW_PAD))

  v.buy:SetLabel(GC.L["Make a BUY list"])
  v.buy:FitLabels({ v.buy.label }, LAYOUT.BUTTON_MIN)
  local lines = GC.CraftQueue.BuyLines(missing, GC.CraftClient.UnitOf, GC.CraftClient.CountOf)
  if #lines > 0 then v.buy:Enable() else v.buy:Disable() end
end

--- One repaint on the next frame, however many times this is asked for before then.
function QV.Queue()
  if QV._pending then return end
  QV._pending = true
  after(QV.Refresh)
end

--- A new BUY list named "Craft queue" holding what the queue is short of, the cheapest priced
--- quality of each reagent, shown in the BUY tab. Returns the list, or nil when nothing is missing.
function QV.MakeBuyList()
  local char = GC.CraftClient.Char()
  if not char then return nil end
  local _, missing = work(char)
  local lines = GC.CraftQueue.BuyLines(missing, GC.CraftClient.UnitOf, GC.CraftClient.CountOf)
  if #lines == 0 then return nil end
  local run = GC.AppRuns.NewList(GC.L["Craft queue"], lines)
  if not run then return nil end
  if GC.Buy and GC.Buy.SelectRun then GC.Buy.SelectRun(run.code) end
  if GC.Buy and GC.Buy.RefreshIfShown then GC.Buy.RefreshIfShown() end
  GC.Print(GC.L["BUY list %s is ready in the BUY tab at the auction house"]:format(GC.AppRuns.Label(run)))
  return run
end

--- UNIT_SPELLCAST_SUCCEEDED: a craft of a counted recipe takes one off its line, the window open
--- or not. OWNED_AUCTIONS_UPDATED: what this character has up on the auction house, for restocks.
function QV.OnEvent(event, ...)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    local _, _, spellID = ...
    -- Every cast the player makes lands here. In a restricted context the client hands a secret
    -- spell id, which addon code may not compare: such a cast is never a craft from the queue.
    local ok, changed = pcall(function()
      local secret = _G.issecretvalue
      if type(secret) == "function" and secret(spellID) then return false end
      local char = GC.CraftClient.Char()
      return char ~= nil and GC.CraftQueue.OnCraftSucceeded(char, spellID)
    end)
    if ok and changed then QV.Queue() end
  elseif event == "OWNED_AUCTIONS_UPDATED" then
    if GC.CraftClient.ReadListed() then QV.Queue() end
  end
end

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
  pcall(events.RegisterEvent, events, "OWNED_AUCTIONS_UPDATED")
  events:SetScript("OnEvent", function(_, event, ...) QV.OnEvent(event, ...) end)
  QV._events = events
end

-- What the panel's This recipe and row menu add shows here at once.
if GC.CraftPanel then GC.CraftPanel.OnQueueChanged = QV.Refresh end
