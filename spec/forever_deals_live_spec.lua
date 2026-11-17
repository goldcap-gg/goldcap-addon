local helper = require("spec.spec_helper")

-- WoW: Forever: gear the browse between scans saw under the vendor price is a row of the Items
-- board at once, whatever the scan's fold says of the item (GC.ForeverDeals.Live).
describe("ForeverDeals live rows", function()
  local GC, D, saved, vendor, clock

  local function rowOf(itemID)
    for _, r in ipairs(D.Rows(clock)) do
      if r.itemID == itemID then return r end
    end
    return nil
  end

  before_each(function()
    clock = 5000
    _G.time = function() return clock end
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverDeals.lua", GC)
    D = GC.ForeverDeals
    vendor = {}
    saved = { at = 4000, items = {} }
    GC.ForeverScan = { Enabled = function() return true end, Fold = function() return saved end }
    GC.ForeverValue = { VendorUnit = function(id) return vendor[id] end, CommodityDepositUnit = function() return nil end }
    GC.db = { settings = { sniper = {} }, commodityByItem = {} }
  end)

  it("a lot under the vendor price is an Items row: one unit, a vendor lead that still needs its Check", function()
    assert.equal("new", D.Live(3021, 2200, 3, 2426, clock))
    local r = rowOf(3021)
    assert.equal("vendor", r.forever)
    assert.equal("items", r.board)
    assert.is_true(r.live)
    assert.is_false(r.isCommodity)
    assert.equal(2200, r.unitPrice)
    assert.equal(1, r.qty)
    assert.equal(3, r.avail)
    assert.equal(226, r.profit)
    assert.equal(2425, r.ceiling)
    assert.equal("Check", r.action)
    assert.is_false(r.buyable)
    assert.is_true(r.stale)
  end)

  it("hands its ceiling to the live Check as the fold's rows do", function()
    D.Live(3021, 2200, 3, 2426, clock)
    local ceiling = D.CeilingFor(3021)
    assert.equal(2425, ceiling.ceilingUnit)
    assert.equal("vendor", ceiling.kind)
    assert.equal(2426, ceiling.exitUnit)
  end)

  describe("makes no row", function()
    local cases = {
      { name = "at or over the vendor price", args = { 3021, 2426, 1, 2426 } },
      { name = "under the minimum profit of one buy (20c)", args = { 3021, 2410, 5, 2426 } },
      { name = "from numbers that are not whole and positive", args = { 3021, 2200.5, 1, 2426 } },
      { name = "with nothing up", args = { 3021, 2200, 0, 2426 } },
    }
    for _, case in ipairs(cases) do
      it(case.name, function()
        assert.is_nil(D.Live(case.args[1], case.args[2], case.args[3], case.args[4], clock))
        assert.is_nil(rowOf(3021))
      end)
    end

    it("without a scan to stand on", function()
      GC.ForeverScan.Fold = function() return nil end
      assert.is_nil(D.Live(3021, 2200, 1, 2426, clock))
    end)
  end)

  it("the player's own minimum profit decides, a copper from zero", function()
    GC.db.settings.sniper.foreverMinimumProfitCopper = 0
    assert.equal("new", D.Live(3021, 2425, 1, 2426, clock))
  end)

  it("the same lot seen again is the same row, with what is up now", function()
    D.Live(3021, 2200, 3, 2426, clock)
    local first = rowOf(3021)
    assert.equal("same", D.Live(3021, 2200, 2, 2426, clock + 19))
    assert.equal(first, rowOf(3021))
    assert.equal(2, first.avail)
  end)

  it("a cheaper key of the item moves the row; a dearer one does not until the round has read them all", function()
    D.Live(2140, 380, 1, 500, clock)
    assert.is_nil(D.Live(2140, 400, 1, 500, clock))
    assert.equal(380, rowOf(2140).unitPrice)
    assert.equal("new", D.Live(2140, 350, 1, 500, clock))
    assert.equal(350, rowOf(2140).unitPrice)
    assert.equal("new", D.Live(2140, 400, 1, 500, clock + 19, true))
    assert.equal(400, rowOf(2140).unitPrice)
  end)

  it("stands over the fold's own row of the item, through a rebuild", function()
    vendor[3021] = 2426
    saved.items[3021] = "2300,1,2300,;0x1|0,0,1"
    assert.equal(2300, rowOf(3021).unitPrice)
    D.Live(3021, 2200, 1, 2426, clock)
    saved.rev = 2 -- the fold was written again: the board rebuilds
    local r = rowOf(3021)
    assert.equal(2200, r.unitPrice)
    assert.is_true(r.live)
    local count = 0
    for _, row in ipairs(D.Rows(clock)) do
      if row.itemID == 3021 then count = count + 1 end
    end
    assert.equal(1, count)
  end)

  it("leaves once a round no longer sees the lot", function()
    D.Live(3021, 2200, 1, 2426, clock)
    D.Live(2140, 350, 1, 500, clock)
    assert.equal(1, D.LiveKeep({ [2140] = true }))
    assert.is_nil(rowOf(3021))
    assert.is_not_nil(rowOf(2140))
    assert.is_nil(D.LiveRow(3021))
    assert.is_not_nil(D.LiveRow(2140))
    saved.rev = 2
    assert.is_nil(rowOf(3021))
  end)

  it("a Check that found the lot gone takes the row off, and that price is not put back for two minutes", function()
    D.Live(3021, 2200, 1, 2426, clock)
    D.Drop(3021)
    assert.is_nil(rowOf(3021))
    assert.is_nil(D.Live(3021, 2200, 1, 2426, clock + 19))
    assert.equal("new", D.Live(3021, 2100, 1, 2426, clock + 38))
    D.Drop(3021)
    clock = clock + D.C.LIVE_REFUSED_SECONDS + 1
    assert.equal("new", D.Live(3021, 2100, 1, 2426, clock))
  end)

  it("a bought lot takes the row off, and the next round may put it back", function()
    D.Live(3021, 2200, 3, 2426, clock)
    D.Bought(3021, 1)
    assert.is_nil(rowOf(3021))
    assert.equal("new", D.Live(3021, 2200, 2, 2426, clock + 19))
  end)

  it("a new sighting of an item whose fold row a Check dropped is a row again", function()
    vendor[3021] = 2426
    saved.items[3021] = "2300,1,2300,;0x1|0,0,1"
    assert.is_not_nil(rowOf(3021))
    D.Drop(3021)
    assert.is_nil(rowOf(3021))
    assert.equal("new", D.Live(3021, 2200, 1, 2426, clock))
    assert.equal(2200, rowOf(3021).unitPrice)
  end)
end)
