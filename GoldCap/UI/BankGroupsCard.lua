local _, GC = ...

-- At a bank: bank by group. Beside the bank window (beside the carry list, UI/BankRoute.lua, when
-- that shows), the groups the player follows on goldcap.gg that have items in the bags or the
-- Warband Bank, each with how many are where, To bank and To bags, how many of each item it keeps
-- in the bags (GC.db.bankKeep, Core/BankGroups.lua), and which stacks stay in the bags and why
-- (still refundable, or the Warband Bank does not take them). Which stack a press moves is
-- Core/BankGroups.lua's Plan; an item's group is Core/GroupRules.lua's. With no followed group there
-- is no card at all: it is not built and no slot is read for it.
--
-- One stack a press, moved inside the player's own click through the bank route's MoveStack,
-- whose guards apply: the bank is the window, the slot still holds the stack, unlocked, and the
-- Warband Bank may take it (spec/bank_route_spec.lua audits the call sites). The button names the
-- next stack as soon as a press has sent one, and a stack sent is offered again only if the bags
-- have not shown it moved within the route's SETTLE_SECONDS.
--
-- Pressed again and again in one spot, so nothing on the card moves between two presses: each
-- button has its own row, kept when its list is empty (it then says so and is disabled, by the
-- repaint after its own last press); the card's width is set for the widest label a press can
-- bring, and the counts line keeps room for the most it can say. The card has its own column,
-- beside the carry list, so that list growing or emptying does not move it either.
--
-- Wired through the bank route's own handlers, which Core/Init.lua's event frame calls: the card
-- hooks them as it loads (after UI/BankRoute.lua in GoldCap.toc). Retail only: GoldCap_Camelot.toc
-- loads none of the bank files.
GC.BankGroupsCard = {}
local C = GC.BankGroupsCard

local LAYOUT = { WIDTH = 240, PAD = 10, GAP = 4, X = 4, LINE_GAP = 2, BLOCK_GAP = 12, BUTTON_H = 22,
  KEEP_H = 18, BUTTON_MIN_W = 80 }
-- The backpack, the four bag slots and the reagent bag: herbs, ore and cloth go to the reagent bag.
local BAGS = { 0, 1, 2, 3, 4, 5 }

C._blocks = {}
-- The stacks a press has sent, "bag:slot" -> { itemID, count } as the slot held them, until the
-- slot shows the move or the settle timer gives up on it.
C._moving = {}
-- While the bank is open: the card's width, which only grows, and whether the carry list has shown
-- (the card then keeps the column beside it until the bank closes).
C._width = nil
C._besideRoute = false
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
--- a column of its own, which the carry list's height never moves.
function C._Place()
  local route, bank = GC.BankRoute._frame, _G.BankFrame
  if isUp(route) then C._besideRoute = true end
  if not frame then return end
  frame:ClearAllPoints()
  if C._besideRoute and route then
    frame:SetPoint("TOPLEFT", route, "TOPRIGHT", LAYOUT.X, 0)
  elseif isUp(bank) then
    frame:SetPoint("TOPLEFT", bank, "TOPRIGHT", LAYOUT.X, 0)
  else
    frame:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
  end
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
-- stack is the one the button names; the button is repainted only after the call.
local function onMoveClick(button)
  local stack = button.stack
  if not stack then return end
  if GC.BankRoute.MoveStack(stack, button.into) then
    C._moving[stack.bag .. ":" .. stack.slot] = { itemID = stack.itemID, count = stack.count }
    settleSeq = settleSeq + 1
    local token = settleSeq
    if C_Timer and C_Timer.After then
      C_Timer.After(GC.BankRoute.SETTLE_SECONDS, function() C._Settle(token) end)
    end
  end
  C.Refresh()
end

-- The keep count, asked in the kit's popup (UI/BuyCapEditor.lua) and saved for the account.
local function askKeep(button)
  local name = button.group
  if not name then return end
  GC.BuyCapEditor.Open(button, {
    title = GC.L["How many of each item in %s to keep in your bags?"]:format(name),
    text = tostring(GC.BankGroups.KeepFor(GC.db, name)),
    read = function(text) return GC.CraftQueue.ParseCount(text, true) end,
    invalid = GC.L["Type a whole number"],
    setLabel = GC.L["Save"],
    onCommit = function(n)
      GC.BankGroups.SetKeep(GC.db, name, n)
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

local function build()
  local T = GC.Theme
  frame = T.Card(UIParent, T.color.panel, T.color.border, true)
  frame:SetWidth(LAYOUT.WIDTH)
  frame:EnableMouse(true)
  frame.title = wrappingLabel(frame, 12, T.color.gold)
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
  C._frame = frame
end

local function moveButton(parent, variant, into)
  local button = GC.Theme.Button(parent, variant, "plaque")
  button:SetHeight(LAYOUT.BUTTON_H)
  button.into = into
  button:SetScript("OnClick", onMoveClick)
  return button
end

-- One group: its name, how many are where, the keep count, To bank and To bags.
local function blockAt(i)
  local block = C._blocks[i]
  if block then return block end
  local T = GC.Theme
  block = CreateFrame("Frame", nil, frame)
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

-- One line a stack that stays in the bags, per item and reason (Core/BankGroups.lua's `stays`).
local function paintStays(block, stays)
  for i, entry in ipairs(stays) do
    local fs = block.stays[i]
    if not fs then
      fs = wrappingLabel(block, 10, GC.Theme.color.fgDim)
      block.stays[i] = fs
    end
    local name = itemName(entry)
    local why = entry.why == "refund" and GC.L["Stays in bags: %s ×%d, can still be refunded"]
      or GC.L["Stays in bags: %s ×%d, the Warband Bank does not take it"]
    fs:SetText(why:format(name, entry.count))
    fs:Show()
  end
  for i = #stays + 1, #block.stays do block.stays[i]:Hide() end
end

-- Paints a block's words and buttons; answers the widest button.
local function paintBlock(block, group, writable)
  block.name:SetText(group.name)
  local counts = GC.L["%d in bags, %d in the Warband Bank"]
  block.counts:SetText(counts:format(group.inBags, group.inBank))
  -- A move keeps the group's total, so neither number can grow longer than it.
  local total = group.inBags + group.inBank
  block.countsMost = counts:format(total, total)
  local widest = 0
  block.keep.group = group.name
  if writable then
    block.keep:SetLabel(GC.L["Keep in bags: %d of each"]:format(group.keep))
    block.keep:Show()
    widest = fitButton(block.keep)
  else
    block.keep:Hide()
  end
  widest = math.max(widest, paintMove(block.toBank, group, group.toBank, GC.L["To bank: %s ×%d (%d left)"],
    GC.L["To bank: nothing to move"]))
  widest = math.max(widest, paintMove(block.toBags, group, group.toBags, GC.L["To bags: %s ×%d (%d left)"],
    GC.L["To bags: nothing to move"]))
  paintStays(block, group.stays)
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

-- Lays a block out at the card's inner width, top to bottom; answers its height. The keep, To bank
-- and To bags rows keep their place whether or not their button shows.
local function layoutBlock(block, inner)
  block:SetWidth(inner)
  block.name:SetWidth(inner)
  block.counts:SetWidth(inner)
  local y = heightOf(block.name, 12) + LAYOUT.LINE_GAP
  block.counts:ClearAllPoints()
  block.counts:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -y)
  y = y + countsHeight(block.counts, block.countsMost)
  for _, button in ipairs({ block.keep, block.toBank, block.toBags }) do
    y = y + LAYOUT.GAP
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -y)
    y = y + (button == block.keep and LAYOUT.KEEP_H or LAYOUT.BUTTON_H)
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

-- The card's title, then the blocks, at the card's width.
local function paint(groups)
  local writable = GC.BankGroups.Writable(GC.db)
  local widest = 0
  for i, group in ipairs(groups) do
    widest = math.max(widest, paintBlock(blockAt(i), group, writable))
  end
  for i = #groups + 1, #C._blocks do C._blocks[i]:Hide() end
  -- Only ever wider while the bank is open: a narrower card would wrap its lines anew.
  local width = math.max(LAYOUT.WIDTH, widest + 2 * LAYOUT.PAD, C._width or 0)
  C._width = width
  local inner = width - 2 * LAYOUT.PAD
  frame:SetWidth(width)
  frame.title:SetWidth(inner)
  frame.title:SetText(GC.L["GoldCap: your groups"])
  local y = LAYOUT.PAD + heightOf(frame.title, 12) + LAYOUT.GAP * 2
  for i, block in ipairs(C._blocks) do
    if i > #groups then break end
    if i > 1 then y = y + LAYOUT.BLOCK_GAP end
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -y)
    block:Show()
    y = y + layoutBlock(block, inner)
  end
  frame:SetHeight(math.ceil(y + LAYOUT.PAD))
  C._Place()
  frame:Show()
end

--- Reads the bags and the Warband Bank again and paints the card, or hides it: with the bank
--- closed or not the window, the Warband Bank out of reach or without a tab, with no followed
--- group (then nothing is built and no slot is read), and when no followed group has an item here.
function C.Refresh()
  if not (GC.BankRoute.CanMove() and GC.GroupRules.HasGroups()) then return hide() end
  pruneMoving()
  local groupOf = GC.GroupRules.GroupOf
  local groups = GC.BankGroups.Plan(GC.BankRoute.ReadStacks(BAGS, false, groupOf),
    GC.BankRoute.ReadStacks(GC.BankRoute.BankTabs(), true, groupOf), {
      groupOf = groupOf,
      keepFor = function(name) return GC.BankGroups.KeepFor(GC.db, name) end,
      moving = C._moving,
    })
  if #groups == 0 then return hide() end
  if not frame then build() end
  paint(groups)
end

-- The route has painted already (the card's hooks run after its handlers): the carry list's
-- column is known.
function C.OnBankOpened()
  C._moving, C._width, C._besideRoute = {}, nil, isUp(GC.BankRoute._frame) and true or false
  C.Refresh()
end

function C.OnBankClosed()
  C._moving, C._width, C._besideRoute = {}, nil, false
  hide()
end

-- BAG_UPDATE_DELAYED, and a run of Warband Bank slot changes (the route repaints once after it).
function C.OnBagsChanged()
  if GC.BankRoute._open then C.Refresh() end
end

-- The route's handlers are what Core/Init.lua calls on the bank events; the card follows each, and
-- is placed again after every repaint of the carry list, which shows, hides and grows by itself.
if hooksecurefunc and GC.BankRoute then
  hooksecurefunc(GC.BankRoute, "OnBankOpened", C.OnBankOpened)
  hooksecurefunc(GC.BankRoute, "OnBankClosed", C.OnBankClosed)
  hooksecurefunc(GC.BankRoute, "OnBagsChanged", C.OnBagsChanged)
  hooksecurefunc(GC.BankRoute, "Refresh", C._Place)
end
