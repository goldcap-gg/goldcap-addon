local _, GC = ...

-- Where a flip sells best among the player's realms (ClickUp 869fjhvn9). goldcap.gg works out, for
-- every flip, the realms it sells on within a week and at what price (wow-auction
-- apps/api/src/lib/realmItemRoutes.ts), and the payload carries them best net first (S); this
-- module picks among them the way the site's item page does (apps/api/src/lib/whereToSell.ts):
-- the player's own realms first, and a realm they have no character on only when it nets notably
-- more. Pure: the caller hands in the spots, the realms and this realm's id.
GC.SellRoute = {}

-- A realm with no character is worth naming when it nets this much more than the best of the
-- player's realms, in both senses at once. The site's NOTABLE_GAIN_RATIO and NOTABLE_GAIN_MIN_COPPER.
GC.SellRoute.SUGGEST_RATIO = 1.25
GC.SellRoute.SUGGEST_MIN_COPPER = 5000000
-- Another of the player's realms is worth carrying a flip to when it nets this much more than this
-- one: a trip through the Warband Bank and a fresh deposit for a few gold is not.
GC.SellRoute.CARRY_RATIO = 1.10
GC.SellRoute.CARRY_MIN_COPPER = 1000000
-- "Among the 5 cheapest" says something only over this many realms: five of six says nothing.
GC.SellRoute.CHEAP_MIN_REALMS = 10

--- A realm name as the payload's C section keys it, and as GetRealmName() is keyed to find it:
--- ASCII letters lowered, digits kept, the rest of ASCII (spaces, apostrophes, hyphens) dropped,
--- every other byte kept as it is. nil for nothing left. The site's realmNameKey, byte for byte.
function GC.SellRoute.Key(name)
  if type(name) ~= "string" then return nil end
  local out = {}
  for i = 1, #name do
    local b = name:byte(i)
    if b >= 65 and b <= 90 then
      out[#out + 1] = string.char(b + 32)
    elseif (b >= 48 and b <= 57) or (b >= 97 and b <= 122) or b >= 128 then
      out[#out + 1] = string.char(b)
    end
  end
  if #out == 0 then return nil end
  return table.concat(out)
end

--- What a sale at `list` copper brings after the auction house's 5% cut, rounded half up as the
--- site rounds it (applyAhCut).
function GC.SellRoute.Net(list)
  return math.floor(list * 0.95 + 0.5)
end

--- The connected realms of `region` the account has a character on: every "Name-Realm" the gold
--- readings (GC.Ledger.GetGold) carry for that region, through `idByKey` (GC.Data.RealmIdByKey),
--- and `hereId`. realmId -> the realm as the player's characters call it ("Tarren Mill", where the
--- payload calls the market "Dentarg"; the most read one when two share a market), or true for this
--- realm with no character reading. A realm the payload does not know is left out.
function GC.SellRoute.Mine(points, region, idByKey, hereId)
  local mine, reads = {}, {}
  if hereId then mine[hereId] = true end
  for _, point in ipairs(points or {}) do
    local realm = type(point.char) == "string" and point.region == region and point.char:match("^[^-]+%-(.+)$")
    local key = realm and GC.SellRoute.Key(realm)
    local id = key and idByKey(key)
    if id then
      reads[realm] = (reads[realm] or 0) + 1
      local held = mine[id]
      if type(held) ~= "string" or reads[realm] > reads[held] then mine[id] = realm end
    end
  end
  return mine
end

--- Where a flip with these `spots` (GC.Data.SellSpots: best net first) sells, for a player with
--- characters on the realms in `mine`, standing on `hereId`:
---   here     this realm's spot, nil when it does not sell here within a week
---   best     the best of the player's realms, this one included
---   suggest  the best realm they have no character on, only when it nets SUGGEST_RATIO times and
---            SUGGEST_MIN_COPPER more than `best` (than nothing, when none of theirs sells it)
--- nil without spots.
function GC.SellRoute.Pick(spots, mine, hereId)
  if type(spots) ~= "table" or #spots == 0 then return nil end
  local pick = {}
  for _, s in ipairs(spots) do
    if s.realmId == hereId then pick.here = s end
    if not pick.best and mine[s.realmId] then pick.best = s end
  end
  local bestNet = pick.best and GC.SellRoute.Net(pick.best.list) or 0
  for _, s in ipairs(spots) do
    if not mine[s.realmId] then
      local net = GC.SellRoute.Net(s.list)
      if net >= bestNet * GC.SellRoute.SUGGEST_RATIO and net - bestNet >= GC.SellRoute.SUGGEST_MIN_COPPER then
        pick.suggest = s
      end
      break
    end
  end
  return pick
end

--- The spot to sell a flip on: the best of the player's realms when it is worth the trip from here
--- (CARRY_RATIO and CARRY_MIN_COPPER more, or it does not sell here within a week), else here. nil
--- when none of the player's realms sells it.
function GC.SellRoute.Target(pick)
  if not (pick and pick.best) then return nil end
  local best, here = pick.best, pick.here
  if not here or best == here then return best end
  local bestNet, hereNet = GC.SellRoute.Net(best.list), GC.SellRoute.Net(here.list)
  if bestNet >= hereNet * GC.SellRoute.CARRY_RATIO and bestNet - hereNet >= GC.SellRoute.CARRY_MIN_COPPER then
    return best
  end
  return here
end

--- Whether a lot at `unit` copper is among the five cheapest realms to buy the flip on
--- (GC.Data.CheapRealms), over CHEAP_MIN_REALMS realms or more.
function GC.SellRoute.IsCheap(unit, cheap)
  return type(unit) == "number" and type(cheap) == "table" and cheap.realms >= GC.SellRoute.CHEAP_MIN_REALMS
    and unit <= cheap.floor5th
end

--- What to move through the Warband Bank at a bank on this realm, from what sits in the bags
--- (`bagItems`) and in the Warband Bank's tabs (`bankItems`): one entry a stack,
--- { itemID, bag, slot, count, name, icon, ilvl?, wue? }, `wue` for one Warbound until equipped.
--- opts: hereId, routeFor(itemID) (ForItem), levelFor(itemID) (GC.Data.FlipLevel).
--- Answers { putIn, takeOut, stuck }, a row an item, its stacks' slots in `locations`, the
--- most valuable first:
---   putIn    in the bags, and it sells notably better on another of the player's realms (Target)
---   takeOut  in the Warband Bank, and it sells best here
---   stuck    Warbound until equipped: the auction house refuses it on every realm
--- Gear under the level its price is for (a 610 of a flip priced at 639) is left where it is: the
--- route's prices are not its prices.
function GC.SellRoute.CarryPlan(bagItems, bankItems, opts)
  local plan = { putIn = {}, takeOut = {}, stuck = {} }
  local hereId = opts.hereId
  if not hereId then return plan end
  local rows = {}
  local function add(list, kind, e, spot)
    local key = kind .. ":" .. e.itemID
    local row = rows[key]
    if not row then
      row = { itemID = e.itemID, name = e.name, icon = e.icon, count = 0, locations = {}, spot = spot }
      rows[key] = row
      list[#list + 1] = row
    end
    row.count = row.count + (e.count or 1)
    row.locations[#row.locations + 1] = { bag = e.bag, slot = e.slot }
  end
  local function walk(items, inBank)
    for _, e in ipairs(items or {}) do
      local level = opts.levelFor(e.itemID)
      local pick = (not level or (e.ilvl or 0) >= level) and opts.routeFor(e.itemID) or nil
      local target = GC.SellRoute.Target(pick)
      if pick and e.wue then
        add(plan.stuck, "stuck", e, target)
      elseif target and not inBank and target.realmId ~= hereId then
        add(plan.putIn, "in", e, target)
      elseif target and inBank and target.realmId == hereId then
        add(plan.takeOut, "out", e, target)
      end
    end
  end
  walk(bagItems, false)
  walk(bankItems, true)
  local function worth(row) return row.spot and row.spot.list * row.count or 0 end
  for _, list in ipairs({ plan.putIn, plan.takeOut }) do
    table.sort(list, function(a, b)
      if worth(a) ~= worth(b) then return worth(a) > worth(b) end
      return a.itemID < b.itemID
    end)
  end
  return plan
end

--- How soon a sale is due, in the site's words (apps/web lib/items/whereToSell.ts's sellDays).
function GC.SellRoute.PaceText(days)
  if days < 1 then return GC.L["sells within a day"] end
  local n = math.floor(days + 0.5)
  if n == 1 then return GC.L["sells in about 1 day"] end
  return (GC.L["sells in about %d days"]):format(n)
end

--- What to tell the player about a pick, a line each: where to sell it (Target), at what list price
--- and how soon, then a realm with no character when it pays notably more. `nameOf(realmId)` names
--- a realm (GC.SellRoute.RealmName); a realm it cannot name is not mentioned. Empty without a pick.
function GC.SellRoute.Lines(pick, nameOf)
  local lines = {}
  local target = GC.SellRoute.Target(pick)
  if target then
    local money, pace = GC.Util.FormatMoney(target.list), GC.SellRoute.PaceText(target.days)
    if target == pick.here then
      lines[#lines + 1] = (GC.L["Sell here for %s, %s"]):format(money, pace)
    elseif nameOf(target.realmId) then
      lines[#lines + 1] = (GC.L["Sell on %s for %s, %s"]):format(nameOf(target.realmId), money, pace)
    end
  end
  local suggest = pick and pick.suggest
  if suggest and nameOf(suggest.realmId) then
    lines[#lines + 1] = (GC.L["Pays more on %s, where you have no character: %s, %s"]):format(
      nameOf(suggest.realmId), GC.Util.FormatMoney(suggest.list), GC.SellRoute.PaceText(suggest.days))
  end
  return lines
end

--- "Among the 5 cheapest of N realms", for a flip whose lot here IsCheap.
function GC.SellRoute.CheapText(cheap)
  return (GC.L["Among the 5 cheapest of %d realms"]):format(cheap.realms)
end

-- How soon, short, for a cell beside a label.
local function shortPace(days)
  if days < 1 then return GC.L["under a day"] end
  local n = math.floor(days + 0.5)
  if n == 1 then return GC.L["about 1 day"] end
  return (GC.L["about %d days"]):format(n)
end

--- The value of a Check panel route row (Core/CheckVerdict.lua's sellOn, betterOn, cheapRealms), at
--- `form` 1 whole ("Kazzak · 2,200g · about 2 days"), 2 without the pace, 3 the realm alone: the
--- panel steps down until it fits its cell, since a cut word is never drawn. nil past the last form.
function GC.SellRoute.FactText(fact, form)
  if fact.id == "cheapRealms" then
    return form == 1 and (GC.L["top 5 of %d"]):format(fact.count) or nil
  end
  local realm = fact.here and GC.L["this realm"] or fact.realm
  if form == 1 then return ("%s · %s · %s"):format(realm, GC.Util.FormatMoney(fact.copper), shortPace(fact.days)) end
  if form == 2 then return ("%s · %s"):format(realm, GC.Util.FormatMoney(fact.copper)) end
  if form == 3 then return realm end
  return nil
end

-- The client's side: this realm and the player's realms as the payload knows them, and the pick
-- for an item. Both realms are worked out once a session: the payload is adopted at load and the
-- realm never changes while the game runs. A realm the payload does not name (no C section, a
-- payload for another region, WoW: Forever) leaves every answer below nil.

--- The connected realm this character stands on, or nil.
function GC.SellRoute.HereId()
  if GC.SellRoute._here == nil then
    local ok, name = pcall(_G.GetRealmName)
    local key = ok and GC.SellRoute.Key(name) or nil
    GC.SellRoute._here = key and GC.Data.RealmIdByKey and GC.Data.RealmIdByKey(key) or false
  end
  return GC.SellRoute._here or nil
end

--- The connected realms the account has characters on (Mine), this one included.
function GC.SellRoute.MyRealms()
  if not GC.SellRoute._mine then
    local region = GC.Data.ClientRegion and GC.Data.ClientRegion() or nil
    local points = GC.Ledger and GC.Ledger.GetGold and GC.Ledger.GetGold() or {}
    GC.SellRoute._mine = GC.SellRoute.Mine(points, region, GC.Data.RealmIdByKey, GC.SellRoute.HereId())
  end
  return GC.SellRoute._mine
end

--- A realm's name for the player: one of theirs as their characters call it, any other as the
--- payload names its market (GC.Data.RealmName). nil for a realm the payload does not know.
function GC.SellRoute.RealmName(realmId)
  local known = GC.SellRoute.MyRealms()[realmId]
  if type(known) == "string" then return known end
  return GC.Data.RealmName and GC.Data.RealmName(realmId) or nil
end

--- Pick's answer for an item from this character's seat, or nil.
function GC.SellRoute.ForItem(itemID)
  local spots = GC.Data.SellSpots and GC.Data.SellSpots(itemID)
  local here = spots and GC.SellRoute.HereId()
  if not here then return nil end
  return GC.SellRoute.Pick(spots, GC.SellRoute.MyRealms(), here)
end
