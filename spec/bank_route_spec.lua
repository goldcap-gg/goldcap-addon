local helper = require("spec.spec_helper")

-- At a bank: what to carry between realms through the Warband Bank (UI/BankRoute.lua). This realm is
-- Tarren Mill (1084); the account has a character on Kazzak (1305). The bags, the Warband Bank and
-- the payload are faked; Core/SellRoute.lua is the real one.
describe("bank carry list", function()
  local GC, bags, used, timers, wue, canUse
  local G = 10000
  local ACCOUNT = 2

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
    function r:SetScript(name, fn) self.scripts[name] = fn end
    function r:CreateTexture() return region("Texture") end
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
    used, timers, wue, canUse = {}, {}, {}, true
    -- 0: the backpack, with a flip that sells better on Kazzak (100) and one with no route (500);
    -- 12: the first Warband Bank tab, with a flip that sells best here (200).
    bags = {
      [0] = { info(100, "Gem-Inlaid Velvet Cinch"), info(500, "Linen Cloth") },
      [12] = { info(200, "Recipe: Ornate Plate") },
    }
    _G.Enum = { BankType = { Account = ACCOUNT } }
    _G.CreateFrame = function(kind) return region(kind) end
    _G.UIParent = region("Frame")
    _G.BankFrame = region("Frame")
    _G.MerchantFrame = region("Frame")
    _G.GetRealmName = function() return "Tarren Mill" end
    _G.ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
      GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] or nil end,
      UseContainerItem = function(...) used[#used + 1] = { n = select("#", ...), ... } end,
    }
    _G.C_Item = {
      IsBoundToAccountUntilEquip = function(loc) return wue[loc.bag .. ":" .. loc.slot] == true end,
      CanBeRefunded = function() return false end,
      GetCurrentItemLevel = function() return 0 end,
    }
    _G.C_Bank = {
      CanUseBank = function(t) return canUse and t == ACCOUNT end,
      IsItemAllowedInBankType = function() return true end,
      FetchPurchasedBankTabIDs = function(t) return t == ACCOUNT and { 12 } or {} end,
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

  it("leaves soulbound stacks out, and shows nothing with nothing to carry", function()
    bags[0][1] = info(100, "Gem-Inlaid Velvet Cinch", { isBound = true })
    bags[12] = {}
    panel().OnBankOpened()
    assert.is_true(panel()._frame == nil or not panel()._frame:IsShown())
  end)

  describe("wiring", function()
    local function read(path)
      local f = assert(io.open(path, "r"))
      local t = f:read("*a")
      f:close()
      return (t:gsub("%-%-[^\n]*", ""))
    end

    it("calls UseContainerItem only inside onCarryClick", function()
      local listing = assert(io.popen("find GoldCap -name '*.lua'"))
      for path in listing:lines() do
        if path ~= "GoldCap/UI/BankRoute.lua" then
          assert.is_nil(read(path):find("UseContainerItem", 1, true), path)
        end
      end
      listing:close()
      local text = read("GoldCap/UI/BankRoute.lua")
      local from = assert(text:find("local function onCarryClick", 1, true))
      local to = assert(text:find("\nend\n", from, true))
      local outside = text:sub(1, from - 1) .. text:sub(to)
      assert.is_nil(outside:find("UseContainerItem", 1, true))
    end)

    it("reaches onCarryClick only through the button's OnClick, and never from a timer", function()
      local text = read("GoldCap/UI/BankRoute.lua")
      local sites = {}
      for line in text:gmatch("[^\n]*onCarryClick[^\n]*") do sites[#sites + 1] = line:match("^%s*(.-)%s*$") end
      assert.same({ "local function onCarryClick(button)", 'button:SetScript("OnClick", onCarryClick)' }, sites)
      for body in text:gmatch("C_Timer%.After%b()") do assert.is_nil(body:find("UseContainerItem", 1, true)) end
    end)

    it("disables the button only after the call", function()
      local text = read("GoldCap/UI/BankRoute.lua")
      local from = assert(text:find("local function onCarryClick", 1, true))
      local body = text:sub(from, assert(text:find("\nend\n", from, true)))
      assert.is_true(assert(body:find("UseContainerItem(", 1, true)) < assert(body:find("button:Disable()", 1, true)))
    end)

    it("loads in retail only, after the route module", function()
      local retail, forever = read("GoldCap/GoldCap.toc"), read("GoldCap/GoldCap_Camelot.toc")
      assert.is_truthy(retail:find("\nUI/BankRoute.lua\n", 1, true))
      assert.is_nil(forever:find("BankRoute", 1, true))
      assert.is_true(retail:find("Core/SellRoute.lua", 1, true) < retail:find("UI/BankRoute.lua", 1, true))
    end)

    it("is routed from the event frame", function()
      local init = read("GoldCap/Core/Init.lua")
      for _, event in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED" }) do
        assert.is_truthy(init:find('"' .. event .. '"', 1, true), event)
      end
      for _, name in ipairs({ "OnBankOpened", "OnBankClosed", "OnBagsChanged" }) do
        assert.is_truthy(init:find("GC.BankRoute." .. name, 1, true), name)
      end
    end)
  end)
end)
