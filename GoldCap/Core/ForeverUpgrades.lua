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
  -- The seconds between a class's weapon-swing abilities, for a class whose main hand is weighed by
  -- its speed (DpsFactor): a rogue's Sinister Strike costs 45 energy and energy comes back at 10 a
  -- second, so one lands about every 4.5 s.
  ABILITY_EVERY = { ROGUE = 4.5 },
  REF_SPEED = 2.0,         -- the weapon speed DpsFactor scores at 1: slower counts more, faster less
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
-- DPS for the three melee classes is 14 times their AP weight (HERO plan, Finding 3, 2026-11-13): in
-- Classic one point of weapon DPS is worth 14 attack power, and the 2 these had weighed it like 4.
-- Hunters, casters and hybrids keep their numbers: nothing measured
-- says otherwise for them. A player's own /gc weights stay as they were saved.
GC.ForeverUpgrades.DEFAULT_WEIGHTS = {
  WARRIOR = { STR = 1, AGI = 0.5, STA = 0.5, AP = 0.5, DPS = 7, ARMOR = 0.01 },
  PALADIN = { STR = 1, INT = 0.4, STA = 0.5, AGI = 0.3, AP = 0.5, DPS = 7, ARMOR = 0.01 },
  ROGUE = { AGI = 1, STR = 0.5, STA = 0.4, AP = 0.5, DPS = 7, ARMOR = 0.01 },
  HUNTER = { AGI = 1, INT = 0.3, STA = 0.4, AP = 0.4, DPS = 2, ARMOR = 0.01 },
  SHAMAN = { INT = 0.8, STR = 0.6, AGI = 0.4, STA = 0.5, SPI = 0.2, SP = 0.8, DPS = 1.5, ARMOR = 0.01 },
  DRUID = { INT = 0.8, STR = 0.6, AGI = 0.6, STA = 0.5, SPI = 0.3, SP = 0.8, ARMOR = 0.01 },
  MAGE = { INT = 1, SPI = 0.4, STA = 0.5, SP = 1, DPS = 0.5, ARMOR = 0.005 },
  PRIEST = { INT = 1, SPI = 0.6, STA = 0.5, SP = 1, DPS = 0.5, ARMOR = 0.005 },
  WARLOCK = { INT = 1, SPI = 0.4, STA = 0.6, SP = 1, DPS = 0.5, ARMOR = 0.005 },
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
  { key = "FINGER", slots = { 11, 12 }, labelKey = "INVTYPE_FINGER" },
  { key = "MAINHAND", slots = { 16 }, labelKey = "INVTYPE_WEAPONMAINHAND" },
  { key = "OFFHAND", slots = { 17 }, labelKey = "INVTYPE_WEAPONOFFHAND" },
  { key = "RANGED", slots = { 18 }, labelKey = "INVTYPE_RANGED" },
}

-- equipLoc -> group. Trinkets, relics, shirts, tabards, bags and ammo are not compared: their
-- worth is mostly effects GetItemStats does not list. A one-hand weapon (INVTYPE_WEAPON) is also an
-- OFFHAND candidate (Build): the HERO plan's Finding 2, a rogue was never offered one for the off
-- hand.
local GROUP_OF = {
  INVTYPE_HEAD = "HEAD", INVTYPE_NECK = "NECK", INVTYPE_SHOULDER = "SHOULDER", INVTYPE_CLOAK = "BACK",
  INVTYPE_CHEST = "CHEST", INVTYPE_ROBE = "CHEST", INVTYPE_WRIST = "WRIST", INVTYPE_HAND = "HANDS",
  INVTYPE_WAIST = "WAIST", INVTYPE_LEGS = "LEGS", INVTYPE_FEET = "FEET", INVTYPE_FINGER = "FINGER",
  INVTYPE_WEAPON = "MAINHAND", INVTYPE_WEAPONMAINHAND = "MAINHAND", INVTYPE_2HWEAPON = "MAINHAND",
  INVTYPE_WEAPONOFFHAND = "OFFHAND", INVTYPE_SHIELD = "OFFHAND", INVTYPE_HOLDABLE = "OFFHAND",
  INVTYPE_RANGED = "RANGED", INVTYPE_RANGEDRIGHT = "RANGED", INVTYPE_THROWN = "RANGED",
}
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
-- listed has no fallback.
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
  ROGUE = set({ 2, 3, 4, 7, 13, 15, 16, 18 }),
  DRUID = set({ 4, 5, 10, 13, 15 }),
  SHAMAN = set({ 0, 1, 4, 5, 10, 13, 15 }),
  MAGE = set({ 7, 10, 15, 19 }),
  PRIEST = set({ 4, 10, 15, 19 }),
  WARLOCK = set({ 7, 10, 15, 19 }),
}

-- Final review I1: dual-wield is not a red tooltip line (a mage's off-hand dagger tooltip shows
-- white), so it must be checked separately from ClassAllows. The client's own CanDualWield() is
-- authoritative when it exists; the Classic fallback below is only for a client or spec driver
-- that lacks it. Rogues always can; warriors and hunters from level 20; nobody else.
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

-- What a point of weapon DPS is worth in each hand, per class (HERO plan, Finding 3): the off hand
-- swings for half in Classic, and a melee class's ranged weapon is a pull more than damage, about a
-- seventh. A class or a group not listed counts as 1: only rogue and warrior get these, from the
-- same Classic rules; nothing measured says what a hunter's or a caster's hands are worth.
GC.ForeverUpgrades.HANDS = {
  ROGUE = { MAINHAND = 1, OFFHAND = 0.5, RANGED = 1 / 7 },
  WARRIOR = { MAINHAND = 1, OFFHAND = 0.5, RANGED = 1 / 7 },
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
-- token's share is scaled; parts stay the piece's own numbers, for Diff and the words on screen.
function GC.ForeverUpgrades.Score(stats, weights, dpsFactor)
  local score, parts = 0, {}
  if type(stats) ~= "table" then return score, parts end
  local dps = tonumber(dpsFactor) or 1
  for token, w in pairs(weights or {}) do
    local keys = GC.ForeverUpgrades.TOKENS[token]
    if keys and type(w) == "number" and w ~= 0 then
      local f = token == "DPS" and dps or 1
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

function GC.ForeverUpgrades.DiffText(diffs)
  local parts = {}
  for _, token in ipairs(GC.ForeverUpgrades.TOKEN_ORDER) do
    for _, key in ipairs(GC.ForeverUpgrades.TOKENS[token]) do
      local v = (diffs or {})[key]
      if v then parts[#parts + 1] = ("%s %s"):format(signed(v), _G[key] or token) end
    end
  end
  return table.concat(parts, ", ")
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
-- probe read the worn weapons' tooltips by their links).
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
      if v and v > 0 then return v end
    end
  end
  return nil
end

-- The client's tooltip for the piece, as data: false on any red line, true when it drew coloured
-- lines and none was red, nil when it cannot tell (no client call, nothing loaded, no colours).
-- One red line is not a "no": the level the piece requires, which the client draws red until the
-- character reaches it (HERO probe P5, 13.11: Feet of the Lynx at level 17, "Requires Level 19" in
-- 1.00/0.13/0.13, line type 43). Every level-ahead piece used to fail here, so the "at level N"
-- picks never showed. Type 43 is every usage requirement, class and skill included, so the line is
-- known by its text, the client's ITEM_MIN_LEVEL, never by its type.
function GC.ForeverUpgrades.TooltipUsable(itemString, api)
  local lines = tooltipLines(itemString, api)
  if not lines then return nil end
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

-- The strongest set the gold carried pays for (HERO plan, 2026-11-13): at most one piece per group,
-- the most gain whose prices add up to no more than money. options[group]: the group's choices, as
-- Build makes them (unit, gain, diffs, itemString, twoHand). The two hands are one group: nothing,
-- either hand alone, both (never one item string in both: one lot cannot fill two hands), or a
-- two-hander alone. A multiple-choice knapsack over Pareto states: after each group only the
-- partial sets no cheaper one matches in gain are kept, the cheapest SET_STATES of them.
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
    if g.key == "MAINHAND" then
      local offs = options.OFFHAND or {}
      for _, m in ipairs(options.MAINHAND or {}) do
        offer(m)
        if not m.twoHand then
          for _, o in ipairs(offs) do
            if o.itemString ~= m.itemString then offer(m, o) end
          end
        end
      end
      for _, o in ipairs(offs) do offer(o) end
    elseif g.key ~= "OFFHAND" then
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
    states = paretoFront(grown)
    for i = #states, C.SET_STATES + 1, -1 do states[i] = nil end
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
-- a tooltip read too: every weapon there counts at REF_SPEED.
--
-- opts.style: StyleFor's answer. "backstab" keeps the main hand to daggers; nil filters nothing.
--
-- The answer: { slots, set, loading, loadingIds, stale?, noWeights?, noScan? }
--   slots[i]     in GROUPS order, only the groups with a pick: { group, labelKey, best, alts, worn },
--                worn the link of the piece the slot is weighed against, or nil.
--   a candidate  { group, itemID, itemString, link, unit, gain, diffs, later, overGold, inSet,
--                version, twoHand }: version the lot's bonus (nil for a lot saved without one),
--                overGold true when the gold carried is below unit, twoHand for INVTYPE_2HWEAPON.
--   set          BestSet's answer, its picks marked inSet; nil without a money read, and on the
--                count-only path, which only counts slots.
--   stale        gear saved before suffix versions (v1): every version there reads as its base.
-- Until the HERO tab replaces UI/ForeverUpgradesFrame.lua, rows (each slot's best, with its
-- labelKey) and dearer = 0 keep that window drawing as before.
function GC.ForeverUpgrades.Build(gear, driver, weights, skipUsable, opts)
  local out = { slots = {}, rows = {}, dearer = 0, loading = 0 }
  if type(weights) ~= "table" or next(weights) == nil then out.noWeights = true; return out end
  if type(gear) ~= "table" or type(gear.items) ~= "table" then out.noScan = true; return out end
  if type(gear.v) == "number" and gear.v < 2 then out.stale = true end
  local style = type(opts) == "table" and opts.style or nil
  local level = tonumber(driver.level()) or 1
  local class = driver.classFile()
  local Score, DpsFactor, loading = GC.ForeverUpgrades.Score, GC.ForeverUpgrades.DpsFactor, {}
  local topPrimary = 0
  for _, token in ipairs({ "STR", "AGI", "STA", "INT", "SPI" }) do
    local w = weights[token]
    if type(w) == "number" and w > topPrimary then topPrimary = w end
  end
  local minGain = C.MIN_GAIN_POINTS * topPrimary

  -- A weapon's speed, only where it changes the score: the main hand of a class with an
  -- ABILITY_EVERY, under weights that count DPS. Never on the count-only path. nil: REF_SPEED.
  local readSpeed = not skipUsable and C.ABILITY_EVERY[class] ~= nil and type(driver.speed) == "function"
    and type(weights.DPS) == "number" and weights.DPS ~= 0
  local function speedIn(group, s)
    if not (readSpeed and group == "MAINHAND") then return nil end
    local v = driver.speed(s)
    return type(v) == "number" and v or nil
  end

  -- What the character wears, per slot, scored in that slot's hand. false: worn, but its stats not
  -- answered yet -- the group is skipped rather than compared against a guess.
  local worn = {}
  local function wornAt(slot)
    if worn[slot] == nil then
      local link = driver.equipped(slot)
      if not link then
        worn[slot] = { score = 0, parts = {} }
      else
        local stats = driver.stats(link)
        if stats == nil then
          worn[slot] = false
          local id = itemIdOf(link)
          if id then loading[id] = true end
        else
          local group = GROUP_AT[slot]
          local s, p = Score(stats, weights, DpsFactor(class, group, speedIn(group, link)))
          worn[slot] = { score = s, parts = p, link = link }
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
    if group == "FINGER" then
      local a, b = wornAt(11), wornAt(12)
      if not (a and b) then return nil end
      return a.score <= b.score and a or b
    end
    if group == "MAINHAND" and equipLoc == "INVTYPE_2HWEAPON" and not twoHandWorn then
      local m, o = wornAt(16), wornAt(17)
      if not (m and o) then return nil end
      return { score = m.score + o.score, parts = merged(m.parts, o.parts), link = m.link }
    end
    return wornAt(SLOT_OF[group]) or nil
  end

  -- Whether a kind of piece goes in the group at all, before any lot of it is read.
  local function wanted(group, equipLoc, classID, subclassID)
    if group == "OFFHAND" then
      -- Under a two-hander there is no off hand to fill. I1 (final review): an off-hand WEAPON (not
      -- a shield or a held item) needs dual-wield, which is not a red tooltip line -- ClassAllows
      -- alone would offer a mage an off-hand dagger it cannot equip.
      return not twoHandWorn and not (OFFHAND_WEAPON[equipLoc] and not canDualWield())
    end
    if group == "MAINHAND" and style == "backstab" then return classID == 2 and subclassID == 15 end
    return true
  end

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

  local byGroup = {}
  local function consider(group, itemID, equipLoc, lot, str, link, stats, minLevel)
    local b = base(group, equipLoc)
    if not b then return end
    local score, parts = Score(stats, weights, DpsFactor(class, group, speedIn(group, str)))
    local gain = score - b.score
    if score > 0 and gain > 0 and gain >= math.max(C.MIN_GAIN_SHARE * b.score, minGain) then
      byGroup[group] = byGroup[group] or {}
      table.insert(byGroup[group], { group = group, itemID = itemID, itemString = str, link = link or str,
        unit = lot.unit, gain = gain, diffs = GC.ForeverUpgrades.Diff(parts, b.parts),
        later = minLevel > level and minLevel or nil, overGold = money ~= nil and money < lot.unit,
        inSet = false, version = lot.bonus, twoHand = equipLoc == "INVTYPE_2HWEAPON" })
    end
  end

  for itemID, encoded in pairs(gear.items) do
    local equipLoc, classID, subclassID = driver.instant(itemID)
    local first = GROUP_OF[equipLoc]
    local second = equipLoc == "INVTYPE_WEAPON" and "OFFHAND" or nil
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
              if first then consider(first, itemID, equipLoc, lot, str, link, stats, minLevel) end
              if second then consider(second, itemID, equipLoc, lot, str, link, stats, minLevel) end
            end
          end
        end
      end
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
    local w
    if group == "FINGER" then w = base("FINGER") else w = wornAt(SLOT_OF[group]) end
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
  -- cheaper than every stronger one kept. The hands keep one more: a piece only one stronger,
  -- cheaper piece beats, since that one may be in the other hand (a sword in each hand needs the
  -- second sword even when it is dearer). A two-hander walks a frontier of its own: it never pairs
  -- with an off hand, so a cheaper, stronger one does not make a one-hander and a shield a worse
  -- pair. FRONTIER_CHECKS reads per group, a budget of its own. Not on the count-only path.
  local setPick = {}
  if money ~= nil and not skipUsable then
    local options = {}
    for _, g in ipairs(GC.ForeverUpgrades.GROUPS) do
      local p = picked[g.key]
      if p then
        local hands = g.key == "MAINHAND" or g.key == "OFFHAND"
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
      local limit, reads = C.ALT_PRICE_STEP * best.unit, 0
      for _, c in ipairs(p.now) do
        if #alts >= C.ALTS then break end
        if c.unit <= limit then
          if not skipUsable and usableOf[c.itemString] == nil then
            if reads >= C.FRONTIER_CHECKS then break end
            reads = reads + 1
          end
          if usableCandidate(c) then
            add(c)
            limit = C.ALT_PRICE_STEP * c.unit
          end
        end
      end
      out.slots[#out.slots + 1] = { group = g.key, labelKey = g.labelKey, best = best, alts = alts,
        worn = wornLink(g.key) }
      local row = { labelKey = g.labelKey }
      for k, v in pairs(best) do row[k] = v end
      out.rows[#out.rows + 1] = row
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
  return out
end

-- Stat weights: the player's own for this class, else a copy of the class's default, else none.
function GC.ForeverUpgrades.WeightsFor(prefs, classFile)
  local own = type(prefs) == "table" and type(prefs.weights) == "table" and prefs.weights[classFile] or nil
  if type(own) == "table" then return own end
  local copy = {}
  for k, v in pairs(GC.ForeverUpgrades.DEFAULT_WEIGHTS[classFile] or {}) do copy[k] = v end
  return copy
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
-- (nothing loaded yet, no colours) is asked again next time.
-- keptSpeed: a weapon's speed per item string or link, only once the tooltip has said it.
local keptInfo, keptStats, keptUsable, keptSpeed = {}, {}, {}, {}

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
    -- A weapon's speed, for DpsFactor (TooltipSpeed): a candidate's by its item string, the worn
    -- one's by its link. Kept once the tooltip said it; asked again while it says nothing.
    speed = function(s)
      if type(s) ~= "string" then return nil end
      local kept = keptSpeed[s]
      if kept then return kept end
      local v = GC.ForeverUpgrades.TooltipSpeed(s)
      if v then keptSpeed[s] = v end
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
  }
end

-- skipUsable, threaded straight through to Build: nil/false (every existing caller -- the window's
-- own Show/RefreshIfShown, /gc weights, a direct call) keeps the tooltip check exactly as before.
--
-- r.style: the rogue's style Build was given (StyleFor), from the main hand it wears unless the
-- player chose one; nil for every other class.
function GC.ForeverUpgrades.Current(skipUsable)
  if not enabled() then return nil end
  local gear, fold = GC.ForeverScan.Gear()
  if not gear then return { slots = {}, rows = {}, loading = 0, noScan = true } end
  local getStats = statsCall()
  if not getStats then return { slots = {}, rows = {}, loading = 0, noStats = true } end
  local class, prefs = classFile(), GC.ForeverScan.Prefs()
  local weights = GC.ForeverUpgrades.WeightsFor(prefs, class)
  local driver = realDriver(getStats)
  local mainID = itemIdOf(driver.equipped(16))
  local mainSub = mainID and select(3, driver.instant(mainID)) or nil
  local style = GC.ForeverUpgrades.StyleFor(prefs, class, mainSub)
  local r = GC.ForeverUpgrades.Build(gear, driver, weights, skipUsable, { style = style })
  r.at, r.weights, r.style = fold.at, weights, style
  return r
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
  local weights = GC.ForeverUpgrades.WeightsFor(prefs, class)
  if rest:lower() == "reset" then
    if type(prefs.weights) == "table" then prefs.weights[class] = nil end
    weights = GC.ForeverUpgrades.WeightsFor(prefs, class)
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
  if GC.ForeverUpgradesUI and GC.ForeverUpgradesUI.RefreshIfShown then GC.ForeverUpgradesUI.RefreshIfShown() end
end
