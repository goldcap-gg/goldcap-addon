local helper = require("spec.spec_helper")

-- GoldCap's own block under an item tooltip reads GetItemValue(itemID), which for gear is every
-- item level at once (the site merges them) and for a caged pet every pet. Under a Sell row that
-- stands for one item level or one pet, whose panel says "no market figure for this item level",
-- the block says the same instead of the merged figure (review N7).
describe("Tooltip under a Sell variant row", function()
  local GC, postCall, lines, owner

  before_each(function()
    postCall, lines = nil, {}
    _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
    _G.Enum = { TooltipDataType = { Item = 0 } }
    owner = nil
    _G.GameTooltip = {
      GetOwner = function() return owner end,
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
    owner = { goldcapVariant = "level" } -- the Sell row that opened this tooltip
    postCall(_G.GameTooltip, { id = 222 })
    local text = table.concat(lines, " | ")
    assert.matches("no market figure for this item level", text, 1, true)
    assert.is_nil(text:find("GoldCap value", 1, true))
  end)

  it("says so for a pet too", function()
    owner = { goldcapVariant = "pet" }
    postCall(_G.GameTooltip, { id = 82800 })
    assert.matches("no market figure for this pet", table.concat(lines, " | "), 1, true)
  end)

  it("keeps the block everywhere else", function()
    owner = {} -- a bag slot's button
    postCall(_G.GameTooltip, { id = 222 })
    assert.matches("GoldCap value", table.concat(lines, " | "), 1, true)
  end)

  -- Read off the tooltip's own owner, never a flag of the Sell tab's: a flag outlived a row hidden
  -- under a stationary cursor, and every item tooltip in the game lost its value (review NI-B).
  it("reads the variant off the tooltip's owner, never off anything the Sell tab left behind", function()
    GC.Sell._hoverVariant = "level"
    owner = {}
    postCall(_G.GameTooltip, { id = 222 })
    assert.matches("GoldCap value", table.concat(lines, " | "), 1, true)
  end)

  -- Only the game's own item tooltip is ever a Sell row's: a linked item's window keeps its block.
  it("reads the note only under GameTooltip", function()
    _G.ItemRefTooltip = { GetOwner = function() return { goldcapVariant = "level" } end,
      AddLine = function(_, text) lines[#lines + 1] = text end,
      AddDoubleLine = function(_, left) lines[#lines + 1] = left end }
    postCall(_G.ItemRefTooltip, { id = 222 })
    _G.ItemRefTooltip = nil
    assert.matches("GoldCap value", table.concat(lines, " | "), 1, true)
  end)

  it("keeps the block on a tooltip with no owner", function()
    postCall(_G.GameTooltip, { id = 222 })
    assert.matches("GoldCap value", table.concat(lines, " | "), 1, true)
  end)
end)
