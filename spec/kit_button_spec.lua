local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

describe("kit button", function()
  local GC, restore

  before_each(function()
    restore = W.install()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    GC.Theme.RefreshFonts("enUS")
  end)

  after_each(function() restore() end)

  local function button(variant, rounded)
    return GC.Theme.Button(W.CreateFrame("Frame"), variant, rounded)
  end

  it("darkens while held through the engine's pushed state, not a mouse script", function()
    local b = button("ghost", "plaque")
    assert.equal(b.pressedTexture, W.state(b).pushed)
    assert.is_nil(W.state(b).scripts.OnMouseDown)
  end)

  it("labels in the condensed heading face: 10 rounded, 12 square", function()
    local rounded, square = button("ghost", "badge"), button("ghost")
    assert.same({ GC.Theme.FONT_HEAD, 10 }, { W.state(rounded.text).font[1], W.state(rounded.text).font[2] })
    assert.same({ GC.Theme.FONT_HEAD, 12 }, { W.state(square.text).font[1], W.state(square.text).font[2] })
  end)

  it("draws a trailing ▼ as the atlas caret and keeps the label as given", function()
    local b = button("ghost", "plaque")
    b:SetLabel("SHOW DETAILS ▼")
    assert.equal("SHOW DETAILS ▼", b.label)
    assert.equal("SHOW DETAILS", W.state(b.text).text)
    assert.same({ GC.Theme.IconCoords("caretDown") }, W.state(b.caret).texCoord)
    assert.is_true(W.state(b.caret).shown)
  end)

  it("takes the caret away again for a label without one, as a pooled row is rebound", function()
    local b = button("ghost", "plaque")
    b:SetLabel("All ▼")
    b:SetLabel("Post")
    assert.is_false(W.state(b.caret).shown)
    assert.equal("Post", W.state(b.text).text)
  end)

  it("glows only while primary and enabled", function()
    local b = button("primary", "plaque")
    assert.is_true(W.state(b.glow).shown)
    b:Disable()
    assert.is_false(W.state(b.glow).shown)
    b:Enable()
    assert.is_true(W.state(b.glow).shown)
    b:SetVariant("ghost")
    assert.is_false(W.state(b.glow).shown)
  end)

  it("builds no glow for a button that is never primary", function()
    assert.is_nil(button("ghost", "badge").glow)
  end)

  it("draws a middle dot and an arrow in a label as written: the Fira faces have them", function()
    local b = button("primary", "plaque")
    b:SetLabel("AUTO · SCANNING → 12g")
    assert.equal("AUTO · SCANNING → 12g", W.state(b.text).text)
  end)

  it("still respells a Label that keeps the client's own face", function()
    local saved = _G.GetLocale
    _G.GetLocale = function() return "koKR" end
    GC.Theme.RefreshFonts("enUS") -- Latin addon on a Korean client: FONT_LABEL nil, face inherited
    local label = GC.Theme.Label(W.CreateFrame("Frame"), 11)
    label:SetText("a · b")
    _G.GetLocale = saved
    assert.is_nil(GC.Theme.FONT_LABEL)
    assert.equal("a, b", W.state(label).text)
  end)

  it("puts the primary button's glow under every fill", function()
    local b = button("primary", "plaque")
    local s = W.state(b.glow)
    assert.equal("BACKGROUND", s.layer)
    assert.equal(-7, s.sublevel)
  end)

  describe("disabled look", function()
    it("dims a rounded ghost's fill by tint and never above its enabled alpha", function()
      local b = button("ghost", "plaque")
      local on = W.state(b.bg).vertex[4]
      b:Disable()
      local off = W.state(b.bg).vertex[4]
      assert.is_true(off < on)
      assert.is_nil(W.state(b.bg).alpha)
      b:Enable()
      assert.equal(on, W.state(b.bg).vertex[4])
      assert.is_nil(W.state(b.bg).alpha)
    end)

    it("dims a primary's fill to 0.45 and a square one too", function()
      local b = button("primary", "plaque")
      b:Disable()
      assert.is_true(math.abs(W.state(b.bg).vertex[4] - 0.45) < 1e-9)
      local sq = button("primary")
      sq:Disable()
      assert.is_true(math.abs(W.state(sq.bg).color[4] - 0.45) < 1e-9)
      sq:Enable()
      assert.equal(1, W.state(sq.bg).color[4])
    end)

    it("keeps a fill dimmed when the variant changes while disabled", function()
      local b = button("ghost", "plaque")
      b:Disable()
      b:SetVariant("active")
      assert.is_true(W.state(b.bg).vertex[4] < 0.14)
    end)
  end)

  describe("SetBusy with a caret", function()
    local function rightInset(b)
      local last
      for _, p in ipairs(W.state(b.text).points) do
        if p[1] == "RIGHT" then last = p end
      end
      return last and last[4]
    end

    it("keeps the caret's room on the right and lets the spinner take the left", function()
      local b = button("ghost", "plaque")
      b:SetLabel("All ▼")
      assert.equal(-16, rightInset(b))
      b:SetBusy(true)
      assert.equal(-16, rightInset(b))
      local left
      for _, p in ipairs(W.state(b.text).points) do
        if p[1] == "LEFT" then left = p end
      end
      assert.equal(b.spinner, left[2])
      b:SetBusy(false)
      assert.equal(-16, rightInset(b))
    end)
  end)

  it("closes the title bar with the atlas cross, not a letter", function()
    local bar = GC.Theme.TitleBar(W.CreateFrame("Frame"), "GoldCap")
    assert.same({ GC.Theme.IconCoords("close") }, W.state(bar.close.icon).texCoord)
    assert.is_nil(bar.close.label)
    assert.equal(GC.Theme.FONT_HEAD, W.state(bar.title).font[1])
  end)
end)
