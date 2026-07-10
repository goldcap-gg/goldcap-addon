local _, GC = ...

GC.DealMath = {}

function GC.DealMath.Evaluate(live, value, cfg)
  if not value or not value.mv or value.mv <= 0 then return nil end
  local discount = 1 - (live.unitPrice / value.mv)
  if discount < cfg.watchDiscount then return nil end

  local qty = live.qty or 1
  local profit = (math.floor(value.mv * 0.95) - live.unitPrice) * qty

  local tier
  if discount > cfg.suspectDiscount then
    tier = "SUSPECT"
  elseif discount >= cfg.hotDiscount and profit >= cfg.hotProfit then
    tier = "HOT"
  elseif discount >= cfg.goodDiscount and profit >= cfg.goodProfit then
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
  return updatedTotal > quotedTotal * (1 + maxRatio)
end
