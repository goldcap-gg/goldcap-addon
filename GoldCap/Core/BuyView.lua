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

-- Whether a row stays on screen under the filter and the search box. The search is a plain
-- substring of the name the row shows (the client's own, translated name), case- and accent-blind
-- in the client's language as Core/NameMatch.lua folds it: "льнян" keeps "Плотные льняные бинты".
function GC.BuyView.Matches(status, name, filter, query)
  if filter and filter ~= "all" then
    local keep = KEEP[filter]
    if not (keep and keep[status]) then return false end
  end
  if type(query) == "string" and query ~= "" then
    local fold = GC.NameMatch.Fold
    return type(name) == "string" and fold(name):find(fold(query), 1, true) ~= nil
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

-- What the BUY tab's item box was given (BUY 2.0's quick list): an item link -- a shift-click into
-- the box -- or a bare item id, both of which name the item exactly, or a name. nil for nothing at
-- all; false for input that cannot be read without guessing.
--
-- A count goes beside a link as a number ("5 [Linen Cloth]", "[Linen Cloth] x5"), beside an item id
-- only with an x stuck to it ("2589 x20", "20x 2589", "x20 2589") -- two bare numbers, or an x
-- standing apart between them, say nothing about which is the item and are refused -- and beside a
-- name either way ("20 Linen Cloth", "Linen Cloth x20", "Linen Cloth 20"). Whether a name can be
-- looked up is the caller's question: the BUY 2.0 probe found the client resolves almost no typed
-- names (0 of 15 in retail).
function GC.BuyView.ParseAdd(text)
  if type(text) ~= "string" then return nil end
  -- "×" is two bytes in UTF-8; a pattern class would treat them as two characters and leave half
  -- of it behind. Turned into a plain "x" first, it is matched as one.
  text = text:gsub("×", "x"):match("^%s*(.-)%s*$")
  if text == "" then return nil end
  local linkID = text:match("|Hitem:(%d+)")
  if linkID then
    -- The hyperlink goes whole (its name can hold digits), and so does every colour escape: both
    -- games colour an item link by its quality as |cnIQ<quality>: (the owner's SavedVariables,
    -- 2026-10-01), older text as |cffRRGGBB -- a quality digit left behind would read as a count.
    local left = text:gsub("|H.-|h.-|h", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", "")
      :gsub("|r", "")
    local count = tonumber(left:match("(%d+)"))
    return { itemID = tonumber(linkID), qty = (count and count > 0) and count or 1 }
  end
  local function item(id, count)
    count = tonumber(count)
    return { itemID = tonumber(id), qty = (count and count > 0) and count or 1 }
  end
  if text:match("^%d+$") then return item(text) end
  local id, count = text:match("^(%d+)%s+x(%d+)$")
  if not id then id, count = text:match("^(%d+)%s+(%d+)x$") end
  if not id then count, id = text:match("^(%d+)x%s+(%d+)$") end
  if not id then count, id = text:match("^x(%d+)%s+(%d+)$") end
  if id then return item(id, count) end
  if text:match("^[%dx%s]+$") then return false end
  local qty, rest = 1, text
  local lead, afterLead = rest:match("^(%d+)%s+(.+)$")
  if lead then qty, rest = tonumber(lead), afterLead end
  -- A count after a name needs a space before it, so a name that merely contains an x is not cut.
  local before, tail = rest:match("^(.-)%s+x%s*(%d+)$")
  if not before then before, tail = rest:match("^(.-)%s+(%d+)$") end
  if tail then qty, rest = tonumber(tail), before end
  return { name = rest, qty = (qty and qty > 0) and qty or 1 }
end
