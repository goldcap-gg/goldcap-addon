local _, GC = ...

-- Sniper fast loop, phase 1 (design doc §5 Board): the pure verdict-label and sort-order
-- rules the board renders by, split out of UI/SniperFrame.lua so they are testable without a
-- frame -- that file is at its 200-local ceiling (see addon/AGENTS.md). Tier pills
-- (HOT/GOOD/WATCH/SUSPECT) are gone from what the player reads; Core/DealMath.lua's tiers
-- keep existing internally (the discovery-time pre-screen still uses them), never rendered
-- on a row again once a verdict exists.
GC.BoardRows = {}

local BUCKET_RANK = { SAFE = 1, WATCH = 2, UNVERIFIED = 3 }

-- SAFE only once the live Check actually approved it; anything else WITH a verdict reads its
-- refusal reason; no verdict at all reads as still being chased by the background pipeline --
-- either the drill queue or the verify walk covers every row on screen, so "checking…" is
-- never a promise the pipeline will not keep (design doc §3).
function GC.BoardRows.Bucket(verdict)
  if verdict and verdict.buyable then return "SAFE" end
  if verdict then return "WATCH" end
  return "UNVERIFIED"
end

function GC.BoardRows.Label(deal, verdict)
  local bucket = GC.BoardRows.Bucket(verdict)
  local label
  if bucket == "SAFE" then
    label = (GC.L["SAFE +%s"]):format(GC.Util.FormatMoney(verdict.stressProfit or 0))
  elseif bucket == "WATCH" then
    label = (GC.L["WATCH %s"]):format(verdict.reason or "")
  else
    label = GC.L["WATCH — checking…"]
  end
  if deal and deal.falling then
    label = label .. GC.L[" |cffff4040v|r"]
  end
  return label
end

-- Board sort order: SAFE before WATCH before UNVERIFIED, estProfit descending within each
-- bucket. Pins are partitioned ahead of this by the caller (renderList), unchanged.
function GC.BoardRows.Compare(dealA, verdictA, dealB, verdictB)
  local ra = BUCKET_RANK[GC.BoardRows.Bucket(verdictA)]
  local rb = BUCKET_RANK[GC.BoardRows.Bucket(verdictB)]
  if ra ~= rb then return ra < rb end
  local pa = dealA.estProfit or dealA.profit or 0
  local pb = dealB.estProfit or dealB.profit or 0
  return pa > pb
end
