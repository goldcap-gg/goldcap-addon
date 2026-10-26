local helper = require("spec.spec_helper")

-- The Disenchant window (UI/DisenchantFrame.lua): its words in all twelve languages, each really
-- translated, and none written with a dash, an ellipsis or a middle dot (the owner's rule: plain
-- punctuation in everything a player reads). "Next", "Skip", "Vendor" and "%d of %d" are older keys
-- the window shares, so they are not listed here. The tooltip's lines and the Kept menu (Task 3b) are here too.
local KEYS = {
  -- The window's name, its button's word and the key binding's label.
  "Disenchant", "Disenchant next",
  -- The Next card: its label while a cast goes, the verdicts, the cast bar and the key line.
  "Now", "Mats pay more: about %s against %s from a vendor.", "A vendor pays more: %s against about %s in mats.",
  "GoldCap learns what this gives the first time.", "GoldCap has no price yet for what this gives.",
  "The auction house pays more: %s after its cut.", "Disenchanting",
  "One press, one item. A key works too: %s, GoldCap, %s.", "item level %d", "Nothing in your bags to disenchant.",
  -- The yield strip.
  "You get about", "Got so far", "GoldCap learns what these give as you disenchant.",
  -- The lists, the right-click menu and the footer.
  "In this order", "Mats", "Never disenchant this", "Left out: the auction house pays more", "Mats: about %s",
  "Disenchant anyway", "Left out: a vendor pays more", "Vendor %s, mats about %s",
  "Mats is what your own disenchants of such items gave, at today's prices. Never on the list: items in an " ..
    "equipment set, items you can still return or trade, items in a group you follow, and items you keep. " ..
    "Click a line to disenchant it next. Right-click a line to keep an item.",
  -- The entry's tooltip and /gc disenchant on a character without the spell.
  "GoldCap Disenchant, 1 item", "GoldCap Disenchant, %d items", "This character does not know Disenchant.",
  -- The item tooltip's one line beside "Disenchant": what its kind gives and where it stands.
  "%s, next", "%s, AH pays more", "%s, vendor pays more", "kept", "cannot be disenchanted", "not learned yet",
  "no price yet",
  -- The way back for a kept item: the window's line and its menu.
  "Kept: 1 item", "Kept: %d items", "Show", "Never disenchanted", "Disenchant it again",
  -- The items the client refused for good, in the same menu.
  "GoldCap could not disenchant these", "Try again",
}

local BANNED = { "\226\128\148", "\226\128\147", "\226\128\166", "\194\183", "..." } -- em dash, en dash, ellipsis, middle dot

describe("Disenchant window strings", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Locale/Core.lua", GC)
    for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
  end)

  it("carries every key in all twelve languages, translated", function()
    assert.equal(12, #helper.localeCodes())
    for _, code in ipairs(helper.localeCodes()) do
      local strings = GC.Locales[code]
      for _, key in ipairs(KEYS) do
        local text = strings[key]
        assert.is_string(text, ("%s lacks %q"):format(code, key))
        if code ~= "enUS" then
          assert.are_not.equal(key, text, ("%s leaves %q in English"):format(code, key))
        end
      end
    end
  end)

  it("writes none of them with a dash, an ellipsis or a middle dot", function()
    for _, code in ipairs(helper.localeCodes()) do
      for _, key in ipairs(KEYS) do
        for _, banned in ipairs(BANNED) do
          assert.is_nil(GC.Locales[code][key]:find(banned, 1, true), ("%s: %q"):format(code, key))
        end
      end
    end
  end)
end)
