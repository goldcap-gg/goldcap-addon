local helper = require("spec.spec_helper")

-- GC.Sell.Reset runs when the auction house closes (GC.Sniper.OnAuctionHouseClosed). It clears what
-- a closed auction house makes stale and keeps the rest on purpose: a reset that replaced the
-- whole state would drop the drain tombstones a late answer still needs, the player's typed
-- prices, the deck they were on and the lots they just cancelled. Both lists are pinned here.
describe("GC.Sell.Reset", function()
  local GC, S

  before_each(function()
    GC = { Sell = {} }
    helper.loadModule("Core/QuoteCache.lua", GC)
    helper.loadSell(GC)
    S = GC.SellState
  end)

  it("clears what a closed auction house makes stale", function()
    S.refresh.phase, S.refresh.queue, S.refresh.index = "pricing", { 1, 2 }, 2
    S.refresh.priority, S.refresh.awaitingPriority, S.refresh.skipped, S.refresh.waitingNoted = { 9 }, 9, 3, true
    S.emptyAnswers[42] = { at = 1, answered = true }
    S.ownedAwaitingKind[42] = true
    S.bagLocationCache["commodity:42"] = { bag = 0, slot = 1 }
    S.quotes[42] = { unit = 100, at = 1 }
    S.quotesSeeded = true
    GC.Sell._lateAnswers = { { pin = {}, at = 1 } }
    GC.Sell._owedUntil = 99
    local generation, expiry = S.refresh.generation, S.quoteExpiryGeneration
    local repeatToken, watchdog = S.walkRepeatToken, S.watchdogToken

    GC.Sell.Reset()

    assert.equal("idle", S.refresh.phase)
    assert.same({}, S.refresh.queue)
    assert.equal(0, S.refresh.index)
    assert.same({}, S.refresh.priority)
    assert.is_nil(S.refresh.awaitingPriority)
    assert.equal(0, S.refresh.skipped)
    assert.is_false(S.refresh.waitingNoted)
    assert.equal(generation + 1, S.refresh.generation)
    assert.is_nil(next(S.emptyAnswers))
    assert.is_nil(next(S.ownedAwaitingKind))
    assert.is_nil(next(S.bagLocationCache))
    assert.is_nil(S.quotes[42])
    assert.is_false(S.quotesSeeded)
    assert.same({}, GC.Sell._lateAnswers)
    assert.is_nil(GC.Sell._owedUntil)
    assert.equal(expiry + 1, S.quoteExpiryGeneration)
    assert.equal(repeatToken + 1, S.walkRepeatToken)
    assert.equal(watchdog + 1, S.watchdogToken)
    assert.is_nil(S.postingRow)
    assert.is_nil(S.repostingRow)
    assert.is_nil(S.removingRow)
  end)

  it("keeps what outlives a visit: drain tombstones, positions, typed prices, the deck, cancelled lots", function()
    S.refresh.drain["commodity:42"] = { abandonedGeneration = 1, terminals = 1, at = 1 }
    S.refresh.progressAt, S.refresh.bulkWanted, S.refresh.ownedWanted = 5, true, true
    local positions, ownedLots, bagStock = { { itemID = 1 } }, { { auctionID = 7 } }, { { itemID = 1 } }
    S.positions, S.ownedLots, S.bagStock = positions, ownedLots, bagStock
    S.priceOverrides["commodity:1"] = 500
    S.filterMode = "listed"
    S.rowPlaces["commodity:1"] = 3
    S.queueEntries = { { positionKey = "commodity:1" } }
    GC.Sell.cancelledLots[7] = { at = 1 }

    GC.Sell.Reset()

    assert.is_table(S.refresh.drain["commodity:42"])
    assert.equal(5, S.refresh.progressAt)
    assert.is_true(S.refresh.bulkWanted)
    assert.is_true(S.refresh.ownedWanted)
    assert.equal(positions, S.positions)
    assert.equal(ownedLots, S.ownedLots)
    assert.equal(bagStock, S.bagStock)
    assert.equal(500, S.priceOverrides["commodity:1"])
    assert.equal("listed", S.filterMode)
    assert.equal(3, S.rowPlaces["commodity:1"])
    assert.equal("commodity:1", S.queueEntries[1].positionKey)
    assert.is_table(GC.Sell.cancelledLots[7])
  end)
end)
