local helper = require("spec.spec_helper")

describe("Acquisition store", function()
  local GC, db, context

  local function record(overrides)
    local fields = {
      source = "auction_house", itemID = 42, positionKey = "commodity:42",
      quantity = 2, total = 200, acquiredAt = 100, evidenceKey = "tx:1",
      character = context.char, region = context.region,
    }
    for key, value in pairs(overrides or {}) do fields[key] = value end
    return GC.Acquisitions.Record(fields)
  end

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua")
    db = {}
    context = { char = "A-R", region = "eu" }
    GC.Acquisitions.Init(db)
  end)

  it("records exact non-divisible total and source", function()
    local batch, isNew = record({ total = 201 })
    assert.is_true(isNew)
    assert.equal(201, batch.originalTotal)
    assert.equal(201, batch.remainingTotal)
    assert.equal("auction_house", batch.source)
  end)

  it("deduplicates one evidence key but keeps distinct identical buys", function()
    local first = record()
    local duplicate, isNew = record()
    local second = record({ evidenceKey = "tx:2" })
    assert.equal(first.id, duplicate.id)
    assert.is_false(isNew)
    assert.not_equal(first.id, second.id)
  end)

  it("rejects invalid exact facts without changing the store", function()
    local max = 9007199254740991
    local cases = {
      { itemID = 0 / 0 }, { quantity = math.huge }, { total = -math.huge },
      { quantity = 1.5 }, { total = -1 }, { quantity = 0 }, { total = 0 },
      { itemID = max + 1 }, { source = "guessed" }, { acquiredAt = -1 },
    }
    for _, overrides in ipairs(cases) do
      local ok, batch = pcall(record, overrides)
      assert.is_true(ok)
      assert.is_nil(batch)
      assert.equal(0, #GC.Acquisitions.GetAll())
    end
  end)

  it("conserves copper across partial FIFO consumption", function()
    record({ source = "manual", quantity = 3, total = 100, acquiredAt = 1,
      evidenceKey = "manual:1" })
    local consumed = GC.Acquisitions.Consume("commodity:42", 1, "sale:1", 2, context)
    assert.equal(33, consumed.cost)
    assert.equal(2, GC.Acquisitions.GetActive(context)[1].remainingQty)
    assert.equal(67, GC.Acquisitions.GetActive(context)[1].remainingTotal)
    assert.equal(67, GC.Acquisitions.Consume("commodity:42", 2, "sale:2", 3, context).cost)
  end)

  it("rejects overspending and repeated sale evidence atomically", function()
    record({ quantity = 2, total = 201 })
    assert.is_nil(GC.Acquisitions.Consume("commodity:42", 3, "sale:1", 1, context))
    assert.equal(2, GC.Acquisitions.GetActive(context)[1].remainingQty)
    assert.equal(201, GC.Acquisitions.GetActive(context)[1].remainingTotal)
    assert.truthy(GC.Acquisitions.Consume("commodity:42", 1, "sale:1", 2, context))
    assert.is_nil(GC.Acquisitions.Consume("commodity:42", 1, "sale:1", 3, context))
    assert.equal(1, GC.Acquisitions.GetActive(context)[1].remainingQty)
  end)

  it("allocates a new listing only after the quantity already listed", function()
    record({ source = "goldcap", quantity = 2, total = 101, acquiredAt = 1,
      evidenceKey = "buy:1" })
    record({ quantity = 2, total = 400, acquiredAt = 2, evidenceKey = "buy:2" })
    local range = GC.Acquisitions.AllocateRange(GC.Acquisitions.GetActive(context), 2, 1)
    assert.equal("COMPLETE", range.coverage)
    assert.equal(200, range.knownCost)
    assert.equal("acq:2", range.allocations[1].batchID)
  end)

  it("rejects invalid range offsets and keeps allocation pure", function()
    local batch = record({ quantity = 3, total = 100 })
    local active = GC.Acquisitions.GetActive(context)
    for _, values in ipairs({ { -1, 1 }, { 0, 0 }, { 1.5, 1 }, { 0, math.huge } }) do
      assert.is_nil(GC.Acquisitions.AllocateRange(active, values[1], values[2]))
    end
    local allocation = GC.Acquisitions.Allocate(active, 1)
    assert.equal(33, allocation.knownCost)
    assert.equal(3, batch.remainingQty)
    assert.equal(100, batch.remainingTotal)
  end)

  it("scopes otherwise identical batches to their owning character", function()
    record({ quantity = 2, total = 200, evidenceKey = "a" })
    record({ quantity = 2, total = 400, evidenceKey = "b", character = "B-R" })
    local a = GC.Acquisitions.GetActive(context)
    local bContext = { char = "B-R", region = "eu" }
    assert.equal(1, #a)
    assert.equal(200, a[1].remainingTotal)
    assert.equal(1, #GC.Acquisitions.GetActive(bContext))
    assert.equal(100, GC.Acquisitions.Consume("commodity:42", 1, "sale:a", 1, context).cost)
    assert.equal(400, GC.Acquisitions.GetActive(bContext)[1].remainingTotal)
  end)

  it("excludes an unowned legacy batch from automatic active cost", function()
    local batch = GC.Acquisitions.Record({
      source = "auction_house", itemID = 42, positionKey = "commodity:42",
      quantity = 2, total = 200, acquiredAt = 100, evidenceKey = "legacy:1",
    })
    assert.truthy(batch)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetActive(context))
    assert.equal(0, #GC.Acquisitions.GetActive({ char = "B-R", region = "eu" }))
  end)

  it("keeps unresolved observations out of allocation", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      quantity = 2, completedAt = 100, character = context.char, region = context.region,
      reason = "exact total unavailable" })
    assert.truthy(pending)
    assert.equal(1, #GC.Acquisitions.GetPending())
    local allocation = GC.Acquisitions.Allocate(GC.Acquisitions.GetActive(context), 1)
    assert.equal("MISSING", allocation.coverage)
    assert.equal(0, allocation.knownQty)
  end)
end)
