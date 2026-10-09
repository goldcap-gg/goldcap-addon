local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

describe("kit surfaces", function()
  local GC, restore

  before_each(function()
    restore = W.install()
    -- The client's CreateColor (Blizzard_SharedXML's ColorMixin), down to the fields a Color has.
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    GC = helper.loadModule("UI/Theme.lua")
  end)

  after_each(function()
    restore()
    _G.CreateColor = nil
  end)

  it("cuts the window's fill from the rounded card in nine pieces, corners at 1:1", function()
    local win = GC.Theme.Window(W.CreateFrame("Frame"))
    assert.equal(9, #win.fill)
    for _, piece in ipairs(win.fill) do
      assert.equal(GC.Theme.MEDIA .. "card.png", W.state(piece).file)
      assert.equal("BACKGROUND", W.state(piece).layer)
    end
    assert.same({ 0, 0.25, 0, 0.25 }, W.state(win.fill[1]).texCoord)
    assert.same({ 0.25, 0.75, 0.25, 0.75 }, W.state(win.fill[5]).texCoord)
    assert.same({ 0.75, 1, 0.75, 1 }, W.state(win.fill[9]).texCoord)
    assert.equal(16, W.state(win.fill[1]).width)
    assert.equal(16, W.state(win.fill[1]).height)
    assert.equal(GC.Theme.MEDIA .. "ring.png", W.state(win.ring).file)
    assert.same({ 24, 24, 24, 24 }, W.state(win.ring).slice)
  end)

  it("shades the middle row from top to bottom and keeps the rows above and below flat to match", function()
    local win = GC.Theme.Window(W.CreateFrame("Frame"))
    local K = GC.Kit.Tokens.color
    for i = 1, 3 do assert.same(K.windowTop, W.state(win.fill[i]).vertex) end
    for i = 7, 9 do assert.same(K.windowBottom, W.state(win.fill[i]).vertex) end
    local bottom = { r = K.windowBottom[1], g = K.windowBottom[2], b = K.windowBottom[3], a = K.windowBottom[4] }
    local top = { r = K.windowTop[1], g = K.windowTop[2], b = K.windowTop[3], a = K.windowTop[4] }
    for i = 4, 6 do
      local gradient = W.state(win.fill[i]).gradient
      assert.equal("VERTICAL", gradient[1])
      -- SetGradient's minColor is the bottom edge, its maxColor the top
      assert.same(bottom, gradient[2])
      assert.same(top, gradient[3])
    end
  end)

  -- The owner's call (2026-10-09): the world shows through the window at 7%. The window often
  -- sits over the auction house, whose own rows then show faintly too; an addon cannot blur what
  -- is behind a frame (the only blur in either game's source is C_CharacterCreation's).
  it("lets 7% of what is behind it through, the same in every piece", function()
    local win = GC.Theme.Window(W.CreateFrame("Frame"))
    for i = 1, 9 do
      local vertex = W.state(win.fill[i]).vertex
      if vertex then assert.equal(0.93, vertex[4], "piece " .. i) end
    end
    for i = 4, 6 do
      local gradient = W.state(win.fill[i]).gradient
      assert.equal(0.93, gradient[2].a)
      assert.equal(0.93, gradient[3].a)
    end
  end)

  -- Seen in WoW: Forever (2026-10-09): drawn by a child frame, the glass sat at the level every
  -- control in the window has, and its fill covered the buttons' own fills -- an active button's
  -- gold plate -- and the window's own lines.
  it("is drawn by the window itself, so it is under every control in the window", function()
    local window = W.CreateFrame("Frame")
    local win = GC.Theme.Window(window)
    for i, piece in ipairs(win.fill) do assert.equal(window, piece:GetParent(), "piece " .. i) end
    assert.equal(window, win.ring:GetParent())
    assert.equal(window, win.shadow:GetParent())
    assert.same({}, W.state(window).children)
  end)

  -- The light beside AUTO (owner, 2026-10-09: "a blinking green thing that says it is working"):
  -- one look says whether Auto is running or held.
  describe("the live light", function()
    local K
    before_each(function() K = GC.Kit.Tokens.color end)

    local function light()
      local parent = W.CreateFrame("Frame")
      return GC.Theme.LiveDot(parent)
    end

    it("pulses a green halo round a green dot while live", function()
      local l = light()
      l:SetState("live")
      assert.is_true(l.dot:IsShown())
      assert.same({ K.profit[1], K.profit[2], K.profit[3], 1 }, W.state(l.dot).vertex)
      assert.is_true(l.halo:IsShown())
      assert.equal("ADD", W.state(l.halo).blend)
      assert.is_true(l.pulse:IsPlaying())
    end)

    it("starts the pulse once, not again on every repaint", function()
      local l = light()
      l:SetState("live"); l:SetState("live"); l:SetState("live")
      assert.equal(1, W.state(l.pulse).plays)
    end)

    it("holds still in amber while held", function()
      local l = light()
      l:SetState("live")
      l:SetState("held")
      assert.is_true(l.dot:IsShown())
      assert.same({ K.warn[1], K.warn[2], K.warn[3], 1 }, W.state(l.dot).vertex)
      assert.is_false(l.halo:IsShown())
      assert.is_false(l.pulse:IsPlaying())
    end)

    it("goes out on nil", function()
      local l = light()
      l:SetState("live")
      l:SetState(nil)
      assert.is_false(l.dot:IsShown())
      assert.is_false(l.halo:IsShown())
      assert.is_false(l.pulse:IsPlaying())
    end)
  end)

  it("hangs a soft shadow outside the frame, under everything else in it", function()
    local shadow = GC.Theme.Shadow(W.CreateFrame("Frame"), 18, 0.6)
    local s = W.state(shadow)
    assert.equal(GC.Theme.MEDIA .. "shadow.png", s.file)
    assert.same({ 24, 24, 24, 24 }, s.slice)
    assert.equal("BACKGROUND", s.layer)
    assert.equal(-8, s.sublevel)
    assert.same({ 0, 0, 0, 0.6 }, s.vertex)
    assert.same({ "TOPLEFT", -18, 18 }, s.points[1])
    assert.same({ "BOTTOMRIGHT", 18, -18 }, s.points[2])
  end)

  it("points a texture at an icon's cell in the atlas and tints it", function()
    local t = W.Texture(W.CreateFrame("Frame"))
    GC.Theme.SetIcon(t, "sell", { 1, 0, 0 })
    local s = W.state(t)
    assert.equal(GC.Kit.Icons.file, s.file)
    -- "sell" is cell 1: column 1, row 0, of 32px cells in a 512px sheet
    assert.same({ 1 / 16, 2 / 16, 0, 1 / 16 }, s.texCoord)
    assert.same({ 1, 0, 0, 1 }, s.vertex)
  end)

  it("fails loudly on an icon the atlas does not have", function()
    assert.has_error(function() GC.Theme.IconCoords("no-such-icon") end)
  end)
end)
