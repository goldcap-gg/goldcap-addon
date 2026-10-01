local _, GC = ...

-- Which of a quest's reward choices fetches the most on the auction house. UI/QuestRewardMark.lua
-- reads the quest frame and draws the mark; this file only decides, and asks the client nothing.
GC.QuestReward = GC.QuestReward or {}

local function positive(n)
  return type(n) == "number" and n == n and n > 0
end

-- What one choice is worth: the price its tooltip prints for one (GC.Tooltip.Headline) times the
-- units the quest hands over. nil without a price, and for a price of nothing.
function GC.QuestReward.Worth(unit, count)
  if not positive(unit) then return nil end
  count = (type(count) == "number" and count >= 1) and math.floor(count) or 1
  return unit * count
end

-- `choices` is the quest's choice list in the order the quest frame draws it, each
-- `{ worth = <copper or nil> }`. Answers the position of the choice to mark and its worth, or nil:
--   * one choice is no choice, so it is never marked;
--   * a choice with no price, or a price of 0, is never marked -- when only one choice has a
--     price, that one is marked as long as it is worth more than nothing;
--   * the dearest wins, and a tie goes to the first drawn.
function GC.QuestReward.Best(choices)
  if type(choices) ~= "table" or #choices < 2 then return nil end
  local best, bestWorth
  for i, choice in ipairs(choices) do
    local worth = type(choice) == "table" and choice.worth or nil
    if positive(worth) and (bestWorth == nil or worth > bestWorth) then
      best, bestWorth = i, worth
    end
  end
  return best, bestWorth
end
