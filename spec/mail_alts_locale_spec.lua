local helper = require("spec.spec_helper")

-- Send to alts (UI/MailAltsFrame.lua): the words its final review round added, in all twelve
-- languages, each really translated, and none written with a dash, an ellipsis or a middle dot (the
-- owner's rule: plain punctuation in everything a player reads).
local KEYS = {
  -- A run stopped because the player (or Blizzard, after a reply's mail) left the Send Mail tab.
  "The Send Mail tab was closed.",
  -- The end of a run in which the server refused a character's mail.
  "Sent 1 mail.", "Sent %d mails.", "The mail to %s did not go.",
  -- A press this character cannot pay the postage of.
  "Postage is %s and this character has %s.",
  -- The recipient menu while none of the account's other characters is known yet.
  "Your other characters show here once each has logged in with GoldCap.",
  -- A typed name of a character recorded on the other faction (the code review, 2026-10-27).
  "Mail goes only to a character of your faction.",
  -- A group set not to be sent (hide-groups, 2026-10-27).
  "Don't send this group", "Send this group again", "Not sent", "Not sent from this realm.",
  "Show 1 group not sent", "Show %d groups not sent", "Hide the groups not sent",
  "Every group here is set not to be sent.",
  -- Keep leaves exactly its count: a split with no empty slot of a plain bag to go to.
  "No free bag slot to split %s, so more of it stays than its keep.",
  -- A split part that never showed in the bags (the Hoard says it in the chat).
  "The split did not show up in your bags in time and was put back.",
}

-- A refused mail no longer stops the run: its old stop text is gone from every language.
local GONE = { "The mail did not go: what was attached is back in your bags." }

local BANNED = { "\226\128\148", "\226\128\147", "\226\128\166", "\194\183", "..." } -- em dash, en dash, ellipsis, middle dot

describe("Send to alts strings", function()
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

  it("drops the words of a stop that no longer happens", function()
    for _, code in ipairs(helper.localeCodes()) do
      for _, key in ipairs(GONE) do
        assert.is_nil(GC.Locales[code][key], ("%s still carries %q"):format(code, key))
      end
    end
  end)
end)
