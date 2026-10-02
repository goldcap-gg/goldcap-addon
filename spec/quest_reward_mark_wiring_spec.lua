-- The quest reward mark (UI/QuestRewardMark.lua, Core/QuestReward.lua): how it is wired, and what
-- it must never do.

local function read(path)
  local f = assert(io.open(path))
  local text = f:read("*a")
  f:close()
  return text
end

local function code(path)
  return (read(path):gsub("%-%-[^\n]*", ""))
end

local FILES = { "GoldCap/Core/QuestReward.lua", "GoldCap/UI/QuestRewardMark.lua" }

describe("quest reward mark wiring", function()
  it("loads both files in both games", function()
    for _, toc in ipairs({ "GoldCap/GoldCap.toc", "GoldCap/GoldCap_Camelot.toc" }) do
      local text = read(toc)
      for _, path in ipairs(FILES) do
        assert.truthy(text:find("\n" .. path:gsub("^GoldCap/", "") .. "\n", 1, true), path .. " missing from " .. toc)
      end
    end
  end)

  it("hooks the quest frame again on entering the world, in case it was not there at load", function()
    local init = read("GoldCap/Core/Init.lua")
    local world = assert(init:find('event == "PLAYER_ENTERING_WORLD"', 1, true))
    local nextEvent = assert(init:find('event == "GET_ITEM_INFO_RECEIVED"', world, true))
    local install = assert(init:find("GC.QuestRewardMark.Install()", world, true))
    assert.is_true(install < nextEvent)
  end)

  -- Read-only, both games alike, and inside the owner's UI rules.
  it("never sells, buys, picks a reward or clicks anything", function()
    local FORBIDDEN = { "UseContainerItem", "PickupContainerItem", "SellAllJunkItems", "BuyMerchantItem",
      "GetQuestReward", "QuestInfoItem_OnClick", "itemChoice", ":Click(", ".Click(", "SetScript(" }
    for _, path in ipairs(FILES) do
      local text = code(path)
      for _, needle in ipairs(FORBIDDEN) do
        assert.is_nil(text:find(needle, 1, true), ("%s contains %s"):format(path, needle))
      end
    end
  end)

  it("never tells the games apart: both draw the same quest window", function()
    for _, path in ipairs(FILES) do
      local text = code(path)
      assert.is_nil(text:find("IsForever", 1, true), path)
      assert.is_nil(text:find("WOW_PROJECT_ID", 1, true), path)
      assert.is_nil(text:find("GetBuildInfo", 1, true), path)
    end
  end)

  it("switches nothing with SetAlpha, and writes no middle dot the client's fonts may lack", function()
    for _, path in ipairs(FILES) do
      local text = code(path)
      assert.is_nil(text:find("SetAlpha", 1, true), path)
      assert.is_nil(text:find("\194\183", 1, true), path)
    end
    -- The sentence, in every language.
    local helper = require("spec.spec_helper")
    local GC = helper.loadModule("Locale/Core.lua")
    local KEYS = {
      "GoldCap: the reward in the gold frame is worth the most on the auction house (%s).",
    }
    for _, localeCode in ipairs(helper.localeCodes()) do
      helper.loadModule("Locale/" .. localeCode .. ".lua", GC)
      for _, key in ipairs(KEYS) do
        local value = GC.Locales[localeCode][key]
        assert.is_string(value, localeCode .. " has no " .. key)
        assert.is_nil(value:find("\194\183", 1, true), localeCode .. ": " .. value)
        assert.is_nil(value:find("...", 1, true), localeCode .. ": " .. value)
        assert.is_nil(value:find("\226\128\166", 1, true), localeCode .. ": " .. value)
      end
    end
  end)
end)
