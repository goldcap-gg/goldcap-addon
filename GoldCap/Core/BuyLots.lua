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
-- `ver` is each row's version, the bonus key of its own link (Core/ForeverGear.lua's BonusKey):
-- what a line that names its versions judges the row by. nil without a link.
function GC.BuyLots.FromRows(rows)
  local bonusKey = GC.ForeverGear and GC.ForeverGear.BonusKey or nil
  local lots = {}
  for _, r in ipairs(rows or {}) do
    if type(r) == "table" and r.auctionID and type(r.buyoutAmount) == "number" and r.buyoutAmount > 0
        and not r.containsOwnerItem then
      local key = type(r.itemKey) == "table" and r.itemKey or {}
      lots[#lots + 1] = { auctionID = r.auctionID, buyout = r.buyoutAmount,
        count = math.max(1, tonumber(r.quantity) or 1),
        itemLevel = key.itemLevel or 0, itemSuffix = key.itemSuffix or 0,
        species = key.battlePetSpeciesID or 0, link = r.itemLink,
        ver = bonusKey and bonusKey(r.itemLink) or nil }
    end
  end
  table.sort(lots, function(a, b)
    if a.buyout ~= b.buyout then return a.buyout < b.buyout end
    return a.auctionID < b.auctionID
  end)
  return lots
end

-- The variants a browse by the item's name named (WoW: Forever, GC.Buy._StepByName), as lots: a
-- browse row says a variant's cheapest price, not its lots, so each is one lot at that price,
-- cheapest first. Never bid on -- a whole-item read only says which key to arm -- and replaced by
-- that variant's real lots once its own key is read (GC.BuyLots.Replace).
function GC.BuyLots.FromVariants(variants)
  local lots = {}
  for _, v in ipairs(variants or {}) do
    if type(v) == "table" and type(v.floor) == "number" and v.floor > 0 then
      lots[#lots + 1] = { auctionID = 0, buyout = v.floor, count = 1, itemLevel = v.itemLevel or 0,
        itemSuffix = v.itemSuffix or 0, species = v.battlePetSpeciesID or 0 }
    end
  end
  table.sort(lots, function(a, b) return a.buyout < b.buyout end)
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

-- A lot the line may take: at or above its item level, and of a version it buys. `version` is the
-- line's set of bonus keys (Core/BuyRun.lua), nil for a line that takes any version. With one, a
-- lot whose version is known must be one of them; a lot whose version is not known is taken only
-- as a browse variant not read yet (auctionID 0), which may be armed -- its own key's search then
-- reads each row's version -- but is never bid on. A real row with no link is never taken.
local function eligible(lot, minIlvl, version)
  if minIlvl and (lot.itemLevel or 0) < minIlvl then return false end
  if version == nil then return true end
  if lot.ver ~= nil then return version[lot.ver] == true end
  return lot.auctionID == 0
end

-- The dock's price lines: lots grouped by price, cheapest first, at most `max` groups. `version`,
-- here and below: the line's versions (eligible), nil for any.
function GC.BuyLots.Groups(lots, cap, minIlvl, max, version)
  max = max or GC.BuyLots.MAX_GROUPS
  local groups, byPrice = {}, {}
  for _, lot in ipairs(lots or {}) do
    if eligible(lot, minIlvl, version) then
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
function GC.BuyLots.Next(lots, cap, minIlvl, money, version)
  if not cap then return nil, "nocap" end
  local sawAny, sawUnder = false, false
  for _, lot in ipairs(lots or {}) do
    if eligible(lot, minIlvl, version) then
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
function GC.BuyLots.AsLevels(lots, minIlvl, version)
  local levels = {}
  for _, lot in ipairs(lots or {}) do
    if eligible(lot, minIlvl, version) then levels[#levels + 1] = { unit = lot.buyout, qty = lot.count } end
  end
  return levels
end
