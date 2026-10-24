local helper = require("spec.spec_helper")

-- At a bank (UI/BankRoute.lua): the one reader of the bags and a bank's tabs, the one move of a
-- stack and its guards, the bank the bank window shows, and what to carry between realms through the
-- Warband Bank, which the GoldCap Hoard's carry cards list (UI/HoardCarry.lua, its own spec in
-- spec/hoard_sections_spec.lua). This realm is Tarren Mill (1084); the account has a character on
-- Kazzak (1305). The bags, both banks and the payload are faked, shaped as the client's;
-- Core/SellRoute.lua is the real one.
describe("bank route", function()
  local GC, bags, used, timers, wue, canUse, reads, refused, refusedHere, tabs, shown, targeting, cursor
  local G = 10000
  -- Enum.BankType (Blizzard_APIDocumentationGenerated's ItemConstantsDocumentation.lua).
  local CHARACTER, ACCOUNT = 0, 2

  -- A window a bag click may feed instead of the bank: shown or not, as the client says.
  local function window()
    local w = { visible = false }
    function w:Show() self.visible = true end
    function w:Hide() self.visible = false end
    function w:IsShown() return self.visible end
    return w
  end

  local function info(itemID, name, over)
    local i = { itemID = itemID, itemName = name, stackCount = 1, iconFileID = itemID, isBound = false, isLocked = false }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
  end

  local function panel() return GC.BankRoute end
  local function stack(bag, slot, itemID) return { bag = bag, slot = slot, itemID = itemID } end

  before_each(function()
    used, timers, wue, canUse, tabs, shown = {}, {}, {}, true, { 12 }, nil
    -- SpellIsTargeting and GetCursorInfo, the client's, read by GC.Util.CursorBusy: no spell waits
    -- for a target and the cursor is empty unless a spec says otherwise.
    targeting, cursor = false, nil
    _G.SpellIsTargeting = function() return targeting end
    _G.GetCursorInfo = function() return cursor end
    -- 0: the backpack, with a flip that sells better on Kazzak (100) and one with no route (500);
    -- 12: the first Warband Bank tab, with a flip that sells best here (200).
    bags = {
      [0] = { info(100, "Gem-Inlaid Velvet Cinch"), info(500, "Linen Cloth") },
      [12] = { info(200, "Recipe: Ornate Plate") },
    }
    _G.Enum = { BankType = { Character = CHARACTER, Account = ACCOUNT } }
    _G.BankFrame = window()
    -- BankFrameMixin:GetActiveBankType (Blizzard_UIPanels_Game's BankFrame.lua): the bank the
    -- window shows, nil while its panel is hidden.
    function _G.BankFrame:GetActiveBankType() return shown end
    _G.MerchantFrame = window()
    _G.GetRealmName = function() return "Tarren Mill" end
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    -- refused: what the Warband Bank refuses; refusedHere: what the character's own bank does.
    reads, refused, refusedHere = 0, {}, {}
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
      GetContainerItemInfo = function(bag, slot) reads = reads + 1; return bags[bag] and bags[bag][slot] or nil end,
      UseContainerItem = function(...) used[#used + 1] = { n = select("#", ...), ... } end,
    }
    _G.C_Item = {
      IsBoundToAccountUntilEquip = function(loc) return wue[loc.bag .. ":" .. loc.slot] == true end,
      CanBeRefunded = function() return false end,
      GetCurrentItemLevel = function() return 0 end,
    }
    _G.C_Bank = {
      CanUseBank = function(t) return canUse and (t == ACCOUNT or t == CHARACTER) end,
      IsItemAllowedInBankType = function(t, loc)
        return not (t == CHARACTER and refusedHere or refused)[loc.bag .. ":" .. loc.slot]
      end,
      FetchPurchasedBankTabIDs = function(t)
        if t == ACCOUNT then return tabs end
        return t == CHARACTER and { 6 } or {}
      end,
    }
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    GC = helper.loadModule("Core/Util.lua")
    local spots = {
      [100] = { { realmId = 1305, list = 2200 * G, days = 2.4, own = true }, { realmId = 1084, list = 1500 * G, days = 1, own = true } },
      [200] = { { realmId = 1084, list = 900 * G, days = 0.5, own = true } },
    }
    local keys = { tarrenmill = 1084, kazzak = 1305 }
    local names = { [1084] = "Tarren Mill", [1305] = "Kazzak" }
    GC.Data = {
      SellSpots = function(id) return spots[id] end,
      FlipLevel = function() return nil end,
      RealmName = function(id) return names[id] end,
      RealmIdByKey = function(key) return keys[key] end,
      ClientRegion = function() return "eu" end,
    }
    GC.Ledger = { GetGold = function() return { { char = "Alt-Kazzak", region = "eu", copper = 1 } } end }
    helper.loadModule("Core/SellRoute.lua", GC)
    helper.loadModule("UI/BankRoute.lua", GC)
  end)

  after_each(function()
    _G.Enum, _G.BankFrame, _G.MerchantFrame, _G.GetRealmName = nil, nil, nil, nil
    _G.ItemLocation, _G.C_Container, _G.C_Item, _G.C_Bank, _G.C_Timer = nil, nil, nil, nil, nil
    _G.SpellIsTargeting, _G.GetCursorInfo = nil, nil
  end)

  -- ---------------------------------------------------------------------------------------------
  -- What to carry
  -- ---------------------------------------------------------------------------------------------

  it("calls the realm to carry to by the player's character's realm, not the payload's name for its market", function()
    GC.Data.RealmName = function(id) return ({ [1084] = "Tarren Mill", [1305] = "Kazzak-Market" })[id] end
    panel().OnBankOpened()
    local row = panel().Plan().putIn[1]
    assert.equal("for Kazzak: " .. GC.Util.FormatMoney(2200 * G) .. ", sells in about 2 days", panel().WhereText("in", row.spot))
  end)

  it("plans what to put in for another realm and what to take out to sell here, with where and for how much", function()
    panel().OnBankOpened()
    local plan = panel().Plan()
    assert.equal(1, #plan.putIn)
    assert.equal("Gem-Inlaid Velvet Cinch", plan.putIn[1].name)
    assert.same({ 0, 1 }, { plan.putIn[1].stacks[1].bag, plan.putIn[1].stacks[1].slot })
    assert.equal("for Kazzak: " .. GC.Util.FormatMoney(2200 * G) .. ", sells in about 2 days",
      panel().WhereText("in", plan.putIn[1].spot))
    assert.equal(1, #plan.takeOut)
    assert.equal("Recipe: Ornate Plate", plan.takeOut[1].name)
    assert.same({ 12, 1 }, { plan.takeOut[1].stacks[1].bag, plan.takeOut[1].stacks[1].slot })
    assert.equal("here: " .. GC.Util.FormatMoney(900 * G) .. ", sells within a day", panel().WhereText("out", plan.takeOut[1].spot))
  end)

  -- What sits in the Warband Bank can only be read at a bank.
  it("plans what to take out only while the bank is open", function()
    local plan = panel().Plan()
    assert.equal(1, #plan.putIn)
    assert.same({}, plan.takeOut)
  end)

  it("tells why a piece Warbound until equipped stays", function()
    wue["0:1"] = true
    panel().OnBankOpened()
    local plan = panel().Plan()
    assert.same({}, plan.putIn)
    assert.equal("Gem-Inlaid Velvet Cinch", plan.stuck[1].name)
    assert.equal("Warbound until equipped: the auction house refuses it", panel().WhereText("stuck", plan.stuck[1].spot))
  end)

  it("leaves out a stack the Warband Bank refuses, and a soulbound one", function()
    refused["0:1"] = true
    panel().OnBankOpened()
    assert.same({}, panel().Plan().putIn)
    assert.equal(1, #panel().Plan().takeOut)
    refused["0:1"] = nil
    bags[0][1] = info(100, "Gem-Inlaid Velvet Cinch", { isBound = true })
    assert.same({}, panel().Plan().putIn)
  end)

  -- The Hoard hands Plan what its paint read (UI/HoardFrame.lua): every stack, bound ones too, those
  -- in the bags marked against the bank its switch names. Plan takes the flips from it, leaves the
  -- bound ones out, and asks a stack marked against the character's own bank again against the
  -- Warband Bank, reading no slot itself.
  it("plans from the Hoard's read, asking a stack read against the character's bank again", function()
    refused["0:1"] = true
    bags[0][3] = info(100, "Gem-Inlaid Velvet Cinch", { isBound = true })
    panel().OnBankOpened()
    local all = { soulbound = true }
    local inBags = panel().ReadStacks({ 0 }, false, nil, CHARACTER, all)
    local inBank = panel().ReadStacks({ 12 }, true, nil, ACCOUNT, all)
    assert.is_nil(inBags[1].stays)
    reads = 0
    local asked = {}
    local plan = panel().Plan({ inBags = function() return inBags end, against = CHARACTER,
      inBank = function(bankType) asked[#asked + 1] = bankType return inBank end })
    assert.equal(0, reads)
    assert.same({ ACCOUNT }, asked)
    -- The cinch the Warband Bank refuses, and the bound one: neither is put in.
    assert.same({}, plan.putIn)
    assert.equal("Recipe: Ornate Plate", plan.takeOut[1].name)
    -- What the Hoard read is left as it was.
    assert.is_nil(inBags[1].stays)
    refused["0:1"] = nil
    plan = panel().Plan({ inBags = function() return inBags end, against = CHARACTER, inBank = function() return inBank end })
    assert.same({ 0, 1 }, { plan.putIn[1].stacks[1].bag, plan.putIn[1].stacks[1].slot })
    assert.equal(1, #plan.putIn[1].stacks)
  end)

  -- A player with no route data never sees a carry card: they pay nothing for it at a bank either.
  it("reads no bag for the plan without route data", function()
    _G.GetRealmName = function() return "Nowhere" end
    panel().OnBankOpened()
    local plan = panel().Plan()
    assert.same({ {}, {}, {} }, { plan.putIn, plan.takeOut, plan.stuck })
    assert.equal(0, reads)
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The reader
  -- ---------------------------------------------------------------------------------------------

  -- The reader the Hoard shares (UI/HoardFrame.lua) says why a stack in the bags stays
  -- there: still refundable first (Blizzard asks before ending a refund), else refused by the
  -- Warband Bank. A stack already in the Warband Bank stays nowhere.
  it("reads why a stack in the bags stays there: still refundable, or refused by the Warband Bank", function()
    local refundable = {}
    _G.C_Item.CanBeRefunded = function(loc) return refundable[loc.bag .. ":" .. loc.slot] == true end
    refundable["0:1"], refused["0:1"], refused["0:2"], refused["12:1"] = true, true, true, true
    panel().OnBankOpened()
    local all = function() return true end
    local inBags = panel().ReadStacks({ 0 }, false, all, ACCOUNT)
    assert.equal("refund", inBags[1].stays)
    assert.equal("refused", inBags[2].stays)
    assert.is_nil(panel().ReadStacks({ 12 }, true, all, ACCOUNT)[1].stays)
    refundable["0:1"], refused["0:1"] = nil, nil
    assert.is_nil(panel().ReadStacks({ 0 }, false, all, ACCOUNT)[1].stays)
  end)

  -- Blizzard asks before a deposit into the Warband Bank ends a refund, and deposits into the
  -- character's own bank without asking (BankFrame.lua's BankUtil_IsAccountBankDepositRefundable,
  -- ContainerFrame.lua's right click): toward the character's bank a refundable stack may go, and
  -- what stays is what that bank refuses.
  it("reads why a stack stays against the bank it would go into: the character's own bank takes a refundable one", function()
    _G.C_Item.CanBeRefunded = function(loc) return loc.bag == 0 and loc.slot == 1 end
    refused["0:2"], refusedHere["0:1"] = true, nil
    panel().OnBankOpened()
    local all = function() return true end
    local inBags = panel().ReadStacks({ 0 }, false, all, CHARACTER)
    assert.is_nil(inBags[1].stays)
    assert.is_nil(inBags[2].stays)
    refusedHere["0:2"] = true
    assert.equal("refused", panel().ReadStacks({ 0 }, false, all, CHARACTER)[2].stays)
    assert.equal("refund", panel().ReadStacks({ 0 }, false, all, ACCOUNT)[1].stays)
  end)

  -- The one move takes the bank it moves to or from, and keeps every guard for that bank.
  describe("MoveStack", function()
    before_each(function()
      bags[6] = { info(300, "Bloom") }
      panel().OnBankOpened()
    end)

    it("deposits into the bank it is handed, and withdraws from a tab of it", function()
      assert.is_true(panel().MoveStack(stack(0, 1, 100), true, CHARACTER))
      assert.is_true(panel().MoveStack(stack(6, 1, 300), false, CHARACTER))
      assert.is_true(panel().MoveStack(stack(0, 2, 500), true, ACCOUNT))
      assert.same({ { n = 5, 0, 1, nil, CHARACTER, false }, { n = 2, 6, 1 }, { n = 5, 0, 2, nil, ACCOUNT, false } }, used)
    end)

    it("moves nothing either way while a spell waits for an item target or the cursor carries something", function()
      targeting = true
      assert.is_false(panel().MoveStack(stack(0, 1, 100), true, CHARACTER))
      assert.is_false(panel().MoveStack(stack(6, 1, 300), false, CHARACTER))
      targeting, cursor = false, "item"
      assert.is_false(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
      assert.is_false(panel().MoveStack(stack(12, 1, 200), false, ACCOUNT))
      assert.same({}, used)
    end)

    it("moves nothing when handed no bank, or one it cannot use here", function()
      assert.is_false(panel().MoveStack(stack(0, 1, 100), true, nil))
      assert.is_false(panel().MoveStack(stack(6, 1, 300), false, nil))
      _G.C_Bank.CanUseBank = function(t) return t == ACCOUNT end
      assert.is_false(panel().MoveStack(stack(0, 1, 100), true, CHARACTER))
      assert.is_false(panel().MoveStack(stack(6, 1, 300), false, CHARACTER))
      assert.same({}, used)
    end)

    it("puts a refundable stack only in the character's own bank, and nothing a bank refuses into it", function()
      _G.C_Item.CanBeRefunded = function() return true end
      assert.is_false(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
      refusedHere["0:2"] = true
      assert.is_false(panel().MoveStack(stack(0, 2, 500), true, CHARACTER))
      assert.is_true(panel().MoveStack(stack(0, 1, 100), true, CHARACTER))
      assert.same({ { n = 5, 0, 1, nil, CHARACTER, false } }, used)
    end)
  end)

  -- What Blizzard's own right click on a bag item deposits into (ContainerFrame.lua).
  it("names the bank the bank window shows, the Warband Bank when it answers neither", function()
    assert.equal(ACCOUNT, panel().ShownBankType())
    shown = CHARACTER
    assert.equal(CHARACTER, panel().ShownBankType())
    shown = ACCOUNT
    assert.equal(ACCOUNT, panel().ShownBankType())
    function _G.BankFrame:GetActiveBankType() error("no panel") end
    assert.equal(ACCOUNT, panel().ShownBankType())
    _G.BankFrame = nil
    assert.equal(ACCOUNT, panel().ShownBankType())
  end)

  -- The Hoard's Make room moves soulbound stacks into the character's own bank, and its Put back and
  -- For your crafts take them out of it; the Warband Bank refuses one, so against it one in the
  -- bags stays, refused, as Blizzard's own bags dim it (C_Bank.IsItemAllowedInBankType,
  -- Blizzard_FrameXMLUtil's ItemUtil.lua). Without the option they are left out, as before.
  it("reads soulbound stacks only when asked, and marks one in the bags the Warband Bank refuses", function()
    bags[0][1] = info(100, "Gem-Inlaid Velvet Cinch", { isBound = true })
    bags[6] = { info(300, "Bloom", { isBound = true }) }
    local isAllowed = _G.C_Bank.IsItemAllowedInBankType
    _G.C_Bank.IsItemAllowedInBankType = function(t, loc)
      if t == ACCOUNT and bags[loc.bag][loc.slot].isBound then return false end
      return isAllowed(t, loc)
    end
    panel().OnBankOpened()
    local all = function() return true end
    assert.same({ 500 }, { panel().ReadStacks({ 0 }, false, all, CHARACTER)[1].itemID })
    local withBound = panel().ReadStacks({ 0 }, false, all, CHARACTER, { soulbound = true })
    assert.same({ 100, 500 }, { withBound[1].itemID, withBound[2].itemID })
    assert.is_nil(withBound[1].stays)
    -- Marked, for a reader that leaves them out to tell them; with no `wanted`, every stack.
    assert.same({ true }, { withBound[1].bound, withBound[2].bound })
    assert.equal(2, #panel().ReadStacks({ 0 }, false, nil, CHARACTER, { soulbound = true }))
    local againstWarband = panel().ReadStacks({ 0 }, false, all, ACCOUNT, { soulbound = true })
    assert.equal("refused", againstWarband[1].stays)
    assert.is_nil(againstWarband[2].stays)
    assert.same({}, panel().ReadStacks({ 6 }, true, all, CHARACTER))
    assert.equal(300, panel().ReadStacks({ 6 }, true, all, CHARACTER, { soulbound = true })[1].itemID)
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The move and its guards
  -- ---------------------------------------------------------------------------------------------

  -- The same call equips a piece of gear with no bank open, which binds it, and sells it to an open
  -- vendor: a move checks first, and does nothing.
  it("moves nothing once the bank has closed, while a vendor is open, or when the bank is out of reach", function()
    panel().OnBankOpened()
    panel().OnBankClosed()
    assert.is_false(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
    assert.same({}, used)
    panel().OnBankOpened()
    _G.MerchantFrame:Show()
    assert.is_false(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
    assert.same({}, used)
    _G.MerchantFrame:Hide()
    canUse = false
    assert.is_false(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
    assert.same({}, used)
    canUse = true
    assert.is_true(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false } }, used)
  end)

  -- Blizzard's own list of windows a bag click feeds instead (ContainerFrame.lua): the mailbox on
  -- either tab, the guild bank and the rest move nothing either.
  it("moves nothing while another window a bag click feeds is open", function()
    panel().OnBankOpened()
    for _, name in ipairs({ "MailFrame", "GuildBankFrame", "TradeFrame", "AuctionHouseFrame", "ItemUpgradeFrame",
        "ObliterumForgeFrame", "ChallengesKeystoneFrame", "AzeriteRespecFrame", "RuneforgeFrame" }) do
      _G[name] = window()
      _G[name]:Show()
      assert.is_false(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT), name)
      assert.same({}, used, name)
      _G[name] = nil
    end
    assert.is_true(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
    assert.equal(1, #used)
  end)

  -- With a spell waiting for an item target (Disenchant, an enchant scroll) the same call casts it
  -- on the item, and with something on the cursor it does something else again. A read that fails
  -- counts as busy.
  it("moves nothing while a read of the cursor fails", function()
    panel().OnBankOpened()
    _G.SpellIsTargeting = function() error("no such function") end
    assert.is_false(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
    assert.same({}, used)
    _G.SpellIsTargeting = function() return false end
    assert.is_true(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
    assert.equal(1, #used)
  end)

  it("moves nothing when the slot no longer holds the item, or it is locked", function()
    panel().OnBankOpened()
    bags[0][1] = info(500, "Linen Cloth")
    assert.is_false(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
    bags[0][1] = info(100, "Gem-Inlaid Velvet Cinch", { isLocked = true })
    assert.is_false(panel().MoveStack(stack(0, 1, 100), true, ACCOUNT))
    assert.same({}, used)
  end)

  -- ---------------------------------------------------------------------------------------------
  -- The bank events
  -- ---------------------------------------------------------------------------------------------

  -- Sorting the Warband Bank or depositing everything moves hundreds of slots, one event each, and a
  -- move into it comes with a BAG_UPDATE_DELAYED too: each is handed on as the bags' change while
  -- the bank is open, and the Hoard, which hooks OnBagsChanged, paints once on the next frame for
  -- all of them (spec/hoard_sections_spec.lua).
  it("hands each Warband Bank slot change on as the bags' change while the bank is open, and none with it closed", function()
    local heard = 0
    local onBags = panel().OnBagsChanged
    panel().OnBagsChanged = function() heard = heard + 1; onBags() end
    for _ = 1, 50 do panel().OnTabSlotsChanged() end
    assert.equal(0, heard)
    panel().OnBankOpened()
    for _ = 1, 50 do panel().OnTabSlotsChanged() end
    assert.equal(50, heard)
    assert.equal(0, #timers)
    panel().OnBankClosed()
    panel().OnTabSlotsChanged()
    assert.equal(50, heard)
  end)

  it("keeps whether the bank is open", function()
    assert.is_falsy(panel()._open)
    panel().OnBankOpened()
    assert.is_true(panel()._open)
    panel().OnBankClosed()
    assert.is_false(panel()._open)
  end)

  describe("/gc route", function()
    local printed
    before_each(function()
      printed = {}
      GC.Print = function(text) printed[#printed + 1] = text end
    end)

    it("prints what in the bags to take to which realm, and that the Warband Bank's half waits for a bank", function()
      GC.slashHandlers.route()
      assert.same({
        "Gem-Inlaid Velvet Cinch: for Kazzak: " .. GC.Util.FormatMoney(2200 * G) .. ", sells in about 2 days",
        "What to take out of the Warband Bank shows at a bank.",
      }, printed)
    end)

    it("prints the Warband Bank's half too at a bank", function()
      panel().OnBankOpened()
      GC.slashHandlers.route()
      assert.equal("Recipe: Ornate Plate: here: " .. GC.Util.FormatMoney(900 * G) .. ", sells within a day", printed[2])
      assert.equal(2, #printed)
    end)

    it("says when nothing needs carrying, and when there is nothing to go on", function()
      bags[0] = {}
      GC.slashHandlers.route()
      assert.same({ "Nothing in your bags sells notably better on another of your realms.",
        "What to take out of the Warband Bank shows at a bank." }, printed)
      printed = {}
      GC.Data.RealmIdByKey = function() return nil end
      GC.SellRoute._here = nil
      GC.slashHandlers.route()
      assert.same({ "Where each flip sells comes with the Companion's region data: nothing to go on yet." }, printed)
    end)
  end)

  describe("wiring", function()
    local function read(path)
      local f = assert(io.open(path, "r"))
      local t = f:read("*a")
      f:close()
      return (t:gsub("%-%-[^\n]*", ""))
    end

    -- The one place the addon moves an item between the bags and a bank is the route's MoveStack,
    -- one call each time, reached only from the GoldCap Hoard's press (UI/HoardFrame.lua), which its
    -- move buttons' onMoveClick starts. A row of the Hoard (UI/HoardRow.lua) builds and paints those
    -- buttons and moves nothing itself, and nor do its search row, checkboxes, selection bar and cast
    -- bars (UI/HoardList.lua), its tiles (UI/HoardTiles.lua), its carry cards (UI/HoardCarry.lua) and
    -- its footer (UI/HoardFooter.lua): each section's buttons are the window's move buttons.
    local ROUTE, HOARD, ROW = "GoldCap/UI/BankRoute.lua", "GoldCap/UI/HoardFrame.lua", "GoldCap/UI/HoardRow.lua"
    local LIST = "GoldCap/UI/HoardList.lua"
    local SECTIONS = { "GoldCap/UI/HoardTiles.lua", "GoldCap/UI/HoardCarry.lua", "GoldCap/UI/HoardFooter.lua" }

    local function bodyOf(text, header)
      local from = assert(text:find(header, 1, true), header)
      return text:sub(from, assert(text:find("\nend\n", from, true), header)), from
    end

    local function count(text, needle)
      local n, at = 0, 1
      while true do
        local i = text:find(needle, at, true)
        if not i then return n end
        n, at = n + 1, i + #needle
      end
    end

    it("calls UseContainerItem only inside MoveStack: to deposit and to withdraw, once each", function()
      local listing = assert(io.popen("find GoldCap -name '*.lua'"))
      for path in listing:lines() do
        -- The vendor sell card makes its own sale call; spec/vendor_sell_wiring_spec.lua audits it.
        if path ~= ROUTE and path ~= "GoldCap/UI/VendorSellCard.lua" then
          assert.is_nil(read(path):find("UseContainerItem", 1, true), path)
        end
      end
      listing:close()
      local text = read(ROUTE)
      local body, from = bodyOf(text, "function P.MoveStack(")
      local outside = text:sub(1, from - 1) .. text:sub(from + #body)
      assert.is_nil(outside:find("UseContainerItem", 1, true))
      assert.equal(2, count(body, "UseContainerItem"))
      -- Into the bank it is handed, as Blizzard's own right click on a bag item deposits.
      assert.equal(1, count(body, "C_Container.UseContainerItem(stack.bag, stack.slot, nil, bankType, false)"))
      assert.equal(1, count(body, "C_Container.UseContainerItem(stack.bag, stack.slot)"))
      assert.is_truthy(body:find("function P.MoveStack(stack, into, bankType)", 1, true))
      -- Every guard is for that bank, before either call, and the cursor is asked first too.
      local first = assert(body:find("C_Container.UseContainerItem(", 1, true))
      assert.is_true(assert(body:find("bankIsTheWindow(bankType)", 1, true)) < first)
      assert.is_true(assert(body:find("if GC.Util.CursorBusy() then return false end", 1, true)) < first)
      assert.is_true(assert(body:find("staysWhy(loc, bankType)", 1, true)) < first)
    end)

    -- The carry cards hand items to another character, which only the Warband Bank does: their
    -- buttons name it, and a move button's click hands the bank it names to the press. The rest of
    -- the Hoard moves to and from the bank its switch names, the one its last paint read and planned
    -- with: its press names that bank on every stack, and the machine hands it on.
    it("hands MoveStack the Warband Bank from a carry card and the switch's bank from the rest of the Hoard", function()
      local carry = read(SECTIONS[2])
      assert.equal(1, count(carry, ".bankType = Enum.BankType.Account"))
      for _, path in ipairs({ SECTIONS[1], SECTIONS[3] }) do assert.is_nil(read(path):find("%.bankType%s*=[^=]"), path) end
      local hoard = read(HOARD)
      local row = bodyOf(hoard, "local function moveRow(")
      assert.is_truthy(row:find("GC.BankRoute.MoveStack(row.stack, row.into, row.bankType)", 1, true))
      local pressBody = bodyOf(hoard, "function HF.Press(")
      assert.is_truthy(pressBody:find("if bankType == nil then bankType = HF._bankType end", 1, true))
      assert.is_truthy(pressBody:find("into = into, bankType = bankType }", 1, true))
      -- A paint reads for the bank the switch names: the bags marked against it, and its tabs.
      local refresh = bodyOf(hoard, "local function refresh(")
      local chosen = assert(refresh:find("local bankType = HF._bankType", 1, true))
      assert.is_true(chosen < assert(refresh:find("reading = newReading(bankType)", 1, true)))
      assert.is_true(chosen < assert(refresh:find("bankOf(reading, bankType)", 1, true)))
      assert.is_truthy(bodyOf(hoard, "local function bagsOf("):find(
        "GC.BankRoute.ReadStacks(BAGS, false, nil, reading.bankType, ALL)", 1, true))
      assert.is_truthy(bodyOf(hoard, "local function bankOf("):find(
        "GC.BankRoute.ReadStacks(tabs, true, nil, bankType, ALL)", 1, true))
      -- The bank is set only by a paint, the switch's own click, and a new visit (the bank opening
      -- or closing); the switch's click moves nothing.
      -- A line that assigns to HF._bankType: it stands left of the line's first lone `=`.
      local function sets(text)
        local n = 0
        for line in text:gmatch("[^\n]+") do
          local left = line:match("^(.-[^=~<>])=[^=]")
          if left and left:find("HF._bankType", 1, true) then n = n + 1 end
        end
        return n
      end
      local click = bodyOf(hoard, "local function onBankClick(")
      local visit = bodyOf(hoard, "local function newVisit(")
      -- Plus its declaration at the top of the file.
      assert.equal(sets(hoard), 1 + sets(refresh) + sets(click) + sets(visit))
      assert.equal(1, sets(click))
      assert.equal(0, sets(read(ROW)))
      -- Its definition, and the bank opening and closing.
      assert.equal(3, count(hoard, "newVisit("))
      assert.equal(1, count(bodyOf(hoard, "function HF.OnBankOpened("), "newVisit()"))
      assert.equal(1, count(bodyOf(hoard, "function HF.OnBankClosed("), "newVisit()"))
      assert.is_nil(click:find("MoveStack", 1, true))
      assert.is_nil(click:find("UseContainerItem", 1, true))
      assert.is_nil(click:find("Press(", 1, true))
      -- Its only use: the click of each side of the switch, as the switch builder sets it.
      assert.equal('frame.choice = newSwitch(frame, "bankType", { banks() }, onBankClick)',
        hoard:match("[^\n]*onBankClick%)[^\n]*"):match("^%s*(.-)%s*$"))
      assert.equal(2, count(hoard, "onBankClick"))
      local switch = bodyOf(hoard, "local function newSwitch(")
      assert.equal(1, count(switch, 'side:SetScript("OnClick", onClick)'))
      assert.equal(2, count(switch, "onClick"))
    end)

    -- A switch of the bank window's tab repaints the Hoard through a post-hook on Blizzard's bank
    -- panel, on the next frame. The hook reads and paints, nothing more: no move is ever made
    -- outside a click, and nothing of the Hoard runs inside Blizzard's call.
    it("follows a switch of the bank window's tab through a post-hook that moves nothing", function()
      local hoard = read(HOARD)
      -- The route's three handlers, and the bank panel's Reset.
      assert.equal(4, count(hoard, "hooksecurefunc("))
      assert.equal(1, count(hoard, 'hooksecurefunc(bankPanel, "Reset", HF.OnBankShown)'))
      assert.is_truthy(hoard:find("local bankPanel = _G.BankPanel", 1, true))
      local shownBody = bodyOf(hoard, "function HF.OnBankShown(")
      for _, needle in ipairs({ "MoveStack", "UseContainerItem", "onMoveClick", "OnClick", "Press(", "refresh(" }) do
        assert.is_nil(shownBody:find(needle, 1, true), needle)
      end
      -- It hands on to the window's own bag change, which paints on the next frame.
      assert.is_truthy(shownBody:find("HF.OnBagsChanged()", 1, true))
      local bagsBody = bodyOf(hoard, "function HF.OnBagsChanged(")
      assert.is_truthy(bagsBody:find("C_Timer.After(0, function()", 1, true))
      for _, needle in ipairs({ "MoveStack", "UseContainerItem", "onMoveClick", "OnClick", "Press(" }) do
        assert.is_nil(bagsBody:find(needle, 1, true), needle)
      end
      assert.is_nil(read(ROW):find("hooksecurefunc", 1, true))
      assert.is_nil(read(LIST):find("hooksecurefunc", 1, true))
      for _, path in ipairs(SECTIONS) do assert.is_nil(read(path):find("hooksecurefunc", 1, true), path) end
      assert.is_nil(read(ROUTE):find("hooksecurefunc", 1, true))
      for line in hoard:gmatch("[^\n]*hooksecurefunc%([^\n]*") do
        assert.is_nil(line:find("onMoveClick", 1, true), line)
        assert.is_nil(line:find("MoveStack", 1, true), line)
        assert.is_nil(line:find("Press", 1, true), line)
      end
    end)

    -- The Hoard's moves are its press's (Core/VendorPress.lua): the first inside the move button's
    -- click, the rest from the machine's timers, each through the Hoard's moveRow, which is the
    -- machine's call and nothing else's. Its press is started, inside the Hoard's files, by the move
    -- button's click alone.
    it("reaches MoveStack only from the Hoard's press, once", function()
      local listing = assert(io.popen("find GoldCap -name '*.lua'"))
      for path in listing:lines() do
        if path ~= ROUTE and path ~= HOARD then
          assert.is_nil(read(path):find("MoveStack", 1, true), path)
        end
      end
      listing:close()
      local function without(text, body)
        local at = assert(text:find(body, 1, true))
        return text:sub(1, at - 1) .. text:sub(at + #body)
      end
      local route, hoard = read(ROUTE), read(HOARD)
      local def = bodyOf(route, "function P.MoveStack(")
      assert.is_nil(without(route, def):find("MoveStack", 1, true))
      assert.equal(1, count(def, "MoveStack"))
      local row = bodyOf(hoard, "local function moveRow(")
      assert.is_nil(without(hoard, row):find("MoveStack", 1, true))
      assert.equal(1, count(row, "GC.BankRoute.MoveStack("))
      -- Its definition and the machine's driver, nothing more.
      assert.equal(2, count(hoard, "moveRow"))
      assert.equal(1, count(hoard, "      use = moveRow,"))
      -- The machine is started by Press alone, and Press by the move button's click.
      assert.equal(1, count(hoard, ":Press("))
      assert.equal(1, count(bodyOf(hoard, "function HF.Press("), "machine:Press(rows)"))
      assert.equal(2, count(hoard, "HF.Press("))
      assert.equal(1, count(bodyOf(hoard, "local function onMoveClick("),
        "HF.Press(button, button.stacks, button.into, button.bankType)"))
      for _, path in ipairs({ ROW, LIST, SECTIONS[1], SECTIONS[2], SECTIONS[3] }) do
        assert.is_nil(read(path):find("Press(", 1, true), path)
        assert.is_nil(read(path):find("UseContainerItem", 1, true), path)
      end
    end)

    -- A paint of the Hoard reads each slot once (UI/HoardFrame.lua's newReading, bagsOf, bankOf):
    -- its rows, its list and its parts take what they want from what the paint read, and none of
    -- them reads a slot of its own.
    it("reads the bags and the banks for the Hoard in its window's paint alone", function()
      for _, path in ipairs({ ROW, LIST, SECTIONS[1], SECTIONS[2], SECTIONS[3] }) do
        local text = read(path)
        for _, needle in ipairs({ "ReadStacks", "BankTabs", "GetContainerItemInfo", "GetContainerNumFreeSlots" }) do
          assert.is_nil(text:find(needle, 1, true), path .. " " .. needle)
        end
      end
      local hoard = read(HOARD)
      assert.equal(2, count(hoard, "ReadStacks("))
      assert.equal(1, count(bodyOf(hoard, "local function bagsOf("), "ReadStacks("))
      assert.equal(1, count(bodyOf(hoard, "local function bankOf("), "ReadStacks("))
    end)

    -- No timer of these files moves anything: the Hoard's moves after the first come from the press
    -- machine's own timers (its driver's `after`), each through moveRow and its re-checks.
    it("reaches each click handler only through its button's OnClick, and moves nothing from a timer of its own", function()
      for path, handler in pairs({ [HOARD] = "onMoveClick" }) do
        local text = read(path)
        local sites = {}
        for line in text:gmatch("[^\n]*" .. handler .. "[^\n]*") do sites[#sites + 1] = line:match("^%s*(.-)%s*$") end
        assert.same({ "local function " .. handler .. "(button)", 'button:SetScript("OnClick", ' .. handler .. ")" }, sites)
        for body in text:gmatch("C_Timer%.After%b()") do
          assert.is_nil(body:find("UseContainerItem", 1, true), path)
          assert.is_nil(body:find("MoveStack", 1, true), path)
          assert.is_nil(body:find(handler, 1, true), path)
          assert.is_nil(body:find("moveRow", 1, true), path)
          assert.is_nil(body:find("Press(", 1, true), path)
        end
      end
      assert.is_nil(read(ROW):find("C_Timer", 1, true))
      assert.is_nil(read(LIST):find("C_Timer", 1, true))
      -- A section's buttons are the window's move buttons: none sets a click of its own, and none
      -- has a timer.
      for _, path in ipairs(SECTIONS) do
        assert.is_nil(read(path):find("C_Timer", 1, true), path)
        assert.is_nil(read(path):find('SetScript("OnClick"', 1, true), path)
      end
      assert.equal(1, count(read(HOARD), "after = function(seconds, fn) C_Timer.After(seconds, fn) end,"))
    end)

    -- The Hoard's click disables nothing itself: it starts its press (the first move), then
    -- repaints, and only the repaint disables a button whose list is now empty (paintMove).
    it("puts a button to sleep only in the repaint after its call", function()
      local hoard = read(HOARD)
      assert.is_nil(bodyOf(hoard, "local function onMoveClick("):find("Disable(", 1, true))
      local pressBody = bodyOf(hoard, "function HF.Press(")
      assert.is_nil(pressBody:find("Disable(", 1, true))
      assert.is_true(assert(pressBody:find("machine:Press(rows)", 1, true)) < assert(pressBody:find("HF.Refresh(true)", 1, true)))
      local paint = bodyOf(hoard, "local function paintMove(")
      assert.equal(1, count(paint, "button:Disable()"))
      -- Store all and Take all out, each row's Store and Take out and the selection bar's, through
      -- the same repaint: the pair's (UI/HoardList.lua), which paints each one that is not a Stop.
      local list = read(LIST)
      assert.is_nil(list:find("Disable(", 1, true))
      assert.equal(1, count(bodyOf(list, "function HL.PaintPair("), "U.paintMove(button, entry[2], entry[3])"))
      assert.is_truthy(bodyOf(hoard, "local function paintAll("):find("HF.List.PaintPair({ { frame.storeAll, lists.toBank,", 1, true))
      assert.equal(1, count(bodyOf(list, "function HL.PaintSelection("), "HL.PaintPair({ { bar.store, sel.toBank,"))
      local row = read(ROW)
      assert.is_nil(row:find("Disable(", 1, true))
      assert.equal(1, count(row, "HF.List.PaintPair({ { row.store, data.toBank,"))
      assert.equal(1, count(row, "{ row.take, data.toBags,"))
      -- The only other: a side of the bank switch a bank cannot use, which moves nothing anyway.
      assert.equal(2, count(hoard, "Disable("))
      assert.equal(1, count(bodyOf(hoard, "local function paintChoice("), "side:Disable()"))
    end)

    it("loads in retail only, the Hoard after the route module", function()
      local retail, forever = read("GoldCap/GoldCap.toc"), read("GoldCap/GoldCap_Camelot.toc")
      for _, file in ipairs({ "UI/BankRoute.lua", "UI/HoardFrame.lua", "UI/HoardRow.lua", "UI/HoardList.lua",
        "UI/HoardTiles.lua", "UI/HoardCarry.lua", "UI/HoardFooter.lua", "Core/BankGroups.lua", "Core/Hoard.lua" }) do
        assert.is_truthy(retail:find("\n" .. file .. "\n", 1, true), file)
      end
      for _, name in ipairs({ "BankRoute", "BankGroups", "Hoard" }) do
        assert.is_nil(forever:find(name, 1, true), name)
      end
      -- The bank tab and the bank by group card it held are gone.
      assert.is_nil(retail:find("BankTab", 1, true))
      assert.is_nil(retail:find("BankGroupsCard", 1, true))
      assert.is_true(retail:find("Core/SellRoute.lua", 1, true) < retail:find("UI/BankRoute.lua", 1, true))
      -- The Hoard hooks the route's handlers as it loads, and its rows read what it shares.
      assert.is_true(retail:find("UI/BankRoute.lua", 1, true) < retail:find("UI/HoardFrame.lua", 1, true))
      assert.is_true(retail:find("UI/HoardFrame.lua", 1, true) < retail:find("UI/HoardRow.lua", 1, true))
      assert.is_true(retail:find("UI/HoardRow.lua", 1, true) < retail:find("UI/HoardList.lua", 1, true))
      -- The sections build on the window, its rows and its list.
      assert.is_true(retail:find("UI/HoardList.lua", 1, true) < retail:find("UI/HoardTiles.lua", 1, true))
      assert.is_true(retail:find("UI/HoardTiles.lua", 1, true) < retail:find("UI/HoardCarry.lua", 1, true))
      assert.is_true(retail:find("UI/HoardCarry.lua", 1, true) < retail:find("UI/HoardFooter.lua", 1, true))
      assert.is_true(retail:find("Core/GroupRules.lua", 1, true) < retail:find("Core/BankGroups.lua", 1, true))
      assert.is_true(retail:find("Core/BankGroups.lua", 1, true) < retail:find("Core/Hoard.lua", 1, true))
    end)

    it("is routed from the event frame", function()
      local init = read("GoldCap/Core/Init.lua")
      for _, event in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" }) do
        assert.is_truthy(init:find('"' .. event .. '"', 1, true), event)
      end
      for _, name in ipairs({ "OnBankOpened", "OnBankClosed", "OnBagsChanged", "OnTabSlotsChanged" }) do
        assert.is_truthy(init:find("GC.BankRoute." .. name, 1, true), name)
      end
    end)
  end)
end)
