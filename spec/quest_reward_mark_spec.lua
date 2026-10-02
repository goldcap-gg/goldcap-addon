local helper = require("spec.spec_helper")
local W = require("spec.support.wow_frames")

-- UI/QuestRewardMark.lua against doubles shaped like the client's quest window. Every field below
-- that is not a widget method is one Blizzard's own code puts there, in both games' Mainline
-- QuestInfo.lua/QuestInfo.xml (wow-ui-source live 12.1.0, forever 1.60.1.70124):
--   QuestInfoFrame.questLog / .rewardsFrame / .itemChoice   QuestInfo_Display, QuestInfoItem_OnClick
--   rewardsFrame.RewardButtons / .ItemChooseText            QuestInfo.xml parentArray / parentKey
--   button.type ("choice" | "reward"), button:SetID(index)  QuestInfo_ShowRewards
-- GetQuestItemInfo answers name, texture, numItems, quality, isUsable, itemID, contextFlags, the
-- order QuestInfo_ShowRewardAsItemCommon reads it in.
describe("quest reward mark", function()
  local GC, M, restore, saved, VALUES, QUEST, calls, hooks
  local KEYS = { "QuestInfoFrame", "GetQuestItemInfo", "GetQuestItemInfoLootType", "hooksecurefunc",
    "QuestInfo_Display", "QuestInfo_ShowRewards", "GetCoinTextureString" }

  local BLIZZARD_HEIGHT = 200
  local LOOT_ITEM, LOOT_CURRENCY = 0, 1

  local function rewardsFrame(choices, fixed)
    local frame = W.CreateFrame("Frame")
    frame:SetSize(285, BLIZZARD_HEIGHT)
    frame.ItemChooseText = frame:CreateFontString(nil, "BACKGROUND", "QuestFont")
    frame.ItemChooseText:SetTextColor(0.2, 0.1, 0, 1)
    frame.RewardButtons = {}
    for i = 1, choices do
      local b = W.CreateFrame("Button", nil, frame)
      b:SetSize(147, 41)
      b.type = "choice"
      b:SetID(i)
      frame.RewardButtons[#frame.RewardButtons + 1] = b
    end
    for i = 1, fixed or 0 do
      local b = W.CreateFrame("Button", nil, frame)
      b.type = "reward"
      b:SetID(i)
      frame.RewardButtons[#frame.RewardButtons + 1] = b
    end
    -- A button a bigger quest used earlier: Blizzard hides it and leaves its old type and ID.
    local spare = W.CreateFrame("Button", nil, frame)
    spare.type = "choice"
    spare:SetID(#frame.RewardButtons + 1)
    spare:Hide()
    frame.RewardButtons[#frame.RewardButtons + 1] = spare
    return frame
  end

  -- The quest giver's window with `quest` as its choice list: { itemID, count, loot }.
  local function questGiver(quest, fixed)
    QUEST = quest
    local frame = rewardsFrame(#quest, fixed)
    _G.QuestInfoFrame = { questLog = nil, rewardsFrame = frame }
    return frame
  end

  local function ring() return M._mark and M._mark.ring end
  local function label() return M._mark and M._mark.label end
  local function marked()
    return M._mark ~= nil and M._mark:IsShown()
  end
  local function markedButton()
    return marked() and W.state(ring()).allPoints or nil
  end

  before_each(function()
    saved = {}
    for _, k in ipairs(KEYS) do saved[k] = _G[k] end
    restore = W.install()
    calls, hooks, VALUES, QUEST = {}, {}, {}, {}
    _G.GetQuestItemInfoLootType = function(kind, index)
      calls[#calls + 1] = { "lootType", kind, index }
      local q = QUEST[index]
      return q and q.loot or LOOT_ITEM
    end
    _G.GetQuestItemInfo = function(kind, index)
      calls[#calls + 1] = { "itemInfo", kind, index }
      local q = QUEST[index]
      if not q then return nil end
      return "Item " .. tostring(q.itemID), 134400, q.count or 1, 2, true, q.itemID, 0
    end
    _G.GetCoinTextureString = function(c) return c .. "c" end
    _G.hooksecurefunc = nil
    _G.QuestInfo_Display, _G.QuestInfo_ShowRewards = nil, nil
    GC = helper.loadModule("Core/Util.lua")
    helper.loadModule("Core/Trigger.lua", GC)
    helper.loadModule("Core/QuestReward.lua", GC)
    helper.loadModule("UI/Theme.lua", GC)
    helper.loadModule("UI/Tooltip.lua", GC)
    helper.loadModule("UI/QuestRewardMark.lua", GC)
    GC.Data = { GetItemValue = function(id) return VALUES[id] end }
    M = GC.QuestRewardMark
  end)

  after_each(function()
    restore()
    for _, k in ipairs(KEYS) do _G[k] = saved[k] end
  end)

  it("frames the choice worth the most -- its tooltip price times its units -- and says so under the rewards", function()
    VALUES[101] = { mv = 500, source = "import", kind = "region_commodity" }
    VALUES[102] = { mv = 300, source = "import", kind = "region_commodity" }
    VALUES[103] = { mv = 1200, source = "import", kind = "region_commodity" }
    local frame = questGiver({ { itemID = 101 }, { itemID = 102, count = 5 }, { itemID = 103 } })
    M.Refresh()
    local button = frame.RewardButtons[2]
    assert.equal(button, markedButton())
    -- Over the button, drawn above it, and taking no mouse: the click still lands on the reward.
    assert.is_true(W.state(ring()).level > button:GetFrameLevel())
    assert.is_false(M._mark:IsMouseEnabled())
    assert.is_false(ring():IsMouseEnabled())
    -- The line: the whole sentence, the choice's total, wrapped to the reward frame's width, in
    -- the colour Blizzard gave the frame's own "Choose your reward" text.
    local fs = label()
    assert.equal("GoldCap: the reward in the gold frame is worth the most on the auction house (1500c).", fs:GetText())
    assert.equal(285, fs:GetWidth())
    assert.is_true(W.state(fs).wordWrap)
    assert.same({ 0.2, 0.1, 0, 1 }, { fs:GetTextColor() })
    assert.is_true(fs:GetHeight() > W.LINE_H) -- this sentence wraps at 285 px: the box grew for it
  end)

  it("puts the line under the last row and makes the reward frame taller by exactly the line", function()
    VALUES[101] = { mv = 900, source = "import", kind = "region_commodity" }
    local frame = questGiver({ { itemID = 101 }, { itemID = 102 } })
    M.Refresh()
    local point, rel, relPoint, x, y = label():GetPoint(1)
    assert.same({ "TOPLEFT", frame, "TOPLEFT", 0, -(BLIZZARD_HEIGHT + 6) }, { point, rel, relPoint, x, y })
    assert.equal(BLIZZARD_HEIGHT + 6 + label():GetHeight() + 4, frame:GetHeight())
  end)

  it("does not grow the frame twice for the same layout, and follows a new one", function()
    VALUES[101] = { mv = 900, source = "import", kind = "region_commodity" }
    local frame = questGiver({ { itemID = 101 }, { itemID = 102 } })
    M.Refresh()
    local grown = frame:GetHeight()
    M.Refresh() -- QUEST_ITEM_UPDATE with nothing re-laid out
    assert.equal(grown, frame:GetHeight())
    frame:SetHeight(260) -- Blizzard lays the rewards out again
    M.Refresh()
    assert.equal(-(260 + 6), select(5, label():GetPoint(1)))
    assert.equal(260 + 6 + label():GetHeight() + 4, frame:GetHeight())
  end)

  it("takes the mark away, and gives back Blizzard's height, when nothing is priced any more", function()
    VALUES[101] = { mv = 900, source = "import", kind = "region_commodity" }
    local frame = questGiver({ { itemID = 101 }, { itemID = 102 } })
    M.Refresh()
    VALUES[101] = nil
    M.Refresh()
    assert.is_false(marked())
    assert.equal(BLIZZARD_HEIGHT, frame:GetHeight())
    -- A new layout by Blizzard is Blizzard's height, never "restored" over.
    VALUES[101] = { mv = 900, source = "import", kind = "region_commodity" }
    M.Refresh()
    frame:SetHeight(150)
    VALUES[101] = nil
    M.Refresh()
    assert.equal(150, frame:GetHeight())
  end)

  describe("which choice", function()
    local cases = {
      { "a tie goes to the first drawn", { 400, 400, 300 }, 1 },
      { "unpriced choices are passed over", { false, 250, false }, 2 },
      { "one priced choice is marked when it is worth more than nothing", { false, false, 1 }, 3 },
      { "a price of nothing is no price", { 0, false }, nil },
      { "nothing priced: no mark", { false, false }, nil },
      { "one choice is no choice", { 5000 }, nil },
    }
    for _, c in ipairs(cases) do
      it(c[1], function()
        local quest = {}
        for i, price in ipairs(c[2]) do
          quest[i] = { itemID = 500 + i }
          if price then VALUES[500 + i] = { mv = price, source = "import", kind = "region_commodity" } end
        end
        local frame = questGiver(quest)
        M.Refresh()
        assert.equal(c[3] and frame.RewardButtons[c[3]] or nil, markedButton())
      end)
    end
  end)

  it("reads a currency choice as no price, and never asks its item", function()
    VALUES[701] = { mv = 100, source = "import", kind = "region_commodity" }
    local frame = questGiver({ { loot = LOOT_CURRENCY }, { itemID = 701 } })
    M.Refresh()
    assert.equal(frame.RewardButtons[2], markedButton())
    for _, call in ipairs(calls) do
      assert.equal("choice", call[2])
      if call[1] == "itemInfo" then assert.equal(2, call[3]) end
    end
  end)

  it("never marks a fixed reward, or a button a bigger quest left behind", function()
    VALUES[801] = { mv = 100, source = "import", kind = "region_commodity" }
    VALUES[802] = { mv = 200, source = "import", kind = "region_commodity" }
    local frame = questGiver({ { itemID = 801 }, { itemID = 802 } }, 2)
    M.Refresh()
    assert.equal(frame.RewardButtons[2], markedButton())
    for _, call in ipairs(calls) do assert.is_true(call[3] <= 2) end
  end)

  it("WoW: Forever gear is worth what its tooltip says: every player's scans, the cheapest version", function()
    VALUES[901] = { mv = 4500, ts = 0, source = "scan", kind = "crowd", scanners = 3, gear = true }
    VALUES[902] = { mv = 3000, ts = 0, source = "scan", gear = true }
    questGiver({ { itemID = 902 }, { itemID = 901 } })
    M.Refresh()
    assert.equal("GoldCap: the reward in the gold frame is worth the most on the auction house (4500c).", label():GetText())
    local first = GC.Tooltip.BuildLines(VALUES[901], 0)[1]
    assert.equal("AH, cheapest version", first.label)
    assert.equal(4500, first.copper)
  end)

  it("a retail realm item is worth the region price its tooltip prints, not its realm median", function()
    -- Two listings on the realm made a median of 900g; the region's reference is 2g.
    VALUES[311] = { mv = 9000000, ref = 20000, ts = 0, source = "import", kind = "realm_item" }
    VALUES[312] = { mv = 50000, ts = 0, source = "import", kind = "region_commodity" }
    local frame = questGiver({ { itemID = 311 }, { itemID = 312 } })
    M.Refresh()
    assert.equal(frame.RewardButtons[2], markedButton())
    assert.equal(20000, GC.Tooltip.BuildLines(VALUES[311], 0)[1].copper)
  end)

  it("leaves the quest log and the map alone: their rewards are not the quest giver's", function()
    VALUES[101] = { mv = 900, source = "import", kind = "region_commodity" }
    local frame = questGiver({ { itemID = 101 }, { itemID = 102 } })
    _G.QuestInfoFrame.questLog = true
    M.Refresh()
    assert.is_false(marked())
    assert.equal(0, #calls)
    assert.equal(BLIZZARD_HEIGHT, frame:GetHeight())
  end)

  it("leaves a hidden reward frame alone", function()
    VALUES[101] = { mv = 900, source = "import", kind = "region_commodity" }
    local frame = questGiver({ { itemID = 101 }, { itemID = 102 } })
    frame:Hide() -- QuestInfo_ShowRewards with no rewards at all
    M.Refresh()
    assert.is_false(marked())
  end)

  it("selects nothing and touches no reward button", function()
    VALUES[101] = { mv = 900, source = "import", kind = "region_commodity" }
    local frame = questGiver({ { itemID = 101 }, { itemID = 102 } })
    M.Refresh()
    assert.is_nil(_G.QuestInfoFrame.itemChoice)
    for _, b in ipairs(frame.RewardButtons) do
      local s = W.state(b)
      assert.same({}, s.scripts)
      assert.is_nil(s.hooks)
      assert.equal(0, b:GetNumPoints())
    end
  end)

  it("hooks Blizzard's two reward draws once, after them, and refreshes on each", function()
    _G.QuestInfo_Display = function() end
    _G.QuestInfo_ShowRewards = function() end
    local installs = 0
    _G.hooksecurefunc = function(name, fn)
      installs = installs + 1
      hooks[name] = fn
    end
    assert.is_true(M.Install())
    assert.is_true(M.Install())
    assert.equal(2, installs)
    VALUES[101] = { mv = 900, source = "import", kind = "region_commodity" }
    questGiver({ { itemID = 101 }, { itemID = 102 } })
    hooks.QuestInfo_Display()
    assert.is_true(marked())
    VALUES[101] = nil
    hooks.QuestInfo_ShowRewards()
    assert.is_false(marked())
  end)

  it("does not hook a client that has no quest window yet", function()
    _G.hooksecurefunc = function() error("must not hook") end
    assert.is_false(M.Install())
  end)
end)
