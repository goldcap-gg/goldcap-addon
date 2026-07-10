local helper = require("spec.spec_helper")

describe("FullScan.Evaluate", function()
  local GC
  local cfg = {
    hotDiscount = 0.40, hotProfit = 5000000,
    goodDiscount = 0.25, goodProfit = 1000000,
    watchDiscount = 0.10, suspectDiscount = 0.90,
  }
  local values = {
    [10] = { mv = 1000000 },   -- 100g market
    [20] = { mv = 200000000 }, -- 20000g market
    [30] = { mv = 100000 },    -- 10g market
  }
  local function getValue(id) return values[id] end

  before_each(function()
    GC = helper.loadModule("Core/DealMath.lua")
    helper.loadModule("Core/FullScan.lua", GC)
  end)

  it("derives per-unit price from a per-stack buyout", function()
    -- item 10: stack of 5 for 2500000 => unit 500000 => 50% discount vs 1000000
    local deals = GC.FullScan.Evaluate({ { itemID = 10, count = 5, buyoutStack = 2500000 } }, getValue, cfg, 100)
    assert.equal(1, #deals)
    assert.equal(500000, deals[1].unitPrice)
    assert.equal(5, deals[1].qty)
    assert.equal(0.5, deals[1].discount)
  end)

  it("skips rows with no value, zero count, or zero buyout", function()
    local deals = GC.FullScan.Evaluate({
      { itemID = 999, count = 1, buyoutStack = 100 },   -- no market value
      { itemID = 10, count = 0, buyoutStack = 100 },    -- zero count
      { itemID = 10, count = 1, buyoutStack = 0 },      -- zero buyout
    }, getValue, cfg, 100)
    assert.equal(0, #deals)
  end)

  it("skips rows below the watch threshold", function()
    -- item 10 at 950000 unit = 5% discount < watch 10%
    local deals = GC.FullScan.Evaluate({ { itemID = 10, count = 1, buyoutStack = 950000 } }, getValue, cfg, 100)
    assert.equal(0, #deals)
  end)

  it("dedupes same-itemID rows to the single higher-profit (cheaper) deal", function()
    -- item 10, mv 1000000: one seller at 700000 (30% off, 250000 profit), one at 500000
    -- (50% off, 450000 profit). Only the cheaper/higher-profit one survives, so downstream
    -- itemID-keyed requery state can't collide on the same item.
    local deals = GC.FullScan.Evaluate({
      { itemID = 10, count = 1, buyoutStack = 700000 },
      { itemID = 10, count = 1, buyoutStack = 500000 },
    }, getValue, cfg, 100)
    assert.equal(1, #deals)
    assert.equal(10, deals[1].itemID)
    assert.equal(500000, deals[1].unitPrice)
    assert.equal(450000, deals[1].profit)
  end)

  it("sorts by tier rank then profit desc and truncates to cap", function()
    local rows = {
      { itemID = 30, count = 1, buyoutStack = 5000 },        -- 10g mv, 50% off, tiny profit => WATCH
      { itemID = 20, count = 1, buyoutStack = 120000000 },   -- 20000g mv, 40% off, big profit => HOT
      { itemID = 10, count = 1, buyoutStack = 500000 },      -- 100g mv, 50% off, ~45g profit => WATCH
    }
    local deals = GC.FullScan.Evaluate(rows, getValue, cfg, 2)
    assert.equal(2, #deals)
    assert.equal("HOT", deals[1].tier)           -- HOT first
    assert.equal(20, deals[1].itemID)
    assert.equal("WATCH", deals[2].tier)          -- then the higher-profit WATCH (item 10, 45g > item 30's ~4.5g)
    assert.equal(10, deals[2].itemID)
  end)
end)
