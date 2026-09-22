-- Player price caps: the alert-group ceilings the site ships through the companion
-- (GoldCap_AppRuns.caps / .groups, see Core/AppRuns.lua for the file's contract). This
-- module only holds and judges them; polling is KeyPoll's and the book pass's, verification
-- the drill queue's, buying onDialogPrimaryClick's. A cap is the player's own price, so a
-- capped item needs no realm reference to be watched.
local _, GC = ...
GC.Caps = {}

local caps, order, generatedAt = {}, {}, nil

-- Final review M9: `v == v` rejects a NaN and nothing else, so an infinity walked straight
-- through -- and an infinite `c` is a cap no price on earth can break (every lot qualifies,
-- every server quote passes GC.Caps.QuoteOk), while an infinite `l` is not an item level at
-- all. Neither is a number the site can have meant; both are dropped with the rest of the junk.
local function num(v)
  if type(v) ~= "number" or v ~= v then return nil end
  if v == math.huge or v == -math.huge then return nil end
  return v
end

-- Spec §5: a cap with an item-level floor cannot be judged from a poll answer at all -- the
-- aggregate row SearchForItemKeys returns says nothing about item level, so every one of them
-- costs a drill. At most this many of them get a polling slot; the rest stay real caps (For()
-- answers for them, and a hit that reaches the addon another way is still judged against them),
-- they simply are not polled for. A cap with no level floor is decided off the poll's own row
-- and is never limited.
local TARGET_GATED_MAX = 200

function GC.Caps.Adopt()
  local raw = _G.GoldCap_AppRuns
  local next_caps, next_order = {}, {}
  local changed = false
  if type(raw) == "table" and (raw.v == 1 or raw.v == 2 or raw.v == 3) and type(raw.caps) == "table" then
    local groups = type(raw.groups) == "table" and raw.groups or {}
    for _, entry in ipairs(raw.caps) do
      if type(entry) == "table" then
        local i, c = num(entry.i), num(entry.c)
        -- An ABSENT `l` means "no item-level floor" and is legitimate (a commodity cap has
        -- none). An `l` that is present and unusable is a different thing, and it may not fall
        -- back to 0: that would quietly widen the player's own "1500g for ilvl >= 610" into
        -- "1500g for anything" and green-light the junk variant at the price meant for the good
        -- one. It drops the entry, exactly as an unusable price does.
        local l = entry.l == nil and 0 or num(entry.l)
        if i and i > 0 and c and c > 0 and l and not next_caps[i] then
          local g = num(entry.g)
          next_caps[i] = {
            c = math.floor(c),
            l = math.max(0, math.floor(l)),
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
-- Item ids in DELIVERY order, which is the site's own order and nothing more. Final review M1:
-- position here is not priority -- Core/KeyPoll.lua's SetTargets sorts what it is handed, so
-- "caps first" was a claim this list could not keep. What a cap really bypasses is the realm
-- VALUE requirement (UI/SniperFrame.lua's _KeyTargetIds): the cap is the player's own price, so
-- a capped item is polled with no market reference of any kind, which nothing else is.
function GC.Caps.Targets()
  local out, gated = {}, 0
  for i = 1, #order do
    local itemID = order[i]
    local cap = caps[itemID]
    if cap and cap.l > 0 then
      if gated < TARGET_GATED_MAX then
        gated = gated + 1
        out[#out + 1] = itemID
      end
    else
      out[#out + 1] = itemID
    end
  end
  return out
end
function GC.Caps.GeneratedAt() return generatedAt end
-- KeyPoll fires on floor < trigger, so "at or under the cap" is trigger = cap + 1.
function GC.Caps.TriggerFor(itemID)
  local cap = caps[itemID]
  return cap and (cap.c + 1) or nil
end

-- Final review I2: the last floor this reported per item. The book pass folds a book that
-- mostly does not move, so without a ratchet every capped commodity sitting under its cap was
-- reported again on EVERY completed pass -- a drill-queue push per pass, per item, for a price
-- nothing had happened to. The key poll's side has always ratcheted (Core/KeyPoll.lua's Fold:
-- a hit is a floor that is also NEWS); this is the same rule for the book-pass side. Cleared by
-- Forget/ForgetAll below, together with the ring's memory, for the same reasons.
local emittedFloor = {}

-- Commodity caps off the book pass (Core/BookPass.lua's `book`: itemID -> { floor, qty, … }).
-- A capped commodity is excluded from the key poll's own target set on purpose
-- (UI/SniperFrame.lua's `_KeyTargetIds`) -- the book pass is what actually sees a commodity
-- floor, so this is the only place these hits come from. Caps order, and silent about anything
-- the book pass has not (yet) reported: a realm item (isCommodity false), an over-cap floor,
-- and a capped commodity the book has no row for at all are all just not in the output.
function GC.Caps.BookHits(book, isCommodity)
  local hits = {}
  for i = 1, #order do
    local itemID = order[i]
    if isCommodity(itemID) then
      local cap = caps[itemID]
      local booked = book[itemID]
      if cap and booked and booked.floor and booked.floor <= cap.c
          and emittedFloor[itemID] ~= booked.floor then
        emittedFloor[itemID] = booked.floor
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
-- a candidate carrying auctionID/buyout/quantity/itemLevel -- plus what that lot costs, in the
-- same three fields GC.SniperDecision.EvaluateRealm's result carries (`quantity`, `entryTotal`,
-- `entryUnitDisplay`), and the player's own price (`capUnit`). The dialog prices UNIT and TOTAL
-- from those and the check panel shows them beside the cap; without them the one lot whose price
-- is known to the copper read "—" and "Can't price this". For an item auction the whole buyout
-- is exactly what PlaceBid pays.
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
  local quantity = best.quantity or 1
  return {
    status = "WATCH",
    cap = true,
    candidate = {
      auctionID = best.auctionID,
      buyout = best.buyout,
      quantity = quantity,
      itemLevel = best.itemLevel,
    },
    unit = bestUnit,
    quantity = quantity,
    entryTotal = best.buyout,
    entryUnitDisplay = bestUnit,
    capUnit = cap.c,
  }
end

-- `levels` as the commodity book holds them (Core/BookPass.lua / driver.commodityBook):
-- { { unitPrice, quantity }, … }, the player's own units already excluded. Buys the units at or
-- under cap.c, CHEAPEST FIRST, inside `limits` -- the player's own Max units per buy and wallet
-- limit, as GC.SniperDecision.BuyLimits works them out -- and says exactly what those units cost
-- (`entryTotal`, `entryUnitDisplay`), the figures every stamp, the wallet check and the requote
-- guard price a buy by. The whole book under the cap used to go into one purchase.
--
-- Nothing market-derived bounds it -- no share of daily sales, no profit floor. A cap is the
-- player's own rule and may have no market data at all, and "at or under your price" is the
-- whole promise, on the site and on the realm side (DecideRealm has no floor either): a floor
-- exactly at the cap qualifies. nil when nothing qualifies, when not one unit fits the wallet
-- limit, and without `limits` at all (fail closed). The shape returned is exactly what
-- onDialogPrimaryClick and armReady read for a commodity: status == "SAFE", buyable == true,
-- quantity. It carries no stressProfit: nothing here measured a resale, and a "profit" figure
-- made of the saving under the cap would be one the panel invented.
function GC.Caps.DecideCommodity(cap, levels, limits)
  if type(limits) ~= "table" then return nil end
  local qualifying = {}
  for i = 1, #levels do
    local level = levels[i]
    if level.unitPrice > 0 and level.unitPrice <= cap.c and (level.quantity or 0) > 0 then
      qualifying[#qualifying + 1] = level
    end
  end
  -- Final review M3: the CHEAPEST levels, not the first ones walked. `unit` is what the board
  -- row, the ring's own dedup and the dialog header all show as the price on offer, and a buy
  -- the limits cut short has to be the cheapest part of what is on offer. The book arrives
  -- ascending today, which made both answers right by luck; a client that ever answers unsorted
  -- would have put the wrong price on screen, and bought the wrong units, silently. Sorted on a
  -- copy -- the caller's book is never reordered.
  table.sort(qualifying, function(a, b) return a.unitPrice < b.unitPrice end)
  local quantity, total = 0, 0
  for i = 1, #qualifying do
    local level = qualifying[i]
    local take = math.min(level.quantity, limits.maxQuantity - quantity,
      math.floor((limits.budget - total) / level.unitPrice))
    if take > 0 then
      quantity, total = quantity + take, total + take * level.unitPrice
    end
    -- A limit bit inside this level: every level after it is dearer, so nothing more fits.
    if take < level.quantity then break end
  end
  if quantity == 0 then return nil end
  return {
    status = "SAFE",
    buyable = true,
    cap = true,
    quantity = quantity,
    entryTotal = total,
    entryUnitDisplay = math.floor(total / quantity),
    unit = qualifying[1].unitPrice,
    capUnit = cap.c,
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
  -- Final review I2: the book-pass ratchet goes with it. The two memories answer the same
  -- question one step apart -- "has the player already been shown this price?" -- so a floor
  -- that climbed back above the cap has to clear both, or the next dip to the SAME price is
  -- announced but never re-drilled (or the other way round).
  emittedFloor[itemID] = nil
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
  for k in pairs(emittedFloor) do emittedFloor[k] = nil end
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
