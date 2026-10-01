local _, GC = ...

-- The quest reward mark. When a quest giver shows a choice of rewards, the one worth the most on
-- the auction house gets a gold frame, and a line under the rewards says what it is worth. The
-- choice is Core/QuestReward.lua's; the price is the one each item's own tooltip prints
-- (GC.Tooltip.Headline over GC.Data.GetItemValue -- in WoW: Forever every player's scans or the
-- player's own, and for gear the cheapest version's price). Read-only: it selects nothing, clicks
-- nothing and makes no protected call. The frame sits over the reward button and takes no mouse,
-- so the player's own click still lands on the reward.
--
-- Both games draw this window with the same Blizzard code: retail and WoW: Forever both load
-- Blizzard_UIPanels_Game's Mainline QuestInfo.lua, QuestFrame.lua and QuestInfo.xml, and
-- LargeItemButtonTemplate from Blizzard_ItemButton (wow-ui-source live 12.1.0.69933 and forever
-- 1.60.1.70124, read 2026-10-01). Every read of the client is in `Client` and `Read` below; a
-- difference between the games goes there and nowhere else.
GC.QuestRewardMark = GC.QuestRewardMark or {}
local M = GC.QuestRewardMark

local LOOT_ITEM = 0                     -- GetQuestItemInfoLootType: 0 an item, 1 a currency
local LAYOUT = { GAP = 6, BOTTOM = 4, LEVEL_ABOVE = 2 }
local CLEAR = { 0, 0, 0, 0 }

-- The client, in one place. QuestInfoFrame's `questLog` and `rewardsFrame` are set by
-- QuestInfo_Display; the two reward functions are the ones QuestInfo_ShowRewards itself calls when
-- the quest giver's own window (not the quest log) is up.
function M.Client()
  return {
    info = _G.QuestInfoFrame,
    lootType = _G.GetQuestItemInfoLootType,
    itemInfo = _G.GetQuestItemInfo,
  }
end

-- The quest giver's reward frame and its choices, in the order it draws them: each
-- `{ button = <reward button>, itemID = <number or nil>, count = <units> }`. A currency choice has
-- no itemID. nil when the window up is the quest log or the map (their rewards are not the quest
-- giver's, and the two reward functions would answer for the wrong quest), or when there is no
-- reward frame on screen.
function M.Read(client)
  local info = client and client.info
  if type(info) ~= "table" or info.questLog then return nil end
  local frame = info.rewardsFrame
  if type(frame) ~= "table" or type(frame.RewardButtons) ~= "table" or not frame:IsShown() then return nil end
  if type(client.lootType) ~= "function" or type(client.itemInfo) ~= "function" then return nil end
  local choices = {}
  for _, button in ipairs(frame.RewardButtons) do
    -- Blizzard stamps `type` on every reward button it fills ("choice" or "reward") and hides the
    -- ones it does not use; a choice button's ID is its index in the quest's choice list.
    if button.type == "choice" and button:IsShown() then
      local index = button:GetID()
      local choice = { button = button }
      if client.lootType("choice", index) == LOOT_ITEM then
        local _, _, count, _, _, itemID = client.itemInfo("choice", index)
        if type(itemID) == "number" then
          choice.itemID, choice.count = itemID, count
        end
      end
      choices[#choices + 1] = choice
    end
  end
  return frame, choices
end

-- The total each choice is worth: the tooltip's figure for one, times the units.
function M.Worths(choices)
  local list = {}
  for i, choice in ipairs(choices) do
    local unit = choice.itemID and GC.Tooltip.Headline(GC.Data.GetItemValue(choice.itemID)) or nil
    list[i] = { worth = GC.QuestReward.Worth(unit, choice.count) }
  end
  return list
end

local function build(frame)
  local T = GC.Theme
  local holder = CreateFrame("Frame", nil, frame)
  holder:SetAllPoints(frame)
  -- A gold ring over the reward: the same small rounded ring every GoldCap card wears, with no
  -- fill, so the reward's icon and name stay as Blizzard drew them.
  holder.ring = T.Card(holder, CLEAR, T.color.gold, true)
  -- The line under the rewards: the quest window's own font, wrapped to the reward frame's width.
  -- When GoldCap speaks a language the client's face cannot draw (Russian or Ukrainian on an
  -- English client), the face T.Label would switch to, at the quest font's own size.
  local label = T.ClientFont(holder:CreateFontString(nil, "ARTWORK", "QuestFont"))
  if T.FONT_LABEL then
    local _, size, flags = label:GetFont()
    label:SetFont(T.FONT_LABEL, size or 13, flags or "")
  end
  label:SetJustifyH("LEFT")
  label:SetWordWrap(true)
  holder.label = label
  return holder
end

-- Gives the reward frame back the height Blizzard gave it, if the line had made it taller.
local function shrink()
  local grown = M._grown
  M._grown = nil
  if grown and math.abs(grown.frame:GetHeight() - grown.to) < 0.5 then grown.frame:SetHeight(grown.from) end
end

function M.Clear()
  if M._mark then M._mark:Hide() end
  shrink()
end

-- Draws the mark on `button` and the line under the rewards. The line goes below the last reward
-- row, inside the reward frame, which is made taller by the line's own wrapped height: the quest
-- window's scroll frame then scrolls to it, and nothing Blizzard draws is moved or covered.
function M.Draw(frame, button, worth)
  local mark = M._mark
  if not mark then
    mark = build(frame)
    M._mark = mark
  end
  mark.ring:ClearAllPoints()
  mark.ring:SetAllPoints(button)
  mark.ring:SetFrameLevel(button:GetFrameLevel() + LAYOUT.LEVEL_ABOVE)

  -- Blizzard sets the frame's height every time it lays the rewards out; a height still equal to
  -- the one set here last time is that same layout with the line already added.
  local base = frame:GetHeight()
  local grown = M._grown
  if grown and grown.frame == frame and math.abs(base - grown.to) < 0.5 then base = grown.from end

  local label = mark.label
  local choose = frame.ItemChooseText
  if type(choose) == "table" and choose.GetTextColor then label:SetTextColor(choose:GetTextColor()) end
  label:ClearAllPoints()
  label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(base + LAYOUT.GAP))
  label:SetWidth(frame:GetWidth())
  label:SetText(GC.L["GoldCap: the reward in the gold frame is worth the most on the auction house (%s)."]
    :format(GC.Util.CoinText(worth)))
  local to = base + LAYOUT.GAP + label:GetHeight() + LAYOUT.BOTTOM
  frame:SetHeight(to)
  M._grown = { frame = frame, from = base, to = to }
  mark:Show()
end

-- After Blizzard has drawn the quest giver's rewards: mark the best choice, or take the mark away.
function M.Refresh()
  local frame, choices = M.Read(M.Client())
  local best, worth
  if frame then best, worth = GC.QuestReward.Best(M.Worths(choices)) end
  if best then
    M.Draw(frame, choices[best].button, worth)
  else
    M.Clear()
  end
end

-- Post-hooks on the two ways Blizzard draws the rewards: QuestInfo_Display (every time the quest
-- giver's window opens a quest) and QuestInfo_ShowRewards (when the quest's item data arrives
-- later, on QUEST_ITEM_UPDATE). The templates hold their own reference to QuestInfo_ShowRewards,
-- so its hook alone would miss the first draw. hooksecurefunc runs after Blizzard's code and
-- cannot change what it did. Once only; true when the hooks are in place.
function M.Install()
  if M._installed then return true end
  local hook = _G.hooksecurefunc
  if type(hook) ~= "function" or type(_G.QuestInfo_Display) ~= "function"
      or type(_G.QuestInfo_ShowRewards) ~= "function" then
    return false
  end
  hook("QuestInfo_Display", function() M.Refresh() end)
  hook("QuestInfo_ShowRewards", function() M.Refresh() end)
  M._installed = true
  return true
end

M.Install()
