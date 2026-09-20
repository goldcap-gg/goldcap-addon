local helper = require("spec.spec_helper")

describe("CraftCapture.Plan", function()
  local GC

  before_each(function() GC = helper.loadModule("Core/CraftCapture.lua", {}) end)

  -- One recipe, two reagents, one output. Overrides replace a whole field.
  local function session(overrides)
    local s = {
      recipe = { recipeID = 1, outputItemID = 500, isRecraft = false,
                 candidates = { [10] = true, [11] = true } },
      before = { [10] = 20, [11] = 8 },
      after = { [10] = 10, [11] = 3 },
      results = { { itemID = 500, quantity = 2 } },
    }
    for key, value in pairs(overrides or {}) do s[key] = value end
    return s
  end

  it("reads consumption as the fall in the recipe's own reagents", function()
    local plan = GC.CraftCapture.Plan(session())
    assert.same({ { itemID = 10, quantity = 10 }, { itemID = 11, quantity = 5 } }, plan.consumed)
    assert.same({ { itemID = 500, quantity = 2 } }, plan.outputs)
  end)

  it("counts multicraft extras as produced units", function()
    -- The event's `quantity` already includes what multicraft added, so there is nothing to
    -- model: the extra units simply make the same mats cover more of them.
    local plan = GC.CraftCapture.Plan(session({ results = { { itemID = 500, quantity = 5 } } }))
    assert.same({ { itemID = 500, quantity = 5 } }, plan.outputs)
  end)

  it("nets resourcefulness returns out of the delta", function()
    -- 10 went in, 4 came straight back: the bags only fell by 6, and 6 is what the craft cost.
    local plan = GC.CraftCapture.Plan(session({ after = { [10] = 14, [11] = 3 } }))
    assert.same({ { itemID = 10, quantity = 6 }, { itemID = 11, quantity = 5 } }, plan.consumed)
  end)

  it("keeps every output quality of one run in one plan", function()
    local plan = GC.CraftCapture.Plan(session({
      recipe = { recipeID = 1, outputItemID = 500, isRecraft = false,
                 candidates = { [10] = true, [11] = true }, outputs = { [500] = true, [501] = true } },
      results = { { itemID = 500, quantity = 3 }, { itemID = 501, quantity = 2 },
                  { itemID = 500, quantity = 1 } },
    }))
    assert.same({ { itemID = 500, quantity = 4 }, { itemID = 501, quantity = 2 } }, plan.outputs)
  end)

  it("ignores an item that only went up", function()
    -- A loot drop landing mid-session is not a consumed reagent.
    local plan = GC.CraftCapture.Plan(session({ after = { [10] = 10, [11] = 30 } }))
    assert.same({ { itemID = 10, quantity = 10 } }, plan.consumed)
  end)

  it("refuses a recraft", function()
    local plan, reason = GC.CraftCapture.Plan(session({
      recipe = { recipeID = 1, outputItemID = 500, isRecraft = true, candidates = { [10] = true } },
    }))
    assert.is_nil(plan)
    assert.equal("recraft", reason)
  end)

  it("refuses a recipe with no determinate output", function()
    local plan, reason = GC.CraftCapture.Plan(session({
      recipe = { recipeID = 1, outputItemID = nil, isRecraft = false, candidates = { [10] = true } },
    }))
    assert.is_nil(plan)
    assert.equal("random-output", reason)
  end)

  it("refuses a session that produced nothing", function()
    local plan, reason = GC.CraftCapture.Plan(session({ results = {} }))
    assert.is_nil(plan)
    assert.equal("no-output", reason)
  end)

  it("refuses a session that consumed nothing", function()
    local plan, reason = GC.CraftCapture.Plan(session({ after = { [10] = 20, [11] = 8 } }))
    assert.is_nil(plan)
    assert.equal("no-consumption", reason)
  end)

  it("refuses an enchant result, which produces no item to hold", function()
    local plan, reason = GC.CraftCapture.Plan(session({
      results = { { itemID = 0, quantity = 1, isEnchant = true } },
    }))
    assert.is_nil(plan)
    assert.equal("no-output", reason)
  end)

  it("refuses counts it cannot trust", function()
    local plan, reason = GC.CraftCapture.Plan(session({ before = { [10] = 20 } }))
    assert.is_nil(plan)
    assert.equal("bad-counts", reason)
  end)

  it("counts only what the recipe actually makes", function()
    -- TRADE_SKILL_ITEM_CRAFTED_RESULT also fires for things that are not the craft -- a
    -- first-craft reward, a knowledge item. Counting one as a produced unit would spread the
    -- session's materials over more units than it made, and understate what each one cost.
    local plan = GC.CraftCapture.Plan(session({
      recipe = { recipeID = 1, outputItemID = 500, isRecraft = false,
                 candidates = { [10] = true, [11] = true }, outputs = { [500] = true, [501] = true } },
      results = { { itemID = 500, quantity = 2 }, { itemID = 501, quantity = 1 },
                  { itemID = 9999, quantity = 1 } },
    }))
    assert.same({ { itemID = 500, quantity = 2 }, { itemID = 501, quantity = 1 } }, plan.outputs)
    assert.equal(1, plan.ignored)
  end)

  it("refuses a session whose every result was something else", function()
    local plan, reason = GC.CraftCapture.Plan(session({
      recipe = { recipeID = 1, outputItemID = 500, isRecraft = false,
                 candidates = { [10] = true, [11] = true }, outputs = { [500] = true } },
      results = { { itemID = 9999, quantity = 1 } },
    }))
    assert.is_nil(plan)
    assert.equal("no-output", reason)
  end)

  it("falls back to the declared output when the client named no variants", function()
    -- Conservative on purpose: a quality variant the client did not name is refused, not
    -- guessed at. Refusing costs a craft its basis; guessing costs it the truth.
    local plan, reason = GC.CraftCapture.Plan(session({
      results = { { itemID = 501, quantity = 2 } },
    }))
    assert.is_nil(plan)
    assert.equal("no-output", reason)
  end)

  it("refuses a recipe that eats what it makes", function()
    -- The same id going both in and out nets against itself in the bag delta, so what the
    -- craft really consumed cannot be read from it at all.
    local plan, reason = GC.CraftCapture.Plan(session({
      recipe = { recipeID = 1, outputItemID = 500, isRecraft = false,
                 candidates = { [10] = true, [500] = true }, outputs = { [500] = true } },
      before = { [10] = 20, [500] = 4 },
      after = { [10] = 10, [500] = 6 },
    }))
    assert.is_nil(plan)
    assert.equal("output-is-reagent", reason)
  end)

  it("refuses a session with no recipe at all", function()
    -- Built by hand: `session({ recipe = nil })` cannot express this, because pairs() never
    -- visits a key whose value is nil.
    local plan, reason = GC.CraftCapture.Plan({ before = {}, after = {}, results = {} })
    assert.is_nil(plan)
    assert.equal("no-recipe", reason)
  end)
end)

describe("CraftCapture.Cost", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua", {})
    helper.loadModule("Core/CraftCapture.lua", GC)
  end)

  local function batch(fields)
    return { id = fields.id, itemID = fields.itemID, positionKey = fields.positionKey,
             remainingQty = fields.qty, remainingTotal = fields.total,
             acquiredAt = fields.at or 1, source = "auction_house" }
  end

  local function storeOf(byItem)
    return function(itemID) return byItem[itemID] or {} end
  end

  it("prices a reagent from its own FIFO batches", function()
    local costing = GC.CraftCapture.Cost({ { itemID = 10, quantity = 10 } }, storeOf({
      [10] = { batch({ id = "acq:1", itemID = 10, positionKey = "commodity:10",
                       qty = 20, total = 2000 }) },
    }))
    assert.equal(1000, costing.total)
    assert.equal("commodity:10", costing.reagents[1].positionKey)
    assert.equal(10, costing.reagents[1].quantity)
  end)

  it("walks two batches in the order they were bought", function()
    local costing = GC.CraftCapture.Cost({ { itemID = 10, quantity = 6 } }, storeOf({
      [10] = {
        batch({ id = "acq:2", itemID = 10, positionKey = "commodity:10", qty = 10, total = 2000, at = 2 }),
        batch({ id = "acq:1", itemID = 10, positionKey = "commodity:10", qty = 4, total = 400, at = 1 }),
      },
    }))
    assert.equal(800, costing.total)   -- the older 4 @100, then 2 of the newer @200
  end)

  it("adds every reagent of the craft up", function()
    local costing = GC.CraftCapture.Cost({ { itemID = 10, quantity = 2 }, { itemID = 11, quantity = 3 } },
      storeOf({
        [10] = { batch({ id = "acq:1", itemID = 10, positionKey = "commodity:10", qty = 5, total = 500 }) },
        [11] = { batch({ id = "acq:2", itemID = 11, positionKey = "commodity:11", qty = 5, total = 5000 }) },
      }))
    assert.equal(200 + 3000, costing.total)
    assert.equal(2, #costing.reagents)
  end)

  it("refuses the whole craft when one reagent is not covered", function()
    local costing, reason = GC.CraftCapture.Cost({ { itemID = 10, quantity = 10 } }, storeOf({
      [10] = { batch({ id = "acq:1", itemID = 10, positionKey = "commodity:10", qty = 3, total = 300 }) },
    }))
    assert.is_nil(costing)
    assert.equal("uncosted", reason)
  end)

  it("refuses the whole craft when a reagent was never bought at all", function()
    -- Gathered, looted, or bought from a vendor: real cost, no record of it. Phase 1 leaves
    -- the craft without a basis rather than inventing one.
    local costing, reason = GC.CraftCapture.Cost({ { itemID = 10, quantity = 1 } }, storeOf({}))
    assert.is_nil(costing)
    assert.equal("uncosted", reason)
  end)

  it("refuses a reagent whose batches disagree on identity", function()
    local costing, reason = GC.CraftCapture.Cost({ { itemID = 10, quantity = 2 } }, storeOf({
      [10] = {
        batch({ id = "acq:1", itemID = 10, positionKey = "commodity:10", qty = 5, total = 500 }),
        batch({ id = "acq:2", itemID = 10, positionKey = "item:10:600:0:0", qty = 5, total = 900 }),
      },
    }))
    assert.is_nil(costing)
    assert.equal("ambiguous-identity", reason)
  end)

  it("refuses a batch carrying no position key", function()
    local costing, reason = GC.CraftCapture.Cost({ { itemID = 10, quantity = 1 } }, storeOf({
      [10] = { batch({ id = "acq:1", itemID = 10, positionKey = nil, qty = 20, total = 2000 }) },
    }))
    assert.is_nil(costing)
    assert.equal("ambiguous-identity", reason)
  end)

  it("refuses a craft whose mats cost nothing on record", function()
    local costing, reason = GC.CraftCapture.Cost({ { itemID = 10, quantity = 2 } }, storeOf({
      [10] = { batch({ id = "acq:1", itemID = 10, positionKey = "commodity:10", qty = 5, total = 0 }) },
    }))
    assert.is_nil(costing)
    assert.equal("uncosted", reason)
  end)
end)

describe("CraftCapture.Settle", function()
  local GC, db
  local context = { char = "Tester", region = "eu" }

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua", {})
    helper.loadModule("Core/CraftCapture.lua", GC)
    db = { acquisitions = {} }
    GC.Acquisitions.Init(db)
  end)

  -- The reagent lookup the live wiring passes: this character's active batches for one item.
  local function batchesFor(itemID)
    local out = {}
    for _, batch in ipairs(GC.Acquisitions.GetActive(context)) do
      if batch.itemID == itemID then out[#out + 1] = batch end
    end
    return out
  end

  local function bought(itemID, quantity, total)
    GC.Acquisitions.Record({ source = "auction_house", itemID = itemID,
      positionKey = ("commodity:%d"):format(itemID), quantity = quantity, total = total,
      acquiredAt = 1, character = context.char, region = context.region })
  end

  local function remainingOf(itemID)
    for _, batch in ipairs(db.acquisitions) do
      if batch.itemID == itemID then return batch.remainingQty end
    end
  end

  it("consumes the reagents and records one batch for the output", function()
    bought(10, 20, 2000)
    local plan = { outputs = { { itemID = 500, quantity = 4 } },
                   consumed = { { itemID = 10, quantity = 10 } } }
    local costing = GC.CraftCapture.Cost(plan.consumed, batchesFor)
    local recorded = GC.CraftCapture.Settle(plan, costing, context, 100, "craft:1:100:1")

    assert.equal(1, #recorded.batches)
    assert.equal(500, recorded.batches[1].itemID)
    assert.equal(4, recorded.batches[1].originalQty)
    assert.equal(1000, recorded.batches[1].originalTotal)   -- 10 mats at 100 each
    assert.equal("craft", recorded.batches[1].source)
    assert.equal(10, remainingOf(10))                        -- and the mats are gone from stock
  end)

  it("gives every output quality the same unit cost", function()
    -- The same mats went into every craft, whatever quality came out of it.
    bought(10, 10, 900)
    local plan = { outputs = { { itemID = 500, quantity = 2 }, { itemID = 501, quantity = 1 } },
                   consumed = { { itemID = 10, quantity = 10 } } }
    local costing = GC.CraftCapture.Cost(plan.consumed, batchesFor)
    local recorded = GC.CraftCapture.Settle(plan, costing, context, 100, "craft:1:100:2")

    local totals = {}
    for _, batch in ipairs(recorded.batches) do totals[batch.itemID] = batch.originalTotal end
    assert.equal(600, totals[500])
    assert.equal(300, totals[501])
    assert.equal(900, totals[500] + totals[501])   -- nothing invented, nothing lost
  end)

  it("keeps the remainder rather than losing it to rounding", function()
    bought(10, 10, 1000)
    local plan = { outputs = { { itemID = 500, quantity = 3 } },
                   consumed = { { itemID = 10, quantity = 10 } } }
    local costing = GC.CraftCapture.Cost(plan.consumed, batchesFor)
    local recorded = GC.CraftCapture.Settle(plan, costing, context, 100, "craft:1:100:3")
    assert.equal(1000, recorded.batches[1].originalTotal)   -- 333 + 333 + 333 would lose a copper
  end)

  it("is idempotent -- a replayed session changes nothing", function()
    bought(10, 20, 2000)
    local plan = { outputs = { { itemID = 500, quantity = 4 } },
                   consumed = { { itemID = 10, quantity = 10 } } }
    GC.CraftCapture.Settle(plan, GC.CraftCapture.Cost(plan.consumed, batchesFor),
      context, 100, "craft:1:100:4")
    local after = #db.acquisitions
    local replay = GC.CraftCapture.Cost(plan.consumed, batchesFor)
    if replay then
      GC.CraftCapture.Settle(plan, replay, context, 100, "craft:1:100:4")
    end
    assert.equal(after, #db.acquisitions)
    assert.equal(10, remainingOf(10))               -- and the mats were not spent twice
  end)

  it("records nothing when a reagent cannot be consumed", function()
    local plan = { outputs = { { itemID = 500, quantity = 4 } },
                   consumed = { { itemID = 10, quantity = 10 } } }
    local costing = { total = 1000, reagents = { { itemID = 10, quantity = 10,
      positionKey = "commodity:10", plan = { coverage = "COMPLETE", knownCost = 1000,
        allocations = { { batchID = "acq:missing", quantity = 10, cost = 1000 } } } } } }
    local recorded, reason = GC.CraftCapture.Settle(plan, costing, context, 100, "craft:1:100:5")
    assert.is_nil(recorded)
    assert.equal("consume-failed", reason)
    assert.equal(0, #db.acquisitions)
  end)

  it("refuses before spending anything when a unit would cost under a copper", function()
    bought(10, 10, 5)
    local plan = { outputs = { { itemID = 500, quantity = 900 } },
                   consumed = { { itemID = 10, quantity = 10 } } }
    local costing = GC.CraftCapture.Cost(plan.consumed, batchesFor)
    local recorded, reason = GC.CraftCapture.Settle(plan, costing, context, 100, "craft:1:100:6")
    assert.is_nil(recorded)
    assert.equal("sub-copper", reason)
    assert.equal(10, remainingOf(10))               -- the mats were not touched
  end)
end)

describe("CraftCapture.OutputKey", function()
  local GC

  before_each(function() GC = helper.loadModule("Core/CraftCapture.lua", {}) end)

  it("reuses the key the item's own batches already carry", function()
    assert.equal("commodity:500", GC.CraftCapture.OutputKey(500, {},
      { { itemID = 500, positionKey = "commodity:500" } }))
  end)

  it("prefers recorded evidence over the remembered answer", function()
    assert.equal("item:500:600:0:0", GC.CraftCapture.OutputKey(500, { [500] = true },
      { { itemID = 500, positionKey = "item:500:600:0:0" } }))
  end)

  it("falls back to the remembered commodity answer", function()
    assert.equal("commodity:500", GC.CraftCapture.OutputKey(500, { [500] = true }, {}))
  end)

  it("stays keyless for gear, whose key needs the item link", function()
    assert.is_nil(GC.CraftCapture.OutputKey(500, { [500] = false }, {}))
  end)

  it("stays keyless for an item nobody has classified", function()
    -- GetItemKeyInfo only answers at the auction house. A batch recorded keyless is bound
    -- later by the identity-repair path; a guessed key files one item under two positions.
    assert.is_nil(GC.CraftCapture.OutputKey(500, {}, {}))
  end)

  it("stays keyless when the item's own batches disagree", function()
    assert.is_nil(GC.CraftCapture.OutputKey(500, { [500] = true }, {
      { itemID = 500, positionKey = "commodity:500" },
      { itemID = 500, positionKey = "item:500:600:0:0" },
    }))
  end)

  it("ignores batches belonging to another item", function()
    assert.equal("commodity:500", GC.CraftCapture.OutputKey(500, { [500] = true },
      { { itemID = 77, positionKey = "commodity:77" } }))
  end)
end)

describe("CraftCapture.Settle identity", function()
  local GC, db
  local context = { char = "Tester", region = "eu" }

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua", {})
    helper.loadModule("Core/CraftCapture.lua", GC)
    db = { acquisitions = {} }
    GC.Acquisitions.Init(db)
    GC.Acquisitions.Record({ source = "auction_house", itemID = 10, positionKey = "commodity:10",
      quantity = 20, total = 2000, acquiredAt = 1, character = context.char, region = context.region })
  end)

  local function settle(outputKeyFor)
    local plan = { outputs = { { itemID = 500, quantity = 4 } },
                   consumed = { { itemID = 10, quantity = 10 } } }
    local costing = GC.CraftCapture.Cost(plan.consumed, function(itemID)
      local out = {}
      for _, batch in ipairs(GC.Acquisitions.GetActive(context)) do
        if batch.itemID == itemID then out[#out + 1] = batch end
      end
      return out
    end)
    return GC.CraftCapture.Settle(plan, costing, context, 100, "craft:1:100:7", outputKeyFor)
  end

  it("stamps the key the caller resolved", function()
    local recorded = settle(function() return "commodity:500" end)
    assert.equal("commodity:500", recorded.batches[1].positionKey)
  end)

  it("records the batch keyless when identity is not known yet", function()
    local recorded = settle(nil)
    assert.is_nil(recorded.batches[1].positionKey)
    assert.equal(4, recorded.batches[1].remainingQty)
  end)
end)
