-- What MY LOTS says about the lots that sold: the sold rows the owned list still holds until their
-- gold is collected (GC.SellPositions.NormalizeOwnedLots' second list). A part-sold lot shows its
-- sold part on its own row; a lot sold out (a sold row with no live row of its auctionID) has a
-- SOLD OUT row of its own until the mail is taken; and a banner adds up what is waiting in the
-- mailbox. Pure: no API, no saved data. Both games; a client that returns no sold rows shows none.
local _, GC = ...

local SoldLots = {}
GC.SoldLots = SoldLots

-- How long before a read the previous one may have been for the sale to be dated by it: a sold
-- row first seen by a read that came this soon after one without it sold in between, so "N min
-- ago" is at most this far off. A longer gap (the auction house shut for an hour) dates nothing.
SoldLots.DATED_GAP = 300

local function whole(value)
  return type(value) == "number" and value == value and value == math.floor(value) and value >= 0
    and value < math.huge
end

local function keyOf(row) return tostring(row.auctionID) .. ":" .. tostring(row.soldQty) end

--- When each sold row was first seen, kept in `memory` (the caller's, for the session) across
-- reads. `previousAt` is when the read before this one answered (nil for the first). A row first
-- seen by a read DATED_GAP or less after one is dated (`soldAt`); one that was already there at
-- the first read, or after a long gap, is not: when it sold is not known.
function SoldLots.Stamp(memory, sold, now, previousAt)
  if type(memory) ~= "table" or type(sold) ~= "table" or not whole(now) then return end
  local dated = whole(previousAt) and now - previousAt <= SoldLots.DATED_GAP
  for _, row in ipairs(sold) do
    local key = keyOf(row)
    if memory[key] == nil then memory[key] = dated and now or false end
    row.soldAt = memory[key] or nil
  end
end

--- What one sold row brings once the auction house has taken its 5% (GC.SellPositions.Net), nil
-- with no total from the client.
function SoldLots.Net(row)
  return type(row) == "table" and whole(row.soldTotal) and row.soldTotal > 0
    and GC.SellPositions.Net(1, row.soldTotal) or nil
end

--- The sold side of MY LOTS from `sold` (NormalizeOwnedLots' second list) and `lots` (its first):
--   sales    how many sold rows there are,
--   net      what they bring after the cut, added row by row (nil when none says),
--   soldOut  the lots sold out, one per position in the order first seen: { positionKey, itemID,
--            soldQty, net, sales, soldAt (the latest dated sale) },
--   byAuction  each live lot's sold part by auctionID: { net, sales, soldAt },
--   chips    up to two items by what they brought, most first: { positionKey, itemID, net },
--   more     how many items more brought something.
-- `keep` (optional) narrows the rows counted, by position key (the GROUPS row's pick).
function SoldLots.Summary(sold, lots, keep)
  local live = {}
  for _, lot in ipairs(type(lots) == "table" and lots or {}) do
    if type(lot) == "table" and lot.auctionID ~= nil then live[lot.auctionID] = true end
  end
  local out = { sales = 0, net = nil, soldOut = {}, byAuction = {}, chips = {}, more = 0 }
  local outByKey, itemNet, itemOrder = {}, {}, {}
  for _, row in ipairs(type(sold) == "table" and sold or {}) do
    if type(row) == "table" and type(row.positionKey) == "string" and whole(row.soldQty)
        and (not keep or keep(row.positionKey)) then
      local net = SoldLots.Net(row)
      out.sales = out.sales + 1
      if net then out.net = (out.net or 0) + net end
      local entry
      if live[row.auctionID] then
        entry = out.byAuction[row.auctionID] or { sales = 0 }
        out.byAuction[row.auctionID] = entry
      else
        entry = outByKey[row.positionKey]
        if not entry then
          entry = { positionKey = row.positionKey, itemID = row.itemID, soldQty = 0, sales = 0 }
          outByKey[row.positionKey] = entry
          out.soldOut[#out.soldOut + 1] = entry
        end
        entry.soldQty = entry.soldQty + row.soldQty
      end
      entry.sales = entry.sales + 1
      if net then entry.net = (entry.net or 0) + net end
      if row.soldAt and (not entry.soldAt or row.soldAt > entry.soldAt) then entry.soldAt = row.soldAt end
      if net then
        if not itemNet[row.positionKey] then
          itemNet[row.positionKey] = { positionKey = row.positionKey, itemID = row.itemID, net = 0 }
          itemOrder[#itemOrder + 1] = itemNet[row.positionKey]
        end
        itemNet[row.positionKey].net = itemNet[row.positionKey].net + net
      end
    end
  end
  local order = {}
  for index, item in ipairs(itemOrder) do order[item] = index end
  table.sort(itemOrder, function(a, b)
    if a.net ~= b.net then return a.net > b.net end
    return order[a] < order[b]
  end)
  for index, item in ipairs(itemOrder) do
    if index <= 2 then out.chips[#out.chips + 1] = item end
  end
  out.more = math.max(0, #itemOrder - 2)
  return out
end

--- Minutes since `soldAt`, the words for it ("51 min ago", "3 h ago"), or nil when not dated.
function SoldLots.Ago(soldAt, now)
  if not (whole(soldAt) and whole(now)) then return nil end
  local minutes = math.max(0, math.floor((now - soldAt) / 60))
  if minutes < 60 then return (GC.L["%d min ago"]):format(minutes) end
  return (GC.L["%d h ago"]):format(math.floor(minutes / 60))
end
