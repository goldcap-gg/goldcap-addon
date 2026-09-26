local helper = require("spec.spec_helper")

describe("ForeverFold", function()
  local GC, F
  before_each(function()
    GC = helper.loadModule("Core/ForeverFold.lua")
    F = GC.ForeverFold
  end)

  it("folds lots per item: min unit, quantity, lot count, ladder cheapest first", function()
    local acc = F.New()
    assert.is_true(F.AddRow(acc, 2589, 20, 1340, true))  -- 67c
    assert.is_true(F.AddRow(acc, 2589, 5, 350, true))    -- 70c
    assert.is_true(F.AddRow(acc, 2589, 10, 670, true))   -- 67c again: same level
    local e = acc.items[2589]
    assert.equal(67, e.min)
    assert.equal(35, e.qty)
    assert.equal(3, e.lots)
    assert.same({ { 67, 30 }, { 70, 5 } }, e.ladder)
    assert.equal(3, acc.rows)
  end)

  it("keeps only the five cheapest levels", function()
    local acc = F.New()
    for unit = 110, 100, -1 do F.AddRow(acc, 7, 1, unit, true) end
    assert.same({ { 100, 1 }, { 101, 1 }, { 102, 1 }, { 103, 1 }, { 104, 1 } }, acc.items[7].ladder)
    assert.equal(11, acc.items[7].qty)
    assert.equal(11, acc.items[7].lots)
  end)

  it("rounds a stack's unit price to the copper and never below one", function()
    local acc = F.New()
    F.AddRow(acc, 1, 2, 101, true)
    F.AddRow(acc, 2, 3, 1, true)
    assert.equal(51, acc.items[1].min)
    assert.equal(1, acc.items[2].min)
  end)

  it("skips rows it cannot price and counts them; folds rows still loading item data", function()
    local acc = F.New()
    assert.is_false(F.AddRow(acc, nil, 1, 100, true))
    assert.is_false(F.AddRow(acc, 5, 0, 100, true))
    assert.is_false(F.AddRow(acc, 5, 1, 0, true))       -- bid-only
    assert.is_false(F.AddRow(acc, 5, 1.5, 100, true))
    assert.is_true(F.AddRow(acc, 5, 1, 100, false))     -- hasAllInfo false: price is still there
    assert.equal(4, acc.skipped)
    assert.equal(1, acc.pending)
    assert.equal(1, acc.rows)
  end)

  it("values an item at the level a tenth of its units reach, not at a troll lot", function()
    local acc = F.New()
    F.AddRow(acc, 2589, 1, 1, true)             -- one unit at 1c
    F.AddRow(acc, 2589, 936, 936 * 67, true)
    F.AddRow(acc, 2589, 3000, 3000 * 70, true)
    assert.equal(67, F.Value(acc.items[2589]))  -- need ceil(3937 * 0.1) = 394 units
  end)

  it("values a thin item at its cheapest lot, and a wide one at its last ladder level", function()
    local acc = F.New()
    F.AddRow(acc, 1, 1, 5000, true)
    assert.equal(5000, F.Value(acc.items[1]))
    for unit = 100, 104 do F.AddRow(acc, 2, 1, unit, true) end
    F.AddRow(acc, 2, 1000, 900000, true)        -- the bulk sits above the ladder
    assert.equal(104, F.Value(acc.items[2]))
  end)

  it("adds browse rows only for items the dump lacked", function()
    local acc = F.New()
    F.AddRow(acc, 2589, 20, 1340, true)
    assert.is_false(F.AddBrowse(acc, 2589, 60, 10))
    assert.is_true(F.AddBrowse(acc, 3000, 500, 2))
    assert.is_false(F.AddBrowse(acc, 3001, 0, 2))
    assert.equal(67, acc.items[2589].min)
    assert.is_true(acc.items[3000].browse)
    assert.equal(500, F.Value(acc.items[3000]))
  end)

  it("encodes and decodes an entry, with gear and browse flags and unknown lots", function()
    local acc = F.New()
    F.AddRow(acc, 2589, 20, 1340, true)
    F.AddRow(acc, 2589, 5, 350, true)
    local s = F.Encode(acc.items[2589], false)
    assert.equal("67,25,2,;0x20 3x5|0,0,2", s)
    local e = F.Decode(s)
    assert.equal(67, e.value); assert.equal(67, e.min); assert.equal(25, e.qty); assert.equal(2, e.lots)
    assert.same({ { 67, 20 }, { 70, 5 } }, e.ladder)
    assert.is_false(e.gear); assert.is_false(e.browse)
    F.AddBrowse(acc, 3000, 500, 2)
    local b = F.Decode(F.Encode(acc.items[3000], true))
    assert.equal(500, b.value); assert.is_nil(b.lots); assert.is_true(b.gear); assert.is_true(b.browse)
  end)

  it("keeps every level while folding and saves p25, p50 and the level count", function()
    local acc = F.New()
    -- 100 units over seven levels; the ladder keeps five, the depth sees all seven.
    F.AddRow(acc, 2589, 10, 10 * 5, true)    -- 5c  x10  (cum 10)
    F.AddRow(acc, 2589, 10, 10 * 6, true)    -- 6c  x10  (cum 20)
    F.AddRow(acc, 2589, 10, 10 * 7, true)    -- 7c  x10  (cum 30)  <- p25 needs 25
    F.AddRow(acc, 2589, 10, 10 * 8, true)    -- 8c  x10  (cum 40)
    F.AddRow(acc, 2589, 5, 5 * 9, true)      -- 9c  x5   (cum 45)
    F.AddRow(acc, 2589, 10, 10 * 10, true)   -- 10c x10  (cum 55)  <- p50 needs 50
    F.AddRow(acc, 2589, 45, 45 * 12, true)   -- 12c x45  (cum 100)
    local p25, p50, levels = F.Depths(acc.items[2589])
    assert.equal(7, p25)
    assert.equal(10, p50)
    assert.equal(7, levels)
    local s = F.Encode(acc.items[2589], false)
    assert.equal("5,100,7,;0x10 1x10 1x10 1x10 1x5|2,5,7", s)
    local e = F.Decode(s)
    assert.equal(7, e.p25); assert.equal(10, e.p50); assert.equal(7, e.levels)
    assert.equal(5, #e.ladder)
  end)

  it("rounds the 25%/50% depth threshold up, not down, when the two disagree", function()
    -- 9 units total: 25% = 2.25 (ceil 3, floor 2), 50% = 4.5 (ceil 5, floor 4). Placing a level
    -- boundary between the ceil and floor cumulative for each share pins which one Depths uses.
    local acc = F.New()
    F.AddRow(acc, 4200, 2, 2 * 5, true)  -- 5c x2  (cum 2)              floor-25 would stop here
    F.AddRow(acc, 4200, 1, 6, true)      -- 6c x1  (cum 3)  <- ceil-25 stops here
    F.AddRow(acc, 4200, 1, 7, true)      -- 7c x1  (cum 4)              floor-50 would stop here
    F.AddRow(acc, 4200, 1, 8, true)      -- 8c x1  (cum 5)  <- ceil-50 stops here
    F.AddRow(acc, 4200, 4, 4 * 9, true)  -- 9c x4  (cum 9)
    local p25, p50, levels = F.Depths(acc.items[4200])
    assert.equal(6, p25)  -- floor(9*0.25)=2 would have picked 5c instead
    assert.equal(8, p50)  -- floor(9*0.50)=4 would have picked 7c instead
    assert.equal(5, levels)
  end)

  it("decodes a version-1 string with no depth, and a browse entry never carries one", function()
    local e = F.Decode("67,4060,31,;0x936 3x3000")
    assert.equal(67, e.min); assert.equal(70, e.ladder[2][1])
    assert.is_nil(e.p25); assert.is_nil(e.p50); assert.is_nil(e.levels)
    local acc = F.New()
    F.AddBrowse(acc, 3000, 500, 2)
    local s = F.Encode(acc.items[3000], false)
    assert.equal("500,2,,b;", s)
    assert.is_nil(F.Decode(s).p50)
  end)

  it("does not carry the in-memory levels into the frozen strings", function()
    local acc = F.New()
    F.AddRow(acc, 1, 3, 30, true)
    local items = F.Freeze(acc)
    assert.is_nil(items[1]:find("all", 1, true))
    assert.equal("10,3,1,;0x3|0,0,1", items[1])
  end)

  it("reads garbage after the bar as no depth, not as an error", function()
    local e = F.Decode("67,25,2,;0x20 3x5|x,y")
    assert.equal(67, e.min); assert.is_nil(e.p50)
  end)

  it("decodes nothing from garbage", function()
    assert.is_nil(F.Decode(nil))
    assert.is_nil(F.Decode(""))
    assert.is_nil(F.Decode("abc"))
    assert.is_nil(F.Decode("0,1,1,;0x1"))
  end)

  it("freezes the fold to strings and counts items, asking isGear per item", function()
    local acc = F.New()
    F.AddRow(acc, 1, 1, 100, true)
    F.AddRow(acc, 2, 1, 200, true)
    local items, n = F.Freeze(acc, function(id) return id == 2 end)
    assert.equal(2, n)
    assert.is_false(F.Decode(items[1]).gear)
    assert.is_true(F.Decode(items[2]).gear)
    local plain = F.Freeze(acc, function() error("client gone") end)
    assert.is_false(F.Decode(plain[2]).gear)
  end)

  -- SavedVariables writes `[id] = "…",` on a line of its own, indented; 12 bytes covers the
  -- punctuation and indentation. The spec's target is ~300-600 KB.
  it("keeps a 6,000-item fold under 600 KB", function()
    local acc = F.New()
    for id = 1, 6000 do
      for level = 0, 5 do F.AddRow(acc, 200000 + id, 999, (1234500 + level * 100) * 999, true) end
    end
    local items = F.Freeze(acc)
    local bytes = 0
    for id, s in pairs(items) do bytes = bytes + #s + #tostring(id) + 12 end
    assert.is_true(bytes < 600 * 1024, ("fold is %d bytes"):format(bytes))
  end)
end)
