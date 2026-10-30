-- An API-shaped double of the client's mailbox. `box.api` carries only names the client has
-- (GetInbox*, TakeInboxMoney, TakeInboxItem, CheckInbox); everything a spec steers lives
-- on `box` itself (advance, refreshNow, addRow ...), so production code can never come to
-- depend on a control only the double has.
--
-- A row is { sender, subject, money, cod, daysLeft, canReply, isGM, auction, invoice, items }:
--   * `invoice` is { invoiceType, itemName, ... } as GetInboxInvoiceInfo answers it, or nil.
--   * `items` maps a slot (1..16) to { name, itemID, count }.
--   * `auction` rows are deleted by the server when nothing is left on them, so every later
--     index shifts; any other mail stays until the player deletes it.
-- A take is a command: it stays pending until box:advance(), which applies it, the
-- way the client answers a take a moment later.
-- A take acts on the mail its index named when it was made, as the server does, not on whatever
-- row that index holds by the time it lands: box:refreshNow can move the rows in between.
local Mailbox = {}

local function copyRow(row)
  local items = {}
  for slot, item in pairs(row.items or {}) do
    items[slot] = { name = item.name or ("Item " .. tostring(item.itemID)), itemID = item.itemID, count = item.count or 1 }
  end
  return {
    sender = row.sender or "Someone", subject = row.subject or "Hello", money = row.money or 0,
    cod = row.cod or 0, daysLeft = row.daysLeft or 29, canReply = row.canReply == true,
    isGM = row.isGM == true, auction = row.auction == true, invoice = row.invoice, items = items,
  }
end

local function itemCountOf(row)
  local n = 0
  for _ in pairs(row.items) do n = n + 1 end
  return n
end

function Mailbox.new(rows, opts)
  opts = opts or {}
  local box = {}
  local state = {
    rows = {}, hidden = {}, pending = nil, checkAsked = false,
  }
  for _, row in ipairs(rows or {}) do state.rows[#state.rows + 1] = copyRow(row) end
  for _, row in ipairs(opts.hidden or {}) do state.hidden[#state.hidden + 1] = copyRow(row) end

  local api = {}

  function api.GetInboxNumItems()
    return #state.rows, #state.rows + #state.hidden
  end

  function api.GetInboxHeaderInfo(index)
    local row = state.rows[index]
    if not row then return end
    -- packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, itemCount,
    -- wasRead, wasReturned, textCreated, canReply, isGM (Blizzard_MailFrame/MailFrame.lua).
    return "package", "stationery", row.sender, row.subject, row.money, row.cod, row.daysLeft,
      itemCountOf(row), false, false, false, row.canReply, row.isGM
  end

  function api.GetInboxInvoiceInfo(index)
    local row = state.rows[index]
    if not row or not row.invoice then return end
    local inv = row.invoice
    return inv.invoiceType, inv.itemName, inv.playerName or "Other", inv.bid or 0, inv.buyout or 0,
      inv.deposit or 0, inv.consignment or 0, inv.moneyDelay or 0, 0, 0, inv.count or 1, true
  end

  function api.GetInboxItem(index, slot)
    local row = state.rows[index]
    local item = row and row.items[slot]
    if not item then return end
    return item.name, item.itemID, "texture", item.count, 1, true
  end

  function api.TakeInboxMoney(index)
    state.pending = { kind = "money", row = state.rows[index] }
  end

  function api.TakeInboxItem(index, slot)
    state.pending = { kind = "item", row = state.rows[index], slot = slot }
  end

  function api.CheckInbox()
    state.checkAsked = true
  end

  box.api = api

  -- The client answers the pending take: the money or slot empties, an emptied auction mail goes
  -- (later indices shift), and a CheckInbox brings the rows that were out of view.
  function box:advance()
    local take = state.pending
    state.pending = nil
    local at
    for i, row in ipairs(state.rows) do
      if take and row == take.row then at = i end
    end
    if at then
      local row = take.row
      if take.kind == "money" then
        row.money = 0
      else
        local item = row.items[take.slot]
        if item then row.items[take.slot] = nil end
      end
      if row.auction and row.money == 0 and next(row.items) == nil then
        table.remove(state.rows, at)
      end
    end
    if state.checkAsked then
      state.checkAsked = false
      for _, row in ipairs(state.hidden) do state.rows[#state.rows + 1] = row end
      state.hidden = {}
    end
  end

  -- Blizzard's own refresh landing right now, whatever take is in flight: MailFrame.lua's
  -- InboxFrame_Update calls CheckInbox by itself on every MAIL_INBOX_UPDATE while fewer than
  -- MAX_INBOX_SIZE (100) rows show and more exist. The rows out of view come in at the back, and
  -- `delivered` (mail that arrived since, newest first) comes in at the front, shifting every
  -- index after it.
  function box:refreshNow(delivered)
    for i = #(delivered or {}), 1, -1 do table.insert(state.rows, 1, copyRow(delivered[i])) end
    for _, row in ipairs(state.hidden) do state.rows[#state.rows + 1] = row end
    state.hidden = {}
  end

  function box:rowCount() return #state.rows end
  function box:row(index) return state.rows[index] end
  function box:addRow(row) state.rows[#state.rows + 1] = copyRow(row) end
  function box:removeRow(index) table.remove(state.rows, index) end

  return box
end

return Mailbox
