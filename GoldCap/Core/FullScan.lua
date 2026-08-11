local _, GC = ...

GC.FullScan = {}

local TIER_RANK = { HOT = 1, GOOD = 2, WATCH = 3, SUSPECT = 4 }

-- Tier rank first, then profit desc, then itemID asc as a deterministic tiebreaker
-- (pairs()/map iteration order is otherwise unspecified). Shared by Evaluate, EvaluateDelta
-- (each page's deals are already in this order) and MergeDeals (the combined set is
-- re-sorted the same way so streamed and single-shot results are identical).
local function compareDeals(a, b)
  local ra, rb = TIER_RANK[a.tier], TIER_RANK[b.tier]
  if ra ~= rb then return ra < rb end
  if a.profit ~= b.profit then return a.profit > b.profit end
  return a.itemID < b.itemID
end

-- Shared by Evaluate and MergeDeals, both of which sort a deals list with compareDeals and
-- then need to drop everything past `cap`.
local function truncate(list, cap)
  if cap and #list > cap then
    for i = #list, cap + 1, -1 do list[i] = nil end
  end
end

-- Dedupe by itemID, keeping the single BEST (highest-profit) deal per item. A full scan
-- can list the same item from several sellers; downstream (SniperFrame's awaitingRequery /
-- awaitingKeyInfo) is keyed by itemID, so two .stale rows sharing an itemID would collide
-- (a second Buy on a same-item row orphans the first requery). Collapsing to one row per
-- item here removes that hazard and also yields a cleaner deals list. First-seen wins on
-- an exact profit tie; callers sort with compareDeals afterward, whose itemID tiebreaker
-- keeps output deterministic regardless of the pairs() iteration order below.
--
-- `first` lets EvaluateDelta walk only the tail of `rows` (a streamed scan page) while
-- Evaluate walks the whole thing (first = 1) -- same per-row body either way.
local function evaluateFrom(rows, first, getValue, cfg)
  local bestByItem = {}
  for i = first, #rows do
    local row = rows[i]
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
  return deals
end

function GC.FullScan.Evaluate(rows, getValue, cfg, cap)
  local deals = evaluateFrom(rows, 1, getValue, cfg)
  table.sort(deals, compareDeals)
  truncate(deals, cap)
  return deals
end

-- Streaming counterpart to Evaluate: only rows[fromIndex+1 ..] are evaluated (deduped by
-- itemID exactly like Evaluate, just scoped to the new tail), so a page arriving mid-scan
-- doesn't cost re-walking everything seen so far. newCount (= #rows) is handed back so the
-- caller can pass it as the next call's fromIndex. Returned deals are sorted the same way
-- Evaluate's are but not capped -- capping happens once, in MergeDeals, against the
-- accumulated set.
--
-- Equivalence with a single-shot Evaluate(rows, ...) holds chunk-by-chunk *within one scan
-- pass* because RowsFromBrowse emits at most one row per itemKey (C_AuctionHouse.GetBrowseResults
-- is already aggregated per item group) -- so itemIDs can never repeat across two
-- EvaluateDelta calls covering disjoint slices of the same pass, and evaluateFrom's own
-- per-call dedupe is never actually exercised across chunk boundaries, only within one.
-- MergeDeals' incoming-wins rule (below) only matters once a *second* pass starts merging
-- fresher rows over the first pass's results.
function GC.FullScan.EvaluateDelta(rows, fromIndex, getValue, cfg)
  local deals = evaluateFrom(rows, fromIndex + 1, getValue, cfg)
  table.sort(deals, compareDeals)
  return deals, #rows
end

-- Combines a previously-merged deal set with a newly-evaluated page. Dedupes by itemID
-- (matching Evaluate/EvaluateDelta's own dedupe key). On a collision the INCOMING row wins
-- unconditionally, regardless of unitPrice -- see EvaluateDelta's comment above: within one
-- scan pass itemIDs can't collide at all (browse aggregates are unique per itemKey), so any
-- collision MergeDeals actually sees comes from a *new* pass merging over the previous
-- pass's deal list. There, the fresher row must win even if it's pricier: keeping a stale
-- cheaper row would advertise a lot that's already gone (bought out, requoted, or expired
-- since the earlier pass saw it). Re-sorts with the same comparator Evaluate uses and
-- truncates to cap.
function GC.FullScan.MergeDeals(existing, incoming, cap)
  local byItem = {}
  for _, deal in ipairs(existing) do
    byItem[deal.itemID] = deal
  end
  for _, deal in ipairs(incoming) do
    byItem[deal.itemID] = deal
  end

  local merged = {}
  for _, deal in pairs(byItem) do
    merged[#merged + 1] = deal
  end
  table.sort(merged, compareDeals)
  truncate(merged, cap)
  return merged
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

-- Sniper v3 §3 new-HOT-deal ping: the pure "which of these deals is a genuinely new HOT
-- listing" question, shared verbatim by BOTH of SniperFrame's ping call sites -- the
-- streaming per-page merge AND the scan-completion reconcile (fix round 1, I2: a tiny
-- realm's very first browse event can already report HasFullBrowseResults() == true, so the
-- completion branch needs its own ping pass too, not just the streaming one -- otherwise
-- last-page HOTs, and on some realms EVERY HOT deal, never ping at all).
--
-- `seen` is a caller-owned set keyed `itemID.."@"..unitPrice`, MUTATED in place: every key
-- returned here is also marked seen[key]=true before returning, so a second call in the same
-- scan pass (completion, after streaming already saw and pinged the same deal) never
-- re-collects it -- and a caller runs both the streaming and completion passes against the
-- SAME `seen` table for exactly that reason. Callers own resetting `seen` between AH
-- sessions (SniperFrame does this on ahClosed).
function GC.FullScan.CollectNewHot(deals, seen)
  local newly = {}
  for _, deal in ipairs(deals) do
    if deal.tier == "HOT" then
      local key = deal.itemID .. "@" .. deal.unitPrice
      if not seen[key] then
        seen[key] = true
        newly[#newly + 1] = deal
      end
    end
  end
  return newly
end
