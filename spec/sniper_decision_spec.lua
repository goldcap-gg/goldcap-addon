local helper = require("spec.spec_helper")

describe("SniperDecision", function()
  local GC

  local function validInput()
    return {
      now = 100000,
      market = {
        kind = "region_commodity", source = "import", sourceAt = 92800,
        marketValue = 3000000, stressUnit = 3000000, soldPerDay = 100000,
        sellThroughBps = 7000, liquidityConfidence = 70, currentQty = 0,
        listings = 3, observations = 12, madBps = 0, trend24hPct = -9,
      },
      live = { itemID = 42, levels = { { unitPrice = 1000000, quantity = 200 }, { unitPrice = 3000001, quantity = 1 } } },
      walletCopper = 10000000000,
      depositForQuantity = function() return 0 end,
      config = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      },
    }
  end

  local function evaluate(input)
    return GC.SniperDecision.Evaluate(input or validInput())
  end

  local function assertReason(result, reason)
    assert.is_true((function()
      for _, got in ipairs(result.reasons) do if got == reason then return true end end
      return false
    end)())
  end

  before_each(function()
    GC = helper.loadModule("Core/Book.lua")
    helper.loadModule("Core/SniperDecision.lua", GC)
  end)

  it("exposes the versioned immutable safe decision contract", function()
    local result = evaluate()
    assert.equal(1, GC.SniperDecision.VERSION)
    assert.equal("SAFE", result.computedStatus)
    assert.equal("WATCH", result.status)
    assert.is_false(result.buyable)
    assert.equal(200, result.quantity)
    assert.equal(200000000, result.entryTotal)
    assert.equal(1000000, result.entryUnitDisplay)
    assert.equal(3000000, result.exitUnit)
  end)

  it("shadows a mathematically SAFE decision while retaining its economic evidence", function()
    local result = evaluate()
    assert.is_false(GC.SniperDecision.SAFE_PURCHASES_ENABLED)
    assert.equal("SAFE", result.computedStatus)
    assert.equal("WATCH", result.status)
    assert.is_false(result.buyable)
    assert.equal("shadow_validation", result.reasons[1])
  end)

  it("leaves an economic AVOID public and without a shadow reason", function()
    local input = validInput(); input.market.listings = 2
    local result = evaluate(input)
    assert.equal("AVOID", result.computedStatus)
    assert.equal("AVOID", result.status)
    assert.is_false(result.buyable)
    assert.not_equal("shadow_validation", result.reasons[1])
  end)

  it("accepts an import exactly 7200 seconds old", function()
    local result = evaluate()
    assert.equal("SAFE", result.computedStatus)
  end)

  it("watches an import 7201 seconds old", function()
    local input = validInput(); input.market.sourceAt = 92799
    local result = evaluate(input)
    assert.equal("WATCH", result.status)
    assertReason(result, "source_stale")
  end)

  it("watches sparse 11-observation history but accepts 12", function()
    local sparse = validInput(); sparse.market.observations = 11
    assert.equal("WATCH", evaluate(sparse).status)
    assert.equal("SAFE", evaluate(validInput()).computedStatus)
  end)

  it("avoids measured listings below three after live verification", function()
    local input = validInput(); input.market.listings = 2
    local result = evaluate(input)
    assert.equal("AVOID", result.status)
    assertReason(result, "listings_too_low")
  end)

  it("avoids measured sold-per-day below three", function()
    local input = validInput(); input.market.soldPerDay = 2.9
    local result = evaluate(input)
    assert.equal("AVOID", result.status)
    assertReason(result, "velocity_too_low")
  end)

  it("accepts the exact sold-per-day floor of three", function()
    local input = validInput()
    input.market.soldPerDay = 3
    input.live.levels = { { unitPrice = 1000000, quantity = 1 }, { unitPrice = 3000001, quantity = 1 } }
    assert.equal("SAFE", evaluate(input).computedStatus)
  end)

  it("avoids sell-through below 7000 bps and accepts its exact floor", function()
    local low = validInput(); low.market.sellThroughBps = 6999
    assert.equal("AVOID", evaluate(low).status)
    assert.equal("SAFE", evaluate(validInput()).computedStatus)
  end)

  it("avoids confidence below 70 and accepts its exact floor", function()
    local low = validInput(); low.market.liquidityConfidence = 69
    assert.equal("AVOID", evaluate(low).status)
    assert.equal("SAFE", evaluate(validInput()).computedStatus)
  end)

  it("avoids a trend at minus ten but not minus nine", function()
    local falling = validInput(); falling.market.trend24hPct = -10
    assert.equal("AVOID", evaluate(falling).status)
    assert.equal("SAFE", evaluate(validInput()).computedStatus)
  end)

  it("watches scan candidates, realm items, bundled data, and estimated values", function()
    local scan = validInput(); scan.live.levels = nil
    assertReason(evaluate(scan), "live_verification_required")
    local realm = validInput(); realm.market.kind = "realm_item"
    assertReason(evaluate(realm), "realm_item_unverified")
    local bundled = validInput(); bundled.market.source = "bundled"
    assertReason(evaluate(bundled), "bundled_data_unverified")
    local estimated = validInput(); estimated.market.estimated = true
    assertReason(evaluate(estimated), "market_value_estimated")
  end)

  it("turns missing market facts into AVOID only once live levels exist", function()
    local beforeLive = validInput(); beforeLive.live.levels = nil; beforeLive.market.soldPerDay = nil
    assert.equal("WATCH", evaluate(beforeLive).status)
    local afterLive = validInput(); afterLive.market.soldPerDay = nil
    local result = evaluate(afterLive)
    assert.equal("AVOID", result.status)
    assertReason(result, "velocity_missing")
  end)

  it("avoids a missing book, partial fill, or missing competing ask", function()
    local absent = validInput(); absent.live.levels = {}
    assertReason(evaluate(absent), "book_missing")
    local partial = validInput(); partial.live.fixedQuantity = 202
    assertReason(evaluate(partial), "book_exhausted")
    local empty = validInput(); empty.live.fixedQuantity = 200
    empty.live.levels = { { unitPrice = 1000000, quantity = 200 } }
    assertReason(evaluate(empty), "competing_ask_missing")
  end)

  it("requires a full 24-hour deposit", function()
    local input = validInput(); input.live.fixedQuantity = 200; input.depositForQuantity = function() return nil end
    local result = evaluate(input)
    assert.equal("AVOID", result.status)
    assertReason(result, "deposit_missing")
  end)

  it("allows an entry at the exact 5 percent capital share", function()
    local input = validInput()
    input.live.fixedQuantity = 1
    input.live.levels = { { unitPrice = 1000000, quantity = 1 }, { unitPrice = 3000001, quantity = 1 } }
    input.walletCopper = 20000000
    local result = evaluate(input)
    assert.equal("SAFE", result.computedStatus)
    assert.equal(1000000, result.entryTotal)
  end)

  it("uses the two-percent demand share and the 200 hard cap", function()
    local input = validInput(); input.market.soldPerDay = 100
    input.live.levels = { { unitPrice = 1000000, quantity = 1 }, { unitPrice = 3000001, quantity = 1 } }
    local demand = evaluate(input)
    assert.equal(1, demand.quantity)

    assert.equal(200, evaluate(validInput()).quantity)
  end)

  it("uses the exact two-percent demand formula before the hard cap", function()
    local input = validInput()
    input.market.soldPerDay = 1000
    input.live.levels = { { unitPrice = 1000000, quantity = 17 }, { unitPrice = 3000001, quantity = 1 } }
    local result = evaluate(input)
    assert.equal("SAFE", result.computedStatus)
    assert.equal(17, result.quantity)
    assertReason(result, "demand_limit")
  end)

  it("uses ceiling AH cut and accepts the exact 100g stress-profit boundary", function()
    local input = validInput()
    input.live.fixedQuantity = 1
    input.live.levels = { { unitPrice = 1000000, quantity = 1 }, { unitPrice = 2105265, quantity = 1 } }
    local result = evaluate(input)
    assert.equal("SAFE", result.computedStatus)
    assert.equal(105264, result.ahCut)
    assert.equal(1000000, result.stressProfit)
    assert.equal(1000000, result.requiredProfit)
  end)

  it("accepts an exact ten-percent ROI boundary when it exceeds the 100g floor", function()
    local input = validInput()
    input.live.fixedQuantity = 1
    input.live.levels = { { unitPrice = 20000000, quantity = 1 }, { unitPrice = 23157896, quantity = 1 } }
    input.market.stressUnit = 23157895
    local result = evaluate(input)
    assert.equal("SAFE", result.computedStatus)
    assert.equal(2000000, result.stressProfit)
    assert.equal(2000000, result.requiredProfit)
  end)

  it("uses the configured fractional ROI without basis-point rounding", function()
    local input = validInput()
    input.live.fixedQuantity = 1
    input.live.levels = { { unitPrice = 100000000, quantity = 1 }, { unitPrice = 115790528, quantity = 1 } }
    input.market.stressUnit = 115790527
    input.config.minimumRoi = 0.10001
    local result = evaluate(input)
    assert.equal("SAFE", result.computedStatus)
    assert.equal(10001000, result.stressProfit)
    assert.equal(10001000, result.requiredProfit)
  end)

  it("enforces a configured profit floor above the safety minimum", function()
    local input = validInput()
    input.live.fixedQuantity = 1
    input.live.levels = { { unitPrice = 1000000, quantity = 1 }, { unitPrice = 392473686, quantity = 1 } }
    input.market.stressUnit = 392473685
    input.config.minimumProfitCopper = 500000000
    local result = evaluate(input)
    assert.equal("AVOID", result.status)
    assertReason(result, "stress_profit_below_buffer")
    assert.equal("requote_broke_safety", result.reasons[#result.reasons])
  end)

  it("selects the largest passing quantity using exact book totals", function()
    local input = validInput()
    input.live.levels = {
      { unitPrice = 1000000, quantity = 1 },
      { unitPrice = 1000001, quantity = 1 },
      { unitPrice = 3000001, quantity = 1 },
    }
    local result = evaluate(input)
    assert.equal("SAFE", result.computedStatus)
    assert.equal(2, result.quantity)
    assert.equal(2000001, result.entryTotal)
    assert.equal(1000000, result.entryUnitDisplay)
  end)

  it("fails a sub-five-percent requote that crosses safety, with the fixed quantity retained", function()
    local input = validInput()
    input.live.fixedQuantity = 1
    input.live.quotedTotal = 1040000
    input.live.levels = { { unitPrice = 1000000, quantity = 1 }, { unitPrice = 2105265, quantity = 1 } }
    local result = evaluate(input)
    assert.equal("AVOID", result.status)
    assert.equal(1, result.quantity)
    assert.equal("requote_broke_safety", result.reasons[#result.reasons])
  end)

  it("keeps a fixed quantity safe when a ten-percent requote clears the buffer", function()
    local input = validInput()
    input.live.fixedQuantity = 1
    input.live.quotedTotal = 1100000
    input.live.levels = { { unitPrice = 1000000, quantity = 1 }, { unitPrice = 4000001, quantity = 1 } }
    local result = evaluate(input)
    assert.equal("SAFE", result.computedStatus)
    assert.equal(1, result.quantity)
  end)

  it("never lets a fixed quantity bypass the configured 200-unit cap", function()
    local input = validInput()
    input.live.fixedQuantity = 201
    input.live.levels = { { unitPrice = 1000000, quantity = 201 }, { unitPrice = 3000001, quantity = 1 } }
    local result = evaluate(input)
    assert.equal("AVOID", result.status)
    assert.equal(201, result.quantity)
    assertReason(result, "demand_limit")
    assert.equal("requote_broke_safety", result.reasons[#result.reasons])
  end)

  it("never lets a fixed quantity exceed the computed demand cap", function()
    local input = validInput()
    input.market.soldPerDay = 100
    input.live.fixedQuantity = 2
    input.live.levels = { { unitPrice = 1000000, quantity = 2 }, { unitPrice = 3000001, quantity = 1 } }
    local result = evaluate(input)
    assert.equal("AVOID", result.status)
    assert.equal(2, result.quantity)
    assertReason(result, "demand_limit")
    assert.equal("requote_broke_safety", result.reasons[#result.reasons])
  end)

  it("finalizes a fixed evaluation without live levels as AVOID", function()
    local input = validInput()
    input.live.fixedQuantity = 1
    input.live.levels = nil
    local result = evaluate(input)
    assert.equal("AVOID", result.status)
    assertReason(result, "live_verification_required")
    assert.equal("requote_broke_safety", result.reasons[#result.reasons])
  end)

  it("fails closed on overflowing or underflowing profit intermediates", function()
    local overflow = validInput()
    overflow.live.fixedQuantity = 2
    overflow.live.levels = { { unitPrice = 1, quantity = 2 }, { unitPrice = 9007199254740991, quantity = 1 } }
    overflow.market.stressUnit = 9007199254740991
    local overflowResult = evaluate(overflow)
    assertReason(overflowResult, "invalid_input")
    assert.equal("requote_broke_safety", overflowResult.reasons[#overflowResult.reasons])

    local underflow = validInput()
    underflow.live.fixedQuantity = 1
    underflow.live.quotedTotal = 1000000000000000
    underflow.live.levels = { { unitPrice = 1, quantity = 1 }, { unitPrice = 2, quantity = 1 } }
    underflow.market.stressUnit = 1
    underflow.walletCopper = 9007199254740991
    underflow.config.maxCapitalShare = 0.20
    underflow.depositForQuantity = function() return 9007199254740991 end
    local underflowResult = evaluate(underflow)
    assertReason(underflowResult, "invalid_input")
    assert.equal("requote_broke_safety", underflowResult.reasons[#underflowResult.reasons])
  end)

  it("orders reasons by confidence, market risk, book, capital, and profit", function()
    local input = validInput()
    input.market.observations = 11; input.market.trend24hPct = -10
    input.walletCopper = 0
    local result = evaluate(input)
    assert.same({ "price_history_sparse", "market_falling", "capital_limit" }, result.reasons)
  end)

  it("clamps edited safety floors and fails closed for invalid input", function()
    local floors = validInput()
    floors.live.fixedQuantity = 1
    floors.live.levels = { { unitPrice = 1000000, quantity = 1 }, { unitPrice = 2105265, quantity = 1 } }
    floors.config.minimumProfitCopper = -1
    floors.config.minimumRoi = -1
    assert.equal(1000000, evaluate(floors).requiredProfit)

    local invalid = validInput(); invalid.config.minimumProfitCopper = "bad"
    assertReason(evaluate(invalid), "invalid_input")
    local unsafe = validInput(); unsafe.live.fixedQuantity = 1
    unsafe.live.levels = { { unitPrice = 9007199254740992, quantity = 1 }, { unitPrice = 9007199254740993, quantity = 1 } }
    assertReason(evaluate(unsafe), "invalid_input")
  end)
end)
