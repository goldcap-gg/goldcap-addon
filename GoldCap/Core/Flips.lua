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

-- F1: true when the lot was bought, posted, sold, and collected -- i.e. a NON-pending sale of
-- this item has landed at or after the flip's own postedAt (falling back to boughtAt for a flip
-- that was never posted through the addon, though in practice BuildRow only reaches this branch
-- once listedUnit is nil, which an UNPOSTED flip already satisfies via UNLISTED further down --
-- see the precedence comment on BuildRow itself). `listedUnit == nil` is required alongside the
-- sale match: as long as an owned lot for this item still exists, whatever sold was some OTHER
-- batch/lot of the same item, not the one this flip is tracking.
--
-- Same name-match fuzziness caveat GC.Flips.SalesForItem's own comment documents: `sales` is
-- matched by item NAME only (a sale mail carries no itemID), so a same-named-but-different item
-- sale could in principle false-positive here. The `at >= floor` check narrows that window the
-- same way SalesForItem's own `sinceAt` narrows SOLD_PENDING's -- a sale that landed before this
-- flip was even posted can never satisfy it.
local function isSold(sales, flip, listedUnit)
  if listedUnit ~= nil then return false end
  local floor = flip.postedAt or flip.boughtAt
  for _, sale in ipairs(sales or {}) do
    if not sale.pending and (sale.at or 0) >= (floor or 0) then return true end
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
--
-- Sell-tab upgrade: `quote` is now { unit = <level-1 unit price>, levels = <ascending
-- {unitPrice,quantity} array, optional> } instead of a bare number -- `levels` is whatever the
-- caller's bounded book read (UI/SellFrame.lua's driver.commodityBook/itemBook, mirroring
-- SniperFrame.lua's own driver.commodityBook idiom) happened to capture, and is nil whenever
-- only a level-1 price is known (marketUnit still works exactly as before in that case; only
-- `ahead` degrades). `stats` is GC.Data.GetItemValue(flip.itemID)'s own return shape (or nil) --
-- BuildRow reads only .sold/.trend off it, so callers can pass the whole table through
-- unfiltered.
--
-- New fields on the returned row: `ahead` (GC.Flips.DepthBelow(quote.levels, listedUnit) --
-- how many posted units are cheaper than OUR OWN listed price, nil when unknowable) and
-- `outlook` (GC.Flips.SellOutlook{...} -- an honest queue-depth/velocity ETA, see that
-- function's own comment for why this is not a fabricated sell-probability number).
function GC.Flips.BuildRow(flip, ownedLots, quote, sales, stats)
  local listedUnit = listedUnitFor(flip.itemID, ownedLots)
  local marketUnit = quote and quote.unit or nil
  local levels = quote and quote.levels or nil

  local profit
  if (listedUnit or marketUnit) and type(flip.paidTotal) == "number" then
    local basis = math.min(listedUnit or marketUnit, marketUnit or listedUnit)
    local projectedNet = math.floor(basis * flip.qty * 95 / 100)
    profit = projectedNet - flip.paidTotal
  end

  -- Precedence (spec §5, extended by F1): a pending sale outranks everything else -- it's
  -- already sold, nothing left to post or repost. Next, SOLD (F1): the lot was bought, posted,
  -- and has since sold AND been collected -- possible now that GC.Data.GetFlips no longer
  -- prunes a flip the instant it's posted (see that function's own comment), so a flip can live
  -- long enough to observe its own sale land. Otherwise an owned lot priced above the current
  -- lowest ask is UNDERCUT; an owned lot with no fresh quote to compare against defaults to
  -- LISTED (can't prove it's undercut); no owned lot at all is UNLISTED.
  local status
  if isSoldPending(sales) then
    status = "SOLD_PENDING"
  elseif isSold(sales, flip, listedUnit) then
    status = "SOLD"
  elseif listedUnit and marketUnit and listedUnit > marketUnit then
    status = "UNDERCUT"
  elseif listedUnit then
    status = "LISTED"
  else
    status = "UNLISTED"
  end

  local ahead = GC.Flips.DepthBelow(levels, listedUnit)
  local outlook = GC.Flips.SellOutlook({
    ahead = ahead,
    qty = flip.qty,
    sold = stats and stats.sold,
    trend = stats and stats.trend,
  })

  return {
    itemID = flip.itemID,
    qty = flip.qty,
    boughtUnit = flip.paidUnit,
    paidTotal = flip.paidTotal,
    listedUnit = listedUnit,
    marketUnit = marketUnit,
    profit = profit,
    status = status,
    ahead = ahead,
    outlook = outlook,
  }
end

--- Sums a set of rows into the Sell-tab summary strip.
-- invested counts every row with a known cost basis -- the gold is already spent whether or
-- not a sale price is known yet. projected/profit only count rows with a known profit, since a
-- row with neither an owned lot nor a fresh quote has nothing to project.
--
-- Sell-tab upgrade: a row posted OUTSIDE GoldCap (UI/SellFrame.lua's orphan rows, built by
-- GC.Flips.OrphanLotRows below) carries boughtUnit == nil -- there is no recorded purchase to
-- derive a cost basis from, so it is skipped here entirely (not just its profit/projected
-- terms): folding a nil-basis row into `invested` would either error on the multiply or, worse,
-- silently understate what the player actually paid for everything ELSE in the list.
function GC.Flips.Summary(rows)
  local invested, projected, profit = 0, 0, 0
  for _, row in ipairs(rows or {}) do
    if type(row.paidTotal) == "number" then
      invested = invested + row.paidTotal
      if row.profit ~= nil then
        profit = profit + row.profit
        projected = projected + row.paidTotal + row.profit
      end
    end
  end
  return { invested = invested, projected = projected, profit = profit }
end

--- Total units strictly cheaper than `ourUnit` across `levels` (an ascending array of
-- {unitPrice, quantity} entries -- a commodity book or a set of competing item lots, both in
-- the shape UI/SellFrame.lua's bounded book reader produces). A level priced EXACTLY at
-- ourUnit is not counted: the AH doesn't expose the intra-tie ordering, and a tie is not the
-- same fact as "N units are cheaper than mine" -- reporting it as ahead would overstate the
-- competition. Returns nil (never 0) whenever the question can't honestly be answered: no book
-- was read yet (`levels` nil/empty) or there's no lot of ours to compare against yet
-- (`ourUnit` nil, e.g. UNLISTED) -- "unknown" and "zero competitors" must stay visibly distinct
-- to the player.
function GC.Flips.DepthBelow(levels, ourUnit)
  if not levels or #levels == 0 or ourUnit == nil then return nil end
  local total = 0
  for _, lvl in ipairs(levels) do
    if lvl.unitPrice < ourUnit then
      total = total + (lvl.quantity or 0)
    end
  end
  return total
end

--- Estimated time-to-sell, expressed as an honest queue-depth-over-velocity ETA -- deliberately
-- NOT a fabricated sell-probability percentage. GC.Data.GetItemValue's `sold` field (sold/day,
-- scraped AH history imported from goldcap.gg) is the only genuinely-measured demand signal
-- this addon has; TSM's own market-value tooltip leans on the identical sold-per-day idea for
-- the same reason. "units queued ahead of mine, divided by units that sell per day" is a
-- defensible ETA; inventing a % chance-to-sell from the same two inputs would not be -- there is
-- no historical fill-rate data behind such a number, so it would just be a guess wearing a
-- precise-looking mask. Returns nil outright when `sold` is unknown or non-positive: absence of
-- import data must never silently become a fabricated estimate.
--
-- `trend` (24h market-value % change, also from GC.Data.GetItemValue) nudges the ETA rather
-- than the velocity itself, because `sold` already measures actual past throughput -- a falling
-- market (trend <= -10) is read as buyers pulling back faster than the sold/day figure has
-- caught up to yet, so the queue is assumed to drain 1.5x slower; a rising market (trend >= 10)
-- the opposite, 0.75x. Thresholds/multipliers are deliberately coarse (a blunt "meaningfully
-- moving" signal, not a precision model) since trend is a single 24h snapshot, not a trend line.
function GC.Flips.SellOutlook(args)
  args = args or {}
  local sold = args.sold
  if not sold or sold <= 0 then return nil end

  local days = ((args.ahead or 0) + (args.qty or 0)) / sold
  if args.trend and args.trend <= -10 then
    days = days * 1.5
  elseif args.trend and args.trend >= 10 then
    days = days * 0.75
  end

  local tier
  if days < 1 then
    tier = "FAST"
  elseif days < 3 then
    tier = "OK"
  elseif days < 7 then
    tier = "SLOW"
  else
    tier = "STALL"
  end

  return { days = days, tier = tier }
end

-- ---------------------------------------------------------------------------
-- Task 9 fix round 1 (minor): the Sell-tab composition helpers below were originally local to
-- UI/SellFrame.lua -- moved here so they're pure, WoW-API-free, and busted-tested like
-- BuildRow/Summary above, instead of only reachable through the UI file's own headless
-- load-order coverage.
-- ---------------------------------------------------------------------------

--- Normalizes C_AuctionHouse.GetOwnedAuctions()'s raw AuctionInfo entries to the
-- {itemID, unitPrice, auctionID, quantity} shape BuildRow/CheapestOwnedLot/OrphanLotRows expect.
-- `auctions` is whatever the caller already fetched -- this function never touches a WoW API
-- itself.
--
-- A commodity lot reports `unitPrice` directly (already per-unit). A single-item lot reports
-- `buyoutAmount` for the WHOLE LOT -- fix round 1 (I3): a stacked item lot (quantity > 1, e.g.
-- 5 of a BoE posted together) must divide by `quantity` or it reads as priced 5x higher than it
-- actually is, which false-positives an UNDERCUT/loss projection against a perfectly healthy
-- lot. `quantity` is guarded defensively (missing/zero treated as 1) since not every caller of
-- this function is guaranteed to have it. Lots with neither field set (zero/no buyout) are
-- dropped -- nothing to compare or cancel.
--
-- Sell-tab upgrade: `quantity` is now carried through onto the returned lot too (same
-- missing/zero-defaults-to-1 guard as the division above) -- GC.Flips.OrphanLotRows needs the
-- per-lot unit count to aggregate an orphan's total qty across however many lots it's spread
-- across; nothing before this needed it on the lot itself (only the pre-division local above).
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
      local quantity = (a.quantity and a.quantity > 0) and a.quantity or 1
      lots[#lots + 1] = { itemID = itemID, itemKey = a.itemKey, isCommodity = a.isCommodity == true,
        unitPrice = unitPrice, auctionID = a.auctionID, quantity = quantity }
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

-- ---------------------------------------------------------------------------
-- Sell-tab upgrade: "I can't see my own posted auctions" -- ownedLots today only ever gets USED
-- to enrich a flip row (listedUnit/status above); a lot whose itemID has no matching flip
-- record (posted manually, via Blizzard's own AH window, or a flip that aged out of db.flips
-- via GC.Data.GetFlips' 14-day prune while the lot itself is still up) was previously invisible
-- to the whole Sell tab. OrphanLotRows/EnrichOrphanRow below build a second, parallel row kind
-- for exactly those lots; UI/SellFrame.lua's renderRows appends them after the ordinary flip
-- rows and renders them read-only (no cost basis to post/repost/remove against -- see
-- EnrichOrphanRow's own comment and setRowOrphan in that file).
-- ---------------------------------------------------------------------------

--- Aggregates `ownedLots` (GC.Flips.ExtractOwnedLots' own shape) into one row per itemID that
-- has NO matching entry in `flips` (GC.Data.GetFlips' own shape) -- i.e. lots posted outside
-- GoldCap's own buy-then-flip flow. Deliberately split from the live-market enrichment below
-- (EnrichOrphanRow) so aggregation-from-owned-lots and pricing-against-a-quote stay
-- independently testable, mirroring BuildRow/Summary's own split.
--
-- Per-itemID aggregate fields: `qty` sums quantity across every one of the item's lots (a
-- player thinks "I have 340 Ironclaw Ore up," not per-lot); `listedUnit` is the CHEAPEST of
-- those lots (same "can't sell below your own cheapest ask" framing BuildRow's listedUnit
-- carries); `lotCount` is how many separate auctions that qty is spread across (surfaced in the
-- UI as a " (N lots)" suffix so a player isn't confused why one itemID shows several different
-- listedUnit-implying stacks). Sorted by itemID ascending purely for a stable, deterministic
-- render order across calls with the same input -- there is no meaningful "priority" ordering
-- for orphans the way SellOutlook's tiers imply one for flips.
function GC.Flips.OrphanLotRows(ownedLots, flips)
  local flipItemIDs = {}
  for _, f in ipairs(flips or {}) do
    flipItemIDs[f.itemID] = true
  end

  local byItem, order = {}, {}
  for _, lot in ipairs(ownedLots or {}) do
    if not flipItemIDs[lot.itemID] then
      local agg = byItem[lot.itemID]
      if not agg then
        agg = { itemID = lot.itemID, qty = 0, listedUnit = nil, lotCount = 0, orphan = true }
        byItem[lot.itemID] = agg
        order[#order + 1] = lot.itemID
      end
      local qty = (lot.quantity and lot.quantity > 0) and lot.quantity or 1
      agg.qty = agg.qty + qty
      agg.lotCount = agg.lotCount + 1
      if not agg.listedUnit or lot.unitPrice < agg.listedUnit then
        agg.listedUnit = lot.unitPrice
      end
    end
  end

  table.sort(order)
  local rows = {}
  for _, itemID in ipairs(order) do
    rows[#rows + 1] = byItem[itemID]
  end
  return rows
end

--- Adds live-market context to one GC.Flips.OrphanLotRows() entry -- `quote`/`stats` are the
-- exact same shapes BuildRow's own params take ({unit, levels} or nil; GC.Data.GetItemValue's
-- return or nil), so a caller composing both row kinds in the same pass (UI/SellFrame.lua's
-- renderRows) doesn't need two different lookups. Returns a NEW table (the input `orphanRow` is
-- never mutated -- OrphanLotRows' own aggregate is cheap to recompute and callers may reasonably
-- hold onto it across an enrichment call).
--
-- status mirrors BuildRow's own UNDERCUT/LISTED split (there is no UNLISTED/SOLD_PENDING case
-- here -- an orphan row only exists because a lot IS currently posted, and it has no flip to
-- carry a ledger-sale match against): UNDERCUT when our cheapest lot sits above the fresh ask,
-- LISTED otherwise (including "no fresh quote yet" -- can't prove undercut without one, same
-- default BuildRow uses).
function GC.Flips.EnrichOrphanRow(orphanRow, quote, stats)
  local marketUnit = quote and quote.unit or nil
  local levels = quote and quote.levels or nil
  local ahead = GC.Flips.DepthBelow(levels, orphanRow.listedUnit)
  local outlook = GC.Flips.SellOutlook({
    ahead = ahead,
    qty = orphanRow.qty,
    sold = stats and stats.sold,
    trend = stats and stats.trend,
  })
  local status = (marketUnit and orphanRow.listedUnit > marketUnit) and "UNDERCUT" or "LISTED"

  local row = {}
  for k, v in pairs(orphanRow) do row[k] = v end
  row.marketUnit = marketUnit
  row.ahead = ahead
  row.outlook = outlook
  row.status = status
  return row
end

--- The row tooltip's "Recommended post" line (design update to the Sell-tab upgrade, per
-- direct player feedback: a price recommendation with a visible breakeven floor, not just a
-- bare status chip). Pure: `paidUnit`/`marketUnit`/`mv` are whatever the caller already has on
-- hand -- see UI/SellFrame.lua's createRow OnEnter for exactly what it passes as each.
--
-- candidate: undercut the live ask by one whole silver (`SilverDown(marketUnit - 1)`) when a
-- fresh quote exists AND the item is worth enough that one silver is a small share of the price;
-- otherwise fall back to `mv` (whatever the caller decided "the best available market read"
-- means when there's no live quote -- see the cross-reference comment on UI/SellFrame.lua's
-- onPostClick for why the row tooltip specifically feeds this flip.targetUnit rather than a
-- second, independently-fresh GC.Data.GetItemValue read: it must never show a different number
-- than what Post would actually post at). Every candidate is normalized to the 100-copper grid
-- (see GC.Flips.SilverDown/SilverUp below) -- PostCommodity/PostItem silently reject anything
-- else. nil candidate (both marketUnit and mv unknown) means nothing to recommend.
--
-- breakeven: the unit price at which the AH's 5% cut exactly cancels out what was paid --
-- ceil (not floor) so a rounded-down breakeven couldn't itself understate a loss. nil whenever
-- paidUnit is unknown (an orphan row -- no recorded purchase, so no cost basis to break even
-- against; RecommendPost is deliberately not called for those rows at all, per the file header
-- above and UI/SellFrame.lua's OnEnter). Deliberately left UNNORMALIZED -- it is a displayed
-- threshold to compare a price against, never itself posted, so there is nothing for it to fail
-- to post at.
--
-- belowCost: true when the recommended candidate would sell at a loss even before the 5% cut is
-- accounted for a second time -- i.e. candidate itself sits below the price where costs are
-- merely recovered. Surfaced as a loud, separate warning line rather than folded into the main
-- recommendation text.
--
-- F3 ("match, don't undercut"): `opts = { levels, sold }` (both optional; omitting either falls
-- through to the undercut/match choice below). Racing to the bottom one silver at a time is
-- wasted effort when the CHEAPEST price tier sells out fast enough that being anywhere IN that
-- tier is enough -- buyers consume the whole tier, not just the single lowest listing, so
-- undercutting it buys nothing but a smaller margin. When marketUnit, opts.levels (with a first
-- entry -- levels is assumed pre-sorted ascending, same convention DepthBelow's callers already
-- follow) and a positive opts.sold are ALL present: tierDepth sums quantity across every level
-- priced exactly at the book's own cheapest unit price. `opts.sold >= 2 * tierDepth` -- "the
-- whole cheapest tier turns over in half a day or less at current velocity" -- is a deliberately
-- coarse rule of thumb, not a probability model: sold/day is a single realm-wide daily figure
-- (GC.Data.GetItemValue), not a real-time fill-rate feed, so there is no honest way to derive a
-- sharper threshold from it. When it holds, mode="match" and the candidate becomes (a
-- grid-normalized) marketUnit itself; otherwise the match-vs-undercut choice falls to the
-- silver-grid share rule below, which is its own, independent reason to match (Part 0 of the
-- posting-queue design, 2026-08-17) -- either reason alone is sufficient, and this tier/velocity
-- rule keeps the precedence it already had. The no-quote (mv) fallback branch always leaves mode
-- nil -- there is no ask to match OR undercut, so neither label applies.
-- How far below the item's market value a live ask may sit before it stops being
-- a price and starts being noise. Ordinary undercutting runs a few percent; a
-- quarter off is not a market, it is one seller in a hurry.
GC.Flips.UNDERPRICE_FLOOR = 0.75

-- How many DISTINCT competing price levels have to sit below the floor before
-- the book is believed even without a velocity figure. This exists because the
-- velocity escape below only ever fires when GC.Data.GetItemValue's `sold` is
-- present, and it usually is not: `sold` comes from the import's optional `s`
-- field, absent for every realm/non-commodity item and for any commodity the
-- ingest has no throughput figure for. Without a second escape the floor held
-- at ANY depth on those items -- thousands of units could sit under a stale
-- market value and GoldCap would still hold out at 75% of it, pricing a lot
-- above a market that had genuinely moved and leaving it unsold.
--
-- One or two levels is exactly the shape of the original loss (a single
-- lingering lot, or that lot plus one more) and must still hold. Three
-- independent sellers agreeing on a lower price is not noise -- nobody
-- coordinates three unrelated auctions to fake a floor, so by the third
-- distinct level the simplest explanation is that the price actually moved.
GC.Flips.MOVED_MARKET_LEVELS = 3

--- The lowest price worth posting at, or nil if the book can be believed as-is.
--
-- Exists because of a real loss: Sanguithorn was posted at 7g against a market
-- value of 20g, because a single lot sat at 7g and the Sell tab's entire notion
-- of "market" was the cheapest competing ask. Matching that lot handed away two
-- thirds of the item's worth to beat one seller who was about to clear anyway.
--
-- The two numbers answer different questions. The cheapest ask is what you must
-- beat to sell *now*; the market value is what the thing is *worth*. When they
-- agree, the ask wins and nothing here applies. When the ask is far below, one
-- of them is wrong, and depth decides which: a day's worth of supply under the
-- floor is a genuine price move and the book is believed; a lot or two is noise
-- and the floor holds.
--
-- The asymmetry is deliberate. Holding above a thin undercut costs a deposit and
-- some waiting -- the cheap lot sells, then yours does. Chasing it costs the
-- difference, in gold, immediately and irreversibly.
--
-- args = { marketUnit (the cheapest competing ask), mv, levels, sold, heldQty }.
-- Returns floor, qtyBelowFloor -- or nil when the book needs no correcting.
--
-- Two independent escapes decide "the book should be believed," combined with OR: either is
-- sufficient on its own, and neither is required when the other already fired. The velocity
-- escape (below >= sold) is the original rule and needs an imported `sold` figure that most
-- items don't have. The level-count escape below is the one that works without it -- see
-- GC.Flips.MOVED_MARKET_LEVELS for why three distinct competing levels is the line.
--
-- The level-count escape alone had a hole: three distinct prices below the floor released it no
-- matter how thin each one was, so a seller posting one unit each at three prices under the
-- floor could make GoldCap price a 200-unit stack against the cheapest of them -- the exact
-- underpricing loss this function exists to prevent, just reached through a different door. The
-- fix is the same idea the velocity escape already uses, one level down: "a whole day's supply
-- sits under the floor" and "more units sit under the floor than I am trying to sell" are both
-- ways of saying the cheap stock will not simply clear ahead of mine. Three units under a
-- 200-unit stack clear in minutes and my price is still the market; 200 units under my 200 mean
-- the market really is down there. So the level-count escape only fires when it is ALSO true
-- that `below` covers at least `heldQty` -- the caller's own bag-plus-listed quantity, when it
-- bothers to pass one. A caller that doesn't (every existing one, today) gets the un-gated
-- level-count rule back, so this must never make PostFloor refuse to answer for want of a new
-- argument.
function GC.Flips.PostFloor(args)
  args = args or {}
  local mv, ask = args.mv, args.marketUnit
  if type(mv) ~= "number" or mv <= 0 then return nil end
  local floor = math.floor(mv * GC.Flips.UNDERPRICE_FLOOR)
  if floor <= 0 then return nil end
  if type(ask) ~= "number" or ask >= floor then return nil end

  local below = 0
  local seenPrices, distinctLevelsBelow = {}, 0
  for _, level in ipairs(args.levels or {}) do
    local unit = type(level.unitPrice) == "number" and level.unitPrice or nil
    if unit and unit < floor then
      local quantity = type(level.quantity) == "number" and level.quantity or 0
      -- The player's own units are not competition and must not be counted as
      -- evidence that the market has moved -- same reasoning as
      -- SellPositions.CheapestCompetingUnit. This feeds `below`, which is what
      -- both escapes below compare against -- so the player's own cheap stock
      -- can't satisfy the depth requirement any more than it can satisfy the
      -- level count.
      local ownerQty = type(level.ownerQty) == "number" and level.ownerQty
        or (level.ownerItem == true and quantity) or 0
      local competing = math.max(0, quantity - ownerQty)
      below = below + competing
      -- A level with nobody else's stock on it is not a second opinion, it's the
      -- same non-evidence the quantity subtraction above already excludes -- so
      -- it must not count toward "distinct sellers," either. Distinct means
      -- distinct unitPrice: two lots at the same price are one seller's worth of
      -- price signal, not two.
      if competing > 0 and not seenPrices[unit] then
        seenPrices[unit] = true
        distinctLevelsBelow = distinctLevelsBelow + 1
      end
    end
  end

  local sold = type(args.sold) == "number" and args.sold or nil
  local velocityMoved = sold and sold > 0 and below >= sold

  local heldQty = type(args.heldQty) == "number" and args.heldQty > 0 and args.heldQty or nil
  local depthMoved = heldQty == nil or below >= heldQty
  local levelsMoved = distinctLevelsBelow >= GC.Flips.MOVED_MARKET_LEVELS and depthMoved

  if velocityMoved or levelsMoved then return nil, below end
  return floor, below
end

-- ---------------------------------------------------------------------------
-- Part 0 of the posting-queue design (2026-08-17) -- a shipped bug. warcraft.wiki.gg, verbatim,
-- about PostCommodity's unitPrice and about PostItem's bid/buyout: "Amount in copper, only
-- accepts gold and silver and silently fails for non-zero copper counts." The undercut branch
-- below used to return `math.max(1, marketUnit - 1)`, and there was no silver rounding anywhere
-- in the addon. Every competing ask is itself whole silver -- the same API forces every other
-- seller onto the same grid -- so `marketUnit - 1` always carried a non-zero copper remainder,
-- and the post silently failed: the player saw the button go dead and "Posting timed out" eight
-- seconds later. Floor mode (`math.floor(mv * UNDERPRICE_FLOOR)`) failed the same way almost
-- always; match mode was the only one that ever worked, because it posts at the ask itself.
-- ---------------------------------------------------------------------------

-- One silver, in copper -- the smallest unit PostCommodity/PostItem will ever accept.
GC.Flips.SILVER = 100

--- Rounds `copper` DOWN to the nearest whole silver -- the direction that keeps an undercut as
-- cheap as the grid allows without ever landing above the ask it is undercutting. The result is
-- then clamped UP to GC.Flips.SILVER when that would put it below one silver: a price under one
-- silver cannot be posted at all, so 100 copper is the floor of the whole grid, not a rounding
-- preference that could ever produce less.
--
-- Fails closed -- returns nil -- on nil, a non-number, NaN, +-infinity, or a negative value.
-- None of those describe a price; they describe a bug somewhere upstream. Clamping a negative or
-- garbage input up to a plausible-looking 100 would hide that bug behind a real auction, so this
-- declines instead. Every caller in this file already treats a nil candidate the same way it
-- treats "nothing to recommend," so nil propagates safely rather than crashing or posting at a
-- guessed number.
function GC.Flips.SilverDown(copper)
  if type(copper) ~= "number" or copper ~= copper or copper == math.huge
      or copper == -math.huge or copper < 0 then
    return nil
  end
  return math.max(GC.Flips.SILVER, math.floor(copper / GC.Flips.SILVER) * GC.Flips.SILVER)
end

--- As GC.Flips.SilverDown, but rounds UP -- the direction the floor override below needs: it
-- must never hand back a price under the floor it exists to enforce, and rounding down could do
-- exactly that. Same clamp, same fail-closed input contract as SilverDown.
function GC.Flips.SilverUp(copper)
  if type(copper) ~= "number" or copper ~= copper or copper == math.huge
      or copper == -math.huge or copper < 0 then
    return nil
  end
  return math.max(GC.Flips.SILVER, math.ceil(copper / GC.Flips.SILVER) * GC.Flips.SILVER)
end

-- The largest share of a unit's price a flat one-silver undercut is allowed to cost before
-- match wins instead. Against a whole-silver competitor (every real one, per the file header
-- above) the only undercut the grid allows is a flat 100 copper below, so solving
-- `SILVER > marketUnit * UNDERCUT_MAX_SHARE` puts the actual boundary this code implements at
-- marketUnit = 5,000 copper (50 silver / 0.5g): below that, a flat silver eats more than 2% of
-- the price and match wins; at 50s and above, the step is cheap enough that undercutting is
-- still worth it.
GC.Flips.UNDERCUT_MAX_SHARE = 0.02

function GC.Flips.RecommendPost(paidUnit, marketUnit, mv, opts)
  opts = opts or {}
  local mode, candidate

  -- Tier-depth/velocity match (F3, unchanged precedence): candidate is grid-normalized too,
  -- defensively -- a live marketUnit should already be whole silver (it couldn't have posted
  -- otherwise), so this is a no-op on every real input, and a fail-closed guard against whatever
  -- reaches this function with a marketUnit that isn't.
  if marketUnit and opts.levels and opts.levels[1] and opts.sold and opts.sold > 0 then
    local cheapest = opts.levels[1].unitPrice
    local tierDepth = 0
    for _, lvl in ipairs(opts.levels) do
      if lvl.unitPrice == cheapest then tierDepth = tierDepth + (lvl.quantity or 0) end
    end
    if opts.sold >= 2 * tierDepth then
      mode, candidate = "match", GC.Flips.SilverDown(marketUnit)
    end
  end

  -- Silver-grid share rule (Part 0): a second, independent reason to match. Either this or the
  -- tier/velocity rule above is sufficient on its own; neither is required when the other has
  -- already fired.
  if not mode and marketUnit then
    local undercut = GC.Flips.SilverDown(marketUnit - 1)
    local shareTooBig = undercut and (marketUnit - undercut) > marketUnit * GC.Flips.UNDERCUT_MAX_SHARE
    -- `undercut < marketUnit` is not redundant with the share rule. At an ask of exactly one
    -- silver, SilverDown's clamp -- the grid has no rung below 100 copper -- hands back the ask
    -- itself, and a zero-copper step trivially passes the share test. Without this the row would
    -- report "undercutting" while posting at precisely the competitor's price. The number would
    -- have been right and the word wrong, which is the failure this whole batch is about.
    if undercut and undercut < marketUnit and not shareTooBig then
      mode, candidate = "undercut", undercut
    else
      mode, candidate = "match", GC.Flips.SilverDown(marketUnit)
    end
  end

  if not mode then
    candidate = mv and GC.Flips.SilverDown(mv)
  end

  if candidate == nil then return nil end

  -- F5, queue-at-exit: the sell-side mirror of SniperDecision's velocity release. A flip the
  -- sniper underwrote carries the exit it was approved against (opts.targetUnit, the batch's
  -- stored stress exit); matching the current cheapest ask instead -- often the very wall the
  -- flip was bought FROM -- locks in the 5% cut as a loss and contradicts the engine's own
  -- approval. When the units queued at or below a rung of the ladder fit inside
  -- `absorbHours` of the item's measured daily sales, that rung is reachable within the
  -- window -- post AT the highest reachable rung, capped by the target. The queue includes
  -- the rung's own stock (a new post joins that price's tail). Only positions with a target
  -- get this: untracked bag stock keeps the match/undercut behaviour unchanged.
  if opts.targetUnit and opts.levels and opts.sold and opts.sold > 0 then
    local hours = opts.absorbHours == nil and 2 or opts.absorbHours
    -- Spike deflation, same rule and constant as the buy side (see SniperDecision's
    -- SPIKE_TREND_PCT): a batch's stored target was computed from a 24h tape, and when the
    -- CURRENT trend says the market is mid-spike, queueing at that number chases the spike.
    local target = opts.targetUnit
    local spikePct = (GC.SniperDecision and GC.SniperDecision.SPIKE_TREND_PCT) or 30
    if type(opts.trendPct) == "number" and opts.trendPct > spikePct then
      target = math.floor(target / (1 + opts.trendPct / 100))
    end
    local ceiling = GC.Flips.SilverDown(target)
    if hours > 0 and ceiling and ceiling > candidate then
      local budget = opts.sold * hours / 24
      local best
      local queued, overBudget, sawAboveCeiling = 0, false, false
      for _, lvl in ipairs(opts.levels) do
        local qty = lvl.quantity or 0
        if qty > 0 then
          if lvl.unitPrice > ceiling then sawAboveCeiling = true; break end
          queued = queued + qty
          if queued > budget then overBudget = true; break end
          if lvl.unitPrice > candidate then best = lvl.unitPrice end
        end
      end
      -- The ceiling itself is a candidate ONLY when a stocked ask ABOVE it was seen: levels
      -- arrive ascending and are capped (LIM.MAX_BOOK_LEVELS), so a book that simply ENDS
      -- below the ceiling proves nothing about the units between its last rung and the
      -- ceiling -- jumping past the end of a truncated book is how a post lands above a
      -- queue nobody measured. With a visible ask above, everything below was visible and
      -- counted, and the jump is proven.
      if not overBudget and sawAboveCeiling then best = ceiling end
      best = best and GC.Flips.SilverDown(best)
      if best and best > candidate then
        mode, candidate = "queue", best
      end
    end
  end

  -- Never recommend below the floor. See GC.Flips.PostFloor for why a live ask can be worth
  -- ignoring, and what it cost to learn that. Runs LAST and rounds UP: normalising a candidate
  -- that already cleared every earlier check can only ever raise it, so it can never re-drop the
  -- price under the very floor this override exists to enforce.
  local floor = opts.floor
  if type(floor) == "number" and floor > 0 and candidate < floor then
    mode, candidate = "floor", GC.Flips.SilverUp(floor)
  end

  -- Deliberately unnormalized -- breakeven is a displayed threshold to compare a price against,
  -- never itself posted, so there is nothing here for the grid to protect.
  local breakeven = paidUnit and math.ceil(paidUnit / 0.95) or nil

  return {
    unit = candidate,
    mode = mode,
    breakeven = breakeven,
    belowCost = (breakeven ~= nil and candidate < breakeven) or false,
  }
end

-- ---------------------------------------------------------------------------
-- F4: repost advice. Blizzard throttles auction cancels (since patch 8.3) -- a blind
-- cancel-and-repost wastes a share of that limited budget, and can lock in a loss the player
-- never actually meant to take. GC.Flips.RepostAdvice is a pure pre-flight check UI/SellFrame.lua's
-- onRepostClick gates the FIRST click of its two-click cancel flow behind (see that file's own
-- comment on the armed/disarm pattern this reuses).
-- ---------------------------------------------------------------------------

--- args = { paidUnit, marketUnit, mv, levels, sold, qty }. Returns nil, or
-- { action = "hold"|"repost", reason = "loss"|"slow" (hold only), rec = <RecommendPost's own
-- return> }.
--
-- rec reuses GC.Flips.RecommendPost with the SAME inputs the row's own Post/tooltip flow already
-- computes from -- one recommendation, one derivation, reused here rather than re-derived with
-- its own copy of the match/undercut branching. A nil rec (neither marketUnit nor mv known)
-- means there is nothing to advise on yet, so RepostAdvice itself returns nil too.
--
-- hold/loss: rec.belowCost already means posting AT THE RECOMMENDED PRICE would lock in a loss
-- -- cancelling the existing (possibly still break-even-or-better) lot to chase that price is
-- strictly worse than doing nothing, so this check runs FIRST and short-circuits the slow-queue
-- check below (a losing repost is never merely "slow," it's a straightforwardly bad idea
-- regardless of how fast it would sell).
--
-- hold/slow: estimates the queue the player would actually join AT THE NEW price -- aheadAtNew
-- via GC.Flips.DepthBelow(levels, rec.unit), nil-safe: an unknown book (levels absent) yields an
-- unknown queue depth, which is read as "cannot prove this repost is bad" and falls through to
-- "repost" rather than blocking the player on data GoldCap simply doesn't have yet. That depth
-- feeds the same GC.Flips.SellOutlook queue-depth/velocity model the row's own ETA already
-- uses; an outlook.tier of STALL at the NEW price means the deposit/cancel-budget spend would
-- likely sit unsold for a week-plus -- not worth spending one of a limited number of cancels on.
--
-- repost: neither guard fired -- cancelling and reposting at rec.unit is judged worth it.
function GC.Flips.RepostAdvice(args)
  args = args or {}
  local rec = GC.Flips.RecommendPost(args.paidUnit, args.marketUnit, args.mv,
    { levels = args.levels, sold = args.sold, floor = args.floor })
  if not rec then return nil end

  if rec.belowCost then
    return { action = "hold", reason = "loss", rec = rec }
  end

  local aheadAtNew = GC.Flips.DepthBelow(args.levels, rec.unit)
  local outlook = GC.Flips.SellOutlook({ ahead = aheadAtNew, qty = args.qty, sold = args.sold })
  if outlook and outlook.tier == "STALL" then
    return { action = "hold", reason = "slow", rec = rec }
  end

  return { action = "repost", rec = rec }
end
