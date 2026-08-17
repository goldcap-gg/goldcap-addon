local helper = require("spec.spec_helper")

-- Fixtures here are built by calling GC.SellPositions.Build (and, for the quote cache,
-- GC.QuoteCache.Set) wherever that is possible, rather than hand-writing position tables --
-- a fixture that drifts from what Build actually produces is how a green test ends up proving
-- nothing, and this project has shipped that exact failure twice already (once through a
-- fixture, once through a widget double). The two exceptions are called out at their use sites
-- below, with the structural reason a real Build() call cannot reach that case.
describe("PostQueue", function()
  local GC
  local context = { char = "A-R", region = "eu" }

  local function batch(id, source, qty, total, at, itemID, positionKey)
    return { id = id, source = source, itemID = itemID or 42, positionKey = positionKey,
      remainingQty = qty, remainingTotal = total, acquiredAt = at,
      character = context.char, region = context.region }
  end

  local function stock(positionKey, itemID, itemName, quantity)
    return { positionKey = positionKey, itemID = itemID, itemName = itemName, quantity = quantity }
  end

  local function setQuote(quotes, itemID, unit, now)
    GC.QuoteCache.Set(quotes, itemID, unit, now or 10)
  end

  local function build(args)
    args = args or {}
    args.acquisitions = args.acquisitions or {}
    args.ownedLots = args.ownedLots or {}
    args.bagStock = args.bagStock or {}
    args.quotes = args.quotes or {}
    args.statsByItemID = args.statsByItemID or {}
    args.context = args.context or context
    args.now = args.now or 10
    return GC.SellPositions.Build(args)
  end

  local function findPosition(positions, positionKey)
    for _, position in ipairs(positions) do
      if position.positionKey == positionKey then return position end
    end
    return nil
  end

  local function findEntry(entries, positionKey)
    for _, entry in ipairs(entries) do
      if entry.positionKey == positionKey then return entry end
    end
    return nil
  end

  local function findSkip(skipped, positionKey)
    for _, skip in ipairs(skipped) do
      if skip.positionKey == positionKey then return skip end
    end
    return nil
  end

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua")
    GC = helper.loadModule("Core/Flips.lua", GC)
    GC = helper.loadModule("Core/QuoteCache.lua", GC)
    GC = helper.loadModule("Core/SellPositions.lua", GC)
    GC = helper.loadModule("Core/PostQueue.lua", GC)
  end)

  -- Three plain bag-stock positions (no acquisitions, no listings): the simplest shape that
  -- reaches SellPositions' `elseif positive(bagQty) and fresh` recommendation branch, which
  -- always yields mode="undercut" with belowCost=false (no paidUnit means no breakeven), so
  -- value/order is the only thing under test here.
  --
  -- Part 0 (silver-grid fix): quotes are whole-silver and comfortably above the match/undercut
  -- share boundary (50 silver -- see silver_grid_spec.lua), so the undercut candidate is a
  -- clean one silver below each quote, on the grid, with no risk of RecommendPost switching to
  -- match mode and changing which value wins.
  local function threeOrderedPositions(quotes)
    local positions = build({
      bagStock = {
        stock("commodity:1", 1, "Ore One", 4),  -- unit 10000 * qty 4 = 40000
        stock("commodity:2", 2, "Ore Two", 4),  -- unit 10000 * qty 4 = 40000 (ties with commodity:1)
        stock("commodity:3", 3, "Ore Three", 1), -- unit 50000 * qty 1 = 50000 (highest)
      },
      quotes = quotes,
    })
    return positions
  end

  it("orders included entries by value (unitPrice * bagQty) descending", function()
    local quotes = {}
    setQuote(quotes, 1, 10100, 10)
    setQuote(quotes, 2, 10100, 10)
    setQuote(quotes, 3, 50100, 10)
    local positions = threeOrderedPositions(quotes)

    local entries, skipped = GC.PostQueue.Build(positions)

    assert.equal(0, #skipped)
    assert.equal(3, #entries)
    assert.same({ "commodity:3", "commodity:1", "commodity:2" }, {
      entries[1].positionKey, entries[2].positionKey, entries[3].positionKey,
    })
    assert.equal(50000, entries[1].value)
    assert.equal(40000, entries[2].value)
    assert.equal(40000, entries[3].value)
  end)

  -- Ties are broken by positionKey ascending. commodity:1 and commodity:2 tie at value 40000
  -- above; commodity:1 must sort first regardless of what order the caller handed the
  -- positions over in, and regardless of how many times the same inputs are rebuilt.
  it("is stable: ties break by positionKey ascending, independent of input order or rebuild", function()
    local quotes = {}
    setQuote(quotes, 1, 10100, 10)
    setQuote(quotes, 2, 10100, 10)
    setQuote(quotes, 3, 50100, 10)
    local first = threeOrderedPositions(quotes)

    -- Same objects, deliberately handed over in a different array order.
    local shuffled = { first[3], first[1], first[2] }
    local shuffledEntries = GC.PostQueue.Build(shuffled)

    -- A completely independent SellPositions.Build() call from the same inputs.
    local secondQuotes = {}
    setQuote(secondQuotes, 1, 10100, 10)
    setQuote(secondQuotes, 2, 10100, 10)
    setQuote(secondQuotes, 3, 50100, 10)
    local second = threeOrderedPositions(secondQuotes)
    local secondEntries = GC.PostQueue.Build(second)

    local firstEntries = GC.PostQueue.Build(first)
    local function keys(entries)
      local out = {}
      for i, entry in ipairs(entries) do out[i] = entry.positionKey end
      return out
    end
    assert.same(keys(firstEntries), keys(shuffledEntries))
    assert.same(keys(firstEntries), keys(secondEntries))
  end)

  it("skips a position with no fresh quote, reason no_fresh_price, and excludes it from entries", function()
    local positions = build({
      bagStock = { stock("commodity:4", 4, "Undated Herb", 5) },
      -- No quote set at all for itemID 4: freshMarketUnit stays nil.
    })

    local entries, skipped = GC.PostQueue.Build(positions)

    assert.is_nil(findEntry(entries, "commodity:4"))
    local skip = findSkip(skipped, "commodity:4")
    assert.is_table(skip)
    assert.equal(4, skip.itemID)
    assert.equal("Undated Herb", skip.itemName)
    assert.equal("no_fresh_price", skip.reason)
  end)

  it("skips a position whose recommendation is below breakeven, reason below_breakeven", function()
    local quotes = {}
    -- Part 0 (silver-grid fix): a 100c/unit ask is exactly one silver, so the undercut candidate
    -- clamps to the grid floor (100c), not the pre-fix 99c.
    setQuote(quotes, 50, 100, 10) -- fresh ask 100c/unit -> undercut candidate 100c/unit (grid floor)
    local positions = build({
      -- Paid 200c/unit; breakeven = ceil(200/0.95) = 211c, well above the 100c candidate.
      acquisitions = { batch("acq:1", "goldcap", 5, 1000, 1, 50, "commodity:50") },
      bagStock = { stock("commodity:50", 50, "Overpaid Widget", 5) },
      quotes = quotes,
    })

    local position = findPosition(positions, "commodity:50")
    assert.equal("COMPLETE", position.coverage)
    -- What PostQueue actually reads to decide this.
    assert.is_true(position.postRecommendation.belowCost)

    local entries, skipped = GC.PostQueue.Build(positions)

    assert.is_nil(findEntry(entries, "commodity:50"))
    local skip = findSkip(skipped, "commodity:50")
    assert.is_table(skip)
    assert.equal("below_breakeven", skip.reason)
  end)

  -- The defect this module shipped with: a position that is COMPLETE-covered, ALREADY PARTLY
  -- LISTED, and still holds bag stock (bought 200, posted 100, 100 still in the bags) gets a
  -- RepostAdvice-shaped `recommendation` from SellPositions ({action, reason, rec}, no top-level
  -- `.unit`). Reading `recommendation.unit` there finds nothing and reports `no_fresh_price`,
  -- even though the row's own Post button posts the 100 bag units fine (BuildPostPlan never
  -- reads `recommendation` at all). `postRecommendation` answers "what would I post the bags
  -- at" independently of the repost question, and this is what actually fixes it.
  it("includes a position that is COMPLETE-covered, already partly listed, AND holds bag stock", function()
    local quotes = {}
    setQuote(quotes, 90, 20000, 10)
    local positions = build({
      acquisitions = { batch("acq:1", "goldcap", 200, 2000000, 1, 90, "commodity:90") },
      ownedLots = { { itemID = 90, positionKey = "commodity:90", quantity = 100,
        unitPrice = 15000, auctionID = 1, firstSeenAt = 1 } },
      bagStock = { stock("commodity:90", 90, "Partly Listed Ore", 100) },
      quotes = quotes,
    })

    local position = findPosition(positions, "commodity:90")
    assert.equal("COMPLETE", position.coverage)
    assert.is_true(position.listedQty > 0)
    assert.equal(100, position.bagQty)
    -- The bug, isolated: recommendation has no price to copy.
    assert.is_nil(position.recommendation.unit)
    -- The fix: postRecommendation does.
    assert.is_not_nil(position.postRecommendation)
    assert.is_true(position.postRecommendation.unit > 0)

    local entries, skipped = GC.PostQueue.Build(positions)

    assert.is_nil(findSkip(skipped, "commodity:90"))
    local entry = findEntry(entries, "commodity:90")
    assert.is_table(entry)
    assert.equal(position.postRecommendation.unit, entry.unitPrice)
    assert.equal(100, entry.bagQty)
  end)

  it("never posts an unresolved position -- absent from the queue Build() actually produces", function()
    -- Real SellPositions.Build() output: two acquisition batches carry distinct, proven
    -- position keys for itemID 5 (making the variant genuinely ambiguous), and a third batch
    -- for the same itemID carries no key at all, so it cannot be resolved and is filed as an
    -- unresolved repair row instead of a normal position.
    local positions = build({
      acquisitions = {
        batch("acq:a", "goldcap", 3, 300, 1, 5, "item:5:1:0:0"),
        batch("acq:b", "goldcap", 2, 200, 1, 5, "item:5:2:0:0"),
        batch("acq:c", "goldcap", 1, 100, 1, 5, nil),
      },
    })

    local sawUnresolved = false
    for _, position in ipairs(positions) do
      if position.itemID == 5 and position.unresolved then sawUnresolved = true end
    end
    assert.is_true(sawUnresolved)

    local entries, skipped = GC.PostQueue.Build(positions)
    for _, entry in ipairs(entries) do assert.is_not.equal(5, entry.itemID) end
    for _, skip in ipairs(skipped) do assert.is_not.equal(5, skip.itemID) end
  end)

  -- SellPositions.Build never produces a position that is BOTH `unresolved` and carries a
  -- postable `bagQty` -- bag stock only ever joins a position through a positionKey a
  -- classifier already resolved (see Core/BagStock.lua's own comment on `classify = nil`),
  -- while an unresolved row exists ONLY because no positionKey could be resolved at all. Those
  -- two facts are structurally exclusive, so the only way to prove the `unresolved` FLAG ITSELF
  -- (as opposed to the bagQty gate alone) is what excludes a position is to take a real,
  -- otherwise-fully-qualifying Build() position and add the flag SellPositions.BuildPostPlan
  -- already treats as disqualifying. This is the one fixture in this file that cannot be
  -- produced by Build() alone.
  it("excludes a position flagged unresolved even when it would otherwise qualify", function()
    local quotes = {}
    setQuote(quotes, 1, 51, 10)
    local positions = build({
      bagStock = { stock("commodity:1", 1, "Ore One", 4) },
      quotes = quotes,
    })
    local qualifying = findPosition(positions, "commodity:1")
    local baselineEntries, baselineSkipped = GC.PostQueue.Build({ qualifying })
    assert.equal(1, #baselineEntries)
    assert.equal(0, #baselineSkipped)

    local clone = {}
    for key, value in pairs(qualifying) do clone[key] = value end
    clone.unresolved = true

    local entries, skipped = GC.PostQueue.Build({ clone })
    assert.equal(0, #entries)
    assert.equal(1, #skipped)
    assert.equal("unresolved_identity", skipped[1].reason)
  end)

  -- A fully real Build() position: two acquisition batches whose combined quantity overflows
  -- MAX_EXACT flip SellPositions' own `position.invalid`, while a separate bagStock entry for
  -- the same key still supplies a positive bagQty and a fresh quote still resolves. This proves
  -- `invalid` alone -- not missing price, not bagQty -- is what excludes it.
  it("excludes an invalid position (SellPositions' own accounting overflowed)", function()
    local huge = 9007199254740991
    local quotes = {}
    setQuote(quotes, 60, 51, 10)
    local positions = build({
      acquisitions = {
        batch("acq:a", "goldcap", huge, 1, 1, 60, "commodity:60"),
        batch("acq:b", "goldcap", huge, 1, 1, 60, "commodity:60"),
      },
      bagStock = { stock("commodity:60", 60, "Overflowed Reagent", 10) },
      quotes = quotes,
    })
    local position = findPosition(positions, "commodity:60")
    assert.is_true(position.invalid)
    assert.equal(10, position.bagQty)
    assert.is_not_nil(position.freshMarketUnit)

    local entries, skipped = GC.PostQueue.Build(positions)
    assert.is_nil(findEntry(entries, "commodity:60"))
    local skip = findSkip(skipped, "commodity:60")
    assert.is_table(skip)
    assert.equal("unresolved_identity", skip.reason)
  end)

  it("leaves bagQty == 0 absent from both lists -- nothing to post, nothing to explain", function()
    local quotes = {}
    setQuote(quotes, 6, 51, 10)
    local positions = build({
      -- Cost basis and a fresh quote, but no bag stock at all: bagQty stays 0.
      acquisitions = { batch("acq:1", "goldcap", 3, 300, 1, 6, "commodity:6") },
      quotes = quotes,
    })
    local position = findPosition(positions, "commodity:6")
    assert.equal(0, position.bagQty)

    local entries, skipped = GC.PostQueue.Build(positions)
    assert.is_nil(findEntry(entries, "commodity:6"))
    assert.is_nil(findSkip(skipped, "commodity:6"))
  end)

  it("copies unitPrice from the position's own postRecommendation.unit, never recomputing it", function()
    local quotes = {}
    setQuote(quotes, 1, 10100, 10)
    setQuote(quotes, 2, 10100, 10)
    setQuote(quotes, 3, 50100, 10)
    local positions = threeOrderedPositions(quotes)

    local entries = GC.PostQueue.Build(positions)
    assert.is_true(#entries > 0)
    for _, entry in ipairs(entries) do
      local position = findPosition(positions, entry.positionKey)
      assert.equal(position.postRecommendation.unit, entry.unitPrice)
    end
  end)

  it("Without returns a new array minus the given entry, leaving the original untouched", function()
    local quotes = {}
    setQuote(quotes, 1, 10100, 10)
    setQuote(quotes, 2, 10100, 10)
    setQuote(quotes, 3, 50100, 10)
    local positions = threeOrderedPositions(quotes)
    local entries = GC.PostQueue.Build(positions)
    assert.equal(3, #entries)
    local originalFirstKey = entries[1].positionKey

    local result = GC.PostQueue.Without(entries, originalFirstKey)

    assert.is_not.equal(entries, result)
    assert.equal(2, #result)
    assert.is_nil(findEntry(result, originalFirstKey))
    -- The input array itself must be completely unaffected by the call.
    assert.equal(3, #entries)
    assert.equal(originalFirstKey, entries[1].positionKey)
  end)

  -- unitPrice and bagQty are each individually well within MAX_EXACT, but their product is not
  -- -- this is PostQueue's OWN arithmetic overflowing (unitPrice * bagQty), a different failure
  -- from SellPositions' internal `invalid` flag tested above. Built via Build() with a
  -- deliberately unrealistic bag quantity, the same technique BagStock's own overflow spec uses.
  it("skips a position whose value overflows exact-integer arithmetic, rather than clamping it", function()
    local quotes = {}
    setQuote(quotes, 7, 100000001, 10) -- undercut candidate: 100000000
    local positions = build({
      bagStock = { stock("commodity:7", 7, "Absurd Stack", 100000000) },
      quotes = quotes,
    })
    local position = findPosition(positions, "commodity:7")
    assert.equal(100000000, position.postRecommendation.unit)
    assert.equal(100000000, position.bagQty)

    local entries, skipped = GC.PostQueue.Build(positions)
    assert.is_nil(findEntry(entries, "commodity:7"))
    local skip = findSkip(skipped, "commodity:7")
    assert.is_table(skip)
    assert.equal("unresolved_identity", skip.reason)
  end)
end)
