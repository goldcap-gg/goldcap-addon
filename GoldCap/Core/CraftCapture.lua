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
-- `recipe.outputs` is the set of item ids this recipe can make -- the declared output and its
-- quality variants. Absent, only the declared id counts.
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

  -- What this recipe is allowed to have made: its declared output and, when the client could
  -- name them, that output's quality variants. TRADE_SKILL_ITEM_CRAFTED_RESULT also fires for
  -- things that are not the craft -- a first-craft reward, a knowledge item -- and counting one
  -- as a produced unit would spread the session's materials over more units than it made, and
  -- so understate what each one cost. Falling back to the declared id alone is the conservative
  -- read: a quality variant the client did not name is refused, never guessed at.
  local allowed = type(recipe.outputs) == "table" and recipe.outputs or { [recipe.outputItemID] = true }

  local produced, ignored = {}, 0
  for _, result in ipairs(session.results) do
    -- An enchant is applied, not held; with no item there is no position to cost. A result
    -- carrying no item id is the same case.
    if type(result) == "table" and result.isEnchant ~= true
        and isPositiveInteger(result.itemID) and isPositiveInteger(result.quantity) then
      if allowed[result.itemID] then
        local running = (produced[result.itemID] or 0) + result.quantity
        if not isExactInteger(running) then return nil, "bad-counts" end
        produced[result.itemID] = running
      else
        ignored = ignored + 1
      end
    end
  end
  local outputs = sortedTotals(produced)
  if #outputs == 0 then return nil, "no-output" end

  local spent = {}
  for itemID in pairs(recipe.candidates) do
    -- An id that is both a reagent and an output nets against itself in the delta: what went
    -- in is hidden by what came out, and no amount of arithmetic here recovers either.
    if allowed[itemID] then return nil, "output-is-reagent" end
    local opened, closed = before[itemID], after[itemID]
    -- A candidate the counts do not cover means the snapshot and the recipe disagree, and a
    -- reagent silently priced at zero is exactly the understatement this module exists to
    -- avoid.
    if not isExactInteger(opened) or not isExactInteger(closed) then return nil, "bad-counts" end
    if opened > closed then spent[itemID] = opened - closed end
  end
  local consumed = sortedTotals(spent)
  if #consumed == 0 then return nil, "no-consumption" end

  return { outputs = outputs, consumed = consumed, ignored = ignored }
end

--- What the reagents a session consumed actually cost the player.
--
-- `batchesFor(itemID)` hands back that item's active acquisition batches; the caller filters
-- GC.Acquisitions.GetActive, so scope (character and region) is decided where it always is.
--
-- Returns { total, reagents = { { itemID, quantity, positionKey, plan } } } or nil + a reason.
--
-- ALL OR NOTHING. A batch carries ONE unit cost for all of its units, so a craft whose inputs
-- are only partly costed cannot be recorded without either understating that unit cost or
-- inventing a quantity split that never happened. Understating is the dangerous direction:
-- Core/Flips.lua turns a cost basis into `breakeven`, and RepostAdvice turns `belowCost` into
-- "hold, you would sell at a loss". A basis that is merely plausible makes GoldCap give advice
-- on a number nobody paid. So a reagent the player gathered, looted or bought from a vendor
-- leaves the whole craft uncosted -- which is exactly what the Sell tab says today.
function GC.CraftCapture.Cost(consumed, batchesFor)
  if type(consumed) ~= "table" or #consumed == 0 or type(batchesFor) ~= "function" then
    return nil, "uncosted"
  end

  local reagents, total = {}, 0
  for _, line in ipairs(consumed) do
    if not isPositiveInteger(line.itemID) or not isPositiveInteger(line.quantity) then
      return nil, "uncosted"
    end
    local batches = batchesFor(line.itemID)
    if type(batches) ~= "table" or #batches == 0 then return nil, "uncosted" end

    -- The key comes off the batches the purchase already wrote, and is never re-derived here.
    -- C_AuctionHouse.GetItemKeyInfo is the only authority on commodity-versus-item identity
    -- and it answers nothing away from the auction house -- which is exactly where crafting
    -- happens. Batches that disagree mean we cannot tell which variant was consumed.
    local positionKey
    for _, candidate in ipairs(batches) do
      if type(candidate.positionKey) ~= "string" or candidate.positionKey == "" then
        return nil, "ambiguous-identity"
      end
      if positionKey == nil then
        positionKey = candidate.positionKey
      elseif positionKey ~= candidate.positionKey then
        return nil, "ambiguous-identity"
      end
    end

    local plan = GC.Acquisitions.Allocate(batches, line.quantity)
    if not plan or plan.coverage ~= "COMPLETE" then return nil, "uncosted" end
    if not isExactInteger(plan.knownCost) or total > MAX_EXACT - plan.knownCost then
      return nil, "overflow"
    end
    total = total + plan.knownCost
    reagents[#reagents + 1] = { itemID = line.itemID, quantity = line.quantity,
      positionKey = positionKey, plan = plan }
  end

  -- Mats that are on record as having cost nothing give a basis of zero, and a zero basis
  -- makes every price look like pure profit. Acquisitions.Record refuses a non-positive total
  -- anyway; refusing here names the reason.
  if not isPositiveInteger(total) then return nil, "uncosted" end
  return { total = total, reagents = reagents }
end

--- Spend the reagents, record what the session made.
--
-- `sessionKey` is one string per crafting session. Every consume keys its evidence off it, and
-- so does every output batch, which makes the whole settlement idempotent for free:
-- Acquisitions.Consume refuses a repeated evidence key outright, and Record hands back the
-- batch that key already wrote.
--
-- Returns { batches, unitCost, total } or nil + a reason.
function GC.CraftCapture.Settle(plan, costing, context, at, sessionKey, outputKeyFor)
  if type(plan) ~= "table" or type(costing) ~= "table" or type(plan.outputs) ~= "table"
      or type(costing.reagents) ~= "table" or not isPositiveInteger(costing.total)
      or type(context) ~= "table" or not isExactInteger(at)
      or type(sessionKey) ~= "string" or sessionKey == "" then
    return nil, "bad-input"
  end

  local units = 0
  for _, output in ipairs(plan.outputs) do
    if not isPositiveInteger(output.itemID) or not isPositiveInteger(output.quantity) then
      return nil, "bad-input"
    end
    units = units + output.quantity
  end
  if units <= 0 then return nil, "bad-input" end

  -- One unit cost for the whole session: the same mats went into every craft, whatever quality
  -- came out, so total / units is right for each output id. Checked BEFORE anything is spent
  -- -- a craft settled halfway, with the mats written off and the output still uncosted, would
  -- be worse than the no-cost state this replaces.
  local unitCost = math.floor(costing.total / units)
  if unitCost < 1 then return nil, "sub-copper" end
  local remainder = costing.total - unitCost * units

  for _, reagent in ipairs(costing.reagents) do
    local spent = GC.Acquisitions.Consume(reagent.positionKey, reagent.quantity,
      sessionKey .. ":" .. reagent.itemID, at, context, reagent.plan)
    if not spent then return nil, "consume-failed" end
  end

  -- The remainder rides on the first output, so the batches still sum to exactly what was
  -- spent: copper is neither invented nor lost on the way in.
  local batches = {}
  for index, output in ipairs(plan.outputs) do
    local total = unitCost * output.quantity + (index == 1 and remainder or 0)
    local batch = GC.Acquisitions.Record({
      source = "craft", itemID = output.itemID, quantity = output.quantity, total = total,
      acquiredAt = at,
      positionKey = type(outputKeyFor) == "function" and outputKeyFor(output.itemID) or nil,
      character = context.char, region = context.region,
      evidenceKey = sessionKey .. ":out:" .. output.itemID,
    })
    if batch then batches[#batches + 1] = batch end
  end
  if #batches == 0 then return nil, "record-failed" end
  return { batches = batches, unitCost = unitCost, total = costing.total }
end

--- The auction identity to stamp on a crafted batch, or nil to leave it keyless.
--
-- Crafting happens away from the auction house, and C_AuctionHouse.GetItemKeyInfo -- the only
-- authority on commodity-versus-item identity -- answers nothing there. So identity comes from
-- evidence in two steps and is never guessed at:
--
--  1. the item's OWN active batches, if they agree on a key (it has been bought or made before);
--  2. `known`, the GC.db.commodityByItem answer that classifyBagItem remembered the first time
--     the auction house told us -- true means a commodity, which keys itself from the id alone.
--
-- Anything else stays keyless. Acquisitions.Record accepts that, and Acquisitions.BindItemOnly
-- binds it the next time the player opens the auction house. A cached `false` is keyless too:
-- gear's key needs the item link's bonus ids, which a bag count does not carry. Guessing is
-- what filed one item under two position keys before.
function GC.CraftCapture.OutputKey(itemID, known, existing)
  if not isPositiveInteger(itemID) then return nil end

  local fromBatches
  for _, batch in ipairs(type(existing) == "table" and existing or {}) do
    if type(batch) == "table" and batch.itemID == itemID
        and type(batch.positionKey) == "string" and batch.positionKey ~= "" then
      if fromBatches == nil then
        fromBatches = batch.positionKey
      elseif fromBatches ~= batch.positionKey then
        return nil
      end
    end
  end
  if fromBatches then return fromBatches end

  if type(known) == "table" and known[itemID] == true then
    return ("commodity:%d"):format(itemID)
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- The session: one press of Create or Create All.
--
-- Cost is per batch, not per craft, so the session is the right unit -- a run of twenty crafts
-- is one batch whose unit cost already has multicraft averaged into it.
--
-- The window opens when a recipe cast is SENT, which matters: the mats leave the bags during
-- the craft, so a snapshot taken at cast success, or at the first result, would miss the first
-- craft's materials entirely and understate the cost. It extends on every further cast and
-- result, and closes after QUIET_SECONDS of neither. A /reload in the middle loses the pending
-- session, and nothing is recorded -- the correct answer.
--
-- A run split in two by a long pause is not a problem: each half snapshots its own counts and
-- settles its own mats against its own output.
-- ---------------------------------------------------------------------------

local QUIET_SECONDS = 3
local RECENT_CAP = 10

local driver
local current
local sessionSeq = 0
local recent = {}

--- driver = {
--   recipeFor(spellID) -> { recipeID, outputItemID, isRecraft, candidates } | nil,
--   countsFor(candidates) -> { [itemID] = count },
--   batchesFor(itemID) -> array of this character's active batches for that item,
--   commodityKinds() -> { [itemID] = boolean },  -- GC.db.commodityByItem
--   context() -> { char, region },
-- }
function GC.CraftCapture.SetDriver(value)
  driver = type(value) == "table" and value or nil
  current = nil
end

function GC.CraftCapture.HasOpenSession()
  return current ~= nil
end

-- Newest first. Diagnostics only (`/gc craft`) -- a settled craft is otherwise silent, and a
-- refused one has to be able to say why without the player reading a log.
function GC.CraftCapture.RecentOutcomes()
  local out = {}
  for index = #recent, 1, -1 do out[#out + 1] = recent[index] end
  return out
end

local function remember(outcome)
  recent[#recent + 1] = outcome
  while #recent > RECENT_CAP do table.remove(recent, 1) end
end

local function close(now)
  local session = current
  current = nil
  if not session or not driver then return end

  local outcome = { recipeID = session.recipe.recipeID, at = now }
  session.after = driver.countsFor(session.recipe.candidates)

  local plan, reason = GC.CraftCapture.Plan(session)
  if not plan then
    outcome.reason = reason
    return remember(outcome)
  end

  local costing
  costing, reason = GC.CraftCapture.Cost(plan.consumed, driver.batchesFor)
  if not costing then
    outcome.reason = reason
    return remember(outcome)
  end

  local known = driver.commodityKinds()
  local recorded
  recorded, reason = GC.CraftCapture.Settle(plan, costing, driver.context(), now, session.key,
    function(itemID) return GC.CraftCapture.OutputKey(itemID, known, driver.batchesFor(itemID)) end)
  if not recorded then
    outcome.reason = reason
    return remember(outcome)
  end

  outcome.total, outcome.unitCost = recorded.total, recorded.unitCost
  outcome.outputs = plan.outputs
  -- Kept so the diagnostic can read each batch's CURRENT identity: a craft away from the
  -- auction house is recorded keyless and picks its key up on the next Sell refresh there.
  outcome.batchIDs = {}
  for _, batch in ipairs(recorded.batches) do outcome.batchIDs[#outcome.batchIDs + 1] = batch.id end
  remember(outcome)
end

--- A spell the player just sent. Opens a session for a recipe, and closes an open one for
--- anything else -- a cast that is not this run's recipe means the run is over.
function GC.CraftCapture.OnCastSent(spellID, now)
  if not driver or not isExactInteger(now) then return end
  local recipe = driver.recipeFor(spellID)
  if type(recipe) ~= "table" or type(recipe.candidates) ~= "table" then
    return close(now)
  end
  if current and current.recipe.recipeID == recipe.recipeID then
    current.lastAt = now
    return
  end
  close(now)
  sessionSeq = sessionSeq + 1
  current = {
    recipe = recipe,
    before = driver.countsFor(recipe.candidates),
    results = {},
    lastAt = now,
    key = table.concat({ "craft", recipe.recipeID, now, sessionSeq }, ":"),
  }
end

--- One TRADE_SKILL_ITEM_CRAFTED_RESULT. Ignored outside a session: with no before-count there
--- is nothing to cost it against.
function GC.CraftCapture.OnCraftResult(result, now)
  if not current or type(result) ~= "table" or not isExactInteger(now) then return end
  current.results[#current.results + 1] = {
    itemID = result.itemID, quantity = result.quantity, isEnchant = result.isEnchant,
  }
  current.lastAt = now
end

--- Called from the addon's bag-update handler and from a one-second ticker while a session is
--- open. Settles the run once it has gone quiet.
function GC.CraftCapture.Tick(now)
  if not current or not isExactInteger(now) then return end
  if now - current.lastAt >= QUIET_SECONDS then close(now) end
end
