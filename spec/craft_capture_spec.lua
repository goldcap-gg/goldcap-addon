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
