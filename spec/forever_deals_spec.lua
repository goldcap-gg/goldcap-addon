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
      GC.ForeverValue = { VendorUnit = function(id) return vendor[id] end, DepositUnit = function() return nil end }
      _G.C_Item = { RequestLoadItemDataByID = function(id) requests[#requests + 1] = id end }
    end)

    after_each(function() _G.C_Item = nil end)

    it("answers nothing on retail", function()
      GC.ForeverScan.Enabled = function() return false end
      vendor[2589] = 13
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
      assert.equal(1, #D.Rows(clock + 5))
      assert.equal(1, #requests)
    end)

    it("stops rebuilding for an item whose vendor price never comes", function()
      D.Rows(clock)
      assert.is_true(D.Due(clock + 5))
      D.Rows(clock + 5)
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
