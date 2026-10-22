-- The selling rules of the groups the player follows on goldcap.gg. The site sends a followed
-- group's members as price caps, and each cap may point (`r`, 1-based in the file) at one of the
-- top-level `rules`: { n = name, p = flip|gather|craft|stock, d = 12|24|48 hours, q = 1 for one
-- at a time, fp = floor as a percent of usual, s = percent cheaper per unsold round }. The cap
-- itself carries the usual price `u` and, for a craft group, the cost to craft `f`. The Companion
-- writes all of it into GoldCap_AppRuns (Core/Caps.lua reads the same caps for DEALS). Retail
-- only: GoldCap_Camelot.toc does not load this file, so every caller asks `if GC.GroupRules`.
--
-- The first cap of an item decides its rule, exactly as it decides the item's cap, so the SELL
-- chip and the DEALS row name the same group. An unreadable rule or index gives the item no rule.
--
-- A cap with an item level `l` was priced by the site at that level. A variant under it keeps the
-- rule (its name, play, duration and how many at a time) but none of the prices: a 600 is never
-- floored or stepped down from the 610's usual price. The cost to craft does not depend on the
-- level, so a craft floor stays.
--
-- `durationByItem` (itemID -> duration index 1|2|3) is a plain table refreshed in place by Adopt.
-- The deposit estimates read it inside the Post click before the protected call, where only
-- field reads belong (Core/Flips.lua's CommodityDeposit comment), never a function of ours.
local _, GC = ...
GC.GroupRules = {}
local M = GC.GroupRules

M.HOURS_TO_INDEX = { [12] = 1, [24] = 2, [48] = 3 }
M.durationByItem = {}

local PLAYS = { flip = true, gather = true, craft = true, stock = true }
local INDEX_TO_HOURS = { 12, 24, 48 }
-- itemID -> { rule = the readable rule as the file has it, l, u, f }, rebuilt by Adopt.
local byItem = {}

-- A finite number, or nil: the same guard Core/Caps.lua reads every cap field with.
local function num(v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function wholePct(v)
  v = num(v)
  if v and v % 1 == 0 and v >= 1 and v <= 100 then return v end
  return nil
end

local function readableRule(rule)
  return type(rule) == "table" and type(rule.n) == "string" and rule.n ~= ""
    and PLAYS[rule.p] == true and M.HOURS_TO_INDEX[rule.d] ~= nil
end

local function sameEntry(a, b)
  if a.l ~= b.l or a.u ~= b.u or a.f ~= b.f then return false end
  local x, y = a.rule, b.rule
  return x.n == y.n and x.p == y.p and x.d == y.d and x.q == y.q and x.fp == y.fp and x.s == y.s
end

function M.Adopt(raw)
  if raw == nil then raw = _G.GoldCap_AppRuns end
  local nextByItem, seen = {}, {}
  if type(raw) == "table" and (raw.v == 1 or raw.v == 2 or raw.v == 3) and type(raw.caps) == "table" then
    local rules = type(raw.rules) == "table" and raw.rules or {}
    for _, entry in ipairs(raw.caps) do
      if type(entry) == "table" then
        local i, c = num(entry.i), num(entry.c)
        local l = entry.l == nil and 0 or num(entry.l)
        -- The cap Core/Caps.lua keeps for the item, by its rules: readable, and the first one.
        if i and i > 0 and c and c > 0 and l and not seen[i] then
          seen[i] = true
          local r = num(entry.r)
          local rule = r and r % 1 == 0 and r >= 1 and rules[r] or nil
          if readableRule(rule) then
            local u, f = num(entry.u), num(entry.f)
            nextByItem[i] = {
              rule = { n = rule.n, p = rule.p, d = rule.d, q = rule.q, fp = rule.fp, s = rule.s },
              l = math.max(0, math.floor(l)),
              u = u and u > 0 and math.floor(u) or nil,
              f = f and f > 0 and math.floor(f) or nil,
            }
          end
        end
      end
    end
  end
  local changed = false
  for id, entry in pairs(nextByItem) do
    if not byItem[id] or not sameEntry(byItem[id], entry) then changed = true; break end
  end
  if not changed then
    for id in pairs(byItem) do
      if not nextByItem[id] then changed = true; break end
    end
  end
  byItem = nextByItem
  local durations = M.durationByItem
  for id in pairs(durations) do durations[id] = nil end
  for id, entry in pairs(byItem) do durations[id] = M.HOURS_TO_INDEX[entry.rule.d] end
  return changed
end

-- The rule for one item at one item level (nil or unknown counts as 0), as a fresh table:
-- { name, play, durationIndex, perItem, stepPct, floorPct, floorUnit, usualUnit, craftFloor }.
-- nil when no followed group's rule covers the item.
function M.RuleFor(itemID, itemLevel)
  local entry = byItem[itemID]
  if not entry then return nil end
  local raw = entry.rule
  local rule = {
    name = raw.n,
    play = raw.p,
    durationIndex = M.HOURS_TO_INDEX[raw.d],
    perItem = raw.q == 1 and 1 or nil,
    stepPct = wholePct(raw.s),
    floorPct = wholePct(raw.fp),
  }
  local below = entry.l > 0 and (num(itemLevel) or 0) < entry.l
  if entry.f then
    rule.floorUnit, rule.craftFloor = entry.f, true
  elseif entry.u and rule.floorPct and not below then
    rule.floorUnit = math.floor(entry.u * rule.floorPct / 100)
  end
  if entry.u and not below then rule.usualUnit = entry.u end
  -- A step down needs both ends: the usual price it starts from and the floor it stops at.
  if not (rule.floorUnit and rule.usualUnit) then rule.stepPct = nil end
  return rule
end

-- The rule in words, for the SELL row's tooltip. Only what applies: a floor the rule has no price
-- for (an alert cap without a usual price, a variant under the cap's level) is not named.
function M.Describe(rule)
  if type(rule) ~= "table" then return nil end
  local parts = {}
  parts[#parts + 1] = rule.perItem == 1 and GC.L["1 at a time"] or GC.L["all you have"]
  local hours = INDEX_TO_HOURS[rule.durationIndex]
  if hours then parts[#parts + 1] = (GC.L["%d h"]):format(hours) end
  if rule.floorUnit and rule.craftFloor then
    parts[#parts + 1] = GC.L["not under the cost to craft"]
  elseif rule.floorUnit and rule.floorPct then
    parts[#parts + 1] = (GC.L["not under %d%% of usual"]):format(rule.floorPct)
  end
  if rule.stepPct then
    parts[#parts + 1] = (GC.L["%d%% cheaper each time it comes back"]):format(rule.stepPct)
  end
  return table.concat(parts, ", ")
end
