local helper = require("spec.spec_helper")

describe("Book pass wiring", function()
  local function upvalue(fn, wanted)
    for i = 1, math.huge do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  -- Unused by Task 4's own single test below (it only reads GC.Sniper._bookPass, never pokes
  -- an upvalue), but Task 5 extends this same describe block with a test that calls it --
  -- kept here rather than reintroduced there, per this batch's plan.
  -- luacheck: ignore set
  local function set(fn, wanted, value)
    for i = 1, math.huge do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local browseSent, browseQueries

  local function loadSniper()
    browseSent, browseQueries = 0, {}
    _G.GetTime = function() return 100 end
    _G.time = function() return 1000 end
    _G.GetMoney = function() return 10 * 1000 * 10000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.PlaySound = function() end
    _G.SOUNDKIT = { READY_CHECK = 8960, MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
    _G.Enum = { ItemClass = { Tradegoods = 7, Consumable = 0, Gem = 3, ItemEnhancement = 8 } }
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function(query)
        browseSent = browseSent + 1
        browseQueries[#browseQueries + 1] = query
      end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return true end,
      GetBrowseResults = function() return {} end,
    }

    local GC = { db = { settings = { sniper = { sound = true, showRefused = false,
      minimumProfitCopper = 50000, minimumRoi = 0.10 } } } }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/WatchSet.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    GC.Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
      tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
      color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
        fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 },
        gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } } }
    GC.Data = { GetItemValue = function() return nil end, GetWatchlist = function() return {} end }
    GC.Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end }
    GC.Print = function() end
    GC.AuctionHouseTab = { PlayerIsBusy = function() return false end }
    helper.loadModule("UI/SniperFrame.lua", GC)
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.C_AuctionHouse, _G.Enum = nil, nil
  end)

  it("sends a class-filtered query, not an empty one, when Auto starts a fresh pass", function()
    local GC = loadSniper()
    -- Reach the real Core/AutoScan.lua machine the way autoscan_wiring_spec.lua does --
    -- feedAuto is a direct upvalue of OnAuctionHouseShow, autoScan a direct upvalue of
    -- feedAuto -- and drive it without ever building the real frame (Tick's own startScan
    -- action calls the real startFullScan(), whose own refreshRows()/etc. all no-op safely
    -- with `frame` still nil).
    local feedAuto = upvalue(GC.Sniper.OnAuctionHouseShow, "feedAuto")
    local autoScan = upvalue(feedAuto, "autoScan")

    autoScan:Input("toggleOn", 1000)
    autoScan:Tick(1000)
    assert.equal(1, browseSent)
    assert.equal(4, #browseQueries[1].itemClassFilters)
  end)

  it("grants a drill-down before a page even while a book pass is mid-paging", function()
    local GC = loadSniper()
    local searched = {}
    -- Reach the same `driver` the search/purchase path uses (installed at file scope, a
    -- direct upvalue of GC.Sniper.OnItemKeyInfo -- see watch_loop_spec.lua's own use of this
    -- exact upvalue) and swap its sendSearch so a drill-down is observable without a real
    -- item key.
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    driverTbl.getKeyInfo = function() return { isCommodity = true } end
    driverTbl.sendSearch = function(itemID) searched[#searched + 1] = itemID end

    set(GC.Sniper.OnAuctionHouseShow, "ahOpen", true)
    GC.Sniper._drillQueue:Push({ itemID = 777, floor = 100, estProfit = 5000 })
    GC.Sniper.OnThrottleReady()
    assert.same({ 777 }, searched)
    assert.equal(0, browseSent) -- the book pass never even got asked this turn
  end)

  it("sends the book pass's deferred start after a queued drill-down is served", function()
    local GC = loadSniper()
    local driverTbl = upvalue(GC.Sniper.OnItemKeyInfo, "driver")
    driverTbl.getKeyInfo = function() return { isCommodity = true } end
    driverTbl.sendSearch = function() end

    set(GC.Sniper.OnAuctionHouseShow, "ahOpen", true)

    -- Throttle busy at Start() time: the book pass's own send is deferred rather than sent.
    _G.C_AuctionHouse.IsThrottledMessageSystemReady = function() return false end
    GC.Sniper._bookPass:Start("classes")
    assert.equal(0, browseSent)

    -- A slot cycle: throttle is ready again, and a drill-down is queued ahead of the pass.
    _G.C_AuctionHouse.IsThrottledMessageSystemReady = function() return true end
    GC.Sniper._drillQueue:Push({ itemID = 777, floor = 100, estProfit = 5000 })
    GC.Sniper.OnThrottleReady()
    assert.equal(0, browseSent) -- drill-down outranked the page this cycle

    -- Next cycle: the deferred start goes out.
    GC.Sniper.OnThrottleReady()
    assert.equal(1, browseSent)
  end)
end)
