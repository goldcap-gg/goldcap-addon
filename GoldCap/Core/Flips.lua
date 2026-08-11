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
  if listedUnit or marketUnit then
    local basis = math.min(listedUnit or marketUnit, marketUnit or listedUnit)
    profit = math.floor((basis * 0.95 - flip.paidUnit) * flip.qty)
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
    invested = invested + row.boughtUnit * row.qty
    if row.profit ~= nil then
      profit = profit + row.profit
      projected = projected + row.boughtUnit * row.qty + row.profit
    end
  end
  return { invested = invested, projected = projected, profit = profit }
end
