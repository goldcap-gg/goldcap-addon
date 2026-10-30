local _, GC = ...

-- What an enchanter disenchants, in what order, and what disenchanting gives. Pure: the stacks come
-- from Services/VendorBags.lua, the prices from the caller. What a cast gives is learned from the
-- player's own casts only (the UI hands Learn the loot that followed its own cast); no table of
-- yields ships with the addon.
--
-- Stack: Core/VendorSelect.lua's, plus { classID, subclassID, equipLoc, expansion }.
GC.Disenchant = {}
local D = GC.Disenchant

D.SPELL = 13262

-- Item classes (Enum.ItemClass): Weapon, Armor, Profession. Armor subclass 5 is Cosmetic.
local WEAPON, ARMOR, PROFESSION = 2, 4, 19
local COSMETIC = 5

-- The average follows the last ~50 casts: past that every count is scaled down before the next adds.
D.WINDOW = 50
D.YIELDS_VERSION = 1
D.KEEP_VERSION = 1

local function positive(n) return type(n) == "number" and n > 0 end

-- The gear the game will not disenchant (Data/NoDisenchant.lua, generated from its own tables:
-- ItemSparse Flags_0 0x8000; the client refuses one with "That item is not a valid target."),
-- decoded on first use into one sorted array, searched by halves: the ids go in sorted runs, each
-- the base 36 step from the last id of the run before and, after "+", how many more follow one by
-- one. The client's table.create sizes the array to the file's count up front (Lua 5.1: 16 bytes an
-- id, about 270 KB for 17,116; a set of them took a hash of 32,768 nodes of 40, about 1.3 MB: the
-- re-review's N2). Empty without the file.
local noDisenchant, noDisenchantN

local function decodeNoDisenchant()
  local data = type(GC.NoDisenchant) == "table" and GC.NoDisenchant or {}
  local count = tonumber(data.count) or 0
  local create = rawget(table, "create")
  local ids = type(create) == "function" and count > 0 and create(count) or {}
  local n, last = 0, 0
  if type(data.ids) == "string" then
    for token in data.ids:gmatch("[^,]+") do
      local step, more = token:match("^(%w+)%+?(%w*)$")
      last = last + (tonumber(step, 36) or 0)
      n = n + 1
      ids[n] = last
      for _ = 1, tonumber(more, 36) or 0 do
        last = last + 1
        n = n + 1
        ids[n] = last
      end
    end
  end
  return ids, n
end

--- Whether the game's own data says `itemID` is never disenchanted.
function D.NoDisenchant(itemID)
  if not noDisenchant then noDisenchant, noDisenchantN = decodeNoDisenchant() end
  if type(itemID) ~= "number" then return false end
  local lo, hi = 1, noDisenchantN
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local id = noDisenchant[mid]
    if id == itemID then return true end
    if id < itemID then lo = mid + 1 else hi = mid - 1 end
  end
  return false
end

--- Gear of a kind disenchanting takes: armor, weapons and profession tools of quality 2 to 4, not a
--- shirt, a tabard or cosmetic armor; whatever the game's own list says of the item.
function D.Eligible(stack)
  local class, quality = stack.classID, stack.quality
  if class ~= ARMOR and class ~= WEAPON and class ~= PROFESSION then return false end
  if quality ~= 2 and quality ~= 3 and quality ~= 4 then return false end
  if stack.equipLoc == "INVTYPE_BODY" or stack.equipLoc == "INVTYPE_TABARD" then return false end
  if class == ARMOR and stack.subclassID == COSMETIC then return false end
  return true
end

--- Gear of such a kind that the game's own list does not refuse.
function D.CanDisenchant(stack)
  return D.Eligible(stack) and not D.NoDisenchant(stack.itemID)
end

-- The first expansion whose gear disenchants alike at every item level (Dragonflight, ItemSparse
-- ExpansionID 9); before it, what an item gives depends on its item level band.
D.LEVELLESS_FROM = 9
-- The item level band's width, in item levels.
D.LEVEL_STEP = 5

-- Loot alike (the code review, 2026-10-27): the quality, the expansion ("x?" where the reader could
-- not tell it), armor ("a"), weapon ("w") or profession tool ("p"), and before Dragonflight the item
-- level band ("i340" for 340 to 344; "i?" where the reader could not tell the level): "q3:x10:a",
-- "q2:x7:w:i340". No yield of anyone's is shipped: every kind is learned from the player's own casts.
function D.KindOf(stack)
  local expansion = type(stack.expansion) == "number" and stack.expansion or nil
  local body = stack.classID == WEAPON and "w" or stack.classID == PROFESSION and "p" or "a"
  local kind = "q" .. tostring(stack.quality) .. ":x" .. (expansion or "?") .. ":" .. body
  if expansion and expansion < D.LEVELLESS_FROM then
    local level = type(stack.itemLevel) == "number" and stack.itemLevel > 0 and stack.itemLevel or nil
    kind = kind .. ":i" .. (level and math.floor(level / D.LEVEL_STEP) * D.LEVEL_STEP or "?")
  end
  return kind
end

-- The kind a yield was learned under before armor, weapons and item levels counted ("q3:x10"),
-- for a kind from Dragonflight on, where only the quality and the expansion count; nil before it,
-- where such a yield mixed what cannot be told apart and lapses.
local function olderKind(kind)
  local older, expansion = kind:match("^(q[^:]+:x(%d+)):[awp]$")
  if older and tonumber(expansion) >= D.LEVELLESS_FROM then return older end
  return nil
end

-- A store a newer GoldCap wrote is read, never written.
local function writable(store, version)
  return type(store) ~= "table" or (tonumber(store.v) or 0) <= version
end

function D.Writable(db)
  return type(db) == "table" and writable(db.deYields, D.YIELDS_VERSION) and writable(db.deKeep, D.KEEP_VERSION)
end

local function kindsOf(db, create)
  if type(db) ~= "table" then return nil end
  if type(db.deYields) ~= "table" then
    if not create then return nil end
    db.deYields = { v = D.YIELDS_VERSION, kinds = {} }
  end
  if type(db.deYields.kinds) ~= "table" then
    if not create then return nil end
    db.deYields.kinds = {}
  end
  return db.deYields.kinds
end

-- One more cast of `kind`; mats = { [itemID] = units }. False when the store is a newer one's, and
-- for a kind the reader could not tell ("x?", "i?"): such a cast would teach every item that could
-- not be told what one of them gave (the code review's re-review, 2026-10-27).
function D.Learn(db, kind, mats)
  if type(db) ~= "table" or type(kind) ~= "string" or type(mats) ~= "table" then return false end
  if kind:find("?", 1, true) then return false end
  if not writable(db.deYields, D.YIELDS_VERSION) then return false end
  local kinds = kindsOf(db, true)
  local k = kinds[kind]
  if type(k) ~= "table" or type(k.mats) ~= "table" then
    k = { n = 0, mats = {} }
    kinds[kind] = k
  end
  k.n = tonumber(k.n) or 0
  if k.n >= D.WINDOW then
    for id, units in pairs(k.mats) do k.mats[id] = units * (D.WINDOW - 1) / D.WINDOW end
    k.n = D.WINDOW - 1
  end
  for id, units in pairs(mats) do
    if type(id) == "number" and positive(units) then k.mats[id] = (k.mats[id] or 0) + units end
  end
  k.n = k.n + 1
  return true
end

-- { [itemID] = average units a cast gave }, and the casts behind it; nil and 0 when none. A kind
-- from Dragonflight on that was never learned reads what its older kind learned (olderKind).
function D.Yield(db, kind)
  local kinds = kindsOf(db, false)
  local k = kinds and kinds[kind]
  if kinds and type(k) ~= "table" and type(kind) == "string" then
    local older = olderKind(kind)
    k = older and kinds[older]
  end
  local n = type(k) == "table" and tonumber(k.n) or 0
  if n < 1 or type(k.mats) ~= "table" then return nil, 0 end
  local out = {}
  for id, units in pairs(k.mats) do out[id] = units / n end
  return out, n
end

-- Copper one cast of `kind` is worth at priceOf(itemID), and the casts behind it. Nil when nothing
-- is learned or a material has no price: a total never counts an unpriced material as nothing. A
-- material priced at 0 (one nobody can sell, UI/DisenchantFrame.lua's priceOf) adds nothing.
function D.MatsValue(db, kind, priceOf)
  local avg, n = D.Yield(db, kind)
  if not avg then return nil, 0 end
  local total = 0
  for id, units in pairs(avg) do
    local price = priceOf(id)
    if type(price) ~= "number" or price < 0 then return nil, n end
    total = total + units * price
  end
  return math.floor(total + 0.5), n
end

-- The keep store (db.deKeep, D.KEEP_VERSION): `items`, what the player keeps (right click), and
-- `cant`, what the client refused to disenchant at all ("Item cannot be disenchanted", "That item is
-- not a valid target."), until the player says Try again. Each set is { [itemID] = true }, made
-- when its first item comes.
local function marked(db, set, itemID)
  local keep = type(db) == "table" and db.deKeep
  return type(keep) == "table" and type(keep[set]) == "table" and keep[set][itemID] == true
end

local function mark(db, set, itemID)
  if type(db) ~= "table" or type(itemID) ~= "number" or not writable(db.deKeep, D.KEEP_VERSION) then return end
  if type(db.deKeep) ~= "table" then db.deKeep = { v = D.KEEP_VERSION } end
  if type(db.deKeep[set]) ~= "table" then db.deKeep[set] = {} end
  db.deKeep[set][itemID] = true
end

local function unmark(db, set, itemID)
  local keep = type(db) == "table" and db.deKeep
  if type(keep) ~= "table" or type(keep[set]) ~= "table" or not writable(keep, D.KEEP_VERSION) then return end
  keep[set][itemID] = nil
end

-- Every item of a set, lowest id first.
local function idsOf(db, set)
  local keep = type(db) == "table" and db.deKeep
  local ids = {}
  if type(keep) == "table" and type(keep[set]) == "table" then
    for id, on in pairs(keep[set]) do
      if on == true and type(id) == "number" then ids[#ids + 1] = id end
    end
  end
  table.sort(ids)
  return ids
end

function D.Kept(db, itemID) return marked(db, "items", itemID) end
function D.Keep(db, itemID) mark(db, "items", itemID) end
function D.Unkeep(db, itemID) unmark(db, "items", itemID) end
function D.KeptIDs(db) return idsOf(db, "items") end

function D.Cant(db, itemID) return marked(db, "cant", itemID) end
function D.MarkCant(db, itemID) mark(db, "cant", itemID) end
function D.Uncant(db, itemID) unmark(db, "cant", itemID) end
function D.CantIDs(db) return idsOf(db, "cant") end

--- The key the Disenchant window's choices for a visit (Disenchant anyway, Skip, the chosen item,
--- the ones done) hold a stack by: its own GUID (the bag reader's `guid`), which follows it wherever a
--- sort of the bags moves it and tells apart two items with one link (the owner, 2026-10-27: four
--- identical slippers); without one, its slot and link, which hold while the slot holds that link.
function D.IdOf(stack)
  if type(stack.guid) == "string" and stack.guid ~= "" then return stack.guid end
  return stack.bag .. ":" .. stack.slot .. "|" .. tostring(stack.link)
end

-- The stack stays off the list whatever the figures say.
local function leftOut(s, opts)
  if not s.itemID or not D.CanDisenchant(s) then return true end
  if s.isLocked or s.refundable or s.tradeTimer or s.inSet or s.selling then return true end
  if D.Kept(opts.db, s.itemID) or D.Cant(opts.db, s.itemID) or opts.inGroup(s.itemID) then return true end
  if opts.failed[s.itemID] or opts.skipped[D.IdOf(s)] then return true end
  return false
end

-- Which figure pays most. Unknown mats name no verdict, unless the auction house is the better of
-- the two figures there are. A vendor that will not buy the item (`vendor` nil) never pays most.
local function bestOf(mats, vendor, ah)
  if mats == nil then return (ah and ah > (vendor or 0)) and "ah" or nil end
  if ah and ah > (vendor or 0) and ah > mats then return "ah" end
  if vendor == nil then return "mats" end
  return mats > vendor and "mats" or "vendor"
end

-- 1: the mats pay more (or no vendor buys it); 2: mats unknown; 3: the vendor pays as much or more.
local function group(row)
  if row.mats == nil then return 2 end
  if row.vendor == nil then return 1 end
  return row.mats > row.vendor and 1 or 3
end

--- Of a plan's `queue`: how many rows' learned mats pay more than a vendor (or no vendor buys
--- them), and how many rows' mats are not learned yet. The rest pay just what a vendor does.
function D.QueueCounts(queue)
  local worth, learning = 0, 0
  for _, row in ipairs(queue or {}) do
    local g = group(row)
    if g == 1 then worth = worth + 1 elseif g == 2 then learning = learning + 1 end
  end
  return worth, learning
end

local function before(a, b)
  local ga, gb = group(a), group(b)
  if ga ~= gb then return ga < gb end
  if ga == 1 then
    local da, db = a.mats - (a.vendor or 0), b.mats - (b.vendor or 0)
    if da ~= db then return da > db end
  elseif ga == 2 then
    -- An unknown kind: the cheapest piece first, so the kind is learned on it (a dear one of the
    -- kind then moves to "a vendor pays more" once its mats are known).
    local va, vb = a.vendor or 0, b.vendor or 0
    if va ~= vb then return va < vb end
  elseif ga == 3 then
    local da, db = a.vendor - a.mats, b.vendor - b.mats
    if da ~= db then return da < db end
  end
  if a.stack.bag ~= b.stack.bag then return a.stack.bag < b.stack.bag end
  return a.stack.slot < b.stack.slot
end

-- The result: queue: mats rows (gain over the vendor largest first), mats unknown (how GoldCap
-- learns; the cheapest to a vendor first), then rows whose mats pay just what a vendor does; left:
-- what the auction house pays more for; leftVendor: what a vendor pays more for than its known mats
-- (smallest loss first). The chosen item (`first`) joins the queue where it sorts, from a left list
-- too, and is `next`; with none chosen `next` is the queue's first. The queue's order never changes
-- for a choice (owner, 2026-10-28: "список меняется при нажатии, не очень удобно").
-- It, a skip and Disenchant anyway hold an item by D.IdOf, so a sort of the bags never moves them to
-- another item, an identical one included. A row's `vendor` is nil for an item no vendor buys.
-- opts: { db, priceOf(itemID) -> copper|nil, inGroup(itemID) -> bool, now, skipped = { [id] = true },
-- failed = { [itemID] }, anyway = { [id] = true }, first = id }. A row: { stack, slotKey, id, mats,
-- n, vendor, ah, best }.
function D.Plan(stacks, opts)
  opts = opts or {}
  local o = {
    db = opts.db, now = opts.now,
    priceOf = opts.priceOf or function() return nil end,
    inGroup = opts.inGroup or function() return false end,
    skipped = opts.skipped or {}, failed = opts.failed or {}, anyway = opts.anyway or {},
  }
  local first = opts.first
  local queue, left, leftVendor, chosen = {}, {}, {}, nil
  for _, s in ipairs(stacks or {}) do
    if not leftOut(s, o) then
      local row = { stack = s, slotKey = s.bag .. ":" .. s.slot, id = D.IdOf(s) }
      row.mats, row.n = D.MatsValue(o.db, D.KindOf(s), o.priceOf)
      row.vendor = positive(s.vendorUnit) and s.vendorUnit * (s.count or 1) or nil
      if positive(s.ahUnit) and GC.VendorSelect.Fresh(s, o.now) then
        row.ah = math.floor(s.ahUnit * GC.VendorSelect.KEEP) * (s.count or 1)
      end
      row.best = bestOf(row.mats, row.vendor, row.ah)
      local anyway = o.anyway[row.id] == true
      if first ~= nil and first == row.id then
        chosen = row
        queue[#queue + 1] = row
      elseif row.ah and row.ah > (row.vendor or 0) and row.ah > (row.mats or 0) and not anyway then
        left[#left + 1] = row
      elseif row.mats and row.vendor and row.vendor > row.mats and not anyway then
        leftVendor[#leftVendor + 1] = row
      else
        queue[#queue + 1] = row
      end
    end
  end
  table.sort(queue, before)
  table.sort(left, before)
  table.sort(leftVendor, before)
  local yields, matsTotal = {}, 0
  for _, row in ipairs(queue) do
    local avg = D.Yield(o.db, D.KindOf(row.stack))
    for id, units in pairs(avg or {}) do yields[id] = (yields[id] or 0) + units end
    matsTotal = matsTotal and row.mats and matsTotal + row.mats or nil
  end
  return { queue = queue, next = chosen or queue[1], left = left, leftVendor = leftVendor, yields = yields,
    matsTotal = matsTotal }
end
