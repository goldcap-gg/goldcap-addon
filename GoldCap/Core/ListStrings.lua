local _, GC = ...

-- Shopping lists as other addons write them, read and written as plain data: no client call
-- here, so every rule below is pinned by spec/list_strings_spec.lua. Core/AppRuns.lua stores
-- what Parse reads (its own GCR1 run string stays there), and UI/BuyLists.lua asks the client
-- the two things only it can answer -- which item a name is, and what an item is called.
--
--   TSM: a group's items, `i:2589,i:2592`, which TSM imports into a group and Auctionator into a
--     list. The accepted tokens are TSM's own (`DecodeGroupExportHelper`, as goldcap.gg reads them
--     in packages/tsm's parseItemList): `i:<id>` or a bare id, either with bonus ids after a colon
--     (the base item is kept), `p:<species>` (a battle pet: skipped and counted), `group:<path>`
--     (a group: the last step of its paths' common prefix names the list, and a string with
--     two or more groups under that prefix can also be read as one list per group). TSM 4.10's packed export (letters, digits and
--     parentheses only, deflated) is not read: Lua 5.1 has no inflate, and goldcap.gg/list can
--     turn one into the plain string.
--   Auctionator: its shopping list export (Source/Shopping/ImportExport.lua,
--     GetBatchExportString): `List name^term^term`, one list per line. A term is an advanced
--     search (Source/Search/Advanced.lua, SplitAdvancedSearch): fourteen `;`-separated fields,
--     the first the name -- in double quotes for an exact search -- and the last the quantity.
--     ReconstituteAdvancedSearch writes an unset tier as "#", which is what Auctionator writes.
GC.ListStrings = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- One TSM token: { id = n }, { pet = true }, { group = path }, or nil when it is not one.
local function tsmToken(tok)
  local path = tok:match("^group:(.*)$")
  if path then return { group = trim(path) } end
  local id, rest = tok:match("^i:(%d+)(.*)$")
  if not id then id, rest = tok:match("^(%d+)(.*)$") end
  if id and (rest == "" or rest:match("^:[%d:%-]*$")) and #id <= 9 then
    local n = tonumber(id)
    if n and n > 0 then return { id = n } end
    return nil
  end
  if tok:match("^p:%d+$") or tok:match("^p:%d+:[%d:%-]*$") then return { pet = true } end
  return nil
end

local function split(text, sep)
  local out, from = {}, 1
  while true do
    local at = text:find(sep, from, true)
    if not at then
      out[#out + 1] = text:sub(from)
      return out
    end
    out[#out + 1] = text:sub(from, at - 1)
    from = at + #sep
  end
end

-- A group path as its steps. TSM writes a sub-group's path with backticks ("Leveling`Alchemy"),
-- and a literal comma inside a name as two ("Herbs``Ore").
local function pathSteps(path)
  local steps = {}
  for _, step in ipairs(split((path:gsub("``", "\1")), "`")) do
    step = trim((step:gsub("\1", ",")))
    if step ~= "" then steps[#steps + 1] = step end
  end
  return steps
end

-- The steps every path starts with. A path is `{}` for items that come before any group. The
-- prefix ends at the first step that differs, so it never has a hole for `#` to read past.
local function commonPrefix(paths)
  local prefix = nil
  for _, steps in ipairs(paths) do
    if not prefix then
      prefix = { unpack(steps) }
    else
      for i = 1, #prefix do
        if prefix[i] ~= steps[i] then
          for j = #prefix, i, -1 do prefix[j] = nil end
          break
        end
      end
    end
  end
  return prefix or {}
end

-- One list per distinct path that holds items, named after the root and the steps below it. An item
-- named in two groups belongs to the last one. Nil unless two or more paths hold items.
local function bySubgroup(seq, prefix)
  local owner = {}
  for _, entry in ipairs(seq) do owner[entry.id] = entry.key end
  local order, lists = {}, {}
  for _, entry in ipairs(seq) do
    if owner[entry.id] == entry.key then
      local list = lists[entry.key]
      if not list then
        local below = {}
        for i = #prefix + 1, #entry.steps do below[#below + 1] = entry.steps[i] end
        local name = #below > 0 and table.concat(below, ": ") or nil
        if #prefix > 0 then name = name and (prefix[#prefix] .. ": " .. name) or prefix[#prefix] end
        list = { name = name, items = {}, seen = {} }
        lists[entry.key] = list
        order[#order + 1] = list
      end
      if not list.seen[entry.id] then
        list.seen[entry.id] = true
        list.items[#list.items + 1] = { itemID = entry.id, qty = 1 }
      end
    end
  end
  if #order < 2 then return nil end
  for _, list in ipairs(order) do list.seen = nil end
  return order
end

local function parseTsm(text)
  if text:find("^", 1, true) then return nil end
  local items, skipped = {}, { pets = 0, groups = 0 }
  local paths, seq, current = {}, {}, { steps = {}, key = "" }
  local started = false
  for _, raw in ipairs(split(text, ",")) do
    local tok = trim(raw)
    if tok ~= "" then
      local t = tsmToken(tok)
      if not t then return nil end
      if t.id or t.pet then
        -- Something before the first group has no group: the paths then share nothing.
        if not started then
          started = true
          paths[#paths + 1] = current.steps
        end
        if t.id then
          items[#items + 1] = { itemID = t.id, qty = 1 }
          seq[#seq + 1] = { id = t.id, key = current.key, steps = current.steps }
        else
          skipped.pets = skipped.pets + 1
        end
      else
        skipped.groups = skipped.groups + 1
        started = true
        local steps = pathSteps(t.group)
        if #steps > 0 then
          current = { steps = steps, key = table.concat(steps, "\0") }
          paths[#paths + 1] = steps
        end
      end
    end
  end
  if #items == 0 and skipped.pets == 0 and skipped.groups == 0 then return nil end
  -- The list is named after the last step of the paths' common prefix: goldcap.gg's Copy for TSM
  -- writes every subgroup under the group's own name, and that name is the group.
  local prefix = commonPrefix(paths)
  local name = prefix[#prefix]
  local parsed = { format = "tsm", lists = { { name = name, items = items } }, skipped = skipped }
  parsed.subgroups = bySubgroup(seq, prefix)
  return parsed
end

-- Lua 5.1's tonumber on a field, as Auctionator reads it: a whole positive count, or nil.
local function count(field)
  local n = tonumber(field and trim(field) or "")
  if not n or n ~= n or n < 1 or n == math.huge then return nil end
  return math.floor(n)
end

local function auctionatorTerm(segment)
  local fields = split(segment, ";")
  local query = trim(fields[1] or "")
  local quoted = query:match('^"(.*)"$')
  local qty = count(fields[14]) or 1
  if quoted then
    query = trim(quoted)
  else
    local t = tsmToken(query)
    if t and t.id then return { itemID = t.id, qty = qty } end
  end
  -- A term with no letter or digit in it is nothing to look for.
  if query == "" or not query:find("[%w\128-\255]") then return nil end
  return { name = query, qty = qty }
end

local function parseAuctionator(text)
  if not text:find("^", 1, true) then return nil end
  local lists = {}
  for _, line in ipairs(split((text:gsub("\r", "")), "\n")) do
    if trim(line) ~= "" then
      local segments = split(line, "^")
      local list = { items = {} }
      for i, segment in ipairs(segments) do
        local bare = trim(segment:match("^[^;]*"))
        -- The first segment is the list's name (Auctionator's own BatchImportFromString), unless it
        -- is plainly an item: quoted, or an item id -- goldcap.gg's reader does the same.
        if i == 1 and bare ~= "" and not bare:find('^"') and not tsmToken(bare) then
          list.name = bare
        else
          local term = auctionatorTerm(segment)
          if term then list.items[#list.items + 1] = term end
        end
      end
      lists[#lists + 1] = list
    end
  end
  if #lists == 0 then return nil end
  return { format = "auctionator", lists = lists, skipped = { pets = 0, groups = 0 } }
end

--- Reads a TSM item or group string, or an Auctionator shopping list export. Returns
--- { format = "tsm"|"auctionator", subgroups = like lists, TSM only, present when two or more groups
--- hold items, lists = { { name = string|nil, items = { { itemID, qty } or
--- { name, qty } } } }, skipped = { pets, groups } }, or nil and why: "empty", "tsm_packed" (TSM's
--- deflated export, which this cannot unpack) or "unknown".
function GC.ListStrings.Parse(text)
  if type(text) ~= "string" then return nil, "empty" end
  text = trim(text)
  if text == "" then return nil, "empty" end
  local parsed = parseTsm(text) or parseAuctionator(text)
  if parsed then return parsed end
  if #text >= 24 and text:match("^[%w()]+$") then return nil, "tsm_packed" end
  return nil, "unknown"
end

-- How a name is compared: case-blind for the letters string.lower knows (Latin), and with its
-- spaces evened out. Cyrillic and CJK are compared as written, which is how the client writes them.
local function key(name)
  return (trim(name):gsub("%s+", " "):lower())
end

--- Names to item ids, built from what the caller knows. Find answers the id, false when two items
--- go by that name (the client has crafted reagents in ranks under one name), or nil.
function GC.ListStrings.NameIndex()
  local byName = {}
  local index = {}
  function index:Add(itemID, name)
    if type(itemID) ~= "number" or itemID <= 0 or type(name) ~= "string" or name == "" then return end
    local k = key(name)
    local seen = byName[k]
    if seen == nil then
      byName[k] = itemID
    elseif seen ~= itemID then
      byName[k] = false
    end
  end
  function index:Find(name)
    if type(name) ~= "string" then return nil end
    return byName[key(name)]
  end
  return index
end

--- The items of one parsed list as lines ({ i, q }), in order, plus every name `lookup` could not
--- turn into exactly one item. `lookup(name)` answers an item id, false (more than one item goes by
--- that name) or nil (unknown).
function GC.ListStrings.Resolve(items, lookup)
  local lines, unresolved, seen = {}, {}, {}
  for _, item in ipairs(items or {}) do
    local id = item.itemID
    if not id and item.name then
      local found = lookup and lookup(item.name) or nil
      if type(found) == "number" and found > 0 then id = found end
    end
    if id then
      lines[#lines + 1] = { i = id, q = item.qty or 1 }
    elseif item.name and not seen[key(item.name)] then
      seen[key(item.name)] = true
      unresolved[#unresolved + 1] = item.name
    end
  end
  return lines, unresolved
end

--- A list's items as a TSM item string, in the list's order, one token per item.
function GC.ListStrings.TSM(lines)
  local out, seen = {}, {}
  for _, line in ipairs(lines or {}) do
    local id = tonumber(line.i)
    if id and id > 0 and not seen[id] then
      seen[id] = true
      out[#out + 1] = "i:" .. math.floor(id)
    end
  end
  return table.concat(out, ",")
end

-- Separators that cannot survive inside a field, and Auctionator's quote.
local function clean(s) return trim((s or ""):gsub('[%^;"\r\n]', "")) end

--- A list as an Auctionator shopping list: its name, then one exact search per line with the
--- quantity in the fourteenth field, written the way Auctionator writes one. A vendor line is left
--- out (Auctionator would search the auction house for it), as goldcap.gg's own export does.
--- `nameOf(itemID)` answers the client's name or nil; an item without one is never written as a
--- blank search -- its id comes back in the second result instead.
function GC.ListStrings.Auctionator(name, lines, nameOf)
  local terms, missing = { clean(name) ~= "" and clean(name) or "GoldCap" }, {}
  for _, line in ipairs(lines or {}) do
    local qty = tonumber(line.q)
    if not line.v and qty and qty >= 1 then
      local itemName = nameOf and nameOf(line.i) or nil
      itemName = type(itemName) == "string" and clean(itemName) or ""
      if itemName ~= "" then
        terms[#terms + 1] = ('"%s";;;;;;;;;;;#;;%d'):format(itemName, math.floor(qty))
      else
        missing[#missing + 1] = line.i
      end
    end
  end
  return table.concat(terms, "^"), missing
end
