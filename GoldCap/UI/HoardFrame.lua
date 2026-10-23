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
-- and its painting, is UI/HoardRow.lua's, loaded after this file. With no followed group and no
-- section there is no window at all: it is not built and no slot is read for it.
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
-- only widens, and an opened row keeps room for the most its lines can say.
--
-- Later parts of the window paint into it through AddSection (the tiles above the groups, the carry
-- list and the footer below them) and move through Press, so the window keeps one run.
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
-- the name.
local L = {
  WIDTH = 382, PAD = 12, GUTTER = 22, X = 4, SCREEN_GAP = 80, MIN_H = 160,
  HEAD_H = 28, LOGO = 22, CLOSE = 22, CLOSE_ICON = 10, SWITCH_GAP = 8, SEG_H = 20, SEG_PAD = 2, SEG_MIN = 50,
  FREE_GAP = 10, FREE_ICON = 10, FREE_PART = 4, SECTION_GAP = 11, HEADING_GAP = 5, ROW_GAP = 3,
  ROW_H = 26, FOLDER_H = 30, ROW_PAD = 6, TEXT_PAD = 5, INDENT = 15, ICON = 15, ICON_GAP = 2, MOVE = 18,
  MOVE_ICON = 9, MOVE_GAP = 4, WORTH_W = 46, COL_GAP = 6, CHIP_H = 13, CHIP_GAP = 4, NAME_MIN = 60,
  MIN_ICONS = 3, CHEVRON = 8, BAR_H = 2, BAR_IN = 7, ALL_H = 18, LEGEND_W = 7, LEGEND_H = 3, FOLD_H = 22,
  ITEM_ICON = 16, ITEM_GAP = 4, KEEP_H = 16, KEEP_PAD = 5, PENCIL = 8, HANDLE_H = 28, HANDLE_LOGO = 18,
}
-- The backpack, the four bag slots and the reagent bag: herbs, ore and cloth go to the reagent bag.
local BAGS = { 0, 1, 2, 3, 4, 5 }

-- The bank's share in the legend of the bar under each row (the bar's own is a step darker,
-- UI/HoardRow.lua): the kit's "yours" blue dimmed to the boards' slate, the kit having no slate of
-- its own. The bags' share is the kit's gold.
local SLATE = { K.yours[1], K.yours[2], K.yours[3], 0.6 }

-- The stacks a press has sent, "bag:slot" -> { itemID, count } as the slot held them, until the
-- slot shows the move or the settle timer gives up on it.
HF._moving = {}
-- The press machine (Core/VendorPress.lua), made at the first press; the run id of the press now
-- running (Press), the bank its stacks go to or come from, and the bank the switch named when it
-- started. Every button a press came from, to find the one that carries the running id now.
HF.machine = nil
HF._runId, HF._runBank, HF._runSwitch = nil, nil, nil
HF._movers = setmetatable({}, { __mode = "k" })
-- While the bank is open: the bank the window works with (Enum.BankType), as of its last paint, and
-- the bank the bank window showed then (the switch goes along only when that changes); the window's
-- width and its worth column's, which only grow; the groups Core/Hoard.lua's Rows has listed in
-- this visit, which stay listed; whether the fold line is open; and the group row open, by key.
HF._bankType, HF._seenType = nil, nil
HF._width, HF._worthW = nil, nil
HF._shown = {}
HF._unfolded = false
HF._open = nil
-- What later parts of the window paint (AddSection), by place.
HF._sections = {}
HF._rows = {}
-- GC.db.hoard saved by a newer GoldCap cannot be written (Core/Hoard.lua): the X then closes the
-- window for this session, and a folder opens for this session.
HF._closedHere = nil
HF._foldersHere = {}

local frame, handle
local settleSeq = 0

local function isUp(widget)
  return type(widget) == "table" and widget.IsShown ~= nil and widget:IsShown() == true
end

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

-- Forgets a sent stack once its slot no longer holds it as it was: moved, merged, or emptied.
local function pruneMoving()
  for slotKey, sent in pairs(HF._moving) do
    local bag, slot = slotKey:match("^(%-?%d+):(%d+)$")
    local info = C_Container.GetContainerItemInfo(tonumber(bag), tonumber(slot))
    if not (info and info.itemID == sent.itemID and (info.stackCount or 1) == sent.count) then
      HF._moving[slotKey] = nil
    end
  end
end

-- Nothing moved in time (a full bank or bags, a slot the server refused): the stacks are offered
-- again.
function HF._Settle(token)
  if token ~= settleSeq then return end
  HF._moving = {}
  HF.Refresh()
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

-- A run over: the window repaints, unless it stopped for a repaint already on its way (the switch
-- came to the other bank, HF.Refresh; another button's press, Press; the window closed).
local function report(result)
  HF._runId, HF._runBank, HF._runSwitch = nil, nil, nil
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
--- switch's bank unless the caller names its own (the carry list's Warband Bank). The machine makes
--- the first move inside this call, so it is called only from the player's own click. The window is
--- repainted only after, so the button's state changes after its call.
---
--- A run is known by `button.runId`, what the button moves, not by the widget: a row's Store or
--- Take out is "<kind>:<key>:in" or ":out" (kind "group" or "folder", the row's key), Store all
--- and Take all out are "all:in" and "all:out", and a later part names its own buttons the same
--- way ("tile:<id>", "carry:<id>", "selection:in"). A button with no run id is its own. A press
--- of the id that runs stops it and moves nothing; a press of another id stops it and starts its
--- own.
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
  if not machine:IsRunning() then HF._runBank = bankType end
  machine:Press(rows)
  if machine:IsRunning() then
    HF._runId, HF._runBank, HF._runSwitch = id, bankType, HF._bankType
  else
    HF._runBank = nil
  end
  HF.Refresh()
end

--- The run id of the press that runs now, or nil; and the button that carries that id where the
--- player sees it now (a row redrawn since may carry it on another widget), or nil.
function HF.Running()
  local id = HF._runId
  if id == nil then return nil end
  for button in pairs(HF._movers) do
    if (button.runId or button) == id and button:IsVisible() then return id, button end
  end
  return id, nil
end

-- A move button's own click: its whole list, the way it moves, through Press.
local function onMoveClick(button)
  HF.Press(button, button.stacks, button.into)
end

-- ---------------------------------------------------------------------------------------------
-- The clicks that move nothing
-- ---------------------------------------------------------------------------------------------

-- A keep count asked in the kit's popup goes with the row it was asked from: on the X, and on any
-- click that redraws the list (a row opened or closed, a folder, the fold line), which can put
-- another group on that row.
local function closeKeep()
  if not GC.BuyCapEditor then return end
  for _, row in ipairs(HF._rows) do GC.BuyCapEditor.CloseFor(row.keep) end
end

-- A side of the bank switch: the window works with that bank until the bank window comes to show
-- the other one or the bank closes. It moves nothing; a disabled side gets no click.
local function onBankClick(button)
  HF._bankType = button.bankType
  HF.Refresh()
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
  HF.Refresh()
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
  HF.Refresh()
end

-- ---------------------------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------------------------

-- What the next press of a move button moves, as the bank card's labels said it: the stack and how
-- many stacks are left, or that there is nothing to move. Repainted while it shows (paintMove).
local function showMoveTip(button)
  local tooltip = _G.GameTooltip
  if not (tooltip and button.tipTitle) then return end
  tooltip:SetOwner(button, GC.Theme.TooltipAnchor(button))
  tooltip:AddLine(GC.Util.ClientText(button.tipTitle), K.goldText[1], K.goldText[2], K.goldText[3])
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

-- A move button: its click is the press, its tooltip what the press moves.
local function moveButton(parent, into, variant)
  local button = GC.Theme.Button(parent, variant, "badge")
  -- In the scroll, which clips at its edges: a halo would be cut flat along its side.
  button:SetGlow(false)
  button.into = into
  button:SetScript("OnClick", onMoveClick)
  button:SetScript("OnEnter", showMoveTip)
  button:SetScript("OnLeave", hideTip)
  HF._movers[button] = true
  return button
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

  -- The bank switch: the crafting panel's view switch (UI/CraftPanel.lua), a sunken track in the
  -- glass's border with the other bank bare text, and the bank chosen in the gold fill the board
  -- gives it (no halo: it is a choice, not the window's main action). In the bank window's order.
  local choice = CreateFrame("Frame", nil, frame)
  choice.track = T.SlicedTexture(choice, "BACKGROUND", T.MEDIA .. "plaque.png", { 0, 0, 0, 0.35 }, T.SLICE.plaque)
  choice.track:SetAllPoints(choice)
  choice.edge = T.SlicedTexture(choice, "BORDER", T.MEDIA .. "plaque_ring.png", K.glassBorder, T.SLICE.plaque)
  choice.edge:SetAllPoints(choice)
  choice.sides = {}
  for i, bankType in ipairs({ banks() }) do
    local side = T.Button(choice, "segment", "plaque")
    side:SetGlow(false)
    side:SetHeight(L.SEG_H)
    side.bankType = bankType
    side:SetScript("OnClick", onBankClick)
    track(frame, side.text)
    choice.sides[i] = side
  end
  frame.choice = choice
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
  -- Quiet, as the board draws them: no fill, a faint ring, the words in the second text colour
  -- (paintMove keeps that over the kit's own on every enable).
  for _, entry in ipairs({ { "storeAll", true, "all:in" }, { "takeAll", false, "all:out" } }) do
    local b = moveButton(content, entry[2], "segment")
    b:SetHeight(L.ALL_H)
    b:SetRing(K.windowBorder)
    b.runId, b.textColor = entry[3], K.text2
    track(frame, b.text)
    frame[entry[1]] = b
  end
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
  local bags, bank = frame.freeBags, frame.freeBank
  local bagsW = paintFree(bags, GC.L["Bags %d free"], freeIn(BAGS))
  local bankW = paintFree(bank, GC.L["Bank %d free"], freeIn(GC.BankRoute.BankTabs(state.bankType)))
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

-- Store all and Take all out: every group's list, group by group in the plan's order. Their label
-- never changes, so a press never resizes them.
local function paintAll(groups, writable)
  local lists = { toBank = {}, toBags = {} }
  for _, group in ipairs(groups) do
    for _, key in ipairs({ "toBank", "toBags" }) do
      for _, stack in ipairs(group[key]) do lists[key][#lists[key] + 1] = stack end
    end
  end
  for _, entry in ipairs({ { frame.storeAll, lists.toBank, GC.L["Store all"] },
    { frame.takeAll, lists.toBags, GC.L["Take all out"] } }) do
    local button, stacks, label = entry[1], entry[2], entry[3]
    button:SetLabel(label)
    button:FitLabels({ label }, 0)
    paintMove(button, stacks, label)
  end
  -- Without the keep counts (a newer GoldCap's), Store is not offered; Take all out keeps its
  -- place.
  frame.storeAll:SetShown(writable)
end

-- "Your groups" with the legend at `y` in the scroll, Store all and Take all out at its right, or
-- on a line under it when there is no room. Answers the y under it.
local function paintHeading(y, inner)
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
  local lineH = oneLine and L.ALL_H or 12
  local mid = y + lineH / 2
  title:ClearAllPoints()
  title:SetPoint("LEFT", frame.content, "TOPLEFT", 0, -mid)
  for _, part in ipairs(parts) do
    part.entry.swatch:ClearAllPoints()
    part.entry.swatch:SetPoint("LEFT", frame.content, "TOPLEFT", part.x, -mid)
    part.entry.text:ClearAllPoints()
    part.entry.text:SetPoint("LEFT", part.entry.swatch, "RIGHT", 4, 0)
  end
  local buttonsY = oneLine and y or (y + lineH + L.HEADING_GAP)
  frame.takeAll:ClearAllPoints()
  frame.takeAll:SetPoint("TOPRIGHT", frame.content, "TOPLEFT", inner, -buttonsY)
  frame.storeAll:ClearAllPoints()
  frame.storeAll:SetPoint("TOPRIGHT", frame.content, "TOPLEFT", inner - takeW - 4, -buttonsY)
  return buttonsY + L.ALL_H
end

-- What a row of the list (UI/HoardRow.lua, loaded after this file) is built and painted with: the
-- window's measures and slate, and the helpers both files draw with.
HF.ui = {
  L = L, SLATE = SLATE, setText = setText, colour = colour, wrapping = wrapping, heightOf = heightOf,
  itemName = itemName, worthText = worthText, plate = plate, moveButton = moveButton, paintMove = paintMove,
  track = track, restamp = restamp, closeKeep = closeKeep,
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

-- A section (AddSection) at `y`: built once in a frame of its own, painted with `ctx`; shown with a
-- height above 0. Answers its height.
local function paintSection(name, ctx, y)
  local entry = HF._sections[name]
  if not entry then return 0 end
  if not entry.frame then
    entry.frame = CreateFrame("Frame", nil, frame.content)
    entry.spec.build(entry.frame)
  end
  local f = entry.frame
  f:SetWidth(ctx.width)
  local h = math.ceil(entry.spec.paint(f, ctx) or 0)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
  f:SetHeight(math.max(h, 1))
  f:SetShown(h > 0)
  return h
end

-- How wide the worth column must be for `lists`' rows, and never narrower than it has been in this
-- visit.
local function worthWidth(lists)
  local widest = math.max(L.WORTH_W, HF._worthW or 0)
  for _, list in ipairs(lists) do
    for _, data in ipairs(list) do
      setText(frame.measure, worthText(data.worth))
      widest = math.max(widest, math.ceil(frame.measure:GetStringWidth() or 0))
    end
  end
  HF._worthW = widest
  return widest
end

-- The window's width: the board's with the scroll's gutter, or as wide as its widest label in the
-- player's language needs (a side of the switch in the header, Store all with Take all out in the
-- list), and only ever wider while the bank is open, so nothing reflows under the cursor. Answers
-- it, the header's room inside the window's margins, and the list's, which the gutter takes from.
local function widthFor()
  local need = 0
  for _, side in ipairs(frame.choice.sides) do
    side:SetLabel(bankName(side.bankType))
    side:FitLabels({ side.label }, L.SEG_MIN)
    need = math.max(need, side:GetWidth() + 2 * L.SEG_PAD + 2 * L.PAD)
  end
  for _, entry in ipairs({ { frame.storeAll, GC.L["Store all"] }, { frame.takeAll, GC.L["Take all out"] } }) do
    entry[1]:SetLabel(entry[2])
    entry[1]:FitLabels({ entry[2] }, 0)
  end
  need = math.max(need, frame.storeAll:GetWidth() + 4 + frame.takeAll:GetWidth() + 2 * L.PAD + L.GUTTER)
  local width = math.max(L.WIDTH, need, HF._width or 0)
  HF._width = width
  return width, width - 2 * L.PAD, width - 2 * L.PAD - L.GUTTER
end

-- The window, top to bottom: the header and the switch, fixed; then in the scroll the tiles, the
-- groups' heading, the rows the plan lists, the fold line with, opened, the folded rows under it,
-- the carry list and the footer. Clamped to the screen and never taller than the room under its
-- top. Laid out, not shown: answers false when it has nothing at all to show (no followed group,
-- and every section empty).
local function paint(state)
  local beside = place(frame)
  local width, head, inner = widthFor()
  frame:SetWidth(width)
  setText(frame.brand, "GoldCap")
  setText(frame.title, GC.L["Hoard"])
  frame.close:ClearAllPoints()
  frame.close:SetPoint("TOPRIGHT", frame, "TOPLEFT", L.PAD + head, -(L.PAD + (L.HEAD_H - L.CLOSE) / 2))
  local y = L.PAD + L.HEAD_H + L.SWITCH_GAP
  y = y + paintSwitch(state, y, head) + L.SECTION_GAP
  local top = y

  local writable = GC.BankGroups.Writable(GC.db)
  for _, group in ipairs(state.groups) do
    -- A newer GoldCap saved the keep counts, which this one cannot read: Store would ignore what
    -- the player keeps, so it moves nothing.
    if not writable then group.toBank = {} end
  end
  local result = GC.Hoard.Rows(state.groups, {
    valueOf = valueOf, filter = "move", sort = "value", folderOpen = folderOpen, shown = HF._shown,
    playOf = playOf, iconOf = function(itemID) return state.icons[itemID] end,
  })
  local folded = HF._unfolded and result.foldedRows or {}
  -- The folded rows' worth is measured too, closed, so opening the fold line moves no column.
  local ctx = { bankType = state.bankType, usable = state.usable, running = HF._runId ~= nil,
    runId = HF._runId, groups = state.groups, valueOf = valueOf, width = inner, writable = writable,
    icons = state.icons, perItem = state.perItem, worthW = worthWidth({ result.rows, result.foldedRows }) }

  local cy, shownH = 0, 0
  local tilesH = paintSection("tiles", ctx, cy)
  if tilesH > 0 then cy, shownH = cy + tilesH + L.SECTION_GAP, shownH + tilesH end
  local groupsUp = state.hasGroups
  local index = 1
  if groupsUp then
    paintAll(state.groups, writable)
    frame.groupsTitle:Show()
    frame.takeAll:Show()
    for _, entry in ipairs(frame.legend) do entry.swatch:Show(); entry.text:Show() end
    cy = paintHeading(cy, inner) + L.HEADING_GAP + 2
    if #state.groups == 0 then
      frame.empty:SetWidth(inner)
      setText(frame.empty, GC.L["None of your groups' items are in your bags or this bank."])
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
  for _, name in ipairs({ "carry", "footer" }) do
    local h = paintSection(name, ctx, cy + L.SECTION_GAP)
    if h > 0 then cy, shownH = cy + L.SECTION_GAP + h, shownH + h end
  end
  if not groupsUp and shownH == 0 then return false end

  cy = math.ceil(math.max(cy, 1))
  frame.content:SetSize(inner, cy)
  local height = math.min(top + cy + L.PAD, maxHeight(beside))
  frame:SetHeight(height)
  frame.scroll:ClearAllPoints()
  frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -top)
  frame.scroll:SetSize(inner, height - top - L.PAD)
  return true
end

-- What the window reads at a paint: the bags and the bank it works with, as the bank route's reader
-- reads them, the plan over them, each item's count in the bags and in that bank, and an icon for
-- each item, from the first of its stacks read. Nothing is read without a followed group.
local function read(bankType, usable, hasGroups)
  local state = { bankType = bankType, usable = usable, hasGroups = hasGroups, groups = {}, perItem = {}, icons = {} }
  if not hasGroups then return state end
  local route, groupOf = GC.BankRoute, GC.GroupRules.GroupOf
  local bagStacks = route.ReadStacks(BAGS, false, groupOf, bankType)
  local bankStacks = route.ReadStacks(route.BankTabs(bankType), true, groupOf, bankType)
  state.groups = GC.BankGroups.Plan(bagStacks, bankStacks, {
    groupOf = groupOf,
    keepFor = function(key) return GC.BankGroups.KeepFor(GC.db, key) end,
    moving = HF._moving,
  })
  for _, side in ipairs({ { bagStacks, "bags" }, { bankStacks, "bank" } }) do
    for _, stack in ipairs(side[1]) do
      local here = state.perItem[stack.itemID] or { bags = 0, bank = 0 }
      here[side[2]] = here[side[2]] + stack.count
      state.perItem[stack.itemID] = here
      if state.icons[stack.itemID] == nil then state.icons[stack.itemID] = stack.icon end
    end
  end
  return state
end

local function hideAll()
  if frame then frame:Hide() end
  if handle then handle:Hide() end
end

-- Closed: the handle beside the bank window instead, the mark and the window's name.
local function showHandle()
  if frame then frame:Hide() end
  if not handle then buildHandle() end
  local wasUp = handle:IsShown()
  place(handle)
  setText(handle.text, GC.L["Hoard"])
  handle:SetWidth(6 + L.HANDLE_LOGO + 5 + math.ceil(handle.text:GetStringWidth() or 0) + 10)
  handle:Show()
  if not wasUp then restamp(handle) end
end

-- Reads the bags and the bank the window works with again and paints it, or hides it: with no
-- followed group and no section (then nothing is built and no slot is read), with the bank closed
-- or not the window, with neither bank usable here with a tab, and with nothing at all to show.
-- While the player has closed it, the handle shows in its place, when the window would have.
local function refresh()
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
  -- A run started under the other side of the switch stops: its stacks were planned against that
  -- bank.
  if HF._runSwitch ~= nil and HF._runSwitch ~= bankType and HF.machine then HF.machine:Stop("bank") end
  if not usable[bankType] then return hideAll() end
  local closed = closedNow()
  -- A followed group always makes a window, so its handle needs no reading.
  if closed and hasGroups then return showHandle() end
  pruneMoving()
  local state = read(bankType, usable, hasGroups)
  if not frame then build() end
  local wasUp = frame:IsShown()
  if not paint(state) then return hideAll() end
  if closed then return showHandle() end
  if handle then handle:Hide() end
  frame:Show()
  if wasUp then return end
  restamp(frame)
  for _, row in ipairs(HF._rows) do
    if row:IsShown() then restamp(row) end
  end
end

-- What of the Hoard stands beside the bank window now: the window, the handle, or nothing.
local function standing()
  if isUp(frame) then return frame end
  if isUp(handle) then return handle end
  return nil
end

--- Paints the window, or hides it (refresh above). The carry list (UI/BankRoute.lua) stands beside
--- whatever of the Hoard stands beside the bank window, so it is placed again when that changes.
function HF.Refresh()
  local before = standing()
  refresh()
  if standing() ~= before and GC.BankRoute._open then GC.BankRoute.Refresh() end
end

--- A later part of the window: `name` is its place ("tiles" between the switch and the groups,
--- "carry" and "footer" below the groups), `spec` = { build = fn(parent), paint = fn(section, ctx)
--- -> height }. `build` runs once, with a frame of its own in the scroll; `paint` at every paint of
--- the window, with ctx = { bankType, usable = { [bankType] = bool }, running, runId (the run id
--- that runs, Press), groups (the plan's), valueOf, width }, and answers the height it took, 0 for
--- nothing to show.
function HF.AddSection(name, spec)
  if name ~= "tiles" and name ~= "carry" and name ~= "footer" then
    error("GoldCap: the Hoard has no place named " .. tostring(name), 2)
  end
  local old = HF._sections[name]
  if old and old.frame then old.frame:Hide() end
  HF._sections[name] = { spec = spec }
end

-- A new visit: the switch, the list and the press start again (the route has painted already: the
-- window's hooks run after its handlers).
local function newVisit()
  HF._runId, HF._runBank, HF._runSwitch = nil, nil, nil
  HF._moving, HF._width, HF._worthW = {}, nil, nil
  -- The switch starts again on the bank the window shows.
  HF._bankType, HF._seenType = nil, nil
  HF._shown, HF._unfolded, HF._open = {}, false, nil
end

function HF.OnBankOpened()
  -- A press of the last visit is dropped without a word.
  if HF.machine then HF.machine:OnShown() end
  newVisit()
  HF.Refresh()
end

function HF.OnBankClosed()
  if HF.machine then HF.machine:OnClosed() end
  newVisit()
  -- A keep count asked at this bank goes with it.
  closeKeep()
  hideAll()
end

-- BAG_UPDATE_DELAYED, and a run of Warband Bank slot changes (the route repaints once after it).
function HF.OnBagsChanged()
  if GC.BankRoute._open then HF.Refresh() end
end

-- The bank window shows a bank: as it opens, when the player switches between the character's own
-- bank and the Warband Bank, and when a tab is bought. The switch goes along when the bank shown
-- changed (refresh), and a bought tab may enable a side of it. Blizzard's panel calls this from
-- inside its own work (the tab click's SetTab, the window's OnShow), so the window repaints on the
-- next frame, once for a run of them, and never inside Blizzard's call.
function HF.OnBankShown()
  if not GC.BankRoute._open or HF._repaintQueued then return end
  if not (C_Timer and C_Timer.After) then return HF.Refresh() end
  HF._repaintQueued = true
  C_Timer.After(0, function()
    HF._repaintQueued = nil
    HF.OnBagsChanged()
  end)
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
