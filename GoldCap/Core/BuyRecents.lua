local _, GC = ...

-- What the BUY tab's item box was last used for (UI/BuyAddBox.lua): the items added through it and
-- the names searched in it, newest first, each once, at most MAX. Kept in GoldCapDB.buyRecents, so
-- every character of the account sees the same row. An entry is { i = itemID, q = count, n = name }
-- for an item (the name the client gave it then, for a chip the client has not loaded yet) or
-- { s = text } for a search. Pure.
GC.BuyRecents = { MAX = 10 }

local function valid(entry)
  if type(entry) ~= "table" then return false end
  if entry.i ~= nil then return type(entry.i) == "number" and entry.i > 0 end
  return type(entry.s) == "string" and entry.s:match("%S") ~= nil
end

-- Two entries are the same when they name the same item, or the same search as Core/NameMatch.lua
-- compares names: "Linen" and "linen " are one search.
local function key(entry)
  if entry.i ~= nil then return "i:" .. entry.i end
  return "s:" .. GC.NameMatch.Fold(entry.s)
end

--- `list` with `entry` in front and its older twin gone, cut to `max` (MAX). A new list; an entry
--- that is neither an item nor a search leaves the list as it was, and anything else in it that is
--- neither is dropped.
function GC.BuyRecents.Push(list, entry, max)
  max = max or GC.BuyRecents.MAX
  local out, seen = {}, {}
  if valid(entry) then
    out[1] = entry
    seen[key(entry)] = true
  end
  for _, old in ipairs(type(list) == "table" and list or {}) do
    if #out >= max then break end
    if valid(old) and not seen[key(old)] then
      seen[key(old)] = true
      out[#out + 1] = old
    end
  end
  return out
end
