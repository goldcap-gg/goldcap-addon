local helper = require("spec.spec_helper")

-- The variant drill (owner report, live, 2026-09-22). The Items board carried "Teebu's
-- Scorching Straight Sword x1 of 2, 250000g" while Blizzard's own browse showed TWO item-level
-- variants of item 159840: a (66) asking 211,111 and a (19) asking 250,000. The drill sent a
-- BARE item key -- C_AuctionHouse.MakeItemKey(itemID), item level 0 -- which resolves to one
-- variant server-side, and read the results back with the same bare key, so GC.Caps.DecideRealm
-- and GC.SniperDecision.EvaluateRealm only ever saw the variant the server happened to pick.
--
-- The key poll already sees every variant (Core/KeyPoll.lua's collapse keeps their rows on the
-- book entry). These are the two seams that have to use them: driver.sendSearch picks the key,
-- driver.itemLots/itemResult read with the key that was sent and no other.
describe("Variant drill", function()
  local values, searched, results

  local function upvalue(fn, wanted)
    for i = 1, 200 do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if name == wanted then return value end
    end
    error("missing upvalue " .. wanted)
  end

  -- The client's own identity for an item key: four numbers, and results are answered for the
  -- key a query was sent with, not for the item.
  local function keyID(key)
    return ("%d:%d:%d:%d"):format(key.itemID, key.itemLevel or 0, key.itemSuffix or 0,
      key.battlePetSpeciesID or 0)
  end

  local function variantRow(itemID, itemLevel, minPrice, totalQuantity)
    return {
      itemKey = { itemID = itemID, itemLevel = itemLevel, itemSuffix = 0, battlePetSpeciesID = 0 },
      minPrice = minPrice,
      totalQuantity = totalQuantity or 1,
    }
  end

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
    _G.Enum = { ItemClass = { Tradegoods = 7, Consumable = 0, Gem = 3, ItemEnhancement = 8 },
      AuctionHouseSortOrder = { Buyout = 4 } }
    searched, results = {}, {}
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return true end,
      GetBrowseResults = function() return {} end,
      SearchForItemKeys = function() end,
      -- The real constructor's contract: itemLevel/itemSuffix/battlePetSpeciesID are optional
      -- and default to 0 (API_C_AuctionHouse.MakeItemKey).
      MakeItemKey = function(itemID, itemLevel, itemSuffix, battlePetSpeciesID)
        return { itemID = itemID, itemLevel = itemLevel or 0, itemSuffix = itemSuffix or 0,
          battlePetSpeciesID = battlePetSpeciesID or 0 }
      end,
      GetItemKeyInfo = function() return { isCommodity = false } end,
      SendSearchQuery = function(key) searched[#searched + 1] = key end,
      GetNumItemSearchResults = function(key) return #(results[keyID(key)] or {}) end,
      GetItemSearchResultInfo = function(key, index) return (results[keyID(key)] or {})[index] end,
      GetNumCommoditySearchResults = function() return 0 end,
      GetCommoditySearchResultInfo = function() return nil end,
    }

    values = {}
    local GC = { db = { commodityByItem = {}, settings = { sniper = { sound = true, showRefused = false,
      board = "items",
      minimumProfitCopper = 50000, minimumRoi = 0.10, watchDiscount = 0.10,
      suspectDiscount = 0.90, hotDiscount = 0.40, hotProfit = 500000,
      goodDiscount = 0.25, goodProfit = 100000, hotMinSold = 3, goodMinSold = 1,
      dumpTrendPct = 10, watchPins = {} } } } }
    helper.loadModule("Core/Book.lua", GC)
    helper.loadModule("Core/SniperDecision.lua", GC)
    helper.loadModule("Core/DealMath.lua", GC)
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/FullScan.lua", GC)
    helper.loadModule("Core/BookPass.lua", GC)
    helper.loadModule("Core/DrillQueue.lua", GC)
    helper.loadModule("Core/KeyPoll.lua", GC)
    helper.loadModule("Core/WatchSet.lua", GC)
    helper.loadModule("Core/AutoScan.lua", GC)
    helper.loadModule("Core/Caps.lua", GC)
    GC.Theme = { ROW_H = 20, RAIL_W = 76, pad = { m = 8, s = 4, xs = 2 },
      tier = { HOT = { 1, 1, 1 }, GOOD = { 1, 1, 1 }, WATCH = { 1, 1, 1 } },
      color = { green = { 0, 1, 0 }, red = { 1, 0, 0 }, fgDim = { 0.5, 0.5, 0.5 },
        fgMuted = { 0.72, 0.71, 0.69 }, fg = { 0.92, 0.91, 0.89 },
        gold = { 0.83, 0.64, 0.22 }, watch = { 0.35, 0.72, 0.90 } } }
    GC.Data = {
      GetItemValue = function(itemID) return values[itemID] end,
      GetWatchlist = function() return {} end,
      TargetIds = function() return {} end,
    }
    GC.Sell = { Refresh = function() end, Reset = function() end, Hide = function() end, Show = function() end }
    GC.Print = function() end
    GC.AuctionHouseTab = { PlayerIsBusy = function() return false end }
    helper.loadModule("UI/SniperFrame.lua", GC)
    return GC
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer = nil, nil, nil, nil, nil
    _G.C_AuctionHouse, _G.Enum, _G.GoldCap_AppRuns = nil, nil, nil
  end)

  local function driverOf(GC) return upvalue(GC.Sniper.OnItemKeyInfo, "driver") end

  local function adoptCap(GC, itemID, c, l)
    _G.GoldCap_AppRuns = { v = 3, generatedAt = 1, groups = {},
      caps = { { i = itemID, c = c, l = l or 0 } } }
    GC.Caps.Adopt()
  end

  -- The live board row: both of Teebu's variants, as SearchForItemKeys answered for them.
  local function foldTeebus(GC)
    GC.Sniper._keyPoll:Fold({ variantRow(159840, 19, 250000, 2), variantRow(159840, 66, 211111, 1) })
  end

  local function lot(auctionID, itemLevel, buyout)
    return { auctionID = auctionID, buyoutAmount = buyout, quantity = 1,
      itemKey = { itemID = 159840, itemLevel = itemLevel } }
  end

  it("searches the cheapest variant's own key, not a bare one", function()
    local GC = loadSniper()
    foldTeebus(GC)

    driverOf(GC).sendSearch(159840)

    assert.equal(1, #searched)
    assert.same({ itemID = 159840, itemLevel = 66, itemSuffix = 0, battlePetSpeciesID = 0 },
      searched[1])
  end)

  it("reads the lots back with the key it searched with", function()
    local GC = loadSniper()
    foldTeebus(GC)
    -- The client answers for the (66) key alone, exactly as it does for a real query: the bare
    -- key's slot is left empty, so a read on it is the silence the old drill mistook for facts.
    results["159840:66:0:0"] = { lot(1, 66, 211111) }
    results["159840:0:0:0"] = { lot(2, 19, 250000) }

    local driver = driverOf(GC)
    driver.sendSearch(159840)
    local lots = driver.itemLots(159840)

    assert.equal(1, #lots)
    assert.equal(211111, lots[1].buyout)
    assert.equal(66, lots[1].itemLevel)
    -- The same key for the probe evaluateLiveItemDeal gates on -- read with the bare key it
    -- would answer for the other variant's lot, or for nothing at all.
    assert.equal(211111, driver.itemResult(159840).unitPrice)
  end)

  -- The floor the drill aims above is the one the decision it feeds will apply: a cap's own `l`
  -- (Core/Caps.lua's DecideRealm) ahead of the realm reference's refIlvl
  -- (GC.SniperDecision.EvaluateRealm).
  it("aims at the cheapest variant the cap's item-level floor allows", function()
    local GC = loadSniper()
    adoptCap(GC, 159840, 300000, 66)
    foldTeebus(GC)

    driverOf(GC).sendSearch(159840)

    assert.equal(66, searched[1].itemLevel)
  end)

  it("aims at the cheapest variant the realm reference's item level allows", function()
    local GC = loadSniper()
    values[300] = { kind = "realm_item", source = "import", mv = 250000, ref = 200000, refIlvl = 66 }
    GC.Sniper._keyPoll:Fold({ variantRow(300, 19, 100000, 1), variantRow(300, 66, 211111, 1) })

    driverOf(GC).sendSearch(300)

    -- The 19 is cheaper and EvaluateRealm would refuse it as no_comparable_lot; drilling it
    -- spends the one throttled search slot on an answer that cannot be acted on.
    assert.equal(66, searched[1].itemLevel)
  end)

  -- An item the key poll has never folded has no variants to choose between: the wide browse
  -- pass fills the BOOK PASS's book (Core/BookPass.lua), and its rows reach the drill queue
  -- without ever passing through this poll. Those keep the bare key -- one variant of an item
  -- nothing knows the shape of is still better than no drill at all.
  it("keeps the bare key for an item the poll has never folded", function()
    local GC = loadSniper()

    local driver = driverOf(GC)
    driver.sendSearch(4242)
    driver.itemLots(4242)

    assert.same({ itemID = 4242, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 },
      searched[1])
  end)

  -- Every variant below the cap's floor: there is nothing here the player's own price can
  -- approve, and the cap says so itself. The drill still goes out -- on the cheapest variant,
  -- never on a bare key -- because a Check the player asked for is waiting on this search and
  -- the honest answer names the lots that do exist.
  it("drills the cheapest variant when none reaches the cap's floor, and the cap approves none", function()
    local GC = loadSniper()
    adoptCap(GC, 159840, 300000, 610)
    foldTeebus(GC)
    results["159840:66:0:0"] = { lot(1, 66, 211111) }

    local driver = driverOf(GC)
    driver.sendSearch(159840)

    assert.equal(66, searched[1].itemLevel)
    assert.is_nil(GC.Caps.DecideRealm(GC.Caps.For(159840), driver.itemLots(159840)))
  end)
end)
