local helper = require("spec.spec_helper")

describe("locale layer", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Locale/Core.lua", GC)
  end)

  it("returns the key itself when nothing is translated", function()
    assert.equal("Post", GC.L["Post"])
    assert.equal("No deals yet.", GC.L["No deals yet."])
  end)

  it("returns the active language's string once activated", function()
    GC.Locales.deDE = { ["Post"] = "Einstellen" }
    GC.ActivateLocale("deDE")
    assert.equal("Einstellen", GC.L["Post"])
    assert.equal("Cancel", GC.L["Cancel"]) -- untranslated key still degrades to English
  end)

  it("falls back to English for an unknown code", function()
    GC.Locales.deDE = { ["Post"] = "Einstellen" }
    GC.ActivateLocale("deDE")
    GC.ActivateLocale("xxXX")
    assert.equal("Post", GC.L["Post"])
  end)

  it("refuses writes so a string can never be set at runtime", function()
    assert.has_error(function() GC.L["Post"] = "nope" end)
  end)

  it("applies the saved setting over the client locale", function()
    _G.GetLocale = function() return "deDE" end
    GC.Locales.deDE = { ["Post"] = "Einstellen" }
    GC.Locales.ukUA = { ["Post"] = "Виставити" }
    GC.db = { settings = { locale = "auto" } }
    GC.ApplyLocale()
    assert.equal("Einstellen", GC.L["Post"])
    GC.db.settings.locale = "ukUA"
    GC.ApplyLocale()
    assert.equal("Виставити", GC.L["Post"])
    _G.GetLocale = nil
  end)

  it("offers every language as a choice, in its own language, auto first", function()
    local choices = GC.LOCALE_CHOICES
    assert.equal("auto", choices[1].code)
    local seen = {}
    for _, choice in ipairs(choices) do
      assert.is_string(choice.label)
      assert.is_nil(seen[choice.code], "duplicate choice " .. tostring(choice.code))
      seen[choice.code] = true
    end
    -- Ukrainian is the reason this picker exists: GetLocale() never returns it.
    assert.is_true(seen.ukUA)
    assert.is_true(seen.koKR)
    assert.equal(13, #choices) -- auto + 11 client locales + ukUA
  end)

  it("resolves the client locale on auto and the chosen one otherwise", function()
    assert.equal("deDE", GC.ResolveLocale("auto", "deDE"))
    assert.equal("enUS", GC.ResolveLocale("auto", nil))
    assert.equal("ukUA", GC.ResolveLocale("ukUA", "deDE"))
    -- enGB never reaches us (the client reports enUS), but a stray value must not blank out.
    assert.equal("enUS", GC.ResolveLocale("auto", "enGB"))
    assert.equal("enUS", GC.ResolveLocale("auto", "xxXX"))
  end)
end)
