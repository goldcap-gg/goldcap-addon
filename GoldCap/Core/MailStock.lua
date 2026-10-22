local _, GC = ...

-- What waits in each character's mailbox (retail): attachments are the player's own, so the BUY
-- tab (UI/BuyFrame.lua's haveOf) and the craft queue (Services/CraftClient.lua's CountOf) count
-- them as held beside the bags and the banks, and neither buys again what is already bought.
--
-- The client shows the inbox only while the mailbox is open, so this is what a read there found
-- last, plus what was bought since:
--   * `items`: every attachment the last read of the inbox found (Observe, from the ledger's scan
--     on MAIL_SHOW, on MAIL_INBOX_UPDATE and before each Collect take), whoever sent it: a won
--     auction, a lot that came back, another player's mail. Cash on delivery mail is left out: it
--     is not the player's until it is paid for.
--   * `bought`: units bought at the auction house whose mail no read has found yet (Bought: BUY,
--     the Sniper and Blizzard's own buy page through Core/PurchaseCapture.lua). Retail delivers
--     every auction house purchase by mail, commodities included (measured in the client,
--     2026-08-08), so a purchase waits there from the moment it is made.
--
-- A purchase leaves `bought` on evidence that its mail came, not because a read did not list it.
-- Blizzard's MailFrame fetches the inbox list at most once per C_Mail.CanCheckInbox() window and
-- shows the list it already holds until then (Blizzard_MailFrame/MailFrame.lua,
-- MailFrame_RefreshInbox), so a read can predate a purchase's mail. Each read keeps every
-- attachment it found by item, count and expiry (the ledger's five-minute bucket, matched one
-- bucket either side because the client recomputes days left on every read). A won auction's
-- attachment the read before did not hold is a delivery and takes its units off `bought`; so is
-- one that was new then and reads as a won auction only now (its invoice came after its row). A
-- stale list, a mail out of view and an old won mail still lying there deliver nothing, and a
-- second pass over the same rows finds nothing new. A character's first read is the baseline:
-- nothing in it is taken for a delivery.
--
-- Absence is the fallback, so that a purchase whose mail no read saw arrive does not count for
-- ever: a read of the whole inbox (every row loaded, none out of view) clears the purchases of
-- an item last bought more than LAG_SECONDS before the visit opened, and a purchase is dropped
-- KEEP_SECONDS after it was made whatever the reads said.
--
-- Reads count only between the opening pass (MAIL_SHOW) and MAIL_CLOSED (Closed). An empty answer
-- counts only at MAIL_CLOSED, and only when it was the visit's last pass and not the opening one
-- (that one reads 0 on every visit, the rows arriving a moment later: the ledger's mail probe,
-- 2026-10-11): after the visit showed rows (the player emptied the inbox), or after a visit of
-- at least SETTLE_SECONDS that never showed one. Everything here errs high, which makes BUY offer
-- too little rather than buy twice: a take the visit's last pass did not see stays counted until
-- a later visit reads the inbox, and a row the client has not loaded yet (the "Retrieving data"
-- subject, an attachment without a name) leaves that pass unread.
--
-- Store: GC.db.mailStock = { v = 1, chars = { ["Name-Realm"] = {
--   items = { [itemID] = n }, bought = { [itemID] = { n = units, at = time() of the last } },
--   seen = { ["itemID:count:bucket"] = n } or nil before the first read,
--   fresh = { ["itemID:count:bucket"] = n }: attachments new at the last read, not yet a won
--   auction } } }, made on the first write and never by a count. A store a newer GoldCap wrote is
-- left exactly as it is and counts nothing. Retail TOC only: WoW: Forever never loads this file,
-- so every caller asks `if GC.MailStock`.
GC.MailStock = GC.MailStock or {}
local MS = GC.MailStock

local VERSION = 1
-- How long after a purchase a read that does not list its mail can still be a list fetched
-- before it came (the CanCheckInbox window). A guess until the Dev mail probe measures the window.
local LAG_SECONDS = 120
-- How long a mailbox that never showed a row has to stay open for its empty answer to count.
local SETTLE_SECONDS = 2
-- An auction house mail is returned or deleted after 30 days: nothing bought waits longer.
local KEEP_SECONDS = 30 * 86400

-- This visit to the mailbox, from its opening pass to MAIL_CLOSED, or nil while it is shut:
-- { char, at = time() it opened, rows = a pass showed a row, empty = the last pass answered an
-- empty inbox }. Not saved: a /reload shuts the mailbox.
local visit

local function store(create)
  local db = GC.db
  if type(db) ~= "table" then return nil end
  local s = db.mailStock
  if type(s) ~= "table" then
    if not create then return nil end
    s = { v = VERSION, chars = {} }
    db.mailStock = s
  end
  if (tonumber(s.v) or 0) > VERSION then return nil end
  if type(s.chars) ~= "table" then s.chars = {} end
  return s
end

local function charOf(char, create)
  if type(char) ~= "string" or char == "" then return nil end
  local s = store(create)
  if not s then return nil end
  local c = s.chars[char]
  if type(c) ~= "table" then
    if not create then return nil end
    c = {}
    s.chars[char] = c
  end
  if type(c.items) ~= "table" then c.items = {} end
  if type(c.bought) ~= "table" then c.bought = {} end
  return c
end

local function isCount(n)
  return type(n) == "number" and n == math.floor(n) and n > 0 and n < math.huge
end

local function add(counts, key, n)
  counts[key] = (counts[key] or 0) + n
end

local function keyOf(itemID, count, bucket)
  return itemID .. ":" .. count .. ":" .. bucket
end

-- Takes one attachment like `a` out of the multiset `set`, at its own expiry bucket or one either
-- side; whether there was one.
local function takeOne(set, a)
  for _, bucket in ipairs({ a.bucket, a.bucket - 1, a.bucket + 1 }) do
    local key = keyOf(a.itemID, a.count, bucket)
    local n = set[key]
    if type(n) == "number" and n > 0 then
      set[key] = n > 1 and n - 1 or nil
      return true
    end
  end
  return false
end

local function copy(set)
  local out = {}
  if type(set) == "table" then
    for key, n in pairs(set) do out[key] = n end
  end
  return out
end

--- How many of an item wait in this character's mailbox: what the last read found plus what was
--- bought since. 0 for an unknown character or a newer store.
function MS.Count(char, itemID)
  local c = charOf(char, false)
  if not c or type(itemID) ~= "number" then return 0 end
  local bought = c.bought[itemID]
  return (tonumber(c.items[itemID]) or 0) + (type(bought) == "table" and tonumber(bought.n) or 0)
end

--- An auction house purchase that succeeded: `qty` units of `itemID` are on their way to the
--- mailbox. `now` is time() unless a spec gives it. Returns whether it was written.
function MS.Bought(char, itemID, qty, now)
  if not (isCount(itemID) and isCount(qty)) then return false end
  local c = charOf(char, true)
  if not c then return false end
  local b = c.bought[itemID]
  if type(b) ~= "table" then
    b = { n = 0 }
    c.bought[itemID] = b
  end
  b.n = (tonumber(b.n) or 0) + qty
  b.at = now or time()
  return true
end

--- Whether a visit to the mailbox is going on: from the opening pass to MAIL_CLOSED. Walking from
--- the mailbox straight to an auctioneer can shut it with no MAIL_CLOSED (in game 2026-09-23), so a
--- caller that acts on this asks the client too (UI/CraftQueueView.lua).
function MS.IsOpen()
  return visit ~= nil
end

-- Every attachment of the `shown` rows: by item, and as a list of { itemID, count, bucket, won }.
-- nil while a row is not loaded. Core/MailClassify.lua reads a row as the Collect button does
-- (`api` is the ledger scan's own: GetInboxHeaderInfo, GetInboxInvoiceInfo, GetInboxItem). A mail
-- with no subject is loaded: only the client's placeholder subject says it is not, so an addon's
-- or a system mail does not hold back every read while it sits in the inbox.
local function readInbox(api, shown, now)
  local items, list = {}, {}
  for index = 1, shown do
    local mail = GC.MailClassify.Read(api, index)
    if not mail or GC.MailClassify.IsRetrieving(mail.subject) then return nil end
    if mail.cod == 0 then
      local bucket = GC.Ledger.ExpiryBucket(now, mail.daysLeft) or 0
      local named = 0
      for _, item in ipairs(mail.items) do
        if isCount(item.itemID) and isCount(item.count) then
          named = named + 1
          add(items, item.itemID, item.count)
          list[#list + 1] = { itemID = item.itemID, count = item.count, bucket = bucket,
            won = mail.invoiceType == "buyer" }
        end
      end
      if named < mail.itemCount then return nil end
    end
  end
  return items, list
end

local function deliver(bought, a)
  local b = bought[a.itemID]
  if type(b) ~= "table" then return end
  local left = (tonumber(b.n) or 0) - a.count
  if left > 0 then b.n = left else bought[a.itemID] = nil end
end

-- One read of the inbox for character `c`: `items` and `list` as readInbox gives them, `allShown`
-- whether nothing was out of view, `opened` when this visit began.
local function settle(c, items, list, allShown, now, opened)
  local seen, fresh = {}, {}
  if type(c.seen) == "table" then
    local lastSeen, lastFresh = copy(c.seen), copy(c.fresh)
    for _, a in ipairs(list) do
      local key = keyOf(a.itemID, a.count, a.bucket)
      if a.won then
        if takeOne(lastFresh, a) or not takeOne(lastSeen, a) then deliver(c.bought, a) end
        add(seen, key, 1)
      elseif takeOne(lastSeen, a) then
        add(seen, key, 1)
      else
        takeOne(lastFresh, a)
        add(fresh, key, 1)
      end
    end
    -- With more mail than the client shows (100), what the read before held and this one did not
    -- may be out of view rather than gone: kept, so it is not new when it comes back into view.
    if not allShown then
      for key, n in pairs(lastSeen) do add(seen, key, n) end
      for key, n in pairs(lastFresh) do add(fresh, key, n) end
    end
  else
    for _, a in ipairs(list) do add(seen, keyOf(a.itemID, a.count, a.bucket), 1) end
  end
  c.items, c.seen, c.fresh = items, seen, fresh
  for itemID, b in pairs(c.bought) do
    local at = type(b) == "table" and tonumber(b.at) or nil
    if not at or (tonumber(b.n) or 0) <= 0 or now - at > KEEP_SECONDS
        or (allShown and opened - at > LAG_SECONDS) then
      c.bought[itemID] = nil
    end
  end
end

--- One scan of the inbox (Core/Ledger.lua's ScanInbox): `shown` rows, whether those are all the
--- inbox holds, and whether this is the pass MAIL_SHOW runs, which opens the visit. Returns
--- whether it read the inbox.
function MS.Observe(api, shown, allShown, char, now, opening)
  if opening then visit = { char = char, at = now, rows = false, empty = false } end
  if not visit or visit.char ~= char or type(shown) ~= "number" then return false end
  if shown == 0 then
    visit.empty = not opening and allShown == true
    return false
  end
  visit.rows, visit.empty = true, false
  if not GC.MailClassify then return false end
  local items, list = readInbox(api, shown, now)
  if not items then return false end
  local c = charOf(char, true)
  if not c then return false end
  settle(c, items, list, allShown, now, visit.at)
  return true
end

--- MAIL_CLOSED (Core/Init.lua, and UI/CraftQueueView.lua before it counts again: whichever hears
--- it first ends the visit, the other finds it ended). An empty answer the visit ended on is read
--- now. Returns whether it emptied the mailbox.
function MS.Closed(now)
  local v = visit
  visit = nil
  if not (v and v.empty) then return false end
  now = now or time()
  if not v.rows and now - v.at < SETTLE_SECONDS then return false end
  local c = charOf(v.char, true)
  if not c then return false end
  settle(c, {}, {}, true, now, v.at)
  return true
end
