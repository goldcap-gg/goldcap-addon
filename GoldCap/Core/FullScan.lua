local _, GC = ...

GC.FullScan = {}

local TIER_RANK = { HOT = 1, GOOD = 2, WATCH = 3, SUSPECT = 4 }

function GC.FullScan.Evaluate(rows, getValue, cfg, cap)
  local deals = {}
  for _, row in ipairs(rows) do
    if row.count and row.count > 0 and row.buyoutStack and row.buyoutStack > 0 then
      local unitPrice = math.floor(row.buyoutStack / row.count)
      local deal = GC.DealMath.Evaluate(
        { itemID = row.itemID, isCommodity = false, auctionID = nil,
          unitPrice = unitPrice, qty = row.count },
        getValue(row.itemID), cfg)
      if deal then deals[#deals + 1] = deal end
    end
  end

  table.sort(deals, function(a, b)
    local ra, rb = TIER_RANK[a.tier], TIER_RANK[b.tier]
    if ra ~= rb then return ra < rb end
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.itemID < b.itemID
  end)

  if cap and #deals > cap then
    for i = #deals, cap + 1, -1 do deals[i] = nil end
  end
  return deals
end
