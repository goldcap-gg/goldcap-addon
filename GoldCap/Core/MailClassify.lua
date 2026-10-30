local _, GC = ...

-- Reads one inbox row into a plain record for Core/MailStock.lua. Nothing here changes the
-- mailbox: `api` only needs GetInboxHeaderInfo, GetInboxInvoiceInfo and GetInboxItem.

GC.MailClassify = {}

local SLOTS = 16

-- `items` are the attachments the client has named; a slot that holds an item id the client has
-- not named yet is left out.
local function readItems(api, index)
  local items = {}
  for slot = 1, SLOTS do
    local ok, name, itemID, _, count = pcall(api.GetInboxItem, index, slot)
    if ok and name then
      items[#items + 1] = { slot = slot, itemID = itemID, count = count or 1 }
    end
  end
  return items
end

local function readHeader(api, index)
  local ok, _, _, sender, subject, money, cod, daysLeft, itemCount =
    pcall(api.GetInboxHeaderInfo, index)
  if not ok or (sender == nil and subject == nil and money == nil) then return nil end
  return { index = index, sender = sender, subject = subject, money = money or 0, cod = cod or 0,
    daysLeft = daysLeft, itemCount = itemCount or 0, items = {} }
end

-- One row as a plain record, or nil when the client cannot answer for it yet.
function GC.MailClassify.Read(api, index)
  local mail = readHeader(api, index)
  if not mail then return nil end
  local invoiceOk, invoiceType = pcall(api.GetInboxInvoiceInfo, index)
  if not invoiceOk then return nil end
  mail.invoiceType = invoiceType
  if mail.itemCount > 0 then mail.items = readItems(api, index) end
  return mail
end

local function trimEllipsis(text)
  return (text:gsub("%.+%s*$", ""):gsub("\226\128\166%s*$", ""))
end

-- Whether `subject` is the client's placeholder for a row whose data has not arrived yet.
-- Core/MailStock.lua holds back its read of the inbox on the placeholder alone: a mail with no
-- subject counts as loaded.
function GC.MailClassify.IsRetrieving(subject)
  local retrieving = _G.RETRIEVING_DATA
  return type(subject) == "string" and type(retrieving) == "string"
    and trimEllipsis(subject) == trimEllipsis(retrieving)
end
