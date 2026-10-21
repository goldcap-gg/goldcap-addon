local helper = require("spec.spec_helper")

-- A recipe's tooltip payload is the recipe (`id`) with the item it makes as its hyperlink: a probe
-- on the live client (2026-10-19) read id 278333, Schematic: R0CKY-To-Go, hyperlink [R0CKY-To-Go].
-- GoldCap's block, which takes the hyperlink first, priced the crafted item there and did not say
-- so, under the game's own price for the recipe.
describe("Tooltip on a recipe", function()
  local GC, postCall, lines, values

  local RECIPE, CRAFTED, OTHER = 278333, 275676, 222
  local CLASS = { [RECIPE] = 9, [CRAFTED] = 0, [OTHER] = 0 } -- Enum.ItemClass: Recipe 9, Consumable 0
  local CRAFTED_LINK = "|cnIQ2:|Hitem:275676::::::::80:::::|h[R0CKY-To-Go]|h|r"

  -- As the client's: an item id or an item link in, the item's id and its class (sixth) out, and
  -- nothing for what is not an item.
  local function getItemInfoInstant(info)
    local id = type(info) == "number" and info or tonumber(tostring(info):match("item:(%d+)"))
    if not id or not CLASS[id] then return end
    return id, "", "", "", 0, CLASS[id], 0
  end

  before_each(function()
    postCall, lines, values = nil, {}, {}
    _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
    _G.Enum = { TooltipDataType = { Item = 0 } }
    _G.GameTooltip = {
      GetOwner = function() return nil end,
      AddLine = function(_, text) lines[#lines + 1] = text end,
      AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. " = " .. right end,
    }
    _G.C_Item = { GetItemInfoInstant = getItemInfoInstant }
    _G.GetCoinTextureString = function(n) return tostring(n) end
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Trigger.lua", GC)
    GC.db = { settings = { tooltip = true } }
    GC.Data = { GetItemValue = function(id) return values[id] end }
    helper.loadModule("UI/Tooltip.lua", GC)
  end)

  after_each(function()
    _G.TooltipDataProcessor, _G.Enum, _G.GameTooltip, _G.C_Item, _G.GetCoinTextureString = nil, nil, nil, nil, nil
  end)

  it("says the crafted item's figure is the crafted item's", function()
    values[CRAFTED] = { mv = 129366, sold = 95, ts = time() }
    postCall(_G.GameTooltip, { id = RECIPE, hyperlink = CRAFTED_LINK })
    assert.same({ "Makes R0CKY-To-Go", "GoldCap value = 129366", "Sold per day = 95" }, lines)
  end)

  it("prints the recipe's own figure first, unlabelled, when GoldCap has one", function()
    values[RECIPE] = { mv = 2000000, listings = 12, ts = time() }
    values[CRAFTED] = { mv = 129366, sold = 95, ts = time() }
    postCall(_G.GameTooltip, { id = RECIPE, hyperlink = CRAFTED_LINK })
    assert.same({
      "GoldCap value = 2000000", "Listings = 12",
      "Makes R0CKY-To-Go", "GoldCap value = 129366", "Sold per day = 95",
    }, lines)
  end)

  it("draws no heading when GoldCap knows nothing of the crafted item", function()
    values[RECIPE] = { mv = 2000000, listings = 12, ts = time() }
    postCall(_G.GameTooltip, { id = RECIPE, hyperlink = CRAFTED_LINK })
    assert.same({ "GoldCap value = 2000000", "Listings = 12" }, lines)
  end)

  it("names the item from the game when the hyperlink carries no name", function()
    _G.C_Item.GetItemNameByID = function(id) return id == CRAFTED and "R0CKY-To-Go" or nil end
    values[CRAFTED] = { mv = 129366, sold = 95, ts = time() }
    postCall(_G.GameTooltip, { id = RECIPE, hyperlink = "item:275676" })
    assert.equal("Makes R0CKY-To-Go", lines[1])
  end)

  it("draws the Companion nudge once, under whichever block comes first", function()
    GC.Data.OriginState = function() return "none" end
    values[RECIPE] = { mv = 2000000, listings = 12, ts = time(), source = "bundled" }
    values[CRAFTED] = { mv = 129366, sold = 95, ts = time(), source = "bundled" }
    postCall(_G.GameTooltip, { id = RECIPE, hyperlink = CRAFTED_LINK })
    local nudges = 0
    for _, text in ipairs(lines) do
      if text:find("/goldcap companion", 1, true) then nudges = nudges + 1 end
    end
    assert.equal(1, nudges)
    assert.truthy(table.concat(lines, " | "):find("Makes R0CKY-To-Go", 1, true))
  end)

  -- Only a recipe's payload is read this way: any other item whose id and link disagree keeps the
  -- old lookup, the hyperlink first, with no heading.
  it("leaves an item that is not a recipe as it was", function()
    values[CRAFTED] = { mv = 129366, sold = 95, ts = time() }
    postCall(_G.GameTooltip, { id = OTHER, hyperlink = CRAFTED_LINK })
    assert.same({ "GoldCap value = 129366", "Sold per day = 95" }, lines)
  end)

  it("leaves an ordinary item tooltip as it was", function()
    values[CRAFTED] = { mv = 129366, sold = 95, ts = time() }
    postCall(_G.GameTooltip, { id = CRAFTED, hyperlink = CRAFTED_LINK })
    assert.same({ "GoldCap value = 129366", "Sold per day = 95" }, lines)
  end)
end)
