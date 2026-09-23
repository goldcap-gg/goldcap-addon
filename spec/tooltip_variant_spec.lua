local helper = require("spec.spec_helper")

-- GoldCap's own block under an item tooltip reads GetItemValue(itemID), which for gear is every
-- item level at once (the site merges them) and for a caged pet every pet. Under a Sell row that
-- stands for one item level or one pet, whose panel says "no market figure for this item level",
-- the block says the same instead of the merged figure (review N7).
describe("Tooltip under a Sell variant row", function()
  local GC, postCall, lines

  before_each(function()
    postCall, lines = nil, {}
    _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
    _G.Enum = { TooltipDataType = { Item = 0 } }
    _G.GameTooltip = {
      AddLine = function(_, text) lines[#lines + 1] = text end,
      AddDoubleLine = function(_, left) lines[#lines + 1] = left end,
    }
    _G.C_Item = { GetItemInfoInstant = function() return 222 end }
    _G.GetCoinTextureString = function(n) return tostring(n) end
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Trigger.lua", GC)
    GC.db = { settings = { tooltip = true } }
    GC.Data = { GetItemValue = function() return { mv = 9000000, sold = 50, ts = time() } end }
    GC.Sell = {}
    helper.loadModule("UI/Tooltip.lua", GC)
  end)

  after_each(function()
    _G.TooltipDataProcessor, _G.Enum, _G.GameTooltip, _G.C_Item, _G.GetCoinTextureString = nil, nil, nil, nil, nil
  end)

  it("says there is no market figure for this item level instead of the merged one", function()
    GC.Sell._hoverVariant = "level"
    postCall(_G.GameTooltip, { id = 222 })
    local text = table.concat(lines, " | ")
    assert.matches("no market figure for this item level", text, 1, true)
    assert.is_nil(text:find("GoldCap value", 1, true))
  end)

  it("says so for a pet too", function()
    GC.Sell._hoverVariant = "pet"
    postCall(_G.GameTooltip, { id = 82800 })
    assert.matches("no market figure for this pet", table.concat(lines, " | "), 1, true)
  end)

  it("keeps the block everywhere else", function()
    postCall(_G.GameTooltip, { id = 222 })
    assert.matches("GoldCap value", table.concat(lines, " | "), 1, true)
  end)
end)
