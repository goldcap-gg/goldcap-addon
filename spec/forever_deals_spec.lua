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

    it("a 44% discount is a market row: 165 at 10c, measured at 18c (half-way under its AH value), +7c each", function()
      vendor[765], commodity[765] = 1, true               -- Silverleaf; a vendor pays under the AH
      local rows = D.Build(fold({ [765] = "10,4062,200,;0x165 5x100 8x3797|0,8,15" }),
        ctx({ depositFor = function() return 0 end }))
      assert.equal(1, #rows)
      local r = rows[1]
      assert.equal("market", r.forever)
      assert.equal(165, r.qty); assert.equal(1650, r.capTotal); assert.equal(1155, r.profit)
      assert.equal(44, math.floor(r.discount * 100 + 0.5))
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

    it("skips browse-only entries (no ladder) and garbage", function()
      vendor[1], vendor[2] = 999, 999
      assert.equal(0, #D.Build(fold({ [1] = "500,2,,b;", [2] = "junk" }), ctx()))
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
      assert.equal(348, r.profit)             -- (95-30-2)*3 + (95-40-2)*3
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
      assert.equal(30, r.qty); assert.equal(690, r.profit)   -- (95-70-2)*30
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
      assert.equal(0, #D.Build(f, marketCtx()))
      assert.equal(0, #D.Build(fold({ [4] = WOOL }), marketCtx({ depositFor = function() return nil end })))
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
      assert.equal(140, rows[1].profit)      -- (35-10)*4 + (35-25)*4
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
      assert.equal(480, rows[1].profit)      -- (135-50)*4 + (135-100)*4
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

    -- Final review I2 (plan 3c): the deposit of a commodity is the client's to quote from the
    -- item alone (C_AuctionHouse.CalculateCommodityDeposit), so an Under market row needs no
    -- stack of it ever seen in the bags by the Sell tab -- only the client's word that it is
    -- a commodity.
    it("builds a market row for a commodity the client names, never held in the bags", function()
      helper.loadModule("Core/Flips.lua", GC)
      helper.loadModule("Core/ForeverValue.lua", GC)
      _G.Enum = { ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 } }
      local asked
      _G.C_AuctionHouse = {
        GetItemCommodityStatus = function(id) return id == 2592 and 2 or 1 end,
        CalculateCommodityDeposit = function(id, _, qty) asked = { id, qty }; return 2 end,
      }
      saved = { at = 5000, items = { [2592] = "30,100,5,;0x3 10x3 60x24 10x30 10x40|70,80,5" } }
      assert.is_nil(GC.db.commodityByItem[2592])
      D.Rows(clock)
      assert.same({ 2592, 1 }, asked)
      assert.same({ ceilingUnit = 70, kind = "market", exitUnit = 100, depositUnit = 2, minimumProfit = 20 },
        D.CeilingFor(2592))
      -- No deposit quoted, no row: still fail-closed.
      _G.C_AuctionHouse.CalculateCommodityDeposit = function() return nil end
      saved = { at = 6000, items = saved.items }
      D.Rows(clock + 1)
      assert.is_nil(D.CeilingFor(2592))
      _G.Enum, _G.C_AuctionHouse = nil, nil
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
      assert.same({ maxQuantity = 200, budget = 5000 }, limits)
    end)

    it("leaves a vendor row's budget alone once the player changed the share", function()
      local limits = D.BuyLimits(config(0.10), 10000, "vendor")
      assert.same({ maxQuantity = 200, budget = 1000 }, limits)
    end)

    it("never widens a market row's share", function()
      local limits = D.BuyLimits(config(0.05), 10000, "market")
      assert.same({ maxQuantity = 200, budget = 500 }, limits)
    end)

    it("answers nothing when the wallet is bad, exactly like SniperDecision.BuyLimits", function()
      assert.is_nil(D.BuyLimits(config(0.05), 0 / 0, "vendor"))
      assert.is_nil(D.BuyLimits(nil, 10000, "vendor"))
    end)
  end)
end)
