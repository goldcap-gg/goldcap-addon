local _, GC = ...

GC.Flips = {}

-- Lowest unit price among the caller's owned lots for this item, or nil if
-- none are currently listed. ownedLots is pre-extracted by the caller from
-- C_AuctionHouse.GetOwnedAuctions() -- this module never touches WoW APIs.
local function listedUnitFor(itemID, ownedLots)
  local min
  for _, lot in ipairs(ownedLots or {}) do
    if lot.itemID == itemID and (min == nil or lot.unitPrice < min) then
      min = lot.unitPrice
    end
  end
  return min
end

-- True when any ledger sale entry for this item is still "Sale Pending" --
-- money attached but not yet collected. sales is pre-filtered by the caller
-- to kind=="sale" rows for this itemID.
local function isSoldPending(sales)
  for _, sale in ipairs(sales or {}) do
    if sale.pending then return true end
  end
  return false
end

--- Builds one Sell-tab row from a recorded flip plus its live context.
-- Pure: no WoW API calls, no globals besides math -- callers gather
-- ownedLots/quote/sales beforehand and pass them in.
--
-- profit projects a resale at whichever of listedUnit/marketUnit is LOWER
-- (you cannot sell above what's already listed, nor above the fresh ask),
-- after the 5% AH cut, minus what was paid, times qty. It is nil when
-- neither an owned lot nor a fresh quote exists -- there is nothing to
-- project against yet.
function GC.Flips.BuildRow(flip, ownedLots, quote, sales)
  local listedUnit = listedUnitFor(flip.itemID, ownedLots)
  local marketUnit = quote and quote.unit or nil

  local profit
  if (listedUnit or marketUnit) and type(flip.paidTotal) == "number" then
    local basis = math.min(listedUnit or marketUnit, marketUnit or listedUnit)
    local projectedNet = math.floor(basis * flip.qty * 95 / 100)
    profit = projectedNet - flip.paidTotal
  end

  -- Precedence (spec §5): a pending sale outranks everything else -- it's
  -- already sold, nothing left to post or repost. Otherwise an owned lot
  -- priced above the current lowest ask is UNDERCUT; an owned lot with no
  -- fresh quote to compare against defaults to LISTED (can't prove it's
  -- undercut); no owned lot at all is UNLISTED.
  local status
  if isSoldPending(sales) then
    status = "SOLD_PENDING"
  elseif listedUnit and marketUnit and listedUnit > marketUnit then
    status = "UNDERCUT"
  elseif listedUnit then
    status = "LISTED"
  else
    status = "UNLISTED"
  end

  return {
    itemID = flip.itemID,
    qty = flip.qty,
    boughtUnit = flip.paidUnit,
    paidTotal = flip.paidTotal,
    listedUnit = listedUnit,
    marketUnit = marketUnit,
    profit = profit,
    status = status,
  }
end

--- Sums a set of rows into the Sell-tab summary strip.
-- invested counts every row -- the gold is already spent whether or not a
-- sale price is known yet. projected/profit only count rows with a known
-- profit, since a row with neither an owned lot nor a fresh quote has
-- nothing to project.
function GC.Flips.Summary(rows)
  local invested, projected, profit = 0, 0, 0
  for _, row in ipairs(rows or {}) do
    if type(row.paidTotal) == "number" then
      invested = invested + row.paidTotal
    end
    if row.profit ~= nil and type(row.paidTotal) == "number" then
      profit = profit + row.profit
      projected = projected + row.paidTotal + row.profit
    end
  end
  return { invested = invested, projected = projected, profit = profit }
end

-- ---------------------------------------------------------------------------
-- Task 9 fix round 1 (minor): the Sell-tab composition helpers below were originally local to
-- UI/SellFrame.lua -- moved here so they're pure, WoW-API-free, and busted-tested like
-- BuildRow/Summary above, instead of only reachable through the UI file's own headless
-- load-order coverage.
-- ---------------------------------------------------------------------------

--- Normalizes C_AuctionHouse.GetOwnedAuctions()'s raw AuctionInfo entries to the
-- {itemID, unitPrice, auctionID} shape BuildRow/CheapestOwnedLot expect. `auctions` is
-- whatever the caller already fetched -- this function never touches a WoW API itself.
--
-- A commodity lot reports `unitPrice` directly (already per-unit). A single-item lot reports
-- `buyoutAmount` for the WHOLE LOT -- fix round 1 (I3): a stacked item lot (quantity > 1, e.g.
-- 5 of a BoE posted together) must divide by `quantity` or it reads as priced 5x higher than it
-- actually is, which false-positives an UNDERCUT/loss projection against a perfectly healthy
-- lot. `quantity` is guarded defensively (missing/zero treated as 1) since not every caller of
-- this function is guaranteed to have it. Lots with neither field set (zero/no buyout) are
-- dropped -- nothing to compare or cancel.
function GC.Flips.ExtractOwnedLots(auctions)
  local lots = {}
  for _, a in ipairs(auctions or {}) do
    local itemID = a.itemKey and a.itemKey.itemID
    local unitPrice
    if a.unitPrice and a.unitPrice > 0 then
      unitPrice = a.unitPrice
    elseif a.buyoutAmount and a.buyoutAmount > 0 then
      local qty = (a.quantity and a.quantity > 0) and a.quantity or 1
      unitPrice = math.floor(a.buyoutAmount / qty)
    end
    if itemID and unitPrice then
      lots[#lots + 1] = { itemID = itemID, unitPrice = unitPrice, auctionID = a.auctionID }
    end
  end
  return lots
end

--- Cheapest owned lot for itemID, WITH its auctionID -- unlike the private listedUnitFor above
-- (which BuildRow only ever needs a bare price from), Repost's cancel step needs to know
-- exactly which lot to cancel.
function GC.Flips.CheapestOwnedLot(itemID, lots)
  local best
  for _, lot in ipairs(lots or {}) do
    if lot.itemID == itemID and (not best or lot.unitPrice < best.unitPrice) then
      best = lot
    end
  end
  return best
end

--- Sale ledger entries for a single item name, at or after `sinceAt`. `entries` is the caller's
-- full ledger (e.g. GC.Ledger.GetEntries()) -- this function does the kind=="sale" + itemName +
-- date filtering in one pass, since Core/Ledger.lua's sale entries never carry itemID (a sale
-- mail has money attached and nothing else -- itemName is all there is to key a flip against).
--
-- fix round 1 (I6): `sinceAt` (a flip's own boughtAt) closes the "eternal SOLD_PENDING" bug --
-- without it, an ancient sale of a same-named item (e.g. a much earlier, already-fully-resolved
-- flip for the identical item) could keep a brand-new, never-yet-posted flip showing
-- SOLD_PENDING forever, since name-only matching has no other way to tell them apart. This also
-- narrows the name-fuzziness window itself: a stale, unrelated sale from before this flip was
-- even bought can no longer match it at all, regardless of name collisions.
function GC.Flips.SalesForItem(entries, itemName, sinceAt)
  local out = {}
  if not itemName then return out end
  for _, e in ipairs(entries or {}) do
    if e.kind == "sale" and e.itemName == itemName and (e.at or 0) >= (sinceAt or 0) then
      out[#out + 1] = e
    end
  end
  return out
end
