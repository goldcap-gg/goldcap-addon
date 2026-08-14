local helper = require("spec.spec_helper")

describe("Ledger inbox scan", function()
  local GC, db, context

  -- One inbox entry: the header fields the scanner reads, plus its invoice.
  local function mail(overrides)
    local m = {
      sender = "Auction House",
      subject = "Auction successful",
      daysLeft = 30,
      invoice = {
        invoiceType = "seller",
        itemName = "Ironclaw Ore",
        playerName = "Buyerguy",
        bid = 500000,
        buyout = 500000,
        deposit = 1000,
        consignment = 25000,
        moneyDelay = 0,
        etaHour = 0,
        etaMin = 0,
        count = 20,
        commerceAuction = true,
      },
      item = nil,
    }
    for k, v in pairs(overrides or {}) do
      if k == "invoice" then
        for ik, iv in pairs(v) do m.invoice[ik] = iv end
      else
        m[k] = v
      end
    end
    return m
  end

  local function apiFor(mails)
    return {
      GetInboxNumItems = function() return #mails end,
      GetInboxHeaderInfo = function(i)
        local m = mails[i]
        if not m then return nil end
        -- Mirrors the complete live return order through canReply, which is
        -- the locale-independent ordinary-mail signal for unreadable invoices.
        return nil, nil, m.sender, m.subject, 0, 0, m.daysLeft, m.item ~= nil,
          false, false, false, m.canReply
      end,
      GetInboxInvoiceInfo = function(i)
        local inv = mails[i] and mails[i].invoice
        if not inv then return nil end
        return inv.invoiceType, inv.itemName, inv.playerName, inv.bid, inv.buyout,
          inv.deposit, inv.consignment, inv.moneyDelay, inv.etaHour, inv.etaMin,
          inv.count, inv.commerceAuction
      end,
      -- Signature is GetInboxItem(index, itemIndex) and BOTH are required in
      -- the live client. The mock enforces that, because a mock that accepted
      -- one argument is what let a one-argument call ship: it tested the
      -- assumption instead of the API.
      GetInboxItem = function(i, itemIndex)
        assert(type(i) == "number", "GetInboxItem needs a mail index")
        assert(type(itemIndex) == "number", "GetInboxItem needs an attachment index")
        local it = mails[i] and mails[i].item
        if not it then return nil end
        return it.name, it.itemID
      end,
    }
  end

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua")
    helper.loadModule("Core/Ledger.lua", GC)
    db = {}
    GC.Acquisitions.Init(db)
    GC.Ledger.Init(db)
    context = { char = "Belarsa-Dentarg", region = "eu" }
  end)

  it("records a completed sale with its proceeds, cut and deposit", function()
    local newCount = GC.Ledger.ScanInbox(apiFor({ mail() }), context, 1000)

    assert.equal(1, newCount)
    local e = GC.Ledger.GetEntries()[1]
    assert.equal("sale", e.kind)
    assert.equal("mail", e.source)
    assert.equal("Ironclaw Ore", e.itemName)
    assert.equal(20, e.qty)
    assert.equal(500000, e.total)
    assert.equal(25000, e.cut)
    assert.equal(1000, e.deposit)
    assert.is_false(e.pending)
    assert.equal("Belarsa-Dentarg", e.char)
    assert.equal("eu", e.region)
    -- The mail holds money, not the item: there is no id to read here, and
    -- the server resolves the name later.
    assert.is_nil(e.itemID)
  end)

  it("records a Sale Pending invoice as pending, with the money still to come", function()
    local pending = mail({ invoice = {
      invoiceType = "seller_temp_invoice", moneyDelay = 500000, etaHour = 1, etaMin = 0,
    } })
    GC.Ledger.ScanInbox(apiFor({ pending }), context, 1000)

    local e = GC.Ledger.GetEntries()[1]
    assert.is_true(e.pending)
    assert.equal(500000, e.total)
  end)

  it("does NOT double-count when a Sale Pending invoice later matures", function()
    local pending = mail({ invoice = {
      invoiceType = "seller_temp_invoice", moneyDelay = 500000, etaHour = 1, etaMin = 0,
    } })
    GC.Ledger.ScanInbox(apiFor({ pending }), context, 1000)

    -- One hour later the SAME mail reports as paid; daysLeft has ticked down.
    local paid = mail({ daysLeft = 30 - (3600 / 86400) })
    local newCount = GC.Ledger.ScanInbox(apiFor({ paid }), context, 1000 + 3600)

    assert.equal(0, newCount)
    assert.equal(1, #GC.Ledger.GetEntries())
    local e = GC.Ledger.GetEntries()[1]
    assert.is_false(e.pending)
    assert.equal(500000, e.total)
  end)

  it("consumes a paid seller invoice once only after its pending row matures", function()
    local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 210930,
      positionKey = "commodity:210930", itemName = "Ironclaw Ore", quantity = 20, total = 400000,
      acquiredAt = 900, evidenceKey = "buy:1", character = context.char, region = context.region })
    GC.Acquisitions.RecordPost("commodity:210930", 210930, "Ironclaw Ore", context.char, context.region, 20, 950)
    local pending = mail({ invoice = {
      invoiceType = "seller_temp_invoice", moneyDelay = 500000, etaHour = 1, etaMin = 0,
    } })

    GC.Ledger.ScanInbox(apiFor({ pending }), context, 1000)
    assert.equal(20, batch.remainingQty)
    assert.equal(0, #GC.Acquisitions.GetRealized(context))

    local paid = mail({ daysLeft = 30 - (3600 / 86400) })
    GC.Ledger.ScanInbox(apiFor({ paid }), context, 4600)
    assert.equal(0, batch.remainingQty)
    assert.equal(1, #GC.Acquisitions.GetRealized(context))

    GC.Ledger.ScanInbox(apiFor({ paid }), context, 4610)
    assert.equal(1, #GC.Acquisitions.GetRealized(context))
  end)

  it("does not re-add the same mail when the inbox refreshes minutes later", function()
    GC.Ledger.ScanInbox(apiFor({ mail() }), context, 1000)
    -- MAIL_INBOX_UPDATE fires constantly; four minutes of drift must not push
    -- the expiry into a different bucket and fork the row.
    local later = mail({ daysLeft = 30 - (240 / 86400) })
    local newCount = GC.Ledger.ScanInbox(apiFor({ later }), context, 1000 + 240)

    assert.equal(0, newCount)
    assert.equal(1, #GC.Ledger.GetEntries())
  end)

  it("records a purchase with its item id, which a buy mail does carry", function()
    local bought = mail({
      invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 },
    })
    GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000)

    local e = GC.Ledger.GetEntries()[1]
    assert.equal("buy", e.kind)
    assert.equal(210930, e.itemID)
    assert.equal(500000, e.total)
    assert.is_nil(e.decisionVersion) -- mail invoices have no Sniper decision evidence
  end)

  it("reconciles a repeated buyer-mail ledger update into one acquisition", function()
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })
    GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000)
    GC.Ledger.ScanInbox(apiFor({ bought }), context, 1010)

    assert.equal(1, #GC.Ledger.GetEntries())
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.is_true(GC.Acquisitions.GetAll()[1].evidenceKeys[GC.Ledger.GetEntries()[1].key])
  end)

  it("[FINAL C1] persists two identical buyer invoices one-to-one across repeat scans and scopes", function()
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })
    local twin = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })

    assert.equal(2, GC.Ledger.ScanInbox(apiFor({ bought, twin }), context, 1000))
    assert.equal(2, #GC.Ledger.GetEntries())
    assert.equal(2, #GC.Acquisitions.GetAll())
    assert.not_equal(GC.Ledger.GetEntries()[1].key, GC.Ledger.GetEntries()[2].key)

    local keys = { GC.Ledger.GetEntries()[1].key, GC.Ledger.GetEntries()[2].key }
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ bought, twin }), context, 1010))
    assert.equal(2, #GC.Ledger.GetEntries())
    assert.equal(2, #GC.Acquisitions.GetAll())
    assert.same(keys, { GC.Ledger.GetEntries()[1].key, GC.Ledger.GetEntries()[2].key })

    local other = { char = "Other-Realm", region = "us" }
    assert.equal(2, GC.Ledger.ScanInbox(apiFor({ bought, twin }), other, 1020))
    assert.equal(4, #GC.Ledger.GetEntries())
    assert.equal(2, #GC.Acquisitions.GetActive(context))
    assert.equal(2, #GC.Acquisitions.GetActive(other))
  end)

  it("[FINAL C1] consumes two identical paid seller occurrences and keeps invoice classes separate", function()
    local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 210930,
      positionKey = "commodity:210930", itemName = "Ironclaw Ore", quantity = 2, total = 200,
      acquiredAt = 900, evidenceKey = "buy:two-sales", character = context.char, region = context.region })
    GC.Acquisitions.RecordPost("commodity:210930", 210930, "Ironclaw Ore",
      context.char, context.region, 2, 950)
    local sale = mail({ invoice = { count = 1, bid = 500, buyout = 500,
      deposit = 0, consignment = 25 } })
    local twin = mail({ invoice = { count = 1, bid = 500, buyout = 500,
      deposit = 0, consignment = 25 } })

    assert.equal(2, GC.Ledger.ScanInbox(apiFor({ sale, twin }), context, 1000))
    assert.equal(0, batch.remainingQty)
    assert.equal(2, #GC.Acquisitions.GetRealized(context))
    assert.not_equal(GC.Ledger.GetEntries()[1].key, GC.Ledger.GetEntries()[2].key)

    local bought = mail({ invoice = { invoiceType = "buyer", count = 1, bid = 500,
      buyout = 500, deposit = 0, consignment = 25 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })
    assert.equal(1, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000))
    assert.equal(3, #GC.Ledger.GetEntries())
    assert.equal("buy", GC.Ledger.GetEntries()[3].kind)
  end)

  it("keeps identical pending seller occurrences paired one-to-one as they mature", function()
    local pending = mail({ invoice = { invoiceType = "seller_temp_invoice",
      count = 1, bid = 500, buyout = 500, deposit = 0, consignment = 25,
      moneyDelay = 500, etaHour = 1, etaMin = 0 } })
    local twin = mail({ invoice = { invoiceType = "seller_temp_invoice",
      count = 1, bid = 500, buyout = 500, deposit = 0, consignment = 25,
      moneyDelay = 500, etaHour = 1, etaMin = 0 } })

    assert.equal(2, GC.Ledger.ScanInbox(apiFor({ pending, twin }), context, 1000))
    local firstKey, secondKey = GC.Ledger.GetEntries()[1].key, GC.Ledger.GetEntries()[2].key
    assert.is_true(GC.Ledger.GetEntries()[1].pending)
    assert.is_true(GC.Ledger.GetEntries()[2].pending)

    local paid = mail({ daysLeft = 30 - (3600 / 86400), invoice = {
      count = 1, bid = 500, buyout = 500, deposit = 0, consignment = 25 } })
    local stillPending = mail({ daysLeft = 30 - (3600 / 86400), invoice = {
      invoiceType = "seller_temp_invoice", count = 1, bid = 500, buyout = 500,
      deposit = 0, consignment = 25, moneyDelay = 500, etaHour = 1, etaMin = 0 } })
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ paid, stillPending }), context, 4600))
    assert.equal(firstKey, GC.Ledger.GetEntries()[1].key)
    assert.equal(secondKey, GC.Ledger.GetEntries()[2].key)
    assert.is_false(GC.Ledger.GetEntries()[1].pending)
    assert.is_true(GC.Ledger.GetEntries()[2].pending)
  end)

  it("[WAVE2 C1] retires a buyer occurrence only after a complete absent inbox snapshot", function()
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })

    assert.equal(1, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000))
    local firstKey = GC.Ledger.GetEntries()[1].key
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({}), context, 1010))

    assert.equal(1, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1020))
    assert.equal(2, #GC.Ledger.GetEntries())
    assert.equal(2, #GC.Acquisitions.GetAll())
    assert.not_equal(firstKey, GC.Ledger.GetEntries()[2].key)
  end)

  it("[WAVE2 C1] never retires a buyer occurrence after an incomplete or malformed inbox snapshot", function()
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })

    assert.equal(1, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000))
    local incomplete = apiFor({ bought })
    incomplete.GetInboxNumItems = function() error("inbox unavailable") end
    assert.equal(0, GC.Ledger.ScanInbox(incomplete, context, 1010))
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1020))

    local malformed = apiFor({ bought })
    malformed.GetInboxInvoiceInfo = function() error("invoice unreadable") end
    assert.equal(0, GC.Ledger.ScanInbox(malformed, context, 1030))
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1040))
    assert.equal(1, #GC.Ledger.GetEntries())
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[WAVE3 C1] retains a readable buyer occurrence across an AH-like nil invoice row", function()
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })
    local unreadable = mail()
    unreadable.invoice = nil

    assert.equal(1, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000))
    local key = GC.Ledger.GetEntries()[1].key
    local generation = db.mailOccurrenceGeneration
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ unreadable }), context, 1010))
    assert.equal(generation, db.mailOccurrenceGeneration)
    assert.is_true(db.mailOccurrences[1].present)

    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1020))
    assert.equal(key, GC.Ledger.GetEntries()[1].key)
    assert.equal(1, #GC.Ledger.GetEntries())
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[WAVE3 C1] fails closed for AH-like empty and unknown invoice types", function()
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })
    assert.equal(1, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000))
    local key = GC.Ledger.GetEntries()[1].key
    local generation = db.mailOccurrenceGeneration

    for _, invoiceType in ipairs({ "", "not-an-auction-invoice" }) do
      local unreadable = mail({ invoice = { invoiceType = invoiceType } })
      assert.equal(0, GC.Ledger.ScanInbox(apiFor({ unreadable }), context, 1010))
      assert.equal(generation, db.mailOccurrenceGeneration)
      assert.is_true(db.mailOccurrences[1].present)
    end

    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1020))
    assert.equal(key, GC.Ledger.GetEntries()[1].key)
    assert.equal(1, #GC.Ledger.GetEntries())
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[WAVE3 C1] ignores positively ordinary non-AH mail while retiring absence", function()
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })
    local ordinary = mail({ sender = "Guildmate", subject = "Hello", canReply = true })
    ordinary.invoice.invoiceType = nil

    assert.equal(1, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000))
    local firstKey = GC.Ledger.GetEntries()[1].key
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ ordinary }), context, 1010))
    assert.is_false(db.mailOccurrences[1].present)

    assert.equal(1, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1020))
    assert.equal(2, #GC.Ledger.GetEntries())
    assert.equal(2, #GC.Acquisitions.GetAll())
    assert.not_equal(firstKey, GC.Ledger.GetEntries()[2].key)
  end)

  it("[WAVE3 C1 fix1] fails closed for unknown localized headers without canReply", function()
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })
    assert.equal(1, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000))
    local key = GC.Ledger.GetEntries()[1].key
    local generation = db.mailOccurrenceGeneration

    local function assertUnreadable(canReply)
      local unreadable = mail({ sender = "Дом аукциона", subject = "Успешный аукцион",
        canReply = canReply, invoice = { invoiceType = "unknown-invoice" } })
      assert.equal(0, GC.Ledger.ScanInbox(apiFor({ unreadable }), context, 1010))
      assert.equal(generation, db.mailOccurrenceGeneration)
      assert.is_true(db.mailOccurrences[1].present)
      assert.equal(1, #GC.Ledger.GetEntries())
      assert.equal(1, #GC.Acquisitions.GetAll())
    end
    assertUnreadable(false)
    assertUnreadable(nil)

    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1020))
    assert.equal(key, GC.Ledger.GetEntries()[1].key)
    assert.equal(1, #GC.Ledger.GetEntries())
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[WAVE2 C1] keeps paid seller twins monotonic when a later snapshot reverses their order", function()
    local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 210930,
      positionKey = "commodity:210930", itemName = "Ironclaw Ore", quantity = 2, total = 200,
      acquiredAt = 900, evidenceKey = "buy:wave2-sellers", character = context.char, region = context.region })
    GC.Acquisitions.RecordPost("commodity:210930", 210930, "Ironclaw Ore",
      context.char, context.region, 2, 950)

    local pending = mail({ invoice = { invoiceType = "seller_temp_invoice",
      count = 1, bid = 500, buyout = 500, deposit = 0, consignment = 25,
      moneyDelay = 500, etaHour = 1, etaMin = 0 } })
    local twin = mail({ invoice = { invoiceType = "seller_temp_invoice",
      count = 1, bid = 500, buyout = 500, deposit = 0, consignment = 25,
      moneyDelay = 500, etaHour = 1, etaMin = 0 } })
    assert.equal(2, GC.Ledger.ScanInbox(apiFor({ pending, twin }), context, 1000))

    local paid = mail({ daysLeft = 30 - (3600 / 86400), invoice = {
      count = 1, bid = 500, buyout = 500, deposit = 0, consignment = 25 } })
    local stillPending = mail({ daysLeft = 30 - (3600 / 86400), invoice = {
      invoiceType = "seller_temp_invoice", count = 1, bid = 500, buyout = 500,
      deposit = 0, consignment = 25, moneyDelay = 500, etaHour = 1, etaMin = 0 } })
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ paid, stillPending }), context, 4600))
    local paidKey
    for _, entry in ipairs(GC.Ledger.GetEntries()) do if entry.pending == false then paidKey = entry.key end end
    assert.is_truthy(paidKey)
    assert.equal(1, batch.remainingQty)
    assert.equal(1, #GC.Acquisitions.GetRealized(context))

    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ stillPending, paid }), context, 4610))
    local paidRow
    for _, entry in ipairs(GC.Ledger.GetEntries()) do if entry.key == paidKey then paidRow = entry end end
    assert.is_false(paidRow.pending)
    assert.equal(1, batch.remainingQty)
    assert.equal(1, #GC.Acquisitions.GetRealized(context))
  end)

  it("[WAVE2 C1] keeps a repeated complete multiset snapshot idempotent", function()
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })
    local twin = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })

    assert.equal(2, GC.Ledger.ScanInbox(apiFor({ bought, twin }), context, 1000))
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ twin, bought }), context, 1010))
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ bought, twin }), context, 1020))
    assert.equal(2, #GC.Ledger.GetEntries())
    assert.equal(2, #GC.Acquisitions.GetAll())
  end)

  it("[WAVE2 C1 regression] fails closed without mutating a malformed persisted occurrence", function()
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })
    assert.equal(1, GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000))
    db.mailOccurrences[#db.mailOccurrences + 1] = { key = "corrupt", identity = "corrupt",
      char = context.char, region = context.region }

    local result
    assert.has_no.errors(function() result = GC.Ledger.ScanInbox(apiFor({ bought }), context, 1010) end)
    assert.equal(0, result)
    assert.equal(1, #GC.Ledger.GetEntries())
    assert.is_nil(db.mailOccurrences[2].present)
  end)

  it("fails closed on malformed expiry and an unsafe occurrence sequence", function()
    local broken = mail()
    broken.daysLeft = 0 / 0
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ broken }), context, 1000))
    assert.equal(0, #GC.Ledger.GetEntries())

    db.mailOccurrenceSeq = 9007199254740991
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ mail() }), context, 1000))
    assert.equal(0, #GC.Ledger.GetEntries())
    assert.equal(0, #db.mailOccurrences)
  end)

  it("does not persist an invoice until its character and region scope are known", function()
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ mail() }), { char = context.char }, 1000))
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ mail() }), { region = context.region }, 1000))
    assert.equal(0, #GC.Ledger.GetEntries())
    assert.equal(0, #db.mailOccurrences)
  end)

  it("refuses to mutate a repeated key owned by another scope or invoice class", function()
    local original = { key = "shared", kind = "buy", source = "mail", qty = 1,
      total = 100, at = 1, char = context.char, region = context.region }
    assert.is_true(select(2, GC.Ledger.Append(original)))

    local stored, isNew, reason = GC.Ledger.Append({ key = "shared", kind = "sale",
      source = "mail", qty = 1, total = 200, at = 2, char = "Other-Realm", region = "us" })
    assert.equal(original, stored)
    assert.is_false(isNew)
    assert.equal("incompatible_key", reason)
    assert.equal("buy", stored.kind)
    assert.equal(100, stored.total)
    assert.equal(context.char, stored.char)
  end)

  it("promotes pending buyer evidence once and keeps repeat mail idempotent", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 210930, quantity = 20,
      completedAt = 999, character = context.char, region = context.region,
      reason = "exact total unavailable" })
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })

    GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000)
    GC.Ledger.ScanInbox(apiFor({ bought }), context, 1010)

    assert.equal(1, #GC.Ledger.GetEntries())
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
    assert.equal(pending.id, GC.Acquisitions.GetAll()[1].promotedPendingID)
    assert.equal(GC.Ledger.GetEntries()[1].key, GC.Acquisitions.GetAll()[1].mailEvidenceKey)
  end)

  it("promotes an unknown pending quantity only through exact buyer mail", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 210930,
      completedAt = 999, character = context.char, region = context.region,
      reason = "quantity unavailable" })
    local bought = mail({ invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
      item = { name = "Ironclaw Ore", itemID = 210930 } })

    GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000)
    GC.Ledger.ScanInbox(apiFor({ bought }), context, 1010)

    assert.equal(1, #GC.Ledger.GetEntries())
    assert.equal(GC.Ledger.GetEntries()[1].key, GC.Acquisitions.GetAll()[1].mailEvidenceKey)
    assert.equal(pending.id, GC.Acquisitions.GetAll()[1].promotedPendingID)
    assert.equal(20, GC.Acquisitions.GetAll()[1].originalQty)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)

  it("skips mail that carries no invoice at all", function()
    local plain = mail()
    plain.invoice = nil
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ plain }), context, 1000))
    assert.equal(0, #GC.Ledger.GetEntries())
  end)

  it("skips an invoice with no item name rather than storing a nameless row", function()
    local broken = mail()
    broken.invoice.itemName = nil
    assert.equal(0, GC.Ledger.ScanInbox(apiFor({ broken }), context, 1000))
  end)

  it("survives an API that throws, so mail collection is never blocked", function()
    local api = apiFor({ mail() })
    api.GetInboxInvoiceInfo = function() error("boom") end
    assert.has_no.errors(function() GC.Ledger.ScanInbox(api, context, 1000) end)
    assert.equal(0, #GC.Ledger.GetEntries())
  end)

  it("survives an inbox count that isn't a number", function()
    local api = apiFor({ mail() })
    api.GetInboxNumItems = function() return nil end
    assert.equal(0, GC.Ledger.ScanInbox(api, context, 1000))
  end)

  it("scans every mail in the inbox, not just the first", function()
    local mails = {
      mail({ invoice = { itemName = "A" } }),
      mail({ invoice = { itemName = "B" } }),
    }
    assert.equal(2, GC.Ledger.ScanInbox(apiFor(mails), context, 1000))
  end)

  -- F2: personal sale rate wiring -- ScanInbox credits GC.Data.RecordSaleEvent once per
  -- genuinely NEW sale entry, never on the pending->paid UPDATE of the same invoice (Append's
  -- repeat-key branch). GC.Data is a plain stub here (this spec loads only Core/Ledger.lua),
  -- exercising the exact defensive `GC.Data and GC.Data.RecordSaleEvent` guard ScanInbox uses.
  describe("RecordSaleEvent wiring (F2)", function()
    it("calls GC.Data.RecordSaleEvent once for a newly-recorded sale", function()
      local calls = {}
      GC.Data = { RecordSaleEvent = function(name) calls[#calls + 1] = name end }
      GC.Ledger.ScanInbox(apiFor({ mail() }), context, 1000)
      assert.same({ "Ironclaw Ore" }, calls)
    end)

    it("does NOT call it again when a pending sale later matures (same invoice, isNew=false)", function()
      local calls = {}
      GC.Data = { RecordSaleEvent = function(name) calls[#calls + 1] = name end }
      local pending = mail({ invoice = {
        invoiceType = "seller_temp_invoice", moneyDelay = 500000, etaHour = 1, etaMin = 0,
      } })
      GC.Ledger.ScanInbox(apiFor({ pending }), context, 1000)
      assert.equal(1, #calls)

      local paid = mail({ daysLeft = 30 - (3600 / 86400) })
      GC.Ledger.ScanInbox(apiFor({ paid }), context, 1000 + 3600)
      assert.equal(1, #calls) -- still just the one call from the pending sighting
    end)

    it("does not call it for a buy entry", function()
      local calls = {}
      GC.Data = { RecordSaleEvent = function(name) calls[#calls + 1] = name end }
      local bought = mail({
        invoice = { invoiceType = "buyer", consignment = 0, deposit = 0 },
        item = { name = "Ironclaw Ore", itemID = 210930 },
      })
      GC.Ledger.ScanInbox(apiFor({ bought }), context, 1000)
      assert.equal(0, #calls)
    end)

    it("tolerates GC.Data being absent entirely, the same defensive way Context guards it", function()
      GC.Data = nil
      assert.has_no.errors(function()
        GC.Ledger.ScanInbox(apiFor({ mail() }), context, 1000)
      end)
    end)

    it("tolerates GC.Data existing without a RecordSaleEvent function", function()
      GC.Data = {}
      assert.has_no.errors(function()
        GC.Ledger.ScanInbox(apiFor({ mail() }), context, 1000)
      end)
    end)
  end)
end)
