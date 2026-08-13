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

  it("returns an unknown summary when an included position lacks complete cost", function()
    local complete = build({ acquisitions = { batch("acq:1", "goldcap", 1, 100, 1) },
      ownedLots = { lot("commodity:42", 1, 200, 1) } })[1]
    local incomplete = { coverage = "PARTIAL", knownCost = 10, profit = nil, projectedNet = nil }
    local summary = GC.SellPositions.Summary({ complete, incomplete })
    assert.is_nil(summary.invested)
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
      { coverage = "COMPLETE", knownCost = 200, projectedNet = 95, profit = -105 },
      { coverage = "COMPLETE", knownCost = 30, projectedNet = 95, profit = 65 },
    })
    assert.same({ invested = 230, projected = 190, profit = -40 }, summary)
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
      { coverage = "COMPLETE", knownCost = max, projectedNet = max },
      { coverage = "COMPLETE", knownCost = 1, projectedNet = 1 },
    })
    assert.same({ invested = nil, projected = nil, profit = nil }, summary)
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

  it("caps post quantity to exact unlisted tracking and exact matching bag quantity", function()
    local p = build({ acquisitions = { batch("acq:1", "goldcap", 5, 500, 1) },
      ownedLots = { lot("commodity:42", 2, 200, 1) } })[1]
    local plan = GC.SellPositions.BuildPostPlan(p, { itemID = 42, exactQty = 9 }, 250)
    assert.equal(3, plan.quantity)
    assert.equal(300, plan.cost)
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
    local plan, reason = GC.SellPositions.BuildPostPlan({ itemID = 42, trackedQty = 1,
      listedQty = 0, batches = {} }, { itemID = 42, exactQty = 1 }, 150)
    assert.is_nil(plan)
    assert.equal("incomplete_cost", reason)
  end)
end)
