local _, GC = ...

-- Item names as a player types them: case-blind in the client's own language, and accent-blind
-- for the Latin letters, so "LINEN" finds "Linen Cloth", "льнян" finds "Плотные льняные бинты" and
-- "eclat" finds "Éclat". Lua's string.lower knows the ASCII letters only, and a UTF-8 letter is
-- two or three bytes it would read one by one, so every other letter goes through a table of its
-- own here: Latin-1 (the accented letters of the European clients), Latin Extended's Œ and Ÿ, and
-- Cyrillic, Ukrainian і ї є ґ included. Ё reads as Е, the way Russian is typed. Pure: the BUY tab's
-- item box (UI/BuyAddBox.lua) and the list's own search (Core/BuyView.lua's Matches) ask it.
GC.NameMatch = {}

local function utf8(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

local ASCII = {}
for b = 65, 90 do ASCII[string.char(b)] = string.char(b + 32) end

-- One letter (as its UTF-8 bytes) -> what it is compared as. A letter not in here is itself.
local FOLD = {}
-- Latin-1 capitals to their small letters (× at U+00D7 is no letter), then every accented small
-- letter -- and so every capital -- to its plain one. Æ Ð Þ only lose their case; ß stays.
for cp = 0xC0, 0xDE do
  if cp ~= 0xD7 then FOLD[utf8(cp)] = utf8(cp + 0x20) end
end
local PLAIN = {
  a = { 0xE0, 0xE5 }, c = { 0xE7, 0xE7 }, e = { 0xE8, 0xEB }, i = { 0xEC, 0xEF }, n = { 0xF1, 0xF1 },
  o = { 0xF2, 0xF6 }, u = { 0xF9, 0xFC }, y = { 0xFD, 0xFD },
}
for plain, range in pairs(PLAIN) do
  for cp = range[1], range[2] do
    FOLD[utf8(cp)] = plain
    FOLD[utf8(cp - 0x20)] = plain
  end
end
FOLD[utf8(0xF8)], FOLD[utf8(0xD8)] = "o", "o" -- ø Ø
FOLD[utf8(0xFF)], FOLD[utf8(0x178)] = "y", "y" -- ÿ Ÿ
FOLD[utf8(0x152)] = utf8(0x153) -- Œ œ
-- Cyrillic: А..Я -> а..я, Ѐ..Џ (Ё, Є, І, Ї among them) -> ѐ..џ, Ґ -> ґ; then ё -> е.
for cp = 0x410, 0x42F do FOLD[utf8(cp)] = utf8(cp + 0x20) end
for cp = 0x400, 0x40F do FOLD[utf8(cp)] = utf8(cp + 0x50) end
FOLD[utf8(0x490)] = utf8(0x491)
FOLD[utf8(0x401)], FOLD[utf8(0x451)] = utf8(0x435), utf8(0x435)

--- `s` as it is compared: every letter above in its small, plain form, runs of white space as one
--- space, none at either end. "" for anything that is not a string.
function GC.NameMatch.Fold(s)
  if type(s) ~= "string" then return "" end
  s = s:gsub("[A-Z]", ASCII):gsub("[\192-\244][\128-\191]+", FOLD)
  return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Where a word starts: the name's first letter, or one after a space or punctuation.
local BOUNDARY = { [" "] = true, ["-"] = true, ["("] = true, ["["] = true, ["'"] = true, [","] = true,
  [":"] = true, ["/"] = true, ["."] = true, ['"'] = true }

local function rankOf(folded, q)
  if folded:sub(1, #q) == q then return 0 end
  local from = 1
  while true do
    local at = folded:find(q, from, true)
    if not at then return 2 end
    if BOUNDARY[folded:sub(at - 1, at - 1)] then return 1 end
    from = at + 1
  end
end

--- The entries whose name holds every word of `query`, best first, one per item, at most `max`:
--- a name that starts with the query, then one with a word that starts with it, then the rest --
--- shorter names first among those, then by name. `entries` are { itemID, name, folded? }
--- (`folded` saves folding the name again); the answer is those same tables.
function GC.NameMatch.Find(entries, query, max)
  local q = GC.NameMatch.Fold(query)
  local out = {}
  if q == "" then return out end
  local words = {}
  for word in q:gmatch("%S+") do words[#words + 1] = word end
  local best = {}
  for _, entry in ipairs(entries or {}) do
    local id = entry.itemID
    local folded = entry.folded or GC.NameMatch.Fold(entry.name)
    local every = id ~= nil and folded ~= ""
    for _, word in ipairs(words) do
      if not every then break end
      every = folded:find(word, 1, true) ~= nil
    end
    if every then
      local rank = rankOf(folded, q)
      local have = best[id]
      if not have or rank < have.rank or (rank == have.rank and #folded < #have.folded) then
        best[id] = { rank = rank, folded = folded, entry = entry }
      end
    end
  end
  local found = {}
  for _, hit in pairs(best) do found[#found + 1] = hit end
  table.sort(found, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if #a.folded ~= #b.folded then return #a.folded < #b.folded end
    if a.folded ~= b.folded then return a.folded < b.folded end
    return a.entry.itemID < b.entry.itemID
  end)
  for i = 1, math.min(#found, max or #found) do out[i] = found[i].entry end
  return out
end
