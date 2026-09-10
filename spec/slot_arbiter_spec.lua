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

  local function load()
    sent = {}
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
      HasFullBrowseResults = function() return false end,
      GetBrowseResults = function() return {} end,
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
      },
      WatchSet = { Observe = function() end, Select = function() return {} end },
      Print = function() end,
      db = { settings = { sniper = { sound = false } } },
    }
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)
    -- A fake watch scanner whose only job is to record that it was handed a slot.
    local watch = { hungry = true }
    function watch:Wants() return self.hungry end
    function watch:OnSystemReady() sent[#sent + 1] = "watch" end
    GC.Sniper.scanner = watch
    -- Starts a real book pass so GC.Sniper._bookPass:IsPaging() is true and its own
    -- OnThrottleReady() has something to arbitrate -- the first query send (via the
    -- IsThrottledMessageSystemReady()==true stub above) doesn't touch `sent`, only
    -- RequestMoreBrowseResults does.
    GC.Sniper._bookPass:Start("classes")
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

  -- Sniper fast loop (Task 5): browse paging is no longer a round-robin peer of watch -- a book
  -- pass with a page pending wins the slot OUTRIGHT (see GC.Sniper.OnThrottleReady), even with
  -- the watch loop hungry every single cycle.
  it("lets browse paging win the slot outright while a page is pending, even with watch hungry", function()
    local GC = load() -- watch.hungry is true by default
    for _ = 1, 3 do
      armPage(GC)
      GC.Sniper.OnThrottleReady()
    end
    assert.same({ "page", "page", "page" }, sent)
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
    set(GC.Sniper.OnThrottleReady, "driver", { sendSearch = function(id) searched[#searched + 1] = id end })
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
  -- terminal event. A purchase in flight is tracked as a non-empty activeItemID (armed through
  -- confirming -- see maybeStartPrewarm's own comment on this upvalue).
  it("sends nothing while a purchase is in flight, and serves again once it resolves", function()
    local GC = load()
    armPage(GC) -- book pass has a page pending and would otherwise win outright
    set(GC.Sniper.OnThrottleReady, "activeItemID", { [12345] = true })

    for _ = 1, 3 do
      GC.Sniper.OnThrottleReady()
    end
    assert.same({}, sent)

    set(GC.Sniper.OnThrottleReady, "activeItemID", {})
    GC.Sniper.OnThrottleReady()
    assert.same({ "page" }, sent) -- the parked page still wants sending, and is free to now
  end)

  -- A parked Check requery is step 1, ahead of the purchase-in-flight veto -- it is the
  -- player's own click and has already stopped the loop as a courtesy, purchase or not.
  it("still lets a parked Check requery through while a purchase is in flight", function()
    local GC = load()
    local searched = {}
    set(GC.Sniper.OnThrottleReady, "driver", { sendSearch = function(id) searched[#searched + 1] = id end })
    local attempt = { itemID = 42, token = 1, row = {}, deal = { itemID = 42 } }
    upvalue(GC.Sniper.OnThrottleReady, "pendingRequerySend")[42] = attempt
    set(GC.Sniper.OnThrottleReady, "isCurrentRequeryAttempt", function() return true end)
    set(GC.Sniper.OnThrottleReady, "activeItemID", { [99] = true })

    GC.Sniper.OnThrottleReady()
    assert.same({ 42 }, searched)
    assert.same({}, sent)
  end)

  it("keeps mayScan closed while a purchase is in flight, even inside the watch loop's own grant", function()
    local GC = load()
    local mayScan = upvalue(GC.Sniper.OnItemKeyInfo, "driver").mayScan
    set(GC.Sniper.OnThrottleReady, "activeItemID", { [12345] = true })

    local seenInside
    GC.Sniper.scanner.OnSystemReady = function() seenInside = mayScan() end
    GC.Sniper._GrantWatchSlot()
    assert.is_false(seenInside) -- the grant window opens, but a purchase in flight still vetoes it

    set(GC.Sniper.OnThrottleReady, "activeItemID", {})
    GC.Sniper._GrantWatchSlot()
    assert.is_true(seenInside) -- and resumes the moment the purchase clears
  end)
end)
