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

  -- T.Label inherits GameFontHighlightSmall, i.e. the CLIENT's own face, on the assumption
  -- that a client can draw whatever language is on screen. That holds only while the addon
  -- speaks the client's language -- and the whole point of the picker is that it need not.
  -- An English client cannot draw Cyrillic, so picking Russian turned every Label in the
  -- addon into empty boxes (reported in-game 2026-08-28) while the mono-faced numbers and
  -- headers beside them read perfectly.
  --
  -- FONT_LABEL is nil for "keep the inherited face" and a path for "override it".
  describe("label face", function()
    it("keeps the client's own face when the client speaks that language", function()
      _G.GetLocale = function() return "ruRU" end
      GC.Theme.RefreshFonts("ruRU")
      assert.is_nil(GC.Theme.FONT_LABEL)
    end)

    it("keeps the client's own face for latin, which every client face draws", function()
      _G.GetLocale = function() return "ruRU" end
      GC.Theme.RefreshFonts("deDE")
      assert.is_nil(GC.Theme.FONT_LABEL)
    end)

    it("overrides with the bundled face for cyrillic on a client that cannot draw it", function()
      _G.GetLocale = function() return "enUS" end
      for _, code in ipairs({ "ruRU", "ukUA" }) do
        GC.Theme.RefreshFonts(code)
        assert.matches("JetBrainsMono", GC.Theme.FONT_LABEL)
      end
    end)

    -- Nothing in the install can draw Hangul on an English client, so there is no face to
    -- switch to. FONT_UI's own CJK rule already reaches for the client face; Label follows
    -- it rather than inventing a second answer, and the picker is what has to warn.
    it("follows FONT_UI on CJK, where no bundled face can help", function()
      _G.GetLocale = function() return "enUS" end
      GC.Theme.RefreshFonts("koKR")
      assert.equal(GC.Theme.FONT_UI, GC.Theme.FONT_LABEL)
    end)

    it("survives a client that will not name its locale", function()
      _G.GetLocale = nil
      GC.Theme.RefreshFonts("ruRU")
      assert.matches("JetBrainsMono", GC.Theme.FONT_LABEL)
    end)
  end)
end)
