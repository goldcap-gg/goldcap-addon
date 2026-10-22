local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local Mailbox = require("spec.support.mail_inbox")

-- UI/MailCollect.lua: the Collect button beside the mailbox. The mailbox is the shared double
-- (spec/support/mail_inbox.lua), the widgets are the shared frame double with the real Theme, and
-- C_Timer.After is captured in a list this spec runs by hand.
describe("Collect button", function()
  local GC, box, bags, events, timers, printed, clock, restoreFrames, eventFrames, realScanInbox
  local KEYS = { "MailFrame", "GetTime", "C_Timer", "C_Mail", "C_Container", "GameTooltip", "GetInboxNumItems",
    "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "GetInboxItem", "TakeInboxMoney", "TakeInboxItem", "CheckInbox",
    "RETRIEVING_DATA", "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT",
    "AUCTION_OUTBID_MAIL_SUBJECT", "ERR_INV_FULL", "ERR_ITEM_MAX_COUNT", "GetCoinTextureString", "time" }
  local saved = {}

  local SALE = function(n) return { sender = "Auction House", subject = "Auction successful: Cloth " .. n,
    money = 1000 * n, auction = true, invoice = { invoiceType = "seller", itemName = "Cloth " .. n } } end
  local EXPIRED = function(itemID) return { sender = "Auction House", subject = "Auction expired: Silk", auction = true,
    items = { [1] = { itemID = itemID, count = 2 } } } end

  local function install(rows, opts)
    box = Mailbox.new(rows, opts)
    local api = box.api
    _G.GetInboxNumItems, _G.GetInboxHeaderInfo = api.GetInboxNumItems, api.GetInboxHeaderInfo
    _G.GetInboxInvoiceInfo, _G.GetInboxItem = api.GetInboxInvoiceInfo, api.GetInboxItem
    _G.TakeInboxMoney = function(i) events[#events + 1] = "money:" .. i; api.TakeInboxMoney(i) end
    _G.TakeInboxItem = function(i, slot) events[#events + 1] = "item:" .. i .. ":" .. slot; api.TakeInboxItem(i, slot) end
    _G.CheckInbox = api.CheckInbox
    _G.C_Mail = api.C_Mail
  end

  local function card() return W.state(_G.MailFrame).children[1] end
  local function button()
    for _, child in ipairs(W.state(card()).children) do
      if W.state(child).kind == "Button" then return child end
    end
  end
  local function press() button():GetScript("OnClick")(button()) end
  local function enabled() return W.state(button()).enabled end

  -- The client answers the pending take, time passes, and the one pending timer fires.
  local function tick()
    box:advance()
    clock = clock + 0.2
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
  end

  local function runOut(limit)
    for _ = 1, limit or 60 do
      if #timers == 0 then break end
      tick()
    end
  end

  local function watchButton()
    local b = button()
    local setLabel, disable = b.SetLabel, b.Disable
    b.SetLabel = function(self, text) events[#events + 1] = "label:" .. text; return setLabel(self, text) end
    b.Disable = function(self) events[#events + 1] = "disable"; return disable(self) end
  end

  before_each(function()
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restoreFrames = W.install()
    events, timers, printed, clock, bags, eventFrames = {}, {}, {}, 100, { free = 20 }, {}
    local create = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent)
      local f = create(kind, name, parent)
      if parent == nil then eventFrames[#eventFrames + 1] = f end
      return f
    end
    _G.MailFrame = W.CreateFrame("Frame")
    _G.MailFrame:SetSize(384, 512)
    _G.GetTime = function() return clock end
    _G.time = function() return 5000 end
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn; events[#events + 1] = "timer" end }
    _G.C_Container = { CalculateTotalNumberOfFreeBagSlots = function() return bags.free end }
    _G.GameTooltip = setmetatable({}, { __index = function() return function() end end })
    _G.RETRIEVING_DATA = "Retrieving data..."
    _G.AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
    _G.AUCTION_REMOVED_MAIL_SUBJECT = "Auction canceled: %s"
    _G.AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
    _G.ERR_INV_FULL, _G.ERR_ITEM_MAX_COUNT = "Inventory is full.", "You can't carry any more of those items."
    _G.GetCoinTextureString = function(c) return c .. "c" end
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Ledger.lua", GC)
    helper.loadModule("Core/MailReturns.lua", GC)
    helper.loadModule("Core/MailClassify.lua", GC)
    helper.loadModule("Core/MailLoop.lua", GC)
    helper.loadModule("UI/Theme.lua", GC)
    GC.db = { settings = { sniper = {} } }
    GC.Ledger.Init(GC.db)
    GC.MailReturns.Init(GC.db)
    GC.Ledger.Context = function() return { char = "A-B", region = "eu" } end
    realScanInbox = GC.Ledger.ScanInbox
    GC.Ledger.ScanInbox = function() events[#events + 1] = "scan" end
    GC.Print = function(text) printed[#printed + 1] = text end
    helper.loadModule("UI/MailCollect.lua", GC)
  end)

  after_each(function()
    restoreFrames()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  local function open(rows, opts)
    install(rows, opts)
    GC.MailCollect.OnMailShow()
    watchButton()
  end

  describe("the press", function()
    it("takes before the label changes, before any timer, and never disables the button", function()
      open(Mailbox.tenMail())
      events = {}
      press()
      local firstTake, firstOther
      for i, e in ipairs(events) do
        if e:match("^money:") or e:match("^item:") then firstTake = firstTake or i
        elseif e == "timer" or e:match("^label:") or e == "disable" then firstOther = firstOther or i end
      end
      assert.is_truthy(firstTake)
      assert.is_truthy(firstOther)
      assert.is_true(firstTake < firstOther)
      for _, e in ipairs(events) do assert.is_not.equal("disable", e) end
    end)

    it("reads Collect 4 before, Stop while running and Collect, disabled, after", function()
      open(Mailbox.tenMail())
      assert.equal("Collect 4", button().label)
      assert.is_true(enabled())
      press()
      assert.equal("Stop", button().label)
      runOut()
      assert.equal("Collect", button().label)
      assert.is_false(enabled())
    end)

    it("stops on a second press and the next tick makes no call", function()
      open(Mailbox.tenMail())
      press()
      local calls = #box:calls()
      press()
      assert.same({ true, false }, box:openingCalls())
      tick()
      assert.equal(calls, #box:calls())
      assert.equal(0, #timers)
    end)

    it("makes no call with nothing to take", function()
      open({ { sender = "GM", isGM = true, money = 5 }, { sender = "F", canReply = true, cod = 9,
        items = { [1] = { itemID = 1, count = 1 } } } })
      assert.equal("Collect", button().label)
      assert.is_false(enabled())
      press()
      assert.same({}, box:calls())
      assert.same({}, box:openingCalls())
    end)

    it("takes nothing when every group is switched off", function()
      GC.db.settings.sniper.collectSales, GC.db.settings.sniper.collectReturns = false, false
      GC.db.settings.sniper.collectPurchases, GC.db.settings.sniper.collectPlayers = false, false
      open(Mailbox.tenMail())
      assert.equal("Collect", button().label)
      press()
      assert.same({}, box:calls())
    end)

    it("says the mailbox did not answer when a command is pending", function()
      open({ SALE(1), SALE(2) })
      box.api.TakeInboxMoney(2)
      press()
      assert.equal("The mailbox did not answer", printed[1])
      assert.equal(0, #timers)
    end)
  end)

  describe("the finish", function()
    it("prints the summary line and keeps it for the tooltip", function()
      open({ SALE(1), SALE(2), EXPIRED(5) })
      press()
      runOut()
      assert.equal("Collected 3000c from 2 sales, 1 lot came back.", printed[#printed])
      assert.same({ true, false }, box:openingCalls())
      assert.equal(1, #GC.MailReturns.Entries())
    end)

    it("stores the lot's time as wall clock, not session time", function()
      open({ EXPIRED(5) })
      press()
      assert.equal(5000, GC.MailReturns.Entries()[1].at)
    end)

    it("says the bags are full when no slot is free", function()
      bags.free = 0
      open({ SALE(1), EXPIRED(5) })
      press()
      runOut()
      assert.equal("Collected 1000c from 1 sale. The bags are full, the rest stays in the mailbox.", printed[#printed])
    end)

    it("paints the wait when the client may not be asked for more mail yet", function()
      open({ SALE(1) }, { hidden = { SALE(2) } })
      box:setCanCheck(false, 9)
      press()
      tick()
      assert.equal("More mail in 9 s", button().label)
      assert.is_true(enabled())
    end)
  end)

  describe("the mailbox closing and opening", function()
    it("ends a run on close: SetOpeningAll(false) and the timer chain dies", function()
      open({ SALE(1), SALE(2), SALE(3) })
      press()
      GC.MailCollect.OnMailClosed()
      assert.same({ true, false }, box:openingCalls())
      local calls = #box:calls()
      tick()
      assert.equal(calls, #box:calls())
      assert.equal(0, #timers)
    end)

    it("starts a clean run on a second MAIL_SHOW and kills the old chain", function()
      open({ EXPIRED(5), SALE(1) })
      box:refuse(5)
      press()
      tick()
      GC.MailCollect.OnMailShow()
      assert.same({ true, false }, box:openingCalls())
      local before = #box:calls()
      -- The old chain's timer is still queued; it is stale and does nothing.
      for _, fn in ipairs(timers) do fn() end
      assert.equal(before, #box:calls())
      timers = {}
      -- Skip sets are empty again: the refused lot is tried once more on the new visit.
      press()
      local again = 0
      for _, call in ipairs(box:calls()) do if call.fn == "TakeInboxItem" then again = again + 1 end end
      assert.is_true(again >= 2)
      assert.same({ true, false, true }, box:openingCalls())
    end)

    -- Blizzard opens a letter in OpenMailFrame, anchored TOPLEFT to InboxFrame's TOPRIGHT and as tall
    -- as the mail window (Blizzard_MailFrame/MailFrame.xml), so the card's old place right of the
    -- mail window's top was under the letter. Under the mail window, below the tabs that hang
    -- 30 px under its bottom edge (MailFrameTab1: BOTTOMLEFT 14, -30), nothing of Blizzard's mail
    -- covers it.
    it("sits under the mail window, below its tabs, where an open letter never reaches", function()
      open({ SALE(1) })
      assert.equal(1, card():GetNumPoints())
      local point, relative, relativePoint, _, y = card():GetPoint(1)
      assert.equal("TOPLEFT", point)
      assert.equal(_G.MailFrame, relative)
      assert.equal("BOTTOMLEFT", relativePoint)
      assert.is_true(y < -30)
    end)

    it("does nothing until MailFrame exists", function()
      _G.MailFrame = nil
      install({ SALE(1) })
      GC.MailCollect.OnMailShow()
      GC.MailCollect.OnInboxUpdate()
      GC.MailCollect.OnMailClosed()
      assert.same({}, box:calls())
    end)
  end)

  describe("the client's own events", function()
    local function fire(event, ...)
      local frame = eventFrames[#eventFrames]
      W.state(frame).scripts.OnEvent(frame, event, ...)
    end

    it("listens for MAIL_FAILED and UI_ERROR_MESSAGE only while running", function()
      open({ SALE(1) })
      press()
      local frame = eventFrames[#eventFrames]
      assert.is_true(frame:IsEventRegistered("MAIL_FAILED"))
      assert.is_true(frame:IsEventRegistered("UI_ERROR_MESSAGE"))
      runOut()
      assert.is_false(frame:IsEventRegistered("MAIL_FAILED"))
      assert.is_false(frame:IsEventRegistered("UI_ERROR_MESSAGE"))
    end)

    it("forwards a failed item to the loop", function()
      open({ EXPIRED(5), SALE(1) })
      box:refuse(5)
      press()
      assert.equal(1, #GC.MailReturns.Entries())
      fire("MAIL_FAILED", 5)
      assert.equal(0, #GC.MailReturns.Entries())
      runOut()
      local itemTakes = 0
      for _, call in ipairs(box:calls()) do if call.fn == "TakeInboxItem" then itemTakes = itemTakes + 1 end end
      assert.equal(1, itemTakes)
    end)

    it("reads the message as the second argument of UI_ERROR_MESSAGE", function()
      open({ EXPIRED(5), EXPIRED(6) })
      press()
      fire("UI_ERROR_MESSAGE", 50, "Inventory is full.")
      runOut()
      assert.equal(1, #box:calls())
      assert.equal(0, #GC.MailReturns.Entries())
    end)
  end)

  -- Ledger first, proven with the real ledger reading the same mailbox double: the sale and the
  -- won auction are in the ledger at the moment their gold and items are taken, and a sale whose
  -- invoice the ledger cannot read yet is left until it can.
  describe("ledger first, with the real ledger", function()
    local WON = { sender = "Auction House", subject = "Auction won: Wool Cloth", auction = true,
      invoice = { invoiceType = "buyer", itemName = "Wool Cloth", bid = 700 },
      items = { [1] = { itemID = 2592, count = 5 } } }
    local recordedAtTake

    local function kinds()
      local seen = {}
      for _, entry in ipairs(GC.db.ledger) do seen[#seen + 1] = entry.kind .. ":" .. tostring(entry.itemName) end
      table.sort(seen)
      return seen
    end

    before_each(function()
      GC.Ledger.ScanInbox = realScanInbox
      recordedAtTake = {}
    end)

    local function watchTakes()
      local money, item = _G.TakeInboxMoney, _G.TakeInboxItem
      _G.TakeInboxMoney = function(i) recordedAtTake[#recordedAtTake + 1] = kinds(); return money(i) end
      _G.TakeInboxItem = function(i, slot) recordedAtTake[#recordedAtTake + 1] = kinds(); return item(i, slot) end
    end

    it("has the sale and the won auction in the ledger when their gold and items are taken", function()
      install({ SALE(1), WON })
      watchTakes()
      GC.MailCollect.OnMailShow()
      press()
      runOut()
      assert.same({ "buy:Wool Cloth", "sale:Cloth 1" }, kinds())
      assert.equal(2, #box:calls())
      assert.same({ "buy:Wool Cloth", "sale:Cloth 1" }, recordedAtTake[1])
      assert.same({ "buy:Wool Cloth", "sale:Cloth 1" }, recordedAtTake[2])
      assert.equal(0, box:rowCount())
    end)

    it("leaves a sale whose invoice the ledger cannot read yet, and takes it once the ledger can", function()
      install({ { sender = "Auction House", subject = "Auction successful: Cloth 1", money = 1000, auction = true,
        invoice = { invoiceType = "seller", itemName = nil } } })
      GC.MailCollect.OnMailShow()
      assert.equal("Collect", button().label)
      press()
      assert.same({}, box:calls())
      assert.same({}, GC.db.ledger)

      box:row(1).invoice.itemName = "Cloth 1"
      GC.MailCollect.OnInboxUpdate()
      assert.equal("Collect 1", button().label)
      press()
      runOut()
      assert.same({ "sale:Cloth 1" }, kinds())
      assert.equal(1, #box:calls())
      assert.equal("Collected 1000c from 1 sale.", printed[#printed])
    end)
  end)

  describe("the settings", function()
    it("counts a missing setting as on", function()
      local on = GC.MailCollect.Enabled()
      assert.same({ sales = true, returns = true, purchases = true, players = true }, on)
    end)

    it("honours a saved false", function()
      GC.db.settings.sniper.collectPlayers = false
      assert.is_false(GC.MailCollect.Enabled().players)
      assert.is_true(GC.MailCollect.Enabled().sales)
    end)
  end)
end)
