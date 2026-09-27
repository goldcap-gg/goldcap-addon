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
    -- 30c x5, 40c x5, 90c x20, 100c x30, 110c x40: 100 units, p25 90c, p50 100c, five levels.
    local WOOL = "30,100,5,;0x5 10x5 50x20 10x30 10x40|60,70,5"

    -- ctx() with a 2c deposit per unit, the answer GC.ForeverValue.CommodityDepositUnit gives a commodity.
    local function marketCtx(over)
      local o = { depositFor = function() return 2 end }
      for k, v in pairs(over or {}) do o[k] = v end
      return ctx(o)
    end

    it("lists the levels at or under 70% of the half-way price, net of the cut and the deposit", function()
      commodity[2592] = true
      local rows, missing = D.Build(fold({ [2592] = WOOL }), marketCtx())
      assert.same({ 2592 }, missing)          -- no vendor price: asked for, and market still judged
      local r = rows[1]
      assert.equal("market", r.forever)
      assert.equal(70, r.ceiling)             -- min(70, 95 - 2 - 1)
      assert.equal(100, r.refUnit)
      assert.equal(10, r.qty)
      assert.equal(350, r.capTotal)
      assert.equal(580, r.profit)             -- (95-30-2)*5 + (95-40-2)*5
      assert.equal(2, r.depositUnit)
      assert.is_true(math.abs(r.discount - 0.7) < 1e-9)
    end)

    it("prefers a vendor deal when both hold", function()
      commodity[2592], vendor[2592] = true, 35
      local rows = D.Build(fold({ [2592] = WOOL }), marketCtx())
      assert.equal("vendor", rows[1].forever)
    end)

    it("falls through to a market row when the vendor row fails the minimum profit", function()
      -- vendor 31: only the 30c level qualifies (5 units * 1c profit = 5c), under the 20c minimum.
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
        [1] = "30,19,5,;0x5 10x5 50x5 10x2 10x2|60,70,5",   -- 19 units
        [2] = "30,100,2,;0x50 70x50|0,0,2",                   -- 2 levels
        [3] = WOOL,                                           -- commodity unknown
      })
      assert.equal(0, #D.Build(f, marketCtx()))
      assert.equal(0, #D.Build(fold({ [4] = WOOL }), marketCtx({ depositFor = function() return nil end })))
    end)

    it("makes no market row from a version-1 fold", function()
      commodity[2592] = true
      assert.equal(0, #D.Build(fold({ [2592] = "30,100,5,;0x5 10x5 50x20 10x30 10x40" }), marketCtx()))
    end)

    it("never sets a ceiling that loses money after the deposit", function()
      commodity[5] = true
      -- p50 100c, deposit 30c: 95 - 30 - 1 = 64 caps the ceiling under 70.
      local rows = D.Build(fold({ [5] = WOOL }), marketCtx({ depositFor = function() return 30 end }))
      assert.equal(64, rows[1].ceiling)
    end)

    -- p50 not a multiple of 20, so 0.70 x p50 and 0.95 x p50 are not already whole numbers:
    -- a math.floor dropped from either formula would leave the ceiling non-integer or a copper
    -- too high, and these three fail on it.

    it("floors the 0.70 x p50 share (p50 37, the deposit branch not binding)", function()
      -- floor(37 * 0.70) = 25 (37 * 0.7 = 25.9); net - deposit - 1 = 35 - 0 - 1 = 34 does not bind.
      commodity[6] = true
      local f = fold({ [6] = "10,25,3,;0x10 15x10 65x5|5,27,3" })   -- min 10, p50 37, 3 levels, 25 units
      local rows = D.Build(f, marketCtx({ depositFor = function() return 0 end }))
      assert.equal(25, rows[1].ceiling)
      assert.equal(20, rows[1].qty)          -- the 10c and 25c levels (10 + 10 units)
      assert.equal(350, rows[1].profit)      -- (35-10)*10 + (35-25)*10
    end)

    it("floors the 0.95 x p50 - deposit - 1 share (p50 101, that branch binding)", function()
      -- net = floor(101 * 0.95) = 95 (101 * 0.95 = 95.95); net - 32 - 1 = 62, under floor(101*0.7) = 70.
      commodity[7] = true
      local f = fold({ [7] = "20,30,3,;0x10 40x15 50x5|40,81,3" })  -- min 20, p50 101, 3 levels, 30 units
      local rows = D.Build(f, marketCtx({ depositFor = function() return 32 end }))
      assert.equal(62, rows[1].ceiling)
      assert.equal(25, rows[1].qty)          -- the 20c and 60c levels (10 + 15 units)
      assert.equal(475, rows[1].profit)      -- (95-20-32)*10 + (95-60-32)*15
    end)

    it("floors the 0.70 x p50 share again at a larger scale (p50 143)", function()
      -- floor(143 * 0.70) = 100 (143 * 0.7 = 100.1); net - deposit - 1 = 135 - 0 - 1 = 134 does not bind.
      commodity[8] = true
      local f = fold({ [8] = "50,25,3,;0x10 50x10 60x5|50,93,3" })  -- min 50, p50 143, 3 levels, 25 units
      local rows = D.Build(f, marketCtx({ depositFor = function() return 0 end }))
      assert.equal(100, rows[1].ceiling)
      assert.equal(20, rows[1].qty)          -- the 50c and 100c levels (10 + 10 units)
      assert.equal(1200, rows[1].profit)     -- (135-50)*10 + (135-100)*10
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
      saved = { at = 5000, items = { [2592] = "30,100,5,;0x5 10x5 50x20 10x30 10x40|60,70,5" } }
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
      saved = { at = 5000, items = { [2592] = "30,100,5,;0x5 10x5 50x20 10x30 10x40|60,70,5" } }
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
