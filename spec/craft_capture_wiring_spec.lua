local helper = require("spec.spec_helper")

describe("CraftCapture session", function()
  local GC, db, counts
  local context = { char = "Tester", region = "eu" }

  local RECIPE_SPELL = 777

  local function driver()
    return {
      recipeFor = function(spellID)
        if spellID ~= RECIPE_SPELL then return nil end
        return { recipeID = RECIPE_SPELL, outputItemID = 500, isRecraft = false,
                 candidates = { [10] = true } }
      end,
      countsFor = function(candidates)
        local out = {}
        for itemID in pairs(candidates) do out[itemID] = counts[itemID] or 0 end
        return out
      end,
      batchesFor = function(itemID)
        local out = {}
        for _, batch in ipairs(GC.Acquisitions.GetActive(context)) do
          if batch.itemID == itemID then out[#out + 1] = batch end
        end
        return out
      end,
      commodityKinds = function() return { [500] = true } end,
      context = function() return context end,
    }
  end

  before_each(function()
    GC = helper.loadModule("Core/Acquisitions.lua", {})
    helper.loadModule("Core/CraftCapture.lua", GC)
    db = { acquisitions = {} }
    GC.Acquisitions.Init(db)
    -- 20 reagents on the books at 100 copper each.
    GC.Acquisitions.Record({ source = "auction_house", itemID = 10, positionKey = "commodity:10",
      quantity = 20, total = 2000, acquiredAt = 1, character = context.char, region = context.region })
    counts = { [10] = 20 }
    GC.CraftCapture.SetDriver(driver())
  end)

  local function crafted()
    for _, batch in ipairs(db.acquisitions) do
      if batch.source == "craft" then return batch end
    end
  end

  it("settles one batch for a whole Create All run", function()
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 100)
    GC.CraftCapture.OnCraftResult({ itemID = 500, quantity = 1 }, 100)
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 101)
    GC.CraftCapture.OnCraftResult({ itemID = 500, quantity = 2 }, 101)   -- multicraft
    counts[10] = 10
    GC.CraftCapture.Tick(105)

    local batch = crafted()
    assert.equal(500, batch.itemID)
    assert.equal(3, batch.originalQty)
    assert.equal(1000, batch.originalTotal)
    assert.equal("commodity:500", batch.positionKey)
    assert.is_false(GC.CraftCapture.HasOpenSession())
  end)

  it("takes the before-count when the cast is sent, not after the mats are gone", function()
    -- The mats leave the bags during the craft. A snapshot taken any later misses them and
    -- understates the cost, which is the one direction this module must never fail in.
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 100)
    counts[10] = 10
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 101)          -- second craft of the same run
    GC.CraftCapture.OnCraftResult({ itemID = 500, quantity = 2 }, 101)
    counts[10] = 0
    GC.CraftCapture.Tick(105)
    assert.equal(2000, crafted().originalTotal)            -- all 20 mats, not just the last 10
  end)

  it("does not settle while the run is still going", function()
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 100)
    GC.CraftCapture.OnCraftResult({ itemID = 500, quantity = 1 }, 100)
    counts[10] = 10
    GC.CraftCapture.Tick(101)
    assert.is_nil(crafted())
    assert.is_true(GC.CraftCapture.HasOpenSession())
  end)

  it("ignores a cast that is not a recipe", function()
    GC.CraftCapture.OnCastSent(1234, 100)
    GC.CraftCapture.OnCraftResult({ itemID = 500, quantity = 1 }, 100)
    counts[10] = 10
    GC.CraftCapture.Tick(105)
    assert.is_nil(crafted())
  end)

  it("drops a session that produced nothing", function()
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 100)
    counts[10] = 10                                        -- an interrupted craft
    GC.CraftCapture.Tick(105)
    assert.is_nil(crafted())
    assert.equal(20, db.acquisitions[1].remainingQty)      -- and nothing was written off
  end)

  it("closes the open session when another recipe starts", function()
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 100)
    GC.CraftCapture.OnCraftResult({ itemID = 500, quantity = 1 }, 100)
    counts[10] = 15
    GC.CraftCapture.OnCastSent(1234, 101)                  -- not a recipe: the run is over
    assert.equal(500, crafted().originalTotal)             -- 5 mats at 100
    assert.is_false(GC.CraftCapture.HasOpenSession())
  end)

  it("keeps a refusal on the record for the diagnostic", function()
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 100)
    counts[10] = 10
    GC.CraftCapture.Tick(105)
    local recent = GC.CraftCapture.RecentOutcomes()
    assert.equal(1, #recent)
    assert.equal("no-output", recent[1].reason)
    assert.equal(RECIPE_SPELL, recent[1].recipeID)
  end)

  it("keeps a settlement on the record too", function()
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 100)
    GC.CraftCapture.OnCraftResult({ itemID = 500, quantity = 4 }, 100)
    counts[10] = 10
    GC.CraftCapture.Tick(105)
    local recent = GC.CraftCapture.RecentOutcomes()
    assert.equal(1, #recent)
    assert.is_nil(recent[1].reason)
    assert.equal(1000, recent[1].total)
    assert.equal(250, recent[1].unitCost)
  end)

  it("says why a craft off gathered mats has no cost", function()
    -- Nothing on the books for item 11, so the whole craft stays uncosted.
    GC.CraftCapture.SetDriver({
      recipeFor = function() return { recipeID = RECIPE_SPELL, outputItemID = 500,
        isRecraft = false, candidates = { [11] = true } } end,
      countsFor = function(candidates)
        local out = {}
        for itemID in pairs(candidates) do out[itemID] = counts[itemID] or 0 end
        return out
      end,
      batchesFor = function() return {} end,
      commodityKinds = function() return {} end,
      context = function() return context end,
    })
    counts[11] = 10
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 100)
    GC.CraftCapture.OnCraftResult({ itemID = 500, quantity = 4 }, 100)
    counts[11] = 0
    GC.CraftCapture.Tick(105)
    assert.is_nil(crafted())
    assert.equal("uncosted", GC.CraftCapture.RecentOutcomes()[1].reason)
  end)

  it("keeps the record where the driver asks it to", function()
    -- A /reload empties anything held in memory, and a /reload is usually what someone has
    -- just done before going looking for this.
    local saved = {}
    local d = driver()
    d.outcomes = saved
    GC.CraftCapture.SetDriver(d)
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 100)
    GC.CraftCapture.OnCraftResult({ itemID = 500, quantity = 4 }, 100)
    counts[10] = 10
    GC.CraftCapture.Tick(105)
    assert.equal(1, #saved)
    assert.equal(1000, saved[1].total)
    assert.equal(1, #GC.CraftCapture.RecentOutcomes())
  end)

  it("reads a record the driver handed it from an earlier session", function()
    local d = driver()
    d.outcomes = { { recipeID = 1, reason = "uncosted", at = 1 } }
    GC.CraftCapture.SetDriver(d)
    assert.equal("uncosted", GC.CraftCapture.RecentOutcomes()[1].reason)
  end)

  it("does nothing at all without a driver", function()
    GC.CraftCapture.SetDriver(nil)
    GC.CraftCapture.OnCastSent(RECIPE_SPELL, 100)
    GC.CraftCapture.OnCraftResult({ itemID = 500, quantity = 1 }, 100)
    GC.CraftCapture.Tick(105)
    assert.is_false(GC.CraftCapture.HasOpenSession())
    assert.is_nil(crafted())
  end)
end)
