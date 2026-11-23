local helper = require("spec.spec_helper")

-- WoW: Forever: flips through the neutral Blackwater house (ClickUp 1an60dzy5r4). The numbers are
-- real rows of Blizzard's US Normal snapshot of 2026-11-22 16:25 UTC (house 117 against 111).
describe("ForeverFlips", function()
  local GC, F
  local AT = 1795371900

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/ImportString.lua", GC)
    helper.loadModule("Core/ForeverFlips.lua", GC)
    F = GC.ForeverFlips
  end)

  local function payload(items, sales, hours)
    return { blackwater = { at = AT, items = items }, sales = sales, salesHours = hours }
  end

  describe("the rule", function()
    it("takes the 5% cut off the home price", function()
      assert.equal(1235000, F.Sell(1300000))
      assert.equal(85500, F.Sell(90000))
      assert.equal(9, F.Sell(10))
    end)

    -- The cap is what BUY may pay: the dearer of the two floors wins, 15% for a dear item, 1s for a
    -- cheap one.
    it("caps a unit where it still makes 15% and at least 1s", function()
      assert.equal(1073913, F.Cap(1300000))
      assert.equal(74347, F.Cap(90000))
      assert.equal(826, F.Cap(1000))
      assert.equal(375, F.Cap(500))
    end)

    it("says a flip is a price at or under the cap", function()
      assert.is_true(F.IsFlip(500000, 1300000))
      assert.is_true(F.IsFlip(1073913, 1300000))
      assert.is_false(F.IsFlip(1073914, 1300000))
      assert.is_false(F.IsFlip(80000, 90000))
      assert.is_false(F.IsFlip(0, 90000))
      assert.is_false(F.IsFlip(500, 0))
      assert.is_false(F.IsFlip(nil, 90000))
    end)
  end)

  describe("the list", function()
    it("is nil when the payload has no Blackwater section", function()
      assert.is_nil(F.Rows({ items = {} }, AT))
      assert.is_nil(F.Rows(nil, AT))
    end)

    it("lists the flips that make 1g a unit or more, the best first, with what each makes", function()
      local list = F.Rows(payload({
        [13493] = { bw = 500000, bwQty = 1, home = 1300000, homeQty = 10 }, -- Recipe: Greater Arcane Elixir
        [9433] = { bw = 25000, bwQty = 1, home = 90000, homeQty = 6 },       -- Forgotten Wraps
        [13138] = { bw = 35099, bwQty = 3, home = 77000, homeQty = 5 },      -- The Silencer
        [6367] = { bw = 99998, bwQty = 4, home = 140000, homeQty = 33 },     -- Big Iron Fishing Pole
        [1] = { bw = 80000, bwQty = 1, home = 90000, homeQty = 6 },          -- not a flip
        [2] = { bw = 4000, bwQty = 9, home = 9000, homeQty = 6 },            -- a flip under 1g
      }), AT + 60)
      assert.equal(AT, list.at)
      assert.is_false(list.stale)
      local ids = {}
      for i, r in ipairs(list.rows) do ids[i] = r.itemID end
      assert.same({ 13493, 9433, 13138, 6367 }, ids)
      local elixir = list.rows[1]
      assert.equal(735000, elixir.profit)
      assert.equal(147, elixir.pct)
      assert.equal(1073913, elixir.cap)
      assert.equal(60500, list.rows[2].profit)
      assert.equal(242, list.rows[2].pct)
      assert.equal(38051, list.rows[3].profit)
      assert.equal(3, list.rows[3].bwQty)
    end)

    it("says nothing of speed without a sales tape, and slow when the home house sold under one a day", function()
      local items = {
        [13493] = { bw = 500000, bwQty = 1, home = 1300000, homeQty = 10 },
        [9433] = { bw = 25000, bwQty = 1, home = 90000, homeQty = 6 },
      }
      local none = F.Rows(payload(items), AT)
      assert.is_nil(none.rows[1].sold)
      assert.is_nil(none.rows[1].slow)
      local taped = F.Rows(payload(items, { [13493] = { units = 14, sales = 12, median = 1290000, p25 = 1250000 } }, 168), AT)
      assert.equal(14, taped.rows[1].sold)
      assert.equal(168, taped.rows[1].soldHours)
      assert.is_nil(taped.rows[1].slow)
      assert.equal(0, taped.rows[2].sold)
      assert.is_true(taped.rows[2].slow)
    end)

    it("calls a snapshot older than three hours stale", function()
      local items = { [13493] = { bw = 500000, bwQty = 1, home = 1300000, homeQty = 10 } }
      assert.is_false(F.Rows(payload(items), AT + F.STALE_SECONDS).stale)
      assert.is_true(F.Rows(payload(items), AT + F.STALE_SECONDS + 1).stale)
    end)

    it("reads straight from what ParseForever returns", function()
      local p = GC.ImportString.ParseForever("GCF1;s;91;All Normal realms;Alliance;" .. AT
        .. ";I:13493=1300000=1300000===10=1=0;B:" .. AT .. ",13493=500000=1=1300000=10")
      local list = F.Rows(p, AT)
      assert.equal(1, #list.rows)
      assert.equal(735000, list.rows[1].profit)
    end)

    -- The speed reads the sales tape under the names ParseForever gives it: a rename there would
    -- leave every row without a speed and every spec above still green.
    it("reads the speed from the sales tape ParseForever returns", function()
      local p = GC.ImportString.ParseForever("GCF1;s;91;All Normal realms;Alliance;" .. AT
        .. ";I:13493=1300000=1300000===10=1=0,9433=90000=90000===6=1=0;H:168;S:13493=14=12=1290000=1250000"
        .. ";B:" .. AT .. ",13493=500000=1=1300000=10,9433=25000=1=90000=6")
      local list = F.Rows(p, AT)
      assert.equal(14, list.rows[1].sold)
      assert.equal(168, list.rows[1].soldHours)
      assert.is_nil(list.rows[1].slow)
      assert.equal(0, list.rows[2].sold)
      assert.is_true(list.rows[2].slow)
    end)
  end)

  describe("the checked rows", function()
    local rows
    before_each(function()
      rows = F.Rows(payload({
        [13493] = { bw = 500000, bwQty = 1, home = 1300000, homeQty = 10 },
        [10822] = { bw = 230000, bwQty = 1, home = 450000, homeQty = 4 },
        [9433] = { bw = 25000, bwQty = 1, home = 90000, homeQty = 6 },
      }), AT).rows
    end)

    it("totals one unit of each, all of them or only the checked", function()
      assert.same({ 3, 755000, 993000 }, { F.Totals(rows) })
      assert.same({ 2, 525000, 795500 }, { F.Totals(rows, { [13493] = true, [9433] = true }) })
      assert.same({ 0, 0, 0 }, { F.Totals(rows, {}) })
    end)

    it("makes BUY lines of one unit each, capped where the flip ends", function()
      local lines, caps = F.Lines(rows, { [13493] = true, [10822] = true })
      assert.same({ { i = 13493, q = 1 }, { i = 10822, q = 1 } }, lines)
      assert.same({ [13493] = 1073913, [10822] = F.Cap(450000) }, caps)
      assert.same({}, (F.Lines(rows, nil)))
    end)
  end)
end)
