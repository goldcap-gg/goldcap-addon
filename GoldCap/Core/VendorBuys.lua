local _, GC = ...

-- Every purchase from a merchant, as a cost. A craft is costed from what the player paid, and a
-- merchant's reagents -- thread, flour, vials -- were paid for at the merchant. Until now only the
-- BUY tab's own vendor button booked such a purchase; one made by clicking the merchant's window
-- left nothing behind, so a craft that used it could never be costed.
--
-- This watches BuyMerchantItem and PickupMerchantItem (the plain left click, which buys when the
-- item is dropped into a bag) with post-hooks, which observes a call and cannot make one (the
-- one call the addon makes stays in UI/BuyVendorPanel.lua's click handler, and the same hook sees
-- that one too -- so there is exactly one place a vendor purchase is booked). A merchant purchase
-- has no answer event: the bag count moving is the answer (GC.BuyVendor.Settle), so a call only
-- becomes a lot once the items have arrived, and never for more than the call asked for.
--
-- Stacks: a merchant's `price` buys `stackCount` units, and the quantity of a call counts units,
-- priced pro rata (the 2026-10-01 probe, both games; see Core/BuyVendor.lua). A call with no
-- quantity buys one stack. The price per unit is therefore price / stackCount, and what a lot
-- records is what GC.BuyVendor.CostOf says the units cost.
--
-- Pure by construction like Core/CraftCapture.lua: the client is a driver --
--   offerAt(index) -> { itemID, price, stack } or nil (not for gold, not purchasable, ...),
--   countOf(itemID) -> bags count,
--   record({ itemID, qty, spent, at, runCode }) -> files the lot.
GC.VendorBuys = {}
local V = GC.VendorBuys

-- A call the bags never showed a result for (the merchant refused it, or it was a repeat of one
-- already settled) is given up after this long.
V.EXPIRE_SECONDS = 15
-- A purchase made by picking the item up from the merchant window completes when the player drops
-- it into a bag. From the moment the cursor lets go of it, the bags have this long to show it: a
-- pickup the player put back must not claim loot of the same item that lands a moment later.
V.DROP_SECONDS = 5

local driver
local pending = {}

function V.SetDriver(value)
  driver = type(value) == "table" and value or nil
  pending = {}
  V.runCode = nil
end

-- The BUY tab's vendor button names the list it buys for just before its call; the hook below
-- reads it once. Everything else is a purchase on no list.
function V.Tag(runCode)
  V.runCode = runCode
end

local function isPositiveInteger(n)
  return type(n) == "number" and n == math.floor(n) and n > 0 and n < 2 ^ 53
end

--- A BuyMerchantItem call just made (the post-hook). `quantity` is in units; nil is one stack.
function V.OnBuy(index, quantity, now)
  -- The tag belongs to the call it was set for, whatever becomes of it.
  local runCode = V.runCode
  V.runCode = nil
  if not driver or type(now) ~= "number" then return end
  local offer = driver.offerAt(index)
  if type(offer) ~= "table" or not isPositiveInteger(offer.itemID) then return end
  local units = quantity == nil and offer.stack or quantity
  if not isPositiveInteger(units) then return end
  local cost = GC.BuyVendor.CostOf(offer, units)
  if not isPositiveInteger(cost) then return end

  local seen = pending[offer.itemID]
  if seen then
    -- A second call before the first one's items arrived: one pool, the first call's count.
    seen.qty, seen.cost, seen.at = seen.qty + units, seen.cost + cost, now
    seen.runCode = seen.runCode or runCode
  else
    pending[offer.itemID] = { itemID = offer.itemID, qty = units, cost = cost, at = now,
      countBefore = driver.countOf(offer.itemID), runCode = runCode }
  end
end

--- PickupMerchantItem just returned (the post-hook): a plain left click on a merchant's item takes
-- it onto the cursor, and the purchase is made when the player drops it into a bag. Noted as a
-- purchase of one stack that is held until the cursor lets go of it; the bags then settle it
-- exactly like a BuyMerchantItem call. Buyback (another tab, another call) and the drop-to-sell
-- call PickupMerchantItem(0) never reach the booking: the cursor holds nothing of the merchant's
-- then, or the index is not a merchant row.
function V.OnPickup(index, now)
  if not driver or type(now) ~= "number" or not isPositiveInteger(index) then return end
  if not driver.cursorHoldsMerchant() then return end
  local offer = driver.offerAt(index)
  if type(offer) ~= "table" or not isPositiveInteger(offer.itemID) then return end
  local units = offer.stack
  if not isPositiveInteger(units) then return end
  local cost = GC.BuyVendor.CostOf(offer, units)
  if not isPositiveInteger(cost) then return end
  local seen = pending[offer.itemID]
  if seen then
    seen.qty, seen.cost, seen.at, seen.held, seen.window = seen.qty + units, seen.cost + cost, now, true, nil
  else
    pending[offer.itemID] = { itemID = offer.itemID, qty = units, cost = cost, at = now,
      countBefore = driver.countOf(offer.itemID), held = true }
  end
end

--- The cursor changed (CURSOR_CHANGED): a held pickup the cursor no longer carries was dropped, or
-- put back; either way the bags now have V.DROP_SECONDS to show it.
function V.OnCursorChanged(now)
  if not driver or type(now) ~= "number" or next(pending) == nil or driver.cursorHoldsMerchant() then return end
  for _, p in pairs(pending) do
    if p.held then p.held, p.at, p.window = nil, now, V.DROP_SECONDS end
  end
end

--- The bags changed (BAG_UPDATE_DELAYED): file what has arrived of each call, give up on the old.
function V.OnBagsChanged(now)
  if not driver then return end
  local carrying = driver.cursorHoldsMerchant()
  for itemID, p in pairs(pending) do
    if p.held and carrying then
      p.at = now
    else
      local got = GC.BuyVendor.Settle({ itemID = itemID, qty = p.qty, unit = p.cost / p.qty,
        countBefore = p.countBefore }, driver.countOf(itemID))
      if got then
        local spent = got.qty >= p.qty and p.cost or math.ceil(got.qty * p.cost / p.qty - 1e-9)
        driver.record({ itemID = itemID, qty = got.qty, spent = spent, at = now, runCode = p.runCode })
        p.qty, p.cost, p.countBefore = p.qty - got.qty, p.cost - spent, p.countBefore + got.qty
      end
      if p.qty <= 0 or now - p.at > (p.window or V.EXPIRE_SECONDS) then pending[itemID] = nil end
    end
  end
end

--- How many calls are still waiting for their items (diagnostics and specs).
function V.Pending()
  local n = 0
  for _ in pairs(pending) do n = n + 1 end
  return n
end

-- One merchant row, as GC.BuyVendor.Offers reads it. The one place the merchant is read, for this
-- module's hook and for the vendor panel beside the window.
function V.MerchantRow(index)
  if not (C_MerchantFrame and C_MerchantFrame.GetItemInfo) then return nil end
  local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
  if not ok or type(info) ~= "table" then return nil end
  return { index = index, itemID = GetMerchantItemID and GetMerchantItemID(index) or nil,
    price = info.price, stackCount = info.stackCount, numAvailable = info.numAvailable,
    isPurchasable = info.isPurchasable, hasExtendedCost = info.hasExtendedCost,
    maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(index) or nil }
end

-- Wires the module to the client: the post-hook and the driver. Called once, when the database is
-- ready. A client without the hook function or the call (nothing does today) simply books nothing.
function V.Install()
  V.SetDriver({
    offerAt = function(index)
      local row = V.MerchantRow(index)
      if not row then return nil end
      local offer = GC.BuyVendor.Offers({ row })[row.itemID]
      if not offer then return nil end
      offer.itemID = row.itemID
      return offer
    end,
    -- GetCursorInfo's first return is "merchant" while the cursor carries an item taken from the
    -- merchant window (Blizzard's ContainerFrame.lua tests the same value on the drop).
    cursorHoldsMerchant = function()
      if type(_G.GetCursorInfo) ~= "function" then return false end
      local ok, kind = pcall(_G.GetCursorInfo)
      return ok and kind == "merchant"
    end,
    countOf = function(itemID)
      if not (C_Item and C_Item.GetItemCount) then return 0 end
      local ok, n = pcall(C_Item.GetItemCount, itemID)
      return ok and tonumber(n) or 0
    end,
    record = function(entry)
      if not (GC.Acquisitions and GC.Acquisitions.Record) then return end
      local context = GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
      local known = GC.db and GC.db.commodityByItem or {}
      local stack
      if C_Item and C_Item.GetItemMaxStackSizeByID then
        local ok, n = pcall(C_Item.GetItemMaxStackSizeByID, entry.itemID)
        stack = ok and tonumber(n) or nil
      end
      -- A stackable item sells at the auction house as a commodity, which keys itself from the id.
      -- Anything else (gear) needs its link's bonus ids, which a merchant row does not carry: it is
      -- filed keyless and keyed the next time the auction house tells us.
      local commodity = known[entry.itemID] == true or (known[entry.itemID] == nil and (stack or 1) > 1)
      V.seq = (V.seq or 0) + 1
      local name
      if C_Item and C_Item.GetItemNameByID then
        local ok, value = pcall(C_Item.GetItemNameByID, entry.itemID)
        name = ok and type(value) == "string" and value or nil
      end
      GC.Acquisitions.Record({
        source = "vendor", itemID = entry.itemID, itemName = name, quantity = entry.qty,
        total = entry.spent, acquiredAt = entry.at, runCode = entry.runCode,
        positionKey = commodity and GC.Acquisitions.PositionKey(entry.itemID, nil, true) or nil,
        character = context and context.char or nil, region = context and context.region or nil,
        evidenceKey = ("vendor:%d:%s:%d"):format(entry.itemID, GC.Util.IntText(entry.at), V.seq),
      })
    end,
  })
  if type(_G.hooksecurefunc) == "function" and type(_G.BuyMerchantItem) == "function" then
    hooksecurefunc("BuyMerchantItem", function(index, quantity)
      pcall(V.OnBuy, index, quantity, time())
    end)
  end
  -- A left click on a merchant item is PickupMerchantItem, not BuyMerchantItem (Blizzard's
  -- MerchantFrame.lua, both games).
  if type(_G.hooksecurefunc) == "function" and type(_G.PickupMerchantItem) == "function" then
    hooksecurefunc("PickupMerchantItem", function(index)
      pcall(V.OnPickup, index, time())
    end)
  end
end
