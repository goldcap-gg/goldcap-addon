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
  local BUTTONS = {
    { what = "the 86px Sell action button", budget = 11,
      keys = { "Set cost", "Post", "Repost", "Cancel lot?", "Remove", "Remove?" } },
    { what = "the 64px Deals buy button", budget = 8,
      keys = { "Buy", "Check", "Avoid" } },
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
end)
