local helper = require("spec.spec_helper")

describe("MailReturns, the log of lots that came back", function()
  local GC, db, realTime
  local DAY = 86400

  before_each(function()
    realTime = _G.time
    GC = helper.loadModule("Core/MailReturns.lua")
    db = {}
  end)

  after_each(function() _G.time = realTime end)

  it("stores exactly itemID, count, reason and at", function()
    GC.MailReturns.Init(db)
    local entry = GC.MailReturns.Record(100, 5, "expired", 1000)
    assert.same({ itemID = 100, count = 5, reason = "expired", at = 1000 }, GC.MailReturns.Entries()[1])
    assert.equal(entry, GC.MailReturns.Entries()[1])
  end)

  it("refuses what is not a lot that came back", function()
    GC.MailReturns.Init(db)
    assert.is_nil(GC.MailReturns.Record(0, 5, "expired", 1000))
    assert.is_nil(GC.MailReturns.Record(1.5, 5, "expired", 1000))
    assert.is_nil(GC.MailReturns.Record(100, 0, "expired", 1000))
    assert.is_nil(GC.MailReturns.Record(100, 5, "outbid", 1000))
    assert.is_nil(GC.MailReturns.Record(100, 5, nil, 1000))
    assert.same({}, GC.MailReturns.Entries())
  end)

  it("records a cancelled lot with its own reason", function()
    GC.MailReturns.Init(db)
    assert.equal("cancelled", GC.MailReturns.Record(100, 1, "cancelled", 1000).reason)
  end)

  it("keeps an entry exactly 14 days old and drops one a second older", function()
    GC.MailReturns.Init(db)
    local now = 10 * 14 * DAY
    db.mailReturns[1] = { itemID = 1, count = 1, reason = "expired", at = now - 14 * DAY }
    db.mailReturns[2] = { itemID = 2, count = 1, reason = "expired", at = now - 14 * DAY - 1 }
    assert.equal(1, GC.MailReturns.Prune(now))
    assert.equal(1, #GC.MailReturns.Entries())
    assert.equal(1, GC.MailReturns.Entries()[1].itemID)
  end)

  it("prunes what a stale save carries when it initialises", function()
    local now = 100 * DAY
    _G.time = function() return now end
    db.mailReturns = {
      { itemID = 1, count = 1, reason = "expired", at = now - 15 * DAY },
      { itemID = 2, count = 1, reason = "expired", at = now - 1 },
    }
    GC.MailReturns.Init(db)
    assert.equal(1, #db.mailReturns)
    assert.equal(2, db.mailReturns[1].itemID)
  end)

  it("keeps the array Entries() handed out when it prunes", function()
    GC.MailReturns.Init(db)
    local live = GC.MailReturns.Entries()
    GC.MailReturns.Record(1, 1, "expired", 1)
    GC.MailReturns.Record(2, 1, "expired", 20 * DAY)
    assert.equal(live, GC.MailReturns.Entries())
    assert.equal(1, #live)
  end)

  it("leaves a newer save alone and records nothing", function()
    local newer = { { itemID = 1, count = 1, reason = "expired", at = 1, extra = true } }
    db.mailReturns = newer
    db.mailReturnsVersion = 2
    _G.time = function() return 100 * DAY end
    GC.MailReturns.Init(db)
    assert.equal(2, db.mailReturnsVersion)
    assert.equal(newer, db.mailReturns)
    assert.same({ { itemID = 1, count = 1, reason = "expired", at = 1, extra = true } }, db.mailReturns)
    assert.is_nil(GC.MailReturns.Record(5, 1, "expired", 100 * DAY))
    assert.equal(1, #db.mailReturns)
  end)

  -- SELL counts unsold rounds from what Entries() hands it, into a save of its own version: a log
  -- of a shape this build does not know must not reach it.
  it("hands out no entries from a newer save", function()
    db.mailReturns = { { itemID = 1, count = 1, reason = "expired", at = 1, extra = true } }
    db.mailReturnsVersion = 2
    _G.time = function() return 100 * DAY end
    GC.MailReturns.Init(db)
    assert.same({}, GC.MailReturns.Entries())
    assert.equal(1, #db.mailReturns)
  end)

  it("creates the log and its version on a fresh save", function()
    GC.MailReturns.Init(db)
    assert.equal(1, db.mailReturnsVersion)
    assert.same({}, db.mailReturns)
    assert.same({}, db.mailReturnsSeen)
  end)

  it("replaces a log that is not a table", function()
    db.mailReturns = "broken"
    GC.MailReturns.Init(db)
    assert.same({}, db.mailReturns)
  end)

  -- Observe is fed by the ledger's inbox scan (spec/ledger_returns_spec.lua drives it through the
  -- real scan); these are its own edges.
  describe("Observe", function()
    local CONTEXT = { char = "A-B", region = "eu" }
    local function lot(itemID, expiresAt) return { itemID = itemID, count = 1, reason = "expired", expiresAt = expiresAt } end

    it("forgets a seen lot once its mail has expired, even on a scan that could not read everything", function()
      GC.MailReturns.Init(db)
      assert.equal(1, GC.MailReturns.Observe({ lot(5, 2000) }, CONTEXT, 1000, false))
      assert.equal(1, #db.mailReturnsSeen)
      GC.MailReturns.Observe({}, CONTEXT, 2000 + GC.MailReturns.MATCH_SECONDS + 1, false)
      assert.same({}, db.mailReturnsSeen)
    end)

    it("logs nothing and keeps nothing in a newer save", function()
      db.mailReturnsVersion = 2
      db.mailReturns = {}
      GC.MailReturns.Init(db)
      assert.equal(0, GC.MailReturns.Observe({ lot(5, 2000) }, CONTEXT, 1000, true))
      assert.same({}, db.mailReturns)
      assert.is_nil(db.mailReturnsSeen)
    end)

    it("logs nothing without a character and a region to keep the lot under", function()
      GC.MailReturns.Init(db)
      assert.equal(0, GC.MailReturns.Observe({ lot(5, 2000) }, { char = "A-B" }, 1000, true))
      assert.equal(0, GC.MailReturns.Observe({ lot(5, 2000) }, nil, 1000, true))
      assert.same({}, GC.MailReturns.Entries())
    end)
  end)

  it("keeps keys it does not know in a stored entry", function()
    _G.time = function() return 100 * DAY end
    db.mailReturns = { { itemID = 1, count = 1, reason = "expired", at = 100 * DAY, note = "kept" } }
    GC.MailReturns.Init(db)
    assert.equal("kept", db.mailReturns[1].note)
  end)

  it("records nothing before Init", function()
    assert.is_nil(GC.MailReturns.Record(100, 5, "expired", 1000))
    assert.same({}, GC.MailReturns.Entries())
  end)
end)
