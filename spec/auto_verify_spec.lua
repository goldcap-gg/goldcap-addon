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
    return w
  end

  -- Enough of a pooled row for the real setRowDeal/refreshRows to run against. The flash
  -- animation is deliberately absent: flashRow returns early without one, which keeps the
  -- ping tests about the SOUND (the observable part) rather than about an animation stub.
  local function fakeRow()
    local row = {
      buy = widget(), tierChip = widget(), icon = widget(), nameText = widget(),
      discountText = widget(), unitText = widget(), priceText = widget(),
      profitText = widget(), trendText = widget(), highlight = widget(),
      shown = false,
    }
    function row:Show() self.shown = true end
    function row:Hide() self.shown = false end
    function row:IsShown() return self.shown end
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

    local GC = {
      Theme = {
        ROW_H = 20,
        pad = { m = 8, s = 4, xs = 2 },
        tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
        color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 } },
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
      FullScan = {},
      Print = function() end,
      db = { settings = { sniper = { sound = true, showRefused = false } } },
    }
    helper.loadModule("UI/SniperFrame.lua", GC)

    local show = GC.Sniper.OnAuctionHouseShow
    local api = {
      GC = GC,
      tick = upvalue(show, "tickAutoVerify"),
      refreshRows = upvalue(show, "refreshRows"),
    }
    api.renderList = upvalue(api.tick, "renderList")
    api.verdicts = upvalue(api.tick, "verdicts")
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

  it("never looks past the top rows", function()
    local api = loadSniper(safe)
    local deals = {}
    for i = 1, 12 do deals[i] = deal(i, i * 100) end
    board(api, deals)

    for i = 1, 12 do
      tickAt(api, 100 + i)
      api.GC.Sniper.OnCommoditySearchResults(sent[#sent])
    end
    assert.equal(8, #sent)
    for i = 1, 8 do assert.equal(i, sent[i]) end
  end)

  it("stands down for the auction house, the tab, the window and the search slot", function()
    local api = loadSniper(safe)
    local show = api.GC.Sniper.OnAuctionHouseShow
    board(api, { deal(1, 100) })

    set(show, "ahOpen", false)
    tickAt(api, 101)
    assert.same({}, sent)
    set(show, "ahOpen", true)

    set(api.tick, "view", "sell")
    tickAt(api, 102)
    assert.same({}, sent)
    set(api.tick, "view", "deals")

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
    assert.equal(0, #api.renderList())
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

  it("buys nothing: the verify path holds no purchase call and no click handler", function()
    local file = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
    local text = file:read("*a")
    file:close()
    local from = assert(text:find("local function tickAutoVerify()", 1, true))
    local to = assert(text:find("-- Router functions the Init.lua event frame dispatches into.", from, true))
    local walk = text:sub(from, to)

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
