local _, GC = ...

GC.Book = {}

local function exact(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value) and value >= 0
end

-- `levels` is the visible order book ascending by unitPrice -- for a commodity, one entry per
-- price level (C_AuctionHouse.GetCommoditySearchResultInfo). `want` is how many units the
-- player is about to buy. This walks the book bottom-up exactly the way a commodity purchase
-- fills, which is the part the sniper was blind to: it only ever read level 1, so a deal
-- quoted at the cheapest level could cost several times that once the level ran out.
--
-- `competing` is the cheapest unit price STILL listed once `want` units are taken -- the price
-- a reseller has to undercut, and the only live evidence this addon has about what an item is
-- actually worth. A fill that stops mid-level competes with that same level (units remain
-- there); a fill that consumes a level exactly competes with the next one. nil means the walk
-- emptied the visible book, so there is no live anchor and callers fall back to the imported
-- market value.
-- Units listed at or below `price` -- the stock that has to sell (or be undercut) before a
-- reseller exiting AT `price` gets a turn. SniperDecision's velocity release compares this
-- against the item's daily sales to decide whether a leftover cheap wall is real competition
-- or just the next hour's turnover. Same-priced units are counted (commodities at one price
-- fill in listing order, and the units already there are ahead of yours), which errs toward
-- the larger, more conservative number.
function GC.Book.UnitsAtOrBelow(levels, price)
  if not levels or not price or price <= 0 then return 0 end
  local units = 0
  for i = 1, #levels do
    local level = levels[i]
    if (level.quantity or 0) > 0 and level.unitPrice and level.unitPrice <= price then
      units = units + level.quantity
    end
  end
  return units
end
function GC.Book.Fill(levels, want)
  if not levels or not want or want <= 0 then return nil end

  local filled, total, levelsUsed = 0, 0, 0
  local competing
  local partialLevel = false

  for i = 1, #levels do
    local level = levels[i]
    local available = level.quantity or 0
    if available > 0 then
      local take = want - filled
      if take > available then take = available end

      filled = filled + take
      total = total + take * level.unitPrice
      levelsUsed = levelsUsed + 1

      if filled >= want then
        if take < available then
          competing = level.unitPrice -- units left over at this level
          -- The competing ask is the remainder of a level THIS fill bought from, not an
          -- untouched seller above it -- the distinction SniperDecision's velocity release
          -- turns on, so it is a fact for Fill to report, not for callers to reconstruct.
          partialLevel = true
        else
          -- This level is gone; the next one with stock is what remains on the market.
          for j = i + 1, #levels do
            if (levels[j].quantity or 0) > 0 then
              competing = levels[j].unitPrice
              break
            end
          end
        end
        break
      end
    end
  end

  if filled <= 0 then return nil end

  return {
    filled = filled,
    total = total,
    unit = math.floor(total / filled),
    competing = competing,
    partialLevel = partialLevel,
    levelsUsed = levelsUsed,
    exhausted = filled < want,
  }
end

-- One summary of a walked book for the live-observation writer: the TRUE
-- minimum (quoteResolved's own `unit` is the competing-not-own price, not
-- the floor), how many result rows the client returned (distinct listings
-- for item searches, price levels for commodities), and the shelf total.
function GC.Book.Summarize(levels)
  if type(levels) ~= "table" then return nil end
  local minUnit, listings, totalQty
  for _, level in ipairs(levels) do
    if type(level) == "table" and exact(level.unitPrice) and level.unitPrice > 0
        and exact(level.quantity) and level.quantity > 0 then
      minUnit = (minUnit == nil or level.unitPrice < minUnit) and level.unitPrice or minUnit
      listings = (listings or 0) + 1
      totalQty = (totalQty or 0) + level.quantity
    end
  end
  if not minUnit then return nil end
  return { minUnit = minUnit, listings = listings, totalQty = totalQty }
end
