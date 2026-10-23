local helper = require("spec.spec_helper")

-- At a bank: what to carry between realms through the Warband Bank (UI/BankRoute.lua). This realm is
-- Tarren Mill (1084); the account has a character on Kazzak (1305). The bags, the Warband Bank and
-- the payload are faked; Core/SellRoute.lua is the real one.
describe("bank carry list", function()
  local GC, bags, used, timers, wue, canUse, reads, refused, refusedHere, tabs, shown, targeting, cursor
  local G = 10000
  -- Enum.BankType (Blizzard_APIDocumentationGenerated's ItemConstantsDocumentation.lua).
  local CHARACTER, ACCOUNT = 0, 2

  local function region(kind)
    local r = { kind = kind, visible = false, enabled = true, scripts = {} }
    function r:SetPoint() end
    function r:ClearAllPoints() end
    function r:SetSize() end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:SetJustifyH() end
    function r:SetWordWrap() end
    function r:SetTextColor() end
    function r:SetTexture(t) self.texture = t end
    function r:SetText(t) self.textValue = t end
    function r:GetText() return self.textValue end
    function r:GetStringHeight() return 12 end
    function r:GetUnboundedStringWidth() return 8 * #(self.textValue or "") end
    function r:Show() self.visible = true end
    function r:Hide() self.visible = false end
    function r:IsShown() return self.visible end
    function r:EnableMouse() end
    function r:SetClampedToScreen() end
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:CreateTexture() return region("Texture") end
    -- The list's scroll: UIPanelScrollFrameTemplate's ScrollFrame, without its bar.
    function r:SetScrollChild(child) self.child = child end
    function r:GetParent() return self.parent end
    return r
  end

  local function button()
    local b = region("Button")
    b.text = region("FontString")
    function b:SetLabel(text) self.label = text; self.text:SetText(text) end
    function b:SetVariant() end
    function b:Enable() self.enabled = true end
    function b:Disable() self.enabled = false end
    return b
  end

  local function info(itemID, name, over)
    local i = { itemID = itemID, itemName = name, stackCount = 1, iconFileID = itemID, isBound = false, isLocked = false }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
  end

  local function panel() return GC.BankRoute end
  local function rowFor(label)
    for _, row in ipairs(panel()._rows) do
      if row.visible and row.button.label == label then return row end
    end
  end
  local function press(row) row.button.scripts.OnClick(row.button) end

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
    _G.CreateFrame = function(kind) return region(kind) end
    _G.UIParent = region("Frame")
    _G.BankFrame = region("Frame")
    -- BankFrameMixin:GetActiveBankType (Blizzard_UIPanels_Game's BankFrame.lua): the bank the
    -- window shows, nil while its panel is hidden.
    function _G.BankFrame:GetActiveBankType() return shown end
    _G.MerchantFrame = region("Frame")
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
    GC.Theme = {
      color = { panel = { 0, 0, 0 }, border = { 1, 1, 1 }, gold = { 1, 0.8, 0 }, fg = { 1, 1, 1 }, fgDim = { 0.5, 0.5, 0.5 } },
      pad = { m = 12 },
      Card = function() return region("Frame") end,
      Label = function() return region("FontString") end,
      Num = function() return region("FontString") end,
      Button = function() return button() end,
    }
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
    _G.Enum, _G.CreateFrame, _G.UIParent, _G.BankFrame, _G.MerchantFrame, _G.GetRealmName = nil, nil, nil, nil, nil, nil
    _G.ItemLocation, _G.C_Container, _G.C_Item, _G.C_Bank, _G.C_Timer = nil, nil, nil, nil, nil
    _G.SpellIsTargeting, _G.GetCursorInfo = nil, nil
  end)

  it("calls the realm to carry to by the player's character's realm, not the payload's name for its market", function()
    GC.Data.RealmName = function(id) return ({ [1084] = "Tarren Mill", [1305] = "Kazzak-Market" })[id] end
    panel().OnBankOpened()
    assert.equal("for Kazzak: " .. GC.Util.FormatMoney(2200 * G) .. ", sells in about 2 days", rowFor("PUT IN").where:GetText())
  end)

  it("lists what to put in for another realm and what to take out to sell here, with where and for how much", function()
    panel().OnBankOpened()
    assert.is_true(panel()._frame:IsShown())
    local putIn = rowFor("PUT IN")
    assert.equal("Gem-Inlaid Velvet Cinch", putIn.name:GetText())
    assert.equal("for Kazzak: " .. GC.Util.FormatMoney(2200 * G) .. ", sells in about 2 days", putIn.where:GetText())
    local takeOut = rowFor("TAKE OUT")
    assert.equal("Recipe: Ornate Plate", takeOut.name:GetText())
    assert.equal("here: " .. GC.Util.FormatMoney(900 * G) .. ", sells within a day", takeOut.where:GetText())
  end)

  it("puts that stack in the Warband Bank on a press, once", function()
    panel().OnBankOpened()
    local putIn = rowFor("PUT IN")
    press(putIn)
    assert.equal(1, #used)
    assert.same({ n = 5, 0, 1, nil, ACCOUNT, false }, used[1])
    assert.is_false(putIn.button.enabled)
    assert.equal("moving...", putIn.button.label)
    press(putIn) -- still settling: nothing more
    assert.equal(1, #used)
  end)

  -- The list hands items to another of the player's characters: only the Warband Bank does that,
  -- whichever bank the bank window shows.
  it("puts a stack in the Warband Bank while the bank window shows the character's own bank", function()
    shown = CHARACTER
    panel().OnBankOpened()
    press(rowFor("PUT IN"))
    assert.same({ { n = 5, 0, 1, nil, ACCOUNT, false } }, used)
  end)

  it("takes that stack out of the Warband Bank tab on a press", function()
    panel().OnBankOpened()
    press(rowFor("TAKE OUT"))
    assert.same({ n = 2, 12, 1 }, used[1])
  end)

  it("offers the button again when the move lands, and when nothing moved in time", function()
    panel().OnBankOpened()
    press(rowFor("PUT IN"))
    bags[12][2], bags[0][1] = bags[0][1], nil
    panel().OnBagsChanged()
    assert.is_nil(rowFor("PUT IN")) -- it is in the bank now, for Kazzak: nothing to do here
    bags[0][1], bags[12][2] = info(100, "Gem-Inlaid Velvet Cinch"), nil
    panel().OnBagsChanged()
    press(rowFor("PUT IN"))
    timers[#timers]()
    assert.is_true(rowFor("PUT IN").button.enabled)
  end)

  -- The same call equips a piece of gear with no bank open, which binds it, and sells it to an open
  -- vendor: a press checks first, and does nothing.
  it("moves nothing once the bank has closed, while a vendor is open, or when the Warband Bank is out of reach", function()
    panel().OnBankOpened()
    local putIn = rowFor("PUT IN")
    panel().OnBankClosed()
    press(putIn)
    assert.same({}, used)
    panel().OnBankOpened()
    _G.MerchantFrame:Show()
    press(rowFor("PUT IN"))
    assert.same({}, used)
    _G.MerchantFrame:Hide()
    canUse = false
    press(rowFor("PUT IN"))
    assert.same({}, used)
  end)

  -- Blizzard's own list of windows a bag click feeds instead (ContainerFrame.lua): the mailbox on
  -- either tab, the guild bank and the rest move nothing either.
  it("moves nothing while another window a bag click feeds is open", function()
    panel().OnBankOpened()
    local putIn = rowFor("PUT IN")
    for _, name in ipairs({ "MailFrame", "GuildBankFrame", "TradeFrame", "AuctionHouseFrame", "ItemUpgradeFrame",
        "ObliterumForgeFrame", "ChallengesKeystoneFrame", "AzeriteRespecFrame", "RuneforgeFrame" }) do
      _G[name] = region("Frame")
      _G[name]:Show()
      press(putIn)
      assert.same({}, used, name)
      _G[name] = nil
    end
    press(putIn)
    assert.equal(1, #used)
  end)

  -- With a spell waiting for an item target (Disenchant, an enchant scroll) the same call casts it
  -- on the item, and with something on the cursor it does something else again.
  it("moves nothing while a spell waits for an item target or the cursor carries something", function()
    panel().OnBankOpened()
    local putIn = rowFor("PUT IN")
    targeting = true
    press(putIn)
    press(rowFor("TAKE OUT"))
    targeting, cursor = false, "item"
    press(putIn)
    press(rowFor("TAKE OUT"))
    assert.same({}, used)
    -- A read that fails counts as busy.
    cursor, _G.SpellIsTargeting = nil, function() error("no such function") end
    press(putIn)
    assert.same({}, used)
    _G.SpellIsTargeting = function() return false end
    press(putIn)
    assert.equal(1, #used)
  end)

  it("moves nothing when the slot no longer holds the item, or it is locked", function()
    panel().OnBankOpened()
    local putIn = rowFor("PUT IN")
    bags[0][1] = info(500, "Linen Cloth")
    press(putIn)
    assert.same({}, used)
    bags[0][1] = info(100, "Gem-Inlaid Velvet Cinch", { isLocked = true })
    press(putIn)
    assert.same({}, used)
  end)

  it("tells why a piece Warbound until equipped stays, with no button", function()
    wue["0:1"] = true
    panel().OnBankOpened()
    assert.is_nil(rowFor("PUT IN"))
    local stuck
    for _, row in ipairs(panel()._rows) do if row.visible and row.name:GetText() == "Gem-Inlaid Velvet Cinch" then stuck = row end end
    assert.equal("Warbound until equipped: the auction house refuses it", stuck.where:GetText())
    assert.is_false(stuck.button.visible)
  end)

  it("leaves out a stack the Warband Bank refuses", function()
    refused["0:1"] = true
    panel().OnBankOpened()
    assert.is_nil(rowFor("PUT IN"))
    assert.is_truthy(rowFor("TAKE OUT"))
  end)

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
    local function stack(bag, slot, itemID) return { bag = bag, slot = slot, itemID = itemID } end

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

  -- A player with no route data never sees the list: they pay nothing for it at a bank either.
  it("reads no bag at a bank without route data", function()
    _G.GetRealmName = function() return "Nowhere" end
    panel().OnBankOpened()
    panel().OnBagsChanged()
    assert.equal(0, reads)
    assert.is_true(panel()._frame == nil or not panel()._frame:IsShown())
  end)

  -- A button that cannot work is not offered: a banker whose Warband Bank is out of reach, or an
  -- account with no Warband Bank tab bought.
  it("shows nothing when the Warband Bank cannot be used here, or has no tab", function()
    canUse = false
    panel().OnBankOpened()
    assert.is_true(panel()._frame == nil or not panel()._frame:IsShown())
    panel().OnBankClosed()
    canUse, tabs = true, {}
    panel().OnBankOpened()
    assert.is_true(panel()._frame == nil or not panel()._frame:IsShown())
  end)

  -- Sorting the Warband Bank or depositing everything moves hundreds of slots, one event each.
  it("repaints once after a run of Warband Bank slot changes, not once a slot", function()
    panel().OnBankOpened()
    reads = 0
    local before = #timers
    for _ = 1, 50 do panel().OnTabSlotsChanged() end
    assert.equal(0, reads)
    assert.equal(before + 1, #timers)
    timers[#timers]()
    assert.is_true(reads > 0 and reads < 10)
    assert.is_truthy(rowFor("PUT IN"))
  end)

  it("opens for a piece Warbound until equipped only beside something to carry", function()
    wue["0:1"] = true
    bags[12] = {}
    panel().OnBankOpened()
    assert.is_true(panel()._frame == nil or not panel()._frame:IsShown())
  end)

  it("leaves soulbound stacks out, and shows nothing with nothing to carry", function()
    bags[0][1] = info(100, "Gem-Inlaid Velvet Cinch", { isBound = true })
    bags[12] = {}
    panel().OnBankOpened()
    assert.is_true(panel()._frame == nil or not panel()._frame:IsShown())
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
    -- one call each time, reached only from the carry list's onCarryClick here and from the GoldCap
    -- Hoard's press (UI/HoardFrame.lua), which its move buttons' onMoveClick starts. A row of the
    -- Hoard (UI/HoardRow.lua) builds and paints those buttons and moves nothing itself.
    local ROUTE, HOARD, ROW = "GoldCap/UI/BankRoute.lua", "GoldCap/UI/HoardFrame.lua", "GoldCap/UI/HoardRow.lua"

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

    -- The carry list hands items to another character, which only the Warband Bank does; the Hoard
    -- moves to and from the bank its switch names, the one its last paint read and planned with, or
    -- the one the caller of its press names (a later part's own list): its press names that bank on
    -- every stack, and the machine hands it on.
    it("hands MoveStack the Warband Bank from the carry list and the bank it names from the Hoard", function()
      local carry = bodyOf(read(ROUTE), "local function onCarryClick(")
      assert.is_truthy(carry:find('P.MoveStack({ bag = loc.bag, slot = loc.slot, itemID = row.itemID }, button.kind == "in", accountBank())',
        1, true))
      local hoard = read(HOARD)
      local row = bodyOf(hoard, "local function moveRow(")
      assert.is_truthy(row:find("GC.BankRoute.MoveStack(row.stack, row.into, row.bankType)", 1, true))
      local pressBody = bodyOf(hoard, "function HF.Press(")
      assert.is_truthy(pressBody:find("if bankType == nil then bankType = HF._bankType end", 1, true))
      assert.is_truthy(pressBody:find("into = into, bankType = bankType }", 1, true))
      local refresh = bodyOf(hoard, "local function refresh(")
      local chosen = assert(refresh:find("local bankType = HF._bankType", 1, true))
      assert.is_true(chosen < assert(refresh:find("read(bankType, usable, hasGroups)", 1, true)))
      local reader = bodyOf(hoard, "local function read(")
      assert.is_truthy(reader:find("route.ReadStacks(BAGS, false, groupOf, bankType)", 1, true))
      assert.is_truthy(reader:find("route.ReadStacks(route.BankTabs(bankType), true, groupOf, bankType)", 1, true))
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
      assert.equal('side:SetScript("OnClick", onBankClick)', hoard:match("[^\n]*onBankClick%)[^\n]*"):match("^%s*(.-)%s*$"))
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
      for _, needle in ipairs({ "MoveStack", "UseContainerItem", "onMoveClick", "OnClick", "Press(" }) do
        assert.is_nil(shownBody:find(needle, 1, true), needle)
      end
      assert.is_truthy(shownBody:find("C_Timer.After(0, function()", 1, true))
      assert.is_nil(read(ROW):find("hooksecurefunc", 1, true))
      for _, path in ipairs({ ROUTE, HOARD }) do
        local text = read(path)
        for line in text:gmatch("[^\n]*hooksecurefunc%([^\n]*") do
          assert.is_nil(line:find("onMoveClick", 1, true), line)
          assert.is_nil(line:find("onCarryClick", 1, true), line)
          assert.is_nil(line:find("MoveStack", 1, true), line)
          assert.is_nil(line:find("Press", 1, true), line)
        end
      end
    end)

    -- The Hoard's moves are its press's (Core/VendorPress.lua): the first inside the move button's
    -- click, the rest from the machine's timers, each through the Hoard's moveRow, which is the
    -- machine's call and nothing else's. Its press is started, inside the Hoard's files, by the move
    -- button's click alone.
    it("reaches MoveStack only from the carry list's click and the Hoard's press, once in each", function()
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
      local carry = bodyOf(route, "local function onCarryClick(")
      local def = bodyOf(route, "function P.MoveStack(")
      assert.is_nil(without(without(route, carry), def):find("MoveStack", 1, true))
      assert.equal(1, count(carry, "P.MoveStack("))
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
      assert.equal(1, count(bodyOf(hoard, "local function onMoveClick("), "HF.Press(button, button.stacks, button.into)"))
      assert.is_nil(read(ROW):find("Press(", 1, true))
    end)

    -- No timer of these files moves anything: the Hoard's moves after the first come from the press
    -- machine's own timers (its driver's `after`), each through moveRow and its re-checks.
    it("reaches each click handler only through its button's OnClick, and moves nothing from a timer of its own", function()
      for path, handler in pairs({ [ROUTE] = "onCarryClick", [HOARD] = "onMoveClick" }) do
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
      assert.equal(1, count(read(HOARD), "after = function(seconds, fn) C_Timer.After(seconds, fn) end,"))
    end)

    -- The Hoard's click disables nothing itself: it starts its press (the first move), then
    -- repaints, and only the repaint disables a button whose list is now empty (paintMove).
    it("puts a button to sleep only after the call: the carry list's in its click, the Hoard's in the repaint after it", function()
      local body = bodyOf(read(ROUTE), "local function onCarryClick(")
      assert.is_true(assert(body:find("P.MoveStack(", 1, true)) < assert(body:find("button:Disable()", 1, true)))
      local hoard = read(HOARD)
      assert.is_nil(bodyOf(hoard, "local function onMoveClick("):find("Disable(", 1, true))
      local pressBody = bodyOf(hoard, "function HF.Press(")
      assert.is_nil(pressBody:find("Disable(", 1, true))
      assert.is_true(assert(pressBody:find("machine:Press(rows)", 1, true)) < assert(pressBody:find("HF.Refresh()", 1, true)))
      local paint = bodyOf(hoard, "local function paintMove(")
      assert.equal(1, count(paint, "button:Disable()"))
      -- Store all and Take all out, and each row's Store and Take out, through the same repaint.
      assert.is_truthy(bodyOf(hoard, "local function paintAll("):find("paintMove(button, stacks, label)", 1, true))
      local row = read(ROW)
      assert.is_nil(row:find("Disable(", 1, true))
      assert.equal(1, count(row, "U.paintMove(row.store, data.toBank,"))
      assert.equal(1, count(row, "U.paintMove(row.take, data.toBags,"))
      -- The only other: a side of the bank switch a bank cannot use, which moves nothing anyway.
      assert.equal(2, count(hoard, "Disable("))
      assert.equal(1, count(bodyOf(hoard, "local function paintChoice("), "side:Disable()"))
    end)

    it("loads in retail only, the Hoard after the route module", function()
      local retail, forever = read("GoldCap/GoldCap.toc"), read("GoldCap/GoldCap_Camelot.toc")
      for _, file in ipairs({ "UI/BankRoute.lua", "UI/HoardFrame.lua", "UI/HoardRow.lua", "Core/BankGroups.lua",
        "Core/Hoard.lua" }) do
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
