local _, GC = ...

-- At a bank (retail only, GoldCap.toc): the one reader of the bags and a bank's tabs as stacks,
-- the one move of a stack between them, and what to carry between realms through the Warband Bank
-- (ClickUp 869fjhvn9): the flips in the bags that sell notably better on another of the player's
-- realms (put in), and the flips in the Warband Bank that sell best on this one (take out), each
-- with where, for how much and how soon (Core/SellRoute.lua's CarryPlan, from goldcap.gg's
-- payload). Worked out from what is there, not from a list kept since the purchase: an item bought
-- outside GoldCap, or one whose best realm moved since, is placed right all the same. goldcap.gg
-- works out where flips sell for retail realms alone, so on WoW: Forever there is nothing to carry.
--
-- This file draws nothing. The GoldCap Hoard (UI/HoardFrame.lua) stands beside the bank window and
-- draws it all: its rows, tiles and footer read through ReadStacks, its carry cards
-- (UI/HoardCarry.lua) list Plan, and every press of the window moves through MoveStack, one
-- C_Container.UseContainerItem a stack (spec/bank_route_spec.lua audits it), made only after
-- checking the bank is the window open and the slot still holds the item: the same call equips a
-- piece of gear when no bank is open, which binds it, and sells it when a vendor is. The bank
-- events reach the Hoard through this file's handlers (OnBankOpened, OnBankClosed, OnBagsChanged,
-- OnTabSlotsChanged), which Core/Init.lua's event frame calls and the Hoard hooks.
--
-- The reader, the move and their guards each take the bank they work with: the carry cards always
-- the Warband Bank (they hand items to another character), the rest of the Hoard the bank its own
-- switch names, which starts on the one the bank window shows (ShownBankType).
GC.BankRoute = {}
local P = GC.BankRoute

-- How long a press waits for the bags to show the move before the stack is offered again.
P.SETTLE_SECONDS = 3

-- The backpack and the four bag slots; the reagent bag holds no realm item.
local BAGS = { 0, 1, 2, 3, 4 }
local IS_BAG = {}
for _, bag in ipairs(BAGS) do IS_BAG[bag] = true end

-- How far past the bank window's right edge a panel beside it starts (the GoldCap Hoard): past the
-- tab buttons Blizzard hangs off the bank panel's right edge (BankFrame.lua,
-- BankPanelMixin:RefreshBankTabs, 2 out from it), which covered the left of the carry list that
-- stood there before (owner, 2026-10-23). Measured from what the panel shows past the edge, plus
-- the tab's border past its button: SpellBook-SkillLineTab is 64 wide at x -3 and drawn to x 38,
-- 4 past the 32-wide button. `gap` alone where nothing sticks out.
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

-- A client call's answer, false kept as false (a refusal is an answer), nil when it errors
-- (Core/Util.lua's Ask).
local ask = GC.Util.Ask

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

-- One stack as the Hoard reads it, or nil: an empty slot, an item `wanted` does not take (with a
-- `wanted`), a bound one unless `soulbound` asks for those too, and then marked `bound`. A
-- Warbound-until-equipped one is marked `wue`, a stack in the bags `bankType`'s bank must not take
-- `stays` (with why, staysWhy above), and one the game holds (on the cursor, or on its way)
-- `locked`.
local function readStack(bag, slot, inBank, wanted, bankType, soulbound, whyStays)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not (info and info.itemID and (wanted == nil or wanted(info.itemID))) then return nil end
  local loc = locationOf(bag, slot)
  if not loc then return nil end
  local wue = ask(C_Item.IsBoundToAccountUntilEquip, loc) == true
  local bound = info.isBound and not wue
  if bound and not soulbound then return nil end
  local stack = { itemID = info.itemID, bag = bag, slot = slot, count = info.stackCount or 1, name = info.itemName,
    link = info.hyperlink, icon = info.iconFileID, ilvl = ask(C_Item.GetCurrentItemLevel, loc), wue = wue or nil,
    locked = info.isLocked or nil, bound = bound or nil }
  if not inBank then
    if whyStays then
      stack.stays = whyStays(loc, stack)
    else
      stack.stays = staysWhy(loc, bankType)
    end
  end
  return stack
end

--- Every stack of `bags` whose item `wanted(itemID)` takes (every stack, `wanted` nil), read as
--- readStack reads one; a stack in the bags is marked `stays` against `bankType`'s bank
--- (Enum.BankType), the one it would go into. `opts.soulbound`: the stacks the client reports
--- bound too, marked `bound`, which are left out otherwise: soulbound ones, and items bound to the
--- account (Warbound), which can report bound as well. The character's own bank takes either (the
--- Hoard's Make room moves them there, and its Put back and For your crafts take them out of it);
--- the Warband Bank refuses a soulbound one and takes a Warbound one, so in the bags against it
--- what it refuses `stays`, refused: that bank's answer (C_Bank.IsItemAllowedInBankType, which
--- Blizzard's own bags ask to dim what the bank shown will not take, Blizzard_FrameXMLUtil's
--- ItemUtil.lua). `opts.staysWhy(loc, stack)` answers why a stack in the bags stays (a reason or
--- nil) in place of the bank's own answer, for a reader that is not feeding a bank: the mailbox's
--- (Core/MailGroups.lua's StaysWhy).
function P.ReadStacks(bags, inBank, wanted, bankType, opts)
  local soulbound = type(opts) == "table" and opts.soulbound == true
  local whyStays = type(opts) == "table" and type(opts.staysWhy) == "function" and opts.staysWhy or nil
  local stacks = {}
  for _, bag in ipairs(bags) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local stack = readStack(bag, slot, inBank, wanted, bankType, soulbound, whyStays)
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
--- bank for the whole visit, so this answers the character's bank all along; the Hoard has its
--- own switch of bank for that (UI/HoardFrame.lua).
function P.ShownBankType()
  local bank, character = _G.BankFrame, Enum and Enum.BankType and Enum.BankType.Character
  local shown = type(bank) == "table" and ask(bank.GetActiveBankType, bank) or nil
  if character ~= nil and shown == character then return character end
  return accountBank()
end

--- What to carry from this bank now (GC.SellRoute.CarryPlan), from the bags and, while the bank is
--- open, the Warband Bank's tabs, for the Hoard's carry cards and /gc route. A stack in the bags the
--- Warband Bank must not take is left out, unless it is Warbound until equipped: that one is told
--- why it stays. Bound stacks are left out: no other character can sell them. Without route data
--- (no Companion region payload, another region) nothing is read and the plan is empty.
---
--- `read`, the Hoard's paint's (UI/HoardFrame.lua), so a paint reads each slot once: { inBags,
--- inBank, against }, `inBags()` every stack it read in the bags, bound ones too, marked `stays`
--- against the bank `against` (the one its switch names), and `inBank(bankType)` every stack of
--- that bank's tabs; both asked only with route data. A stack in the bags marked against the
--- character's own bank is asked again here, against the Warband Bank. Without `read` (/gc route)
--- Plan reads them itself.
function P.Plan(read)
  local hereId = GC.SellRoute.HereId()
  if not hereId then return GC.SellRoute.CarryPlan({}, {}, {}) end
  local account = accountBank()
  local against = read and read.against or account
  local function routed(stacks, inBank)
    local out = {}
    for _, stack in ipairs(stacks) do
      if not stack.bound and (inBank or IS_BAG[stack.bag]) and GC.Data.SellSpots(stack.itemID) then
        if not inBank and against ~= account then
          local mine = {}
          for k, v in pairs(stack) do mine[k] = v end
          local loc = locationOf(stack.bag, stack.slot)
          mine.stays = loc and staysWhy(loc, account) or nil
          stack = mine
        end
        if inBank or stack.wue or not stack.stays then out[#out + 1] = stack end
      end
    end
    return out
  end
  local bagStacks, bankStacks
  if read then
    bagStacks, bankStacks = read.inBags(), read.inBank(account)
  else
    bagStacks = P.ReadStacks(BAGS, false, GC.Data.SellSpots, account)
    bankStacks = P.ReadStacks(P.BankTabs(account), true, GC.Data.SellSpots, account)
  end
  return GC.SellRoute.CarryPlan(routed(bagStacks, false), routed(bankStacks, true), {
    hereId = hereId,
    routeFor = GC.SellRoute.ForItem,
    levelFor = GC.Data.FlipLevel,
  })
end

--- The one place the addon moves an item between the bags and a bank: one
--- C_Container.UseContainerItem, made by the player's own press, the Hoard's (UI/HoardFrame.lua's
--- moveRow, which Core/VendorPress.lua calls first inside the Hoard's click and then from its
--- timers, each after re-checking the bank and the slot); spec/bank_route_spec.lua audits it.
--- `bankType` (Enum.BankType) is the bank the stack goes into or comes out of; there is no
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

--- The first empty slot of a plain bag, the backpack or bags 1 to 4 (never the reagent bag or a
--- profession bag: a bag whose second answer of GetContainerNumFreeSlots, its bagFamily, is not 0),
--- as bag, slot; nil when there is none. Read at the moment of the split, not planned ahead.
function P.FreePlainSlot()
  for _, bag in ipairs(BAGS) do
    local free, family = C_Container.GetContainerNumFreeSlots(bag)
    if (free or 0) > 0 and family == 0 then
      for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
        if not C_Container.GetContainerItemInfo(bag, slot) then return bag, slot end
      end
    end
  end
  return nil
end

--- The first part of moving a split (Core/BankGroups.lua's Plan: `stack.split` is what the source
--- slot holds, `stack.count` what leaves it): splits `stack.count` off the source and drops it into
--- an empty slot of a plain bag, the way Blizzard's own split does (SplitContainerItem, then
--- PickupContainerItem; neither has restrictions). Answers { bag, slot } of the slot the part goes
--- to, which shows it once the server answers (SplitLanded); or nil and why: "cursor" (something is
--- on it), "gone" (the source no longer holds the stack as it was read), "room" (no empty slot of a
--- plain bag). It makes no call in any of those cases, so nothing is left on the cursor.
function P.SplitStack(stack)
  if type(stack) ~= "table" or type(stack.split) ~= "number" then return nil, "gone" end
  if GC.Util.CursorBusy() then return nil, "cursor" end
  local info = C_Container.GetContainerItemInfo(stack.bag, stack.slot)
  if not (info and info.itemID == stack.itemID) or info.isLocked or info.stackCount ~= stack.split then
    return nil, "gone"
  end
  local bag, slot = P.FreePlainSlot()
  if not bag then return nil, "room" end
  C_Container.SplitContainerItem(stack.bag, stack.slot, stack.count)
  C_Container.PickupContainerItem(bag, slot)
  return { bag = bag, slot = slot }
end

--- Whether the part of `stack` split off into `dest` ({ bag, slot }) shows there: the item, exactly
--- `stack.count` of it, not locked.
function P.SplitLanded(dest, stack)
  local info = C_Container.GetContainerItemInfo(dest.bag, dest.slot)
  return type(info) == "table" and info.itemID == stack.itemID and info.stackCount == stack.count
    and not info.isLocked
end

--- The part never showed in its slot: whatever the split left on the cursor goes back to where it
--- came from (ClearCursor returns a split part to its source).
function P.AbandonSplit()
  if ClearCursor then pcall(ClearCursor) end
end

--- Where a carry row's item goes, in words: for which realm, at what list price and how soon
--- ("in", put in for another realm), here ("out", take out to sell here), or why the auction house
--- refuses it ("stuck"). The Hoard's carry cards and /gc route say it the same way.
function P.WhereText(kind, spot)
  if kind == "stuck" then return GC.L["Warbound until equipped: the auction house refuses it"] end
  local money, pace = GC.Util.FormatMoney(spot.list), GC.SellRoute.PaceText(spot.days)
  if kind == "out" then return (GC.L["here: %s, %s"]):format(money, pace) end
  return (GC.L["for %s: %s, %s"]):format(GC.SellRoute.RealmName(spot.realmId) or "?", money, pace)
end

-- The bank events, as Core/Init.lua's event frame hands them on. The Hoard hooks each
-- (UI/HoardFrame.lua) and repaints; here they only keep whether the bank is open.
function P.OnBankOpened()
  P._open = true
end

function P.OnBankClosed()
  P._open = false
end

-- BAG_UPDATE_DELAYED: an item moved, by a press or by the player's own hand. Once a batch; the
-- Hoard repaints.
function P.OnBagsChanged()
end

-- PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED comes once a slot: sorting the Warband Bank or depositing
-- everything is hundreds of them, and a move into it comes with a BAG_UPDATE_DELAYED too. Each is
-- handed on as the bags' change while the bank is open; the Hoard paints once on the next frame
-- for all of them (UI/HoardFrame.lua's OnBagsChanged), so a move into the Warband Bank paints once.
function P.OnTabSlotsChanged()
  if P._open then P.OnBagsChanged() end
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
      GC.Print((GC.L["%s: %s"]):format(name, P.WhereText(kind, row.spot)))
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
