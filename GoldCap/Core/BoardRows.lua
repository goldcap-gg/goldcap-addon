local _, GC = ...

-- Sniper fast loop, phase 1 (design doc §5 Board): the pure verdict-label and sort-order
-- rules the board renders by, split out of UI/SniperFrame.lua so they are testable without a
-- frame -- that file is at its 200-local ceiling (see the addon's engineering notes). Tier pills
-- (HOT/GOOD/WATCH/SUSPECT) are gone from what the player reads; Core/DealMath.lua's tiers
-- keep existing internally (the discovery-time pre-screen still uses them), never rendered
-- on a row again once a verdict exists.
GC.BoardRows = {}

local BUCKET_RANK = { CAP = 0, SAFE = 1, WATCH = 2, PENDING = 3, UNVERIFIED = 4 }

-- SAFE only once the live Check actually approved it; anything else WITH a verdict is a
-- refusal. Without a verdict there are two different states, and conflating them was a lie:
-- PENDING means this exact row is queued for a live look (the drill queue) or sits inside the
-- verify walk's own window, and UNVERIFIED means nothing is looking at it right now. The board
-- used to promise "checking…" on every unverified row, including the ones far below the window
-- that no pass would reach for minutes.
--
-- Live price caps, addon task 6: CAP outranks every other bucket, including SAFE -- a listing
-- at or under the PLAYER'S OWN price is not merely a good market deal, it is exactly what they
-- asked to be told about, so it leads the board regardless of how a commodity cap deal's own
-- `buyable` field reads (GC.Caps.DecideCommodity sets both `cap` and `buyable`; checking `cap`
-- first keeps it out of the plain SAFE bucket it would otherwise also qualify for).
function GC.BoardRows.Bucket(verdict, pending)
  if verdict and verdict.cap then return "CAP" end
  if verdict and verdict.buyable then return "SAFE" end
  if verdict then return "WATCH" end
  if pending then return "PENDING" end
  return "UNVERIFIED"
end

-- The bucket as a plain ascending number, so a header-click sort can order by it directly
-- instead of keeping a second copy of this ordering.
function GC.BoardRows.Rank(verdict, pending)
  return BUCKET_RANK[GC.BoardRows.Bucket(verdict, pending)]
end

-- What the row's verdict cell says. SHORT, deliberately: it is one column on a row, and the
-- refusal sentence that used to be painted into it (WATCH <reason>) ran straight across the
-- discount and price columns beside it. The sentence has two places with room for it -- the
-- row tooltip and the check dialog -- and Reason below is where both get it.
--
-- Takes no deal: the label is entirely a function of the verdict now. The falling marker it
-- used to append is the trend column's own job (it prints the actual figure, in red), and a
-- second copy of that fact in a cell this narrow cost more than it said.
function GC.BoardRows.Label(verdict, pending)
  local bucket = GC.BoardRows.Bucket(verdict, pending)
  if bucket == "CAP" then
    return GC.L["YOUR PRICE"]
  elseif bucket == "SAFE" then
    -- GC.Util.FormatGoldFloor, not FormatMoney: this cell is a fixed width and FormatMoney's
    -- gold+silver form ("61g35s") is two units, wide enough to clip. Gold only, floored.
    return (GC.L["SAFE +%s"]):format(GC.Util.FormatGoldFloor(verdict.stressProfit or 0))
  elseif bucket == "WATCH" then
    -- AVOID gets its own word when the live verdict actually said AVOID -- everything else
    -- non-buyable (WATCH itself, Gone, any other refusal status) keeps the WATCH label. Bucket
    -- and sort are unchanged: both statuses are still the one non-buyable bucket, this only
    -- changes which word the cell prints.
    if verdict and verdict.status == "AVOID" then
      return GC.L["AVOID"]
    end
    return GC.L["WATCH"]
  elseif bucket == "PENDING" then
    return "…"
  end
  return "—"
end

-- The refusal in words, for the surfaces that can hold a sentence. nil whenever there is
-- nothing to explain: no verdict yet, or a verdict that said yes.
function GC.BoardRows.Reason(verdict)
  if not verdict or verdict.buyable then return nil end
  return verdict.reason
end

-- Board sort order: SAFE before WATCH before pending before everything else, estProfit
-- descending within each bucket. Pins are partitioned ahead of this by the caller
-- (renderList), unchanged.
function GC.BoardRows.Compare(dealA, verdictA, pendingA, dealB, verdictB, pendingB)
  local ra = GC.BoardRows.Rank(verdictA, pendingA)
  local rb = GC.BoardRows.Rank(verdictB, pendingB)
  if ra ~= rb then return ra < rb end
  local pa = dealA.estProfit or dealA.profit or 0
  local pb = dealB.estProfit or dealB.profit or 0
  return pa > pb
end
