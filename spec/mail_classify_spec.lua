local helper = require("spec.spec_helper")
local Mailbox = require("spec.support.mail_inbox")

describe("MailClassify, reading an inbox row and deciding take or skip", function()
  local GC, patterns
  local ALL = { sales = true, returns = true, purchases = true, players = true }
  -- The ledger's context (Core/Ledger.lua, Context): the character and region a sale is recorded under.
  local CONTEXT = { char = "A-B", region = "eu" }

  local function with(overrides)
    local on = {}
    for k, v in pairs(ALL) do on[k] = v end
    for k, v in pairs(overrides or {}) do on[k] = v end
    return on
  end

  local function classify(row, enabled, loaded, context)
    local box = Mailbox.new({ row })
    local mail = GC.MailClassify.Read(box.api, 1, loaded or patterns, context or CONTEXT)
    return GC.MailClassify.Decide(mail, enabled or ALL), mail
  end

  local SALE = { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 50000,
    auction = true, invoice = { invoiceType = "seller", itemName = "Linen Cloth" } }
  local PENDING = { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 0,
    auction = true, invoice = { invoiceType = "seller_temp_invoice", itemName = "Linen Cloth" } }
  local EXPIRED = { sender = "Auction House", subject = "Auction expired: Linen Cloth", auction = true,
    items = { [1] = { itemID = 2589, count = 20 } } }
  local REMOVED = { sender = "Auction House", subject = "Auction canceled: Linen Cloth", auction = true,
    items = { [1] = { itemID = 2589, count = 20 } } }
  local OUTBID = { sender = "Auction House", subject = "Outbid on Linen Cloth", money = 9000, auction = true }
  local WON = { sender = "Auction House", subject = "Auction won: Linen Cloth", auction = true,
    invoice = { invoiceType = "buyer", itemName = "Linen Cloth" }, items = { [1] = { itemID = 2589, count = 20 } } }
  local PLAYER = { sender = "Friend", subject = "For you", money = 1000, canReply = true }
  local PLAYER_EMPTY = { sender = "Friend", subject = "Hi", canReply = true }
  local COD = { sender = "Friend", subject = "Pay me", canReply = true, cod = 1000,
    items = { [1] = { itemID = 1, count = 1 } } }
  local GM = { sender = "GM", subject = "Ticket", isGM = true, money = 5 }
  local LOADING = { sender = "Auction House", subject = "Retrieving data...", money = 0 }
  local REWARD = { sender = "Quest Giver", subject = "Reward", items = { [1] = { itemID = 5, count = 1 } } }

  before_each(function()
    _G.RETRIEVING_DATA = "Retrieving data..."
    _G.AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
    _G.AUCTION_REMOVED_MAIL_SUBJECT = "Auction canceled: %s"
    _G.AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
    GC = helper.loadModule("Core/Ledger.lua")
    GC.Ledger.Init({})
    helper.loadModule("Core/MailClassify.lua", GC)
    patterns = GC.MailClassify.Patterns({ expired = _G.AUCTION_EXPIRED_MAIL_SUBJECT,
      removed = _G.AUCTION_REMOVED_MAIL_SUBJECT, outbid = _G.AUCTION_OUTBID_MAIL_SUBJECT })
  end)

  after_each(function()
    _G.RETRIEVING_DATA, _G.AUCTION_EXPIRED_MAIL_SUBJECT = nil, nil
    _G.AUCTION_REMOVED_MAIL_SUBJECT, _G.AUCTION_OUTBID_MAIL_SUBJECT = nil, nil
  end)

  describe("Decide", function()
    for _, case in ipairs({
      { "a sale", SALE, { take = true, kind = "sale", group = "sales" } },
      { "an expired lot", EXPIRED, { take = true, kind = "expired", group = "returns" } },
      { "a cancelled lot", REMOVED, { take = true, kind = "cancelled", group = "returns" } },
      { "an outbid refund", OUTBID, { take = true, kind = "outbid", group = "purchases" } },
      { "a won auction", WON, { take = true, kind = "purchase", group = "purchases" } },
      { "player mail with gold", PLAYER, { take = true, kind = "player", group = "players" } },
      { "a sale still pending", PENDING, { skip = "pending" } },
      { "player mail with nothing", PLAYER_EMPTY, { skip = "empty" } },
      { "cash on delivery mail", COD, { skip = "cod" } },
      { "GM mail", GM, { skip = "gm" } },
      { "a sale mail still loading", LOADING, { skip = "loading" } },
      { "a quest reward style system mail", REWARD, { skip = "system" } },
    }) do
      it("reads " .. case[1], function()
        assert.same(case[3], (classify(case[2])))
      end)
    end

    it("skips an item mail whose attachments have not loaded yet", function()
      local box = Mailbox.new({ { sender = "Auction House", subject = "Auction expired: X", auction = true,
        items = { [1] = { itemID = 7, count = 1 } } } })
      local real = box.api.GetInboxItem
      box.api.GetInboxItem = function() end
      local mail = GC.MailClassify.Read(box.api, 1, patterns)
      assert.same({ skip = "loading" }, GC.MailClassify.Decide(mail, ALL))
      box.api.GetInboxItem = real
    end)

    -- Ledger first: once a sale's gold or a won auction's items are taken, the invoice is gone, so
    -- they wait until the ledger's own rule (Core/Ledger.lua, ReadsInvoice) says it can record them.
    it("leaves a sale whose invoice the ledger cannot read yet as still loading", function()
      local unnamed = { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 50000,
        auction = true, invoice = { invoiceType = "seller", itemName = nil } }
      assert.same({ skip = "loading" }, (classify(unnamed)))
    end)

    it("leaves a won auction whose invoice the ledger cannot read yet as still loading", function()
      local uncounted = { sender = "Auction House", subject = "Auction won: Linen Cloth", auction = true,
        invoice = { invoiceType = "buyer", itemName = "Linen Cloth", count = 0 },
        items = { [1] = { itemID = 2589, count = 20 } } }
      assert.same({ skip = "loading" }, (classify(uncounted)))
    end)

    it("leaves sales and won auctions while the ledger has no region to record them under", function()
      local noRegion = { char = "A-B" }
      assert.same({ skip = "loading" }, (classify(SALE, ALL, nil, noRegion)))
      assert.same({ skip = "loading" }, (classify(WON, ALL, nil, noRegion)))
      assert.same({ take = true, kind = "expired", group = "returns" }, (classify(EXPIRED, ALL, nil, noRegion)))
      assert.same({ take = true, kind = "player", group = "players" }, (classify(PLAYER, ALL, nil, noRegion)))
    end)

    it("skips a cash on delivery mail first, even with items and a reply button", function()
      local decision = classify(COD)
      assert.equal("cod", decision.skip)
    end)

    it("does not take an auction looking subject from a player", function()
      local decision = classify({ sender = "Friend", subject = "Auction expired: Gift", canReply = true,
        items = { [1] = { itemID = 9, count = 1 } } })
      assert.same({ take = true, kind = "player", group = "players" }, decision)
    end)

    for _, case in ipairs({
      { "sales", SALE }, { "returns", EXPIRED }, { "purchases", WON }, { "players", PLAYER },
    }) do
      it("skips " .. case[1] .. " when that group is switched off", function()
        assert.same({ skip = "off" }, (classify(case[2], with({ [case[1]] = false }))))
      end)
    end

    it("treats an outbid refund as a purchase for the switch", function()
      assert.same({ skip = "off" }, (classify(OUTBID, with({ purchases = false }))))
    end)
  end)

  describe("Read", function()
    it("returns nil when the header call raises", function()
      local box = Mailbox.new({ SALE })
      box.api.GetInboxHeaderInfo = function() error("not loaded") end
      assert.is_nil(GC.MailClassify.Read(box.api, 1, patterns))
    end)

    it("returns nil for an index with no row", function()
      assert.is_nil(GC.MailClassify.Read(Mailbox.new({}).api, 1, patterns))
    end)

    it("fills the record from the header and the invoice", function()
      local _, mail = classify(SALE)
      assert.equal(1, mail.index)
      assert.equal("Auction House", mail.sender)
      assert.equal(50000, mail.money)
      assert.equal(0, mail.cod)
      assert.equal("seller", mail.invoiceType)
      assert.is_false(mail.canReply)
      assert.is_false(mail.isGM)
    end)

    it("reads attachments for slots 1 and 16 only", function()
      local _, mail = classify({ sender = "Friend", canReply = true,
        items = { [1] = { itemID = 11, count = 3 }, [16] = { itemID = 16, count = 1 } } })
      assert.same({ { slot = 1, itemID = 11, count = 3 }, { slot = 16, itemID = 16, count = 1 } }, mail.items)
    end)

    it("tells two otherwise equal mails apart by days left", function()
      local a = select(2, classify({ sender = "A", subject = "S", money = 1, daysLeft = 20, canReply = true }))
      local b = select(2, classify({ sender = "A", subject = "S", money = 1, daysLeft = 21, canReply = true }))
      assert.is_not.equal(a.key, b.key)
    end)

    it("matches the expired subject of another language", function()
      local german = GC.MailClassify.Patterns({ expired = "Auktion abgelaufen: %s" })
      local decision = classify({ sender = "Auktionshaus", subject = "Auktion abgelaufen: Leinenstoff",
        auction = true, items = { [1] = { itemID = 2589, count = 20 } } }, ALL, german)
      assert.same({ take = true, kind = "expired", group = "returns" }, decision)
    end)
  end)

  describe("Patterns", function()
    it("leaves a missing subject with an empty list", function()
      local p = GC.MailClassify.Patterns({ expired = "Auction expired: %s" })
      assert.equal(1, #p.expired)
      assert.same({}, p.removed)
      assert.same({}, p.outbid)
    end)
  end)

  describe("Count", function()
    it("counts the takeable and the loading mails of a ten row mailbox", function()
      local box = Mailbox.new(Mailbox.tenMail())
      local takeable, loading = GC.MailClassify.Count(box.api, patterns, ALL, CONTEXT)
      assert.equal(4, takeable)
      assert.equal(1, loading)
    end)

    it("counts a sale the ledger cannot read yet as loading, not takeable", function()
      local box = Mailbox.new({ SALE, { sender = "Auction House", subject = "Auction successful: X", money = 9,
        auction = true, invoice = { invoiceType = "seller", itemName = nil } } })
      local takeable, loading = GC.MailClassify.Count(box.api, patterns, ALL, CONTEXT)
      assert.equal(1, takeable)
      assert.equal(1, loading)
    end)

    it("leaves a switched off group out of the count", function()
      local box = Mailbox.new(Mailbox.tenMail())
      local takeable, loading = GC.MailClassify.Count(box.api, patterns, with({ returns = false }), CONTEXT)
      assert.equal(3, takeable)
      assert.equal(1, loading)
    end)

    it("counts a row that cannot be read yet as loading", function()
      local box = Mailbox.new({ SALE, PLAYER })
      local real = box.api.GetInboxHeaderInfo
      box.api.GetInboxHeaderInfo = function(i) if i == 2 then error("no") end return real(i) end
      local takeable, loading = GC.MailClassify.Count(box.api, patterns, ALL, CONTEXT)
      assert.equal(1, takeable)
      assert.equal(1, loading)
    end)
  end)
end)
