local helper = require("spec.spec_helper")

-- Live price caps: the money-facing half of the review fixes. A cap is the player's own rule --
-- "this item at or under this price" -- and everything here is about what that rule is allowed
-- to spend and what the buy window says while it spends it:
--
--   * a cap decision says what its units cost (`entryTotal`), so the dialog shows real UNIT and
--     TOTAL, the requote guard holds the quote against the real plan, and the wallet check runs;
--   * a commodity cap buys within the player's own Max units per buy and wallet limit, and at
--     any saving at all -- "at or under" is the promise, with no 5g floor under it;
--   * at the server's quote the window shows the quantity that Confirm will actually buy;
--   * a quantity chosen on a cap row is decided by the cap rule, never by the market engine, and
--     a quote that may hold units above the cap is never confirmed quietly.
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

  local books, money, cancels, confirms

  -- 10 x 100g + 10 x 190g + 10 x 250g, with the cap at 200g: twenty units qualify, ten do not.
  local LADDER = {
    { unitPrice = 1000000, quantity = 10 },
    { unitPrice = 1900000, quantity = 10 },
    { unitPrice = 2500000, quantity = 10 },
  }

  local function loadSniper(settings)
    books, money, cancels, confirms = {}, 10000000000, 0, 0
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
        -- No market data for anything: the items a cap exists for are exactly those.
        GetItemValue = function() return nil end,
        GetWatchlist = function() return {} end,
        -- The old flip queue; what it takes from a cap buy (nothing) is spec/flips_spec.lua's.
        RecordFlip = function() end,
      },
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
    -- The two stores a purchase is recorded in, for real: the ledger the Companion uploads and
    -- the acquisition batches the Sell tab's cost basis is built from.
    helper.loadModule("Core/Ledger.lua", GC)
    helper.loadModule("Core/Acquisitions.lua", GC)
    local saved = {}
    GC.Ledger.Init(saved)
    GC.Acquisitions.Init(saved)
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

  -- The seven fields the upload takes all-or-nothing as the engine's decision evidence
  -- (goldcap-companion's savedvars.rs decision_evidence, the site's ledger entrySchema).
  local EVIDENCE = { "decisionVersion", "decisionStatus", "decisionReasons", "stressUnit",
    "expectedProfit", "recommendedQuantity", "sourceAt" }

  -- A cap buy is recorded where every sniper buy is -- the session, the ledger row the
  -- Companion uploads, the acquisition batch behind the Sell tab's cost basis -- at exactly
  -- what it cost, and with none of the decision evidence it never had.
  local function assertRecordedCapBuy(GC, itemID, quantity, total)
    assert.equal(1, GC.Sniper.session.buys)
    assert.equal(total, GC.Sniper.session.spent)
    assert.equal(0, GC.Sniper.session.estProfit)
    local entries = GC.Ledger.GetEntries()
    assert.equal(1, #entries)
    local entry = entries[1]
    assert.equal("buy", entry.kind)
    assert.equal("goldcap_sniper", entry.source)
    assert.equal(itemID, entry.itemID)
    assert.equal(quantity, entry.qty)
    assert.equal(total, entry.total)
    assert.is_true(entry.cap)
    for _, field in ipairs(EVIDENCE) do assert.is_nil(entry[field], field) end
    local batches = GC.Acquisitions.GetAll()
    assert.equal(1, #batches)
    assert.equal("goldcap", batches[1].source)
    assert.equal(quantity, batches[1].originalQty)
    assert.equal(total, batches[1].originalTotal)
    assert.is_nil(batches[1].targetUnit) -- no resale target was ever measured
    assert.is_string(batches[1].positionKey)
    assert.equal(entry.key, batches[1].sniperEvidenceKey)
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

    -- The window's own status line said "live safety confirmed" over a cap arm -- the engine's
    -- verdict, which a cap never asked for. It says what the Check actually found.
    it("says the price is at or under yours, not that the engine confirmed its safety", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local levels = { { unitPrice = 900000, quantity = 5 } }
      local live = capLive(GC, 42, levels)
      local deal = boardDeal(GC, 42)
      local row = { deal = deal, purchaseStage = "requerying" }
      local lines = {}
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", fakeDialog(row, deal))
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "frame",
        { status = { SetText = function(_, text) lines[#lines + 1] = text end } })
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      local applyRequeryResult = getUpvalue(finishRequery, "applyRequeryResult")
      -- The board repaint needs the whole frame; it is not this test's subject.
      setUpvalue(applyRequeryResult, "refreshRows", function() end)

      applyRequeryResult(row, 42, live)

      assert.equal("ready", row.purchaseStage)
      assert.equal("at or under your price -- click Buy to purchase", lines[1])
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

      assert.is_nil(row.purchaseStage)
      assertRecordedCapBuy(GC, 42, 5, 4500000)
    end)
  end)

  describe("at the server's quote", function()
    -- Caps fixes 2e: the stamp wrote every unit under the cap into the quantity box while
    -- Confirm bought the two that were armed.
    it("shows the quantity Confirm will buy and the quote's own total for it", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      books[42] = { { unitPrice = 900000, quantity = 5 } }
      local deal = { itemID = 42, isCommodity = true, cap = 1000000, unitPrice = 900000, qty = 5 }
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = { status = "SAFE", buyable = true, cap = true, quantity = 2,
          entryTotal = 1800000, entryUnitDisplay = 900000, unit = 900000, capUnit = 1000000 } }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })

      GC.Sniper.OnCommodityPriceUpdated(900000, 1800000)

      assert.equal("confirm", row.purchaseStage)
      assert.equal("2", d.qtyBox.editBox.text)
      assert.equal(GC.Util.FormatMoney(1800000), d.totalCostText.text)
      assert.equal(2, row.quoteSnapshot.quantity)
      assert.equal(2, row.quoteSnapshot.decision.quantity)
      assert.equal(1800000, row.quoteSnapshot.decision.entryTotal)
    end)

    -- The same quantity is what the purchase is recorded from. A quote decision that named a
    -- different quantity than the quote itself used to leave a successful cap buy frozen on
    -- "purchase total unavailable -- inspect mailbox" with nothing recorded.
    it("records a confirmed cap buy instead of freezing it for the mailbox", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      books[42] = { { unitPrice = 900000, quantity = 5 } }
      local deal = { itemID = 42, isCommodity = true, cap = 1000000, unitPrice = 900000, qty = 5 }
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = { status = "SAFE", buyable = true, cap = true, quantity = 2,
          entryTotal = 1800000, entryUnitDisplay = 900000, unit = 900000, capUnit = 1000000 } }
      local d = fakeDialog(row, deal)
      local pending = { row = row, itemID = 42, token = 7 }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", pending)
      GC.Sniper.OnCommodityPriceUpdated(900000, 1800000)
      -- What the Confirm click records on the attempt (onDialogPrimaryClick's own bookkeeping).
      pending.confirmed, pending.deal, pending.quote = true, row.purchaseDeal, row.quoteSnapshot
      row.purchaseStage = "confirming"

      GC.Sniper.OnCommodityPurchaseSucceeded()

      assert.is_nil(row.purchaseStage) -- resolved, not "frozen"
      assertRecordedCapBuy(GC, 42, 2, 1800000)
    end)

    -- Caps fixes 2f: a quote's AVERAGE can sit under the cap while units inside it do not.
    -- The market engine approved 25 units off a ladder with only 20 under the cap; the old
    -- guard read the 166g average against the 200g cap and confirmed it quietly.
    it("never confirms quietly a quote the book says must reach above the cap", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 2000000)
      books[42] = LADDER
      local deal = { itemID = 42, isCommodity = true, cap = 2000000, unitPrice = 1000000, qty = 20 }
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = { status = "SAFE", buyable = true, quantity = 25, entryTotal = 41500000,
          reasons = {} } }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })
      -- The market still approves it: the cap is the only thing that can object.
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "evaluateLive", function()
        return { status = "SAFE", buyable = true, quantity = 25, entryTotal = 41500000, reasons = {} }
      end)

      GC.Sniper.OnCommodityPriceUpdated(1660000, 41500000)

      assert.equal("requote", row.purchaseStage) -- the loud path, not "confirm"
      assert.is_true(d.banner.shown)
      assert.is_false(d.enabled)
      assert.equal(0, confirms)
      assert.is_nil(d.bannerHead:find("Above your price", 1, true)) -- the average is not above it
      assert.is_truthy(d.bannerHead:find("your price", 1, true))
    end)

    it("does not confirm a quote costing more than the book's own units under the cap", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 2000000)
      books[42] = LADDER
      local deal = { itemID = 42, isCommodity = true, cap = 2000000, unitPrice = 1000000, qty = 20 }
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = { status = "SAFE", buyable = true, cap = true, quantity = 20,
          entryTotal = 29000000, entryUnitDisplay = 1450000, unit = 1000000, capUnit = 2000000 } }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", { row = row, itemID = 42, token = 7 })

      -- 200 copper over what the twenty units under the cap cost on the book: something in
      -- the quote is not what the book showed, and the book cannot say it is under the cap.
      GC.Sniper.OnCommodityPriceUpdated(1450010, 29000200)

      assert.not_equal("confirm", row.purchaseStage)
      assert.equal(1, cancels) -- no market data to fall back on: cancelled and re-checked
      assert.equal(0, confirms)
    end)
  end)

  describe("a realm cap lot", function()
    local function realmLot(GC)
      adoptCap(GC, 42, 1000000)
      local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
        { { auctionID = 9, buyout = 800000, itemLevel = 615, quantity = 1 } })
      local deal = { itemID = 42, isCommodity = false, cap = 1000000, unitPrice = 800000, qty = 1,
        auctionID = 9, stale = true }
      return deal, decision
    end

    -- Review fix: DecideRealm names no region reference -- a cap needs none -- and the realm
    -- purchase record was built only for a lot with one, so a gear buy on the player's own price
    -- was recorded nowhere: no session spend, no ledger row, no cost basis in the Sell tab.
    it("is recorded everywhere a sniper buy is, at what PlaceBid paid", function()
      local GC = loadSniper()
      local deal, decision = realmLot(GC)
      -- The copy onDialogPrimaryClick buys on: the candidate's identity, item level included.
      local purchaseDeal = { itemID = 42, isCommodity = false, cap = 1000000, boardDeal = deal,
        auctionID = 9, qty = 1, unitPrice = 800000,
        itemKey = { itemID = 42, itemLevel = 615, itemSuffix = 0, battlePetSpeciesID = 0 } }
      local row = { deal = deal, purchaseDeal = purchaseDeal, purchaseStage = "buying",
        purchaseToken = 7, decisionSnapshot = decision }
      getUpvalue(GC.Sniper.OnPurchaseCompleted, "pendingAuction")[9] = row

      GC.Sniper.OnPurchaseCompleted(9)

      assert.is_nil(row.purchaseStage)
      assertRecordedCapBuy(GC, 42, 1, 800000)
      assert.is_truthy(GC.Acquisitions.GetAll()[1].positionKey:find("615", 1, true))
    end)

    -- Review fix: the panel said "At your price" over a button reading "BUY — unverified" and a
    -- status line about unmeasured sale speed -- the words for a lot judged against a region
    -- reference, not for the player's own price.
    it("is offered as a buy at the player's own price, not an unverified one", function()
      local GC = loadSniper()
      local deal, decision = realmLot(GC)
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      local applyRequeryResult = getUpvalue(finishRequery, "applyRequeryResult")

      applyRequeryResult(row, 42, { isCommodity = false, decision = decision })

      assert.equal("ready", row.purchaseStage)
      assert.equal("Buy", d.label)
      assert.is_true(d.enabled)
      assert.equal("at or under your price -- click Buy to purchase", d.written[#d.written])
    end)
  end)

  describe("a commodity cap row on the board", function()
    local function fakeRow()
      local function cell()
        local w = { text = "" }
        function w:SetText(t) self.text = t end
        function w:SetTextColor() end
        function w:SetTexture() end
        function w:SetLabel() end
        function w:SetVariant() end
        function w:Show() end
        function w:Hide() end
        function w:SetColorTexture() end
        function w:Enable() end
        function w:Disable() end
        return w
      end
      local row = { buy = cell(), tierChip = cell(), icon = cell(), nameText = cell(),
        discountText = cell(), unitText = cell(), priceText = cell(), profitText = cell(),
        trendText = cell(), highlight = cell(), rail = cell(), pinBg = cell(), shown = false }
      function row:Show() self.shown = true end
      function row:Hide() self.shown = false end
      function row:IsShown() return self.shown end
      function row:SetAlpha() end
      return row
    end

    local TWO_LEVELS = { { unitPrice = 1000000, quantity = 10 }, { unitPrice = 1900000, quantity = 10 } }

    local function refreshRowsOf(GC)
      return getUpvalue(getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals"), "refreshRows")
    end

    -- Review fix: the row's total was its cheapest level times the quantity -- 2000g for a buy
    -- that costs 2900g across two levels.
    it("shows what the whole cap buy costs, not the cheapest level times the quantity", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 2000000)
      capLive(GC, 42, TWO_LEVELS)
      local row = fakeRow()

      getUpvalue(refreshRowsOf(GC), "setRowDeal")(row, boardDeal(GC, 42))

      assert.equal(GC.Util.FormatMoney(1000000), row.unitText.text)
      assert.equal(GC.Util.FormatMoney(29000000), row.priceText.text)
    end)

    it("sorts by that same total", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 2000000)
      capLive(GC, 42, TWO_LEVELS)
      local ordinary = { itemID = 7, isCommodity = true, unitPrice = 25000000, qty = 1, profit = 0 }
      local applySortOverride = getUpvalue(getUpvalue(refreshRowsOf(GC), "renderList"), "applySortOverride")
      setUpvalue(applySortOverride, "sortOverride", { key = "price", desc = true })

      local sorted = applySortOverride({ ordinary, boardDeal(GC, 42) })

      assert.equal(42, sorted[1].itemID) -- 2900g ahead of 2500g
    end)
  end)

  describe("choosing a quantity on a cap row", function()
    local function armLadder(GC)
      adoptCap(GC, 42, 2000000)
      local live = capLive(GC, 42, LADDER)
      local deal = boardDeal(GC, 42)
      local row = { deal = deal }
      local d = armOnDialog(GC, row, deal, live.decision, LADDER)
      -- The quantity controls are wired inside createDialog; reach them the way the dialog does.
      local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
      local refreshRows = getUpvalue(clearDeals, "refreshRows")
      local createRow = getUpvalue(refreshRows, "createRow")
      local buildRowCell = getUpvalue(createRow, "buildRowCell")
      local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
      local openDialog = getUpvalue(onBuyClick, "openDialog")
      local createDialog = getUpvalue(openDialog, "createDialog")
      return row, deal, d, getUpvalue(createDialog, "applyQuickFillQty")
    end

    -- Caps fixes 2f: a typed quantity went to the market engine, which knows nothing about an
    -- item a cap exists for -- any number disarmed the dialog.
    it("re-decides a typed quantity by the cap rule, not the market engine", function()
      local GC = loadSniper()
      local row, _, d, applyQuickFillQty = armLadder(GC)
      local applyChosenQty = getUpvalue(applyQuickFillQty, "applyChosenQty")

      applyChosenQty(row, 5)

      assert.equal("ready", row.purchaseStage)
      assert.is_true(row.decisionSnapshot.cap)
      assert.equal(5, row.decisionSnapshot.quantity)
      assert.equal(5 * 1000000, row.decisionSnapshot.entryTotal)
      assert.is_true(d.enabled)
    end)

    it("fills to what the cap allows, not to the whole book", function()
      local GC = loadSniper()
      local row, deal, d, applyQuickFillQty = armLadder(GC)
      local qtyMaxAvailable = getUpvalue(applyQuickFillQty, "qtyMaxAvailable")

      assert.equal(20, qtyMaxAvailable(deal))
      assert.equal("of 20", d.qtyOfLabel.text)
      applyQuickFillQty(100)

      assert.equal("ready", row.purchaseStage)
      assert.equal(20, row.decisionSnapshot.quantity)
      assert.equal(29000000, row.decisionSnapshot.entryTotal)
    end)

    -- Review fix: after the wallet dropped since the Check, the cap rule allowed one unit and
    -- "of N" said "of 1" beside a box still showing the ten that were armed. The box shows what
    -- Buy will start; the ceiling beside it never reads below it. Whether those ten still fit the
    -- wallet limit is judged again at the quote, against the gold in the bags then.
    it("never says 'of N' below the quantity the box is showing", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 2000000)
      local levels = { { unitPrice = 1000000, quantity = 10 } }
      local live = capLive(GC, 42, levels)
      local deal = boardDeal(GC, 42)
      local row = { deal = deal }
      local d = armOnDialog(GC, row, deal, live.decision, levels)
      assert.equal("10", d.qtyBox.editBox.text)
      money = 30000000 -- 3,000g now: 5% of it pays for one unit at 100g

      local stamp = getUpvalue(armReadyFn(GC), "stampDialogFromDecision")
      getUpvalue(stamp, "refreshQtyRow")()

      assert.equal("10", d.qtyBox.editBox.text)
      assert.equal("of 10", d.qtyOfLabel.text)
    end)

    it("will not arm units above the cap, even where the market would", function()
      local GC = loadSniper()
      local row, _, _, applyQuickFillQty = armLadder(GC)
      local applyChosenQty = getUpvalue(applyQuickFillQty, "applyChosenQty")
      setUpvalue(applyChosenQty, "evaluateLive", function(_, _, n)
        return { status = "SAFE", buyable = true, quantity = n, entryTotal = n * 1660000, reasons = {} }
      end)

      applyChosenQty(row, 25)

      assert.not_equal(25, row.decisionSnapshot and row.decisionSnapshot.quantity)
      assert.not_equal("ready", row.purchaseStage)
    end)
  end)
end)
