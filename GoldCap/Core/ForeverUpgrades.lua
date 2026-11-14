local _, GC = ...

-- WoW: Forever's AH Upgrade Finder (plan 3e, growth spec D8; the HERO tab, 2026-11-13): for each
-- equipment slot, the piece in the player's last full scan (Core/ForeverGear.lua's lots) that this
-- character can use now and that beats what it wears by the most, whatever it costs (one over the
-- gold carried is marked overGold, not hidden); one a level or two ahead when nothing usable now
-- does. Beside it, up to ALTS others: the piece the best set for the gold carried puts there
-- (BestSet), a stronger piece a level or two ahead, and cheaper ones on the price frontier. It used
-- to be the cheapest piece that beat the worn one at all, which on the owner's save (2026-11-06)
-- offered "+1 armour" for 1s in every slot while greens with agility sat a silver or two dearer;
-- then the strongest the gold carried paid for, which at 0 gold showed one line saying everything
-- costs more and never the piece itself (owner's scan, 2026-11-13).
--
-- A score is the piece's own stats -- the client's GetItemStats, never a guess -- times the
-- class's stat weights, which the player sees in the window and changes with /gc weights. A piece
-- the client has not answered for (level or stats not loaded) is counted as loading and asked for;
-- effects GetItemStats does not list are not counted, and the window says what is.
--
-- Usable: judged for the character looking, never at scan time (the fold is account-wide). The
-- tooltip first -- a red line is the client saying no (armour or weapon skill, class, profession)
-- -- then Classic's class rules below when the tooltip cannot tell. Pure over an injected driver;
-- the client's is Task 9's realDriver.
GC.ForeverUpgrades = GC.ForeverUpgrades or {}

local C = {
  LEVEL_AHEAD = 2,         -- "for later": a required level up to this many above the character's
  MIN_GAIN_SHARE = 0.05,   -- an upgrade beats the worn piece by at least 5% of its score
  -- ...and by at least this many points of the character's top primary stat (its largest weight
  -- among STR/AGI/STA/INT/SPI): +1 agility for a rogue, +2 strength, +100 armour. A white piece
  -- worn has almost no score, so 5% of it let "+3 armour" for 6s through (owner's save, 2026-11-06).
  MIN_GAIN_POINTS = 1,
  TOOLTIP_CHECKS = 5,      -- tooltip reads per slot and per pass, strongest first
  ALTS = 3,                -- other choices shown beside a slot's strongest piece
  -- Each cheaper choice costs at most this share of the one shown before it (the first, of the
  -- strongest): 100, 90, 80 would be three lines saying the same thing.
  ALT_PRICE_STEP = 0.8,
  FRONTIER_CHECKS = 8,     -- tooltip reads per slot for its cheaper choices, and again for its set choices
  SET_STATES = 400,        -- the best set's partial sets kept after each group (BestSet)
  REQUEST_PER_BUILD = 100, -- item-data requests per build
  -- Weapon-speed tooltip reads per build (Build's speedOfItem). A rogue's first build read one for
  -- every main-hand lot it weighed, several hundred C_TooltipInfo.GetHyperlink calls in one frame
  -- (13.11); the rest wait for the next build, strongest first.
  SPEED_READS = 40,
  -- The seconds between a class's weapon-swing abilities, for a class whose main hand is weighed by
  -- its speed (DpsFactor): a rogue's Sinister Strike costs 45 energy and energy comes back at 10 a
  -- second, so one lands about every 4.5 s.
  ABILITY_EVERY = { ROGUE = 4.5 },
  REF_SPEED = 2.0,         -- the weapon speed DpsFactor scores at 1: slower counts more, faster less
  -- The attack power one point of weapon DPS is worth: Camelot's ATTACK_POWER_MAGIC_NUMBER, its
  -- character sheet's damage from attack power (PaperDollFrameStats.lua).
  AP_PER_DPS = 14,
  -- The white damage left while a weapon swings in each hand: Classic's white hits miss 24% of the
  -- time instead of 5% when dual-wielding, (1 - 0.24) / (1 - 0.05). Abilities (Sinister Strike)
  -- miss as before. A Classic rule, not yet measured in WoW: Forever.
  DUAL_WIELD_WHITE = 0.8,
}
GC.ForeverUpgrades.C = C

-- The stat tokens /gc weights takes, and the GetItemStats keys each one reads. Names on screen are
-- the client's own globals (_G[key]), already in the player's language.
GC.ForeverUpgrades.TOKENS = {
  STR = { "ITEM_MOD_STRENGTH_SHORT" }, AGI = { "ITEM_MOD_AGILITY_SHORT" },
  STA = { "ITEM_MOD_STAMINA_SHORT" }, INT = { "ITEM_MOD_INTELLECT_SHORT" },
  SPI = { "ITEM_MOD_SPIRIT_SHORT" }, ARMOR = { "RESISTANCE0_NAME" },
  DPS = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" }, AP = { "ITEM_MOD_ATTACK_POWER_SHORT" },
  SP = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
}
GC.ForeverUpgrades.TOKEN_ORDER = { "STR", "AGI", "STA", "INT", "SPI", "ARMOR", "DPS", "AP", "SP" }

-- Starting weights per class: which stats a levelling character of the class wants, roughly. Shown
-- in the window and changed with /gc weights -- a scoring choice the player can see, never a stat.
-- In Classic one point of weapon DPS is worth 14 attack power (HERO plan, Finding 3, 2026-11-13), so
-- a class's DPS weight is 14 times its AP weight, for the weapon it fights with (HANDS below says
-- which hand that is): the melee classes' 7 (AP 0.5), the hunter's 5.6 (AP 0.4, the bow). A
-- shaman's strength is two attack power, so its AP is half its STR, 0.3, and its DPS 14 times that,
-- 4.2; a druid's 0.3 AP is the attack power on gear its forms fight with. A caster's weapon DPS is
-- its wand's: 2, as much as its top stat for a few points of DPS, the most its wand adds while it
-- levels. A player's own /gc weights stay as they were saved (migrateWeights below).
GC.ForeverUpgrades.DEFAULT_WEIGHTS = {
  WARRIOR = { STR = 1, AGI = 0.5, STA = 0.5, AP = 0.5, DPS = 7, ARMOR = 0.01 },
  PALADIN = { STR = 1, INT = 0.4, STA = 0.5, AGI = 0.3, AP = 0.5, DPS = 7, ARMOR = 0.01 },
  ROGUE = { AGI = 1, STR = 0.5, STA = 0.4, AP = 0.5, DPS = 7, ARMOR = 0.01 },
  HUNTER = { AGI = 1, INT = 0.3, STA = 0.4, AP = 0.4, DPS = 5.6, ARMOR = 0.01 },
  SHAMAN = { INT = 0.8, STR = 0.6, AGI = 0.4, STA = 0.5, SPI = 0.2, SP = 0.8, AP = 0.3, DPS = 4.2, ARMOR = 0.01 },
  DRUID = { INT = 0.8, STR = 0.6, AGI = 0.6, STA = 0.5, SPI = 0.3, SP = 0.8, AP = 0.3, ARMOR = 0.01 },
  MAGE = { INT = 1, SPI = 0.4, STA = 0.5, SP = 1, DPS = 2, ARMOR = 0.005 },
  PRIEST = { INT = 1, SPI = 0.6, STA = 0.5, SP = 1, DPS = 2, ARMOR = 0.005 },
  WARLOCK = { INT = 1, SPI = 0.4, STA = 0.6, SP = 1, DPS = 2, ARMOR = 0.005 },
}

-- Slot groups in display order; labelKey is the client's own slot name global (INVTYPE_*).
GC.ForeverUpgrades.GROUPS = {
  { key = "HEAD", slots = { 1 }, labelKey = "INVTYPE_HEAD" },
  { key = "NECK", slots = { 2 }, labelKey = "INVTYPE_NECK" },
  { key = "SHOULDER", slots = { 3 }, labelKey = "INVTYPE_SHOULDER" },
  { key = "BACK", slots = { 15 }, labelKey = "INVTYPE_CLOAK" },
  { key = "CHEST", slots = { 5 }, labelKey = "INVTYPE_CHEST" },
  { key = "WRIST", slots = { 9 }, labelKey = "INVTYPE_WRIST" },
  { key = "HANDS", slots = { 10 }, labelKey = "INVTYPE_HAND" },
  { key = "WAIST", slots = { 6 }, labelKey = "INVTYPE_WAIST" },
  { key = "LEGS", slots = { 7 }, labelKey = "INVTYPE_LEGS" },
  { key = "FEET", slots = { 8 }, labelKey = "INVTYPE_FEET" },
  -- Each finger its own group, weighed against the ring worn on it: the HERO tab shows each ring
  -- slot's own choices, and the set fills both (never with one item, BestSet).
  { key = "FINGER1", slots = { 11 }, labelKey = "INVTYPE_FINGER" },
  { key = "FINGER2", slots = { 12 }, labelKey = "INVTYPE_FINGER" },
  { key = "MAINHAND", slots = { 16 }, labelKey = "INVTYPE_WEAPONMAINHAND" },
  { key = "OFFHAND", slots = { 17 }, labelKey = "INVTYPE_WEAPONOFFHAND" },
  { key = "RANGED", slots = { 18 }, labelKey = "INVTYPE_RANGED" },
}

-- equipLoc -> group. Trinkets, relics, shirts, tabards, bags and ammo are not compared: their
-- worth is mostly effects GetItemStats does not list. A piece that goes in either of two slots is a
-- candidate for both (SECOND_OF): a one-hand weapon for the off hand too, the HERO plan's Finding 2
-- (a rogue was never offered one for the off hand), and a ring for the second finger.
local GROUP_OF = {
  INVTYPE_HEAD = "HEAD", INVTYPE_NECK = "NECK", INVTYPE_SHOULDER = "SHOULDER", INVTYPE_CLOAK = "BACK",
  INVTYPE_CHEST = "CHEST", INVTYPE_ROBE = "CHEST", INVTYPE_WRIST = "WRIST", INVTYPE_HAND = "HANDS",
  INVTYPE_WAIST = "WAIST", INVTYPE_LEGS = "LEGS", INVTYPE_FEET = "FEET", INVTYPE_FINGER = "FINGER1",
  INVTYPE_WEAPON = "MAINHAND", INVTYPE_WEAPONMAINHAND = "MAINHAND", INVTYPE_2HWEAPON = "MAINHAND",
  INVTYPE_WEAPONOFFHAND = "OFFHAND", INVTYPE_SHIELD = "OFFHAND", INVTYPE_HOLDABLE = "OFFHAND",
  INVTYPE_RANGED = "RANGED", INVTYPE_RANGEDRIGHT = "RANGED", INVTYPE_THROWN = "RANGED",
}
local SECOND_OF = { INVTYPE_WEAPON = "OFFHAND", INVTYPE_FINGER = "FINGER2" }
-- The groups that fill two slots of one kind, each other's pair: the set never puts one item in
-- both, and a piece only one stronger, cheaper piece beats stays among their set choices, since
-- that one may be in the other slot.
local PAIR_OF = { MAINHAND = "OFFHAND", OFFHAND = "MAINHAND", FINGER1 = "FINGER2", FINGER2 = "FINGER1" }
-- A weapon in the off hand, not a shield or a held item: it needs dual-wield (I1 below).
local OFFHAND_WEAPON = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }

local function set(list)
  local out = {}
  for _, v in ipairs(list) do out[v] = true end
  return out
end

-- Classic's rules: the fallback when the tooltip cannot tell, and for a piece a few levels ahead
-- the judge at the level it will be worn at (TooltipUsable passes over its red level line).
-- Armour subclass -> the level the class may wear it from (0 misc, 1 cloth, 2 leather, 3 mail, 4
-- plate, 6 shield). Weapon subclass -> the class can learn it (0/1 axe, 2 bow, 3 gun, 4/5 mace, 6
-- polearm, 7/8 sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand). A class not
-- listed has no fallback. WoW: Forever lets a rogue use one-hand axes, as Classic does not (Pawn
-- 2.14.4's ScaleTemplates.lua records it); two-hand axes stay out, as every two-hander does.
local ARMOR = {
  WARRIOR = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
  PALADIN = { [0] = 1, [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
  HUNTER = { [0] = 1, [1] = 1, [2] = 1, [3] = 40 },
  SHAMAN = { [0] = 1, [1] = 1, [2] = 1, [3] = 40, [6] = 1 },
  ROGUE = { [0] = 1, [1] = 1, [2] = 1 },
  DRUID = { [0] = 1, [1] = 1, [2] = 1 },
  MAGE = { [0] = 1, [1] = 1 },
  PRIEST = { [0] = 1, [1] = 1 },
  WARLOCK = { [0] = 1, [1] = 1 },
}
local WEAPON = {
  WARRIOR = set({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }),
  PALADIN = set({ 0, 1, 4, 5, 6, 7, 8 }),
  HUNTER = set({ 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }),
  ROGUE = set({ 0, 2, 3, 4, 7, 13, 15, 16, 18 }),
  DRUID = set({ 4, 5, 10, 13, 15 }),
  SHAMAN = set({ 0, 1, 4, 5, 10, 13, 15 }),
  MAGE = set({ 7, 10, 15, 19 }),
  PRIEST = set({ 4, 10, 15, 19 }),
  WARLOCK = set({ 7, 10, 15, 19 }),
}

-- Final review I1: dual-wield is not a red tooltip line (a mage's off-hand dagger tooltip shows
-- white), so it must be checked separately from ClassAllows. The client's own CanDualWield() is
-- authoritative when it exists; the Classic fallback below is only for a client or spec driver
-- that lacks it. Rogues always can; warriors and hunters from level 20; nobody else, a shaman
-- neither, on WoW: Forever as in Classic (Pawn 2.14.4 records the same).
local DUAL_WIELD_FROM = { WARRIOR = 20, HUNTER = 20 }
local function classCanDualWield(classFile, level)
  if classFile == "ROGUE" then return true end
  local from = DUAL_WIELD_FROM[classFile]
  return from ~= nil and (level or 0) >= from
end

function GC.ForeverUpgrades.ClassAllows(classFile, classID, subclassID, level)
  if classID == 4 then
    local t = ARMOR[classFile]
    if not t then return nil end
    local from = t[subclassID]
    return from ~= nil and (level or 0) >= from
  elseif classID == 2 then
    local t = WEAPON[classFile]
    if not t then return nil end
    return t[subclassID] == true
  end
  return false
end

-- Whether the class wants a kind of piece it can wear (ClassAllows says whether it can). A rogue, a
-- warrior or a hunter fights in leather or mail, and cloth (armour subclass 1) is never one of its
-- choices: the owner's rogue was offered cloth robes "of the Tiger", one as GoldCap's pick, over his
-- leather tunic (14.11). A cloak is cloth for every class and stays. Paladins, shamans and druids
-- keep cloth for their caster trees, and the casters wear it.
local NO_CLOTH = { ROGUE = true, WARRIOR = true, HUNTER = true }
function GC.ForeverUpgrades.Wants(classFile, equipLoc, classID, subclassID)
  if classID == 4 and subclassID == 1 and equipLoc ~= "INVTYPE_CLOAK" and NO_CLOTH[classFile] then return false end
  return true
end

-- What a point of weapon DPS is worth in each hand, per class (HERO plan, Finding 3), the hand the
-- class fights with at 1: the off hand swings for half in Classic. A rogue's or warrior's bow, gun,
-- crossbow or thrown weapon only pulls, so its damage counts for nothing and the piece for its
-- stats alone, as GearQuest Forever weighs it (its score.py, 14.11; a seventh until then).
-- Paladins and shamans swing the main hand and shoot nothing (their off hand is a shield or a held
-- piece); a hunter fights with the bow, gun or crossbow, its melee weapon a tenth of that; a mage's,
-- priest's or warlock's weapon DPS is the wand's, a staff's or a dagger's counting for its stats
-- alone; a druid's forms fight without the weapon. A class or a group not listed counts as 1.
GC.ForeverUpgrades.HANDS = {
  ROGUE = { MAINHAND = 1, OFFHAND = 0.5, RANGED = 0 },
  WARRIOR = { MAINHAND = 1, OFFHAND = 0.5, RANGED = 0 },
  PALADIN = { MAINHAND = 1, OFFHAND = 0.5, RANGED = 0 },
  SHAMAN = { MAINHAND = 1, OFFHAND = 0.5, RANGED = 0 },
  HUNTER = { MAINHAND = 0.1, OFFHAND = 0.05, RANGED = 1 },
  MAGE = { MAINHAND = 0, OFFHAND = 0, RANGED = 1 },
  PRIEST = { MAINHAND = 0, OFFHAND = 0, RANGED = 1 },
  WARLOCK = { MAINHAND = 0, OFFHAND = 0, RANGED = 1 },
  DRUID = { MAINHAND = 0, OFFHAND = 0, RANGED = 0 },
}

-- The factor Score puts on a piece's DPS in that group. A class with an ABILITY_EVERY swings its
-- main hand once more with every such ability (Sinister Strike adds a weapon swing), and that swing
-- hits for speed x DPS: per second the main hand then does DPS x (1 + speed / E), so at the same
-- DPS a slower weapon gives more. Scaled to REF_SPEED, so a 2.0 weapon counts as before. A speed
-- the client has not told counts as REF_SPEED.
function GC.ForeverUpgrades.DpsFactor(classFile, group, speed)
  local hands = GC.ForeverUpgrades.HANDS[classFile]
  local f = hands and hands[group] or 1
  local every = C.ABILITY_EVERY[classFile]
  if group == "MAINHAND" and every and type(speed) == "number" and speed > 0 then
    f = f * (1 + speed / every) / (1 + C.REF_SPEED / every)
  end
  return f
end

-- How a rogue uses its main hand: "backstab" wants a dagger there (Backstab needs one), "sinister"
-- takes any weapon it can use. The player's own choice wins (prefs.heroStyle); otherwise the
-- weapon it wears says, a dagger (subclass 15) meaning Backstab. nil for every other class.
function GC.ForeverUpgrades.StyleFor(prefs, classFile, wornMainSubclass)
  if classFile ~= "ROGUE" then return nil end
  local own = type(prefs) == "table" and prefs.heroStyle or nil
  if own == "backstab" or own == "sinister" then return own end
  return wornMainSubclass == 15 and "backstab" or "sinister"
end

-- dpsFactor: DpsFactor's answer for the hand the piece goes in, 1 when not given. Only the DPS
-- token's share is scaled; parts stay the piece's own numbers, for Diff and the words on screen,
-- but a DPS that counts for nothing in that hand (a priest's staff) is not among them.
function GC.ForeverUpgrades.Score(stats, weights, dpsFactor)
  local score, parts = 0, {}
  if type(stats) ~= "table" then return score, parts end
  local dps = tonumber(dpsFactor) or 1
  for token, w in pairs(weights or {}) do
    local keys = GC.ForeverUpgrades.TOKENS[token]
    local f = token == "DPS" and dps or 1
    if keys and type(w) == "number" and w ~= 0 and f ~= 0 then
      for _, key in ipairs(keys) do
        local v = stats[key]
        if type(v) == "number" then
          score = score + w * v * f
          parts[key] = (parts[key] or 0) + v
        end
      end
    end
  end
  return score, parts
end

-- Whether a piece's stats carry weapon DPS: the only share a weapon's speed scales (DpsFactor).
local function hasDps(stats)
  for _, key in ipairs(GC.ForeverUpgrades.TOKENS.DPS) do
    local v = stats[key]
    if type(v) == "number" and v ~= 0 then return true end
  end
  return false
end

function GC.ForeverUpgrades.Diff(parts, base)
  local out = {}
  for key, v in pairs(parts or {}) do out[key] = v - ((base or {})[key] or 0) end
  for key, v in pairs(base or {}) do
    if out[key] == nil then out[key] = -v end
  end
  for key, v in pairs(out) do
    if v == 0 then out[key] = nil end
  end
  return out
end

local function signed(v)
  if v == math.floor(v) then return ("%+d"):format(v) end
  return ("%+.1f"):format(v)
end

-- A diff in words, part by part in TOKEN_ORDER: { text = "+3 Strength", loss = the stat goes down,
-- token }, for a caller that colours a loss or leaves some tokens out (the HERO tab, the tooltip).
function GC.ForeverUpgrades.DiffParts(diffs)
  local parts = {}
  for _, token in ipairs(GC.ForeverUpgrades.TOKEN_ORDER) do
    for _, key in ipairs(GC.ForeverUpgrades.TOKENS[token]) do
      local v = (diffs or {})[key]
      if v then parts[#parts + 1] = { text = ("%s %s"):format(signed(v), _G[key] or token), loss = v < 0, token = token } end
    end
  end
  return parts
end

local function isRed(c)
  return type(c) == "table" and (c.r or 0) > 0.9 and (c.g or 1) < 0.25 and (c.b or 1) < 0.25
end

-- A client string as a Lua pattern that matches it literally.
local function literal(text)
  return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- The tooltip's own text for a line, turned into a pattern: every "%d" (or "%1$d") a number, the
-- rest literal. nil without the client's string, or with one that holds no number.
local function formatPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local out, pos, numbers = {}, 1, 0
  while true do
    local from, to = fmt:find("%%%d*%$?d", pos)
    if not from then break end
    out[#out + 1] = literal(fmt:sub(pos, from - 1))
    out[#out + 1] = "%d+"
    numbers, pos = numbers + 1, to + 1
  end
  if numbers == 0 then return nil end
  out[#out + 1] = literal(fmt:sub(pos))
  return "^" .. table.concat(out) .. "$"
end

-- The client's tooltip for a link or an item string, as data, or nil.
local function tooltipLines(itemString, api)
  if api == nil then api = _G.C_TooltipInfo end
  if type(api) ~= "table" or type(api.GetHyperlink) ~= "function" then return nil end
  local ok, data = pcall(api.GetHyperlink, itemString)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  return data.lines
end

-- A weapon's speed, from its tooltip's damage line: the right text is the client's SPEED and the
-- seconds (HERO probe P4, 13.11: "Speed 1.50" on worn Hook Daggers, "Speed 1.80" on Jagged
-- Knives). A comma reads as the decimal point, as some languages write it. nil for a piece with no
-- such line, a tooltip not answered, or a client without the string. Works on a full link too (the
-- probe read the worn weapons' tooltips by their links). The second value says the tooltip itself
-- had loaded (a name on its first line, not the client's "retrieving" text): a nil speed from a
-- loaded tooltip will not change on a second read, and the driver keeps it as the reference speed
-- rather than reading the same tooltip again on every build.
function GC.ForeverUpgrades.TooltipSpeed(itemString, api)
  local word = _G.SPEED
  if type(word) ~= "string" or word == "" then return nil end
  local lines = tooltipLines(itemString, api)
  if not lines then return nil end
  local pattern = "^" .. literal(word) .. "%s*([%d%.,]+)$"
  for _, line in ipairs(lines) do
    local text = type(line) == "table" and line.rightText or nil
    local n = type(text) == "string" and text:match(pattern) or nil
    if n then
      local v = tonumber((n:gsub(",", ".")))
      if v and v > 0 then return v, true end
    end
  end
  local first = type(lines[1]) == "table" and lines[1].leftText or nil
  local loading = _G.RETRIEVING_ITEM_INFO
  return nil, type(first) == "string" and first ~= "" and first ~= loading
end

-- The client's tooltip for the piece, as data: false on any red line, true when it drew coloured
-- lines and none was red, nil when it cannot tell (no client call, nothing loaded, still loading,
-- no colours). One red line is not a "no": the level the piece requires, which the client draws red until the
-- character reaches it (HERO probe P5, 13.11: Feet of the Lynx at level 17, "Requires Level 19" in
-- 1.00/0.13/0.13, line type 43). Every level-ahead piece used to fail here, so the "at level N"
-- picks never showed. Type 43 is every usage requirement, class and skill included, so the line is
-- known by its text, the client's ITEM_MIN_LEVEL, never by its type.
function GC.ForeverUpgrades.TooltipUsable(itemString, api)
  local lines = tooltipLines(itemString, api)
  if not lines then return nil end
  -- A tooltip still loading says so in red (the client's RETRIEVING_ITEM_INFO, which Blizzard's
  -- own frames draw in RED_FONT_COLOR): that is "cannot tell", never a "no" to keep for the session.
  local loading = _G.RETRIEVING_ITEM_INFO
  if type(loading) == "string" and loading ~= "" then
    for _, line in ipairs(lines) do
      if type(line) == "table" and (line.leftText == loading or line.rightText == loading) then return nil end
    end
  end
  local levelLine = formatPattern(_G.ITEM_MIN_LEVEL)
  local sawColour = false
  for _, line in ipairs(lines) do
    if type(line) == "table" then
      if line.leftColor or line.rightColor then sawColour = true end
      local leftRed = isRed(line.leftColor)
      if leftRed and levelLine and type(line.leftText) == "string" and line.leftText:match(levelLine) then
        leftRed = false
      end
      if leftRed or isRed(line.rightColor) then return false end
    end
  end
  return sawColour or nil
end

local SLOT_OF, GROUP_AT = {}, {}
for _, g in ipairs(GC.ForeverUpgrades.GROUPS) do
  SLOT_OF[g.key] = g.slots[1]
  for _, slot in ipairs(g.slots) do GROUP_AT[slot] = g.key end
end

local function itemIdOf(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function merged(a, b)
  local out = {}
  for k, v in pairs(a or {}) do out[k] = v end
  for k, v in pairs(b or {}) do out[k] = (out[k] or 0) + v end
  return out
end

-- The character's damage per second, as the game counts it (owner, 14.11: "count DPS" instead of
-- making the player add up -4 Agility and +14 Attack Power). For the classes that fight with their
-- weapons; a caster's or a druid's damage is not its weapon's, and it keeps its weights.
local NO_MODEL = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true }
-- The tokens the model counts: on screen a piece's DPS figure stands for them. PER_ORDER: those it
-- prices a point of (per), in one order, so each build sums them the same way.
GC.ForeverUpgrades.MODELLED = { STR = true, AGI = true, AP = true, DPS = true }
local PER_ORDER = { "STR", "AGI", "AP" }

-- The white part of DpsFactor in `group`: the hand's own swings, without those an ABILITY_EVERY
-- adds, at REF_SPEED's scale (the two parts of a 2.0 weapon still make 1). All of it for a class
-- without one.
local function whiteFactor(classFile, group)
  local hands = GC.ForeverUpgrades.HANDS[classFile]
  local f = hands and hands[group] or 1
  local every = group == "MAINHAND" and C.ABILITY_EVERY[classFile] or nil
  if every then return f / (1 + C.REF_SPEED / every) end
  return f
end

-- What the character does per second before crits, for attack power ap and ranged attack power
-- rap, with weapons of mh DPS in the main hand (0 bare: it still hits) at mhSpeed, and of oh and r
-- DPS in the off hand and the ranged slot (nil: none there, that hand does nothing). Each hand hits
-- for its weapon's DPS and one more for every AP_PER_DPS attack power, in its DpsFactor; while a
-- weapon swings in the off hand, both hands' white hits keep DUAL_WIELD_WHITE of their damage.
-- Its other return values: the factor each hand hit for, main hand, off hand and ranged slot.
local function baseOf(classFile, ap, rap, mh, mhSpeed, oh, r)
  local DpsFactor, M = GC.ForeverUpgrades.DpsFactor, C.AP_PER_DPS
  local hands = GC.ForeverUpgrades.HANDS[classFile]
  local hMH = DpsFactor(classFile, "MAINHAND", mhSpeed)
  local hOH = 0
  if oh then
    hMH = hMH - (1 - C.DUAL_WIELD_WHITE) * whiteFactor(classFile, "MAINHAND")
    hOH = DpsFactor(classFile, "OFFHAND") * C.DUAL_WIELD_WHITE
  end
  local hR = r and (hands and hands.RANGED or 0) or 0
  return hMH * (mh + ap / M) + hOH * ((oh or 0) + ap / M) + hR * ((r or 0) + rap / M), hMH, hOH, hR
end

-- classFile's DPS model from char (the driver's char(): attack power, ranged attack power, crit as a
-- fraction, and what one more point of a stat adds to each, read from the client) and the weapons
-- worn ({ MAINHAND = { dps, speed }, OFFHAND = { dps }, RANGED = { dps } }, the off hand only for a
-- weapon there), or nil for a class above or a char missing a number:
--   base: what the character does per second now, before crits (baseOf); a crit doubles a hit, so
--         its DPS is base (1 + crit)
--   per.AP = (hMH + hOH + hR') / 14 (1 + crit): Classic's attack power on gear is melee and ranged
--   per.STR, per.AGI: the attack power the game says a point gives, in the hands it reaches, and
--   for agility the crit a point gives times base
--   char, worn: the numbers it was made from, for what a piece changes (swapDps)
-- per is what one more point adds, at baseOf's hand factors, for the weights the window shows
-- (WeightsFor); a piece's own figure is counted whole (swapDps). hR' is hR, or for a class that
-- fights with the ranged hand (a hunter, HANDS' RANGED 1) that hand's whole factor even with
-- nothing in it: its agility is its ranged attack power, between bows too.
-- K is the class's default DPS weight, the points one DPS is worth on the scale every other weight
-- sits on (WeightsFor).
function GC.ForeverUpgrades.DpsModel(classFile, char, worn)
  if type(char) ~= "table" or NO_MODEL[classFile] then return nil end
  local defaults, hands = GC.ForeverUpgrades.DEFAULT_WEIGHTS[classFile], GC.ForeverUpgrades.HANDS[classFile]
  local K = defaults and tonumber(defaults.DPS)
  if not (hands and K and K > 0) then return nil end
  local function num(t, k) return type(t) == "table" and type(t[k]) == "number" and t[k] or nil end
  local ap, rap, c = num(char, "ap"), num(char, "rap"), num(char, "crit")
  local apSTR, apAGI = num(char.apPer, "STR"), num(char.apPer, "AGI")
  local rapAGI, critAGI = num(char.rapPer, "AGI"), num(char.critPer, "AGI")
  if not (ap and rap and c and apSTR and apAGI and rapAGI and critAGI) then return nil end
  worn = type(worn) == "table" and worn or {}
  local function dpsAt(group) return worn[group] and (num(worn[group], "dps") or 0) or nil end
  local mh, mhSpeed, oh, r = dpsAt("MAINHAND") or 0, num(worn.MAINHAND, "speed"), dpsAt("OFFHAND"), dpsAt("RANGED")
  local base, hMH, hOH, hR = baseOf(classFile, ap, rap, mh, mhSpeed, oh, r)
  local M = C.AP_PER_DPS
  local melee = hMH + hOH
  local hRper = (hands.RANGED or 0) >= 1 and hands.RANGED or hR
  return {
    K = K, crit = c, base = base, class = classFile,
    per = {
      AP = (melee + hRper) / M * (1 + c),
      STR = apSTR * melee / M * (1 + c),
      AGI = (apAGI * melee + rapAGI * hRper) / M * (1 + c) + critAGI * base,
    },
    char = { ap = ap, rap = rap, apSTR = apSTR, apAGI = apAGI, rapAGI = rapAGI, critAGI = critAGI },
    worn = { mh = mh, mhSpeed = mhSpeed, oh = oh, r = r },
  }
end

-- A token's numbers in a piece's stats, summed (0 for none).
local function statOf(stats, token)
  local v = 0
  for _, key in ipairs(GC.ForeverUpgrades.TOKENS[token]) do
    local n = stats[key]
    if type(n) == "number" then v = v + n end
  end
  return v
end

-- What wearing a piece with `stats` (an `equipLoc`) in `group` (at `speed`) instead of the pieces
-- whose stats are in `off` (the one it replaces; both hands, for a two-hander over a pair; none for
-- an empty slot) changes the model's DPS by: the character's DPS after, less its DPS now, each
-- base (1 + crit). After, its attack power, ranged attack power and crit move by what the stats
-- given and taken off add to each (char's apPer, rapPer, critPer), and the piece swings in its
-- hand: a two-hander empties the off hand, a shield or a held piece leaves it without a swing, any
-- piece not for a hand leaves the weapons as they are. Counted whole, never a point at a time: a
-- two-hander's strength reaches one hand, not the two its per counted (review, 14.11). A main hand
-- whose speed is not known (speed nil) swings at the worn one's: its speed counts once it is read.
local function swapDps(model, stats, group, speed, equipLoc, off)
  local dSTR, dAGI, dAP = statOf(stats, "STR"), statOf(stats, "AGI"), statOf(stats, "AP")
  for _, st in ipairs(off) do
    dSTR, dAGI, dAP = dSTR - statOf(st, "STR"), dAGI - statOf(st, "AGI"), dAP - statOf(st, "AP")
  end
  local w, ch = model.worn, model.char
  local mh, mhSpeed, oh, r = w.mh, w.mhSpeed, w.oh, w.r
  if group == "MAINHAND" then
    mh, mhSpeed = statOf(stats, "DPS"), speed or w.mhSpeed
    if equipLoc == "INVTYPE_2HWEAPON" then oh = nil end
  elseif group == "OFFHAND" then
    oh = OFFHAND_WEAPON[equipLoc] and statOf(stats, "DPS") or nil
  elseif group == "RANGED" then
    r = statOf(stats, "DPS")
  end
  local ap = ch.ap + dAP + dSTR * ch.apSTR + dAGI * ch.apAGI
  local rap = ch.rap + dAP + dAGI * ch.rapAGI
  local c = model.crit + dAGI * ch.critAGI
  return baseOf(model.class, ap, rap, mh, mhSpeed, oh, r) * (1 + c) - model.base * (1 + model.crit)
end

-- The stats the model counts on a piece in `group` ({ key = n }, none zero): its strength, agility
-- and attack power, and its weapon DPS where that hand weighs something (DpsFactor).
local COUNTED = { "STR", "AGI", "AP", "DPS" }
local function modelledOf(classFile, stats, group)
  local out = {}
  for _, token in ipairs(COUNTED) do
    if token ~= "DPS" or GC.ForeverUpgrades.DpsFactor(classFile, group) ~= 0 then
      for _, key in ipairs(GC.ForeverUpgrades.TOKENS[token]) do
        local n = stats[key]
        if type(n) == "number" and n ~= 0 then out[key] = n end
      end
    end
  end
  return out
end

-- A change in DPS as the HERO tab and the tooltip write it: signed, to one decimal, and "0.0" for
-- less than 0.05 either way; and its sign (1, -1 or 0).
function GC.ForeverUpgrades.DpsFigure(v)
  if type(v) ~= "number" or math.abs(v) < 0.05 then return "0.0", 0 end
  return ("%+.1f"):format(v), v > 0 and 1 or -1
end

-- The model from a driver: its char() and the weapons it wears, the main hand's speed (for a class
-- whose main hand counts it) as the driver keeps it; `read`: one tooltip read when it keeps none,
-- never inside a tooltip. nil without char(), for a class with no model, or when char() says nil.
function GC.ForeverUpgrades.ModelFor(driver, classFile, read)
  if type(driver) ~= "table" or type(driver.char) ~= "function" or NO_MODEL[classFile] then return nil end
  local ok, char = pcall(driver.char)
  if not (ok and type(char) == "table") then return nil end
  local worn = {}
  for _, group in ipairs({ "MAINHAND", "OFFHAND", "RANGED" }) do
    local link = driver.equipped(SLOT_OF[group])
    local id = itemIdOf(link)
    if id and (group ~= "OFFHAND" or OFFHAND_WEAPON[(driver.instant(id))]) then
      local stats = driver.stats(link)
      local speed
      if group == "MAINHAND" and C.ABILITY_EVERY[classFile] and type(driver.speed) == "function" then
        local v = driver.speed(id, read == true)
        speed = type(v) == "number" and v > 0 and v or nil
      end
      worn[group] = { dps = type(stats) == "table" and tonumber(stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT) or 0,
        speed = speed }
    end
  end
  return GC.ForeverUpgrades.DpsModel(classFile, char, worn)
end

-- The weights WeightsFor set from a DPS model, as keys: never a table of the player's own, nor the
-- copy a typed weight goes into (ApplyWeights), which ranks by its numbers.
local DERIVED = setmetatable({}, { __mode = "k" })

-- The character's side of every comparison, for Build and TooltipVerdict alike, so an item's
-- tooltip never says what the HERO tab does not: what it wears per slot, scored in that slot's
-- hand; the piece a candidate replaces (the ring on that finger; both hands, for a two-hander while
-- a one-hander is worn); which kinds of piece a group takes; and how much more a piece must score.
-- wornSpeed(itemID): the worn main hand's speed, or nil (REF_SPEED); a main-hand candidate's speed
-- not read yet is that one too, so speed counts nothing until it is known. loading: where the ids
-- of worn pieces whose stats have not answered go. model: the character's DPS model (DpsModel), or
-- nil. With weights set from it (WeightsFor), a candidate gains K times the DPS it adds over what
-- it replaces (swapDps) and the other stats' worth; with weights of the player's own, the weighted
-- sum as before the model, its DPS said all the same (bench.dps).
local function newBench(driver, weights, class, level, style, wornSpeed, loading, model)
  local Score, DpsFactor = GC.ForeverUpgrades.Score, GC.ForeverUpgrades.DpsFactor
  local bench = {}
  local topPrimary = 0
  for _, token in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do
    local w = weights[token]
    if type(w) == "number" and w > topPrimary then topPrimary = w end
  end
  local minGain = C.MIN_GAIN_POINTS * topPrimary

  -- The weights of the stats the model does not count, with weights set from the model; nil otherwise.
  local rest
  if model and DERIVED[weights] then
    rest = {}
    for token, w in pairs(weights) do
      if not GC.ForeverUpgrades.MODELLED[token] then rest[token] = w end
    end
  end

  -- What the character wears, per slot, scored in that slot's hand. false: worn, but its stats not
  -- answered yet -- the group is skipped rather than compared against a guess.
  local worn = {}
  local function wornAt(slot)
    if worn[slot] == nil then
      local link = driver.equipped(slot)
      local group = GROUP_AT[slot]
      if not link then
        worn[slot] = { score = 0, parts = {}, stats = {}, group = group }
      else
        local stats = driver.stats(link)
        if stats == nil then
          worn[slot] = false
          local id = itemIdOf(link)
          if id then loading[id] = true end
        else
          local speed = group == "MAINHAND" and wornSpeed and wornSpeed(itemIdOf(link)) or nil
          local s, p = Score(stats, weights, DpsFactor(class, group, speed))
          worn[slot] = { score = s, parts = p, link = link, stats = stats, group = group, speed = speed }
        end
      end
    end
    return worn[slot]
  end
  local twoHandWorn = driver.instant(itemIdOf(driver.equipped(16)) or 0) == "INVTYPE_2HWEAPON"

  local dualWield
  local function canDualWield()
    if dualWield == nil then
      if type(driver.canDualWield) == "function" then
        local ok, v = pcall(driver.canDualWield)
        if ok and type(v) == "boolean" then
          dualWield = v
        else
          dualWield = classCanDualWield(class, level)
        end
      else
        dualWield = classCanDualWield(class, level)
      end
    end
    return dualWield
  end

  local function base(group, equipLoc)
    if group == "MAINHAND" and equipLoc == "INVTYPE_2HWEAPON" and not twoHandWorn then
      local m, o = wornAt(16), wornAt(17)
      if not (m and o) then return nil end
      return { score = m.score + o.score, parts = merged(m.parts, o.parts), link = m.link, pair = { m, o } }
    end
    return wornAt(SLOT_OF[group]) or nil
  end

  -- Whether a kind of piece goes in the group at all, before any lot of it is read: one the class
  -- wants (Wants), and in the off hand and a Backstab rogue's main hand one that hand takes. Only
  -- for a candidate: what is worn is weighed against whatever it is.
  local function wanted(group, equipLoc, classID, subclassID)
    if not GC.ForeverUpgrades.Wants(class, equipLoc, classID, subclassID) then return false end
    if group == "OFFHAND" then
      -- Under a two-hander there is no off hand to fill. I1 (final review): an off-hand WEAPON (not
      -- a shield or a held item) needs dual-wield, which is not a red tooltip line -- ClassAllows
      -- alone would offer a mage an off-hand dagger it cannot equip. With nothing in the main hand,
      -- a weapon goes there first: no off-hand weapon is offered, nor put in the set (review,
      -- 14.11: the set put the only sword in the off hand). With the DPS model, so a build without
      -- the character's numbers reads as before it.
      if OFFHAND_WEAPON[equipLoc] and model and not driver.equipped(16) then return false end
      return not twoHandWorn and not (OFFHAND_WEAPON[equipLoc] and not canDualWield())
    end
    if group == "MAINHAND" and style == "backstab" then return classID == 2 and subclassID == 15 end
    return true
  end

  -- A candidate's speed in `group` for its score: its own, or in the main hand while it is not read
  -- the worn main hand's (nil, REF_SPEED, with nothing there or its speed not read either), as the
  -- model's figure does with its own (swapDps). Review, 14.11: at REF_SPEED a worn 1.5 dagger
  -- credited every weapon not read yet with 7.7% of its DPS.
  local function speedIn(group, speed)
    if speed or group ~= "MAINHAND" then return speed end
    local w = wornAt(16)
    return w and w.speed or nil
  end

  -- The gain over b that makes an upgrade, or nil: a score above nothing, gaining (gain: score less
  -- b's, unless the caller says) at least MIN_GAIN_SHARE of b's score and minGain.
  local function beats(score, b, gain)
    gain = gain or score - b.score
    if score > 0 and gain > 0 and gain >= math.max(C.MIN_GAIN_SHARE * b.score, minGain) then return gain end
    return nil
  end

  -- The stats of what a candidate takes off: b's, both hands' for a pair.
  local function offOf(b)
    local off = {}
    for _, w in ipairs(b.pair or { b }) do off[#off + 1] = w.stats end
    return off
  end

  -- A candidate with `stats` (an `equipLoc`) in `group` (at `speed`) over b, base()'s answer: its
  -- score (Score, its DPS in the hand's DpsFactor), its parts, and what it gains over b. With weights
  -- set from the model, that gain is K times the DPS it adds (swapDps) and what the stats the model
  -- does not count add at their weights; otherwise its score less b's. For Build and the tooltip.
  local function over(stats, group, equipLoc, speed, b)
    local s, p = Score(stats, weights, DpsFactor(class, group, speedIn(group, speed)))
    if not rest then return s, p, s - b.score end
    local gain = model.K * swapDps(model, stats, group, speed, equipLoc, offOf(b)) + (Score(stats, rest))
    for _, w in ipairs(b.pair or { b }) do gain = gain - (Score(w.stats, rest)) end
    return s, p, gain
  end

  -- What a candidate adds to the character's DPS over b by the model (swapDps), and the stats the
  -- model counted on each side, as a diff (Diff). nil without a model, and when neither side has a
  -- stat the model counts. From the stats themselves, not Score's parts: a player's own weights
  -- without attack power still see what it adds.
  local function dps(stats, group, equipLoc, speed, b)
    if not model then return nil end
    local mine, theirs = modelledOf(class, stats, group), {}
    for _, w in ipairs(b.pair or { b }) do theirs = merged(theirs, modelledOf(class, w.stats, w.group)) end
    if next(mine) == nil and next(theirs) == nil then return nil end
    return swapDps(model, stats, group, speed, equipLoc, offOf(b)), GC.ForeverUpgrades.Diff(mine, theirs)
  end

  bench.wornAt, bench.base, bench.wanted, bench.beats, bench.dps = wornAt, base, wanted, beats, dps
  bench.over = over
  bench.twoHandWorn = twoHandWorn
  return bench
end

local function byCost(a, b)
  if a.cost ~= b.cost then return a.cost < b.cost end
  if a.gain ~= b.gain then return a.gain > b.gain end
  return a.seq < b.seq
end

-- The entries no cheaper one matches in gain, cheapest first; on a tie in both, the one made first.
local function paretoFront(list)
  table.sort(list, byCost)
  local out = {}
  for _, e in ipairs(list) do
    if #out == 0 or e.gain > out[#out].gain then out[#out + 1] = e end
  end
  return out
end

-- At most `cap` of a front's states, spread evenly over it by index: always its cheapest (the
-- empty set, which every later group builds on) and its strongest. Keeping only the cheapest made
-- a rich character's set spend less than it could: every partial set that had bought the dearer
-- pieces was gone before the last groups were weighed.
local function thinned(front, cap)
  local n = #front
  cap = math.max(2, math.floor(tonumber(cap) or 2))
  if n <= cap then return front end
  local out = {}
  for j = 1, cap do
    out[j] = front[math.floor(1 + (j - 1) * (n - 1) / (cap - 1) + 0.5)]
  end
  return out
end

-- The strongest set the gold carried pays for (HERO plan, 2026-11-13): at most one piece per group,
-- the most gain whose prices add up to no more than money. options[group]: the group's choices, as
-- Build makes them (itemID, unit, gain, diffs, itemString, twoHand). The two hands are one step:
-- nothing, either hand alone, both, or a two-hander alone; the two fingers too, either or both.
-- Never one item in both slots of a pair: one lot cannot fill two, and a BUY line buys one version
-- of an item at a time (GC.ForeverUpgrades.ListAdd), so two versions of it could not both be bought. A multiple-choice knapsack over Pareto states: after each group only the
-- partial sets no cheaper one matches in gain are kept, SET_STATES of them at most (thinned).
-- nil without a money read; otherwise { picks = { [group] = cand }, list (the picks in GROUPS
-- order), cost, gain, left = money - cost, diffs (the picks' summed) }.
function GC.ForeverUpgrades.BestSet(options, money)
  money = tonumber(money)
  if money == nil then return nil end
  if type(options) ~= "table" then options = {} end
  local steps = {}
  for _, g in ipairs(GC.ForeverUpgrades.GROUPS) do
    local raw = {}
    local function offer(...)
      local cands, cost, gain = { ... }, 0, 0
      for _, c in ipairs(cands) do cost, gain = cost + c.unit, gain + c.gain end
      if cost <= money then raw[#raw + 1] = { cost = cost, gain = gain, seq = #raw + 1, cands = cands } end
    end
    if g.key == "MAINHAND" or g.key == "FINGER1" then
      local seconds = options[PAIR_OF[g.key]] or {}
      for _, m in ipairs(options[g.key] or {}) do
        offer(m)
        if not m.twoHand then
          for _, o in ipairs(seconds) do
            if o.itemID ~= m.itemID then offer(m, o) end
          end
        end
      end
      for _, o in ipairs(seconds) do offer(o) end
    elseif g.key ~= "OFFHAND" and g.key ~= "FINGER2" then
      for _, c in ipairs(options[g.key] or {}) do offer(c) end
    end
    -- A choice another one of the group beats for no more gold is never part of the best set.
    if #raw > 0 then steps[#steps + 1] = paretoFront(raw) end
  end

  local seq = 0
  local states = { { cost = 0, gain = 0, seq = 0 } }
  for _, choices in ipairs(steps) do
    local grown = {}
    for _, st in ipairs(states) do
      grown[#grown + 1] = st
      for _, ch in ipairs(choices) do
        local cost = st.cost + ch.cost
        if cost <= money then
          seq = seq + 1
          grown[#grown + 1] = { cost = cost, gain = st.gain + ch.gain, seq = seq, up = st, take = ch.cands }
        end
      end
    end
    states = thinned(paretoFront(grown), C.SET_STATES)
  end

  -- The front's gain only grows with its cost: its last state is the strongest, and the cheapest
  -- of the strongest.
  local top = states[#states]
  local picks, st = {}, top
  while st.up do
    for _, c in ipairs(st.take) do picks[c.group] = c end
    st = st.up
  end
  local list, diffs = {}, {}
  for _, g in ipairs(GC.ForeverUpgrades.GROUPS) do
    local c = picks[g.key]
    if c then
      list[#list + 1] = c
      for k, v in pairs(c.diffs or {}) do diffs[k] = (diffs[k] or 0) + v end
    end
  end
  for k, v in pairs(diffs) do
    if v == 0 then diffs[k] = nil end
  end
  return { picks = picks, list = list, cost = top.cost, gain = top.gain, left = money - top.cost, diffs = diffs }
end

-- skipUsable (final review 2026-09-27): the count-only path (the upgrades window is closed, so
-- nothing will render its rows) skips driver.usable's tooltip read entirely -- up to ~140
-- C_TooltipInfo.GetHyperlink calls, the priciest primitive here -- and picks straight off
-- known, the same class armour/weapon table and CanDualWield check every candidate already passed
-- to reach byGroup. The window's own render always passes false (the default): a picked row must
-- still clear the tooltip's red-line check, exactly as before. Nor does it read a weapon's speed,
-- a tooltip read too: every weapon there swings at the worn main hand's speed, or REF_SPEED.
--
-- opts.style: StyleFor's answer. "backstab" keeps the main hand to daggers; nil filters nothing.
--
-- The answer: { slots, set, loading, loadingIds, stale?, waiting?, noWeights?, noScan? }
--   slots[i]     in GROUPS order, only the groups with a pick: { group, labelKey, best, alts, worn,
--                invSlot }, worn the link of the piece the slot is weighed against, or nil, and
--                invSlot that piece's inventory slot (11 and 12 for the two fingers).
--   a candidate  { group, itemID, itemString, link, unit, gain, diffs, later, overGold, inSet,
--                version, twoHand }: version the lot's bonus (nil for a lot saved without one),
--                overGold true when the gold carried is below unit, twoHand for INVTYPE_2HWEAPON.
--   set          BestSet's answer, its picks marked inSet; nil without a money read, and on the
--                count-only path, which only counts slots.
--   speedPending the main-hand items (the worn one included) still without a speed after this
--                build's SPEED_READS, each weighed at the worn main hand's speed (the worn one at
--                REF_SPEED) until a later build reads it; absent when there are none.
--   stale        gear saved before suffix versions (v1): every version there reads as its base.
--   waiting      { [group] = true } for each group with a piece to weigh that a worn piece's
--                unanswered stats left unweighed; the group is not in slots until a later build
--                reads it. Its ids are among loadingIds. Absent when none.
function GC.ForeverUpgrades.Build(gear, driver, weights, skipUsable, opts)
  local out = { slots = {}, loading = 0 }
  if type(weights) ~= "table" or next(weights) == nil then out.noWeights = true; return out end
  if type(gear) ~= "table" or type(gear.items) ~= "table" then out.noScan = true; return out end
  if type(gear.v) == "number" and gear.v < 2 then out.stale = true end
  local style = type(opts) == "table" and opts.style or nil
  local model = type(opts) == "table" and opts.model or nil
  local level = tonumber(driver.level()) or 1
  local class = driver.classFile()
  local loading = {}

  -- A weapon's speed, only where it changes the score: the main hand of a class with an
  -- ABILITY_EVERY, under weights that count DPS. Never on the count-only path. nil: not read (the
  -- worn main hand's at REF_SPEED, a candidate at the worn one's).
  local readSpeed = not skipUsable and C.ABILITY_EVERY[class] ~= nil and type(driver.speed) == "function"
    and type(weights.DPS) == "number" and weights.DPS ~= 0
  -- Per item, never per version: a random suffix changes a weapon's stats and damage, not its
  -- speed. driver.speed(itemID, false) is what the driver already knows, never a tooltip read;
  -- (itemID, true) reads one when it knows none. read: this caller needs the speed, and may spend
  -- one of the build's SPEED_READS on it, once per item; an item past them scores at the worn main
  -- hand's speed this build and counts in speedPending.
  local speeds, speedAsked, speedReads, speedWanted = {}, {}, 0, {}
  local function speedOfItem(itemID, read)
    if not (readSpeed and itemID) then return nil end
    if speeds[itemID] == nil then
      local v = driver.speed(itemID, false)
      speeds[itemID] = type(v) == "number" and v > 0 and v or false
    end
    if read then
      speedWanted[itemID] = true
      if speeds[itemID] == false and not speedAsked[itemID] and speedReads < C.SPEED_READS then
        speedAsked[itemID], speedReads = true, speedReads + 1
        local v = driver.speed(itemID, true)
        if type(v) == "number" and v > 0 then speeds[itemID] = v end
      end
    end
    return speeds[itemID] or nil
  end

  -- What the character wears and what each candidate replaces (newBench). The worn main hand's
  -- speed comes first among the build's reads: every main-hand candidate is weighed against it.
  -- opts.model: the character's DPS model (ModelFor), for each choice's `dps`.
  local bench = newBench(driver, weights, class, level, style, function(id) return speedOfItem(id, true) end,
    loading, model)
  local wornAt, base, wanted, beats, dpsOver = bench.wornAt, bench.base, bench.wanted, bench.beats, bench.dps
  local over = bench.over

  -- Usable, per item string and build: one sword is the same piece in either hand. known: the class
  -- armour/weapon table said yes. usable: true only on that "yes" (skipUsable) or a tooltip check
  -- that agrees (or cannot tell, deferring to known) -- unchanged from before the skipUsable path.
  local knownOf, usableOf = {}, {}
  local function usableCandidate(c)
    local s = c.itemString
    if skipUsable then return knownOf[s] == true end
    if usableOf[s] == nil then
      local u = driver.usable(s)
      usableOf[s] = u == true or (u == nil and knownOf[s] == true)
    end
    return usableOf[s]
  end

  -- The gold the character carries: a piece dearer than that is still shown, marked overGold. nil
  -- (a driver with no money read) marks none.
  local money = type(driver.money) == "function" and tonumber(driver.money()) or nil

  -- waiting: the groups a piece could not be weighed in because a worn piece there (or the off hand
  -- under a two-hander's weighing) has not answered: base() has nothing to weigh it by. dps: what
  -- the piece adds to the character's DPS over what it replaces (bench.dps), whatever weights
  -- ranked it; nil without a model or a stat the model counts.
  local byGroup, waiting = {}, {}
  local function consider(group, itemID, equipLoc, lot, str, link, stats, minLevel, speed)
    local b = base(group, equipLoc)
    if not b then
      waiting[group] = true
      return
    end
    local score, parts, raw = over(stats, group, equipLoc, speed, b)
    local gain = beats(score, b, raw)
    if gain then
      byGroup[group] = byGroup[group] or {}
      table.insert(byGroup[group], { group = group, itemID = itemID, itemString = str, link = link or str,
        unit = lot.unit, gain = gain, diffs = GC.ForeverUpgrades.Diff(parts, b.parts),
        later = minLevel > level and minLevel or nil, overGold = money ~= nil and money < lot.unit,
        inSet = false, version = lot.bonus, twoHand = equipLoc == "INVTYPE_2HWEAPON",
        dps = dpsOver(stats, group, equipLoc, speed, b) })
    end
  end

  -- Main-hand lots wait until the build knows which speeds to read (below), when speeds count.
  local mainLots = {}
  for itemID, encoded in pairs(gear.items) do
    local equipLoc, classID, subclassID = driver.instant(itemID)
    local first = GROUP_OF[equipLoc]
    local second = SECOND_OF[equipLoc]
    if first and not wanted(first, equipLoc, classID, subclassID) then first = nil end
    if second and not wanted(second, equipLoc, classID, subclassID) then second = nil end
    if first or second then
      for _, lot in ipairs(GC.ForeverGear.Decode(encoded)) do
        local str = GC.ForeverGear.ItemString(itemID, lot)
        local minLevel, link = driver.info(str)
        if minLevel == nil then
          loading[itemID] = true
        elseif minLevel <= level + C.LEVEL_AHEAD then
          local allowed = GC.ForeverUpgrades.ClassAllows(class, classID, subclassID, math.max(level, minLevel))
          if allowed ~= false then
            local stats = driver.stats(str)
            if stats == nil then
              loading[itemID] = true
            else
              knownOf[str] = allowed == true
              if first == "MAINHAND" and readSpeed then
                mainLots[#mainLots + 1] = { itemID, equipLoc, lot, str, link, stats, minLevel }
              elseif first then
                consider(first, itemID, equipLoc, lot, str, link, stats, minLevel)
              end
              if second then consider(second, itemID, equipLoc, lot, str, link, stats, minLevel) end
            end
          end
        end
      end
    end
  end

  -- The main hand's speeds, strongest item first: each item's strongest version, weighed at the
  -- worn main hand's speed against what it replaces, ties on the itemID, so the picks that matter
  -- settle in the first builds. A piece with no DPS has no use for its speed. Then every main-hand
  -- lot, with the speed now known or none.
  if #mainLots > 0 then
    local gainOf, order = {}, {}
    for _, e in ipairs(mainLots) do
      local id, stats = e[1], e[6]
      if hasDps(stats) and not speedOfItem(id) then
        local b = base("MAINHAND", e[2])
        local g = b and select(3, over(stats, "MAINHAND", e[2], nil, b)) or -math.huge
        if gainOf[id] == nil then order[#order + 1] = id end
        if gainOf[id] == nil or g > gainOf[id] then gainOf[id] = g end
      end
    end
    table.sort(order, function(a, b)
      if gainOf[a] ~= gainOf[b] then return gainOf[a] > gainOf[b] end
      return a < b
    end)
    for _, id in ipairs(order) do speedOfItem(id, true) end
    for _, e in ipairs(mainLots) do
      consider("MAINHAND", e[1], e[2], e[3], e[4], e[5], e[6], e[7], speedOfItem(e[1]))
    end
  end

  -- Every order here ends on the item string, so two builds over the same answers show the same
  -- (the 0.28.1 rows came and went while the client's cache answered part of the lots).
  local function byGain(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    if a.unit ~= b.unit then return a.unit < b.unit end
    return a.itemString < b.itemString
  end
  -- The strongest usable piece of a list sorted byGain: up to TOOLTIP_CHECKS looked at, strongest
  -- first. skipUsable: no tooltip call to cap, so every candidate may be looked at.
  local function strongestUsable(list)
    local checks = 0
    for _, c in ipairs(list) do
      if not skipUsable and checks >= C.TOOLTIP_CHECKS then break end
      checks = checks + 1
      if usableCandidate(c) then return c end
    end
    return nil
  end
  local function wornLink(group)
    local w = wornAt(SLOT_OF[group])
    return w and w.link or nil
  end

  -- Each group's strongest piece: usable now, over the gold carried or not.
  local picked = {}
  for _, g in ipairs(GC.ForeverUpgrades.GROUPS) do
    local now, later = {}, {}
    for _, c in ipairs(byGroup[g.key] or {}) do
      if c.later then later[#later + 1] = c else now[#now + 1] = c end
    end
    table.sort(now, byGain)
    table.sort(later, byGain)
    -- M4 (final review): a level-ahead piece gets the same tooltip check a usable-now one does, not
    -- the class table alone -- a profession-required piece the table says nothing against (an
    -- engineering item, say) could otherwise be offered "at level N" on class rules alone.
    local best = strongestUsable(now) or strongestUsable(later)
    if best then picked[g.key] = { now = now, later = later, best = best } end
  end

  -- The set's choices per group, walked strongest first like the other choices below: the
  -- affordable usable-now pieces on its price frontier, each at or under the gold carried and
  -- cheaper than every stronger one kept. A pair's groups (PAIR_OF) keep one more: a piece only one
  -- stronger, cheaper piece beats, since that one may be in the other slot (a sword in each hand
  -- needs the second sword even when it is dearer, a ring on each finger the second ring). A two-hander walks a frontier of its own: it never pairs
  -- with an off hand, so a cheaper, stronger one does not make a one-hander and a shield a worse
  -- pair. FRONTIER_CHECKS reads per group, a budget of its own. Not on the count-only path.
  local setPick = {}
  if money ~= nil and not skipUsable then
    local options = {}
    for _, g in ipairs(GC.ForeverUpgrades.GROUPS) do
      local p = picked[g.key]
      if p then
        local hands = PAIR_OF[g.key] ~= nil
        local list, reads, low = {}, 0, { one = { math.huge, math.huge }, two = { math.huge, math.huge } }
        for _, c in ipairs(p.now) do
          local t = low[c.twoHand and "two" or "one"]
          local room = (hands and not c.twoHand) and t[2] or t[1]
          if c.unit <= money and c.unit < room then
            if usableOf[c.itemString] == nil then
              if reads >= C.FRONTIER_CHECKS then break end
              reads = reads + 1
            end
            if usableCandidate(c) then
              list[#list + 1] = c
              if c.unit < t[1] then t[1], t[2] = c.unit, t[1] else t[2] = c.unit end
            end
          end
        end
        options[g.key] = list
      end
    end
    out.set = GC.ForeverUpgrades.BestSet(options, money)
    for key, c in pairs(out.set.picks) do
      c.inSet = true
      setPick[key] = c
    end
  end

  -- The other choices beside each strongest piece, in this order, at most ALTS, never the strongest
  -- itself and never one item string twice:
  --   1. the set's piece for the group, when it is not the strongest;
  --   2. the strongest usable piece a level or two ahead that beats it, when it is usable now;
  --   3. cheaper usable-now pieces, strongest first, each at most ALT_PRICE_STEP of the price of the
  --      one shown before it (the first, of the strongest's). Walking strongest first, a piece the
  --      step lets through is cheaper than every stronger one shown, so each is on the price
  --      frontier: nothing cheaper and as strong is usable. One the tooltip refuses moves nothing,
  --      and those behind it stay in reach; the set's piece, met again here, moves the step as if
  --      shown. Only a read costs one of FRONTIER_CHECKS, and a piece over the step is never read.
  --   4. when that frontier finds nothing (the strongest is also the cheapest), the next strongest
  --      usable-now items whatever they cost, one version of each and none already shown, so a
  --      slot with thirty pieces never shows one. Their reads share the frontier's FRONTIER_CHECKS.
  for _, g in ipairs(GC.ForeverUpgrades.GROUPS) do
    local p = picked[g.key]
    if p then
      local best, alts, listed = p.best, {}, { [p.best.itemString] = true }
      local function add(c)
        if c and #alts < C.ALTS and not listed[c.itemString] then
          listed[c.itemString] = true
          alts[#alts + 1] = c
        end
      end
      add(setPick[g.key])
      if not best.later then
        local stronger = {}
        for _, c in ipairs(p.later) do
          if c.gain > best.gain then stronger[#stronger + 1] = c end
        end
        add(strongestUsable(stronger))
      end
      local limit, reads, found = C.ALT_PRICE_STEP * best.unit, 0, false
      for _, c in ipairs(p.now) do
        if #alts >= C.ALTS then break end
        if c.unit <= limit then
          if not skipUsable and usableOf[c.itemString] == nil then
            if reads >= C.FRONTIER_CHECKS then break end
            reads = reads + 1
          end
          if usableCandidate(c) then
            add(c)
            limit, found = C.ALT_PRICE_STEP * c.unit, true
          end
        end
      end
      if not found then
        local items = {}
        for _, c in ipairs(alts) do items[c.itemID] = true end
        items[best.itemID] = true
        for _, c in ipairs(p.now) do
          if #alts >= C.ALTS then break end
          if not items[c.itemID] then
            if not skipUsable and usableOf[c.itemString] == nil then
              if reads >= C.FRONTIER_CHECKS then break end
              reads = reads + 1
            end
            if usableCandidate(c) then
              items[c.itemID] = true
              add(c)
            end
          end
        end
      end
      out.slots[#out.slots + 1] = { group = g.key, labelKey = g.labelKey, best = best, alts = alts,
        worn = wornLink(g.key), invSlot = SLOT_OF[g.key] }
    end
  end

  local asked = 0
  for itemID in pairs(loading) do
    out.loading = out.loading + 1
    if asked < C.REQUEST_PER_BUILD then
      asked = asked + 1
      driver.requestLoad(itemID)
    end
  end
  -- M1 (final review): the exact ids this build is still waiting on, so a caller (the upgrades
  -- window) can tell a GET_ITEM_INFO_RECEIVED it was not waiting for from one that might resolve
  -- something, instead of rebuilding on every arrival regardless.
  out.loadingIds = loading
  -- The main-hand items still without a speed, weighed at the worn one's this build: a later build
  -- reads the next SPEED_READS of them.
  local speedPending = 0
  for id in pairs(speedWanted) do
    if not speeds[id] then speedPending = speedPending + 1 end
  end
  if speedPending > 0 then out.speedPending = speedPending end
  if next(waiting) ~= nil then out.waiting = waiting end
  return out
end

-- Every /gc weights call saves the class's whole table, its defaults included, so a saved default
-- is not the player's choice and moves with the defaults, once, for every class in the account's
-- prefs at the same time; prefs.weightsV says how far that has gone, so a number the player types
-- later stays. 2: the three melee classes' DPS was 2 until the HERO plan (Finding 3, 13.11). 3
-- (14.11): the other classes' DPS was the old number below (a druid had none), and a shaman's or a
-- druid's table had no AP. 4 (14.11): a table equal to its class's defaults in every token goes, after
-- the moves above: it was never the player's choice, and without it a class with a DPS model takes
-- its weights from the character (WeightsFor).
local MELEE_DPS_MOVED = { "WARRIOR", "PALADIN", "ROGUE" }
local OLD_DPS = { HUNTER = 2, SHAMAN = 1.5, MAGE = 0.5, PRIEST = 0.5, WARLOCK = 0.5 }
local AP_ADDED = { "SHAMAN", "DRUID" }
local function sameWeights(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if b[k] ~= v then return false end
  end
  for k, v in pairs(b) do
    if a[k] ~= v then return false end
  end
  return true
end
local function migrateWeights(prefs)
  if type(prefs) ~= "table" then return end
  local v = tonumber(prefs.weightsV) or 0
  if v >= 4 then return end
  local saved = type(prefs.weights) == "table" and prefs.weights or {}
  local defaults = GC.ForeverUpgrades.DEFAULT_WEIGHTS
  if v < 2 then
    for _, class in ipairs(MELEE_DPS_MOVED) do
      local own = saved[class]
      if type(own) == "table" and own.DPS == 2 then own.DPS = defaults[class].DPS end
    end
  end
  if v < 3 then
    for class, old in pairs(OLD_DPS) do
      local own = saved[class]
      if type(own) == "table" and own.DPS == old then own.DPS = defaults[class].DPS end
    end
    for _, class in ipairs(AP_ADDED) do
      local own = saved[class]
      if type(own) == "table" and own.AP == nil then own.AP = defaults[class].AP end
    end
  end
  for class, own in pairs(saved) do
    if sameWeights(own, defaults[class]) then saved[class] = nil end
  end
  prefs.weightsV = 4
end

-- Stat weights: the player's own for this class, else a copy of the class's default, else none.
-- With a DPS model (ModelFor) and no table of the player's own, the class's default with the stats
-- the model counts set from the character, for the window to show: STR, AGI and AP at K x per, and
-- weapon DPS at K (1 + crit). A piece is ranked by K times the DPS it adds, counted whole, and what
-- the other stats are worth (newBench). Second return value: true for those (the window says so).
function GC.ForeverUpgrades.WeightsFor(prefs, classFile, model)
  migrateWeights(prefs)
  local own = type(prefs) == "table" and type(prefs.weights) == "table" and prefs.weights[classFile] or nil
  if type(own) == "table" then return own end
  local copy = {}
  for k, v in pairs(GC.ForeverUpgrades.DEFAULT_WEIGHTS[classFile] or {}) do copy[k] = v end
  if type(model) ~= "table" then return copy end
  for _, token in ipairs(PER_ORDER) do copy[token] = model.K * model.per[token] end
  copy.DPS = model.K * (1 + model.crit)
  DERIVED[copy] = true
  return copy, true
end

-- The table a weight the player types goes into (/gc weights and the HERO tab's panel save it whole):
-- the weights in force, those from the character at the two decimals the panel shows.
function GC.ForeverUpgrades.EditWeights(prefs, classFile, model)
  local weights, derived = GC.ForeverUpgrades.WeightsFor(prefs, classFile, model)
  if not derived then return weights end
  for token in pairs(GC.ForeverUpgrades.MODELLED) do
    local w = weights[token]
    if w then weights[token] = math.floor(w * 100 + 0.5) / 100 end
  end
  return weights
end

-- "STR 2 DPS 0": each token set to its number, 0 removes it. nil and the offending text on a token
-- it does not know or a number it cannot read -- then nothing is changed.
-- Third return value: "novalue" only when a recognized token is the LAST word typed, nothing
-- after it at all -- SlashWeights uses that to tell a real stat missing its number apart from a
-- genuinely unrecognized word. A recognized token followed by a word that still is not a number
-- ("STR lots") is not this case: `bad` there carries both words, same as an unknown token does,
-- because a trailing word that parses as neither a stat nor a number is closer to nonsense than
-- to "forgot the number".
function GC.ForeverUpgrades.ApplyWeights(weights, rest)
  local words = {}
  for w in (rest or ""):gmatch("%S+") do words[#words + 1] = w end
  local new = {}
  for k, v in pairs(weights or {}) do new[k] = v end
  for i = 1, #words, 2 do
    local token, value = words[i]:upper(), tonumber(words[i + 1] or "")
    if not GC.ForeverUpgrades.TOKENS[token] then return nil, words[i] end
    if value == nil then
      if words[i + 1] == nil then return nil, words[i], "novalue" end
      return nil, words[i] .. " " .. words[i + 1]
    end
    new[token] = value ~= 0 and value or nil
  end
  return new
end

function GC.ForeverUpgrades.WeightsText(weights)
  local parts = {}
  for _, token in ipairs(GC.ForeverUpgrades.TOKEN_ORDER) do
    local w = (weights or {})[token]
    if type(w) == "number" and w ~= 0 then
      parts[#parts + 1] = ("%s %g"):format(_G[GC.ForeverUpgrades.TOKENS[token][1]] or token, w)
    end
  end
  return table.concat(parts, ", ")
end

local function enabled()
  return GC.ForeverScan and GC.ForeverScan.Enabled and GC.ForeverScan.Enabled() or false
end

local function statsCall()
  local item = _G.C_Item
  if type(item) == "table" and type(item.GetItemStats) == "function" then return item.GetItemStats end
  if type(_G.GetItemStats) == "function" then return _G.GetItemStats end
  return nil
end

local function classFile()
  local ok, _, file = pcall(_G.UnitClass, "player")
  return ok and type(file) == "string" and file or nil
end

-- What the client said about each item string, for the session: a piece's level requirement, link
-- and stats do not change, and the client's item cache does not hold every lot a scan lists. Asked
-- about all of them on every repaint (~1170 on the owner's realm, 2026-11-13, recorded), it held
-- about half, dropped the other half to load the rest, and the two halves swapped places on each
-- repaint: the window's rows came and went every half second, a rebuild of ~60 ms each time. Kept,
-- a piece is asked about until it answers once. Build only reads the stats it is handed.
--
-- keptUsable: the tooltip's verdict on a piece, the priciest read here, per piece and character
-- level, so a level-up asks again (a red "Requires Level" line is gone then). A skill trained
-- mid-session shows on the next level or /reload. Only a yes or a no is kept: "cannot tell"
-- (nothing loaded yet, still loading, no colours) is asked again next time.
-- keptSpeed: a weapon's speed per itemID, only once the tooltip has said it. A random suffix
-- changes a weapon's stats and damage, never its speed, so every version and the worn piece share
-- one read (kept per item string until 13.11, two versions of one dagger cost two).
local keptInfo, keptStats, keptUsable, keptSpeed = {}, {}, {}, {}
-- keptChar: the character's numbers (char() below) as last read whole, and at what level. Each of
-- the reads is SecretWhenUnitStatsRestricted in Forever (1.60.1 docs): where the client keeps unit
-- stats secret it answers with a value addon code cannot count with, and the tab would then lose
-- its DPS figures and rank by other weights until it can read again. Those moments use the last
-- numbers instead, at the same level.
local keptChar = nil

local function playerLevel()
  local ok, l = pcall(_G.UnitLevel, "player")
  return ok and tonumber(l) or 1
end

-- The client, for Build. Every read guarded: a missing API reads as "not answered", never an error.
local function realDriver(getStats)
  local item = _G.C_Item or {}
  return {
    level = playerLevel,
    classFile = classFile,
    equipped = function(slot)
      local ok, link = pcall(_G.GetInventoryItemLink, "player", slot)
      return ok and type(link) == "string" and link or nil
    end,
    instant = function(itemID)
      local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(item.GetItemInfoInstant, itemID)
      if ok then return equipLoc, classID, subclassID end
      return nil
    end,
    info = function(itemString)
      local kept = keptInfo[itemString]
      if kept then return kept[1], kept[2] end
      local ok, name, link, _, _, minLevel = pcall(item.GetItemInfo, itemString)
      if not (ok and name) then return nil end
      kept = { tonumber(minLevel) or 0, link }
      keptInfo[itemString] = kept
      return kept[1], kept[2]
    end,
    stats = function(s)
      local kept = keptStats[s]
      if kept then return kept end
      local ok, t = pcall(getStats, s)
      if not (ok and type(t) == "table") then return nil end
      keptStats[s] = t
      return t
    end,
    usable = function(s)
      local key = s .. "@" .. playerLevel()
      local kept = keptUsable[key]
      if kept ~= nil then return kept end
      local u = GC.ForeverUpgrades.TooltipUsable(s)
      if u ~= nil then keptUsable[key] = u end
      return u
    end,
    -- A weapon's speed, for DpsFactor (TooltipSpeed), by its itemID: the bare "item:<id>" read,
    -- the worn piece's too. read false: only what is kept, never a tooltip read (Build spends its
    -- SPEED_READS on true). Kept once the tooltip said it; asked again while it says nothing.
    speed = function(itemID, read)
      itemID = tonumber(itemID)
      if not itemID then return nil end
      local kept = keptSpeed[itemID]
      if kept or not read then return kept end
      local v, loaded = GC.ForeverUpgrades.TooltipSpeed(("item:%d"):format(itemID))
      if not v and loaded then v = C.REF_SPEED end
      if v then keptSpeed[itemID] = v end
      return v
    end,
    requestLoad = function(itemID) pcall(item.RequestLoadItemDataByID, itemID) end,
    money = function()
      local ok, m = pcall(_G.GetMoney)
      return ok and tonumber(m) or nil
    end,
    -- I1: the client's own answer, when it has the call; Build falls back to Classic's rule
    -- (rogue always, warrior/hunter from level 20) when this is absent or errors.
    canDualWield = function()
      local ok, v = pcall(_G.CanDualWield)
      if ok and type(v) == "boolean" then return v end
      return nil
    end,
    -- The class's name in the player's language, as the client writes it (TooltipVerdict's words).
    className = function()
      local ok, name = pcall(_G.UnitClass, "player")
      return ok and type(name) == "string" and name or nil
    end,
    -- The character's numbers for its DPS model (DpsModel), as Camelot's character sheet reads
    -- them (PaperDollFrameStats.lua): its attack power and ranged attack power with their buffs,
    -- its crit chance (GetCritChance is a percent, kept as a fraction), and what ten more points of
    -- strength (1) or agility (2) give at the character's own, a point's worth (GetCritChanceFromStat
    -- is a fraction already). nil when any of it does not answer: no model, the weights as before.
    -- A client without one of the calls has no model; one that has them all but keeps an answer
    -- secret (or errors) for now gives keptChar, at the level it was read.
    char = function()
      local absent = false
      local function secret(v)
        local is = _G.issecretvalue
        if type(is) ~= "function" then return false end
        local ok, yes = pcall(is, v)
        return ok and yes == true
      end
      local function call(fn, ...)
        if type(fn) ~= "function" then
          absent = true
          return nil
        end
        local ok, a, b, c = pcall(fn, ...)
        if not ok or secret(a) or secret(b) or secret(c) then return nil end
        return a, b, c
      end
      local function total(fn)
        local base, pos, neg = call(fn, "player")
        if type(base) ~= "number" then return nil end
        return base + (tonumber(pos) or 0) + (tonumber(neg) or 0)
      end
      local function per(fn, stat)
        local _, eff = call(_G.UnitStat, "player", stat)
        if type(eff) ~= "number" then return nil end
        local now, more = call(fn, stat, eff), call(fn, stat, eff + 10)
        if type(now) ~= "number" or type(more) ~= "number" then return nil end
        return (more - now) / 10
      end
      local crit = call(_G.GetCritChance)
      local out = { ap = total(_G.UnitAttackPower), rap = total(_G.UnitRangedAttackPower),
        crit = type(crit) == "number" and crit / 100 or nil,
        apPer = { STR = per(_G.GetAttackPowerForStat, 1), AGI = per(_G.GetAttackPowerForStat, 2) },
        rapPer = { AGI = per(_G.GetRangedAttackPowerForStat, 2) },
        critPer = { AGI = per(_G.GetCritChanceFromStat, 2) } }
      if not (out.ap and out.rap and out.crit and out.apPer.STR and out.apPer.AGI and out.rapPer.AGI
          and out.critPer.AGI) then
        if absent or not keptChar or keptChar.level ~= playerLevel() then return nil end
        return keptChar.out
      end
      keptChar = { level = playerLevel(), out = out }
      return out
    end,
  }
end

-- How a rogue uses its main hand (StyleFor), from the weapon it wears there unless it chose.
local function wornStyle(driver, prefs, class)
  local mainID = itemIdOf(driver.equipped(16))
  local mainSub = mainID and select(3, driver.instant(mainID)) or nil
  return GC.ForeverUpgrades.StyleFor(prefs, class, mainSub)
end

-- skipUsable, threaded straight through to Build: nil/false (every existing caller -- the window's
-- own Show/RefreshIfShown, /gc weights, a direct call) keeps the tooltip check exactly as before.
--
-- r.style: the rogue's style Build was given (StyleFor), from the main hand it wears unless the
-- player chose one; nil for every other class. r.model: the character's DPS model (ModelFor), or nil;
-- its worn main hand's speed read once off the count-only path. Read before a scan is there too:
-- with none, the weights panel still shows and saves the weights in force (review, 14.11).
function GC.ForeverUpgrades.Current(skipUsable)
  if not enabled() then return nil end
  local gear, fold = GC.ForeverScan.Gear()
  local getStats = statsCall()
  local class, prefs = classFile(), GC.ForeverScan.Prefs()
  local driver = getStats and realDriver(getStats) or nil
  local model = driver and GC.ForeverUpgrades.ModelFor(driver, class, not skipUsable) or nil
  if not gear then return { slots = {}, loading = 0, noScan = true, model = model } end
  if not driver then return { slots = {}, loading = 0, noStats = true } end
  local weights = GC.ForeverUpgrades.WeightsFor(prefs, class, model)
  local style = wornStyle(driver, prefs, class)
  local r = GC.ForeverUpgrades.Build(gear, driver, weights, skipUsable, { style = style, model = model })
  r.at, r.weights, r.style, r.model = fold.at, weights, style, model
  return r
end

-- A loss on the game's tooltip, in the client's own red (its "Requires Level" line's): the line
-- itself is green, and a gain keeps that.
local function lossRed(text)
  local c = _G.RED_FONT_COLOR
  local rgb = type(c) == "table" and type(c.r) == "number" and { c.r, c.g, c.b } or { 1, 0.1, 0.1 }
  return GC.Util.Colored(rgb, text)
end

-- An item's tooltip on WoW: Forever (UI/Tooltip.lua, the HERO plan's Task 9): whether the piece is
-- an upgrade for the character looking, by the HERO tab's own rules (newBench: the weaker ring, a
-- two-hander against both hands, dual-wield for an off-hand weapon, the Backstab rogue's dagger,
-- Build's threshold), so the two never disagree. Lines for BuildLines, { kind = "verdict", tone,
-- text }, or nil to say nothing.
--   An upgrade: "Upgrade: <what changes> over your <worn piece>", good, and for a piece above the
--   character's level how many levels until it can wear it, dim. A one-hand weapon is weighed for
--   either hand and a ring for either finger, and the larger gain is said, with that slot's piece:
--   for a ring, the weaker ring worn. A piece more than LEVEL_AHEAD levels ahead is no upgrade
--   yet, as the HERO tab never offers it.
--   Nothing the class weighs: "Not an upgrade for your <class>: nothing here you use", dim.
--   Otherwise nil: a weaker piece, the piece worn, one ClassAllows refuses (the client's own red
--   line says so), a slot the groups leave out (trinkets, bags), a link the client has not
--   answered for, and never a bare item id, which scores a suffix version by its base stats.
-- No tooltip read inside a tooltip: usable is ClassAllows alone, and a weapon's speed is one the
-- driver already keeps from Build's reads; one not kept is the worn main hand's, as in Build.
-- driver, weights, opts: as Build's, for a spec; with no driver, the client's and the character's
-- own, and only on WoW: Forever.
function GC.ForeverUpgrades.TooltipVerdict(link, driver, weights, opts)
  local client = driver == nil
  if client then
    if not enabled() then return nil end
    local getStats = statsCall()
    if not getStats then return nil end
    driver = realDriver(getStats)
  end
  local itemID = itemIdOf(link)
  if not itemID then return nil end
  local equipLoc, classID, subclassID = driver.instant(itemID)
  local groups = { GROUP_OF[equipLoc], SECOND_OF[equipLoc] }
  if not groups[1] then return nil end
  -- It runs on every item tooltip: the character's weights only once the item is gear.
  if client then
    local class, prefs = classFile(), GC.ForeverScan.Prefs()
    local model = GC.ForeverUpgrades.ModelFor(driver, class, false)
    weights = GC.ForeverUpgrades.WeightsFor(prefs, class, model)
    opts = { style = wornStyle(driver, prefs, class), model = model }
  end
  if type(weights) ~= "table" or next(weights) == nil then return nil end
  local level, class = tonumber(driver.level()) or 1, driver.classFile()
  local minLevel = driver.info(link)
  if minLevel == nil then return nil end
  if GC.ForeverUpgrades.ClassAllows(class, classID, subclassID, math.max(level, minLevel)) ~= true then return nil end
  local stats = driver.stats(link)
  if stats == nil then return nil end

  -- The piece worn in a slot it could go in says nothing: the stronger of two rings would read as
  -- an upgrade over the weaker, and a one-hander in the main hand as one over the off hand.
  local inGroup = {}
  for _, g in ipairs(groups) do inGroup[g] = true end
  local suffix, unique, bonus = GC.ForeverGear.Variant(link)
  for slot, g in pairs(GROUP_AT) do
    local other = inGroup[g] and driver.equipped(slot) or nil
    if other and itemIdOf(other) == itemID then
      local otherSuffix, otherUnique, otherBonus = GC.ForeverGear.Variant(other)
      if otherSuffix == suffix and otherUnique == unique and otherBonus == bonus then return nil end
    end
  end

  -- Speeds as kept: a weapon not read yet swings at the worn main hand's (newBench), and with the
  -- worn one's not kept neither counts. A worn 1.50 dagger kept (about 0.92) against REF_SPEED
  -- (1) would call an equal weapon an upgrade.
  local mine, theirs
  if C.ABILITY_EVERY[class] and type(driver.speed) == "function" and type(weights.DPS) == "number"
      and weights.DPS ~= 0 then
    local function kept(id)
      local v = id and driver.speed(id, false) or nil
      return type(v) == "number" and v > 0 and v or nil
    end
    local wornMain = itemIdOf(driver.equipped(16))
    mine, theirs = kept(itemID), kept(wornMain)
    if wornMain and not theirs then mine = nil end
  end

  local Score = GC.ForeverUpgrades.Score
  local style = type(opts) == "table" and opts.style or nil
  local model = type(opts) == "table" and opts.model or nil
  local bench = newBench(driver, weights, class, level, style, function() return theirs end, {}, model)
  local best, goes = nil, false
  for _, g in ipairs(groups) do
    if bench.wanted(g, equipLoc, classID, subclassID) then
      goes = true
      local b = bench.base(g, equipLoc)
      if b then
        local score, parts, raw = bench.over(stats, g, equipLoc, g == "MAINHAND" and mine or nil, b)
        local gain = bench.beats(score, b, raw)
        if gain and (best == nil or gain > best.gain) then best = { gain = gain, group = g, base = b, parts = parts } end
      end
    end
  end
  if not goes then return nil end
  local _, parts = Score(stats, weights)
  if next(parts) == nil then
    local name = type(driver.className) == "function" and driver.className() or class
    if type(name) ~= "string" then return nil end
    return { { kind = "verdict", tone = "dim",
      text = GC.L["Not an upgrade for your %s: nothing here you use"]:format(name) } }
  end
  if not best or minLevel > level + C.LEVEL_AHEAD then return nil end

  -- What changes, each loss in the client's red: with a model, first what the piece adds to the
  -- character's DPS (Build's `dps`, by the same bench) and the stats that make it in brackets, then
  -- the others; without one, every stat.
  local U = GC.ForeverUpgrades
  local function said(diffs, skip)
    local out = {}
    for _, part in ipairs(U.DiffParts(diffs)) do
      if not (skip and skip[part.token]) then out[#out + 1] = part.loss and lossRed(part.text) or part.text end
    end
    return table.concat(out, ", ")
  end
  local diff = U.Diff(best.parts, best.base.parts)
  local dps, counted = bench.dps(stats, best.group, equipLoc, best.group == "MAINHAND" and mine or nil, best.base)
  local what
  if dps then
    local figure, sign = U.DpsFigure(dps)
    what = GC.L["%s DPS"]:format(figure)
    if sign < 0 then what = lossRed(what) end
    local inside = said(counted)
    if inside ~= "" then what = GC.L["%s (%s)"]:format(what, inside) end
    local rest = said(diff, U.MODELLED)
    if rest ~= "" then what = what .. ", " .. rest end
  else
    what = said(diff)
    if what == "" then
      -- Nothing changes but the swing: the same stats at a slower speed, both speeds kept (above).
      if not (mine and theirs and type(_G.SPEED) == "string" and _G.SPEED ~= "") then return nil end
      what = ("%+.2f %s"):format(mine - theirs, _G.SPEED)
    end
  end
  -- The worn piece by its own name, both hands' for a two-hander over a one-hander and what the
  -- off hand holds. One the client names nowhere yet goes by its slot's name, never as nothing.
  local names = {}
  local function name(worn, group)
    local text = worn and worn.link
    if type(text) ~= "string" then return end
    local n = text:match("%[(.-)%]")
    if not n then
      local _, full = driver.info(text)
      n = type(full) == "string" and full:match("%[(.-)%]") or nil
    end
    if not n then
      for _, g in ipairs(GC.ForeverUpgrades.GROUPS) do
        if g.key == group then n = _G[g.labelKey] or g.labelKey end
      end
    end
    names[#names + 1] = n
  end
  if best.group == "MAINHAND" and equipLoc == "INVTYPE_2HWEAPON" and not bench.twoHandWorn then
    name(bench.wornAt(16), "MAINHAND"); name(bench.wornAt(17), "OFFHAND")
  else
    name(best.base, best.group)
  end
  local text
  if #names == 2 then
    text = GC.L["Upgrade: %s over your %s"]:format(what, GC.L["%s and %s"]:format(names[1], names[2]))
  elseif #names == 1 then
    text = GC.L["Upgrade: %s over your %s"]:format(what, names[1])
  else
    text = GC.L["Upgrade: %s, nothing worn there"]:format(what)
  end
  local lines = { { kind = "verdict", tone = "good", text = text } }
  if minLevel > level then
    local n = minLevel - level
    lines[2] = { kind = "verdict", tone = "dim",
      text = n == 1 and GC.L["You can wear it next level"] or GC.L["You can wear it in %d levels"]:format(n) }
  end
  return lines
end

-- The HERO tab's shopping list: the player's Upgrades list in BUY (prefs.heroList), read and
-- changed here as plain data, so its rules live in one place. `lines` are the list's own ({ i, q,
-- ver, ... }), `bought` what this character bought on it ({ [itemID] = n }), `c` a candidate of
-- Build's. A line buys one version of its item at a time, `ver` the candidate's (nil, a lot from a
-- scan saved before versions, buys any): BUY never bids on another (Core/BuyLots.lua), and a line
-- with a version counts only what it bought, never what the bags hold (Core/BuyRun.lua). Each
-- answer is a new list; the lines handed in are left as they are.

local function lineOf(lines, itemID)
  for i, line in ipairs(lines or {}) do
    if line.i == itemID then return line, i end
  end
  return nil, nil
end

local function boughtOf(bought, itemID)
  local n = type(bought) == "table" and tonumber(bought[itemID]) or nil
  return n and n > 0 and math.floor(n) or 0
end

-- Whether a line's versions take candidate version `version`: any, the same, or one of a list
-- (two lines of one item joined in BUY buy the versions of both: Core/AppRuns.lua's joinVer).
local function holds(ver, version)
  if ver == nil or ver == version then return true end
  if type(ver) ~= "string" or type(version) ~= "string" then return false end
  return ("," .. ver .. ","):find("," .. version .. ",", 1, true) ~= nil
end

local function copied(lines)
  local out = {}
  for i, line in ipairs(lines or {}) do
    local copy = {}
    for k, v in pairs(line) do copy[k] = v end
    out[i] = copy
  end
  return out
end

--- "listed" while the list still buys `c` (its item's line has need left, q over what was bought,
--- and takes c's version); "bought" once that line has none left and bought some; else nil.
function GC.ForeverUpgrades.ListState(lines, bought, c)
  local line = type(c) == "table" and lineOf(lines, c.itemID) or nil
  if not (line and holds(line.ver, c.version)) then return nil end
  local got = boughtOf(bought, c.itemID)
  if (tonumber(line.q) or 0) > got then return "listed" end
  return got > 0 and "bought" or nil
end

--- One more `c` on the list: a new line of one past what was bought; on a line with nothing left to
--- buy, one more of c's version alone; on one still buying c's version, one more of it; on one
--- buying another version, one of c's instead (one item, one version at a time). Answers the new
--- lines, and whether c joined pieces of its own version already wanted.
function GC.ForeverUpgrades.ListAdd(lines, bought, c)
  local out = copied(lines)
  local line = lineOf(out, c.itemID)
  local got = boughtOf(bought, c.itemID)
  if not line then
    out[#out + 1] = { i = c.itemID, q = got + 1, ver = c.version }
    return out, false
  end
  if (tonumber(line.q) or 0) > got and line.ver == c.version then
    line.q = line.q + 1
    return out, true
  end
  line.q, line.ver = got + 1, c.version
  return out, false
end

--- One `c` fewer: its line asks for one less, never less than was bought; a line left with nothing
--- bought and nothing to buy goes. A line that does not take c's version stays as it is.
function GC.ForeverUpgrades.ListRemove(lines, bought, c)
  local out = copied(lines)
  local line, at = lineOf(out, c.itemID)
  if not (line and holds(line.ver, c.version)) then return out end
  local got = boughtOf(bought, c.itemID)
  line.q = math.max(got, (tonumber(line.q) or 0) - 1)
  if line.q == 0 then table.remove(out, at) end
  return out
end

--- The cap BUY holds a piece's line to: its lot's price and 5% (copper), the player's own line cap
--- BUY ranks first (GC.Buy._SetLineCap).
function GC.ForeverUpgrades.LineCap(c)
  return math.floor((tonumber(c.unit) or 0) * 105 / 100)
end

-- After every saved scan (Core/ForeverScan.lua's _QueueUpgradesUpdate): one line, only when there
-- is something. r: the scan's own already-built result, when the caller has one -- the deferred
-- post-scan update builds once and hands the same result to this and to the window's own render,
-- rather than each building its own. A direct call (a test, /gc upgrades' own paths) with no r
-- still gets a correct count from its own Current().
--
-- `said` (the scan's session record) keeps the line from repeating while the count is unchanged.
-- The count is of slots: one whose strongest piece costs more than the gold carried counts too.
function GC.ForeverUpgrades.PrintCount(r, said)
  r = r or GC.ForeverUpgrades.Current()
  local n = r and type(r.slots) == "table" and #r.slots or 0
  if n > 0 then
    if said then
      if said.upgrades == n then return end
      said.upgrades = n
    end
    GC.Print(GC.L["Upgrades for your gear on the auction house: %d. Type /gc upgrades to see them."]:format(n))
  end
end

-- /gc weights [<TOKEN> <number> ... | reset]
function GC.ForeverUpgrades.SlashWeights(rest)
  local prefs = GC.ForeverScan and GC.ForeverScan.Prefs and GC.ForeverScan.Prefs()
  local class = classFile()
  if not prefs or not class then return end
  rest = type(rest) == "string" and rest or ""
  -- The weights in force, those from the character as the panel shows them (EditWeights).
  local getStats = statsCall()
  local model = getStats and GC.ForeverUpgrades.ModelFor(realDriver(getStats), class, false) or nil
  local weights = GC.ForeverUpgrades.EditWeights(prefs, class, model)
  if rest:lower() == "reset" then
    if type(prefs.weights) == "table" then prefs.weights[class] = nil end
    weights = GC.ForeverUpgrades.EditWeights(prefs, class, model)
  elseif rest ~= "" then
    local new, bad, reason = GC.ForeverUpgrades.ApplyWeights(weights, rest)
    if not new then
      if reason == "novalue" then
        GC.Print(GC.L["%s needs a number, for example /gc weights %s 1.5"]:format(bad, bad))
        return
      end
      GC.Print(GC.L["Unknown stat %s. Use one of: %s"]:format(bad,
        table.concat(GC.ForeverUpgrades.TOKEN_ORDER, ", ")))
      return
    end
    prefs.weights = type(prefs.weights) == "table" and prefs.weights or {}
    prefs.weights[class] = new
    weights = new
  end
  if next(weights) == nil then
    GC.Print(GC.L["No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5"])
  else
    GC.Print(GC.L["Stat weights: %s"]:format(GC.ForeverUpgrades.WeightsText(weights)))
  end
  if GC.Hero and GC.Hero.RefreshIfShown then GC.Hero.RefreshIfShown(true) end
end
