local _, GC = ...

-- The seller's posting queue: an ORDER over positions that could be posted right now, plus a
-- named reason for every one that could not. See docs/superpowers/specs/2026-08-17-post-queue-
-- design.md Part 1 for the approved design this file implements.
--
-- Why this exists: `C_AuctionHouse.PostCommodity`/`PostItem` are `#hwevent` -- they can only run
-- from the player's own hardware click, never a timer or an event handler -- so there can never
-- be a "post everything" button. What IS buildable is a queue that turns twenty rows of hunting
-- into one control that never moves: the head of the queue is always what the next click posts.
--
-- ***THIS MODULE IS NOT AN AUTHORITY ON PRICE OR QUANTITY.*** `unitPrice` is copied verbatim
-- from the position's own `postRecommendation.unit` -- SellPositions.decoratePosition's answer
-- to "what would I list the stock in my bags at," the exact number the Sell tab's row is
-- already showing on screen for that stock -- and `bagQty` is carried through for display only.
-- Deliberately NOT `position.recommendation`: that field sometimes answers a different question
-- (RepostAdvice's "should I cancel and relist the lot that's already up," once coverage is
-- COMPLETE and something is already listed) and has no top-level `.unit` when it does -- see
-- `postRecommendation`'s own comment in SellPositions.lua for the defect that shipped from
-- conflating the two. At click time,
-- `GC.SellPositions.BuildPostPlan` re-derives BOTH the quantity and the price from live bag
-- state and a fresh quote, exactly as it does for a row's own Post button (see that function:
-- it never reads `position.recommendation` at all, only `freshQuote`/`position.postFloor` and
-- the caller-supplied `bagState`). If this module ever computed a price or quantity of its own,
-- the queue and the row it is standing in for could disagree about what a click is about to do
-- -- that is the exact class of defect this codebase has shipped and been bitten by before (see
-- the price-ladder and market-value postmortems). So: never derive a number here that
-- `BuildPostPlan` is responsible for. Copy, don't compute.
--
-- What is deliberately NOT decided here: whether an exact bag stack can be identified for a
-- given position is LIVE state (`liveBagState` in UI/SellFrame.lua, a file this module never
-- touches and never will), not something knowable from a position table alone. A position can
-- look perfectly postable here and still fail at click time (ambiguous variant, bag contents
-- changed since the position was built, etc.) -- that failure belongs to `BuildPostPlan` and the
-- click handler, and must be surfaced THERE, not guessed at or pre-empted here. Do not "fix"
-- this by inventing a skip reason for it.
GC.PostQueue = {}

local MAX_EXACT = 9007199254740991

local function exact(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

local function positive(value) return exact(value) and value > 0 end

-- left * right, without ever constructing a product that has already lost precision or wrapped.
-- Same guard UI/SellFrame.lua's own safeMultiply uses for the same reason: `value` below is
-- exactly what the design calls "money", and a position whose value cannot be stated exactly
-- must be dropped, never silently clamped to something smaller than it really is.
local function mulExact(left, right)
  if not exact(left) or not exact(right) then return nil end
  if left ~= 0 and right > math.floor(MAX_EXACT / left) then return nil end
  return left * right
end

-- Precedence when more than one reason could apply, checked in this order (first match wins):
--
--   1. unresolved_identity -- the position itself cannot be trusted: SellPositions marked it
--      `unresolved` or `protectedAction == false` (an identity/repair row -- see
--      SellPositions.Build's unresolvedRows), or `invalid` (its own accounting overflowed), or
--      this module's OWN value computation (unitPrice * bagQty) overflowed. All four are the
--      same family of problem -- "the numbers for this position cannot be soundly stated" -- and
--      BuildPostPlan already lumps the first three under one refusal for the same reason. A
--      position in this bucket gets no further consideration: none of its other fields are
--      trustworthy enough to justify a more specific reason.
--   2. no_fresh_price -- there is no trustworthy price to show. This covers two cases that look
--      identical to a seller: `freshMarketUnit` itself is missing (a stale or absent quote --
--      the exact freshness contract `BuildPostPlan`'s own `freshUnit` enforces before it will
--      derive a plan), OR `freshMarketUnit` is present but `postRecommendation` has no positive
--      `.unit` -- RecommendPost itself had nothing to recommend (see its own nil contract).
--      `postRecommendation` is always RecommendPost-shaped (`{unit, mode, breakeven, belowCost}`)
--      or nil, never RepostAdvice-shaped -- see SellPositions.decoratePosition's own comment on
--      why it computes this separately from `recommendation` (which sometimes IS RepostAdvice-
--      shaped, once coverage is COMPLETE and something is already listed). Cancelling and
--      reposting an existing lot is its own future batch (design doc Part 3), never this one, but
--      that boundary is about which ACTION this module offers, not about which positions can
--      appear in it -- bag stock belonging to a partly-listed position is squarely Part 1, and
--      reading `postRecommendation` instead of `recommendation` is what keeps that boundary
--      honest without this module having to know RepostAdvice's shape at all.
--   3. below_breakeven -- postRecommendation.unit is a real, positive price, but
--      postRecommendation.belowCost is true: posting at the recommended price would lock in a
--      loss. A queue whose whole purpose is "money first" must not silently rank, let alone
--      recommend clicking through, a loss.
--
-- Returns reason, unit, value -- unit/value are only meaningful when reason is nil.
local function evaluate(position)
  if position.unresolved or position.protectedAction == false or position.invalid then
    return "unresolved_identity"
  end
  if type(position.positionKey) ~= "string" or position.positionKey == "" or not positive(position.itemID) then
    return "unresolved_identity"
  end
  if not positive(position.freshMarketUnit) then
    return "no_fresh_price"
  end
  local recommendation = position.postRecommendation
  local unit = type(recommendation) == "table" and recommendation.unit or nil
  if not positive(unit) then
    return "no_fresh_price"
  end
  if recommendation.belowCost == true then
    return "below_breakeven"
  end
  local value = mulExact(unit, position.bagQty)
  if not value then
    return "unresolved_identity"
  end
  return nil, unit, value
end

-- Money first, descending; ties broken by positionKey ascending so a rebuild with the same
-- inputs -- and, just as importantly, the same inputs handed over in a DIFFERENT array order --
-- always produces the same queue. A queue that reshuffles between two renders is
-- indistinguishable from a broken one to the seller standing in front of it.
local function entryLess(left, right)
  if left.value ~= right.value then return left.value > right.value end
  return left.positionKey < right.positionKey
end

-- Same tie-break for the explanation list: nothing about WHY a position is missing should
-- reshuffle between renders either.
local function skipLess(left, right)
  return (left.positionKey or "") < (right.positionKey or "")
end

--- GC.PostQueue.Build(positions) -> entries, skipped
--
-- `positions` is GC.SellPositions.Build's own return array -- every field this function reads
-- (`bagQty`, `postRecommendation`, `freshMarketUnit`, `unresolved`, `invalid`, ...) is set by
-- that module's `decoratePosition`, not by anything here.
--
-- `bagQty <= 0` (including positions where it is missing entirely, e.g. an unresolved/repair
-- row, which never carries a numeric `bagQty` at all) is silently absent from BOTH `entries` and
-- `skipped`: there is nothing in the player's bags to post and so nothing to explain. Every
-- other position that fails to qualify gets a `skipped` entry -- a silently short queue is the
-- same lie as a silently short deals list.
function GC.PostQueue.Build(positions)
  local entries, skipped = {}, {}
  for _, position in ipairs(positions or {}) do
    if type(position) == "table" and positive(position.bagQty) then
      local reason, unit, value = evaluate(position)
      if reason then
        skipped[#skipped + 1] = { positionKey = position.positionKey, itemID = position.itemID,
          itemName = position.itemName, reason = reason }
      else
        entries[#entries + 1] = { positionKey = position.positionKey, scopeKey = position.scopeKey,
          itemID = position.itemID, itemName = position.itemName, bagQty = position.bagQty,
          unitPrice = unit, value = value }
      end
    end
  end
  table.sort(entries, entryLess)
  table.sort(skipped, skipLess)
  return entries, skipped
end

--- GC.PostQueue.Without(entries, positionKey) -> a NEW array holding every entry except the one
-- whose positionKey matches. Never mutates `entries` -- the UI renders straight from the array
-- it holds (`renderRows`/`renderEntryID` in UI/SellFrame.lua), and mutating that array out from
-- under an in-flight render is exactly how a row gets bound to the wrong pin mid-click.
function GC.PostQueue.Without(entries, positionKey)
  local result = {}
  for _, entry in ipairs(entries or {}) do
    if entry.positionKey ~= positionKey then
      result[#result + 1] = entry
    end
  end
  return result
end
