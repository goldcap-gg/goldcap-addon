local _, GC = ...

-- GoldCap Hoard (retail only): a window of GoldCap's beside Blizzard's bank window (owner,
-- 2026-10-24; it took over from the bank by group card and the GoldCap tab on the bank window,
-- which the owner turned down). The groups the player follows on goldcap.gg that have items in the
-- bags or the bank it works with, each as one row: its name, its play, its items' icons with how
-- many there are, what they are worth here, Store and Take out, and a bar of how much is in the
-- bags and how much in the bank. The subgroups of one group on goldcap.gg fold into a folder; the
-- groups with nothing to move at this bank fold into one line that opens them. A click on a group's
-- row opens it: every item with where it is, how many of each item it keeps in the bags
-- (GC.db.bankKeep, Core/BankGroups.lua), and which stacks stay in the bags and why. What each press
-- moves, and in which order, is Core/BankGroups.lua's Plan; the rows, folders and the fold line are
-- Core/Hoard.lua's Rows; an item's group is Core/GroupRules.lua's; a row of the list, its widgets
-- and its painting, is UI/HoardRow.lua's, loaded after this file; the search row over many groups,
-- the selection bar and a run's cast bar are UI/HoardList.lua's, loaded after that. With no
-- followed group and no section there is no window at all: it is not built and no slot is read
-- for it.
--
-- Which bank: the character's own or the Warband Bank, a two-way switch under the title named and
-- ordered as the bank window's tabs are. At each open it starts on the bank the window shows
-- (GC.BankRoute.ShownBankType), and it goes along when the window comes to show the other bank (the
-- player clicks its tab: the post-hook on BankPanel's Reset at the end of this file). A click on
-- the switch holds until then or until the bank closes: a bag addon such as Bagnon keeps Blizzard's
-- hidden window on the character's bank for the whole visit, and the switch is how its player
-- reaches the Warband Bank. A bank with no tab bought, or out of reach at this banker, is a
-- disabled side, and the window works with the other.
--
-- One press moves the button's whole list, a stack at a time, through the bank route's MoveStack,
-- whose guards apply to every move: the bank is the window, no spell waits for an item target and
-- the cursor is empty, the slot still holds the stack, unlocked, and the bank may take it
-- (spec/bank_route_spec.lua audits the call sites). The press is the vendor card's machine
-- (Core/VendorPress.lua): the first move inside the player's click, the rest 0.2 s apart from its
-- timers, each once the one before has left its slot. One run at a time, for the whole window
-- (Press), known by what it moves (its button's run id: a group's Store, a folder's Take out) and
-- not by the widget pressed, as rows are pooled by place and a folder opened mid-run draws another
-- group on the running row's widget. A second press of what runs stops it, a press of anything
-- else stops it and starts its own, and the bank closing, the switch changing and the window
-- closing stop it too. A move that stays (a full bank or bags: the game says so itself) ends the
-- run without a word, and the next press still makes its first move in the click. A stack sent is
-- offered again only if the bags have not shown it moved within the route's SETTLE_SECONDS.
--
-- Pressed again and again in one spot, so nothing in the window moves between two presses or while
-- one runs: every row keeps its buttons where they are, a button with nothing left is disabled only
-- by the repaint after its own last move, a group shown in this visit stays shown, the worth column
-- only widens, and an opened row keeps room for the most its lines can say. While a run goes, the
-- button pressed is its Stop where it stands (one button with two looks, never a second one laid
-- over it: docs/addon/AGENTS.md "Buttons and hover"), and a second press of it is the press that
-- stops the run; the other move of its row gives way. How far the run is takes the row's worth
-- column (UI/HoardRow.lua); where it goes is said in its Stop's tooltip, and on Store all's line
-- and the selection bar beside it (UI/HoardList.lua), in room those lines keep from their first
-- paint. The search row over many groups stands fixed above the list, and the selection bar's room
-- at the window's foot from the first paint with checkboxes, so neither a search nor a check
-- moves the list.
--
-- Later parts of the window paint into it through AddSection and move through Press, so the window
-- keeps one run: the tiles pinned under the switch (UI/HoardTiles.lua), the carry cards below the
-- groups (UI/HoardCarry.lua), and the footer pinned at the window's foot under the selection bar
-- (UI/HoardFooter.lua).
--
-- Wired through the bank route's own handlers, which Core/Init.lua's event frame calls: the window
-- hooks them as it loads (after UI/BankRoute.lua in GoldCap.toc), and Blizzard's bank panel's
-- Reset. Retail only: GoldCap_Camelot.toc loads none of the bank files.
GC.HoardFrame = {}
local HF = GC.HoardFrame
local K = GC.Kit.Tokens.color

-- In UI units; the approved boards are drawn at twice that. WIDTH: the board's 360 and GUTTER, the
-- room the scroll's bar takes right of the list (it hangs 6px right of the scroll frame and is 16px
-- wide, Blizzard_SharedXML/SecureScrollTemplates.xml), so the rows keep the board's 336 and the
-- header, the switch and the bar all end PAD from the window's right edge, as everything starts
-- PAD from its left. SCREEN_GAP: what the window leaves free under it, above the action bars.
-- INDENT: a folder's groups, in from its own row. NAME_MIN: the least room a row's name gets beside
-- its play's chip; MIN_ICONS: the fewest icons a row gives up for that before its chip goes under
-- the name. CHECK: a row's checkbox, the badge art's least size (UI/Kit/Textures.lua). The search
-- row (WELL_H: the BUY tab's search well), the selection bar (SEL_*) and the cast bar (CAST_GAP
-- between its words and its count, FILL_H its gold fill's height) are UI/HoardList.lua's. ROWS_MIN:
-- the fewest rows' room the scroll keeps between the window's fixed parts, however low the room
-- beside the bank window is.
local L = {
  WIDTH = 382, PAD = 12, GUTTER = 22, X = 4, SCREEN_GAP = 80, MIN_H = 160,
  HEAD_H = 28, LOGO = 22, CLOSE = 22, CLOSE_ICON = 10, SWITCH_GAP = 8, SEG_H = 20, SEG_PAD = 2, SEG_MIN = 50,
  FREE_GAP = 10, FREE_ICON = 10, FREE_PART = 4, SECTION_GAP = 11, HEADING_GAP = 5, ROW_GAP = 3,
  ROW_H = 26, FOLDER_H = 30, ROW_PAD = 6, TEXT_PAD = 5, INDENT = 15, ICON = 15, ICON_GAP = 2, MOVE = 18,
  MOVE_ICON = 9, MOVE_GAP = 4, WORTH_W = 46, COL_GAP = 6, CHIP_H = 13, CHIP_GAP = 4, NAME_MIN = 60,
  MIN_ICONS = 3, CHEVRON = 8, BAR_H = 2, BAR_IN = 7, ALL_H = 18, LEGEND_W = 7, LEGEND_H = 3, FOLD_H = 22,
  ITEM_ICON = 16, ITEM_GAP = 4, KEEP_H = 16, KEEP_PAD = 5, PENCIL = 8, HANDLE_H = 28, HANDLE_LOGO = 18,
  CHECK = 13, CHECK_GAP = 5, CHECK_GLYPH = 9, MARK = 9, CAST_GAP = 6, FILL_H = 3, TOOL_GAP = 6, WELL_H = 22,
  WELL_ICON = 10, WELL_PAD = 8, SORT_H = 20, SEL_PAD = 8, SEL_GAP = 4, SEL_BTN = 21, SEL_BTN_PAD = 8, SEL_ICON = 9,
  SEL_TEXT_MIN = 110, ROWS_MIN = 3,
}
-- The backpack, the four bag slots and the reagent bag: herbs, ore and cloth go to the reagent bag.
local BAGS = { 0, 1, 2, 3, 4, 5 }
local IS_BAG = {}
for _, bag in ipairs(BAGS) do IS_BAG[bag] = true end

-- The bank's share in the legend of the bar under each row (the bar's own is a step darker,
-- UI/HoardRow.lua): the kit's "yours" blue dimmed to the boards' slate, the kit having no slate of
-- its own. The bags' share is the kit's gold.
local SLATE = { K.yours[1], K.yours[2], K.yours[3], 0.6 }
-- The sunken track of a two-way switch, the bank switch's and the search row's filter
-- (UI/HoardList.lua): black at 0.35 under the glass, as the boards draw it; the kit has no token for
-- it.
local SWITCH_TRACK = { 0, 0, 0, 0.35 }

-- The stacks a press has sent, "bag:slot" -> { itemID, count } as the slot held them, until the
-- slot shows the move or the settle timer gives up on it.
HF._moving = {}
-- The press machine (Core/VendorPress.lua), made at the first press; the run id of the press now
-- running (Press), the bank its stacks go to or come from, and the bank the switch named when it
-- started. Every button a press came from, to find the one that carries the running id now.
HF.machine = nil
HF._runId, HF._runBank, HF._runSwitch = nil, nil, nil
HF._movers = setmetatable({}, { __mode = "k" })
-- The run that goes, as its cast bars show it: whether it moves into the bank, the list it was
-- pressed with (Press's rows), and the slots of its stacks that have shown the move, with how many
-- left each ("bag:slot" -> count; pruneMoving fills it, never the settle timer). What its button
-- asked to hear at its end (`onRunEnd`, Press).
HF._runInto, HF._runRows, HF._moved = nil, nil, {}
HF._runEnd = nil
-- The runs over whose button has not heard yet (Press's onRunEnd): each waits until every stack it
-- sent before it ended has landed or been given up, a bank visit or not, { done, bank, result, rows,
-- landed = { ["bag:slot"] = how many left it }, flying = { ["bag:slot"] = { itemID, count } as sent } }
-- (report, settleEndings).
HF._endings = {}
-- How many bank visits the window has seen: a section keeps what only grows (a tile's room) for
-- one visit.
HF._visit = 0
-- While the bank is open: the bank the window works with (Enum.BankType), as of its last paint, and
-- the bank the bank window showed then (the switch goes along only when that changes), and the bank
-- its last paint worked with (a keep count asked there goes when that changes); the window's width
-- and its worth column's, which only grow, and its height, which holds while things move (paint);
-- the groups Core/Hoard.lua's Rows has listed in this visit, which stay listed; whether the fold
-- line is open; and the group row open, by key.
HF._bankType, HF._seenType, HF._paintedType = nil, nil, nil
HF._width, HF._worthW, HF._height = nil, nil, nil
HF._shown = {}
HF._unfolded = false
HF._open = nil
-- From SEARCH_MIN_GROUPS groups, for the bank visit (UI/HoardList.lua): whether the search row has
-- shown, what is typed in it, the filter ("move" or "all") and the sort ("value" or "name"). The
-- groups checked, by key, and the bank they were checked at: a switch to the other bank drops them.
-- The room the selection bar keeps at the window's foot for the visit, once checkboxes have shown;
-- it only grows.
HF._searchUp, HF._query, HF._filter, HF._sort = nil, "", "move", "value"
HF._selected, HF._selBank, HF._selH = {}, nil, nil
-- What later parts of the window paint (AddSection), by place.
HF._sections = {}
HF._rows = {}
-- What the last paint read of the bags and the banks (newReading), for a paint that reads nothing.
-- A paint asked for on the next frame (OnBagsChanged), and whether one still needs to read: a paint
-- that read since makes it needless.
HF._reading = nil
HF._repaintQueued, HF._dirty = nil, nil
-- GC.db.hoard saved by a newer GoldCap cannot be written (Core/Hoard.lua): the X then closes the
-- window for this session, and a folder opens for this session.
HF._closedHere = nil
HF._foldersHere = {}

local frame, handle
local settleSeq = 0

local function heightOf(fs, fallback)
  local h = fs.GetStringHeight and fs:GetStringHeight()
  return type(h) == "number" and h or fallback
end

local function colour(fs, c)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- SetText with the text a FontString already holds does not redraw it (docs/addon/AGENTS.md
-- "Text"): clear first.
local function setText(fs, text)
  fs:SetText("")
  fs:SetText(text or "")
end

-- How tall `fs` is for the tallest of `texts`, at `width` when one is given, else at the width it
-- has: the room a line keeps for the most it can say, so a count or a word that changes moves
-- nothing. It is left holding the last of them.
local function tallest(fs, texts, width)
  if width then fs:SetWidth(math.max(1, width)) end
  local most = 0
  for _, text in ipairs(texts) do
    setText(fs, text)
    most = math.max(most, heightOf(fs, 12))
  end
  return math.ceil(most)
end

-- A line that wraps, at word breaks and, for a name with none (a Chinese one, or one long German
-- word), anywhere.
local function wrapping(fs)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  fs:SetNonSpaceWrap(true)
  return fs
end

-- Every FontString a frame of the window draws in (`owner`: the window, a row, the handle), so a
-- re-show can redraw them all (restamp).
local function track(owner, fs)
  owner.texts = owner.texts or {}
  owner.texts[#owner.texts + 1] = fs
  return fs
end

-- docs/addon/AGENTS.md "Text", measured in game: a one-line FontString whose frame or a parent was
-- hidden and shown again can come back with its text not drawn, and SetText with the text it holds
-- does not redraw it. The cure is clear, set, hide, show, on every re-show: here for each of
-- `owner`'s lines that shows.
local function restamp(owner)
  for _, fs in ipairs(owner.texts or {}) do
    if fs:IsShown() then
      local text = fs:GetText()
      fs:SetText("")
      fs:SetText(text or "")
      fs:Hide()
      fs:Show()
    end
  end
end

-- `text` with the figure `n` in it in `c`, brighter than the words around it, as the boards draw a
-- count.
local function lit(text, n, c)
  local digits = tostring(n)
  local s, e = text:find(digits, 1, true)
  if not s then return text end
  return text:sub(1, s - 1) .. GC.Util.Colored(c, digits) .. text:sub(e + 1)
end

-- The two banks, the character's own first, as the bank window's tabs come.
local function banks()
  local types = Enum and Enum.BankType
  return types and types.Character, types and types.Account
end

-- The bank window's own name for a bank, in the player's language: Blizzard's BANK and
-- ACCOUNT_BANK_PANEL_TITLE, which its tabs and its title read (Blizzard_UIPanels_Game's
-- Mainline/BankFrame.lua, GenerateBankTypeTabs and RequestTitleRefresh).
local function bankName(bankType)
  local _, account = banks()
  local name = bankType == account and _G.ACCOUNT_BANK_PANEL_TITLE or _G.BANK
  return type(name) == "string" and name or ""
end

-- An item's name with its quality's mark, as a tooltip and a line that stays name it.
local function itemName(item)
  return (item.name or ("#" .. tostring(item.itemID))) .. GC.Theme.QualityMarkup(item.itemID, 12)
end

-- What an item is worth to GoldCap now: its market value, in copper, or nil without one.
local function valueOf(itemID)
  local get = GC.Data and GC.Data.GetItemValue
  local value = get and get(itemID)
  return type(value) == "table" and value.mv or nil
end

-- valueOf for one paint: each item's market value asked once, however many parts of the window ask
-- for it (the rows, the selection bar, the tiles).
local function valuesOnce()
  local seen = {}
  return function(itemID)
    local value = seen[itemID]
    if value == nil then
      value = valueOf(itemID) or false
      seen[itemID] = value
    end
    return value or nil
  end
end

-- How many stacks a press moves, and where: into the bank named `bank` (its name), or into the bags
-- without one. A tooltip's line under its title (the selection bar's, a tile's).
local function stacksInto(n, bank)
  if bank then
    return n == 1 and GC.L["1 stack into %s"]:format(bank) or GC.L["%d stacks into %s"]:format(n, bank)
  end
  return n == 1 and GC.L["1 stack into your bags"] or GC.L["%d stacks into your bags"]:format(n)
end

-- The play of an item's group (Core/GroupRules.lua's rule): flip, gather, craft or stock.
local function playOf(itemID)
  local rule = GC.GroupRules.RuleFor(itemID)
  return rule and rule.play or nil
end

-- A group's worth as a row shows it: whole gold from a gold up, the silver being noise there;
-- nothing for a group none of whose items has a price yet.
local function worthText(copper)
  if type(copper) ~= "number" or copper <= 0 then return "" end
  if copper >= 10000 then return GC.Util.Money(math.floor(copper / 10000) * 10000) end
  return GC.Util.Money(copper)
end

-- ---------------------------------------------------------------------------------------------
-- Where the window stands
-- ---------------------------------------------------------------------------------------------

-- Blizzard's bank window is what the player sees: shown under shown parents, at a real size and not
-- see-through. A bag addon that takes the bank over shows it under a hidden or tiny parent (Bagnon:
-- BagBrother's core/features/uiOverrides.lua parks it under a 0.001-scale frame, then under a
-- hidden one in a deferred step); both are no window, whichever step ran.
local function bankShows(bank)
  if not (type(bank) == "table" and bank.IsVisible and bank:IsVisible()) then return false end
  local scale = bank.GetEffectiveScale and bank:GetEffectiveScale()
  local ui = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
  if type(scale) == "number" and type(ui) == "number" and scale < ui / 2 then return false end
  local alpha = bank.GetEffectiveAlpha and bank:GetEffectiveAlpha()
  if type(alpha) == "number" and alpha < 0.1 then return false end
  return true
end

-- Beside the bank window, past the tab buttons down its right edge (GC.BankRoute.BesideBankX), its
-- top level with the window's; with no window to stand beside, at the screen's left. Answers the
-- frame whose top the widget's top is level with, or nil.
local function place(widget)
  local bank = _G.BankFrame
  widget:ClearAllPoints()
  if bankShows(bank) then
    widget:SetPoint("TOPLEFT", bank, "TOPRIGHT", GC.BankRoute.BesideBankX(bank, L.X), 0)
    return bank
  end
  widget:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
  return nil
end

-- The most the window may be tall: the room from its top (the bank window's) down to SCREEN_GAP
-- above the screen's bottom, or the screen less twice that when it stands at the screen's left.
-- Unbounded where the client gives no measure.
local function maxHeight(beside)
  local top = beside and beside.GetTop and beside:GetTop()
  if type(top) == "number" then return math.max(L.MIN_H, top - L.SCREEN_GAP) end
  local screen = UIParent and UIParent.GetHeight and UIParent:GetHeight()
  if type(screen) == "number" and screen > 0 then return math.max(L.MIN_H, screen - 2 * L.SCREEN_GAP) end
  return math.huge
end

-- ---------------------------------------------------------------------------------------------
-- The press
-- ---------------------------------------------------------------------------------------------

-- How many of what was sent from `slotKey` (`sent`, { itemID, count }) have left its slot: all of
-- them once the slot is empty or holds another item; what it holds fewer of, when the same item
-- stayed in part (the other side had room for only some: a withdraw into bags with one free slot);
-- none while it holds as many. The slot as `reading` (newReading) has it, when that paint's read
-- covered its bag or tab; else as the client answers now.
local function leftOf(slotKey, sent, reading)
  local bag, slot = slotKey:match("^(%-?%d+):(%d+)$")
  bag, slot = tonumber(bag), tonumber(slot)
  local itemID, count
  if reading and reading.covered[bag] then
    local now = reading.held[slotKey]
    if now then itemID, count = now.itemID, now.count end
  else
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then itemID, count = info.itemID, info.stackCount or 1 end
  end
  if itemID ~= sent.itemID then return sent.count end
  return math.max(0, sent.count - count)
end

-- Whether a slot can be told from a move now: a bag's always, a bank tab's only while the bank is
-- open (closed, its slots answer nothing that could be told from a move).
local function readable(slotKey)
  return IS_BAG[tonumber(slotKey:match("^(%-?%d+):"))] == true or GC.BankRoute._open == true
end

-- Forgets a sent stack once some of it has left its slot: moved, merged, or emptied, read from the
-- paint's `reading` where it covers the slot. That is the one place a stack counts as moved
-- (HF._moved, with how many left), for the run's cast bars and checks, and for what a run's end
-- hands its button (report).
local function pruneMoving(reading)
  for slotKey, sent in pairs(HF._moving) do
    local left = readable(slotKey) and leftOf(slotKey, sent, reading) or 0
    if left > 0 then
      HF._moving[slotKey] = nil
      HF._moved[slotKey] = left
    end
  end
end

-- Nothing moved in time (a full bank or bags, a slot the server refused): the stacks are offered
-- again, and none of them counts as moved.
function HF._Settle(token)
  if token ~= settleSeq then return end
  HF._moving = {}
  HF.OnBagsChanged()
end

-- `stack` as what left its slot: `count` of it, a copy when that is fewer than the stack held.
local function leftPart(stack, count)
  if stack.count == count then return stack end
  local part = {}
  for k, v in pairs(stack) do part[k] = v end
  part.count = count
  return part
end

-- Hands each run over whose stacks have all landed or been given up to its button: onRunEnd(the
-- stacks that left their slots, in the run's order, each as many of it as left, the run's bank,
-- the machine's report). A stack still on its way lands when its slot shows the move, read as
-- pruneMoving reads it; `gaveUp`, the run whose settle timer ran, drops what has not landed by then.
-- Answers whether a button heard.
local function settleEndings(gaveUp)
  local i, heard = 1, false
  while i <= #HF._endings do
    local ending = HF._endings[i]
    for slotKey, sent in pairs(ending.flying) do
      local left = readable(slotKey) and leftOf(slotKey, sent) or 0
      if left > 0 then
        ending.flying[slotKey], ending.landed[slotKey] = nil, left
      elseif ending == gaveUp then
        ending.flying[slotKey] = nil
      end
    end
    if next(ending.flying) == nil then
      table.remove(HF._endings, i)
      local moved = {}
      for _, row in ipairs(ending.rows) do
        local left = ending.landed[row.bag .. ":" .. row.slot]
        if left then moved[#moved + 1] = leftPart(row.stack, left) end
      end
      ending.done(moved, ending.bank, ending.result)
      heard = true
    else
      i = i + 1
    end
  end
  return heard
end

-- What the press machine (Core/VendorPress.lua) reads of a slot: the item it holds, and whether
-- it is locked.
local function slotNow(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if type(info) == "table" then return { link = info.hyperlink, isLocked = info.isLocked == true } end
  return nil
end

-- The machine's call: one stack, through the bank route's MoveStack, the way and the bank the
-- press named. A stack sent is on its way (HF._moving) until its slot shows the move or the settle
-- timer gives up on it. False when MoveStack made no call: the machine goes on with the next.
local function moveRow(_, _, row)
  local stack = row.stack
  if not GC.BankRoute.MoveStack(row.stack, row.into, row.bankType) then return false end
  HF._moving[stack.bag .. ":" .. stack.slot] = { itemID = stack.itemID, count = stack.count }
  settleSeq = settleSeq + 1
  local token = settleSeq
  if C_Timer and C_Timer.After then
    C_Timer.After(GC.BankRoute.SETTLE_SECONDS, function() HF._Settle(token) end)
  end
  return true
end

-- A run over: the button it was pressed with learns which of its stacks left their slots (its
-- `onRunEnd`, Press), then the window repaints on the next frame, unless the run stopped for a
-- repaint already on its way (the switch came to the other bank, HF.Refresh; another button's
-- press, Press; the window closed). A stack counts as moved as the cast bars count it, with as many
-- of it as left its slot (pruneMoving, HF._moved), never by a guess from the bags afterwards: the
-- footer's Make room remembers exactly those for Put back. A stack still on its way as the run ends
-- (a Stop, the bank closed, the switch) is waited for: the button hears once it has landed or the
-- route's SETTLE_SECONDS have given up on it (settleEndings), so what lands after the end is
-- remembered too.
local function report(result)
  local rows, bank, done = HF._runRows, HF._runBank, HF._runEnd
  HF._runId, HF._runBank, HF._runSwitch = nil, nil, nil
  HF._runInto, HF._runRows, HF._runEnd = nil, nil, nil
  if done then
    pruneMoving()
    local ending = { done = done, bank = bank, result = result, rows = rows or {}, landed = {}, flying = {} }
    for _, row in ipairs(ending.rows) do
      local slotKey = row.bag .. ":" .. row.slot
      if HF._moved[slotKey] then
        ending.landed[slotKey] = HF._moved[slotKey]
      elseif HF._moving[slotKey] then
        ending.flying[slotKey] = HF._moving[slotKey]
      end
    end
    HF._endings[#HF._endings + 1] = ending
    if next(ending.flying) ~= nil and C_Timer and C_Timer.After then
      C_Timer.After(GC.BankRoute.SETTLE_SECONDS, function()
        settleEndings(ending)
        HF.OnBagsChanged()
      end)
    end
    settleEndings()
  end
  local stopped = result.stopped
  if stopped ~= "bank" and stopped ~= "switched" and stopped ~= "hidden" then HF.OnBagsChanged() end
end

function HF._Machine()
  if not HF.machine then
    HF.machine = GC.VendorPress.New({
      open = function() return GC.BankRoute.CanMove(HF._runBank) end,
      slot = slotNow,
      cursorBusy = GC.Util.CursorBusy,
      use = moveRow,
      after = function(seconds, fn) C_Timer.After(seconds, fn) end,
      report = report,
    })
  end
  return HF.machine
end

--- The one way anything in the window starts a run: a press of `button` over `stacks` (a plan's
--- list, in its order), into the bank (`into` true) or out to the bags, to or from `bankType`, the
--- switch's bank unless the caller names its own (the carry cards' Warband Bank, UI/HoardCarry.lua).
--- The machine makes the first move inside this call, so it is called only from the player's own
--- click. The window is repainted only after, so the button's state changes after its call. A
--- button with `onRunEnd` hears once, when its run is over however it ended, which of the stacks
--- left their slots: onRunEnd(moved stacks, the run's bank, the machine's report).
---
--- A run is known by `button.runId`, what the button moves, not by the widget: a row's Store or
--- Take out is "<kind>:<key>:in" or ":out" (kind "group" or "folder", the row's key), Store all
--- and Take all out are "all:in" and "all:out", and a later part names its own buttons the same
--- way ("tile:<id>", "carry:<id>", "selection:in"). A button with no run id is its own. A press
--- of the id that runs stops it and moves nothing; a press of another id stops it and starts its
--- own. While its run goes the button is its Stop (UI/HoardList.lua's PaintPair), so that second
--- press is a press of the same button where it stands. A section's button presses here the same
--- way wherever the section stands, in the scroll or pinned outside it (AddSection: the tiles under
--- the switch, the footer at the window's foot).
function HF.Press(button, stacks, into, bankType)
  if bankType == nil then bankType = HF._bankType end
  local rows = {}
  for i, stack in ipairs(stacks or {}) do
    rows[i] = { bag = stack.bag, slot = stack.slot, link = stack.link, itemID = stack.itemID, stack = stack,
      into = into, bankType = bankType }
  end
  local id = button.runId or button
  HF._movers[button] = true
  local machine = HF._Machine()
  if machine:IsRunning() and HF._runId ~= id then machine:Stop("switched") end
  -- The machine asks this bank (its driver's open) before every move, the first one inside Press.
  if not machine:IsRunning() then HF._runBank, HF._moved = bankType, {} end
  machine:Press(rows)
  if machine:IsRunning() then
    HF._runId, HF._runBank, HF._runSwitch = id, bankType, HF._bankType
    HF._runInto, HF._runRows, HF._runEnd = into, rows, button.onRunEnd
  else
    HF._runBank = nil
  end
  HF.Refresh(true)
end

--- Whether no run goes and every run over has told its button (settleEndings): only then do the
--- bags and the banks hold still for a section to write down what it reads of them (the footer's
--- room, UI/HoardFooter.lua). While a run goes, a stack that has left its slot is not yet one its
--- button has heard of.
function HF.Settled()
  return HF._runId == nil and #HF._endings == 0
end

--- The run id of the press that runs now, or nil; and the button that carries that id where the
--- player sees it now (a row redrawn since may carry it on another widget), or nil. The specs read
--- it (spec/hoard_frame_spec.lua, spec/hoard_sections_spec.lua) to tell which run goes and on which
--- button; the window itself goes by HF._runId.
function HF.Running()
  local id = HF._runId
  if id == nil then return nil end
  for button in pairs(HF._movers) do
    if (button.runId or button) == id and button:IsVisible() then return id, button end
  end
  return id, nil
end

-- A move button's own click: its whole list, the way it moves, to or from its own bank when it
-- names one (a carry card's), through Press.
local function onMoveClick(button)
  HF.Press(button, button.stacks, button.into, button.bankType)
end

-- ---------------------------------------------------------------------------------------------
-- The clicks that move nothing
-- ---------------------------------------------------------------------------------------------

-- A keep count asked in the kit's popup goes with the row it was asked from: on the X, and on any
-- click that redraws the list (a row opened or closed, a folder, the fold line, a search, the
-- filter, the sort, a checkbox, the bank switch), which can put another group on that row.
local function closeKeep()
  if not GC.BuyCapEditor then return end
  for _, row in ipairs(HF._rows) do GC.BuyCapEditor.CloseFor(row.keep) end
end

-- A side of the bank switch: the window works with that bank until the bank window comes to show
-- the other one or the bank closes. It moves nothing; a disabled side gets no click.
local function onBankClick(button)
  HF._bankType = button.bankType
  HF.Refresh(true, true)
end

-- Whether a folder is open: as the player left it (GC.db.hoard), or for this session when a newer
-- GoldCap's memory cannot be written.
local function folderOpen(key)
  local here = HF._foldersHere[key]
  if here ~= nil then return here end
  return GC.Hoard.FolderOpen(GC.db, key)
end

-- The fold line's own click: opens or closes the groups with nothing to move.
local function onFoldClick()
  closeKeep()
  HF._unfolded = not HF._unfolded
  HF.Refresh(false, true)
end

local function closedNow()
  return HF._closedHere == true or GC.Hoard.Closed(GC.db)
end

-- The X: the window goes, remembered for the account (Core/Hoard.lua's SetClosed), and a run of it
-- stops; the handle beside the bank window brings it back.
local function onCloseClick()
  closeKeep()
  if not GC.Hoard.SetClosed(GC.db, true) then HF._closedHere = true end
  if HF.machine and HF.machine:IsRunning() then HF.machine:Stop("hidden") end
  HF.Refresh()
end

local function onHandleClick()
  GC.Hoard.SetClosed(GC.db, false)
  HF._closedHere = nil
  HF.Refresh(true)
end

-- ---------------------------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------------------------

-- What the next press of a move button moves, as the bank card's labels said it: the stack and how
-- many stacks are left, or that there is nothing to move, under the button's own note (`tipNote`,
-- the selection bar's count) when it has one. A button that lists what it moves its own way (a
-- tile's, the footer's, a carry card's) says it with `tipLines(tooltip, button)` instead. A Stop
-- (`stopping`, UI/HoardList.lua) says what it stops: its title and the run's words as its note.
-- Repainted while it shows (paintMove).
local function showMoveTip(button)
  local tooltip = _G.GameTooltip
  if not (tooltip and button.tipTitle) then return end
  tooltip:SetOwner(button, GC.Theme.TooltipAnchor(button))
  tooltip:AddLine(GC.Util.ClientText(button.tipTitle), K.goldText[1], K.goldText[2], K.goldText[3])
  if button.tipNote then
    tooltip:AddLine(GC.Util.ClientText(button.tipNote), K.text1[1], K.text1[2], K.text1[3], true)
  end
  if button.stopping then return tooltip:Show() end
  if button.tipLines then
    button.tipLines(tooltip, button)
    return tooltip:Show()
  end
  local stacks = button.stacks or {}
  local stack = stacks[1]
  if stack then
    tooltip:AddLine(GC.Util.ClientText(GC.L["%s ×%d (%d left)"]:format(itemName(stack), stack.count, #stacks)),
      K.text1[1], K.text1[2], K.text1[3], true)
  else
    tooltip:AddLine(GC.Util.ClientText(GC.L["Nothing to move"]), K.text3[1], K.text3[2], K.text3[3])
  end
  tooltip:Show()
end

local function hideTip()
  if _G.GameTooltip then _G.GameTooltip:Hide() end
end

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------

-- A move button: its click is the press, its tooltip what the press moves. `look` is how it is
-- drawn at rest, kept for when its run's Stop is over (UI/HoardList.lua's PaintPair): { variant,
-- ring, icon, iconColor, textColor, label }, all but the variant optional: the kit's glyph `icon`
-- in `iconColor` while enabled (the caller sizes and places it), the words in `textColor` over the
-- variant's, and `label` true for a button that carries words beside its icon.
local function moveButton(parent, into, look)
  local button = GC.Theme.Button(parent, look.variant, "badge")
  -- In the scroll, which clips at its edges: a halo would be cut flat along its side.
  button:SetGlow(false)
  if look.ring then button:SetRing(look.ring) end
  if look.icon then
    button.icon = button:CreateTexture(nil, "OVERLAY")
    GC.Theme.SetIcon(button.icon, look.icon, look.iconColor)
  end
  button.look, button.into, button.iconColor, button.textColor = look, into, look.iconColor, look.textColor
  button:SetScript("OnClick", onMoveClick)
  button:SetScript("OnEnter", showMoveTip)
  button:SetScript("OnLeave", hideTip)
  HF._movers[button] = true
  return button
end

-- The quiet look the boards give Store all, Take all out, Make room and Put back, and the search
-- row's sort (UI/HoardList.lua): no fill, a faint ring, the words in the second text colour.
local QUIET = { variant = "segment", ring = K.windowBorder, textColor = K.text2 }

-- A quiet move button on a line of buttons (Store all's, the footer's): ALL_H tall, its words
-- redrawn with the window's, moving what `runId` names.
local function quietMove(parent, into, runId)
  local button = moveButton(parent, into, QUIET)
  button:SetHeight(L.ALL_H)
  button.runId = runId
  track(frame, button.text)
  return button
end

-- A two-way switch, the bank switch's and the search row's filter (UI/HoardList.lua), as the
-- crafting panel's view switch is built (UI/CraftPanel.lua): a sunken track in the glass's border,
-- and a kit segment for each of `values`, carrying it as `side[field]`, its click `onClick`.
local function newSwitch(parent, field, values, onClick)
  local T = GC.Theme
  local switch = CreateFrame("Frame", nil, parent)
  switch.track = T.SlicedTexture(switch, "BACKGROUND", T.MEDIA .. "plaque.png", SWITCH_TRACK, T.SLICE.plaque)
  switch.track:SetAllPoints(switch)
  switch.edge = T.SlicedTexture(switch, "BORDER", T.MEDIA .. "plaque_ring.png", K.glassBorder, T.SLICE.plaque)
  switch.edge:SetAllPoints(switch)
  switch.sides = {}
  for i, value in ipairs(values) do
    local side = T.Button(switch, "segment", "plaque")
    side:SetGlow(false)
    side:SetHeight(L.SEG_H)
    side[field] = value
    side:SetScript("OnClick", onClick)
    track(frame, side.text)
    switch.sides[i] = side
  end
  return switch
end

-- The kit's rounded art a plate is cut from, by its size class: plaque for a widget taller than
-- twice its 12px slice, badge (6px) for one down to 13px (UI/Kit/Textures.lua's slice rule).
local PLATE_ART = {
  plaque = { fill = "plaque.png", ring = "plaque_ring.png" },
  badge = { fill = "badge.png", ring = "badge_ring.png" },
}

-- A quiet clickable plate: a ring when asked, and the engine's gold wash under the cursor.
local function plate(parent, ring, art)
  local T = GC.Theme
  local files, slice = PLATE_ART[art], T.SLICE[art]
  local b = CreateFrame("Button", nil, parent)
  b:RegisterForClicks("LeftButtonUp")
  -- Required for the HIGHLIGHT layer (docs/addon/AGENTS.md "Buttons and hover").
  b:EnableMouse(true)
  if ring then
    b.ring = T.SlicedTexture(b, "BORDER", T.MEDIA .. files.ring, ring, slice)
    b.ring:SetAllPoints()
  end
  b.wash = T.SlicedTexture(b, "HIGHLIGHT", T.MEDIA .. files.fill, K.hoverWash, slice)
  b.wash:SetAllPoints()
  b.wash:SetBlendMode("ADD")
  return b
end

-- The window's name, "Hoard" in the player's language, in Fira Sans SemiBold as the board draws it
-- where GoldCap's own face carries the language; in the label face the kit picks elsewhere (the
-- client's, for Korean and Chinese).
local function semibold(parent, size)
  local T = GC.Theme
  local fs = T.Label(parent, size)
  if T.FONT_LABEL == T.FONT_TEXT then
    fs:SetFont(T.FONT_TEXT_SEMI, size * T.Scale(), "")
    T.TrackFont(fs, { role = "label", path = T.FONT_TEXT_SEMI, size = size, flags = "" })
  end
  fs:SetWordWrap(false)
  return fs
end

-- A free-slot count beside the switch, as the board draws it: the kit's glyph (a bag, a bank), the
-- words before the number, the number in the mono face, the words after it fainter.
local function freeChip(glyph)
  local T = GC.Theme
  local chip = CreateFrame("Frame", nil, frame)
  chip:SetHeight(12)
  chip.icon = chip:CreateTexture(nil, "ARTWORK")
  chip.icon:SetSize(L.FREE_ICON, L.FREE_ICON)
  T.SetIcon(chip.icon, glyph, K.text3)
  chip.words = track(frame, T.Label(chip, 10))
  colour(chip.words, K.text2)
  chip.num = track(frame, T.Num(chip, 10))
  colour(chip.num, K.text1)
  chip.rest = track(frame, T.Label(chip, 10))
  colour(chip.rest, K.text3)
  for _, fs in ipairs({ chip.words, chip.num, chip.rest }) do fs:SetWordWrap(false) end
  return chip
end

-- The window: its glass, the header (the GoldCap mark, its name in the brand's face, "Hoard" and
-- the X), the bank switch with the free slots, then the kit's scroll (UIPanelScrollFrameTemplate
-- under Theme.QuietScrollBar, its bar hidden while everything fits), whose child holds the
-- sections, the groups' heading, the rows and the fold line.
local function build()
  local T = GC.Theme
  frame = CreateFrame("Frame", nil, UIParent)
  frame:SetSize(L.WIDTH, L.MIN_H)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame.glass = T.Window(frame)
  -- The GoldCap mark, full colour, as the rail and the welcome window draw it.
  frame.logo = frame:CreateTexture(nil, "ARTWORK")
  frame.logo:SetTexture(T.MEDIA .. "GoldCap")
  frame.logo:SetSize(L.LOGO, L.LOGO)
  frame.logo:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -(L.PAD + (L.HEAD_H - L.LOGO) / 2))
  -- The brand in the condensed heavy face whatever the language: it is the name, written in Latin.
  frame.brand = track(frame, frame:CreateFontString(nil, "OVERLAY"))
  frame.brand:SetFont(T.FONT_HEAD_HEAVY, 16 * T.Scale(), "")
  T.TrackFont(frame.brand, { role = "brand", path = T.FONT_HEAD_HEAVY, size = 16 })
  frame.brand:SetWordWrap(false)
  colour(frame.brand, K.goldText)
  frame.brand:SetPoint("LEFT", frame.logo, "RIGHT", 7, 0)
  frame.title = track(frame, semibold(frame, 12))
  colour(frame.title, K.text2)
  frame.title:SetPoint("BOTTOMLEFT", frame.brand, "BOTTOMRIGHT", 6, 1)
  frame.close = T.Button(frame, "ghost", "badge")
  frame.close:SetSize(L.CLOSE, L.CLOSE)
  frame.close:SetRing(K.glassBorder)
  frame.close.icon = frame.close:CreateTexture(nil, "OVERLAY")
  frame.close.icon:SetSize(L.CLOSE_ICON, L.CLOSE_ICON)
  frame.close.icon:SetPoint("CENTER", frame.close, "CENTER", 0, 0)
  T.SetIcon(frame.close.icon, "close", K.text2)
  frame.close:SetScript("OnClick", onCloseClick)

  -- The bank switch, the other bank bare text and the bank chosen in the gold fill the board gives
  -- it (no halo: it is a choice, not the window's main action). In the bank window's order.
  frame.choice = newSwitch(frame, "bankType", { banks() }, onBankClick)
  frame.freeBags, frame.freeBank = freeChip("bag"), freeChip("bank")

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  if T.QuietScrollBar then T.QuietScrollBar(scroll) end
  scroll.scrollBarHideable = true
  if scroll.ScrollBar then scroll.ScrollBar:Hide() end
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(L.WIDTH - 2 * L.PAD - L.GUTTER, 1)
  scroll:SetScrollChild(content)
  frame.scroll, frame.content = scroll, content

  -- "Your groups", the legend of the bar under each row, Store all and Take all out.
  frame.groupsTitle = track(frame, T.Heading(content, 9))
  frame.groupsTitle:SetWordWrap(false)
  colour(frame.groupsTitle, K.text3)
  frame.legend = {}
  for i, c in ipairs({ K.gold, SLATE }) do
    local swatch = T.Solid(content, "ARTWORK", c)
    swatch:SetSize(L.LEGEND_W, L.LEGEND_H)
    local fs = track(frame, T.Label(content, 9))
    fs:SetWordWrap(false)
    colour(fs, K.text3)
    frame.legend[i] = { swatch = swatch, text = fs }
  end
  -- Quiet, as the board draws them (paintMove keeps their words' colour over the kit's own on
  -- every enable).
  frame.storeAll, frame.takeAll = quietMove(content, true, "all:in"), quietMove(content, false, "all:out")
  frame.empty = track(frame, wrapping(T.Label(content, 10)))
  colour(frame.empty, K.text3)

  -- As tall as one line of its text: the badge art, whose corners a plaque's would notch at that
  -- height.
  local fold = plate(content, K.glassBorder, "badge")
  fold.caret = fold:CreateTexture(nil, "ARTWORK")
  fold.caret:SetSize(L.CHEVRON, L.CHEVRON)
  fold.text = track(frame, wrapping(T.Label(fold, 10)))
  colour(fold.text, K.text3)
  fold:SetScript("OnClick", onFoldClick)
  frame.fold = fold
  -- Measures what a worth column must hold; never shown.
  frame.measure = T.Num(content, 10)
  frame.measure:Hide()
  -- The search row, the selection bar and Store all's cast bar.
  HF.List.Build(frame)
  -- A frame made from Lua starts shown: hidden until refresh shows it, so its first show is a
  -- re-show like any other (restamp).
  frame:Hide()
  HF._frame = frame
end

-- The small handle that stays beside the bank window while the window is closed: the mark and its
-- name, on the window's own glass so it reads over the world.
local function buildHandle()
  local T = GC.Theme
  handle = plate(UIParent, K.windowBorder, "plaque")
  handle:SetHeight(L.HANDLE_H)
  handle:SetClampedToScreen(true)
  handle.bg = T.SlicedTexture(handle, "BACKGROUND", T.MEDIA .. "plaque.png", K.windowTop, T.SLICE.plaque)
  handle.bg:SetAllPoints()
  handle.logo = handle:CreateTexture(nil, "ARTWORK")
  handle.logo:SetTexture(T.MEDIA .. "GoldCap")
  handle.logo:SetSize(L.HANDLE_LOGO, L.HANDLE_LOGO)
  handle.logo:SetPoint("LEFT", handle, "LEFT", 6, 0)
  handle.text = track(handle, semibold(handle, 12))
  colour(handle.text, K.text2)
  handle.text:SetPoint("LEFT", handle.logo, "RIGHT", 5, 0)
  handle:SetScript("OnClick", onHandleClick)
  handle:Hide()
  HF._handle = handle
end

-- ---------------------------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------------------------

-- Every stack the bank route's reader reads, bound ones too (marked `bound`): each part of the
-- window takes from that what it wants.
local ALL = { soulbound = true }

-- What the window reads of the client for a paint, working with `bankType`'s bank (the one the
-- switch names): each part read at its first ask (bagsOf, bankOf, freeOf), once, however many parts
-- of the window ask, and kept for the paints after it until the next read (refresh), so a click
-- that only changes what the window shows reads nothing. `held` and `covered`: every stack read, by
-- "bag:slot", and the bags and tabs read, for pruneMoving to tell a move from the same read.
local function newReading(bankType)
  return { bankType = bankType, banks = {}, held = {}, covered = {} }
end

-- `stacks`, read from `bags` (bags, or a bank's tabs), noted in `reading`.
local function noted(reading, stacks, bags)
  for _, bag in ipairs(bags) do reading.covered[bag] = true end
  for _, stack in ipairs(stacks) do reading.held[stack.bag .. ":" .. stack.slot] = stack end
  return stacks
end

-- Every stack in the bags (the backpack, the four bags and the reagent bag), each in the bags marked
-- `stays` against the reading's bank, as the bank route's reader reads them.
local function bagsOf(reading)
  if not reading.bags then
    reading.bags = noted(reading, GC.BankRoute.ReadStacks(BAGS, false, nil, reading.bankType, ALL), BAGS)
  end
  return reading.bags
end

-- Every stack in `bankType`'s tabs: the reading's own bank, or the other one a part asks for (the
-- carry cards' Warband Bank, the bank Make room put things in).
local function bankOf(reading, bankType)
  local stacks = reading.banks[bankType]
  if not stacks then
    local tabs = GC.BankRoute.BankTabs(bankType)
    stacks = noted(reading, GC.BankRoute.ReadStacks(tabs, true, nil, bankType, ALL), tabs)
    reading.banks[bankType] = stacks
  end
  return stacks
end

-- How many slots of `bags` are free, and how many they have.
local function freeIn(bags)
  local free, all = 0, 0
  for _, bag in ipairs(bags) do
    local ok, n = pcall(C_Container.GetContainerNumFreeSlots, bag)
    if ok and type(n) == "number" then free = free + n end
    all = all + (C_Container.GetContainerNumSlots(bag) or 0)
  end
  return free, all
end

-- The free slots in the bags and in the reading's bank: { bags = { free, all }, bank = { free, all } }.
local function freeOf(reading)
  if not reading.free then
    reading.free = { bags = { freeIn(BAGS) }, bank = { freeIn(GC.BankRoute.BankTabs(reading.bankType)) } }
  end
  return reading.free
end

-- What the window paints from `reading`: the followed groups' stacks in the bags and the bank (not a
-- bound one), the plan over them (Core/BankGroups.lua's Plan, with the stacks a press has sent by
-- now), each item's count in the bags and in that bank, and an icon for each item, from the first
-- of its stacks read. Without a followed group nothing is read for it.
local function stateOf(reading, usable, hasGroups)
  local state = { reading = reading, bankType = reading.bankType, usable = usable, hasGroups = hasGroups, groups = {},
    perItem = {}, icons = {}, bagStacks = {}, bankStacks = {} }
  if not hasGroups then return state end
  local groupOf = GC.GroupRules.GroupOf
  local sides = { { bagsOf(reading), state.bagStacks, "bags" }, { bankOf(reading, reading.bankType), state.bankStacks, "bank" } }
  for _, side in ipairs(sides) do
    for _, stack in ipairs(side[1]) do
      if not stack.bound and groupOf(stack.itemID) then side[2][#side[2] + 1] = stack end
    end
  end
  state.groups = GC.BankGroups.Plan(state.bagStacks, state.bankStacks, {
    groupOf = groupOf,
    keepFor = function(key) return GC.BankGroups.KeepFor(GC.db, key) end,
    moving = HF._moving,
  })
  for _, side in ipairs(sides) do
    for _, stack in ipairs(side[2]) do
      local here = state.perItem[stack.itemID] or { bags = 0, bank = 0 }
      here[side[3]] = here[side[3]] + stack.count
      state.perItem[stack.itemID] = here
      if state.icons[stack.itemID] == nil then state.icons[stack.itemID] = stack.icon end
    end
  end
  return state
end

-- ---------------------------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------------------------

-- The bank switch: each side named and as wide as its name, the bank chosen lit, the other in the
-- second text colour the board gives it, a bank that cannot be used (`usable[bankType]` false)
-- disabled; side by side, or one under the other when the two do not fit, so a name is never cut.
-- Answers its height and width.
local function paintChoice(usable, inner)
  local choice, pad = frame.choice, L.SEG_PAD
  for _, side in ipairs(choice.sides) do
    side:SetLabel(bankName(side.bankType))
    side:FitLabels({ side.label }, L.SEG_MIN)
    local chosen = side.bankType == HF._bankType
    side:SetVariant(chosen and "primary" or "segment")
    -- Enabled first, so a side disabled again repaints as disabled over its new variant.
    side:Enable()
    if not usable[side.bankType] then side:Disable() end
    if not chosen and side:IsEnabled() then colour(side.text, K.text2) end
  end
  local first, second = choice.sides[1], choice.sides[2]
  local a, b = first:GetWidth(), second:GetWidth()
  first:ClearAllPoints()
  first:SetPoint("TOPLEFT", choice, "TOPLEFT", pad, -pad)
  second:ClearAllPoints()
  if a + b + 3 * pad <= inner then
    second:SetPoint("LEFT", first, "RIGHT", pad, 0)
    choice:SetSize(a + b + 3 * pad, L.SEG_H + 2 * pad)
  else
    second:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 0, -pad)
    choice:SetSize(math.max(a, b) + 2 * pad, 2 * L.SEG_H + 3 * pad)
  end
  return choice:GetHeight(), choice:GetWidth()
end

-- A free-slot chip from `words` ("Bags %d free" in the player's language): the words either side
-- of the number, and the number in a box as wide as the most it can say (every slot free), so a
-- move never moves anything on the line. Answers the chip's width.
local function paintFree(chip, words, free, all)
  local at = words:find("%d", 1, true)
  local before = at and (words:sub(1, at - 1):gsub("%s+$", "")) or words
  local after = at and (words:sub(at + 2):gsub("^%s+", "")) or ""
  setText(chip.words, before)
  setText(chip.num, tostring(all))
  local numW = math.ceil(chip.num:GetStringWidth() or 0)
  setText(chip.num, tostring(free))
  setText(chip.rest, after)
  chip.rest:SetShown(after ~= "")
  local x = 0
  chip.icon:ClearAllPoints()
  chip.icon:SetPoint("LEFT", chip, "LEFT", x, 0)
  x = x + L.FREE_ICON + L.FREE_PART
  chip.words:ClearAllPoints()
  chip.words:SetPoint("LEFT", chip, "LEFT", x, 0)
  x = x + math.ceil(chip.words:GetStringWidth() or 0) + L.FREE_PART
  chip.num:SetWidth(numW)
  chip.num:ClearAllPoints()
  chip.num:SetPoint("LEFT", chip, "LEFT", x, 0)
  x = x + numW
  if after ~= "" then
    x = x + L.FREE_PART
    chip.rest:ClearAllPoints()
    chip.rest:SetPoint("LEFT", chip, "LEFT", x, 0)
    x = x + math.ceil(chip.rest:GetStringWidth() or 0)
  end
  chip:SetWidth(x)
  return x
end

-- The bank switch at `y`, with the free slots in the bags and the bank chosen at the header's
-- right, or under it when there is no room. Answers the height they take.
local function paintSwitch(state, y, inner)
  local h, w = paintChoice(state.usable, inner)
  frame.choice:ClearAllPoints()
  frame.choice:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -y)
  local bags, bank, free = frame.freeBags, frame.freeBank, freeOf(state.reading)
  local bagsW = paintFree(bags, GC.L["Bags %d free"], free.bags[1], free.bags[2])
  local bankW = paintFree(bank, GC.L["Bank %d free"], free.bank[1], free.bank[2])
  bags:ClearAllPoints()
  bank:ClearAllPoints()
  if w + L.FREE_GAP + bagsW + L.FREE_GAP + bankW <= inner then
    local right, mid = L.PAD + inner, -(y + h / 2)
    bank:SetPoint("RIGHT", frame, "TOPLEFT", right, mid)
    bags:SetPoint("RIGHT", frame, "TOPLEFT", right - bankW - L.FREE_GAP, mid)
    return h
  end
  local below = y + h + L.HEADING_GAP
  bags:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -below)
  bank:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD + bagsW + L.FREE_GAP, -below)
  return h + L.HEADING_GAP + 12
end

-- A move button for `stacks`: enabled while it has something to move; disabled with nothing, from
-- the start or by the repaint after its own last move, never by its click. Its icon and, for a
-- quiet one, its words keep their colour over the kit's own enable. Its tooltip follows.
local function paintMove(button, stacks, title)
  button.stacks, button.tipTitle = stacks, title
  if #stacks > 0 then button:Enable() else button:Disable() end
  local live = button:IsEnabled()
  if button.icon then
    local c = live and button.iconColor or K.text3
    button.icon:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  end
  if button.textColor and live then colour(button.text, button.textColor) end
  local tooltip = _G.GameTooltip
  if tooltip and tooltip.IsOwned and tooltip:IsOwned(button) then showMoveTip(button) end
end

-- Store all and Take all out: every group's list, group by group in the plan's order. Each is as
-- wide as the wider of its words and Stop, which it says while its run goes, so a press never
-- resizes it. Without the keep counts (a newer GoldCap's), Store all is not offered; Take all out
-- keeps its place.
--
-- A group's or a folder's run whose row the list does not show (`stray`, its run id: the search
-- hides the group, its folder is closed) is watched and stopped here instead: the button of its way
-- (Store all for a run into the bank, Take all out for one out of it) carries its run id while it
-- shows nowhere else, so it is that run's Stop, and a press of it is the press that stops it
-- (HF.Press). Answers the one whose run goes, or nil.
local function paintAll(groups, writable, ctx, stray)
  local lists = { toBank = {}, toBags = {} }
  for _, group in ipairs(groups) do
    for _, key in ipairs({ "toBank", "toBags" }) do
      for _, stack in ipairs(group[key]) do lists[key][#lists[key] + 1] = stack end
    end
  end
  local labels = { GC.L["Store all"], GC.L["Take all out"] }
  frame.storeAll.runId, frame.takeAll.runId = "all:in", "all:out"
  if stray then
    local button = HF._runInto and frame.storeAll or frame.takeAll
    button.runId = stray
  end
  local running = HF.List.PaintPair({ { frame.storeAll, lists.toBank, labels[1] },
    { frame.takeAll, lists.toBags, labels[2] } }, ctx.runId, writable, ctx.run)
  for i, button in ipairs({ frame.storeAll, frame.takeAll }) do
    button:SetLabel(button == running and GC.L["Stop"] or labels[i])
    button:FitLabels({ labels[i], GC.L["Stop"] }, 0)
  end
  return running
end

-- "Your groups" with the legend at `y` in the scroll, Store all and Take all out at its right, or
-- on a line under it when there is no room. While the run of one of them goes (`running`), its
-- cast bar stands left of them, over the heading and the legend on their line; the line keeps the
-- cast bar's room from its first paint (UI/HoardList.lua's LineCastHeight), so a press moves
-- nothing. Answers the y under it.
local function paintHeading(y, inner, ctx, running)
  local title = frame.groupsTitle
  setText(title, GC.Util.Upper(GC.L["Your groups"]))
  local x = math.ceil(title:GetStringWidth() or 0) + 10
  local parts = {}
  for i, word in ipairs({ GC.L["bags"], GC.L["bank"] }) do
    local entry = frame.legend[i]
    setText(entry.text, word)
    parts[i] = { entry = entry, x = x }
    x = x + L.LEGEND_W + 4 + math.ceil(entry.text:GetStringWidth() or 0) + 10
  end
  local storeW, takeW = frame.storeAll:GetWidth(), frame.takeAll:GetWidth()
  local buttonsW = storeW + 4 + takeW
  local oneLine = x + buttonsW <= inner
  local castW = inner - buttonsW - L.CAST_GAP
  local castH = HF.List.LineCastHeight(frame.cast, ctx.castLabels, castW)
  local buttonsH = math.max(L.ALL_H, castH)
  local lineH = oneLine and buttonsH or 12
  local mid = y + lineH / 2
  local headingUp = not (oneLine and running)
  title:ClearAllPoints()
  title:SetPoint("LEFT", frame.content, "TOPLEFT", 0, -mid)
  title:SetShown(headingUp)
  for _, part in ipairs(parts) do
    part.entry.swatch:ClearAllPoints()
    part.entry.swatch:SetPoint("LEFT", frame.content, "TOPLEFT", part.x, -mid)
    part.entry.text:ClearAllPoints()
    part.entry.text:SetPoint("LEFT", part.entry.swatch, "RIGHT", 4, 0)
    part.entry.swatch:SetShown(headingUp)
    part.entry.text:SetShown(headingUp)
  end
  local buttonsY = oneLine and y or (y + lineH + L.HEADING_GAP)
  local top = buttonsY + math.floor((buttonsH - L.ALL_H) / 2)
  frame.takeAll:ClearAllPoints()
  frame.takeAll:SetPoint("TOPRIGHT", frame.content, "TOPLEFT", inner, -top)
  frame.storeAll:ClearAllPoints()
  frame.storeAll:SetPoint("TOPRIGHT", frame.content, "TOPLEFT", inner - takeW - 4, -top)
  if running then
    HF.List.PaintLineCast(frame.cast, ctx.run, frame.content, 0, buttonsY + math.floor((buttonsH - castH) / 2), castW)
  else
    HF.List.HideCast(frame.cast)
  end
  -- What was hidden for the run, or the run's words, shown again: redrawn whole.
  if (running ~= nil) ~= (frame.headRan == true) then restamp(frame) end
  frame.headRan = running ~= nil
  return buttonsY + buttonsH
end

-- What a row of the list (UI/HoardRow.lua, loaded after this file) is built and painted with: the
-- window's measures and slate, and the helpers both files draw with.
HF.ui = {
  L = L, SLATE = SLATE, QUIET = QUIET, setText = setText, colour = colour, wrapping = wrapping, heightOf = heightOf,
  tallest = tallest, itemName = itemName, worthText = worthText, stacksInto = stacksInto, plate = plate,
  moveButton = moveButton, quietMove = quietMove, newSwitch = newSwitch, paintMove = paintMove,
  showMoveTip = showMoveTip, hideTip = hideTip, track = track, restamp = restamp, closeKeep = closeKeep,
  bankName = bankName,
}

-- The rows of `list` from `y` in the scroll, from the pool's `first`; answers the y under them and
-- the next free place in the pool. A pooled row shown again in a window that shows is redrawn
-- whole (restamp).
local function paintRows(list, ctx, y, first, inner)
  local index = first
  for _, data in ipairs(list) do
    local row = HF._rows[index] or HF.Row.New(frame.content)
    HF._rows[index] = row
    local indent = (data.depth or 0) * L.INDENT
    local wasUp = row:IsShown()
    row:SetWidth(inner - indent)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", indent, -y)
    row:Show()
    y = y + HF.Row.Paint(row, data, ctx) + L.ROW_GAP
    if not wasUp and frame:IsShown() then restamp(row) end
    index = index + 1
  end
  return y, index
end

-- The fold line at `y`: how many groups have nothing to move at this bank, wrapping, and the kit's
-- caret (right closed, down open). Answers its height.
local function paintFold(count, y, inner)
  local fold = frame.fold
  local text = count == 1 and GC.L["1 more group has nothing to move at this bank"]
    or GC.L["%d more groups have nothing to move at this bank"]:format(count)
  local textX = L.ROW_PAD + L.CHEVRON + L.TEXT_PAD
  fold.text:SetWidth(inner - textX - L.ROW_PAD)
  setText(fold.text, lit(text, count, K.text2))
  local h = math.max(L.FOLD_H, math.ceil(heightOf(fold.text, 12)) + 2 * L.TEXT_PAD)
  fold.text:ClearAllPoints()
  fold.text:SetPoint("LEFT", fold, "LEFT", textX, 0)
  GC.Theme.SetIcon(fold.caret, HF._unfolded and "caretDown" or "caretRight", K.text3)
  fold.caret:ClearAllPoints()
  fold.caret:SetPoint("LEFT", fold, "LEFT", L.ROW_PAD, 0)
  fold:ClearAllPoints()
  fold:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
  fold:SetSize(inner, h)
  fold:Show()
  return h
end

-- Where each part stands (AddSection): the tiles pinned under the switch and the footer pinned at
-- the window's foot, outside the scroll, so they stay in reach however far the list scrolls; the
-- carry cards in the scroll under the groups.
local PINNED = { tiles = true, footer = true }

-- A section (AddSection): built once in a frame of its own, in the window when it is pinned, else in
-- the scroll; painted with `ctx`, at `y` in the scroll unless pinned (the window's top or foot
-- places those); shown with a height above 0. Answers its height.
local function paintSection(name, ctx, y)
  local entry = HF._sections[name]
  if not entry then return 0 end
  local pinned = PINNED[name] == true
  if not entry.frame then
    entry.frame = CreateFrame("Frame", nil, pinned and frame or frame.content)
    entry.spec.build(entry.frame)
  end
  local f = entry.frame
  f:SetWidth(ctx.width)
  local h = math.ceil(entry.spec.paint(f, ctx) or 0)
  if not pinned then
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
  end
  f:SetHeight(math.max(h, 1))
  f:SetShown(h > 0)
  return h
end

-- `ctx` for a pinned section: the same, at the window's width less its margins (`head`).
local function wideCtx(ctx, head)
  local wide = {}
  for k, v in pairs(ctx) do wide[k] = v end
  wide.width = head
  return wide
end

-- How wide the worth column must be for `lists`' rows, and never narrower than it has been in this
-- visit: what each row is worth, and how far a run of its longer list can say it has come, which
-- its cast bar writes there (UI/HoardRow.lua).
local function worthWidth(lists)
  local widest = math.max(L.WORTH_W, HF._worthW or 0)
  for _, list in ipairs(lists) do
    for _, data in ipairs(list) do
      local most = math.max(#data.toBank, #data.toBags)
      for _, text in ipairs({ worthText(data.worth), ("%d / %d"):format(most, most) }) do
        setText(frame.measure, text)
        widest = math.max(widest, math.ceil(frame.measure:GetStringWidth() or 0))
      end
    end
  end
  HF._worthW = widest
  return widest
end

-- The window's width: the board's with the scroll's gutter, or as wide as its widest label in the
-- player's language needs (a side of the switch in the header, Store all with Take all out in the
-- list, each as wide as Stop too), and only ever wider while the bank is open, so nothing reflows
-- under the cursor. Answers it, the header's room inside the window's margins, and the list's,
-- which the gutter takes from.
local function widthFor()
  local need = 0
  for _, side in ipairs(frame.choice.sides) do
    side:SetLabel(bankName(side.bankType))
    side:FitLabels({ side.label }, L.SEG_MIN)
    need = math.max(need, side:GetWidth() + 2 * L.SEG_PAD + 2 * L.PAD)
  end
  for _, entry in ipairs({ { frame.storeAll, GC.L["Store all"] }, { frame.takeAll, GC.L["Take all out"] } }) do
    entry[1]:SetLabel(entry[2])
    entry[1]:FitLabels({ entry[2], GC.L["Stop"] }, 0)
  end
  need = math.max(need, frame.storeAll:GetWidth() + 4 + frame.takeAll:GetWidth() + 2 * L.PAD + L.GUTTER)
  local width = math.max(L.WIDTH, need, HF._width or 0)
  HF._width = width
  return width, width - 2 * L.PAD, width - 2 * L.PAD - L.GUTTER
end

-- The window, top to bottom: the header and the switch, fixed; the tiles pinned under them; from
-- SEARCH_MIN_GROUPS groups the search row, fixed above the list; then in the scroll the groups'
-- heading, the rows the plan lists, the fold line with, opened, the folded rows under it, and the
-- carry cards; under the scroll, at the window's foot, the selection bar's room and under it the
-- pinned footer. Clamped to the screen and never taller than the room under its top, but never so
-- low that the scroll between the fixed parts shows fewer than ROWS_MIN rows' room (or all there
-- is, when that is less).
--
-- Its height is set only where nothing stands under the cursor: as it comes up (the first paint of
-- a bank visit, or back from its handle), and at the player's own click that changes what the list
-- holds (`layout`: a row, a folder or the fold line opened or closed, a search, the filter, the
-- sort, the bank switch), and when the other bank comes up by the bank window's own tab, never while
-- a run goes. Else it keeps the height it had and the scroll takes what the list gained or lost, so
-- the selection bar and the footer at its foot, and a Stop on them, stay where they are through a
-- run and the bag events of its moves (Make room bringing a folded group up, Put back bringing a
-- card to carry); outside a run it grows to the least height when it kept less. Laid out, not
-- shown: answers false when it has nothing at all to show (no followed group, and every section
-- empty).
local function paint(state, layout)
  local beside = place(frame)
  local width, head, inner = widthFor()
  frame:SetWidth(width)
  setText(frame.brand, "GoldCap")
  setText(frame.title, GC.L["Hoard"])
  frame.close:ClearAllPoints()
  frame.close:SetPoint("TOPRIGHT", frame, "TOPLEFT", L.PAD + head, -(L.PAD + (L.HEAD_H - L.CLOSE) / 2))
  local y = L.PAD + L.HEAD_H + L.SWITCH_GAP
  y = y + paintSwitch(state, y, head) + L.SECTION_GAP

  local writable = GC.BankGroups.Writable(GC.db)
  for _, group in ipairs(state.groups) do
    -- A newer GoldCap saved the keep counts, which this one cannot read: Store would ignore what
    -- the player keeps, so it moves nothing.
    if not writable then group.toBank = {} end
  end
  -- From SEARCH_MIN_GROUPS groups the search row, for the rest of the visit; with fewer, the list is
  -- what can move here, by value.
  if #state.groups >= GC.Hoard.SEARCH_MIN_GROUPS then HF._searchUp = true end
  local searching = HF._searchUp == true
  local values = valuesOnce()
  local result = GC.Hoard.Rows(state.groups, {
    valueOf = values, filter = searching and HF._filter or "move", sort = searching and HF._sort or "value",
    query = searching and HF._query or nil, folderOpen = folderOpen, shown = HF._shown, playOf = playOf,
    iconOf = function(itemID) return state.icons[itemID] end,
  })
  local folded = HF._unfolded and result.foldedRows or {}
  -- The run as its cast bars show it, and the marks on its items' icons (UI/HoardList.lua).
  local run, marks = HF.List.RunState()
  -- The checked groups that neither the rows nor the folded rows open under the fold line show; and
  -- a group's or a folder's run whose row none of them is (paintAll).
  local painted, rowRuns = {}, {}
  for _, list in ipairs({ result.rows, folded }) do
    for _, data in ipairs(list) do
      painted[#painted + 1] = data
      rowRuns[data.kind .. ":" .. data.key .. ":in"], rowRuns[data.kind .. ":" .. data.key .. ":out"] = true, true
    end
  end
  local id = HF._runId
  local stray = type(id) == "string" and (id:find("^group:") or id:find("^folder:")) and not rowRuns[id] and id or nil
  -- The folded rows' worth is measured too, closed, so opening the fold line moves no column.
  local reading = state.reading
  local ctx = { bankType = state.bankType, usable = state.usable, running = HF._runId ~= nil,
    runId = HF._runId, run = run, marks = marks, castLabels = HF.List.CastLabels(state.bankType),
    selected = HF._selected, notShown = GC.Hoard.NotShown(state.groups, painted, HF._selected),
    groups = state.groups, valueOf = values, width = inner, writable = writable, icons = state.icons,
    perItem = state.perItem, worthW = worthWidth({ result.rows, result.foldedRows }),
    hasGroups = state.hasGroups, bagStacks = state.bagStacks, bankStacks = state.bankStacks,
    inBags = function() return bagsOf(reading) end, inBank = function(bankType) return bankOf(reading, bankType) end,
    moving = HF._moving, many = searching, visit = HF._visit }
  local wide = wideCtx(ctx, head)

  local shownH = 0
  -- The tiles pinned under the switch, as wide as the header.
  local tilesH = paintSection("tiles", wide, 0)
  if tilesH > 0 then
    local tiles = HF._sections.tiles.frame
    tiles:ClearAllPoints()
    tiles:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -y)
    y, shownH = y + tilesH + L.SECTION_GAP, shownH + tilesH
  end

  -- The search row, fixed above the list so it never scrolls away.
  local groupsUp = state.hasGroups
  if groupsUp and searching then
    y = y + HF.List.PaintSearch(L.PAD, y, inner, result.total, result.toMove) + L.SECTION_GAP
  else
    HF.List.HideSearch()
  end
  local top = y

  local cy, index = 0, 1
  if groupsUp then
    cy = paintHeading(cy, inner, ctx, paintAll(state.groups, writable, ctx, stray)) + L.HEADING_GAP + 2
    -- No group here at all, or none the search finds.
    local nothing = #state.groups == 0 and GC.L["None of your groups' items are in your bags or this bank."]
      or (#result.rows == 0 and result.folded == 0 and GC.L["No group or item matches your search."])
    if nothing then
      frame.empty:SetWidth(inner)
      setText(frame.empty, nothing)
      frame.empty:ClearAllPoints()
      frame.empty:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -cy)
      frame.empty:Show()
      cy = cy + math.ceil(heightOf(frame.empty, 12)) + L.ROW_GAP
    else
      frame.empty:Hide()
    end
    cy, index = paintRows(result.rows, ctx, cy, 1, inner)
    if result.folded > 0 then
      cy = cy + paintFold(result.folded, cy, inner) + L.ROW_GAP
      cy, index = paintRows(folded, ctx, cy, index, inner)
    else
      frame.fold:Hide()
    end
    cy = cy - L.ROW_GAP
  else
    for _, key in ipairs({ "groupsTitle", "storeAll", "takeAll", "empty", "fold" }) do frame[key]:Hide() end
    for _, entry in ipairs(frame.legend) do entry.swatch:Hide(); entry.text:Hide() end
  end
  for i = index, #HF._rows do HF._rows[i]:Hide() end
  -- The carry cards in the scroll, under the groups.
  local carryH = paintSection("carry", ctx, cy + L.SECTION_GAP)
  if carryH > 0 then cy, shownH = cy + L.SECTION_GAP + carryH, shownH + carryH end
  -- The window's foot, bottom up: the footer, pinned, then the selection bar's room, once a group's
  -- checkbox has shown in this visit. The scroll ends a SECTION_GAP over them.
  local foot = L.PAD
  local footerH = paintSection("footer", wide, 0)
  if footerH > 0 then
    local footer = HF._sections.footer.frame
    footer:ClearAllPoints()
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", L.PAD, foot)
    foot, shownH = foot + footerH + L.SECTION_GAP, shownH + footerH
  end
  if not groupsUp and shownH == 0 then return false end

  cy = math.ceil(math.max(cy, 1))
  frame.content:SetSize(inner, cy)
  local roomH = HF.List.PaintSelection(groupsUp and state.groups or {}, ctx, head, foot)
  if roomH > 0 then foot = foot + roomH + L.SECTION_GAP end
  local least = top + math.min(cy, L.ROWS_MIN * (L.ROW_H + L.ROW_GAP)) + foot
  local height = math.min(top + cy + foot, math.max(least, maxHeight(beside)))
  -- Kept while things move, but outside a run never so short that a part which came since (the
  -- selection bar's room, the search row) leaves the list fewer than ROWS_MIN rows.
  if HF._height and not layout then height = HF._runId and HF._height or math.max(HF._height, least) end
  HF._height = height
  frame:SetHeight(height)
  frame.scroll:ClearAllPoints()
  frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -top)
  frame.scroll:SetSize(inner, math.max(1, height - top - foot))
  return true
end

-- Nothing of the window keeps the keyboard once it is gone (UI/HoardList.lua's search box). What it
-- last read is read again before it next paints.
local function hideAll()
  HF.List.Blur()
  HF._reading = nil
  if frame then frame:Hide() end
  if handle then handle:Hide() end
end

-- Closed: the handle beside the bank window instead, the mark and the window's name.
local function showHandle()
  HF.List.Blur()
  HF._reading = nil
  if frame then frame:Hide() end
  if not handle then buildHandle() end
  local wasUp = handle:IsShown()
  place(handle)
  setText(handle.text, GC.L["Hoard"])
  handle:SetWidth(6 + L.HANDLE_LOGO + 5 + math.ceil(handle.text:GetStringWidth() or 0) + 10)
  handle:Show()
  if not wasUp then restamp(handle) end
end

-- Paints the window, or hides it: with no followed group and no section (then nothing is built and
-- no slot is read), with the bank closed or not the window, with neither bank usable here with a
-- tab, and with nothing at all to show. While the player has closed it, the handle shows in its
-- place, when the window would have. With `read`, or at another bank than its last read's, it reads
-- the bags and the banks again (newReading) and tells the stacks sent from that read
-- (pruneMoving); else it paints from what it last read. `layout`: paint's.
local function refresh(read, layout)
  local route, character, account = GC.BankRoute, banks()
  if not (route._open and character and account) then return hideAll() end
  local hasGroups = GC.GroupRules ~= nil and GC.GroupRules.HasGroups()
  if not hasGroups and next(HF._sections) == nil then return hideAll() end
  -- The bank window shows another bank than at the last paint (it opened, or the player clicked its
  -- other tab): the switch goes along. Else the bank stays the one the player chose on the switch.
  local seen = route.ShownBankType()
  if seen ~= HF._seenType then HF._seenType, HF._bankType = seen, seen end
  local usable = { [character] = route.CanMove(character), [account] = route.CanMove(account) }
  if not usable[HF._bankType] then HF._bankType = HF._bankType == account and character or account end
  local bankType = HF._bankType
  -- The groups checked at the other bank are dropped: what the selection bar moves is planned
  -- against the bank the switch names.
  if HF._selBank ~= bankType then HF._selected, HF._selBank = {}, bankType end
  -- A run started under the other side of the switch stops: its stacks were planned against that
  -- bank.
  if HF._runSwitch ~= nil and HF._runSwitch ~= bankType and HF.machine then HF.machine:Stop("bank") end
  -- A keep count asked at the other bank goes with it: its row may show another group here. The
  -- other bank is a new list, so the window takes its height again, whichever switch or tab chose it.
  local bankChanged = HF._paintedType ~= nil and HF._paintedType ~= bankType
  if bankChanged then closeKeep() end
  HF._paintedType = bankType
  if not usable[bankType] then return hideAll() end
  local closed = closedNow()
  -- A followed group always makes a window, so its handle needs no reading.
  if closed and hasGroups then return showHandle() end
  local reading = HF._reading
  if read or not (reading and reading.bankType == bankType) then
    reading = newReading(bankType)
    HF._reading, HF._dirty = reading, nil
    -- The bags and the bank the switch names first, so a stack sent is told moved from this read.
    if hasGroups then
      bagsOf(reading)
      bankOf(reading, bankType)
    end
    pruneMoving(reading)
  end
  local state = stateOf(reading, usable, hasGroups)
  if not frame then build() end
  local wasUp = frame:IsShown()
  if not paint(state, (layout or not wasUp or bankChanged) and HF._runId == nil) then return hideAll() end
  if closed then return showHandle() end
  if handle then handle:Hide() end
  frame:Show()
  if wasUp then return end
  restamp(frame)
  for _, row in ipairs(HF._rows) do
    if row:IsShown() then restamp(row) end
  end
end

--- Paints the window again, or hides it (refresh above), at once: a click's paint. `read`: the bags
--- and the banks are read again first (a press, the bank switch, the handle); else it paints from
--- what its last paint read, for a click that only changes what the window shows (a search, the
--- filter, the sort, a checkbox, a row or a folder opened, a keep count). `layout`: the player's own
--- click that changes what the list holds (a row, a folder or the fold line opened or closed, a
--- search, the filter, the sort, the bank switch), after which the window may take a new height.
--- What the bags and the banks tell paints on the next frame instead (OnBagsChanged).
function HF.Refresh(read, layout)
  refresh(read, layout)
end

--- A later part of the window: `name` is its place, `spec` = { build = fn(parent), paint =
--- fn(section, ctx) -> height }. "tiles" stand pinned under the switch, over the search row;
--- "footer" pinned at the window's foot, under the selection bar's room: outside the scroll, so they
--- stay in reach however far the list scrolls, their frame the window's and their width the
--- window's less its margins. "carry" stands in the scroll under the groups, the list's width.
--- `build` runs once, with a frame of its own; `paint` at every paint of the window, with ctx = {
--- bankType, usable = { [bankType] = bool }, running, runId (the run id that runs, Press), run
--- (UI/HoardList.lua's RunState: { id, into, label, done, total }), groups (the plan's), valueOf
--- (each item's market value, asked once a paint), width (the room it paints in), hasGroups (a
--- followed group), bagStacks and bankStacks (the followed groups' stacks in the bags and in the
--- bank chosen, as the bank route's reader reads them, not a bound one), inBags() and
--- inBank(bankType) (every stack in the bags, bound ones too, marked `stays` against the bank
--- chosen, and every stack in that bank's tabs: what the paint read, each read at its first ask and
--- once; a part takes what it wants from them and reads no slot itself), moving (the stacks a press
--- has sent), many (the search row shows: SEARCH_MIN_GROUPS groups or more this visit), visit
--- (which bank visit this is: what only grows is kept for one) }, and answers the height it took, 0
--- for nothing to show.
function HF.AddSection(name, spec)
  if not PINNED[name] and name ~= "carry" then
    error("GoldCap: the Hoard has no place named " .. tostring(name), 2)
  end
  local old = HF._sections[name]
  if old and old.frame then old.frame:Hide() end
  HF._sections[name] = { spec = spec }
end

-- A new visit: the switch, the list, the search, the selection and the press start again, and the
-- window reads afresh and takes its height at its first paint (the route's handler has run already:
-- the window's hooks run after its handlers).
local function newVisit()
  HF._runId, HF._runBank, HF._runSwitch = nil, nil, nil
  HF._runInto, HF._runRows, HF._moved, HF._runEnd = nil, nil, {}, nil
  HF._visit = HF._visit + 1
  HF._moving, HF._width, HF._worthW, HF._height = {}, nil, nil, nil
  HF._reading, HF._dirty = nil, nil
  -- The switch starts again on the bank the window shows.
  HF._bankType, HF._seenType, HF._paintedType = nil, nil, nil
  HF._shown, HF._unfolded, HF._open = {}, false, nil
  HF._searchUp, HF._query, HF._filter, HF._sort = nil, "", "move", "value"
  HF._selected, HF._selBank, HF._selH = {}, nil, nil
  HF.List.Reset()
end

function HF.OnBankOpened()
  -- A press of the last visit is dropped without a word.
  if HF.machine then HF.machine:OnShown() end
  newVisit()
  HF.Refresh(true)
end

function HF.OnBankClosed()
  if HF.machine then HF.machine:OnClosed() end
  newVisit()
  -- A keep count asked at this bank goes with it.
  closeKeep()
  hideAll()
end

-- BAG_UPDATE_DELAYED, each Warband Bank slot change the route hands on (one move into it tells
-- both), a bank panel reset (OnBankShown), a run's end, a settle timer: the window paints once on
-- the next frame for all of them, reading the bags and the banks again, and never inside the
-- client's event or Blizzard's call. A paint a click made with a read since makes it needless
-- (HF._dirty), unless a run over has heard of its stacks meanwhile. A run over hears of a stack
-- that landed after it, the bank open or not (settleEndings).
function HF.OnBagsChanged()
  if not GC.BankRoute._open and #HF._endings == 0 then return end
  HF._dirty = true
  if HF._repaintQueued then return end
  if not (C_Timer and C_Timer.After) then
    settleEndings()
    if GC.BankRoute._open then refresh(true) end
    return
  end
  HF._repaintQueued = true
  C_Timer.After(0, function()
    HF._repaintQueued = nil
    local heard = settleEndings()
    if (HF._dirty or heard) and GC.BankRoute._open then refresh(true) end
  end)
end

-- The bank window shows a bank: as it opens, when the player switches between the character's own
-- bank and the Warband Bank, and when a tab is bought. The switch goes along when the bank shown
-- changed (refresh), and a bought tab may enable a side of it. Blizzard's panel calls this from
-- inside its own work (the tab click's SetTab, the window's OnShow), so the window repaints on the
-- next frame (OnBagsChanged), once for a run of them, and never inside Blizzard's call.
function HF.OnBankShown()
  if not GC.BankRoute._open then return end
  HF.OnBagsChanged()
end

-- The route's handlers are what Core/Init.lua calls on the bank events; the window follows each.
if hooksecurefunc and GC.BankRoute then
  hooksecurefunc(GC.BankRoute, "OnBankOpened", HF.OnBankOpened)
  hooksecurefunc(GC.BankRoute, "OnBankClosed", HF.OnBankClosed)
  hooksecurefunc(GC.BankRoute, "OnBagsChanged", HF.OnBagsChanged)
end
-- Blizzard's bank panel (Blizzard_UIPanels_Game's BankFrame.lua, BankPanelMixin) resets as the
-- window opens (its OnShow), when the player clicks the other bank's tab (BankFrame:SetTab, then
-- SetBankType while the panel is shown) and on BANK_TABS_CHANGED for its bank; by the next frame
-- the panel is shown and BankFrame:GetActiveBankType() answers the bank it shows. Not a hook on
-- BankFrame's SetTab: the tab buttons call the function captured at load
-- (TabSystemOwnerMixin:SetTabSystem's GenerateClosure), which a hook on the frame never sees. A
-- post-hook on a call nothing protected goes through; the window only reads and paints.
local bankPanel = _G.BankPanel
if hooksecurefunc and type(bankPanel) == "table" and type(bankPanel.Reset) == "function" then
  hooksecurefunc(bankPanel, "Reset", HF.OnBankShown)
end
