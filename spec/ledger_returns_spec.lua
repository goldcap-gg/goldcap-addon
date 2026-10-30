local helper = require("spec.spec_helper")
local Mailbox = require("spec.support.mail_inbox")

-- The lots that came back reach SELL's unsold rounds through the ledger's inbox scan
-- (Core/Ledger.lua, ScanInbox), which reads every row on MAIL_SHOW and MAIL_INBOX_UPDATE whoever
-- then takes the mail: Blizzard's Open All, Postal, TSM's mailing or a click on the attachment. A mail read on many scans is logged once, by
-- the rule the ledger keeps for an invoice: the same lot in this character's inbox, by item, reason
-- and expiry, is the same mail until a complete scan no longer holds it.
describe("Ledger scan, the lots that came back", function()
  local GC, db, box, getItemCalls, hidden, last
  local DAY = 86400
  local CONTEXT = { char = "A-B", region = "eu" }
  local SUBJECTS = { expired = "Auction expired: %s", cancelled = "Auction canceled: %s", outbid = "Outbid on %s" }

  local function lot(itemID, stacks, subject)
    local items = {}
    for slot, count in ipairs(stacks) do items[slot] = { itemID = itemID, count = count } end
    return { sender = "Auction House", subject = subject or "Auction expired: Silk", auction = true,
      daysLeft = 30, items = items }
  end

  -- Time passes for the mail as it does in the client: days left count down.
  local function clockTo(now)
    for i = 1, box:rowCount() do
      local row = box:row(i)
      row.daysLeft = row.daysLeft - (now - last) / DAY
    end
    last = now
  end

  local function scan(now, context, opening)
    clockTo(now)
    local api = box.api
    return GC.Ledger.ScanInbox({
      GetInboxNumItems = api.GetInboxNumItems,
      GetInboxHeaderInfo = api.GetInboxHeaderInfo,
      GetInboxInvoiceInfo = api.GetInboxInvoiceInfo,
      -- A hidden row's attachments are not loaded yet: the client names none of them.
      GetInboxItem = function(index, slot)
        getItemCalls = getItemCalls + 1
        if hidden[index] then return nil end
        return api.GetInboxItem(index, slot)
      end,
      noInvoiceSubjects = SUBJECTS,
    }, context or CONTEXT, now, opening)
  end

  local function entries() return GC.MailReturns.Entries() end

  before_each(function()
    GC = helper.loadModule("Core/Ledger.lua")
    db = {}
    GC.Ledger.Init(db)
    helper.loadModule("Core/MailReturns.lua", GC)
    GC.MailReturns.Init(db)
    getItemCalls, hidden, last = 0, {}, 1000
  end)

  it("logs a lot the first time a scan reads it, its stacks' count summed, at the scan's time", function()
    box = Mailbox.new({ lot(5, { 200, 200, 100 }) })
    scan(1000, nil, true)
    assert.same({ { itemID = 5, count = 500, reason = "expired", at = 1000 } }, entries())
  end)

  it("logs a cancelled lot as cancelled and an outbid mail not at all", function()
    box = Mailbox.new({ lot(5, { 3 }, "Auction canceled: Silk"),
      { sender = "Auction House", subject = "Outbid on Silk", auction = true, money = 500, daysLeft = 30 } })
    scan(1000, nil, true)
    assert.same({ { itemID = 5, count = 3, reason = "cancelled", at = 1000 } }, entries())
  end)

  it("logs a mail read on every scan once, even when its days left jump half an hour", function()
    box = Mailbox.new({ lot(5, { 20 }) })
    scan(1000, nil, true)
    scan(1060)
    box:row(1).daysLeft = box:row(1).daysLeft + 1800 / DAY
    scan(1063)
    scan(4000)
    assert.equal(1, #entries())
  end)

  it("counts a lot taken by hand after the scan saw it once", function()
    helper.loadModule("Core/SellRounds.lua", GC)
    GC.SellRounds.Init(db)
    box = Mailbox.new({ lot(5, { 20 }) })
    scan(1000, nil, true)
    GC.SellRounds.Ingest(entries(), 1000)
    -- The player clicks the attachment: the auction mail goes, and the scan on the update sees
    -- an inbox without it.
    box:removeRow(1)
    scan(1010)
    GC.SellRounds.Ingest(entries(), 1010)
    assert.equal(1, #entries())
    assert.equal(1, GC.SellRounds.Rounds(5))
    GC.SellRounds.Ingest(entries(), 1000 + GC.SellRounds.SETTLE_SECONDS + 1)
    assert.equal(1, GC.SellRounds.Rounds(5))
  end)

  it("keeps a lot taken one stack at a time as the one lot it is", function()
    box = Mailbox.new({ lot(5, { 200, 200, 100 }) })
    scan(1000, nil, true)
    box:row(1).items[3] = nil
    scan(1005)
    box:row(1).items[2] = nil
    scan(1010)
    assert.same({ { itemID = 5, count = 500, reason = "expired", at = 1000 } }, entries())
  end)

  it("logs two lots that read the same as two, once each", function()
    box = Mailbox.new({ lot(5, { 1 }), lot(5, { 1 }) })
    scan(1000, nil, true)
    scan(1010)
    assert.equal(2, #entries())
    box:removeRow(1)
    scan(1020)
    assert.equal(2, #entries())
  end)

  it("logs a new lot of the same item once the first has gone", function()
    box = Mailbox.new({ lot(5, { 1 }) })
    scan(1000, nil, true)
    box:removeRow(1)
    scan(1010)
    -- Two hours later the next copy of the flip comes back.
    box:addRow(lot(5, { 1 }))
    scan(1000 + 7200)
    assert.equal(2, #entries())
    assert.equal(1000 + 7200, entries()[2].at)
  end)

  it("waits for a lot whose attachments are not loaded, and a scan that cannot read one keeps every lot", function()
    box = Mailbox.new({ lot(5, { 1 }), lot(6, { 1 }) })
    hidden[2] = true
    scan(1000, nil, true)
    assert.same({ { itemID = 5, count = 1, reason = "expired", at = 1000 } }, entries())
    -- Item 5's lot cannot be read on this pass: it is not gone, and the next read is no new lot.
    hidden[1], hidden[2] = true, nil
    scan(1010)
    hidden[1] = nil
    scan(1020)
    assert.equal(2, #entries())
    assert.equal(6, entries()[2].itemID)
  end)

  it("never lets another character's inbox decide this character's lots are gone", function()
    box = Mailbox.new({ lot(5, { 1 }) })
    scan(1000, nil, true)
    local mine = box
    -- The other character's inbox, read whole: a complete scan without this character's lot.
    box = Mailbox.new({ { sender = "Friend", subject = "Hi", canReply = true, daysLeft = 30 } })
    scan(1010, { char = "C-B", region = "eu" }, true)
    box = mine
    scan(1020)
    assert.equal(1, #entries())
  end)

  it("reads no attachment and logs nothing where the returns log is not loaded (WoW: Forever)", function()
    GC.MailReturns = nil
    db = {}
    GC.Ledger.Init(db)
    box = Mailbox.new({ lot(5, { 1 }) })
    scan(1000, nil, true)
    assert.equal(0, getItemCalls)
    assert.is_nil(db.mailReturns)
    assert.is_nil(db.mailReturnsSeen)
  end)

  -- A sale of the item after its lot came back sets the rounds back to 0, however both mails
  -- were taken.
  describe("and a sale", function()
    before_each(function()
      helper.loadModule("Core/Acquisitions.lua", GC)
      helper.loadModule("Core/SoldView.lua", GC)
      helper.loadModule("Core/SellRounds.lua", GC)
      GC.Acquisitions.Init(db)
      GC.SellRounds.Init(db)
    end)

    after_each(function() GC.SellRounds, GC.SoldView = nil, nil end)

    it("still resets the rounds", function()
      GC.Acquisitions.RecordPost("commodity:210930", 210930, "Ironclaw Ore", CONTEXT.char, CONTEXT.region, 20, 950)
      box = Mailbox.new({ lot(210930, { 20 }, "Auction expired: Ironclaw Ore") })
      scan(1000, nil, true)
      box:removeRow(1)
      scan(1010)
      GC.SellRounds.Ingest(entries(), 1010)
      assert.equal(1, GC.SellRounds.Rounds(210930))
      box:addRow({ sender = "Auction House", subject = "Auction successful: Ironclaw Ore", money = 400000,
        auction = true, daysLeft = 30,
        invoice = { invoiceType = "seller", itemName = "Ironclaw Ore", bid = 400000, buyout = 400000, count = 20 } })
      scan(9000)
      GC.SellRounds.Ingest(entries(), 9000)
      assert.equal(0, GC.SellRounds.Rounds(210930))
    end)

    -- Both stamped with the scan's `now`. A batch's unsold lots expire after its sales, so the
    -- lot is the later one: the visit leaves a round.
    it("counts a lot read in the same scan as a sale of the item as after the sale", function()
      GC.Acquisitions.RecordPost("commodity:210930", 210930, "Ironclaw Ore", CONTEXT.char, CONTEXT.region, 40, 950)
      box = Mailbox.new({ lot(210930, { 20 }, "Auction expired: Ironclaw Ore"),
        { sender = "Auction House", subject = "Auction successful: Ironclaw Ore", money = 400000,
          auction = true, daysLeft = 30,
          invoice = { invoiceType = "seller", itemName = "Ironclaw Ore", bid = 400000, buyout = 400000, count = 20 } } })
      scan(1000, nil, true)
      assert.same({ { itemID = 210930, count = 20, reason = "expired", at = 1000 } }, entries())
      assert.equal(210930, next(db.sellRounds.items))
      assert.equal(1000, db.sellRounds.items[210930].soldAt)
      GC.SellRounds.Ingest(entries(), 1000)
      assert.equal(1, GC.SellRounds.Rounds(210930))
      GC.SellRounds.Ingest(entries(), 1000 + GC.SellRounds.SETTLE_SECONDS + 1)
      assert.equal(1, GC.SellRounds.Rounds(210930))
    end)
  end)
end)
