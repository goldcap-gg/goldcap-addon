local _, GC = ...

GC.QuoteCache = {}

GC.QuoteCache.MAX_AGE_SECONDS = 10

local MAX_EXACT = 9007199254740991

local function exactNonnegative(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value) and value >= 0 and value <= MAX_EXACT
end

function GC.QuoteCache.Set(cache, itemID, unit, now)
  if type(unit) ~= "number" or unit <= 0 then
    cache[itemID] = nil
    return
  end
  cache[itemID] = { unit = unit, at = now }
end

function GC.QuoteCache.Latest(cache, itemID)
  return type(cache) == "table" and cache[itemID] or nil
end

local function validEntry(cache, itemID, now)
  local quote = GC.QuoteCache.Latest(cache, itemID)
  if type(quote) ~= "table" or not exactNonnegative(now) or not exactNonnegative(quote.unit) or quote.unit <= 0
      or not exactNonnegative(quote.at) or quote.at > now then return nil end
  return quote
end

function GC.QuoteCache.Fresh(cache, itemID, now)
  local quote = validEntry(cache, itemID, now)
  if not quote or quote.stale == true or quote.fresh == false
      or now - quote.at > GC.QuoteCache.MAX_AGE_SECONDS then return nil end
  return quote
end

function GC.QuoteCache.Age(cache, itemID, now)
  local quote = validEntry(cache, itemID, now)
  return quote and math.max(0, now - quote.at) or nil
end

function GC.QuoteCache.Get(cache, itemID, now)
  local quote = GC.QuoteCache.Fresh(cache, itemID, now)
  return quote and quote.unit or nil
end

function GC.QuoteCache.Clear(cache)
  for itemID in pairs(cache) do
    cache[itemID] = nil
  end
end
