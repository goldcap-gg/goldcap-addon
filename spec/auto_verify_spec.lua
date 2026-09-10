local helper = require("spec.spec_helper")

-- Background verification of the deals list: the addon runs the SAME live query a Check runs,
-- on the handful of rows the player is looking at, so a row can carry a real verdict before it
-- is clicked. It must never buy anything -- see the last test in this file, and
-- spec/sniper_purchase_wiring_spec.lua, which asserts the protected calls stay inside the
-- hardware click handler for the whole file.
describe("Deals background verification", function()
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

  local clock, sounds, sent

  local function widget()
    local w = {}
    function w:SetText() end
    function w:SetTextColor() end
    function w:SetTexture() end
    function w:SetLabel(label) self.label = label end
    function w:SetVariant(name) self.variant = name end
    -- The row's left rail is a real texture the pin marker drives: it is shown in blue while
    -- the watch loop is polling that row, and hidden otherwise.
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetColorTexture(r, g, b) self.rgb = { r, g, b } end
    function w:Enable() self.enabled = true end
    function w:Disable() self.enabled = false end
    return w
  end

  -- Enough of a pooled row for the real setRowDeal/refreshRows to run against. The flash
  -- animation is deliberately absent: flashRow returns early without one, which keeps the
  -- ping tests about the SOUND (the observable part) rather than about an animation stub.
  local function fakeRow()
    local row = {
      buy = widget(), tierChip = widget(), icon = widget(), nameText = widget(),
      discountText = widget(), unitText = widget(), priceText = widget(),
      profitText = widget(), trendText = widget(), highlight = widget(), rail = widget(), pinBg = widget(),
      shown = false,
    }
    function row:Show() self.shown = true end
    function row:Hide() self.shown = false end
    function row:IsShown() return self.shown end
    function row:SetAlpha(a) self.alpha = a end
    return row
  end

  local function deal(itemID, unitPrice, profit)
    return { itemID = itemID, unitPrice = unitPrice, qty = 1, avail = 10,
      profit = profit or 1000, discount = 0.5, tier = "GOOD", stale = true,
      action = "Check", status = "WATCH", reason = "live_verification_required" }
  end

  -- Loads the real UI/SniperFrame.lua and hands back the internals these tests drive. The
  -- getupvalue chains are the seam this file has (see addon/AGENTS.md): the module's state is
  -- all chunk-level locals, and every closure in the chunk shares the same upvalue cell, so
  -- setting one through any function sets it for all of them.
  local function loadSniper(decision)
    clock, sounds, sent = 100, {}, {}
    _G.GetTime = function() return clock end
    _G.time = function() return 1000 end
    _G.GetMoney = function() return 10 * 1000 * 10000 end
    _G.GetCoinTextureString = function(copper) return tostring(copper) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.PlaySound = function(id) sounds[#sounds + 1] = id end
    _G.SOUNDKIT = { READY_CHECK = 8960, MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    -- RequestMoreBrowseResults is reassigned per-test (a fresh closure over that test's own
    -- `paged` local) by the three arbiter tests below that actually drive the book pass;
    -- every other test in this file never starts a pass, so this default is never reached.
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return false end,
      GetBrowseResults = function() return {} end,
    }

    local GC = {
      Theme = {
        ROW_H = 20,
        RAIL_W = 76,
        pad = { m = 8, s = 4, xs = 2 },
        tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 }, fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 },
          gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } },
      },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end }
      end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end },
      Scanner = { New = function() return { Start = function() end, Stop = function() end } end },
      Sell = { Refresh = function() end, Reset = function() end,
        Hide = function() end, Show = function() end },
      SniperDecision = {
        Evaluate = function() return decision() end,
        MarketFromValue = function() return {} end,
        ReasonText = function(token) return "reason:" .. tostring(token) end,
      },
      -- Real no-op shapes, not an empty table: the book pass's onRows driver callback runs
      -- this pipeline on every results event, even an empty tail (see the three arbiter
      -- tests below that actually start a pass).
      FullScan = {
        RowsFromBrowse = function() return {} end,
        EvaluateDelta = function() return {}, 0, 0 end,
        CollectNewHot = function() return {} end,
        MergeDeals = function(existing) return existing end,
      },
      WatchSet = { Observe = function() end, Select = function() return {} end },
      Print = function() end,
      db = { settings = { sniper = { sound = true, showRefused = false } } },
    }
    if not _G.time then _G.time = os.time end
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/BoardRows.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local show = GC.Sniper.OnAuctionHouseShow
    local api = {
      GC = GC,
      tick = upvalue(show, "tickAutoVerify"),
      refreshRows = upvalue(show, "refreshRows"),
    }
    -- One hop further than it used to be: the walk was split so the slot arbiter can TAKE a
    -- turn with it (GC.Sniper.OnThrottleReady), leaving tickAutoVerify as the ticker path that
    -- calls into it. Both still exist and the upvalue names are unchanged.
    api.step = upvalue(api.tick, "stepVerifyWalk")
    -- The gates the walk stands down for moved into their own predicate when the walk was
    -- split, because the ticker has to ask them BEFORE spending its once-a-second turn and the
    -- arbiter has to ask them before offering a slot. `view` is a module-level local, so
    -- setting it through this closure sets it for every reader.
    api.standsDown = upvalue(api.step, "verifyWalkStandsDown")
    api.renderList = upvalue(api.step, "renderList")
    api.verdicts = upvalue(api.step, "verdicts")
    api.rows = upvalue(api.refreshRows, "rows")

    set(api.refreshRows, "content", { SetHeight = function() end })
    set(api.refreshRows, "createRow", function() return fakeRow() end)
    set(GC.Sniper.OnItemKeyInfo, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function(itemID) sent[#sent + 1] = itemID end,
      commodityBook = function() return { { unitPrice = 100, quantity = 50 } } end,
      commodityResult = function() return { unitPrice = 100, qty = 50, avail = 50 } end,
      itemResult = function() return nil end,
    })
    set(show, "ahOpen", true)
    set(show, "mode", "fullscan")
    set(show, "frame", { IsShown = function() return true end, Hide = function() end,
      status = { SetText = function() end } })
    return api
  end

  -- Advances past the once-a-second walk gate so consecutive ticks each get to walk.
  local function tickAt(api, seconds)
    clock = seconds
    api.tick()
  end

  local function board(api, deals)
    set(api.GC.Sniper.OnAuctionHouseShow, "scanDeals", deals)
  end

  local safe = function() return { status = "SAFE", buyable = true, quantity = 5, reasons = {} } end
  local avoid = function() return { status = "AVOID", buyable = false, reasons = { "demand_limit" } } end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.C_AuctionHouse = nil
  end)

  it("checks the top unverified row, one query per walk", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100), deal(2, 200), deal(3, 300) })

    tickAt(api, 101)
    assert.same({ 1 }, sent)
    -- Same walk, second tick: the first query is still in flight, so nothing else goes out.
    tickAt(api, 102)
    assert.same({ 1 }, sent)
  end)

  it("walks at most once a second, not on every one of the four ticks in it", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100), deal(2, 200) })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.same({ 1 }, sent)

    -- Same second, nothing in flight, an unverified row waiting: still no second walk.
    tickAt(api, 101.5)
    assert.same({ 1 }, sent)

    tickAt(api, 102.1)
    assert.same({ 1, 2 }, sent)
  end)

  it("moves down the list rather than re-asking about a fresh verdict", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100), deal(2, 200) })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.same({ 1 }, sent)

    tickAt(api, 102)
    assert.same({ 1, 2 }, sent)
  end)

  it("re-checks a row only once the interval has passed", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100) })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.same({ 1 }, sent)

    tickAt(api, 125) -- 24s later: still inside LIM.VERIFY_INTERVAL_SECONDS
    assert.same({ 1 }, sent)

    tickAt(api, 132) -- 31s after the verdict landed
    assert.same({ 1, 1 }, sent)
  end)

  it("never looks past the widened top-24 rows", function()
    local api = loadSniper(safe)
    local deals = {}
    -- Distinct, descending profit per item: with no verdict yet every row ties on bucket
    -- (UNVERIFIED), so GC.BoardRows.Compare's estProfit tiebreak is what has to give this a
    -- deterministic order -- a flat tie here would leave table.sort free to reshuffle rows
    -- 25/26 items wide, which is not what this test is about.
    for i = 1, 26 do deals[i] = deal(i, i * 100, (27 - i) * 10) end
    board(api, deals)

    for i = 1, 26 do
      tickAt(api, 100 + i)
      api.GC.Sniper.OnCommoditySearchResults(sent[#sent])
    end
    assert.equal(24, #sent)
    for i = 1, 24 do assert.equal(i, sent[i]) end
  end)

  -- Never-verified rows get first claim on the walk's one query per tick, ahead of an
  -- already-verified row that merely became due for a recheck -- even though that already-
  -- verified row sits FIRST in renderList()'s own order. Under the old single-pass, top-down
  -- walk this row would have won the slot instead: it is "due" the moment 30s pass, exactly
  -- like a never-verified row reads as "due" from tick one.
  it("prioritizes a never-verified row over re-confirming one that is merely due", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100) })

    tickAt(api, 101)
    assert.same({ 1 }, sent)
    api.GC.Sniper.OnCommoditySearchResults(1) -- item1's verdict lands at t=101

    -- item2 joins the board, never checked. item1's verdict is now well past
    -- LIM.VERIFY_INTERVAL_SECONDS (30s) -- under the OLD top-down walk it would be the only
    -- candidate this tick, since it sits ahead of item2 in the list and reads as "due".
    board(api, { deal(1, 100), deal(2, 200) })
    tickAt(api, 140) -- 39s after item1's verdict
    assert.same({ 1, 2 }, sent) -- item2 (never verified) wins the slot, not a re-confirmation of item1
  end)

  -- An AVOID verdict gets a much longer leash than any other status: the gates that produce it
  -- (demand/velocity/liquidity limits) do not move on a 30-second clock, so re-confirming one
  -- costs a query the walk could spend on a row nothing has looked at yet.
  it("rechecks an AVOID row only after the wider 120s backoff, not the normal 30s", function()
    local api = loadSniper(avoid)
    -- Keep the AVOID row visible to the walk itself (renderList hides an unmanaged refusal by
    -- default) -- same toggle the toolbar's "Hidden: N" button flips, see the tests below.
    api.GC.db.settings.sniper.showRefused = true
    board(api, { deal(1, 100) })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1) -- AVOID verdict lands at t=101
    assert.equal("AVOID", api.verdicts[1].status)
    assert.same({ 1 }, sent)

    tickAt(api, 101 + 31) -- past the normal 30s interval, short of the 120s AVOID backoff
    assert.same({ 1 }, sent)

    tickAt(api, 101 + 121) -- past the 120s AVOID backoff
    assert.same({ 1, 1 }, sent)
  end)

  -- THE bug this walk existed to have and did not: it used to run only on the 0.25s ticker,
  -- and only if it happened to catch the throttled system idle. GC.Sniper.OnThrottleReady
  -- hands that slot to the browse scan synchronously the instant it opens, so under Auto --
  -- where the scan pages continuously -- the ticker essentially never found an idle moment.
  -- The board therefore filled with UNVERIFIED rows that were checked, and refused, only once
  -- the player pressed Stop. From the player's chair that read as "stopping the scan deleted
  -- my deals". The walk is a slot consumer now, so it is never left idle: it takes a slot on
  -- any cycle the book pass itself has nothing pending, rather than only once the scan stops.
  --
  -- Sniper fast loop (Task 5): a book pass with a page pending now wins the slot OUTRIGHT
  -- ahead of the watch/verify round robin (see GC.Sniper.OnThrottleReady) -- discovery is the
  -- send that keeps the loop finding anything at all, so it is no longer a peer the walk
  -- alternates with. This test now covers the other half of that contract: the walk still gets
  -- covered whenever the pass is not itself asking for the slot that cycle.
  it("gets its turn from the arbiter once the book pass has nothing pending", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100) })
    local ready = api.GC.Sniper.OnThrottleReady
    local paged = 0
    _G.C_AuctionHouse.RequestMoreBrowseResults = function() paged = paged + 1 end
    -- No watch loop, so the only other consumer for the round robin to reach is the walk.
    api.GC.Sniper.scanner = nil
    api.GC.Sniper._bookPass:Start("classes")

    -- A page pending: the pass wins the slot outright, and the walk does not even get asked.
    api.GC.Sniper._bookPass:OnResultsUpdated() -- arms a pending page (HasFullBrowseResults stubs false)
    ready()
    assert.equal(1, paged)
    assert.same({}, sent)

    -- Nothing pending for the pass this cycle: the walk takes the slot instead of it idling.
    ready()
    assert.equal(1, paged)
    assert.same({ 1 }, sent)
  end)

  it("lets the book pass take every slot while a page is pending, never yielding to the walk", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100), deal(2, 200), deal(3, 300) })
    local ready = api.GC.Sniper.OnThrottleReady
    local order = {}
    _G.C_AuctionHouse.RequestMoreBrowseResults = function() order[#order + 1] = "page" end
    set(api.step, "maybeStartPrewarm", function(target)
      order[#order + 1] = "verify:" .. target.itemID
      return true
    end)
    api.GC.Sniper.scanner = nil
    api.GC.Sniper._bookPass:Start("classes")

    for _ = 1, 6 do
      api.GC.Sniper._bookPass:OnResultsUpdated()
      ready()
    end

    -- Discovery outranks the walk outright now: as long as the pass has a page pending it wins
    -- every slot -- the walk only ever runs on a cycle the pass has nothing to send (see the
    -- test above).
    assert.same({ "page", "page", "page", "page", "page", "page" }, order)
  end)

  -- The other half of the same contract: a walk with nothing to check must not cost the scan a
  -- slot. A split that manufactures idle slots is worse than no split at all.
  it("hands the slot straight back when the walk has nothing to check", function()
    local api = loadSniper(safe)
    board(api, {})
    local ready = api.GC.Sniper.OnThrottleReady
    local paged = 0
    _G.C_AuctionHouse.RequestMoreBrowseResults = function() paged = paged + 1 end
    api.GC.Sniper.scanner = nil
    api.GC.Sniper._bookPass:Start("classes")

    for _ = 1, 4 do
      api.GC.Sniper._bookPass:OnResultsUpdated()
      ready()
    end

    assert.equal(4, paged)
    assert.same({}, sent)
  end)

  it("stands down for the auction house, the tab, the window and the search slot", function()
    local api = loadSniper(safe)
    local show = api.GC.Sniper.OnAuctionHouseShow
    board(api, { deal(1, 100) })

    set(show, "ahOpen", false)
    tickAt(api, 101)
    assert.same({}, sent)
    set(show, "ahOpen", true)

    set(api.standsDown, "view", "sell")
    tickAt(api, 102)
    assert.same({}, sent)
    set(api.standsDown, "view", "deals")

    set(show, "frame", { IsShown = function() return false end })
    tickAt(api, 103)
    assert.same({}, sent)
    set(show, "frame", { IsShown = function() return true end, status = { SetText = function() end } })

    -- A purchase (or a Check) owns the throttled search slot. IsSearchCritical is the same
    -- gate the Sell tab's own quote walker stands down for.
    upvalue(api.GC.Sniper.IsBusy, "activeItemID")[1] = true
    assert.is_true(api.GC.Sniper.IsSearchCritical())
    tickAt(api, 104)
    assert.same({}, sent)
    upvalue(api.GC.Sniper.IsBusy, "activeItemID")[1] = nil

    tickAt(api, 105)
    assert.same({ 1 }, sent)
  end)

  -- Confirmed live 2026-08-18: with the window closed, this walk kept burning the shared
  -- request throttle while the player tried to click Create Auction in Blizzard's own default
  -- sell panel, and every click failed with "You're doing that too fast". PlayerIsBusy is the
  -- single predicate this gate reads now -- posting, buying a browse result, or reading their
  -- own search all mean the same thing to this walk: yield.
  it("stands down while the player is busy on Blizzard's own AH panes", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100) })
    api.GC.AuctionHouseTab = { PlayerIsBusy = function() return true end }

    tickAt(api, 101)
    assert.same({}, sent)

    api.GC.AuctionHouseTab.PlayerIsBusy = function() return false end
    tickAt(api, 102)
    assert.same({ 1 }, sent)
  end)

  -- The walk used to `return` the moment it picked a candidate, whether or not a query
  -- actually went out. Two of maybeStartPrewarm's own gates never clear on their own -- an
  -- item whose key the client has not cached yet, and one parked behind the untagged-result
  -- drain fence -- so a single unsendable row at the top starved every row beneath it for the
  -- rest of the session. That is what "it only works sometimes" was.
  it("gets past a row it cannot send and checks the ones under it", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100), deal(2, 200), deal(3, 300) })
    set(api.GC.Sniper.OnItemKeyInfo, "driver", {
      isReady = function() return true end,
      -- The client has no item-key info for 1 yet. A pre-warm cannot chase it (only the
      -- dialog's own patient startRequery does), so this row is unsendable right now.
      getKeyInfo = function(itemID) return itemID ~= 1 and { isCommodity = true } or nil end,
      sendSearch = function(itemID) sent[#sent + 1] = itemID end,
      commodityBook = function() return { { unitPrice = 100, quantity = 50 } } end,
      commodityResult = function() return { unitPrice = 100, qty = 50, avail = 50 } end,
      itemResult = function() return nil end,
    })

    tickAt(api, 101)
    assert.same({ 2 }, sent)
    api.GC.Sniper.OnCommoditySearchResults(2)
    tickAt(api, 102)
    assert.same({ 2, 3 }, sent)
  end)

  it("does not spend its once-a-second turn on a throttle that was not ready", function()
    local ready = false
    local api = loadSniper(safe)
    board(api, { deal(1, 100) })
    set(api.GC.Sniper.OnItemKeyInfo, "driver", {
      isReady = function() return ready end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function(itemID) sent[#sent + 1] = itemID end,
      commodityBook = function() return { { unitPrice = 100, quantity = 50 } } end,
      commodityResult = function() return { unitPrice = 100, qty = 50, avail = 50 } end,
      itemResult = function() return nil end,
    })

    tickAt(api, 101) -- throttle busy: the scan is paging, which under Auto is most of the time
    assert.same({}, sent)

    ready = true
    tickAt(api, 101.25) -- the very next tick, not a second later
    assert.same({ 1 }, sent)
  end)

  it("rings even though a scan page replaced the deal table under the query", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100) })
    tickAt(api, 101)
    assert.same({ 1 }, sent)

    -- Streaming re-evaluates on every browse page, and MergeDeals splices in FRESH tables.
    -- Same item, same asking price, different table -- which is all it took to lose the ping.
    board(api, { deal(1, 100) })
    api.refreshRows()

    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal("Buy", api.rows[1].buy.label)
    assert.equal(1, #sounds)
  end)

  it("marks a SAFE commodity result buyable and puts Buy on the row", function()
    local api = loadSniper(safe)
    local d = deal(1, 100)
    board(api, { d })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)

    local verdict = api.verdicts[1]
    assert.is_true(verdict.buyable)
    assert.equal(100, verdict.unitPrice)
    assert.equal("SAFE", verdict.status)
    assert.equal(1, #api.rows)
    assert.equal("Buy", api.rows[1].buy.label)
    assert.equal("primary", api.rows[1].buy.variant)
  end)

  it("hides a refused row, counts it, and shows it again on request", function()
    local api = loadSniper(avoid)
    board(api, { deal(1, 100), deal(2, 200) })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)

    local list = api.renderList()
    assert.equal(1, #list)
    assert.equal(2, list[1].itemID)
    assert.equal(1, upvalue(api.renderList, "refusedCount"))

    api.GC.db.settings.sniper.showRefused = true
    list = api.renderList()
    assert.equal(2, #list)
    assert.equal(1, upvalue(api.renderList, "refusedCount"))

    api.refreshRows()
    assert.equal("AVOID", api.rows[1].buy.label)
    assert.equal("ghost", api.rows[1].buy.variant)
  end)

  it("voids a verdict when the asking price moves", function()
    local api = loadSniper(avoid)
    board(api, { deal(1, 100) })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal(0, #api.renderList()) -- refused, hidden

    -- A fresh scan pass quoting a different price is a different offer, and was never checked.
    board(api, { deal(1, 90) })
    assert.equal(1, #api.renderList())
    assert.equal(0, upvalue(api.renderList, "refusedCount"))
  end)

  it("rings on the transition into buyable, not on every re-check", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100) })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal(1, #sounds)

    tickAt(api, 140)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal(1, #sounds)
  end)

  it("will not ring twice for the same item inside the floor", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100), deal(2, 200) })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal(1, #sounds)

    -- The cheap lot is bought, the price recovers, a new one appears -- a genuine second
    -- transition, five seconds later. Worth showing, not worth a second bell.
    board(api, { deal(1, 95), deal(2, 200) })
    tickAt(api, 106)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal(1, #sounds)
    assert.equal("Buy", api.rows[1].buy.label)   -- still shown, just not announced

    -- A DIFFERENT item is never muted by its neighbour.
    tickAt(api, 107)
    api.GC.Sniper.OnCommoditySearchResults(2)
    assert.equal(2, #sounds)

    -- And past the floor the same item may ring again.
    board(api, { deal(1, 90), deal(2, 200) })
    tickAt(api, 140)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal(3, #sounds)
  end)

  it("keeps quiet when the sound setting is off", function()
    local api = loadSniper(safe)
    api.GC.db.settings.sniper.sound = false
    board(api, { deal(1, 100) })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal(0, #sounds)
  end)

  it("stops advertising a SAFE verdict nothing has refreshed, but keeps a refusal", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100) })
    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)

    clock = 101 + 121 -- past LIM.VERIFY_TRUST_SECONDS with no refresh
    api.refreshRows()
    assert.equal("Check", api.rows[1].buy.label)

    -- A refusal is not a claim that decays: it came from demand and velocity limits that do
    -- not move in two minutes, and expiring it would flicker hidden rows back every so often.
    local refused = loadSniper(avoid)
    board(refused, { deal(1, 100) })
    tickAt(refused, 101)
    refused.GC.Sniper.OnCommoditySearchResults(1)
    clock = 101 + 500
    assert.equal(0, #refused.renderList())
  end)

  it("lets a real Check overrule the background verdict it disagrees with", function()
    local api = loadSniper(safe)
    local d = deal(1, 100)
    board(api, { d })
    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal("Buy", api.rows[1].buy.label)

    -- The player clicks that Buy, and the authoritative live Check disagrees. What it found
    -- has to replace what the background walk recorded, or cancelling out of the dialog drops
    -- them back onto a row still wearing a gold Buy button.
    local finish = upvalue(api.GC.Sniper.OnItemSearchResults, "finishRequery")
    local apply = upvalue(finish, "applyRequeryResult")
    set(apply, "dialog", { status = widget() })
    apply({ deal = d }, 1, { isCommodity = true, levels = {},
      decision = { status = "AVOID", buyable = false, reasons = { "demand_limit" } } })

    assert.is_false(api.verdicts[1].buyable)
    assert.equal("AVOID", api.verdicts[1].status)
    -- The gold Buy is gone, which was the point. The ROW is not: they asked about this one.
    api.refreshRows()
    assert.equal(1, #api.renderList())
    assert.equal("AVOID", api.rows[1].buy.label)
    assert.equal("ghost", api.rows[1].buy.variant)
  end)

  it("stays silent when the player ran the Check themselves", function()
    local api = loadSniper(safe)
    local d = deal(1, 100)
    board(api, { d })
    local finish = upvalue(api.GC.Sniper.OnItemSearchResults, "finishRequery")
    local stamp = upvalue(upvalue(finish, "applyRequeryResult"), "stampVerdict")

    stamp(d, { isCommodity = true, levels = {},
      decision = { status = "SAFE", buyable = true, quantity = 5, reasons = {} } }, true)

    -- The verdict is recorded -- that is the point of routing the Check through here -- but
    -- the ping means "something became buyable while you were not looking". The player is
    -- looking: they clicked Check and the dialog is open in front of them.
    assert.is_true(api.verdicts[1].buyable)
    assert.equal("Buy", api.rows[1].buy.label)
    assert.equal(0, #sounds)

    -- ...and the Check path is the one that asks for the silence. (armReady's dialog surface
    -- is far too wide to drive headlessly; this is the one line that wires the two together.)
    local file = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = file:read("*a")
    file:close()
    assert.is_truthy(text:find("stampVerdict(deal, live, true)", 1, true))
  end)

  -- Answering "what about this one?" by making it vanish is not an answer. The background
  -- walk prunes rows nobody asked about; a row the player opened stays put and says what the
  -- Check said, whatever the toggle is set to.
  it("keeps a row the player checked themselves, even when it is refused", function()
    local api = loadSniper(safe)
    local d = deal(1, 100)
    board(api, { d, deal(2, 200) })
    local finish = upvalue(api.GC.Sniper.OnItemSearchResults, "finishRequery")
    local stamp = upvalue(upvalue(finish, "applyRequeryResult"), "stampVerdict")

    stamp(d, { isCommodity = true, levels = {},
      decision = { status = "AVOID", buyable = false, reasons = { "demand_limit" } } }, true)

    local list = api.renderList()
    assert.equal(2, #list)
    assert.equal(1, list[1].itemID)
    -- It is not hidden, so it is not part of the number that explains a shorter list.
    assert.equal(0, upvalue(api.renderList, "refusedCount"))
    api.refreshRows()
    assert.equal("AVOID", api.rows[1].buy.label)
  end)

  -- Sniper phase 2. A realm lot is never buyable and never will be, but a check that found one
  -- under its region reference did not REFUSE it -- it is the offer. Pruned as a refusal, every
  -- realm row left the board at the exact moment its own check finally had something to say.
  it("keeps an unverified realm row the check found a lot for, and does not count it as refused", function()
    local api = loadSniper(safe)
    local d = deal(1, 100)
    board(api, { d, deal(2, 200) })
    local finish = upvalue(api.GC.Sniper.OnItemSearchResults, "finishRequery")
    local stamp = upvalue(upvalue(finish, "applyRequeryResult"), "stampVerdict")

    stamp(d, { isCommodity = false, decision = {
      status = "WATCH", buyable = false, reasons = { "realm_item_unverified" },
      candidate = { auctionID = 7, buyout = 90, itemLevel = 623, quantity = 1 },
    } })

    local list = api.renderList()
    assert.equal(2, #list)
    assert.equal(0, upvalue(api.renderList, "refusedCount"))
    assert.is_true(api.verdicts[1].unverified)
    assert.is_false(api.verdicts[1].buyable)

    -- A realm check that found nothing to buy IS a refusal, and prunes like any other.
    stamp(d, { isCommodity = false, decision = {
      status = "AVOID", buyable = false, reasons = { "no_comparable_lot" },
    } })
    assert.equal(1, #api.renderList())
    assert.equal(1, upvalue(api.renderList, "refusedCount"))
  end)

  it("does not let a background re-check quietly hide what the player kept", function()
    local api = loadSniper(avoid)
    local d = deal(1, 100)
    board(api, { d })
    local finish = upvalue(api.GC.Sniper.OnItemSearchResults, "finishRequery")
    local stamp = upvalue(upvalue(finish, "applyRequeryResult"), "stampVerdict")
    stamp(d, { isCommodity = true, levels = {},
      decision = { status = "AVOID", buyable = false, reasons = { "demand_limit" } } }, true)
    assert.equal(1, #api.renderList())

    -- 30s later the walk re-checks it (it is still on screen) and gets the same refusal.
    tickAt(api, 140)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal(1, #api.renderList())
  end)

  it("stops keeping it once the asking price moves -- that is a different offer", function()
    local api = loadSniper(avoid)
    local d = deal(1, 100)
    board(api, { d })
    local finish = upvalue(api.GC.Sniper.OnItemSearchResults, "finishRequery")
    local stamp = upvalue(upvalue(finish, "applyRequeryResult"), "stampVerdict")
    stamp(d, { isCommodity = true, levels = {},
      decision = { status = "AVOID", buyable = false, reasons = { "demand_limit" } } }, true)

    board(api, { deal(1, 90) }) -- somebody undercut: a new price is a new question
    assert.equal(1, #api.renderList())
    tickAt(api, 102)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.equal(0, #api.renderList()) -- checked in the background, refused, pruned
  end)

  it("throws every verdict away when the auction house closes", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100) })
    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)
    assert.is_table(api.verdicts[1])

    api.GC.Sniper.OnAuctionHouseClosed()
    assert.is_nil(api.verdicts[1])
  end)

  it("records a vanished listing as refused rather than as still buyable", function()
    local api = loadSniper(safe)
    board(api, { deal(1, 100) })
    tickAt(api, 101)
    -- No commodity book comes back: the listing is gone or was repriced out of the results.
    set(api.GC.Sniper.OnItemKeyInfo, "driver", {
      isReady = function() return true end,
      getKeyInfo = function() return { isCommodity = true } end,
      sendSearch = function(itemID) sent[#sent + 1] = itemID end,
      commodityBook = function() return nil end,
      commodityResult = function() return nil end,
      itemResult = function() return nil end,
    })
    api.GC.Sniper.OnCommoditySearchResults(1)

    assert.is_false(api.verdicts[1].buyable)
    assert.equal("Gone", api.verdicts[1].status)
    assert.equal(0, #api.renderList())
  end)

  -- The board empties in bursts, because the walk competes for one throttled slot and a run of
  -- refusals therefore lands together. Before this, nothing on screen accounted for it -- the
  -- explanation was a number on a toolbar button nobody was watching -- so a shrinking list
  -- read as the addon losing deals rather than as it refusing them.
  it("says so on the status line when a live check takes a row off the board", function()
    local api = loadSniper(avoid)
    local said = {}
    set(api.GC.Sniper.OnAuctionHouseShow, "frame", {
      IsShown = function() return true end, Hide = function() end,
      status = { SetText = function(_, text) said[#said + 1] = text end },
    })
    board(api, { deal(1, 100) })

    tickAt(api, 101)
    api.GC.Sniper.OnCommoditySearchResults(1)

    assert.equal(1, upvalue(api.renderList, "refusedCount"))
    local told = false
    for _, text in ipairs(said) do
      if text:find("1", 1, true) and text:find("hidden", 1, true) then told = true end
    end
    assert.is_true(told)
  end)

  -- A Check the player ran themselves never removes its own row, so announcing a removal for
  -- one would be describing something that did not happen.
  it("stays quiet about a refusal the player asked for themselves", function()
    local api = loadSniper(avoid)
    local said = {}
    set(api.GC.Sniper.OnAuctionHouseShow, "frame", {
      IsShown = function() return true end, Hide = function() end,
      status = { SetText = function(_, text) said[#said + 1] = text end },
    })
    board(api, { deal(1, 100) })
    local finish = upvalue(api.GC.Sniper.OnItemSearchResults, "finishRequery")
    local stamp = upvalue(upvalue(finish, "applyRequeryResult"), "stampVerdict")

    stamp(deal(1, 100), { isCommodity = true, decision = avoid() }, true)

    for _, text in ipairs(said) do
      assert.is_nil(text:find("hidden", 1, true))
    end
  end)

  -- An unverified row shows a tier, a discount and a profit, every one of them read off the
  -- imported market snapshot rather than confirmed against the live auction house. The only
  -- thing that separated it from a row a live check HAD approved was the word on the button,
  -- which is too thin a line for that difference to rest on. Pinned as source text because the
  -- branch lives in createRow's OnEnter, which needs the whole themed widget tree to reach.
  it("tells the tooltip when nothing has checked the row yet", function()
    local file = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = file:read("*a")
    file:close()
    local from = assert(text:find("local verdict = verdictFor(self.deal)", 1, true))
    local to = assert(text:find("if self.deal.pinPlaceholder then", from, true))
    local branch = text:sub(from, to)

    assert.is_truthy(branch:find("GoldCap: checked live -- safe to buy", 1, true))
    -- The third state, the one that used to render as silence.
    assert.is_truthy(branch:find("not checked against the live auction house yet", 1, true))
    -- A pin that is not currently a deal has nothing to check, so it must not be told it is
    -- unchecked -- its own line below says what it actually is.
    assert.is_truthy(branch:find("elseif not self.deal.pinPlaceholder then", 1, true))
  end)

  it("buys nothing: the verify path holds no purchase call and no click handler", function()
    local file = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = file:read("*a")
    file:close()
    -- Anchored at the stand-down predicate, not at tickAutoVerify: the walk was split so the
    -- slot arbiter could take a turn with it, and tickAutoVerify is now the SHORTER half,
    -- below stepVerifyWalk in the file. Slicing from it would have left this test passing
    -- while covering none of the code it exists to police.
    local from = assert(text:find("local function verifyWalkStandsDown()", 1, true))
    local to = assert(text:find("-- Router functions the Init.lua event frame dispatches into.", from, true))
    local walk = text:sub(from, to)
    assert.is_truthy(walk:find("local function stepVerifyWalk()", 1, true))
    assert.is_truthy(walk:find("local function tickAutoVerify()", 1, true))

    assert.is_nil(walk:find("C_AuctionHouse.StartCommoditiesPurchase", 1, true))
    assert.is_nil(walk:find("C_AuctionHouse.ConfirmCommoditiesPurchase", 1, true))
    assert.is_nil(walk:find("C_AuctionHouse.PlaceBid", 1, true))
    assert.is_nil(walk:find("openDialog", 1, true))
    assert.is_nil(walk:find("onBuyClick", 1, true))
  end)

  -- The toolbar toggle is built inside createFrame, which needs the whole themed widget tree;
  -- spec/loadorder_spec.lua already constructs it for real through the stubbed CreateFrame.
  -- What is worth pinning here is that it is wired to the same two things these tests drive:
  -- the persisted setting renderList reads, and the count renderList writes.
  it("wires the toolbar toggle to the setting and the count", function()
    local file = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = file:read("*a")
    file:close()
    local from = assert(text:find("local verifyBtn = Theme.Button", 1, true))
    local to = assert(text:find("-- The \"Live\" button is gone.", from, true))
    local toolbar = text:sub(from, to)

    assert.is_truthy(toolbar:find("cfg.showRefused = not showRefused()", 1, true))
    assert.is_truthy(toolbar:find("refreshRows()", 1, true))
    assert.is_truthy(toolbar:find("refusedCount", 1, true))
    assert.is_truthy(toolbar:find("SetVariant", 1, true))
  end)
end)
