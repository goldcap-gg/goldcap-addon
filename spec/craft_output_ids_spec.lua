local helper = require("spec.spec_helper")

-- C_TradeSkillUI as the 12.x client shapes it: a quality recipe lists its quality IDs (crafting
-- quality ids, not 1..5) and one item id per quality; GetRecipeOutputItemData answers only for a
-- quality ID it knows.
local function fakeApi(opts)
  opts = opts or {}
  local byQuality = opts.byQuality or { [13] = 245001, [14] = 245002 }
  local api = {
    GetRecipeQualityItemIDs = function(spellID)
      if opts.qualityListErrors then error("not allowed") end
      return spellID == 900 and { 245001, 245002 } or nil
    end,
    GetRecipeInfo = function(spellID)
      if spellID ~= 900 then return nil end
      return { recipeID = 900, qualityIDs = opts.qualityIDs or { 13, 14 },
               qualityItemIDs = opts.infoItemIDs }
    end,
    GetRecipeOutputItemData = function(spellID, _, _, qualityID)
      if spellID ~= 900 then return nil end
      local id = byQuality[qualityID]
      return id and { itemID = id } or nil
    end,
  }
  if opts.noQualityList then api.GetRecipeQualityItemIDs = nil end
  return api
end

describe("CraftCapture.OutputIDs", function()
  local GC

  before_each(function() GC = helper.loadModule("Core/CraftCapture.lua", {}) end)

  it("lists every quality's item, not just the declared output", function()
    assert.same({ [245000] = true, [245001] = true, [245002] = true },
      GC.CraftCapture.OutputIDs(fakeApi(), 900, 245000))
  end)

  it("asks GetRecipeOutputItemData by the recipe's quality IDs, which are not 1 to 5", function()
    -- No quality list and no qualityItemIDs: only the per-quality output data can name them,
    -- and it answers to 13 and 14, never to an index.
    local api = fakeApi({ noQualityList = true })
    assert.same({ [245000] = true, [245001] = true, [245002] = true },
      GC.CraftCapture.OutputIDs(api, 900, 245000))
  end)

  it("reads recipeInfo.qualityItemIDs the way the client's crafter details do", function()
    local api = fakeApi({ noQualityList = true, qualityIDs = {}, infoItemIDs = { 245007, 245008 } })
    assert.same({ [245000] = true, [245007] = true, [245008] = true },
      GC.CraftCapture.OutputIDs(api, 900, 245000))
  end)

  it("keeps the declared output when the client refuses or knows nothing more", function()
    assert.same({ [245000] = true }, GC.CraftCapture.OutputIDs(nil, 900, 245000))
    assert.same({ [245000] = true }, GC.CraftCapture.OutputIDs(fakeApi(), 901, 245000))
    local erroring = fakeApi({ qualityListErrors = true, qualityIDs = {} })
    assert.same({ [245000] = true }, GC.CraftCapture.OutputIDs(erroring, 900, 245000))
  end)

  it("lets Plan count a craft that came out at the higher quality", function()
    local outputs = GC.CraftCapture.OutputIDs(fakeApi(), 900, 245000)
    local plan, reason = GC.CraftCapture.Plan({
      recipe = { recipeID = 900, outputItemID = 245000, candidates = { [10] = true }, outputs = outputs },
      before = { [10] = 5 }, after = { [10] = 4 },
      results = { { itemID = 245002, quantity = 1 } },
    })
    assert.is_nil(reason)
    assert.same({ { itemID = 245002, quantity = 1 } }, plan.outputs)
  end)
end)
