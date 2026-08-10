local _, GC = ...

GC.Book = {}

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
function GC.Book.Fill(levels, want)
  if not levels or not want or want <= 0 then return nil end

  local filled, total, levelsUsed = 0, 0, 0
  local competing

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
    levelsUsed = levelsUsed,
    exhausted = filled < want,
  }
end
