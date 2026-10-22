-- An API-shaped double of the client's mailbox. `box.api` carries only names the client has
-- (GetInbox*, TakeInboxMoney, TakeInboxItem, CheckInbox, C_Mail.*); everything a spec steers lives
-- on `box` itself (advance, refuse, setCanCheck, calls ...), so production code can never come to
-- depend on a control only the double has (spec/mail_collect_wiring_spec.lua greps for them).
--
-- A row is { sender, subject, money, cod, daysLeft, canReply, isGM, auction, invoice, items }:
--   * `invoice` is { invoiceType, itemName, ... } as GetInboxInvoiceInfo answers it, or nil.
--   * `items` maps a slot (1..16) to { name, itemID, count }.
--   * `auction` rows are deleted by the server when nothing is left on them, so every later
--     index shifts; any other mail stays until the player deletes it.
-- A take is a command: IsCommandPending() stays true until box:advance(), which applies it, the
-- way the client answers a take a moment later. A refused item (box:refuse) is never emptied.
local Mailbox = {}

local SLOTS = 16

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
    rows = {}, hidden = {}, pending = nil, canCheck = true, canCheckSeconds = 0,
    checkAsked = false, refused = {}, takes = {}, opening = false, openingCalls = {},
    checks = 0,
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
    state.takes[#state.takes + 1] = { fn = "TakeInboxMoney", index = index }
    state.pending = { kind = "money", index = index }
  end

  function api.TakeInboxItem(index, slot)
    state.takes[#state.takes + 1] = { fn = "TakeInboxItem", index = index, slot = slot }
    state.pending = { kind = "item", index = index, slot = slot }
  end

  function api.CheckInbox()
    state.checks = state.checks + 1
    if state.canCheck then state.checkAsked = true end
  end

  api.C_Mail = {
    CanCheckInbox = function() return state.canCheck, state.canCheckSeconds end,
    IsCommandPending = function() return state.pending ~= nil end,
    SetOpeningAll = function(flag)
      state.opening = flag and true or false
      state.openingCalls[#state.openingCalls + 1] = state.opening
    end,
    HasInboxMoney = function(index)
      local row = state.rows[index]
      return row ~= nil and row.money > 0
    end,
  }
  box.api = api

  -- The client answers the pending take: the money or slot empties, an emptied auction mail goes
  -- (later indices shift), and a CheckInbox brings the rows that were out of view.
  function box:advance()
    local take = state.pending
    state.pending = nil
    if take then
      local row = state.rows[take.index]
      if row then
        if take.kind == "money" then
          row.money = 0
        else
          local item = row.items[take.slot]
          if item and not state.refused[item.itemID] then row.items[take.slot] = nil end
        end
        if row.auction and row.money == 0 and next(row.items) == nil then
          table.remove(state.rows, take.index)
        end
      end
    end
    if state.checkAsked then
      state.checkAsked = false
      for _, row in ipairs(state.hidden) do state.rows[#state.rows + 1] = row end
      state.hidden = {}
    end
  end

  -- The flat table Core/MailLoop.lua is given: the mailbox functions under their own names plus
  -- the four members UI/MailCollect.lua builds from C_Mail and C_Container. `bags.free` is the
  -- number of free bag slots, steered by the spec.
  function box:flat(bags)
    bags = bags or { free = 20 }
    local flat = {}
    for name, fn in pairs(api) do
      if name ~= "C_Mail" then flat[name] = fn end
    end
    flat.CanCheckInbox = api.C_Mail.CanCheckInbox
    flat.IsCommandPending = api.C_Mail.IsCommandPending
    flat.SetOpeningAll = api.C_Mail.SetOpeningAll
    flat.FreeBagSlots = function() return bags.free end
    return flat
  end

  function box:refuse(itemID) state.refused[itemID] = true end
  function box:setCanCheck(flag, seconds)
    state.canCheck, state.canCheckSeconds = flag and true or false, seconds or 0
  end
  -- The ordered take calls: { fn = "TakeInboxMoney" | "TakeInboxItem", index, slot }.
  function box:calls() return state.takes end
  function box:openingCalls() return state.openingCalls end
  function box:isOpeningAll() return state.opening end
  function box:checkCalls() return state.checks end
  function box:rowCount() return #state.rows end
  function box:row(index) return state.rows[index] end
  function box:pendingCommand() return state.pending ~= nil end
  function box:addRow(row) state.rows[#state.rows + 1] = copyRow(row) end
  function box:removeRow(index) table.remove(state.rows, index) end
  Mailbox.SLOTS = SLOTS

  return box
end

-- The ten-mail inbox the specs share: four mails Collect takes (a sale, an expired lot, a won
-- auction, a player's gold) and six it leaves alone (cash on delivery, GM, one still loading,
-- an empty player mail, a quest reward that is neither player nor auction, a sale still pending).
function Mailbox.tenMail()
  return {
    { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 50000, auction = true,
      invoice = { invoiceType = "seller", itemName = "Linen Cloth" } },
    { sender = "Auction House", subject = "Auction expired: Silk Cloth", auction = true,
      items = { [1] = { itemID = 4306, count = 20 } } },
    { sender = "Auction House", subject = "Auction won: Wool Cloth", auction = true,
      invoice = { invoiceType = "buyer", itemName = "Wool Cloth" },
      items = { [1] = { itemID = 2592, count = 5 } } },
    { sender = "Friend", subject = "For you", money = 1000, canReply = true },
    { sender = "Friend", subject = "Pay me", canReply = true, cod = 1000, items = { [1] = { itemID = 1, count = 1 } } },
    { sender = "GM", subject = "Ticket", isGM = true, money = 5 },
    { sender = "Auction House", subject = "Retrieving data...", money = 0 },
    { sender = "Friend", subject = "Hi", canReply = true },
    { sender = "Quest Giver", subject = "Reward", items = { [1] = { itemID = 5, count = 1 } } },
    { sender = "Auction House", subject = "Auction successful: Mageweave", money = 0, auction = true,
      invoice = { invoiceType = "seller_temp_invoice", itemName = "Mageweave" } },
  }
end

return Mailbox
