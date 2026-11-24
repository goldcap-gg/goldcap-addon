local helper = require("spec.spec_helper")

-- WoW: Forever's finds and checks for DEALS' AUTO readout (Core/AutoReadout.lua). There is no
-- drill there: a find is a row that appears on the board between two looks, whichever made it
-- (a browse pass's patch, a full scan's rebuild, the gear loop), and checked is the first live
-- Check answered for it (GC.ForeverDeals.Found, GC.ForeverDeals.Checked).
describe("Forever AUTO finds and checks", function()
  local GC, D, AR, saved, vendor, clock

  describe("the items that appeared between two looks", function()
    before_each(function()
      GC = helper.loadModule("Core/ForeverDeals.lua")
      D = GC.ForeverDeals
    end)

    local a, b = { itemID = 1, unitPrice = 60 }, { itemID = 2, unitPrice = 70 }
    local CASES = {
      { "a new row", { [1] = a }, { [1] = a, [2] = b }, { 2 } },
      { "the same row repriced", { [1] = a }, { [1] = { itemID = 1, unitPrice = 55 } }, {} },
      { "a row gone", { [1] = a, [2] = b }, { [1] = a }, {} },
      { "the row back", { [1] = a }, { [1] = a, [2] = b }, { 2 } },
      { "a full scan's rebuild with the same rows", { [1] = a, [2] = b },
        { [1] = { itemID = 1, unitPrice = 60 }, [2] = { itemID = 2, unitPrice = 70 } }, {} },
      { "a fold row replaced by the gear loop's live row", { [1] = a },
        { [1] = { itemID = 1, unitPrice = 40, live = true } }, {} },
      { "no earlier look", nil, { [1] = a, [2] = b }, {} },
      { "two new rows, in item order", {}, { [2] = b, [1] = a }, { 1, 2 } },
    }
    for _, case in ipairs(CASES) do
      it(case[1], function()
        assert.same(case[4], D.Appeared(case[2], case[3]))
      end)
    end
  end)

  -- 100c x10 .. 300c x10: 50 units in 6 lots, over every vendor price below but 4306's.
  local DUMP = "100,50,6,;0x10 20x10 30x10 50x10 100x10|30,80,7"

  local function pass(seen)
    local book = {}
    for itemID, s in pairs(seen) do book[itemID] = { floor = s[1], qty = s[2], seenAt = clock, kind = "classes" } end
    return book
  end

  local function counts() return AR.Counts(clock) end

  before_each(function()
    clock = 5000
    _G.time = function() return clock end
    _G.GetTime = function() return clock end
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverItemMarket.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/ForeverDeals.lua", GC)
    helper.loadModule("Core/AutoReadout.lua", GC)
    D, AR = GC.ForeverDeals, GC.AutoReadout
    AR._Reset()
    vendor = { [2589] = 90, [2592] = 90, [2996] = 90, [4306] = 90 }
    saved = { at = 4000, itemCount = 4, rev = 1, items = { [2589] = DUMP, [2592] = DUMP, [2996] = DUMP, [4306] = DUMP } }
    GC.ForeverScan = { Enabled = function() return true end, Fold = function() return saved end }
    GC.ForeverValue = {
      VendorUnit = function(id) return vendor[id] end,
      CommodityDepositUnit = function() return nil end,
    }
    GC.db = { settings = { sniper = {} }, commodityByItem = {} }
    D.Rows(clock) -- the first look: nothing on the board was found
  end)
  after_each(function() _G.time, _G.GetTime = os.time, nil end)

  it("one browse pass that adds 3 Commodities rows, one of them then checked", function()
    D.OnBrowsePass(pass({ [2589] = { 60, 51 }, [2592] = { 61, 51 }, [2996] = { 62, 51 } }), true)
    assert.is_true(D.Refresh(clock))
    local rows = {}
    for _, r in ipairs(D.Rows(clock)) do rows[r.itemID] = r end
    for _, itemID in ipairs({ 2589, 2592, 2996 }) do assert.equal("commodities", rows[itemID].board) end
    assert.same({ finds = 3, checked = 0, deals = 0 }, counts())

    assert.is_true(D.Checked(2592))
    assert.is_false(D.Checked(2592)) -- its second Check is a recheck, not a find's
    assert.is_false(D.Checked(4306)) -- no row of it
    assert.same({ finds = 3, checked = 1, deals = 0 }, counts())
    assert.equal("5 min: 3 finds · 1 checked · 0 deals · 0 req/min",
      AR.Lines({ counts = counts(), perMinute = 0 }).recent[1])
  end)

  it("a row only repriced, or rebuilt by a full scan with the same rows, is no new find", function()
    D.OnBrowsePass(pass({ [2589] = { 60, 51 } }), true)
    D.Refresh(clock)
    D.OnBrowsePass(pass({ [2589] = { 55, 51 } }), true)
    D.Refresh(clock)
    assert.equal(55, D.Rows(clock)[1].unitPrice)
    -- The next full scan saw the same cheap lots: a new fold, its board built again whole.
    local items = {}
    for itemID, dump in pairs(saved.items) do items[itemID] = dump end
    items[2589] = (DUMP:gsub("^100", "55"))
    saved = { at = 5100, itemCount = 4, rev = 2, items = items }
    clock = 5100
    assert.is_true(D.Refresh(clock))
    assert.equal(55, D.Rows(clock)[1].unitPrice)
    assert.same({ finds = 1, checked = 0, deals = 0 }, counts())
  end)

  it("an item that leaves the board and comes back is found again, and owes its Check again", function()
    D.OnBrowsePass(pass({ [2589] = { 60, 51 } }), true)
    D.Refresh(clock)
    assert.is_true(D.Checked(2589))
    D.OnBrowsePass(pass({ [2589] = { 100, 51 } }), true) -- the cheap lots are gone: no row
    D.Refresh(clock)
    assert.equal(0, #D.Rows(clock))
    D.OnBrowsePass(pass({ [2589] = { 60, 51 } }), true)
    D.Refresh(clock)
    assert.same({ finds = 2, checked = 1, deals = 0 }, counts())
    assert.is_true(D.Checked(2589))
  end)

  it("a row dropped by its Check and put back by a pass is found again", function()
    D.OnBrowsePass(pass({ [2589] = { 60, 51 } }), true)
    D.Refresh(clock)
    D.Drop(2589)
    D.OnBrowsePass(pass({ [2589] = { 58, 51 } }), true)
    D.Refresh(clock)
    assert.same({ finds = 2, checked = 0, deals = 0 }, counts())
  end)

  it("the gear loop's find and a board look of the same row count it once", function()
    local admit = D.Live(3021, 50, 1, 90, clock) -- not in the fold: an Items row
    assert.equal("new", admit)
    assert.is_true(D.Found(3021)) -- the loop's push
    assert.is_false(D.Found(3021)) -- a dearer key of it, pushed again
    D.OnBrowsePass(pass({ [2589] = { 60, 51 } }), true)
    D.Refresh(clock) -- the patch keeps the live row: nothing new of it
    assert.same({ finds = 2, checked = 0, deals = 0 }, counts())
    -- Its Check answers twice (the loop's, then the walk's): one check.
    assert.is_true(D.Checked(3021))
    assert.is_false(D.Checked(3021))
    assert.same({ finds = 2, checked = 1, deals = 0 }, counts())
  end)

  it("a fold row the gear loop's live row replaces is no new find", function()
    D.OnBrowsePass(pass({ [2589] = { 60, 51 } }), true)
    D.Refresh(clock)
    assert.equal("new", D.Live(2589, 40, 1, 90, clock))
    assert.is_false(D.Found(2589))
    assert.same({ finds = 1, checked = 0, deals = 0 }, counts())
  end)

  it("a board with no fold forgets what it saw: the next first look finds nothing", function()
    D.OnBrowsePass(pass({ [2589] = { 60, 51 } }), true)
    D.Refresh(clock)
    GC.ForeverScan.Enabled = function() return false end
    D.Rows(clock)
    GC.ForeverScan.Enabled = function() return true end
    D.Rows(clock)
    assert.is_false(D.Checked(2589)) -- a row of the first look owes no find's Check
    assert.same({ finds = 1, checked = 0, deals = 0 }, counts())
  end)
end)
