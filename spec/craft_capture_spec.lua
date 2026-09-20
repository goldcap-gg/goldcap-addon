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
