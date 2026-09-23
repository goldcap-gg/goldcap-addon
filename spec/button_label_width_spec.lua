local helper = require("spec.spec_helper")

-- The Sell tab's action column is 86px wide and its button is sized to the pixel: UI/SellFrame
-- comments the choice as "the largest width that still leaves >=2px clearance" for
-- "Cancel lot?" at 85.8px, using this project's own measured figure of ~7.8px per character
-- (mono-10 at Theme.Scale() 1.3). Eleven characters is therefore the whole budget.
--
-- Nothing checked that. English is the only language whose action labels were ever short
-- enough, so eight locales shipped labels that drew straight across the price columns to the
-- left of the button -- "Set cost" as "Задати собівартість" is 19 characters, more than half
-- as wide again as the button holding it. Theme.Button now bounds its FontString to the
-- button's own edges (spec/theme_button_contract_spec.lua), so the damage is contained to a
-- clipped label; this spec is the other half, keeping the label short enough not to clip.
--
-- Deliberately a CHARACTER budget rather than a pixel one: no font metrics are available off
-- the client, and a count that is right to within a character is worth more here than a width
-- computed from a made-up per-glyph table. CJK counts by codepoint, where one glyph is roughly
-- two Latin ones -- hence its own, halved budget.
describe("row button labels fit the button", function()
  -- Two fixed-width row buttons, each with the set of labels its own code can put on it, and
  -- each budget derived the same way: width divided by ~7.8px per character.
  --   row.action:SetSize(86, 18)          -- UI/SellFrame.lua, showRowAction
  --   COLUMNS { key = "buy", w = 64 }     -- UI/SniperFrame.lua, setRowDeal
  --
  -- A button that is posting shares its width with the client's spinner (Theme.Button's
  -- SetBusy: a 12px ring 2px in from the edge, the label 1px after it), so its label has 15px
  -- less to live in:
  --   row.action (86px)                    -- the row's Post while its post is out
  --   queueButton:SetSize(136, 26)         -- the dock's POST while a post is out
  local BUTTONS = {
    { what = "the 86px Sell action button", budget = 11,
      keys = { "Set cost", "Post", "Cancel lot", "Cancel lot?", "Remove", "Remove?" } },
    { what = "the 64px Deals buy button", budget = 8,
      keys = { "Buy", "Check", "Avoid" } },
    -- UI/BuyFrame.lua: row.action:SetSize(72, 18). Measured at the DEFAULT scale (1.0, 6.0px per
    -- character), not at 1.3 like the two above: at 1.3 the 72px badge holds 9, and the German and
    -- Russian/Ukrainian "CONFIRM" (10 and 11) clip there already -- that is recorded, not fixed
    -- here. 11, not the 12 that fill it exactly: the Sell precedent's >=2px of clearance (66px of
    -- 72). What this pins is the label a player sees at the default scale: the countdown lives in
    -- the line's name cell, because "CONFIRM (9)" did not fit (fix round 5).
    { what = "the 72px BUY action button", budget = 11,
      keys = { "CONFIRM", "waiting..." } },
    { what = "the 86px Sell action button beside its spinner", budget = 9,
      keys = { "Posting…" } },
    { what = "the 136px dock POST button beside its spinner", budget = 15,
      keys = { "POSTING…" } },
  }

  -- Codepoints, not bytes: string.len on UTF-8 counts bytes, so "Витрати" would score 14 and
  -- every Cyrillic locale would fail on encoding alone. Full-width CJK/Hangul counts double,
  -- because one of those glyphs is about two Latin characters wide.
  local function displayWidth(text)
    local width, i = 0, 1
    while i <= #text do
      local byte = text:byte(i)
      local size = (byte < 0x80 and 1) or (byte < 0xE0 and 2) or (byte < 0xF0 and 3) or 4
      local code = byte
      if size == 2 then code = (byte - 0xC0) * 64 + (text:byte(i + 1) - 0x80)
      elseif size == 3 then
        code = (byte - 0xE0) * 4096 + (text:byte(i + 1) - 0x80) * 64 + (text:byte(i + 2) - 0x80)
      end
      local wide = (code >= 0x1100 and code <= 0x11FF) or (code >= 0x2E80 and code <= 0x9FFF)
        or (code >= 0xAC00 and code <= 0xD7AF) or (code >= 0xFF00 and code <= 0xFF60)
      width = width + (wide and 2 or 1)
      i = i + size
    end
    return width
  end

  for _, code in ipairs(helper.localeCodes()) do
    it(("keeps every %s row-button label inside its button"):format(code), function()
      local GC = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", GC)
      -- The locale TABLE, not GC.L: GC.L's metatable falls back to the key, so reading a
      -- translation through it silently measures the English string for every language that
      -- happens to be missing the key -- which is how the first draft of this spec passed
      -- against all twelve locales while measuring nothing.
      local translations = GC.Locales[code]
      assert.is_truthy(translations, code .. " registered no locale table")
      for _, button in ipairs(BUTTONS) do
        local seen = 0
        for _, key in ipairs(button.keys) do
          local label = translations[key]
          if label then
            seen = seen + 1
            assert.is_true(displayWidth(label) <= button.budget,
              ("%s: %q is %d wide, over the %d %s holds"):format(
                code, label, displayWidth(label), button.budget, button.what))
          end
        end
        -- Every locale carries every one of these; a locale that suddenly measures none has
        -- been renamed or gutted, and a spec that quietly checks nothing is worse than none.
        assert.equal(#button.keys, seen, code .. " is missing labels for " .. button.what)
      end
    end)
  end

  -- THE BOOK's marker note runs from the bar's start to the count's right edge: ~210px at mono-10,
  -- 7.8px a character at Theme.Scale() 1.3 -- 26 characters, the number included. The words
  -- "your price · … units ahead of you" were 36 in English and cut the NUMBER in Russian and
  -- Ukrainian (review M1). Measured formatted, with a four-character count. The gap line is
  -- drawn in the same place: "1.1k Stück auf 93 Preise verteilt" ran 33 (final review M3).
  for _, code in ipairs(helper.localeCodes()) do
    it(("keeps every %s marker note inside THE BOOK's line, the number first"):format(code), function()
      local GC = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", GC)
      local translations = GC.Locales[code]
      for _, key in ipairs({ "%s ahead", "%s+ ahead", "first in line", "%s units in %d prices" }) do
        local label = translations[key]
        assert.is_truthy(label, code .. " is missing " .. key)
        local shown = label:gsub("%%s", "5.6k"):gsub("%%d", "93")
        assert.is_true(displayWidth(shown) <= 26, ("%s: %q is %d wide"):format(code, shown, displayWidth(shown)))
      end
    end)
  end

  -- The addon's measured monospace metric: 0.6 em a character, an em of `size` x Theme.Scale()
  -- pixels. A cell of `width` px in a mono-`size` face holds floor(width / (0.6 * size * scale)).
  local function holds(width, size, scale) return math.floor(width / (0.6 * size * scale)) end

  local source
  local function sellSource()
    if not source then
      local file = assert(io.open("GoldCap/UI/SellFrame.lua", "r"))
      source = file:read("*a")
      file:close()
    end
    return source
  end

  -- The line under THE BOOK: 294px (the panel's 340, less its scroll gutter and edges), mono-10.
  -- Two cells on it -- what the price's place means, then "yours ×N" in the blue of your own
  -- levels, right-aligned -- and neither is ever cut: the longest of the words with the longest
  -- key, formatted with the widest figures each can carry, fit side by side at 1.0 and at 1.3
  -- (final review I1: "past the first 100 prices read (5.6k units)" plus "yours ×300" ran off the
  -- line in every Latin and Cyrillic language, and the count was the part cut).
  it("draws the line under THE BOOK in the mono-10 face both of its cells are budgeted in", function()
    assert.is_truthy(sellSource():find("row.drawerStand = Theme.Num(row, 10)", 1, true))
    assert.is_truthy(sellSource():find("row.drawerOwn = Theme.Num(row, 10)", 1, true))
  end)

  for _, code in ipairs(helper.localeCodes()) do
    it(("keeps the %s line under THE BOOK whole, its count and yours ×N, at 1.0 and 1.3"):format(code), function()
      local GC = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", GC)
      local translations = GC.Locales[code]
      local words = {
        { "~%dh to reach you", "23" }, { "~%dd to reach you", "99" },
        { "%s+, %d prices read", "12.3k", "100" }, { "price stands %d of %d", "8", "100" },
      }
      -- Five-character counts (load-bearing round M-4): a deep book reads "12.3k+", and a wall of
      -- your own "×12.3k". "5.6k" measured one character short of both.
      local own = assert(translations["yours ×%s"], code .. " is missing yours ×%s"):gsub("%%s", "12.3k")
      for _, entry in ipairs(words) do
        local label = assert(translations[entry[1]], code .. " is missing " .. entry[1])
        local i = 1
        local shown = label:gsub("%%[sd]", function() i = i + 1 return entry[i] end)
        for _, scale in ipairs({ 1.0, 1.3 }) do
          local width = displayWidth(shown) + 1 + displayWidth(own)
          assert.is_true(width <= holds(294, 10, scale), ("%s at %.1f: %q + %q is %d, over %d"):format(
            code, scale, shown, own, width, holds(294, 10, scale)))
        end
      end
    end)
  end

  -- "wall" at the start of its level's bar, mono-9, in a tag of WALL_TAG_W pixels (less 2 for air)
  -- when the client cannot measure it: every language's word fits at 1.3 (final review I2 --
  -- "стена" was 35px in a 28px tag).
  for _, code in ipairs(helper.localeCodes()) do
    it(("fits the %s wall word in its tag at 1.3"):format(code), function()
      local GC = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", GC)
      local tagW = tonumber(sellSource():match("WALL_TAG_W = (%d+)"))
      local word = assert(GC.Locales[code]["wall"], code .. " is missing wall")
      assert.is_true(displayWidth(word) <= holds(tagW - 2, 9, 1.3), ("%s: %q in %dpx"):format(code, word, tagW))
    end)
  end

  -- The dock's second line beside POST: ~254px of mono-9 at the default window, 47 characters
  -- at 1.0. The late-answer notes were 54 and 68 in English and lost the "a minute" that is
  -- their point in nearly every language (final review M2).
  for _, code in ipairs(helper.localeCodes()) do
    it(("keeps the %s late-answer notes on the dock's line"):format(code), function()
      local GC = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", GC)
      for _, key in ipairs({ "No answer yet -- listening for a minute", "Last post may still go up -- wait a minute" }) do
        local label = assert(GC.Locales[code][key], code .. " is missing " .. key)
        assert.is_true(displayWidth(label) <= holds(254, 9, 1.0), ("%s: %q is %d wide"):format(
          code, label, displayWidth(label)))
      end
    end)
  end

  -- The check pane's facts: Theme.Label(factsBlock, 11) in a DG.FACT_LABEL_W column, one line, no
  -- wrap (UI/SniperFrame.lua, createDialog). Measured at the default scale with the mono metric:
  -- exact for the bundled mono face ukUA and ruRU labels are drawn in away from a Russian client
  -- (Theme.RefreshFonts), an upper bound for a client's own face. The yardstick is the column's
  -- own: in each language, the longest label already in it that fits. "Sales certainty" is new
  -- there and must be no longer than that. English is the key itself and was ruled on its own;
  -- spec/check_verdict_spec.lua pins it.
  local FACT_KEYS = { "Sellers", "Sold per day", "Sell-through", "Live ask", "Snapshot value",
    "You would pay", "You would get", "Gold tied up", "If it clears", "You pay", "Worst case back",
    "Your minimum", "Your price" }
  local sniper
  local function factColumn()
    if not sniper then
      local file = assert(io.open("GoldCap/UI/SniperFrame.lua", "r"))
      sniper = file:read("*a")
      file:close()
    end
    assert.is_truthy(sniper:find("rowFacts.label = Theme.Label(factsBlock, 11)", 1, true))
    return tonumber(sniper:match("DG.FACT_LABEL_W = (%d+)"))
  end

  for _, code in ipairs(helper.localeCodes()) do
    if code ~= "enUS" then
      it(("fits the %s Sales certainty label in the check pane's fact column"):format(code), function()
        local GC = helper.loadModule("Locale/Core.lua")
        helper.loadModule("Locale/" .. code .. ".lua", GC)
        local translations = GC.Locales[code]
        local budget = holds(factColumn(), 11, 1.0)
        local yardstick = 0
        for _, key in ipairs(FACT_KEYS) do
          local width = displayWidth(assert(translations[key], code .. " is missing " .. key))
          if width <= budget and width > yardstick then yardstick = width end
        end
        local label = assert(translations["Sales certainty"], code .. " is missing Sales certainty")
        assert.is_true(displayWidth(label) <= yardstick, ("%s: %q is %d wide, the column's longest fitting label %d"):format(
          code, label, displayWidth(label), yardstick))
      end)
    end
  end

  -- A deal only the wallet limit refused. Its verdict cell is the tier column's TierMark, mono-10
  -- bold: 80px less the 11px its dot and gap take (COLUMNS in UI/SniperFrame.lua), the same
  -- eleven characters "SAFE +9999g" was sized to -- measured with the same four-figure amount.
  -- Its line at the top of the board is Theme.Label(10) between the ITEMS chip and the window's
  -- right gutter: at the default 720px window, 688 - 332 = 356px.
  for _, code in ipairs(helper.localeCodes()) do
    it(("fits the %s needs-gold cell and the not-enough-gold line"):format(code), function()
      local GC = helper.loadModule("Locale/Core.lua")
      helper.loadModule("Locale/" .. code .. ".lua", GC)
      local translations = GC.Locales[code]
      local needs = assert(translations["needs %s"], code .. " is missing needs %s"):gsub("%%s", "9999g")
      assert.is_true(displayWidth(needs) <= holds(69, 10, 1.0), ("%s: %q is %d wide"):format(
        code, needs, displayWidth(needs)))
      local key = "Not enough gold on this character to buy what GoldCap finds"
      local line = assert(translations[key], code .. " is missing " .. key)
      assert.is_true(displayWidth(line) <= holds(356, 10, 1.0), ("%s: %q is %d wide"):format(
        code, line, displayWidth(line)))
    end)
  end
end)
