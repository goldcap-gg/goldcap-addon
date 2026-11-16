local helper = require("spec.spec_helper")

-- WoW: Forever: gear under the vendor price, judged from a browse row (Core/ForeverGearLoop.lua).
describe("ForeverGearLoop", function()
  local GC, L, vendor, known

  local function row(itemID, level, suffix, minPrice, qty)
    return { itemKey = { itemID = itemID, itemLevel = level, itemSuffix = suffix, battlePetSpeciesID = 0 },
      minPrice = minPrice, totalQuantity = qty }
  end

  local function new()
    return L.New({
      vendorFor = function(id) return vendor[id] end,
      known = function(id) return known[id] == true or vendor[id] ~= nil end,
    })
  end

  before_each(function()
    GC = helper.loadModule("Core/ForeverGearLoop.lua")
    L = GC.ForeverGearLoop
    vendor, known = {}, {}
  end)

  describe("a page of browse rows", function()
    local cases = {
      { name = "a key cheaper than the vendor price is under it",
        rows = { row(3021, 20, 0, 2200, 1) }, vendor = { [3021] = 2426 }, under = { "3021/20/0 2200" } },
      { name = "a key at the vendor price is not",
        rows = { row(3021, 20, 0, 2426, 1) }, vendor = { [3021] = 2426 }, under = {} },
      { name = "each suffix is its own key, judged against the item's one vendor price",
        rows = { row(2140, 11, 14315, 400, 121), row(2140, 11, 14300, 350, 13), row(2140, 11, 14307, 2500, 6) },
        vendor = { [2140] = 401 }, under = { "2140/11/14315 400", "2140/11/14300 350" } },
      { name = "a key with nothing up, or no price, is no lot",
        rows = { row(2140, 11, 0, 0, 0), row(2141, 20, 0, 100, 0), { itemKey = { itemID = 5 } } },
        vendor = { [2140] = 500, [2141] = 500, [5] = 500 }, under = {} },
      { name = "an item with no kept vendor price is not judged",
        rows = { row(7001, 30, 0, 1, 1) }, vendor = {}, under = {}, ask = { 7001 } },
      { name = "an item kept as having no vendor price is neither judged nor asked about",
        rows = { row(7002, 30, 0, 1, 1) }, vendor = {}, knownItems = { [7002] = true }, under = {}, ask = {} },
    }
    for _, case in ipairs(cases) do
      it(case.name, function()
        vendor, known = case.vendor, case.knownItems or {}
        local loop = new()
        loop:BeginRound(100)
        local under, ask = loop:Fold(case.rows)
        local got = {}
        for _, u in ipairs(under) do got[#got + 1] = L.KeyText(u.key) .. " " .. u.unit end
        assert.same(case.under, got)
        if case.ask then assert.same(case.ask, ask) end
      end)
    end

    it("says what the lot is: the unit, how many are up, what a vendor pays", function()
      vendor = { [3021] = 2426 }
      local loop = new()
      loop:BeginRound(100)
      local under = loop:Fold({ row(3021, 20, 0, 2200, 3) })
      assert.equal(3021, under[1].itemID)
      assert.equal(2200, under[1].unit)
      assert.equal(3, under[1].qty)
      assert.equal(2426, under[1].vendor)
    end)

    it("folds nothing outside a round", function()
      vendor = { [3021] = 2426 }
      local under = new():Fold({ row(3021, 20, 0, 2200, 1) })
      assert.same({}, under)
    end)
  end)

  describe("the client is asked about unknown items", function()
    it("at most ASKS_PER_PAGE a page", function()
      local rows = {}
      for i = 1, L.C.ASKS_PER_PAGE + 10 do rows[i] = row(9000 + i, 10, 0, 5, 1) end
      local loop = new()
      loop:BeginRound(100)
      local _, ask = loop:Fold(rows)
      assert.equal(L.C.ASKS_PER_PAGE, #ask)
      local _, more = loop:Fold(rows)
      assert.equal(10, #more)
    end)

    it("once a session, whatever round it is seen in again", function()
      local loop = new()
      loop:BeginRound(100)
      local _, ask = loop:Fold({ row(9001, 10, 0, 5, 1), row(9001, 10, 77, 6, 1) })
      assert.same({ 9001 }, ask)
      loop:EndRound(120)
      loop:BeginRound(121)
      local _, again = loop:Fold({ row(9001, 10, 0, 5, 1) })
      assert.same({}, again)
    end)
  end)

  describe("a round", function()
    it("ends with what it read and the items it saw under the vendor price", function()
      vendor = { [2140] = 401, [3021] = 2426 }
      local loop = new()
      loop:BeginRound(100)
      loop:Fold({ row(2140, 11, 14315, 400, 121), row(2140, 11, 14300, 350, 13), row(4000, 5, 0, 9, 1) })
      loop:Fold({ row(3021, 20, 0, 9999, 1) })
      local figures = loop:EndRound(119.5)
      assert.equal(19.5, figures.seconds)
      assert.equal(4, figures.rows)
      assert.equal(2, figures.pages)
      assert.equal(1, figures.underCount)
      assert.equal(1, figures.unknown)
      assert.is_not_nil(figures.under[2140])
      assert.is_nil(figures.under[3021])
      assert.is_false(loop:InRound())
    end)

    it("keeps an item's keys under the vendor price as a browse by its name would leave them", function()
      vendor = { [2140] = 401 }
      local loop = new()
      loop:BeginRound(100)
      loop:Fold({ row(2140, 11, 14315, 400, 121), row(2140, 11, 14300, 350, 13) })
      local variants = loop:Variants(2140)
      assert.equal(2, #variants)
      assert.equal(14300, variants[2].itemSuffix)
      assert.equal(350, variants[2].floor)
      assert.equal(11, variants[2].itemLevel)
    end)

    it("keeps every key with lots of an item the board already shows, under the vendor price or not", function()
      vendor = { [2140] = 300 }
      local loop = L.New({ vendorFor = function(id) return vendor[id] end,
        known = function() return true end, listed = function(id) return id == 2140 end })
      loop:BeginRound(100)
      local under = loop:Fold({ row(2140, 11, 14315, 400, 121), row(2140, 11, 14300, 350, 13), row(4000, 5, 0, 9, 1) })
      assert.same({}, under)
      assert.equal(2, #loop:Variants(2140))
      assert.is_nil(loop:Variants(4000))
      assert.is_not_nil(loop:Tracked()[2140])
    end)

    it("cut short answers nothing", function()
      vendor = { [2140] = 401 }
      local loop = new()
      loop:BeginRound(100)
      loop:Fold({ row(2140, 11, 14315, 400, 121) })
      loop:AbortRound()
      assert.is_nil(loop:EndRound(110))
      assert.is_nil(loop:Variants(2140))
    end)
  end)

  describe("the lots waiting for their Check", function()
    it("come oldest first, one an item, and are let go after HIT_WAIT_SECONDS", function()
      local loop = new()
      loop:Push(1, 100, 10)
      loop:Push(2, 200, 12)
      loop:Push(1, 90, 14)
      local waiting = loop:Waiting(15)
      assert.equal(2, #waiting)
      assert.equal(2, waiting[1].itemID)
      assert.equal(90, waiting[2].unit)
      assert.equal(1, #loop:Waiting(12 + L.C.HIT_WAIT_SECONDS + 1))
      assert.equal(1, loop:Take(1).itemID)
      assert.equal(0, #loop:Waiting(15))
    end)
  end)

  describe("the save's journal", function()
    it("keeps the last rounds and lots, and is made by the first note alone", function()
      local root = {}
      assert.is_nil(L.Journal(root, false))
      for i = 1, L.C.KEEP_ROUNDS + 3 do
        L.NoteRound(root, 1000 + i, { seconds = 19.25, rows = 13963, pages = 29, underCount = 2, unknown = 40 })
      end
      assert.equal(L.C.KEEP_ROUNDS, #root.foreverGearLoop.rounds)
      assert.equal(("%d 19.2 13963 29 2 40"):format(1000 + L.C.KEEP_ROUNDS + 3),
        root.foreverGearLoop.rounds[L.C.KEEP_ROUNDS])
      L.NoteHit(root, 2000, "3021/20/0", 2200, 2426, 0.75)
      assert.equal("2000 3021/20/0 2200 v2426 0.8", root.foreverGearLoop.hits[1])
    end)

    it("leaves a store of another shape alone", function()
      local root = { foreverGearLoop = { v = 2 } }
      L.NoteRound(root, 1, { seconds = 1 })
      assert.same({ v = 2 }, root.foreverGearLoop)
    end)
  end)
end)
