local helper = require("spec.spec_helper")

-- GoldCap's lines on the tooltip of a bag item for a character with Disenchant (UI/Tooltip.lua): where
-- the item stands in the Disenchant window, and what its kind gave. They come after the lines the
-- tooltip already had and add no auction house figure of their own. The standing is
-- GC.DisenchantFrame.Standing's, a seam here (spec/disenchant_frame_spec.lua tests it).
describe("Tooltip on a bag item for an enchanter", function()
  local GC, postCall, lines, values, standing, asked, owner, wraps

  local ITEM = 501
  local LINK = "|cnIQ2:|Hitem:501::::::::80:::::|h[Belt]|h|r"

  before_each(function()
    postCall, lines, values, standing, asked, wraps = nil, {}, {}, nil, {}, {}
    owner = { name = "bag button" }
    _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
    _G.Enum = { TooltipDataType = { Item = 0 } }
    _G.GameTooltip = {
      GetOwner = function() return owner end,
      AddLine = function(_, text, _, _, _, wrap)
        lines[#lines + 1] = text
        wraps[#lines] = wrap
      end,
      AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. " = " .. right end,
    }
    _G.C_Item = { GetItemInfoInstant = function(link)
      local id = type(link) == "number" and link or tonumber(tostring(link):match("item:(%d+)"))
      return id, "", "", "", 0, 4, 4
    end }
    _G.GetCoinTextureString = function(n) return tostring(n) end
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Trigger.lua", GC)
    GC.db = { settings = { tooltip = true } }
    GC.Data = { GetItemValue = function(id) return values[id] end }
    GC.DisenchantFrame = { Standing = function(button, itemID)
      asked[#asked + 1] = { button, itemID }
      return standing
    end }
    helper.loadModule("UI/Tooltip.lua", GC)
  end)

  after_each(function()
    _G.TooltipDataProcessor, _G.Enum, _G.GameTooltip, _G.C_Item, _G.GetCoinTextureString = nil, nil, nil, nil, nil
  end)

  local function hover() postCall(_G.GameTooltip, { hyperlink = LINK }) end

  it("asks about the slot under the cursor and the item in it", function()
    hover()
    assert.same({ { owner, ITEM } }, asked)
  end)

  it("draws them on the Disenchant window's own tooltip, read off its owner, and on no other tooltip", function()
    standing = { state = "listed", n = 0 }
    local row = { name = "window line" }
    local own = {
      GetOwner = function() return row end,
      AddLine = function(_, text) lines[#lines + 1] = text end,
      AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. " = " .. right end,
    }
    local other = { GetOwner = own.GetOwner, AddLine = own.AddLine, AddDoubleLine = own.AddDoubleLine }
    GC.Tooltip.Carriers[own] = true
    postCall(other, { hyperlink = LINK })
    assert.same({}, lines)
    postCall(own, { hyperlink = LINK })
    assert.same({ { row, ITEM } }, asked)
    assert.equal("GoldCap: on the Disenchant list", lines[1])
  end)

  it("says the item is next, when it is, and that GoldCap learns the kind the first time", function()
    standing = { state = "next", n = 0 }
    hover()
    assert.same({
      "GoldCap: next to disenchant",
      "Disenchant: GoldCap learns what this gives the first time.",
    }, lines)
  end)

  it("says the item is on the list", function()
    standing = { state = "listed", n = 0 }
    hover()
    assert.equal("GoldCap: on the Disenchant list", lines[1])
  end)

  it("says the auction house pays more for a left-out item", function()
    standing = { state = "left", n = 0 }
    hover()
    assert.equal("GoldCap: left out of Disenchant, the auction house pays more", lines[1])
  end)

  it("says a vendor pays more for a left-out item", function()
    standing = { state = "leftVendor", n = 0 }
    hover()
    assert.equal("GoldCap: left out of Disenchant, a vendor pays more", lines[1])
  end)

  it("says a kept item is never disenchanted, and where to undo it", function()
    standing = { state = "kept", n = 0 }
    hover()
    assert.equal("GoldCap: kept, never disenchanted. Undo it in the Disenchant window.", lines[1])
  end)

  it("gives the mats a kind learned, and how many disenchants it comes from", function()
    standing = { state = "listed", mats = 3800, n = 24 }
    hover()
    assert.same({
      "GoldCap: on the Disenchant list",
      "Disenchant: about 3800 in mats, from your 24 disenchants of such items",
    }, lines)
  end)

  it("says it has no price yet, not that it learns it, when the kind is learned but a material has none", function()
    standing = { state = "listed", mats = nil, n = 5 }
    hover()
    assert.equal("GoldCap has no price yet for what this gives.", lines[2])
  end)

  it("says one disenchant in the singular", function()
    standing = { state = "listed", mats = 3800, n = 1 }
    hover()
    assert.equal("Disenchant: about 3800 in mats, from your 1 disenchant of such an item", lines[2])
  end)

  it("lets a long line wrap, so it does not widen the tooltip", function()
    standing = { state = "left", n = 0 }
    hover()
    assert.is_true(wraps[1])
    assert.is_true(wraps[2])
  end)

  it("comes after GoldCap's own lines and adds no auction house figure", function()
    values[ITEM] = { mv = 129366, sold = 95, ts = time() }
    standing = { state = "next", n = 0 }
    hover()
    assert.same({
      "GoldCap value = 129366", "Sold per day = 95",
      "GoldCap: next to disenchant",
      "Disenchant: GoldCap learns what this gives the first time.",
    }, lines)
  end)

  it("adds nothing for an item that has no standing, or for a character without Disenchant", function()
    standing = nil
    hover()
    assert.same({}, lines)
  end)

  it("adds nothing when the file that owns the standing is not loaded", function()
    GC.DisenchantFrame = nil
    values[ITEM] = { mv = 129366, ts = time() }
    hover()
    assert.same({ "GoldCap value = 129366" }, lines)
  end)

  it("adds nothing when the tooltip has no owner", function()
    owner = nil
    standing = { state = "next", n = 0 }
    hover()
    assert.same({}, lines)
    assert.same({}, asked)
  end)

  it("is silent with the tooltip setting off", function()
    GC.db.settings.tooltip = false
    standing = { state = "next", n = 0 }
    hover()
    assert.same({}, lines)
  end)
end)
