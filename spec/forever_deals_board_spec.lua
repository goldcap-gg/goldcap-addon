local helper = require("spec.spec_helper")

-- Task 4 (3c): the Deals board in WoW: Forever reads GC.ForeverDeals.Rows() instead of the
-- retail stores, and the empty state, the chip and the row tooltip speak of the scan rather
-- than goldcap.gg prices. Per the addon's engineering notes, each spec keeps its own doubles.
describe("WoW: Forever", function()
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
    set(GC.Sniper.OnItemKeyInfo, "driver", { getKeyInfo = function() return nil end })
    set(show, "mode", "fullscan")
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

  local function foreverRow(itemID, board, kind)
    return { itemID = itemID, forever = kind or "vendor", ceiling = 12, refUnit = 13, unitPrice = 8,
      qty = 55, avail = 355, capTotal = 610, mv = 13, discount = 1 - 8 / 13, profit = 105,
      estProfit = 105, isCommodity = board == "commodities", board = board, tier = "WATCH",
      status = "WATCH", reason = "live_verification_required", action = "Check", buyable = false,
      stale = true }
  end

  local function forever(api, rows, fold)
    api.GC.ForeverScan = { Enabled = function() return true end, Fold = function() return fold end }
    api.GC.ForeverDeals = { Rows = function() return rows end, Due = function() return false end }
  end

  it("reads the scan's rows, each on its own board, and nothing from the retail stores", function()
    local api = loadSniper()
    api.setScanDeals({ deal(10, 5000) })
    forever(api, { foreverRow(2589, "commodities"), foreverRow(19019, "items") }, { at = 1 })
    assert.same({ 2589 }, ids(api.renderList()))
    api.GC.Sniper._SetBoard("items")
    assert.same({ 19019 }, ids(api.renderList()))
  end)

  it("keeps retail on its own stores", function()
    local api = loadSniper()
    api.setScanDeals({ deal(10, 5000) })
    api.GC.ForeverScan = { Enabled = function() return false end }
    api.GC.ForeverDeals = { Rows = function() error("read on retail") end }
    assert.same({ 10 }, ids(api.renderList()))
  end)

  it("says there is no scan yet, or that the last one found nothing", function()
    local api = loadSniper()
    forever(api, {}, nil)
    api.GC.Sniper._UpdateEmptyState(0)
    assert.is_truthy(api.emptyText:find("No scan of this auction house yet.", 1, true))
    forever(api, {}, { at = 1 })
    api.GC.Sniper._UpdateEmptyState(0)
    assert.is_truthy(api.emptyText:find("No deals in your last scan.", 1, true))
    assert.is_nil(api.emptyText:find("goldcap.gg prices", 1, true))
  end)

  it("names the kind on the chip and says what to do after the name", function()
    local api = loadSniper()
    local setRowDeal = upvalue(api.refreshRows, "setRowDeal")
    local row = fakeRow()
    setRowDeal(row, foreverRow(2589, "commodities"))
    assert.equal("Below vendor", row.tierChip.label)
    assert.is_truthy(row._nameParts[2]:find("buy at 12c or less, vendor pays 13c", 1, true))
    local market = foreverRow(2592, "commodities", "market")
    market.refUnit = 100
    setRowDeal(row, market)
    assert.equal("Under market", row.tierChip.label)
    assert.is_truthy(row._nameParts[2]:find("half ask 100c+", 1, true))
  end)

  it("writes the whole sentence for each kind", function()
    local api = loadSniper()
    assert.equal("Buy at or under 12c: a vendor pays 13c each. This buy makes 105c.",
      api.GC.Sniper._ForeverNote("vendor", 12, 13, 105))
    assert.is_truthy(api.GC.Sniper._ForeverNote("market", 70, 100, 580):find("Resale speed is unknown", 1, true))
  end)
end)
