-- An API-shaped double of the client's bags and Send Mail tab, for the Send to alts window
-- (UI/MailAltsFrame.lua). `post.api` carries only names the client has, under the names a file
-- reads them by: the container calls a spec puts in C_Container (GetContainerNumSlots,
-- GetContainerItemInfo, PickupContainerItem), and the globals PickupContainerItem leaves behind
-- (ClickSendMailItemButton, HasSendMailItem, SetSendMailCOD, SetSendMailMoney, SendMail,
-- GetCursorInfo, ClearCursor, MailFrameTab_OnClick, GetAutoCompleteRealms) and the frames
-- (MailFrame, SendMailFrame, SendMailNameEditBox). Everything a spec steers or reads lives on
-- `post` itself (succeed, fail, refuse, calls, attached ...), so production code can never come to
-- depend on a control only the double has.
--
-- The bags are `bags[bag][slot] = info`, as GetContainerItemInfo answers it ({ itemID, itemName,
-- stackCount, iconFileID, hyperlink, isBound, isLocked }); `false` is an empty slot that still
-- counts toward the bag's size. As in the client, a stack picked up onto the cursor or attached to
-- the Send Mail tab shows locked in its slot until it is put back or the mail goes.
--
-- Shapes as Blizzard_MailFrame/MailFrame.lua uses them: ClickSendMailItemButton() drops the cursor's
-- item into the first free attachment (SendMailAttachmentButton_OnDropAny),
-- ClickSendMailItemButton(index, true) takes attachment `index` back to the bags (a right click,
-- SendMailAttachmentButton_OnClick), and MailFrameTab_OnClick(nil, 2) shows the Send Mail tab and
-- sets its `sendMode` to "send" (the field Blizzard's Lua keeps on SendMailFrame, "reply" after
-- OpenMail_Reply), 1 the inbox. SendMail hands the mail to the server: its attachments stay until
-- the server answers (post:succeed, after which the window hears MAIL_SEND_SUCCESS; post:fail,
-- MAIL_FAILED).
local W = require("spec.support.wow_frames")

local Post = {}

-- ATTACHMENTS_MAX_SEND (Blizzard_MailFrame/MailFrame.lua).
local SLOTS = 12

function Post.new(opts)
  opts = opts or {}
  local post = {}
  local state = { bags = opts.bags or {}, sizes = opts.sizes or {}, cursor = nil, attachments = {}, log = {},
    refused = {}, ignored = {}, pending = nil, realms = opts.realms or {} }
  post.bags = state.bags

  local function log(name, ...)
    state.log[#state.log + 1] = { name = name, n = select("#", ...), ... }
  end

  local function copy(info)
    local out = {}
    for k, v in pairs(info) do out[k] = v end
    return out
  end

  local function setLocked(bag, slot, locked)
    local info = state.bags[bag] and state.bags[bag][slot]
    if info then info.isLocked = locked end
  end

  local api = {}

  function api.GetContainerNumSlots(bag)
    return state.sizes[bag] or (state.bags[bag] and #state.bags[bag]) or 0
  end

  function api.GetContainerItemInfo(bag, slot)
    local info = state.bags[bag] and state.bags[bag][slot]
    if not info then return nil end
    return copy(info)
  end

  -- The cursor takes the stack and its slot locks; with the cursor already holding that stack, it
  -- goes back.
  function api.PickupContainerItem(bag, slot)
    log("PickupContainerItem", bag, slot)
    local held = state.cursor
    if held then
      if held.bag == bag and held.slot == slot then
        setLocked(bag, slot, false)
        state.cursor = nil
      end
      return
    end
    local info = state.bags[bag] and state.bags[bag][slot]
    if not info or info.isLocked or state.ignored[bag .. ":" .. slot] then return end
    info.isLocked = true
    state.cursor = { bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink }
  end

  function api.ClickSendMailItemButton(index, clearItem)
    log("ClickSendMailItemButton", index, clearItem)
    if index ~= nil then
      local attached = state.attachments[index]
      if not attached then return end
      if clearItem then
        state.attachments[index] = nil
        setLocked(attached.bag, attached.slot, false)
      elseif not state.cursor then
        state.attachments[index] = nil
        state.cursor = attached
      end
      return
    end
    local held = state.cursor
    if not held or state.refused[held.bag .. ":" .. held.slot] then return end
    for i = 1, SLOTS do
      if not state.attachments[i] then
        state.attachments[i] = held
        state.cursor = nil
        return
      end
    end
  end

  function api.HasSendMailItem(index)
    return state.attachments[index] ~= nil
  end

  function api.SetSendMailCOD(copper)
    log("SetSendMailCOD", copper)
    state.cod = copper
  end

  function api.SetSendMailMoney(copper)
    log("SetSendMailMoney", copper)
    state.money = copper
  end

  function api.SendMail(to, subject, body)
    log("SendMail", to, subject, body)
    local items = {}
    for i = 1, SLOTS do
      local a = state.attachments[i]
      if a then items[#items + 1] = a.bag .. ":" .. a.slot end
    end
    state.pending = { to = to, subject = subject, body = body, cod = state.cod, money = state.money, items = items }
  end

  -- GetCursorInfo: "item", itemID, link while an item is on the cursor.
  function api.GetCursorInfo()
    local held = state.cursor
    if not held then return nil end
    return "item", held.itemID, held.link
  end

  function api.ClearCursor()
    log("ClearCursor")
    local held = state.cursor
    if held then setLocked(held.bag, held.slot, false) end
    state.cursor = nil
  end

  function api.GetAutoCompleteRealms()
    return state.realms
  end

  api.MailFrame = W.CreateFrame("Frame")
  api.SendMailFrame = W.CreateFrame("Frame", nil, api.MailFrame)
  api.SendMailNameEditBox = W.CreateFrame("EditBox", nil, api.SendMailFrame)
  -- The mailbox opens on the inbox (MailFrame_Show calls MailFrameTab_OnClick(nil, 1)).
  api.SendMailFrame:Hide()

  function api.MailFrameTab_OnClick(self, tabID)
    log("MailFrameTab_OnClick", self, tabID)
    if tabID == 2 then
      api.SendMailFrame:Show()
      api.SendMailFrame.sendMode = "send"
    else
      api.SendMailFrame:Hide()
    end
  end

  post.api = api

  -- The server takes the mail in flight: its stacks leave the bags, the attachments empty.
  function post:succeed()
    local mail = assert(state.pending, "no mail in flight")
    state.pending = nil
    for i = 1, SLOTS do
      local a = state.attachments[i]
      if a then
        state.bags[a.bag][a.slot] = false
        state.attachments[i] = nil
      end
    end
    return mail
  end

  -- The server refuses the mail in flight: its attachments stay in the Send Mail tab.
  function post:fail()
    state.pending = nil
  end

  -- The Send Mail tab will not take the stack in `bag`, `slot`: it stays on the cursor.
  function post:refuse(bag, slot)
    state.refused[bag .. ":" .. slot] = true
  end

  -- The client drops a pickup of the stack in `bag`, `slot` without a word: the cursor stays empty.
  function post:ignore(bag, slot)
    state.ignored[bag .. ":" .. slot] = true
  end

  -- Every call a name was logged under, in order, each { name, n, args ... }; or all of them.
  function post:calls(name)
    if name == nil then return state.log end
    local out = {}
    for _, call in ipairs(state.log) do
      if call.name == name then out[#out + 1] = call end
    end
    return out
  end

  -- The names of the calls so far, in order.
  function post:names()
    local out = {}
    for _, call in ipairs(state.log) do out[#out + 1] = call.name end
    return out
  end

  function post:attached()
    local n = 0
    for i = 1, SLOTS do
      if state.attachments[i] then n = n + 1 end
    end
    return n
  end

  function post:holding() return state.cursor end
  function post:pending() return state.pending end

  return post
end

return Post
