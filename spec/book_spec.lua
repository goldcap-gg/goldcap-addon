local helper = require("spec.spec_helper")

describe("Book", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Book.lua")
  end)

  -- levels({unitPrice, quantity}, ...) -- ascending, the order the AH returns them in
  local function levels(...)
    local out = {}
    for _, pair in ipairs({ ... }) do
      out[#out + 1] = { unitPrice = pair[1], quantity = pair[2] }
    end
    return out
  end

  describe("Fill", function()
    it("returns nil without a book or a positive want", function()
      assert.is_nil(GC.Book.Fill(nil, 10))
      assert.is_nil(GC.Book.Fill(levels(), 10))
      assert.is_nil(GC.Book.Fill(levels({ 100, 5 }), 0))
      assert.is_nil(GC.Book.Fill(levels({ 100, 5 }), nil))
    end)

    it("competes with the leftovers when a fill stops mid-level", function()
      local f = GC.Book.Fill(levels({ 100, 50 }), 20)
      assert.equal(20, f.filled)
      assert.equal(2000, f.total)
      assert.equal(100, f.unit)
      assert.equal(100, f.competing) -- 30 units remain at this very price
      assert.equal(1, f.levelsUsed)
      assert.is_false(f.exhausted)
    end)

    it("competes with the next level when a level is consumed exactly", function()
      local f = GC.Book.Fill(levels({ 100, 20 }, { 150, 30 }), 20)
      assert.equal(150, f.competing)
      assert.equal(1, f.levelsUsed)
      assert.is_false(f.exhausted)
    end)

    it("averages across every level the fill spans", function()
      -- 20 @ 100 + 10 @ 400 = 6000 over 30 units
      local f = GC.Book.Fill(levels({ 100, 20 }, { 400, 30 }), 30)
      assert.equal(30, f.filled)
      assert.equal(6000, f.total)
      assert.equal(200, f.unit)
      assert.equal(400, f.competing)
      assert.equal(2, f.levelsUsed)
    end)

    it("floors a fractional average unit price", function()
      -- 100 + 101 = 201 over 2 units = 100.5
      local f = GC.Book.Fill(levels({ 100, 1 }, { 101, 1 }), 2)
      assert.equal(100, f.unit)
    end)

    it("reports no competing ask when the walk empties the book", function()
      local f = GC.Book.Fill(levels({ 100, 20 }), 20)
      assert.is_nil(f.competing)
      assert.is_false(f.exhausted)
    end)

    it("marks a book too shallow to cover the request", function()
      local f = GC.Book.Fill(levels({ 100, 5 }), 20)
      assert.is_true(f.exhausted)
      assert.equal(5, f.filled)
      assert.equal(500, f.total)
      assert.is_nil(f.competing)
    end)

    it("skips levels with no quantity instead of counting them as used", function()
      local f = GC.Book.Fill(levels({ 100, 0 }, { 120, 10 }), 5)
      assert.equal(120, f.unit)
      assert.equal(1, f.levelsUsed)
    end)
  end)
end)
