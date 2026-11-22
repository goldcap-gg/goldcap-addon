local _, GC = ...

-- WoW: Forever: DEALS' BLACKWATER board, the flips through the neutral goblin auction house in Booty
-- Bay, Gadgetzan and Everlook (Core/ForeverFlips.lua says what a flip is; ClickUp 1an60dzy5r4 has
-- the owner's approved picture). Loaded by GoldCap_Camelot.toc alone, after the other Forever DEALS
-- files; retail never loads it, and UI/SniperFrame.lua calls in only where GC.Blackwater exists.
--
-- A third chip beside COMMODITIES and ITEMS. On it the board below the chips is this file's own:
-- one big figure (what one of each flip makes), the flips best first with what each costs there,
-- fetches here and makes after the cut, how fast it sells here, a box to take it or leave it, and
-- one button that writes the checked ones to BUY as the list "Blackwater flips", each line capped
-- where the flip ends. Buying is BUY's: one lot a click, at the auctioneer there. Nothing here asks
-- the auction house anything; the prices are goldcap.gg's, from Blizzard's hourly snapshots.
local S, Flips = GC.Sniper, GC.ForeverFlips
if not (S and Flips) then return end

local BW = {}
GC.Blackwater = BW

local Theme
local LY = {
  CHIP_W = 128, BANNER_H = 58, HEAD_H = 18, ROW_H = 42, ICON = 28, DOCK_H = 70, PAD = 8,
  COL_BW = 92, COL_HOME = 92, COL_MAKE = 100, COL_TAKE = 26, STACK = 6, STACK_ICON = 24,
  GOBLIN = "Interface\\Icons\\Achievement_Goblinhead",
  CHECK = "Interface\\Buttons\\UI-CheckBox-Check",
}
-- Blackwater's own colour, its banner and the line over it: the skin's blue (the token of what is
-- yours), which every skin sets, the paper ones too, where a pale sea green would not read.
local function sea(a) return GC.Kit.Tokens.alpha("yours", a or 1) end

local state = { active = false, view = "deals", unchecked = {}, rows = {}, at = nil, stale = false, loadAsked = {} }
local ui = {}
BW._ui = ui -- what is on screen, for the spec (spec/blackwater_board_spec.lua)

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end

local function prefs()
  return GC.ForeverScan and GC.ForeverScan.Prefs and GC.ForeverScan.Prefs() or nil
end

-- What goldcap.gg sent (the Companion's payload, adopted at load), worked out again when the payload
-- changes or a minute has passed: the chips are painted on DEALS' own clock, four times a second.
local cache = {}
local function readList()
  local payload = GC.Data and GC.Data.ForeverPayload and GC.Data.ForeverPayload() or nil
  local minute = math.floor(time() / 60)
  if cache.payload ~= payload or cache.minute ~= minute then
    cache.payload, cache.minute, cache.list = payload, minute, Flips.Rows(payload, time())
  end
  return cache.list
end

local function itemName(itemID)
  local api = _G.C_Item
  local name = api and api.GetItemNameByID and api.GetItemNameByID(itemID) or nil
  if not name and api and api.RequestLoadItemDataByID and not state.loadAsked[itemID] then
    state.loadAsked[itemID] = true
    pcall(api.RequestLoadItemDataByID, itemID)
  end
  return name
end

local function itemIcon(itemID)
  local api = _G.C_Item
  return api and api.GetItemIconByID and api.GetItemIconByID(itemID) or 134400
end

local function checkedSet()
  local set = {}
  for _, r in ipairs(state.rows) do
    if not state.unchecked[r.itemID] then set[r.itemID] = true end
  end
  return set
end

-- ---------------------------------------------------------------------------------------------
-- The BUY list: the player's own list "Blackwater flips" (prefs.blackwaterList), made once and
-- written again on every press, as HERO keeps its Upgrades list.

local function bwRun()
  local p = prefs()
  local run = p and p.blackwaterList and GC.AppRuns and GC.AppRuns.Get(p.blackwaterList) or nil
  return type(run) == "table" and run.origin == "game" and run or nil
end

local function ensureRun()
  local run = bwRun()
  if run or not (GC.AppRuns and GC.AppRuns.NewList) then return run end
  run = GC.AppRuns.NewList(GC.L["Blackwater flips"], {})
  local p = prefs()
  if run and p then p.blackwaterList = run.code end
  return run
end

function BW.AddToBuy()
  local lines, caps = Flips.Lines(state.rows, checkedSet())
  if #lines == 0 then return false end
  local run = ensureRun()
  if not run then return false end
  -- One more of each, whatever an earlier trip bought on the list or the bags still hold: the list
  -- is emptied first, so what was bought on its lines no longer counts (GC.AppRuns.SetLines), and
  -- each line asks for one more than is held now (`h`, as the BUY box adds a line).
  for _, line in ipairs(lines) do
    line.h = GC.Buy and GC.Buy.HaveOf and GC.Buy.HaveOf(line.i) or nil
  end
  GC.AppRuns.SetLines(run.code, {}, false)
  if not GC.AppRuns.SetLines(run.code, lines, true) then return false end
  if GC.Buy and GC.Buy._SetLineCap then
    for itemID, cap in pairs(caps) do GC.Buy._SetLineCap(run.code, itemID, cap) end
  end
  GC.AppRuns.SetArchived(run.code, false)
  if GC.Buy and GC.Buy.SelectRun then GC.Buy.SelectRun(run.code) end
  if S.ShowView then S.ShowView("buy") end
  return true
end

-- ---------------------------------------------------------------------------------------------
-- Rows.

local paint

local function money(copper) return GC.Util.Money(copper) end

local function speed(r)
  if r.slow then return GC.L["SLOW"], Theme.color.amber end
  if r.sold and r.sold > 0 and r.soldHours then
    return GC.L["%d sold at home in %d days"]:format(r.sold, math.max(1, math.floor(r.soldHours / 24 + 0.5))),
      Theme.color.green
  end
  return nil
end

local function showItemTip(row)
  if not row.itemID or not _G.GameTooltip then return end
  _G.GameTooltip:SetOwner(row, Theme.TooltipAnchor and Theme.TooltipAnchor(row) or "ANCHOR_RIGHT")
  _G.GameTooltip:SetItemByID(row.itemID)
  _G.GameTooltip:Show()
end

local function createRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(LY.ROW_H)
  row.plate = Theme.ShapeTexture(row, "BACKGROUND", "control", Theme.color.zebra)
  row.plate:SetPoint("TOPLEFT", 0, -1)
  row.plate:SetPoint("BOTTOMRIGHT", 0, 1)
  row.highlight = Theme.ShapeTexture(row, "BACKGROUND", "control", Theme.color.hover)
  row.highlight:SetDrawLayer("BACKGROUND", 1)
  row.highlight:SetAllPoints(row.plate)
  row.highlight:Hide()
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self) self.highlight:Show() showItemTip(self) end)
  row:SetScript("OnLeave", function(self)
    self.highlight:Hide()
    if _G.GameTooltip then _G.GameTooltip:Hide() end
  end)

  row.iconEdge = row:CreateTexture(nil, "BORDER")
  row.iconEdge:SetSize(LY.ICON + 2, LY.ICON + 2)
  row.iconEdge:SetPoint("LEFT", row, "LEFT", 6, 0)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(LY.ICON, LY.ICON)
  row.icon:SetPoint("CENTER", row.iconEdge, "CENTER")
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.name = Theme.Label(row, 12)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.name:SetPoint("TOPLEFT", row.iconEdge, "TOPRIGHT", 8, 1)
  row.sub = Theme.Num(row, 10)
  row.sub:SetJustifyH("LEFT")
  setColor(row.sub, Theme.color.fgDim)
  row.sub:SetPoint("BOTTOMLEFT", row.iconEdge, "BOTTOMRIGHT", 8, -1)
  row.tag = Theme.Num(row, 9, true)
  row.tag:SetJustifyH("LEFT")
  row.tag:SetPoint("LEFT", row.sub, "RIGHT", 8, 0)

  row.take = CreateFrame("Button", nil, row)
  row.take:SetSize(18, 18)
  row.take:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row.take.box = Theme.ShapeTexture(row.take, "BACKGROUND", "control", Theme.color.border, true)
  row.take.box:SetAllPoints()
  row.take.mark = row.take:CreateTexture(nil, "ARTWORK")
  row.take.mark:SetTexture(LY.CHECK)
  row.take.mark:SetPoint("CENTER", 1, 0)
  row.take.mark:SetSize(22, 22)
  row.take:SetScript("OnClick", function(self)
    local id = self:GetParent().itemID
    if not id then return end
    state.unchecked[id] = not state.unchecked[id] or nil
    paint()
  end)

  row.make = Theme.Num(row, 12, true)
  row.make:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(LY.COL_TAKE + 6), -7)
  setColor(row.make, Theme.color.green)
  row.pct = Theme.Num(row, 10)
  row.pct:SetPoint("TOPRIGHT", row.make, "BOTTOMRIGHT", 0, -2)
  setColor(row.pct, Theme.color.fgDim)
  row.home = Theme.Num(row, 12, true)
  row.home:SetPoint("RIGHT", row, "RIGHT", -(LY.COL_TAKE + 6 + LY.COL_MAKE), 0)
  setColor(row.home, Theme.color.fg)
  row.bw = Theme.Num(row, 12, true)
  row.bw:SetPoint("RIGHT", row, "RIGHT", -(LY.COL_TAKE + 6 + LY.COL_MAKE + LY.COL_HOME), 0)
  setColor(row.bw, Theme.color.fg)
  row.name:SetPoint("RIGHT", row, "RIGHT", -(LY.COL_TAKE + 6 + LY.COL_MAKE + LY.COL_HOME + LY.COL_BW), 0)
  return row
end

local function paintRow(row, r)
  row.itemID = r.itemID
  row.icon:SetTexture(itemIcon(r.itemID))
  -- The edge in the item's quality colour as the skin draws it, as on the Sold rows.
  local q = Theme.QualityColor(r.itemID, false)
  local edge = q and { q.r, q.g, q.b, 0.6 } or GC.Kit.Tokens.ink(0.16)
  row.iconEdge:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
  row.name:SetText(Theme.WithQuality(itemName(r.itemID) or GC.L["item %d"]:format(r.itemID), r.itemID, 12))
  row.sub:SetText(GC.L["%d cheap at Blackwater · %d listed at home"]:format(r.bwQty or 0, r.homeQty or 0))
  local tag, colour = speed(r)
  row.tag:SetText(tag or "")
  if colour then setColor(row.tag, colour) end
  row.bw:SetText(money(r.bw))
  row.home:SetText(money(r.home))
  row.make:SetText("+" .. money(r.profit))
  row.pct:SetText(("+%d%%"):format(r.pct))
  local taken = not state.unchecked[r.itemID]
  row.take.mark:SetShown(taken)
  row:SetAlpha(taken and 1 or 0.55)
  row:Show()
end

-- ---------------------------------------------------------------------------------------------
-- The board.

local function header(parent, text, right)
  local fs = Theme.Num(parent, 9, true)
  fs:SetText(text)
  setColor(fs, Theme.color.fgDim)
  fs:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -right, 2)
  return fs
end

local function build(container)
  -- The banner: Blackwater's goblin, one big figure, what it takes.
  local banner = CreateFrame("Frame", nil, container)
  banner:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  banner:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
  banner:SetHeight(LY.BANNER_H)
  banner.fill = Theme.ShapeTexture(banner, "BACKGROUND", "control", sea(0.07))
  banner.fill:SetAllPoints()
  banner.ring = Theme.ShapeTexture(banner, "BORDER", "control", sea(0.4), true)
  banner.ring:SetAllPoints()
  banner.goblin = banner:CreateTexture(nil, "ARTWORK")
  banner.goblin:SetSize(40, 40)
  banner.goblin:SetPoint("LEFT", banner, "LEFT", 9, 0)
  banner.goblin:SetTexture(LY.GOBLIN)
  banner.goblin:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  banner.over = Theme.Num(banner, 9, true)
  banner.over:SetJustifyH("LEFT")
  banner.over:SetPoint("TOPLEFT", banner.goblin, "TOPRIGHT", 10, -1)
  setColor(banner.over, sea())
  banner.over:SetText(GC.L["BLACKWATER AUCTION HOUSE · BOOTY BAY, GADGETZAN, EVERLOOK"])
  banner.big = Theme.Num(banner, 20, true)
  banner.big:SetJustifyH("LEFT")
  banner.big:SetPoint("BOTTOMLEFT", banner.goblin, "BOTTOMRIGHT", 10, -1)
  setColor(banner.big, Theme.color.goldHi)
  banner.what = Theme.Label(banner, 11)
  banner.what:SetJustifyH("LEFT")
  banner.what:SetPoint("LEFT", banner.big, "RIGHT", 10, 0)
  setColor(banner.what, Theme.color.fgMuted)
  banner.cost = Theme.Label(banner, 10)
  banner.cost:SetJustifyH("RIGHT")
  banner.cost:SetPoint("RIGHT", banner, "RIGHT", -12, 0)
  setColor(banner.cost, Theme.color.fgMuted)
  banner.what:SetPoint("RIGHT", banner.cost, "LEFT", -10, 0)
  banner.what:SetWordWrap(true)
  banner.what:SetMaxLines(2)
  ui.banner = banner

  -- The headings.
  local head = CreateFrame("Frame", nil, container)
  head:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -6)
  head:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT", 0, -6)
  head:SetHeight(LY.HEAD_H)
  local item = Theme.Num(head, 9, true)
  item:SetText(GC.L["ITEM"])
  setColor(item, Theme.color.fgDim)
  item:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 8, 2)
  header(head, GC.L["YOU MAKE"], LY.COL_TAKE + 6)
  header(head, GC.L["HOME"], LY.COL_TAKE + 6 + LY.COL_MAKE)
  header(head, GC.L["BLACKWATER"], LY.COL_TAKE + 6 + LY.COL_MAKE + LY.COL_HOME)
  ui.head = head

  -- The dock: what the checked rows take and make, and the one button.
  local dock = CreateFrame("Frame", nil, container)
  dock:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
  dock:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
  dock:SetHeight(LY.DOCK_H)
  dock.card = Theme.Card(dock, nil, nil, true)
  dock.card:SetAllPoints()
  dock.stack = {}
  for i = 1, LY.STACK do
    local t = dock:CreateTexture(nil, "ARTWORK", nil, LY.STACK - i)
    t:SetSize(LY.STACK_ICON, LY.STACK_ICON)
    t:SetPoint("TOPLEFT", dock, "TOPLEFT", 10 + (i - 1) * (LY.STACK_ICON - 7), -9)
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    dock.stack[i] = t
  end
  dock.button = Theme.Button(dock, "primary", "plaque")
  dock.button:SetSize(132, 30)
  dock.button:FitLabels({ GC.L["ADD %d TO BUY"]:format(99) }, 132)
  dock.button:SetPoint("TOPRIGHT", dock, "TOPRIGHT", -10, -6)
  dock.button:SetScript("OnClick", function() BW.AddToBuy() end)
  dock.makeLabel = Theme.Num(dock, 9, true)
  dock.makeLabel:SetPoint("TOPRIGHT", dock.button, "TOPLEFT", -14, -1)
  dock.makeLabel:SetText(GC.L["YOU MAKE"])
  setColor(dock.makeLabel, Theme.color.fgDim)
  dock.make = Theme.Num(dock, 12, true)
  dock.make:SetPoint("TOPRIGHT", dock.makeLabel, "BOTTOMRIGHT", 0, -3)
  setColor(dock.make, Theme.color.green)
  dock.spendLabel = Theme.Num(dock, 9, true)
  dock.spendLabel:SetPoint("TOPRIGHT", dock.makeLabel, "TOPLEFT", -40, 0)
  dock.spendLabel:SetText(GC.L["YOU SPEND"])
  setColor(dock.spendLabel, Theme.color.fgDim)
  dock.spend = Theme.Num(dock, 12, true)
  dock.spend:SetPoint("TOPRIGHT", dock.spendLabel, "BOTTOMRIGHT", 0, -3)
  setColor(dock.spend, Theme.color.fg)
  dock.title = Theme.Label(dock, 12)
  dock.title:SetJustifyH("LEFT")
  dock.title:SetPoint("TOPLEFT", dock, "TOPLEFT", 10 + LY.STACK * (LY.STACK_ICON - 7) + 14, -8)
  dock.title:SetPoint("RIGHT", dock.spendLabel, "LEFT", -12, 0)
  setColor(dock.title, Theme.color.fg)
  dock.sub = Theme.Label(dock, 10)
  dock.sub:SetJustifyH("LEFT")
  dock.sub:SetPoint("TOPLEFT", dock.title, "BOTTOMLEFT", 0, -3)
  dock.sub:SetPoint("RIGHT", dock.spendLabel, "LEFT", -12, 0)
  setColor(dock.sub, Theme.color.fgDim)
  dock.rule = Theme.Solid(dock, "ARTWORK", Theme.color.border)
  dock.rule:SetHeight(1)
  dock.rule:SetPoint("BOTTOMLEFT", dock, "BOTTOMLEFT", 10, 24)
  dock.rule:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", -10, 24)
  dock.note = Theme.Label(dock, 10)
  dock.note:SetJustifyH("LEFT")
  dock.note:SetPoint("BOTTOMLEFT", dock, "BOTTOMLEFT", 10, 7)
  setColor(dock.note, Theme.color.fgDim)
  dock.slow = Theme.Label(dock, 10)
  dock.slow:SetJustifyH("RIGHT")
  dock.slow:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", -10, 7)
  dock.slow:SetPoint("LEFT", dock.note, "RIGHT", 12, 0)
  setColor(dock.slow, Theme.color.amber)
  ui.dock = dock

  -- The list between them.
  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  if Theme.QuietScrollBar then Theme.QuietScrollBar(scroll) end
  scroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
  scroll:SetPoint("BOTTOMRIGHT", dock, "TOPRIGHT", 0, 6)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  ui.scroll, ui.content, ui.rows = scroll, content, {}

  -- What the board says when it has no rows.
  local empty = Theme.Label(container, 12)
  empty:SetPoint("TOP", head, "BOTTOM", 0, -40)
  empty:SetPoint("LEFT", container, "LEFT", 40, 0)
  empty:SetPoint("RIGHT", container, "RIGHT", -40, 0)
  empty:SetJustifyH("CENTER")
  empty:SetWordWrap(true)
  setColor(empty, Theme.color.fgMuted)
  ui.empty = empty
end

local function paintDock()
  local dock = ui.dock
  local n, spend, make = Flips.Totals(state.rows, checkedSet())
  local shown = 0
  for _, r in ipairs(state.rows) do
    if shown >= LY.STACK then break end
    if not state.unchecked[r.itemID] then
      shown = shown + 1
      dock.stack[shown]:SetTexture(itemIcon(r.itemID))
      dock.stack[shown]:Show()
    end
  end
  for i = shown + 1, LY.STACK do dock.stack[i]:Hide() end
  dock.title:SetText(GC.L["%d checked, one of each"]:format(n))
  dock.sub:SetText(GC.L["They go to BUY as the list %s"]:format(GC.L["Blackwater flips"]))
  dock.spend:SetText(money(spend))
  dock.make:SetText("+" .. money(make))
  dock.button:SetLabel(GC.L["ADD %d TO BUY"]:format(n))
  if n > 0 then dock.button:Enable() else dock.button:Disable() end
  local note
  if state.stale then
    note = GC.L["These prices are %s old. The Companion brings new ones from goldcap.gg."]:format(
      GC.Util.FormatAge(time() - (state.at or time())))
  else
    note = GC.L["Prices from goldcap.gg at %s. BUY checks each one again at the Blackwater auctioneer."]:format(
      date("%H:%M", state.at or time()))
  end
  dock.note:SetText(note)
  local slow = false
  for _, r in ipairs(state.rows) do if r.slow then slow = true break end end
  dock.slow:SetText(slow and GC.L["Slow: under one a day sells at home"] or "")
end

paint = function()
  if not ui.container then return end
  local list = readList()
  state.rows = list and list.rows or {}
  state.at, state.stale = list and list.at or nil, list and list.stale or false
  local n, spend, make = Flips.Totals(state.rows)
  local banner = ui.banner
  banner.big:SetText("+" .. money(make))
  banner.what:SetText(GC.L["buy one of each of these %d at Blackwater, sell them at home"]:format(n))
  banner.cost:SetText(GC.L["they cost %s"]:format(money(spend)) .. "\n" .. GC.L["after the 5% cut at home"])

  local width = ui.scroll:GetWidth()
  if not width or width <= 0 then width = ui.container:GetWidth() or 600 end
  ui.content:SetWidth(width)
  for i, r in ipairs(state.rows) do
    local row = ui.rows[i]
    if not row then
      row = createRow(ui.content)
      ui.rows[i] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", ui.content, "TOPLEFT", 0, -(i - 1) * (LY.ROW_H + 3))
    row:SetWidth(width)
    paintRow(row, r)
  end
  for i = #state.rows + 1, #ui.rows do ui.rows[i]:Hide() end
  ui.content:SetHeight(math.max(1, #state.rows * (LY.ROW_H + 3)))

  local has = #state.rows > 0
  ui.banner:SetShown(has)
  ui.head:SetShown(has)
  ui.dock:SetShown(has)
  if list == nil then
    ui.empty:SetText(GC.L["No Blackwater prices yet. goldcap.gg sends them with the Companion's next sync."])
  elseif not has then
    ui.empty:SetText(GC.L["Nothing at Blackwater is 1g or more cheaper than at home right now."])
  end
  ui.empty:SetShown(not has)
  if has then paintDock() end
  if S._PaintBoardChips then S._PaintBoardChips() end
end
BW.Paint = function() paint() end

-- ---------------------------------------------------------------------------------------------
-- The chip, and the board's place among the others.

local function showBoard()
  local f, on = ui.frame, state.active and state.view == "deals"
  if not f then return end
  if on then
    f.scroll:Hide()
    f.headerRow:Hide()
    ui.container:Show()
    paint()
  else
    ui.container:Hide()
    if state.view == "deals" then
      f.scroll:Show()
      f.headerRow:Show()
    end
  end
end

function BW.SetActive(on)
  state.active = on and true or false
  if ui.frame and ui.frame.scroll then ui.frame.scroll:SetVerticalScroll(0) end
  showBoard()
  if S._PaintBoardChips then S._PaintBoardChips() end
end

function BW.Active() return state.active end

-- setView's last word (UI/SniperFrame.lua): the board follows the rail.
function BW.OnView(v)
  state.view = v
  showBoard()
end

-- COMMODITIES and ITEMS take the board back.
local setBoard = S._SetBoard
S._SetBoard = function(id)
  if state.active then
    state.active = false
    showBoard()
  end
  return setBoard(id)
end

-- The chips' paint: ours lit while the board is up, and the other two dark then.
local paintChips = S._PaintBoardChips
S._PaintBoardChips = function(target)
  paintChips(target)
  local owner = target or ui.frame
  local chips = owner and owner.boardChips
  local chip = chips and chips.blackwater
  if not chip then return end
  local list = readList()
  local n = list and Flips.Totals(list.rows) or 0
  chip:SetLabel(n > 0 and GC.L["BLACKWATER %d"]:format(n) or GC.L["BLACKWATER"])
  chip:SetVariant(state.active and "active" or "ghost")
  if not state.active then return end
  for id, c in pairs(chips) do
    if id ~= "blackwater" then c:SetVariant("ghost") end
  end
  -- "Only what I lack" is the Items board's, and the Items board is not the one up.
  if owner.lackToggle and owner.lackToggle:IsShown() then
    owner.lackToggle:Hide()
    S._LayoutBoardRow(owner)
  end
end

-- The session line and the gold line start after the last chip, which is now ours.
local layoutRow = S._LayoutBoardRow
S._LayoutBoardRow = function(target)
  layoutRow(target)
  local owner = target or ui.frame
  local chip = owner and owner.boardChips and owner.boardChips.blackwater
  if not chip then return end
  for _, w in ipairs({ owner.sessionText, owner.goldLine }) do
    if w then w:SetPoint("LEFT", chip, "RIGHT", Theme.pad.m, 0) end
  end
end

-- UI/SniperFrame.lua's createFrame, after the other tabs attach: `geo.top` is the headings' row,
-- the board below the chips.
function BW.Attach(f, geo)
  Theme = GC.Theme
  ui.frame = f
  local items = f.boardChips and f.boardChips.items
  if items then
    local chip = Theme.Button(f, "ghost", "plaque")
    chip:SetSize(LY.CHIP_W, items:GetHeight())
    chip:FitLabels({ GC.L["BLACKWATER"], GC.L["BLACKWATER %d"]:format(99) }, LY.CHIP_W)
    chip:SetPoint("LEFT", items, "RIGHT", Theme.pad.xs, 0)
    chip:SetScript("OnClick", function() BW.SetActive(not state.active) end)
    chip:SetScript("OnEnter", function(self)
      if not _G.GameTooltip then return end
      _G.GameTooltip:SetOwner(self, Theme.TooltipAnchor and Theme.TooltipAnchor(self) or "ANCHOR_RIGHT")
      _G.GameTooltip:SetText(GC.Util.ClientText(GC.L["Blackwater: what the neutral auction house in Booty Bay, Gadgetzan and Everlook sells for less than your faction's auction house. Buy there, post at home."]), 1, 1, 1, 1, true)
      _G.GameTooltip:Show()
    end)
    chip:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)
    f.boardChips.blackwater = chip
    if type(f.dealsChrome) == "table" then f.dealsChrome[#f.dealsChrome + 1] = chip end
    f._boardRowLayout = nil
    S._LayoutBoardRow(f)
  end
  local container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", f, "TOPLEFT", geo.panelLeft, geo.top)
  container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -geo.panelRightInset, geo.bottom)
  container:SetFrameLevel((f.scroll and f.scroll:GetFrameLevel() or f:GetFrameLevel()) + 5)
  container:Hide()
  ui.container = container
  build(container)
  container:HookScript("OnSizeChanged", function() if container:IsShown() then paint() end end)
  if Theme.OnRescale then Theme.OnRescale(function() if container:IsShown() then paint() end end) end
  S._PaintBoardChips(f)
end

-- A name the client loads while the board is up repaints it, once a beat.
local events = CreateFrame("Frame")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local due = false
events:SetScript("OnEvent", function()
  if due or not (ui.container and ui.container:IsShown()) then return end
  due = true
  C_Timer.After(0.3, function()
    due = false
    if ui.container and ui.container:IsShown() then paint() end
  end)
end)
