local helper = require("spec.spec_helper")

describe("SniperDecision ceiling mode (WoW: Forever)", function()
  local GC, S
  before_each(function()
    GC = helper.loadModule("Core/Book.lua")
    helper.loadModule("Core/Caps.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    S = GC.SniperDecision
  end)

  local BOOK = { { unitPrice = 8, quantity = 5 }, { unitPrice = 9, quantity = 10 },
    { unitPrice = 12, quantity = 40 }, { unitPrice = 13, quantity = 100 } }

  local function vendorInput(over)
    local i = { ceilingUnit = 12, kind = "vendor", exitUnit = 13, levels = BOOK,
      limits = { maxQuantity = 200, budget = 100000 }, minimumProfit = 20 }
    for k, v in pairs(over or {}) do i[k] = v end
    return i
  end

  describe("EvaluateCeiling", function()
    it("buys every unit at or under the ceiling, cheapest first, and says what it makes", function()
      local d = S.EvaluateCeiling(vendorInput())
      assert.equal("SAFE", d.status); assert.is_true(d.buyable)
      assert.equal(55, d.quantity)
      assert.equal(610, d.entryTotal)
      assert.equal(11, d.entryUnitDisplay)
      assert.equal(8, d.unit)
      assert.equal(12, d.ceiling); assert.equal("vendor", d.forever)
      assert.equal(13, d.exitUnit)
      assert.equal(105, d.stressProfit)    -- 13 * 55 - 610
      assert.equal(0, d.deposit)
      assert.equal(20, d.requiredProfit)
      assert.same({}, d.reasons)
    end)

    it("stops where the wallet limit bites", function()
      local d = S.EvaluateCeiling(vendorInput({ limits = { maxQuantity = 200, budget = 100 } }))
      assert.equal(11, d.quantity)         -- 5 at 8c, then 6 at 9c: 94c
      assert.equal(94, d.entryTotal)
      assert.equal(49, d.stressProfit)
      assert.is_true(d.buyable)
    end)

    it("refuses when nothing is at or under the ceiling any more", function()
      local d = S.EvaluateCeiling(vendorInput({ levels = { { unitPrice = 13, quantity = 100 } } }))
      assert.equal("AVOID", d.status); assert.is_false(d.buyable)
      assert.same({ "price_rose" }, d.reasons)
    end)

    it("says the wallet limit when units are there but not one fits it", function()
      local d = S.EvaluateCeiling(vendorInput({ limits = { maxQuantity = 200, budget = 5 } }))
      assert.same({ "capital_limit" }, d.reasons)
    end)

    it("holds a server quote to what those units cost on the book", function()
      assert.is_true(S.EvaluateCeiling(vendorInput({ fixedQuantity = 55, quotedTotal = 610 })).buyable)
      local d = S.EvaluateCeiling(vendorInput({ fixedQuantity = 55, quotedTotal = 611 }))
      assert.is_false(d.buyable)
      assert.same({ "requote_broke_safety" }, d.reasons)
    end)

    it("never fills a fixed quantity with units above the ceiling", function()
      local d = S.EvaluateCeiling(vendorInput({ fixedQuantity = 60 }))
      assert.is_false(d.buyable)
      assert.same({ "book_exhausted" }, d.reasons)
    end)

    it("refuses a buy under the minimum profit and still shows its figures", function()
      local d = S.EvaluateCeiling(vendorInput({ minimumProfit = 200 }))
      assert.is_false(d.buyable)
      assert.same({ "profit_below_minimum" }, d.reasons)
      assert.equal(55, d.quantity); assert.equal(105, d.stressProfit); assert.equal(200, d.requiredProfit)
    end)

    it("prices a market resale after the 5% cut and the deposit", function()
      local d = S.EvaluateCeiling({ ceilingUnit = 70, kind = "market", exitUnit = 100,
        levels = { { unitPrice = 60, quantity = 10 } }, limits = { maxQuantity = 200, budget = 100000 },
        depositForQuantity = function(q) return q * 2 end, minimumProfit = 20 })
      assert.is_true(d.buyable)
      assert.equal(20, d.deposit)
      assert.equal(330, d.stressProfit)    -- 1000 - 50 - 600 - 20
    end)

    it("refuses a market buy whose deposit the auction house would not quote", function()
      local d = S.EvaluateCeiling({ ceilingUnit = 70, kind = "market", exitUnit = 100,
        levels = { { unitPrice = 60, quantity = 10 } }, limits = { maxQuantity = 200, budget = 100000 },
        depositForQuantity = function() return nil end, minimumProfit = 20 })
      assert.same({ "deposit_missing" }, d.reasons)
    end)

    it("obeys the purchases kill switch like every SAFE answer", function()
      S.SAFE_PURCHASES_ENABLED = false
      local d = S.EvaluateCeiling(vendorInput())
      S.SAFE_PURCHASES_ENABLED = true
      assert.equal("WATCH", d.status); assert.is_false(d.buyable)
      assert.same({ "shadow_validation" }, d.reasons)
    end)

    it("fails closed on missing limits, a bad ceiling or an unknown kind", function()
      assert.same({ "invalid_input" }, S.EvaluateCeiling(vendorInput({ limits = false })).reasons)
      assert.same({ "invalid_input" }, S.EvaluateCeiling(vendorInput({ ceilingUnit = 0 })).reasons)
      assert.same({ "invalid_input" }, S.EvaluateCeiling(vendorInput({ kind = "retail" })).reasons)
      assert.same({ "invalid_input" }, S.EvaluateCeiling(nil).reasons)
    end)

    it("fails closed on a limits table missing or mistyping maxQuantity or budget", function()
      assert.same({ "invalid_input" },
        S.EvaluateCeiling(vendorInput({ limits = { maxQuantity = 200 } })).reasons)     -- no budget
      assert.same({ "invalid_input" },
        S.EvaluateCeiling(vendorInput({ limits = { budget = 100000 } })).reasons)       -- no maxQuantity
      assert.same({ "invalid_input" },
        S.EvaluateCeiling(vendorInput({ limits = { maxQuantity = 0, budget = 100000 } })).reasons)
      assert.same({ "invalid_input" },
        S.EvaluateCeiling(vendorInput({ limits = { maxQuantity = "200", budget = 100000 } })).reasons)
      assert.same({ "invalid_input" },
        S.EvaluateCeiling(vendorInput({ limits = { maxQuantity = 200, budget = -1 } })).reasons)
    end)

    it("drops a malformed level instead of crashing, and still prices the good ones", function()
      local d = S.EvaluateCeiling(vendorInput({ levels = { "junk", { unitPrice = 8, quantity = 5 } } }))
      assert.is_true(d.buyable)
      assert.equal(5, d.quantity); assert.equal(40, d.entryTotal)
    end)

    it("refuses cleanly, never crashes, when every level is malformed", function()
      local d = S.EvaluateCeiling(vendorInput({ levels = { "junk", { quantity = 5 }, { unitPrice = -1, quantity = 5 } } }))
      assert.same({ "price_rose" }, d.reasons)
    end)

    it("fails closed on a negative or non-integer minimum profit", function()
      assert.same({ "invalid_input" }, S.EvaluateCeiling(vendorInput({ minimumProfit = -1 })).reasons)
      assert.same({ "invalid_input" }, S.EvaluateCeiling(vendorInput({ minimumProfit = 1.5 })).reasons)
    end)
  end)

  describe("EvaluateCeilingLot", function()
    local LOTS = { { auctionID = 1, buyout = 150, quantity = 1, itemLevel = 20 },
      { auctionID = 2, buyout = 60, quantity = 1, itemLevel = 18 },
      { auctionID = 3, quantity = 1 } }       -- bid-only: no buyout

    it("names the cheapest lot at or under the ceiling, and its exact profit", function()
      local d = S.EvaluateCeilingLot({ ceilingUnit = 99, kind = "vendor", exitUnit = 100, lots = LOTS,
        minimumProfit = 20 })
      assert.equal("WATCH", d.status); assert.is_false(d.buyable)
      assert.same({ auctionID = 2, buyout = 60, quantity = 1, itemLevel = 18 }, d.candidate)
      assert.equal(60, d.entryTotal); assert.equal(40, d.stressProfit)
      assert.equal(40, d.estProfit); assert.equal(100, d.reference)
      assert.equal(99, d.ceiling); assert.equal("vendor", d.forever)
    end)

    it("refuses when every lot is above the ceiling, or the profit is under the minimum", function()
      assert.same({ "price_rose" }, S.EvaluateCeilingLot({ ceilingUnit = 50, kind = "vendor",
        exitUnit = 51, lots = LOTS, minimumProfit = 1 }).reasons)
      local d = S.EvaluateCeilingLot({ ceilingUnit = 99, kind = "vendor", exitUnit = 100, lots = LOTS,
        minimumProfit = 50 })
      assert.same({ "profit_below_minimum" }, d.reasons)
      assert.is_nil(d.candidate)
    end)

    it("is vendor-only", function()
      assert.same({ "invalid_input" }, S.EvaluateCeilingLot({ ceilingUnit = 99, kind = "market",
        exitUnit = 100, lots = LOTS, minimumProfit = 1 }).reasons)
    end)

    it("prices a multi-unit lot by its per-unit price against the ceiling, and profit on the whole lot", function()
      local d = S.EvaluateCeilingLot({ ceilingUnit = 99, kind = "vendor", exitUnit = 100,
        lots = { { auctionID = 5, buyout = 480, quantity = 5, itemLevel = 10 } }, minimumProfit = 20 })
      assert.equal("WATCH", d.status); assert.is_false(d.buyable)
      assert.same({ auctionID = 5, buyout = 480, quantity = 5, itemLevel = 10 }, d.candidate)
      assert.equal(5, d.quantity); assert.equal(480, d.entryTotal); assert.equal(96, d.entryUnitDisplay)
      assert.equal(20, d.stressProfit); assert.equal(20, d.estProfit)    -- 100 * 5 - 480
    end)

    it("fails closed on a negative or non-integer minimum profit", function()
      assert.same({ "invalid_input" }, S.EvaluateCeilingLot({ ceilingUnit = 99, kind = "vendor",
        exitUnit = 100, lots = LOTS, minimumProfit = -1 }).reasons)
      assert.same({ "invalid_input" }, S.EvaluateCeilingLot({ ceilingUnit = 99, kind = "vendor",
        exitUnit = 100, lots = LOTS, minimumProfit = 1.5 }).reasons)
    end)
  end)

  it("explains the new reason in words", function()
    assert.is_true(S.REASONS.profit_below_minimum)
    assert.equal("What this buy would make is under your minimum profit.", S.ReasonText("profit_below_minimum"))
  end)
end)
