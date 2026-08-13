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
-- candidate: undercut the live ask by 1 copper (`marketUnit - 1`, floored at 1c so a 1c ask
-- can't drive a negative/zero recommendation) when a fresh quote exists; otherwise fall back to
-- `mv` (whatever the caller decided "the best available market read" means when there's no
-- live quote -- see the cross-reference comment on UI/SellFrame.lua's onPostClick for why the
-- row tooltip specifically feeds this flip.targetUnit rather than a second, independently-fresh
-- GC.Data.GetItemValue read: it must never show a different number than what Post would
-- actually post at). nil candidate (both marketUnit and mv unknown) means nothing to recommend.
--
-- breakeven: the unit price at which the AH's 5% cut exactly cancels out what was paid --
-- ceil (not floor) so a rounded-down breakeven couldn't itself understate a loss. nil whenever
-- paidUnit is unknown (an orphan row -- no recorded purchase, so no cost basis to break even
-- against; RecommendPost is deliberately not called for those rows at all, per the file header
-- above and UI/SellFrame.lua's OnEnter).
--
-- belowCost: true when the recommended candidate would sell at a loss even before the 5% cut is
-- accounted for a second time -- i.e. candidate itself sits below the price where costs are
-- merely recovered. Surfaced as a loud, separate warning line rather than folded into the main
-- recommendation text.
--
-- F3 ("match, don't undercut"): `opts = { levels, sold }` (both optional; omitting either falls
-- straight back to the undercut behavior above). Racing to the bottom 1c at a time is wasted
-- effort when the CHEAPEST price tier sells out fast enough that being anywhere IN that tier is
-- enough -- buyers consume the whole tier, not just the single lowest listing, so undercutting
-- it by 1c buys nothing but a smaller margin. When marketUnit, opts.levels (with a first entry --
-- levels is assumed pre-sorted ascending, same convention DepthBelow's callers already follow)
-- and a positive opts.sold are ALL present: tierDepth sums quantity across every level priced
-- exactly at the book's own cheapest unit price. `opts.sold >= 2 * tierDepth` -- "the whole
-- cheapest tier turns over in half a day or less at current velocity" -- is a deliberately
-- coarse rule of thumb, not a probability model: sold/day is a single realm-wide daily figure
-- (GC.Data.GetItemValue), not a real-time fill-rate feed, so there is no honest way to derive a
-- sharper threshold from it. When it holds, mode="match" and the candidate becomes marketUnit
-- itself (no -1c undercut); otherwise (or when the match-mode inputs aren't all available)
-- mode="undercut", exactly the pre-F3 `max(1, marketUnit - 1)` expression. The no-quote (mv)
-- fallback branch always leaves mode nil -- there is no ask to match OR undercut, so neither
-- label applies.
function GC.Flips.RecommendPost(paidUnit, marketUnit, mv, opts)
  opts = opts or {}
  local mode, candidate

  if marketUnit and opts.levels and opts.levels[1] and opts.sold and opts.sold > 0 then
    local cheapest = opts.levels[1].unitPrice
    local tierDepth = 0
    for _, lvl in ipairs(opts.levels) do
      if lvl.unitPrice == cheapest then tierDepth = tierDepth + (lvl.quantity or 0) end
    end
    if opts.sold >= 2 * tierDepth then
      mode, candidate = "match", marketUnit
    end
  end

  if not mode then
    if marketUnit then
      mode, candidate = "undercut", math.max(1, marketUnit - 1)
    else
      candidate = mv or nil
    end
  end

  if candidate == nil then return nil end

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
    { levels = args.levels, sold = args.sold })
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
