-- Where the Sell tab's prices come from: the reads of the auction house's own search results
-- (GC.SellQuotes.driver, the one place this tab reads them), the quotes kept across a reload, the
-- check a Post or a Repost makes before it trusts one, and the bulk fill that prices every
-- commodity on the tab in one message. Moved from UI/SellFrame.lua as it was.
local _, GC = ...

local S, View = GC.SellState, GC.SellView
local Quotes, Compose, Walk = GC.SellQuotes, GC.SellCompose, GC.SellWalk
local exact = GC.SellUtil.exact
local QUOTE_STALE_SECONDS, SELL_QUOTE_ACTION_AGE = GC.Sell.QUOTE_STALE_SECONDS, GC.Sell.SELL_QUOTE_ACTION_AGE
local QUOTE_REWALK_AGE = GC.Sell.QUOTE_REWALK_AGE

local function quoteDriver()
  local function boundedLevels(itemID, commodity)
    local _, itemKey = GC.Sell._QuoteItemKey(itemID)
    local levels, count = {}, commodity and C_AuctionHouse.GetNumCommoditySearchResults(itemID)
      or C_AuctionHouse.GetNumItemSearchResults(itemKey)
    local cap = GC.SellViewModel and GC.SellViewModel.BOOK_READ_MAX or 100
    for i = 1, math.min(count or 0, cap) do
      local info = commodity and C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        or C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
      -- An item row groups identical auctions, and its buyoutAmount is what ONE of them costs --
      -- Blizzard's own sell frame takes it as the unit price. Divided by the row's quantity, 150
      -- bags at 1,800g read as 12g (player report, 2026-09-26).
      local unit = info and (commodity and info.unitPrice or info.buyoutAmount)
      if unit and unit > 0 then
        levels[#levels + 1] = { unitPrice = unit, quantity = info.quantity or 0,
          ownerItem = info.containsOwnerItem == true, ownerQty = info.numOwnerItems }
      end
    end
    -- Whether the read stopped short of the whole book: more rows than it takes, or an answer
    -- the client does not hold in full. THE BOOK's "past the read" is this flag, never a count
    -- that happens to equal the cap (review M5).
    if #levels > 0 then
      local full = true
      if commodity and C_AuctionHouse.HasFullCommoditySearchResults then
        full = C_AuctionHouse.HasFullCommoditySearchResults(itemID) ~= false
      elseif not commodity and C_AuctionHouse.HasFullItemSearchResults then
        full = C_AuctionHouse.HasFullItemSearchResults(itemKey) ~= false
      end
      levels.cut = (count or 0) > cap or not full or nil
    end
    return #levels > 0 and levels or nil
  end

  local function competingOrOwnUnit(levels)
    if not levels then return nil end
    local competing = GC.SellPositions.CheapestCompetingUnit(levels)
    if competing then return competing end
    local own
    for i = 1, #levels do
      local unit = levels[i].unitPrice
      if type(unit) == "number" and unit > 0 and (own == nil or unit < own) then own = unit end
    end
    return own
  end
  return {
    -- GC.Util.ThrottleReady, not the raw flag: see its comment for the stuck-flag client.
    isReady = function()
      if GC.Util and GC.Util.ThrottleReady then return GC.Util.ThrottleReady() end
      return C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady and C_AuctionHouse.IsThrottledMessageSystemReady()
    end,
    -- isReady answers whether a send is permitted; this takes the permit, once, immediately
    -- before a query goes out. Under a throttle flag that has stopped changing it is what keeps
    -- this walk moving at all: the permit used to be one global one, and the Sniper's arbiter
    -- runs immediately ahead of this tab on every ready event, so the tab never saw one.
    claimSend = function()
      if GC.Util and GC.Util.ClaimThrottleSend then return GC.Util.ClaimThrottleSend("sell") end
      return true
    end,
    keyInfo = function(itemID)
      if not (C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo) then return nil end
      local _, itemKey = GC.Sell._QuoteItemKey(itemID)
      return itemKey and C_AuctionHouse.GetItemKeyInfo(itemKey)
    end,
    send = function(itemID)
      local _, key = GC.Sell._QuoteItemKey(itemID)
      local info = C_AuctionHouse.GetItemKeyInfo(key)
      -- Blizzard's pane may open this item's buy page in answer; that page is ours, not a buy.
      if GC.AuctionHouseTab and GC.AuctionHouseTab.NoteAddonSearch then GC.AuctionHouseTab.NoteAddonSearch() end
      if info and info.isCommodity then
        if GC.Util and GC.Util.Trace then GC.Util.Trace("sell: search") end
        C_AuctionHouse.SendSearchQuery(key, {}, false)
      else
        C_AuctionHouse.SendSearchQuery(key, { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }, false)
      end
    end,
    -- Both price against the cheapest level somebody ELSE is selling at. Reading level 1 blind
    -- means pricing against your own auction the moment you are the cheapest seller, so every
    -- Post/Repost undercut the previous one and the price walked down against nobody. Sharing a
    -- level with real competitors still counts -- see SellPositions.CheapestCompetingUnit.
    --
    -- With no competition at all the fallback is the player's OWN cheapest listing: holding the
    -- current price is the honest answer there, where undercutting would just resume the walk.
    item = function(itemID)
      return competingOrOwnUnit(boundedLevels(itemID, false))
    end,
    commodity = function(itemID)
      return competingOrOwnUnit(boundedLevels(itemID, true))
    end,
    itemLevels = function(itemID) return boundedLevels(itemID, false) end,
    commodityLevels = function(itemID) return boundedLevels(itemID, true) end,
    -- Is the client holding a COMPLETE reply for this key, or merely whatever result set the
    -- last search left in the slot? GetNum*SearchResults answers the second question only, and
    -- the results events UI/SellFrame.lua listens to are raised by the Sniper's searches as well as
    -- our own -- so a zero read is not proof the auction house said "nothing listed". This is
    -- the proof; see quoteResolved, which will not gag an item without it.
    --
    -- Returns TRUE when the client offers no way to ask. A missing API is not evidence of
    -- anything, and failing that case closed would gag nothing ever again.
    hasFullResults = function(itemID, commodity)
      if not C_AuctionHouse then return true end
      if commodity then
        if not C_AuctionHouse.HasFullCommoditySearchResults then return true end
        return C_AuctionHouse.HasFullCommoditySearchResults(itemID) == true
      end
      if not (C_AuctionHouse.HasFullItemSearchResults and C_AuctionHouse.MakeItemKey) then return true end
      local _, itemKey = GC.Sell._QuoteItemKey(itemID)
      return C_AuctionHouse.HasFullItemSearchResults(itemKey) == true
    end,
  }
end
Quotes.driver = quoteDriver()

-- The Sell tab's own persisted mirror of `quotes` (GC.SellState.quotes): only
-- {unit, at}, never `levels` -- see Core/Init.lua's `sellQuotes` default for the write side
-- and why. nil once GC.db does not exist yet: Init.lua runs LAST in the .toc, so no store
-- exists at file load, and persistence is simply skipped until it does. Unlike
-- Bags.CommodityKinds, there is no session-local fallback -- an unpersisted quote costs
-- nothing worse than today's behavior (a dash until the walk answers).
function Quotes.Persisted()
  if not GC.db then return nil end
  GC.db.sellQuotes = type(GC.db.sellQuotes) == "table" and GC.db.sellQuotes or {}
  return GC.db.sellQuotes
end

-- How old a persisted quote may be and still seed `quotes` on the first compose after a
-- reload. Loose on purpose: a days-old price is still a better anchor than a dash (the
-- renderer's own " . stale %ds" tag already tells the truth about its age), but week-old
-- garbage should not resurrect and confuse a Post decision. Pruning here is also what stops
-- the persisted store growing forever, since nothing else ever deletes an old entry from it.
local QUOTE_PERSIST_MAX_AGE = 3 * 24 * 60 * 60

function Quotes.Seed()
  local store = Quotes.Persisted()
  if not store then return end
  S.quotesSeeded = true
  local now = time()
  for itemID, entry in pairs(store) do
    local unit = type(entry) == "table" and entry.unit or nil
    local at = type(entry) == "table" and entry.at or nil
    local valid = exact(unit) and unit > 0 and exact(at) and at <= now and (now - at) <= QUOTE_PERSIST_MAX_AGE
    if valid then
      -- A live answer this session already produced beats a persisted one.
      -- `bookless`: a restored quote is a number with no book under it -- the store keeps the
      -- unit and its date, never the levels. Seconds after a reload it is still "fresh", so the
      -- walk left it alone and the row sat with a price and no queue standing, and its panel
      -- with no book, until the quote aged out (seen in game). The walk owes it a real answer
      -- exactly as it owes a bulk price one; see Walk.Queue.
      if S.quotes[itemID] == nil then S.quotes[itemID] = { unit = unit, at = at, bookless = true } end
    else
      store[itemID] = nil
    end
  end
end

function Quotes.Fresh(position)
  local quote = GC.QuoteCache.Fresh(S.quotes, position.quoteKey or position.itemID, time(), SELL_QUOTE_ACTION_AGE)
  if type(quote) ~= "table" or not exact(quote.unit) or quote.unit <= 0 or not exact(quote.at) then return nil end
  -- A price from the bulk fill (GC.Sell.FoldBulk) is the realm's cheapest unit with nobody
  -- subtracted from it -- good enough to show, never good enough to spend on. Post and Repost
  -- get exactly what they get for a stale quote: a fetch of this one item, then the click.
  if quote.bulk then return nil end
  return quote
end

-- The bulk fill: every commodity on the tab priced by ONE throttled message.
--
-- The walk prices a row per round trip -- a SendSearchQuery each, through the one throttled
-- slot the whole addon shares -- so a tab of twenty rows filled in over half a minute, top to
-- bottom, and a press of Refresh did it all again. C_AuctionHouse.SearchForItemKeys answers
-- for up to a hundred item keys at once with the realm's cheapest unit for each; the Items
-- board and the BUY tab already share one such batch through UI/SniperFrame.lua's arbiter,
-- and this is the third name on it. Every addon-wide rule lives there (one batch outstanding,
-- never across a book pass, never while the player is using the auction house themselves).
--
-- What comes back is a price to SHOW. It is the cheapest unit on the realm with nobody
-- subtracted -- the player's own lots included -- and it carries no book. So a row whose
-- answer says the player is among the sellers is left for the walk, the price is marked
-- `bulk`, Quotes.Fresh refuses to post against it, and the walk treats it as still owed a real
-- quote. Commodities only: a basic item key's price can be another variant's, and a wrong
-- number is worse than none (the walk's own rule, see Walk.Queue).
local BULK_MAX = 100 -- Blizzard's ceiling for one call; more disconnects the client

function GC.Sell.BulkTargets()
  local ids, seen = {}, {}
  for _, position in ipairs(S.positions) do
    local commodity = type(position.positionKey) == "string"
      and position.positionKey:find("commodity:", 1, true) == 1
    local actionable = (type(position.bagQty) == "number" and position.bagQty > 0)
      or (type(position.listedQty) == "number" and position.listedQty > 0)
    local id = position.itemID
    if commodity and actionable and exact(id) and id > 0 and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
      if #ids >= BULK_MAX then break end
    end
  end
  return ids
end

-- Whether this tab's own batch is still waiting for its answer. Eight seconds, not the
-- arbiter's thirty: that timeout protects a poll that has nothing else to do, whereas this
-- wait holds up the whole pricing walk, and a batch that has not answered in eight seconds is
-- not going to make the tab feel fast.
function GC.Sell.BulkOutstanding()
  local sniper = GC.Sniper
  if not (sniper and sniper._keysOwner == "sell" and sniper._keysAwaiting) then return false end
  return (time() - sniper._keysAwaiting) < 8
end

-- Whether the pricing walk's own search is still waiting for its answer (refresh.pending, until it
-- lands or is older than a quote can be). Final review m9: UI/SniperFrame.lua's
-- _TrySendKeysBatchFor asks it before any keys batch goes, this tab's own bulk fill included -- a
-- batch sent on top of the search takes its answer.
function GC.Sell.SearchPending()
  local pending = S.refresh.pending
  return pending ~= nil and (time() - (pending.at or 0)) <= QUOTE_STALE_SECONDS
end

function GC.Sell.TrySendBulk(playerBusy)
  if not S.refresh.bulkWanted or not Walk.Live() then return false end
  if not (GC.Sniper and GC.Sniper._TrySendKeysBatchFor and GC.Sniper.CurrentView
      and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen()) then return false end
  local sent = GC.Sniper._TrySendKeysBatchFor({
    HasPending = function() return S.refresh.bulkWanted == true end,
    NextBatch = GC.Sell.BulkTargets,
  }, "sell", function() return GC.Sniper.CurrentView() == "sell" end, playerBusy) and true or false
  -- Asked once per press. A batch that could not go this second (a pass paging, the throttle
  -- shut) is asked for again by the ticker; one that went is not repeated until the next press.
  if sent then S.refresh.bulkWanted, S.refresh.bulkSent = false, true end
  return sent
end

-- The batch's answer, routed here by GC.Sniper._FoldKeysBatch because this tab asked.
function GC.Sell.FoldBulk(browsed)
  local now, filled = time(), 0
  S.refresh.bulkSent = nil
  for i = 1, #(browsed or {}) do
    local row = browsed[i]
    local itemKey = type(row) == "table" and row.itemKey or nil
    local itemID = type(itemKey) == "table" and itemKey.itemID or nil
    local unit = type(row) == "table" and row.minPrice or nil
    local held = itemID and S.quotes[itemID] or nil
    -- A real quote the walk already holds is better than this in every way; keep it.
    local keep = type(held) == "table" and not held.bulk and not held.bookless and exact(held.at)
      and (now - held.at) <= QUOTE_REWALK_AGE
    if exact(itemID) and exact(unit) and unit > 0 and not row.containsOwnerItem and not keep then
      GC.QuoteCache.Set(S.quotes, itemID, unit, now)
      if type(S.quotes[itemID]) == "table" then
        S.quotes[itemID].bulk = true
        filled = filled + 1
      end
    end
  end
  if filled > 0 then
    S.refresh.bulkLanded = true
    Compose.Positions()
    View.render()
    -- Said out loud: without it the only sign this happened is that the numbers were already
    -- there, which is indistinguishable from the walk having been quick.
    View.status((GC.L["%d prices in one request · books still loading"]):format(filled))
  end
  -- The answer is in: whatever stood still for it -- the listings query, the walk -- goes now.
  GC.Sell.OnThrottleReady()
end
