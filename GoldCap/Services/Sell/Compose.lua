-- The positions the Sell tab shows, composed from the bags, the player's own lots, the quotes and
-- the purchase records (Core/SellPositions.lua does the accounting), with the posting and cancel
-- queues derived from them and the count on the tab. Moved from UI/SellFrame.lua as it was.
local _, GC = ...

local S, View = GC.SellState, GC.SellView
local Quotes, Bags, Compose = GC.SellQuotes, GC.SellBags, GC.SellCompose
local context, itemName = GC.SellUtil.context, GC.SellUtil.itemName
local SELL_QUOTE_ACTION_AGE = GC.Sell.SELL_QUOTE_ACTION_AGE

-- Stamped by Compose.Positions() as it walks every position, so SellableCount() can read it
-- without recomposing. nil only until the first compose has ever run.
local sellableCount

-- `skipPaint`: WoW: Forever's taint engine blocks a protected AH call once the same hardware
-- click has read certain GoldCap runtime state -- and `View.paintDeck()` below,
-- which reads `position.listedQty`/`bagQty` off `positions`, is one of the reads it flags
-- (see onRepostClick's own comment on this). onRepostClick's pre-cancel validation needs this
-- function's DATA (fresh `ownedLots`/`positions`) but must not trigger that paint before its own
-- protected call further down; it passes true here and repaints the deck switch itself, once,
-- right after that call. Every other caller leaves this at its default (false) and keeps the
-- paint exactly where it always was.
function Compose.Positions(skipPaint)
  if not S.quotesSeeded then Quotes.Seed() end
  local scope = context()
  Bags.Scan()

  -- A craft happens away from the auction house, where the client will not say whether the
  -- item sells as a commodity, so Core/CraftCapture.lua records those batches keyless rather
  -- than filing them under a guessed key. The bag walk immediately above has just put that
  -- question to GetItemKeyInfo -- the authority itself -- so this is where a crafted batch
  -- stops being keyless, and it runs before the batches are read below so the cost shows on
  -- this very pass. BindItemOnly cannot serve here: it is for legacy item-only evidence and
  -- requires the item to have been LISTED, which stock the player has only just made has not.
  if GC.Acquisitions and GC.Acquisitions.BindClassifiedIdentity and scope then
    local classified, ambiguous = {}, {}
    for _, stock in ipairs(S.bagStock) do
      if type(stock.positionKey) == "string" and stock.positionKey ~= "" then
        if classified[stock.itemID] and classified[stock.itemID] ~= stock.positionKey then
          ambiguous[stock.itemID] = true
        end
        classified[stock.itemID] = stock.positionKey
      end
    end
    for _, batch in ipairs(GC.Acquisitions.GetActive(scope)) do
      -- Two stacks of one item under different keys means the bags cannot say which one this
      -- batch is; leaving it keyless is the honest answer.
      if not batch.positionKey and classified[batch.itemID] and not ambiguous[batch.itemID] then
        GC.Acquisitions.BindClassifiedIdentity(batch.id, classified[batch.itemID], scope)
      end
    end
  end
  local stats = {}
  for _, lot in ipairs(S.ownedLots) do
    stats[lot.itemID] = GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(lot.itemID) or nil
  end
  for _, stock in ipairs(S.bagStock) do
    stats[stock.itemID] = stats[stock.itemID]
      or (GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(stock.itemID) or nil)
  end
  local batches = GC.Acquisitions and GC.Acquisitions.GetActive and GC.Acquisitions.GetActive(scope) or {}
  for _, batch in ipairs(batches) do
    stats[batch.itemID] = stats[batch.itemID] or (GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(batch.itemID) or nil)
  end
  local pending = GC.Acquisitions and GC.Acquisitions.GetPending and GC.Acquisitions.GetPending(scope) or {}
  local activities = GC.Acquisitions and GC.Acquisitions.GetActivities and GC.Acquisitions.GetActivities(scope) or {}
  local consumed = {}
  for _, realized in ipairs(GC.Acquisitions and GC.Acquisitions.GetRealized and GC.Acquisitions.GetRealized(scope) or {}) do
    if realized.evidenceKey then consumed[realized.evidenceKey] = true end
  end
  local sellerEvidence = {}
  for _, entry in ipairs(GC.Ledger and GC.Ledger.GetEntries and GC.Ledger.GetEntries() or {}) do
    if entry.kind == "sale" and entry.source == "mail" and entry.char == scope.char
        and entry.region == scope.region and not consumed[entry.key] then
      sellerEvidence[#sellerEvidence + 1] = entry
    end
  end
  -- Identity evidence travels separately from `batches`: GetActive drops a batch the moment it
  -- is sold out, and taking the item's auction identity from that same list is what orphaned
  -- every keyless batch of a fully-sold item into its own repair row.
  local identityEvidence = GC.Acquisitions and GC.Acquisitions.GetIdentityEvidence
    and GC.Acquisitions.GetIdentityEvidence(scope) or {}
  S.positions = GC.SellPositions.Build({ acquisitions = batches, identityEvidence = identityEvidence,
    pendingAcquisitions = pending,
    activities = activities, sellerEvidence = sellerEvidence, ownedLots = S.ownedLots,
    bagStock = S.bagStock, quotes = S.quotes, statsByItemID = stats, context = scope, now = time(),
    -- "Does this item sell as a commodity", straight from C_AuctionHouse.GetItemKeyInfo and
    -- remembered. Build cannot reach SavedVariables and must not; it is handed the answer so
    -- it can settle an activity set holding `commodity:X` and `item:X:...` for one itemID --
    -- provable corruption that a purchase record can only settle when there IS a purchase.
    commodityKinds = Bags.CommodityKinds(),
    -- A price the seller typed has to reach the decoration, not just the post: the PROFIT
    -- column, the posting queue's own label and the plan all read the recommendation, and
    -- this tab has twice shipped a bug where the price shown and the price sent were two
    -- different numbers.
    chosenUnits = S.priceOverrides,
    -- WoW: Forever only (Core/SellPositions.lua's decoratePosition): the player's own scan is
    -- the market there, so the projection prices bag stock from it while the live walk is still
    -- waiting on the throttle. Posting and cancelling are untouched -- they still wait for fresh.
    scanProjects = GC.ForeverScan and GC.ForeverScan.Enabled and GC.ForeverScan.Enabled() or nil,
    quoteMaxAge = SELL_QUOTE_ACTION_AGE })
  -- Stamped in the same walk this function already does over every position, rather than a
  -- second pass triggered from SellableCount() -- see that function for why a fresh compose
  -- per label-read was wasteful (a six-bag scan plus every Acquisitions/Ledger walk, on a tab
  -- that may not even be the one currently shown).
  local sellable = 0
  for _, position in ipairs(S.positions) do
    -- "" is no name (S.knownNames says why): the name this position was last shown under, else
    -- the client's for the item, else "Item N" until it loads.
    if position.itemID then
      local key, name = position.positionKey or position.itemID, position.itemName
      if type(name) == "string" and name ~= "" then S.knownNames[key] = name
      else position.itemName = S.knownNames[key] or itemName(position.itemID) end
    end
    if (position.bagQty or 0) > 0 then sellable = sellable + 1 end
  end
  sellableCount = sellable
  Compose.Queue()
  -- The cancel twin, same degradation contract for fixtures loaded without the module.
  if GC.CancelQueue and GC.CancelQueue.Build then
    S.cancelEntries, S.cancelSkipped = GC.CancelQueue.Build(S.positions)
  else
    S.cancelEntries, S.cancelSkipped = {}, {}
  end
  View.paintCancel()
  -- The deck switch's two counts are read straight off `positions`, so they have to be
  -- repainted whenever `positions` moves. `container.paintDeckSwitch` (now behind View.paintDeck)
  -- was exported for exactly this and then never called by anybody: the switch was painted once
  -- at construction, over an empty table, and after that only when the player clicked one of its
  -- own two buttons. So it sat at "TO POST 0 · MY LOTS 0" above a full list -- and that zero is
  -- what made a fixed bag-stock bug look like it was still broken, twice, to two different readers.
  if not skipPaint then View.paintDeck() end
end

-- The posting queue, rebuilt from THESE positions every time -- never kept as a separate stateful
-- list (see State.lua's queueEntries/queueSkipped declaration for why) -- and from the player's
-- selling list. Its own function so a click on a row's selling mark can rebuild it without a
-- whole compose (a six-bag scan and every purchase record): a mark changes which positions are
-- queued, not the positions. Guarded for GC.PostQueue being absent: every real load carries
-- Core/PostQueue.lua (GoldCap.toc), but a handful of older fixtures in this spec suite load the
-- Sell view (helper.loadSell) without it, and a missing queue module must degrade to "nothing
-- queued," never a crash.
function Compose.Queue()
  if GC.PostQueue and GC.PostQueue.Build then
    S.queueEntries, S.queueSkipped, S.notSelling = GC.PostQueue.Build(S.positions, GC.Sell._QueueOpts())
  else
    S.queueEntries, S.queueSkipped, S.notSelling = {}, {}, 0
  end
  GC.Sell._HoldLateInQueue()
  View.paintQueue()
end

--- The player's click on a row's selling mark (UI/Sell/Row.lua): kept for the position in the saved
-- data, for every character, then the queue rebuilt and the list drawn again. Its own click,
-- never on the way to a post.
function GC.Sell.SetSelling(positionKey, selling)
  if type(positionKey) ~= "string" or positionKey == "" or type(GC.db) ~= "table" then return end
  GC.db.sellMarks = GC.db.sellMarks or {}
  GC.db.sellMarks[positionKey] = selling == true
  Compose.Queue()
  View.render()
end

--- Is this position on the player's selling list (Core/PostQueue.lua's Selling, over the saved
-- marks)? For the row's mark and the list's two sections.
function GC.Sell.IsSelling(position)
  return GC.PostQueue ~= nil and GC.PostQueue.Selling(position, GC.Sell._QueueOpts().marks)
end

-- The number on the Sell tab. It counted positions whose tracked purchases
-- outran their known listings -- an accounting difference, not a count of
-- anything a player can act on. It now counts items sitting in the bags that
-- the auction house would accept, which is what "Sell (9)" reads as.
--
-- Reads the count Compose.Positions() already stamped rather than recomposing to answer this --
-- a compose is a full six-bag scan plus every Acquisitions/Ledger walk, and every caller of
-- this function calls it right where Compose.Positions() was either just run or is about to be:
--   * updateSellTabLabel(), from renderRows()'s own tail -- always after this same render's
--     Compose.Positions() has already run.
--   * GC.Sniper.Toggle() and the AH-open handler -- both call GC.Sell.Refresh() (which
--     composes synchronously, before any network round trip) immediately before reading this.
--   * recordPurchaseFacts(), right after a purchase -- calls this WITHOUT a fresh compose, but
--     a GoldCap purchase always lands in the mailbox, never straight into the bags, so bagQty
--     (what this counts) cannot have changed at that exact instant; the cached value is still
--     correct, and was already the only thing an immediate recompose there would have measured.
-- Only a cold call before anything has ever composed falls back to composing once itself.
function GC.Sell.SellableCount()
  if sellableCount == nil then Compose.Positions() end
  return sellableCount or 0
end
