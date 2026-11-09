local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- The skins' window frames: the ring, the ornament and the glow each skin draws around a window
-- built on T.Window, and what the window drops when it docks in the auction house.
describe("skin frames", function()
  local GC, T, Skins, K, restore, MEDIA

  local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close() return true end
    return false
  end

  -- A window frame that remembers every texture drawn on it.
  local function windowFrame()
    local f = W.CreateFrame("Frame")
    local made, create = {}, f.CreateTexture
    function f:CreateTexture(...)
      local t = create(self, ...)
      made[#made + 1] = t
      return t
    end
    return f, made
  end

  local function shown(t) return t ~= nil and t:IsShown() end

  before_each(function()
    restore = W.install()
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    GC = helper.loadModule("UI/Theme.lua")
    T, Skins, K = GC.Theme, GC.Kit.Skins, GC.Kit.Tokens.color
    MEDIA = T.MEDIA
  end)

  after_each(function()
    Skins.Apply("goldcap")
    restore()
    _G.CreateColor = nil
  end)

  it("names the art by radius and keeps today's files for today's radii", function()
    assert.equal(MEDIA .. "card.png", T.Art("card", 12))
    assert.equal(MEDIA .. "ring.png", T.Art("ring", 12))
    assert.equal(MEDIA .. "plaque.png", T.Art("plaque", 8))
    assert.equal(MEDIA .. "plaque_ring.png", T.Art("plaqueRing", 8))
    assert.equal(MEDIA .. "card_r5.png", T.Art("card", 5))
    assert.equal(MEDIA .. "ring_r0.png", T.Art("ring", 0))
    assert.equal(MEDIA .. "plaque_r3.png", T.Art("plaque", 3))
    assert.equal(MEDIA .. "plaque_ring_r6.png", T.Art("plaqueRing", 6))
    assert.equal(MEDIA .. "bevel_r8_w2.png", T.Art("bevel", 8, 2))
    assert.equal(MEDIA .. "bevel_r10_w1p5.png", T.Art("bevel", 10, 1.5))
    assert.equal(T.SLICE.card, T.ArtSlice("card", 12))
    assert.equal(T.SLICE.plaque, T.ArtSlice("plaque", 8))
    assert.equal(5, T.ArtSlice("card", 5))
    assert.equal(2, T.ArtSlice("card", 0))
    assert.equal(2, T.ArtSlice("ring", 1))
  end)

  it("ships every file a skin's window and panel draw", function()
    for _, id in ipairs(Skins.ORDER) do
      Skins.Apply(id)
      local f, made = windowFrame()
      T.Window(f)
      T.Card(f)
      T.Card(f, nil, nil, true)
      for _, t in ipairs(made) do
        local file = W.state(t).file
        if file then
          local onDisk = "GoldCap/Media/" .. file:match("[^\\]+$")
          assert.is_true(exists(onDisk), id .. ": " .. file .. " is missing")
        end
      end
    end
  end)

  it("goldcap builds today's window", function()
    Skins.Apply("goldcap")
    local win = T.Window(W.CreateFrame("Frame"))
    assert.equal(MEDIA .. "ring.png", W.state(win.ring).file)
    for _, piece in ipairs(win.fill) do assert.equal(MEDIA .. "card.png", W.state(piece).file) end
    assert.same({ 24, 24, 24, 24 }, W.state(win.ring).slice)
    assert.is_true(shown(win.shadow))
    assert.is_nil(win.ornament)
  end)

  it("forever builds a bronze bevel", function()
    Skins.Apply("forever")
    local win = T.Window(W.CreateFrame("Frame"))
    assert.equal(MEDIA .. "bevel_r8_w2.png", W.state(win.ring).file)
    local v = W.state(win.ring).vertex
    for i = 1, 3 do assert.equal(K.frameTint[i], v[i]) end
    assert.equal(MEDIA .. "card_r8.png", W.state(win.fill[1]).file)
    assert.same({ 8, 8, 8, 8 }, W.state(win.ring).slice)
    assert.is_true(shown(win.shadow))
  end)

  it("pixel has no glow and square corners", function()
    Skins.Apply("pixel")
    local win = T.Window(W.CreateFrame("Frame"))
    assert.is_false(shown(win.shadow))
    for _, piece in ipairs(win.fill) do assert.equal(MEDIA .. "card_r0.png", W.state(piece).file) end
    assert.equal(MEDIA .. "pixel_line.png", W.state(win.ring).file)
  end)

  it("each ornament comes with its skin", function()
    local expected = { horde = { 6, "rivet.png" }, alliance = { 4, "bracket.png" },
      midnight = { 2, "shimmer.png" }, leather = { 4, "stitch.png" } }
    for _, id in ipairs(Skins.ORDER) do
      Skins.Apply(id)
      local win = T.Window(W.CreateFrame("Frame"))
      local want = expected[id]
      if want then
        assert.equal(want[1], #win.ornament, id)
        for _, region in ipairs(win.ornament) do assert.equal(MEDIA .. want[2], W.state(region).file, id) end
      else
        assert.is_nil(win.ornament, id)
      end
    end
  end)

  it("leather tiles its grain over the gradient and midnight hangs a violet glow", function()
    Skins.Apply("leather")
    local f, made = windowFrame()
    T.Window(f)
    local tiled
    for _, t in ipairs(made) do
      if W.state(t).file == MEDIA .. "leather.png" then tiled = W.state(t) end
    end
    assert.is_not_nil(tiled)
    assert.is_true(tiled.horizTile)
    assert.is_true(tiled.vertTile)

    Skins.Apply("midnight")
    local win = T.Window(W.CreateFrame("Frame"))
    assert.equal(MEDIA .. "glow.png", W.state(win.glow).file)
    assert.equal(0.45, W.state(win.glow).vertex[4])
    assert.equal(K.gold[1], W.state(win.glow).vertex[1])
  end)

  -- The corner pieces show the centre piece's pixels, so the window's edge is square.
  local function squared(win)
    local centre = W.state(win.fill[5]).texCoord
    for _, i in ipairs({ 1, 3, 7, 9 }) do assert.same(centre, W.state(win.fill[i]).texCoord, "piece " .. i) end
  end

  local function framePieces(win)
    local list = { win.ring, win.shadow, win.glow }
    for _, extra in ipairs(win.frameExtra or {}) do list[#list + 1] = extra end
    for _, region in ipairs(win.ornament or {}) do list[#list + 1] = region end
    return list
  end

  it("docking hides the frame and squares the corners, every time", function()
    Skins.Apply("horde")
    local win = T.Window(W.CreateFrame("Frame"))
    local corner = { unpack(W.state(win.fill[1]).texCoord) }
    for round = 1, 2 do
      win:SetDocked(true)
      for i, region in ipairs(framePieces(win)) do assert.is_false(region:IsShown(), round .. "/" .. i) end
      squared(win)
      win:SetDocked(false)
      for i, region in ipairs(framePieces(win)) do assert.is_true(region:IsShown(), round .. "/" .. i) end
      assert.same(corner, W.state(win.fill[1]).texCoord)
      assert.same({ 1 - 0.25, 1, 0.75, 1 }, { unpack(W.state(win.fill[9]).texCoord) })
    end
    win:SetDocked(true)
    for i, region in ipairs(framePieces(win)) do assert.is_false(region:IsShown(), "last/" .. i) end
  end)

  it("docking under goldcap hides only the shadow, as it always has", function()
    Skins.Apply("goldcap")
    local win = T.Window(W.CreateFrame("Frame"))
    win:SetDocked(true)
    assert.is_false(win.shadow:IsShown())
    assert.is_true(win.ring:IsShown())
    assert.same({ 0, 0.25, 0, 0.25 }, W.state(win.fill[1]).texCoord)
    win:SetDocked(false)
    assert.is_true(win.shadow:IsShown())
    assert.is_true(win.ring:IsShown())
  end)

  -- True when a point of `t` hangs outside the window's own rect.
  local function outside(t)
    local s = W.state(t)
    for _, p in ipairs(s.points) do
      local point, rel, x, y = p[1], p[2], p[4] or 0, p[5] or 0
      if rel == nil then
        if point:find("LEFT") and x < 0 then return true end
        if point:find("RIGHT") and x > 0 then return true end
        if point:find("TOP") and y > 0 then return true end
        if point:find("BOTTOM") and y < 0 then return true end
      end
    end
    return false
  end

  it("windows against a Blizzard frame keep everything inside", function()
    for _, id in ipairs({ "horde", "midnight", "alliance", "leather", "forever" }) do
      Skins.Apply(id)
      local f, made = windowFrame()
      local win = T.Window(f, { inside = true })
      assert.is_nil(win.shadow, id)
      assert.is_nil(win.glow, id)
      for i, t in ipairs(made) do assert.is_false(outside(t), id .. " region " .. i) end
      assert.is_true(#made > 9, id)
    end
  end)

  it("keeps goldcap's shadow on a window against a Blizzard frame, as today", function()
    Skins.Apply("goldcap")
    local win = T.Window(W.CreateFrame("Frame"), { inside = true })
    assert.is_true(shown(win.shadow))
  end)

  it("gives a panel card the skin's panel radius", function()
    Skins.Apply("forever")
    local card = T.Card(W.CreateFrame("Frame"))
    assert.equal(MEDIA .. "card_r4.png", W.state(card.bg).file)
    assert.equal(MEDIA .. "ring_r4.png", W.state(card.ring).file)
    assert.same({ 4, 4, 4, 4 }, W.state(card.bg).slice)
    Skins.Apply("goldcap")
    local today = T.Card(W.CreateFrame("Frame"))
    assert.equal(MEDIA .. "card.png", W.state(today.bg).file)
    assert.same({ 24, 24, 24, 24 }, W.state(today.bg).slice)
    local small = T.Card(W.CreateFrame("Frame"), nil, nil, true)
    assert.equal(MEDIA .. "plaque.png", W.state(small.bg).file)
  end)
end)
