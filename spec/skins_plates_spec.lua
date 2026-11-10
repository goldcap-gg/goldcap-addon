local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- The rail, the tabs, the buttons and the chips in each skin: the framed plate the five plate skins
-- give them, the bar Pixel marks its selected rail button with, the primary button's colours, and
-- which skins draw a glow at all.
describe("skin plates", function()
  local GC, T, Skins, K, restore, MEDIA

  -- Every texture any frame of the spec made, so a file a widget draws can be checked on disk.
  local made

  local function parent()
    return _G.CreateFrame("Frame")
  end

  local function shown(t) return t ~= nil and t:IsShown() end
  local function rgb(c) return { c[1], c[2], c[3] } end
  local function stop(color) return { color.r, color.g, color.b } end

  before_each(function()
    restore = W.install()
    made = {}
    local create = _G.CreateFrame
    _G.CreateFrame = function(...)
      local f = create(...)
      local make = f.CreateTexture
      function f:CreateTexture(...)
        local t = make(self, ...)
        made[#made + 1] = t
        return t
      end
      return f
    end
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    GC = helper.loadModule("UI/Theme.lua")
    T, Skins, K = GC.Theme, GC.Kit.Skins, GC.Kit.Tokens.color
    MEDIA = T.MEDIA
    T.RefreshFonts("enUS")
  end)

  after_each(function()
    Skins.Apply("goldcap")
    restore()
    _G.CreateColor = nil
  end)

  it("goldcap rail is today's", function()
    Skins.Apply("goldcap")
    local b = T.RailButton(parent(), "deals", "DEALS")
    assert.equal(MEDIA .. "ring.png", W.state(b.ring).file)
    assert.equal(MEDIA .. "card.png", W.state(b.bg).file)
    assert.same({ 24, 24, 24, 24 }, W.state(b.ring).slice)
    assert.is_not_nil(b.glow)
    assert.is_nil(b.plate)
    b:SetActive(true)
    assert.is_true(shown(b.glow))
    assert.is_true(shown(b.ring))
    assert.same(rgb(K.railActive), { unpack(W.state(b.text).color, 1, 3) })
    b:SetActive(false)
    assert.same(rgb(K.railIdle), { unpack(W.state(b.text).color, 1, 3) })
  end)

  it("goldcap keeps today's rail label colours", function()
    Skins.Apply("goldcap")
    local b = T.RailButton(parent(), "deals", "DEALS")
    assert.same(rgb(T.color.fgDim), rgb(K.railIdle))
    assert.same(rgb(T.color.goldHi), rgb(K.railActive))
    assert.is_false(shown(b.ring))
  end)

  it("plates under forever", function()
    Skins.Apply("forever")
    local b = T.RailButton(parent(), "deals", "DEALS")
    assert.equal(MEDIA .. "plate_forever.png", W.state(b.ring).file)
    assert.same({ 1, 1, 1, 1 }, W.state(b.ring).vertex)
    assert.same({ 6, 6, 6, 6 }, W.state(b.ring).slice) -- the radius covers the 3px band
    assert.equal(MEDIA .. "plaque_r6.png", W.state(b.plateFill[5]).file)
    -- idle: the plate wears the idle pair, drawn all the time
    assert.is_true(shown(b.ring))
    assert.same(rgb(K.plateBottom), stop(W.state(b.plateFill[5]).gradient[2]))
    assert.same(rgb(K.plateTop), stop(W.state(b.plateFill[5]).gradient[3]))
    b:SetActive(true)
    assert.same(rgb(K.plateOnBottom), stop(W.state(b.plateFill[5]).gradient[2]))
    assert.same(rgb(K.plateOnTop), stop(W.state(b.plateFill[5]).gradient[3]))
    assert.is_true(shown(b.glow))
  end)

  it("every plate skin but classic bakes its ring, and classic draws the client's", function()
    for _, id in ipairs({ "forever", "horde", "alliance", "leather" }) do
      Skins.Apply(id)
      local b = T.RailButton(parent(), "deals", "DEALS")
      assert.equal(MEDIA .. "plate_" .. id .. ".png", W.state(b.ring).file, id)
    end
    Skins.Apply("classic")
    local b = T.RailButton(parent(), "deals", "DEALS")
    assert.is_nil(b.plateFill)
    assert.is_nil(b.glow)
  end)

  it("pixel marks the active rail button with a bar and no glow", function()
    Skins.Apply("pixel")
    local b = T.RailButton(parent(), "deals", "DEALS")
    assert.is_nil(b.glow)
    assert.is_false(shown(b.bar))
    b:SetActive(true)
    assert.is_true(shown(b.bar))
    assert.equal(3, b.bar:GetWidth())
    assert.same(rgb(K.gold), { unpack(W.state(b.bar).color, 1, 3) })
    b:SetActive(false)
    assert.is_false(shown(b.bar))
  end)

  it("glow false creates no glow in the rail, the buttons or the chips", function()
    for _, id in ipairs({ "pixel", "parchment", "classic" }) do
      Skins.Apply(id)
      made = {}
      local p = parent()
      T.RailButton(p, "deals", "DEALS")
      T.Button(p, "primary", "plaque")
      T.Button(p, "danger", "plaque"):SetGlow(true)
      T.Chip(p)
      for _, t in ipairs(made) do assert.not_equal(MEDIA .. "glow.png", W.state(t).file, id) end
      assert.is_nil(T.Button(p, "primary", "plaque").glow, id)
    end
  end)

  it("goldcap buttons are today's", function()
    Skins.Apply("goldcap")
    local b = T.Button(parent(), "primary", "plaque")
    assert.equal(MEDIA .. "plaque.png", W.state(b.bg).file)
    assert.same(rgb(K.gold), { unpack(W.state(b.bg).vertex, 1, 3) })
    assert.same(rgb(K.onGold), { unpack(W.state(b.text).color, 1, 3) })
    assert.is_nil(b.plateFill)
    assert.is_not_nil(b.glow)
    local ghost = T.Button(parent(), "ghost", "plaque")
    assert.equal(MEDIA .. "plaque_ring.png", W.state(ghost.ring).file)
    local badge = T.Button(parent(), "ghost", "badge")
    assert.equal(MEDIA .. "badge.png", W.state(badge.bg).file)
    assert.same({ 6, 6, 6, 6 }, W.state(badge.bg).slice)
  end)

  it("the primary button wears the skin's primary colours", function()
    Skins.Apply("horde")
    local b = T.Button(parent(), "primary", "plaque")
    local mid = W.state(b.plateFill[5]).gradient
    assert.same(rgb(K.primaryBottom), stop(mid[2]))
    assert.same(rgb(K.primaryTop), stop(mid[3]))
    assert.same(rgb(K.primaryText), { unpack(W.state(b.text).color, 1, 3) })
    assert.is_false(shown(b.bg))
  end)

  it("a plate skin's tab wears the plate, lit when selected", function()
    Skins.Apply("alliance")
    local b = T.Button(parent(), "segment", "plaque")
    assert.equal(MEDIA .. "plate_alliance.png", W.state(b.ring).file)
    assert.same({ 1, 1, 1, 1 }, W.state(b.ring).vertex)
    assert.is_true(shown(b.ring))
    assert.same(rgb(K.plateBottom), stop(W.state(b.plateFill[5]).gradient[2]))
    b:SetVariant("active")
    assert.same(rgb(K.plateOnBottom), stop(W.state(b.plateFill[5]).gradient[2]))
    assert.same(rgb(K.plateOnTop), stop(W.state(b.plateFill[5]).gradient[3]))
    b:SetVariant("segment")
    assert.same(rgb(K.plateTop), stop(W.state(b.plateFill[5]).gradient[3]))
  end)

  it("chips take the skin's chip radius, goldcap's today's pill", function()
    Skins.Apply("goldcap")
    local chip = T.Chip(parent())
    assert.equal(MEDIA .. "badge.png", W.state(chip.bg).file)
    assert.same({ 6, 6, 6, 6 }, W.state(chip.bg).slice)
    Skins.Apply("alliance")
    chip = T.Chip(parent())
    assert.equal(MEDIA .. "plaque_r10.png", W.state(chip.bg).file)
    assert.same({ 9, 9, 9, 9 }, W.state(chip.bg).slice)
    Skins.Apply("pixel")
    chip = T.Chip(parent())
    assert.equal(MEDIA .. "plaque_r0.png", W.state(chip.bg).file)
  end)

  -- WCAG relative luminance contrast of two {r, g, b} colours.
  local function contrast(a, b)
    local function lum(c)
      local function lin(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
      return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
    end
    local hi, lo = math.max(lum(a), lum(b)), math.min(lum(a), lum(b))
    return (hi + 0.05) / (lo + 0.05)
  end

  it("goldcap's rail fill is today's flat black at 22%", function()
    Skins.Apply("goldcap")
    local rail = T.Rail(parent())
    assert.equal(MEDIA .. "card_left.png", W.state(rail.frame.fill).file)
    assert.same({ 0, 0, 0, 0.22 }, W.state(rail.frame.fill).vertex)
  end)

  -- The rail lies flush against the window's left edge: its left corners are the window's, so no
  -- wedge of the window shows past them.
  it("cuts the rail's left corners at the window's radius, today's file for goldcap", function()
    local want = { goldcap = "card_left.png", forever = "card_left_r8.png", pixel = "card_left_r0.png",
      parchment = "card_left_r5.png", horde = "card_left_r5.png", alliance = "card_left_r8.png",
      midnight = "card_left_r10.png", classic = "card_left_r4.png", leather = "card_left_r6.png" }
    for _, id in ipairs(Skins.ORDER) do
      Skins.Apply(id)
      local fill = T.Rail(parent()).frame.fill
      local file = W.state(fill[1] or fill).file
      assert.equal(MEDIA .. want[id], file, id)
      assert.is_true(helper.shipsMedia(file, MEDIA), id)
    end
    Skins.Apply("goldcap")
    assert.same({ 24, 24, 24, 24 }, W.state(T.Rail(parent()).frame.fill).slice)
  end)

  it("squares the rail's corners docked, where the window's are, and keeps goldcap's", function()
    Skins.Apply("parchment") -- a gradient rail
    local rail = T.Rail(parent())
    local corner = { unpack(W.state(rail.frame.fill[1]).texCoord) }
    rail.SetDocked(true)
    assert.same(W.state(rail.frame.fill[5]).texCoord, W.state(rail.frame.fill[1]).texCoord)
    rail.SetDocked(false)
    assert.same(corner, W.state(rail.frame.fill[1]).texCoord)
    Skins.Apply("classic") -- a flat one
    local flat = T.Rail(parent())
    flat.SetDocked(true)
    assert.equal(MEDIA .. "card_left_r0.png", W.state(flat.frame.fill).file)
    assert.same({ 2, 2, 2, 2 }, W.state(flat.frame.fill).slice)
    flat.SetDocked(false)
    assert.equal(MEDIA .. "card_left_r4.png", W.state(flat.frame.fill).file)
    assert.same({ 4, 4, 4, 4 }, W.state(flat.frame.fill).slice)
    Skins.Apply("goldcap")
    local today = T.Rail(parent())
    today.SetDocked(true)
    assert.equal(MEDIA .. "card_left.png", W.state(today.frame.fill).file)
    assert.same({ 24, 24, 24, 24 }, W.state(today.frame.fill).slice)
  end)

  it("parchment's rail is the wood gradient and its labels read against it", function()
    Skins.Apply("parchment")
    local rail = T.Rail(parent())
    local mid = W.state(rail.frame.fill[5]).gradient
    assert.same(rgb(K.railBottom), stop(mid[2]))
    assert.same(rgb(K.railTop), stop(mid[3]))
    assert.same(rgb(Skins.defs.parchment.color.railTop), { 0x34 / 255, 0x24 / 255, 0x14 / 255 })
    assert.is_true(contrast(K.railIdle, K.railBottom) >= 3)
    assert.is_true(contrast(K.railActive, K.railBottom) >= 3)
  end)

  it("a plate skin draws no track behind plated tabs, and keeps the Craft switch's", function()
    local function track(plated)
      local sw = parent()
      GC.Theme.Parts.sunkenTrack(sw, plated)
      return sw.track
    end
    Skins.Apply("goldcap")
    assert.is_not_nil(track(true)) -- the Hoard's switches
    assert.is_not_nil(track(nil)) -- the Craft switch's badge-class tabs
    Skins.Apply("forever")
    assert.is_nil(track(true))
    assert.is_not_nil(track(nil))
  end)

  it("a plate ring's slice is its outline and band, and no more", function()
    assert.equal(3, T.ArtSlice("plate", 3, 2))
    assert.equal(6, T.ArtSlice("plate", 6, 2))
    Skins.Apply("horde")
    assert.same({ 3, 3, 3, 3 }, W.state(T.RailButton(parent(), "deals", "DEALS").ring).slice)
  end)

  it("ships every file the rail, the buttons and the chips draw in every skin", function()
    -- The check itself: a GoldCap path missing from Media fails, a client path is the client's.
    assert.is_false(helper.shipsMedia(MEDIA .. "does_not_exist.png", MEDIA))
    assert.is_nil(helper.shipsMedia("Interface\\Buttons\\UI-Panel-Button-Up", MEDIA))
    local checked = 0
    for _, id in ipairs(Skins.ORDER) do
      Skins.Apply(id)
      made = {}
      local p = parent()
      local rail = T.RailButton(p, "deals", "DEALS")
      rail:SetActive(true)
      for _, variant in ipairs({ "primary", "ghost", "segment", "active", "danger" }) do
        T.Button(p, variant, "plaque")
        T.Button(p, variant, "badge"):SetRing(K.gold)
      end
      T.Chip(p)
      for _, t in ipairs(made) do
        local file = W.state(t).file
        -- Classic's textures are the client's, by path: only GoldCap's own are looked for on disk.
        local ships = helper.shipsMedia(file, MEDIA)
        if ships ~= nil then
          checked = checked + 1
          assert.is_true(ships, id .. ": " .. file .. " is missing")
        end
      end
    end
    assert.is_true(checked > 50, "checked " .. checked)
  end)
end)
