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
