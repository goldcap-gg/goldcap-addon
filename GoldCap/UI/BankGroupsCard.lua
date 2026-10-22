local _, GC = ...

-- At a bank: bank by group. Beside the bank window (under the carry list, UI/BankRoute.lua, when
-- that shows), the groups the player follows on goldcap.gg that have items in the bags or the
-- Warband Bank, each with how many are where, To bank and To bags, how many of each item it keeps
-- in the bags (GC.db.bankKeep, Core/BankGroups.lua), and which stacks stay in the bags and why
-- (still refundable, or the Warband Bank does not take them). Which stack a press moves is
-- Core/BankGroups.lua's Plan; an item's group is Core/GroupRules.lua's. With no followed group there
-- is no card at all: it is not built and no slot is read for it.
--
-- One stack a press, moved inside the player's own click through the bank route's MoveStack,
-- whose guards apply: the bank is the window, the slot still holds the stack, unlocked, and the
-- Warband Bank may take it (spec/bank_route_spec.lua audits the call sites). The button is never
-- put to sleep: it names the next stack as soon as a press has sent one, and a stack sent is
-- offered again only if the bags have not shown it moved within the route's SETTLE_SECONDS.
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
local frame
local settleSeq = 0

local function isUp(widget)
  return type(widget) == "table" and widget.IsShown and widget:IsShown()
end

local function heightOf(fs, fallback)
  local h = fs.GetStringHeight and fs:GetStringHeight()
  return type(h) == "number" and h or fallback
end

--- Under the carry list when it shows, else beside the bank window.
function C._Place()
  if not frame then return end
  frame:ClearAllPoints()
  local route, bank = GC.BankRoute._frame, _G.BankFrame
  if isUp(route) then
    frame:SetPoint("TOPLEFT", route, "BOTTOMLEFT", 0, -LAYOUT.GAP)
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

-- What the next press moves and how many presses are left, or nothing to press.
local function paintMove(button, stacks, format)
  local stack = stacks[1]
  button.stack = stack
  if not stack then
    button:Hide()
    return 0
  end
  local name = (stack.name or ("#" .. tostring(stack.itemID))) .. GC.Theme.QualityMarkup(stack.itemID, 12)
  button:SetLabel(format:format(name, stack.count, #stacks))
  button:Show()
  return fitButton(button)
end

-- One line a stack that stays in the bags, per item and reason (Core/BankGroups.lua's `stays`).
local function paintStays(block, stays)
  for i, entry in ipairs(stays) do
    local fs = block.stays[i]
    if not fs then
      fs = wrappingLabel(block, 10, GC.Theme.color.fgDim)
      block.stays[i] = fs
    end
    local name = (entry.name or ("#" .. tostring(entry.itemID))) .. GC.Theme.QualityMarkup(entry.itemID, 12)
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
  block.counts:SetText(GC.L["%d in bags, %d in the Warband Bank"]:format(group.inBags, group.inBank))
  local widest = 0
  block.keep.group = group.name
  if writable then
    block.keep:SetLabel(GC.L["Keep in bags: %d of each"]:format(group.keep))
    block.keep:Show()
    widest = fitButton(block.keep)
  else
    block.keep:Hide()
  end
  widest = math.max(widest, paintMove(block.toBank, group.toBank, GC.L["To bank: %s ×%d (%d left)"]))
  widest = math.max(widest, paintMove(block.toBags, group.toBags, GC.L["To bags: %s ×%d (%d left)"]))
  paintStays(block, group.stays)
  return widest
end

-- Lays a block out at the card's inner width, top to bottom; answers its height.
local function layoutBlock(block, inner)
  block:SetWidth(inner)
  block.name:SetWidth(inner)
  block.counts:SetWidth(inner)
  local y = heightOf(block.name, 12) + LAYOUT.LINE_GAP
  block.counts:ClearAllPoints()
  block.counts:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -y)
  y = y + heightOf(block.counts, 10)
  for _, button in ipairs({ block.keep, block.toBank, block.toBags }) do
    if button:IsShown() then
      y = y + LAYOUT.GAP
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -y)
      y = y + (button == block.keep and LAYOUT.KEEP_H or LAYOUT.BUTTON_H)
    end
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
  local width = math.max(LAYOUT.WIDTH, widest + 2 * LAYOUT.PAD)
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

function C.OnBankOpened()
  C._moving = {}
  C.Refresh()
end

function C.OnBankClosed()
  C._moving = {}
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
