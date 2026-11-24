local helper = require("spec.spec_helper")

-- The units a DEALS row offers to buy count what the account already holds (Core/Holdings.lua):
-- limit = max(0, cap - held), held = this character's bags, banks and mail, the other characters'
-- mail and the player's own lots still listed. Caps keep their own limit.
describe("the buy limit counts what is held", function()
  local GC, counts

  before_each(function()
    counts = {}
    _G.C_Item = { GetItemCount = function(itemID) return counts[itemID] or 0 end }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    helper.loadModule("Core/MailStock.lua", GC)
    helper.loadModule("Services/CraftClient.lua", GC)
    helper.loadModule("Core/Holdings.lua", GC)
    GC.Ledger = { Context = function() return { char = "Me-Realm", region = "eu" } end }
    GC.db = {}
  end)

  after_each(function() _G.C_Item = nil end)

  describe("GC.Holdings.Limit", function()
    -- { cap, held, limit }
    local CASES = {
      { 10, 0, 10 }, { 10, nil, 10 }, { 10, 3, 7 }, { 10, 10, 0 }, { 10, 15, 0 },
      { 10, 2.7, 8 }, { 10, -4, 10 }, { 200, 150, 50 },
      -- no sales figure to plan by: left as it is, never read as full
      { 0, 5, 0 }, { nil, 5, nil },
    }
    for _, case in ipairs(CASES) do
      it(("cap %s, held %s: %s"):format(tostring(case[1]), tostring(case[2]), tostring(case[3])), function()
        assert.equal(case[3], GC.Holdings.Limit(case[1], case[2]))
      end)
    end
  end)

  describe("what is held, from each source", function()
    local ITEM = 777
    local function mail(chars)
      GC.db.mailStock = { v = 1, chars = chars }
    end
    local function lots(read, listed)
      GC.SellState = { ownedRead = read, ownedLots = listed, soldLots = {} }
    end

    -- { name, setup, held }
    local CASES = {
      { "nothing anywhere", function() end, 0 },
      { "the bags and banks", function() counts[ITEM] = 4 end, 4 },
      { "this character's mail", function() mail({ ["Me-Realm"] = { items = { [ITEM] = 3 } } }) end, 3 },
      { "a purchase on its way by mail", function()
        mail({ ["Me-Realm"] = { items = {}, bought = { [ITEM] = { n = 2, at = 1, first = 1 } } } })
      end, 2 },
      { "another character's mail, in view and out of it", function()
        mail({ ["Alt-Realm"] = { items = { [ITEM] = 5 }, bought = {}, away = { seen = { [ITEM .. ":4:100"] = 2 } } } })
      end, 13 },
      { "own lots still listed", function()
        lots(true, { { itemID = ITEM, quantity = 6 }, { itemID = ITEM, quantity = 1 }, { itemID = 1, quantity = 9 } })
      end, 7 },
      { "own lots before the SELL tab has read them", function()
        lots(false, { { itemID = ITEM, quantity = 6 } })
      end, 0 },
      { "everything at once, each counted once", function()
        counts[ITEM] = 4
        mail({ ["Me-Realm"] = { items = { [ITEM] = 3 } }, ["Alt-Realm"] = { items = { [ITEM] = 5 } } })
        lots(true, { { itemID = ITEM, quantity = 6 } })
      end, 18 },
    }
    for _, case in ipairs(CASES) do
      it(case[1], function()
        case[2]()
        assert.equal(case[3], GC.Holdings.Of(ITEM))
      end)
    end

    it("counts a sold lot nowhere: the SELL tab keeps it apart from the listed ones", function()
      helper.loadModule("Core/Acquisitions.lua", GC)
      helper.loadModule("Core/SellPositions.lua", GC)
      local listed, sold = GC.SellPositions.NormalizeOwnedLots({
        { auctionID = 1, itemKey = { itemID = ITEM }, quantity = 6, buyoutAmount = 600, status = 0 },
        { auctionID = 2, itemKey = { itemID = ITEM }, quantity = 4, buyoutAmount = 400,
          status = GC.SellPositions.AUCTION_SOLD },
      }, 1000)
      assert.equal(1, #sold)
      GC.SellState = { ownedRead = true, ownedLots = listed, soldLots = sold }
      assert.equal(6, GC.Holdings.Of(ITEM))
    end)
  end)

  describe("GC.SniperDecision.DemandCap and Evaluate", function()
    local config = { maxDailyDemandShare = 0.05, maxQuantity = 200 }
    local market = { soldPerDay = 5000, currentQty = 5000, madBps = 250 }

    it("takes what is held off the cap, and nothing without it", function()
      assert.equal(106, GC.SniperDecision.DemandCap(market, config, 0))
      assert.equal(100, GC.SniperDecision.DemandCap(market, config, 0, 6))
      assert.equal(0, GC.SniperDecision.DemandCap(market, config, 0, 500))
      assert.equal(0, GC.SniperDecision.DemandCap({ soldPerDay = 1 }, config, 0, 3))
    end)

    local function input(held)
      return {
        now = 100000,
        market = { kind = "region_commodity", source = "import", sourceAt = 92800,
          marketValue = 3000000, stressUnit = 3000000, soldPerDay = 100000,
          sellThroughBps = 7000, liquidityConfidence = 70, currentQty = 0,
          listings = 3, observations = 12, madBps = 0, trend24hPct = -9 },
        live = { itemID = 42, levels = { { unitPrice = 1000000, quantity = 200 }, { unitPrice = 3000001, quantity = 1 } } },
        walletCopper = 10000000000,
        depositForQuantity = function() return 0 end,
        config = { maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
          minimumProfitCopper = 1000000, minimumRoi = 0.10 },
        held = held,
      }
    end

    it("buys fewer once some are held, and refuses as demand_limit once they fill the cap", function()
      assert.equal(200, GC.SniperDecision.Evaluate(input(nil)).quantity)
      assert.equal(50, GC.SniperDecision.Evaluate(input(150)).quantity)
      local full = GC.SniperDecision.Evaluate(input(200))
      assert.is_false(full.buyable)
      assert.equal("demand_limit", full.reasons[1])
    end)
  end)

  describe("discovery (GC.FullScan.RowsFromBrowse)", function()
    local cfg = { maxDailyDemandShare = 0.05, maxQuantity = 200 }
    local values = {
      [10] = { kind = "commodity", mv = 1000, sold = 5000, currentQty = 5000, madBps = 250 },
      [20] = { kind = "realm_item", mv = 1000, ref = 900 },
    }
    local function getValue(itemID) return values[itemID] end
    local function browse(itemID) return { itemKey = { itemID = itemID }, minPrice = 500, totalQuantity = 5000 } end

    it("offers what is left of the cap and says what is held", function()
      local plain = GC.FullScan.RowsFromBrowse({ browse(10) }, getValue, cfg)[1]
      assert.same({ 106 }, { plain.count })
      assert.is_nil(plain.held)
      counts[10] = 6
      local row = GC.FullScan.RowsFromBrowse({ browse(10) }, getValue, cfg)[1]
      assert.same({ 100, 6 }, { row.count, row.held })
    end)

    it("is no row once the holdings fill the cap", function()
      counts[10] = 106
      assert.same({}, GC.FullScan.RowsFromBrowse({ browse(10) }, getValue, cfg))
    end)

    it("leaves an item with no sales figure at its one unit, whatever is held", function()
      counts[20] = 50
      local row = GC.FullScan.RowsFromBrowse({ browse(20) }, getValue, cfg)[1]
      assert.same({ 1 }, { row.count })
      assert.is_nil(row.held)
    end)
  end)

  describe("caps", function()
    it("keep their own limit, whatever is held", function()
      counts[10] = 1000
      local settings = { maxCapitalShare = 0.05, maxDailyDemandShare = 0.05, maxQuantity = 20,
        minimumProfitCopper = 1, minimumRoi = 0.10 }
      local decision = GC.Caps.DecideCommodity({ c = 100 }, { { unitPrice = 90, quantity = 50 } },
        GC.SniperDecision.BuyLimits(settings, 10000000))
      assert.equal(20, decision.quantity)
    end)
  end)

  describe("WoW: Forever's Under market rows", function()
    local vendor, commodity = {}, {}
    local function sold(perDay)
      return function() return { units = perDay * 7, sales = 300, median = 100, p25 = 95, perDay = perDay, hours = 168 } end
    end
    local function build(held)
      helper.loadModule("Core/ForeverFold.lua", GC)
      helper.loadModule("Core/ForeverItemMarket.lua", GC)
      helper.loadModule("Core/ForeverDeals.lua", GC)
      commodity[1] = true
      return GC.ForeverDeals.Build({ at = 5000, items = { [1] = "50,200,10,;0x30 50x170|50,50,2" } }, {
        vendorFor = function(id) return vendor[id] end,
        isCommodity = function(id) return commodity[id] end,
        depositFor = function() return 0 end,
        minimumProfit = 20, watchPins = {},
        salesFor = sold(200),
        heldOf = held and function() return held end or nil,
      })
    end

    -- 200 sell a day: a quarter day of them (SOLD_DAYS) is 50. The row's buy takes whole price
    -- levels, the cheap one 30 units: a limit under that leaves no row, as the sales alone would.
    -- { held, units the row takes (nil: no row), its limit, held on the row }
    local CASES = { { nil, 30, 50, nil }, { 0, 30, 50, nil }, { 10, 30, 40, 10 }, { 20, 30, 30, 20 },
      { 21, nil }, { 50, nil }, { 80, nil } }
    for _, case in ipairs(CASES) do
      it(("holding %s: %s"):format(tostring(case[1]), case[2] and (case[2] .. " units") or "no row"), function()
        local rows = build(case[1])
        if not case[2] then
          assert.equal(0, #rows)
        else
          assert.equal(1, #rows)
          assert.same({ case[2], case[3], 50, case[4] }, { rows[1].qty, rows[1].maxUnits, rows[1].soldMax, rows[1].held })
        end
      end)
    end
  end)
end)
