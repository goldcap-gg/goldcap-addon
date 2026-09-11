local helper = require("spec.spec_helper")

-- The first attempt hardcoded the Dragonflight atlas names, so the list drew two
-- diamonds beside an item whose own tooltip drew something else -- the addon
-- disagreeing with the game about the same item. An atlas name is art, and art
-- is versioned; the fix is to stop naming it and read what the client itself
-- renders.
describe("Reagent quality markup", function()
  local GC

  local function stubFrame()
    return {
      SetPoint = function() end, SetSize = function() end, SetScript = function() end,
      CreateFontString = function() return { SetPoint = function() end } end,
      CreateTexture = function() return { SetAllPoints = function() end,
        SetColorTexture = function() end, SetBlendMode = function() end, Hide = function() end,
        SetTexture = function() end } end,
      EnableMouse = function() end, RegisterForDrag = function() end, SetMovable = function() end,
      SetFrameStrata = function() end, SetFrameLevel = function() end, GetFrameLevel = function() return 0 end,
    }
  end

  local function tooltip(lines)
    _G.C_TooltipInfo = { GetItemByID = function() return { lines = lines } end }
  end

  before_each(function()
    GC = {}
    _G.CreateFrame = function() return stubFrame() end
    _G.C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function() return 2 end }
    helper.loadModule("UI/Theme.lua", GC)
  end)

  after_each(function()
    _G.C_TradeSkillUI, _G.CreateFrame, _G.C_TooltipInfo, _G.C_Texture = nil, nil, nil, nil
  end)

  it("draws whatever icon the client's own tooltip draws", function()
    tooltip({ { leftText = "Arcanoweave" },
              { leftText = "Quality: |A:some-future-quality-mark-2:20:20|a" } })
    assert.equal("|A:some-future-quality-mark-2:14:14|a", GC.Theme.QualityMarkup(1))
  end)

  it("rescales it to the row rather than keeping the tooltip's size", function()
    tooltip({ { leftText = "Quality: |A:quality-mark-2:20:20|a" } })
    assert.equal("|A:quality-mark-2:12:12|a", GC.Theme.QualityMarkup(1, 12))
  end)

  it("matches on the atlas name, never on the label beside it", function()
    -- Atlas names are not localised; the label is. A Russian client says
    -- "Качество:" and must still work.
    tooltip({ { leftText = "Качество: |A:profession-quality-tier2:20:20|a" } })
    assert.equal("|A:profession-quality-tier2:14:14|a", GC.Theme.QualityMarkup(1))
  end)

  it("ignores atlases on the tooltip that are not about quality", function()
    tooltip({ { leftText = "|A:warbound-until-equipped:16:16|a Warbound" },
              { leftText = "Quality: |A:the-quality-one:20:20|a" } })
    assert.equal("|A:the-quality-one:14:14|a", GC.Theme.QualityMarkup(1))
  end)

  it("says nothing for an item that has no tier", function()
    -- Most items do not. A pip on all of them would be noise, and a wrong pip on
    -- any of them is worse than none.
    _G.C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function() return nil end }
    tooltip({ { leftText = "Quality: |A:quality-mark-2:20:20|a" } })
    assert.equal("", GC.Theme.QualityMarkup(1))
  end)

  it("says nothing rather than guessing when the tooltip API is unavailable", function()
    -- There is no hardcoded fallback atlas: a client that will not say what to
    -- draw gets no pip, never a remembered guess from an older expansion.
    _G.C_TooltipInfo = nil
    assert.equal("", GC.Theme.QualityMarkup(1))
  end)

  it("does not remember a tooltip that had not loaded yet", function()
    -- An uncached item answers nothing, which is temporary. Caching that would
    -- leave the pip permanently missing -- or permanently wrong -- for the
    -- rest of the session.
    _G.C_TooltipInfo = { GetItemByID = function() return nil end }
    assert.equal("", GC.Theme.QualityMarkup(1))
    tooltip({ { leftText = "Quality: |A:quality-mark-2:20:20|a" } })
    assert.equal("|A:quality-mark-2:14:14|a", GC.Theme.QualityMarkup(1))
  end)

  it("never falls back to an old expansion's atlas once the tooltip goes quiet", function()
    -- A tooltip that resolves once and then (for whatever reason) stops
    -- answering must not make the cached-nothing path reach for a name this
    -- file used to hardcode. The cache from the first resolution is what
    -- carries the answer, not a guess keyed off the reagent's tier number.
    tooltip({ { leftText = "Quality: |A:new-expansion-quality-mark:20:20|a" } })
    assert.equal("|A:new-expansion-quality-mark:14:14|a", GC.Theme.QualityMarkup(1))
    _G.C_TooltipInfo = { GetItemByID = function() return nil end }
    assert.equal("|A:new-expansion-quality-mark:14:14|a", GC.Theme.QualityMarkup(1))
  end)

  it("survives an API that throws rather than taking the row down with it", function()
    _G.C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function() error("nope") end }
    assert.equal("", GC.Theme.QualityMarkup(1))
  end)

  it("prefixes a name only when there is a tier to show", function()
    tooltip({ { leftText = "Quality: |A:quality-mark-2:20:20|a" } })
    assert.equal("|A:quality-mark-2:14:14|a Ore", GC.Theme.WithQuality("Ore", 1))
    _G.C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function() return nil end }
    assert.equal("Ore", GC.Theme.WithQuality("Ore", 2))
  end)
end)
