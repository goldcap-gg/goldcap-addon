local _, GC = ...

-- The BUY tab: one shopping run at a time, rendered as "what do I still need, what have I
-- already got, what should the rest cost". The arithmetic is entirely Core/BuyRun.lua's --
-- this file owns only the picking of the run, the four things the client alone can answer
-- (bag counts, market value, the price cap setting, the free-line limit), and the drawing.
--
-- Buying (BUY 2.0) is pick, press, press: a left click on a row picks its line for the dock at
-- the foot of the tab and quotes it against the live commodity book (the ticker quotes the line
-- the dock lands on by itself), the dock's one button starts the purchase for exactly that
-- quantity, and a second press confirms the price the server came back with. Both protected
-- C_AuctionHouse calls are reached ONLY from the player's own hardware click on that button or
-- the Enter key (the addon's engineering notes' "Protected actions"), which
-- spec/buy_purchase_wiring_spec.lua pins against this file's source text. A hover explains a line
-- and, after a short rest, reads its book for the tooltip -- never for a purchase.
--
-- Presentation is the Sold tab's (UI/SoldFrame.lua): one COLUMNS table driving both the
-- header row and every pooled row, zebra/hover through the engine's own HIGHLIGHT layer. Its
-- three columns are as wide as what they hold in the player's language (fitColumns), and a name
-- that does not fit wraps. Duplicated rather than shared -- as Sold duplicates it from Deals --
-- because these locals do not cross files.
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
  -- The band above the table: the list picker, how much of it is done, what is left to buy here
  -- and a thin progress bar. Its least height; it grows when a long name or line wraps (layoutBand).
  BAND_HEIGHT = 48,
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
  -- How long a Start cancelled before the server answered it keeps the shared slot, waiting for
  -- that answer to arrive and be swallowed (final money review I1): the Sniper's own bound for the
  -- same wait, LIM.DRAIN_TIMEOUT_SECONDS, and like every hold here inside the claim's life.
  DRAIN_SECONDS = 20,
  -- The last seconds of a quote the CONFIRM button counts down (fix round 4): Blizzard's own buy
  -- dialog shows them from ten (REMAINING_QUOTE_DURATION_THRESHOLD).
  COUNTDOWN_SECONDS = 10,
  -- Deep commodity books run to thousands of price levels and a purchase only ever walks as far
  -- as the cap lets it; the same bound UI/SniperFrame.lua's commodityBook uses.
  MAX_LEVELS = 60,
  LOG_LINES = 20,
  -- How long a stranded confirm is worth keeping. GC.Sniper's _strandedConfirmed uses the same
  -- ten minutes for the same reason: long enough for a server that is merely slow, short enough
  -- that a record cannot still be sitting there when an unrelated purchase of the same item
  -- turns up and gets credited with it.
  STRANDED_SECONDS = 600,
  -- How long the band says a run's plan was recomputed on the site. A day: long enough that a
  -- player who logs in once between sessions still reads it, short enough that it is news.
  NOTICE_SECONDS = 86400,
  -- The next-purchase dock at the foot of the tab: the item on one line, what it costs on the
  -- next, one button that buys. DOCK_H is its least height; it grows to whatever its two lines
  -- need once they wrap (layoutDock). Its buttons are as wide as their labels in the player's
  -- language (fitButton), never less than these.
  DOCK_H = 52,
  DOCK_BUY_MIN_W = 96,
  DOCK_SECOND_MIN_W = 72,
  -- How long a read of a line's book is still worth drawing (the tooltip's ladder, PRICE EACH, the
  -- dock's sub-line). Much longer than QUOTE_SECONDS: this is a number to read, not one to spend,
  -- and what a click spends is still only a fresh quote of the line's own (planBuyClick).
  LADDER_SECONDS = 60,
  -- How long the pointer has to rest on a row before its tooltip asks the auction house for the
  -- line's book (lookLine): long enough that sweeping the cursor down the list asks nothing.
  LOOK_DWELL_SECONDS = 0.35,
  -- The search box and the filter, in a row of their own under the band: shown for a run longer
  -- than TOOLS_MIN_LINES, or while either is in use -- a short list is read at a glance.
  TOOLS_H = 26,
  TOOLS_MIN_LINES = 8,
  -- A window at least this wide (undocked and dragged wide) lists the player's lists in a column
  -- of its own on the left, LISTS_W across.
  WIDE_MIN = 880,
  LISTS_W = 196,
  -- The item box's well (BUY 2.0's quick list): as wide as this, or the row when that is narrower.
  ADD_W = 260,
  -- BUY 2.0 week 2: the most rows of a lot line's search this tab reads (the Buyout sort puts the
  -- cheapest first, so the first page holds every lot a press could buy).
  MAX_LOTS = 100,
  -- How many other variants one read may arm when the armed one has sold out from under it.
  MAX_REARMS = 3,
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
-- The same for a gear line's bid (BUY 2.0 week 2): a PlaceBid whose answer did not come -- the
-- watchdog gave up, the auction house closed on it, or an error arrived that could be another
-- request's -- keyed by the auctionID its late AUCTION_HOUSE_PURCHASE_COMPLETED will name, so it is
-- booked exactly once. Unlike a commodity event that completion names its auction, so a record is
-- good across an auction house close and reopen too, for BD.STRANDED_SECONDS.
--
--   auctionID -> { itemID, total, runCode, itemKey, have, at }
GC.Buy._bidStranded = {}
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
  return stage == "started" or stage == "confirm" or stage == "confirming" or stage == "bidding"
end

local function setColor(fontString, color)
  if fontString and color then
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  end
end

-- Mirrors SellFrame/SoldFrame's formatAmount: plain "65g24s" text, coin icons only below one
-- gold (icon escapes truncate mid-escape in clipped FontStrings).
-- `gold` goes through GC.Util.IntText, not %d: WoW's own string.format raises "integer
-- overflow attempting to store N" past +-2^31 copper (about 214,748g). `silver` stays on %d:
-- it is bounded 0-99 by the mod above.
local function formatAmount(amount)
  if amount == nil then return EM_DASH end
  if amount < 0 then return "-" .. formatAmount(-amount) end
  if amount >= 10000 then
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    if silver == 0 then return GC.Util.IntText(gold) .. "g" end
    return GC.Util.IntText(gold) .. ("g%02ds"):format(silver)
  end
  return GC.Util.CoinText(amount)
end

-- Money as plain text, for a list the player copies out of the game. formatAmount's sub-gold
-- branch returns GC.Util.CoinText, which is icon ESCAPES: they draw beautifully in a
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

-- BUY 2.0's three columns: the item and how many are left to buy (the flex column), what one
-- unit costs, and what the rest of the line costs. A line that is not simply ready to buy says
-- why in one word across the two price columns instead (row.status). `w` is each fixed column's
-- least width; fitColumns widens it to whatever its heading and its cells need in the player's
-- language, so nothing in them is ever cut short.
local COLUMNS = {
  { key = "item",  flex = true },
  { key = "price", w = 72, num = true, size = 11 },
  { key = "cost",  w = 84, num = true, size = 11 },
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
  item = "ITEM", price = "PRICE EACH", cost = "COST",
}
local function headerText(key) return GC.L[HEADER_TEXT[key] or ""] end

-- The filter's choices, in GC.BuyView.FILTERS' order.
-- @localised-keys: literals in this table ARE GC.L keys, looked up where the filter is drawn.
-- The table closes with a `}` on its own line.
local FILTER_LABEL = {
  all = "All", buy = "To buy", over = "Over cap", vendor = "At a vendor", craft = "To craft",
  done = "Bought", skipped = "Skipped",
}

-- The width a fixed column is drawn at this render (fitColumns), or its least.
local function columnWidth(col)
  return (band and band.colW and band.colW[col.key]) or col.w
end

-- Anchors every fixed COLUMNS entry's RIGHT edge right-to-left off `host`'s own RIGHT edge at its
-- fitted width; returns the flex ("item") column's anchor pair. The same shape as SniperFrame's
-- anchorColumns, less its column drop: three columns never drop.
local function anchorColumns(host, cellFor)
  local prev, prevPoint = host, "RIGHT"
  local flexAnchor
  for i = #COLUMNS, 1, -1 do
    local col = COLUMNS[i]
    if col.flex then
      flexAnchor = { frame = prev, point = prevPoint }
    else
      local cell = cellFor(col)
      cell:ClearAllPoints()
      cell:SetWidth(columnWidth(col))
      if prevPoint == "RIGHT" then
        cell:SetPoint("RIGHT", prev, "RIGHT")
      else
        cell:SetPoint("RIGHT", prev, "LEFT", -Theme.pad.s, 0)
      end
      prev, prevPoint = cell, "LEFT"
    end
  end
  return flexAnchor
end

-- The two price columns together, the gap between them included: the width a row's status word
-- has, and what the item column leaves room for.
local function priceArea()
  local sum, n = 0, 0
  for _, col in ipairs(COLUMNS) do
    if not col.flex then sum, n = sum + columnWidth(col), n + 1 end
  end
  return sum + math.max(0, n - 1) * Theme.pad.s
end

local createRow, layoutRow, headerLayout

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

-- The player's own price for one line of a run: GC.db.runLineCaps[code][itemID] = copper per unit.
-- Beside the run, not on it, for the reason the splits are (a companion sync replaces the run
-- wholesale), and created only when a write needs it, for the reason splitsFor gives.
local function lineCapsFor(code, create)
  local db = GC.db
  if type(db) ~= "table" or type(code) ~= "string" or code == "" then return nil end
  if type(db.runLineCaps) ~= "table" then
    if not create then return nil end
    db.runLineCaps = {}
  end
  local set = db.runLineCaps[code]
  if type(set) ~= "table" then
    if not create then return nil end
    set = {}
    db.runLineCaps[code] = set
  end
  return set
end

-- Stores the player's price for a line, or clears it (nil): a cleared cap leaves nothing behind.
local function setLineCap(code, itemID, copper)
  local set = lineCapsFor(code, copper ~= nil)
  if not set then return end
  set[itemID] = (type(copper) == "number" and copper > 0) and math.floor(copper) or nil
end
GC.Buy._SetLineCap = setLineCap -- spec seam

-- Lines skipped for this session (the dock's Skip, the row menu): GC.Buy._skipped[code][itemID].
-- Session only, on purpose -- the dock says "skipped for this session, it stays on the list".
GC.Buy._skipped = {}
local function isSkipped(line)
  local code = current and current:Code()
  local set = code and GC.Buy._skipped[code]
  return (set and line and set[line.itemID]) and true or false
end
local function setSkipped(itemID, on)
  local code = current and current:Code()
  if not code then return end
  GC.Buy._skipped[code] = GC.Buy._skipped[code] or {}
  GC.Buy._skipped[code][itemID] = on and true or nil
end

-- The run on screen as the STORE holds it. `current` is the arithmetic object built from it, and
-- the three things the site says ABOUT a run -- it is an alert group's hits, somebody else owns
-- it, it came from a plan -- live on the stored run rather than on the object.
local function shownRunData()
  if not (current and GC.AppRuns and GC.AppRuns.Get) then return nil end
  return GC.AppRuns.Get(current:Code())
end

-- An alert group's live hits: its lines' caps are the group's own target prices, set on
-- goldcap.gg, so nothing here offers to move them.
local function alertRun()
  local shown = shownRunData()
  return shown ~= nil and shown.k == "alert"
end

-- What the site last changed about this run, for as long as it is still news. Written by
-- Core/AppRuns.lua's Adopt when a run it already had came back with different lines; a recompute
-- that only moved a quantity has nothing to count, and says so without the figures rather than
-- with two zeroes.
local function noticeText(code)
  local db = GC.db
  local notices = type(db) == "table" and db.runNotices or nil
  local notice = (type(notices) == "table" and code) and notices[code] or nil
  if type(notice) ~= "table" then return nil end
  local at = tonumber(notice.at)
  if not at or (time() - at) >= BD.NOTICE_SECONDS then return nil end
  local added, removed = tonumber(notice.added) or 0, tonumber(notice.removed) or 0
  if added == 0 and removed == 0 then return GC.L["plan updated on goldcap.gg"] end
  return (GC.L["plan updated on goldcap.gg · +%d −%d lines"]):format(added, removed)
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

-- The reference a line is priced and capped against. The player's own single scan is not one
-- (GC.DealMath.IsOwnScan, the rule Measure applies everywhere else): when it is all
-- GetItemValue has, the community price is asked for directly -- GetItemValue hands back the
-- FRESHER of the two, so the player's scan can hide a community price -- and without one the
-- line has no usual price and no cap. Community prices, and every retail source, pass as before.
local function usualUnit(itemID)
  local value = GC.Data and GC.Data.GetItemValue and GC.Data.GetItemValue(itemID)
  if type(value) ~= "table" then return nil end
  if GC.DealMath.IsOwnScan(value) then
    local community = GC.Data.ForeverReference and GC.Data.ForeverReference(itemID, 0)
    return community and community.source == "crowd" and community.value or nil
  end
  return value.mv
end

-- The crowd reference for an item -- WoW: Forever's prices from other players' scans
-- (Core/Data.lua) -- or nil. The only reference that says whose price it is and how old, which is
-- what the tooltip's Source line needs; every other source answers nil, so retail is untouched.
local function usualRef(itemID)
  local ref = GC.Data and GC.Data.ForeverReference and GC.Data.ForeverReference(itemID, 0)
  if type(ref) ~= "table" or ref.source ~= "crowd" or not ref.value then return nil end
  return ref
end

local DRIVER = {
  now = function() return time() end,
  haveOf = haveOf,
  usualUnit = usualUnit,
  usualRef = usualRef,
  -- A run's own cap when it has been given one in the run menu, the global setting otherwise,
  -- clamped at the read either way (see runCapPct/globalCapPct above).
  capPct = runCapPct,
  -- Which of this run's lines are being crafted rather than bought. Asked on every Refresh,
  -- unlike progress: the row menu writes it and re-renders, and the answer has to be current.
  splits = function(code) return splitsFor(code) end,
  -- The player's own price per line (BUY 2.0's cap box, the dock's RAISE CAP), same reasoning.
  lineCaps = function(code) return lineCapsFor(code) end,
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
}

-- The same questions for a run that is NOT on screen, asked by the wide window's list column:
-- its progress is read and never created -- DRIVER.progress makes an empty table for every run it
-- is asked about, and listing twenty runs must not write twenty rows into SavedVariables.
local LIST_DRIVER = setmetatable({
  progress = function(code)
    local db = GC.db
    local context = GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
    local mine = type(db) == "table" and type(db.buyProgress) == "table"
      and db.buyProgress[context and context.char or "?"] or nil
    return type(mine) == "table" and type(mine[code]) == "table" and mine[code] or nil
  end,
}, { __index = DRIVER })

local function runList()
  return (GC.AppRuns and GC.AppRuns.List and GC.AppRuns.List()) or {}
end
local openRunMenu -- defined after cycleRun; the band's picker is the only caller
local vendorListText -- defined with the rows; the run menu's "Copy vendor list" reads it

-- The run's own name if the site gave it one, otherwise its code -- never an invented label.
-- The quick list (BUY 2.0, Core/AppRuns.lua's AddQuick) is named in the player's language.
local function isQuickRun(code)
  local stored = code and GC.AppRuns and GC.AppRuns.Get and GC.AppRuns.Get(code) or nil
  return type(stored) == "table" and stored.quick == true
end

local function runLabel(run)
  if run and isQuickRun(run:Code()) then return GC.L["Quick list"] end
  return (run and (run:Name() or run:Code())) or ""
end

function GC.Buy.CurrentRun() return current end

-- What the list is narrowed to: one of GC.BuyView.FILTERS, and a name to look for. Both belong
-- to the list on screen and are forgotten when another is picked (GC.Buy.SelectRun).
GC.Buy._filter, GC.Buy._query = "all", ""

-- The wide window's list column: how far the rest of the tab starts from the left (0 while the
-- column is hidden), and each list's progress, worked out once per Show, purchase or bag change
-- rather than on every render -- a run that is not on screen needs a BuyRun of its own.
GC.Buy._leftInset = 0
GC.Buy._listMeta = {}

function GC.Buy._SetFilter(key)
  GC.Buy._filter = key or "all"
  GC.Buy.RefreshIfShown()
end

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
  GC.Buy._filter, GC.Buy._query = "all", ""
  GC.Buy._adding = nil
  if band and band.tools then band.tools.search:SetText("") end
  -- A quote is a plan against one run's lines. A purchase already in the client's hands keeps
  -- its attempt -- its terminal event still has to land somewhere, and OnCommodityPurchaseSucceeded
  -- checks the run code before it credits anything to a line.
  if not inFlight(GC.Buy._attempt) then
    GC.Buy._attempt, GC.Buy._focus, GC.Buy._quotedFocus = nil, nil, nil
  end
  if not run then
    current, currentUpdatedAt = nil, nil
    if sniper then sniper.buyRun = nil end
    return
  end
  if sniper then sniper.buyRun = run.code end
  current = GC.BuyRun.New(run, DRIVER)
  currentUpdatedAt = run.updatedAt
  current:Refresh()
  -- At a merchant, the vendor panel shows the list on screen (UI/BuyVendorPanel.lua).
  if GC.BuyVendorPanel and GC.BuyVendorPanel.OnListChanged then GC.BuyVendorPanel.OnListChanged() end
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
  local name = run.quick and GC.L["Quick list"] or run.name or run.code or "?"
  local count = type(run.lines) == "table" and #run.lines or 0
  -- Where a run came from, in one word: the site, the player's own clipboard, or -- for a run
  -- the player follows -- whose it is.
  local origin = "goldcap.gg"
  if run.origin == "paste" then
    origin = GC.L["pasted"]
  elseif type(run.by) == "string" and run.by ~= "" then
    origin = (GC.L["from %s"]):format(run.by)
  end
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
    -- Core/AppRuns.lua already orders the list own -> followed -> pasted -> alert, so the
    -- divider goes in at the first alert run and never again: the alert groups are the tail.
    local alertsTitled = false
    for _, run in ipairs(list) do
      local code = run.code
      if run.k == "alert" and not alertsTitled then
        alertsTitled = true
        root:CreateDivider()
        root:CreateTitle(GC.L["Alerts"])
      end
      root:CreateButton(runMenuLabel(run), function()
        GC.Buy.SelectRun(code)
        GC.Buy.RefreshIfShown()
      end)
    end
    root:CreateDivider()
    local shown = shownRunData()
    -- A run the site owns -- an alert group's live hits, or somebody else's list the player
    -- follows -- carries none of the three decisions below. Its cap is the alert's own target
    -- price, it comes and goes with the group or the follow, and Unfollow lives on goldcap.gg:
    -- an Archive or a Remove here would last exactly until the next sync.
    local siteManaged = shown ~= nil
      and (shown.k == "alert" or (type(shown.by) == "string" and shown.by ~= ""))
    -- A purchase in flight has already committed to this run's `current`: re-capping the lines
    -- or archiving out from under it is exactly the hole Finding 1 describes (`settlePurchase`
    -- would book the gold nowhere a bought-count can see it). Runs/remove/paste are unaffected.
    if siteManaged then
      if shown.k == "alert" then root:CreateTitle(GC.L["cap: alert target"]) end
      root:CreateTitle(GC.L["From goldcap.gg — manage it there"])
    elseif shown and not inFlight(GC.Buy._attempt) then
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
    -- The run's vendor stops as text to take out of the game: the one part of a run the game
    -- cannot help with. Harmless for a run the site owns too.
    if vendorListText() then
      root:CreateButton(GC.L["Copy vendor list"], function()
        local text = vendorListText()
        if text and GC.UI and GC.UI.ShowVendorList then GC.UI.ShowVendorList(text) end
      end)
    end
    if shown and shown.origin == "paste" then
      root:CreateButton(GC.L["Remove this run"], removeCurrentRun)
    elseif shown and not siteManaged then
      root:CreateTitle(GC.L["From goldcap.gg — remove it there"])
    end
    root:CreateButton(GC.L["Paste a run..."], function()
      if GC.UI and GC.UI.ShowImportDialog then GC.UI.ShowImportDialog() end
    end)
    -- The item box: on the quick list, or -- with none yet -- at the foot of the list on screen,
    -- which stays; the quick list is made by the first item added.
    root:CreateButton(GC.L["Item to add"], function()
      if isQuickRun(GC.AppRuns.QUICK) then
        GC.Buy.SelectRun(GC.AppRuns.QUICK)
      else
        GC.Buy._adding = true
      end
      GC.Buy.RefreshIfShown()
      local add = GC.Buy._view and GC.Buy._view.add
      if add and add.box.SetFocus then add.box:SetFocus() end
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
-- already cover, a line being crafted rather than bought, a line skipped for this session -- is
-- never quoted, never bought and never the dock's next purchase (planBuyClick, quote,
-- nextOpenAfter and the dock all ask this one question).
local function buyable(line)
  return line ~= nil and not line.vendor and line.kind ~= "craft"
    and not line.done and line.buy > 0 and not isSkipped(line)
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
  -- A gear line's bids with no answer (GC.Buy._bidStranded): each may have bought its lot, so the
  -- line is not offered past its need -- held once those bids could cover what is left to buy --
  -- until HAVE moves, the late answers land or the records age out.
  local holding, bids = nil, 0
  for auctionID, bid in pairs(GC.Buy._bidStranded) do
    if (time() - (bid.at or 0)) > BD.STRANDED_SECONDS then
      GC.Buy._bidStranded[auctionID] = nil
    elseif bid.itemID == line.itemID and (bid.have == nil or line.have == bid.have) then
      holding, bids = bid, bids + 1
    end
  end
  if holding and bids >= (line.buy or 0) then return holding end
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
-- agree with the button -- swallowed, the keystroke did nothing, and it reached planBuyClick for a
-- line the player may not touch.
local function actionable(line)
  if not line then return false end
  if strandedFor(line) then return false end
  local attempt = GC.Buy._attempt
  if attempt and attempt.itemID == line.itemID and attempt.stage == "confirm" then return true end
  return buyable(line)
end

-- A gear line's read is fresh only while nothing has searched since its own exact-key search went
-- out (GC.Buy._searchSeq, counted by the post-hooks GC.Buy._WatchSearches installs): PlaceBid buys
-- only while the auction house's current search is a buy search for the lot's own key, and returns
-- with no error and buys nothing otherwise (BUY 2.0 probe, 2026-10-01).
local function quoteFresh(attempt)
  return attempt ~= nil and attempt.stage == "quoted" and attempt.quotedAt ~= nil
    and (time() - attempt.quotedAt) < BD.QUOTE_SECONDS
    and (attempt.armSeq == nil or attempt.armSeq == (GC.Buy._searchSeq or 0))
end

-- A question already on the wire, and still worth waiting for. The client drops a throttled
-- search without a word (AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED is the only hint, and it names
-- nothing), so a `quoting` stage with no answer has to age out the same way a quote does -- or
-- the line sits on "quoting..." for the rest of the session, refusing to ask again.
local function quotePending(attempt)
  return attempt ~= nil and attempt.stage == "quoting"
    and (time() - (attempt.askedAt or 0)) < BD.QUOTE_SECONDS
end

-- A hover's read of another line's book (BUY 2.0's tooltip ladder). It shares the client's one
-- commodity buffer with the dock's quote, so only one of the two is ever out, and it never touches
-- GC.Buy._attempt: what it learns goes to `quotes` for drawing, never for spending. Ages out like
-- a quote, for the same reason: the client drops a throttled search without a word.
GC.Buy._look = nil
local function lookPending()
  local look = GC.Buy._look
  return look ~= nil and (time() - (look.askedAt or 0)) < BD.QUOTE_SECONDS
end

-- The last quote this line got, for the line's whole remaining quantity, while it is inside
-- BD.QUOTE_SECONDS -- or nil. A quote outlives the hover that asked for it: the COST cell keeps its
-- sum, and the button keeps its "BUY n". It is what the line SHOWS, not what a click spends: a
-- click buys only on the line's own attempt holding a fresh quote (planBuyClick), and otherwise asks
-- the auction house again -- which waits while a keys batch is out (quote, GC.Buy._owedByClick).
local function recentQuote(line)
  local recent = quotes[line.itemID]
  if recent and recent.qty == line.buy and recent.qty > 0
      and (time() - (recent.at or 0)) <= BD.QUOTE_SECONDS then
    return recent
  end
  return nil
end

-- The whole seconds the quote at CONFIRM has left, while BD.COUNTDOWN_SECONDS or fewer remain, or
-- nil (fix round 4, m2). Said on the dock's second line ("Blizzard's price: X · 9 s left"), never on
-- the button: "CONFIRM (9)" lost its digit to the button's edge in seven languages (fix round 5).
local function quoteSecondsLeft(attempt)
  if not (attempt and attempt.stage == "confirm" and attempt.stallEnds) then return nil end
  local left = math.ceil(attempt.stallEnds - (GetTime and GetTime() or time()))
  if left < 1 or left > BD.COUNTDOWN_SECONDS then return nil end
  return left
end

-- A purchase the OTHER window confirmed is still owed its answer: nothing here may start one (the
-- click refuses, and the line's button waits).
--
-- Final money review: and two more that a Start here would land on. The Sniper holding the slot --
-- a purchase it started and has not confirmed, or the drain of one it cancelled unanswered -- the
-- mirror of the Sniper waiting over a live BUY claim (n1). And this tab's own drain (I1,
-- GC.Buy._StartDrain): the answer to the Start it cancelled is still coming, and a Start now
-- would read it as its own.
local function owedElsewhere()
  if GC.Buy._drain then return true end
  -- BUY 2.0 week 2: a realm bid of the Deals window waiting for its answer. An auction house error
  -- names no request, so this tab does not bid or start over it (GC.Sniper.BidOut).
  if GC.Sniper and GC.Sniper.BidOut and GC.Sniper.BidOut() then return true end
  -- Load-bearing round (M-3): this tab's own confirm the auction house closed on, still owed its
  -- answer (GC.Buy._owedUntil): nothing else starts here over it, as nothing starts in the Sniper.
  if GC.Buy._owedUntil and GC.Buy.ConfirmOwed() then return true end
  local slot = GC.PurchaseSlot
  if not slot then return false end
  local owed = slot.ConfirmOwed and slot.ConfirmOwed()
  if owed ~= nil and owed ~= "buy" then return true end
  return (slot.Owner and slot.Owner() == "sniper" and slot.IsBusy and slot.IsBusy()) and true or false
end

-- "▲N% over ..." for an attempt the cap stopped, against whose ceiling it was (overUsualPct). A
-- site ceiling (`cc`) is an alert group's target on an alert run, and on an ordinary list the cap
-- its owner set on goldcap.gg -- theirs, like one typed here.
local function overText(attempt)
  if attempt.overTarget == "target" and alertRun() then
    return (GC.L["▲%d%% over the alert target"]):format(attempt.overPct)
  elseif attempt.overTarget == "target" or attempt.overTarget == "yours" then
    return (GC.L["▲%d%% over your cap"]):format(attempt.overPct)
  end
  return (GC.L["▲%d%% over usual"]):format(attempt.overPct)
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
  -- A quote held back for an unanswered keys batch (quote): the ask is taken and will go the moment
  -- the batch is gone. Said like a question already on the wire, not as a resting "BUY n" whose
  -- click could do nothing yet (caps fixes 5i) -- for a line with no fresh quote only: one that has
  -- one keeps its own label, as it did before the batch went out.
  --
  -- Final review m10: and a line that has one, after a click on it: the click asked again (a quote
  -- shown is not one a click spends -- recentQuote) and the ask is waiting too, so the button says
  -- so instead of reading "BUY n", enabled, as if the click had done nothing.
  if GC.Buy._quoteOwed == line.itemID and not inFlight(attempt)
      and not (attempt and attempt.itemID == line.itemID and quoteFresh(attempt))
      and (not recentQuote(line) or GC.Buy._owedByClick == line.itemID) then
    return GC.L["..."], false
  end
  if not attempt or attempt.itemID ~= line.itemID then
    -- Some other line is mid-purchase. A click here cannot start a second one (planBuyClick and
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
    -- A gear line: one lot per press, the one its own read chose (GC.BuyLots.Next). With none, the
    -- reason, never a press that could only fail: no cap is no bid at all (a bid has no quote step
    -- to catch a mistake), and a wallet that cannot pay is said before the auction house says it.
    if attempt.lots then
      if attempt.lot then
        if owedElsewhere() then return GC.L["waiting..."], false end
        return (GC.L["BUY ONE · %s"]):format(formatAmount(attempt.lot.buyout)), true
      end
      if attempt.lotWhy == "nocap" then return GC.L["set a cap first"], false end
      if attempt.lotWhy == "wallet" then return GC.L["not enough gold"], false end
      if attempt.lotWhy == "over" then return GC.L["over your cap"], false, "warn" end
      return GC.L["nothing on offer"], false
    end
    if (attempt.qty or 0) > 0 then
      -- Fix round 2: a click here would start a purchase, and one the Sniper confirmed is still
      -- owed its answer (GC.PurchaseSlot.ConfirmOwed): the button waits, as the Sniper's own Buy
      -- does over it, and reads BUY again once that purchase has its answer (the Sniper repaints
      -- this tab when it settles).
      if owedElsewhere() then return GC.L["waiting..."], false end
      -- A partial fill: the cap stopped the ladder part-way, so what is on the button is real
      -- but it is not the whole line. The button wears the over-cap look and the dock's second
      -- line says how many of the line fit; how far over the rest sits is on the log line
      -- OnCommodityResults writes, which is what `/gc buy` prints.
      return (GC.L["BUY %d"]):format(attempt.qty), true, attempt.capped and "warn" or nil
    end
    -- Nothing under the cap. The percentage is the honest reason -- "this costs half again what
    -- it usually does" is a decision the player can make; a greyed-out button is not.
    if attempt.overPct then return overText(attempt), false, "warn" end
    return GC.L["nothing on offer"], false
  end
  if stage == "started" or stage == "bidding" then return GC.L["buying..."], false end
  -- The seconds the quote has left are counted on the dock's second line, not here.
  if stage == "confirm" then return GC.L["CONFIRM"], true end
  if stage == "confirming" then return GC.L["confirming..."], false end
  if stage == "requote" then
    return (GC.L["price moved to %s"]):format(formatAmount(attempt.movedTotal)), true
  end
  if stage == "expired" then return GC.L["took too long — try again"], true end
  -- Confirm reached the server and nothing came back. Not offered as a retry: the units may
  -- already be paid for, and the mailbox is where the answer is -- an auction house purchase is
  -- delivered as "Auction won" mail, so the bag re-count only settles it once that mail is taken.
  -- A gear line with more to buy than its unanswered bids could cover (strandedFor said nothing
  -- above) goes on: the next press reads its lots again.
  if stage == "unknown" and attempt.lots and attempt.auctionID then return resting, true end
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

-- Whether a purchase this tab confirmed is still owed its answer: Confirm reached the server and
-- neither a terminal event, a re-quote nor the confirming timeout (retireStalled) has spoken since.
-- Half of GC.PurchaseSlot.ConfirmOwed, the rule both windows start by.
--
-- Final money review M3: and a confirm the auction house closed on, until the moment this tab would
-- have stopped waiting for it anyway (its confirming stall, `_owedUntil`) -- across the reopen, as a
-- Sniper confirm carried across a close holds this tab. It went to "unknown" and stopped counting
-- at once, and the Sniper could start while this purchase might still take the gold its own
-- checks were counting.
function GC.Buy.ConfirmOwed()
  local attempt = GC.Buy._attempt
  if attempt ~= nil and attempt.stage == "confirming" then return true end
  local untilAt = GC.Buy._owedUntil
  if untilAt and (GetTime and GetTime() or time()) < untilAt then return true end
  -- A question only: it used to clear the lapsed stamp here, and the 0.25 s auction house ticker
  -- asks it four times a second (GC.Sniper._TickOwedHold), so that write rode every tick into the
  -- one field both purchase clicks read before their protected call. In WoW: Forever the ticker's
  -- execution was tainted, and the Buy it reached was blocked (3c beta taint log). A lapsed stamp
  -- answers false all the same.
  return false
end

-- Final money review I1: a Start cancelled before the server answered it -- the watchdog's -- still
-- has that answer coming, and commodity events name no attempt. With the slot released at once, the
-- Sniper could start in the gap and this Start's late quote reached it (and, the other way round,
-- the Sniper's lit this tab's CONFIRM at a total nobody here quoted). So the slot stays this tab's,
-- the claim re-stamped, until the drain is over: the late quote or failure arrives and is swallowed
-- here (the terminal handlers below), or BD.DRAIN_SECONDS pass. Nothing here starts meanwhile
-- (owedElsewhere).
function GC.Buy._StartDrain()
  local drain = {}
  GC.Buy._drain = drain
  if GC.PurchaseSlot then GC.PurchaseSlot.Claim("buy") end
  if C_Timer and C_Timer.After then
    C_Timer.After(BD.DRAIN_SECONDS, function()
      if GC.Buy._drain == drain then GC.Buy._EndDrain() end
    end)
  end
end

function GC.Buy._EndDrain()
  GC.Buy._drain = nil
  if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
  GC.Buy.RefreshIfShown()
end

-- The auction house ticker's call (UI/SniperFrame.lua, four times a second): repaints the tab once
-- a second while a CONFIRM counts down its last BD.COUNTDOWN_SECONDS (fix round 4, m2).
function GC.Buy.TickCountdown()
  -- Load-bearing round (M-1): the moment whatever this tab waited on lets go -- the Sniper's slot,
  -- a confirm owed its answer, its own drain -- the lines read BUY again, not on the next refresh up
  -- to twenty seconds later. The mirror of the Sniper's own edge (GC.Sniper._TickOwedHold).
  local waiting = owedElsewhere()
  if GC.Buy._lastWaiting and not waiting then GC.Buy.RefreshIfShown() end
  GC.Buy._lastWaiting = waiting
  local attempt = GC.Buy._attempt
  local left = quoteSecondsLeft(attempt)
  if not left or left == attempt.countdownShown then return end
  attempt.countdownShown = left
  GC.Buy.RefreshIfShown()
end

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
-- not only one IsBusy still reports: the Sniper re-stamps its claim at every stage it holds a
-- purchase in and at Confirm (GC.Sniper._ArmStall), but a confirmed purchase's success can still
-- land past GC.PurchaseSlot.MAX_SECONDS after the last stamp, with the claim still in place, and a
-- stranded record here would have taken it.
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

-- How far over its ceiling the cheapest level the cap refused sits, and whose ceiling it is
-- (Core/BuyRun.lua's `capFrom`: "yours", "target" or "default"). Computed whenever the cap
-- stopped the ladder -- before the first unit or part-way through a partial fill.
--
-- A line with an absolute ceiling (the player's own price, or an alert group's target) is
-- measured against THAT number: the site's usual price is not what refused the lot, and an alert
-- set below usual -- which is what an alert is for -- reported a NEGATIVE amount over usual. A
-- percentage that is not over anything is not a reason, so it is left unsaid and the caller says
-- what it says when there is nothing to buy.
local function overUsualPct(line, ladder)
  if not (line and line.cap) then return nil end
  local target = line.capFrom == "target" or line.capFrom == "yours"
  local against = target and line.cap or line.usual
  if not (against and against > 0) then return nil end
  for _, level in ipairs(ladder or {}) do
    if level.unit > line.cap then
      local pct = math.floor(level.unit * 100 / against) - 100
      if pct <= 0 then return nil end
      return pct, line.capFrom
    end
  end
  return nil
end

-- The quote in hand, judged again against its line as the line is now. A cap the player moved
-- (the cap box, the row menu, the dock's raise, the run's percent) or units that arrived since the
-- read change what the next press may spend -- and a press must never spend what the line's cap
-- now refuses. The book is the one the quote read; nothing is asked again. Run on every refresh,
-- so every path that moves a cap is covered by the one place that re-reads it.
-- A gear line's read judged against its line (defined with the lot read, below `failAttempt`).
local judgeLots, armLot

local function rejudgeQuote()
  local attempt = GC.Buy._attempt
  if not (current and attempt and attempt.stage == "quoted" and quoteFresh(attempt)) then return end
  local seen = quotes[attempt.itemID]
  local line = lineFor(attempt.itemID)
  -- A gear line: the lot the next press bids on is chosen again from the same rows, so a press can
  -- never bid over a cap that moved down or past a wallet that emptied. A whole-item read that now
  -- finds a lot under a raised cap searches that lot's own key, which is what a bid needs.
  if line and attempt.lots then
    local lot = judgeLots(attempt, line)
    if lot and attempt.phase == "all" then armLot(attempt, lot) end
    return
  end
  if not (line and seen and seen.ladder) then return end
  local qty, total, capped = current:PurchaseQuantity(line.itemID, seen.ladder)
  attempt.qty, attempt.total, attempt.capped = qty, total, capped
  seen.qty, seen.total, seen.capped = qty, total, capped
  attempt.overPct, attempt.overTarget = nil, nil
  if capped then attempt.overPct, attempt.overTarget = overUsualPct(line, seen.ladder) end
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

-- CancelCommoditiesPurchase fires NONE of the three terminal events (the addon's engineering notes), so it is
-- only ever used to hand a started-but-unconfirmed purchase back to the client -- never to end
-- an attempt this tab is still waiting on an event for.
local function cancelStartedPurchase()
  if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
    C_AuctionHouse.CancelCommoditiesPurchase()
  end
end

-- The dock's Cancel at CONFIRM: the quote goes back to the client and the slot with it. Exactly
-- what the confirm stage's own timeout does (retireStalled) minus the "expired" word: the quote
-- had arrived, so nothing is still coming, and CancelCommoditiesPurchase fires no event.
function GC.Buy._CancelConfirm()
  local attempt = GC.Buy._attempt
  if not (attempt and attempt.stage == "confirm") then return false end
  cancelStartedPurchase()
  if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
  logAttempt(lineFor(attempt.itemID), GC.L["Cancel"])
  GC.Buy._attempt = nil
  GC.Buy.RefreshIfShown()
  return true
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
  -- When this wait runs out, for the CONFIRM countdown (actionLabel, GC.Buy.TickCountdown).
  attempt.stallEnds = (GetTime and GetTime() or time()) + seconds
  attempt.countdownShown = nil
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
local function recordAcquisition(itemID, name, qty, total, at, runCode, itemKey)
  if not (GC.Acquisitions and GC.Acquisitions.Record and GC.Acquisitions.PositionKey) then return end
  local context = GC.Ledger and GC.Ledger.Context and GC.Ledger.Context() or nil
  acquisitionSeq = acquisitionSeq + 1
  GC.Acquisitions.Record({
    source = "goldcap_buy",
    itemID = itemID,
    -- A gear lot is filed under its own item key (level, suffix), a commodity under the item.
    positionKey = itemKey and GC.Acquisitions.PositionKey(itemID, itemKey, false)
      or GC.Acquisitions.PositionKey(itemID, nil, true),
    itemName = name,
    quantity = qty,
    total = total,
    acquiredAt = at,
    runCode = runCode,
    character = context and context.char or nil,
    region = context and context.region or nil,
    -- `at` is an epoch second, not money -- but it is still a value %d silently mishandles once
    -- WoW's own client crosses the same +-2^31 ceiling (2038), so it goes through
    -- GC.Util.IntText for the same reason every copper figure in this sweep does.
    evidenceKey = ("goldcap-buy:%d:%s:%d"):format(itemID, GC.Util.IntText(at), acquisitionSeq),
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
--
-- `mv`: the line's usual price per unit at the moment of the purchase -- the number its cap was
-- built on -- in whole copper, from which the site says how far under market a run was bought.
-- Left off (nil, so the row has no such field) when the line had no usual price.
local function recordLedgerBuy(itemID, name, qty, total, at, runCode, mv)
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
    mv = mv,
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
local function settlePurchase(itemID, qty, total, runCode, itemKey)
  if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
  qty, total = qty or 0, total or 0
  local line = lineFor(itemID)
  if current and qty > 0 and total > 0 then
    local at = time()
    -- Read before RecordPurchase re-counts the line. A vendor line is never bought here (buyable),
    -- and would carry no market price if it were: a merchant's price is not the auction house's.
    local mv = (line and not line.vendor and type(line.usual) == "number" and line.usual > 0)
      and math.floor(line.usual) or nil
    if runCode == current:Code() then current:RecordPurchase(itemID, qty, total, at) end
    recordAcquisition(itemID, line and lineName(line) or nil, qty, total, at, runCode, itemKey)
    recordLedgerBuy(itemID, line and lineName(line) or nil, qty, total, at, runCode, mv)
  end
  logAttempt(line, (GC.L["bought %d for %s"]):format(qty, formatAmount(total)), itemID)
  -- The purchase is booked against the run whether or not the units have arrived: the auction
  -- house delivers them as mail, so HAVE moves only once the player empties the mailbox, and
  -- `buy` is need - max(have, bought) precisely so the line is right in the meantime. HAVE is
  -- re-counted anyway (the mail may already be in), and the next line that still needs
  -- something takes the focus, so Enter carries on down the run without reaching for the mouse.
  scanBags()
  GC.Buy._focus = nextOpenAfter(itemID)
  -- The dock's line -- the next one, or this same gear line with more to buy -- is read again.
  GC.Buy._quotedFocus = nil
  GC.Buy._listMeta = {}
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

-- ---------------------------------------------------------------------------
-- A gear line's read (BUY 2.0 week 2). Anything the client will not sell as a commodity is bought
-- one lot per press with PlaceBid, which the BUY 2.0 probe (2026-10-01, both games) measured:
--   * it buys only while the auction house's current search is a BUY search for the lot's exact
--     item key; with any other search in between it returns, says nothing and buys nothing;
--   * a buy search on the bare key (item level 0, suffix 0) finds no lots for gear that has item
--     level or suffix variants -- only the variant's own key does.
-- So a read is two searches. First a SELL search on the bare key: Blizzard's own sell frame sends
-- exactly that for equipment, "so you can compare to similar items" (ConvertItemSellItemKey in
-- Blizzard_AuctionHouseUtil.lua, the same in both games), and its rows are every variant's lots,
-- each with its own item key. Then a buy search on the chosen lot's own key; its answer is what a
-- press bids on, and nothing may search in between (GC.Buy.HoldsSearch, GC.Buy._WatchSearches).
-- ---------------------------------------------------------------------------

local function lotSorts()
  local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Buyout
  if not order then return {} end
  return { { sortOrder = order, reverseSort = false } }
end

-- The rows the client holds for `key`, as the client gives them, and whether that is its whole
-- answer. A key with no rows and no full answer has not been answered yet.
local function readItemRows(key)
  local found = {}
  local ah = C_AuctionHouse
  if not (ah and ah.GetNumItemSearchResults and ah.GetItemSearchResultInfo) then return found, false end
  local n = ah.GetNumItemSearchResults(key) or 0
  for i = 1, math.min(n, BD.MAX_LOTS) do
    local ok, info = pcall(ah.GetItemSearchResultInfo, key, i)
    if ok and type(info) == "table" then found[#found + 1] = info end
  end
  local full = ah.HasFullItemSearchResults and ah.HasFullItemSearchResults(key) or false
  return found, full
end

-- The lot the next press would bid on (GC.BuyLots.Next: at or under the cap, at or above the item
-- level, within the wallet), from the rows of the search the read is on. Only an armed read -- the
-- answer to the lot's own key -- has a lot a press may bid on; the whole-item read only says which
-- key to arm. Returns that lot either way.
judgeLots = function(attempt, line)
  local armed = attempt.phase == "arm"
  local list = (armed and attempt.armLots or attempt.lotList) or {}
  local lot, why = GC.BuyLots.Next(list, line.cap, line.minIlvl, GetMoney and GetMoney() or nil)
  attempt.lot = armed and lot or nil
  attempt.lotWhy = why
  attempt.qty = attempt.lot and 1 or 0
  attempt.total = attempt.lot and attempt.lot.buyout or 0
  attempt.capped = why == "over"
  return lot
end

-- The armed search, when the throttle lets it go: a buy search on the lot's own key, the player's
-- own lots in rows of their own. `armSeq` is the search count right after it went (the post-hooks
-- count our own send too), so any search after it -- ours, Blizzard's pane, another addon --
-- voids the read (quoteFresh).
local function sendArm(attempt)
  if not (attempt and attempt.armDue) then return false end
  if not throttleReady() then return false end
  if GC.Util and GC.Util.ClaimThrottleSend and not GC.Util.ClaimThrottleSend("buy-arm") then return false end
  attempt.armDue, attempt.askedAt = nil, time()
  C_AuctionHouse.SendSearchQuery(attempt.key, lotSorts(), true)
  attempt.armSeq = GC.Buy._searchSeq or 0
  if GC.Sniper and GC.Sniper._NoteSearchSent then GC.Sniper._NoteSearchSent(attempt.key) end
  if GC.AuctionHouseTab and GC.AuctionHouseTab.NoteAddonSearch then GC.AuctionHouseTab.NoteAddonSearch() end
  return true
end

armLot = function(attempt, lot)
  attempt.phase, attempt.stage, attempt.askedAt, attempt.armDue = "arm", "quoting", time(), true
  attempt.key = C_AuctionHouse.MakeItemKey(attempt.itemID, lot.itemLevel or 0, lot.itemSuffix or 0,
    lot.species or 0)
  attempt.lot, attempt.qty, attempt.total, attempt.armLots, attempt.armSeq = nil, 0, 0, nil, nil
  sendArm(attempt)
end

-- What a gear line's read draws (the tooltip's ladder, PRICE EACH, the row's word, the dock's
-- price groups): every variant's lots it has seen, and what the rest of the line would cost at
-- the lot the next press buys.
local function noteLots(line, attempt, lot)
  local levels = GC.BuyLots.AsLevels(attempt.lotList, line.minIlvl)
  quotes[line.itemID] = { qty = lot and line.buy or 0, total = lot and lot.buyout * line.buy or 0,
    at = time(), capped = attempt.lotWhy == "over", ladder = #levels > 0 and levels or false,
    lots = attempt.lotList }
end

-- ITEM_SEARCH_RESULTS_UPDATED, routed by Core/Init.lua: the answer to a gear line's read, or the
-- client refreshing the armed key's lots by itself after a purchase (one lot fewer, no new query).
-- The rows are read under the key this tab sent, the only key the client answers for, so a key
-- with no rows and no full answer yet is not this read's answer. Once a lot's own key is armed, an
-- event about another variant of the item is somebody else's.
function GC.Buy.OnItemResults(itemKey)
  local attempt = GC.Buy._attempt
  if not (attempt and attempt.lots and type(itemKey) == "table" and itemKey.itemID == attempt.itemID) then
    return
  end
  local sent = attempt.key or {}
  if attempt.phase == "arm" and itemKey.itemLevel ~= nil
      and ((itemKey.itemLevel or 0) ~= (sent.itemLevel or 0) or (itemKey.itemSuffix or 0) ~= (sent.itemSuffix or 0)) then
    return
  end
  -- A bid is out: the refresh that follows a purchase is read once its completion has booked it.
  if attempt.stage == "bidding" then
    attempt.refreshed = true
    return
  end
  if not (attempt.stage == "quoting" or (attempt.stage == "quoted" and attempt.phase == "arm")) then return end
  if attempt.armDue then return end
  local line = lineFor(attempt.itemID)
  if not (current and buyable(line)) then
    GC.Buy._attempt = nil
    return
  end
  local answer, full = readItemRows(sent)
  if #answer == 0 and not full then return end
  local lots = GC.BuyLots.FromRows(answer)
  if attempt.phase == "arm" then
    attempt.armLots = lots
    attempt.lotList = GC.BuyLots.Replace(attempt.lotList, lots, sent)
  else
    attempt.lotList = lots
  end
  local lot = judgeLots(attempt, line)
  attempt.stage, attempt.quotedAt = "quoted", time()
  noteLots(line, attempt, lot)
  if attempt.phase == "all" and lot then
    armLot(attempt, lot)
  elseif attempt.phase == "arm" and not lot then
    -- The armed variant has nothing left under the cap -- sold between the whole-item read and its
    -- own, or bought out by this line's last press. Another variant the whole-item read saw may
    -- still be: it is armed instead (a few times at most per read). With none, a read after a
    -- purchase reads the item whole again on the next tick; any other says what it found.
    local other = GC.BuyLots.Next(attempt.lotList or {}, line.cap, line.minIlvl, GetMoney and GetMoney() or nil)
    if other and (attempt.rearms or 0) < BD.MAX_REARMS then
      attempt.rearms = (attempt.rearms or 0) + 1
      armLot(attempt, other)
    elseif attempt.afterBuy then
      GC.Buy._attempt, GC.Buy._quotedFocus = nil, nil
    end
  end
  logAttempt(line)
  GC.Buy.RefreshIfShown()
end

-- Asks the auction house for this line's book. One SendSearchQuery, under the addon's own
-- throttle claim, and only when there is nothing better already in hand: a quote younger than
-- BD.QUOTE_SECONDS for this same line is what the next click will spend, and a purchase in
-- flight owns the buffer until it is done.
-- `clicked`: the ask is the player's click, not a hover (final review m10, actionLabel).
local function quote(line, clicked)
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
  -- Not over an unanswered keys batch -- one still out from the Deals board the player just left,
  -- or this tab's own refresh. A search sent on top of one takes its answer and comes back empty
  -- itself (UI/SellFrame.lua's advanceQuote, seen in game): an empty quote. The line is asked for
  -- again once the batch is gone, if it still has the focus (GC.Buy.Tick).
  -- ...nor over a hover's look still out (lookLine): one question per buffer.
  if (GC.Sniper._KeysOutstanding and GC.Sniper._KeysOutstanding()) or lookPending() then
    GC.Buy._quoteOwed = line.itemID
    -- A hover over the line a click is waiting on keeps the click's word (the button's "...").
    if clicked then
      GC.Buy._owedByClick = line.itemID
    elseif GC.Buy._owedByClick ~= line.itemID then
      GC.Buy._owedByClick = nil
    end
    GC.Buy.RefreshIfShown() -- the button says it is waiting (actionLabel)
    return
  end
  if not throttleReady() then return end
  -- Claimed as "buy-quote", not "buy": the NOW batch (TrySendRefresh) already claims "buy", and
  -- under a stuck throttle flag GC.Util paces one forced send per consumer -- sharing a name
  -- would have the board's refresh and the player's own hover taking turns in one window.
  if GC.Util and GC.Util.ClaimThrottleSend and not GC.Util.ClaimThrottleSend("buy-quote") then return end

  -- A gear line (the client will not sell it as a commodity) is read whole first: a sell search on
  -- the bare key answers with every variant's lots, the player's own in rows of their own so
  -- dropping them hides nobody else's (see "A gear line's read" above).
  local lotLine = not askableItem(line.itemID)
  local key = C_AuctionHouse.MakeItemKey(line.itemID)
  if lotLine then
    C_AuctionHouse.SendSellSearchQuery(key, lotSorts(), true)
  else
    C_AuctionHouse.SendSearchQuery(key, {}, false)
  end
  -- Out until its answer lands, in the book the Sell tab reads: a "busy" it draws must not be
  -- taken for a post's refusal there (GC.Sniper.RequestOut; review sell-fix4 M3).
  if GC.Sniper and GC.Sniper._NoteSearchSent then GC.Sniper._NoteSearchSent(key) end
  -- Blizzard's own pane may open this item's buy page in answer; that page is ours, not a buy.
  if GC.AuctionHouseTab and GC.AuctionHouseTab.NoteAddonSearch then GC.AuctionHouseTab.NoteAddonSearch() end
  attemptSeq = attemptSeq + 1
  GC.Buy._attempt = {
    itemID = line.itemID, stage = "quoting", token = attemptSeq, askedAt = time(),
    runCode = current and current:Code() or nil,
    lots = lotLine or nil, phase = lotLine and "all" or nil, key = lotLine and key or nil,
  }
  logAttempt(line)
  GC.Buy.RefreshIfShown()
end

-- A hover's look at a line's book, for its tooltip's ladder. Only a line that is not the dock's
-- (the dock's own line is quoted by `quote`), that could be bought, that the client sells as a
-- commodity, and that has no read younger than BD.QUOTE_SECONDS; never while a purchase is in
-- flight, while the dock's quote is being asked for or is fresh, while another look or a keys
-- batch is out, or while the throttle is not ready. Asked under its own throttle claim.
local function lookLine(line)
  if not (line and current) or not buyable(line) then return end
  if line.itemID == GC.Buy._focus then return end
  local seen = quotes[line.itemID]
  if seen and seen.ladder ~= nil and (time() - (seen.at or 0)) < BD.QUOTE_SECONDS then return end
  local attempt = GC.Buy._attempt
  if inFlight(attempt) or quotePending(attempt) or quoteFresh(attempt) or lookPending() then return end
  if strandedFor(line) then return end
  if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey) then return end
  if not (GC.Sniper and GC.Sniper.IsAHOpen and GC.Sniper.IsAHOpen()) then return end
  if GC.Sniper._KeysOutstanding and GC.Sniper._KeysOutstanding() then return end
  if not askableItem(line.itemID) or not throttleReady() then return end
  if GC.Util and GC.Util.ClaimThrottleSend and not GC.Util.ClaimThrottleSend("buy-look") then return end
  local key = C_AuctionHouse.MakeItemKey(line.itemID)
  C_AuctionHouse.SendSearchQuery(key, {}, false)
  if GC.Sniper._NoteSearchSent then GC.Sniper._NoteSearchSent(key) end
  if GC.AuctionHouseTab and GC.AuctionHouseTab.NoteAddonSearch then GC.AuctionHouseTab.NoteAddonSearch() end
  GC.Buy._look = { itemID = line.itemID, askedAt = time() }
end

-- COMMODITY_SEARCH_RESULTS_UPDATED, routed here by Core/Init.lua. The buffer is addon-wide and
-- every consumer sees every answer, so an event for anything but the item this tab is currently
-- quoting -- or looking at for a tooltip -- belongs to somebody else and is left alone.
function GC.Buy.OnCommodityResults(itemID)
  -- A hover's look answered: drawn, never spent. The attempt, whatever it is, is not touched.
  local look = GC.Buy._look
  if look and look.itemID == itemID then
    GC.Buy._look = nil
    local line = lineFor(itemID)
    if current and line then
      local ladder = ladderFor(itemID)
      local qty, total, capped = current:PurchaseQuantity(itemID, ladder or {})
      quotes[itemID] = { qty = qty, total = total, at = time(), capped = capped, ladder = ladder or false }
      if ladder and ladder[1] then current:SetFloor(itemID, ladder[1].unit, time()) end
    end
    GC.Buy.RefreshIfShown()
    if GC.Buy._refreshTooltip then GC.Buy._refreshTooltip(itemID) end
    return
  end
  local attempt = GC.Buy._attempt
  if not attempt or attempt.stage ~= "quoting" or attempt.itemID ~= itemID then return end
  local line = lineFor(itemID)
  if not (current and buyable(line)) then
    GC.Buy._attempt = nil
    return
  end
  local ladder = ladderFor(itemID)
  -- No ladder AND the client now says this is not a commodity (its key was not cached when the
  -- line was asked): the search filled the ITEM buffer, not the commodity one. "Nothing on offer"
  -- would be a false claim about the market, so the line is read again on the next tick, as the
  -- gear line it is.
  if ladder == nil and not askableItem(itemID) then
    GC.Buy._attempt, GC.Buy._quotedFocus = nil, nil
    GC.Buy.RefreshIfShown()
    return
  end
  local qty, total, capped = current:PurchaseQuantity(itemID, ladder or {})
  attempt.qty, attempt.total, attempt.capped = qty, total, capped
  -- The ladder rides along for drawing (the tooltip, PRICE EACH, the dock's raise): `false` is a
  -- book that came back empty, which is news too.
  quotes[itemID] = { qty = qty, total = total, at = time(), capped = capped, ladder = ladder or false }
  -- Computed whenever the cap stopped the ladder, not only when it stopped it before a single
  -- unit: a partial fill needs the same number -- what the REST would have cost -- or the line
  -- silently buys six of ten and says nothing about why the other four stayed behind.
  attempt.overPct, attempt.overTarget = nil, nil
  if capped then attempt.overPct, attempt.overTarget = overUsualPct(line, ladder) end
  attempt.quotedAt = time()
  attempt.stage = "quoted"
  -- The percentage and the cheap hour ride on the log line (the dock says what the cheapest unit
  -- costs against the cap, and the button wears the over-cap variant -- actionLabel). `/gc buy`
  -- is where a player reads them back. Both belong to a refusal: a line the cap was happy with
  -- explains nothing.
  local text = nil
  if capped then
    text = actionLabel(line)
    if qty > 0 and attempt.overPct then text = ("%s %s"):format(text, overText(attempt)) end
    local cheap = cheapHourText(line)
    if cheap then text = ("%s · %s"):format(text, cheap) end
  end
  logAttempt(line, text)
  GC.Buy.RefreshIfShown()
end

-- COMMODITY_PRICE_UPDATED: the server's answer to StartCommoditiesPurchase, and the first price
-- anybody has actually seen. It does not confirm anything -- see planBuyClick.
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
  -- The late quote of a Start this tab cancelled unanswered (I1): swallowed, never read as the
  -- answer to anything, the Cancel sent again, and the drain -- and the slot -- over.
  if GC.Buy._drain then
    cancelStartedPurchase()
    GC.Buy._EndDrain()
    return true
  end
  local attempt = GC.Buy._attempt
  if not attempt or not inFlight(attempt) then return false end
  -- A bid is out (a gear line): a commodity event is never its answer, and false hands it to the
  -- Deals window exactly as when this tab holds nothing.
  if attempt.stage == "bidding" then return false end
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
    -- Never past the server's own quote, when the client can say when it runs out (fix round 4).
    armStall(attempt, GC.PurchaseSlot and GC.PurchaseSlot.QuoteSeconds
      and GC.PurchaseSlot.QuoteSeconds(BD.CONFIRM_SECONDS) or BD.CONFIRM_SECONDS)
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
  -- A bid is out (a gear line): never a commodity event's answer.
  if stage == "bidding" then return false end

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
  if GC.Buy._drain then GC.Buy._EndDrain() return true end -- the drained Start's answer (I1)
  local attempt = GC.Buy._attempt
  if attempt and attempt.stage == "bidding" then return false end -- never a bid's answer
  if attempt and (inFlight(attempt) or attempt.stage == "requote") then
    failAttempt(attempt)
    return true
  end
  return dropStrandedOnFailure()
end

function GC.Buy.OnCommodityPriceUnavailable()
  if not mayOwnTerminal() then return false end
  if GC.Buy._drain then GC.Buy._EndDrain() return true end -- the drained Start's answer (I1)
  local attempt = GC.Buy._attempt
  if attempt and attempt.stage == "bidding" then return false end -- never a bid's answer
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
  if not attempt or attempt.itemID ~= itemID or not inFlight(attempt) or attempt.lots then return false end
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
-- A bid that reached the server and got no answer of its own: the lot may be bought. The slot goes
-- back, the attempt says so (`unknown`), and the record keeps what a late
-- AUCTION_HOUSE_PURCHASE_COMPLETED needs to book it exactly once (GC.Buy.OnPurchaseCompleted) --
-- and holds the line from being bought past its need meanwhile (strandedFor).
local function strandBid(attempt, line)
  if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
  GC.Buy._bidStranded[attempt.auctionID] = { itemID = attempt.itemID, total = attempt.total,
    runCode = attempt.runCode, itemKey = attempt.itemKey, have = line and line.have or nil, at = time() }
  attempt.stage = "unknown"
end

retireStalled = function(token, stall)
  local attempt = GC.Buy._attempt
  if not attempt or attempt.token ~= token or attempt.stall ~= stall then return end
  if not inFlight(attempt) then return end
  local line = lineFor(attempt.itemID)
  if attempt.stage == "bidding" then
    strandBid(attempt, line)
    logAttempt(line)
    GC.Buy.RefreshIfShown()
    return
  end
  if attempt.stage ~= "confirming" then
    cancelStartedPurchase()
    -- Unanswered, its answer is still coming: the slot is held for it (GC.Buy._StartDrain). A
    -- quote that did come leaves nothing in flight, and the slot goes back as before.
    if attempt.stage == "started" then
      GC.Buy._StartDrain()
    elseif GC.PurchaseSlot then
      GC.PurchaseSlot.Release("buy")
    end
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
  -- A drain belongs to the session that sent the Start (I1).
  if GC.Buy._drain then
    GC.Buy._drain = nil
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
  end
  -- A quote owed to this session is not the next one's to ask: the line it was for has long lost
  -- the pointer by then, and the button would read "..." until something asked (caps fixes 5i).
  GC.Buy._quoteOwed, GC.Buy._owedByClick = nil, nil
  GC.Buy._quotedFocus, GC.Buy._look = nil, nil
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
  if stage == "bidding" then
    -- A bid may have bought (like a confirm): the slot goes, the warning stays, and its late
    -- completion is still booked after the auction house opens again. Nothing to cancel: PlaceBid
    -- has no purchase of its own to hand back.
    strandBid(attempt, line)
  elseif stage ~= "confirming" then
    cancelStartedPurchase()
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
    attempt.stage = "expired"
  else
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
    attempt.stage = "unknown"
    -- Still owed its answer across the reopen, until this tab's own wait for it would have ended
    -- (GC.Buy.ConfirmOwed, final money review M3).
    GC.Buy._owedUntil = attempt.stallEnds
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
  -- ...except a confirm the close hit while it is still owed its answer (load-bearing round, M-3):
  -- its units may still come by mail, and the line keeps saying so instead of offering BUY again.
  if attempt and attempt.stage == "unknown" and GC.Buy.ConfirmOwed() then return end
  if attempt and not inFlight(attempt) then GC.Buy._attempt = nil end
end

local function afterClick(line)
  logAttempt(line)
  GC.Buy.RefreshIfShown()
end

-- What the line's last read of the book said, for GC.BuyView.Status: the attempt's own quote when
-- it is this line's, else a recent read (an earlier quote, a hover's look) still worth drawing.
local function readOf(line)
  local attempt = GC.Buy._attempt
  if attempt and attempt.itemID == line.itemID and attempt.stage == "quoted" then
    return { qty = attempt.qty or 0, total = attempt.total, capped = attempt.capped, at = attempt.quotedAt,
             ladder = quotes[line.itemID] and quotes[line.itemID].ladder or nil }
  end
  local seen = quotes[line.itemID]
  if seen and (time() - (seen.at or 0)) <= BD.LADDER_SECONDS then return seen end
  return nil
end

-- The one word a row and the dock say about a line (GC.BuyView.Status), from what only this tab
-- knows about it.
local function lineStatus(line)
  local read = readOf(line)
  local verdict = nil
  if read and read.ladder ~= nil then
    verdict = (read.qty or 0) > 0 and "fits" or (read.capped and "over" or nil)
  end
  local byHand = not line.vendor and line.kind ~= "craft" and not askableItem(line.itemID)
  return GC.BuyView.Status(line, { skipped = isSkipped(line), stranded = strandedFor(line) ~= nil,
    byHand = byHand, quote = verdict })
end

-- The raise the dock offers this line, in copper, or nil: only while its last read found nothing
-- at or under the cap, and never on an alert group's line (its cap is the group's target, set on
-- goldcap.gg).
local function raiseOffered(line)
  if not line or alertRun() or lineStatus(line) ~= "over" then return nil end
  local read = readOf(line)
  local ladder = (read and read.ladder) or (line.floor and { { unit = line.floor, qty = 1 } }) or nil
  return GC.BuyView.RaiseTo(ladder, line.cap, line.usual)
end

-- Raises the line's own cap to what the dock offered and re-reads the quote already in hand
-- against it -- no second search: the book is the one read a moment ago, and the server's own
-- quote is judged again at Start anyway (OnCommodityPriceUpdated). A stale quote asks again.
local function raiseCap(line)
  local to = raiseOffered(line)
  if not (to and current) then return end
  setLineCap(current:Code(), line.itemID, to)
  current:Refresh()
  line = lineFor(line.itemID)
  if not line then return end
  local attempt = GC.Buy._attempt
  local seen = quotes[line.itemID]
  if attempt and attempt.itemID == line.itemID and quoteFresh(attempt) and seen and seen.ladder then
    rejudgeQuote()
  else
    quote(line, true)
  end
end

-- ---------------------------------------------------------------------------
-- The one hardware click. Nothing in this file calls a protected purchase API: this plans the
-- click and answers the one call to make, and GC.PurchaseCall.Click (Core/PurchaseCall.lua)
-- makes it, synchronously, from inside the same click or Enter key -- fenced off from what
-- this reads, which WoW: Forever would otherwise hold against the call.
-- spec/buy_purchase_wiring_spec.lua reads this file's source text and proves it.
-- ---------------------------------------------------------------------------

local function planBuyClick(line, fromDock)
  if not (line and current) then return end
  local attempt = GC.Buy._attempt

  -- The confirming click. The client only demands a hardware event for the START of a commodity
  -- purchase, so an addon MAY confirm straight from COMMODITY_PRICE_UPDATED -- and this one
  -- never will. The server's price is the first price anybody has actually seen, and agreeing to
  -- it is the player's to do (the addon's engineering notes: "Do not 'helpfully' auto-confirm anything").
  if attempt and attempt.stage == "confirm" and attempt.itemID == line.itemID
      and (attempt.qty or 0) > 0 then
    attempt.stage = "confirming"
    return "confirm", attempt.itemID, attempt.qty, function()
      armStall(attempt, BD.CONFIRM_SECONDS)
      afterClick(line)
    end
  end

  -- The client is holding a purchase of ours: a second click can only make trouble.
  if attempt and (attempt.stage == "started" or attempt.stage == "confirming" or attempt.stage == "bidding") then
    return
  end
  if not buyable(line) then return end

  -- Anything but a live quote for THIS line asks the auction house instead of spending: a stale
  -- ladder is a plan against prices somebody else has already bought off. The next click buys.
  if not (attempt and attempt.itemID == line.itemID and quoteFresh(attempt)
      and (attempt.qty or 0) > 0) then
    -- The dock's RAISE CAP TO X: a line nothing under its cap can fill has its cap raised to the
    -- price the dock names, and the quote in hand is re-read against it. No purchase call is made
    -- on this click; the next one buys. Only from the dock's own button -- Enter never moves a
    -- cap -- and only on this branch, which makes no protected call at all: what the raise reads
    -- is never read on a click that starts or confirms.
    if fromDock and raiseOffered(line) then
      raiseCap(line)
      afterClick(line)
      return
    end
    -- Focus does not move onto a line a click cannot act on while another line's purchase is in
    -- the client's hands: Enter has to keep pointing at the line waiting for its confirm.
    if not inFlight(attempt) then GC.Buy._focus = line.itemID end
    quote(line, true)
    return
  end

  -- The one rule (GC.PurchaseSlot.ConfirmOwed): never start over a purchase the Sniper confirmed
  -- that is still owed its answer, whatever the claim below says -- that claim goes stale long
  -- before such a purchase has to have answered. Nor over a purchase the Sniper holds the slot
  -- for, nor while this tab drains a Start it cancelled (owedElsewhere). Said the way the Sniper
  -- says it.
  if owedElsewhere() then
    logAttempt(line, GC.L["waiting for previous commodity purchase to settle"])
    if GC.Print then GC.Print(GC.L["waiting for previous commodity purchase to settle"]) end
    GC.Buy.RefreshIfShown()
    return
  end
  if GC.PurchaseSlot and not GC.PurchaseSlot.Claim("buy") then
    if GC.Print then GC.Print(GC.L["another purchase is in flight"]) end
    return
  end
  -- A gear line: one lot per press, the one the line's own fresh read chose (GC.BuyLots.Next -- at
  -- or under the cap, at or above the item level, within the wallet; judged again on every repaint,
  -- rejudgeQuote). PlaceBid has no quote step, so the lot and its price on the button are the whole
  -- agreement. quoteFresh above holds the read to BD.QUOTE_SECONDS and to the lot's own search
  -- being the auction house's current one; the claim above keeps it the only purchase in flight.
  -- Stage first, call second: Core/PurchaseCapture.lua's PlaceBid hook asks
  -- GC.Buy.OwnsAuctionPurchase inside the call.
  if attempt.lots then
    local lot = attempt.lot
    attempt.auctionID, attempt.total = lot.auctionID, lot.buyout
    attempt.itemKey = { itemID = line.itemID, itemLevel = lot.itemLevel or 0,
      itemSuffix = lot.itemSuffix or 0, battlePetSpeciesID = lot.species or 0 }
    attempt.stage = "bidding"
    return "bid", lot.auctionID, lot.buyout, function()
      -- Not when the client already answered inside the call (an error, a completion).
      if GC.Buy._attempt == attempt and attempt.stage == "bidding" then armStall(attempt, BD.WATCHDOG_SECONDS) end
      afterClick(line)
    end
  end
  -- Stage first, call second: Core/PurchaseCapture.lua's StartCommoditiesPurchase hook runs
  -- inside this very call and asks GC.Buy.OwnsCommodityPurchase whether the purchase is ours.
  attempt.stage = "started"
  return "start", attempt.itemID, attempt.qty, function()
    armStall(attempt, BD.WATCHDOG_SECONDS)
    afterClick(line)
  end
end

-- The dock's one button. Everything, the line included, is looked up inside the plan: the click
-- itself reads nothing before GC.PurchaseCall.Click has fenced it off. The button's parent is the
-- dock (createDock), stamped with the line it shows by paintDock.
local function planBuyButton(button)
  return planBuyClick(lineFor(button:GetParent().lineItemID), true)
end

local function onBuyButtonClick(button)
  GC.PurchaseCall.Click(planBuyButton, button)
end

-- Enter on the BUY tab: the same plan as the button, for the focused line. Everything it reads
-- is read inside the plan, for the reason the button's own is (GC.PurchaseCall.Click).
local function planBuyKey(self, key)
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
  return planBuyClick(line)
end

local function onBuyKey(self, key)
  GC.PurchaseCall.Click(planBuyKey, self, key)
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

-- A left click on a row picks its line for the dock and asks for its price -- what a hover did
-- before BUY 2.0. Focus does not move while a purchase is in the client's hands: CONFIRM belongs
-- to that line. Any line may be picked, a vendor or craft line included: the dock explains it.
local function selectLine(line)
  if not line or inFlight(GC.Buy._attempt) then return end
  GC.Buy._focus = line.itemID
  if buyable(line) then quote(line) end
  GC.Buy.RefreshIfShown()
end

-- The dock's second button: Cancel at CONFIRM, Skip on a line over its cap. Never a purchase.
local function onDockSecondaryClick(button)
  local line = lineFor(button:GetParent().lineItemID)
  if not line then return end
  local attempt = GC.Buy._attempt
  if attempt and attempt.itemID == line.itemID and attempt.stage == "confirm" then
    GC.Buy._CancelConfirm()
    return
  end
  if inFlight(attempt) then return end
  setSkipped(line.itemID, true)
  if GC.Buy._focus == line.itemID then GC.Buy._focus = nextOpenAfter(line.itemID) end
  GC.Buy.RefreshIfShown()
end

-- The one list this tab renders, top to bottom. Vendor lines are already last (Core/BuyRun.lua's
-- Refresh puts them there); this only decides what is a row at all.
local function buildEntries()
  local entries = {}
  -- No list on screen: the first-time state -- the item box that starts a quick list in the game.
  if not current then
    entries[#entries + 1] = { kind = "hint", text = GC.L["Make a list once, buy it here at or under your price."] }
    entries[#entries + 1] = { kind = "add" }
    entries[#entries + 1] = { kind = "hint", text = GC.L["or plan a whole profession on goldcap.gg"] }
    return entries
  end
  local filter, query = GC.Buy._filter or "all", GC.Buy._query or ""
  local lines = current:Lines()
  for _, line in ipairs(lines) do
    if GC.BuyView.Matches(lineStatus(line), lineName(line), filter, query) then
      entries[#entries + 1] = { kind = "line", line = line }
    end
  end
  if #entries == 0 and #lines > 0 then
    entries[1] = { kind = "hint", text = GC.L["Nothing on this list matches."] }
  end
  -- The quick list ends with its item box, so the next item goes on where the last one did; any
  -- other list shows it once the list menu's "Item to add" asked for it.
  if isQuickRun(current:Code()) or GC.Buy._adding then entries[#entries + 1] = { kind = "add" } end
  return entries
end

-- How tall a painted row is: its least, or what its wrapped text needs. A name too long for the
-- item column in the player's language takes a second line rather than losing its end.
local function heightFor(kind, row)
  if kind == "add" then
    local add = GC.Buy._view and GC.Buy._view.add
    return add and add.h or geometry.rowHeight * 3
  end
  if kind == "hint" then
    local h = geometry.rowHeight * 2
    if row and row.wide.GetStringHeight then h = math.max(h, math.ceil(row.wide:GetStringHeight() + 12)) end
    return h
  end
  local h = geometry.rowHeight
  if row and row.reagent.GetStringHeight then h = math.max(h, math.ceil(row.reagent:GetStringHeight() + 10)) end
  return h
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
  row:EnableMouse(true)
  row.reagent:SetText("")
  row.reagent:Show()
  row.wide:SetText("")
  row.wide:Hide()
  row.selected:Hide()
  row.status:SetText("")
  row.status:Hide()
  row:SetAlpha(1)
  row.reagentInset = 0
  row.icon:Hide()
  row.tooltipItemID = nil
  row.lineItemID = nil
  for _, col in ipairs(COLUMNS) do
    if not col.flex then
      row.cells[col.key]:SetText("")
      row.cells[col.key]:Show()
    end
  end
end

-- @localised-keys: literals in this table ARE GC.L keys, looked up in paintLine: the one word a
-- row says for a line that is not simply ready to buy. `over`, `vendor` and `craft` carry a price
-- and are formatted there. The table closes with a `}` on its own line.
local STATUS_WORD = {
  done = "bought",
  skipped = "skipped for now",
  stranded = "no answer — check your mail",
  vendor = "at a vendor",
  craft = "craft",
}

local function paintLine(row, line)
  row.tooltipItemID = line.itemID
  row.lineItemID = line.itemID
  local name = lineName(line)
  local named = (Theme.WithQuality and Theme.WithQuality(name, line.itemID, 11)) or name
  -- How many: what is left to buy, or -- once the line is done -- what it asked for.
  local decorated = ("%s ×%d"):format(named, line.buy > 0 and line.buy or line.need)
  -- A craft line names what it makes and how many batches of it; a reagent the split brought in
  -- is indented under the line it belongs to, so the block reads as one instruction.
  if line.kind == "craft" and line.crafts and line.craft then
    decorated = (GC.L["%s → craft %d× (%d per craft)"]):format(
      decorated, line.crafts, line.craft.craftedQty)
  elseif line.parent then
    decorated = (GC.L["↳ %s"]):format(decorated)
  end
  -- An alert group's gear member names the item level its price was set for (caps fixes 5h). The
  -- line is bought by hand on Blizzard's own page, and without this a cheaper copy below that
  -- level was the obvious one to take.
  if line.minIlvl then
    decorated = ("%s · %s"):format(decorated, (GC.L["item level %d+"]):format(line.minIlvl))
  end
  -- An alert hit can be bound to one realm; the auction house search finds nothing for it on
  -- any other, so the row says which rather than leaving the player to wonder why it is empty.
  if line.realmName then
    decorated = ("%s %s"):format(decorated, (GC.L["on %s"]):format(line.realmName))
  end
  row.reagent:SetText(decorated)
  -- Neither a vendor stop nor a craft line is something this tab can act on -- the whole row
  -- reads back, so it does not compete with the lines the player is actually here to buy.
  setColor(row.reagent, (line.vendor or line.kind == "craft") and Theme.color.fgDim or Theme.color.fg)
  -- The line the dock is on: a faint gold wash, drawn at render (it is state, not hover).
  if GC.Buy._focus == line.itemID then row.selected:Show() else row.selected:Hide() end

  local icon = nil
  if C_Item and C_Item.GetItemIconByID then
    local ok, texture = pcall(C_Item.GetItemIconByID, line.itemID)
    icon = ok and texture or nil
  end
  row.reagentInset = icon and 26 or 0
  if icon then row.icon:SetTexture(icon); row.icon:Show() else row.icon:Hide() end

  local status = lineStatus(line)
  if status == "ready" or status == "unpriced" or status == "lots" then
    -- PRICE EACH: the cheapest unit the last read of the book found, else the cheapest seen (NOW),
    -- else the market price -- dimmed, because nobody has looked at the book for it yet.
    local read = readOf(line)
    local seen = read and read.ladder and read.ladder[1] and read.ladder[1].unit or nil
    local each = seen or line.floor or line.usual
    row.cells.price:SetText(formatAmount(each))
    setColor(row.cells.price, (seen or line.floor) and Theme.color.fg or Theme.color.fgDim)
    -- COST: the quote on this line (what the next press spends, or at CONFIRM the server's own
    -- figure) or an estimate, marked as one.
    local attempt = GC.Buy._attempt
    -- A gear line's attempt is one lot; what the rest of it costs is its read's (noteLots).
    local quotedTotal = attempt and attempt.itemID == line.itemID and not attempt.lots
      and (attempt.stage == "quoted" or inFlight(attempt)) and (attempt.serverTotal or attempt.total) or nil
    local cost, estimated = GC.BuyView.CostOf(line,
      (quotedTotal and quotedTotal > 0) and { qty = line.buy, total = quotedTotal } or recentQuote(line))
    row.cells.cost:SetText(cost and ((estimated and "~" or "") .. formatAmount(cost)) or EM_DASH)
    setColor(row.cells.cost, (attempt and attempt.itemID == line.itemID and attempt.stage == "confirm")
      and Theme.color.goldHi or (estimated and Theme.color.fgDim or Theme.color.fg))
    return
  end
  row.cells.price:Hide()
  row.cells.cost:Hide()
  local text, color = GC.L[STATUS_WORD[status] or "craft"], Theme.color.fgDim
  if status == "over" then
    local read = readOf(line)
    local cheapest = (read and read.ladder and read.ladder[1] and read.ladder[1].unit) or line.floor
    text, color = (GC.L["over your cap · %s"]):format(formatAmount(cheapest)), Theme.tier.SUSPECT
  elseif status == "vendor" then
    if line.vendorUnit then text = (GC.L["at a vendor · %s each"]):format(formatAmount(line.vendorUnit)) end
    color = Theme.color.fgMuted
  elseif status == "craft" then
    local compare = GC.BuyRun.CraftText(line)
    if compare then text = (GC.L["craft it · %s each"]):format(formatAmount(compare.unit)) end
    color = (compare and compare.cheaper) and Theme.color.green or Theme.color.fgMuted
  elseif status == "done" then
    color = Theme.color.green
  elseif status == "stranded" then
    color = Theme.color.red
  elseif status == "skipped" then
    -- The ROW frame's alpha, never a texture's: on a texture SetAlpha is the same value
    -- SetVertexColor's fourth argument sets, and would repaint a wash.
    row:SetAlpha(0.5)
  end
  row.status:SetText(text)
  setColor(row.status, color)
  row.status:Show()
end

local function paintRow(row, entry, index)
  clearRow(row)

  local zc = Theme.color.zebra
  row.zebra:SetVertexColor(zc[1], zc[2], zc[3], (index % 2 == 1) and (zc[4] or 0) or 0)

  if entry.kind == "add" then
    -- The item box itself sits over this row (renderRows); the row only holds its place, and takes
    -- no clicks, so the box under the pointer gets them.
    row:EnableMouse(false)
    row.reagent:Hide()
    for _, col in ipairs(COLUMNS) do
      if not col.flex then row.cells[col.key]:Hide() end
    end
  elseif entry.kind == "hint" then
    row.reagent:Hide()
    row.wide:Show()
    row.wide:SetJustifyH("CENTER")
    row.wide:SetWordWrap(true)
    row.wide:SetText(entry.text)
    setColor(row.wide, Theme.color.fgDim)
    row.wide:SetSpacing(4)
    for _, col in ipairs(COLUMNS) do
      if not col.flex then row.cells[col.key]:Hide() end
    end
  elseif entry.kind == "line" then
    paintLine(row, entry.line)
  end
end

-- The width each fixed column needs for what this render shows: its heading and every cell in
-- it, as the client measures them in the player's language and at the current scale, never less
-- than the column's own least. The status word spans both price columns, so the widest one
-- widens COST when it has to. Unbounded widths: a cell pinned to its column would answer with the
-- width it had already been cut to. Re-lays the heading out when a width moved.
local function measured(fs)
  if not (fs and fs.GetUnboundedStringWidth) then return nil end
  local width = fs:GetUnboundedStringWidth()
  return type(width) == "number" and math.ceil(width) or nil
end

local function fitColumns(count)
  local want = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then
      want[col.key] = col.w
      local hit = band.header and band.header.cells[col.key]
      local w = hit and measured(hit.label)
      if w and w > want[col.key] then want[col.key] = w end
    end
  end
  local statusW = 0
  for i = 1, count do
    local row = rows[i]
    for key in pairs(want) do
      local cell = row.cells[key]
      local w = cell:IsShown() and measured(cell) or nil
      if w and w > want[key] then want[key] = w end
    end
    local w = row.status:IsShown() and measured(row.status) or nil
    if w and w > statusW then statusW = w end
  end
  local area = want.price + Theme.pad.s + want.cost
  if statusW > area then want.cost = want.cost + (statusW - area) end
  local old = band.colW
  band.colW = want
  if headerLayout and not (old and old.price == want.price and old.cost == want.cost) then headerLayout() end
end

-- A row's cells at their fitted widths, the status word across the two price columns, and the
-- item column in what is left -- as a width, so its text wraps there rather than running under
-- the prices, and heightFor can ask how tall it came out.
layoutRow = function(row)
  local flexAnchor = anchorColumns(row, function(col) return row.cells[col.key] end)
  local area = priceArea()
  row.status:ClearAllPoints()
  row.status:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.status:SetWidth(area)
  local inset = row.reagentInset or 0
  row.reagent:ClearAllPoints()
  row.reagent:SetPoint("LEFT", row, "LEFT", inset, 0)
  local width = geometry and geometry.rowWidth or 0
  if width > 0 then
    row.reagent:SetWidth(math.max(40, width - inset - area - Theme.pad.s))
  else
    row.reagent:SetPoint("RIGHT", flexAnchor.frame, flexAnchor.point, -Theme.pad.s, 0)
  end
end

-- The player's own cap for a line, typed into UI/BuyCapEditor.lua's price box. Refused while a
-- purchase is in flight -- asked again at commit, because the box can stay open across one
-- starting: the attempt has committed to `current`'s lines and their caps.
local function openCapEditor(anchor, line)
  if not (GC.BuyCapEditor and current and line) or inFlight(GC.Buy._attempt) then return end
  local code, itemID = current:Code(), line.itemID
  GC.BuyCapEditor.Open(anchor, {
    title = (GC.L["Cap for %s"]):format(lineName(line)),
    current = line.cap,
    onCommit = function(copper)
      if inFlight(GC.Buy._attempt) then return end
      setLineCap(code, itemID, copper)
      -- A read judged against the old cap (a gear line's "set a cap first" included) is asked
      -- again on the next tick; a fresh one is judged again on this repaint (rejudgeQuote). At a
      -- merchant, the vendor panel holds the line to the new cap too.
      GC.Buy._quotedFocus = nil
      GC.Buy.RefreshIfShown()
      if GC.BuyVendorPanel and GC.BuyVendorPanel.OnListChanged then GC.BuyVendorPanel.OnListChanged() end
    end,
  })
end

-- Right-click on a row: every decision a line carries that is not a purchase -- skip it for this
-- session, raise its cap to what the dock would offer, type a cap of its own or go back to the
-- default, and for a line the site sent a recipe for, buy it or craft it. Nothing here spends
-- gold: it writes a flag or a price and re-renders (spec/buy_purchase_wiring_spec.lua proves no
-- protected call can be reached from a context menu at all).
--
-- Refused while a purchase is in flight, for the reason the run menu refuses a re-cap there:
-- the attempt has already committed to `current`'s lines, and a split or a cap rewrites them, so
-- settlePurchase would book the gold against a line that no longer exists. And on a line already
-- bought, which has nothing left to decide.
local function openRowMenu(owner, line)
  if not (current and line) or line.done or inFlight(GC.Buy._attempt) then return false end
  local menu = _G.MenuUtil
  if not (menu and menu.CreateContextMenu) then return false end
  local code, itemID = current:Code(), line.itemID
  local skipped, alert = isSkipped(line), alertRun()
  -- An alert group's cap is its target, set on goldcap.gg; a vendor or craft line has none here.
  local canCap = not alert and not line.vendor and line.kind ~= "craft"
  local raiseTo = canCap and raiseOffered(line) or nil
  local split = line.kind == "craft"
  -- A line the list's route crafts itself (`make`) has no split: its reagents are lines already.
  local canSplit = line.craft and not line.parent and not line.make
  -- How many batches an unsplit line would need is the same arithmetic Core/BuyRun.lua does once
  -- it IS split: what is left to get, rounded up to a whole craft.
  local crafts = canSplit and (split and (line.crafts or 0)
    or math.ceil(line.buy / math.max(1, line.craft.craftedQty))) or 0
  local quick = isQuickRun(code)
  menu.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(lineName(line))
    -- The quick list is the player's own, line by line.
    if quick then
      root:CreateButton(GC.L["Remove from the list"], function()
        if inFlight(GC.Buy._attempt) then return end
        GC.AppRuns.RemoveQuickLine(itemID)
        GC.Buy.SelectRun(isQuickRun(GC.AppRuns.QUICK) and GC.AppRuns.QUICK or nil)
        GC.Buy.RefreshIfShown()
      end)
    end
    root:CreateButton(skipped and GC.L["Don't skip"] or GC.L["Skip for now"], function()
      setSkipped(itemID, not skipped)
      if not skipped and GC.Buy._focus == itemID then GC.Buy._focus = nextOpenAfter(itemID) end
      GC.Buy.RefreshIfShown()
    end)
    if raiseTo then
      root:CreateButton((GC.L["Raise cap to %s"]):format(formatAmount(raiseTo)), function()
        if inFlight(GC.Buy._attempt) then return end
        local now = lineFor(itemID)
        if now then raiseCap(now) end
        GC.Buy.RefreshIfShown()
      end)
    end
    if canCap then
      root:CreateButton(GC.L["Change the cap…"], function() openCapEditor(owner, lineFor(itemID)) end)
      if line.capFrom == "yours" then
        root:CreateButton(GC.L["Use the default cap"], function()
          if inFlight(GC.Buy._attempt) then return end
          setLineCap(code, itemID, nil)
          GC.Buy.RefreshIfShown()
        end)
      end
    end
    if canSplit then
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
    end
  end)
  return true
end

-- A line explained: what is left to buy and what the player has, the ladder of prices the
-- purchase would walk (what it takes at each, and the first level it does not), the market price
-- and -- on WoW: Forever -- whose it is and how old, the cap, and the line's other footnotes.
-- GameTooltip draws with the client's own font, which has no "·" in every language (the Russian
-- client drew an empty box): every line that can carry one goes through GC.Util.TooltipText.
local function showLineTooltip(row)
  if not GameTooltip then return end
  local line = row.lineItemID and lineFor(row.lineItemID) or nil
  if not line then return end
  local dim, fg, gold = Theme.color.fgDim, Theme.color.fg, Theme.color.gold
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(lineName(line), 1, 1, 1)
  local bags, bank = haveSplit(line.itemID)
  if line.buy > 0 then
    local have = bags + bank
    GameTooltip:AddLine(have > 0
      and (GC.L["buy %d of %d, have %d in bags and bank"]):format(line.buy, line.need, have)
      or (GC.L["buy %d of %d"]):format(line.buy, line.need), dim[1], dim[2], dim[3], true)
  end
  -- HAVE counts the banks as well as the bags, so a line covered by three hundred of them owes the
  -- player where they are. Only when the bank actually holds some.
  if bank > 0 then
    GameTooltip:AddLine(GC.Util.TooltipText((GC.L["in bags %d · in bank %d"]):format(bags, bank)), dim[1], dim[2], dim[3], true)
  end
  if not line.vendor and line.kind ~= "craft" and not line.done then
    local read = readOf(line)
    if read and read.ladder then
      for _, r in ipairs(GC.BuyView.Ladder(read.ladder, line.buy, line.cap)) do
        local right = (r.take > 0 and (GC.L["you take %d"]):format(r.take)) or (r.over and GC.L["over your cap"]) or ""
        local rc = r.take > 0 and gold or (r.over and Theme.tier.SUSPECT or dim)
        GameTooltip:AddDoubleLine((GC.L["%d at %s"]):format(r.qty, formatAmount(r.unit)), right,
          fg[1], fg[2], fg[3], rc[1], rc[2], rc[3])
      end
      local age = time() - (read.at or time())
      if age > BD.QUOTE_SECONDS then
        GameTooltip:AddLine((GC.L["seen %s ago"]):format(GC.Util.FormatElapsedWords(age) or ""), dim[1], dim[2], dim[3])
      end
    elseif read and read.ladder == false then
      GameTooltip:AddLine(GC.L["nothing on offer"], dim[1], dim[2], dim[3])
    elseif line.floor then
      GameTooltip:AddLine((GC.L["cheapest seen %s"]):format(formatAmount(line.floor)), dim[1], dim[2], dim[3])
    end
  end
  GameTooltip:AddLine(" ")
  if line.usual then
    GameTooltip:AddDoubleLine(GC.L["Market"], (GC.L["%s each"]):format(formatAmount(line.usual)),
      dim[1], dim[2], dim[3], fg[1], fg[2], fg[3])
    -- WoW: Forever: a price other players' scans agreed on says how many and how long ago.
    local note = GC.BuyView.MarketNote(line.usualRef, time())
    if note then
      local ago = GC.Util.FormatElapsedWords(note.age) or GC.Util.FormatElapsedWords(0)
      GameTooltip:AddDoubleLine(GC.L["Source"], note.scanners == 1 and (GC.L["1 scanner, %s ago"]):format(ago)
        or (GC.L["%d scanners, %s ago"]):format(note.scanners, ago), dim[1], dim[2], dim[3], dim[1], dim[2], dim[3])
    end
  end
  local alert = alertRun()
  if line.cap and not line.vendor and line.kind ~= "craft" then
    GameTooltip:AddDoubleLine((line.capFrom == "target" and alert) and GC.L["Alert target"] or GC.L["Your cap"],
      (GC.L["%s each"]):format(formatAmount(line.cap)), dim[1], dim[2], dim[3], fg[1], fg[2], fg[3])
  end
  -- The one thing the item's own data cannot know: when this realm usually sells it cheapest.
  -- Not on a vendor line -- the auction house's cheap hour is noise next to a fixed price -- and
  -- not on a done line, which nobody is about to act on.
  local cheap = not line.vendor and not line.done and cheapHourText(line)
  if cheap then GameTooltip:AddLine(GC.Util.TooltipText(cheap), dim[1], dim[2], dim[3], true) end
  -- Where a merged line's NEED came from: a reagent the run already asked for grows the row it has
  -- rather than getting a second one, and a NEED that grew with no explanation cannot be checked.
  if line.forCraft then
    for parentID, qty in pairs(line.forCraft) do
      local parentLine = lineFor(parentID)
      GameTooltip:AddLine((GC.L["includes %d for crafting %s"]):format(
        qty, parentLine and lineName(parentLine) or ("#" .. tostring(parentID))), dim[1], dim[2], dim[3], true)
    end
  end
  -- Craft it or buy it: two numbers about this region's prices now, and never a promise about
  -- what the player will save. Green when crafting is the cheaper of the two, grey otherwise --
  -- including when the auction house has no price to compare against at all.
  local compare = not line.done and GC.BuyRun.CraftText(line) or nil
  if compare then
    local cc = compare.cheaper and Theme.color.green or dim
    local parts = {}
    for _, reagent in ipairs(compare.reagents) do
      parts[#parts + 1] = (GC.L["%d× %s"]):format(
        reagent.qty, lineName({ itemID = reagent.itemID, name = reagent.name }))
    end
    GameTooltip:AddLine((GC.L["craft it: %s = %s each"]):format(
      table.concat(parts, " + "), formatAmount(compare.unit)), cc[1], cc[2], cc[3], true)
    -- The hint names what the right-click would DO, which is the opposite thing on a line that is
    -- already split -- and nothing on a line the list's route crafts itself, which has no split.
    if line.kind == "craft" and not line.make then
      GameTooltip:AddLine(GC.Util.TooltipText((GC.L["vs %s at the auction house · right-click to buy it whole"])
        :format(formatAmount(compare.ahUnit))), cc[1], cc[2], cc[3], true)
    elseif not line.make then
      GameTooltip:AddLine(GC.Util.TooltipText((GC.L["vs %s at the auction house · right-click to split"])
        :format(formatAmount(compare.ahUnit))), cc[1], cc[2], cc[3], true)
    end
  end
  -- What the row's right-click offers, on a line whose cap it can change (Task 11's menu).
  if not line.done and not line.vendor and line.kind ~= "craft" and not alert then
    GameTooltip:AddLine(GC.L["right-click to skip or change the cap"], dim[1], dim[2], dim[3], true)
  end
  GameTooltip:Show()
end

-- A look that answered while its row's tooltip is still up redraws it with the ladder.
function GC.Buy._refreshTooltip(itemID)
  local row = GC.Buy._tooltipRow
  if row and row.lineItemID == itemID and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(row) then
    showLineTooltip(row)
  end
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
  -- OnEnter/OnLeave repaint (the addon's engineering notes' "Buttons and hover").
  local hc = Theme.color.hover
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture(Theme.MEDIA .. "plaque.png")
  highlight:SetTextureSliceMargins(12, 12, 12, 12)
  highlight:SetPoint("TOPLEFT", 2, -1)
  highlight:SetPoint("BOTTOMRIGHT", -2, 1)
  highlight:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 0.08)
  row.highlight = highlight
  row:EnableMouse(true)

  -- The line the dock is on: a faint gold wash, shown by paintLine (state, not hover).
  local sel = row:CreateTexture(nil, "BORDER")
  sel:SetTexture(Theme.MEDIA .. "plaque.png")
  sel:SetTextureSliceMargins(12, 12, 12, 12)
  sel:SetPoint("TOPLEFT", 2, -1)
  sel:SetPoint("BOTTOMRIGHT", -2, 1)
  local gc = Theme.color.gold
  sel:SetVertexColor(gc[1], gc[2], gc[3], 0.08)
  sel:Hide()
  row.selected = sel

  -- A Frame with the mouse enabled gets OnMouseUp for every button, which is how a row that is
  -- not a Button carries a context menu -- and, in BUY 2.0, how a left click picks the line the
  -- dock buys. Neither is a purchase: the dock's own button is.
  row:SetScript("OnMouseUp", function(self, button)
    local line = self.lineItemID and lineFor(self.lineItemID) or nil
    if button == "RightButton" then openRowMenu(self, line) return end
    if button == "LeftButton" then selectLine(line) end
  end)

  -- The line explained on hover (showLineTooltip), and -- after a short dwell -- another line's
  -- book read for it (lookLine). Wired ONCE on the pooled row, reading whatever paintRow last
  -- stamped. A hover no longer picks the line: a left click does (selectLine).
  row:SetScript("OnEnter", function(self)
    GC.Buy._tooltipRow = self
    showLineTooltip(self)
    local line = self.lineItemID and lineFor(self.lineItemID) or nil
    if not line then return end
    if line.itemID == GC.Buy._focus then
      -- The dock's own line: keep its quote fresh, as the hover always did.
      if buyable(line) and not inFlight(GC.Buy._attempt) then quote(line) end
    elseif C_Timer and C_Timer.After then
      local itemID = line.itemID
      C_Timer.After(BD.LOOK_DWELL_SECONDS, function()
        if GC.Buy._tooltipRow == self and self.lineItemID == itemID then lookLine(lineFor(itemID)) end
      end)
    end
  end)
  row:SetScript("OnLeave", function()
    GC.Buy._tooltipRow = nil
    if GameTooltip then GameTooltip:Hide() end
  end)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.icon:Hide()

  -- The full-row text used by the "hint" kind -- the empty state.
  row.wide = Theme.Label(row, 11)
  row.wide:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  row.wide:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  row.wide:Hide()

  -- The item and how many: wraps to a second line rather than losing its end (layoutRow gives it
  -- a width, heightFor a height).
  row.reagent = Theme.Label(row, 11)
  row.reagent:SetJustifyH("LEFT")
  row.reagent:SetWordWrap(true)

  row.cells = {}
  for _, col in ipairs(COLUMNS) do
    if not col.flex then row.cells[col.key] = buildRowCell(row, col) end
  end

  -- One word in place of PRICE EACH and COST for a line that is not simply ready to buy, as wide
  -- as the two columns -- which fitColumns widens until the longest such word fits.
  row.status = Theme.Num(row, 11)
  row.status:SetJustifyH("RIGHT")
  row.status:SetWordWrap(false)
  row.status:Hide()

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
  reagentLabel:SetText(headerText("item"))
  reagentHit.label = reagentLabel
  -- Not read by any production code; exposed so the behavior spec can reach the ITEM cell.
  header.reagentCell = reagentHit

  headerLayout = function()
    local flexAnchor = anchorColumns(header, function(col) return header.cells[col.key] end)
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
  if header.reagentCell then stamp(header.reagentCell.label, headerText("item")) end
end

-- The run's vendor stops as one block of text: what to buy, what each costs and what the trip
-- comes to. Only lines with something still to buy -- this is a shopping list, not an inventory
-- -- and a line the site could not price is named without a price rather than with a blank one.
-- nil when there is nothing to copy, which is also when the run menu offers no copy.
vendorListText = function()
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

-- The band above the table (BUY 2.0): the list picker, under it how much of the list is done
-- (and whose it is, and what the site last changed), on the right TO BUY HERE and the total of every
-- line ready to buy, and a thin progress bar along the bottom. SellFrame/SoldFrame's header-band
-- convention.
local function createBand(parent)
  local picker = Theme.Button(parent, "ghost", "plaque")
  picker:SetSize(150, 24)
  picker:SetPoint("TOPLEFT", 0, -2)
  -- A list's name is the player's own words, of any length: the picker's label wraps rather than
  -- being cut (layoutBand grows the button to it).
  if picker.text then
    picker.text:SetWordWrap(true)
    picker.text:SetMaxLines(3)
  end
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

  local totalCaption = Theme.Num(parent, 9)
  totalCaption:SetJustifyH("RIGHT")
  totalCaption:SetWordWrap(false)
  totalCaption:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -4)
  totalCaption:SetText(GC.L["TO BUY HERE"])
  setColor(totalCaption, Theme.color.fgDim)
  local total = Theme.Num(parent, 14, true)
  total:SetJustifyH("RIGHT")
  total:SetWordWrap(false)
  total:SetPoint("TOPRIGHT", totalCaption, "BOTTOMRIGHT", 0, -3)

  -- How much of the list is done, whose it is and what the site last changed: wraps rather than
  -- running under the total.
  local done = Theme.Num(parent, 9)
  done:SetJustifyH("LEFT")
  done:SetWordWrap(true)
  setColor(done, Theme.color.fgDim)

  -- The search box and the filter (BD.TOOLS_MIN_LINES), in a row of their own under the band. The
  -- well and the box are UI/SellFrame.lua's search, the filter a menu of GC.BuyView.FILTERS.
  local tools = CreateFrame("Frame", nil, parent)
  tools:SetHeight(BD.TOOLS_H)
  tools:Hide()
  local well = CreateFrame("Frame", nil, tools)
  well:SetSize(200, 22)
  well:SetPoint("LEFT", tools, "LEFT", 0, 0)
  local wc = Theme.color.bg or Theme.color.panel
  Theme.SlicedTexture(well, "BACKGROUND", Theme.MEDIA .. "plaque.png", { wc[1], wc[2], wc[3], 1 }, 12):SetAllPoints(well)
  Theme.SlicedTexture(well, "BORDER", Theme.MEDIA .. "plaque_ring.png", { 1, 1, 1, 0.12 }, 12):SetAllPoints(well)
  local search = CreateFrame("EditBox", nil, well)
  search:SetAutoFocus(false)
  search:SetPoint("TOPLEFT", 10, -2)
  search:SetPoint("BOTTOMRIGHT", -8, 2)
  -- Guarded for busted; in the client a bare EditBox with no font draws no text at all.
  if search.SetFont then
    search:SetFont(Theme.FONT_UI, 11 * Theme.Scale(), "")
    search:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
  end
  local hint = Theme.Num(well, 10)
  hint:SetJustifyH("LEFT")
  hint:SetPoint("LEFT", well, "LEFT", 10, 0)
  hint:SetText(GC.L["Search"])
  setColor(hint, Theme.color.fgDim)
  local function applyHint()
    if (search:GetText() or "") ~= "" or (search.HasFocus and search:HasFocus()) then hint:Hide() else hint:Show() end
  end
  search:SetScript("OnTextChanged", function(box, byUser)
    GC.Buy._query = (box:GetText() or ""):match("^%s*(.-)%s*$")
    applyHint()
    if byUser then GC.Buy.RefreshIfShown() end
  end)
  search:SetScript("OnEditFocusGained", applyHint)
  search:SetScript("OnEditFocusLost", applyHint)
  search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
  search:SetScript("OnEscapePressed", function(box)
    box:SetText("")
    box:ClearFocus()
    GC.Buy._query = ""
    applyHint()
    GC.Buy.RefreshIfShown()
  end)
  local filter = Theme.Button(tools, "ghost", "badge")
  filter:SetSize(96, 20)
  filter:SetPoint("LEFT", well, "RIGHT", Theme.pad.s, 0)
  filter:SetScript("OnClick", function(self)
    local menu = _G.MenuUtil
    if not (menu and menu.CreateContextMenu) then return end
    menu.CreateContextMenu(self, function(_, root)
      for _, key in ipairs(GC.BuyView.FILTERS) do
        root:CreateRadio(GC.L[FILTER_LABEL[key]], function(v) return GC.Buy._filter == v end,
          function(v) GC.Buy._SetFilter(v) end, key)
      end
    end)
  end)

  -- A frame pinned to the band's own height, so the progress bar sits at the band's bottom edge
  -- regardless of where the text above it ends.
  local bandFrame = CreateFrame("Frame", nil, parent)
  bandFrame:SetPoint("TOPLEFT", 0, 0)
  bandFrame:SetPoint("TOPRIGHT", 0, 0)
  bandFrame:SetHeight(BD.BAND_HEIGHT)
  local bc, gc = Theme.color.border, Theme.color.gold
  local track = bandFrame:CreateTexture(nil, "ARTWORK")
  track:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  track:SetPoint("BOTTOMLEFT")
  track:SetPoint("BOTTOMRIGHT")
  track:SetHeight(2)
  local fill = bandFrame:CreateTexture(nil, "OVERLAY")
  fill:SetColorTexture(gc[1], gc[2], gc[3], 0.9)
  fill:SetPoint("BOTTOMLEFT")
  fill:SetHeight(2)
  fill:Hide()

  return { picker = picker, done = done, totalCaption = totalCaption, total = total,
           track = track, fill = fill, frame = bandFrame, h = BD.BAND_HEIGHT,
           tools = { frame = tools, search = search, hint = hint, filter = filter } }
end

-- A button exactly as wide as its label in the player's language, and never under `minW`: the
-- dock's labels change with the purchase's stage (BUY 120, CONFIRM, RAISE CAP TO 1s 87c) and run
-- long in some languages, and a label cut short is a button nobody can read. Unbounded: the
-- button pins its label to its own edges, so GetStringWidth would answer with the cut width.
local function fitButton(btn, minW)
  local fs = btn.text
  local width = fs and fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
  if type(width) ~= "number" then return end
  btn:SetWidth(math.max(minW, math.ceil(width) + 2 * Theme.pad.m))
end

-- The next-purchase dock at the foot of the tab: the item and how many on one line, what it costs
-- (or why it cannot be bought) on the next, and the one button that buys -- the only hardware
-- entry to a purchase besides Enter. A second button beside it cancels a quote or skips a line.
local function createDock(parent)
  local dock = CreateFrame("Frame", nil, parent)
  dock:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  dock:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  dock:SetHeight(BD.DOCK_H)
  dock.h = BD.DOCK_H
  dock:EnableMouse(true)
  local bc = Theme.color.border
  local rule = dock:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
  rule:SetPoint("TOPLEFT")
  rule:SetPoint("TOPRIGHT")
  rule:SetHeight(1)
  dock.icon = dock:CreateTexture(nil, "ARTWORK")
  dock.icon:SetSize(28, 28)
  dock.icon:SetPoint("TOPLEFT", dock, "TOPLEFT", 4, -10)
  dock.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  dock.icon:Hide()
  dock.buy = Theme.Button(dock, "primary", "plaque")
  dock.buy:SetSize(BD.DOCK_BUY_MIN_W, 28)
  dock.buy:SetScript("OnClick", onBuyButtonClick)
  -- The hover keeps the dock line's quote fresh, as a row's hover always did: the press then buys
  -- on its first try. HookScript, so the button's own scripts stay.
  dock.buy:HookScript("OnEnter", function(self)
    local line = lineFor(self:GetParent().lineItemID)
    if line and buyable(line) and not inFlight(GC.Buy._attempt) then quote(line) end
  end)
  dock.second = Theme.Button(dock, "ghost", "plaque")
  dock.second:SetSize(BD.DOCK_SECOND_MIN_W, 28)
  dock.second:SetScript("OnClick", onDockSecondaryClick)
  -- Both lines wrap rather than cut: a long item name, or a sentence that runs long in the
  -- player's language, takes a second line and the dock grows to hold it (layoutDock).
  dock.title = Theme.Label(dock, 12)
  dock.title:SetJustifyH("LEFT")
  dock.title:SetWordWrap(true)
  dock.sub = Theme.Num(dock, 10)
  dock.sub:SetJustifyH("LEFT")
  dock.sub:SetWordWrap(true)
  return dock
end

-- The dock's geometry for what it now says: each shown button as wide as its label, the text
-- between the icon and the leftmost button, and the dock as tall as its wrapped text needs.
-- Returns the dock's height.
local function layoutDock(dock)
  local right = nil
  for _, entry in ipairs({ { dock.buy, BD.DOCK_BUY_MIN_W }, { dock.second, BD.DOCK_SECOND_MIN_W } }) do
    local btn = entry[1]
    if btn:IsShown() then
      fitButton(btn, entry[2])
      btn:ClearAllPoints()
      if right then
        btn:SetPoint("RIGHT", right, "LEFT", -Theme.pad.s, 0)
      else
        btn:SetPoint("RIGHT", dock, "RIGHT", -4, 0)
      end
      right = btn
    end
  end
  local left = dock.icon:IsShown() and 40 or 4
  dock.title:ClearAllPoints()
  dock.title:SetPoint("TOPLEFT", dock, "TOPLEFT", left, -10)
  dock.sub:ClearAllPoints()
  dock.sub:SetPoint("TOPLEFT", dock.title, "BOTTOMLEFT", 0, -4)
  if right then
    dock.title:SetPoint("RIGHT", right, "LEFT", -Theme.pad.s, 0)
    dock.sub:SetPoint("RIGHT", right, "LEFT", -Theme.pad.s, 0)
  else
    dock.title:SetPoint("RIGHT", dock, "RIGHT", -4, 0)
    dock.sub:SetPoint("RIGHT", dock, "RIGHT", -4, 0)
  end
  local h = BD.DOCK_H
  if dock.title.GetStringHeight then
    local th = dock.title:GetStringHeight() or 0
    local sh = ((dock.sub:GetText() or "") ~= "" and dock.sub:GetStringHeight()) or 0
    h = math.max(BD.DOCK_H, math.ceil(10 + th + 4 + sh + 10))
  end
  if h ~= dock.h then
    dock.h = h
    dock:SetHeight(h)
  end
  return h
end

-- A list's progress for the column: `done` of `total` of its own lines, or an alert group's hits.
local function listMeta(run)
  local meta = GC.Buy._listMeta[run.code]
  if meta then return meta end
  local obj = (current and current:Code() == run.code) and current or GC.BuyRun.New(run, LIST_DRIVER)
  if obj ~= current then obj:Refresh() end
  local done, total = GC.BuyView.Progress(obj:Lines())
  meta = { done = done, total = total, hits = run.k == "alert" and obj:Totals().topLines or nil }
  GC.Buy._listMeta[run.code] = meta
  return meta
end

-- The wide window's column: YOUR LISTS, one entry per list (its name, wrapping; N of M or N hits;
-- a thin progress bar), and where the lists come from under them.
local function createLists(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  frame:SetWidth(BD.LISTS_W)
  frame:Hide()
  local caption = Theme.Num(frame, 9)
  caption:SetJustifyH("LEFT")
  caption:SetWordWrap(true)
  caption:SetWidth(BD.LISTS_W)
  caption:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -6)
  caption:SetText(GC.L["YOUR LISTS"])
  setColor(caption, Theme.color.fgDim)
  local footer = Theme.Num(frame, 9)
  footer:SetJustifyH("LEFT")
  footer:SetWordWrap(true)
  footer:SetWidth(BD.LISTS_W)
  footer:SetText(GC.L["Lists come from goldcap.gg through the companion."])
  setColor(footer, Theme.color.fgDim)
  return { frame = frame, caption = caption, footer = footer, entries = {} }
end

-- One pooled entry of the column: a button carrying the list's name -- its label re-anchored to
-- wrap beside the count rather than run under it -- the count on the right, a bar along the foot.
local function listEntry(lists, i)
  local entry = lists.entries[i]
  if entry then return entry end
  local button = Theme.Button(lists.frame, "ghost", "plaque")
  button:SetSize(BD.LISTS_W, 34)
  button:SetScript("OnClick", function(self)
    if not self.code then return end
    GC.Buy.SelectRun(self.code)
    GC.Buy.RefreshIfShown()
  end)
  local meta = Theme.Num(button, 9)
  meta:SetJustifyH("RIGHT")
  meta:SetWordWrap(false)
  meta:SetPoint("TOPRIGHT", button, "TOPRIGHT", -8, -8)
  button.text:ClearAllPoints()
  button.text:SetPoint("TOPLEFT", button, "TOPLEFT", 8, -7)
  button.text:SetPoint("RIGHT", meta, "LEFT", -6, 0)
  button.text:SetJustifyH("LEFT")
  button.text:SetWordWrap(true)
  button.text:SetMaxLines(3)
  local fill = button:CreateTexture(nil, "OVERLAY")
  fill:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 6, 3)
  fill:SetHeight(1)
  fill:Hide()
  entry = { button = button, meta = meta, fill = fill }
  lists.entries[i] = entry
  return entry
end

local function paintLists()
  local lists = band.lists
  if not (lists and lists.frame:IsShown()) then return end
  local y = -6
  if lists.caption.GetStringHeight then y = y - math.ceil(lists.caption:GetStringHeight()) end
  y = y - 8
  local list = runList()
  for i, run in ipairs(list) do
    local entry = listEntry(lists, i)
    local meta = listMeta(run)
    local button = entry.button
    button.code = run.code
    button:SetVariant((current and current:Code() == run.code) and "active" or "ghost")
    button:SetLabel(run.name or run.code or "?")
    entry.meta:SetText(meta.hits and (GC.L["%d hits"]):format(meta.hits)
      or (GC.L["%d of %d"]):format(meta.done, meta.total))
    local share = meta.hits and 1 or (meta.total > 0 and meta.done / meta.total or 0)
    if share > 0 then
      local c = meta.hits and Theme.color.green or Theme.color.gold
      entry.fill:SetColorTexture(c[1], c[2], c[3], 0.9)
      entry.fill:SetWidth(math.max(1, (BD.LISTS_W - 12) * share))
      entry.fill:Show()
    else
      entry.fill:Hide()
    end
    local h = 34
    if button.text.GetStringHeight then h = math.max(34, math.ceil(button.text:GetStringHeight() + 16)) end
    button:SetHeight(h)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", lists.frame, "TOPLEFT", 0, y)
    button:Show()
    y = y - h - 4
  end
  for i = #list + 1, #lists.entries do lists.entries[i].button:Hide() end
  lists.footer:ClearAllPoints()
  lists.footer:SetPoint("TOPLEFT", lists.frame, "TOPLEFT", 0, y - 6)
end

-- The window's width decides the column: shown at BD.WIDE_MIN and wider, and the rest of the tab
-- -- band, tools, headings, rows, dock -- starts after it. Rows are as wide as what is left.
local function applyWidth(width)
  if not (width and width > 0) then return end
  local wide = width >= BD.WIDE_MIN
  GC.Buy._leftInset = wide and (BD.LISTS_W + Theme.pad.m) or 0
  geometry.rowWidth = width - GC.Buy._leftInset
  content:SetWidth(geometry.rowWidth)
  if band and band.lists then
    if wide then band.lists.frame:Show() else band.lists.frame:Hide() end
    band.bodyTop = nil -- the body re-anchors after the column on the next layoutBody
  end
end

-- The band's geometry for what it now says: the picker as wide as the list's name -- wrapping
-- when the name is longer than the room beside the total -- the done line under it wrapping
-- before the total, and the band as tall as all of that.
local function layoutBand()
  local picker = band.picker
  local inset = GC.Buy._leftInset or 0
  local width = math.max(0, (container and container:GetWidth() or 0) - inset)
  picker:ClearAllPoints()
  picker:SetPoint("TOPLEFT", container, "TOPLEFT", inset, -2)
  band.frame:ClearAllPoints()
  band.frame:SetPoint("TOPLEFT", container, "TOPLEFT", inset, 0)
  band.frame:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
  local rightW = math.max(measured(band.totalCaption) or 0, measured(band.total) or 0, 60)
  local labelW = picker.text and measured(picker.text)
  local pickerH = 24
  if labelW then
    local want = math.max(120, labelW + 2 * Theme.pad.m)
    if width > 0 then want = math.min(want, width - rightW - Theme.pad.m) end
    picker:SetWidth(want)
    if picker.text.GetStringHeight then
      pickerH = math.max(24, math.ceil(picker.text:GetStringHeight() + 8))
    end
    picker:SetHeight(pickerH)
  end
  band.done:ClearAllPoints()
  band.done:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 4, -4)
  band.done:SetPoint("RIGHT", band.total, "LEFT", -Theme.pad.m, 0)
  local doneH = band.done.GetStringHeight and band.done:GetStringHeight() or 0
  local h = math.max(BD.BAND_HEIGHT, math.ceil(2 + pickerH + 4 + doneH + 8))
  if h ~= band.h then
    band.h = h
    band.frame:SetHeight(h)
  end
end

-- The band for the run on screen: its name on the picker, how much of it is done, TO BUY HERE
-- and the total of every line ready to buy (an estimate, marked, while any part is one), the
-- progress bar, and the BUY rail badge's count.
local function paintBand()
  local ready = 0
  if current then
    local shown = shownRunData()
    local sharedBy = (shown and type(shown.by) == "string" and shown.by ~= "") and shown.by or nil
    band.picker:SetLabel(runLabel(current) .. " ▼")
    band.picker:Show()
    local lines = current:Lines()
    local doneCount, totalCount = GC.BuyView.Progress(lines)
    -- An alert run is not a shopping list somebody wrote: it is what the group found, and every
    -- line of it is one hit -- the run's own lines, that is: a reagent the player split a hit
    -- into is part of that hit, not another one the group found.
    local doneText = (shown and shown.k == "alert")
      and (GC.L["alert group · %d hits"]):format(current:Totals().topLines)
      or (GC.L["%d of %d done"]):format(doneCount, totalCount)
    if sharedBy then doneText = ("%s · %s"):format(doneText, (GC.L["from %s"]):format(sharedBy)) end
    -- What the site last changed about the plan, for the day it is news.
    local notice = noticeText(current:Code())
    if notice then doneText = ("%s · %s"):format(doneText, notice) end
    band.done:SetText(doneText)
    local sum, estimated = 0, false
    for _, line in ipairs(lines) do
      if lineStatus(line) == "ready" then
        ready = ready + 1
        local cost, est = GC.BuyView.CostOf(line, recentQuote(line))
        if cost then sum, estimated = sum + cost, estimated or est end
      end
    end
    band.totalCaption:Show()
    band.total:SetText(ready > 0 and ((estimated and "~" or "") .. formatAmount(sum)) or EM_DASH)
    local width = ((container and container:GetWidth()) or 0) - (GC.Buy._leftInset or 0)
    if totalCount > 0 and doneCount > 0 and width > 0 then
      band.fill:SetWidth(math.max(1, width * doneCount / totalCount))
      band.fill:Show()
    else
      band.fill:Hide()
    end
  else
    -- Nothing to name and nothing to count: a picker offering a run that does not exist is worse
    -- than no picker at all.
    band.picker:Hide()
    band.done:SetText("")
    band.totalCaption:Hide()
    band.total:SetText("")
    band.fill:Hide()
  end
  GC.Buy._readyCount = ready
  if GC.Sniper and GC.Sniper.UpdateBuyTabLabel then GC.Sniper.UpdateBuyTabLabel() end
  -- The search and the filter, for a long list or while either is in use.
  local tools = band.tools
  local filter, query = GC.Buy._filter or "all", GC.Buy._query or ""
  local long = current ~= nil and #current:Lines() > BD.TOOLS_MIN_LINES
  if long or filter ~= "all" or query ~= "" then
    tools.filter:SetLabel(GC.L[FILTER_LABEL[filter] or "All"] .. " ▾")
    fitButton(tools.filter, 96)
    tools.frame:Show()
  else
    tools.frame:Hide()
  end
  layoutBand()
end

-- How many lines of the run on screen are ready to buy at or under their cap: the BUY rail
-- button's badge (UI/SniperFrame.lua's GC.Sniper.UpdateBuyTabLabel).
function GC.Buy.ReadyCount() return GC.Buy._readyCount or 0 end

-- Where the column headings and the list sit: under the band, above the dock. Re-anchored only
-- when that changes -- this runs on every render.
local function layoutBody()
  local header, scroll = band.header, band.scroll
  local dock = band.dock
  local bottom = (dock and dock:IsShown()) and (dock.h or BD.DOCK_H) or 0
  local top = band.h or BD.BAND_HEIGHT
  local tools = band.tools and band.tools.frame
  if tools and tools:IsShown() then top = top + BD.TOOLS_H end
  if band.bodyBottom == bottom and band.bodyTop == top then return end
  band.bodyBottom, band.bodyTop = bottom, top
  local inset = GC.Buy._leftInset or 0
  if tools then
    tools:ClearAllPoints()
    tools:SetPoint("TOPLEFT", container, "TOPLEFT", inset, -(band.h or BD.BAND_HEIGHT))
    tools:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -(band.h or BD.BAND_HEIGHT))
  end
  header:ClearAllPoints()
  header:SetPoint("TOPLEFT", container, "TOPLEFT", inset, -top)
  header:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -top)
  scroll:ClearAllPoints()
  scroll:SetPoint("TOPLEFT", container, "TOPLEFT", inset, -(top + BD.HEADER_H + Theme.pad.xs))
  scroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, bottom)
  if dock then
    dock:ClearAllPoints()
    dock:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", inset, 0)
    dock:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
  end
end

-- @localised-keys: literals in this table ARE GC.L keys, looked up in dockSubText. The table closes
-- with a `}` on its own line, where the contract spec's scanner stops.
local DOCK_SUB = {
  left = "still on the list: %d at a vendor · %d to craft",
  blizzard = "Blizzard's price: %s",
  blizzard_left = "Blizzard's price: %s · %d s left",
  partial = "%d of %d at or under your cap",
  under = "%s · %s under market",
  at_market = "%s · at market price",
  over = "the cheapest is %s, your cap is %s",
  over_nocheap = "nothing at or under your cap of %s",
  bought = "bought %d for %s",
  have = "already in your bags and bank",
  skipped = "skipped for this session, it stays on the list",
  vendor = "a vendor sells it for %s each",
  vendor_vs = "a vendor sells it for %s each · the auction house asks %s",
  vendor_only = "a vendor sells it",
  craft = "craft it for %s each",
  craft_vs = "craft it for %s each · %s here",
  craft_only = "craft it yourself",
  nocap = "no cap for this item — right-click the line to set one",
}

-- Which arguments of each sub-line are money (formatted), in order; the rest are counts.
local DOCK_MONEY = { blizzard = { true }, blizzard_left = { true, false },
  under = { true, true }, at_market = { true }, over = { true, true }, over_nocheap = { true },
  bought = { false, true }, vendor = { true }, vendor_vs = { true, true }, craft = { true },
  craft_vs = { true, true }, total = { true }, estimate = { true } }

local function dockSubText(sub)
  if not sub then return "" end
  local money = DOCK_MONEY[sub.key] or {}
  local args = {}
  for i, value in ipairs(sub.args or {}) do
    args[i] = money[i] and formatAmount(value) or value
  end
  if sub.key == "total" or sub.key == "error" then return args[1] end
  -- A gear line's lots by price: "9s · 4 lots   10s · 2 lots   19s · over your cap".
  if sub.key == "lots" then
    local parts = {}
    for _, g in ipairs(sub.groups) do
      local price = formatAmount(g.buyout)
      parts[#parts + 1] = (g.over and (GC.L["%s · over your cap"]):format(price))
        or (g.count == 1 and (GC.L["%s · 1 lot"]):format(price))
        or (GC.L["%s · %d lots"]):format(price, g.count)
    end
    return table.concat(parts, "   ")
  end
  if sub.key == "estimate" then return "~" .. args[1] end
  return (GC.L[DOCK_SUB[sub.key]]):format(unpack(args))
end

-- Paints the dock for the line it is on (GC.Buy._focus), or for the end of the run. The purchase
-- button's words are actionLabel's -- the same answer the Enter key and the attempt log read.
local function paintDock()
  local dock = band and band.dock
  if not dock then return end
  if not current then
    dock:Hide()
    return
  end
  dock:Show()
  local line = lineFor(GC.Buy._focus)
  local d
  if line then
    local attempt = GC.Buy._attempt
    local mine = (attempt and attempt.itemID == line.itemID) and attempt or nil
    local status = lineStatus(line)
    local read = readOf(line)
    d = { line = line, status = status,
      attempt = mine and { stage = mine.stage, qty = mine.qty, total = mine.total,
        serverTotal = mine.serverTotal, capped = mine.capped, secondsLeft = quoteSecondsLeft(mine),
        errorText = mine.errorText } or nil,
      quote = recentQuote(line), raiseTo = status == "over" and raiseOffered(line) or nil,
      cheapest = (read and read.ladder and read.ladder[1] and read.ladder[1].unit) or line.floor,
      craft = GC.BuyRun.CraftText(line) }
    -- A gear line: its lots by price, from its own read, or the last one still worth drawing.
    local seen = quotes[line.itemID]
    if mine and mine.lots and mine.lotList then
      d.lots = { groups = GC.BuyLots.Groups(mine.lotList, line.cap, line.minIlvl), why = mine.lotWhy }
    elseif seen and seen.lots and (time() - (seen.at or 0)) <= BD.LADDER_SECONDS then
      d.lots = { groups = GC.BuyLots.Groups(seen.lots, line.cap, line.minIlvl) }
    end
  else
    local t = current:Totals()
    local skipped = 0
    for _, l in ipairs(current:Lines()) do
      if not l.done and isSkipped(l) then skipped = skipped + 1 end
    end
    d = { vendorLeft = t.atVendor or 0, craftLeft = t.toCraft or 0, skippedLeft = skipped }
  end
  local v = GC.BuyDock.View(d)
  dock.lineItemID = line and line.itemID or nil
  if line then
    dock.title:SetText(("%s ×%d"):format(lineName(line), line.buy > 0 and line.buy or line.need))
    local icon = nil
    if C_Item and C_Item.GetItemIconByID then
      local ok, texture = pcall(C_Item.GetItemIconByID, line.itemID)
      icon = ok and texture or nil
    end
    if icon then dock.icon:SetTexture(icon); dock.icon:Show() else dock.icon:Hide() end
  else
    dock.title:SetText(v.title == "rest_skipped" and GC.L["The rest is skipped for now"]
      or GC.L["Everything here is bought"])
    dock.icon:Hide()
  end
  dock.sub:SetText(dockSubText(v.sub))
  setColor(dock.sub, (v.mode == "over" and Theme.tier.SUSPECT) or (v.mode == "confirm" and Theme.color.goldHi)
    or (v.mode == "done" and Theme.color.green) or Theme.color.fgDim)
  -- One control, several looks, never two overlaid buttons: SetVariant runs BEFORE Enable/Disable
  -- (it repaints the text in the variant's own colours and would undo the dimmed look), and a
  -- disabled look is Enable() then Disable() -- OnDisable fires on a state CHANGE only.
  if v.primary == "purchase" then
    local label, clickable, variant = actionLabel(line)
    dock.buy:SetVariant(variant or "primary")
    dock.buy:SetLabel(label)
    dock.buy:Enable()
    if not clickable then dock.buy:Disable() end
    dock.buy:Show()
  elseif v.primary == "raise" then
    dock.buy:SetVariant("active")
    dock.buy:SetLabel((GC.L["RAISE CAP TO %s"]):format(formatAmount(v.raiseTo)))
    dock.buy:Enable()
    dock.buy:Show()
  else
    dock.buy:Hide()
  end
  if v.secondary then
    dock.second:SetLabel(v.secondary == "cancel" and GC.L["Cancel"] or GC.L["Skip"])
    dock.second:Enable()
    dock.second:Show()
  else
    dock.second:Hide()
  end
  layoutDock(dock)
end

-- ---------------------------------------------------------------------------
-- The item box (BUY 2.0): a quick list made in the game, one item at a time
-- ---------------------------------------------------------------------------

-- What the box adds: an item link (a shift-click into it) or an item id, with an optional count.
-- A typed name is not looked up: the BUY 2.0 probe found the client resolves almost none
-- (C_Item.GetItemInfoInstant answered 0 of 15 typed names in retail, 2 of 15 in the Russian WoW:
-- Forever client), and GoldCap keeps no name index of its own. An id is checked with the client,
-- which always knows its items by id.
local function addFromBox(box)
  local add = GC.Buy._view.add
  local parsed = GC.BuyView.ParseAdd(box:GetText() or "")
  if parsed == nil then return end
  -- false: two bare numbers, which say nothing about which one is the item (GC.BuyView.ParseAdd).
  local itemID = parsed and parsed.itemID
  if itemID and C_Item and C_Item.GetItemInfoInstant then
    local ok, known = pcall(C_Item.GetItemInfoInstant, itemID)
    if not (ok and known) then itemID = nil end
  end
  if not itemID then
    add.note:SetText(GC.L["Could not find that item. Shift-click it, or type its item id."])
    GC.Buy.RefreshIfShown()
    return
  end
  GC.AppRuns.AddQuick(itemID, parsed.qty)
  box:SetText("")
  add.note:SetText((GC.L["Added %d× %s to your quick list."]):format(parsed.qty, lineName({ itemID = itemID })))
  GC.Buy.SelectRun(GC.AppRuns.QUICK)
  GC.Buy.RefreshIfShown()
end

-- The box: "Item to add" over a well the player types or shift-clicks into, and a line under it
-- that says how to use it, or what the last Enter did. Every line wraps rather than cut.
local function createAdd(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:Hide()
  local caption = Theme.Num(frame, 9)
  caption:SetJustifyH("LEFT")
  caption:SetWordWrap(true)
  caption:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -6)
  caption:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
  caption:SetText(GC.L["Item to add"])
  setColor(caption, Theme.color.fgDim)
  local well = CreateFrame("Frame", nil, frame)
  well:SetSize(BD.ADD_W, 22)
  well:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -4)
  local wc = Theme.color.bg or Theme.color.panel
  Theme.SlicedTexture(well, "BACKGROUND", Theme.MEDIA .. "plaque.png", { wc[1], wc[2], wc[3], 1 }, 12):SetAllPoints(well)
  Theme.SlicedTexture(well, "BORDER", Theme.MEDIA .. "plaque_ring.png", { 1, 1, 1, 0.12 }, 12):SetAllPoints(well)
  local box = CreateFrame("EditBox", nil, well)
  box:SetAutoFocus(false)
  box:SetPoint("TOPLEFT", 10, -2)
  box:SetPoint("BOTTOMRIGHT", -8, 2)
  if box.SetFont then
    box:SetFont(Theme.FONT_UI, 11 * Theme.Scale(), "")
    box:SetTextColor(Theme.color.fg[1], Theme.color.fg[2], Theme.color.fg[3], 1)
  end
  box:SetScript("OnEnterPressed", addFromBox)
  box:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
  end)
  local note = Theme.Num(frame, 10)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  note:SetPoint("TOPLEFT", well, "BOTTOMLEFT", 0, -4)
  note:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
  note:SetText(GC.L["Shift-click an item or type its item id, with x and a count for more: 2589 x20."])
  setColor(note, Theme.color.fgDim)
  return { frame = frame, caption = caption, well = well, box = box, note = note, h = 64 }
end

-- The box as tall as its wrapped lines, for the row that holds its place (heightFor).
local function layoutAdd(add)
  local width = (geometry and geometry.rowWidth or 0) - 8
  if width > 0 then
    add.well:SetWidth(math.min(BD.ADD_W, width))
    add.caption:SetWidth(width)
    add.note:SetWidth(width)
  end
  local ch = add.caption.GetStringHeight and add.caption:GetStringHeight() or 12
  local nh = add.note.GetStringHeight and add.note:GetStringHeight() or 12
  add.h = math.ceil(6 + (ch or 12) + 4 + 22 + 4 + (nh or 12) + 8)
  add.frame:SetHeight(add.h)
end

local function updateContentWidth()
  if not container or not content then return end
  applyWidth(container:GetWidth())
end

local function renderRows()
  if not content then return end
  -- The dock is on a line whenever there is one to buy: the one the player picked (a purchase
  -- moves it on by itself, settlePurchase), or -- when nothing is picked, or the picked line has
  -- gone from the run -- the first still worth buying. Never moved while a purchase is in the
  -- client's hands: CONFIRM belongs to that line.
  if current and not inFlight(GC.Buy._attempt) and not lineFor(GC.Buy._focus) then
    GC.Buy._focus = nextOpenAfter(nil)
  end
  local entries = buildEntries()
  -- A filter or search that hides the dock's line moves the dock to the first visible line it can
  -- buy (or, with none, the first visible line, which the dock explains) -- never while a purchase
  -- is in the client's hands, whose CONFIRM belongs to its own line.
  local narrowed = (GC.Buy._filter or "all") ~= "all" or (GC.Buy._query or "") ~= ""
  if current and narrowed and not inFlight(GC.Buy._attempt) then
    local visible, firstBuyable, firstShown = {}, nil, nil
    for _, e in ipairs(entries) do
      if e.line then
        visible[e.line.itemID] = true
        firstShown = firstShown or e.line.itemID
        if not firstBuyable and buyable(e.line) then firstBuyable = e.line.itemID end
      end
    end
    if firstShown and not visible[GC.Buy._focus or -1] then GC.Buy._focus = firstBuyable or firstShown end
  end

  paintBand()

  for i = #rows + 1, #entries do rows[i] = createRow(content) end
  if GC.Buy._view and GC.Buy._view.add then layoutAdd(GC.Buy._view.add) end
  -- Painted first, measured second, laid out last: a column is as wide as the widest thing this
  -- render puts in it, and a row as tall as its wrapped name.
  for i, entry in ipairs(entries) do paintRow(rows[i], entry, i) end
  fitColumns(#entries)
  local y = 0
  for i, entry in ipairs(entries) do
    local row = rows[i]
    layoutRow(row)
    local h = heightFor(entry.kind, row)
    row:SetHeight(h)
    -- TOPLEFT + TOPRIGHT so a row's width tracks content's, which updateContentWidth keeps
    -- current with the real window/dock width.
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    row:Show()
    y = y + h
  end
  for i = #entries + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math.max(1, y))
  local add = GC.Buy._view and GC.Buy._view.add
  if add then
    add.frame:Hide()
    for i, entry in ipairs(entries) do
      if entry.kind == "add" then
        add.frame:ClearAllPoints()
        add.frame:SetPoint("TOPLEFT", rows[i], "TOPLEFT", 0, 0)
        add.frame:SetPoint("TOPRIGHT", rows[i], "TOPRIGHT", 0, 0)
        if add.frame.SetFrameLevel and rows[i].GetFrameLevel then
          add.frame:SetFrameLevel(rows[i]:GetFrameLevel() + 2)
        end
        add.frame:Show()
      end
    end
  end
  paintDock()
  layoutBody()
  paintLists()
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

  band = createBand(container)

  band.header = createHeaderRow(container)
  band.dock = createDock(container)
  band.lists = createLists(container)

  local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  if Theme.QuietScrollBar then Theme.QuietScrollBar(scroll) end -- no Blizzard arrows beside a kit panel
  band.scroll = scroll
  layoutBody()
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(geo.rowWidth, geo.rowHeight)
  scroll:SetScrollChild(content)
  -- OnSizeChanged is the live path (the resize grip, or the AH tab reparenting the window into
  -- a different-width dock); Show() below is the catch-up path for a frame that was hidden
  -- while that happened, since a hidden frame does not reliably fire OnSizeChanged.
  container:HookScript("OnSizeChanged", function(_, width)
    if not width or width <= 0 then return end
    applyWidth(width)
    -- Lay the rows out again for the new width -- their names wrap to it -- without asking the
    -- client about the run again: a drag fires this many times a second.
    if container:IsShown() and band then renderRows() end
  end)

  -- Enter buys the focused line. A key press is a hardware event, so it may reach the protected
  -- purchase call exactly as the click does -- it goes through the same planBuyClick either way.
  --
  -- Propagation is decided PER KEYSTROKE, never set once (UI/SettingsFrame.lua's OnKeyDown says
  -- why): EnableKeyboard(true) delivers EVERY key here, and a frame that swallowed them all
  -- would eat movement, action bars and Enter-to-chat for as long as this tab is up. Only Enter,
  -- and only while the cursor is actually over this window, is taken; everything else is put
  -- straight back. Each widget call is guarded so the headless specs can run without them.
  if container.EnableKeyboard then container:EnableKeyboard(true) end
  container:SetScript("OnKeyDown", onBuyKey)
  -- The one keystroke that leaves propagation off is an Enter that bought a line. Re-armed on
  -- its release, so combat beginning right after that press cannot leave this container eating
  -- movement, action bars and chat for the rest of the fight (OnKeyDown stands down in combat).
  container:SetScript("OnKeyUp", function(self)
    if InCombatLockdown and InCombatLockdown() then return end
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
  end)

  -- The cap box (UI/BuyCapEditor.lua) floats over the list on UIParent; it goes with the tab,
  -- whether the tab is switched away or the window holding it closes.
  container:HookScript("OnHide", function()
    if GC.BuyCapEditor and GC.BuyCapEditor.Close then GC.BuyCapEditor.Close() end
  end)

  GC.Buy._WatchSearches()

  GC.Buy._WatchLinks()

  -- The one seam specs use instead of debug.getupvalue.
  GC.Buy._view = { container = container, rows = rows, band = band, dock = band.dock, lists = band.lists,
    add = createAdd(content) }
end

-- A shift-click while the item box has the focus puts the item's link into it (the BUY 2.0 probe:
-- it does, in both games). A post-hook: it sees what Blizzard's InsertLink was handed and changes
-- nothing that function did -- which, with the auction house open, also fills Blizzard's own
-- search box, harmless.
function GC.Buy._WatchLinks()
  if GC.Buy._watchingLinks or not (hooksecurefunc and _G.ChatFrameUtil
      and type(_G.ChatFrameUtil.InsertLink) == "function") then return end
  GC.Buy._watchingLinks = true
  hooksecurefunc(_G.ChatFrameUtil, "InsertLink", function(text)
    local add = GC.Buy._view and GC.Buy._view.add
    if add and type(text) == "string" and add.box.HasFocus and add.box:HasFocus() then add.box:Insert(text) end
  end)
end

function GC.Buy.Show()
  if not container then return end
  container:Show()
  -- The dock's line is asked for its price again on the next tick: whatever it knew is from
  -- before the tab was put away -- and the list column's progress is worked out afresh.
  GC.Buy._quotedFocus = nil
  GC.Buy._listMeta = {}
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
    rejudgeQuote()
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

-- The ids this run still has a reason to price: open (something left to buy), not a vendor line
-- (the auction house has no answer about it and the row is greyed out anyway). Deduplicated --
-- a run may name the same reagent twice -- because a duplicate key spends a slot in a batch
-- that is capped.
local function refreshTargets()
  if not current then return nil end
  local ids, seen = {}, {}
  for _, line in ipairs(current:Lines()) do
    if not line.vendor and line.kind ~= "craft" and not line.done
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
-- vendor) still took the shared throttle claim for a batch that would come back empty --
-- spending a consumer's slot in GC.Util's per-name pacing for nothing.
local function hasPendingLine()
  if not current then return false end
  for _, line in ipairs(current:Lines()) do
    if not line.vendor and line.kind ~= "craft" and not line.done then
      return true
    end
  end
  return false
end

-- Whether a quote this tab asked for is still waiting for its answer (quotePending). Final review
-- m9: UI/SniperFrame.lua's _TrySendKeysBatchFor asks it before any keys batch goes -- a hover quote
-- left on the wire by a switch to Deals is one a cap batch sent on top would take the answer of.
function GC.Buy.QuotePending()
  return quotePending(GC.Buy._attempt) or lookPending()
end

-- BUY 2.0 week 2: whether a gear line's read holds the auction house's search, from the moment its
-- first search goes until the lot is bought, given up or stale. PlaceBid buys only while the lot's
-- own buy search is the current one, so nothing of ours searches meanwhile: GC.Sniper's quiet zone
-- (IsPurchaseQuiet) asks this, and with it the drills, the verify walk, the watch loop, the keys
-- batches, the book pass and the Sell tab's walk all wait. Bounded by BD.QUOTE_SECONDS, and a bid
-- by its watchdog.
function GC.Buy.HoldsSearch()
  local attempt = GC.Buy._attempt
  if not (attempt and attempt.lots) then return false end
  if attempt.stage == "bidding" then return true end
  if attempt.stage == "quoting" then return quotePending(attempt) end
  return attempt.lot ~= nil and quoteFresh(attempt)
end

-- Every search anybody sends -- ours, Blizzard's own pane, another addon -- counted by post-hooks,
-- which observe a call and cannot change it. A gear line's armed read remembers the count its own
-- search left (sendArm), and a press bids only while nothing has searched since (quoteFresh). The
-- calls that refresh or page a result, query owned auctions or bids, or ask for the full dump are
-- counted too: whether they move the current search was not measured, and the worst a count too
-- many costs is one read more before the bid. Each is hooked only where the client has it (all of
-- them exist in both games, wowsrc.py 2026-10-01).
function GC.Buy._WatchSearches()
  if GC.Buy._watching or not (hooksecurefunc and C_AuctionHouse) then return end
  GC.Buy._watching = true
  local function note() GC.Buy._searchSeq = (GC.Buy._searchSeq or 0) + 1 end
  for _, name in ipairs({ "SendSearchQuery", "SendSellSearchQuery", "SendBrowseQuery",
      "SearchForItemKeys", "SearchForFavorites", "RefreshItemSearchResults",
      "RefreshCommoditySearchResults", "RequestMoreItemSearchResults",
      "RequestMoreCommoditySearchResults", "RequestMoreBrowseResults", "QueryOwnedAuctions",
      "QueryBids", "ReplicateItems" }) do
    if type(C_AuctionHouse[name]) == "function" then hooksecurefunc(C_AuctionHouse, name, note) end
  end
end

-- AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID): the one purchase event that names what it answers.
-- The client then refreshes the armed key's lots by itself, one fewer, with no new query; the line
-- is read again from that refresh (OnItemResults) while the dock stays on it, and nothing is sent.
function GC.Buy.OnPurchaseCompleted(auctionID)
  local attempt = GC.Buy._attempt
  if attempt and attempt.stage == "bidding" and attempt.auctionID == auctionID then
    GC.Buy._attempt = nil
    settlePurchase(attempt.itemID, 1, attempt.total, attempt.runCode, attempt.itemKey)
    local line = lineFor(attempt.itemID)
    -- One lot per press: the dock stays on a gear line until the line is bought.
    if line and buyable(line) then
      GC.Buy._focus = line.itemID
      attemptSeq = attemptSeq + 1
      GC.Buy._attempt = { itemID = line.itemID, stage = "quoting", token = attemptSeq, askedAt = time(),
        runCode = attempt.runCode, lots = true, phase = "arm", key = attempt.key, armSeq = attempt.armSeq,
        lotList = attempt.lotList, afterBuy = true }
      GC.Buy._quotedFocus = line.itemID
      -- The dock shows the line it stays on, and Enter acts on it.
      GC.Buy.RefreshIfShown()
      if attempt.refreshed then GC.Buy.OnItemResults(attempt.key) end
    end
    return true
  end
  local record = GC.Buy._bidStranded[auctionID]
  if record and (time() - (record.at or 0)) <= BD.STRANDED_SECONDS then
    GC.Buy._bidStranded[auctionID] = nil
    if attempt and attempt.stage == "unknown" and attempt.auctionID == auctionID then GC.Buy._attempt = nil end
    settlePurchase(record.itemID, 1, record.total, record.runCode, record.itemKey)
    return true
  end
  return false
end

-- AUCTION_HOUSE_SHOW_ERROR while a bid of this tab is out. An error only a bid can raise
-- (GC.Sell._ErrorKind "bid") is this bid's answer: no gold moved, and the next press reads the lots
-- again. An error only a post can raise is the Sell tab's. Any other names no request and may be
-- another sender's, so the bid is kept as one with no answer (strandBid): its late completion is
-- still booked, and the line is not bought past its need meanwhile. The dock says the error in the
-- client's own words either way.
function GC.Buy.OnAuctionHouseError(code)
  local attempt = GC.Buy._attempt
  if not (attempt and attempt.stage == "bidding") then return false end
  local kind = GC.Sell and GC.Sell._ErrorKind and GC.Sell._ErrorKind(code) or "shared"
  if kind == "post" then return false end
  local line = lineFor(attempt.itemID)
  attempt.errorText = GC.Util and GC.Util.AuctionHouseErrorText and GC.Util.AuctionHouseErrorText(code) or nil
  if kind == "bid" then
    if GC.PurchaseSlot then GC.PurchaseSlot.Release("buy") end
    attempt.stage = "failed"
  else
    strandBid(attempt, line)
  end
  logAttempt(line, attempt.errorText or GC.L["purchase failed — try again"])
  GC.Buy.RefreshIfShown()
  return true
end

-- Read-only, for Core/PurchaseCapture.lua's PlaceBid hook: this tab's own bid, or one it gave up on
-- that may still answer, is filed here once (settlePurchase), never a second time by the capture.
function GC.Buy.OwnsAuctionPurchase(auctionID)
  local attempt = GC.Buy._attempt
  if attempt and attempt.stage == "bidding" and attempt.auctionID == auctionID then return true end
  local record = GC.Buy._bidStranded[auctionID]
  return (record ~= nil and (time() - (record.at or 0)) <= BD.STRANDED_SECONDS) or false
end

-- Whether a bid of this tab is waiting for its answer: the Deals window does not bid over it.
function GC.Buy.BidOut()
  local attempt = GC.Buy._attempt
  return (attempt ~= nil and attempt.stage == "bidding") or false
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
  -- Not over a hover quote still waiting for its answer: a batch sent on top of it would take
  -- that answer (the same collision quote() waits out in the other direction).
  if quotePending(GC.Buy._attempt) or lookPending() then return false end
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
  -- A gear line's armed search the throttle held back (sendArm): first, ahead of anything that
  -- would search over it.
  local arming = GC.Buy._attempt
  if arming and arming.armDue then sendArm(arming) end
  -- A quote held back for an unanswered keys batch (see quote): asked for once the batch is gone,
  -- and only for the line that still has the focus -- the player has moved on otherwise. Ahead
  -- of the refresh, which would otherwise take the moment with a batch of its own.
  local owed = GC.Buy._quoteOwed
  if owed and not (GC.Sniper and GC.Sniper._KeysOutstanding and GC.Sniper._KeysOutstanding())
      and not lookPending() then
    GC.Buy._quoteOwed, GC.Buy._owedByClick = nil, nil
    local line = lineFor(owed)
    if line and GC.Buy._focus == owed and container and container:IsShown() then quote(line) end
    -- The waiting look goes with the debt, whether or not the ask above went out.
    GC.Buy.RefreshIfShown()
  end
  -- The dock's line is asked for its price once each time the dock moves onto it (a pick, a
  -- purchase moving it on, the first line of a run), so its first press can buy: two presses a
  -- line, as Blizzard's own buy page. Marked done only once the ask is on the wire or owed.
  local focus = GC.Buy._focus
  if focus and focus ~= GC.Buy._quotedFocus and container and container:IsShown() then
    local line = lineFor(focus)
    if line and buyable(line) and not inFlight(GC.Buy._attempt) then quote(line) end
    local attempt = GC.Buy._attempt
    if (attempt and attempt.itemID == focus) or GC.Buy._quoteOwed == focus then
      GC.Buy._quotedFocus = focus
    end
  end
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
  GC.Buy._listMeta = {}
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
    local data = shownRunData()
    GC.Print(("run: code=%s name=%s kind=%s from=%s source=%s"):format(
      tostring(current:Code()), tostring(current:Name()),
      tostring(data and data.k or "list"), tostring(data and data.by or "-"),
      tostring(data and data.src or "-")))
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
    elseif line.kind == "craft" then state = GC.L["craft"] end
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

-- ---------------------------------------------------------------------------
-- At a vendor (BUY 2.0 week 2, UI/BuyVendorPanel.lua)
-- ---------------------------------------------------------------------------

-- The vendor panel's question: the current list's lines a merchant could sell -- every line that is
-- bought rather than crafted, not only the site's vendor lines (a quick list has none) -- with
-- what each still needs and its cap, done ones included so a line bought at this merchant can say
-- so. Fresh bag counts: the panel can open while this tab has never been shown this session. A
-- line skipped for the session is left out, as everywhere else. Which of them this merchant sells,
-- at or under its cap, is Core/BuyVendor.lua's Plan.
function GC.Buy.VendorLines()
  if not current then ensureRun() end
  if not current then return nil end
  scanBags()
  current:Refresh()
  local lines = {}
  for _, line in ipairs(current:Lines()) do
    if line.kind ~= "craft" and not line.make and not isSkipped(line) then
      lines[#lines + 1] = { itemID = line.itemID, buy = line.done and 0 or (line.buy or 0),
        need = line.need, cap = line.cap, name = lineName(line) }
    end
  end
  return { runName = runLabel(current), code = current:Code(), lines = lines }
end

-- A vendor purchase the bags proved (GC.BuyVendor.Settle): booked against the list, and as cost in
-- the addon's own acquisitions -- never as a ledger row: goldcap.gg's ledger is auction house money.
function GC.Buy.RecordVendorPurchase(itemID, qty, spent)
  if not (current and (qty or 0) > 0) then return end
  local at = time()
  current:RecordPurchase(itemID, qty, spent or 0, at)
  local line = lineFor(itemID)
  if (spent or 0) > 0 then
    recordAcquisition(itemID, line and lineName(line) or nil, qty, spent, at, current:Code())
  end
  scanBags()
  GC.Buy._listMeta = {}
  GC.Buy.RefreshIfShown()
end
