local _, GC = ...

-- WoW: Forever: flips through Blackwater, the neutral goblin auction house in Booty Bay, Gadgetzan
-- and Everlook that both factions share (ClickUp 1an60dzy5r4). An item it sells for less than this
-- character's own faction house, bought there and posted at home, makes the difference less the
-- house's 5% cut. The deposit is not counted: a lot that sells gets it back.
--
-- goldcap.gg compares Blizzard's hourly snapshots of the two houses and sends what it found in the
-- Companion's payload (Core/ImportString.lua ParseForever, section B): per item Blackwater's
-- cheapest unit, how many of its units are a flip, and the home house's cheapest unit and how many
-- it lists. The same rule is applied again here, so a flip the site sent that this rule refuses is
-- never shown, and BUY's cap for the line is the most a unit may cost and still be one.
--
-- Pure: the payload, the time and what the player checked are handed in.
GC.ForeverFlips = GC.ForeverFlips or {}
local F = GC.ForeverFlips

-- The auction house's cut on a sale at home, in percent.
F.CUT_PCT = 5
-- A flip makes at least this much a unit after the cut, in copper...
F.MIN_PROFIT = 100
-- ...and at least this share of what it costs.
F.MIN_RATIO = 0.15
-- The list shows the flips that make at least this a unit (1g); the many that make a few silver
-- would bury them.
F.LIST_MIN_PROFIT = 10000
-- A snapshot older than this is old news: the site reads one every hour.
F.STALE_SECONDS = 3 * 3600
-- Fewer sold a day than this on the home house, by its sales tape, and the flip is slow.
F.SLOW_PER_DAY = 1

local function count(v)
  return type(v) == "number" and v >= 0 and v == math.floor(v)
end

-- What a unit posted at home for `home` brings once the cut is taken.
function F.Sell(home)
  return math.floor(home * (100 - F.CUT_PCT) / 100)
end

-- The most a unit may cost and still be a flip against a home price of `home`.
function F.Cap(home)
  local sell = F.Sell(home)
  return math.min(sell - F.MIN_PROFIT, math.floor(sell / (1 + F.MIN_RATIO)))
end

function F.IsFlip(price, home)
  return count(price) and price > 0 and count(home) and home > 0 and price <= F.Cap(home)
end

-- How fast the item sells at home, from the payload's sales tape (`S` over `H` hours): nil when the
-- payload has no tape, so "slow" is never said of an item nobody measured.
function F.Speed(sales, hours, itemID)
  if not (type(hours) == "number" and hours > 0) then return nil end
  local s = type(sales) == "table" and sales[itemID] or nil
  local units = s and tonumber(s.units) or 0
  return { units = units, hours = hours, perDay = units * 24 / hours }
end

-- The list from a parsed payload: { at, stale, rows }, or nil when the payload has no section B.
-- Rows are the flips worth a line (LIST_MIN_PROFIT), the best a unit first:
--   { itemID, bw, bwQty, home, homeQty, profit, pct, cap, sold, soldHours, slow }
function F.Rows(payload, now)
  local data = type(payload) == "table" and payload.blackwater or nil
  if type(data) ~= "table" or type(data.items) ~= "table" then return nil end
  local rows = {}
  for itemID, e in pairs(data.items) do
    if F.IsFlip(e.bw, e.home) then
      local profit = F.Sell(e.home) - e.bw
      if profit >= F.LIST_MIN_PROFIT then
        local speed = F.Speed(payload.sales, payload.salesHours, itemID)
        rows[#rows + 1] = {
          itemID = itemID, bw = e.bw, bwQty = e.bwQty, home = e.home, homeQty = e.homeQty,
          profit = profit, pct = math.floor(profit * 100 / e.bw), cap = F.Cap(e.home),
          sold = speed and speed.units or nil, soldHours = speed and speed.hours or nil,
          slow = speed ~= nil and speed.perDay < F.SLOW_PER_DAY or nil,
        }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.itemID < b.itemID
  end)
  local at = tonumber(data.at) or 0
  return { at = at, stale = type(now) == "number" and now - at > F.STALE_SECONDS or false, rows = rows }
end

-- One unit of every row: how many rows, what they cost there and what they make at home. With
-- `checked` ({ [itemID] = true }) only the checked rows count.
function F.Totals(rows, checked)
  local n, spend, make = 0, 0, 0
  for _, r in ipairs(rows or {}) do
    if checked == nil or checked[r.itemID] then
      n, spend, make = n + 1, spend + r.bw, make + r.profit
    end
  end
  return n, spend, make
end

-- The BUY list for the checked rows, one unit each: its lines ({ i, q }, as GC.AppRuns takes them)
-- and each line's cap ({ [itemID] = copper }).
function F.Lines(rows, checked)
  local lines, caps = {}, {}
  for _, r in ipairs(rows or {}) do
    if checked and checked[r.itemID] then
      lines[#lines + 1] = { i = r.itemID, q = 1 }
      caps[r.itemID] = r.cap
    end
  end
  return lines, caps
end
