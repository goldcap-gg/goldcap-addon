local _, GC = ...

-- At a bank: bank by group. Beside the bank window (beside the carry list, UI/BankRoute.lua, when
-- that shows), the groups the player follows on goldcap.gg that have items in the bags or the bank
-- the card works with, each with how many are where, To bank and To bags, how many of each item it
-- keeps in the bags (GC.db.bankKeep, Core/BankGroups.lua, by the group's key), and which stacks
-- stay in the bags and why (the bank does not take them, or, for the Warband Bank, they are still
-- refundable). Which stack a press moves is Core/BankGroups.lua's Plan; an item's group is
-- Core/GroupRules.lua's. With no followed group there is no card at all: it is not built and no
-- slot is read for it.
--
-- Which bank: the character's own or the Warband Bank, a two-way choice under the title named as
-- the bank window's tabs name them. At each open it starts on the bank the window shows
-- (GC.BankRoute.ShownBankType), and it goes along when the window comes to show the other bank (the
-- player clicks its tab: the post-hook on BankPanel's Reset at the end of this file). A click on
-- the card's choice sets it until then or until the bank closes: a bag addon such as Bagnon keeps
-- Blizzard's hidden window on the character's bank for the whole visit, and the choice is how its
-- player reaches the Warband Bank. A bank with no tab bought, or out of reach at this banker, is
-- a disabled side, and the card works with the other. The counts, the plan and every move come
-- from the bank chosen. The carry list stays with the Warband Bank whatever is chosen.
--
-- One stack a press, moved inside the player's own click through the bank route's MoveStack,
-- whose guards apply: the bank is the window, no spell waits for an item target and the cursor is
-- empty, the slot still holds the stack, unlocked, and the bank may take it
-- (spec/bank_route_spec.lua audits the call sites). The button names the next
-- stack as soon as a press has sent one, and a stack sent is offered again only if the bags have
-- not shown it moved within the route's SETTLE_SECONDS.
--
-- Pressed again and again in one spot, so nothing on the card moves between two presses: each
-- button has its own row, kept when its list is empty (it then says so and is disabled, by the
-- repaint after its own last press); the card's width is set for the widest label a press can
-- bring, and the counts line keeps room for the most it can say. The card has its own column,
-- beside the carry list, so that list growing or emptying does not move it either.
--
-- On the screen with any number of groups: each group is a compact block (the keep count a badge
-- on its name line), the groups with nothing to move and nothing to say (all they have here kept in
-- the bags by their keep count) fold into one line that opens them, and the
-- card is clamped to the screen, no taller than the room under its top, with the rest in the kit's
-- scroll. A group shown as a block keeps it until the bank closes, so a press never folds the
-- block under the cursor.
--
-- Wired through the bank route's own handlers, which Core/Init.lua's event frame calls: the card
-- hooks them as it loads (after UI/BankRoute.lua in GoldCap.toc), and Blizzard's bank panel's
-- Reset. Retail only: GoldCap_Camelot.toc loads none of the bank files.
GC.BankGroupsCard = {}
local C = GC.BankGroupsCard

-- BAR: the scroll's bar hangs 6px right of the scroll frame and is 16px wide
-- (Blizzard_SharedXML/SecureScrollTemplates.xml), so the scroll frame stops 22px short of the
-- card's right edge and the bar lands in that margin, as in UI/SettingsFrame.lua. SCREEN_GAP: what
-- the card leaves free under it, above the action bars.
-- SEG_PAD, SEG_MIN: the bank choice's track around its two sides, and a side's least width, as the
-- crafting panel's view switch has them (UI/CraftPanel.lua).
local LAYOUT = { WIDTH = 260, PAD = 10, GAP = 4, X = 4, LINE_GAP = 2, BLOCK_GAP = 8, BUTTON_H = 22,
  KEEP_H = 18, BUTTON_MIN_W = 80, NAME_MIN_W = 80, BAR = 22, SCREEN_GAP = 80, MIN_H = 160, SEG_PAD = 2,
  SEG_MIN = 60 }
-- The backpack, the four bag slots and the reagent bag: herbs, ore and cloth go to the reagent bag.
local BAGS = { 0, 1, 2, 3, 4, 5 }

C._blocks = {}
-- The stacks a press has sent, "bag:slot" -> { itemID, count } as the slot held them, until the
-- slot shows the move or the settle timer gives up on it.
C._moving = {}
-- While the bank is open: the bank the card works with (Enum.BankType), as of its last paint, and
-- the bank the window showed then (the card goes along only when that changes); the card's width,
-- which only grows; whether the carry list has shown (the card then keeps the column beside it
-- until the bank closes); the groups shown as a block (by key), which stay one; and whether the
-- folded groups are open.
C._bankType = nil
C._seenType = nil
C._width = nil
C._besideRoute = false
C._shown = {}
C._unfolded = false
local frame
local settleSeq = 0

local function isUp(widget)
  return type(widget) == "table" and widget.IsShown and widget:IsShown()
end

local function heightOf(fs, fallback)
  local h = fs.GetStringHeight and fs:GetStringHeight()
  return type(h) == "number" and h or fallback
end

--- Beside the carry list once it has shown in this visit to the bank, else beside the bank window:
--- a column of its own, which the carry list's height never moves. Answers the frame whose top
--- the card's top is level with, or nil.
function C._Place()
  local route, bank = GC.BankRoute._frame, _G.BankFrame
  if isUp(route) then C._besideRoute = true end
  if not frame then return nil end
  frame:ClearAllPoints()
  if C._besideRoute and route then
    frame:SetPoint("TOPLEFT", route, "TOPRIGHT", LAYOUT.X, 0)
    return route
  elseif isUp(bank) then
    frame:SetPoint("TOPLEFT", bank, "TOPRIGHT", GC.BankRoute.BesideBankX(bank, LAYOUT.X), 0)
    return bank
  end
  frame:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
  return nil
end

-- The most the card may be tall: the room from its top (the top of what it stands beside) down to
-- SCREEN_GAP above the screen's bottom, or the screen less twice that when it stands centred.
-- Unbounded where the client gives no measure.
local function maxHeight(beside)
  local top = beside and beside.GetTop and beside:GetTop()
  if type(top) == "number" then return math.max(LAYOUT.MIN_H, top - LAYOUT.SCREEN_GAP) end
  local screen = UIParent and UIParent.GetHeight and UIParent:GetHeight()
  if type(screen) == "number" and screen > 0 then
    return math.max(LAYOUT.MIN_H, screen - 2 * LAYOUT.SCREEN_GAP)
  end
  return math.huge
end

-- Forgets a sent stack once its slot no longer holds it as it was: moved, merged, or emptied.
local function pruneMoving()
  for slotKey, sent in pairs(C._moving) do
    local bag, slot = slotKey:match("^(%-?%d+):(%d+)$")
    local info = C_Container.GetContainerItemInfo(tonumber(bag), tonumber(slot))
    if not (info and info.itemID == sent.itemID and (info.stackCount or 1) == sent.count) then
      C._moving[slotKey] = nil
    end
  end
end

-- Nothing moved in time (a full bank or bags, a slot the server refused): the stacks are offered again.
function C._Settle(token)
  if token ~= settleSeq then return end
  C._moving = {}
  C.Refresh()
end

-- A move button's own click: one stack, through the bank route's MoveStack, inside the click. The
-- stack is the one the button names, and the bank the one the card names; the button is repainted
-- only after the call.
local function onMoveClick(button)
  local stack = button.stack
  if not stack then return end
  if GC.BankRoute.MoveStack(stack, button.into, C._bankType) then
    C._moving[stack.bag .. ":" .. stack.slot] = { itemID = stack.itemID, count = stack.count }
    settleSeq = settleSeq + 1
    local token = settleSeq
    if C_Timer and C_Timer.After then
      C_Timer.After(GC.BankRoute.SETTLE_SECONDS, function() C._Settle(token) end)
    end
  end
  C.Refresh()
end

-- The keep count, asked in the kit's popup (UI/BuyCapEditor.lua) and saved for the account, by the
-- group's key; the question names the group.
local function askKeep(button)
  local key = button.group
  if not key then return end
  GC.BuyCapEditor.Open(button, {
    title = GC.L["How many of each item in %s to keep in your bags?"]:format(button.groupName or key),
    text = tostring(GC.BankGroups.KeepFor(GC.db, key)),
    read = function(text) return GC.CraftQueue.ParseCount(text, true) end,
    invalid = GC.L["Type a whole number"],
    setLabel = GC.L["Save"],
    onCommit = function(n)
      GC.BankGroups.SetKeep(GC.db, key, n)
      C.Refresh()
    end,
  })
end

local function wrappingLabel(parent, size, color)
  local fs = GC.Theme.Label(parent, size)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  fs:SetTextColor(color[1], color[2], color[3])
  return fs
end

-- The fold line's own click: opens or closes the groups with nothing to move.
local function onFoldClick()
  C._unfolded = not C._unfolded
  C.Refresh()
end

-- A side of the bank choice: the card works with that bank until the window comes to show the
-- other one or the bank closes. It moves nothing; a disabled side gets no click.
local function onBankClick(button)
  C._bankType = button.bankType
  C.Refresh()
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

-- The title and the bank choice, then the kit's scroll (UIPanelScrollFrameTemplate under
-- Theme.QuietScrollBar, its bar hidden while everything fits), whose child holds the blocks and the
-- fold line. The choice is the crafting panel's view switch (UI/CraftPanel.lua): a sunken track,
-- the bank chosen lit and the other bare text.
local function build()
  local T = GC.Theme
  frame = T.Card(UIParent, T.color.panel, T.color.border, true)
  frame:SetWidth(LAYOUT.WIDTH)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame.title = wrappingLabel(frame, 12, T.color.gold)
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
  local choice = CreateFrame("Frame", nil, frame)
  choice.track = T.SlicedTexture(choice, "BACKGROUND", T.MEDIA .. "plaque.png", { 0, 0, 0, 0.3 }, 12)
  choice.track:SetAllPoints(choice)
  choice.sides = {}
  for i, bankType in ipairs({ banks() }) do
    local side = T.Button(choice, "segment", "plaque")
    side:SetHeight(LAYOUT.KEEP_H)
    side.bankType = bankType
    side:SetScript("OnClick", onBankClick)
    choice.sides[i] = side
  end
  frame.choice = choice
  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  if T.QuietScrollBar then T.QuietScrollBar(scroll) end
  scroll.scrollBarHideable = true
  if scroll.ScrollBar then scroll.ScrollBar:Hide() end
  frame.content = CreateFrame("Frame", nil, scroll)
  frame.content:SetSize(1, 1)
  scroll:SetScrollChild(frame.content)
  frame.scroll = scroll
  frame.fold = T.Button(frame.content, "ghost", "badge")
  frame.fold:SetHeight(LAYOUT.KEEP_H)
  frame.fold:SetScript("OnClick", onFoldClick)
  C._frame = frame
end

local function moveButton(parent, variant, into)
  local button = GC.Theme.Button(parent, variant, "plaque")
  -- In the scroll, which clips at its edges: a halo would be cut flat along the card's left side.
  button:SetGlow(false)
  button:SetHeight(LAYOUT.BUTTON_H)
  button.into = into
  button:SetScript("OnClick", onMoveClick)
  return button
end

-- One group: its name and keep count, how many are where, To bank and To bags.
local function blockAt(i)
  local block = C._blocks[i]
  if block then return block end
  local T = GC.Theme
  block = CreateFrame("Frame", nil, frame.content)
  block.name = wrappingLabel(block, 11, T.color.fg)
  block.name:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
  block.counts = wrappingLabel(block, 10, T.color.fgDim)
  block.keep = T.Button(block, "ghost", "badge")
  block.keep:SetHeight(LAYOUT.KEEP_H)
  block.keep:SetScript("OnClick", askKeep)
  block.toBank = moveButton(block, "primary", true)
  block.toBags = moveButton(block, "ghost", false)
  block.stays = {}
  C._blocks[i] = block
  return block
end

local function itemName(item)
  return (item.name or ("#" .. tostring(item.itemID))) .. GC.Theme.QualityMarkup(item.itemID, 12)
end

-- The button as wide as its label in the player's language, never narrower than BUTTON_MIN_W: a
-- label is never cut. Answers the width; the card grows to the widest.
local function fitButton(button)
  local fs = button.text
  local width = fs and fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  if type(width) ~= "number" then width = 0 end
  local w = math.max(LAYOUT.BUTTON_MIN_W, math.ceil(width) + 2 * GC.Theme.pad.m)
  button:SetWidth(w)
  return w
end

-- What the next press moves and how many presses are left. With nothing to move the button stays
-- in its row, says so and is disabled: from the start, or by the repaint its own last press makes
-- after its call. Its width is the widest label it can show while the bank is open (each item of
-- the group with its total and the group's stack count, which no press raises), so a press never
-- resizes it; answers that width.
local function paintMove(button, group, stacks, format, done)
  local stack = stacks[1]
  button.stack = stack
  local labels = { done }
  for _, item in ipairs(group.items) do
    labels[#labels + 1] = format:format(itemName(item), item.count, group.stackCount)
  end
  if stack then
    labels[#labels + 1] = format:format(itemName(stack), stack.count, #stacks)
    button:SetLabel(labels[#labels])
    button:Enable()
  else
    button:SetLabel(done)
    button:Disable()
  end
  button:FitLabels(labels, LAYOUT.BUTTON_MIN_W)
  return button:GetWidth()
end

-- The card's words for the bank it works with: the Warband Bank's, else the character's own bank's.
local function bankWords()
  local _, account = banks()
  if C._bankType == account then
    return { counts = GC.L["%d in bags, %d in the Warband Bank"],
      refused = GC.L["Stays in bags: %s ×%d, the Warband Bank does not take it"] }
  end
  return { counts = GC.L["%d in bags, %d in your bank"],
    refused = GC.L["Stays in bags: %s ×%d, your bank does not take it"] }
end

-- The bank choice: each side named and as wide as its name, the bank chosen lit, a bank that
-- cannot be used (`usable[bankType]` false) disabled. The two sides stand side by side and the card
-- grows to hold them, so a name is never cut. Answers the track's width.
local function paintChoice(usable)
  local choice, pad = frame.choice, LAYOUT.SEG_PAD
  for _, side in ipairs(choice.sides) do
    side:SetLabel(bankName(side.bankType))
    side:FitLabels({ side.label }, LAYOUT.SEG_MIN)
    side:SetVariant(side.bankType == C._bankType and "active" or "segment")
    -- Enabled first, so a side disabled again repaints as disabled over its new variant.
    side:Enable()
    if not usable[side.bankType] then side:Disable() end
  end
  local first, second = choice.sides[1], choice.sides[2]
  first:ClearAllPoints()
  first:SetPoint("TOPLEFT", choice, "TOPLEFT", pad, -pad)
  second:ClearAllPoints()
  second:SetPoint("LEFT", first, "RIGHT", pad, 0)
  choice:SetSize(first:GetWidth() + second:GetWidth() + 3 * pad, LAYOUT.KEEP_H + 2 * pad)
  return choice:GetWidth()
end

-- One line a stack that stays in the bags, per item and reason (Core/BankGroups.lua's `stays`).
local function paintStays(block, stays, words)
  for i, entry in ipairs(stays) do
    local fs = block.stays[i]
    if not fs then
      fs = wrappingLabel(block, 10, GC.Theme.color.fgDim)
      block.stays[i] = fs
    end
    local name = itemName(entry)
    local why = entry.why == "refund" and GC.L["Stays in bags: %s ×%d, can still be refunded"] or words.refused
    fs:SetText(why:format(name, entry.count))
    fs:Show()
  end
  for i = #stays + 1, #block.stays do block.stays[i]:Hide() end
end

-- Paints a block's words and buttons; answers the widest button.
local function paintBlock(block, group, writable, words)
  block.name:SetText(group.name)
  local counts = words.counts
  block.counts:SetText(counts:format(group.inBags, group.inBank))
  -- A move keeps the group's total, so neither number can grow longer than it.
  local total = group.inBags + group.inBank
  block.countsMost = counts:format(total, total)
  local widest = 0
  block.keep.group, block.keep.groupName = group.key, group.name
  if writable then
    block.keep:SetLabel(GC.L["Keep in bags: %d of each"]:format(group.keep))
    block.keep:Show()
    -- The name wraps beside the badge, in no less than NAME_MIN_W.
    widest = fitButton(block.keep) + LAYOUT.GAP + LAYOUT.NAME_MIN_W
  else
    block.keep:Hide()
  end
  widest = math.max(widest, paintMove(block.toBank, group, group.toBank, GC.L["To bank: %s ×%d (%d left)"],
    GC.L["To bank: nothing to move"]))
  widest = math.max(widest, paintMove(block.toBags, group, group.toBags, GC.L["To bags: %s ×%d (%d left)"],
    GC.L["To bags: nothing to move"]))
  -- Without the keep counts (a newer GoldCap's), To bank is not offered; its row stays (layoutBlock).
  block.toBank:SetShown(writable)
  paintStays(block, group.stays, words)
  return widest
end

-- The counts line's height: room for the most it can say while the bank is open.
local function countsHeight(counts, most)
  local said = counts:GetText()
  counts:SetText(most)
  local h = heightOf(counts, 10)
  counts:SetText(said)
  return math.max(h, heightOf(counts, 10))
end

-- Lays a block out at the card's inner width, top to bottom: the name with the keep badge at its
-- right, the counts, To bank, To bags, then what stays in the bags. Answers its height. The badge's
-- line and the two move rows keep their place whether or not their button shows.
local function layoutBlock(block, inner)
  block:SetWidth(inner)
  block.keep:ClearAllPoints()
  block.keep:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)
  block.name:SetWidth(block.keep:IsShown() and (inner - block.keep:GetWidth() - LAYOUT.GAP) or inner)
  block.counts:SetWidth(inner)
  local y = math.max(heightOf(block.name, 12), LAYOUT.KEEP_H) + LAYOUT.LINE_GAP
  block.counts:ClearAllPoints()
  block.counts:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -y)
  y = y + countsHeight(block.counts, block.countsMost)
  for _, button in ipairs({ block.toBank, block.toBags }) do
    y = y + LAYOUT.GAP
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -y)
    y = y + LAYOUT.BUTTON_H
  end
  for _, fs in ipairs(block.stays) do
    if fs:IsShown() then
      fs:SetWidth(inner)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -(y + LAYOUT.LINE_GAP))
      y = y + LAYOUT.LINE_GAP + heightOf(fs, 10)
    end
  end
  y = math.ceil(y)
  block:SetHeight(y)
  return y
end

local function hide()
  if frame then frame:Hide() end
end

-- The card: its title and the bank choice, then in the scroll as blocks the groups with something
-- to move or a stack that stays in the bags (and those shown as a block earlier in this visit), the
-- fold line for the others, and, opened, their blocks under it.
local function paint(groups, usable)
  local writable = GC.BankGroups.Writable(GC.db)
  local words = bankWords()
  local open, folded = {}, {}
  for _, group in ipairs(groups) do
    -- A newer GoldCap saved the keep counts, which this one cannot read: To bank would ignore what
    -- the player keeps, so it moves nothing.
    if not writable then group.toBank = {} end
    if C._shown[group.key] or #group.toBank + #group.toBags + #group.stays > 0 then
      C._shown[group.key] = true
      open[#open + 1] = group
    else
      folded[#folded + 1] = group
    end
  end
  local listed = { unpack(open) }
  if C._unfolded then
    for _, group in ipairs(folded) do listed[#listed + 1] = group end
  end
  local widest = paintChoice(usable)
  for i, group in ipairs(listed) do
    widest = math.max(widest, paintBlock(blockAt(i), group, writable, words))
  end
  for i = #listed + 1, #C._blocks do C._blocks[i]:Hide() end
  local fold = frame.fold
  if #folded > 0 then
    fold:SetLabel(GC.L["Groups with nothing to move: %d"]:format(#folded) .. (C._unfolded and " ▲" or " ▼"))
    fold:Show()
    widest = math.max(widest, fitButton(fold))
  else
    fold:Hide()
  end
  -- Only ever wider while the bank is open: a narrower card would wrap its lines anew.
  local width = math.max(LAYOUT.WIDTH, widest + LAYOUT.PAD + LAYOUT.BAR, C._width or 0)
  C._width = width
  local inner = width - LAYOUT.PAD - LAYOUT.BAR
  frame:SetWidth(width)
  frame.title:SetWidth(inner)
  frame.title:SetText(GC.L["GoldCap: your groups"])
  local titleH = heightOf(frame.title, 12)
  frame.choice:ClearAllPoints()
  frame.choice:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -(LAYOUT.PAD + titleH + LAYOUT.LINE_GAP))
  local y = 0
  local function place(i)
    local block = C._blocks[i]
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
    block:Show()
    y = y + layoutBlock(block, inner)
  end
  for i = 1, #open do
    if i > 1 then y = y + LAYOUT.BLOCK_GAP end
    place(i)
  end
  if #folded > 0 then
    if #open > 0 then y = y + LAYOUT.BLOCK_GAP end
    fold:ClearAllPoints()
    fold:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
    y = y + LAYOUT.KEEP_H
    for i = #open + 1, #listed do
      y = y + LAYOUT.BLOCK_GAP
      place(i)
    end
  end
  y = math.ceil(y)
  frame.content:SetSize(inner, y)
  local top = math.ceil(LAYOUT.PAD + titleH + LAYOUT.LINE_GAP + frame.choice:GetHeight() + LAYOUT.GAP * 2)
  local height = math.min(top + y + LAYOUT.PAD, maxHeight(C._Place()))
  frame:SetHeight(height)
  frame.scroll:ClearAllPoints()
  frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -top)
  frame.scroll:SetSize(inner, height - top - LAYOUT.PAD)
  frame:Show()
end

--- Reads the bags and the bank the card works with again and paints the card, or hides it: with no
--- followed group (then nothing is built and no slot is read), with the bank closed or not the
--- window, with neither bank usable here with a tab, and when no followed group has an item here.
function C.Refresh()
  local route, character, account = GC.BankRoute, banks()
  if not (character and account and GC.GroupRules.HasGroups()) then return hide() end
  -- The window shows another bank than at the last paint (it opened, or the player clicked its
  -- other tab): the card goes along. Else the bank stays the one the player chose on the card.
  local shown = route.ShownBankType()
  if shown ~= C._seenType then C._seenType, C._bankType = shown, shown end
  local usable = { [character] = route.CanMove(character), [account] = route.CanMove(account) }
  if not usable[C._bankType] then C._bankType = C._bankType == account and character or account end
  local bankType = C._bankType
  if not usable[bankType] then return hide() end
  pruneMoving()
  local groupOf = GC.GroupRules.GroupOf
  local groups = GC.BankGroups.Plan(GC.BankRoute.ReadStacks(BAGS, false, groupOf, bankType),
    GC.BankRoute.ReadStacks(GC.BankRoute.BankTabs(bankType), true, groupOf, bankType), {
      groupOf = groupOf,
      keepFor = function(key) return GC.BankGroups.KeepFor(GC.db, key) end,
      moving = C._moving,
    })
  if #groups == 0 then return hide() end
  if not frame then build() end
  paint(groups, usable)
end

-- The route has painted already (the card's hooks run after its handlers): the carry list's
-- column is known.
function C.OnBankOpened()
  C._moving, C._width, C._besideRoute = {}, nil, isUp(GC.BankRoute._frame) and true or false
  -- The choice starts again on the bank the window shows.
  C._bankType, C._seenType = nil, nil
  C._shown, C._unfolded = {}, false
  C.Refresh()
end

function C.OnBankClosed()
  C._moving, C._width, C._besideRoute, C._bankType, C._seenType = {}, nil, false, nil, nil
  C._shown, C._unfolded = {}, false
  -- A keep count asked at this bank goes with it.
  for _, block in ipairs(C._blocks) do GC.BuyCapEditor.CloseFor(block.keep) end
  hide()
end

-- BAG_UPDATE_DELAYED, and a run of Warband Bank slot changes (the route repaints once after it).
function C.OnBagsChanged()
  if GC.BankRoute._open then C.Refresh() end
end

-- The bank window shows a bank: as it opens, when the player switches between the character's own
-- bank and the Warband Bank, and when a tab is bought. The card goes along when the bank shown
-- changed (C.Refresh), and a bought tab may enable a side of its choice. Blizzard's
-- panel calls this from inside its own work (the tab click's SetTab, the window's OnShow), so the
-- card repaints on the next frame, once for a run of them, and never inside Blizzard's call.
function C.OnBankShown()
  if not GC.BankRoute._open or C._repaintQueued then return end
  if not (C_Timer and C_Timer.After) then return C.Refresh() end
  C._repaintQueued = true
  C_Timer.After(0, function()
    C._repaintQueued = nil
    C.OnBagsChanged()
  end)
end

-- The route's handlers are what Core/Init.lua calls on the bank events; the card follows each, and
-- is placed again after every repaint of the carry list, which shows, hides and grows by itself.
if hooksecurefunc and GC.BankRoute then
  hooksecurefunc(GC.BankRoute, "OnBankOpened", C.OnBankOpened)
  hooksecurefunc(GC.BankRoute, "OnBankClosed", C.OnBankClosed)
  hooksecurefunc(GC.BankRoute, "OnBagsChanged", C.OnBagsChanged)
  hooksecurefunc(GC.BankRoute, "Refresh", C._Place)
end
-- Blizzard's bank panel (Blizzard_UIPanels_Game's BankFrame.lua, BankPanelMixin) resets as the
-- window opens (its OnShow), when the player clicks the other bank's tab (BankFrame:SetTab, then
-- SetBankType while the panel is shown) and on BANK_TABS_CHANGED for its bank; by the next frame
-- the panel is shown and BankFrame:GetActiveBankType() answers the bank it shows. Not a hook on
-- BankFrame's SetTab: the tab buttons call the function captured at load
-- (TabSystemOwnerMixin:SetTabSystem's GenerateClosure), which a hook on the frame never sees. A
-- post-hook on a call nothing protected goes through; the card only reads and paints.
local bankPanel = _G.BankPanel
if hooksecurefunc and type(bankPanel) == "table" and type(bankPanel.Reset) == "function" then
  hooksecurefunc(bankPanel, "Reset", C.OnBankShown)
end
