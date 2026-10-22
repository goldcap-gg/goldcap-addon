local helper = require("spec.spec_helper")

-- Every player string the bank by group card adds (UI/BankGroupsCard.lua), in all twelve
-- languages, and none of them written with a dash, an ellipsis or a middle dot: the owner's rule
-- is plain punctuation in everything a player reads. The popup's "Type a whole number" and "Save"
-- are the craft queue's and BUY's own keys.
local KEYS = {
  "GoldCap: your groups",
  "%d in bags, %d in the Warband Bank", "Keep in bags: %d of each",
  "How many of each item in %s to keep in your bags?", "To bank: %s ×%d (%d left)", "To bags: %s ×%d (%d left)",
  "Stays in bags: %s ×%d, can still be refunded", "Stays in bags: %s ×%d, the Warband Bank does not take it",
  "To bank: nothing to move", "To bags: nothing to move",
  "Type a whole number", "Save",
}

local BANNED = { "\226\128\148", "\226\128\147", "\226\128\166", "\194\183", "..." } -- em dash, en dash, ellipsis, middle dot

describe("bank by group strings", function()
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
