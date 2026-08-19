local _, GC = ...

GC.WatchSet = {}

-- How many DISTINCT asking prices an item has to have appeared at before the loop starts
-- watching it closely. Presence is not the signal: under Auto almost every item recurs from
-- pass to pass, because the market between two passes is mostly unchanged. Downward price
-- movement is. An item that is cheap and motionless scores 1 and is cheap for a reason; an item
-- whose floor is repeatedly reset and eaten scores a new point every time.
GC.WatchSet.MIN_CHURN = 3

-- Folds one pass's deals into the running churn table. `seq` only has to increase; it is used
-- for recency ordering and never for arithmetic, so a pass counter is as good as a clock.
function GC.WatchSet.Observe(churn, deals, seq)
  for _, deal in ipairs(deals or {}) do
    local itemID, unitPrice = deal.itemID, deal.unitPrice
    if itemID and type(unitPrice) == "number" and unitPrice > 0 then
      local entry = churn[itemID]
      if not entry then
        entry = { count = 0, seen = {}, at = seq }
        churn[itemID] = entry
      end
      if not entry.seen[unitPrice] then
        entry.seen[unitPrice] = true
        entry.count = entry.count + 1
        entry.at = seq
      end
    end
  end
end

-- Pins first, in the owner's own order, then recidivists by score, recency and itemID.
--
-- The tiebreak chain is not decoration: a set that reshuffles on a tie changes WHICH items get
-- polled between one pass and the next, which is indistinguishable from the loop being broken.
--
-- Capacity bounds the churn-derived portion of the set only, never the pins. A pin is a
-- standing instruction and outranks anything the addon worked out for itself, so every pin is
-- always included -- the total set can run past `capacity` once pins outnumber it, and that is
-- the point: `capacity` limits how many recidivists get to ride along, not how many pins the
-- player is allowed to have.
function GC.WatchSet.Select(churn, pins, capacity)
  local out, taken = {}, {}
  for _, itemID in ipairs(pins or {}) do
    if not taken[itemID] then
      taken[itemID] = true
      out[#out + 1] = itemID
    end
  end

  local candidates = {}
  for itemID, entry in pairs(churn or {}) do
    if not taken[itemID] and entry.count >= GC.WatchSet.MIN_CHURN then
      candidates[#candidates + 1] = { itemID = itemID, count = entry.count, at = entry.at or 0 }
    end
  end
  table.sort(candidates, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.at ~= b.at then return a.at > b.at end
    return a.itemID < b.itemID
  end)

  local churnAdded = 0
  for _, candidate in ipairs(candidates) do
    if churnAdded >= capacity then break end
    out[#out + 1] = candidate.itemID
    churnAdded = churnAdded + 1
  end
  return out
end
