local helper = require("spec.spec_helper")

describe("Sell positions", function()
  local GC
  local context = { char = "A-R", region = "eu" }

  local function batch(id, source, qty, total, at, char, region, itemID, positionKey)
    return { id = id, source = source, itemID = itemID or 42, positionKey = positionKey or "commodity:42",
      remainingQty = qty, remainingTotal = total, acquiredAt = at,
      character = char or context.char, region = region or context.region }
  end

  local function lot(positionKey, quantity, unitPrice, auctionID, firstSeenAt)
    return { itemID = 42, positionKey = positionKey or "commodity:42", quantity = quantity,
      unitPrice = unitPrice, auctionID = auctionID, firstSeenAt = firstSeenAt or 1 }
  end

  local function build(args)
    args = args or {}
    args.acquisitions = args.acquisitions or {}
    args.ownedLots = args.ownedLots or {}
    args.quotes = args.quotes or {}
    args.statsByItemID = args.statsByItemID or {}
    args.context = args.context or context
    args.now = args.now or 10
    return GC.SellPositions.Build(args)
  end

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua")
    GC = helper.loadModule("Core/Flips.lua", GC)
    GC = helper.loadModule("Core/QuoteCache.lua", GC)
    GC = helper.loadModule("Core/SellPositions.lua", GC)
  end)

  it("normalizes every owned auction into an independently priced position lot", function()
    local lots = GC.SellPositions.NormalizeOwnedLots({
      { itemKey = { itemID = 42 }, isCommodity = true, quantity = 2, unitPrice = 90, auctionID = 2 },
      { itemKey = { itemID = 42 }, isCommodity = true, quantity = 3, unitPrice = 120, auctionID = 3 },
    }, 77)
    assert.same({
      { positionKey = "commodity:42", itemID = 42, quantity = 2, unitPrice = 90,
        auctionID = 2, firstSeenAt = 77, isCommodity = true },
      { positionKey = "commodity:42", itemID = 42, quantity = 3, unitPrice = 120,
        auctionID = 3, firstSeenAt = 77, isCommodity = true },
    }, lots)
  end)

  it("does not attach accounting state to a caller-owned auction lot", function()
    local ownedLot = lot("commodity:42", 1, 200, 1)
    build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) }, ownedLots = { ownedLot } })
    assert.is_nil(ownedLot.allocation)
  end)

  it("groups mixed-source batches and counts one owned lot once", function()
    local positions = build({
      acquisitions = {
        batch("acq:1", "goldcap", 100, 1000, 1),
        batch("acq:2", "auction_house", 50, 600, 2),
      },
      ownedLots = { lot("commodity:42", 120, 20, 9001) },
    })
    assert.equal(1, #positions)
    assert.same({ auction_house = 50, goldcap = 100 }, positions[1].sources)
    assert.equal(120, positions[1].listedQty)
    assert.equal(120, positions[1].knownQty)
    assert.equal(1240, positions[1].knownCost)
    assert.equal("COMPLETE", positions[1].coverage)
  end)

  it("does not double project one listing across two purchase batches", function()
    local p = build({ acquisitions = {
      batch("acq:1", "goldcap", 100, 1000, 1), batch("acq:2", "auction_house", 50, 600, 2),
    }, ownedLots = { lot("commodity:42", 120, 20, 9001) } })[1]
    assert.equal(2280, p.projectedNet)
    assert.equal(1040, p.profit)
  end)

  it("renders partial cost without fabricated profit", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 100, 1000, 1) },
      ownedLots = { lot("commodity:42", 150, 20, 9001) } })[1]
    assert.equal("PARTIAL", p.coverage)
    assert.equal(100, p.knownQty)
    assert.equal(150, p.exposureQty)
    assert.is_nil(p.profit)
  end)

  it("[FINAL I2] applies the auction cut once to aggregate multi-lot gross", function()
    local tiny = build({ acquisitions = { batch("acq:1", "goldcap", 2, 1, 1) },
      ownedLots = { lot("commodity:42", 1, 1, 1), lot("commodity:42", 1, 1, 2) } })[1]
    assert.equal(1, tiny.projectedNet)

    local normal = build({ acquisitions = { batch("acq:2", "goldcap", 5, 100, 1) },
      ownedLots = { lot("commodity:42", 2, 101, 1), lot("commodity:42", 3, 202, 2) } })[1]
    assert.equal(math.floor((2 * 101 + 3 * 202) * 95 / 100), normal.projectedNet)

    local max = 9007199254740991
    local overflow = build({ acquisitions = { batch("acq:max", "goldcap", 2, 2, 1) },
      ownedLots = { lot("commodity:42", 1, max, 1), lot("commodity:42", 1, 1, 2) } })[1]
    assert.is_nil(overflow.projectedNet)
    assert.is_nil(overflow.profit)
  end)

  it("[FINAL I1] keeps pending and unresolved evidence visible without inventing a position", function()
    local active = batch("acq:1", "goldcap", 1, 100, 1)
    active.itemName = "Sold Ore"
    local soldPending = build({ acquisitions = { active }, activities = {
      { scopeKey = "eu\1A-R\1commodity:42", positionKey = "commodity:42", itemID = 42,
        itemName = "Sold Ore", character = "A-R", region = "eu", firstSeenAt = 1 },
    }, sellerEvidence = {
      { key = "sale:pending", kind = "sale", source = "mail", itemName = "Sold Ore",
        qty = 1, total = 150, at = 5, char = "A-R", region = "eu", pending = true },
    } })
    assert.equal(1, #soldPending)
    assert.equal("SOLD_PENDING", soldPending[1].status)
    assert.is_true(soldPending[1].facts.soldPending)
    assert.equal(1, soldPending[1].trackedQty)

    local unassigned = batch("acq:item-only", "auction_house", 1, 75, 1, nil, nil, 77)
    unassigned.positionKey = nil
    local unresolved = build({ acquisitions = { unassigned }, pendingAcquisitions = {
      { id = "pending:1", itemID = 88, quantity = 2, completedAt = 2,
        character = "A-R", region = "eu", reason = "missing identity" },
    }, activities = {
      { scopeKey = "eu\1A-R\1item:1:0:0:0", positionKey = "item:1:0:0:0", itemID = 1,
        itemName = "Shared", character = "A-R", region = "eu", firstSeenAt = 1 },
      { scopeKey = "eu\1A-R\1item:2:0:0:0", positionKey = "item:2:0:0:0", itemID = 2,
        itemName = "Shared", character = "A-R", region = "eu", firstSeenAt = 1 },
    }, sellerEvidence = {
      { key = "sale:paid-unresolved", kind = "sale", source = "mail", itemName = "No Activity",
        qty = 1, total = 100, at = 5, char = "A-R", region = "eu", pending = false },
      { key = "sale:ambiguous", kind = "sale", source = "mail", itemName = "Shared",
        qty = 1, total = 100, at = 5, char = "A-R", region = "eu", pending = false },
    } })
    local kinds = {}
    for _, position in ipairs(unresolved) do
      assert.is_nil(position.positionKey)
      assert.is_true(position.unresolved)
      assert.is_false(position.protectedAction)
      kinds[position.unresolvedKind] = (kinds[position.unresolvedKind] or 0) + 1
      assert.is_nil(GC.SellPositions.BuildPostPlan(position, { itemID = position.itemID, exactQty = 1 }, 100))
      assert.is_nil(GC.SellPositions.BuildRepostPlan(position, 1, 100))
    end
    assert.equal(1, kinds.pending_purchase)
    assert.equal(1, kinds.unassigned_acquisition)
    assert.equal(1, kinds.paid_sale)
    assert.equal(1, kinds.ambiguous_sale)

    local resolvable = batch("acq:item-only", "auction_house", 1, 75, 1, nil, nil, 77)
    resolvable.positionKey = nil
    local resolved = build({ acquisitions = { resolvable }, ownedLots = {
      { itemID = 77, positionKey = "item:77:10:0:0", quantity = 1,
        unitPrice = 100, auctionID = 9, firstSeenAt = 1 },
    } })
    assert.equal(1, #resolved)
    assert.equal("item:77:10:0:0", resolved[1].positionKey)
    assert.equal(75, resolved[1].knownCost)
  end)

  it("keeps same-item variants and per-lot listing prices separate", function()
    local variants = build({ acquisitions = {
      batch("acq:1", "goldcap", 1, 100, 1, nil, nil, 42, "item:42:10:0:0"),
      batch("acq:2", "goldcap", 1, 200, 2, nil, nil, 42, "item:42:20:0:0"),
    }, ownedLots = {
      lot("item:42:10:0:0", 1, 300, 1), lot("item:42:20:0:0", 1, 400, 2),
    } })
    assert.equal(2, #variants)
    assert.equal(300, variants[1].listedValue)
    assert.equal(400, variants[2].listedValue)
  end)

  it("uses an item-only batch only when one compatible variant exists", function()
    local itemOnly = batch("acq:1", "manual", 1, 100, 1)
    itemOnly.positionKey = nil
    local one = build({ acquisitions = { itemOnly },
      ownedLots = { lot("item:42:10:0:0", 1, 200, 1) } })[1]
    assert.equal(100, one.knownCost)
    local ambiguous = batch("acq:1", "manual", 1, 100, 1)
    ambiguous.positionKey = nil
    local many = build({ acquisitions = { ambiguous },
      ownedLots = { lot("item:42:10:0:0", 1, 200, 1), lot("item:42:20:0:0", 1, 200, 2) } })
    assert.equal("UNKNOWN", many[1].coverage)
    assert.equal("UNKNOWN", many[2].coverage)
  end)

  it("uses a stale quote only for display and a fresh quote to cap each listed lot", function()
    local stale = build({ acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
      ownedLots = { lot("commodity:42", 1, 300, 1), lot("commodity:42", 1, 200, 2) },
      quotes = { [42] = { unit = 100, at = 0 } }, now = 11 })[1]
    assert.equal(100, stale.displayMarketUnit)
    assert.is_nil(stale.freshMarketUnit)
    assert.equal(11, stale.quoteAge)
    assert.equal(475, stale.projectedNet)
    local fresh = build({ acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
      ownedLots = { lot("commodity:42", 1, 300, 1), lot("commodity:42", 1, 200, 2) },
      quotes = { [42] = { unit = 100, at = 9 } } })[1]
    assert.equal(190, fresh.projectedNet)
  end)

  it("does not call a position undercut when its cheapest listed lot is still competitive", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
      ownedLots = { lot("commodity:42", 1, 300, 1), lot("commodity:42", 1, 80, 2) },
      quotes = { [42] = { unit = 100, at = 9 } } })[1]
    assert.equal("LISTED", p.status)
  end)

  it("requires a fresh quote before projecting an unlisted position", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      quotes = { [42] = { unit = 200, at = 0 } }, now = 11 })[1]
    assert.is_nil(p.projectedNet)
    assert.is_nil(p.profit)
  end)

  it("carries measured outlook and a pure recommendation rather than a status label", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
      ownedLots = { lot("commodity:42", 2, 200, 1) },
      quotes = { [42] = { unit = 150, at = 9, levels = { { unitPrice = 100, quantity = 3 } } } },
      statsByItemID = { [42] = { sold = 4 } } })[1]
    assert.equal(3, p.ahead)
    assert.equal(4, p.soldPerDay)
    assert.equal("repost", p.recommendation.action)
    assert.equal(149, p.recommendation.rec.unit)
    assert.equal(106, p.recommendation.rec.breakeven)
  end)

  it("carries a direct RecommendPost decision for unlisted exact stock and no fallback without a quote", function()
    local advised = build({ acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
      quotes = { [42] = { unit = 150, at = 9, levels = { { unitPrice = 150, quantity = 3 } } } },
      statsByItemID = { [42] = { sold = 5 } } })[1]
    assert.equal(149, advised.recommendation.unit)
    assert.equal("undercut", advised.recommendation.mode)
    assert.equal(106, advised.recommendation.breakeven)
    assert.equal(5, advised.soldPerDay)
    local noQuote = build({ acquisitions = { batch("acq:2", "goldcap", 1, 100, 1) } })[1]
    assert.is_nil(noQuote.recommendation)
  end)

  it("keeps every batch and owned lot alongside bounded queue facts", function()
    local p = build({ acquisitions = {
      batch("acq:1", "goldcap", 1, 100, 1), batch("acq:2", "manual", 2, 400, 2),
    }, ownedLots = { lot("commodity:42", 1, 180, 11, 1), lot("commodity:42", 2, 220, 12, 2) },
      quotes = { [42] = { unit = 150, at = 9, levels = { { unitPrice = 120, quantity = 3 }, { unitPrice = 180, quantity = 4 } } } },
      statsByItemID = { [42] = { sold = 2 } } })[1]
    assert.equal(2, #p.batches)
    assert.equal(2, #p.ownedLots)
    assert.equal(3, p.ahead)
    assert.equal(2, p.soldPerDay)
    assert.equal(3, p.outlook.days)
    assert.equal(11, p.ownedLots[1].auctionID)
    assert.equal(12, p.ownedLots[2].auctionID)
    assert.equal("hold", p.recommendation.action)
    assert.equal("loss", p.recommendation.reason)
  end)

  it("never authorizes stale display data for post or repost plans", function()
    local unlisted = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      quotes = { [42] = { unit = 200, at = 0 } }, now = 11 })[1]
    local listed = build({ acquisitions = { batch("acq:2", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 1, 200, 1) },
      quotes = { [42] = { unit = 150, at = 0 } }, now = 11 })[1]

    assert.equal(200, unlisted.displayMarketUnit)
    assert.is_nil(unlisted.freshMarketUnit)
    assert.is_nil(unlisted.projectedNet)
    assert.is_nil(GC.SellPositions.BuildPostPlan(unlisted, { itemID = 42, exactQty = 1 },
      { unit = unlisted.displayMarketUnit, at = 0 }))
    assert.equal(150, listed.displayMarketUnit)
    assert.is_nil(listed.freshMarketUnit)
    assert.equal(190, listed.projectedNet)
    assert.is_nil(GC.SellPositions.BuildRepostPlan(listed, 1,
      { unit = listed.displayMarketUnit, at = 0 }))
  end)

  it("never treats a contradictory fresh-marked stale display quote as fresh", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 1, 200, 1) },
      quotes = { [42] = { unit = 150, at = 9, fresh = true, stale = true } } })[1]
    assert.equal(150, p.displayMarketUnit)
    assert.is_nil(p.freshMarketUnit)
    assert.equal(190, p.projectedNet)
  end)

  it("makes no cost outrank an undercut listing", function()
    local p = build({ ownedLots = { lot("commodity:42", 1, 200, 1) },
      quotes = { [42] = { unit = 100, at = 9 } } })[1]
    assert.equal("NO_COST", p.status)
  end)

  it("scopes positions and summaries to exactly one character and region", function()
    local legacy = batch("acq:legacy", "manual", 1, 1, 3)
    legacy.character, legacy.region = nil, nil
    local acquisitions = {
      batch("acq:a", "goldcap", 1, 100, 1, "A-R", "eu"),
      batch("acq:b", "auction_house", 1, 900, 2, "B-R", "eu"),
      legacy,
    }
    local p = build({ acquisitions = acquisitions, ownedLots = { lot("commodity:42", 1, 200, 1) } })[1]
    assert.same({ goldcap = 1 }, p.sources)
    assert.equal(100, p.knownCost)
    assert.equal(90, p.profit)
    local repost = GC.SellPositions.BuildRepostPlan(p, 1, 150)
    assert.equal(100, repost.cost)
    local summary = GC.SellPositions.Summary({ p })
    assert.equal(100, summary.invested)
    assert.equal(90, summary.profit)
  end)

  it("[FINAL I3] retains independently known partial cost and listed value in mixed summaries", function()
    local complete = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 1, 200, 1) } })[1]
    local incomplete = { coverage = "PARTIAL", knownQty = 1, exposureQty = 2,
      knownCost = 10, listedValue = 50, profit = nil, projectedNet = nil }
    local summary = GC.SellPositions.Summary({ complete, incomplete })
    assert.equal(110, summary.invested)
    assert.equal(250, summary.listedValue)
    assert.is_nil(summary.projected)
    assert.is_nil(summary.profit)
  end)

  it("keeps known investment while leaving an unquoted complete position's projection unknown", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) } })[1]
    local summary = GC.SellPositions.Summary({ p })
    assert.equal(100, summary.invested)
    assert.is_nil(summary.projected)
    assert.is_nil(summary.profit)
  end)

  it("keeps a complete losing position's signed profit in the summary", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 200, 1) },
      ownedLots = { lot("commodity:42", 1, 100, 1) } })[1]
    local summary = GC.SellPositions.Summary({ p })
    assert.equal(200, summary.invested)
    assert.equal(95, summary.projected)
    assert.equal(-105, summary.profit)
  end)

  it("sums multiple complete positions including losses into a signed exact profit", function()
    local summary = GC.SellPositions.Summary({
      { coverage = "COMPLETE", knownCost = 200, listedValue = 0, projectedNet = 95, profit = -105 },
      { coverage = "COMPLETE", knownCost = 30, listedValue = 0, projectedNet = 95, profit = 65 },
    })
    assert.same({ invested = 230, listedValue = 0, projected = 190, profit = -40 }, summary)
  end)

  it("fails closed when batch tracked and source quantities overflow exact accounting", function()
    local max = 9007199254740991
    local p = build({ acquisitions = {
      batch("acq:1", "goldcap", max, max, 1), batch("acq:2", "goldcap", 1, 1, 2),
    }, ownedLots = { lot("commodity:42", 1, 1, 1) } })[1]
    assert.not_equal("COMPLETE", p.coverage)
    assert.is_nil(p.trackedQty)
    assert.is_nil(p.sources.goldcap)
    assert.is_nil(p.projectedNet)
    assert.is_nil(GC.SellPositions.BuildRepostPlan(p, 1, 1))
  end)

  it("fails closed when owned-lot quantities, values, or FIFO skip ranges overflow", function()
    local max = 9007199254740991
    local first = lot("commodity:42", max, 1, 1, 1)
    local second = lot("commodity:42", 1, 1, 2, nil)
    local p = build({ acquisitions = { batch("acq:1", "goldcap", max, max, 1) },
      ownedLots = { first, second } })[1]
    assert.not_equal("COMPLETE", p.coverage)
    assert.is_nil(p.listedValue)
    assert.is_nil(GC.SellPositions.BuildRepostPlan(p, 1, 1))
    assert.is_nil(GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 1 }, 1))
  end)

  it("returns an unknown summary when complete cost aggregation would overflow", function()
    local max = 9007199254740991
    local summary = GC.SellPositions.Summary({
      { coverage = "COMPLETE", knownCost = max, listedValue = max, projectedNet = max },
      { coverage = "COMPLETE", knownCost = 1, listedValue = 1, projectedNet = 1 },
    })
    assert.same({ invested = nil, listedValue = nil, projected = nil, profit = nil }, summary)
  end)

  it("normalizes missing lot timestamps for stable FIFO sorting without mutating input", function()
    local undated = lot("commodity:42", 1, 100, 2, nil)
    undated.firstSeenAt = nil
    local dated = lot("commodity:42", 1, 100, 1, 1)
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 2, 200, 1) },
      ownedLots = { dated, undated } })[1]
    assert.equal(2, p.ownedLots[1].auctionID)
    assert.equal(1, p.ownedLots[2].auctionID)
    assert.is_nil(undated.firstSeenAt)
    assert.is_nil(undated.allocation)
  end)

  it("reserves listed FIFO quantity before allocating an exact post quantity", function()
    local p = build({ acquisitions = {
      batch("acq:1", "goldcap", 2, 101, 1), batch("acq:2", "manual", 2, 400, 2),
    }, ownedLots = { lot("commodity:42", 2, 200, 9) } })[1]
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 1 }, 300)
    assert.equal(1, plan.quantity)
    assert.equal(200, plan.cost)
    assert.equal("acq:2", plan.allocations[1].batchID)
  end)

  -- Posts what is in the bags, not what GoldCap has a receipt for. Listed units
  -- are on the auction house and not in the bags, so the bag count already IS
  -- "everything not yet listed" -- the old min(tracked - listed, bags) capped a
  -- real 9-unit stack at the 3 units GoldCap happened to know the price of, and
  -- refused outright for anything it had never seen bought.
  it("posts the whole bag quantity and reports how much of it is costed", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 5, 500, 1) },
      ownedLots = { lot("commodity:42", 2, 200, 1) } })[1]
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 9 }, 250)
    assert.equal(9, plan.quantity)
    -- Three of the nine are covered by the tracked purchase, so the cost of this
    -- post is not known exactly and is reported as unknown rather than guessed.
    assert.is_false(plan.costKnown)
    assert.is_nil(plan.cost)
  end)

  it("costs a post exactly when every unit of it is covered", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 5, 500, 1) },
      ownedLots = { lot("commodity:42", 2, 200, 1) } })[1]
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 3 }, 250)
    assert.equal(3, plan.quantity)
    assert.is_true(plan.costKnown)
    assert.equal(300, plan.cost)
  end)

  it("posts untracked bag stock that GoldCap never bought", function()
    local p = build({ bagStock = { { positionKey = "commodity:42", itemID = 42,
      itemName = "Ore", quantity = 40, isCommodity = true } } })[1]
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 40 }, 250)
    assert.equal(40, plan.quantity)
    assert.is_false(plan.costKnown)
    assert.equal(250, plan.unitPrice)
  end)

  -- Everything farmed, crafted, milled or bought before GoldCap existed. It used
  -- to be invisible here: a position existed only if GoldCap had a purchase
  -- receipt for it or the player already had it listed.
  it("builds a position out of bag stock alone and still advises a price", function()
    local p = build({
      bagStock = { { positionKey = "commodity:42", itemID = 42, itemName = "Ore", quantity = 40,
        isCommodity = true } },
      quotes = { [42] = { unit = 500, at = 10 } },
      statsByItemID = { [42] = { sold = 100 } },
      now = 10,
    })[1]
    assert.equal(40, p.bagQty)
    assert.equal("Ore", p.itemName)
    assert.equal(500, p.freshMarketUnit)
    -- No cost basis means no breakeven and no below-cost warning, rather than a
    -- cost invented from the market price.
    assert.is_not_nil(p.recommendation)
    assert.is_nil(p.recommendation.breakeven)
    assert.is_false(p.recommendation.belowCost)
  end)

  it("folds bag stock into the position its purchases and listings already share", function()
    local p = build({
      acquisitions = { batch("acq:1", "goldcap", 5, 500, 1) },
      ownedLots = { lot("commodity:42", 2, 200, 1) },
      bagStock = { { positionKey = "commodity:42", itemID = 42, quantity = 9, isCommodity = true } },
    })
    assert.equal(1, #p)
    assert.equal(9, p[1].bagQty)
    assert.equal(2, p[1].listedQty)
    assert.equal(5, p[1].trackedQty)
  end)

  it("fails closed on an ambiguous normal-item bag variant", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1, nil, nil, 42, "item:42:10:0:0") } })[1]
    local plan, reason = GC.SellPositions.BuildPostPlan(p,
      { itemID = 42, exactQty = 1, positionKey = "item:42:20:0:0" }, 200)
    assert.is_nil(plan)
    assert.equal("ambiguous_variant", reason)
  end)

  it("reposts one concrete auction and its precomputed FIFO slice", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1), batch("acq:2", "manual", 2, 500, 2) },
      ownedLots = { lot("commodity:42", 1, 200, 11, 1), lot("commodity:42", 2, 300, 12, 2) } })[1]
    local plan = GC.SellPositions.BuildRepostPlan(p, 12, 250)
    assert.equal(12, plan.auctionID)
    assert.equal(2, plan.quantity)
    assert.equal(500, plan.cost)
    assert.equal("acq:2", plan.allocations[1].batchID)
  end)

  it("rejects actions without a fresh quote or complete cost", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 2, 200, 1) } })[1]
    local plan, reason = GC.SellPositions.BuildRepostPlan(p, 1, { unit = 150, stale = true })
    assert.is_nil(plan)
    assert.equal("stale_quote", reason)
    plan, reason = GC.SellPositions.BuildRepostPlan(p, 1, 150)
    assert.is_nil(plan)
    assert.equal("incomplete_cost", reason)
  end)

  it("fails closed when an action receives a timestamped quote without fresh proof", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 1, 200, 1) } })[1]
    local plan, reason = GC.SellPositions.BuildRepostPlan(p, 1, { unit = 150, at = 0 })
    assert.is_nil(plan)
    assert.equal("stale_quote", reason)
    plan = GC.SellPositions.BuildRepostPlan(p, 1, { unit = 150, fresh = true })
    assert.equal(150, plan.unitPrice)
  end)

  it("fails malformed post positions closed instead of matching a missing variant key", function()
    -- No position key at all. The caller proves a plan belongs to the clicked row
    -- by comparing keys, and nil == nil passes that check, so this has to fail
    -- here rather than be caught downstream.
    local plan, reason = GC.SellPositions.BuildPostPlan({ itemID = 42, trackedQty = 1,
      listedQty = 0, batches = {} }, { itemID = 42, exactQty = 1 }, 150)
    assert.is_nil(plan)
    assert.equal("missing_position_key", reason)
  end)

  -- Pricing a sale off the cheapest row in the book prices it off the player's own auction as
  -- soon as they are the cheapest, so every repost walks their own price down against nobody.
  describe("CheapestCompetingUnit", function()
    it("ignores the player's own listings and returns the cheapest real competitor", function()
      assert.equal(60000, GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 55000, quantity = 240, ownerQty = 240, ownerItem = true },
        { unitPrice = 60000, quantity = 100 },
        { unitPrice = 65000, quantity = 2684 },
      }))
    end)

    -- The owner's real case: 110 competitor units already sat at 5g50s and his 130 joined the
    -- same price point. Matching that price was correct -- posting above it would have queued
    -- his stock behind someone else's -- so a shared level must still count as competition.
    it("keeps a level the player shares with real competitors", function()
      assert.equal(55000, GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 55000, quantity = 240, ownerQty = 130, ownerItem = true },
        { unitPrice = 60000, quantity = 100 },
      }))
    end)

    it("skips a level that is entirely the player's own", function()
      assert.equal(60000, GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 55000, quantity = 130, ownerQty = 130, ownerItem = true },
        { unitPrice = 60000, quantity = 100 },
      }))
    end)

    -- Without a count the level cannot be split, so it is skipped: erring high costs a match,
    -- erring low restarts the undercut spiral.
    it("skips an unsplittable owner level when the API reports no count", function()
      assert.equal(60000, GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 55000, quantity = 300, ownerItem = true },
        { unitPrice = 60000, quantity = 10 },
      }))
    end)

    it("returns nothing when the player is the only seller", function()
      assert.is_nil(GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 55000, quantity = 240, ownerQty = 240, ownerItem = true },
      }))
      assert.is_nil(GC.SellPositions.CheapestCompetingUnit({}))
      assert.is_nil(GC.SellPositions.CheapestCompetingUnit(nil))
    end)

    it("is not fooled by an unsorted book or an invalid price", function()
      assert.equal(60000, GC.SellPositions.CheapestCompetingUnit({
        { unitPrice = 90000, quantity = 5 },
        { unitPrice = 0, quantity = 5 },
        { unitPrice = 60000, quantity = 5 },
      }))
    end)
  end)
end)
