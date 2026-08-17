local helper = require("spec.spec_helper")

-- Fixtures are built by calling GC.SellPositions.Build wherever that is possible, same rule as
-- spec/post_queue_spec.lua and for the same reason: a hand-written position table that drifts
-- from what Build actually produces is how a green test ends up proving nothing. The one
-- hand-written exception is the unresolved position, called out at its use site.
describe("CancelQueue", function()
  local GC
  local context = { char = "A-R", region = "eu" }

  local function batch(id, qty, total, itemID, positionKey)
    return { id = id, source = "goldcap", itemID = itemID or 42, positionKey = positionKey,
      remainingQty = qty, remainingTotal = total, acquiredAt = 1,
      character = context.char, region = context.region }
  end

  local function lot(positionKey, quantity, unitPrice, auctionID)
    return { itemID = tonumber(positionKey:match(":(%d+)$")) or 42, positionKey = positionKey,
      quantity = quantity, unitPrice = unitPrice, auctionID = auctionID, firstSeenAt = 1 }
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
    GC = helper.loadModule("Core/CancelQueue.lua", GC)
  end)

  -- The canonical inclusion: COMPLETE coverage, RepostAdvice says "repost" (paid 100s/unit,
  -- market 150s -- relisting beats holding), and the lot sits at 200s, above the 150s fresh
  -- quote, so it cannot sell until the book climbs back.
  local function advisedRepostPositions()
    return build({
      acquisitions = { batch("acq:1", 2, 20000, 42, "commodity:42") },
      ownedLots = { lot("commodity:42", 2, 20000, 7) },
      quotes = { [42] = { unit = 15000, at = 9, levels = { { unitPrice = 15000, quantity = 3 } } } },
      statsByItemID = { [42] = { sold = 400 } },
    })
  end

  it("queues an advised-repost lot listed above the fresh market", function()
    local positions = advisedRepostPositions()
    assert.equal("repost", positions[1].recommendation.action) -- fixture honesty check

    local entries, skipped = GC.CancelQueue.Build(positions)

    assert.equal(0, #skipped)
    assert.equal(1, #entries)
    local entry = entries[1]
    assert.equal("commodity:42", entry.positionKey)
    assert.equal(positions[1].scopeKey, entry.scopeKey)
    assert.equal(42, entry.itemID)
    assert.equal(7, entry.auctionID)
    assert.equal(2, entry.quantity)
    assert.equal(20000, entry.listedUnit)
    assert.equal(30000, entry.value) -- 2 units x the 15000 fresh market unit
    assert.is_nil(entry.urgent)
  end)

  it("never queues a competitive lot -- at or below the fresh market", function()
    local positions = build({
      acquisitions = { batch("acq:1", 4, 40000, 42, "commodity:42") },
      -- One lot above the 150s market (cancel-worthy), one at 149s (the live cheapest ask,
      -- healthy) -- cancelling the competitive one would burn a deposit for nothing.
      ownedLots = { lot("commodity:42", 2, 20000, 7), lot("commodity:42", 2, 14900, 8) },
      quotes = { [42] = { unit = 15000, at = 9, levels = { { unitPrice = 14900, quantity = 2 } } } },
      statsByItemID = { [42] = { sold = 400 } },
    })

    local entries = GC.CancelQueue.Build(positions)

    assert.equal(1, #entries)
    assert.equal(7, entries[1].auctionID)
  end)

  it("marks the underpriced lot urgent and puts it first regardless of value", function()
    local positions = build({
      acquisitions = {
        batch("acq:1", 2, 20000, 42, "commodity:42"),
        batch("acq:2", 50, 500000, 43, "commodity:43"),
      },
      ownedLots = {
        -- The Arcane Crystal shape: bought at 100s, listed at 18s against a 92s market --
        -- money leaving silently. Value 2 x 9200 = 18400, far SMALLER than the other entry's.
        lot("commodity:42", 2, 1800, 7),
        -- An ordinary undercut leftover worth far more: 50 x 20000 = 1000000.
        lot("commodity:43", 50, 30000, 9),
      },
      quotes = {
        [42] = { unit = 9200, at = 9, levels = { { unitPrice = 9200, quantity = 3 } } },
        [43] = { unit = 20000, at = 9, levels = { { unitPrice = 20000, quantity = 3 } } },
      },
      statsByItemID = { [42] = { sold = 400 }, [43] = { sold = 400 } },
    })

    local entries = GC.CancelQueue.Build(positions)

    assert.equal(2, #entries)
    assert.equal(7, entries[1].auctionID)
    assert.is_true(entries[1].urgent)
    assert.equal(9, entries[2].auctionID)
    assert.is_nil(entries[2].urgent)
  end)

  it("orders non-urgent entries by value descending, ties by positionKey then auctionID", function()
    local positions = build({
      acquisitions = {
        batch("acq:1", 2, 20000, 42, "commodity:42"),
        batch("acq:2", 4, 40000, 43, "commodity:43"),
      },
      ownedLots = {
        lot("commodity:42", 2, 20000, 9),  -- value 2 x 15000 = 30000
        lot("commodity:43", 2, 21000, 8),  -- value 2 x 15000 = 30000 (ties; commodity:42 first)
        lot("commodity:43", 2, 20500, 3),  -- value 30000 (same position: lower auctionID first)
      },
      quotes = {
        [42] = { unit = 15000, at = 9, levels = { { unitPrice = 15000, quantity = 3 } } },
        [43] = { unit = 15000, at = 9, levels = { { unitPrice = 15000, quantity = 3 } } },
      },
      statsByItemID = { [42] = { sold = 400 }, [43] = { sold = 400 } },
    })

    local entries = GC.CancelQueue.Build(positions)

    assert.equal(3, #entries)
    assert.equal("commodity:42", entries[1].positionKey)
    assert.equal("commodity:43", entries[2].positionKey)
    assert.equal(3, entries[2].auctionID)
    assert.equal(8, entries[3].auctionID)
  end)

  it("holds back an above-market lot when the advice is hold, reason advised_hold", function()
    -- Paid 300s/unit against a 150s market: RepostAdvice returns hold/loss -- relisting locks
    -- in the loss, so the queue must not recommend the cancel either.
    local positions = build({
      acquisitions = { batch("acq:1", 2, 60000, 42, "commodity:42") },
      ownedLots = { lot("commodity:42", 2, 40000, 7) },
      quotes = { [42] = { unit = 15000, at = 9, levels = { { unitPrice = 15000, quantity = 3 } } } },
      statsByItemID = { [42] = { sold = 400 } },
    })
    assert.equal("hold", positions[1].recommendation.action) -- fixture honesty check

    local entries, skipped = GC.CancelQueue.Build(positions)

    assert.equal(0, #entries)
    local skip = findSkip(skipped, "commodity:42")
    assert.is_table(skip)
    assert.equal("advised_hold", skip.reason)
  end)

  it("holds back a listed position with no fresh quote, reason no_fresh_price", function()
    local positions = build({
      acquisitions = { batch("acq:1", 2, 20000, 42, "commodity:42") },
      ownedLots = { lot("commodity:42", 2, 20000, 7) },
      quotes = { [42] = { unit = 15000, at = 0 } }, -- stale: freshMarketUnit stays nil
      now = 11,
    })

    local entries, skipped = GC.CancelQueue.Build(positions)

    assert.equal(0, #entries)
    assert.equal("no_fresh_price", findSkip(skipped, "commodity:42").reason)
  end)

  it("holds back an above-market lot on a PARTIAL position, reason no_advice", function()
    -- Coverage PARTIAL: only 1 of the 2 listed units has a cost, so SellPositions computes no
    -- RepostAdvice at all -- no authority says relisting beats holding.
    local positions = build({
      acquisitions = { batch("acq:1", 1, 10000, 42, "commodity:42") },
      ownedLots = { lot("commodity:42", 2, 20000, 7) },
      quotes = { [42] = { unit = 15000, at = 9, levels = { { unitPrice = 15000, quantity = 3 } } } },
      statsByItemID = { [42] = { sold = 400 } },
    })
    assert.equal("PARTIAL", positions[1].coverage) -- fixture honesty check

    local entries, skipped = GC.CancelQueue.Build(positions)

    assert.equal(0, #entries)
    assert.equal("no_advice", findSkip(skipped, "commodity:42").reason)
  end)

  it("holds back an unresolved position, reason unresolved_identity", function()
    -- Hand-written on purpose: SellPositions' unresolved rows come out of identity repair, a
    -- shape Build() cannot be driven into from this spec's plain inputs. Fields mirror what
    -- decoratePosition leaves on such a row.
    local entries, skipped = GC.CancelQueue.Build({ {
      unresolved = true, positionKey = "commodity:42", itemID = 42, itemName = "Ore",
      freshMarketUnit = 15000,
      ownedLots = { { auctionID = 7, quantity = 2, unitPrice = 20000 } },
    } })

    assert.equal(0, #entries)
    assert.equal("unresolved_identity", findSkip(skipped, "commodity:42").reason)
  end)

  it("Without returns a new array minus the given auctionID, never mutating the input", function()
    local positions = advisedRepostPositions()
    local entries = GC.CancelQueue.Build(positions)
    assert.equal(1, #entries)

    local trimmed = GC.CancelQueue.Without(entries, 7)

    assert.equal(0, #trimmed)
    assert.equal(1, #entries)
    assert.not_equal(entries, trimmed)
  end)
end)
