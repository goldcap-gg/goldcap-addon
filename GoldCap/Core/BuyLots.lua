local _, GC = ...

-- A lot line (gear, and anything else the client will not sell as a commodity) as data. The
-- client's item search answers with rows; a row is N identical auctions, its `buyoutAmount` is what
-- ONE of them costs and PlaceBid buys one -- dividing the buyout by the row's quantity sold bags 150
-- times too cheap once (docs/addon/AGENTS.md). Pure: UI/BuyFrame.lua reads the client and draws.
GC.BuyLots = {}

GC.BuyLots.MAX_GROUPS = 3

-- The rows a search answered, as lots, cheapest first. Each lot keeps its own item key's fields
-- (level, suffix, pet species): a gear line is bid on under its lot's exact key (UI/BuyFrame.lua). The player's own lot is never one (it cannot
-- be bought, and offering it would sell the player their own auction), nor is a row with no buyout
-- (a bid-only auction).
function GC.BuyLots.FromRows(rows)
  local lots = {}
  for _, r in ipairs(rows or {}) do
    if type(r) == "table" and r.auctionID and type(r.buyoutAmount) == "number" and r.buyoutAmount > 0
        and not r.containsOwnerItem then
      local key = type(r.itemKey) == "table" and r.itemKey or {}
      lots[#lots + 1] = { auctionID = r.auctionID, buyout = r.buyoutAmount,
        count = math.max(1, tonumber(r.quantity) or 1),
        itemLevel = key.itemLevel or 0, itemSuffix = key.itemSuffix or 0,
        species = key.battlePetSpeciesID or 0, link = r.itemLink }
    end
  end
  table.sort(lots, function(a, b)
    if a.buyout ~= b.buyout then return a.buyout < b.buyout end
    return a.auctionID < b.auctionID
  end)
  return lots
end

-- The lots of every variant `all` holds, with one variant's lots -- those of `key`, read again by
-- its own search -- swapped for `fresh`: after a purchase only the bought lot's variant is read
-- again, and the others still stand as the whole-item read saw them.
function GC.BuyLots.Replace(all, fresh, key)
  local lots = {}
  key = key or {}
  for _, lot in ipairs(all or {}) do
    if lot.itemLevel ~= (key.itemLevel or 0) or lot.itemSuffix ~= (key.itemSuffix or 0)
        or (lot.species or 0) ~= (key.battlePetSpeciesID or 0) then
      lots[#lots + 1] = lot
    end
  end
  for _, lot in ipairs(fresh or {}) do lots[#lots + 1] = lot end
  table.sort(lots, function(a, b)
    if a.buyout ~= b.buyout then return a.buyout < b.buyout end
    return a.auctionID < b.auctionID
  end)
  return lots
end

local function eligible(lot, minIlvl)
  return not minIlvl or (lot.itemLevel or 0) >= minIlvl
end

-- The dock's price lines: lots grouped by price, cheapest first, at most `max` groups.
function GC.BuyLots.Groups(lots, cap, minIlvl, max)
  max = max or GC.BuyLots.MAX_GROUPS
  local groups, byPrice = {}, {}
  for _, lot in ipairs(lots or {}) do
    if eligible(lot, minIlvl) then
      local group = byPrice[lot.buyout]
      if not group then
        if #groups >= max then break end
        group = { buyout = lot.buyout, count = 0, over = cap ~= nil and lot.buyout > cap }
        byPrice[lot.buyout] = group
        groups[#groups + 1] = group
      end
      group.count = group.count + lot.count
    end
  end
  return groups
end

-- The one lot the dock's next press buys: the cheapest at or under the cap, at or above the line's
-- item level, that the wallet can pay. Without a cap nothing is offered at all: a bid has no quote
-- step to catch a mistake, so the cap is the only guard there is.
function GC.BuyLots.Next(lots, cap, minIlvl, money)
  if not cap then return nil, "nocap" end
  local sawAny, sawUnder = false, false
  for _, lot in ipairs(lots or {}) do
    if eligible(lot, minIlvl) then
      sawAny = true
      if lot.buyout > cap then break end
      sawUnder = true
      if money == nil or lot.buyout <= money then return lot end
    end
  end
  if sawUnder then return nil, "wallet" end
  if sawAny then return nil, "over" end
  return nil, "none"
end

-- The same lots as the price ladder every other BUY line has, so the tooltip, the row status and the
-- cap raise read a lot line exactly as they read a commodity.
function GC.BuyLots.AsLevels(lots, minIlvl)
  local levels = {}
  for _, lot in ipairs(lots or {}) do
    if eligible(lot, minIlvl) then levels[#levels + 1] = { unit = lot.buyout, qty = lot.count } end
  end
  return levels
end
