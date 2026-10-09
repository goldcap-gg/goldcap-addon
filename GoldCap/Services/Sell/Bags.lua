-- What is in the bags, for the Sell tab: the snapshot of every sellable stack, the key each one
-- posts under, whether the auction house sells it as a commodity, and the check a Post click makes
-- on its stack -- by plain C API, from the location the last paint cached -- before the protected
-- call. Moved from UI/SellFrame.lua as it was.
local _, GC = ...

local S = GC.SellState
local Bags, Walk = GC.SellBags, GC.SellWalk
local exact, safeAdd = GC.SellUtil.exact, GC.SellUtil.safeAdd

local SELL_BAGS = { 0, 1, 2, 3, 4, 5 }
local sessionCommodityKind = {}
-- Forward-declared: Bags.Scan calls it, and it is defined beside the classifier whose store it keeps within bounds.
local pruneCommodityKinds

local function normalizedPositionKey(itemID, link)
  if type(link) ~= "string" or link:find("battlepet:", 1, true) then return nil end
  local payload = link:match("|H(item:[^|]+)|h") or link:match("^(item:.-)$")
  if not payload then return nil end
  local fields, start = {}, 1
  while true do
    local colon = payload:find(":", start, true)
    if not colon then fields[#fields + 1] = payload:sub(start); break end
    fields[#fields + 1], start = payload:sub(start, colon - 1), colon + 1
  end
  local actualID = tonumber(fields[2])
  if actualID ~= itemID then return nil end
  local bonusCount = tonumber(fields[14])
  if #fields < 14 or bonusCount == nil or bonusCount ~= 0 then return nil end
  local level = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
  local suffix = tonumber(fields[8])
  if type(level) ~= "number" or suffix == nil then return nil end
  return ("item:%d:%d:%d:%d"):format(itemID, math.floor(level), suffix, 0)
end

-- The auction identity of a non-commodity bag stack, and the quote id it is priced by (nil for
-- the itemID). A link the parse above can read keeps exactly the key it always had: ledgers,
-- typed prices and listings are filed under it. The rest -- bonus IDs, which is nearly all modern
-- gear, and caged battle pets -- the parse gives up on, and used to be left out of the tab
-- altogether (in game: a bag of gear, none of it on TO POST). The client knows them exactly:
-- C_AuctionHouse.GetItemKeyFromItem answers, for this one bag slot, the ItemKey the auction house
-- itself files the stack under (item level, suffix, pet species), and PostItem posts by this
-- same slot. Nothing is guessed: no answer, no key.
function GC.Sell._SlotKey(itemID, link, bag, slot)
  local parsed = normalizedPositionKey(itemID, link)
  if parsed then return parsed, nil end
  if not (bag and slot and C_AuctionHouse and C_AuctionHouse.GetItemKeyFromItem
      and ItemLocation and ItemLocation.CreateFromBagAndSlot) then return nil, nil end
  local ok, itemKey = pcall(function()
    return C_AuctionHouse.GetItemKeyFromItem(ItemLocation:CreateFromBagAndSlot(bag, slot))
  end)
  if not ok or type(itemKey) ~= "table" or itemKey.itemID ~= itemID then return nil, nil end
  local positionKey = GC.Acquisitions and GC.Acquisitions.PositionKey
    and GC.Acquisitions.PositionKey(itemID, itemKey, false) or nil
  -- An ItemKey with no level, suffix or species (bonus IDs on a non-gear item) is the bare key:
  -- no variant, priced and valued as the item always was (review N8).
  local plain = (itemKey.itemLevel or 0) == 0 and (itemKey.itemSuffix or 0) == 0
    and (itemKey.battlePetSpeciesID or 0) == 0
  return positionKey, not plain and positionKey or nil
end

-- Whether an item sells as a commodity decides its whole auction identity, and
-- GetItemKeyInfo is the only authority on it -- but it is only reachable while
-- the auction house is open, and the Sell tab is useful standing anywhere. So
-- the answer is remembered in SavedVariables the first time it is learned, and
-- an item nobody has ever classified is left out rather than filed under a
-- guessed key. Guessing is what split one item into two positions before.
function Bags.CommodityKinds()
  if GC.db then
    GC.db.commodityByItem = type(GC.db.commodityByItem) == "table" and GC.db.commodityByItem or {}
    return GC.db.commodityByItem
  end
  return sessionCommodityKind
end

local function classifyBagItem(itemID, link, bag, slot)
  local cache = Bags.CommodityKinds()
  local isCommodity = cache[itemID]
  if isCommodity == nil and C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.MakeItemKey then
    local ok, info = pcall(function() return C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID)) end)
    if ok and type(info) == "table" and info.isCommodity ~= nil then
      isCommodity = info.isCommodity == true
      cache[itemID] = isCommodity
    end
  end
  if isCommodity == true then return ("commodity:%d"):format(itemID), true end
  if isCommodity == false then
    local positionKey, quoteKey = GC.Sell._SlotKey(itemID, link, bag, slot)
    -- The auction house -- open, so its answer means something -- says it cannot take this
    -- stack: not tradeable stock at all, so neither a row nor "waiting" (review M10). Asked of a
    -- keyed stack too: gear that is not bound yet cannot be auctioned -- Warbound until equipped
    -- -- keys like any other and would take a row and a search every pass (final review I3).
    if bag and slot and GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen()
        and C_AuctionHouse and C_AuctionHouse.IsSellItemValid and ItemLocation and ItemLocation.CreateFromBagAndSlot then
      local ok, valid = pcall(function()
        -- displayError false, as Auctionator's own bag scan asks: with it on, every compose at the
        -- auction house put the red "can't auction" error and its sound on screen (review N1).
        return C_AuctionHouse.IsSellItemValid(ItemLocation:CreateFromBagAndSlot(bag, slot), false)
      end)
      if ok and valid == false then return nil, false, nil, true end
    end
    return positionKey, false, quoteKey
  end
  return nil, nil
end

function Bags.Scan()
  if not GC.BagStock then S.bagStock, GC.Sell._waitingStock = {}, {} return end
  -- The second list is the stock nothing could key yet (the client has not said whether the item
  -- is a commodity, or cannot give its ItemKey): shown under its own heading, never dropped.
  S.bagStock, GC.Sell._waitingStock = GC.BagStock.Scan({
    numSlots = function(bag)
      return C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    end,
    itemInfo = function(bag, slot)
      if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if type(info) ~= "table" then return nil end
      local hyperlink = info.hyperlink
        or (C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or nil
      -- A caged pet's own name is in its battle-pet link; the item is "Pet Cage" for every one.
      local petName = type(hyperlink) == "string" and hyperlink:find("battlepet:", 1, true)
        and hyperlink:match("|h%[(.-)%]|h") or nil
      return {
        itemID = info.itemID, stackCount = info.stackCount, isBound = info.isBound,
        hasNoValue = info.hasNoValue, itemName = petName or info.itemName,
        hyperlink = hyperlink,
      }
    end,
    classify = classifyBagItem,
  }, SELL_BAGS)
  pruneCommodityKinds()
end

-- GC.db.commodityByItem is SavedVariables-resident and was append-only: one boolean for every
-- item this character has ever carried, kept for the life of the account. Capped the way
-- db.postStats is (Core/Data.lua's POST_STATS_CAP) -- past the cap, keep only what is on hand
-- or on sale right now. Nothing is lost that cannot be learned again: every entry came from a
-- GetItemKeyInfo call the next visit to an auctioneer makes anyway.
local COMMODITY_KIND_CAP = 2000
pruneCommodityKinds = function()
  local cache = Bags.CommodityKinds()
  local count = 0
  for _ in pairs(cache) do count = count + 1 end
  if count <= COMMODITY_KIND_CAP then return end
  local keep = {}
  for _, stock in ipairs(S.bagStock) do keep[stock.itemID] = true end
  for _, lot in ipairs(S.ownedLots) do keep[lot.itemID] = true end
  for itemID in pairs(cache) do
    if not keep[itemID] then cache[itemID] = nil end
  end
end

do -- a block, so the matcher below costs the file no top-level local slot
-- The one per-slot matching rule, shared by the live full scan and the paint snapshot so the two
-- cannot drift. `acc` carries the running result; false means the commodity total overflowed.
local function matchSlot(acc, position, requiredQty, commodity, bag, slot, stackCount)
  local qty = stackCount or 1
  if exact(qty) and qty > 0 and commodity then
    acc.total = safeAdd(acc.total, qty)
    if not acc.total then return false end
    if not acc.bag then acc.bag, acc.slot, acc.stack = bag, slot, qty end
  else
    local link = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
    -- Keyed exactly as the scan keyed it (GC.Sell._SlotKey), so Post pins the very stack
    -- the row stands for: for a variant, the slot whose own ItemKey is that variant's.
    if exact(qty) and qty > 0 and GC.Sell._SlotKey(position.itemID, link, bag, slot) == position.positionKey then
      if qty > acc.total then acc.total = qty end
      if (requiredQty and qty >= requiredQty and not acc.bag) or (not requiredQty and qty >= (acc.stack or 0)) then
        -- The exact hyperlink this slot holds right now, carried onward so cacheBagLocation
        -- can pin it at paint time -- a plain C_Container read, kept only for a
        -- non-commodity match (final review I2; see verifyBagStack).
        acc.bag, acc.slot, acc.stack, acc.link = bag, slot, qty, link
      end
    end
  end
  return true
end

-- `snapshot` (GC.Sell._BagSnapshot) is passed only by the paint paths, which read many
-- positions in one pass; without it every call scans the live bags, as every click path does.
function Bags.LiveState(position, requiredQty, snapshot)
  local acc = { total = 0 }
  local commodity = type(position.positionKey) == "string" and position.positionKey:match("^commodity:")
  if snapshot then
    for _, entry in ipairs(snapshot[position.itemID] or {}) do
      if not matchSlot(acc, position, requiredQty, commodity, entry.bag, entry.slot, entry.stackCount) then
        return { itemID = position.itemID, exactQty = nil }
      end
    end
  else
    for _, bag in ipairs(SELL_BAGS) do
      local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
      for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        -- Never a soulbound copy: the auction house refuses it, and a bound twin sharing the
        -- ItemKey kept the tradeable copy from ever being posted (review M8).
        if info and info.itemID == position.itemID and info.isBound ~= true then
          if not matchSlot(acc, position, requiredQty, commodity, bag, slot, info.stackCount) then
            return { itemID = position.itemID, exactQty = nil }
          end
        end
      end
    end
  end
  return { itemID = position.itemID, exactQty = acc.total, positionKey = acc.bag and position.positionKey or nil,
    bag = acc.bag, slot = acc.slot, stackQty = acc.stack, hyperlink = acc.bag and acc.link or nil }
end

-- One read of every bag slot, itemID -> its unbound slots in bag/slot order. A paint pass
-- (renderRows, OnBagsChanged) builds it once and hands it down as a local, so it cannot outlive
-- the pass or be seen by a click; the 5-second refresh used to rescan all slots per position.
function GC.Sell._BagSnapshot()
  local index = {}
  for _, bag in ipairs(SELL_BAGS) do
    local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and info.isBound ~= true then
        local list = index[info.itemID]
        if not list then list = {}; index[info.itemID] = list end
        list[#list + 1] = { bag = bag, slot = slot, stackCount = info.stackCount }
      end
    end
  end
  return index
end

GC.Sell._LiveBagState = Bags.LiveState -- read by specs, like GC.Sell._SlotKey
end


-- A GC.Sell field, not a top-level local: paint-only (every real call site is inside
-- pushPosition/renderRows, never a click's pre-call body -- SellFrame.lua has no local headroom
-- left to spend on it (final review "Headroom"). Safe unlike the click-path helpers just below
-- (Bags.ClickSafe, verifyBagStack, Bags.ResolveLocation): this one is never reached from
-- inside a click at all, so it carries none of their function-field-call taint risk.
function GC.Sell._CacheBagLocation(position, bagState)
  if not (bagState and bagState.bag and bagState.slot and bagState.itemID
      and ItemLocation and ItemLocation.CreateFromBagAndSlot) then
    S.bagLocationCache[position.positionKey] = nil
    return
  end
  local ok, location = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bagState.bag, bagState.slot)
  S.bagLocationCache[position.positionKey] = (ok and location) and { itemID = bagState.itemID,
    bag = bagState.bag, slot = bagState.slot, location = location, positionKey = bagState.positionKey,
    -- Only a non-commodity match ever carries one (Bags.LiveState above); nil here means "commodity
    -- position, or nothing was matched" and verifyBagStack skips the check for it accordingly.
    hyperlink = bagState.hyperlink } or nil
end

-- The click-time half of the cache above: a plain C API on plain numbers, never a Blizzard mixin
-- method. Confirms the exact bag/slot the cache pinned still holds this item, with enough of it,
-- before the location cacheBagLocation already built is trusted. A stack that moved is refused
-- here rather than re-resolved -- the next paint, or the next bag change while the tab is shown
-- (GC.Sell.OnBagsChanged below), recaches it.
--
-- Checking only itemID/bound/count let a DIFFERENT variant of the same item -- another item
-- level, bonus IDs, or a Classic-style random suffix ("...of the Bear") -- pass, and post at
-- THIS version's price (final review I2; applies on retail too: a swap that lands between the
-- last recache and the click would otherwise go unnoticed). requiredHyperlink, when given, is compared against a fresh
-- C_Container.GetContainerItemLink read -- itself a plain C API, not the mixin method a click
-- must not call -- so a swapped stack is refused rather than silently posted as its old self. A
-- commodity call site never has one to pass (only a non-commodity match ever caches a hyperlink),
-- so it keeps exactly the item-ID check it always had.
local function verifyBagStack(bag, slot, itemID, requiredQty, requiredHyperlink)
  if not (bag and slot and itemID and C_Container and C_Container.GetContainerItemInfo) then return nil end
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not info or info.itemID ~= itemID or info.isBound == true then return nil end
  if requiredHyperlink ~= nil then
    local link = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)
    if link ~= requiredHyperlink then return nil end
  end
  local qty = info.stackCount or 1
  if not exact(qty) or qty <= 0 then return nil end
  if requiredQty and (not exact(requiredQty) or qty < requiredQty) then return nil end
  return qty
end

-- Bags.LiveState's own loop calls GC.Sell._SlotKey for a non-commodity stack, to ask the client what
-- ItemKey a slot files under -- and that builds an ItemLocation, exactly the Blizzard mixin call a
-- click must not make (see cacheBagLocation above). For a commodity position Bags.LiveState never
-- does this: its loop only sums plain C_Container reads for a matching itemID, so it stays safe to
-- call fresh inside a click. Only the non-commodity branch below needs the cache instead of a live
-- rescan.
function Bags.ClickSafe(position, requiredQty)
  local commodity = type(position.positionKey) == "string" and position.positionKey:match("^commodity:")
  if commodity then return Bags.LiveState(position, requiredQty) end
  local cached = S.bagLocationCache[position.positionKey]
  if not cached or cached.itemID ~= position.itemID then return { itemID = position.itemID, exactQty = nil } end
  local qty = verifyBagStack(cached.bag, cached.slot, position.itemID, requiredQty, cached.hyperlink)
  if not qty then return { itemID = position.itemID, exactQty = nil } end
  return { itemID = position.itemID, exactQty = qty, positionKey = cached.positionKey,
    bag = cached.bag, slot = cached.slot, stackQty = qty }
end

-- The location cacheBagLocation already built for this position, reused only once a plain C API
-- proves its own cached bag/slot still holds the item -- never rebuilt here. The cache's own slot
-- is what is asked about, not bagState's: a commodity posts by itemID, and Bags.LiveState's live
-- aggregate scan (Bags.ClickSafe above) can find a different "first" stack than the one the
-- cache anchored at the last paint without that meaning the cached stack is gone.
function Bags.ResolveLocation(position)
  local cached = S.bagLocationCache[position.positionKey]
  if not cached or cached.itemID ~= position.itemID then return nil end
  if not verifyBagStack(cached.bag, cached.slot, cached.itemID, nil, cached.hyperlink) then return nil end
  return cached.location
end

-- BAG_UPDATE_DELAYED (Core/Init.lua), while this tab is on screen: re-pins every position's
-- cached bag location to where its stack sits now. Without it a stack moved, split, used or sold
-- after the last Sell paint stayed pinned at its old slot, and Post answered "No exact bag stack"
-- until something happened to repaint -- nothing on a bare bag change did (retail drift audit
-- F2; 0.15.3 found the stack live inside the click). This runs in the event's own execution,
-- never inside a click and never from the auction-house ticker, so the click keeps reading only
-- the plain cached values it reads today. Cache only: no render, no recompose -- the rows and
-- their counts repaint as they always have. A hidden tab skips it: Show() refreshes and renders,
-- which recaches before any Post can be pressed. A GC.Sell field, not a top-level local
-- (SellFrame.lua's headroom).
function GC.Sell.OnBagsChanged()
  if not Walk.Shown() then return end
  local snapshot = GC.Sell._BagSnapshot()
  for _, position in ipairs(S.positions) do
    if position.positionKey and (position.bagQty or 0) > 0 then
      GC.Sell._CacheBagLocation(position, Bags.LiveState(position, nil, snapshot))
    end
  end
end
