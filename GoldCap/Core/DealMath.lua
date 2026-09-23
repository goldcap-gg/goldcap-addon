local _, GC = ...

GC.DealMath = {}

-- Float ratios vs decimal thresholds: 1 - 900000/1000000 is 0.09999999999999998,
-- and round-percentage listings are common, so every comparison gets an epsilon.
local EPS = 1e-9

-- The two figures every board row shows against the market: how far under it the unit sits
-- (`discount`, a fraction) and what reselling `qty` at it would make after the 5% cut, against
-- what they cost (`profit`; `cost` defaults to unitPrice * qty -- a YOUR PRICE row passes the
-- exact sum over the levels it buys). nil when there is no market to measure against -- no
-- value, or a realm item with no region reference (see Evaluate below for why its own median is
-- no yardstick). Evaluate uses it for a deal; the Sniper's watched and YOUR PRICE rows use it
-- for items that are not one (in game 2026-09-23 a pinned row showed its unit price and nothing
-- else).
function GC.DealMath.Measure(unitPrice, qty, value, cost)
  if not value or not value.mv or value.mv <= 0 then return nil end
  if value.kind == "realm_item" and not value.ref then return nil end
  return { discount = 1 - (unitPrice / value.mv),
    profit = math.floor(value.mv * 0.95) * qty - (cost or unitPrice * qty) }
end

function GC.DealMath.Evaluate(live, value, cfg)
  if not value or not value.mv or value.mv <= 0 then return nil end
  -- A realm item is a deal only against the REGION's price for it (the import's T section,
  -- exposed as `ref`). Its own realm median is not a second-best yardstick: a realm item can
  -- sit at two listings for days, and a median of two is whatever the odd one out happens to
  -- be. Measured in game 2026-09-11, before T shipped: two lots of Leather Gauntlets of the
  -- Sun, 90,000 and 5.4 million, made a "median" of 2.7 million -- so the cheap one showed as
  -- 97% off with 2.5 million gold of profit that could never be realised. Every one of those
  -- rows was noise, and the honest answer is not a smaller number, it is no row at all.
  -- Commodities are untouched: their market value is measured across the region already.
  local qty = live.qty or 1
  local measured = GC.DealMath.Measure(live.unitPrice, qty, value)
  if not measured then return nil end
  local discount, profit = measured.discount, measured.profit
  if discount < cfg.watchDiscount - EPS then return nil end

  -- Estimated stress-exit profit (Sniper discovery rework): mirrors the SHAPE of Check's own
  -- stressProfit (SniperDecision.Evaluate) so the number discovery sorts and displays by is the
  -- one that predicts what a live Check will say, not just how far under mv the ask sits.
  -- estExitUnit stands in for the live competing ask discovery has no order book to read:
  -- stressUnit (the same fact.stressUnit GC.Data.GetItemValue exposes) capped at mv, since a
  -- resale can never be usefully projected above the market value that produced it. Falls back
  -- to mv alone -- the same ceiling `profit` above has always used -- whenever this value
  -- carries no usable stressUnit (bundled data, a realm item, or a watch-loop poll of an item
  -- nobody has imported verification for), so estProfit degrades to the old projection instead
  -- of going nil.
  -- Only the 5% AH cut is modeled here, same fee `profit` above already applies. The deposit is
  -- unknowable at this point: it comes from a live StartCommoditiesPurchase quote, which
  -- discovery never has (that is exactly what Check's own live requery is for).
  local estExitUnit = value.stressUnit
  if not estExitUnit or estExitUnit <= 0 or estExitUnit > value.mv then estExitUnit = value.mv end
  local estProfit = math.floor(estExitUnit * qty * 0.95) - live.unitPrice * qty

  -- Liquidity gate against thin-market noise: an inflated mv with no real turnover
  -- otherwise dominates the tier+profit sort. Only an import entry's absent sold/day
  -- carries meaning ("zero recorded sales in the realm's last 24h"); bundled data has
  -- no liquidity figure at all, so gating on it would zero out HOT/GOOD for anyone who
  -- hasn't imported yet -- skip the gate entirely for bundled (or sourceless) values.
  local gated = value.source == "import"
  local sold = gated and (value.sold or 0) or nil

  -- Anti-dump gate (Sniper v2): a market actively crashing >= dumpTrendPct in
  -- the last 24h can't be trusted as "cheap" -- the mv itself may already be
  -- stale and falling, so cap it below GOOD no matter how good today's
  -- discount/profit look. Missing trend (no import, or the wire format
  -- omitted it -- see @wowa/tsm's itemToken) means no gate, same as before
  -- this field existed. Independent of, and composes with, the liquidity
  -- gate above -- either one alone is enough to deny HOT/GOOD.
  local falling = value.trend ~= nil and value.trend <= -cfg.dumpTrendPct

  local tier
  if discount > cfg.suspectDiscount + EPS then
    tier = "SUSPECT"
  elseif discount >= cfg.hotDiscount - EPS and profit >= cfg.hotProfit
      and (not gated or sold >= cfg.hotMinSold - EPS) and not falling then
    tier = "HOT"
  elseif discount >= cfg.goodDiscount - EPS and profit >= cfg.goodProfit
      and (not gated or sold >= cfg.goodMinSold - EPS) and not falling then
    tier = "GOOD"
  else
    tier = "WATCH"
  end

  return {
    itemID = live.itemID,
    isCommodity = live.isCommodity,
    auctionID = live.auctionID,
    unitPrice = live.unitPrice,
    qty = qty,
    -- Fix 1: how much is really out there (a browse-scan's totalQuantity, or a commodity
    -- book's summed level quantities) -- distinct from `qty`, which is only how much THIS
    -- deal proposes to buy. nil whenever the caller has no such figure (plain watchlist
    -- item snapshots never did, and still don't).
    avail = live.avail,
    mv = value.mv,
    discount = discount,
    profit = profit,
    estProfit = estProfit,
    estExitUnit = estExitUnit,
    tier = tier,
    falling = falling,
  }
end

function GC.DealMath.PriceIncreaseExceeds(quotedTotal, updatedTotal, maxRatio)
  local threshold = quotedTotal * (1 + maxRatio)
  return updatedTotal > threshold + math.abs(threshold) * EPS
end

-- The GROSS price to project a resale against, before the 5% AH cut -- callers still apply
-- their own floor(unit * 0.95). `competing` is GC.Book.Fill's cheapest surviving ask.
--
-- You cannot sell above what is already listed, so an mv the visible market broadly
-- contradicts must not drive the projection: on 2026-08-10 an mv of 195g on an item trading
-- near 35g turned into a +63,201g "profit" on the confirmation dialog. Clamping to one copper
-- under the competing ask is the same rule UI/SellFrame.lua already posts at
-- (`recommended = max(1, quote - 1)`), so the buy screen and the sell screen finally agree.
-- A legitimate snipe is untouched: the competing ask sits near mv, not far below it.
-- The market value arrives from an import that has been wrong before, and this function
-- is the last place a bad one can be caught before it reaches a projection.
function GC.DealMath.SellUnit(mv, competing)
  -- Guard against non-positive market values: there is no usable projection without one.
  if not mv or mv <= 0 then
    if not competing or competing <= 0 then return 1, false, nil end
    local ask = competing - 1
    if ask < 1 then ask = 1 end
    return ask, true, nil
  end
  if not competing or competing <= 0 then return mv, false, nil end
  local ratio = mv / competing
  local ask = competing - 1
  if ask < 1 then ask = 1 end
  if ask < mv then return ask, true, ratio end
  return mv, false, ratio
end

-- How hard to shout about a price that moved between the quote and the purchase.
-- Two thresholds on purpose: one alarm that fires on a 6% drift is the mechanism that trains
-- players to click through it, so the loud treatment is reserved for a rise that changes the
-- decision. Built on PriceIncreaseExceeds above so both tiers inherit its epsilon contract.
function GC.DealMath.RequoteSeverity(quotedTotal, updatedTotal, warnRatio, loudRatio)
  local ratio = (quotedTotal and quotedTotal > 0) and (updatedTotal / quotedTotal) or nil
  if not ratio then return "none", nil end
  if GC.DealMath.PriceIncreaseExceeds(quotedTotal, updatedTotal, loudRatio) then
    return "loud", ratio
  end
  if GC.DealMath.PriceIncreaseExceeds(quotedTotal, updatedTotal, warnRatio) then
    return "warn", ratio
  end
  return "none", ratio
end
