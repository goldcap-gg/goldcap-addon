local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/VendorSellCard.lua: the Sell to vendor card in the merchant column. Which stacks one press
-- sells is Core/VendorSelect.lua's (the real one runs here); the bag read is stubbed except in the
-- one test that puts the card next to the merchant note.
describe("vendor sell card", function()
  local GC, C, restore, saved, reads, menus
  local KEYS = { "C_Container", "C_Item", "C_Timer", "GetCursorInfo", "SpellIsTargeting", "MerchantFrame",
    "GetCoinTextureString", "hooksecurefunc", "MenuUtil", "UIParent" }

  local nextID = 5000
  -- An auction house price, where a case gives one, is the import's and a minute old.
  local function stack(over)
    nextID = nextID + 1
    local s = {
      bag = 0, slot = nextID - 5000, itemID = nextID, link = "item:" .. nextID, count = 1, quality = 0,
      vendorUnit = 10, ahSource = "import", ahAt = time() - 60, hasNoValue = false, isLocked = false,
      isBound = false, isGear = false, isReagent = false, refundable = false, tradeTimer = false,
      inSet = false, excludedBag = false, selling = false,
    }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
  end

  local function anchorOf(widget)
    local p = W.state(widget).points
    return p[#p]
  end
  local function textOf(fs) return W.state(fs).text end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    reads, menus = {}, {}
    _G.UIParent = W.CreateFrame("Frame")
    _G.MerchantFrame = W.CreateFrame("Frame")
    _G.C_Item = {
      GetItemInfo = function(id) return "Item " .. id end,
      GetItemIconByID = function() return 134400 end,
    }
    _G.GetCoinTextureString = function(c) return c .. "c" end
    _G.hooksecurefunc = function(t, name, fn)
      local original = t[name]
      t[name] = function(...)
        local result = original(...)
        fn(...)
        return result
      end
    end
    _G.MenuUtil = { CreateContextMenu = function(owner, generator)
      local root = { buttons = {} }
      function root:CreateButton(text, fn) self.buttons[#self.buttons + 1] = { text = text, fn = fn } end
      generator(owner, root)
      menus[#menus + 1] = root
    end }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Flips.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/ForeverValue.lua", GC)
    helper.loadModule("Core/VendorSelect.lua", GC)
    helper.loadModule("Core/VendorPress.lua", GC)
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("UI/Tooltip.lua", GC)
    helper.loadModule("UI/MerchantNote.lua", GC)
    GC.Data = { GetItemValue = function() return nil end }
    GC.BuyVendorPanel = { Refresh = function() end }
    GC.db = { settings = { sniper = { vendorJunk = true, vendorWorth = true } }, vendorKeep = {} }
    GC.VendorBags = { Read = function() return reads end }
    helper.loadModule("UI/VendorSellCard.lua", GC)
    C = GC.VendorSellCard
  end)

  after_each(function()
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  local function names()
    local out = {}
    for i = 1, #C._pick.rows do out[#out + 1] = textOf(C._rows[i].name) end
    return out
  end

  it("lists a grey stack and the cheap item, not a refundable one", function()
    local grey = stack({ count = 3 })
    local cheap = stack({ quality = 1, vendorUnit = 95, ahUnit = 100 })
    local refundable = stack({ refundable = true })
    reads = { grey, cheap, refundable }
    C.OnMerchantShow()
    assert.is_true(C._frame:IsShown())
    assert.equal(2, #C._pick.rows)
    local text = table.concat(names(), "|")
    assert.is_truthy(text:find("Item " .. grey.itemID .. " ×3", 1, true))
    assert.is_truthy(text:find("Item " .. cheap.itemID, 1, true))
    assert.is_nil(text:find("Item " .. refundable.itemID, 1, true))
    assert.equal("95c", textOf(C._rows[1].price))
  end)

  it("lists by the value rule on a price under a day old by the clock, not on an older one", function()
    local fresh = stack({ quality = 1, vendorUnit = 95, ahUnit = 100, ahAt = time() - 3600 })
    local old = stack({ quality = 1, vendorUnit = 95, ahUnit = 100, ahAt = time() - 25 * 3600 })
    reads = { fresh, old }
    C.OnMerchantShow()
    assert.equal(1, #C._pick.rows)
    assert.equal(fresh.itemID, C._pick.rows[1].itemID)
  end)

  it("shows nothing when the bags hold nothing to sell, and when both toggles are off", function()
    reads = { stack({ refundable = true }) }
    C.OnMerchantShow()
    assert.is_true(C._frame == nil or not C._frame:IsShown())
    reads = { stack({}), stack({ quality = 1, vendorUnit = 95, ahUnit = 100 }) }
    GC.db.settings.sniper.vendorJunk, GC.db.settings.sniper.vendorWorth = false, false
    C.OnBagsChanged()
    assert.is_true(C._frame == nil or not C._frame:IsShown())
    GC.db.settings.sniper.vendorJunk = true
    C.OnBagsChanged()
    assert.equal(1, #C._pick.rows) -- only the enabled kind
    assert.is_true(C._frame:IsShown())
  end)

  it("says N more after this above 12", function()
    reads = {}
    for _ = 1, 15 do reads[#reads + 1] = stack({}) end
    C.OnMerchantShow()
    assert.equal(12, #C._pick.rows)
    assert.equal("3 more after this", textOf(C._frame.more))
    assert.is_true(C._frame.more:IsShown())
  end)

  it("labels the button with the stack count and the total", function()
    reads = { stack({ vendorUnit = 10, count = 2 }), stack({ vendorUnit = 5 }) }
    C.OnMerchantShow()
    assert.equal("Sell 2 for 25c", textOf(C._frame.button.text))
  end)

  it("never lists what the merchant note keeps for the auction house", function()
    -- The real bag read and the real note over one set of bags.
    local bags = {
      [0] = {
        { itemID = 70, stackCount = 2, quality = 0, hyperlink = "item:70", isBound = false },  -- AH pays more
        { itemID = 71, stackCount = 4, quality = 0, hyperlink = "item:71", isBound = false },  -- no AH price
      },
    }
    local sells = { [70] = 10, [71] = 8 }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
      GetContainerItemInfo = function(bag, slot)
        local i = bags[bag] and bags[bag][slot]
        if not i then return nil end
        return { iconFileID = 1, stackCount = i.stackCount, isLocked = false, quality = i.quality,
          isReadable = false, hasLoot = false, hyperlink = i.hyperlink, isFiltered = false,
          hasNoValue = false, itemID = i.itemID, isBound = i.isBound, itemName = "Item" }
      end,
      GetContainerItemPurchaseInfo = function() return nil end,
      GetBagSlotFlag = function() return false end,
      GetBackpackSellJunkDisabled = function() return false end,
    }
    _G.C_Item = {
      GetItemInfo = function(id)
        return "Item " .. id, "link", 0, 1, 1, "t", "s", 20, "", 1, sells[id], 15, 0, 0, 0, nil, false
      end,
      GetItemIconByID = function() return 1 end,
      CanBeRefunded = function() return false end,
    }
    _G.ItemLocation = nil
    GC.Data = { GetItemValue = function(id)
      if id == 70 then return { mv = 1000, ts = 0, source = "import", kind = "region_commodity" } end
    end }
    GC.db.sellMarks = {}
    helper.loadModule("Services/VendorBags.lua", GC)
    C.OnMerchantShow()
    local note = GC.MerchantNote.Text(GC.ForeverValue.RealBagTotals(GC.MerchantNote.ValueFor))
    assert.is_not_nil(note) -- the note does count item 70
    assert.equal(1, #C._pick.rows)
    assert.equal(71, C._pick.rows[1].itemID)
  end)

  describe("placement", function()
    local function shown(name)
      local frame = W.CreateFrame("Frame")
      GC[name]._frame = frame
      return frame
    end

    it("sits under the BUY panel when it is shown, under the note when only the note is, beside the merchant window otherwise", function()
      reads = { stack({}) }
      C.OnMerchantShow()
      local point = anchorOf(C._frame)
      assert.equal("TOPLEFT", point[1])
      assert.equal(_G.MerchantFrame, point[2])
      assert.equal("TOPRIGHT", point[3])
      assert.equal(4, point[4])

      local note = shown("MerchantNote")
      C._Place()
      assert.equal(note, anchorOf(C._frame)[2])
      assert.equal("BOTTOMLEFT", anchorOf(C._frame)[3])

      local buy = shown("BuyVendorPanel")
      C._Place()
      assert.equal(buy, anchorOf(C._frame)[2])

      W.state(buy).shown = false
      C._Place()
      assert.equal(note, anchorOf(C._frame)[2])
    end)

    it("re-places after the note and the BUY panel refresh", function()
      reads = { stack({}) }
      C.OnMerchantShow()
      local note = shown("MerchantNote")
      GC.MerchantNote.Refresh()
      assert.equal(note, anchorOf(C._frame)[2])
      local buy = shown("BuyVendorPanel")
      GC.BuyVendorPanel.Refresh()
      assert.equal(buy, anchorOf(C._frame)[2])
      W.state(buy).shown = false
      GC.BuyVendorPanel.Refresh()
      assert.equal(note, anchorOf(C._frame)[2])
    end)

    it("installs each follow hook once", function()
      reads = { stack({}) }
      C.OnMerchantShow()
      local refresh = GC.BuyVendorPanel.Refresh
      C.OnBagsChanged()
      C.OnMerchantShow()
      assert.equal(refresh, GC.BuyVendorPanel.Refresh)
    end)
  end)

  describe("Never sell this", function()
    it("keeps the item and the next refresh drops its line", function()
      local a, b = stack({}), stack({})
      reads = { a, b }
      C.OnMerchantShow()
      assert.equal(2, #C._pick.rows)
      local row
      for i = 1, #C._pick.rows do
        if C._rows[i].itemID == a.itemID then row = C._rows[i] end
      end
      W.state(row).scripts.OnClick(row, "RightButton")
      assert.equal(1, #menus)
      assert.equal("Never sell this", menus[1].buttons[1].text)
      menus[1].buttons[1].fn()
      assert.is_true(GC.db.vendorKeep[a.itemID])
      assert.equal(1, #C._pick.rows)
      assert.equal(b.itemID, C._pick.rows[1].itemID)
    end)

    it("opens only on a right click", function()
      reads = { stack({}) }
      C.OnMerchantShow()
      local row = C._rows[1]
      W.state(row).scripts.OnClick(row, "LeftButton")
      assert.equal(0, #menus)
    end)
  end)

  it("hides when the merchant closes", function()
    reads = { stack({}) }
    C.OnMerchantShow()
    assert.is_true(C._frame:IsShown())
    C.OnMerchantClosed()
    assert.is_false(C._frame:IsShown())
    C.OnBagsChanged()
    assert.is_false(C._frame:IsShown())
  end)

  it("a kept item that is no longer in the bags changes nothing", function()
    GC.db.vendorKeep = { [424242] = true }
    reads = { stack({}) }
    C.OnMerchantShow()
    assert.equal(1, #C._pick.rows)
  end)

  -- The press: the click, the machine's driver, the chat line and the stop events. The bags are a
  -- table the fake C_Container and the stubbed bag read both look at, so a sale is the slot going.
  describe("the press", function()
    local bags, used, timers, printed, refuse, buttonEnabledAtUse, readCount, targeting

    local function put(bag, slot, vendorUnit)
      nextID = nextID + 1
      bags[bag .. ":" .. slot] = { bag = bag, slot = slot, itemID = nextID, link = "item:" .. nextID,
        vendorUnit = vendorUnit }
    end

    local function click()
      local button = C._frame.button
      W.state(button).scripts.OnClick(button)
    end
    local function fire()
      local t = table.remove(timers, 1)
      if t then t() end
      return t ~= nil
    end
    local function drain() while fire() do end end
    local function label() return textOf(C._frame.button.text) end

    before_each(function()
      bags, used, timers, printed, refuse, readCount, targeting = {}, {}, {}, {}, false, 0, false
      buttonEnabledAtUse = nil
      -- Strict: the card may read an item and make the sale, nothing else in the container API.
      _G.C_Container = setmetatable({
        GetContainerItemInfo = function(bag, slot)
          local item = bags[bag .. ":" .. slot]
          return item and { hyperlink = item.link, isLocked = false, itemID = item.itemID } or nil
        end,
        UseContainerItem = function(bag, slot)
          used[#used + 1] = { bag, slot }
          buttonEnabledAtUse = C._frame.button:IsEnabled()
          if not refuse then bags[bag .. ":" .. slot] = nil end
        end,
      }, { __index = function(_, name) error("the card must not call C_Container." .. name) end })
      _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
      _G.GetCursorInfo = function() return nil end
      -- A global function the client defines (FrameXML calls it bare, ContainerFrame.lua), no
      -- arguments, one boolean.
      _G.SpellIsTargeting = function() return targeting end
      GC.Print = function(text) printed[#printed + 1] = text end
      GC.VendorBags = { Read = function()
        readCount = readCount + 1
        local out = {}
        for _, item in pairs(bags) do
          out[#out + 1] = stack({ bag = item.bag, slot = item.slot, itemID = item.itemID,
            link = item.link, vendorUnit = item.vendorUnit })
        end
        return out
      end }
      put(0, 1, 10); put(0, 2, 20); put(0, 3, 30)
      C.OnMerchantShow()
    end)

    after_each(function() _G.C_Timer, _G.GetCursorInfo, _G.SpellIsTargeting = nil, nil, nil end)

    it("the click sells the first stack before returning", function()
      assert.equal("Sell 3 for 60c", label())
      click()
      assert.equal(1, #used)
      assert.same({ 0, 3 }, used[1]) -- the dearest first
      assert.is_true(buttonEnabledAtUse) -- the clicked button was not put to sleep before the call
      assert.equal(1, #timers)
    end)

    it("timers sell the rest and the chat line names count and total", function()
      click()
      drain()
      assert.equal(3, #used)
      assert.same({ "Sold 3 stacks for 60c. Buyback has them until you leave." }, printed)
      assert.is_false(C.machine:IsRunning())
    end)

    it("one stack reads 'Sold 1 stack'", function()
      bags["0:2"], bags["0:3"] = nil, nil
      C.OnBagsChanged()
      click()
      drain()
      assert.same({ "Sold 1 stack for 10c. Buyback has it until you leave." }, printed)
    end)

    it("closing the merchant mid-run stops it and reports what sold", function()
      click()
      C.OnMerchantClosed()
      drain()
      assert.equal(1, #used)
      assert.same({ "Sold 1 stack for 30c. Buyback has it until you leave." }, printed)
      assert.is_false(C._frame:IsShown())
    end)

    it("a bag update during the run does not rebuild the rows or reset the label", function()
      click()
      local before = readCount
      C.OnBagsChanged()
      C.OnMerchantUpdate()
      assert.equal(before, readCount)
      assert.equal("Stop", label())
      assert.equal(3, #C._pick.rows)
    end)

    it("the button reads Stop while running and a second click stops", function()
      click()
      assert.equal("Stop", label())
      click()
      assert.equal(1, #used)
      drain()
      assert.equal(1, #used)
      assert.same({ "Sold 1 stack for 30c. Buyback has it until you leave." }, printed)
      assert.equal("Sell 2 for 30c", label()) -- what is left, read again
    end)

    it("after a slow timer sale the card says the game sells one stack per press and the next click sells one", function()
      click()
      refuse = true -- the first sale has left; the next one stays
      drain()
      assert.is_true(C.machine.oneAtATime)
      assert.equal("The game sells one stack per press here.", textOf(C._frame.slow))
      assert.is_true(C._frame.slow:IsShown())
      refuse = false
      used = {}
      assert.equal("Sell 1 for 20c", label()) -- the dearest stack that is left, alone
      click()
      assert.equal(1, #used)
      drain()
      assert.equal(1, #used)
    end)

    -- A spell waiting for an item target (Disenchant, an enchant scroll) turns UseContainerItem
    -- into casting it on the item, and GetCursorInfo is nil then.
    it("a spell waiting for an item target refuses the first sale in the click", function()
      targeting = true
      click()
      assert.equal(0, #used)
      assert.is_false(C.machine:IsRunning())
      assert.same({}, printed)
      assert.equal("Sell 3 for 60c", label())
    end)

    it("a spell waiting for an item target stops the run before the next sale", function()
      click()
      targeting = true
      drain()
      assert.equal(1, #used)
      assert.is_false(C.machine:IsRunning())
      assert.same({ "Sold 1 stack for 30c. Buyback has it until you leave." }, printed)
    end)

    it("an error from SpellIsTargeting is read as a spell waiting, and nothing is sold", function()
      _G.SpellIsTargeting = function() error("no such function") end
      click()
      assert.equal(0, #used)
      _G.SpellIsTargeting = nil
      click()
      assert.equal(0, #used)
    end)

    it("the trade timer confirm event stops the run", function()
      click()
      C.OnTradeTimerConfirm()
      assert.is_false(C.machine:IsRunning())
      drain()
      assert.equal(1, #used)
    end)

    it("nothing is printed when nothing sold", function()
      refuse = true
      click()
      drain()
      assert.same({}, printed)
      assert.is_false(C.machine.oneAtATime)
    end)

    it("a new visit forgets the one stack per press mode", function()
      click()
      refuse = true
      drain()
      assert.is_true(C.machine.oneAtATime)
      C.OnMerchantClosed()
      C.OnMerchantShow()
      assert.is_false(C.machine.oneAtATime)
      assert.is_false(C._frame.slow:IsShown())
    end)
  end)
end)
