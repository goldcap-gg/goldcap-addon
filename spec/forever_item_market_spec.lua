local helper = require("spec.spec_helper")

-- ClickUp 1an60dzy9nt: WoW: Forever items (not commodities) judged against what the same item, or
-- the same version of a piece of gear, sold for on the house. The rules come from the backtest of
-- 2026-11-23 (wow-auction's scripts/analytics/forever-items-under-market/).
describe("ForeverItemMarket", function()
  local M

  before_each(function()
    local GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ForeverItemMarket.lua", GC)
    M = GC.ForeverItemMarket
  end)

  local function sold(sales, median, hours, units)
    return { units = units or sales, sales = sales, median = median, p25 = median, hours = hours or 168,
      perDay = (units or sales) * 24 / (hours or 168) }
  end

  describe("Reference", function()
    it("takes an item sold 35 times a week or more, its ceiling half its median", function()
      local r = M.Reference(sold(35, 1001), false)
      assert.same({ 1001, 500, 35, 5 }, { r.ref, r.ceiling, r.perWeek, r.perDay })
      assert.is_nil(M.Reference(sold(34, 1001), false))
    end)

    it("counts the week over the hours of tape there are", function()
      assert.is_not_nil(M.Reference(sold(10, 1000, 48), false)) -- 35 a week
      assert.is_nil(M.Reference(sold(9, 1000, 48), false))
    end)

    it("takes a version of a piece of gear sold 7 times a week, at 40% and only under 10g", function()
      local r = M.Reference(sold(7, 50000), true)
      assert.same({ 50000, 20000 }, { r.ref, r.ceiling })
      assert.is_nil(M.Reference(sold(6, 50000), true))
      assert.is_nil(M.Reference(sold(70, 100000), true)) -- the backtest's 10g+ gear lost 1.2g a lot
      assert.is_not_nil(M.Reference(sold(70, 99999), true))
    end)

    it("is nothing without a median, a tape, or a sale", function()
      assert.is_nil(M.Reference(nil, false))
      assert.is_nil(M.Reference({ units = 0, sales = 0, perDay = 0, hours = 168 }, false))
      assert.is_nil(M.Reference({ sales = 50, median = 100 }, false))
    end)
  end)

  describe("Plan", function()
    local ref = { ref = 1000, ceiling = 500, perDay = 5 }

    it("resells at 90% of the median after the cut and one deposit", function()
      local p = M.Plan(ref, { 400 }, M.Deposit(100), 2)
      -- exit 900, cut 45, deposit 20% of the 100c vendor price
      assert.same({ 1, 400, 900, 20, 435, 435 }, { p.take, p.cost, p.exit, p.deposit, p.profit, p.firstProfit })
      assert.equal(0.6, p.discount)
    end)

    it("sells one copper under the next lot it leaves on the book", function()
      local p = M.Plan(ref, { 400, 700 }, 0, 2)
      assert.equal(699, p.exit) -- 699 - 35 cut - 400
      assert.equal(264, p.profit)
    end)

    it("takes every lot under the ceiling the player has room for, and no more", function()
      local p = M.Plan(ref, { 300, 400, 450, 950 }, 0, 2)
      assert.same({ 2, 700 }, { p.take, p.cost })
      -- The 450c lot it had no room for stays under the median: the resale has to beat it.
      assert.equal(449, p.exit)
      assert.equal(449 - 23 - 300, p.firstProfit)
      assert.equal(2 * (449 - 23) - 700, p.profit)
    end)

    it("is nothing when no lot is under the ceiling or there is no room", function()
      assert.is_nil(M.Plan(ref, { 501 }, 0, 2))
      assert.is_nil(M.Plan(ref, { 400 }, 0, 0))
      assert.is_nil(M.Plan(ref, {}, 0, 2))
    end)
  end)

  describe("Deposit", function()
    it("is a fifth of the vendor price, rounded up, and nothing without one", function()
      assert.same({ 20, 1, 0, 0 }, { M.Deposit(100), M.Deposit(3), M.Deposit(0), M.Deposit(nil) })
    end)
  end)

  describe("HeldCap", function()
    it("is half a day of sales, never under one", function()
      assert.equal(1, M.HeldCap(0.4))
      assert.equal(1, M.HeldCap(3))
      assert.equal(4, M.HeldCap(8.9))
      assert.equal(1, M.HeldCap(nil))
    end)
  end)

  describe("Units", function()
    it("spreads a fold ladder's levels into lot prices, cheapest first, up to a limit", function()
      assert.same({ 10, 10, 12 }, M.Units({ { 10, 2 }, { 12, 1 } }, 5))
      assert.same({ 10, 10, 10 }, M.Units({ { 10, 7 }, { 12, 1 } }, 3))
    end)
  end)
end)
