local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- The Classic skin: the client's own textures by path, and the client's own face through a Font
-- family per size.
describe("classic skin", function()
  local GC, T, Skins, K, restore, MEDIA

  local MARBLE = "Interface\\FrameGeneral\\UI-Background-Marble"
  local GOLD_BORDER = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border"
  local GOLD_HEADER = "Interface\\DialogFrame\\UI-DialogBox-Gold-Header"
  local NAME_FRAME = "Interface\\AuctionFrame\\UI-AuctionItemNameFrame"
  local PANEL_BUTTON = "Interface\\Buttons\\UI-Panel-Button-Up"

  local families, failFamily

  local function shown(t) return t ~= nil and t:IsShown() end

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

  before_each(function()
    restore = W.install()
    W.missingTextures = {}
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    families = {}
    failFamily = false
    -- CreateFontFamily(name, members) makes a global Font object of that name.
    _G.CreateFontFamily = function(name, members)
      if failFamily then error("no families here") end
      local font = { name = name, members = members }
      function font:GetFont() return members[1].file, members[1].height, "" end
      families[#families + 1] = font
      _G[name] = font
      return font
    end
    GC = helper.loadModule("UI/Theme.lua")
    T, Skins, K = GC.Theme, GC.Kit.Skins, GC.Kit.Tokens.color
    MEDIA = T.MEDIA
    T.RefreshFonts("enUS")
  end)

  after_each(function()
    Skins.Apply("goldcap")
    restore()
    for _, size in ipairs({ 9.5, 10, 12, 13, 16 }) do _G["GoldCapClassic" .. size] = nil end
    _G.CreateFontFamily, _G.GameFontNormal, _G.CreateColor = nil, nil, nil
    W.missingTextures = {}
  end)

  it("classic draws with the client's textures", function()
    Skins.Apply("classic")
    local f = windowFrame()
    local win = T.Window(f)
    assert.equal(MARBLE, W.state(win.fill[1]).file)
    assert.is_true(W.state(win.fill[1]).horizTile)
    assert.is_true(W.state(win.fill[1]).vertTile)
    -- the gold dialog border is a backdrop edge of 40px, 14px outside the window
    local border = win.ring
    assert.equal(GOLD_BORDER, W.state(border).backdrop.edgeFile)
    assert.equal(40, W.state(border).backdrop.edgeSize)
    assert.same({ "TOPLEFT", f, "TOPLEFT", -14, 14 }, W.state(border).points[1])
    assert.same({ "BOTTOMRIGHT", f, "BOTTOMRIGHT", 14, -14 }, W.state(border).points[2])
    -- the title plate: the header cropped (58,0)-(197,40) of its 256x64 file, 236x66 over the top edge
    local plate = win.title
    assert.equal(GOLD_HEADER, W.state(plate).file)
    assert.same({ 58 / 256, 197 / 256, 0, 40 / 64 }, W.state(plate).texCoord)
    assert.equal(236, plate:GetWidth())
    assert.equal(66, plate:GetHeight())
    assert.equal("GoldCap", win.titleText:GetText())
    assert.same({ 1, 1, 1, 1 }, W.state(win.titleText).color)
    assert.is_true(shown(win.shadow))
  end)

  it("list rows are the client's name frame", function()
    Skins.Apply("classic")
    local plate = T.RowPlate(W.CreateFrame("Frame"))
    assert.equal(NAME_FRAME, W.state(plate).file)
    assert.same({ 0, 106 / 256, 0, 1 }, W.state(plate).texCoord)
    assert.same({ 8, 8, 8, 8 }, W.state(plate).slice)
    Skins.Apply("goldcap")
    assert.is_nil(T.RowPlate(W.CreateFrame("Frame")))
  end)

  it("every button is the client's panel button with a gold label", function()
    Skins.Apply("classic")
    for _, args in ipairs({ { "primary", "plaque" }, { "ghost", "badge" }, { "danger" } }) do
      local b = T.Button(W.CreateFrame("Frame"), args[1], args[2])
      assert.equal(PANEL_BUTTON, W.state(b.bg).file, args[1])
      assert.same({ 0, 80 / 128, 0, 22 / 32 }, W.state(b.bg).texCoord)
      assert.same({ 10, 5, 10, 5 }, W.state(b.bg).slice)
      assert.same({ 1, 1, 1, 1 }, W.state(b.bg).vertex)
      assert.is_nil(b.ring)
      b:SetLabel("Post")
      assert.same({ K.goldText[1], K.goldText[2], K.goldText[3], 1 }, W.state(b.text).color)
    end
    Skins.Apply("goldcap")
    local b = T.Button(W.CreateFrame("Frame"), "primary", "plaque")
    assert.equal(MEDIA .. "plaque.png", W.state(b.bg).file)
  end)

  it("the rail wears quickslot frames, the client's icons and a hilight on the selected one", function()
    Skins.Apply("classic")
    local b = T.RailButton(W.CreateFrame("Frame"), "deals", "DEALS")
    assert.equal("Interface\\Icons\\INV_Misc_Spyglass_02", W.state(b.icon).file)
    assert.equal(40, b.icon:GetWidth())
    assert.equal("Interface\\Buttons\\UI-Quickslot2", W.state(b.iconFrame).file)
    assert.same({ 12 / 64, 51 / 64, 12 / 64, 51 / 64 }, W.state(b.iconFrame).texCoord)
    assert.same({ 6, 6, 6, 6 }, W.state(b.iconFrame).slice)
    assert.equal("Interface\\Buttons\\CheckButtonHilight", W.state(b.selected).file)
    assert.equal("ADD", W.state(b.selected).blend)
    assert.equal(46, b.selected:GetWidth())
    assert.is_false(shown(b.selected))
    b:SetActive(true)
    assert.is_true(shown(b.selected))
    assert.same({ 1, 1, 1, 1 }, W.state(b.icon).vertex) -- the icon keeps its own colours
    assert.same({ K.railActive[1], K.railActive[2], K.railActive[3], 1 }, W.state(b.text).color)
  end)

  it("classic faces come from a family per size", function()
    Skins.Apply("classic")
    local a = T.ClassicFont(13)
    assert.is_not_nil(a)
    assert.equal(a, T.ClassicFont(13))
    assert.equal("GoldCapClassic13", a.name)
    assert.equal(1, #families)
    local alphabets = {}
    for _, m in ipairs(a.members) do
      alphabets[m.alphabet] = m.file
      assert.equal(13, m.height)
      assert.equal("", m.flags)
    end
    assert.same({ roman = "Fonts\\FRIZQT__.TTF", russian = "Fonts\\FRIZQT___CYR.TTF",
      korean = "Fonts\\2002.TTF", simplifiedchinese = "Fonts\\ARKai_T.ttf",
      traditionalchinese = "Fonts\\bLEI00D.ttf" }, alphabets)
    local b = T.ClassicFont(16)
    assert.is_not_equal(a, b)
    assert.equal(2, #families)
  end)

  it("a family the client already made is reused", function()
    Skins.Apply("classic")
    local mine = { name = "GoldCapClassic12" }
    _G.GoldCapClassic12 = mine
    assert.equal(mine, T.ClassicFont(12))
    assert.equal(0, #families)
  end)

  it("headings and labels draw through the family, figures stay Fira Mono", function()
    Skins.Apply("classic")
    local parent = W.CreateFrame("Frame")
    local h = T.Heading(parent, 12)
    assert.equal(T.ClassicFont(12), W.state(h).fontObject)
    local l = T.Label(parent, 13)
    assert.equal(T.ClassicFont(13), W.state(l).fontObject)
    local n = T.Num(parent, 12)
    assert.equal(T.FONT_MONO, (n:GetFont()))
    -- the font-scale slider cannot move a Font object; it must not break it either
    T.SetScale(1.2)
    assert.equal(T.ClassicFont(12), W.state(h).fontObject)
    T.SetScale(1.0)
    Skins.Apply("goldcap")
    local g = T.Heading(parent, 12)
    assert.is_nil(W.state(g).fontObject)
    assert.equal(T.FONT_HEAD, (g:GetFont()))
  end)

  it("a client that cannot make a family draws with GameFontNormal", function()
    Skins.Apply("classic")
    failFamily = true
    local normal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
    _G.GameFontNormal = normal
    assert.equal(normal, T.ClassicFont(13))
    local h = T.Heading(W.CreateFrame("Frame"), 13)
    assert.equal(normal, W.state(h).fontObject)
  end)

  it("a client with neither keeps the bundled face", function()
    Skins.Apply("classic")
    failFamily = true
    _G.GameFontNormal = nil
    assert.is_nil(T.ClassicFont(13))
    local h = T.Heading(W.CreateFrame("Frame"), 13)
    assert.is_nil(W.state(h).fontObject)
    assert.equal(T.FONT_HEADING, (h:GetFont()))
  end)

  it("docked classic has no gold border and no plate", function()
    Skins.Apply("classic")
    local f = windowFrame()
    local win = T.Window(f)
    win:SetDocked(true)
    assert.is_false(shown(win.ring))
    assert.is_false(shown(win.title))
    assert.is_false(shown(win.titleText))
    assert.is_false(shown(win.shadow))
    assert.is_true(shown(win.fill[1])) -- the marble stays
    win:SetDocked(false)
    assert.is_true(shown(win.ring))
    assert.is_true(shown(win.title))
    assert.is_true(shown(win.titleText))
    assert.is_true(shown(win.shadow))
  end)

  it("a window against a Blizzard frame draws classic's frame inside its edge", function()
    Skins.Apply("classic")
    local f = windowFrame()
    local win = T.Window(f, { inside = true })
    assert.is_nil(win.shadow)
    assert.is_nil(win.title)
    assert.same({ "TOPLEFT", f, "TOPLEFT", 0, 0 }, W.state(win.ring).points[1])
    assert.same({ "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0 }, W.state(win.ring).points[2])
    assert.equal(GOLD_BORDER, W.state(win.ring).backdrop.edgeFile)
  end)

  it("a client without the header draws the generated plate", function()
    W.missingTextures[GOLD_HEADER] = true
    Skins.Apply("classic")
    local win = T.Window(windowFrame())
    assert.equal(MEDIA .. "classic_header.png", W.state(win.title).file)
    assert.same({ 0, 1, 0, 1 }, W.state(win.title).texCoord)
    local file = io.open("GoldCap/Media/classic_header.png", "rb")
    assert.is_not_nil(file)
    file:close()
  end)

  it("the item panel and the posting panel wear the tooltip border over #10101f", function()
    Skins.Apply("classic")
    local panel = T.ClientPanel(W.CreateFrame("Frame"))
    local backdrop = W.state(panel).backdrop
    assert.equal("Interface\\Tooltips\\UI-Tooltip-Border", backdrop.edgeFile)
    assert.equal(14, backdrop.edgeSize)
    assert.same({ K.popup[1], K.popup[2], K.popup[3], 1 }, W.state(panel).backdropColor)
    Skins.Apply("goldcap")
    assert.is_nil(T.ClientPanel(W.CreateFrame("Frame")))
  end)
end)
