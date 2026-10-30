local helper = require("spec.spec_helper")
local Mailbox = require("spec.support.mail_inbox")

describe("MailClassify, reading an inbox row", function()
  local GC

  before_each(function()
    _G.RETRIEVING_DATA = "Retrieving data..."
    GC = helper.loadModule("Core/MailClassify.lua")
  end)

  after_each(function()
    _G.RETRIEVING_DATA = nil
  end)

  local SALE = { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 50000,
    auction = true, invoice = { invoiceType = "seller", itemName = "Linen Cloth" } }

  local function read(row)
    return GC.MailClassify.Read(Mailbox.new({ row }).api, 1)
  end

  describe("Read", function()
    it("returns nil when the header call raises", function()
      local box = Mailbox.new({ SALE })
      box.api.GetInboxHeaderInfo = function() error("not loaded") end
      assert.is_nil(GC.MailClassify.Read(box.api, 1))
    end)

    it("returns nil when the invoice call raises", function()
      local box = Mailbox.new({ SALE })
      box.api.GetInboxInvoiceInfo = function() error("not loaded") end
      assert.is_nil(GC.MailClassify.Read(box.api, 1))
    end)

    it("returns nil for an index with no row", function()
      assert.is_nil(GC.MailClassify.Read(Mailbox.new({}).api, 1))
    end)

    it("fills the record from the header and the invoice", function()
      local mail = read(SALE)
      assert.equal(1, mail.index)
      assert.equal("Auction House", mail.sender)
      assert.equal("Auction successful: Linen Cloth", mail.subject)
      assert.equal(50000, mail.money)
      assert.equal(0, mail.cod)
      assert.equal(29, mail.daysLeft)
      assert.equal(0, mail.itemCount)
      assert.equal("seller", mail.invoiceType)
    end)

    it("reads attachments for slots 1 and 16 only", function()
      local mail = read({ sender = "Friend", canReply = true,
        items = { [1] = { itemID = 11, count = 3 }, [16] = { itemID = 16, count = 1 } } })
      assert.equal(2, mail.itemCount)
      assert.same({ { slot = 1, itemID = 11, count = 3 }, { slot = 16, itemID = 16, count = 1 } }, mail.items)
    end)

    it("leaves out an attachment the client has not named yet", function()
      local box = Mailbox.new({ { sender = "Friend", items = { [1] = { itemID = 7, count = 1 } } } })
      box.api.GetInboxItem = function() end
      local mail = GC.MailClassify.Read(box.api, 1)
      assert.equal(1, mail.itemCount)
      assert.same({}, mail.items)
    end)

    it("reads the cash on delivery amount", function()
      assert.equal(1000, read({ sender = "Friend", cod = 1000, items = { [1] = { itemID = 1, count = 1 } } }).cod)
    end)
  end)

  describe("IsRetrieving", function()
    it("is true for the client's placeholder subject, with or without its ellipsis", function()
      assert.is_true(GC.MailClassify.IsRetrieving("Retrieving data..."))
      assert.is_true(GC.MailClassify.IsRetrieving("Retrieving data\226\128\166"))
      assert.is_true(GC.MailClassify.IsRetrieving("Retrieving data"))
    end)

    it("is false for any other subject, an empty one or none", function()
      assert.is_false(GC.MailClassify.IsRetrieving("Auction expired: Linen Cloth"))
      assert.is_false(GC.MailClassify.IsRetrieving(""))
      assert.is_false(GC.MailClassify.IsRetrieving(nil))
    end)

    it("is false while the client has no placeholder text", function()
      _G.RETRIEVING_DATA = nil
      assert.is_false(GC.MailClassify.IsRetrieving("Retrieving data..."))
    end)
  end)
end)
