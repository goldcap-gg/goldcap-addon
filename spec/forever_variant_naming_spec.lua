local helper = require("spec.spec_helper")

-- WoW: Forever files an item with random suffixes under one item key per suffix, and its bare key
-- answers no lots at all (probe 08.11): the Deals Check asked Carving Knife's 2140/11/0/0 and was
-- told 0 lots, while Blizzard's own pane asked 2140/11/14315/0 and got 119. A keys batch on the
-- bare key names no suffix; a browse by the item's name names them all. So on Forever the Check and
-- the background walk browse the name first and search the cheapest variant's key after it.
describe("Forever Deals: an item's variant keys learnt by its name", function()
  local searched, browsed, browseRows, timers, clock

  -- C_Timer.After's callbacks, run when the spec says the frame has moved on.
  local function flush()
    local due = timers
    timers = {}
    for _, fn in ipairs(due) do fn() end
  end

  local function upvalue(fn, wanted)
    for i = 1, 200 do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  local function setUpvalue(fn, wanted, value)
    for i = 1, 200 do
      local name = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then debug.setupvalue(fn, i, value); return end
    end
    error("missing upvalue " .. wanted)
  end

  local function key(itemID, itemLevel, itemSuffix)
    return { itemID = itemID, itemLevel = itemLevel or 0, itemSuffix = itemSuffix or 0, battlePetSpeciesID = 0 }
  end

  local function browseRow(itemID, itemLevel, itemSuffix, minPrice, totalQuantity)
    return { itemKey = key(itemID, itemLevel, itemSuffix), minPrice = minPrice, totalQuantity = totalQuantity }
  end

  -- What a browse for "Carving Knife" answered in game, cut down: the bare key with nothing up, a
  -- few suffixes, and an item whose name holds the words.
  local KNIVES = {
    browseRow(2140, 11, 0, 0, 0),
    browseRow(2140, 11, 14322, 400, 3),
    browseRow(2140, 11, 14315, 400, 121),
    browseRow(2140, 11, 14300, 350, 13),
    browseRow(2140, 11, 14307, 2500, 6),
    browseRow(2141, 20, 0, 1, 1),
  }

  local function loadSniper(forever)
    clock, timers = 100, {}
    _G.GetTime = function() return clock end
    _G.time = function() return 1000 end
    _G.GetMoney = function() return 10 * 1000 * 10000 end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.ITEM_QUALITY_COLORS = {}
    _G.Item = { CreateFromItemID = function() return { ContinueOnItemLoad = function() end } end }
    _G.PlaySound = function() end
    _G.SOUNDKIT = { READY_CHECK = 8960, MAP_PING = 3175, RAID_WARNING = 1 }
    _G.C_Timer = {
      -- Only the arbiter's own next turn (GC.Sniper._DeferTurn) is run; the 8 s timeouts are not.
      After = function(seconds, fn) if seconds == 0 then timers[#timers + 1] = fn end end,
      NewTicker = function() return { Cancel = function() end } end,
    }
    _G.Enum = { ItemClass = { Tradegoods = 7, Consumable = 0, Gem = 3, ItemEnhancement = 8 },
      AuctionHouseSortOrder = { Buyout = 4, Price = 0, Name = 1 } }
    searched, browsed, browseRows = {}, {}, {}
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function(query) browsed[#browsed + 1] = query end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return true end,
      GetBrowseResults = function() return browseRows end,
      SearchForItemKeys = function() end,
      MakeItemKey = function(itemID, itemLevel, itemSuffix, battlePetSpeciesID)
        return { itemID = itemID, itemLevel = itemLevel or 0, itemSuffix = itemSuffix or 0,
          battlePetSpeciesID = battlePetSpeciesID or 0 }
      end,
      GetItemKeyInfo = function(k)
        if k.itemID == 2589 then return { isCommodity = true, itemName = "Linen Cloth" } end
        return { isCommodity = false, itemName = "Carving Knife" }
      end,
      SendSearchQuery = function(k) searched[#searched + 1] = k end,
      GetNumItemSearchResults = function() return 0 end,
      GetItemSearchResultInfo = function() return nil end,
      GetNumCommoditySearchResults = function() return 0 end,
      GetCommoditySearchResultInfo = function() return nil end,
    }

    local GC = { db = { commodityByItem = {}, settings = { sniper = { sound = true, showRefused = false,
      board = "items",
      minimumProfitCopper = 50000, minimumRoi = 0.10, watchDiscount = 0.10,
      suspectDiscount = 0.90, hotDiscount = 0.40, hotProfit = 500000,
      goodDiscount = 0.25, goodProfit = 100000, hotMinSold = 3, goodMinSold = 1,
      dumpTrendPct = 10, watchPins = {} } } } }
    for _, m in ipairs({ "Core/Book.lua", "Core/SniperDecision.lua", "Core/DealMath.lua", "Core/Trigger.lua",
      "Core/FullScan.lua", "Core/BookPass.lua", "Core/DrillQueue.lua", "Core/KeyPoll.lua", "Core/WatchSet.lua",
      "Core/AutoScan.lua", "Core/Caps.lua" }) do
      helper.loadModule(m, GC)
    end
    GC.Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
      tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
      color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
        fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 },
        gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } } }
    GC.Data = {
      GetItemValue = function() return nil end,
      GetWatchlist = function() return {} end,
      TargetIds = function() return {} end,
    }
    GC.Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end }
    GC.Print = function() end
    GC.AuctionHouseTab = { PlayerIsBusy = function() return false end }
    helper.loadModule("UI/SniperFrame.lua", GC)
    if forever then helper.loadModule("UI/SniperFrame_Camelot.lua", GC) end
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.C_AuctionHouse, _G.Enum = nil, nil
  end)

  -- The player's Check of a board row (openDialog's own startRequery).
  local function check(GC, itemID)
    local deal = { itemID = itemID, unitPrice = 300, stale = true }
    local row = { deal = deal }
    upvalue(GC.Sniper.OnCommodityPriceUpdated, "startRequery")(row, deal)
    return row
  end

  -- The background walk's, or a hover's, live look at a row (maybeStartPrewarm).
  local function prewarm(GC, itemID)
    local maybeStartPrewarm = upvalue(GC.Sniper._HoverPrewarm, "maybeStartPrewarm")
    setUpvalue(maybeStartPrewarm, "ahOpen", true)
    return maybeStartPrewarm({ itemID = itemID, unitPrice = 300, stale = true }, true)
  end

  it("browses a Check's item by its name first, then searches the cheapest suffix's own key", function()
    local GC = loadSniper(true)
    check(GC, 2140)
    assert.equal(1, #browsed)
    assert.equal("Carving Knife", browsed[1].searchString)
    assert.equal(0, #searched)

    browseRows = KNIVES
    GC.Sniper.OnBrowseResults()
    assert.equal(0, #searched)
    flush() -- the answer asks for the turn that sends the Check; no ready tick is owed after it

    assert.equal(1, #searched)
    assert.same(key(2140, 11, 14300), searched[1])
  end)

  it("drops a written-off keys batch's late answer and waits for its own", function()
    local GC = loadSniper(true)
    GC.Sniper._keysOrphan = { asked = { [555] = true }, untilAt = 1000 }
    check(GC, 2140)
    browseRows = { browseRow(555, 10, 0, 50, 4) }
    GC.Sniper.OnBrowseResults()
    flush()
    assert.equal(0, #searched)
    assert.is_true(GC.Sniper._NamingBusy())

    browseRows = KNIVES
    GC.Sniper.OnBrowseResults()
    flush()
    assert.same(key(2140, 11, 14300), searched[1])
  end)

  it("waits for a page still on the wire, then browses the name", function()
    local GC = loadSniper(true)
    GC.Sniper._browseOutAt = 1000 -- an abandoned pass's last page
    check(GC, 2140)
    assert.equal(0, #browsed)
    assert.equal(0, #searched)

    browseRows = { browseRow(9999, 1, 0, 1, 1) } -- that page lands
    GC.Sniper.OnBrowseResults()
    flush()
    assert.equal(1, #browsed)
    assert.equal(0, #searched)
  end)

  it("asks again when a message was dropped, rather than holding the list for its answer", function()
    local GC = loadSniper(true)
    check(GC, 2140)
    assert.equal(1, #browsed)
    GC.Sniper.OnThrottledMessageDropped()
    assert.equal(2, #browsed)
  end)

  it("holds a second item's Check while the first one's browse is out, and browses it after", function()
    local GC = loadSniper(true)
    check(GC, 2140)
    check(GC, 2142)
    assert.equal(1, #browsed)
    assert.equal(0, #searched)

    browseRows = KNIVES
    GC.Sniper.OnBrowseResults()
    flush()
    GC.Sniper.OnThrottleReady() -- the ready tick after whichever of the two went first
    -- One message a turn, in either order: the first item's suffix searched, the second's name browsed.
    assert.equal(1, #searched)
    assert.same(key(2140, 11, 14300), searched[1])
    assert.equal(2, #browsed)
  end)

  it("browses an item again once a minute has passed", function()
    local GC = loadSniper(true)
    check(GC, 2140)
    browseRows = KNIVES
    GC.Sniper.OnBrowseResults()
    assert.is_false(GC.Sniper._VariantsOwed(2140))
    clock = clock + 61
    assert.is_true(GC.Sniper._VariantsOwed(2140))
  end)

  it("spends the walk's turn on the name, and its next turn on the cheapest suffix", function()
    local GC = loadSniper(true)
    assert.is_true(prewarm(GC, 2140))
    assert.equal(1, #browsed)
    assert.equal(0, #searched)

    browseRows = KNIVES
    GC.Sniper.OnBrowseResults()
    assert.is_true(prewarm(GC, 2140))

    assert.equal(1, #browsed)
    assert.same(key(2140, 11, 14300), searched[1])
  end)

  it("searches a commodity at once, with no browse", function()
    local GC = loadSniper(true)
    GC.Sniper._keyInfoCommodity[2589] = true
    check(GC, 2589)
    assert.equal(0, #browsed)
    assert.equal(1, #searched)
  end)

  it("leaves the bare key to an item the browse found none of, and does not browse it again", function()
    local GC = loadSniper(true)
    check(GC, 2140)
    browseRows = { browseRow(2141, 20, 0, 1, 1) }
    GC.Sniper.OnBrowseResults()
    flush()

    assert.same(key(2140), searched[1])
    assert.is_false(GC.Sniper._VariantsOwed(2140))
  end)

  it("leaves what lands while a scan pages the list to the scan", function()
    local GC = loadSniper(true)
    check(GC, 2140)
    GC.Sniper._bookPass.IsPaging = function() return true end
    browseRows = { browseRow(2141, 20, 0, 1, 1) }

    assert.is_false(GC.Sniper._TakeNaming())
    assert.is_true(GC.Sniper._NamingBusy())
  end)

  it("on retail searches the bare key at once, as before", function()
    local GC = loadSniper(false)
    check(GC, 2140)
    assert.equal(0, #browsed)
    assert.same(key(2140), searched[1])
    assert.is_true(prewarm(GC, 4242))
    assert.equal(0, #browsed)
  end)
end)
