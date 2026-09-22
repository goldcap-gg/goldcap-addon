local helper = require("spec.spec_helper")

-- Live price caps: the money-facing half of the review fixes. A cap is the player's own rule --
-- "this item at or under this price" -- and everything here is about what that rule is allowed
-- to spend and what the buy window says while it spends it:
--
--   * a cap decision says what its units cost (`entryTotal`), so the dialog shows real UNIT and
--     TOTAL, the requote guard holds the quote against the real plan, and the wallet check runs;
--   * a commodity cap buys within the player's own Max units per buy and wallet limit, and at
--     any saving at all -- "at or under" is the promise, with no 5g floor under it.
--
-- No protected call is issued anywhere here: every purchase call stays in onDialogPrimaryClick,
-- which spec/sniper_purchase_wiring_spec.lua pins.
describe("Live price caps -- buying at the player's own price", function()
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

  local values, books, money, cancels, confirms, recorded

  local function loadSniper(settings)
    values, books, money, cancels, confirms = {}, {}, 10000000000, 0, 0
    recorded = { acquisitions = 0, flips = 0, ledger = 0 }
    _G.time = function() return 100000 end
    _G.GetTime = function() return 100 end
    _G.GetMoney = function() return money end
    _G.GetCoinTextureString = function(value) return tostring(value) end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.SOUNDKIT = { RAID_WARNING = 1, MAP_PING = 2, READY_CHECK = 3 }
    _G.PlaySound = function() end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() cancels = cancels + 1 end,
      ConfirmCommoditiesPurchase = function() confirms = confirms + 1 end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      HasFullBrowseResults = function() return false end,
      GetNumCommoditySearchResults = function() return 0 end,
      GetCommoditySearchResultInfo = function() return nil end,
    }
    local sniper = { sound = false, showRefused = false, watchPins = {},
      maxCapitalShare = 0.05, maxDailyDemandShare = 0.02, maxQuantity = 200,
      minimumProfitCopper = 50000, minimumRoi = 0.10 }
    for k, v in pairs(settings or {}) do sniper[k] = v end
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
        tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
        color = { fg = { 0.92, 0.91, 0.89 }, fgMuted = { 0.72, 0.71, 0.69 },
          fgDim = { 0.55, 0.54, 0.52 }, red = { 0.9, 0.28, 0.3 },
          green = { 0.25, 0.85, 0.25 }, gold = { 0.83, 0.64, 0.22 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = {
        GetItemValue = function(itemID) return values[itemID] end,
        GetWatchlist = function() return {} end,
        RecordFlip = function() recorded.flips = recorded.flips + 1 end,
      },
      Ledger = {
        Context = function() return { char = "A-R", region = "eu" } end,
        RecordSniperBuy = function() recorded.ledger = recorded.ledger + 1 end,
      },
      Acquisitions = { RecordGoldCap = function() recorded.acquisitions = recorded.acquisitions + 1 end },
      Print = function() end,
      db = { settings = { sniper = sniper } },
    }
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/CheckVerdict.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/BoardRows.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    -- The live driver, at its seam: `books` is the client's commodity search buffer.
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() end,
      commodityBook = function(itemID) return books[itemID] end,
      commodityResult = function(itemID) return books[itemID] and { avail = 1 } or nil end,
      itemResult = function() return {} end,
      itemLots = function() return {} end,
      onStatus = function() end,
    })
    return GC
  end

  local function adoptCap(GC, itemID, c, l)
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = {},
      caps = { { i = itemID, c = c, l = l or 0 } } }
    GC.Caps.Adopt()
  end

  local function recorder()
    local w = { text = "", shown = nil }
    function w:SetText(t) self.text = t end
    function w:SetTextColor() end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:ClearAllPoints() end
    function w:SetPoint() end
    function w:SetHeight() end
    function w:GetStringHeight() return 24 end
    return w
  end

  -- A dialog double that answers everything the purchase paths and the quantity row ask a
  -- dialog, and records what the player would read on it.
  local function fakeDialog(row, deal)
    local d = { row = row, deal = deal, written = {}, enabled = false, height = 0, baseHeight = 400 }
    d.primaryBtn = {
      Disable = function() d.enabled = false end,
      Enable = function() d.enabled = true end,
      IsEnabled = function() return d.enabled end,
      SetLabel = function(_, text) d.label = text end,
      text = { SetTextColor = function() end },
    }
    d.cancelBtn = { Enable = function() end, Disable = function() end, SetLabel = function() end }
    d.status = {
      SetText = function(_, text) d.written[#d.written + 1] = text end,
      SetTextColor = function() end, ClearAllPoints = function() end, SetPoint = function() end,
    }
    d.banner = { shown = false,
      Hide = function(self) self.shown = false end, Show = function(self) self.shown = true end,
      IsShown = function(self) return self.shown end,
      head = { SetText = function(_, text) d.bannerHead = text end }, detail = { SetText = function() end } }
    d.SetHeight = function(_, height) d.height = height end
    d.Hide = function() end
    d.IsShown = function() return true end
    d.fixedHeight, d.diagnosticGaps, d.diagnosticMinimumHeight = 400, 4, 108
    d.detailsOpen, d.evidenceTopOpen, d.evidenceTopClosed = false, -200, -100
    for _, field in ipairs({ "decisionStatusText", "unitPriceText", "totalCostText", "exitUnitText",
      "profitText", "mvText", "soldText", "sellThroughText", "sourceAgeText", "reasonText",
      "verdictHead", "verdictSub", "diagnosticText", "mvNote", "nameText", "qtyLotText",
      "qtyOfLabel" }) do
      d[field] = recorder()
    end
    d.tierChip = { SetLabel = function() end, Show = function() end, Hide = function() end }
    d.icon = { SetTexture = function() end }
    local editBox = { text = "" }
    function editBox:SetText(t) self.text = t end
    function editBox:GetText() return self.text end
    function editBox:HasFocus() return false end
    function editBox:ClearFocus() end
    function editBox:EnableMouse() end
    function editBox:SetTextColor() end
    d.qtyBox = { editBox = editBox, Show = function() end, Hide = function() end }
    d.quickFillBtns = {}
    return d
  end

  after_each(function()
    _G.time, _G.GetTime, _G.GetMoney, _G.GetCoinTextureString = os.time, nil, nil, nil
    _G.C_Timer, _G.SOUNDKIT, _G.PlaySound, _G.ITEM_QUALITY_COLORS, _G.Item = nil, nil, nil, nil, nil
    _G.C_AuctionHouse, _G.GoldCap_AppRuns = nil, nil
  end)

  -- What the board's own cap branch builds for a commodity: the deal on the board and the
  -- decision it carries (evaluateLiveCommodityDeal, reached the way a drill result reaches it).
  local function capLive(GC, itemID, levels)
    books[itemID] = levels
    local evaluate = getUpvalue(GC.Sniper.OnCommoditySearchResults, "evaluateLiveCommodityDeal")
    return evaluate(itemID, levels)
  end

  local function boardDeal(GC, itemID)
    return GC.Sniper._CurrentLiveDeal(itemID)
  end

  local function armReadyFn(GC)
    local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
    local applyRequeryResult = getUpvalue(finishRequery, "applyRequeryResult")
    return getUpvalue(applyRequeryResult, "armReady")
  end

  -- Arms `row` the way a Check that found a cap hit arms it, on the dialog the player is reading.
  local function armOnDialog(GC, row, deal, decision, levels)
    local d = fakeDialog(row, deal)
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
    armReadyFn(GC)(row, deal, decision, levels)
    return d
  end

  describe("the decision a commodity cap arms", function()
    -- Caps fixes 2c: the whole book used to go into one purchase.
    it("buys no more than the player's Max units per buy", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local live = capLive(GC, 42, { { unitPrice = 900000, quantity = 5000 } })

      assert.equal(200, live.decision.quantity)
      assert.equal(200 * 900000, live.decision.entryTotal)
      assert.equal(200, boardDeal(GC, 42).qty)
    end)

    it("stops at the player's wallet limit", function()
      local GC = loadSniper()
      money = 180000000 -- 18,000g: 5% of it pays for ten units at 90g
      adoptCap(GC, 42, 1000000)
      local live = capLive(GC, 42, { { unitPrice = 900000, quantity = 5000 } })

      assert.equal(10, live.decision.quantity)
      assert.equal(9000000, live.decision.entryTotal)
    end)

    -- Caps fixes 2d: the player's own 5g profit floor has no business under their own price.
    it("fires at the cap exactly, with no saving under it at all", function()
      local GC = loadSniper({ minimumProfitCopper = 50000 })
      adoptCap(GC, 42, 1000000)
      local live = capLive(GC, 42, { { unitPrice = 1000000, quantity = 1 } })

      assert.is_true(live.decision.cap)
      assert.equal(1000000, boardDeal(GC, 42).unitPrice)
    end)

    -- Caps fixes 2b, the probe from the review: a cap over two levels was "planned" at the
    -- cheapest level times the quantity, so its own honest quote read as a 1.45x rise.
    it("holds the quote against what the plan really costs, so it does not cry wolf", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 2000000)
      local levels = { { unitPrice = 1000000, quantity = 10 }, { unitPrice = 1900000, quantity = 10 } }
      local live = capLive(GC, 42, levels)
      local deal = boardDeal(GC, 42)
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = live.decision }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })

      GC.Sniper.OnCommodityPriceUpdated(1450000, 29000000)

      assert.equal("confirm", row.purchaseStage)
      assert.is_false(d.banner.shown)
      assert.is_true(d.enabled)
      assert.equal(0, cancels)
    end)

    -- Caps fixes 2b: updateBuyAffordance reads the total the stamper put on screen, and a cap
    -- decision gave it none -- so the wallet check simply did not run for a cap buy.
    it("checks the player's gold against what the cap buy costs", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 2000000)
      local levels = { { unitPrice = 1000000, quantity = 10 } }
      local live = capLive(GC, 42, levels)
      local deal = boardDeal(GC, 42)
      money = 1000 -- gold spent elsewhere since the check
      local row = { deal = deal }
      local d = armOnDialog(GC, row, deal, live.decision, levels)

      assert.equal("ready", row.purchaseStage)
      assert.is_false(d.enabled)
      assert.is_truthy(d.written[#d.written]:find("not enough gold", 1, true))
    end)

    -- A cap decision carries no stressProfit -- nothing measured a resale -- and a successful
    -- buy adds its expected profit into the session: a cap buy counts there as exactly nothing,
    -- not as a crash and not as the saving under the cap dressed up as profit.
    it("records a confirmed cap buy with no profit claimed for it", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local live = capLive(GC, 42, { { unitPrice = 900000, quantity = 5 } })
      local deal = boardDeal(GC, 42)
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = live.decision }
      local d = fakeDialog(row, deal)
      local pending = { row = row, itemID = 42, token = 7 }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", pending)
      GC.Sniper.OnCommodityPriceUpdated(900000, 4500000)
      -- What the Confirm click records on the attempt (onDialogPrimaryClick's own bookkeeping).
      pending.confirmed, pending.deal, pending.quote = true, row.purchaseDeal, row.quoteSnapshot
      row.purchaseStage = "confirming"

      GC.Sniper.OnCommodityPurchaseSucceeded()

      assert.equal(1, recorded.acquisitions)
      assert.is_nil(row.purchaseStage)
      assert.equal(4500000, GC.Sniper.session.spent)
      assert.equal(0, GC.Sniper.session.estProfit)
    end)
  end)
end)
