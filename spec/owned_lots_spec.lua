local helper = require("spec.spec_helper")

describe("Owned lots store", function()
  local GC, db

  local function lot(over)
    local l = { positionKey = "commodity:190316", itemID = 190316, quantity = 20,
      unitPrice = 921200, auctionID = 1932076389, firstSeenAt = 1757100000,
      isCommodity = true, expiresAt = 1757200000 }
    for k, v in pairs(over or {}) do l[k] = v end
    return l
  end

  local scope = { char = "Aiyana-Dentarg", region = "eu" }

  before_each(function()
    GC = helper.loadModule("Core/ImportString.lua")
    helper.loadModule("Core/Data.lua", GC)
    db = { ownedLots = {} }
  end)

  it("stores a fresh lot in the wire shape", function()
    assert.is_true(GC.Data.RecordOwnedLots(db, { lot() }, scope, 1757100000))
    local row = db.ownedLots[1]
    assert.equal(1932076389, row.auctionID)
    assert.equal(190316, row.itemID)
    assert.is_true(row.isCommodity)
    assert.equal(20, row.quantity)
    assert.equal(921200, row.unitPrice)
    assert.equal(1757200000, row.expiresAt)
    assert.equal("Aiyana-Dentarg", row.char)
    assert.equal("eu", row.region)
    assert.equal(1757100000, row.seenAt)
    assert.is_nil(row.cancelledAt)
  end)

  it("keeps cancelledAt when a re-seen lot's price and quantity are unchanged", function()
    GC.Data.RecordOwnedLots(db, { lot() }, scope, 1000)
    GC.Data.MarkOwnedLotCancelled(db, 1932076389, scope, 1050)
    GC.Data.RecordOwnedLots(db, { lot() }, scope, 1100)
    assert.equal(1050, db.ownedLots[1].cancelledAt)
    assert.equal(1100, db.ownedLots[1].seenAt)
  end)

  it("clears cancelledAt when the price changes -- a new fact", function()
    GC.Data.RecordOwnedLots(db, { lot() }, scope, 1000)
    GC.Data.MarkOwnedLotCancelled(db, 1932076389, scope, 1050)
    GC.Data.RecordOwnedLots(db, { lot({ unitPrice = 900000 }) }, scope, 1100)
    assert.is_nil(db.ownedLots[1].cancelledAt)
    assert.equal(900000, db.ownedLots[1].unitPrice)
  end)

  it("clears cancelledAt when the quantity changes -- a new fact", function()
    GC.Data.RecordOwnedLots(db, { lot() }, scope, 1000)
    GC.Data.MarkOwnedLotCancelled(db, 1932076389, scope, 1050)
    GC.Data.RecordOwnedLots(db, { lot({ quantity = 10 }) }, scope, 1100)
    assert.is_nil(db.ownedLots[1].cancelledAt)
  end)

  it("leaves a row for the same char that is not in the roster untouched", function()
    GC.Data.RecordOwnedLots(db, { lot() }, scope, 1000)
    GC.Data.RecordOwnedLots(db, {}, scope, 2000) -- empty roster: the lot fell off the AH tab
    assert.equal(1, #db.ownedLots)
    assert.equal(1000, db.ownedLots[1].seenAt)
  end)

  it("does not touch another character's rows", function()
    GC.Data.RecordOwnedLots(db, { lot() }, scope, 1000)
    local other = { char = "Bjorn-Area52", region = "us" }
    GC.Data.RecordOwnedLots(db, {}, other, 2000)
    assert.equal(1, #db.ownedLots)
    assert.equal("Aiyana-Dentarg", db.ownedLots[1].char)
    assert.equal(1000, db.ownedLots[1].seenAt)
  end)

  it("prunes rows older than three days on write", function()
    GC.Data.RecordOwnedLots(db, { lot({ auctionID = 1 }) }, scope, 1000)
    GC.Data.RecordOwnedLots(db, { lot({ auctionID = 2 }) }, scope,
      1000 + GC.Data.OWNED_LOT_MAX_AGE + 1)
    local seen = {}
    for _, row in ipairs(db.ownedLots) do seen[row.auctionID] = true end
    assert.is_nil(seen[1])
    assert.is_true(seen[2])
  end)

  it("caps the table at 500 rows by evicting the oldest seenAt", function()
    for i = 1, 500 do
      GC.Data.RecordOwnedLots(db, { lot({ auctionID = i }) }, scope, 1000 + i)
    end
    GC.Data.RecordOwnedLots(db, { lot({ auctionID = 999 }) }, scope, 9000)
    assert.equal(500, #db.ownedLots)
    local seen = {}
    for _, row in ipairs(db.ownedLots) do seen[row.auctionID] = true end
    assert.is_nil(seen[1])
    assert.is_true(seen[999])
  end)

  it("returns true but adds nothing when every lot in the roster is invalid", function()
    assert.is_true(GC.Data.RecordOwnedLots(db, { lot({ auctionID = 0 }) }, scope, 1000))
    assert.equal(0, #db.ownedLots)
  end)

  it("drops one bad lot but keeps the rest of the roster", function()
    assert.is_true(GC.Data.RecordOwnedLots(db,
      { lot({ auctionID = 1, unitPrice = 0 }), lot({ auctionID = 2 }) }, scope, 1000))
    assert.equal(1, #db.ownedLots)
    assert.equal(2, db.ownedLots[1].auctionID)
  end)

  it("rejects a call with an invalid scope, now, or lots argument", function()
    assert.is_nil(GC.Data.RecordOwnedLots(db, { lot() }, { char = "A-R", region = "xx" }, 1000))
    assert.is_nil(GC.Data.RecordOwnedLots(db, { lot() }, { region = "eu" }, 1000))
    assert.is_nil(GC.Data.RecordOwnedLots(db, { lot() }, scope, nil))
    assert.is_nil(GC.Data.RecordOwnedLots(db, "not a table", scope, 1000))
    assert.equal(0, #db.ownedLots)
  end)

  it("rejects a scope whose char is not Name-Realm", function()
    assert.is_nil(GC.Data.RecordOwnedLots(db, { lot() }, { char = "NoRealm", region = "eu" }, 1000))
    assert.is_nil(GC.Data.RecordOwnedLots(db, { lot() }, { char = "Too-Many-Hyphens", region = "eu" }, 1000))
    assert.is_nil(GC.Data.RecordOwnedLots(db, { lot() }, { char = "", region = "eu" }, 1000))
    assert.equal(0, #db.ownedLots)
  end)

  it("drops a lot whose isCommodity is not a boolean instead of coercing it to false", function()
    -- A Lua table constructor cannot express "isCommodity explicitly nil"
    -- through lot()'s override merge (assigning nil removes the key), so
    -- this row is built by hand, entirely missing the field.
    local missingField = { auctionID = 1932076389, itemID = 190316, quantity = 20, unitPrice = 921200 }
    assert.is_true(GC.Data.RecordOwnedLots(db, { missingField }, scope, 1000))
    assert.equal(0, #db.ownedLots)
    assert.is_true(GC.Data.RecordOwnedLots(db, { lot({ isCommodity = "yes" }) }, scope, 1000))
    assert.equal(0, #db.ownedLots)
  end)

  it("tolerates a missing or corrupt ownedLots table", function()
    assert.is_nil(GC.Data.RecordOwnedLots({ ownedLots = "corrupt" }, { lot() }, scope, 1000))
    local fresh = {}
    assert.is_true(GC.Data.RecordOwnedLots(fresh, { lot() }, scope, 1000))
    assert.equal(1, #fresh.ownedLots)
  end)

  describe("MarkOwnedLotCancelled", function()
    it("stamps cancelledAt on the matching row", function()
      GC.Data.RecordOwnedLots(db, { lot() }, scope, 1000)
      assert.is_true(GC.Data.MarkOwnedLotCancelled(db, 1932076389, scope, 1050))
      assert.equal(1050, db.ownedLots[1].cancelledAt)
    end)

    it("returns nil for an auctionID it does not hold", function()
      assert.is_nil(GC.Data.MarkOwnedLotCancelled(db, 404, scope, 1050))
    end)

    it("does not stamp a row belonging to a different character", function()
      GC.Data.RecordOwnedLots(db, { lot() }, scope, 1000)
      local other = { char = "Bjorn-Area52", region = "us" }
      assert.is_nil(GC.Data.MarkOwnedLotCancelled(db, 1932076389, other, 1050))
      assert.is_nil(db.ownedLots[1].cancelledAt)
    end)
  end)
end)
