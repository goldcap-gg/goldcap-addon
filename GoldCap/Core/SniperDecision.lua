local _, GC = ...

-- ACTIVATION BRANCH. Owner-authorized on 2026-08-16 after the first computed SAFE was observed
-- in shadow (item 236775, evidence in
-- docs/superpowers/reports/2026-08-12-verified-sniper-shadow-checklist.md). With this true a
-- mathematically SAFE decision reaches the player as buyable and a hardware click can complete
-- a real purchase. Setting it back to false is the rollback, and it is a one-word change.
GC.SniperDecision = { VERSION = 1, SAFE_PURCHASES_ENABLED = true }

local MAX_EXACT = 9007199254740991
local SOURCE_MAX_AGE = 7200
local MAXIMUM_ROI = 10 -- 1000%; larger edited settings fail closed instead of relaxing.

local function isFinite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isInteger(n)
  return isFinite(n) and n % 1 == 0 and n >= 0 and n <= MAX_EXACT
end

local function isSignedInteger(n)
  return isFinite(n) and n % 1 == 0 and math.abs(n) <= MAX_EXACT
end

local function safeAdd(a, b)
  if a > MAX_EXACT - b then return nil end
  return a + b
end

-- `a` may be a prior signed profit while `b` is always a non-negative exact integer.
-- The branch avoids constructing an out-of-range intermediate before rejecting it.
local function safeSubtract(a, b)
  if a < -MAX_EXACT or a > MAX_EXACT or b < 0 or b > MAX_EXACT then return nil end
  if a < 0 and b > MAX_EXACT + a then return nil end
  return a - b
end

local function safeMultiply(a, b)
  if a ~= 0 and b > math.floor(MAX_EXACT / a) then return nil end
  return a * b
end

local function safeCeilDiv(n, d)
  local adjusted = safeAdd(n, d - 1)
  return adjusted and math.floor(adjusted / d) or nil
end

local function requiredProfitFor(entryTotal, minimumProfitCopper, minimumRoi)
  -- Preserve the caller's finite numeric ROI exactly as the v1 contract defines it. The
  -- multiplication is checked before ceil so an edited setting cannot round an unsafe value.
  local roiProduct = entryTotal * minimumRoi
  if not isFinite(roiProduct) or roiProduct < 0 or roiProduct > MAX_EXACT then return nil end
  local required = math.ceil(roiProduct)
  if not isInteger(required) then return nil end
  return math.max(minimumProfitCopper, required)
end

local function clamp(n, low, high)
  if n < low then return low end
  if n > high then return high end
  return n
end

local function normalizeConfig(config)
  if type(config) ~= "table" then return nil end
  local capital = config.maxCapitalShare
  local demand = config.maxDailyDemandShare
  local quantity = config.maxQuantity
  local profit = config.minimumProfitCopper
  local roi = config.minimumRoi
  if not isFinite(capital) or not isFinite(demand) or not isSignedInteger(quantity)
      or not isSignedInteger(profit) or not isFinite(roi) then
    return nil
  end
  if roi > MAXIMUM_ROI then return nil end
  return {
    maxCapitalShare = clamp(capital, 0.01, 0.20),
    maxDailyDemandShare = clamp(demand, 0, 0.02),
    maxQuantity = clamp(quantity, 1, 200),
    minimumProfitCopper = math.max(profit, 10000),
    minimumRoi = math.max(roi, 0.10),
  }
end

local function preflightLevels(levels, maximum)
  if type(levels) ~= "table" then return nil, "invalid" end
  local visible, remaining, cost = 0, maximum, 0
  for i = 1, #levels do
    local level = levels[i]
    if type(level) ~= "table" or not isInteger(level.unitPrice) or not isInteger(level.quantity)
        or level.unitPrice <= 0 then
      return nil, "invalid"
    end
    visible = safeAdd(visible, level.quantity)
    if not visible then return nil, "invalid" end
    local take = math.min(level.quantity, remaining)
    local line = safeMultiply(level.unitPrice, take)
    cost = line and safeAdd(cost, line)
    if not cost then return nil, "invalid" end
    remaining = remaining - take
  end
  return visible
end

local function resultTemplate()
  return {
    version = GC.SniperDecision.VERSION,
    status = "AVOID",
    buyable = false,
    reasons = {},
    quantity = 0,
    entryTotal = nil,
    entryUnitDisplay = nil,
    competingUnit = nil,
    exitUnit = nil,
    ahCut = nil,
    deposit = 0,
    stressProfit = nil,
    requiredProfit = nil,
  }
end

local REASON_ORDER = {
  live_verification_required = 10, realm_item_unverified = 11, bundled_data_unverified = 12,
  source_stale = 13, market_value_estimated = 14, price_history_sparse = 15,
  listings_too_low = 20, velocity_missing = 21, velocity_too_low = 22,
  sell_through_too_low = 23, liquidity_confidence_low = 24, market_falling = 25,
  book_missing = 30, book_exhausted = 31, competing_ask_missing = 32, deposit_missing = 33,
  capital_limit = 40, demand_limit = 41,
  stress_exit_missing = 50, stress_profit_below_buffer = 51,
  invalid_input = 60, requote_broke_safety = 70,
}

local function orderReasons(reasons)
  table.sort(reasons, function(a, b)
    return REASON_ORDER[a] < REASON_ORDER[b]
  end)
end

function GC.SniperDecision.Evaluate(input)
  local out = resultTemplate()
  -- This is the sole release gate. Keep the economic calculation intact for shadow
  -- validation, then shape only a mathematically SAFE public result into non-buyable WATCH.
  local function finalizePublicResult()
    out.computedStatus = out.status
    if out.computedStatus == "SAFE" and not GC.SniperDecision.SAFE_PURCHASES_ENABLED then
      out.status = "WATCH"
      out.buyable = false
      table.insert(out.reasons, 1, "shadow_validation")
    end
    return out
  end
  local severity = 0 -- WATCH 1, AVOID 2
  local knownReasons = {}
  local fixed = type(input) == "table" and type(input.live) == "table"
    and input.live.fixedQuantity or nil
  local fixedRequested = fixed ~= nil
  local function add(reason, level)
    if not knownReasons[reason] then
      knownReasons[reason] = true
      out.reasons[#out.reasons + 1] = reason
    end
    if level > severity then severity = level end
  end
  local function finalizeFixedFailure()
    if fixedRequested and isInteger(fixed) and fixed > 0 then out.quantity = fixed end
    if fixedRequested then add("requote_broke_safety", 2) end
    out.status = "AVOID"
    out.buyable = false
    orderReasons(out.reasons)
    return finalizePublicResult()
  end
  local function invalid()
    add("invalid_input", 2)
    return finalizeFixedFailure()
  end

  if type(input) ~= "table" or type(input.market) ~= "table" or type(input.live) ~= "table"
      or not isInteger(input.now) or not isInteger(input.walletCopper)
      or type(input.depositForQuantity) ~= "function" then
    return invalid()
  end
  local market, live = input.market, input.live
  if (market.kind ~= "region_commodity" and market.kind ~= "realm_item")
      or (market.source ~= "import" and market.source ~= "bundled")
      or not isInteger(market.marketValue) or market.marketValue <= 0
      or not isInteger(live.itemID) or live.itemID <= 0 then
    return invalid()
  end
  local config = normalizeConfig(input.config)
  if not config then return invalid() end

  if (market.sourceAt ~= nil and not isInteger(market.sourceAt))
      or (market.estimated ~= nil and type(market.estimated) ~= "boolean")
      or (market.stressUnit ~= nil and not isInteger(market.stressUnit))
      or (market.soldPerDay ~= nil and not isFinite(market.soldPerDay))
      or (market.sellThroughBps ~= nil and not isInteger(market.sellThroughBps))
      or (market.liquidityConfidence ~= nil and not isInteger(market.liquidityConfidence))
      or (market.currentQty ~= nil and not isInteger(market.currentQty))
      or (market.listings ~= nil and not isInteger(market.listings))
      or (market.observations ~= nil and not isInteger(market.observations))
      or (market.madBps ~= nil and not isInteger(market.madBps))
      or (market.trend24hPct ~= nil and not isSignedInteger(market.trend24hPct)) then
    return invalid()
  end

  if fixed ~= nil and (not isInteger(fixed) or fixed <= 0) then return invalid() end
  if live.quotedTotal ~= nil and (not isInteger(live.quotedTotal) or live.quotedTotal <= 0) then
    return invalid()
  end
  if live.quotedTotal ~= nil and not fixed then return invalid() end

  -- Confidence reasons are first and remain visible beside later live-book failures.
  local hasLive = live.levels ~= nil
  if not hasLive then add("live_verification_required", 1) end
  if market.kind == "realm_item" then add("realm_item_unverified", 1) end
  if market.source == "bundled" then add("bundled_data_unverified", 1) end
  if market.sourceAt == nil then
    add("source_stale", 1)
  elseif market.sourceAt > input.now
      or input.now - market.sourceAt > SOURCE_MAX_AGE then
    add("source_stale", 1)
  end
  if market.estimated then add("market_value_estimated", 1) end
  if market.observations == nil or market.observations < 12 then
    add("price_history_sparse", 1)
  end

  -- A scan has no actual purchase request: absent proof stays WATCH, never a synthetic book error.
  if not hasLive then
    if fixedRequested then return finalizeFixedFailure() end
    out.status = severity == 2 and "AVOID" or "WATCH"
    out.buyable = false
    orderReasons(out.reasons)
    return finalizePublicResult()
  end

  -- Live market-risk gates. Missing metrics are adverse only after an actual live query exists.
  if market.listings == nil or market.listings < 3 then
    add("listings_too_low", 2)
  end
  if market.soldPerDay == nil then
    add("velocity_missing", 2)
  elseif market.soldPerDay < 3 then
    add("velocity_too_low", 2)
  end
  if market.sellThroughBps == nil or market.sellThroughBps < 7000 then
    add("sell_through_too_low", 2)
  end
  if market.liquidityConfidence == nil or market.liquidityConfidence < 70 then
    add("liquidity_confidence_low", 2)
  end
  if market.trend24hPct ~= nil and market.trend24hPct <= -10 then
    add("market_falling", 2)
  end

  local maxWant = math.max(config.maxQuantity, fixed or 0)
  local visible, levelError = preflightLevels(live.levels, maxWant)
  if levelError then return invalid() end
  if #live.levels == 0 or visible <= 0 then
    add("book_missing", 2)
  end

  local stressUnit = market.stressUnit
  if stressUnit == nil or stressUnit <= 0 then
    add("stress_exit_missing", 2)
  end
  local computedCap = 0
  if isFinite(market.soldPerDay) and market.soldPerDay >= 3 and visible then
    local mad = market.madBps or 0
    local stressDiscount = clamp(0.10 + 2 * mad / 10000, 0.10, 0.30)
    local stock = math.max(market.currentQty or 0, visible)
    local supplyFactor = market.soldPerDay / (market.soldPerDay + stock)
    local demandCap = math.max(1, math.floor(market.soldPerDay * config.maxDailyDemandShare
      * supplyFactor * (1 - stressDiscount)))
    computedCap = math.min(demandCap, config.maxQuantity)
  end
  if computedCap <= 0 then
    add("demand_limit", 2)
  elseif not fixed and computedCap < config.maxQuantity then
    add("demand_limit", 0) -- informational: a passing lower quantity remains SAFE
  end
  if fixed and fixed > computedCap then add("demand_limit", 2) end

  local coarseCap = fixed or computedCap

  local budget = math.floor(input.walletCopper * config.maxCapitalShare)
  local selected
  local sawCapital, sawAffordable, sawProfit, sawExhausted, sawCompeting = false, false, false, false, false
  local start, finish = fixed and fixed or 1, coarseCap
  for quantity = start, finish do
    local fill = GC.Book and GC.Book.Fill and GC.Book.Fill(live.levels, quantity)
    if not fill then
      sawExhausted = true
    elseif fill.exhausted or fill.filled ~= quantity then
      sawExhausted = true
    elseif not isInteger(fill.total) or not isInteger(fill.unit) then
      return invalid()
    else
      local entryTotal = live.quotedTotal or fill.total
      if entryTotal <= budget then sawAffordable = true end
      if not fill.competing or not isInteger(fill.competing) or fill.competing <= 0 then
        sawCompeting = true
      elseif entryTotal > budget then
        sawCapital = true
      else
        local exitUnit = math.min(stressUnit or 0, fill.competing - 1)
        if exitUnit <= 0 then
          add("stress_exit_missing", 2)
        else
          local gross = safeMultiply(exitUnit, quantity)
          local cutBase = gross and safeMultiply(gross, 5)
          local ahCut = cutBase and safeCeilDiv(cutBase, 100)
          local deposit = input.depositForQuantity(quantity)
          if deposit == nil then
            add("deposit_missing", 2)
          elseif not isInteger(deposit) then
            return invalid()
          elseif not gross or not ahCut then
            return invalid()
          else
            local afterCut = safeSubtract(gross, ahCut)
            local afterEntry = afterCut and safeSubtract(afterCut, entryTotal)
            local stressProfit = afterEntry and safeSubtract(afterEntry, deposit)
            local requiredProfit = requiredProfitFor(
              entryTotal, config.minimumProfitCopper, config.minimumRoi)
            if not requiredProfit then return invalid() end
            if not stressProfit then return invalid() end
            if stressProfit < requiredProfit then
              sawProfit = true
            else
              if not selected or stressProfit > selected.stressProfit then
                selected = {
                  quantity = quantity, entryTotal = entryTotal, entryUnitDisplay = math.floor(entryTotal / quantity),
                  competingUnit = fill.competing, exitUnit = exitUnit, ahCut = ahCut,
                  deposit = deposit, stressProfit = stressProfit, requiredProfit = requiredProfit,
                }
              end
            end
          end
        end
      end
    end
  end

  if not selected then
    if sawExhausted and not knownReasons.book_missing then add("book_exhausted", 2) end
    if sawCompeting then add("competing_ask_missing", 2) end
    if sawCapital and not sawAffordable then add("capital_limit", 2) end
    if sawProfit then add("stress_profit_below_buffer", 2) end
  end

  if selected then
    for k, v in pairs(selected) do out[k] = v end
  end
  if selected and severity == 0 then
    out.status = "SAFE"
    out.buyable = true
    orderReasons(out.reasons)
    return finalizePublicResult()
  end

  if fixedRequested then return finalizeFixedFailure() end
  out.status = severity == 1 and "WATCH" or "AVOID"
  out.buyable = false
  orderReasons(out.reasons)
  return finalizePublicResult()
end

-- Discovery-time screen. A browse aggregate has no order book, so Evaluate cannot run on it --
-- but the import facts alone already decide several gates, and a row failing one of those can
-- never become buyable however the live book turns out. Running it at scan time is what stops
-- the deals list advertising rows whose only possible outcome is an AVOID after the player has
-- spent a click discovering it.
--
-- Deliberately mirrors Evaluate's own thresholds and reason names by living in this file --
-- a second copy of "70% sell-through" somewhere else would drift the day one of them moves.
--
-- Only HARD (severity 2) gates are screened. Staleness and an estimated market value also
-- block SAFE, but they apply to every row at once and clear on the next sync, so screening on
-- them would empty the list instead of explaining it; the import-age banner already reports it.
function GC.SniperDecision.PreScreen(market, config)
  if type(market) ~= "table" or type(config) ~= "table" then return { "invalid_input" } end
  local reasons = {}
  local function add(reason) reasons[#reasons + 1] = reason end

  if market.listings == nil or market.listings < 3 then add("listings_too_low") end
  if market.soldPerDay == nil then
    add("velocity_missing")
  elseif market.soldPerDay < 3 then
    add("velocity_too_low")
  end
  if market.sellThroughBps == nil or market.sellThroughBps < 7000 then add("sell_through_too_low") end
  if market.liquidityConfidence == nil or market.liquidityConfidence < 70 then add("liquidity_confidence_low") end
  if market.trend24hPct ~= nil and market.trend24hPct <= -10 then add("market_falling") end
  if market.stressUnit == nil or market.stressUnit <= 0 then add("stress_exit_missing") end

  -- No demand-cap screen here, deliberately. Evaluate's cap is floored at 1
  -- (`math.max(1, ...)`), so it can only reach zero when soldPerDay is missing or under 3 --
  -- which the velocity gates above already catch. The other way `demand_limit` appears is a
  -- player typing a quantity larger than the cap, which needs a live book to know.
  orderReasons(reasons)
  return reasons
end

-- The one mapping from a stored import fact to the market table Evaluate and PreScreen read.
-- Both the dialog and the scan need it, and two copies would drift the first time a field is
-- renamed on the import side.
function GC.SniperDecision.MarketFromValue(value)
  value = value or {}
  return {
    kind = value.kind,
    source = value.source,
    sourceAt = value.sourceAt,
    marketValue = value.mv,
    estimated = value.estimated,
    stressUnit = value.stressUnit,
    soldPerDay = value.sold,
    sellThroughBps = value.sellThroughBps,
    liquidityConfidence = value.liquidityConfidence,
    currentQty = value.currentQty,
    listings = value.listings,
    observations = value.observations,
    madBps = value.madBps,
    trend24hPct = value.trend,
  }
end
