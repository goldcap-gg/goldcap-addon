local _, GC = ...

-- WoW: Forever: an item that is not a commodity, judged against what the same item -- or, for a
-- piece of gear with random suffixes, the same version -- sold for on this auction house over the
-- last week (goldcap.gg's GCF1 S and V sections, GC.Data.ForeverSales / ForeverVersionSales).
-- ClickUp 1an60dzy9nt. Pure: figures in, figures out.
--
-- The rules are the backtest's (wow-auction's scripts/analytics/forever-items-under-market/, prod
-- tape 2026-11-06..23, the 8 big houses, lots that stood an hour, resold at 90% of the median when
-- the item sold there again inside 48 h, else to a vendor). Per house a day:
--   * not gear at most 50% of its median, sold 35+ times a week: 360 lots, 76% resold, +17g;
--   * gear at most 40% of its version's median, 7+ a week, median under 10g: weapons +7g, armor
--     +16.6g, a quarter to a third of the buys losing;
--   * with no sales floor every rule lost (not gear, 50%, 7+ a week: -7g a day), and gear with a
--     median of 10g or more lost 1.2g a lot.
GC.ForeverItemMarket = {}
local M = GC.ForeverItemMarket

M.C = {
  NOT_GEAR = { share = 0.50, minPerWeek = 35 },
  GEAR = { share = 0.40, minPerWeek = 7, maxRef = 100000 },
  -- Where the resale is listed: under the median, so it sells in the 48 h the backtest gave it.
  EXIT_SHARE = 0.90,
  -- One 8-hour post's deposit on Forever, a share of the vendor price (Red Linen Bag: vendor 2s
  -- 50c, deposit 50c; owner's save, 2026-11-22). Counted once, as the post that does not sell.
  DEPOSIT_SHARE = 0.20,
  -- The most the player should hold of one item at once: half a day of its sales.
  HELD_DAYS = 0.5,
  WEEK_HOURS = 168,
  -- The lots a fold ladder is spread into (Units): the cheapest five levels hold more than enough.
  UNITS = 20,
}
local C = M.C

local function positive(n)
  return type(n) == "number" and n == n and n > 0
end

-- `sold`: GC.Data.ForeverSales or ForeverVersionSales. `gear`: a weapon or armor, measured per
-- version. nil when the item does not sell often enough, or its gear is too dear, to be a deal.
function M.Reference(sold, gear)
  if type(sold) ~= "table" or not positive(sold.median) or not positive(sold.hours) then return nil end
  local rule = gear and C.GEAR or C.NOT_GEAR
  local perWeek = (sold.sales or 0) * C.WEEK_HOURS / sold.hours
  if perWeek < rule.minPerWeek then return nil end
  if rule.maxRef and sold.median >= rule.maxRef then return nil end
  return { ref = sold.median, ceiling = math.floor(sold.median * rule.share), perWeek = perWeek,
    perDay = sold.perDay, gear = gear and true or false }
end

-- One 8-hour post's deposit for an item a vendor pays `vendor` for; 0 when it pays nothing.
function M.Deposit(vendor)
  return positive(vendor) and math.ceil(vendor * C.DEPOSIT_SHARE) or 0
end

-- The buy: of `units` (one version's lot prices, cheapest first, over the ceiling too), the lots
-- at or under the ceiling, as many as there is `room` for. Each resells at 90% of the median, or
-- one copper under the first lot the buy leaves on the book when that is lower: a lot under the
-- median the player had no room for still has to be beaten. `deposit` (M.Deposit) is paid once a
-- lot, as the post that does not sell. `firstProfit` is what one press makes (an item buy is one
-- lot); `profit` all of them. nil when nothing is to be bought.
function M.Plan(ref, units, deposit, room)
  if type(ref) ~= "table" or type(units) ~= "table" or not positive(room) then return nil end
  local take, cost = 0, 0
  for _, unit in ipairs(units) do
    if take >= room or unit > ref.ceiling then break end
    take = take + 1
    cost = cost + unit
  end
  if take == 0 then return nil end
  local exit = math.floor(ref.ref * C.EXIT_SHARE)
  local after = units[take + 1]
  if positive(after) and after - 1 < exit then exit = after - 1 end
  deposit = positive(deposit) and deposit or 0
  local each = exit - math.ceil(exit * 5 / 100) - deposit
  return { take = take, cost = cost, exit = exit, deposit = deposit, profit = each * take - cost,
    firstProfit = each - units[1], discount = 1 - units[1] / ref.ref }
end

function M.HeldCap(perDay)
  local n = positive(perDay) and math.floor(perDay * C.HELD_DAYS) or 0
  return n < 1 and 1 or n
end

-- A fold ladder ({ { unit, qty }, ... }) as one price per lot: every Forever item lot is one unit
-- (the owner's save, 2026-11-06).
function M.Units(ladder, limit)
  local out = {}
  limit = limit or C.UNITS
  for _, level in ipairs(type(ladder) == "table" and ladder or {}) do
    for _ = 1, level[2] or 0 do
      if #out >= limit then return out end
      out[#out + 1] = level[1]
    end
  end
  return out
end
