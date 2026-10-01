local helper = require("spec.spec_helper")

-- BUY 2.0 week 2: at a vendor, the BUY list's vendor lines this merchant sells, each with a button
-- that buys what is left of it (UI/BuyVendorPanel.lua). The merchant, the bags and the BUY tab's
-- answer are faked; Core/BuyVendor.lua is the real one.
describe("BUY vendor panel", function()
  local GC, bought, count, recorded, timers, money, lines

  local function region(kind)
    local r = { kind = kind, visible = false, enabled = true, scripts = {}, pointsSet = {} }
    function r:SetPoint(...) self.pointsSet[#self.pointsSet + 1] = { ... } end
    function r:ClearAllPoints() self.pointsSet = {} end
    function r:SetSize(w, h) self.width, self.height = w, h end
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
    function b:SetVariant(v) self.variant = v end
    function b:Enable() self.enabled = true end
    function b:Disable() self.enabled = false end
    return b
  end

  local function panel() return GC.BuyVendorPanel end
  local function row(i) return panel()._rows[i or 1] end
  local function press(i) local b = row(i).button; b.scripts.OnClick(b) end

  before_each(function()
    bought, count, recorded, timers, money = {}, 0, nil, {}, 100000
    lines = { { itemID = 2320, buy = 45, need = 45, name = "Coarse Thread" } }
    _G.CreateFrame = function(kind) return region(kind) end
    _G.UIParent = region("Frame")
    _G.MerchantFrame = region("Frame")
    _G.GetMerchantNumItems = function() return 1 end
    _G.GetMerchantItemID = function() return 2320 end
    _G.GetMerchantItemMaxStack = function() return 20 end
    _G.C_MerchantFrame = { GetItemInfo = function() return { price = 10, stackCount = 1, numAvailable = -1,
      isPurchasable = true, hasExtendedCost = false } end }
    _G.BuyMerchantItem = function(index, qty) bought[#bought + 1] = { index, qty } end
    _G.C_Item = { GetItemCount = function() return count end, GetItemIconByID = function() return 136000 end }
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    _G.GetMoney = function() return money end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.UnitName = function() return "Tharynn" end
    GC = helper.loadModule("Core/Util.lua")
    GC.Theme = {
      color = { panel = { 0, 0, 0 }, border = { 1, 1, 1 }, gold = { 1, 0.8, 0 }, fg = { 1, 1, 1 },
                fgDim = { 0.5, 0.5, 0.5 } },
      pad = { m = 12 },
      Card = function() return region("Frame") end,
      Label = function() return region("FontString") end,
      Num = function() return region("FontString") end,
      Button = function() return button() end,
    }
    helper.loadModule("Core/BuyVendor.lua", GC)
    GC.Buy = {
      VendorLines = function() return { runName = "Tailoring 1 → 100", code = "r", lines = lines } end,
      RecordVendorPurchase = function(itemID, qty, spent) recorded = { itemID, qty, spent } end,
    }
    helper.loadModule("UI/BuyVendorPanel.lua", GC)
  end)

  after_each(function()
    _G.CreateFrame, _G.UIParent, _G.MerchantFrame, _G.GetMerchantNumItems = nil, nil, nil, nil
    _G.GetMerchantItemID, _G.GetMerchantItemMaxStack, _G.C_MerchantFrame, _G.BuyMerchantItem = nil, nil, nil, nil
    _G.C_Item, _G.C_Timer, _G.GetMoney, _G.GetCoinTextureString, _G.UnitName = nil, nil, nil, nil, nil
  end)

  it("shows a button for each list line this merchant sells, under the merchant's name", function()
    panel().OnMerchantShow()
    assert.is_true(panel()._frame:IsShown())
    assert.equal("Tharynn", panel()._frame.title:GetText())
    assert.equal("Coarse Thread ×45", row().name:GetText())
    assert.equal("from Tailoring 1 → 100", row().from:GetText())
    -- One call per press (the probe measured nothing else): the button walks the line.
    assert.is_false(panel().MULTI_CALL)
    assert.equal("BUY 20 · 200c", row().button.label)
    assert.is_true(row().button.enabled)
  end)

  it("says BUY with the whole cost when one call buys the whole line", function()
    lines[1].buy = 12
    panel().OnMerchantShow()
    assert.equal("BUY · 120c", row().button.label)
  end)

  it("stays hidden at a merchant who sells nothing on the list", function()
    _G.GetMerchantItemID = function() return 999 end
    panel().OnMerchantShow()
    assert.is_false(panel()._frame ~= nil and panel()._frame:IsShown())
  end)

  it("makes one call per press, and disables the button only after it", function()
    panel().OnMerchantShow()
    local b = row().button
    local enabledAtCall
    _G.BuyMerchantItem = function(index, qty)
      enabledAtCall = b.enabled
      bought[#bought + 1] = { index, qty }
    end
    press()
    assert.same({ { 1, 20 } }, bought)
    assert.is_true(enabledAtCall)
    assert.is_false(b.enabled)
    assert.equal("buying...", b.label)
    press() -- a second press while the first is settling buys nothing
    assert.equal(1, #bought)
  end)

  it("books what arrived when the bags change, at the merchant's price, and offers the rest", function()
    panel().OnMerchantShow()
    press()
    count = 20
    lines[1].buy = 25
    panel().OnBagsChanged()
    assert.same({ 2320, 20, 200 }, recorded)
    assert.is_nil(panel()._pending)
    assert.equal("BUY 20 · 200c", row().button.label)
    assert.equal("Coarse Thread ×25", row().name:GetText())
  end)

  -- Review Focus 5: loot of the same item landing meanwhile is not this purchase.
  it("never credits more than the press asked for", function()
    panel().OnMerchantShow()
    press()
    count = 27
    panel().OnBagsChanged()
    assert.same({ 2320, 20, 200 }, recorded)
  end)

  it("reads bought once the line is bought at this merchant", function()
    lines[1].buy = 12
    panel().OnMerchantShow()
    press()
    count = 12
    lines[1].buy = 0
    panel().OnBagsChanged()
    assert.equal("bought", row().button.label)
    assert.is_false(row().button.enabled)
    assert.equal("Coarse Thread ×12", row().name:GetText())
  end)

  it("gives the button back if nothing arrives", function()
    panel().OnMerchantShow()
    press()
    timers[#timers]()
    assert.is_nil(panel()._pending)
    assert.is_true(row().button.enabled)
    assert.equal("BUY 20 · 200c", row().button.label)
  end)

  -- Review Focus 4.
  it("says not enough gold for a line the wallet cannot start, and buys what it can pay", function()
    money = 5
    panel().OnMerchantShow()
    assert.equal("not enough gold", row().button.label)
    assert.is_false(row().button.enabled)
    money = 75
    panel().OnMerchantUpdate()
    assert.equal("BUY 7 · 70c", row().button.label)
  end)

  -- The GoldCap merchant note (UI/MerchantNote.lua) sits beside the merchant window too: the panel
  -- goes under it while it is up, so the two never overlap.
  it("sits under the merchant note while the note is up, beside the merchant while it is not", function()
    local note = region("Frame")
    GC.MerchantNote = { _frame = note, Refresh = function() end }
    note:Show()
    panel().OnMerchantShow()
    assert.equal(note, panel()._frame.pointsSet[1][2])
    assert.equal("BOTTOMLEFT", panel()._frame.pointsSet[1][3])
    note:Hide()
    panel().OnMerchantUpdate()
    assert.equal(_G.MerchantFrame, panel()._frame.pointsSet[1][2])
    assert.equal("TOPRIGHT", panel()._frame.pointsSet[1][3])
    GC.MerchantNote = nil
  end)

  it("hides with the merchant", function()
    panel().OnMerchantShow()
    panel().OnMerchantClosed()
    assert.is_false(panel()._frame:IsShown())
  end)
end)
