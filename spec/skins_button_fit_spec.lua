local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")
local Font = require("spec.support.font_metrics")

-- A button's label in a skin's heading face runs wider than Fira's, and a display face never goes
-- under 11px: a word that fits a fixed-width row button in goldcap can be cut in Horde or Leather.
-- Theme.Button draws such a label in goldcap's face and size instead (Theme.FitHeading), and asks
-- again whenever the label, the button's width or the font scale changes. Measured in the shipped
-- files (spec/support/font_metrics.lua), as the client measures them.
describe("skin button labels fit their button", function()
  local GC, T, Skins, restore
  local faces = {}

  local function width(path, text, size)
    local file = assert(tostring(path):match("[^\\]+$"), "no face")
    if not faces[file] then faces[file] = Font.load("GoldCap/Media/" .. file) end
    return faces[file]:width(text, size)
  end

  before_each(function()
    restore = W.install()
    W.FACE_WIDTH = width
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    -- Every face loads (Fonts.lua asks UIParent's scratch FontString).
    _G.UIParent = { CreateFontString = function() return { SetFont = function() return true end } end }
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    T, Skins = GC.Theme, GC.Kit.Skins
    T.RefreshFonts("ruRU")
  end)

  after_each(function()
    Skins.Apply("goldcap")
    T.SetScale(1.0)
    W.FACE_WIDTH = nil
    _G.UIParent, _G.CreateColor = nil, nil
    restore()
  end)

  local function face(fs)
    local font = W.state(fs).font
    return font[1]:match("[^\\]+$"), font[2]
  end

  -- A row button: the Sell tab's action (86px) or the Deals tab's Buy/Check (64px), its label in
  -- capitals as both draw it.
  local function rowButton(w, label)
    local b = T.Button(W.CreateFrame("Frame"), "ghost", "badge")
    b:SetSize(w, 18)
    b:SetUppercase(true)
    b:SetLabel(label)
    return b
  end

  it("draws Подтвердить and Проверка at 1.3 in Fira under horde and leather, and they fit", function()
    T.SetScale(1.3)
    for _, id in ipairs({ "horde", "leather" }) do
      Skins.Apply(id)
      for _, case in ipairs({ { 86, "Подтвердить" }, { 64, "Проверка" } }) do
        local b = rowButton(case[1], case[2])
        local file, size = face(b.text)
        assert.equal("FiraSansCondensed-Bold.ttf", file, id .. " " .. case[2])
        assert.is_true(math.abs(size - 10 * 1.3) < 1e-9, id .. " " .. case[2] .. " at " .. size)
        assert.is_true(b.text:GetUnboundedStringWidth() <= case[1], id .. " " .. case[2])
      end
    end
  end)

  it("keeps a label that fits in the skin's own face, at its floor", function()
    T.SetScale(1.3)
    Skins.Apply("horde")
    local file, size = face(rowButton(86, "Post").text)
    assert.equal("RuslanDisplay-Regular.ttf", file)
    assert.is_true(math.abs(size - 11 * 1.3) < 1e-9)
  end)

  it("asks again at every font scale, and for every label", function()
    Skins.Apply("horde")
    local b = rowButton(86, "Подтвердить") -- 85px in Ruslan at 1.0
    assert.equal("RuslanDisplay-Regular.ttf", (face(b.text)))
    T.SetScale(1.15)
    assert.equal("FiraSansCondensed-Bold.ttf", (face(b.text)))
    T.SetScale(1.0)
    assert.equal("RuslanDisplay-Regular.ttf", (face(b.text)))
    T.SetScale(1.3)
    b:SetLabel("Post")
    assert.equal("RuslanDisplay-Regular.ttf", (face(b.text)))
    b:SetLabel("Подтвердить")
    assert.equal("FiraSansCondensed-Bold.ttf", (face(b.text)))
  end)

  it("asks again when the button's width comes after its label", function()
    T.SetScale(1.3)
    Skins.Apply("horde")
    local b = T.Button(W.CreateFrame("Frame"), "primary", "badge")
    b:SetUppercase(true)
    b:SetLabel("Проверка")
    assert.equal("RuslanDisplay-Regular.ttf", (face(b.text))) -- no width yet: nothing to fit
    b:SetWidth(64)
    W.state(b).hooks.OnSizeChanged(b, 64, 22)
    assert.equal("FiraSansCondensed-Bold.ttf", (face(b.text)))
  end)

  it("counts the spinner's room while a post is out", function()
    Skins.Apply("leather")
    _G.CreateFrame = function(kind, name, parent, template)
      if template == "SpinnerTemplate" then return W.CreateFrame("Frame", name, parent) end
      return W.CreateFrame(kind, name, parent)
    end
    local b = rowButton(86, "Пост") -- fits the whole button, not the 71px beside the ring
    local wide = "Выставление…"
    b:SetUppercase(false)
    b:SetLabel(wide)
    local room = 86 - 15
    local own = width(GC.Kit.MEDIA .. "OldStandard-Bold.ttf", wide, 11)
    assert.is_true(own <= 86 and own > room, "the case needs a label between the two rooms: " .. own)
    assert.equal("OldStandard-Bold.ttf", (face(b.text)))
    b:SetBusy(true)
    assert.equal("FiraSansCondensed-Bold.ttf", (face(b.text)))
    b:SetBusy(false)
    assert.equal("OldStandard-Bold.ttf", (face(b.text)))
  end)

  it("measures a fitted button's labels in the skin's face, so they keep it", function()
    T.SetScale(1.3)
    Skins.Apply("horde")
    local b = rowButton(64, "Подтвердить")
    assert.equal("FiraSansCondensed-Bold.ttf", (face(b.text)))
    b:FitLabels({ "Подтвердить" }, 64)
    assert.equal("RuslanDisplay-Regular.ttf", (face(b.text)))
    assert.is_true(b.text:GetUnboundedStringWidth() <= b:GetWidth())
  end)

  it("changes nothing in goldcap: no second face, no size hook", function()
    T.SetScale(1.3)
    Skins.Apply("goldcap")
    local b = rowButton(86, "Подтвердить")
    local file, size = face(b.text)
    assert.equal("FiraSansCondensed-Bold.ttf", file)
    assert.is_true(math.abs(size - 13) < 1e-9)
    assert.is_nil(W.state(b).hooks)
    local narrow = rowButton(20, "Подтвердить")
    assert.equal("FiraSansCondensed-Bold.ttf", (face(narrow.text)))
    assert.is_nil(W.state(narrow).hooks)
  end)
end)
