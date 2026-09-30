local _, GC = ...

-- BUY 2.0's view rules as data: what a line's row says, the price ladder its tooltip shows, the
-- price the dock offers to raise a cap to, which lines a filter keeps. Pure and text-free like
-- Core/BuyRun.lua -- UI/BuyFrame.lua owns every string the player reads.
GC.BuyView = {}

GC.BuyView.LADDER_ROWS = 4

-- The ladder a line's tooltip draws: every level the purchase takes units from, then the first
-- level it does not take from (the next price up, or the level the cap stops at), at most
-- `maxRows` rows. `take` is how many units the line buys at that level; `over` whether the
-- level's unit price is above the cap. The walk is Core/BuyRun.lua's PurchaseQuantity: cheapest
-- level first, and the first level over the cap ends it.
function GC.BuyView.Ladder(levels, buy, cap, maxRows)
  maxRows = maxRows or GC.BuyView.LADDER_ROWS
  local rows, left = {}, math.max(0, buy or 0)
  for _, level in ipairs(levels or {}) do
    if #rows >= maxRows then break end
    local over = cap ~= nil and level.unit > cap
    local take = 0
    if not over and left > 0 then
      take = math.min(level.qty, left)
      left = left - take
    end
    rows[#rows + 1] = { qty = level.qty, unit = level.unit, take = take, over = over }
    if take == 0 then break end
  end
  return rows
end

-- The price the dock offers to raise a line's cap to when not one unit fits under it: the
-- market price when that is above the cheapest ask (a cap set below the market), otherwise the
-- cheapest ask itself -- the least that buys anything at all. nil whenever raising would change
-- nothing: no cap, no book, or the cheapest level already fits.
function GC.BuyView.RaiseTo(levels, cap, market)
  local first = levels and levels[1]
  if not first or cap == nil or first.unit <= cap then return nil end
  local target = first.unit
  if type(market) == "number" and market > target then target = market end
  return target
end
