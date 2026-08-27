local _, GC = ...

GC.Util = {}

function GC.Util.ApplyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      GC.Util.ApplyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function GC.Util.FormatAge(seconds)
  if seconds < 3600 then return "<1h" end
  if seconds < 48 * 3600 then return math.floor(seconds / 3600) .. "h" end
  return math.floor(seconds / 86400) .. "d"
end

local function finitePositive(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge and value > 0
end

-- How long the shelf lasts at the rate the market is clearing it, for the tooltip's depth
-- line. Floors to whole days the way FormatAge does, so a number the player reads never
-- rounds up into a promise the market has not made. Past 99 days the figure stops carrying
-- information -- "400d" and "99d+" say the same thing to a seller, and the short one does
-- not stretch the tooltip. nil means the question has no answer, either because nothing is
-- listed or because there are no sales to divide by; the caller then prints the stock alone
-- rather than inventing a rate.
function GC.Util.FormatSupplyDays(qty, soldPerDay)
  if not finitePositive(qty) or not finitePositive(soldPerDay) then return nil end
  local days = qty / soldPerDay
  if days < 1 then return "<1d" end
  local whole = math.floor(days)
  if whole > 99 then return "99d+" end
  return whole .. "d"
end

-- How long ago, for a figure the player is reading while deciding. FormatAge above answers
-- a coarser question ("is my whole snapshot stale") and collapses everything under an hour
-- to "<1h" -- which is exactly the resolution that matters on a live check. The Sniper's
-- check panel printed a raw "3384s" instead; this is what it should have been saying.
--
-- Floors at every step: a freshness figure that rounds UP claims the data is older than it
-- is, which is harmless, while rounding down would claim it is fresher, which is not.
function GC.Util.FormatElapsed(seconds)
  if type(seconds) ~= "number" or seconds ~= seconds
      or seconds == math.huge or seconds == -math.huge or seconds < 0 then return nil end
  if seconds < 60 then return math.floor(seconds) .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  if seconds < 48 * 3600 then return math.floor(seconds / 3600) .. "h" end
  return math.floor(seconds / 86400) .. "d"
end

-- A count, in the width a panel cell actually has. Small numbers stay exact because they
-- carry the decision -- three sales a day is the difference between a trade and a trap --
-- while a region-wide commodity's turnover does not: the check panel was printing
-- "856146.0", where both the trailing .0 and the last five digits were noise.
function GC.Util.FormatCount(value)
  if type(value) ~= "number" or value ~= value
      or value == math.huge or value == -math.huge or value < 0 then return nil end
  if value < 1000 then return tostring(math.floor(value + 0.5)) end
  if value < 1000000 then
    local thousands = value / 1000
    if thousands < 10 then return ("%.1fk"):format(math.floor(thousands * 10) / 10) end
    return math.floor(thousands + 0.5) .. "k"
  end
  local millions = value / 1000000
  if millions < 10 then return ("%.1fM"):format(math.floor(millions * 10) / 10) end
  return math.floor(millions + 0.5) .. "M"
end
