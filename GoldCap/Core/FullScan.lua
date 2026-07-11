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

-- Auctionator-style incremental browse scan: C_AuctionHouse.GetBrowseResults() returns one
-- BrowseResultInfo per itemKey, already aggregated across every seller of that item group
-- (minPrice, totalQuantity), not one row per individual auction the way GetReplicateItemInfo
-- used to. RowsFromBrowse converts that aggregate shape into the same
-- { itemID, count, buyoutStack } rows Evaluate already consumes, so both scan sources feed
-- one evaluation path unchanged.
function GC.FullScan.RowsFromBrowse(results, getValue)
  local rows = {}
  for _, result in ipairs(results) do
    local itemKey = result.itemKey
    local itemID = itemKey and itemKey.itemID
    local minPrice = result.minPrice
    if itemID and minPrice and minPrice > 0 then
      -- minPrice is the lowest per-unit buyout across the whole item group, but
      -- totalQuantity can run into the thousands for a staple commodity -- buying out an
      -- entire group is never realistic. Bound the flip quantity by a day's sold volume
      -- (from the goldcap.gg import, when available) instead: that's what's actually
      -- flippable before the market re-equilibrates. 200 is a hard sanity cap regardless of
      -- what sold/day says. Items and unknown-liquidity entries carry no sold figure at all,
      -- so they naturally collapse to a qty of 1 -- a single-unit flip, same as a one-off
      -- item auction always was.
      local value = getValue(itemID) or {}
      local estQty = math.min(result.totalQuantity or 1, math.ceil(value.sold or 1), 200)
      if estQty < 1 then estQty = 1 end
      rows[#rows + 1] = { itemID = itemID, count = estQty, buyoutStack = minPrice * estQty }
    end
  end
  return rows
end
