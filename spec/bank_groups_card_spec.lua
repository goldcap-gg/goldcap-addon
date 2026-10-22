local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/BankGroupsCard.lua: at a bank, the followed groups with items in the bags or the bank the bank
-- window shows (the character's own or the Warband Bank), each with To bank and To bags, one stack a
-- press. The real Theme, the real group rules (from a Companion file), the real selection
-- (Core/BankGroups.lua) and the real bank route (UI/BankRoute.lua), whose reader, move function and
-- guards the card uses; the bags, both banks, the bank window and the client calls are faked.
describe("bank by group card", function()
  local GC, C, restore, saved, bags, used, timers, canUse, tabs, refundable, refused, reads, asked, closedFor
  local showing, usable, charTabs, refusedHere, targeting
  -- Enum.BankType (Blizzard_APIDocumentationGenerated's ItemConstantsDocumentation.lua).
  local CHARACTER, ACCOUNT = 0, 2
  local KEYS = { "Enum", "UIParent", "BankFrame", "BankPanel", "MerchantFrame", "ItemLocation", "C_Container",
    "C_Item", "C_Bank", "C_Timer", "hooksecurefunc", "GoldCap_AppRuns", "SpellIsTargeting", "GetCursorInfo" }

  -- Herbs: Bloom (two qualities, 1 and 2); Ore: Bismuth (3); Cloth: Weavercloth (4), never in the
  -- bags here. Item 9 is in no followed group.
  local FILE = {
    v = 3, generatedAt = 1, runs = {}, groups = { "G" },
    caps = {
      { i = 1, c = 700, u = 1000, r = 1, k = true }, { i = 2, c = 700, u = 1000, r = 1, k = true },
      { i = 3, c = 700, u = 1000, r = 2, k = true }, { i = 4, c = 700, u = 1000, r = 3, k = true },
      { i = 6, c = 700, u = 1000, r = 1, k = true },
    },
    rules = { { n = "Herbs", p = "gather", d = 24, fp = 80 }, { n = "Ore", p = "gather", d = 24, fp = 80 },
      { n = "Cloth", p = "gather", d = 24, fp = 80 } },
  }
  local NAMES = { [1] = "Bloom", [2] = "Bloom", [3] = "Bismuth", [4] = "Weavercloth", [6] = "Mycobloom of the Deepest Earthen Caverns",
    [9] = "Linen Cloth" }

  local function info(itemID, count, over)
    local i = { itemID = itemID, itemName = NAMES[itemID], stackCount = count, iconFileID = itemID,
      isBound = false, isLocked = false }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
  end

  local function textOf(fs) return W.state(fs).text end
  local function shown(widget) return widget ~= nil and widget:IsShown() end
  local function cardUp() return C._frame ~= nil and C._frame:IsShown() end

  local function block(name)
    for _, b in ipairs(C._blocks) do
      if b:IsShown() and textOf(b.name) == name then return b end
    end
  end

  local function press(button) W.state(button).scripts.OnClick(button) end
  local function at(widget) return W.state(widget).points[1] end
  local function staysOf(b)
    local out = {}
    for _, fs in ipairs(b.stays) do if fs:IsShown() then out[#out + 1] = textOf(fs) end end
    return out
  end
  -- The player clicks the bank window's other tab: BankFrame:SetTab sets the panel's bank type and
  -- the panel resets (Blizzard_UIPanels_Game's BankFrame.lua); the card repaints on the next frame.
  local function switchTo(bankType)
    showing = bankType
    _G.BankPanel:Reset()
    for i = #timers, 1, -1 do
      if timers[i].seconds == 0 then table.remove(timers, i).fn() end
    end
  end

  local function open()
    GC.BankRoute.OnBankOpened()
  end

  -- n followed groups, "Group 01" to "Group n", each with one item (100 + k), 20 of it in the bags.
  local function manyGroups(n)
    local file = { v = 3, generatedAt = 1, runs = {}, groups = { "G" }, caps = {}, rules = {} }
    bags = { [0] = {}, [12] = {} }
    for k = 1, n do
      file.caps[k] = { i = 100 + k, c = 700, u = 1000, r = k, k = true }
      file.rules[k] = { n = ("Group %02d"):format(k), p = "gather", d = 24, fp = 80 }
      NAMES[100 + k] = "Item " .. k
      bags[0][k] = info(100 + k, 20)
    end
    _G.GoldCap_AppRuns = file
    GC.GroupRules.Adopt()
  end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    used, timers, canUse, tabs, refundable, refused, reads, asked = {}, {}, true, { 12 }, {}, {}, 0, nil
    -- The bank window shows the Warband Bank unless a spec switches it; refusedHere is what the
    -- character's own bank refuses, refused what the Warband Bank does.
    showing, usable, charTabs, refusedHere = ACCOUNT, { [ACCOUNT] = true, [CHARACTER] = true }, { 6 }, {}
    -- 0: the backpack; 5: the reagent bag; 6: the character's first bank tab; 12: the first
    -- Warband Bank tab.
    bags = {
      [0] = { info(1, 200), info(1, 20), info(9, 20) },
      [5] = { info(3, 50) },
      [6] = { info(2, 40) },
      [12] = { info(2, 600) },
    }
    _G.Enum = { BankType = { Character = CHARACTER, Account = ACCOUNT } }
    -- Read by GC.Util.CursorBusy: no spell waits for a target and the cursor is empty.
    targeting = false
    _G.SpellIsTargeting = function() return targeting end
    _G.GetCursorInfo = function() return nil end
    _G.UIParent = W.CreateFrame("Frame")
    _G.BankFrame = W.CreateFrame("Frame")
    _G.BankFrame:Show()
    -- BankFrameMixin:GetActiveBankType, and the panel's BankPanelMixin:Reset, which the card post-hooks.
    function _G.BankFrame:GetActiveBankType() return showing end
    _G.BankPanel = W.CreateFrame("Frame", nil, _G.BankFrame)
    function _G.BankPanel:Reset() end
    -- A frame the client builds is hidden until it opens; a W frame starts shown.
    _G.MerchantFrame = W.CreateFrame("Frame")
    _G.MerchantFrame:Hide()
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
      GetContainerItemInfo = function(bag, slot) reads = reads + 1; return bags[bag] and bags[bag][slot] or nil end,
      UseContainerItem = function(...) used[#used + 1] = { n = select("#", ...), ... } end,
    }
    _G.C_Item = {
      IsBoundToAccountUntilEquip = function() return false end,
      CanBeRefunded = function(loc) return refundable[loc.bag .. ":" .. loc.slot] == true end,
      GetCurrentItemLevel = function() return 0 end,
    }
    _G.C_Bank = {
      CanUseBank = function(t) return canUse and usable[t] == true end,
      IsItemAllowedInBankType = function(t, loc)
        return not (t == CHARACTER and refusedHere or refused)[loc.bag .. ":" .. loc.slot]
      end,
      FetchPurchasedBankTabIDs = function(t)
        if t == ACCOUNT then return tabs end
        return t == CHARACTER and charTabs or {}
      end,
    }
    _G.C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
    _G.hooksecurefunc = function(t, name, fn)
      local original = t[name]
      t[name] = function(...)
        local result = original(...)
        fn(...)
        return result
      end
    end
    _G.GoldCap_AppRuns = FILE
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("Core/GroupRules.lua", GC)
    helper.loadModule("Core/CraftQueue.lua", GC)
    helper.loadModule("Core/BankGroups.lua", GC)
    GC.GroupRules.Adopt()
    -- No route data (no Companion region payload): the carry list stays hidden.
    GC.SellRoute = { HereId = function() return nil end }
    GC.db = {}
    closedFor = {}
    GC.BuyCapEditor = {
      Open = function(anchor, opts) asked = { anchor = anchor, opts = opts } end,
      CloseFor = function(anchor) closedFor[anchor] = true end,
    }
    helper.loadModule("UI/BankRoute.lua", GC)
    helper.loadModule("UI/BankGroupsCard.lua", GC)
    C = GC.BankGroupsCard
  end)

  after_each(function()
    GC.ActivateLocale(nil)
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  it("lists each followed group with items in the bags or the Warband Bank, with both counts", function()
    open()
    assert.is_true(cardUp())
    assert.equal("GoldCap: your groups", textOf(C._frame.title))
    assert.equal("Moves stacks between your bags and the Warband Bank", textOf(C._frame.bank))
    local herbs, ore = block("Herbs"), block("Ore")
    assert.equal("220 in bags, 600 in the Warband Bank", textOf(herbs.counts))
    -- The reagent bag counts: herbs and ore go there.
    assert.equal("50 in bags, 0 in the Warband Bank", textOf(ore.counts))
    assert.is_nil(block("Cloth"))
    local names = {}
    for _, b in ipairs(C._blocks) do if b:IsShown() then names[#names + 1] = textOf(b.name) end end
    assert.same({ "Herbs", "Ore" }, names)
  end)

  it("says what the next press moves and how many stacks are left", function()
    open()
    local herbs = block("Herbs")
    assert.equal("To bank: Bloom ×200 (2 left)", herbs.toBank.label)
    assert.equal("To bags: Bloom ×600 (1 left)", herbs.toBags.label)
    -- Nothing of Ore in the Warband Bank: its To bags stays in its place, saying so, disabled.
    local oreBags = block("Ore").toBags
    assert.is_true(shown(oreBags))
    assert.equal("To bags: nothing to move", oreBags.label)
    assert.is_false(oreBags:IsEnabled())
  end)

  it("puts exactly one stack in the Warband Bank a press, inside the click, and names the next one at once", function()
    open()
    local toBank = block("Herbs").toBank
    press(toBank)
    assert.equal(1, #used)
    assert.same({ n = 5, 0, 1, nil, ACCOUNT, false }, used[1])
    -- Never put to sleep: the next press moves the next stack.
    assert.is_true(toBank:IsEnabled())
    assert.equal("To bank: Bloom ×20 (1 left)", block("Herbs").toBank.label)
    press(block("Herbs").toBank)
    assert.equal(2, #used)
    assert.same({ n = 5, 0, 2, nil, ACCOUNT, false }, used[2])
    -- Both on their way: nothing more to send. The button stays where it was, disabled.
    assert.is_true(shown(toBank))
    assert.equal("To bank: nothing to move", toBank.label)
    assert.is_false(toBank:IsEnabled())
  end)

  it("takes exactly one stack out of the Warband Bank a press", function()
    open()
    press(block("Herbs").toBags)
    assert.same({ { n = 2, 12, 1 } }, used)
    assert.equal("To bags: nothing to move", block("Herbs").toBags.label)
    assert.is_false(block("Herbs").toBags:IsEnabled())
  end)

  it("repaints when the game shows the move, and offers a stack again when nothing moved in time", function()
    open()
    press(block("Herbs").toBank)
    bags[12][2], bags[0][1] = bags[0][1], info(9, 1)
    GC.BankRoute.OnBagsChanged()
    assert.equal("20 in bags, 800 in the Warband Bank", textOf(block("Herbs").counts))
    assert.equal("To bank: Bloom ×20 (1 left)", block("Herbs").toBank.label)
    -- A press the server refused (a full bank): the stack stays in its slot.
    press(block("Herbs").toBank)
    assert.is_false(block("Herbs").toBank:IsEnabled())
    GC.BankRoute.OnBagsChanged()
    assert.is_false(block("Herbs").toBank:IsEnabled())
    timers[#timers].fn()
    assert.equal(GC.BankRoute.SETTLE_SECONDS, timers[#timers].seconds)
    assert.equal("To bank: Bloom ×20 (1 left)", block("Herbs").toBank.label)
    assert.is_true(block("Herbs").toBank:IsEnabled())
  end)

  -- The card is pressed again and again in one spot: nothing on it moves between two presses, so
  -- a press never lands on another button. An emptied button stays where it was and is disabled
  -- only after its own last move; the card's width (and so every line's wrapping) is set for the
  -- widest label any press can bring, and each line keeps room for the most it can say.
  it("keeps every button and line where it is between presses, an emptied button included", function()
    bags[0][4] = info(6, 5)
    open()
    local card, herbs, ore = C._frame, block("Herbs"), block("Ore")
    local function snapshot()
      return {
        width = card:GetWidth(), height = card:GetHeight(), herbs = at(herbs), ore = at(ore),
        keep = at(herbs.keep), toBank = at(herbs.toBank), toBags = at(herbs.toBags),
        bankW = herbs.toBank:GetWidth(), bagsW = herbs.toBags:GetWidth(), oreBank = at(ore.toBank),
      }
    end
    local before = snapshot()
    local enabledAtCall = {}
    local use = _G.C_Container.UseContainerItem
    _G.C_Container.UseContainerItem = function(...)
      enabledAtCall[#enabledAtCall + 1] = herbs.toBank:IsEnabled()
      return use(...)
    end
    press(herbs.toBank)
    press(herbs.toBank)
    -- The next one has the longest name of the group: the card was already wide enough for it.
    assert.equal("To bank: Mycobloom of the Deepest Earthen Caverns ×5 (1 left)", herbs.toBank.label)
    assert.same(before, snapshot())
    press(herbs.toBank)
    assert.same({ true, true, true }, enabledAtCall)
    assert.equal("To bank: nothing to move", herbs.toBank.label)
    assert.is_false(herbs.toBank:IsEnabled())
    -- A press on it now moves nothing, and never reaches To bags.
    press(herbs.toBank)
    assert.equal(3, #used)
    assert.same(before, snapshot())
    -- The three land in the Warband Bank: To bags has four stacks now, To bank none.
    bags[12][2], bags[12][3], bags[12][4] = bags[0][1], bags[0][2], bags[0][4]
    bags[0][1], bags[0][2], bags[0][4] = info(9, 1), info(9, 1), info(9, 1)
    GC.BankRoute.OnBagsChanged()
    assert.equal("0 in bags, 825 in the Warband Bank", textOf(herbs.counts))
    assert.equal("To bags: Bloom ×200 (4 left)", herbs.toBags.label)
    assert.same(before, snapshot())
  end)

  it("keeps the keep count of each item in the bags, set from the card and remembered for the account", function()
    open()
    local keep = block("Herbs").keep
    assert.equal("Keep in bags: 0 of each", keep.label)
    press(keep)
    assert.equal(keep, asked.anchor)
    assert.equal("How many of each item in Herbs to keep in your bags?", asked.opts.title)
    assert.equal("0", asked.opts.text)
    assert.equal(30, asked.opts.read("30"))
    assert.is_nil(asked.opts.read("lots"))
    asked.opts.onCommit(30)
    assert.same({ v = GC.BankGroups.VERSION, groups = { Herbs = 30 } }, GC.db.bankKeep)
    local herbs = block("Herbs")
    assert.equal("Keep in bags: 30 of each", herbs.keep.label)
    -- 220 Bloom: the 200 would leave 20, under 30; the 20 leaves 200.
    assert.equal("To bank: Bloom ×20 (1 left)", herbs.toBank.label)
    asked.opts.onCommit(300)
    assert.equal("To bank: nothing to move", block("Herbs").toBank.label)
    assert.is_false(block("Herbs").toBank:IsEnabled())
    assert.equal("To bags: Bloom ×600 (1 left)", block("Herbs").toBags.label)
  end)

  -- The question is about this bank's card: it goes when the bank closes.
  it("closes the keep popup with the bank", function()
    open()
    local keep = block("Herbs").keep
    press(keep)
    assert.is_nil(closedFor[keep])
    GC.BankRoute.OnBankClosed()
    assert.is_true(closedFor[keep])
  end)

  -- The bank route's own guards, reused: the same call equips gear with no bank open (which binds
  -- it) and sells to an open vendor; a stack still refundable or one the Warband Bank refuses is the
  -- player's to decide.
  it("moves nothing once the bank has closed, while a vendor is open, or with the Warband Bank out of reach", function()
    open()
    local toBank = block("Herbs").toBank
    GC.BankRoute.OnBankClosed()
    assert.is_false(cardUp())
    press(toBank)
    assert.same({}, used)
    open()
    toBank = block("Herbs").toBank
    _G.MerchantFrame:Show()
    press(toBank)
    assert.same({}, used)
    _G.MerchantFrame:Hide()
    canUse = false
    press(toBank)
    assert.same({}, used)
  end)

  it("moves nothing when the slot no longer holds the stack's item, or it is locked", function()
    open()
    -- The button names Bloom ×200 in 0:1; the bags change before any event says so.
    bags[0][1] = info(9, 200)
    press(block("Herbs").toBank)
    assert.same({}, used)
    -- The refusal repaints: the next press names what is there now.
    assert.equal("To bank: Bloom ×20 (1 left)", block("Herbs").toBank.label)
    bags[0][1] = info(1, 200)
    GC.BankRoute.OnBagsChanged()
    assert.equal("To bank: Bloom ×200 (2 left)", block("Herbs").toBank.label)
    bags[0][1] = info(1, 200, { isLocked = true })
    press(block("Herbs").toBank)
    assert.same({}, used)
  end)

  it("never offers a stack still refundable or one the Warband Bank refuses, and refuses it at the press too", function()
    refundable["0:1"], refused["0:2"] = true, true
    open()
    assert.is_false(block("Herbs").toBank:IsEnabled())
    assert.equal("220 in bags, 600 in the Warband Bank", textOf(block("Herbs").counts))
    refundable["0:1"], refused["0:2"] = nil, nil
    GC.BankRoute.OnBagsChanged()
    local toBank = block("Herbs").toBank
    refundable["0:1"] = true
    press(toBank)
    assert.same({}, used)
  end)

  -- A stack that stays is still counted ("220 in bags"), so the card says which one and why.
  it("names each stack that stays in the bags and why, under its group", function()
    refundable["0:2"] = true
    bags[5][2] = info(3, 7)
    refused["5:2"] = true
    open()
    local herbs, ore = block("Herbs"), block("Ore")
    assert.equal("220 in bags, 600 in the Warband Bank", textOf(herbs.counts))
    assert.equal("To bank: Bloom ×200 (1 left)", herbs.toBank.label)
    assert.same({ "Stays in bags: Bloom ×20, can still be refunded" }, staysOf(herbs))
    assert.same({ "Stays in bags: Bismuth ×7, the Warband Bank does not take it" }, staysOf(ore))
    -- The refund window ends: the line goes, and the stack is offered.
    refundable["0:2"] = nil
    GC.BankRoute.OnBagsChanged()
    assert.same({}, staysOf(block("Herbs")))
    assert.equal("To bank: Bloom ×200 (2 left)", block("Herbs").toBank.label)
  end)

  it("shows nothing when the Warband Bank cannot be used here, or has no tab", function()
    canUse = false
    open()
    assert.is_false(cardUp())
    GC.BankRoute.OnBankClosed()
    canUse, tabs = true, {}
    open()
    assert.is_false(cardUp())
  end)

  -- The ruling: the card follows the bank the player is looking at. With the character's own bank
  -- shown, To bank deposits into it, as Blizzard's own right click on a bag item does, and To bags
  -- takes from its tabs; the Warband Bank's stacks are not that bank's.
  it("with the character's own bank shown, names it, counts it, and moves to and from it", function()
    showing = CHARACTER
    open()
    assert.is_true(cardUp())
    assert.equal("Moves stacks between your bags and your bank", textOf(C._frame.bank))
    local herbs = block("Herbs")
    assert.equal("220 in bags, 40 in your bank", textOf(herbs.counts))
    assert.equal("50 in bags, 0 in your bank", textOf(block("Ore").counts))
    assert.equal("To bank: Bloom ×200 (2 left)", herbs.toBank.label)
    assert.equal("To bags: Bloom ×40 (1 left)", herbs.toBags.label)
    press(herbs.toBank)
    press(block("Herbs").toBags)
    assert.same({ { n = 5, 0, 1, nil, CHARACTER, false }, { n = 2, 6, 1 } }, used)
  end)

  it("repaints for the bank the window shows when the player switches its tab", function()
    open()
    assert.equal("220 in bags, 600 in the Warband Bank", textOf(block("Herbs").counts))
    switchTo(CHARACTER)
    assert.equal("Moves stacks between your bags and your bank", textOf(C._frame.bank))
    assert.equal("220 in bags, 40 in your bank", textOf(block("Herbs").counts))
    press(block("Herbs").toBank)
    assert.same({ { n = 5, 0, 1, nil, CHARACTER, false } }, used)
    -- Back on the Warband Bank's tab: the stack on its way is still on its way, the next one goes there.
    switchTo(ACCOUNT)
    assert.equal("Moves stacks between your bags and the Warband Bank", textOf(C._frame.bank))
    press(block("Herbs").toBank)
    assert.same({ n = 5, 0, 2, nil, ACCOUNT, false }, used[2])
    press(block("Herbs").toBags)
    assert.same({ n = 2, 12, 1 }, used[3])
  end)

  -- The panel resets from inside Blizzard's own work (a tab click, the window opening, twice as it
  -- opens): the card repaints once, on the next frame, so nothing of the card runs in that call.
  it("repaints once on the next frame for a run of bank panel resets, not inside them", function()
    open()
    reads = 0
    local before = #timers
    showing = CHARACTER
    _G.BankPanel:Reset()
    _G.BankPanel:Reset()
    assert.equal(0, reads)
    assert.equal("220 in bags, 600 in the Warband Bank", textOf(block("Herbs").counts))
    assert.equal(before + 1, #timers)
    assert.equal(0, timers[#timers].seconds)
    timers[#timers].fn()
    assert.is_true(reads > 0)
    assert.equal("220 in bags, 40 in your bank", textOf(block("Herbs").counts))
    _G.BankPanel:Reset()
    assert.equal(before + 2, #timers)
  end)

  -- The panel resets only while the window is open; should it reset outside a visit, nothing is read.
  it("reads nothing when the bank panel resets with the bank closed", function()
    open()
    GC.BankRoute.OnBankClosed()
    reads = 0
    local before = #timers
    switchTo(CHARACTER)
    assert.equal(before, #timers)
    assert.equal(0, reads)
    assert.is_false(cardUp())
  end)

  -- Blizzard asks before a deposit into the Warband Bank ends a refund, and deposits into the
  -- character's own bank without asking (BankFrame.lua's BankUtil_IsAccountBankDepositRefundable).
  it("toward the character's own bank, offers a refundable stack and names one that bank refuses", function()
    refundable["0:2"] = true
    bags[5][2] = info(3, 7)
    refused["5:2"], refusedHere["5:2"] = true, true
    showing = CHARACTER
    open()
    local herbs, ore = block("Herbs"), block("Ore")
    assert.same({}, staysOf(herbs))
    assert.equal("To bank: Bloom ×200 (2 left)", herbs.toBank.label)
    assert.same({ "Stays in bags: Bismuth ×7, your bank does not take it" }, staysOf(ore))
    press(herbs.toBank)
    press(block("Herbs").toBank)
    assert.same({ n = 5, 0, 2, nil, CHARACTER, false }, used[2])
    -- What only the Warband Bank refuses goes into the character's own bank.
    refusedHere["5:2"] = nil
    GC.BankRoute.OnBagsChanged()
    assert.same({}, staysOf(block("Ore")))
  end)

  it("hides while the character's own bank shown has no tab or cannot be used here, and shows on the Warband Bank's tab", function()
    showing, charTabs = CHARACTER, {}
    open()
    assert.is_false(cardUp())
    switchTo(ACCOUNT)
    assert.is_true(cardUp())
    charTabs, usable[CHARACTER] = { 6 }, false
    switchTo(CHARACTER)
    assert.is_false(cardUp())
    usable[CHARACTER] = true
    switchTo(CHARACTER)
    assert.is_true(cardUp())
    assert.equal("220 in bags, 40 in your bank", textOf(block("Herbs").counts))
  end)

  -- A group is its id on goldcap.gg: a follow from the site in another language keeps its count,
  -- and a catalog group and a player's own list that read alike are two groups.
  it("keeps a group's count by its id: a new name keeps it, and two groups named alike are two", function()
    local file = { v = 3, generatedAt = 1, runs = {}, groups = { "G" }, caps = FILE.caps, rules = {
      { n = "Herbs", id = "herbs", p = "gather", d = 24, fp = 80 },
      { n = "Herbs", id = "u_a1b2c3d4e5f6", p = "gather", d = 24, fp = 80 },
      { n = "Cloth", id = "cloth", p = "gather", d = 24, fp = 80 },
    } }
    _G.GoldCap_AppRuns = file
    GC.GroupRules.Adopt()
    open()
    local named = {}
    for _, b in ipairs(C._blocks) do if b:IsShown() then named[#named + 1] = b end end
    assert.same({ "Herbs", "Herbs" }, { textOf(named[1].name), textOf(named[2].name) })
    assert.equal("220 in bags, 600 in the Warband Bank", textOf(named[1].counts))
    assert.equal("50 in bags, 0 in the Warband Bank", textOf(named[2].counts))
    press(named[1].keep)
    assert.equal("How many of each item in Herbs to keep in your bags?", asked.opts.title)
    asked.opts.onCommit(30)
    assert.same({ v = GC.BankGroups.VERSION, groups = { herbs = 30 } }, GC.db.bankKeep)
    assert.equal("Keep in bags: 30 of each", named[1].keep.label)
    assert.equal("Keep in bags: 0 of each", named[2].keep.label)
    -- The same group, followed again from the site in German: its id stays, its name changes.
    file.rules[1].n = "Kräuter"
    GC.GroupRules.Adopt()
    GC.BankRoute.OnBagsChanged()
    local herbs = block("Kräuter")
    assert.equal("Keep in bags: 30 of each", herbs.keep.label)
    assert.equal("To bank: Bloom ×20 (1 left)", herbs.toBank.label)
    press(herbs.keep)
    assert.equal("How many of each item in Kräuter to keep in your bags?", asked.opts.title)
    assert.equal("30", asked.opts.text)
  end)

  -- A spell waiting for an item target turns the move into casting it on the item: the bank route's
  -- MoveStack refuses, and the card's press moves nothing.
  it("moves nothing while a spell waits for an item target", function()
    open()
    targeting = true
    press(block("Herbs").toBank)
    press(block("Herbs").toBags)
    assert.same({}, used)
    targeting = false
    press(block("Herbs").toBank)
    assert.equal(1, #used)
  end)

  it("shows nothing when no followed group has an item here", function()
    bags = { [0] = { info(9, 20) } }
    open()
    assert.is_false(cardUp())
  end)

  -- Most players follow no group: they see no card at all, and nothing is built or read for it.
  it("is not shown at all when no group is followed: builds nothing and reads no slot", function()
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    open()
    assert.is_nil(C._frame)
    assert.equal(0, reads)
    GC.BankRoute.OnBagsChanged()
    assert.is_nil(C._frame)
    assert.equal(0, reads)
  end)

  it("hides once the last followed group is gone, and reads no slot for it", function()
    open()
    assert.is_true(cardUp())
    _G.GoldCap_AppRuns = nil
    GC.GroupRules.Adopt()
    reads = 0
    GC.BankRoute.OnBagsChanged()
    assert.is_false(cardUp())
    assert.equal(0, reads)
  end)

  -- Compact: the keep count is a badge on the group's name line, the moves one under the other
  -- under the counts.
  it("puts the keep count on the group's name line, and the two moves under the counts", function()
    open()
    local herbs = block("Herbs")
    assert.equal(C._frame.content, herbs:GetParent())
    assert.same({ "TOPRIGHT", herbs, "TOPRIGHT", 0, 0 }, at(herbs.keep))
    assert.same({ "TOPLEFT", herbs, "TOPLEFT", 0, 0 }, at(herbs.name))
    assert.equal(herbs:GetWidth() - herbs.keep:GetWidth() - 4, herbs.name:GetWidth())
    local countsY, bankY, bagsY = at(herbs.counts)[5], at(herbs.toBank)[5], at(herbs.toBags)[5]
    assert.is_true(countsY > bankY and bankY > bagsY)
    -- A one-line name and counts: 18 + 2 + 14 + 4 + 22 + 4 + 22.
    assert.equal(86, herbs:GetHeight())
    -- The scroll clips at its edges, so no button in it draws the halo it would cut.
    for _, button in ipairs({ herbs.toBank, herbs.toBags }) do
      assert.is_true(button.glow == nil or not button.glow:IsShown())
    end
  end)

  -- A group with nothing to move (all of it kept in the bags, or staying there) is one line among
  -- others, not a block; the line opens them, so their keep count can still be changed.
  it("folds the groups with nothing to move into one line, which opens them below it", function()
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { Ore = 100 } }
    open()
    assert.is_nil(block("Ore"))
    assert.is_truthy(block("Herbs"))
    local fold = C._frame.fold
    assert.is_true(shown(fold))
    assert.equal("Groups with nothing to move: 1 ▼", fold.label)
    local foldAt = at(fold)
    press(fold)
    assert.equal("Groups with nothing to move: 1 ▲", fold.label)
    assert.same(foldAt, at(fold))
    local ore = block("Ore")
    assert.is_true(at(ore)[5] < foldAt[5])
    assert.equal("Keep in bags: 100 of each", ore.keep.label)
    assert.is_false(ore.toBank:IsEnabled())
    assert.is_false(ore.toBags:IsEnabled())
    press(fold)
    assert.is_nil(block("Ore"))
    assert.equal("Groups with nothing to move: 1 ▼", fold.label)
  end)

  it("shows no fold line when every group has something to move", function()
    open()
    assert.is_false(shown(C._frame.fold))
  end)

  -- A stack that stays has a reason to tell: its group is a block, not folded.
  it("never folds a group with a stack that stays in the bags", function()
    refundable["5:1"] = true
    open()
    local ore = block("Ore")
    assert.is_truthy(ore)
    assert.equal("Stays in bags: Bismuth ×50, can still be refunded", textOf(ore.stays[1]))
    assert.is_false(ore.toBank:IsEnabled())
    assert.is_false(shown(C._frame.fold))
  end)

  -- Folding a group the player is pressing would slide the blocks under it up into the cursor.
  it("keeps a group's block while the bank is open once it has shown, even with nothing left to move", function()
    open()
    local ore = block("Ore")
    local before = at(ore)
    press(ore.toBank)
    assert.equal(ore, block("Ore"))
    assert.same(before, at(ore))
    assert.is_false(shown(C._frame.fold))
    GC.BankRoute.OnBankClosed()
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { Ore = 100 } }
    open()
    assert.is_nil(block("Ore"))
  end)

  -- A TSM player brings 8 to 20 groups: the card stays on the screen, no taller than the room under
  -- its top, and the rest scrolls.
  it("stays on the screen with many groups: clamped, no taller than the room under its top, the rest scrolls", function()
    manyGroups(12)
    _G.BankFrame.GetTop = function() return 700 end
    open()
    local card = C._frame
    assert.is_true(W.state(card).clamped)
    assert.equal(700 - 80, card:GetHeight())
    local scroll, content = card.scroll, card.content
    assert.equal(content, scroll:GetScrollChild())
    assert.is_true(scroll:GetVerticalScrollRange() > 0)
    local names, lowest = {}, 0
    for _, b in ipairs(C._blocks) do
      if b:IsShown() then
        names[#names + 1] = textOf(b.name)
        assert.equal(content, b:GetParent())
        lowest = math.max(lowest, -at(b)[5] + b:GetHeight())
      end
    end
    assert.equal(12, #names)
    assert.equal(lowest, content:GetHeight())
    -- Few groups: as tall as they need.
    GC.BankRoute.OnBankClosed()
    manyGroups(1)
    open()
    assert.is_true(card:GetHeight() < 700 - 80)
    assert.equal(0, scroll:GetVerticalScrollRange())
  end)

  -- Its own column: beside the carry list, never under it, so the carry list growing, shrinking
  -- or emptying does not move the card. Once the carry list has shown, the card keeps that column
  -- until the bank closes.
  it("sits beside the carry list in its own column, else beside the bank window, and stays put while the bank is open", function()
    open()
    assert.same({ "TOPLEFT", _G.BankFrame, "TOPRIGHT", 4, 0 }, at(C._frame))
    assert.equal(1, #W.state(C._frame).points)
    local route = W.CreateFrame("Frame")
    route:Show()
    GC.BankRoute._frame = route
    GC.BankRoute.Refresh()
    assert.same({ "TOPLEFT", route, "TOPRIGHT", 4, 0 }, at(C._frame))
    route:SetHeight(400)
    GC.BankRoute.Refresh()
    route:Hide()
    GC.BankRoute.OnBagsChanged()
    assert.same({ "TOPLEFT", route, "TOPRIGHT", 4, 0 }, at(C._frame))
    -- A new visit starts beside whatever shows then.
    GC.BankRoute.OnBankClosed()
    open()
    assert.same({ "TOPLEFT", _G.BankFrame, "TOPRIGHT", 4, 0 }, at(C._frame))
    route:Show()
    GC.BankRoute.OnBankClosed()
    open()
    assert.same({ "TOPLEFT", route, "TOPRIGHT", 4, 0 }, at(C._frame))
  end)

  -- A newer GoldCap's keep counts cannot be read here, so To bank would ignore them: neither the
  -- keep count nor To bank is offered (To bank's row stays), To bags still is.
  it("offers neither the keep count nor To bank when a newer GoldCap saved the keep counts", function()
    GC.db.bankKeep = { v = GC.BankGroups.VERSION + 1 }
    open()
    local herbs = block("Herbs")
    assert.is_false(shown(herbs.keep))
    assert.is_false(shown(herbs.toBank))
    assert.is_nil(herbs.toBank.stack)
    assert.is_true(shown(herbs.toBags))
    assert.equal("To bags: Bloom ×600 (1 left)", herbs.toBags.label)
    -- Ore has nothing in the Warband Bank: nothing to move, so it folds.
    assert.is_nil(block("Ore"))
    press(herbs.toBank)
    assert.same({}, used)
    press(herbs.toBags)
    assert.same({ { n = 2, 12, 1 } }, used)
  end)

  -- Labels wrap and buttons are as wide as their words: a long item name in a long language widens
  -- the card instead of being cut.
  it("never cuts a label, in any language", function()
    NAMES[1] = "Verzauberte Blütenblätter der leuchtenden Hochenblume"
    bags[0][1] = info(1, 200)
    -- A stack that stays, in each group and toward each bank: the Warband Bank's refund and refusal,
    -- the character's own bank's refusal.
    refundable["0:2"], refusedHere["0:2"] = true, true
    bags[5][2] = info(3, 7)
    refused["5:2"], refusedHere["5:2"] = true, true
    bags[0][4] = info(4, 3)
    GC.db.bankKeep = { v = GC.BankGroups.VERSION, groups = { Cloth = 10 } }
    for _, code in ipairs(helper.localeCodes()) do
      helper.loadModule("Locale/" .. code .. ".lua", GC)
    end
    local runs = {}
    for _, code in ipairs(helper.localeCodes()) do
      runs[#runs + 1] = { code, ACCOUNT }
      runs[#runs + 1] = { code, CHARACTER }
    end
    for _, run in ipairs(runs) do
      local code, bankType = run[1], run[2]
      GC.ActivateLocale(code)
      showing = bankType
      open()
      local card = C._frame
      assert.is_true(W.state(card.title).wordWrap ~= false, code)
      assert.equal(card.content:GetWidth(), card.title:GetWidth(), code)
      -- The line naming the bank wraps at the card's width.
      assert.is_true(W.state(card.bank).wordWrap ~= false, code)
      assert.equal(card.content:GetWidth(), card.bank:GetWidth(), code)
      assert.is_true((card.bank:GetText() or "") ~= "", code)
      local fold = card.fold
      assert.is_true(shown(fold), code)
      assert.is_true(fold:GetWidth() >= fold.text:GetUnboundedStringWidth(), code .. " " .. fold.label)
      assert.is_true(card.content:GetWidth() >= fold:GetWidth(), code .. " " .. fold.label)
      for _, b in ipairs(C._blocks) do
        if b:IsShown() then
          local inner = card.content:GetWidth()
          assert.equal(inner, b:GetWidth(), code)
          local labels = { b.counts }
          for _, fs in ipairs(b.stays) do if fs:IsShown() then labels[#labels + 1] = fs end end
          assert.is_true(#labels > 1, code)
          for _, fs in ipairs(labels) do
            assert.is_true(W.state(fs).wordWrap ~= false, code)
            assert.equal(inner, fs:GetWidth(), code)
          end
          -- The name wraps beside the keep badge, never under 80px.
          assert.is_true(W.state(b.name).wordWrap ~= false, code)
          assert.is_true(b.name:GetWidth() >= 80, code)
          assert.is_true(b.name:GetWidth() + 4 + b.keep:GetWidth() <= inner, code)
          for _, button in ipairs({ b.keep, b.toBank, b.toBags }) do
            if button:IsShown() then
              assert.is_true(button:GetWidth() >= button.text:GetUnboundedStringWidth(), code .. " " .. button.label)
              assert.is_true(inner >= button:GetWidth(), code .. " " .. button.label)
            end
          end
        end
      end
      GC.BankRoute.OnBankClosed()
    end
    NAMES[1] = "Bloom"
  end)
end)
