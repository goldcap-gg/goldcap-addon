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

function D.CanDisenchant(stack)
  local class, quality = stack.classID, stack.quality
  if class ~= ARMOR and class ~= WEAPON and class ~= PROFESSION then return false end
  if quality ~= 2 and quality ~= 3 and quality ~= 4 then return false end
  if stack.equipLoc == "INVTYPE_BODY" or stack.equipLoc == "INVTYPE_TABARD" then return false end
  if class == ARMOR and stack.subclassID == COSMETIC then return false end
  return true
end

-- Loot of one quality and expansion alike: "q3:x10"; an expansion the reader could not tell is "x?".
function D.KindOf(stack)
  return "q" .. tostring(stack.quality) .. ":x" .. (type(stack.expansion) == "number" and stack.expansion or "?")
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

-- One more cast of `kind`; mats = { [itemID] = units }. False when the store is a newer one's.
function D.Learn(db, kind, mats)
  if type(db) ~= "table" or type(kind) ~= "string" or type(mats) ~= "table" then return false end
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

-- { [itemID] = average units a cast gave }, and the casts behind it; nil and 0 when none.
function D.Yield(db, kind)
  local kinds = kindsOf(db, false)
  local k = kinds and kinds[kind]
  local n = type(k) == "table" and tonumber(k.n) or 0
  if n < 1 or type(k.mats) ~= "table" then return nil, 0 end
  local out = {}
  for id, units in pairs(k.mats) do out[id] = units / n end
  return out, n
end

-- Copper one cast of `kind` is worth at priceOf(itemID), and the casts behind it. Nil when nothing
-- is learned or a material has no price: a total never counts an unpriced material as nothing.
function D.MatsValue(db, kind, priceOf)
  local avg, n = D.Yield(db, kind)
  if not avg then return nil, 0 end
  local total = 0
  for id, units in pairs(avg) do
    local price = priceOf(id)
    if not positive(price) then return nil, n end
    total = total + units * price
  end
  return math.floor(total + 0.5), n
end

-- Items the player keeps (right click).
function D.Kept(db, itemID)
  local keep = type(db) == "table" and db.deKeep
  return type(keep) == "table" and type(keep.items) == "table" and keep.items[itemID] == true
end

function D.Keep(db, itemID)
  if type(db) ~= "table" or type(itemID) ~= "number" or not writable(db.deKeep, D.KEEP_VERSION) then return end
  if type(db.deKeep) ~= "table" then db.deKeep = { v = D.KEEP_VERSION, items = {} } end
  if type(db.deKeep.items) ~= "table" then db.deKeep.items = {} end
  db.deKeep.items[itemID] = true
end

function D.Unkeep(db, itemID)
  local keep = type(db) == "table" and db.deKeep
  if type(keep) ~= "table" or type(keep.items) ~= "table" or not writable(keep, D.KEEP_VERSION) then return end
  keep.items[itemID] = nil
end

-- The stack stays off the list whatever the figures say.
local function leftOut(s, opts)
  if not s.itemID or not D.CanDisenchant(s) then return true end
  if s.isLocked or s.refundable or s.tradeTimer or s.inSet or s.selling then return true end
  if D.Kept(opts.db, s.itemID) or opts.inGroup(s.itemID) then return true end
  if opts.failed[s.itemID] or opts.skipped[s.bag .. ":" .. s.slot] then return true end
  return false
end

-- Which figure pays most. Unknown mats name no verdict, unless the auction house is the better of
-- the two figures there are.
local function bestOf(mats, vendor, ah)
  if mats == nil then return (ah and ah > vendor) and "ah" or nil end
  if ah and ah > vendor and ah > mats then return "ah" end
  return mats > vendor and "mats" or "vendor"
end

local function group(row)
  if row.mats == nil then return 2 end
  return row.mats > row.vendor and 1 or 3
end

local function before(a, b)
  local ga, gb = group(a), group(b)
  if ga ~= gb then return ga < gb end
  if ga == 1 then
    local da, db = a.mats - a.vendor, b.mats - b.vendor
    if da ~= db then return da > db end
  elseif ga == 3 then
    local da, db = a.vendor - a.mats, b.vendor - b.mats
    if da ~= db then return da < db end
  end
  if a.stack.bag ~= b.stack.bag then return a.stack.bag < b.stack.bag end
  return a.stack.slot < b.stack.slot
end

-- The result: queue: mats rows (gain over the vendor largest first), mats unknown, then vendor rows
-- (loss smallest first); left: what the auction house pays more for.
-- opts: { db, priceOf(itemID) -> copper|nil, inGroup(itemID) -> bool, now, skipped = { [slotKey] },
-- failed = { [itemID] }, anyway = { [slotKey] } }. A row: { stack, slotKey, mats, n, vendor, ah, best }.
function D.Plan(stacks, opts)
  opts = opts or {}
  local o = {
    db = opts.db, now = opts.now,
    priceOf = opts.priceOf or function() return nil end,
    inGroup = opts.inGroup or function() return false end,
    skipped = opts.skipped or {}, failed = opts.failed or {}, anyway = opts.anyway or {},
  }
  local queue, left = {}, {}
  for _, s in ipairs(stacks or {}) do
    if not leftOut(s, o) then
      local row = { stack = s, slotKey = s.bag .. ":" .. s.slot }
      row.mats, row.n = D.MatsValue(o.db, D.KindOf(s), o.priceOf)
      row.vendor = positive(s.vendorUnit) and s.vendorUnit * (s.count or 1) or 0
      if positive(s.ahUnit) and GC.VendorSelect.Fresh(s, o.now) then
        row.ah = math.floor(s.ahUnit * GC.VendorSelect.KEEP) * (s.count or 1)
      end
      row.best = bestOf(row.mats, row.vendor, row.ah)
      if row.ah and row.ah > row.vendor and row.ah > (row.mats or 0) and not o.anyway[row.slotKey] then
        left[#left + 1] = row
      else
        queue[#queue + 1] = row
      end
    end
  end
  table.sort(queue, before)
  table.sort(left, before)
  local yields, matsTotal = {}, 0
  for _, row in ipairs(queue) do
    local avg = D.Yield(o.db, D.KindOf(row.stack))
    for id, units in pairs(avg or {}) do yields[id] = (yields[id] or 0) + units end
    matsTotal = matsTotal and row.mats and matsTotal + row.mats or nil
  end
  return { queue = queue, left = left, yields = yields, matsTotal = matsTotal }
end
