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

local function accountBank()
  return Enum and Enum.BankType and Enum.BankType.Account or nil
end

-- The bank is open, its Warband tabs can be used, and no other window is open that a container
-- click would feed instead: a vendor sells the item, the auction house, the mail and a trade take it.
local function bankIsTheWindow()
  local account = accountBank()
  if not (P._open and account and C_Bank and C_Bank.CanUseBank) then return false end
  local ok, can = pcall(C_Bank.CanUseBank, account)
  if not (ok and can) then return false end
  for _, name in ipairs({ "MerchantFrame", "AuctionHouseFrame", "SendMailFrame", "TradeFrame" }) do
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

-- The Warband Bank has a tab to put things in: a deposit into none goes nowhere.
local function hasTabs()
  local tabs = ask(C_Bank.FetchPurchasedBankTabIDs, accountBank())
  return type(tabs) == "table" and #tabs > 0
end

-- One stack as CarryPlan reads it, or nil: an empty slot, an item goldcap.gg has no route for, a
-- soulbound one, one the Warband Bank refuses or one still refundable (Blizzard asks before ending
-- the refund; GoldCap does not decide that for the player). A Warbound-until-equipped one is read,
-- marked, so the player is told why it stays.
local function readStack(bag, slot, inBank)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not (info and info.itemID and GC.Data.SellSpots(info.itemID)) then return nil end
  local loc = locationOf(bag, slot)
  if not loc then return nil end
  local wue = ask(C_Item.IsBoundToAccountUntilEquip, loc) == true
  if info.isBound and not wue then return nil end
  if not inBank and not wue then
    if ask(C_Item.CanBeRefunded, loc) then return nil end
    if ask(C_Bank.IsItemAllowedInBankType, accountBank(), loc) == false then return nil end
  end
  return { itemID = info.itemID, bag = bag, slot = slot, count = info.stackCount or 1, name = info.itemName,
    icon = info.iconFileID, ilvl = ask(C_Item.GetCurrentItemLevel, loc), wue = wue or nil }
end

local function readContainers(bags, inBank)
  local stacks = {}
  for _, bag in ipairs(bags) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local stack = readStack(bag, slot, inBank)
      if stack then stacks[#stacks + 1] = stack end
    end
  end
  return stacks
end

--- What to carry from this bank now (GC.SellRoute.CarryPlan), from the bags and, while the bank is
--- open, the Warband Bank's tabs.
function P.Plan()
  local tabs = P._open and ask(C_Bank.FetchPurchasedBankTabIDs, accountBank()) or {}
  return GC.SellRoute.CarryPlan(readContainers(BAGS, false), readContainers(tabs, true), {
    hereId = GC.SellRoute.HereId(),
    routeFor = GC.SellRoute.ForItem,
    levelFor = GC.Data.FlipLevel,
  })
end

-- The button's own click: the one place the addon moves an item. Checks the bank is the window
-- and the slot still holds the row's item and is not locked, makes the call, and only then puts
-- the button to sleep: BAG_UPDATE_DELAYED (OnBagsChanged) paints the move.
local function onCarryClick(button)
  local row = button.row
  local loc = row and row.locations[1]
  if not loc or P._pending or not bankIsTheWindow() then return end
  local info = C_Container.GetContainerItemInfo(loc.bag, loc.slot)
  if not (info and info.itemID == row.itemID) or info.isLocked then return end
  if button.kind == "in" then
    C_Container.UseContainerItem(loc.bag, loc.slot, nil, accountBank(), false)
  else
    C_Container.UseContainerItem(loc.bag, loc.slot)
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
  if not (P._open and GC.SellRoute.HereId() and bankIsTheWindow() and hasTabs()) then
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
    frame:SetPoint("TOPLEFT", bank, "TOPRIGHT", LAYOUT.X, 0)
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
