local _, GC = ...

-- Buying a BUY list's vendor lines at a merchant, as data. A merchant sells in stacks -- `price`
-- buys `stack` units -- a purchase quantity is in units, and one BuyMerchantItem call asks for at
-- most the item's GetMerchantItemMaxStack units, as Blizzard's own merchant window does. Pure: the
-- caller reads the merchant, makes the call from the player's click and watches the bags.
GC.BuyVendor = {}

-- What this merchant sells for gold, per item: the cheapest offer when an item is listed twice. A
-- sold-out item (numAvailable 0), one that costs anything but gold (hasExtendedCost: currency or
-- items) or one the client says cannot be bought is not an offer.
function GC.BuyVendor.Offers(rows)
  local offers = {}
  for _, r in ipairs(rows or {}) do
    local price = tonumber(r.price) or 0
    if r.itemID and r.isPurchasable ~= false and not r.hasExtendedCost and price > 0
        and r.numAvailable ~= 0 then
      local stack = math.max(1, tonumber(r.stackCount) or 1)
      local unit = price / stack
      local seen = offers[r.itemID]
      if not seen or unit < seen.unit then
        offers[r.itemID] = { index = r.index, price = price, stack = stack, unit = unit,
          available = (tonumber(r.numAvailable) or -1) > 0 and r.numAvailable or nil,
          maxStack = math.max(1, tonumber(r.maxStack) or stack) }
      end
    end
  end
  return offers
end

-- What `qty` units of an offer cost. The BUY 2.0 probe (2026-10-01, both games): a purchase quantity
-- counts units, priced pro rata -- one of a 5-stack at 10c cost 2c -- so a line is bought to the
-- unit, never rounded up to the merchant's stack. Rounded up: a cost said is never under the cost
-- paid.
function GC.BuyVendor.CostOf(offer, qty)
  return math.ceil((qty or 0) * offer.price / offer.stack - 1e-9)
end

-- Per open line this merchant sells: how many units to buy -- the line's remaining need, held to the
-- merchant's stock and to the gold in hand -- what that costs, and the calls it takes: one call buys
-- at most the item's GetMerchantItemMaxStack units (one more fails with "internal bag error", the
-- probe), so 45 Coarse Thread at a maximum of 20 is 20, 20 and 5. `firstCost` is what the first
-- call costs. `short` says the line is not wholly bought by these calls.
function GC.BuyVendor.Plan(lines, offers, money)
  local out = {}
  for _, line in ipairs(lines or {}) do
    local offer = offers and offers[line.itemID]
    local want = line.buy or 0
    if offer and want > 0 then
      local qty = want
      if offer.available then qty = math.min(qty, offer.available * offer.stack) end
      if money then qty = math.min(qty, math.floor(money * offer.stack / offer.price + 1e-9)) end
      qty = math.max(0, qty)
      local calls, left = {}, qty
      while left > 0 do
        local n = math.min(offer.maxStack, left)
        calls[#calls + 1] = n
        left = left - n
      end
      out[#out + 1] = { itemID = line.itemID, index = offer.index, qty = qty,
        cost = GC.BuyVendor.CostOf(offer, qty), calls = calls,
        firstCost = calls[1] and GC.BuyVendor.CostOf(offer, calls[1]) or 0,
        short = qty < want, name = line.name }
    end
  end
  return out
end

-- A merchant purchase has no answer event: the bag count moving is the answer. What the press
-- bought, from the count it took before its call and the count seen now, at the merchant's own
-- price; never more than the press asked for (loot of the same item can land meanwhile). nil while
-- nothing has arrived.
function GC.BuyVendor.Settle(pending, countNow)
  if not pending then return nil end
  local got = (tonumber(countNow) or 0) - (pending.countBefore or 0)
  if got <= 0 then return nil end
  got = math.min(got, pending.qty or got)
  return { itemID = pending.itemID, qty = got, spent = math.floor(got * (pending.unit or 0) + 0.5) }
end
