local helper = require("spec.spec_helper")

describe("Ledger inbox scan", function()
  local GC, db, context

  -- One inbox entry: the header fields the scanner reads, plus its invoice.
  local function mail(overrides)
    local m = {
      sender = "Auction House",
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
        -- Mirrors the live return order for the fields we read:
        -- packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft
        return nil, nil, m.sender, "Auction successful", 0, 0, m.daysLeft
      end,
      GetInboxInvoiceInfo = function(i)
        local inv = mails[i] and mails[i].invoice
        if not inv then return nil end
        return inv.invoiceType, inv.itemName, inv.playerName, inv.bid, inv.buyout,
          inv.deposit, inv.consignment, inv.moneyDelay, inv.etaHour, inv.etaMin,
          inv.count, inv.commerceAuction
      end,
      GetInboxItem = function(i)
        local it = mails[i] and mails[i].item
        if not it then return nil end
        return it.name, it.itemID
      end,
    }
  end

  before_each(function()
    GC = helper.loadModule("Core/Ledger.lua")
    db = {}
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
end)
