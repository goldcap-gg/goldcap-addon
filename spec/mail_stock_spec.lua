local helper = require("spec.spec_helper")
local Mailbox = require("spec.support.mail_inbox")

-- Core/MailStock.lua: what waits in a character's mailbox, which the BUY tab and the craft queue
-- count as held beside the bags and the banks. The ledger's inbox scan reads it on every pass of
-- a visit (Core/Ledger.lua, ScanInbox), and an auction house purchase is counted from the moment
-- it is made, since retail delivers every one by mail. A purchase stops counting on its own when
-- a read finds its mail arrived, never only because a read did not list it.
describe("MailStock", function()
  local GC, box, now
  local CONTEXT = { char = "A-B", region = "eu" }
  local DAY = 86400
  -- The client's answer on MAIL_SHOW: no row yet, every visit (the ledger's mail probe).
  local NOT_YET = { GetInboxNumItems = function() return 0, 0 end }

  -- A mail delivered at `at` (time()); its days left are worked out when the mailbox shows it, as
  -- the client does, so the same mail keeps one expiry from visit to visit.
  local function won(itemID, count, at)
    return { sender = "Auction House", subject = "Auction won: Item A", auction = true, at = at or 0,
      invoice = { invoiceType = "buyer", itemName = "Item A", count = count, bid = 100 * count },
      items = { [1] = { itemID = itemID, count = count } } }
  end

  local function returned(itemID, count, at)
    return { sender = "Auction House", subject = "Auction expired: Item A", auction = true, at = at or 0,
      items = { [1] = { itemID = itemID, count = count } } }
  end

  local function player(itemID, count, cod, at)
    return { sender = "Friend", subject = "For you", canReply = true, cod = cod, at = at or 0,
      items = { [1] = { itemID = itemID, count = count } } }
  end

  local function dated(rows)
    local out = {}
    for i, row in ipairs(rows or {}) do
      local copy = {}
      for k, v in pairs(row) do copy[k] = v end
      copy.daysLeft = ((row.at or 0) + 30 * DAY - now) / DAY
      out[i] = copy
    end
    return out
  end

  -- The inbox as the client lists it now: `rows` in view, `hidden` past the hundredth.
  local function inbox(rows, hidden)
    box = Mailbox.new(dated(rows), { hidden = dated(hidden) })
    return box
  end

  -- One pass of the ledger's scan, as Core/Init.lua runs it on MAIL_SHOW (`opening`) and on every
  -- MAIL_INBOX_UPDATE after it. `api` stands in for the mailbox when a spec needs another answer.
  local function scan(opening, api)
    return GC.Ledger.ScanInbox(api or box.api, CONTEXT, now, opening)
  end

  -- MAIL_SHOW's pass (no row yet), then MAIL_INBOX_UPDATE's with the rows.
  local function show(rows, hidden)
    inbox(rows, hidden)
    scan(true, NOT_YET)
    scan(false)
  end

  local function close(seconds)
    now = now + (seconds or 3)
    return GC.MailStock.Closed()
  end

  local function count(itemID, char) return GC.MailStock.Count(char or "A-B", itemID) end

  -- The character's first visit: nothing in it is taken for a delivery.
  local function baseline()
    show({ player(900, 1) })
    close()
  end

  local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
  end

  before_each(function()
    now = 100000
    _G.time = function() return now end
    GC = helper.loadModule("Core/Ledger.lua")
    GC.db = {}
    GC.Ledger.Init(GC.db)
    helper.loadModule("Core/MailClassify.lua", GC)
    helper.loadModule("Core/MailStock.lua", GC)
  end)

  after_each(function()
    _G.RETRIEVING_DATA = nil
    _G.time = os.time
  end)

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
    show({ won(101, 6), returned(101, 2), player(101, 3), player(101, 5, 100), player(102, 4) })
    assert.equal(11, count(101))
    assert.equal(4, count(102))
  end)

  it("counts a purchase once when a read finds its mail arrived, on every pass after", function()
    baseline()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 30
    show({ won(101, 6, now - 30), player(900, 1) })
    assert.equal(6, count(101))
    scan(false)
    scan(false)
    assert.equal(6, count(101))
    close()
    assert.equal(6, count(101))
  end)

  -- I1: Blizzard's MailFrame fetches the inbox at most once per CanCheckInbox window, so a
  -- mailbox opened soon after a purchase can list what the client held before it.
  it("keeps counting a purchase a stale list does not hold, until a later pass lists its mail", function()
    baseline()
    now = now + 20
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 20
    -- Every row loaded and in view, and the won auction not among them.
    inbox({ player(900, 1) })
    scan(true)
    scan(false)
    assert.equal(6, count(101))
    -- The deferred check answers: the mail comes in at the front.
    box:refreshNow(dated({ won(101, 6, now - 20) }))
    scan(false)
    assert.equal(6, count(101))
    close()
    assert.equal(6, count(101))
  end)

  it("keeps counting a purchase when the visit closes on the stale list, and finds its mail next visit", function()
    baseline()
    now = now + 20
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 20
    show({ player(900, 1) })
    close(5)
    assert.equal(6, count(101))
    now = now + 300
    show({ won(101, 6, now - 345), player(900, 1) })
    assert.equal(6, count(101))
  end)

  -- The fallback: a purchase no read ever saw arrive (taken on a visit whose reads missed it, or
  -- never sent) stops counting at a read of the whole inbox well after it was made.
  it("drops a purchase a full read does not hold once it is older than the visit by two minutes", function()
    baseline()
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 119
    show({ player(900, 1) })
    assert.equal(6, count(101))
    close()
    now = now + 60
    show({ player(900, 1) })
    assert.equal(0, count(101))
  end)

  -- I2: with more than 100 mails, a won auction out of view must not let a second pass, or an
  -- older won auction of the same item in view, take a purchase off.
  it("counts two purchases right over two passes of an overflowing inbox", function()
    baseline()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 6)
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 10
    show({ won(101, 6, now - 10), player(900, 1) }, { won(101, 6, now - 10) })
    assert.equal(12, count(101))
    scan(false)
    assert.equal(12, count(101))
    -- The hidden one comes into view: the same twelve.
    box:refreshNow()
    scan(false)
    assert.equal(12, count(101))
    close()
    assert.equal(12, count(101))
  end)

  it("never takes an older won auction of the same item for the purchase's mail", function()
    local old = won(101, 6, now - 2 * DAY)
    show({ old, player(900, 1) })
    close()
    assert.equal(6, count(101))
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 10
    -- The new mail out of view behind a full inbox.
    show({ old, player(900, 1) }, { won(101, 6, now - 10) })
    assert.equal(12, count(101))
    scan(false)
    assert.equal(12, count(101))
    close()
    -- A stale list, every row in view, the new mail not among them.
    show({ old, player(900, 1) })
    assert.equal(12, count(101))
  end)

  it("takes nothing off on a character's first read, and lets the fallback clear it later", function()
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 10
    show({ won(101, 6, now - 10) })
    -- The baseline cannot tell this mail from one that was there before the purchase: high.
    assert.equal(12, count(101))
    close()
    now = now + 300
    show({ won(101, 6, now - 313) })
    assert.equal(6, count(101))
  end)

  it("keeps a purchase whose mail is not listed when the first read holds an older one of the item", function()
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 10
    show({ won(101, 6, now - 3 * DAY) })
    assert.equal(12, count(101))
  end)

  -- A won auction's invoice can come a pass after its row: the row reads as a mail with no invoice.
  it("counts a won auction whose invoice comes a pass late once, and an old one's not at all", function()
    local old = won(102, 2, now - DAY)
    show({ old, player(900, 1) })
    close()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 6)
    GC.MailStock.Bought("A-B", 102, 2)
    now = now + 10
    inbox({ won(101, 6, now - 10), old, player(900, 1) })
    local late = {}
    for name, fn in pairs(box.api) do late[name] = fn end
    late.GetInboxInvoiceInfo = function() return nil end
    scan(true, NOT_YET)
    scan(false, late)
    assert.equal(12, count(101))
    assert.equal(4, count(102))
    scan(false)
    assert.equal(6, count(101))
    -- The old one was in the inbox before the visit: the purchase of 102 is still on its way.
    assert.equal(4, count(102))
    scan(false)
    assert.equal(6, count(101))
  end)

  it("stops counting a mail once a read sees it taken, and an emptied inbox at the close", function()
    baseline()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 6)
    show({ won(101, 6, now), player(102, 4) })
    box.api.TakeInboxItem(1, 1)
    box:advance()
    scan(false)
    assert.equal(0, count(101))
    assert.equal(4, count(102))
    box.api.TakeInboxItem(1, 1)
    box:advance()
    box:removeRow(1)
    scan(false)
    -- The empty answer counts when the visit ends on it.
    assert.equal(4, count(102))
    assert.is_true(close(1))
    assert.equal(0, count(102))
  end)

  -- I3: a take that lands after the visit's last pass. The next visit to an empty inbox reads it.
  it("stops counting the last mail taken with no pass after it, at the next visit to an empty inbox", function()
    baseline()
    now = now + 600
    show({ won(101, 6, now) })
    assert.equal(6, count(101))
    box.api.TakeInboxItem(1, 1)
    close()
    box:advance()
    assert.equal(6, count(101))
    -- Next visit: MAIL_SHOW reads nothing yet, then the client answers an empty inbox.
    now = now + 60
    show({})
    assert.equal(6, count(101))
    assert.is_true(close(3))
    assert.equal(0, count(101))
  end)

  it("reads no empty inbox from a visit too short to have shown its rows, nor from the opening pass", function()
    show({ won(101, 6) })
    close()
    show({})
    assert.is_false(close(1))
    assert.equal(6, count(101))
    inbox({})
    scan(true)
    assert.is_false(close(5))
    assert.equal(6, count(101))
  end)

  it("clears nothing on an empty pass the rows come after", function()
    show({ won(101, 6) })
    close()
    inbox({ won(101, 6) })
    scan(true, NOT_YET)
    scan(false, NOT_YET)
    scan(false)
    assert.is_false(close(5))
    assert.equal(6, count(101))
  end)

  -- Blizzard's deferred CheckInbox can answer after the frame closed.
  it("reads nothing from a pass after the mailbox closed", function()
    GC.MailStock.Bought("A-B", 103, 1)
    show({ won(101, 6), player(102, 4) })
    close()
    inbox({})
    scan(false)
    assert.is_false(close())
    inbox({ player(102, 4) })
    scan(false)
    assert.equal(6, count(101))
    assert.equal(4, count(102))
    assert.equal(1, count(103))
  end)

  it("says the mailbox is open from MAIL_SHOW to MAIL_CLOSED", function()
    assert.is_false(GC.MailStock.IsOpen())
    show({ won(101, 6) })
    assert.is_true(GC.MailStock.IsOpen())
    close()
    assert.is_false(GC.MailStock.IsOpen())
  end)

  it("changes nothing while a row is not loaded: an attachment unnamed, or the subject still loading", function()
    GC.MailStock.Bought("A-B", 105, 2)
    inbox({ won(101, 6), player(102, 4) })
    local api = {}
    for name, fn in pairs(box.api) do api[name] = fn end
    api.GetInboxItem = function(index, slot)
      if index == 2 then return nil end
      return box.api.GetInboxItem(index, slot)
    end
    scan(true, NOT_YET)
    scan(false, api)
    assert.equal(2, count(105))
    assert.equal(0, count(101))
    assert.equal(0, count(102))
    close()

    _G.RETRIEVING_DATA = "Retrieving data..."
    show({ won(101, 6), { sender = "Auction House", subject = "Retrieving data...", auction = true } })
    assert.equal(2, count(105))
    assert.equal(0, count(101))
    close()
  end)

  -- M9: a mail with no subject (an addon's, a system mail) is loaded, and must not hold back every
  -- read while it sits in the inbox.
  it("reads an inbox holding a mail with no subject", function()
    show({ won(101, 6), { sender = "Someone", subject = "", items = { [1] = { itemID = 102, count = 1 } } } })
    assert.equal(6, count(101))
    assert.equal(1, count(102))
  end)

  it("drops a purchase thirty days after it was made, whatever the reads said", function()
    baseline()
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 31 * DAY
    show({ player(900, 1) }, { player(901, 1) })
    assert.equal(0, count(101))
  end)

  it("keeps each character's mailbox apart", function()
    GC.MailStock.Bought("C-D", 101, 5)
    show({ won(101, 6) })
    assert.equal(6, count(101))
    assert.equal(5, count(101, "C-D"))
  end)

  it("leaves a store a newer GoldCap wrote as it is, and counts nothing from it", function()
    GC.db.mailStock = { v = 2, chars = { ["A-B"] = { items = { [101] = 5 }, bought = { [101] = 1 } } } }
    local saved = copy(GC.db.mailStock)
    assert.equal(0, count(101))
    assert.is_false(GC.MailStock.Bought("A-B", 101, 6))
    show({ won(101, 6) })
    show({})
    close()
    assert.same(saved, GC.db.mailStock)
  end)

  -- WoW: Forever loads no Core/MailStock.lua: its ledger scan keeps no mailbox.
  it("is never read nor written where the file is not loaded", function()
    GC = helper.loadModule("Core/Ledger.lua")
    GC.db = {}
    GC.Ledger.Init(GC.db)
    show({ won(101, 6), player(102, 4) })
    assert.is_nil(GC.db.mailStock)
    assert.is_nil(GC.MailStock)
  end)
end)
