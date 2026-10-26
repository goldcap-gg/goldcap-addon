local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

describe("kit bar", function()
  local GC, restore

  before_each(function()
    restore = W.install()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("UI/Kit/Bar.lua", GC)
  end)

  after_each(function() restore() end)

  local function bar(width, color)
    local b = GC.Theme.Bar(W.CreateFrame("Frame"), 4, color)
    b:SetWidth(width)
    return b
  end

  local function fillWidth(b) return W.state(b.fill).width end

  it("draws the track the kit's quiet white and the fill in the colour it was given", function()
    local b = bar(200, { 0.1, 0.2, 0.3, 1 })
    assert.equal(4, b:GetHeight())
    assert.same({ 1, 1, 1, 0.08 }, W.state(b.track).color)
    assert.same({ 0.1, 0.2, 0.3, 1 }, W.state(b.fill).color)
  end)

  it("hides the fill at 0 and fills a share of the width above it", function()
    local b = bar(200)
    b:SetShare(0)
    assert.is_false(W.state(b.fill).shown)
    b:SetShare(0.5)
    assert.is_true(W.state(b.fill).shown)
    assert.equal(100, fillWidth(b))
    b:SetShare(1)
    assert.equal(200, fillWidth(b))
  end)

  it("clamps a share outside 0 to 1", function()
    local b = bar(200)
    b:SetShare(3)
    assert.equal(200, fillWidth(b))
    b:SetShare(-1)
    assert.is_false(W.state(b.fill).shown)
  end)

  it("follows a change of width", function()
    local b = bar(200)
    b:SetShare(0.5)
    b:SetWidth(300)
    W.state(b).scripts.OnSizeChanged(b, 300, 4)
    assert.equal(150, fillWidth(b))
  end)

  it("takes a new colour for the fill", function()
    local b = bar(200)
    b:SetColor({ 0.4, 0.5, 0.6 })
    assert.same({ 0.4, 0.5, 0.6, 1 }, W.state(b.fill).color)
  end)
end)
