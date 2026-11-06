local helper = require("spec.spec_helper")

describe("ForeverDeals", function()
  local GC, D, vendor, commodity

  local function ctx(over)
    local c = {
      vendorFor = function(id) return vendor[id] end,
      isCommodity = function(id) return commodity[id] end,
      depositFor = function() return nil end,
      minimumProfit = 20,
      watchPins = {},
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
  end

  local function fold(items) return { at = 5000, items = items } end

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/ForeverFold.lua", GC)
    helper.loadModule("Core/ForeverDeals.lua", GC)
    D = GC.ForeverDeals
    vendor, commodity = {}, {}
  end)

  -- The owner's board (beta, 2026-09-27 11:13) showed five SAFE rows with no kind on them, one at a
  -- 2% discount, and read them as retail verdicts. Both kinds make exactly those figures.
  describe("the owner's board of 2026-09-27", function()
    it("a 2% discount is a vendor row: 32 at 49c, a vendor pays 50c, +1c each", function()
      vendor[1081], commodity[1081] = 50, true            -- Crisp Spider Meat
      local rows = D.Build(fold({ [1081] = "49,727,50,;0x32 1x695|0,1,2" }), ctx())
      assert.equal(1, #rows)
      local r = rows[1]
      assert.equal("vendor", r.forever)
      assert.equal(32, r.qty); assert.equal(1568, r.capTotal); assert.equal(32, r.profit)
      assert.equal(2, math.floor(r.discount * 100 + 0.5))
    end)

    -- Resold as the Check resells (review 2026-11-06): one copper under the 15c level the buy
    -- leaves, 14c, not the AH value's 18c.
    it("a 44% discount is a market row: 165 at 10c, measured at 18c (half-way under its AH value), +3c each", function()
      vendor[765], commodity[765] = 1, true               -- Silverleaf; a vendor pays under the AH
      local rows = D.Build(fold({ [765] = "10,4062,200,;0x165 5x100 8x3797|0,8,15" }),
        ctx({ depositFor = function() return 0 end }))
      assert.equal(1, #rows)
      local r = rows[1]
      assert.equal("market", r.forever)
      assert.equal(165, r.qty); assert.equal(1650, r.capTotal); assert.equal(544, r.profit) -- 14c x165 - 5% - 1650
      assert.equal(44, math.floor(r.discount * 100 + 0.5))
    end)
  end)

  -- Owner's evening of 2026-11-06: every full dump came back cut at 1023 rows, the browse pass
  -- priced 1525 items by their lowest price alone, and the board said "deals 0".
  describe("Build, floor-only entries (the server cut the full dump short)", function()
    it("makes a one-unit vendor row from an item's lowest price, and counts the floor-only entries", function()
      vendor[1], commodity[1] = 999, true
      local rows, _, _, floorOnly = D.Build(fold({ [1] = "500,2,,b;", [3] = "8,355,5,;0x5 1x10" }), ctx())
      assert.equal(1, #rows)
      local r = rows[1]
      assert.equal("vendor", r.forever)
      assert.equal(1, r.qty); assert.equal(2, r.avail)          -- one unit proven, two listed
      assert.equal(500, r.unitPrice); assert.equal(499, r.profit)
      assert.equal(1, floorOnly)
    end)

    it("tells the readout when at least half the scan's items had only their lowest price", function()
      GC.ForeverScan = { Enabled = function() return true end,
        Fold = function() return GC._fold end }
      GC.ForeverValue = { VendorUnit = function() return nil end, CommodityDepositUnit = function() return nil end }
      GC.db = { settings = { sniper = {} }, commodityByItem = {} }
      GC._fold = { at = 5000, rev = 1, itemCount = 3,
        items = { [1] = "500,2,,b;", [2] = "600,2,,b;", [3] = "8,355,5,;0x5 1x10" } }
      D.Rows(6000)
      assert.is_true(D.MostlyFloors())
      GC._fold = { at = 7000, rev = 2, itemCount = 3,
        items = { [1] = "500,2,,b;", [2] = "8,355,5,;0x5", [3] = "8,355,5,;0x5 1x10" } }
      D.Rows(8000)
      assert.is_false(D.MostlyFloors())
    end)

    it("wants the minimum profit from that one unit", function()
      vendor[1], commodity[1] = 510, true
      assert.equal(0, #D.Build(fold({ [1] = "500,2000,,b;" }), ctx()))   -- +10c, not 20c
    end)

    local function crowd(value, at)
      return function() return { value = value, source = "crowd", at = at, scanners = 3 } end
    end

    it("measures a commodity's lowest price against the crowd's AH value: one unit", function()
      commodity[2] = true
      local rows = D.Build(fold({ [2] = "300,40,,b;" }),
        ctx({ depositFor = function() return 10 end, referenceFor = crowd(1000, 4000) }))
      assert.equal(1, #rows)
      local r = rows[1]
      assert.equal("market", r.forever)
      assert.equal(1, r.qty); assert.equal("crowd", r.refSource)
      assert.equal(1000 - 50 - 300 - 10, r.profit)                     -- resold at 1000, 5% cut, deposit
    end)

    it("never measures it against its own figure, a crowd much older than the scan, or a thin book", function()
      commodity[2] = true
      local deposit = function() return 0 end
      local entry = { [2] = "300,40,,b;" }
      assert.equal(0, #D.Build(fold(entry), ctx({ depositFor = deposit,
        referenceFor = function() return { value = 1000, source = "own" } end })))
      assert.equal(0, #D.Build(fold(entry), ctx({ depositFor = deposit,
        referenceFor = crowd(1000, 5000 - D.C.FLOOR_CROWD_MAX_AGE_SECONDS - 1) })))
      assert.equal(1, #D.Build(fold(entry), ctx({ depositFor = deposit,
        referenceFor = crowd(1000, 5000 - D.C.FLOOR_CROWD_MAX_AGE_SECONDS) })))
      assert.equal(0, #D.Build(fold({ [2] = "300,19,,b;" }), ctx({ depositFor = deposit,
        referenceFor = crowd(1000, 4000) })))                              -- under 20 units listed
    end)
  end)

  describe("Build, kind vendor", function()
    -- Linen-shaped: 8c x5, 9c x10, 12c x40, 13c x100, 15c x200; a vendor pays 13c.
    local LINEN = "8,355,5,;0x5 1x10 3x40 1x100 2x200"

    it("lists the levels strictly under the vendor price, with the exact cost and profit", function()
      vendor[2589], commodity[2589] = 13, true
      local rows, missing = D.Build(fold({ [2589] = LINEN }), ctx())
      assert.equal(0, #missing)
      assert.equal(1, #rows)
      local r = rows[1]
      assert.equal("vendor", r.forever)
      assert.equal(12, r.ceiling)        -- vendor - 1
      assert.equal(13, r.refUnit)
      assert.equal(8, r.unitPrice)       -- the cheapest level
      assert.equal(55, r.qty)            -- 5 + 10 + 40
      assert.equal(355, r.avail)
      assert.equal(610, r.capTotal)      -- 40 + 90 + 480
      assert.equal(105, r.profit)        -- 5*5 + 4*10 + 1*40, no cut, no fee
      assert.equal(105, r.estProfit)
      assert.equal(13, r.mv)
      assert.is_true(math.abs(r.discount - (1 - 8 / 13)) < 1e-9)
      assert.is_true(r.isCommodity)
      assert.equal("commodities", r.board)
      assert.equal("WATCH", r.status); assert.equal("Check", r.action)
      assert.is_false(r.buyable); assert.is_true(r.stale)
      assert.equal("live_verification_required", r.reason)
    end)

    it("makes no row when nothing is under the vendor price", function()
      vendor[4000] = 20
      assert.equal(0, #D.Build(fold({ [4000] = "20,10,1,;0x10" }), ctx()))
    end)

    it("makes no row under the Forever minimum, and one when the player lowered theirs", function()
      vendor[3000] = 10
      local f = fold({ [3000] = "9,3,1,;0x3" })            -- 3 units x 1c profit = 3c
      assert.equal(0, #D.Build(f, ctx()))
      assert.equal(1, #D.Build(f, ctx({ minimumProfit = 1 })))
    end)

    it("never guesses a vendor price: no row, and the item is named as missing", function()
      local rows, missing = D.Build(fold({ [2589] = LINEN }), ctx())
      assert.equal(0, #rows)
      assert.same({ 2589 }, missing)
    end)

    it("puts known non-commodities and gear on the Items board, unknown on Commodities", function()
      vendor[10], vendor[11], vendor[12] = 500, 500, 500
      commodity[10], commodity[11] = false, nil
      local rows = D.Build(fold({ [10] = "100,1,1,;0x1", [11] = "100,1,1,;0x1", [12] = "100,1,1,g;0x1" }), ctx())
      local board = {}
      for _, r in ipairs(rows) do board[r.itemID] = r.board end
      assert.equal("items", board[10])
      assert.equal("commodities", board[11])
      assert.equal("items", board[12])   -- the fold's gear flag
    end)

    -- Review, 2026-11-06: an Items-board buy is one lot (PlaceBid), so the minimum profit per buy
    -- is met by one lot or not at all. 53 Training Swords at 6c profit each summed to 318c.
    describe("the minimum profit per buy on the Items board", function()
      local SWORDS = "94,53,53,g;0x53"                    -- 53 lots of one, 94c each

      it("refuses gear whose every lot makes less than the minimum, however many lots there are", function()
        vendor[2495] = 100
        assert.equal(0, #D.Build(fold({ [2495] = SWORDS }), ctx()))
      end)

      it("lists it once one lot clears the minimum, with the row's totals as they were", function()
        vendor[2495] = 100
        local rows = D.Build(fold({ [2495] = SWORDS }), ctx({ minimumProfit = 6 }))
        assert.equal(1, #rows)
        assert.equal("items", rows[1].board)
        assert.equal(53, rows[1].qty)
        assert.equal(318, rows[1].profit)
        assert.equal(318, rows[1].estProfit)
      end)

      it("measures the cheapest lot: one lot clearing the minimum lists the whole row", function()
        vendor[2495] = 100
        local rows = D.Build(fold({ [2495] = "70,11,11,g;0x1 24x10" }), ctx()) -- 30c, then 10 at 6c
        assert.equal(1, #rows)
        assert.equal(90, rows[1].profit)
      end)

      it("holds a known non-commodity that is not gear to one lot too", function()
        vendor[6000], commodity[6000] = 100, false
        assert.equal(0, #D.Build(fold({ [6000] = "94,53,53,;0x53" }), ctx()))
      end)

      it("keeps the summed rule for a commodity, whose one buy takes many units", function()
        vendor[6000], commodity[6000] = 100, true
        local rows = D.Build(fold({ [6000] = "99,30,3,;0x30" }), ctx())  -- 30 units at 1c profit each
        assert.equal(1, #rows)
        assert.equal("commodities", rows[1].board)
      end)

      it("keeps the summed rule for an item the client has not named yet, rather than wait", function()
        vendor[6000] = 100
        local rows, _, unsure = D.Build(fold({ [6000] = "94,53,53,;0x53" }), ctx())
        assert.equal(1, #rows)
        assert.equal("commodities", rows[1].board)
        assert.same({ 6000 }, unsure)
      end)

      it("still lists a pinned item, as BoardAdmits does everywhere", function()
        vendor[2495] = 100
        assert.equal(1, #D.Build(fold({ [2495] = SWORDS }), ctx({ watchPins = { 2495 } })))
      end)
    end)

    it("skips garbage", function()
      vendor[2] = 999
      assert.equal(0, #D.Build(fold({ [2] = "junk" }), ctx()))
    end)

    it("keeps the hundred best per board", function()
      local items = {}
      for id = 1, 150 do
        items[id] = ("%d,1,1,;0x1"):format(100)
        vendor[id] = 100 + id              -- profit grows with id
        commodity[id] = true
      end
      local rows = D.Build(fold(items), ctx())
      assert.equal(100, #rows)
      assert.equal(150, rows[1].itemID)
    end)
  end)

  describe("Build, kind market", function()
    -- 30c x3, 40c x3, 100c x24, 110c x30, 120c x40: 100 units, p25 100c, p50 110c, five levels.
    -- AH value 100c: the cheapest tenth (10 units) reaches the 1s band; the six cheap units do not.
    local WOOL = "30,100,5,;0x3 10x3 60x24 10x30 10x40|70,80,5"

    -- ctx() with a 2c deposit per unit, the answer GC.ForeverValue.CommodityDepositUnit gives a commodity.
    local function marketCtx(over)
      local o = { depositFor = function() return 2 end }
      for k, v in pairs(over or {}) do o[k] = v end
      return ctx(o)
    end

    it("lists the levels at or under 70% of the AH value, net of the cut and the deposit", function()
      commodity[2592] = true
      local rows, missing = D.Build(fold({ [2592] = WOOL }), marketCtx())
      assert.same({ 2592 }, missing)          -- no vendor price: asked for, and market still judged
      local r = rows[1]
      assert.equal("market", r.forever)
      assert.equal(70, r.ceiling)             -- min(floor(100 * 0.70), 95 - 2 - 1)
      assert.equal(100, r.refUnit)            -- the AH value, not the half-way 1s10c
      assert.equal(6, r.qty)
      assert.equal(210, r.capTotal)
      assert.equal(342, r.profit)             -- under the 1s level left: 99c x6 = 594, -30 cut, -210, -12 deposit
      assert.equal(2, r.depositUnit)
      assert.is_true(math.abs(r.discount - 0.7) < 1e-9)
    end)

    -- The owner's beta board (WoW: Forever, 2026-09-27 11:23): Linen Cloth "Under market", 73% off,
    -- +2g29s, from 4,843 units at 66-82c while half the units listed asked 3s or more -- asks
    -- nobody pays. Measured against its AH value (82c) the cheapest lots are ordinary stock.
    it("makes no row of ordinary stock under an inflated half-way price (Linen: 66c, AH value 82c, p50 3s)", function()
      commodity[2589], vendor[2589] = true, 13
      -- 66c x300, 70c x100, 82c x200, 90c x300, 100c x500 of 4,843; p25 1s50c, p50 3s, 40 prices.
      local linen = "66,4843,900,;0x300 4x100 12x200 8x300 10x500|84,234,40"
      local e = GC.ForeverFold.Decode(linen)
      assert.equal(82, e.value); assert.equal(300, e.p50)
      assert.equal(0, #D.Build(fold({ [2589] = linen }), marketCtx({ depositFor = function() return 1 end })))
    end)

    it("still finds a few lots 30% under a thick AH-value band", function()
      commodity[4] = true
      -- 70c x30 under 600 units at 1s and 370 at 1s01c: AH value 1s, half-way 1s.
      local rows = D.Build(fold({ [4] = "70,1000,40,;0x30 30x600 1x370|30,30,3" }), marketCtx())
      assert.equal(1, #rows)
      local r = rows[1]
      assert.equal("market", r.forever)
      assert.equal(100, r.refUnit); assert.equal(70, r.ceiling)
      assert.equal(30, r.qty); assert.equal(661, r.profit)   -- 99c x30 = 2970, -149 cut, -2100, -60 deposit
    end)

    it("prefers a vendor deal when both hold", function()
      commodity[2592], vendor[2592] = true, 41
      local rows = D.Build(fold({ [2592] = WOOL }), marketCtx())
      assert.equal("vendor", rows[1].forever)
    end)

    it("falls through to a market row when the vendor row fails the minimum profit", function()
      -- vendor 31: only the 30c level qualifies (3 units * 1c profit = 3c), under the 20c minimum.
      commodity[2592], vendor[2592] = true, 31
      local rows = D.Build(fold({ [2592] = WOOL }), marketCtx())
      assert.equal(1, #rows)
      assert.equal("market", rows[1].forever)
    end)

    it("emits nothing when neither the vendor nor the market row clears the minimum", function()
      -- Same too-small vendor row as above, and the market candidate is refused too (no deposit).
      commodity[2592], vendor[2592] = true, 31
      local rows = D.Build(fold({ [2592] = WOOL }), marketCtx({ depositFor = function() return nil end }))
      assert.equal(0, #rows)
    end)

    it("needs 20 units, 3 price levels, a known commodity and a deposit", function()
      commodity[1], commodity[2], commodity[3], commodity[4] = true, true, nil, true
      local f = fold({
        [1] = "30,19,5,;0x1 60x4 10x5 10x5 10x4|60,70,5",   -- 19 units
        [2] = "30,100,2,;0x5 70x95|70,70,2",                  -- 2 levels
        [3] = WOOL,                                           -- commodity unknown
      })
      local rows, _, unsure = D.Build(f, marketCtx())
      assert.equal(0, #rows)
      assert.same({ 3 }, unsure)                              -- waiting on the client's answer
      assert.equal(0, #D.Build(fold({ [4] = WOOL }), marketCtx({ depositFor = function() return nil end })))
    end)

    -- The client answers "is this a commodity" by item key, and an uncached key is a server
    -- request (UI/SniperFrame.lua, getKeyInfo). A fold holds a couple of thousand items; the
    -- question goes only to an item with a row to place or lots under its market, never to
    -- gear (never a commodity), and once per item.
    it("asks whether an item is a commodity only where a row hangs on the answer", function()
      local asked = {}
      local function counting(id) asked[id] = (asked[id] or 0) + 1; return commodity[id] end
      commodity[1], commodity[2], commodity[3] = true, true, true
      vendor[4] = 500
      local rows, _, unsure = D.Build(fold({
        [1] = WOOL,                                           -- lots under its market: asked
        [2] = "100,100,3,;0x40 10x30 10x30|10,10,3",          -- nothing under 70c of 1s: not asked
        [3] = "30,100,5,g;0x3 10x3 60x24 10x30 10x40|70,80,5", -- gear: not asked
        [4] = "100,1,1,;0x1",                                 -- a vendor row to place: asked, unknown
      }), marketCtx({ isCommodity = counting }))
      assert.same({ [1] = 1, [4] = 1 }, asked)
      assert.equal(2, #rows)
      assert.same({ 4 }, unsure)
    end)

    it("makes no market row from a version-1 fold", function()
      commodity[2592] = true
      assert.equal(0, #D.Build(fold({ [2592] = "30,100,5,;0x3 10x3 60x24 10x30 10x40" }), marketCtx()))
    end)

    it("never sets a ceiling that loses money after the deposit", function()
      commodity[5] = true
      -- AH value 100c, deposit 30c: 95 - 30 - 1 = 64 caps the ceiling under 70.
      local rows = D.Build(fold({ [5] = WOOL }), marketCtx({ depositFor = function() return 30 end }))
      assert.equal(64, rows[1].ceiling)
    end)

    it("measures against the half-way price when a reference's is the lower of the two", function()
      commodity[2592] = true
      local rows = D.Build(fold({ [2592] = WOOL }), marketCtx({
        referenceFor = function() return { value = 100, p50 = 80, source = "crowd", scanners = 2 } end,
      }))
      assert.equal(80, rows[1].refUnit); assert.equal(56, rows[1].ceiling)
    end)

    -- AH value not a multiple of 20, so 0.70 x value and 0.95 x value are not already whole
    -- numbers: a math.floor dropped from either formula would leave the ceiling non-integer or a
    -- copper too high, and these three fail on it. Each book: 4 + 4 cheap units under 92 at the
    -- AH value, which the cheapest tenth (10 units) reaches.

    it("floors the 0.70 x value share (AH value 37, the deposit branch not binding)", function()
      -- floor(37 * 0.70) = 25 (37 * 0.7 = 25.9); net - deposit - 1 = 35 - 0 - 1 = 34 does not bind.
      commodity[6] = true
      local f = fold({ [6] = "10,100,3,;0x4 15x4 12x92|27,27,3" })  -- 10c x4, 25c x4, 37c x92
      local rows = D.Build(f, marketCtx({ depositFor = function() return 0 end }))
      assert.equal(25, rows[1].ceiling)
      assert.equal(8, rows[1].qty)           -- the 10c and 25c levels
      assert.equal(133, rows[1].profit)      -- under the 37c level left: 36c x8 = 288, -15 cut, -140
    end)

    it("floors the 0.95 x value - deposit - 1 share (AH value 101, that branch binding)", function()
      -- net = floor(101 * 0.95) = 95 (101 * 0.95 = 95.95); net - 32 - 1 = 62, under floor(101*0.7) = 70.
      commodity[7] = true
      local f = fold({ [7] = "20,100,3,;0x4 40x4 41x92|81,81,3" })  -- 20c x4, 60c x4, 101c x92
      local rows = D.Build(f, marketCtx({ depositFor = function() return 32 end }))
      assert.equal(62, rows[1].ceiling)
      assert.equal(8, rows[1].qty)           -- the 20c and 60c levels
      assert.equal(184, rows[1].profit)      -- (95-20-32)*4 + (95-60-32)*4
    end)

    it("floors the 0.70 x value share again at a larger scale (AH value 143)", function()
      -- floor(143 * 0.70) = 100 (143 * 0.7 = 100.1); net - deposit - 1 = 135 - 0 - 1 = 134 does not bind.
      commodity[8] = true
      local f = fold({ [8] = "50,100,3,;0x4 50x4 43x92|93,93,3" })  -- 50c x4, 100c x4, 143c x92
      local rows = D.Build(f, marketCtx({ depositFor = function() return 0 end }))
      assert.equal(100, rows[1].ceiling)
      assert.equal(8, rows[1].qty)           -- the 50c and 100c levels
      assert.equal(479, rows[1].profit)      -- under the 143c level left: 142c x8 = 1136, -57 cut, -600
    end)
  end)

  describe("MinimumProfit", function()
    it("is 20c unless the player changed Min profit per buy from its default", function()
      assert.equal(20, D.MinimumProfit({ minimumProfitCopper = 50000 }))
      assert.equal(20, D.MinimumProfit({}))
      assert.equal(20, D.MinimumProfit(nil))
      assert.equal(20, D.MinimumProfit({ minimumProfitCopper = -5 }))
      assert.equal(0, D.MinimumProfit({ minimumProfitCopper = 0 }))
      assert.equal(30000, D.MinimumProfit({ minimumProfitCopper = 30000 }))
      assert.equal(12, D.MinimumProfit({ minimumProfitCopper = 12.7 }))
    end)

    -- Task S: foreverMinimumProfitCopper is the settings panel's own Forever key now
    -- (UI/SettingsFrame.lua). Once it holds a number, it always wins -- retail's own
    -- minimumProfitCopper, changed or not, is never consulted again.
    it("prefers foreverMinimumProfitCopper once it holds a number, over the old retail carry-forward", function()
      assert.equal(500, D.MinimumProfit({ foreverMinimumProfitCopper = 500, minimumProfitCopper = 30000 }))
      assert.equal(500, D.MinimumProfit({ foreverMinimumProfitCopper = 500, minimumProfitCopper = 50000 }))
      assert.equal(0, D.MinimumProfit({ foreverMinimumProfitCopper = 0, minimumProfitCopper = 30000 }))
      assert.equal(12, D.MinimumProfit({ foreverMinimumProfitCopper = 12.7 }))
      -- Absent (nil) or garbage falls through to the old rule, unchanged.
      assert.equal(30000, D.MinimumProfit({ foreverMinimumProfitCopper = -5, minimumProfitCopper = 30000 }))
      assert.equal(20, D.MinimumProfit({ foreverMinimumProfitCopper = nil, minimumProfitCopper = 50000 }))
    end)
  end)

  describe("Rows, CeilingFor, Drop, Due", function()
    local saved, requests, clock

    before_each(function()
      requests, clock = {}, 1000
      saved = { at = 5000, items = { [2589] = "8,355,5,;0x5 1x10 3x40 1x100 2x200" } }
      GC.ForeverScan = { Enabled = function() return true end, Fold = function() return saved end }
      GC.db = { settings = { sniper = { minimumProfitCopper = 50000, watchPins = {} } }, commodityByItem = { [2589] = true } }
      GC.ForeverValue = { VendorUnit = function(id) return vendor[id] end, CommodityDepositUnit = function() return nil end }
      _G.C_Item = { RequestLoadItemDataByID = function(id) requests[#requests + 1] = id end }
    end)

    after_each(function() _G.C_Item = nil end)

    it("answers nothing on retail", function()
      GC.ForeverScan.Enabled = function() return false end
      vendor[2589] = 13
      assert.is_false(D.Refresh(clock))
      assert.same({}, D.Rows(clock))
      assert.is_nil(D.CeilingFor(2589))
    end)

    it("asks for missing item data once, then builds the row a later rebuild can price", function()
      assert.equal(0, #D.Rows(clock))
      assert.same({ 2589 }, requests)
      assert.is_false(D.Due(clock + 1))
      D.Rows(clock + 1)
      assert.equal(1, #requests)           -- cached: no second request, no rebuild
      vendor[2589] = 13
      assert.is_true(D.Due(clock + 5))
      -- A render does not rebuild for a vendor price (it may run in the auction house ticker);
      -- the board's own clock does, through Refresh.
      assert.equal(0, #D.Rows(clock + 5))
      assert.is_true(D.Refresh(clock + 5))
      assert.equal(1, #D.Rows(clock + 5))
      assert.equal(1, #requests)
      assert.is_false(D.Refresh(clock + 6)) -- nothing left to wait for
    end)

    it("stops rebuilding for an item whose vendor price never comes", function()
      D.Rows(clock)
      assert.is_true(D.Due(clock + 5))
      assert.is_true(D.Refresh(clock + 5))
      assert.is_true(D.Due(clock + 10))
      assert.is_false(D.Due(clock + 40))   -- asked 40 s ago: treated as no vendor price
    end)

    it("rebuilds when a new fold lands", function()
      vendor[2589] = 13
      assert.equal(1, #D.Rows(clock))
      saved = { at = 6000, items = {} }
      assert.is_true(D.Due(clock + 1))
      assert.equal(0, #D.Rows(clock + 1))
    end)

    -- Final review I2b: Core/ForeverScan.lua's browse top-up can add items to a fold while
    -- keeping its `at` pinned to the dump's own honest stamp -- `at` alone can no longer tell
    -- every changed fold apart, so a same-`at` fold with a different `itemCount` must still
    -- count as due.
    it("rebuilds on a same-`at` fold whose itemCount moved, even though `at` did not", function()
      vendor[2589] = 13
      saved.itemCount = 1
      assert.equal(1, #D.Rows(clock))
      assert.is_false(D.Due(clock + 1))
      saved = { at = saved.at, itemCount = 2, items = saved.items }
      assert.is_true(D.Due(clock + 1))
    end)

    -- Review, 2026-11-06: a merge that only overwrote entries keeps both `at` and `itemCount`;
    -- the fold's `rev` (Core/ForeverScan.lua, bumped on every write) still moves.
    it("rebuilds on a fold whose rev moved while `at` and itemCount did not", function()
      vendor[2589] = 13
      saved = { at = 5000, itemCount = 1, rev = 3, items = saved.items }
      assert.equal(8, D.Rows(clock)[1].unitPrice)
      assert.is_false(D.Due(clock + 1))
      saved = { at = 5000, itemCount = 1, rev = 4, items = { [2589] = "9,350,4,;0x10 3x40 1x100 2x200" } }
      assert.is_true(D.Due(clock + 1))
      assert.equal(9, D.Rows(clock + 1)[1].unitPrice)
    end)

    it("brings a dropped row back when a write under the same `at` gives its item a newer entry", function()
      vendor[2589] = 13
      saved = { at = 5000, itemCount = 1, rev = 1, items = saved.items }
      D.Rows(clock)
      D.Drop(2589)
      saved = { at = 5000, itemCount = 1, rev = 2, items = { [2589] = "9,350,4,;0x10 3x40 1x100 2x200" } }
      assert.equal(1, #D.Rows(clock + 1))
    end)

    -- A browse-only top-up keeps the saved entry of every item it shares with the fold: the lead
    -- the player just bought is still that entry, and must not come straight back.
    it("keeps a dropped row off through a write that kept its item's entry", function()
      vendor[2589], vendor[3000] = 13, 50
      saved = { at = 5000, itemCount = 1, rev = 1, items = saved.items }
      D.Rows(clock)
      D.Drop(2589)
      saved = { at = 5000, itemCount = 2, rev = 2,
        items = { [2589] = saved.items[2589], [3000] = "40,2,1,;0x2" } }
      local rows = D.Rows(clock + 1)
      assert.equal(1, #rows)
      assert.equal(3000, rows[1].itemID)
    end)

    -- The reviewer's case end to end (review, 2026-11-06): each scan's dump is read whole, and
    -- the player opens a Deals row while its browse pass runs, which aborts the pass.
    it("shows each fresh whole scan's prices when a Deals row aborted its browse pass", function()
      helper.loadModule("Core/Game.lua", GC)
      helper.loadModule("Core/ForeverGear.lua", GC)
      helper.loadModule("Core/ForeverScan.lua", GC)
      local store, timers, dumpRows, t = {}, {}, {}, 100000
      GC.ForeverScan.Enabled = function() return true end
      GC.ForeverScan.Fold = function() return store.fold end
      GC.ForeverValue.CommodityDepositUnit = function() return 0 end
      GC.db.commodityByItem[5471] = true
      local drv = {
        now = function() return t end,
        after = function(sec, fn) timers[#timers + 1] = { s = sec, fn = fn } end,
        replicate = function() return true end,
        numRows = function() return #dumpRows end,
        rowInfo = function(i) local r = dumpRows[i + 1]; if not r then return nil end; return r[1], r[2], r[3], r[4] end,
        isGear = function() return false end,
        startBrowse = function() return "started" end,
        store = function() return store end,
        passport = function() return { interface = 16001, region = 3, realm = "R", faction = "Horde" } end,
        notify = function() end,
      }
      local function scan(cheap, abort)
        store.requestedAt = nil
        dumpRows = {}
        for _ = 1, 10 do dumpRows[#dumpRows + 1] = { 5471, 1, cheap, true } end
        for i = 1, 200 do dumpRows[#dumpRows + 1] = { 5471, 1, 199 + (i % 5), true } end
        local s = GC.ForeverScan.New(drv)
        s:OnAuctionHouseShow()
        while #timers > 0 and (s:State() == "reading" or s:State() == "waiting") do table.remove(timers, 1).fn() end
        if abort then s:OnBrowsePassAbandoned({}) else s:OnBrowsePassDone({}) end
        timers = {}
      end
      scan(133, false)
      assert.equal(133, D.Rows(t)[1].unitPrice)
      t = t + 1200
      scan(120, true)                            -- 20 minutes on, 120c lots; a row opened
      assert.equal(120, D.Rows(t)[1].unitPrice)
      t = t + 1200
      scan(110, true)
      assert.equal(110, D.Rows(t)[1].unitPrice)
    end)

    it("names the ceiling a live Check is held to, and drops a row until the next fold", function()
      vendor[2589] = 13
      D.Rows(clock)
      assert.same({ ceilingUnit = 12, kind = "vendor", exitUnit = 13, depositUnit = nil, minimumProfit = 20 },
        D.CeilingFor(2589))
      D.Drop(2589)
      assert.equal(0, #D.Rows(clock + 1))
      assert.is_nil(D.CeilingFor(2589))
      saved = { at = 7000, items = saved.items }
      assert.equal(1, #D.Rows(clock + 2))
    end)

    -- The client, shaped as it is (AuctionHouseDocumentation, live and forever alike):
    -- GetItemCommodityStatus takes an ItemLocation, a bag slot, and refuses an item ID;
    -- GetItemKeyInfo answers an item key, and nothing until the client has cached it.
    local function clientAH(isCommodity, cached)
      return {
        GetItemCommodityStatus = function(location)
          if type(location) ~= "table" then
            error("bad argument #1 to 'GetItemCommodityStatus' (ItemLocation expected)")
          end
          return 0
        end,
        MakeItemKey = function(itemID)
          return { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
        end,
        GetItemKeyInfo = function(key)
          if not cached[key.itemID] then return nil end
          return { itemID = key.itemID, isCommodity = isCommodity[key.itemID] == true }
        end,
        CalculateCommodityDeposit = function() return 2 end,
      }
    end

    -- The real deposit path (Flips -> CalculateCommodityDeposit) under a client-shaped AH; a vendor
    -- pays 1c, so no item waits on a vendor price and no vendor row competes.
    local function withClient(isCommodity, cached)
      helper.loadModule("Core/Flips.lua", GC)
      helper.loadModule("Core/ForeverValue.lua", GC)
      GC.ForeverValue.VendorUnit = function() return 1 end
      _G.C_AuctionHouse = clientAH(isCommodity, cached)
      return _G.C_AuctionHouse
    end

    -- Final review I2 (plan 3c): the deposit of a commodity is the client's to quote from the
    -- item alone (C_AuctionHouse.CalculateCommodityDeposit), so an Under market row needs no
    -- stack of it ever seen in the bags by the Sell tab -- only the client's word that it is
    -- a commodity. Its word comes by item key, as the Sell tab asks for it (Services/Sell/
    -- Bags.lua): asked with an item ID, GetItemCommodityStatus refused every item the Sell tab
    -- had never seen, and WoW: Forever's board showed no Under market row at all (2026-11-06).
    it("builds a market row for a commodity the client names by its item key, never held in the bags", function()
      local ah = withClient({ [2592] = true }, { [2592] = true })
      local asked
      ah.CalculateCommodityDeposit = function(id, _, qty) asked = { id, qty }; return 2 end
      saved = { at = 5000, items = { [2592] = "30,100,5,;0x3 10x3 60x24 10x30 10x40|70,80,5" } }
      assert.is_nil(GC.db.commodityByItem[2592])
      D.Rows(clock)
      assert.same({ 2592, 1 }, asked)
      assert.same({ ceilingUnit = 70, kind = "market", exitUnit = 100, depositUnit = 2, minimumProfit = 20 },
        D.CeilingFor(2592))
      assert.is_true(GC.db.commodityByItem[2592])   -- remembered, as the Sell tab remembers it
      -- No deposit quoted, no row: still fail-closed.
      _G.C_AuctionHouse.CalculateCommodityDeposit = function() return nil end
      saved = { at = 6000, items = saved.items }
      D.Rows(clock + 1)
      assert.is_nil(D.CeilingFor(2592))
      _G.C_AuctionHouse = nil
    end)

    it("waits for an item key the client has not cached, then builds the row", function()
      local cached = {}
      withClient({ [2592] = true }, cached)
      saved = { at = 5000, items = { [2592] = "30,100,5,;0x3 10x3 60x24 10x30 10x40|70,80,5" } }
      assert.equal(0, #D.Rows(clock))
      assert.is_nil(GC.db.commodityByItem[2592])
      assert.is_false(D.Due(clock + 1))
      cached[2592] = true                           -- ITEM_KEY_ITEM_INFO_RECEIVED
      assert.is_true(D.Refresh(clock + 5))
      assert.equal("market", D.CeilingFor(2592).kind)
      _G.C_AuctionHouse = nil
    end)

    it("stops waiting for an item key that never comes", function()
      withClient({}, {})
      saved = { at = 5000, items = { [2592] = "30,100,5,;0x3 10x3 60x24 10x30 10x40|70,80,5" } }
      D.Rows(clock)
      assert.is_true(D.Refresh(clock + 5))
      assert.is_false(D.Due(clock + 40))
      _G.C_AuctionHouse = nil
    end)

    -- Review, 2026-11-06: GetItemKeyInfo sends the server its question only at the auction
    -- house. A client whose answer comes only for a key asked there, a few ms later.
    local function askedOnlyAtTheAH(isCommodity)
      local ah = withClient(isCommodity, {})
      local state = { open = false, cached = {}, pending = {} }
      ah.GetItemKeyInfo = function(key)
        if state.cached[key.itemID] then return { itemID = key.itemID, isCommodity = isCommodity[key.itemID] == true } end
        if state.open then state.pending[key.itemID] = true end
        return nil
      end
      function state.answer() for id in pairs(state.pending) do state.cached[id] = true end end
      return state
    end

    it("asks again at the auction house for an item key a build away from it left unsure", function()
      local client = askedOnlyAtTheAH({ [2592] = true })
      saved = { at = 5000, items = { [2592] = "30,100,5,;0x3 10x3 60x24 10x30 10x40|70,80,5" } }
      assert.equal(0, #D.Rows(clock))              -- the window opened from the minimap
      assert.is_false(D.Due(clock + 40))           -- its wait ran out; nobody was asked
      client.open = true                           -- 20 minutes later, the auction house
      D.OnAuctionHouseShow()
      assert.is_true(D.Due(clock + 1200))
      assert.is_true(D.Refresh(clock + 1200))      -- the board clock asks, now for real
      assert.is_nil(D.CeilingFor(2592))
      client.answer()                              -- ITEM_KEY_ITEM_INFO_RECEIVED
      assert.is_true(D.Refresh(clock + 1205))      -- inside the new wait
      assert.equal("market", D.CeilingFor(2592).kind)
      _G.C_AuctionHouse = nil
    end)

    it("gives a new fold's unsure items a wait of their own, whatever an earlier fold asked", function()
      local client = askedOnlyAtTheAH({ [2592] = true })
      local items = { [2592] = "30,100,5,;0x3 10x3 60x24 10x30 10x40|70,80,5" }
      saved = { at = 5000, items = items }
      D.Rows(clock)                                -- asked away from the auction house
      client.open = true
      saved = { at = 6200, items = items }         -- the scan on opening lands a new fold
      assert.equal(0, #D.Rows(clock + 1200))       -- asked; the answer is not in yet
      client.answer()
      assert.is_true(D.Due(clock + 1205))
      assert.is_true(D.Refresh(clock + 1205))
      assert.equal("market", D.CeilingFor(2592).kind)
      _G.C_AuctionHouse = nil
    end)

    it("leaves the board alone at the auction house when its last build left nothing unsure", function()
      vendor[2589] = 13
      assert.equal(1, #D.Rows(clock))
      D.OnAuctionHouseShow()
      assert.is_false(D.Due(clock + 60))
      assert.is_false(D.Refresh(clock + 60))
    end)

    it("does nothing at the auction house on retail", function()
      withClient({ [2592] = true }, {})
      saved = { at = 5000, items = { [2592] = "30,100,5,;0x3 10x3 60x24 10x30 10x40|70,80,5" } }
      D.Rows(clock)
      GC.ForeverScan.Enabled = function() return false end
      D.OnAuctionHouseShow()
      assert.is_false(D.Refresh(clock + 60))
      _G.C_AuctionHouse = nil
    end)

    it("takes a known non-commodity from the Sell tab's memory without asking", function()
      withClient({}, {}).GetItemKeyInfo = function() error("asked") end
      GC.db.commodityByItem[2592] = false
      saved = { at = 5000, items = { [2592] = "30,100,5,;0x3 10x3 60x24 10x30 10x40|70,80,5" } }
      assert.equal(0, #D.Rows(clock))
      assert.is_false(D.Due(clock + 5))
      _G.C_AuctionHouse = nil
    end)

    it("hands out a market ceiling with its deposit", function()
      saved = { at = 5000, items = { [2592] = "30,100,5,;0x3 10x3 60x24 10x30 10x40|70,80,5" } }
      GC.db.commodityByItem[2592] = true
      GC.ForeverValue.CommodityDepositUnit = function() return 2 end
      D.Rows(clock)
      assert.same({ ceilingUnit = 70, kind = "market", exitUnit = 100, depositUnit = 2, minimumProfit = 20 },
        D.CeilingFor(2592))
    end)
  end)

  describe("BuyLimits", function()
    local function config(share)
      return { maxCapitalShare = share, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 50000, minimumRoi = 0.10 }
    end

    before_each(function()
      helper.loadModule("Core/SniperDecision.lua", GC)
    end)

    it("gives a vendor row half the wallet when the player kept the shipped 5% share", function()
      local limits = D.BuyLimits(config(0.05), 10000, "vendor")
      assert.same({ maxQuantity = 200, budget = 5000, share = 0.50 }, limits)
    end)

    -- Review, 2026-11-06: only the shipped 5% itself used to qualify, so raising the share to
    -- 10% gave a vendor row 10% of the wallet where the default gave it half.
    it("gives a vendor row half the wallet when the player raised the share", function()
      assert.same({ maxQuantity = 200, budget = 5000, share = 0.50 }, D.BuyLimits(config(0.10), 10000, "vendor"))
      assert.same({ maxQuantity = 200, budget = 5000, share = 0.50 }, D.BuyLimits(config(0.20), 10000, "vendor"))
      -- Above the 20% the settings allow, the share is clamped first, as everywhere else.
      assert.same({ maxQuantity = 200, budget = 5000, share = 0.50 }, D.BuyLimits(config(0.90), 10000, "vendor"))
    end)

    it("leaves a vendor row the share a player lowered", function()
      assert.same({ maxQuantity = 200, budget = 300, share = 0.03 }, D.BuyLimits(config(0.03), 10000, "vendor"))
    end)

    -- Owner, WoW: Forever 2026-11-06: at 5% nearly every Under market row read "needs 2g" -- a
    -- new character's whole wallet buys nothing. A quarter while the shipped share stands; a
    -- resale is a bet, so less than a vendor row's half.
    it("gives a market row a quarter of the wallet when the player kept the shipped 5% share", function()
      local limits = D.BuyLimits(config(0.05), 10000, "market")
      assert.same({ maxQuantity = 200, budget = 2500, share = 0.25 }, limits)
    end)

    it("gives a market row a quarter of the wallet when the player raised the share", function()
      assert.same({ maxQuantity = 200, budget = 2500, share = 0.25 }, D.BuyLimits(config(0.10), 10000, "market"))
      assert.same({ maxQuantity = 200, budget = 2500, share = 0.25 }, D.BuyLimits(config(0.20), 10000, "market"))
    end)

    it("leaves a market row the share a player lowered", function()
      assert.same({ maxQuantity = 200, budget = 300, share = 0.03 }, D.BuyLimits(config(0.03), 10000, "market"))
    end)

    it("leaves a row of no Forever kind the player's own share, as SniperDecision.BuyLimits gives it", function()
      assert.same({ maxQuantity = 200, budget = 1000, share = 0.10 }, D.BuyLimits(config(0.10), 10000, nil))
    end)

    it("answers nothing when the wallet is bad, exactly like SniperDecision.BuyLimits", function()
      assert.is_nil(D.BuyLimits(config(0.05), 0 / 0, "vendor"))
      assert.is_nil(D.BuyLimits(nil, 10000, "vendor"))
    end)
  end)
end)
