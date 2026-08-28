local helper = require("spec.spec_helper")

-- Measured from the shipped font's cmap on 2026-08-27, not assumed: JetBrains Mono covers
-- Latin, Greek and the whole Cyrillic range (including і, ї, ґ) and NO CJK. So Russian and
-- Ukrainian draw in our own kit, while Korean and both Chinese locales would render empty
-- boxes anywhere we set that face -- they draw in one of Blizzard's own faces for the script
-- instead (see the CJK faces block at the bottom of this file).
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

    -- One script, one face: FONT_UI's own CJK rule picks it (see the CJK faces block below),
    -- and Label follows rather than making a second guess at the same question.
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

  -- Blizzard's locale faces live in the CLIENT's own data, not in the locale install. Probed
  -- in-game on an enUS-only install 2026-08-28: ARKai_T, ARHei, 2002, 2002B and bKAI00M all
  -- load; bLEI00D, bHEI01B, bHEI00M and ARKai_C do not. Reading the client's own face instead
  -- (GameFontNormal) hands back Fonts\FRIZQT__.TTF on that install, which has no CJK at all --
  -- which is why every label in the addon drew empty boxes while the language picker beside
  -- them drew 한국어 and 简体中文 perfectly, and the "your client has no font for this
  -- language" warning printed in flawless Korean.
  --
  -- Probed rather than assumed: a client missing one of these has to fall through to the next,
  -- and a client missing all of them has to keep the old answer rather than blank the kit.
  describe("CJK faces", function()
    local function clientHas(...)
      local available = {}
      for _, file in ipairs({ ... }) do available["Fonts\\" .. file] = true end
      _G.UIParent = {
        CreateFontString = function()
          return { SetFont = function(_, path) return available[path] == true end }
        end,
      }
    end

    before_each(function()
      _G.GetLocale = function() return "enUS" end
      _G.GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
    end)

    after_each(function()
      _G.UIParent = nil
      _G.GetLocale = nil
    end)

    it("draws simplified Chinese in the client's own Chinese face, not its latin one", function()
      clientHas("ARKai_T.ttf", "ARHei.ttf")
      GC.Theme.RefreshFonts("zhCN")
      assert.equal("Fonts\\ARKai_T.ttf", GC.Theme.FONT_UI)
      assert.equal("Fonts\\ARHei.ttf", GC.Theme.FONT_UI_BOLD)
      assert.equal(GC.Theme.FONT_UI, GC.Theme.FONT_LABEL)
    end)

    it("draws Korean in 2002, and its bold weight in 2002B", function()
      clientHas("2002.TTF", "2002B.TTF")
      GC.Theme.RefreshFonts("koKR")
      assert.equal("Fonts\\2002.TTF", GC.Theme.FONT_UI)
      assert.equal("Fonts\\2002B.TTF", GC.Theme.FONT_UI_BOLD)
    end)

    -- Traditional Chinese asks for bLEI00D first; that one is absent on the install this was
    -- found on, so it falls through to the next face of its OWN script rather than straight to
    -- the simplified one.
    it("falls through to the next face of the same script", function()
      clientHas("bKAI00M.ttf", "ARKai_T.ttf")
      GC.Theme.RefreshFonts("zhTW")
      assert.equal("Fonts\\bKAI00M.ttf", GC.Theme.FONT_UI)
    end)

    it("keeps the client's own face when it has no face for that script at all", function()
      clientHas()
      GC.Theme.RefreshFonts("koKR")
      assert.equal("Fonts\\FRIZQT__.TTF", GC.Theme.FONT_UI)
    end)

    -- The picker's warning is derived from the same probe, so it can no longer claim a client
    -- cannot draw a language while the menu item under the cursor is drawing it.
    it("only warns about a language nothing in the client can draw", function()
      clientHas("2002.TTF")
      assert.is_true(GC.Theme.LocaleIsDrawable("koKR"))
      assert.is_false(GC.Theme.LocaleIsDrawable("zhCN"))
    end)
  end)

  -- Faces change under a LIVE interface -- picking a language the current face cannot draw is
  -- the entire point of the picker. A FontString that remembered the FILE it was built with
  -- stayed on it, and that is how the Settings language button came out as "\226\153\166\226\153\166\226\153\166" the
  -- instant Korean was picked: the new label was Hangul, the button's own FontString was still
  -- on the bundled latin mono. Every registered widget remembers its ROLE instead, so the face
  -- follows the language in place. (The TEXT still needs the /reload the picker asks for --
  -- labels are written when a widget is built. Only the face moves here.)
  describe("re-fonting a live interface", function()
    local function stubFontString()
      local fs = {}
      function fs:SetFont(path, size, flags) self.font = { path, size, flags } end
      function fs:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
      function fs:SetJustifyH() end
      function fs:SetText() end
      function fs:SetTextColor() end
      return fs
    end
    local parent = { CreateFontString = function() return stubFontString() end }

    before_each(function()
      _G.GetLocale = function() return "enUS" end
      _G.GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
      _G.UIParent = {
        CreateFontString = function()
          return { SetFont = function(_, path) return path == "Fonts\\2002.TTF" end }
        end,
      }
    end)

    after_each(function()
      _G.UIParent = nil
      _G.GetLocale = nil
    end)

    -- The text on screen is still written in the language it was built in. Moving all of it
    -- onto the new script's face is worse than leaving it: Ukrainian redrawn in Fonts\\2002.TTF
    -- came back as "м□н□мальна" -- that face has Cyrillic but no і, є or ї.
    it("leaves text already on screen in the face that draws it", function()
      GC.Theme.RefreshFonts("ukUA")
      local num = GC.Theme.Num(parent, 12)
      GC.Theme.RefreshFonts("koKR")
      assert.matches("JetBrainsMono", num.font[1])
    end)

    -- The one widget whose text IS rewritten in the new language the moment it is picked.
    it("moves a single named widget when its own text changes language", function()
      GC.Theme.RefreshFonts("ukUA")
      local num = GC.Theme.Num(parent, 12)
      GC.Theme.RefreshFonts("koKR")
      GC.Theme.RefontWidget(num)
      assert.equal("Fonts\\2002.TTF", num.font[1])
    end)

    it("keeps a re-fonted widget on its new face across a rescale", function()
      GC.Theme.RefreshFonts("ukUA")
      local num = GC.Theme.Num(parent, 10)
      GC.Theme.RefreshFonts("koKR")
      GC.Theme.RefontWidget(num)
      GC.Theme.SetScale(1.2)
      assert.equal("Fonts\\2002.TTF", num.font[1])
      assert.equal(12, num.font[2])
      GC.Theme.SetScale(1.0)
    end)

    it("ignores a widget it never registered", function()
      assert.has_no.errors(function() GC.Theme.RefontWidget(stubFontString()) end)
      assert.has_no.errors(function() GC.Theme.RefontWidget(nil) end)
    end)

    -- A Label inherits the client's face and its FLAGS from GameFontHighlightSmall. Re-fonting
    -- used to drop the flags (it passed ""), which quietly took the outline off every label the
    -- first time the font-scale slider moved.
    it("keeps a label's inherited flags when it re-fonts", function()
      GC.Theme.RefreshFonts("enUS")
      local label = GC.Theme.Label(parent, 11)
      GC.Theme.SetScale(1.1)
      assert.equal("OUTLINE", label.font[3])
      GC.Theme.SetScale(1.0)
    end)
  end)
end)
