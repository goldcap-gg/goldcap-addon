require("spec.spec_helper")

-- WoW: Forever beta, 3c (the owner's Shadowgem "Below vendor" Buy, build 1.60.1.70009): three
-- Buy clicks, each blocked, each logged as
--
--   Execution tainted by GoldCap while reading field lastOn (<table>)
--       UI/SniperFrame.lua refreshVerifyButton() <- the auction house's 0.25 s ticker
--   An action was blocked because of taint from GoldCap - StartCommoditiesPurchase()
--       UI/SniperFrame.lua onDialogPrimaryClick
--
-- The taint the click was blocked for was picked up by a DIFFERENT execution -- the ticker --
-- and reached the click through state the ticker writes and the click reads before its
-- protected call. spec/forever_clean_click_runtime_spec.lua cannot see that: it watches what a
-- click CALLS, and the click called nothing new. This file models the part of the client's taint
-- engine the log shows at work:
--
--   * every top-level entry (a timer's tick, a click, an event) starts clean;
--   * reading a table field that a tainted execution wrote taints the reader, and the taint it
--     carries is the one that field was written under (so the log names where it began);
--   * every field a tainted execution writes carries its taint on to whoever reads it next;
--   * a protected call made while the execution is tainted is blocked.
--
-- It tracks the tables the ticker and the purchase clicks share: GC.Sniper, GC.Buy, the shared
-- purchase slot (its state is upvalues, so its functions stand in for the field reads and
-- writes), the toolbar's buttons, and the buy window, its row, deal and decision. Then it
-- drives the real ticker and the real click handlers against it.
describe("A tainted auction house ticker never reaches a purchase click", function()
  local function upvalue(fn, wanted)
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

  -- The model. `exec` is the running execution's taint (nil = clean); `blocked` collects every
  -- protected call made while it was not.
  local model

  local function newModel()
    local m = { exec = nil, calls = {} }
    local backing = setmetatable({}, { __mode = "k" })
    local marks = setmetatable({}, { __mode = "k" })
    local fallbacks = setmetatable({}, { __mode = "k" })
    local meta = {
      __index = function(proxy, key)
        local taint = marks[proxy][key]
        if taint ~= nil and m.exec == nil then
          m.exec = taint
          m.via = tostring(key) -- the field this execution picked the taint up from
        end
        local value = backing[proxy][key]
        if value == nil and fallbacks[proxy] then return fallbacks[proxy](proxy, key) end
        return value
      end,
      __newindex = function(proxy, key, value)
        backing[proxy][key] = value
        marks[proxy][key] = m.exec
      end,
      __pairs = function(proxy) return next, backing[proxy], nil end,
      __len = function(proxy) return #backing[proxy] end,
    }

    -- Puts `tbl`'s fields behind a watched proxy and returns the proxy: every reference that
    -- should be watched must be the proxy from here on.
    -- `fallback(proxy, key)` answers a key the table does not hold (a frame's C-side methods),
    -- untracked, the way a real frame's metatable does.
    function m.track(tbl, fallback)
      local proxy = setmetatable({}, meta)
      backing[proxy], marks[proxy], fallbacks[proxy] = tbl, {}, fallback
      return proxy
    end

    function m.taintOf(proxy, key) return marks[proxy][key] end

    -- The unknown first cause: a field some earlier tainted execution wrote.
    function m.seed(proxy, key, taint)
      assert(marks[proxy], "not a tracked table")
      marks[proxy][key] = taint
    end

    -- A module whose state lives in upvalues (Core/PurchaseSlot.lua): its readers and writers
    -- stand in for the field accesses.
    function m.trackState(module, readers, writers)
      local stateTaint
      for _, name in ipairs(readers) do
        local real = module[name]
        local isWriter = false
        for _, w in ipairs(writers) do if w == name then isWriter = true end end
        module[name] = function(...)
          if stateTaint ~= nil and m.exec == nil then
            m.exec = stateTaint
            m.via = "GC.PurchaseSlot." .. name
          end
          local result = real(...) -- each of these answers one value
          if isWriter then stateTaint = m.exec end
          return result
        end
      end
    end

    -- One top-level entry: the client starts every script, timer and event clean.
    function m.entry(fn, ...)
      m.exec, m.via = nil, nil
      fn(...)
      local taint = m.exec
      m.exec = nil
      return taint
    end

    -- An entry that is tainted from its first line, whatever did it.
    function m.taintedEntry(taint, fn, ...)
      m.exec = taint
      fn(...)
      m.exec = nil
    end

    function m.protect(api, name)
      local real = api[name]
      api[name] = function(...)
        m.calls[#m.calls + 1] = { name = name, taint = m.exec, via = m.via }
        if real then return real(...) end
      end
    end

    return m
  end

  local function assertCalledClean(name)
    local seen
    for _, call in ipairs(model.calls) do
      if call.name == name then seen = call end
    end
    assert.is_not_nil(seen, name .. " was never called -- the click bought nothing")
    assert.is_nil(seen.taint, ("%s ran in an execution tainted by %s, picked up reading %s: the client blocks it")
      :format(name, tostring(seen.taint), tostring(seen.via)))
  end

  -- A frame double, and every one of them watched by the model: every Capitalised key is a
  -- no-op method unless named below, every other key a plain field -- so `frame.autoBtn` reads
  -- nil until someone sets it, the way a real frame table does.
  local stubFrame
  local METHODS = {
    SetScript = function(self, name, fn) self.scripts[name] = fn end,
    GetScript = function(self, name) return self.scripts[name] end,
    HookScript = function(self, name, fn)
      local scripts = self.scripts
      local prev = scripts[name]
      scripts[name] = function(...)
        if prev then prev(...) end
        return fn(...)
      end
    end,
    Show = function(self)
      self.shown = true
      local onShow = self.scripts.OnShow
      if onShow then onShow(self) end
    end,
    Hide = function(self)
      self.shown = false
      local onHide = self.scripts.OnHide
      if onHide then onHide(self) end
    end,
    IsShown = function(self) return self.shown == true end,
    IsVisible = function(self) return self.shown == true end,
    SetText = function(self, text) self.text = text end,
    GetText = function(self) return self.text or "" end,
    GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
    IsEnabled = function() return true end,
    HasFocus = function() return false end,
    GetChecked = function() return false end,
    GetFrameStrata = function() return "MEDIUM" end,
    GetFrameLevel = function() return 1 end,
    CreateFontString = function() return stubFrame() end,
    CreateTexture = function() return stubFrame() end,
    CreateAnimationGroup = function() return stubFrame() end,
    CreateAnimation = function() return stubFrame() end,
    IsPlaying = function() return false end,
  }
  local ZERO = { GetWidth = true, GetHeight = true, GetStringWidth = true,
    GetUnboundedStringWidth = true, GetStringHeight = true, GetVerticalScroll = true,
    GetVerticalScrollRange = true, GetValue = true, GetNumPoints = true, GetScale = true,
    GetEffectiveScale = true, GetLeft = true, GetRight = true, GetTop = true, GetBottom = true }
  -- A capitalised key that is not a method is a child region (ScrollBar, TitleText): nil.
  local VERBS = { "Set", "Get", "Is", "Has", "Can", "Create", "Enable", "Disable", "Register",
    "Unregister", "Clear", "Start", "Stop", "Play", "Lock", "Unlock", "Raise", "Lower", "Adjust",
    "Update", "Refresh", "Insert", "Highlight", "Unhighlight", "Resume", "Pause", "Restart" }
  local function noop() end
  local function zero() return 0 end
  local function frameMethod(_, key)
    if METHODS[key] then return METHODS[key] end
    if ZERO[key] then return zero end
    if type(key) ~= "string" then return nil end
    for _, verb in ipairs(VERBS) do
      if key:sub(1, #verb) == verb then return noop end
    end
    return nil
  end
  stubFrame = function()
    return model.track({ scripts = {}, shown = false }, frameMethod)
  end

  -- The clocks OnAuctionHouseShow starts, in the order it starts them: the auction house ticker
  -- (`tick`, the one the beta's log caught tainted), then the purchase clock and, in WoW: Forever,
  -- the board clock (`tickers.purchase`, `tickers.board`; absent before the round 1 fix).
  local GC, frame, tick, tickers

  -- One quarter-second of every clock: the auction house ticker first, under `taint` if given,
  -- then the others, each its own clean execution as the client runs them.
  local function quarterSecond(taint)
    if taint then model.taintedEntry(taint, tick) else model.entry(tick) end
    if tickers.purchase then model.entry(tickers.purchase) end
    if tickers.board then model.entry(tickers.board) end
  end

  local function loadClient(retail)
    model = newModel()
    local frames = {}
    _G.CreateFrame = function(_, name)
      local f = stubFrame()
      frames[#frames + 1] = f
      if name and name ~= "" then _G[name] = f end
      return f
    end
    _G.GetBuildInfo = retail and function() return "12.0.7", "64000", "Sep 1 2026", 120007 end
      or function() return "1.60.1", "70009", "Sep 1 2026", 16001 end
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    _G.hooksecurefunc = function() end
    _G.GetTime = function() return 100 end
    _G.time = function() return 100000 end
    _G.GetMoney = function() return 10000000000 end
    _G.PlaySound = function() end
    _G.SOUNDKIT = { MAP_PING = 3175, RAID_WARNING = 1, READY_CHECK = 3 }
    _G.C_CurrencyInfo = { GetCoinTextureString = function(copper) return tostring(copper) .. "c" end }
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function(_, itemID)
      return {
        ContinueOnItemLoad = function(_, cb) cb() end,
        GetItemIcon = function() return "icon:" .. tostring(itemID) end,
        GetItemQuality = function() return nil end,
        GetItemName = function() return "Item " .. tostring(itemID) end,
      }
    end }
    local ticks = {}
    _G.C_Timer = {
      After = function() end,
      NewTicker = function(_, fn)
        ticks[#ticks + 1] = fn
        return { Cancel = function() end }
      end,
    }
    _G.C_AuctionHouse = {
      CalculateCommodityDeposit = function() return 0 end,
      CancelCommoditiesPurchase = function() end,
      ConfirmCommoditiesPurchase = function() end,
      StartCommoditiesPurchase = function() end,
      PlaceBid = function() end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      HasFullBrowseResults = function() return false end,
      GetNumCommoditySearchResults = function() return 0 end,
      GetCommoditySearchResultInfo = function() return nil end,
      SendBrowseQuery = function() end,
      IsThrottledMessageSystemReady = function() return true end,
    }

    GC = {}
    local toc = assert(io.open(retail and "GoldCap/GoldCap.toc" or "GoldCap/GoldCap_Camelot.toc", "r"))
    for rawLine in toc:lines() do
      local line = rawLine:gsub("%s+$", "")
      if line ~= "" and not line:match("^##") and not line:match("^#") then
        local chunk, err = loadfile("GoldCap/" .. line:gsub("\\", "/"))
        assert(chunk, err)
        chunk("GoldCap", GC)
      end
    end
    toc:close()

    GC.Print = function() end -- chat lines are not what this is about
    -- ADDON_LOADED, as the client fires it: builds GC.db from GoldCapDB.
    for _, f in ipairs(frames) do
      local onEvent = f.scripts.OnEvent
      if onEvent then onEvent(f, "ADDON_LOADED", "GoldCap") end
    end
    assert(GC.db, "ADDON_LOADED did not build GC.db")

    GC.Sniper.Toggle()
    frame = _G.GoldCapSniperFrame
    assert(frame and frame.verifyBtn, "no Deals window was built")
    GC.Sniper.OnAuctionHouseShow()
    assert.is_true(#ticks >= 1, "OnAuctionHouseShow did not start the auction house ticker")
    tick = ticks[1]
    tickers = { purchase = ticks[2], board = ticks[3] }

    -- Watched from here on, beside every frame: the tables the ticker and the clicks share.
    GC.Sniper = model.track(GC.Sniper)
    GC.Buy = model.track(GC.Buy)
    model.trackState(GC.PurchaseSlot, { "Claim", "Release", "Owner", "IsBusy" }, { "Claim", "Release" })
    for _, name in ipairs({ "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase", "PlaceBid" }) do
      model.protect(_G.C_AuctionHouse, name)
    end
    return GC
  end

  local function loadForever() return loadClient(false) end

  after_each(function()
    for _, name in ipairs({ "CreateFrame", "GoldCapSniperFrame", "GoldCapAuctionHouseDock",
      "UISpecialFrames", "SlashCmdList", "C_AddOns", "SLASH_GOLDCAP1", "SLASH_GOLDCAP2",
      "hooksecurefunc", "GetTime", "GetMoney", "PlaySound", "SOUNDKIT", "C_Timer", "C_CurrencyInfo",
      "ITEM_QUALITY_COLORS", "Item", "GoldCapDB", "GetBuildInfo", "C_AuctionHouse" }) do
      _G[name] = nil
    end
    _G.time = os.time
  end)

  -- The buy window, as spec/forever_clean_click_runtime_spec.lua's fakeDialog builds it: the
  -- fields the click reads, doubles for the calls it makes.
  local function recorder()
    local w = { text = "" }
    function w:SetText(t) self.text = t end
    for _, name in ipairs({ "SetTextColor", "Show", "Hide", "ClearAllPoints", "SetPoint", "SetHeight" }) do
      w[name] = function() end
    end
    function w:GetStringHeight() return 24 end
    return w
  end

  local function buyWindow(row, deal)
    local d = { row = row, deal = deal, written = {}, enabled = false, height = 0, baseHeight = 400 }
    d.primaryBtn = {
      Disable = function() d.enabled = false end,
      Enable = function() d.enabled = true end,
      IsEnabled = function() return d.enabled end,
      SetLabel = function(_, text) d.label = text end,
      text = { SetTextColor = function() end },
    }
    d.cancelBtn = { Enable = function() end, Disable = function() end, SetLabel = function() end }
    d.status = { SetText = function(_, text) d.written[#d.written + 1] = text end,
      SetTextColor = function() end, ClearAllPoints = function() end, SetPoint = function() end }
    d.banner = { shown = false,
      Hide = function(self) self.shown = false end, Show = function(self) self.shown = true end,
      IsShown = function(self) return self.shown end,
      head = { SetText = function() end }, detail = { SetText = function() end } }
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
    for _, name in ipairs({ "ClearFocus", "EnableMouse", "SetTextColor" }) do editBox[name] = function() end end
    d.qtyBox = { editBox = editBox, Show = function() end, Hide = function() end }
    d.quickFillBtns = {}
    return model.track(d)
  end

  -- A Below vendor commodity, as the Deals board lists it, and the ceiling its Check is held to
  -- (GC.ForeverDeals.CeilingFor): 55 units at or under 12c on a book whose vendor pays 13c.
  local BOOK = { { unitPrice = 8, quantity = 5 }, { unitPrice = 9, quantity = 10 },
    { unitPrice = 12, quantity = 40 }, { unitPrice = 13, quantity = 100 } }

  local function useCeiling(itemID, ceilingUnit, exitUnit)
    GC.ForeverDeals.CeilingFor = function(id)
      if id ~= itemID then return nil end
      return { ceilingUnit = ceilingUnit, kind = "vendor", exitUnit = exitUnit, minimumProfit = 20 }
    end
    GC.ForeverDeals.Drop = function() end
  end

  local function belowVendorDeal(itemID, isCommodity)
    return model.track({ itemID = itemID, isCommodity = isCommodity, forever = "vendor", ceiling = 12,
      refUnit = 13, unitPrice = 8, qty = 55, capTotal = 610, profit = 105, estProfit = 105, stale = true })
  end

  local function clickHandler()
    local clearDeals = upvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals")
    local refreshRows = upvalue(clearDeals, "refreshRows")
    local createRow = upvalue(refreshRows, "createRow")
    local buildRowCell = upvalue(createRow, "buildRowCell")
    local onBuyClick = upvalue(buildRowCell, "onBuyClick")
    local openDialog = upvalue(onBuyClick, "openDialog")
    local createDialog = upvalue(openDialog, "createDialog")
    return upvalue(createDialog, "onDialogPrimaryClick")
  end

  -- A Check that came back buyable, armed on the buy window: the Deals row's Buy, lit. All of it
  -- in clean entries -- the Check's own answer is an event.
  local function armedCommodity()
    loadForever()
    useCeiling(42, 12, 13)
    setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function() end,
      commodityBook = function() return BOOK end,
      commodityResult = function() return { avail = 1 } end,
      itemResult = function() return {} end,
      itemLots = function() return {} end,
      onStatus = function() end,
    })
    local deal = belowVendorDeal(42, true)
    local row = model.track({ deal = deal, purchaseToken = 1 })
    local d = buyWindow(row, deal)
    model.entry(function()
      local live = upvalue(GC.Sniper.OnCommoditySearchResults, "evaluateLiveCommodityDeal")(42, BOOK)
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = upvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      local armReady = upvalue(upvalue(finishRequery, "applyRequeryResult"), "armReady")
      armReady(row, deal, live.decision, BOOK)
    end)
    assert.equal("ready", row.purchaseStage)
    assert.is_true(d.enabled)
    return row, d, clickHandler()
  end

  local function armedLot()
    loadForever()
    useCeiling(42, 99, 100)
    local decision = GC.SniperDecision.EvaluateCeilingLot({ ceilingUnit = 99, kind = "vendor",
      exitUnit = 100, lots = { { auctionID = 9, buyout = 60, quantity = 1, itemLevel = 18 } },
      minimumProfit = 20 })
    local deal = belowVendorDeal(42, false)
    local row = model.track({ deal = deal, purchaseStage = "requerying" })
    local d = buyWindow(row, deal)
    model.entry(function()
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog", d)
      local finishRequery = upvalue(GC.Sniper.OnCommoditySearchResults, "finishRequery")
      upvalue(finishRequery, "applyRequeryResult")(row, 42, { isCommodity = false, decision = decision })
    end)
    assert.equal("ready", row.purchaseStage)
    assert.is_true(d.enabled)
    return row, d, clickHandler()
  end

  -- What the beta's log named: the HIDDEN button's remembered on/off, read by the ticker.
  local function seedTheLoggedField()
    model.seed(frame.verifyBtn, "lastOn", "verifyBtn.lastOn")
  end

  describe("the chain the beta logged: a toolbar field some other execution tainted", function()
    it("Start (StartCommoditiesPurchase)", function()
      local _, _, click = armedCommodity()
      seedTheLoggedField()
      quarterSecond()
      model.entry(click)
      assertCalledClean("StartCommoditiesPurchase")
    end)

    it("Confirm (ConfirmCommoditiesPurchase)", function()
      local row, _, click = armedCommodity()
      model.entry(click) -- Start
      model.entry(GC.Sniper.OnCommodityPriceUpdated, 11, 610)
      assert.equal("confirm", row.purchaseStage)
      seedTheLoggedField()
      quarterSecond()
      model.entry(click)
      assertCalledClean("ConfirmCommoditiesPurchase")
    end)

    it("PlaceBid", function()
      local _, _, click = armedLot()
      seedTheLoggedField()
      quarterSecond()
      model.entry(click)
      assertCalledClean("PlaceBid")
    end)
  end)

  -- Review F1 (round 1): a ticker that is not quiet. On Forever the Deals board is rebuilt while
  -- vendor prices load, and a caps stop-and-open opens the buy window by itself; both wrote,
  -- from inside the ticker, the row, the deal and the window a Buy click reads first. Driven here
  -- through the real board, the real row click, the real buy window and its real Buy button.
  describe("a ticker tainted from its first line, and busy", function()
    local LINEN = 2589

    -- Reads the spec makes itself are not an execution of the addon's: forget what they touched.
    local function look(fn)
      local value = fn()
      model.exec, model.via = nil, nil
      return value
    end

    local function foreverBoard()
      loadForever()
      local vendor
      local fold = { at = 5000, items = { [LINEN] = "8,355,5,;0x5 1x10 3x40 1x100 2x200" } }
      GC.ForeverScan.Enabled = function() return true end
      GC.ForeverScan.Fold = function() return fold end
      GC.ForeverValue.VendorUnit = function() return vendor end
      GC.ForeverValue.DepositUnit = function() return nil end
      GC.db.commodityByItem = GC.db.commodityByItem or {}
      GC.db.commodityByItem[LINEN] = true
      _G.C_Item = { RequestLoadItemDataByID = function() end }
      setUpvalue(GC.Sniper.OnCommodityPriceUpdated, "driver", {
        isReady = function() return true end,
        claimSend = function() return true end,
        getKeyInfo = function() return { isCommodity = true } end,
        sendSearch = function() end,
        commodityBook = function() return BOOK end,
        commodityResult = function() return { avail = 1 } end,
        itemResult = function() return {} end,
        itemLots = function() return {} end,
        onStatus = function() end,
      })
      model.entry(GC.Sniper.OnForeverFold) -- the scan's own repaint: no vendor price yet, no row
      vendor = 13 -- the client has loaded it since, and a rebuild is due
      _G.time = function() return 100010 end
      return GC
    end

    local function boardRow()
      return look(function()
        local refreshRows = upvalue(upvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals"), "refreshRows")
        for _, row in ipairs(upvalue(refreshRows, "rows")) do
          if row.deal and row.deal.itemID == LINEN then return row end
        end
      end)
    end

    local function onBuyClick()
      local refreshRows = upvalue(upvalue(GC.Sniper.OnAuctionHouseClosed, "clearDeals"), "refreshRows")
      return upvalue(upvalue(upvalue(refreshRows, "createRow"), "buildRowCell"), "onBuyClick")
    end

    -- The Check's answer (an event: a background check's search still out for the same item
    -- answers first, then the window's own), then the buy window's own Buy button.
    local function checkAndBuy()
      local d = look(function() return upvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog") end)
      for _ = 1, 6 do
        local stage = look(function() return d.row.purchaseStage end)
        if stage == "ready" then break end
        model.entry(GC.Sniper.OnCommoditySearchResults, LINEN) -- whichever search is out answers
        if look(function() return d.row.purchaseStage end) == "check" then
          -- Held behind the background check's search: the player presses Check again.
          model.entry(look(function() return d.primaryBtn.scripts.OnClick end), d.primaryBtn)
        end
        quarterSecond() -- a clean quarter: a parked send goes out
      end
      assert.equal("ready", look(function() return d.row.purchaseStage end))
      model.entry(look(function() return d.primaryBtn.scripts.OnClick end), d.primaryBtn)
      assertCalledClean("StartCommoditiesPurchase")
    end

    it("while vendor prices load and the board is rebuilt: row click, Check, Buy", function()
      foreverBoard()
      quarterSecond("the ticker")
      -- A minute on, with the row on the board: the tainted ticker's background check walks it.
      _G.GetTime = function() return 160 end
      quarterSecond("the ticker")
      local row = boardRow()
      assert.is_not_nil(row, "the board never listed the Below vendor row")
      model.entry(onBuyClick(), row)
      checkAndBuy()
    end)

    it("with a caps stop-and-open waiting: the window opens itself, Check, Buy", function()
      foreverBoard()
      quarterSecond() -- the board lists the row
      local row = boardRow()
      assert.is_not_nil(row)
      look(function()
        GC.db.settings.sniper.capStopAndOpen = true
        GC.Caps.IsNews = function() return true end
        GC.Caps.Announce = function() return true end
        GC.Sniper._BoardCapRow = function(deal) return deal end
        GC.Sniper._RowOnScreen = function() return true end
        GC.Sniper._QueueCapPing(row.deal)
      end)
      quarterSecond("the ticker") -- the open
      local d = look(function() return upvalue(GC.Sniper.OnCommodityPriceUpdated, "dialog") end)
      assert.is_not_nil(d, "stop-and-open opened no window")
      checkAndBuy()
    end)
  end)

  -- The ticker itself: the first thing the log showed was the ticker picking the taint up from a
  -- field the toolbar keeps between paints. Whatever wrote those, a tick must not read them.
  describe("the ticker", function()
    it("stays clean when what the toolbar remembers between paints was tainted", function()
      loadForever()
      for _, button in ipairs({ frame.autoBtn, frame.verifyBtn, frame.fullScanBtn }) do
        for _, key in ipairs({ "lastOn", "lastText", "lastBusy" }) do model.seed(button, key, "toolbar " .. key) end
      end
      for _, chip in pairs(frame.boardChips) do
        model.seed(chip, "lastOn", "chip lastOn")
        model.seed(chip, "lastText", "chip lastText")
      end
      assert.is_nil(model.entry(tick))
    end)

    -- And whatever a toolbar button carries, the repaints come last in a tick: nothing the
    -- ticker writes for the purchase path runs after a read of a button.
    it("writes the purchase path's state before it repaints the toolbar", function()
      loadForever()
      for _, button in ipairs({ frame.autoBtn, frame.verifyBtn, frame.fullScanBtn }) do
        for key in pairs(button) do model.seed(button, key, "a toolbar button") end
      end
      model.entry(tick)
      assert.is_nil(model.taintOf(GC.Sniper, "_lastOwed"))
      assert.is_nil(model.taintOf(GC.Sniper, "_keysPokeAt"))
      assert.is_nil(model.taintOf(GC.Buy, "_lastWaiting"))
    end)
  end)

  -- Round 1: the auction house ticker keeps nothing that writes a Buy click's state. Pinned at
  -- the source as well as by the runs above, since a line added back to its body is all it takes.
  describe("the clocks", function()
    local function body(src, head)
      local start = assert(src:find(head, 1, true), head)
      -- Comments blanked: only code counts.
      return (src:sub(start, src:find("\n  end)\n", start, true)):gsub("%-%-[^\n]*", ""))
    end

    it("keeps the board, the purchase path and BUY's lines off the auction house ticker", function()
      local f = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
      local src = f:read("*a")
      f:close()
      local tickBody = body(src, "autoScanTicker = autoScanTicker or C_Timer.NewTicker(")
      for _, name in ipairs({ "_TickCapPings", "_TickOwedHold", "_TickConfirmCountdown", "TickCountdown",
        "OnForeverFold", "ForeverDeals", "RefreshIfShown", "refreshRows" }) do
        assert.is_nil(tickBody:find(name, 1, true), name .. " is back on the auction house ticker")
      end
      local purchaseBody = body(src, "GC.Sniper._purchaseTicker = GC.Sniper._purchaseTicker or C_Timer.NewTicker(")
      for _, name in ipairs({ "GC.Sniper._TickCapPings()", "GC.Sniper._TickOwedHold()",
        "GC.Sniper._TickConfirmCountdown()", "GC.Buy.TickCountdown()" }) do
        assert.is_truthy(purchaseBody:find(name, 1, true), name .. " left the purchase clock")
      end
    end)

    it("starts the board clock in WoW: Forever only", function()
      loadForever()
      assert.is_function(tickers.purchase)
      assert.is_function(tickers.board)
    end)

    -- One build serves both games: retail keeps the purchase clock (caps stop-and-open, the BUY
    -- hand-off, both countdowns -- the same work at the same cadence) and has no board clock.
    it("on retail: the purchase clock, and no board clock", function()
      loadClient(true)
      assert.is_function(tickers.purchase)
      assert.is_nil(tickers.board)
    end)

    -- A render no longer paints the toolbar (refreshRows); the ticker does, every tick, and the
    -- HIDDEN toggle's own click repaints at once.
    it("on retail: the ticker paints HIDDEN and the board chips, the toggle repaints at once", function()
      loadClient(true)
      frame.verifyBtn.label = "stale"
      frame.boardChips.items.label = "stale"
      quarterSecond()
      assert.equal("HIDDEN 0", frame.verifyBtn.label)
      assert.equal("ITEMS", frame.boardChips.items.label)
      frame.verifyBtn.scripts.OnClick()
      assert.equal("REFUSED 0", frame.verifyBtn.label)
    end)
  end)

  -- The BUY tab's Start/Confirm click (UI/BuyFrame.lua onBuyClick) asks owedElsewhere before its
  -- protected call; the ticker asks the same questions four times a second.
  describe("the BUY tab's purchase guard", function()
    local function owedElsewhere()
      local container = upvalue(GC.Buy.Show, "container")
      local onBuyClick = upvalue(container.scripts.OnKeyDown, "onBuyClick")
      return upvalue(onBuyClick, "owedElsewhere")
    end

    it("reads nothing a tainted ticker wrote", function()
      loadForever()
      local guard = owedElsewhere()
      quarterSecond("the ticker")
      assert.is_nil(model.entry(guard))
    end)

    it("reads nothing the logged chain wrote", function()
      loadForever()
      local guard = owedElsewhere()
      seedTheLoggedField()
      quarterSecond()
      assert.is_nil(model.entry(guard))
    end)
  end)

  -- /gc taint: the owner's in-game check of the fields above, from the client's own answer.
  describe("/gc taint", function()
    it("names each field's taint from issecurevariable and changes nothing", function()
      loadForever()
      local printed = {}
      GC.Print = function(text) printed[#printed + 1] = text end
      _G.issecure = function() return false end
      _G.issecurevariable = function(_, key)
        if key == "_lastOwed" then return false, "GoldCap" end
        return true, nil
      end
      local before = model.taintOf(GC.Sniper, "_lastOwed")
      GC.slashHandlers.taint()
      _G.issecure, _G.issecurevariable = nil, nil
      assert.equal("taint: this command itself runs TAINTED", printed[1])
      assert.equal("taint: GC.Sniper._lastOwed (ticker) TAINTED by GoldCap", printed[2])
      assert.equal("taint: GC.Buy._owedUntil secure", printed[7])
      assert.equal(before, model.taintOf(GC.Sniper, "_lastOwed"))
    end)
  end)

  -- Whatever taints the ticker next -- a field this spec has not thought of -- the clicks must
  -- not read what it writes before their protected call.
  describe("a ticker tainted from its first line", function()
    it("Start (StartCommoditiesPurchase)", function()
      local _, _, click = armedCommodity()
      quarterSecond("the ticker")
      model.entry(click)
      assertCalledClean("StartCommoditiesPurchase")
    end)

    it("Confirm (ConfirmCommoditiesPurchase)", function()
      local row, _, click = armedCommodity()
      model.entry(click) -- Start
      model.entry(GC.Sniper.OnCommodityPriceUpdated, 11, 610)
      assert.equal("confirm", row.purchaseStage)
      quarterSecond("the ticker")
      model.entry(click)
      assertCalledClean("ConfirmCommoditiesPurchase")
    end)

    it("PlaceBid", function()
      local _, _, click = armedLot()
      quarterSecond("the ticker")
      model.entry(click)
      assertCalledClean("PlaceBid")
    end)
  end)
end)
