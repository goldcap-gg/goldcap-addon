local helper = require("spec.spec_helper")

describe("Live observations store", function()
  local GC, db

  local function obs(over)
    local o = { itemID = 42, region = "eu", minUnit = 1000, listings = 3, totalQty = 14,
      levels = { { unitPrice = 1000, quantity = 4 }, { unitPrice = 1200, quantity = 10 } } }
    for k, v in pairs(over or {}) do o[k] = v end
    return o
  end

  before_each(function()
    GC = helper.loadModule("Core/Data.lua")
    db = { liveObservations = {} }
  end)

  it("stores a bounded observation in the wire shape", function()
    assert.is_true(GC.Data.RecordLiveObservation(db, obs(), 5000))
    local row = db.liveObservations[1]
    assert.equal(42, row.itemID)
    assert.equal("eu", row.region)
    assert.equal(5000, row.scannedAt)
    assert.equal(1000, row.minUnit)
    assert.equal(3, row.listings)
    assert.equal(14, row.totalQty)
    -- levels converted {unitPrice,quantity} -> {unit,qty}
    assert.same({ { unit = 1000, qty = 4 }, { unit = 1200, qty = 10 } }, row.levels)
  end)

  it("newest scan wins per item — one row per itemID", function()
    GC.Data.RecordLiveObservation(db, obs({ minUnit = 1000 }), 5000)
    GC.Data.RecordLiveObservation(db, obs({ minUnit = 900 }), 5100)
    assert.equal(1, #db.liveObservations)
    assert.equal(900, db.liveObservations[1].minUnit)
    assert.equal(5100, db.liveObservations[1].scannedAt)
  end)

  it("levels are truncated to five", function()
    local levels = {}
    for i = 1, 9 do levels[i] = { unitPrice = 100 * i, quantity = i } end
    GC.Data.RecordLiveObservation(db, obs({ levels = levels }), 5000)
    assert.equal(5, #db.liveObservations[1].levels)
  end)

  it("caps the table at 200 items by evicting the oldest scan", function()
    for i = 1, 200 do
      GC.Data.RecordLiveObservation(db, obs({ itemID = i }), 1000 + i)
    end
    GC.Data.RecordLiveObservation(db, obs({ itemID = 999 }), 9000)
    assert.equal(200, #db.liveObservations)
    local seen = {}
    for _, row in ipairs(db.liveObservations) do seen[row.itemID] = true end
    assert.is_nil(seen[1])       -- oldest evicted
    assert.is_true(seen[999])
  end)

  it("prunes rows older than a day on write", function()
    GC.Data.RecordLiveObservation(db, obs({ itemID = 1 }), 1000)
    GC.Data.RecordLiveObservation(db, obs({ itemID = 2 }), 1000 + GC.Data.LIVE_OBSERVATION_MAX_AGE + 1)
    local seen = {}
    for _, row in ipairs(db.liveObservations) do seen[row.itemID] = true end
    assert.is_nil(seen[1])
    assert.is_true(seen[2])
  end)

  it("rejects malformed input without touching the table", function()
    assert.is_nil(GC.Data.RecordLiveObservation(db, obs({ minUnit = 0 }), 5000))
    assert.is_nil(GC.Data.RecordLiveObservation(db, obs({ minUnit = 10.5 }), 5000))
    -- obs({ itemID = nil }) can't express "omit itemID": Lua table constructors never
    -- materialize a key whose value is nil, so pairs() never sees it to override anything,
    -- and the call would be indistinguishable from obs() (a fully valid observation). Build
    -- the itemID-missing case directly instead.
    assert.is_nil(GC.Data.RecordLiveObservation(db, { region = "eu", minUnit = 1000 }, 5000))
    assert.is_nil(GC.Data.RecordLiveObservation(db, obs({ region = "xx" }), 5000))
    assert.is_nil(GC.Data.RecordLiveObservation(db, obs(), nil))
    assert.equal(0, #db.liveObservations)
    -- listings/totalQty/levels are optional: a floor alone is a valid observation
    assert.is_true(GC.Data.RecordLiveObservation(db,
      { itemID = 7, region = "us", minUnit = 500 }, 5000))
  end)

  it("tolerates a missing or corrupt liveObservations table", function()
    assert.is_nil(GC.Data.RecordLiveObservation({ liveObservations = "corrupt" }, obs(), 5000))
    local fresh = {}
    assert.is_true(GC.Data.RecordLiveObservation(fresh, obs(), 5000))
    assert.equal(1, #fresh.liveObservations)
  end)
end)
