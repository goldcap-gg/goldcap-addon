local _, GC = ...

-- At a bank: what to carry between realms through the Warband Bank (ClickUp 869fjhvn9). Beside
-- the bank window, the flips in the bags that sell notably better on another of the player's
-- realms (PUT IN), and the flips in the Warband Bank that sell best on this one (TAKE OUT), each
-- with where, for how much and how soon (Core/SellRoute.lua's CarryPlan, from goldcap.gg's
-- payload). Worked out from what is there, not from a list kept since the purchase: an item bought
-- outside GoldCap, or one whose best realm moved since, is placed right all the same.
--
-- Retail only (GoldCap.toc): goldcap.gg works out where flips sell for retail realms alone, so on
-- WoW: Forever there is nothing to carry. One C_Container.UseContainerItem a
-- click, made by the player's own click (spec/bank_route_spec.lua) and only after checking
-- the bank is the window open and the slot still holds the item: the same call equips a piece of
-- gear when no bank is open, which binds it, and sells it when a vendor is.
--
-- The reader, the move and their guards are shared, and each takes the bank it works with: this
-- list always the Warband Bank (it hands items to another character), the bank by group card
-- (UI/BankGroupsCard.lua) the bank its own choice names, which starts on the one the bank window
-- shows (ShownBankType). The card reads through ReadStacks and moves its stacks through MoveStack.
GC.BankRoute = {}
local P = GC.BankRoute

-- How long a press waits for the bags to show the move before the button is offered again.
P.SETTLE_SECONDS = 3
P._rows = {}
P._headings = {}

local LAYOUT = { WIDTH = 240, PAD = 10, GAP = 4, X = 4, ICON = 24, ICON_GAP = 6, ROW_GAP = 8,
  SECTION_GAP = 12, BUTTON_H = 22, BUTTON_MIN_W = 80 }
-- The backpack and the four bag slots; the reagent bag holds no realm item.
local BAGS = { 0, 1, 2, 3, 4 }

local frame
local pendingSeq = 0

-- How far past the bank window's right edge a panel beside it starts (this list, and the bank by
-- group card): past the tab buttons Blizzard hangs off the bank panel's right edge (BankFrame.lua,
-- BankPanelMixin:RefreshBankTabs, 2 out from it), which covered the left of both (owner,
-- 2026-10-23). Measured from what the panel shows past the edge, plus the tab's border past its
-- button: SpellBook-SkillLineTab is 64 wide at x -3 and drawn to x 38, 4 past the 32-wide button.
-- `gap` alone where nothing sticks out.
local TAB_BORDER = 4
function P.BesideBankX(bank, gap)
  local panel = _G.BankPanel
  local edge = type(bank) == "table" and bank.GetRight and bank:GetRight()
  if not (edge and type(panel) == "table" and panel.GetChildren) then return gap end
  local far = edge
  for _, child in ipairs({ panel:GetChildren() }) do
    local right = child.IsShown and child:IsShown() and child.GetRight and child:GetRight()
    if right and right > far then far = right end
  end
  if far <= edge then return gap end
  return far - edge + TAB_BORDER + gap
end

local function accountBank()
  return Enum and Enum.BankType and Enum.BankType.Account or nil
end

-- The windows a container click feeds instead of the bank, as Blizzard's own right click on a bag
-- item lists them (live Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua,
-- ContainerFrameItemButton_OnClick): a vendor sells the item, the auction house takes it to post,
-- the Azerite respec and the Runeforge take it as theirs, and Blizzard treats the click as a plain
-- use only while none of the guild bank, the mailbox (either tab), a trade, the item upgrade, the
-- Obliterum forge and the keystone slot is open. Most of them load on demand: one that is not
-- loaded is not open.
local OTHER_WINDOWS = { "MerchantFrame", "AuctionHouseFrame", "AzeriteRespecFrame", "RuneforgeFrame",
  "GuildBankFrame", "MailFrame", "TradeFrame", "ItemUpgradeFrame", "ObliterumForgeFrame",
  "ChallengesKeystoneFrame" }

-- The bank is open, `bankType`'s bank can be used here, and none of OTHER_WINDOWS is open.
local function bankIsTheWindow(bankType)
  if not (P._open and bankType ~= nil and C_Bank and C_Bank.CanUseBank) then return false end
  local ok, can = pcall(C_Bank.CanUseBank, bankType)
  if not (ok and can) then return false end
  for _, name in ipairs(OTHER_WINDOWS) do
    local other = _G[name]
    if type(other) == "table" and other.IsShown and other:IsShown() then return false end
  end
  return true
end

local function locationOf(bag, slot)
  if not (ItemLocation and ItemLocation.CreateFromBagAndSlot) then return nil end
  return ItemLocation:CreateFromBagAndSlot(bag, slot)
end

-- A client call's answer, false kept as false (a refusal is an answer), nil when it errors.
local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, answer = pcall(fn, ...)
  if not ok then return nil end
  return answer
end

-- `bankType`'s bank has a tab to put things in: a deposit into none goes nowhere.
local function hasTabs(bankType)
  local tabs = ask(C_Bank.FetchPurchasedBankTabIDs, bankType)
  return type(tabs) == "table" and #tabs > 0
end

-- Why `bankType`'s bank must not take a stack in the bags, or nil when it may. "refund" while it is
-- still refundable and the bank is the Warband Bank: Blizzard asks before a deposit there ends the
-- refund (BankUtil_IsAccountBankDepositRefundable, Blizzard_UIPanels_Game's BankFrame.lua), and
-- GoldCap does not decide that for the player; into the character's own bank Blizzard deposits
-- without asking. Else "refused" when that bank does not take it.
local function staysWhy(loc, bankType)
  if bankType == accountBank() and ask(C_Item.CanBeRefunded, loc) == true then return "refund" end
  if ask(C_Bank.IsItemAllowedInBankType, bankType, loc) == false then return "refused" end
  return nil
end

-- One stack as the bank cards read it, or nil: an empty slot, an item `wanted` does not take, a
-- soulbound one. A Warbound-until-equipped one is marked `wue`, a stack in the bags `bankType`'s
-- bank must not take `stays` (with why, staysWhy above), and one the game holds (on the cursor, or
-- on its way) `locked`.
local function readStack(bag, slot, inBank, wanted, bankType)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not (info and info.itemID and wanted(info.itemID)) then return nil end
  local loc = locationOf(bag, slot)
  if not loc then return nil end
  local wue = ask(C_Item.IsBoundToAccountUntilEquip, loc) == true
  if info.isBound and not wue then return nil end
  return { itemID = info.itemID, bag = bag, slot = slot, count = info.stackCount or 1, name = info.itemName,
    icon = info.iconFileID, ilvl = ask(C_Item.GetCurrentItemLevel, loc), wue = wue or nil,
    stays = (not inBank and staysWhy(loc, bankType)) or nil, locked = info.isLocked or nil }
end

--- Every stack of `bags` whose item `wanted(itemID)` takes, read as readStack reads one; a stack in
--- the bags is marked `stays` against `bankType`'s bank (Enum.BankType), the one it would go into.
function P.ReadStacks(bags, inBank, wanted, bankType)
  local stacks = {}
  for _, bag in ipairs(bags) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local stack = readStack(bag, slot, inBank, wanted, bankType)
      if stack then stacks[#stacks + 1] = stack end
    end
  end
  return stacks
end

--- The tabs of `bankType`'s bank, as bags to read, while the bank is open; none otherwise.
function P.BankTabs(bankType)
  local tabs = P._open and ask(C_Bank.FetchPurchasedBankTabIDs, bankType) or nil
  return type(tabs) == "table" and tabs or {}
end

--- Whether a press can move anything to or from `bankType`'s bank now: the bank is open and is the
--- window, and that bank can be used here and has a tab.
function P.CanMove(bankType)
  return P._open == true and bankIsTheWindow(bankType) and hasTabs(bankType)
end

--- The bank the bank window shows: what Blizzard's own right click on a bag item deposits into
--- (`BankFrame:GetActiveBankType()`, Blizzard_UIPanels_Game's ContainerFrame.lua), the character's
--- own bank or the Warband Bank. The Warband Bank when the window answers neither, which is only
--- while its panel is not shown yet (the first open of the session, before the panel's OnShow). A
--- bag addon such as Bagnon keeps Blizzard's window shown under a hidden parent on the character's
--- bank for the whole visit, so this answers the character's bank all along; the group card has
--- its own choice of bank for that (UI/BankGroupsCard.lua).
function P.ShownBankType()
  local bank, character = _G.BankFrame, Enum and Enum.BankType and Enum.BankType.Character
  local shown = type(bank) == "table" and ask(bank.GetActiveBankType, bank) or nil
  if character ~= nil and shown == character then return character end
  return accountBank()
end

--- What to carry from this bank now (GC.SellRoute.CarryPlan), from the bags and, while the bank is
--- open, the Warband Bank's tabs. A stack in the bags the Warband Bank must not take is left out,
--- unless it is Warbound until equipped: that one is told why it stays.
function P.Plan()
  local function routed(stacks, inBank)
    local out = {}
    for _, stack in ipairs(stacks) do
      if inBank or stack.wue or not stack.stays then out[#out + 1] = stack end
    end
    return out
  end
  local account = accountBank()
  return GC.SellRoute.CarryPlan(routed(P.ReadStacks(BAGS, false, GC.Data.SellSpots, account), false),
    routed(P.ReadStacks(P.BankTabs(account), true, GC.Data.SellSpots, account), true), {
    hereId = GC.SellRoute.HereId(),
    routeFor = GC.SellRoute.ForItem,
    levelFor = GC.Data.FlipLevel,
  })
end

--- The one place the addon moves an item between the bags and a bank: one
--- C_Container.UseContainerItem, made inside the player's own click by the handler that calls this
--- (onCarryClick below, onMoveClick in UI/BankGroupsCard.lua; spec/bank_route_spec.lua audits
--- both). `bankType` (Enum.BankType) is the bank the stack goes into or comes out of; there is no
--- default, so a call that names none moves nothing. The same call equips a piece of gear when no
--- bank is open, which binds it, and sells the item when a vendor is; so first it checks that the
--- bank is the window and that bank can be used here, that the slot still holds the stack's item,
--- unlocked, and, into the bank, that the bank may take it. A spell waiting for an item target, or
--- anything on the cursor, would turn the call into casting that spell on the item
--- (GC.Util.CursorBusy): then it moves nothing. Deposit with (bag, slot, nil, bankType, false), as
--- Blizzard's own right click on a bag item does, withdraw with (tabID, slot). True when the call
--- was made.
function P.MoveStack(stack, into, bankType)
  if not (type(stack) == "table" and bankIsTheWindow(bankType)) then return false end
  if GC.Util.CursorBusy() then return false end
  local info = C_Container.GetContainerItemInfo(stack.bag, stack.slot)
  if not (info and info.itemID == stack.itemID) or info.isLocked then return false end
  if into then
    local loc = locationOf(stack.bag, stack.slot)
    if not loc or staysWhy(loc, bankType) then return false end
    C_Container.UseContainerItem(stack.bag, stack.slot, nil, bankType, false)
  else
    C_Container.UseContainerItem(stack.bag, stack.slot)
  end
  return true
end

-- The carry list's button: moves the row's stack through MoveStack, and only after the call puts
-- the button to sleep: BAG_UPDATE_DELAYED (OnBagsChanged) paints the move.
local function onCarryClick(button)
  local row = button.row
  local loc = row and row.locations[1]
  if not loc or P._pending then return end
  -- Always the Warband Bank: the list hands items to another of the player's characters.
  if not P.MoveStack({ bag = loc.bag, slot = loc.slot, itemID = row.itemID }, button.kind == "in", accountBank()) then
    return
  end
  pendingSeq = pendingSeq + 1
  local token = pendingSeq
  P._pending = token
  button:Disable()
  button:SetLabel(GC.L["moving..."])
  if C_Timer and C_Timer.After then
    C_Timer.After(P.SETTLE_SECONDS, function() P._Expire(token) end)
  end
end

-- Nothing moved in time (full bags, a slot the server refused): the button is offered again.
function P._Expire(token)
  if P._pending == token then
    P._pending = nil
    P.Refresh()
  end
end

local function build()
  local T = GC.Theme
  frame = T.Card(UIParent, T.color.panel, T.color.border, true)
  frame:SetWidth(LAYOUT.WIDTH)
  frame:EnableMouse(true)
  frame.title = T.Label(frame, 12)
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -LAYOUT.PAD)
  frame.title:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  frame.title:SetJustifyH("LEFT")
  frame.title:SetWordWrap(true)
  frame.title:SetTextColor(T.color.gold[1], T.color.gold[2], T.color.gold[3])
  frame.note = T.Label(frame, 10)
  frame.note:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  frame.note:SetJustifyH("LEFT")
  frame.note:SetWordWrap(true)
  frame.note:SetTextColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3])
  P._frame = frame
end

local function headingAt(i)
  local T = GC.Theme
  local heading = P._headings[i]
  if heading then return heading end
  heading = T.Label(frame, 11)
  heading:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  heading:SetJustifyH("LEFT")
  heading:SetWordWrap(true)
  heading:SetTextColor(T.color.fg[1], T.color.fg[2], T.color.fg[3])
  P._headings[i] = heading
  return heading
end

-- One line: the icon, the item and how many (wrapping), where it goes (wrapping), and under them
-- the button, as wide as its label.
local function rowAt(i)
  local T = GC.Theme
  local row = P._rows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, frame)
  row:SetWidth(LAYOUT.WIDTH - 2 * LAYOUT.PAD)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(LAYOUT.ICON, LAYOUT.ICON)
  row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  local textW = LAYOUT.WIDTH - 2 * LAYOUT.PAD - LAYOUT.ICON - LAYOUT.ICON_GAP
  row.name = T.Label(row, 11)
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", LAYOUT.ICON + LAYOUT.ICON_GAP, 0)
  row.name:SetWidth(textW)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(true)
  row.name:SetTextColor(T.color.fg[1], T.color.fg[2], T.color.fg[3])
  row.where = T.Num(row, 9)
  row.where:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
  row.where:SetWidth(textW)
  row.where:SetJustifyH("LEFT")
  row.where:SetWordWrap(true)
  row.where:SetTextColor(T.color.fgDim[1], T.color.fgDim[2], T.color.fgDim[3])
  local button = T.Button(row, "primary", "plaque")
  button:SetHeight(LAYOUT.BUTTON_H)
  button:SetScript("OnClick", onCarryClick)
  row.button = button
  P._rows[i] = row
  return row
end

local function fitButton(button)
  local fs = button.text
  local width = fs and fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  if type(width) ~= "number" then width = 0 end
  button:SetWidth(math.min(LAYOUT.WIDTH - 2 * LAYOUT.PAD,
    math.max(LAYOUT.BUTTON_MIN_W, math.ceil(width) + 2 * GC.Theme.pad.m)))
end

-- Lays a row out for what it now says, and answers its height. A row with no button (a stuck one)
-- ends under its words.
local function layoutRow(row, withButton)
  local nameH = row.name.GetStringHeight and row.name:GetStringHeight() or 12
  local whereH = row.where.GetStringHeight and row.where:GetStringHeight() or 10
  local textH = math.max(LAYOUT.ICON, (nameH or 0) + 2 + (whereH or 0))
  local h = textH
  if withButton then
    fitButton(row.button)
    row.button:ClearAllPoints()
    row.button:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -(textH + LAYOUT.GAP))
    row.button:Show()
    h = textH + LAYOUT.GAP + LAYOUT.BUTTON_H
  else
    row.button:Hide()
  end
  h = math.ceil(h)
  row:SetHeight(h)
  return h
end

-- Where a row's item goes, in words.
local function whereText(kind, spot)
  if kind == "stuck" then return GC.L["Warbound until equipped: the auction house refuses it"] end
  local money, pace = GC.Util.FormatMoney(spot.list), GC.SellRoute.PaceText(spot.days)
  if kind == "out" then return (GC.L["here: %s, %s"]):format(money, pace) end
  return (GC.L["for %s: %s, %s"]):format(GC.SellRoute.RealmName(spot.realmId) or "?", money, pace)
end

local function paintRow(row, entry, kind)
  row.button.row, row.button.kind = entry, kind
  if entry.icon then row.icon:SetTexture(entry.icon); row.icon:Show() else row.icon:Hide() end
  local name = entry.name or ("#" .. tostring(entry.itemID))
  row.name:SetText(entry.count > 1 and ("%s ×%d"):format(name, entry.count) or name)
  row.where:SetText(whereText(kind, entry.spot))
  local b = row.button
  b:SetVariant("primary")
  if P._pending then
    b:SetLabel(GC.L["moving..."])
    b:Enable(); b:Disable()
  else
    b:SetLabel(kind == "in" and GC.L["PUT IN"] or GC.L["TAKE OUT"])
    b:Enable()
  end
end

--- Reads the bags and the bank again and paints the list, or hides it when there is nothing to
--- carry. Reads nothing without route data (no Companion, another region): that player never sees
--- the list. Hidden too when its buttons could not work: the Warband Bank out of reach at this
--- banker, or no tab bought.
function P.Refresh()
  if not (P._open and GC.SellRoute.HereId() and bankIsTheWindow(accountBank()) and hasTabs(accountBank())) then
    if frame then frame:Hide() end
    return
  end
  local plan = P.Plan()
  local sections = {}
  if #plan.putIn > 0 then
    sections[#sections + 1] = { kind = "in", heading = GC.L["Put in the Warband Bank"], rows = plan.putIn }
  end
  if #plan.takeOut > 0 then
    sections[#sections + 1] = { kind = "out", heading = GC.L["Take out to sell here"], rows = plan.takeOut }
  end
  if #plan.stuck > 0 then
    sections[#sections + 1] = { kind = "stuck", heading = GC.L["Can't be sold"], rows = plan.stuck }
  end
  -- A piece that cannot be sold is told beside something to carry, never opens the list alone.
  if #plan.putIn + #plan.takeOut == 0 then
    if frame then frame:Hide() end
    return
  end
  if not frame then build() end
  frame:ClearAllPoints()
  local bank = _G.BankFrame
  if type(bank) == "table" and bank.IsShown and bank:IsShown() then
    frame:SetPoint("TOPLEFT", bank, "TOPRIGHT", P.BesideBankX(bank, LAYOUT.X), 0)
  else
    frame:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
  end
  frame.title:SetText(GC.L["GoldCap: carry between realms"])
  local y = LAYOUT.PAD + (frame.title.GetStringHeight and frame.title:GetStringHeight() or 12)
  local r = 0
  for i, section in ipairs(sections) do
    local heading = headingAt(i)
    heading:SetText(section.heading)
    heading:ClearAllPoints()
    y = y + (i == 1 and LAYOUT.ROW_GAP or LAYOUT.SECTION_GAP)
    heading:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -y)
    heading:Show()
    y = y + (heading.GetStringHeight and heading:GetStringHeight() or 12) + LAYOUT.ROW_GAP
    for _, entry in ipairs(section.rows) do
      r = r + 1
      local row = rowAt(r)
      paintRow(row, entry, section.kind)
      local h = layoutRow(row, section.kind ~= "stuck")
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -y)
      row:Show()
      y = y + h + LAYOUT.ROW_GAP
    end
  end
  for i = #sections + 1, #P._headings do P._headings[i]:Hide() end
  for i = r + 1, #P._rows do P._rows[i]:Hide() end
  -- What comes next, for a player new to it: where the item goes after the bank.
  frame.note:SetText(#plan.putIn > 0
    and GC.L["Then log in a character on that realm and open a bank: GoldCap lists what to take out."]
    or GC.L["Then list it from GoldCap's Sell tab at the auction house."])
  frame.note:ClearAllPoints()
  frame.note:SetPoint("TOPLEFT", frame, "TOPLEFT", LAYOUT.PAD, -y)
  y = y + (frame.note.GetStringHeight and frame.note:GetStringHeight() or 10) + LAYOUT.PAD
  frame:SetHeight(math.ceil(y))
  frame:Show()
end

function P.OnBankOpened()
  P._open, P._pending = true, nil
  P.Refresh()
end

function P.OnBankClosed()
  P._open, P._pending = false, nil
  if frame then frame:Hide() end
end

-- BAG_UPDATE_DELAYED: an item moved, by a press or by the player's own hand. Once a batch.
function P.OnBagsChanged()
  if not P._open then return end
  P._pending = nil
  P.Refresh()
end

-- PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED comes once a slot: sorting the Warband Bank or depositing
-- everything is hundreds of them. One repaint after the run.
function P.OnTabSlotsChanged()
  if not P._open or P._repaintQueued then return end
  if not (C_Timer and C_Timer.After) then return P.OnBagsChanged() end
  P._repaintQueued = true
  C_Timer.After(0, function()
    P._repaintQueued = nil
    P.OnBagsChanged()
  end)
end

--- The carry list in the chat, from anywhere: what in the bags to take to which realm. What sits in
--- the Warband Bank can only be read at a bank, so that half waits for one.
function P.PrintRoute()
  if not GC.SellRoute.HereId() then
    GC.Print(GC.L["Where each flip sells comes with the Companion's region data: nothing to go on yet."])
    return
  end
  local plan = P.Plan()
  local function say(rows, kind)
    for _, row in ipairs(rows) do
      local name = row.name or ("#" .. tostring(row.itemID))
      if row.count > 1 then name = ("%s ×%d"):format(name, row.count) end
      GC.Print((GC.L["%s: %s"]):format(name, whereText(kind, row.spot)))
    end
  end
  if #plan.putIn == 0 and (not P._open or #plan.takeOut + #plan.stuck == 0) then
    GC.Print(GC.L["Nothing in your bags sells notably better on another of your realms."])
  end
  say(plan.putIn, "in")
  say(plan.takeOut, "out")
  say(plan.stuck, "stuck")
  if not P._open then GC.Print(GC.L["What to take out of the Warband Bank shows at a bank."]) end
end

GC.slashHandlers = GC.slashHandlers or {}
GC.slashHandlers.route = function() P.PrintRoute() end
