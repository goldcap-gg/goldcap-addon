local _, GC = ...

-- WoW: Forever: the player's own full scan, folded per item. Pure: rows in, one compact string
-- per item out, no WoW API. Core/ForeverScan.lua feeds it and keeps the latest fold in
-- GoldCapDB.foreverScan.fold.
--
-- Per item: the cheapest unit, the units listed, the lots holding them, and the five cheapest
-- price levels, plus (fold version 2) the quarter- and half-way unit prices and the count of
-- distinct price levels the item was listed at. One string per item, not a table, because
-- SavedVariables writes every table field on a line of its own -- a table per item would triple
-- the file (spec target ~300-600 KB). Ladder levels are stored as their distance from the level
-- below, the first from `min`: prices repeat their leading digits, deltas do not. The depth part
-- rides after the ladder, behind a `|`, as distances from `min` too, so a version-1 reader and a
-- version-1 string both still work.
GC.ForeverFold = {}
GC.ForeverFold.LADDER_LEVELS = 5
-- "AH value": the cheapest level a tenth of the listed units reach, not the single cheapest lot.
-- One troll lot at 1c among four thousand units is not what the item fetches.
GC.ForeverFold.VALUE_SHARE = 0.10

-- Fold version 2 (plan 3c): every string may carry a depth part after the ladder -- the unit
-- prices at a quarter and at half of the listed units, and how many distinct prices the item
-- was listed at. The Deals board's "Under market" kind needs the price count for its thin-market
-- guard and never measures above the half-way price (it measures against the AH value below).
-- A version-1 string simply has no depth part.
GC.ForeverFold.VERSION = 2
GC.ForeverFold.DEPTH_SHARES = { 0.25, 0.50 }

local MAX_EXACT = 9007199254740991

local function positiveInt(v)
  return type(v) == "number" and v == v and v > 0 and v <= MAX_EXACT and v == math.floor(v)
end

function GC.ForeverFold.New()
  return { items = {}, rows = 0, skipped = 0, pending = 0 }
end

local function insertLevel(ladder, unit, qty)
  for i = 1, #ladder do
    local level = ladder[i]
    if level[1] == unit then level[2] = level[2] + qty; return end
    if unit < level[1] then
      table.insert(ladder, i, { unit, qty })
      if #ladder > GC.ForeverFold.LADDER_LEVELS then ladder[#ladder] = nil end
      return
    end
  end
  if #ladder < GC.ForeverFold.LADDER_LEVELS then ladder[#ladder + 1] = { unit, qty } end
end

-- One auction of the dump. A row with no buyout (bid-only), no count or no item is not a price
-- and is only counted. hasAllInfo == false means the client has not loaded the item's name or
-- link yet; the price and item id come with the row, so it is folded, and counted.
function GC.ForeverFold.AddRow(acc, itemID, count, buyout, hasAllInfo)
  if not (positiveInt(itemID) and positiveInt(count) and positiveInt(buyout)) then
    acc.skipped = acc.skipped + 1
    return false
  end
  if hasAllInfo == false then acc.pending = acc.pending + 1 end
  local unit = math.max(1, math.floor(buyout / count + 0.5))
  local e = acc.items[itemID]
  if not e or e.browse then
    e = { min = unit, qty = 0, lots = 0, ladder = {} }
    acc.items[itemID] = e
  end
  if unit < e.min then e.min = unit end
  e.qty = e.qty + count
  e.lots = e.lots + 1
  insertLevel(e.ladder, unit, count)
  -- Every level, not only the ladder's five: the depth part needs the whole book. This scan's
  -- memory only -- Depths counts distinct prices straight off this table, and it is never
  -- written to the save.
  e.all = e.all or {}
  e.all[unit] = (e.all[unit] or 0) + count
  acc.rows = acc.rows + 1
  return true
end

-- An item a browse pass saw (Core/BookPass.lua's book row: floor, qty) that the dump did not
-- list: its floor and quantity, no lot count, no ladder.
function GC.ForeverFold.AddBrowse(acc, itemID, floor, qty)
  if not (positiveInt(itemID) and positiveInt(floor)) then return false end
  if acc.items[itemID] then return false end
  acc.items[itemID] = { min = floor, qty = positiveInt(qty) and qty or 0, browse = true }
  return true
end

function GC.ForeverFold.Value(e)
  local ladder = e.ladder
  if not ladder or #ladder == 0 then return e.min end
  local need = math.max(1, math.ceil((e.qty or 0) * GC.ForeverFold.VALUE_SHARE))
  local seen = 0
  for i = 1, #ladder do
    seen = seen + ladder[i][2]
    if seen >= need then return ladder[i][1] end
  end
  return ladder[#ladder][1]
end

-- The unit prices at which a quarter and half of the listed units sit at or under, and how many
-- distinct prices the item was listed at -- from every level this scan saw. nil, nil, nil for an
-- entry with no levels in memory (a browse row, or one decoded from the save).
function GC.ForeverFold.Depths(e)
  local all = type(e) == "table" and e.all or nil
  if type(all) ~= "table" or type(e.qty) ~= "number" or e.qty <= 0 then return nil, nil, nil end
  local units = {}
  for unit in pairs(all) do units[#units + 1] = unit end
  table.sort(units)
  local shares, found, seen, s = GC.ForeverFold.DEPTH_SHARES, {}, 0, 1
  for _, unit in ipairs(units) do
    seen = seen + all[unit]
    while s <= #shares and seen >= math.max(1, math.ceil(e.qty * shares[s])) do
      found[s] = unit
      s = s + 1
    end
  end
  for i = s, #shares do found[i] = units[#units] end
  return found[1], found[2], #units
end

function GC.ForeverFold.Encode(e, gear)
  local flags = (gear and "g" or "") .. (e.browse and "b" or "")
  local parts, prev = {}, e.min
  for i, level in ipairs(e.ladder or {}) do
    parts[i] = ("%dx%d"):format(level[1] - prev, level[2])
    prev = level[1]
  end
  local s = ("%d,%d,%s,%s;%s"):format(e.min, e.qty or 0, e.lots and ("%d"):format(e.lots) or "", flags,
    table.concat(parts, " "))
  local p25, p50, levels = GC.ForeverFold.Depths(e)
  if p25 and p50 and levels then
    s = s .. ("|%d,%d,%d"):format(p25 - e.min, p50 - e.min, levels)
  end
  return s
end

function GC.ForeverFold.Decode(s)
  if type(s) ~= "string" then return nil end
  local body, depth = s:match("^([^|]*)|?(.*)$")
  local min, qty, lots, flags, ladder = body:match("^(%d+),(%d+),(%d*),(%a*);(.*)$")
  min = tonumber(min)
  if not min or min <= 0 then return nil end
  local e = { min = min, qty = tonumber(qty), lots = tonumber(lots),
    gear = flags:find("g", 1, true) ~= nil, browse = flags:find("b", 1, true) ~= nil, ladder = {} }
  local unit = min
  for delta, q in ladder:gmatch("(%d+)x(%d+)") do
    unit = unit + tonumber(delta)
    e.ladder[#e.ladder + 1] = { unit, tonumber(q) }
  end
  local d25, d50, levels = depth:match("^(%d+),(%d+),(%d+)$")
  if d25 then
    e.p25, e.p50, e.levels = min + tonumber(d25), min + tonumber(d50), tonumber(levels)
  end
  e.value = GC.ForeverFold.Value(e)
  return e
end

-- isGear(itemID) is the caller's client question (weapon or armor: several random suffixes can
-- share one id, so the fold's figure is the cheapest version's); a failing answer is "no".
function GC.ForeverFold.Freeze(acc, isGear)
  local out, n = {}, 0
  for itemID, e in pairs(acc.items) do
    local gear = false
    if isGear then
      local ok, g = pcall(isGear, itemID)
      gear = ok and g == true
    end
    out[itemID] = GC.ForeverFold.Encode(e, gear)
    n = n + 1
  end
  return out, n
end
