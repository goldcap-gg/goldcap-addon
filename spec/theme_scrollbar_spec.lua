local helper = require("spec.spec_helper")

-- UIPanelScrollFrameTemplate brings Blizzard's own scrollbar: two arrow buttons and a knurled
-- thumb, floating beside a panel drawn in none of that style. Theme.QuietScrollBar keeps the
-- bar working and takes the chrome off it.
describe("Theme.QuietScrollBar", function()
  local GC

  local function region()
    local r = { calls = {} }
    function r:SetAlpha(a) self.alpha = a end
    function r:EnableMouse(on) self.mouse = on end
    function r:Hide() self.hidden = true end
    function r:SetTexture(file) self.texture = file end
    function r:SetTexCoord(...) self.texCoord = { ... } end
    function r:SetTextureSliceMargins(...) self.slice = { ... } end
    function r:SetVertexColor(...) self.vertex = { ... } end
    function r:SetSize(w, h) self.width, self.height = w, h end
    return r
  end

  before_each(function()
    GC = {}
    _G.CreateFrame = function() return region() end
    helper.loadModule("UI/Theme.lua", GC)
  end)
  after_each(function() _G.CreateFrame = nil end)

  it("takes the arrows out of sight and out of the cursor's way without hiding them", function()
    local bar = { ScrollUpButton = region(), ScrollDownButton = region(), ThumbTexture = region() }
    GC.Theme.QuietScrollBar({ ScrollBar = bar })
    for _, button in ipairs({ bar.ScrollUpButton, bar.ScrollDownButton }) do
      assert.equal(0, button.alpha)
      assert.is_false(button.mouse)
      -- The template's own scripts Enable/Disable these and anchor the track between them.
      assert.is_nil(button.hidden)
    end
  end)

  it("draws the thumb as a thin rounded bar in the panel's own quiet white", function()
    local bar = { ThumbTexture = region() }
    GC.Theme.QuietScrollBar({ ScrollBar = bar })
    local thumb = bar.ThumbTexture
    assert.equal(GC.Theme.MEDIA .. "bar.png", thumb.texture)
    assert.same({ 0, 1, 0, 1 }, thumb.texCoord)
    assert.same({ 2, 2, 2, 2 }, thumb.slice)
    assert.same({ 1, 1, 1, 0.22 }, thumb.vertex)
    assert.equal(4, thumb.width)
  end)

  it("puts away the track art a client version may or may not have", function()
    local bar = { Top = region(), Middle = region(), Bottom = region(), ThumbTexture = region() }
    GC.Theme.QuietScrollBar({ ScrollBar = bar })
    assert.is_true(bar.Top.hidden and bar.Middle.hidden and bar.Bottom.hidden)
  end)

  it("is a no-op for a frame with no scrollbar, and for one with no parts", function()
    assert.has_no.errors(function()
      GC.Theme.QuietScrollBar(nil)
      GC.Theme.QuietScrollBar({})
      GC.Theme.QuietScrollBar({ ScrollBar = {} })
    end)
  end)
end)
