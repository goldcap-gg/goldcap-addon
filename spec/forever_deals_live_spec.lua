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
    helper.loadModule("Core/ForeverItemMarket.lua", GC)
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

  -- ClickUp 1an60dzy9nt: a key far under what its own version sells for (40% of its median at most),
  -- seen by the gear loop, is an "Under market" row of the Items board.
  describe("under what its version sells for", function()
    local function info(over)
      local i = { ref = { ref = 5000, ceiling = 2000, perDay = 2, gear = true }, version = "12729", vendor = 300 }
      for k, v in pairs(over or {}) do i[k] = v end
      return i
    end

    it("is a market lead for one lot, priced for its version, still needing its Check", function()
      assert.equal("new", D.LiveMarket(15210, 1800, 2, info(), clock))
      local r = rowOf(15210)
      assert.same({ "market", "items", true, true, "12729", 5000, 2000, 1 },
        { r.forever, r.board, r.live, r.item, r.version, r.refUnit, r.ceiling, r.qty })
      -- 90% of 5000 = 4500, less 225 cut, less a 60c deposit, less 1800
      assert.equal(2415, r.profit)
      assert.equal(2415, r.firstProfit)
      assert.same({ "Check", false, true }, { r.action, r.buyable, r.stale })
      local ceiling = D.CeilingFor(15210)
      assert.same({ 2000, "market", 5000, "12729", 2, 60, true },
        { ceiling.ceilingUnit, ceiling.kind, ceiling.refUnit, ceiling.version, ceiling.perDay, ceiling.depositUnit, ceiling.item })
    end)

    it("makes no row over the ceiling, under the minimum, or with no room left", function()
      assert.is_nil(D.LiveMarket(15210, 2001, 1, info(), clock))
      GC.db.settings.sniper.foreverMinimumProfitCopper = 5000
      assert.is_nil(D.LiveMarket(15210, 1800, 1, info(), clock))
      GC.db.settings.sniper.foreverMinimumProfitCopper = nil
      _G.C_Item = { GetItemCount = function() return 1 end }
      assert.is_nil(D.LiveMarket(15210, 1800, 1, info(), clock)) -- 2 a day: room for one, and one is held
      _G.C_Item = nil
      assert.is_nil(rowOf(15210))
    end)

    it("takes the place of a vendor row of the item that makes less, mid-round", function()
      assert.equal("new", D.Live(15210, 250, 1, 300, clock))
      assert.equal("new", D.LiveMarket(15210, 1800, 1, info(), clock))
      assert.equal("market", rowOf(15210).forever)
      -- and a vendor sighting making less does not take it back before the round ends
      assert.is_nil(D.Live(15210, 260, 1, 300, clock))
      assert.equal("market", rowOf(15210).forever)
      assert.equal("same", D.LiveMarket(15210, 1800, 3, info(), clock))
    end)

    it("at the round's end is the item's row when it makes the most, whatever the other kind", function()
      local market = { kind = "market", unit = 1800, qty = 1, info = info({ key = { itemLevel = 16, itemSuffix = 14299 } }) }
      assert.equal("new", D.LiveBest(15210, { { unit = 250, qty = 1, vendor = 300 }, market }, clock))
      local r = rowOf(15210)
      assert.same({ "market", 16, 14299 }, { r.forever, r.keyLevel, r.keySuffix })
      -- The next round's end saw only a vendor lot: that is the row now.
      assert.equal("new", D.LiveBest(15210, { { unit = 100, qty = 1, vendor = 300 } }, clock))
      assert.equal("vendor", rowOf(15210).forever)
      assert.is_nil(D.LiveBest(15210, { { unit = 299, qty = 1, vendor = 300 } }, clock)) -- 1c: under the minimum
    end)

    it("stands through a rebuild, and leaves once a round no longer sees it", function()
      D.LiveMarket(15210, 1800, 1, info(), clock)
      saved = { at = 4500, items = {} }
      assert.equal("market", rowOf(15210).forever)
      assert.equal(1, D.LiveKeep({}))
      assert.is_nil(rowOf(15210))
    end)
  end)
end)
