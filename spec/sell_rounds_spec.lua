local helper = require("spec.spec_helper")

-- Followed groups (plan 2026-10-22, task 9): how many times an item came back unsold since its
-- last sale. A flip group's rule posts it a little cheaper each round (Core/SellPositions.lua).
-- The returns come from the mail log (GC.MailReturns, the mail branch: `{ itemID, count, reason,
-- at }`); a sale mail resets the count (Core/Ledger.lua). Times are seconds.
describe("SellRounds", function()
  local GC, db
  local day = 86400

  local function expired(itemID, at) return { itemID = itemID, count = 1, reason = "expired", at = at } end

  before_each(function()
    GC = helper.loadModule("Core/SellRounds.lua")
    db = {}
    GC.SellRounds.Init(db)
  end)

  it("starts a versioned table in the save", function()
    assert.same({ v = 1, lastReturnAt = 0, items = {} }, db.sellRounds)
    assert.equal(0, GC.SellRounds.Rounds(10))
  end)

  it("an expired return adds a round, a cancelled one does not", function()
    assert.equal(1, GC.SellRounds.Ingest({ expired(10, 1000),
      { itemID = 11, count = 1, reason = "cancelled", at = 1000 } }, 1000))
    assert.equal(1, GC.SellRounds.Rounds(10))
    assert.equal(0, GC.SellRounds.Rounds(11))
  end)

  it("returns of one item within the hour count once", function()
    GC.SellRounds.Ingest({ expired(10, 1000), expired(10, 1500), expired(10, 1000 + 7200) }, 9000)
    assert.equal(2, GC.SellRounds.Rounds(10))
  end)

  it("ingesting the same log twice adds nothing", function()
    local log = { expired(10, 1000), expired(12, 1000), expired(10, 5000) }
    assert.equal(3, GC.SellRounds.Ingest(log, 6000))
    assert.equal(0, GC.SellRounds.Ingest(log, 6000))
    -- A mail collected later, in the same second as the last one counted, still counts.
    log[#log + 1] = expired(13, 5000)
    assert.equal(1, GC.SellRounds.Ingest(log, 6000))
  end)

  it("reads the log as the mail module keeps it, or wrapped in entries", function()
    assert.equal(1, GC.SellRounds.Ingest({ entries = { expired(10, 1000) } }, 1000))
    assert.equal(1, GC.SellRounds.Rounds(10))
  end)

  it("a sale resets the count and older returns stay uncounted", function()
    GC.SellRounds.Ingest({ expired(10, 1000), expired(10, 1000 + 3600) }, 4600)
    assert.equal(2, GC.SellRounds.Rounds(10))
    assert.is_true(GC.SellRounds.Sold(10, 5000))
    assert.equal(0, GC.SellRounds.Rounds(10))
    assert.equal(0, GC.SellRounds.Ingest({ expired(10, 4000) }, 6000))
    assert.equal(0, GC.SellRounds.Rounds(10))
    assert.is_false(GC.SellRounds.Sold(10, 4000))
    -- A return after the sale is a new round.
    assert.equal(1, GC.SellRounds.Ingest({ expired(10, 9000) }, 9000))
    assert.equal(1, GC.SellRounds.Rounds(10))
  end)

  it("untouched for 30 days is pruned", function()
    GC.SellRounds.Sold(10, 0)
    GC.SellRounds.Sold(11, day)
    assert.equal(1, GC.SellRounds.Prune(30 * day + 1))
    assert.is_nil(db.sellRounds.items[10])
    assert.is_not_nil(db.sellRounds.items[11])
  end)

  it("a newer save is left alone", function()
    local saved = { v = 2, items = { [10] = { rounds = 4 } } }
    db = { sellRounds = saved }
    GC.SellRounds.Init(db)
    assert.equal(0, GC.SellRounds.Ingest({ expired(10, 1000) }, 1000))
    assert.equal(0, GC.SellRounds.Rounds(10))
    assert.is_false(GC.SellRounds.Sold(10, 2000))
    assert.equal(0, GC.SellRounds.Prune(100 * day))
    assert.same({ v = 2, items = { [10] = { rounds = 4 } } }, db.sellRounds)
  end)

  it("keeps a save of its own version and repairs a broken one", function()
    db = { sellRounds = { v = 1, lastReturnAt = 1000, items = { [10] = { rounds = 2, returnAt = 900, at = 900 } } } }
    GC.SellRounds.Init(db)
    assert.equal(2, GC.SellRounds.Rounds(10))
    db = { sellRounds = "junk" }
    GC.SellRounds.Init(db)
    assert.same({ v = 1, lastReturnAt = 0, items = {} }, db.sellRounds)
  end)

  it("no returns log is no rounds", function()
    assert.equal(0, GC.SellRounds.Ingest(nil, 1))
    assert.equal(0, GC.SellRounds.Ingest({ "x", { itemID = "a", reason = "expired", at = 1 },
      { itemID = 10, reason = "expired" } }, 1))
    assert.equal(0, GC.SellRounds.Rounds(10))
  end)

  it("does nothing before Init", function()
    local fresh = helper.loadModule("Core/SellRounds.lua")
    assert.equal(0, fresh.SellRounds.Ingest({ expired(10, 1000) }, 1000))
    assert.equal(0, fresh.SellRounds.Rounds(10))
    assert.is_false(fresh.SellRounds.Sold(10, 1000))
  end)
end)

-- The mail loop writes a lot's returns entry before it takes the lot, and takes the entry back
-- when the take did nothing (Core/MailLoop.lua). A compose that read the entry in between must not
-- keep the round it gave (group-rules review M2): the count reads the log again until an entry
-- is settled.
describe("SellRounds with the mail loop's returns log", function()
  local Mailbox = require("spec.support.mail_inbox")
  local GC, box, loop, clock, epoch
  local EXPIRED = function(itemID) return { sender = "Auction House", subject = "Auction expired: Silk",
    auction = true, items = { [1] = { itemID = itemID, count = 1 } } } end

  local function visit(rows, at)
    box = Mailbox.new(rows)
    epoch = at
    loop = GC.MailLoop.New({
      api = box:flat({ free = 20 }),
      patterns = GC.MailClassify.Patterns({ expired = "Auction expired: %s", removed = "Auction canceled: %s",
        outbid = "Outbid on %s" }),
      enabled = function() return { sales = true, returns = true, purchases = true, players = true } end,
      scanLedger = function() end,
      context = function() return { char = "A-B", region = "eu" } end,
      epoch = function() return epoch end,
      errors = { full = "Inventory is full.", unique = "You can't carry any more of those items." },
    })
  end

  local function runToEnd()
    for _ = 1, 60 do
      box:advance()
      clock = clock + GC.MailLoop.DELAY + 0.01
      loop:Step(clock)
      if loop:State() == "done" then return end
    end
  end

  -- What the Sell tab does on every compose (Services/Sell/Compose.lua).
  local function compose(now) GC.SellRounds.Ingest(GC.MailReturns.Entries(), now) end

  before_each(function()
    _G.RETRIEVING_DATA = "Retrieving data..."
    GC = helper.loadModule("Core/Ledger.lua")
    GC.Ledger.Init({})
    helper.loadModule("Core/MailReturns.lua", GC)
    helper.loadModule("Core/MailClassify.lua", GC)
    helper.loadModule("Core/MailLoop.lua", GC)
    helper.loadModule("Core/SellRounds.lua", GC)
    local db = {}
    GC.MailReturns.Init(db)
    GC.SellRounds.Init(db)
    clock = 100
  end)

  after_each(function() _G.RETRIEVING_DATA = nil end)

  it("leaves no round for an entry taken back after a compose read it", function()
    visit({ EXPIRED(5), EXPIRED(6) }, 5000)
    box:refuse(5)
    loop:Start(clock)
    -- The take of item 5 is out and its entry written: a compose now sees the round.
    compose(5000)
    assert.equal(1, GC.SellRounds.Rounds(5))
    runToEnd()
    -- Item 5 never left the mailbox, its entry is gone; item 6 came back.
    assert.same({ { itemID = 6, count = 1, reason = "expired", at = 5000 } }, GC.MailReturns.Entries())
    compose(5001)
    assert.equal(0, GC.SellRounds.Rounds(5))
    assert.equal(1, GC.SellRounds.Rounds(6))
  end)

  it("counts the lot once when it is taken on a later visit", function()
    visit({ EXPIRED(5) }, 5000)
    box:refuse(5)
    loop:Start(clock)
    compose(5000)
    runToEnd()
    compose(5001)
    -- Two hours later the same lot is taken: one round, not two.
    visit({ EXPIRED(5) }, 5000 + 7200)
    loop:Start(clock)
    runToEnd()
    compose(5000 + 7200)
    assert.equal(1, GC.SellRounds.Rounds(5))
    -- And it stays one once its entry is settled and saved.
    compose(5000 + 7200 + GC.SellRounds.SETTLE_SECONDS)
    assert.equal(1, GC.SellRounds.Rounds(5))
    compose(5000 + 7200 + 2 * GC.SellRounds.SETTLE_SECONDS)
    assert.equal(1, GC.SellRounds.Rounds(5))
  end)

  it("counts a second return within the hour once the first one is taken back", function()
    local log = {}
    local first = { itemID = 5, count = 1, reason = "expired", at = 5000 }
    log[1] = first
    assert.equal(1, GC.SellRounds.Ingest(log, 5000))
    log[2] = { itemID = 5, count = 1, reason = "expired", at = 5600 }
    assert.equal(0, GC.SellRounds.Ingest(log, 5600))
    table.remove(log, 1)
    assert.equal(0, GC.SellRounds.Ingest(log, 5601))
    assert.equal(1, GC.SellRounds.Rounds(5))
  end)
end)
