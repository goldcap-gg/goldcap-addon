local _, GC = ...

-- GoldCap Hoard (retail only): the model behind the window that stands beside the bank window
-- (UI/HoardFrame.lua). Pure: it reads no slot, no price and no rule of its own. The stacks are
-- UI/BankRoute.lua's reader's, the groups Core/BankGroups.lua's Plan, the craft queue's shortfall
-- Core/CraftQueue.lua's Missing, and every price comes from a function the window hands in (an
-- item's market value, its group's usual price). It writes only GC.db.hoard, through the store
-- functions at the end, and the window's own list of the groups it has shown in this visit
-- (Rows). GoldCap_Camelot.toc does not load this file.
--
-- It answers what each press of the window moves, as a list of stacks in the order the press
-- machine moves them, one whole stack at a time (the game cannot split a stack in one call, see
-- Core/BankGroups.lua), and what the window shows about it:
-- - the three tiles over the groups: Prices are up (PricesUp, IsPriceUp), For your crafts
--   (ForCrafts) and Put away (PutAway);
-- - the followed groups as rows (Rows): a row per group, a folder for the subgroups of one parent
--   group on goldcap.gg, the filter, the search and the sort, a folder's checkbox (CheckState) and
--   the selection bar's totals (Selection);
-- - the footer's Make room (MakeRoom, then Remember what went) and Put back (PutBack).
GC.Hoard = {}
local H = GC.Hoard

H.VERSION = 1
-- Prices are up takes out an item whose market value is at least this percent of its usual price.
H.PRICE_UP_PCT = 110
-- From this many followed groups the window shows its search, filter and sort above the list.
H.SEARCH_MIN_GROUPS = 8
-- The most item icons a row shows; the rest are its "+N".
H.ICONS = 5

local function slotKey(stack)
  return stack.bag .. ":" .. stack.slot
end

-- The biggest stack first, then by where it sits: Core/BankGroups.lua's order, so a plan reads the
-- same every time.
local function stackOrder(a, b)
  if a.count ~= b.count then return a.count > b.count end
  if a.bag ~= b.bag then return a.bag < b.bag end
  return a.slot < b.slot
end

-- Whether a press may take the stack now: the game does not hold it (`locked`), and it is not on
-- its way already (`moving`, "bag:slot" -> what the window recorded when it sent the stack, kept
-- until the bags show it moved, as Core/BankGroups.lua's Plan reads it).
local function free(stack, moving)
  return not stack.locked and not (moving and moving[slotKey(stack)])
end

-- A price the window can use: a positive, finite number of copper. Anything else is no price yet.
local function price(v)
  if type(v) ~= "number" or v ~= v or v <= 0 or v == math.huge then return nil end
  return v
end

-- What `count` of an item is worth at its market value, in whole copper; 0 without a value, so an
-- item the Companion has no price for yet counts for nothing rather than for a guess.
local function worthOf(valueOf, itemID, count)
  local v = valueOf and price(valueOf(itemID))
  return v and math.floor(count * v) or 0
end

-- Sums `stack` into its item's entry of `items` (in first-seen order, indexed by `byItem`), made
-- with `fields` on top of { itemID, name, count }.
local function addTo(items, byItem, stack, fields)
  local item = byItem[stack.itemID]
  if not item then
    item = { itemID = stack.itemID, name = stack.name, count = 0 }
    for k, v in pairs(fields or {}) do item[k] = v end
    byItem[stack.itemID] = item
    items[#items + 1] = item
  end
  item.count = item.count + stack.count
end

--- Whether an item sells above its usual price now: both prices known, and the market value
--- (`valueOf(itemID)`) at least PRICE_UP_PCT percent of the usual price (`usualOf(itemID)`). An
--- item missing either price is never up: a guess would take out what the player stored on
--- purpose. The window also asks it of the bags, to keep those items out of Put away.
function H.IsPriceUp(itemID, valueOf, usualOf)
  local now = valueOf and price(valueOf(itemID))
  local usual = usualOf and price(usualOf(itemID))
  if not (now and usual) then return false end
  return now * 100 >= usual * H.PRICE_UP_PCT
end

--- Prices are up: the stacks in the bank (`bankStacks`) of the followed groups' items that sell
--- above their usual price now (IsPriceUp), to take out for the Sell tab. `opts.groupOf(itemID)`
--- answers an item's group (Core/GroupRules.lua's GroupOf), nil for an item in none;
--- `opts.valueOf` and `opts.usualOf` the two prices; `opts.moving` marks the stacks a press has
--- sent. Answers { stacks, items = { { itemID, name, count, now, usual } }, worth }: the items the
--- most worth first (count × now), then by name and item, each item's stacks the biggest first,
--- and `worth` their worth now in whole copper.
function H.PricesUp(bankStacks, opts)
  local items, byItem, stacksOf, up = {}, {}, {}, {}
  for _, stack in ipairs(bankStacks or {}) do
    local id = stack.itemID
    if up[id] == nil then
      up[id] = opts.groupOf(id) ~= nil and H.IsPriceUp(id, opts.valueOf, opts.usualOf)
    end
    if up[id] and free(stack, opts.moving) then
      addTo(items, byItem, stack, { now = price(opts.valueOf(id)), usual = price(opts.usualOf(id)) })
      stacksOf[id] = stacksOf[id] or {}
      table.insert(stacksOf[id], stack)
    end
  end
  local function worth(item) return math.floor(item.count * item.now) end
  table.sort(items, function(a, b)
    local aw, bw = worth(a), worth(b)
    if aw ~= bw then return aw > bw end
    local an, bn = a.name or "", b.name or ""
    if an ~= bn then return an < bn end
    return a.itemID < b.itemID
  end)
  local out = { stacks = {}, items = items, worth = 0 }
  for _, item in ipairs(items) do
    out.worth = out.worth + worth(item)
    table.sort(stacksOf[item.itemID], stackOrder)
    for _, stack in ipairs(stacksOf[item.itemID]) do out.stacks[#out.stacks + 1] = stack end
  end
  return out
end

--- For your crafts: what to take out of the bank (`bankStacks`) for the craft queue, from
--- Core/CraftQueue.lua's Missing rows { ids, need, have, missing } counted against the bags alone.
--- For each reagent, the fewest whole stacks of any of its qualities (`ids`) whose sum covers what
--- the bags lack, or every stack the bank has of it when that is not enough. The biggest stack goes
--- first while none covers what is left alone; then the smallest that does, so a shortfall of 10
--- takes a stack of 10 and not the 200 beside it (the count of stacks is the same either way). A
--- currency row is no item and is skipped; a stack is taken once, for the first reagent that
--- wants it, and never one the game holds or a press has sent (`moving`, optional, as in PricesUp).
--- Answers { stacks, items = { { itemID, name, need, inBags, taken } } }, in the queue's order: one
--- item per reagent the bank has some of, named after its first stack taken, with the craft
--- queue's need, what the bags hold and what the stacks bring.
function H.ForCrafts(missing, bankStacks, moving)
  local out, used = { stacks = {}, items = {} }, {}
  for _, row in ipairs(missing or {}) do
    if type(row) == "table" and not row.currency and type(row.ids) == "table"
      and type(row.missing) == "number" and row.missing > 0 then
      local wanted, candidates = {}, {}
      for _, id in ipairs(row.ids) do wanted[id] = true end
      for _, stack in ipairs(bankStacks or {}) do
        if wanted[stack.itemID] and free(stack, moving) and not used[slotKey(stack)] then
          candidates[#candidates + 1] = stack
        end
      end
      table.sort(candidates, stackOrder)
      local taken, first = 0, nil
      while taken < row.missing and #candidates > 0 do
        local left, pick = row.missing - taken, 1
        if candidates[1].count >= left then
          -- The stacks that cover what is left alone come first: take the last of them, the
          -- smallest, and of a run of the same size the first in stack order.
          while candidates[pick + 1] and candidates[pick + 1].count >= left do pick = pick + 1 end
          while pick > 1 and candidates[pick - 1].count == candidates[pick].count do pick = pick - 1 end
        end
        local stack = table.remove(candidates, pick)
        used[slotKey(stack)] = true
        out.stacks[#out.stacks + 1] = stack
        taken = taken + stack.count
        first = first or stack
      end
      if first then
        out.items[#out.items + 1] = { itemID = first.itemID, name = first.name, need = row.need,
          inBags = row.have, taken = taken }
      end
    end
  end
  return out
end

--- Put away: every group's To bank stack (Core/BankGroups.lua's Plan, so each group's keep count
--- holds) whose item is not in `excludeIds` ({ [itemID] = true }: the window leaves out what
--- Prices are up would sell and the reagents the craft queue needs). Answers { stacks, items =
--- { { itemID, name, count } } }, the stacks in the groups' order and the items summed in the
--- order they first come.
function H.PutAway(groups, excludeIds)
  local exclude = excludeIds or {}
  local out, byItem = { stacks = {}, items = {} }, {}
  for _, group in ipairs(groups or {}) do
    for _, stack in ipairs(group.toBank or {}) do
      if not exclude[stack.itemID] then
        out.stacks[#out.stacks + 1] = stack
        addTo(out.items, byItem, stack)
      end
    end
  end
  return out
end

-- A Plan group's items with what each is worth here, the most worth first, then by name and item:
-- the order a group row shows their icons in. Answers the list and the group's worth.
local function rankedItems(group, valueOf)
  local ranked, total = {}, 0
  for _, item in ipairs(group.items or {}) do
    local worth = worthOf(valueOf, item.itemID, item.count)
    total = total + worth
    ranked[#ranked + 1] = { item = item, worth = worth }
  end
  table.sort(ranked, function(a, b)
    if a.worth ~= b.worth then return a.worth > b.worth end
    local an, bn = a.item.name or "", b.item.name or ""
    if an ~= bn then return an < bn end
    return a.item.itemID < b.item.itemID
  end)
  return ranked, total
end

local function listLength(list)
  return type(list) == "table" and #list or 0
end

-- Whether the group has a line under To move here: a stack to move either way, or one that stays
-- in the bags and says why.
local function hasMoves(group)
  return listLength(group.toBank) + listLength(group.toBags) + listLength(group.stays) > 0
end

-- Whether `query` (folded, not blank) is in a name the row or its folder shows, or in the name of
-- one of the group's items. Core/NameMatch.lua's fold: case-blind in every script and accent-blind
-- in the Latin ones, as the BUY list's search is, and a plain find, so "." or "%" is just a
-- character.
local function matches(group, query)
  local fold = GC.NameMatch.Fold
  local function holds(text)
    return type(text) == "string" and fold(text):find(query, 1, true) ~= nil
  end
  if holds(group.name) or holds(group.shortName) or holds(group.parentName) then return true end
  for _, item in ipairs(group.items or {}) do
    if holds(item.name) then return true end
  end
  return false
end

local function nameOrder(a, b)
  if a.name ~= b.name then return a.name < b.name end
  if a.key ~= b.key then return a.key < b.key end
  return a.kind < b.kind
end

local function valueOrder(a, b)
  if a.worth ~= b.worth then return a.worth > b.worth end
  return nameOrder(a, b)
end

local function groupRow(group, depth, name, opts)
  local ranked, worth = rankedItems(group, opts.valueOf)
  local icons = {}
  for i = 1, math.min(H.ICONS, #ranked) do
    local item = ranked[i].item
    icons[i] = { itemID = item.itemID, icon = opts.iconOf and opts.iconOf(item.itemID) or nil, count = item.count }
  end
  local first = group.items and group.items[1]
  return { kind = "group", key = group.key, name = name, depth = depth,
    play = opts.playOf and first and opts.playOf(first.itemID) or nil, icons = icons, more = #ranked - #icons,
    worth = worth, inBags = group.inBags or 0, inBank = group.inBank or 0, toBank = group.toBank,
    toBags = group.toBags, group = group }
end

-- A folder's row over the group rows it lists (`kids`, in its order): their worth, counts and
-- moves together, and the first icon of each, up to ICONS.
local function folderRow(folder, kids, open)
  local row = { kind = "folder", key = folder.key, name = folder.name, depth = 0, icons = {}, more = 0, worth = 0,
    inBags = 0, inBank = 0, toBank = {}, toBags = {}, children = {}, childCount = folder.count, open = open }
  local items = 0
  for _, kid in ipairs(kids) do
    row.children[#row.children + 1] = kid.key
    row.worth = row.worth + kid.worth
    row.inBags = row.inBags + kid.inBags
    row.inBank = row.inBank + kid.inBank
    for _, stack in ipairs(kid.toBank or {}) do row.toBank[#row.toBank + 1] = stack end
    for _, stack in ipairs(kid.toBags or {}) do row.toBags[#row.toBags + 1] = stack end
    items = items + #kid.icons + kid.more
    local icon = kid.icons[1]
    if icon and #row.icons < H.ICONS then
      row.icons[#row.icons + 1] = { itemID = icon.itemID, icon = icon.icon, count = icon.count }
    end
  end
  -- An item is in one group only (Core/GroupRules.lua's first cap decides it), so the groups'
  -- items added up are the folder's distinct items.
  row.more = items - #row.icons
  return row
end

--- The followed groups (Core/BankGroups.lua's Plan) as the window's rows, in the order it paints
--- them: { rows, folded, total, toMove }.
---
--- A row is { kind = "group" | "folder", key, name, depth, play, icons, more, worth, inBags, inBank,
--- toBank, toBags }. `icons` are at most ICONS { itemID, icon, count }, with the item's count in the
--- bags and the bank together, and `more` is how many items have no icon; `worth` is each item's
--- count at its market value (`opts.valueOf`), in whole copper, an item without one counting 0. A
--- group row also has `group`, its Plan group, and `play`, `opts.playOf(itemID)` asked with the
--- group's first item, as every item of a group has its rule (Core/GroupRules.lua's RuleFor), nil
--- without it. Its icons are its items the most worth first, then by name. `opts.iconOf(itemID)`
--- answers an icon, from the first stack of that item the window read in the bags or the bank;
--- the groups themselves do not carry every stack.
---
--- Folders: the groups that share a parent group (`parentKey`) are one folder when there are two
--- or more of them, named after the parent; a lone subgroup is a group row with its whole name.
--- A folder's groups are its children, rows of depth 1 under it named by their short name, painted
--- only while it is open (`opts.folderOpen(parentKey)`, also its `open`). Folders are made from all
--- the groups before the filter and the search, so a folder neither comes nor goes as its groups'
--- moves finish: it shows while at least one of its groups is listed, and over those alone (its
--- `children`, their keys, and its worth, counts, moves and icons, the first icon of each). Its
--- `childCount` is all its groups. Its key is the parent's, which a followed top group may share,
--- so the window tells rows apart by `kind` too.
---
--- `opts.filter`: "move" (the default) lists a group with a stack to move or a stack that stays in
--- the bags, or one in `opts.shown`, and counts the others the search finds as `folded`; "all"
--- lists every group. `opts.shown` ({ [group key] = true }) is the window's table for the visit,
--- emptied as the bank opens and closes: Rows adds every group with something to move to it, so a
--- group listed once stays listed after its last move, as the bank card did, and a press never
--- takes the row from under the cursor.
---
--- `opts.query` keeps the groups whose name, short name or parent's name, or one of whose items'
--- names, holds it, case-blind (Core/NameMatch.lua); blank keeps all. `opts.sort`: "value" (the
--- default) puts the most worth first, then by name; "name" sorts by name, then key. Folders sort
--- among the rows by their own worth and name, and their groups inside by the same order.
---
--- `total` is every group, `toMove` every group "move" lists, whatever the search.
function H.Rows(groups, opts)
  opts = opts or {}
  local shown = opts.shown or {}
  local all = opts.filter == "all"
  local order = opts.sort == "name" and nameOrder or valueOrder
  local query = GC.NameMatch.Fold(opts.query)
  local result = { rows = {}, folded = 0, total = 0, toMove = 0 }

  local siblings = {}
  for _, group in ipairs(groups or {}) do
    if group.parentKey then siblings[group.parentKey] = (siblings[group.parentKey] or 0) + 1 end
  end

  local top, folders, byParent = {}, {}, {}
  for _, group in ipairs(groups or {}) do
    result.total = result.total + 1
    if hasMoves(group) then shown[group.key] = true end
    local listed = shown[group.key] == true
    if listed then result.toMove = result.toMove + 1 end
    local parent = group.parentKey
    local folder = nil
    if parent and siblings[parent] >= 2 then
      folder = byParent[parent]
      if not folder then
        folder = { key = parent, name = group.parentName or parent, count = 0, kids = {} }
        byParent[parent] = folder
        folders[#folders + 1] = folder
      end
      folder.count = folder.count + 1
    end
    if query == "" or matches(group, query) then
      if all or listed then
        if folder then
          folder.kids[#folder.kids + 1] = groupRow(group, 1, group.shortName or group.name, opts)
        else
          top[#top + 1] = groupRow(group, 0, group.name, opts)
        end
      else
        result.folded = result.folded + 1
      end
    end
  end

  local kidsOf = {}
  for _, folder in ipairs(folders) do
    if #folder.kids > 0 then
      table.sort(folder.kids, order)
      local row = folderRow(folder, folder.kids, opts.folderOpen and opts.folderOpen(folder.key) == true or false)
      kidsOf[row] = folder.kids
      top[#top + 1] = row
    end
  end
  table.sort(top, order)
  for _, row in ipairs(top) do
    result.rows[#result.rows + 1] = row
    if row.open then
      for _, kid in ipairs(kidsOf[row]) do result.rows[#result.rows + 1] = kid end
    end
  end
  return result
end

--- A folder row's checkbox: "on" with every group it lists selected (`selected`, { [group key] =
--- true }), "mixed" with some, "off" with none.
function H.CheckState(row, selected)
  local on, off = 0, 0
  for _, key in ipairs(row and row.children or {}) do
    if selected and selected[key] then on = on + 1 else off = off + 1 end
  end
  if on > 0 and off == 0 then return "on" end
  if on > 0 then return "mixed" end
  return "off"
end

--- The selection bar: the Plan groups whose key is selected ({ [group key] = true }), the children
--- of a closed folder included, as they are not painted but are selected. Answers { groups, toBank,
--- toBags, worth }: how many, their To bank and To bags stacks in the groups' order, and what they
--- are worth here (`valueOf`, as a row's worth). A key with no group here is left out; each group
--- counts once, however it was checked.
function H.Selection(groups, selected, valueOf)
  local out = { groups = 0, toBank = {}, toBags = {}, worth = 0 }
  for _, group in ipairs(groups or {}) do
    if selected and selected[group.key] then
      out.groups = out.groups + 1
      for _, stack in ipairs(group.toBank or {}) do out.toBank[#out.toBank + 1] = stack end
      for _, stack in ipairs(group.toBags or {}) do out.toBags[#out.toBags + 1] = stack end
      local _, worth = rankedItems(group, valueOf)
      out.worth = out.worth + worth
    end
  end
  return out
end

--- Make room: every stack in the bags (`bagStacks`, as the reader marks them against the bank
--- chosen) that the bank takes, the biggest first, then by bag and slot. Not one that `stays` (the
--- bank refuses it, or it is still refundable and the bank is the Warband Bank), one the game
--- holds, or one a press has sent (`moving`, optional). Whether a soulbound stack is among them is
--- the reader's to decide: the character's own bank takes one, the Warband Bank none.
function H.MakeRoom(bagStacks, moving)
  local out = {}
  for _, stack in ipairs(bagStacks or {}) do
    if not stack.stays and free(stack, moving) then out[#out + 1] = stack end
  end
  table.sort(out, stackOrder)
  return out
end

--- What Make room put into the bank, for Put back: { bankType, at, items = { [itemID] = count } },
--- the bank (Enum.BankType), when (`now`, time()) and how many of each item `stacks` held.
function H.Remember(bankType, now, stacks)
  local room = { bankType = bankType, at = now, items = {} }
  for _, stack in ipairs(stacks or {}) do
    if type(stack.count) == "number" and stack.count > 0 then
      room.items[stack.itemID] = (room.items[stack.itemID] or 0) + stack.count
    end
  end
  return room
end

--- Put back: the stacks to take out of the bank (`bankStacks`, read from `room.bankType`) for what
--- Make room put there (`room`, as Remember made it). For each item remembered, its stacks the
--- biggest first, each taken while it fits in what is left of the count: a stack moves whole, so
--- Put back never takes more than went in (what the bank held before stays there), and never more
--- than is there (another character may have taken some out of the Warband Bank). A stack the game
--- holds or a press has sent (`moving`, optional) is left. In item order.
function H.PutBack(room, bankStacks, moving)
  local out = {}
  if type(room) ~= "table" or type(room.items) ~= "table" then return out end
  local byItem, ids = {}, {}
  for _, stack in ipairs(bankStacks or {}) do
    local want = room.items[stack.itemID]
    if type(want) == "number" and want > 0 and free(stack, moving) then
      if not byItem[stack.itemID] then
        byItem[stack.itemID] = {}
        ids[#ids + 1] = stack.itemID
      end
      table.insert(byItem[stack.itemID], stack)
    end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local stacks, left = byItem[id], room.items[id]
    table.sort(stacks, stackOrder)
    for _, stack in ipairs(stacks) do
      if stack.count <= left then
        out[#out + 1] = stack
        left = left - stack.count
      end
    end
  end
  return out
end

-- The window's memory, GC.db.hoard = { v = 1, closed = true or nil, open = { [parent key] = true },
-- room = { [character] = { bankType, at, items = { [itemID] = count } } } }: whether the player
-- closed the window (a small handle then stays beside the bank), which folders are open, and what
-- Make room put into a bank for each character, for Put back after a reload or the next visit.
-- Account wide, made lazily by the first write that keeps something and not through DEFAULTS, so
-- a client that never loads this file keeps its SavedVariables as they were, as GC.db.bankKeep
-- does (Core/BankGroups.lua). A read writes nothing. A save with a newer `v` is read-only: nothing
-- writes to it and every read answers as if nothing were saved. A damaged part reads as nothing
-- saved and is made afresh by the next write to it.

local function newer(saved)
  return type(saved) == "table" and type(saved.v) == "number" and saved.v > H.VERSION
end

local function ours(saved)
  return type(saved) == "table" and saved.v == H.VERSION
end

-- The saved part `name` of an ours table, or nil when it is missing or damaged.
local function part(db, name)
  local saved = type(db) == "table" and db.hoard or nil
  if not ours(saved) then return nil end
  return type(saved[name]) == "table" and saved[name] or nil
end

-- The table to write into, made now when nothing of ours is saved, and its part `name`, made now
-- when it is missing or damaged. Only for a db that passed Writable.
local function writable(db, name)
  if not ours(db.hoard) then db.hoard = { v = H.VERSION, open = {}, room = {} } end
  if name and type(db.hoard[name]) ~= "table" then db.hoard[name] = {} end
  return db.hoard
end

local function key(s)
  return type(s) == "string" and s ~= ""
end

local function wholeAbove0(n)
  return type(n) == "number" and n == n and n > 0 and n ~= math.huge and n % 1 == 0
end

-- A room as it is kept: a fresh copy with only the items of a whole positive id and count, or
-- nil when it is not a room (no bank, no time, no items table). `strict` refuses a room with any
-- unsound item, for a write; a read keeps the sound ones.
local function cleanRoom(room, strict)
  if type(room) ~= "table" or type(room.items) ~= "table" then return nil end
  local bankType, at = room.bankType, room.at
  if not (type(bankType) == "number" and bankType >= 0 and bankType % 1 == 0) then return nil end
  if not (type(at) == "number" and at == at and at >= 0 and at ~= math.huge) then return nil end
  local items = {}
  for id, count in pairs(room.items) do
    if wholeAbove0(id) and wholeAbove0(count) then
      items[id] = count
    elseif strict then
      return nil
    end
  end
  return { bankType = bankType, at = at, items = items }
end

--- Whether the window's memory can be written: false while a newer GoldCap's table is saved.
function H.Writable(db)
  return type(db) == "table" and not newer(db.hoard)
end

--- Whether the player closed the window.
function H.Closed(db)
  local saved = type(db) == "table" and db.hoard or nil
  return ours(saved) and saved.closed == true
end

--- Remembers the window closed (true) or open (false, which keeps nothing). True when it is kept
--- (or open with nothing saved); false for a value that is not true or false, or a newer table.
function H.SetClosed(db, closed)
  if not H.Writable(db) or type(closed) ~= "boolean" then return false end
  if not closed and not ours(db.hoard) then return true end
  writable(db).closed = closed or nil
  return true
end

--- Whether the folder of the parent group `parentKey` is open: closed until the player opens it.
function H.FolderOpen(db, parentKey)
  local open = part(db, "open")
  return open ~= nil and open[parentKey] == true
end

--- Remembers the folder `parentKey` open (true) or closed (false, which forgets it). True when it is
--- kept; false for a folder with no key, a value that is not true or false, or a newer table.
function H.SetFolderOpen(db, parentKey, open)
  if not H.Writable(db) or not key(parentKey) or type(open) ~= "boolean" then return false end
  if not open and not ours(db.hoard) then return true end
  writable(db, "open").open[parentKey] = open or nil
  return true
end

--- What Make room put into a bank for the character `char` (its name and realm), as a fresh copy
--- { bankType, at, items }, or nil with nothing remembered.
function H.Room(db, char)
  local rooms = part(db, "room")
  local room = rooms and cleanRoom(rooms[char], false)
  if not room or next(room.items) == nil then return nil end
  return room
end

--- Remembers what Make room put away for `char` (a copy of `room`), or forgets it (nil, or a room
--- with no item: nothing to put back). True when it is kept or forgotten; false for no character,
--- a room that is not one (no bank, no time, an item or count that is not a whole number above 0),
--- or a newer table.
function H.SetRoom(db, char, room)
  if not H.Writable(db) or not key(char) then return false end
  local clean = nil
  if room ~= nil then
    clean = cleanRoom(room, true)
    if not clean then return false end
    if next(clean.items) == nil then clean = nil end
  end
  if not clean and not ours(db.hoard) then return true end
  writable(db, "room").room[char] = clean
  return true
end
