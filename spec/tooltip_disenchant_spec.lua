local helper = require("spec.spec_helper")

-- GoldCap's line on the tooltip of a bag item for a character with Disenchant (UI/Tooltip.lua): one
-- line in GoldCap's two columns, "Disenchant" and what its kind gives with where the item stands
-- (the owner, 2026-10-26: two long lines wrapped). It comes after the lines the tooltip already had
-- and adds no auction house figure of its own. The standing is
-- GC.DisenchantFrame.Standing's, a seam here (spec/disenchant_frame_spec.lua tests it).
describe("Tooltip on a bag item for an enchanter", function()
  local GC, postCall, lines, values, standing, asked, owner

  local ITEM = 501
  local LINK = "|cnIQ2:|Hitem:501::::::::80:::::|h[Belt]|h|r"

  before_each(function()
    postCall, lines, values, standing, asked = nil, {}, {}, nil, {}
    owner = { name = "bag button" }
    _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
    _G.Enum = { TooltipDataType = { Item = 0 } }
    _G.GameTooltip = {
      GetOwner = function() return owner end,
      AddLine = function(_, text) lines[#lines + 1] = text end,
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

  -- What the right column reads, the coins as letters.
  local function right(i)
    local text = lines[i or 1] or ""
    text = text:gsub("|TInterface\\MoneyFrame\\UI%-GoldIcon[^|]*|t", "g")
    text = text:gsub("|TInterface\\MoneyFrame\\UI%-SilverIcon[^|]*|t", "s")
    return text
  end

  it("draws it on the Disenchant window's own tooltip, read off its owner, and on no other tooltip", function()
    standing = { state = "listed", n = 0 }
    local row = { name = "window line" }
    local own = {
      GetOwner = function() return row end,
      AddLine = function(_, text) lines[#lines + 1] = text end,
      AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " = " .. r end,
    }
    local other = { GetOwner = own.GetOwner, AddLine = own.AddLine, AddDoubleLine = own.AddDoubleLine }
    GC.Tooltip.Carriers[own] = true
    postCall(other, { hyperlink = LINK })
    assert.same({}, lines)
    postCall(own, { hyperlink = LINK })
    assert.same({ { row, ITEM } }, asked)
    assert.equal("Disenchant = not learned yet", lines[1])
  end)

  it("gives a listed item's mats in whole gold, an estimate", function()
    standing = { state = "listed", mats = 102114, n = 1 }
    hover()
    assert.same({ "Disenchant = ~10g" }, { right() })
  end)

  -- Under a gold the client's own coins draw it (GetCoinTextureString, a seam here that prints the
  -- copper): 21s 14c goes as 21s.
  it("gives mats under a gold in whole silver", function()
    standing = { state = "listed", mats = 2114, n = 4 }
    hover()
    assert.equal("Disenchant = ~2100", right())
  end)

  it("says the next one is next", function()
    standing = { state = "next", mats = 102114, n = 1 }
    hover()
    assert.equal("Disenchant = ~10g, next", right())
  end)

  it("says why a left-out item is out: the auction house or a vendor pays more", function()
    standing = { state = "left", mats = 102114, n = 1 }
    hover()
    assert.equal("Disenchant = ~10g, AH pays more", right())
    lines = {}
    standing = { state = "leftVendor", mats = 102114, n = 1 }
    hover()
    assert.equal("Disenchant = ~10g, vendor pays more", right())
  end)

  it("says a kept item is kept, and one the game refuses cannot be disenchanted, with no mats", function()
    standing = { state = "kept", mats = 102114, n = 1 }
    hover()
    assert.same({ "Disenchant = kept" }, lines)
    lines = {}
    standing = { state = "cant", mats = 102114, n = 3 }
    hover()
    assert.same({ "Disenchant = cannot be disenchanted" }, lines)
  end)

  it("says a kind is not learned yet, or that a material has no price yet", function()
    standing = { state = "next", n = 0 }
    hover()
    assert.same({ "Disenchant = not learned yet, next" }, lines)
    lines = {}
    standing = { state = "listed", mats = nil, n = 5 }
    hover()
    assert.same({ "Disenchant = no price yet" }, lines)
  end)

  it("comes after GoldCap's own lines, one line, and adds no auction house figure", function()
    values[ITEM] = { mv = 129366, sold = 95, ts = time() }
    standing = { state = "next", n = 0 }
    hover()
    assert.same({
      "GoldCap value = 129366", "Sold per day = 95",
      "Disenchant = not learned yet, next",
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
