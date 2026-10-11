-- What the Sell tab's services (GoldCap/Services/Sell) share, in the first of their files to load:
-- GC.SellState, the state they and the screen read; GC.SellView,
-- what they ask of the screen, which the view's files (UI/Sell/) fill; and GC.SellUtil, the checks every one
-- of them makes on a number, a position and a pin.
local _, GC = ...

GC.Sell = GC.Sell or {}

-- Every service's module table, empty until its own file fills it, so a file can hold any other's
-- at load and call into it at run time, whichever loaded first. Calls between them go through the
-- table, never through a copy taken at load, so a spec that replaces one reaches every caller.
-- Fresh on every load, as the file locals they replace were: a reload starts every file over.
GC.SellQuotes, GC.SellBags, GC.SellCompose = {}, {}, {}
GC.SellOwned, GC.SellWalk, GC.SellPost = {}, {}, {}

GC.Sell.QUOTE_STALE_SECONDS = (GC.QuoteCache and GC.QuoteCache.MAX_AGE_SECONDS) or 10
-- How old a quote may be and still back a Post or a Repost.
--
-- The Sniper's 10s window is right for a purchase: it commits gold against one
-- price point. A listing competes over hours, and 10s made Post effectively
-- unclickable -- pricing the whole tab takes longer than that, so by the time
-- the walk finished the first row's quote had already expired, and clicking Post
-- only ever started another walk. Wide enough that a click lands, narrow enough
-- that the price on screen is the price you get.
GC.Sell.SELL_QUOTE_ACTION_AGE = 45
-- A quote younger than this is not re-asked about: it is already fresh enough for every
-- decision on this screen, and re-pricing it burns one of the walk's throttled server round
-- trips that a never-priced row further down the list needed. 30 sits under
-- SELL_QUOTE_ACTION_AGE (45) by more than a whole pass takes, so a quote is renewed before
-- the Post/Repost window on it ever closes. This is what turned the permanent
-- "PRICING N/24" grind into an empty steady-state pass.
GC.Sell.QUOTE_REWALK_AGE = 30
-- How long "the auction house answered: nothing listed" is remembered and treated like a
-- fresh quote. Without this, an item with zero live listings was indistinguishable from one
-- never asked about -- its cache entry was wiped on the empty answer -- so EVERY pass re-asked
-- it (or burned the full request timeout on one that never answers), which is what ground a
-- tab full of niche items to a crawl. A manual Refresh wipes these: the player asked for real.
GC.Sell.EMPTY_ANSWER_AGE = 60

GC.SellState = {
  positions = {}, ownedLots = {}, quotes = {},
  -- The posting queue, DERIVED, never stored: rebuilt by Compose.Positions() every time positions
  -- are, straight from GC.PostQueue.Build(positions). There is deliberately no separate stateful
  -- queue with an index into it -- a post empties that item from the bags, so the entry drops out
  -- of the very next build on its own. A stored queue is a second source of truth that can
  -- disagree with the bags, which is exactly the class of bug this codebase has been bitten by
  -- before (see the price-ladder and market-value postmortems). Both default to {} so the toolbar
  -- control has something sane to paint before the very first compose ever runs.
  queueEntries = {}, queueSkipped = {},
  -- The positions in the bags the player has not marked for selling, each with the reason it
  -- would have been held back for: out of the queue, their rows still tagged, and the dock's hint
  -- when nothing on hand is selling (Core/PostQueue.lua's Build).
  notSelling = {},
  -- The cancel twin, same statelessness contract: rebuilt from the positions on every compose,
  -- never kept as its own list with an index. A confirmed cancel makes the lot vanish from
  -- GetOwnedAuctions, so the entry drops out of the very next build on its own.
  cancelEntries = {}, cancelSkipped = {},
  bagStock = {},
  -- itemIDs whose OWNED lots could not be told commodity-from-item yet (Owned.Classify).
  -- Read by GC.Sell.OnItemKeyInfo, which re-keys those lots the moment the client learns the
  -- answer -- without it a lot stayed filed under a guessed key until the next owned-auctions
  -- query happened to come round.
  ownedAwaitingKind = {},
  -- Still "all": hiding the player's live listings behind a filter to answer "what
  -- can I list" would trade one blind spot for another. What changed is the order
  -- -- everything postable now sorts to the top (see SellViewModel.Order) -- and a
  -- Sellable chip for narrowing to it deliberately.
  -- Prices the seller typed, keyed by position. Deliberately NOT persisted and deliberately not
  -- a second source of truth about what to list at: BuildPostPlan is still the one place a post
  -- price is decided, and this is only what gets handed to it. Cleared when the position is
  -- posted (the stock leaves the bags and the row with it) or when the box is emptied.
  priceOverrides = {},
  -- How many units the seller asked one Post to list, keyed the same way and kept the same way:
  -- not persisted, handed to BuildPostPlan, spent with the post that carried it
  -- (GC.Sell._SpendPrice). Only ever under what one click could list; "all of it" is no entry.
  quantityOverrides = {},
  -- The dock walks the selling list once a visit (owner, 2026-10-10): what was posted this visit,
  -- and what the player passed over with SKIP, by positionKey. Out of the walk until the auction
  -- house is closed (GC.Sell._HoldDoneInQueue, GC.Sell.Reset); a row click still puts either in
  -- the dock. queueDone is what they took out of the queue, for the rows' tags.
  postedThisVisit = {},
  -- Posted whole, by positionKey: how many the bags held when all of it went up. The row leaves
  -- the posting deck at once, for as long as the bags still count exactly that (UI/Sell/List.lua).
  postedOut = {},
  passedThisVisit = {},
  queueDone = {},
  -- The item the player put in the dock by clicking its row, by positionKey; nil while the dock
  -- shows the walk's next. Once posted or passed it moves to the item after it (UI.Dock.MoveOn).
  dockKey = nil,
  -- "post" and "listed" are the two DECKS this tab is built on (SellViewModel.Deck). "cancelqueue"
  -- is a transient FOCUS state the CANCEL control sets for a single render, so its head entry
  -- lands on row 1 -- a deck is what the switch paints, a focus state is not.
  filterMode = "post",
  -- Where each position sits, remembered across renders (SellViewModel.Settle). Thrown away only
  -- when the PLAYER asks for a new order -- Refresh, a deck change, a chip -- never by a quote
  -- landing, an owned-auction scan or the walk's own repeat. Those change numbers, not places.
  rowPlaces = {},
  -- `priority` holds items a CLICK asked about while a pass was already running (Post/Repost on a
  -- row whose quote had aged out). Deliberately outside `queue`: splicing into that array put the
  -- item in a slot the walk then stepped over -- and a queue rebuilt by Walk.Begin, which is
  -- what the owned-auctions phase ends in, dropped it outright. Walk.Advance drains this before
  -- the queue's own next step, so the row the player is standing on is answered first.
  refresh = { generation = 0, phase = "idle", queue = {}, index = 0, pending = nil, awaiting = nil,
    drain = {}, priority = {} },
  walkRepeatToken = 0, watchdogToken = 0, quoteExpiryGeneration = 0,
  -- The armed post, cancel and removal: the row each stands on and what its first click pinned.
  postingRow = nil, postingPin = nil,
  repostingRow = nil, repostPin = nil,
  removingRow = nil, removePin = nil,
  -- renderRows holds a render back while a post, a cancel or a removal is armed; the disarm that
  -- lets the last of them go renders it.
  deferredRender = false,
  -- One-shot: Compose.Positions() runs on every refresh tick, and re-merging the persisted store
  -- on every one of them would let a persisted quote silently resurrect over a quote this
  -- session has already, correctly, forgotten (an empty answer via Walk.SkipPending). Guarded on
  -- GC.db existing at all -- the very first compose can run before ADDON_LOADED has -- so a
  -- session with no store yet simply retries on the next compose instead of flipping the flag on
  -- nothing.
  quotesSeeded = false,
  -- One entry per rested item, `{ at = when, answered = did the auction house actually reply }`.
  -- The second field is the whole point. A request that timed out and a reply that genuinely
  -- carried no listings both earn the item a rest -- re-asking either on the very next pass is
  -- what burned the walk's slots -- but only one of them is an ANSWER, and only an answer may be
  -- shown to the player as "none"/"Nothing listed". This was a bare timestamp, so an item that
  -- never came back was reported on screen, and by /gc sellstate, as the auction house saying it
  -- was unlisted.
  emptyAnswers = {},
  -- Where every position's current ItemLocation is built and cached: at paint time (renderRows,
  -- through its two call sites in UI/Sell/List.lua), never inside a click. WoW: Forever's taint
  -- engine blocks a protected auction house call once the same hardware click has run Blizzard's
  -- own Lua-side ItemLocation mixin code ahead of it -- whether or not the result is kept -- so
  -- onPostClick in UI/Sell/Dock.lua never calls ItemLocation:CreateFromBagAndSlot, or
  -- GC.Sell._SlotKey (which does, for a non-commodity stack), itself. Mirrors Auctionator: it
  -- builds itemInfo.location when a bag item is picked, well before its own Post click
  -- (Source_ModernAH/Selling/Hooks.lua's SelectOwnItem), and the click only reads that stored field.
  bagLocationCache = {},
  -- positionKey -> the last name a position was shown under, for the session. The client names an
  -- item it has not loaded yet "" (ContainerItemInfo.itemName is a string that is never nil, and an
  -- owned lot's link reads "[]" the same way), and on WoW: Forever items went unloaded in the middle
  -- of a REFRESH: rows painted blank, and some stayed blank until something repainted them. Keyed by
  -- position, not item: every caged pet is item 82800, "Pet Cage". Never reset -- a position's name
  -- does not change within a session.
  knownNames = {},
}

-- What the services ask of the screen. The view's files (UI/Sell/) fill every slot when they load; until they
-- have, and in a spec that loads the services alone, each does nothing and the tab reads as never
-- built.
local function nothing() end
GC.SellView = {
  render = nothing,      -- renderRows: rebuild the rows from the composed positions
  status = nothing,      -- setStatus(text): the status line, and the buttons that carry it
  paintQueue = nothing,  -- the dock's POST control
  paintCancel = nothing, -- the dock's CANCEL control
  paintDeck = nothing,   -- the deck switch's two counts
  notePost = nothing,    -- GC.Sell._NotePost(text, tone, seconds): the dock's note on the player's own post
  endPostNote = nothing, -- GC.Sell._EndPostNote(heldOnly): that note let go
  moveOn = nothing,      -- UI.Dock.MoveOn(positionKey): the dock, and an open panel, go on to the next item
  leave = nothing,       -- UI.List.Leave(positionKey): a row posted whole fades out and the list closes up
  attached = function() return false end, -- GC.Sell.Attach has built the tab
  isShown = nothing,     -- the tab's own shown flag; nil until it is built
}

local MAX_EXACT = 9007199254740991

local function exact(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

local function safeAdd(left, right)
  if not exact(left) or not exact(right) or left > MAX_EXACT - right then return nil end
  return left + right
end

local function safeMultiply(left, right)
  if not exact(left) or not exact(right) or (left ~= 0 and right > math.floor(MAX_EXACT / left)) then return nil end
  return left * right
end

-- One key per position for the typed price. The scope key carries the character and region as
-- well, which is what keeps a price chosen on one character from following the same item onto
-- another; positionKey alone is the fallback for a position composed before a scope exists.
local function overrideKey(position)
  if type(position) ~= "table" then return nil end
  -- positionKey, not scopeKey: the decoration (Core/SellPositions) has to key the same table,
  -- and it runs over positions that do not all carry a scope yet. The Sell tab composes for
  -- one character at a time anyway, so this cannot leak a price across characters in practice.
  local key = position.positionKey
  return type(key) == "string" and key ~= "" and key or nil
end

-- What Post would list this position at right now: the seller's own number when they have
-- given one, otherwise whatever GoldCap worked out. Both go through the SAME silver-grid
-- rounding BuildPostPlan applies, so the figure in the box is the figure that gets sent.
local function effectivePostUnit(position)
  local key = overrideKey(position)
  local chosen = key and GC.SellState.priceOverrides[key] or nil
  local rec = type(position.postRecommendation) == "table" and position.postRecommendation.unit or nil
  local unit = chosen or rec
  if not exact(unit) or unit <= 0 then return nil, chosen ~= nil end
  return (GC.Flips.SilverUp and GC.Flips.SilverUp(unit)) or unit, chosen ~= nil
end

-- How many units Post would list for this position right now, the most it could, and whether
-- the first is the seller's own number. The most is what one click can list (the largest stack
-- of a normal item, a commodity's whole pool: SellPositions' postableQty, else the bag count);
-- a number the seller gave counts only under it. Read live, like effectivePostUnit, so the row,
-- the panel and the queue move as the number is typed.
local function postQuantity(position)
  local most = exact(position.postableQty) and position.postableQty > 0 and position.postableQty
    or exact(position.bagQty) and position.bagQty or 0
  local key = overrideKey(position)
  local chosen = key and GC.SellState.quantityOverrides[key] or nil
  if exact(chosen) and chosen > 0 and chosen < most then return chosen, most, true end
  return most, most, false
end

local function context()
  return GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
end

local function activeScope(position)
  local scope = context()
  if type(position) ~= "table" or type(position.positionKey) ~= "string"
      or type(scope) ~= "table" or type(scope.char) ~= "string" or scope.char == ""
      or type(scope.region) ~= "string" or scope.region == "" then return nil, nil end
  local scopeKey
  if GC.Acquisitions and GC.Acquisitions.ScopeKey then
    scopeKey = GC.Acquisitions.ScopeKey(position.positionKey, scope)
  else
    scopeKey = table.concat({ scope.region, scope.char, position.positionKey }, "\1")
  end
  if scopeKey ~= position.scopeKey then return nil, nil end
  return scope, scopeKey
end

local function exactRenderEntry(row, pin)
  return row and pin and type(row.renderEntryID) == "string" and row.renderEntryID ~= ""
    and row.renderEntryID == pin.renderEntryID and pin.row == row and pin.action == row.action
    and pin.position == row.position
end

local function itemName(itemID)
  if C_Item and C_Item.GetItemNameByID then
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  -- Not loaded yet. Nothing else asks the client for it, so ask here: the walk's next pass, five
  -- seconds on, finds the name.
  if itemID and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
  return (GC.L["Item %d"]):format(itemID or 0)
end

GC.SellUtil = { exact = exact, safeAdd = safeAdd, safeMultiply = safeMultiply, overrideKey = overrideKey,
  effectivePostUnit = effectivePostUnit, postQuantity = postQuantity,
  context = context, activeScope = activeScope, exactRenderEntry = exactRenderEntry, itemName = itemName }

-- What the pricing walk searches for. A quote id is an itemID -- a commodity, or an item priced
-- by its bare key as the tab always has -- or, for an item-level variant keyed from its bag
-- slot's own ItemKey (GC.Sell._SlotKey), that variant's position key "item:id:level:suffix:pet":
-- its market is its own, and the bare key answers with the item's cheapest variant, which is
-- another item's price. Returns the itemID and the ItemKey to search and read by.
function GC.Sell._QuoteItemKey(id)
  if type(id) == "number" then return id, C_AuctionHouse.MakeItemKey(id) end
  local itemID, level, suffix, pet = tostring(id):match("^item:(%d+):(%d+):(%d+):(%d+)$")
  itemID = tonumber(itemID)
  if not itemID then return nil, nil end
  return itemID, C_AuctionHouse.MakeItemKey(itemID, tonumber(level), tonumber(suffix), tonumber(pet))
end

-- What the POST queue is built with (Core/PostQueue.lua's Build): the player's selling list, the
-- marks kept in the saved data (GC.Sell.SetSelling), and in WoW: Forever the vendor's price, so it
-- holds back what a vendor pays at least as much for (below_vendor). `quantities` are the
-- numbers the seller typed into "how many" (quantityOverrides), so the queue lists and values
-- what each Post will actually send. Before the saved data is
-- loaded there are no marks and no list: every position is queued, as before the selling list.
-- Read-only lookups: it runs inside Compose.Positions, which the Cancel click also calls.
function GC.Sell._QueueOpts()
  local opts = { marks = type(GC.db) == "table" and GC.db.sellMarks or nil, quantities = GC.SellState.quantityOverrides }
  if GC.ForeverScan and GC.ForeverScan.Enabled and GC.ForeverScan.Enabled()
      and GC.ForeverValue and GC.ForeverValue.VendorUnit then
    opts.vendorUnit = GC.ForeverValue.VendorUnit
  end
  return opts
end
