local _, GC = ...

-- Bank by group (retail only): at a bank, what one press of Store or Take out moves for each
-- followed group, and how many of each item the player keeps in the bags. Pure: the stacks come
-- from UI/BankRoute.lua's reader and the group of an item from Core/GroupRules.lua, both handed in
-- by the GoldCap Hoard (UI/HoardFrame.lua), which reads the bank its switch names: the character's
-- own or the Warband Bank. GoldCap_Camelot.toc does not load this file.
--
-- A group is planned and its keep count kept by its key, shown and sorted by its name. The key is
-- the group's id on goldcap.gg, which a follow in another language or a renamed list keeps, else
-- its name (Core/GroupRules.lua's GroupOf): two groups named alike are two groups.
--
-- A press moves its button's list in order, a stack at a time and each whole: the game cannot
-- split a stack in one call. So Store lists a stack of an item only while the bags keep at least
-- the group's keep count of that item without it, the biggest stack first, and Take out lists every
-- stack of the group. A stack a press has
-- sent and the bags do not show moved yet (`moving`) is on its way: it is offered to no press, and
-- it no longer counts toward what the bags keep. A stack in the bags the bank must not take
-- (`stays`: refused by it, or still refundable and the bank is the Warband Bank) is counted and
-- kept, and named with why, so the Hoard can say which stack stays and why instead of counting it
-- silently.
--
-- Keep counts are saved in GC.db.bankKeep = { v = 1, groups = { [group key] = count } }, one count
-- per group for the whole account and both banks, created lazily with the first count above 0 and
-- not through DEFAULTS, so a client that never loads this file keeps its SavedVariables as they
-- were. A save with a newer `v` is read-only: nothing writes to it and every group keeps 0.
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

--- How many of each item of the group `key` the player keeps in the bags: 0 until they set a count.
function M.KeepFor(db, key)
  local saved = type(db) == "table" and db.bankKeep or nil
  if not ours(saved) then return 0 end
  local n = saved.groups[key]
  return wholeKeep(n) and n or 0
end

--- Sets the keep count of the group `key`, 0 to forget it. True when it is set (or already 0 with
--- nothing saved); false for a count that is not a whole number from 0 to MAX_KEEP, a group with no
--- key, or a newer GoldCap's table.
function M.SetKeep(db, key, n)
  if type(db) ~= "table" or type(key) ~= "string" or key == "" or not wholeKeep(n) then return false end
  if newer(db.bankKeep) then return false end
  if not ours(db.bankKeep) then
    if n == 0 then return true end
    db.bankKeep = { v = M.VERSION, groups = {} }
  end
  db.bankKeep.groups[key] = n > 0 and n or nil
  return true
end

--- Where a stack sits, "bag:slot": the key a press records a stack it has sent under (`moving`),
--- which Plan and Core/Hoard.lua read.
function M.SlotKey(stack)
  return stack.bag .. ":" .. stack.slot
end

local function itemOrder(a, b)
  local an, bn = a.name or "", b.name or ""
  if an ~= bn then return an < bn end
  return a.itemID < b.itemID
end

--- The order a press moves stacks in, a table.sort comparator: the biggest stack first, then by
--- where it sits, so a plan reads the same every time. Core/Hoard.lua's plans use it too.
function M.StackOrder(a, b)
  if a.count ~= b.count then return a.count > b.count end
  if a.bag ~= b.bag then return a.bag < b.bag end
  return a.slot < b.slot
end

--- The followed groups with items in the bags or the bank, sorted by name (then key), each
--- { key, name, inBags, inBank, keep, toBank = { stack, ... }, toBags = { stack, ... }, stays = { ... } }:
--- the counts are what the bags and the bank show, each list is what the presses of its button
--- move, in order, and `stays` is what the bags keep because the bank must not take it,
--- { itemID, name, count, why } summed per item and reason ("refund" or "refused"), by name.
--- Stacks are UI/BankRoute.lua's: { itemID, bag, slot, count, name, locked, stays }. Each group
--- also carries what no press can raise, for the Hoard to size itself once: `items`, every item of
--- the group here { itemID, name, count } with its count in the bags and the bank together, and
--- `stackCount`, its stacks in both (a stack moves whole, and landing on another only merges them).
--- Each group also has `parentKey`, `parentName` and `shortName` (nil for a top group), as
--- `opts.groupOf(itemID)` answers them after the key and the name (Core/GroupRules.lua's GroupOf).
--- `opts.keepFor(key)` answers a group's keep count, and `opts.moving[bag .. ":" .. slot]` marks a
--- stack a press has sent.
function M.Plan(bagStacks, bankStacks, opts)
  local moving = opts.moving or {}
  local groups, byKey = {}, {}
  -- The stack's group, or nil; the stack is counted in it (stackCount, items).
  local function groupFor(stack)
    local key, name, parentKey, parentName, shortName = opts.groupOf(stack.itemID)
    if not key then return nil end
    local group = byKey[key]
    if not group then
      group = { key = key, name = name or key, parentKey = parentKey, parentName = parentName,
        shortName = shortName, inBags = 0, inBank = 0, keep = opts.keepFor(key) or 0, toBank = {},
        toBags = {}, stays = {}, items = {}, stackCount = 0, bagItems = {}, bankItems = {}, staysBy = {}, totals = {} }
      byKey[key] = group
      groups[#groups + 1] = group
    end
    group.stackCount = group.stackCount + 1
    local total = group.totals[stack.itemID]
    if not total then
      total = { itemID = stack.itemID, name = stack.name, count = 0 }
      group.totals[stack.itemID] = total
      group.items[#group.items + 1] = total
    end
    total.count = total.count + stack.count
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
    return not moving[M.SlotKey(stack)] and not stack.locked
  end

  for _, stack in ipairs(bagStacks or {}) do
    local group = groupFor(stack)
    if group then
      group.inBags = group.inBags + stack.count
      local item = itemIn(group.bagItems, stack)
      -- What the bags hold once the stacks already sent have left.
      if not moving[M.SlotKey(stack)] then item.kept = item.kept + stack.count end
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
    for _, item in ipairs(sortedItems(group.bagItems)) do
      table.sort(item.stacks, M.StackOrder)
      local left = item.kept
      for _, stack in ipairs(item.stacks) do
        if left - stack.count >= group.keep then
          group.toBank[#group.toBank + 1] = stack
          left = left - stack.count
        end
      end
    end
    for _, item in ipairs(sortedItems(group.bankItems)) do
      table.sort(item.stacks, M.StackOrder)
      for _, stack in ipairs(item.stacks) do group.toBags[#group.toBags + 1] = stack end
    end
    table.sort(group.stays, function(a, b)
      if a.name ~= b.name or a.itemID ~= b.itemID then return itemOrder(a, b) end
      return a.why < b.why
    end)
    table.sort(group.items, itemOrder)
    group.bagItems, group.bankItems, group.staysBy, group.totals = nil, nil, nil, nil
  end
  table.sort(groups, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.key < b.key
  end)
  return groups
end
