local helper = require("spec.spec_helper")

-- WoW: Forever: between full scans, every browse pass moves the Deals board's live view
-- (GC.ForeverDeals.OnBrowsePass), and the board clock builds again only the rows it moved
-- (GC.ForeverDeals.Refresh). The fold itself is never touched.
describe("ForeverDeals live view from browse passes", function()
  local GC, D, saved, vendor, clock, vendorCalls

  -- 100c x10 .. 300c x10: 50 units in 6 lots.
  local DUMP = "100,50,6,;0x10 20x10 30x10 50x10 100x10|30,80,7"

  local function rows()
    local out = {}
    for _, r in ipairs(D.Rows(clock)) do out[r.itemID] = r end
    return out
  end

  -- A book as Core/BookPass.lua keeps it: a new row table for every item a pass reads.
  local function pass(book, kind, seen)
    for itemID, s in pairs(seen) do
      book[itemID] = { floor = s[1], qty = s[2], seenAt = clock, kind = kind, variants = s.variants }
    end
    return book
  end

  local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
  end

  before_each(function()
    clock = 5000
    _G.time = function() return clock end
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverItemMarket.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/ForeverDeals.lua", GC)
    D = GC.ForeverDeals
    vendor, vendorCalls = { [2589] = 90, [2592] = 90, [4306] = 500 }, 0
    saved = { at = 4000, itemCount = 2, rev = 1, items = { [2589] = DUMP, [2592] = DUMP } }
    GC.ForeverScan = { Enabled = function() return true end, Fold = function() return saved end }
    GC.ForeverValue = {
      VendorUnit = function(id) vendorCalls = vendorCalls + 1; return vendor[id] end,
      CommodityDepositUnit = function() return nil end,
    }
    GC.db = { settings = { sniper = {} }, commodityByItem = {} }
    D.Rows(clock)
  end)

  it("a cheaper lot a pass read is a row by the next board tick, and the fold stays the scan's", function()
    local before = copy(saved.items)
    assert.is_nil(rows()[2589])
    assert.equal(1, D.OnBrowsePass(pass({}, "classes", { [2589] = { 60, 51 } }), true))
    assert.is_nil(rows()[2589]) -- Rows never builds for the view: only the board clock does
    assert.is_true(D.Refresh(clock))
    local r = rows()[2589]
    assert.equal("vendor", r.forever)
    assert.equal(60, r.unitPrice)
    assert.equal(1, r.qty)
    assert.equal(30, r.profit)
    assert.same(before, saved.items)
    assert.equal(4000, saved.at)
  end)

  it("builds again only the items whose floor moved", function()
    D.OnBrowsePass(pass({}, "classes", { [2589] = { 60, 51 }, [2592] = { 100, 50 } }), true)
    vendorCalls = 0
    D.Refresh(clock)
    assert.equal(1, vendorCalls)
  end)

  describe("a row the view made", function()
    local book
    before_each(function()
      book = pass({}, "classes", { [2589] = { 60, 51 }, [2592] = { 100, 50 } })
      D.OnBrowsePass(book, true)
      D.Refresh(clock)
    end)

    local cases = {
      { name = "goes when the floor rises over the vendor price", kind = "classes", whole = true,
        seen = { [2589] = { 100, 50 }, [2592] = { 100, 50 } }, row = false },
      { name = "is priced again at a floor still under it", kind = "classes", whole = true,
        seen = { [2589] = { 70, 50 }, [2592] = { 100, 50 } }, row = 70 },
      { name = "goes when a whole wide pass no longer lists the item", kind = "wide", whole = true,
        seen = { [2592] = { 100, 50 } }, row = false },
      { name = "goes when a whole classes pass no longer lists an item a classes pass listed", kind = "classes",
        whole = true, seen = { [2592] = { 100, 50 } }, row = false },
      { name = "stays when a pass given up did not read it", kind = "wide", whole = false,
        seen = { [2592] = { 100, 50 } }, row = 60 },
      { name = "stays when the same floor is read again", kind = "classes", whole = true,
        seen = { [2589] = { 60, 51 }, [2592] = { 100, 50 } }, row = 60 },
      { name = "is listed while a variant row of it is read", kind = "wide", whole = true,
        seen = { [2589] = { 10, 1, variants = true }, [2592] = { 100, 50 } }, row = 60 },
    }
    for _, case in ipairs(cases) do
      it(case.name, function()
        D.OnBrowsePass(pass(book, case.kind, case.seen), case.whole)
        D.Refresh(clock)
        local r = rows()[2589]
        if case.row then assert.equal(case.row, r and r.unitPrice) else assert.is_nil(r) end
      end)
    end

    it("comes back when a later pass lists the item again", function()
      D.OnBrowsePass(pass(book, "wide", { [2592] = { 100, 50 } }), true)
      D.Refresh(clock)
      D.OnBrowsePass(pass(book, "classes", { [2589] = { 60, 9 } }), true)
      D.Refresh(clock)
      assert.equal(60, rows()[2589].unitPrice)
    end)

    it("keeps its row and its units bought through passes at the same floor", function()
      local r = rows()[2589]
      assert.is_false(D.Refresh(clock))
      D.OnBrowsePass(pass(book, "classes", { [2589] = { 60, 40 }, [2592] = { 100, 50 } }), true)
      assert.is_true(D.Refresh(clock))
      assert.equal(r, rows()[2589])
      assert.equal(40, r.avail)
    end)

    it("a Check that found the lot gone keeps it off at that floor, not at a cheaper one", function()
      D.Drop(2589)
      D.OnBrowsePass(pass(book, "classes", { [2589] = { 60, 51 }, [2592] = { 100, 50 } }), true)
      D.Refresh(clock)
      assert.is_nil(rows()[2589])
      D.OnBrowsePass(pass(book, "classes", { [2589] = { 50, 51 }, [2592] = { 100, 50 } }), true)
      D.Refresh(clock)
      assert.equal(50, rows()[2589].unitPrice)
    end)

    it("passes started over each other say nothing of what they did not read", function()
      book[2592] = { floor = 100, qty = 50, kind = "classes" }
      book[4306] = { floor = 400, qty = 1, kind = "wide" }
      D.OnBrowsePass(book, true)
      D.Refresh(clock)
      assert.equal(60, rows()[2589].unitPrice)
    end)

    it("gives way to the next full scan's fold", function()
      saved = { at = 6000, itemCount = 2, rev = 2, items = { [2589] = DUMP, [2592] = DUMP } }
      D.Refresh(clock)
      assert.is_nil(rows()[2589])
    end)
  end)

  it("an item the fold lacks is a floor-only row, and does not read as a cut scan", function()
    D.OnBrowsePass(pass({}, "classes", { [4306] = { 400, 3 } }), true)
    D.Refresh(clock)
    local r = rows()[4306]
    assert.equal(400, r.unitPrice)
    assert.equal(1, r.qty)
    clock = clock + 60
    D.OnItemInfo(4306)
    GC.db.settings.sniper.foreverMinimumProfitCopper = 20
    saved.rev = 2 -- a whole build reads the view too
    D.Refresh(clock)
    assert.is_nil(rows()[4306])
    assert.is_false(D.MostlyFloors())
  end)

  it("a whole build reads the view over the fold", function()
    D.OnBrowsePass(pass({}, "classes", { [2589] = { 60, 51 } }), true)
    GC.GroupRules = { rev = 1 } -- a followed group changed: the whole board is built again
    D.Refresh(clock)
    assert.equal(60, rows()[2589].unitPrice)
  end)

  it("never counts an item twice", function()
    local book = pass({}, "classes", { [2589] = { 60, 51 }, [2592] = { 70, 50 } })
    for _ = 1, 3 do
      D.OnBrowsePass(book, true)
      D.Refresh(clock)
      pass(book, "classes", { [2589] = { 61, 51 }, [2592] = { 71, 50 } })
    end
    D.Live(2589, 50, 1, 90, clock)
    D.OnBrowsePass(pass(book, "classes", { [2589] = { 62, 51 }, [2592] = { 72, 50 } }), true)
    D.Refresh(clock)
    local seen = {}
    for _, r in ipairs(D.Rows(clock)) do
      assert.is_nil(seen[r.itemID])
      seen[r.itemID] = true
    end
    assert.is_true(rows()[2589].live)
  end)

  it("an answer awaited for one item builds that item again, not the fold", function()
    vendor[4306] = nil
    D.OnBrowsePass(pass({}, "classes", { [4306] = { 400, 3 } }), true)
    D.Refresh(clock)
    assert.is_nil(rows()[4306])
    vendor[4306] = 500
    vendorCalls = 0
    D.OnItemInfo(4306)
    assert.is_true(D.Refresh(clock))
    assert.equal(1, vendorCalls)
    assert.equal(400, rows()[4306].unitPrice)
  end)

  it("reads Core/BookPass.lua's own book", function()
    local results = {}
    local done = 0
    local bp = GC.BookPass.New({
      now = function() return clock end,
      sendBrowseQuery = function() end,
      requestMoreBrowseResults = function() end,
      hasFullBrowseResults = function() return true end,
      getBrowseResults = function() return results end,
      triggerFor = function() return nil end,
      onHit = function() end,
      onRows = function() end,
      onPassDone = function() done = done + 1 end,
    })
    local function run(kind, list)
      bp:Start(kind)
      bp:OnThrottleReady()
      bp:OnResultsAdded(list)
      D.OnBrowsePass(bp:Book(), true)
      D.Refresh(clock)
    end
    run("classes", { { itemKey = { itemID = 2589 }, minPrice = 60, totalQuantity = 51 },
      { itemKey = { itemID = 2592 }, minPrice = 100, totalQuantity = 50 } })
    assert.equal(60, rows()[2589].unitPrice)
    run("classes", { { itemKey = { itemID = 2592 }, minPrice = 100, totalQuantity = 50 } })
    assert.is_nil(rows()[2589])
    assert.equal(2, done)
  end)

  it("bounds a pass over a big fold: one vendor read per moved item, the asks within a build's", function()
    local items, book, n = {}, {}, 25000
    for i = 1, n do
      items[100000 + i] = DUMP
      vendor[100000 + i] = 90
    end
    saved = { at = 4000, itemCount = n, rev = 7, items = items }
    D.Rows(clock)
    for i = 1, n do book[100000 + i] = { floor = 100, qty = 50, kind = "wide" } end
    D.OnBrowsePass(book, true)
    D.Refresh(clock)
    local known, asks = 0, 0
    GC.ForeverValue.Known = function() known = known + 1; return false end
    GC.ForeverValue.VendorUnit = function(id, ask)
      vendorCalls = vendorCalls + 1
      if ask then asks = asks + 1 end
      return vendor[id]
    end
    -- The next wide pass reads every item again (new row tables), 1,600 of them at a new floor.
    for i = 1, n do book[100000 + i] = { floor = i % 15 == 0 and i <= 24000 and 60 or 100, qty = 50, kind = "wide" } end
    vendorCalls = 0
    local t0 = os.clock()
    D.OnBrowsePass(book, true)
    local t1 = os.clock()
    assert.is_true(D.Refresh(clock))
    local t2 = os.clock()
    print(("\n  live view, 25,000 items, 1,600 floors moved: pass %.1f ms, board %.1f ms"):format(
      (t1 - t0) * 1000, (t2 - t1) * 1000))
    assert.equal(1600, vendorCalls)
    assert.is_true(asks <= D.C.ASKS_PER_BUILD)
    assert.equal(D.C.ROW_CAP, #D.Rows(clock)) -- one board here: no item has a commodity answer
  end)
end)
