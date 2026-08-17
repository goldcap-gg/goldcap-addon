local helper = require("spec.spec_helper")

describe("Sell view model", function()
  local GC

  before_each(function()
    GC = {}
    helper.loadModule("UI/SellViewModel.lua", GC)
  end)

  it("shows mixed sources and filters the same position into both source views", function()
    local position = { positionKey = "commodity:42",
      sources = { goldcap = 100, auction_house = 50 }, coverage = "COMPLETE" }
    assert.equal("GC ×100 · AH ×50", GC.SellViewModel.SourceText(position))
    assert.same({ position }, GC.SellViewModel.Filter({ position }, "goldcap"))
    assert.same({ position }, GC.SellViewModel.Filter({ position }, "auction_house"))
  end)

  it("renders unknown summary instead of zero profit", function()
    local text = GC.SellViewModel.SummaryText({ knownCost = 1000,
      listedValue = 2000, profit = nil, partialCount = 1, unknownCount = 2 })
    assert.equal("Unknown · 1 partial · 2 missing", text.profit)
  end)

  it("puts partial and unknown positions in the missing-cost view", function()
    local partial = { coverage = "PARTIAL" }
    local unknown = { coverage = "UNKNOWN" }
    local complete = { coverage = "COMPLETE" }
    assert.same({ partial, unknown }, GC.SellViewModel.Filter({ partial, unknown, complete }, "missing_cost"))
  end)

  it("[FINAL I3] shows exact partial known cost with coverage while Set cost stays separate", function()
    local partial = { coverage = "PARTIAL", knownCost = 101, knownQty = 2, exposureQty = 5 }
    assert.equal("101 · 2/5 covered", GC.SellViewModel.CostText(partial))
    local expansion = GC.SellViewModel.Expansion(partial)
    assert.equal("2/5 covered", expansion.coverageText)
  end)

  it("exposes every batch, owned lot, and position detail without changing FIFO data", function()
    local position = {
      positionKey = "commodity:42", coverage = "PARTIAL", quoteAge = 3, ahead = 4,
      outlook = { days = 2, tier = "OK" }, recommendation = "Post", batches = {
        { source = "goldcap", acquiredAt = 10, originalQty = 3, remainingQty = 2,
          allocatedQty = 1, unitCost = 50, totalCost = 100, sniperEvidenceKey = "capture:1" },
      }, ownedLots = { { auctionID = 7, quantity = 1, unitPrice = 99 } },
    }
    local expanded = GC.SellViewModel.Expansion(position)
    assert.equal("FIFO allocations", expanded.note)
    assert.equal("goldcap", expanded.batches[1].source)
    assert.equal(10, expanded.batches[1].acquiredAt)
    assert.equal(3, expanded.batches[1].originalQty)
    assert.equal(2, expanded.batches[1].remainingQty)
    assert.equal(1, expanded.batches[1].allocatedQty)
    assert.equal(50, expanded.batches[1].unitCost)
    assert.equal(100, expanded.batches[1].totalCost)
    assert.equal("captured", expanded.batches[1].evidence)
    assert.equal(7, expanded.ownedLots[1].auctionID)
    assert.equal(3, expanded.quoteAge)
    assert.equal(4, expanded.ahead)
    assert.equal(2, expanded.days)
    assert.equal("Post", expanded.recommendation)
    assert.equal(3, position.batches[1].originalQty)
    assert.equal(50, position.batches[1].unitCost)
    assert.not_equal(position.batches[1], expanded.batches[1])
  end)

  it("does not mutate a deep position input through any pure view method", function()
    local position = { positionKey = "commodity:42", coverage = "COMPLETE", sources = { goldcap = 1 },
      batches = { { id = "a", remainingQty = 1, remainingTotal = 10, evidenceKeys = { x = true } } },
      ownedLots = { { auctionID = 1, quantity = 1, allocation = { allocations = { { batchID = "a", quantity = 1 } } } } },
      allocations = { { batchID = "a", quantity = 1 } }, outlook = { days = 1 }, recommendation = { action = "repost", rec = { unit = 9 } } }
    local snapshot = { positionKey = "commodity:42", coverage = "COMPLETE", sources = { goldcap = 1 },
      batches = { { id = "a", remainingQty = 1, remainingTotal = 10, evidenceKeys = { x = true } } },
      ownedLots = { { auctionID = 1, quantity = 1, allocation = { allocations = { { batchID = "a", quantity = 1 } } } } },
      allocations = { { batchID = "a", quantity = 1 } }, outlook = { days = 1 }, recommendation = { action = "repost", rec = { unit = 9 } } }
    GC.SellViewModel.Filter({ position }, "all")
    GC.SellViewModel.SourceText(position); GC.SellViewModel.CostText(position); GC.SellViewModel.ProfitText(position)
    GC.SellViewModel.SummaryText({ knownCost = 10, listedValue = 12, profit = 2 })
    GC.SellViewModel.Expansion(position)
    assert.same(snapshot, position)
  end)

  it("[WAVE2 I4] exposes the display quote with an explicit fresh or stale state", function()
    local fresh = GC.SellViewModel.Expansion({ displayMarketUnit = 12345, freshMarketUnit = 12345,
      quoteAge = 3 })
    assert.equal(12345, fresh.displayMarketUnit)
    assert.equal("fresh", fresh.marketState)
    assert.is_true(fresh.marketFresh)
    assert.is_false(fresh.marketStale)
    assert.equal(3, fresh.quoteAge)

    local stale = GC.SellViewModel.Expansion({ displayMarketUnit = 12345, freshMarketUnit = nil,
      quoteAge = 11 })
    assert.equal(12345, stale.displayMarketUnit)
    assert.equal("stale", stale.marketState)
    assert.is_false(stale.marketFresh)
    assert.is_true(stale.marketStale)
    assert.equal(11, stale.quoteAge)
  end)

  it("[I2] maps internal acquisition evidence to stable semantic labels", function()
    local expanded = GC.SellViewModel.Expansion({ batches = {
      { source = "goldcap", remainingQty = 1, remainingTotal = 1, sniperEvidenceKey = "capture:1" },
      { source = "auction_house", remainingQty = 1, remainingTotal = 1, mailEvidenceKey = "mail:2" },
      { source = "manual", remainingQty = 1, remainingTotal = 1 },
      { source = "auction_house", remainingQty = 1, remainingTotal = 1 },
    } })
    assert.equal("captured", expanded.batches[1].evidence)
    assert.equal("mail-confirmed", expanded.batches[2].evidence)
    assert.equal("manual", expanded.batches[3].evidence)
    assert.equal("unknown evidence", expanded.batches[4].evidence)
  end)

  it("collapses adjacent purchases at one price into a single counted line", function()
    local expanded = GC.SellViewModel.Expansion({ batches = {
      { id = "a", source = "goldcap", acquiredAt = 100, originalQty = 200, remainingQty = 200,
        allocatedQty = 0, unitCost = 198, totalCost = 39600, sniperEvidenceKey = "capture:1" },
      { id = "b", source = "goldcap", acquiredAt = 250, originalQty = 200, remainingQty = 150,
        allocatedQty = 50, unitCost = 198, totalCost = 39600, sniperEvidenceKey = "capture:2" },
      { id = "c", source = "goldcap", acquiredAt = 300, originalQty = 5, remainingQty = 5,
        allocatedQty = 0, unitCost = 220, totalCost = 1100, sniperEvidenceKey = "capture:3" },
    } })
    assert.equal(2, #expanded.batches)
    local merged = expanded.batches[1]
    assert.equal(2, merged.purchases)
    assert.equal(400, merged.originalQty)
    assert.equal(350, merged.remainingQty)
    assert.equal(50, merged.allocatedQty)
    assert.equal(198, merged.unitCost)
    assert.equal(79200, merged.totalCost)
    assert.equal(100, merged.acquiredAtFirst)
    assert.equal(250, merged.acquiredAtLast)
    assert.equal("goldcap", merged.source)
    assert.equal("captured", merged.evidence)
    -- The odd-priced purchase stays its own uncounted line.
    assert.equal(220, expanded.batches[2].unitCost)
    assert.is_nil(expanded.batches[2].purchases)
  end)

  it("keeps purchases apart when price, evidence, or adjacency differs", function()
    local expanded = GC.SellViewModel.Expansion({ batches = {
      -- Same price, different evidence: a confirmed invoice never merges with a guess.
      { source = "auction_house", originalQty = 1, remainingQty = 1, unitCost = 100, totalCost = 100,
        mailEvidenceKey = "mail:1" },
      { source = "auction_house", originalQty = 1, remainingQty = 1, unitCost = 100, totalCost = 100 },
      -- Two 50s separated by a 60: merging across the price change would re-order the
      -- oldest-first story the group's own hint promises, so all three stay put.
      { source = "goldcap", originalQty = 1, remainingQty = 1, unitCost = 50, totalCost = 50,
        sniperEvidenceKey = "c:1" },
      { source = "goldcap", originalQty = 1, remainingQty = 1, unitCost = 60, totalCost = 60,
        sniperEvidenceKey = "c:2" },
      { source = "goldcap", originalQty = 1, remainingQty = 1, unitCost = 50, totalCost = 50,
        sniperEvidenceKey = "c:3" },
    } })
    assert.equal(5, #expanded.batches)
  end)
  describe("Filter", function()
    local rows = {
      { positionKey = "a", bagQty = 5, listedQty = 0, coverage = "UNKNOWN" },
      { positionKey = "b", bagQty = 0, listedQty = 2, coverage = "COMPLETE" },
      { positionKey = "c", bagQty = 0, listedQty = 0, coverage = "PARTIAL" },
    }

    local function keys(filtered)
      local out = {}
      for i, row in ipairs(filtered) do out[i] = row.positionKey end
      return out
    end

    it("narrows to what is in the bags", function()
      assert.same({ "a" }, keys(GC.SellViewModel.Filter(rows, "sellable")))
    end)

    it("narrows to what is already up for sale", function()
      assert.same({ "b" }, keys(GC.SellViewModel.Filter(rows, "listed")))
    end)

    it("still narrows to incomplete cost", function()
      assert.same({ "a", "c" }, keys(GC.SellViewModel.Filter(rows, "missing_cost")))
    end)
  end)

  -- Build sorts by scope and position key, which is stable and means nothing to a
  -- seller: it put an item you could list right now below thirty rows of finished
  -- business, which is most of why the answer to "what can I sell" was invisible.
  describe("Order", function()
    local function keys(ordered)
      local out = {}
      for i, row in ipairs(ordered) do out[i] = row.positionKey end
      return out
    end

    it("lifts postable stock over everything else, priced first", function()
      assert.same({ "priced", "unpriced", "listed", "idle" }, keys(GC.SellViewModel.Order({
        { positionKey = "listed", listedQty = 3, listedValue = 900 },
        { positionKey = "unpriced", bagQty = 2 },
        { positionKey = "idle" },
        { positionKey = "priced", bagQty = 1, freshMarketUnit = 10 },
      })))
    end)

    it("puts the most valuable postable stack first", function()
      assert.same({ "big", "small" }, keys(GC.SellViewModel.Order({
        { positionKey = "small", bagQty = 1, freshMarketUnit = 100 },
        { positionKey = "big", bagQty = 50, freshMarketUnit = 100 },
      })))
    end)

    it("leaves everything it is not ranking exactly where it was", function()
      -- Reshuffling rows a player is not acting on costs them their place on the
      -- screen for no gain, so ties fall back to the incoming order.
      assert.same({ "z", "m", "a" }, keys(GC.SellViewModel.Order({
        { positionKey = "z", listedQty = 1, listedValue = 5 },
        { positionKey = "m" },
        { positionKey = "a", listedQty = 9, listedValue = 900 },
      })))
    end)
  end)
end)
