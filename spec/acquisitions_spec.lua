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

  it("promotes an unknown pending quantity when exact mail evidence arrives", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 42, completedAt = 100,
      character = context.char, region = context.region, reason = "quantity unavailable",
      evidenceKey = "purchase:unknown-quantity" })
    assert.truthy(pending)
    assert.is_nil(pending.quantity)
    assert.equal(0, #GC.Acquisitions.GetActive(context))

    local entry = { key = "mail:unknown-quantity", kind = "buy", source = "mail",
      itemID = 42, qty = 2, total = 201, at = 200, char = context.char, region = context.region }
    GC.Acquisitions.ReconcileBuy(entry)
    GC.Acquisitions.ReconcileBuy(entry)

    local promoted = GC.Acquisitions.GetAll()[1]
    assert.equal("mail:unknown-quantity", promoted.mailEvidenceKey)
    assert.equal(pending.id, promoted.promotedPendingID)
    assert.equal(2, promoted.originalQty)
    assert.equal(201, promoted.originalTotal)
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

  it("removes a manual batch by id", function()
    local batch = record({ source = "manual", evidenceKey = "manual:remove" })
    assert.is_truthy(GC.Acquisitions.RemoveManual(batch.id))
    assert.equal(0, #GC.Acquisitions.GetAll())
  end)

  it("refuses to remove a goldcap batch", function()
    local batch = record({ source = "goldcap", evidenceKey = "goldcap:remove" })
    assert.is_falsy(GC.Acquisitions.RemoveManual(batch.id))
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("refuses an unknown id", function()
    assert.is_falsy(GC.Acquisitions.RemoveManual("acq:999"))
  end)

  it("is idempotent -- a second removal of the same id is falsy", function()
    local batch = record({ source = "manual", evidenceKey = "manual:remove2" })
    assert.is_truthy(GC.Acquisitions.RemoveManual(batch.id))
    assert.is_falsy(GC.Acquisitions.RemoveManual(batch.id))
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

  it("promotes the oldest compatible pending observation before creating another mail batch", function()
    local first = GC.Acquisitions.RecordPending({ itemID = 42, quantity = 2, completedAt = 50,
      character = "A-R", region = "eu", reason = "missing total" })
    GC.Acquisitions.RecordPending({ itemID = 42, quantity = 2, completedAt = 60,
      character = "A-R", region = "eu", reason = "missing total" })

    GC.Acquisitions.ReconcileBuy({ key = "mail:pending", kind = "buy", source = "mail",
      itemID = 42, qty = 2, total = 201, at = 100, char = "A-R", region = "eu" })

    assert.equal(first.id, GC.Acquisitions.GetAll()[1].promotedPendingID)
    assert.equal("mail:pending", GC.Acquisitions.GetAll()[1].mailEvidenceKey)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(1, #GC.Acquisitions.GetPending())
  end)

  it("[FINAL C2] atomically promotes exact buyer mail into one active batch", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = nil, quantity = 2, completedAt = 50, character = context.char,
      region = context.region, reason = "missing total", evidenceKey = "capture:pending" })
    local entry = { key = "mail:promote", kind = "buy", source = "mail", itemID = 42,
      itemName = "Ironclaw Ore", qty = 2, total = 201, at = 100,
      char = context.char, region = context.region }

    local promoted, isNew = GC.Acquisitions.ReconcileBuy(entry)
    assert.is_true(isNew)
    assert.equal(0, #GC.Acquisitions.GetPending())
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal("auction_house", promoted.source)
    assert.equal(pending.id, promoted.promotedPendingID)
    assert.equal("commodity:42", promoted.positionKey)
    assert.equal("Ironclaw Ore", promoted.itemName)
    assert.equal(50, promoted.acquiredAt)
    assert.equal(2, promoted.originalQty)
    assert.equal(201, promoted.originalTotal)
    assert.is_true(promoted.evidenceKeys["capture:pending"])
    assert.is_true(promoted.evidenceKeys["mail:promote"])
    assert.equal("mail:promote", promoted.mailEvidenceKey)

    local repeated, repeatedNew = GC.Acquisitions.ReconcileBuy(entry)
    assert.equal(promoted, repeated)
    assert.is_false(repeatedNew)
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[FINAL C2] promotes legacy mail-linked pending rows and keeps invalid promotion atomic", function()
    local legacy = GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      quantity = 2, completedAt = 50, character = context.char, region = context.region,
      reason = "missing total", evidenceKey = "capture:legacy" })
    legacy.mailEvidenceKey = "mail:legacy"
    legacy.evidenceKeys["mail:legacy"] = true

    local promoted = GC.Acquisitions.ReconcileBuy({ key = "mail:legacy", kind = "buy", source = "mail",
      itemID = 42, itemName = "Ironclaw Ore", qty = 2, total = 201, at = 100,
      char = context.char, region = context.region })
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending())
    assert.equal(legacy.id, promoted.promotedPendingID)

    local invalid = GC.Acquisitions.RecordPending({ itemID = 43, positionKey = "commodity:43",
      quantity = 1, completedAt = 60, character = context.char, region = context.region,
      reason = "missing total", evidenceKey = "capture:invalid" })
    assert.is_nil(GC.Acquisitions.ReconcileBuy({ key = "mail:invalid", kind = "buy", source = "mail",
      itemID = 43, itemName = "Bad", qty = 1, total = 0, at = 101,
      char = context.char, region = context.region }))
    assert.equal(invalid, GC.Acquisitions.GetPending()[1])
    assert.equal(1, #GC.Acquisitions.GetAll())
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

  it("creates a new mail batch when an identical older batch is exhausted", function()
    local exhausted = record({ total = 201, evidenceKey = "old:buy" })
    assert.truthy(GC.Acquisitions.Consume("commodity:42", 2, "sale:old", 101, context))
    assert.equal(0, exhausted.remainingQty)
    assert.equal(0, exhausted.remainingTotal)

    GC.Acquisitions.ReconcileBuy({ key = "mail:new", kind = "buy", source = "mail",
      itemID = 42, qty = 2, total = 201, at = 200, char = "A-R", region = "eu" })

    assert.equal(2, #GC.Acquisitions.GetAll())
    assert.is_nil(exhausted.evidenceKeys["mail:new"])
    assert.is_true(GC.Acquisitions.GetAll()[2].evidenceKeys["mail:new"])
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

  it("enriches a matching active batch name but never promotes a different scope", function()
    local active = record({ itemName = nil, total = 201, evidenceKey = "capture:active" })
    GC.Acquisitions.ReconcileBuy({ key = "mail:active", kind = "buy", source = "mail",
      itemID = 42, itemName = "Copper Ore", qty = 2, total = 201, at = 200,
      char = context.char, region = context.region })
    assert.equal("Copper Ore", active.itemName)
    assert.is_true(active.evidenceKeys["mail:active"])

    local pending = GC.Acquisitions.RecordPending({ itemID = 43, positionKey = "commodity:43",
      quantity = 1, completedAt = 50, character = context.char, region = context.region,
      reason = "missing total", evidenceKey = "capture:scoped" })
    GC.Acquisitions.ReconcileBuy({ key = "mail:unscoped", kind = "buy", source = "mail",
      itemID = 43, itemName = "Tin Ore", qty = 1, total = 90, at = 200 })
    assert.equal(pending, GC.Acquisitions.GetPending()[1])
    assert.is_false(GC.Acquisitions.HasEvidence("mail:unscoped"))

    GC.Acquisitions.ReconcileBuy({ key = "mail:other-scope", kind = "buy", source = "mail",
      itemID = 43, itemName = "Tin Ore", qty = 1, total = 90, at = 201,
      char = "B-R", region = "us" })
    assert.equal(pending, GC.Acquisitions.GetPending()[1])
    assert.equal(1, #GC.Acquisitions.GetActive({ char = context.char, region = context.region }))
    assert.equal(1, #GC.Acquisitions.GetActive({ char = "B-R", region = "us" }))
  end)

  it("keeps id-less buyer mail unresolved even when its name has one candidate", function()
    record({ itemName = "Copper Ore", total = 201, evidenceKey = "first" })
    GC.Acquisitions.ReconcileBuy({ key = "mail:name", kind = "buy", source = "mail",
      itemName = "Copper Ore", qty = 2, total = 201, at = 200, char = "A-R", region = "eu" })
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.is_nil(GC.Acquisitions.GetAll()[1].evidenceKeys["mail:name"])

    record({ itemName = "Tin Ore", total = 201, evidenceKey = "second", acquiredAt = 101 })
    record({ itemName = "Tin Ore", total = 201, evidenceKey = "third", acquiredAt = 102 })
    GC.Acquisitions.ReconcileBuy({ key = "mail:ambiguous", kind = "buy", source = "mail",
      itemName = "Tin Ore", qty = 2, total = 201, at = 201, char = "A-R", region = "eu" })
    assert.is_false(GC.Acquisitions.HasEvidence("mail:ambiguous"))
    assert.equal(3, #GC.Acquisitions.GetAll())
  end)

  it("assigns one paid sale to its single scoped position and consumes FIFO once", function()
    local first = record({ itemName = "Ironclaw Ore", quantity = 10, total = 1000, evidenceKey = "buy:1" })
    local second = record({ itemName = "Ironclaw Ore", quantity = 10, total = 1000,
      acquiredAt = 101, evidenceKey = "buy:2" })
    GC.Acquisitions.RecordPost("commodity:42", 42, "Ironclaw Ore", context.char, context.region, 20, 150)
    local sale = { key = "sale:1", kind = "sale", source = "mail", itemName = "Ironclaw Ore",
      qty = 5, total = 1000, at = 200, char = context.char, region = context.region, pending = false }

    local applied = GC.Acquisitions.ReconcileSale(sale)
    assert.same({ status = "applied", positionKey = "commodity:42", quantity = 5,
      cost = 500, proceeds = 1000, profit = 500 }, applied)
    assert.equal(5, first.remainingQty)
    assert.equal(10, second.remainingQty)
    assert.is_true(first.consumedEvidenceKeys["sale:1"])
    assert.equal("duplicate", GC.Acquisitions.ReconcileSale(sale).status)
    assert.equal(1, #GC.Acquisitions.GetRealized(context))
  end)

  it("does not mistake same-name batches in separate positions for one sale candidate", function()
    record({ itemID = 1, positionKey = "item:1:0:0:0", itemName = "Shared Name", evidenceKey = "buy:1" })
    record({ itemID = 2, positionKey = "item:2:0:0:0", itemName = "Shared Name", evidenceKey = "buy:2" })
    GC.Acquisitions.RecordPost("item:1:0:0:0", 1, "Shared Name", context.char, context.region, 2, 100)
    GC.Acquisitions.RecordPost("item:2:0:0:0", 2, "Shared Name", context.char, context.region, 2, 100)

    local result = GC.Acquisitions.ReconcileSale({ key = "sale:ambiguous", kind = "sale", source = "mail",
      itemName = "Shared Name", qty = 1, total = 100, at = 200,
      char = context.char, region = context.region, pending = false })
    assert.equal("unresolved", result.status)
    assert.equal("ambiguous_name", result.reason)
  end)

  it("requires observed scoped activity at or before an exact-character paid sale", function()
    local batch = record({ itemName = "Ironclaw Ore", quantity = 2, total = 200 })
    local sale = { key = "sale:early", kind = "sale", source = "mail", itemName = "Ironclaw Ore",
      qty = 1, total = 100, at = 200, char = context.char, region = context.region, pending = false }
    assert.equal("unresolved", GC.Acquisitions.ReconcileSale(sale).status)
    GC.Acquisitions.ObserveOwnedPosition("commodity:42", 42, "Ironclaw Ore", context.char, context.region, 300)
    assert.equal("unresolved", GC.Acquisitions.ReconcileSale(sale).status)
    sale.key, sale.at, sale.char = "sale:wrong-character", 400, "B-R"
    assert.equal("unresolved", GC.Acquisitions.ReconcileSale(sale).status)
    assert.equal(2, batch.remainingQty)
  end)

  it("never consumes on disappearance and rejects insufficient sales atomically", function()
    local batch = record({ itemName = "Ironclaw Ore", quantity = 2, total = 201 })
    GC.Acquisitions.ObserveOwnedPosition("commodity:42", 42, "Ironclaw Ore", context.char, context.region, 100)
    local sale = { key = "sale:too-many", kind = "sale", source = "mail", itemName = "Ironclaw Ore",
      qty = 3, total = 300, at = 200, char = context.char, region = context.region, pending = false }
    assert.equal("unresolved", GC.Acquisitions.ReconcileSale(sale).status)
    assert.equal(2, batch.remainingQty)
    assert.equal(201, batch.remainingTotal)
    assert.equal(0, #GC.Acquisitions.GetRealized(context))
  end)

  it("keeps active batches beyond fourteen days without inferring a sale", function()
    record({ itemName = "Ironclaw Ore", acquiredAt = 0 })
    assert.equal(1, #GC.Acquisitions.GetActive(context))
  end)

  it("[FINAL C3] selects one activity position then consumes all of its batches regardless of cached names", function()
    local unnamed = record({ itemName = nil, quantity = 1, total = 1000,
      evidenceKey = "buy:other", acquiredAt = 1 })
    local named = record({ itemName = "Ironclaw Ore", quantity = 1, total = 100,
      evidenceKey = "buy:named", acquiredAt = 2 })
    GC.Acquisitions.ObserveOwnedPosition("commodity:42", 42, "Ironclaw Ore", context.char, context.region, 10)

    local result = GC.Acquisitions.ReconcileSale({ key = "sale:exact-set", kind = "sale", source = "mail",
      itemName = "Ironclaw Ore", qty = 1, total = 500, at = 20,
      char = context.char, region = context.region, pending = false })

    assert.same({ status = "applied", positionKey = "commodity:42", quantity = 1,
      cost = 1000, proceeds = 500, profit = -500 }, result)
    assert.equal(0, unnamed.remainingQty)
    assert.equal(0, unnamed.remainingTotal)
    assert.equal(1, named.remainingQty)
    assert.equal(100, named.remainingTotal)
    assert.equal("duplicate", GC.Acquisitions.ReconcileSale({ key = "sale:exact-set", kind = "sale",
      source = "mail", itemName = "Ironclaw Ore", qty = 1, total = 500, at = 20,
      char = context.char, region = context.region, pending = false }).status)
  end)

  it("fails closed when persisted activity item identity disagrees with its position", function()
    local batch = record({ itemName = nil, quantity = 1, total = 100,
      evidenceKey = "buy:activity-corrupt" })
    local scopeKey = GC.Acquisitions.ScopeKey("commodity:42", context)
    db.acquisitionActivity[scopeKey] = { scopeKey = scopeKey, positionKey = "commodity:42",
      itemID = 99, itemName = "Ironclaw Ore", character = context.char,
      region = context.region, firstSeenAt = 10 }

    local result = GC.Acquisitions.ReconcileSale({ key = "sale:activity-corrupt",
      kind = "sale", source = "mail", itemName = "Ironclaw Ore", qty = 1,
      total = 200, at = 20, char = context.char, region = context.region, pending = false })
    assert.equal("unresolved", result.status)
    assert.equal(1, batch.remainingQty)
    assert.equal(0, #GC.Acquisitions.GetRealized(context))
  end)

  it("[WAVE2 I1] repairs one full pending purchase into one exact manual batch without doubled exposure", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 2, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable", evidenceKey = "capture:repair-full" })
    local repair = GC.Acquisitions.RepairPendingManual
    assert.equal("function", type(repair))
    if type(repair) ~= "function" then return end
    local args = { pendingID = pending.id, repairID = "manual-repair:full", itemID = 42,
      positionKey = "commodity:42", itemName = "Copper Ore", quantity = 2, total = 201,
      acquiredAt = 200, character = context.char, region = context.region }

    local batch, isNew = repair(args)
    assert.is_true(isNew)
    assert.equal("manual", batch.source)
    assert.equal(pending.id, batch.repairedPendingID)
    assert.equal(2, batch.originalQty)
    assert.is_true(batch.evidenceKeys[args.repairID])
    assert.equal(0, #GC.Acquisitions.GetPending(context))
    assert.equal(1, #GC.Acquisitions.GetActive(context))
    assert.equal(2, GC.Acquisitions.GetActive(context)[1].remainingQty)

    local repeated, repeatedNew = repair(args)
    assert.equal(batch, repeated)
    assert.is_false(repeatedNew)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending(context))
  end)

  it("[WAVE2 I1] partially repairs only the exact pending row and rejects invalid or scope-drifted repair", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable", evidenceKey = "capture:repair-partial" })
    local repair = GC.Acquisitions.RepairPendingManual
    assert.equal("function", type(repair))
    if type(repair) ~= "function" then return end
    local partial = repair({ pendingID = pending.id, repairID = "manual-repair:partial", itemID = 42,
      positionKey = "commodity:42", itemName = "Copper Ore", quantity = 2, total = 200,
      acquiredAt = 200, character = context.char, region = context.region })
    assert.truthy(partial)
    assert.equal(2, partial.originalQty)
    assert.equal(3, GC.Acquisitions.GetPending(context)[1].quantity)
    assert.equal(1, #GC.Acquisitions.GetAll())

    assert.is_nil(repair({ pendingID = pending.id, repairID = "manual-repair:invalid", itemID = 42,
      positionKey = "commodity:42", itemName = "Copper Ore", quantity = 4, total = 400,
      acquiredAt = 201, character = context.char, region = context.region }))
    assert.is_nil(repair({ pendingID = pending.id, repairID = "manual-repair:drift", itemID = 42,
      positionKey = "commodity:42", itemName = "Copper Ore", quantity = 1, total = 100,
      acquiredAt = 202, character = "B-R", region = "us" }))
    assert.equal(3, GC.Acquisitions.GetPending(context)[1].quantity)
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[WAVE2 I1] durably binds one item-only batch to one scoped variant before its later exact sale", function()
    local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 42, positionKey = nil,
      itemName = "Copper Ore", quantity = 1, total = 100, acquiredAt = 100,
      evidenceKey = "legacy:item-only", character = context.char, region = context.region })
    local positionKey = "item:42:10:0:0"
    GC.Acquisitions.ObserveOwnedPosition(positionKey, 42, "Copper Ore", context.char, context.region, 10)
    local bind = GC.Acquisitions.BindItemOnly
    assert.equal("function", type(bind))
    if type(bind) ~= "function" then return end
    local bound, isNew = bind(batch.id, {
      { positionKey = positionKey, itemID = 42, character = context.char, region = context.region },
    }, context)
    assert.is_true(isNew)
    assert.equal(positionKey, bound.positionKey)
    assert.equal(positionKey, GC.Acquisitions.GetActive(context)[1].positionKey)

    local sale = GC.Acquisitions.ReconcileSale({ key = "sale:bound-item-only", kind = "sale", source = "mail",
      itemName = "Copper Ore", qty = 1, total = 150, at = 20, char = context.char,
      region = context.region, pending = false })
    assert.equal("applied", sale.status)
    assert.equal(positionKey, sale.positionKey)
    assert.equal(0, batch.remainingQty)
  end)

  it("[WAVE2 I1] never binds item-only evidence across variants or scopes and leaves its sale unresolved", function()
    local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 42, positionKey = nil,
      itemName = "Copper Ore", quantity = 1, total = 100, acquiredAt = 100,
      evidenceKey = "legacy:ambiguous-item-only", character = context.char, region = context.region })
    local first, second = "item:42:10:0:0", "item:42:20:0:0"
    GC.Acquisitions.ObserveOwnedPosition(first, 42, "Copper Ore", context.char, context.region, 10)
    GC.Acquisitions.ObserveOwnedPosition(second, 42, "Copper Ore", context.char, context.region, 10)
    local bind = GC.Acquisitions.BindItemOnly
    assert.equal("function", type(bind))
    if type(bind) ~= "function" then return end
    assert.is_nil(bind(batch.id, {
      { positionKey = first, itemID = 42, character = context.char, region = context.region },
      { positionKey = second, itemID = 42, character = context.char, region = context.region },
    }, context))
    assert.is_nil(batch.positionKey)
    local sale = GC.Acquisitions.ReconcileSale({ key = "sale:ambiguous-item-only", kind = "sale", source = "mail",
      itemName = "Copper Ore", qty = 1, total = 150, at = 20, char = context.char,
      region = context.region, pending = false })
    assert.equal("unresolved", sale.status)
    assert.equal("no_position", sale.reason)
    assert.equal(1, batch.remainingQty)

    local crossScope = GC.Acquisitions.Record({ source = "auction_house", itemID = 43, positionKey = nil,
      itemName = "Tin Ore", quantity = 1, total = 100, acquiredAt = 101,
      evidenceKey = "legacy:cross-scope-item-only", character = context.char, region = context.region })
    assert.is_nil(bind(crossScope.id, {
      { positionKey = "item:43:10:0:0", itemID = 43, character = "B-R", region = "us" },
    }, context))
    assert.is_nil(crossScope.positionKey)
  end)

  it("[WAVE2 I1 regression] refuses to bind a retired item-only batch", function()
    local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 42, positionKey = nil,
      itemName = "Copper Ore", quantity = 1, total = 100, acquiredAt = 100,
      evidenceKey = "legacy:retired-item-only", character = context.char, region = context.region })
    local positionKey = "item:42:10:0:0"
    GC.Acquisitions.ObserveOwnedPosition(positionKey, 42, "Copper Ore", context.char, context.region, 10)
    batch.remainingQty, batch.remainingTotal = 0, 0

    assert.is_nil(GC.Acquisitions.BindItemOnly(batch.id, {
      { positionKey = positionKey, itemID = 42, character = context.char, region = context.region },
    }, context))
    assert.is_nil(batch.positionKey)
  end)

  it("[WAVE2 I1 regression] refuses a malformed item-variant identity", function()
    local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 42, positionKey = nil,
      itemName = "Copper Ore", quantity = 1, total = 100, acquiredAt = 100,
      evidenceKey = "legacy:malformed-item-only", character = context.char, region = context.region })
    local malformed = "item:42:not-a-level:0:0"
    GC.Acquisitions.ObserveOwnedPosition(malformed, 42, "Copper Ore", context.char, context.region, 10)

    assert.is_nil(GC.Acquisitions.BindItemOnly(batch.id, {
      { positionKey = malformed, itemID = 42, character = context.char, region = context.region },
    }, context))
    assert.is_nil(batch.positionKey)
  end)

  it("[FINAL I1] reconciles exact buyer mail after a partial repair without duplicate exposure", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable", evidenceKey = "capture:partial" })
    local repaired = assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id,
      repairID = "repair:partial", itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 2, total = 200, acquiredAt = 101,
      character = context.char, region = context.region }))
    local entry = { key = "mail:partial", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102,
      char = context.char, region = context.region }

    -- Simulate an upgrade from the earlier manual-repair format, which had
    -- repair batches and a reduced pending row but no durable group map.
    db.acquisitionRepairGroups = nil
    GC.Acquisitions.Init(db)
    local residual, isNew = GC.Acquisitions.ReconcileBuy(entry)
    assert.is_true(isNew)
    assert.equal(0, #GC.Acquisitions.GetPending(context))
    assert.equal(2, #GC.Acquisitions.GetAll())
    assert.equal(5, GC.Acquisitions.GetActive(context)[1].remainingQty
      + GC.Acquisitions.GetActive(context)[2].remainingQty)
    assert.equal(5, repaired.originalQty + residual.originalQty)
    assert.equal(500, repaired.originalTotal + residual.originalTotal)
    assert.is_true(residual.evidenceKeys[entry.key])

    local repeated, repeatedNew = GC.Acquisitions.ReconcileBuy(entry)
    assert.equal(residual, repeated)
    assert.is_false(repeatedNew)
    assert.equal(2, #GC.Acquisitions.GetAll())
  end)

  it("[FINAL I1] retains a full repair group and rejects inconsistent or corrupt buyer mail", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable", evidenceKey = "capture:full" })
    local repaired = assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id,
      repairID = "repair:full", itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, total = 500, acquiredAt = 101,
      character = context.char, region = context.region }))
    GC.Acquisitions.Init(db)
    assert.is_table(db.acquisitionRepairGroups)
    if type(db.acquisitionRepairGroups) ~= "table" then return end
    assert.is_table(db.acquisitionRepairGroups[pending.id])
    if type(db.acquisitionRepairGroups[pending.id]) ~= "table" then return end

    local entry = { key = "mail:full", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102,
      char = context.char, region = context.region }
    local matched, isNew = GC.Acquisitions.ReconcileBuy(entry)
    assert.equal(repaired, matched)
    assert.is_false(isNew)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.is_true(db.acquisitionRepairGroups[pending.id].mailEvidenceKeys[entry.key])

    db = {}
    GC.Acquisitions.Init(db)
    pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable" }))
    assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = "repair:inconsistent",
      itemID = 42, positionKey = "commodity:42", itemName = "Copper Ore", quantity = 5,
      total = 400, acquiredAt = 101, character = context.char, region = context.region }))
    assert.is_nil(GC.Acquisitions.ReconcileBuy({ key = "mail:inconsistent", kind = "buy", source = "mail",
      itemID = 42, itemName = "Copper Ore", qty = 5, total = 500, at = 102,
      char = context.char, region = context.region }))
    assert.equal(1, #GC.Acquisitions.GetAll())

    db.acquisitionRepairGroups[pending.id].repairedQty = 6
    assert.is_nil(GC.Acquisitions.ReconcileBuy({ key = "mail:corrupt", kind = "buy", source = "mail",
      itemID = 42, itemName = "Copper Ore", qty = 5, total = 400, at = 103,
      char = context.char, region = context.region }))
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[FINAL I1] rejects a repair when its pending or request position belongs to another item", function()
    local pending = GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:99",
      itemName = "Copper Ore", quantity = 1, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable" })
    local repaired, isNew = GC.Acquisitions.RepairPendingManual({ pendingID = pending.id,
      repairID = "repair:wrong-position", itemID = 42, positionKey = "commodity:99",
      itemName = "Copper Ore", quantity = 1, total = 100, acquiredAt = 101,
      character = context.char, region = context.region })

    assert.is_nil(repaired)
    assert.is_false(isNew)
    assert.equal(1, #GC.Acquisitions.GetPending(context))
    assert.equal(0, #GC.Acquisitions.GetAll())
  end)

  it("[FINAL I1] fails closed without mutation when an activity entry is not a table", function()
    local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 42, positionKey = nil,
      itemName = "Copper Ore", quantity = 1, total = 100, acquiredAt = 100,
      evidenceKey = "legacy:bad-activity", character = context.char, region = context.region })
    db.acquisitionActivity[GC.Acquisitions.ScopeKey("item:42:10:0:0", context)] = true

    local ok, bound, isNew = pcall(GC.Acquisitions.BindItemOnly, batch.id, {
      { positionKey = "item:42:10:0:0", itemID = 42, character = context.char, region = context.region },
    }, context)
    assert.is_true(ok)
    assert.is_nil(bound)
    assert.is_false(isNew)
    assert.is_nil(batch.positionKey)
  end)

  it("[FINAL I1] fails closed for wrong activity keys or scope keys and leaves sale unresolved", function()
    local function assertRejectedActivity(activityKey, activity)
      db = {}
      GC.Acquisitions.Init(db)
      local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 42, positionKey = nil,
        itemName = "Copper Ore", quantity = 1, total = 100, acquiredAt = 100,
        evidenceKey = activityKey, character = context.char, region = context.region })
      db.acquisitionActivity[activityKey] = activity

      local bound, isNew = GC.Acquisitions.BindItemOnly(batch.id, {
        { positionKey = "item:42:10:0:0", itemID = 42, character = context.char, region = context.region },
      }, context)
      assert.is_nil(bound)
      assert.is_false(isNew)
      assert.is_nil(batch.positionKey)
      local sale = GC.Acquisitions.ReconcileSale({ key = "sale:" .. activityKey, kind = "sale", source = "mail",
        itemName = "Copper Ore", qty = 1, total = 150, at = 20, char = context.char,
        region = context.region, pending = false })
      assert.equal("unresolved", sale.status)
      assert.equal(1, batch.remainingQty)
    end

    local expectedScope = GC.Acquisitions.ScopeKey("item:42:10:0:0", context)
    local activity = { scopeKey = expectedScope, positionKey = "item:42:10:0:0", itemID = 42,
      itemName = "Copper Ore", character = context.char, region = context.region, firstSeenAt = 10 }
    assertRejectedActivity("wrong-map-key", activity)
    activity.scopeKey = "wrong-scope-key"
    assertRejectedActivity(expectedScope, activity)
  end)

  it("[FINAL I1] binds one valid activity store and consumes its later sale exactly once", function()
    local batch = GC.Acquisitions.Record({ source = "auction_house", itemID = 42, positionKey = nil,
      itemName = "Copper Ore", quantity = 1, total = 100, acquiredAt = 100,
      evidenceKey = "legacy:valid-activity", character = context.char, region = context.region })
    local positionKey = "item:42:10:0:0"
    assert.truthy(GC.Acquisitions.ObserveOwnedPosition(positionKey, 42, "Copper Ore", context.char,
      context.region, 10))

    local bound, isNew = GC.Acquisitions.BindItemOnly(batch.id, {
      { positionKey = positionKey, itemID = 42, character = context.char, region = context.region },
    }, context)
    assert.equal(batch, bound)
    assert.is_true(isNew)
    local entry = { key = "sale:valid-activity", kind = "sale", source = "mail", itemName = "Copper Ore",
      qty = 1, total = 150, at = 20, char = context.char, region = context.region, pending = false }
    assert.equal("applied", GC.Acquisitions.ReconcileSale(entry).status)
    assert.equal(0, batch.remainingQty)
    assert.equal(1, #GC.Acquisitions.GetRealized(context))
    assert.equal("duplicate", GC.Acquisitions.ReconcileSale(entry).status)
    assert.equal(1, #GC.Acquisitions.GetRealized(context))
  end)

  it("[FINAL I1 C1] blocks quantity or name mismatches against an unresolved repair group", function()
    local function repairPartial(key)
      db = {}
      GC.Acquisitions.Init(db)
      local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
        itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
        region = context.region, reason = "exact total unavailable", evidenceKey = key }))
      assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = key .. ":repair",
        itemID = 42, positionKey = "commodity:42", itemName = "Copper Ore", quantity = 2,
        total = 200, acquiredAt = 101, character = context.char, region = context.region }))
    end

    repairPartial("capture:c1-quantity")
    local blocked, isNew = GC.Acquisitions.ReconcileBuy({ key = "mail:c1-quantity", kind = "buy",
      source = "mail", itemID = 42, itemName = "Copper Ore", qty = 4, total = 400, at = 102,
      char = context.char, region = context.region })
    assert.is_nil(blocked)
    assert.is_false(isNew)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(1, #GC.Acquisitions.GetPending(context))

    repairPartial("capture:c1-name")
    blocked, isNew = GC.Acquisitions.ReconcileBuy({ key = "mail:c1-name", kind = "buy", source = "mail",
      itemID = 42, itemName = "Tin Ore", qty = 5, total = 500, at = 102,
      char = context.char, region = context.region })
    assert.is_nil(blocked)
    assert.is_false(isNew)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(1, #GC.Acquisitions.GetPending(context))
  end)

  it("[FINAL I1 C2] treats every valid repair-group evidence key as globally authoritative", function()
    local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable", evidenceKey = "capture:c2" }))
    assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = "repair:c2",
      itemID = 42, positionKey = "commodity:42", itemName = "Copper Ore", quantity = 5,
      total = 500, acquiredAt = 101, character = context.char, region = context.region }))

    assert.is_true(GC.Acquisitions.HasEvidence("capture:c2"))
    assert.is_true(GC.Acquisitions.HasEvidence("repair:c2"))
    local replayed, isNew = GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable", evidenceKey = "capture:c2" })
    assert.is_nil(replayed)
    assert.is_false(isNew)
    assert.is_nil(GC.Acquisitions.Record({ source = "manual", itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 1, total = 100, acquiredAt = 102,
      character = context.char, region = context.region, evidenceKey = "capture:c2" }))

    assert(GC.Acquisitions.ReconcileBuy({ key = "mail:c2", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 103, char = context.char,
      region = context.region }))
    assert.is_true(GC.Acquisitions.HasEvidence("mail:c2"))
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(0, #GC.Acquisitions.GetPending(context))
  end)

  it("[FINAL I1 C3] rejects incomplete repair evidence, mismatched completion evidence, and ungrouped repair batches", function()
    local function repairPartial(key)
      db = {}
      GC.Acquisitions.Init(db)
      local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
        itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
        region = context.region, reason = "exact total unavailable", evidenceKey = key }))
      local batch = assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id,
        repairID = key .. ":repair", itemID = 42, positionKey = "commodity:42",
        itemName = "Copper Ore", quantity = 2, total = 200, acquiredAt = 101,
        character = context.char, region = context.region }))
      return pending, batch
    end
    local function mail(key)
      return { key = key, kind = "buy", source = "mail", itemID = 42, itemName = "Copper Ore",
        qty = 5, total = 500, at = 102, char = context.char, region = context.region }
    end

    local _, repaired = repairPartial("capture:c3-batch")
    repaired.evidenceKeys["capture:c3-batch:repair"] = nil
    assert.is_nil(GC.Acquisitions.ReconcileBuy(mail("mail:c3-batch")))
    assert.equal(1, #GC.Acquisitions.GetAll())

    local pending = repairPartial("capture:c3-completion")
    pending.evidenceKeys["capture:c3-extra"] = true
    assert.is_nil(GC.Acquisitions.ReconcileBuy(mail("mail:c3-completion")))
    assert.equal(1, #GC.Acquisitions.GetAll())

    pending = repairPartial("capture:c3-ungrouped")
    local extra = assert(GC.Acquisitions.Record({ source = "manual", itemID = 42,
      positionKey = "commodity:42", itemName = "Copper Ore", quantity = 1, total = 100,
      acquiredAt = 102, character = context.char, region = context.region,
      evidenceKey = "repair:c3-ungrouped" }))
    extra.repairedPendingID, extra.repairEvidenceKey = pending.id, "repair:c3-ungrouped"
    assert.is_nil(GC.Acquisitions.ReconcileBuy(mail("mail:c3-ungrouped")))
    assert.equal(2, #GC.Acquisitions.GetAll())
  end)

  it("[FINAL I1 I1] leaves a legacy repair with no pending identity fail-closed", function()
    local repaired = assert(GC.Acquisitions.Record({ source = "manual", itemID = 42,
      positionKey = "commodity:42", itemName = "Copper Ore", quantity = 2, total = 200,
      acquiredAt = 100, character = context.char, region = context.region,
      evidenceKey = "repair:i1-legacy" }))
    repaired.repairedPendingID, repaired.repairEvidenceKey = "pending:legacy", "repair:i1-legacy"
    db.acquisitionRepairGroups = nil
    GC.Acquisitions.Init(db)

    local matched, isNew = GC.Acquisitions.ReconcileBuy({ key = "mail:i1-legacy", kind = "buy", source = "mail",
      itemID = 42, itemName = "Copper Ore", qty = 5, total = 500, at = 101,
      char = context.char, region = context.region })
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[FINAL I1 I2] permits a distinct same-shape buyer mail after a repair group is absorbed", function()
    local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable" }))
    assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = "repair:i2",
      itemID = 42, positionKey = "commodity:42", itemName = "Copper Ore", quantity = 5,
      total = 500, acquiredAt = 101, character = context.char, region = context.region }))
    local first = { key = "mail:i2-first", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102, char = context.char,
      region = context.region }
    assert(GC.Acquisitions.ReconcileBuy(first))

    local second, isNew = GC.Acquisitions.ReconcileBuy({ key = "mail:i2-second", kind = "buy", source = "mail",
      itemID = 42, itemName = "Copper Ore", qty = 5, total = 500, at = 103,
      char = context.char, region = context.region })
    assert.is_true(isNew)
    assert.equal("auction_house", second.source)
    assert.equal(2, #GC.Acquisitions.GetAll())
    assert.equal(10, GC.Acquisitions.GetActive(context)[1].remainingQty
      + GC.Acquisitions.GetActive(context)[2].remainingQty)
  end)

  it("[FINAL I1 I3] validates group-owned mail before returning its linked active batch", function()
    local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable" }))
    assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = "repair:i3",
      itemID = 42, positionKey = "commodity:42", itemName = "Copper Ore", quantity = 5,
      total = 500, acquiredAt = 101, character = context.char, region = context.region }))
    local entry = { key = "mail:i3", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102, char = context.char,
      region = context.region }
    assert(GC.Acquisitions.ReconcileBuy(entry))

    local changed = { key = entry.key, kind = entry.kind, source = entry.source, itemID = entry.itemID,
      itemName = entry.itemName, qty = entry.qty, total = 501, at = entry.at,
      char = entry.char, region = entry.region }
    local matched, isNew = GC.Acquisitions.ReconcileBuy(changed)
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.equal(1, #GC.Acquisitions.GetAll())

    db.acquisitionRepairGroups[pending.id].repairedQty = 6
    assert.is_nil(GC.Acquisitions.ReconcileBuy(entry))
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[FINAL I1 R2 C1] blocks a full repair group when its buyer-mail key already has an active or pending owner", function()
    local function fullRepair(key)
      db = {}
      GC.Acquisitions.Init(db)
      local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
        itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
        region = context.region, reason = "exact total unavailable" }))
      local repair = assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = key .. ":repair",
        itemID = 42, positionKey = "commodity:42", itemName = "Copper Ore", quantity = 5,
        total = 500, acquiredAt = 101, character = context.char, region = context.region }))
      return pending, repair
    end
    local function entry(key)
      return { key = key, kind = "buy", source = "mail", itemID = 42, itemName = "Copper Ore",
        qty = 5, total = 500, at = 102, char = context.char, region = context.region }
    end

    local pending, repair = fullRepair("mail:r2-active")
    local active = assert(GC.Acquisitions.Record({ source = "manual", itemID = 43,
      positionKey = "commodity:43", itemName = "Tin Ore", quantity = 1, total = 100,
      acquiredAt = 101, character = context.char, region = context.region, evidenceKey = "mail:r2-active" }))
    local matched, isNew = GC.Acquisitions.ReconcileBuy(entry("mail:r2-active"))
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.is_true(active.evidenceKeys["mail:r2-active"])
    assert.is_nil(repair.evidenceKeys["mail:r2-active"])
    assert.is_nil(db.acquisitionRepairGroups[pending.id].mailEvidenceKeys["mail:r2-active"])
    assert.equal(2, #GC.Acquisitions.GetAll())

    repair = select(2, fullRepair("mail:r2-pending"))
    local otherPending = assert(GC.Acquisitions.RecordPending({ itemID = 43, positionKey = "commodity:43",
      itemName = "Tin Ore", quantity = 1, completedAt = 101, character = context.char,
      region = context.region, reason = "exact total unavailable", evidenceKey = "mail:r2-pending" }))
    matched, isNew = GC.Acquisitions.ReconcileBuy(entry("mail:r2-pending"))
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.is_true(otherPending.evidenceKeys["mail:r2-pending"])
    assert.is_nil(repair.evidenceKeys["mail:r2-pending"])
    assert.equal(1, #GC.Acquisitions.GetPending(context))
    assert.equal(1, otherPending.quantity)
  end)

  it("[FINAL I1 R2 C2] blocks replay of a completion key claimed by a corrupt repair group", function()
    local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable", evidenceKey = "capture:r2-corrupt" }))
    assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = "repair:r2-corrupt",
      itemID = 42, positionKey = "commodity:42", itemName = "Copper Ore", quantity = 5,
      total = 500, acquiredAt = 101, character = context.char, region = context.region }))
    db.acquisitionRepairGroups[pending.id].repairedQty = 6

    local ok, replayed, isNew = pcall(GC.Acquisitions.RecordPending, { itemID = 42,
      positionKey = "commodity:42", itemName = "Copper Ore", quantity = 5, completedAt = 100,
      character = context.char, region = context.region, reason = "exact total unavailable",
      evidenceKey = "capture:r2-corrupt" })
    assert.is_true(ok)
    assert.is_nil(replayed)
    assert.is_false(isNew)
    assert.is_true(GC.Acquisitions.HasEvidence("capture:r2-corrupt"))
    assert.equal(0, #GC.Acquisitions.GetPending(context))
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[FINAL I1 R2 I1] excludes resolved repair allocations from generic buyer-mail matching", function()
    local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 2, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable" }))
    assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = "repair:r2-resolved",
      itemID = 42, positionKey = "commodity:42", itemName = "Copper Ore", quantity = 1,
      total = 100, acquiredAt = 101, character = context.char, region = context.region }))
    assert(GC.Acquisitions.ReconcileBuy({ key = "mail:r2-resolve", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 2, total = 200, at = 102, char = context.char,
      region = context.region }))

    local second, isNew = GC.Acquisitions.ReconcileBuy({ key = "mail:r2-distinct", kind = "buy", source = "mail",
      itemID = 42, itemName = "Copper Ore", qty = 1, total = 100, at = 103,
      char = context.char, region = context.region })
    assert.is_true(isNew)
    assert.equal("auction_house", second.source)
    assert.equal(3, #GC.Acquisitions.GetAll())
    assert.equal(3, GC.Acquisitions.GetActive(context)[1].remainingQty
      + GC.Acquisitions.GetActive(context)[2].remainingQty
      + GC.Acquisitions.GetActive(context)[3].remainingQty)
  end)

  it("[FINAL I1 R2 I2] refuses grouped pending mail markers and preserves a corrupt pre-existing marker", function()
    local function partialRepair(key)
      db = {}
      GC.Acquisitions.Init(db)
      local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
        itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
        region = context.region, reason = "exact total unavailable" }))
      assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = key .. ":repair",
        itemID = 42, positionKey = "commodity:42", itemName = "Copper Ore", quantity = 2,
        total = 200, acquiredAt = 101, character = context.char, region = context.region }))
      return pending
    end
    local function buyer(key)
      return { key = key, kind = "buy", source = "mail", itemID = 42, itemName = "Copper Ore",
        qty = 5, total = 500, at = 102, char = context.char, region = context.region }
    end

    local pending = partialRepair("mail:r2-resolve")
    local marked, isNew = GC.Acquisitions.ResolvePending(pending.id, "mail:r2-marker")
    assert.is_nil(marked)
    assert.is_false(isNew)
    assert.is_nil(pending.mailEvidenceKey)
    assert.equal(3, pending.quantity)

    pending = partialRepair("mail:r2-corrupt-marker")
    pending.mailEvidenceKey = "mail:r2-old-marker"
    local matched
    matched, isNew = GC.Acquisitions.ReconcileBuy(buyer("mail:r2-corrupt-marker"))
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.equal("mail:r2-old-marker", pending.mailEvidenceKey)
    assert.equal(3, pending.quantity)
    assert.equal(1, #GC.Acquisitions.GetPending(context))
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[FINAL I1 R2 I3] rejects a full group whose stored mail total differs from repaired cost", function()
    local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable" }))
    local repair = assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id, repairID = "repair:r2-total",
      itemID = 42, positionKey = "commodity:42", itemName = "Copper Ore", quantity = 5,
      total = 500, acquiredAt = 101, character = context.char, region = context.region }))
    local entry = { key = "mail:r2-total", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102, char = context.char,
      region = context.region }
    assert(GC.Acquisitions.ReconcileBuy(entry))
    db.acquisitionRepairGroups[pending.id].mailEvidence[entry.key].total = 400

    local changed = { key = entry.key, kind = entry.kind, source = entry.source, itemID = entry.itemID,
      itemName = entry.itemName, qty = entry.qty, total = 400, at = entry.at,
      char = entry.char, region = entry.region }
    local matched, isNew = GC.Acquisitions.ReconcileBuy(changed)
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.equal(5, repair.remainingQty)
    assert.equal(1, #GC.Acquisitions.GetAll())
  end)

  it("[WAVE3 I1 fix3] blocks an orphan repairedPendingID marker from generic buyer-mail fallback", function()
    local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable" }))
    local repair = assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id,
      repairID = "repair:fix3-pending", itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, total = 500, acquiredAt = 101,
      character = context.char, region = context.region }))
    repair.repairEvidenceKey = nil
    db.acquisitionRepairGroups[pending.id] = nil

    local entry = { key = "mail:fix3-pending", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102, char = context.char,
      region = context.region }
    local ok, matched, isNew = pcall(GC.Acquisitions.ReconcileBuy, entry)
    assert.is_true(ok)
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(5, GC.Acquisitions.GetAll()[1].remainingQty)
    assert.is_nil(repair.mailEvidenceKey)
    assert.is_nil(repair.evidenceKeys[entry.key])
    assert.is_false(GC.Acquisitions.HasEvidence(entry.key))
  end)

  it("[WAVE3 I1 fix3] blocks an orphan repairEvidenceKey marker from generic buyer-mail fallback", function()
    local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable" }))
    local repair = assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id,
      repairID = "repair:fix3-evidence", itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, total = 500, acquiredAt = 101,
      character = context.char, region = context.region }))
    repair.repairedPendingID = nil
    db.acquisitionRepairGroups[pending.id] = nil

    local entry = { key = "mail:fix3-evidence", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102, char = context.char,
      region = context.region }
    local ok, matched, isNew = pcall(GC.Acquisitions.ReconcileBuy, entry)
    assert.is_true(ok)
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.equal(1, #GC.Acquisitions.GetAll())
    assert.equal(5, GC.Acquisitions.GetAll()[1].remainingQty)
    assert.is_nil(repair.mailEvidenceKey)
    assert.is_nil(repair.evidenceKeys[entry.key])
    assert.is_false(GC.Acquisitions.HasEvidence(entry.key))
  end)

  it("[WAVE3 I1 fix4] blocks a sparse index-2 repairedPendingID orphan before buyer-mail fallback", function()
    local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable" }))
    local repair = assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id,
      repairID = "repair:fix4-sparse", itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, total = 500, acquiredAt = 101,
      character = context.char, region = context.region }))
    repair.repairEvidenceKey = nil
    db.acquisitionRepairGroups[pending.id] = nil
    db.acquisitions[2] = repair
    db.acquisitions[1] = nil
    local sequenceBefore = db.acquisitionSeq

    local entry = { key = "mail:fix4-sparse", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102,
      char = context.char, region = context.region }
    local ok, matched, isNew = pcall(GC.Acquisitions.ReconcileBuy, entry)
    assert.is_true(ok)
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.equal(sequenceBefore, db.acquisitionSeq)
    assert.is_nil(db.acquisitions[1])
    assert.equal(repair, db.acquisitions[2])
    assert.is_nil(repair.mailEvidenceKey)
    assert.is_nil(repair.evidenceKeys[entry.key])
    assert.is_false(GC.Acquisitions.HasEvidence(entry.key))
  end)

  it("[WAVE3 I1 fix4] blocks a dictionary repairEvidenceKey orphan before buyer-mail fallback", function()
    local pending = assert(GC.Acquisitions.RecordPending({ itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, completedAt = 100, character = context.char,
      region = context.region, reason = "exact total unavailable" }))
    local repair = assert(GC.Acquisitions.RepairPendingManual({ pendingID = pending.id,
      repairID = "repair:fix4-dictionary", itemID = 42, positionKey = "commodity:42",
      itemName = "Copper Ore", quantity = 5, total = 500, acquiredAt = 101,
      character = context.char, region = context.region }))
    repair.repairedPendingID = nil
    db.acquisitionRepairGroups[pending.id] = nil
    db.acquisitions["dictionary-orphan"] = repair
    db.acquisitions[1] = nil
    local sequenceBefore = db.acquisitionSeq

    local entry = { key = "mail:fix4-dictionary", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102,
      char = context.char, region = context.region }
    local ok, matched, isNew = pcall(GC.Acquisitions.ReconcileBuy, entry)
    assert.is_true(ok)
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.equal(sequenceBefore, db.acquisitionSeq)
    assert.is_nil(db.acquisitions[1])
    assert.equal(repair, db.acquisitions["dictionary-orphan"])
    assert.is_nil(repair.mailEvidenceKey)
    assert.is_nil(repair.evidenceKeys[entry.key])
    assert.is_false(GC.Acquisitions.HasEvidence(entry.key))
  end)

  it("[WAVE3 I1 fix4] rejects a dense non-table acquisition without throwing or accounting mutation", function()
    db.acquisitions[1] = true
    local entry = { key = "mail:fix4-non-table", kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102,
      char = context.char, region = context.region }

    local ok, matched, isNew = pcall(GC.Acquisitions.ReconcileBuy, entry)
    assert.is_true(ok)
    assert.is_nil(matched)
    assert.is_false(isNew)
    assert.is_true(db.acquisitions[1])
    assert.equal(0, db.acquisitionSeq)
    assert.equal(0, #db.acquisitionPending)
    assert.equal(0, #db.acquisitionRealized)
    assert.is_nil(next(db.acquisitionConsumptionEvidence))
  end)

  local function assertMalformedStartupFailsClosed(acquisitions, mailKey)
    local loaded = helper.loadModule("Core/Acquisitions.lua")
    local database = { acquisitions = acquisitions }
    local originalAcquisitions = database.acquisitions

    local initOK = pcall(loaded.Acquisitions.Init, database)
    assert.is_true(initOK)
    assert.equal(originalAcquisitions, database.acquisitions)
    local databaseFieldCount = 0
    for _ in pairs(database) do databaseFieldCount = databaseFieldCount + 1 end
    assert.equal(1, databaseFieldCount)
    assert.is_nil(database.acquisitionPending)
    assert.is_nil(database.acquisitionRealized)
    assert.is_nil(database.acquisitionActivity)
    assert.is_nil(database.acquisitionConsumptionEvidence)
    assert.is_nil(database.acquisitionRepairGroups)
    assert.is_nil(database.acquisitionSeq)
    assert.is_nil(database.acquisitionPendingSeq)
    assert.is_nil(database.acquisitionVersion)
    for _, row in pairs(acquisitions) do
      if type(row) == "table" then
        assert.is_nil(row.evidenceKeys)
        assert.is_nil(row.consumedEvidenceKeys)
      end
    end

    local reconcileOK, matched, isNew = pcall(loaded.Acquisitions.ReconcileBuy, {
      key = mailKey, kind = "buy", source = "mail", itemID = 42,
      itemName = "Copper Ore", qty = 5, total = 500, at = 102,
      char = "A-R", region = "eu",
    })
    assert.is_true(reconcileOK)
    assert.is_nil(matched)
    assert.is_false(isNew)
  end

  it("[WAVE3 I1 fix5] fails closed at startup for a dense non-table acquisition row", function()
    assertMalformedStartupFailsClosed({ true }, "mail:fix5-non-table")
  end)

  it("[WAVE3 I1 fix5] fails closed at startup for a sparse acquisition store", function()
    assertMalformedStartupFailsClosed({ [2] = {
      id = "acq:2", repairedPendingID = "pending:fix5-sparse",
    } }, "mail:fix5-sparse")
  end)

  it("[WAVE3 I1 fix5] fails closed at startup for a dictionary acquisition store", function()
    assertMalformedStartupFailsClosed({ ["dictionary-orphan"] = {
      id = "acq:2", repairEvidenceKey = "repair:fix5-dictionary",
    } }, "mail:fix5-dictionary")
  end)
end)
