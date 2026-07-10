local _, GC = ...

GC.FullScan = {}

local TIER_RANK = { HOT = 1, GOOD = 2, WATCH = 3, SUSPECT = 4 }

function GC.FullScan.Evaluate(rows, getValue, cfg, cap)
  -- Dedupe by itemID, keeping the single BEST (highest-profit) deal per item. A full scan
  -- can list the same item from several sellers; downstream (SniperFrame's awaitingRequery /
  -- awaitingKeyInfo) is keyed by itemID, so two .stale rows sharing an itemID would collide
  -- (a second Buy on a same-item row orphans the first requery). Collapsing to one row per
  -- item here removes that hazard and also yields a cleaner deals list. First-seen wins on
  -- an exact profit tie; the final sort's itemID tiebreaker keeps output deterministic
  -- regardless of the pairs() iteration order below.
  local bestByItem = {}
  for _, row in ipairs(rows) do
    if row.count and row.count > 0 and row.buyoutStack and row.buyoutStack > 0 then
      local unitPrice = math.floor(row.buyoutStack / row.count)
      local deal = GC.DealMath.Evaluate(
        { itemID = row.itemID, isCommodity = false, auctionID = nil,
          unitPrice = unitPrice, qty = row.count },
        getValue(row.itemID), cfg)
      if deal then
        local existing = bestByItem[deal.itemID]
        if not existing or deal.profit > existing.profit then
          bestByItem[deal.itemID] = deal
        end
      end
    end
  end

  local deals = {}
  for _, deal in pairs(bestByItem) do
    deals[#deals + 1] = deal
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
