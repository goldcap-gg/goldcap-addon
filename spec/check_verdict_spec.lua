local helper = require("spec.spec_helper")

-- What the check panel SAYS, decided away from the panel that draws it.
--
-- UI/SniperFrame.lua is 6,400 lines and several specs reach into it through
-- debug.getupvalue chains, so every content decision made in there is one nothing can
-- test directly. These are content decisions -- which figure leads, in what unit, which
-- four facts back it, whether there is anything left to act on -- and they are exactly
-- the ones the owner's in-game session found wrong: a panel that reserved 94px for a
-- number a refusal never has, printed the same sentence three times, and showed a
-- quantity box on a verdict where nothing could be bought.
describe("CheckVerdict", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
  end)

  local function decision(over)
    local d = {
      status = "AVOID", buyable = false, reasons = {}, quantity = 200,
      entryTotal = 6220000, entryUnitDisplay = 31100, exitUnit = 27700,
      stressProfit = nil, informational = nil,
    }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
  end

  -- `pairs` skips a nil value, so an override table cannot UNSET a field -- which quietly
  -- made "no sales rate" a test against the default rate of 412. NONE is the sentinel.
  local NONE = {}

  local function market(over)
    local m = { marketValue = 30400, stressUnit = 27700, soldPerDay = 412,
      sellThroughBps = 8800, liquidityConfidence = 90, listings = 17, currentQty = 707550 }
    for k, v in pairs(over or {}) do m[k] = (v ~= NONE) and v or nil end
    return m
  end

  local function factById(verdict, id)
    for _, fact in ipairs(verdict.facts) do if fact.id == id then return fact end end
  end

  describe("tone", function()
    it("is clear when the engine will buy the whole requested lot", function()
      local v = GC.CheckVerdict.Build(decision({ status = "SAFE", buyable = true, stressProfit = 2180000 }), market())
      assert.equal("clear", v.tone)
      assert.is_true(v.actionable)
    end)

    -- The engine caps quantity by itself and files demand_limit as a NOTE (severity 0,
    -- see SniperDecision's own `add`), leaving the decision SAFE with a smaller number.
    -- The panel says nothing about that today: the player asked for 200, is buying 46,
    -- and is never told which -- or why.
    it("is adjust when the engine quietly bought less than the maximum", function()
      local v = GC.CheckVerdict.Build(decision({
        status = "SAFE", buyable = true, quantity = 46, stressProfit = 611000,
        reasons = { "demand_limit" }, informational = { demand_limit = true },
      }), market({ soldPerDay = 46 }))
      assert.equal("adjust", v.tone)
      assert.is_true(v.actionable)
      assert.same({ kind = "units", quantity = 46 }, v.hero)
    end)

    -- Nothing on a refusal can be acted on, so the quantity box and its quick-fill chips
    -- have nothing to do -- they are the bulk of what the panel makes a player read past.
    it("is refuse when the engine will not buy, and nothing is actionable", function()
      local v = GC.CheckVerdict.Build(decision({ reasons = { "price_history_sparse" } }), market())
      assert.equal("refuse", v.tone)
      assert.is_false(v.actionable)
    end)

    it("leads with the reason that refused, never with an informational note", function()
      local v = GC.CheckVerdict.Build(decision({
        reasons = { "demand_limit", "stress_profit_below_buffer" },
        informational = { demand_limit = true },
      }), market())
      assert.equal("stress_profit_below_buffer", v.reason)
    end)
  end)

  -- The hero answers one question -- what happens to my gold -- and changes UNIT rather
  -- than going blank, which is what the old panel did on every refusal: four cards of
  -- dashes and a 94px hole where the figure would have been.
  describe("hero", function()
    it("is the loss, in gold, when the exit is known and does not clear the floor", function()
      local v = GC.CheckVerdict.Build(decision({
        reasons = { "stress_profit_below_buffer" }, stressProfit = -1240000,
      }), market())
      assert.same({ kind = "gold", copper = -1240000 }, v.hero)
    end)

    it("is the profit, in gold, when the trade is clear", function()
      local v = GC.CheckVerdict.Build(decision({ status = "SAFE", buyable = true, stressProfit = 2180000 }), market())
      assert.same({ kind = "gold", copper = 2180000 }, v.hero)
    end)

    -- Gold is the wrong unit for a liquidity refusal: the price may be fine and the trap
    -- is the months you would hold it. 200 units at 3 a day is 66.6 -> 66 whole days.
    it("is time, not gold, when the trap is how slowly it sells", function()
      local v = GC.CheckVerdict.Build(decision({
        reasons = { "velocity_too_low" }, stressProfit = 184000,
      }), market({ soldPerDay = 3 }))
      assert.same({ kind = "days", days = 66 }, v.hero)
    end)

    -- The owner's own screenshot: HOT at -81%, refused because the value cannot be
    -- trusted. Printing a loss figure here would invent precision out of the very number
    -- being refused, so the hero says what is true instead.
    it("refuses to put a figure on a value it has just called untrustworthy", function()
      for _, reason in ipairs({ "price_history_sparse", "listings_too_low",
          "market_value_estimated", "source_stale", "bundled_data_unverified" }) do
        local v = GC.CheckVerdict.Build(decision({ reasons = { reason }, stressProfit = -1240000 }), market())
        assert.same({ kind = "unpriceable" }, v.hero, reason .. " should not print a figure")
      end
    end)

    it("falls back to unpriceable when no exit was ever worked out", function()
      local v = GC.CheckVerdict.Build(decision({ reasons = { "stress_exit_missing" } }), market())
      assert.same({ kind = "unpriceable" }, v.hero)
    end)

    -- A hold measured in whole days is only a meaningful headline when there IS one:
    -- 200 units at 412 a day floors to "0 days", which reads as instant rather than as
    -- fast. Anything under a day falls back rather than printing a zero.
    it("does not put a zero on the clock", function()
      local v = GC.CheckVerdict.Build(decision({
        reasons = { "sell_through_too_low" }, stressProfit = -1000,
      }), market({ soldPerDay = 412 }))
      assert.same({ kind = "gold", copper = -1000 }, v.hero)
    end)

    -- "No sales data" is a refusal about SPEED, not about price: the exit was worked out,
    -- so the loss figure is real and worth showing. What it must not do is manufacture a
    -- hold time out of a rate it does not have.
    it("does not divide by a sales rate it does not have", function()
      local v = GC.CheckVerdict.Build(decision({
        reasons = { "velocity_missing" }, stressProfit = -1000,
      }), market({ soldPerDay = NONE }))
      assert.equal("gold", v.hero.kind)
    end)

    it("has nothing to say when neither the price nor the speed is known", function()
      local v = GC.CheckVerdict.Build(decision({ reasons = { "velocity_missing" } }),
        market({ soldPerDay = NONE }))
      assert.same({ kind = "unpriceable" }, v.hero)
    end)
  end)

  -- A meter is only honest where a scale is real: a percentage, a threshold the engine
  -- itself applies, or a pair sharing one ceiling. Everything else gets no bar, which is
  -- what stops the meters from competing with the figure above them.
  describe("facts", function()
    it("meters the seller count against the engine's own floor of three", function()
      local v = GC.CheckVerdict.Build(decision({ reasons = { "listings_too_low" } }), market({ listings = 2 }))
      local sellers = factById(v, "sellers")
      assert.equal(2, sellers.count)
      assert.equal("bad", sellers.tone)
      assert.is_truthy(sellers.meter)
      assert.is_true(sellers.meter.at < sellers.meter.gate)
    end)

    it("meters sell-through as the percentage it already is", function()
      local v = GC.CheckVerdict.Build(decision({ reasons = { "sell_through_too_low" } }), market({ sellThroughBps = 4100 }))
      local through = factById(v, "sellThrough")
      assert.equal(4100, through.bps)
      assert.is_near(0.41, through.meter.at, 0.001)
      assert.is_near(0.70, through.meter.gate, 0.001)
    end)

    -- In versus out, on one ceiling, so the shortfall is visible before either number is
    -- read rather than being arithmetic the player has to do.
    it("puts what you pay and what you get back on a shared ceiling", function()
      local v = GC.CheckVerdict.Build(decision({
        reasons = { "stress_profit_below_buffer" }, entryTotal = 6220000, stressProfit = -960000,
      }), market())
      local pay, get = factById(v, "youPay"), factById(v, "youGet")
      assert.equal(6220000, pay.copper)
      assert.equal(5260000, get.copper)
      assert.equal(1, pay.meter.at)
      assert.is_near(5260000 / 6220000, get.meter.at, 0.0001)
      assert.equal("bad", get.tone)
    end)

    -- The refusal IS a comparison, so the floor the trade fell short of sits right under
    -- what came back -- "+38g" against "Your minimum 150g" -- instead of the player having to
    -- open Settings to remember which number the engine was holding them to.
    it("names the profit floor on a profit refusal", function()
      local v = GC.CheckVerdict.Build(decision({
        reasons = { "stress_profit_below_buffer" }, entryTotal = 150000000,
        stressProfit = 380000, requiredProfit = 15000000,
      }), market())
      assert.same({ kind = "gold", copper = 380000 }, v.hero)
      local floor = factById(v, "yourMinimum")
      assert.equal(15000000, floor.copper)
      assert.equal("youPay", v.facts[1].id)
      assert.equal("youGet", v.facts[2].id)
      assert.equal("yourMinimum", v.facts[3].id)
    end)

    it("skips an absent fact without dropping the ones offered after it", function()
      -- No requiredProfit on the decision: the "Your minimum" slot is empty, and the market
      -- facts behind it must still fill the block.
      local v = GC.CheckVerdict.Build(decision({
        reasons = { "stress_profit_below_buffer" }, entryTotal = 6220000, stressProfit = -960000,
      }), market())
      assert.equal(4, #v.facts)
      assert.is_nil(factById(v, "yourMinimum"))
      assert.equal("sellThrough", v.facts[3].id)
    end)

    it("gives a figure with no natural ceiling no meter at all", function()
      local v = GC.CheckVerdict.Build(decision({
        reasons = { "velocity_too_low" }, stressProfit = 184000,
      }), market({ soldPerDay = 3 }))
      assert.is_nil(factById(v, "goldTiedUp").meter)
    end)

    it("never offers more than four, so the block cannot outgrow the panel", function()
      for _, reason in ipairs({ "price_history_sparse", "stress_profit_below_buffer",
          "velocity_too_low", "listings_too_low", "capital_limit" }) do
        local v = GC.CheckVerdict.Build(decision({ reasons = { reason }, stressProfit = -1000 }), market())
        assert.is_true(#v.facts <= 4, reason .. " offered " .. #v.facts)
        assert.is_true(#v.facts > 0, reason .. " offered none")
      end
    end)

    it("skips a fact the market cannot answer rather than showing a dash", function()
      local v = GC.CheckVerdict.Build(decision({ reasons = { "price_history_sparse" } }),
        market({ listings = NONE, liquidityConfidence = NONE, marketValue = NONE }))
      for _, fact in ipairs(v.facts) do
        assert.is_truthy(fact.count or fact.copper or fact.bps or fact.days or fact.text,
          fact.id .. " carries no value")
      end
    end)
  end)

  -- The board tiers off the imported snapshot; this panel reads the live book. When they
  -- disagree the player is owed the reconciliation rather than two contradictory badges
  -- 320 pixels apart.
  describe("reconcile", function()
    it("is offered when a refusal contradicts the tier the board showed", function()
      local v = GC.CheckVerdict.Build(decision({ reasons = { "price_history_sparse" } }), market(), { tier = "HOT" })
      assert.is_true(v.reconcile)
    end)

    it("is not offered when the verdict agrees with the board", function()
      local v = GC.CheckVerdict.Build(decision({ status = "SAFE", buyable = true, stressProfit = 1 }), market(), { tier = "HOT" })
      assert.is_false(v.reconcile)
    end)

    it("is not offered when the board never tiered it", function()
      local v = GC.CheckVerdict.Build(decision({ reasons = { "price_history_sparse" } }), market(), {})
      assert.is_false(v.reconcile)
    end)
  end)

  -- Sniper phase 2. A realm lot the live check found under its region reference is neither a
  -- refusal nor an approval: the price comparison is real and the dialog offers the buy, but
  -- nothing measures how fast the item sells, so the panel must not print "Won't buy" over an
  -- enabled buy button -- nor "Clear to buy", which would be the bigger lie.
  describe("an unverified realm lot", function()
    local function realmDecision(over)
      local d = {
        status = "WATCH", buyable = false, reasons = { "realm_item_unverified" },
        quantity = 1, entryTotal = 750000, entryUnitDisplay = 750000,
        reference = 1000000, estProfit = 200000,
        candidate = { auctionID = 8801, buyout = 750000, itemLevel = 623, quantity = 1 },
      }
      for k, v in pairs(over or {}) do d[k] = v end
      return d
    end

    it("gets its own tone, and is actionable", function()
      local v = GC.CheckVerdict.Build(realmDecision(), market({ soldPerDay = NONE,
        sellThroughBps = NONE, liquidityConfidence = NONE, listings = NONE }))
      assert.equal("unverified", v.tone)
      assert.is_true(v.actionable)
      assert.is_false(v.reconcile)
    end)

    it("leads with what the lot clears against the reference, in its own unit", function()
      local v = GC.CheckVerdict.Build(realmDecision(), market())
      assert.equal("reference", v.hero.kind)
      assert.equal(200000, v.hero.copper)
    end)

    it("shows only the two facts a realm item honestly has", function()
      local v = GC.CheckVerdict.Build(realmDecision(), market({ soldPerDay = NONE,
        sellThroughBps = NONE, liquidityConfidence = NONE, listings = NONE }))
      assert.equal(2, #v.facts)
      assert.equal(750000, factById(v, "youPayFlat").copper)
      assert.equal(1000000, factById(v, "snapshotValue").copper)
    end)

    -- No region reference means no candidate, so the "Your call" tone must not apply: there is
    -- nothing to buy on, nothing to put in the headline figure, and no BUY button.
    it("is not the unverified tone when there is no region reference", function()
      local v = GC.CheckVerdict.Build(
        decision({ status = "WATCH", reasons = { "realm_no_reference" }, stressProfit = nil }),
        market())
      assert.equal("refuse", v.tone)
      assert.is_false(v.actionable)
      assert.equal("unpriceable", v.hero.kind)
      assert.equal("realm_no_reference", v.reason)
    end)

    it("stays a refusal when the check named no lot to buy", function()
      local v = GC.CheckVerdict.Build(
        decision({ status = "AVOID", reasons = { "no_comparable_lot" } }), market())
      assert.equal("refuse", v.tone)
      assert.is_false(v.actionable)
    end)
  end)

  it("survives a decision it cannot read rather than erroring on the buy path", function()
    assert.is_table(GC.CheckVerdict.Build(nil, nil))
    assert.equal("refuse", GC.CheckVerdict.Build(nil, nil).tone)
    assert.is_table(GC.CheckVerdict.Build({}, {}).facts)
  end)
end)
