local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- Every rounded surface a window draws takes the applied skin's radius for its role (Theme.Shape):
-- a panel (radius[2]), a control such as a row or a well (radius[3]), a chip (radius[4]). Goldcap's
-- are today's files and margins, so nothing changes there; Pixel's are square.
describe("skin shapes", function()
  local GC, T, Skins, restore, MEDIA

  before_each(function()
    restore = W.install()
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    GC = helper.loadModule("UI/Theme.lua")
    T, Skins = GC.Theme, GC.Kit.Skins
    MEDIA = T.MEDIA
  end)

  after_each(function()
    Skins.Apply("goldcap")
    restore()
    _G.CreateColor = nil
  end)

  local function shape(role) return { T.Shape(role) } end

  it("gives goldcap today's files and margins for every role", function()
    Skins.Apply("goldcap")
    assert.same({ MEDIA .. "card.png", MEDIA .. "ring.png", T.SLICE.card }, shape("panel"))
    assert.same({ MEDIA .. "plaque.png", MEDIA .. "plaque_ring.png", T.SLICE.plaque }, shape("control"))
    assert.same({ MEDIA .. "badge.png", MEDIA .. "badge_ring.png", T.SLICE.badge }, shape("chip"))
  end)

  it("gives Pixel square art for every role", function()
    Skins.Apply("pixel")
    assert.same({ MEDIA .. "card_r0.png", MEDIA .. "ring_r0.png", 2 }, shape("panel"))
    assert.same({ MEDIA .. "plaque_r0.png", MEDIA .. "plaque_ring_r0.png", 2 }, shape("control"))
    assert.same({ MEDIA .. "plaque_r0.png", MEDIA .. "plaque_ring_r0.png", 2 }, shape("chip"))
  end)

  it("ships every skin's art for every role, cut no deeper than goldcap's", function()
    local deepest = {}
    Skins.Apply("goldcap")
    for _, role in ipairs({ "panel", "control", "chip" }) do deepest[role] = shape(role)[3] end
    for _, id in ipairs(Skins.ORDER) do
      Skins.Apply(id)
      for _, role in ipairs({ "panel", "control", "chip" }) do
        local fill, ring, slice = T.Shape(role)
        assert.is_true(helper.shipsMedia(fill, MEDIA), id .. " " .. role .. ": " .. fill)
        assert.is_true(helper.shipsMedia(ring, MEDIA), id .. " " .. role .. ": " .. ring)
        assert.is_true(slice <= deepest[role], id .. " " .. role)
      end
    end
  end)

  it("draws a small card and a switch's track square in Pixel and as today in goldcap", function()
    Skins.Apply("pixel")
    local card = T.Card(W.CreateFrame("Frame"), nil, nil, true)
    assert.equal(MEDIA .. "plaque_r0.png", W.state(card.bg).file)
    assert.equal(MEDIA .. "plaque_ring_r0.png", W.state(card.ring).file)
    local sw = W.CreateFrame("Frame")
    T.Parts.sunkenTrack(sw)
    assert.equal(MEDIA .. "plaque_r0.png", W.state(sw.track).file)
    assert.same({ 2, 2, 2, 2 }, W.state(sw.track).slice)
    Skins.Apply("goldcap")
    local today = T.Card(W.CreateFrame("Frame"), nil, nil, true)
    assert.equal(MEDIA .. "plaque.png", W.state(today.bg).file)
    assert.same({ 12, 12, 12, 12 }, W.state(today.bg).slice)
    local sw2 = W.CreateFrame("Frame")
    T.Parts.sunkenTrack(sw2)
    assert.equal(MEDIA .. "plaque.png", W.state(sw2.track).file)
    assert.same({ 12, 12, 12, 12 }, W.state(sw2.track).slice)
    assert.equal(MEDIA .. "plaque_ring.png", W.state(sw2.edge).file)
  end)

  it("points a texture at a role's art with its margins", function()
    Skins.Apply("horde")
    local t = W.CreateFrame("Frame"):CreateTexture(nil, "BACKGROUND")
    T.SetShape(t, "control", true)
    assert.equal(MEDIA .. "plaque_ring_r3.png", W.state(t).file)
    assert.same({ 3, 3, 3, 3 }, W.state(t).slice)
  end)

  -- The item panel and the dock carry a frame of their own in a bevel skin (the mock's .insp and
  -- .dock): the skin's bevel, baked in colour, the panel's at its panel radius and frame width, the
  -- dock's at its control radius and 1.5px.
  it("frames a panel and the dock in the skin's bevel, and nothing in a skin without one", function()
    Skins.Apply("horde")
    local host = W.CreateFrame("Frame")
    local panel = T.PanelBevel(host, "panel")
    assert.equal(host, W.state(panel).allPoints)
    assert.equal(MEDIA .. "bevel_horde_panel.png", W.state(panel).file)
    assert.same({ 1, 1, 1, 1 }, W.state(panel).vertex)
    assert.same({ 5, 5, 5, 5 }, W.state(panel).slice) -- radius 3, 1 + 3 + 1
    assert.equal("BORDER", W.state(panel).layer)
    local fill = host:CreateTexture(nil, "BACKGROUND")
    local dock = T.PanelBevel(host, "dock", fill)
    assert.equal(fill, W.state(dock).allPoints)
    assert.equal(MEDIA .. "bevel_horde_dock.png", W.state(dock).file)
    assert.same({ 4, 4, 4, 4 }, W.state(dock).slice) -- radius 3, 1 + 1.5 + 1
    for _, id in ipairs({ "goldcap", "pixel", "classic" }) do
      Skins.Apply(id)
      assert.is_nil(T.PanelBevel(W.CreateFrame("Frame"), "panel"), id)
      assert.is_nil(T.PanelBevel(W.CreateFrame("Frame"), "dock"), id)
    end
    for _, id in ipairs(Skins.ORDER) do
      Skins.Apply(id)
      for _, which in ipairs({ "panel", "dock" }) do
        local t = T.PanelBevel(W.CreateFrame("Frame"), which)
        if t then assert.is_true(helper.shipsMedia(W.state(t).file, MEDIA), id .. " " .. which) end
      end
    end
  end)

  -- Rounded art in a window comes from the kit, so it follows the skin. Left out: the marks that are
  -- round at their size whatever the skin (a coin, a dot), and the art GoldCap lays on Blizzard's
  -- own frames, which keeps today's look in every skin.
  local ROUND_OR_BLIZZARD = {
    ["GoldCap/UI/Sell/Row.lua"] = 2, -- the row's coin mark: a ring and a coin, 12 and 8px
    ["GoldCap/UI/MinimapButton.lua"] = 1, -- on the minimap
    ["GoldCap/UI/DisenchantMarks.lua"] = 1, -- on the bag's own buttons
  }

  it("leaves no window's rounded art to a file named in its own code", function()
    local found = {}
    local handle = assert(io.popen("ls GoldCap/UI/*.lua GoldCap/UI/Sell/*.lua"))
    for path in handle:lines() do
      local file = assert(io.open(path, "rb"))
      local text = file:read("*a")
      file:close()
      local n = 0
      for name in text:gmatch('"([%w_]+)%.png"') do
        if name == "card" or name == "ring" or name == "plaque" or name == "plaque_ring" or name == "badge"
          or name == "badge_ring" then n = n + 1 end
      end
      if n ~= (ROUND_OR_BLIZZARD[path] or 0) then found[#found + 1] = path .. ": " .. n end
    end
    handle:close()
    assert.same({}, found)
  end)
end)
