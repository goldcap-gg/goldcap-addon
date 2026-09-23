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
--   classify(itemID, link, bag, slot) -> positionKey | nil, isCommodity | nil, quoteKey | nil,
--     refused | nil (true: the auction house says it cannot take this stack -- skipped outright),
-- }
--
-- `bag`/`slot` are handed to `classify` because the exact auction identity of a non-commodity
-- stack is a property of that stack, not of its item: the client answers it for one ItemLocation
-- (C_AuctionHouse.GetItemKeyFromItem). `quoteKey` is what the market search for the position
-- is keyed by when that differs from the itemID (an item-level variant): carried to the
-- position unchanged.
--
-- `bags` is the list of container ids to walk (the caller owns which bags count as sellable
-- storage -- a reagent bank slot is not a bag the auction house can post from).
--
-- Returns an array of { positionKey, itemID, itemName, quantity, isCommodity, quoteKey, stacks }
-- sorted by positionKey, so a render built from it is stable across scans -- and, second, the
-- tradeable stock `classify` could not key yet, as { itemID, itemName, quantity } per item in
-- item order: an item the client has not said is a commodity or not, or whose identity it cannot
-- give. It used to be dropped here without a word; the tab shows it under its own heading.
--
-- Skipped, and why:
--   isBound        -- soulbound; the auction house will refuse it, so offering it is a lie.
--   classify = nil -- an item whose exact auction identity cannot be derived yet. Posting one
--                     under a guessed key is how the split-position bug happened, so it gets no
--                     position -- but it is returned in the second list, never lost.
--
-- `hasNoValue` is deliberately NOT one of them, though it used to be. That flag means the
-- VENDOR will not buy the item, which says nothing about the auction house -- and a great many
-- of the best things to sell have no vendor price at all. Reading it as a refusal quietly
-- deleted a seller's reagent inventory from this tab: a live bag dump had 322 Venomous
-- Combatant's Heraldry, 850 Gloom Dust and 38 Greater Eternal Essence, all hasNoValue, all
-- freely tradeable, all reported by the Sell tab as "not on hand" -- and, because the pricing
-- walk only quotes a position with stock, all of them priceless and profitless too. What the
-- auction house actually refuses is soulbound stock, which `isBound` above already catches.
function GC.BagStock.Scan(driver, bags)
  if type(driver) ~= "table" or type(driver.numSlots) ~= "function"
      or type(driver.itemInfo) ~= "function" or type(driver.classify) ~= "function" then
    return {}
  end
  local byKey, order, waitingByItem, waitingOrder = {}, {}, {}, {}
  for _, bag in ipairs(bags or {}) do
    local slots = driver.numSlots(bag) or 0
    for slot = 1, slots do
      local info = driver.itemInfo(bag, slot)
      local quantity = info and info.stackCount or nil
      if info and exactPositive(info.itemID) and exactPositive(quantity)
          and info.isBound ~= true then
        local positionKey, isCommodity, quoteKey, refused = driver.classify(info.itemID, info.hyperlink, bag, slot)
        if refused then -- luacheck: ignore 542
          -- The auction house says it cannot take this stack: not tradeable stock at all.
        elseif type(positionKey) ~= "string" or positionKey == "" then
          -- By item AND name: every caged pet is one item (Pet Cage), and two different pets
          -- waiting were one line named after the first.
          local waitKey = info.itemID .. "\1" .. tostring(info.itemName or "")
          local waiting = waitingByItem[waitKey]
          if not waiting then
            waiting = { itemID = info.itemID, itemName = info.itemName, quantity = 0 }
            waitingByItem[waitKey], waitingOrder[#waitingOrder + 1] = waiting, waitKey
          end
          waiting.quantity = add(waiting.quantity, quantity) or waiting.quantity
        else
          local entry = byKey[positionKey]
          if not entry then
            entry = { positionKey = positionKey, itemID = info.itemID, itemName = info.itemName,
              quantity = 0, isCommodity = isCommodity == true, quoteKey = quoteKey, stacks = {} }
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
  local waiting = {}
  table.sort(waitingOrder)
  for _, waitKey in ipairs(waitingOrder) do waiting[#waiting + 1] = waitingByItem[waitKey] end
  return result, waiting
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
