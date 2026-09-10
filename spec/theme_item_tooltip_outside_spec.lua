local helper = require("spec.spec_helper")

-- GameTooltip:SetItemByID covers the board it is hovering over -- the row's own item tooltip
-- used to open ANCHOR_RIGHT off the row itself, which the client happily clamps back on top of
-- the window when there is no literal screen space to its right. T.ItemTooltipOutside instead
-- anchors off the WINDOW, never the row, so the tooltip lands beside the whole board rather
-- than wherever the clamp pushes it.
describe("Theme.ItemTooltipOutside", function()
  local T
  local tooltip

  local function windowFrame(right, top, scale)
    return {
      GetRight = function() return right end,
      GetTop = function() return top end,
      GetEffectiveScale = function() return scale or 1 end,
    }
  end

  local function rowFrame(top)
    return { GetTop = function() return top end }
  end

  before_each(function()
    tooltip = { points = {} }
    _G.GameTooltip = {
      SetOwner = function(_, owner, anchor) tooltip.owner, tooltip.anchor = owner, anchor end,
      ClearAllPoints = function() tooltip.cleared = true; tooltip.points = {} end,
      SetPoint = function(_, ...) tooltip.points[#tooltip.points + 1] = { ... } end,
    }
    -- A 1000px-wide screen at scale 1: the right edge sits at 1000.
    _G.UIParent = { GetRight = function() return 1000 end, GetEffectiveScale = function() return 1 end }
    T = helper.loadModule("UI/Theme.lua", {}).Theme
  end)

  after_each(function()
    _G.GameTooltip, _G.UIParent = nil, nil
  end)

  it("opens off the window's right edge, top-aligned to the row, when the right has room", function()
    local window = windowFrame(500, 300) -- 500 + 330 <= 1000: fits
    local row = rowFrame(280)
    T.ItemTooltipOutside(row, window)
    assert.equal(row, tooltip.owner)
    assert.equal("ANCHOR_NONE", tooltip.anchor)
    assert.is_true(tooltip.cleared)
    assert.same({ "TOPLEFT", window, "TOPRIGHT", 8, -20 }, tooltip.points[1])
  end)

  it("opens off the window's left edge when the right edge has no room", function()
    local window = windowFrame(800, 300) -- 800 + 330 > 1000: no room
    local row = rowFrame(260)
    T.ItemTooltipOutside(row, window)
    assert.equal("ANCHOR_NONE", tooltip.anchor)
    assert.same({ "TOPRIGHT", window, "TOPLEFT", -8, -40 }, tooltip.points[1])
  end)

  it("computes the y offset from the row's own top against the window's top", function()
    local window = windowFrame(100, 500)
    local row = rowFrame(420)
    T.ItemTooltipOutside(row, window)
    assert.equal(-80, tooltip.points[1][5])
  end)

  -- GetRight/GetTop answer in each frame's own scaled space, and the Sniper window carries its
  -- own scale (T.SetScale), so the right-edge comparison has to happen in screen pixels -- the
  -- same conversion T.TooltipAnchor's own scale test proves.
  it("compares the window's right edge in screen pixels, not the window's own scaled units", function()
    local scaledUp = windowFrame(400, 100, 2) -- 400 * 2 = 800px; 800 + 330 > 1000: no room
    T.ItemTooltipOutside(rowFrame(100), scaledUp)
    assert.equal("TOPRIGHT", tooltip.points[1][1])

    tooltip.points = {}
    local unscaled = windowFrame(400, 100, 1) -- 400 * 1 = 400px; 400 + 330 <= 1000: fits
    T.ItemTooltipOutside(rowFrame(100), unscaled)
    assert.equal("TOPLEFT", tooltip.points[1][1])
  end)

  it("falls back to ANCHOR_RIGHT off the row when the window has no geometry yet", function()
    T.ItemTooltipOutside(rowFrame(100), {})
    assert.equal("ANCHOR_RIGHT", tooltip.anchor)
    assert.is_nil(tooltip.points[1])
  end)

  it("falls back to ANCHOR_RIGHT when the row has no geometry yet", function()
    T.ItemTooltipOutside({}, windowFrame(500, 100))
    assert.equal("ANCHOR_RIGHT", tooltip.anchor)
  end)

  it("falls back to ANCHOR_RIGHT where there is no screen to measure against (the test bed)", function()
    _G.UIParent = nil
    T.ItemTooltipOutside(rowFrame(100), windowFrame(500, 100))
    assert.equal("ANCHOR_RIGHT", tooltip.anchor)
  end)

  it("falls back to ANCHOR_RIGHT off nil arguments rather than erroring", function()
    assert.has_no.errors(function() T.ItemTooltipOutside(nil, nil) end)
    assert.equal("ANCHOR_RIGHT", tooltip.anchor)
  end)
end)
