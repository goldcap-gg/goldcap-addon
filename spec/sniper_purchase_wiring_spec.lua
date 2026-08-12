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
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
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

    -- The cancellation remains owned until a terminal event. A second late price must be
    -- drained too; otherwise its terminal event could be misattributed to a later Start.
    local draining = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining")
    assert.is_table(draining)
    GC.Sniper.OnCommodityPriceUpdated(1040000, 1040000)
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == draining)
    GC.Sniper.OnCommodityPurchaseFailed()
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))

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

  it("retains a commodity tombstone through late prices until its terminal event", function()
    local cancelCalls = 0
    _G.C_AuctionHouse = { CancelCommoditiesPurchase = function() cancelCalls = cancelCalls + 1 end }
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

    local old = { row = { purchaseToken = 1 }, itemID = 42, token = 1 }
    local newerRow = { purchaseToken = 2, purchaseStage = "buying", purchaseDeal = { itemID = 42, isCommodity = true } }
    local newer = { row = newerRow, itemID = 42, token = 2 }
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", old)
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", newer)

    GC.Sniper.OnCommodityPriceUpdated(1000000, 1000000) -- late price for the drained old attempt

    assert.equal(1, cancelCalls)
    assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == old)
    assert.equal("buying", newerRow.purchaseStage)

    GC.Sniper.OnCommodityPurchaseFailed() -- terminal failure belonging to the drained old attempt
    assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPurchaseFailed, "commodityDraining"))
    assert.equal("buying", newerRow.purchaseStage)
    _G.C_AuctionHouse = nil
  end)

  it("keeps a delayed price tombstone until a terminal event", function()
    _G.C_AuctionHouse = { CancelCommoditiesPurchase = function() end }
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
    assert.is_table(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining"))
    _G.C_AuctionHouse = nil
  end)

  it("records the confirmed final quote exactly once after an AH-close tombstone", function()
    local flipPurchase, ledgerPurchase, confirmCalls, cancelDisabled = nil, nil, 0, false
    _G.time = function() return 100000 end
    _G.GetTime = function() return 0 end
    _G.C_AuctionHouse = { ConfirmCommoditiesPurchase = function() confirmCalls = confirmCalls + 1 end }
    local GC = {
      Theme = { ROW_H = 20, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = {
        GetItemValue = function() return {} end,
        RecordFlip = function(_, purchase) flipPurchase = purchase end,
      },
      Ledger = {
        Context = function() return {} end,
        RecordSniperBuy = function(_, purchase) ledgerPurchase = purchase end,
      },
      Sell = { Reset = function() end, SellableCount = function() return 0 end },
      Print = function() end,
      db = { settings = { sniper = {} } },
    }
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local row = {
      purchaseStage = "confirm", purchaseToken = 9,
      purchaseDeal = { itemID = 42, isCommodity = true },
      quoteSnapshot = {
        token = 9, itemID = 42, quantity = 3, total = 123456,
        decision = { version = 1, status = "SAFE", buyable = true, quantity = 3,
          reasons = { "safe" }, exitUnit = 60000, stressProfit = 42000 },
        market = { sourceAt = 99999 },
      },
    }
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
    -- Follow the real row-click closure chain to the hardware-only Confirm handler and the
    -- exact OnHide abort helper; this is intentionally not a hand-written state transition.
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local confirm = getUpvalue(createDialog, "onDialogPrimaryClick")
    local abortOnHide = getUpvalue(createDialog, "abortRowPurchase")
    local fakeDialog = {
      row = row,
      primaryBtn = { Disable = function() end },
      cancelBtn = { Disable = function() cancelDisabled = true end },
      status = { SetText = function() end, SetTextColor = function() end },
      banner = { Hide = function() end },
      SetHeight = function() end,
      Hide = function() end,
      baseHeight = 1,
    }
    setUpvalue(confirm, "dialog", fakeDialog)
    setUpvalue(confirm, "commodityPurchase", { row = row, itemID = 42, token = 9 })

    confirm() -- exact protected click path
    assert.equal(1, confirmCalls)
    assert.is_true(cancelDisabled)
    assert.equal("confirming", row.purchaseStage)
    fakeDialog.row = nil -- exact OnHide ordering before it invokes abortRowPurchase
    abortOnHide(row, "purchase canceled")
    assert.equal("confirming", row.purchaseStage)

    GC.Sniper.OnAuctionHouseClosed()
    GC.Sniper.OnCommodityPurchaseSucceeded()
    GC.Sniper.OnCommodityPurchaseSucceeded() -- duplicate terminal is a no-op

    assert.is_table(flipPurchase)
    assert.is_true(flipPurchase == ledgerPurchase)
    assert.equal(123456, flipPurchase.total)
    assert.equal(1, GC.Sniper.session.buys)
    assert.equal(123456, GC.Sniper.session.spent)
    _G.time, _G.GetTime, _G.C_AuctionHouse = nil, nil, nil
  end)

  it("ignores a stale requery result after its row token advances", function()
    _G.C_AuctionHouse = {}
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

    local row = { purchaseStage = "requerying", purchaseToken = 2, deal = { itemID = 42, isCommodity = true } }
    local old = { row = row, itemID = 42, token = 1, deal = row.deal }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery", { [42] = old })
    GC.Sniper.OnCommoditySearchResults(42)

    assert.equal("requerying", row.purchaseStage)
    _G.C_AuctionHouse = nil
  end)

  it("token-fences an old Check timeout from a newer Check attempt", function()
    local timers = {}
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    local GC = {
      Theme = { ROW_H = 20, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end

    -- Reach the same private Check function the row click ultimately uses, through real
    -- closures rather than duplicating its logic in the fixture.
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local startRequery = getUpvalue(openDialog, "startRequery")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local abortRowPurchase = getUpvalue(createDialog, "abortRowPurchase")
    setUpvalue(startRequery, "driver", {
      isReady = function() return false end,
      getKeyInfo = function() return { isCommodity = true } end,
    })

    local deal = { itemID = 42, isCommodity = true }
    local row = { deal = deal }
    startRequery(row, deal)
    abortRowPurchase(row, nil) -- unsent Check is cancelled locally; no drain is needed
    startRequery(row, deal)

    assert.equal(2, row.purchaseToken)
    assert.equal(2, #timers)
    timers[1]() -- timer for token 1 must not alter the live token-2 Check
    assert.equal("requerying", row.purchaseStage)
    local awaiting = getUpvalue(GC.Sniper.OnCommoditySearchResults, "awaitingRequery")
    assert.equal(2, awaiting[42].token)
    _G.C_Timer = nil
  end)

  it("drains an old search result before it can resolve a newer prewarm attempt", function()
    _G.C_AuctionHouse = {}
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

    local old = { itemID = 42, token = 1, sent = true }
    local warm = { itemID = 42, token = 2, sent = true, deal = { itemID = 42 } }
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining", { [42] = old })
    setUpvalue(GC.Sniper.OnCommoditySearchResults, "prewarmAttempt", warm)

    GC.Sniper.OnCommoditySearchResults(42)

    assert.is_nil(getUpvalue(GC.Sniper.OnCommoditySearchResults, "requeryDraining")[42])
    assert.is_true(getUpvalue(GC.Sniper.OnCommoditySearchResults, "prewarmAttempt") == warm)
    _G.C_AuctionHouse = nil
  end)

  it("does not Start while a cancelled requote tombstone still owns commodity events", function()
    local starts = 0
    _G.C_AuctionHouse = { StartCommoditiesPurchase = function() starts = starts + 1 end }
    local GC = {
      Theme = { ROW_H = 20, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end, PauseReasons = function() return {} end } end },
      Data = { GetItemValue = function() return nil end },
    }
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    local function getUpvalue(fn, wanted)
      for i = 1, math.huge do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
      end
      error("missing upvalue " .. wanted)
    end
    local function setUpvalue(fn, wanted, value)
      for i = 1, math.huge do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then debug.setupvalue(fn, i, value); return end
      end
      error("missing upvalue " .. wanted)
    end
    local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = getUpvalue(clearDeals, "refreshRows")
    local createRow = getUpvalue(refreshRows, "createRow")
    local buildRowCell = getUpvalue(createRow, "buildRowCell")
    local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
    local openDialog = getUpvalue(onBuyClick, "openDialog")
    local createDialog = getUpvalue(openDialog, "createDialog")
    local primary = getUpvalue(createDialog, "onDialogPrimaryClick")
    local deal = { itemID = 42, isCommodity = true }
    local row = {
      deal = deal, purchaseStage = "ready", purchaseToken = 5,
      decisionSnapshot = { status = "SAFE", buyable = true, quantity = 3 },
    }
    setUpvalue(primary, "dialog", {
      row = row,
      primaryBtn = { Disable = function() end },
      status = { SetText = function() end, SetTextColor = function() end },
    })
    setUpvalue(primary, "commodityDraining", { itemID = 42, token = 4 })

    primary()

    assert.equal(0, starts)
    assert.equal("ready", row.purchaseStage)
    _G.C_AuctionHouse = nil
  end)
end)
