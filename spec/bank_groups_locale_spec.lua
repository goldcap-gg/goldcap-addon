local helper = require("spec.spec_helper")

-- Every player string the GoldCap Hoard shows (UI/HoardFrame.lua, UI/HoardRow.lua and
-- UI/HoardList.lua), in all twelve languages, and none of them written with a dash, an ellipsis or a middle dot: the owner's
-- rule is plain punctuation in everything a player reads. The popup's "Type a whole number" and
-- "Save" are the craft queue's and BUY's own keys. The two sides of the bank switch are the bank
-- window's own tab names, Blizzard's BANK and ACCOUNT_BANK_PANEL_TITLE, so they need no key. The
-- window's name is "Hoard" in the player's language beside the brand, GoldCap, which stays. The
-- search box's "Search" is BUY's own key, and a run's "Stop" the vendor sell's and the mail's.
local KEYS = {
  -- The window's name, at its header and on the handle that brings it back.
  "Hoard",
  -- The switch's free slots, the groups' heading with the bar's legend, and the buttons over every
  -- group.
  "Bags %d free", "Bank %d free", "Your groups", "bags", "bank", "Store all", "Take all out",
  -- A row: its two moves and what their tooltips say, its play, a folder's count, and the fold
  -- line.
  "Store", "Take out", "%s ×%d (%d left)", "Nothing to move", "Gather", "Craft", "Flip", "Stock", "%d groups",
  "%d more groups have nothing to move at this bank", "1 more group has nothing to move at this bank",
  -- An opened row, at the Warband Bank and at the character's own bank, and its keep count's popup.
  "%d in bags, %d in the Warband Bank", "%d in bags, %d in your bank", "Keep in bags: %d of each",
  "How many of each item in %s to keep in your bags?", "Stays in bags: %s ×%d, can still be refunded",
  "Stays in bags: %s ×%d, the Warband Bank does not take it", "Stays in bags: %s ×%d, your bank does not take it",
  "Type a whole number", "Save",
  -- No followed group's item in the bags or this bank.
  "None of your groups' items are in your bags or this bank.",
  -- The search row's filter and sort, and a search that matches nothing.
  "To move here %d", "All %d", "By value", "By name", "No group or item matches your search.",
  -- The selection bar: its hint while nothing is checked, its lines, its buttons' and its clear
  -- button's tooltips.
  "Tick groups to move several at once", "%d groups selected", "1 group selected", "%d not shown", "Worth about %s",
  "%d stacks into %s", "1 stack into %s", "%d stacks into your bags", "1 stack into your bags", "Clear the selection",
  -- A run: its cast bar, and its Stop's tooltip.
  "Moving to %s", "Moving to your bags", "Stop moving",
}

-- The bank by group card's, which the Hoard took over from: gone from every language.
local GONE = {
  "GoldCap: your groups", "To bank: %s ×%d (%d left)", "To bags: %s ×%d (%d left)", "To bank: nothing to move",
  "To bags: nothing to move", "Groups with nothing to move: %d", "All to bank", "All to bags",
  "Nothing to move at this bank.",
  -- The selection bar's first stacks line, which named a count neither of its buttons moves.
  "%d stacks to move, worth about %s", "1 stack to move, worth about %s",
}

local BANNED = { "\226\128\148", "\226\128\147", "\226\128\166", "\194\183", "..." } -- em dash, en dash, ellipsis, middle dot

describe("GoldCap Hoard strings", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Locale/Core.lua", GC)
    for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
  end)

  it("has every string in all 12 locales", function()
    assert.equal(12, #helper.localeCodes())
    for _, code in ipairs(helper.localeCodes()) do
      for _, key in ipairs(KEYS) do
        local value = GC.Locales[code][key]
        assert.is_string(value, ("%s has no %q"):format(code, key))
        assert.is_true(value ~= "", ("%s: %q is empty"):format(code, key))
      end
    end
  end)

  it("translates them outside English", function()
    for _, code in ipairs(helper.localeCodes()) do
      if code ~= "enUS" then
        for _, key in ipairs(KEYS) do
          assert.is_true(GC.Locales[code][key] ~= key, ("%s leaves %q in English"):format(code, key))
        end
      end
    end
  end)

  it("keeps none of the bank card's strings", function()
    for _, code in ipairs(helper.localeCodes()) do
      for _, key in ipairs(GONE) do
        assert.is_nil(rawget(GC.Locales[code], key), ("%s still has %q"):format(code, key))
      end
    end
  end)

  it("writes no dash, ellipsis or middle dot", function()
    for _, code in ipairs(helper.localeCodes()) do
      for _, key in ipairs(KEYS) do
        for _, text in ipairs({ key, GC.Locales[code][key] or "" }) do
          for _, banned in ipairs(BANNED) do
            assert.is_nil(text:find(banned, 1, true), ("%s: %q"):format(code, text))
          end
        end
      end
    end
  end)
end)
