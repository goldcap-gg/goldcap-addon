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

  local tier
  if discount > cfg.suspectDiscount + EPS then
    tier = "SUSPECT"
  elseif discount >= cfg.hotDiscount - EPS and profit >= cfg.hotProfit then
    tier = "HOT"
  elseif discount >= cfg.goodDiscount - EPS and profit >= cfg.goodProfit then
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
