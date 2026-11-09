-- The selling rules of the groups the player follows on goldcap.gg. The site sends a followed
-- group's members as price caps, and each cap may point (`r`, 1-based in the file) at one of the
-- top-level `rules`: { n = name, id = the group's slug, p = flip|gather|craft|stock, d = 12|24|48
-- hours, q = 1 for one at a time, fp = floor as a percent of usual, s = percent cheaper per unsold
-- round, and for a subgroup only pi = its parent group's slug, pn = the parent's name, cn = the
-- subgroup's own short label }. The cap itself carries the usual price `u` and, for a craft group, the cost to craft `f`.
-- The Companion writes all of it into GoldCap_AppRuns (Core/Caps.lua reads the same caps for
-- DEALS). Both games load it (WoW: Forever too), and so do SellRounds and the returns log
-- (Core/MailReturns.lua); the mail, bank and Hoard files that read it stay retail only. A caller of
-- any of those still asks `if GC.SellRounds` and the like.
--
-- `d` is the rule's duration in HOURS OF THE GAME IT IS FOR: 12, 24 or 48 on retail, 2, 8 or 24 on
-- WoW: Forever, whose auction house offers those three (AUCTION_DURATION_ONE to THREE, index 1 to
-- 3). The one place that turns hours into the index the posting calls take is `hoursFor` below;
-- an hour count the game does not offer makes the rule unreadable, as any other bad field does.
--
-- The name is the group's in the language of the player's newest follow, so it can change; the id
-- (lowercase letters, digits, `_` and `-`, 1 to 80 of them; anything else is read as no id) does
-- not. An older Companion's file has no id. The parent's slug `pi` is read the same way.
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

M.durationByItem = {}

local PLAYS = { flip = true, gather = true, craft = true, stock = true }
local RETAIL_HOURS = { 12, 24, 48 }
local FOREVER_HOURS = { 2, 8, 24 }
local HOURS_TO_INDEX = {
  [RETAIL_HOURS] = { [12] = 1, [24] = 2, [48] = 3 },
  [FOREVER_HOURS] = { [2] = 1, [8] = 2, [24] = 3 },
}
M.RETAIL_HOURS, M.FOREVER_HOURS = RETAIL_HOURS, FOREVER_HOURS

-- The three hour counts this client's auction house offers, shortest first. Read at the call, as
-- every game gate in the addon is (GC.Game.IsForever on the passport).
local function hoursFor()
  local game = GC.Game
  if game and game.IsForever and game.IsForever(game.Passport and game.Passport()) then return FOREVER_HOURS end
  return RETAIL_HOURS
end

-- The posting index (1 to 3) for a rule's hours on this client, or nil.
function M.IndexOfHours(hours)
  return HOURS_TO_INDEX[hoursFor()][hours]
end
-- itemID -> { rule = the readable rule as the file has it, l, u, f }, rebuilt by Adopt.
local byItem = {}
-- Counts the Adopts that changed something, for a reader that caches what it built from the groups
-- (Core/ForeverDeals.lua).
M.rev = 0

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

-- The group's id as the site sends it, or nil: an older Companion's file has none.
local function groupId(v)
  if type(v) == "string" and #v <= 80 and v:find("^[a-z0-9_%-]+$") then return v end
  return nil
end

-- A non-empty string, or nil.
local function label(v)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

local function readableRule(rule)
  return type(rule) == "table" and type(rule.n) == "string" and rule.n ~= ""
    and PLAYS[rule.p] == true and M.IndexOfHours(rule.d) ~= nil
end

local function sameEntry(a, b)
  if a.l ~= b.l or a.u ~= b.u or a.f ~= b.f or a.c ~= b.c then return false end
  local x, y = a.rule, b.rule
  return x.n == y.n and x.id == y.id and x.p == y.p and x.d == y.d and x.q == y.q and x.fp == y.fp and x.s == y.s
    and x.pi == y.pi and x.pn == y.pn and x.cn == y.cn
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
              rule = { n = rule.n, id = groupId(rule.id), p = rule.p, d = rule.d, q = rule.q, fp = rule.fp,
                s = rule.s, pi = groupId(rule.pi), pn = label(rule.pn), cn = label(rule.cn) },
              l = math.max(0, math.floor(l)),
              -- The group's own price for the item, which WoW: Forever's board holds a lot to
              -- (Followed below).
              c = math.floor(c),
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
  if changed then M.rev = M.rev + 1 end
  local durations = M.durationByItem
  for id in pairs(durations) do durations[id] = nil end
  for id, entry in pairs(byItem) do durations[id] = M.IndexOfHours(entry.rule.d) end
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
    durationIndex = M.IndexOfHours(raw.d),
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

-- The followed group an item belongs to, or nil: the same first cap that decides the rule decides
-- the group. Answers the group's key and its name. The key is the group's id, else (an older
-- Companion's file, or one made by hand) its name: the GoldCap Hoard (UI/HoardFrame.lua) keeps a
-- group's count by the key, so a follow in another language or a renamed list keeps it, and shows
-- the name.
--
-- A subgroup also answers its parent's key and name and its own short name (`cn`, else the whole
-- name), for the bank window to fold groups sharing a parent into a folder. A folder needs a name,
-- so a rule with a good `pi` but no `pn` has no parent at all: all three are nil, as they are for
-- a top group and for a malformed `pi`.
function M.GroupOf(itemID)
  local entry = byItem[itemID]
  if not entry then return nil end
  local rule = entry.rule
  local key, name = rule.id or rule.n, rule.n
  if rule.pi and rule.pn then return key, name, rule.pi, rule.pn, rule.cn or name end
  return key, name
end

-- The followed group's own offer for an item: its name, the group's price per unit and the usual
-- price the site worked it out from (nil without one). nil when no followed group holds the item.
-- WoW: Forever's board marks a row of such an item and measures it against `usual` (Core/ForeverDeals.lua).
function M.Followed(itemID)
  local entry = byItem[itemID]
  if not entry then return nil end
  return entry.rule.n, entry.c, entry.u
end

-- Whether any followed group reached the addon: false with no Companion file, an old one, or no
-- follow on goldcap.gg.
function M.HasGroups()
  return next(byItem) ~= nil
end

-- The rule in words, for the SELL row's tooltip. Only what applies: a floor the rule has no price
-- for (an alert cap without a usual price, a variant under the cap's level) is not named.
function M.Describe(rule)
  if type(rule) ~= "table" then return nil end
  local parts = {}
  parts[#parts + 1] = rule.perItem == 1 and GC.L["1 at a time"] or GC.L["all you have"]
  local hours = hoursFor()[rule.durationIndex]
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
