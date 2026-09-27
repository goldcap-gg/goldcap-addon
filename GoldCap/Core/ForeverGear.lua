local _, GC = ...

-- WoW: Forever: the cheapest lots of each piece of gear in the player's own full scan, with the
-- part of the item link that decides its stats. Core/ForeverFold.lua keeps one aggregate per item
-- id and no link, and several versions of one id ("... of the Bear", "... of the Owl") differ in
-- stats -- so the AH Upgrade Finder (Core/ForeverUpgrades.lua) reads these instead.
--
-- Saved beside the fold, never inside it: the companion uploads the fold verbatim and the server
-- checks every fold string against its own grammar (plan 2a, D5), which has no room for a link.
--
-- Saved shape "gear v1" (Core/ForeverScan.lua writes it):
--   GoldCapDB.foreverScan.gear = { v = 1, at = <the fold's own `at`>, items = { [itemID] = "<lots>" } }
--   <lots>  = up to VARIANTS lots, cheapest first, space-separated, each "<unit>:<suffixID>:<uniqueID>"
--   unit    = buyout per unit, copper
--   suffixID, uniqueID = item string fields 7 and 8; "0:0" for a piece with no random suffix
--   One lot per distinct version: its cheapest.
-- Pure: rows in, strings out, no WoW API.
GC.ForeverGear = {}
GC.ForeverGear.VERSION = 1
GC.ForeverGear.VARIANTS = 3

local MAX_EXACT = 9007199254740991

local function positiveInt(v)
  return type(v) == "number" and v == v and v > 0 and v <= MAX_EXACT and v == math.floor(v)
end

-- The version of a link or item string: its suffix id and unique id (the suffix's scale), or
-- "0", "0" for a piece with no random suffix. nil when the text holds no item.
function GC.ForeverGear.Variant(link)
  if type(link) ~= "string" then return nil end
  local body = link:match("item:([%-%d:]+)")
  if not body then return nil end
  local fields, i = {}, 0
  for field in (body .. ":"):gmatch("([^:]*):") do
    i = i + 1
    fields[i] = field
  end
  local suffix = tonumber(fields[7]) or 0
  if suffix == 0 then return "0", "0" end
  return tostring(math.floor(suffix)), tostring(math.floor(tonumber(fields[8]) or 0))
end

function GC.ForeverGear.New()
  return { items = {}, rows = 0, nolink = 0 }
end

-- One gear row of the dump. A row whose link the client has not loaded yet is only counted: its
-- version is unknown, and a guessed one would score another version's stats.
function GC.ForeverGear.AddRow(acc, itemID, count, buyout, link)
  if not (positiveInt(itemID) and positiveInt(count) and positiveInt(buyout)) then return false end
  local suffix, unique = GC.ForeverGear.Variant(link)
  if not suffix then
    acc.nolink = acc.nolink + 1
    return false
  end
  local unit = math.max(1, math.floor(buyout / count + 0.5))
  local key = suffix .. ":" .. unique
  local lots = acc.items[itemID]
  if not lots then
    lots = {}
    acc.items[itemID] = lots
  end
  if lots[key] == nil or unit < lots[key] then lots[key] = unit end
  acc.rows = acc.rows + 1
  return true
end

local function encode(lots)
  local list = {}
  for key, unit in pairs(lots) do list[#list + 1] = { unit, key } end
  table.sort(list, function(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[2] < b[2]
  end)
  local parts = {}
  for i = 1, math.min(#list, GC.ForeverGear.VARIANTS) do
    parts[i] = ("%d:%s"):format(list[i][1], list[i][2])
  end
  return table.concat(parts, " ")
end

function GC.ForeverGear.Freeze(acc, at)
  local items, n = {}, 0
  for itemID, lots in pairs(acc.items) do
    items[itemID] = encode(lots)
    n = n + 1
  end
  if n == 0 then return nil end
  return { v = GC.ForeverGear.VERSION, at = at, items = items }
end

function GC.ForeverGear.Decode(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for unit, suffix, unique in s:gmatch("(%d+):(%-?%d+):(%-?%d+)") do
    out[#out + 1] = { unit = tonumber(unit), suffix = suffix, unique = unique }
  end
  return out
end

-- The item string a lot's stats and tooltip are read from: the bare id for a plain piece, the id
-- plus the two fields that pick the suffix and its scale for a random one.
function GC.ForeverGear.ItemString(itemID, lot)
  if lot.suffix == "0" then return ("item:%d"):format(itemID) end
  return ("item:%d:0:0:0:0:0:%s:%s"):format(itemID, lot.suffix, lot.unique)
end
