local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- The Parchment skin: the quest paper for a fill, and item colours that stay readable on it.
describe("parchment skin", function()
  local GC, T, Skins, K, restore
  local GAME = {
    [0] = { r = 0.62, g = 0.62, b = 0.62, hex = "|cff9d9d9d" },
    [1] = { r = 1, g = 1, b = 1, hex = "|cffffffff" },
    [2] = { r = 0.12, g = 1, b = 0, hex = "|cff1eff00" },
    [3] = { r = 0, g = 0.44, b = 0.87, hex = "|cff0070dd" },
    [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "|cffa335ee" },
    [5] = { r = 1, g = 0.5, b = 0, hex = "|cffff8000" },
  }
  local qualities

  local function windowFrame()
    return W.CreateFrame("Frame")
  end

  before_each(function()
    restore = W.install()
    W.missingTextures = {}
    qualities = { [101] = 2, [102] = 3, [103] = 1, [104] = 4 }
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.C_Item = { GetItemQualityByID = function(id) return qualities[id] end }
    _G.ITEM_QUALITY_COLORS = GAME
    _G.C_Texture = { GetAtlasInfo = function(name) return name == "QuestBG-Parchment" and { width = 256 } or nil end }
    GC = helper.loadModule("UI/Theme.lua")
    T, Skins, K = GC.Theme, GC.Kit.Skins, GC.Kit.Tokens.color
  end)

  after_each(function()
    Skins.Apply("goldcap")
    _G.C_Item, _G.ITEM_QUALITY_COLORS, _G.C_Texture, _G.CreateColor = nil, nil, nil, nil
    restore()
  end)

  local function luminance(c)
    local function lin(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
  end
  local function contrast(a, b)
    local la, lb = luminance(a), luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
  end
  local function rgb(c) return { r = c[1], g = c[2], b = c[3] } end

  it("parchment darkens item quality", function()
    Skins.Apply("parchment")
    local c = T.QualityColor(101)
    assert.equal("|cff0c5300", c.hex)
    assert.is_near(0x0c / 255, c.r, 1e-6)
    assert.is_near(0x53 / 255, c.g, 1e-6)
    assert.is_near(0, c.b, 1e-6)
  end)

  it("other skins keep the game's colours", function()
    Skins.Apply("forever")
    assert.equal(GAME[2], T.QualityColor(101))
    Skins.Apply("goldcap")
    assert.equal(GAME[3], T.QualityColor(102))
    assert.is_nil(T.QualityColor(103)) -- common stays the interface's own text
  end)

  it("classic's rare is its own blue", function()
    Skins.Apply("classic")
    assert.equal("|cff2e8bff", T.QualityColor(102).hex)
    assert.equal(GAME[2], T.QualityColor(101)) -- the game's colours read on marble
  end)

  it("a quality number works like an itemID", function()
    Skins.Apply("parchment")
    assert.equal("|cff004394", T.QualityColor(3, true).hex)
    Skins.Apply("forever")
    assert.equal(GAME[2], T.QualityColor(2, true))
  end)

  it("goldcap returns the game's table unchanged", function()
    Skins.Apply("goldcap")
    assert.equal(GAME[4], T.QualityColor(104))
    assert.equal(GAME[2], T.QualityColor(2, true))
    assert.is_nil(T.SkinQuality(2))
  end)

  it("an item of common quality gets no colour on paper, a quality number 1 gets the body brown", function()
    Skins.Apply("parchment")
    assert.is_nil(T.QualityColor(103))
    local c = T.QualityColor(1, true)
    assert.same({ K.text1[1], K.text1[2], K.text1[3] }, { c.r, c.g, c.b })
  end)

  it("the parchment table covers every quality and passes contrast", function()
    Skins.Apply("parchment")
    local top, bottom = rgb(K.windowTop), rgb(K.windowBottom)
    for q = 0, 8 do
      local c = T.SkinQuality(q)
      assert.is_table(c, "quality " .. q)
      assert.is_true(contrast(c, top) >= 4.5, ("quality %d on the lighter stop: %.2f"):format(q, contrast(c, top)))
      assert.is_true(contrast(c, bottom) >= 4.5, ("quality %d on the darker stop: %.2f"):format(q, contrast(c, bottom)))
    end
  end)

  it("a Blizzard surface keeps the game's colour under parchment", function()
    Skins.Apply("parchment")
    assert.equal(GAME[2], T.QualityColor(101, false, true))
    assert.equal(GAME[3], T.QualityColor(3, true, true))
    assert.equal("|cff1eff00Wolf|r", T.WithQuality("Wolf", 101, nil, true))
    assert.equal("|cff0c5300Wolf|r", T.WithQuality("Wolf", 101))
  end)

  it("the quality-number path falls back to the game's table for every quality", function()
    Skins.Apply("forever")
    assert.equal(GAME[0], T.QualityColor(0, true))
    assert.equal(GAME[1], T.QualityColor(1, true))
    assert.is_nil(T.QualityColor(7, true))
  end)

  it("a skin's colour is made once", function()
    Skins.Apply("parchment")
    assert.equal(T.SkinQuality(2), T.SkinQuality(2))
  end)

  it("the window fill is the quest paper atlas", function()
    Skins.Apply("parchment")
    local f = windowFrame()
    local win = T.Window(f)
    assert.equal(1, #win.fill)
    assert.equal("QuestBG-Parchment", W.state(win.fill[1]).atlas)
  end)

  it("atlas missing -> parchment.png", function()
    _G.C_Texture = { GetAtlasInfo = function() return nil end }
    Skins.Apply("parchment")
    local win = T.Window(windowFrame())
    assert.is_nil(W.state(win.fill[1]).atlas)
    assert.equal(T.MEDIA .. "parchment.png", W.state(win.fill[1]).file)
  end)

  it("ships the fallback paper", function()
    local file = io.open("GoldCap/Media/parchment.png", "rb")
    assert.is_truthy(file)
    file:close()
  end)

  it("no C_Texture at all -> parchment.png", function()
    _G.C_Texture = nil
    Skins.Apply("parchment")
    local win = T.Window(windowFrame())
    assert.equal(T.MEDIA .. "parchment.png", W.state(win.fill[1]).file)
  end)

  it("a docked parchment window keeps its fill", function()
    Skins.Apply("parchment")
    local win = T.Window(windowFrame(), { inside = true })
    win:SetDocked(true)
    assert.is_true(win.fill[1]:IsShown())
    win:SetDocked(false)
    assert.is_true(win.fill[1]:IsShown())
  end)

  it("the paper sits 2px in from the edge, and fills a docked window", function()
    Skins.Apply("parchment")
    local f = windowFrame()
    local win = T.Window(f)
    local points = W.state(win.fill[1]).points
    assert.same({ "TOPLEFT", f, "TOPLEFT", 2, -2 }, points[1])
    assert.same({ "BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2 }, points[2])
    win:SetDocked(true)
    assert.equal(f, W.state(win.fill[1]).allPoints)
    assert.equal(0, #W.state(win.fill[1]).points)
    win:SetDocked(false)
    points = W.state(win.fill[1]).points
    assert.same({ "TOPLEFT", f, "TOPLEFT", 2, -2 }, points[1])
    assert.same({ "BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2 }, points[2])
  end)

  it("the other skins keep their gradient fill", function()
    Skins.Apply("forever")
    local win = T.Window(windowFrame())
    assert.equal(9, #win.fill)
  end)
end)
