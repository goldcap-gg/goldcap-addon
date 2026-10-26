local helper = require("spec.spec_helper")

-- Every player string the crafting surfaces in the profession window add (UI/CraftStrip.lua,
-- UI/CraftPanel.lua, UI/CraftQueueView.lua), in all twelve languages, and none of them written
-- with a dash, an ellipsis or a middle dot: the client's faces draw some of those as boxes, and
-- the owner's rule is plain punctuation in everything a player reads.
local KEYS = {
  -- The strip under the open recipe's reagents.
  "Reagents cost %s", "One craft sells for %s after the auction house cut", "Profit %s",
  "No GoldCap price for %s",
  -- The panel's Worth crafting list.
  "Worth crafting", "Best profit a craft", "reagents at their cheapest quality", "Costs %s, sells for %s",
  "%d a craft. Costs %s, sells for %s", "about %s a day", "Slow seller", "Add one craft to the queue",
  "1 more recipe makes no profit now.", "%d more recipes make no profit now.", "No recipe here makes a profit now",
  "1 has no GoldCap price for a reagent or what it makes.", "%d have no GoldCap price for a reagent or what they make.",
  "No recipe here has a GoldCap price yet",
  -- How fast a crafted item sells, in Disenchant's notes (UI/DisenchantFrame.lua), once the panel's.
  "Sells about %s a day",
  -- This recipe, and the two questions it asks (BUY's popup: Add and Save are BUY's own keys).
  "This recipe", "In queue: %d", "Restock to %d", "Reagents", "Sells for, after cut", "Profit a craft", "Add to queue",
  "Restock to",
  "How many crafts of %s?", "Restock %s to how many? 0 takes it off the queue.", "Type a whole number", "Add", "Save",
  -- The Queue view.
  "Queue", "%d to craft", "%d to craft. Reagents for %d now", "Restock to %d: you hold %d, %d crafts",
  "Restock to %d: you hold %d, 1 craft", "Auctions not counted yet: open GoldCap's Sell tab at the auction house",
  "Remove from queue", "The queue is empty. Add a recipe from This recipe.",
  -- A line's Craft and the run of crafts it starts.
  "Craft %d", "Crafting", "%d crafted, %d to go", "Crafting %d one after another. Moving stops it.",
  "Crafting %s now. Wait for it to finish.",
  "Crafts %d now, one after another, with the reagents the profession window would use. Moving stops it.",
  "Open %s to craft it here.", "Open this recipe's profession to craft it here.",
  "Not enough reagents for one craft. Missing below says what to get.",
  -- Missing.
  "Missing", "about %s to buy", "%d have no price yet", "1 has no price yet", "%d in your mailbox", "about %s",
  "%s is not sold on the auction house", "Nothing is missing for the queue", "Make a BUY list",
  "The BUY tab at the auction house buys what is missing, and the list follows the queue.", "Craft queue",
  "BUY list %s is ready in the BUY tab at the auction house", "Currency %d",
}

local BANNED = { "\226\128\148", "\226\128\147", "\226\128\166", "\194\183", "..." } -- em dash, en dash, ellipsis, middle dot

describe("crafting strings", function()
  local GC

  before_each(function()
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Locale/Core.lua", GC)
    for _, code in ipairs(helper.localeCodes()) do helper.loadModule("Locale/" .. code .. ".lua", GC) end
  end)

  it("has every crafting string in all 12 locales", function()
    assert.equal(12, #helper.localeCodes())
    for _, code in ipairs(helper.localeCodes()) do
      for _, key in ipairs(KEYS) do
        local value = GC.Locales[code][key]
        assert.is_string(value, ("%s has no %q"):format(code, key))
        assert.is_true(value ~= "", ("%s: %q is empty"):format(code, key))
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
