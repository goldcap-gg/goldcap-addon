local _, GC = ...

-- Send to alts (retail only): at a mailbox, what goes in which mail to which alt, for each followed
-- group with items in the bags. Pure: the stacks come from UI/BankRoute.lua's reader, the group of
-- an item from Core/GroupRules.lua, and who the group's alt is and whether this character can mail
-- them from Core/Alts.lua, all handed in by the Send to alts window, which also makes every mail call. GoldCap_Camelot.toc does not load this file.
--
-- What a group sends is what GC.BankGroups.Plan puts in its `toBank` list: the stacks that leave
-- the bags while the bags still keep the group's keep count of each item (the same "Keep N" as the
-- GoldCap Hoard), the biggest stack first, a stack a press has already sent (`moving`) or the game
-- holds (`locked`) left out. A stack the mail must not take (`stays`: bound, Warbound until
-- equipped, or still refundable, see StaysWhy) is kept and named with why, never attached.
--
-- A mail carries at most MAX_ATTACH stacks. The mails of one alt are cut from all their groups'
-- stacks in row order, each starting where the last stopped, so a big group spans mails and two
-- small groups share one. Postage is POSTAGE copper a stack (measured on retail 12.1.5,
-- 2026-10-26: 1 stack 30, 3 stacks 90).
--
-- The alt of a group is saved in GC.db.mailTo = { v = 1, byFaction = { [home realm] = { [faction] =
-- { [group key] = "Name-Realm" } } }, realms = { [home realm] = { [group key] = "Name-Realm" } },
-- trusted = { ["Name-Realm"] = true } }: one alt a group per home realm (a group is sold on one
-- realm) and faction (characters of opposite factions cannot mail each other: the code review,
-- 2026-10-27), and the alts the player has confirmed once. `realms` is the older save, from before
-- the faction counted: written now only for a sender whose faction is not known, and read for a
-- sender only when its recipient is recorded of the sender's faction (Core/Alts.lua's FactionOf).
-- A recipient recorded of the other faction never counts, wherever it is saved. `byFaction` is a
-- table of its own, not a level inside `realms`, since a group's key can be its name ("Horde").
-- Created lazily with the first recipient or trust and not through DEFAULTS, so a client that never
-- loads this file keeps its SavedVariables as they were. A save with a newer `v` is read-only:
-- nothing writes to it and every group has no recipient.
GC.MailGroups = {}
local M = GC.MailGroups

M.VERSION = 1
-- ATTACHMENTS_MAX_SEND: the stacks a mail takes.
M.MAX_ATTACH = 12
-- What the post office takes for each attached stack, in copper.
M.POSTAGE = 30
-- The most letters a subject may have; the client allows more, but this keeps it readable in the
-- inbox of the alt.
M.SUBJECT_MAX = 64

local function newer(saved)
  return type(saved) == "table" and type(saved.v) == "number" and saved.v > M.VERSION
end

local function ours(saved)
  return type(saved) == "table" and saved.v == M.VERSION and type(saved.realms) == "table"
    and type(saved.trusted) == "table"
end

local function text(s)
  return type(s) == "string" and s ~= ""
end

--- Whether recipients can be set: false while a newer GoldCap's table is saved.
function M.Writable(db)
  return type(db) == "table" and not newer(db.mailTo)
end

-- The saved table, created when `db` may take one; nil when it may not.
local function table_(db)
  if type(db) ~= "table" or newer(db.mailTo) then return nil end
  if not ours(db.mailTo) then db.mailTo = { v = M.VERSION, realms = {}, trusted = {} } end
  return db.mailTo
end

-- The faction `full` was recorded with (Core/Alts.lua), or nil when it was never recorded.
local function factionOf(db, full)
  return GC.Alts and GC.Alts.FactionOf and GC.Alts.FactionOf(db, full) or nil
end

-- The older save's entry for `key` on `homeRealm`, or nil.
local function oldEntry(saved, homeRealm, key)
  local realm = saved.realms[homeRealm]
  local full = type(realm) == "table" and realm[key] or nil
  return text(full) and full or nil
end

local function forgetOld(saved, homeRealm, key)
  local realm = saved.realms[homeRealm]
  if type(realm) ~= "table" then return end
  realm[key] = nil
  if next(realm) == nil then saved.realms[homeRealm] = nil end
end

-- `faction`'s own choices on `homeRealm`, made when `create`.
local function ownOf(saved, homeRealm, faction, create)
  local by = saved.byFaction
  if type(by) ~= "table" then
    if not create then return nil end
    by = {}
    saved.byFaction = by
  end
  if type(by[homeRealm]) ~= "table" then
    if not create then return nil end
    by[homeRealm] = {}
  end
  if type(by[homeRealm][faction]) ~= "table" then
    if not create then return nil end
    by[homeRealm][faction] = {}
  end
  return by[homeRealm][faction]
end

--- The alt ("Name-Realm") that sells the group `key` on `homeRealm` for a sender of `faction`, or
--- nil: the faction's own choice, else the older save's entry when its recipient is recorded of
--- that faction; never one recorded of the other faction. Without a `faction` (not known), the
--- older save's entry as it is.
function M.RecipientOf(db, homeRealm, key, faction)
  local saved = type(db) == "table" and db.mailTo or nil
  if not ours(saved) then return nil end
  if not text(faction) then return oldEntry(saved, homeRealm, key) end
  local own = ownOf(saved, homeRealm, faction, false)
  local full = own and own[key]
  if text(full) then
    local side = factionOf(db, full)
    return (side == nil or side == faction) and full or nil
  end
  full = oldEntry(saved, homeRealm, key)
  return full and factionOf(db, full) == faction and full or nil
end

--- Sets the alt of the group `key` on `homeRealm` for a sender of `faction`, nil to forget it; the
--- older save's entry goes too when it read for that faction, so it never comes back. Without a
--- `faction` (not known), the older save's entry. True when it is set (or already forgotten with
--- nothing saved); false for a realm or group with no name, a recipient that is neither nil nor a
--- name, or a newer GoldCap's table.
function M.SetRecipient(db, homeRealm, key, full, faction)
  if type(db) ~= "table" or not text(homeRealm) or not text(key) then return false end
  if full ~= nil and not text(full) then return false end
  if newer(db.mailTo) then return false end
  if full == nil and not ours(db.mailTo) then return true end
  local saved = table_(db)
  if not saved then return false end
  if not text(faction) then
    if full == nil then
      forgetOld(saved, homeRealm, key)
    else
      if type(saved.realms[homeRealm]) ~= "table" then saved.realms[homeRealm] = {} end
      saved.realms[homeRealm][key] = full
    end
    return true
  end
  local old = oldEntry(saved, homeRealm, key)
  if old and factionOf(db, old) == faction then forgetOld(saved, homeRealm, key) end
  if full == nil then
    local own = ownOf(saved, homeRealm, faction, false)
    if own then
      own[key] = nil
      if next(own) == nil then
        local realm = saved.byFaction[homeRealm]
        realm[faction] = nil
        if next(realm) == nil then saved.byFaction[homeRealm] = nil end
        if next(saved.byFaction) == nil then saved.byFaction = nil end
      end
    end
    return true
  end
  ownOf(saved, homeRealm, faction, true)[key] = full
  return true
end

--- Whether the player has confirmed `full` ("Name-Realm") as an alt to send to.
function M.Trusted(db, full)
  local saved = type(db) == "table" and db.mailTo or nil
  return ours(saved) and saved.trusted[full] == true or false
end

--- Remembers `full` as confirmed. False for a name that is not one or a newer GoldCap's table.
function M.Trust(db, full)
  if not text(full) then return false end
  local saved = table_(db)
  if not saved then return false end
  saved.trusted[full] = true
  return true
end

--- Why a stack stays in the bags, read as UI/BankRoute.lua's reader marks it, or nil when a mail
--- may take it: "bound" for a stack read `bound` or `wue` (Warbound until equipped: the mail
--- refuses it, attached it would bind), "refund" while `canBeRefunded` (C_Item.CanBeRefunded; a
--- mail ends the refund). The reader asks it through `opts.staysWhy`, in place of the bank's.
function M.StaysWhy(stack, canBeRefunded)
  if stack.bound or stack.wue then return "bound" end
  if canBeRefunded == true then return "refund" end
  return nil
end

local function letters(s)
  return select(2, s:gsub("[^\128-\191]", ""))
end

local PREFIX = "GoldCap: "

-- The subject of a mail for groups called `names`, in order: all of them when they fit in
-- SUBJECT_MAX letters, else as many first names as fit and " and N more". A name is never cut: when
-- not even the first fits, alone or with " and N more", the subject counts the groups ("GoldCap: 1
-- group", "GoldCap: 3 groups"), as a group's name has no cap on goldcap.gg.
local function subjectOf(names)
  local all = PREFIX .. table.concat(names, ", ")
  if letters(all) <= M.SUBJECT_MAX then return all end
  local best
  for k = 1, #names - 1 do
    local head = {}
    for i = 1, k do head[i] = names[i] end
    local subject = PREFIX .. table.concat(head, ", ") .. " and " .. (#names - k) .. " more"
    if letters(subject) > M.SUBJECT_MAX then break end
    best = subject
  end
  return best or (PREFIX .. (#names == 1 and "1 group" or (#names .. " groups")))
end

-- The mails for `parts` = { { key, name, stack }, ... } (a stack with the group it came from) to
-- the recipient `to` ("mailName") / `full`: cut at MAX_ATTACH, each mail naming its groups once.
local function cut(parts, to, full)
  local mails = {}
  for first = 1, #parts, M.MAX_ATTACH do
    local mail = { to = to, full = full, stacks = {}, keys = {} }
    local names, seen = {}, {}
    for i = first, math.min(first + M.MAX_ATTACH - 1, #parts) do
      local part = parts[i]
      mail.stacks[#mail.stacks + 1] = part.stack
      if not seen[part.key] then
        seen[part.key] = true
        mail.keys[#mail.keys + 1] = part.key
        names[#names + 1] = part.name
      end
    end
    mail.subject = subjectOf(names)
    mails[#mails + 1] = mail
  end
  return mails
end

local function itemsOf(stacks)
  local byID, items = {}, {}
  for _, stack in ipairs(stacks) do
    local item = byID[stack.itemID]
    if not item then
      item = { itemID = stack.itemID, name = stack.name, count = 0 }
      byID[stack.itemID] = item
      items[#items + 1] = item
    end
    item.count = item.count + stack.count
  end
  table.sort(items, function(a, b)
    local an, bn = a.name or "", b.name or ""
    if an ~= bn then return an < bn end
    return a.itemID < b.itemID
  end)
  return items
end

--- What one press of Send to alts mails, for the stacks in the bags `bagStacks` (UI/BankRoute.lua's
--- reader, marked `stays` through StaysWhy): { rows, mails, stacks, postage }.
---
--- `rows` has one row for each followed group with anything in the bags, as Core/BankGroups.lua's
--- Plan orders them (by name, then key): { key, name, parentName, shortName, keep, send, items,
--- stays, to, mailName, state }. `send` is the group's stacks that leave the bags, `items` those
--- summed per item { itemID, name, count } by name, `stays` what the bags keep and why (Plan's),
--- `to` the group's alt ("Name-Realm") or nil and `mailName` what SendMail takes for them or nil.
--- `state` is "nothing" with nothing to send (all kept or staying, whoever the alt is), else "self"
--- when the alt is this character, "pick" with no alt or one this character cannot mail from here,
--- and "send" otherwise.
---
--- `mails` is the "send" rows' stacks grouped by `mailName` (a recipient's first row first), cut
--- as described above: { to = mailName, full, stacks, keys = { group key, ... }, subject }.
--- `stacks` is the stacks in all of them and `postage` what they cost, POSTAGE a stack.
---
--- `opts`: `groupOf(itemID)` and `keepFor(key)` and `moving`, as Plan takes them; `recipientOf(key)`
--- the group's alt or nil, `mailName(full)` what to mail them (Core/Alts.lua's MailName, nil when
--- this character cannot), `isMe(full)` whether `full` is this character.
function M.Plan(bagStacks, opts)
  local groups = GC.BankGroups.Plan(bagStacks, nil,
    { groupOf = opts.groupOf, keepFor = opts.keepFor, moving = opts.moving })
  local rows, perAlt, order = {}, {}, {}
  for _, group in ipairs(groups) do
    local to = opts.recipientOf(group.key)
    local mailName = to and opts.mailName(to) or nil
    local state
    if #group.toBank == 0 then
      state = "nothing"
    elseif to and opts.isMe(to) then
      state = "self"
    elseif not mailName then
      state = "pick"
    else
      state = "send"
    end
    rows[#rows + 1] = { key = group.key, name = group.name, parentName = group.parentName,
      shortName = group.shortName, keep = group.keep, send = group.toBank, items = itemsOf(group.toBank),
      stays = group.stays, to = to, mailName = mailName, state = state }
    if state == "send" then
      local alt = perAlt[mailName]
      if not alt then
        alt = { full = to, parts = {} }
        perAlt[mailName] = alt
        order[#order + 1] = mailName
      end
      for _, stack in ipairs(group.toBank) do
        alt.parts[#alt.parts + 1] = { key = group.key, name = group.name, stack = stack }
      end
    end
  end
  local mails, stacks = {}, 0
  for _, mailName in ipairs(order) do
    local alt = perAlt[mailName]
    for _, mail in ipairs(cut(alt.parts, mailName, alt.full)) do
      mails[#mails + 1] = mail
      stacks = stacks + #mail.stacks
    end
  end
  return { rows = rows, mails = mails, stacks = stacks, postage = M.POSTAGE * stacks }
end

--- The mails of the group `key` alone, the Send button of its row: its stacks only, cut the same
--- way. Empty when the group is not in `plan` or its state is not "send".
function M.MailsFor(plan, key)
  for _, row in ipairs(plan.rows) do
    if row.key == key then
      if row.state ~= "send" then return {} end
      local parts = {}
      for _, stack in ipairs(row.send) do parts[#parts + 1] = { key = key, name = row.name, stack = stack } end
      return cut(parts, row.mailName, row.to)
    end
  end
  return {}
end
