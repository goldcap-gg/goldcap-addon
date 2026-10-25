local _, GC = ...

-- What the GoldCap Hoard's list does beyond its rows (UI/HoardFrame.lua, the window, and
-- UI/HoardRow.lua, a row, both loaded before this file): finding a group, checking several, and
-- showing a run as it goes. Over many groups (from GC.Hoard.SEARCH_MIN_GROUPS) the search row,
-- fixed above the list: the BUY tab's search box, the filter "To move here" or "All" and the sort
-- "By value" or "By name", for the bank visit. A checkbox on every row, and the selection bar's
-- room at the window's foot from the first paint with checkboxes: a quiet hint while nothing is
-- checked, then how many groups (and how many of them the search or the fold hides) and their
-- worth, their Store and Take out, and a clear button. And a run's look: the button pressed turns
-- into its Stop where it stands, its tooltip saying where the run goes, and the other move of its
-- pair gives way (PaintPair); how many stacks have moved, with a gold fill; on Store all's line and
-- the selection bar, the cast bar's words too; and the marks on the items' icons (RunState). What
-- is checked, found and run is Core/Hoard.lua's (Rows, Check, CheckState, NotShown, Selection);
-- every move is the window's press (its move buttons, HF.ui.moveButton), and nothing here moves an
-- item or presses for the player.
local HF = GC.HoardFrame
local K = GC.Kit.Tokens.color
local U = HF.ui
local L = U.L
local setText, colour, wrapping, heightOf, track = U.setText, U.colour, U.wrapping, U.heightOf, U.track

HF.List = {}
local HL = HF.List

-- The colours the boards draw these with, from the kit's tokens: an unchecked box's faint ring (a
-- checked one is filled and ringed in gold), a cast bar's track under its gold fill, the selection
-- bar in a gold wash with a gold ring, its Take out ringed in gold (its clear button wears the
-- window's own border).
local CHECK_OFF = { 1, 1, 1, 0.28 }
local FILL_TRACK = { 1, 1, 1, 0.08 }
local BAR_FILL = { K.gold[1], K.gold[2], K.gold[3], 0.10 }
local BAR_RING = { K.gold[1], K.gold[2], K.gold[3], 0.55 }
local TAKE_RING = { K.gold[1], K.gold[2], K.gold[3], 0.5 }
-- A move button's Stop: the kit's stop look with a ring in its colour.
local STOP_RING = { K.loss[1], K.loss[2], K.loss[3], 0.5 }
-- The most a run's count can say: the bags and both banks hold fewer than a thousand stacks.
local COUNT_MOST = 999

local frame

-- ---------------------------------------------------------------------------------------------
-- A run's look
-- ---------------------------------------------------------------------------------------------

-- Puts a move button in its Stop look (`stop` true) or back in its own (`button.look`), only on a
-- change: SetVariant paints the words in the variant's colour whatever the button's state. A button
-- with words beside its icon says Stop without the icon (labelMove); an icon alone turns into the
-- kit's X.
local function wear(button, stop)
  if (button.stopping == true) == stop then return end
  button.stopping = stop
  local look = button.look
  button:SetVariant(stop and "stop" or look.variant)
  button:SetRing(stop and STOP_RING or look.ring)
  if button.icon and look.label then
    button.icon:SetShown(not stop)
  elseif button.icon then
    GC.Theme.SetIcon(button.icon, stop and "close" or look.icon)
  end
end

-- A move button while the run its press started goes (`run`, RunState's): its Stop, live whatever
-- it has left (a press of it is the second press, which stops the run: HF.Press), its tooltip
-- saying what it stops and where the run goes.
local function paintStop(button, stacks, run)
  wear(button, true)
  button.stacks, button.tipTitle, button.tipNote = stacks, GC.L["Stop moving"], run and run.label
  button:Enable()
  if button.icon then button.icon:SetVertexColor(K.loss[1], K.loss[2], K.loss[3], 1) end
  local tooltip = _G.GameTooltip
  if tooltip and tooltip.IsOwned and tooltip:IsOwned(button) then U.showMoveTip(button) end
end

--- Store and Take out side by side (a row's, Store all and Take all out, the selection bar's):
--- `pair` = { { store, its stacks, its tooltip's title, a note under it or nil }, { take out, ...
--- } }. Each paints what it moves (HF.ui.paintMove); while the run of one of them goes (`runId`,
--- `run` as RunState gives it), that one is Stop and the other gives way. Store shows only with
--- the keep counts readable (`writable`); Take out keeps its place. Answers the button whose run
--- goes, or nil.
function HL.PaintPair(pair, runId, writable, run)
  local running
  for _, entry in ipairs(pair) do
    if runId ~= nil and entry[1].runId == runId then running = entry[1] end
  end
  local tooltip = _G.GameTooltip
  for i, entry in ipairs(pair) do
    local button = entry[1]
    if button == running then
      paintStop(button, entry[2], run)
    else
      wear(button, false)
      button.tipNote = entry[4]
      U.paintMove(button, entry[2], entry[3])
    end
    local up = (running == nil or running == button) and (i > 1 or writable)
    if not up and tooltip and tooltip.IsOwned and tooltip:IsOwned(button) then U.hideTip() end
    button:SetShown(up)
  end
  return running
end

--- The run that goes, as its cast bars say it: { id, into, label, done, total }, `done` its
--- stacks whose slots have shown the move (the window's HF._moved, never a stack the settle timer
--- gave up on) of the `total` it was pressed with; and each item's mark, { [itemID] = "moving" |
--- "moved" }: moved once every stack of it in the run has, else moving while one is on its way.
--- Nothing while no run goes.
function HL.RunState()
  local rows = HF._runRows
  if HF._runId == nil or not rows then return nil, {} end
  local done, items = 0, {}
  for _, row in ipairs(rows) do
    local slotKey = row.bag .. ":" .. row.slot
    local item = items[row.itemID] or { total = 0, moved = 0, moving = false }
    item.total = item.total + 1
    if HF._moved[slotKey] then
      done, item.moved = done + 1, item.moved + 1
    elseif HF._moving[slotKey] then
      item.moving = true
    end
    items[row.itemID] = item
  end
  local marks = {}
  for itemID, item in pairs(items) do
    if item.moved == item.total then
      marks[itemID] = "moved"
    elseif item.moving then
      marks[itemID] = "moving"
    end
  end
  local label = HF._runInto and GC.L["Moving to %s"]:format(U.bankName(HF._runBank)) or GC.L["Moving to your bags"]
  return { id = HF._runId, into = HF._runInto, label = label, done = done, total = #rows }, marks
end

--- What a cast bar can say at the bank `bankType`, either way a run goes: the room every line keeps
--- for it.
function HL.CastLabels(bankType)
  return { GC.L["Moving to %s"]:format(U.bankName(bankType)), GC.L["Moving to your bags"] }
end

function HL.CountText(run)
  return ("%d / %d"):format(run.done, run.total)
end

--- A cast bar's parts on `parent`, its lines tracked on `owner` for the redraw cure: with `words`,
--- where the run goes, wrapping, in the gold the board gives them (a row has none: its Stop's
--- tooltip says it); its count in the mono face at `countSize`; its track and gold fill. Hidden
--- until a run paints it.
function HL.NewCast(parent, owner, countSize, words)
  local T = GC.Theme
  local cast = { count = track(owner, T.Num(parent, countSize)), track = T.Solid(parent, "ARTWORK", FILL_TRACK),
    fill = T.Solid(parent, "OVERLAY", K.gold) }
  if words then
    cast.label = track(owner, wrapping(T.Label(parent, 9)))
    colour(cast.label, K.goldText)
  end
  colour(cast.count, K.text2)
  cast.count:SetWordWrap(false)
  HL.HideCast(cast)
  return cast
end

function HL.HideCast(cast)
  for _, part in ipairs({ cast.count, cast.track, cast.fill }) do part:Hide() end
  if cast.label then cast.label:Hide() end
end

-- The room the most a cast bar's count can say takes.
local function countRoom(cast)
  local was = cast.count:GetText()
  setText(cast.count, ("%d / %d"):format(COUNT_MOST, COUNT_MOST))
  local width = math.ceil(cast.count:GetStringWidth() or 0)
  setText(cast.count, was)
  return width
end

--- The room a cast bar takes on a line `width` wide (Store all's, the selection bar's): its words,
--- wrapping, as tall as the longest of `labels` (HF.ui.tallest: the words are set again when a run
--- paints it), the most its count can say at their right, and the gold fill under them.
function HL.LineCastHeight(cast, labels, width)
  return U.tallest(cast.label, labels, width - countRoom(cast) - L.CAST_GAP) + 2 + L.FILL_H
end

--- The gold fill of `run` (done of total) at `x`, `y` in `parent`, `width` wide, over its track.
function HL.PaintFill(cast, parent, x, y, width, run)
  cast.track:ClearAllPoints()
  cast.track:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  cast.track:SetSize(width, L.FILL_H)
  cast.track:Show()
  local fillW = run.total > 0 and math.floor(width * run.done / run.total + 0.5) or 0
  cast.fill:ClearAllPoints()
  cast.fill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  cast.fill:SetSize(math.max(fillW, 1), L.FILL_H)
  cast.fill:SetShown(fillW > 0)
end

--- A cast bar on a line (LineCastHeight) at `x`, `y` in `parent`, `width` wide: where the run goes,
--- how far it is at the right of the words' first line, the gold fill under the words.
function HL.PaintLineCast(cast, run, parent, x, y, width)
  local label = cast.label
  label:SetWidth(math.max(1, width - countRoom(cast) - L.CAST_GAP))
  setText(label, run.label)
  label:ClearAllPoints()
  label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
  label:Show()
  setText(cast.count, HL.CountText(run))
  cast.count:ClearAllPoints()
  cast.count:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, -y)
  cast.count:Show()
  HL.PaintFill(cast, parent, x, y + math.ceil(heightOf(label, 11)) + 2, width, run)
end

-- ---------------------------------------------------------------------------------------------
-- Checking groups
-- ---------------------------------------------------------------------------------------------

-- A run of the selection bar's goes with the bar: no Stop is left to press.
local function stopBarRun()
  local id = HF._runId
  if (id == "selection:in" or id == "selection:out") and HF.machine then HF.machine:Stop("pressed") end
end

-- A checkbox's click, which moves nothing: a group checks or unchecks; a folder checks every group
-- it lists from off, and clears them all from on or mixed (GC.Hoard.Check). The list is redrawn
-- from what the window last read, so a keep count asked from a row goes (HF.ui.closeKeep).
local function onCheckClick(check)
  local data = check.data
  if not data then return end
  U.closeKeep()
  GC.Hoard.Check(data, HF._selected)
  if next(HF._selected) == nil then stopBarRun() end
  HF.Refresh()
end

--- A row's checkbox, as the board draws it: a small rounded box, a faint ring while off, filled and
--- ringed in gold with the kit's check (on) or minus (some of a folder's groups) in the dark of a
--- gold fill. Above the row's own click, which opens it.
function HL.NewCheck(row)
  local T = GC.Theme
  local check = U.plate(row, CHECK_OFF, "badge")
  check:SetSize(L.CHECK, L.CHECK)
  check.fill = T.SlicedTexture(check, "BACKGROUND", T.MEDIA .. "badge.png", K.gold, T.SLICE.badge)
  check.fill:SetAllPoints()
  check.glyph = check:CreateTexture(nil, "OVERLAY")
  check.glyph:SetSize(L.CHECK_GLYPH, L.CHECK_GLYPH)
  check.glyph:SetPoint("CENTER", check, "CENTER", 0, 0)
  check:SetScript("OnClick", onCheckClick)
  return check
end

--- A checkbox for the row `data` (Core/Hoard.lua's Rows) against `selected`: a group's own key, a
--- folder's groups together (GC.Hoard.CheckState). Answers its state: "on", "mixed" or "off".
function HL.PaintCheck(check, data, selected)
  local state = data.kind == "folder" and GC.Hoard.CheckState(data, selected) or (selected[data.key] and "on" or "off")
  check.data, check.state = data, state
  local on = state ~= "off"
  local c = on and K.gold or CHECK_OFF
  check.ring:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  check.fill:SetShown(on)
  if on then GC.Theme.SetIcon(check.glyph, state == "on" and "check" or "minus", K.onGold) end
  check.glyph:SetShown(on)
  return state
end

local function onClearClick()
  U.closeKeep()
  HF._selected = {}
  stopBarRun()
  HF.Refresh()
end

local function showClearTip(button)
  local tooltip = _G.GameTooltip
  if not tooltip then return end
  tooltip:SetOwner(button, GC.Theme.TooltipAnchor(button))
  tooltip:AddLine(GC.Util.ClientText(GC.L["Clear the selection"]), K.text1[1], K.text1[2], K.text1[3])
  tooltip:Show()
end

-- The selection bar, at the window's foot outside the scroll, so it stays in reach over 40 groups;
-- with nothing checked, its room holds a quiet hint instead.
local function buildSelection()
  local T = GC.Theme
  local bar = CreateFrame("Frame", nil, frame)
  bar:EnableMouse(true)
  bar.bg = T.SlicedTexture(bar, "BACKGROUND", T.MEDIA .. "plaque.png", BAR_FILL, T.SLICE.plaque)
  bar.bg:SetAllPoints()
  bar.ring = T.SlicedTexture(bar, "BORDER", T.MEDIA .. "plaque_ring.png", BAR_RING, T.SLICE.plaque)
  bar.ring:SetAllPoints()
  bar.title = track(frame, wrapping(T.Label(bar, 11)))
  colour(bar.title, K.goldText)
  bar.sub = track(frame, wrapping(T.Label(bar, 9)))
  colour(bar.sub, K.text2)
  bar.hint = track(frame, wrapping(T.Label(bar, 10)))
  bar.hint:SetJustifyH("CENTER")
  colour(bar.hint, K.text3)
  -- Store in the gold fill, Take out ringed in gold, each with the kit's tray arrow before its words.
  bar.store = U.moveButton(bar, true, { variant = "primary", icon = "arrowDown", iconColor = K.onGold, label = true })
  bar.take = U.moveButton(bar, false, { variant = "active", ring = TAKE_RING, icon = "arrowUp", iconColor = K.goldText,
    label = true })
  bar.store.runId, bar.take.runId = "selection:in", "selection:out"
  for _, button in ipairs({ bar.store, bar.take }) do
    button:SetHeight(L.SEL_BTN)
    button.icon:SetSize(L.SEL_ICON, L.SEL_ICON)
    button.icon:SetPoint("LEFT", button, "LEFT", L.SEL_BTN_PAD, 0)
    track(frame, button.text)
  end
  bar.clear = T.Button(bar, "ghost", "badge")
  bar.clear:SetSize(L.SEL_BTN, L.SEL_BTN)
  bar.clear:SetRing(K.windowBorder)
  bar.clear.icon = bar.clear:CreateTexture(nil, "OVERLAY")
  bar.clear.icon:SetSize(L.SEL_ICON, L.SEL_ICON)
  bar.clear.icon:SetPoint("CENTER", bar.clear, "CENTER", 0, 0)
  T.SetIcon(bar.clear.icon, "close", K.text2)
  bar.clear:SetScript("OnClick", onClearClick)
  bar.clear:SetScript("OnEnter", showClearTip)
  bar.clear:SetScript("OnLeave", U.hideTip)
  bar.cast = HL.NewCast(bar, frame, 9, true)
  bar:Hide()
  frame.selection = bar
end

-- A selection bar button's words: its own after its icon, or Stop alone while its run goes; as
-- wide as the wider of the two, so its press never resizes it. Answers its width.
local function labelMove(button, label, stop)
  local stopWord = GC.L["Stop"]
  button:SetLabel(stopWord)
  local stopW = math.ceil(button.text:GetUnboundedStringWidth() or 0)
  button:SetLabel(label)
  local labelW = math.ceil(button.text:GetUnboundedStringWidth() or 0)
  local iconRoom = L.SEL_BTN_PAD + L.SEL_ICON + 4
  local width = math.max(iconRoom + labelW + L.SEL_BTN_PAD, stopW + 2 * L.SEL_BTN_PAD)
  button:SetWidth(width)
  if stop then button:SetLabel(stopWord) end
  -- After SetLabel, which bounds the words by the button's own edges again.
  button.text:ClearAllPoints()
  button.text:SetPoint("LEFT", button, "LEFT", stop and 0 or iconRoom, 0)
  button.text:SetPoint("RIGHT", button, "RIGHT", stop and 0 or -L.SEL_BTN_PAD, 0)
  return width
end

-- The selection bar's first line: how many groups are checked, and how many of them the search or
-- the fold line hides, fainter, joined with the language's own punctuation (the key carries it).
local function selectedText(n, hidden)
  local text = n == 1 and GC.L["1 group selected"] or GC.L["%d groups selected"]:format(n)
  if hidden > 0 then text = text .. GC.Util.Colored(K.text3, GC.L[", %d not shown"]:format(hidden)) end
  return text
end

-- Its second line: what the checked groups are worth here, in gold, as a row's worth is written.
local function worthLine(copper)
  local worth = U.worthText(copper)
  return GC.L["Worth about %s"]:format(GC.Util.Colored(K.goldText, worth ~= "" and worth or GC.Util.Money(0)))
end

-- What a press of the bar's Store or Take out moves (`into`: Store's, to the bank the switch
-- names), under its tooltip's title; nothing with nothing to move.
local function moveNote(stacks, into, bankName)
  if #stacks == 0 then return nil end
  return U.stacksInto(#stacks, into and bankName or nil)
end

--- The selection bar for the groups checked of `groups` (the plan's), `head` wide at the window's
--- foot, its bottom `bottom` over the window's. Its room is kept for the visit from the first paint
--- with a group (its rows' checkboxes), as tall as the most it can say (every group checked and
--- hidden, their whole worth, the run's cast bar, or the hint), and only ever taller (HF._selH), so
--- a check never moves the list. Nothing checked: the hint alone in it. Checked: on its left how
--- many groups (`ctx.notShown` of them hidden) and their worth here (GC.Hoard.Selection), on its
--- right their Store and Take out, each tooltip saying what it moves, and the clear button; or the
--- buttons on a line of their own where the words would have too little room. While its run goes,
--- Stop where the press was and the cast bar in the worth's line. Answers the room's height, 0
--- with no group.
function HL.PaintSelection(groups, ctx, head, bottom)
  local bar = frame.selection
  if #groups == 0 then
    bar:Hide()
    return 0
  end
  local sel = GC.Hoard.Selection(groups, ctx.selected, ctx.valueOf)
  local any = sel.groups > 0
  local bankName = U.bankName(ctx.bankType)
  local running = HL.PaintPair({ { bar.store, sel.toBank, GC.L["Store"], moveNote(sel.toBank, true, bankName) },
    { bar.take, sel.toBags, GC.L["Take out"], moveNote(sel.toBags, false, bankName) } }, ctx.runId, ctx.writable,
    ctx.run)
  local storeW = labelMove(bar.store, GC.L["Store"], running == bar.store)
  local takeW = labelMove(bar.take, GC.L["Take out"], running == bar.take)
  local rightW = storeW + L.SEL_GAP + takeW + L.SEL_GAP + L.SEL_BTN
  local textW = head - 3 * L.SEL_PAD - rightW
  local twoLines = textW < L.SEL_TEXT_MIN
  if twoLines then textW = head - 2 * L.SEL_PAD end

  -- The room, from the most each line can say: every group checked and as many hidden, their whole
  -- worth or the widest worth under a gold, the cast bar's words; and the hint across the bar.
  local every = {}
  for _, group in ipairs(groups) do every[group.key] = true end
  local most = GC.Hoard.Selection(groups, every, ctx.valueOf)
  bar.title:SetWidth(textW)
  setText(bar.title, selectedText(most.groups, most.groups))
  local titleH = math.ceil(heightOf(bar.title, 13))
  local subH = U.tallest(bar.sub, { worthLine(most.worth), worthLine(9999) }, textW)
  local lowerH = math.max(subH, HL.LineCastHeight(bar.cast, ctx.castLabels, textW))
  local textH = titleH + 2 + lowerH
  local plateH = 2 * L.SEL_PAD + (twoLines and (textH + L.SEL_GAP + L.SEL_BTN) or math.max(textH, L.SEL_BTN))
  bar.hint:SetWidth(head - 2 * L.SEL_PAD)
  setText(bar.hint, GC.L["Tick groups to move several at once"])
  local hintH = math.ceil(heightOf(bar.hint, 12))
  local height = math.max(HF._selH or 0, plateH, hintH + 2 * L.SEL_PAD)
  HF._selH = height

  bar:ClearAllPoints()
  bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", L.PAD, bottom)
  bar:SetSize(head, height)
  bar.hint:ClearAllPoints()
  bar.hint:SetPoint("TOPLEFT", bar, "TOPLEFT", L.SEL_PAD, -math.floor((height - hintH) / 2))
  bar.hint:SetShown(not any)
  for _, part in ipairs({ bar.bg, bar.ring, bar.title, bar.clear }) do part:SetShown(any) end
  if any then
    setText(bar.title, selectedText(sel.groups, ctx.notShown or 0))
    setText(bar.sub, worthLine(sel.worth))
    local textTop = twoLines and L.SEL_PAD or math.floor((height - textH) / 2)
    bar.title:ClearAllPoints()
    bar.title:SetPoint("TOPLEFT", bar, "TOPLEFT", L.SEL_PAD, -textTop)
    local lowerY = textTop + titleH + 2
    bar.sub:ClearAllPoints()
    bar.sub:SetPoint("TOPLEFT", bar, "TOPLEFT", L.SEL_PAD, -lowerY)
    bar.sub:SetShown(not running)
    if running then HL.PaintLineCast(bar.cast, ctx.run, bar, L.SEL_PAD, lowerY, textW) else HL.HideCast(bar.cast) end
    local buttonY = twoLines and (height - L.SEL_PAD - L.SEL_BTN) or math.floor((height - L.SEL_BTN) / 2)
    local x = head - L.SEL_PAD - rightW
    bar.store:ClearAllPoints()
    bar.store:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -buttonY)
    bar.take:ClearAllPoints()
    bar.take:SetPoint("TOPLEFT", bar, "TOPLEFT", x + storeW + L.SEL_GAP, -buttonY)
    bar.clear:ClearAllPoints()
    bar.clear:SetPoint("TOPLEFT", bar, "TOPLEFT", head - L.SEL_PAD - L.SEL_BTN, -buttonY)
  else
    for _, part in ipairs({ bar.sub, bar.store, bar.take }) do part:Hide() end
    HL.HideCast(bar.cast)
  end
  -- Shown again, or the hint and the bar, or its worth's line and the cast bar, trading places:
  -- redrawn whole.
  local wasUp = bar:IsShown()
  bar:Show()
  if not wasUp or any ~= (bar.any == true) or (running ~= nil) ~= (bar.ran == true) then U.restamp(frame) end
  bar.any, bar.ran = any, running ~= nil
  return height
end

-- ---------------------------------------------------------------------------------------------
-- The search row
-- ---------------------------------------------------------------------------------------------

-- The filter's and the sort's clicks redraw the list from what the window last read, so a keep
-- count asked from a row goes (HF.ui.closeKeep); the window may take its new height.
local function onFilterClick(side)
  U.closeKeep()
  HF._filter = side.filter
  HF.Refresh(false, true)
end

local function onSortClick()
  U.closeKeep()
  HF._sort = HF._sort == "name" and "value" or "name"
  HF.Refresh(false, true)
end

-- The search row, fixed in the window over the list (the scroll), as the board draws it: the BUY
-- tab's search box (UI/BuyFrame.lua's tools row: the kit's well, an edit box in the mono face, the
-- hint while it is empty and not typed in), with the kit's magnifier at its left; the filter, a
-- switch as the bank switch is built, on its sunken track, the side chosen in the kit's active
-- gold; the sort, a quiet button with the kit's caret.
local function buildSearch()
  local T = GC.Theme
  local row = CreateFrame("Frame", nil, frame)
  local well = CreateFrame("Frame", nil, row)
  well:SetHeight(L.WELL_H)
  local wc = T.color.bg or T.color.panel
  local fill = T.SlicedTexture(well, "BACKGROUND", T.MEDIA .. "plaque.png", { wc[1], wc[2], wc[3], 1 }, T.SLICE.plaque)
  fill:SetAllPoints(well)
  T.SlicedTexture(well, "BORDER", T.MEDIA .. "plaque_ring.png", { 1, 1, 1, 0.12 }, T.SLICE.plaque):SetAllPoints(well)
  well.icon = well:CreateTexture(nil, "ARTWORK")
  well.icon:SetSize(L.WELL_ICON, L.WELL_ICON)
  well.icon:SetPoint("LEFT", well, "LEFT", L.WELL_PAD, 0)
  T.SetIcon(well.icon, "search", T.color.fgDim)
  local textX = L.WELL_PAD + L.WELL_ICON + 5
  local box = CreateFrame("EditBox", nil, well)
  box:SetAutoFocus(false)
  box:SetPoint("TOPLEFT", well, "TOPLEFT", textX, -2)
  box:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -L.WELL_PAD, 2)
  -- Guarded for busted; in the client a bare EditBox with no font draws no text at all.
  if box.SetFont then
    box:SetFont(T.FONT_UI, 11 * T.Scale(), "")
    box:SetTextColor(T.color.fg[1], T.color.fg[2], T.color.fg[3], 1)
    T.OnRescale(function(scale) box:SetFont(T.FONT_UI, 11 * scale, "") end)
  end
  local hint = track(frame, T.Num(well, 10))
  hint:SetJustifyH("LEFT")
  hint:SetWordWrap(false)
  hint:SetPoint("LEFT", well, "LEFT", textX, 0)
  colour(hint, T.color.fgDim)
  local function applyHint()
    hint:SetShown((box:GetText() or "") == "" and not box:HasFocus())
  end
  -- What is typed, trimmed, narrows the rows as it is typed (Core/Hoard.lua's Rows, `query`): each
  -- keystroke redraws the list from what the window last read, and reads no slot.
  box:SetScript("OnTextChanged", function(self, byUser)
    HF._query = (self:GetText() or ""):match("^%s*(.-)%s*$")
    applyHint()
    if byUser then
      U.closeKeep()
      HF.Refresh(false, true)
    end
  end)
  box:SetScript("OnEditFocusGained", applyHint)
  box:SetScript("OnEditFocusLost", applyHint)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
    U.closeKeep()
    HF.Refresh(false, true)
  end)
  row.well, row.box, row.hint, row.textX, row.applyHint = well, box, hint, textX, applyHint

  row.filter = U.newSwitch(row, "filter", { "move", "all" }, onFilterClick)
  -- Quiet, as Store all and Take all out are.
  local sort = T.Button(row, U.QUIET.variant, "badge")
  sort:SetHeight(L.SORT_H)
  sort:SetRing(U.QUIET.ring)
  sort:SetScript("OnClick", onSortClick)
  track(frame, sort.text)
  row.sort = sort
  row:Hide()
  frame.search = row
end

--- The search row at `x`, `y` in the window, `inner` wide (the list's): the search box, the filter
--- with every group counted (`total`) and those that can move here (`toMove`), and the sort, on one
--- line; or the box on a line of its own and the filter with the sort under it where they do not
--- fit. Every part as wide as the most it can say, so a click or a count that changes moves
--- nothing. Answers its height.
function HL.PaintSearch(x, y, inner, total, toMove)
  local s = frame.search
  local words = { move = GC.L["To move here %d"], all = GC.L["All %d"] }
  local sides, pad = s.filter.sides, L.SEG_PAD
  for _, side in ipairs(sides) do
    side:SetLabel(words[side.filter]:format(total))
    side:FitLabels({ side.label }, 0)
    side:SetLabel(words[side.filter]:format(side.filter == "move" and toMove or total))
    local chosen = side.filter == HF._filter
    side:SetVariant(chosen and "active" or "segment")
    if not chosen then colour(side.text, K.text2) end
  end
  sides[1]:ClearAllPoints()
  sides[1]:SetPoint("TOPLEFT", s.filter, "TOPLEFT", pad, -pad)
  sides[2]:ClearAllPoints()
  sides[2]:SetPoint("LEFT", sides[1], "RIGHT", pad, 0)
  local filterW, filterH = sides[1]:GetWidth() + sides[2]:GetWidth() + 3 * pad, L.SEG_H + 2 * pad
  s.filter:SetSize(filterW, filterH)

  local byValue, byName = GC.L["By value"] .. " ▼", GC.L["By name"] .. " ▼"
  s.sort:SetLabel(HF._sort == "name" and byName or byValue)
  s.sort:FitLabels({ byValue, byName }, 0)
  colour(s.sort.text, U.QUIET.textColor)
  local sortW = s.sort:GetWidth()

  setText(s.hint, GC.L["Search"])
  s.applyHint()
  local gap = L.TOOL_GAP
  local leastW = s.textX + math.ceil(s.hint:GetStringWidth() or 0) + L.WELL_PAD
  local lineH = math.max(L.WELL_H, filterH, L.SORT_H)
  local height
  local function put(widget, left, top, h)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", s, "TOPLEFT", left, -(top + math.floor((lineH - h) / 2)))
  end
  if leastW + gap + filterW + gap + sortW <= inner then
    local wellW = inner - filterW - sortW - 2 * gap
    s.well:SetWidth(wellW)
    put(s.well, 0, 0, L.WELL_H)
    put(s.filter, wellW + gap, 0, filterH)
    put(s.sort, inner - sortW, 0, L.SORT_H)
    height = lineH
  else
    s.well:SetWidth(inner)
    put(s.well, 0, 0, L.WELL_H)
    local second = lineH + gap
    put(s.filter, 0, second, filterH)
    if filterW + gap + sortW <= inner then
      put(s.sort, inner - sortW, second, L.SORT_H)
      height = second + lineH
    else
      put(s.sort, 0, second + lineH + gap, L.SORT_H)
      height = second + 2 * lineH + gap
    end
  end
  s:ClearAllPoints()
  s:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
  s:SetSize(inner, height)
  s:Show()
  return height
end

--- Under SEARCH_MIN_GROUPS groups, or with no followed group: no search row, and its box keeps no
--- keyboard.
function HL.HideSearch()
  if not (frame and frame.search) then return end
  frame.search:Hide()
  frame.search.box:ClearFocus()
end

--- The search box lets go of the keyboard (the window hides, or closes to its handle).
function HL.Blur()
  if frame and frame.search then frame.search.box:ClearFocus() end
end

--- A new visit, or the bank closed: the search box is emptied and lets go of the keyboard.
function HL.Reset()
  if not (frame and frame.search) then return end
  frame.search.box:SetText("")
  frame.search.box:ClearFocus()
end

--- Builds the search row, the selection bar and Store all's cast bar in the window (`f`, as
--- UI/HoardFrame.lua's build made it), once.
function HL.Build(f)
  frame = f
  buildSearch()
  buildSelection()
  frame.cast = HL.NewCast(frame.content, frame, 9, true)
end
