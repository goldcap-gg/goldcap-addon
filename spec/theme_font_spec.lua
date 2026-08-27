local helper = require("spec.spec_helper")

-- Measured from the shipped font's cmap on 2026-08-27, not assumed: JetBrains Mono covers
-- Latin, Greek and the whole Cyrillic range (including і, ї, ґ) and NO CJK. So Russian and
-- Ukrainian draw in our own kit, while Korean and both Chinese locales would render empty
-- boxes anywhere we set that face.
describe("Theme fonts per locale", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("UI/Theme.lua", GC)
    _G.GameFontNormal = { GetFont = function() return "Fonts\\ARKai_T.ttf", 12, "" end }
  end)

  after_each(function()
    _G.GameFontNormal = nil
  end)

  it("keeps the bundled mono face for latin and cyrillic", function()
    for _, code in ipairs({ "enUS", "deDE", "ruRU", "ukUA" }) do
      GC.Theme.RefreshFonts(code)
      assert.matches("JetBrainsMono", GC.Theme.FONT_UI)
    end
  end)

  it("uses the client's own face for CJK, which the bundled font cannot draw", function()
    for _, code in ipairs({ "koKR", "zhCN", "zhTW" }) do
      GC.Theme.RefreshFonts(code)
      assert.equal("Fonts\\ARKai_T.ttf", GC.Theme.FONT_UI)
    end
  end)

  -- T.Num draws column headers and band labels as well as figures, so it follows FONT_UI: on
  -- CJK the digits stop being monospaced (columns then align by their RIGHT anchor), which is
  -- the deliberate trade against headers rendering as empty boxes.
  it("keeps the bundled face available for the brand mark", function()
    GC.Theme.RefreshFonts("koKR")
    assert.matches("JetBrainsMono", GC.Theme.FONT_MONO)
    assert.is_not.equal(GC.Theme.FONT_MONO, GC.Theme.FONT_UI)
  end)

  it("falls back to the bundled face when the client font is unreadable", function()
    _G.GameFontNormal = nil
    GC.Theme.RefreshFonts("koKR")
    assert.matches("JetBrainsMono", GC.Theme.FONT_UI)
  end)
end)
