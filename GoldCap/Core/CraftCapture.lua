local _, GC = ...

-- A craft is an acquisition. The mats the player already paid for turn into the item he is
-- about to list, and until this module existed that transformation was invisible: the reagent
-- batches stayed on the books as stock he no longer held, and the thing he made out of them
-- had no cost at all. Every crafted position read "NO COST", and `Set cost` -- a number typed
-- by hand -- was the only way out of it.
--
-- Pure by construction, the way Core/BagStock.lua is: every WoW API call is injected by the
-- caller, so the delicate part is testable headless.
--
-- Consumption is read as the FALL in the recipe's OWN candidate reagents between the session
-- opening and closing, not as a bag walk. Three things fall out of that for free: a
-- resourcefulness refund is already netted (the mats came back before we looked), the exact
-- quality tier the player allocated names itself without our asking, and an unrelated loot
-- drop landing mid-craft cannot be mistaken for a reagent.
--
-- Nothing here estimates. A craft whose inputs are not fully costed records nothing at all --
-- see Cost below for why understating a basis is the dangerous direction.
GC.CraftCapture = {}

local MAX_EXACT = 9007199254740991

local function isExactInteger(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value ~= -math.huge and value == math.floor(value)
    and value >= 0 and value <= MAX_EXACT
end

local function isPositiveInteger(value)
  return isExactInteger(value) and value > 0
end

-- { [itemID] = quantity } -> a stable array. Stable because the order reaches SavedVariables
-- through the batches this plans, and pairs() order is not reproducible between sessions.
local function sortedTotals(totals)
  local out = {}
  for itemID, quantity in pairs(totals) do
    out[#out + 1] = { itemID = itemID, quantity = quantity }
  end
  table.sort(out, function(left, right) return left.itemID < right.itemID end)
  return out
end

--- What one crafting session produced and what it cost in materials.
--
-- session = {
--   recipe  = { recipeID, outputItemID, isRecraft, candidates = { [itemID] = true } },
--   before  = { [itemID] = count },  -- the candidates, counted when the session opened
--   after   = { [itemID] = count },  -- the same ids, counted when it closed
--   results = { { itemID, quantity, isEnchant }, ... },  -- TRADE_SKILL_ITEM_CRAFTED_RESULT
-- }
--
-- Returns { outputs, consumed }, each a sorted array of { itemID, quantity }, or nil plus a
-- reason. Every refusal is deliberate: "no cost" is what the Sell tab says today, and it is a
-- correct answer. A guessed one is not.
function GC.CraftCapture.Plan(session)
  if type(session) ~= "table" then return nil, "no-recipe" end
  local recipe, before, after = session.recipe, session.before, session.after
  if type(recipe) ~= "table" or type(recipe.candidates) ~= "table"
      or type(before) ~= "table" or type(after) ~= "table"
      or type(session.results) ~= "table" then
    return nil, "no-recipe"
  end

  -- A recraft spends mats to change an item the player already owns. There are no new units,
  -- so a batch here would be stock that does not exist.
  if recipe.isRecraft == true then return nil, "recraft" end

  -- A recipe whose output the client cannot name is prospecting, milling or salvage: one input
  -- becomes several unrelated items, and splitting one cost across them by unit count would
  -- say a rare gem cost the same as a common one. That needs a value-share decision, not a
  -- default.
  if not isPositiveInteger(recipe.outputItemID) then return nil, "random-output" end

  local produced = {}
  for _, result in ipairs(session.results) do
    -- An enchant is applied, not held; with no item there is no position to cost. A result
    -- carrying no item id is the same case (Artisan's Mettle and friends arrive this way).
    if type(result) == "table" and result.isEnchant ~= true
        and isPositiveInteger(result.itemID) and isPositiveInteger(result.quantity) then
      local running = (produced[result.itemID] or 0) + result.quantity
      if not isExactInteger(running) then return nil, "bad-counts" end
      produced[result.itemID] = running
    end
  end
  local outputs = sortedTotals(produced)
  if #outputs == 0 then return nil, "no-output" end

  local spent = {}
  for itemID in pairs(recipe.candidates) do
    local opened, closed = before[itemID], after[itemID]
    -- A candidate the counts do not cover means the snapshot and the recipe disagree, and a
    -- reagent silently priced at zero is exactly the understatement this module exists to
    -- avoid.
    if not isExactInteger(opened) or not isExactInteger(closed) then return nil, "bad-counts" end
    if opened > closed then spent[itemID] = opened - closed end
  end
  local consumed = sortedTotals(spent)
  if #consumed == 0 then return nil, "no-consumption" end

  return { outputs = outputs, consumed = consumed }
end
