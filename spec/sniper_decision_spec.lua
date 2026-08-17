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

  local function assertNoReason(result, reason)
    for _, got in ipairs(result.reasons) do assert.not_equal(reason, got) end
  end

  before_each(function()
    GC = helper.loadModule("Core/Book.lua")
    helper.loadModule("Core/SniperDecision.lua", GC)
  end)

  it("exposes the versioned immutable safe decision contract", function()
    local result = evaluate()
    assert.equal(1, GC.SniperDecision.VERSION)
    assert.equal("SAFE", result.computedStatus)
    assert.equal("SAFE", result.status)
    assert.is_true(result.buyable)
    assert.equal(200, result.quantity)
    assert.equal(200000000, result.entryTotal)
    assert.equal(1000000, result.entryUnitDisplay)
    assert.equal(3000000, result.exitUnit)
  end)

  -- Activation branch: the release gate is open. The economic calculation is untouched by the
  -- flag -- only the final shaping in finalizePublicResult differs -- so both states are
  -- asserted here against the same fixture, and the shadow behaviour must remain intact and
  -- reachable by flipping the constant back.
  it("publishes a mathematically SAFE decision once purchases are enabled", function()
    local result = evaluate()
    assert.is_true(GC.SniperDecision.SAFE_PURCHASES_ENABLED)
    assert.equal("SAFE", result.computedStatus)
    assert.equal("SAFE", result.status)
    assert.is_true(result.buyable)
    assertNoReason(result, "shadow_validation")
  end)

  it("still shadows a mathematically SAFE decision whenever purchases are disabled", function()
    -- before_each reloads the module, so this mutation cannot leak into another example.
    GC.SniperDecision.SAFE_PURCHASES_ENABLED = false
    local result = evaluate()
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

  -- Three hours, calibrated to the upstream: Blizzard republishes commodity data roughly once
  -- an hour, so anything under two hours left no room for a single missed ingest cycle and the
  -- gate fired on ordinary healthy data. Three tolerates exactly one missed cycle and still
  -- rejects what this gate is for -- a dead Companion, an abandoned session, a day-old import.
  it("accepts an import exactly 10800 seconds old", function()
    local input = validInput(); input.market.sourceAt = 89200
    assert.equal("SAFE", evaluate(input).computedStatus)
  end)

  it("watches an import 10801 seconds old", function()
    local input = validInput(); input.market.sourceAt = 89199
    local result = evaluate(input)
    assert.equal("WATCH", result.status)
    assertReason(result, "source_stale")
  end)

  it("still accepts a two-hour-old import", function()
    local input = validInput(); input.market.sourceAt = 92800
    assert.equal("SAFE", evaluate(input).computedStatus)
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

  it("accepts a small high-return flip and chooses the quantity with the highest stress profit", function()
    local input = validInput()
    input.live.levels = {
      { unitPrice = 301700, quantity = 1 },
      { unitPrice = 450200, quantity = 1126 },
    }
    input.market.marketValue = 466454
    input.market.stressUnit = 450199
    input.config.minimumProfitCopper = 50000
    input.config.maxQuantity = 200
    input.walletCopper = 213290000
    input.depositForQuantity = function(quantity) return quantity * 1000 end

    local result = evaluate(input)

    assert.equal("SAFE", result.computedStatus)
    assert.equal(1, result.quantity)
    assert.equal(301700, result.entryTotal)
    assert.equal(124989, result.stressProfit)
    assert.equal(50000, result.requiredProfit)
  end)

  it("does not report capital_limit when an affordable quantity exists but misses profit", function()
    local input = validInput()
    input.live.levels = {
      { unitPrice = 1000000, quantity = 1 },
      { unitPrice = 1000001, quantity = 1 },
      { unitPrice = 3000001, quantity = 1 },
    }
    input.config.maxQuantity = 2
    input.config.minimumProfitCopper = 50000
    input.walletCopper = 30000000 -- five-percent budget is 1,500,000 copper

    local result = evaluate(input)

    assert.equal("AVOID", result.computedStatus)
    assertReason(result, "stress_profit_below_buffer")
    assertNoReason(result, "capital_limit")
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

  it("displays a fixed requote from its authoritative total, not the book average", function()
    local input = validInput()
    input.live.fixedQuantity = 2
    input.live.quotedTotal = 2100001
    input.live.levels = { { unitPrice = 1000000, quantity = 2 }, { unitPrice = 4000001, quantity = 1 } }
    local result = evaluate(input)
    assert.equal("SAFE", result.computedStatus)
    assert.equal(2, result.quantity)
    assert.equal(2100001, result.entryTotal)
    assert.equal(1050000, result.entryUnitDisplay)
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
    floors.live.levels = { { unitPrice = 50000, quantity = 1 }, { unitPrice = 1000001, quantity = 1 } }
    floors.market.stressUnit = 1000000
    floors.config.minimumProfitCopper = -1
    floors.config.minimumRoi = -1
    assert.equal(10000, evaluate(floors).requiredProfit)

    local invalid = validInput(); invalid.config.minimumProfitCopper = "bad"
    assertReason(evaluate(invalid), "invalid_input")
    local unsafe = validInput(); unsafe.live.fixedQuantity = 1
    unsafe.live.levels = { { unitPrice = 9007199254740992, quantity = 1 }, { unitPrice = 9007199254740993, quantity = 1 } }
    assertReason(evaluate(unsafe), "invalid_input")
  end)

  -- Discovery rows carry no order book, so most of Evaluate cannot run on them. But the market
  -- facts that come from the import decide several gates outright, and a row failing one of
  -- those can never become buyable no matter how the live book looks. PreScreen answers that
  -- much from the same thresholds, so the scan can stop advertising rows whose only possible
  -- outcome is an AVOID after the player has spent a click finding out.
  describe("PreScreen", function()
    local function screenable(overrides)
      local market = {
        sourceAt = 92800, stressUnit = 3000000, soldPerDay = 100000, sellThroughBps = 7000,
        liquidityConfidence = 70, currentQty = 0, listings = 3, madBps = 0, trend24hPct = -9,
      }
      for key, value in pairs(overrides or {}) do market[key] = value end
      return market
    end
    local config = { maxDailyDemandShare = 0.02, maxQuantity = 200 }

    local function screen(overrides)
      return GC.SniperDecision.PreScreen(screenable(overrides), config)
    end

    it("clears a market that passes every gate decidable without a book", function()
      assert.same({}, screen())
    end)

    it("names each hard gate a discovery row can never pass", function()
      assert.same({ "listings_too_low" }, screen({ listings = 2 }))
      assert.same({ "velocity_too_low" }, screen({ soldPerDay = 2 }))
      local noVelocity = screenable(); noVelocity.soldPerDay = nil
      assert.same({ "velocity_missing" }, GC.SniperDecision.PreScreen(noVelocity, config))
      assert.same({ "sell_through_too_low" }, screen({ sellThroughBps = 6999 }))
      assert.same({ "liquidity_confidence_low" }, screen({ liquidityConfidence = 69 }))
      assert.same({ "market_falling" }, screen({ trend24hPct = -10 }))
      assert.same({ "stress_exit_missing" }, screen({ stressUnit = 0 }))
    end)

    it("orders several failures the same way Evaluate does", function()
      assert.same({ "listings_too_low", "sell_through_too_low" },
        screen({ listings = 1, sellThroughBps = 100 }))
    end)

    -- Staleness is transient and applies to every row at once: emptying the whole list would
    -- hide the market rather than explain it, and the import-age banner already says so.
    it("does not screen out a row for a stale or estimated import", function()
      assert.same({}, screen({ sourceAt = 1 }))
      assert.same({}, screen({ estimated = true }))
    end)

    -- Evaluate floors its demand cap at 1, so the cap alone can never make a row hopeless; the
    -- only way it reaches zero is a velocity the gates above already reject.
    it("leaves a thin but qualifying market alone rather than inventing a demand limit", function()
      assert.same({}, screen({ soldPerDay = 3, currentQty = 100000000 }))
    end)

    it("fails closed on input it cannot read", function()
      assert.same({ "invalid_input" }, GC.SniperDecision.PreScreen(nil, config))
      assert.same({ "invalid_input" }, GC.SniperDecision.PreScreen(screenable(), nil))
    end)
  end)

  -- FullScan.RowsFromBrowse calls this at discovery time so the deals list can never advertise
  -- a quantity larger than what a live Check could actually approve. These fixtures are the
  -- measured gap documented alongside the fix: a 500-sold/5000-stock item was shown at a flat
  -- 200 units when the engine would only ever approve 1, etc.
  describe("DemandCap", function()
    local config = { maxDailyDemandShare = 0.02, maxQuantity = 200 }

    local function cap(soldPerDay, currentQty, madBps)
      return GC.SniperDecision.DemandCap(
        { soldPerDay = soldPerDay, currentQty = currentQty, madBps = madBps }, config, 0)
    end

    it("reproduces the measured engine-vs-list gap", function()
      assert.equal(1, cap(500, 5000, 0))
      assert.equal(3, cap(500, 500, 1000))
      assert.equal(10, cap(2000, 4000, 500))
      assert.equal(42, cap(5000, 5000, 250))
      assert.equal(1, cap(200, 2000, 0))
    end)

    it("floors at 1 rather than reaching zero", function()
      -- A thin market (soldPerDay barely above the velocity floor, deep stock) still returns a
      -- buyable quantity, never a zero that would make the row look like it has no cap at all.
      assert.equal(1, cap(3, 1000000, 0))
    end)

    it("caps at config.maxQuantity regardless of how permissive the raw arithmetic is", function()
      assert.equal(200, cap(1000000, 10, 0))
    end)

    it("returns 0 below the velocity floor or with no velocity figure at all", function()
      assert.equal(0, cap(2.9, 100, 0))
      assert.equal(0, cap(nil, 100, 0))
    end)

    it("fails closed on non-table input or a non-finite config", function()
      assert.equal(0, GC.SniperDecision.DemandCap(nil, config, 0))
      assert.equal(0, GC.SniperDecision.DemandCap({ soldPerDay = 500 }, nil, 0))
      assert.equal(0, GC.SniperDecision.DemandCap(
        { soldPerDay = 500 }, { maxDailyDemandShare = 0.02, maxQuantity = "bad" }, 0))
    end)

    it("agrees with Evaluate's own computed cap for the same inputs", function()
      -- Same fixture as the "uses the two-percent demand share and the 200 hard cap" test
      -- above: soldPerDay=100, a two-level book totalling visible=2, currentQty=0. Evaluate
      -- selects quantity 1 there; DemandCap must return the identical number for the identical
      -- market/config/visible -- it is the exact code Evaluate now calls internally.
      local input = validInput(); input.market.soldPerDay = 100
      input.live.levels = { { unitPrice = 1000000, quantity = 1 }, { unitPrice = 3000001, quantity = 1 } }
      local viaEvaluate = evaluate(input)
      local viaDemandCap = GC.SniperDecision.DemandCap(
        { soldPerDay = 100, currentQty = 0, madBps = 0 }, input.config, 2)
      assert.equal(1, viaEvaluate.quantity)
      assert.equal(viaDemandCap, viaEvaluate.quantity)
    end)
  end)

  -- A refusal shown as a bare token ("source_stale") tells a player what the engine calls the
  -- problem, not what to do about it. The dialog needs a sentence, and it has to come from the
  -- same file that owns the reasons so a new gate cannot ship without one.
  describe("ReasonText", function()
    it("explains every reason the engine can return", function()
      for reason in pairs(GC.SniperDecision.REASONS) do
        local text = GC.SniperDecision.ReasonText(reason)
        assert.is_string(text, reason)
        assert.is_true(#text > 0, reason)
        assert.not_equal(reason, text, reason)
      end
    end)

    it("names the remedy for a stale import rather than the symptom", function()
      local text = GC.SniperDecision.ReasonText("source_stale")
      assert.is_truthy(text:lower():find("reload", 1, true))
    end)

    it("falls back to the raw reason it does not know", function()
      assert.equal("mystery_gate", GC.SniperDecision.ReasonText("mystery_gate"))
      assert.equal("", GC.SniperDecision.ReasonText(nil))
    end)
  end)

  -- The velocity release. Before it, ANY discounted wall deeper than the buyable quantity was
  -- an automatic AVOID: a partial fill competes with the rest of the wall, exit = entry minus
  -- one copper, guaranteed loss after the cut. That refused exactly the deep liquid dips the
  -- deals list exists to surface (screenshot-reproduced: 33%-off Elementium Bar, 1185-unit
  -- wall, 34k sold/day, AVOID). A wall the market absorbs within `wallAbsorbHours` of daily
  -- sales is turnover, not competition -- the exit prices at stressUnit. Depth WITHOUT
  -- velocity keeps the old refusal: that is the Sanguithorn shape, and it must stay refused.
  describe("velocity release of a partial wall", function()
    local function deepWallInput()
      local input = validInput()
      -- 5000 units at 100g against a 300g stress exit: DemandCap approves 200, so the fill is
      -- always partial and the leftover wall (4800) is what the release must judge.
      input.live.levels = { { unitPrice = 1000000, quantity = 5000 }, { unitPrice = 3000001, quantity = 1 } }
      input.market.currentQty = 0
      return input
    end

    it("prices the exit at stressUnit when the leftover wall is hours of turnover", function()
      local input = deepWallInput()
      input.market.soldPerDay = 100000 -- 2h absorb budget = 8333 units >= 4800 leftover
      local result = evaluate(input)
      assert.equal("SAFE", result.computedStatus)
      assert.equal(3000000, result.exitUnit)     -- stressUnit, not wall - 1c
      assert.equal(1000000, result.competingUnit) -- the wall is still reported honestly
      assertReason(result, "wall_absorbed")
      assert.is_true(result.informational and result.informational.wall_absorbed or false)
    end)

    it("keeps refusing depth without velocity -- the Sanguithorn shape", function()
      local input = deepWallInput()
      input.market.soldPerDay = 20000 -- 2h absorb budget = 1666 units < 4800 leftover
      local result = evaluate(input)
      assert.equal("AVOID", result.computedStatus)
      assertReason(result, "stress_profit_below_buffer")
      assertNoReason(result, "wall_absorbed")
    end)

    it("is disabled outright by wallAbsorbHours = 0", function()
      local input = deepWallInput()
      input.market.soldPerDay = 100000
      input.config.wallAbsorbHours = 0
      local result = evaluate(input)
      assert.equal("AVOID", result.computedStatus)
      assertNoReason(result, "wall_absorbed")
    end)

    it("adds no note when the buy consumes the wall and the release never fires", function()
      local result = evaluate() -- the base fixture buys its 200-unit wall whole
      assert.equal("SAFE", result.computedStatus)
      assertNoReason(result, "wall_absorbed")
    end)

    it("fails closed on a malformed wallAbsorbHours", function()
      local input = deepWallInput()
      input.config.wallAbsorbHours = "fast"
      local result = evaluate(input)
      assert.equal("AVOID", result.status)
      assertReason(result, "invalid_input")
    end)
  end)
end)
