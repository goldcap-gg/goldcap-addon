local _, GC = ...

-- Reads one inbox row into a plain record and decides whether the Collect button takes it
-- (Core/MailLoop.lua drives the takes, UI/MailCollect.lua owns the only calls). Nothing here
-- changes the mailbox: `api` only needs GetInboxHeaderInfo, GetInboxInvoiceInfo and GetInboxItem,
-- and GetInboxNumItems for Count.
--
-- What is never taken, and why:
--   * cash on delivery mail (the 6th return of GetInboxHeaderInfo is above zero): taking it spends
--     the player's gold on a stranger's price;
--   * GM mail (13th return);
--   * mail that is neither a player's nor an auction's, such as a quest reward: Collect has no
--     business with it;
--   * a "Sale Pending" invoice, whose gold is not attached yet;
--   * a mail still "Retrieving data": taking before the ledger could read its invoice would lose
--     the sale, so it is left for the next press and counted as still loading;
--   * a sale or a won auction whose invoice the ledger cannot record yet, by the ledger's own rule
--     (Core/Ledger.lua, ReadsInvoice), for the same reason and with the same count.
-- Blizzard's own Open All (Blizzard_MailFrame/MailFrame.lua, OpenAllMailMixin) applies the same
-- first two rules.

GC.MailClassify = {}

local SLOTS = 16

local KEYS = { "expired", "removed", "outbid" }

-- The client's own subject formats (AUCTION_EXPIRED_MAIL_SUBJECT and its siblings) as patterns,
-- by the ledger's subject matching, so the match holds in every language. A missing format
-- leaves an empty list.
function GC.MailClassify.Patterns(subjects)
  local patterns = {}
  for _, key in ipairs(KEYS) do
    local format = type(subjects) == "table" and subjects[key] or nil
    patterns[key] = format and GC.Ledger.NoInvoicePatterns({ format }) or {}
  end
  return patterns
end

local function subjectKindOf(subject, patterns)
  if type(subject) ~= "string" or type(patterns) ~= "table" then return nil end
  for _, key in ipairs(KEYS) do
    for _, pattern in ipairs(patterns[key] or {}) do
      if subject:find(pattern) then return key end
    end
  end
  return nil
end

-- `items` are the attachments the client has named, the ones a take can go for; `attachments`
-- are every slot that holds an item id, named yet or not, for the mail's identity.
local function readItems(api, index)
  local items, attachments = {}, {}
  for slot = 1, SLOTS do
    local ok, name, itemID, _, count = pcall(api.GetInboxItem, index, slot)
    if ok and (name or itemID ~= nil) then
      local item = { slot = slot, itemID = itemID, count = count or 1 }
      attachments[#attachments + 1] = item
      if name then items[#items + 1] = item end
    end
  end
  return items, attachments
end

-- What a mail is, apart from where it sits and how long it has left: sender, subject, gold, the
-- number of attachments and each attachment's item id and count. Core/MailLoop.lua confirms a
-- take by it, because a row index does not hold still: Blizzard's MailFrame refreshes the inbox by
-- itself in the middle of a run (MailFrame.lua, InboxFrame_Update), which brings rows in at the
-- back and new mail in at the front. Days left is left out because a refresh recomputes it.
function GC.MailClassify.Identity(mail)
  local parts = { tostring(mail.sender), tostring(mail.subject), tostring(mail.money),
    tostring(mail.itemCount) }
  for _, item in ipairs(mail.attachments or {}) do
    parts[#parts + 1] = item.slot .. ":" .. tostring(item.itemID) .. "x" .. tostring(item.count)
  end
  return table.concat(parts, "\1")
end

-- The identity the same mail has once a take of its gold (`slot` nil) or of one slot has landed.
function GC.MailClassify.IdentityAfter(mail, slot)
  local after = { sender = mail.sender, subject = mail.subject, money = mail.money,
    itemCount = mail.itemCount, attachments = mail.attachments }
  if slot then
    after.itemCount = mail.itemCount - 1
    after.attachments = {}
    for _, item in ipairs(mail.attachments or {}) do
      if item.slot ~= slot then after.attachments[#after.attachments + 1] = item end
    end
  else
    after.money = 0
  end
  return GC.MailClassify.Identity(after)
end

local function readHeader(api, index)
  local ok, _, _, sender, subject, money, cod, daysLeft, itemCount, _, _, _, canReply, isGM =
    pcall(api.GetInboxHeaderInfo, index)
  if not ok or (sender == nil and subject == nil and money == nil) then return nil end
  return { index = index, sender = sender, subject = subject, money = money or 0, cod = cod or 0,
    daysLeft = daysLeft, itemCount = itemCount or 0, canReply = canReply, isGM = isGM,
    items = {}, attachments = {} }
end

-- The identity of the row at `index` now, or nil when the client cannot answer for it yet.
function GC.MailClassify.IdentityAt(api, index)
  local mail = readHeader(api, index)
  if not mail then return nil end
  if mail.itemCount > 0 then mail.items, mail.attachments = readItems(api, index) end
  return GC.MailClassify.Identity(mail)
end

-- One row as a plain record, or nil when the client cannot answer for it yet. `context` is the
-- ledger's (Core/Ledger.lua, Context), for its rule on whether it can record this row's invoice.
function GC.MailClassify.Read(api, index, patterns, context)
  local mail = readHeader(api, index)
  if not mail then return nil end
  local invoiceOk, invoiceType = pcall(api.GetInboxInvoiceInfo, index)
  if not invoiceOk then return nil end
  mail.invoiceType = invoiceType
  mail.subjectKind = subjectKindOf(mail.subject, patterns)
  if invoiceType == "seller" or invoiceType == "buyer" then
    mail.ledgerReads = GC.Ledger.ReadsInvoice(api, index, context) == true
  end
  if mail.itemCount > 0 then mail.items, mail.attachments = readItems(api, index) end
  local parts = { mail.sender, mail.subject, mail.daysLeft, mail.money, mail.itemCount }
  for i = 1, 5 do parts[i] = parts[i] == nil and "" or tostring(parts[i]) end
  mail.key = table.concat(parts, "\1")
  mail.identity = GC.MailClassify.Identity(mail)
  return mail
end

local function trimEllipsis(text)
  return (text:gsub("%.+%s*$", ""):gsub("\226\128\166%s*$", ""))
end

local function isLoadingSubject(subject)
  if subject == nil or subject == "" then return true end
  local retrieving = _G.RETRIEVING_DATA
  return type(retrieving) == "string" and trimEllipsis(subject) == trimEllipsis(retrieving)
end
-- Core/MailStock.lua holds back its read of the inbox on the same rule.
GC.MailClassify.IsLoading = isLoadingSubject

local KIND_GROUP = {
  sale = "sales", expired = "returns", cancelled = "returns", purchase = "purchases",
  outbid = "purchases", player = "players",
}
local SUBJECT_KIND = { expired = "expired", removed = "cancelled", outbid = "outbid" }

-- { take = true, kind, group } or { skip = reason }. The order of the rules is the contract.
function GC.MailClassify.Decide(mail, enabled)
  if mail.isGM then return { skip = "gm" } end
  if mail.cod > 0 then return { skip = "cod" } end

  local kind
  if mail.invoiceType == "seller" then
    kind = "sale"
  elseif mail.invoiceType == "seller_temp_invoice" then
    return { skip = "pending" }
  elseif mail.invoiceType == "buyer" then
    kind = "purchase"
  elseif mail.subjectKind and mail.canReply ~= true then
    -- A player's own subject can read like an auction's; only a mail without a reply button is
    -- the auction house's.
    kind = SUBJECT_KIND[mail.subjectKind]
  elseif mail.canReply == true then
    kind = "player"
  elseif isLoadingSubject(mail.subject) then
    return { skip = "loading" }
  else
    return { skip = "system" }
  end

  local group = KIND_GROUP[kind]
  if not (enabled and enabled[group]) then return { skip = "off" } end
  if mail.money == 0 and mail.itemCount == 0 then return { skip = "empty" } end
  -- Attachments the client has not named yet: nothing to take from until they load.
  if mail.money == 0 and #mail.items == 0 then return { skip = "loading" } end
  -- Ledger first: the invoice goes with the gold or the items, so it must be recordable now.
  if (kind == "sale" or kind == "purchase") and not mail.ledgerReads then return { skip = "loading" } end
  return { take = true, kind = kind, group = group }
end

-- How many rows Collect would take now, and how many are still loading.
function GC.MailClassify.Count(api, patterns, enabled, context)
  local ok, shown = pcall(api.GetInboxNumItems)
  if not ok or type(shown) ~= "number" then return 0, 0 end
  local takeable, loading = 0, 0
  for index = 1, shown do
    local mail = GC.MailClassify.Read(api, index, patterns, context)
    if not mail then
      loading = loading + 1
    else
      local decision = GC.MailClassify.Decide(mail, enabled)
      if decision.take then takeable = takeable + 1
      elseif decision.skip == "loading" then loading = loading + 1 end
    end
  end
  return takeable, loading
end
