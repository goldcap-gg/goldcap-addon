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

-- e.min, and every ladder/depth price built from it, go through GC.Util.IntText, not a bare
-- %d: a listing's price is copper, and WoW's own string.format raises "integer overflow
-- attempting to store N" past +-2^31 (about 214,748g) -- a 1.5M-gold troll listing did exactly
-- that here (owner, Forever beta 2026-09-28). e.qty, e.lots and `levels` stay on %d: they are
-- counts, never prices, and cannot reach that range.
function GC.ForeverFold.Encode(e, gear)
  local flags = (gear and "g" or "") .. (e.browse and "b" or "")
  local parts, prev = {}, e.min
  for i, level in ipairs(e.ladder or {}) do
    parts[i] = ("%sx%d"):format(GC.Util.IntText(level[1] - prev), level[2])
    prev = level[1]
  end
  local s = ("%s,%d,%s,%s;%s"):format(GC.Util.IntText(e.min), e.qty or 0,
    e.lots and ("%d"):format(e.lots) or "", flags, table.concat(parts, " "))
  local p25, p50, levels = GC.ForeverFold.Depths(e)
  -- An entry with no levels in memory (Refloor's, decoded from the save) keeps the depth it has.
  if not p25 and positiveInt(e.p25) and positiveInt(e.p50) and positiveInt(e.levels) then
    p25, p50, levels = e.p25, e.p50, e.levels
  end
  if p25 and p50 and levels then
    s = s .. ("|%s,%s,%d"):format(GC.Util.IntText(p25 - e.min), GC.Util.IntText(p50 - e.min), levels)
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

-- A saved dump's entry (`encoded`) as a later browse pass found the item: its lowest price `floor`
-- and the units listed in all, `qty`. A browse-only scan used to keep the saved entry whole for
-- every item the dump had priced, however old the dump: a new cheap lot on a known item never
-- reached the Deals board, and lots bought since stayed on it, until the next whole dump (review,
-- 2026-11-07). The levels under the floor are gone (bought, or expired); a floor under the first
-- level is a new lot, of a size the browse pass does not say, so one unit, as a floor-only entry
-- counts it (Core/ForeverDeals.lua). The levels above the floor, the lot count and the depth part
-- stay the dump's, the depth never under the floor. Gear is left as it is: its browse rows are
-- per item key, and the first key a pass saw need not be the cheapest. Anything that does not
-- decode, or is not a dump's entry, comes back unchanged.
function GC.ForeverFold.Refloor(encoded, floor, qty)
  local e = GC.ForeverFold.Decode(encoded)
  if not e or e.gear or e.browse or #e.ladder == 0 or not positiveInt(floor) then return encoded end
  if not positiveInt(qty) then qty = e.qty end
  if floor == e.min and qty == e.qty then return encoded end
  local ladder = {}
  for _, level in ipairs(e.ladder) do
    if level[1] >= floor then ladder[#ladder + 1] = { level[1], level[2] } end
  end
  if #ladder == 0 or ladder[1][1] ~= floor then table.insert(ladder, 1, { floor, 1 }) end
  while #ladder > GC.ForeverFold.LADDER_LEVELS do ladder[#ladder] = nil end
  local out = { min = floor, qty = qty, lots = e.lots, ladder = ladder, levels = e.levels,
    p25 = e.p25 and math.max(e.p25, floor), p50 = e.p50 and math.max(e.p50, floor) }
  return GC.ForeverFold.Encode(out, false)
end

-- isGear(itemID) is the caller's client question (weapon or armor: several random suffixes can
-- share one id, so the fold's figure is the cheapest version's); a failing answer is "no".
--
-- `over`, when given, is asked after each entry whether this frame's share is spent: Freeze then
-- answers nil and how far it got, and a call given that back (`from`) goes on from there.
-- acc.items must take no new key in between, which the scanner sees to: it folds nothing while it
-- saves (Core/ForeverScan.lua's saveStep).
function GC.ForeverFold.Freeze(acc, isGear, over, from)
  local job = from or { out = {}, n = 0 }
  local out = job.out
  local itemID, e = next(acc.items, job.key)
  while itemID ~= nil do
    local gear = false
    if isGear then
      local ok, g = pcall(isGear, itemID)
      gear = ok and g == true
    end
    out[itemID] = GC.ForeverFold.Encode(e, gear)
    job.n, job.key = job.n + 1, itemID
    if over and over() then return nil, job end
    itemID, e = next(acc.items, itemID)
  end
  return out, job.n
end
