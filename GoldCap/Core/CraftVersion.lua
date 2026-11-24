local _, GC = ...

-- Crafted items sold per piece (gear, tools, bags): what the version a character makes sold for
-- this week, from what the region payload's X says each version sold for (GC.Data.CraftedVersions:
-- { [version] = { ilvl, sales, realms, median } }, version 0 for an item without ranks).
--
-- Pure. A version's price is proven by MIN_SALES sales on MIN_REALMS realms or more; fewer is a
-- hint, never a price. An item's listed median says nothing of what a version sells for, so
-- nothing here falls back to it.
GC.CraftVersion = GC.CraftVersion or {}
local V = GC.CraftVersion

V.MIN_SALES = 5
V.MIN_REALMS = 3

--- Whether a version's sales prove its price.
function V.Proven(entry)
  return type(entry) == "table" and type(entry.median) == "number" and entry.median > 0
    and (tonumber(entry.sales) or 0) >= V.MIN_SALES and (tonumber(entry.realms) or 0) >= V.MIN_REALMS
end

-- The item's proven versions but `skip`, best rank first.
local function othersOf(versions, skip)
  local out = {}
  for rank, e in pairs(versions or {}) do
    if rank ~= skip and V.Proven(e) then
      out[#out + 1] = { rank = rank, ilvl = e.ilvl, median = e.median, sales = e.sales }
    end
  end
  table.sort(out, function(a, b) return a.rank > b.rank end)
  return out
end

--- What a craft of `rank` (nil: not known) sells on: { kind, rank, ilvl, sales, realms, median,
--- others }. `kind`: "proven" (its version's sales prove its price), "thin" (it sold, too few times
--- or on too few realms), "unsold" (its version did not sell), "unknown" (the rank is not known),
--- "nosales" (the item sold nothing this week) or "nodata" (no versions to read). An item whose
--- only version is 0 has no ranks and needs none. `others`: the item's other proven versions.
function V.Pick(versions, rank)
  if type(versions) ~= "table" then return { kind = "nodata", others = {} } end
  if next(versions) == nil then return { kind = "nosales", others = {} } end
  if rank == nil and versions[0] ~= nil and next(versions, next(versions)) == nil then rank = 0 end
  if rank == nil then return { kind = "unknown", others = othersOf(versions) } end
  local e = versions[rank]
  local basis = { rank = rank, others = othersOf(versions, rank) }
  if type(e) ~= "table" or (tonumber(e.sales) or 0) <= 0 then
    basis.kind = "unsold"
    return basis
  end
  basis.kind = V.Proven(e) and "proven" or "thin"
  basis.ilvl, basis.sales, basis.realms, basis.median = e.ilvl, e.sales, e.realms, e.median
  return basis
end

--- The lowest median among the proven versions, and its version; nothing when none is proven.
function V.Cheapest(versions)
  local best, at
  for rank, e in pairs(type(versions) == "table" and versions or {}) do
    if V.Proven(e) and (best == nil or e.median < best or (e.median == best and rank < at)) then
      best, at = e.median, rank
    end
  end
  return best, at
end

--- The version whose item level is `ilvl`, and its entry; nothing for an unknown level (0) or none.
function V.ByLevel(versions, ilvl)
  if type(versions) ~= "table" or type(ilvl) ~= "number" or ilvl <= 0 then return nil end
  for rank, e in pairs(versions) do
    if type(e) == "table" and e.ilvl == ilvl then return rank, e end
  end
  return nil
end

-- What a basis says beside the item's level, `fmt` with it and `bare` without (an item level of 0 or
-- one not known).
local function withLevel(ilvl, fmt, bare, ...)
  if type(ilvl) == "number" and ilvl > 0 then return fmt:format(ilvl, ...) end
  return bare:format(...)
end

--- The lines a craft's price basis (Pick's, or Services/CraftClient.lua's SellOf) prints, in the
--- player's language, `coin` formatting copper: a proven price's sales; for no price, what is known
--- of the version made and up to three of the item's other proven versions. None for any other basis.
function V.Lines(basis, coin)
  local out = {}
  local kind = type(basis) == "table" and basis.kind or nil
  if kind == "proven" then
    -- The sales come first in this key, the item level after them.
    local known = type(basis.ilvl) == "number" and basis.ilvl > 0
    out[1] = known and GC.L["Sold %d times this week, item level %d"]:format(basis.sales, basis.ilvl)
      or GC.L["Sold %d times this week"]:format(basis.sales)
    return out
  elseif kind == "thin" then
    out[1] = withLevel(basis.ilvl, GC.L["Your version (%d) sold %d times this week, about %s"],
      GC.L["Your version sold %d times this week, about %s"], basis.sales, coin(basis.median))
  elseif kind == "unsold" then
    out[1] = withLevel(basis.ilvl, GC.L["Your version (%d) did not sell this week"], GC.L["Your version did not sell this week"])
  elseif kind == "unknown" then
    out[1] = GC.L["The game did not say which version you make"]
  elseif kind == "nosales" then
    out[1] = GC.L["No sales this week"]
  elseif kind == "nodata" then
    out[1] = GC.L["Sale prices by version come with the Companion"]
  else
    return out
  end
  for i, o in ipairs(basis.others or {}) do
    if i > 3 then break end
    if type(o.ilvl) == "number" and o.ilvl > 0 then
      out[#out + 1] = GC.L["Quality %d (%d) sells for %s"]:format(o.rank, o.ilvl, coin(o.median))
    else
      out[#out + 1] = GC.L["Quality %d sells for %s"]:format(o.rank, coin(o.median))
    end
  end
  return out
end
