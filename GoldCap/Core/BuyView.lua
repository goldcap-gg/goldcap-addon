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

-- One word for a row, in the order the rules outrank each other. `s` carries what only the tab
-- knows: `skipped` (this session), `stranded` (a confirm still owed its answer), `byHand` (the
-- client will not sell the item as a commodity), `quote` ("fits" / "over": what the line's last
-- read of the live book said). Without a read, NOW (the cheapest unit seen) over the cap is the
-- evidence; a read, being fresher, overrules it either way.
function GC.BuyView.Status(line, s)
  s = s or {}
  if line.done then return "done" end
  if s.skipped then return "skipped" end
  if line.kind == "craft" then return "craft" end
  if line.vendor then return "vendor" end
  if s.stranded then return "stranded" end
  -- A lot line (BUY 2.0 week 2) is bought here one lot at a time; its read can find nothing under
  -- the cap, exactly as a commodity's can.
  if s.byHand then return s.quote == "over" and "over" or "lots" end
  if s.quote == "over" then return "over" end
  if s.quote == "fits" then return "ready" end
  if line.cap and line.floor and line.floor > line.cap then return "over" end
  if line.floor or line.usual then return "ready" end
  return "unpriced"
end

GC.BuyView.FILTERS = { "all", "buy", "over", "vendor", "craft", "done", "skipped" }

local KEEP = {
  buy = { ready = true, unpriced = true, lots = true, stranded = true },
  over = { over = true }, vendor = { vendor = true }, craft = { craft = true },
  done = { done = true }, skipped = { skipped = true },
}

-- Whether a row stays on screen under the filter and the search box. The search is a plain,
-- case-blind substring of the name the row shows (the client's own, translated name).
function GC.BuyView.Matches(status, name, filter, query)
  if filter and filter ~= "all" then
    local keep = KEEP[filter]
    if not (keep and keep[status]) then return false end
  end
  if type(query) == "string" and query ~= "" then
    return type(name) == "string" and name:lower():find(query:lower(), 1, true) ~= nil
  end
  return true
end

-- "N of M done" over the run's own lines: a reagent a split put under a line is part of it.
function GC.BuyView.Progress(lines)
  local done, total = 0, 0
  for _, line in ipairs(lines or {}) do
    if not line.parent then
      total = total + 1
      if line.done then done = done + 1 end
    end
  end
  return done, total
end

-- What the rest of a line costs: a quote's own total when it covers the whole remaining quantity,
-- else the remaining units at the best price known -- an estimate, and said to be one. nil when
-- nothing is known or nothing is left to buy.
function GC.BuyView.CostOf(line, quote)
  if (line.buy or 0) <= 0 then return nil, nil end
  if quote and quote.total and quote.total > 0 and quote.qty == line.buy then
    return quote.total, false
  end
  local unit = line.floor or line.usual
  if not unit then return nil, nil end
  return line.buy * unit, true
end

-- Whose price a line's market figure is: a price other players' scans agreed on (Core/Data.lua's
-- crowd reference) says how many scanners and how old it is. Nothing else says anything.
function GC.BuyView.MarketNote(ref, now)
  if type(ref) ~= "table" or ref.source ~= "crowd" or type(ref.at) ~= "number" then return nil end
  return { scanners = ref.scanners or 0, age = math.max(0, (now or 0) - ref.at) }
end
