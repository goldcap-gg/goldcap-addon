local helper = require("spec.spec_helper")

-- Every GameTooltip in the addon opened with ANCHOR_RIGHT: the tooltip's bottom-left corner
-- pinned to the owner's top-right, growing up and to the right. For the Post button -- the
-- right-hand column of a window that can fill the screen -- there is no "right" to grow into.
-- The client then clamps the tooltip back onto the screen, which drags it left across the
-- list it describes and over the very button under the cursor, and a four-paragraph body
-- also runs into the top edge. Theme.TooltipAnchor reads where the owner sits and opens the
-- tooltip into the quadrant that has room.
describe("Theme.TooltipAnchor", function()
  local T

  -- `x, y` are the owner's centre in its own scaled space; `scale` its effective scale.
  local function owner(x, y, scale)
    return {
      GetCenter = function() return x, y end,
      GetEffectiveScale = function() return scale or 1 end,
    }
  end

  before_each(function()
    _G.CreateFrame = function() return { SetPoint = function() end, SetScript = function() end } end
    -- A 1000x600 screen at scale 1: the centre is (500, 300).
    _G.UIParent = {
      GetCenter = function() return 500, 300 end,
      GetEffectiveScale = function() return 1 end,
    }
    T = helper.loadModule("UI/Theme.lua", {}).Theme
  end)

  after_each(function()
    _G.CreateFrame = nil
    _G.UIParent = nil
  end)

  it("opens leftward and downward for a control in the top-right of the screen (the Post column)", function()
    assert.equal("ANCHOR_BOTTOMLEFT", T.TooltipAnchor(owner(900, 500)))
  end)

  it("opens leftward and upward for a control in the bottom-right", function()
    assert.equal("ANCHOR_LEFT", T.TooltipAnchor(owner(900, 100)))
  end)

  it("opens rightward and downward for a control in the top-left", function()
    assert.equal("ANCHOR_BOTTOMRIGHT", T.TooltipAnchor(owner(100, 500)))
  end)

  it("keeps the classic ANCHOR_RIGHT for a control in the bottom-left", function()
    assert.equal("ANCHOR_RIGHT", T.TooltipAnchor(owner(100, 100)))
  end)

  -- GetCenter answers in the owner's own scaled space. A control in the Sniper window (which
  -- carries its own scale) reporting x=400 at scale 1.5 is really at pixel 600 -- the right
  -- half of a 1000px screen, not the left. Comparing raw numbers would put the tooltip on the
  -- wrong side of the window whenever the player has scaled it.
  it("compares positions in screen pixels, not in the owner's own scaled units", function()
    assert.equal("ANCHOR_BOTTOMLEFT", T.TooltipAnchor(owner(400, 250, 1.5)))
    assert.equal("ANCHOR_RIGHT", T.TooltipAnchor(owner(400, 250, 1)))
  end)

  it("falls back to ANCHOR_RIGHT when the owner has no position yet", function()
    assert.equal("ANCHOR_RIGHT", T.TooltipAnchor(owner(nil, nil)))
    assert.equal("ANCHOR_RIGHT", T.TooltipAnchor({}))
    assert.equal("ANCHOR_RIGHT", T.TooltipAnchor(nil))
  end)

  it("falls back to ANCHOR_RIGHT where there is no screen to measure against (the test bed)", function()
    _G.UIParent = nil
    assert.equal("ANCHOR_RIGHT", T.TooltipAnchor(owner(900, 500)))
  end)
end)
