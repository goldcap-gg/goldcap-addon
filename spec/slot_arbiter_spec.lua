local helper = require("spec.spec_helper")

describe("Search slot arbiter", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end
  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local sent
  -- Sniper phase 2: the browse buffer's own "settled" flag. False by default, which is what
  -- keeps a page perpetually pending for the paging tests below AND what refuses a keys call
  -- while a pass owns the buffer; the keys tests flip it.
  local fullResults

  local function load()
    sent = {}
    fullResults = false
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    -- The book pass now owns what used to be the bare pendingBrowsePage/sendBrowsePage
    -- upvalues this spec poked directly -- RequestMoreBrowseResults is its own "a page sent"
    -- signal, and HasFullBrowseResults staying false is what keeps a page perpetually pending
    -- until the test arms one with armPage() below.
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() sent[#sent + 1] = "page" end,
      HasFullBrowseResults = function() return fullResults end,
      GetBrowseResults = function() return {} end,
      MakeItemKey = function(itemID) return { itemID = itemID } end,
      SearchForItemKeys = function(keys) sent[#sent + 1] = "keys:" .. #keys end,
    }
    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 }, tier = { WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 }, fgMuted = { 0.72, 0.71, 0.69 } } },
      AutoScan = { New = function() return { Input = function() end, State = function() return "OFF" end,
        PauseReasons = function() return {} end, Tick = function() end } end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end },
      Scanner = { New = function() return {} end },
      Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end },
      SniperDecision = { Evaluate = function() return {} end, MarketFromValue = function() return {} end,
        ReasonText = function(t) return tostring(t) end },
      -- The book pass's onRows driver callback runs the real streaming pipeline on every
      -- results event (even an empty tail), so these four need real no-op shapes, not an
      -- empty table -- this spec only cares about slot arbitration, never about deals.
      FullScan = {
        RowsFromBrowse = function() return {} end,
        EvaluateDelta = function() return {}, 0, 0 end,
        CollectNewHot = function() return {} end,
        MergeDeals = function(existing) return existing end,
        -- The key poll's fold caps its own store with this (0.9.2's two boards).
        CapDeals = function(deals) return deals end,
      },
      WatchSet = { Observe = function() end, Select = function() return {} end },
      Print = function() end,
      -- board = "items": the key poll only spends a slot while the board it fills is the one
      -- on screen (0.9.2), and every keys test below is about what it does when it may run.
      -- The refusal on the other board has its own test, in spec/key_poll_wiring_spec.lua.
      db = { settings = { sniper = { sound = false, board = "items" } } },
    }
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    -- A fake watch scanner whose only job is to record that it was handed a slot.
    local watch = { hungry = true }
    function watch:Wants() return self.hungry end
    function watch:OnSystemReady() sent[#sent + 1] = "watch" end
    GC.Sniper.scanner = watch
    -- Starts a real book pass so GC.Sniper._bookPass:IsPaging() is true and its own
    -- OnThrottleReady() has something to arbitrate. Start only ARMS the pass now, so the
    -- opening query is spent here the way startFullScan's own poke spends it -- the send
    -- itself doesn't touch `sent` (SendBrowseQuery is a bare stub), only
    -- RequestMoreBrowseResults does.
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper._bookPass:OnThrottleReady()
    return GC, watch
  end

  -- Arms a pending page the same way a real OnBrowseResultsAdded would: HasFullBrowseResults
  -- stays false (stubbed above), so this always leaves the book pass wanting one more page.
  local function armPage(GC)
    GC.Sniper._bookPass:OnResultsUpdated()
  end

  after_each(function()
    _G.GetTime, _G.time, _G.C_Timer, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.C_AuctionHouse = nil
  end)

  -- The BUY tab asks this before it books a late success of its own (UI/BuyFrame.lua's
  -- mayOwnTerminal): with a stranded confirm on both sides the event is nobody's to take. Same
  -- ten-minute window as takeStrandedConfirmed, and read-only -- asking must not consume.
  describe("HasStrandedConfirmed", function()
    it("is false with nothing stranded, and true inside the window", function()
      local GC = load()
      assert.is_false(GC.Sniper.HasStrandedConfirmed())
      GC.Sniper._strandedConfirmed[7] = { pending = {}, at = 100 - 599 }
      assert.is_true(GC.Sniper.HasStrandedConfirmed())
      assert.is_true(GC.Sniper.HasStrandedConfirmed())
      assert.is_truthy(GC.Sniper._strandedConfirmed[7])
    end)

    it("is false once the record has aged out", function()
      local GC = load()
      GC.Sniper._strandedConfirmed[7] = { pending = {}, at = 100 - 601 }
      assert.is_false(GC.Sniper.HasStrandedConfirmed())
    end)

    -- The other direction of the same fail-closed rule (review item 2). With a stranded confirm
    -- on BOTH sides and nothing owning the flow, a terminal event carries nothing that could say
    -- whose purchase it answers: the Sniper booking its record on a success would put a
    -- goldcap_sniper row on the site for a buy that may well have been BUY's, and dropping it on
    -- a failure would leave the NEXT success free to be taken by whichever window asked first.
    it("keeps its own record while the BUY tab holds a stranded confirm too", function()
      local GC = load()
      GC.Buy = { HasStranded = function() return true end }

      GC.Sniper._strandedConfirmed[7] = { pending = { itemID = 7 }, at = 100 }
      GC.Sniper.OnCommodityPurchaseSucceeded()
      assert.is_truthy(GC.Sniper._strandedConfirmed[7])
      GC.Sniper.OnCommodityPurchaseFailed()
      assert.is_truthy(GC.Sniper._strandedConfirmed[7])
      GC.Sniper.OnCommodityPriceUnavailable()
      assert.is_truthy(GC.Sniper._strandedConfirmed[7])

      -- ...and retires it as usual the moment BUY has nothing of its own to attribute.
      GC.Buy = { HasStranded = function() return false end }
      GC.Sniper.OnCommodityPurchaseFailed()
      assert.is_nil(GC.Sniper._strandedConfirmed[7])
    end)
  end)

  -- Browse paging and the tail (watch loop + verify walk) alternate. Paging used to win
  -- outright, which in the client meant it won always: with Auto on, the pass is pending again
  -- within its two-second breather, so the rows on screen were never judged at all until Auto
  -- was switched off.
  it("alternates the slot between browse paging and the watch loop when both want it", function()
    local GC = load() -- watch.hungry is true by default
    for _ = 1, 4 do
      armPage(GC)
      GC.Sniper.OnThrottleReady()
    end
    assert.same({ "page", "watch", "page", "watch" }, sent)
  end)

  it("leaves no slot idle when only one consumer is hungry", function()
    local GC, watch = load()
    watch.hungry = false
    for _ = 1, 3 do
      armPage(GC)
      GC.Sniper.OnThrottleReady()
    end
    assert.same({ "page", "page", "page" }, sent)

    watch.hungry = true
    -- No armPage() this time: nothing is pending, so browse's turn is skipped and watch's
    -- own hunger is what wins the next two slots instead.
    GC.Sniper.OnThrottleReady()
    GC.Sniper.OnThrottleReady()
    assert.same({ "page", "page", "page", "watch", "watch" }, sent)
  end)

  it("stands the watch loop down when the Deals view is not on screen, so Sell isn't starved", function()
    local GC = load()
    set(GC.Sniper.OnThrottleReady, "view", "sell")
    -- No armPage(): the book pass has nothing pending, so this isolates the watch-vs-idle
    -- question from the (now unconditional) browse-paging priority covered above.
    for _ = 1, 3 do
      GC.Sniper.OnThrottleReady()
    end
    -- With the watch loop stood down, no slot goes to "watch", and none are left idle for
    -- GC.Sell.OnThrottleReady to starve on next.
    assert.same({}, sent)

    set(GC.Sniper.OnThrottleReady, "view", "deals")
    GC.Sniper.OnThrottleReady()
    assert.same({ "watch" }, sent) -- watch resumes once Deals is back up
  end)

  it("gives a parked Check the slot ahead of both", function()
    local GC = load()
    local searched = {}
    set(GC.Sniper.OnThrottleReady, "driver", { isReady = function() return true end,
      sendSearch = function(id) searched[#searched + 1] = id end })
    local attempt = { itemID = 42, token = 1, row = {}, deal = { itemID = 42 } }
    upvalue(GC.Sniper.OnThrottleReady, "pendingRequerySend")[42] = attempt
    set(GC.Sniper.OnThrottleReady, "isCurrentRequeryAttempt", function() return true end)

    GC.Sniper.OnThrottleReady()
    assert.same({ 42 }, searched)
    assert.same({}, sent)
  end)

  it("only lets the watch loop send inside its own grant", function()
    local GC = load()
    local mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan
    assert.is_function(mayScan)
    assert.is_false(mayScan())            -- outside a grant

    local seenInside
    GC.Sniper.scanner.OnSystemReady = function() seenInside = mayScan() end
    GC.Sniper._GrantWatchSlot()
    assert.is_true(seenInside)            -- inside its grant
    assert.is_false(mayScan())            -- and closed again straight after
  end)

  -- Confirmed live 2026-08-18: the watch loop's polls kept firing while the player tried to
  -- click Create Auction in Blizzard's own default sell panel, burning the same shared
  -- throttle budget and turning every click into "You're doing that too fast". PlayerIsBusy is
  -- the single predicate this gate reads now -- posting, buying a browse result, or reading
  -- their own search all vetoe the grant the same way.
  it("keeps the watch loop's grant closed while the player is busy, even mid-grant", function()
    local GC = load()
    local mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan
    GC.AuctionHouseTab = { PlayerIsBusy = function() return true end }

    local seenInside
    GC.Sniper.scanner.OnSystemReady = function() seenInside = mayScan() end
    GC.Sniper._GrantWatchSlot()
    assert.is_false(seenInside)          -- the grant window opens, but being busy still vetoes it

    GC.AuctionHouseTab.PlayerIsBusy = function() return false end
    GC.Sniper._GrantWatchSlot()
    assert.is_true(seenInside)           -- and resumes the moment the player is no longer busy
  end)

  it("does not wedge the gate open when the scanner throws", function()
    local GC = load()
    local mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan
    GC.Sniper.scanner.OnSystemReady = function() error("scanner blew up") end
    GC.Sniper._GrantWatchSlot()
    assert.is_false(mayScan())
  end)

  -- Owner-reported: "confirming purchase..." sat for 5-10s on a busy board. The confirm call
  -- itself is instant; what was slow was the throttled search SLOT, still being handed to
  -- drill-downs/the book pass/the watch loop/the verify walk while the purchase waited on its
  -- terminal event. A purchase in flight opens the quiet zone (GC.Sniper.IsPurchaseQuiet).
  it("sends nothing while a purchase is in flight, and serves again once it resolves", function()
    local GC = load()
    armPage(GC) -- book pass has a page pending and would otherwise win outright
    local row = { purchaseStage = "buying" }
    set(GC.Sniper._QuietZoneOpen, "rows", { row })

    for _ = 1, 3 do
      GC.Sniper.OnThrottleReady()
    end
    assert.same({}, sent)

    row.purchaseStage = nil
    GC.Sniper.OnThrottleReady()
    assert.same({ "page" }, sent) -- the parked page still wants sending, and is free to now
  end)

  -- The quiet zone, stage by stage. "check", "expired", "frozen" and "ready" are rows the
  -- player is READING -- nothing of ours is outstanding at the server for them -- and the board
  -- has to keep working underneath. "frozen" is the one that stopped the board for good before
  -- this: resolvePurchase pins a server success with no final quote (activeItemID,
  -- deliberately, for the rest of the AH session) so the row cannot be repooled, and the old
  -- `next(activeItemID) ~= nil` veto read that display pin as a purchase and refused every
  -- search until the auction house closed.
  it("is quiet for the stages a purchase is actually in flight for, and no others", function()
    local GC = load()
    local row = {}
    set(GC.Sniper._QuietZoneOpen, "rows", { row })

    for _, stage in ipairs({ "requerying", "buying", "confirm", "requote", "confirming" }) do
      row.purchaseStage = stage
      assert.is_true(GC.Sniper.IsPurchaseQuiet(), stage .. " must be quiet")
    end
    for _, stage in ipairs({ "check", "expired", "frozen", "ready" }) do
      row.purchaseStage = stage
      assert.is_false(GC.Sniper.IsPurchaseQuiet(), stage .. " must not be quiet")
    end
    row.purchaseStage = nil
    assert.is_false(GC.Sniper.IsPurchaseQuiet())

    -- A commodity attempt owns the client's single commodity flow whether or not any row is
    -- still pinned to its item, so either tombstone holds the zone open on its own.
    set(GC.Sniper._QuietZoneOpen, "commodityPurchase", { itemID = 42 })
    assert.is_true(GC.Sniper.IsPurchaseQuiet())
    set(GC.Sniper._QuietZoneOpen, "commodityPurchase", nil)
    set(GC.Sniper._QuietZoneOpen, "commodityDraining", { itemID = 42 })
    assert.is_true(GC.Sniper.IsPurchaseQuiet())
    set(GC.Sniper._QuietZoneOpen, "commodityDraining", nil)
    assert.is_false(GC.Sniper.IsPurchaseQuiet())
  end)

  -- The Sell tab's quote walk (UI/SellFrame.lua's advanceQuote) stands down on exactly this
  -- predicate, and an armed dialog used to be enough to stop it -- so a quote left on screen
  -- froze the board and parked the Sell tab on "Waiting for the purchase to finish…" for the
  -- whole 30-second arm window, over a purchase nobody had made. An armed quote has nothing
  -- outstanding at the auction house, and the Buy click spends from the decision snapshot the
  -- Check already took, never from the client's search buffer -- so nothing a background
  -- search does can reach it.
  it("does not stop the Sell walk for a quote that is only waiting on the player", function()
    local GC = load()
    local row = { purchaseStage = "ready" }
    set(GC.Sniper._QuietZoneOpen, "dialog", { row = row })
    assert.is_false(GC.Sniper.IsSearchCritical())

    row.purchaseStage = "buying" -- the purchase call has gone out: now it is in flight
    assert.is_true(GC.Sniper.IsSearchCritical())
  end)

  -- The veto has to be bounded, or it is the same board freeze one layer down: an "Internal
  -- auction error" fires NONE of the three commodity terminal events, so the attempt that
  -- raised it would own the search slot for the rest of the session.
  describe("bounded veto", function()
    local function clockAt(seconds)
      _G.GetTime = function() return seconds end
    end

    it("releases a stuck attempt after 30 seconds and returns its row to Check", function()
      local GC = load()
      local status = {}
      local row = { purchaseStage = "buying", deal = { itemID = 42, isCommodity = true },
        purchaseDeal = { itemID = 42, isCommodity = true } }
      set(GC.Sniper._QuietZoneOpen, "rows", { row })
      set(GC.Sniper.OnCommodityPriceUpdated, "frame",
        { status = { SetText = function(_, text) status[#status + 1] = text end } })
      -- This example is about the STATE the release leaves behind; the re-render it ends with
      -- needs the whole window built, which this headless harness deliberately does not have.
      set(GC.Sniper._ReleaseQuietZone, "refreshRows", function() end)
      local cancels = 0
      _G.C_AuctionHouse.CancelCommoditiesPurchase = function() cancels = cancels + 1 end
      set(GC.Sniper._QuietZoneOpen, "commodityPurchase", { row = row, itemID = 42, token = 1 })

      clockAt(100)
      assert.is_true(GC.Sniper.IsPurchaseQuiet()) -- the clock starts on the first look
      clockAt(125)
      assert.is_true(GC.Sniper.IsPurchaseQuiet()) -- still inside the window

      clockAt(131)
      assert.is_false(GC.Sniper.IsPurchaseQuiet())
      assert.equal("check", row.purchaseStage)
      assert.is_nil(upvalue(GC.Sniper._QuietZoneOpen, "commodityPurchase"))
      assert.equal(1, cancels) -- an opened server session is settled, not abandoned
      assert.is_truthy(status[#status]:find("Check again", 1, true))

      -- And the board is serving again on the very next slot.
      armPage(GC)
      GC.Sniper.OnThrottleReady()
      assert.same({ "page" }, sent)
    end)

    it("keeps the zone while the dialog is on screen, however long it has been open", function()
      local GC = load()
      local row = { purchaseStage = "confirm", deal = { itemID = 42 } }
      set(GC.Sniper._QuietZoneOpen, "rows", { row })
      set(GC.Sniper._QuietZoneOpen, "dialog", { row = row, IsShown = function() return true end })

      clockAt(100)
      assert.is_true(GC.Sniper.IsPurchaseQuiet())
      clockAt(400)
      assert.is_true(GC.Sniper.IsPurchaseQuiet())
      assert.equal("confirm", row.purchaseStage)
    end)

    -- Gold may have moved. A confirmed attempt keeps its row and its tombstone until a
    -- terminal event or GC.Sniper._ReleaseStrandedConfirmed settles it -- releasing it here
    -- would free the row for a retry that buys the same lot twice.
    it("never releases a confirmed attempt or the row it owns", function()
      local GC = load()
      local row = { purchaseStage = "confirming", deal = { itemID = 42 } }
      local confirmed = { row = row, itemID = 42, token = 1, confirmed = true }
      set(GC.Sniper._QuietZoneOpen, "rows", { row })
      set(GC.Sniper._QuietZoneOpen, "commodityDraining", confirmed)

      clockAt(100)
      assert.is_true(GC.Sniper.IsPurchaseQuiet())
      clockAt(200)
      assert.is_true(GC.Sniper.IsPurchaseQuiet())
      assert.equal("confirming", row.purchaseStage)
      assert.is_true(upvalue(GC.Sniper._QuietZoneOpen, "commodityDraining") == confirmed)

      -- Once its own release has dropped the tombstone, the next window frees the row.
      set(GC.Sniper._QuietZoneOpen, "commodityDraining", nil)
      clockAt(300)
      assert.is_false(GC.Sniper.IsPurchaseQuiet())
      assert.equal("check", row.purchaseStage)
    end)
  end)

  it("keeps serving the board while a frozen row holds its display pin", function()
    local GC = load()
    -- Exactly what resolvePurchase's frozen branch leaves behind: the row pinned by itemID,
    -- for the rest of the session, with no attempt in flight anywhere.
    set(GC.Sniper._QuietZoneOpen, "rows", { { purchaseStage = "frozen" } })
    -- The pin itself, on the shared upvalue every purchase-flow function reads.
    set(upvalue(GC.Sniper.OnThrottleReady, "maybeStartPrewarm"), "activeItemID", { [12345] = true })

    armPage(GC)
    GC.Sniper.OnThrottleReady()
    assert.same({ "page" }, sent)
  end)

  -- A parked Check requery is step 1, ahead of the purchase-in-flight veto -- it is the
  -- player's own click and has already stopped the loop as a courtesy, purchase or not.
  it("still lets a parked Check requery through while a purchase is in flight", function()
    local GC = load()
    local searched = {}
    set(GC.Sniper.OnThrottleReady, "driver", { isReady = function() return true end,
      sendSearch = function(id) searched[#searched + 1] = id end })
    local attempt = { itemID = 42, token = 1, row = {}, deal = { itemID = 42 } }
    upvalue(GC.Sniper.OnThrottleReady, "pendingRequerySend")[42] = attempt
    set(GC.Sniper.OnThrottleReady, "isCurrentRequeryAttempt", function() return true end)
    set(GC.Sniper._QuietZoneOpen, "rows", { { purchaseStage = "buying" } })

    GC.Sniper.OnThrottleReady()
    assert.same({ 42 }, searched)
    assert.same({}, sent)
  end)

  -- Sniper phase 2 (the realm-item key poll). A keys call REPLACES the browse buffer, so the
  -- one rule that makes it safe is that it never runs while a pass owns that buffer.
  describe("key poll", function()
    local function targets(GC, first, last)
      local ids = {}
      for id = first, last do ids[#ids + 1] = id end
      GC.Sniper._keyPoll:SetTargets(ids)
    end

    -- Simulates the browse event a sent batch answers on, so the next grant is free to send
    -- the following one.
    local function foldKeys(GC)
      GC.Sniper.OnBrowseResults()
    end

    it("sends no keys call while the book pass is paging", function()
      local GC = load()
      targets(GC, 1, 3)
      armPage(GC)
      GC.Sniper.OnThrottleReady()
      assert.same({ "page" }, sent)
    end)

    it("sends no keys call while a pass is about to fetch the browse buffer", function()
      local GC, watch = load()
      watch.hungry = false
      targets(GC, 1, 3)
      GC.Sniper._bookPass:Abort() -- not paging any more...
      GC.Sniper._bookPass:Start("wide") -- ...but a pass is parked on the next grant: its page
      -- is what the buffer is about to hold, so it is not ours to replace. (A buffer that is
      -- merely EMPTY -- the auction house opened straight onto the Items board -- is fair game;
      -- HasFullBrowseResults() used to gate this and kept that board empty for good.)
      GC.Sniper.OnThrottleReady()
      for _, what in ipairs(sent) do assert.is_nil(what:match("^keys")) end
    end)

    it("spends the gap between passes on one batch per grant, 100 keys at a time", function()
      local GC, watch = load()
      watch.hungry = false
      GC.Sniper._bookPass:Abort()
      fullResults = true
      targets(GC, 1, 250)

      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:100" }, sent)
      -- A second grant while the first batch is still unanswered sends nothing: one batch is
      -- outstanding at a time, and its rows are what the next fold reads.
      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:100" }, sent)

      foldKeys(GC)
      GC.Sniper.OnThrottleReady()
      foldKeys(GC)
      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:100", "keys:100", "keys:50" }, sent)

      -- The cycle has now visited every target once. Nothing more goes out until a fresh pass
      -- calls BeginCycle -- the loop is one pass plus one visit each, not keys forever.
      foldKeys(GC)
      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:100", "keys:100", "keys:50" }, sent)

      -- A fresh pass is what re-arms it: startFullScan calls BeginCycle, and the poll starts
      -- handing out batches again from where its cursor stopped.
      GC.Sniper._keyPoll:BeginCycle()
      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:100", "keys:100", "keys:50", "keys:100" }, sent)
    end)

    it("lets a queued drill-down go first, and does not drop a hit only the key poll saw", function()
      local GC, watch = load()
      watch.hungry = false
      GC.Sniper._bookPass:Abort()
      fullResults = true
      targets(GC, 1, 3)
      -- The key poll has seen item 42 at 900; the book pass never has. The arbiter used to ask
      -- only the book pass whether a queued hit was still live, which dropped every realm hit
      -- before it could be drilled.
      GC.Sniper._keyPoll:Fold({ { itemKey = { itemID = 42 }, minPrice = 900, totalQuantity = 1 } })
      GC.Sniper._drillQueue:Push({ itemID = 42, floor = 900, estProfit = 1 })
      set(GC.Sniper.OnThrottleReady, "canDrillNow", function() return true end)
      set(GC.Sniper.OnThrottleReady, "maybeStartPrewarm", function()
        sent[#sent + 1] = "drill"
        return true
      end)

      GC.Sniper.OnThrottleReady()
      assert.same({ "drill" }, sent)
      -- With the queue drained, the same slot's successor goes to the keys batch.
      GC.Sniper.OnThrottleReady()
      assert.same({ "drill", "keys:3" }, sent)
    end)

    -- Both replace the client's ONE browse buffer, and both answer on the same browse events.
    -- A page sent under an outstanding batch is folded into the poll, not into the pass: the
    -- pass loses the page it was waiting for, and the fold -- reading the page as the batch's
    -- own answer -- deletes every realm row that batch had asked about.
    it("holds the book pass back while a keys batch is still outstanding", function()
      local GC, watch = load()
      watch.hungry = false
      local clock = 1000
      _G.time = function() return clock end
      GC.Sniper._bookPass:Abort()
      fullResults = true
      _G.C_AuctionHouse.SendBrowseQuery = function() sent[#sent + 1] = "browse" end
      targets(GC, 1, 3)

      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:3" }, sent)

      GC.Sniper._bookPass:Start("classes") -- a fresh pass wants to open
      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:3" }, sent) -- not while the batch is unanswered

      -- The batch answering releases it...
      foldKeys(GC)
      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:3", "browse" }, sent)
    end)

    it("gives up on an unanswered batch, and forgets what it asked", function()
      local GC, watch = load()
      watch.hungry = false
      local clock = 1000
      _G.time = function() return clock end
      GC.Sniper._bookPass:Abort()
      fullResults = true
      _G.C_AuctionHouse.SendBrowseQuery = function() sent[#sent + 1] = "browse" end
      targets(GC, 1, 3)

      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:3" }, sent)
      assert.is_table(GC.Sniper._keysBatch)

      GC.Sniper._bookPass:Start("classes")
      clock = clock + 31 -- past LIM.KEYS_TIMEOUT_SECONDS (30 -- a hundred-key search is slow): no browse event is coming
      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:3", "browse" }, sent)
      -- The list of items that batch asked about goes with the wait. Left behind, the next
      -- fold reads it as "these were asked about and did not come back" and deletes rows
      -- nobody asked about this time.
      assert.is_nil(GC.Sniper._keysBatch)
    end)

    -- The Sell tab's bulk fill stops waiting for its own batch after eight seconds
    -- (GC.Sell.BulkOutstanding). The arbiter kept the slot shut for the full thirty: REFRESH on
    -- Sell, straight over to Deals, and the board stood still for up to half a minute over an
    -- answer nobody wanted any more.
    describe("unanswered batch, by owner", function()
      local function outstandingAfter(owner, seconds)
        local GC = load()
        local clock = 1000
        _G.time = function() return clock end
        GC.Sniper._keysAwaiting, GC.Sniper._keysOwner, GC.Sniper._keysBatch = clock, owner, { 1, 2, 3 }
        clock = clock + seconds
        return GC.Sniper._KeysOutstanding(), GC
      end

      it("writes the Sell tab's batch off after eight seconds, and forgets what it asked", function()
        assert.is_true((outstandingAfter("sell", 7)))
        local outstanding, GC = outstandingAfter("sell", 8)
        assert.is_false(outstanding)
        assert.is_nil(GC.Sniper._keysAwaiting)
        assert.is_nil(GC.Sniper._keysOwner)
        assert.is_nil(GC.Sniper._keysBatch)
      end)

      it("still waits the full thirty for the realm poll's batch", function()
        assert.is_true((outstandingAfter("sniper", 8)))
        assert.is_true((outstandingAfter("sniper", 29)))
        assert.is_false((outstandingAfter("sniper", 30)))
      end)

      -- Caps fixes 5i: the BUY tab's own refresh batch got the thirty seconds, so a lost answer
      -- held the player's hover or click quote -- which waits for it -- for half a minute with
      -- nothing on screen. It is a tab's own batch like the Sell tab's, and waits as long.
      it("writes the BUY tab's batch off after eight seconds too", function()
        assert.is_true((outstandingAfter("buy", 7)))
        assert.is_false((outstandingAfter("buy", 8)))
      end)

      -- Caps fixes 4a, round 1: a batch still out from the board the player just left, while the
      -- Sell or BUY tab is on screen. Those tabs' own searches take its answer (UI/SellFrame.lua's
      -- advanceQuote, seen in game) and the Sell walk now stands still for it -- thirty seconds of
      -- that held every keys consumer and the walk. The tab's own batch keeps its own allowance.
      it("gives a batch the tab on screen did not send eight seconds on the Sell and BUY tabs", function()
        local function after(owner, onView, seconds)
          local GC = load()
          set(GC.Sniper.OnThrottleReady, "view", onView)
          local clock = 1000
          _G.time = function() return clock end
          GC.Sniper._keysAwaiting, GC.Sniper._keysOwner, GC.Sniper._keysBatch = clock, owner, { 1 }
          clock = clock + seconds
          return GC.Sniper._KeysOutstanding()
        end
        for _, owner in ipairs({ "sniper", "caps", "buy" }) do
          assert.is_false(after(owner, "sell", 8))
        end
        for _, owner in ipairs({ "sniper", "caps" }) do
          assert.is_false(after(owner, "buy", 8))
        end
        assert.is_true(after("buy", "buy", 7))
        assert.is_false(after("buy", "buy", 8))
        assert.is_true(after("caps", "sold", 29))
      end)
    end)

    -- Observed in game as the player's own Browse pane jumping to an item page with a spinner
    -- on it: both of these replace the buffer that pane is showing.
    it("sends neither a keys batch nor a browse page while the player is using the auction house", function()
      local GC, watch = load()
      watch.hungry = false
      GC.Sniper._bookPass:Abort()
      fullResults = true
      _G.C_AuctionHouse.SendBrowseQuery = function() sent[#sent + 1] = "browse" end
      targets(GC, 1, 3)
      GC.AuctionHouseTab = { PlayerIsBusy = function() return true end }
      GC.Sniper._bookPass:Start("classes")

      GC.Sniper.OnThrottleReady()
      assert.same({}, sent)

      GC.AuctionHouseTab.PlayerIsBusy = function() return false end
      GC.Sniper.OnThrottleReady()
      assert.same({ "browse" }, sent) -- the pass, which was armed first

      GC.Sniper._bookPass:Abort()
      GC.Sniper.OnThrottleReady()
      assert.same({ "browse", "keys:3" }, sent)
    end)

    it("sends nothing for the key poll while a purchase is in flight", function()
      local GC, watch = load()
      watch.hungry = false
      GC.Sniper._bookPass:Abort()
      fullResults = true
      targets(GC, 1, 3)
      local row = { purchaseStage = "confirming" }
      set(GC.Sniper._QuietZoneOpen, "rows", { row })
      GC.Sniper.OnThrottleReady()
      assert.same({}, sent)

      row.purchaseStage = nil
      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:3" }, sent)
    end)
  end)

  -- The drill queue charges a send at Pop, and REFUSES once its per-minute budget is spent.
  -- That answer was thrown away: the drill went out anyway, past the budget, and the entry Pop
  -- had not removed stayed at the head of the queue to do it again on the next ready tick.
  it("stops drilling once the queue's own per-minute budget is spent", function()
    local GC, watch = load()
    watch.hungry = false
    GC.Sniper._bookPass:Abort()
    GC.Sniper._drillQueue = GC.DrillQueue.New({ now = _G.time }, { perMinute = 1 })
    GC.Sniper._keyPoll:Fold({
      { itemKey = { itemID = 42 }, minPrice = 900, totalQuantity = 1 },
      { itemKey = { itemID = 43 }, minPrice = 800, totalQuantity = 1 },
    })
    GC.Sniper._drillQueue:Push({ itemID = 42, floor = 900, estProfit = 20 })
    GC.Sniper._drillQueue:Push({ itemID = 43, floor = 800, estProfit = 10 })
    set(GC.Sniper.OnThrottleReady, "canDrillNow", function() return true end)
    set(GC.Sniper.OnThrottleReady, "maybeStartPrewarm", function()
      sent[#sent + 1] = "drill"
      return true
    end)

    GC.Sniper.OnThrottleReady()
    assert.same({ "drill" }, sent)

    -- The budget is gone. The second hit is not drilled, and it is not lost either: it is
    -- still queued for a minute from now.
    GC.Sniper.OnThrottleReady()
    assert.same({ "drill" }, sent)
    assert.equal(1, GC.Sniper._drillQueue:Depth())
  end)

  -- Whole-market coverage: with thousands of fact-bearing commodities the drill queue is never
  -- empty, and drills went before pages every slot -- a 7-14 s pass stretched to minutes. While a
  -- page waits too, drills take at most LIM.DRILL_SHARE slots in a row.
  it("gives the book pass every third slot while drills and pages both wait", function()
    local GC, watch = load()
    watch.hungry = false
    for i = 1, 9 do
      GC.Sniper._keyPoll:Fold({ { itemKey = { itemID = 40 + i }, minPrice = 900, totalQuantity = 1 } })
      GC.Sniper._drillQueue:Push({ itemID = 40 + i, floor = 900, estProfit = 100 - i })
    end
    set(GC.Sniper.OnThrottleReady, "canDrillNow", function() return true end)
    set(GC.Sniper.OnThrottleReady, "maybeStartPrewarm", function()
      sent[#sent + 1] = "drill"
      return true
    end)
    for _ = 1, 6 do
      armPage(GC)
      GC.Sniper.OnThrottleReady()
    end
    assert.same({ "drill", "drill", "page", "drill", "drill", "page" }, sent)
    assert.equal(4, GC.Sniper._drillShare.drills)
    assert.equal(2, GC.Sniper._drillShare.pages)
  end)

  -- Fix round 1 (m1): /gc board's drillShare counts a page as contended only when a drill that
  -- could have gone stood aside for it -- not when the drills were out of budget, or could not
  -- send at all this slot (canDrillNow false: a drill in flight, the player busy, another tab).
  it("counts a page against the drills only when a sendable drill stood aside for it", function()
    local GC, watch = load()
    watch.hungry = false
    GC.Sniper._drillQueue = GC.DrillQueue.New({ now = _G.time }, { perMinute = 2 })
    for i = 1, 9 do
      GC.Sniper._keyPoll:Fold({ { itemKey = { itemID = 40 + i }, minPrice = 900, totalQuantity = 1 } })
      GC.Sniper._drillQueue:Push({ itemID = 40 + i, floor = 900, estProfit = 100 - i })
    end
    local drillable = true
    set(GC.Sniper.OnThrottleReady, "canDrillNow", function() return drillable end)
    set(GC.Sniper.OnThrottleReady, "maybeStartPrewarm", function()
      sent[#sent + 1] = "drill"
      return true
    end)
    for _ = 1, 5 do
      armPage(GC)
      GC.Sniper.OnThrottleReady()
    end
    -- The budget of two is gone after two drills: every page after them went to a pass nobody
    -- was waiting behind.
    assert.same({ "drill", "drill", "page", "page", "page" }, sent)
    assert.equal(2, GC.Sniper._drillShare.drills)
    assert.equal(0, GC.Sniper._drillShare.pages)

    GC.Sniper._drillQueue = GC.DrillQueue.New({ now = _G.time })
    GC.Sniper._drillQueue:Push({ itemID = 41, floor = 900, estProfit = 99 })
    GC.Sniper._drillShare.run = 2
    drillable = false
    armPage(GC)
    GC.Sniper.OnThrottleReady()
    assert.same("page", sent[#sent])
    assert.equal(0, GC.Sniper._drillShare.pages)
  end)

  it("lets drills take every slot when no page is waiting", function()
    local GC, watch = load()
    watch.hungry = false
    GC.Sniper._bookPass:Abort()
    for i = 1, 4 do
      GC.Sniper._keyPoll:Fold({ { itemKey = { itemID = 40 + i }, minPrice = 900, totalQuantity = 1 } })
      GC.Sniper._drillQueue:Push({ itemID = 40 + i, floor = 900, estProfit = 100 - i })
    end
    set(GC.Sniper.OnThrottleReady, "canDrillNow", function() return true end)
    set(GC.Sniper.OnThrottleReady, "maybeStartPrewarm", function()
      sent[#sent + 1] = "drill"
      return true
    end)
    for _ = 1, 4 do GC.Sniper.OnThrottleReady() end
    assert.same({ "drill", "drill", "drill", "drill" }, sent)
  end)

  -- Same two gates the verify walk stands down for: with the Sell tab up nobody is reading
  -- what a drill answers, and while the player is working Blizzard's own panes their click
  -- outranks it. Both were taking slots from the Sell tab's pricing walk.
  it("does not drill for a board nobody is looking at, or over the player's own search", function()
    local GC, watch = load()
    watch.hungry = false
    GC.Sniper._bookPass:Abort()
    set(GC.Sniper.OnAuctionHouseShow, "ahOpen", true)
    GC.Sniper._keyPoll:Fold({ { itemKey = { itemID = 42 }, minPrice = 900, totalQuantity = 1 } })
    GC.Sniper._drillQueue:Push({ itemID = 42, floor = 900, estProfit = 20 })
    set(GC.Sniper.OnThrottleReady, "maybeStartPrewarm", function()
      sent[#sent + 1] = "drill"
      return true
    end)

    set(GC.Sniper.OnThrottleReady, "view", "sell")
    GC.Sniper.OnThrottleReady()
    assert.same({}, sent)

    set(GC.Sniper.OnThrottleReady, "view", "deals")
    GC.AuctionHouseTab = { PlayerIsBusy = function() return true end }
    GC.Sniper.OnThrottleReady()
    assert.same({}, sent)

    GC.AuctionHouseTab.PlayerIsBusy = function() return false end
    GC.Sniper.OnThrottleReady()
    assert.same({ "drill" }, sent)
  end)

  -- The loop answers whether its turn produced a search (Core/Scanner.lua). A turn it did not
  -- spend belongs to whoever is next in line -- it used to be reported as spent regardless,
  -- and the page or the verify check behind it simply did not happen.
  it("passes the slot on when the watch loop had nothing to send", function()
    local GC = load()
    GC.Sniper.scanner.OnSystemReady = function() return false end

    -- The pass takes the first turn and yields the next one to the tail.
    armPage(GC)
    GC.Sniper.OnThrottleReady()
    assert.same({ "page" }, sent)

    -- The tail's turn. The watch loop is hungry but sends nothing -- every item in its set is
    -- waiting on an item key the client has not cached -- so the turn goes to the pass rather
    -- than being reported as spent and lost.
    armPage(GC)
    GC.Sniper.OnThrottleReady()
    assert.same({ "page", "page" }, sent)
  end)

  -- The BUY tab's floor refresh (UI/BuyFrame.lua) is a second consumer of the ONE keys batch
  -- this addon allows itself, and it reaches the client through the same arbiter entry point.
  -- Stood in for here rather than loaded: this file is about who gets the slot, and BuyFrame's
  -- own gates (a run on screen, the twenty-second window) have their own spec.
  describe("BUY floor refresh", function()
    local function armBuy(GC, ids)
      local handed = false
      GC.Buy = {
        TrySendRefresh = function(playerBusy)
          return GC.Sniper._TrySendKeysBatchFor({
            HasPending = function() return not handed end,
            NextBatch = function() handed = true; return ids end,
          }, "buy", function() return true end, playerBusy)
        end,
      }
    end

    -- The rule that makes a keys call safe at all: it REPLACES the client's one browse buffer,
    -- so a pass mid-page owns that buffer and nobody else may touch it. BUY is no exception --
    -- its batch would steal the page the pass is waiting for, and the pass would fold BUY's
    -- rows as its own.
    it("refuses BUY's batch while the book pass is paging", function()
      local GC, watch = load()
      watch.hungry = false
      armBuy(GC, { 11, 12 })
      armPage(GC)
      GC.Sniper.OnThrottleReady()
      assert.same({ "page" }, sent)
    end)

    it("hands BUY the grant once no pass owns the browse buffer", function()
      local GC, watch = load()
      watch.hungry = false
      GC.Sniper._bookPass:Abort()
      fullResults = true
      armBuy(GC, { 11, 12 })
      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:2" }, sent)

      -- And one batch is one batch, whoever sent it: the Items poll waits for BUY's answer
      -- exactly as it waits for its own.
      GC.Sniper._keyPoll:SetTargets({ 1, 2, 3 })
      GC.Sniper.OnThrottleReady()
      assert.same({ "keys:2" }, sent)
    end)
  end)

  it("keeps mayScan closed while a purchase is in flight, even inside the watch loop's own grant", function()
    local GC = load()
    local mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan
    local row = { purchaseStage = "buying" }
    set(GC.Sniper._QuietZoneOpen, "rows", { row })

    local seenInside
    GC.Sniper.scanner.OnSystemReady = function() seenInside = mayScan() end
    GC.Sniper._GrantWatchSlot()
    assert.is_false(seenInside) -- the grant window opens, but a purchase in flight still vetoes it

    row.purchaseStage = nil
    GC.Sniper._GrantWatchSlot()
    assert.is_true(seenInside) -- and resumes the moment the purchase clears
  end)
end)
