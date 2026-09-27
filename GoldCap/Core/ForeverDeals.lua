local _, GC = ...

-- WoW: Forever's Deals board, from the player's own full scan (Core/ForeverScan.lua's fold).
--
-- Discovery only. A row here is a lead -- WATCH, "Check", never buyable by itself -- exactly like
-- every row a retail scan finds (Core/FullScan.lua). Each carries a CEILING, the most one unit may
-- cost and still pay. The live Check holds the live book to it (GC.SniperDecision.EvaluateCeiling
-- and EvaluateCeilingLot, routed by UI/SniperFrame.lua), and the Sniper's own buy window buys.
--
-- Kind "vendor" ("Below vendor"): the fold's price levels under what a vendor pays for one
-- (GC.ForeverValue.VendorUnit, C_Item.GetItemInfo's sellPrice). Buying pays no cut and a vendor
-- charges no fee, so the profit is exact: vendor - price, per unit. Ceiling: vendor - 1.
-- Only the fold's five cheapest levels are seen, so qty can be short of what the live book
-- holds; the Check reads the book itself.
--
-- Kind "market" ("Under market"), commodities only: levels at or under 70% of p50 -- the price
-- half of the listed units ask at most (Core/ForeverFold.lua's depth part, fold version 2) --
-- whose resale at p50, after the 5% cut and the deposit, still makes at least a copper each.
-- Riskier than a vendor deal: nothing in Forever measures how fast an item sells. A thin book
-- (under 20 units, or under three prices) is no market at all, and an item auction is left out:
-- its deposit needs a bag location a scan has not got, and it has no quote step to catch a bad
-- resale estimate before PlaceBid.
GC.ForeverDeals = GC.ForeverDeals or {}

local C = {
  MIN_PROFIT_COPPER = 20,            -- a Forever row's whole buy, unless the player changed theirs
  RETAIL_DEFAULT_MIN_PROFIT = 50000, -- Core/Init.lua's default for settings.sniper.minimumProfitCopper
  MARKET_SHARE = 0.70,               -- a market deal asks at most this share of the half-way price
  MARKET_MIN_UNITS = 20,             -- thin-market guard: units listed
  MARKET_MIN_LEVELS = 3,             -- thin-market guard: distinct prices listed
  ROW_CAP = 100,                     -- per board, as UI/SniperFrame.lua's WIN.ROW_CAP
  REBUILD_SECONDS = 5,               -- while vendor prices the rows need are still loading
  REQUEST_PER_BUILD = 100,           -- item-data requests per build
  REQUEST_WAIT_SECONDS = 30,         -- after this, an item still without a vendor price has none
  -- Decision 5 of plan 3c: retail's 5% per-buy share makes "Below vendor" useless at low level
  -- (13s in the bags buys 69c), so a vendor row gets half the wallet while the player kept the
  -- shipped share -- Core/Init.lua's default, Core/SniperDecision.lua's normalizeConfig clamp.
  RETAIL_DEFAULT_CAPITAL_SHARE = 0.05,
  VENDOR_CAPITAL_SHARE = 0.50,
}
GC.ForeverDeals.C = C

-- Decision 4 of plan 3c: 20c, unless the player changed "Min profit per buy" from its shipped
-- default -- then theirs, as it stands. Retail's own floor (at least 1g, SniperDecision's
-- normalizeConfig) is a gold economy's and never applies here.
function GC.ForeverDeals.MinimumProfit(settings)
  local m = type(settings) == "table" and settings.minimumProfitCopper or nil
  if type(m) == "number" and m == m and m >= 0 and m ~= C.RETAIL_DEFAULT_MIN_PROFIT then
    return math.floor(m)
  end
  return C.MIN_PROFIT_COPPER
end

local KEEP = 0.95 -- the 5% cut, as Core/ForeverValue.lua and Core/DealMath.lua apply it

local function lead(itemID, e, kind, ceiling, refUnit, units, cost, profit)
  local unit = e.ladder[1][1]
  return {
    itemID = itemID, forever = kind, ceiling = ceiling, refUnit = refUnit,
    unitPrice = unit, qty = units, avail = e.qty, capTotal = cost,
    mv = refUnit, discount = 1 - unit / refUnit, profit = profit, estProfit = profit,
    -- Discovery evidence, never a resolved lot or a live book: the same four fields a retail
    -- scan row carries (Core/FullScan.lua), and `stale`, so openDialog's first click Checks.
    tier = "WATCH", status = "WATCH", reason = "live_verification_required", action = "Check",
    buyable = false, stale = true,
  }
end

local function belowVendor(itemID, e, vendor)
  local ceiling = vendor - 1
  local units, cost, profit = 0, 0, 0
  for _, level in ipairs(e.ladder) do
    if level[1] > ceiling then break end
    units = units + level[2]
    cost = cost + level[1] * level[2]
    profit = profit + (vendor - level[1]) * level[2]
  end
  if units == 0 then return nil end
  return lead(itemID, e, "vendor", ceiling, vendor, units, cost, profit)
end

local function underMarket(itemID, e, ctx, isCommodity)
  if not (e.p50 and e.levels and e.qty) then return nil end
  if e.qty < C.MARKET_MIN_UNITS or e.levels < C.MARKET_MIN_LEVELS then return nil end
  if isCommodity ~= true then return nil end
  local deposit = ctx.depositFor(itemID)
  if type(deposit) ~= "number" or deposit < 0 then return nil end
  local net = math.floor(e.p50 * KEEP)
  local ceiling = math.min(math.floor(e.p50 * C.MARKET_SHARE), net - deposit - 1)
  if ceiling < 1 then return nil end
  local units, cost, profit = 0, 0, 0
  for _, level in ipairs(e.ladder) do
    if level[1] > ceiling then break end
    units = units + level[2]
    cost = cost + level[1] * level[2]
    profit = profit + (net - level[1] - deposit) * level[2]
  end
  if units == 0 then return nil end
  local row = lead(itemID, e, "market", ceiling, e.p50, units, cost, profit)
  row.depositUnit = deposit
  return row
end

function GC.ForeverDeals.Build(fold, ctx)
  local rows, missing = {}, {}
  if type(fold) ~= "table" or type(fold.items) ~= "table" or type(ctx) ~= "table" then
    return rows, missing
  end
  local boards = { commodities = {}, items = {} }
  local admit = { minimumProfitCopper = ctx.minimumProfit, watchPins = ctx.watchPins }
  for itemID, encoded in pairs(fold.items) do
    local e = GC.ForeverFold.Decode(encoded)
    if e and not e.browse and #e.ladder > 0 then
      local vendor = ctx.vendorFor(itemID)
      local vendorRow
      if type(vendor) == "number" and vendor > 0 then
        vendorRow = belowVendor(itemID, e, vendor)
      else
        missing[#missing + 1] = itemID
      end
      -- One isCommodity call per item, shared by the market candidate and the board placement
      -- below. Both candidates are built before either is judged: a vendor row too small for the
      -- Forever minimum (or otherwise refused) must not block a market row that would otherwise
      -- qualify. The vendor row wins only when it is itself admitted; never both for one item.
      local commodity = ctx.isCommodity(itemID, e)
      local marketRow = underMarket(itemID, e, ctx, commodity)
      local row
      if vendorRow and GC.DealMath.BoardAdmits(vendorRow, admit) then
        row = vendorRow
      elseif marketRow and GC.DealMath.BoardAdmits(marketRow, admit) then
        row = marketRow
      end
      if row then
        if commodity == nil and e.gear then commodity = false end
        row.isCommodity = commodity == true
        row.board = commodity == false and "items" or "commodities"
        boards[row.board][itemID] = row
      end
    end
  end
  for _, board in ipairs({ "commodities", "items" }) do
    for _, row in ipairs(GC.FullScan.CapDeals(boards[board], C.ROW_CAP)) do rows[#rows + 1] = row end
  end
  table.sort(missing)
  return rows, missing
end

-- The client, for Rows. Guarded: a missing API answers "unknown", never an error.
local function realIsCommodity(itemID)
  if GC.db and GC.db.commodityByItem and GC.db.commodityByItem[itemID] == true then return true end
  local ah = _G.C_AuctionHouse
  local status = _G.Enum and _G.Enum.ItemCommodityStatus
  if ah and type(ah.GetItemCommodityStatus) == "function" and status then
    local ok, answer = pcall(ah.GetItemCommodityStatus, itemID)
    if ok and answer == status.Commodity then return true end
    if ok and answer == status.Item then return false end
  end
  return nil
end

local cache = { at = nil, builtAt = 0, waitUntil = 0, rows = {}, byItem = {} }
local requested, dropped = {}, {}

local function rebuild(fold, now)
  local settings = GC.db and GC.db.settings and GC.db.settings.sniper or {}
  local rows, missing = GC.ForeverDeals.Build(fold, {
    vendorFor = GC.ForeverValue.VendorUnit,
    isCommodity = realIsCommodity,
    -- Asked only once isCommodity said yes (underMarket), so any commodity the scan holds has
    -- its deposit -- not only those the Sell tab once saw in the bags (final review I2).
    depositFor = GC.ForeverValue.CommodityDepositUnit,
    minimumProfit = GC.ForeverDeals.MinimumProfit(settings),
    watchPins = settings.watchPins,
  })
  local kept, byItem = {}, {}
  for _, row in ipairs(rows) do
    if dropped[row.itemID] ~= fold.at then
      kept[#kept + 1] = row
      byItem[row.itemID] = row
    end
  end
  -- Ask the client about items whose vendor price it has not loaded, once each: the answer
  -- (GET_ITEM_INFO_RECEIVED) fills C_Item.GetItemInfo, and the next rebuild reads it.
  -- `waitUntil`: the last moment a rebuild could still pick up a vendor price -- REQUEST_WAIT_SECONDS
  -- after the latest request (or after now, for an item past this build's request budget, which
  -- the next build asks about). An item still unpriced after that has no vendor price.
  local item, asked, waitUntil = _G.C_Item, 0, 0
  for _, itemID in ipairs(missing) do
    if requested[itemID] == nil and asked < C.REQUEST_PER_BUILD
        and item and type(item.RequestLoadItemDataByID) == "function" then
      requested[itemID] = now
      asked = asked + 1
      pcall(item.RequestLoadItemDataByID, itemID)
    end
    waitUntil = math.max(waitUntil, (requested[itemID] or now) + C.REQUEST_WAIT_SECONDS)
  end
  cache.at, cache.builtAt, cache.waitUntil, cache.rows, cache.byItem = fold.at, now, waitUntil, kept, byItem
end

local function currentFold()
  if not (GC.ForeverScan and GC.ForeverScan.Enabled and GC.ForeverScan.Enabled()) then return nil end
  return GC.ForeverScan.Fold and GC.ForeverScan.Fold() or nil
end

function GC.ForeverDeals.Due(now)
  local fold = currentFold()
  if not fold then return cache.at ~= nil end
  if cache.at ~= fold.at then return true end
  now = now or time()
  return now < cache.waitUntil and now - cache.builtAt >= C.REBUILD_SECONDS
end

-- The board's rows. Rebuilt here only for a fold it has not built yet -- the scan that landed it
-- repaints straight away (Core/ForeverScan.lua), so that rebuild runs in the scan's own execution.
-- The rebuilds that pick up vendor prices as they load are GC.ForeverDeals.Refresh's, on the
-- board's own clock (UI/SniperFrame.lua, OnAuctionHouseShow). Not in whatever render asks first:
-- the deal tables this makes are what a Buy click reads, and a render also runs inside the
-- auction house ticker, whose execution WoW: Forever's beta caught tainted (3c taint fix).
function GC.ForeverDeals.Rows(now)
  now = now or time()
  local fold = currentFold()
  if not fold then
    cache.at, cache.rows, cache.byItem, cache.waitUntil = nil, {}, {}, 0
    return cache.rows
  end
  if cache.at ~= fold.at then rebuild(fold, now) end
  return cache.rows
end

-- Rebuilds when due (a new fold, or vendor prices still loading). True when it did, so the caller
-- repaints.
function GC.ForeverDeals.Refresh(now)
  now = now or time()
  local fold = currentFold()
  if not (fold and GC.ForeverDeals.Due(now)) then return false end
  rebuild(fold, now)
  return true
end

function GC.ForeverDeals.CeilingFor(itemID)
  if not currentFold() then return nil end
  local row = cache.byItem[itemID]
  if not row then return nil end
  local settings = GC.db and GC.db.settings and GC.db.settings.sniper or {}
  return { ceilingUnit = row.ceiling, kind = row.forever, exitUnit = row.refUnit,
    depositUnit = row.depositUnit, minimumProfit = GC.ForeverDeals.MinimumProfit(settings) }
end

function GC.ForeverDeals.Drop(itemID)
  if cache.at == nil then return end
  dropped[itemID] = cache.at
  cache.byItem[itemID] = nil
  for i = #cache.rows, 1, -1 do
    if cache.rows[i].itemID == itemID then table.remove(cache.rows, i) end
  end
end

-- Decision 5 of plan 3c (controller ruling 2026-09-26). Wraps GC.SniperDecision.BuyLimits with
-- the one Forever-specific carve-out: a "vendor" row's profit is locked in by the vendor price
-- the live Check re-reads, so retail's 5% per-buy share would leave nothing to buy at low level.
-- While the player kept that shipped default, a vendor row gets half the wallet instead; a
-- player who changed the share gets their own value, unclamped by this function. Kind "market"
-- always gets exactly what SniperDecision.BuyLimits answers. Max units per buy (maxQuantity)
-- is untouched for both kinds.
function GC.ForeverDeals.BuyLimits(config, walletCopper, kind)
  local limits = GC.SniperDecision.BuyLimits(config, walletCopper)
  if not limits then return nil end
  if kind == "vendor" then
    local share = type(config) == "table" and config.maxCapitalShare or nil
    if share == nil or share == C.RETAIL_DEFAULT_CAPITAL_SHARE then
      return { maxQuantity = limits.maxQuantity, budget = math.floor(walletCopper * C.VENDOR_CAPITAL_SHARE) }
    end
  end
  return limits
end
