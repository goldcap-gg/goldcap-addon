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

  local tier
  if discount > cfg.suspectDiscount + EPS then
    tier = "SUSPECT"
  elseif discount >= cfg.hotDiscount - EPS and profit >= cfg.hotProfit
      and (not gated or sold >= cfg.hotMinSold - EPS) then
    tier = "HOT"
  elseif discount >= cfg.goodDiscount - EPS and profit >= cfg.goodProfit
      and (not gated or sold >= cfg.goodMinSold - EPS) then
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
    mv = value.mv,
    discount = discount,
    profit = profit,
    tier = tier,
  }
end

function GC.DealMath.PriceIncreaseExceeds(quotedTotal, updatedTotal, maxRatio)
  local threshold = quotedTotal * (1 + maxRatio)
  return updatedTotal > threshold + math.abs(threshold) * EPS
end
