local helper = require("spec.spec_helper")

describe("BuyRun", function()
  local GC, run
  local have, usual
  before_each(function()
    GC = {}
    helper.loadModule("Core/BuyRun.lua", GC)
    have, usual = { [5] = 60, [7] = 0, [9] = 300 }, { [5] = 30000, [7] = nil, [9] = 100 }
    run = GC.BuyRun.New({ code = "abcd2345", name = "Cooking", updatedAt = 1, lines = {
      { i = 5, q = 210, v = false, n = "Plant Protein" },
      { i = 8, q = 215, v = true, n = "Tavern Fixings" },
      { i = 7, q = 5, v = false, n = "Petrified Root" },
      { i = 9, q = 100, v = false, n = "Done Thing" },
    } }, { now = function() return 1000 end, haveOf = function(id) return have[id] or 0 end,
           usualUnit = function(id) return usual[id] end, capPct = function() return 130 end,
           freeLines = function() return nil end })
    run:Refresh()
  end)

  it("computes buy = need - have and folds done lines and vendor lines to the end", function()
    local ids = {}
    for _, l in ipairs(run:Lines()) do ids[#ids + 1] = l.itemID .. ":" .. l.buy end
    assert.same({ "5:150", "7:5", "9:0", "8:215" }, ids)
    assert.is_true(run:Lines()[3].done)
    assert.is_true(run:Lines()[4].vendor)
  end)

  it("caps at 1.3x the usual price and buys only what fits", function()
    local qty, total, capped = run:PurchaseQuantity(5, { { unit = 30000, qty = 100 }, { unit = 39000, qty = 100 }, { unit = 39001, qty = 100 } })
    assert.equal(150, qty)                -- 100 @ 3g + 50 @ 3g90 (cap = 3g90)
    assert.equal(100 * 30000 + 50 * 39000, total)
    assert.is_false(capped)
    qty, total, capped = run:PurchaseQuantity(5, { { unit = 30000, qty = 20 }, { unit = 50000, qty = 500 } })
    assert.equal(20, qty)
    assert.equal(20 * 30000, total)       -- 20 @ 3g fit under the cap before the 5g level
    assert.is_true(capped)
  end)

  it("stops at whatever the ladder has when it runs out before need is met", function()
    local qty, total, capped = run:PurchaseQuantity(5, { { unit = 30000, qty = 40 } })
    assert.equal(40, qty)
    assert.equal(40 * 30000, total)
    assert.is_false(capped)               -- ran out of ladder, not stopped by the cap
  end)

  it("a line without a usual price has no cap and buys the whole need", function()
    local qty, _, capped = run:PurchaseQuantity(7, { { unit = 999999, qty = 10 } })
    assert.equal(5, qty)
    assert.is_false(capped)
  end)

  it("records purchases into bought, spent and the totals", function()
    -- What was bought lands in the bags, which is where `have` reads it from on the next
    -- Refresh -- so the fixture moves it there, exactly as the client would.
    run:RecordPurchase(5, 150, 4410000, 1001)
    have[5] = 60 + 150
    run:Refresh()
    local line = run:Lines()[1]
    assert.equal(150, line.bought)
    assert.equal(4410000, line.spent)
    assert.equal(210, line.have)
    assert.equal(0, line.buy)
    assert.is_true(line.done)
    assert.equal(4410000, run:Totals().spent)
  end)

  -- `have` and `bought` are two views of the SAME units once a purchase is delivered. Subtracting
  -- both counted every buy twice: a line that filled only part of what it needed went straight to
  -- done, and the rest of it could never be bought -- which is the whole job of this tab.
  it("keeps the remainder buyable after a partial fill lands in the bags", function()
    run:RecordPurchase(5, 90, 90 * 30000, 1001)
    have[5] = 60 + 90
    run:Refresh()
    local line = run:Lines()[1]
    assert.equal(150, line.have)
    assert.equal(90, line.bought)
    assert.equal(60, line.buy)
    assert.is_false(line.done)
    -- ...and the run still says those 60 cost something.
    assert.equal(60 * 30000, run:Totals().left)
  end)

  it("left to spend uses the floor when one is known, else the usual price", function()
    run:SetFloor(5, 29400, 999)
    assert.equal(150 * 29400 + 0, run:Totals().left)   -- line 7 has no usual and no floor: counts 0
  end)

  it("locks lines past the free limit, vendor lines never count", function()
    local gated = GC.BuyRun.New({ code = "x", lines = {
      { i = 1, q = 1 }, { i = 2, q = 1 }, { i = 8, q = 1, v = true }, { i = 3, q = 1 } } },
      { now = function() return 0 end, haveOf = function() return 0 end, usualUnit = function() return nil end,
        capPct = function() return 130 end, freeLines = function() return 2 end })
    gated:Refresh()
    local locked = {}
    for _, l in ipairs(gated:Lines()) do locked[#locked + 1] = tostring(l.locked) end
    assert.same({ "false", "false", "true", "false" }, locked)   -- 1, 2 buyable; 3 locked; vendor line last, never locked
  end)
end)
