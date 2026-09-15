local _, GC = ...

-- The BUY tab: one shopping run at a time, rendered as "what do I still need, what have I
-- already got, what should the rest cost". The arithmetic is entirely Core/BuyRun.lua's --
-- this file owns only the picking of the run, the four things the client alone can answer
-- (bag counts, market value, the price cap setting, the free-line limit), and the drawing.
--
-- Buying is hover, click, click: the cursor landing on a line quotes it against the live
-- commodity book, the first click starts the purchase for exactly that quantity, and a second
-- click confirms the price the server came back with. Both protected C_AuctionHouse calls are
-- reached ONLY from the player's own hardware click (addon/AGENTS.md's "Protected actions"),
-- which spec/buy_purchase_wiring_spec.lua pins against this file's source text.
--
-- Presentation is the Sold tab's (UI/SoldFrame.lua): one COLUMNS table driving both the
-- header row and every pooled row, responsive column drop in a declared priority order,
-- zebra/hover through the engine's own HIGHLIGHT layer. Duplicated rather than shared -- as
-- Sold duplicates it from Deals -- because these locals do not cross files.
GC.Buy = {}

local Theme
local container, content
local rows = {}
local geometry
local band

-- The BuyRun object for the run currently on screen (nil until one is picked), the
-- `updatedAt` of the AppRuns run it was built from (see ensureRun), and the itemID -> count
-- map the bags half of `haveOf` reads. Module-local so the whole file agrees on one answer.
local current, currentUpdatedAt
local bagStock = {}

-- The walk covers exactly the bags: the backpack and the five carried bags. The banks are
-- counted too (haveOf below) but never walked -- a bank has no container to walk until it is
-- opened -- so they are asked of the client's own count API instead.
local BUY_BAGS = { 0, 1, 2, 3, 4, 5 }

-- Not a translatable string: a glyph standing in for a number nobody has measured yet.
local EM_DASH = "—"

local BD = {
  BAND_HEIGHT = 44, -- header band: the run picker + two text lines above the table
  HEADER_H = 16,    -- column header row height, matches Deals' CH.HEADER
  -- How long a NOW price is allowed to stand before this tab asks again. Twenty seconds is
  -- the shopping rhythm, not a network budget: the batch costs one throttled message, and a
  -- player working down a run is buying a line every ten to thirty seconds, so anything much
  -- longer has them clicking BUY against a price the board learned two purchases ago.
  REFRESH_SECONDS = 20,
  -- Blizzard's hard ceiling for one SearchForItemKeys call (Core/KeyPoll.lua's MAX_BATCH); a
  -- run longer than this loses its tail rather than disconnecting the client.
  MAX_KEYS = 100,
  -- How long a quote may stand before a click has to ask again. Much shorter than the board's
  -- twenty seconds on purpose: NOW is a number to read, a quote is a number to SPEND, and the
  -- ladder a purchase is planned against goes stale the moment somebody else buys off it.
  QUOTE_SECONDS = 10,
  -- How long to wait for the client to answer a started purchase before giving the shared slot
  -- back. A commodity purchase that produces no terminal event would otherwise hold the slot
  -- for GC.PurchaseSlot.MAX_SECONDS with the board saying nothing.
  WATCHDOG_SECONDS = 10,
  -- The same fail-safe for the two stages that are waiting on a person rather than on the
  -- server: longer, because reading a price and clicking is a human act. It is NOT what keeps
  -- the attempt inside GC.PurchaseSlot.MAX_SECONDS -- these timers are armed from now, so a
  -- click at t+19 would be watched until t+39 against a claim stamped at t. armStall re-stamps
  -- the claim on every arming, which is what actually holds the two together.
  CONFIRM_SECONDS = 20,
  -- Deep commodity books run to thousands of price levels and a purchase only ever walks as far
  -- as the cap lets it; the same bound UI/SniperFrame.lua's commodityBook uses.
  MAX_LEVELS = 60,
  LOG_LINES = 20,
  -- How long a stranded confirm is worth keeping. GC.Sniper's _strandedConfirmed uses the same
  -- ten minutes for the same reason: long enough for a server that is merely slow, short enough
  -- that a record cannot still be sitting there when an unrelated purchase of the same item
  -- turns up and gets credited with it.
  STRANDED_SECONDS = 600,
}

-- When the last batch's answer landed. Zero means "never", which is what makes the first ask
-- on Show() free. Advanced by FoldRefresh alone, not by the send: a batch the client swallowed
-- leaves this where it was, so the next tick retries instead of waiting out a refresh window
-- for prices that never arrived.
local lastRefreshAt = 0
-- The last quote per item: what the cheapest lots actually add up to, kept BD.QUOTE_SECONDS so
-- the COST cell does not snap back to the floor estimate the moment the cursor leaves the row.
local quotes = {}

-- One purchase attempt at a time, addon-wide, and it lives on GC.Buy rather than on a row:
-- rows are pooled and repainted, so a row holding the attempt would hand it to whatever line
-- the next render happened to put at that index. `stage` is the whole machine --
--
--   quoting -> quoted -> started -> confirm -> confirming -> (cleared, on success)
--                           |          |
--                           |          +-> requote   the server's price left the line's cap
--                           +-> failed | expired
--
-- -- and every terminal handler checks it before acting, because a commodity event carries no
-- attempt id (Core/PurchaseSlot.lua) and Core/Init.lua routes one here on ownership alone.
-- `_focus` is the line Enter would buy; `_log` is the last BD.LOG_LINES attempts, for `/gc buy`.
GC.Buy._attempt = nil
GC.Buy._focus = nil
GC.Buy._log = {}

-- What outlives an attempt: confirms that reached the server and were then given up on (see
-- retireStalled). The success may still be coming, and when it does this is the only record of
-- what was bought and for how much -- GC.Sniper keeps exactly such a table, for exactly this, in
-- _strandedConfirmed. Keyed by itemID, because a player can strand one line and carry on down the
-- run: a single slot let the second strand overwrite the first, and the first one's late success
-- was then booked as the wrong item at the wrong price. Good for the auction house session that
-- made it and no longer -- a late event cannot cross a session boundary.
--
--   itemID -> { qty, total, runCode, have, at, session }
--
-- `have` is the line's HAVE at the moment it was stranded: the warning on that line lifts
-- when that number moves, which is exactly what a delivery that really happened does to it.
GC.Buy._stranded = {}
local sessionToken = 0

-- Bumped per attempt so a watchdog armed for one purchase cannot retire the next, per recorded
-- purchase so two identical buys in the same second are still two acquisitions, and per ledger
-- row for the same reason -- a buy has no natural dedupe key.
local attemptSeq, acquisitionSeq, ledgerSeq = 0, 0, 0

-- The stages in which the client is holding a purchase of ours: no second attempt may start,
-- no hover may replace the quote, and the passive capture in Core/PurchaseCapture.lua must
-- stand down (GC.Buy.OwnsCommodityPurchase below).
local function inFlight(attempt)
  local stage = attempt and attempt.stage
  return stage == "started" or stage == "confirm" or stage == "confirming"
end

local function setColor(fontString, color)
  if fontString and color then
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  end
end

-- Mirrors SellFrame/SoldFrame's formatAmount: plain "65g24s" text, coin icons only below one
-- gold (icon escapes truncate mid-escape in clipped FontStrings).
local function formatAmount(amount)
  if amount == nil then return EM_DASH end
  if amount < 0 then return "-" .. formatAmount(-amount) end
  if amount >= 10000 then
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    if silver == 0 then return ("%dg"):format(gold) end
    return ("%dg%02ds"):format(gold, silver)
  end
  return GetCoinTextureString(amount)
end

-- Money as plain text, for a list the player copies out of the game. formatAmount's sub-gold
-- branch returns GetCoinTextureString, which is icon ESCAPES: they draw beautifully in a
-- FontString and come out of an EditBox as |TInterface\MoneyFrame\UI-CopperIcon:0|t.
local function plainAmount(amount)
  if type(amount) ~= "number" then return "" end
  local gold = math.floor(amount / 10000)
  local silver = math.floor((amount % 10000) / 100)
  local copper = amount % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = gold .. "g" end
  if silver > 0 then parts[#parts + 1] = silver .. "s" end
  if copper > 0 or #parts == 0 then parts[#parts + 1] = copper .. "c" end
  return table.concat(parts)
end

local COLUMNS = {
  { key = "reagent", flex = true, min = 140 },
  { key = "need",   w = 36, num = true, size = 11 },
  { key = "have",   w = 36, num = true, size = 11 },
  { key = "buy",    w = 36, num = true, size = 11, bold = true },
  { key = "now",    w = 66, num = true, size = 11, optional = true },
  { key = "usual",  w = 66, num = true, size = 11, optional = true },
  { key = "cost",   w = 72, num = true, size = 11 },
  { key = "action", w = 80, center = true },
}

-- Already uppercase in the key, and never passed through :upper() -- Lua's upper is byte-wise
-- and would leave every non-ASCII letter in a translated heading alone, coming back half-cased.
-- Keys, not translations: this table is built at FILE SCOPE and GC.L only resolves once
-- ApplyLocale has run at ADDON_LOADED, so headerText() below looks up where the header is
-- actually built.
-- @localised-keys: literals in this table ARE GC.L keys; see the comment above for why the
-- lookup happens where the table is read rather than where it is built. The table has to close
-- with a `}` on its own line -- that is where the spec's scanner stops.
local HEADER_TEXT = {
  reagent = "REAGENT", need = "NEED", have = "HAVE", buy = "BUY",
  now = "NOW", usual = "USUAL", cost = "COST", action = "ACTION",
}
local function headerText(key) return GC.L[HEADER_TEXT[key] or ""] end

-- Drop priority, spelled out rather than derived from COLUMNS' order (Sold derives it, and can
-- only because its optional columns happen to sit in priority order). USUAL goes first: it is
-- the reference price, and a shopper who has lost a column would rather keep NOW, which is
-- what the next click actually pays.
local OPTIONAL_KEYS, DROP_THRESHOLDS = { "usual", "now" }, { 130, 100 }

-- Anchors every visible fixed COLUMNS entry's RIGHT edge right-to-left off `host`'s own RIGHT
-- edge, skipping any key present in `hidden`; returns the flex ("reagent") column's anchor pair.
-- Identical in shape to SoldFrame's/SniperFrame's anchorColumns.
local function anchorColumns(host, hidden, cellFor)
  local prev, prevPoint = host, "RIGHT"
  local flexAnchor
  for i = #COLUMNS, 1, -1 do
    local col = COLUMNS[i]
    if col.flex then
      flexAnchor = { frame = prev, point = prevPoint }
    else
      local cell = cellFor(col)
      if hidden[col.key] then
        cell:Hide()
      else
        cell:Show()
        cell:ClearAllPoints()
        cell:SetWidth(col.w)
        if prevPoint == "RIGHT" then
          cell:SetPoint("RIGHT", prev, "RIGHT")
        else
          cell:SetPoint("RIGHT", prev, "LEFT", -Theme.pad.s, 0)
        end
        prev, prevPoint = cell, "LEFT"
      end
    end
  end
  return flexAnchor
end

local function fixedColumnBudget(hidden)
  local sum, visible = 0, 0
  for _, col in ipairs(COLUMNS) do
    if not col.flex and not hidden[col.key] then
      sum = sum + col.w
      visible = visible + 1
    end
  end
  return sum + visible * Theme.pad.s
end

local function computeHidden(containerWidth)
  local hidden = {}
  for i, key in ipairs(OPTIONAL_KEYS) do
    local reagentWidth = containerWidth - fixedColumnBudget(hidden)
    if reagentWidth < DROP_THRESHOLDS[i] then
      hidden[key] = true
    end
  end
  return hidden
end

local function sameHidden(a, b)
  for _, key in ipairs(OPTIONAL_KEYS) do
    if (not a[key]) ~= (not b[key]) then return false end
  end
  return true
end

local hiddenColumns = {}

local createRow, layoutRow, headerLayout

local function applyColumnVisibility(containerWidth)
  if not headerLayout then return end
  local newHidden = computeHidden(containerWidth)
  if sameHidden(newHidden, hiddenColumns) then return end
  hiddenColumns = newHidden
  headerLayout()
  for i = 1, #rows do layoutRow(rows[i]) end
end

-- ---------------------------------------------------------------------------
-- The run, and what only the client knows about it
-- ---------------------------------------------------------------------------

local function settings()
  local db = GC.db
  local s = type(db) == "table" and db.settings or nil
  local sniper = type(s) == "table" and s.sniper or nil
  return type(sniper) == "table" and sniper or nil
end

-- The caps a run menu offers. Whole percents of the run's own reference price, coarse on
-- purpose: this is a decision about how much of a hurry the player is in, not a dial.
local CAP_CHOICES = { 100, 110, 120, 130, 150, 200, 300 }

-- The global cap from Settings, clamped at the READ. UI/SettingsFrame.lua bounds the box on
-- commit, which says nothing about what is already in SavedVariables: a hand-edited file, or one
-- written before the bound existed, hands this a 900 that would quietly triple the cap every
-- purchase is judged against -- and a non-number would error inside Refresh() on every render,
-- taking the whole tab down.
local function globalCapPct()
  local sniper = settings()
  local value = tonumber(sniper and sniper.buyCapPct)
  if not value then return 130 end
  return math.max(100, math.min(300, math.floor(value)))
end

-- The cap this run is actually judged against: its own if it has been given one, the global
-- otherwise. Same clamp, for the same reason.
local function runCapPct(code)
  local db = GC.db
  local caps = type(db) == "table" and db.runCaps or nil
  local value = type(caps) == "table" and code and tonumber(caps[code]) or nil
  if not value then return globalCapPct() end
  return math.max(100, math.min(300, math.floor(value)))
end

local function setRunCapPct(code, pct)
  local db = GC.db
  if type(db) ~= "table" or type(code) ~= "string" or code == "" then return end
  if type(db.runCaps) ~= "table" then db.runCaps = {} end
  db.runCaps[code] = pct
end

-- The lines of a run the player has chosen to craft instead of buy: GC.db.runSplits[code][itemID].
-- Beside the run rather than on it, for the same reason the cap is (see the DRIVER below): a run
-- from the companion is replaced wholesale on every sync. Only ever CREATES the tables when a
-- write needs them -- the read runs on every render, and an empty table written per run code
-- would be SavedVariables growing a row for every run the player ever opened.
local function splitsFor(code, create)
  local db = GC.db
  if type(db) ~= "table" or type(code) ~= "string" or code == "" then return nil end
  if type(db.runSplits) ~= "table" then
    if not create then return nil end
    db.runSplits = {}
  end
  local set = db.runSplits[code]
  if type(set) ~= "table" then
    if not create then return nil end
    set = {}
    db.runSplits[code] = set
  end
  return set
end

-- Marks one line of a run as crafted rather than bought, or clears it. Clearing REMOVES the
-- entry rather than storing false, so a line the player put back leaves nothing behind in
-- SavedVariables to explain later -- the same rule SetArchived follows.
local function setSplit(code, itemID, split)
  local set = splitsFor(code, split and true or false)
  if not set then return end
  set[itemID] = split and true or nil
end

-- Bag stock, from the same C_Container walk UI/SellFrame.lua's scanBagStock uses. The classify
-- hook is deliberately NOT Sell's: Sell has to tell a commodity from a bonus-id bearing item
-- because it posts them differently, and returns nil -- dropping the stack -- when it cannot.
-- This tab only ever asks "how many of item N am I already carrying", so it keys on the item id
-- alone; borrowing Sell's rule would silently under-count every stack the auction house API has
-- not classified yet and send the player shopping for what is already in the bag.
local function scanBags()
  bagStock = {}
  if not GC.BagStock then return end
  local entries = GC.BagStock.Scan({
    numSlots = function(bag)
      return C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
    end,
    itemInfo = function(bag, slot)
      if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if type(info) ~= "table" then return nil end
      return {
        itemID = info.itemID, stackCount = info.stackCount,
        -- isBound is deliberately dropped, not forwarded. GC.BagStock.Scan skips a bound stack
        -- because the auction house refuses to POST it (Core/BagStock.lua) -- a Sell rule. This
        -- tab asks a different question: a soulbound reagent sitting in the bags is still a
        -- reagent the player does not have to buy, and crafting does not care how it got bound.
        -- Forwarding the flag made HAVE under-count and sent the player shopping for what they
        -- were already carrying.
        isBound = nil,
        hasNoValue = info.hasNoValue, itemName = info.itemName,
        hyperlink = info.hyperlink
          or (C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bag, slot)) or nil,
      }
    end,
    classify = function(itemID) return ("buy:%d"):format(itemID), nil end,
  }, BUY_BAGS)
  -- Folded into itemID -> count here, once per scan, rather than re-walked per line: `haveOf`
  -- is called for every line of every Refresh(), and a run is dozens of lines long.
  for _, entry in ipairs(entries) do
    bagStock[entry.itemID] = (bagStock[entry.itemID] or 0) + (entry.quantity or 0)
  end
end

-- The count the client keeps for an item across everything the flags ask about. Two shapes of
-- the same call: modern clients carry it on C_Item, older ones as a bare global. Neither, or one
-- that throws, answers nil -- the caller then keeps the bags rather than losing them.
local function itemCount(itemID, includeBank, includeReagentBank, includeAccountBank)
  local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
  if type(fn) ~= "function" then return nil end
  local ok, count = pcall(fn, itemID, includeBank, false, includeReagentBank, includeAccountBank)
  if not ok or type(count) ~= "number" then return nil end
  return count
end

-- Everything the player owns minus what they are carrying: the character bank, the reagent bank
-- and the warband bank together. Subtracted rather than asked for directly because the client
-- has no "bank only" question, and floored at zero because two counts taken a moment apart can
-- disagree -- a negative here would take stock out of the bags the walk just found.
--
-- Known limit: the client only knows what a bank holds once that bank has been opened on this
-- character, so a fresh login can report nothing for stock that is really there. It under-counts
-- HAVE and never over-counts it, which is the safe direction for a shopping list.
local function bankOf(itemID)
  local owned = itemCount(itemID, true, true, true)
  local carried = itemCount(itemID, false, false, false)
  if not owned or not carried then return 0 end
  local bank = owned - carried
  return bank > 0 and bank or 0
end

-- bags, bank -- the row tooltip is the one place the two halves are said apart.
local function haveSplit(itemID)
  return bagStock[itemID] or 0, bankOf(itemID)
end

local function haveOf(itemID)
  local bags, bank = haveSplit(itemID)
  return bags + bank
end

local function usualUnit(itemID)
  local value = GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(itemID)
  return type(value) == "table" and value.mv or nil
end

local DRIVER = {
  now = function() return time() end,
  haveOf = haveOf,
  usualUnit = usualUnit,
  -- A run's own cap when it has been given one in the run menu, the global setting otherwise,
  -- clamped at the read either way (see runCapPct/globalCapPct above).
  capPct = runCapPct,
  -- Which of this run's lines are being crafted rather than bought. Asked on every Refresh,
  -- unlike progress: the row menu writes it and re-renders, and the answer has to be current.
  splits = function(code) return splitsFor(code) end,
  -- The run's score, per character and per run code, in SavedVariables: GC.db.buyProgress
  -- ["Name-Realm"][code][itemID] = { bought, spent, boughtAt }. The spec's rule is "the addon
  -- keeps HAVE/spent per character"; without this a /reload read as a run nobody had bought
  -- anything for, while the gold was already gone.
  progress = function(code)
    local db = GC.db
    if type(db) ~= "table" or type(code) ~= "string" or code == "" then return nil end
    local context = GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
    local char = context and context.char or "?"
    db.buyProgress = type(db.buyProgress) == "table" and db.buyProgress or {}
    local mine = db.buyProgress[char]
    if type(mine) ~= "table" then mine = {}; db.buyProgress[char] = mine end
    local forRun = mine[code]
    if type(forRun) ~= "table" then forRun = {}; mine[code] = forRun end
    return forRun
  end,
  freeLines = function()
    return GC.AppRuns and GC.AppRuns.FreeLines and GC.AppRuns.FreeLines() or nil
  end,
}

local function runList()
  return (GC.AppRuns and GC.AppRuns.List and GC.AppRuns.List()) or {}
end
local openRunMenu -- defined after cycleRun; the band's picker is the only caller

-- The run's own name if the site gave it one, otherwise its code -- never an invented label.
local function runLabel(run)
  return (run and (run:Name() or run:Code())) or ""
end

function GC.Buy.CurrentRun() return current end

-- Adopts `code` as the shown run and remembers it. A code with no run behind it (the companion
-- dropped it on its next sync, or the saved preference outlived the run) clears the board
-- rather than resurrecting a stale copy.
function GC.Buy.SelectRun(code)
  local run = code and GC.AppRuns and GC.AppRuns.Get and GC.AppRuns.Get(code) or nil
  local sniper = settings()
  -- A new BuyRun object carries no floors at all, so the twenty-second window that was
  -- protecting the OLD run's prices is now protecting nothing -- it would just hold every NOW
  -- cell on an em dash for up to twenty seconds after a cycle-run click or a companion sync
  -- that rebuilt the run under ensureRun(). The window belongs to a run's prices, not to the
  -- tab, so it is given up with them. Reset before the early return too: clearing the board is
  -- just as much a replacement, and the next run picked must not inherit a stale window.
  lastRefreshAt = 0
  -- A quote is a plan against one run's lines. A purchase already in the client's hands keeps
  -- its attempt -- its terminal event still has to land somewhere, and OnCommodityPurchaseSucceeded
  -- checks the run code before it credits anything to a line.
  if not inFlight(GC.Buy._attempt) then GC.Buy._attempt, GC.Buy._focus = nil, nil end
  if not run then
    current, currentUpdatedAt = nil, nil
    if sniper then sniper.buyRun = nil end
    return
  end
  if sniper then sniper.buyRun = run.code end
  current = GC.BuyRun.New(run, DRIVER)
  currentUpdatedAt = run.updatedAt
  current:Refresh()
end

-- Picks up the remembered run, falling back to the first the list offers (app runs first,
-- newest first -- Core/AppRuns.lua's own order), so a first visit lands on something rather
-- than on the empty state with runs sitting right there.
-- Returns whether it (re)built `current`, so Show() can skip a second Refresh() of a run that
-- was just built and refreshed.
local function ensureRun()
  local list = runList()
  if #list == 0 then
    current, currentUpdatedAt = nil, nil
    return false
  end
  local sniper = settings()
  local wanted = sniper and sniper.buyRun
  for _, run in ipairs(list) do
    if run.code == wanted then
      -- Already on it: keep the BuyRun object rather than rebuilding it, so what this session
      -- has already bought against the run survives leaving the tab and coming back.
      --
      -- A run keeps its code across a companion sync while its LINES change (the site's list
      -- was edited, quantities moved), so the code alone does not prove the object is current.
      -- `updatedAt` does -- Core/AppRuns.lua stamps it on every adopted run -- and a newer one
      -- means the object was built from lines that no longer exist. Rebuilding drops this
      -- session's recorded purchases against the old lines, deliberately: they were counted
      -- against quantities the run no longer asks for, and carrying them over would credit
      -- the new lines with buys that were never made for them.
      if not (current and current:Code() == wanted)
          or (run.updatedAt or 0) > (currentUpdatedAt or 0) then
        GC.Buy.SelectRun(run.code)
        return true
      end
      return false
    end
  end
  -- The remembered run is gone (the companion dropped it on its last sync, or it was never
  -- there): fall to the top of the list rather than to the empty state with runs sitting in it.
  GC.Buy.SelectRun(list[1].code)
  return true
end

-- The picker is a cycle, not a dropdown: a player has one or two runs open at a time, and a
-- button that names the next one is a smaller control than a menu for a list that short.
local function cycleRun()
  local list = runList()
  if #list == 0 then return end
  local index = 1
  for i, run in ipairs(list) do
    if current and run.code == current:Code() then
      index = i % #list + 1
      break
    end
  end
  -- One run in the list cycles back onto itself: re-selecting would rebuild the BuyRun object
  -- and forget what this session has already bought against it, for a click that changed
  -- nothing the player can see.
  if current and list[index].code == current:Code() then return end
  GC.Buy.SelectRun(list[index].code)
end

-- Drops the shown run and moves to the next one the addon still holds (or clears the board).
-- Only a pasted run is removable here: an "app" run is the companion's mirror of a list on
-- goldcap.gg and would be back on the next sync, so it is removed where it lives.
local function removeCurrentRun()
  if not (current and GC.AppRuns and GC.AppRuns.Remove) then return end
  local code = current:Code()
  if not GC.AppRuns.Remove(code) then return end
  local list = runList()
  GC.Buy.SelectRun(list[1] and list[1].code or nil)
  GC.Buy.RefreshIfShown()
end

-- Puts the shown run away and moves to the next one still on offer (or clears the board).
-- Offered for any run, unlike removal: an "app" run is the companion's mirror of a list on
-- goldcap.gg and comes back on the next sync, and this flag is exactly how a finished one is
-- told to stay out of the picker anyway. A no-op while a purchase is in flight -- belt and
-- braces alongside the menu guard below, since `current` moves on and the in-flight purchase's
-- gold would then book against a run it can no longer see (Finding 1).
local function archiveCurrentRun()
  if inFlight(GC.Buy._attempt) then return end
  if not (current and GC.AppRuns and GC.AppRuns.SetArchived) then return end
  if not GC.AppRuns.SetArchived(current:Code(), true) then return end
  local list = runList()
  GC.Buy.SelectRun(list[1] and list[1].code or nil)
  GC.Buy.RefreshIfShown()
end

local function runMenuLabel(run)
  local name = run.name or run.code or "?"
  local count = type(run.lines) == "table" and #run.lines or 0
  local origin = run.origin == "paste" and GC.L["pasted"] or "goldcap.gg"
  local mark = (current and current:Code() == run.code) and "• " or "   "
  return ("%s%s  ·  %s  ·  %s"):format(mark, name, (GC.L["%d lines"]):format(count), origin)
end

-- The run picker's menu: every live run, the current one marked, then this run's cap, archive
-- and remove / paste, and last what has been archived. Returns false when the client has no
-- MenuUtil, so the caller can fall back to cycling.
openRunMenu = function(owner)
  local menu = _G.MenuUtil
  if not (menu and menu.CreateContextMenu) then return false end
  local list = runList()
  menu.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(GC.L["Runs"])
    for _, run in ipairs(list) do
      local code = run.code
      root:CreateButton(runMenuLabel(run), function()
        GC.Buy.SelectRun(code)
        GC.Buy.RefreshIfShown()
      end)
    end
    root:CreateDivider()
    local shown = current and GC.AppRuns and GC.AppRuns.Get and GC.AppRuns.Get(current:Code()) or nil
    -- A purchase in flight has already committed to this run's `current`: re-capping the lines
    -- or archiving out from under it is exactly the hole Finding 1 describes (`settlePurchase`
    -- would book the gold nowhere a bought-count can see it). Runs/remove/paste are unaffected.
    if shown and not inFlight(GC.Buy._attempt) then
      local code = shown.code
      -- MenuUtil's own submenu shape: an element description with children added to it displays
      -- as one (Blizzard's Menu implementation guide), and CreateRadio(text, isSelected,
      -- setSelected, data) is the same triple UI/SettingsFrame.lua's language picker hands to
      -- CreateRadioContextMenu. The title carries the cap the run is judged against right now,
      -- so a run using the global one still reads as capped rather than as unset.
      local capMenu = root:CreateButton((GC.L["Cap: %d%%"]):format(runCapPct(code)))
      if capMenu and capMenu.CreateRadio then
        for _, pct in ipairs(CAP_CHOICES) do
          capMenu:CreateRadio(("%d%%"):format(pct),
            function(value) return runCapPct(code) == value end,
            function(value)
              setRunCapPct(code, value)
              GC.Buy.RefreshIfShown()
            end, pct)
        end
      end
      root:CreateButton(GC.L["Archive this run"], archiveCurrentRun)
    end
    if shown and shown.origin == "paste" then
      root:CreateButton(GC.L["Remove this run"], removeCurrentRun)
    elseif shown then
      root:CreateTitle(GC.L["From goldcap.gg — remove it there"])
    end
    root:CreateButton(GC.L["Paste a run..."], function()
      if GC.UI and GC.UI.ShowImportDialog then GC.UI.ShowImportDialog() end
    end)
    -- What has been put away, under its own divider: a run leaves the picker but not the addon,
    -- and this is the only way back to it.
    local archivedRuns = (GC.AppRuns and GC.AppRuns.List and GC.AppRuns.List({ archived = true })) or {}
    if #archivedRuns > 0 then
      root:CreateDivider()
      root:CreateTitle(GC.L["Archived"])
      for _, archivedRun in ipairs(archivedRuns) do
        local code = archivedRun.code
        root:CreateButton((GC.L["Restore %s"]):format(archivedRun.name or code), function()
          if GC.AppRuns.SetArchived then GC.AppRuns.SetArchived(code, false) end
          GC.Buy.SelectRun(code)
          GC.Buy.RefreshIfShown()
        end)
      end
    end
  end)
  return true
end

-- The client's own name for the line's item. A run from the companion carries one; a pasted
-- GCR1 string carries none (Core/AppRuns.lua's ImportString), and an item the client has never
-- cached answers nothing at all -- so the id itself is the last honest fallback.
local function lineName(line)
  if line.name then return line.name end
  if C_Item and C_Item.GetItemInfo then
    local ok, name = pcall(C_Item.GetItemInfo, line.itemID)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return "#" .. tostring(line.itemID)
end

-- A line this tab can actually spend gold on. Everything else -- a vendor stop, a line the bags
-- already cover, a line past the free limit, a line being crafted rather than bought -- has no
-- BUY button and never gets quoted.
local function buyable(line)
  return line ~= nil and not line.vendor and line.kind ~= "craft"
    and not line.locked and not line.done and line.buy > 0
end

local function lineFor(itemID)
  if not (current and itemID) then return nil end
  for _, line in ipairs(current:Lines()) do
    if line.itemID == itemID then return line end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Buying: the quote, and the attempt it becomes
-- ---------------------------------------------------------------------------

-- The live stranded record covering this line, if the warning on it still stands. Read at hover
-- and at render time rather than stamped onto an attempt: an attempt is replaced by the very next
-- hover, and a warning a hover can erase is a warning that WILL be erased -- with a live BUY
-- button under it, one click from buying the same units a second time.
local function strandedFor(line)
  if not line then return nil end
  local record = GC.Buy._stranded[line.itemID]
  if not record then return nil end
  if record.session ~= sessionToken or (time() - (record.at or 0)) > BD.STRANDED_SECONDS then
    GC.Buy._stranded[line.itemID] = nil
    return nil
  end
  -- Released on evidence, not on a timer. The record itself is kept -- a late success still has
  -- to be bookable -- but the line stops being one the player may not touch.
  if record.have ~= nil and line.have ~= record.have then return nil end
  return record
end

-- Whether a click on this line would do anything at all -- what the Enter key has to know before
-- it decides to swallow the keystroke rather than hand it back to the game. A line waiting for
-- its confirming click counts even though its own BUY quantity may already be spoken for. A line
-- under a stranded confirm never does: its button is disabled (actionLabel), and Enter has to
-- agree with the button -- swallowed, the keystroke did nothing, and it reached onBuyClick for a
-- line the player may not touch.
local function actionable(line)
  if not line then return false end
  if strandedFor(line) then return false end
  local attempt = GC.Buy._attempt
  if attempt and attempt.itemID == line.itemID and attempt.stage == "confirm" then return true end
  return buyable(line)
end

local function quoteFresh(attempt)
  return attempt ~= nil and attempt.stage == "quoted" and attempt.quotedAt ~= nil
    and (time() - attempt.quotedAt) < BD.QUOTE_SECONDS
end

-- A question already on the wire, and still worth waiting for. The client drops a throttled
-- search without a word (AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED is the only hint, and it names
-- nothing), so a `quoting` stage with no answer has to age out the same way a quote does -- or
-- the line sits on "quoting..." for the rest of the session, refusing to ask again.
local function quotePending(attempt)
  return attempt ~= nil and attempt.stage == "quoting"
    and (time() - (attempt.askedAt or 0)) < BD.QUOTE_SECONDS
end

-- What the line's own button says right now, whether it is clickable, and -- for the one state
-- that needs a look of its own -- which Theme variant to wear. One function so the render, the
-- Enter key and the attempt log can never disagree about what state a line is in.
-- Returns label, enabled, variant (nil variant means "the focus-driven default").
local function actionLabel(line)
  local attempt = GC.Buy._attempt
  local resting = (GC.L["BUY %d"]):format(line.buy)
  -- Ahead of everything, including a fresh quote for some other line: a confirm reached the
  -- server for THIS item and nothing came back, so the units may already be paid for. Retail
  -- auction house purchases are DELIVERED AS MAIL (Core/Ledger.lua reads them as "Auction won"
  -- invoices), so the mailbox, not the bags, is where the player finds out whether it happened.
  if strandedFor(line) then return GC.L["no answer — check your mail"], false end
  if not attempt or attempt.itemID ~= line.itemID then
    -- Some other line is mid-purchase. A click here cannot start a second one (onBuyClick and
    -- quote both refuse while the client holds a purchase of ours), so the button says so
    -- rather than reading "BUY n", enabled, and doing nothing at all when it is pressed.
    if inFlight(attempt) then return resting, false end
    return resting, true
  end
  local stage = attempt.stage
  -- A question still worth waiting for says so. One the client swallowed has to offer the click
  -- that asks again, or the row reads "quoting..." -- greyed out -- for the rest of the session.
  if stage == "quoting" then
    if quotePending(attempt) then return GC.L["..."], false end
    return resting, true
  end
  if stage == "quoted" then
    -- The client will not sell this item as a commodity, so there is no book to quote and no
    -- quantity this tab could buy in one click. Saying "nothing on offer" about a lot list that
    -- is full is the one thing worse than saying nothing: it is a false claim about the market.
    if attempt.byHand then return GC.L["not a commodity — buy by hand"], false end
    if (attempt.qty or 0) > 0 then
      -- A partial fill: the cap stopped the ladder part-way, so what is on the button is real
      -- but it is not the whole line. The label stays short enough for the 72px badge and the
      -- button wears the over-cap look; how far over the rest sits is on the log line
      -- OnCommodityResults writes, which is what `/gc buy` prints.
      return (GC.L["BUY %d"]):format(attempt.qty), true, attempt.capped and "warn" or nil
    end
    -- Nothing under the cap. The percentage is the honest reason -- "this costs half again what
    -- it usually does" is a decision the player can make; a greyed-out button is not.
    if attempt.overPct then
      return (GC.L["▲%d%% over usual"]):format(attempt.overPct), false, "warn"
    end
    return GC.L["nothing on offer"], false
  end
  if stage == "started" then return GC.L["buying..."], false end
  if stage == "confirm" then
    return GC.L["CONFIRM"], true
  end
  if stage == "confirming" then return GC.L["confirming..."], false end
  if stage == "requote" then
    return (GC.L["price moved to %s"]):format(formatAmount(attempt.movedTotal)), true
  end
  if stage == "expired" then return GC.L["took too long — try again"], true end
  -- Confirm reached the server and nothing came back. Not offered as a retry: the units may
  -- already be paid for, and the mailbox is where the answer is -- an auction house purchase is
  -- delivered as "Auction won" mail, so the bag re-count only settles it once that mail is taken.
  if stage == "unknown" then return GC.L["no answer — check your mail"], false end
  if stage == "failed" then return GC.L["purchase failed — try again"], true end
  return resting, true
end

-- The last BD.LOG_LINES things an attempt did, so `/gc buy` can answer "what happened when I
-- clicked" without a screenshot. `text` defaults to whatever the button is saying, which is
-- already through GC.L and already the shortest true description of the stage.
local function logAttempt(line, text, itemID)
  local attempt = GC.Buy._attempt
  local log = GC.Buy._log
  itemID = (line and line.itemID) or itemID or (attempt and attempt.itemID) or nil
  log[#log + 1] = {
    at = time(),
    itemID = itemID,
    stage = attempt and attempt.stage or nil,
    qty = attempt and attempt.qty or nil,
    total = attempt and (attempt.serverTotal or attempt.total) or nil,
    -- The id is the last honest name. A line that has gone -- the run was swapped under the
    -- purchase -- used to print as "?", which is the one thing `/gc buy` exists not to say.
    text = ("%s · %s"):format(
      (line and lineName(line)) or (itemID and ("#" .. tostring(itemID))) or "?",
      text or (line and actionLabel(line)) or ""),
  }
  while #log > BD.LOG_LINES do table.remove(log, 1) end
end

-- Prunes the table of everything the current session can no longer answer for, and says how much
-- is left. Same shape and the same ten-minute bound as GC.Sniper's takeStrandedConfirmed.
local function liveStranded()
  local records = GC.Buy._stranded
  local found, count = nil, 0
  local now = time()
  for itemID, record in pairs(records) do
    if record.session ~= sessionToken or (now - (record.at or 0)) > BD.STRANDED_SECONDS then
      records[itemID] = nil
    else
      found, count = itemID, count + 1
    end
  end
  return count, found
end

-- Whether this tab is holding a stranded confirm of its own. The Sniper asks before IT books a
-- terminal event nothing else owns (UI/SniperFrame.lua's three no-pending branches): a commodity
-- event carries no attempt identifier, so with a record on both sides the event is nobody's to
-- take -- the same fail-closed answer mayOwnTerminal gives when the Sniper is the one holding
-- one. Asking never consumes a record; liveStranded does prune records that have expired or
-- belong to an earlier session, which is the same ageing the Sniper's mirror applies.
function GC.Buy.HasStranded() return (liveStranded()) > 0 end

-- The one record a terminal event can honestly be attributed to, consumed. A commodity event
-- carries no attempt id, so with two of them live attribution is a guess: they are ALL dropped and
-- nothing is recorded -- the same fail-closed answer the Sniper gives, and a better one than an
-- acquisition for a purchase that may never have happened. Returns record, consumed.
local function takeStranded()
  local count, itemID = liveStranded()
  if count == 0 then return nil, false end
  if count > 1 then
    GC.Buy._stranded = {}
    logAttempt(lineFor(itemID), GC.L["a purchase landed that GoldCap could not attribute"], itemID)
    GC.Buy.RefreshIfShown()
    return nil, true
  end
  local record = GC.Buy._stranded[itemID]
  GC.Buy._stranded[itemID] = nil
  record.itemID = itemID
  return record, true
end

-- Whether a terminal commodity event is BUY's to answer at all. Core/Init.lua offers all four to
-- this tab first and only passes them on when it says no, so this is the whole boundary between
-- the two windows that can own a purchase.
--
-- Holding the slot is the ordinary answer. A stranded record is the other one: the purchase that
-- left it RELEASED the slot on its way out, so an event gated on ownership alone could never
-- reach the branch that books it. What a stranded record may never do is take an event from
-- somebody who is holding the slot -- that purchase owns its own terminals. ANY claim of theirs,
-- not only one IsBusy still reports: the Sniper claims once at its buy click and never re-stamps,
-- so its own success can land past GC.PurchaseSlot.MAX_SECONDS with the claim still in place, and
-- a stranded record here would have taken it.
--
-- Nor may it take one when the Sniper holds a stranded confirm of its own. A commodity event
-- carries nothing that could say which window's it is, so with a record on both sides the answer
-- is the same fail-closed no that two records of this tab's own get from takeStranded.
local function mayOwnTerminal()
  if GC.PurchaseSlot then
    local owner = GC.PurchaseSlot.Owner()
    if owner == "buy" then return true end
    if owner ~= nil then return false end
  end
  if GC.Sniper and GC.Sniper.HasStrandedConfirmed and GC.Sniper.HasStrandedConfirmed() then
    return false
  end
  return (liveStranded()) > 0
end

-- Defined with the NOW refresh at the foot of this file (it is the same question a keys batch
-- asks), declared here because the quote path needs it too: an item the client will not sell as
-- a commodity has no commodity book, and telling the two apart is what keeps this tab from
-- reporting an empty market for a lot list that is full.
local askableItem

-- The client's single commodity buffer read as a price ladder: cheapest level first, in the
-- { unit, qty } shape Core/BuyRun.lua's PurchaseQuantity walks. Level 1 is the probe -- a nil
-- there means the buffer is holding some other item's book entirely, which is the only way this
-- tab can tell its own answer from whatever the last search left behind.
--
-- The player's own units come out of every level: nobody can buy their own auction, so a plan
-- built on them fills from stock that will never be sold. Same subtraction, same reason, as
-- UI/SniperFrame.lua's commodityBook and GC.SellPositions.CheapestCompetingUnit.
local function ladderFor(itemID)
  if not (C_AuctionHouse and C_AuctionHouse.GetNumCommoditySearchResults
      and C_AuctionHouse.GetCommoditySearchResultInfo) then return nil end
  local ok, first = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
  if not ok or type(first) ~= "table" then return nil end
  local count = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
  if count > BD.MAX_LEVELS then count = BD.MAX_LEVELS end
  local ladder = {}
  for i = 1, count do
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if type(info) == "table" and info.unitPrice then
      local mine = 0
      if type(info.numOwnerItems) == "number" then
        mine = info.numOwnerItems
      elseif info.containsOwnerItem == true then
        -- A level the client will not split counts as the player's own in full. On the buy side
        -- that errs towards seeing LESS stock than there is, which refuses a fill rather than
        -- planning one that cannot happen.
        mine = info.quantity or 0
      end
      local quantity = (info.quantity or 0) - mine
      if quantity > 0 then ladder[#ladder + 1] = { unit = info.unitPrice, qty = quantity } end
    end
  end
  if #ladder == 0 then return nil end
  return ladder
end

-- How far over the usual price the cheapest level the cap refused sits. Computed whenever the
-- cap stopped the ladder -- before the first unit or part-way through a partial fill.
local function overUsualPct(line, ladder)
  if not (line and line.usual and line.usual > 0 and line.cap) then return nil end
  for _, level in ipairs(ladder or {}) do
    if level.unit > line.cap then return math.floor(level.unit * 100 / line.usual) - 100 end
  end
  return nil
end

-- The site measures the cheap hour in UTC; a player reads realm time. The client knows both:
-- C_DateAndTime.GetCurrentCalendarTime() is realm time and date("!*t", GetServerTime()) is the
-- same instant in UTC, so their difference is this realm's offset. Without both there is no
-- offset to apply, and an hour in the wrong timezone is worse than no hour -- nil says nothing.
local function serverHour(utcHour)
  if type(utcHour) ~= "number" or utcHour ~= math.floor(utcHour)
      or utcHour < 0 or utcHour > 23 then return nil end
  if not (C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and GetServerTime and date) then
    return nil
  end
  local localOk, calendar = pcall(C_DateAndTime.GetCurrentCalendarTime)
  if not localOk or type(calendar) ~= "table" or type(calendar.hour) ~= "number" then return nil end
  local utcOk, utc = pcall(date, "!*t", GetServerTime())
  if not utcOk or type(utc) ~= "table" or type(utc.hour) ~= "number" then return nil end
  local offset = (calendar.hour - utc.hour) % 24
  return (utcHour + offset) % 24
end

-- "usually cheapest around 05:00 · -18%". A statement about the last fortnight of this region's
-- hourly history and nothing more: the word is "usually", never "will be". nil whenever the site
-- was not sure enough to send a figure, or the client cannot place the hour.
local function cheapHourText(line)
  if not line or type(line.cheapPct) ~= "number" or line.cheapPct >= 0 then return nil end
  local hour = serverHour(line.cheapHour)
  if not hour then return nil end
  return (GC.L["usually cheapest around %s · %d%%"])
    :format(("%02d:00"):format(hour), math.floor(line.cheapPct))
end

local function throttleReady()
  if GC.Util and GC.Util.ThrottleReady then return GC.Util.ThrottleReady() end
  return (C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady
    and C_AuctionHouse.IsThrottledMessageSystemReady()) or false
end

-- CancelCommoditiesPurchase fires NONE of the three terminal events (addon/AGENTS.md), so it is
-- only ever used to hand a started-but-unconfirmed purchase back to the client -- never to end
-- an attempt this tab is still waiting on an event for.
local function cancelStartedPurchase()
  if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
    C_AuctionHouse.CancelCommoditiesPurchase()
  end
end

local armStall, retireStalled

-- Re-armed for whatever the attempt has just become, not once at the start. EVERY post-start
-- stage needs a way out: `started` and `confirming` are waits on the server, `confirm` is a wait
-- on the player, and any of the three left un-timed holds the shared slot and keeps
-- GC.Buy.OwnsCommodityPurchase true -- which stands Core/PurchaseCapture.lua down for that item,
-- so the player's own ordinary auction-house buys of it stop being recorded, until /reload.
-- `stall` is bumped on every arming so only the newest timer of an attempt can fire.
armStall = function(attempt, seconds)
  -- The claim is re-stamped here, not only taken at the start. GC.PurchaseSlot expires a claim
  -- MAX_SECONDS after it was STAMPED, while these timers are armed from now: a confirm click at
  -- t+19 is watched until t+39 against a claim stamped at t, so from t+30 the Sniper could take
  -- the slot out from under a purchase this tab is still holding. Re-claiming by the current
  -- owner always succeeds and re-stamps (Core/PurchaseSlot.lua).
  if GC.PurchaseSlot then GC.PurchaseSlot.Claim("buy") end
  if not (C_Timer and C_Timer.After) then return end
  attempt.stall = (attempt.stall or 0) + 1
  local token, stall = attempt.token, attempt.stall
  C_Timer.After(seconds, function() retireStalled(token, stall) end)
end

-- What the player just bought, filed as cost: the addon's OWN basis, which never leaves the
-- client -- the same acquisitions path a hand-entered auction house cost takes
-- (Core/Acquisitions.lua). The site learns about the same purchase through the ledger row
-- recordLedgerBuy writes below; `runCode` rides on both, so either can say which shopping run
-- the gold went to.
local function recordAcquisition(itemID, name, qty, total, at, runCode)
  if not (GC.Acquisitions and GC.Acquisitions.Record and GC.Acquisitions.PositionKey) then return end
  local context = GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
  acquisitionSeq = acquisitionSeq + 1
  GC.Acquisitions.Record({
    source = "goldcap_buy",
    itemID = itemID,
    positionKey = GC.Acquisitions.PositionKey(itemID, nil, true),
    itemName = name,
    quantity = qty,
    total = total,
    acquiredAt = at,
    runCode = runCode,
    character = context and context.char or nil,
    region = context and context.region or nil,
    evidenceKey = ("goldcap-buy:%d:%d:%d"):format(itemID, at, acquisitionSeq),
  })
end

-- The same purchase, filed a second time where the site can see it. The acquisition above is the
-- addon's own cost basis and never leaves the client; a ledger row is what the companion
-- uploads, which is how goldcap.gg can say what a shopping run actually cost. `goldcap_buy` is a
-- source the site's API learned in 1.32 -- it ships before this addon version, deliberately, so
-- no player's upload can be rejected for carrying a source the server has not heard of.
--
-- No natural dedupe key exists (two identical buys a second apart are two real buys), so the key
-- carries a counter, exactly as GC.Ledger.RecordSniperBuy's does.
local function recordLedgerBuy(itemID, name, qty, total, at, runCode)
  if not (GC.Ledger and GC.Ledger.Append) then return end
  local context = GC.Ledger.Context and GC.Ledger.Context() or nil
  ledgerSeq = ledgerSeq + 1
  GC.Ledger.Append({
    key = "buyrun" .. "\1" .. itemID .. "\1" .. at .. "\1" .. ledgerSeq,
    kind = "buy",
    source = "goldcap_buy",
    itemID = itemID,
    itemName = name,
    qty = qty,
    total = total,
    cut = 0,
    deposit = 0,
    pending = false,
    runCode = runCode,
    at = at,
    char = context and context.char or nil,
    region = context and context.region or nil,
  })
end

-- The next line still worth buying, starting after `itemID` and wrapping -- so finishing the
-- last line of a run lands on the first one that is still open rather than on nothing.
local function nextOpenAfter(itemID)
  if not current then return nil end
  local lines = current:Lines()
  if #lines == 0 then return nil end
  local from = 0
  for i, line in ipairs(lines) do
    if line.itemID == itemID then from = i break end
  end
  for offset = 1, #lines do
    local line = lines[(from + offset - 1) % #lines + 1]
    if buyable(line) then return line.itemID end
  end
  return nil
end

-- Books one commodity purchase that really happened: against the run it was bought for, as cost
-- in the acquisition store, and as a ledger row for the site. Shared by the ordinary confirmed
-- path and by the late answer to an attempt the confirming timeout had already given up on --
-- the gold left the bags either way.
--
-- The run can be swapped or resynced while a purchase is in the air; crediting these units to
-- lines that were not what was bought against would be worse than not crediting them at all. The
-- cost itself is recorded regardless -- the gold moved and the items are real. The acquisition
-- and the ledger row are the same fact filed twice and are written in the one guard below, so
-- they can never disagree about whether a purchase happened.
local function settlePurchase(itemID, qty, total, runCode)
  if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
  qty, total = qty or 0, total or 0
  local line = lineFor(itemID)
  if current and qty > 0 and total > 0 then
    local at = time()
    if runCode == current:Code() then current:RecordPurchase(itemID, qty, total, at) end
    recordAcquisition(itemID, line and lineName(line) or nil, qty, total, at, runCode)
    recordLedgerBuy(itemID, line and lineName(line) or nil, qty, total, at, runCode)
  end
  logAttempt(line, (GC.L["bought %d for %s"]):format(qty, formatAmount(total)), itemID)
  -- The purchase is booked against the run whether or not the units have arrived: the auction
  -- house delivers them as mail, so HAVE moves only once the player empties the mailbox, and
  -- `buy` is need - max(have, bought) precisely so the line is right in the meantime. HAVE is
  -- re-counted anyway (the mail may already be in), and the next line that still needs
  -- something takes the focus, so Enter carries on down the run without reaching for the mouse.
  scanBags()
  GC.Buy._focus = nextOpenAfter(itemID)
  GC.Buy.RefreshIfShown()
end

-- A late FAILED or PRICE_UNAVAILABLE for a confirm this tab had given up on is the answer it was
-- waiting for: the purchase did NOT happen. Attributed exactly as takeStranded attributes a
-- success, and no looser: with two records live neither can be named, and the failure is not
-- this tab's to take; with one, it is taken only while the attempt on screen is still that very
-- confirm at `unknown`. Anything else -- the player has moved on to another line, or the failure
-- is from their own purchase on Blizzard's pane, which claims no slot -- is evidence about some
-- other purchase, and a warning lifted on it would leave a live BUY button over units that may
-- still arrive. Returns true only when a record was consumed.
local function dropStrandedOnFailure()
  local count, itemID = liveStranded()
  if count ~= 1 then return false end
  local attempt = GC.Buy._attempt
  if not (attempt and attempt.stage == "unknown" and attempt.itemID == itemID) then return false end
  GC.Buy._stranded[itemID] = nil
  attempt.stage = "failed"
  logAttempt(lineFor(itemID), GC.L["purchase failed — try again"], itemID)
  GC.Buy.RefreshIfShown()
  return true
end

local function failAttempt(attempt)
  if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
  attempt.stage = "failed"
  logAttempt(lineFor(attempt.itemID))
  GC.Buy.RefreshIfShown()
end

-- Asks the auction house for this line's book. One SendSearchQuery, under the addon's own
-- throttle claim, and only when there is nothing better already in hand: a quote younger than
-- BD.QUOTE_SECONDS for this same line is what the next click will spend, and a purchase in
-- flight owns the buffer until it is done.
local function quote(line)
  if not buyable(line) then return end
  local attempt = GC.Buy._attempt
  if inFlight(attempt) then return end
  if attempt and attempt.itemID == line.itemID
      and (quotePending(attempt) or quoteFresh(attempt)) then return end
  -- A line under a stranded confirm is never re-offered. Its confirm reached the server and
  -- nothing came back, so the units may already be paid for and a fresh quote is an invitation to
  -- buy them twice. Asked of the record, not of the attempt: the attempt is gone the moment the
  -- player's cursor crosses another row.
  if strandedFor(line) then return end
  if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey) then return end
  -- No auction house session, no question to ask -- and a SendSearchQuery nobody will answer
  -- leaves the board promising a quote that never lands. Same gate as TrySendRefresh's.
  if not (GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen()) then return end
  if not throttleReady() then return end
  -- Claimed as "buy-quote", not "buy": the NOW batch (TrySendRefresh) already claims "buy", and
  -- under a stuck throttle flag GC.Util paces one forced send per consumer -- sharing a name
  -- would have the board's refresh and the player's own hover taking turns in one window.
  if GC.Util and GC.Util.ClaimThrottleSend and not GC.Util.ClaimThrottleSend("buy-quote") then return end

  C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(line.itemID), {}, false)
  -- Blizzard's own pane may open this item's buy page in answer; that page is ours, not a buy.
  if GC.AuctionHouseTab and GC.AuctionHouseTab.NoteAddonSearch then GC.AuctionHouseTab.NoteAddonSearch() end
  attemptSeq = attemptSeq + 1
  GC.Buy._attempt = {
    itemID = line.itemID, stage = "quoting", token = attemptSeq, askedAt = time(),
    runCode = current and current:Code() or nil,
  }
  -- A gear, pet or recipe line is answered by ITEM_SEARCH_RESULTS_UPDATED, which this tab does
  -- not listen to (the commodity buffer is the only book it can buy from in one click), so the
  -- answer is settled here, at the ask: the search above opens Blizzard's own page for the
  -- player, and the button says so instead of waiting on a commodity event that never comes.
  if not askableItem(line.itemID) then
    local asked = GC.Buy._attempt
    asked.stage, asked.byHand, asked.quotedAt = "quoted", true, time()
    asked.qty, asked.total = 0, 0
  end
  logAttempt(line)
  GC.Buy.RefreshIfShown()
end

-- COMMODITY_SEARCH_RESULTS_UPDATED, routed here by Core/Init.lua. The buffer is addon-wide and
-- every consumer sees every answer, so an event for anything but the item this tab is currently
-- quoting belongs to somebody else and is left alone.
function GC.Buy.OnCommodityResults(itemID)
  local attempt = GC.Buy._attempt
  if not attempt or attempt.stage ~= "quoting" or attempt.itemID ~= itemID then return end
  local line = lineFor(itemID)
  if not (current and buyable(line)) then
    GC.Buy._attempt = nil
    return
  end
  local ladder = ladderFor(itemID)
  -- No ladder AND the client says this is not a commodity: the search filled the ITEM buffer,
  -- not the commodity one, so there is nothing here to buy in one click however full the lot
  -- list on Blizzard's own pane is. Marked, so the button says which -- quoting qty 0 and
  -- printing "nothing on offer" was this tab telling the player a falsehood about the market.
  attempt.byHand = (ladder == nil and not askableItem(itemID)) or nil
  local qty, total, capped = current:PurchaseQuantity(itemID, ladder or {})
  attempt.qty, attempt.total, attempt.capped = qty, total, capped
  quotes[itemID] = { qty = qty, total = total, at = time() }
  -- Computed whenever the cap stopped the ladder, not only when it stopped it before a single
  -- unit: a partial fill needs the same number -- what the REST would have cost -- or the line
  -- silently buys six of ten and says nothing about why the other four stayed behind.
  attempt.overPct = capped and overUsualPct(line, ladder) or nil
  attempt.quotedAt = time()
  attempt.stage = "quoted"
  -- The button holds 72px, so the percentage and the cheap hour ride on the log line instead
  -- (the button wears the over-cap variant -- actionLabel). `/gc buy` is where a player reads
  -- them back. Both belong to a refusal: a line the cap was happy with explains nothing.
  local text = nil
  if capped then
    text = actionLabel(line)
    if qty > 0 and attempt.overPct then
      text = ("%s %s"):format(text, (GC.L["▲%d%% over usual"]):format(attempt.overPct))
    end
    local cheap = cheapHourText(line)
    if cheap then text = ("%s · %s"):format(text, cheap) end
  end
  logAttempt(line, text)
  GC.Buy.RefreshIfShown()
end

-- COMMODITY_PRICE_UPDATED: the server's answer to StartCommoditiesPurchase, and the first price
-- anybody has actually seen. It does not confirm anything -- see onBuyClick.
--
-- Taken in EVERY post-start stage, not only `started`. A price update arriving in `confirming` is
-- the server RE-QUOTING: the price moved between the quote and the Confirm click, so the purchase
-- did not happen, and no terminal event ever follows -- Blizzard's own buy dialog keeps this
-- event live through its Purchasing state for exactly that reason. The Sniper learned it the hard
-- way (UI/SniperFrame.lua's OnCommodityPriceUpdated): a stage that went deaf here left the
-- attempt owned forever, the button on "confirming...", and every later commodity purchase
-- refused until /reload. One arriving in `confirm` is the same news before the click.
--
-- Every one of them is re-judged against the quote and the cap, so the confirm click can never
-- reach a total nothing has checked: an update that leaves the cap requotes the line instead.
function GC.Buy.OnCommodityPriceUpdated(unitPrice, totalPrice)
  if not mayOwnTerminal() then return false end
  local attempt = GC.Buy._attempt
  if not attempt or not inFlight(attempt) then return false end
  local qty = attempt.qty or 0
  local total = type(totalPrice) == "number" and totalPrice
    or (type(unitPrice) == "number" and qty > 0 and unitPrice * qty) or nil
  if not total or qty <= 0 then return true end
  local line = lineFor(attempt.itemID)
  -- The line is gone: the run was swapped or resynced under the purchase. There is nothing left
  -- to judge the price against and nothing to credit the units to, so the purchase goes back to
  -- the client rather than being confirmed against a run that no longer asks for it.
  if not line then
    cancelStartedPurchase()
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
    -- Logged BEFORE the attempt is cleared, so `/gc buy` can still name the item it was about.
    logAttempt(nil, GC.L["the run changed — start again"], attempt.itemID)
    GC.Buy._attempt = nil
    GC.Buy.RefreshIfShown()
    return true
  end
  -- Two ways this is still a price the line agreed to: no worse than the quote the player read,
  -- or -- the quote having been optimistic -- inside the line's own cap per unit. An ABSENT cap
  -- is not the third way. A line whose item has no usual price has nothing to cap against, which
  -- makes the quote the only number anybody checked; letting a capless line wave any total
  -- through turned "we could not price this" into "spend what you like".
  local underCap = line.cap ~= nil and math.floor(total / qty) <= line.cap
  if total <= (attempt.total or 0) or underCap then
    attempt.serverTotal = total
    -- Back to `confirm` even from `confirming`: no gold moved, and the price on the button is a
    -- new one, so it needs the player's agreement again exactly as the first one did.
    attempt.stage = "confirm"
    armStall(attempt, BD.CONFIRM_SECONDS)
  else
    attempt.movedTotal = total
    attempt.stage = "requote"
    -- Safe after a Confirm that was already sent: a re-quote IS the server saying that confirm
    -- bought nothing. Same reasoning, same call, as the Sniper's own requote path.
    cancelStartedPurchase()
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
  end
  logAttempt(line)
  GC.Buy.RefreshIfShown()
  return true
end

-- COMMODITY_PURCHASE_SUCCEEDED. Three ways one can arrive here, and they are not the same event.
function GC.Buy.OnCommodityPurchaseSucceeded()
  if not mayOwnTerminal() then return false end
  local attempt = GC.Buy._attempt
  local stage = attempt and attempt.stage

  -- One: the purchase this tab confirmed, answered. The only one that books a cost.
  if stage == "confirming" then
    GC.Buy._attempt = nil
    GC.Buy._stranded[attempt.itemID] = nil
    settlePurchase(attempt.itemID, attempt.qty, attempt.serverTotal or attempt.total,
      attempt.runCode)
    return true
  end

  -- Two: a purchase landed while this tab was still holding an unconfirmed one -- the player
  -- confirmed on Blizzard's own buy page, which a search of ours can open, or the event belongs
  -- to somebody else entirely. It ENDS the attempt: left live, its CONFIRM button invited a
  -- second purchase of the same units, and twenty seconds later the watchdog aimed a Cancel at a
  -- purchase that had already succeeded. Nothing is recorded -- this tab never saw the price, and
  -- a cost basis taken from a total nobody was charged is worse than no row at all, which is what
  -- UI/SniperFrame.lua concludes about its own unpriceable successes.
  if attempt and inFlight(attempt) then
    -- Our own Start may still be dangling in the client -- it was never confirmed, so it is ours
    -- to take back. A purchase at `confirm` or `confirming` is NOT cancelled: this success may
    -- well be its own answer, and cancelling a purchase that has already gone through is noise
    -- at best.
    if stage == "started" then cancelStartedPurchase() end
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
    logAttempt(lineFor(attempt.itemID), GC.L["a purchase landed that GoldCap could not price"])
    GC.Buy._stranded[attempt.itemID] = nil
    GC.Buy._attempt = nil
    scanBags()
    GC.Buy.RefreshIfShown()
    return true
  end

  -- Three: the late answer to an attempt the confirming timeout gave up on. The gold left the
  -- bags, so the books have to say so, at the total the server last quoted for it.
  local stranded, consumed = takeStranded()
  if not stranded then return consumed end
  if attempt and attempt.stage == "unknown" and attempt.itemID == stranded.itemID then
    GC.Buy._attempt = nil
  end
  settlePurchase(stranded.itemID, stranded.qty, stranded.total, stranded.runCode)
  return true
end

-- COMMODITY_PURCHASE_FAILED / COMMODITY_PRICE_UNAVAILABLE. Both say the same thing to this tab:
-- no gold moved, the slot goes back, and the button says so rather than sitting on "buying...".
-- The stage check is the same guard the success path carries, for the same reason.
function GC.Buy.OnCommodityPurchaseFailed()
  if not mayOwnTerminal() then return false end
  local attempt = GC.Buy._attempt
  if attempt and (inFlight(attempt) or attempt.stage == "requote") then
    failAttempt(attempt)
    return true
  end
  return dropStrandedOnFailure()
end

function GC.Buy.OnCommodityPriceUnavailable()
  if not mayOwnTerminal() then return false end
  local attempt = GC.Buy._attempt
  if attempt and (inFlight(attempt) or attempt.stage == "requote") then
    failAttempt(attempt)
    return true
  end
  return dropStrandedOnFailure()
end

-- Read-only ownership, asked by Core/PurchaseCapture.lua's passive hooks. Without it every BUY
-- purchase is filed twice: once here as `goldcap_buy`, and once by the capture as an ordinary
-- `auction_house` buy -- the same gold counted twice in the Sell tab's cost basis. Mirrors
-- GC.Sniper.OwnsCommodityPurchase, including its "a nil quantity means any".
function GC.Buy.OwnsCommodityPurchase(itemID, quantity)
  -- A stranded confirm counts. Its success is still owed, and the capture discarded its own
  -- record of the Start hook while this tab owned the purchase -- so if ownership lapsed here the
  -- capture would file a batch for it too, on top of the one settlePurchase writes.
  --
  -- BOTH the item and the quantity have to match, unlike the live attempt below where a nil
  -- quantity means any: a stranded record is not a purchase in flight, and claiming every buy of
  -- that item would stop the capture recording the player's own unrelated ones.
  local record = GC.Buy._stranded[itemID]
  if record and quantity ~= nil and record.qty == quantity
      and record.session == sessionToken
      and (time() - (record.at or 0)) <= BD.STRANDED_SECONDS then
    return true
  end
  local attempt = GC.Buy._attempt
  if not attempt or attempt.itemID ~= itemID or not inFlight(attempt) then return false end
  if quantity == nil then return true end
  return attempt.qty == quantity
end

-- What armStall's timer does when it comes due, and the one place an attempt is given up
-- without a terminal event. `token` keeps a timer armed for one attempt from retiring the next;
-- `stall` keeps an earlier arming of the SAME attempt from retiring a stage that has since moved
-- on (a price update re-arms, and the older timer must simply expire quietly).
--
-- A `confirming` attempt is never re-armed for a retry: ConfirmCommoditiesPurchase already
-- reached the server, so gold may well have moved, and offering the line back for another click
-- could buy the same units twice -- the rule the Sniper's own confirming timeout follows. It
-- says so instead, and leaves the correction to the bag re-count that any real delivery brings.
retireStalled = function(token, stall)
  local attempt = GC.Buy._attempt
  if not attempt or attempt.token ~= token or attempt.stall ~= stall then return end
  if not inFlight(attempt) then return end
  local line = lineFor(attempt.itemID)
  if attempt.stage ~= "confirming" then
    cancelStartedPurchase()
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
    attempt.stage = "expired"
    logAttempt(line)
    GC.Buy.RefreshIfShown()
    return
  end
  if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
  attempt.stage = "unknown"
  -- Everything a late success would need to book the purchase, kept where the attempt cannot take
  -- it with it -- and keyed by item, so stranding a second line never overwrites the first.
  -- GC.Sniper keeps the same table for the same reason (_strandedConfirmed).
  GC.Buy._stranded[attempt.itemID] = {
    qty = attempt.qty, total = attempt.serverTotal or attempt.total,
    runCode = attempt.runCode, have = line and line.have or nil,
    at = time(), session = sessionToken,
  }
  logAttempt(line)
  GC.Buy.RefreshIfShown()
end

-- AUCTION_HOUSE_CLOSED / the Auctioneer frame going away (Core/Init.lua routes BOTH, deliberately:
-- either can be the last event a session gets). The session that owed this attempt an answer is
-- gone, so no terminal event is ever coming: an attempt left standing would hold the shared slot
-- and keep OwnsCommodityPurchase true until /reload. The stranded record goes with it -- a late
-- success cannot cross a session boundary.
--
-- Idempotent, because on a real close this runs twice. A stage that is already finished with is
-- left exactly as it was: the second call used to clear `unknown` -- the one state whose whole
-- job is to warn that a confirm may have taken gold -- before the player could read it.
function GC.Buy.OnAuctionHouseClosed()
  GC.Buy._stranded = {}
  local attempt = GC.Buy._attempt
  if not attempt then return end
  local stage = attempt.stage
  if stage == "unknown" or stage == "expired" then return end
  if not inFlight(attempt) then
    -- A quote, a refused price, a failure: nothing the next session can use, and nothing it has
    -- to be warned about.
    GC.Buy._attempt = nil
    GC.Buy.RefreshIfShown()
    return
  end
  local line = lineFor(attempt.itemID)
  if stage ~= "confirming" then
    cancelStartedPurchase()
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
    attempt.stage = "expired"
  else
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
    attempt.stage = "unknown"
  end
  logAttempt(line)
  GC.Buy.RefreshIfShown()
end

-- The auction house opening. A new session cannot answer for the last one, so whatever the last
-- one left behind is cleared here: the stranded record ages out with its token, and a line the
-- old session gave up on is offered again -- by now the bags say whether the units ever arrived.
function GC.Buy.OnAuctionHouseShow()
  sessionToken = sessionToken + 1
  GC.Buy._stranded = {}
  local attempt = GC.Buy._attempt
  if attempt and not inFlight(attempt) then GC.Buy._attempt = nil end
end

local function afterClick(line)
  logAttempt(line)
  GC.Buy.RefreshIfShown()
end

-- ---------------------------------------------------------------------------
-- The one hardware click. Nothing else in this file may reach a protected purchase API --
-- spec/buy_purchase_wiring_spec.lua reads this file's source text and proves it.
-- ---------------------------------------------------------------------------

local function onBuyClick(line)
  if not (line and current) then return end
  local attempt = GC.Buy._attempt

  -- The confirming click. The client only demands a hardware event for the START of a commodity
  -- purchase, so an addon MAY confirm straight from COMMODITY_PRICE_UPDATED -- and this one
  -- never will. The server's price is the first price anybody has actually seen, and agreeing to
  -- it is the player's to do (addon/AGENTS.md: "Do not 'helpfully' auto-confirm anything").
  if attempt and attempt.stage == "confirm" and attempt.itemID == line.itemID
      and (attempt.qty or 0) > 0 then
    attempt.stage = "confirming"
    C_AuctionHouse.ConfirmCommoditiesPurchase(attempt.itemID, attempt.qty)
    armStall(attempt, BD.CONFIRM_SECONDS)
    afterClick(line)
    return
  end

  -- The client is holding a purchase of ours: a second click can only make trouble.
  if attempt and (attempt.stage == "started" or attempt.stage == "confirming") then return end
  if not buyable(line) then return end

  -- Anything but a live quote for THIS line asks the auction house instead of spending: a stale
  -- ladder is a plan against prices somebody else has already bought off. The next click buys.
  if not (attempt and attempt.itemID == line.itemID and quoteFresh(attempt)
      and (attempt.qty or 0) > 0) then
    -- Focus does not move onto a line a click cannot act on while another line's purchase is in
    -- the client's hands: Enter has to keep pointing at the line waiting for its confirm.
    if not inFlight(attempt) then GC.Buy._focus = line.itemID end
    quote(line)
    return
  end

  if GC.PurchaseSlot and not GC.PurchaseSlot.Claim("buy") then
    if GC.Print then GC.Print(GC.L["another purchase is in flight"]) end
    return
  end
  -- Stage first, call second: Core/PurchaseCapture.lua's StartCommoditiesPurchase hook runs
  -- inside this very call and asks GC.Buy.OwnsCommodityPurchase whether the purchase is ours.
  attempt.stage = "started"
  C_AuctionHouse.StartCommoditiesPurchase(attempt.itemID, attempt.qty)
  armStall(attempt, BD.WATCHDOG_SECONDS)
  afterClick(line)
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

-- The one list this tab renders, top to bottom. Vendor lines are already last (Core/BuyRun.lua's
-- Refresh puts them there); this only decides what is a row at all.
local function buildEntries()
  local entries = {}
  if not current then
    entries[#entries + 1] = { kind = "hint", text =
      GC.L["No runs yet. Save a list with quantities on goldcap.gg, or type /gc import and paste a run string."] }
    return entries
  end
  local locked = 0
  for _, line in ipairs(current:Lines()) do
    -- A reagent a split brought in is not a line of the run, so it is not one of the lines the
    -- free tier is counting (Core/BuyRun.lua gives it its parent's lock and no index).
    if line.locked and not line.parent then locked = locked + 1 end
    entries[#entries + 1] = { kind = "line", line = line }
  end
  if locked > 0 then
    entries[#entries + 1] = { kind = "hint", text = (GC.L["%d more lines with Pro"]):format(locked) }
  end
  return entries
end

local function heightFor(kind)
  if kind == "hint" then return geometry.rowHeight * 2 end
  return geometry.rowHeight
end

local function buildRowCell(row, col)
  local fs
  if col.num then
    fs = Theme.Num(row, col.size or 11, col.bold)
  else
    fs = Theme.Label(row, col.size or 11)
    fs:SetJustifyH(col.center and "CENTER" or "LEFT")
  end
  fs:SetWordWrap(false)
  return fs
end

local function clearRow(row)
  row.reagent:SetText("")
  row.reagent:Show()
  row.wide:SetText("")
  row.wide:Hide()
  row.action:Hide()
  row.pro:Hide()
  row.reagentInset = 0
  row.icon:Hide()
  row.tooltipItemID = nil
  row.lineItemID = nil
  for _, col in ipairs(COLUMNS) do
    if not col.flex then
      row.cells[col.key]:SetText("")
      if hiddenColumns[col.key] then
        row.cells[col.key]:Hide()
      else
        row.cells[col.key]:Show()
      end
    end
  end
end

-- What one craft line's reagents still cost, at the best price known for each: the child lines
-- the split created in full, and -- for a reagent the run already asked for, which grew an
-- existing line rather than getting one of its own -- the share of that line this craft is
-- responsible for, counted first. nil when no reagent has a price at all, which is the same
-- em dash every other unpriceable cell shows.
local function craftCostNow(parent)
  if not (current and parent) then return nil end
  local total, known = 0, false
  for _, line in ipairs(current:Lines()) do
    local qty = nil
    if line.parent == parent.itemID then
      qty = line.buy
    elseif line.forCraft and line.forCraft[parent.itemID] then
      qty = math.min(line.buy, line.forCraft[parent.itemID])
    end
    if qty and qty > 0 then
      local unit = line.vendor and line.vendorUnit or (line.floor or line.usual)
      if unit then
        total = total + qty * unit
        known = true
      end
    end
  end
  if not known then return nil end
  return total
end

local function paintLine(row, line)
  row.tooltipItemID = line.itemID
  row.lineItemID = line.itemID
  local name = lineName(line)
  local decorated = (Theme.WithQuality and Theme.WithQuality(name, line.itemID, 11)) or name
  -- A craft line names what it makes and how many batches of it; a reagent the split brought in
  -- is indented under the line it belongs to, so the block reads as one instruction.
  if line.kind == "craft" then
    decorated = (GC.L["%s → craft %d× (%d per craft)"]):format(
      decorated, line.crafts or 0, (line.craft and line.craft.craftedQty) or 0)
  elseif line.parent then
    decorated = (GC.L["↳ %s"]):format(decorated)
  end
  row.reagent:SetText(decorated)
  -- Neither a vendor stop nor a craft line is something this tab can act on -- the whole row
  -- reads back, so it does not compete with the lines the player is actually here to buy.
  setColor(row.reagent, (line.vendor or line.kind == "craft") and Theme.color.fgDim or Theme.color.fg)

  local icon = nil
  if C_Item and C_Item.GetItemIconByID then
    local ok, texture = pcall(C_Item.GetItemIconByID, line.itemID)
    icon = ok and texture or nil
  end
  row.reagentInset = icon and 26 or 0
  if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end

  row.cells.need:SetText(tostring(line.need))
  setColor(row.cells.need, Theme.color.fgDim)
  row.cells.have:SetText(tostring(line.have))
  setColor(row.cells.have, line.have > 0 and Theme.color.fg or Theme.color.fgDim)
  row.cells.buy:SetText(tostring(line.buy))
  setColor(row.cells.buy, line.buy > 0 and Theme.color.gold or Theme.color.fgDim)

  if line.vendor then
    -- A vendor sells at a fixed price, so NOW and USUAL are the same number and COST is
    -- arithmetic rather than a quote. All three stay grey: this line is not something to buy
    -- here, and the auction house has no opinion about it worth printing. With no vendor price
    -- known it is three em dashes, the way an unknown price is said everywhere else.
    local unit = line.vendorUnit
    row.cells.now:SetText(formatAmount(unit))
    row.cells.usual:SetText(formatAmount(unit))
    row.cells.cost:SetText(unit and line.buy > 0 and formatAmount(line.buy * unit) or EM_DASH)
    for _, key in ipairs({ "now", "usual", "cost" }) do
      setColor(row.cells[key], Theme.color.fgDim)
    end
  elseif line.kind == "craft" then
    -- Nothing here is bought at the auction house, so NOW and USUAL have nothing to say about
    -- this row -- the same argument the vendor branch above makes. COST is what the reagents
    -- still cost, which is the number this row exists to give; marked as an estimate, like
    -- every other cost built out of prices rather than out of a quote.
    local craftCost = craftCostNow(line)
    row.cells.now:SetText(EM_DASH)
    row.cells.usual:SetText(EM_DASH)
    row.cells.cost:SetText(craftCost and ("~" .. formatAmount(craftCost)) or EM_DASH)
    for _, key in ipairs({ "now", "usual", "cost" }) do
      setColor(row.cells[key], Theme.color.fgDim)
    end
  else
    -- NOW is the best unit price actually seen for this item; nothing has looked yet on a fresh
    -- run, and an em dash says so rather than borrowing the USUAL beside it.
    row.cells.now:SetText(formatAmount(line.floor))
    setColor(row.cells.now, line.floor and Theme.color.fg or Theme.color.fgDim)
    row.cells.usual:SetText(formatAmount(line.usual))
    setColor(row.cells.usual, Theme.color.fgDim)

    -- What the rest of this line should cost at the best price known for it. With neither a seen
    -- floor nor a market value there is no honest number, so the cell stays an em dash.
    local unit = line.floor or line.usual
    local attempt = GC.Buy._attempt
    -- Once this line has a quote (or a purchase under way) the cell shows THAT total -- what the
    -- next click spends, and after the server's price update, what the confirm click spends.
    -- The button stays "BUY n" / "CONFIRM": a badge 80px wide has no room for a sum, and the
    -- sum has a column of its own right beside it.
    local quotedTotal = attempt and attempt.itemID == line.itemID and not attempt.byHand
      and (attempt.stage == "quoted" or inFlight(attempt)) and (attempt.serverTotal or attempt.total) or nil
    -- A quote outlives the hover that asked for it: the cell keeps the real sum for as long as
    -- the quote is one the next click would spend, and only then falls back to the estimate.
    local recent = quotes[line.itemID]
    if not quotedTotal and recent and recent.qty == line.buy and recent.qty > 0
        and (time() - (recent.at or 0)) <= BD.QUOTE_SECONDS then
      quotedTotal = recent.total
    end
    if quotedTotal and quotedTotal > 0 then
      row.cells.cost:SetText(formatAmount(quotedTotal))
      setColor(row.cells.cost, (attempt and attempt.itemID == line.itemID and attempt.stage == "confirm")
        and Theme.color.goldHi or Theme.color.fg)
    else
      -- An estimate, and marked as one: remaining units at the cheapest price seen, which the
      -- lots above that price will exceed once the line is actually quoted.
      row.cells.cost:SetText(unit and ("~" .. formatAmount(line.buy * unit)) or EM_DASH)
      setColor(row.cells.cost, Theme.color.fgDim)
    end
  end

  if line.vendor then
    row.cells.action:SetText(GC.L["vendor"])
    setColor(row.cells.action, Theme.color.fgDim)
  elseif line.done then
    row.cells.action:SetText(GC.L["done"])
    setColor(row.cells.action, Theme.color.fgDim)
  elseif line.kind == "craft" then
    row.cells.action:SetText(GC.L["craft"])
    setColor(row.cells.action, Theme.color.fgDim)
  elseif line.locked then
    row.pro:SetLabel(GC.L["Pro"], Theme.color.gold)
    row.pro:Show()
  else
    -- One control, two looks, never two overlaid buttons (addon/AGENTS.md): the label says what
    -- the next click does, and the focused line -- the one Enter would buy -- wears the active
    -- variant so the key is never aimed at a row nobody can see it pointing at. A state with a
    -- look of its own (over the cap, whether nothing fits under it or only part of the line
    -- does) says so instead; SetVariant runs BEFORE Enable/Disable, since it repaints the text
    -- in the variant's own colours and would undo the dimmed look (UI/SellFrame.lua's rule).
    local label, clickable, variant = actionLabel(line)
    row.action:SetVariant(variant or (GC.Buy._focus == line.itemID and "active" or "ghost"))
    row.action:SetLabel(label)
    if clickable then
      row.action:Enable()
    else
      -- Enable first, then Disable. OnDisable fires on a state CHANGE, and SetVariant above has
      -- just repainted the background and the text in the variant's own live colours -- so a row
      -- that was already disabled would come back looking perfectly clickable. Theme.Button has
      -- no template-driven disabled look to fall back on; UI/Theme.lua's OnDisable is all of it.
      row.action:Enable()
      row.action:Disable()
    end
    row.action:Show()
  end
end

local function paintRow(row, entry, index)
  clearRow(row)

  local zc = Theme.color.zebra
  row.zebra:SetVertexColor(zc[1], zc[2], zc[3], (index % 2 == 1) and (zc[4] or 0) or 0)

  if entry.kind == "hint" then
    row.reagent:Hide()
    row.wide:Show()
    row.wide:SetJustifyH("CENTER")
    row.wide:SetWordWrap(true)
    row.wide:SetText(entry.text)
    setColor(row.wide, Theme.color.fgDim)
    row.wide:SetSpacing(4)
  elseif entry.kind == "line" then
    paintLine(row, entry.line)
  end

  -- Re-anchor the reagent cell now that this render's own row.reagentInset is known; rows are
  -- pooled and an index's kind can change between renders (SoldFrame's paintRow carries the
  -- same call for the same reason).
  layoutRow(row)
end

layoutRow = function(row)
  local flexAnchor = anchorColumns(row, hiddenColumns, function(col) return row.cells[col.key] end)
  row.reagent:ClearAllPoints()
  row.reagent:SetPoint("LEFT", row, "LEFT", row.reagentInset or 0, 0)
  row.reagent:SetPoint("RIGHT", flexAnchor.frame, flexAnchor.point, -Theme.pad.s, 0)
end

-- Right-click on a row: the one decision a line carries that is not a purchase -- buy this item,
-- or buy what it is made of. Only a line the site sent a recipe for has anything to decide, and
-- nothing here spends gold: it writes a flag and re-renders (spec/buy_purchase_wiring_spec.lua
-- proves no protected call can be reached from a context menu at all).
--
-- Refused while a purchase is in flight, for the reason the run menu refuses a re-cap there:
-- the attempt has already committed to `current`'s lines, and a split rewrites them, so
-- settlePurchase would book the gold against a line that no longer exists.
local function openRowMenu(owner, line)
  if not (current and line and line.craft) then return false end
  if line.parent or line.locked then return false end
  if inFlight(GC.Buy._attempt) then return false end
  local menu = _G.MenuUtil
  if not (menu and menu.CreateContextMenu) then return false end
  local code, itemID = current:Code(), line.itemID
  local split = line.kind == "craft"
  -- How many batches an unsplit line would need is the same arithmetic Core/BuyRun.lua does once
  -- it IS split: what is left to get, rounded up to a whole craft.
  local crafts = split and (line.crafts or 0)
    or math.ceil(line.buy / math.max(1, line.craft.craftedQty))
  menu.CreateContextMenu(owner, function(_, root)
    if split then
      root:CreateButton(GC.L["Buy it whole instead"], function()
        setSplit(code, itemID, false)
        GC.Buy.RefreshIfShown()
      end)
    else
      root:CreateButton((GC.L["Split into reagents (craft %d×)"]):format(crafts), function()
        setSplit(code, itemID, true)
        GC.Buy.RefreshIfShown()
      end)
    end
  end)
  return true
end

createRow = function(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(geometry.rowHeight)

  -- Zebra + hover, the Sell/Sold convention: a sliced rounded fill recomputed every render off
  -- the row's CURRENT index, since this tab's entry composition reshuffles between renders.
  local zc = Theme.color.zebra
  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetTexture(Theme.MEDIA .. "plaque.png")
  zebra:SetTextureSliceMargins(12, 12, 12, 12)
  zebra:SetPoint("TOPLEFT", 2, -1)
  zebra:SetPoint("BOTTOMRIGHT", -2, 1)
  zebra:SetVertexColor(zc[1], zc[2], zc[3], 0)
  row.zebra = zebra

  -- Hover is the engine's HIGHLIGHT draw layer on a mouse-enabled frame, never an
  -- OnEnter/OnLeave repaint (addon/AGENTS.md's "Buttons and hover").
  local hc = Theme.color.hover
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture(Theme.MEDIA .. "plaque.png")
  highlight:SetTextureSliceMargins(12, 12, 12, 12)
  highlight:SetPoint("TOPLEFT", 2, -1)
  highlight:SetPoint("BOTTOMRIGHT", -2, 1)
  highlight:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 0.08)
  row.highlight = highlight
  row:EnableMouse(true)

  -- A Frame with the mouse enabled gets OnMouseUp for every button, which is how a row that is
  -- not a Button carries a context menu. Left clicks are the BUY button's alone and are handed
  -- straight back.
  row:SetScript("OnMouseUp", function(self, button)
    if button ~= "RightButton" then return end
    openRowMenu(self, self.lineItemID and lineFor(self.lineItemID) or nil)
  end)

  -- The item's own tooltip on hover, the same affordance Deals, Sell and Sold give their rows.
  -- Wired ONCE on the pooled row, reading whatever paintRow last stamped.
  row:SetScript("OnEnter", function(self)
    -- The quote comes FIRST: the tooltip is a nicety and its own early return would otherwise
    -- take the hover-quotes-the-line affordance with it on any client without GameTooltip.
    -- Focus does not move while a purchase is in flight -- Enter must keep pointing at the line
    -- the player is part-way through buying.
    local line = self.lineItemID and lineFor(self.lineItemID) or nil
    if buyable(line) and not inFlight(GC.Buy._attempt) then
      GC.Buy._focus = line.itemID
      quote(line)
    end
    if not GameTooltip or not self.tooltipItemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.tooltipItemID) end
    -- HAVE counts the banks as well as the bags, so a line reading 305 with five in the bags
    -- owes the player an explanation of where the other three hundred are. Only when the bank
    -- actually holds some: on every other line it would be a zero nobody asked about.
    local bags, bank = haveSplit(self.tooltipItemID)
    if bank > 0 and GameTooltip.AddLine then
      local bc = Theme.color.fgDim
      GameTooltip:AddLine((GC.L["in bags %d · in bank %d"]):format(bags, bank), bc[1], bc[2], bc[3])
    end
    -- The one thing the item's own tooltip cannot know: when this realm usually sells it
    -- cheapest. Added after the item so it reads as a footnote rather than as a claim the game
    -- is making about the item. Not on a vendor line -- the auction house's cheap hour is noise
    -- next to a fixed price -- and not on a done line, which nobody is about to act on.
    local cheap = line and not line.vendor and not line.done and cheapHourText(line)
    if cheap and GameTooltip.AddLine then
      local c = Theme.color.fgDim
      GameTooltip:AddLine(cheap, c[1], c[2], c[3])
    end
    -- Where a merged line's NEED came from. A reagent the run already asked for does not get a
    -- second row -- it grows the row it has -- and a NEED that grew with no explanation is a
    -- number the player cannot check.
    if line and line.forCraft and GameTooltip.AddLine then
      local mc = Theme.color.fgDim
      for parentID, qty in pairs(line.forCraft) do
        local parentLine = lineFor(parentID)
        GameTooltip:AddLine((GC.L["includes %d for crafting %s"]):format(
          qty, parentLine and lineName(parentLine) or ("#" .. tostring(parentID))), mc[1], mc[2], mc[3])
      end
    end
    -- Craft it or buy it: two numbers about this region's prices now, and never a promise about
    -- what the player will save. Green when crafting is the cheaper of the two, grey otherwise --
    -- including when the auction house has no price to compare against at all.
    local compare = line and not line.done and GC.BuyRun and GC.BuyRun.CraftText
      and GC.BuyRun.CraftText(line) or nil
    if compare and GameTooltip.AddLine then
      local cc = compare.cheaper and Theme.color.green or Theme.color.fgDim
      local parts = {}
      for _, reagent in ipairs(compare.reagents) do
        parts[#parts + 1] = (GC.L["%d× %s"]):format(
          reagent.qty, lineName({ itemID = reagent.itemID, name = reagent.name }))
      end
      GameTooltip:AddLine((GC.L["craft it: %s = %s each"]):format(
        table.concat(parts, " + "), formatAmount(compare.unit)), cc[1], cc[2], cc[3])
      -- The hint names what the right-click would DO, which is the opposite thing on a line
      -- that is already split.
      if line.kind == "craft" then
        GameTooltip:AddLine(
          (GC.L["vs %s at the auction house · right-click to buy it whole"])
            :format(formatAmount(compare.ahUnit)), cc[1], cc[2], cc[3])
      else
        GameTooltip:AddLine(
          (GC.L["vs %s at the auction house · right-click to split"])
            :format(formatAmount(compare.ahUnit)), cc[1], cc[2], cc[3])
      end
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.icon:Hide()

  -- The full-row text used by the "hint" kind -- the empty state and the locked-lines notice.
  row.wide = Theme.Label(row, 11)
  row.wide:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.wide:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  row.wide:Hide()

  row.reagent = Theme.Label(row, 11)
  row.reagent:SetWordWrap(false)

  row.cells = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then row.cells[col.key] = buildRowCell(row, col) end
  end

  -- One control with one look, shown only on a line that can actually be bought (paintLine).
  -- 72 inside an 80px column, the same "sized to the longest English label" rule SellFrame's
  -- 86px action button follows.
  row.action = Theme.Button(row, "ghost", "badge")
  row.action:SetSize(72, 18)
  row.action:SetPoint("CENTER", row.cells.action, "CENTER", 0, 0)
  -- Wired ONCE on the pooled row and reading whatever paintRow last stamped on it, the same way
  -- the row's own tooltip is wired: a per-render SetScript would leak a closure per repaint.
  row.action:SetScript("OnClick", function()
    onBuyClick(lineFor(row.lineItemID))
  end)
  row.action:Hide()

  -- The locked-line marker sits in the same cell the BUY button would have: a line past the
  -- free limit is not a line with no action, it is a line whose action is behind Pro.
  row.pro = Theme.Chip(row)
  row.pro:SetSize(40, 16)
  row.pro:SetPoint("CENTER", row.cells.action, "CENTER", 0, 0)
  row.pro:Hide()

  layoutRow(row)
  return row
end

local function createHeaderRow(parent)
  local header = CreateFrame("Frame", nil, parent)
  header:SetHeight(BD.HEADER_H)
  header.cells = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then
      local hit = CreateFrame("Frame", nil, header)
      hit:SetHeight(BD.HEADER_H)
      local label = Theme.Num(hit, 9)
      label:SetWordWrap(false)
      -- One line, hard capped: the label is SetAllPoints() onto a BD.HEADER_H-tall cell, and a
      -- line that does not fit the height it is given is not drawn at all.
      label:SetMaxLines(1)
      setColor(label, Theme.color.fgDim)
      label:SetAllPoints()
      label:SetJustifyH(col.num and "RIGHT" or (col.center and "CENTER" or "LEFT"))
      label:SetText(headerText(col.key))
      hit.label = label
      header.cells[col.key] = hit
    end
  end

  local reagentHit = CreateFrame("Frame", nil, header)
  local reagentLabel = Theme.Num(reagentHit, 9)
  reagentLabel:SetWordWrap(false)
  reagentLabel:SetMaxLines(1)
  setColor(reagentLabel, Theme.color.fgDim)
  reagentLabel:SetAllPoints()
  reagentLabel:SetJustifyH("LEFT")
  reagentLabel:SetText(headerText("reagent"))
  reagentHit.label = reagentLabel
  -- Not read by any production code; exposed so the behavior spec can reach the REAGENT cell.
  header.reagentCell = reagentHit

  headerLayout = function()
    local flexAnchor = anchorColumns(header, hiddenColumns, function(col) return header.cells[col.key] end)
    reagentHit:ClearAllPoints()
    reagentHit:SetPoint("TOPLEFT", header, "TOPLEFT")
    reagentHit:SetPoint("BOTTOMRIGHT", flexAnchor.frame, "BOTTOMLEFT", -Theme.pad.s, 0)
  end
  headerLayout()

  local bc = Theme.color.border
  local rule = header:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")
  rule:SetHeight(1)
  header.rule = rule

  return header
end

-- The headings are stamped once, at build, and this tab spends most of its life hidden behind
-- Deals. A one-line FontString hidden with its parent can come back with its text simply not
-- drawn (see UI/SniperFrame.lua's updateHeaderSortIndicators for the full story), and SetText
-- is what the client needs to draw it again -- so Show() goes through here.
local function restampHeadings()
  local header = band and band.header
  if not header or not header.cells then return end
  -- Cleared before it is set again: SetText with the text the string already holds is a no-op
  -- to the client, and a no-op does not make it draw. Measured in game -- every heading but
  -- NEED came back shown, anchored, its text and string width intact, and blank on screen.
  local function stamp(label, text)
    if not label then return end
    label:SetText("")
    label:SetText(text)
    if label.Hide and label.Show then label:Hide(); label:Show() end
  end
  for key, hit in pairs(header.cells) do stamp(hit.label, headerText(key)) end
  if header.reagentCell then stamp(header.reagentCell.label, headerText("reagent")) end
end

-- The run's vendor stops as one block of text: what to buy, what each costs and what the trip
-- comes to. Only lines with something still to buy -- this is a shopping list, not an inventory
-- -- and a line the site could not price is named without a price rather than with a blank one.
-- nil when there is nothing to copy, which is also when the button is hidden.
local function vendorListText()
  if not current then return nil end
  local out, total = {}, 0
  for _, line in ipairs(current:Lines()) do
    if line.vendor and line.buy > 0 then
      local unit = line.vendorUnit
      if unit then
        total = total + line.buy * unit
        out[#out + 1] = (GC.L["%d× %s · %s each · %s"]):format(
          line.buy, lineName(line), plainAmount(unit), plainAmount(line.buy * unit))
      else
        out[#out + 1] = (GC.L["%d× %s"]):format(line.buy, lineName(line))
      end
    end
  end
  if #out == 0 then return nil end
  out[#out + 1] = (GC.L["Total: %s"]):format(plainAmount(total))
  return table.concat(out, "\n")
end

-- The header band: the run picker and the run's line counts on one line, the money, the vendor
-- button and the bags legend under them. SellFrame/SoldFrame's header-band convention.
local function createBand(parent)
  local picker = Theme.Button(parent, "ghost", "badge")
  picker:SetSize(150, 20)
  picker:SetPoint("TOPLEFT", 0, -2)
  -- A menu of every run the addon holds, with remove and paste beside it. MenuUtil is the
  -- engine's own framework (UI/SettingsFrame.lua's language picker opens one the same way);
  -- a client without it falls back to cycling, which is what the button used to do and what
  -- the headless specs drive.
  picker:SetScript("OnClick", function(self)
    if not openRunMenu(self) then
      cycleRun()
      GC.Buy.RefreshIfShown()
    end
  end)
  picker:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(GC.L["Runs: click to switch, remove or paste one"], 1, 1, 1)
    GameTooltip:Show()
  end)
  picker:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  local counts = Theme.Num(parent, 9)
  counts:SetJustifyH("RIGHT")
  counts:SetWordWrap(false)
  counts:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -6)
  counts:SetPoint("LEFT", picker, "RIGHT", Theme.pad.s, 0)
  setColor(counts, Theme.color.fgDim)

  -- What the HAVE column counts -- the bags plus every bank the character can reach -- and where
  -- a purchase actually turns up: the auction house delivers commodities as mail, so a bought
  -- line's HAVE does not move until the mailbox is emptied. Said once here rather than on every
  -- row that is waiting for it.
  -- Anchored first and by its RIGHT edge alone, so its width is its own text -- `spent` below
  -- binds to its LEFT, and binding them to each other in both directions would be circular.
  local bags = Theme.Num(parent, 9)
  bags:SetJustifyH("RIGHT")
  bags:SetWordWrap(false)
  bags:SetPoint("TOPRIGHT", 0, -26)
  bags:SetText(GC.L["in bags and bank · purchases arrive by mail"])
  setColor(bags, Theme.color.fgDim)

  -- Shown only for a run that still has a vendor stop (renderRows). A vendor trip is the one
  -- part of a run the game cannot help with, so the list leaves the game as text.
  -- On the SECOND line, hung off the legend: `counts` above has two opposing anchors and no
  -- width of its own, so a button parked in front of it is what its text overflows onto the
  -- moment the tab is docked narrow.
  local vendorBtn = Theme.Button(parent, "ghost", "badge")
  vendorBtn:SetSize(120, 20)
  vendorBtn:SetPoint("RIGHT", bags, "LEFT", -Theme.pad.s, 0)
  vendorBtn:SetLabel(GC.L["Copy vendor list"])
  vendorBtn:SetScript("OnClick", function()
    local text = vendorListText()
    if text and GC.UI and GC.UI.ShowVendorList then GC.UI.ShowVendorList(text) end
  end)
  vendorBtn:Hide()

  local spent = Theme.Num(parent, 10)
  spent:SetJustifyH("LEFT")
  spent:SetWordWrap(false)
  spent:SetPoint("TOPLEFT", 0, -26)
  spent:SetPoint("RIGHT", bags, "LEFT", -Theme.pad.s, 0)
  setColor(spent, Theme.color.fgMuted)

  -- Band rule: a separate frame pinned to the band's own height so the 1px line sits at the
  -- band's bottom edge regardless of where the text above it ends.
  local bandFrame = CreateFrame("Frame", nil, parent)
  bandFrame:SetPoint("TOPLEFT", 0, 0)
  bandFrame:SetPoint("TOPRIGHT", 0, 0)
  bandFrame:SetHeight(BD.BAND_HEIGHT)
  local bc = Theme.color.border
  local rule = bandFrame:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")
  rule:SetHeight(1)

  return { picker = picker, vendor = vendorBtn, counts = counts, spent = spent,
           bags = bags, rule = rule }
end

local function updateContentWidth()
  if not container or not content then return end
  local width = container:GetWidth()
  if width and width > 0 then
    geometry.rowWidth = width
    content:SetWidth(width)
    applyColumnVisibility(width)
  end
end

local function renderRows()
  if not content then return end
  local entries = buildEntries()

  if current then
    local totals = current:Totals()
    band.picker:SetLabel(runLabel(current) .. " ▼")
    band.picker:Show()
    -- Nothing to buy, nothing to craft and nothing to fetch: four zeroes are a worse way of
    -- saying it.
    if totals.lines > 0 and totals.toBuy == 0 and totals.toCraft == 0 and totals.atVendor == 0 then
      band.counts:SetText(GC.L["everything bought"])
    elseif totals.toCraft > 0 then
      band.counts:SetText((GC.L["%d lines · %d to buy · %d to craft · %d at the vendor"]):format(
        totals.lines, totals.toBuy, totals.toCraft, totals.atVendor))
    else
      band.counts:SetText((GC.L["%d lines · %d to buy · %d at the vendor"]):format(
        totals.lines, totals.toBuy, totals.atVendor))
    end
    if totals.atVendor > 0 then band.vendor:Show() else band.vendor:Hide() end
    -- The money line stops where the button starts while the button is up, and runs to the
    -- legend when it is not: a RIGHT anchor shared with the button would put the text UNDER
    -- it, and a hidden frame still occupies its anchor width.
    band.spent:ClearAllPoints()
    band.spent:SetPoint("TOPLEFT", 0, -26)
    if totals.atVendor > 0 then
      band.spent:SetPoint("RIGHT", band.vendor, "LEFT", -Theme.pad.s, 0)
    else
      band.spent:SetPoint("RIGHT", band.bags, "LEFT", -Theme.pad.s, 0)
    end
    band.spent:SetText((GC.L["spent %s · left ~%s"]):format(
      formatAmount(totals.spent), formatAmount(totals.left)))
  else
    -- Nothing to name and nothing to count: a picker offering a run that does not exist is
    -- worse than no picker at all.
    band.picker:Hide()
    band.vendor:Hide()
    band.counts:SetText("")
    band.spent:SetText("")
  end

  for i = #rows + 1, #entries do rows[i] = createRow(content) end
  local y = 0
  for i, entry in ipairs(entries) do
    local row = rows[i]
    local h = heightFor(entry.kind)
    row:SetHeight(h)
    -- TOPLEFT + TOPRIGHT so a row's width tracks content's, which updateContentWidth keeps
    -- current with the real window/dock width.
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    paintRow(row, entry, i)
    row:Show()
    y = y + h
  end
  for i = #entries + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math.max(1, y))
end

-- Builds the tab's container, hidden, filling the same region Deals' scroll occupies --
-- geometry passed through from createFrame, never re-declared, exactly like GC.Sold.Attach.
function GC.Buy.Attach(f, geo)
  Theme = GC.Theme
  geometry = geo
  container = CreateFrame("Frame", nil, f)
  container:SetPoint("TOPLEFT", f, "TOPLEFT", geo.panelLeft, geo.top)
  container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -geo.panelRightInset, geo.bottom)
  container:Hide()

  -- Establish the drop state from the starting width, so the first header/row layout already
  -- reflects it instead of waiting for a resize.
  hiddenColumns = computeHidden(geo.rowWidth or 0)

  band = createBand(container)

  local header = createHeaderRow(container)
  header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -BD.BAND_HEIGHT)
  header:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -BD.BAND_HEIGHT)
  -- Not read by any production code -- attached so the behavior spec can reach the column
  -- header's cells through the same `band` upvalue it already uses for the summary lines.
  band.header = header

  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(BD.BAND_HEIGHT + BD.HEADER_H + Theme.pad.xs))
  scroll:SetPoint("BOTTOMRIGHT")
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(geo.rowWidth, geo.rowHeight)
  scroll:SetScrollChild(content)
  -- OnSizeChanged is the live path (the resize grip, or the AH tab reparenting the window into
  -- a different-width dock); Show() below is the catch-up path for a frame that was hidden
  -- while that happened, since a hidden frame does not reliably fire OnSizeChanged.
  container:HookScript("OnSizeChanged", function(_, width)
    if not width or width <= 0 then return end
    geometry.rowWidth = width
    content:SetWidth(width)
    applyColumnVisibility(width)
  end)

  -- Enter buys the focused line. A key press is a hardware event, so it may reach the protected
  -- purchase call exactly as the click does -- it goes through the same onBuyClick either way.
  --
  -- Propagation is decided PER KEYSTROKE, never set once (UI/SettingsFrame.lua's OnKeyDown says
  -- why): EnableKeyboard(true) delivers EVERY key here, and a frame that swallowed them all
  -- would eat movement, action bars and Enter-to-chat for as long as this tab is up. Only Enter,
  -- and only while the cursor is actually over this window, is taken; everything else is put
  -- straight back. Each widget call is guarded so the headless specs can run without them.
  if container.EnableKeyboard then container:EnableKeyboard(true) end
  container:SetScript("OnKeyDown", function(self, key)
    -- SetPropagateKeyboardInput is combat-protected, and this container has the keyboard for as
    -- long as the BUY tab is up -- including the standalone window, which outlives the auction
    -- house and can be open in a fight. Calling it there raises a protected-function error on
    -- every keystroke. There is no purchase to make in combat anyway (the auction house is not
    -- reachable), so the handler stands down entirely and the key goes where it always would.
    if InCombatLockdown and InCombatLockdown() then return end
    local line
    if (key == "ENTER" or key == "NUMPADENTER") and self.IsMouseOver and self:IsMouseOver() then
      line = lineFor(GC.Buy._focus)
    end
    -- Swallowed ONLY once there is something for it to do. Deciding on the key and the cursor
    -- alone ate Enter -- and with it opening chat -- whenever the cursor happened to be over this
    -- panel with no line focused, which is most of the time a player is reading the board.
    if not actionable(line) then
      if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
      return
    end
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
    onBuyClick(line)
  end)
  -- The one keystroke that leaves propagation off is an Enter that bought a line. Re-armed on
  -- its release, so combat beginning right after that press cannot leave this container eating
  -- movement, action bars and chat for the rest of the fight (OnKeyDown stands down in combat).
  container:SetScript("OnKeyUp", function(self)
    if InCombatLockdown and InCombatLockdown() then return end
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
  end)
end

function GC.Buy.Show()
  if not container then return end
  container:Show()
  restampHeadings() -- see its comment: a heading can come back from a hide undrawn
  -- The bags move while this tab is hidden; a Show that trusted the last scan would open on
  -- counts from whenever the player last looked.
  scanBags()
  -- SelectRun already refreshes what it builds, so only a run ensureRun left alone needs one.
  local rebuilt = ensureRun()
  if current and not rebuilt then current:Refresh() end
  updateContentWidth()
  renderRows()
  -- Ask for prices the moment the tab is up, rather than waiting for the ticker's next second:
  -- the board draws em dashes until an answer lands, and a second of them is a second of a
  -- shopping list that looks like it does not know anything.
  GC.Buy.TrySendRefresh()
end

function GC.Buy.Hide()
  if container then container:Hide() end
end

function GC.Buy.RefreshIfShown()
  if container and container:IsShown() and rows and band then
    if current then current:Refresh() end
    renderRows()
  end
end

-- ---------------------------------------------------------------------------
-- NOW: the floors, refreshed through the addon's one search slot
-- ---------------------------------------------------------------------------

-- Whether an item is something a keys batch can usefully price. C_AuctionHouse.SearchForItemKeys
-- answers with one aggregate row per item key, which is the whole truth for a commodity and
-- only the cheapest variant for anything carrying bonus ids -- so a gear line's "floor" would
-- be a price for some other item's stats. A run is reagents in practice, but a pasted GCR1
-- string can hold anything. Unknown counts as askable: the client answers nil for an item key
-- it has not cached yet, and refusing those would leave a fresh session's whole run unpriced.
-- Declared at the top of the quote path (see there), which asks the same question of a line
-- whose own search came back with no commodity book at all.
askableItem = function(itemID)
  if not (C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.MakeItemKey) then
    return true
  end
  local ok, info = pcall(function()
    return C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
  end)
  if not ok or type(info) ~= "table" or info.isCommodity == nil then return true end
  return info.isCommodity == true
end

-- The ids this run still has a reason to price: open (something left to buy), unlocked (a Pro
-- line has no BUY button to spend the price on), not a vendor line (the auction house has no
-- answer about it and the row is greyed out anyway). Deduplicated -- a run may name the same
-- reagent twice -- because a duplicate key spends a slot in a batch that is capped.
local function refreshTargets()
  if not current then return nil end
  local ids, seen = {}, {}
  for _, line in ipairs(current:Lines()) do
    if not line.vendor and line.kind ~= "craft" and not line.locked and not line.done
        and not seen[line.itemID] and askableItem(line.itemID) then
      seen[line.itemID] = true
      ids[#ids + 1] = line.itemID
      if #ids >= BD.MAX_KEYS then break end
    end
  end
  return ids
end

-- Cheap "is there anything to even ask about" check for the arbiter's HasPending() below --
-- true only when a line still wants buying, deliberately WITHOUT askableItem's
-- GetItemKeyInfo/MakeItemKey calls: those stay inside refreshTargets/NextBatch, which the
-- arbiter only runs once every other gate has already cleared and it has taken the throttle
-- claim. The stub this replaced always answered true, so an all-done run (nothing open, not
-- locked, not vendor) still took the shared throttle claim for a batch that would come back
-- empty -- spending a consumer's slot in GC.Util's per-name pacing for nothing.
local function hasPendingLine()
  if not current then return false end
  for _, line in ipairs(current:Lines()) do
    if not line.vendor and line.kind ~= "craft" and not line.locked and not line.done then
      return true
    end
  end
  return false
end

-- Asks UI/SniperFrame.lua's arbiter for the one outstanding keys batch this addon allows, on
-- this tab's behalf. Every addon-wide rule (no second batch, not across a book pass's browse
-- buffer, not while the player is on Blizzard's own panes, and the throttle claim) lives
-- there; what belongs here is only what BUY alone knows -- the tab is on screen, a run is
-- shown, and the last answer is old enough to be worth replacing. Returns whether a batch went.
function GC.Buy.TrySendRefresh(playerBusy)
  if not (container and container:IsShown() and current) then return false end
  if not (GC.Sniper and GC.Sniper._TrySendKeysBatchFor and GC.Sniper.CurrentView
      and GC.Sniper.IsAHOpen) then return false end
  -- No auction house session, no question to ask. This window outlives the auction house --
  -- it can be re-shown with /goldcap with yesterday's board still in it -- so a rail click to
  -- BUY lands here with nothing to query against, and a SearchForItemKeys nobody will ever
  -- answer would hold the addon-wide keys interlock shut for the full thirty-second timeout.
  -- Same gate, same reason, as canDrillNow's first line in UI/SniperFrame.lua.
  if not GC.Sniper.IsAHOpen() then return false end
  if (time() - lastRefreshAt) < BD.REFRESH_SECONDS then return false end
  -- refreshTargets is handed to the arbiter rather than called here: it walks the whole run
  -- asking the client about every line's item key, and this function runs once a second off
  -- the auction house ticker. Inside NextBatch it runs only on the tick that has already
  -- cleared every gate and taken the throttle claim -- at most once per batch actually sent.
  -- An empty answer is the arbiter's to handle, and it does (it sends nothing).
  return GC.Sniper._TrySendKeysBatchFor({
    HasPending = hasPendingLine,
    NextBatch = refreshTargets,
  }, "buy", function() return GC.Sniper.CurrentView() == "buy" end, playerBusy) and true or false
end

-- The once-a-second nudge from UI/SniperFrame.lua's auction-house ticker. A ready tick is not
-- enough on its own: Auto is paused for as long as this tab is up, so on a quiet client
-- nothing else sends anything and no readiness event ever fires.
function GC.Buy.Tick()
  GC.Buy.TrySendRefresh()
end

-- The batch's answer, routed here by GC.Sniper._FoldKeysBatch because this tab is what asked.
-- Browse rows are one aggregate per item key: `minPrice` is the cheapest unit on the realm,
-- which is exactly what NOW claims to be. An item the answer does not mention keeps the floor
-- it had -- unlike the Items board, silence here is not news (a run line the auction house has
-- nothing for is simply unbuyable right now), and blanking it would throw away the only price
-- the player had for a line they are still shopping.
function GC.Buy.FoldRefresh(browsed)
  local now = time()
  lastRefreshAt = now
  if not current then return end
  for i = 1, #(browsed or {}) do
    local row = browsed[i]
    local itemKey = type(row) == "table" and row.itemKey or nil
    local itemID = type(itemKey) == "table" and itemKey.itemID or nil
    local floor = type(row) == "table" and row.minPrice or nil
    if itemID and floor and floor > 0 then current:SetFloor(itemID, floor, now) end
  end
  GC.Buy.RefreshIfShown()
end

-- BAG_UPDATE_DELAYED (Core/Init.lua). Fires on every loot, craft, mail and vendor trip for the
-- whole session, so it does nothing at all unless this tab is actually on screen -- a six-bag
-- walk behind Deals costs the player frames and buys nothing. Nothing goes stale by skipping
-- it: Show() rescans before it renders, which is the only moment a hidden tab's counts could
-- have been read.
function GC.Buy.OnBagsChanged()
  if not (container and container:IsShown()) then return end
  scanBags()
  GC.Buy.RefreshIfShown()
end

-- `/gc buy` (the slash command itself lands with the purchase flow): what the tab believes,
-- printed, so a player can report a wrong count without a screenshot. Same diagnostic register
-- as GC.Sell.DebugPrint -- plain untranslated field=value text, not player-facing copy, so it
-- carries none of the surface's own GC.L keys.
function GC.Buy.DebugPrint()
  -- No run is not a reason to say nothing else. "What happened when I clicked" is the question
  -- this command exists for, and an attempt, a stranded confirm and the log all outlive the run
  -- being swapped away or dropped by the companion -- which is exactly when a player asks.
  if current then
    local totals = current:Totals()
    GC.Print((GC.L["Buy: %s · %d lines · %d to buy · %d at the vendor · spent %s · left ~%s"]):format(
      runLabel(current), totals.lines, totals.toBuy, totals.atVendor,
      formatAmount(totals.spent), formatAmount(totals.left)))
    GC.Print(("run: code=%s name=%s"):format(tostring(current:Code()), tostring(current:Name())))
  else
    GC.Print(GC.L["Buy: no run selected."])
  end
  local attempt = GC.Buy._attempt
  GC.Print(("attempt: stage=%s item=%s"):format(
    attempt and tostring(attempt.stage) or "none", attempt and tostring(attempt.itemID) or "n/a"))
  local strandedCount, strandedParts = 0, {}
  for itemID, record in pairs(GC.Buy._stranded) do
    strandedCount = strandedCount + 1
    strandedParts[#strandedParts + 1] = ("#%s qty=%s age=%ds"):format(
      tostring(itemID), tostring(record.qty), time() - (record.at or time()))
  end
  GC.Print(("stranded: %d%s"):format(strandedCount,
    strandedCount > 0 and (" (" .. table.concat(strandedParts, ", ") .. ")") or ""))
  for _, line in ipairs(current and current:Lines() or {}) do
    local state = ""
    if line.vendor then state = GC.L["vendor"]
    elseif line.done then state = GC.L["done"]
    elseif line.kind == "craft" then state = GC.L["craft"]
    elseif line.locked then state = GC.L["Pro"] end
    GC.Print((GC.L["  %s · need %d · have %d · buy %d · %s"]):format(
      lineName(line), line.need, line.have, line.buy, state))
  end
  local log = GC.Buy._log
  for i = math.max(1, #log - 4), #log do
    GC.Print(("log: %s"):format(log[i].text))
  end
  -- The header row, cell by cell: what the client thinks each heading is, where it sits and
  -- whether it is drawn. A heading can exist, be anchored and still show no text (see
  -- restampHeadings); this is how that is told apart from a cell that is not there at all.
  local header = band and band.header
  if header and header.cells then
    for _, col in ipairs(COLUMNS) do
      local cell = col.flex and header.reagentCell or header.cells[col.key]
      if cell then
        local label = cell.label
        GC.Print(("header %s: shown=%s vis=%s w=%s left=%s right=%s text=%q strw=%s lvl=%s"):format(
          col.key, tostring(cell.IsShown and cell:IsShown()), tostring(cell.IsVisible and cell:IsVisible()),
          tostring(cell.GetWidth and math.floor((cell:GetWidth() or 0) + 0.5)),
          tostring(cell.GetLeft and cell:GetLeft() and math.floor(cell:GetLeft() + 0.5)),
          tostring(cell.GetRight and cell:GetRight() and math.floor(cell:GetRight() + 0.5)),
          tostring(label and label.GetText and label:GetText()),
          tostring(label and label.GetStringWidth and math.floor((label:GetStringWidth() or 0) + 0.5)),
          tostring(cell.GetFrameLevel and cell:GetFrameLevel())))
      end
    end
  end
end
