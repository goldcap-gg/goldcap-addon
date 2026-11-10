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
-- given position is LIVE state (`GC.SellBags.LiveState`, in Services/Sell/Bags.lua, a file this
-- module never touches and never will), not something knowable from a position table alone. A
-- position can
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
-- Same guard GC.SellUtil.safeMultiply (Services/Sell/State.lua) uses for the same reason: `value` below is
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
--   4. below_vendor -- WoW: Forever only (opts.vendorUnit is set, which only the Sell tab's own
--      GC.Sell._QueueOpts does): postRecommendation.unit is real and positive, but after the 5%
--      cut a vendor pays at least as much for it. "Post everything worth more than a vendor
--      pays" is this queue's whole design there, so such a position is held back and says why.
--      Retail passes no opts at all, so this branch never runs there.
--   enough_listed -- WoW: Forever only (opts.durationFor, opts.unitFor): the sale pace is already
--      covered by the units up at or under the price (GC.SellPositions.PostQuantity), so this post
--      would list none. Decided where the quantity is, before the deposit below weighs it.
--   5. below_deposit -- WoW: Forever only too (opts.depositFor, 2026-11-06): what one click
--      lists, after the 5% cut and less what a vendor pays for the same units, is no more than
--      the deposit the post puts up. The deposit comes back only if the lot sells, so posting
--      is a bet that wins less than it stakes, the tooltip's "deposit outweighs the gain" verdict
--      (Core/ForeverValue.lua's Verdict) for a whole post. A deposit the client cannot quote
--      holds nothing, as a missing vendor price holds nothing above.
--      keeps_returning and low_profit -- WoW: Forever only too (opts.returnHold, opts.minimumProfit):
--      the item came back unsold that many rounds in a row, or the post would earn under the
--      minimum after the cut, the vendor and the deposit.
--
-- How many posts of an item come back unsold for each one that sells, doubled to stay whole, by
-- the units a day the house sells of it (position.pacePerDay, WoW: Forever's sale tape). Each of
-- those loses its deposit, so `below_deposit` holds the gain to that many deposits, where it held
-- it to one. Measured over every lot the 24 houses posted at their item's cheapest ask or under
-- (wow-auction's scripts/analytics/forever-sell-bands.sql, to 2026-11-08, 2 million lots): 7.8
-- unsold for each sale under 1 a day, 4.0 at 1-3, 3.1 at 3-10, 2.1 at 10-30, 1.6 and 1.3 at
-- 30-300, and under one from there. No pace known, or a busy item: one deposit, as before.
local UNSOLD_PER_SALE_X2 = { { 1, 16 }, { 3, 8 }, { 10, 6 }, { 30, 4 }, { 300, 3 } }

local function unsoldPerSaleX2(perDay)
  if type(perDay) ~= "number" or perDay ~= perDay or perDay < 0 then return 2 end
  for _, step in ipairs(UNSOLD_PER_SALE_X2) do
    if perDay < step[1] then return step[2] end
  end
  return 2
end

-- Returns reason, unit, value -- unit/value are only meaningful when reason is nil.
local function evaluate(position, opts)
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
  -- A followed group's floor over the live market ("a floor above the market holds POST" in
  -- spec/sell_group_rules_spec.lua): posting at the floor would sit above every ask, and posting
  -- under it breaks the group's rule. Held back; a price the player typed still goes.
  local ruleFloor = type(position.rule) == "table" and position.rule.floorUnit or nil
  if positive(ruleFloor) and position.freshMarketUnit < ruleFloor and recommendation.mode ~= "chosen" then
    return "below_rule_floor"
  end
  if recommendation.belowCost == true then
    return "below_breakeven"
  end
  -- WoW: Forever only (the Sell tab passes opts there, GC.Sell._QueueOpts): the queue is "post
  -- everything worth more than the vendor", so a position whose price, after the 5% cut, a
  -- vendor matches is held back and says so. No opts, no change: retail's queue is built as
  -- before.
  local vendorUnit = opts and opts.vendorUnit and opts.vendorUnit(position.itemID) or nil
  if type(vendorUnit) == "number" and vendorUnit > 0 and math.floor(unit * 0.95) <= vendorUnit then
    return "below_vendor"
  end
  -- WoW: Forever only (opts.returnHold, GC.ForeverPace.RETURN_HOLD): the item came back unsold
  -- that many rounds in a row, so another post is held. A followed group's rule decides its own.
  if positive(opts and opts.returnHold) and not position.rule
      and (position.returnRounds or 0) >= opts.returnHold then
    return "keeps_returning"
  end
  -- Ranked on what one click actually LISTS, not on what is in the bags. A normal item posts a
  -- single stack (PostItem pins one ItemLocation -- see GC.BagStock.PostableQuantity and
  -- `postableQty` in SellPositions), so five stacks of twenty used to sort this queue as if a
  -- hundred units were about to change hands when twenty were. Commodities are unaffected: the
  -- whole bag pool is one postable quantity. Falls back to bagQty when nothing set the field,
  -- which is exactly the old behaviour.
  local postable = positive(position.postableQty) and position.postableQty or position.bagQty
  -- ...and on fewer by the one quantity rule the post plan and the panel read
  -- (GC.SellPositions.PostQuantity): the seller's own number (the Sell tab's "how many"), a
  -- followed group's "1 at a time" ("POST takes one at a time"), or on WoW: Forever the sale pace
  -- at the duration and the price the post goes up at (opts.durationFor and opts.unitFor, passed
  -- there alone; the price live, a number the player typed since the last compose included, so
  -- the queue counts the same own lots as already up as the click does). Nothing to list because
  -- enough is already up holds the item as enough_listed.
  local quantityUnit = opts and opts.unitFor and opts.unitFor(position) or unit
  postable = GC.SellPositions.PostQuantity(position, opts and opts.quantities and opts.quantities[position.positionKey],
    postable, quantityUnit, opts and opts.durationFor and opts.durationFor(position))
  if postable <= 0 then return "enough_listed" end
  local value = mulExact(unit, postable)
  if not value then
    return "unresolved_identity"
  end
  -- below_deposit (the list above). value - ceil(value / 20) is floor(value * 0.95) without the
  -- product. Seven Stringy Wolf Meat posted at 35c put up a 99c deposit, 40% of the sale
  -- (owner's save, 2026-11-06): on cheap stock the deposit is no rounding error.
  local deposit = opts and opts.depositFor and opts.depositFor(position, postable) or nil
  if exact(deposit) then
    local vendorTotal = positive(vendorUnit) and mulExact(vendorUnit, postable) or 0
    -- Twice the gain against twice the deposits lost before the lot sells (unsoldPerSaleX2).
    if vendorTotal and (value - math.ceil(value / 20) - vendorTotal) * 2
        <= deposit * unsoldPerSaleX2(position.pacePerDay) then
      return "below_deposit"
    end
    -- WoW: Forever only (opts.minimumProfit): what is left after the cut, the vendor and the
    -- deposit is under the least the player thinks a post worth.
    if positive(opts.minimumProfit) and vendorTotal
        and value - math.ceil(value / 20) - vendorTotal - deposit < opts.minimumProfit then
      return "low_profit"
    end
  end
  return nil, unit, value, postable
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

--- GC.PostQueue.Selling(position, marks, grouped) -> boolean
--
-- The selling list (owner, 2026-10-09): is this position one the player sells through POST and
-- the post-next key? `marks` is the player's own choice per positionKey, true or false, kept
-- across sessions (GC.db.sellMarks); a choice, either way, wins. With none, what the Deals board
-- bought and is still held (an active batch of source "goldcap", SellPositions' `sources`) is
-- selling: it was bought to be sold again. Nothing else is: the BUY tab's runs are shopping lists
-- (what a craft still needs), and a merchant sells reagents as readily as anything. Per position,
-- not per item: every caged pet is item 82800.
-- `grouped`: the player picked a group to post (the Sell tab's GROUPS row, owner 2026-10-25), and
-- every item of it with no choice of its own is selling: picking the group was the choice.
function GC.PostQueue.Selling(position, marks, grouped)
  local key, choice = position.positionKey, nil
  -- Not `a and b and marks[key] or nil`: a choice of false would read as no choice at all.
  if type(marks) == "table" and type(key) == "string" then choice = marks[key] end
  if choice ~= nil then return choice == true end
  if grouped then return true end
  local sources = position.sources
  if type(sources) == "table" and type(sources.goldcap) == "number" and sources.goldcap > 0 then return true end
  -- A followed group's flip or gather item is stock to sell too ("flip and gather sell by
  -- default"); a craft or stock group's members may be reagents the player keeps.
  local rule = position.rule
  return type(rule) == "table" and (rule.play == "flip" or rule.play == "gather")
end

--- GC.PostQueue.Build(positions, opts) -> entries, skipped, notSelling
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
--
-- `opts` comes from the Sell tab (`GC.Sell._QueueOpts()`); without it the queue is built from
-- every position, as before the selling list. `opts.marks`, when present, is the player's
-- selling list (see Selling above): a position it leaves out is in neither list -- it is not held
-- back, the player chose -- but in `notSelling`, shaped like a `skipped` entry, its `reason` the
-- one it would have been held back for (nil when it could be posted). Its row still has its own
-- Post, so its row still says what is wrong with it; the dock reads the count.
-- `opts.vendorUnit` is WoW: Forever's (`function(itemID) ...`), read by `evaluate`'s
-- `below_vendor` case above, and so is `opts.depositFor` (`function(position, quantity)`, the
-- deposit for posting that many, or nil), read by `below_deposit`, and `opts.durationFor` and
-- `opts.unitFor` (`function(position)`, the duration index and the unit price the post goes up
-- at), read by the quantity rule.
-- `opts.group`, when set, is the group the Sell tab's GROUPS row picked, and `opts.inGroup(key)`
-- answers whether a position is in it: one that is not is in none of the three lists, as its row
-- is not on screen, and one that is sells unless the player unmarked it (Selling's `grouped`).
function GC.PostQueue.Build(positions, opts)
  local entries, skipped, notSelling = {}, {}, {}
  local marks = opts and opts.marks
  local grouped = opts ~= nil and opts.group ~= nil and type(opts.inGroup) == "function"
  for _, position in ipairs(positions or {}) do
    if type(position) == "table" and positive(position.bagQty)
        and not (grouped and not opts.inGroup(position.positionKey)) then
      local reason, unit, value, postable = evaluate(position, opts)
      if type(marks) == "table" and not GC.PostQueue.Selling(position, marks, grouped) then
        notSelling[#notSelling + 1] = { positionKey = position.positionKey, itemID = position.itemID,
          itemName = position.itemName, reason = reason }
      elseif reason then
        skipped[#skipped + 1] = { positionKey = position.positionKey, itemID = position.itemID,
          itemName = position.itemName, reason = reason }
      else
        -- Both figures travel: `bagQty` is what the player is holding, `postableQty` is what the
        -- next click lists. Conflating them is the defect this carries a second field for.
        entries[#entries + 1] = { positionKey = position.positionKey, scopeKey = position.scopeKey,
          itemID = position.itemID, itemName = position.itemName, bagQty = position.bagQty,
          postableQty = postable, unitPrice = unit, value = value }
      end
    end
  end
  table.sort(entries, entryLess)
  table.sort(skipped, skipLess)
  table.sort(notSelling, skipLess)
  return entries, skipped, notSelling
end

--- GC.PostQueue.Without(entries, positionKey) -> a NEW array holding every entry except the one
-- whose positionKey matches. Never mutates `entries` -- the UI renders straight from the array
-- it holds (`renderRows`/`renderEntryID` in UI/Sell/List.lua), and mutating that array out from
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
