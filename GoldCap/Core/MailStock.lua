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
-- attachment it found by item, count and expiry: the ledger's five-minute bucket, matched within
-- the ledger's own tolerance, nearest bucket first, because a fresh delivery can read 30 minutes
-- "younger" on one pass than on the next (Core/Ledger.lua, BUCKET_MATCH_TOLERANCE). A won auction
-- that the read before did not hold is a delivery and takes its units off `bought`; so is one that
-- was new then and reads as a won auction only now (its invoice came after its row). Anything else
-- the read before held is never a delivery, and neither is a mail that arrived before the item's
-- oldest pending purchase (auction house mail lasts KEEP_SECONDS, so its expiry says when
-- it came). A stale list, a mail out of view and an old won mail still lying there deliver
-- nothing, and a second pass over the same rows finds nothing new. A character's first read is the
-- baseline: nothing in it is taken for a delivery.
--
-- With more mail than the client shows (100), what the read before held and this one does not is
-- either out of view or gone. The inbox's total tells them apart: when it fell by exactly as many
-- mails as left the view, they were taken (a take moves one mail per pass, and new mail that
-- pushes old mail out of view raises the total), so their attachments are let go; otherwise they
-- are kept apart as out of view, so they are not new when they come back into view. A kept
-- attachment leaves only when it comes back into view or its mail would have expired by now, so
-- nothing is kept longer than its mail can wait. Won auctions are matched before other mail, so a
-- player's mail of the same item and count never uses up a won auction's key.
--
-- Absence is the fallback, so that a purchase whose mail no read saw arrive does not count for
-- ever: a read of the whole inbox (every row loaded, none out of view) clears the purchases of
-- an item last bought more than LAG_SECONDS before the visit opened, and a purchase is dropped
-- KEEP_SECONDS after it was made whatever the reads said. The opening pass never clears: MailFrame
-- asks the server for the inbox only once it shows (MailFrame_Show calls MailFrame_RefreshInbox),
-- so that pass reads the list the client held from before the visit.
--
-- Reads count only between the opening pass (MAIL_SHOW) and MAIL_CLOSED (Closed). An empty answer
-- counts only at MAIL_CLOSED, and only when the visit showed rows and its last pass answered empty
-- (the player emptied the inbox). Everything here errs high, which makes BUY offer too little
-- rather than buy twice: a take the visit's last pass did not see stays counted until a visit that
-- shows mail; two mails of the same item and count within the tolerance are one to the keys, so
-- such a take followed within the hour by the same purchase reads as the old mail still there; and
-- a row the client has not loaded yet (the "Retrieving data" subject, an attachment without a
-- name) leaves that pass unread. Mail out of view counts by the keys kept for it (`away`), so a
-- purchase already credited still counts after the day's sale mail pushed it past the hundredth
-- row; a take on the very pass new mail came in reads as a scroll, and that mail counts until its
-- expiry.
--
-- Store: GC.db.mailStock = { v = 1, chars = { ["Name-Realm"] = {
--   items = { [itemID] = n },
--   bought = { [itemID] = { n = units, at = time() of the last, first = time() of the oldest } },
--   seen = { ["itemID:count:bucket"] = n } or nil before the first read,
--   fresh = { ["itemID:count:bucket"] = n }: attachments new at the last read, not yet a won auction,
--   last = { total, mails = { ["sender\1subject:bucket"] = n } }: the last read's inbox,
--   away = { seen = {...}, fresh = {...} } or nil: kept for mail out of view, keyed as seen } } },
-- made on the first write and never by a count. A store a newer GoldCap wrote is left exactly as it
-- is and counts nothing. Retail TOC only: WoW: Forever never loads this file, so every caller asks
-- `if GC.MailStock`.
GC.MailStock = GC.MailStock or {}
local MS = GC.MailStock

local VERSION = 1
-- How long after a purchase a read that does not list its mail can still be a list fetched
-- before it came (the CanCheckInbox window). A guess until the Dev mail probe measures the window.
local LAG_SECONDS = 120
-- An auction house mail is returned or deleted after 30 days: nothing bought waits longer, and a
-- won auction arrived its expiry less this.
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

local function take(set, key)
  local n = set[key]
  if type(n) == "number" and n > 0 then
    set[key] = n > 1 and n - 1 or nil
    return true
  end
  return false
end

-- Takes one entry like `e` ({ prefix, bucket }) out of the multiset `set`, at its own expiry bucket
-- or the nearest one within the ledger's tolerance; whether there was one.
local function takeOne(set, e)
  local tolerance = GC.Ledger.BUCKET_MATCH_TOLERANCE
  for d = 0, tolerance do
    if take(set, e.prefix .. ":" .. (e.bucket - d))
        or (d > 0 and take(set, e.prefix .. ":" .. (e.bucket + d))) then
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

-- The units of `itemID` that the keys in `set` ({ ["itemID:count:bucket"] = n }) stand for.
local function unitsIn(set, itemID)
  local units = 0
  if type(set) ~= "table" then return units end
  for key, n in pairs(set) do
    local id, per = key:match("^(%d+):(%d+):")
    if tonumber(id) == itemID then units = units + tonumber(per) * n end
  end
  return units
end

--- How many of an item wait in this character's mailbox: what the last read found in view and
--- kept for mail out of view, plus what was bought since. 0 for an unknown character or a newer
--- store.
function MS.Count(char, itemID)
  local c = charOf(char, false)
  if not c or type(itemID) ~= "number" then return 0 end
  local bought = c.bought[itemID]
  local away = type(c.away) == "table" and c.away or {}
  return (tonumber(c.items[itemID]) or 0) + (type(bought) == "table" and tonumber(bought.n) or 0)
    + unitsIn(away.seen, itemID) + unitsIn(away.fresh, itemID)
end

--- An auction house purchase that succeeded: `qty` units of `itemID` are on their way to the
--- mailbox. `now` is time() unless a spec gives it. Returns whether it was written.
function MS.Bought(char, itemID, qty, now)
  if not (isCount(itemID) and isCount(qty)) then return false end
  local c = charOf(char, true)
  if not c then return false end
  now = now or time()
  local b = c.bought[itemID]
  if type(b) ~= "table" then
    b = { n = 0, first = now }
    c.bought[itemID] = b
  end
  b.n = (tonumber(b.n) or 0) + qty
  b.at = now
  return true
end

--- Whether a visit to the mailbox is going on: from the opening pass to MAIL_CLOSED. Walking from
--- the mailbox straight to an auctioneer can shut it with no MAIL_CLOSED (in game 2026-09-23), so a
--- caller that acts on this asks the client too (UI/CraftQueueView.lua).
function MS.IsOpen()
  return visit ~= nil
end

-- What the `shown` rows hold: every attachment by item; the attachments as a list of { prefix =
-- "itemID:count", itemID, count, bucket, won }; and the mails as a list of { prefix =
-- "sender\1subject", bucket }. nil while a row is not loaded. Core/MailClassify.lua reads a row as
-- the Collect button does (`api` is the ledger scan's own: GetInboxHeaderInfo, GetInboxInvoiceInfo,
-- GetInboxItem). A mail with no subject is loaded: only the client's placeholder subject says it is
-- not, so an addon's or a system mail does not hold back every read while it sits in the inbox.
local function readInbox(api, shown, now)
  local items, list, mails = {}, {}, {}
  for index = 1, shown do
    local mail = GC.MailClassify.Read(api, index)
    if not mail or GC.MailClassify.IsRetrieving(mail.subject) then return nil end
    local bucket = GC.Ledger.ExpiryBucket(now, mail.daysLeft) or 0
    mails[#mails + 1] = { prefix = tostring(mail.sender) .. "\1" .. tostring(mail.subject), bucket = bucket }
    if mail.cod == 0 then
      local named = 0
      for _, item in ipairs(mail.items) do
        if isCount(item.itemID) and isCount(item.count) then
          named = named + 1
          add(items, item.itemID, item.count)
          list[#list + 1] = { prefix = item.itemID .. ":" .. item.count, itemID = item.itemID,
            count = item.count, bucket = bucket, won = mail.invoiceType == "buyer" }
        end
      end
      if named < mail.itemCount then return nil end
    end
  end
  return items, list, mails
end

local function deliver(bought, a)
  local b = bought[a.itemID]
  if type(b) ~= "table" then return end
  local left = (tonumber(b.n) or 0) - a.count
  if left > 0 then b.n = left else bought[a.itemID] = nil end
end

-- Whether won auction `a` can have arrived after the item's oldest pending purchase: its expiry
-- less KEEP_SECONDS, read at the top of its bucket and the ledger's tolerance, so a mail that came
-- before the purchase is never taken for its delivery.
local function arrivedSince(b, a)
  if type(b) ~= "table" then return false end
  local first = tonumber(b.first) or tonumber(b.at)
  if not first then return true end
  local L = GC.Ledger
  return (a.bucket + 1 + L.BUCKET_MATCH_TOLERANCE) * L.BUCKET_SECONDS - KEEP_SECONDS >= first
end

-- Whether every mail the last read held and this one does not left the inbox: the total fell by
-- exactly as many mails as left the view (an attachment taken off a mail that stays is no mail
-- leaving). New mail pushing old mail out of view raises the total, so it never passes for a take.
local function onlyTaken(last, mails, total)
  if type(last) ~= "table" or type(last.mails) ~= "table" or type(last.total) ~= "number"
      or type(total) ~= "number" then return false end
  local left = copy(last.mails)
  for _, m in ipairs(mails) do takeOne(left, m) end
  local gone = 0
  for _, n in pairs(left) do gone = gone + n end
  return last.total - total == gone
end

-- Lets go of the entries whose mail would have expired by now, its bucket read late by the
-- ledger's tolerance: no mail waits past its expiry.
local function prune(set, now)
  local L = GC.Ledger
  for key in pairs(set) do
    local bucket = tonumber(key:match(":(%-?%d+)$"))
    if not bucket or (bucket + 1 + L.BUCKET_MATCH_TOLERANCE) * L.BUCKET_SECONDS < now then set[key] = nil end
  end
end

-- Takes one entry like `e` out of the first of `sets` that holds it; that set's index, or nil.
local function takeFirst(sets, e)
  for i, set in ipairs(sets) do
    if takeOne(set, e) then return i end
  end
  return nil
end

-- One read of the inbox for character `c`: `items`, `list` and `mails` as readInbox gives them,
-- `total` the inbox's own count of its mail, `opened` when this visit began, `opening` whether
-- this is the visit's first pass (the list from before it).
local function settle(c, items, list, mails, total, now, opened, opening)
  local allShown = not (type(total) == "number" and total > #mails)
  local seen, fresh = {}, {}
  local away = type(c.away) == "table" and c.away or {}
  local awaySeen, awayFresh = copy(away.seen), copy(away.fresh)
  if type(c.seen) == "table" then
    local lastSeen, lastFresh = copy(c.seen), copy(c.fresh)
    -- Won auctions first, and each takes a key already seen before a new one, in view or out of
    -- it: a won auction already seen is never a delivery, and a player's mail with the same key
    -- must not use its key up. A player's mail takes a new key first for the same reason.
    for _, a in ipairs(list) do
      if a.won then
        local was = takeFirst({ lastSeen, awaySeen, lastFresh, awayFresh }, a)
        if (not was or was > 2) and arrivedSince(c.bought[a.itemID], a) then deliver(c.bought, a) end
        add(seen, a.prefix .. ":" .. a.bucket, 1)
      end
    end
    for _, a in ipairs(list) do
      if not a.won then
        local was = takeFirst({ lastFresh, awayFresh, lastSeen, awaySeen }, a)
        add((was == 3 or was == 4) and seen or fresh, a.prefix .. ":" .. a.bucket, 1)
      end
    end
    -- What left the view on this pass: gone when the total fell by it, otherwise out of view and
    -- kept apart until it comes back or its mail would have expired, so it is not new then.
    if not allShown and not onlyTaken(c.last, mails, total) then
      for key, n in pairs(lastSeen) do add(awaySeen, key, n) end
      for key, n in pairs(lastFresh) do add(awayFresh, key, n) end
    end
  else
    for _, a in ipairs(list) do add(seen, a.prefix .. ":" .. a.bucket, 1) end
  end
  if allShown then awaySeen, awayFresh = {}, {} end
  for _, set in ipairs({ seen, fresh, awaySeen, awayFresh }) do prune(set, now) end
  local inView = {}
  for _, m in ipairs(mails) do add(inView, m.prefix .. ":" .. m.bucket, 1) end
  c.items, c.seen, c.fresh = items, seen, fresh
  c.away = (next(awaySeen) or next(awayFresh)) and { seen = awaySeen, fresh = awayFresh } or nil
  c.last = { total = type(total) == "number" and total or #mails, mails = inView }
  for itemID, b in pairs(c.bought) do
    local at = type(b) == "table" and tonumber(b.at) or nil
    if not at or (tonumber(b.n) or 0) <= 0 or now - at > KEEP_SECONDS
        or (allShown and not opening and opened - at > LAG_SECONDS) then
      c.bought[itemID] = nil
    end
  end
end

--- One scan of the inbox (Core/Ledger.lua's ScanInbox): `shown` rows, `total` the mail the inbox
--- holds (GetInboxNumItems' second return: more than `shown` when mail is out of view), and
--- whether this is the pass MAIL_SHOW runs, which opens the visit. Returns whether it read the
--- inbox.
function MS.Observe(api, shown, total, char, now, opening)
  if opening then visit = { char = char, at = now, rows = false, empty = false } end
  if not visit or visit.char ~= char or type(shown) ~= "number" then return false end
  if shown == 0 then
    visit.empty = not opening and not (type(total) == "number" and total > 0)
    return false
  end
  visit.rows, visit.empty = true, false
  if not GC.MailClassify then return false end
  local items, list, mails = readInbox(api, shown, now)
  if not items then return false end
  local c = charOf(char, true)
  if not c then return false end
  settle(c, items, list, mails, total, now, visit.at, opening)
  return true
end

--- MAIL_CLOSED (Core/Init.lua, and UI/CraftQueueView.lua before it counts again: whichever hears
--- it first ends the visit, the other finds it ended). A visit that showed rows and ended on an
--- empty answer emptied the inbox, and is read so now. Returns whether it did.
function MS.Closed(now)
  local v = visit
  visit = nil
  -- An empty answer from a visit that never showed a row is not read: the client may answer 0, 0
  -- before the rows on a reopen inside the CanCheckInbox window. Session D's log decides whether it
  -- may count again.
  if not (v and v.rows and v.empty) then return false end
  local c = charOf(v.char, true)
  if not c then return false end
  settle(c, {}, {}, {}, 0, now or time(), v.at)
  return true
end
