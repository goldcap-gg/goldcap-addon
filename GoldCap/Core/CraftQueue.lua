local _, GC = ...

-- The craft queue (retail, the profession window's GoldCap panel): per character, a list of
-- recipes each with a count of crafts or a restock target, and the arithmetic that turns it into
-- what to buy. Pure apart from GC.db; every count and price is a function the caller hands in.
--
-- Store: GC.db.craft = { v = 1, chars = { ["Name-Realm"] = { entries = { Entry, ... },
--   listed = { [itemID] = quantity }, listedAt = time() or nil, buyList = code or nil } } }
-- `buyList` is the code of the character's one craft queue BUY list in GC.db.runs (the list
-- UI/CraftQueueView.lua keeps in step with the queue).
-- Entry: { recipe = Recipe, count = n } or { recipe = Recipe, restock = n }. Recipe is the
-- snapshot Services/CraftClient.lua makes (Core/CraftMath.lua names its shape), stored whole so
-- the queue reads without the profession window open.
--
-- The store is made on the first write and never by a read. A store a newer GoldCap wrote
-- (v above this file's) is left exactly as it is: every write answers nil and reads see nothing.
GC.CraftQueue = GC.CraftQueue or {}
local Q = GC.CraftQueue

local C = {
  VERSION = 1,
  MAX_COUNT = 9999,
  -- Enum.AuctionStatus.Sold (AuctionHouseDocumentation.lua): a sold auction stays in the owned
  -- list until its gold is collected, and it is no longer anything the player holds.
  SOLD = 1,
  -- The longest an auction runs: a read of the owned auctions older than that may count auctions
  -- that sold, expired and were collected since.
  LISTED_MAX_AGE = 48 * 3600,
}

local function isWhole(n, min)
  return type(n) == "number" and n == math.floor(n) and n >= min and n <= C.MAX_COUNT
end

-- The store, or nil. `create`: make it when absent. A newer store is never handed out.
local function store(create)
  local db = GC.db
  if type(db) ~= "table" then return nil end
  local s = db.craft
  if type(s) ~= "table" then
    if not create then return nil end
    s = { v = C.VERSION, chars = {} }
    db.craft = s
  end
  if (tonumber(s.v) or 0) > C.VERSION then return nil end
  if type(s.chars) ~= "table" then s.chars = {} end
  return s
end

local function charOf(char, create)
  if type(char) ~= "string" or char == "" then return nil end
  if create and not Q.Writable() then return nil end
  local s = store(create)
  if not s then return nil end
  local c = s.chars[char]
  if type(c) ~= "table" then
    if not create then return nil end
    c = { entries = {}, listed = {} }
    s.chars[char] = c
  end
  if type(c.entries) ~= "table" then c.entries = {} end
  if type(c.listed) ~= "table" then c.listed = {} end
  return c
end

local function indexOf(c, recipeID)
  for i, e in ipairs(c.entries) do
    if type(e) == "table" and type(e.recipe) == "table" and e.recipe.recipeID == recipeID then return i end
  end
  return nil
end

local function validRecipe(recipe)
  return type(recipe) == "table" and type(recipe.recipeID) == "number"
end

--- False when the store was written by a newer GoldCap: nothing may be added to it here.
function Q.Writable()
  local db = GC.db
  if type(db) ~= "table" then return false end
  return type(db.craft) ~= "table" or (tonumber(db.craft.v) or 0) <= C.VERSION
end

--- This character's entries in queue order; an empty table when there are none.
function Q.Entries(char)
  local c = charOf(char, false)
  local out = {}
  for _, e in ipairs(c and c.entries or {}) do
    if type(e) == "table" and validRecipe(e.recipe) then out[#out + 1] = e end
  end
  return out
end

--- Adds `count` crafts of `recipe`: summed into a count the recipe already has, in place of a
--- restock target it had. The stored snapshot becomes `recipe`. Returns the entry, or nil.
function Q.Add(char, recipe, count)
  if not validRecipe(recipe) or not isWhole(count, 1) then return nil end
  local c = charOf(char, true)
  if not c then return nil end
  local i = indexOf(c, recipe.recipeID)
  local e = i and c.entries[i] or nil
  if e and type(e.count) == "number" then
    e.count = math.min(C.MAX_COUNT, e.count + count)
    e.recipe = recipe
    return e
  end
  e = { recipe = recipe, count = count }
  if i then c.entries[i] = e else c.entries[#c.entries + 1] = e end
  return e
end

--- Restocks `recipe` to `target` held: replaces whatever the recipe had in the queue, keeping its
--- place. 0 takes the recipe off. Returns the entry, or nil (taken off, or nothing written).
function Q.Restock(char, recipe, target)
  if not validRecipe(recipe) or not isWhole(target, 0) then return nil end
  local c = charOf(char, true)
  if not c then return nil end
  local i = indexOf(c, recipe.recipeID)
  if target == 0 then
    if i then table.remove(c.entries, i) end
    return nil
  end
  local e = { recipe = recipe, restock = target }
  if i then c.entries[i] = e else c.entries[#c.entries + 1] = e end
  return e
end

function Q.Remove(char, recipeID)
  local c = charOf(char, false)
  if not c or not Q.Writable() then return end
  local i = indexOf(c, recipeID)
  if i then table.remove(c.entries, i) end
end

--- What the character holds of what the recipe makes, in every quality: `countOf` (bags, banks and
--- the mailbox) plus what `listed` says is up on the auction house.
function Q.Held(entry, countOf, listed)
  local recipe = type(entry) == "table" and entry.recipe or nil
  if type(recipe) ~= "table" then return 0 end
  local outputs = type(recipe.outputs) == "table" and #recipe.outputs > 0 and recipe.outputs or { recipe.output }
  listed = type(listed) == "table" and listed or {}
  local held = 0
  for _, id in ipairs(outputs) do
    held = held + (tonumber(countOf(id)) or 0) + (tonumber(listed[id]) or 0)
  end
  return held
end

--- Crafts still to make: a count as it stands; a restock as the whole crafts that bring `held` up
--- to the target, none when it is already there.
function Q.CraftsNeeded(entry, held)
  if type(entry) ~= "table" then return 0 end
  if type(entry.count) == "number" then return entry.count end
  if type(entry.restock) ~= "number" then return 0 end
  local per = math.max(1, type(entry.recipe) == "table" and tonumber(entry.recipe.per) or 1)
  return math.ceil(math.max(0, entry.restock - (tonumber(held) or 0)) / per)
end

local function slotKey(slot)
  if slot.currency then return "c" .. slot.currency end
  if type(slot.ids) ~= "table" then return nil end
  local parts = {}
  for i, id in ipairs(slot.ids) do parts[i] = tostring(id) end
  return table.concat(parts, ",")
end

--- What the queue needs of each reagent: `craftsOf(entry)` crafts of each entry, summed across
--- entries for slots that take the same reagent (the same qualities in the same order). Rows are
--- { ids, q } or { currency, q }, in the order first seen.
function Q.Needs(entries, craftsOf)
  local rows, byKey = {}, {}
  for _, entry in ipairs(type(entries) == "table" and entries or {}) do
    local crafts = tonumber(craftsOf(entry)) or 0
    if crafts > 0 and type(entry.recipe) == "table" then
      for _, slot in ipairs(type(entry.recipe.slots) == "table" and entry.recipe.slots or {}) do
        local key = slotKey(slot)
        if key then
          local row = byKey[key]
          if not row then
            row = slot.currency and { currency = slot.currency, q = 0 } or { ids = slot.ids, q = 0 }
            byKey[key] = row
            rows[#rows + 1] = row
          end
          row.q = row.q + (tonumber(slot.q) or 0) * crafts
        end
      end
    end
  end
  return rows
end

--- The needs the character is short of: `have` counts every quality of a reagent, and what
--- `currencyOf` says the character holds of a currency (none when it is not handed in). Rows
--- { ids or currency, need, have, missing }, only those missing some.
function Q.Missing(needs, countOf, currencyOf)
  local out = {}
  for _, row in ipairs(type(needs) == "table" and needs or {}) do
    local have = 0
    if row.currency then
      have = currencyOf and tonumber(currencyOf(row.currency)) or 0
    else
      for _, id in ipairs(row.ids or {}) do have = have + (tonumber(countOf(id)) or 0) end
    end
    local missing = row.q - have
    if missing > 0 then
      out[#out + 1] = { ids = row.ids, currency = row.currency, need = row.q, have = have, missing = missing }
    end
  end
  return out
end

--- The craft queue's BUY lines ({ i, q }), from `needs` (Needs' rows): one per reagent, the
--- cheapest priced quality, else the lowest, asking for the whole need less what is held of the
--- reagent's other qualities. BUY buys a line's `q` less what it sees held of that one item
--- (Core/BuyRun.lua), so the line buys exactly what is missing, and reads done once the bags hold
--- it. A reagent the other qualities cover has no line. An item `vendorOf` gives a vendor's price
--- for is a vendor stop ({ i, q, v = true, vu }), which BUY lists for the merchant instead of
--- searching the auction house. A currency goes to `notBuyable`.
function Q.BuyLines(needs, unitOf, countOf, vendorOf)
  local lines, notBuyable = {}, {}
  for _, row in ipairs(type(needs) == "table" and needs or {}) do
    if row.currency then
      notBuyable[#notBuyable + 1] = { currency = row.currency }
    elseif type(row.ids) == "table" and row.ids[1] then
      local i = GC.CraftMath.SlotChoice({ ids = row.ids }, unitOf) or row.ids[1]
      local q = tonumber(row.q) or 0
      for _, id in ipairs(row.ids) do
        if id ~= i then q = q - (tonumber(countOf(id)) or 0) end
      end
      if q > 0 then
        local line = { i = i, q = q }
        local vu = vendorOf and tonumber(vendorOf(i)) or nil
        if vu and vu > 0 then line.v, line.vu = true, vu end
        lines[#lines + 1] = line
      end
    end
  end
  return lines, notBuyable
end

--- The code of this character's craft queue BUY list, or nil (none yet, or a newer store).
function Q.BuyList(char)
  local c = charOf(char, false)
  local code = c and c.buyList or nil
  return type(code) == "string" and code ~= "" and code or nil
end

--- Remembers `code` as this character's craft queue BUY list. False when nothing may be written.
function Q.SetBuyList(char, code)
  if type(code) ~= "string" or code == "" then return false end
  local c = charOf(char, true)
  if not c then return false end
  c.buyList = code
  return true
end

--- The character's own auctions (C_AuctionHouse.GetOwnedAuctions) as listed counts, replacing the
--- last ones. A sold auction is not counted: the item is gone.
function Q.FoldListed(char, owned, now)
  local c = charOf(char, true)
  if not c then return end
  local listed = {}
  for _, a in ipairs(type(owned) == "table" and owned or {}) do
    local id = type(a) == "table" and type(a.itemKey) == "table" and a.itemKey.itemID or nil
    if type(id) == "number" and a.status ~= C.SOLD and type(a.quantity) == "number" then
      listed[id] = (listed[id] or 0) + a.quantity
    end
  end
  c.listed = listed
  c.listedAt = now
end

--- What this character has up on the auction house, and when that was read (nil: not yet). With
--- `now`, a read older than the longest auction (48 hours) is no read: {} and nil.
function Q.Listed(char, now)
  local c = charOf(char, false)
  if not c then return {}, nil end
  local at = tonumber(c.listedAt)
  if at and type(now) == "number" and now - at > C.LISTED_MAX_AGE then return {}, nil end
  return c.listed, c.listedAt
end

--- A finished cast: a counted recipe of that spell has one craft fewer, and leaves the queue at 0.
--- A restock target is untouched; what it holds says how far it is. True when an entry changed.
function Q.OnCraftSucceeded(char, spellID)
  local c = charOf(char, false)
  if not c or not Q.Writable() or type(spellID) ~= "number" then return false end
  local i = indexOf(c, spellID)
  local e = i and c.entries[i] or nil
  if not (e and type(e.count) == "number") then return false end
  e.count = e.count - 1
  if e.count <= 0 then table.remove(c.entries, i) end
  return true
end

--- A count the player typed: a whole number 1 to 9999 (0 to 9999 with `allowZero`), else nil.
function Q.ParseCount(text, allowZero)
  if type(text) ~= "string" then return nil end
  local digits = text:match("^%s*(%d+)%s*$")
  local n = digits and tonumber(digits) or nil
  if not n or not isWhole(n, allowZero and 0 or 1) then return nil end
  return n
end
