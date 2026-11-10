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

  local families, failFamily, savedNormal

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
    savedNormal = _G.GameFontNormal
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
    for name in pairs(_G) do
      if type(name) == "string" and name:find("^GoldCapClassic") then _G[name] = nil end
    end
    _G.CreateFontFamily, _G.GameFontNormal, _G.CreateColor = nil, savedNormal, nil
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
    assert.same({ 0, 106 / 128, 0, 1 }, W.state(plate).texCoord)
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
    -- The glow covers the icon and no more, as on the client's own action buttons: at 46px it
    -- reached 3px under the icon onto the label (owner, round B 2026-11-10).
    assert.equal(b.icon:GetWidth(), b.selected:GetWidth())
    assert.equal(b.icon:GetWidth(), b.highlightTexture:GetWidth())
    -- The label hangs 2px under the icon (the board's gap), so a larger font scale grows it down.
    local point, relativeTo, relativePoint, x, y = b.text:GetPoint(1)
    assert.same({ "TOP", b.icon, "BOTTOM", 0, -2 }, { point, relativeTo, relativePoint, x, y })
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
    Skins.Apply("goldcap")
    local g = T.Heading(parent, 12)
    assert.is_nil(W.state(g).fontObject)
    assert.equal(T.FONT_HEAD, (g:GetFont()))
  end)

  -- The font-scale slider moves Classic's words too: a family for the scaled size (in half-pixel
  -- steps, so a slider drag makes few), put on again at every scale, keeping the text's colour.
  it("words follow the font scale through a family per scaled size", function()
    Skins.Apply("classic")
    local parent = W.CreateFrame("Frame")
    local h = T.Heading(parent, 12)
    local l = T.Label(parent, 13)
    h:SetTextColor(1, 0.82, 0, 1)
    T.SetScale(1.2)
    assert.equal("GoldCapClassic14_5", W.state(h).fontObject.name) -- 14.4
    assert.equal("GoldCapClassic15_5", W.state(l).fontObject.name) -- 15.6
    assert.same({ 1, 0.82, 0, 1 }, W.state(h).color)
    local built = T.Heading(parent, 10)
    assert.equal("GoldCapClassic12", W.state(built).fontObject.name)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    assert.is_true(T.UseClientFont(fs, 10))
    assert.equal("GoldCapClassic12", W.state(fs).fontObject.name)
    T.SetScale(1.0)
    assert.equal(T.ClassicFont(12), W.state(h).fontObject)
    assert.equal(T.ClassicFont(13), W.state(l).fontObject)
    assert.same({ 1, 0.82, 0, 1 }, W.state(h).color)
  end)

  it("GameFontNormal keeps its own size at every scale", function()
    Skins.Apply("classic")
    failFamily = true
    local normal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
    _G.GameFontNormal = normal
    local h = T.Heading(W.CreateFrame("Frame"), 13)
    T.SetScale(1.3)
    assert.equal(normal, W.state(h).fontObject)
    assert.equal(12, W.state(h).font[2])
    T.SetScale(1.0)
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

  -- The plate says "GoldCap" over the top edge: a floating window's own title would say it twice.
  it("hides the window's own title while the plate shows, and gives it back docked", function()
    Skins.Apply("classic")
    local f = windowFrame()
    local win = T.Window(f)
    local title = f:CreateFontString(nil, "OVERLAY")
    win:CoverTitle(title)
    assert.is_false(shown(title))
    win:SetDocked(true)
    assert.is_true(shown(title))
    win:SetDocked(false)
    assert.is_false(shown(title))
    for _, id in ipairs({ "goldcap", "horde" }) do
      Skins.Apply(id)
      local other = T.Window(windowFrame())
      local own = f:CreateFontString(nil, "OVERLAY")
      other:CoverTitle(own)
      other:SetDocked(true)
      other:SetDocked(false)
      assert.is_true(shown(own), id)
    end
    Skins.Apply("classic")
    local inside = T.Window(windowFrame(), { inside = true })
    local kept = f:CreateFontString(nil, "OVERLAY")
    inside:CoverTitle(kept)
    assert.is_true(shown(kept))
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

  it("the dock's panel sits on its parent's level, under the posting panel's own text", function()
    Skins.Apply("classic")
    local container = W.CreateFrame("Frame")
    local label = container:CreateFontString(nil, "OVERLAY") -- a region of the posting panel
    local panel = T.ClientPanel(container, 0.94)
    assert.is_true(W.state(panel).usingParentLevel)
    assert.equal(container:GetFrameLevel(), panel:GetFrameLevel())
    local button = W.CreateFrame("Button", nil, container)
    assert.is_true(button:GetFrameLevel() > panel:GetFrameLevel())
    assert.is_not_nil(label)
    assert.equal(0.94, W.state(panel).backdropColor[4])
    -- the gold border of a window is on the level of its frame overlay, over the window's controls
    local f = windowFrame()
    local win = T.Window(f)
    assert.is_true(W.state(win.ring).usingParentLevel)
    assert.equal(win.overlay, W.state(win.ring).parent)
  end)

  it("a formerly square button keeps its 12px label", function()
    Skins.Apply("classic")
    local square = T.Button(W.CreateFrame("Frame"), "ghost")
    local rounded = T.Button(W.CreateFrame("Frame"), "ghost", "plaque")
    assert.equal(12, select(2, square.text:GetFont()))
    assert.equal(10, select(2, rounded.text:GetFont()))
  end)

  it("classic tabs are dark gradient tabs, filters light their check box on hover", function()
    Skins.Apply("classic")
    local tab = T.Button(W.CreateFrame("Frame"), "segment", "plaque")
    assert.same({ 0, 0, 0, 0 }, W.state(tab.bg).slice)
    assert.is_not_nil(W.state(tab.bg).gradient)
    assert.is_nil(W.state(tab.bg).file)
    tab:SetVariant("active")
    assert.same({ K.text1[1], K.text1[2], K.text1[3], 1 }, W.state(tab.text).color)
    local chip = T.Button(W.CreateFrame("Frame"), "ghost", "badge")
    chip:SetCheckStyle()
    assert.equal("Interface\\Buttons\\UI-CheckBox-Highlight", W.state(chip.highlightTexture).file)
    assert.equal("ADD", W.state(chip.highlightTexture).blend)
  end)

  it("item icons wear the quickslot frame, shown with the icon", function()
    Skins.Apply("classic")
    local f = W.CreateFrame("Frame")
    local icon = f:CreateTexture(nil, "ARTWORK")
    local frame = T.IconFrame(icon, f)
    assert.equal("Interface\\Buttons\\UI-Quickslot2", W.state(frame).file)
    Skins.Apply("goldcap")
    assert.is_nil(T.IconFrame(icon, f))
  end)

  it("brand text and the Hoard's name draw through the client's face", function()
    Skins.Apply("classic")
    assert.is_true(T.ClientFonts())
    local fs = W.CreateFrame("Frame"):CreateFontString(nil, "OVERLAY")
    assert.is_true(T.UseClientFont(fs, 14))
    assert.equal(T.ClassicFont(14), W.state(fs).fontObject)
    Skins.Apply("goldcap")
    assert.is_false(T.ClientFonts())
  end)

  it("a switch side set to primary draws the selected tab, and back to idle", function()
    Skins.Apply("classic")
    local side = T.Button(W.CreateFrame("Frame"), "segment", "plaque")
    local function stops() local g = W.state(side.bg).gradient return { g[2].r, g[3].r } end
    local idle = stops()
    side:SetVariant("primary")
    assert.same({ K.plateOnBottom[1], K.plateOnTop[1] }, stops())
    assert.same({ K.text1[1], K.text1[2], K.text1[3], 1 }, W.state(side.text).color)
    side:SetVariant("segment")
    assert.same(idle, stops())
    assert.same({ K.plateBottom[1], K.plateTop[1] }, idle)
    assert.same({ K.goldText[1], K.goldText[2], K.goldText[3], 1 }, W.state(side.text).color)
  end)
end)
