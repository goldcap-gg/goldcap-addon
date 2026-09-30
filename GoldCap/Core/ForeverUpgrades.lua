local _, GC = ...

-- WoW: Forever's AH Upgrade Finder (plan 3e, growth spec D8): for each equipment slot, the
-- cheapest piece in the player's last full scan (Core/ForeverGear.lua's lots) that this character
-- can use, now or one or two levels on, and that scores higher than what it wears.
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
  TOOLTIP_CHECKS = 5,      -- tooltip reads per slot, cheapest first
  REQUEST_PER_BUILD = 100, -- item-data requests per build
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
GC.ForeverUpgrades.DEFAULT_WEIGHTS = {
  WARRIOR = { STR = 1, AGI = 0.5, STA = 0.5, AP = 0.5, DPS = 2, ARMOR = 0.01 },
  PALADIN = { STR = 1, INT = 0.4, STA = 0.5, AGI = 0.3, AP = 0.5, DPS = 2, ARMOR = 0.01 },
  ROGUE = { AGI = 1, STR = 0.5, STA = 0.4, AP = 0.5, DPS = 2, ARMOR = 0.01 },
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
-- worth is mostly effects GetItemStats does not list.
local GROUP_OF = {
  INVTYPE_HEAD = "HEAD", INVTYPE_NECK = "NECK", INVTYPE_SHOULDER = "SHOULDER", INVTYPE_CLOAK = "BACK",
  INVTYPE_CHEST = "CHEST", INVTYPE_ROBE = "CHEST", INVTYPE_WRIST = "WRIST", INVTYPE_HAND = "HANDS",
  INVTYPE_WAIST = "WAIST", INVTYPE_LEGS = "LEGS", INVTYPE_FEET = "FEET", INVTYPE_FINGER = "FINGER",
  INVTYPE_WEAPON = "MAINHAND", INVTYPE_WEAPONMAINHAND = "MAINHAND", INVTYPE_2HWEAPON = "MAINHAND",
  INVTYPE_WEAPONOFFHAND = "OFFHAND", INVTYPE_SHIELD = "OFFHAND", INVTYPE_HOLDABLE = "OFFHAND",
  INVTYPE_RANGED = "RANGED", INVTYPE_RANGEDRIGHT = "RANGED", INVTYPE_THROWN = "RANGED",
}

local function set(list)
  local out = {}
  for _, v in ipairs(list) do out[v] = true end
  return out
end

-- Classic's rules: the fallback when the tooltip cannot tell, and the only judge for a piece a few
-- levels ahead (its tooltip is red for the level anyway). Armour subclass -> the level the class
-- may wear it from (0 misc, 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield). Weapon subclass ->
-- the class can learn it (0/1 axe, 2 bow, 3 gun, 4/5 mace, 6 polearm, 7/8 sword, 10 staff, 13
-- fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand). A class not listed has no fallback.
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

function GC.ForeverUpgrades.Score(stats, weights)
  local score, parts = 0, {}
  if type(stats) ~= "table" then return score, parts end
  for token, w in pairs(weights or {}) do
    local keys = GC.ForeverUpgrades.TOKENS[token]
    if keys and type(w) == "number" and w ~= 0 then
      for _, key in ipairs(keys) do
        local v = stats[key]
        if type(v) == "number" then
          score = score + w * v
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

-- The client's tooltip for the piece, as data: false on any red line, true when it drew coloured
-- lines and none was red, nil when it cannot tell (no client call, nothing loaded, no colours).
function GC.ForeverUpgrades.TooltipUsable(itemString, api)
  if api == nil then api = _G.C_TooltipInfo end
  if type(api) ~= "table" or type(api.GetHyperlink) ~= "function" then return nil end
  local ok, data = pcall(api.GetHyperlink, itemString)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  local sawColour = false
  for _, line in ipairs(data.lines) do
    if type(line) == "table" then
      if line.leftColor or line.rightColor then sawColour = true end
      if isRed(line.leftColor) or isRed(line.rightColor) then return false end
    end
  end
  return sawColour or nil
end

local SLOT_OF = {}
for _, g in ipairs(GC.ForeverUpgrades.GROUPS) do SLOT_OF[g.key] = g.slots[1] end

local function itemIdOf(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function merged(a, b)
  local out = {}
  for k, v in pairs(a or {}) do out[k] = v end
  for k, v in pairs(b or {}) do out[k] = (out[k] or 0) + v end
  return out
end

-- skipUsable (final review 2026-09-27): the count-only path (the upgrades window is closed, so
-- nothing will render its rows) skips driver.usable's tooltip read entirely -- up to ~140
-- C_TooltipInfo.GetHyperlink calls, the priciest primitive here -- and picks straight off
-- known, the same class armour/weapon table and CanDualWield check every candidate already passed
-- to reach byGroup. The window's own render always passes false (the default): a picked row must
-- still clear the tooltip's red-line check, exactly as before.
function GC.ForeverUpgrades.Build(gear, driver, weights, skipUsable)
  local out = { rows = {}, loading = 0 }
  if type(weights) ~= "table" or next(weights) == nil then out.noWeights = true; return out end
  if type(gear) ~= "table" or type(gear.items) ~= "table" then out.noScan = true; return out end
  local level = tonumber(driver.level()) or 1
  local class = driver.classFile()
  local Score, loading = GC.ForeverUpgrades.Score, {}

  -- What the character wears, per slot. false: worn, but its stats not answered yet -- the group is
  -- skipped rather than compared against a guess.
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
          local s, p = Score(stats, weights)
          worn[slot] = { score = s, parts = p }
        end
      end
    end
    return worn[slot]
  end
  local twoHandWorn = driver.instant(itemIdOf(driver.equipped(16)) or 0) == "INVTYPE_2HWEAPON"

  -- I1: an off-hand WEAPON (not a shield or held item) needs dual-wield, which is not a red
  -- tooltip line -- ClassAllows alone would offer a mage an off-hand dagger it cannot equip.
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
      return { score = m.score + o.score, parts = merged(m.parts, o.parts) }
    end
    return wornAt(SLOT_OF[group]) or nil
  end

  -- true only on a class-table/dual-wield "yes" (skipUsable) or a tooltip check that agrees (or
  -- cannot tell, deferring to that same known flag) -- unchanged from before this file grew the
  -- skipUsable path.
  local function usableCandidate(c)
    if skipUsable then return c.known == true end
    local u = driver.usable(c.itemString)
    return u == true or (u == nil and c.known)
  end

  local byGroup = {}
  for itemID, encoded in pairs(gear.items) do
    local equipLoc, classID, subclassID = driver.instant(itemID)
    local group = GROUP_OF[equipLoc]
    if group and not (group == "OFFHAND" and twoHandWorn)
        and not (equipLoc == "INVTYPE_WEAPONOFFHAND" and not canDualWield()) then
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
              local score, parts = Score(stats, weights)
              local b = base(group, equipLoc)
              local gain = b and score - b.score or 0
              if b and score > 0 and gain > 0 and gain >= C.MIN_GAIN_SHARE * b.score then
                byGroup[group] = byGroup[group] or {}
                table.insert(byGroup[group], { group = group, itemID = itemID, itemString = str,
                  link = link or str, unit = lot.unit, gain = gain, diffs = GC.ForeverUpgrades.Diff(parts, b.parts),
                  later = minLevel > level and minLevel or nil, known = allowed == true })
              end
            end
          end
        end
      end
    end
  end

  for _, g in ipairs(GC.ForeverUpgrades.GROUPS) do
    local list = byGroup[g.key]
    if list then
      table.sort(list, function(a, b)
        if a.unit ~= b.unit then return a.unit < b.unit end
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.itemString < b.itemString
      end)
      -- skipUsable: no tooltip call to cap, so every candidate is looked at (still cheapest-gain
      -- first, from the sort above) rather than only the first TOOLTIP_CHECKS.
      local pick, checks = nil, 0
      for _, c in ipairs(list) do
        if not c.later and (skipUsable or checks < C.TOOLTIP_CHECKS) then
          if not skipUsable then checks = checks + 1 end
          if usableCandidate(c) then pick = c; break end
        end
      end
      if not pick then
        -- M4 (final review): the same tooltip check usable-now picks get, not the class table
        -- alone -- otherwise a profession-required piece a class table says nothing against (an
        -- engineering item, say) could be offered "at level N" on class rules alone.
        local laterChecks = 0
        for _, c in ipairs(list) do
          if c.later and (skipUsable or laterChecks < C.TOOLTIP_CHECKS) then
            if not skipUsable then laterChecks = laterChecks + 1 end
            if usableCandidate(c) then pick = c; break end
          end
        end
      end
      if pick then
        pick.labelKey, pick.known = g.labelKey, nil
        out.rows[#out.rows + 1] = pick
      end
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

-- The client, for Build. Every read guarded: a missing API reads as "not answered", never an error.
local function realDriver(getStats)
  local item = _G.C_Item or {}
  return {
    level = function()
      local ok, l = pcall(_G.UnitLevel, "player")
      return ok and tonumber(l) or 1
    end,
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
      local ok, name, link, _, _, minLevel = pcall(item.GetItemInfo, itemString)
      if ok and name then return tonumber(minLevel) or 0, link end
      return nil
    end,
    stats = function(s)
      local ok, t = pcall(getStats, s)
      return ok and type(t) == "table" and t or nil
    end,
    usable = function(s) return GC.ForeverUpgrades.TooltipUsable(s) end,
    requestLoad = function(itemID) pcall(item.RequestLoadItemDataByID, itemID) end,
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
function GC.ForeverUpgrades.Current(skipUsable)
  if not enabled() then return nil end
  local gear, fold = GC.ForeverScan.Gear()
  if not gear then return { rows = {}, loading = 0, noScan = true } end
  local getStats = statsCall()
  if not getStats then return { rows = {}, loading = 0, noStats = true } end
  local weights = GC.ForeverUpgrades.WeightsFor(GC.ForeverScan.Prefs(), classFile())
  local r = GC.ForeverUpgrades.Build(gear, realDriver(getStats), weights, skipUsable)
  r.at, r.weights = fold.at, weights
  return r
end

-- After every saved scan (Core/ForeverScan.lua's _QueueUpgradesUpdate): one line, only when there
-- is something. r: the scan's own already-built result, when the caller has one -- the deferred
-- post-scan update builds once and hands the same result to this and to the window's own render,
-- rather than each building its own. A direct call (a test, /gc upgrades' own paths) with no r
-- still gets a correct count from its own Current().
--
-- `said` (the scan's session record) keeps the line from repeating while the count is unchanged.
function GC.ForeverUpgrades.PrintCount(r, said)
  r = r or GC.ForeverUpgrades.Current()
  if r and #r.rows > 0 then
    if said then
      if said.upgrades == #r.rows then return end
      said.upgrades = #r.rows
    end
    GC.Print(GC.L["Upgrades for your gear on the auction house: %d. Type /gc upgrades to see them."]:format(#r.rows))
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
