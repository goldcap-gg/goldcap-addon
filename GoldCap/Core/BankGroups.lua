local _, GC = ...

-- Bank by group (retail only): at a bank, what one press of To bank or To bags moves for each
-- followed group, and how many of each item the player keeps in the bags. Pure: the stacks come
-- from UI/BankRoute.lua's reader and the group of an item from Core/GroupRules.lua, both handed in
-- by the card (UI/BankGroupsCard.lua). GoldCap_Camelot.toc does not load this file.
--
-- A press moves one stack, whole: the game cannot split a stack in one call. So To bank moves a
-- stack of an item only while the bags keep at least the group's keep count of that item without
-- it, the biggest stack first, and To bags takes every stack of the group out. A stack a press has
-- sent and the bags do not show moved yet (`moving`) is on its way: it is offered to no press, and
-- it no longer counts toward what the bags keep. A stack in the bags the Warband Bank must not take
-- (`stays`: still refundable, or refused) is counted and kept, and named with why, so the card can
-- say which stack stays and why instead of counting it silently.
--
-- Keep counts are saved in GC.db.bankKeep = { v = 1, groups = { [group name] = count } }, one count
-- per group for the whole account, created lazily with the first count above 0 and not through
-- DEFAULTS, so a client that never loads this file keeps its SavedVariables as they were. A save
-- with a newer `v` is read-only: nothing writes to it and every group keeps 0.
GC.BankGroups = {}
local M = GC.BankGroups

M.VERSION = 1
-- The most a keep count may be: the craft queue's limit for a typed count (Core/CraftQueue.lua's
-- ParseCount), which reads what the player types into the same popup.
M.MAX_KEEP = 9999

local function wholeKeep(n)
  return type(n) == "number" and n == n and n >= 0 and n <= M.MAX_KEEP and n % 1 == 0
end

local function newer(saved)
  return type(saved) == "table" and type(saved.v) == "number" and saved.v > M.VERSION
end

local function ours(saved)
  return type(saved) == "table" and saved.v == M.VERSION and type(saved.groups) == "table"
end

--- Whether keep counts can be set: false while a newer GoldCap's table is saved.
function M.Writable(db)
  return type(db) == "table" and not newer(db.bankKeep)
end

--- How many of each item of `name` the player keeps in the bags: 0 until they set a count.
function M.KeepFor(db, name)
  local saved = type(db) == "table" and db.bankKeep or nil
  if not ours(saved) then return 0 end
  local n = saved.groups[name]
  return wholeKeep(n) and n or 0
end

--- Sets the keep count of a group, 0 to forget it. True when it is set (or already 0 with nothing
--- saved); false for a count that is not a whole number from 0 to MAX_KEEP, a group with no name,
--- or a newer GoldCap's table.
function M.SetKeep(db, name, n)
  if type(db) ~= "table" or type(name) ~= "string" or name == "" or not wholeKeep(n) then return false end
  if newer(db.bankKeep) then return false end
  if not ours(db.bankKeep) then
    if n == 0 then return true end
    db.bankKeep = { v = M.VERSION, groups = {} }
  end
  db.bankKeep.groups[name] = n > 0 and n or nil
  return true
end

local function key(stack)
  return stack.bag .. ":" .. stack.slot
end

local function itemOrder(a, b)
  local an, bn = a.name or "", b.name or ""
  if an ~= bn then return an < bn end
  return a.itemID < b.itemID
end

-- The biggest stack first, then by where it sits, so a plan reads the same every time.
local function stackOrder(a, b)
  if a.count ~= b.count then return a.count > b.count end
  if a.bag ~= b.bag then return a.bag < b.bag end
  return a.slot < b.slot
end

--- The followed groups with items in the bags or the bank, sorted by name, each
--- { name, inBags, inBank, keep, toBank = { stack, ... }, toBags = { stack, ... }, stays = { ... } }:
--- the counts are what the bags and the bank show, each list is what the presses of its button
--- move, in order, and `stays` is what the bags keep because the Warband Bank must not take it,
--- { itemID, name, count, why } summed per item and reason ("refund" or "refused"), by name.
--- Stacks are UI/BankRoute.lua's: { itemID, bag, slot, count, name, locked, stays }.
--- `opts.groupOf(itemID)` names an item's group, `opts.keepFor(name)` its keep count, and
--- `opts.moving[bag .. ":" .. slot]` marks a stack a press has sent.
function M.Plan(bagStacks, bankStacks, opts)
  local moving = opts.moving or {}
  local groups, byName = {}, {}
  local function groupFor(stack)
    local name = opts.groupOf(stack.itemID)
    if not name then return nil end
    local group = byName[name]
    if not group then
      group = { name = name, inBags = 0, inBank = 0, keep = opts.keepFor(name) or 0, toBank = {}, toBags = {},
        stays = {}, items = {}, bankItems = {}, staysBy = {} }
      byName[name] = group
      groups[#groups + 1] = group
    end
    return group
  end
  local function itemIn(list, stack)
    local item = list[stack.itemID]
    if not item then
      item = { itemID = stack.itemID, name = stack.name, stacks = {}, kept = 0 }
      list[stack.itemID] = item
    end
    return item
  end
  local function free(stack)
    return not moving[key(stack)] and not stack.locked
  end

  for _, stack in ipairs(bagStacks or {}) do
    local group = groupFor(stack)
    if group then
      group.inBags = group.inBags + stack.count
      local item = itemIn(group.items, stack)
      -- What the bags hold once the stacks already sent have left.
      if not moving[key(stack)] then item.kept = item.kept + stack.count end
      if stack.stays then
        local why = stack.itemID .. ":" .. stack.stays
        local entry = group.staysBy[why]
        if not entry then
          entry = { itemID = stack.itemID, name = stack.name, count = 0, why = stack.stays }
          group.staysBy[why] = entry
          group.stays[#group.stays + 1] = entry
        end
        entry.count = entry.count + stack.count
      elseif free(stack) then
        item.stacks[#item.stacks + 1] = stack
      end
    end
  end
  for _, stack in ipairs(bankStacks or {}) do
    local group = groupFor(stack)
    if group then
      group.inBank = group.inBank + stack.count
      local item = itemIn(group.bankItems, stack)
      if free(stack) then item.stacks[#item.stacks + 1] = stack end
    end
  end

  local function sortedItems(list)
    local out = {}
    for _, item in pairs(list) do out[#out + 1] = item end
    table.sort(out, itemOrder)
    return out
  end
  for _, group in ipairs(groups) do
    for _, item in ipairs(sortedItems(group.items)) do
      table.sort(item.stacks, stackOrder)
      local left = item.kept
      for _, stack in ipairs(item.stacks) do
        if left - stack.count >= group.keep then
          group.toBank[#group.toBank + 1] = stack
          left = left - stack.count
        end
      end
    end
    for _, item in ipairs(sortedItems(group.bankItems)) do
      table.sort(item.stacks, stackOrder)
      for _, stack in ipairs(item.stacks) do group.toBags[#group.toBags + 1] = stack end
    end
    table.sort(group.stays, function(a, b)
      if a.name ~= b.name or a.itemID ~= b.itemID then return itemOrder(a, b) end
      return a.why < b.why
    end)
    group.items, group.bankItems, group.staysBy = nil, nil, nil
  end
  table.sort(groups, function(a, b) return a.name < b.name end)
  return groups
end
