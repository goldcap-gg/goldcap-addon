local _, GC = ...

-- What waits in each character's mailbox (retail): attachments are the player's own, so the BUY
-- tab (UI/BuyFrame.lua's haveOf) and the craft queue (Services/CraftClient.lua's CountOf) count
-- them as held beside the bags and the banks, and neither buys again what is already bought.
--
-- The client shows the inbox only while the mailbox is open, so this is what was seen there last,
-- plus what was bought since:
--   * `items`: every attachment the last full read of the inbox found (Observe, from the ledger's
--     scan on MAIL_SHOW and MAIL_INBOX_UPDATE), whoever sent it: a won auction, a lot that came
--     back, another player's mail. Cash on delivery mail is left out: it is not the player's
--     until it is paid for.
--   * `bought`: units bought at the auction house after that read (Bought: BUY, the Sniper and
--     Blizzard's own buy page through Core/PurchaseCapture.lua). Retail delivers every auction
--     house purchase by mail, commodities included (measured in the client, 2026-08-08), so a
--     purchase waits there from the moment it is made until a read of the inbox finds it.
-- A read that finds everything the inbox holds clears `bought`: each purchase is then among the
-- attachments, or taken. With more mail than the client shows (100), a purchase is cleared by the
-- won auctions of its item the read found, so a purchase whose mail is out of view still counts.
-- A read with a row the client has not loaded yet (header, subject or an attachment) changes
-- nothing, and neither does the empty pass before the first row arrives (the ledger's rule), so a
-- taken mail stops counting only once a read sees it gone. Between reads the count misses only
-- what it cannot know of, mail another player sent since; everything else errs high (a mail that
-- expired, a taken one the visit's last read did not see): BUY then offers too little and the
-- player buys the rest by hand, never what is already bought.
--
-- Store: GC.db.mailStock = { v = 1, chars = { ["Name-Realm"] = { items = { [itemID] = n },
--   bought = { [itemID] = n }, at = time() of the last read or nil } } }, made on the first write
-- and never by a read. A store a newer GoldCap wrote is left exactly as it is and counts nothing.
-- Retail TOC only: WoW: Forever never loads this file, so every caller asks `if GC.MailStock`.
GC.MailStock = GC.MailStock or {}
local MS = GC.MailStock

local VERSION = 1

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

local function add(counts, itemID, n)
  counts[itemID] = (counts[itemID] or 0) + n
end

--- How many of an item wait in this character's mailbox: what the last read found plus what was
--- bought since. 0 for an unknown character or a newer store.
function MS.Count(char, itemID)
  local c = charOf(char, false)
  if not c or type(itemID) ~= "number" then return 0 end
  return (tonumber(c.items[itemID]) or 0) + (tonumber(c.bought[itemID]) or 0)
end

--- An auction house purchase that succeeded: `qty` units of `itemID` are on their way to the
--- mailbox. Returns whether it was written.
function MS.Bought(char, itemID, qty)
  if not (isCount(itemID) and isCount(qty)) then return false end
  local c = charOf(char, true)
  if not c then return false end
  add(c.bought, itemID, qty)
  return true
end

-- Every attachment of the `shown` rows by item, and those of won auctions apart; nil while a row
-- is not loaded. Core/MailClassify.lua reads a row as the Collect button does (`api` is the
-- ledger scan's own: GetInboxHeaderInfo, GetInboxInvoiceInfo, GetInboxItem).
local function readInbox(api, shown)
  local items, won = {}, {}
  for index = 1, shown do
    local mail = GC.MailClassify.Read(api, index)
    if not mail or GC.MailClassify.IsLoading(mail.subject) then return nil end
    if mail.cod == 0 then
      local named = 0
      for _, item in ipairs(mail.attachments) do
        if type(item.itemID) == "number" and isCount(item.count) then
          named = named + 1
          add(items, item.itemID, item.count)
          if mail.invoiceType == "buyer" then add(won, item.itemID, item.count) end
        end
      end
      if named < mail.itemCount then return nil end
    end
  end
  return items, won
end

--- One scan of the inbox (Core/Ledger.lua's ScanInbox, past the empty pass before the first row):
--- `shown` rows, and whether those are all the inbox holds. Replaces what the character's mailbox
--- holds when every row reads; returns whether it did.
function MS.Observe(api, shown, allShown, char, now)
  if type(shown) ~= "number" or not GC.MailClassify then return false end
  local items, won = readInbox(api, shown)
  if not items then return false end
  local c = charOf(char, true)
  if not c then return false end
  c.items, c.at = items, now
  for itemID, n in pairs(c.bought) do
    local left = allShown and 0 or (tonumber(n) or 0) - (won[itemID] or 0)
    c.bought[itemID] = left > 0 and left or nil
  end
  return true
end
