-- Player price caps: the alert-group ceilings the site ships through the companion
-- (GoldCap_AppRuns.caps / .groups, see Core/AppRuns.lua for the file's contract). This
-- module only holds and judges them; polling is KeyPoll's and the book pass's, verification
-- the drill queue's, buying onDialogPrimaryClick's. A cap is the player's own price, so a
-- capped item needs no realm reference to be watched.
local _, GC = ...
GC.Caps = {}

local caps, order, generatedAt = {}, {}, nil

local function num(v) return type(v) == "number" and v == v and v or nil end

function GC.Caps.Adopt()
  local raw = _G.GoldCap_AppRuns
  local next_caps, next_order = {}, {}
  local changed = false
  if type(raw) == "table" and (raw.v == 1 or raw.v == 2 or raw.v == 3) and type(raw.caps) == "table" then
    local groups = type(raw.groups) == "table" and raw.groups or {}
    for _, entry in ipairs(raw.caps) do
      if type(entry) == "table" then
        local i, c = num(entry.i), num(entry.c)
        if i and i > 0 and c and c > 0 and not next_caps[i] then
          local g = num(entry.g)
          next_caps[i] = {
            c = math.floor(c),
            l = math.max(0, math.floor(num(entry.l) or 0)),
            group = g and type(groups[g]) == "string" and groups[g] or nil,
            manual = entry.m == true,
          }
          next_order[#next_order + 1] = i
        end
      end
    end
    generatedAt = num(raw.generatedAt)
  else
    generatedAt = nil
  end
  -- Changed when any id came or went or any field moved; callers rebuild targets on true.
  if #next_order ~= #order then changed = true end
  if not changed then
    for id, cap in pairs(next_caps) do
      local old = caps[id]
      if not old or old.c ~= cap.c or old.l ~= cap.l or old.group ~= cap.group or old.manual ~= cap.manual then
        changed = true; break
      end
    end
  end
  caps, order = next_caps, next_order
  return changed
end

function GC.Caps.Count() return #order end
function GC.Caps.For(itemID) return caps[itemID] end
function GC.Caps.Targets()
  local out = {}
  for i = 1, #order do out[i] = order[i] end
  return out
end
function GC.Caps.GeneratedAt() return generatedAt end
-- KeyPoll fires on floor < trigger, so "at or under the cap" is trigger = cap + 1.
function GC.Caps.TriggerFor(itemID)
  local cap = caps[itemID]
  return cap and (cap.c + 1) or nil
end

-- Commodity caps off the book pass (Core/BookPass.lua's `book`: itemID -> { floor, qty, … }).
-- A capped commodity is excluded from the key poll's own target set on purpose
-- (UI/SniperFrame.lua's `_KeyTargetIds`) -- the book pass is what actually sees a commodity
-- floor, so this is the only place these hits come from. Pure, caps order, and silent about
-- anything the book pass has not (yet) reported: a realm item (isCommodity false), an over-cap
-- floor, and a capped commodity the book has no row for at all are all just not in the output.
function GC.Caps.BookHits(book, isCommodity)
  local hits = {}
  for i = 1, #order do
    local itemID = order[i]
    if isCommodity(itemID) then
      local cap = caps[itemID]
      local booked = book[itemID]
      if cap and booked and booked.floor and booked.floor <= cap.c then
        hits[#hits + 1] = { itemID = itemID, floor = booked.floor, estProfit = cap.c - booked.floor }
      end
    end
  end
  return hits
end
