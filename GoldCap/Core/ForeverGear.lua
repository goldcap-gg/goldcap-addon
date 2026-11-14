local _, GC = ...

-- WoW: Forever: the cheapest lots of each piece of gear in the player's own full scan, with the
-- part of the item link that decides its stats. Core/ForeverFold.lua keeps one aggregate per item
-- id and no link, and several versions of one id ("... of the Bear", "... of the Owl") differ in
-- stats -- so the AH Upgrade Finder (Core/ForeverUpgrades.lua) reads these instead.
--
-- Saved beside the fold, never inside it: the companion uploads the fold verbatim and the server
-- checks every fold string against its own grammar (plan 2a, D5), which has no room for a link.
--
-- Saved shape "gear v2" (Core/ForeverScan.lua writes it):
--   GoldCapDB.foreverScan.gear = { v = 2, at = <the fold's own `at`>, items = { [itemID] = "<lots>" },
--     late = { missing, found }? }
--   <lots>  = up to VARIANTS lots, cheapest first, space-separated, each
--             "<unit>:<suffixID>:<uniqueID>:<bonus>"
--   unit    = buyout per unit, copper
--   suffixID, uniqueID = item string fields 7 and 8; "0:0" for a piece with no random suffix
--   bonus   = the link's bonus IDs, sorted and joined by "." (BonusKey); "0" for none
--   One lot per distinct version: its cheapest.
--   late    = the gear rows the read found with no link yet, and how many of them the late-link
--             pass after the save read (Core/ForeverScan.lua)
-- Forever writes a random suffix as a bonus ID, with fields 7 and 8 empty (HERO probe P1, 13.11:
-- 15,044 of the 79,250 gear rows a scan read carried one, none two or more), so a v1 save stored
-- every version as "0:0" and every version was scored by its base stats. A v1 lot
-- ("<unit>:<suffixID>:<uniqueID>") still decodes, its bonus unknown (nil).
-- Pure: rows in, strings out, no WoW API.
GC.ForeverGear = {}
GC.ForeverGear.VERSION = 2
-- Versions kept per item: a green with a random suffix lists a dozen or more of them at once (a
-- browse by name listed 24 for Carving Knife, probe 08.11), and three kept only the cheapest
-- three, whatever their stats.
GC.ForeverGear.VARIANTS = 8

local MAX_EXACT = 9007199254740991

local function positiveInt(v)
  return type(v) == "number" and v == v and v > 0 and v <= MAX_EXACT and v == math.floor(v)
end

-- An item string's fields by position, empty ones kept: "item:15211::::::::17" is 15211, seven
-- empty fields, then 17. nil when the text holds no item. The pattern stops at a crafter's GUID
-- ("Player-6949-006A8F82"), which comes after every field read here.
local function fieldsOf(link)
  if type(link) ~= "string" then return nil end
  local body = link:match("item:([%-%d:]+)")
  if not body then return nil end
  local fields, i = {}, 0
  for field in (body .. ":"):gmatch("([^:]*):") do
    i = i + 1
    fields[i] = field
  end
  return fields
end

-- The link's bonus IDs, the version on Forever (HERO probe P1, 13.11): field 13 is their count and
-- that many IDs follow it. Sorted and joined by ".", so the same IDs in another order are the same
-- version; "0" for none. What comes after them -- a modifier (":1:28:5240", whose value varies
-- between lots of one version and changes no stat), relic fields, the crafter's GUID -- is not
-- read. The scan, an item-search row and a key's sample link agreed on every lot the probe read.
-- nil when the text holds no item.
function GC.ForeverGear.BonusKey(link)
  local fields = fieldsOf(link)
  if not fields then return nil end
  local n = tonumber(fields[13])
  if not n or n <= 0 then return "0" end
  local ids = {}
  for j = 14, 13 + n do
    local id = tonumber(fields[j])
    if id then ids[#ids + 1] = math.floor(id) end
  end
  if #ids == 0 then return "0" end
  table.sort(ids)
  for j = 1, #ids do ids[j] = tostring(ids[j]) end
  return table.concat(ids, ".")
end

-- The version of a link or item string: its suffix id and unique id (the suffix's scale), "0",
-- "0" for a piece with no random suffix in fields 7 and 8, and its bonus IDs (BonusKey). nil when
-- the text holds no item.
function GC.ForeverGear.Variant(link)
  local fields = fieldsOf(link)
  if not fields then return nil end
  local bonus = GC.ForeverGear.BonusKey(link)
  local suffix = tonumber(fields[7]) or 0
  if suffix == 0 then return "0", "0", bonus end
  return tostring(math.floor(suffix)), tostring(math.floor(tonumber(fields[8]) or 0)), bonus
end

function GC.ForeverGear.New()
  return { items = {}, rows = 0, nolink = 0 }
end

-- Final review I2: for a random-suffix item (a negative suffixID), only the low 16 bits of field 8
-- pick the suffix's stat roll ("factor") -- the rest of a real link's uniqueID is per-instance
-- noise the client's stats do not depend on. Dedupe on that factor, never the whole uniqueID, or
-- every lot of one suffix ("... of the Owl") reads as its own version and fills the lot cap,
-- crowding out a different, cheaper suffix ("... of the Bear") entirely. A non-random piece
-- (suffixID 0 or a positive random property) has no such factor: its stats do not depend on field
-- 8 at all, so the whole field is ignored.
local function versionKey(suffix, unique)
  local n = tonumber(suffix) or 0
  if n >= 0 then return suffix end
  return suffix .. ":" .. tostring((tonumber(unique) or 0) % 65536)
end

-- One gear row of the dump. A row whose link the client has not loaded yet is only counted, and
-- answers false, "nolink": its version is unknown, and a guessed one would score another
-- version's stats. Core/ForeverScan.lua reads such a row again once its link has loaded.
function GC.ForeverGear.AddRow(acc, itemID, count, buyout, link)
  if not (positiveInt(itemID) and positiveInt(count) and positiveInt(buyout)) then return false end
  local suffix, unique, bonus = GC.ForeverGear.Variant(link)
  if not suffix then
    acc.nolink = acc.nolink + 1
    return false, "nolink"
  end
  local unit = math.max(1, math.floor(buyout / count + 0.5))
  local key = versionKey(suffix, unique) .. "/" .. bonus
  local lots = acc.items[itemID]
  if not lots then
    lots = {}
    acc.items[itemID] = lots
  end
  local cur = lots[key]
  -- The full uniqueID of whichever lot is currently cheapest is kept for ItemString -- which
  -- exact per-instance id survives does not matter, since the client's stats only follow the
  -- suffix and its factor (above), never the rest of the id.
  if cur == nil or unit < cur.unit then
    lots[key] = { unit = unit, suffix = suffix, unique = unique, bonus = bonus }
  end
  acc.rows = acc.rows + 1
  return true
end

local function encode(lots)
  local list = {}
  for _, lot in pairs(lots) do list[#list + 1] = lot end
  table.sort(list, function(a, b)
    if a.unit ~= b.unit then return a.unit < b.unit end
    if a.suffix ~= b.suffix then return a.suffix < b.suffix end
    if a.unique ~= b.unique then return a.unique < b.unique end
    -- On Forever every lot's suffix and unique are "0": the bonus is what tells two versions at
    -- one price apart, so the same scan freezes to the same text.
    return a.bonus < b.bonus
  end)
  local parts = {}
  for i = 1, math.min(#list, GC.ForeverGear.VARIANTS) do
    -- `unit` is copper -- WoW's own string.format raises "integer overflow attempting to store
    -- N" past +-2^31 (about 214,748g), same as Core/ForeverFold.lua's Encode.
    parts[i] = ("%s:%s:%s:%s"):format(GC.Util.IntText(list[i].unit), list[i].suffix, list[i].unique,
      list[i].bonus)
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

-- A v1 lot has no fourth field: its bonus is nil, unknown -- not "0", which says the lot has none.
function GC.ForeverGear.Decode(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for unit, suffix, unique, bonus in s:gmatch("(%d+):(%-?%d+):(%-?%d+):?([%d%.]*)") do
    out[#out + 1] = { unit = tonumber(unit), suffix = suffix, unique = unique,
      bonus = bonus ~= "" and bonus or nil }
  end
  return out
end

-- The item string a lot's stats and tooltip are read from. A lot with bonus IDs: the id and those
-- IDs alone, "item:<id>::::::::::::<n>:<b1>..." (fields 2 to 12 empty) -- in the HERO probe (P2,
-- 13.11) that form gave exactly the full link's stats and name in all 9 reads, and the bare id the
-- base item's (Carving Knife: 5.94 DPS bare, 3.75 "of Healing"). Otherwise the bare id for a plain
-- piece, the id plus the two fields that pick the suffix and its scale for a random one.
function GC.ForeverGear.ItemString(itemID, lot)
  local bonus = lot.bonus
  if type(bonus) == "string" and bonus ~= "0" and bonus ~= "" then
    local ids = {}
    for id in bonus:gmatch("%d+") do ids[#ids + 1] = id end
    return ("item:%d::::::::::::%d:%s"):format(itemID, #ids, table.concat(ids, ":"))
  end
  if lot.suffix == "0" then return ("item:%d"):format(itemID) end
  return ("item:%d:0:0:0:0:0:%s:%s"):format(itemID, lot.suffix, lot.unique)
end
