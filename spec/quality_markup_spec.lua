local helper = require("spec.spec_helper")

describe("Reagent quality markup", function()
  local GC

  before_each(function()
    GC = { }
    _G.CreateFrame = function() return {
      SetPoint = function() end, SetSize = function() end, SetScript = function() end,
      CreateFontString = function() return { SetPoint = function() end } end,
      CreateTexture = function() return { SetAllPoints = function() end,
        SetColorTexture = function() end, SetBlendMode = function() end, Hide = function() end,
        SetTexture = function() end } end,
      EnableMouse = function() end, RegisterForDrag = function() end, SetMovable = function() end,
      SetFrameStrata = function() end, SetFrameLevel = function() end, GetFrameLevel = function() return 0 end,
    } end
    helper.loadModule("UI/Theme.lua", GC)
  end)

  after_each(function() _G.C_TradeSkillUI, _G.CreateFrame = nil, nil end)

  it("draws the tier the client reports, from the client's own atlas", function()
    _G.C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function() return 3 end }
    assert.equal("|A:Professions-ChatIcon-Quality-Tier3:14:14|a", GC.Theme.QualityMarkup(190395))
  end)

  it("says nothing for an item that has no tier", function()
    -- Most items do not. A pip on all of them would be noise, and a wrong pip on
    -- any of them is worse than none.
    _G.C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function() return nil end }
    assert.equal("", GC.Theme.QualityMarkup(12345))
  end)

  it("says nothing on a client too old to have the API", function()
    _G.C_TradeSkillUI = nil
    assert.equal("", GC.Theme.QualityMarkup(12345))
  end)

  it("survives an API that throws rather than taking the row down with it", function()
    _G.C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function() error("nope") end }
    assert.equal("", GC.Theme.QualityMarkup(12345))
  end)

  it("refuses a tier the atlas does not cover", function()
    _G.C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function() return 9 end }
    assert.equal("", GC.Theme.QualityMarkup(12345))
  end)

  it("prefixes a name only when there is a tier to show", function()
    _G.C_TradeSkillUI = { GetItemReagentQualityByItemInfo = function(id) return id == 1 and 2 or nil end }
    assert.equal("|A:Professions-ChatIcon-Quality-Tier2:14:14|a Ore", GC.Theme.WithQuality("Ore", 1))
    assert.equal("Ore", GC.Theme.WithQuality("Ore", 2))
  end)
end)
