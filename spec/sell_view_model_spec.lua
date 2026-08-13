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

  it("exposes every batch, owned lot, and position detail without changing FIFO data", function()
    local position = {
      positionKey = "commodity:42", coverage = "PARTIAL", quoteAge = 3, ahead = 4,
      outlook = { days = 2, tier = "OK" }, recommendation = "Post", batches = {
        { source = "goldcap", acquiredAt = 10, originalQty = 3, remainingQty = 2,
          allocatedQty = 1, unitCost = 50, totalCost = 100, evidence = "Sniper buy" },
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
    assert.equal("Sniper buy", expanded.batches[1].evidence)
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
end)
