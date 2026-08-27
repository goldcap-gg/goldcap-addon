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
