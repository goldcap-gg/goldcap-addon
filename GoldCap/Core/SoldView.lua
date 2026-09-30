local _, GC = ...

-- The Sold tab's arithmetic, apart from the frames that show it (UI/SoldFrame.lua). Pure Lua:
-- nothing here calls the client, so the spec (spec/sold_view_spec.lua) drives it with plain
-- tables. The clock arrives as arguments -- `now`, and a `dateOf(at)` that answers what
-- `date("*t", at)` would -- because the calendar is the client's and this file is not.
--
-- What a row is. A sale is normalised into one shape whichever list it came from:
--   { section = "local" | "server", key, name, itemID, itemExact, qty, gross, cut, cutEstimated,
--     net, each, pending, at, profit, paid, paidEach, costUnits, sources, costUnknown, noBasis }
-- `gross` is what the buyer paid (the ledger's and the server's `total`), `cut` the auction
-- house's share of it, `net` what reached the mailbox. `profit` is a number only where GoldCap
-- knows the cost -- a local sale on an EXACT evidence-key join to its realized row, a server
-- sale whose basis matched units -- and nil everywhere else. Nothing here guesses one.
GC.SoldView = {}
local V = GC.SoldView

-- The auction house keeps 5% of a sale. Used only where a sale did not record its own cut.
V.CUT_RATE = 0.05

V.PERIODS = { "today", "7d", "30d" }
V.PERIOD_DAYS = { today = 1, ["7d"] = 7, ["30d"] = 30 }
V.DEFAULT_PERIOD = "7d"

--- The cut a sale paid and whether it was estimated: the recorded figure when there is one,
--- else CUT_RATE of the gross.
function V.Cut(gross, cut)
  if type(cut) == "number" and cut >= 0 then return cut, false end
  return math.floor((tonumber(gross) or 0) * V.CUT_RATE + 0.5), true
end

--- The item an acquisition position names: "commodity:<id>" or "item:<id>:<level>:...".
function V.PositionItemID(positionKey)
  if type(positionKey) ~= "string" then return nil end
  local id = positionKey:match("^commodity:(%d+)") or positionKey:match("^item:(%d+)")
  return id and tonumber(id) or nil
end

--- The item a sale mail's name stands for, from the character's own listings. GoldCap records
--- every item a character put on the auction house, by id and by the name the client gave it
--- (GC.Acquisitions.GetActivities); a sale mail carries the name only. When exactly one item
--- this character listed in this region bears the name, that is the item sold. Two items with
--- one name -- two quality ranks of a reagent -- is no answer.
function V.ListedItemID(activities, name, character, region)
  if type(name) ~= "string" or name == "" then return nil end
  local found
  for _, activity in ipairs(activities or {}) do
    if activity.itemName == name and activity.character == character and activity.region == region
        and type(activity.itemID) == "number" then
      if found and found ~= activity.itemID then return nil end
      found = activity.itemID
    end
  end
  return found
end

local function base(section, name, itemID, qty, gross, cut, pending, at)
  qty, gross = tonumber(qty) or 0, tonumber(gross) or 0
  local paidCut, estimated = V.Cut(gross, cut)
  return { section = section, name = name, itemID = itemID, itemExact = itemID ~= nil, qty = qty,
    gross = gross, cut = paidCut, cutEstimated = estimated, net = gross - paidCut,
    each = qty > 0 and math.floor(gross / qty) or nil, pending = pending == true, at = at }
end

--- A ledger sale. `realized` is its row in GC.Acquisitions.GetRealized(), joined on the
--- sale's own evidence key by the caller and on nothing looser; `sources` where the stock it
--- drew on came from (GC.Acquisitions.SourcesOf); `listedID` the item V.ListedItemID found for
--- the sale's name among the character's own listings.
--- realized.profit is GROSS -- proceeds minus known cost, the cut never subtracted there
--- (Core/Acquisitions.lua's ReconcileSale) -- so the cut comes off here, once, and the local
--- rows then agree with the server's basis.profit, which is net of it.
function V.LocalRow(sale, realized, sources, listedID)
  local row = base("local", sale.itemName, sale.itemID, sale.qty, sale.total, sale.cut, sale.pending, sale.at)
  row.key = sale.key
  if type(realized) == "table" and type(realized.profit) == "number" then
    row.profit = realized.profit - row.cut
    if type(realized.cost) == "number" then
      row.paid = realized.cost
      local units = tonumber(realized.quantity)
      if units and units > 0 then row.paidEach = math.floor(realized.cost / units) end
    end
    -- The position the sale was matched to names the item exactly -- the mail itself carries
    -- only the name.
    if row.itemID == nil then
      row.itemID = V.PositionItemID(realized.positionKey)
      row.itemExact = row.itemID ~= nil
    end
    row.sources = type(sources) == "table" and sources or nil
  end
  -- The sale's own id or its matched position first; the name among the character's own
  -- listings only when neither says.
  if row.itemID == nil and listedID then row.itemID, row.itemExact = listedID, true end
  return row
end

--- A sale from the goldcap.gg snapshot (GC.AppLedger). Its basis says how many units the
--- server's FIFO could cost: all, some (the profit and the cost cover those units only), none,
--- or -- no basis at all -- a free account, which is told nothing about profit.
function V.ServerRow(sale)
  local row = base("server", sale.name, sale.item, sale.qty, sale.total, sale.cut, sale.pending, sale.at)
  local basis = sale.basis
  if type(basis) ~= "table" then
    row.noBasis = true
  elseif basis.matched > 0 then
    row.profit, row.paid = basis.profit, basis.cost
    row.paidEach = math.floor(basis.cost / basis.matched)
    if basis.unmatched > 0 then row.costUnits = basis.matched end
  else
    row.costUnknown = true
  end
  return row
end

--- The newest `at` among the snapshot's own sale rows: what the server demonstrably holds.
--- 0 without a snapshot or with no sales in it, so every local sale stays local.
function V.Boundary(summary)
  local boundary = 0
  if type(summary) == "table" and type(summary.sales) == "table" then
    for _, sale in ipairs(summary.sales) do
      if type(sale.at) == "number" and sale.at > boundary then boundary = sale.at end
    end
  end
  return boundary
end

--- The ledger's sales newer than `boundary`, newest first.
function V.LocalSales(entries, boundary)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    if entry.kind == "sale" and type(entry.at) == "number" and entry.at > (boundary or 0) then
      out[#out + 1] = entry
    end
  end
  table.sort(out, function(a, b) return a.at > b.at end)
  return out
end

-- Case folding for the search box. Lua's lower() only knows ASCII, and the item names this
-- matches are in the client's language, so the capitals of Latin-1 (German, French, Spanish,
-- Portuguese, Italian) and of Cyrillic (Russian, Ukrainian) are folded here too. Korean and
-- Chinese have no case.
local function foldChar(ch)
  local b1, b2 = ch:byte(1, 2)
  local cp = (b1 - 192) * 64 + (b2 - 128)
  if cp >= 0x410 and cp <= 0x42F then cp = cp + 0x20          -- А..Я
  elseif cp >= 0x400 and cp <= 0x40F then cp = cp + 0x50      -- Ѐ..Џ (Ё, Є, І, Ї)
  elseif cp == 0x490 then cp = 0x491                          -- Ґ
  elseif cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then cp = cp + 0x20 -- À..Þ
  else return ch end
  return string.char(192 + math.floor(cp / 64), 128 + cp % 64)
end

function V.Fold(text)
  return (tostring(text or ""):lower():gsub("[\192-\223][\128-\191]", foldChar))
end

--- Whether `name` holds `query`, ignoring case; an empty query matches everything.
function V.Matches(name, query)
  local q = V.Fold(query):match("^%s*(.-)%s*$")
  if q == "" then return true end
  return V.Fold(name):find(q, 1, true) ~= nil
end

--- The rows sold at or after `from` whose name holds `query`, in their own order.
function V.Filter(rows, from, query)
  local out = {}
  for _, row in ipairs(rows or {}) do
    if type(row.at) == "number" and row.at >= (from or 0) and V.Matches(row.name, query) then
      out[#out + 1] = row
    end
  end
  return out
end

--- What the summary tiles say: how many sales, what reached the mailbox, the profit GoldCap
--- knows and on how many of the sales it knows it.
function V.Totals(rows)
  local t = { count = 0, net = 0, profit = 0, known = 0 }
  for _, row in ipairs(rows or {}) do
    t.count = t.count + 1
    t.net = t.net + row.net
    if type(row.profit) == "number" then
      t.profit = t.profit + row.profit
      t.known = t.known + 1
    end
  end
  return t
end

--- The row with the largest known profit above zero (the first of equals), or nil.
function V.Best(rows)
  local best
  for _, row in ipairs(rows or {}) do
    if type(row.profit) == "number" and row.profit > 0 and (not best or row.profit > best.profit) then
      best = row
    end
  end
  return best
end

--- A calendar day's key, 20260926 for 26 Sep 2026, from `dateOf(at)` (date("*t", at)).
function V.DayKey(at, dateOf)
  local t = dateOf(at)
  return t.year * 10000 + t.month * 100 + t.day
end

--- Local midnight `n` days before today's. A step of 86400 seconds lands an hour off
--- midnight when a clock change falls in between, so the result is snapped to the midnight of
--- the calendar day it landed on.
function V.DayStart(now, n, dateOf)
  local t = dateOf(now)
  local at = now - (t.hour * 3600 + t.min * 60 + t.sec) - (n or 0) * 86400
  local lt = dateOf(at)
  local off = lt.hour * 3600 + lt.min * 60 + lt.sec
  if off == 0 then return at end
  if lt.hour >= 12 then return at + (86400 - off) end
  return at - off
end

--- The first second a period covers: today's midnight for "today", six midnights back for
--- seven days (today and the six before it), and so on.
function V.PeriodStart(period, now, dateOf)
  local days = V.PERIOD_DAYS[period] or V.PERIOD_DAYS[V.DEFAULT_PERIOD]
  return V.DayStart(now, days - 1, dateOf)
end

--- Rows grouped by calendar day, in the order the days first appear (newest first for rows
--- sorted that way), each with its count and what reached the mailbox that day.
function V.Days(rows, dateOf)
  local days, byKey = {}, {}
  for _, row in ipairs(rows or {}) do
    local key = V.DayKey(row.at, dateOf)
    local day = byKey[key]
    if not day then
      day = { key = key, count = 0, net = 0, rows = {} }
      byKey[key] = day
      days[#days + 1] = day
    end
    day.count = day.count + 1
    day.net = day.net + row.net
    day.rows[#day.rows + 1] = row
  end
  return days
end

--- Whether the snapshot's sale list is a tail the period reaches past: the server holds more
--- sales than it listed, and the period starts before the oldest one listed -- so sales in the
--- period may be missing from this screen, and the totals must not pretend otherwise.
function V.Truncated(summary, from)
  if type(summary) ~= "table" or type(summary.sales) ~= "table" or type(summary.totals) ~= "table" then
    return false
  end
  if (summary.totals.salesCount or 0) <= #summary.sales then return false end
  local oldest
  for _, sale in ipairs(summary.sales) do
    if type(sale.at) == "number" and (not oldest or sale.at < oldest) then oldest = sale.at end
  end
  return oldest ~= nil and (from or 0) < oldest
end

-- Thousands grouped with a comma: the client's BreakUpLargeNumbers is passed in where it
-- exists, and uses the player's own separator.
local function comma(n)
  local text, found = ("%.0f"):format(n), 1
  while found > 0 do text, found = text:gsub("^(%d+)(%d%d%d)", "%1,%2") end
  return text
end

--- Copper as text with letter units, no coin icons: "12g 50s", "75c", "9,400g".
--- Compact (the default, for tiles and columns): a thousand gold and up drops the silver, a
--- gold and up drops the copper. `full` keeps every non-zero unit, for a breakdown whose
--- lines have to add up. `group(n)` may format the gold figure; nil falls back to commas.
function V.Money(copper, group, full)
  copper = math.floor(math.abs(tonumber(copper) or 0) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local gold = g > 0 and ((group and group(g)) or comma(g)) .. "g" or nil
  local parts = {}
  if gold then parts[#parts + 1] = gold end
  if full then
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
  end
  if g >= 1000 then return gold end
  if g > 0 then
    if s > 0 then parts[#parts + 1] = s .. "s" end
    return table.concat(parts, " ")
  end
  if s > 0 then parts[#parts + 1] = s .. "s" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
  return table.concat(parts, " ")
end

--- The same with its sign: "+61g", "-38g"; zero reads "+0c".
function V.Signed(copper, group, full)
  local n = tonumber(copper) or 0
  return (n < 0 and "-" or "+") .. V.Money(n, group, full)
end

--- How far a sale's price per unit sat from the market's, as a whole percent: 7 for 7% above,
--- -6 for 6% under. nil without a market price.
function V.Percent(each, market)
  if type(each) ~= "number" or type(market) ~= "number" or market <= 0 then return nil end
  return math.floor((each / market - 1) * 100 + 0.5)
end

--- How much of the riding cost gold plus bags covers, 0..1.
function V.Progress(have, cost)
  if type(cost) ~= "number" or cost <= 0 then return 0 end
  return math.max(0, math.min(1, (tonumber(have) or 0) / cost))
end

--- The table's column widths. `cols` lists the fixed columns left to right, each with the
--- width its widest text needs; the ITEM column takes whatever is left of `avail`. Nothing is
--- ever narrowed below what it needs -- a clipped figure is worse than a missing one -- so when
--- ITEM would fall under `itemMin` the columns named in `drop` go, in that order, and what
--- they said stays in the row's tooltip.
function V.FitColumns(avail, cols, gap, itemMin, drop)
  local hidden = {}
  local function left()
    local used = 0
    for _, col in ipairs(cols) do
      if not hidden[col.key] then used = used + col.need + gap end
    end
    return avail - used
  end
  for _, key in ipairs(drop or {}) do
    if left() >= itemMin then break end
    hidden[key] = true
  end
  local widths = {}
  for _, col in ipairs(cols) do widths[col.key] = col.need end
  return { widths = widths, hidden = hidden, item = math.max(0, left()) }
end
