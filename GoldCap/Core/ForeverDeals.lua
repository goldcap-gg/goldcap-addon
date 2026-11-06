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
-- holds; the Check reads the book itself. On the Items board a buy is one lot, so a row there
-- must clear the minimum profit in its cheapest lot alone (oneBuyAdmits).
--
-- Kind "market" ("Under market"), commodities only: levels at or under 70% of the AH value -- the
-- price the cheapest tenth of the listed units reach (GC.ForeverFold.Value, the figure the tooltip
-- calls "AH value"), never above the half-way price -- whose resale at that value, after the 5%
-- cut and the deposit, still makes at least a copper each. Not the half-way price itself: in a
-- thin Forever book half the units are asks nobody pays (Linen at 66-82c with half the units at
-- 3s+ made a 2g29s "deal" of ordinary stock, beta 2026-09-27), so a row appears only when lots sit
-- clearly under where the cheap end of the book already is. Riskier than a vendor deal: nothing in
-- Forever measures how fast an item sells. A thin book (under 20 units, or under three prices) is
-- no market at all, and an item auction is left out: its deposit needs a bag location a scan has
-- not got, and it has no quote step to catch a bad resale estimate before PlaceBid.
GC.ForeverDeals = GC.ForeverDeals or {}

local C = {
  MIN_PROFIT_COPPER = 20,            -- a Forever row's whole buy, unless the player changed theirs
  RETAIL_DEFAULT_MIN_PROFIT = 50000, -- Core/Init.lua's default for settings.sniper.minimumProfitCopper
  MARKET_SHARE = 0.70,               -- a market deal asks at most this share of the AH value
  MARKET_MIN_UNITS = 20,             -- thin-market guard: units listed
  MARKET_MIN_LEVELS = 3,             -- thin-market guard: distinct prices listed
  -- A floor-only entry (below) is measured against the crowd's AH value only when the crowd saw
  -- the item no more than this long before the scan did.
  FLOOR_CROWD_MAX_AGE_SECONDS = 6 * 3600,
  ROW_CAP = 100,                     -- per board, as UI/SniperFrame.lua's WIN.ROW_CAP
  REBUILD_SECONDS = 5,               -- while vendor prices the rows need are still loading
  REQUEST_PER_BUILD = 100,           -- item-data requests per build
  REQUEST_WAIT_SECONDS = 30,         -- after this, an item still without a vendor price has none
  -- Decision 5 of plan 3c: retail's 5% per-buy share makes "Below vendor" useless at low level
  -- (13s in the bags buys 69c), so a vendor row gets half the wallet while the player kept the
  -- shipped share -- Core/Init.lua's default, Core/SniperDecision.lua's normalizeConfig clamp.
  RETAIL_DEFAULT_CAPITAL_SHARE = 0.05,
  VENDOR_CAPITAL_SHARE = 0.50,
  -- A market row's resale is a bet, so less than a vendor row's half -- but 5% left a new
  -- character's wallet buying nothing at all ("needs 2g" on a 10s lot; owner, 2026-11-06).
  MARKET_CAPITAL_SHARE = 0.25,
}
GC.ForeverDeals.C = C

-- Task S (Settings for Forever): its own key now, settings.sniper.foreverMinimumProfitCopper --
-- UI/SettingsFrame.lua edits it in copper, so an edit there can never move retail's own
-- minimumProfitCopper (5g), and the field never shows a number this function ignores. Once it
-- holds a number (even 0, even a re-save of the figure the migration below would have chosen
-- anyway) it always wins, forever after.
--
-- Migration (decision 4 of plan 3c, kept as the fallback): a player who changed the RETAIL
-- field's default before this key ever existed keeps that old rule -- their retail value, as it
-- stands -- until they touch the Forever field once. Retail's own floor (at least 1g,
-- SniperDecision's normalizeConfig) is a gold economy's and never applies here.
function GC.ForeverDeals.MinimumProfit(settings)
  if type(settings) ~= "table" then return C.MIN_PROFIT_COPPER end
  local own = settings.foreverMinimumProfitCopper
  if type(own) == "number" and own == own and own >= 0 then
    return math.floor(own)
  end
  local m = settings.minimumProfitCopper
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

-- The price a market row is measured against: the AH value, or the half-way price when that is
-- lower (it never is in one consistent book; a crowd payload's two figures are separate numbers).
local function referenceUnit(ref)
  local unit = ref.value
  if type(unit) ~= "number" or unit <= 0 then return nil end
  if type(ref.p50) == "number" and ref.p50 > 0 and ref.p50 < unit then unit = ref.p50 end
  return unit
end

-- `isCommodity` is a function: for an item key the client has not cached, its answer is a server
-- request, so it is asked only once the cheapest lot sits under the ceiling a zero deposit would
-- allow. Nothing under that, no row, whatever the item is.
local function underMarket(itemID, e, ctx, isCommodity)
  if not e.qty or e.qty < C.MARKET_MIN_UNITS then return nil end
  if not e.floorOnly and not (e.levels and e.levels >= C.MARKET_MIN_LEVELS) then return nil end
  local ref = ctx.referenceFor and ctx.referenceFor(itemID, e)
    or { value = e.value, p50 = e.p50, source = "own" }
  -- A floor-only entry has no AH value of its own: its one price is the floor itself. Only the
  -- crowd's will do, and only one the crowd took about when the scan did.
  if e.floorOnly and (ref.source ~= "crowd" or (type(ref.at) == "number" and type(e.foldAt) == "number"
      and e.foldAt - ref.at > C.FLOOR_CROWD_MAX_AGE_SECONDS)) then
    return nil
  end
  local refUnit = referenceUnit(ref)
  if not refUnit then return nil end
  local net = math.floor(refUnit * KEEP)
  if e.ladder[1][1] > math.min(math.floor(refUnit * C.MARKET_SHARE), net - 1) then return nil end
  if isCommodity() ~= true then return nil end
  local deposit = ctx.depositFor(itemID)
  if type(deposit) ~= "number" or deposit < 0 then return nil end
  local ceiling = math.min(math.floor(refUnit * C.MARKET_SHARE), net - deposit - 1)
  if ceiling < 1 then return nil end
  -- Priced as the Check prices it (GC.SniperDecision.EvaluateCeiling): resold one copper under the
  -- cheapest ask the buy leaves on the book, never above the AH value, and of the buys that take
  -- whole levels under the ceiling, the one that pays most. At the AH value itself every row read
  -- richer than its Check, which the next level up always holds lower, and some the board listed
  -- the Check then refused (review 2026-11-06: Silverleaf +1,155c on the board, +544c checked).
  -- A level past the ladder's last is not known; the AH value stands in for it.
  local units, cost = 0, 0
  local best
  for i, level in ipairs(e.ladder) do
    if level[1] > ceiling then break end
    units = units + level[2]
    cost = cost + level[1] * level[2]
    local after = e.ladder[i + 1]
    local exit = after and math.max(1, math.min(refUnit, after[1] - 1)) or refUnit
    local gross = exit * units
    local profit = gross - math.ceil(gross * 5 / 100) - cost - deposit * units
    if not best or profit > best.profit then best = { units = units, cost = cost, profit = profit } end
  end
  if not best or best.profit <= 0 then return nil end
  local row = lead(itemID, e, "market", ceiling, refUnit, best.units, best.cost, best.profit)
  row.depositUnit = deposit
  -- Whose AH value this is: the check panel's caption says so (CheckVerdict market_crowd).
  row.refSource, row.refScanners = ref.source, ref.scanners
  return row
end

-- The minimum profit is per BUY. A commodity buy takes many units at once, so a row's sum over its
-- levels is what one buy can make. An Items-board buy is one lot (PlaceBid), and every Forever
-- non-commodity lot holds one unit (the owner's save, 2026-11-06), so the row's best buy is its
-- cheapest lot, one unit of it: 53 Training Swords at 6c profit each made a 318c row whose every
-- click earned 6c and took a bag slot (review, 2026-11-06). Asked only of a row the summed rule
-- already admits, which Build asks the commodity question of anyway; an item the client has not
-- answered for yet keeps the summed rule rather than wait. The row's totals stay as they are.
local function oneBuyAdmits(row, isCommodity, admit)
  if isCommodity() ~= false then return true end
  return GC.DealMath.BoardAdmits({ itemID = row.itemID, estProfit = row.refUnit - row.unitPrice }, admit)
end

-- rows, missing (no vendor price yet), unsure (a row or a market candidate waits on the client's
-- word that the item is a commodity), floorOnly (how many entries had only their lowest price).
--
-- A floor-only entry: the browse pass's (Core/ForeverScan.lua), which is all an item gets once
-- the server cut the full dump short -- every dump of the owner's evening of 2026-11-06 came back
-- at 1023 rows, the board was left with 1525 items and no price levels, and it said "deals 0". The
-- browse pass sees each item's lowest price and how many units are listed in all, not at what
-- prices. One unit at the lowest price is all that proves, so a row from it is that one unit,
-- vendor or market alike, and stands only when that one unit clears the minimum profit. The Check
-- reads the live book when the row is opened and buys whatever more there is under the ceiling.
function GC.ForeverDeals.Build(fold, ctx)
  local rows, missing, unsure, floorOnly = {}, {}, {}, 0
  if type(fold) ~= "table" or type(fold.items) ~= "table" or type(ctx) ~= "table" then
    return rows, missing, unsure, floorOnly
  end
  local boards = { commodities = {}, items = {} }
  local admit = { minimumProfitCopper = ctx.minimumProfit, watchPins = ctx.watchPins }
  for itemID, encoded in pairs(fold.items) do
    local e = GC.ForeverFold.Decode(encoded)
    if e and e.browse and #e.ladder == 0 then
      e.ladder, e.floorOnly, e.foldAt = { { e.min, 1 } }, true, fold.at
      floorOnly = floorOnly + 1
    end
    if e and #e.ladder > 0 then
      local vendor = ctx.vendorFor(itemID)
      local vendorRow
      if type(vendor) == "number" and vendor > 0 then
        vendorRow = belowVendor(itemID, e, vendor)
      else
        missing[#missing + 1] = itemID
      end
      -- At most one isCommodity call per item, shared by the market candidate and the board
      -- placement below, and only when one of them needs it. Gear is never a commodity, and is
      -- not asked. Both candidates are built before either is judged: a vendor row too small for
      -- the Forever minimum (or otherwise refused) must not block a market row that would
      -- otherwise qualify. The vendor row wins only when it is itself admitted; never both.
      local askedCommodity, commodity = false, nil
      local function isCommodity()
        if not askedCommodity then
          askedCommodity = true
          if e.gear then commodity = false else commodity = ctx.isCommodity(itemID, e) end
        end
        return commodity
      end
      local marketRow = underMarket(itemID, e, ctx, isCommodity)
      local row
      if vendorRow and GC.DealMath.BoardAdmits(vendorRow, admit) and oneBuyAdmits(vendorRow, isCommodity, admit) then
        row = vendorRow
      elseif marketRow and GC.DealMath.BoardAdmits(marketRow, admit) then
        row = marketRow
      end
      if row then
        isCommodity()
        row.isCommodity = commodity == true
        row.board = commodity == false and "items" or "commodities"
        boards[row.board][itemID] = row
      end
      if askedCommodity and commodity == nil then unsure[#unsure + 1] = itemID end
    end
  end
  for _, board in ipairs({ "commodities", "items" }) do
    for _, row in ipairs(GC.FullScan.CapDeals(boards[board], C.ROW_CAP)) do rows[#rows + 1] = row end
  end
  table.sort(missing)
  table.sort(unsure)
  return rows, missing, unsure, floorOnly
end

-- The client, for Rows. Guarded: a missing API answers "unknown", never an error. Asked the way
-- the Sell tab asks it (Services/Sell/Bags.lua's classifyBagItem) and Blizzard's own auction house
-- decides it: the remembered answer, else GetItemKeyInfo of the item's key, remembered once it
-- comes. Not GetItemCommodityStatus: it takes an ItemLocation, a bag slot, and refuses an item ID
-- -- asked with one, every item the Sell tab had never seen stayed unknown, and WoW: Forever's
-- board had no Under market row at all (2026-11-06). nil while the client has not cached the key.
local function realIsCommodity(itemID)
  local known = GC.db and GC.db.commodityByItem and GC.db.commodityByItem[itemID]
  if known ~= nil then return known == true end
  local ah = _G.C_AuctionHouse
  if not (ah and type(ah.GetItemKeyInfo) == "function" and type(ah.MakeItemKey) == "function") then
    return nil
  end
  local ok, info = pcall(function() return ah.GetItemKeyInfo(ah.MakeItemKey(itemID)) end)
  if not (ok and type(info) == "table" and info.isCommodity ~= nil) then return nil end
  local answer = info.isCommodity == true
  if GC.db and type(GC.db.commodityByItem) == "table" then GC.db.commodityByItem[itemID] = answer end
  return answer
end

-- `unsure`: how many items the last build left waiting on the client's commodity answer.
-- `reask`: the auction house opened since (GC.ForeverDeals.OnAuctionHouseShow), so they are asked
-- again at the next Refresh.
-- `from`: the fold table the rows were built from (Drop reads the entry a row came from).
local cache = { at = nil, itemCount = nil, rev = nil, from = nil, builtAt = 0, waitUntil = 0,
  rows = {}, byItem = {}, unsure = 0, reask = false, floorOnly = 0, entries = 0 }
-- keyAsked: when each unsure item's key was first asked, for this fold only (rebuild wipes it when
-- the fold changes, OnAuctionHouseShow when the auction house opens).
local requested, dropped, keyAsked = {}, {}, {}

-- `at` alone used to tell every new fold apart, because every commit stamped driver.now(). Core/
-- ForeverScan.lua's merge path (final review I2b) now keeps a browse-topped-up fold's `at` pinned
-- to its dump's own honest stamp, so a top-up can add items while `at` does not move at all --
-- `itemCount` (bumped only when items were actually added) catches that case. A merge that only
-- overwrote entries moves neither, and the board never rebuilt for it (review, 2026-11-06):
-- `rev`, bumped on every write, does. A fold saved before `rev` existed has none, and the first
-- two still tell it apart.
local function foldChanged(fold)
  return cache.at ~= fold.at or cache.itemCount ~= fold.itemCount or cache.rev ~= fold.rev
end

-- A dropped row stays off while the fold still holds the very entry it was built from, under the
-- same `at`. Keyed to `at` alone, a row stayed off through a merge that brought the item a newer
-- entry, since a merge keeps `at` (review, 2026-11-06); keyed to every write, a browse-only top-up
-- that kept the item's saved entry would put a lead the player just bought straight back.
local function isDropped(fold, itemID)
  local d = dropped[itemID]
  return d ~= nil and d.at == fold.at and d.entry == fold.items[itemID]
end

local function rebuild(fold, now)
  -- Each fold waits for its own unsure items. A stamp kept from an earlier fold (once a session,
  -- 2026-11-06 and before) gave a new fold's items no wait at all when the first ask had run out
  -- long ago, and their Under market rows never came for that fold.
  if foldChanged(fold) then keyAsked = {} end
  local settings = GC.db and GC.db.settings and GC.db.settings.sniper or {}
  local rows, missing, unsure, floorOnly = GC.ForeverDeals.Build(fold, {
    vendorFor = GC.ForeverValue.VendorUnit,
    isCommodity = realIsCommodity,
    -- Asked only once isCommodity said yes (underMarket), so any commodity the scan holds has
    -- its deposit -- not only those the Sell tab once saw in the bags (final review I2).
    depositFor = GC.ForeverValue.CommodityDepositUnit,
    minimumProfit = GC.ForeverDeals.MinimumProfit(settings),
    watchPins = settings.watchPins,
    referenceFor = function(itemID, e)
      if GC.Data and GC.Data.ForeverReference then
        -- A floor-only entry's own figure is only its floor, so the crowd's is taken however the
        -- two compare in time; underMarket bounds how much older it may be.
        return GC.Data.ForeverReference(itemID, e.floorOnly and 0 or fold.at, e.value, e.p50)
      end
      return { value = e.value, p50 = e.p50, source = "own" }
    end,
  })
  local kept, byItem = {}, {}
  for _, row in ipairs(rows) do
    if not isDropped(fold, row.itemID) then
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
  -- An item key the client had not cached: asking was the request (GetItemKeyInfo), and its
  -- answer (ITEM_KEY_ITEM_INFO_RECEIVED) is read by a rebuild inside the same wait. Past it, the
  -- item has no row until the next fold asks again.
  for _, itemID in ipairs(unsure) do
    keyAsked[itemID] = keyAsked[itemID] or now
    waitUntil = math.max(waitUntil, keyAsked[itemID] + C.REQUEST_WAIT_SECONDS)
  end
  cache.at, cache.itemCount, cache.rev, cache.from = fold.at, fold.itemCount, fold.rev, fold
  cache.builtAt, cache.waitUntil, cache.rows, cache.byItem = now, waitUntil, kept, byItem
  cache.unsure, cache.reask = #unsure, false
  local entries = fold.itemCount
  if type(entries) ~= "number" then
    entries = 0
    for _ in pairs(fold.items) do entries = entries + 1 end
  end
  cache.floorOnly, cache.entries = floorOnly or 0, entries
end

local function currentFold()
  if not (GC.ForeverScan and GC.ForeverScan.Enabled and GC.ForeverScan.Enabled()) then return nil end
  return GC.ForeverScan.Fold and GC.ForeverScan.Fold() or nil
end

function GC.ForeverDeals.Due(now)
  local fold = currentFold()
  if not fold then return cache.at ~= nil end
  if foldChanged(fold) or cache.reask then return true end
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
    cache.at, cache.itemCount, cache.rev, cache.from = nil, nil, nil, nil
    cache.rows, cache.byItem, cache.waitUntil = {}, {}, 0
    cache.unsure, cache.reask = 0, false
    return cache.rows
  end
  if foldChanged(fold) then rebuild(fold, now) end
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

-- The auction house opened (Core/Init.lua, beside GC.ForeverScan.OnAuctionHouseShow). Away from
-- it GetItemKeyInfo sends the server nothing (Core/Init.lua's commodityByItem note), so a build
-- made there -- the window opened from the minimap, or the fold a scan committed as the auction
-- house closed -- waited 30 s on a question nobody was asked. At the next visit, with the same
-- fold, nothing was due, and the board had no Under market row the whole visit (review,
-- 2026-11-06). The items that build left unsure get a wait of their own now, asked at the board
-- clock's next Refresh (UI/SniperFrame.lua), never here: that rebuild writes the deal tables a
-- Buy click reads.
function GC.ForeverDeals.OnAuctionHouseShow()
  if cache.unsure == 0 or not currentFold() then return end
  keyAsked = {}
  cache.reask = true
end

-- The rows as last built, never building: for what the auction house ticker paints (the ITEMS
-- chip's count), which must not write the deal tables a Buy click reads (3c taint fix; review
-- 2026-11-06).
-- Whether the board's last build had only lowest prices for at least half the scan's items: the
-- server cut the full dump short, and the readout says so instead of a bare "deals 0". Reads the
-- last build only, never builds.
function GC.ForeverDeals.MostlyFloors()
  return cache.entries > 0 and cache.floorOnly * 2 >= cache.entries
end

function GC.ForeverDeals.Built()
  if not currentFold() then return {} end
  return cache.rows
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
  local from = cache.from
  if from == nil then return end
  dropped[itemID] = { at = from.at, entry = from.items[itemID] }
  cache.byItem[itemID] = nil
  for i = #cache.rows, 1, -1 do
    if cache.rows[i].itemID == itemID then table.remove(cache.rows, i) end
  end
end

-- Decision 5 of plan 3c (controller ruling 2026-09-26). Wraps GC.SniperDecision.BuyLimits with
-- the Forever-specific carve-out: retail's 5% per-buy share leaves nothing to buy at low level.
-- At that shipped default or above, a "vendor" row (its profit locked in by the vendor price the
-- live Check re-reads) gets half the wallet, and a "market" row a quarter (owner, 2026-11-06),
-- or the player's own share where that is the larger. Only the default itself used to qualify,
-- so a player who RAISED the share to 10% got 10%, less than the default gives (review,
-- 2026-11-06). A player who lowered it keeps their own value. Max units per buy (maxQuantity) is
-- untouched for both kinds.
function GC.ForeverDeals.BuyLimits(config, walletCopper, kind)
  local limits = GC.SniperDecision.BuyLimits(config, walletCopper)
  if not limits then return nil end
  local wide = kind == "vendor" and C.VENDOR_CAPITAL_SHARE or kind == "market" and C.MARKET_CAPITAL_SHARE or nil
  if wide and limits.share >= C.RETAIL_DEFAULT_CAPITAL_SHARE and wide > limits.share then
    return { maxQuantity = limits.maxQuantity, budget = math.floor(walletCopper * wide), share = wide }
  end
  return limits
end
