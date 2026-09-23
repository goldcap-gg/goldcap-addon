local helper = require("spec.spec_helper")

-- The Deals view's two boards (0.9.2). Commodities is the browse scan's own store: region
-- priced, live-verifiable, the only rows a Check can ever approve for buying. Items is the key
-- poll's: gear, pets and recipes measured against the region reference the import carries,
-- leads that can only ever be WATCH.
--
-- They were one list, and one list could not serve both. A realm lead is worth five figures
-- where a reagent flip is worth three, so the shared profit sort put realm rows on top and the
-- shared hundred-row cap evicted the commodities under them -- "fewer commodities than before
-- 0.9.0", measured on the owner's own board. These tests pin the separation itself: neither
-- store may leak onto the other's board, whatever the sort or the mode.
describe("Deals boards: commodities and items", function()
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

  local function deal(itemID, profit)
    return { itemID = itemID, unitPrice = 100, qty = 1, avail = 10,
      profit = profit or 1000, estProfit = profit or 1000, discount = 0.5, tier = "GOOD",
      stale = true, action = "Check", status = "WATCH", reason = "live_verification_required" }
  end

  -- Enough of a pooled row for the real setRowDeal to run against, copied from
  -- spec/auto_verify_spec.lua rather than shared -- per the addon's engineering notes' note on this pattern,
  -- a per-spec double keeps one spec's construction needs from perturbing another's.
  local function widget()
    local w = {}
    function w:SetText() end
    function w:SetTextColor() end
    function w:SetTexture() end
    function w:SetLabel(label) self.label = label end
    function w:SetVariant(name) self.variant = name end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetColorTexture(r, g, b) self.rgb = { r, g, b } end
    function w:Enable() self.enabled = true end
    function w:Disable() self.enabled = false end
    return w
  end

  local function fakeRow()
    local row = {
      buy = widget(), tierChip = widget(), icon = widget(), nameText = widget(),
      discountText = widget(), unitText = widget(), priceText = widget(),
      profitText = widget(), trendText = widget(), highlight = widget(), rail = widget(),
      pinBg = widget(), shown = false,
    }
    function row:Show() self.shown = true end
    function row:Hide() self.shown = false end
    function row:IsShown() return self.shown end
    function row:SetAlpha(a) self.alpha = a end
    return row
  end

  -- Loads the real UI/SniperFrame.lua and hands back the board's own read path. Same seam every
  -- other SniperFrame spec uses (see the addon's engineering notes): the module's state is chunk-level
  -- locals, and every closure in the chunk shares one upvalue cell per local, so setting it
  -- through any function that reaches it sets it for all of them.
  local function loadSniper()
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.GetMoney = function() return 10 * 1000 * 10000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.PlaySound = function() end
    _G.SOUNDKIT = { READY_CHECK = 8960, MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return false end,
      GetBrowseResults = function() return {} end,
    }

    local GC = {
      Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
        tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
          fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 },
          gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } } },
      AutoScan = { New = function()
        return { Input = function() end, State = function() return "OFF" end,
          PauseReasons = function() return {} end, Tick = function() end }
      end },
      Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end,
        OriginState = function() return "manual" end,
        FactItemIds = function() return { 10 } end },
      Scanner = { New = function() return { Start = function() end, Stop = function() end } end },
      Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end },
      SniperDecision = { Evaluate = function() return {} end, MarketFromValue = function() return {} end,
        ReasonText = function(token) return tostring(token) end },
      FullScan = {
        RowsFromBrowse = function() return {} end,
        EvaluateDelta = function() return {}, 0, 0 end,
        CollectNewHot = function() return {} end,
        MergeDeals = function(existing) return existing end,
        CapDeals = function(deals) return deals end,
      },
      WatchSet = { Observe = function() end, Select = function() return {} end },
      -- Enough for anyItemArmed() to say yes, so the commodity board's empty state reaches its
      -- own "nothing scanned yet" sentence rather than stopping at "import to arm the sniper".
      Trigger = { AnyArmed = function() return true end,
        RealmReference = function(value) return value and value.ref end },
      Print = function() end,
      db = {
        settings = { sniper = { sound = false, showRefused = false, watchPins = {} } } },
    }
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/Util.lua", GC)
    helper.loadModule("Core/BoardRows.lua", GC)
    helper.loadModule("UI/SniperFrame.lua", GC)

    local show = GC.Sniper.OnAuctionHouseShow
    local api = { GC = GC, refreshRows = upvalue(show, "refreshRows") }
    api.renderList = upvalue(api.refreshRows, "renderList")
    -- The walk's slice asks the client which rows are commodities; nothing here is about that
    -- split, so answer "not cached yet" for everything.
    set(GC.Sniper.OnItemKeyInfo, "driver", { getKeyInfo = function() return nil end })
    set(show, "mode", "fullscan")
    -- refreshRows needs somewhere to render: a scroll child to stamp a height on, a row
    -- factory, and a frame (it early-returns without one). Rows are never read here -- the
    -- board itself is renderList's return value and the slice it publishes.
    set(api.refreshRows, "content", { SetHeight = function() end })
    set(api.refreshRows, "createRow", fakeRow)
    api.scrolledTo = nil
    set(show, "frame", {
      scroll = { SetVerticalScroll = function(_, value) api.scrolledTo = value end },
      emptyText = { SetText = function(_, text) api.emptyText = text end,
        Show = function() end, Hide = function() api.emptyText = nil end },
    })
    api.setScanDeals = function(list) set(show, "scanDeals", list) end
    return api
  end

  local function ids(list)
    local out = {}
    for i = 1, #list do out[#out + 1] = list[i].itemID end
    table.sort(out)
    return out
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.C_AuctionHouse = nil
  end)

  it("shows the scan's own deals on Commodities and never a realm row", function()
    local api = loadSniper()
    api.setScanDeals({ deal(10, 5000), deal(11, 4000) })
    api.GC.Sniper._realmDeals[900] = deal(900, 9000000) -- a five-figure lead

    assert.same({ 10, 11 }, ids(api.renderList()))
  end)

  it("shows the key poll's own deals on Items and never a commodity", function()
    local api = loadSniper()
    api.setScanDeals({ deal(10, 5000), deal(11, 4000) })
    api.GC.Sniper._realmDeals[900] = deal(900, 9000000)
    api.GC.Sniper._realmDeals[901] = deal(901, 8000000)

    api.GC.Sniper._SetBoard("items")

    assert.same({ 900, 901 }, ids(api.renderList()))
  end)

  -- The commodity board has two backing stores (the watchlist map and the scan's array, picked
  -- by `mode`); the Items board has one, and the poll answers whether or not a scan has ever
  -- run. Gating it on `mode` would show an empty board with rows in hand.
  it("shows the Items board in watchlist mode too", function()
    local api = loadSniper()
    set(api.GC.Sniper.OnAuctionHouseShow, "mode", "watchlist")
    api.GC.Sniper._realmDeals[900] = deal(900, 9000000)

    api.GC.Sniper._SetBoard("items")
    assert.same({ 900 }, ids(api.renderList()))

    api.GC.Sniper._SetBoard("commodities")
    assert.same({}, ids(api.renderList()))
  end)

  it("remembers the board it was left on, and refuses a board that does not exist", function()
    local api = loadSniper()
    api.GC.Sniper._SetBoard("items")
    assert.equal("items", api.GC.db.settings.sniper.board)
    assert.equal("items", api.GC.Sniper._Board())

    api.GC.Sniper._SetBoard("gear")
    assert.equal("commodities", api.GC.db.settings.sniper.board)
  end)

  -- Seen in game 2026-09-15: sat on Commodities, switched to Items, the board polled its set
  -- once and then stood still. The cycle only ever restarted when a book pass began, and the
  -- pass is paused for as long as Items is on screen.
  it("starts the next poll cycle itself on the Items board, after a breather", function()
    local api = loadSniper()
    local sent = {}
    _G.C_AuctionHouse.MakeItemKey = function(id) return { itemID = id } end
    _G.C_AuctionHouse.SearchForItemKeys = function(keys) sent[#sent + 1] = #keys end
    -- The spec's driver stub knows only getKeyInfo; the batch sender asks the throttle too.
    set(api.GC.Sniper.OnItemKeyInfo, "driver", { getKeyInfo = function() return nil end,
      isReady = function() return true end, claimSend = function() return true end })
    local clock = 1000
    _G.time = function() return clock end
    api.GC.Sniper._keyPoll:SetTargets({ 11, 12, 13 })
    set(api.GC.Sniper.OnAuctionHouseShow, "view", "deals")
    api.GC.Sniper._SetBoard("items")
    -- The switch itself sends the first batch; its answer exhausts the cycle.
    assert.same({ 3 }, sent)
    api.GC.Sniper._keysAwaiting = nil
    api.GC.Sniper._keyPoll:Fold({})
    api.GC.Sniper._keysCycleDoneAt = clock
    -- Inside the breather nothing goes out, however often the board asks.
    clock = clock + 2
    assert.is_false(api.GC.Sniper._TrySendKeysBatch())
    assert.same({ 3 }, sent)
    -- Past it, a new cycle begins and the set is visited again.
    clock = clock + 4
    assert.is_true(api.GC.Sniper._TrySendKeysBatch())
    assert.same({ 3, 3 }, sent)
    -- And not on the Commodities board, where the pass owns the buffer.
    api.GC.Sniper._keysAwaiting = nil
    api.GC.Sniper._keyPoll:Fold({})
    api.GC.Sniper._keysCycleDoneAt = clock
    api.GC.Sniper._SetBoard("commodities")
    clock = clock + 10
    assert.is_false(api.GC.Sniper._TrySendKeysBatch())
    assert.same({ 3, 3 }, sent)
  end)

  -- A different board is a different list: the offset the player had scrolled to describes
  -- rows that are not there any more.
  it("puts the scroll back to the top when the board changes", function()
    local api = loadSniper()
    api.GC.Sniper._SetBoard("items")
    assert.equal(0, api.scrolledTo)
  end)

  -- The count is the whole reason the switch is worth having while the player is on
  -- Commodities: it says how much is waiting on the other board without moving any of it here.
  it("counts the Items store for the chip, and says nothing numeric when it is empty", function()
    local api = loadSniper()
    assert.equal(0, api.GC.Sniper._RealmCount())
    api.GC.Sniper._realmDeals[900] = deal(900)
    api.GC.Sniper._realmDeals[901] = deal(901)
    assert.equal(2, api.GC.Sniper._RealmCount())
  end)

  -- Both boards are rendered by the same code, so everything downstream of the store -- the
  -- refused-rows filter, the "N hidden" count, the walk's slice, the "…" markers -- describes
  -- whichever one is up. This is the observable half of that: the slice the render publishes.
  it("publishes the visible board's own rows as the verify walk's slice", function()
    local api = loadSniper()
    api.setScanDeals({ deal(10, 5000) })
    api.GC.Sniper._realmDeals[900] = deal(900, 9000000)

    api.refreshRows()
    assert.same({ 10 }, ids(api.GC.Sniper._verifySlice))

    api.GC.Sniper._SetBoard("items")
    assert.same({ 900 }, ids(api.GC.Sniper._verifySlice))
  end)

  -- A pin is a standing instruction and gets a dimmed row wherever its item is not currently a
  -- deal, so it can always be right-clicked off. It belongs to ONE board: a pinned piece of
  -- gear used to place that twin on the commodity board too, which is the mixing the split
  -- exists to end.
  it("places a pin's own placeholder on its own board only", function()
    local api = loadSniper()
    api.GC.Data.GetItemValue = function(itemID)
      if itemID == 900 then
        return { kind = "realm_item", source = "import", mv = 200000, ref = 180000 }
      end
      return nil
    end
    api.GC.db.settings.sniper.watchPins = { 10, 900 } -- one commodity, one piece of gear

    assert.same({ 10 }, ids(api.renderList()))

    api.GC.Sniper._SetBoard("items")
    assert.same({ 900 }, ids(api.renderList()))
  end)

  describe("the empty state", function()
    local function emptyText(api)
      api.GC.Sniper._UpdateEmptyState(0)
      return api.emptyText
    end

    it("tells the Items board why it is empty, in its own terms", function()
      local api = loadSniper()
      api.GC.Sniper._SetBoard("items")
      api.GC.Sniper._keyPoll:SetTargets({ 900, 901 })

      local text = emptyText(api)
      assert.is_truthy(text:find("No gear, pets or recipes under their region price", 1, true))
    end)

    -- Caps fixes 4a: the player's caps left the realm poll for a poll of their own, so an empty
    -- realm poll no longer means nothing on this board is being watched.
    it("does not call a board with a capped realm item on it unwatched", function()
      local api = loadSniper()
      api.GC.Sniper._SetBoard("items")
      api.GC.Sniper._keyPoll:SetTargets({})
      api.GC.Caps = { Count = function() return 2 end, Targets = function() return { 10, 900 } end }
      api.GC.db.commodityByItem = { [10] = true }

      local text = emptyText(api)
      assert.is_nil(text:find("Nothing to watch on this board yet.", 1, true))

      -- Commodity caps alone do not count: they are the other board's.
      api.GC.Caps.Targets = function() return { 10 } end
      assert.is_truthy(emptyText(api):find("Nothing to watch on this board yet.", 1, true))
    end)

    it("says the import carries nothing to watch when the poll set is empty", function()
      local api = loadSniper()
      api.GC.Sniper._SetBoard("items")
      api.GC.Sniper._keyPoll:SetTargets({})

      local text = emptyText(api)
      assert.is_truthy(text:find("Nothing to watch on this board yet.", 1, true))
    end)

    -- The commodity story ("press Scan", the pre-screen counts, the refusals) is not true of
    -- the Items board and must not be told there -- nor may the Items story appear here.
    it("keeps the commodity board's own explanations", function()
      local api = loadSniper()
      local text = emptyText(api)
      assert.is_truthy(text:find("No deals yet.", 1, true))
      assert.is_nil(text:find("gear, pets", 1, true))
    end)
  end)
end)
