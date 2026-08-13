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

  it("promotes matching pending evidence only when exact cost arrives", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      quantity = 2, completedAt = 100, character = context.char, region = context.region,
      reason = "exact total unavailable", evidenceKey = "purchase:1" })
    local batch, isNew = record({ evidenceKey = "purchase:1" })
    assert.is_true(isNew)
    assert.equal(200, batch.originalTotal)
    assert.equal(0, #GC.Acquisitions.GetPending())
    assert.equal(pending.id, batch.promotedPendingID)
  end)

  it("never creates a pending duplicate for active purchase evidence", function()
    record({ evidenceKey = "purchase:1" })
    local pending, isNew = GC.Acquisitions.RecordPending({ itemID = 42,
      positionKey = "commodity:42", quantity = 2, completedAt = 100,
      character = context.char, region = context.region,
      reason = "exact total unavailable", evidenceKey = "purchase:1" })
    assert.is_nil(pending)
    assert.is_false(isNew)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
  end)

  it("rejects malformed GoldCap commodity wrappers without throwing", function()
    local ok, batch, isNew = pcall(GC.Acquisitions.RecordGoldCap,
      { isCommodity = true }, { itemID = "not-an-id", quantity = 1, total = 1 }, context, 1, "bad")
    assert.is_true(ok)
    assert.is_nil(batch)
    assert.is_false(isNew)
  end)

  it("rejects invalid exact facts without changing the store", function()
    local max = 9007199254740991
    local cases = {
      { itemID = 0 / 0 }, { quantity = math.huge }, { total = -math.huge },
      { quantity = 1.5 }, { total = -1 }, { quantity = 0 }, { total = 0 },
      { itemID = max + 1 }, { quantity = max + 1 }, { total = max + 1 },
      { source = "guessed" }, { acquiredAt = -1 },
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

  it("keeps maximum-boundary partial allocation and range costs exact", function()
    local max = 9007199254740991
    local batch = record({ quantity = max, total = max, evidenceKey = "max:allocate" })
    local partial = GC.Acquisitions.Allocate({ batch }, max - 1)
    assert.equal(max - 1, partial.knownQty)
    assert.equal(max - 1, partial.knownCost)
    assert.equal(max, batch.remainingQty)
    assert.equal(max, batch.remainingTotal)

    local range = GC.Acquisitions.AllocateRange({ batch }, max - 1, 1)
    assert.equal("COMPLETE", range.coverage)
    assert.equal(1, range.knownQty)
    assert.equal(1, range.knownCost)
  end)

  it("keeps maximum-boundary consumption exact and rejects unsafe aggregate availability atomically", function()
    local max = 9007199254740991
    local batch = record({ quantity = max, total = max, evidenceKey = "max:consume" })
    local consumed = GC.Acquisitions.Consume("commodity:42", max - 1, "sale:max", 1, context)
    assert.equal(max - 1, consumed.cost)
    assert.equal(1, batch.remainingQty)
    assert.equal(1, batch.remainingTotal)
    assert.truthy(GC.Acquisitions.Consume("commodity:42", 1, "sale:last", 2, context))

    local first = record({ quantity = max - 1, total = max, evidenceKey = "max:first" })
    local second = record({ quantity = 1, total = max, evidenceKey = "max:second" })
    assert.is_nil(GC.Acquisitions.Allocate({ first, second }, max))
    assert.is_nil(GC.Acquisitions.Consume("commodity:42", max, "sale:overflow", 3, context))
    assert.equal(max - 1, first.remainingQty)
    assert.equal(max, first.remainingTotal)
    assert.equal(1, second.remainingQty)
    assert.equal(max, second.remainingTotal)
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

  it("migrates one flip and its sniper ledger twin into one goldcap batch", function()
    local flips = { { itemID = 42, qty = 2, paidUnit = 100, paidTotal = 201,
      boughtAt = 500, targetUnit = 180 } }
    local ledger = { { key = "snipe:42", kind = "buy", source = "goldcap_sniper",
      itemID = 42, qty = 2, total = 201, at = 500, char = "A-R", region = "eu" } }

    db.flips, db.ledger = flips, ledger
    GC.Acquisitions.MigrateLegacy(db.flips, db.ledger)
    GC.Acquisitions.MigrateLegacy(flips, ledger)

    local all = GC.Acquisitions.GetAll()
    assert.equal(1, #all)
    assert.equal("goldcap", all[1].source)
    assert.is_true(all[1].evidenceKeys["snipe:42"])
    assert.equal("A-R", all[1].character)
    assert.equal("eu", all[1].region)
    assert.same(flips[1], db.flips[1])
    assert.same(ledger[1], db.ledger[1])
  end)

  it("migrates every valid flip, skips invalid rows, and imports unmatched sniper evidence", function()
    local flips = {
      { itemID = 42, qty = 2, paidTotal = 201, boughtAt = 500, targetUnit = 180 },
      { itemID = 43, qty = 1, paidTotal = 90, boughtAt = 510, targetUnit = 120 },
      { itemID = 0, qty = 1, paidTotal = 1, boughtAt = 1 },
    }
    local ledger = {
      { key = "snipe:42", kind = "buy", source = "goldcap_sniper", itemID = 42,
        qty = 2, total = 201, at = 500 },
      { key = "snipe:44", kind = "buy", source = "goldcap_sniper", itemID = 44,
        qty = 1, total = 75, at = 520 },
    }

    GC.Acquisitions.MigrateLegacy(flips, ledger)
    assert.equal(3, #GC.Acquisitions.GetAll())
    assert.equal(1, db.acquisitionVersion)
    assert.is_true(GC.Acquisitions.HasEvidence("snipe:42"))
    assert.is_true(GC.Acquisitions.HasEvidence("snipe:44"))
  end)

  it("does not re-import flips after migration but does import a later unmatched sniper row", function()
    local flips = { { itemID = 42, qty = 2, paidTotal = 201, boughtAt = 500 } }
    local ledger = {}
    GC.Acquisitions.MigrateLegacy(flips, ledger)
    flips[#flips + 1] = { itemID = 43, qty = 1, paidTotal = 90, boughtAt = 510 }
    ledger[#ledger + 1] = { key = "snipe:44", kind = "buy", source = "goldcap_sniper",
      itemID = 44, qty = 1, total = 75, at = 520 }
    GC.Acquisitions.MigrateLegacy(flips, ledger)

    assert.equal(2, #GC.Acquisitions.GetAll())
    assert.equal(42, GC.Acquisitions.GetAll()[1].itemID)
    assert.equal(44, GC.Acquisitions.GetAll()[2].itemID)
  end)

  it("attaches buyer mail to one compatible active batch without replacing its source", function()
    local goldcap = record({ source = "goldcap", total = 201, acquiredAt = 100,
      evidenceKey = "snipe:42" })
    GC.Acquisitions.ReconcileBuy({ key = "mail:42", kind = "buy", source = "mail",
      itemID = 42, qty = 2, total = 201, at = 200, char = "A-R", region = "eu" })

    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal("goldcap", goldcap.source)
    assert.is_true(goldcap.evidenceKeys["mail:42"])
    assert.equal("mail:42", goldcap.mailEvidenceKey)
  end)

  it("resolves the oldest compatible pending observation before creating a mail batch", function()
    local first = GC.Acquisitions.RecordPending({ itemID = 42, quantity = 2, completedAt = 50,
      character = "A-R", region = "eu", reason = "missing total" })
    GC.Acquisitions.RecordPending({ itemID = 42, quantity = 2, completedAt = 60,
      character = "A-R", region = "eu", reason = "missing total" })

    GC.Acquisitions.ReconcileBuy({ key = "mail:pending", kind = "buy", source = "mail",
      itemID = 42, qty = 2, total = 201, at = 100, char = "A-R", region = "eu" })

    assert.equal("mail:pending", first.mailEvidenceKey)
    assert.equal(0, #GC.Acquisitions.GetAll())
    assert.equal(2, #GC.Acquisitions.GetPending())
  end)

  it("creates one auction-house batch for a repeat mail key and separate batches for distinct keys", function()
    local entry = { key = "mail:one", kind = "buy", source = "mail", itemID = 42,
      qty = 2, total = 201, at = 100, char = "A-R", region = "eu" }
    GC.Acquisitions.ReconcileBuy(entry)
    GC.Acquisitions.ReconcileBuy(entry)
    GC.Acquisitions.ReconcileBuy({ key = "mail:two", kind = "buy", source = "mail", itemID = 42,
      qty = 2, total = 201, at = 101, char = "A-R", region = "eu" })

    assert.equal(2, #GC.Acquisitions.GetAll())
    assert.equal("auction_house", GC.Acquisitions.GetAll()[1].source)
    assert.is_true(GC.Acquisitions.GetAll()[1].evidenceKeys["mail:one"])
    assert.is_true(GC.Acquisitions.GetAll()[2].evidenceKeys["mail:two"])
  end)

  it("only enriches an unowned legacy batch through an exact mail reconciliation", function()
    GC.Acquisitions.MigrateLegacy({ { itemID = 42, qty = 2, paidTotal = 201, boughtAt = 100 } }, {})
    local batch = GC.Acquisitions.GetAll()[1]
    GC.Acquisitions.ReconcileBuy({ key = "mail:wrong", kind = "buy", source = "mail",
      itemID = 42, qty = 1, total = 201, at = 200, char = "A-R", region = "eu" })
    assert.is_nil(batch.character)
    GC.Acquisitions.ReconcileBuy({ key = "mail:right", kind = "buy", source = "mail",
      itemID = 42, qty = 2, total = 201, at = 200, char = "A-R", region = "eu" })
    assert.equal("A-R", batch.character)
    assert.equal("eu", batch.region)
  end)

  it("reconciles an id-less mail only when its item name identifies one candidate", function()
    record({ itemName = "Copper Ore", total = 201, evidenceKey = "first" })
    GC.Acquisitions.ReconcileBuy({ key = "mail:name", kind = "buy", source = "mail",
      itemName = "Copper Ore", qty = 2, total = 201, at = 200, char = "A-R", region = "eu" })
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.is_true(GC.Acquisitions.GetAll()[1].evidenceKeys["mail:name"])

    record({ itemName = "Tin Ore", total = 201, evidenceKey = "second", acquiredAt = 101 })
    record({ itemName = "Tin Ore", total = 201, evidenceKey = "third", acquiredAt = 102 })
    GC.Acquisitions.ReconcileBuy({ key = "mail:ambiguous", kind = "buy", source = "mail",
      itemName = "Tin Ore", qty = 2, total = 201, at = 201, char = "A-R", region = "eu" })
    assert.is_false(GC.Acquisitions.HasEvidence("mail:ambiguous"))
    assert.equal(3, #GC.Acquisitions.GetAll())
  end)
end)
