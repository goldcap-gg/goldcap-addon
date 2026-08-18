local _, GC = ...

-- What is actually in the player's bags and could be put on the auction house.
--
-- The Sell tab used to derive its whole world from GoldCap's own purchase ledger: a position
-- existed only if GoldCap had recorded buying the item, or if the player already had it listed.
-- Everything farmed, crafted, looted, milled or bought before the addon was installed was
-- invisible, so the answer to "what can I sell right now" was "open the Blizzard sell tab and
-- find out yourself". This module supplies the missing half.
--
-- Pure by construction: every WoW API call is injected through `driver`, so the identity rules
-- (which are the delicate part -- a commodity and an item-with-bonus-ids key differently, and
-- getting that wrong splits one item into two positions) stay in the caller, and the walk itself
-- is testable headless.
GC.BagStock = {}

local MAX_EXACT = 9007199254740991

local function exactPositive(value)
  return type(value) == "number" and value == value and value ~= math.huge
    and value == math.floor(value) and value > 0 and value <= MAX_EXACT
end

local function add(left, right)
  if not exactPositive(left) and left ~= 0 then return nil end
  if not exactPositive(right) then return nil end
  if left > MAX_EXACT - right then return nil end
  return left + right
end

--- driver = {
--   numSlots(bag) -> number,
--   itemInfo(bag, slot) -> { itemID, stackCount, isBound, hasNoValue, hyperlink, itemName } | nil,
--   classify(itemID, link) -> positionKey | nil, isCommodity | nil,
-- }
--
-- `bags` is the list of container ids to walk (the caller owns which bags count as sellable
-- storage -- a reagent bank slot is not a bag the auction house can post from).
--
-- Returns an array of { positionKey, itemID, itemName, quantity, isCommodity, stacks } sorted by
-- positionKey, so a render built from it is stable across scans.
--
-- Skipped, and why:
--   isBound        -- soulbound; the auction house will refuse it, so offering it is a lie.
--   hasNoValue     -- vendor-worthless junk the AH also refuses (quest items, conjured goods).
--   classify = nil -- an item whose exact auction identity cannot be derived (a bonus-id bearing
--                     link). Posting one under a guessed key is how the split-position bug
--                     happened; leaving it out is the honest failure.
function GC.BagStock.Scan(driver, bags)
  if type(driver) ~= "table" or type(driver.numSlots) ~= "function"
      or type(driver.itemInfo) ~= "function" or type(driver.classify) ~= "function" then
    return {}
  end
  local byKey, order = {}, {}
  for _, bag in ipairs(bags or {}) do
    local slots = driver.numSlots(bag) or 0
    for slot = 1, slots do
      local info = driver.itemInfo(bag, slot)
      local quantity = info and info.stackCount or nil
      if info and exactPositive(info.itemID) and exactPositive(quantity)
          and info.isBound ~= true and info.hasNoValue ~= true then
        local positionKey, isCommodity = driver.classify(info.itemID, info.hyperlink)
        if type(positionKey) == "string" and positionKey ~= "" then
          local entry = byKey[positionKey]
          if not entry then
            entry = { positionKey = positionKey, itemID = info.itemID, itemName = info.itemName,
              quantity = 0, isCommodity = isCommodity == true, stacks = {} }
            byKey[positionKey], order[#order + 1] = entry, positionKey
          end
          entry.itemName = entry.itemName or info.itemName
          local total = add(entry.quantity, quantity)
          -- An overflowing total is not clamped: a position whose quantity cannot be stated
          -- exactly must not be offered for posting at all, so drop the whole entry.
          if total then
            entry.quantity = total
            entry.stacks[#entry.stacks + 1] = { bag = bag, slot = slot, quantity = quantity }
          else
            entry.overflow = true
          end
        end
      end
    end
  end
  local result = {}
  table.sort(order)
  for _, positionKey in ipairs(order) do
    local entry = byKey[positionKey]
    if not entry.overflow then result[#result + 1] = entry end
  end
  return result
end

--- The single largest stack of a position, which is what a non-commodity post is limited to:
-- PostItem takes one ItemLocation, and while the API will pull the remainder from other bag
-- slots, GoldCap only ever posts a quantity it has proven sits in the one slot it pinned.
-- Commodities aggregate instead -- the whole bag total is one postable pool.
function GC.BagStock.PostableQuantity(entry)
  if type(entry) ~= "table" then return nil end
  if entry.isCommodity then return exactPositive(entry.quantity) and entry.quantity or nil end
  local best
  for _, stack in ipairs(entry.stacks or {}) do
    if exactPositive(stack.quantity) and (best == nil or stack.quantity > best) then best = stack.quantity end
  end
  return best
end
