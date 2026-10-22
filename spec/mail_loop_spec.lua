local helper = require("spec.spec_helper")
local Mailbox = require("spec.support.mail_inbox")

describe("MailLoop, the paced take loop", function()
  local GC, box, loop, events, now, bags, enabled, patterns
  local ALL = { sales = true, returns = true, purchases = true, players = true }
  local DELAY = 0.15

  local SALE = function(n) return { sender = "Auction House", subject = "Auction successful: Cloth " .. n,
    money = 1000 * n, auction = true, invoice = { invoiceType = "seller", itemName = "Cloth " .. n } } end
  local EXPIRED = function(itemID, count, subject) return { sender = "Auction House",
    subject = subject or "Auction expired: Silk", auction = true,
    items = { [1] = { itemID = itemID, count = count } } } end

  local function build(rows, opts)
    box = Mailbox.new(rows, opts)
    bags = { free = 20 }
    events = {}
    now = 100
    local flat = box:flat(bags)
    local takeMoney, takeItem, opening = flat.TakeInboxMoney, flat.TakeInboxItem, flat.SetOpeningAll
    flat.TakeInboxMoney = function(i) events[#events + 1] = "money:" .. i; return takeMoney(i) end
    flat.TakeInboxItem = function(i, slot) events[#events + 1] = "item:" .. i .. ":" .. slot; return takeItem(i, slot) end
    flat.SetOpeningAll = function(flag) events[#events + 1] = "opening:" .. tostring(flag); return opening(flag) end
    enabled = ALL
    loop = GC.MailLoop.New({
      api = flat, patterns = patterns,
      enabled = function() return enabled end,
      scanLedger = function() events[#events + 1] = "scan" end,
      epoch = function() return 5000 end,
      errors = { full = "Inventory is full.", unique = "You can't carry any more of those items." },
    })
  end

  -- One full cycle: the client answers the pending take, the clock moves past the pacing delay.
  local function cycle()
    box:advance()
    now = now + DELAY + 0.01
    return loop:Step(now)
  end

  local function runToEnd(limit)
    local last
    for _ = 1, limit or 60 do
      last = cycle()
      if loop:State() == "done" then break end
    end
    return last
  end

  before_each(function()
    _G.RETRIEVING_DATA = "Retrieving data..."
    GC = helper.loadModule("Core/Ledger.lua")
    helper.loadModule("Core/MailReturns.lua", GC)
    helper.loadModule("Core/MailClassify.lua", GC)
    helper.loadModule("Core/MailLoop.lua", GC)
    GC.Util = GC.Util or {}
    GC.Util.CoinText = function(c) return c .. "c" end
    GC.MailReturns.Init({})
    patterns = GC.MailClassify.Patterns({ expired = "Auction expired: %s", removed = "Auction canceled: %s",
      outbid = "Outbid on %s" })
  end)

  after_each(function() _G.RETRIEVING_DATA = nil end)

  describe("pacing", function()
    it("opens, scans the ledger and takes once at Start", function()
      build({ SALE(1), SALE(2) })
      assert.is_true(loop:Start(now))
      assert.same({ "opening:true", "scan", "scan", "money:1" }, events)
      assert.equal(1, #box:calls())
      assert.equal("running", loop:State())
    end)

    it("waits until 0.15 s have passed and while a command is pending", function()
      build({ SALE(1), SALE(2) })
      loop:Start(now)
      assert.equal("wait", loop:Step(now + 0.05))
      assert.equal(1, #box:calls())
      box:advance()
      assert.equal("wait", loop:Step(now + 0.14))
      assert.equal(1, #box:calls())
      assert.equal("took", loop:Step(now + 0.15))
      assert.equal(2, #box:calls())
      -- A take is pending again, and later than the delay it still waits.
      assert.equal("wait", loop:Step(now + 5))
      assert.equal(2, #box:calls())
    end)
  end)

  describe("what it takes", function()
    it("takes money first, then the items from the last slot down", function()
      build({ { sender = "Friend", subject = "Hi", canReply = true, money = 1000,
        items = { [1] = { itemID = 11, count = 1 }, [2] = { itemID = 12, count = 1 } } } })
      loop:Start(now)
      runToEnd()
      assert.same({ { fn = "TakeInboxMoney", index = 1 }, { fn = "TakeInboxItem", index = 1, slot = 2 },
        { fn = "TakeInboxItem", index = 1, slot = 1 } }, box:calls())
    end)

    it("takes the four takeable mails of a ten mail box and nothing else", function()
      build(Mailbox.tenMail())
      loop:Start(now)
      runToEnd()
      -- The sale (row 1) and the won auction (row 2 once the sale is gone) are deleted, the
      -- expired lot goes too, and the player's gold stays as a mail.
      assert.same({
        { fn = "TakeInboxMoney", index = 1 },
        { fn = "TakeInboxItem", index = 1, slot = 1 },
        { fn = "TakeInboxItem", index = 1, slot = 1 },
        { fn = "TakeInboxMoney", index = 1 },
      }, box:calls())
      assert.equal("done", loop:State())
      assert.equal(1, loop:Result().sales)
      assert.equal(1, loop:Result().returns)
      assert.equal(1, loop:Result().purchases)
      assert.equal(1, loop:Result().players)
      assert.equal(1, loop:Result().loading)
    end)

    it("refuses to start with nothing takeable and calls nothing", function()
      build({ { sender = "Friend", subject = "Pay", canReply = true, cod = 5, items = { [1] = { itemID = 1, count = 1 } } },
        { sender = "GM", isGM = true, money = 5 } })
      assert.is_false(loop:Start(now))
      assert.same({}, events)
      assert.equal("idle", loop:State())
    end)

    it("refuses to start with every group off", function()
      build({ SALE(1), EXPIRED(5, 1) })
      enabled = { sales = false, returns = false, purchases = false, players = false }
      assert.is_false(loop:Start(now))
      assert.same({}, events)
    end)

    it("refuses to start while a command is pending", function()
      build({ SALE(1), SALE(2) })
      box.api.TakeInboxMoney(1)
      assert.is_false(loop:Start(now))
      assert.same({}, events)
    end)

    it("reads the switches fresh at every step", function()
      build({ SALE(1), EXPIRED(5, 1), SALE(2) })
      loop:Start(now)
      enabled = { sales = false, returns = true, purchases = true, players = true }
      runToEnd()
      assert.equal(1, loop:Result().sales)
      assert.equal(1, loop:Result().returns)
    end)
  end)

  describe("ledger first", function()
    it("scans the ledger right before a sale take and a purchase take", function()
      build({ SALE(1), { sender = "Auction House", subject = "Auction won: Wool", auction = true,
        invoice = { invoiceType = "buyer", itemName = "Wool" }, items = { [1] = { itemID = 2592, count = 5 } } } })
      loop:Start(now)
      runToEnd()
      assert.same({ "opening:true", "scan", "scan", "money:1", "scan", "item:1:1", "opening:false" }, events)
    end)

    it("records an expired lot before taking it", function()
      build({ EXPIRED(2589, 20) })
      loop:Start(now)
      assert.same({ { itemID = 2589, count = 20, reason = "expired", at = 5000 } }, GC.MailReturns.Entries())
      assert.same({ "opening:true", "scan", "item:1:1" }, events)
    end)

    it("records a cancelled lot with its own reason", function()
      build({ EXPIRED(2589, 3, "Auction canceled: Silk") })
      loop:Start(now)
      assert.equal("cancelled", GC.MailReturns.Entries()[1].reason)
    end)
  end)

  describe("indices move under the loop", function()
    it("targets row 1 every time while sale mails are deleted, never index 3", function()
      build({ SALE(1), SALE(2), SALE(3) })
      loop:Start(now)
      runToEnd()
      assert.same({ { fn = "TakeInboxMoney", index = 1 }, { fn = "TakeInboxMoney", index = 1 },
        { fn = "TakeInboxMoney", index = 1 } }, box:calls())
      assert.equal(6000, loop:Result().gold)
      assert.equal(3, loop:Result().sales)
    end)
  end)

  -- Blizzard's MailFrame refreshes the inbox by itself while it shows fewer than 100 rows and more
  -- exist (MailFrame.lua, InboxFrame_Update), so rows can come in between a take and the step that
  -- confirms it. A take is confirmed by the mail it was made on, never by the row index.
  describe("the inbox refreshing under a take", function()
    it("keeps a lot taken just before rows came in at the back, and takes the rest of that item", function()
      build({ EXPIRED(5, 20), EXPIRED(5, 20), EXPIRED(5, 20) }, { hidden = { EXPIRED(9, 20) } })
      loop:Start(now)
      box:advance()
      box:refreshNow()
      runToEnd()
      assert.equal(0, box:rowCount())
      assert.equal(4, #box:calls())
      assert.equal(4, loop:Result().returns)
      assert.equal(4, #GC.MailReturns.Entries())
    end)

    it("counts the gold of a sale taken just before new mail came in at the front", function()
      build({ SALE(1), SALE(2) })
      loop:Start(now)
      box:advance()
      box:refreshNow({ SALE(9) })
      runToEnd()
      assert.equal(3, loop:Result().sales)
      assert.equal(12000, loop:Result().gold)
      assert.equal(0, box:rowCount())
      assert.equal(3, #box:calls())
    end)

    it("counts a mail once when new mail comes in at the front between two of its takes", function()
      build({ { sender = "Friend", subject = "Hi", canReply = true, money = 100,
        items = { [1] = { itemID = 11, count = 1 }, [2] = { itemID = 12, count = 1 } } } })
      loop:Start(now)
      box:advance()
      box:refreshNow({ { sender = "Other", subject = "Yo", canReply = true, money = 5 } })
      runToEnd()
      assert.equal(2, loop:Result().players)
      assert.equal(4, #box:calls())
    end)
  end)

  describe("the bags", function()
    it("leaves item mails alone with no free slot but still takes gold", function()
      build({ SALE(1), EXPIRED(5, 1), EXPIRED(6, 1) })
      bags.free = 0
      loop:Start(now)
      runToEnd()
      assert.same({ { fn = "TakeInboxMoney", index = 1 } }, box:calls())
      assert.equal("bags", loop:Result().reason)
      assert.equal(2, loop:Result().itemsLeft)
      assert.same({ "opening:true", "scan", "scan", "money:1", "opening:false" }, events)
    end)

    it("stops item takes after the client says the bags are full", function()
      build({ EXPIRED(5, 1), EXPIRED(6, 1) })
      loop:Start(now)
      loop:OnUiError("Inventory is full.")
      runToEnd()
      assert.equal(1, #box:calls())
      assert.equal("bags", loop:Result().reason)
      assert.equal(0, loop:Result().returns)
      assert.same({}, GC.MailReturns.Entries())
    end)
  end)

  describe("failures", function()
    it("skips an item the client reports failed and retracts its returns entry", function()
      build({ EXPIRED(5, 1), EXPIRED(5, 2), EXPIRED(6, 1) })
      box:refuse(5)
      loop:Start(now)
      loop:OnMailFailed(5)
      runToEnd()
      -- Row 1 stays (refused), both item 5 mails are skipped, item 6 is taken.
      local took6
      for _, call in ipairs(box:calls()) do if call.index == 3 then took6 = true end end
      assert.is_true(took6)
      assert.equal(1, #GC.MailReturns.Entries())
      assert.equal(6, GC.MailReturns.Entries()[1].itemID)
      assert.equal("done", loop:Result().reason)
    end)

    it("skips the in-flight item when the client says it is unique", function()
      build({ EXPIRED(5, 1), EXPIRED(6, 1) })
      loop:Start(now)
      loop:OnUiError("You can't carry any more of those items.")
      runToEnd()
      assert.equal(1, #GC.MailReturns.Entries())
      assert.equal(6, GC.MailReturns.Entries()[1].itemID)
    end)

    it("declares a take that does nothing stuck, skips it and carries on", function()
      build({ EXPIRED(5, 1), EXPIRED(6, 1) })
      box:refuse(5)
      loop:Start(now)
      runToEnd()
      assert.equal("done", loop:State())
      assert.equal("done", loop:Result().reason)
      assert.equal(1, loop:Result().returns)
      assert.equal(1, #GC.MailReturns.Entries())
      assert.equal(6, GC.MailReturns.Entries()[1].itemID)
      local againstRefused = 0
      for _, call in ipairs(box:calls()) do if call.index == 1 and call.slot == 1 then againstRefused = againstRefused + 1 end end
      assert.equal(1, againstRefused)
    end)
  end)

  describe("more mail than the inbox shows", function()
    local HIDDEN = { SALE(7), SALE(8) }

    it("asks the client for the rest, waits for the update, then takes it", function()
      build({ SALE(1), SALE(2), SALE(3) }, { hidden = HIDDEN })
      loop:Start(now)
      runToEnd(3)
      assert.equal("refresh", loop:State())
      assert.equal(1, box:checkCalls())
      assert.equal("refresh", loop:Step(now + 5))
      assert.equal(1, box:checkCalls())
      box:advance()
      loop:OnInboxUpdate()
      assert.equal("running", loop:State())
      runToEnd()
      assert.equal(5, loop:Result().sales)
      assert.equal("done", loop:Result().reason)
    end)

    it("shows the seconds when the client may not be asked yet", function()
      build({ SALE(1) }, { hidden = HIDDEN })
      box:setCanCheck(false, 9)
      loop:Start(now)
      runToEnd(2)
      assert.equal("refresh", loop:State())
      assert.equal(9, loop:WaitSeconds())
      assert.equal(0, box:checkCalls())
      box:setCanCheck(true, 0)
      assert.equal("refresh", loop:Step(now + 20))
      assert.equal(1, box:checkCalls())
      assert.is_nil(loop:WaitSeconds())
    end)

    -- Blizzard's MailFrame asks for the rest by itself (MailFrame.lua, MailFrame_RefreshInbox), so
    -- while the loop waits for its own turn to ask, the rows can arrive without it.
    it("carries on when Blizzard's own refresh brings the rows while it waits to ask", function()
      build({ SALE(1) }, { hidden = HIDDEN })
      box:setCanCheck(false, 9)
      loop:Start(now)
      runToEnd(1)
      assert.equal("refresh", loop:State())
      box:refreshNow()
      loop:OnInboxUpdate()
      assert.equal("running", loop:State())
      runToEnd()
      assert.equal(3, loop:Result().sales)
      assert.equal("done", loop:Result().reason)
      assert.equal(0, box:rowCount())
      assert.equal(0, box:checkCalls())
    end)

    it("carries on at its next step when the rows came in without an update it saw", function()
      build({ SALE(1) }, { hidden = HIDDEN })
      box:setCanCheck(false, 9)
      loop:Start(now)
      runToEnd(1)
      box:refreshNow()
      runToEnd()
      assert.equal(3, loop:Result().sales)
      assert.equal(0, box:rowCount())
    end)

    it("stops waiting when the client never answers its refresh", function()
      build({ SALE(1) }, { hidden = HIDDEN })
      loop:Start(now)
      runToEnd(1)
      assert.equal("refresh", loop:State())
      assert.equal(1, box:checkCalls())
      local asked = now
      assert.equal("refresh", loop:Step(asked + GC.MailLoop.REFRESH_TIMEOUT - 1))
      assert.equal("done", loop:Step(asked + GC.MailLoop.REFRESH_TIMEOUT))
      assert.equal("done", loop:Result().reason)
      assert.same({ true, false }, box:openingCalls())
    end)

    it("ends when a refresh brings nothing", function()
      build({ SALE(1) }, { hidden = HIDDEN })
      loop:Start(now)
      runToEnd(1)
      assert.equal("refresh", loop:State())
      loop:OnInboxUpdate()
      assert.equal("done", loop:State())
      assert.equal("done", loop:Result().reason)
    end)

    it("never refreshes more than ten times", function()
      build({ SALE(1) }, { hidden = HIDDEN })
      local api = box:flat(bags)
      -- Each refresh shows one more mail while the total keeps growing.
      local grown = 1
      local shown = api.GetInboxNumItems
      api.GetInboxNumItems = function() local n, total = shown(); return n, total + grown end
      loop = GC.MailLoop.New({ api = api, patterns = patterns, enabled = function() return enabled end,
        scanLedger = function() end, epoch = function() return 5000 end, errors = {} })
      loop:Start(now)
      local refreshes = 0
      for _ = 1, 100 do
        box:advance()
        now = now + 1
        local result = loop:Step(now)
        if loop:State() == "done" then break end
        if loop:State() == "refresh" then
          refreshes = refreshes + 1
          grown = grown + 1
          loop:OnInboxUpdate()
        end
        assert.is_true(result ~= nil)
      end
      assert.is_true(refreshes <= 10)
      assert.equal("done", loop:State())
    end)
  end)

  describe("finishing", function()
    it("Stop ends the run once, and a later Step makes no call", function()
      build({ SALE(1), SALE(2) })
      loop:Start(now)
      loop:Stop("stopped")
      loop:Stop("stopped")
      assert.equal("stopped", loop:Result().reason)
      assert.same({ true, false }, box:openingCalls())
      local calls = #box:calls()
      box:advance()
      assert.equal("done", loop:Step(now + 1))
      assert.equal(calls, #box:calls())
    end)

    it("OnClosed ends the run as closed", function()
      build({ SALE(1), SALE(2) })
      loop:Start(now)
      loop:OnClosed()
      assert.equal("closed", loop:Result().reason)
      assert.same({ true, false }, box:openingCalls())
    end)

    it("OnClosed while idle changes nothing", function()
      build({ SALE(1) })
      loop:OnClosed()
      assert.same({}, box:openingCalls())
      assert.equal("idle", loop:State())
    end)

    it("a second Start begins with empty skip sets and tally", function()
      build({ EXPIRED(5, 1), EXPIRED(6, 1) })
      box:refuse(5)
      loop:Start(now)
      runToEnd()
      assert.equal(1, loop:Result().returns)
      box:refuse(0)
      assert.is_true(loop:Start(now + 100))
      assert.equal(0, loop:Result().returns)
      assert.equal("running", loop:State())
    end)

    it("calls SetOpeningAll(false) exactly once however the run ends", function()
      build({ SALE(1) })
      loop:Start(now)
      runToEnd()
      loop:Stop("stopped")
      loop:OnClosed()
      assert.same({ true, false }, box:openingCalls())
    end)
  end)

  describe("counting mails, not takes", function()
    it("counts a player mail with gold and two items once", function()
      build({ { sender = "Friend", subject = "Hi", canReply = true, money = 100,
        items = { [1] = { itemID = 11, count = 1 }, [2] = { itemID = 12, count = 1 } } } })
      loop:Start(now)
      runToEnd()
      assert.equal(1, loop:Result().players)
      assert.equal(3, #box:calls())
    end)
  end)

  describe("Summary", function()
    it("joins the present parts and the loading line", function()
      assert.equal("Collected 12340000c from 18 sales, 6 lots came back, 3 purchases. 2 still loading.",
        GC.MailLoop.Summary({ gold = 12340000, sales = 18, returns = 6, purchases = 3, players = 0, loading = 2 }))
    end)

    it("uses the singular forms for one", function()
      assert.equal("Collected 5c from 1 sale, 1 lot came back, 1 purchase, 1 other mail.",
        GC.MailLoop.Summary({ gold = 5, sales = 1, returns = 1, purchases = 1, players = 1, loading = 0 }))
    end)

    it("says there was nothing to collect", function()
      assert.equal("Nothing to collect.", GC.MailLoop.Summary({ gold = 0, sales = 0, returns = 0, purchases = 0, players = 0, loading = 0 }))
    end)

    it("ends a bags result with the bags sentence", function()
      local text = GC.MailLoop.Summary({ reason = "bags", gold = 7, sales = 1, returns = 0, purchases = 0, players = 0, loading = 0 })
      assert.equal("Collected 7c from 1 sale. The bags are full, the rest stays in the mailbox.", text)
    end)
  end)
end)
