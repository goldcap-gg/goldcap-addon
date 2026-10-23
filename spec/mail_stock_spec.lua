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
  -- the client does, so the same mail keeps one expiry from visit to visit (`shift` moves the
  -- expiry one read reports, as a fresh delivery's placeholder does).
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
      copy.daysLeft = ((row.at or 0) + 30 * DAY + (row.shift or 0) - now) / DAY
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

  -- Blizzard's MailFrame asks the server for the inbox only once it shows (MailFrame_Show calls
  -- MailFrame_RefreshInbox), so the pass MAIL_SHOW runs reads the list the client already held.
  it("drops nothing on the opening pass, which lists the inbox from before the visit", function()
    baseline()
    now = now + 30
    GC.MailStock.Bought("A-B", 101, 50)
    now = now + 130
    -- Every row loaded and in view, no won auction: the list of the visit before the purchase.
    inbox({ player(900, 1) })
    scan(true)
    assert.equal(50, count(101))
    -- The fetch answers with the won auction in front: the same fifty, never a hundred.
    box:refreshNow(dated({ won(101, 50, now - 130) }))
    scan(false)
    assert.equal(50, count(101))
    close()
    assert.equal(50, count(101))
  end)

  it("keeps counting a purchase when the visit closes before the fetch answers", function()
    baseline()
    now = now + 30
    GC.MailStock.Bought("A-B", 101, 50)
    now = now + 130
    inbox({ player(900, 1) })
    scan(true)
    close()
    assert.equal(50, count(101))
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

  -- R1: a fresh delivery can read 30 minutes "younger" on one pass than on the next (the ledger's
  -- 2026-08-19 incident); the same mail must not be credited twice.
  it("credits a fresh won auction once when its expiry moves half an hour between passes", function()
    baseline()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 6)
    GC.MailStock.Bought("A-B", 101, 6, now + 5)
    now = now + 20
    local placeholder = won(101, 6, now - 20)
    placeholder.shift = -1800
    show({ placeholder, player(900, 1) })
    assert.equal(12, count(101))
    inbox({ won(101, 6, now - 20), player(900, 1) })
    scan(false)
    assert.equal(12, count(101))
    close(5)
    assert.equal(12, count(101))
  end)

  -- R2: with mail always out of view, a taken mail's attachment must not swallow the next one.
  local function overflow(n)
    local out = {}
    for i = 1, n do out[i] = player(500 + i, 1) end
    return out
  end

  it("tells a take from a scroll by the total, so the same purchase minutes later is credited", function()
    local hidden = overflow(5)
    baseline()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 10
    show({ won(101, 6, now - 10), player(900, 1) }, hidden)
    assert.equal(6, count(101))
    box.api.TakeInboxItem(1, 1)
    box:advance()
    scan(false)
    assert.equal(0, count(101))
    close()
    now = now + 180
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 10
    show({ won(101, 6, now - 10), player(900, 1) }, hidden)
    assert.equal(6, count(101))
    box.api.TakeInboxItem(1, 1)
    box:advance()
    scan(false)
    close()
    assert.equal(0, count(101))
    for _ = 1, 3 do
      now = now + DAY
      show({ player(900, 1) }, hidden)
      close()
    end
    assert.equal(0, count(101))
  end)

  -- A take that landed after the visit's last pass: the next visit's total says the mail went, so
  -- the same purchase made minutes later is credited when it shows.
  it("lets a mail taken after the last pass go at the next read, when the total fell by it", function()
    local hidden = overflow(5)
    baseline()
    now = now + 600
    show({ won(101, 6, now), player(900, 1) }, hidden)
    box.api.TakeInboxItem(1, 1)
    close()
    box:advance()
    now = now + 60
    show({ player(900, 1) }, hidden)
    close()
    now = now + 60
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 10
    show({ won(101, 6, now - 10), player(900, 1) }, hidden)
    assert.equal(6, count(101))
  end)

  it("keeps what scrolled out of view when new mail pushed it, and its key does not grow for ever", function()
    local hidden = overflow(5)
    baseline()
    now = now + 600
    local old = won(101, 6, now - DAY)
    show({ old, player(900, 1) }, hidden)
    close()
    -- New mail arrived: the total rose, and the old won auction is out of view.
    now = now + 60
    show({ player(902, 1), player(900, 1) }, { old, hidden[1], hidden[2], hidden[3], hidden[4], hidden[5] })
    close()
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 10
    show({ old, player(900, 1) }, hidden)
    -- The old one is back in view and not a delivery: the purchase still counts.
    assert.equal(12, count(101))
    -- Thirty days on, nothing of it is kept.
    now = now + 31 * DAY
    show({ player(900, 1) }, hidden)
    local c = GC.db.mailStock.chars["A-B"]
    local away = c.away or {}
    for _, set in ipairs({ c.seen, c.fresh, away.seen or {}, away.fresh or {} }) do
      for key in pairs(set) do assert.is_nil(key:find("^101:"), key) end
    end
  end)

  -- A seller's inbox: the won auction was credited, then the day's sale mail pushed it past the
  -- hundredth row. It still waits there, so BUY must not offer its units again.
  it("keeps counting a credited purchase whose mail newer mail pushed out of view", function()
    local hidden = overflow(3)
    baseline()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 200)
    now = now + 10
    local mail = won(101, 200, now - 10)
    show({ mail, player(900, 1) }, hidden)
    assert.equal(200, count(101))
    close()
    now = now + 600
    show({ player(902, 1), player(900, 1) }, { mail, hidden[1], hidden[2], hidden[3] })
    assert.equal(200, count(101))
    close()
    -- The sale mail is taken and the won auction is back in view: the same two hundred.
    now = now + 60
    show({ mail, player(900, 1) }, hidden)
    assert.equal(200, count(101))
  end)

  -- C1: what is kept for mail out of view lasts until that mail comes back or would have expired,
  -- not until the next pass where nothing changed.
  it("never credits a won auction again when it comes back into view after unchanged passes", function()
    local hidden = overflow(2)
    baseline()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 10
    local first = won(101, 6, now - 10)
    show({ first, player(900, 1) }, hidden)
    assert.equal(6, count(101))
    close()
    -- A second purchase of the same within the hour; its mail stays out of view.
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 10
    -- New mail in front pushed the first won auction out of view, then a pass where nothing changed.
    show({ player(902, 1), player(900, 1) }, { first, won(101, 6, now - 10), hidden[1], hidden[2] })
    scan(false)
    -- The new mail is taken, and the first won auction comes back into view.
    inbox({ player(900, 1), first }, { won(101, 6, now - 10), hidden[1], hidden[2] })
    scan(false)
    assert.equal(12, count(101))
    scan(false)
    assert.equal(12, count(101))
  end)

  -- The last take of each visit leaves no row in view, so no pass reads it, and the next visit's
  -- new mail hides whether it was taken or pushed out of view: its key is kept as out of view
  -- until that mail would have expired.
  it("keeps the store bounded by the mail's expiry with an inbox always over 100 and mail taken on every visit", function()
    local hidden = overflow(1)
    baseline()
    local id = 1000
    local function size(t)
      local n = 0
      for _ in pairs(t or {}) do n = n + 1 end
      return n
    end
    local function kept()
      local c = GC.db.mailStock.chars["A-B"]
      local away = c.away or {}
      return size(c.seen) + size(c.fresh) + size(away.seen) + size(away.fresh)
    end
    for visit = 1, 50 do
      local rows = {}
      for i = 1, 10 do
        id = id + 1
        rows[i] = returned(id, 1, now)
      end
      show(rows, hidden)
      for _ = 1, 10 do
        box.api.TakeInboxItem(1, 1)
        box:advance()
        scan(false)
      end
      close()
      assert.is_true(kept() <= visit + 1, kept() .. " keys kept after visit " .. visit)
      now = now + 3600
    end
    now = now + 31 * DAY
    show({ player(900, 1) }, hidden)
    close()
    assert.is_true(kept() <= 2, kept() .. " keys kept")
  end)

  -- R4: an old won auction out of view since the first read is no delivery when it comes into view.
  it("never takes a won auction that came before the purchase for its delivery", function()
    local old = won(101, 6, now - 20 * DAY)
    show({ player(900, 1) }, { old })
    close()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 6)
    now = now + 30
    show({ old, player(900, 1) }, { won(101, 6, now - 30), player(777, 1) })
    assert.equal(12, count(101))
  end)

  -- R5: a won auction already seen is never a delivery, even when another player's mail of the same
  -- item, count and expiry sits among the new ones.
  it("never credits a won auction already seen, for a player's mail of the same key", function()
    baseline()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 20)
    now = now + 10
    show({ won(101, 20, now - 10), player(900, 1) })
    assert.equal(20, count(101))
    GC.MailStock.Bought("A-B", 101, 20)
    -- An alt's 20 arrives within the same minutes of expiry; the second purchase is not listed yet.
    inbox({ won(101, 20, now - 10), player(101, 20, nil, now - 5), player(900, 1) })
    scan(false)
    assert.equal(60, count(101))
    scan(false)
    assert.equal(60, count(101))
  end)

  -- R5: a player's mail takes a new key before one already seen, so a won auction pushed out of
  -- view beside it keeps its own after that mail is taken.
  it("keeps a credited won auction's key out of view when a player's mail of the same key goes", function()
    local hidden = overflow(1)
    baseline()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 20)
    now = now + 10
    local first = won(101, 20, now - 10)
    local alt = player(101, 20, nil, now - 5)
    show({ alt, first, player(900, 1) }, hidden)
    assert.equal(40, count(101))
    close()
    -- A second purchase of the same; its mail stays out of view.
    now = now + 120
    GC.MailStock.Bought("A-B", 101, 20)
    now = now + 10
    local second = won(101, 20, now - 10)
    -- New mail pushed the first won auction out of view; then the alt's mail is taken.
    show({ player(902, 1), alt, player(900, 1) }, { first, second, hidden[1] })
    inbox({ player(902, 1), player(900, 1) }, { first, second, hidden[1] })
    scan(false)
    -- The new mail is taken too, and the first won auction comes back into view.
    inbox({ player(900, 1), first }, { second, hidden[1] })
    scan(false)
    assert.equal(40, count(101))
  end)

  -- R5: nor when the player's mail is read before the won auction it shares a key with.
  it("never lets a player's mail read above a credited won auction use up its key", function()
    local hidden = overflow(1)
    baseline()
    now = now + 600
    GC.MailStock.Bought("A-B", 101, 20)
    now = now + 10
    local first = won(101, 20, now - 10)
    show({ first, player(900, 1) }, hidden)
    assert.equal(20, count(101))
    close()
    -- A second purchase of the same; its mail stays out of view.
    now = now + 120
    GC.MailStock.Bought("A-B", 101, 20)
    now = now + 10
    -- An alt's 20, sent when the first was delivered, now sits above it.
    show({ player(101, 20, nil, now - 140), first, player(900, 1) }, { won(101, 20, now - 10), hidden[1] })
    assert.equal(60, count(101))
    scan(false)
    assert.equal(60, count(101))
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

  -- I3: a take that lands after the visit's last pass stays counted until a visit that shows mail;
  -- an empty inbox is not read (the client may answer 0, 0 before the rows).
  it("keeps the last mail taken with no pass after it counted until a visit that shows mail", function()
    baseline()
    now = now + 600
    show({ won(101, 6, now) })
    assert.equal(6, count(101))
    box.api.TakeInboxItem(1, 1)
    close()
    box:advance()
    assert.equal(6, count(101))
    now = now + 60
    show({})
    assert.is_false(close(5))
    assert.equal(6, count(101))
    now = now + 600
    show({ player(900, 1) })
    assert.equal(0, count(101))
  end)

  -- R3: on a reopen inside the CanCheckInbox window the client may answer 0, 0 before the rows.
  it("reads no empty inbox from a visit that never showed a row, however long it lasts", function()
    show({ won(101, 6, now - 3600) })
    close()
    GC.MailStock.Bought("A-B", 101, 4)
    now = now + 200
    show({})
    assert.is_false(close(30))
    assert.equal(10, count(101))
    inbox({})
    scan(true)
    assert.is_false(close(5))
    assert.equal(10, count(101))
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
