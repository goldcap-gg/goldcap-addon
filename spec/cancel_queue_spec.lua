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
  -- Followed groups (plan 2026-10-22, task 12): a group's floor lets an undercut lot be queued
  -- with no cost basis at all, as long as relisting stays at or over the floor; and a threshold
  -- the player sets keeps a small undercut from costing a deposit. Underpriced lots are urgent
  -- whatever the threshold. Positions come from Build with the rule injected, as SELL does.
  describe("with a followed group's rule and a cancel threshold", function()
    local function ruled(fresh, lotUnit, opts)
      opts = opts or {}
      local rules = { ruleFor = function() return { name = "Herbs", play = "gather",
        durationIndex = 2, floorUnit = opts.floor or 700 } end, roundsFor = function() return 0 end }
      if opts.noRule then rules = nil end
      return build({
        acquisitions = opts.acquisitions or {},
        ownedLots = { lot("commodity:42", 2, lotUnit or 1000, 7) },
        quotes = { [42] = { unit = fresh, at = 9 } },
        rules = rules,
      })
    end

    it("a rule queues an undercut lot without a cost basis", function()
      local positions = ruled(800)
      assert.equal("NO_COST", positions[1].status) -- fixture honesty check
      assert.is_nil(positions[1].recommendation)
      local entries, skipped = GC.CancelQueue.Build(positions)
      assert.equal(0, #skipped)
      assert.equal(1, #entries)
      assert.equal(1000, entries[1].listedUnit)
      assert.equal(1600, entries[1].value)
      -- Without the rule the same lot waits for a cost basis, as before.
      assert.equal("no_advice", select(2, GC.CancelQueue.Build(ruled(800, 1000, { noRule = true })))[1].reason)
    end)

    it("a repost under the floor holds with below_floor", function()
      local entries, skipped = GC.CancelQueue.Build(ruled(650))
      assert.equal(0, #entries)
      assert.equal("below_floor", findSkip(skipped, "commodity:42").reason)
    end)

    it("a small undercut holds", function()
      local entries, skipped = GC.CancelQueue.Build(ruled(960), { undercutPct = 5 })
      assert.equal(0, #entries)
      assert.equal("small_undercut", findSkip(skipped, "commodity:42").reason)
      entries = GC.CancelQueue.Build(ruled(940), { undercutPct = 5 })
      assert.equal(1, #entries)
      -- At 0 any undercut counts.
      assert.equal(1, #GC.CancelQueue.Build(ruled(990), { undercutPct = 0 }))
      -- An underpriced lot is urgent whatever the threshold.
      local urgent = ruled(960, 300)
      assert.is_true(urgent[1].facts.underpriced) -- fixture honesty check
      entries = GC.CancelQueue.Build(urgent, { undercutPct = 20 })
      assert.equal(1, #entries)
      assert.is_true(entries[1].urgent)
    end)

    it("applies the threshold to an advised repost without a rule too", function()
      local positions = advisedRepostPositions() -- lot 20000 against a 15000 market: 25% under
      assert.equal(1, #GC.CancelQueue.Build(positions, { undercutPct = 20 }))
      local entries, skipped = GC.CancelQueue.Build(positions, { undercutPct = 25 })
      assert.equal(0, #entries)
      assert.equal("small_undercut", findSkip(skipped, "commodity:42").reason)
    end)

    it("a loss hold still holds under a rule", function()
      -- Paid 1000 a unit against an 800 market: RepostAdvice says hold, for a loss.
      local positions = ruled(800, 1000, { acquisitions = { batch("acq:1", 2, 2000, 42, "commodity:42") } })
      assert.equal("hold", positions[1].recommendation.action) -- fixture honesty check
      assert.equal("loss", positions[1].recommendation.reason)
      local entries, skipped = GC.CancelQueue.Build(positions)
      assert.equal(0, #entries)
      assert.equal("advised_hold", findSkip(skipped, "commodity:42").reason)
      -- A slow hold is not the group's concern: its rule relists over the floor.
      positions[1].recommendation = { action = "hold", reason = "slow" }
      assert.equal(1, #GC.CancelQueue.Build(positions))
    end)

    it("no rule and no threshold is today's queue", function()
      for _, opts in ipairs({ false, { undercutPct = 0 }, {} }) do
        local entries, skipped = GC.CancelQueue.Build(advisedRepostPositions(), opts or nil)
        assert.equal(1, #entries)
        assert.equal(0, #skipped)
      end
    end)
  end)

  -- WoW: Forever (2026-11-06): a cancel loses the lot's deposit, and the advice spent it on a copper.
  -- The owner's save: 7 Stringy Wolf Meat bought at 30c, listed at 40c, a 39c lot under them, and
  -- the lots that sold paid a 99c deposit. Build gets what a cancel loses as `cancelForfeit`
  -- (Services/Sell/Cancel.lua's GC.Sell.LotForfeit, Forever only); retail passes none.
  describe("in WoW: Forever, weighing the deposit a cancel loses", function()
    local MEAT = "commodity:2672"
    local savedAH

    before_each(function()
      -- Forever's book carries copper: the relist price is 39c, not a silver.
      savedAH = _G.C_AuctionHouse
      _G.C_AuctionHouse = { SupportsCopperValues = function() return true end }
    end)

    after_each(function() _G.C_AuctionHouse = savedAH end)

    local function meat(lots, forfeit)
      local owned = {}
      for i, unit in ipairs(lots) do owned[i] = lot(MEAT, 7, unit, 776 + i) end
      return build({
        acquisitions = { batch("acq:9", 7 * #lots, 210 * #lots, 2672, MEAT) },
        ownedLots = owned,
        quotes = { [2672] = { unit = 39, at = 9, levels = { { unitPrice = 39, quantity = 5 },
          { unitPrice = 40, quantity = 7, ownerQty = 7, ownerItem = true }, { unitPrice = 45, quantity = 30 } } } },
        statsByItemID = { [2672] = { mv = 41, source = "scan" } },
        cancelForfeit = forfeit,
      })
    end

    it("holds a 1c undercut that would cost a 99c deposit", function()
      local positions = meat({ 40 }, function() return 99 end)
      assert.same({ action = "hold", reason = "deposit" },
        { action = positions[1].recommendation.action, reason = positions[1].recommendation.reason })
      assert.equal(39, positions[1].recommendation.rec.unit)
      assert.is_false(positions[1].ownedLots[1].cancelWorth)
      assert.equal(99, positions[1].ownedLots[1].cancelForfeit)
      local entries, skipped = GC.CancelQueue.Build(positions, { undercutPct = 0 })
      assert.equal(0, #entries)
      assert.equal("deposit", findSkip(skipped, MEAT).reason)
    end)

    it("leaves retail's advice as it was: no forfeit, the same lot is a repost at the queue's head", function()
      local positions = meat({ 40 })
      assert.equal("repost", positions[1].recommendation.action)
      assert.is_nil(positions[1].ownedLots[1].cancelWorth)
      local entries = GC.CancelQueue.Build(positions, { undercutPct = 0 })
      assert.equal(1, #entries)
      assert.equal(777, entries[1].auctionID)
    end)

    it("queues an undercut worth more than the deposit", function()
      -- (200 - 39) x 7 = 1127c moved for a 99c deposit.
      local positions = meat({ 200 }, function() return 99 end)
      assert.equal("repost", positions[1].recommendation.action)
      assert.is_true(positions[1].ownedLots[1].cancelWorth)
      local entries = GC.CancelQueue.Build(positions)
      assert.equal(1, #entries)
      assert.equal(200, entries[1].listedUnit)
    end)

    it("needs the undercut to be MORE than the deposit, not equal to it", function()
      -- (40 - 39) x 7 = 7c against a 7c forfeit.
      local positions = meat({ 40 }, function() return 7 end)
      assert.equal("deposit", positions[1].recommendation.reason)
      assert.is_true(meat({ 40 }, function() return 6 end)[1].ownedLots[1].cancelWorth)
    end)

    it("holds when the client cannot quote what the cancel loses", function()
      local positions = meat({ 200 }, function() return nil end)
      assert.equal("hold", positions[1].recommendation.action)
      assert.equal("deposit", positions[1].recommendation.reason)
      assert.is_nil(positions[1].ownedLots[1].cancelForfeit)
      assert.equal("deposit", findSkip(select(2, GC.CancelQueue.Build(positions)), MEAT).reason)
    end)

    it("weighs each lot: the one worth it is queued, the one that is not stays", function()
      local asked = {}
      local positions = meat({ 40, 200 }, function(owned) asked[#asked + 1] = owned.auctionID; return 99 end)
      table.sort(asked)
      assert.same({ 777, 778 }, asked)
      assert.equal("repost", positions[1].recommendation.action)
      local entries, skipped = GC.CancelQueue.Build(positions)
      assert.equal(1, #entries)
      assert.equal(778, entries[1].auctionID)
      assert.equal(0, #skipped)
    end)

    it("still pulls a lot far below its value, whatever its deposit", function()
      -- 10c against a 41c value: urgent, and no undercut for the deposit to weigh.
      local positions = meat({ 10 }, function() return 99 end)
      assert.is_true(positions[1].facts.underpriced) -- fixture honesty check
      -- Nothing over the market was weighed, so the advice is left as it was.
      assert.equal("repost", positions[1].recommendation.action)
      local entries = GC.CancelQueue.Build(positions)
      assert.equal(1, #entries)
      assert.is_true(entries[1].urgent)
    end)
  end)
end)
