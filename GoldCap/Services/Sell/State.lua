-- What the Sell tab's services (GoldCap/Services/Sell) share, in the first of their files to load:
-- GC.SellState, the state they and the screen read (Task 2 of the move fills it); GC.SellView,
-- what they ask of the screen, which UI/SellFrame.lua fills; and GC.SellUtil, the checks every one
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

-- What the services ask of the screen. UI/SellFrame.lua fills every slot when it loads; until it
-- has, and in a spec that loads the services alone, each does nothing and the tab reads as never
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
  return (GC.L["Item %d"]):format(itemID or 0)
end

GC.SellUtil = { exact = exact, safeAdd = safeAdd, safeMultiply = safeMultiply, overrideKey = overrideKey,
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

-- WoW: Forever: the POST queue holds back what a vendor pays at least as much for (see
-- Core/PostQueue.lua's below_vendor). nil anywhere else, so retail's queue is built exactly as
-- before. Read-only lookups: it runs inside composePositions, which the Cancel click also calls.
function GC.Sell._QueueOpts()
  if not (GC.ForeverScan and GC.ForeverScan.Enabled and GC.ForeverScan.Enabled()) then return nil end
  if not (GC.ForeverValue and GC.ForeverValue.VendorUnit) then return nil end
  return { vendorUnit = GC.ForeverValue.VendorUnit }
end
