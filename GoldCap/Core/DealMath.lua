local _, GC = ...

GC.DealMath = {}

-- Float ratios vs decimal thresholds: 1 - 900000/1000000 is 0.09999999999999998,
-- and round-percentage listings are common, so every comparison gets an epsilon.
local EPS = 1e-9

function GC.DealMath.Evaluate(live, value, cfg)
  if not value or not value.mv or value.mv <= 0 then return nil end
  local discount = 1 - (live.unitPrice / value.mv)
  if discount < cfg.watchDiscount - EPS then return nil end

  local qty = live.qty or 1
  local profit = (math.floor(value.mv * 0.95) - live.unitPrice) * qty

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
