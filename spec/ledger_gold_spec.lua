local helper = require("spec.spec_helper")

describe("Ledger gold series", function()
  local GC, db
  local context = { char = "Belarsa-Dentarg", region = "eu" }

  before_each(function()
    GC = helper.loadModule("Core/Ledger.lua")
    db = {}
    GC.Ledger.Init(db)
  end)

  it("stores the first reading it is given", function()
    assert.is_true(GC.Ledger.RecordGold(123456, context, 1000))
    local points = GC.Ledger.GetGold()
    assert.equal(1, #points)
    assert.equal(123456, points[1].copper)
    assert.equal("Belarsa-Dentarg", points[1].char)
  end)

  it("ignores a reading taken again too soon", function()
    GC.Ledger.RecordGold(123456, context, 1000)
    -- PLAYER_MONEY fires on every vendor sale, loot and repair; storing each
    -- one would bloat SavedVariables for a curve nobody can see at that zoom.
    assert.is_false(GC.Ledger.RecordGold(999999, context, 1000 + 60))
    assert.equal(1, #GC.Ledger.GetGold())
  end)

  it("stores again once the interval has passed", function()
    GC.Ledger.RecordGold(123456, context, 1000)
    assert.is_true(GC.Ledger.RecordGold(999999, context, 1000 + 300))
    assert.equal(2, #GC.Ledger.GetGold())
  end)

  it("always stores a forced reading, which is what logout uses", function()
    GC.Ledger.RecordGold(123456, context, 1000)
    assert.is_true(GC.Ledger.RecordGold(999999, context, 1000 + 5, true))
    assert.equal(999999, GC.Ledger.GetGold()[2].copper)
  end)

  it("does not store an unchanged amount even when forced", function()
    GC.Ledger.RecordGold(123456, context, 1000)
    -- Logging out five times without earning anything must not draw five
    -- points on a flat line.
    assert.is_false(GC.Ledger.RecordGold(123456, context, 9999, true))
    assert.equal(1, #GC.Ledger.GetGold())
  end)

  it("tracks each character separately", function()
    GC.Ledger.RecordGold(100, { char = "A-Dentarg", region = "eu" }, 1000)
    -- A different alt's first reading is its own first reading, not a
    -- too-soon repeat of the previous character's.
    assert.is_true(GC.Ledger.RecordGold(200, { char = "B-Dentarg", region = "eu" }, 1010))
    assert.equal(2, #GC.Ledger.GetGold())
  end)

  it("drops the oldest point when the series is full", function()
    for i = 1, GC.Ledger.MAX_GOLD_POINTS do
      GC.Ledger.RecordGold(i, context, i * 300)
    end
    GC.Ledger.RecordGold(777, context, 9999999)
    local points = GC.Ledger.GetGold()
    assert.equal(GC.Ledger.MAX_GOLD_POINTS, #points)
    assert.equal(2, points[1].copper)
    assert.equal(777, points[#points].copper)
  end)

  it("ignores a non-numeric reading rather than storing junk", function()
    assert.is_false(GC.Ledger.RecordGold(nil, context, 1000))
    assert.equal(0, #GC.Ledger.GetGold())
  end)

  it("ignores a zero reading once a real balance is known", function()
    -- Seen in real SavedVariables: GetMoney() returns 0 when the client has
    -- not loaded (or has already torn down) the player's money, which is
    -- exactly what the forced PLAYER_LOGOUT sample catches. A goldmaker's
    -- curve dropping to zero and back is always that artifact, never an
    -- event, and one such point makes the coverage figure nonsense.
    GC.Ledger.RecordGold(2598169166, context, 1000)
    assert.is_false(GC.Ledger.RecordGold(0, context, 9000))
    assert.equal(1, #GC.Ledger.GetGold())
  end)

  it("ignores a zero reading even when forced, which is when it actually happens", function()
    GC.Ledger.RecordGold(2598169166, context, 1000)
    assert.is_false(GC.Ledger.RecordGold(0, context, 9000, true))
    assert.equal(1, #GC.Ledger.GetGold())
  end)

  it("still records zero as a character's first reading", function()
    -- A brand-new alt really does have nothing, and refusing to ever start a
    -- curve at zero would leave it invisible until its first sale.
    assert.is_true(GC.Ledger.RecordGold(0, { char = "Fresh-Dentarg", region = "eu" }, 1000))
    assert.equal(1, #GC.Ledger.GetGold())
  end)

  it("keeps a zero from one character out of another character's history", function()
    GC.Ledger.RecordGold(500, { char = "Rich-Dentarg", region = "eu" }, 1000)
    assert.is_true(GC.Ledger.RecordGold(0, { char = "Poor-Dentarg", region = "eu" }, 1010))
    assert.equal(2, #GC.Ledger.GetGold())
  end)

  it("is a no-op before Init", function()
    local fresh = helper.loadModule("Core/Ledger.lua")
    assert.is_false(fresh.Ledger.RecordGold(1, context, 1))
    assert.same({}, fresh.Ledger.GetGold())
  end)
end)
