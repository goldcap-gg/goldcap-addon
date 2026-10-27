local _, GC = ...

-- Send to alts (retail only): a window of GoldCap's beside Blizzard's mail frame (owner, 2026-10-26)
-- that mails each followed group's items in the bags to the character that sells them, one press for
-- all of them. Drawn in the GoldCap Hoard's look (UI/HoardFrame.lua and UI/HoardRow.lua, loaded
-- before this file, whose header, handle, keep chip, item icons and helpers it builds with):
-- - the top card: how many mails go to how many of the player's characters, who gets what and how
--   many stacks, the postage, and Send all; while a run goes, what goes now, a gold bar, how many
--   have gone, and Stop where Send all stood; with nothing to send, why;
-- - a card per group with items in the bags (Core/MailGroups.lua's Plan rows, by name): its name,
--   its play, its Keep (the Hoard's keep count and popup, GC.HoardRow.AskKeep), who sells it (a menu
--   of the characters this one can mail), the icons of what goes (a bound or refundable stack dimmed
--   with a lock, its tooltip saying why it stays), a line, and its own Send; while a run goes, Sent,
--   Sending or Next in the Send's place;
-- - a footer: gold never goes, what a group keeps stays, and a mail holds 12 stacks.
--
-- What goes in which mail is Core/MailGroups.lua's Plan over the bag reader's stacks
-- (UI/BankRoute.lua's ReadStacks, a bound or refundable stack marked `stays` through StaysWhy); who
-- the player's characters are and which of them this one can mail, Core/Alts.lua's; the press,
-- Core/MailPress.lua's machine over the driver below, which makes every mail call there is: the
-- first mail attached and sent inside the player's click, the rest from the machine's timers once the
-- server has answered the one before. Gold never goes: SetSendMailCOD(0) and SetSendMailMoney(0)
-- right before every SendMail. Measured in retail 12.1.5 (probe B, 2026-10-26): PickupContainerItem
-- then ClickSendMailItemButton attaches a stack, and SendMail sends, from a click and from a timer,
-- with the Send Mail tab open. Opening that tab from code (MailFrameTab_OnClick(nil, 2)) was not
-- measured: it is one call, in openSendTab, made inside the press before the first attach.
--
-- A name typed by hand that is not one of the player's characters, and one of them not seen for 30
-- days (Core/Alts.lua's Recent: it may have been deleted and its name taken), is asked about once:
-- the first press that would mail it arms its button ("Send to <name>? Press again") for
-- ARM_SECONDS, as the Sniper's loud confirm does (UI/SniperFrame.lua's armLoudConfirm): disabled for
-- its first ARM_HOLD, so a double click's second click cannot confirm it, then the second press
-- trusts it (GC.MailGroups.Trust) and sends. The Stop a press puts in Send all's place refuses
-- presses for its first ARM_HOLD the same way, so a double click never stops the run it started. A
-- press this character cannot pay the postage of does not start, and says so.
--
-- While a run goes the window shows the plan it was pressed with, so nothing on it moves while the
-- bags change under the run; a group a run sent in full says Sent for the rest of the visit. A mail
-- the server refuses goes back to the bags and the run goes on with the next character; its end
-- names whose mail did not go. The window shows at every visit to the mailbox, with nothing to send
-- too (it then says why), unless the player closed it with its X: remembered for the account in
-- GC.db.mailAlts = { v = 1, closed = true }, made lazily and not through DEFAULTS (a newer `v` is
-- read-only, and the X then closes it for this session), and a small handle at the mail frame's
-- right edge brings it back. It goes with the mailbox: at MAIL_CLOSED, and at the mail frame's own
-- hide, which can come with no MAIL_CLOSED. Its own event frame (at the end) hears the mailbox and
-- the bags. GoldCap_Camelot.toc does not load this file.
GC.MailAlts = {}
local MA = GC.MailAlts
local HF = GC.HoardFrame
local K = GC.Kit.Tokens.color
local U = HF.ui
local L = U.L
local setText, colour, wrapping, heightOf, track, restamp = U.setText, U.colour, U.wrapping, U.heightOf, U.track,
  U.restamp

MA.VERSION = 1
-- How long a press that asks about a typed name waits for the second one.
MA.ARM_SECONDS = 5
-- How long, from that first press, its button refuses the second: long enough that a click already
-- on its way (a double click's second) lands on a disabled button (UI/SniperFrame.lua's
-- LIM.REQUOTE_ARM_SECONDS).
MA.ARM_HOLD = 1.5

-- In UI units; the approved boards are drawn at twice that. The window is the Hoard's width (L.WIDTH)
-- with its margins (L.PAD) and the scroll's gutter (L.GUTTER). CARD_PAD: the top card's margin;
-- LETTER: its letter icon, LETTER_GAP right of it; POSTAGE_GAP left of the postage; SEND_H: Send all,
-- STOP_MIN the least its Stop is wide; CAST_GAP between the run's words, its count and Stop; FILL_H:
-- the gold bar. ROW_PAD: a group card's margin, ROW_GAP between two; ICON: an item icon, ICONS the
-- most a card shows; CHIP_H: who sells it, CLASS its class icon, CHIP_PAD its margins; BUTTON_H and
-- BUTTON_PAD: a card's Send; NAME_MIN: the least room a group's name gets beside the chips before
-- they go under it; LINE_TOP between a card's two lines (and above an armed Send's own); LOCK: a
-- staying stack's lock; ROW_LEAST: a card's least height, for the scroll's least room (ROWS_MIN
-- cards). WRAP_PAD: above and below a Send's words when they wrap.
local M = {
  CARD_PAD = 9, LETTER = 26, LETTER_GAP = 9, POSTAGE_GAP = 10, LINE_GAP = 2, NOTE_GAP = 4, BUTTON_GAP = 8,
  SEND_H = 24, STOP_MIN = 64, CAST_GAP = 6, FILL_H = 3, WRAP_PAD = 4,
  ROW_PAD = 7, ROW_GAP = 5, ICON = 24, ICON_GAP = 4, ICONS = 6, CHIP_H = 16, CLASS = 12, CHIP_PAD = 6, CHEVRON = 8,
  CHIP_GAP = 5, COL_GAP = 6, BLOCK_GAP = 4, BUTTON_H = 20, BUTTON_PAD = 8, BUTTON_ICON = 10, NAME_MIN = 60,
  LINE_TOP = 6, LOCK = 12, SECTION_GAP = 10, HEADING_GAP = 6, ROWS_MIN = 3, ROW_LEAST = 56,
}
-- The backpack, the four bag slots and the reagent bag.
local BAGS = { 0, 1, 2, 3, 4, 5 }
-- The letter on the top card: the game's own mail icon (inv_letter_15).
local LETTER_ICON = "Interface\\Icons\\INV_Letter_15"
-- A stack that stays: the lock Blizzard's group finder draws over a locked entry (LFGFrame.lua), cut
-- the way it cuts it.
local LOCK_ICON, LOCK_EDGE = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK", 28 / 32

-- The boards' colours, from the kit's tokens: the top card's gold tint and ring; a card's Send in a
-- gold outline; Stop's ring in the loss colour, as the Hoard's Stop wears it; the card in flight in
-- the Hoard's run gold; "Who sells it?" ringed in gold; a card this character sells at SELF_ALPHA.
local CARD_FILL = { K.gold[1], K.gold[2], K.gold[3], 0.06 }
local CARD_RING = { K.gold[1], K.gold[2], K.gold[3], 0.35 }
local SEND_RING = { K.gold[1], K.gold[2], K.gold[3], 0.5 }
local STOP_RING = { K.loss[1], K.loss[2], K.loss[3], 0.5 }
local RUN_FILL = { K.gold[1], K.gold[2], K.gold[3], 0.07 }
local RUN_RING = { K.gold[1], K.gold[2], K.gold[3], 0.6 }
local PICK_RING = { K.gold[1], K.gold[2], K.gold[3], 0.6 }
local SELF_ALPHA = 0.6

-- Whether the mailbox is open (MAIL_SHOW until MAIL_CLOSED or the mail frame's hide). What the last
-- paint read (readBags): the plan, the item icons, this character, its connected realms and the
-- characters it can mail. The run that goes (pressMails): { id, mails, plan (the one it was pressed
-- with), done = { [mail] = true }, failed = { [recipient] = true } (whose mail the server refused),
-- current (the mail in flight), shown, index, total (the last mail the machine announced), held
-- (its Stop refusing presses, for ARM_HOLD from its start) }. The
-- groups a run sent in full in this visit, by key, as the run's plan had them; why the last run
-- stopped, in words; the button armed for a typed name ({ id, full, to, token }); the names trusted
-- for this session that a newer GoldCap's save could not keep; the X for this session while
-- GC.db.mailAlts is a newer GoldCap's. The cards, pooled by place.
MA._open = false
MA._reading = nil
MA._run = nil
MA._sent = {}
MA._stopped = nil
MA._armed = nil
MA._trustedHere = {}
MA._closedHere = nil
MA._rows = {}
MA.machine = nil

local frame, handle
local armSeq = 0
local paint

-- One guarded client call: its first answer (false kept as false), or nil when it is missing or fails.
local function ask(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- What the window remembers
-- ---------------------------------------------------------------------------------------------

local function newer(saved)
  return type(saved) == "table" and type(saved.v) == "number" and saved.v > MA.VERSION
end

local function ours(saved)
  return type(saved) == "table" and saved.v == MA.VERSION
end

local function closedNow()
  if MA._closedHere ~= nil then return MA._closedHere end
  local saved = type(GC.db) == "table" and GC.db.mailAlts or nil
  return ours(saved) and saved.closed == true
end

-- Remembers the window closed (true) or open (false, which keeps nothing new): for the account, or for
-- this session while a newer GoldCap's memory is saved.
local function setClosed(closed)
  local db = GC.db
  if type(db) ~= "table" or newer(db.mailAlts) then
    MA._closedHere = closed
    return
  end
  MA._closedHere = nil
  if not closed and not ours(db.mailAlts) then return end
  if not ours(db.mailAlts) then db.mailAlts = { v = MA.VERSION } end
  db.mailAlts.closed = closed or nil
end

-- ---------------------------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------------------------

-- This character as Core/Alts.lua keys it ({ name, realm, faction, full }), or nil while the client
-- has not told its name and realm.
local function meNow()
  local name, realm = ask(UnitName, "player"), ask(GetNormalizedRealmName)
  if type(name) ~= "string" or name == "" or type(realm) ~= "string" or realm == "" then return nil end
  return { name = name, realm = realm, faction = ask(UnitFactionGroup, "player"), full = name .. "-" .. realm }
end

-- The realms this character can mail besides its own: the client's connected realms, as its own name
-- box completes them (Blizzard_AutoComplete's AutoComplete.lua).
local function connectedNow()
  local realms = C_AutoComplete and ask(C_AutoComplete.GetAutoCompleteRealms) or ask(GetAutoCompleteRealms)
  return type(realms) == "table" and realms or {}
end

-- Why a stack in the bags stays out of a mail (Core/MailGroups.lua's StaysWhy), for the reader.
local function staysWhy(loc, stack)
  return GC.MailGroups.StaysWhy(stack, ask(C_Item.CanBeRefunded, loc))
end

local function wanted(itemID)
  return GC.GroupRules.GroupOf(itemID) ~= nil
end

-- What the window paints from: the followed groups' stacks in the bags, bound ones too (they stay,
-- named), planned into mails against the alts saved for this realm; each item's icon from the first
-- of its stacks; and the characters this one can mail, with each one's class. Without a followed
-- group no slot is read.
local function readBags()
  local me = meNow()
  local connected = connectedNow()
  local reading = { me = me, connected = connected, icons = {}, classOf = {},
    hasGroups = GC.GroupRules ~= nil and GC.GroupRules.HasGroups(),
    plan = { rows = {}, mails = {}, stacks = 0, postage = 0 } }
  reading.alts = me and GC.Alts.Recipients(GC.db, me, connected) or {}
  for _, alt in ipairs(reading.alts) do reading.classOf[alt.full] = alt.class end
  if not reading.hasGroups then return reading end
  local stacks = GC.BankRoute.ReadStacks(BAGS, false, wanted, nil, { soulbound = true, staysWhy = staysWhy })
  for _, stack in ipairs(stacks) do
    if reading.icons[stack.itemID] == nil then reading.icons[stack.itemID] = stack.icon end
  end
  local home = me and me.realm
  reading.plan = GC.MailGroups.Plan(stacks, {
    groupOf = GC.GroupRules.GroupOf,
    keepFor = function(key) return GC.BankGroups.KeepFor(GC.db, key) end,
    recipientOf = function(key) return home and GC.MailGroups.RecipientOf(GC.db, home, key, me.faction) or nil end,
    mailName = function(full) return me and GC.Alts.MailName(full, me, connected) or nil end,
    isMe = function(full) return me ~= nil and full == me.full end,
  })
  return reading
end

-- ---------------------------------------------------------------------------------------------
-- Words
-- ---------------------------------------------------------------------------------------------

-- `names` as one list, in the language's own way: "Herbs", "Herbs and Ore", "Herbs, Ore and Cloth".
local function listOf(names)
  local text = names[1] or ""
  for i = 2, #names - 1 do text = GC.L["%s, %s"]:format(text, names[i]) end
  if #names >= 2 then text = GC.L["%s and %s"]:format(text, names[#names]) end
  return text
end

-- `names` with commas alone: "Herbs, Ore".
local function commasOf(names)
  local text = names[1] or ""
  for i = 2, #names do text = GC.L["%s, %s"]:format(text, names[i]) end
  return text
end

-- Each group's name by its key, from a plan's rows.
local function namesOf(plan)
  local names = {}
  for _, row in ipairs(plan.rows) do names[row.key] = row.name end
  return names
end

local function groupNames(keys, names)
  local out = {}
  for _, key in ipairs(keys) do out[#out + 1] = names[key] or key end
  return out
end

-- The recipients of `mails` in mail order, each { to, keys, mails, done }: its groups' keys in order,
-- how many of the mails go to it, and how many of those `done` holds.
local function byRecipient(mails, done)
  local list, by = {}, {}
  for _, mail in ipairs(mails) do
    local r = by[mail.to]
    if not r then
      r = { to = mail.to, keys = {}, seen = {}, mails = 0, done = 0 }
      by[mail.to] = r
      list[#list + 1] = r
    end
    r.mails = r.mails + 1
    if done and done[mail] then r.done = r.done + 1 end
    for _, key in ipairs(mail.keys) do
      if not r.seen[key] then
        r.seen[key] = true
        r.keys[#r.keys + 1] = key
      end
    end
  end
  return list
end

local function stacksOf(mails)
  local n = 0
  for _, mail in ipairs(mails) do n = n + #mail.stacks end
  return n
end

-- "2 mails to 2 of your characters".
local function mailsTitle(mails)
  local alts = #byRecipient(mails)
  if #mails == 1 then return GC.L["1 mail to 1 of your characters"] end
  if alts == 1 then return GC.L["%d mails to 1 of your characters"]:format(#mails) end
  return GC.L["%d mails to %d of your characters"]:format(#mails, alts)
end

-- "Herbs and Ore to Mirelle in one mail, Potions to Thornwick. 11 stacks.": "in one mail" only where
-- several groups share one.
local function plannedLine(mails, names)
  local text
  for _, r in ipairs(byRecipient(mails)) do
    local groups = listOf(groupNames(r.keys, names))
    local part = (#r.keys >= 2 and r.mails == 1) and GC.L["%s to %s in one mail"]:format(groups, r.to)
      or GC.L["%s to %s"]:format(groups, r.to)
    text = text and GC.L["%s, %s"]:format(text, part) or part
  end
  local n = stacksOf(mails)
  if n == 1 then return GC.L["%s. 1 stack."]:format(text or "") end
  return GC.L["%s. %d stacks."]:format(text or "", n)
end

-- How a group stands in `run`: "sending" while a mail of it is in flight, "sent" once every mail of
-- it has gone, "next" before; nil for a group the run does not send, or no longer does (the server
-- refused a mail to its character).
local function runStatus(run, key)
  local inRun, all = false, true
  for _, mail in ipairs(run.mails) do
    for _, k in ipairs(mail.keys) do
      if k == key then
        inRun = true
        if run.current == mail then return "sending" end
        if not run.done[mail] then
          if run.failed[mail.to] then return nil end
          all = false
        end
      end
    end
  end
  if not inRun then return nil end
  return all and "sent" or "next"
end

-- While a run goes: what has gone, to whom, and what goes now. "Herbs and Ore went to Mirelle in one
-- mail. Sending Potions to Thornwick now."
local function runLine(run, names)
  local parts = {}
  for _, r in ipairs(byRecipient(run.mails, run.done)) do
    local gone = {}
    for _, key in ipairs(r.keys) do
      if runStatus(run, key) == "sent" then gone[#gone + 1] = names[key] or key end
    end
    if #gone > 0 then
      local groups = listOf(gone)
      parts[#parts + 1] = (#gone >= 2 and r.done == 1) and GC.L["%s went to %s in one mail."]:format(groups, r.to)
        or GC.L["%s went to %s."]:format(groups, r.to)
    end
  end
  local mail = run.current
  if mail then
    parts[#parts + 1] = GC.L["Sending %s to %s now."]:format(listOf(groupNames(mail.keys, names)), mail.to)
  end
  return table.concat(parts, " ")
end

-- With nothing to send: why. No followed group; a group with no one chosen to sell it; a group this
-- character sells; else every group keeps what is in the bags.
local function whyNothing(reading)
  if not reading.hasGroups then return GC.L["Follow groups on goldcap.gg to send them to your alts here."] end
  local self = false
  for _, row in ipairs(reading.plan.rows) do
    if row.state == "pick" then return GC.L["Choose who it goes to, once. GoldCap remembers."] end
    self = self or row.state == "self"
  end
  if self then return GC.L["This character sells them, so they stay."] end
  return GC.L["Your groups have nothing in your bags beyond what they keep."]
end

-- Why a run stopped, in words; nil for a run that finished or the mailbox closing (the window goes
-- with it).
local function stopText(result)
  local reason = result.stopped
  if reason == nil or reason == "closed" then return nil end
  if reason == "tab" then return GC.L["The Send Mail tab was closed."] end
  if reason == "timeout" then return GC.L["The mailbox did not answer. Check your bags and the Send Mail tab."] end
  if reason == "cursor" then return GC.L["Stopped: something is on your cursor."] end
  if reason == "busy" then return GC.L["Stopped: the Send Mail tab already holds items."] end
  if reason == "refused" and type(result.why) == "table" then
    return GC.L["Stopped: %s would not go into the mail."]:format(U.itemName(result.why))
  end
  return GC.L["Stopped."]
end

-- What the end of a run says, in words, or nil: with a mail the server refused, how many went and
-- whose did not ("Sent 3 mails. The mail to Thornwick did not go."); then why it stopped.
local function endText(result)
  local parts = {}
  local failed = result.failed or {}
  if #failed > 0 then
    if result.sent == 1 then
      parts[#parts + 1] = GC.L["Sent 1 mail."]
    elseif (result.sent or 0) > 1 then
      parts[#parts + 1] = GC.L["Sent %d mails."]:format(result.sent)
    end
    parts[#parts + 1] = GC.L["The mail to %s did not go."]:format(listOf(failed))
  end
  parts[#parts + 1] = stopText(result)
  if #parts == 0 then return nil end
  return table.concat(parts, " ")
end

-- When `seen` was, as the recipient menu says it.
local function seenText(seen)
  local days = math.floor(math.max(0, time() - (seen or 0)) / 86400)
  if days == 0 then return GC.L["seen today"] end
  if days == 1 then return GC.L["seen yesterday"] end
  return GC.L["seen %d days ago"]:format(days)
end

-- ---------------------------------------------------------------------------------------------
-- The press
-- ---------------------------------------------------------------------------------------------

-- Whether the mailbox is open: between MAIL_SHOW and MAIL_CLOSED, and the client agrees (walking away
-- can end the visit with no MAIL_CLOSED, as UI/CraftQueueView.lua's mailboxOpen notes).
local function mailboxOpen()
  if not MA._open then return false end
  local manager, kinds = _G.C_PlayerInteractionManager, _G.Enum and _G.Enum.PlayerInteractionType
  if manager and manager.IsInteractingWithNpcOfType and kinds and kinds.MailInfo then
    local ok, open = pcall(manager.IsInteractingWithNpcOfType, kinds.MailInfo)
    if ok and open == false then return false end
  end
  return true
end

-- Whether Blizzard's Send Mail tab shows.
local function sendTabShown()
  local tab = SendMailFrame
  return type(tab) == "table" and type(tab.IsShown) == "function" and tab:IsShown() == true
end

-- Whether the next mail can go: the mailbox open (else "closed") and its Send Mail tab showing (else
-- "tab": the player went to the inbox, or Blizzard did after a reply's mail).
local function sendable()
  if not mailboxOpen() then return false, "closed" end
  if not sendTabShown() then return false, "tab" end
  return true
end

-- How many Send Mail slots hold an item.
local function attachedCount()
  local n = 0
  for i = 1, GC.MailGroups.MAX_ATTACH do
    if ask(HasSendMailItem, i) then n = n + 1 end
  end
  return n
end

-- One stack into the Send Mail tab: picked up, then dropped into its first free slot, as Blizzard's
-- own drop on the tab does (Blizzard_MailFrame's SendMailAttachmentButton_OnDropAny). True only when
-- the cursor is empty again and the tab holds one more item than before: a stack still on the
-- cursor (the tab would not take it; the cursor is emptied again) and a pickup the client dropped
-- without a word (nothing on the cursor, nothing new in the tab) are both not attached, so the
-- machine stops and a mail with nothing in it never goes.
local function attach(stack)
  local before = attachedCount()
  pcall(C_Container.PickupContainerItem, stack.bag, stack.slot)
  pcall(ClickSendMailItemButton)
  local ok, kind = pcall(GetCursorInfo)
  if not (ok and kind == nil) then
    pcall(ClearCursor)
    return false
  end
  return attachedCount() == before + 1
end

-- Every attachment back to the bags, the last slot first, as a right click on it does.
local function clearAttached()
  for i = GC.MailGroups.MAX_ATTACH, 1, -1 do
    if ask(HasSendMailItem, i) then pcall(ClickSendMailItemButton, i, true) end
  end
end

-- The mail: no gold asked for and none sent, set right before every SendMail; no text. False, and
-- no SendMail, when either could not be set: the client may still hold what the player typed for a
-- mail of their own.
local function send(to, subject)
  if not (pcall(SetSendMailCOD, 0) and pcall(SetSendMailMoney, 0)) then return false end
  pcall(SendMail, to, subject, "")
end

-- Blizzard focuses the To box after every mail it sends (MAIL_SEND_SUCCESS's SendMailFrame_Reset),
-- so after a run the keys would type a name instead of moving the character. Its handler may run
-- after this window's, so once now and once on the next frame.
local function letGoOfNameBox()
  local box = SendMailNameEditBox
  if type(box) == "table" and box.ClearFocus then pcall(box.ClearFocus, box) end
end

-- The machine announces a mail it is about to attach: the window shows it (no press or stop from
-- here: Core/MailPress.lua).
local function onProgress(p)
  local run = MA._run
  if not run then return end
  run.current, run.shown, run.index, run.total = p.mail, p.mail, p.index, p.total
  paint()
end

-- A run is over, however it ended: the groups it sent in full say Sent for the rest of the visit, a
-- refused mail and a stop say what happened, the name box lets go, and the window reads the bags
-- again.
local function onReport(result)
  local run = MA._run
  MA._run = nil
  if run then
    local whole = {}
    for _, mail in ipairs(run.mails) do
      for _, key in ipairs(mail.keys) do
        if not run.done[mail] then
          whole[key] = false
        elseif whole[key] == nil then
          whole[key] = true
        end
      end
    end
    for _, row in ipairs(run.plan.rows) do
      if whole[row.key] then MA._sent[row.key] = row end
    end
  end
  MA._stopped = endText(result)
  letGoOfNameBox()
  if C_Timer and C_Timer.After then C_Timer.After(0, letGoOfNameBox) end
  if MA._open then MA.Refresh(true) end
end

function MA._Machine()
  if not MA.machine then
    MA.machine = GC.MailPress.New({
      open = sendable,
      cursorBusy = GC.Util.CursorBusy,
      slot = U.slotNow,
      attach = attach,
      attached = attachedCount,
      clear = clearAttached,
      send = send,
      after = function(seconds, fn) C_Timer.After(seconds, fn) end,
      progress = onProgress,
      report = onReport,
    })
  end
  return MA.machine
end

-- The first name `mails` go to that is neither one of the player's characters seen within 30 days
-- (Core/Alts.lua's Recent) nor trusted yet, with what SendMail takes for it; nil when there is none.
local function untrusted(mails)
  local now = time()
  for _, mail in ipairs(mails) do
    local full = mail.full
    if not (GC.Alts.Recent(GC.db, full, now) or GC.MailGroups.Trusted(GC.db, full) or MA._trustedHere[full]) then
      return full, mail.to
    end
  end
  return nil
end

-- Arms the button `id` for `full` until ARM_SECONDS pass or another arm takes over; `held` (the
-- button disabled) for its first ARM_HOLD.
local function arm(id, full, to)
  armSeq = armSeq + 1
  local token = armSeq
  MA._armed = { id = id, full = full, to = to, token = token, held = true }
  C_Timer.After(MA.ARM_HOLD, function()
    if MA._armed and MA._armed.token == token then
      MA._armed.held = nil
      paint()
    end
  end)
  C_Timer.After(MA.ARM_SECONDS, function()
    if MA._armed and MA._armed.token == token then
      MA._armed = nil
      paint()
    end
  end)
end

-- Blizzard's Send Mail tab, as a send: when the mailbox shows the inbox, and when the tab shows for
-- a reply. Probe B measured attaching and sending with that tab open; the mailbox opens on the inbox
-- (MailFrame_Show); and a reply's tab (OpenMail_Reply's sendMode "reply") turns back to the inbox
-- after the first mail it sends (MailFrame_OnEvent's MAIL_SEND_SUCCESS), where MailFrameTab_OnClick
-- sets sendMode "send". Not measured itself: kept to this one call so it can go if the in-game check
-- shows a problem.
local function openSendTab()
  if sendTabShown() and SendMailFrame.sendMode == "send" then return end
  if type(MailFrameTab_OnClick) == "function" then pcall(MailFrameTab_OnClick, nil, 2) end
end

-- The one way the window sends: a press of the button `id` ("all", or "row:<group key>") over
-- `mails`, inside the player's click, which attaches and sends the first mail before it returns. A
-- press while a run goes is that run's Stop, but for ARM_HOLD from its start (a double click's second
-- click, which its button refuses then). A press this character cannot pay the postage of says so
-- and sends nothing. A press that would mail a name not yet trusted arms instead; a second press
-- inside ARM_HOLD does nothing (its button is disabled then, so in the client it never arrives), and
-- one after it, within ARM_SECONDS, trusts the name.
local function pressMails(id, mails)
  local machine = MA._Machine()
  if machine:IsRunning() then
    if MA._run and MA._run.held then return end
    machine:Stop("pressed")
    return paint()
  end
  if not mails or #mails == 0 then return end
  local postage, money = GC.MailGroups.POSTAGE * stacksOf(mails), ask(GetMoney)
  if type(money) == "number" and money < postage then
    MA._armed = nil
    MA._stopped = GC.L["Postage is %s and this character has %s."]:format(GC.Util.Money(postage), GC.Util.Money(money))
    return paint()
  end
  local full, to = untrusted(mails)
  if full then
    local armed = MA._armed
    if not (armed and armed.id == id and armed.full == full) then
      arm(id, full, to)
      return paint()
    end
    if armed.held then return end
    if not GC.MailGroups.Trust(GC.db, full) then MA._trustedHere[full] = true end
    full, to = untrusted(mails)
    if full then
      arm(id, full, to)
      return paint()
    end
  end
  MA._armed, MA._stopped = nil, nil
  openSendTab()
  local run = { id = id, mails = mails, plan = MA._reading.plan, done = {}, failed = {}, held = true }
  MA._run = run
  machine:Press(mails)
  if MA._run == run then
    C_Timer.After(MA.ARM_HOLD, function()
      if MA._run == run then
        run.held = nil
        paint()
      end
    end)
  end
  paint()
end

local function onSendAllClick()
  if not MA._reading then return end
  pressMails("all", MA._reading.plan.mails)
end

local function onRowSendClick(button)
  if not (MA._reading and button.key) then return end
  pressMails("row:" .. button.key, GC.MailGroups.MailsFor(MA._reading.plan, button.key))
end

-- ---------------------------------------------------------------------------------------------
-- The clicks that send nothing
-- ---------------------------------------------------------------------------------------------

-- The popups the window opened (a Keep's count, a typed name) go with it.
local function closePopups()
  if not GC.BuyCapEditor then return end
  for _, row in ipairs(MA._rows) do
    GC.BuyCapEditor.CloseFor(row.keep)
    GC.BuyCapEditor.CloseFor(row.to)
  end
end

-- Who sells the group `key` on this realm for this character's faction, `full` or nil to forget it;
-- the window reads again.
local function setRecipient(key, full)
  local me = MA._reading and MA._reading.me
  if not me then return end
  GC.MailGroups.SetRecipient(GC.db, me.realm, key, full, me.faction)
  MA._armed = nil
  MA.Refresh(true)
end

-- A name typed in the kit's popup: Name, or Name-Realm for a connected realm's character, in any
-- case (Core/Alts.lua's Full takes the client's spelling of the realm and the recorded one of a
-- character of the player's). A realm this character cannot mail (Core/Alts.lua's MailName) is
-- refused there, saying so, rather than saved and then ringed on its card as if no one were chosen;
-- so is a character recorded of the other faction (Core/Alts.lua's FactionOf), which no mail reaches.
local function askName(chip, row)
  if not GC.BuyCapEditor then return end
  GC.BuyCapEditor.Open(chip, {
    title = GC.L["Name or Name-Realm"] .. "\n"
      .. GC.L["A name that is not one of your characters is asked about once, before the first mail goes."],
    text = "",
    read = function(text)
      local me, connected = meNow(), connectedNow()
      local full = me and GC.Alts.Full(GC.db, (text or ""):match("^%s*(.-)%s*$"), me, connected)
      if not full then return nil end
      if full ~= me.full and not GC.Alts.MailName(full, me, connected) then
        return nil, GC.L["Mail goes only to a character on this realm or a connected one."]
      end
      local side = GC.Alts.FactionOf(GC.db, full)
      if side and me.faction and side ~= me.faction then
        return nil, GC.L["Mail goes only to a character of your faction."]
      end
      return full
    end,
    invalid = GC.L["Type a character name"],
    setLabel = GC.L["Save"],
    onCommit = function(full) setRecipient(row.key, full) end,
  })
end

-- A class's colour, as the game gives it (Blizzard_SharedXML's GetClassColor), or nil.
local function classColour(class)
  if type(class) ~= "string" or type(GetClassColor) ~= "function" then return nil end
  local ok, r, g, b = pcall(GetClassColor, class)
  if not (ok and type(r) == "number" and type(g) == "number" and type(b) == "number") then return nil end
  return { r, g, b }
end

-- The game's own icon for a class (Blizzard_SharedXML's GetClassAtlas), or nil.
local function classAtlas(class)
  if type(class) ~= "string" then return nil end
  local atlas = ask(GetClassAtlas, class)
  return type(atlas) == "string" and atlas or nil
end

-- A character in the menu: its class icon, its name in its class colour, and a grey note: the groups
-- that go to it already here, else when it was last seen.
local function altLine(alt, reading)
  local text = GC.Util.Colored(classColour(alt.class) or K.text1, alt.mailName)
  local atlas = classAtlas(alt.class)
  if atlas then text = ("|A:%s:14:14|a %s"):format(atlas, text) end
  local gets = {}
  for _, row in ipairs(reading.plan.rows) do
    if row.to == alt.full then gets[#gets + 1] = row.name end
  end
  local note = #gets > 0 and GC.L["gets %s"]:format(commasOf(gets)) or seenText(alt.seen)
  return text .. "  " .. GC.Util.Colored(K.text3, note)
end

-- Who sells a group, from its chip: the characters this one can mail, this character, a name typed
-- by hand, or nobody yet; saved for this realm. With none of the others known yet (each is recorded
-- as it logs in with GoldCap), a grey line says so.
local function fillMenu(root, chip, row)
  local reading = MA._reading
  root:CreateTitle(GC.Util.ClientText(GC.L["Who sells %s?"]:format(row.name)))
  if #reading.alts > 0 then
    root:CreateTitle(GC.Util.ClientText(GC.L["Your characters on this realm"]))
    for _, alt in ipairs(reading.alts) do
      root:CreateButton(GC.Util.ClientText(altLine(alt, reading)), function() setRecipient(row.key, alt.full) end)
    end
  else
    root:CreateTitle(GC.Util.ClientText(GC.Util.Colored(K.text3,
      GC.L["Your other characters show here once each has logged in with GoldCap."])))
  end
  root:CreateDivider()
  local me = reading.me
  if me then
    root:CreateButton(GC.Util.ClientText(GC.L["This character"]), function() setRecipient(row.key, me.full) end)
  end
  root:CreateButton(GC.Util.ClientText(GC.L["Type a name"]), function() askName(chip, row) end)
  root:CreateButton(GC.Util.ClientText(GC.L["Nobody yet"]), function() setRecipient(row.key, nil) end)
end

local function onRecipientClick(chip)
  local menu = _G.MenuUtil
  if not (chip.data and MA._reading and menu and menu.CreateContextMenu) then return end
  menu.CreateContextMenu(chip, function(_, root) fillMenu(root, chip, chip.data) end)
end

-- A card's Keep: the Hoard's popup and the same count, then the window reads again.
local function onKeepClick(button)
  GC.HoardRow.AskKeep(button, button.group, button.groupName, function() MA.Refresh(true) end)
end

local function onCloseClick()
  closePopups()
  setClosed(true)
  if MA.machine and MA.machine:IsRunning() then MA.machine:Stop("hidden") end
  MA.Refresh()
end

local function onHandleClick()
  setClosed(false)
  MA.Refresh(true)
end

-- An item icon's tooltip, beside the window: the item and how many, and why a stack that stays does.
local function showIconTip(hit)
  local tooltip, item = _G.GameTooltip, hit.item
  if not (tooltip and item) then return end
  GC.Theme.ItemTooltipOutside(hit, frame)
  tooltip:AddLine(GC.Util.ClientText(("%s ×%d"):format(U.itemName(item), item.count)), K.text1[1], K.text1[2], K.text1[3])
  local why = item.why == "bound" and GC.L["Bound to you: a mail cannot take it."]
    or item.why == "refund" and GC.L["Can still be refunded: a mail would end that, so it stays."] or nil
  if why then tooltip:AddLine(GC.Util.ClientText(why), K.text2[1], K.text2[2], K.text2[3], true) end
  tooltip:Show()
end

-- ---------------------------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------------------------

-- A Send: the kit's paper plane before its words, left-justified so paintSend can centre the two;
-- `look.height` tall.
local function sendButton(parent, variant, art, look)
  local b = GC.Theme.Button(parent, variant, art)
  b.look = look
  b:SetHeight(look.height)
  b.icon = b:CreateTexture(nil, "OVERLAY")
  b.icon:SetSize(M.BUTTON_ICON, M.BUTTON_ICON)
  b.text:SetJustifyH("LEFT")
  return b
end

-- The top card: the letter, the title, the line, a stop's words, the postage, Send all (its Stop
-- while a run goes) and the run's words, count and gold bar (the kit's, UI/Kit/Bar.lua).
local function buildTop()
  local T = GC.Theme
  local card = T.Card(frame, CARD_FILL, CARD_RING, true)
  card.letter = card:CreateTexture(nil, "ARTWORK")
  card.letter:SetTexture(LETTER_ICON)
  card.letter:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  card.letter:SetSize(M.LETTER, M.LETTER)
  card.letter:SetPoint("TOPLEFT", card, "TOPLEFT", M.CARD_PAD, -M.CARD_PAD)
  card.title = track(frame, wrapping(T.Label(card, 12)))
  colour(card.title, K.text1)
  card.line = track(frame, wrapping(T.Label(card, 10)))
  colour(card.line, K.text2)
  card.note = track(frame, wrapping(T.Label(card, 10)))
  colour(card.note, K.loss)
  card.postageLabel = track(frame, T.Heading(card, 8))
  card.postageLabel:SetWordWrap(false)
  card.postageLabel:SetJustifyH("RIGHT")
  colour(card.postageLabel, K.text3)
  card.postage = track(frame, T.Num(card, 11))
  card.postage:SetWordWrap(false)
  card.postage:SetJustifyH("RIGHT")
  colour(card.postage, K.goldText)
  card.send = sendButton(card, "primary", "plaque", { variant = "primary", iconColor = K.onGold, height = M.SEND_H })
  card.send:SetScript("OnClick", onSendAllClick)
  track(frame, card.send.text)
  card.cast = { label = track(frame, wrapping(T.Label(card, 9))), count = track(frame, T.Num(card, 9)),
    bar = T.Bar(card, M.FILL_H, K.gold) }
  colour(card.cast.label, K.goldText)
  colour(card.cast.count, K.text2)
  card.cast.count:SetWordWrap(false)
  frame.top = card
end

-- Who sells a group, on its card: a quiet chip with the character's class icon, its name in its
-- class colour and a down caret; its click opens the menu.
local function recipientChip(row)
  local T = GC.Theme
  local chip = U.plate(row, K.windowBorder, "badge")
  chip:SetHeight(M.CHIP_H)
  chip.bg = T.SlicedTexture(chip, "BACKGROUND", T.MEDIA .. "badge.png", K.glassTop, T.SLICE.badge)
  chip.bg:SetAllPoints()
  chip.icon = chip:CreateTexture(nil, "ARTWORK")
  chip.icon:SetSize(M.CLASS, M.CLASS)
  chip.text = track(row, T.Label(chip, 10))
  chip.text:SetWordWrap(false)
  chip.chevron = chip:CreateTexture(nil, "ARTWORK")
  chip.chevron:SetSize(M.CHEVRON, M.CHEVRON)
  T.SetIcon(chip.chevron, "caretDown", K.text3)
  chip:SetScript("OnClick", onRecipientClick)
  return chip
end

-- An item icon on a card, as a Hoard row draws one (with its count), and over it a lock for a stack
-- that stays and the room its tooltip answers to.
local function newIcon(row)
  local slot = HF.Row.NewIcon(row, M.ICON, true)
  slot.lock = row:CreateTexture(nil, "OVERLAY", nil, 2)
  slot.lock:SetTexture(LOCK_ICON)
  slot.lock:SetTexCoord(0, LOCK_EDGE, 0, LOCK_EDGE)
  slot.lock:SetSize(M.LOCK, M.LOCK)
  slot.lock:SetPoint("CENTER", slot.edge, "CENTER", 0, 0)
  slot.lock:Hide()
  slot.hit = CreateFrame("Frame", nil, row)
  slot.hit:SetAllPoints(slot.edge)
  slot.hit:EnableMouse(true)
  slot.hit:SetScript("OnEnter", showIconTip)
  slot.hit:SetScript("OnLeave", U.hideTip)
  slot.hit:Hide()
  return slot
end

-- A group's card, in the scroll.
local function newRow()
  local T = GC.Theme
  local row = CreateFrame("Frame", nil, frame.content)
  row.bg = T.SlicedTexture(row, "BACKGROUND", T.MEDIA .. "plaque.png", K.glassBottom, T.SLICE.plaque)
  row.bg:SetAllPoints()
  row.ring = T.SlicedTexture(row, "BORDER", T.MEDIA .. "plaque_ring.png", K.hairline, T.SLICE.plaque)
  row.ring:SetAllPoints()
  row.name = track(row, wrapping(T.Label(row, 11)))
  colour(row.name, K.text1)
  row.chip = T.Chip(row)
  row.chip:SetHeight(L.CHIP_H)
  track(row, row.chip.text)
  row.keep = HF.Row.KeepChip(row, onKeepClick)
  row.to = recipientChip(row)
  row.icons = {}
  row.more = track(row, T.Num(row, 9))
  row.more:SetWordWrap(false)
  colour(row.more, K.text2)
  row.line = track(row, wrapping(T.Label(row, 10)))
  colour(row.line, K.text3)
  row.send = sendButton(row, "active", "badge",
    { variant = "active", ring = SEND_RING, iconColor = K.goldText, height = M.BUTTON_H })
  row.send:SetScript("OnClick", onRowSendClick)
  track(row, row.send.text)
  row.status = track(row, T.Heading(row, 10))
  row.status:SetWordWrap(false)
  for _, b in ipairs({ row.keep, row.to, row.send }) do b:SetFrameLevel(row:GetFrameLevel() + 3) end
  return row
end

-- The window: its glass, the Hoard's header ("Send to alts" beside the brand, and the X), the top
-- card, the section's heading, the kit's scroll whose child holds the cards, and the footer.
local function build()
  local T = GC.Theme
  frame = CreateFrame("Frame", nil, UIParent)
  frame:SetSize(L.WIDTH, L.MIN_H)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame.glass = T.Window(frame)
  U.newHeader(frame, onCloseClick)
  buildTop()
  frame.section = track(frame, wrapping(T.Heading(frame, 9)))
  colour(frame.section, K.text3)
  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  if T.QuietScrollBar then T.QuietScrollBar(scroll) end
  scroll.scrollBarHideable = true
  if scroll.ScrollBar then scroll.ScrollBar:Hide() end
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(L.WIDTH - 2 * L.PAD - L.GUTTER, 1)
  scroll:SetScrollChild(content)
  frame.scroll, frame.content = scroll, content
  frame.footer = track(frame, wrapping(T.Label(frame, 9)))
  colour(frame.footer, K.text3)
  -- A frame made from Lua starts shown: hidden until a paint shows it, so its first show is a re-show
  -- like any other (restamp).
  frame:Hide()
  MA._frame = frame
end

-- ---------------------------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------------------------

-- Blizzard's open letter (Blizzard_MailFrame's OpenMailFrame, a UIChildWindow anchored at the
-- inbox's right edge) while it shows: it opens on the very spot beside the mail frame.
local function letterShown()
  local letter = _G.OpenMailFrame
  if type(letter) == "table" and letter.IsVisible and letter:IsVisible() then return letter end
  return nil
end

-- Beside Blizzard's mail frame, or past its open letter while that shows, its top level with that
-- frame's; with no mail frame, at the screen's left. Answers the frame it stands beside, or nil.
local function place(widget)
  widget:ClearAllPoints()
  local beside = letterShown() or MailFrame
  if type(beside) == "table" then
    widget:SetPoint("TOPLEFT", beside, "TOPRIGHT", L.X, 0)
    return beside
  end
  widget:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
  return nil
end

-- A Send's look and words: "send", its own look with the paper plane; "armed", the loud look and its
-- question alone; "stop", the Hoard's Stop. As wide as `width`, or as its words need with nil; the
-- glyph and the words centred together. Words wider than the button (an ask in a long language, for
-- a name on a connected realm) wrap inside it, centred, and it grows to hold them: never cut.
-- Answers its width and height.
local function paintSend(button, mode, label, width)
  local look = button.look
  if mode == "stop" then
    button:SetVariant("stop")
    button:SetRing(STOP_RING)
  elseif mode == "armed" then
    button:SetVariant("danger")
    button:SetRing(nil)
  else
    button:SetVariant(look.variant)
    button:SetRing(look.ring)
  end
  local glyph = mode == "send"
  button.icon:SetShown(glyph)
  if glyph then GC.Theme.SetIcon(button.icon, "send", look.iconColor) end
  button:SetLabel(label)
  local text = button.text
  local textW = math.ceil(text:GetUnboundedStringWidth() or 0)
  local iconRoom = glyph and (M.BUTTON_ICON + 4) or 0
  width = width or math.max(mode == "stop" and M.STOP_MIN or 0, M.BUTTON_PAD + iconRoom + textW + M.BUTTON_PAD)
  button:SetWidth(width)
  local room = width - 2 * M.BUTTON_PAD - iconRoom
  local wraps = textW > room
  local x = wraps and M.BUTTON_PAD or math.max(M.BUTTON_PAD, math.floor((width - iconRoom - textW) / 2))
  if glyph then
    button.icon:ClearAllPoints()
    button.icon:SetPoint("LEFT", button, "LEFT", x, 0)
  end
  -- After SetLabel, which bounds the words by the button's own edges again.
  text:ClearAllPoints()
  text:SetWordWrap(wraps)
  text:SetMaxLines(wraps and 0 or 1)
  local height = look.height
  if wraps then
    text:SetJustifyH("CENTER")
    text:SetWidth(room)
    text:SetPoint("LEFT", button, "LEFT", x + iconRoom, 0)
    height = math.max(height, math.ceil(heightOf(text, look.height)) + 2 * M.WRAP_PAD)
  else
    text:SetJustifyH("LEFT")
    text:SetWidth(0)
    text:SetPoint("LEFT", button, "LEFT", x + iconRoom, 0)
    text:SetPoint("RIGHT", button, "RIGHT", -M.BUTTON_PAD, 0)
  end
  button:SetHeight(height)
  return width, height
end

-- A Send live or refusing presses. paintSend's SetVariant has just painted it live, and the kit
-- dims a button in its OnDisable, so one already disabled is enabled and disabled again to dim it.
local function setEnabled(button, on)
  if on then return button:Enable() end
  if not button:IsEnabled() then button:Enable() end
  button:Disable()
end

-- The run's words, count and gold bar left of Stop, `width` wide at `x`, `y` in the card. Answers
-- their height.
local function paintCast(card, run, names, x, y, width)
  local cast = card.cast
  local done = 0
  for _ in pairs(run.done) do done = done + 1 end
  setText(cast.count, GC.L["%d sent"]:format(done))
  local countW = math.ceil(cast.count:GetStringWidth() or 0)
  local mail = run.shown
  cast.label:SetWidth(math.max(1, width - countW - M.CAST_GAP))
  setText(cast.label, mail and GC.L["Mail %d of %d: %s to %s"]:format(run.index, run.total,
    listOf(groupNames(mail.keys, names)), mail.to) or "")
  cast.label:ClearAllPoints()
  cast.label:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
  cast.count:ClearAllPoints()
  cast.count:SetPoint("TOPRIGHT", card, "TOPLEFT", x + width, -y)
  local labelH = math.ceil(heightOf(cast.label, 11))
  local total = run.total or #run.mails
  cast.bar:ClearAllPoints()
  cast.bar:SetPoint("TOPLEFT", card, "TOPLEFT", x, -(y + labelH + 2))
  cast.bar:SetWidth(width)
  cast.bar:SetShare(total > 0 and math.min(done, total) / total or 0)
  for _, part in ipairs({ cast.label, cast.count, cast.bar }) do part:Show() end
  return labelH + 2 + M.FILL_H
end

local function hideCast(card)
  for _, part in ipairs({ card.cast.label, card.cast.count, card.cast.bar }) do part:Hide() end
end

-- The top card, `width` wide: the title, the line and a stop's words beside the letter, the postage
-- at the right, then Send all; or, while a run goes, the run's words and bar beside Stop. Answers
-- its height.
local function paintTop(reading, width)
  local card, run = frame.top, MA._run
  local plan = run and run.plan or reading.plan
  local mails = run and run.mails or plan.mails
  local names = namesOf(plan)
  local any = #mails > 0
  local textX = M.CARD_PAD + M.LETTER + M.LETTER_GAP
  local postW = 0
  card.postageLabel:SetShown(any)
  card.postage:SetShown(any)
  if any then
    setText(card.postageLabel, GC.Util.Upper(GC.L["Postage"]))
    setText(card.postage, GC.Util.Money(GC.MailGroups.POSTAGE * stacksOf(mails)))
    postW = math.ceil(math.max(card.postageLabel:GetStringWidth() or 0, card.postage:GetStringWidth() or 0))
    card.postageLabel:ClearAllPoints()
    card.postageLabel:SetPoint("TOPRIGHT", card, "TOPLEFT", width - M.CARD_PAD, -M.CARD_PAD)
    card.postage:ClearAllPoints()
    card.postage:SetPoint("TOPRIGHT", card, "TOPLEFT", width - M.CARD_PAD,
      -(M.CARD_PAD + math.ceil(heightOf(card.postageLabel, 10)) + 2))
  end
  local textW = math.max(1, width - textX - M.CARD_PAD - (any and (postW + M.POSTAGE_GAP) or 0))
  local title, line
  if run then
    title = #mails == 1 and GC.L["Sending 1 mail"] or GC.L["Sending %d mails"]:format(#mails)
    line = runLine(run, names)
  elseif any then
    title, line = mailsTitle(mails), plannedLine(mails, names)
  else
    title, line = GC.L["Nothing to send now"], whyNothing(reading)
  end
  local y = M.CARD_PAD
  for _, part in ipairs({ { card.title, title }, { card.line, line } }) do
    local fs = part[1]
    fs:SetWidth(textW)
    setText(fs, part[2])
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", textX, -y)
    y = y + math.ceil(heightOf(fs, 12)) + M.LINE_GAP
  end
  y = y - M.LINE_GAP
  local note = not run and MA._stopped or nil
  card.note:SetShown(note ~= nil)
  if note then
    y = y + M.NOTE_GAP
    card.note:SetWidth(textW)
    setText(card.note, note)
    card.note:ClearAllPoints()
    card.note:SetPoint("TOPLEFT", card, "TOPLEFT", textX, -y)
    y = y + math.ceil(heightOf(card.note, 12))
  end
  y = math.max(y, M.CARD_PAD + M.LETTER)
  local button, inner = card.send, width - 2 * M.CARD_PAD
  if run then
    y = y + M.BUTTON_GAP
    local stopW = paintSend(button, "stop", GC.L["Stop"])
    setEnabled(button, not run.held)
    local castH = paintCast(card, run, names, M.CARD_PAD, y, inner - stopW - M.CAST_GAP)
    local rowH = math.max(M.SEND_H, castH)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", card, "TOPLEFT", width - M.CARD_PAD, -(y + math.floor((rowH - M.SEND_H) / 2)))
    button:Show()
    y = y + rowH
  elseif any then
    y = y + M.BUTTON_GAP
    hideCast(card)
    local armed = MA._armed and MA._armed.id == "all" and MA._armed or nil
    local _, buttonH
    if armed then
      _, buttonH = paintSend(button, "armed", GC.L["Send to %s? Press again"]:format(armed.to), inner)
    else
      _, buttonH = paintSend(button, "send", GC.L["Send all"], inner)
    end
    setEnabled(button, not (armed and armed.held))
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", card, "TOPLEFT", M.CARD_PAD, -y)
    button:Show()
    y = y + buttonH
  else
    hideCast(card)
    button:Hide()
  end
  -- Its words and Stop trading places with Send all: redrawn whole.
  if (run ~= nil) ~= (card.ran == true) then restamp(frame) end
  card.ran = run ~= nil
  return y + M.CARD_PAD
end

-- The play of a group, from its first item (Core/GroupRules.lua's rule).
local function playOf(row)
  local first = row.items[1] or row.stays[1]
  local rule = first and GC.GroupRules.RuleFor(first.itemID)
  return rule and rule.play or nil
end

-- Who sells a group, on its chip: "This character", the character in its class colour with its class
-- icon, or "Who sells it?" ringed in gold (a name this character cannot mail is ringed so too).
-- Answers its width.
local function paintRecipient(chip, row, reading)
  chip.data = row
  local me = reading.me
  local text, c, atlas, ring
  if row.to and me and row.to == me.full then
    text, c, ring = GC.L["This character"], K.text2, K.windowBorder
  elseif row.to then
    local class = reading.classOf[row.to]
    text, c, atlas = row.mailName or row.to, classColour(class) or K.text1, classAtlas(class)
    ring = row.state == "pick" and PICK_RING or K.windowBorder
  else
    text, c, ring = GC.L["Who sells it?"], K.goldText, PICK_RING
  end
  chip.ring:SetVertexColor(ring[1], ring[2], ring[3], ring[4] or 1)
  setText(chip.text, text)
  colour(chip.text, c)
  local x = M.CHIP_PAD
  chip.icon:SetShown(atlas ~= nil)
  if atlas then
    chip.icon:SetAtlas(atlas)
    chip.icon:ClearAllPoints()
    chip.icon:SetPoint("LEFT", chip, "LEFT", x, 0)
    x = x + M.CLASS + 4
  end
  chip.text:ClearAllPoints()
  chip.text:SetPoint("LEFT", chip, "LEFT", x, 0)
  x = x + math.ceil(chip.text:GetStringWidth() or 0) + 4
  chip.chevron:ClearAllPoints()
  chip.chevron:SetPoint("LEFT", chip, "LEFT", x, 0)
  x = x + M.CHEVRON + M.CHIP_PAD
  chip:SetWidth(x)
  return x
end

-- A card's line: how many stacks go, or why none do.
local function lineOf(row)
  if row.state == "send" then
    return #row.send == 1 and GC.L["1 stack"] or GC.L["%d stacks"]:format(#row.send)
  end
  if row.state == "pick" then return GC.L["Choose who it goes to, once. GoldCap remembers."] end
  if row.state == "self" then return GC.L["This character sells them, so they stay."] end
  return GC.L["Nothing to send beyond what it keeps."]
end

-- A card's right end on its second line: its Send (disabled while another run goes), or the run's
-- word for it (Sent in green, Sending in gold, Next in grey). Its Send armed for a typed name stands
-- on a line of its own under the icons instead, `inner` wide. Answers its width, its height and
-- whether it stands on that line of its own.
local function paintAction(row, data, status, inner)
  if status then
    row.send:Hide()
    local word, c = GC.L["Next"], K.text3
    if status == "sent" then word, c = GC.L["Sent"], K.profit end
    if status == "sending" then word, c = GC.L["Sending"], K.goldText end
    setText(row.status, word)
    colour(row.status, c)
    row.status:Show()
    return math.ceil(row.status:GetStringWidth() or 0), 0, false
  end
  row.status:Hide()
  if data.state ~= "send" then
    row.send:Hide()
    return 0, 0, false
  end
  local armed = MA._armed and MA._armed.id == "row:" .. data.key and MA._armed or nil
  row.send.key = data.key
  local width, height
  if armed then
    width, height = paintSend(row.send, "armed", GC.L["Send to %s? Press again"]:format(armed.to), inner)
  else
    width, height = paintSend(row.send, "send", GC.L["Send"])
  end
  setEnabled(row.send, not (MA._run or (armed and armed.held)))
  row.send:Show()
  return width, height, armed ~= nil
end

-- The icons of a card: what goes (checked once it has gone, `sent`), then what stays, each with its
-- reason.
local function iconEntries(data, sent)
  local entries = {}
  for _, item in ipairs(data.items) do
    entries[#entries + 1] = { itemID = item.itemID, name = item.name, count = item.count, mark = sent and "moved" or nil }
  end
  for _, entry in ipairs(data.stays) do
    entries[#entries + 1] = { itemID = entry.itemID, name = entry.name, count = entry.count, why = entry.why }
  end
  return entries
end

-- The top line of a card: the name and the play beside Keep and who sells it, or Keep and who sells
-- it on a line of their own where the name would have too little room beside them (and the play under
-- the name where it would have too little beside its chip). Answers its height.
local function paintHead(row, data, reading, width)
  local x, inner = M.ROW_PAD, width - 2 * M.ROW_PAD
  local keep = row.keep
  keep.group, keep.groupName = data.key, data.name
  HF.Row.FitKeep(keep, GC.L["Keep %d"]:format(GC.BankGroups.KeepFor(GC.db, data.key)))
  keep:SetShown(GC.BankGroups.Writable(GC.db))
  local keepW = keep:IsShown() and keep:GetWidth() or 0
  local toW = paintRecipient(row.to, data, reading)
  local rightW = toW + (keepW > 0 and (keepW + M.CHIP_GAP) or 0)
  local play = playOf(data)
  local label = HF.Row.PlayLabel(play)
  local chipW = 0
  if label then
    row.chip:SetLabel(GC.Util.Upper(label), HF.Row.PLAY_COLOR[play])
    chipW = math.ceil(row.chip.text:GetUnboundedStringWidth() or 0) + 10
    row.chip:SetWidth(chipW)
    row.chip:Show()
  else
    row.chip:Hide()
  end
  local chipRoom = chipW > 0 and (chipW + L.CHIP_GAP) or 0
  local room = inner - rightW - M.COL_GAP
  local blockBelow = room < M.NAME_MIN + chipRoom
  if blockBelow then room = inner end
  local nameMax = room - chipRoom
  local playBelow = chipW > 0 and nameMax < M.NAME_MIN
  if playBelow then nameMax = room end
  setText(row.name, data.name)
  local nameW = math.max(1, math.min(math.ceil(row.name:GetUnboundedStringWidth() or 0) + 1, nameMax))
  row.name:SetWidth(nameW)
  setText(row.name, data.name)
  local nameH = math.ceil(heightOf(row.name, 13))
  local firstLine = math.min(nameH, 14)
  local leftH = nameH
  if chipW > 0 then leftH = playBelow and (nameH + 2 + L.CHIP_H) or math.max(nameH, L.CHIP_H) end
  local y = M.ROW_PAD
  row.name:ClearAllPoints()
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
  if chipW > 0 then
    row.chip:ClearAllPoints()
    if playBelow then
      row.chip:SetPoint("TOPLEFT", row, "TOPLEFT", x, -(y + nameH + 2))
    else
      row.chip:SetPoint("TOPLEFT", row, "TOPLEFT", x + nameW + L.CHIP_GAP,
        -(y + math.max(0, math.floor((firstLine - L.CHIP_H) / 2))))
    end
  end
  local blockY = blockBelow and (y + leftH + M.BLOCK_GAP) or (y + math.max(0, math.floor((firstLine - M.CHIP_H) / 2)))
  row.to:ClearAllPoints()
  row.to:SetPoint("TOPRIGHT", row, "TOPLEFT", width - M.ROW_PAD, -blockY)
  if keepW > 0 then
    keep:ClearAllPoints()
    keep:SetPoint("TOPRIGHT", row, "TOPLEFT", width - M.ROW_PAD - toW - M.CHIP_GAP,
      -(blockY + math.floor((M.CHIP_H - L.KEEP_H) / 2)))
  end
  return blockBelow and (leftH + M.BLOCK_GAP + M.CHIP_H) or math.max(leftH, M.CHIP_H)
end

-- One card, `width` wide, for `view` ({ row, status }): its top line (paintHead), then the icons of
-- what goes and what stays ("+N" for the rest), the line, and the Send or the run's word at the
-- right. A Send armed for a typed name takes a line of its own under the icons, as wide as the card,
-- the line and the "+N" hidden while it asks: its question is long, and never covers the icons nor
-- squeezes the line. Answers its height.
local function paintRow(row, view, reading, width)
  local data, status = view.row, view.status
  row.data = data
  local x = M.ROW_PAD
  local lineY = M.ROW_PAD + paintHead(row, data, reading, width) + M.LINE_TOP
  local entries = iconEntries(data, status == "sent")
  local n = math.min(#entries, M.ICONS)
  local actionW, actionH, below = paintAction(row, data, status, width - 2 * M.ROW_PAD)
  local besideW = below and 0 or actionW
  local moreW = 0
  if #entries > n and not below then
    setText(row.more, "+" .. (#entries - n))
    moreW = math.ceil(row.more:GetStringWidth() or 0) + M.ICON_GAP
    row.more:Show()
  else
    row.more:Hide()
  end
  local iconsW = n * M.ICON + math.max(0, n - 1) * M.ICON_GAP
  local lineX = x + iconsW + moreW + (n > 0 and M.COL_GAP or 0)
  local lineH = 0
  row.line:SetShown(not below)
  if not below then
    row.line:SetWidth(math.max(1, width - M.ROW_PAD - besideW - (besideW > 0 and M.COL_GAP or 0) - lineX))
    setText(row.line, lineOf(data))
    lineH = math.ceil(heightOf(row.line, 12))
  end
  local bottomH = math.max(n > 0 and M.ICON or 0, besideW > 0 and M.BUTTON_H or 0, lineH)
  for i = 1, math.max(n, #row.icons) do
    local slot, entry = row.icons[i], i <= n and entries[i] or nil
    if entry then
      slot = slot or newIcon(row)
      row.icons[i] = slot
      slot.edge:ClearAllPoints()
      slot.edge:SetPoint("TOPLEFT", row, "TOPLEFT", x + (i - 1) * (M.ICON + M.ICON_GAP),
        -(lineY + math.floor((bottomH - M.ICON) / 2)))
      HF.Row.PaintIcon(slot, entry.itemID, reading.icons[entry.itemID], entry.count, entry.mark)
      if entry.why then slot.shade:Show() end
      slot.lock:SetShown(entry.why ~= nil)
      slot.hit.item = entry
      slot.hit:Show()
    elseif slot then
      HF.Row.HideIcon(slot)
      slot.lock:Hide()
      slot.hit.item = nil
      slot.hit:Hide()
    end
  end
  if moreW > 0 then
    row.more:ClearAllPoints()
    row.more:SetPoint("LEFT", row, "TOPLEFT", x + iconsW + M.ICON_GAP, -(lineY + bottomH / 2))
  end
  if not below then
    row.line:ClearAllPoints()
    row.line:SetPoint("TOPLEFT", row, "TOPLEFT", lineX, -(lineY + math.floor((bottomH - lineH) / 2)))
  end
  local mid = -(lineY + bottomH / 2)
  local height = lineY + bottomH + M.ROW_PAD
  if status then
    row.status:ClearAllPoints()
    row.status:SetPoint("RIGHT", row, "TOPLEFT", width - M.ROW_PAD, mid)
  elseif below then
    local y = lineY + bottomH + (bottomH > 0 and M.LINE_TOP or 0)
    row.send:ClearAllPoints()
    row.send:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    height = y + actionH + M.ROW_PAD
  elseif row.send:IsShown() then
    row.send:ClearAllPoints()
    row.send:SetPoint("RIGHT", row, "TOPLEFT", width - M.ROW_PAD, mid)
  end
  -- The line and the "+N" back after the ask, or gone for it: redrawn whole.
  if below ~= (row.below == true) then restamp(row) end
  row.below = below
  -- Its glass: gold while a mail of it is in flight; a group this character sells, faded.
  local fill, ring = K.glassBottom, K.hairline
  if status == "sending" then fill, ring = RUN_FILL, RUN_RING end
  row.bg:SetVertexColor(fill[1], fill[2], fill[3], fill[4])
  row.ring:SetVertexColor(ring[1], ring[2], ring[3], ring[4])
  row:SetAlpha(data.state == "self" and not status and SELF_ALPHA or 1)
  row:SetHeight(height)
  return height
end

local function byName(a, b)
  if a.row.name ~= b.row.name then return a.row.name < b.row.name end
  return a.row.key < b.row.key
end

-- The cards to paint: while a run goes, the plan it was pressed with and how each group stands in
-- the run; else the plan read now, a group a run of this visit sent in full saying Sent while nothing
-- more of it is to send.
local function viewRows(reading)
  local out, run = {}, MA._run
  if run then
    for _, row in ipairs(run.plan.rows) do out[#out + 1] = { row = row, status = runStatus(run, row.key) } end
    return out
  end
  local here = {}
  for _, row in ipairs(reading.plan.rows) do
    here[row.key] = true
    local sent = MA._sent[row.key]
    if sent and row.state == "nothing" then
      out[#out + 1] = { row = sent, status = "sent" }
    else
      out[#out + 1] = { row = row }
    end
  end
  for key, row in pairs(MA._sent) do
    if not here[key] then out[#out + 1] = { row = row, status = "sent" } end
  end
  table.sort(out, byName)
  return out
end

-- The window, top to bottom: the header; the top card; with any card, the section's heading, the
-- cards in the scroll and the footer at the window's foot; clamped to the screen and never taller
-- than the room under the mail frame's top, but never so low that the scroll shows fewer than
-- ROWS_MIN cards' room (or all there is).
paint = function()
  local reading = MA._reading
  if not (frame and reading) then return end
  local beside = place(frame)
  local width = L.WIDTH
  local head, inner = width - 2 * L.PAD, width - 2 * L.PAD - L.GUTTER
  frame:SetWidth(width)
  setText(frame.brand, "GoldCap")
  setText(frame.title, GC.L["Send to alts"])
  frame.close:ClearAllPoints()
  frame.close:SetPoint("TOPRIGHT", frame, "TOPLEFT", L.PAD + head, -(L.PAD + (L.HEAD_H - L.CLOSE) / 2))
  local y = L.PAD + L.HEAD_H + M.SECTION_GAP
  local cardH = paintTop(reading, head)
  frame.top:ClearAllPoints()
  frame.top:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -y)
  frame.top:SetSize(head, cardH)
  y = y + cardH

  local views = viewRows(reading)
  local any = #views > 0
  for _, part in ipairs({ frame.section, frame.scroll, frame.footer }) do part:SetShown(any) end
  local cy = 0
  for i, view in ipairs(views) do
    local row = MA._rows[i] or newRow()
    MA._rows[i] = row
    local wasUp = row:IsShown()
    row:SetWidth(inner)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -cy)
    row:Show()
    cy = cy + paintRow(row, view, reading, inner) + M.ROW_GAP
    if not wasUp and frame:IsShown() then restamp(row) end
  end
  for i = #views + 1, #MA._rows do MA._rows[i]:Hide() end
  if not any then
    frame:SetHeight(y + L.PAD)
    return
  end
  cy = math.max(1, cy - M.ROW_GAP)
  y = y + M.SECTION_GAP
  frame.section:SetWidth(head)
  setText(frame.section, GC.Util.Upper(GC.L["Your groups in your bags"]))
  frame.section:ClearAllPoints()
  frame.section:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -y)
  y = y + math.ceil(heightOf(frame.section, 11)) + M.HEADING_GAP
  frame.footer:SetWidth(head)
  setText(frame.footer, GC.L["Gold is never sent, and what a group keeps stays in your bags. Soulbound items stay too. Each mail holds up to 12 stacks, so a big group goes in a few mails."])
  local footH = math.ceil(heightOf(frame.footer, 12))
  frame.footer:ClearAllPoints()
  frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", L.PAD, L.PAD)
  local foot = L.PAD + footH + M.SECTION_GAP
  frame.content:SetSize(inner, cy)
  local least = y + math.min(cy, M.ROWS_MIN * M.ROW_LEAST) + foot
  local height = math.min(y + cy + foot, math.max(least, U.maxHeight(beside)))
  frame:SetHeight(height)
  frame.scroll:ClearAllPoints()
  frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", L.PAD, -y)
  frame.scroll:SetSize(inner, math.max(1, height - y - foot))
end

local function hideAll()
  if frame then frame:Hide() end
  if handle then handle:Hide() end
end

-- Closed: the handle at the mail frame's right edge instead.
local function showHandle()
  if frame then frame:Hide() end
  if not handle then
    handle = U.newHandle(onHandleClick)
    MA._handle = handle
  end
  local wasUp = handle:IsShown()
  place(handle)
  U.paintHandle(handle, GC.L["Send to alts"])
  handle:Show()
  if not wasUp then restamp(handle) end
end

--- Paints the window, or its handle while the player has it closed, or hides both with the mailbox
--- closed (mailboxOpen: the client is asked too, except with `atShow`, MAIL_SHOW's own paint). With
--- `again`, or with nothing read yet in this visit, it reads the bags first (readBags); else it
--- paints from what it last read.
function MA.Refresh(again, atShow)
  -- At MAIL_SHOW the mailbox is opening: the client's interaction state is not asked then.
  if not (atShow and MA._open) and not mailboxOpen() then return hideAll() end
  if closedNow() then return showHandle() end
  if again or not MA._reading then MA._reading = readBags() end
  if not frame then build() end
  local wasUp = frame:IsShown()
  paint()
  if handle then handle:Hide() end
  frame:Show()
  if wasUp then return end
  restamp(frame)
  for _, row in ipairs(MA._rows) do
    if row:IsShown() then restamp(row) end
  end
end

-- A new visit: what the last one sent, stopped and asked about is forgotten, and a run left over
-- from it (a mailbox that closed with no MAIL_CLOSED) goes without a word.
local function newVisit()
  if MA.machine and MA.machine:IsRunning() then MA.machine:Stop("closed") end
  MA._run, MA._sent, MA._stopped, MA._armed, MA._reading = nil, {}, nil, nil, nil
end

-- BAG_UPDATE_DELAYED: the window reads and paints once on the next frame, never inside the client's
-- event; only while the mailbox is open, which Refresh asks the client too (a mailbox gone with no
-- MAIL_CLOSED hides the window there instead).
local function onBagsChanged()
  if not MA._open or MA._queued then return end
  if not (C_Timer and C_Timer.After) then return MA.Refresh(true) end
  MA._queued = true
  C_Timer.After(0, function()
    MA._queued = nil
    MA.Refresh(true)
  end)
end

-- The end of a visit, at MAIL_CLOSED or the mail frame's own hide: a run stops, the popups the window
-- opened close, and the window and its handle go.
local function endVisit()
  MA._open = false
  if MA.machine then MA.machine:OnClosed() end
  closePopups()
  hideAll()
end

-- The open letter's own show and hide move the window and its handle (place). Hooked at the first
-- visit rather than at load, as the mail frame's code may load after this file; a post-hook on a
-- frame nothing protected goes through, and the window only paints.
local letterHooked
local function hookLetter()
  local letter = _G.OpenMailFrame
  if letter == letterHooked or type(letter) ~= "table" or type(letter.HookScript) ~= "function" then return end
  letterHooked = letter
  local function moved()
    if MA._open then MA.Refresh() end
  end
  pcall(letter.HookScript, letter, "OnShow", moved)
  pcall(letter.HookScript, letter, "OnHide", moved)
end

-- The mail frame's own hide ends the visit as MAIL_CLOSED does: Blizzard's OnHide for it calls
-- CloseMail (Blizzard_MailFrame's MailFrame.xml), and walking from the mailbox straight to an
-- auctioneer can close the mailbox with no MAIL_CLOSED (in game 2026-09-23, UI/CraftQueueView.lua's
-- mailboxOpen), which left the window standing over the auction house. Hooked at the first visit,
-- as the open letter is.
local mailHooked
local function hookMailFrame()
  local mail = _G.MailFrame
  if mail == mailHooked or type(mail) ~= "table" or type(mail.HookScript) ~= "function" then return end
  mailHooked = mail
  pcall(mail.HookScript, mail, "OnHide", function()
    if MA._open then endVisit() end
  end)
end

--- The window's events, as its own event frame below hears them. MAIL_SHOW: this character is
--- remembered (Core/Alts.lua's OnEvent, which keeps its `seen` fresh) and a visit starts.
--- MAIL_CLOSED: the visit ends (endVisit, as at the mail frame's hide). MAIL_SEND_SUCCESS and
--- MAIL_FAILED: the server's answer to the mail in flight, for the press machine; a refused one marks
--- its character's groups out of the run. BAG_UPDATE_DELAYED: a paint on the next frame.
function MA.OnEvent(event)
  if event == "MAIL_SHOW" then
    if not GC.db then return end
    if GC.Alts and GC.Alts.OnEvent then GC.Alts.OnEvent() end
    newVisit()
    MA._open = true
    hookLetter()
    hookMailFrame()
    MA.Refresh(true, true)
  elseif event == "MAIL_CLOSED" then
    endVisit()
  elseif event == "MAIL_SEND_SUCCESS" then
    local run = MA._run
    if run and run.current then
      run.done[run.current] = true
      run.current = nil
    end
    if MA.machine then MA.machine:OnSendResult(true) end
    if MA._run and frame and frame:IsShown() then paint() end
  elseif event == "MAIL_FAILED" then
    local run = MA._run
    if run and run.current then
      run.failed[run.current.to] = true
      run.current = nil
    end
    if MA.machine then MA.machine:OnSendResult(false) end
    if MA._run and frame and frame:IsShown() then paint() end
  elseif event == "BAG_UPDATE_DELAYED" then
    onBagsChanged()
  end
end

if type(CreateFrame) == "function" then
  local events = CreateFrame("Frame")
  for _, name in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "BAG_UPDATE_DELAYED" }) do
    pcall(events.RegisterEvent, events, name)
  end
  events:SetScript("OnEvent", function(_, event) MA.OnEvent(event) end)
  MA._events = events
end
