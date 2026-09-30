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

  -- The needs-gold cell names gold the character must HOLD, not a price being asked: es, mx and pt
  -- say "exige", not the "pide"/"pede" a seller's asking price takes.
  it("words the needs-gold cell as gold to hold in Spanish and Portuguese", function()
    local expected = { esES = "exige %s", esMX = "exige %s", ptBR = "exige %s" }
    for code, label in pairs(expected) do
      local loc = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", loc)
      assert.equal(label, loc.Locales[code]["needs %s"], code)
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

  -- Owner rule: i18n in all twelve. The contract spec lets a key fall back to English; these may
  -- not. The 3b follow-up key and every key plan 3c added.
  it("carries the Forever keys in all twelve languages", function()
    local keys = {
      "Queue ready — press POST again to post it",
      "What this buy would make is under your minimum profit.",
      "Below vendor", "Under market",
      " · buy at %s or less, vendor pays %s", " · buy at %s or less, AH value %s",
      "Buy at or under %s: a vendor pays %s each. This buy makes %s.",
      "Buy at or under %s: the AH value, what the cheapest tenth of the units listed ask, is %s. Resale speed is unknown, so this is riskier than a vendor deal. This buy makes about %s after the 5%% cut and the deposit.",
      "No deals in your last scan.",
      "GoldCap looks for items listed cheaper than they are worth. SCAN looks again.",
      "No scan of this auction house yet.",
      "GoldCap scans when you open the auction house; SCAN on this board scans again.",
      "under the vendor price -- click Buy to purchase",
      "far under the market, resale speed unknown -- click Buy to purchase",
      "AH value",
      "no live price", "NO LIVE PRICE YET", "Checking prices — waiting for the Auction House…",
      "last live price %s ago",
      "Press Buy again to buy this quantity",
      "%ds", "%dm", "%dh", "%dd",
      -- Final review m5: four of 3c's keys the list had missed.
      "This lot holds more units than your Max units per buy.",
      "sure profit: a vendor pays %s each",
      "resale at your scan's AH value, %s each, after the 5%% cut and deposit; speed unknown",
      "Checked against the live auction house a moment ago.",
      -- Task S: the settings panel's own Forever min-profit row and its vendor-wallet note.
      "Min profit per buy (copper)",
      "While this stays at the default 5%, a vendor-priced lead may spend up to half your wallet instead.",
    }
    for _, code in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU",
        "ukUA", "zhCN", "zhTW" }) do
      local f = assert(io.open("GoldCap/Locale/" .. code .. ".lua"))
      local text = f:read("*a")
      f:close()
      for _, key in ipairs(keys) do
        assert.is_truthy(text:find('["' .. key .. '"]', 1, true), code .. " lacks: " .. key)
      end
    end
  end)

  -- Plan 3e (Road to 40, AH Upgrade Finder, loot recorder): every key it added, in every file.
  it("carries the plan 3e keys in all twelve languages", function()
    local keys = {
      "ROAD TO 40",
      "Road to 40: %s of %s (gold %s, bags %s).",
      "Road to 40: you have %s (gold %s, bags %s).",
      "Blizzard has not published the riding cost yet. Type /gc mount and the cost you expect.",
      "At your pace you reach it at level %d.",
      "At your pace you will be %s short at level 40.",
      "You can pay for it now.",
      "Play a little longer for an estimate of your pace.",
      "Your gold has not grown lately, so there is no pace to estimate.",
      "Items in your bags that fetch more on the auction house than at a vendor: %d (%s more).",
      "Mount cost set to %s.",
      "Mount cost cleared.",
      "Could not read that amount. Type it like 12g 50s.",
      "Road to 40 with GoldCap: %s of %s for my mount (%d%%).",
      "Gear upgrades on the auction house",
      "From your scan %s ago. Counts only %s. Change with /gc weights.",
      "No scan with gear in it yet. Open the auction house and let GoldCap scan it.",
      "Nothing on the auction house beats what you wear at your level.",
      "at level %d",
      "Items still loading: %d. Open this again in a moment.",
      "This client does not report item stats, so GoldCap cannot compare gear.",
      "No stat weights for your class yet. Set them like this: /gc weights STR 1 STA 0.5",
      "Upgrades for your gear on the auction house: %d. Type /gc upgrades to see them.",
      "Stat weights: %s",
      "Unknown stat %s. Use one of: %s",
      "GoldCap now counts what drops from what you loot, with no names, for drop rates on goldcap.gg. The Companion shares it once that part is released. Type /gc loot off to stop.",
      "Loot counting is on.",
      -- Final review fix dispatch, M7: the off message also points at the new /gc loot clear.
      "Loot counting is off. Type /gc loot clear to remove what was recorded.",
      "Loot record cleared.",
    }
    for _, code in ipairs({ "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU",
        "ukUA", "zhCN", "zhTW" }) do
      local f = assert(io.open("GoldCap/Locale/" .. code .. ".lua"))
      local text = f:read("*a")
      f:close()
      for _, key in ipairs(keys) do
        assert.is_truthy(text:find('["' .. key .. '"]', 1, true), code .. " lacks: " .. key)
      end
    end
  end)

  -- BUY 2.0 (week 1): every string the BUY tab and its cap box can show, in all twelve. Read off
  -- the two files' own source -- their GC.L["..."] literals and their @localised-keys tables -- so
  -- a string added to the tab later is held to the same rule without anybody listing it here. The
  -- tab was English in every language before BUY 2.0; the owner plays in Russian.
  it("carries every BUY tab key in all twelve languages", function()
    local asked = {}
    for _, path in ipairs({ "GoldCap/UI/BuyFrame.lua", "GoldCap/UI/BuyCapEditor.lua" }) do
      local f = assert(io.open(path))
      local text = f:read("*a")
      f:close()
      for body in text:gmatch("@localised%-keys.-\n(.-)\n}") do
        for literal in body:gmatch('"(.-)"') do asked[literal] = true end
      end
      for raw in text:gmatch('GC%.L%["(.-)"%]') do asked[(raw:gsub('\\"', '"'))] = true end
    end
    local count = 0
    for _ in pairs(asked) do count = count + 1 end
    assert.is_true(count > 100)
    for _, code in ipairs(helper.localeCodes()) do
      local loc = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", loc)
      for key in pairs(asked) do
        assert.is_truthy(loc.Locales[code][key], code .. " lacks: " .. key)
      end
    end
  end)

  -- ...and the week 1 keys by name, so a key renamed in the source cannot quietly drop out of the
  -- rule above along with its translations.
  it("carries the BUY 2.0 week 1 keys in all twelve languages", function()
    local keys = {
      "▲%d%% over your cap",
      "Blizzard's price: %s · %d s left", "Blizzard's price: %s", "%s · %s under market",
      "%s · at market price", "%d of %d at or under your cap", "Everything here is bought",
      "The rest is skipped for now", "still on the list: %d at a vendor · %d to craft",
      "skipped for this session, it stays on the list", "a vendor sells it for %s each",
      "a vendor sells it for %s each · the auction house asks %s", "a vendor sells it",
      "craft it for %s each", "craft it for %s each · %s here", "craft it yourself",
      "already in your bags and bank", "the cheapest is %s, your cap is %s",
      "nothing at or under your cap of %s", "RAISE CAP TO %s", "Skip",
      "PRICE EACH", "over your cap · %s", "at a vendor · %s each", "at a vendor", "craft it · %s each",
      "bought", "skipped for now", "buy by hand",
      "TO BUY HERE", "%d of %d done",
      "buy %d of %d", "buy %d of %d, have %d in bags and bank", "%d at %s", "you take %d",
      "over your cap", "seen %s ago", "cheapest seen %s", "Market", "%s each", "Your cap",
      "Alert target", "right-click to skip or change the cap",
      "Skip for now", "Don't skip", "Raise cap to %s", "Change the cap…", "Use the default cap",
      "Cap for %s", "Set cap",
      "All", "To buy", "Over cap", "At a vendor", "To craft", "Bought", "Skipped",
      "Nothing on this list matches.",
      "YOUR LISTS", "Lists come from goldcap.gg through the companion.", "%d of %d", "%d hits",
      "BUY %d", "buying...", "confirming...",
    }
    for _, code in ipairs(helper.localeCodes()) do
      local f = assert(io.open("GoldCap/Locale/" .. code .. ".lua"))
      local text = f:read("*a")
      f:close()
      for _, key in ipairs(keys) do
        assert.is_truthy(text:find('["' .. key .. '"]', 1, true), code .. " lacks: " .. key)
      end
    end
  end)

  -- The owner plays in Russian: the words the dock and the rows say most, pinned as they read.
  it("says the BUY dock's words naturally in Russian and Ukrainian", function()
    local expected = {
      ruRU = { ["BUY %d"] = "КУПИТЬ %d", ["RAISE CAP TO %s"] = "ПОДНЯТЬ ДО %s", ["Skip"] = "Пропустить",
               ["Your cap"] = "Ваш потолок", ["TO BUY HERE"] = "К ПОКУПКЕ ЗДЕСЬ" },
      ukUA = { ["BUY %d"] = "КУПИТИ %d", ["RAISE CAP TO %s"] = "ПІДНЯТИ ДО %s", ["Skip"] = "Пропустити",
               ["Your cap"] = "Ваша стеля", ["TO BUY HERE"] = "ДО КУПІВЛІ ТУТ" },
    }
    for code, strings in pairs(expected) do
      local loc = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", loc)
      for key, text in pairs(strings) do assert.equal(text, loc.Locales[code][key], code .. " " .. key) end
    end
  end)
end)
