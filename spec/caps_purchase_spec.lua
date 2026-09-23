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

  -- Final review S3. A cap buy is clamped -- Max units per buy, the wallet limit -- and the buy
  -- takes its row off the board, while the rest of the wall sits at the same floor with a smaller
  -- quantity. Neither ratchet calls that news (the poll's wants a new floor or a larger quantity,
  -- the book pass's a new floor), so the rest never got a row back. A purchase lets both go; the
  -- ring's memory stays, so the row that comes back does not ring a second time.
  describe("after a buy at the player's price", function()
    local function wallRow(minPrice, quantity)
      return { itemKey = { itemID = 42 }, minPrice = minPrice, totalQuantity = quantity }
    end
    local function isCommodity() return true end

    it("lets the rest of a commodity wall come back", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      GC.Sniper._capPoll:Fold({ wallRow(900000, 5000) })
      assert.equal(1, #GC.Caps.BookHits({ [42] = { floor = 900000, qty = 5000 } }, isCommodity))
      GC.Sniper._drillQueue:Clear()
      local live = capLive(GC, 42, { { unitPrice = 900000, quantity = 5000 } })
      GC.Caps.Announce(boardDeal(GC, 42)) -- the ring played
      local deal = boardDeal(GC, 42)
      local row = { deal = deal, purchaseDeal = deal, purchaseStage = "buying", purchaseToken = 7,
        decisionSnapshot = live.decision }
      local pending = { row = row, itemID = 42, token = 7 }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", fakeDialog(row, deal))
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase", pending)
      GC.Sniper.OnCommodityPriceUpdated(900000, 200 * 900000)
      pending.confirmed, pending.deal, pending.quote = true, row.purchaseDeal, row.quoteSnapshot
      row.purchaseStage = "confirming"

      GC.Sniper.OnCommodityPurchaseSucceeded()

      assert.is_nil(GC.Sniper._CurrentLiveDeal(42)) -- the bought row is gone...
      GC.Sniper._capPoll:Fold({ wallRow(900000, 4800) })
      assert.is_true(GC.Sniper._drillQueue:Has(42)) -- ...and the rest is looked at again
      assert.equal(1, #GC.Caps.BookHits({ [42] = { floor = 900000, qty = 4800 } }, isCommodity))
      assert.is_false(GC.Caps.IsNews({ itemID = 42, isCommodity = true, unitPrice = 900000 }))
    end)

    it("lets the next lot at the same price come back after a realm buy", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      GC.Sniper._capPoll:Fold({ wallRow(800000, 3) })
      GC.Sniper._drillQueue:Clear()
      local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
        { { auctionID = 9, buyout = 800000, itemLevel = 615, quantity = 1 } })
      local deal = { itemID = 42, isCommodity = false, cap = 1000000, unitPrice = 800000, qty = 1,
        auctionID = 9, stale = true }
      local purchaseDeal = { itemID = 42, isCommodity = false, cap = 1000000, boardDeal = deal,
        auctionID = 9, qty = 1, unitPrice = 800000,
        itemKey = { itemID = 42, itemLevel = 615, itemSuffix = 0, battlePetSpeciesID = 0 } }
      local row = { deal = deal, purchaseDeal = purchaseDeal, purchaseStage = "buying",
        purchaseToken = 7, decisionSnapshot = decision }
      getUpvalue(GC.Sniper.OnPurchaseCompleted, "pendingAuction")[9] = row

      GC.Sniper.OnPurchaseCompleted(9)

      GC.Sniper._capPoll:Fold({ wallRow(800000, 2) })
      assert.is_true(GC.Sniper._drillQueue:Has(42))
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

    -- Caps fixes 5g: the diagnostic Status row read WATCH -- the shape a realm purchase is carried
    -- in (onDialogPrimaryClick buys a realm lot on status WATCH plus a candidate), not what
    -- decided it. It names the player's own price, as the board's own chip does.
    it("says on the Status row that the player's own price decided it", function()
      local GC = loadSniper()
      local deal, decision = realmLot(GC)
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")

      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })

      assert.equal("YOUR PRICE", d.decisionStatusText.text)
    end)

    -- Final review m2: the one check this path ran was the gold in the bags. A commodity at the
    -- player's price is held to their own "Max wallet per buy %" (GC.Caps.DecideCommodity); a
    -- realm lot at it went through whatever it cost.
    it("keeps to the player's wallet limit", function()
      local GC = loadSniper()
      local deal, decision = realmLot(GC)
      money = 10000000 -- 1,000g: the 5% limit is 50g, under an 80g lot
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")

      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })

      assert.is_false(d.enabled)
      assert.equal("Costs more than your per-buy wallet limit allows.", d.written[#d.written])
    end)

    -- Final review m4: "(whole lot)" read the board row's own quantity -- the lot the scan saw --
    -- not the lot the Check found and Buy would bid on.
    it("names the size of the lot the Check found", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
        { { auctionID = 9, buyout = 4000000, itemLevel = 615, quantity = 5 } })
      local deal = { itemID = 42, isCommodity = false, cap = 1000000, unitPrice = 800000, qty = 1,
        auctionID = 3, stale = true }
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")

      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })

      assert.equal("5 (whole lot)", d.qtyLotText.text)
    end)
  end)

  -- Final review M1. A Check on a YOUR PRICE row that finds nothing at the player's price -- the
  -- lot was bought between the ring and the click -- falls through to the region verdict, and
  -- that armed "BUY — unverified" on whatever lot sat under the region reference: above the
  -- player's price, or below their item level, with nothing on screen to say so and nothing
  -- between that and PlaceBid on the next click. The window says what the player's price says
  -- about the lot, and holds Buy the way a loud requote holds Confirm.
  describe("a YOUR PRICE row whose Check finds no lot at the player's price", function()
    local timers

    local function checked(GC, candidate, capLevel)
      adoptCap(GC, 42, 1000000, capLevel)
      timers = {}
      _G.C_Timer.After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end
      local unit = math.floor(candidate.buyout / candidate.quantity)
      local decision = { status = "WATCH", reasons = { "realm_item_unverified" },
        quantity = candidate.quantity, entryTotal = candidate.buyout, entryUnitDisplay = unit,
        candidate = candidate }
      local deal = { itemID = 42, isCommodity = false, cap = 1000000, unitPrice = 800000, qty = 1,
        auctionID = 3, stale = true }
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })
      return row, d
    end

    local function holdEnds(seconds)
      for _, timer in ipairs(timers) do
        if timer.seconds == seconds then timer.fn() end
      end
    end

    it("names the player's price and holds Buy when the lot is above it", function()
      local GC = loadSniper()
      local row, d = checked(GC, { auctionID = 10, buyout = 1200000, quantity = 1, itemLevel = 615 })

      assert.equal("ready", row.purchaseStage)
      assert.is_false(d.enabled)
      assert.equal(("Above your price -- quoted %s, your price %s"):format(
        GC.Util.FormatMoney(1200000), GC.Util.FormatMoney(1000000)), d.written[#d.written])
      holdEnds(1.5)
      assert.is_true(d.enabled)
    end)

    it("says the lot is below the item level the price is for", function()
      local GC = loadSniper()
      local _, d = checked(GC, { auctionID = 10, buyout = 800000, quantity = 1, itemLevel = 590 }, 610)

      assert.is_false(d.enabled)
      assert.equal("Item level 590, below the 610 your price is for", d.written[#d.written])
      holdEnds(1.5)
      assert.is_true(d.enabled)
    end)

    it("says both when the lot misses the price and the item level", function()
      local GC = loadSniper()
      local _, d = checked(GC, { auctionID = 10, buyout = 1200000, quantity = 1, itemLevel = 590 }, 610)

      local text = d.written[#d.written]
      assert.is_truthy(text:find("Above your price", 1, true), text)
      assert.is_truthy(text:find("Item level 590, below the 610 your price is for", 1, true), text)
    end)

    it("prices a stack by the unit, like the cap", function()
      local GC = loadSniper()
      local _, d = checked(GC, { auctionID = 10, buyout = 6000000, quantity = 5, itemLevel = 615 })

      assert.equal(("Above your price -- quoted %s, your price %s"):format(
        GC.Util.FormatMoney(1200000), GC.Util.FormatMoney(1000000)), d.written[#d.written])
    end)

    it("does not enable Buy early for a hold that was taken over", function()
      local GC = loadSniper()
      local row, d = checked(GC, { auctionID = 10, buyout = 1200000, quantity = 1, itemLevel = 615 })
      row.purchaseStage = "check"
      holdEnds(1.5)
      assert.is_false(d.enabled)
    end)
  end)

  -- Final review m3. A window stop-and-open put on screen arrived unasked, over the board's own
  -- action column, and was armed the moment its Check landed: a click aimed at a row could land
  -- on its Buy. Its first arm waits, as a loud requote's Confirm does -- in the calm colours.
  describe("the first arm of a window stop-and-open opened", function()
    local timers

    local function realmLot(GC)
      adoptCap(GC, 42, 1000000)
      local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
        { { auctionID = 9, buyout = 800000, itemLevel = 615, quantity = 1 } })
      local deal = { itemID = 42, isCommodity = false, cap = 1000000, unitPrice = 800000, qty = 1,
        auctionID = 9, stale = true }
      return deal, decision
    end

    local function held(GC, arm)
      timers = {}
      _G.C_Timer.After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end
      return arm(GC)
    end

    local function holdEnds()
      for _, timer in ipairs(timers) do
        if timer.seconds == 1.5 then timer.fn() end
      end
    end

    it("holds a commodity's Buy for a moment", function()
      local GC = loadSniper()
      adoptCap(GC, 42, 1000000)
      local levels = { { unitPrice = 900000, quantity = 5 } }
      local live = capLive(GC, 42, levels)
      local deal = boardDeal(GC, 42)
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = held(GC, function()
        local dlg = fakeDialog(row, deal)
        dlg.holdFirstArm = true
        setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", dlg)
        local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
        getUpvalue(finishRequery, "applyRequeryResult")(row, 42, live)
        return dlg
      end)

      assert.equal("ready", row.purchaseStage)
      assert.is_false(d.enabled)
      holdEnds()
      assert.is_true(d.enabled)
      assert.equal("Buy", d.label)
    end)

    it("holds a realm lot's Buy for a moment, once", function()
      local GC = loadSniper()
      local deal, decision = realmLot(GC)
      local row = { deal = deal, purchaseStage = "requerying" }
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      local apply = getUpvalue(finishRequery, "applyRequeryResult")
      local d = held(GC, function()
        local dlg = fakeDialog(row, deal)
        dlg.holdFirstArm = true
        setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", dlg)
        apply(row, 42, { isCommodity = false, decision = decision })
        return dlg
      end)

      assert.is_false(d.enabled)
      holdEnds()
      assert.is_true(d.enabled)
      -- A Refresh later on is the player's own click: armed at once.
      row.purchaseStage = "requerying"
      apply(row, 42, { isCommodity = false, decision = decision })
      assert.is_true(d.enabled)
    end)

    it("is not held on a window the player opened", function()
      local GC = loadSniper()
      local deal, decision = realmLot(GC)
      local row = { deal = deal, purchaseStage = "requerying" }
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      getUpvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })
      assert.is_true(d.enabled)
    end)

    -- The mark itself: openDialog carries it from the drain's open onto the dialog, and a window
    -- the player opens by hand starts without it.
    it("is marked on the dialog by the open stop-and-open makes, and only by it", function()
      local GC = loadSniper()
      local deal, decision = realmLot(GC)
      local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
      local createRow = getUpvalue(getUpvalue(clearDeals, "refreshRows"), "createRow")
      local onBuyClick = getUpvalue(getUpvalue(createRow, "buildRowCell"), "onBuyClick")
      local openDialog = getUpvalue(onBuyClick, "openDialog")
      local row = { deal = deal }
      local d = fakeDialog(row, deal)
      d.Show = function() end
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      timers = {}
      _G.C_Timer.After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end
      deal.prewarm = { at = 100, data = { isCommodity = false, decision = decision } }

      GC.Sniper._capOpening = true
      openDialog(row, deal)
      GC.Sniper._capOpening = nil

      assert.is_false(d.enabled)
      holdEnds()
      assert.is_true(d.enabled)

      row.purchaseStage = nil
      deal.prewarm = { at = 100, data = { isCommodity = false, decision = decision } }
      openDialog(row, deal)
      assert.is_true(d.enabled)
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

    -- In game 2026-09-23: "Void-Tempered Scales x400 Test caps · yo..." -- the VERDICT column
    -- already says YOUR PRICE, and the name cell ran out of room saying it again.
    describe("its item cell", function()
      local function grouped(GC)
        _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, runs = {}, groups = { "Test caps" },
          caps = { { i = 42, c = 2000000, g = 1 } } }
        GC.Caps.Adopt()
        capLive(GC, 42, TWO_LEVELS)
      end

      it("names the group and does not repeat the price", function()
        local GC = loadSniper()
        grouped(GC)
        local row = fakeRow()
        getUpvalue(refreshRowsOf(GC), "setRowDeal")(row, boardDeal(GC, 42))
        assert.is_truthy(row.nameText.text:find("Test caps", 1, true))
        assert.is_nil(row.nameText.text:find("your price", 1, true))
      end)

      it("leaves the group to the tooltip when the cell has no room for it", function()
        local GC = loadSniper()
        grouped(GC)
        local row = fakeRow()
        function row.nameText:IsTruncated() return self.text:find("Test caps", 1, true) ~= nil end
        getUpvalue(refreshRowsOf(GC), "setRowDeal")(row, boardDeal(GC, 42))
        assert.is_nil(row.nameText.text:find("Test caps", 1, true))
        assert.is_truthy(row.nameText.text:find("x20", 1, true)) -- the quantity stays
      end)

      -- Review M6: decided once at the stamp, the group stayed cut after the window narrowed and
      -- never came back after it widened -- a row whose deal did not move skips its repaint. The
      -- row's own size change asks again (createRow's OnSizeChanged).
      it("re-decides the group whenever the row's width changes", function()
        local GC = loadSniper()
        grouped(GC)
        local row = fakeRow()
        local narrow = true
        function row.nameText:IsTruncated() return narrow and self.text:find("Test caps", 1, true) ~= nil end
        getUpvalue(refreshRowsOf(GC), "setRowDeal")(row, boardDeal(GC, 42))
        assert.is_nil(row.nameText.text:find("Test caps", 1, true))

        narrow = false -- the window widened
        GC.Sniper._FitRowName(row)
        assert.is_truthy(row.nameText.text:find("Test caps", 1, true))

        narrow = true -- and narrowed again
        GC.Sniper._FitRowName(row)
        assert.is_nil(row.nameText.text:find("Test caps", 1, true))

        local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
        local text = f:read("*a")
        f:close()
        assert.is_truthy(text:find('row:SetScript("OnSizeChanged", function(self) GC.Sniper._FitRowName(self) end)', 1, true))
        -- And the tooltip names the group for any cap row, with or without a fresh verdict: the
        -- note is its own branch, never gated on a cap verdict.
        local enterAt = assert(text:find('row:SetScript("OnEnter", function(self)', 1, true))
        local enter = text:sub(enterAt)
        local note = assert(enter:find("local capNote = GC.Sniper._CapNote(self.deal)", 1, true))
        assert.is_truthy(enter:find("    if capNote then\n", note, true))
        assert.is_nil(enter:find("verdict.cap and capNote", 1, true))
      end)

      it("says in the row's tooltip what YOUR PRICE means, group included", function()
        local GC = loadSniper()
        grouped(GC)
        assert.equal((GC.L["Listed at or under the price you set on goldcap.gg (group: %s)"]):format("Test caps"),
          GC.Sniper._CapNote(boardDeal(GC, 42)))
        adoptCap(GC, 42, 2000000) -- a price typed for the item alone: no group to name
        capLive(GC, 42, TWO_LEVELS)
        assert.equal(GC.L["Listed at or under the price you set on goldcap.gg. Whether it resells is yours to judge."],
          GC.Sniper._CapNote(boardDeal(GC, 42)))
        assert.is_nil(GC.Sniper._CapNote({ itemID = 7, isCommodity = true, unitPrice = 1 }))
      end)
    end)

    -- In game 2026-09-23 a x400 YOUR PRICE row read "-5s 37c" under PROFIT beside a 400g PRICE:
    -- one unit's resale against the cheapest level, on a row whose every other figure is the
    -- whole buy. It is figured the way every row's is now -- reselling the units the row buys
    -- at the market, after the cut, against what they cost.
    it("figures PROFIT over the whole buy against the market, like every other row", function()
      local GC = loadSniper()
      GC.Data.GetItemValue = function() return { mv = 1100000 } end
      adoptCap(GC, 42, 2000000)
      capLive(GC, 42, TWO_LEVELS)
      local row = fakeRow()

      getUpvalue(refreshRowsOf(GC), "setRowDeal")(row, boardDeal(GC, 42))

      -- 20 units: 20 x floor(110g x 0.95) = 2090g back, against the 2900g they cost.
      assert.equal(GC.Util.FormatMoney(20 * 1045000 - 29000000), row.profitText.text)
    end)

    -- Review M5: the yardstick is the one every row uses (GC.DealMath.Measure). A realm item with
    -- no region reference has none -- its own realm median is noise -- so its PROFIT says nothing.
    it("says nothing under PROFIT for a realm cap lot with no region reference", function()
      local GC = loadSniper()
      GC.Data.GetItemValue = function() return { mv = 900000, kind = "realm_item" } end
      adoptCap(GC, 42, 1000000)
      local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
        { { auctionID = 9, buyout = 800000, itemLevel = 615, quantity = 1 } })
      local evaluate = getUpvalue(GC.Sniper.OnCommoditySearchResults, "evaluateLiveCommodityDeal")
      local capDeal = getUpvalue(evaluate, "buildCapDeal")(42, false, decision, GC.Caps.For(42))
      local row = fakeRow()

      getUpvalue(refreshRowsOf(GC), "setRowDeal")(row, capDeal)

      assert.equal("—", row.profitText.text)
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

    it("says on the Status row that the player's own price decided it", function()
      local GC = loadSniper()
      local _, _, d = armLadder(GC)
      assert.equal("YOUR PRICE", d.decisionStatusText.text)
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

    -- Caps fixes 5g: the ceiling held at the armed ten after the wallet dropped (the test above),
    -- so 100% asked the cap rule for ten units it now refuses and the dialog disarmed with the
    -- generic "live_verification_required". A quick-fill offers what the rule allows now -- and
    -- a hand-typed number above that is brought down to it -- while "of N" still never reads
    -- below the box.
    describe("after the wallet dropped", function()
      local function armTenThenDrop(GC)
        adoptCap(GC, 42, 2000000)
        local levels = { { unitPrice = 1000000, quantity = 10 } }
        local live = capLive(GC, 42, levels)
        local deal = boardDeal(GC, 42)
        local row = { deal = deal }
        local d = armOnDialog(GC, row, deal, live.decision, levels)
        assert.equal("10", d.qtyBox.editBox.text)
        money = 30000000 -- 3,000g now: 5% of it pays for one unit at 100g
        local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
        local createRow = getUpvalue(getUpvalue(clearDeals, "refreshRows"), "createRow")
        local onBuyClick = getUpvalue(getUpvalue(createRow, "buildRowCell"), "onBuyClick")
        local createDialog = getUpvalue(getUpvalue(onBuyClick, "openDialog"), "createDialog")
        return row, d, getUpvalue(createDialog, "applyQuickFillQty")
      end

      it("quick-fills to the units the cap rule allows now", function()
        local GC = loadSniper()
        local row, d, applyQuickFillQty = armTenThenDrop(GC)

        applyQuickFillQty(100)

        assert.equal("ready", row.purchaseStage)
        assert.equal(1, row.decisionSnapshot.quantity)
        assert.equal("1", d.qtyBox.editBox.text)
        assert.equal("of 1", d.qtyOfLabel.text)
        assert.is_true(d.enabled)
      end)

      -- Review round 1: with the wallet unable to pay for even one unit at the player's price the
      -- rule allows nothing, the ceiling fell back to one, and the one was refused with the generic
      -- "live verification required". The honest reason is the wallet limit.
      it("says the wallet limit is what refuses even one unit", function()
        local GC = loadSniper()
        local row, d, applyQuickFillQty = armTenThenDrop(GC)
        money = 10000000 -- 1,000g: 5% of it is 50g, under one unit at 100g

        applyQuickFillQty(100)

        assert.equal("check", row.purchaseStage)
        assert.equal("Costs more than your per-buy wallet limit allows.", d.written[#d.written])
        assert.same({ "capital_limit" }, row.decisionSnapshot.reasons)
      end)

      -- The typed box clamps to the same ceiling (qtyBox.onCommit, built by createDialog) -- the
      -- one number both controls read, while "of N" keeps its own floor at the box.
      it("gives the typed box the same ceiling, and keeps 'of N' at the box", function()
        local GC = loadSniper()
        local row, d, applyQuickFillQty = armTenThenDrop(GC)
        local qtyMaxAvailable = getUpvalue(applyQuickFillQty, "qtyMaxAvailable")

        assert.equal(1, qtyMaxAvailable(row.deal))
        getUpvalue(getUpvalue(armReadyFn(GC), "stampDialogFromDecision"), "refreshQtyRow")()
        assert.equal("10", d.qtyBox.editBox.text)
        assert.equal("of 10", d.qtyOfLabel.text)
      end)
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

  -- In game 2026-09-23 (Void-Tempered Scales x400 at 1g10s): Buy, the quote came back and was
  -- sent to a re-check, the window went back to Check, and the next Buy on the same 400 units
  -- said "waiting for previous commodity purchase to settle" with the button lit and nothing
  -- happening. The cancelled attempt leaves a tombstone (commodity events carry no attempt id)
  -- that only an answer to a search sent after the cancel may retire -- but it was retired only
  -- by the one requery token stamped on it at the cancel, and every Check the player started
  -- afterwards carried a new token.
  describe("after a purchase attempt was cancelled", function()
    local CAP, UNIT, QTY = 11000, 9938, 400
    local starts, sends

    local function clickHandlers(GC)
      local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
      local refreshRows = getUpvalue(clearDeals, "refreshRows")
      local createRow = getUpvalue(refreshRows, "createRow")
      local buildRowCell = getUpvalue(createRow, "buildRowCell")
      local onBuyClick = getUpvalue(buildRowCell, "onBuyClick")
      local openDialog = getUpvalue(onBuyClick, "openDialog")
      local createDialog = getUpvalue(openDialog, "createDialog")
      return getUpvalue(createDialog, "onDialogPrimaryClick"), getUpvalue(createDialog, "abortRowPurchase")
    end

    local function freshBook() return { { unitPrice = UNIT, quantity = QTY } } end

    -- A cap row armed on the dialog for QTY units at UNIT, the way the owner's was.
    local function armed()
      local GC = loadSniper({ maxQuantity = QTY })
      starts, sends = 0, 0
      _G.C_AuctionHouse.StartCommoditiesPurchase = function() starts = starts + 1 end
      getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver").sendSearch = function() sends = sends + 1 end
      adoptCap(GC, 42, CAP)
      local book = freshBook()
      local live = capLive(GC, 42, book)
      local deal = boardDeal(GC, 42)
      local row = { deal = deal, purchaseToken = 1 }
      local d = armOnDialog(GC, row, deal, live.decision, book)
      local click, abort = clickHandlers(GC)
      return GC, row, deal, d, click, abort
    end

    -- The window the player opens again on the same row, before anything arms it.
    local function reopened(GC, row, deal)
      local d = fakeDialog(row, deal)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      return d
    end

    -- The search a Check sent is answered with the book as it now stands.
    local function answer(GC)
      books[42] = freshBook()
      GC.Sniper.OnCommoditySearchResults(42)
    end

    it("buys on the next Buy once a Check the player started has answered", function()
      local GC, row, _, d, click = armed()
      -- An older search for this item is still unanswered (a pre-warm the open fenced), so the
      -- re-check the quote sends has to wait for it: the window goes back to Check.
      GC.Sniper._FenceDrain(42, { itemID = 42, token = 0, sent = true })
      click() -- Buy
      assert.equal(1, starts)
      -- The server quotes above what the book showed (somebody bought the cheapest units
      -- between the Check and the click): cancelled and sent to a re-check, as it should be.
      GC.Sniper.OnCommodityPriceUpdated(UNIT + 500, (UNIT + 500) * QTY)
      assert.equal(1, cancels)
      assert.equal("check", row.purchaseStage)
      assert.equal("Check", d.label)

      click() -- Check, while the old answer is still out: waits again
      answer(GC) -- the old answer lands and is drained
      click() -- Check
      assert.equal("requerying", row.purchaseStage)
      answer(GC) -- its own answer: armed again on the same 400 units
      assert.equal("ready", row.purchaseStage)
      assert.equal(QTY, row.decisionSnapshot.quantity)

      click() -- Buy
      assert.equal(2, starts)
      assert.equal("buying", row.purchaseStage)
    end)

    it("buys on the next Buy after the player cancelled the window and opened it again", function()
      local GC, row, deal, _, click, abort = armed()
      click() -- Buy
      assert.equal(1, starts)
      abort(row, "purchase canceled") -- Cancel before the quote came back
      assert.equal(1, cancels)

      reopened(GC, row, deal)
      getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")(row, deal) -- the open's Check
      answer(GC)
      assert.equal("ready", row.purchaseStage)

      click() -- Buy
      assert.equal(2, starts)
    end)

    it("never leaves a lit Buy that does nothing while the last attempt settles", function()
      local GC, row, deal, _, click, abort = armed()
      click() -- Buy
      abort(row, "purchase canceled")
      -- Opened again and armed straight off a pre-warm the hover had already fetched: no Check
      -- of the window's own has been answered since the cancel.
      local d = reopened(GC, row, deal)
      local book = freshBook()
      armReadyFn(GC)(row, deal, capLive(GC, 42, book).decision, book)
      assert.equal("ready", row.purchaseStage)
      local before = sends

      click() -- Buy over the young tombstone: no purchase, and not a dead click either
      assert.equal(1, starts)
      assert.is_false(d.enabled)
      assert.equal("requerying", row.purchaseStage)
      assert.equal(before + 1, sends)

      answer(GC) -- that Check's answer is the proof the tombstone was waiting for
      assert.equal("ready", row.purchaseStage)
      assert.is_true(d.enabled)
      click() -- Buy
      assert.equal(2, starts)
    end)

    -- Review M2: over a CONFIRMED commodity attempt, though, a bid still waits. That purchase
    -- may already have taken the gold the bid's own affordability check can still see.
    it("holds a realm lot's bid while a confirmed commodity purchase is still owed its answer", function()
      local GC, _, _, _, click = armed()
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining",
        { itemID = 77, token = 1, confirmed = true, drainingAt = 100 })
      local bids = 0
      _G.C_AuctionHouse.PlaceBid = function() bids = bids + 1 end
      local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
        { { auctionID = 9, buyout = 8000, itemLevel = 615, quantity = 1 } })
      local lot = { itemID = 42, isCommodity = false, cap = CAP, unitPrice = 8000, qty = 1, auctionID = 9 }
      local realmRow = { deal = lot, purchaseStage = "ready", purchaseToken = 3, decisionSnapshot = decision }
      local d = reopened(GC, realmRow, lot)
      d.enabled = true

      click()

      assert.equal(0, bids)
      assert.equal("ready", realmRow.purchaseStage)
      assert.is_false(d.enabled)
    end)

    -- Review M3: a confirmed attempt is owed its answer (or the stranded release, 35 s) and a Check
    -- cannot retire it -- but Buy sat lit and refused all that while. It goes dark and says why;
    -- the purchase settling hands the player Refresh (follow-up P1, below).
    it("does not leave Buy lit while a confirmed purchase settles", function()
      local GC, row, _, d, click = armed()
      local confirmed = { itemID = 77, token = 1, confirmed = true, drainingAt = 100 }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", confirmed)
      assert.is_true(d.enabled)

      click()

      assert.equal(0, starts)
      assert.equal("ready", row.purchaseStage)
      assert.is_false(d.enabled)
      assert.equal(GC.L["waiting for previous commodity purchase to settle"], d.written[#d.written])
    end)

    -- Review M4: a Check started while a CONFIRMED tombstone is down answers and leaves it there --
    -- its late success still has to land on the attempt that paid.
    it("never retires a confirmed tombstone on a Check's answer", function()
      local GC, row, deal = armed()
      local confirmed = { itemID = 42, token = 1, confirmed = true, drainingAt = 100 }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", confirmed)

      getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")(row, deal)
      answer(GC)

      assert.equal("ready", row.purchaseStage)
      assert.is_true(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining") == confirmed)
    end)

    -- Follow-up P1 (the owner called the old version of this "a hang"): Buy went dark over a
    -- confirmed purchase and stayed dark until the quote's own 30-second expiry, although the
    -- purchase had settled within a second. The moment it settles the window offers the next
    -- step -- and that step is a Check: a quote or decision taken before that purchase landed is
    -- never spent (the gold, and for the same item the book, may have moved under it).
    describe("once the confirmed purchase it waited on settles", function()
      local WAITING = "waiting for previous commodity purchase to settle"

      -- Buy and Confirm through the real click handler and the real quote event, on `row`.
      local function confirmOn(GC, row, click)
        click() -- Buy
        GC.Sniper.OnCommodityPriceUpdated(UNIT, UNIT * QTY)
        assert.equal("confirm", row.purchaseStage)
        click() -- Confirm
        assert.equal(1, confirms)
        assert.equal("confirming", row.purchaseStage)
      end

      it("offers Refresh at once, and Refresh runs a Check, never a purchase", function()
        local GC, row, _, d, click = armed()
        setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining",
          { itemID = 77, token = 1, confirmed = true, drainingAt = 100 })
        click() -- Buy over the confirmed purchase: dark, waiting
        assert.is_false(d.enabled)

        GC.Sniper.OnCommodityPurchaseSucceeded()

        assert.equal("expired", row.purchaseStage)
        assert.is_true(d.enabled)
        assert.equal(GC.L["Refresh"], d.label)
        assert.equal(GC.L["previous commodity purchase settled -- %s to re-check the price"]
          :format(GC.L["Refresh"]:upper()), d.written[#d.written])
        local before = sends
        click() -- Refresh
        assert.equal(0, starts)
        assert.equal("requerying", row.purchaseStage)
        assert.equal(before + 1, sends)
        answer(GC)
        click() -- Buy, on the Check the player just ran
        assert.equal(1, starts)
      end)

      -- Fix round 1, nit 2: the line names the button by what it reads -- REFRESH in English,
      -- AKTUALISIEREN in German -- not by an English word no translated button shows.
      it("names the button the way the button itself reads, in the player's language", function()
        local GC, _, _, d, click = armed()
        helper.loadModule("Locale/deDE.lua", GC)
        GC.ActivateLocale("deDE")
        setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining",
          { itemID = 77, token = 1, confirmed = true, drainingAt = 100 })
        click()

        GC.Sniper.OnCommodityPurchaseSucceeded()

        assert.is_truthy(d.written[#d.written]:find("AKTUALISIEREN", 1, true), d.written[#d.written])
        GC.ActivateLocale(nil)
      end)

      it("does the same when the purchase fails", function()
        local GC, row, _, d, click = armed()
        setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining",
          { itemID = 77, token = 1, confirmed = true, drainingAt = 100 })
        click()

        GC.Sniper.OnCommodityPurchaseFailed()

        assert.equal("expired", row.purchaseStage)
        assert.is_true(d.enabled)
        click()
        assert.equal(0, starts)
        assert.equal("requerying", row.purchaseStage)
      end)

      it("does the same when the stranded release gives up on it", function()
        local GC, row, _, d, click = armed()
        local confirmed = { itemID = 77, token = 1, confirmed = true, drainingAt = 100 }
        setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining", confirmed)
        click()

        GC.Sniper._ReleaseStrandedConfirmed(confirmed)

        assert.equal("expired", row.purchaseStage)
        assert.is_true(d.enabled)
      end)

      -- The owner's sequence: Confirm, the window closed with Esc while the purchase is still
      -- confirming (Cancel is disabled there, Escape is not), the next row's window opened and
      -- armed. Its Buy -- and a realm lot's bid alike -- used to answer "finish the pending buy
      -- first" on a lit button, over a purchase that may already have taken the gold.
      it("holds the next window over a purchase still confirming, then hands it Refresh", function()
        local GC, first, _, d, click, abort = armed()
        confirmOn(GC, first, click)
        d.row = nil -- Escape: the window closes, the confirmed purchase stays owed
        abort(first, "purchase canceled")

        local lot = { itemID = 42, isCommodity = true, cap = CAP, unitPrice = UNIT, qty = QTY }
        local book = freshBook()
        local second = { deal = lot, purchaseToken = 1 }
        local d2 = armOnDialog(GC, second, lot, capLive(GC, 42, book).decision, book)
        -- Waiting from the moment it arms (fix round 1, minor 2), not a lit "click Buy".
        assert.equal("ready", second.purchaseStage)
        assert.is_false(d2.enabled)
        assert.equal(WAITING, d2.written[#d2.written])
        click()
        assert.equal(1, starts)
        assert.is_false(d2.enabled)
        assert.equal(WAITING, d2.written[#d2.written])

        GC.Sniper.OnCommodityPurchaseSucceeded()

        assertRecordedCapBuy(GC, 42, QTY, UNIT * QTY) -- the first purchase, booked
        assert.equal("expired", second.purchaseStage)
        assert.is_true(d2.enabled)
        assert.equal(GC.L["Refresh"], d2.label)
        click()
        assert.equal(1, starts)
        assert.equal("requerying", second.purchaseStage)
      end)

      -- The same row, opened again after Escape and armed by its own Check: the old gate let its
      -- Buy through, a second Start replaced the confirmed attempt, and the first purchase's
      -- success was then read as the answer to the new one -- and never booked.
      it("does not start a second purchase on the same row while its first is owed", function()
        local GC, first, deal, d, click, abort = armed()
        confirmOn(GC, first, click)
        d.row = nil
        abort(first, "purchase canceled")
        reopened(GC, first, deal)
        getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")(first, deal)
        answer(GC)
        assert.equal("ready", first.purchaseStage)

        click()
        assert.equal(1, starts)

        GC.Sniper.OnCommodityPurchaseSucceeded()
        assertRecordedCapBuy(GC, 42, QTY, UNIT * QTY)
        assert.equal("expired", first.purchaseStage)
      end)

      -- Fix round 1, minor 3: that first purchase lands after its row was taken over, so it is
      -- settled detached -- and was reported "bought 400 x item 42 after AH close" with the
      -- auction house open the whole time.
      it("reports the first purchase as bought, not as bought after an AH close", function()
        local GC, first, deal, d, click, abort = armed()
        setUpvalue(GC.Sniper.IsAHOpen, "ahOpen", true)
        confirmOn(GC, first, click)
        d.row = nil
        abort(first, "purchase canceled")
        reopened(GC, first, deal)
        getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")(first, deal)
        answer(GC)

        GC.Sniper.OnCommodityPurchaseSucceeded()

        assert.equal(GC.L["bought %d x item %d"]:format(QTY, 42), GC.Sniper.detachedCommodityStatus[42].note)
      end)

      it("still says after AH close for a purchase the auction house closed on", function()
        local GC, first, _, _, click = armed()
        setUpvalue(GC.Sniper.IsAHOpen, "ahOpen", true)
        confirmOn(GC, first, click)
        getUpvalue(GC.Sniper.OnAuctionHouseClosed, "resetAllPurchases")() -- carried across the close
        -- ...and the auction house opened again before the answer came.

        GC.Sniper.OnCommodityPurchaseSucceeded()

        assert.equal(GC.L["bought %d x item %d after AH close"]:format(QTY, 42),
          GC.Sniper.detachedCommodityStatus[42].note)
      end)

      it("holds a realm lot's bid the same way, and its next click is a Check", function()
        local GC, first, _, d, click, abort = armed()
        confirmOn(GC, first, click)
        d.row = nil
        abort(first, "purchase canceled")
        local bids = 0
        _G.C_AuctionHouse.PlaceBid = function() bids = bids + 1 end
        local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
          { { auctionID = 9, buyout = 8000, itemLevel = 615, quantity = 1 } })
        local lot = { itemID = 42, isCommodity = false, cap = CAP, unitPrice = 8000, qty = 1, auctionID = 9 }
        local realmRow = { deal = lot, purchaseStage = "ready", purchaseToken = 3, decisionSnapshot = decision }
        local d2 = reopened(GC, realmRow, lot)
        d2.enabled = true
        click()
        assert.equal(0, bids)
        assert.is_false(d2.enabled)

        GC.Sniper.OnCommodityPurchaseSucceeded()
        assert.equal("expired", realmRow.purchaseStage)
        assert.is_true(d2.enabled)
        click()

        assert.equal(0, bids)
        assert.equal("requerying", realmRow.purchaseStage)
      end)

      -- Fix round 2: one rule for both windows that can start a commodity purchase -- nothing
      -- starts while a purchase either of them confirmed is still owed its answer
      -- (GC.PurchaseSlot.ConfirmOwed). The Sniper's side of it, and the two things it tells the
      -- BUY tab: its claim is re-stamped at Confirm, and its settle repaints the tab.
      describe("across the BUY tab", function()
        it("holds a window over a purchase the BUY tab confirmed, then hands it Refresh", function()
          local GC, row, deal, d, click = armed()
          helper.loadModule("Core/PurchaseSlot.lua", GC)
          local buyOwed = true
          GC.Buy = { ConfirmOwed = function() return buyOwed end, RefreshIfShown = function() end }
          GC.PurchaseSlot.Claim("buy")
          local book = freshBook()
          armReadyFn(GC)(row, deal, capLive(GC, 42, book).decision, book) -- a Check lands now

          assert.is_false(d.enabled)
          assert.equal(WAITING, d.written[#d.written])
          click()
          assert.equal(0, starts)
          assert.is_false(d.enabled)

          buyOwed = false -- BUY's purchase has its answer
          GC.PurchaseSlot.Release("buy")
          GC.Sniper._TickOwedHold()
          assert.equal("expired", row.purchaseStage)
          assert.is_true(d.enabled)
          click() -- Refresh: a Check
          assert.equal(0, starts)
          assert.equal("requerying", row.purchaseStage)
        end)

        -- The hand-off above rides the auction house's 0.25 s ticker: BUY's terminal paths hand
        -- nothing to this window. Pinned at the source, as caps_stop_and_open_spec pins its drain.
        it("is handed off by the auction house ticker", function()
          local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
          local src = f:read("*a")
          f:close()
          local start = src:find("autoScanTicker = autoScanTicker or C_Timer.NewTicker(", 1, true)
          assert.is_number(start)
          local body = src:sub(start, src:find("\n  end)\n", start, true))
          assert.is_truthy(body:find("GC.Sniper._TickOwedHold()", 1, true))
        end)

        it("re-stamps its slot claim at Confirm, so the claim lives as long as the wait", function()
          local GC, row, _, _, click = armed()
          helper.loadModule("Core/PurchaseSlot.lua", GC)
          local clock = 100
          _G.GetTime = function() return clock end
          click() -- Buy: claimed at 100
          assert.equal("sniper", GC.PurchaseSlot.Owner())
          GC.Sniper.OnCommodityPriceUpdated(UNIT, UNIT * QTY)
          clock = 125
          click() -- Confirm
          assert.equal("confirming", row.purchaseStage)
          assert.is_true(GC.PurchaseSlot.IsBusy(150)) -- 25 s after Confirm, 50 s after Start
        end)

        it("repaints the BUY tab when its confirmed purchase is answered", function()
          local GC, row, _, _, click = armed()
          local refreshed = 0
          GC.Buy = { RefreshIfShown = function() refreshed = refreshed + 1 end }
          confirmOn(GC, row, click)

          GC.Sniper.OnCommodityPurchaseSucceeded()

          assert.is_true(refreshed > 0)
        end)
      end)

      -- Fix round 1, minor 1: the server may answer a Confirm with a new quote -- the price moved
      -- between the quote and the click, nothing was bought, and Blizzard's own dialog asks for
      -- another click. After Escape there is no window to click it from. The attempt used to be
      -- left un-confirmed and re-armed with no window: the next window stayed dark to its own
      -- expiry and then answered "finish the pending buy first" on a lit Buy, and on the same row
      -- reopened the attempt stayed "confirmed" until the stranded release reported a purchase
      -- that never happened. It is cancelled now, and whoever waited on it is handed Refresh.
      describe("when the server re-quotes a purchase whose window was closed", function()
        local DROPPED = "price changed after you closed the buy window -- nothing was bought"

        it("cancels it and hands the next window Refresh", function()
          local GC, first, _, d, click, abort = armed()
          confirmOn(GC, first, click)
          d.row = nil -- Escape
          abort(first, "purchase canceled")
          local lot = { itemID = 42, isCommodity = true, cap = CAP, unitPrice = UNIT, qty = QTY }
          local book = freshBook()
          local second = { deal = lot, purchaseToken = 1 }
          local d2 = armOnDialog(GC, second, lot, capLive(GC, 42, book).decision, book)
          assert.is_false(d2.enabled)

          GC.Sniper.OnCommodityPriceUpdated(UNIT - 10, (UNIT - 10) * QTY) -- still under the cap

          assert.equal(1, cancels)
          assert.equal(1, confirms) -- never confirmed again
          assert.is_nil(first.purchaseStage) -- the closed window's row is let go
          assert.is_nil(getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase"))
          assert.is_false(GC.Sniper.HasStrandedConfirmed())
          assert.equal(0, GC.Sniper.session.buys)
          assert.equal(GC.L[DROPPED], GC.Sniper.detachedCommodityStatus[42].note)
          assert.equal("expired", second.purchaseStage)
          assert.is_true(d2.enabled)
          click() -- Refresh: a Check
          assert.equal(1, starts)
          answer(GC)
          click() -- Buy
          assert.equal(2, starts)
        end)

        -- Fix round 2: the other side of the rule, and the path it must never take. With the window
        -- still open at "confirming", a re-quote is that window's to show: nothing is cancelled,
        -- Confirm is offered again at the new price, and a second Confirm books the purchase.
        it("leaves a purchase its own open window is confirming to that window", function()
          local GC, row, _, d, click = armed()
          confirmOn(GC, row, click)

          GC.Sniper.OnCommodityPriceUpdated(UNIT - 10, (UNIT - 10) * QTY)

          assert.equal(0, cancels)
          assert.equal("confirm", row.purchaseStage)
          assert.is_true(d.row == row)
          assert.is_true(d.enabled)
          click() -- Confirm, again
          assert.equal(2, confirms)
          assert.equal("confirming", row.purchaseStage)
          GC.Sniper.OnCommodityPurchaseSucceeded()
          assertRecordedCapBuy(GC, 42, QTY, (UNIT - 10) * QTY)
        end)

        it("does not leave the same row, opened again, behind a purchase that never happened", function()
          local GC, first, deal, d, click, abort = armed()
          confirmOn(GC, first, click)
          local pending = getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityPurchase")
          d.row = nil
          abort(first, "purchase canceled")
          reopened(GC, first, deal)
          getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")(first, deal)
          answer(GC)
          assert.equal("ready", first.purchaseStage)

          GC.Sniper.OnCommodityPriceUpdated(UNIT - 10, (UNIT - 10) * QTY)

          assert.equal(1, cancels)
          assert.is_false(GC.Sniper.HasStrandedConfirmed())
          assert.equal("expired", first.purchaseStage)
          GC.Sniper._ReleaseStrandedConfirmed(pending) -- its 35-second timer, later
          assert.equal(GC.L[DROPPED], GC.Sniper.detachedCommodityStatus[42].note)
          assert.equal(0, GC.Sniper.session.buys)
          click() -- Refresh: a Check
          answer(GC)
          click() -- Buy
          assert.equal(2, starts)
        end)
      end)

      -- Fix round 1, minor 2: a window armed over a confirmed purchase still owed its answer said
      -- "price confirmed -- click Buy to purchase" on a lit, green Buy -- which the owner reads as
      -- ready -- and only the click turned it dark. It waits from the moment it arms.
      describe("a window armed while that purchase is still owed", function()
        local function owed(GC)
          setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining",
            { itemID = 77, token = 1, confirmed = true, drainingAt = 100 })
        end

        it("waits up front, and says so, rather than offering a Buy the click refuses", function()
          local GC = loadSniper({ maxQuantity = QTY })
          adoptCap(GC, 42, CAP)
          owed(GC)
          local book = freshBook()
          local live = capLive(GC, 42, book)
          local deal = boardDeal(GC, 42)
          local row = { deal = deal, purchaseToken = 1 }

          local d = armOnDialog(GC, row, deal, live.decision, book)

          assert.equal("ready", row.purchaseStage)
          assert.is_false(d.enabled)
          assert.equal(WAITING, d.written[#d.written])
        end)

        it("keeps waiting after the player picks another quantity", function()
          local GC = loadSniper({ maxQuantity = QTY })
          adoptCap(GC, 42, CAP)
          owed(GC)
          local book = freshBook()
          local live = capLive(GC, 42, book)
          local deal = boardDeal(GC, 42)
          local row = { deal = deal, purchaseToken = 1 }
          local d = armOnDialog(GC, row, deal, live.decision, book)
          local clearDeals = getUpvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
          local createRow = getUpvalue(getUpvalue(clearDeals, "refreshRows"), "createRow")
          local onBuyClick = getUpvalue(getUpvalue(createRow, "buildRowCell"), "onBuyClick")
          local createDialog = getUpvalue(getUpvalue(onBuyClick, "openDialog"), "createDialog")
          local applyQuickFillQty = getUpvalue(createDialog, "applyQuickFillQty")

          getUpvalue(applyQuickFillQty, "applyChosenQty")(row, 100) -- typed
          assert.equal(100, row.decisionSnapshot.quantity)
          assert.is_false(d.enabled)
          assert.equal(WAITING, d.written[#d.written])

          applyQuickFillQty(50) -- a quick-fill button
          assert.is_false(d.enabled)
          assert.equal(WAITING, d.written[#d.written])
        end)

        it("waits for a realm lot at the player's price the same way", function()
          local GC = loadSniper()
          adoptCap(GC, 42, CAP)
          owed(GC)
          local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
            { { auctionID = 9, buyout = 8000, itemLevel = 615, quantity = 1 } })
          local lot = { itemID = 42, isCommodity = false, cap = CAP, unitPrice = 8000, qty = 1, auctionID = 9 }
          local realmRow = { deal = lot, purchaseStage = "requerying", purchaseToken = 3 }
          local d = fakeDialog(realmRow, lot)
          setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
          local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")

          getUpvalue(finishRequery, "applyRequeryResult")(realmRow, 42, { isCommodity = false, decision = decision })

          assert.equal("ready", realmRow.purchaseStage)
          assert.is_false(d.enabled)
          assert.equal(WAITING, d.written[#d.written])
        end)

        -- Fix round 2 (nit): only a Buy that would otherwise be lit waits. A window that cannot be
        -- bought whatever happens to the other purchase says why -- not enough gold, the wallet
        -- limit -- instead of "waiting", which would only hand it a Refresh to find out.
        describe("that could not be bought anyway", function()
          local function realmArmed(GC, buyout)
            local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
              { { auctionID = 9, buyout = buyout, itemLevel = 615, quantity = 1 } })
            local lot = { itemID = 42, isCommodity = false, cap = CAP, unitPrice = buyout, qty = 1, auctionID = 9 }
            local realmRow = { deal = lot, purchaseStage = "requerying", purchaseToken = 3 }
            local d = fakeDialog(realmRow, lot)
            setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
            local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
            getUpvalue(finishRequery, "applyRequeryResult")(realmRow, 42, { isCommodity = false, decision = decision })
            return d
          end

          it("says a commodity costs more gold than the player has", function()
            local GC = loadSniper({ maxQuantity = QTY })
            adoptCap(GC, 42, CAP)
            owed(GC)
            local book = freshBook()
            local live = capLive(GC, 42, book)
            local deal = boardDeal(GC, 42)
            money = 1000 -- the gold went on something else since the Check
            local d = armOnDialog(GC, { deal = deal, purchaseToken = 1 }, deal, live.decision, book)

            assert.is_false(d.enabled)
            assert.is_truthy(d.written[#d.written]:find("not enough gold", 1, true), d.written[#d.written])
          end)

          it("says a realm lot costs more gold than the player has", function()
            local GC = loadSniper()
            adoptCap(GC, 42, CAP)
            owed(GC)
            money = 5000
            local d = realmArmed(GC, 8000)

            assert.is_false(d.enabled)
            assert.is_truthy(d.written[#d.written]:find("not enough gold", 1, true), d.written[#d.written])
          end)

          it("says a realm lot costs more than the player's wallet limit", function()
            local GC = loadSniper()
            adoptCap(GC, 42, 1000000)
            owed(GC)
            money = 10000000 -- 1,000g: the 5% limit is 50g, under an 80g lot
            local d = realmArmed(GC, 800000)

            assert.is_false(d.enabled)
            assert.equal("Costs more than your per-buy wallet limit allows.", d.written[#d.written])
          end)
        end)

        it("does not light a held Buy when its hold ends", function()
          local GC = loadSniper()
          adoptCap(GC, 42, CAP)
          owed(GC)
          local timers = {}
          _G.C_Timer.After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end
          -- A YOUR PRICE row whose Check found only a lot above the price: Buy is held a moment.
          local candidate = { auctionID = 10, buyout = CAP * 2, quantity = 1, itemLevel = 615 }
          local decision = { status = "WATCH", reasons = { "realm_item_unverified" }, quantity = 1,
            entryTotal = CAP * 2, entryUnitDisplay = CAP * 2, candidate = candidate }
          local lot = { itemID = 42, isCommodity = false, cap = CAP, unitPrice = 8000, qty = 1,
            auctionID = 3, stale = true }
          local realmRow = { deal = lot, purchaseStage = "requerying", purchaseToken = 3 }
          local d = fakeDialog(realmRow, lot)
          setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
          local finishRequery = getUpvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
          getUpvalue(finishRequery, "applyRequeryResult")(realmRow, 42, { isCommodity = false, decision = decision })

          for _, timer in ipairs(timers) do
            if timer.seconds == 1.5 then timer.fn() end
          end

          assert.equal("ready", realmRow.purchaseStage)
          assert.is_false(d.enabled)
          assert.equal(WAITING, d.written[#d.written])
        end)
      end)

      -- Armed while the purchase was owed and not clicked yet: its decision predates the
      -- purchase all the same, so it is not the one a Buy may spend.
      it("turns a Buy armed before the purchase settled into Refresh, clicked or not", function()
        local GC, row, _, d = armed()
        setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining",
          { itemID = 77, token = 1, confirmed = true, drainingAt = 100 })
        assert.is_true(d.enabled)

        GC.Sniper.OnCommodityPurchaseSucceeded()

        assert.equal("expired", row.purchaseStage)
        assert.equal(GC.L["Refresh"], d.label)
      end)

      it("leaves a window that is not armed exactly as it is", function()
        local GC, row, deal, d = armed()
        setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "commodityDraining",
          { itemID = 77, token = 1, confirmed = true, drainingAt = 100 })
        getUpvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")(row, deal) -- a Check in flight
        local label = d.label

        GC.Sniper.OnCommodityPurchaseSucceeded()

        assert.equal("requerying", row.purchaseStage)
        assert.equal(label, d.label)
      end)
    end)

    -- The tombstone guards the commodity events; a realm lot's bid answers on its own.
    it("does not hold a realm lot's bid behind a commodity attempt still settling", function()
      local GC, row, _, _, click, abort = armed()
      click()
      abort(row, "purchase canceled")
      local bids = 0
      _G.C_AuctionHouse.PlaceBid = function() bids = bids + 1 end
      local decision = GC.Caps.DecideRealm(GC.Caps.For(42),
        { { auctionID = 9, buyout = 8000, itemLevel = 615, quantity = 1 } })
      local lot = { itemID = 42, isCommodity = false, cap = CAP, unitPrice = 8000, qty = 1, auctionID = 9 }
      local realmRow = { deal = lot, purchaseStage = "ready", purchaseToken = 3, decisionSnapshot = decision }
      reopened(GC, realmRow, lot)

      click()

      assert.equal(1, bids)
      assert.equal("buying", realmRow.purchaseStage)
    end)
  end)
end)
