local helper = require("spec.spec_helper")

-- The line beside AUTO on the Deals tab (owner, 2026-10-09): under Auto on a small auction house a
-- pass ends every second or two, and the line swapped between a page count and a sentence each
-- time, faster than it could be read. It says three numbers now, once a pass ends, in the same
-- places every time; the light beside AUTO says the addon is working.
describe("the Deals readout", function()
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

  local results, complete

  local function browseRow(itemID, minPrice)
    return { itemKey = { itemID = itemID }, minPrice = minPrice, totalQuantity = 3 }
  end

  local function widget()
    local w = { shown = true }
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:SetText(text) self.text = text end
    function w:SetTextColor() end
    return w
  end

  -- The window as far as a pass reaches it: the status line keeps every write.
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
    _G.Enum = { ItemClass = { Tradegoods = 7, Consumable = 0, Gem = 3, ItemEnhancement = 8 } }
    results, complete = {}, true
    _G.C_AuctionHouse = {
      IsThrottledMessageSystemReady = function() return true end,
      SendBrowseQuery = function() end,
      RequestMoreBrowseResults = function() end,
      HasFullBrowseResults = function() return complete end,
      GetBrowseResults = function() return results end,
    }
    local GC = { db = { commodityByItem = {}, settings = { sniper = { sound = true, showRefused = false,
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

    local f = widget()
    f.status = widget()
    f.status.writes = {}
    function f.status:SetText(text)
      self.text = text
      self.writes[#self.writes + 1] = text
    end
    set(upvalue(GC.Sniper.SetScanStatus, "setStatus"), "frame", f)
    set(upvalue(GC.Sniper.OnForeverFold, "refreshRows"), "content", { SetHeight = function() end })
    return GC, f.status
  end

  after_each(function()
    _G.GetTime, _G.time, _G.GetMoney, _G.GetCoinTextureString = nil, os.time, nil, nil
    _G.ITEM_QUALITY_COLORS, _G.Item, _G.PlaySound, _G.SOUNDKIT, _G.C_Timer, _G.C_AuctionHouse, _G.Enum =
      nil, nil, nil, nil, nil, nil, nil
  end)

  -- A whole pass: the first page, then the rest, then the end.
  local function pass(GC, pages)
    GC.Sniper._bookPass:Start("classes")
    assert.is_true(GC.Sniper._bookPass:OnThrottleReady())
    for i = 1, #pages do
      for _, row in ipairs(pages[i]) do results[#results + 1] = row end
      complete = i == #pages
      GC.Sniper._bookPass:OnResultsUpdated()
      if not complete then assert.is_true(GC.Sniper._bookPass:OnThrottleReady()) end
    end
    assert.is_false(GC.Sniper._bookPass:IsPaging())
  end

  -- No item here has a price, so the pre-screen filters every one of them.
  it("says deals, items and filtered once a pass ends, and nothing page by page", function()
    local GC, status = loadSniper()
    pass(GC, { { browseRow(1, 100), browseRow(2, 100) }, { browseRow(3, 100) } })
    assert.same({ "scanning auction house...", "deals 0 · items 3 · filtered 3" }, status.writes)
  end)

  it("keeps the last readout up while the next pass runs, and writes the same words when nothing changed", function()
    local GC, status = loadSniper()
    pass(GC, { { browseRow(1, 100) } })
    results = {}
    status.writes = {}
    pass(GC, { { browseRow(1, 100) } })
    assert.same({ "deals 0 · items 1 · filtered 1", "deals 0 · items 1 · filtered 1" }, status.writes)
  end)

  it("puts the next pass's readout over a one-shot message the line was left with", function()
    local GC, status = loadSniper()
    pass(GC, { { browseRow(1, 100) } })
    status:SetText("auto off")
    results = {}
    GC.Sniper._bookPass:Start("classes")
    GC.Sniper._bookPass:OnThrottleReady()
    assert.equal("deals 0 · items 1 · filtered 1", status.text)
  end)

  it("counts the rows the pre-screen filtered, and the keys the poll asked about", function()
    local GC, status = loadSniper()
    GC.FullScan.Evaluate = function() return {}, 2 end
    GC.Sniper._keysLastCycle = 4
    pass(GC, { { browseRow(1, 100), browseRow(2, 100) } })
    assert.equal("deals 0 · items 2 · filtered 2 · 4 keys", status.text)
  end)

  it("puts the deals count in gold once there are any", function()
    local GC, status = loadSniper()
    local found = { itemID = 1, unitPrice = 100, qty = 1, avail = 3, profit = 900000, estProfit = 900000,
      discount = 0.5, tier = "GOOD", status = "WATCH", action = "Check" }
    GC.FullScan.Evaluate = function() return { found }, 0 end
    set(upvalue(GC.Sniper.OnForeverFold, "refreshRows"), "renderList", function() return {} end) -- no rows to draw
    pass(GC, { { browseRow(1, 100) } })
    assert.equal("deals |cfff7cf5a1|r · items 1 · filtered 0", status.text)
  end)

  -- The watch loop re-checks a handful of items on its own, one a second, and said so on the same
  -- line ("scanning 3/7", "stopped", in English) over the readout.
  it("does not let the watch loop's progress onto the line", function()
    local GC, status = loadSniper()
    pass(GC, { { browseRow(1, 100) } })
    local driver = upvalue(GC.Sniper.OnAuctionHouseShow, "driver")
    driver.onStatus("scanning 3/7")
    driver.onStatus("stopped")
    assert.equal("deals 0 · items 1 · filtered 1", status.text)
  end)

  it("says it in the player's language", function()
    local GC, status = loadSniper()
    helper.loadModule("Locale/ruRU.lua", GC)
    GC.ActivateLocale("ruRU")
    pass(GC, { { browseRow(1, 100) } })
    assert.equal("сделки 0 · предметы 1 · отсеяно 1", status.text)
    GC.ActivateLocale(nil)
  end)
end)
