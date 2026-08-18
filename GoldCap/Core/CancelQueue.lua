local _, GC = ...

-- The seller's cancel queue: an ORDER over the player's own live lots worth cancelling right
-- now, plus a named reason for every position holding an above-market lot that was held back.
-- See docs/superpowers/specs/2026-08-17-post-queue-design.md Part 3 for the approved design.
--
-- Why this exists: `C_AuctionHouse.CancelAuction` is `#hwevent` -- one hardware click per lot
-- is the ceiling -- and unlike posting, every confirmed click here FORFEITS a real deposit. So
-- this module is even stricter than PostQueue about not having opinions of its own:
--
-- ***THIS MODULE IS NOT AN AUTHORITY ON WHETHER CANCELLING IS WISE.*** It only reads the
-- judgments SellPositions.decoratePosition already publishes on the position:
--   * `facts.underpriced` / `underpricedUnit` -- the alarm ("money leaving silently"; see the
--     Arcane Crystal postmortem in decoratePosition). That lot is queued URGENT, first
--     regardless of value and independently of the repost advice -- a lot selling below value
--     is worth pulling even when relisting advice says the market is slow.
--   * `recommendation.action == "repost"` (Flips.RepostAdvice: relisting beats holding) --
--     and then ONLY lots priced ABOVE `freshMarketUnit`. A lot at or below the fresh quote is
--     competitive: cancelling it burns a deposit for nothing, so it is never queued, no matter
--     what the advice says about the position as a whole.
-- At click time nothing from an entry is trusted anyway: the control hands the click to
-- UI/SellFrame.lua's onRepostClick, whose pin validation re-derives the plan from live owned
-- lots and a fresh quote, with its own two-click arm and its own timeout. Copy, don't compute.
GC.CancelQueue = {}

local MAX_EXACT = 9007199254740991

local function exact(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

local function positive(value) return exact(value) and value > 0 end

local function mulExact(left, right)
  if not exact(left) or not exact(right) then return nil end
  if left ~= 0 and right > math.floor(MAX_EXACT / left) then return nil end
  return left * right
end

-- Precedence when more than one reason could apply (first match wins), same family logic as
-- PostQueue's evaluate: identity first (nothing else about the position is trustworthy), then
-- the missing live market, then the advice. `no_advice` is deliberately distinct from
-- `advised_hold`: "no cost basis, so nobody has judged this" is a different fact from "it was
-- judged and the judgment is hold", and a seller deciding whether to set a cost needs to know
-- which one they are looking at.
local function positionReason(position)
  if position.unresolved or position.protectedAction == false or position.invalid then
    return "unresolved_identity"
  end
  if type(position.positionKey) ~= "string" or position.positionKey == "" or not positive(position.itemID) then
    return "unresolved_identity"
  end
  if not positive(position.freshMarketUnit) then
    return "no_fresh_price"
  end
  return nil
end

function GC.CancelQueue.Build(positions)
  local entries, skipped = {}, {}
  for _, position in ipairs(positions or {}) do
    local lots = position.ownedLots or {}
    if #lots > 0 then
      local reason = positionReason(position)
      local included, aboveMarket, overflowed = {}, 0, false
      if not reason then
        local fresh = position.freshMarketUnit
        local advice = type(position.recommendation) == "table" and position.recommendation.action or nil
        local urgentUnit = position.facts and position.facts.underpriced and position.underpricedUnit or nil
        for _, lot in ipairs(lots) do
          if positive(lot.auctionID) and positive(lot.quantity) and positive(lot.unitPrice) then
            if lot.unitPrice > fresh then aboveMarket = aboveMarket + 1 end
            local urgent = urgentUnit ~= nil and lot.unitPrice == urgentUnit
            local advised = advice == "repost" and lot.unitPrice > fresh
            if urgent or advised then
              local value = mulExact(lot.quantity, fresh)
              if not value then
                overflowed = true
              else
                included[#included + 1] = {
                  positionKey = position.positionKey, scopeKey = position.scopeKey,
                  itemID = position.itemID, itemName = position.itemName,
                  auctionID = lot.auctionID, quantity = lot.quantity,
                  listedUnit = lot.unitPrice, value = value, urgent = urgent or nil,
                }
              end
            end
          end
        end
        if overflowed then
          -- A value that cannot be stated exactly poisons the ordering for the whole position;
          -- same "cannot soundly state the numbers" family PostQueue files under this reason.
          reason, included = "unresolved_identity", {}
        elseif #included == 0 and aboveMarket > 0 then
          reason = advice == "hold" and "advised_hold" or "no_advice"
        end
      end
      if reason then
        skipped[#skipped + 1] = { positionKey = position.positionKey, itemID = position.itemID,
          itemName = position.itemName, reason = reason }
      end
      for _, entry in ipairs(included) do entries[#entries + 1] = entry end
    end
  end
  table.sort(entries, function(a, b)
    local ua, ub = a.urgent or false, b.urgent or false
    if ua ~= ub then return ua end
    if a.value ~= b.value then return a.value > b.value end
    if a.positionKey ~= b.positionKey then return a.positionKey < b.positionKey end
    return a.auctionID < b.auctionID
  end)
  return entries, skipped
end

-- A new array minus that lot, so the UI never mutates a list it is rendering from -- the same
-- contract as PostQueue.Without, keyed by auctionID because that is a lot's identity.
function GC.CancelQueue.Without(entries, auctionID)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    if entry.auctionID ~= auctionID then out[#out + 1] = entry end
  end
  return out
end
