local _, GC = ...

-- What the account already holds of an item, so the units a DEALS row offers to buy count it: the
-- limit is the demand cap less what is held, never under 0 (GC.SniperDecision.DemandCap's `held`,
-- and WoW: Forever's "Under market" rows, Core/ForeverDeals.lua). Caps keep their own limit.
--
-- Held is, of what the addon knows and nothing it would have to guess:
--   * this character's bags, bank, reagent bank, warband bank and mailbox (GC.CraftClient.CountOf,
--     the count the craft queue and the BUY tab's `have` stand on);
--   * what waits in the mailboxes of the account's other characters (GC.MailStock, retail only);
--   * the player's own lots still up on the auction house: the SELL tab's owned roster
--     (GC.SellState.ownedLots, which holds no sold lot and no lot on its way back), once it has
--     been read this session. GoldCapDB.ownedLots keeps rows after they sell, and is not read.
-- Another character's bags are not known to the addon and count as nothing.
GC.Holdings = GC.Holdings or {}
local H = GC.Holdings

local function units(n)
  return type(n) == "number" and n == n and n > 0 and n < math.huge and math.floor(n) or 0
end

--- The units the player's own listed lots hold, as { [itemID] = units }. `lots` as the SELL tab
--- keeps them: one row per lot still listed, `quantity` units each.
function H.Listed(lots)
  local out = {}
  for _, lot in ipairs(type(lots) == "table" and lots or {}) do
    if type(lot) == "table" and type(lot.itemID) == "number" then
      out[lot.itemID] = (out[lot.itemID] or 0) + units(lot.quantity)
    end
  end
  return out
end

--- What is held in all, from its parts: { carried, othersMail, listed }, each a count or nil.
function H.Total(parts)
  local total = 0
  for i = 1, 3 do total = total + units(parts[i]) end
  return total
end

--- The units a row may still offer once `held` is counted: `cap` less it, never under 0. A cap of
--- 0 or none is left as it is: that is no sales figure to plan by (one unit, Core/FullScan.lua),
--- not a cap that is full.
function H.Limit(cap, held)
  if type(cap) ~= "number" or cap <= 0 then return cap end
  return math.max(0, cap - units(held))
end

--- itemID -> units held, for a whole pass: the other characters' mail and the listed lots are read
--- once, the character's own count per item.
function H.Reader()
  local CC = GC.CraftClient
  local me = CC and CC.Char and CC.Char() or nil
  local others = GC.MailStock and GC.MailStock.OthersHold and GC.MailStock.OthersHold(me) or {}
  local state = GC.SellState
  local listed = H.Listed(state and state.ownedRead and state.ownedLots or nil)
  return function(itemID)
    local carried = CC and CC.CountOf and CC.CountOf(itemID, me) or 0
    return H.Total({ carried, others[itemID], listed[itemID] })
  end
end

--- What is held of one item now.
function H.Of(itemID)
  return H.Reader()(itemID)
end
