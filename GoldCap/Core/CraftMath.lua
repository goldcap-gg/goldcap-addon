local _, GC = ...

-- Crafting in the profession window (retail): what one craft of a recipe costs in reagents, what
-- it sells for after the auction house cut, and the profit; the slow mark, and the order the Worth
-- crafting list reads in, which keeps only the recipes that make a profit.
--
-- Pure: every price is a function the caller hands in (Services/CraftClient.lua's UnitOf and
-- SellOf), in copper. A recipe is the snapshot CraftClient makes:
--   { recipeID, name, per, output, outputs = { itemID, ... }, slots = { Slot, ... } }
--   Slot: { slotIndex, q, ids = { itemID, ... } } (lowest quality first), or { slotIndex, q, currency }
-- and `open` is what the profession window shows for it (CraftClient.OpenRecipe):
--   { alloc = { [slotIndex] = { { itemID, q }, ... } }, output = itemID }
--
-- All or nothing, as Core/CraftCapture.lua is: a reagent or a crafted item with no price makes no
-- figure at all, only the list of what is missing. A guessed cost would print a profit nobody can
-- make, and a reagent priced at zero is the guess that does it.
GC.CraftMath = GC.CraftMath or {}
local M = GC.CraftMath

-- The auction house keeps 5% of a sale: the same cut Core/DealMath.lua's Measure takes.
local SELL_SHARE = 0.95

local function price(fn, id)
  local v = type(id) == "number" and fn(id) or nil
  if type(v) == "number" and v == v and v >= 0 then return v end
  return nil
end

--- The reagent a slot is bought as: the cheapest quality that has a price, the lower quality on a
--- tie. Returns itemID, unit price; nothing for a currency slot or when no quality has a price.
function M.SlotChoice(slot, unitOf)
  if type(slot) ~= "table" or type(slot.ids) ~= "table" or type(unitOf) ~= "function" then return nil end
  local bestID, bestUnit
  for _, id in ipairs(slot.ids) do
    local u = price(unitOf, id)
    if u and (bestUnit == nil or u < bestUnit) then bestID, bestUnit = id, u end
  end
  if bestID == nil then return nil end
  return bestID, bestUnit
end

-- The allocation the window holds for a slot, when it covers the whole slot.
local function coveringAlloc(open, slot)
  local alloc = type(open) == "table" and type(open.alloc) == "table" and open.alloc[slot.slotIndex] or nil
  if type(alloc) ~= "table" then return nil end
  local total = 0
  for _, a in ipairs(alloc) do total = total + (tonumber(a.q) or 0) end
  if total < (slot.q or 0) or total <= 0 then return nil end
  return alloc
end

--- What one craft costs and sells for. Returns { cost, sells, profit }, or { missing = { ... } }
--- naming each reagent ({ itemID } or { currencyID }) and then the crafted item with no price, in
--- slot order. Never both.
---
--- A slot the window has fully allocated costs exactly what is allocated; an allocated reagent with
--- no price is missing, never priced at another quality the player did not pick. Any other slot
--- (nothing allocated, or not enough to craft) is priced at its cheapest priced quality. The
--- crafted item is the one the window shows when it shows one, else the recipe's usual one.
function M.Profit(recipe, unitOf, sellUnitOf, open)
  local missing, cost = {}, 0
  for _, slot in ipairs(type(recipe) == "table" and recipe.slots or {}) do
    local alloc = slot.currency == nil and coveringAlloc(open, slot) or nil
    if alloc then
      for _, a in ipairs(alloc) do
        local u = price(unitOf, a.itemID)
        if u then cost = cost + u * (tonumber(a.q) or 0) else missing[#missing + 1] = { itemID = a.itemID } end
      end
    else
      local id, u = M.SlotChoice(slot, unitOf)
      if id then
        cost = cost + u * slot.q
      elseif slot.currency then
        missing[#missing + 1] = { currencyID = slot.currency }
      else
        missing[#missing + 1] = { itemID = slot.ids and slot.ids[1] }
      end
    end
  end
  local output = (type(open) == "table" and open.output) or (type(recipe) == "table" and recipe.output) or nil
  local sellUnit = price(sellUnitOf, output)
  if not sellUnit then missing[#missing + 1] = { itemID = output } end
  if #missing > 0 then return { missing = missing } end
  local sells = math.floor(sellUnit * SELL_SHARE) * math.max(1, recipe.per or 1)
  return { cost = cost, sells = sells, profit = sells - cost }
end

--- A crafted item that sells less than once a day on the market. Unknown sales are not slow.
function M.IsSlow(sold)
  return type(sold) == "number" and sold < 1
end

--- The Worth crafting order: priced rows that make a profit, by profit per craft, highest first,
--- then by name, then by recipe id. Returns ranked, unpriced, unprofitable: a row whose result is
--- missing a price is left out and counted, never ranked as 0; a priced row with no profit (0 or a
--- loss) is left out and counted too.
function M.Rank(rows)
  local ranked, unpriced, unprofitable = {}, 0, 0
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    local r = row.result
    if type(r) == "table" and type(r.profit) == "number" and r.missing == nil then
      if r.profit > 0 then ranked[#ranked + 1] = row else unprofitable = unprofitable + 1 end
    else
      unpriced = unpriced + 1
    end
  end
  table.sort(ranked, function(a, b)
    if a.result.profit ~= b.result.profit then return a.result.profit > b.result.profit end
    local an, bn = tostring(a.name or ""), tostring(b.name or "")
    if an ~= bn then return an < bn end
    return (a.recipeID or 0) < (b.recipeID or 0)
  end)
  return ranked, unpriced, unprofitable
end
