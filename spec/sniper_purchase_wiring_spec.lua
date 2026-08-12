local helper = require("spec.spec_helper")

-- This protects the UI boundary around the pure SniperDecision engine. The static checks make
-- the protected WoW calls auditable; the fixture below also runs the real price-update handler
-- with a failed 4% requote, so the safety branch is not merely a source-text convention.
describe("Sniper purchase wiring", function()
  local function source()
    local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = f:read("*a")
    f:close()
    return text
  end

  local function section(text, first, last)
    local from = assert(text:find(first, 1, true), first)
    local to = assert(text:find(last, from + #first, true), last)
    return text:sub(from, to - 1)
  end

  it("keeps purchase calls in the hardware-click handler and starts exact decision quantity", function()
    local text = source()
    local click = section(text, "local function onDialogPrimaryClick()", "-- ---------------------------------------------------------------------------\n-- Sniper v3 dialog layout constants")

    assert.is_truthy(click:find("C_AuctionHouse.StartCommoditiesPurchase(deal.itemID, decision.quantity)", 1, true))
    assert.is_truthy(click:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_truthy(click:find("C_AuctionHouse.PlaceBid", 1, true))
    local nonCommodityGate = assert(click:find("if not deal.isCommodity", 1, true))
    local placeBid = assert(click:find("C_AuctionHouse.PlaceBid", 1, true))
    assert.is_true(nonCommodityGate < placeBid)
    assert.is_truthy(click:find("quoteSnapshot", 1, true))
    assert.is_truthy(click:find("quoteSnapshot.decision.status ~= \"SAFE\"", 1, true))
    assert.is_truthy(click:find("commodityDraining", 1, true))

    local before = text:sub(1, assert(text:find("local function onDialogPrimaryClick()", 1, true)) - 1)
    local after = text:sub(assert(text:find("-- Sniper v3 dialog layout constants", 1, true)))
    assert.is_nil(before:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_nil(before:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_nil(before:find("C_AuctionHouse.PlaceBid", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_nil(after:find("C_AuctionHouse.PlaceBid", 1, true))
  end)

  it("requires a newly evaluated safe quote, cancels a broken requote, and records one purchase fact", function()
    local text = source()
    local quote = section(text, "function GC.Sniper.OnCommodityPriceUpdated", "function GC.Sniper.OnCommodityPriceUnavailable")
    local resolve = section(text, "resolvePurchase = function", "-- Cancel button / Esc")

    assert.is_truthy(quote:find("evaluateLive", 1, true))
    assert.is_truthy(quote:find("C_AuctionHouse.CancelCommoditiesPurchase()", 1, true))
    assert.is_truthy(quote:find("requote_broke_safety", 1, true))
    assert.is_truthy(quote:find("drainCommodityPurchase(row)", 1, true))
    assert.is_truthy(resolve:find("purchase.total", 1, true))
    assert.is_truthy(resolve:find("GC.Data.RecordFlip(deal, purchase", 1, true))
    assert.is_truthy(resolve:find("GC.Ledger.RecordSniperBuy(deal, purchase", 1, true))
  end)

  it("cancels a sub-five-percent failed requote before any confirm can run", function()
    -- The integration fixture intentionally supplies a final server total that is only 4%
    -- higher, but whose stress math fails. This must cancel on economics, not rely on the old
    -- 5% visual-warning threshold; no event is permitted to confirm a protected purchase.
    local cancelCalls, confirmCalls = 0, 0
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end,
      ConfirmCommoditiesPurchase = function() confirmCalls = confirmCalls + 1 end,
    }
    _G.C_Timer = { After = function() end }
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.GetTime = function() return 0 end
    _G.SOUNDKIT = { RAID_WARNING = 1 }
    _G.PlaySound = function() end

    local GC = {
      Theme = { ROW_H = 20, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function()
        return {
          mv = 3000000, kind = "region_commodity", source = "import", sourceAt = 92800,
          stressUnit = 2105264, sold = 100000, sellThroughBps = 7000,
          liquidityConfidence = 70, currentQty = 0, listings = 3, observations = 12,
          madBps = 0, trend = -9,
        }
      end },
      db = { settings = { sniper = {
        maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
        minimumProfitCopper = 1000000, minimumRoi = 0.10,
      } } },
    }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    local row = {
      purchaseStage = "buying", purchaseToken = 7,
      purchaseDeal = { itemID = 42, isCommodity = true },
      decisionSnapshot = { version = 1, status = "SAFE", buyable = true, quantity = 1 },
    }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", nil)

    -- The fresh book still begins at 100g; a 104g server quote makes the 100g stress-profit
    -- boundary fail. The real handler must cancel before any button can be a Confirm path.
    _G.C_AuctionHouse.GetNumCommoditySearchResults = function() return 2 end
    _G.C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index)
      if index == 1 then return { unitPrice = 1000000, quantity = 1 } end
      return { unitPrice = 2105265, quantity = 1 }
    end
    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000)

    assert.equal(1, cancelCalls)
    assert.equal(0, confirmCalls)
    assert.equal("check", row.purchaseStage)
    assert.is_nil(row.decisionSnapshot)
    assert.is_nil(row.quoteSnapshot)

    _G.time, _G.GetMoney, _G.C_AuctionHouse, _G.C_Timer = nil, nil, nil, nil
    _G.GetCoinTextureString, _G.GetTime, _G.SOUNDKIT, _G.PlaySound = nil, nil, nil, nil
  end)

  it("freezes a commodity success without a matching final quote instead of estimating a purchase", function()
    local flipCalls, ledgerCalls = 0, 0
    _G.C_AuctionHouse = {}
    _G.GetTime = function() return 0 end
    local GC = {
      Theme = { ROW_H = 20, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return {} end, RecordFlip = function() flipCalls = flipCalls + 1 end },
      Ledger = { RecordSniperBuy = function() ledgerCalls = ledgerCalls + 1 end },
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    local row = { purchaseStage = "confirming", purchaseToken = 3, purchaseDeal = { itemID = 42, isCommodity = true } }
    setUpvalue(GC.Sniper.OnCommodityPurchaseSucceeded, "commodityPurchase", { row = row, itemID = 42, token = 3 })
    GC.Sniper.OnCommodityPurchaseSucceeded()

    assert.equal("frozen", row.purchaseStage)
    assert.equal(0, flipCalls)
    assert.equal(0, ledgerCalls)
    _G.C_AuctionHouse, _G.GetTime = nil, nil
  end)

  it("discards a drained terminal event instead of resolving a newer commodity attempt", function()
    local GC = {
      Theme = { ROW_H = 20, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    local old = { row = { purchaseToken = 1 }, itemID = 42, token = 1 }
    local newerRow = { purchaseToken = 2, purchaseStage = "buying", purchaseDeal = { itemID = 42, isCommodity = true } }
    local newer = { row = newerRow, itemID = 42, token = 2 }
    setUpvalue(GC.Sniper.OnCommodityPurchaseFailed, "commodityDraining", old)
    setUpvalue(GC.Sniper.OnCommodityPurchaseFailed, "commodityPurchase", newer)

    GC.Sniper.OnCommodityPurchaseFailed() -- terminal failure belonging to the drained old attempt

    assert.equal("buying", newerRow.purchaseStage)
  end)

  it("consumes a delayed first price event from an aborted pre-quote attempt", function()
    local GC = {
      Theme = { ROW_H = 20, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end

    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", { row = {}, itemID = 42, token = 1 })
    GC.Sniper.OnCommodityPriceUpdated(1000000, 1000000)
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))
  end)
end)
