-- Player price caps: the alert-group ceilings the site ships through the companion
-- (GoldCap_AppRuns.caps / .groups, see Core/AppRuns.lua for the file's contract). This
-- module only holds and judges them; polling is KeyPoll's and the book pass's, verification
-- the drill queue's, buying onDialogPrimaryClick's. A cap is the player's own price, so a
-- capped item needs no realm reference to be watched.
local _, GC = ...
GC.Caps = {}

local caps, order, generatedAt = {}, {}, nil

local function num(v) return type(v) == "number" and v == v and v or nil end

function GC.Caps.Adopt()
  local raw = _G.GoldCap_AppRuns
  local next_caps, next_order = {}, {}
  local changed = false
  if type(raw) == "table" and (raw.v == 1 or raw.v == 2 or raw.v == 3) and type(raw.caps) == "table" then
    local groups = type(raw.groups) == "table" and raw.groups or {}
    for _, entry in ipairs(raw.caps) do
      if type(entry) == "table" then
        local i, c = num(entry.i), num(entry.c)
        if i and i > 0 and c and c > 0 and not next_caps[i] then
          local g = num(entry.g)
          next_caps[i] = {
            c = math.floor(c),
            l = math.max(0, math.floor(num(entry.l) or 0)),
            group = g and type(groups[g]) == "string" and groups[g] or nil,
            manual = entry.m == true,
          }
          next_order[#next_order + 1] = i
        end
      end
    end
    generatedAt = num(raw.generatedAt)
  else
    generatedAt = nil
  end
  -- Changed when any id came or went or any field moved; callers rebuild targets on true.
  if #next_order ~= #order then changed = true end
  if not changed then
    for id, cap in pairs(next_caps) do
      local old = caps[id]
      if not old or old.c ~= cap.c or old.l ~= cap.l or old.group ~= cap.group or old.manual ~= cap.manual then
        changed = true; break
      end
    end
  end
  caps, order = next_caps, next_order
  return changed
end

function GC.Caps.Count() return #order end
function GC.Caps.For(itemID) return caps[itemID] end
function GC.Caps.Targets()
  local out = {}
  for i = 1, #order do out[i] = order[i] end
  return out
end
function GC.Caps.GeneratedAt() return generatedAt end
-- KeyPoll fires on floor < trigger, so "at or under the cap" is trigger = cap + 1.
function GC.Caps.TriggerFor(itemID)
  local cap = caps[itemID]
  return cap and (cap.c + 1) or nil
end

-- Commodity caps off the book pass (Core/BookPass.lua's `book`: itemID -> { floor, qty, … }).
-- A capped commodity is excluded from the key poll's own target set on purpose
-- (UI/SniperFrame.lua's `_KeyTargetIds`) -- the book pass is what actually sees a commodity
-- floor, so this is the only place these hits come from. Pure, caps order, and silent about
-- anything the book pass has not (yet) reported: a realm item (isCommodity false), an over-cap
-- floor, and a capped commodity the book has no row for at all are all just not in the output.
function GC.Caps.BookHits(book, isCommodity)
  local hits = {}
  for i = 1, #order do
    local itemID = order[i]
    if isCommodity(itemID) then
      local cap = caps[itemID]
      local booked = book[itemID]
      if cap and booked and booked.floor and booked.floor <= cap.c then
        hits[#hits + 1] = { itemID = itemID, floor = booked.floor, estProfit = cap.c - booked.floor }
      end
    end
  end
  return hits
end

-- Addon task 5: judge a drilled lot/book against the player's own cap, not the market. Both
-- pure -- the drill-results handler (UI/SniperFrame.lua) runs one of these FIRST, ahead of the
-- ordinary SniperDecision.EvaluateRealm/Evaluate, whenever GC.Caps.For(itemID) is non-nil.

-- `lots` as itemLots() returns them: { auctionID, buyout, itemLevel, quantity }, already
-- excluding bid-only and the player's own lots. The cheapest COMPARABLE lot (itemLevel >=
-- cap.l) at or under cap.c, or nil when none qualifies. The shape returned is exactly what
-- onDialogPrimaryClick reads off row.decisionSnapshot for a realm item: status == "WATCH" and
-- a candidate carrying auctionID/buyout/quantity/itemLevel.
function GC.Caps.DecideRealm(cap, lots)
  local best, bestUnit
  for i = 1, #lots do
    local lot = lots[i]
    local itemLevel = lot.itemLevel or 0
    if itemLevel >= cap.l then
      local quantity = lot.quantity or 1
      local unit = math.floor(lot.buyout / quantity)
      if unit <= cap.c and (not best or unit < bestUnit) then
        best, bestUnit = lot, unit
      end
    end
  end
  if not best then return nil end
  return {
    status = "WATCH",
    cap = true,
    candidate = {
      auctionID = best.auctionID,
      buyout = best.buyout,
      quantity = best.quantity or 1,
      itemLevel = best.itemLevel,
    },
    unit = bestUnit,
  }
end

-- `levels` as the commodity book holds them (Core/BookPass.lua / driver.commodityBook):
-- { { unitPrice, quantity }, … } ascending, the player's own units already excluded. Sums
-- every level at or under cap.c into one buyable quantity and its stress-tested saving; nil
-- when there is nothing to buy, or when the saving does not clear the player's own
-- minimumProfitCopper floor (GC.db.settings.sniper.minimumProfitCopper). The shape returned is
-- exactly what onDialogPrimaryClick and armReady read for a commodity: status == "SAFE",
-- buyable == true, quantity.
function GC.Caps.DecideCommodity(cap, levels, minimumProfitCopper)
  local quantity, stressProfit, unit = 0, 0, nil
  for i = 1, #levels do
    local level = levels[i]
    if level.unitPrice <= cap.c then
      local levelQty = level.quantity or 0
      quantity = quantity + levelQty
      stressProfit = stressProfit + (cap.c - level.unitPrice) * levelQty
      if not unit then unit = level.unitPrice end
    end
  end
  if quantity == 0 then return nil end
  if stressProfit < (minimumProfitCopper or 0) then return nil end
  return {
    status = "SAFE",
    buyable = true,
    cap = true,
    quantity = quantity,
    stressProfit = stressProfit,
    unit = unit,
  }
end

-- Addon task 6: has THIS cap row already been rung/flashed? Pure module state, deliberately
-- separate from the caps/order tables above -- Adopt() rebuilds those wholesale on every
-- companion sync, and announcement memory must not reset with it, or the player would hear the
-- same lot ring again on the very next sync that changes nothing about it.
--
-- A realm lot IS a single resolved auction (buildCapDeal's own `auctionID`): once announced,
-- that exact auctionID never rings twice, however many drills/polls see it again -- it is the
-- SAME opportunity, not a new one. A commodity has no single lot to key on, only a book, so it
-- rings again only when the price actually IMPROVES on the last one announced for that item; a
-- re-poll of an unchanged (or worse) floor stays silent. `Forget` clears that memory for an item
-- whose cap decision just came back nil (the floor rose back above the cap) -- the next time it
-- dips under the cap again, even at the SAME price as before, that is a new opportunity, not a
-- repeat of the old one.
local announcedAuctions, announcedUnit = {}, {}

function GC.Caps.Announce(deal)
  if not deal or not deal.itemID then return false end
  if deal.isCommodity then
    local last = announcedUnit[deal.itemID]
    if last ~= nil and not (deal.unitPrice and deal.unitPrice < last) then return false end
    announcedUnit[deal.itemID] = deal.unitPrice
    return true
  end
  local auctionID = deal.auctionID
  if not auctionID or announcedAuctions[auctionID] then return false end
  announcedAuctions[auctionID] = true
  return true
end

function GC.Caps.Forget(itemID)
  announcedUnit[itemID] = nil
end

-- Final review I4: the whole memory, for the Auction House close (UI/SniperFrame.lua clears it
-- beside `seenHotDeals`, which is the same claim about the same session). Announcement memory
-- is a statement about ONE visit to the auction house -- "the player has already been told
-- about this lot" -- and a fresh visit is a fresh judgment of what is worth flagging. Kept
-- across the close, a lot announced hours ago stayed silenced for the rest of the login, and
-- the auction still sitting there at the player's own price was the one thing the new session
-- never mentioned.
function GC.Caps.ForgetAll()
  for k in pairs(announcedUnit) do announcedUnit[k] = nil end
  for k in pairs(announcedAuctions) do announcedAuctions[k] = nil end
end

-- Addon task 7: the requote guard. `deal` is a board deal (buildCapDeal's own `.cap`, the
-- copper amount, or nil for an uncapped item) and `unit` is the unit price a live server quote
-- just came back with (UI/SniperFrame.lua's OnCommodityPriceUpdated). True when there is no cap
-- to violate, or the quote is at or under it; false only when a cap exists and the quote broke
-- it -- the one case the player must never be allowed to confirm quietly.
function GC.Caps.QuoteOk(deal, unit)
  local cap = deal and deal.cap
  if not cap then return true end
  return unit <= cap
end
