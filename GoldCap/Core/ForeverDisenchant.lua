local _, GC = ...

-- WoW: Forever: what a piece of gear disenchants into, and what that is worth at the scan's prices,
-- for the item tooltip (UI/Tooltip.lua). The owner asked for it after seeing another addon's
-- tooltip break a disenchant down by material and chance (2026-11-16).
--
-- Retail learns its yields from the player's own casts (Core/Disenchant.lua) and can say nothing of
-- an item never disenchanted. Here the table is the classic one, by quality, item level and weapon
-- or armor, as the Warcraft Wiki's "Disenchanting tables" page prints it (read 2026-11-16; the page
-- is marked outdated for the modern game, and its level 5 to 65 rows are the classic ones).
--
-- NOT yet checked against this server's drops. Known disagreements to settle with real casts:
--   * another Forever addon (Mastercraft 1.9.9, "checked against Wowhead Forever") gives green
--     weapons of item level 21 to 30 Greater Magic Essence where this table has Astral Essence;
--   * it uses 20% dust / 75% essence / 5% shard for every green weapon, and 75 / 20 / 5 for green
--     armor of level 21 to 25, where this table has 22 / 75 / 3 above level 50 and 75 / 15 / 10.
-- Gear above item level 65 has no row: nothing is said of it rather than guessed.
--
-- Pure: prices, names and icons are handed in.
GC.ForeverDisenchant = GC.ForeverDisenchant or {}
local D = GC.ForeverDisenchant

local STRANGE, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
local L_MAGIC, G_MAGIC, L_ASTRAL, G_ASTRAL, L_MYSTIC = 10938, 10939, 10998, 11082, 11134
local G_MYSTIC, L_NETHER, G_NETHER, L_ETERNAL, G_ETERNAL = 11135, 11174, 11175, 16202, 16203
local S_GLIMMER, L_GLIMMER, S_GLOW, L_GLOW = 10978, 11084, 11138, 11139
local S_RADIANT, L_RADIANT, S_BRILLIANT, L_BRILLIANT, NEXUS = 11177, 11178, 14343, 14344, 20725

-- Uncommon gear: { from, to, dust, dustMin, dustMax, essence, essMin, essMax, shard,
--                  armor's chances of the three, weapons' chances of the three }, in percent.
D.UNCOMMON = {
  { 5, 15, STRANGE, 1, 2, L_MAGIC, 1, 2, nil, { 80, 20, 0 }, { 20, 80, 0 } },
  { 16, 20, STRANGE, 2, 3, G_MAGIC, 1, 2, S_GLIMMER, { 75, 20, 5 }, { 20, 75, 5 } },
  { 21, 25, STRANGE, 4, 6, L_ASTRAL, 1, 2, S_GLIMMER, { 75, 15, 10 }, { 15, 75, 10 } },
  { 26, 30, SOUL, 1, 2, G_ASTRAL, 1, 2, L_GLIMMER, { 75, 20, 5 }, { 20, 75, 5 } },
  { 31, 35, SOUL, 2, 5, L_MYSTIC, 1, 2, S_GLOW, { 75, 20, 5 }, { 20, 75, 5 } },
  { 36, 40, VISION, 1, 2, G_MYSTIC, 1, 2, L_GLOW, { 75, 20, 5 }, { 20, 75, 5 } },
  { 41, 45, VISION, 2, 5, L_NETHER, 1, 2, S_RADIANT, { 75, 20, 5 }, { 20, 75, 5 } },
  { 46, 50, DREAM, 1, 2, G_NETHER, 1, 2, L_RADIANT, { 75, 20, 5 }, { 20, 75, 5 } },
  { 51, 55, DREAM, 2, 5, L_ETERNAL, 1, 2, S_BRILLIANT, { 75, 20, 5 }, { 22, 75, 3 } },
  { 56, 60, ILLUSION, 1, 2, G_ETERNAL, 1, 2, L_BRILLIANT, { 75, 20, 5 }, { 22, 75, 3 } },
  { 61, 65, ILLUSION, 2, 5, G_ETERNAL, 2, 3, L_BRILLIANT, { 75, 20, 5 }, { 22, 75, 3 } },
}

-- Rare and epic gear: { from, to, { item, min, max, chance }... }.
D.RARE = {
  { 1, 25, { S_GLIMMER, 1, 1, 100 } },
  { 26, 30, { L_GLIMMER, 1, 1, 100 } },
  { 31, 35, { S_GLOW, 1, 1, 100 } },
  { 36, 40, { L_GLOW, 1, 1, 100 } },
  { 41, 45, { S_RADIANT, 1, 1, 100 } },
  { 46, 50, { L_RADIANT, 1, 1, 100 } },
  { 51, 55, { S_BRILLIANT, 1, 1, 100 } },
  { 56, 65, { L_BRILLIANT, 1, 1, 99.5 }, { NEXUS, 1, 1, 0.5 } },
}
D.EPIC = {
  { 40, 45, { S_RADIANT, 2, 4, 100 } },
  { 46, 50, { L_RADIANT, 2, 4, 100 } },
  { 51, 55, { S_BRILLIANT, 2, 4, 100 } },
  { 56, 60, { NEXUS, 1, 1, 100 } },
  { 61, 65, { NEXUS, 1, 2, 100 } },
}

-- The wands an enchanter makes: gear by class and quality that the game does not disenchant (the
-- item database lists no disenchant result for them).
D.NEVER = { [11287] = true, [11288] = true, [11289] = true, [11290] = true, [217287] = true,
  [249144] = true, [249232] = true, [249234] = true, [249237] = true, [249385] = true }

local WEAPON, ARMOR = 2, 4
-- A shirt and a tabard are armor the game does not disenchant.
local NO_SLOT = { INVTYPE_BODY = true, INVTYPE_TABARD = true, [""] = true }

local function rowFor(rows, itemLevel)
  for _, row in ipairs(rows) do
    if itemLevel >= row[1] and itemLevel <= row[2] then return row end
  end
  return nil
end

--- What gear of this quality (Enum.ItemQuality: 2 uncommon, 3 rare, 4 epic) and item level gives:
--- { { itemID, min, max, chance (percent) }, ... }, the likeliest first; nil when the table has no
--- row for it.
function D.Results(quality, itemLevel, isWeapon)
  if type(quality) ~= "number" or type(itemLevel) ~= "number" then return nil end
  if quality == 2 then
    local row = rowFor(D.UNCOMMON, itemLevel)
    if not row or (isWeapon and itemLevel < 6) then return nil end
    local chance = isWeapon and row[11] or row[10]
    local out = {
      { itemID = row[3], min = row[4], max = row[5], chance = chance[1] },
      { itemID = row[6], min = row[7], max = row[8], chance = chance[2] },
    }
    if row[9] and chance[3] > 0 then out[3] = { itemID = row[9], min = 1, max = 1, chance = chance[3] } end
    table.sort(out, function(a, b) return a.chance > b.chance end)
    return out
  end
  local row = rowFor(quality == 3 and D.RARE or quality == 4 and D.EPIC or {}, itemLevel)
  if not row then return nil end
  local out = {}
  for i = 3, #row do
    out[#out + 1] = { itemID = row[i][1], min = row[i][2], max = row[i][3], chance = row[i][4] }
  end
  return out
end

--- Whether an item is gear the game disenchants at all: a weapon or armor that is worn, of
--- uncommon to epic quality, and not one of the few it refuses.
function D.Can(itemID, quality, classID, equipLoc)
  if D.NEVER[itemID] then return false end
  if not (classID == WEAPON or classID == ARMOR) then return false end
  if type(quality) ~= "number" or quality < 2 or quality > 4 then return false end
  return not NO_SLOT[equipLoc or ""]
end

--- What one disenchant is worth on average: the sum of chance x mean count x price, over the
--- materials with a price. Answers the copper (nil when none has a price) and whether a material
--- had none. `priceOf(itemID)`: a unit's price in copper, or nil.
function D.Value(results, priceOf)
  local total, missing, priced = 0, false, false
  for _, m in ipairs(results or {}) do
    local price = priceOf(m.itemID)
    m.price = (type(price) == "number" and price > 0) and price or nil
    if m.price then
      priced = true
      total = total + m.price * (m.min + m.max) / 2 * m.chance / 100
    else
      missing = true
    end
  end
  if not priced then return nil, missing end
  return math.floor(total + 0.5), missing
end

local function percent(chance)
  if chance == math.floor(chance) then return ("%d%%"):format(chance) end
  return ("%.1f%%"):format(chance)
end

--- The tooltip's lines for one item, each { kind = "text", left, right }: "Disenchant" with what a
--- cast is worth on average, then a line a material: its icon and name, how many, a unit's price,
--- and its chance. Nil for an item that is not disenchanted or that the table has no row for.
--- `item`: { itemID, quality, itemLevel, classID, equipLoc }. `driver`: priceOf(itemID),
--- nameOf(itemID), iconOf(itemID) (each may answer nil), coin(copper). `show` (optional):
--- { value = false } leaves the lines out altogether, { mats = false } the materials' lines.
function D.Lines(item, driver, show)
  if show and show.value == false then return nil end
  if type(item) ~= "table" or not D.Can(item.itemID, item.quality, item.classID, item.equipLoc) then return nil end
  local results = D.Results(item.quality, item.itemLevel, item.classID == WEAPON)
  if not results then return nil end
  local total = D.Value(results, driver.priceOf)
  local lines = { { kind = "text", left = GC.L["Disenchant"],
    right = total and ("~" .. driver.coin(total)) or GC.L["no price yet"] } }
  if show and show.mats == false then return lines end
  for _, m in ipairs(results) do
    local icon = driver.iconOf(m.itemID)
    local name = driver.nameOf(m.itemID) or ("#" .. m.itemID)
    local count = m.min == m.max and ("×%d"):format(m.min) or ("×%d-%d"):format(m.min, m.max)
    local left = ("  %s%s %s"):format(icon and ("|T" .. icon .. ":0|t ") or "", name, count)
    left = left .. " · " .. (m.price and driver.coin(m.price) or GC.L["no price yet"])
    lines[#lines + 1] = { kind = "text", left = left, right = percent(m.chance) }
  end
  return lines
end
