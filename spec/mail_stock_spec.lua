local helper = require("spec.spec_helper")
local Mailbox = require("spec.support.mail_inbox")

-- Core/MailStock.lua: what waits in a character's mailbox, which the BUY tab and the craft queue
-- count as held beside the bags and the banks. The ledger's inbox scan reads it whenever the
-- mailbox shows (Core/Ledger.lua, ScanInbox), and an auction house purchase is counted from the
-- moment it is made, since retail delivers every one by mail.
describe("MailStock", function()
  local GC, box, now
  local CONTEXT = { char = "A-B", region = "eu" }

  local function won(itemID, count)
    return { sender = "Auction House", subject = "Auction won: Item A", auction = true,
      invoice = { invoiceType = "buyer", itemName = "Item A", count = count, bid = 100 * count },
      items = { [1] = { itemID = itemID, count = count } } }
  end

  local function returned(itemID, count)
    return { sender = "Auction House", subject = "Auction expired: Item A", auction = true,
      items = { [1] = { itemID = itemID, count = count } } }
  end

  local function player(itemID, count, cod)
    return { sender = "Friend", subject = "For you", canReply = true, cod = cod,
      items = { [1] = { itemID = itemID, count = count } } }
  end

  -- One pass of the ledger's scan, as Core/Init.lua runs it on MAIL_SHOW (`opening`) and on every
  -- MAIL_INBOX_UPDATE after it. `api` stands in for the mailbox when a spec needs another answer.
  local function scan(opening, api, context)
    return GC.Ledger.ScanInbox(api or box.api, context or CONTEXT, now, opening)
  end

  local function count(itemID, char) return GC.MailStock.Count(char or "A-B", itemID) end

  local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
  end

  before_each(function()
    now = 1000
    GC = helper.loadModule("Core/Ledger.lua")
    GC.db = {}
    GC.Ledger.Init(GC.db)
    helper.loadModule("Core/MailClassify.lua", GC)
    helper.loadModule("Core/MailStock.lua", GC)
  end)

  after_each(function() _G.RETRIEVING_DATA = nil end)

  it("counts nothing, and writes nothing, before anything is bought or read", function()
    assert.equal(0, count(101))
    assert.is_nil(GC.db.mailStock)
  end)

  it("counts a purchase from the moment it is made, after a relog too, for its own character", function()
    assert.is_true(GC.MailStock.Bought("A-B", 101, 6))
    assert.is_true(GC.MailStock.Bought("A-B", 101, 2))
    assert.equal(8, count(101))
    -- A relog: a fresh load of the file over the SavedVariables the client wrote.
    local after = helper.loadModule("Core/MailStock.lua")
    after.db = GC.db
    assert.equal(8, after.MailStock.Count("A-B", 101))
    assert.equal(0, after.MailStock.Count("C-D", 101))
    assert.is_false(GC.MailStock.Bought("A-B", 101, 0))
    assert.is_false(GC.MailStock.Bought(nil, 101, 1))
    assert.equal(8, count(101))
  end)

  it("counts every attachment the mailbox shows, whoever sent it, but not cash on delivery", function()
    box = Mailbox.new({ won(101, 6), returned(101, 2), player(101, 3), player(101, 5, 100), player(102, 4) })
    scan(true)
    assert.equal(11, count(101))
    assert.equal(4, count(102))
  end)

  it("counts a purchase once when the mailbox shows its mail", function()
    GC.MailStock.Bought("A-B", 101, 6)
    box = Mailbox.new({ won(101, 6) })
    scan(true)
    assert.equal(6, count(101))
    scan(false)
    assert.equal(6, count(101))
  end)

  it("stops counting a mail once a read sees it taken", function()
    GC.MailStock.Bought("A-B", 101, 6)
    box = Mailbox.new({ won(101, 6), player(102, 4) })
    scan(true)
    box.api.TakeInboxItem(1, 1)
    box:advance()
    scan(false)
    assert.equal(0, count(101))
    assert.equal(4, count(102))
    -- The inbox emptied: a read of no rows, after rows were seen this visit, is an empty mailbox.
    box.api.TakeInboxItem(1, 1)
    box:advance()
    box:removeRow(1)
    scan(false)
    assert.equal(0, count(102))
  end)

  it("changes nothing on the empty pass before the first row arrives", function()
    GC.MailStock.Bought("A-B", 101, 6)
    box = Mailbox.new({})
    scan(true)
    assert.equal(6, count(101))
  end)

  it("changes nothing while a row is not loaded: an attachment unnamed, or the subject still loading", function()
    GC.MailStock.Bought("A-B", 105, 2)
    box = Mailbox.new({ won(101, 6), player(102, 4) })
    local api = {}
    for name, fn in pairs(box.api) do api[name] = fn end
    api.GetInboxItem = function(index, slot)
      if index == 2 then return nil end
      return box.api.GetInboxItem(index, slot)
    end
    scan(true, api)
    assert.equal(2, count(105))
    assert.equal(0, count(101))
    assert.equal(0, count(102))

    _G.RETRIEVING_DATA = "Retrieving data..."
    box = Mailbox.new({ won(101, 6), { sender = "Auction House", subject = "Retrieving data...", auction = true } })
    scan(true)
    assert.equal(2, count(105))
    assert.equal(0, count(101))
    -- Loaded, the same inbox reads: the purchase it does not hold was taken, or never came.
    box = Mailbox.new({ won(101, 6), player(102, 4) })
    scan(true)
    assert.equal(0, count(105))
    assert.equal(6, count(101))
    assert.equal(4, count(102))
  end)

  -- The inbox shows 100 mails at most; the rest are out of view until the player takes some.
  it("with mail out of view, clears a purchase whose won auction it read and keeps one it did not", function()
    GC.MailStock.Bought("A-B", 101, 6)
    GC.MailStock.Bought("A-B", 102, 3)
    box = Mailbox.new({ won(101, 6), player(103, 1) }, { hidden = { won(102, 3) } })
    scan(true)
    assert.equal(6, count(101))
    assert.equal(3, count(102))
    assert.equal(1, count(103))
  end)

  it("keeps each character's mailbox apart", function()
    GC.MailStock.Bought("C-D", 101, 5)
    box = Mailbox.new({ won(101, 6) })
    scan(true)
    assert.equal(6, count(101))
    assert.equal(5, count(101, "C-D"))
  end)

  it("leaves a store a newer GoldCap wrote as it is, and counts nothing from it", function()
    GC.db.mailStock = { v = 2, chars = { ["A-B"] = { items = { [101] = 5 }, bought = { [101] = 1 } } } }
    local saved = copy(GC.db.mailStock)
    assert.equal(0, count(101))
    assert.is_false(GC.MailStock.Bought("A-B", 101, 6))
    box = Mailbox.new({ won(101, 6) })
    scan(true)
    assert.same(saved, GC.db.mailStock)
  end)

  -- WoW: Forever loads no Core/MailStock.lua: its ledger scan keeps no mailbox.
  it("is never read nor written where the file is not loaded", function()
    GC = helper.loadModule("Core/Ledger.lua")
    GC.db = {}
    GC.Ledger.Init(GC.db)
    box = Mailbox.new({ won(101, 6), player(102, 4) })
    scan(true)
    assert.is_nil(GC.db.mailStock)
    assert.is_nil(GC.MailStock)
  end)
end)
