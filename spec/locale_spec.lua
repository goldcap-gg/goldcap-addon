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

  -- The Sell tab speaks to a French player as tu, as THE BOOK settled: one line of the dock said
  -- "attends une minute" and the next "réessayez" (final review M8).
  it("keeps the French Sell tab's post lines in one register", function()
    local fr = helper.loadModule("Locale/Core.lua")
    helper.loadModule("Locale/frFR.lua", fr)
    local translations = fr.Locales.frFR
    for _, key in ipairs({ "The auction house did not answer -- try again",
        "Last post may still go up -- wait a minute", "No answer yet -- listening for a minute",
        "%d ahead of you", "Click Confirm to post" }) do
      local text = assert(translations[key], "frFR is missing " .. key)
      assert.is_nil(text:find("vous", 1, true), text)
      assert.is_nil(text:find("ez%f[%A]"), text)
    end
  end)

  -- ...and every French string the Sell tab shows, not only the new ones: its older lines said
  -- vous ("Terminez", "cliquez", "vos sacs") beside THE BOOK's tu (final review M8).
  it("speaks tu in every French string the Sell tab shows", function()
    local fr = helper.loadModule("Locale/Core.lua")
    helper.loadModule("Locale/frFR.lua", fr)
    local translations = fr.Locales.frFR
    local keys = {}
    for _, path in ipairs({ "GoldCap/UI/SellFrame.lua", "GoldCap/UI/SellViewModel.lua", "GoldCap/Core/SellPositions.lua",
        "GoldCap/Core/PostQueue.lua", "GoldCap/Core/CancelQueue.lua" }) do
      local file = assert(io.open(path, "r"))
      local source = file:read("*a")
      file:close()
      for key in source:gmatch('GC%.L%["(.-)"%]') do keys[key] = true end
      -- The queue's reasons, looked up by value (UI/SellFrame.lua's reason table).
      for key in source:gmatch('= "([^"\n]-)",\n') do keys[key] = true end
    end
    local checked = 0
    for key in pairs(keys) do
      local text = translations[key]
      if text then
        checked = checked + 1
        for _, word in ipairs({ "%f[%w]vous%f[%W]", "%f[%w]votre%f[%W]", "%f[%w]vos%f[%W]", "%f[%w]%a+ez%f[%W]" }) do
          assert.is_nil(text:find(word), ("frFR %q: %q"):format(key, text))
        end
      end
    end
    assert.is_true(checked > 100)
  end)

  -- The tooltip's live line (UI/Tooltip.lua): "En la casa de subastas ahora" ran 15-20 glyphs wider
  -- than any other GoldCap line, and a label with its own "now" said it twice beside "ahora mismo".
  -- The detail already says when (final review M2).
  it("keeps the live line's label short in Spanish, Portuguese and German, with no 'now' of its own", function()
    -- German said "gerade" twice in the just-now case: "Gerade im AH: … · gerade eben".
    local expected = { esES = "En subasta", esMX = "En subasta", ptBR = "No leilão", deDE = "Im AH" }
    for code, label in pairs(expected) do
      local loc = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", loc)
      assert.equal(label, loc.Locales[code]["On the AH now"], code)
    end
  end)

  -- /goldcap status's two "sync again" reasons (UI/ImportDialog.lua): the addon reads the Companion's
  -- file only at load, so the line does not change after a sync until the player reloads -- in every
  -- language, or the player concludes the Companion is broken (final re-review N1).
  it("tells a player whose Companion must sync again to /reload after it, in every language", function()
    for _, code in ipairs(helper.localeCodes()) do
      local loc = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", loc)
      for _, key in ipairs({ "the Companion wrote an empty copy -- let it sync, then /reload",
          "the Companion wrote it with no prices -- let it sync, then /reload" }) do
        local text = assert(loc.Locales[code][key], code .. " is missing " .. key)
        assert.is_truthy(text:find("/reload", 1, true), code .. ": " .. text)
      end
    end
  end)

  -- The check pane's "Confidence" was renamed to what it measures (Core/CheckVerdict.lua's
  -- FACT_LABEL.confidence). Every language says it in its own words, and none keeps the old key
  -- behind: a stale translation of a word nothing asks for any more is a trap for the next edit.
  it("names the sales evidence fact and its readings in every language, and drops the old words", function()
    for _, code in ipairs(helper.localeCodes()) do
      local loc = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", loc)
      for _, key in ipairs({ "Sales evidence", "weak", "fair", "strong" }) do
        assert.is_string(loc.Locales[code][key], code .. " is missing " .. key)
      end
      for _, key in ipairs({ "Confidence", "Sales certainty", "low", "high" }) do
        assert.is_nil(loc.Locales[code][key], code .. " still carries " .. key)
      end
    end
  end)

  -- The scan's hidden count takes rows under the player's Min profit per buy as well as the ones
  -- that are hard to resell (Core/FullScan.lua), and both of its sentences say so in every
  -- language; the old keys, which named only the second reason, are gone.
  it("says what the scan's hidden count counts, in every language", function()
    for _, code in ipairs(helper.localeCodes()) do
      local loc = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", loc)
      for _, key in ipairs({ ", %d hidden: hard to resell or under your min profit",
          "%d filtered out: hard to resell, or under your Min profit per buy" }) do
        assert.is_string(loc.Locales[code][key], code .. " is missing " .. key)
      end
      assert.is_nil(loc.Locales[code][", %d hidden as unsellable"], code .. " keeps the old status key")
      assert.is_nil(loc.Locales[code]["%d filtered out as hard to resell"], code .. " keeps the old empty-state key")
    end
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
