local helper = require("spec.spec_helper")

-- Discovery keeps a commodity row only if the live Check could still pass it (GC.DealMath.ExitAdmits):
-- run both on the same inputs over a table of cases, and the new rule never drops a row the Check
-- passes, while it does drop rows the Check is sure to refuse.
describe("DealMath.ExitAdmits", function()
  local GC
  local NOW, MV = 1700000000, 1000000

  before_each(function()
    GC = helper.loadModule("Core/Book.lua")
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
  end)

  local function config(minimumProfitCopper, minimumRoi)
    return { maxCapitalShare = 0.05, maxDailyDemandShare = 0.05, maxQuantity = 200, lowestQuality = 0,
      minimumProfitCopper = minimumProfitCopper, minimumRoi = minimumRoi, watchDiscount = 0.10,
      suspectDiscount = 0.90, hotDiscount = 0.40, hotProfit = 500000, goodDiscount = 0.25,
      goodProfit = 100000, hotMinSold = 3, goodMinSold = 1, dumpTrendPct = 10, watchPins = {} }
  end

  local function value(stressUnit, currentQty)
    return { kind = "region_commodity", source = "region", sourceAt = NOW, mv = MV, stressUnit = stressUnit,
      sold = 2000, sellThroughBps = 9000, liquidityConfidence = 90, listings = 40, observations = 50,
      currentQty = currentQty, madBps = 0 }
  end

  -- One case: what discovery made of the browse row before this rule, what it makes of it now,
  -- and whether the live Check passes a buy of the same book: `listed` units at the row's price,
  -- with `second` as many again halfway up to the stress exit when given, and a competitor over
  -- the stress exit, so the Check's exit is its most optimistic one. `known`: the import says how
  -- many are listed; without it discovery reads the browse row's total, as in the client.
  local function run(stressUnit, discount, listed, cfg, known, second)
    local unit = math.floor(MV * (1 - discount))
    local levels = { { unitPrice = unit, quantity = listed } }
    if second then levels[2] = { unitPrice = math.floor((unit + stressUnit) / 2), quantity = listed } end
    local total = 0
    for _, level in ipairs(levels) do total = total + level.quantity end
    levels[#levels + 1] = { unitPrice = MV * 2, quantity = 1000 }
    local v = value(stressUnit, known and total or nil)
    local getValue = function() return v end
    local rows = GC.FullScan.RowsFromBrowse(
      { { itemKey = { itemID = 7 }, minPrice = unit, totalQuantity = total } }, getValue, cfg)
    local row = rows[1]
    local deal = row and GC.DealMath.Evaluate({ itemID = 7, unitPrice = unit, qty = row.count, avail = total }, v, cfg)
    local before = deal ~= nil and GC.DealMath.BoardAdmits(deal, cfg)
    local now = #GC.FullScan.Evaluate(rows, getValue, cfg) > 0
    local check = GC.SniperDecision.Evaluate({
      market = GC.SniperDecision.MarketFromValue(v), config = cfg, now = NOW, walletCopper = 10 ^ 12,
      depositForQuantity = function() return 0 end, live = { itemID = 7, levels = levels },
    })
    return before, now, check.buyable == true
  end

  it("never drops a row the live Check passes, and drops rows it is sure to refuse", function()
    local cases, removed, passed, shown = 0, 0, 0, 0
    for _, stress in ipairs({ 950000, 900000, 800000, 700000 }) do
      for _, discount in ipairs({ 0.10, 0.12, 0.15, 0.18, 0.20, 0.25, 0.31, 0.40, 0.60 }) do
        for _, listed in ipairs({ 1, 5, 50, 500, 5000 }) do
          for _, floors in ipairs({ { 50000, 0.10 }, { 2000000, 0.10 }, { 50000, 0.25 }, { 5000, 0.10 } }) do
            for _, known in ipairs({ true, false }) do
              for _, second in ipairs({ false, true }) do
                local cfg = config(floors[1], floors[2])
                local before, now, check = run(stress, discount, listed, cfg, known, second)
                local label = ("stress %d, %d%% off, %d listed, floors %d/%.2f, %s, %s"):format(stress,
                  discount * 100, listed, floors[1], floors[2], known and "known" or "unknown",
                  second and "two levels" or "one level")
                cases = cases + 1
                if check then passed = passed + 1 end
                assert.is_false(check and not now, "dropped a row the Check passes: " .. label)
                assert.is_false(now and not before, "kept a row the old rule dropped: " .. label)
                if before then shown = shown + 1 end
                if before and not now then removed = removed + 1 end
              end
            end
          end
        end
      end
    end
    -- 2880 cases; the old rule showed a row in 1472 of them, the Check passes 504 (each one still
    -- shown), and 528 of the rows shown are now left off, every one of them a row the Check refuses.
    assert.equal(2880, cases)
    assert.equal(504, passed)
    assert.equal(1472, shown)
    assert.equal(528, removed)
  end)

  it("drops the row of the measured shape: 10% off a market whose stress exit is 95% of it", function()
    local before, now, check = run(950000, 0.10, 50, config(50000, 0.10))
    assert.is_true(before)
    assert.is_false(now)
    assert.is_false(check)
  end)

  it("leaves pins and YOUR PRICE rows alone, and keeps a row with nothing to judge by", function()
    local cfg = config(50000, 0.10)
    local v = value(950000, 50)
    local deal = { itemID = 7, unitPrice = 900000, qty = 1 }
    assert.is_false(GC.DealMath.ExitAdmits(deal, v, cfg))
    cfg.watchPins = { 7 }
    assert.is_true(GC.DealMath.ExitAdmits(deal, v, cfg))
    cfg.watchPins = {}
    assert.is_true(GC.DealMath.ExitAdmits({ itemID = 7, unitPrice = 900000, qty = 1, cap = true }, v, cfg))
    v.stressUnit = nil
    assert.is_true(GC.DealMath.ExitAdmits(deal, v, cfg))
    assert.is_true(GC.DealMath.ExitAdmits(deal, value(950000, 50), {}))
  end)

  it("holds a buy to the Check's floors after they are normalized, by the table", function()
    local cases = {
      -- stress, unit, qty, minimum profit, minimum return -> clears
      { 1000, 800, 100, 10000, 0.10, true },   -- 15000 over a floor of max(10000, 8000)
      { 1000, 870, 100, 10000, 0.10, false },  -- 8000 under 10000
      { 1000, 860, 1000, 10000, 0.10, true },  -- 90000 over max(10000, 86000)
      { 1000, 870, 1000, 10000, 0.10, false }, -- 80000 under 87000
      { 1000, 800, 100, 0, 0, true },          -- floors of 0 are 1g and 10%: 15000 over max(10000, 8000)
      { 1000, 900, 1000, 0, 0, false },        -- 50000 under 90000
    }
    for i, c in ipairs(cases) do
      local cfg = config(c[4], c[5])
      assert.equal(c[6], GC.SniperDecision.ExitCanClear({ stressUnit = c[1] }, cfg, c[2], c[3]), "case " .. i)
    end
  end)
end)
